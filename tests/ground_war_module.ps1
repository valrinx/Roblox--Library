$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot '..\modules\ground_war.lua'
$hubPath = Join-Path $PSScriptRoot '..\RAVENHUB'

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw 'Ground War module is missing'
}

$source = Get-Content -Raw -LiteralPath $modulePath
$hub = Get-Content -Raw -LiteralPath $hubPath

foreach ($required in @(
    'Ground War (o)',
    'PlaceId: 76822114837453',
    'GameId: 6583326485',
    'workspace:FindFirstChild("Bots")',
    'CollectionService:GetTagged("AIBot")',
    'GetAttribute("MG_Team")',
    'GetAttribute("Team")',
    'local function getTargetEntries()',
    'local function getCurrentWeaponConfig()',
    'local function getPredictedPosition(',
    'local function isCharacterVisible(',
    'local function updateAutoAim(',
    'local function updateRadar()',
    'local function applyFullbright(',
    'local function applyNoFog(',
    'local function applyFOV(',
    'UnbindFromRenderStep(renderStepName)',
    '__RAVEN_GROUND_WAR = {Version='
)) {
    if ($source.IndexOf($required) -lt 0) {
        throw "Ground War module is missing required behavior: $required"
    }
}

$visibilityMatch = [regex]::Match(
    $source,
    '(?s)local function rayReachesTarget\(.*?\r?\n    end\r?\n\r?\n    local function partOffsets'
)
if (-not $visibilityMatch.Success -or
    $visibilityMatch.Value -notmatch 'local reachesTarget = false' -or
    $visibilityMatch.Value -notmatch 'RayParams\.FilterDescendantsInstances = baseIgnored\s+return reachesTarget' -or
    $visibilityMatch.Value -match '(?s)for _ = 1, MAX_VISION_PASSTHROUGHS do.*?return (true|false)') {
    throw 'Visibility raycasts must restore their temporary filter before returning'
}

if ($source -notmatch '(?s)workspace:FindFirstChild\("Bots"\).*?GetAttribute\("MG_Team"\)' -and
    $source -notmatch '(?s)GetAttribute\("MG_Team"\).*?workspace:FindFirstChild\("Bots"\)') {
    throw 'Ground War target resolution must use bot team metadata'
}

if ($source -match 'FireServer|InvokeServer|Replay|replay_remote') {
    throw 'Ground War module must remain read-only and must not invoke game remotes'
}

if ($hub -notmatch 'name\s*=\s*"Ground War \(o\)"' -or
    $hub -notmatch 'placeIds\s*=\s*\{76822114837453\}' -or
    $hub -notmatch 'gameIds\s*=\s*\{6583326485\}' -or
    $hub -notmatch 'modules/ground_war\.lua') {
    throw 'RAVENHUB registration is missing or incorrect'
}

Write-Output 'PASS: Ground War module contract and registration checks passed'
