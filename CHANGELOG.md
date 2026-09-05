- **Iron Soul: Dungeon v1.6.2** - Fixed Auto Dungeon matchmaking entry deadlock and Auto Sell dropdowns & execution:
  - **Auto Dungeon Matchmaking**: Removed premature `firetouchinterest(root, touch, 1)` and linear velocity impulse that kicked the player off the room pad before match creation. Removed `LP:GetAttribute("EnterRoomId")` deadlock guard in `requestDungeonEntry` to ensure `SelectWorld` and `CreatRoom` fire reliably and teleport the player into the dungeon.
  - **Auto Sell Dropdowns & Master Catalog**: Fixed empty dropdown options caused by deferred framework loading. Implemented full catalog extraction for all 53 Ores and 21 Crystals with interactive refresh buttons. Added fallback rarity tiers and protected currently equipped items from being sold.
- **Beeconomy! v2.0.1** - Fixed Auto Rock Mining and Tool Equip Audio Spam:
  - **Auto Rock Mining**: Corrected `BreakableRocks:tryMineRockTarget(1, rock)` parameter binding where the 1st argument is the hit quality score (`1` for 100% perfect hit) and the 2nd argument is the rock Model target (previously passed as `(rock)` causing `p2` to be `nil` and triggering early return). Added direct authoritative network call `Network:send("MineRock", rock.Name, rockKey, 1)` and `ToolsManager:playPickaxeAction()`.
  - **Rock & Tree Positioning**: Fixed character climbing on top of rocks/trees by computing a 4.5-stud ground-level approach offset from the target center towards the player (`standPos`) with automatic look-at CFrame facing, preventing collision issues and standing on top of targets.
  - **Alive Target Filtering**: Filtered out dead/broken rocks and trees in `getNearestRock()` and `getNearestTree()` using `BreakableRocks.stateByKey[Name .. "\0" .. Key].dead` and `BreakableTrees.stateByKey`.
  - **Tool Equip Audio Spam Fix**: Added `isAlreadyEquipped` guard in `ensureToolEquipped(kind)` checking `ToolsManager:isHoldingKind(kind)` and `GripHoldKind` attribute (and character `Tool` instance for pollen tools). Completely eliminated repeated equip sound spamming in automation loops (0.22s-0.25s) by immediately returning when the desired tool is already held.
