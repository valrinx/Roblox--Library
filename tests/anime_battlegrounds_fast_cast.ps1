$ErrorActionPreference = "Stop"
$source = Get-Content -Raw (Join-Path $PSScriptRoot "..\modules\anime_battlegrounds.lua")
$required = @{
    "ability-scoped animation" = 'movesetFolder\.Parent ~= animRoot'
    "only Start marker" = 'animation\.Name ~= "Start"'
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
Write-Output "PASS: 12 Fast Cast source contracts; safe restoration and no fake cooldown/damage"