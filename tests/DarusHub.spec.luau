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

-- Targets use received catches, match both fields literally, and stop both automation modes.
step(15) -- let the previous simulated server sale finish
click("Target & Statistik")
local catchPage=findText("TARGET IKAN & STATISTIK SESI","TextLabel").Parent
check(catchPage.Visible,"catch dashboard navigation opens")
click("Pantau Target dan Stop Otomatis")
check(findText("Pantau Target dan Stop Otomatis","TextButton").Text:find("[OFF]",1,true),"empty target cannot arm")
fill("Nama ikan target","  Test Fish  ")
fill("Mutasi target","8-Bit")
click("Pantau Target dan Stop Otomatis")
click("Smart Auto Fishing (Di Tempat Saja)")
click("Auto Sell Timer")
notify.OnClientEvent:Fire("GotFish",{uid="catch1",baseName="Test Fish",rarity="Rare",mutation="8xBit"}); step(0)
check(findText("Smart Auto Fishing (Di Tempat Saja)","TextButton").Text:find("[ON]",1,true),"wrong mutation does not stop fishing")
notify.OnClientEvent:Fire("GotFish",{uid="catch2",baseName="test fish",rarity="Secret",mutation="8-bit"}); step(0)
check(findText("Smart Auto Fishing (Di Tempat Saja)","TextButton").Text:find("[OFF]",1,true),"matching target stops fishing")
check(findText("Auto Sell Timer","TextButton").Text:find("[OFF]",1,true),"target stops auto sell")
check(playerGui.DarusHub.TargetCatchNotification.Visible,"target shows visible dismissible notification")
check(findText("Tangkapan: 2","TextLabel",catchPage)~=nil,"received catches counted")
check(findText("Secret: 1","TextLabel",catchPage)~=nil,"rarity counts tracked")
notify.OnClientEvent:Fire("GotFish",{uid="catch2",baseName="test fish",rarity="Secret",mutation="8-bit"}); step(0)
check(findText("Tangkapan: 2","TextLabel",catchPage)~=nil,"duplicate server catch ID counted once")
notify.OnClientEvent:Fire("Bite",{}); notify.OnClientEvent:Fire("GotFish",{}); step(0)
check(findText("Tangkapan: 2","TextLabel",catchPage)~=nil,"non-catch and malformed events ignored")
click("Reset Statistik Sesi")
notify.OnClientEvent:Fire("GotFish",{uid="catch2",baseName="test fish"}); step(0)
check(findText("Tangkapan: 0","TextLabel",catchPage)~=nil,"stats reset preserves deduplication")
fill("Nama ikan target",""); fill("Mutasi target","Gold")
click("Smart Auto Fishing + Teleport")
notify.OnClientEvent:Fire("GotFish",{uid="catch3",baseName="Any Fish",rarity="Forgotten",mutation="Gold"}); step(0)
check(findText("Smart Auto Fishing + Teleport","TextButton").Text:find("[OFF]",1,true),"mutation-only target stops teleport fishing")
check(findText("Rarity tertinggi: Any Fish | Gold | Forgotten","TextLabel",catchPage)~=nil,"highest known rarity displayed")
click("Pantau Target dan Stop Otomatis")
fill("Nama ikan target","Test Fish"); fill("Mutasi target","8-Bit")
fill("Nama ikan dilindungi","Keep Fish, Another Fish")
fill("Mutasi dilindungi","Gold, 8-Bit")
click("Simpan Konfigurasi")
local catchSaved=encoded[files["DarusHub_Config.json"]]
check(catchSaved.TargetName=="Test Fish" and catchSaved.ProtectMutations=="Gold, 8-Bit","target and protection fields persist")

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
check(attemptSale({{uid="p3",nama="test fish",rarity="Common",mutasi="8-bit"}})==0,"configured target protected when tracking is OFF")
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
check(box("Nama ikan target").Text=="" and box("Rarity dilindungi").Text=="Secret, Forgotten","reset restores target and protection defaults")
check(findText("8-Bit","TextButton",mutationScope).Text:find("[ ]",1,true),"reset refreshes filter UI")
step(2)

