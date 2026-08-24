$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\cold_war.lua')
$match = [regex]::Match(
    $source,
    '(?s)local function updateAimPrediction\(dt\)(.*?)\r?\n    ---------------------------------------------------------------------------\r?\n    -- Connections'
)

if (-not $match.Success) {
    throw 'Could not isolate updateAimPrediction'
}

$body = $match.Groups[1].Value
if ($body -match 'predictionDisplayPosition:Lerp') {
    throw 'Aim Prediction applies a second screen-space smoothing pass after Auto Aim already smooths the camera'
}

Write-Output 'PASS: Aim Prediction uses the current camera projection without double smoothing'
