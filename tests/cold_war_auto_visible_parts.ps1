$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\cold_war.lua')

if ($source -notmatch '(?s)local function scanAutoVisibleParts\(.*?for _, candidate in ipairs\(parts\).*?rayReachesTarget') {
    throw 'Auto Visible must evaluate every candidate part in the same visibility update'
}

if ($source -notmatch '(?s)if autoVisibleActive then\s+.*?scanAutoVisibleParts\(') {
    throw 'Active Auto Visible mode must use the full-part visibility scan'
}

if ($source -notmatch '(?s)if targetPart then\s+return result\.Instance == targetPart\s+or \(targetCharacter ~= nil and result\.Instance:IsDescendantOf\(targetCharacter\)\)') {
    throw 'A target accessory in front of an exposed body part must count as reaching that target'
}

if ($source -notmatch '(?s)local function getAimPartPriority\(part\).*?Head.*?return 1.*?Torso.*?return 2.*?Arm.*?return 3.*?return 4') {
    throw 'Auto Lock Part must prioritize head, torso, arms, then legs'
}

if ($source -notmatch '(?s)local AUTO_VISIBLE_SAMPLE_SCALE = 0\.48.*?for _, offset in ipairs\(getVisibilityOffsets\(candidate, AUTO_VISIBLE_SAMPLE_SCALE\)\).*?rayReachesTarget') {
    throw 'Auto Visible must sample near each part edge to detect small exposed areas'
}

Write-Output 'PASS: Auto Visible evaluates all candidate parts together'
