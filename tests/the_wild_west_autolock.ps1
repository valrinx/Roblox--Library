$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\modules\the_wild_west.lua"
$source = Get-Content -Raw $modulePath

if ($source -notmatch 'LOCK_GRACE_DURATION\s*=\s*') {
    throw "Auto Lock has no grace window for transient visibility/target-scan misses"
}

if ($source -notmatch 'PredictionLeadScale') {
    throw "Prediction lead is not exposed as a tunable setting"
}

if ($source -notmatch 'Name="Prediction Lead"') {
    throw "Prediction Lead control is missing from the Wild West combat tab"
}

if ($source -notmatch 'State\.PredictionLeadScale') {
    throw "Aim prediction does not consume the configured lead scale"
}

if (($source -notmatch 'resolveTargetAimPart\(player, State\.AimVisibleCheck, true\)') -or ($source -notmatch 'resolveTargetAimPart\(animal, State\.AimVisibleCheck, true\)')) {
    throw "Visible check does not force a complete scan for candidate targets"
}

Write-Output "PASS: Wild West Auto Lock has grace, tunable lead, and complete candidate visibility scanning"
