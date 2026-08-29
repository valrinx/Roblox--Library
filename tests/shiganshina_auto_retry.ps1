$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\modules\shiganshina.lua"
$source = Get-Content -Raw $modulePath

if ($source -notmatch 'local RetryState\s*=\s*\{') {
    throw "Auto Retry must keep explicit state for pending and in-flight retry attempts"
}

if ($source -notmatch 'local function getVisibleRetryButton\(') {
    throw "Auto Retry must resolve the mission Retry button from the Rewards UI"
}

if ($source -notmatch 'Rewards[\s\S]{0,700}Buttons[\s\S]{0,200}Retry') {
    throw "The mission completion Retry path is missing"
}

if ($source -notmatch '\.Died:Connect') {
    throw "Auto Retry must observe Humanoid.Died instead of polling only the UI"
}

if ($source -notmatch 'LP\.CharacterAdded:Connect\([\s\S]{0,500}bindRetryDeath\(c\)') {
    throw "Auto Retry must rebind death detection after every character respawn"
}

if ($source -notmatch 'VirtualInputManager') {
    throw "Auto Retry needs a real mouse-input fallback when GuiButton signals are not exposed"
}

if ($source -notmatch 'RetryState\.waitingForRound') {
    throw "Auto Retry must debounce a click until the next round starts"
}

if ($source -match 'death:GetDescendants\(\)') {
    throw "Death handling must not scan for buttons that do not exist in this game's Death screen"
}

if ($source -match 'POST:FireServer\("Retry"\)' -or
    $source -match 'POST:FireServer\("Respawn"\)' -or
    $source -match 'GET:InvokeServer\("Retry"\)') {
    throw "Auto Retry must not send unverified Retry/Respawn remote arguments"
}

Write-Output "PASS: Shiganshina Auto Retry has explicit death detection, UI resolution, input fallback, and debounce"
