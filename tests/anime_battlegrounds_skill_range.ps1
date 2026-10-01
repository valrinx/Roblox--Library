$ErrorActionPreference = "Stop"
$root = Join-Path $PSScriptRoot ".."
$source = Get-Content -Raw (Join-Path $root "modules\anime_battlegrounds.lua")
$audit = Get-Content -Raw (Join-Path $root "artifacts\anime_ability_range_audit.md")
$checks = @{
    "runtime registry lookup" = 'registry\.GetAbilityById'
    "ability cast selects profile" = 'name == "AbilityCast" or fresh'
    "charged cast respects same ID" = 'abilityId ~= skillAim\.ActiveAbilityId'
    "named cast registry owner" = 'payload\.AbilityId or skillAim\.PacketOwners\[name\]'
    "range check uses current target distance" = '\(point - ownRoot\.Position\)\.Magnitude > range'
    "unknown ranges are not hard-capped" = 'classification = "unknown", max = nil'
    "movement and hitbox are hints" = 'classification = "hint-only"'
    "declared range margin" = 'info\.max \* skillAim\.RangeMargin'
    "original packet fallback" = 'return original\(payload, \.\.\.\)'
    "range-aware control" = 'Flag = "AB_SkillAimRangeAware"'
    "public per-ability profile" = 'GetSkillRangeProfile = function\(abilityId\)'
}
foreach ($item in $checks.GetEnumerator()) {
    if ($source -notmatch $item.Value) { throw "Missing: $($item.Key)" }
}
if ($source -match 'cfg\.Cooldown\s*=\s*0' -or $source -match 'cfg\.Damage\s*=\s*9999') {
    throw "Unsafe client-only cooldown/damage proof-of-concept leaked into production"
}
$lines = ($audit -split '[\r\n]+' | Where-Object { $_ -match '^\| [A-Za-z].*\| \d+(?:\.\d+)? \|' })
if ($lines.Count -ne 44) { throw "Expected 44 config records, found $($lines.Count)" }
Write-Output "PASS: range-aware selection contracts and 44-config audit; no fake CD/one-shot mode"