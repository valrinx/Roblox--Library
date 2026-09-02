$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')

$requiredPatterns = @(
    'local function runPotassiumAutofarm\(\)',
    'local function runPotassiumCombat\(\)',
    'local function collectChests\(\)',
    'local function collectDragonEggs\(\)',
    'LocalControlMgr',
    'Controller\.new',
    'GamePlayerRE',
    'GameRoundRE',
    'VotePlayAgain',
    'workspace\.EnemyNpc',
    'PlayerRespawn',
    'HitCount',
    'DragonEgg',
    'EggModel',
    'SetWalkSpeed',
    'Version="v1\.6\.0"'
)

foreach ($pattern in $requiredPatterns) {
    if ($source -notmatch $pattern) {
        throw "Iron Soul autofarm contract missing: $pattern"
    }
}

foreach ($removed in @('autoOpenDoor','autoNextPortal','progressPortals','RoundDoor','Portal ESP','Auto Open Round Door','Auto Next Round Portal','portalRoot','portalRound')) {
    if ($source -match [regex]::Escape($removed)) {
        throw "Door/portal progression must remain removed: $removed"
    }
}

Write-Output 'PASS: Iron Soul source autofarm is covered and door/portal progression remains removed'
