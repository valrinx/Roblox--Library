# Changelog

## 2026-08-21

- Added selectable left-click, right-click, or always-on activation for KILLSTREAK! Smooth Auto Lock, plus independent raycast Visible Checks for both player ESP and Auto Lock.
- Added configurable smooth enemy-only Auto Lock to KILLSTREAK! with sticky FOV targeting, head/root selection, and an enabled-by-default wall check.
- Updated KILLSTREAK! player ESP to exclude the local player's teammates and immediately clear existing teammate overlays after team changes.

## Unreleased

- Added the first KILLSTREAK! v1.0 module with read-only The Hill tracking, player/team ESP, health and distance labels, nearest-enemy summary, equipment overview, ping diagnostics, and cleanup-safe local overlays.
- Optimized Build and Crush v0.3.1 to cache vehicle contacts and objective part IDs, refresh spatial targeting at 0.15-second intervals, refresh world structure at 0.75-second intervals, keep damage sends lightweight, and throttle Aura UI updates to twice per second to prevent the v0.3 frame-rate regression.
- Upgraded Build and Crush to v0.3: Objective Aura now measures range from owned-vehicle contact parts instead of the player, targets the nearest objective part IDs, reports the real impact position, prefers weapon contacts, removes duplicate IDs, and runs at a faster configurable 0.04-second default interval.
- Upgraded Build and Crush to v0.2 with decoded `crushNet` Objective Aura safe/fast modes, owned-vehicle source validation, quest/gold/flying target filters, accurate nested chest and vehicle-owner ESP, objective rarity/HP/reward labels, and live Research, conveyor quest, plot, and crate timers sourced from the game's state atoms.
- Added the first Build and Crush module with cleanup-safe chest, objective, and vehicle ESP; live world/progression counters; manual nearest-target travel; reversible local performance controls; and anti-AFK. ZAP remote automation remains disabled until packet schemas are verified.
- Added a Dueling Grounds module with marker-driven Auto Parry, live half-ping compensation, configurable range/timing, opponent-facing checks, cleanup-safe guard input, automatic target selection, smooth auto-facing, and target highlighting. The attack catalog is generated from the game's weapon modules at runtime so new basic attacks are picked up without hard-coded animation IDs.
- Reworked RAVEN UI v1.1.0 to match the concept proportions with a floating 16:9 workbench, vertical icon rail, code-native raven/search/clock/profile icons, larger typography, wider dashboard, in-window toasts, and an explicit unsupported-experience state.
- Fixed RAVEN UI startup on executors without writable CoreGui by adding gethui/PlayerGui/CoreGui mounting fallbacks, tolerant property assignment, and visible bootstrap error reporting.
- Replaced the external Rayfield dependency with the original native `RAVEN UI` library, matching the dark tactical concept with responsive navigation, search, dashboard metrics, activity history, notifications, saved flags, and compatible controls.
- Added a modular TWDO3 combat suite with player/walker aimbot, automatic and sticky locking, head/body selection, strength/FOV/range/priority controls, manual distance-scaled velocity prediction, wall checks, delayed trigger bot, reversible player/walker head hitboxes, FOV/target overlays, and teammate filtering/ESP.
- Added the TWDO3 awareness suite: 2D radar, wall raycasts, threat colors, box/tracer/skeleton overlays, rarity/search loot filters, adaptive presets, proximity alerts, death markers, live player monitoring, persisted controls, panic clear, and FPS/ping/MCP diagnostics.
- Made player/walker HP text and bars react directly to Humanoid health changes, and immediately remove ESP when the Humanoid dies or its model is removed.
- Rebuilt ESP labels with separate name/detail rows, a compact 260px canvas, a 120px health bar, and live text-size/health-bar-width controls.
- Fixed ESP labels wrapping health values on long player names by using a wider fixed two-line layout, compact HP formatting, and a shorter health bar.
- Expanded TWDO3 ESP into an optimized multi-category system for players, walkers, and indexed loot containers, with distance/quantity caps, category filters, health bars, through-wall controls, live counts, and throttled cleanup-safe updates.
- Changed the TWDO3 module URL to the executor-safe `modules/twdo3.lua` path, retained a compatibility bridge for cached registries, and added visible hub build/module-load diagnostics so fetch, compile, and runtime failures no longer fail silently.
- Added a The Walking Dead Online 3 module with player ESP, configurable labels and distance, a live player picker, spectate controls, respawn handling, and cleanup on hub destruction.
