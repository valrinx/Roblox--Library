$ErrorActionPreference = "Stop"
$source = Get-Content -Raw (Join-Path $PSScriptRoot "..\modules\anime_battlegrounds.lua")
$checks = @{
    "default center-first" = 'TargetPriority = "Center FOV"'
    "center comparator" = 'return pixels < bestPixels or \(pixels == bestPixels and health < bestHealth\)'
    "low HP comparator" = 'return health < bestHealth or \(health == bestHealth and pixels < bestPixels\)'
    "priority dropdown" = 'Flag = "AB_SkillAimTargetPriority"'
    "priority options" = 'Options = \{"Center FOV", "Lowest HP"\}'
    "mode setter" = 'local function setSkillTargetPriority\(value\)'
    "invalid mode rejected" = 'mode ~= "Center FOV" and mode ~= "Lowest HP"'
    "target and preview invalidated" = 'skillAim\.Target, skillAim\.VisualTarget = nil, nil'
    "lock cleared on switch" = 'skillAim\.LockUntil, skillAim\.LastScan = 0, 0'
    "range gate" = 'if range and \(point - ownRoot\.Position\)\.Magnitude > range then'
    "FOV gate independent of ranking" = 'pixels >= skillAim\.Fov'
    "dead enemies filtered" = 'not hum or hum\.Health <= 0'
    "wall raycast gate" = 'if ray and not ray\.Instance:IsDescendantOf\(model\) then return end'
    "dummy fallback" = 'if not chosen then\s+for _, dummy in ipairs\(CollectionService:GetTagged\("Dummy"\)\)'
    "public mode setter" = 'SetSkillAimTargetPriority = function\(value\)'
    "status mode" = 'targetPriority = skillAim\.TargetPriority'
}
foreach ($item in $checks.GetEnumerator()) {
    if ($source -notmatch $item.Value) { throw "Missing target priority contract: $($item.Key)" }
}
$selectorStart = $source.IndexOf('local function chooseSkillTarget()')
$selectorEnd = $source.IndexOf('local function setSkillTargetPriority(value)', $selectorStart)
if ($selectorStart -lt 0 -or $selectorEnd -le $selectorStart) { throw "Target selector missing" }
$selector = $source.Substring($selectorStart, $selectorEnd - $selectorStart)
$indexes = @(
    $selector.IndexOf('pixels >= skillAim.Fov'),
    $selector.IndexOf('betterSkillCandidate(pixels, hum.Health, bestPixels, bestHealth)'),
    $selector.IndexOf('Workspace:Raycast('),
    $selector.IndexOf('bestPixels, bestHealth, chosen ='),
    $selector.IndexOf('for _, player in ipairs(Players:GetPlayers())'),
    $selector.IndexOf('if not chosen then'),
    $selector.IndexOf('CollectionService:GetTagged("Dummy")')
)
if ($indexes -contains -1) { throw "Missing selector condition" }
if (-not ($indexes[0] -lt $indexes[1] -and $indexes[1] -lt $indexes[2] -and $indexes[2] -lt $indexes[3])) {
    throw "FOV/priority/occlusion filters must run before target selection"
}
if (-not ($indexes[4] -lt $indexes[5] -and $indexes[5] -lt $indexes[6])) {
    throw "Players must be evaluated before dummy fallback"
}
Write-Output "PASS: 16 target priority contracts plus ordering guards"
