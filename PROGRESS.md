# UMT Modularization Progress

## Completed
- [x] `ore_resolver.lua` - Pure ore resolution utilities (normalization, signatures, color, inference, mapping, world inspection, default static tables)
- [x] `settings.lua` - Settings I/O (saveAsync, isStringMap, mergeStringMap, buildDefaults, applyDecoded, unwrapPayload)
- [x] `esp.lua` - ESP scan/watch helpers (scanAll, bindFolder, countActiveVisuals)
- [x] `esp_runtime.lua` - ESP visual lifecycle (clearAll, setVisualVisibility, syncVisualStyle, createOreVisuals)
- [x] `auto_mine.lua` - Auto Mine utilities (randomRange, hasNearbyPlayers, isMadCommIdAllowed, markMadCommRemoteInvalid, resolveToolMadCommId, resolveActivateRemote, pickMineActivateRemoteAlternateDiscovered, mineGridForActivateRemote, buildGridCandidates, ensureRemoteClientDrain, nextDrillPacketNonce)
- [x] `sell.lua` - Sell ore utilities (countCarriedOres, findSellTargets, sellFromAnywhere, sellByMethod)
- [x] `safe_ui.lua` - Safe UI wrappers (wrapNotify, patchRayfield, safeSetText)
- [x] `player_util.lua` - Player helpers (setWalkSpeed, applyWalkSpeedOnSpawn, startInfiniteJump, stopConnection, getHumanoid, getRootPart)
- [x] Legacy script wired with fallback for all above helpers
- [x] `auto_mine_loop.lua` - Auto Mine main loop extracted with `ctx` state-bag pattern and inline fallback
- [x] ESP Billboard now shows ore price from `oreReferenceFromList` (`esp_runtime.lua` + legacy script updated)
- [x] Cache-bust bumped to `umt-modular-12`
- [x] README changelog updated

## Next Priority: Main Loop Extraction

### 1. ESP Heartbeat Loop
**Target:** `modules/umt/systems/esp_loop.lua`
**Scope:** Extract the `RunService.Heartbeat` connection that updates ESP visuals
**State to pass:** `ESP` table, `oreNameCache`

### 2. Auto Sell Loop
**Target:** `modules/umt/systems/auto_sell_loop.lua`
**Scope:** Extract `task.spawn` inside `AutoSellToggle.Callback`
**State to pass:** `autoSellEnabled`, `autoSellOreCount`, `safeSellCooldown`, `safeNearbyPauseEnabled`, `safeNearbyRadius`

### 3. UI Tab Builders (Lower Priority)
- `modules/umt/ui/farm_tab.lua` - Farm tab creation (Auto Mine + Safe Profile + Ore Ignore + Auto Sell controls)
- `modules/umt/ui/esp_tab.lua` - Ore ESP tab creation
- `modules/umt/ui/mobile_tab.lua` - Mobile tab creation
- `modules/umt/ui/misc_tab.lua` - Misc tab creation (WalkSpeed, Infinite Jump, Shop TP, Vehicle)

## Cache-Bust Strategy
Current: `umt-modular-12`. Next bump: `umt-modular-13` when ESP loop or Auto Sell loop is extracted.

## New Project: Blackhawk Rescue Mission 5 ESP

### Completed (2026-05-01)
- [x] `modules/BlackhawkRescue5_ESP/main.lua` - Core ESP system with Drawing API
- [x] `modules/BlackhawkRescue5_ESP/entity_detector.lua` - BRM5-specific entity detection
- [x] `modules/BlackhawkRescue5_ESP/loader.lua` - Simple loader script
- [x] `RAVENHUB` - Added BRM5 to script registry with auto-detector

**Features:**
- Player ESP (blue) - Name, Distance, Health, Box
- Zombie ESP (red) - Auto-detects zombie/infected patterns
- AI ESP (yellow) - Detects NPCs, enemies, hostiles
- Performance optimized with distance culling and throttled scans
- Auto-load when entering BRM5 map

## Notes
- All helper modules are pure functions or self-contained
- Legacy script uses `pcall` + `type(helper.function) == "function"` fallback pattern
- Keep fallback implementations in legacy script until helper is proven stable
