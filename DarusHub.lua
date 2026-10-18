-- ==============================================================================
-- DARUS HUB - Full Item Kios Taruh Edition
-- ==============================================================================

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Darus Hub harus dijalankan di sisi pemain.")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Each run owns its state, connections and tasks. Destroying the previous UI
-- stops its workers before this run starts.
local previousGui = PlayerGui:FindFirstChild("DarusHubCollect")
if previousGui then
	local shutdown = previousGui:FindFirstChild("DarusShutdown")
	if shutdown and shutdown:IsA("BindableFunction") then pcall(function() shutdown:Invoke() end) end
	previousGui:Destroy()
end
local State = {}
local running = true
local connections = {}
local threads = {}
local heldPrompt
local Gui
local StatusLabel
local lastWarnings = {}

local function Connect(signal, callback)
	local connection = signal:Connect(function(...)
		if running then callback(...) end
	end)

	table.insert(connections, connection)
	return connection
end

local function Spawn(callback)
	for index = #threads, 1, -1 do
		if coroutine.status(threads[index]) == "dead" then table.remove(threads, index) end
	end
	-- defer lets us register the thread before its callback can yield or finish.
	local thread = task.defer(callback)
	table.insert(threads, thread)
	return thread
end

local function Report(message, isError)
	if not running then return end
	if StatusLabel then
		StatusLabel.Text = message
		StatusLabel.TextColor3 = isError and Color3.fromRGB(255, 130, 110) or Color3.fromRGB(160, 210, 240)
	end
	if isError and (not lastWarnings[message] or os.clock() - lastWarnings[message] > 10) then
		lastWarnings[message] = os.clock()
		warn("[Darus Hub] " .. message)
	end
end

local function WaitWhile(seconds, predicate)
	local deadline = os.clock() + seconds
	repeat
		if not running or (predicate and not predicate()) then return false end
		local remaining = deadline - os.clock()
		if remaining <= 0 then return true end
		task.wait(math.min(0.1, remaining))
	until false
end

------------------------------------------------------------------
-- SETTING WAKTU TUNGGU & CONFIG
------------------------------------------------------------------
State.ConfigWait = {
	BatuKecil = 5.8,
	BatuSedang = 11.5,
	BatuBesar = 19.5,
	PohonKecil = 5.8,
	PohonSedang = 11.5,
	PohonBesar = 19.5,
}

State.SelectedTaruhSlot = "slot1"
State.SelectedTaruhItem = "Bunga Melati"
State.AutoTaruhEnabled = false

State.AutoSpawnCollect = false
State.AutoMineEnabled = false
State.AutoWoodEnabled = false

State.RemoveWaterEnabled = true

State.SelectedMaterials = {
	["Spawn_Dupa"] = false,
	["Spawn_JamurKuburan"] = false,
	["Spawn_Kemenyan"] = false,
	["Spawn_Gagak"] = false,
	["Spawn_KepitingSungai"] = false,
	["Spawn_Melati"] = false,
}

State.SelectedBatu = {
	["BatuKecil"] = false,
	["BatuSedang"] = false,
	["BatuBesar"] = false,
}

State.SelectedPohon = {
	["PohonKecil"] = false,
	["PohonSedang"] = false,
	["PohonBesar"] = false,
}

local waterParts = {}
local terrainSettings
local swimmingStates = {}

local function HideWaterPart(part)
	if not part:IsA("BasePart") then return end
	local name = part.Name:lower()
	-- Substring "air" also matched chairs, stairs and unrelated map parts.
	if name ~= "water" and name ~= "air" and part.Material ~= Enum.Material.Water
		and part:GetAttribute("DarusWater") ~= true then return end
	if not waterParts[part] then
		waterParts[part] = {CanCollide = part.CanCollide, Transparency = part.Transparency}
	end
	part.CanCollide = false
	part.Transparency = 1
end

local function ApplyAntiWater(enabled)
	if enabled then
		if Terrain and not terrainSettings then
			terrainSettings = {
				WaterTransparency = Terrain.WaterTransparency,
				WaterWaveSize = Terrain.WaterWaveSize,
				WaterWaveSpeed = Terrain.WaterWaveSpeed,
			}
			Terrain.WaterTransparency = 1
			Terrain.WaterWaveSize = 0
			Terrain.WaterWaveSpeed = 0
		end
		for _, part in ipairs(Workspace:GetDescendants()) do HideWaterPart(part) end
	else
		for part, properties in pairs(waterParts) do
			pcall(function()
				for property, value in pairs(properties) do part[property] = value end
			end)
		end
		table.clear(waterParts)
		if terrainSettings then
			for property, value in pairs(terrainSettings) do Terrain[property] = value end
			terrainSettings = nil
		end
		for humanoid, enabledBefore in pairs(swimmingStates) do
			pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, enabledBefore) end)
		end
		table.clear(swimmingStates)
	end