- **Beeconomy! v2.0.0 (Universal Multi-Tool Edition)** - Full future-proof overhaul supporting all 110+ current and future tools across 5 categories (`tool`, `axe`, `pickaxe`, `fishing_rod`, `net`). Implemented dynamic OOP binding to `PlayerData.equipment`, `BackpackToolKinds`, `GripKinds`, and `ToolsManager` to automatically detect, index, and equip any current and newly introduced gear without requiring future script updates. Added new "Gathering & Multi-Tool" tab featuring: Auto Mine Rocks with Pickaxe (`BreakableRocks:tryMineRockTarget` & `ToolsManager:playPickaxeAction` targeting `Workspace.World1.Combat.BreakableRocks`), Auto Chop Trees with Axe (`BreakableTrees:tryChopTarget` & `ToolsManager:playAxeSwing` targeting `Workspace.World1.Combat.BreakableTrees`), Auto Catch Beetles with Bug Net (`NetCatchingMinigame:tryCatchMob` & `ToolsManager:playNetSwing` targeting active mobs), Quick Equip buttons for all 5 tool kinds with dynamic name resolution, adjustable scan reach sliders, and seamless tool state preservation across teleports and honey conversions.
- **Beeconomy! v1.4.0** - Added Universal Pollen Tool Auto-Equip supporting all harvesting tools in the game (Shovels, Elite Rakes, Wands, Vacuums, Clippers) by querying `clientController.BackpackToolKinds.isPollenCollectionTool` and dynamically syncing with `PlayerData.equipment.tool` and `ToolsManager:selectHotbarGear`. Fixed flower stagnation / frozen character bug: added Anti-Sticking Watchdog with 30s dynamic flower blacklist (detects when a bone cannot be harvested after 0.8s at $\le 4.5$ studs and instantly retargets to the next flower without stopping) and continuous Lawn Mower sweep fallback whenever all flowers in the field are temporarily dead or blacklisted.
- **Beeconomy! v1.3.0** - Added Smart Pollen Hunter (Real-Time Flower Pollen Detection & Auto-Navigation) supporting all 23 fields. Queries `clientController.SkinnedGrass` and `BoneHarvestState` to read live flower status (alive vs harvested/respawning), automatically targets the nearest unharvested flower bones with remaining pollen in the selected field, and navigates the player to them with continuous scoops. Added instant field teleportation on dropdown change when auto-farm is running. Verified live across all 23 fields.
- **Beeconomy! v1.2.0** - Added Whole-Field Autonomous Movement covering 100% of the field surface with "Lawn Mower" (systematic S-curve / boustrophedon sweep), "Smooth Sweep" (ergodic Lissajous wave), "Glide Roam", and "Random Bounce", dynamically extracting exact 3D field boundaries from `Workspace.World1.World.Fields[Name].Base`. Added Field Coverage Margin slider (50%-95%). Fixed shovel breakage on honey conversion: added comprehensive post-convert recovery that automatically closes convert prompts, unblocks `HudVisibility`, restores camera, forces `ToolsManager:equipTool()`, sets `ShovelEquipped` and `GripHoldKind` attributes, and instantly resumes continuous auto-scooping without manual re-equipping or clicking.
- **Beeconomy! v1.1.0** - Added Auto Walk / Auto Orbit modes ("Circle Walk", "Glide Orbit", "Stay Center") with adjustable Roam Radius (8-35 studs) and Roam Speed sliders, allowing fully autonomous pollen farming without manual movement. Added Force Equip Shovel toggle to continuously ensure the shovel/scooper tool is held and active. Tested and verified live on client.
- **Beeconomy! v1.0.0** - Added dedicated game module for PlaceId 101558830312092 (GameId 7000989941). Features Auto Farm Pollen (digs flowers in selected field with 0.22s rhythmic scoops), 23-Field selector with exact 3D coordinates, Infinite Scoop Stamina (bypasses 3s cooldown by hooking canScoop and locking stamina to 100), Auto Collect Pollen Orbs (magnet vacuum with 1000-stud reach on active orbs in GC), Auto Honey Conversion (teleports to nearest converter when backpack is 95% full, triggers conversion, and returns to farming), Auto Fishing with instant perfect catch (hooks ReelMinigame.Start to finish minigame with max quality score), Auto Fish gamepass perk unlocker, 23 Field teleports, Pollen Converter teleports, Shop & Mastery Shrine teleports, Chest teleports, Custom WalkSpeed, Infinite Jump, Fullbright, and ESP for Fields, Chests, and Players. Registered in RAVENHUB.
- **Illegal Soccer v1.2.1** - Fixed Instant Max Charge Power: replaced naive constant modification (which caused soft kicks due to server validation/power curve clamping) with deep mathematical hooks on `KickCore.GetChargeAlpha` (forces 1.0 full alpha), `KickCore.GetMinimumReleaseDelaySeconds` (0s instant release delay), `KickCore.IsFullyCharged`/`IsFullPower` (true), `ActionCommands` (forces max charge seconds on Kick, TackleKick, Volley, Throw, and AssistedPass), and `ActionRemoteProtocol.Release` (spoofs 0.4s+ charge timestamp for authoritative server execution). Guaranteed 100% full maximum velocity (123+ speed) instantly even on a light tap.
- **Illegal Soccer v1.2.0** - Added No Ball Slowdown (eliminates ball carrier jog/run speed penalties for 100% full dribble speed), Full Speed Charge (eliminates charging walk speed penalty and post-charge recovery delay), Instant Max Charge Power (0.01s max kick and pass charge), and Auto Pass with 360° Magnetic Assisted Pass lock plus quick-pass keybind (Z). Registered in RAVENHUB.
- **Illegal Soccer v1.1.0** - Added Auto Goalkeeper (GK) system. Features dynamic goal side detection (Team 1 vs Team 2), auto angle-bisecting positioning along the goal line, real-time incoming shot trajectory prediction, automatic dive/save with facing alignment and repeat cooldown protection, automatic loose ball clear/punch, adjustable dive reach distance slider, and dedicated MacLib Goalkeeper tab.
- **Illegal Soccer v1.0.0** - Added dedicated module for PlaceId 126987974021910 (GameId 10155360168). Features Infinite Stamina (hooked Sprint drain/spend and unlimited flags with GC locking and respawn resilience), Always Sprint, Custom WalkSpeed, Infinite Jump, Ball ESP (⚽ Gold highlight + distance billboard), Goal ESP (🥅 Team 1 & 2 nets with distance), Player ESP (matched with live Jersey team colors + distance/health), Fullbright, FOV changer, and safe MacLib cleanup. Registered in RAVENHUB.
- **Shiganshina (AoT) v7.4** - Added support for new Shiganshina place (PlaceId 126678335159530, GameId 4658598196). Made Titans folder detection timeout-safe with 10s wait. Added dynamic UI fallback search for Blades frame instead of hardcoded path.
- **Shiganshina (AoT) v7.3** - Fixed Auto Retry button detection by removing parent-frame visibility check that blocked Retry button when Rewards frame was hidden. Added 7 click modes (Activate, MouseButton1Click, Activated, MouseButton1Down/Up, mouse1click, keyboard Enter, player mouse) with aggressive retry that cycles through all modes until one works.
- **Shiganshina (AoT) v7.2** - Rewrote blade detection to use live UI elements instead of Broken attribute. Durability bar (หลอด) now read from Bar/Gradient.Offset.X — reload (remote) when bar empty. Blade sets (ใบดาบ) read from Sets label — refill (station) when sets empty. Two-tier reload: remote for durability, station for blade sets.
- **Shiganshina (AoT) v7.1** - Fixed Auto Reload Blades to only trigger when all blades are broken instead of just partially reduced. Changed reload method from station teleport to simple remote reload. Fixed Auto Retry by removing parent Rewards frame visibility check that blocked Retry button detection.
- **Shiganshina (AoT) v7.0** - Fixed double reload race condition that caused blades to be reloaded twice in rapid succession.
- **Dungeon Quest Reborn v0.1.0** - Added Raven Hub registration, dungeon state tracking, bounded enemy scanning, Auto Farm/Attack, boss preference, room progression, runtime cleanup, and status UI. Lobby selection, difficulty, rewards, and retry remain adapter hooks until the live game contract is confirmed.
- **Train Your Fish to Race v1.2.0** - Added eligibility-gated Auto Online Rewards, Auto Daily Sign, Auto Spin/Free Spin, and event-driven Auto Race Reward with cooldown protection.

