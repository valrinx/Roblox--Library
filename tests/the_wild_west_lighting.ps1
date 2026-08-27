$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\modules\the_wild_west.lua"
$source = Get-Content -Raw $modulePath

if ($source -notmatch 'originalAtmospheres') {
    throw "Lighting override only tracks one Atmosphere and cannot restore dynamic fog effects"
}

if ($source -notmatch 'for _, child in ipairs\(Lighting:GetChildren\(\)\) do[\s\S]{0,500}IsA\("Atmosphere"\)') {
    throw "No Fog does not apply to every live Atmosphere instance"
}

if ($source -notmatch 'originalAtmospheres\[child\]') {
    throw "No Fog does not restore each Atmosphere's original density"
}

if ($source -notmatch 'applyNoFog\(State\.NoFog\)') {
    throw "No Fog state is not reapplied during the runtime update loop"
}

Write-Output "PASS: Wild West lighting overrides handle dynamic Atmosphere instances and restore them"
