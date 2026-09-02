$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\modules\iron_soul.lua'
$source = Get-Content -Raw -LiteralPath $path

$required = @(
    'LocalControlMgr',
    'ActionFolder',
    'Controller.new',
    'PerformAction("BaseAttack")',
    'GamePlayerRE',
    'VotePlayAgain',
    'PlayerRevive',
    'PlayerRespawn',
    'workspace.EnemyNpc',
    'HitCount',
    'DragonEgg',
    'EggModel',
    'SetWalkSpeed',
    'TweenService:Create',
    'CameraDistance',
    'distanceX',
    'distanceY',
    'distanceZ',
    'pitch',
    'autoPlayAgain',
    'changeWalkSpeed'
)

foreach ($needle in $required) {
    if ($source -notmatch [regex]::Escape($needle)) {
        throw "Source adoption contract is missing: $needle"
    }
}

$removed = @(
    'autoOpenDoor',
    'autoNextPortal',
    'progressPortals',
    'RoundDoor',
    'Portal ESP',
    'Auto Open Round Door',
    'Auto Next Round Portal',
    'portalRoot',
    'portalRound'
)
foreach ($needle in $removed) {
    if ($source -match [regex]::Escape($needle)) {
        throw "Door/portal system must be removed: $needle"
    }
}

if ($source -match 'for _,v in pairs\(workspace\.PlayerRespawn:GetChildren\(\)\)') {
    throw 'Autofarm must not sweep every respawn as a progression fallback'
}

Write-Output 'PASS: Iron Soul adopts Potassium autofarm contracts and removes door/portal progression'
