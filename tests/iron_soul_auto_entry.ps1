$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')

$required = @(
    'autoEnterDungeon = false',
    'autoDungeonWorld',
    'autoDungeonDifficulty',
    'local function findFreeMatchRoom',
    'local function touchMatchRoom',
    'local function requestDungeonEntry',
    'workspace:FindFirstChild\("MatchRoom"\)',
    'GetAttribute\("PlayersCount"\)',
    'GetAttribute\("RoomState"\)',
    'GameMatchRE',
    'CreatRoom',
    'SelectWorld',
    'runAutoDungeonWorker\(\)',
    'Name="Auto Enter Dungeon"'
)

foreach ($pattern in $required) {
    if ($source -notmatch $pattern) {
        throw "Iron Soul auto-entry contract is missing: $pattern"
    }
}

if ($source -notmatch 'if game\.PlaceId==117533937949084 and settings\.autoEnterDungeon then[\s\S]{0,1200}requestDungeonEntry') {
    throw 'Auto dungeon entry must be guarded to the lobby place and must not run inside a dungeon'
}

if ($source -notmatch 'RoomState.*Empty|Empty.*RoomState') {
    throw 'Auto dungeon entry must require an empty match room'
}

Write-Output 'PASS: Iron Soul auto dungeon entry contract is covered'
