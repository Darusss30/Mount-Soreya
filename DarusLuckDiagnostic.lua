-- Darus Hub: read-only luck discovery. Run separately from DarusHub.lua.
-- Client-visible values and remote names do not establish server authority.
local Players = game:GetService("Players")
local player = assert(Players.LocalPlayer, "Jalankan di sisi pemain.")
local playerGui = player:WaitForChild("PlayerGui")
local previous = playerGui:FindFirstChild("DarusLuckDiagnostic")
if previous then previous:Destroy() end

local gui = Instance.new("ScreenGui", playerGui)
gui.Name = "DarusLuckDiagnostic"
gui.ResetOnSpawn = false
local panel = Instance.new("Frame", gui)
panel.Size = UDim2.fromScale(0.85, 0.8)
panel.Position = UDim2.fromScale(0.075, 0.1)
panel.BackgroundColor3 = Color3.fromRGB(22, 27, 36)
Instance.new("UICorner", panel)
local title = Instance.new("TextLabel", panel)
title.Size = UDim2.new(1, -55, 0, 38)
title.Position = UDim2.fromOffset(12, 0)
title.BackgroundTransparency = 1
title.Text = "DARUS HUB / DIAGNOSTIK LUCK v2"
title.TextColor3 = Color3.fromRGB(115, 226, 239)
title.TextSize = 14
title.Font = Enum.Font.GothamBold
title.TextXAlignment = Enum.TextXAlignment.Left

local function button(text, position, size)
	local item = Instance.new("TextButton", panel)
	item.Position, item.Size = position, size
	item.BackgroundColor3 = Color3.fromRGB(28, 74, 95)
	item.TextColor3 = Color3.new(1, 1, 1)
	item.Font, item.TextSize, item.Text = Enum.Font.Gotham, 12, text
	Instance.new("UICorner", item)
	return item
end
local close = button("X", UDim2.new(1, -38, 0, 6), UDim2.fromOffset(30, 28))
local scan = button("Pindai ulang", UDim2.new(0, 12, 1, -42), UDim2.new(0.5, -18, 0, 30))
local copy = button("Salin laporan", UDim2.new(0.5, 6, 1, -42), UDim2.new(0.5, -18, 0, 30))
local scroll = Instance.new("ScrollingFrame", panel)
scroll.Position, scroll.Size = UDim2.fromOffset(12, 42), UDim2.new(1, -24, 1, -94)
scroll.BackgroundTransparency, scroll.BorderSizePixel = 1, 0
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 4
local output = Instance.new("TextBox", scroll)
output.Size = UDim2.new(1, -10, 0, 0)
output.AutomaticSize = Enum.AutomaticSize.Y
output.BackgroundTransparency = 1
output.TextColor3 = Color3.fromRGB(220, 232, 241)
output.Font, output.TextSize = Enum.Font.Code, 12
output.TextXAlignment, output.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
output.MultiLine, output.TextEditable, output.ClearTextOnFocus, output.TextWrapped = true, false, false, true
output.Text = "Memindai data yang terlihat di klien..."

local running, busy, baseline = true, false, nil
local terms = {"luck", "keberuntungan", "rod", "pet", "friend", "teman", "event", "acara", "buff", "boost", "bonus", "cepat"}
local function relevant(text)
	text = text:lower()
	for _, term in ipairs(terms) do
		if text:find(term, 1, true) then return true end
	end
	return false
end
local function clean(value)
	return tostring(value):gsub("<[^>]*>", ""):gsub("[%c]", " "):sub(1, 180)
end
local function scalar(value)
	if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
	if type(value) == "string" and tonumber(value) then return clean(value) end
	return nil
end
local function ignored(path)
	local lower = path:lower()
	return lower:find("darus", 1, true) or lower:find("chat", 1, true)
