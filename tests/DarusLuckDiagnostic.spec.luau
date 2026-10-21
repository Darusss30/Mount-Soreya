-- Uses the shared client mock from DarusHub.spec.luau via run-luck.ps1.
local function ui(class, parent, name, text)
	local object = Instance.new(class, parent)
	object.Name = name
	if text then object.Text = text end
	return object
end
-- Reproduce the user's truncated scan: unrelated UI fills the ordinary budget.
for index=1,3100 do ui("Frame",playerGui,"Unrelated" .. index) end
local inventory = ui("ScreenGui",playerGui,"Inventory")
local main = ui("Frame",inventory,"Main")
local content = ui("Frame",main,"Content")
local pages = ui("Frame",content,"Pages")
local rods = ui("Frame",pages,"Rods")
local withering = ui("Frame",rods,"Kartu")
ui("TextLabel",withering,"Name","Withering Rod")
local witheringLuck = ui("TextLabel",withering,"Luck","Keberuntungan: 1.8K")
ui("TextLabel",withering,"Equipped","DIPAKAI")
local diamond = ui("Frame",rods,"Kartu")
ui("TextLabel",diamond,"Name","Diamond Rod")
ui("TextLabel",diamond,"Luck","Keberuntungan:")
ui("TextLabel",diamond,"Value","1.4K")
local pets = ui("Frame",pages,"Pets2")
ui("TextLabel",pets,"Bonus","Keberuntungan: 10%")
player:SetAttribute("LuckPass",29)
local function RunDiagnostic()
-- @LUCK_SOURCE@
end
RunDiagnostic()
step(10)
local diagnostic = playerGui:FindFirstChild("DarusLuckDiagnostic")
local report, rescan
for _, object in ipairs(diagnostic:GetDescendants()) do
	if object:IsA("TextBox") then report=object end
	if object:IsA("TextButton") and object.Text == "Pindai ulang" then rescan=object end
end
local passed=0
local function check(value, message)
	assert(value,message)
	passed+=1
end
check(report.Text:find("diagnostik luck v2",1,true),"new diagnostic version visible")
check(report.Text:find("Kartu[1]/Luck .Text = Keberuntungan: 1.8K",1,true),"localized Withering luck survives the ordinary UI scan limit")
check(report.Text:find("Kartu[2]/Value .Text = 1.4K",1,true),"separate compact Diamond value and duplicate card names preserved")
check(report.Text:find("Equipped .Text = DIPAKAI",1,true),"equipped label captured")
check(report.Text:find("Pets2/Bonus .Text = Keberuntungan: 10%",1,true),"pet page also prioritized")
check(report.Text:find("LocalPlayer @LuckPass = 29",1,true),"player attributes retained alongside rod specifications")
check(report.Text:find("Batas 3000 objek tercapai: LocalPlayer",1,true),"remaining scan truncation explicitly reported")
witheringLuck.Text="Keberuntungan: 1.9K"
task.defer(function() rescan.MouseButton1Click:Fire() end)
step(10)
check(report.Text:find("Keberuntungan: 1.8K -> Keberuntungan: 1.9K",1,true),"rescan compares localized card values")
check(casts==0 and reels==0 and player:GetAttribute("LuckPass")==29,"diagnostic does not invoke fishing remotes or alter luck")
diagnostic:Destroy()
step(1)
print("PASS: " .. passed .. " luck diagnostic regression checks (mock runtime)")
