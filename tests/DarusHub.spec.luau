-- Deterministic client mock. This exercises lifecycle and UI behavior, not
-- Roblox physics, replication, rendering, or the target game's server rules.
local now = 0
local os = {clock = function() return now end}
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
local Vector2, Vector3 = {new = vector}, {new = vector}
local CFrame = {new = function(position) return {Position = position or vector(0,0,0), RightVector = vector(1,0,0)} end}
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
	__index = function(self,key) return methods[key] or self.properties[key] end,
	__newindex = function(self,key,value)
		if key == "Parent" then
			local old = self.properties.Parent
			if old then
				notifyAncestors(old,"DescendantRemoving",self)
				local index = table.find(old.children,self)
				if index then table.remove(old.children,index) end
			end
			self.properties.Parent = value
			if value then table.insert(value.children,self); notifyAncestors(value,"DescendantAdded",self) end
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
	}, children = {}, attributes = {}, states = {}, propertySignals = {}}, Object)
	for _, name in ipairs({"Destroying","DescendantAdded","DescendantRemoving","MouseButton1Click","InputBegan","InputChanged","InputEnded","CharacterRemoving","WindowFocusReleased"}) do object[name] = Signal() end
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

local services = {}
for _, name in ipairs({"Players","UserInputService","Workspace","ReplicatedStorage"}) do services[name] = Instance.new(name) end
local game = {GetService = function(_,name) return assert(services[name],name) end}
local warnings = {}
local function warn(message) table.insert(warnings,message) end
local workspace = services.Workspace
local terrain = Instance.new("Terrain",workspace)
terrain.WaterTransparency, terrain.WaterWaveSize, terrain.WaterWaveSpeed = 0.4, 0.2, 8
workspace.CurrentCamera = Instance.new("Camera")
workspace.CurrentCamera.ViewportSize = vector(800,600)
local player = Instance.new("Player")
services.Players.LocalPlayer = player
local playerGui = Instance.new("PlayerGui",player)
local backpack = Instance.new("Backpack",player)
local function character()
	local model = Instance.new("Model",workspace)
	Instance.new("Humanoid",model)
	local root = Instance.new("Part",model); root.Name = "HumanoidRootPart"
	return model
end
player.Character = character()
local chair = Instance.new("Part",workspace); chair.Name = "Chair"
local water = Instance.new("MeshPart",workspace); water.Name = "water"

local function RunHub()
-- @DARUS_SOURCE@
end

local passed = 0
local function check(condition, message) assert(condition,message); passed += 1 end
local function findText(fragment, class)
	for _, object in ipairs(playerGui:GetDescendants()) do
		if object.Text and string.find(object.Text,fragment,1,true) and (not class or object:IsA(class)) then return object end
	end
	error("UI not found: " .. fragment)
end
local function click(fragment) findText(fragment,"TextButton").MouseButton1Click:Fire() end
local function input(kind,x,y) return {UserInputType = Enum.UserInputType[kind], Position = vector(x,y)} end

RunHub()
step(0)
local firstGui = playerGui:FindFirstChild("DarusHubCollect")
local main = firstGui:FindFirstChildOfClass("Frame")
check(main.Visible, "main must open immediately")
check(water.Transparency == 1 and not water.CanCollide, "water enabled")
check(chair.Transparency == 0.25 and chair.CanCollide, "chair must not match air")
click("Anti-Water")
check(water.Transparency == 0.25 and water.CanCollide, "water properties restored")
check(terrain.WaterTransparency == 0.4 and terrain.WaterWaveSize == 0.2 and terrain.WaterWaveSpeed == 8, "terrain restored")
click("Anti-Water")
local streamedWater = Instance.new("Part"); streamedWater.Name = "air"; streamedWater.Parent = workspace
check(streamedWater.Transparency == 1, "new water tracked")
streamedWater.Parent = nil
check(streamedWater.Transparency == 0.25, "removed water restored")

