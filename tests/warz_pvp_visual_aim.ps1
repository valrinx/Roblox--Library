$ErrorActionPreference = "Stop"
$source = Get-Content -Raw (Join-Path $PSScriptRoot "..\modules\warz_pvp.lua")
$required = @{
    "patch version" = 'RAVEN_WARZPVP_VER = "1\.4\.3"'
    "R15 rig-part bounds" = 'local BODY_PARTS = \{'
    "R15 head, torso, hands and feet" = '"Head", "UpperTorso", "LowerTorso", "Torso"'
    "live part validation" = 'part:IsA\("BasePart"\)'
    "shared validated head" = 'local head = getAimPart\(model\)'
    "reject detached target" = 'target\.Position - root\.Position'
    "head extremities" = 'head\.CFrame\.UpVector \* head\.Size\.Y \* 0\.5'
    "torso projection" = 'torso\.CFrame\.RightVector \* torso\.Size\.X \* 0\.5'
    "feet projection" = 'foot\.CFrame\.UpVector \* foot\.Size\.Y \* 0\.5'
    "reject offscreen bounds" = 'maxX < 0 or minX > vs\.X'
    "player uses body bounds" = 'characterScreenBounds\(ch\)'
    "boss uses body bounds" = 'characterScreenBounds\(model\)'
    "liveAim joints" = 'local function liveAimJoints\(live\)'
    "aim checks real head" = 'local head = getAimPart\(character\)'
    "aim validates alive" = 'if not isAlive\(character\) then return nil, nil end'
    "aim uses viewport projection" = 'camera:WorldToViewportPoint\(position\)'
    "aim validates FOV" = 'if pixels > maxFov then return nil, nil end'
    "aim line of sight" = 'Workspace:Raycast\(origin, direction, params\)'
    "aim ignores game hitbox folder" = 'Workspace:FindFirstChild\("WarzHitboxes"\)'
    "aim rejects obstructed target" = 'hit\.Instance:IsDescendantOf\(character\)'
    "aim preserves model lock" = 'player\.Character == character'
    "aim lock character reset" = 'aimLockPlayer, aimLockCharacter = nil, nil'
    "aim only acts on aim key" = 'if not aimHeld or not hasMouseMove'
    "ESP throttle" = 'if espTime >= 1 / 30 then'
    "loot throttle" = 'if lootTime >= 1 / 8 then'
    "boss throttle" = 'if bossTime >= 1 / 12 then'
    "refresh camera on replacement" = 'camera = Workspace\.CurrentCamera or camera'
    "cleanup on shutdown" = 'table\.clear\(connections\)'
}
foreach ($item in $required.GetEnumerator()) {
    if ($source -notmatch $item.Value) { throw "Missing: $($item.Key)" }
}
$oldPatterns = @(
    'hrp\.Position \+ Vector3\.new\(0, 3, 0\)',
    'hrp\.Position - Vector3\.new\(0, 3, 0\)',
    'hrp\.Position \+ Vector3\.new\(0, 4, 0\)',
    'hrp\.Position - Vector3\.new\(0, 4, 0\)',
    'ch:FindFirstChild\("Head"\) or ch:FindFirstChild\("HumanoidRootPart"\)'
)
foreach ($pattern in $oldPatterns) {
    if ($source -match $pattern) { throw "Legacy aim/bounds path remains: $pattern" }
}
Write-Output "PASS: $($required.Count) WarZ ESP/aim source contracts; no fixed-root boxes or HRP aim fallback"
