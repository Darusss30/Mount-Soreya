-- Deterministic client mock. This exercises lifecycle and UI behavior, not
-- Roblox physics, replication, rendering, or the target game's server rules.
local now = 0
local minute = 30
local os = {clock = function() return now end, date = function(format) return format == "%M" and tostring(minute) or "2026-10-19T12:30:00Z" end}
local function tick() return now end
local scheduled = {}
local task = {}
function task.defer(callback)
	local thread = coroutine.create(callback)
	scheduled[thread] = now
	return thread
end
function task.wait(seconds) return coroutine.yield(seconds or 0.03) end
function task.cancel(thread) scheduled[thread] = nil; coroutine.close(thread) end
local function step(seconds)
	local deadline = now + seconds
	local iterations = 0
	while true do
		local nextThread, nextTime
		for thread, wakeAt in pairs(scheduled) do
			if wakeAt <= deadline and (not nextTime or wakeAt < nextTime) then nextThread, nextTime = thread, wakeAt end
		end
		if not nextThread then break end
		now = nextTime
		scheduled[nextThread] = nil
		local ok, delay = coroutine.resume(nextThread)
		assert(ok, tostring(delay))
		if coroutine.status(nextThread) ~= "dead" then scheduled[nextThread] = now + math.max(delay or 0.001, 0.001) end
		iterations += 1
		assert(iterations < 100000, "Scheduler did not converge")
	end
	now = deadline
end

local signals = {}
local function Signal()
	local signal = {listeners = {}}
	function signal:Connect(callback)
		local connection = {Connected = true, callback = callback}
		function connection:Disconnect() self.Connected = false end
		table.insert(self.listeners, connection)
		return connection
	end
	function signal:Fire(...)
		for _, connection in ipairs(table.clone(self.listeners)) do
			if connection.Connected then connection.callback(...) end
		end
	end
	table.insert(signals, signal)
	return signal
end
local function connectionCount()
	local count = 0
	for _, signal in ipairs(signals) do
		for _, connection in ipairs(signal.listeners) do if connection.Connected then count += 1 end end
	end
	return count
end

