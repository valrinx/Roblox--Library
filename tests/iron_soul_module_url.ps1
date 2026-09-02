$ErrorActionPreference = 'Stop'

$hub = Get-Content -Raw (Join-Path $PSScriptRoot '..\RAVENHUB')
$match = [regex]::Match($hub, 'name\s*=\s*"Iron Soul: Dungeon"[\s\S]*?moduleUrl\s*=\s*"([^"]+)"')
if (-not $match.Success) {
    throw 'Iron Soul module URL is missing from RAVENHUB'
}

$url = $match.Groups[1].Value
try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing
} catch {
    throw "Iron Soul module URL is not reachable: $url ($($_.Exception.Message))"
}

if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'RAVEN HUB \| Iron Soul: Dungeon') {
    throw "Iron Soul module URL returned an invalid module payload: $url"
}

Write-Output 'PASS: Iron Soul module URL resolves to a valid payload'