local farmPage = findText("Master Auto Mining","TextButton").Parent
check(farmPage.AutomaticCanvasSize == Enum.AutomaticSize.Y, "canvas follows content")
local slider
for _, object in ipairs(farmPage:GetDescendants()) do if object:IsA("TextButton") and object.Text == "" then slider = object; break end end
local firstTouch, otherTouch = input("Touch",100,0), input("Touch",400,0)
slider.InputBegan:Fire(firstTouch)
check(not farmPage.ScrollingEnabled, "scroll disabled while dragging slider")
local fill = slider.Parent:FindFirstChildOfClass("Frame")
local firstFill = fill.Size.X.Scale
services.UserInputService.InputChanged:Fire(otherTouch)
services.UserInputService.InputEnded:Fire(otherTouch)
check(fill.Size.X.Scale == firstFill and not farmPage.ScrollingEnabled, "unrelated touch must not move/end slider")
firstTouch.Position = vector(300,0)
services.UserInputService.InputChanged:Fire(firstTouch)
check(fill.Size.X.Scale ~= firstFill, "own touch moves slider")
services.UserInputService.InputEnded:Fire(firstTouch)
check(farmPage.ScrollingEnabled, "scroll restored")
slider.Parent.AbsoluteSize = vector(0,0)
slider.InputBegan:Fire(firstTouch)
services.UserInputService.InputEnded:Fire(firstTouch)
check(fill.Size.X.Scale == fill.Size.X.Scale, "zero width slider must not produce NaN")
slider.InputBegan:Fire(firstTouch)
services.UserInputService.WindowFocusReleased:Fire()
check(farmPage.ScrollingEnabled, "losing focus releases slider")
workspace.CurrentCamera.ViewportSize = vector(320,480)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
check(main:FindFirstChildOfClass("UIScale").Scale <= 296/550, "small viewport fits main")

local float = firstGui:FindFirstChild("DarusToggle")
local mouse = input("MouseButton1",20,120)
float.InputBegan:Fire(mouse)
services.UserInputService.InputChanged:Fire(input("MouseMovement",2000,2000))
services.UserInputService.InputEnded:Fire(mouse)
float.MouseButton1Click:Fire()

local finger = input("Touch",0,0)
float.InputBegan:Fire(finger)
local originalX = float.Position.X.Offset
services.UserInputService.InputChanged:Fire(otherTouch)
services.UserInputService.InputEnded:Fire(otherTouch)
check(float.Position.X.Offset == originalX, "unrelated touch must not drag float")
services.UserInputService.WindowFocusReleased:Fire()
finger.Position = vector(-100,-100)
services.UserInputService.InputChanged:Fire(finger)
check(float.Position.X.Offset == originalX, "losing focus cancels floating drag")
check(main.Visible and float.Position.X.Offset <= 744 and float.Position.Y.Offset <= 544, "drag clamps and does not toggle")
step(0.4)
float.MouseButton1Click:Fire()
check(not main.Visible, "normal click hides main")
float.MouseButton1Click:Fire()

click("Taruh Barang Sekarang")
check(findText("Kios tidak tersedia") ~= nil, "missing remote shown")
local remoteFolder = Instance.new("Folder",services.ReplicatedStorage); remoteFolder.Name = "rc645e8ded8e146828f98af5123faf3a8"
local remote = Instance.new("RemoteFunction",remoteFolder); remote.Name = "r2c39d7b63e484766b0f0da9e3961ed82"
local calls = 0
remote.serverCallback = function() calls += 1; task.wait(20); return true end
click("Taruh Barang Sekarang")
click("Menunggu kios")
step(11)
check(calls == 1 and findText("Kios belum merespons") ~= nil, "timeout must not duplicate in-flight request")
click("Kios belum merespons")
step(0)
check(calls == 1, "retry blocked until response")

