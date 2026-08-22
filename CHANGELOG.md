# Changelog

## 2026-08-22

- Updated Cold War to v1.1.2 with target-aware visibility raycasts that ignore only the local character and accept direct hits on the intended target character instead of excluding the entire Characters folder.
- Updated Cold War to v1.1.1 so Prediction Dot and Auto Aim share one per-frame target-velocity and ballistic solution, eliminating divergence caused by sampling target movement twice in the same frame.
- Updated Cold War to v1.1 with ballistic smooth Auto Aim, configurable FOV/activation/sticky visibility targeting, a live match ticket/death/spawn dashboard, and a team-aware tactical radar.
- Fixed The Sea Kill Aura by sending the same primary-input path consumed by weapon LocalScripts instead of calling Tool:Activate, exempting Machete from ranged visibility filtering, and raising its default aura radius to 16 studs.
- Fixed The Sea Auto Collect repeatedly selecting the first pulled item by temporarily marking processed models and skipping resources already resting at the character drop point.
- Updated The Sea to v1.2.3 so Auto Collect requests temporary item ownership directly and moves items to the character without opening the game's cursor-bound drag state or cloning drag constraints.
- Updated The Sea to v1.2.2 with per-weapon long-range prediction (hitscan, Harpoon/Riptide, and Flare profiles) and character-anchored Auto Collect that overrides the drag cursor destination until release.
- Updated The Sea to v1.2.1 with multi-weapon target cycling, screen-space FOV targeting, a visible FOV ring, and category-filtered server-authorized Auto Collect for wood, metal, food, and fuel.
- Updated The Sea to v1.2 with bounded Creature ESP, health/visibility labels, configurable Machete Aura, optional Flintlock/Raygun aim and trigger assistance, Harpoon target diagnostics, and an explicit in-module version/status display.
- Updated The Sea to v1.1 with a selectable nearest-target compass, bounded multi-stop loot routes, and live inventory/sack capacity summaries.
- Added The Sea v1.0 with bounded treasure/resource/food/fuel ESP, island and merchant navigation, survival/currency/objective telemetry, Food/O2 warnings, and reversible Fullbright/FOV controls.

## 2026-08-21

- Fixed Operation One player silhouettes by resolving each Player to the game's visible `Workspace.Viewmodels` model; character collision models are fully transparent, so a through-wall 3D box remains as fallback whenever a render model is unavailable.
- Fixed Operation One ESP being completely hidden while dead, spectating, or behind cover: Visible Check now color-codes visible enemies green and covered enemies red instead of disabling their overlays; gadget character-owner references are also resolved back to Players before team filtering.
- Added the first Operation One v1.0 module with enemy-only visible-check ESP, Bomb/Claymore/Drone/Reinforcement intelligence, live match and player telemetry, flash reduction, custom FOV, and cleanup-safe local overlays.
- Fixed KILLSTREAK! Auto Lock for its FPS camera by using executor relative-mouse aiming, with Camera.CFrame retained as a compatibility fallback.
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