## 2026-08-30 - Attack on Titan Revolution Family Roll v1.0.1

- Fixed Auto Roll on Potassium by replacing unsupported `TextButton:Activate()` with `MouseButton1Click`/`Activated` signal fallbacks and a real UI mouse fallback.

## 2026-08-30 - Attack on Titan Revolution Family Roll v1.0.0

- Added a Rayfield-style Family Roll tab for the current Attack on Titan Revolution place.
- Added quick-select and free-text Family targets, adjustable roll interval, UI-only roll activation, and automatic stop when the Family title matches.
- Narrowed the existing Shiganshina registry match to its dedicated PlaceId so it does not load in the main customization place.
# Changelog

## 2026-09-03 - Iron Soul: Dungeon v1.6.1

- Expanded the `Dodge Hold` control from a 3-second maximum to a 10-second maximum.

## 2026-09-02 - Ground War (o) v0.1.0

- Added a Ground War module for PlaceId 76822114837453 with player/AIBot ESP, team-aware visibility checks, bounded ballistic prediction, optional smooth auto aim, tactical radar, match monitoring, fullbright, no fog, and custom FOV.
- Registered the module in RAVENHUB and kept its runtime behavior local-only without invoking game remotes.

## 2026-08-31 - Dungeon Lootr v2.0.1