end

local function EquipTool(character, humanoid, toolName)
	local currentTool = character:FindFirstChildOfClass("Tool")
	if currentTool and currentTool.Name == toolName then return true end
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	local tool = backpack and backpack:FindFirstChild(toolName)
	if not tool or not tool:IsA("Tool") then
		Report("Alat tidak ditemukan: " .. toolName, true)
		return false
	end
	humanoid:EquipTool(tool)
	return true
end

local function Cleanup()
	if not running then return end
	running = false
	if heldPrompt then pcall(function() heldPrompt:InputHoldEnd() end) end
	heldPrompt = nil
	for _, connection in ipairs(connections) do connection:Disconnect() end
	for _, thread in ipairs(threads) do
		if thread ~= coroutine.running() and coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	end
	ApplyAntiWater(false)
end

Gui = Instance.new("ScreenGui")
Gui.Name = "DarusHubCollect"
Gui.Parent = PlayerGui
Gui.ResetOnSpawn = false
local Shutdown = Instance.new("BindableFunction", Gui)
Shutdown.Name = "DarusShutdown"
Shutdown.OnInvoke = Cleanup
Connect(Gui.Destroying, Cleanup)
Connect(Workspace.DescendantAdded, function(instance)
	if State.RemoveWaterEnabled then HideWaterPart(instance) end
end)

----------------------------------------------------
-- MAIN HUB UI
----------------------------------------------------
local Main = Instance.new("Frame")
Main.Parent = Gui
Main.Visible = true
Main.Size = UDim2.new(0,550,0,320)
Main.Position = UDim2.new(0.5,-275,0.5,-160)
Main.BackgroundColor3 = Color3.fromRGB(20,20,25)

local MainScale = Instance.new("UIScale", Main)
local function FitScreen()
	local camera = Workspace.CurrentCamera
	if not camera then return end
	local size = camera.ViewportSize
	MainScale.Scale = math.min(1, math.max(0.1, (size.X - 24) / 550), math.max(0.1, (size.Y - 64) / 320))
	Main.AnchorPoint = Vector2.new(0.5, 0.5)
	Main.Position = UDim2.fromScale(0.5, 0.5)
end
local viewportConnection
local function WatchCamera()
	if viewportConnection then viewportConnection:Disconnect() end
	if Workspace.CurrentCamera then
		viewportConnection = Connect(Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), FitScreen)
	end
	FitScreen()
end
Connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), WatchCamera)
WatchCamera()

local CloseButton = Instance.new("TextButton", Main)
CloseButton.Size = UDim2.fromOffset(28, 24)
CloseButton.Position = UDim2.new(1, -32, 0, 2)
CloseButton.Text = "X"
CloseButton.BackgroundColor3 = Color3.fromRGB(100, 40, 40)
CloseButton.TextColor3 = Color3.new(1, 1, 1)
Connect(CloseButton.MouseButton1Click, function() Gui:Destroy() end)

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0,18)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Parent = Main
MainStroke.Color = Color3.fromRGB(0,170,255)

local Sidebar = Instance.new("ScrollingFrame")
Sidebar.Parent = Main
Sidebar.Size = UDim2.new(0,140,1,0)
Sidebar.BackgroundColor3 = Color3.fromRGB(15,15,20)
Sidebar.CanvasSize = UDim2.fromOffset(0, 190)
Sidebar.ScrollBarThickness = 2

local SideCorner = Instance.new("UICorner")
SideCorner.Parent = Sidebar

local HubTitle = Instance.new("TextLabel")
HubTitle.Parent = Sidebar
HubTitle.BackgroundTransparency = 1
HubTitle.Size = UDim2.new(1,0,0,60)
HubTitle.Text = "DARUS HUB"
HubTitle.Font = Enum.Font.GothamBold
HubTitle.TextColor3 = Color3.fromRGB(0,170,255)
HubTitle.TextSize = 18

local AutoCollectMenuBtn = Instance.new("TextButton")
AutoCollectMenuBtn.Parent = Sidebar
AutoCollectMenuBtn.Position = UDim2.new(0,10,0,65)
AutoCollectMenuBtn.Size = UDim2.new(1,-20,0,32)
AutoCollectMenuBtn.Text = "Auto Collect"
AutoCollectMenuBtn.TextColor3 = Color3.new(1,1,1)
AutoCollectMenuBtn.Font = Enum.Font.GothamMedium
AutoCollectMenuBtn.TextSize = 12
AutoCollectMenuBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
Instance.new("UICorner", AutoCollectMenuBtn)

