# RAVEN HUB UI

RAVEN HUB now uses [MacLib](https://github.com/biggaboy212/Maclib) for the complete interface. The previous custom RAVEN UI runtime has been retired.

## Runtime

```lua
local MacLib = loadstring(game:HttpGet(
    "https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"
))()
```

`RAVENHUB` then loads `modules/maclib_adapter.lua`. The adapter only translates the existing Rayfield-style calls used by the game modules into MacLib controls; all visible windows, tabs, sections, controls, notifications, acrylic blur, user information, and configuration UI are rendered by MacLib.

## Supported compatibility calls

- `CreateWindow`
- `CreateTab` / `CreatePlaceholderTab`
- `CreateSection` / `CreateStatus` / `CreateLabel` / `CreateParagraph` / `CreateDivider`
- `CreateButton` / `CreateToggle` / `CreateSlider`
- `CreateDropdown` / `CreateInput` / `CreateKeybind`
- `Notify` / `Destroy` / `LoadAutoLoadConfig`

Use `RightShift` to hide or show the MacLib window.
