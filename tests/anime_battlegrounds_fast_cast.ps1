$ErrorActionPreference = "Stop"
$source = Get-Content -Raw (Join-Path $PSScriptRoot "..\modules\anime_battlegrounds.lua")
$required = @{
    "catalogue from registry" = 'pcall\(registry\.GetMoveset, movesetFolder\.Name\)'
    "all registered skill phases" = 'abilityFolder:GetDescendants\(\)'
    "animation instances only" = 'animation:IsA\("Animation"\)'
    "catalogue scoped to ability" = 'key = ability\.Key'
    "catalogue scoped to active moveset" = 'entry\.moveset == localPlayer:GetAttribute\("Moveset"\)'
    "include arbitrary skill phases" = 'phase = animation\.Name'
    "victim tracks excluded" = 'animation\.Name:lower\(\):find\("victim", 1, true\)'
    "registered specials counted" = 'fastCast\.RegisteredAbilities \+= 1'
    "covered specials counted" = 'fastCast\.CoveredAbilities \+= 1'
    "missing ability list" = 'table\.insert\(fastCast\.Missing'
    "ignore basic attacks" = 'config\.Kind ~= "Attack"'
    "ignore melee" = 'config\.Kind ~= "Melee"'
    "Road Roller observable" = 'roadRollerAccelerated = fastCast\.RoadRollerAccelerated'
    "server timing unchanged" = 'serverTimedRoadRollerUnchanged = true'
    "regular animation played event" = 'animator\.AnimationPlayed:Connect'
    "deferred speed update" = 'task\.defer\(function\(\)'
    "bounded multiplier" = 'math\.min\(3, math\.max\(original, 1\) \* fastCast\.Multiplier\)'
    "restores live tracks" = 'track:AdjustSpeed\(original\)'
    "character respawn" = 'localPlayer\.CharacterAdded:Connect'
    "disconnects on shutdown" = 'stopFastCast\(\)'
    "user toggle" = 'Flag = "AB_FastCast"'
    "user speed slider" = 'Flag = "AB_FastCastSpeed"'
    "status observability" = 'GetFastCastStatus = function'
    "coverage API" = 'GetFastCastCoverage = function'
    "last skill and phase" = 'fastCast\.LastAbility, fastCast\.LastPhase = trackKind\.key, trackKind\.phase'
    "active tracks restored on character change" = 'restoreActiveCastTracks\(\)\s+fastCast\.Bound = false'
}
foreach ($item in $required.GetEnumerator()) {
    if ($source -notmatch $item.Value) { throw "Missing: $($item.Key)" }
}
if ($source -match 'localPlayer\.Character\.HumanoidRootPart\.CFrame\s*=' -or
    $source -match 'cfg\.Cooldown\s*=\s*0' -or
    $source -match 'cfg\.Damage\s*=\s*9999') {
    throw "Fast Cast must not include camera/root steering or fake cooldown/damage"
}
Write-Output "PASS: all-skill Fast Cast source contracts; caster-only scope and unchanged server timing"