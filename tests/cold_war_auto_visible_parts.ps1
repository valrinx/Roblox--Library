$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\cold_war.lua')

if ($source -notmatch '(?s)local function scanAutoVisibleParts\(.*?for _, candidate in ipairs\(parts\).*?rayReachesTarget') {
    throw 'Auto Visible must evaluate every candidate part in the same visibility update'
}

if ($source -notmatch '(?s)if autoVisibleActive then\s+.*?scanAutoVisibleParts\(') {
    throw 'Active Auto Visible mode must use the full-part visibility scan'
}

Write-Output 'PASS: Auto Visible evaluates all candidate parts together'
