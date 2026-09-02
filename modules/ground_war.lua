--[[
    RAVEN HUB Module - Ground War (o)
    Game: Ground War (o) (PlaceId: 76822114837453, GameId: 6583326485)
    Developer: Stealth Developers

    Features:
    - Player and AIBot ESP with distance and bounded visibility sampling
    - Team-aware target resolution for Players and workspace.Bots models
    - Weapon-aware ballistic aim prediction with movement lead and drop
    - Optional smooth auto aim with FOV, sticky target, and visible-part modes
    - Tactical radar, match statistics dashboard, fullbright, no fog, and FOV

    Module format: returns function(Window, runtimeInfo) for RAVENHUB loader.
    The module only changes local presentation/camera state and never invokes
    game remotes.
]]

return function(Window, runtimeInfo)
    pcall(function()
        local previous = getgenv().__RAVEN_GROUND_WAR
        if previous and type(previous.Destroy) == "function" then
            previous.Destroy()
        end
    end)

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local UserInputService = game:GetService("UserInputService")
    local CollectionService = game:GetService("CollectionService")
    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    local State = {
        ESP = false,
        ESPNames = true,
        ESPDistance = true,
        ESPWallCheck = true,
        MaxDistance = 2000,
        TargetBots = true,
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 90,
        AimPrediction = false,
        PredictTargetPart = "Head",
        PredictDotSize = 6,
        AutoAim = false,
        AimActivation = "Right Mouse",
        AimFOV = 180,
        AimSmoothness = 0.18,
        AdaptiveSmoothness = true,
        AimSwayCompensation = true,
        AimVisibleCheck = true,
        AimPartMode = "Auto Visible",
        StickyTarget = true,
        Radar = false,
        RadarRange = 700,
        RadarSize = 150,
        AimInputActive = false,
        AimEngaged = false,
        AimLockedTarget = nil,
        AimLockedPart = nil,
    }

    local Connections = {}
    local ESPObjects = {}
    local visibilityCache = {}
    local predictionCache = {}
    local targetPositions = {}
    local targetTimes = {}
    local targetVelocities = {}
    local radarBlips = {}
    local lockedTarget = nil
    local rightMouseDown = false
    local visibilityFrame = 0
    local predictionFrame = 0
    local rayFilterFrame = -1
    local destroyed = false

    local OriginalLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        GlobalShadows = Lighting.GlobalShadows,
    }
    local OriginalFOV = Camera.FieldOfView
    local OriginalAtmospheres = {}
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Atmosphere") then
            OriginalAtmospheres[child] = {
                Density = child.Density,
                Haze = child.Haze,
                Glare = child.Glare,
                Offset = child.Offset,
            }
        end
    end

    local function safeDrawing(className)
        if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
            return nil
        end
        local ok, object = pcall(Drawing.new, className)
        return ok and object or nil
    end

    local function removeDrawing(object)
        if object then pcall(function() object:Remove() end) end
    end

    local function getModel(source)
        if not source then return nil end
        if source:IsA("Model") then return source end
        if source:IsA("Player") then
            return workspace:FindFirstChild(source.Name) or source.Character
        end
        return nil
    end

    local function getCharacter(source)
        return getModel(source)
    end

    local function getRoot(source)
        local model = getCharacter(source)
        if not model then return nil end
        return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    end

    local function getMyRoot()
        return getRoot(LP)
    end

    local function getHumanoid(source)
        local model = getCharacter(source)
        return model and model:FindFirstChildOfClass("Humanoid") or nil
    end

    local function normalizedTeam(value)
        if value == nil then return nil end
        local text = string.lower(tostring(value))
        text = text:gsub("[%s_%-]", "")
        return text ~= "" and text or nil
    end

    local function getTeamValue(source)
        if not source then return nil end
        local model = getCharacter(source)
        local value = source:GetAttribute("MG_Team")
        if value == nil then value = source:GetAttribute("Team") end
        if value == nil and model then value = model:GetAttribute("MG_Team") end
        if value == nil and model then value = model:GetAttribute("Team") end
        if value == nil and source:IsA("Player") and source.Team then
            value = source.Team.Name
        end
        return value
    end

    local function localTeam()
        return normalizedTeam(getTeamValue(LP))
    end

    local function isNeutralTeam(value)
        local team = normalizedTeam(value)
        return team == "neutral" or team == "none"
    end

    local function getTargetEntries()
        local entries = {}
        local seen = {}

        local function add(source, isBot)
            local model = getCharacter(source)
            if not model or seen[model] then return end
            if not model:FindFirstChildOfClass("Humanoid") then return end
            seen[model] = true
            local player = source:IsA("Player") and source or nil
            table.insert(entries, {
                key = model,
                player = player,
                character = model,
                isBot = isBot == true,
                name = player and (player.DisplayName or player.Name) or model.Name,
            })
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP then add(player, false) end
        end

        local bots = workspace:FindFirstChild("Bots")
        if State.TargetBots and bots then
            local tagged = {}
            pcall(function() tagged = CollectionService:GetTagged("AIBot") end)
            for _, bot in ipairs(tagged) do
                if bot:IsA("Model") and bot:IsDescendantOf(bots) then
                    add(bot, true)
                end
            end
            for _, bot in ipairs(bots:GetChildren()) do
                if bot:IsA("Model") then add(bot, true) end
            end
        end

        return entries
    end

    local function isEnemy(entry)
        if not entry or not entry.character then return false end
        local mine = localTeam()
        local theirs = normalizedTeam(getTeamValue(entry.character))
        if not theirs then theirs = normalizedTeam(getTeamValue(entry.player)) end
        if isNeutralTeam(theirs) then return false end
        if mine and theirs then return mine ~= theirs end
        return entry.isBot == true
    end

    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude
    local MAX_VISION_PASSTHROUGHS = 10
    local VISIBILITY_PARTS = {
        "Head", "UpperTorso", "LowerTorso", "Torso", "HumanoidRootPart",
        "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
        "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg",
        "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot",
        "Left Arm", "Right Arm", "Left Leg", "Right Leg",
    }
    local AUTO_VISIBLE_PARTS_PER_SCAN = 4
    local AUTO_VISIBLE_SCAN_INTERVAL = 2
    local AUTO_VISIBLE_SAMPLE_SCALE = 0.45
    local AIM_PREFILTER_MARGIN = 80
    local COLOR_VISIBLE = Color3.fromRGB(255, 65, 65)
    local COLOR_HIDDEN = Color3.fromRGB(80, 220, 120)
    local COLOR_TEXT_VISIBLE = Color3.fromRGB(255, 90, 90)
    local COLOR_TEXT_HIDDEN = Color3.fromRGB(120, 255, 150)

    local function buildRayFilter()
        if rayFilterFrame == visibilityFrame then return end
        local ignored = {}
        local ownCharacter = getCharacter(LP)
        if ownCharacter then table.insert(ignored, ownCharacter) end
        local viewmodel = workspace:FindFirstChild("Camera")
        if viewmodel then table.insert(ignored, viewmodel) end
        for _, name in ipairs({"Ignore", "Effects", "Debris", "CosmeticShellsFolder"}) do
            local folder = workspace:FindFirstChild(name)
            if folder then table.insert(ignored, folder) end
        end
        RayParams.FilterDescendantsInstances = ignored
        rayFilterFrame = visibilityFrame
    end

    local function isVisionTransparent(instance)
        return instance:IsA("BasePart") and instance.Transparency >= 0.25
    end

    local function rayReachesTarget(fromPosition, toPosition, targetCharacter, targetPart)
        local direction = toPosition - fromPosition
        local baseIgnored = table.clone(RayParams.FilterDescendantsInstances)
        local ignored = table.clone(baseIgnored)
        local reachesTarget = false
        for _ = 1, MAX_VISION_PASSTHROUGHS do
            RayParams.FilterDescendantsInstances = ignored
            local result = workspace:Raycast(fromPosition, direction, RayParams)
            if not result then
                reachesTarget = true
                break
            end
            if result.Instance == targetPart
                or (targetCharacter and result.Instance:IsDescendantOf(targetCharacter)) then
                reachesTarget = true
                break
            end
            if not isVisionTransparent(result.Instance) then break end
            table.insert(ignored, result.Instance)
        end
        RayParams.FilterDescendantsInstances = baseIgnored
        return reachesTarget
    end

    local function partOffsets(part, scale)
        local halfX = part.Size.X * scale
        local halfY = part.Size.Y * scale
        return {
            Vector3.zero,
            Vector3.new(halfX, 0, 0),
            Vector3.new(-halfX, 0, 0),
            Vector3.new(0, halfY, 0),
            Vector3.new(0, -halfY, 0),
        }
    end

    local function getAimPartPriority(part)
        local name = part.Name
        if name == "Head" then return 1 end
        if string.find(name, "Torso", 1, true) then return 2 end
        if string.find(name, "Arm", 1, true) or string.find(name, "Hand", 1, true) then return 3 end
        return 4
    end

    local function visiblePartStates(fromPosition, character)
        buildRayFilter()
        local states = {}
        local anyVisible = false
        for _, partName in ipairs(VISIBILITY_PARTS) do
            local part = character:FindFirstChild(partName)
            if part and part:IsA("BasePart") and not states[part] then
                local offsets = partOffsets(part, 0.42)
                local visible = rayReachesTarget(
                    fromPosition,
                    part.CFrame:PointToWorldSpace(offsets[1]),
                    character,
                    part
                )
                if not visible and offsets[2] then
                    visible = rayReachesTarget(
                        fromPosition,
                        part.CFrame:PointToWorldSpace(offsets[2]),
                        character,
                        part
                    )
                end
                states[part] = {visible = visible}
                anyVisible = anyVisible or visible
            end
        end
        return anyVisible, states
    end

    local function scanAutoVisibleParts(fromPosition, character, parts, cached)
        buildRayFilter()
        cached.parts = cached.parts or {}
        if cached.lastAutoVisibleScan
            and visibilityFrame - cached.lastAutoVisibleScan < AUTO_VISIBLE_SCAN_INTERVAL then
            return cached.visible or false, cached.parts, cached.priorityPart
        end
        cached.lastAutoVisibleScan = visibilityFrame
        local scanCount = math.min(AUTO_VISIBLE_PARTS_PER_SCAN, #parts)
        local index = math.clamp(cached.autoVisiblePartIndex or 1, 1, #parts)
        for _ = 1, scanCount do
            local part = parts[index]
            local offsets = partOffsets(part, AUTO_VISIBLE_SAMPLE_SCALE)
            local visible = rayReachesTarget(
                fromPosition,
                part.CFrame:PointToWorldSpace(offsets[1]),
                character,
                part
            )
            if not visible and offsets[2] then
                visible = rayReachesTarget(
                    fromPosition,
                    part.CFrame:PointToWorldSpace(offsets[2]),
                    character,
                    part
                )
            end
            cached.parts[part] = {visible = visible}
            index = index % #parts + 1
        end
        cached.autoVisiblePartIndex = index

        local center = Camera.ViewportSize * 0.5
        local priorityPart, priorityDistance = nil, math.huge
        local anyVisible = false
        for rank = 1, 4 do
            for _, part in ipairs(parts) do
                local state = cached.parts[part]
                if state and state.visible then
                    anyVisible = true
                    if getAimPartPriority(part) == rank then
                        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
                        if onScreen and point.Z > 0 then
                            local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
                            if distance < priorityDistance then
                                priorityPart, priorityDistance = part, distance
                            end
                        end
                    end
                end
            end
            if priorityPart then break end
        end
        cached.visible = anyVisible
        cached.priorityPart = priorityPart
        visibilityCache[character] = cached
        return anyVisible, cached.parts, priorityPart
    end

    local function isCharacterVisible(fromPosition, targetCharacter, autoVisibleRequest)
        if not targetCharacter then return false, {} end
        local cached = visibilityCache[targetCharacter]
        if cached and cached.frame == visibilityFrame then
            return cached.visible, cached.parts, cached.priorityPart
        end

        local parts = {}
        for _, partName in ipairs(VISIBILITY_PARTS) do
            local part = targetCharacter:FindFirstChild(partName)
            if part and part:IsA("BasePart") then table.insert(parts, part) end
        end
        if #parts == 0 then return false, {} end
        cached = cached or {parts = {}}
        local autoVisibleActive = autoVisibleRequest == true and State.AutoAim
            and State.AimPartMode == "Auto Visible"
            and (State.AimActivation == "Always" or rightMouseDown)
        if autoVisibleActive then
            local visible, states, priority = scanAutoVisibleParts(
                fromPosition, targetCharacter, parts, cached
            )
            cached.frame = visibilityFrame
            return visible, states, priority
        end
        local visible, states = visiblePartStates(fromPosition, targetCharacter)
        cached.visible = visible
        cached.parts = states
        cached.frame = visibilityFrame
        visibilityCache[targetCharacter] = cached
        return visible, states, nil
    end

    local espFolder = Instance.new("Folder")
    espFolder.Name = "GroundWar_ESP"
    espFolder.Parent = game:GetService("CoreGui")

    local function createESP(entry)
        if ESPObjects[entry.key] then return ESPObjects[entry.key] end
        local highlight = Instance.new("Highlight")
        highlight.FillColor = COLOR_VISIBLE
        highlight.FillTransparency = 0.65
        highlight.OutlineColor = COLOR_VISIBLE
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Enabled = false
        highlight.Parent = espFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 190, 0, 46)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false
        billboard.Parent = espFolder

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = COLOR_TEXT_VISIBLE
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = entry.name
        nameLabel.Parent = billboard

        local distLabel = Instance.new("TextLabel")
        distLabel.Size = UDim2.new(1, 0, 0.45, 0)
        distLabel.Position = UDim2.new(0, 0, 0.55, 0)
        distLabel.BackgroundTransparency = 1
        distLabel.TextColor3 = Color3.fromRGB(255, 210, 210)
        distLabel.TextStrokeTransparency = 0.2
        distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        distLabel.TextScaled = true
        distLabel.Font = Enum.Font.Gotham
        distLabel.Parent = billboard

        local object = {
            highlight = highlight,
            billboard = billboard,
            nameLabel = nameLabel,
            distLabel = distLabel,
            partBoxes = {},
        }
        ESPObjects[entry.key] = object
        return object
    end

    local function hidePartBoxes(esp)
        for _, box in pairs(esp.partBoxes) do box.Visible = false end
    end

    local function updatePartBoxes(esp, character, states)
        local active = {}
        for part, state in pairs(states or {}) do
            if part.Parent and part:IsDescendantOf(character) then
                local box = esp.partBoxes[part]
                if not box then
                    box = Instance.new("BoxHandleAdornment")
                    box.Name = "GroundWarVisibility"
                    box.AlwaysOnTop = true
                    box.ZIndex = 5
                    box.Transparency = 0.72
                    box.Adornee = part
                    box.Parent = espFolder
                    esp.partBoxes[part] = box
                end
                box.Size = part.Size + Vector3.new(0.04, 0.04, 0.04)
                box.Color3 = state.visible and COLOR_VISIBLE or COLOR_HIDDEN
                box.Visible = true
                active[part] = true
            end
        end
        for part, box in pairs(esp.partBoxes) do
            if not active[part] then
                box.Visible = false
                if not part.Parent then
                    box:Destroy()
                    esp.partBoxes[part] = nil
                end
            end
        end
    end

    local function removeESP(key)
        local esp = ESPObjects[key]
        if not esp then return end
        for _, box in pairs(esp.partBoxes) do box:Destroy() end
        esp.highlight:Destroy()
        esp.billboard:Destroy()
        ESPObjects[key] = nil
    end

    local function clearAllESP()
        for key in pairs(ESPObjects) do removeESP(key) end
    end

    local function updateESP()
        if not State.ESP then
            for _, esp in pairs(ESPObjects) do
                esp.highlight.Enabled = false
                esp.billboard.Enabled = false
                hidePartBoxes(esp)
            end
            return
        end

        local myRoot = getMyRoot()
        local active = {}
        for _, entry in ipairs(getTargetEntries()) do
            if isEnemy(entry) then
                local root = getRoot(entry.character)
                local humanoid = getHumanoid(entry.character)
                if root and humanoid and humanoid.Health > 0 then
                    local distance = myRoot and (myRoot.Position - root.Position).Magnitude or 0
                    local esp = createESP(entry)
                    active[entry.key] = true
                    if distance <= State.MaxDistance then
                        esp.billboard.Adornee = root
                        esp.billboard.Enabled = true
                        esp.nameLabel.Text = entry.name
                        esp.nameLabel.Visible = State.ESPNames
                        esp.distLabel.Visible = State.ESPDistance
                        if State.ESPDistance then
                            esp.distLabel.Text = string.format("[%dm]", math.floor(distance))
                        end
                        if State.ESPWallCheck and myRoot then
                            local visible, states = isCharacterVisible(
                                Camera.CFrame.Position, entry.character, false
                            )
                            updatePartBoxes(esp, entry.character, states)
                            esp.highlight.Enabled = false
                            esp.nameLabel.TextColor3 = visible and COLOR_TEXT_VISIBLE or COLOR_TEXT_HIDDEN
                        else
                            hidePartBoxes(esp)
                            esp.highlight.Adornee = entry.character
                            esp.highlight.Enabled = true
                            esp.highlight.FillColor = COLOR_VISIBLE
                            esp.highlight.OutlineColor = COLOR_VISIBLE
                            esp.nameLabel.TextColor3 = COLOR_TEXT_VISIBLE
                        end
                    else
                        esp.highlight.Enabled = false
                        esp.billboard.Enabled = false
                        hidePartBoxes(esp)
                    end
                end
            end
        end
        for key, esp in pairs(ESPObjects) do
            if not active[key] then
                esp.highlight.Enabled = false
                esp.billboard.Enabled = false
                hidePartBoxes(esp)
                if not key.Parent then removeESP(key) end
            end
        end
    end

    local function applyFullbright(enabled)
        if enabled then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(178, 178, 178)
            Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
        else
            Lighting.Brightness = OriginalLighting.Brightness
            Lighting.ClockTime = OriginalLighting.ClockTime
            Lighting.GlobalShadows = OriginalLighting.GlobalShadows
            Lighting.Ambient = OriginalLighting.Ambient
            Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
        end
    end

    local function applyNoFog(enabled)
        if enabled then
            Lighting.FogStart = 1000000
            Lighting.FogEnd = 1000000
            for atmosphere in pairs(OriginalAtmospheres) do atmosphere.Density = 0 end
        else
            Lighting.FogStart = OriginalLighting.FogStart
            Lighting.FogEnd = OriginalLighting.FogEnd
            for atmosphere, values in pairs(OriginalAtmospheres) do
                if atmosphere.Parent then
                    atmosphere.Density = values.Density
                    atmosphere.Haze = values.Haze
                    atmosphere.Glare = values.Glare
                    atmosphere.Offset = values.Offset
                end
            end
        end
    end

    local function applyFOV(enabled, value)
        Camera.FieldOfView = enabled and value or OriginalFOV
    end

    local function readNumber(source, names, depth)
        if type(source) ~= "table" or (depth or 0) > 3 then return nil end
        for _, name in ipairs(names) do
            if type(source[name]) == "number" then return source[name] end
        end
        for _, child in pairs(source) do
            if type(child) == "table" then
                local value = readNumber(child, names, (depth or 0) + 1)
                if value ~= nil then return value end
            end
        end
        return nil
    end

    local WeaponCache = {}
    local GRAVITY = workspace.Gravity

    local function getWeaponConfig(tool)
        if not tool then return nil end
        if WeaponCache[tool.Name] then return WeaponCache[tool.Name] end
        local config = {
            Name = tool.Name,
            MuzzleVelocity = tool:GetAttribute("MuzzleVelocity")
                or tool:GetAttribute("BulletVelocity")
                or tool:GetAttribute("ProjectileSpeed")
                or 1000,
            Drag = tool:GetAttribute("Drag") or 0,
            Gravity = tool:GetAttribute("Gravity") or GRAVITY,
            Spread = tool:GetAttribute("Spread") or 1,
            ZeroMeters = tool:GetAttribute("ZeroMeters") or 0,
        }
        local settings = tool:FindFirstChild("ACS_Settings")
        if settings and settings:IsA("ModuleScript") then
            local ok, data = pcall(require, settings)
            if ok and type(data) == "table" then
                config.MuzzleVelocity = readNumber(data, {
                    "MuzzleVelocity", "BulletVelocity", "ProjectileSpeed", "MuzzleSpeed", "Velocity",
                }) or config.MuzzleVelocity
                config.Drag = readNumber(data, {"Drag", "BulletDrag"}) or config.Drag
                config.Gravity = readNumber(data, {"Gravity", "BulletGravity"}) or config.Gravity
                config.Spread = readNumber(data, {"Spread", "AccuracySpread"}) or config.Spread
                config.ZeroMeters = readNumber(data, {"ZeroMeters", "ZeroDistance", "ZeroingDistance"})
                    or config.ZeroMeters
            end
        end
        config.MuzzleVelocity = math.max(tonumber(config.MuzzleVelocity) or 1000, 1)
        config.Drag = math.max(tonumber(config.Drag) or 0, 0)
        config.Gravity = math.max(tonumber(config.Gravity) or GRAVITY, 0)
        config.Spread = math.max(tonumber(config.Spread) or 1, 0)
        config.ZeroMeters = math.max(tonumber(config.ZeroMeters) or 0, 0)
        WeaponCache[tool.Name] = config
        return config
    end

    local function getCurrentWeaponConfig()
        local character = getCharacter(LP)
        local backpack = LP:FindFirstChildOfClass("Backpack")
        for _, container in ipairs({character, backpack}) do
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Tool") then
                        local config = getWeaponConfig(child)
                        if config then return config end
                    end
                end
            end
        end
        return nil
    end

    local function getBulletTravelTime(distance, muzzleVelocity, drag)
        distance = math.max(distance or 0, 0)
        muzzleVelocity = math.max(muzzleVelocity or 1, 1)
        drag = math.max(drag or 0, 0)
        if drag <= 0 then return distance / muzzleVelocity end
        local time = distance / muzzleVelocity
        for _ = 1, 4 do
            local endSpeed = muzzleVelocity * math.exp(-drag * time)
            time = distance / math.max((muzzleVelocity + endSpeed) * 0.5, 1)
        end
        return time
    end

    local function getTargetVelocity(entry)
        local root = getRoot(entry and entry.character)
        if not root then return Vector3.zero end
        local now = os.clock()
        local position = root.Position
        local previousPosition = targetPositions[entry.key]
        local previousTime = targetTimes[entry.key]
        targetPositions[entry.key] = position
        targetTimes[entry.key] = now
        if previousPosition and previousTime then
            local deltaTime = now - previousTime
            if deltaTime > 0 and deltaTime < 1 then
                local measured = (position - previousPosition) / deltaTime
                local assembly = root.AssemblyLinearVelocity
                if assembly.Magnitude < 250 then measured = measured:Lerp(assembly, 0.45) end
                local previous = targetVelocities[entry.key] or measured
                local alpha = 1 - math.exp(-deltaTime * 12)
                local smoothed = previous:Lerp(measured, alpha)
                targetVelocities[entry.key] = smoothed
                return smoothed
            end
        end
        return targetVelocities[entry.key] or Vector3.zero
    end

    local function getPredictedPosition(targetPosition, targetVelocity, weaponConfig, shooterPosition)
        if not weaponConfig then return targetPosition, 0 end
        local travelTime = 0
        local leadOffset = Vector3.zero
        for _ = 1, 3 do
            leadOffset = targetVelocity * travelTime
            local future = targetPosition + leadOffset - shooterPosition
            local horizontalDistance = Vector3.new(future.X, 0, future.Z).Magnitude
            travelTime = getBulletTravelTime(
                horizontalDistance,
                weaponConfig.MuzzleVelocity,
                weaponConfig.Drag
            )
        end
        leadOffset = targetVelocity * travelTime
        local zeroDistance = weaponConfig.ZeroMeters * 3.57
        local zeroTime = zeroDistance > 0 and getBulletTravelTime(
            zeroDistance,
            weaponConfig.MuzzleVelocity,
            weaponConfig.Drag
        ) or 0
        local drop = 0.5 * weaponConfig.Gravity * (travelTime * travelTime - zeroTime * zeroTime)
        return targetPosition + leadOffset + Vector3.new(0, drop, 0), travelTime
    end

    local function getSharedPrediction(entry, weaponConfig, selectedPart)
        if not entry or not weaponConfig then return nil end
        local character = entry.character
        local targetPart = selectedPart or (character and (
            character:FindFirstChild(State.PredictTargetPart)
            or character:FindFirstChild("Head")
            or character:FindFirstChild("HumanoidRootPart")
        ))
        if not targetPart then return nil end
        local cached = predictionCache[entry.key]
        if cached and cached.frame == predictionFrame
            and cached.part == targetPart and cached.weapon == weaponConfig.Name then
            return cached
        end
        local predicted, travelTime = getPredictedPosition(
            targetPart.Position,
            getTargetVelocity(entry),
            weaponConfig,
            Camera.CFrame.Position
        )
        cached = {
            frame = predictionFrame,
            part = targetPart,
            weapon = weaponConfig.Name,
            position = predicted,
            travelTime = travelTime,
        }
        predictionCache[entry.key] = cached
        return cached
    end

    local function getReferencePart(entry)
        local character = entry and entry.character
        return character and (
            character:FindFirstChild("Head")
            or character:FindFirstChild("UpperTorso")
            or character:FindFirstChild("Torso")
            or character:FindFirstChild("HumanoidRootPart")
        ) or nil
    end

    local resolveAimPart

    resolveAimPart = function(entry, requireVisible)
        local character = entry and entry.character
        if not character then return nil end
        local preferred = character:FindFirstChild(State.PredictTargetPart)
            or character:FindFirstChild("Head")
            or character:FindFirstChild("HumanoidRootPart")
        if not requireVisible then return preferred end
        local _, states, priorityPart = isCharacterVisible(
            Camera.CFrame.Position,
            character,
            true
        )
        local function visible(part)
            local state = part and states and states[part]
            return part and part:IsA("BasePart") and state and state.visible
        end
        if State.AimPartMode == "Selected Only" then
            return visible(preferred) and preferred or nil
        end
        if State.AimPartMode == "Auto Visible" and visible(priorityPart) then
            return priorityPart
        end
        local candidates = {
            preferred,
            character:FindFirstChild("Head"),
            character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"),
            character:FindFirstChild("LowerTorso"),
            character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm"),
            character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm"),
            character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg"),
            character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("Right Leg"),
        }
        local center = Camera.ViewportSize * 0.5
        local best, bestDistance = nil, math.huge
        local seen = {}
        for _, part in ipairs(candidates) do
            if part and not seen[part] and visible(part) then
                seen[part] = true
                local point, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and point.Z > 0 then
                    local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
                    if distance < bestDistance then best, bestDistance = part, distance end
                end
            end
        end
        return best
    end

    local function getClosestEnemyToCrosshair(maxPixels, requireVisible)
        local closest, closestDistance = nil, math.huge
        local center = Camera.ViewportSize * 0.5
        for _, entry in ipairs(getTargetEntries()) do
            if isEnemy(entry) then
                local humanoid = getHumanoid(entry.character)
                local referencePart = getReferencePart(entry)
                if humanoid and humanoid.Health > 0 and referencePart then
                    local point, onScreen = Camera:WorldToViewportPoint(referencePart.Position)
                    if onScreen and point.Z > 0 then
                        local referenceDistance = (Vector2.new(point.X, point.Y) - center).Magnitude
                        if not maxPixels or referenceDistance <= maxPixels + AIM_PREFILTER_MARGIN then
                            local part = resolveAimPart(entry, requireVisible)
                            if part then
                                local targetPoint, targetOnScreen = Camera:WorldToViewportPoint(part.Position)
                                if targetOnScreen and targetPoint.Z > 0 then
                                    local distance = (Vector2.new(targetPoint.X, targetPoint.Y) - center).Magnitude
                                    if (not maxPixels or distance <= maxPixels) and distance < closestDistance then
                                        closest, closestDistance = entry, distance
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        return closest
    end

    local function aimActive()
        if not State.AutoAim then return false end
        if State.AimActivation == "Always" then return true end
        local ok, held = pcall(function()
            return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end)
        return rightMouseDown and ok and held == true
    end

    local function aimResponse(screenError)
        local response = math.max(1, State.AimSmoothness * 60)
        if State.AdaptiveSmoothness then
            local normalized = math.clamp((screenError or 0) / math.max(State.AimFOV, 1), 0, 1)
            response *= 1 + normalized * 2.5
        end
        return response
    end

    local function validAimTarget(entry)
        if not entry or not isEnemy(entry) then return false end
        local part = resolveAimPart(entry, State.AimVisibleCheck)
        if not part then return false end
        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then return false end
        return (Vector2.new(point.X, point.Y) - Camera.ViewportSize * 0.5).Magnitude <= State.AimFOV
    end

    local function updateAutoAim(dt)
        local active = aimActive()
        State.AimInputActive = active
        State.AimEngaged = false
        State.AimLockedTarget = nil
        State.AimLockedPart = nil
        if not active then lockedTarget = nil return end
        if not State.StickyTarget or not validAimTarget(lockedTarget) then
            lockedTarget = getClosestEnemyToCrosshair(State.AimFOV, State.AimVisibleCheck)
        end
        if not lockedTarget then return end
        local part = resolveAimPart(lockedTarget, State.AimVisibleCheck)
        local weaponConfig = getCurrentWeaponConfig()
        if not part or not weaponConfig then return end
        local sample = getSharedPrediction(lockedTarget, weaponConfig, part)
        if not sample then return end
        local point, onScreen = Camera:WorldToViewportPoint(sample.position)
        if not onScreen or point.Z <= 0 then return end
        local desired = CFrame.lookAt(Camera.CFrame.Position, sample.position, Camera.CFrame.UpVector)
        local center = Camera.ViewportSize * 0.5
        local error = (Vector2.new(point.X, point.Y) - center).Magnitude
        local alpha = 1 - math.exp(-aimResponse(error) * math.max(dt or 1 / 60, 1 / 240))
        if State.AimSwayCompensation then
            Camera.CFrame = Camera.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))
        elseif type(mousemoverel) == "function" then
            pcall(mousemoverel, (point.X - center.X) * State.AimSmoothness, (point.Y - center.Y) * State.AimSmoothness)
        else
            Camera.CFrame = Camera.CFrame:Lerp(desired, math.clamp(State.AimSmoothness, 0, 1))
        end
        State.AimEngaged = true
        State.AimLockedTarget = lockedTarget.name
        State.AimLockedPart = part.Name
    end

    local predictionDot = nil
    local predictionCircle = nil
    local predictionText = nil

    local function createPredictionDot()
        if predictionDot then return end
        predictionDot = safeDrawing("Circle")
        predictionCircle = safeDrawing("Circle")
        predictionText = safeDrawing("Text")
        if predictionDot then
            predictionDot.Filled = true
            predictionDot.Thickness = 1
            predictionDot.Transparency = 1
        end
        if predictionCircle then
            predictionCircle.Filled = false
            predictionCircle.Thickness = 2
            predictionCircle.Transparency = 1
        end
        if predictionText then
            predictionText.Size = 14
            predictionText.Center = true
            predictionText.Outline = true
            predictionText.OutlineColor = Color3.new(0, 0, 0)
            if Drawing.Fonts then predictionText.Font = Drawing.Fonts.Monospace end
        end
    end

    local function hidePrediction()
        if predictionDot then predictionDot.Visible = false end
        if predictionCircle then predictionCircle.Visible = false end
        if predictionText then predictionText.Visible = false end
    end

    local function destroyPredictionDot()
        removeDrawing(predictionDot)
        removeDrawing(predictionCircle)
        removeDrawing(predictionText)
        predictionDot, predictionCircle, predictionText = nil, nil, nil
    end

    local function updateAimPrediction()
        if not State.AimPrediction then hidePrediction() return end
        createPredictionDot()
        local config = getCurrentWeaponConfig()
        local requireShootable = State.AutoAim and aimActive() and State.AimVisibleCheck
        local entry = lockedTarget
        if not entry or (requireShootable and not validAimTarget(entry)) then
            entry = getClosestEnemyToCrosshair(requireShootable and State.AimFOV or nil, requireShootable)
        end
        if not entry or not config then hidePrediction() return end
        local part = resolveAimPart(entry, requireShootable)
        local sample = part and getSharedPrediction(entry, config, part)
        if not sample then hidePrediction() return end
        local point, onScreen = Camera:WorldToViewportPoint(sample.position)
        if not onScreen or point.Z <= 0 then hidePrediction() return end
        local position = Vector2.new(point.X, point.Y)
        local color = config.Spread <= 0.5
            and Color3.fromRGB(0, 255, 100)
            or (config.Spread <= 2 and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(255, 120, 30))
        if predictionDot then
            predictionDot.Position = position
            predictionDot.Radius = State.PredictDotSize
            predictionDot.Color = color
            predictionDot.Visible = true
        end
        if predictionCircle then
            predictionCircle.Position = position
            predictionCircle.Radius = State.PredictDotSize + 4
            predictionCircle.Color = color
            predictionCircle.Visible = true
        end
        if predictionText then
            predictionText.Position = position + Vector2.new(0, -(State.PredictDotSize + 16))
            predictionText.Text = string.format("%s | %.0fms", config.Name, sample.travelTime * 1000)
            predictionText.Color = color
            predictionText.Visible = true
        end
    end

    local aimFovCircle = safeDrawing("Circle")
    if aimFovCircle then
        aimFovCircle.Filled = false
        aimFovCircle.Thickness = 1.5
        aimFovCircle.Color = Color3.fromRGB(255, 90, 90)
        aimFovCircle.Transparency = 0.65
        aimFovCircle.Visible = false
    end
    local radarCircle = safeDrawing("Circle")
    if radarCircle then
        radarCircle.Filled = true
        radarCircle.Color = Color3.fromRGB(12, 16, 22)
        radarCircle.Transparency = 0.65
        radarCircle.Visible = false
    end
    local radarOutline = safeDrawing("Circle")
    if radarOutline then
        radarOutline.Filled = false
        radarOutline.Thickness = 2
        radarOutline.Color = Color3.fromRGB(120, 180, 255)
        radarOutline.Visible = false
    end

    local function updateRadar()
        if not radarCircle or not radarOutline then return end
        local center = Vector2.new(State.RadarSize + 24, Camera.ViewportSize.Y - State.RadarSize - 44)
        radarCircle.Position, radarOutline.Position = center, center
        radarCircle.Radius, radarOutline.Radius = State.RadarSize, State.RadarSize
        radarCircle.Visible, radarOutline.Visible = State.Radar, State.Radar
        if not State.Radar then
            for _, blip in pairs(radarBlips) do blip.Visible = false end
            return
        end
        local myRoot = getMyRoot()
        if not myRoot then return end
        local active = {}
        for _, entry in ipairs(getTargetEntries()) do
            if isEnemy(entry) then
                local root = getRoot(entry.character)
                if root then
                    local relative = myRoot.CFrame:VectorToObjectSpace(root.Position - myRoot.Position)
                    local planar = Vector2.new(relative.X, relative.Z)
                    if planar.Magnitude <= State.RadarRange then
                        local blip = radarBlips[entry.key]
                        if not blip then
                            blip = safeDrawing("Circle")
                            if blip then
                                blip.Filled = true
                                blip.Radius = 3.5
                                radarBlips[entry.key] = blip
                            end
                        end
                        if blip then
                            local scaled = planar / State.RadarRange * (State.RadarSize - 6)
                            blip.Position = center + Vector2.new(scaled.X, scaled.Y)
                            blip.Color = isCharacterVisible(
                                Camera.CFrame.Position,
                                entry.character,
                                false
                            ) and COLOR_VISIBLE or Color3.fromRGB(255, 190, 60)
                            blip.Visible = true
                            active[entry.key] = true
                        end
                    end
                end
            end
        end
        for key, blip in pairs(radarBlips) do
            if not active[key] then blip.Visible = false end
            if not key.Parent then
                removeDrawing(blip)
                radarBlips[key] = nil
            end
        end
    end

    Connections.playerAdded = Players.PlayerAdded:Connect(function()
        visibilityCache = {}
    end)
    Connections.playerRemoving = Players.PlayerRemoving:Connect(function(player)
        local character = getCharacter(player)
        if character then visibilityCache[character] = nil end
        local key = character or player
        removeESP(key)
        targetPositions[key], targetTimes[key], targetVelocities[key], predictionCache[key] = nil, nil, nil, nil
    end)
    Connections.inputBegan = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2
            and UserInputService:GetFocusedTextBox() == nil then
            rightMouseDown = true
            visibilityCache = {}
            lockedTarget = nil
        end
    end)
    Connections.inputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then rightMouseDown = false end
    end)

    local renderStepName = "RavenGroundWarAim_" .. tostring(LP.UserId)
    RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Camera.Value + 10, function(dt)
        visibilityFrame += 1
        predictionFrame += 1
        updateAutoAim(dt)
        updateAimPrediction()
        updateESP()
        updateRadar()
        if aimFovCircle then
            aimFovCircle.Position = Camera.ViewportSize * 0.5
            aimFovCircle.Radius = State.AimFOV
            aimFovCircle.Visible = State.AutoAim
        end
        if State.FOVEnabled then Camera.FieldOfView = State.FOVValue end
    end)

    local function dropdownValue(value, fallback)
        if type(value) == "table" then
            local selected = value[1]
            if selected == nil then
                for key, item in pairs(value) do
                    selected = item == true and key or item
                    break
                end
            end
            return tostring(selected or fallback)
        end
        return tostring(value or fallback)
    end

    local VisualsTab = Window:CreateTab("Visuals", "eye")
    VisualsTab:CreateSection("Enemy ESP")
    VisualsTab:CreateToggle({Name = "Enemy ESP", CurrentValue = false, Callback = function(value)
        State.ESP = value == true
    end})
    VisualsTab:CreateToggle({Name = "Show Names", CurrentValue = true, Callback = function(value)
        State.ESPNames = value == true
    end})
    VisualsTab:CreateToggle({Name = "Show Distance", CurrentValue = true, Callback = function(value)
        State.ESPDistance = value == true
    end})
    VisualsTab:CreateToggle({Name = "Part Visible Check", CurrentValue = true, Callback = function(value)
        State.ESPWallCheck = value == true
    end})
    VisualsTab:CreateToggle({Name = "Target AIBots", CurrentValue = true, Callback = function(value)
        State.TargetBots = value == true
    end})
    VisualsTab:CreateSlider({Name = "Max Distance (studs)", Range = {100, 5000}, Increment = 100,
        CurrentValue = 2000, Callback = function(value) State.MaxDistance = value end})
    VisualsTab:CreateSection("Environment")
    VisualsTab:CreateToggle({Name = "Fullbright", CurrentValue = false, Callback = function(value)
        State.Fullbright = value == true
        applyFullbright(State.Fullbright)
    end})
    VisualsTab:CreateToggle({Name = "No Fog", CurrentValue = false, Callback = function(value)
        State.NoFog = value == true
        applyNoFog(State.NoFog)
    end})
    VisualsTab:CreateSection("Camera")
    VisualsTab:CreateToggle({Name = "Custom FOV", CurrentValue = false, Callback = function(value)
        State.FOVEnabled = value == true
        applyFOV(State.FOVEnabled, State.FOVValue)
    end})
    VisualsTab:CreateSlider({Name = "FOV Value", Range = {30, 120}, Increment = 5, CurrentValue = 90,
        Callback = function(value)
            State.FOVValue = value
            if State.FOVEnabled then Camera.FieldOfView = value end
        end})

    local AimTab = Window:CreateTab("Aim Predict", "crosshair")
    AimTab:CreateSection("Ballistic Prediction")
    AimTab:CreateToggle({Name = "Enable Aim Prediction", CurrentValue = false, Callback = function(value)
        State.AimPrediction = value == true
        if not State.AimPrediction then hidePrediction() end
    end})
    AimTab:CreateDropdown({Name = "Target Part", Options = {"Head", "HumanoidRootPart"},
        CurrentOption = {"Head"}, MultipleOptions = false, Callback = function(value)
            State.PredictTargetPart = dropdownValue(value, "Head")
            predictionCache = {}
        end})
    AimTab:CreateSlider({Name = "Dot Size", Range = {3, 15}, Increment = 1, CurrentValue = 6,
        Callback = function(value) State.PredictDotSize = value end})
    AimTab:CreateLabel("Dot uses weapon speed, drag, drop, and movement lead")
    AimTab:CreateSection("Smooth Auto Aim")
    AimTab:CreateToggle({Name = "Enable Auto Aim", CurrentValue = false, Callback = function(value)
        State.AutoAim = value == true
        if not State.AutoAim then lockedTarget = nil end
    end})
    AimTab:CreateDropdown({Name = "Activation", Options = {"Right Mouse", "Always"},
        CurrentOption = {"Right Mouse"}, MultipleOptions = false, Callback = function(value)
            State.AimActivation = dropdownValue(value, "Right Mouse") == "Always" and "Always" or "Right Mouse"
        end})
    AimTab:CreateToggle({Name = "Sticky Target", CurrentValue = true, Callback = function(value)
        State.StickyTarget = value == true
    end})
    AimTab:CreateToggle({Name = "Aim Visible Check", CurrentValue = true, Callback = function(value)
        State.AimVisibleCheck = value == true
    end})
    AimTab:CreateDropdown({Name = "Auto Lock Part", Options = {"Auto Visible", "Closest Visible", "Selected Only"},
        CurrentOption = {"Auto Visible"}, MultipleOptions = false, Callback = function(value)
            local selected = dropdownValue(value, "Auto Visible")
            if selected == "Closest Visible" or selected == "Selected Only" then
                State.AimPartMode = selected
            else
                State.AimPartMode = "Auto Visible"
            end
            lockedTarget = nil
            visibilityCache = {}
        end})
    AimTab:CreateToggle({Name = "Recoil / Sway Compensation", CurrentValue = true, Callback = function(value)
        State.AimSwayCompensation = value == true
    end})
    AimTab:CreateToggle({Name = "Adaptive Smoothness", CurrentValue = true, Callback = function(value)
        State.AdaptiveSmoothness = value == true
    end})
    AimTab:CreateSlider({Name = "Aim FOV", Range = {40, 500}, Increment = 10, CurrentValue = 180,
        Suffix = " px", Callback = function(value) State.AimFOV = value end})
    AimTab:CreateSlider({Name = "Smoothness", Range = {0.05, 0.6}, Increment = 0.01, CurrentValue = 0.18,
        Callback = function(value) State.AimSmoothness = value end})

    local TacticalTab = Window:CreateTab("Tactical", "radar")
    TacticalTab:CreateSection("Match Monitor")
    local modeLabel = TacticalTab:CreateLabel("Mode: loading...")
    local teamLabel = TacticalTab:CreateLabel("Team: loading...")
    local scoreLabel = TacticalTab:CreateLabel("Kills / Deaths: loading...")
    local accuracyLabel = TacticalTab:CreateLabel("Shots: loading...")
    local targetLabel = TacticalTab:CreateLabel("Enemies: loading...")
    TacticalTab:CreateSection("Radar")
    TacticalTab:CreateToggle({Name = "Tactical Radar", CurrentValue = false, Callback = function(value)
        State.Radar = value == true
    end})
    TacticalTab:CreateSlider({Name = "Radar Range", Range = {100, 2000}, Increment = 50, CurrentValue = 700,
        Suffix = " studs", Callback = function(value) State.RadarRange = value end})
    TacticalTab:CreateSlider({Name = "Radar Size", Range = {80, 240}, Increment = 10, CurrentValue = 150,
        Suffix = " px", Callback = function(value) State.RadarSize = value end})

    local lastDashboardUpdate = 0
    Connections.dashboard = RunService.Heartbeat:Connect(function()
        if os.clock() - lastDashboardUpdate < 0.5 then return end
        lastDashboardUpdate = os.clock()
        local attributes = LP:GetAttributes()
        local mode = attributes.MG_Name or "Ground War"
        local team = attributes.MG_Team or (LP.Team and LP.Team.Name) or "Unknown"
        local kills = attributes.MG_Stat_Kills or 0
        local deaths = attributes.MG_Stat_Deaths or 0
        local fired = attributes.MG_Stat_ShotsFired or 0
        local hit = attributes.MG_Stat_ShotsHit or 0
        local enemies = 0
        for _, entry in ipairs(getTargetEntries()) do
            if isEnemy(entry) then enemies += 1 end
        end
        pcall(function()
            modeLabel:Set("Mode: " .. tostring(mode))
            teamLabel:Set("Team: " .. tostring(team))
            scoreLabel:Set(string.format("Kills / Deaths: %s / %s", tostring(kills), tostring(deaths)))
            accuracyLabel:Set(string.format("Shots: %s fired | %s hit", tostring(fired), tostring(hit)))
            targetLabel:Set("Enemies: " .. tostring(enemies))
        end)
    end)

    local InfoTab = Window:CreateTab("Info", "info")
    InfoTab:CreateSection("Ground War (o)")
    InfoTab:CreateLabel("Player: " .. tostring(LP.DisplayName or LP.Name))
    InfoTab:CreateLabel("Team: " .. tostring(getTeamValue(LP) or "Unknown"))
    InfoTab:CreateLabel("Target source: Players + workspace.Bots/AIBot")
    InfoTab:CreateLabel("PlaceId: 76822114837453 | GameId: 6583326485")

    local function destroy()
        if destroyed then return end
        destroyed = true
        pcall(function() RunService:UnbindFromRenderStep(renderStepName) end)
        for _, connection in pairs(Connections) do pcall(function() connection:Disconnect() end) end
        clearAllESP()
        destroyPredictionDot()
        removeDrawing(aimFovCircle)
        removeDrawing(radarCircle)
        removeDrawing(radarOutline)
        for key, blip in pairs(radarBlips) do
            removeDrawing(blip)
            radarBlips[key] = nil
        end
        espFolder:Destroy()
        applyFullbright(false)
        applyNoFog(false)
        applyFOV(false)
        if getgenv().__RAVEN_GROUND_WAR and getgenv().__RAVEN_GROUND_WAR.State == State then
            getgenv().__RAVEN_GROUND_WAR = nil
        end
    end

    getgenv().__RAVEN_GROUND_WAR = {Version = "v0.1.0", State = State, Destroy = destroy}
    if runtimeInfo and runtimeInfo.registerCleanup then runtimeInfo.registerCleanup(destroy) end
end