local AutoFarmMenuBtn = Instance.new("TextButton")
AutoFarmMenuBtn.Parent = Sidebar
AutoFarmMenuBtn.Position = UDim2.new(0,10,0,105)
AutoFarmMenuBtn.Size = UDim2.new(1,-20,0,32)
AutoFarmMenuBtn.Text = "Auto Mine & Wood"
AutoFarmMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
AutoFarmMenuBtn.Font = Enum.Font.GothamMedium
AutoFarmMenuBtn.TextSize = 11
AutoFarmMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
Instance.new("UICorner", AutoFarmMenuBtn)

local AutoRestockMenuBtn = Instance.new("TextButton")
AutoRestockMenuBtn.Parent = Sidebar
AutoRestockMenuBtn.Position = UDim2.new(0,10,0,145)
AutoRestockMenuBtn.Size = UDim2.new(1,-20,0,32)
AutoRestockMenuBtn.Text = "Auto Kios Taruh"
AutoRestockMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
AutoRestockMenuBtn.Font = Enum.Font.GothamMedium
AutoRestockMenuBtn.TextSize = 11
AutoRestockMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
Instance.new("UICorner", AutoRestockMenuBtn)

----------------------------------------------------
-- CONTENT & PAGES
----------------------------------------------------
local Content = Instance.new("Frame")
Content.Parent = Main
Content.Position = UDim2.new(0,150,0,30)
Content.Size = UDim2.new(1,-160,1,-62)
Content.BackgroundTransparency = 1

StatusLabel = Instance.new("TextLabel", Main)
StatusLabel.Position = UDim2.new(0, 150, 1, -30)
StatusLabel.Size = UDim2.new(1, -160, 0, 28)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextSize = 11
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextWrapped = true
Report("Siap. Pilih bahan dan aktifkan fitur yang diperlukan.", false)

----------------------------------------------------
-- HALAMAN 1: AUTO COLLECT
----------------------------------------------------
local AutoCollectPage = Instance.new("ScrollingFrame")
AutoCollectPage.Parent = Content
AutoCollectPage.Size = UDim2.new(1,0,1,0)
AutoCollectPage.BackgroundTransparency = 1
AutoCollectPage.Visible = true
AutoCollectPage.CanvasSize = UDim2.new(0,0,2.6,0)
AutoCollectPage.ScrollBarThickness = 4

local pad1 = Instance.new("UIPadding")
pad1.Parent = AutoCollectPage
pad1.PaddingTop = UDim.new(0, 10)

local l1 = Instance.new("UIListLayout")
l1.Parent = AutoCollectPage
l1.SortOrder = Enum.SortOrder.LayoutOrder
l1.Padding = UDim.new(0, 8)

local TitleCol = Instance.new("TextLabel")
TitleCol.Parent = AutoCollectPage
TitleCol.Size = UDim2.new(1,0,0,25)
TitleCol.BackgroundTransparency = 1
TitleCol.Text = "📦 MENU AUTO COLLECT"
TitleCol.TextColor3 = Color3.fromRGB(0,170,255)
TitleCol.Font = Enum.Font.GothamBold
TitleCol.TextSize = 12

local function AddToggle(parent, text, defaultState, callback)
	local b = Instance.new("TextButton")
	b.Parent = parent
	b.Size = UDim2.new(1,0,0,30)
	b.BackgroundColor3 = defaultState and Color3.fromRGB(0,100,180) or Color3.fromRGB(30,30,40)
	b.Text = "  " .. text .. (defaultState and " [ON]" or " [OFF]")
	b.TextColor3 = Color3.new(1,1,1)
	b.Font = Enum.Font.Gotham
	b.TextSize = 12
	b.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UICorner", b)
	local state = defaultState
	Connect(b.MouseButton1Click, function()
		state = not state
		b.Text = "  " .. text .. (state and " [ON]" or " [OFF]")
		b.BackgroundColor3 = state and Color3.fromRGB(0,100,180) or Color3.fromRGB(30,30,40)
		callback(state)
	end)
end

AddToggle(AutoCollectPage, "Master Auto Collect", false, function(v) State.AutoSpawnCollect = v end)
AddToggle(AutoCollectPage, "Anti-Water (Fix Kepiting)", true, function(v)
	State.RemoveWaterEnabled = v
	ApplyAntiWater(v)
end)

local function AddSectionHeader(parent, text)
	local lbl = Instance.new("TextLabel")
	lbl.Parent = parent
	lbl.Size = UDim2.new(1,0,0,22)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(170,170,170)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 10
end

