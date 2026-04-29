# Project Status

Status: CLOSED (Maintenance Mode)

Date: 2026-04-29

## Scope Closed
- RAVENHUB now loads UMT through modular entrypoint: `modules/umt/main.lua`
- UMT settings schema and migration layer are in place (`settingsVersion`)
- ESP system has modular helpers (`esp.lua`, `esp_runtime.lua`)
- Auto Mine has modular helpers (`auto_mine.lua`) for resolver/runtime utility pieces
- Documentation updated with smoke test checklist and known issues

## Operational Policy
- No new feature expansion in this phase
- Only allow maintenance changes:
  - Critical runtime fixes
  - Game update compatibility fixes
  - Safety/performance regressions

## Release Readiness Checklist
- [x] Entry loader path updated in `RAVENHUB`
- [x] Backward-compatible fallback paths preserved in UMT module
- [x] Lint check passes on touched files
- [x] Changelog updated in `README.md`

## Completion Definition
- No pending deferred items for this closure.
- Remaining changes are maintenance-only requests after closure.

