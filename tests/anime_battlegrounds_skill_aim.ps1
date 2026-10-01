$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "..\modules\anime_battlegrounds.lua"
$source = Get-Content -Raw $modulePath

$checks = @{
    "skill aim target selector" = 'local function chooseSkillTarget\(\)'
    "players and dummy targets" = 'CollectionService:GetTagged\("Dummy"\)'
    "FOV target selection" = 'pixels >= skillAim\.Fov'
    "cast acquisition" = 'name == "AbilityCast"'
    "charged ability handling" = 'name == "AbilityCharge"'
    "direction payload only" = 'copy\.Look = math\.abs\(payload\.Look\.Y\)'
    "no payload mutation" = 'table\.clone\(payload\)'
    "original passthrough" = 'return original\(payload, \.\.\.\)'
    "aim module restoration" = 'skillAim\.Aim\.Point = skillAim\.Original\.Point'
    "packet restoration" = 'packet\.send = skillAim\.Original\[name\]'
    "classical FOV GUI" = 'RAVEN_SkillAim_V4'
    "throttled target scan" = 'ScanInterval = 0\.2'
    "one frame-tracked HUD" = 'updateSkillAimHUD\(\)'
    "module cleanup" = 'restoreSkillAim\(\)'
    "module status" = 'GetSkillAimStatus = function'
}
foreach ($check in $checks.GetEnumerator()) {
    if ($source -notmatch $check.Value) { throw "Missing: $($check.Key)" }
}
if ($source -match 'camera\.CFrame = currentCF:Lerp') {
    throw "Legacy camera aimlock is still present"
}
if ($source -match 'isAiming\s*=') { throw "Legacy aim key state is still present" }
Write-Output "PASS: Anime Battlegrounds Skill Aim V4 source contracts (15 checks), no camera aimlock"