- Fixed live UI resolution for `PlayerGui.Main.HUD` and `Main.Frames`, including skill, health, chest, and quest actions.
- Scoped enemy scanning to generated dungeon/NPC roots and added cooldowns to prevent overlapping automation loops.
- Filtered the hub library list to modules compatible with the current PlaceId/GameId.

## 2026-08-28 - The Wild West v0.1.12

- Added a short lock grace window so transient visibility scans do not drop a valid target.
- Candidate targets now receive a complete body-part visibility scan before acquisition; incremental scans remain for steady-state performance.
- Reduced visibility refresh latency and added an adjustable `Prediction Lead` multiplier shared by the aim point and prediction dot.

## 2026-08-25
- **Train Your Fish v1.1.2** - Made Smart Loop race-aware and synchronized native Auto Train/Auto Race toggles back to the game BoolValues after server-side rejection or changes.
- **Train Your Fish v1.1.1** - Fixed BoolValue resolution for Train/Auto states and reads Level, Evolution, and Mount from Character with Player fallback.

- **Train Your Fish to Race v1.1.0** - Fixed native state detection by resolving only ValueBase instances and caching AutoTrain/AutoRace/Train references, avoiding collisions with same-named UI/scripts and repeated deep scans.

- **Train Your Fish to Race v1.0.0** - Added native Auto Train/Auto Race controls, Smart Train + Race loop, live Race HUD, boost/progress tracking, native-state sync, and Anti AFK.

- **Sniper Arena v1.3** - Added adjustable 0-100 aim smoothness plus configurable Hold Key / Always lock activation with a user-selectable lock key.
- **Sniper Arena** - Verified `[No Bots FFA]` (PlaceId `119661268047775`) under GameId `9534705677` and added explicit registry support for the current sub-place.

## 2026-08-24 - Roll A Gnome v1.0.8

- Reduced per-plant readiness wait from 0.8 seconds to 0.12 seconds.
- Removed the fixed delay after every collect remote and retained one short batch-settle wait.

## 2026-08-24 - Roll A Gnome v1.0.7

- Fixed the ready queue repeatedly selecting a plant through its stale `FruitReady` attribute.
- Ready collection now requires an eligible ready fruit model and reports growing fruit separately.

## 2026-08-24 - Roll A Gnome v1.0.6

- Added per-`FruitId` retry cooldown so a ready fruit rejected or delayed by the server is not targeted every collection tick.
- Added an adjustable Same Fruit Retry interval, defaulting to 15 seconds.

## 2026-08-24 - Roll A Gnome v1.0.5

- The farm status now separates spawned fruit models from server-ready fruit so visible growing fruit is no longer mistaken for collectable fruit.

## 2026-08-24 - Roll A Gnome v1.0.4

- Ready now reports individual fruit models whose `READY` attribute is true instead of counting mature plants.
- Collected now uses the replicated inventory delta and no longer counts rejected collection requests.
- Plants are queued only when they contain ready fruit, avoiding repeated requests for mature but uncollectable plants.

## 2026-08-24 - Roll A Gnome v1.0.3

- Fixed newly replicated plants being skipped when `OwnerUserId` is temporarily absent; ownership remains bounded by the player's plot.

## 2026-08-24 - Roll A Gnome v1.0.2

- Fixed collection proximity by raycasting to the owned garden floor instead of positioning above the plant model.
- Waits briefly for the game's `CanCollect` state before requesting collection, then restores the original position.

## 2026-08-24 - Roll A Gnome v1.0.1