local material = Instance.new("Model",workspace); material.Name = "Spawn_Dupa"
local nestedPart = Instance.new("Part",material); nestedPart.Name = "Spawn_Dupa"
local prompt = Instance.new("ProximityPrompt",nestedPart); prompt.ActionText = "Ambil bahan"; prompt.HoldDuration = 2
click("• Spawn_Dupa")
click("Master Auto Collect")
step(0.6)
check(prompt.beginCount == 1, "movement works while kiosk hangs; nested names do not duplicate prompt")
click("Master Auto Collect")
step(0.2)
check(prompt.endCount == 1 and prompt.beginCount == 1, "toggle off releases hold and stops work promptly")
local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
click("Anti-Water")
check(humanoid:GetStateEnabled(Enum.HumanoidStateType.Swimming), "swimming restored on disable")
click("Anti-Water")
click("Master Auto Collect")
step(0.6)
local oldCharacter = player.Character
player.CharacterRemoving:Fire(oldCharacter)
player.Character = nil
local beginsBeforeRespawn = prompt.beginCount
step(0.3)
check(prompt.beginCount == beginsBeforeRespawn and humanoid:GetStateEnabled(Enum.HumanoidStateType.Swimming), "respawn releases old character")
player.Character = character()
step(0.6)
check(prompt.beginCount > beginsBeforeRespawn, "worker resumes with new character")

local connectionBaseline = connectionCount()
RunHub()
step(0.3)
check(firstGui.destroyed, "old GUI removed on rerun")
check(connectionCount() == connectionBaseline, "rerun must not leak connections")
local beginsAfterRerun = prompt.beginCount
step(2)
check(prompt.beginCount == beginsAfterRerun, "old worker must stop; new toggles default off")
remote.serverCallback = function() calls += 1; return false end
click("Taruh Barang Sekarang")
step(0)
check(findText("ditolak server") ~= nil, "server rejection surfaced")
remote.serverCallback = function() error("network failure") end
click("Taruh Barang Sekarang")
step(0)
check(findText("Permintaan kios gagal") ~= nil, "remote exception surfaced and lock released")
remote.serverCallback = function() return nil end
click("Taruh Barang Sekarang")
step(0)
check(findText("periksa isi slot") ~= nil, "unknown response does not claim item success")

-- Complete one normal hold, then ensure no duplicate trigger or queued extra
-- interaction after OFF. Also exercise live prompt removal and tool checks.
click("• Spawn_Dupa")
click("Master Auto Collect")
local previousBegins, previousEnds = prompt.beginCount, prompt.endCount
step(2.55)
check(prompt.beginCount == previousBegins + 1 and prompt.endCount == previousEnds + 1, "normal hold triggers exactly one begin/end sequence")
click("Master Auto Collect")
step(0.3)
check(prompt.beginCount == previousBegins + 1, "no post-OFF interaction")
prompt.Parent = nil
click("Master Auto Collect")
step(1)
check(prompt.beginCount == previousBegins + 1, "removed prompt no longer processed")
click("Master Auto Collect")

local rock = Instance.new("Model",workspace); rock.Name = "BatuKecil"
local rockPart = Instance.new("Part",rock)
local minePrompt = Instance.new("ProximityPrompt",rockPart); minePrompt.ActionText = "Tambang"; minePrompt.HoldDuration = 0
click("• Batu Kecil")
click("Master Auto Mining")
step(0.5)
check(minePrompt.beginCount == 0 and findText("Alat tidak ditemukan") ~= nil, "missing mining tool reported without interaction")
local tool = Instance.new("Tool",backpack); tool.Name = "Beliung Kayu"
step(0.6)
check(minePrompt.beginCount == 1 and tool.Parent == player.Character, "mining equips tool before interaction")
step(1)
check(minePrompt.beginCount == 1, "mining cooldown honored")
click("Master Auto Mining")

local autoCalls = 0
remote.serverCallback = function() autoCalls += 1; return nil end
click("Master Auto Taruh")
step(3.5)
check(autoCalls == 2, "auto kiosk uses independent timed worker")
click("Master Auto Taruh")
step(4)
check(autoCalls == 2, "auto kiosk stops after OFF")

click("X")
step(1)
check(playerGui:FindFirstChild("DarusHubCollect") == nil, "close destroys UI")
check(connectionCount() == 0, "close disconnects all handlers")
check(next(scheduled) == nil, "close cancels all workers and requests")
check(water.Transparency == 0.25 and terrain.WaterTransparency == 0.4, "close restores environment")
print("PASS: " .. passed .. " Darus Hub regression checks (mock runtime)")
