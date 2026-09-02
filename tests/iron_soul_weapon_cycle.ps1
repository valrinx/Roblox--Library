$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')

$requiredPatterns = @(
    'autoSwitchWeapon = false',
    'local function getSkillButtons',
    'local function useAllReadySkills',
    'local function switchWeapon',
    'firesignal\(button\.MouseButton1Down\)',
    'firesignal\(button\.MouseButton1Up\)',
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

if ($source -notmatch 'if not value or value=="" then return nil end') {
    throw 'Weapon switch key lookup must handle buttons without a Key label'
}
if ($source -notmatch 'local enumOk,enumValue=pcall\(function\(\) return Enum\.KeyCode\[value\] end\)') {
    throw 'Weapon switch key lookup must ignore labels that are not valid Enum.KeyCode names'
}

$switchBlock = [regex]::Match($source, 'local function switchWeapon[\s\S]*?\n    end\n    local function runAutoWeaponWorker').Value
$keyIndex = $switchBlock.IndexOf('local keyCode=buttonKeyCode(switch)')
$candidateIndex = $switchBlock.IndexOf('local candidates=')
if ($keyIndex -lt 0 -or $candidateIndex -lt 0 -or $keyIndex -gt $candidateIndex) {
    throw 'Weapon switching must try the main button key before GUI signal fallbacks'
}

Write-Output 'PASS: Iron Soul auto weapon skill cycle contract is covered'
