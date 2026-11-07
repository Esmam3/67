# Pepsi UI

The Roblox UI library behind Pepsi Hub. One file, works on PC and mobile.

## Files

| File | What it is |
|---|---|
| `PepsiUI.lua` | The library source |
| `PepsiUI_Demo.lua` | A window with every element, to try it out |
| `PepsiUI_Example.lua` | A small starter script to copy for your own hub |

## Run the demo

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Esmam3/67/refs/heads/pepsi-ui/PepsiUI_Demo.lua"))()
```

## Use it in a script

```lua
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Esmam3/67/refs/heads/pepsi-ui/PepsiUI.lua"))()

local Window = UI:CreateWindow({
	Title = "Pepsi Hub",
	Subtitle = "Game name",
	ToggleKey = Enum.KeyCode.RightControl,
})

local Main = Window:Tab({ Name = "Main", Icon = "swords" })
local Farm = Main:Section({ Name = "Auto farm", Side = "Left" })

Farm:Toggle({ Name = "Auto farm", Flag = "AutoFarm", Callback = function(on) end })
Farm:Slider({ Name = "Speed", Min = 16, Max = 200, Default = 60, Suffix = " ws", Flag = "Speed" })
Farm:Dropdown({ Name = "Mob", Options = { "Bandit", "Pirate" }, Default = "Bandit", Flag = "Mob" })
Farm:Button({ Name = "Teleport", Callback = function() end })

Window:BuildSettings() -- themes, menu key, configs, unload
Window:LoadAutoload()
```

## Elements

- `Toggle` (with `AddKeybind` / `AddColorpicker`), `Slider`, `RangeSlider`, `Dropdown` (single, multi, players)
- `Button`, `Buttons`, `Textbox`, `Keybind`, `Colorpicker`, `Stepper`, `Segmented`, `Radio`, `Checkboxes`, `Chips`
- `Paragraph`, `Label`, `Divider`, `Progress`, `Stats`, `Graph`, `Console`, `Code`, `Image`, `Card`, `Link`
- Containers: `Tab`, `Tab:SubTab`, `Section` (Left / Right / Full, collapsible), `TabBox`, `Section:Group`

Every element has `:Set(v)`, `:Get()`, `.Value`, `:OnChanged(fn)`, `:SetVisible(bool)` and `:SetLocked(bool, reason)`.
Read any value with `UI.Flags.FlagName`.

## Notes

- Settings (theme, menu key, toggle style, transparency) are saved per player in `PepsiUI/settings.json`.
- Configs are saved per game in `PepsiUI/configs/<PlaceId>/`.
- Phones get a floating Pepsi Hub button to open and close the menu.
