$ErrorActionPreference = 'Stop'

$source = Get-Content -Raw (Join-Path $PSScriptRoot '..\modules\iron_soul.lua')
$hub = Get-Content -Raw (Join-Path $PSScriptRoot '..\RAVENHUB')

if ($source -notmatch 'local function createTab\(name, icon\)') {
    throw 'Iron Soul must centralize module tab creation behind createTab'
}

if ($source -match 'local function createTab\(name, icon\)\s*task\.wait\(\)') {
    throw 'Iron Soul createTab must not yield before calling MacLib CreateTab'
}

if ($source -notmatch 'local function createTab\(name, icon\)\s*return Window:CreateTab\(name, icon\)') {
    throw 'Iron Soul createTab must call MacLib CreateTab on the original loader thread'
}

$tabDefinition = $source.IndexOf('local function createTab')
if ($tabDefinition -lt 0) {
    throw 'Iron Soul createTab definition is missing'
}
$preTabSource = $source.Substring(0, $tabDefinition)
if ($preTabSource -match ':WaitForChild\(') {
    throw 'Iron Soul must not yield on WaitForChild before building MacLib tabs'
}

$firstTabCall = $source.IndexOf('local Dashboard=createTab')
if ($firstTabCall -lt 0) {
    throw 'Iron Soul Dashboard tab definition is missing'
}
$preFirstTabSource = $source.Substring(0, $firstTabCall)
if ($preFirstTabSource -match 'require\(frameworkModule\)') {
    throw 'Iron Soul must not require Framework before building MacLib tabs'
}

if ([regex]::Matches($source, '(?m)^\s*(?!return\s+)Window:CreateTab\(').Count -gt 0) {
    throw 'Iron Soul must not bypass the createTab wrapper'
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

$settingsTabCall = $hub.IndexOf('local HubSettingsTab = Window:CreateTab("Settings"')
$moduleDispatchLoop = $hub.IndexOf('local matchedAnyScript = false')
if ($settingsTabCall -lt 0 -or $moduleDispatchLoop -lt 0 -or $settingsTabCall -gt $moduleDispatchLoop) {
    throw 'RAVENHUB must create its Settings tab before dispatching experience modules'
}

Write-Output 'Iron Soul UI capability regression checks passed.'
