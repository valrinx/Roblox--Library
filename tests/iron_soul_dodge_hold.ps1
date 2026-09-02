$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')
$match = [regex]::Match(
    $source,
    'Dodge:CreateSlider\(\{Name="Dodge Hold",Range=\{0\.5,([0-9]+(?:\.[0-9]+)?)\}'
)

if (-not $match.Success) {
    throw 'Iron Soul Dodge Hold slider range is missing or has an unexpected shape'
}

$maximumSeconds = [double]::Parse($match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
if ($maximumSeconds -lt 10) {
    throw "Iron Soul Dodge Hold must support at least 10 seconds; found $maximumSeconds"
}

Write-Output 'PASS: Iron Soul Dodge Hold supports a hold window of at least 10 seconds'
