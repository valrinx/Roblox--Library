$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\modules\the_wild_west.lua"
$source = Get-Content -Raw $modulePath

if ($source -notmatch 'local function adjustProjectileDirection\(result, projectileType, projectileData, sharedData\)') {
    throw "No Spread must normalize the returned projectile velocity table"
}

if ($source -notmatch 'function\(self, projectileType, sharedData, projectileData, projectileCount, \.\.\.\)') {
    throw "No Spread hook is not using ProjectileHandler:GetProjectileSpread's real argument layout"
}

if ($source -notmatch 'projectileData\.direction' -or
    $source -notmatch 'for key, velocity in pairs\(result\) do') {
    throw "No Spread must flatten each returned projectile around the requested direction"
}

$hookBlock = [regex]::Match($source, 'local function installNoSpreadHook\(\)[\s\S]{0,1800}').Value
if ($hookBlock -match 'function\(self, direction, \.\.\.\)' -or
    $hookBlock -match 'if typeof\(direction\) ~= "Vector3"' -or
    $hookBlock -match 'return direction\s*end') {
    throw "No Spread still treats the projectile type as a Vector3 and bypasses the result table"
}

Write-Output "PASS: Wild West No Spread maps the real spread signature and flattens projectile velocities"