-- Persistent listeners/worker counts must be stable across re-execution.
local baseline=connectionCount()
RunHub(); step(2)
check(gui.destroyed,"rerun shuts down previous GUI")
check(connectionCount()<=baseline,"rerun does not leak connections: " .. connectionCount() .. "/" .. baseline)
local cleanBaseline=connectionCount()
fill("Nama ikan target","Reload Fish"); fill("Mutasi dilindungi","8-Bit")
click("Simpan Konfigurasi")
RunHub(); step(2)
check(connectionCount()==cleanBaseline,"consecutive fresh runs have stable connection count")
check(box("Nama ikan target").Text=="Reload Fish" and box("Mutasi dilindungi").Text=="8-Bit","saved catch settings reload")
check(findText("Pantau Target dan Stop Otomatis","TextButton").Text:find("[OFF]",1,true),"reloaded target monitor starts OFF")
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

-- Rod editor uses only owned tools and existing numeric fields/attributes.
click("Rod & Value")
local editorPage=findText("ROD & VALUE","TextLabel").Parent
check(editorPage.Visible,"rod editor tab opens")
local sword=Instance.new("Tool",backpack); sword.Name="Sword"
local templateRod=Instance.new("Tool",workspace); templateRod.Name="Template Rod"
click("Refresh Daftar Rod",editorPage)
local rodButtons={}
for _,object in ipairs(editorPage:GetDescendants()) do
	if object:IsA("TextButton") and object.Text:find("Withering Rod #",1,true) then table.insert(rodButtons,object) end
