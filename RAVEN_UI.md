# RAVEN HUB UI Architecture

RAVEN HUB implements a dual-engine interface architecture with **100% Drawing API (Ghost Mode)** as the primary, zero-detection standard, backed by **MacLib** for environments without Drawing API.

---

## 1. Primary Engine: Ghost Drawing UI (`modules/drawing_ui.lua`)

The primary standard for RAVEN HUB is **100% Drawing API**.
It is specifically engineered for strict Anti-Cheat environments (Frog Anti-Cheat / BAC / fr0g, e.g. *BloxStrike*, *Basketball: Zero*, *Basketball: Current*).

### Why Ghost Mode?
- **Zero Roblox Instances Created**: Renders strictly through executor Drawing primitives (`Square`, `Text`, `Line`).
- **Zero Object Injection**: Completely avoids `ScreenGui`, `Frame`, `BillboardGui`, or `Highlight` in `CoreGui` or `PlayerGui`.
- **BAC / Fr0g Anti-Cheat Immunity**: Games using BAC scan `CoreGui` and monitor tree integrity for injected UI objects (`BAC - Alpha-3B` Error Code 267). Ghost Mode renders completely outside the Roblox DataModel, leaving zero traces for client-side scanners.

### Key Features
- **Window Controls**: Draggable header, custom titles, minimize keybind (`RightShift`), stealth dark theme.
- **Tab Bar & Navigation**: Instant tab switching with active indicator underlines and automatic tab ordering (`SortTabs`).
- **Interactive Controls**:
  - `CreateToggle`: On/Off state with colored square indicators and status tags.
  - `CreateSlider`: Smooth draggable slider bar with step rounding, percentage fill, and custom value suffixes.
  - `CreateDropdown`: Click-to-cycle option selection with truncated label safety.
  - `CreateKeybind`: Interactive listener for rebinding control hotkeys.
  - `CreateButton`: Responsive click triggers.
  - `CreateParagraph` / `CreateLabel` / `CreateStatus`: Text descriptions with dynamic `:Set()` updates.
  - `CreateDivider`: Visual separator lines.
- **Viewport Clipping & Scrolling**: Mouse-wheel scrolling with boundary clipping so controls never draw outside the window.
- **Clean Teardown Lifecycle**: Disconnects all user input events and calls `:Remove()` on all Drawing objects with zero memory leaks.

---

## 2. Universal Drawing ESP (`modules/drawing_esp.lua`)

Cross-game Drawing ESP engine used by all tactical modules:
- 2D Bounding Boxes with contrast outline
- Health Bar with dynamic HSV color transitions (Green -> Yellow -> Red)
- Target Name & Distance tag in meters/studs
- Equipped Weapon text overlay
- Optional Snaplines / Tracers & Head Dots
- Objective ESP (C4 Bomb, Basketball Rims & Balls)

---

## 3. Secondary Engine: MacLib Fallback

For legacy games or environments where executor `Drawing` is not supported, `RAVENHUB` gracefully falls back to `MacLib` via `modules/maclib_adapter.lua`.
*(Note: BAC-protected games automatically enforce Drawing Ghost Mode to ensure player accounts are never kicked or banned).*

---

## Supported Compatibility Calls

Both engines provide 100% drop-in call compatibility:
- `CreateWindow`
- `CreateTab` / `GetTab` / `SortTabs` / `CreatePlaceholderTab`
- `CreateSection` / `CreateStatus` / `CreateLabel` / `CreateParagraph` / `CreateDivider`
- `CreateButton` / `CreateToggle` / `CreateSlider` / `CreateDropdown` / `CreateKeybind`
- `Notify` / `Destroy` / `LoadAutoLoadConfig` / `OnUnload`

Use `RightShift` to hide or show the RAVEN HUB window.
