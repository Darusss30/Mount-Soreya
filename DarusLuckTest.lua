-- Temporary client-side LuckPet experiment; no fishing/server requests are sent.
local player = assert(game:GetService("Players").LocalPlayer, "Jalankan di sisi pemain.")
local playerGui = player:WaitForChild("PlayerGui")
local previous = playerGui:FindFirstChild("DarusLuckTest")
if previous then previous:Destroy() end

local gui = Instance.new("ScreenGui", playerGui)
gui.Name, gui.ResetOnSpawn = "DarusLuckTest", false
local panel = Instance.new("Frame", gui)
panel.Size, panel.Position = UDim2.fromScale(0.85, 0.8), UDim2.fromScale(0.075, 0.1)
panel.BackgroundColor3 = Color3.fromRGB(22, 27, 36)
Instance.new("UICorner", panel)
local function textObject(class, text, position, size)
	local item = Instance.new(class, panel)
	item.Position, item.Size, item.Text = position, size, text
	item.BackgroundColor3 = Color3.fromRGB(28, 64, 80)
	item.TextColor3, item.Font, item.TextSize = Color3.fromRGB(222, 236, 245), Enum.Font.Gotham, 12
	item.TextWrapped = true
	Instance.new("UICorner", item)
	return item
end
local title = textObject("TextLabel", "DARUS HUB / UJI LUCKPET v1", UDim2.fromOffset(12, 4), UDim2.new(1, -60, 0, 30))
title.BackgroundTransparency, title.TextXAlignment = 1, Enum.TextXAlignment.Left
local close = textObject("TextButton", "X", UDim2.new(1, -38, 0, 5), UDim2.fromOffset(30, 28))
local hint = textObject("TextLabel", "Pancing dahulu untuk data awal. Saat pancing berhenti, isi nilai lalu tekan Uji 60 detik. Gunakan rod, pet, dan server yang sama.", UDim2.fromOffset(12, 40), UDim2.new(1, -24, 0, 58))
hint.BackgroundTransparency = 1
local target = textObject("TextBox", "20", UDim2.new(0, 12, 0, 104), UDim2.new(0.3, -16, 0, 34))
target.Name, target.PlaceholderText, target.ClearTextOnFocus = "TestValue", "LuckPet (0-1000)", false
local apply = textObject("TextButton", "Uji 60 detik", UDim2.new(0.3, 0, 0, 104), UDim2.new(0.35, -6, 0, 34))
local restore = textObject("TextButton", "Pulihkan", UDim2.new(0.65, 0, 0, 104), UDim2.new(0.35, -12, 0, 34))
local copy = textObject("TextButton", "Salin laporan", UDim2.new(0, 12, 1, -40), UDim2.new(1, -24, 0, 28))
local scroll = Instance.new("ScrollingFrame", panel)
scroll.Position, scroll.Size = UDim2.fromOffset(12, 150), UDim2.new(1, -24, 1, -200)
scroll.BackgroundTransparency, scroll.BorderSizePixel, scroll.ScrollBarThickness = 1, 0, 4
scroll.CanvasSize, scroll.AutomaticCanvasSize = UDim2.fromOffset(0, 0), Enum.AutomaticSize.Y
local output = textObject("TextBox", "", UDim2.fromOffset(0, 0), UDim2.new(1, -10, 0, 0))
output.Parent, output.AutomaticSize, output.BackgroundTransparency = scroll, Enum.AutomaticSize.Y, 1
output.Name, output.Font = "LuckTestReport", Enum.Font.Code
output.TextXAlignment, output.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
output.MultiLine, output.TextEditable, output.ClearTextOnFocus = true, false, false

local running, active, testIndex = true, false, 0
local original, applied, deadline, worker
local events, notes, hooks = {}, {}, {}
local phase, status = "AWAL", "Belum ada nilai yang diubah."
local function clean(value)
	return tostring(value):gsub("[%c]", " "):sub(1, 160)
end
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end
local function note(message)
	table.insert(notes, message)
	if #notes > 20 then table.remove(notes, 1) end
end
local function report()
	local listenerCount = 0
	for _ in pairs(hooks) do listenerCount += 1 end
	local lines = {"Darus Hub uji LuckPet v1", status,
		"LuckPet lokal saat ini: " .. clean(player:GetAttribute("LuckPet")),
		"Fase: " .. phase .. (active and ("; sisa " .. math.max(0, math.ceil(deadline - os.clock())) .. " detik") or ""),
		"Listener NotifyClient rod: " .. listenerCount,
		"Perubahan lokal/UI bukan bukti server menerima luck baru.",
		"luckUsed dicatat dari payload GotFish; makna dan rumusnya belum diverifikasi.",
		"Fase mengikuti waktu event diterima. Selesaikan lemparan sebelum memulai/mengakhiri uji.", "\nCATATAN:"}
	for _, message in ipairs(notes) do table.insert(lines, message) end
	table.insert(lines, "\nTANGKAPAN (40 event terakhir, terbaru di bawah):")
	if #events == 0 then table.insert(lines, "Belum ada event GotFish. Lakukan tangkapan melalui game.") end
	for _, event in ipairs(events) do table.insert(lines, event) end
	return table.concat(lines, "\n")
