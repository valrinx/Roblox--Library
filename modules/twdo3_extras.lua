-- RAVEN HUB | TWDO3 awareness, overlay, radar, alerts, and diagnostics
return function(context)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local Debris = game:GetService("Debris")

    local Window = context.Window
    local localPlayer = context.localPlayer
    local settings = context.settings
    local records = context.records
    local espFolder = context.espFolder
    local scriptRunning = true
    local connections = {}
    local overlays = {}
    local alertInside = {}
    local deathMarkers = {}
    local selectedPlayerId = nil
    local playerByMonitorLabel = {}
    local monitorDropdown = nil
    local monitorLabel = nil
    local debugLabel = nil
    local presetLabel = nil
    local frameCount = 0
    local fps = 0
    local lastFpsClock = os.clock()
    local visualAccumulator = 0
    local diagnosticAccumulator = 0
    local monitorAccumulator = 0

    local function disconnect(connection)
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    local function applyDefault(key, value)
        if settings[key] == nil then
            settings[key] = value
        end
    end

    applyDefault("boxESP", false)
    applyDefault("tracerESP", false)
    applyDefault("skeletonESP", false)
    applyDefault("radarEnabled", false)
    applyDefault("radarRange", 500)
    applyDefault("proximityAlerts", false)
    applyDefault("playerAlertDistance", 250)
    applyDefault("walkerAlertDistance", 100)
    applyDefault("deathMarkers", true)
    applyDefault("deathMarkerDuration", 20)
    applyDefault("visualFps", 20)
    applyDefault("debugEnabled", true)

    local previousGui = nil
    pcall(function()
        local parent = localPlayer:FindFirstChildOfClass("PlayerGui")
        if type(gethui) == "function" then
            parent = gethui()
        end
        previousGui = parent and parent:FindFirstChild("RavenHub_TWDO3_Overlay")
    end)
    if previousGui then
        previousGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RavenHub_TWDO3_Overlay"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 900
    local guiParent = localPlayer:WaitForChild("PlayerGui")
    pcall(function()
        if type(gethui) == "function" then
            guiParent = gethui()
        end
    end)
    screenGui.Parent = guiParent

    local function makeLine(parent, thickness)
        local line = Instance.new("Frame")
        line.AnchorPoint = Vector2.new(0, 0.5)
        line.BackgroundColor3 = Color3.new(1, 1, 1)
        line.BorderSizePixel = 0
        line.Size = UDim2.fromOffset(0, thickness or 1)
        line.Visible = false
        line.ZIndex = 20
        line.Parent = parent
        return line
    end

    local function updateLine(line, fromPoint, toPoint, color, thickness, visible)
        if not visible then
            line.Visible = false
            return
        end
        local delta = toPoint - fromPoint
        local length = delta.Magnitude
        if length < 1 then
            line.Visible = false
            return
        end
        line.Position = UDim2.fromOffset(fromPoint.X, fromPoint.Y)
        line.Size = UDim2.fromOffset(length, thickness or 1)
        line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
        line.BackgroundColor3 = color
        line.Visible = true
    end

    local radar = Instance.new("Frame")
    radar.Name = "Radar"
    radar.AnchorPoint = Vector2.new(1, 0)
    radar.Position = UDim2.new(1, -24, 0, 90)
    radar.Size = UDim2.fromOffset(190, 190)
    radar.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
    radar.BackgroundTransparency = 0.18
    radar.BorderSizePixel = 0
    radar.Visible = false
    radar.ZIndex = 30
    radar.Parent = screenGui

    local radarCorner = Instance.new("UICorner")
    radarCorner.CornerRadius = UDim.new(1, 0)
    radarCorner.Parent = radar

    local radarStroke = Instance.new("UIStroke")
    radarStroke.Color = Color3.fromRGB(100, 110, 125)
    radarStroke.Transparency = 0.25
    radarStroke.Thickness = 1
    radarStroke.Parent = radar

    local horizontal = Instance.new("Frame")
    horizontal.Position = UDim2.new(0, 8, 0.5, 0)
    horizontal.Size = UDim2.new(1, -16, 0, 1)
    horizontal.BackgroundColor3 = Color3.fromRGB(90, 100, 115)
    horizontal.BackgroundTransparency = 0.55
    horizontal.BorderSizePixel = 0
    horizontal.ZIndex = 31
    horizontal.Parent = radar

    local vertical = horizontal:Clone()
    vertical.Position = UDim2.new(0.5, 0, 0, 8)
    vertical.Size = UDim2.new(0, 1, 1, -16)
    vertical.Parent = radar

    local radarTitle = Instance.new("TextLabel")
    radarTitle.BackgroundTransparency = 1
    radarTitle.Position = UDim2.fromOffset(0, 8)
    radarTitle.Size = UDim2.new(1, 0, 0, 16)
    radarTitle.Font = Enum.Font.GothamBold
    radarTitle.Text = "RADAR"
    radarTitle.TextColor3 = Color3.fromRGB(225, 230, 240)
    radarTitle.TextSize = 11
    radarTitle.ZIndex = 32
    radarTitle.Parent = radar

    local radarCenter = Instance.new("Frame")
    radarCenter.AnchorPoint = Vector2.new(0.5, 0.5)
    radarCenter.Position = UDim2.fromScale(0.5, 0.5)
    radarCenter.Size = UDim2.fromOffset(7, 7)
    radarCenter.BackgroundColor3 = Color3.fromRGB(80, 180, 255)
    radarCenter.BorderSizePixel = 0
    radarCenter.ZIndex = 34
    radarCenter.Parent = radar
    local centerCorner = Instance.new("UICorner")
    centerCorner.CornerRadius = UDim.new(1, 0)
    centerCorner.Parent = radarCenter

    local function createOverlay(record)
        local existing = overlays[record]
        if existing then
            return existing
        end
        local overlay = {
            box = {},
            skeleton = {},
        }
        for index = 1, 4 do
            overlay.box[index] = makeLine(screenGui, 1)
        end
        overlay.tracer = makeLine(screenGui, 1)
        for index = 1, 12 do
            overlay.skeleton[index] = makeLine(screenGui, 1)
        end
        overlay.radarBlip = Instance.new("Frame")
        overlay.radarBlip.AnchorPoint = Vector2.new(0.5, 0.5)
        overlay.radarBlip.Size = UDim2.fromOffset(record.category == "player" and 7 or 5, record.category == "player" and 7 or 5)
        overlay.radarBlip.BorderSizePixel = 0
        overlay.radarBlip.Visible = false
        overlay.radarBlip.ZIndex = 35
        overlay.radarBlip.Parent = radar
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = overlay.radarBlip
        overlays[record] = overlay
        return overlay
    end

    local function hideOverlay(overlay)
        for _, line in ipairs(overlay.box) do
            line.Visible = false
        end
        for _, line in ipairs(overlay.skeleton) do
            line.Visible = false
        end
        overlay.tracer.Visible = false
        overlay.radarBlip.Visible = false
    end

    local function destroyOverlay(record)
        local overlay = overlays[record]
        if not overlay then
            return
        end
        for _, line in ipairs(overlay.box) do
            line:Destroy()
        end
        for _, line in ipairs(overlay.skeleton) do
            line:Destroy()
        end
        overlay.tracer:Destroy()
        overlay.radarBlip:Destroy()
        overlays[record] = nil
        alertInside[record] = nil
    end

    local function project(camera, position)
        local point, onScreen = camera:WorldToViewportPoint(position)
        return Vector2.new(point.X, point.Y), onScreen and point.Z > 0
    end

    local function updateBox(overlay, camera, record, color, enabled)
        if not enabled or not record.target:IsA("Model") then
            for _, line in ipairs(overlay.box) do
                line.Visible = false
            end
            return
        end
        local ok, _, size = pcall(record.target.GetBoundingBox, record.target)
        local position = record.root and record.root.Position
        if not ok or not position then
            for _, line in ipairs(overlay.box) do
                line.Visible = false
            end
            return
        end
        local top, topVisible = project(camera, position + Vector3.new(0, size.Y * 0.58, 0))
        local bottom, bottomVisible = project(camera, position - Vector3.new(0, size.Y * 0.52, 0))
        if not topVisible or not bottomVisible then
            for _, line in ipairs(overlay.box) do
                line.Visible = false
            end
            return
        end
        local height = math.max(math.abs(bottom.Y - top.Y), 12)
        local width = math.max(height * 0.48, 10)
        local centerX = (top.X + bottom.X) * 0.5
        local left = centerX - width * 0.5
        local right = centerX + width * 0.5
        updateLine(overlay.box[1], Vector2.new(left, top.Y), Vector2.new(right, top.Y), color, 1, true)
        updateLine(overlay.box[2], Vector2.new(right, top.Y), Vector2.new(right, bottom.Y), color, 1, true)
        updateLine(overlay.box[3], Vector2.new(right, bottom.Y), Vector2.new(left, bottom.Y), color, 1, true)
        updateLine(overlay.box[4], Vector2.new(left, bottom.Y), Vector2.new(left, top.Y), color, 1, true)
    end

    local skeletonPairs = {
        {"Head", "UpperTorso"}, {"Head", "Torso"}, {"UpperTorso", "LowerTorso"},
        {"Torso", "Left Arm"}, {"Torso", "Right Arm"}, {"Torso", "Left Leg"}, {"Torso", "Right Leg"},
        {"UpperTorso", "LeftUpperArm"}, {"LeftUpperArm", "LeftLowerArm"},
        {"UpperTorso", "RightUpperArm"}, {"RightUpperArm", "RightLowerArm"},
        {"LowerTorso", "LeftUpperLeg"}, {"LowerTorso", "RightUpperLeg"},
    }

    local function updateSkeleton(overlay, camera, record, color, enabled)
        local lineIndex = 0
        if enabled and record.target:IsA("Model") then
            for _, pair in ipairs(skeletonPairs) do
                if lineIndex >= #overlay.skeleton then
                    break
                end
                local first = record.target:FindFirstChild(pair[1])
                local second = record.target:FindFirstChild(pair[2])
                if first and second and first:IsA("BasePart") and second:IsA("BasePart") then
                    local firstPoint, firstVisible = project(camera, first.Position)
                    local secondPoint, secondVisible = project(camera, second.Position)
                    if firstVisible and secondVisible then
                        lineIndex += 1
                        updateLine(overlay.skeleton[lineIndex], firstPoint, secondPoint, color, 1, true)
                    end
                end
            end
        end
        for index = lineIndex + 1, #overlay.skeleton do
            overlay.skeleton[index].Visible = false
        end
    end

    local function updateRadarBlip(overlay, camera, record, localPosition, color)
        if not settings.radarEnabled or not localPosition or not record.root then
            overlay.radarBlip.Visible = false
            return
        end
        local offset = record.root.Position - localPosition
        local flatDistance = Vector2.new(offset.X, offset.Z).Magnitude
        if flatDistance > settings.radarRange then
            overlay.radarBlip.Visible = false
            return
        end
        local relative = camera.CFrame:VectorToObjectSpace(offset)
        local radius = 82
        local point = Vector2.new(relative.X, relative.Z) / math.max(settings.radarRange, 1) * radius
        if point.Magnitude > radius then
            point = point.Unit * radius
        end
        overlay.radarBlip.Position = UDim2.fromOffset(95 + point.X, 95 + point.Y)
        overlay.radarBlip.BackgroundColor3 = color
        overlay.radarBlip.Visible = true
    end

    local function maybeAlert(record)
        if not settings.proximityAlerts or record.category == "loot" or not record.distance then
            alertInside[record] = false
            return
        end
        local threshold = record.category == "player" and settings.playerAlertDistance or settings.walkerAlertDistance
        local isInside = record.distance <= threshold
        if isInside and not alertInside[record] then
            local label = record.category == "player" and record.label or "Walker"
            context.notify("Proximity Alert", string.format("%s at %.0f studs%s", label, record.distance, record.wallBlocked and " [WALL]" or ""))
        end
        alertInside[record] = isInside
    end

    local function updateRecordOverlay(record, camera, localPosition)
        local overlay = createOverlay(record)
        if not record.active or not record.root or not record.root.Parent then
            hideOverlay(overlay)
            return
        end
        local targetPoint, onScreen = project(camera, record.root.Position)
        local hiddenByWall = settings.hideBehindWalls and record.wallBlocked
        local color = record.displayColor or record.color or Color3.new(1, 1, 1)
        local canDraw = onScreen and not hiddenByWall and record.category ~= "loot"
        updateBox(overlay, camera, record, color, settings.boxESP and canDraw)
        updateSkeleton(overlay, camera, record, color, settings.skeletonESP and canDraw)
        updateLine(
            overlay.tracer,
            Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y - 8),
            targetPoint,
            color,
            1,
            settings.tracerESP and canDraw
        )
        updateRadarBlip(overlay, camera, record, localPosition, color)
        maybeAlert(record)
    end

    local function getDropdownValue(value)
        if type(value) ~= "table" then
            return value
        end
        if type(value[1]) == "string" then
            return value[1]
        end
        for key, selected in pairs(value) do
            if type(key) == "string" and selected == true then
                return key
            elseif type(selected) == "string" then
                return selected
            end
        end
        return nil
    end

    local function collectMonitorOptions()
        local options = {}
        playerByMonitorLabel = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then
                local label = context.playerLabel(player)
                playerByMonitorLabel[label] = player.UserId
                table.insert(options, label)
            end
        end
        table.sort(options, function(left, right)
            return string.lower(left) < string.lower(right)
        end)
        if #options == 0 then
            table.insert(options, "No other players")
        end
        return options
    end

    local function refreshMonitorDropdown()
        local options = collectMonitorOptions()
        if monitorDropdown then
            pcall(function()
                monitorDropdown:Refresh(options)
            end)
        end
        return options
    end

    local function updateMonitor()
        if not monitorLabel then
            return
        end
        local player = selectedPlayerId and Players:GetPlayerByUserId(selectedPlayerId)
        if not player then
            pcall(function()
                monitorLabel:Set("Selected: none")
            end)
            return
        end
        local _, humanoid, root = context.getCharacterParts(player)
        local _, _, localRoot = context.getCharacterParts(localPlayer)
        local distance = root and localRoot and (root.Position - localRoot.Position).Magnitude or 0
        local record = records.player[player]
        local wallState = record and (record.wallBlocked and "WALL" or "VISIBLE") or "UNKNOWN"
        local team = player.Team and player.Team.Name or "No team"
        local health = humanoid and string.format("%.1f/%.1f", humanoid.Health, humanoid.MaxHealth) or "N/A"
        pcall(function()
            monitorLabel:Set(string.format("%s | HP %s | %.0f studs | %s | %s", context.playerLabel(player), health, distance, team, wallState))
        end)
    end

    local function getPing()
        local ok, value = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValueString()
        end)
        return ok and value or "N/A"
    end

    local function getMcpStatus()
        local ok, environment = pcall(function()
            return getgenv()
        end)
        if ok and environment and environment.BridgeURL then
            local state = environment.RavenMCPStatus or "configured"
            return tostring(state) .. " @ " .. tostring(environment.BridgeURL)
        end
        return "not detected"
    end

    local function countOccluded()
        local count = 0
        for _, categoryRecords in pairs(records) do
            for _, record in pairs(categoryRecords) do
                if record.wallBlocked then
                    count += 1
                end
            end
        end
        return count
    end

    local function updateDiagnostics()
        if not debugLabel or not settings.debugEnabled then
            return
        end
        pcall(function()
            debugLabel:Set(string.format(
                "FPS %d | Ping %s | P %d W %d L %d | Behind wall %d | MCP %s",
                fps,
                getPing(),
                context.countRecords("player"),
                context.countRecords("walker"),
                context.countRecords("loot"),
                countOccluded(),
                getMcpStatus()
            ))
        end)
    end

    local function applyPreset(name)
        if name == "Low" then
            settings.visualFps = 10
            settings.maxWalkers = 20
            settings.maxLoot = 20
            settings.skeletonESP = false
            settings.adaptiveDistance = true
            settings.detailDistance = 350
            settings.wallCheckInterval = 0.35
        elseif name == "Ultra" then
            settings.visualFps = 30
            settings.maxWalkers = 80
            settings.maxLoot = 80
            settings.adaptiveDistance = false
            settings.detailDistance = 1500
            settings.wallCheckInterval = 0.1
        else
            name = "Balanced"
            settings.visualFps = 20
            settings.maxWalkers = 40
            settings.maxLoot = 40
            settings.adaptiveDistance = true
            settings.detailDistance = 700
            settings.wallCheckInterval = 0.2
        end
        pcall(function()
            presetLabel:Set("Active preset: " .. name)
        end)
        context.notify("Performance", name .. " preset applied")
    end

    local function panicClear()
        settings.playerEnabled = false
        settings.walkerEnabled = false
        settings.lootEnabled = false
        settings.radarEnabled = false
        settings.boxESP = false
        settings.tracerESP = false
        settings.skeletonESP = false
        settings.proximityAlerts = false
        settings.monitorActive = false
        radar.Visible = false
        context.clearAllVisuals()
        local overlayRecords = {}
        for record in pairs(overlays) do
            table.insert(overlayRecords, record)
        end
        for _, record in ipairs(overlayRecords) do
            destroyOverlay(record)
        end
        for marker in pairs(deathMarkers) do
            if marker.Parent then
                marker:Destroy()
            end
            deathMarkers[marker] = nil
        end
        context.notify("PANIC", "All TWDO3 ESP visuals cleared")
    end

    local AwarenessTab = Window:CreateTab("Awareness", 4483362458)
    AwarenessTab:CreateSection("Radar")
    AwarenessTab:CreateToggle({
        Name = "2D Radar",
        CurrentValue = false,
        Flag = "TWDO3RadarEnabled",
        Callback = function(value)
            settings.radarEnabled = value
            radar.Visible = value
        end,
    })
    AwarenessTab:CreateSlider({
        Name = "Radar Range",
        Range = {100, 1500},
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 500,
        Flag = "TWDO3RadarRange",
        Callback = function(value)
            settings.radarRange = value
        end,
    })

    AwarenessTab:CreateSection("Screen Overlay")
    AwarenessTab:CreateToggle({
        Name = "Box ESP",
        CurrentValue = false,
        Flag = "TWDO3BoxESP",
        Callback = function(value)
            settings.boxESP = value
        end,
    })
    AwarenessTab:CreateToggle({
        Name = "Tracer ESP",
        CurrentValue = false,
        Flag = "TWDO3TracerESP",
        Callback = function(value)
            settings.tracerESP = value
        end,
    })
    AwarenessTab:CreateToggle({
        Name = "Skeleton ESP",
        CurrentValue = false,
        Flag = "TWDO3SkeletonESP",
        Callback = function(value)
            settings.skeletonESP = value
        end,
    })

    AwarenessTab:CreateSection("Walls / Threat")
    AwarenessTab:CreateToggle({
        Name = "Check Behind Walls",
        CurrentValue = true,
        Flag = "TWDO3WallCheck",
        Callback = function(value)
            settings.wallCheckEnabled = value
        end,
    })
    AwarenessTab:CreateToggle({
        Name = "Hide Targets Behind Walls",
        CurrentValue = false,
        Flag = "TWDO3HideBehindWalls",
        Callback = function(value)
            settings.hideBehindWalls = value
        end,
    })
    AwarenessTab:CreateToggle({
        Name = "Threat Colors",
        CurrentValue = true,
        Flag = "TWDO3ThreatColors",
        Callback = function(value)
            settings.threatColors = value
        end,
    })
    AwarenessTab:CreateSlider({
        Name = "Red Threat Distance",
        Range = {20, 300},
        Increment = 10,
        Suffix = " studs",
        CurrentValue = 80,
        Flag = "TWDO3ThreatNear",
        Callback = function(value)
            settings.threatNearDistance = value
        end,
    })
    AwarenessTab:CreateSlider({
        Name = "Orange Threat Distance",
        Range = {50, 600},
        Increment = 10,
        Suffix = " studs",
        CurrentValue = 200,
        Flag = "TWDO3ThreatMedium",
        Callback = function(value)
            settings.threatMediumDistance = value
        end,
    })

    AwarenessTab:CreateSection("Alerts / Death")
    AwarenessTab:CreateToggle({
        Name = "Proximity Alerts",
        CurrentValue = false,
        Flag = "TWDO3ProximityAlerts",
        Callback = function(value)
            settings.proximityAlerts = value
        end,
    })
    AwarenessTab:CreateSlider({
        Name = "Player Alert Distance",
        Range = {50, 1000},
        Increment = 25,
        Suffix = " studs",
        CurrentValue = 250,
        Flag = "TWDO3PlayerAlertDistance",
        Callback = function(value)
            settings.playerAlertDistance = value
        end,
    })
    AwarenessTab:CreateSlider({
        Name = "Walker Alert Distance",
        Range = {20, 400},
        Increment = 10,
        Suffix = " studs",
        CurrentValue = 100,
        Flag = "TWDO3WalkerAlertDistance",
        Callback = function(value)
            settings.walkerAlertDistance = value
        end,
    })
    AwarenessTab:CreateToggle({
        Name = "Death Markers",
        CurrentValue = true,
        Flag = "TWDO3DeathMarkers",
        Callback = function(value)
            settings.deathMarkers = value
        end,
    })
    AwarenessTab:CreateSlider({
        Name = "Death Marker Duration",
        Range = {5, 60},
        Increment = 5,
        Suffix = " sec",
        CurrentValue = 20,
        Flag = "TWDO3DeathMarkerDuration",
        Callback = function(value)
            settings.deathMarkerDuration = value
        end,
    })

    AwarenessTab:CreateSection("Player Monitor")
    local initialMonitorOptions = collectMonitorOptions()
    monitorDropdown = AwarenessTab:CreateDropdown({
        Name = "Monitor Player",
        Options = initialMonitorOptions,
        CurrentOption = {initialMonitorOptions[1]},
        MultipleOptions = false,
        Flag = "TWDO3MonitorPlayer",
        Callback = function(value)
            selectedPlayerId = playerByMonitorLabel[getDropdownValue(value)]
            settings.monitorActive = selectedPlayerId ~= nil
            updateMonitor()
        end,
    })
    monitorLabel = AwarenessTab:CreateLabel("Selected: none")
    AwarenessTab:CreateButton({
        Name = "Refresh Monitor List",
        Callback = function()
            refreshMonitorDropdown()
            updateMonitor()
        end,
    })
    AwarenessTab:CreateButton({
        Name = "Spectate Monitored Player",
        Callback = function()
            local player = selectedPlayerId and Players:GetPlayerByUserId(selectedPlayerId)
            context.spectatePlayer(player)
        end,
    })

    local ToolsTab = Window:CreateTab("ESP Tools", 4483362458)
    ToolsTab:CreateSection("Loot Search / Rarity")
    pcall(function()
        ToolsTab:CreateInput({
            Name = "Loot Name Search",
            CurrentValue = "",
            PlaceholderText = "ammo, military, fridge...",
            RemoveTextAfterFocusLost = false,
            Flag = "TWDO3LootSearch",
            Callback = function(value)
                settings.lootSearch = tostring(value or "")
            end,
        })
    end)
    ToolsTab:CreateDropdown({
        Name = "Minimum Loot Rarity",
        Options = {"Common", "Uncommon", "Rare", "Legendary"},
        CurrentOption = {"Common"},
        MultipleOptions = false,
        Flag = "TWDO3LootMinimumRarity",
        Callback = function(value)
            local ranks = {Common = 1, Uncommon = 2, Rare = 3, Legendary = 4}
            settings.lootMinimumRarity = ranks[getDropdownValue(value)] or 1
        end,
    })

    ToolsTab:CreateSection("Adaptive Performance")
    presetLabel = ToolsTab:CreateLabel("Active preset: Balanced")
    ToolsTab:CreateDropdown({
        Name = "Performance Preset",
        Options = {"Low", "Balanced", "Ultra"},
        CurrentOption = {"Balanced"},
        MultipleOptions = false,
        Flag = "TWDO3PerformancePreset",
        Callback = function(value)
            applyPreset(getDropdownValue(value))
        end,
    })
    ToolsTab:CreateToggle({
        Name = "Adaptive Distance Detail",
        CurrentValue = true,
        Flag = "TWDO3AdaptiveDistance",
        Callback = function(value)
            settings.adaptiveDistance = value
        end,
    })
    ToolsTab:CreateSlider({
        Name = "Full Detail Distance",
        Range = {100, 2000},
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 700,
        Flag = "TWDO3DetailDistance",
        Callback = function(value)
            settings.detailDistance = value
        end,
    })
    ToolsTab:CreateLabel("All controls with a Flag are auto-saved in RAVENHUB/HubConfig")

    ToolsTab:CreateSection("Diagnostics / Safety")
    debugLabel = ToolsTab:CreateLabel("Diagnostics starting...")
    ToolsTab:CreateToggle({
        Name = "Debug Panel Updates",
        CurrentValue = true,
        Flag = "TWDO3DebugEnabled",
        Callback = function(value)
            settings.debugEnabled = value
            if not value then
                pcall(function()
                    debugLabel:Set("Diagnostics paused")
                end)
            end
        end,
    })
    ToolsTab:CreateButton({
        Name = "PANIC: Clear All ESP",
        Callback = panicClear,
    })
    ToolsTab:CreateKeybind({
        Name = "Panic Key",
        CurrentKeybind = "End",
        HoldToInteract = false,
        Flag = "TWDO3PanicKey",
        Callback = panicClear,
    })

    local controller = {}

    function controller:OnRecordCreated(record)
        if scriptRunning then
            createOverlay(record)
        end
    end

    function controller:OnRecordRemoved(record)
        destroyOverlay(record)
    end

    function controller:OnDeath(record)
        if not settings.deathMarkers or record.category == "loot" then
            return
        end
        local position = record.root and record.root.Position or context.safePosition(record.target, record.root)
        if not position then
            return
        end
        local marker = Instance.new("Part")
        marker.Name = "DeathMarker"
        marker.Anchored = true
        marker.CanCollide = false
        marker.CanQuery = false
        marker.CanTouch = false
        marker.Material = Enum.Material.Neon
        marker.Shape = Enum.PartType.Ball
        marker.Size = Vector3.new(0.5, 0.5, 0.5)
        marker.Color = record.category == "player" and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 150, 45)
        marker.Position = position
        marker.Parent = espFolder
        deathMarkers[marker] = true

        local tag = Instance.new("BillboardGui")
        tag.AlwaysOnTop = true
        tag.Size = UDim2.fromOffset(180, 36)
        tag.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
        tag.Adornee = marker
        tag.Parent = marker
        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.Size = UDim2.fromScale(1, 1)
        text.Font = Enum.Font.GothamBold
        text.TextColor3 = marker.Color
        text.TextStrokeTransparency = 0.15
        text.TextSize = 12
        text.Text = string.format("DEATH: %s", record.label or record.category)
        text.Parent = tag

        task.delay(settings.deathMarkerDuration, function()
            deathMarkers[marker] = nil
        end)
        Debris:AddItem(marker, settings.deathMarkerDuration)
    end

    function controller:Destroy()
        if not scriptRunning then
            return
        end
        scriptRunning = false
        for _, connection in ipairs(connections) do
            disconnect(connection)
        end
        table.clear(connections)
        for record in pairs(overlays) do
            destroyOverlay(record)
        end
        for marker in pairs(deathMarkers) do
            if marker.Parent then
                marker:Destroy()
            end
        end
        table.clear(deathMarkers)
        screenGui:Destroy()
    end

    for _, categoryRecords in pairs(records) do
        for _, record in pairs(categoryRecords) do
            controller:OnRecordCreated(record)
        end
    end

    table.insert(connections, Players.PlayerAdded:Connect(function()
        task.defer(refreshMonitorDropdown)
    end))
    table.insert(connections, Players.PlayerRemoving:Connect(function(player)
        if selectedPlayerId == player.UserId then
            selectedPlayerId = nil
        end
        task.defer(refreshMonitorDropdown)
    end))
    table.insert(connections, RunService.RenderStepped:Connect(function(deltaTime)
        if not scriptRunning then
            return
        end
        frameCount += 1
        visualAccumulator += deltaTime
        diagnosticAccumulator += deltaTime
        monitorAccumulator += deltaTime
        local now = os.clock()
        if now - lastFpsClock >= 1 then
            fps = math.round(frameCount / (now - lastFpsClock))
            frameCount = 0
            lastFpsClock = now
        end
        if visualAccumulator >= 1 / math.max(settings.visualFps, 1) then
            visualAccumulator = 0
            local camera = workspace.CurrentCamera
            local _, _, localRoot = context.getCharacterParts(localPlayer)
            local localPosition = localRoot and localRoot.Position
            radar.Visible = settings.radarEnabled
            if camera then
                for _, categoryRecords in pairs(records) do
                    for _, record in pairs(categoryRecords) do
                        updateRecordOverlay(record, camera, localPosition)
                    end
                end
            end
        end
        if diagnosticAccumulator >= 1 then
            diagnosticAccumulator = 0
            updateDiagnostics()
        end
        if monitorAccumulator >= 0.5 then
            monitorAccumulator = 0
            updateMonitor()
        end
    end))

    return controller
end
