$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "..\modules\the_wild_west.lua"
$source = Get-Content -Raw $modulePath

foreach ($required in @(
    'ItemESP = false',
    'ItemESPDistance = 1200',
    'ItemESPSelected = {}',
    'local droppedItemsFolder = interactablesRoot and interactablesRoot:FindFirstChild\("DroppedItems"\)',
    'local function updateItemESP\(\)',
    'CollectionService:GetTagged\("DroppedItem"\)',
    'IsDescendantOf\(folder\)',
    'State.ItemESPSelected',
    'EntityESPObjects = \{animals = \{\}, loot = \{\}, ore = \{\}, items = \{\}\}',
    'updateItemESP\(\)',
    'clearEntityGroup\(EntityESPObjects.items\)',
    'Name="Item ESP"',
    'Name="Item Filter"',
    'MultipleOptions=true'
)) {
    if ($source -notmatch $required) {
        throw "Item ESP regression check failed: missing $required"
    }
}

if ($source -notmatch 'selected\[itemName\]') {
    throw "Item ESP filter must match each dropped item's display name"
}

Write-Output "PASS: Wild West Item ESP scans tagged dropped items and supports a multi-select item filter"
