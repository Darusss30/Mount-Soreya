-- ==============================================================================
-- DARUS HUB | Based on UBEYHUB.lua by UbeyDev
-- ==============================================================================

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local Stats = game:GetService("Stats")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Darus Hub harus dijalankan di sisi pemain.")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Session-local state and synchronous shutdown on rerun (including the former V3 build).
for _, name in ipairs({"DarusHub", "DarusHubCollect"}) do
	local previous = PlayerGui:FindFirstChild(name)
	if previous then
		local shutdown = previous:FindFirstChild("DarusShutdown")
		if shutdown and shutdown:IsA("BindableFunction") then pcall(function() shutdown:Invoke() end) end
		previous:Destroy()
	end
end
local State = {}
local App = {running = true, threads = {}, connections = {}, snapshots = {}, owned = setmetatable({}, {__mode = "k"}),
	dragSuppressed = {}, pending = {}, toggles = {}, fishingEpoch = 0, lastError = {}}
local Gui = Instance.new("ScreenGui", PlayerGui)
Gui.Name = "DarusHub"
Gui.ResetOnSpawn = false

function App.Report(message)
	if not App.running then return end
	if App.status then App.status.Text = message end
	if not App.lastError[message] or os.clock() - App.lastError[message] > 10 then
		App.lastError[message] = os.clock()
		warn("[Darus Hub] " .. message)
	end
end

function App.Spawn(callback, ...)
	if not App.running then return nil end
	local args = table.pack(...)
	local thread
	thread = task.defer(function()
		if App.running then
			local ok, err = pcall(callback, table.unpack(args, 1, args.n))
			if not ok then App.Report(tostring(err)) end
		end
		App.threads[thread] = nil
	end)
	App.threads[thread] = true
	return thread
end

function App.Connect(signal, callback)
	for connection in pairs(App.connections) do
		if not connection.Connected then App.connections[connection] = nil end
	end
	local connection = signal:Connect(function(...)
		if App.running then App.Spawn(callback, ...) end
	end)
	App.connections[connection] = true
	return connection
end

function App.Wait(seconds, predicate)
	local deadline = os.clock() + seconds
	while App.running and (not predicate or predicate()) do
		local remaining = deadline - os.clock()
		if remaining <= 0 then return true end
		task.wait(math.min(remaining, 0.1))
	end
	return false
end

function App.Number(value, default, minimum, maximum)
	local number = tonumber(value)
	if not number or number ~= number or math.abs(number) == math.huge then return default end
	return math.clamp(number, minimum, maximum)
end

function App.Set(group, object, property, value)
	if not App.running or not object then return end
	App.snapshots[group] = App.snapshots[group] or setmetatable({}, {__mode = "k"})
	local objects = App.snapshots[group]
	objects[object] = objects[object] or {}
	if objects[object][property] == nil then objects[object][property] = object[property] end
	object[property] = value
end

function App.Restore(group)
	for object, properties in pairs(App.snapshots[group] or {}) do
		pcall(function() for property, value in pairs(properties) do object[property] = value end end)
	end
	App.snapshots[group] = nil
end

function App.Cleanup()
	if not App.running then return end
	App.running = false
	if App.tween then App.tween:Cancel(); App.tween = nil end
	for connection in pairs(App.connections) do connection:Disconnect() end
	for thread in pairs(App.threads) do
		if thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then pcall(task.cancel, thread) end
	end
	for group in pairs(App.snapshots) do App.Restore(group) end
	for object in pairs(App.owned) do pcall(function() object:Destroy() end) end
end

local shutdown = Instance.new("BindableFunction", Gui)
shutdown.Name = "DarusShutdown"
shutdown.OnInvoke = App.Cleanup
App.connections[Gui.Destroying:Connect(App.Cleanup)] = true

-- A timed-out InvokeServer may still be executing on the server. Keep its lock
-- until it returns; callers must not accumulate duplicate requests.
function App.Invoke(remote, ...)
	if not remote or not remote:IsA("RemoteFunction") then
		App.Report("RemoteFunction tidak tersedia pada game ini.")
		return nil
	end
	if App.pending[remote] then App.Report("Permintaan sebelumnya masih menunggu server."); return nil end
	local args = table.pack(...)
	local pending = {done = false}
	App.pending[remote] = pending
	App.Spawn(function()
		pending.result = table.pack(pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end))
		pending.done = true
		App.pending[remote] = nil
	end)
	App.Wait(10, function() return not pending.done end)
	if not pending.done then App.Report("Server belum merespons; permintaan tidak diulang."); return nil end
	if not pending.result[1] then App.Report("Permintaan gagal: " .. tostring(pending.result[2])); return nil end
	return table.unpack(pending.result, 2, pending.result.n)
end

------------------------------------------------------------------
-- CONFIGURATION & FILE SAVE SYSTEM
------------------------------------------------------------------
local CONFIG_FILE = "DarusHub_Config.json"

State.Config = {
	BiteDelay = "0.5",
	SelectedSpot = "Spot Mancing Jembatan",
	AutoSellTimer = "5",
	AntiAdminEnabled = false,
	TargetGroupId = 7019573,
	WebhookEnabled = false,
	WebhookUrl = ""
}

local function SaveConfig()
	if type(writefile) ~= "function" then App.Report("Penyimpanan file tidak tersedia di lingkungan ini."); return false end
	local data = table.clone(State.Config)
	for _, key in ipairs({"FavRarities", "FavMutations", "UnfavRarities", "UnfavMutations", "SpotLoopConfig"}) do data[key] = State[key] end
	local ok, err = pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(data)) end)
	if not ok then App.Report("Gagal menyimpan konfigurasi: " .. tostring(err)) end
	return ok
end

local function LoadConfig()
	if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
	local ok, data = pcall(function()
		if isfile(CONFIG_FILE) then return HttpService:JSONDecode(readfile(CONFIG_FILE)) end
		return nil
	end)
	if not ok then App.Report("Konfigurasi tidak terbaca; memakai nilai awal."); return end
	if type(data) ~= "table" then return end
	State.Config.BiteDelay = tostring(App.Number(data.BiteDelay, 0.5, 0, 30))
	State.Config.AutoSellTimer = tostring(App.Number(data.AutoSellTimer, 5, 0.1, 1440))
	if table.find({"Spot Mancing Jembatan", "Spot Mancing Core", "Spot Mancing Ikan Anomali"}, data.SelectedSpot) then State.Config.SelectedSpot = data.SelectedSpot end
	State.Config.AntiAdminEnabled = data.AntiAdminEnabled == true
	State.Config.TargetGroupId = math.floor(App.Number(data.TargetGroupId, 7019573, 1, 1e12))
	State.Config.WebhookEnabled = false
	State.Config.WebhookUrl = type(data.WebhookUrl) == "string" and data.WebhookUrl or ""
	App.loadedConfig = data
end

local function ResetConfig()
	State.Config = {BiteDelay = "0.5", SelectedSpot = "Spot Mancing Jembatan", AutoSellTimer = "5",
		AntiAdminEnabled = false, TargetGroupId = 7019573, WebhookEnabled = false, WebhookUrl = ""}
	State.BiteDelayInput, State.AutoSellTimerInput = "0.5", "5"
	State.SelectedFishingSpot = State.Config.SelectedSpot
	State.CoreEventActive = false
	for key, defaults in pairs(App.filterDefaults or {}) do
		for name, value in pairs(defaults) do State[key][name] = value end
	end
	for _, config in pairs(State.SpotLoopConfig or {}) do config.Timer = "10"; config.Enabled = false end
	for _, toggle in pairs(App.toggles) do toggle:Set(false) end
	App.fishingEpoch += 1
	if App.RefreshConfig then App.RefreshConfig() end
	return SaveConfig()
end

LoadConfig()

------------------------------------------------------------------
-- DISCORD WEBHOOK SYSTEM (STRICT SECRET & FORGOTTEN ONLY)
------------------------------------------------------------------
function App.PostWebhook(payload)
	local url = State.Config.WebhookUrl
	if type(url) ~= "string" or not url:match("^https://discord%.com/api/webhooks/%d+/[%w_-]+$") then
		App.Report("URL webhook Discord tidak valid."); return false
	end
	local requestFunc = (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request)
	if type(requestFunc) ~= "function" then App.Report("HTTP request tidak tersedia."); return false end
	payload.allowed_mentions = {parse = {}}
	local ok, response = pcall(requestFunc, {Url=url, Method="POST", Headers={["Content-Type"]="application/json"}, Body=HttpService:JSONEncode(payload)})
	local code = ok and type(response) == "table" and tonumber(response.StatusCode or response.Status)
	if not code or code < 200 or code >= 300 then App.Report("Webhook gagal atau tidak mendapat respons sukses."); return false end
	return true
