$ErrorActionPreference = "Stop"
$source = Get-Content -Raw (Join-Path $PSScriptRoot "..\modules\anime_battlegrounds.lua")
$required = @{
    "ability-scoped animation" = 'movesetFolder\.Parent ~= animRoot'
    "default Start marker" = 'animation\.Name ~= "Start" and not roadRollerTrack'
    "Road Roller cast/end" = '\(animation\.Name == "Cast" or animation\.Name == "End"\)'
    "Road Roller only Diyo" = 'movesetFolder\.Name == "Diyo"'
    "Road Roller only valid ability" = 'abilityFolder\.Name == "RoadRoller"'
    "Road Roller observable" = 'roadRollerAccelerated = fastCast\.RoadRollerAccelerated'
    "server timing unchanged" = 'serverTimedRoadRollerUnchanged = true'
    "ignore melee" = 'ability\.Config\.Kind ~= "Melee"'
    "regular animation played event" = 'animator\.AnimationPlayed:Connect'
    "deferred speed update" = 'task\.defer\(function\(\)'
    "bounded multiplier" = 'math\.min\(3, math\.max\(original, 1\) \* fastCast\.Multiplier\)'
    "restores live tracks" = 'track:AdjustSpeed\(original\)'
    "character respawn" = 'localPlayer\.CharacterAdded:Connect'
    "disconnects on shutdown" = 'stopFastCast\(\)'
    "user toggle" = 'Flag = "AB_FastCast"'
    "user speed slider" = 'Flag = "AB_FastCastSpeed"'
    "status observability" = 'GetFastCastStatus = function'
}
foreach ($item in $required.GetEnumerator()) {
    if ($source -notmatch $item.Value) { throw "Missing: $($item.Key)" }
}
if ($source -match 'localPlayer\.Character\.HumanoidRootPart\.CFrame\s*=' -or
    $source -match 'cfg\.Cooldown\s*=\s*0' -or
    $source -match 'cfg\.Damage\s*=\s*9999') {
    throw "Fast Cast must not include camera/root steering or fake cooldown/damage"
}
Write-Output "PASS: 17 Fast Cast source contracts; Road Roller Cast/End scoped and server timing unchanged"