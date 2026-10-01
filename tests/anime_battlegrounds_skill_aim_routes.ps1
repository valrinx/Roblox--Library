$ErrorActionPreference = "Stop"
$source = Get-Content -Raw (Join-Path $PSScriptRoot "..\modules\anime_battlegrounds.lua")
$checks = @{
    "registry discovery" = 'pcall\(registry\.GetMovesetNames\)'
    "registry special ability filter" = 'config\.Kind ~= "Attack" and config\.Kind ~= "Melee"'
    "registered ability catalog" = 'skillAim\.AbilityCatalog\[ability\.Id\] = ability'
    "packet owner mapping" = 'skillAim\.PacketOwners\[packetName\] = ability\.Id'
    "longest prefix" = 'table\.sort\(abilities, function\(a, b\) return #a\.Key > #b\.Key end\)'
    "active moveset guard" = 'ability\.Moveset == currentMoveset'
    "original payload preserved" = 'local copy, route = table\.clone\(payload\), nil'
    "Look redirect" = 'copy\.Look = math\.abs\(payload\.Look\.Y\)'
    "Direction redirect" = 'copy\.Direction = delta\.Unit \* payload\.Direction\.Magnitude'
    "AimDirection redirect" = 'copy\.AimDirection = delta\.Unit \* payload\.AimDirection\.Magnitude'
    "target point redirect" = 'copy\.TargetPosition, route = point'
    "Road Roller ground plane" = 'Vector3\.new\(point\.X, payload\.Position\.Y, point\.Z\)'
    "Whip Smash exact point" = 'WhipSmashAim = "point"'
    "bounded reacquisition" = 'os\.clock\(\) - skillAim\.LastAcquire >= skillAim\.ReacquireInterval'
    "no stale M1 target" = 'skillAim\.Target, skillAim\.ActiveAbilityId = nil, nil'
    "coverage observability" = 'GetSkillAimCoverage = function'
    "verification limitation" = 'allServerHitsVerified = false'
}
foreach ($check in $checks.GetEnumerator()) {
    if ($source -notmatch $check.Value) { throw "Missing Skill Aim route: $($check.Key)" }
}
$start = $source.IndexOf('local function redirectSkillPayload(name, payload)')
$end = $source.IndexOf('local function installSkillAim()', $start)
if ($start -lt 0 -or $end -le $start) { throw "Aim payload adapter not found" }
$adapter = $source.Substring($start, $end - $start)
foreach ($field in @('Origin', 'Victims', 'ClientTime', 'Cooldown', 'Damage')) {
    if ($adapter -match ("copy\." + $field + '\s*=')) {
        throw "Protected payload field written: $field"
    }
}
if ($source -notmatch 'aimOutgoingPacket\(name\)' -or
    $source -notmatch 'isAbilityPacket or skillAim\.PacketOwners\[name\] ~= nil') {
    throw "Unscoped packet interception"
}
$abilityNames = @(
    "Burst","Tensho","StandBarrage","RoadRoller","Clones","Rasengan","DetroitSmash","WhipSmash",
    "DragonTornado","FireBarrage","PhaseSlam","Unleash","Igris","TelekineticSlam","Rush","Kamehameha",
    "Spin","Slam","FireBreath","Susanoo","WaterWheel","FireHead","NeckSpinner","LightningSlam",
    "DivergentFist","CursedCombo","PhasePunch","Unearth","Cleave","FireArrow","Tornado","Onigiri",
    "Barrage","Bazooka","BluePull","HollowPurple","Zoltraak","Tsunami","DivinePunch","DivineBeam"
)
if ($abilityNames.Count -ne 40 -or ($abilityNames | Sort-Object -Unique).Count -ne 40) {
    throw "Expected 40 unique archived special abilities"
}
$ordered = @($abilityNames | Sort-Object { -$_.Length })
foreach ($pair in @(
    @("RoadRollerAim","RoadRoller"),@("WhipSmashAim","WhipSmash"),
    @("TornadoDash","Tornado"),@("HollowPurpleShoot","HollowPurple"),
    @("FireBarrageShot","FireBarrage"),@("OnigiriFire","Onigiri"),
    @("ZoltraakFire","Zoltraak"),@("TsunamiCast","Tsunami")
)) {
    $owner = @($ordered | Where-Object { $pair[0].StartsWith($_) } | Select-Object -First 1)
    if ($owner.Count -ne 1 -or $owner[0] -ne $pair[1]) {
        throw "Wrong sample packet ownership: $($pair[0])"
    }
}
Write-Output "PASS: 17 Skill Aim route contracts, 40-key archive fixture and guarded packet adapters"
