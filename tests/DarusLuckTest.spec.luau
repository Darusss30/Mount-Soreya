-- Shared client mock is supplied by run-luck.ps1.
player:SetAttribute("LuckPet",10)
player:SetAttribute("LuckPass",29)
player:SetAttribute("LuckTeman",0)
local function RunTest()
-- @LUCK_SOURCE@
end
local passed=0
local function check(value, message)
	assert(value,message)
	passed+=1
end
local function find(class, text)
	local gui=playerGui:FindFirstChild("DarusLuckTest")
	for _, object in ipairs(gui:GetDescendants()) do
		if object:IsA(class) and (object.Name==text or object.Text==text) then return object end
	end
	error("Missing UI: " .. text)
end
local function applyValue(value)
	find("TextBox","TestValue").Text=value
	find("TextButton","Uji 60 detik").MouseButton1Click:Fire()
end
RunTest()
step(0)
local report=find("TextBox","LuckTestReport")
check(player:GetAttribute("LuckPet")==10,"loading does not change luck")
notify.OnClientEvent:Fire("GotFish",{baseName="Baseline Fish",luckUsed=123,chance=0.0002})
check(report.Text:find("AWAL | rod=Withering Rod | ikan=Baseline Fish | luckUsed=123",1,true),"baseline event payload recorded")
for _, invalid in ipairs({"invalid","-1","1001","1e999"}) do
	applyValue(invalid)
	check(player:GetAttribute("LuckPet")==10,"invalid input rejected: " .. invalid)
end
applyValue("10")
check(report.Text:find("Nilai uji sama",1,true),"equal-value test does not begin")
applyValue("20")
check(player:GetAttribute("LuckPet")==20 and player:GetAttribute("LuckPass")==29,"only selected local LuckPet attribute changes")
notify.OnClientEvent:Fire("GotFish",{baseName="Test Fish",luckUsed=123,chance=0.0002})
check(report.Text:find("UJI 1 | rod=Withering Rod | ikan=Test Fish | luckUsed=123",1,true),"received luckUsed is recorded unchanged even if it did not rise")
applyValue("30")
check(player:GetAttribute("LuckPet")==20,"active test cannot overwrite saved original")
step(61)
check(player:GetAttribute("LuckPet")==10 and report.Text:find("batas waktu",1,true),"automatic timeout restores original")
applyValue("30")
find("TextButton","Pulihkan").MouseButton1Click:Fire()
check(player:GetAttribute("LuckPet")==10,"manual restore works")
applyValue("20")
player:SetAttribute("LuckPet",12)
step(1)
find("TextButton","Pulihkan").MouseButton1Click:Fire()
check(player:GetAttribute("LuckPet")==12 and report.Text:find("nilai terbaru dipertahankan",1,true),"external updates end test without overwriting newer luck")
applyValue("20")
RunTest()
step(0)
check(player:GetAttribute("LuckPet")==12,"rerun restores previous test before opening new window")
report=find("TextBox","LuckTestReport")
local oldNotify=notify
rod.Parent=nil
rodFor(player.Character,true)
step(1)
oldNotify.OnClientEvent:Fire("GotFish",{baseName="Stale Fish",luckUsed=999})
notify.OnClientEvent:Fire("GotFish",{baseName="Replacement Fish",luckUsed=125})
check(not report.Text:find("Stale Fish",1,true) and report.Text:find("Replacement Fish",1,true),"rod replacement removes stale listener and attaches replacement")
applyValue("20")
find("TextButton","X").MouseButton1Click:Fire()
check(player:GetAttribute("LuckPet")==12,"close restores original")
local captured=report.Text
notify.OnClientEvent:Fire("GotFish",{baseName="After Close",luckUsed=999})
step(61)
check(report.Text==captured and player:GetAttribute("LuckPet")==12,"close stops listener and background worker")
player:SetAttribute("LuckPet",nil)
RunTest()
applyValue("20")
check(player:GetAttribute("LuckPet")==nil,"missing numeric attribute is not invented")
find("TextButton","X").MouseButton1Click:Fire()
check(casts==0 and reels==0 and requestCalls==0,"test sends no fishing or HTTP requests")
print("PASS: " .. passed .. " LuckPet experiment checks (mock runtime)")