end
local function capture()
	if busy or not running then return end
	busy = true
	scan.Text = "Memindai..."
	local values, structures, notices, count = {}, {}, {}, 0
	local function add(key, value)
		if values[key] == nil and count >= 250 then return end
		if values[key] == nil then count += 1 end
		values[key] = value
	end
	local function inspect(object, path)
		-- Skip hub output and chat so a scan cannot ingest its own report or chat text.
		if ignored(path) then return end
		local context = relevant(path)
		for key, value in pairs(object:GetAttributes()) do
			local generic = ({multiplier=true, value=true, amount=true, enabled=true, active=true})[key:lower()]
			local readable = scalar(value)
			if readable and (relevant(key) or (context and generic)) then add(path .. " @" .. key, readable) end
		end
		if context and (object:IsA("NumberValue") or object:IsA("IntValue") or object:IsA("BoolValue")) then
			add(path .. " .Value", tostring(object.Value))
		elseif context and (object:IsA("RemoteEvent") or object:IsA("RemoteFunction") or object:IsA("ModuleScript")) then
			if #structures < 100 then table.insert(structures, object.ClassName .. " " .. path) end
		end
		if object:IsA("TextLabel") or object:IsA("TextButton") then
			local text = clean(object.Text)
			if relevant(text) or (context and (text:match("^%s*[%dxXkKmMbB%.,%%+%-%s]+%s*$") or text:lower() == "dipakai")) then
				add(path .. " .Text", text)
			end
		end
	end
	local ok, err = pcall(function()
		-- Inventory pages get their own budget before unrelated inventory items/UI.
		inspect(player, "LocalPlayer")
		local roots, priorityRoots = {}, {}
		local inventory = playerGui:FindFirstChild("Inventory")
		local main = inventory and inventory:FindFirstChild("Main")
		local content = main and main:FindFirstChild("Content")
		local pages = content and content:FindFirstChild("Pages")
		if pages then
			for _, page in ipairs(pages:GetChildren()) do
				local name = page.Name:lower()
				if name:find("rod", 1, true) or name:find("pet", 1, true) then
					table.insert(roots, {page, "LocalPlayer/PlayerGui/Inventory/Main/Content/Pages/" .. page.Name})
					priorityRoots[page] = true
				end
			end
		end
		if inventory and #roots == 0 then
			table.insert(roots, {inventory, "LocalPlayer/PlayerGui/Inventory"})
			priorityRoots[inventory] = true
		end
		table.insert(roots, {player, "LocalPlayer"})
		table.insert(roots, {game:GetService("ReplicatedStorage"), "ReplicatedStorage"})
		if player.Character then table.insert(roots, {player.Character, "Character"}) end
		for _, entry in ipairs(roots) do
			local queue = {{entry[1], entry[2]}}
			local index = 1
			while index <= #queue and running do
				local object, path = queue[index][1], queue[index][2]
				if not ignored(path) then
					inspect(object, path)
					local children, nameCounts, nameIndexes = object:GetChildren(), {}, {}
					for _, child in ipairs(children) do nameCounts[child.Name] = (nameCounts[child.Name] or 0) + 1 end
					for _, child in ipairs(children) do
						if priorityRoots[child] then continue end
						if #queue >= 3000 then
							notices[entry[2]] = "Batas 3000 objek tercapai: " .. entry[2]
							break
						end
						nameIndexes[child.Name] = (nameIndexes[child.Name] or 0) + 1
						local name = child.Name
						if nameCounts[name] > 1 then name ..= "[" .. nameIndexes[child.Name] .. "]" end
						table.insert(queue, {child, path .. "/" .. name})
					end
				end
				index += 1
				if index % 150 == 0 then task.wait() end
			end
		end
		-- Global attributes only; do not traverse other players' world objects.
		inspect(game:GetService("Workspace"), "Workspace")
		inspect(game:GetService("Lighting"), "Lighting")
	end)
	if not running then return end
	local lines = {"Darus Hub diagnostik luck v2", "Nilai klien bukan bukti bahwa server menerima perubahan luck.",
		"Tidak mengubah data game, memanggil remote, atau menjalankan modul.",
		"Buka tab Rods/Pets di inventaris, lalu Pindai ulang. Kartu rod/pet diprioritaskan.",
		"Teks kartu adalah spesifikasi yang ditampilkan game; bukan otomatis total luck pemain.",
		"Ganti satu rod/pet melalui menu game, lalu tekan Pindai ulang untuk membandingkan.", ""}
	if not ok then table.insert(lines, "Pemindaian tidak lengkap: " .. clean(err)) end
	if baseline then
		table.insert(lines, "PERUBAHAN SEJAK PEMINDAIAN SEBELUMNYA:")
		local changes = {}
		for key, value in pairs(values) do
			if baseline[key] ~= value then table.insert(changes, key .. ": " .. (baseline[key] or "[belum terlihat]") .. " -> " .. value) end
		end
		for key in pairs(baseline) do
			if values[key] == nil then table.insert(changes, key .. ": [tidak terlihat pada pemindaian ini]") end
		end
		table.sort(changes)
		if #changes == 0 then table.insert(lines, "Tidak ada perubahan pada nilai yang terbaca.") end
		for index = 1, math.min(80, #changes) do table.insert(lines, changes[index]) end
		if #changes > 80 then table.insert(lines, "Perubahan lainnya tidak ditampilkan (batas 80).") end
	end
	table.insert(lines, "\nNILAI / ATRIBUT / TEKS TERKAIT (maks 250):")
	local keys = {}
	for key in pairs(values) do table.insert(keys, key) end
	table.sort(keys)
	for _, key in ipairs(keys) do table.insert(lines, key .. " = " .. values[key]) end
	if #keys == 0 then table.insert(lines, "Belum ada data cocok. Buka panel luck/pet lalu pindai ulang.") end
	table.insert(lines, "\nNAMA REMOTE / MODUL TERKAIT (maks 100; nama saja, fungsi belum diketahui):")
	table.sort(structures)
	for _, entry in ipairs(structures) do table.insert(lines, entry) end
	for _, notice in pairs(notices) do table.insert(lines, notice) end
	if count >= 250 then table.insert(lines, "Batas hasil tercapai; sebagian nilai mungkin tidak tercantum.") end
	output.Text = table.concat(lines, "\n")
	baseline, busy = values, false
	scan.Text, copy.Text = "Pindai ulang", "Salin laporan"
end
gui.Destroying:Connect(function() running = false end)
close.MouseButton1Click:Connect(function() gui:Destroy() end)
scan.MouseButton1Click:Connect(capture)
copy.MouseButton1Click:Connect(function()
	local ok = type(setclipboard) == "function" and pcall(setclipboard, output.Text)
	copy.Text = ok and "Tersalin" or "Pilih teks lalu salin manual"
end)
task.defer(capture)
