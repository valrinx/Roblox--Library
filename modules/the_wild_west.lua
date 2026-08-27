--[[
    RAVEN HUB Module - The Wild West v0.1.5
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
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local SystemModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("System")
    local ReplicatedState = require(SystemModules:WaitForChild("ReplicatedState"))
    local PlayerData = require(SystemModules:WaitForChild("PlayerData"))
    local CharacterModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Character")
    local PlayerCharacter = require(CharacterModules:WaitForChild("PlayerCharacter"))
    local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
    local ProjectileModule = SharedModules:WaitForChild("World"):WaitForChild("ProjectileHandler")
    local ProjectileHandler = require(ProjectileModule)
    local SharedProjectiles = require(ProjectileModule:WaitForChild("SharedProjectiles"))
    local Global = require(SharedModules:WaitForChild("Global"))
    local Hotbar = nil
    pcall(function() Hotbar = Global.LoadModule("Hotbar") end)

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
        AnimalAutoLock = false,
        AimPrediction = false,
        ExactSeedCorrection = false,
        LastProjectileSeed = nil,
        LastSeedCorrectionApplied = false,
        PredictDotSize = 6,
        AimActivation = "Right Mouse",
        AimFOV = 180,
        AimSmoothness = 0.18,
        AdaptiveSmoothness = true,
        StickyTarget = true,
        AimVisibleCheck = true,
        AimPartMode = "Auto Visible",
        AimTargetPart = "Head",
        IgnoreSameTeam = true,
        IgnoreSameFaction = true,
        PlayerESP = false,
        PlayerESPDistance = 1800,
        PlayerESPShowRole = true,
        PlayerESPShowFaction = true,
        AnimalESP = false,
        AnimalESPDistance = 900,
        LootESP = false,
        LootAvailableOnly = true,
        LootESPDistance = 1200,
        OreESP = false,
        OreESPDistance = 1200,
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 90,
    }

    local Connections = {}
    local rightMouseDown = false
    local lockedTarget = nil
    local destroyed = false
    local predictionFrame = 0
    local predictionCache = {}
    local lastTargetPositions = {}
    local lastTargetTimes = {}
    local smoothedTargetVelocities = {}
    local cachedWeaponItem = nil
    local cachedWeaponConfig = nil
    local cachedWeaponFrame = -1
    local latestAimSolution = nil
    local originalGetProjectileSpread = nil
    local seedHookTarget = nil
    local seedHookInstalled = false

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

    local ROLE_LABELS = {
        Outlaws = "OUTLAW",
        Lawmen = "LAWMAN",
        Citizens = "CITIZEN",
        Default = "DEFAULT",
    }
    local ROLE_COLORS = {
        Outlaws = Color3.fromRGB(255, 70, 70),
        Lawmen = Color3.fromRGB(80, 165, 255),
        Citizens = Color3.fromRGB(255, 215, 105),
        Default = Color3.fromRGB(190, 190, 190),
    }
    local factionIdCache = {}
    local factionInfoCache = {}

    local function getTeamName(player)
        if not player then return nil end
        local team = player.Team
        return team and team.Name ~= "" and team.Name or nil
    end

    local function getRoleLabel(player)
        local teamName = getTeamName(player) or "Default"
        return ROLE_LABELS[teamName] or string.upper(teamName), ROLE_COLORS[teamName] or ROLE_COLORS.Default
    end

    local function getFactionId(player)
        if not player then return nil end
        local now = os.clock()
        local cached = factionIdCache[player]
        if cached and now < cached.expires then return cached.id end
        local factionId = nil
        pcall(function()
            local playerState = ReplicatedState:GetPlayerState(player)
            factionId = playerState and playerState.State and playerState.State.CurrentFactionId or nil
        end)
        factionIdCache[player] = {id = factionId, expires = now + 1}
        return factionId
    end

    local function getFactionInfo(player)
        local factionId = getFactionId(player)
        if not factionId then return nil, nil end
        local now = os.clock()
        local cached = factionInfoCache[factionId]
        if cached and now < cached.expires then return cached.name, cached.tag end
        local name, tag = nil, nil
        pcall(function()
            local faction = PlayerData:GetFaction(factionId)
            if faction and faction.Data then
                name = faction.Data.Name
                tag = faction.Data.Tag
            end
        end)
        factionInfoCache[factionId] = {name = name, tag = tag, expires = now + 5}
        return name, tag
    end

    local function isSameTeam(player)
        local myTeam = getTeamName(LP)
        local otherTeam = getTeamName(player)
        return myTeam ~= nil and otherTeam ~= nil and myTeam == otherTeam
    end

    local function isSameFaction(player)
        local myFaction = getFactionId(LP)
        local otherFaction = getFactionId(player)
        return myFaction ~= nil and otherFaction ~= nil and myFaction == otherFaction
    end

    local function isTargetPlayer(player)
        if not player or player == LP then return false end
        local model = getPlayerModel(player)
        local humanoid = getHumanoid(model)
        if not model or not humanoid or humanoid.Health <= 0 then return false end
        if State.IgnoreSameTeam and isSameTeam(player) then return false end
        if State.IgnoreSameFaction and isSameFaction(player) then return false end
        return true
    end

    local function getBasePart(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then return instance end
        if instance:IsA("Model") and instance.PrimaryPart then return instance.PrimaryPart end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end

    local function isTargetAnimal(animal)
        if not animalFolder or not animal or not animal:IsDescendantOf(animalFolder) then return false end
        local humanoid = getHumanoid(animal)
        if humanoid and humanoid.Health <= 0 then return false end
        local health = animal:FindFirstChild("Health")
        if health and health:IsA("ValueBase") and tonumber(health.Value) and tonumber(health.Value) <= 0 then return false end
        return getBasePart(animal) ~= nil
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
        if name == "HumanoidRootPart" or string.find(name, "Torso", 1, true) or string.find(name, "Body", 1, true) then return 2 end
        if string.find(name, "Arm", 1, true) or string.find(name, "Hand", 1, true) then return 3 end
        return 4
    end

    local function getAimParts(model)
        local parts = {}
        local seen = {}
        local function add(part)
            if part and part:IsA("BasePart") and not seen[part] then
                seen[part] = true
                table.insert(parts, part)
            end
        end
        for _, partName in ipairs(VISIBILITY_PARTS) do
            add(model:FindFirstChild(partName))
        end
        add(model:FindFirstChild("HumanoidRootPart"))
        add(model:FindFirstChild("Body"))
        if #parts == 0 then
            add(model:FindFirstChild("Head"))
            if model:IsA("Model") then add(model.PrimaryPart) end
            for _, part in ipairs(model:GetDescendants()) do
                if #parts >= 6 then break end
                if part:IsA("BasePart") and part.Transparency < 1 then add(part) end
            end
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

    local function resolveModelAimPart(model, preferredName, requireVisible)
        if not model then return nil end
        local preferred = model:FindFirstChild(preferredName or State.AimTargetPart)
            or model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or getBasePart(model)
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

    local function resolveTargetAimPart(target, requireVisible)
        if not target then return nil end
        if target:IsA("Player") then
            return resolveModelAimPart(getPlayerModel(target), State.AimTargetPart, requireVisible)
        end
        return resolveModelAimPart(target, "Head", requireVisible)
    end

    local function getTargetModel(target)
        if not target then return nil end
        return target:IsA("Player") and getPlayerModel(target) or target
    end

    local function isTargetValid(target)
        if not target then return false end
        if target:IsA("Player") then return State.AutoLock and isTargetPlayer(target) end
        return State.AnimalAutoLock and isTargetAnimal(target)
    end

    local function getEffectiveAmmoType(shared)
        local specialAmmo = shared.SpecialAmmoTypes
        if type(specialAmmo) ~= "table" then return nil end
        local sniperAmmo = Hotbar and Hotbar.EquippedSniperAmmo or nil
        local shotgunAmmo = Hotbar and Hotbar.EquippedShotgunAmmo or nil
        for _, ammoType in {sniperAmmo, shotgunAmmo, shared.DefaultAmmoType} do
            if ammoType and table.find(specialAmmo, ammoType) then
                if ammoType == shared.DefaultAmmoType then return ammoType end
                local ok, owned = pcall(function() return PlayerData:HasItemOfName(ammoType) end)
                if ok and owned then return ammoType end
            end
        end
        return nil
    end

    local function getProjectileOrigin(item)
        local origin = Camera.CFrame.Position
        pcall(function()
            local muzzleOrigin = item:GetShootOrigin()
            if typeof(muzzleOrigin) ~= "Vector3" then return end
            origin = muzzleOrigin
            local root = getMyRoot()
            if root then
                local resolved = SharedProjectiles.ResolveProjectileOrigin(root.Position, muzzleOrigin)
                if typeof(resolved) == "Vector3" then origin = resolved end
            end
        end)
        return origin
    end

    local function getCurrentProjectileConfig()
        local ok, item = pcall(function() return PlayerCharacter:GetEquippedItem() end)
        if not ok or type(item) ~= "table" then
            cachedWeaponItem, cachedWeaponConfig, cachedWeaponFrame = nil, nil, -1
            return nil
        end
        if item == cachedWeaponItem and cachedWeaponFrame == predictionFrame then return cachedWeaponConfig end
        cachedWeaponItem = item
        cachedWeaponFrame = predictionFrame
        cachedWeaponConfig = nil
        if item.IsGunItem ~= true or type(item.SharedData) ~= "table" then return nil end

        local shared = item.SharedData
        local ammoType = getEffectiveAmmoType(shared)
        local hipOrFanning = not item.IsAiming or item.IsFanning
        local accuracyModifier = hipOrFanning and (tonumber(shared.FanAccuracy) or 0.75) or 1
        pcall(function()
            accuracyModifier *= tonumber(ProjectileHandler:GetHorseBackAccMod(shared)) or 1
        end)

        local info = {
            ammoType = ammoType,
            accuracy = accuracyModifier,
            isAiming = item.IsAiming == true,
            isFanning = item.IsFanning == true,
        }
        local speed, accuracy = tonumber(shared.ProjectilePower) or 1000, tonumber(shared.ProjectileAccuracy) or 1
        pcall(function()
            local resolvedSpeed, resolvedAccuracy = ProjectileHandler:GetProjectilePowerAndAccuracy("GunProjectile", shared, info)
            if tonumber(resolvedSpeed) then speed = tonumber(resolvedSpeed) end
            if tonumber(resolvedAccuracy) then accuracy = tonumber(resolvedAccuracy) end
        end)
        if speed <= 0 then return nil end

        local gravity = ProjectileHandler.Gravity or Vector3.new(0, -32, 0)
        pcall(function()
            local resolved = ProjectileHandler:GetProjectileGravity(shared, info)
            if typeof(resolved) == "Vector3" then gravity = resolved end
        end)

        local name = tostring(item.Name or shared.ItemType or "Gun")
        cachedWeaponConfig = {
            Name = name,
            AmmoType = ammoType,
            Speed = speed,
            Accuracy = math.clamp(accuracy, 0, 1),
            Gravity = gravity,
            Origin = getProjectileOrigin(item),
            CacheKey = table.concat({name, tostring(ammoType), string.format("%.4f", accuracy)}, "|"),
        }
        return cachedWeaponConfig
    end

    local function getTargetVelocity(target, aimPart)
        local model = getTargetModel(target)
        local motionPart = getRoot(model) or aimPart
        if not motionPart then return Vector3.zero end
        local now = os.clock()
        local position = motionPart.Position
        local lastPosition = lastTargetPositions[target]
        local lastTime = lastTargetTimes[target]
        lastTargetPositions[target] = position
        lastTargetTimes[target] = now
        if not lastPosition or not lastTime then return Vector3.zero end
        local dt = now - lastTime
        if dt <= 0 or dt >= 1 then return Vector3.zero end
        local measured = (position - lastPosition) / dt
        local assembly = motionPart.AssemblyLinearVelocity
        if assembly.Magnitude < 250 then measured = measured:Lerp(assembly, 0.45) end
        local previous = smoothedTargetVelocities[target] or measured
        local smoothed = previous:Lerp(measured, 1 - math.exp(-dt * 12))
        smoothedTargetVelocities[target] = smoothed
        return smoothed
    end

    local function getPredictedPosition(targetPosition, targetVelocity, weaponConfig, shooterPosition)
        if not weaponConfig then return targetPosition, 0 end
        local speed = math.max(weaponConfig.Speed, 1)
        local travelTime = (targetPosition - shooterPosition).Magnitude / speed
        for _ = 1, 5 do
            local futurePosition = targetPosition + targetVelocity * travelTime
            local launchVector = futurePosition - shooterPosition
                - weaponConfig.Gravity * (0.5 * travelTime * travelTime)
            local nextTime = launchVector.Magnitude / speed
            if math.abs(nextTime - travelTime) < 0.0001 then
                travelTime = nextTime
                break
            end
            travelTime = nextTime
        end
        local predicted = targetPosition + targetVelocity * travelTime
            - weaponConfig.Gravity * (0.5 * travelTime * travelTime)
        return predicted, travelTime
    end

    local function getSharedPrediction(target, weaponConfig, aimPart)
        if not target or not weaponConfig or not aimPart then return nil end
        local cached = predictionCache[target]
        if cached and cached.frame == predictionFrame and cached.part == aimPart and cached.weapon == weaponConfig.CacheKey then
            return cached
        end
        local velocity = getTargetVelocity(target, aimPart)
        local predicted, travelTime = getPredictedPosition(aimPart.Position, velocity, weaponConfig, weaponConfig.Origin)
        cached = {frame = predictionFrame, part = aimPart, weapon = weaponConfig.CacheKey, position = predicted, travelTime = travelTime}
        predictionCache[target] = cached
        return cached
    end

    local function getSpreadCenter(spread)
        if type(spread) ~= "table" then return nil end
        local sum = Vector3.zero
        local count = 0
        for _, velocity in ipairs(spread) do
            if typeof(velocity) == "Vector3" and velocity.Magnitude > 0 then
                sum += velocity.Unit
                count += 1
            end
        end
        if count == 0 or sum.Magnitude <= 1e-6 then return nil end
        return sum.Unit
    end

    local function rotateSpreadInput(inputDirection, actualDirection, desiredDirection)
        local dot = math.clamp(actualDirection:Dot(desiredDirection), -1, 1)
        local axis = actualDirection:Cross(desiredDirection)
        if dot >= 0.999999 or axis.Magnitude <= 1e-6 then return inputDirection end
        return CFrame.fromAxisAngle(axis.Unit, math.acos(dot)):VectorToWorldSpace(inputDirection).Unit
    end

    local function solveExactSeedDirection(projectileType, shared, info, numProjectiles, desiredDirection)
        if not originalGetProjectileSpread or type(info) ~= "table" then return nil end
        local corrected = desiredDirection.Unit
        for _ = 1, 2 do
            local probeInfo = table.clone(info)
            probeInfo.direction = corrected
            local ok, spread = pcall(originalGetProjectileSpread, ProjectileHandler, projectileType, shared, probeInfo, numProjectiles)
            if not ok then return nil end
            local center = getSpreadCenter(spread)
            if not center then return nil end
            corrected = rotateSpreadInput(corrected, center, desiredDirection)
        end
        return corrected
    end

    local function installExactSeedHook()
        if type(hookfunction) ~= "function" or type(ProjectileHandler.GetProjectileSpread) ~= "function" then return end
        seedHookTarget = ProjectileHandler.GetProjectileSpread
        local original
        original = hookfunction(seedHookTarget, function(self, projectileType, shared, info, numProjectiles)
            if self ~= ProjectileHandler or type(info) ~= "table" then
                return original(self, projectileType, shared, info, numProjectiles)
            end

            if info.seed ~= nil then
                State.LastProjectileSeed = info.seed
                State.LastProjectileSeedTime = os.clock()
            end

            local solution = latestAimSolution
            if State.ExactSeedCorrection and State.AimPrediction and State.AimEngaged
                and solution and os.clock() - solution.updatedAt <= 0.15
                and typeof(solution.direction) == "Vector3" and solution.direction.Magnitude > 0 then
                local corrected = solveExactSeedDirection(projectileType, shared, info, numProjectiles, solution.direction)
                if corrected then
                    local correctedInfo = table.clone(info)
                    correctedInfo.direction = corrected
                    State.LastSeedCorrectionApplied = true
                    return original(self, projectileType, shared, correctedInfo, numProjectiles)
                end
            end

            State.LastSeedCorrectionApplied = false
            return original(self, projectileType, shared, info, numProjectiles)
        end)
        originalGetProjectileSpread = original
        seedHookInstalled = true
    end

    installExactSeedHook()

    local function getWeaponAdjustedAimPart(target, part, weaponConfig)
        if not part or not weaponConfig or State.AimPartMode ~= "Auto Visible" or weaponConfig.Accuracy >= 0.9 then
            return part
        end
        local model = getTargetModel(target)
        if not model then return part end
        local candidates = target:IsA("Player")
            and {"UpperTorso", "LowerTorso", "HumanoidRootPart"}
            or {"Body", "HumanoidRootPart"}
        local visibleStates = nil
        if State.AimVisibleCheck then
            local _, states = getVisibleState(model)
            visibleStates = states
        end
        for _, partName in ipairs(candidates) do
            local candidate = model:FindFirstChild(partName)
            if candidate and candidate:IsA("BasePart") then
                if not State.AimVisibleCheck or (visibleStates[candidate] and visibleStates[candidate].visible) then
                    return candidate
                end
            end
        end
        return part
    end

    local function aimActive()
        if not State.AutoLock and not State.AnimalAutoLock then return false end
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

    local function validAimTarget(target)
        if not isTargetValid(target) then return false end
        local part = resolveTargetAimPart(target, State.AimVisibleCheck)
        if not part then return false end
        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then return false end
        return (Vector2.new(point.X, point.Y) - Camera.ViewportSize * 0.5).Magnitude <= State.AimFOV
    end

    local function getClosestTarget(includePlayers, includeAnimals)
        local center = Camera.ViewportSize * 0.5
        local best, bestDistance = nil, math.huge
        local weaponConfig = getCurrentProjectileConfig()

        local function getTargetScreenDistance(target, part)
            part = getWeaponAdjustedAimPart(target, part, weaponConfig)
            local aimPosition = part.Position
            if State.AimPrediction and weaponConfig then
                local sample = getSharedPrediction(target, weaponConfig, part)
                if sample then aimPosition = sample.position end
            end
            local targetPoint, targetOnScreen = Camera:WorldToViewportPoint(aimPosition)
            if not targetOnScreen or targetPoint.Z <= 0 then return nil end
            return (Vector2.new(targetPoint.X, targetPoint.Y) - center).Magnitude
        end

        if includePlayers then
            for _, player in ipairs(Players:GetPlayers()) do
                if not isTargetPlayer(player) then continue end
                local model = getPlayerModel(player)
                local reference = model and (model:FindFirstChild("Head") or model:FindFirstChild("UpperTorso") or getRoot(model))
                if not reference then continue end
                local point, onScreen = Camera:WorldToViewportPoint(reference.Position)
                if not onScreen or point.Z <= 0 then continue end
                local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
                if distance > State.AimFOV + AIM_PREFILTER_MARGIN then continue end
                local part = resolveTargetAimPart(player, State.AimVisibleCheck)
                if not part then continue end
                local targetDistance = getTargetScreenDistance(player, part)
                if targetDistance and targetDistance <= State.AimFOV and targetDistance < bestDistance then
                    best, bestDistance = player, targetDistance
                end
            end
        end

        if includeAnimals and animalFolder then
            for _, animal in ipairs(animalFolder:GetChildren()) do
                if not isTargetAnimal(animal) then continue end
                local reference = animal:FindFirstChild("Head") or animal:FindFirstChild("HumanoidRootPart") or getBasePart(animal)
                if not reference then continue end
                local point, onScreen = Camera:WorldToViewportPoint(reference.Position)
                if not onScreen or point.Z <= 0 then continue end
                local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
                if distance > State.AimFOV + AIM_PREFILTER_MARGIN then continue end
                local part = resolveTargetAimPart(animal, State.AimVisibleCheck)
                if not part then continue end
                local targetDistance = getTargetScreenDistance(animal, part)
                if targetDistance and targetDistance <= State.AimFOV and targetDistance < bestDistance then
                    best, bestDistance = animal, targetDistance
                end
            end
        end
        return best
    end

    local function clearAimState()
        State.AimEngaged = false
        State.AimLockedPart = nil
        State.AimLockedPlayer = nil
        latestAimSolution = nil
    end

    local function updateAutoLock(dt)
        if not aimActive() then
            lockedTarget = nil
            clearAimState()
            return
        end
        if not State.StickyTarget or not validAimTarget(lockedTarget) then
            lockedTarget = getClosestTarget(State.AutoLock, State.AnimalAutoLock)
        end
        if not lockedTarget then
            clearAimState()
            return
        end
        local part = resolveTargetAimPart(lockedTarget, State.AimVisibleCheck)
        if not part then
            lockedTarget = nil
            clearAimState()
            return
        end

        local weaponConfig = getCurrentProjectileConfig()
        part = getWeaponAdjustedAimPart(lockedTarget, part, weaponConfig)
        local aimPosition = part.Position
        if State.AimPrediction and weaponConfig then
            local sample = getSharedPrediction(lockedTarget, weaponConfig, part)
            if sample then aimPosition = sample.position end
        end
        if State.AimPrediction and weaponConfig then
            local launchVector = aimPosition - weaponConfig.Origin
            if launchVector.Magnitude > 1e-3 then
                latestAimSolution = {
                    direction = launchVector.Unit,
                    updatedAt = os.clock(),
                    weapon = weaponConfig.CacheKey,
                    target = lockedTarget,
                }
            end
        else
            latestAimSolution = nil
        end
        local center = Camera.ViewportSize * 0.5
        local point, onScreen = Camera:WorldToViewportPoint(aimPosition)
        if not onScreen or point.Z <= 0 then
            lockedTarget = nil
            clearAimState()
            return
        end
        local delta = Vector2.new(point.X, point.Y) - center
        local response = getAimResponse(delta.Magnitude)
        local alpha = math.clamp(1 - math.exp(-response * math.max(dt or 1 / 60, 1 / 240)), 0, 1)

        if type(mousemoverel) == "function" then
            pcall(mousemoverel, delta.X * alpha, delta.Y * alpha)
        else
            local desired = CFrame.lookAt(Camera.CFrame.Position, aimPosition, Camera.CFrame.UpVector)
            Camera.CFrame = Camera.CFrame:Lerp(desired, alpha)
        end

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

    local predictionDot = Drawing.new("Circle")
    predictionDot.Filled = true
    predictionDot.Thickness = 1
    predictionDot.Transparency = 0.9
    predictionDot.Color = Color3.fromRGB(100, 255, 140)
    predictionDot.Visible = false

    local function updateAimPrediction()
        predictionDot.Visible = false
        if not State.AimPrediction then return end
        local target = lockedTarget
        if not target or not validAimTarget(target) then
            target = getClosestTarget(true, State.AnimalAutoLock)
        end
        if not target then return end
        local part = resolveTargetAimPart(target, State.AimVisibleCheck)
        local weaponConfig = getCurrentProjectileConfig()
        part = getWeaponAdjustedAimPart(target, part, weaponConfig)
        local sample = getSharedPrediction(target, weaponConfig, part)
        if not sample then return end
        local point, onScreen = Camera:WorldToViewportPoint(sample.position)
        if not onScreen or point.Z <= 0 then return end
        predictionDot.Position = Vector2.new(point.X, point.Y)
        predictionDot.Radius = State.PredictDotSize
        predictionDot.Visible = true
    end

    local PlayerESPObjects = {}
    local EntityESPObjects = {animals = {}, loot = {}, ore = {}}
    local PLAYER_ESP_UPDATE_INTERVAL = 0.5
    local WORLD_ESP_UPDATE_INTERVAL = 0.75

    local function createEntityESP(group, key, owner, part, color)
        if group[key] or not owner or not part then return end
        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenWildWestEntityHighlight"
        highlight.FillTransparency = 0.82
        highlight.OutlineTransparency = 0.15
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.Enabled = false
        highlight.Parent = owner

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenWildWestEntityBillboard"
        billboard.Size = UDim2.new(0, 190, 0, 24)
        billboard.StudsOffset = Vector3.new(0, 2.6, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false
        billboard.Parent = part

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.25
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextScaled = false
        label.TextSize = 12
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard

        group[key] = {highlight = highlight, billboard = billboard, label = label}
    end

    local function removeEntityESP(group, key)
        local esp = group[key]
        if not esp then return end
        pcall(function() esp.highlight:Destroy() end)
        pcall(function() esp.billboard:Destroy() end)
        group[key] = nil
    end

    local function clearEntityGroup(group)
        for key in pairs(group) do removeEntityESP(group, key) end
    end

    local function updateEntityESP(group, key, owner, part, label, color)
        if not group[key] then createEntityESP(group, key, owner, part, color) end
        local esp = group[key]
        if not esp or not esp.highlight.Parent or not esp.billboard.Parent then return end
        esp.highlight.FillColor = color
        esp.highlight.OutlineColor = color
        esp.highlight.Enabled = true
        esp.billboard.Enabled = true
        esp.label.TextColor3 = color
        esp.label.Text = label
    end

    local function createPlayerESP(player, model, adornee)
        if PlayerESPObjects[player] or not model or not adornee then return end
        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenWildWestHighlight"
        highlight.FillTransparency = 0.76
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Enabled = false
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenWildWestBillboard"
        billboard.Size = UDim2.new(0, 210, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 3.15, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false
        billboard.Parent = adornee

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextScaled = false
        nameLabel.TextSize = 14
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Parent = billboard

        local infoLabel = Instance.new("TextLabel")
        infoLabel.Size = UDim2.new(1, 0, 0.45, 0)
        infoLabel.Position = UDim2.new(0, 0, 0.55, 0)
        infoLabel.BackgroundTransparency = 1
        infoLabel.TextStrokeTransparency = 0.25
        infoLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        infoLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
        infoLabel.TextScaled = false
        infoLabel.TextSize = 12
        infoLabel.Font = Enum.Font.Gotham
        infoLabel.Parent = billboard

        PlayerESPObjects[player] = {
            highlight = highlight,
            billboard = billboard,
            nameLabel = nameLabel,
            infoLabel = infoLabel,
        }
    end

    local function removePlayerESP(player)
        local esp = PlayerESPObjects[player]
        if not esp then return end
        pcall(function() esp.highlight:Destroy() end)
        pcall(function() esp.billboard:Destroy() end)
        PlayerESPObjects[player] = nil
    end

    local function clearPlayerESP()
        for player in pairs(PlayerESPObjects) do removePlayerESP(player) end
    end

    local function updatePlayerESP()
        if not State.PlayerESP then clearPlayerESP() return end

        local myRoot = getMyRoot()
        local active = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP then
                local model = getPlayerModel(player)
                local humanoid = getHumanoid(model)
                local root = getRoot(model)
                local adornee = model and (model:FindFirstChild("Head") or root)
                if model and humanoid and humanoid.Health > 0 and root and adornee and myRoot then
                    local distance = (myRoot.Position - root.Position).Magnitude
                    if distance <= State.PlayerESPDistance then
                        if not PlayerESPObjects[player] then createPlayerESP(player, model, adornee) end
                        local esp = PlayerESPObjects[player]
                        if esp and esp.highlight.Parent and esp.billboard.Parent then
                            active[player] = true
                            local roleLabel, roleColor = getRoleLabel(player)
                            local factionName, factionTag = getFactionInfo(player)
                            local factionText = factionTag or factionName
                            local sameFaction = isSameFaction(player)
                            local title = player.DisplayName
                            if State.PlayerESPShowRole then title ..= " [" .. roleLabel .. "]" end
                            if State.PlayerESPShowFaction and factionText then title ..= " [" .. factionText .. "]" end
                            esp.highlight.FillColor = roleColor
                            esp.highlight.OutlineColor = sameFaction and Color3.fromRGB(80, 255, 120) or roleColor
                            esp.highlight.Enabled = true
                            esp.billboard.Enabled = true
                            esp.nameLabel.TextColor3 = roleColor
                            esp.nameLabel.Text = title
                            esp.infoLabel.Text = string.format("%.0fm | HP %.0f%s", distance, humanoid.Health, sameFaction and " | ALLY" or "")
                        end
                    end
                end
            end
        end

        for player in pairs(PlayerESPObjects) do
            if not active[player] then removePlayerESP(player) end
        end
    end

    local function updateAnimalESP()
        local group = EntityESPObjects.animals
        if not State.AnimalESP or not animalFolder then clearEntityGroup(group) return end
        local myRoot = getMyRoot()
        if not myRoot then return end
        local active = {}
        for _, animal in ipairs(animalFolder:GetChildren()) do
            local part = animal:FindFirstChild("Head") or animal:FindFirstChild("HumanoidRootPart") or getBasePart(animal)
            if part and (part.Position - myRoot.Position).Magnitude <= State.AnimalESPDistance then
                local health = animal:FindFirstChild("Health")
                local anger = animal:FindFirstChild("Anger")
                local label = animal.Name
                if health then label ..= string.format(" | HP %.0f", tonumber(health.Value) or 0) end
                if anger and tonumber(anger.Value) and tonumber(anger.Value) > 0 then label ..= " | HOSTILE" end
                updateEntityESP(group, animal, animal, part, label, Color3.fromRGB(255, 210, 90))
                active[animal] = true
            end
        end
        for key in pairs(group) do if not active[key] then removeEntityESP(group, key) end end
    end

    local function updateLootESP()
        local group = EntityESPObjects.loot
        if not State.LootESP or not lootFolder then clearEntityGroup(group) return end
        local myRoot = getMyRoot()
        if not myRoot then return end
        local active = {}
        for _, chest in ipairs(CollectionService:GetTagged("LootChest")) do
            if chest:IsDescendantOf(lootFolder) then
                local state = chest:GetAttribute("State")
                if not State.LootAvailableOnly or state == "Available" then
                    local part = getBasePart(chest)
                    if part and (part.Position - myRoot.Position).Magnitude <= State.LootESPDistance then
                        local lootTable = chest:GetAttribute("LootTable") or chest.Name
                        updateEntityESP(group, chest, chest, part, tostring(lootTable) .. " [" .. tostring(state or "?") .. "]", Color3.fromRGB(100, 255, 150))
                        active[chest] = true
                    end
                end
            end
        end
        for key in pairs(group) do if not active[key] then removeEntityESP(group, key) end end
    end

    local function updateOreESP()
        local group = EntityESPObjects.ore
        if not State.OreESP or not oreDeposits then clearEntityGroup(group) return end
        local myRoot = getMyRoot()
        if not myRoot then return end
        local active = {}
        for _, typeFolder in ipairs(oreDeposits:GetChildren()) do
            for _, deposit in ipairs(typeFolder:GetChildren()) do
                local part = getBasePart(deposit)
                if part and (part.Position - myRoot.Position).Magnitude <= State.OreESPDistance then
                    local oreRemaining = deposit:FindFirstChild("OreRemaining", true)
                    local label = typeFolder.Name
                    if oreRemaining then label ..= string.format(" | %.0f", tonumber(oreRemaining.Value) or 0) end
                    updateEntityESP(group, deposit, deposit, part, label, Color3.fromRGB(120, 200, 255))
                    active[deposit] = true
                end
            end
        end
        for key in pairs(group) do if not active[key] then removeEntityESP(group, key) end end
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

    local playerEspAccumulator = 0
    local worldEspAccumulator = 0
    local renderStepName = "RavenWildWest_" .. tostring(LP.UserId)
    RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Camera.Value + 10, function(dt)
        visibilityFrame += 1
        predictionFrame += 1
        updateAutoLock(dt)
        updateAimPrediction()
        aimCircle.Position = Camera.ViewportSize * 0.5
        aimCircle.Radius = State.AimFOV
        aimCircle.Visible = State.AutoLock or State.AnimalAutoLock
        if State.FOVEnabled then Camera.FieldOfView = State.FOVValue end

        playerEspAccumulator += dt
        if playerEspAccumulator >= PLAYER_ESP_UPDATE_INTERVAL then
            playerEspAccumulator = 0
            updatePlayerESP()
        end

        worldEspAccumulator += dt
        if worldEspAccumulator >= WORLD_ESP_UPDATE_INTERVAL then
            worldEspAccumulator = 0
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
    CombatTab:CreateSection("Aim Prediction")
    CombatTab:CreateToggle({Name="Enable Aim Prediction",CurrentValue=false,Flag="WildWestAimPrediction",Callback=function(v) State.AimPrediction = v == true end})
    CombatTab:CreateToggle({Name="Exact Projectile Seed Correction",CurrentValue=false,Flag="WildWestExactSeed",Callback=function(v) State.ExactSeedCorrection = v == true end})
    CombatTab:CreateSlider({Name="Prediction Dot Size",Range={2,14},Increment=1,CurrentValue=6,Suffix=" px",Flag="WildWestPredictDotSize",Callback=function(v) State.PredictDotSize = v end})
    CombatTab:CreateLabel("Uses live weapon/ammo power, gravity, fanning and muzzle origin")
    CombatTab:CreateLabel("Exact Seed centers the real seeded spread pattern on the ballistic solution")
    CombatTab:CreateLabel("Auto Visible prefers center mass when weapon accuracy is below 90%")
    CombatTab:CreateSection("Smooth Auto Lock")
    CombatTab:CreateToggle({Name="Player Auto Lock",CurrentValue=false,Flag="WildWestAutoLock",Callback=function(v)
        State.AutoLock = v == true
        if not State.AutoLock then lockedTarget = nil end
    end})
    CombatTab:CreateToggle({Name="Animal Auto Lock",CurrentValue=false,Flag="WildWestAnimalAutoLock",Callback=function(v)
        State.AnimalAutoLock = v == true
        lockedTarget = nil
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
    CombatTab:CreateToggle({Name="Ignore Same Team",CurrentValue=true,Flag="WildWestIgnoreTeam",Callback=function(v)
        State.IgnoreSameTeam = v == true
        lockedTarget = nil
    end})
    CombatTab:CreateToggle({Name="Ignore Same Faction",CurrentValue=true,Flag="WildWestIgnoreFaction",Callback=function(v)
        State.IgnoreSameFaction = v == true
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
    EspTab:CreateSection("Player")
    EspTab:CreateToggle({Name="Player ESP",CurrentValue=false,Flag="WildWestPlayerESP",Callback=function(v) State.PlayerESP = v == true end})
    EspTab:CreateToggle({Name="Show Role",CurrentValue=true,Flag="WildWestPlayerRole",Callback=function(v) State.PlayerESPShowRole = v == true end})
    EspTab:CreateToggle({Name="Show Faction",CurrentValue=true,Flag="WildWestPlayerFaction",Callback=function(v) State.PlayerESPShowFaction = v == true end})
    EspTab:CreateSlider({Name="Player ESP Distance",Range={100,5000},Increment=100,CurrentValue=1800,Suffix=" studs",Flag="WildWestPlayerESPRange",Callback=function(v) State.PlayerESPDistance = v end})

    EspTab:CreateSection("Animal")
    EspTab:CreateToggle({Name="Animal ESP",CurrentValue=false,Flag="WildWestAnimalESP",Callback=function(v) State.AnimalESP = v == true end})
    EspTab:CreateSlider({Name="Animal ESP Distance",Range={100,3000},Increment=100,CurrentValue=900,Suffix=" studs",Flag="WildWestAnimalESPRange",Callback=function(v) State.AnimalESPDistance = v end})

    EspTab:CreateSection("Chest")
    EspTab:CreateToggle({Name="Loot Chest ESP",CurrentValue=false,Flag="WildWestLootESP",Callback=function(v) State.LootESP = v == true end})
    EspTab:CreateToggle({Name="Available Chests Only",CurrentValue=true,Flag="WildWestLootAvailable",Callback=function(v) State.LootAvailableOnly = v == true end})
    EspTab:CreateSlider({Name="Chest ESP Distance",Range={100,3000},Increment=100,CurrentValue=1200,Suffix=" studs",Flag="WildWestLootESPRange",Callback=function(v) State.LootESPDistance = v end})

    EspTab:CreateSection("Ore")
    EspTab:CreateToggle({Name="Ore ESP",CurrentValue=false,Flag="WildWestOreESP",Callback=function(v) State.OreESP = v == true end})
    EspTab:CreateSlider({Name="Ore ESP Distance",Range={100,3000},Increment=100,CurrentValue=1200,Suffix=" studs",Flag="WildWestOreESPRange",Callback=function(v) State.OreESPDistance = v end})

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
        pcall(function() predictionDot:Remove() end)
        if seedHookInstalled and seedHookTarget and originalGetProjectileSpread and type(hookfunction) == "function" then
            pcall(hookfunction, seedHookTarget, originalGetProjectileSpread)
            seedHookInstalled = false
        end
        clearPlayerESP()
        clearEntityGroup(EntityESPObjects.animals)
        clearEntityGroup(EntityESPObjects.loot)
        clearEntityGroup(EntityESPObjects.ore)
        applyFullbright(false)
        applyNoFog(false)
        Camera.FieldOfView = OriginalFOV
        if getgenv().__RAVEN_THE_WILD_WEST and getgenv().__RAVEN_THE_WILD_WEST.State == State then
            getgenv().__RAVEN_THE_WILD_WEST = nil
        end
    end

    getgenv().__RAVEN_THE_WILD_WEST = {Version="v0.1.5",State=State,Destroy=destroy}
    if runtimeInfo and runtimeInfo.registerCleanup then runtimeInfo.registerCleanup(destroy) end
end
