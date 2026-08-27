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

if ($source -notmatch 'Glare = child\.Glare' -or
    $source -notmatch 'atmosphere\.Glare = 0') {
    throw "No Fog must neutralize Atmosphere glare as well as density and haze"
}

if ($source -notmatch 'ExposureCompensation = Lighting\.ExposureCompensation' -or
    $source -notmatch 'EnvironmentDiffuseScale = Lighting\.EnvironmentDiffuseScale' -or
    $source -notmatch 'EnvironmentSpecularScale = Lighting\.EnvironmentSpecularScale') {
    throw "Fullbright must preserve the additional Lighting exposure/scattering settings"
}

if ($source -notmatch 'Lighting\.ExposureCompensation = 0' -or
    $source -notmatch 'Lighting\.EnvironmentDiffuseScale = 1' -or
    $source -notmatch 'Lighting\.EnvironmentSpecularScale = 1') {
    throw "Fullbright does not force a usable exposure and environment light level"
}

if ($source -notmatch 'BindToRenderStep\(renderStepName, Enum\.RenderPriority\.Last\.Value') {
    throw "Lighting overrides must run after the game's weather render updates"
}

if ($source -notmatch 'applyNoFog\(State\.NoFog\)') {
    throw "No Fog state is not reapplied during the runtime update loop"
}

Write-Output "PASS: Wild West lighting overrides handle dynamic Atmosphere instances and restore them"
