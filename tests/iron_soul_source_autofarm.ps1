$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')

$worker = [regex]::Match($source, '(?s)local function runPotassiumAutofarm\(\).*?(?=local function runPotassiumCombat\(\))').Value
if (-not $worker) { throw 'Source autofarm worker is missing' }

foreach ($pattern in @(
    'game\.PlaceId\s*==\s*117533937949084',
    'workspace\.EnemyNpc:FindFirstChildOfClass\("Model"\)',
    'workspace:GetAttribute\("GameMode"\)\s*==\s*""',
    'CFrame\.new\(8561\.28906,\s*273\.670654,\s*-3727\.4563',
    'local MaxNum,\s*MaxNum2\s*=\s*1000,\s*100',
    'local Counting,\s*Counting2\s*=\s*0,\s*0',
    'repeat\s+task\.wait\(\)',
    'local FinalDistance\s*=\s*CFrame\.new\(',
    'LevelType.*Boss',
    'Counting\s*=\s*Counting\s*\+\s*1'
)) {
    if ($worker -notmatch $pattern) {
        throw "Potassium source autofarm contract missing: $pattern"
    }
}

if ($worker -match 'recoverWithoutEnemies|farmCFrame\(') {
    throw 'Custom autofarm recovery/position helpers must not replace the source loop'
}

if ($worker -match 'Attack\(') {
    throw 'BaseAttack must remain in the source-style combat loop, not movement/recovery'
}

foreach ($custom in @('endActionButton', 'After Dungeon', 'endActionState')) {
    if ($source -match [regex]::Escape($custom)) {
        throw "Custom post-clear progression must be removed: $custom"
    }
}

if ($source -notmatch 'local CAMERA_BACK\s*=\s*50') {
    throw 'Source camera back constant is missing'
}

$combat = [regex]::Match($source, '(?s)local function runPotassiumCombat\(\).*?(?=local function runCollectionWorker\(\))').Value
foreach ($pattern in @(
    '(?s)task\.spawn\(function\(\).*?workspace\.EnemyNpc:GetChildren\(\)',
    '(?s)task\.spawn\(function\(\).*?DragonEgg',
    '(?s)task\.spawn\(function\(\).*?Attack\(settings\.autoUseSkill\)'
)) {
    if ($combat -notmatch $pattern) {
        throw "Potassium source combat contract missing: $pattern"
    }
}

if ($source -notmatch 'local function runPotassiumCombat\(\)') {
    throw 'Source-style combat loop is missing'
}

Write-Output 'PASS: Iron Soul autofarm uses the source movement/recovery state machine'
