--[[
    RAVEN HUB Module - The Wild West v0.1.0
    Game: The Wild West (PlaceId: 2317712696, GameId: 807930589)
    Developer: Starboard Studios

    Features:
    - FPS-safe Smooth Auto Lock for replicated player models
    - Player / Animal / Loot Chest / Ore ESP
    - Fullbright / No Fog / Custom FOV
    - Cleanup-safe runtime state
]]

return function(Window, runtimeInfo)
    pcall(function()
        local previous = getgenv().__RAVEN_THE_WILD_WEST
        if previous and type(previous.Destroy) == "function" then previous.Destroy() end
    end)

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Lighting = game:GetService("Lighting")
    local CollectionService = game:GetService("CollectionService")

    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera
    local entitiesRoot = workspace:FindFirstChild("WORKSPACE_Entities")
    local interactablesRoot = workspace:FindFirstChild("WORKSPACE_Interactables")
    local playerModels = entitiesRoot and entitiesRoot:FindFirstChild("Players")
    local animalFolder = entitiesRoot and entitiesRoot:FindFirstChild("Animals")
    local lootFolder = interactablesRoot and interactablesRoot:FindFirstChild("LootChests")
    local miningFolder = interactablesRoot and interactablesRoot:FindFirstChild("Mining")
    local oreDeposits = miningFolder and miningFolder:FindFirstChild("OreDeposits")

    local State = {
        AutoLock = false,
        AimActivation = "Right Mouse",
        AimFOV = 180,
        AimSmoothness = 0.18,
        AdaptiveSmoothness = true,
        StickyTarget = true,
        AimVisibleCheck = true,
        AimPartMode = "Auto Visible",
        AimTargetPart = "Head",
        IgnoreSameTeam = false,
        PlayerESP = false,
        AnimalESP = false,
        LootESP = false,
        LootAvailableOnly = true,
        OreESP = false,
        ESPMaxDistance = 1800,
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 90,
    }

    local Connections = {}
    local rightMouseDown = false
    local lockedTarget = nil
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
    local OriginalAtmosphere = nil
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Atmosphere") then
            OriginalAtmosphere = {instance = child, Density = child.Density}
            break
        end
    end

    local function getPlayerModel(player)
        if playerModels then
            local model = playerModels:FindFirstChild(player.Name)
            if model then return model end
        end
        return player.Character
    end

    local function getHumanoid(model)
        return model and model:FindFirstChildOfClass("Humanoid") or nil
    end

    local function getRoot(model)
        return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) or nil
    end

    local function getMyRoot()
        return getRoot(getPlayerModel(LP))
    end

    local function isTargetPlayer(player)
        if not player or player == LP then return false end
        local model = getPlayerModel(player)
        local humanoid = getHumanoid(model)
        if not model or not humanoid or humanoid.Health <= 0 then return false end
        if State.IgnoreSameTeam and LP.Team and player.Team and LP.Team == player.Team then return false end
        return true
    end

    local function getBasePart(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then return instance end
        if instance:IsA("Model") and instance.PrimaryPart then return instance.PrimaryPart end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end

    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude
    local MAX_VISION_PASSTHROUGHS = 6
    local visibilityCache = {}
    local visibilityFrame = 0
    local rayFilterFrame = -1
    local AUTO_VISIBLE_SAMPLE_SCALE = 0.48
    local AUTO_VISIBLE_PARTS_PER_SCAN = 4
    local AUTO_VISIBLE_SCAN_INTERVAL = 2
    local AIM_PREFILTER_MARGIN = 80
    local VISIBILITY_PARTS = {
        "Head", "UpperTorso", "LowerTorso",
        "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
        "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
    }

    local function buildRayFilter()
        if rayFilterFrame == visibilityFrame then return end
        local ignore = {}
        local myModel = getPlayerModel(LP)
        if myModel then table.insert(ignore, myModel) end
        local ignoreFolder = workspace:FindFirstChild("Ignore")
        if ignoreFolder then table.insert(ignore, ignoreFolder) end
        RayParams.FilterDescendantsInstances = ignore
        rayFilterFrame = visibilityFrame
    end

    local function isVisionTransparent(instance)
        return instance:IsA("BasePart") and instance.Transparency >= 0.35
    end

    local function rayReachesTarget(fromPos, toPos, targetModel, targetPart)
        buildRayFilter()
        local direction = toPos - fromPos
        local baseIgnored = table.clone(RayParams.FilterDescendantsInstances)
        local ignored = table.clone(baseIgnored)
        local visible = false
        for _ = 1, MAX_VISION_PASSTHROUGHS do
            RayParams.FilterDescendantsInstances = ignored
            local result = workspace:Raycast(fromPos, direction, RayParams)
            if not result then
                visible = true
                break
            end
            if result.Instance == targetPart or (targetModel and result.Instance:IsDescendantOf(targetModel)) then
                visible = true
                break
            end
            if not isVisionTransparent(result.Instance) then break end
            table.insert(ignored, result.Instance)
        end
        RayParams.FilterDescendantsInstances = baseIgnored
        return visible
    end

    local function getVisibilityOffsets(part, scale)
        local halfX = part.Size.X * scale
        local halfY = part.Size.Y * scale
        return {
            Vector3.zero,
            Vector3.new(halfX, 0, 0),
            Vector3.new(-halfX, 0, 0),
            Vector3.new(0, halfY, 0),
            Vector3.new(0, -halfY, 0),
            Vector3.new(halfX, halfY, 0),
            Vector3.new(-halfX, halfY, 0),
            Vector3.new(halfX, -halfY, 0),
            Vector3.new(-halfX, -halfY, 0),
        }
    end

    local function getAimPartPriority(part)
        local name = part.Name
        if name == "Head" then return 1 end
        if string.find(name, "Torso", 1, true) then return 2 end
        if string.find(name, "Arm", 1, true) or string.find(name, "Hand", 1, true) then return 3 end
        return 4
    end

    local function getAimParts(model)
        local parts = {}
        for _, partName in ipairs(VISIBILITY_PARTS) do
            local part = model:FindFirstChild(partName)
            if part and part:IsA("BasePart") then table.insert(parts, part) end
        end
        return parts
    end

    local function scanAutoVisibleParts(fromPos, targetModel, parts, cached)
        cached.parts = cached.parts or {}
        if cached.lastScan and visibilityFrame - cached.lastScan < AUTO_VISIBLE_SCAN_INTERVAL then
            cached.frame = visibilityFrame
            visibilityCache[targetModel] = cached
            return cached.visible or false, cached.parts, cached.priorityPart
        end
        cached.lastScan = visibilityFrame

        local scanCount = math.min(AUTO_VISIBLE_PARTS_PER_SCAN, #parts)
        local index = math.clamp(cached.partIndex or 1, 1, math.max(#parts, 1))
        for _ = 1, scanCount do
            local part = parts[index]
            local partState = cached.parts[part] or {edgeIndex = 2, visible = false}
            local offsets = getVisibilityOffsets(part, AUTO_VISIBLE_SAMPLE_SCALE)
            local sampleVisible = rayReachesTarget(
                fromPos, part.CFrame:PointToWorldSpace(offsets[1]), targetModel, part
            )
            if not sampleVisible then
                local edgeIndex = math.clamp(partState.edgeIndex or 2, 2, #offsets)
                sampleVisible = rayReachesTarget(
                    fromPos, part.CFrame:PointToWorldSpace(offsets[edgeIndex]), targetModel, part
                )
                edgeIndex += 1
                if edgeIndex > #offsets then edgeIndex = 2 end
                partState.edgeIndex = edgeIndex
            end
            partState.visible = sampleVisible
            cached.parts[part] = partState
            index = index % #parts + 1
        end
        cached.partIndex = index

        local center = Camera.ViewportSize * 0.5
        local priorityPart, priorityDistance = nil, math.huge
        local anyVisible = false
        for rank = 1, 4 do
            for _, part in ipairs(parts) do
                local partState = cached.parts[part]
                if partState and partState.visible then
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
        cached.frame = visibilityFrame
        visibilityCache[targetModel] = cached
        return anyVisible, cached.parts, priorityPart
    end

    local function getVisibleState(targetModel)
        if not targetModel then return false, {}, nil end
        local cached = visibilityCache[targetModel]
        if cached and cached.frame == visibilityFrame then
            return cached.visible or false, cached.parts or {}, cached.priorityPart
        end
        local parts = getAimParts(targetModel)
        if #parts == 0 then return false, {}, nil end
        cached = cached or {parts = {}, partIndex = 1}
        return scanAutoVisibleParts(Camera.CFrame.Position, targetModel, parts, cached)
    end

    local function resolveAimPart(player, requireVisible)
        local model = getPlayerModel(player)
        if not model then return nil end
        local preferred = model:FindFirstChild(State.AimTargetPart) or model:FindFirstChild("Head")
        if not requireVisible then return preferred end
        local _, states, priorityPart = getVisibleState(model)
        local function visible(part)
            local partState = part and states and states[part]
            return part and part:IsA("BasePart") and partState and partState.visible
        end
        if State.AimPartMode == "Selected Only" then
            return visible(preferred) and preferred or nil
        end
        if State.AimPartMode == "Auto Visible" and visible(priorityPart) then
            return priorityPart
        end

        local best, bestDistance = nil, math.huge
        local center = Camera.ViewportSize * 0.5
        for _, part in ipairs(getAimParts(model)) do
            if visible(part) then
                local point, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and point.Z > 0 then
                    local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
                    if distance < bestDistance then
                        best, bestDistance = part, distance
                    end
                end
            end
        end
        return best
    end

    local function aimActive()
        if not State.AutoLock then return false end
        if State.AimActivation == "Always" then return true end
        local ok, held = pcall(function()
            return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end)
        return rightMouseDown and ok and held == true
    end

    local function getAimResponse(screenError)
        local response = math.max(1, State.AimSmoothness * 60)
        if State.AdaptiveSmoothness then
            local normalized = math.clamp((screenError or 0) / math.max(State.AimFOV, 1), 0, 1)
            response *= 1 + normalized * 2.5
        end
        return response
    end

    local function validAimTarget(player)
        if not isTargetPlayer(player) then return false end
        local part = resolveAimPart(player, State.AimVisibleCheck)
        if not part then return false end
        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then return false end
        return (Vector2.new(point.X, point.Y) - Camera.ViewportSize * 0.5).Magnitude <= State.AimFOV
    end

    local function getClosestTarget()
        local center = Camera.ViewportSize * 0.5
        local best, bestDistance = nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if not isTargetPlayer(player) then continue end
            local model = getPlayerModel(player)
            local reference = model and (model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso") or getRoot(model))
            if not reference then continue end
            local point, onScreen = Camera:WorldToViewportPoint(reference.Position)
            if not onScreen or point.Z <= 0 then continue end
            local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
            if distance > State.AimFOV + AIM_PREFILTER_MARGIN then continue end
            local part = resolveAimPart(player, State.AimVisibleCheck)
            if part then
                local targetPoint, targetOnScreen = Camera:WorldToViewportPoint(part.Position)
                if targetOnScreen and targetPoint.Z > 0 then
                    local targetDistance = (Vector2.new(targetPoint.X, targetPoint.Y) - center).Magnitude
                    if targetDistance <= State.AimFOV and targetDistance < bestDistance then
                        best, bestDistance = player, targetDistance
                    end
                end
            end
        end
        return best
    end

    local function updateAutoLock(dt)
        if not aimActive() then
            lockedTarget = nil
            State.AimEngaged = false
            State.AimLockedPart = nil
            return
        end
        if not State.StickyTarget or not validAimTarget(lockedTarget) then
            lockedTarget = getClosestTarget()
        end
        if not lockedTarget then return end
        local part = resolveAimPart(lockedTarget, State.AimVisibleCheck)
        if not part then return end

        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then return end
        local desired = CFrame.lookAt(Camera.CFrame.Position, part.Position, Camera.CFrame.UpVector)
        local screenError = (Vector2.new(point.X, point.Y) - Camera.ViewportSize * 0.5).Magnitude
        local response = getAimResponse(screenError)
        local alpha = 1 - math.exp(-response * math.max(dt or 1 / 60, 1 / 240))
        Camera.CFrame = Camera.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))
        State.AimEngaged = true
        State.AimLockedPart = part.Name
        State.AimLockedPlayer = lockedTarget.Name
    end

    local aimCircle = Drawing.new("Circle")
    aimCircle.Filled = false
    aimCircle.Thickness = 1.5
    aimCircle.Transparency = 0.7
    aimCircle.Color = Color3.fromRGB(255, 100, 100)
    aimCircle.Visible = false

    local EspRecords = {players = {}, animals = {}, loot = {}, ore = {}}

    local function removeDrawing(record)
        if record and record.text then pcall(function() record.text:Remove() end) end
    end

    local function clearGroup(group)
        for key, record in pairs(group) do
            removeDrawing(record)
            group[key] = nil
        end
    end

    local function getTextRecord(group, key)
        local record = group[key]
        if record then return record end
        local text = Drawing.new("Text")
        text.Size = 13
        text.Center = true
        text.Outline = true
        text.Visible = false
        record = {text = text}
        group[key] = record
        return record
    end

    local function setEspText(record, part, label, color)
        if not record or not part then return end
        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then
            record.text.Visible = false
            return
        end
        local myRoot = getMyRoot()
        if not myRoot then
            record.text.Visible = false
            return
        end
        local distance = (part.Position - myRoot.Position).Magnitude
        if distance > State.ESPMaxDistance then
            record.text.Visible = false
            return
        end
        record.text.Position = Vector2.new(point.X, point.Y)
        record.text.Text = string.format("%s | %.0f", label, distance)
        record.text.Color = color
        record.text.Visible = true
    end

    local function updatePlayerESP()
        if not State.PlayerESP then clearGroup(EspRecords.players) return end
        local active = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP then
                local model = getPlayerModel(player)
                local head = model and (model:FindFirstChild("Head") or getRoot(model))
                local humanoid = getHumanoid(model)
                if head and humanoid and humanoid.Health > 0 then
                    local record = getTextRecord(EspRecords.players, player)
                    local label = string.format("%s | HP %.0f", player.Name, humanoid.Health)
                    setEspText(record, head, label, Color3.fromRGB(255, 90, 90))
                    active[player] = true
                end
            end
        end
        for key, record in pairs(EspRecords.players) do
            if not active[key] then removeDrawing(record); EspRecords.players[key] = nil end
        end
    end

    local function updateAnimalESP()
        if not State.AnimalESP or not animalFolder then clearGroup(EspRecords.animals) return end
        local active = {}
        for _, animal in ipairs(animalFolder:GetChildren()) do
            local part = animal:FindFirstChild("Head") or animal:FindFirstChild("HumanoidRootPart") or getBasePart(animal)
            if part then
                local health = animal:FindFirstChild("Health")
                local anger = animal:FindFirstChild("Anger")
                local suffix = health and string.format(" HP %.0f", tonumber(health.Value) or 0) or ""
                if anger and tonumber(anger.Value) and tonumber(anger.Value) > 0 then suffix ..= " !" end
                local record = getTextRecord(EspRecords.animals, animal)
                setEspText(record, part, animal.Name .. suffix, Color3.fromRGB(255, 210, 90))
                active[animal] = true
            end
        end
        for key, record in pairs(EspRecords.animals) do
            if not active[key] then removeDrawing(record); EspRecords.animals[key] = nil end
        end
    end

    local function updateLootESP()
        if not State.LootESP or not lootFolder then clearGroup(EspRecords.loot) return end
        local active = {}
        for _, chest in ipairs(CollectionService:GetTagged("LootChest")) do
            if chest:IsDescendantOf(lootFolder) then
                local state = chest:GetAttribute("State")
                if not State.LootAvailableOnly or state == "Available" then
                    local part = getBasePart(chest)
                    if part then
                        local record = getTextRecord(EspRecords.loot, chest)
                        local lootTable = chest:GetAttribute("LootTable") or chest.Name
                        setEspText(record, part, tostring(lootTable) .. " [" .. tostring(state or "?") .. "]", Color3.fromRGB(100, 255, 150))
                        active[chest] = true
                    end
                end
            end
        end
        for key, record in pairs(EspRecords.loot) do
            if not active[key] then removeDrawing(record); EspRecords.loot[key] = nil end
        end
    end

    local function updateOreESP()
        if not State.OreESP or not oreDeposits then clearGroup(EspRecords.ore) return end
        local active = {}
        for _, typeFolder in ipairs(oreDeposits:GetChildren()) do
            for _, deposit in ipairs(typeFolder:GetChildren()) do
                local part = getBasePart(deposit)
                if part then
                    local record = getTextRecord(EspRecords.ore, deposit)
                    local oreRemaining = deposit:FindFirstChild("OreRemaining", true)
                    local suffix = oreRemaining and string.format(" %.0f", tonumber(oreRemaining.Value) or 0) or ""
                    setEspText(record, part, typeFolder.Name .. suffix, Color3.fromRGB(120, 200, 255))
                    active[deposit] = true
                end
            end
        end
        for key, record in pairs(EspRecords.ore) do
            if not active[key] then removeDrawing(record); EspRecords.ore[key] = nil end
        end
    end

    local function applyFullbright(enabled)
        if enabled then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.Ambient = Color3.new(1, 1, 1)
            Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
            Lighting.GlobalShadows = false
        else
            Lighting.Brightness = OriginalLighting.Brightness
            Lighting.ClockTime = OriginalLighting.ClockTime
            Lighting.Ambient = OriginalLighting.Ambient
            Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
            Lighting.GlobalShadows = OriginalLighting.GlobalShadows
        end
    end

    local function applyNoFog(enabled)
        if enabled then
            Lighting.FogStart = 1e6
            Lighting.FogEnd = 1e6
            if OriginalAtmosphere and OriginalAtmosphere.instance then OriginalAtmosphere.instance.Density = 0 end
        else
            Lighting.FogStart = OriginalLighting.FogStart
            Lighting.FogEnd = OriginalLighting.FogEnd
            if OriginalAtmosphere and OriginalAtmosphere.instance then
                OriginalAtmosphere.instance.Density = OriginalAtmosphere.Density
            end
        end
    end

    Connections.inputBegan = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 and UserInputService:GetFocusedTextBox() == nil then
            rightMouseDown = true
            visibilityCache = {}
            lockedTarget = nil
        end
    end)
    Connections.inputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then rightMouseDown = false end
    end)

    local espAccumulator = 0
    local renderStepName = "RavenWildWest_" .. tostring(LP.UserId)
    RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Camera.Value + 10, function(dt)
        visibilityFrame += 1
        updateAutoLock(dt)
        aimCircle.Position = Camera.ViewportSize * 0.5
        aimCircle.Radius = State.AimFOV
        aimCircle.Visible = State.AutoLock
        if State.FOVEnabled then Camera.FieldOfView = State.FOVValue end
        espAccumulator += dt
        if espAccumulator >= 0.1 then
            espAccumulator = 0
            updatePlayerESP()
            updateAnimalESP()
            updateLootESP()
            updateOreESP()
        end
    end)

    Connections.environment = RunService.Heartbeat:Connect(function()
        if destroyed then return end
        if State.Fullbright then applyFullbright(true) end
        if State.NoFog then applyNoFog(true) end
    end)

    local function dropdownValue(value, fallback)
        if type(value) ~= "table" then return tostring(value or fallback) end
        if value[1] ~= nil then return tostring(value[1]) end
        for key, item in pairs(value) do
            return tostring(item == true and key or item)
        end
        return fallback
    end

    local CombatTab = Window:CreateTab("Combat", "crosshair")
    CombatTab:CreateSection("Smooth Auto Lock")
    CombatTab:CreateToggle({Name="Enable Auto Lock",CurrentValue=false,Flag="WildWestAutoLock",Callback=function(v)
        State.AutoLock = v == true
        if not State.AutoLock then lockedTarget = nil end
    end})
    CombatTab:CreateDropdown({Name="Activation",Options={"Right Mouse","Always"},CurrentOption={"Right Mouse"},MultipleOptions=false,Flag="WildWestAimActivation",Callback=function(v)
        local selected = dropdownValue(v, "Right Mouse")
        State.AimActivation = selected:lower() == "always" and "Always" or "Right Mouse"
    end})
    CombatTab:CreateToggle({Name="Sticky Target",CurrentValue=true,Flag="WildWestStickyTarget",Callback=function(v) State.StickyTarget = v == true end})
    CombatTab:CreateToggle({Name="Visible Check",CurrentValue=true,Flag="WildWestVisibleCheck",Callback=function(v)
        State.AimVisibleCheck = v == true
        lockedTarget = nil
    end})
    CombatTab:CreateToggle({Name="Ignore Same Team",CurrentValue=false,Flag="WildWestIgnoreTeam",Callback=function(v)
        State.IgnoreSameTeam = v == true
        lockedTarget = nil
    end})
    CombatTab:CreateDropdown({Name="Auto Lock Part",Options={"Auto Visible","Closest Visible","Selected Only"},CurrentOption={"Auto Visible"},MultipleOptions=false,Flag="WildWestAimPartMode",Callback=function(v)
        local selected = dropdownValue(v, "Auto Visible")
        if selected ~= "Closest Visible" and selected ~= "Selected Only" then selected = "Auto Visible" end
        State.AimPartMode = selected
        lockedTarget = nil
    end})
    CombatTab:CreateDropdown({Name="Selected Part",Options={"Head","UpperTorso","LowerTorso"},CurrentOption={"Head"},MultipleOptions=false,Flag="WildWestAimTargetPart",Callback=function(v)
        State.AimTargetPart = dropdownValue(v, "Head")
        lockedTarget = nil
    end})
    CombatTab:CreateToggle({Name="Adaptive Smoothness",CurrentValue=true,Flag="WildWestAdaptiveSmooth",Callback=function(v) State.AdaptiveSmoothness = v == true end})
    CombatTab:CreateSlider({Name="Aim FOV",Range={40,500},Increment=10,CurrentValue=180,Suffix=" px",Flag="WildWestAimFOV",Callback=function(v) State.AimFOV = v end})
    CombatTab:CreateSlider({Name="Smoothness",Range={0.05,0.6},Increment=0.01,CurrentValue=0.18,Flag="WildWestAimSmooth",Callback=function(v) State.AimSmoothness = v end})
    CombatTab:CreateLabel("FPS-safe: 4 parts per visibility scan, every 2 frames")

    local EspTab = Window:CreateTab("ESP", "eye")
    EspTab:CreateSection("Entities")
    EspTab:CreateToggle({Name="Player ESP",CurrentValue=false,Flag="WildWestPlayerESP",Callback=function(v) State.PlayerESP = v == true end})
    EspTab:CreateToggle({Name="Animal ESP",CurrentValue=false,Flag="WildWestAnimalESP",Callback=function(v) State.AnimalESP = v == true end})
    EspTab:CreateToggle({Name="Loot Chest ESP",CurrentValue=false,Flag="WildWestLootESP",Callback=function(v) State.LootESP = v == true end})
    EspTab:CreateToggle({Name="Available Chests Only",CurrentValue=true,Flag="WildWestLootAvailable",Callback=function(v) State.LootAvailableOnly = v == true end})
    EspTab:CreateToggle({Name="Ore ESP",CurrentValue=false,Flag="WildWestOreESP",Callback=function(v) State.OreESP = v == true end})
    EspTab:CreateSlider({Name="ESP Max Distance",Range={100,5000},Increment=100,CurrentValue=1800,Suffix=" studs",Flag="WildWestESPRange",Callback=function(v) State.ESPMaxDistance = v end})

    local VisualsTab = Window:CreateTab("Visuals", "sun")
    VisualsTab:CreateSection("Environment")
    VisualsTab:CreateToggle({Name="Fullbright",CurrentValue=false,Flag="WildWestFullbright",Callback=function(v)
        State.Fullbright = v == true
        applyFullbright(State.Fullbright)
    end})
    VisualsTab:CreateToggle({Name="No Fog",CurrentValue=false,Flag="WildWestNoFog",Callback=function(v)
        State.NoFog = v == true
        applyNoFog(State.NoFog)
    end})
    VisualsTab:CreateSection("Camera")
    VisualsTab:CreateToggle({Name="Custom FOV",CurrentValue=false,Flag="WildWestCustomFOV",Callback=function(v)
        State.FOVEnabled = v == true
        if not State.FOVEnabled then Camera.FieldOfView = OriginalFOV end
    end})
    VisualsTab:CreateSlider({Name="FOV Value",Range={30,120},Increment=5,CurrentValue=90,Flag="WildWestFOVValue",Callback=function(v)
        State.FOVValue = v
        if State.FOVEnabled then Camera.FieldOfView = v end
    end})

    local InfoTab = Window:CreateTab("Info", "info")
    InfoTab:CreateSection("The Wild West")
    InfoTab:CreateLabel("Player Models: WORKSPACE_Entities/Players")
    InfoTab:CreateLabel("Loot State: LootChest tag + State attribute")
    InfoTab:CreateLabel("Ore Source: WORKSPACE_Interactables/Mining/OreDeposits")
    local statusLabel = InfoTab:CreateLabel("Status: ready")
    Connections.status = RunService.Heartbeat:Connect(function()
        if destroyed then return end
        if math.floor(os.clock() * 2) ~= math.floor((os.clock() - 1 / 60) * 2) then
            pcall(function()
                statusLabel:Set(string.format(
                    "Players %d | Animals %d | Chests %d | Ore Types %d",
                    playerModels and #playerModels:GetChildren() or 0,
                    animalFolder and #animalFolder:GetChildren() or 0,
                    lootFolder and #lootFolder:GetChildren() or 0,
                    oreDeposits and #oreDeposits:GetChildren() or 0
                ))
            end)
        end
    end)

    local function destroy()
        if destroyed then return end
        destroyed = true
        pcall(function() RunService:UnbindFromRenderStep(renderStepName) end)
        for _, connection in pairs(Connections) do pcall(function() connection:Disconnect() end) end
        pcall(function() aimCircle:Remove() end)
        clearGroup(EspRecords.players)
        clearGroup(EspRecords.animals)
        clearGroup(EspRecords.loot)
        clearGroup(EspRecords.ore)
        applyFullbright(false)
        applyNoFog(false)
        Camera.FieldOfView = OriginalFOV
        if getgenv().__RAVEN_THE_WILD_WEST and getgenv().__RAVEN_THE_WILD_WEST.State == State then
            getgenv().__RAVEN_THE_WILD_WEST = nil
        end
    end

    getgenv().__RAVEN_THE_WILD_WEST = {Version="v0.1.0",State=State,Destroy=destroy}
    if runtimeInfo and runtimeInfo.registerCleanup then runtimeInfo.registerCleanup(destroy) end
end