local function AddCompactButton(parent, matKey, displayName, categoryTable)
	local btn = Instance.new("TextButton")
	btn.Parent = parent
	btn.Size = UDim2.new(1,0,0,26)
	btn.BackgroundColor3 = Color3.fromRGB(30,30,40)
	btn.Text = "  • " .. displayName
	btn.TextColor3 = Color3.fromRGB(200,200,200)
	btn.Font = Enum.Font.GothamMedium
	btn.TextSize = 11
	btn.TextXAlignment = Enum.TextXAlignment.Left
	Instance.new("UICorner", btn)

	local active = false
	Connect(btn.MouseButton1Click, function()
		active = not active
		categoryTable[matKey] = active
		if active then
			btn.BackgroundColor3 = Color3.fromRGB(0, 150, 80)
			btn.TextColor3 = Color3.new(1,1,1)
		else
			btn.BackgroundColor3 = Color3.fromRGB(30,30,40)
			btn.TextColor3 = Color3.fromRGB(200,200,200)
		end
	end)
end

AddSectionHeader(AutoCollectPage, "--- PILIH BAHAN (AMBIL) ---")
AddCompactButton(AutoCollectPage, "Spawn_Dupa", "Spawn_Dupa", State.SelectedMaterials)
AddCompactButton(AutoCollectPage, "Spawn_JamurKuburan", "Spawn_JamurKuburan", State.SelectedMaterials)
AddCompactButton(AutoCollectPage, "Spawn_Kemenyan", "Spawn_Kemenyan", State.SelectedMaterials)
AddCompactButton(AutoCollectPage, "Spawn_Gagak", "Spawn_Gagak", State.SelectedMaterials)
AddCompactButton(AutoCollectPage, "Spawn_KepitingSungai", "Spawn_KepitingSungai", State.SelectedMaterials)
AddCompactButton(AutoCollectPage, "Spawn_Melati", "Spawn_Melati", State.SelectedMaterials)


----------------------------------------------------
-- HALAMAN 2: AUTO MINE & WOOD
----------------------------------------------------
local AutoFarmPage = Instance.new("ScrollingFrame")
AutoFarmPage.Parent = Content
AutoFarmPage.Size = UDim2.new(1,0,1,0)
AutoFarmPage.BackgroundTransparency = 1
AutoFarmPage.Visible = false
AutoFarmPage.CanvasSize = UDim2.new(0,0,3.2,0)
AutoFarmPage.ScrollBarThickness = 4

local pad2 = Instance.new("UIPadding")
pad2.Parent = AutoFarmPage
pad2.PaddingTop = UDim.new(0, 10)

local l2 = Instance.new("UIListLayout")
l2.Parent = AutoFarmPage
l2.SortOrder = Enum.SortOrder.LayoutOrder
l2.Padding = UDim.new(0, 8)

local TitleFarm = Instance.new("TextLabel")
TitleFarm.Parent = AutoFarmPage
TitleFarm.Size = UDim2.new(1,0,0,25)
TitleFarm.BackgroundTransparency = 1
TitleFarm.Text = "⛏️ MENU MINING & WOODCUTTING"
TitleFarm.TextColor3 = Color3.fromRGB(0,170,255)
TitleFarm.Font = Enum.Font.GothamBold
TitleFarm.TextSize = 12

AddToggle(AutoFarmPage, "Master Auto Mining (Beliung)", false, function(v) State.AutoMineEnabled = v end)
AddToggle(AutoFarmPage, "Master Auto Wood (Kapak)", false, function(v) State.AutoWoodEnabled = v end)

AddSectionHeader(AutoFarmPage, "--- PILIH BATU & POHON ---")
AddCompactButton(AutoFarmPage, "BatuKecil", "Batu Kecil", State.SelectedBatu)
AddCompactButton(AutoFarmPage, "BatuSedang", "Batu Sedang", State.SelectedBatu)
AddCompactButton(AutoFarmPage, "BatuBesar", "Batu Besar", State.SelectedBatu)
AddCompactButton(AutoFarmPage, "PohonKecil", "Pohon Kecil", State.SelectedPohon)
AddCompactButton(AutoFarmPage, "PohonSedang", "Pohon Sedang", State.SelectedPohon)
AddCompactButton(AutoFarmPage, "PohonBesar", "Pohon Besar", State.SelectedPohon)