- Fixed ready detection to match the game's `READY` or `FruitReady` collection contract.
- Auto Collect now enters collection range briefly for each plant and restores the original position after the batch.

## 2026-08-24 - Roll A Gnome v1.0.0

- Added owner-plot-only collection for plants whose fruit is ready.
- Added throttled Auto Collect and Auto Sell controls with manual actions and bounded batch size.
- Added cleanup-safe runtime state and status counters.

## 2026-08-24 - Cold War v1.8.0

- Removed Frag Auto Aim, Frag Auto Equip, trajectory solving, related runtime state, and menu controls.
- Removed the Frag render-step and Auto Aim interception so gun Auto Aim and Aim Prediction remain independent.

## 2026-08-24 - Cold War v1.7.4

- Fixed gun Aim Prediction applying a second screen-space smoothing pass after Auto Aim had already smoothed the camera.
- The prediction marker now uses the ballistic point projected through the latest camera state, keeping it synchronized with the configured aim smoothness.

## 2026-08-24 - Cold War v1.7.3

- Added Frag Auto Equip so enabling Frag Auto Aim can equip an available grenade from the backpack automatically.
- Auto equip is throttled and only runs while Frag Auto Aim is enabled.

## 2026-08-24 - Cold War v1.7.2

- Added Best Effort Frag locking so Auto Aim still locks the closest trajectory when every target is outside grenade range.
- Added Frag Reachable Only for users who want the lock restricted to solutions inside Frag Max Miss.
- Exposed FragAimReachable state so the menu/runtime can distinguish a true hit solution from best effort.

## 2026-08-24 - Cold War v1.7.1

- Frag Auto Aim now rejects unreachable solutions instead of pulling the camera toward targets far outside the grenade trajectory.
- Added an adjustable Frag Max Miss threshold, defaulting to 12 studs.
- Reduced trajectory solve frequency and search density to lower raycast cost while retaining bounce calculation.

## 2026-08-24 - Cold War v1.7.0

- Added Frag Auto Aim for equipped grenade tools with adjustable throw speed, bounce, fuse, and smoothing.
- Added a map-aware trajectory solver that applies gravity and raycast collision reflection for grenade bounces.
- Frag aiming uses normal player input and does not fire the grenade remote automatically.

## 2026-08-24 - Cold War v1.6.1

- Fixed Auto Visible choosing Head/Torso by priority even when the crosshair is on an exposed arm or leg.
- Part visibility rays now count only when they reach the sampled body part, preventing another body part from producing a false visible result.
- Reused the existing visibility cache and ray budget; the fix does not add per-frame raycasts.

## 2026-08-24 - Cold War v1.6.0

- Added configurable Auto Lock Part modes: Auto Visible, Closest Visible, and Selected Only.
- Auto Aim and its prediction display now share the same cached shootable body part and switch away from covered parts without extra raycasts.

## 2026-08-24 - Cold War v1.5.0

- Reworked visibility into independent Head/Torso/arm/leg states with center and four edge samples per part.
- Kept raycast cost bounded to one sample per enemy per frame and replaced whole-character coloring with per-part adornments for partial cover.

## 2026-08-24 - Cold War v1.4.0

- Added Adaptive Smoothness: large crosshair errors acquire faster while small errors retain the configured precision response.
- Prediction display and Auto Aim share the same adaptive response calculation so their motion remains synchronized.

## 2026-08-24 - Cold War v1.3.1

- Synchronized the prediction dot/circle/text motion with the same frame-rate-independent response used by Auto Aim smoothness.
- The display starts at the crosshair when aim engages and resets cleanly on target changes, release, or disable.

## 2026-08-24 - Cold War v1.3.0

- Replaced the approximate drag loop with Cold War's native `Trajectory:GetTimeForDistance()` calculation using the weapon's real `Drag` value.
- Matched the game's `ZeroSolver` conversion of `3.57 studs/m` and added iterative moving-target lead convergence.
- Hardened Right Mouse activation so unknown dropdown values fail safe to Right Mouse and both event and physical input state must agree.