end
local function refresh()
	if running then output.Text = report() end
end
local function restoreValue(reason)
	if not active then return end
	local current = player:GetAttribute("LuckPet")
	if current == applied then
		local ok, err = pcall(function() player:SetAttribute("LuckPet", original) end)
		if not ok then
			status = "Pemulihan gagal: " .. clean(err)
			note(status)
			return false
		end
		status = "LuckPet dipulihkan ke " .. clean(original) .. " (" .. reason .. ")."
	else
		status = "LuckPet sudah berubah menjadi " .. clean(current) .. "; nilai terbaru dipertahankan (" .. reason .. ")."
	end
	active, phase = false, "SETELAH UJI " .. testIndex
	note(status)
	return true
end
local function beginTest()
	if not running then return end
	if active then status = "Uji masih aktif. Pulihkan dahulu untuk memulai uji baru."; refresh(); return end
	local value, current = tonumber(target.Text), player:GetAttribute("LuckPet")
	if not finite(value) or value < 0 or value > 1000 then
		status = "Masukkan nilai LuckPet antara 0 dan 1000."; refresh(); return
	end
	if not finite(current) then
		status = "Atribut LuckPet numerik belum tersedia; uji belum dijalankan."; refresh(); return
	end
	if value == current then status = "Nilai uji sama dengan nilai saat ini; pilih nilai berbeda."; refresh(); return end
	original, applied, deadline = current, value, os.clock() + 60
	local ok, err = pcall(function() player:SetAttribute("LuckPet", value) end)
	if not ok then status = "Gagal mengubah nilai lokal: " .. clean(err); refresh(); return end
	testIndex += 1
	active, phase = true, "UJI " .. testIndex
	status = "LuckPet lokal: " .. clean(original) .. " -> " .. clean(applied) .. ". Pemulihan otomatis setelah 60 detik."
	note(status)
	refresh()
end
local function inCurrentInventory(remote)
	local backpack = player:FindFirstChild("Backpack")
	return (player.Character and remote:IsDescendantOf(player.Character)) or (backpack and remote:IsDescendantOf(backpack))
end
local function attachRod(tool)
	if not tool:IsA("Tool") then return end
	local mechanics = tool:FindFirstChild("Mechanics")
	local remotes = mechanics and mechanics:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("NotifyClient")
	if not remote or not remote:IsA("RemoteEvent") or hooks[remote] then return end
	hooks[remote] = remote.OnClientEvent:Connect(function(action, data)
		if not running or not inCurrentInventory(remote) or action ~= "GotFish" or type(data) ~= "table" then return end
		local entry = phase .. " | rod=" .. clean(tool.Name) .. " | ikan=" .. clean(data.baseName or data.originalName)
			.. " | luckUsed=" .. clean(data.luckUsed) .. " | chance=" .. clean(data.chance)
			.. " | LuckPet lokal=" .. clean(player:GetAttribute("LuckPet"))
			.. " | LuckPass=" .. clean(player:GetAttribute("LuckPass")) .. " | LuckTeman=" .. clean(player:GetAttribute("LuckTeman"))
		table.insert(events, entry)
		if #events > 40 then table.remove(events, 1) end
		refresh()
	end)
end
local function update()
	if active then
		if player:GetAttribute("LuckPet") ~= applied then restoreValue("nilai berubah di luar uji")
		elseif os.clock() >= deadline then restoreValue("batas waktu") end
	end
	for remote, connection in pairs(hooks) do
		if not inCurrentInventory(remote) then connection:Disconnect(); hooks[remote] = nil end
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then for _, tool in ipairs(backpack:GetChildren()) do attachRod(tool) end end
	if player.Character then for _, tool in ipairs(player.Character:GetChildren()) do attachRod(tool) end end
	refresh()
end
gui.Destroying:Connect(function()
	if not running then return end
	if restoreValue("jendela ditutup/dijalankan ulang") == false then warn("[Darus Hub] " .. status) end
	running = false
	for _, connection in pairs(hooks) do connection:Disconnect() end
	if worker and coroutine.status(worker) ~= "dead" then task.cancel(worker) end
end)
close.MouseButton1Click:Connect(function() gui:Destroy() end)
apply.MouseButton1Click:Connect(beginTest)
restore.MouseButton1Click:Connect(function() restoreValue("tombol Pulihkan"); refresh() end)
copy.MouseButton1Click:Connect(function()
	refresh()
	local ok = type(setclipboard) == "function" and pcall(setclipboard, output.Text)
	copy.Text = ok and "Tersalin" or "Pilih teks lalu salin manual"
end)
update()
worker = task.defer(function()
	while running do
		task.wait(1)
		if running then update() end
	end
end)
