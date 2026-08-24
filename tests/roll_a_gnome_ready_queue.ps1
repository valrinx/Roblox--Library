$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\modules\roll_a_gnome.lua"
$source = Get-Content -Raw $modulePath

if ($source -match 'hasReadyFruit\s+or\s+plant:GetAttribute\("FruitReady"\)') {
    throw "Ready queue bypasses per-fruit eligibility through the plant FruitReady attribute"
}

if ($source -notmatch 'GetGrowingFruitCount') {
    throw "Status does not distinguish spawned-but-growing fruit from ready fruit"
}

if ($source -match 'os\.clock\(\) \+ 0\.8') {
    throw "Collector still waits up to 0.8 seconds for every plant in a batch"
}

if ($source -match 'Network:InvokeServer\("CollectPlant", plant\)[\s\S]{0,250}task\.wait\(0\.1\)') {
    throw "Collector still adds a fixed delay after every plant remote"
}

Write-Output "PASS: ready queue only uses eligible fruit and reports growing fruit separately"
