$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')
$hub = Get-Content -Raw (Join-Path $PSScriptRoot '..\RAVENHUB')

if ($source -notmatch 'local function createTab\(name, icon\)') {
    throw 'Iron Soul must centralize module tab creation behind createTab'
}

if ($source -notmatch 'local function createTab\(name, icon\)\s*task\.wait\(\)\s*return Window:CreateTab\(name, icon\)') {
    throw 'Iron Soul createTab must yield before calling MacLib CreateTab'
}

if ([regex]::Matches($source, '(?m)^\s*(?!return\s+)Window:CreateTab\(').Count -gt 0) {
    throw 'Iron Soul must not bypass the yielding createTab wrapper'
}

$tabCalls = [regex]::Matches($source, '\bcreateTab\(').Count
if ($tabCalls -ne 6) {
    throw "Expected createTab to be used for all 5 module tabs plus its definition; found $tabCalls"
}

if ($source -match '(?m)^\s*local\s+Utility\s*=\s*createTab\(') {
    throw 'Iron Soul Utility tab must be removed'
}

if ($source -match '(?m)^\s*local\s+Progress\s*=\s*createTab\(') {
    throw 'Iron Soul Progress tab must be removed'
}

if ($source -match 'createTab\("Combat Intel"') {
    throw 'Iron Soul Combat Intel tab must be renamed to ESP'
}

if ($source -notmatch 'createTab\("ESP"') {
    throw 'Iron Soul must expose the combat intelligence tab as ESP'
}

if ($hub -notmatch 'moduleUrl\s*=\s*"https://raw\.githubusercontent\.com/valrinx/Roblox--Library/[0-9a-f]{7,40}/modules/iron_soul\.lua"') {
    throw 'RAVENHUB must pin Iron Soul to an immutable module revision to avoid stale client cache'
}

Write-Output 'Iron Soul UI capability regression checks passed.'