end
local function SendFilteredWebhook(fishName, fishRarity, fishMutation, fishGrade, fishWeight, fishChance)
	pcall(function()
		if not State.Config.WebhookEnabled then return end
		local url = State.Config.WebhookUrl
		if not url or url == "" or not url:match("^https://discord%.com/api/webhooks/%d+/[%w_-]+$") then return end

		local targetName = tostring(fishName or "Unknown Fish")
		local targetRarity = tostring(fishRarity or "Common")
		local targetMutation = tostring(fishMutation or "Normal")
		local targetGrade = tostring(fishGrade or "N/A")
		local targetWeight = tostring(fishWeight or "0") .. " kg"
		local targetChance = tostring(fishChance or "N/A")

		local targetRarityLower = string.lower(targetRarity)

		if targetRarityLower == "secret" or targetRarityLower == "forgotten" then
			local requestFunc = (syn and syn.request) or (http and http.request) or request or (fluxus and fluxus.request)
			if not requestFunc then return end

			local data = {
				["content"] = "🎣 **FISH SECRET / FORGOTTEN CATCH!**",
["allowed_mentions"] = {parse = {}},
				["embeds"] = {
					{
						["title"] = "👑 Darus Hub - Secret & Forgotten Tracker!",
						["description"] = "Pemain **" .. LocalPlayer.Name .. "** baru saja mendapatkan ikan langka!",
						["color"] = 16711935,
						["fields"] = {
							{ ["name"] = "🐟 Nama Ikan", ["value"] = targetName, ["inline"] = true },
							{ ["name"] = "⭐ Rarity", ["value"] = targetRarity, ["inline"] = true },
							{ ["name"] = "🧬 Mutasi", ["value"] = targetMutation, ["inline"] = true },
							{ ["name"] = "🏆 Grade", ["value"] = targetGrade, ["inline"] = true },
							{ ["name"] = "⚖️ Berat (Weight)", ["value"] = targetWeight, ["inline"] = true },
							{ ["name"] = "🎲 Chance", ["value"] = targetChance, ["inline"] = true }
						},
						["footer"] = { ["text"] = "Darus Hub • Secret & Forgotten Notification" },
						["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
					}
				}
			}

			App.PostWebhook(data)
		end
	end)
end

------------------------------------------------------------------
-- REAL-TIME CATCH MONITOR
------------------------------------------------------------------
local hookedRemotes = setmetatable({}, {__mode = "k"})

local function ProcessNotifyClient(actionType, fishDataArg)
	if actionType == "GotFish" and type(fishDataArg) == "table" then
		pcall(function()
			local name = fishDataArg.baseName or fishDataArg.originalName or "Unknown Fish"
			local rarity = fishDataArg.rarity or "Common"
			local mutation = fishDataArg.mutation or "Normal"
			local grade = fishDataArg.grade or "N/A"
			local weight = fishDataArg.weight or "0"
			local chance = fishDataArg.chance or "N/A"

			if name ~= "Unknown Fish" and name ~= "" then
				SendFilteredWebhook(name, rarity, mutation, grade, weight, chance)
			end
		end)
	end
end

local function AttachNotifyHook(remote)
	if remote and remote:IsA("RemoteEvent") and not hookedRemotes[remote] then
		hookedRemotes[remote] = true
		App.Connect(remote.OnClientEvent, ProcessNotifyClient)
	end
end

local function ListenToFishCatch()
	pcall(function()
		for _, v in ipairs(ReplicatedStorage:GetDescendants()) do
			if v:IsA("RemoteEvent") and v.Name == "NotifyClient" then
				AttachNotifyHook(v)
			end
		end

		local function ScanCharacter(char)
			if not char then return end
			for _, v in ipairs(char:GetDescendants()) do
				if v:IsA("RemoteEvent") and v.Name == "NotifyClient" then
					AttachNotifyHook(v)
				end
			end
			App.Connect(char.DescendantAdded, function(v)
				if v:IsA("RemoteEvent") and v.Name == "NotifyClient" then
					AttachNotifyHook(v)
				end
			end)
		end

		if LocalPlayer.Character then ScanCharacter(LocalPlayer.Character) end
		App.Connect(LocalPlayer.CharacterAdded, ScanCharacter)

		App.Connect(ReplicatedStorage.DescendantAdded, function(v)
			if v:IsA("RemoteEvent") and v.Name == "NotifyClient" then
				AttachNotifyHook(v)
			end
		end)
	end)
end

App.Spawn(function()
	task.wait(1)
	ListenToFishCatch()
end)

------------------------------------------------------------------
-- AUTO RECONNECT
------------------------------------------------------------------
App.Spawn(function()
	pcall(function()
		App.Connect(CoreGui.DescendantAdded, function(child)
			if not App.reconnecting and (child.Name == "ErrorPrompt" or child.Name == "DisconnectPrompt") then
				App.reconnecting = true
				task.wait(1)
				pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
			end
		end)
	end)
end)

-- GLOBAL STATES
State.AutoFishingEventRunning = false
State.BiteDelayInput = State.Config.BiteDelay
State.SelectedFishingSpot = State.Config.SelectedSpot
State.AutoSellRunning = false
State.AutoSellTimerInput = State.Config.AutoSellTimer
State.AutoGalatamaRunning = false
State.AutoSummitRunning = false
State.AntiAFKRunning = false
State.HideNameRunning = false
State.FakeNameInput = "DARUS HUB"
State.CurrentSelectedHalo = nil
State.AutoDetectCoreEvent = false

State.LoopSpotEnabled = false
State.SpotLoopConfig = {
	["Spot Mancing Jembatan"] = { Enabled = false, Timer = "10" },
	["Spot Mancing Core"] = { Enabled = false, Timer = "10" },
	["Spot Mancing Ikan Anomali"] = { Enabled = false, Timer = "10" }
}

State.AutoFavoriteRunning = false
State.FavRarities = {
	["Common"] = false, ["UnCommon"] = false, ["Rare"] = false, ["Epic"] = false,
	["Legendary"] = true, ["Mythical"] = true, ["Secret"] = true, ["Forgotten"] = true
}
State.FavMutations = {
	["Galaxy"] = false, ["Corrupt"] = false, ["Gemstone"] = false, ["Ghost"] = false,
	["Lightning"] = false, ["Fairy Dust"] = true, ["Gold"] = false, ["Midnight"] = false,
	["Radioactive"] = false, ["Stone"] = false, ["Holographic"] = false, ["Albino"] = false,
	["Sandy"] = false, ["Cosmic"] = false, ["Normal"] = false, ["Elemental"] = false,
	["Festive"] = false, ["8-Bit"] = false, ["Bloodmoon"] = false, ["Abyssal"] = false,
	["Strawberry"] = false, ["Void"] = false, ["Cupid"] = false
}

State.UnfavRarities = {
	["Common"] = false, ["UnCommon"] = false, ["Rare"] = false, ["Epic"] = false,
	["Legendary"] = false, ["Mythical"] = false, ["Secret"] = false, ["Forgotten"] = false
}
State.UnfavMutations = {
	["Galaxy"] = false, ["Corrupt"] = false, ["Gemstone"] = false, ["Ghost"] = false,
	["Lightning"] = false, ["Fairy Dust"] = false, ["Gold"] = false, ["Midnight"] = false,
	["Radioactive"] = false, ["Stone"] = false, ["Holographic"] = false, ["Albino"] = false,
	["Sandy"] = false, ["Cosmic"] = false, ["Normal"] = false, ["Elemental"] = false,
	["Festive"] = false, ["8-Bit"] = false, ["Bloodmoon"] = false, ["Abyssal"] = false,
	["Strawberry"] = false, ["Void"] = false, ["Cupid"] = false
}

local FishingSpots = {
	["Spot Mancing Jembatan"] = CFrame.new(-6783.74756, 1322.81006, -9757.34473, 0.0899723172, -9.34088291e-08, 0.995944262, 1.76120434e-08, 1, 9.21981638e-08, -0.995944262, 9.24533072e-09, 0.0899723172),
	["Spot Mancing Core"] = CFrame.new(-9069.33887, 1250.32092, -6510.3374, 0.99812746, -7.96398965e-08, -0.0611686334, 8.05492206e-08, 1, 1.24000188e-08, 0.0611686334, -1.73038845e-08, 0.99812746),
	["Spot Mancing Ikan Anomali"] = CFrame.new(-8199.52832, 1238.83752, -6278.13135, -0.999144316, 1.1644854e-08, -0.0413601957, 1.63464247e-08, 1, -1.13335595e-07, 0.0413601957, -1.13914709e-07, -0.999144316)
}

local NpcSellCFrame = CFrame.new(-6668.01416, 1312.69983, -9965.2998, 0.999977231, 1.08366018e-08, -0.00675115408, -1.09201403e-08, 1, -1.2337189e-08, 0.00675115408, 1.24106316e-08, 0.999977231)

-- Merge only known saved filter entries into the local state.
App.filterDefaults = {}
for _, key in ipairs({"FavRarities", "FavMutations", "UnfavRarities", "UnfavMutations"}) do
	App.filterDefaults[key] = table.clone(State[key])
	local saved = App.loadedConfig and App.loadedConfig[key]
	if type(saved) == "table" then
		for name in pairs(State[key]) do if type(saved[name]) == "boolean" then State[key][name] = saved[name] end end
	end
end
for name, config in pairs(State.SpotLoopConfig) do
	local saved = App.loadedConfig and App.loadedConfig.SpotLoopConfig
	saved = type(saved) == "table" and saved[name]
	if type(saved) == "table" then
		config.Timer = tostring(App.Number(saved.Timer, 10, 0.1, 1440))
		config.Enabled = saved.Enabled == true
	end
end
App.loadedConfig = nil

local function OptimizeRodSettings(rod)
	local mechanics = rod and rod:FindFirstChild("Mechanics")
	local settings = mechanics and mechanics:FindFirstChild("Settings")
	if not settings then return end
	local timeSetting = settings:FindFirstChild("Time_before_getfish")
	local miniGame = settings:FindFirstChild("EnableMiniGame")
	if timeSetting and (timeSetting:IsA("NumberValue") or timeSetting:IsA("IntValue")) then App.Set("rod", timeSetting, "Value", 0.05) end
	if miniGame and miniGame:IsA("BoolValue") then App.Set("rod", miniGame, "Value", false) end
end

function App.Teleport(cf)
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not cf then return false end
	App.fishingEpoch += 1
	root.CFrame = cf
	return true
end

local function RunAutoFishCycle(remoteFolder, rod)
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local epoch = App.fishingEpoch
	local function active()
		return App.running and State.AutoFishingEventRunning and not State.Selling and not State.AutoSummitRunning
			and App.fishingEpoch == epoch and LocalPlayer.Character == character and root and root.Parent == character
			and rod.Parent == character
	end
	local cast = remoteFolder:FindFirstChild("CastEvent")
	local notify = remoteFolder:FindFirstChild("NotifyClient")
	local miniGame = remoteFolder:FindFirstChild("MiniGame")
	if not cast or not cast:IsA("RemoteEvent") or not notify or not notify:IsA("RemoteEvent") or not miniGame or not miniGame:IsA("RemoteEvent") then
		App.Report("Remote pancing tidak lengkap atau tidak kompatibel.")
		return
	end
	if not active() then return end
	local hooked = false
	-- Subscribe first: a fast server can answer during the cast itself.
	local connection = App.Connect(notify.OnClientEvent, function(action)
		if action == "Bite" or action == "Hook" then hooked = true end
	end)
	local ok, err = pcall(function()
		OptimizeRodSettings(rod)
		cast:FireServer(true)
		if not App.Wait(0.05, active) then return end
		cast:FireServer(false, 100, root.CFrame.LookVector)
		App.Wait(8, function() return active() and not hooked end)
		if not hooked or not active() then return end
		if not App.Wait(App.Number(State.BiteDelayInput, 0.5, 0, 30), active) then return end
		local marker = remoteFolder:FindFirstChild("TandaSeruBersama")
		if marker and marker:IsA("RemoteEvent") then
			local color = Color3.fromRGB(23, 255, 151)
			marker:FireServer(color, Color3.fromRGB(20,20,20), ColorSequence.new({ColorSequenceKeypoint.new(0,color), ColorSequenceKeypoint.new(1,color)}), 1.5)
		end
		if not App.Wait(0.1, active) then return end
		miniGame:FireServer(true)
		App.Wait(0.3, active)
	end)
	connection:Disconnect()
	App.connections[connection] = nil
	if not ok then App.Report("Pancing gagal: " .. tostring(err)) end
end

local function TriggerSellToNpc()
	if State.Selling or State.AutoSummitRunning then return end
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local folder = ReplicatedStorage:FindFirstChild("Remote")
	local mancing = folder and folder:FindFirstChild("Mancing")
	local sell = mancing and mancing:FindFirstChild("JualSemua")
	if not root or not sell or not sell:IsA("RemoteFunction") then App.Report("NPC jual/karakter belum tersedia."); return end
	if App.pending[sell] then return end
	State.Selling = true
	App.fishingEpoch += 1
	local ok, err = pcall(function()
		App.Set("sellPosition",root,"CFrame",NpcSellCFrame + Vector3.new(0,5,0))
		if App.Wait(0.8, function() return State.AutoSellRunning and LocalPlayer.Character == character end) then App.Invoke(sell) end
	end)
	-- Always return, including when fishing is OFF or the request errors.
	if App.running then App.Restore("sellPosition") end
	State.Selling = false
	if not ok then App.Report("Jual ikan gagal: " .. tostring(err)) end
end

local function GetInventoryRemote()
	local repStorage = game:GetService("ReplicatedStorage")
	return repStorage:FindFirstChild("Remote")
		and repStorage.Remote:FindFirstChild("Mancing")
		and repStorage.Remote.Mancing:FindFirstChild("TandaiFavorit")
end

local function GetServerFishData()
	local fishDataList = {}
	pcall(function()
		local repStorage = game:GetService("ReplicatedStorage")
		local ambilSemuaRemote = repStorage:FindFirstChild("Remote")
			and repStorage.Remote:FindFirstChild("Inventaris")
			and repStorage.Remote.Inventaris:FindFirstChild("AmbilSemua")

		if ambilSemuaRemote then
			local result = {App.Invoke(ambilSemuaRemote)}
			local data = result[1]
			if type(data) == "table" then
				for _, fish in ipairs(data) do
					if type(fish) == "table" and (fish.uid or fish.UUID) then
						table.insert(fishDataList, {
							UUID = tostring(fish.uid or fish.UUID),
							Name = tostring(fish.nama or fish.Name or ""),
							Rarity = tostring(fish.rarity or fish.Rarity or ""),
							Mutation = tostring(fish.mutasi or fish.Mutation or ""),
							IsFavorited = fish.favorit or fish.IsFavorit or fish.IsFavorite or false
						})
					end
				end
			end
		end
	end)
	return fishDataList
end

function App.MatchesFish(fish, rarities, mutations)
	if rarities[fish.Rarity] then return true end
	for name, enabled in pairs(rarities) do if enabled and name:lower() == fish.Rarity:lower() then return true end end
	for name, enabled in pairs(mutations) do
		if enabled and fish.Mutation:lower():find(name:lower(),1,true) then return true end
	end
	return false
end

local function ProcessAutoFavorite()
	if App.favoriteBusy then return end
	App.favoriteBusy = true
	local ok, err = pcall(function()
		local remote = GetInventoryRemote()
		if not remote or not remote:IsA("RemoteEvent") then return end
		for _, fish in ipairs(GetServerFishData()) do
			if not State.AutoFavoriteRunning or not App.running then break end
			if not fish.IsFavorited and App.MatchesFish(fish,State.FavRarities,State.FavMutations) then
				remote:FireServer(fish.UUID,true)
				if not App.Wait(0.12,function() return State.AutoFavoriteRunning end) then break end
			end
		end
	end)
	App.favoriteBusy = false
	if not ok then App.Report("Favorite gagal: " .. tostring(err)) end
end
App.Spawn(function()
	while App.Wait(2.5) do if State.AutoFavoriteRunning then ProcessAutoFavorite() end end
end)

function App.Unfavorite(all)
	App.toggles["AUTO FAVORITE"]:Set(false)
	if App.unfavoriteBusy then return end
	App.unfavoriteBusy = true
	App.Spawn(function()
		App.Wait(10,function() return App.favoriteBusy end)
		if App.favoriteBusy then App.unfavoriteBusy = false; return end
		App.favoriteBusy = true
		local ok, err = pcall(function()
			local remote = GetInventoryRemote()
			if not remote or not remote:IsA("RemoteEvent") then App.Report("Remote favorite belum tersedia."); return end
			for _, fish in ipairs(GetServerFishData()) do
				if not App.running then break end
				if fish.IsFavorited and (all or App.MatchesFish(fish,State.UnfavRarities,State.UnfavMutations)) then
					remote:FireServer(fish.UUID,false)
					if not App.Wait(0.08) then break end
				end
			end
		end)
		App.favoriteBusy, App.unfavoriteBusy = false, false
		if not ok then App.Report("Unfavorite gagal: " .. tostring(err)) end
	end)
end
local function UnfavoriteAllFish() App.Unfavorite(true) end
local function UnfavoriteByFilter() App.Unfavorite(false) end

local function MakeDraggable(guiObject, handleObject)
	handleObject = handleObject or guiObject
	local dragInput, dragStart, startPos, moved
	App.Connect(handleObject.InputBegan, function(input)
		if dragInput then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragInput, dragStart, startPos, moved = input, input.Position, guiObject.Position, false
		end
	end)
	App.Connect(UIS.InputChanged, function(input)
		if not dragInput then return end
		if input ~= dragInput and not (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
		local delta = input.Position - dragStart
		if delta.Magnitude > 6 then moved = true end
		if not moved then return end
		App.dragSuppressed[guiObject] = os.clock() + 0.3
		local viewport, size = Gui.AbsoluteSize, guiObject.AbsoluteSize
		local x = startPos.X.Scale * viewport.X + startPos.X.Offset + delta.X
		local y = startPos.Y.Scale * viewport.Y + startPos.Y.Offset + delta.Y
		guiObject.Position = UDim2.fromOffset(math.clamp(x, 0, math.max(0, viewport.X-size.X)), math.clamp(y, 0, math.max(0, viewport.Y-size.Y)))
	end)
	App.Connect(UIS.InputEnded, function(input)
		if input == dragInput or (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
			if moved then App.dragSuppressed[guiObject] = os.clock()+0.3 end
			dragInput = nil
		end
	end)
	App.Connect(UIS.WindowFocusReleased, function() dragInput = nil end)
end

----------------------------------------------------
-- MAIN HUB UI
----------------------------------------------------
local Main = Instance.new("Frame")
Main.Parent = Gui
Main.Visible = true
Main.Size = UDim2.new(0,550,0,320)
Main.Position = UDim2.new(0.5,-275,0.5,-160)
Main.BackgroundColor3 = Color3.fromRGB(20,20,25)
Main.ClipsDescendants = true
local DragHandle = Instance.new("Frame", Main)
DragHandle.Size = UDim2.new(1,-240,0,28)
DragHandle.BackgroundTransparency = 1
DragHandle.Active = true
MakeDraggable(Main, DragHandle)
local MainScale = Instance.new("UIScale", Main)
function App.FitScreen()
	local size = Gui.AbsoluteSize
	MainScale.Scale = math.min(1, math.max(0.1,(size.X-24)/550), math.max(0.1,(size.Y-24)/320))
	Main.Position = UDim2.fromOffset(math.max(0,(size.X-550*MainScale.Scale)/2), math.max(0,(size.Y-320*MainScale.Scale)/2))
end
App.Connect(Gui:GetPropertyChangedSignal("AbsoluteSize"), App.FitScreen)
App.FitScreen()

local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0,18)
mainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Parent = Main
MainStroke.Color = Color3.fromRGB(0,170,255)

local ControlsFrame = Instance.new("Frame")
ControlsFrame.Parent = Main
ControlsFrame.Size = UDim2.new(0, 65, 0, 30)
ControlsFrame.Position = UDim2.new(1, -70, 0, 5)
ControlsFrame.BackgroundTransparency = 1
ControlsFrame.ZIndex = 10

local ControlLayout = Instance.new("UIListLayout")
ControlLayout.Parent = ControlsFrame
ControlLayout.FillDirection = Enum.FillDirection.Horizontal
ControlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
ControlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
ControlLayout.Padding = UDim.new(0, 5)

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Parent = ControlsFrame
MinimizeBtn.Size = UDim2.new(0, 26, 0, 26)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
MinimizeBtn.Text = "-"
MinimizeBtn.TextColor3 = Color3.fromRGB(220, 220, 220)
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 18
MinimizeBtn.ZIndex = 11
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 6)
minCorner.Parent = MinimizeBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Parent = ControlsFrame
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.ZIndex = 11
local clsCorner = Instance.new("UICorner")
clsCorner.CornerRadius = UDim.new(0, 6)
clsCorner.Parent = CloseBtn

local PingLabel = Instance.new("TextLabel")
PingLabel.Parent = Main
PingLabel.Size = UDim2.new(0,150,0,25)
PingLabel.Position = UDim2.new(1,-225,0,7)
PingLabel.BackgroundTransparency = 1
PingLabel.Text = "Ping: Menghitung..."
PingLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
PingLabel.Font = Enum.Font.GothamBold
PingLabel.TextSize = 12
PingLabel.TextXAlignment = Enum.TextXAlignment.Right

App.Spawn(function()
	while App.running do
		pcall(function()
			local pingVal = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
			PingLabel.Text = "📡 Ping: " .. pingVal .. " ms"
		end)
		task.wait(1)
	end
end)

local Sidebar = Instance.new("ScrollingFrame")
Sidebar.Parent = Main
Sidebar.Size = UDim2.new(0,140,1,0)
Sidebar.BackgroundColor3 = Color3.fromRGB(15,15,20)
Sidebar.CanvasSize = UDim2.fromOffset(0,450)
Sidebar.ScrollBarThickness = 2
local sbCorner = Instance.new("UICorner")
sbCorner.Parent = Sidebar

local HubTitle = Instance.new("TextLabel")
HubTitle.Parent = Sidebar
HubTitle.BackgroundTransparency = 1
HubTitle.Position = UDim2.new(0, 0, 0, 8)
HubTitle.Size = UDim2.new(1, 0, 0, 22)
HubTitle.Text = "DARUS HUB"
HubTitle.Font = Enum.Font.GothamBold
HubTitle.TextColor3 = Color3.fromRGB(0, 170, 255)
HubTitle.TextSize = 17

local HubSubTitle = Instance.new("TextLabel")
HubSubTitle.Parent = Sidebar
HubSubTitle.BackgroundTransparency = 1
HubSubTitle.Position = UDim2.new(0, 0, 0, 32)
HubSubTitle.Size = UDim2.new(1, 0, 0, 18)
HubSubTitle.Text = "Tanpa Aktivasi"
HubSubTitle.Font = Enum.Font.GothamBold
HubSubTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
HubSubTitle.TextSize = 12

local Content = Instance.new("Frame")
Content.Parent = Main
Content.Position = UDim2.new(0,150,0,30)
Content.Size = UDim2.new(1,-160,1,-64)
Content.BackgroundTransparency = 1
App.status = Instance.new("TextLabel", Main)
App.status.Size = UDim2.new(1,-160,0,28)
App.status.Position = UDim2.new(0,150,1,-30)
App.status.BackgroundTransparency = 1
App.status.Font = Enum.Font.Gotham
App.status.TextSize = 10
App.status.TextWrapped = true
App.status.TextColor3 = Color3.fromRGB(255,210,130)
App.status.Text = "Darus Hub siap. Pilih fitur yang diperlukan."

local isMinimized = false
App.Connect(MinimizeBtn.MouseButton1Click, function()
	isMinimized = not isMinimized
	MinimizeBtn.Text = isMinimized and "+" or "-"
	Main:TweenSize(isMinimized and UDim2.new(0,550,0,38) or UDim2.new(0,550,0,320), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
	Sidebar.Visible = not isMinimized
	Content.Visible = not isMinimized
	PingLabel.Visible = not isMinimized
	App.status.Visible = not isMinimized
end)

App.Connect(CloseBtn.MouseButton1Click, function() Gui:Destroy() end)

local function CreateNavButton(text, yPos)
	local btn = Instance.new("TextButton")
	btn.Parent = Sidebar
	btn.Position = UDim2.new(0, 10, 0, yPos)
	btn.Size = UDim2.new(1, -20, 0, 28)
	btn.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	btn.Text = text
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	local corner = Instance.new("UICorner")
	corner.Parent = btn
	return btn
end

local HomeBtn = CreateNavButton("Fishing & Sell", 60)
local FavoriteBtn = CreateNavButton("⭐ Favorite", 95)
local GalatamaBtn = CreateNavButton("Galatama", 130)
local TeleportShopBtn = CreateNavButton("Teleport Shop", 165)
local SummitBtn = CreateNavButton("Summit", 200)
local PlayerMenuBtn = CreateNavButton("Player", 235)
local HaloMenuBtn = CreateNavButton("Halo Kepala", 270)
local PlayerTpBtn = CreateNavButton("Teleport Player", 305)
local PrivacyBtn = CreateNavButton("Privacy", 340)
local SettingsBtn = CreateNavButton("Settings", 375)
local CreditsBtn = CreateNavButton("Credits", 410)

local function MakePage()
	local f = Instance.new("ScrollingFrame")
	f.Parent = Content
	f.Size = UDim2.new(1,0,1,0)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.CanvasSize = UDim2.fromOffset(0,0)
	f.AutomaticCanvasSize = Enum.AutomaticSize.Y
	f.ScrollBarThickness = 4
	local pad = Instance.new("UIPadding")
	pad.Parent = f
	pad.PaddingTop = UDim.new(0, 10)
	local l = Instance.new("UIListLayout")
	l.Parent = f
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 8)
	local order = 0
	App.Connect(f.ChildAdded, function(child)
		if child:IsA("GuiObject") then order += 1; child.LayoutOrder = order end
	end)
	return f
end

local FishingPage = MakePage()
FishingPage.Visible = true
local FavoritePage = MakePage()
local GalatamaPage = MakePage()
local TeleportShopPage = MakePage()
local SummitPage = MakePage()
local PlayerPage = MakePage()
local HaloPage = MakePage()
local PlayerTpPage = MakePage()
local PrivacyPage = MakePage()
local SettingsPage = MakePage()
local CreditsPage = MakePage()

local function HideAll()
	FishingPage.Visible = false
	FavoritePage.Visible = false
	GalatamaPage.Visible = false
	TeleportShopPage.Visible = false
	SummitPage.Visible = false
	PlayerPage.Visible = false
	HaloPage.Visible = false
	PlayerTpPage.Visible = false
	PrivacyPage.Visible = false
	SettingsPage.Visible = false
	CreditsPage.Visible = false
end

App.Connect(HomeBtn.MouseButton1Click, function() HideAll(); FishingPage.Visible = true end)
App.Connect(FavoriteBtn.MouseButton1Click, function() HideAll(); FavoritePage.Visible = true end)
App.Connect(GalatamaBtn.MouseButton1Click, function() HideAll(); GalatamaPage.Visible = true end)
App.Connect(TeleportShopBtn.MouseButton1Click, function() HideAll(); TeleportShopPage.Visible = true end)
App.Connect(SummitBtn.MouseButton1Click, function() HideAll(); SummitPage.Visible = true end)
App.Connect(PlayerMenuBtn.MouseButton1Click, function() HideAll(); PlayerPage.Visible = true end)
App.Connect(HaloMenuBtn.MouseButton1Click, function() HideAll(); HaloPage.Visible = true end)
App.Connect(PlayerTpBtn.MouseButton1Click, function() HideAll(); PlayerTpPage.Visible = true end)
App.Connect(PrivacyBtn.MouseButton1Click, function() HideAll(); PrivacyPage.Visible = true end)
App.Connect(SettingsBtn.MouseButton1Click, function() HideAll(); SettingsPage.Visible = true end)
App.Connect(CreditsBtn.MouseButton1Click, function() HideAll(); CreditsPage.Visible = true end)

local function AddToggle(parent, text, callback)
	local b = Instance.new("TextButton", parent)
	b.Size = UDim2.new(1,0,0,35)
	b.TextColor3 = Color3.new(1,1,1)
	b.Font = Enum.Font.Gotham
	b.TextSize = 13
	b.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UICorner", b)
	local controller = {value = false}
	function controller:Set(value, silent)
		local changed = self.value ~= value
		self.value = value
		b.Text = "  " .. text .. (value and " [ON]" or " [OFF]")
		b.BackgroundColor3 = value and Color3.fromRGB(0,100,180) or Color3.fromRGB(30,30,40)
		if changed and not silent then callback(value) end
	end
	App.toggles[text] = controller
	controller:Set(false, true)
	App.Connect(b.MouseButton1Click, function() controller:Set(not controller.value) end)
	return controller
end

----------------------------------------------------
-- 1. FISHING PAGE
----------------------------------------------------
local TitleFish = Instance.new("TextLabel")
TitleFish.Parent = FishingPage
TitleFish.Size = UDim2.new(1,0,0,30)
TitleFish.BackgroundTransparency = 1
TitleFish.Text = "🔥 AUTO FISHING & SELL UTILITIES"
TitleFish.TextColor3 = Color3.fromRGB(0,170,255)
TitleFish.Font = Enum.Font.GothamBold
TitleFish.TextSize = 13

local SpotLabel = Instance.new("TextLabel")
SpotLabel.Parent = FishingPage
SpotLabel.Size = UDim2.new(1,0,0,25)
SpotLabel.BackgroundTransparency = 1
SpotLabel.Text = "Lokasi Saat Ini: " .. State.SelectedFishingSpot
SpotLabel.TextColor3 = Color3.new(1,1,1)
SpotLabel.Font = Enum.Font.Gotham
SpotLabel.TextSize = 12

local ChangeSpotBtn = Instance.new("TextButton")
ChangeSpotBtn.Parent = FishingPage
ChangeSpotBtn.Size = UDim2.new(1,0,0,32)
ChangeSpotBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
ChangeSpotBtn.Text = "Ganti Spot Manual"
ChangeSpotBtn.TextColor3 = Color3.new(1,1,1)
ChangeSpotBtn.Font = Enum.Font.GothamMedium
ChangeSpotBtn.TextSize = 12
local csCorner = Instance.new("UICorner")
csCorner.Parent = ChangeSpotBtn

local spotList = {"Spot Mancing Jembatan", "Spot Mancing Core", "Spot Mancing Ikan Anomali"}
local spotIndex = table.find(spotList, State.SelectedFishingSpot) or 1
App.Connect(ChangeSpotBtn.MouseButton1Click, function()
	spotIndex = (table.find(spotList, State.SelectedFishingSpot) or spotIndex) % #spotList + 1
	State.SelectedFishingSpot = spotList[spotIndex]
	SpotLabel.Text = "Lokasi Saat Ini: " .. State.SelectedFishingSpot
	State.Config.SelectedSpot = State.SelectedFishingSpot
	App.fishingEpoch += 1
	SaveConfig()
end)

function App.SetFishing(mode, enabled)
	local other = mode == "spot" and "Smart Auto Fishing (Di Tempat Saja)" or "Smart Auto Fishing + Teleport"
	if enabled then
		if App.toggles[other] then App.toggles[other]:Set(false, true) end
		if App.toggles["Auto Summit Loop (Tween)"] then App.toggles["Auto Summit Loop (Tween)"]:Set(false) end
		State.FishingMode = mode
		State.AutoFishingEventRunning = true
		if mode == "spot" then App.Teleport(FishingSpots[State.SelectedFishingSpot] + Vector3.new(0,5,0)) end
	elseif State.FishingMode == mode then
		State.AutoFishingEventRunning = false
		State.FishingMode = nil
	end
	App.fishingEpoch += 1
	App.Restore("rod")
end
AddToggle(FishingPage, "Smart Auto Fishing + Teleport", function(v) App.SetFishing("spot", v) end)
AddToggle(FishingPage, "Smart Auto Fishing (Di Tempat Saja)", function(v) App.SetFishing("here", v) end)
App.Spawn(function()
	while App.Wait(0.15) do
		if State.AutoFishingEventRunning and not State.Selling and not State.AutoSummitRunning then
			local character = LocalPlayer.Character
			local rod = character and character:FindFirstChild("Withering Rod")
			local mechanics = rod and rod:FindFirstChild("Mechanics")
			local remotes = mechanics and mechanics:FindFirstChild("Remotes")
			if remotes then RunAutoFishCycle(remotes, rod)
			else App.Report("Pegang Withering Rod yang kompatibel untuk memancing.") end
		end
	end
end)

local BiteDelayBox = Instance.new("TextBox")
BiteDelayBox.Parent = FishingPage
BiteDelayBox.Size = UDim2.new(1,0,0,35)
BiteDelayBox.BackgroundColor3 = Color3.fromRGB(35,35,45)
BiteDelayBox.PlaceholderText = "Bite Delay (Detik, Cth: 0.5)"
BiteDelayBox.Text = tostring(State.Config.BiteDelay)
BiteDelayBox.TextColor3 = Color3.new(1,1,1)
BiteDelayBox.Font = Enum.Font.Gotham
BiteDelayBox.TextSize = 12
local bdCorner = Instance.new("UICorner")
bdCorner.Parent = BiteDelayBox

App.Connect(BiteDelayBox.FocusLost, function()
	BiteDelayBox.Text = tostring(App.Number(BiteDelayBox.Text, 0.5, 0, 30))
	State.BiteDelayInput = BiteDelayBox.Text
	State.Config.BiteDelay = BiteDelayBox.Text
	SaveConfig()
end)

AddToggle(FishingPage, "Auto Sell Timer ke NPC", function(v)
	State.AutoSellRunning = v
	if not v then App.Restore("sellPosition"); State.Selling = false end
end)
App.Spawn(function()
	local lastSell = os.clock()
	while App.Wait(0.2) do
		if not State.AutoSellRunning then lastSell = os.clock()
		elseif os.clock()-lastSell >= App.Number(State.AutoSellTimerInput,5,0.1,1440)*60 then
			TriggerSellToNpc()
			lastSell = os.clock()
		end
	end
end)

local SellTimerBox = Instance.new("TextBox")
SellTimerBox.Parent = FishingPage
SellTimerBox.Size = UDim2.new(1,0,0,35)
SellTimerBox.BackgroundColor3 = Color3.fromRGB(35,35,45)
SellTimerBox.PlaceholderText = "Jeda Waktu Jual (Menit, Cth: 5)"
SellTimerBox.Text = tostring(State.Config.AutoSellTimer)
SellTimerBox.TextColor3 = Color3.new(1,1,1)
SellTimerBox.Font = Enum.Font.Gotham
SellTimerBox.TextSize = 12
local stCorner = Instance.new("UICorner")
stCorner.Parent = SellTimerBox

App.Connect(SellTimerBox.FocusLost, function()
	SellTimerBox.Text = tostring(App.Number(SellTimerBox.Text, 5, 0.1, 1440))
	State.AutoSellTimerInput = SellTimerBox.Text
	State.Config.AutoSellTimer = SellTimerBox.Text
	SaveConfig()
end)

----------------------------------------------------
-- SYSTEM ROTASI / LOOP SPOT MANCING
----------------------------------------------------
local TitleLoop = Instance.new("TextLabel")
TitleLoop.Parent = FishingPage
TitleLoop.Size = UDim2.new(1,0,0,25)
TitleLoop.BackgroundTransparency = 1
TitleLoop.Text = "⏳ ROTASI AUTO SPOT MANCING (TIMER)"
TitleLoop.TextColor3 = Color3.fromRGB(0,255,170)
TitleLoop.Font = Enum.Font.GothamBold
TitleLoop.TextSize = 13

AddToggle(FishingPage, "Aktifkan Loop Spot Mancing (Timer)", function(v) State.LoopSpotEnabled = v end)

local function CreateSpotTimerSetting(parent, spotName)
	local frame = Instance.new("Frame")
	frame.Parent = parent
	frame.Size = UDim2.new(1,0,0,35)
	frame.BackgroundColor3 = Color3.fromRGB(30,30,40)
	local fc = Instance.new("UICorner")
	fc.Parent = frame

	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Parent = frame
	toggleBtn.Size = UDim2.new(0.65,0,1,0)
	toggleBtn.BackgroundTransparency = 1
	toggleBtn.Text = "  " .. spotName .. " [OFF]"
	toggleBtn.TextColor3 = Color3.new(1,1,1)
	toggleBtn.Font = Enum.Font.Gotham
	toggleBtn.TextSize = 11
	toggleBtn.TextXAlignment = Enum.TextXAlignment.Left

	local timeBox = Instance.new("TextBox")
	timeBox.Parent = frame
	timeBox.Size = UDim2.new(0.3, -5, 0, 25)
	timeBox.Position = UDim2.new(0.7, 0, 0, 5)
	timeBox.BackgroundColor3 = Color3.fromRGB(45,45,55)
	timeBox.Text = State.SpotLoopConfig[spotName].Timer
	timeBox.PlaceholderText = "Menit"
	timeBox.TextColor3 = Color3.fromRGB(0,170,255)
	timeBox.Font = Enum.Font.GothamBold
	timeBox.TextSize = 11
	local tc = Instance.new("UICorner")
	tc.Parent = timeBox

	App.Connect(toggleBtn.MouseButton1Click, function()
		local cur = not State.SpotLoopConfig[spotName].Enabled
		State.SpotLoopConfig[spotName].Enabled = cur
		toggleBtn.Text = "  " .. spotName .. (cur and " [ON]" or " [OFF]")
		toggleBtn.TextColor3 = cur and Color3.fromRGB(0,255,150) or Color3.new(1,1,1)
		SaveConfig()
	end)
	App.configViews = App.configViews or {}
	local function RefreshSpotSetting()
		local config = State.SpotLoopConfig[spotName]
		toggleBtn.Text = "  " .. spotName .. (config.Enabled and " [ON]" or " [OFF]")
		toggleBtn.TextColor3 = config.Enabled and Color3.fromRGB(0,255,150) or Color3.new(1,1,1)
		timeBox.Text = config.Timer
	end
	table.insert(App.configViews, RefreshSpotSetting)
	RefreshSpotSetting()

	App.Connect(timeBox.FocusLost, function() timeBox.Text = tostring(App.Number(timeBox.Text,10,0.1,1440)); State.SpotLoopConfig[spotName].Timer = timeBox.Text; SaveConfig() end)
end

CreateSpotTimerSetting(FishingPage, "Spot Mancing Jembatan")
CreateSpotTimerSetting(FishingPage, "Spot Mancing Core")
CreateSpotTimerSetting(FishingPage, "Spot Mancing Ikan Anomali")

App.Spawn(function()
	local spotOrder = {"Spot Mancing Jembatan", "Spot Mancing Core", "Spot Mancing Ikan Anomali"}
	while App.running do
		if State.LoopSpotEnabled and not State.CoreEventActive and not State.Selling and not State.AutoSummitRunning then
			for _, name in ipairs(spotOrder) do
				local cfg = State.SpotLoopConfig[name]
				if State.LoopSpotEnabled and not State.CoreEventActive and not State.Selling and not State.AutoSummitRunning and cfg and cfg.Enabled then
					State.SelectedFishingSpot = name
					SpotLabel.Text = "Lokasi Saat Ini: " .. name
					pcall(function()
						local character = LocalPlayer.Character
						local hrp = character and character:FindFirstChild("HumanoidRootPart")
						local targetCFrame = FishingSpots[name]
						if hrp and targetCFrame then App.Teleport(targetCFrame + Vector3.new(0,5,0)) end
					end)
					local duration = (tonumber(cfg.Timer) or 10) * 60
					local timerStart = tick()
					while App.running and State.LoopSpotEnabled and not State.CoreEventActive and not State.Selling and not State.AutoSummitRunning and cfg.Enabled and (tick() - timerStart < duration) do
						task.wait(1)
					end
				end
			end
		end
		task.wait(1)
	end
end)

----------------------------------------------------
-- DROPDOWN BUILDER (UNIVERSAL MULTI-SELECT)
----------------------------------------------------
local function CreateMultiSelectDropdown(parent, titleText, optionsTable, targetStateTable)
	local container = Instance.new("Frame")
	container.Parent = parent
	container.Size = UDim2.new(1,0,0,40)
	container.BackgroundColor3 = Color3.fromRGB(30,30,40)
	container.ClipsDescendants = true
	local cc = Instance.new("UICorner")
	cc.Parent = container

	local header = Instance.new("TextButton")
	header.Parent = container
	header.Size = UDim2.new(1,0,0,40)
	header.BackgroundTransparency = 1
	header.Text = "  " .. titleText
	header.TextColor3 = Color3.new(1,1,1)
	header.Font = Enum.Font.GothamMedium
	header.TextSize = 12
	header.TextXAlignment = Enum.TextXAlignment.Left

	local countLabel = Instance.new("TextLabel")
	countLabel.Parent = header
	countLabel.Size = UDim2.new(0,120,1,0)
	countLabel.Position = UDim2.new(1,-130,0,0)
	countLabel.BackgroundTransparency = 1
	countLabel.TextColor3 = Color3.fromRGB(0,170,255)
	countLabel.Font = Enum.Font.GothamBold
	countLabel.TextSize = 11
	countLabel.TextXAlignment = Enum.TextXAlignment.Right

	local optionsHolder = Instance.new("Frame")
	optionsHolder.Parent = container
	optionsHolder.Position = UDim2.new(0,5,0,40)
	optionsHolder.Size = UDim2.new(1,-10,0,0)
	optionsHolder.BackgroundTransparency = 1

	local listLayout = Instance.new("UIListLayout")
	listLayout.Parent = optionsHolder
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)

	local itemButtons = {}

	local function UpdateSummary()
		local selectedCount = 0
		for _, name in ipairs(optionsTable) do if targetStateTable[name] then selectedCount = selectedCount + 1 end end
		if selectedCount == 0 then countLabel.Text = "None 🔽"
		elseif selectedCount == #optionsTable then countLabel.Text = "All (" .. selectedCount .. ") 🔽"
		else countLabel.Text = selectedCount .. " Selected 🔽" end
	end

	local selectAllBtn = Instance.new("TextButton")
	selectAllBtn.Parent = optionsHolder
	selectAllBtn.Size = UDim2.new(1,0,0,28)
	selectAllBtn.BackgroundColor3 = Color3.fromRGB(0,150,120)
	selectAllBtn.Text = "  ⚡ SELECT ALL / UNSELECT ALL"
	selectAllBtn.TextColor3 = Color3.new(1,1,1)
	selectAllBtn.Font = Enum.Font.GothamBold
	selectAllBtn.TextSize = 11
	selectAllBtn.TextXAlignment = Enum.TextXAlignment.Left
	local saCorner = Instance.new("UICorner")
	saCorner.Parent = selectAllBtn

	App.Connect(selectAllBtn.MouseButton1Click, function()
		local allState = false
		for _, name in ipairs(optionsTable) do if not targetStateTable[name] then allState = true; break end end
		for _, optName in ipairs(optionsTable) do targetStateTable[optName] = allState end
		for optName, btn in pairs(itemButtons) do
			btn.BackgroundColor3 = allState and Color3.fromRGB(0,120,200) or Color3.fromRGB(40,40,50)
			btn.Text = "  " .. optName .. (allState and "  [✓]" or "  [ ]")
		end
		UpdateSummary()
		SaveConfig()
	end)

	for _, optName in ipairs(optionsTable) do
		local optBtn = Instance.new("TextButton")
		optBtn.Parent = optionsHolder
		optBtn.Size = UDim2.new(1,0,0,28)
		optBtn.LayoutOrder = #optionsHolder:GetChildren()
		optBtn.BackgroundColor3 = targetStateTable[optName] and Color3.fromRGB(0,120,200) or Color3.fromRGB(40,40,50)
		optBtn.Text = "  " .. optName .. (targetStateTable[optName] and "  [✓]" or "  [ ]")
		optBtn.TextColor3 = Color3.new(1,1,1)
		optBtn.Font = Enum.Font.Gotham
		optBtn.TextSize = 11
		optBtn.TextXAlignment = Enum.TextXAlignment.Left
		local obc = Instance.new("UICorner")
		obc.Parent = optBtn

		itemButtons[optName] = optBtn

		App.Connect(optBtn.MouseButton1Click, function()
			targetStateTable[optName] = not targetStateTable[optName]
			optBtn.BackgroundColor3 = targetStateTable[optName] and Color3.fromRGB(0,120,200) or Color3.fromRGB(40,40,50)
			optBtn.Text = "  " .. optName .. (targetStateTable[optName] and "  [✓]" or "  [ ]")
			UpdateSummary()
			SaveConfig()
		end)
	end

	UpdateSummary()
	App.configViews = App.configViews or {}
	table.insert(App.configViews, function()
		for name, btn in pairs(itemButtons) do
			local selected = targetStateTable[name] == true
			btn.Text = "  " .. name .. (selected and "  [✓]" or "  [ ]")
			btn.BackgroundColor3 = selected and Color3.fromRGB(0,120,200) or Color3.fromRGB(40,40,50)
		end
		UpdateSummary()
	end)

	local isOpen = false
	App.Connect(header.MouseButton1Click, function()
		isOpen = not isOpen
		container:TweenSize(isOpen and UDim2.new(1,0,0, 45 + ((#optionsTable + 1) * 32)) or UDim2.new(1,0,0,40), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.2, true)
	end)
end

----------------------------------------------------
-- 2. FAVORITE PAGE
----------------------------------------------------
local TitleFav = Instance.new("TextLabel")
TitleFav.Parent = FavoritePage
TitleFav.Size = UDim2.new(1,0,0,25)
TitleFav.BackgroundTransparency = 1
TitleFav.Text = "⭐ AUTO FAVORITE FILTER"
TitleFav.TextColor3 = Color3.fromRGB(0,170,255)
TitleFav.Font = Enum.Font.GothamBold
TitleFav.TextSize = 13

AddToggle(FavoritePage, "AUTO FAVORITE", function(v) State.AutoFavoriteRunning = v end)

local rarityList = {"Common", "UnCommon", "Rare", "Epic", "Legendary", "Mythical", "Secret", "Forgotten"}
local mutationList = {
	"Galaxy", "Corrupt", "Gemstone", "Ghost", "Lightning", "Fairy Dust",
	"Gold", "Midnight", "Radioactive", "Stone", "Holographic", "Albino", "Sandy", "Cosmic",
	"Normal", "Elemental", "Festive", "8-Bit", "Bloodmoon", "Abyssal", "Strawberry", "Void", "Cupid"
}

CreateMultiSelectDropdown(FavoritePage, "Fav Filter Rarity", rarityList, State.FavRarities)
CreateMultiSelectDropdown(FavoritePage, "Fav Filter Mutasi", mutationList, State.FavMutations)

local TitleUnfav = Instance.new("TextLabel")
TitleUnfav.Parent = FavoritePage
TitleUnfav.Size = UDim2.new(1,0,0,25)
TitleUnfav.BackgroundTransparency = 1
TitleUnfav.Text = "🗑️ UNFAVORITE FILTER SETTINGS"
TitleUnfav.TextColor3 = Color3.fromRGB(255,100,100)
TitleUnfav.Font = Enum.Font.GothamBold
TitleUnfav.TextSize = 13

CreateMultiSelectDropdown(FavoritePage, "Unfav Filter Rarity", rarityList, State.UnfavRarities)
CreateMultiSelectDropdown(FavoritePage, "Unfav Filter Mutasi", mutationList, State.UnfavMutations)

local UnfavFilterBtn = Instance.new("TextButton")
UnfavFilterBtn.Parent = FavoritePage
UnfavFilterBtn.Size = UDim2.new(1,0,0,38)
UnfavFilterBtn.BackgroundColor3 = Color3.fromRGB(200, 100, 30)
UnfavFilterBtn.Text = "🎯 UNFAVORITE BY FILTER"
UnfavFilterBtn.TextColor3 = Color3.new(1,1,1)
UnfavFilterBtn.Font = Enum.Font.GothamBold
UnfavFilterBtn.TextSize = 12
local ufc = Instance.new("UICorner")
ufc.Parent = UnfavFilterBtn
App.Connect(UnfavFilterBtn.MouseButton1Click, function() UnfavoriteByFilter() end)

local UnfavBtn = Instance.new("TextButton")
UnfavBtn.Parent = FavoritePage
UnfavBtn.Size = UDim2.new(1,0,0,38)
UnfavBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
UnfavBtn.Text = "🚨 UNFAVORITE ALL FISH"
UnfavBtn.TextColor3 = Color3.new(1,1,1)
UnfavBtn.Font = Enum.Font.GothamBold
UnfavBtn.TextSize = 12
local uac = Instance.new("UICorner")
uac.Parent = UnfavBtn
App.Connect(UnfavBtn.MouseButton1Click, function() UnfavoriteAllFish() end)

----------------------------------------------------
-- 3. GALATAMA PAGE (DENGAN AUTO DETEKSI CORE EVENT)
----------------------------------------------------
local TitleGal = Instance.new("TextLabel")
TitleGal.Parent = GalatamaPage
TitleGal.Size = UDim2.new(1,0,0,30)
TitleGal.BackgroundTransparency = 1
TitleGal.Text = "🏆 GALATAMA & CORE EVENT UTILITIES"
TitleGal.TextColor3 = Color3.fromRGB(0,170,255)
TitleGal.Font = Enum.Font.GothamBold
TitleGal.TextSize = 13

local TeleportGalatamaBtn = Instance.new("TextButton")
TeleportGalatamaBtn.Parent = GalatamaPage
TeleportGalatamaBtn.Size = UDim2.new(1,0,0,35)
TeleportGalatamaBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
TeleportGalatamaBtn.Text = "📍 Teleport ke Galatama"
TeleportGalatamaBtn.TextColor3 = Color3.new(1,1,1)
TeleportGalatamaBtn.Font = Enum.Font.GothamBold
TeleportGalatamaBtn.TextSize = 13
local tgc = Instance.new("UICorner")
tgc.Parent = TeleportGalatamaBtn
App.Connect(TeleportGalatamaBtn.MouseButton1Click, function()
	pcall(function() LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-8008.12744, 1227.96838, -6091.92627) + Vector3.new(0, 5, 0) end)
end)

AddToggle(GalatamaPage, "Aktifkan Auto Join Galatama", function(v) State.AutoGalatamaRunning = v end)
App.Spawn(function()
	while App.Wait(0.2) do
		if State.AutoGalatamaRunning then
			local folder = ReplicatedStorage:FindFirstChild("Remote")
			local galatama = folder and folder:FindFirstChild("Galatama")
			App.Invoke(galatama and galatama:FindFirstChild("Ikut"))
			App.Wait(10,function() return State.AutoGalatamaRunning end)
		end
	end
end)

local TitleCoreEvent = Instance.new("TextLabel")
TitleCoreEvent.Parent = GalatamaPage
TitleCoreEvent.Size = UDim2.new(1,0,0,25)
TitleCoreEvent.BackgroundTransparency = 1
TitleCoreEvent.Text = "💎 PERKIRAAN JADWAL WITHERING CORE"
TitleCoreEvent.TextColor3 = Color3.fromRGB(255,200,0)
TitleCoreEvent.Font = Enum.Font.GothamBold
TitleCoreEvent.TextSize = 13

AddToggle(GalatamaPage, "Ikuti Jadwal Core (menit 00-10, perkiraan)", function(v) State.AutoDetectCoreEvent = v end)
App.Spawn(function()
	local savedSpot
	while App.Wait(1) do
		local minute = tonumber(os.date("%M")) or -1
		local scheduled = State.AutoDetectCoreEvent and minute >= 0 and minute <= 10
		if scheduled and not State.Selling and not State.AutoSummitRunning then
			if not State.CoreEventActive then savedSpot = State.SelectedFishingSpot end
			State.CoreEventActive = true
			State.SelectedFishingSpot = "Spot Mancing Core"
			SpotLabel.Text = "Lokasi Saat Ini: Spot Mancing Core (perkiraan jadwal)"
			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local target = FishingSpots["Spot Mancing Core"]
			if root and (root.Position-target.Position).Magnitude > 20 then App.Teleport(target+Vector3.new(0,5,0)) end
		elseif not scheduled and State.CoreEventActive then
			State.CoreEventActive = false
			if savedSpot and FishingSpots[savedSpot] then
				State.SelectedFishingSpot = savedSpot
				SpotLabel.Text = "Lokasi Saat Ini: " .. savedSpot
				if not State.Selling and not State.AutoSummitRunning then App.Teleport(FishingSpots[savedSpot]+Vector3.new(0,5,0)) end
			end
			savedSpot = nil
		end
	end
end)

----------------------------------------------------
-- 4. TELEPORT SHOP PAGE
----------------------------------------------------
local TitleShop = Instance.new("TextLabel")
TitleShop.Parent = TeleportShopPage
TitleShop.Size = UDim2.new(1,0,0,30)
TitleShop.BackgroundTransparency = 1
TitleShop.Text = "🛒 TELEPORT TO SHOPS & NPCS"
TitleShop.TextColor3 = Color3.fromRGB(0,170,255)
TitleShop.Font = Enum.Font.GothamBold
TitleShop.TextSize = 13

local function AddShopTeleportBtn(parent, name, cf)
	local btn = Instance.new("TextButton")
	btn.Parent = parent
	btn.Size = UDim2.new(1,0,0,35)
	btn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	btn.Text = "📍 Teleport ke " .. name
	btn.TextColor3 = Color3.new(1,1,1)
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 12
	local c = Instance.new("UICorner")
	c.Parent = btn
	App.Connect(btn.MouseButton1Click, function() pcall(function() LocalPlayer.Character.HumanoidRootPart.CFrame = cf + Vector3.new(0, 5, 0) end) end)
end

AddShopTeleportBtn(TeleportShopPage, "Tempat Jual Ikan", CFrame.new(-6668.79785, 1312.69983, -9964.06152))
AddShopTeleportBtn(TeleportShopPage, "Skin Shop", CFrame.new(-6639.45947, 1312.69983, -9947.36133))
AddShopTeleportBtn(TeleportShopPage, "Pet Shop", CFrame.new(-6640.44092, 1312.69983, -9917.93652))
AddShopTeleportBtn(TeleportShopPage, "Upgrade Pet", CFrame.new(-6637.85156, 1312.69983, -9886.52441))
AddShopTeleportBtn(TeleportShopPage, "Rod Shop", CFrame.new(-6638.09521, 1312.69983, -9857.41797))
AddShopTeleportBtn(TeleportShopPage, "Title Shop", CFrame.new(-6667.0249, 1312.69983, -9843.66113))

----------------------------------------------------
-- 5. SUMMIT PAGE (TWEEN CFRAME)
----------------------------------------------------
local TitleSum = Instance.new("TextLabel")
TitleSum.Parent = SummitPage
TitleSum.Size = UDim2.new(1,0,0,30)
TitleSum.BackgroundTransparency = 1
TitleSum.Text = "⛰️ AUTO SUMMIT FARM (TWEEN)"
TitleSum.TextColor3 = Color3.fromRGB(0,170,255)
TitleSum.Font = Enum.Font.GothamBold
TitleSum.TextSize = 13

State.SummitDelay = 1
State.SummitCpHeight = 1.5
State.SummitUseRemote = false
State.SummitSpeed = 150
State.SummitHeight = 6
local TweenService = game:GetService("TweenService")

local SummitPoints = {
	{"Cp1", CFrame.new(464.845001, 452.719116, -8948.57227, 0.997986674, 0.00330765732, -0.063337639, 5.851164e-10, 0.998639166, 0.0521515608, 0.0634239465, -0.0520465635, 0.996628582)},
	{"Tengah 1", CFrame.new(474.590057, 447.956573, -9159.24023, 0.999968529, -0.000852574885, -0.00788716134, -1.21188393e-10, 0.994208276, -0.107470497, 0.0079331072, 0.107467115, 0.994176984)},
	{"Cp2", CFrame.new(451.694855, 499.646576, -9572.44434, 0.99949652, 0.000553500664, 0.0317238159, 1.04904453e-10, 0.999847829, -0.0174448304, -0.0317286439, 0.0174360462, 0.999344409)},
	{"Tengah 2", CFrame.new(445.483307, 621.606934, -9778.32324, 0.997986615, -0.0062114615, 0.0631198436, 2.39959358e-10, 0.995192885, 0.0979343653, -0.0634247363, -0.0977371857, 0.993189156)},
	{"Cp3", CFrame.new(397.967834, 639.463623, -10116.7002, 0.999716818, -0.000510056969, -0.02379141, 4.97792363e-11, 0.999770284, -0.0214337762, 0.0237968769, 0.0214277059, 0.999487162)},
	{"Tengah 3", CFrame.new(395.853546, 635.549683, -10386.791, 0.999716818, 0.00315287593, -0.0235871132, 5.91942884e-10, 0.991184175, 0.132491052, 0.0237969011, -0.132453531, 0.990903497)},
	{"Cp4", CFrame.new(489.159821, 642.277039, -10681.7002, -0.0475802682, 0.0602015518, -0.997051597, 1.55177843e-10, 0.998182118, 0.060269814, 0.998867393, 0.00286765373, -0.0474937744)},
	{"Tengah 4", CFrame.new(956.084595, 697.091187, -10802.7363, 0.795761228, -0.0310973153, -0.604811549, -1.72196937e-10, 0.99868077, -0.0513487086, 0.60561049, 0.0408613123, 0.794711471)},
	{"Cp5", CFrame.new(1086.91284, 731.401855, -11160.585, 0.998458445, 0.000272808335, 0.0555039383, 3.18766229e-11, 0.9999879, -0.00491505768, -0.0555046089, 0.00490748091, 0.998446345)},
	{"Tengah 5", CFrame.new(1057.28174, 733.071716, -11465.1123, 0.986154497, 0.0050284788, -0.165753007, 1.63842329e-09, 0.99954015, 0.030323239, 0.165829256, -0.0299033988, 0.985700965)},
	{"Cp6", CFrame.new(971.530334, 740.581787, -11810.3145, 0.126592144, -0.0387375578, 0.991198182, 2.35382769e-10, 0.99923718, 0.0390517339, -0.991954863, -0.00494364277, 0.126495585)},
	{"Tengah 6", CFrame.new(691.74884, 797.521545, -11823.7451, 0.0396752357, -0.102132671, 0.993979275, -7.48076157e-10, 0.99476254, 0.102213152, -0.999212623, -0.00405533146, 0.0394674353)},
	{"Cp7", CFrame.new(388.335876, 895.511658, -11840.2939, 0.0238173455, -0.0717899501, 0.997135341, -6.08690737e-11, 0.997418284, 0.07181032, -0.999716341, -0.0017103313, 0.0237558559)},
	{"Tengah 7", CFrame.new(49.462944, 888.104858, -11861.6387, -0.34944579, -0.19423911, 0.916601777, -3.19386761e-09, 0.978275597, 0.207308546, -0.936956584, 0.0724430978, -0.341854304)},
	{"Cp8", CFrame.new(-328.146729, 853.138916, -11739.3906, 0.00795334298, -0.0638618842, 0.99792707, -8.82961412e-11, 0.997958601, 0.0638639033, -0.99996835, -0.000507931632, 0.00793710724)},
	{"Tengah 8", CFrame.new(-586.720459, 854.341248, -11757.834, -0.0317074656, -0.143703595, 0.989112675, -3.78500481e-10, 0.989610255, 0.14377588, -0.999497175, 0.00455876859, -0.0313780345)},
	{"Cp9", CFrame.new(-873.571655, 857.913574, -11736.6006, -0.0475608706, -0.0613531955, 0.996982336, -8.74402217e-11, 0.998111844, 0.0614227057, -0.998868346, 0.00292131724, -0.0474710688)},
	{"Tengah 9", CFrame.new(-1278.78198, 862.183228, -11790.2275, 0.987442195, -0.0267404672, 0.155701235, 5.12804066e-09, 0.985570729, 0.169264019, -0.157980785, -0.167138427, 0.973194122)},
	{"Cp10", CFrame.new(-1282.57056, 863.854065, -12096.4014, 0.999212563, 5.95095444e-05, -0.0396771468, -1.05802248e-12, 0.999998868, 0.00149984262, 0.0396771915, -0.00149866159, 0.999211431)},
	{"Tengah 10", CFrame.new(-1163.88379, 880.556641, -12491.4229, 0.999716282, 0.00329811801, -0.0235888157, 4.36980556e-11, 0.990366638, 0.138470113, 0.0238182656, -0.138430834, 0.990085661)},
	{"Cp11", CFrame.new(-1314.84912, 896.930481, -12835.1504, -0.0317075849, -0.0382487178, 0.998765051, -2.9176847e-10, 0.999267519, 0.0382679589, -0.999497175, 0.00121338433, -0.0316843614)},
	{"Tengah 11", CFrame.new(-1935.85815, 918.891724, -12822.8037, 0.0555249788, -0.118038259, 0.991455495, 5.07237197e-10, 0.992987335, 0.118220635, -0.998457313, -0.0065641976, 0.0551356003)},
	{"Cp12", CFrame.new(-2322.29541, 919.173645, -12668.2285, -0.99745357, 0.00879278593, -0.0707743391, -2.61384775e-10, 0.992370784, 0.123289101, 0.0713184401, 0.122975156, -0.989843845)},
	{"Tengah 12", CFrame.new(-2335.94287, 919.825073, -12331.4092, -0.999212563, 0.000273454934, 0.0396762192, 4.04826658e-11, 0.999976277, -0.00689199753, -0.0396771617, -0.00688657025, -0.99918884)},
	{"Cp13", CFrame.new(-2311.24023, 923.90979, -11851.917, -0.99745059, -0.00294975913, 0.0712991208, -1.04126284e-10, 0.999145269, 0.0413362421, -0.0713601112, 0.0412308611, -0.996598065)},
	{"Tengah 13", CFrame.new(-2340.36206, 951.430298, -11351.1699, -0.999497175, 0.00360921631, -0.03150158, -6.74113487e-10, 0.993500471, 0.113827907, 0.0317076631, 0.113770671, -0.993000925)},
	{"Cp14", CFrame.new(-2448.27344, 964.254089, -11057.0312, 0.0476028472, -0.0647127628, 0.996767879, 3.43433559e-10, 0.997899175, 0.0647862107, -0.99886632, -0.00308400765, 0.0475028418)},
	{"Tengah 14", CFrame.new(-3044.74292, 981.493469, -11030.8037, 0.0238184482, -0.0852627605, 0.996073782, -5.87034976e-10, 0.996356428, 0.08528696, -0.999716282, -0.00203140359, 0.0237316638)},
	{"Cp15", CFrame.new(-3483.43945, 988.503296, -11013.0811, 0.0396763459, -0.0475526191, 0.998080432, -1.16498686e-10, 0.998866975, 0.0475900918, -0.999212563, -0.00188820099, 0.0396313891)},
	{"Tengah 15", CFrame.new(-3854.48242, 985.936829, -11009.2061, -0.0950342268, -0.142578945, 0.985210478, -2.72903367e-09, 0.989689827, 0.14322719, -0.995473981, 0.0136114825, -0.0940544084)},
	{"Cp16", CFrame.new(-4231.1875, 1006.55963, -11017.707, 0.0950784385, -0.0579245724, 0.993783116, -6.25444918e-10, 0.998305619, 0.0581881776, -0.995469809, -0.00553244166, 0.0949173421)},
	{"Tengah 16", CFrame.new(-4490.48242, 1038.65771, -11328.7051, 0.990922332, -0.00802882854, 0.134195656, -4.68678207e-10, 0.99821502, 0.0597224832, -0.134435624, -0.0591803417, 0.989153564)},
	{"Cp17", CFrame.new(-4655.4458, 1085.97107, -11667.3447, -0.110815927, 0.02199829, 0.993597448, 2.2579081e-11, 0.999755025, -0.0221346188, -0.993840933, -0.00245286827, -0.110788777)},
	{"Tengah 17", CFrame.new(-5027.59277, 1094.36035, -11674.2949, 0.0238194466, -0.060855411, 0.997862339, -6.60101834e-11, 0.998145521, 0.0608726814, -0.999716282, -0.00144995365, 0.0237752739)},
	{"Cp18", CFrame.new(-5545.39404, 1107.8219, -11650.6357, -0.00791138876, -0.0912490711, 0.99579668, -1.18666341e-10, 0.995827854, 0.0912519246, -0.999968708, 0.000721929304, -0.00787838083)},
	{"Tengah 18", CFrame.new(-6414.31885, 1107.92029, -11711.4941, 0.39367038, -0.111929558, 0.912411869, 1.31374795e-08, 0.992559373, 0.121761598, -0.91925168, -0.0479339212, 0.390741229)},
	{"Cp19", CFrame.new(-6766.26074, 1105.58411, -11503.3955, -0.999874473, 0.000155506685, -0.015843736, -2.90724042e-12, 0.999951839, 0.00981455389, 0.0158444997, 0.00981332175, -0.999826312)},
	{"Tengah 19", CFrame.new(-6762.13184, 1099.67126, -11186.042, -0.998868346, 0.00112270634, -0.0475471318, -5.17564568e-11, 0.999721348, 0.0236059148, 0.0475603864, 0.0235792007, -0.998589993)},
	{"Cp20", CFrame.new(-6746.04248, 1108.37537, -10794.8271, -0.993840754, 0.0067165764, -0.11061395, -6.0127392e-10, 0.998161554, 0.060609255, 0.110817678, 0.0602359474, -0.992013633)}
}

local function SetPlatformStand(state)
	pcall(function()
		local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if state and hum then App.Set("platform", hum, "PlatformStand", true)
		else App.Restore("platform") end
	end)
end

AddToggle(SummitPage, "Auto Summit Loop (Tween)", function(v)
	State.AutoSummitRunning = v
	App.summitEpoch = (App.summitEpoch or 0) + 1
	if App.tween then App.tween:Cancel(); App.tween = nil end
	if v then
		App.toggles["Smart Auto Fishing + Teleport"]:Set(false)
		App.toggles["Smart Auto Fishing (Di Tempat Saja)"]:Set(false)
	else SetPlatformStand(false) end
end)

local function AddSummitBox(placeholder, default, onChange)
	local box = Instance.new("TextBox")
	box.Parent = SummitPage
	box.Size = UDim2.new(1,0,0,35)
	box.BackgroundColor3 = Color3.fromRGB(35,35,45)
	box.PlaceholderText = placeholder
	box.Text = tostring(default)
	box.TextColor3 = Color3.new(1,1,1)
	box.Font = Enum.Font.Gotham
	box.TextSize = 12
	local bc = Instance.new("UICorner")
	bc.Parent = box
	App.Connect(box.FocusLost, function()
		local n = App.Number(box.Text, default, 0, 10000)
		box.Text = tostring(n)
		onChange(n)
	end)
end

AddSummitBox("Kecepatan Tween (studs/detik, Cth: 150)", 150, function(n) State.SummitSpeed = math.max(n, 20) end)
AddSummitBox("Tinggi di titik Tengah (Cth: 6)", 6, function(n) State.SummitHeight = n end)
AddSummitBox("Tinggi di titik Cp (Cth: 1.5)", 1.5, function(n) State.SummitCpHeight = n end)
AddToggle(SummitPage, "Pakai Remote Checkpoint (opsional)", function(v) State.SummitUseRemote = v end)
AddSummitBox("Jeda di tiap Cp (detik, Cth: 1)", 1, function(n) State.SummitDelay = math.max(n, 0) end)

local function TweenTo(root, target, active)
	if not active() then return false end
	local distance = (root.Position-target.Position).Magnitude
	local tween = TweenService:Create(root, TweenInfo.new(distance/App.Number(State.SummitSpeed,150,20,10000),Enum.EasingStyle.Linear), {CFrame=target})
	App.tween = tween
	local completed = false
	local connection = App.Connect(tween.Completed,function(playback) completed = playback == Enum.PlaybackState.Completed end)
	tween:Play()
	App.Wait(distance/App.Number(State.SummitSpeed,150,20,10000)+2,function()
		if not active() or completed then return false end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return true
	end)
	if not completed then tween:Cancel() end
	connection:Disconnect()
	App.connections[connection] = nil
	if App.tween == tween then App.tween = nil end
	return completed and active()
end

local function TouchCheckpoint(number, position, active)
	local part
	local deadline = os.clock()+4
	while active() and os.clock()<deadline do
		local folder = Workspace:FindFirstChild("Checkpoint")
		part = folder and folder:FindFirstChild("Checkpoint " .. tostring(number))
		if part and part:IsA("BasePart") then break end
		part = nil
		pcall(function() LocalPlayer:RequestStreamAroundAsync(position.Position,1) end)
		if not App.Wait(0.5,active) then return end
	end
	if not part or not active() then return end
	local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local stand = part.Position+Vector3.new(0,part.Size.Y/2+3,0)
	root.CFrame = CFrame.new(stand+Vector3.new(0,6,0))
	root.AssemblyLinearVelocity = Vector3.zero
	if not App.Wait(0.2,active) then return end
	root.CFrame = CFrame.new(stand)
	if type(firetouchinterest) == "function" then
		pcall(function()
			firetouchinterest(root,part,0)
			App.Wait(0.1,active)
			firetouchinterest(root,part,1)
		end)
	end
end

App.Spawn(function()
	while App.Wait(0.2) do
		if State.AutoSummitRunning and not State.Selling then
			local character, epoch = LocalPlayer.Character, App.summitEpoch
			local function active()
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				return App.running and State.AutoSummitRunning and App.summitEpoch == epoch and not State.Selling
					and LocalPlayer.Character == character and humanoid and humanoid.Health>0
			end
			local ok, err = pcall(function()
				for _, point in ipairs(SummitPoints) do
					if not active() then break end
					local root = character:FindFirstChild("HumanoidRootPart")
					if not root then break end
					local cp = tonumber(point[1]:match("^Cp(%d+)$"))
					local height = cp and State.SummitCpHeight or State.SummitHeight
					pcall(function() LocalPlayer:RequestStreamAroundAsync(point[2].Position,3) end)
					if not active() then break end
					SetPlatformStand(true)
					if not TweenTo(root,point[2]+Vector3.new(0,height,0),active) then break end
					if cp then
						SetPlatformStand(false)
						TouchCheckpoint(cp,point[2],active)
						if not App.Wait(State.SummitDelay,active) then break end
						if State.SummitUseRemote and active() then
							local remotes = ReplicatedStorage:FindFirstChild("Remote")
							local checkpoints = remotes and remotes:FindFirstChild("Checkpoint")
							local remote = checkpoints and checkpoints:FindFirstChild("TpToCheckpoint")
							if remote and remote:IsA("RemoteEvent") then remote:FireServer(cp) end
						end
					end
					if not App.Wait(0.2,active) then break end
				end
				if active() then
					local root = character:FindFirstChild("HumanoidRootPart")
					if root and TweenTo(root,CFrame.new(-6766.44629,1325.69983,-10083.8037),active) and App.Wait(3,active) then
						TweenTo(root,CFrame.new(-6834.84912,1318.24744,-9902.42285),active)
					end
				end
			end)
			if App.tween then App.tween:Cancel(); App.tween=nil end
			SetPlatformStand(false)
			if not ok then App.Report("Summit gagal: " .. tostring(err)) end
		end
	end
end)

----------------------------------------------------
-- 6. PLAYER PAGE
----------------------------------------------------
local TitlePly = Instance.new("TextLabel")
TitlePly.Parent = PlayerPage
TitlePly.Size = UDim2.new(1,0,0,30)
TitlePly.BackgroundTransparency = 1
TitlePly.Text = "⚡ PLAYER SETTINGS & VISUALS"
TitlePly.TextColor3 = Color3.fromRGB(0,170,255)
TitlePly.Font = Enum.Font.GothamBold
TitlePly.TextSize = 13

local SpeedBox = Instance.new("TextBox")
SpeedBox.Parent = PlayerPage
SpeedBox.Size = UDim2.new(1,0,0,35)
SpeedBox.BackgroundColor3 = Color3.fromRGB(35,35,45)
SpeedBox.PlaceholderText = "Ketik WalkSpeed (Cth: 50)"
SpeedBox.Text = ""
SpeedBox.TextColor3 = Color3.new(1,1,1)
local spc = Instance.new("UICorner")
spc.Parent = SpeedBox

App.Connect(SpeedBox.FocusLost, function()
	local num = App.Number(SpeedBox.Text,16,0,500)
	SpeedBox.Text = tostring(num)
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then App.Set("speed",humanoid,"WalkSpeed",num) end
end)

AddToggle(PlayerPage, "Anti-AFK", function(v) State.AntiAFKRunning = v end)
App.Connect(LocalPlayer.Idled, function()
	if State.AntiAFKRunning then VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new(0,0)) end
end)

local HeadlessBtn = Instance.new("TextButton")
HeadlessBtn.Parent = PlayerPage
HeadlessBtn.Size = UDim2.new(1,0,0,35)
HeadlessBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
HeadlessBtn.Text = "👻 Enable Headless"
HeadlessBtn.TextColor3 = Color3.new(1,1,1)
HeadlessBtn.Font = Enum.Font.GothamBold
HeadlessBtn.TextSize = 13
local hlc = Instance.new("UICorner")
hlc.Parent = HeadlessBtn

App.Connect(HeadlessBtn.MouseButton1Click, function()
	pcall(function()
		local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
		if head then
			App.Set("headless",head,"Transparency",1)
			for _, child in ipairs(head:GetChildren()) do if child:IsA("Decal") then App.Set("headless",child,"Transparency",1) end end
		end
	end)
end)

local FireRgbBtn = Instance.new("TextButton")
FireRgbBtn.Parent = PlayerPage
FireRgbBtn.Size = UDim2.new(1,0,0,35)
FireRgbBtn.BackgroundColor3 = Color3.fromRGB(150, 0, 200)
FireRgbBtn.Text = "🔥🌈 Auto RGB Fire: [OFF]"
FireRgbBtn.TextColor3 = Color3.new(1,1,1)
FireRgbBtn.Font = Enum.Font.GothamBold
FireRgbBtn.TextSize = 13
local frc = Instance.new("UICorner")
frc.Parent = FireRgbBtn

local autoRgbActive = false
App.Connect(FireRgbBtn.MouseButton1Click, function()
	autoRgbActive = not autoRgbActive
	FireRgbBtn.Text = "🔥🌈 Auto RGB Fire: " .. (autoRgbActive and "[ON]" or "[OFF]")
	FireRgbBtn.BackgroundColor3 = autoRgbActive and Color3.fromRGB(0, 150, 50) or Color3.fromRGB(150, 0, 200)
	pcall(function()
		local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
		if head then
			local fire = head:FindFirstChild("DarusHeadFire")
			if autoRgbActive and not fire then
				fire = Instance.new("Fire")
				fire.Name = "DarusHeadFire"
				fire.Size = 5
				fire.Heat = 15
				fire.Parent = head
				App.owned[fire] = true
			elseif not autoRgbActive and fire then
				fire:Destroy()
			end
		end
	end)
end)

App.Spawn(function()
	local colors = {Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 100, 255), Color3.fromRGB(255, 0, 255), Color3.fromRGB(255, 255, 0), Color3.fromRGB(0, 255, 255)}
	local index = 1
	while App.running do
		if autoRgbActive then
			pcall(function()
				local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
				local fire = head and head:FindFirstChild("DarusHeadFire")
				if fire then
					index = index % #colors + 1
					fire.Color = colors[index]
					fire.SecondaryColor = colors[(index % #colors) + 1]
				end
			end)
		end
		task.wait(1)
	end
end)

----------------------------------------------------
-- 7. HALO PAGE
----------------------------------------------------
local TitleHalo = Instance.new("TextLabel")
TitleHalo.Parent = HaloPage
TitleHalo.Size = UDim2.new(1,0,0,30)
TitleHalo.BackgroundTransparency = 1
TitleHalo.Text = "👑 HALO & AKSESORIS KEPALA"
TitleHalo.TextColor3 = Color3.fromRGB(0,170,255)
TitleHalo.Font = Enum.Font.GothamBold
TitleHalo.TextSize = 13

local function ApplyHaloToCharacter(haloName)
	State.CurrentSelectedHalo = haloName
	pcall(function()
		local character = LocalPlayer.Character
		local head = character and character:FindFirstChild("Head")
		if not head then return end
		for _, v in ipairs(head:GetChildren()) do if v.Name == "CustomPlayerHalo" then v:Destroy() end end
		local haloSourceFolder = ReplicatedStorage:FindFirstChild("HaloKenyal")
		if haloSourceFolder then
			local targetHaloModel = haloSourceFolder:FindFirstChild(haloName)
			if targetHaloModel then
				local cloneModel = targetHaloModel:Clone()
				App.owned[cloneModel] = true
				cloneModel.Name = "CustomPlayerHalo"
				local primaryPart = cloneModel:FindFirstChild("Handle") or cloneModel:FindFirstChild("Antenna") or cloneModel:FindFirstChildWhichIsA("BasePart")
				for _, desc in ipairs(cloneModel:GetDescendants()) do
					if desc:IsA("BasePart") then
						desc.Anchored = false
						desc.CanCollide = false
						desc.Massless = true
					elseif desc:IsA("Script") or desc:IsA("LocalScript") then desc:Destroy() end
				end
				if primaryPart and primaryPart:IsA("BasePart") then
					local target = head.CFrame * CFrame.new(0,1.3,0)
					local transform = target * primaryPart.CFrame:Inverse()
					for _, part in ipairs(cloneModel:GetDescendants()) do
						if part:IsA("BasePart") then part.CFrame = transform * part.CFrame end
					end
					for _, part in ipairs(cloneModel:GetDescendants()) do
						if part:IsA("BasePart") and part ~= primaryPart then
							local joint = Instance.new("WeldConstraint",part)
							joint.Part0, joint.Part1 = primaryPart, part
						end
					end
					cloneModel.Parent = head
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = head
					weld.Part1 = primaryPart
					weld.Parent = primaryPart
				else cloneModel:Destroy()
				end
			end
		end
	end)
end

App.Connect(LocalPlayer.CharacterAdded, function(char)
	task.wait(1)
	if State.CurrentSelectedHalo then ApplyHaloToCharacter(State.CurrentSelectedHalo) end
end)

pcall(function()
	local haloSourceFolder = ReplicatedStorage:FindFirstChild("HaloKenyal")
	if haloSourceFolder then
		local clearHaloBtn = Instance.new("TextButton")
		clearHaloBtn.Parent = HaloPage
		clearHaloBtn.Size = UDim2.new(1,0,0,32)
		clearHaloBtn.BackgroundColor3 = Color3.fromRGB(150, 30, 30)
		clearHaloBtn.Text = "❌ Lepas Aksesoris Kepala"
		clearHaloBtn.TextColor3 = Color3.new(1,1,1)
		clearHaloBtn.Font = Enum.Font.GothamBold
		clearHaloBtn.TextSize = 12
		local chc = Instance.new("UICorner")
		chc.Parent = clearHaloBtn

		App.Connect(clearHaloBtn.MouseButton1Click, function()
			State.CurrentSelectedHalo = nil
			pcall(function()
				local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
				if head then for _, v in ipairs(head:GetChildren()) do if v.Name == "CustomPlayerHalo" then v:Destroy() end end end
			end)
		end)
		for _, haloItem in ipairs(haloSourceFolder:GetChildren()) do
			local name = haloItem.Name
			local haloBtn = Instance.new("TextButton")
			haloBtn.Parent = HaloPage
			haloBtn.Size = UDim2.new(1,0,0,32)
			haloBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
			haloBtn.Text = "👑 " .. name
			haloBtn.TextColor3 = Color3.new(1,1,1)
			haloBtn.Font = Enum.Font.GothamMedium
			haloBtn.TextSize = 12
			local hbc = Instance.new("UICorner")
			hbc.Parent = haloBtn
			App.Connect(haloBtn.MouseButton1Click, function() ApplyHaloToCharacter(name) end)
		end
	end
end)

----------------------------------------------------
-- 8. TELEPORT PLAYER PAGE
----------------------------------------------------
local TitleTpPly = Instance.new("TextLabel")
TitleTpPly.Parent = PlayerTpPage
TitleTpPly.Size = UDim2.new(1,0,0,30)
TitleTpPly.BackgroundTransparency = 1
TitleTpPly.Text = "👥 TELEPORT TO OTHER PLAYERS"
TitleTpPly.TextColor3 = Color3.fromRGB(0,170,255)
TitleTpPly.Font = Enum.Font.GothamBold
TitleTpPly.TextSize = 13

local RefreshPlayerBtn = Instance.new("TextButton")
RefreshPlayerBtn.Parent = PlayerTpPage
RefreshPlayerBtn.Size = UDim2.new(1,0,0,35)
RefreshPlayerBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
RefreshPlayerBtn.Text = "🔄 Refresh / Scan Pemain"
RefreshPlayerBtn.TextColor3 = Color3.new(1,1,1)
RefreshPlayerBtn.Font = Enum.Font.GothamBold
RefreshPlayerBtn.TextSize = 12
local rpc = Instance.new("UICorner")
rpc.Parent = RefreshPlayerBtn

local PlayerListContainer = Instance.new("ScrollingFrame")
PlayerListContainer.Parent = PlayerTpPage
PlayerListContainer.Size = UDim2.new(1,0,0,210)
PlayerListContainer.BackgroundTransparency = 1
PlayerListContainer.CanvasSize = UDim2.fromOffset(0,0)
PlayerListContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
PlayerListContainer.ScrollBarThickness = 3
local ListLayout = Instance.new("UIListLayout")
ListLayout.Parent = PlayerListContainer
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Padding = UDim.new(0, 5)

local function ScanAndDisplayPlayers()
	for _, child in ipairs(PlayerListContainer:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local pBtn = Instance.new("TextButton")
			pBtn.Parent = PlayerListContainer
			pBtn.Size = UDim2.new(1,0,0,32)
			pBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
			pBtn.Text = "👤 " .. plr.Name .. " (" .. plr.DisplayName .. ")"
			pBtn.TextColor3 = Color3.new(1,1,1)
			pBtn.Font = Enum.Font.GothamMedium
			pBtn.TextSize = 11
			local pbc = Instance.new("UICorner")
			pbc.Parent = pBtn
			App.Connect(pBtn.MouseButton1Click, function()
				pcall(function()
					local hrpTarget = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
					local myHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
					if hrpTarget and myHrp then myHrp.CFrame = hrpTarget.CFrame + Vector3.new(0, 5, 0) end
				end)
			end)
		end
	end
end

App.Connect(RefreshPlayerBtn.MouseButton1Click, ScanAndDisplayPlayers)
App.Spawn(function() task.wait(2); ScanAndDisplayPlayers() end)

----------------------------------------------------
-- 9. PRIVACY & ANTI-ADMIN PAGE
----------------------------------------------------
local TitlePrv = Instance.new("TextLabel")
TitlePrv.Parent = PrivacyPage
TitlePrv.Size = UDim2.new(1,0,0,30)
TitlePrv.BackgroundTransparency = 1
TitlePrv.Text = "🛡️ PRIVACY & ANTI-ADMIN"
TitlePrv.TextColor3 = Color3.fromRGB(0,170,255)
TitlePrv.Font = Enum.Font.GothamBold
TitlePrv.TextSize = 13

local FakeNameBox = Instance.new("TextBox")
FakeNameBox.Parent = PrivacyPage
FakeNameBox.Size = UDim2.new(1,0,0,35)
FakeNameBox.BackgroundColor3 = Color3.fromRGB(35,35,45)
FakeNameBox.PlaceholderText = "Nama Samaran (Cth: DARUS HUB)"
FakeNameBox.Text = "DARUS HUB"
FakeNameBox.TextColor3 = Color3.new(1,1,1)
local fnc = Instance.new("UICorner")
fnc.Parent = FakeNameBox
App.Connect(FakeNameBox.FocusLost, function() State.FakeNameInput = FakeNameBox.Text end)

AddToggle(PrivacyPage, "Privacy Mode (Hide Name)", function(v)
	State.HideNameRunning = v
	if not v then App.Restore("privacy") end
end)
App.Spawn(function()
	while App.Wait(0.5) do
		if State.HideNameRunning then
			local character = LocalPlayer.Character
			local head = character and character:FindFirstChild("Head")
			if head then
				for _, child in ipairs(head:GetDescendants()) do
					if child:IsA("TextLabel") or child:IsA("TextButton") then
						local saved = App.snapshots.privacy and App.snapshots.privacy[child]
						local original = saved and saved.Text or child.Text
						if original:find(LocalPlayer.Name,1,true) or original:find(LocalPlayer.DisplayName,1,true) then
							App.Set("privacy",child,"Text",State.FakeNameInput)
						end
					end
				end
			end
		end
	end
end)

local AntiAdminToggleBtn = Instance.new("TextButton")
AntiAdminToggleBtn.Parent = PrivacyPage
AntiAdminToggleBtn.Size = UDim2.new(1,0,0,35)
AntiAdminToggleBtn.BackgroundColor3 = State.Config.AntiAdminEnabled and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(30, 30, 40)
AntiAdminToggleBtn.Text = "  Anti-Admin Protect (MPG Group): " .. (State.Config.AntiAdminEnabled and "[ON]" or "[OFF]")
AntiAdminToggleBtn.TextColor3 = Color3.new(1,1,1)
AntiAdminToggleBtn.Font = Enum.Font.Gotham
AntiAdminToggleBtn.TextXAlignment = Enum.TextXAlignment.Left
local aac = Instance.new("UICorner")
aac.Parent = AntiAdminToggleBtn

App.Connect(AntiAdminToggleBtn.MouseButton1Click, function()
	State.Config.AntiAdminEnabled = not State.Config.AntiAdminEnabled
	local active = State.Config.AntiAdminEnabled
	AntiAdminToggleBtn.Text = "  Anti-Admin Protect (MPG Group): " .. (active and "[ON]" or "[OFF]")
	AntiAdminToggleBtn.BackgroundColor3 = active and Color3.fromRGB(180, 50, 50) or Color3.fromRGB(30, 30, 40)
	SaveConfig()
end)

local function CheckPlayerIsAdmin(player)
	local success, rank = pcall(function() return player:GetRankInGroup(State.Config.TargetGroupId or 7019573) end)
	return success and rank and rank > 1
end

App.Connect(Players.PlayerAdded, function(player)
	if player ~= LocalPlayer then
		App.Spawn(function()
			task.wait(1.5)
			if State.Config.AntiAdminEnabled and CheckPlayerIsAdmin(player) then
				TeleportService:Teleport(game.PlaceId, LocalPlayer)
			end
		end)
	end
end)

----------------------------------------------------
-- 10. SETTINGS & WEBHOOK PAGE (SECRET & FORGOTTEN EXCLUSIVE)
----------------------------------------------------
local TitleSet = Instance.new("TextLabel")
TitleSet.Parent = SettingsPage
TitleSet.Size = UDim2.new(1,0,0,30)
TitleSet.BackgroundTransparency = 1
TitleSet.Text = "⚙️ SETTINGS & WEBHOOK SECRET / FORGOTTEN"
TitleSet.TextColor3 = Color3.fromRGB(0,170,255)
TitleSet.Font = Enum.Font.GothamBold
TitleSet.TextSize = 13

local AntiLagBtn = Instance.new("TextButton")
AntiLagBtn.Parent = SettingsPage
AntiLagBtn.Size = UDim2.new(1,0,0,35)
AntiLagBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 180)
AntiLagBtn.Text = "⚡ Aktifkan Anti-Lag (Boost FPS)"
AntiLagBtn.TextColor3 = Color3.new(1,1,1)
AntiLagBtn.Font = Enum.Font.GothamBold
local alc = Instance.new("UICorner")
alc.Parent = AntiLagBtn
App.Connect(AntiLagBtn.MouseButton1Click, function()
	pcall(function()
		App.Set("lighting",Lighting,"GlobalShadows",false)
		App.Set("lighting",Lighting,"FogEnd",999999)
		for _, v in ipairs(Workspace:GetDescendants()) do if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then App.Set("lighting",v,"Enabled",false) end end
		AntiLagBtn.Text = "⚡ Anti-Lag Aktif!"
	end)
end)

local WebhookToggleBtn = Instance.new("TextButton")
WebhookToggleBtn.Parent = SettingsPage
WebhookToggleBtn.Size = UDim2.new(1,0,0,35)
WebhookToggleBtn.BackgroundColor3 = State.Config.WebhookEnabled and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(30, 30, 40)
WebhookToggleBtn.Text = "  Webhook Secret & Forgotten: " .. (State.Config.WebhookEnabled and "[ON]" or "[OFF]")
WebhookToggleBtn.TextColor3 = Color3.new(1,1,1)
WebhookToggleBtn.Font = Enum.Font.Gotham
WebhookToggleBtn.TextXAlignment = Enum.TextXAlignment.Left
local wtc = Instance.new("UICorner")
wtc.Parent = WebhookToggleBtn

App.Connect(WebhookToggleBtn.MouseButton1Click, function()
	State.Config.WebhookEnabled = not State.Config.WebhookEnabled
	WebhookToggleBtn.Text = "  Webhook Secret & Forgotten: " .. (State.Config.WebhookEnabled and "[ON]" or "[OFF]")
	WebhookToggleBtn.BackgroundColor3 = State.Config.WebhookEnabled and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(30, 30, 40)
	SaveConfig()
end)

local WebhookBox = Instance.new("TextBox")
WebhookBox.Parent = SettingsPage
WebhookBox.Size = UDim2.new(1,0,0,35)
WebhookBox.BackgroundColor3 = Color3.fromRGB(35,35,45)
WebhookBox.PlaceholderText = "Paste Discord Webhook URL di sini..."
WebhookBox.Text = tostring(State.Config.WebhookUrl or "")
WebhookBox.TextColor3 = Color3.new(1,1,1)
local wbc = Instance.new("UICorner")
wbc.Parent = WebhookBox
App.Connect(WebhookBox.FocusLost, function()
	State.Config.WebhookUrl = WebhookBox.Text
	SaveConfig()
end)

local TestWebhookBtn = Instance.new("TextButton")
TestWebhookBtn.Parent = SettingsPage
TestWebhookBtn.Size = UDim2.new(1,0,0,35)
TestWebhookBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
TestWebhookBtn.Text = "🧪 Test Kirim Webhook ke Discord"
TestWebhookBtn.TextColor3 = Color3.new(1,1,1)
TestWebhookBtn.Font = Enum.Font.GothamBold
TestWebhookBtn.TextSize = 13
local twc = Instance.new("UICorner")
twc.Parent = TestWebhookBtn

App.Connect(TestWebhookBtn.MouseButton1Click, function()
	if App.webhookTestBusy then return end
	App.webhookTestBusy = true
	local sent = App.PostWebhook({content = "Darus Hub: tes koneksi webhook."})
	TestWebhookBtn.Text = sent and "✅ Pesan Test Berhasil Dikirim!" or "❌ Webhook gagal; periksa status"
	App.Wait(2)
	App.webhookTestBusy = false
	if App.running then TestWebhookBtn.Text = "🧪 Test Kirim Webhook ke Discord" end
end)

local SaveConfigBtn = Instance.new("TextButton")
SaveConfigBtn.Parent = SettingsPage
SaveConfigBtn.Size = UDim2.new(1,0,0,35)
SaveConfigBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
SaveConfigBtn.Text = "💾 Simpan Konfigurasi"
SaveConfigBtn.TextColor3 = Color3.new(1,1,1)
SaveConfigBtn.Font = Enum.Font.GothamBold
local scc = Instance.new("UICorner")
scc.Parent = SaveConfigBtn
App.Connect(SaveConfigBtn.MouseButton1Click, function()
	local saved = SaveConfig()
	SaveConfigBtn.Text = saved and "✅ Config Berhasil Disimpan!" or "❌ Config tidak tersimpan"
	task.wait(1.5)
	SaveConfigBtn.Text = "💾 Simpan Konfigurasi"
end)

local ResetConfigBtn = Instance.new("TextButton")
ResetConfigBtn.Parent = SettingsPage
ResetConfigBtn.Size = UDim2.new(1,0,0,35)
ResetConfigBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
ResetConfigBtn.Text = "🔄 Reset Konfigurasi"
ResetConfigBtn.TextColor3 = Color3.new(1,1,1)
ResetConfigBtn.Font = Enum.Font.GothamBold
local rcc = Instance.new("UICorner")
rcc.Parent = ResetConfigBtn
App.Connect(ResetConfigBtn.MouseButton1Click, function()
	local saved = ResetConfig()
	ResetConfigBtn.Text = saved and "🔄 Config Direset!" or "🔄 Reset sesi; penyimpanan gagal"
	task.wait(1.5)
	ResetConfigBtn.Text = "🔄 Reset Konfigurasi"
end)

local CredLbl = Instance.new("TextLabel")
CredLbl.Parent = CreditsPage
CredLbl.Size = UDim2.new(1,0,1,0)
CredLbl.BackgroundTransparency = 1
CredLbl.Text = "Darus Hub by Darusss30 | Original: UbeyDev / UBEYHUB.lua"
CredLbl.TextColor3 = Color3.new(1,1,1)
CredLbl.Font = Enum.Font.GothamBold
CredLbl.TextSize = 20
CredLbl.TextWrapped = true

----------------------------------------------------
-- FLOATING BUTTON
----------------------------------------------------
local Float = Instance.new("TextButton")
Float.Parent = Gui
Float.Size = UDim2.new(0,65,0,65)
Float.Position = UDim2.new(0,20,0,120)
Float.Text = "DH"
Float.Name = "DarusToggle"
Float.TextSize = 20
Float.TextColor3 = Color3.fromRGB(0,170,255)
Float.BackgroundColor3 = Color3.fromRGB(20,20,25)
local flCorner = Instance.new("UICorner")
flCorner.CornerRadius = UDim.new(1,0)
flCorner.Parent = Float
MakeDraggable(Float)

App.Connect(Float.MouseButton1Click, function()
	if not App.dragSuppressed[Float] or os.clock() >= App.dragSuppressed[Float] then Main.Visible = not Main.Visible end
end)

function App.RefreshConfig()
	BiteDelayBox.Text = State.Config.BiteDelay
	SellTimerBox.Text = State.Config.AutoSellTimer
	SpotLabel.Text = "Lokasi Saat Ini: " .. State.SelectedFishingSpot
	WebhookBox.Text = State.Config.WebhookUrl
	WebhookToggleBtn.Text = "  Webhook Secret & Forgotten: " .. (State.Config.WebhookEnabled and "[ON]" or "[OFF]")
	WebhookToggleBtn.BackgroundColor3 = State.Config.WebhookEnabled and Color3.fromRGB(0,150,100) or Color3.fromRGB(30,30,40)
	AntiAdminToggleBtn.Text = "  Anti-Admin Protect (MPG Group): " .. (State.Config.AntiAdminEnabled and "[ON]" or "[OFF]")
	AntiAdminToggleBtn.BackgroundColor3 = State.Config.AntiAdminEnabled and Color3.fromRGB(180,50,50) or Color3.fromRGB(30,30,40)
	for _, refresh in ipairs(App.configViews or {}) do refresh() end
end

App.Connect(LocalPlayer.CharacterRemoving, function()
	App.fishingEpoch += 1
	App.summitEpoch = (App.summitEpoch or 0)+1
	if App.tween then App.tween:Cancel(); App.tween=nil end
	for _, group in ipairs({"rod","platform","privacy","speed","headless","sellPosition"}) do App.Restore(group) end
end)
App.Connect(LocalPlayer.CharacterAdded, function(character)
	if not App.Wait(0.5,function() return LocalPlayer.Character == character end) then return end
	if State.AutoFishingEventRunning and State.FishingMode == "spot" and not State.Selling then
		App.Teleport(FishingSpots[State.SelectedFishingSpot]+Vector3.new(0,5,0))
	end
	local head = character:FindFirstChild("Head")
	if autoRgbActive and head and not head:FindFirstChild("DarusHeadFire") then
		local fire = Instance.new("Fire",head)
		fire.Name, fire.Size, fire.Heat = "DarusHeadFire",5,15
		App.owned[fire] = true
	end
end)
