$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')

if ($source -match 'Name="Auto Skills \(Ready Only\)"' -or $source -match 'Flag="IronSoulAutoSkills"') {
    throw 'The Ready Only skills toggle must be removed from Iron Soul'
}

foreach ($pattern in @(
    'local CHEST_HIT_LIMIT\s*=\s*3',
    'local function chestHitCount\(',
    'local function hitChest\(',
    'chestHits\s*<\s*CHEST_HIT_LIMIT',
    'root\.CFrame\s*=\s*chestRoot\.CFrame',
    'hitChest\(v\s*,\s*chestRoot\)',
    'Attack\(false\)'
)) {
    if ($source -notmatch $pattern) {
        throw "Chest 3-hit flow contract missing: $pattern"
    }
}

$collector = [regex]::Match($source, '(?s)local function collectChests\(\).*?(?=local function collectDragonEggs\(\))').Value
if ($collector -notmatch 'CHEST_HIT_LIMIT' -or $collector -notmatch 'hitChest') {
    throw 'Chest collection does not invoke the bounded hit flow'
}

Write-Output 'PASS: Ready Only toggle removed and chest collection uses teleport + bounded three-hit flow'
