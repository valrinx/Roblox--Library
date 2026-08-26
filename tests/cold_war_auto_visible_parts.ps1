$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\cold_war.lua')

if ($source -notmatch 'local AUTO_VISIBLE_PARTS_PER_SCAN = 4' -or
    $source -notmatch 'local AUTO_VISIBLE_SCAN_INTERVAL = 2' -or
    $source -notmatch '(?s)local function scanAutoVisibleParts\(.*?local scanCount = math\.min\(AUTO_VISIBLE_PARTS_PER_SCAN, #parts\).*?for _ = 1, scanCount do.*?rayReachesTarget') {
    throw 'Auto Visible must use the bounded per-scan raycast budget'
}

if ($source -notmatch '(?s)if autoVisibleActive then\s+.*?scanAutoVisibleParts\(') {
    throw 'Active Auto Visible mode must use the full-part visibility scan'
}

if ($source -notmatch '(?s)result\.Instance == targetPart\s+or \(targetCharacter ~= nil and result\.Instance:IsDescendantOf\(targetCharacter\)\)') {
    throw 'A target accessory in front of an exposed body part must count as reaching that target'
}

if ($source -notmatch '(?s)local function getAimPartPriority\(part\).*?Head.*?return 1.*?Torso.*?return 2.*?Arm.*?return 3.*?return 4') {
    throw 'Auto Lock Part must prioritize head, torso, arms, then legs'
}

if ($source -notmatch '(?s)local AUTO_VISIBLE_SAMPLE_SCALE = 0\.48.*?offsets\[1\].*?edgeIndex.*?rayReachesTarget') {
    throw 'Auto Visible must check the part center first and rotate one edge fallback'
}

if ($source -match 'AUTO_VISIBLE_GRID_STEPS' -or
    $source -match 'getVisibilityOffsets\(candidate, AUTO_VISIBLE_SAMPLE_SCALE, true\)') {
    throw 'Auto Visible must not restore the dense 5x5 per-part scan'
}

if ($source -notmatch '(?s)local function isVisionTransparent\(instance\).*?instance\.Transparency >= 0\.25') {
    throw 'Visibility rays must classify transparent fence and window blockers as pass-through'
}

if ($source -notmatch '(?s)for _ = 1, MAX_VISION_PASSTHROUGHS do.*?isVisionTransparent\(result\.Instance\).*?table\.insert\(ignored, result\.Instance\)') {
    throw 'Visibility rays must continue beyond bounded transparent blockers'
}

$closestMatch = [regex]::Match($source, '(?s)local function getClosestEnemyToCrosshair\(.*?\r?\n    end')
if (-not $closestMatch.Success -or
    $closestMatch.Value.IndexOf('if maxPixels and referenceDistance > maxPixels + AIM_PREFILTER_MARGIN then continue end') -lt 0 -or
    $closestMatch.Value.IndexOf('if maxPixels and referenceDistance > maxPixels + AIM_PREFILTER_MARGIN then continue end') -gt $closestMatch.Value.IndexOf('resolveAimPart(player, requireVisible)')) {
    throw 'Enemies outside the aim FOV must be rejected before visibility raycasts'
}

if ($source -notmatch '(?s)for rank = 1, 4 do.*?getAimPartPriority\(candidate\) == rank.*?if priorityPart then break end') {
    throw 'Auto Visible must stop scanning lower-priority groups after finding a lockable part'
}

if ($source -notmatch '(?s)getClosestEnemyToCrosshair\(\s*requireShootable and State\.AimFOV or nil, requireShootable\s*\)') {
    throw 'Auto Aim prediction fallback must keep visibility searches inside the configured FOV'
}

if ($source -notmatch 'local function isCharacterVisible\(fromPos, targetCharacter, autoVisibleRequest\)' -or
    $source -notmatch 'local autoVisibleActive = autoVisibleRequest == true and State\.AutoAim' -or
    $source -notmatch '(?s)isCharacterVisible\(\s*Camera\.CFrame\.Position, character, true\s*\)') {
    throw 'Dense Auto Visible scans must be requested only by aim resolution, never globally by ESP or radar'
}

Write-Output 'PASS: Auto Visible uses bounded center/edge visibility scans'
