$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')

$requiredPatterns = @(
    'autoSwitchWeapon = false',
    'local function getSkillButtons',
    'local function useAllReadySkills',
    'local function switchWeapon',
    'local function runAutoWeaponWorker',
    'SwitchWpn',
    'Weapon2',
    '"Skill1"',
    '"Skill2"',
    '"SkillAW"',
    '"SkillU"',
    'Name="Auto Switch Weapon"'
)

foreach ($pattern in $requiredPatterns) {
    if ($source -notmatch $pattern) {
        throw "Iron Soul weapon-cycle contract missing: $pattern"
    }
}

if ($source -notmatch 'runAutoWeaponWorker\(\)[\s\S]{0,400}while running') {
    throw 'Auto weapon cycle must run in a guarded worker loop'
}

if ($source -notmatch 'currentSlot == 1[\s\S]{0,120}switchWeapon[\s\S]{0,120}currentSlot = 2') {
    throw 'Auto weapon cycle must switch from weapon 1 to weapon 2 after the skill burst'
}

if ($source -notmatch 'currentSlot == 2[\s\S]{0,120}switchWeapon[\s\S]{0,120}currentSlot = 1') {
    throw 'Auto weapon cycle must switch from weapon 2 back to weapon 1'
}

Write-Output 'PASS: Iron Soul auto weapon skill cycle contract is covered'
