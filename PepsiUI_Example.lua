--[[
	Pepsi UI v2.1 - starter script
	Loads the library from your GitHub. Build your own tabs the same way.
]]

local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Esmam3/67/refs/heads/main/pepsihubUI.txt"))()

local Window = UI:CreateWindow({
	Title = "Pepsi Hub",
	Subtitle = "Game name",
	ToggleKey = Enum.KeyCode.RightControl, -- PC key that opens and hides the menu
})

Window:BuildHome({ Discord = "https://discord.gg/yourserver" })

local Main = Window:Tab({ Name = "Main", Icon = "swords", Description = "Farming" })
local Farm = Main:Section({ Name = "Auto farm", Icon = "wheat", Side = "Left" })

local autoFarm = Farm:Toggle({
	Name = "Auto farm",
	Description = "Farms the closest mob",
	Flag = "AutoFarm",
	Callback = function(on)
		-- your code here
	end,
})
autoFarm:AddKeybind({ Default = "F" }) -- press F to flip it (phones get an on-screen button)

Farm:Slider({ Name = "Speed", Min = 16, Max = 200, Default = 60, Suffix = " ws", Flag = "Speed" })
Farm:RangeSlider({ Name = "Delay", Min = 0, Max = 100, Default = { 20, 60 }, Suffix = "ms", Flag = "Delay" })
Farm:Dropdown({ Name = "Mob", Options = { "Bandit", "Pirate", "Marine" }, Default = "Bandit", Flag = "Mob" })

local Other = Main:Section({ Name = "Other", Icon = "zap", Side = "Right" })
Other:Button({ Name = "Teleport to quest", Style = "Primary", Callback = function()
	UI:Notify({ Title = "Teleporting", Content = "Hang on...", Type = "Success" })
end })

Window:BuildSettings() -- theme editor, sounds, configs, rejoin, unload
Window:LoadAutoload()

-- Read a value anywhere: UI.Flags.AutoFarm, UI.Flags.Speed, UI.Flags.Delay[1] / [2]
UI:OnUnload(function()
	-- turn your features off here
end)