local function AddSlider(parent, configKey, labelName, minVal, maxVal)
	local container = Instance.new("Frame")
	container.Parent = parent
	container.Size = UDim2.new(1,0,0,45)
	container.BackgroundTransparency = 1

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Parent = container
	titleLbl.Size = UDim2.new(1,-40,0,20)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "  Jeda " .. labelName .. " (Detik)"
	titleLbl.TextColor3 = Color3.fromRGB(200,200,200)
	titleLbl.Font = Enum.Font.Gotham
	titleLbl.TextSize = 11
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left

	local valLbl = Instance.new("TextLabel")
	valLbl.Parent = container
	valLbl.Size = UDim2.new(0,35,0,20)
	valLbl.Position = UDim2.new(1,-38,0,0)
	valLbl.BackgroundTransparency = 1
	valLbl.Text = tostring(State.ConfigWait[configKey])
	valLbl.TextColor3 = Color3.fromRGB(0,170,255)
	valLbl.Font = Enum.Font.GothamBold
	valLbl.TextSize = 11
	valLbl.TextXAlignment = Enum.TextXAlignment.Right

	local sliderBg = Instance.new("Frame")
	sliderBg.Parent = container
	sliderBg.Size = UDim2.new(1,-10,0,6)
	sliderBg.Position = UDim2.new(0,5,0,28)
	sliderBg.BackgroundColor3 = Color3.fromRGB(35,35,45)
	Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1,0)

	local sliderFill = Instance.new("Frame")
	sliderFill.Parent = sliderBg
	sliderFill.Size = UDim2.new(math.clamp((State.ConfigWait[configKey] - minVal)/(maxVal - minVal), 0, 1), 0, 1, 0)
	sliderFill.BackgroundColor3 = Color3.fromRGB(0,170,255)
	Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1,0)

	local sliderBtn = Instance.new("TextButton")
	sliderBtn.Parent = sliderBg
	sliderBtn.Size = UDim2.new(1,10,1,10)
	sliderBtn.Position = UDim2.new(0,-5,0,-5)
	sliderBtn.BackgroundTransparency = 1
	sliderBtn.Text = ""

	local sliding
	local function updateSlider(input)
		if sliderBg.AbsoluteSize.X <= 0 then return end
		local pos = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
		local val = math.floor((minVal + (maxVal - minVal) * pos) * 10) / 10
		sliderFill.Size = UDim2.new(pos, 0, 1, 0)
		valLbl.Text = tostring(val)
		State.ConfigWait[configKey] = val
	end

	Connect(sliderBtn.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = input
			parent.ScrollingEnabled = false
			updateSlider(input)
		end
	end)

	Connect(UIS.InputEnded, function(input)
		if sliding and (input == sliding or (sliding.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			sliding = nil
			parent.ScrollingEnabled = true
		end
	end)

	Connect(UIS.InputChanged, function(input)
		if sliding and (input == sliding or (sliding.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then
			updateSlider(input)
		end
	end)
	Connect(UIS.WindowFocusReleased, function()
		sliding = nil
		parent.ScrollingEnabled = true
	end)
end

AddSectionHeader(AutoFarmPage, "--- ATUR WAKTU SLIDER (MAKS 60 DETIK) ---")
AddSlider(AutoFarmPage, "BatuKecil", "Batu Kecil", 1, 60)
AddSlider(AutoFarmPage, "BatuSedang", "Batu Sedang", 1, 60)
AddSlider(AutoFarmPage, "BatuBesar", "Batu Besar", 1, 60)
AddSlider(AutoFarmPage, "PohonKecil", "Pohon Kecil", 1, 60)
AddSlider(AutoFarmPage, "PohonSedang", "Pohon Sedang", 1, 60)
AddSlider(AutoFarmPage, "PohonBesar", "Pohon Besar", 1, 60)


----------------------------------------------------
-- HALAMAN 3: AUTO KIOS TARUH (PILIH SLOT & 12 ITEM LENGKAP)
----------------------------------------------------
local AutoRestockPage = Instance.new("ScrollingFrame")
AutoRestockPage.Parent = Content
AutoRestockPage.Size = UDim2.new(1,0,1,0)
AutoRestockPage.BackgroundTransparency = 1
AutoRestockPage.Visible = false
AutoRestockPage.CanvasSize = UDim2.new(0,0,1.8,0)
AutoRestockPage.ScrollBarThickness = 4

local pad3 = Instance.new("UIPadding")
pad3.Parent = AutoRestockPage
pad3.PaddingTop = UDim.new(0, 10)

local l3 = Instance.new("UIListLayout")
l3.Parent = AutoRestockPage
l3.SortOrder = Enum.SortOrder.LayoutOrder
l3.Padding = UDim.new(0, 8)

local TitleRestock = Instance.new("TextLabel")
TitleRestock.Parent = AutoRestockPage
TitleRestock.Size = UDim2.new(1,0,0,25)
TitleRestock.BackgroundTransparency = 1
TitleRestock.Text = "🏪 MENU AUTO KIOS (TARUH)"
TitleRestock.TextColor3 = Color3.fromRGB(0,170,255)
TitleRestock.Font = Enum.Font.GothamBold
TitleRestock.TextSize = 12

AddToggle(AutoRestockPage, "Master Auto Taruh Kios", false, function(v) State.AutoTaruhEnabled = v end)

AddSectionHeader(AutoRestockPage, "--- PENGATURAN SLOT & ITEM ---")

local function AddSlotSelector(parent)
	local container = Instance.new("Frame")
	container.Parent = parent
	container.Size = UDim2.new(1,0,0,36)
	container.BackgroundTransparency = 1

	local lbl = Instance.new("TextLabel")
	lbl.Parent = container
	lbl.Size = UDim2.new(0.5,0,1,0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "  Pilih Slot Kios"
	lbl.TextColor3 = Color3.fromRGB(220,220,220)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left

	local btn = Instance.new("TextButton")
	btn.Parent = container
	btn.Size = UDim2.new(0.45,0,0,30)
	btn.Position = UDim2.new(0.52,0,0.1,0)
	btn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	btn.Text = "slot1 ▾"
	btn.TextColor3 = Color3.fromRGB(0,170,255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 11
	Instance.new("UICorner", btn)

	local currentIdx = 1
	Connect(btn.MouseButton1Click, function()
		currentIdx = currentIdx + 1
		if currentIdx > 12 then currentIdx = 1 end
		local slotName = "slot" .. tostring(currentIdx)
		State.SelectedTaruhSlot = slotName
		btn.Text = slotName .. " ▾"
	end)
end

local function AddItemSelector(parent)
	-- 12 Daftar item lengkap sesuai gambar game
	local items = {
		"Bunga Melati", "Dupa", "Jagung", "Jamur Rebus", "Kemenyan", "Kepiting Sungai",
		"Pisang Raja", "Sate Gagak", "Sate Kepiting", "Susu", "Telur", "Tumis Kamboja"
	}
	local container = Instance.new("Frame")
	container.Parent = parent
	container.Size = UDim2.new(1,0,0,36)
	container.BackgroundTransparency = 1

	local lbl = Instance.new("TextLabel")
	lbl.Parent = container
	lbl.Size = UDim2.new(0.5,0,1,0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "  Pilih Item Barang"
	lbl.TextColor3 = Color3.fromRGB(220,220,220)
	lbl.Font = Enum.Font.Gotham
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left

	local btn = Instance.new("TextButton")
	btn.Parent = container
	btn.Size = UDim2.new(0.45,0,0,30)
	btn.Position = UDim2.new(0.52,0,0.1,0)
	btn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	btn.Text = "Bunga Melati ▾"
	btn.TextColor3 = Color3.fromRGB(0,170,255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 11
	Instance.new("UICorner", btn)

	local itemIdx = 1
	Connect(btn.MouseButton1Click, function()
		itemIdx = itemIdx + 1
		if itemIdx > #items then itemIdx = 1 end
		local itemName = items[itemIdx]
		State.SelectedTaruhItem = itemName
		btn.Text = itemName .. " ▾"
	end)
end

AddSlotSelector(AutoRestockPage)
AddItemSelector(AutoRestockPage)

local ExecuteTaruhBtn = Instance.new("TextButton")
ExecuteTaruhBtn.Parent = AutoRestockPage
ExecuteTaruhBtn.Size = UDim2.new(1,0,0,32)
ExecuteTaruhBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
ExecuteTaruhBtn.Text = "Taruh Barang Sekarang"
ExecuteTaruhBtn.TextColor3 = Color3.new(1,1,1)
ExecuteTaruhBtn.Font = Enum.Font.GothamBold
ExecuteTaruhBtn.TextSize = 12
Instance.new("UICorner", ExecuteTaruhBtn)

-- Manual and automatic requests share one in-flight lock.
local kioskBusy = false
local kioskTimedOut = false
local function RequestKiosk()
	if kioskBusy then
		Report(kioskTimedOut and "Kios belum merespons; permintaan tidak diulang." or "Menunggu respons kios...", false)
		return
	end
	local folder = ReplicatedStorage:FindFirstChild("rc645e8ded8e146828f98af5123faf3a8")
	local remote = folder and folder:FindFirstChild("r2c39d7b63e484766b0f0da9e3961ed82")
	if not remote or not remote:IsA("RemoteFunction") then
		Report("Kios tidak tersedia pada game ini.", true)
		return
	end
	kioskBusy = true
	kioskTimedOut = false
	local slot, item = State.SelectedTaruhSlot, State.SelectedTaruhItem
	local requestDone = false
	ExecuteTaruhBtn.Text = "Menunggu kios..."
	Spawn(function()
		local ok, response = pcall(function() return remote:InvokeServer("taruh", slot, item) end)
		requestDone = true
		kioskBusy = false
		kioskTimedOut = false
		if not running then return end
		ExecuteTaruhBtn.Text = "Taruh Barang Sekarang"
		if not ok then
			Report("Permintaan kios gagal: " .. tostring(response), true)
		elseif response == false then
			Report("Permintaan kios ditolak server.", true)
		else
			Report("Permintaan kios selesai; periksa isi slot di game.", false)
		end
	end)
	Spawn(function()
		if WaitWhile(10, function() return not requestDone end) then
			kioskTimedOut = true
			ExecuteTaruhBtn.Text = "Kios belum merespons"
			Report("Kios belum merespons; permintaan tidak diulang.", true)
		end
	end)
end
Connect(ExecuteTaruhBtn.MouseButton1Click, RequestKiosk)

-- Sistem Ganti Halaman (Tab Switching)
Connect(AutoCollectMenuBtn.MouseButton1Click, function()
	AutoCollectPage.Visible = true
	AutoFarmPage.Visible = false
	AutoRestockPage.Visible = false
	AutoCollectMenuBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
	AutoCollectMenuBtn.TextColor3 = Color3.new(1,1,1)
	AutoFarmMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	AutoFarmMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
	AutoRestockMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	AutoRestockMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
end)

Connect(AutoFarmMenuBtn.MouseButton1Click, function()
	AutoCollectPage.Visible = false
	AutoFarmPage.Visible = true
	AutoRestockPage.Visible = false
	AutoFarmMenuBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
	AutoFarmMenuBtn.TextColor3 = Color3.new(1,1,1)
	AutoCollectMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	AutoCollectMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
	AutoRestockMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	AutoRestockMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
end)

Connect(AutoRestockMenuBtn.MouseButton1Click, function()
	AutoCollectPage.Visible = false
	AutoFarmPage.Visible = false
	AutoRestockPage.Visible = true
	AutoRestockMenuBtn.BackgroundColor3 = Color3.fromRGB(0,100,180)
	AutoRestockMenuBtn.TextColor3 = Color3.new(1,1,1)
	AutoCollectMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	AutoCollectMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
	AutoFarmMenuBtn.BackgroundColor3 = Color3.fromRGB(35,35,45)
	AutoFarmMenuBtn.TextColor3 = Color3.fromRGB(200,200,200)
end)

----------------------------------------------------
-- WORKERS: one movement action at a time; kiosk runs independently.
----------------------------------------------------
local prompts = {}
local cooldowns = setmetatable({}, {__mode = "k"})
local function RegisterPrompt(instance)
	if instance:IsA("ProximityPrompt") then table.insert(prompts, instance) end
end
for _, instance in ipairs(Workspace:GetDescendants()) do RegisterPrompt(instance) end
Connect(Workspace.DescendantAdded, RegisterPrompt)
Connect(Workspace.DescendantRemoving, function(instance)
	local index = table.find(prompts, instance)
	if index then table.remove(prompts, index) end
	cooldowns[instance] = nil
	local properties = waterParts[instance]
	if properties then
		for property, value in pairs(properties) do instance[property] = value end
		waterParts[instance] = nil
	end
end)

local modes = {
	{flag = "AutoSpawnCollect", selection = "SelectedMaterials", action = "Ambil bahan", cursor = 0},
	{flag = "AutoMineEnabled", selection = "SelectedBatu", action = "Tambang", tool = "Beliung Kayu", cursor = 0},
	{flag = "AutoWoodEnabled", selection = "SelectedPohon", action = "Tebang", tool = "Kapak Kayu", cursor = 0},
}

local function SelectedAncestor(prompt, selection)
	local ancestor = prompt.Parent
	while ancestor and ancestor ~= Workspace do
		if selection[ancestor.Name] then return ancestor end
		ancestor = ancestor.Parent
	end
	return nil
end

local function PromptCFrame(prompt)
	local parent = prompt.Parent
	if not parent then return nil end
	if parent:IsA("Attachment") then return parent.WorldCFrame end
	if parent:IsA("BasePart") then return parent.CFrame end
	if parent:IsA("Model") then
		local part = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart", true)
		return part and part.CFrame
	end
	return nil
end

local function ReleasePrompt()
	if heldPrompt then pcall(function() heldPrompt:InputHoldEnd() end) end
	heldPrompt = nil
end

local function ProcessMode(mode)
	if not State[mode.flag] or #prompts == 0 then return end
	local character = LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return end
	local count = #prompts
	for _ = 1, count do
		mode.cursor = mode.cursor % count + 1
		local prompt = prompts[mode.cursor]
		local target = prompt and SelectedAncestor(prompt, State[mode.selection])
		if target and prompt.Enabled and prompt.ActionText == mode.action
			and (cooldowns[prompt] or 0) <= os.clock() then
			local targetCFrame = PromptCFrame(prompt)
			if targetCFrame and prompt.MaxActivationDistance > 0 then
				if mode.tool and not EquipTool(character, humanoid, mode.tool) then return end
				local function active()
					return State[mode.flag] and State[mode.selection][target.Name] == true
						and LocalPlayer.Character == character and root.Parent == character
						and humanoid.Health > 0 and prompt:IsDescendantOf(Workspace) and prompt.Enabled
				end
				if not active() then return end
				if State.RemoveWaterEnabled then
					if swimmingStates[humanoid] == nil then
						swimmingStates[humanoid] = humanoid:GetStateEnabled(Enum.HumanoidStateType.Swimming)
					end
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
				end
				local distance = math.min(3, prompt.MaxActivationDistance * 0.6)
				local offset = mode.tool and targetCFrame.RightVector * distance or Vector3.new(0, distance, 0)
				root.CFrame = CFrame.new(targetCFrame.Position + offset, targetCFrame.Position)
				if not WaitWhile(0.3, active) then return end
				-- Exactly one hold sequence: do not also fire a second synthetic interaction.
				heldPrompt = prompt
				prompt:InputHoldBegin()
				local completed = WaitWhile(math.max(0, prompt.HoldDuration) + 0.05, active)
				ReleasePrompt()
				if completed then
					cooldowns[prompt] = os.clock() + (mode.tool and State.ConfigWait[target.Name] or 0.5)
				end
				return
			end
		end
	end
end

Connect(LocalPlayer.CharacterRemoving, function(character)
	ReleasePrompt()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and swimmingStates[humanoid] ~= nil then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, swimmingStates[humanoid])
		swimmingStates[humanoid] = nil
	end
end)

ApplyAntiWater(State.RemoveWaterEnabled)
Spawn(function()
	while WaitWhile(0.1) do
		for _, mode in ipairs(modes) do
			if not running then break end
			local ok, err = pcall(ProcessMode, mode)
			if not ok then
				ReleasePrompt()
				Report("Interaksi gagal: " .. tostring(err), true)
			end
		end
	end
end)
Spawn(function()
	while WaitWhile(0.2) do
		if State.AutoTaruhEnabled then
			RequestKiosk()
			WaitWhile(3, function() return State.AutoTaruhEnabled end)
		end
	end
end)

-- Canvas follows actual content; controls stay reachable on small screens.
for _, page in ipairs({AutoCollectPage, AutoFarmPage, AutoRestockPage}) do
	page.CanvasSize = UDim2.fromOffset(0, 0)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local layoutOrder = 0
	for _, child in ipairs(page:GetChildren()) do
		if child:IsA("GuiObject") then
			layoutOrder = layoutOrder + 1
			child.LayoutOrder = layoutOrder
		end
	end
end

----------------------------------------------------
-- FLOATING BUTTON: mouse/touch drag, viewport bounds, no toggle after dragging.
----------------------------------------------------
local Float = Instance.new("TextButton", Gui)
Float.Name = "DarusToggle"
Float.Size = UDim2.fromOffset(56, 56)
Float.Position = UDim2.fromOffset(20, 120)
Float.Text = "DH"
Float.Font = Enum.Font.GothamBold
Float.TextSize = 18
Float.TextColor3 = Color3.fromRGB(0, 170, 255)
Float.BackgroundColor3 = Color3.fromRGB(20,20,25)
Instance.new("UICorner", Float).CornerRadius = UDim.new(1, 0)

local dragInput, dragStart, startPosition
local dragged = false
local suppressClickUntil = 0
local function ClampFloat(x, y)
	local size = Gui.AbsoluteSize
	Float.Position = UDim2.fromOffset(math.clamp(x, 0, math.max(0, size.X - 56)), math.clamp(y, 0, math.max(0, size.Y - 56)))
end
Connect(Float.MouseButton1Click, function()
	if os.clock() >= suppressClickUntil then Main.Visible = not Main.Visible end
end)
Connect(Float.InputBegan, function(input)
	if dragInput then return end
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragInput, dragStart = input, input.Position
		startPosition = Vector2.new(Float.Position.X.Offset, Float.Position.Y.Offset)
		dragged = false
	end
end)
Connect(UIS.InputChanged, function(input)
	if not dragInput then return end
	if input ~= dragInput and not (dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
	local delta = input.Position - dragStart
	if delta.Magnitude > 6 then dragged = true end
	if dragged then
		suppressClickUntil = os.clock() + 0.3
		ClampFloat(startPosition.X + delta.X, startPosition.Y + delta.Y)
	end
end)
Connect(UIS.InputEnded, function(input)
	if input == dragInput or (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1) then
		if dragged then suppressClickUntil = os.clock() + 0.3 end
		dragInput = nil
	end
end)
Connect(UIS.WindowFocusReleased, function()
	if dragInput then suppressClickUntil = os.clock() + 0.3 end
	dragInput = nil
end)
Connect(Gui:GetPropertyChangedSignal("AbsoluteSize"), function()
	ClampFloat(Float.Position.X.Offset, Float.Position.Y.Offset)
end)
ClampFloat(20, 120)