local Vector = {}
Vector.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self.X^2 + self.Y^2 + self.Z^2) end
end
local function vector(x, y, z) return setmetatable({X = x, Y = y, Z = z or 0}, Vector) end
Vector.__add = function(a,b) return vector(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
Vector.__sub = function(a,b) return vector(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
Vector.__mul = function(a,b) return vector(a.X*b,a.Y*b,a.Z*b) end
local Vector2, Vector3 = {new = vector}, {new = vector, zero = vector(0,0,0)}
local CFrame = {}
local CF = {}
CF.__index = {Inverse=function(self) return CFrame.new(self.Position * -1) end}
function CFrame.new(x,y,z)
	return setmetatable({Position = type(x) == "table" and x or vector(x or 0,y or 0,z or 0), RightVector=vector(1,0,0), LookVector=vector(0,0,-1)},CF)
end
CF.__add = function(cf, delta) return CFrame.new(cf.Position+delta) end
CF.__mul = function(a,b) return CFrame.new(a.Position+b.Position) end
local TweenInfo = {new = function(duration) return {Time=duration} end}
local ColorSequence = {new = function(value) return value end}
local ColorSequenceKeypoint = {new = function(...) return {...} end}
local UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end}
local UDim2 = {}
function UDim2.new(x, xo, y, yo) return {X = UDim.new(x,xo), Y = UDim.new(y,yo)} end
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
local Color3 = {new = vector, fromRGB = vector}
local Enum = setmetatable({}, {__index = function(self, group)
	local values = setmetatable({}, {__index = function(_, item) return group .. "." .. item end})
	rawset(self, group, values)
	return values
end})

local methods = {}
local function notifyAncestors(parent, name, object)
	while parent do parent[name]:Fire(object); parent = parent.Parent end
end
local Object = {
	__index = function(self,key)
		if key == "Position" and self:IsA("BasePart") then return self.CFrame.Position end
		if methods[key] then return methods[key] end
		if self.properties[key] ~= nil then return self.properties[key] end
		for _, child in ipairs(self.children) do if child.Name == key then return child end end
		return nil
	end,
	__newindex = function(self,key,value)
		if key == "Parent" then
			local old = self.properties.Parent
			if old then
				notifyAncestors(old,"DescendantRemoving",self)
				local index = table.find(old.children,self)
				if index then table.remove(old.children,index) end
			end
			self.properties.Parent = value
			if value then table.insert(value.children,self); notifyAncestors(value,"DescendantAdded",self); value.ChildAdded:Fire(self) end
		else self.properties[key] = value end
	end,
}
local Instance = {}
function Instance.new(class, parent)
	local object = setmetatable({properties = {
		ClassName = class, Name = class, Visible = true, Enabled = true, Health = 100,
		CanCollide = true, Transparency = 0.25, Material = "Plastic", ScrollingEnabled = true,
		AbsoluteSize = vector(800,600), AbsolutePosition = vector(0,0), CFrame = CFrame.new(),
		HoldDuration = 1, MaxActivationDistance = 10, Text = "", beginCount = 0, endCount = 0,
		PlatformStand = false, WalkSpeed = 16, Value = 0, Size=vector(2,2,2), Position=UDim2.fromOffset(0,0),
	}, children = {}, attributes = {}, states = {}, propertySignals = {}}, Object)
	for _, name in ipairs({"Destroying","DescendantAdded","DescendantRemoving","ChildAdded","MouseButton1Click","InputBegan","InputChanged","InputEnded","CharacterRemoving","CharacterAdded","PlayerAdded","Idled","FocusLost","OnClientEvent","WindowFocusReleased"}) do object[name] = Signal() end
	object.Parent = parent
	return object
end
function methods:IsA(class)
	if class == self.ClassName then return true end
	if class == "BasePart" then return self.ClassName == "Part" or self.ClassName == "MeshPart" end
	if class == "GuiObject" then return table.find({"Frame","ScrollingFrame","TextLabel","TextButton","ImageButton"}, self.ClassName) ~= nil end
	return false
end
function methods:GetChildren() return table.clone(self.children) end
function methods:GetDescendants()
	local result = {}
	for _, child in ipairs(self.children) do table.insert(result,child); for _, nested in ipairs(child:GetDescendants()) do table.insert(result,nested) end end
	return result
end
function methods:FindFirstChild(name)
	for _, child in ipairs(self.children) do if child.Name == name then return child end end
	return nil
end
function methods:WaitForChild(name) return assert(self:FindFirstChild(name), name) end
function methods:FindFirstChildOfClass(class)
	for _, child in ipairs(self.children) do if child.ClassName == class then return child end end
	return nil
end
function methods:FindFirstChildWhichIsA(class, recursive)
	for _, child in ipairs(recursive and self:GetDescendants() or self.children) do if child:IsA(class) then return child end end
	return nil
end
function methods:IsDescendantOf(ancestor)
	local parent = self.Parent
	while parent do if parent == ancestor then return true end; parent = parent.Parent end
	return false
end
function methods:GetAttribute(name) return self.attributes[name] end
function methods:GetAttributes() return table.clone(self.attributes) end
function methods:SetAttribute(name,value) self.attributes[name]=value end
function methods:GetPropertyChangedSignal(name)
	if not self.propertySignals[name] then self.propertySignals[name] = Signal() end
	return self.propertySignals[name]
end
function methods:Destroy()
	if self.destroyed then return end
	self.Destroying:Fire()
	for _, child in ipairs(self:GetChildren()) do child:Destroy() end
	self.Parent = nil
	self.destroyed = true
	for _, value in pairs(self.properties) do
		if type(value) == "table" and value.listeners then for _, c in ipairs(value.listeners) do c:Disconnect() end end
	end
end
function methods:GetStateEnabled(state) if self.states[state] == nil then return true end; return self.states[state] end
function methods:SetStateEnabled(state, value) self.states[state] = value end
function methods:EquipTool(tool) tool.Parent = self.Parent end
function methods:InputHoldBegin() self.beginCount += 1 end
function methods:InputHoldEnd() self.endCount += 1 end
function methods:Invoke() return self.OnInvoke() end
function methods:InvokeServer(...) return self.serverCallback(...) end
function methods:FireServer(...) if self.serverCallback then return self.serverCallback(...) end end
function methods:TweenSize(size) self.Size=size end
function methods:Clone()
	local clone=Instance.new(self.ClassName)
	for key,value in pairs(self.properties) do
		if key~="Parent" and not (type(value)=="table" and value.listeners) then clone[key]=value end
	end
	for _,child in ipairs(self.children) do child:Clone().Parent=clone end
	return clone
end
function methods:RequestStreamAroundAsync() end
function methods:GetPlayers() return {self.LocalPlayer} end
function methods:GetRankInGroup() return 0 end
function methods:Teleport() end
function methods:TeleportToPlaceInstance() end
function methods:GetValue() return self.Value end
function methods:CaptureController() end
function methods:ClickButton2() end
function methods:Create(object, info, properties)
	local tween = {Completed=Signal(), cancelled=false}
	function tween:Play()
		self.thread = task.defer(function()
			task.wait(info.Time)
			if self.cancelled then return end
			for key,value in pairs(properties) do object[key]=value end
			self.Completed:Fire(Enum.PlaybackState.Completed)
		end)
	end
	function tween:Cancel()
		self.cancelled = true
		if self.thread and coroutine.status(self.thread) ~= "dead" then task.cancel(self.thread) end
		self.Completed:Fire(Enum.PlaybackState.Cancelled)
	end
	return tween
end

local services = {}
for _, name in ipairs({"HttpService","Players","ReplicatedStorage","VirtualUser","CoreGui","UserInputService","TeleportService","Stats","Lighting","Workspace","TweenService"}) do services[name] = Instance.new(name) end
services.Lighting.GlobalShadows, services.Lighting.FogEnd = true, 1000
services.Stats.Network = {ServerStatsItem = {["Data Ping"] = {GetValue=function() return 50 end}}}
local game = {PlaceId=1,JobId="test",GetService=function(_,name) return assert(services[name],name) end}
local warnings = {}
local function warn(message) table.insert(warnings,message) end
local encoded, files = {}, {}
function methods:JSONEncode(value)
	local key = "mock-json-" .. tostring(#encoded+1)
	encoded[#encoded+1] = value
	encoded[key] = value
	return key
end
function methods:JSONDecode(value) return assert(encoded[value],"invalid JSON") end
local function writefile(path,value) files[path]=value end
local function readfile(path) return assert(files[path],"file missing") end
local function isfile(path) return files[path]~=nil end
local requestStatus, requestCalls = 204, 0
local function request(_) requestCalls+=1; return {StatusCode=requestStatus} end
local workspace = services.Workspace
local player = Instance.new("Player")
player.Name, player.DisplayName, player.UserId = "Tester", "Test Player", 123
services.Players.LocalPlayer=player
local playerGui = Instance.new("PlayerGui",player)
local backpack = Instance.new("Backpack",player)
local function character()
	local model=Instance.new("Model",workspace)
	Instance.new("Humanoid",model)
	local root=Instance.new("Part",model); root.Name="HumanoidRootPart"
	local head=Instance.new("Part",model); head.Name="Head"
	local nameLabel=Instance.new("TextLabel",head); nameLabel.Text="Tester"
	return model
end
player.Character=character()
local halos=Instance.new("Folder",services.ReplicatedStorage); halos.Name="HaloKenyal"
local haloModel=Instance.new("Model",halos); haloModel.Name="TestHalo"
local haloHandle=Instance.new("Part",haloModel); haloHandle.Name="Handle"; haloHandle.CFrame=CFrame.new(0,0,0)
local haloRing=Instance.new("Part",haloModel); haloRing.Name="Ring"; haloRing.CFrame=CFrame.new(2,0,0)
Instance.new("Script",haloModel)
local casts, reels = 0, 0
local notify
local function rodFor(model, fastBite)
	local rod=Instance.new("Tool",model); rod.Name="Withering Rod"
	local mechanics=Instance.new("Folder",rod); mechanics.Name="Mechanics"
	local settings=Instance.new("Folder",mechanics); settings.Name="Settings"
	local delay=Instance.new("NumberValue",settings); delay.Name="Time_before_getfish"; delay.Value=2
	local mini=Instance.new("BoolValue",settings); mini.Name="EnableMiniGame"; mini.Value=true
	local luck=Instance.new("NumberValue",settings); luck.Name="Luck"; luck.Value=1
	local weight=Instance.new("IntValue",settings); weight.Name="MaxWeight"; weight.Value=10
	rod:SetAttribute("LuckMultiplier",2)
	rod:SetAttribute("Description","Example rod")
	local remotes=Instance.new("Folder",mechanics); remotes.Name="Remotes"
	notify=Instance.new("RemoteEvent",remotes); notify.Name="NotifyClient"
	local currentNotify=notify
	local cast=Instance.new("RemoteEvent",remotes); cast.Name="CastEvent"
	cast.serverCallback=function(charging)
		if charging==false then casts+=1; if fastBite then currentNotify.OnClientEvent:Fire("Bite") end end
	end
	local reel=Instance.new("RemoteEvent",remotes); reel.Name="MiniGame"
	reel.serverCallback=function() reels+=1 end
	return rod,delay,mini
end
local rod,rodDelay,rodMini = rodFor(player.Character,true)

local function RunHub()
-- @DARUS_SOURCE@
end

local passed=0
local function check(condition,message) assert(condition,message); passed+=1 end
local function findText(fragment,class,scope)
	for _,object in ipairs((scope or playerGui):GetDescendants()) do
		if object.Text and object.Text:find(fragment,1,true) and (not class or object:IsA(class)) then return object end
	end
	error("UI not found: " .. fragment)
end
local function click(fragment,scope) findText(fragment,"TextButton",scope).MouseButton1Click:Fire(); step(0) end
local function box(placeholder)
	for _,object in ipairs(playerGui:GetDescendants()) do
		if object:IsA("TextBox") and object.PlaceholderText and object.PlaceholderText:find(placeholder,1,true) then return object end
	end
	error("TextBox not found: " .. placeholder)
end
local function fill(placeholder,value)
	local target=box(placeholder); target.Text=value; target.FocusLost:Fire(); step(0); return target
end
local function input(kind,x,y) return {UserInputType=Enum.UserInputType[kind],Position=vector(x,y)} end

-- Invalid/corrupt saved config must not prevent startup.
files.DarusHub_Config_json=nil
files["DarusHub_Config.json"]="not-json"
RunHub(); step(0)
local gui=playerGui:FindFirstChild("DarusHub")
local main=gui:FindFirstChildOfClass("Frame")
check(main.Visible,"main opens without key")
check(findText("Fishing & Sell") and findText("UNFAVORITE BY FILTER") and findText("AUTO SUMMIT"),"correct UBEYHUB feature base")
for _,name in ipairs({"Fishing & Sell","⭐ Favorite","Galatama","Teleport Shop","Summit","Player","Halo Kepala","Teleport Player","Privacy","Settings","Credits"}) do
	check(findText(name,"TextButton")~=nil,"tab preserved: " .. name)
end
check(#warnings>0,"corrupt config diagnosed")
check(fill("Bite Delay","-50").Text=="0","negative bite delay clamped")
check(fill("Bite Delay","NaN").Text=="0.5","invalid bite delay reset")
check(fill("Jeda Waktu Jual","0").Text=="0.1","sell timer cannot spin at zero")
check(fill("Jeda Waktu Jual","1e999").Text=="5","infinite timer rejected")

click("Smart Auto Fishing (Di Tempat Saja)")
step(1.3)
check(casts>0 and reels>0,"instant Bite caught by subscription before cast")
check(rodDelay.Value==0.05 and not rodMini.Value,"rod settings applied")
click("Smart Auto Fishing + Teleport")
check(findText("Smart Auto Fishing (Di Tempat Saja)","TextButton").Text:find("[OFF]",1,true),"fishing modes mutually exclusive")
local before=casts
step(1.3)
check(casts-before<=2,"single fishing worker after switching")
click("Smart Auto Fishing + Teleport")
local beforeOff=reels
step(1)
check(reels==beforeOff and rodDelay.Value==2 and rodMini.Value,"OFF cancels reel and restores rod")

-- Stop while waiting for a delayed bite; old notifications cannot finish it.
rod.Parent=backpack
local slowRod=rodFor(player.Character,false)
click("Smart Auto Fishing (Di Tempat Saja)"); step(0.3)
local waitingReels=reels
click("Smart Auto Fishing (Di Tempat Saja)")
notify.OnClientEvent:Fire("Bite"); step(1)
check(reels==waitingReels,"late Bite after OFF ignored")
slowRod.Parent=backpack; rod.Parent=player.Character

-- OFF/ON does not leak the previous waiting cycle across respawn.
click("Smart Auto Fishing (Di Tempat Saja)"); step(0.3)
local old=player.Character
player.CharacterRemoving:Fire(old); player.Character=nil; step(0.2)
check(rodDelay.Value==2 and rodMini.Value,"respawn restores old rod")
local respawnReels=reels
step(1)
check(reels==respawnReels,"no reel with missing character")
player.Character=character(); rod,rodDelay,rodMini=rodFor(player.Character,true)
player.CharacterAdded:Fire(player.Character); step(1.3)
check(reels>respawnReels,"fishing resumes on new character")
click("Smart Auto Fishing (Di Tempat Saja)")

-- Favorite selects actual state, handles literal 8-Bit, and persists filters.
local favHeader=findText("Fav Filter Rarity","TextButton")
local favScope=favHeader.Parent
click("SELECT ALL",favScope)
click("Common",favScope)
click("SELECT ALL",favScope)
check(findText("Common","TextButton",favScope).Text:find("[✓]",1,true),"select all recomputes mixed selection")
click("SELECT ALL",favScope)
check(findText("Common","TextButton",favScope).Text:find("[ ]",1,true),"unselect all clears selected state")
local remoteFolder=Instance.new("Folder",services.ReplicatedStorage); remoteFolder.Name="Remote"
local inventory=Instance.new("Folder",remoteFolder); inventory.Name="Inventaris"
local getAll=Instance.new("RemoteFunction",inventory); getAll.Name="AmbilSemua"
local mancing=Instance.new("Folder",remoteFolder); mancing.Name="Mancing"
local favorite=Instance.new("RemoteEvent",mancing); favorite.Name="TandaiFavorit"
local favorites={}
favorite.serverCallback=function(id,value) table.insert(favorites,{id,value}) end
getAll.serverCallback=function() return {{uid="fish8",nama="Test Fish",rarity="Common",mutasi="8-Bit",favorit=false}} end
local mutationScope=findText("Fav Filter Mutasi","TextButton").Parent
click("8-Bit",mutationScope)
click("AUTO FAVORITE"); step(3)
check(#favorites==1 and favorites[1][1]=="fish8","8-Bit matched literally")
click("AUTO FAVORITE")
click("Simpan Konfigurasi")
local saved=encoded[files["DarusHub_Config.json"]]
check(saved.FavMutations["8-Bit"]==true,"filter saved")
step(2)

-- Slow remote times out without creating repeat requests; UI still works.
local sell=Instance.new("RemoteFunction",mancing); sell.Name="JualSemua"
local sellCalls=0
sell.serverCallback=function() sellCalls+=1; task.wait(30); return true end
fill("Jeda Waktu Jual","0.1")
local root=player.Character.HumanoidRootPart
local initialPosition=root.Position
click("Auto Sell Timer"); step(18)
check(sellCalls==1,"one in-flight sell request after timeout")
check(root.Position.X==initialPosition.X and root.Position.Y==initialPosition.Y,"sell returns to original spot even with fishing OFF")
step(7)
check(sellCalls==1,"no duplicate sell while server pending")
click("Auto Sell Timer")

-- Statistics work without targets or automatic stops.
step(15)
click("Statistik")
local catchPage=findText("STATISTIK SESI","TextLabel").Parent
check(catchPage.Visible,"statistics navigation opens")
local hasTarget=false
for _,object in ipairs(playerGui:GetDescendants()) do
    if object.Text and (object.Text:find("Pantau Target",1,true) or object.Text=="Target & Statistik") then hasTarget=true end
end
check(not hasTarget and not playerGui.DarusHub:FindFirstChild("TargetCatchNotification"),"target UI and notification removed")
notify.OnClientEvent:Fire("GotFish",{uid="catch1",baseName="Test Fish",rarity="Mythical",mutation="Normal",chance="600K"}); step(0)
notify.OnClientEvent:Fire("GotFish",{uid="catch2",baseName="Secret Fish",rarity="Secret",mutation="Normal"}); step(0)
check(findText("Tangkapan: 2","TextLabel",catchPage)~=nil,"received catches counted")
notify.OnClientEvent:Fire("GotFish",{uid="catch2",baseName="Secret Fish",rarity="Secret",chance="1M"}); step(0)
check(findText("Ikan terlangka: Secret Fish | Normal | Secret | 1 dari 1M","TextLabel",catchPage)~=nil,"late duplicate-ID odds promote Secret 1M above Mythical 600K")
check(findText("Tangkapan: 2","TextLabel",catchPage)~=nil,"late odds do not duplicate count")
check(findText("Peluang terbaca: 2/2","TextLabel",catchPage)~=nil,"resolved odds coverage tracked")
check(findText("#2  Secret Fish | Normal | Secret | 1 dari 1M","TextLabel",catchPage)~=nil,"history enriched by delayed odds")
notify.OnClientEvent:Fire("Bite",{}); notify.OnClientEvent:Fire("GotFish",{}); step(0)
check(findText("Tangkapan: 2","TextLabel",catchPage)~=nil,"non-catch and malformed events ignored")
click("Reset Statistik Sesi")
notify.OnClientEvent:Fire("GotFish",{uid="catch2",baseName="Secret Fish",chance="2M"}); step(0)
check(findText("Tangkapan: 0","TextLabel",catchPage)~=nil,"reset prevents duplicate events from prior session")
fill("Nama ikan dilindungi","Keep Fish, Another Fish")
fill("Mutasi dilindungi","Gold, 8-Bit")
click("Simpan Konfigurasi")
local catchSaved=encoded[files["DarusHub_Config.json"]]
check(catchSaved.TargetName==nil and catchSaved.ProtectMutations=="Gold, 8-Bit","target settings removed; protection settings saved")

-- Bulk sale is blocked even for favorited fish: server sell exclusions are unknown.
sell.serverCallback=function() sellCalls+=1; return true end
local guardedPosition=root.Position
local function attemptSale(data)
	getAll.serverCallback=function() return data end
	local count=sellCalls
	click("Auto Sell Timer"); step(7.5); click("Auto Sell Timer")
	return sellCalls-count
end
check(attemptSale({{uid="p1",nama="Rare Fish",rarity="Secret",mutasi="Normal"}})==0,"default Secret protection blocks bulk sale")
check(attemptSale({{uid="p2",nama="Rare Fish",rarity="Forgotten",mutasi="Normal"}})==0,"default Forgotten protection blocks bulk sale")
check(attemptSale({{uid="p3",nama="test fish",rarity="Common",mutasi="8-bit"}})==0,"protected mutation remains effective")
check(attemptSale({{uid="p4",nama="keep fish",rarity="Common",mutasi="Normal"}})==0,"custom protected name blocks sale")
check(attemptSale({{uid="p5",nama="Ordinary Fish",rarity="Common",mutasi="Gold"}})==0,"protected mutation blocks sale")
check(attemptSale({{uid="p6",nama="Ordinary Fish",rarity="Common",mutasi="Normal",favorit=true}})==0,"existing favorite blocks bulk sale")
check(attemptSale({{uid="p7",rarity="Common",mutasi="Normal"}})==0,"incomplete inventory cannot pass sale guard")
check(attemptSale({{uid="p8",nama="Ordinary Fish",rarity="Common",mutasi="Normal"},false})==0,"malformed row cannot be silently omitted")
check(attemptSale({items={}})==0,"unknown inventory envelope blocked")
check(attemptSale(nil)==0,"failed inventory response blocks sale")
check(attemptSale({{uid="p9",nama="Ordinary Fish",rarity="Common",mutasi="8xBit"}})==1,"safe fish sold and mutation pattern is literal")
check(root.Position.X==guardedPosition.X and root.Position.Y==guardedPosition.Y,"guarded sale restores initial position")
local beforeRace=sellCalls
getAll.serverCallback=function()
	notify.OnClientEvent:Fire("GotFish",{uid="lateCatch",baseName="New Fish",rarity="Secret",mutation="Normal"})
	task.wait(0.1)
	return {}
end
click("Auto Sell Timer"); step(7.5); click("Auto Sell Timer")
check(sellCalls==beforeRace,"catch during inventory read invalidates sale snapshot")
getAll.serverCallback=function() task.wait(2); return {} end
click("Auto Sell Timer"); step(7); click("Auto Sell Timer"); step(3)
check(sellCalls==beforeRace,"OFF during inventory read prevents delayed sale")
getAll.serverCallback=function() task.wait(2); return {} end
click("Auto Sell Timer"); step(7); click("Auto Sell Timer"); click("Auto Sell Timer"); step(2)
check(sellCalls==beforeRace,"OFF/ON invalidates the previous sale check")
click("Auto Sell Timer")
getAll.serverCallback=function() error("inventory unavailable") end
click("Auto Sell Timer"); step(7.5); click("Auto Sell Timer")
check(sellCalls==beforeRace,"inventory exception blocks sale")
getAll.serverCallback=function() return {} end

-- Visual changes restore both on OFF and shutdown.
local head=player.Character.Head
local nameLabel=head:FindFirstChildOfClass("TextLabel")
fill("Nama Samaran","Darus Test")
click("Privacy Mode"); step(0.6)
check(nameLabel.Text=="Darus Test","privacy replaces displayed name")
fill("Nama Samaran","Darus Next"); step(0.6)
check(nameLabel.Text=="Darus Next","privacy text updates after first substitution")
click("Privacy Mode")
check(nameLabel.Text=="Tester","privacy OFF restores original name")
fill("WalkSpeed","50"); click("Enable Headless"); click("Anti-Lag")
check(player.Character.Humanoid.WalkSpeed==50 and head.Transparency==1 and not services.Lighting.GlobalShadows,"visual options applied")
click("TestHalo")
local halo=head:FindFirstChild("CustomPlayerHalo")
check(halo~=nil and halo:FindFirstChildOfClass("Script")==nil,"halo strips scripts before attaching")
check(halo.Ring.Position.X-halo.Handle.Position.X==2,"halo parts retain relative position")
check(halo.Ring:FindFirstChildOfClass("WeldConstraint")~=nil,"all halo parts attached")

-- Summit movement cancels immediately and restores PlatformStand.
click("Auto Summit Loop"); step(0.3)
check(player.Character.Humanoid.PlatformStand,"summit uses platform state")
click("Auto Summit Loop"); step(0.3)
check(not player.Character.Humanoid.PlatformStand,"summit OFF restores platform state")
local stoppedPosition=root.Position
step(2)
check(root.Position.X==stoppedPosition.X and root.Position.Y==stoppedPosition.Y,"cancelled tween cannot move character later")

-- No external messages are sent: request() is a local stub.
fill("Paste Discord", "https://discord.com/api/webhooks/123/fake_test_token")
requestStatus=500
click("Test Kirim Webhook")
check(findText("Webhook gagal","TextButton")~=nil,"HTTP error does not claim webhook success")
step(2.1); requestStatus=204
click("Test Kirim Webhook")
check(findText("Pesan Test Berhasil","TextButton")~=nil,"HTTP 204 marks webhook success")
step(2.1)
click("Reset Konfigurasi"); step(0)
check(box("Bite Delay").Text=="0.5" and box("Jeda Waktu Jual").Text=="5","reset refreshes numeric UI")
check(box("Paste Discord").Text=="","reset clears webhook UI")
check(box("Rarity dilindungi").Text=="Secret, Forgotten","reset restores protection defaults")
check(findText("8-Bit","TextButton",mutationScope).Text:find("[ ]",1,true),"reset refreshes filter UI")
step(2)

-- Persistent listeners/worker counts must be stable across re-execution.
local baseline=connectionCount()
RunHub(); step(2)
check(gui.destroyed,"rerun shuts down previous GUI")
check(connectionCount()<=baseline,"rerun does not leak connections: " .. connectionCount() .. "/" .. baseline)
local cleanBaseline=connectionCount()
fill("Mutasi dilindungi","8-Bit")
click("Simpan Konfigurasi")
RunHub(); step(2)
check(connectionCount()==cleanBaseline,"consecutive fresh runs have stable connection count")
check(box("Mutasi dilindungi").Text=="8-Bit","saved catch settings reload")
check(findText("Tangkapan: 0","TextLabel")~=nil,"rerun begins fresh catch statistics")
check(player.Character.Humanoid.WalkSpeed==16 and head.Transparency==0.25 and services.Lighting.GlobalShadows,"rerun restores character and lighting")
check(head:FindFirstChild("CustomPlayerHalo")==nil,"rerun removes owned halo")
local newGui=playerGui:FindFirstChild("DarusHub")
local newMain=newGui:FindFirstChildOfClass("Frame")
local float=newGui:FindFirstChild("DarusToggle")
local finger=input("Touch",20,120)
float.InputBegan:Fire(finger); step(0)
local unrelated=input("Touch",300,300)
services.UserInputService.InputChanged:Fire(unrelated); step(0)
check(float.Position.X.Offset==20,"other finger cannot drag float")
finger.Position=vector(400,400)
services.UserInputService.InputChanged:Fire(finger); step(0)
services.UserInputService.InputEnded:Fire(finger); step(0)
float.MouseButton1Click:Fire(); step(0)
check(newMain.Visible,"drag does not toggle main")
step(0.4); float.MouseButton1Click:Fire(); step(0)
check(not newMain.Visible,"normal float click toggles main")
float.MouseButton1Click:Fire(); step(0)

-- Removed rod editor must not leave its menu behind.
local hasRodEditor=false
for _,object in ipairs(playerGui:GetDescendants()) do
    if object:IsA("TextButton") and object.Text=="Rod & Value" then hasRodEditor=true end
end
check(not hasRodEditor,"rod editor removed")

click("Statistik")
local oddsPage=findText("STATISTIK SESI","TextLabel").Parent
click("Reset Statistik Sesi")
local function catchOdds(name, chance, rarity)
	notify.OnClientEvent:Fire("GotFish", {baseName=name, chance=chance, rarity=rarity or "Secret", mutation="Normal"})
	step(0)
end
catchOdds("No Odds",nil,"Forgotten")
check(findText("Ikan terlangka: Belum ada data peluang","TextLabel",oddsPage)~=nil,"missing odds do not invent a ranking")
catchOdds("Great Whale","1 in 950K")
check(findText("Ikan terlangka: Great Whale | Normal | Secret | 1 dari 950K","TextLabel",oddsPage)~=nil,"950K denominator parsed")
catchOdds("Rare Secret","1 dari 20M")
check(findText("Ikan terlangka: Rare Secret | Normal | Secret | 1 dari 20M","TextLabel",oddsPage)~=nil,"20M beats 950K within same Secret category")
catchOdds("Great Whale Again",950000)
catchOdds("Higher Category","1/1000000","Forgotten")
check(findText("Ikan terlangka: Rare Secret | Normal | Secret | 1 dari 20M","TextLabel",oddsPage)~=nil,"commoner odds cannot replace best even with higher category")
for _,case in ipairs({
	{"1/200,000,000",200000000,"200M"}, {"1 dari 250.000.000",250000000,"250M"},
	{"300.5M",300500000,"300.5M"}, {"350,5M",350500000,"350.5M"},
	{400000000,400000000,"400M"}, {"1 : 500 000 000",500000000,"500M"}, {"1B",1000000000,"1B"},
}) do
	catchOdds("Format " .. tostring(case[2]),case[1])
	check(findText("Ikan terlangka: Format " .. tostring(case[2]) .. " | Normal | Secret | 1 dari " .. case[3],"TextLabel",oddsPage)~=nil,"supported denominator format: " .. tostring(case[1]))
end
for _,value in ipairs({"N/A","20M garbage","1/0",-10,0.01,math.huge,0/0,"1 in 1e999","12,34,567"}) do catchOdds("Invalid",value,"Forgotten") end
catchOdds("Missing",nil,"Forgotten")
catchOdds("Tie","1 in 1B")
check(findText("Ikan terlangka: Format 1000000000 | Normal | Secret | 1 dari 1B","TextLabel",oddsPage)~=nil,"invalid missing and tied odds preserve best catch")
check(findText("Tangkapan: 23","TextLabel",oddsPage)~=nil,"unknown odds still count as catches")
click("Reset Statistik Sesi")
check(findText("Ikan terlangka: Belum ada data peluang","TextLabel",oddsPage)~=nil,"reset clears best odds")

-- Game popup fallback: reproduce the supplied Manta Ray / 1 in 50.0K display.
local gamePopup=Instance.new("ScreenGui",playerGui)
local popupFrame=Instance.new("Frame",gamePopup)
local popupName=Instance.new("TextLabel",popupFrame)
local popupOdds=Instance.new("TextLabel",popupFrame)
local function popupCatch(name, mutation, weight, text, odds, direct)
	notify.OnClientEvent:Fire("GotFish",{baseName=name,rarity="Secret",mutation=mutation,weight=weight,chance=direct})
	step(0)
	popupName.Text, popupOdds.Text = text, odds
	step(0.5)
end
popupCatch("Manta Ray","Stone",157.97,"Stone Big Manta Ray (157.97kg)","1 in 50.0K")
check(findText("Ikan terlangka: Manta Ray | Stone | Secret | 1 dari 50K (tampilan game)","TextLabel",oddsPage)~=nil,"screenshot popup odds matched to catch")
check(findText("Tangkapan: 1","TextLabel",oddsPage)~=nil,"popup enriches catch without incrementing count")
popupCatch("Great Whale","Normal",500,"Big Great Whale (500.00kg)","<font color='#fff'>1 in 950.0K</font>")
popupCatch("Rare Secret","Normal",100,"Big Rare Secret (100.00kg)","1 in 20.0M")
check(findText("Ikan terlangka: Rare Secret | Normal | Secret | 1 dari 20M (tampilan game)","TextLabel",oddsPage)~=nil,"popup 20M replaces popup 950K")
check(findText("Tangkapan: 3","TextLabel",oddsPage)~=nil,"popup tracking does not duplicate catches")
popupCatch("Direct Odds","Normal",1,"Direct Odds (1.00kg)","1 in 999B","1 in 30M")
check(findText("Ikan terlangka: Direct Odds | Normal | Secret | 1 dari 30M","TextLabel",oddsPage)~=nil,"event odds take precedence over popup")
popupCatch("Other Fish","Normal",1,"Wrong Fish (1.00kg)","1 in 900B")
popupCatch("Wrong Weight","Normal",1,"Wrong Weight (2.00kg)","1 in 800B")
popupCatch("Wrong Mutation","Gold",1,"Stone Wrong Mutation (1.00kg)","1 in 700B")
check(findText("Ikan terlangka: Direct Odds | Normal | Secret | 1 dari 30M","TextLabel",oddsPage)~=nil,"unrelated name weight and mutation cannot set best odds")
popupFrame.Visible=false
popupCatch("Hidden","Normal",1,"Hidden (1.00kg)","1 in 600B")
check(findText("Ikan terlangka: Direct Odds | Normal | Secret | 1 dari 30M","TextLabel",oddsPage)~=nil,"hidden popup ignored")
popupFrame.Visible=true
popupCatch("Late UI","Normal",1,"Late UI (1.00kg)","1 in 40M")
notify.OnClientEvent:Fire("GotFish",{baseName="Newer Fish",rarity="Common",mutation="Normal"}); step(0.5)
check(findText("Terakhir: Newer Fish","TextLabel",oddsPage)~=nil,"old popup cannot overwrite latest catch text")
step(4)
notify.OnClientEvent:Fire("GotFish",{baseName="Late UI",rarity="Secret",mutation="Normal",weight=1}); step(0.5)
check(findText("Terakhir: Late UI | Normal | Secret | menunggu data peluang","TextLabel",oddsPage)~=nil,"stale popup not reused for a later catch")
step(21)
check(findText("peluang belum terbaca","TextLabel",oddsPage)~=nil,"unresolved popup has explicit timeout status")
click("Reset Statistik Sesi")
notify.OnClientEvent:Fire("GotFish",{baseName="Reset Pending",rarity="Secret",mutation="Normal"}); step(0)
click("Reset Statistik Sesi")
popupName.Text="Reset Pending (1kg)"; popupOdds.Text="1 in 100B"; step(0.5)
check(findText("Ikan terlangka: Belum ada data peluang","TextLabel",oddsPage)~=nil,"reset cancels pending UI enrichment")
popupName.Text="Old"; step(0.2)
notify.OnClientEvent:Fire("GotFish",{baseName="Ambiguous",rarity="Secret",mutation="Normal"})
notify.OnClientEvent:Fire("GotFish",{baseName="Ambiguous",rarity="Secret",mutation="Normal"}); step(0)
popupName.Text="Ambiguous (1kg)"; popupOdds.Text="1 in 10B"; step(0.5)
check(findText("Ikan terlangka: Belum ada data peluang","TextLabel",oddsPage)~=nil,"ambiguous rapid catches are not guessed")
click("Reset Statistik Sesi"); step(1)
notify.OnClientEvent:Fire("GotFish",{baseName="Staggered",rarity="Secret",mutation="Normal"}); step(0)
popupName.Text="Staggered (1kg)"; step(0.5)
check(findText("Ikan terlangka: Belum ada data peluang","TextLabel",oddsPage)~=nil,"new title cannot borrow old popup odds")
popupOdds.Text="1 in 60M"; step(0.5)
check(findText("Ikan terlangka: Staggered | Normal | Secret | 1 dari 60M","TextLabel",oddsPage)~=nil,"delayed popup odds resolve once both fields are fresh")
gamePopup:Destroy()

-- Rare notification layouts can be deeper and more decorative than normal ones.
click("Reset Statistik Sesi")
catchOdds("Mythical Baseline",600000,"Mythical")
local rareGui=Instance.new("ScreenGui",playerGui)
local rareFrame=Instance.new("Frame",rareGui)
for _=1,55 do Instance.new("Frame",rareFrame) end
local nested=rareFrame
for _=1,5 do nested=Instance.new("Frame",nested) end
local rareTitle=Instance.new("TextLabel",nested)
local rareShadow=Instance.new("TextLabel",nested)
local rareOdds=Instance.new("TextLabel",rareFrame)
local rareOddsShadow=Instance.new("TextLabel",rareFrame)
notify.OnClientEvent:Fire("GotFish",{uid="rareDelayed",baseName="Delayed Secret",rarity="Secret",mutation="Normal",weight=12}); step(5)
rareTitle.Text="Big Delayed Secret (12kg)"; rareShadow.Text=rareTitle.Text
rareOdds.Text="1 in 1.0M"; rareOddsShadow.Text=rareOdds.Text; step(0.5)
check(findText("Ikan terlangka: Delayed Secret | Normal | Secret | 1 dari 1M","TextLabel",oddsPage)~=nil,"delayed decorative rare popup replaces Mythical 600K with Secret 1M")
check(findText("#2  Delayed Secret | Normal | Secret | 1 dari 1M","TextLabel",oddsPage)~=nil,"delayed rare popup updates history")
rareOdds.Text="1 in 2M"; rareOddsShadow.Text=rareOdds.Text; step(0.5)
check(findText("Ikan terlangka: Delayed Secret | Normal | Secret | 1 dari 2M","TextLabel",oddsPage)~=nil,"same popup odds can finish updating after initial read")
notify.OnClientEvent:Fire("GotFish",{uid="rareDelayed",chance="1.5M"}); step(0)
check(findText("Ikan terlangka: Delayed Secret | Normal | Secret | 1 dari 1.5M","TextLabel",oddsPage)~=nil,"ID-only authoritative update corrects popup without name")
check(findText("Tangkapan: 2","TextLabel",oddsPage)~=nil,"delayed enrichment never adds a fish")
rareGui:Destroy()

click("Reset Statistik Sesi")
catchOdds("Mythical Baseline",600000,"Mythical")
notify.OnClientEvent:Fire("GotFish",{uid="inventoryCatch",baseName="Inventory Secret",rarity="Secret",mutation="Normal"}); step(0)
getAll.serverCallback=function() return {
	{uid="inventoryCatch",nama="Inventory Secret",rarity="Secret",mutasi="Normal",chance="1M"},
	{uid="preexistingFish",nama="Old Inventory Fish",rarity="Secret",mutasi="Normal",chance="100M"},
} end
step(9)
check(findText("Ikan terlangka: Inventory Secret | Normal | Secret | 1 dari 1M","TextLabel",oddsPage)~=nil,"inventory chance backfills only current-session catch ID")
check(findText("Tangkapan: 2","TextLabel",oddsPage)~=nil,"inventory read does not import preexisting fish")
check(findText("Peluang terbaca: 2/2","TextLabel",oddsPage)~=nil,"inventory enrichment updates coverage")
getAll.serverCallback=function() return {} end
click("Reset Statistik Sesi")
catchOdds("Four Thousand",4000)
check(findText("1 dari 4K","TextLabel",oddsPage)~=nil,"4000 compacted to 4K")
catchOdds("One Million",1000000)
check(findText("1 dari 1M","TextLabel",oddsPage)~=nil,"1000000 compacted to 1M")
catchOdds("More Precise",1000200)
catchOdds("Less Precise",1000100)
check(findText("Ikan terlangka: More Precise","TextLabel",oddsPage)~=nil,"ranking uses unrounded numbers despite identical compact display")
for index=1,101 do catchOdds("History Fish " .. index,10) end
local history=findText("#105  History Fish 101","TextLabel",oddsPage).Text
check(not history:find("#1  ",1,true) and history:find("#6  ",1,true),"history bounded to 100 most recent catches")
check(findText("Ikan terlangka: More Precise","TextLabel",oddsPage)~=nil,"best session record survives eviction from visible history")
catchOdds("Unknown Secret",nil,"Secret")
check(findText("#106  Unknown Secret","TextLabel",oddsPage)~=nil,"unread rare catch remains visible in history")
check(findText("Peluang terbaca: 105/106","TextLabel",oddsPage)~=nil,"unread odds are explicit instead of silently missing")
click("Reset Statistik Sesi")
check(findText("Belum ada tangkapan.","TextLabel",oddsPage)~=nil,"reset clears history")

click("×"); step(1)
check(playerGui:FindFirstChild("DarusHub")==nil,"close destroys UI")
check(connectionCount()==0,"close removes every registered connection")
check(next(scheduled)==nil,"close cancels workers and requests")
print("PASS: " .. passed .. " UBEYHUB-based Darus Hub regression checks (mock runtime)")