## 2026-08-24 - Cold War v1.2.2

- Fixed Right Mouse activation continuing from stale `InputBegan` state after the button was released.
- Right Mouse mode now reads the physical mouse-button state on every aim frame.
- Normalized MacLib dropdown return shapes and moved activation to a new config flag so an old saved `Always` value cannot override the UI.

## 2026-08-24 - Cold War v1.2.1

- Fixed Auto Aim remaining inactive when Cold War consumes right-mouse input before the module receives `InputBegan`.
- Added persistent UI flags for Auto Aim and activation mode.
- Changed aim visibility validation from head-only to multi-part checks across head, torso and root.

## 2026-08-24 - Cold War v1.2.0

- Moved Auto Aim after the game's camera render step so weapon sway and camera recoil are included in each correction.
- Added configurable recoil/sway compensation using frame-rate-independent camera convergence.
- Corrected ballistic drop for the weapon's configured sight zero and smoothed target velocity using replicated assembly velocity.

## 2026-08-23 - TTK Testing v1.0.0

- Added FFA player ESP with live health and distance, plus configurable range.
- Added per-body-part chams and multi-point raycast Visible Check with green visible/red obstructed states.
- Added match, score, weapon, timer, current-map and map-voting dashboards.
- Added Fullbright, screen-smudge removal, FOV override and Anti AFK without combat-remote automation.

## 2026-08-23 - Fish an Anime RNG v1.0.0

- Added native-controller Auto Fish, backpack capacity automation, Equip Best and guarded Sell All.
- Added state-aware Daily/Playtime claiming, Quest/Index Claim All, Pick Up All, and cash Rebirth controls.
- Added the game's Performance Mode, pond/catch ESP, status dashboard, Anti AFK, and travel shortcuts.
- Registered PlaceId `74729868188364` and GameId `9582986239` in RAVENHUB.

## 2026-08-23 - Load The Truck v1.0.3

- Fixed `WakeWorker`, `AssignWorkerZone`, conveyor/floor/parking unlock, scanner upgrade/unlock, and box-tier remote arguments to match the live game controllers.
- Reduced remote spam by assigning each worker once per module session and rotating through one general upgrade per interval.
- Added all upgrade keys currently exposed by the game UI and state-aware selection for the next conveyor, floor, scanner, and box tier.

## 2026-08-23