end
check(#rodButtons>=2 and rodButtons[1].Text~=rodButtons[2].Text,"duplicate rod names have distinct IDs")
local forbidden=false
for _,object in ipairs(editorPage:GetDescendants()) do
	if object:IsA("TextButton") and (object.Text:find("Sword #",1,true) or object.Text:find("Template Rod #",1,true)) then forbidden=true end
end
check(not forbidden,"non-rods and unowned templates excluded")
click("[Dipakai]",editorPage)
check(findText("Luck [NumberValue]","TextButton",editorPage)~=nil,"numeric value discovered")
check(findText("@LuckMultiplier [Attribute]","TextButton",editorPage)~=nil,"numeric attribute discovered")
local nonNumeric=false
for _,object in ipairs(editorPage:GetDescendants()) do
	if object:IsA("TextButton") and (object.Text:find("EnableMiniGame [",1,true) or object.Text:find("@Description",1,true)) then nonNumeric=true end
end
check(not nonNumeric,"boolean and string fields omitted")

local luck=rod.Mechanics.Settings.Luck
local weight=rod.Mechanics.Settings.MaxWeight
click("Luck [NumberValue]",editorPage)
fill("Nilai baru","25"); click("Terapkan Value Lokal",editorPage)
check(luck.Value==25,"NumberValue edited")
fill("Nilai baru","40"); click("Terapkan Value Lokal",editorPage)
click("Reset Value Terpilih",editorPage)
check(luck.Value==1,"repeated edit preserves original value for reset")
fill("Nilai baru","abc"); click("Terapkan Value Lokal",editorPage)
check(luck.Value==1 and findText("Masukkan angka valid","TextLabel",editorPage),"invalid numeric input rejected")
fill("Nilai baru","1e309"); click("Terapkan Value Lokal",editorPage)
check(luck.Value==1,"infinite input rejected")
click("MaxWeight [IntValue]",editorPage)
fill("Nilai baru","2.5"); click("Terapkan Value Lokal",editorPage)
check(weight.Value==10,"fractional IntValue rejected")
fill("Nilai baru","9007199254740992"); click("Terapkan Value Lokal",editorPage)
check(weight.Value==10,"integer outside exact precision rejected")
fill("Nilai baru","75"); click("Terapkan Value Lokal",editorPage)
check(weight.Value==75,"IntValue edited")
click("@LuckMultiplier [Attribute]",editorPage)
fill("Nilai baru","4.5"); click("Terapkan Value Lokal",editorPage)
check(rod:GetAttribute("LuckMultiplier")==4.5,"numeric attribute edited")
click("Reset Semua Value Rod",editorPage)
check(weight.Value==10 and rod:GetAttribute("LuckMultiplier")==2,"reset all restores values and attributes")

click("Luck [NumberValue]",editorPage)
fill("Nilai baru","25"); click("Terapkan Value Lokal",editorPage)
luck.Value=777
step(0.8)
check(luck.Value==777 and findText("Saat ini: 777","TextLabel",editorPage),"external update displayed without fighting it")
click("Reset Value Terpilih",editorPage)
check(luck.Value==1,"reset after external update restores pre-edit value")
local settings=luck.Parent
luck.Parent=nil
fill("Nilai baru","50"); click("Terapkan Value Lokal",editorPage)
check(luck.Value==1,"stale removed value cannot be edited")
luck.Parent=settings
click("Refresh Daftar Rod",editorPage)
click("Luck [NumberValue]",editorPage)
rod.Parent=backpack
click("Refresh Daftar Rod",editorPage)
fill("Nilai baru","33"); click("Terapkan Value Lokal",editorPage)
check(luck.Value==33,"selection survives equip to backpack transfer")
rod.Parent=workspace
fill("Nilai baru","66"); click("Terapkan Value Lokal",editorPage)
step(0.8)
check(luck.Value==1,"unowned rod rejects edits and restores previous edit")
rod.Parent=player.Character
click("Refresh Daftar Rod",editorPage); click("[Dipakai]",editorPage)

-- Manual delay edits own that setting until reset; Auto Fishing cannot clobber it.
click("Smart Auto Fishing (Di Tempat Saja)"); step(0.3)
check(rodDelay.Value==0.05,"auto optimizer active before manual edit")
click("Time_before_getfish [NumberValue]",editorPage)
fill("Nilai baru","3"); click("Terapkan Value Lokal",editorPage)
step(1.5)
check(rodDelay.Value==3,"manual value overrides automatic optimizer")
click("Smart Auto Fishing (Di Tempat Saja)"); step(0.2)
check(rodDelay.Value==3,"fishing OFF preserves explicitly edited value")
click("Reset Value Terpilih",editorPage)
check(rodDelay.Value==2,"editor reset restores pre-optimization original")

local emptyRod=Instance.new("Tool",backpack); emptyRod.Name="Empty Rod"
click("Refresh Daftar Rod",editorPage); click("Empty Rod #",editorPage)
check(findText("Tidak ada value angka","TextLabel",editorPage)~=nil,"rod without exposed values shows empty state")
click("[Dipakai]",editorPage)
click("Luck [NumberValue]",editorPage)
fill("Nilai baru","99"); click("Terapkan Value Lokal",editorPage)
click("@LuckMultiplier [Attribute]",editorPage)
fill("Nilai baru","8"); click("Terapkan Value Lokal",editorPage)
click("Refresh Daftar Rod",editorPage)
local editorConnections=connectionCount()
for _=1,5 do click("Refresh Daftar Rod",editorPage) end
check(connectionCount()==editorConnections,"refresh does not accumulate handlers")

click("×"); step(1)
check(playerGui:FindFirstChild("DarusHub")==nil,"close destroys UI")
check(connectionCount()==0,"close removes every registered connection")
check(next(scheduled)==nil,"close cancels workers and requests")
check(luck.Value==1 and rod:GetAttribute("LuckMultiplier")==2,"close restores all rod edits")
print("PASS: " .. passed .. " UBEYHUB-based Darus Hub regression checks (mock runtime)")
