# Changelog

## Unreleased

- Added the TWDO3 awareness suite: 2D radar, wall raycasts, threat colors, box/tracer/skeleton overlays, rarity/search loot filters, adaptive presets, proximity alerts, death markers, live player monitoring, persisted controls, panic clear, and FPS/ping/MCP diagnostics.
- Made player/walker HP text and bars react directly to Humanoid health changes, and immediately remove ESP when the Humanoid dies or its model is removed.
- Rebuilt ESP labels with separate name/detail rows, a compact 260px canvas, a 120px health bar, and live text-size/health-bar-width controls.
- Fixed ESP labels wrapping health values on long player names by using a wider fixed two-line layout, compact HP formatting, and a shorter health bar.
- Expanded TWDO3 ESP into an optimized multi-category system for players, walkers, and indexed loot containers, with distance/quantity caps, category filters, health bars, through-wall controls, live counts, and throttled cleanup-safe updates.
- Changed the TWDO3 module URL to the executor-safe `modules/twdo3.lua` path, retained a compatibility bridge for cached registries, and added visible hub build/module-load diagnostics so fetch, compile, and runtime failures no longer fail silently.
- Added a The Walking Dead Online 3 module with player ESP, configurable labels and distance, a live player picker, spectate controls, respawn handling, and cleanup on hub destruction.