- **Load The Truck v1.0.2** — Fixed Auto Wake by sending the owned worker Model instance to `WakeWorker`, matching the game's `WorkerHoverController`, instead of sending the worker-name string rejected by the server.
- **Load The Truck v1.0.1** — Fixed shared-timer starvation across collect/deposit, workers, upgrades, and scanners; implemented Auto Assign and Auto Unlock Scanner; corrected upgrade remote arguments; rate-limited rebirth/leave rewards; restricted status and collection to owned objects; fixed ESP range cleanup/distance updates; and added Conveyor ESP.
- **Cold War v1.1.5** — Restored visibility evaluation for every enemy each frame while rotating one body sample per enemy per frame; full character coverage is retained without burst raycasts, and hidden state is committed only after a complete missed cycle.
- **Cold War v1.1.4** — Capped multi-part visibility work at three characters per frame, increased cache lifetime, and reduced each character to bounded centre/side samples to remove the v1.1.3 frame spikes.
- **Cold War v1.1.3** — Added cached multi-part and inset-corner visibility sampling, so ESP/radar detect enemies whose head, limbs, or body edge is exposed while the HumanoidRootPart remains behind cover.
- **RAVEN HUB maclib-4** — Removed automatic `queue_on_teleport` persistence; script startup is now left to the executor's Auto Execute configuration.
- **RAVEN HUB maclib-3** — Added JobId-scoped queue_on_teleport persistence so the hub reloads and re-arms itself after dungeon/lobby server transitions without duplicate queues in the same session.
- **Iron Soul: Dungeon v1.2.11** — Added a guarded Door-to-Portal chain recovery: after an open door, an empty between-round player within 35 studs of a real portal is teleported into it and touched automatically.
- **Iron Soul: Dungeon v1.2.10** — Added open-door entry recovery: an empty player standing beside a disabled/open door is moved to the active GameRound respawn so the next room's wave trigger can start.
- **Iron Soul: Dungeon v1.2.9** — Door automation now crosses 18 studs beyond the doorway toward the next area after opening, and completed-route handling prevents repeated or backward actions while the next room loads.
- **Iron Soul: Dungeon v1.2.8** — Corrected round-transition semantics: GameRoundComplete now identifies the room whose exit must be used, completion increments create a pending move state, and reload recovery uses the nearest PlayerRespawn plus an empty room.
- **Iron Soul: Dungeon v1.2.7** — Fixed BaseAttack remaining active after targets disappear by pulsing and stopping the controller action, and added a current-room nearest real-portal fallback for randomized layouts with stale RoundNum metadata.
- **Iron Soul: Dungeon v1.2.6** — Added a configurable post-clear confirmation delay and made teleport-mode Door/Portal interactions fire after a short replication pause in the same scheduled action.
- **Iron Soul: Dungeon v1.2.5** — Replaced transient EnemyNpc-count progression with the game's authoritative GameRoundCfg state; Door/Portal automation now waits until GameRoundComplete reaches the active GameRound.
- **Iron Soul: Dungeon v1.2.4** — Added round-scoped Door/Portal state: matching doors always take priority, handled doors block portals until the player's current round actually changes, and portals run only for rounds without a matching door.

## 2026-08-22

- **Iron Soul: Dungeon v1.2.3** — Fixed incorrect progress destinations by selecting enabled doors relative to the current round spawn and using only RoundDoor portals whose RoundNum matches the player's current round.
- **Iron Soul: Dungeon v1.2.2** — Made teleport the default Door/Portal progress movement, added safe interaction offsets, and retained Walk as an optional movement mode.
- **Iron Soul: Dungeon v1.2.1** — Fixed progress automation by navigating to distant doors/portals before interaction, preventing repeated door use, exposing live wait/movement state, and corrected the local Auto Skills test-state mismatch.
- **Iron Soul: Dungeon v1.2** — Added enemy-clear-aware automatic round-door prompts and next-portal touch handling, progress cooldown controls, and corrected Portal ESP round metadata.
- **Iron Soul: Dungeon v1.1** — Added target-based autofarm, multi-weapon base attack input, ready-only auto skills, approach/above-target positioning, and adjustable combat distance/height/delay.
- Added Iron Soul: Dungeon v1.0 with bounded Enemy ESP, nearest/lowest-HP target selection, live target HP, RedShow-based Auto Dodge, spectating, and round/portal diagnostics.
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
# Iron Soul v1.3.0

- v1.3.6 changes the default vertical dodge to `Air` at `50 studs`.
- v1.3.5 reacts immediately to `RedShow.DescendantAdded`, preventing short-lived telegraphs from being missed between scans.
- v1.3.4 adds vertical Auto Dodge modes (`Underground`/`Air`) and a `Below Target` Autofarm position.
- v1.3.3 adds a configurable Dodge Hold window that keeps Autofarm from immediately walking back into an active attack.
- v1.3.2 fixes Auto Dodge for transparent `RedShow` hitboxes and exits rectangular danger zones through their nearest edge.
- v1.3.1 fixes Replay/Return Lobby activation by targeting the exact ResultGui buttons and dispatching the game's full click sequence.
- Added configurable post-dungeon automation: `Replay`, `Return Lobby`, or `Off`.
- Result actions only target visible dungeon-result GUI buttons and ignore the regular top-bar Exit button.
- Added an adjustable result-screen delay and live end-action status to the Dungeon dashboard.
