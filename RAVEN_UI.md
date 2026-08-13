# RAVEN UI

RAVEN UI is the repository's original native Roblox interface library. It uses Roblox GUI instances directly and has no Rayfield dependency.

## Load

```lua
local RavenUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/valrinx/Roblox--Library/refs/heads/main/modules/raven_ui.lua"
))()

local Window = RavenUI:CreateWindow({
    Name = "RAVEN UI",
    LoadingTitle = "RAVEN UI | v1.0.0",
    LoadingSubtitle = "by valrinx",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "RAVENHUB",
        FileName = "HubConfig",
    },
})
```

## Controls

```lua
local Tab = Window:CreateTab("Automation")
Tab:CreateSection("Mining")

local Status = Tab:CreateLabel("Ready")
Status:Set("Connected")

Tab:CreateToggle({
    Name = "Auto Mine",
    CurrentValue = false,
    Flag = "AutoMine",
    Callback = function(enabled)
        print("Auto Mine", enabled)
    end,
})

Tab:CreateSlider({
    Name = "Walk Speed",
    Range = {16, 100},
    Increment = 1,
    Suffix = " studs/s",
    CurrentValue = 24,
    Flag = "WalkSpeed",
    Callback = function(value)
        print("Walk Speed", value)
    end,
})

local Profile = Tab:CreateDropdown({
    Name = "Performance Preset",
    Options = {"Low", "Balanced", "Ultra"},
    CurrentOption = {"Balanced"},
    Flag = "PerformancePreset",
    Callback = function(selection)
        print(selection[1])
    end,
})

Profile:Refresh({"Low", "Balanced", "Ultra"}, true)

Tab:CreateInput({
    Name = "Loot Name Search",
    PlaceholderText = "ammo, military, fridge...",
    CurrentValue = "",
    Flag = "LootSearch",
    Callback = function(value)
        print(value)
    end,
})

Tab:CreateKeybind({
    Name = "Panic Key",
    CurrentKeybind = "End",
    HoldToInteract = false,
    Flag = "PanicKey",
    Callback = function()
        print("Panic")
    end,
})

Tab:CreateButton({
    Name = "Destroy Hub",
    Callback = function()
        RavenUI:Destroy()
    end,
})
```

Use `RightShift` to hide or show the interface. Controls with a `Flag` are saved when `ConfigurationSaving.Enabled` is enabled and the executor exposes file APIs.
