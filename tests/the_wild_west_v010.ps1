$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\the_wild_west.lua')
$hub = Get-Content -Raw (Join-Path $PSScriptRoot '..\RAVENHUB')

if ($source -notmatch 'WORKSPACE_Entities' -or $source -notmatch 'FindFirstChild\("Players"\)') {
    throw 'The Wild West target resolver must use WORKSPACE_Entities/Players'
}

if ($source -notmatch 'local AUTO_VISIBLE_PARTS_PER_SCAN = 4' -or
    $source -notmatch 'local AUTO_VISIBLE_SCAN_INTERVAL = 2' -or
    $source -match 'AUTO_VISIBLE_GRID_STEPS') {
    throw 'Auto Lock must keep the bounded visibility budget from the Cold War FPS fix'
}

if ($source -notmatch 'AIM_PREFILTER_MARGIN' -or
    $source -notmatch 'distance > State\.AimFOV \+ AIM_PREFILTER_MARGIN then continue') {
    throw 'Auto Lock must reject off-FOV players before visibility work'
}

if ($source -notmatch 'local function getTeamName\(player\)' -or
    $source -notmatch 'if State\.IgnoreSameTeam and isSameTeam\(player\) then return false end') {
    throw 'Ignore Same Team must compare the live team identity before target selection'
}

if ($source -notmatch 'type\(mousemoverel\) == "function"' -or
    $source -notmatch 'pcall\(mousemoverel, delta\.X \* alpha, delta\.Y \* alpha\)') {
    throw 'Auto Lock must drive the Wild West custom camera through mouse delta when available'
}

if ($source -notmatch 'local ESP_UPDATE_INTERVAL = 0\.25' -or
    $source -notmatch 'if espAccumulator >= ESP_UPDATE_INTERVAL then') {
    throw 'ESP must use the throttled update cadence'
}

foreach ($required in @('Player ESP','Animal ESP','Loot Chest ESP','Ore ESP','Fullbright','No Fog','Custom FOV')) {
    if ($source -notmatch [regex]::Escape($required)) {
        throw "Missing v0.1.1 control: $required"
    }
}

if ($source -notmatch 'CollectionService:GetTagged\("LootChest"\)' -or
    $source -notmatch 'GetAttribute\("State"\)' -or
    $source -notmatch 'FindFirstChild\("OreDeposits"\)') {
    throw 'ESP must use verified live LootChest state and OreDeposits sources'
}

if ($source -notmatch 'UnbindFromRenderStep\(renderStepName\)' -or
    $source -notmatch '__RAVEN_THE_WILD_WEST = \{Version="v0\.1\.1"') {
    throw 'Module cleanup/runtime registration is incomplete'
}

if ($hub -notmatch 'name\s*=\s*"The Wild West"' -or
    $hub -notmatch 'placeIds\s*=\s*\{2317712696\}' -or
    $hub -notmatch 'gameIds\s*=\s*\{807930589\}' -or
    $hub -notmatch 'modules/the_wild_west\.lua') {
    throw 'RAVENHUB registration is missing or incorrect'
}

Write-Output 'PASS: The Wild West v0.1.1 Auto Lock/team/ESP regression checks passed'
