$ErrorActionPreference = "Stop"

$adapter = Get-Content -Raw (Join-Path $PSScriptRoot "..\modules\maclib_adapter.lua")
$hub = Get-Content -Raw (Join-Path $PSScriptRoot "..\RAVENHUB")

if ($adapter -notmatch 'local function installExactConfigLoader\(\)') {
    throw "The exact config loader implementation is missing"
}

if ($adapter -notmatch '(?s)function Adapter:CreateWindow\(options\).*?installExactConfigLoader\(\).*?return window') {
    throw "The exact config loader must be installed after MacLib creates the window"
}

if ($adapter -notmatch 'option:UpdateState\(saved\.state == true\)' -or
    $adapter -notmatch 'option:UpdateValue\(tonumber\(saved\.value\) or saved\.value\)' -or
    $adapter -notmatch 'option:UpdateSelection\(saved\.value\)') {
    throw "Config loading does not replay toggle, slider, and dropdown values"
}

if ($adapter -notmatch 'local callback = option\.Settings and option\.Settings\.Callback' -or
    $adapter -notmatch 'callback\(option:GetValue\(\)\)') {
    throw "Config loading does not synchronize slider callbacks with module state"
}

if ($hub -notmatch 'HubUI:LoadAutoLoadConfig\(\)') {
    throw "The hub does not load the saved profile on startup"
}

if ($hub -notmatch 'modules/maclib_adapter\.lua\?v=maclib-adapter-1\.1\.2') {
    throw "The hub adapter URL must be cache-busted for the config loader fix"
}

if ($hub -notmatch 'local function sanitizeConfigSegment\(value, fallback\)') {
    throw "Config game names must be sanitized before being used as filesystem paths"
}

if ($hub -notmatch 'local CONFIG_GAME_NAME = sanitizeConfigSegment\(EXPERIENCE_NAME, "Roblox Experience"\)') {
    throw "Config folder must be scoped by the sanitized experience name"
}

if ($hub -notmatch 'local CONFIG_FOLDER = "RAVENHUB/" \.\. CONFIG_GAME_NAME') {
    throw "Config folder must use the RAVENHUB/<GameName> hierarchy"
}

if ($hub -notmatch 'local CONFIG_FILE_NAME\s*=\s*"TEST"' -or
    $hub -notmatch 'FileName\s*=\s*CONFIG_FILE_NAME') {
    throw "The default config file name must be TEST (MacLib adds .json)"
}

if ($adapter -notmatch 'local function ensureFolderTree\(folder\)') {
    throw "Nested config folders must be created one segment at a time"
}

if ($adapter -notmatch '(?s)ensureFolderTree\(tostring\(saving\.FolderName or "RAVENHUB"\)\).*?MacLib:SetFolder\(tostring\(saving\.FolderName or "RAVENHUB"\)\)') {
    throw "The adapter must prepare nested folders before handing the path to MacLib"
}

Write-Output "PASS: MacLib config loader is installed and replays saved control state"
