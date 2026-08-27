--[[
    RAVEN HUB Module - The Wild West v0.1.18
    Game: The Wild West (PlaceId: 2317712696, GameId: 807930589)
    Developer: Starboard Studios

    Features:
    - FPS-safe Smooth Auto Lock for replicated player models
    - Player / Animal / Loot Chest / Ore / Dropped Item ESP
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
    local Ragdolls = require(CharacterModules:WaitForChild("Ragdolls"))
    local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
    local ProjectileModule = SharedModules:WaitForChild("World"):WaitForChild("ProjectileHandler")
    local ProjectileHandler = require(ProjectileModule)
    local SharedProjectiles = require(ProjectileModule:WaitForChild("SharedProjectiles"))
    local Global = require(SharedModules:WaitForChild("Global"))
    local Network = Global.Network
    local SyncedTime = Global.SyncedTime
    local Hotbar = nil
    pcall(function() Hotbar = Global.LoadModule("Hotbar") end)

    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera
    local entitiesRoot = workspace:FindFirstChild("WORKSPACE_Entities")
    local interactablesRoot = workspace:FindFirstChild("WORKSPACE_Interactables")
    local playerModels = entitiesRoot and entitiesRoot:FindFirstChild("Players")
    local animalFolder = entitiesRoot and entitiesRoot:FindFirstChild("Animals")
    local lootFolder = interactablesRoot and interactablesRoot:FindFirstChild("LootChests")
    local droppedItemsFolder = interactablesRoot and interactablesRoot:FindFirstChild("DroppedItems")
    local miningFolder = interactablesRoot and interactablesRoot:FindFirstChild("Mining")
    local oreDeposits = miningFolder and miningFolder:FindFirstChild("OreDeposits")

    local State = {
        AutoLock = false,
        AnimalAutoLock = false,
        AimPrediction = false,
        ExactSeedCapture = false,
        LastProjectileSeed = nil,
        PredictDotSize = 6,
        AimActivation = "Right Mouse",
        AimFOV = 180,
        AimSmoothness = 0.18,
        AdaptiveSmoothness = true,
        PredictionLeadScale = 1,
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
        ItemESP = false,
        ItemESPDistance = 1200,
        ItemESPSelected = {},
        AutoRespawn = false,
        RespawnLocation = "CanyonCamp",
        AutoGetUp = false,
        AutoBreakFree = false,
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 90,
        NoRecoil = false,
        NoSpread = false,
        NoSpreadHookActive = false,
        SilentAim = false,
        SilentAimFOV = 180,
        SilentAimPart = "Head",
    }

    local Connections = {}
    local rightMouseDown = false
    local lockedTarget = nil
    local lockedAimPart = nil
    local lockedTargetLostAt = nil
    local destroyed = false
    local predictionFrame = 0
    local predictionCache = {}
    local lastTargetPositions = {}
    local lastTargetTimes = {}
    local smoothedTargetVelocities = {}
    local cachedWeaponItem = nil
    local cachedWeaponConfig = nil
    local cachedWeaponFrame = -1
    local originalGenerateProjectileSeed = nil
    local seedHookTarget = nil
    local seedHookInstalled = false
    local originalAddRecoil = nil
    local recoilHookTarget = nil
    local recoilHookInstalled = false
    local originalGetProjectileSpread = nil
    local spreadHookTarget = nil
    local spreadHookInstalled = false
    local silentAimLastTarget = nil
    local cachedSilentAimTarget = nil
    local originalInitProjectiles = nil
    local initProjectilesHookTarget = nil
    local initProjectilesHookInstalled = false
    local initProjectilesHookRecursion = false
    local playersData = {}
    local RECOVERY_UPDATE_INTERVAL = 0.08
    local GET_UP_COOLDOWN = 1.5
    local BREAK_FREE_INTERVAL = 0.12
    local RESPAWN_UPDATE_INTERVAL = 0.2
    local RESPAWN_RETRY_INTERVAL = 2
    local RESPAWN_STREAM_FALLBACK_WAIT = 0.8
    local recoveryAccumulator = 0
    local respawnAccumulator = 0
    local lastRespawnTrigger = -math.huge
    local lastRespawnAttempt = -math.huge
    local respawnStreamRequestedAt = -math.huge
    local respawnStreamLocation = nil
    local respawnAcceptedThisDeath = false
    local getUpAttemptedThisFall = false
    local lastGetUpAttempt = -math.huge
    local lastBreakFreeAttempt = -math.huge
    local OriginalLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        GlobalShadows = Lighting.GlobalShadows,
        ExposureCompensation = Lighting.ExposureCompensation,
        EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
        EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
    }
    local OriginalFOV = Camera.FieldOfView
    local originalAtmospheres = {}
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Atmosphere") then
            originalAtmospheres[child] = {
                Density = child.Density,
                Haze = child.Haze,
                Glare = child.Glare,
                Offset = child.Offset,
            }
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
    local AUTO_VISIBLE_SCAN_INTERVAL = 1
    local LOCK_GRACE_DURATION = 0.2
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

    local function scanAutoVisibleParts(fromPos, targetModel, parts, cached, completeScan)
        cached.parts = cached.parts or {}
        if not completeScan and cached.lastScan and visibilityFrame - cached.lastScan < AUTO_VISIBLE_SCAN_INTERVAL then
            cached.frame = visibilityFrame
            visibilityCache[targetModel] = cached
            return cached.visible or false, cached.parts, cached.priorityPart
        end
        cached.lastScan = visibilityFrame

        local scanCount = completeScan and #parts or math.min(AUTO_VISIBLE_PARTS_PER_SCAN, #parts)
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

    local function getVisibleState(targetModel, completeScan)
        if not targetModel then return false, {}, nil end
        local cached = visibilityCache[targetModel]
        if cached and cached.frame == visibilityFrame then
            return cached.visible or false, cached.parts or {}, cached.priorityPart
        end
        local parts = getAimParts(targetModel)
        if #parts == 0 then return false, {}, nil end
        cached = cached or {parts = {}, partIndex = 1}
        return scanAutoVisibleParts(Camera.CFrame.Position, targetModel, parts, cached, completeScan == true)
    end

    local function resolveModelAimPart(model, preferredName, requireVisible, completeScan)
        if not model then return nil end
        local preferred = model:FindFirstChild(preferredName or State.AimTargetPart)
            or model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or getBasePart(model)
        if not requireVisible then return preferred end
        local _, states, priorityPart = getVisibleState(model, completeScan)
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

    local function resolveTargetAimPart(target, requireVisible, completeScan)
        if not target then return nil end
        if target:IsA("Player") then
            return resolveModelAimPart(getPlayerModel(target), State.AimTargetPart, requireVisible, completeScan)
        end
        return resolveModelAimPart(target, "Head", requireVisible, completeScan)
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
            local futurePosition = targetPosition + targetVelocity * travelTime * math.max(0, State.PredictionLeadScale)
            local launchVector = futurePosition - shooterPosition
                - weaponConfig.Gravity * (0.5 * travelTime * travelTime)
            local nextTime = launchVector.Magnitude / speed
            if math.abs(nextTime - travelTime) < 0.0001 then
                travelTime = nextTime
                break
            end
            travelTime = nextTime
        end
        local predicted = targetPosition + targetVelocity * travelTime * math.max(0, State.PredictionLeadScale)
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

    local function installExactSeedHook()
        if type(hookfunction) ~= "function" or type(ProjectileHandler.GenerateProjectileSeed) ~= "function" then return end
        seedHookTarget = ProjectileHandler.GenerateProjectileSeed
        local original
        original = hookfunction(seedHookTarget, function(self, ...)
            local seed = original(self, ...)
            if self == ProjectileHandler and State.ExactSeedCapture then
                State.LastProjectileSeed = seed
                State.LastProjectileSeedTime = os.clock()
            end
            return seed
        end)
        originalGenerateProjectileSeed = original
        seedHookInstalled = true
    end

    installExactSeedHook()

    local function installNoRecoilHook()
        if type(hookfunction) ~= "function" then return end
        local CharacterModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Character")
        local ok, CameraModule = pcall(function() return require(CharacterModules:WaitForChild("Camera")) end)
        if not ok or type(CameraModule) ~= "table" then return end
        if type(CameraModule.AddRecoil) ~= "function" then return end
        recoilHookTarget = CameraModule.AddRecoil
        local original
        original = hookfunction(recoilHookTarget, function(self, ...)
            if State.NoRecoil then return end
            return original(self, ...)
        end)
        originalAddRecoil = original
        recoilHookInstalled = true
    end

    installNoRecoilHook()

    local function getSilentAimTarget()
        if not State.SilentAim then return nil end
        local weaponConfig = getCurrentProjectileConfig()
        -- Try full pipeline first
        local target = getClosestTarget(State.AutoLock or true, State.AnimalAutoLock)
        if not target then
            -- Fallback: find closest on-screen target without visibility check
            local center = Camera.ViewportSize * 0.5
            local bestDist = State.SilentAimFOV
            do
                for _, player in ipairs(Players:GetPlayers()) do
                    if player == LP then continue end
                    if State.IgnoreSameTeam and isSameTeam(player) then continue end
                    if State.IgnoreSameFaction and isSameFaction(player) then continue end
                    local model = getPlayerModel(player)
                    local hum = getHumanoid(model)
                    if not model or not hum or hum.Health <= 0 then continue end
                    local ref = model:FindFirstChild("Head") or getRoot(model)
                    if not ref then continue end
                    local pt, ok = Camera:WorldToViewportPoint(ref.Position)
                    if not ok or pt.Z <= 0 then continue end
                    local d = (Vector2.new(pt.X, pt.Y) - center).Magnitude
                    if d < bestDist then bestDist = d; target = player end
                end
            end
            if State.AnimalAutoLock and animalFolder then
                for _, animal in ipairs(animalFolder:GetChildren()) do
                    if not isTargetAnimal(animal) then continue end
                    local ref = animal:FindFirstChild("Head") or animal:FindFirstChild("HumanoidRootPart") or getBasePart(animal)
                    if not ref then continue end
                    local pt, ok = Camera:WorldToViewportPoint(ref.Position)
                    if not ok or pt.Z <= 0 then continue end
                    local d = (Vector2.new(pt.X, pt.Y) - center).Magnitude
                    if d < bestDist then bestDist = d; target = animal end
                end
            end
        end
        if not target then return nil end
        local model = getTargetModel(target)
        if not model then return nil end
        local part = model:FindFirstChild(State.SilentAimPart) or model:FindFirstChild("Head") or getBasePart(model)
        if not part then return nil end
        local aimPosition = part.Position
        if State.AimPrediction and weaponConfig then
            local sample = getSharedPrediction(target, weaponConfig, part)
            if sample then aimPosition = sample.position end
        end
        local point, onScreen = Camera:WorldToViewportPoint(aimPosition)
        if not onScreen or point.Z <= 0 then return nil end
        local screenCenter = Camera.ViewportSize * 0.5
        local dist = (Vector2.new(point.X, point.Y) - screenCenter).Magnitude
        if dist > State.SilentAimFOV then return nil end
        return aimPosition
    end

    local function adjustProjectileDirection(result, projectileType, projectileData, sharedData)
        if type(result) ~= "table" or type(projectileData) ~= "table" then return result end
        if projectileType ~= "GunProjectile" and projectileType ~= "ServerGunProjectile"
            and projectileType ~= "DartProjectile" and projectileType ~= "SnowballProjectile"
            and projectileType ~= "GatlingProjectile" then
            return result
        end

        local direction = projectileData.direction
        if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.0001 then return result end
        local unitDirection = direction.Unit
        local flattened = {}
        local changed = false
        for key, velocity in pairs(result) do
            if typeof(velocity) == "Vector3" and velocity.Magnitude > 0.0001 then
                flattened[key] = unitDirection * velocity.Magnitude
                changed = true
            else
                flattened[key] = velocity
            end
        end
        return changed and flattened or result
    end

    local function restoreNoSpreadHook()
        if spreadHookInstalled and spreadHookTarget and originalGetProjectileSpread and type(hookfunction) == "function" then
            pcall(hookfunction, spreadHookTarget, originalGetProjectileSpread)
        end
        spreadHookTarget = nil
        originalGetProjectileSpread = nil
        spreadHookInstalled = false
        State.NoSpreadHookActive = false
    end

    local function installSpreadHook()
        if type(hookfunction) ~= "function" then return end
        local target = ProjectileHandler.GetProjectileSpread
        if type(target) ~= "function" then return end
        if spreadHookInstalled and spreadHookTarget == target then return end
        if spreadHookInstalled then restoreNoSpreadHook() end

        local original
        local ok = pcall(function()
            original = hookfunction(target, function(self, projectileType, sharedData, projectileData, projectileCount, ...)
                local result = original(self, projectileType, sharedData, projectileData, projectileCount, ...)
                if not State.NoSpread then return result end
                return adjustProjectileDirection(result, projectileType, projectileData, sharedData)
            end)
        end)
        if not ok or type(original) ~= "function" then
            spreadHookTarget = nil
            originalGetProjectileSpread = nil
            spreadHookInstalled = false
            State.NoSpreadHookActive = false
            return
        end
        spreadHookTarget = target
        originalGetProjectileSpread = original
        spreadHookInstalled = true
        State.NoSpreadHookActive = true
    end

    installSpreadHook()

    -- Silent Aim: Hook ProjectileHandler.InitProjectiles to redirect bullet direction
    -- This is the correct hook point - modifies info.accuracy + info.direction
    -- BEFORE the projectile is processed, so server sees consistent data.
    local function restoreInitProjectilesHook()
        if initProjectilesHookInstalled and initProjectilesHookTarget and originalInitProjectiles and type(hookfunction) == "function" then
            pcall(hookfunction, initProjectilesHookTarget, originalInitProjectiles)
        end
        initProjectilesHookTarget = nil
        originalInitProjectiles = nil
        initProjectilesHookInstalled = false
    end

    local function getInitProjectilesTarget()
        -- Try direct access first
        if type(ProjectileHandler.InitProjectiles) == "function" then
            return ProjectileHandler.InitProjectiles
        end
        -- Try through SharedProjectiles module
        if type(SharedProjectiles.InitProjectiles) == "function" then
            return SharedProjectiles.InitProjectiles
        end
        -- Try scanning upvalues of GetProjectileSpread to find InitProjectiles
        if type(debug) == "table" and type(debug.getupvalues) == "function" then
            local ok, uvs = pcall(debug.getupvalues, ProjectileHandler)
            if ok and type(uvs) == "table" then
                for _, v in pairs(uvs) do
                    if type(v) == "table" then
                        if type(v.InitProjectiles) == "function" then
                            return v.InitProjectiles
                        end
                    end
                end
            end
        end
        return nil
    end

    local function installInitProjectilesHook()
        if type(hookfunction) ~= "function" then return end
        if initProjectilesHookInstalled then return end
        local target = getInitProjectilesTarget()
        if not target then return end

        local original
        local ok = pcall(function()
            original = hookfunction(target, function(self, projectileType, sharedData, info, callback, ...)
                -- Recursion guard
                if initProjectilesHookRecursion then
                    return original(self, projectileType, sharedData, info, callback, ...)
                end
                initProjectilesHookRecursion = true
                pcall(function() _G._ravenHookFired = (_G._ravenHookFired or 0) + 1 end)
                local success, err = pcall(function()
                    if State.SilentAim and type(info) == "table" then
                        local targetPos = cachedSilentAimTarget
                        if targetPos and typeof(targetPos) == "Vector3" then
                            local origin = Camera.CFrame.Position
                            local direction = (targetPos - origin)
                            if direction.Magnitude > 0.0001 then
                                info.accuracy = 1  -- Max accuracy = no spread
                                info.direction = direction.Unit  -- Aim at target
                                pcall(function() _G._ravenAimRedirected = (_G._ravenAimRedirected or 0) + 1 end)
                            end
                        end
                    end
                end)
                initProjectilesHookRecursion = false
                if not success then
                    -- Silently ignore errors in hook
                end
                return original(self, projectileType, sharedData, info, callback, ...)
            end)
        end)
        if not ok or type(original) ~= "function" then
            initProjectilesHookTarget = nil
            originalInitProjectiles = nil
            initProjectilesHookInstalled = false
            return
        end
        initProjectilesHookTarget = target
        originalInitProjectiles = original
        initProjectilesHookInstalled = true
    end

    installInitProjectilesHook()

    -- Ban packet protection: block Terrain.Color changes that contain 'Environment' in traceback
    -- This prevents the game from sending ban packets when it detects script interference
    do
        local IsA = game.IsA
        local oldNewIndex
        oldNewIndex = hookmetamethod(game, "__newindex", function(self, p, v)
            if initProjectilesHookRecursion then return oldNewIndex(self, p, v) end
            if IsA(self, "Terrain") and p == "Color" then
                local trace = debug.traceback()
                if trace and string.find(trace, "Environment") then
                    -- Block ban packet
                    return
                end
            end
            return oldNewIndex(self, p, v)
        end)
    end

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
                local part = resolveTargetAimPart(player, State.AimVisibleCheck, true)
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
                local part = resolveTargetAimPart(animal, State.AimVisibleCheck, true)
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
    end

    local function updateAutoLock(dt)
        local now = os.clock()
        if not aimActive() then
            lockedTarget = nil
            lockedAimPart = nil
            lockedTargetLostAt = nil
            clearAimState()
            return
        end

        local targetValid = lockedTarget and validAimTarget(lockedTarget)
        if not targetValid and lockedTarget then
            lockedTargetLostAt = lockedTargetLostAt or now
        end
        if not State.StickyTarget or not lockedTarget
            or (not targetValid and now - (lockedTargetLostAt or now) > LOCK_GRACE_DURATION) then
            lockedTarget = getClosestTarget(State.AutoLock, State.AnimalAutoLock)
            lockedAimPart = nil
            lockedTargetLostAt = nil
        end
        if not lockedTarget then
            clearAimState()
            return
        end
        local part = resolveTargetAimPart(lockedTarget, State.AimVisibleCheck)
        if not part and lockedAimPart and lockedAimPart.Parent and lockedTargetLostAt
            and now - lockedTargetLostAt <= LOCK_GRACE_DURATION then
            part = lockedAimPart
        end
        if not part then
            lockedTarget = nil
            lockedAimPart = nil
            lockedTargetLostAt = nil
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
        local center = Camera.ViewportSize * 0.5
        local point, onScreen = Camera:WorldToViewportPoint(aimPosition)
        if not onScreen or point.Z <= 0 then
            lockedTargetLostAt = lockedTargetLostAt or now
            if not lockedAimPart or not lockedAimPart.Parent
                or now - lockedTargetLostAt > LOCK_GRACE_DURATION then
                lockedTarget = nil
                lockedAimPart = nil
                lockedTargetLostAt = nil
                clearAimState()
                return
            end
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
        lockedAimPart = part
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
    local EntityESPObjects = {animals = {}, loot = {}, ore = {}, items = {}}
    local itemFilterOptions = {}
    local itemFilterOptionSet = {}
    local itemFilterDropdown = nil
    local itemFilterOptionsDirty = false
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

    local function addItemFilterOption(value)
        local name = tostring(value or "")
        if name == "" or itemFilterOptionSet[name] then return false end
        itemFilterOptionSet[name] = true
        table.insert(itemFilterOptions, name)
        itemFilterOptionsDirty = true
        return true
    end

    local function seedItemFilterOptions()
        -- PlayerItems contains the authoritative item ids, so the filter is
        -- useful even when no dropped item is currently on the map.
        local sharedData = Global.SharedData
        local playerItems = sharedData and sharedData.PlayerItems
        if type(playerItems) == "table" then
            for itemName, itemData in pairs(playerItems) do
                if type(itemName) == "string" and type(itemData) == "table" then
                    local droppable = itemData.Droppable == true or itemData.Droppable == "true"
                    local loot = itemData.IsLoot == true or itemData.IsLoot == "true"
                    local dropsOnDeath = itemData.DropOnDeath == "Drop"
                    if droppable or loot or dropsOnDeath then addItemFilterOption(itemName) end
                end
            end
        end
        for _, itemName in ipairs({"AnimalMeat", "GatorSkin"}) do addItemFilterOption(itemName) end
        table.sort(itemFilterOptions)
        itemFilterOptionsDirty = false
    end

    local function getDroppedItemName(item)
        if not item then return nil end
        local name = item:GetAttribute("ItemName") or item:GetAttribute("ItemId") or item:GetAttribute("ItemType")
        return tostring(name or item.Name)
    end

    local function isItemSelected(itemName)
        local selected = State.ItemESPSelected
        if type(selected) ~= "table" then return true end
        local hasSelection = false
        for _, value in pairs(selected) do
            if value == true then hasSelection = true break end
        end
        return not hasSelection or selected[itemName] == true
    end

    local function refreshItemFilterOptions()
        if not itemFilterDropdown or not itemFilterOptionsDirty then return end
        table.sort(itemFilterOptions)
        itemFilterDropdown:Refresh(itemFilterOptions, true)
        itemFilterOptionsDirty = false
    end

    local function updateItemESP()
        local group = EntityESPObjects.items
        if not State.ItemESP then clearEntityGroup(group) return end
        local folder = droppedItemsFolder
        if not folder or not folder.Parent then
            interactablesRoot = workspace:FindFirstChild("WORKSPACE_Interactables")
            folder = interactablesRoot and interactablesRoot:FindFirstChild("DroppedItems")
            droppedItemsFolder = folder
        end
        if not folder then clearEntityGroup(group) return end

        local myRoot = getMyRoot()
        if not myRoot then return end
        local active = {}
        for _, item in ipairs(CollectionService:GetTagged("DroppedItem")) do
            if item:IsDescendantOf(folder) then
                local itemName = getDroppedItemName(item)
                if itemName then
                    addItemFilterOption(itemName)
                    local part = item:FindFirstChild("DropCollider", true)
                    if not part or not part:IsA("BasePart") then part = getBasePart(item) end
                    if part and isItemSelected(itemName) and (part.Position - myRoot.Position).Magnitude <= State.ItemESPDistance then
                        local distance = (part.Position - myRoot.Position).Magnitude
                        updateEntityESP(group, item, item, part, string.format("%s | %.0fm", itemName, distance), Color3.fromRGB(255, 190, 90))
                        active[item] = true
                    end
                end
            end
        end
        for key in pairs(group) do if not active[key] then removeEntityESP(group, key) end end
        refreshItemFilterOptions()
    end

    seedItemFilterOptions()

    local function applyFullbright(enabled)
        if enabled then
            Lighting.Brightness = 1.5
            Lighting.ClockTime = 14
            Lighting.Ambient = Color3.fromRGB(200, 200, 200)
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
            Lighting.GlobalShadows = false
            Lighting.ExposureCompensation = 0
            Lighting.EnvironmentDiffuseScale = 1
            Lighting.EnvironmentSpecularScale = 1
        else
            Lighting.Brightness = OriginalLighting.Brightness
            Lighting.ClockTime = OriginalLighting.ClockTime
            Lighting.Ambient = OriginalLighting.Ambient
            Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
            Lighting.GlobalShadows = OriginalLighting.GlobalShadows
            Lighting.ExposureCompensation = OriginalLighting.ExposureCompensation
            Lighting.EnvironmentDiffuseScale = OriginalLighting.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale = OriginalLighting.EnvironmentSpecularScale
        end
    end

    local function applyNoFog(enabled)
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Atmosphere") and not originalAtmospheres[child] then
                originalAtmospheres[child] = {
                    Density = child.Density,
                    Haze = child.Haze,
                    Glare = child.Glare,
                    Offset = child.Offset,
                }
            end
        end
        if enabled then
            Lighting.FogStart = 1e6
            Lighting.FogEnd = 1e6
            for atmosphere in pairs(originalAtmospheres) do
                if atmosphere.Parent == Lighting then
                    atmosphere.Density = 0
                    atmosphere.Haze = 0
                    atmosphere.Glare = 0
                end
            end
        else
            Lighting.FogStart = OriginalLighting.FogStart
            Lighting.FogEnd = OriginalLighting.FogEnd
            for atmosphere, original in pairs(originalAtmospheres) do
                if atmosphere.Parent == Lighting then
                    atmosphere.Density = original.Density
                    atmosphere.Haze = original.Haze
                    atmosphere.Glare = original.Glare
                    atmosphere.Offset = original.Offset
                else
                    originalAtmospheres[atmosphere] = nil
                end
            end
        end
    end

    Connections.inputBegan = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 and UserInputService:GetFocusedTextBox() == nil then
            rightMouseDown = true
            visibilityCache = {}
            lockedTarget = nil
            lockedAimPart = nil
            lockedTargetLostAt = nil
        end
    end)
    Connections.inputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then rightMouseDown = false end
    end)

    local playerEspAccumulator = 0
    local worldEspAccumulator = 0
    local renderStepName = "RavenWildWest_" .. tostring(LP.UserId)
    RunService:BindToRenderStep(renderStepName, Enum.RenderPriority.Last.Value, function(dt)
        -- Apply environment overrides first so a separate aim/ESP error cannot
        -- prevent Fullbright or No Fog from taking effect this frame.
        if State.Fullbright then applyFullbright(true) end
        if State.NoFog then applyNoFog(true) end
        visibilityFrame += 1
        predictionFrame += 1
        updateAutoLock(dt)
        updateAimPrediction()
        -- Cache silent aim target once per frame for GetProjectileSpread hook
        if State.SilentAim then
            local ok, target = pcall(getSilentAimTarget)
            cachedSilentAimTarget = ok and target or nil
        else
            cachedSilentAimTarget = nil
        end
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
            updateItemESP()
        end
    end)

    local function getRespawnStreamPosition(spawnName)
        local sharedData = Global.SharedData
        local spawnInfoFolder = sharedData and sharedData.SpawnInfoFolder
        local spawnInfo = spawnInfoFolder and spawnInfoFolder:FindFirstChild(spawnName)
        local cameraValue = spawnInfo and spawnInfo:FindFirstChild("CameraCFrame")
        local cameraCFrame = cameraValue and cameraValue.Value
        return typeof(cameraCFrame) == "CFrame" and cameraCFrame.Position or nil
    end

    local function resetRespawnCycle()
        lastRespawnTrigger = -math.huge
        lastRespawnAttempt = -math.huge
        respawnStreamRequestedAt = -math.huge
        respawnStreamLocation = nil
        respawnAcceptedThisDeath = false
    end

    local function updateAutoRespawn(dt)
        respawnAccumulator += dt or 0
        if respawnAccumulator < RESPAWN_UPDATE_INTERVAL then return end
        respawnAccumulator = 0

        local repChar = PlayerCharacter.RepChar
        local repState = repChar and repChar.State
        local dead = PlayerCharacter.IsDead == true or (repState and repState.Dead == true)
        if not dead then
            resetRespawnCycle()
            return
        end
        if not State.AutoRespawn or not repState or repState.CanRespawn ~= true or respawnAcceptedThisDeath then return end

        local now = os.clock()
        if repState.RespawnMenuOpen ~= true then
            if now - lastRespawnTrigger >= RESPAWN_RETRY_INTERVAL then
                lastRespawnTrigger = now
                pcall(function() Network:FireServer("RespawnTriggered") end)
            end
            return
        end

        local spawnName = State.RespawnLocation
        if type(spawnName) ~= "string" or spawnName == "" then return end

        local spawnUI = Global.UI and Global.UI.Spawn
        if spawnUI and type(spawnUI.Select) == "function" then
            local selected = spawnUI.SelectedButton
            local paused = false
            pcall(function()
                paused = spawnUI.SpawnUIPaused and spawnUI.SpawnUIPaused:get() == true or false
            end)
            if not selected or selected.Name ~= spawnName then
                if spawnUI.SelectingButton or paused then return end
                local ok = pcall(function() spawnUI:Select(spawnName) end)
                if ok then
                    respawnStreamLocation = spawnName
                    respawnStreamRequestedAt = now
                    return
                end
            end
            if spawnUI.SelectingButton or paused then return end
        else
            local streamPosition = getRespawnStreamPosition(spawnName)
            if respawnStreamLocation ~= spawnName then
                respawnStreamLocation = spawnName
                respawnStreamRequestedAt = now
                if streamPosition then
                    pcall(function() Network:FireServer("RequestStreamAround", streamPosition) end)
                end
                return
            end

            if streamPosition then
                local streamingLoad = Global.StreamingLoad
                if streamingLoad and type(streamingLoad.IsRegionStreamedIn) == "function" then
                    local ok, ready = pcall(function() return streamingLoad:IsRegionStreamedIn(streamPosition) end)
                    if ok then
                        if ready ~= true then return end
                    elseif now - respawnStreamRequestedAt < RESPAWN_STREAM_FALLBACK_WAIT then
                        return
                    end
                elseif now - respawnStreamRequestedAt < RESPAWN_STREAM_FALLBACK_WAIT then
                    return
                end
            elseif now - respawnStreamRequestedAt < RESPAWN_STREAM_FALLBACK_WAIT then
                return
            end
        end

        if now - lastRespawnAttempt < RESPAWN_RETRY_INTERVAL then return end
        lastRespawnAttempt = now
        local ok, accepted = pcall(function()
            return Network:InvokeServer("Respawn", spawnName)
        end)
        if ok and accepted == true then respawnAcceptedThisDeath = true end
    end

    local function updateRecovery(dt)
        recoveryAccumulator += dt or 0
        if recoveryAccumulator < RECOVERY_UPDATE_INTERVAL then return end
        recoveryAccumulator = 0

        local character = PlayerCharacter.Character
        local repChar = PlayerCharacter.RepChar
        local tiedUp = repChar and repChar.State and repChar.State.TiedUp == true or false
        local ragdolled = false
        if character then
            pcall(function() ragdolled = Ragdolls:IsRagdolledLocal(character) == true end)
        end

        if not ragdolled then getUpAttemptedThisFall = false end
        if State.AutoGetUp and ragdolled and not tiedUp and not getUpAttemptedThisFall then
            local canGetUp = false
            pcall(function() canGetUp = PlayerCharacter:CanGetUp() == true end)
            if canGetUp and os.clock() - lastGetUpAttempt >= GET_UP_COOLDOWN then
                lastGetUpAttempt = os.clock()
                local ok = pcall(function() PlayerCharacter:GetUp() end)
                if ok then getUpAttemptedThisFall = true end
            end
        end

        if not tiedUp then
            lastBreakFreeAttempt = -math.huge
        elseif State.AutoBreakFree and os.clock() - lastBreakFreeAttempt >= BREAK_FREE_INTERVAL then
            local canBreakFree = false
            pcall(function() canBreakFree = PlayerCharacter:CanBreakFree() == true end)
            if canBreakFree then
                lastBreakFreeAttempt = os.clock()
                pcall(function() PlayerCharacter:BreakFree() end)
            end
        end
    end

    Connections.environment = RunService.Heartbeat:Connect(function(dt)
        if destroyed then return end
        updateAutoRespawn(dt)
        updateRecovery(dt)
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

    local function dropdownValues(value)
        local selected = {}
        if type(value) ~= "table" then
            local name = tostring(value or "")
            if name ~= "" then selected[name] = true end
            return selected
        end
        for key, item in pairs(value) do
            if type(key) == "number" then
                local name = tostring(item or "")
                if name ~= "" then selected[name] = true end
            elseif item == true then
                selected[tostring(key)] = true
            elseif item ~= false and item ~= nil then
                selected[tostring(item)] = true
            end
        end
        return selected
    end

    local CombatTab = Window:CreateTab("Combat", "crosshair")
    CombatTab:CreateSection("Aim Prediction")
    CombatTab:CreateToggle({Name="Enable Aim Prediction",CurrentValue=false,Flag="WildWestAimPrediction",Callback=function(v) State.AimPrediction = v == true end})
    CombatTab:CreateToggle({Name="Capture Exact Projectile Seed",CurrentValue=false,Flag="WildWestExactSeed",Callback=function(v) State.ExactSeedCapture = v == true end})
    CombatTab:CreateSlider({Name="Prediction Dot Size",Range={2,14},Increment=1,CurrentValue=6,Suffix=" px",Flag="WildWestPredictDotSize",Callback=function(v) State.PredictDotSize = v end})
    CombatTab:CreateSlider({Name="Prediction Lead",Range={0.5,1.5},Increment=0.05,CurrentValue=1,Suffix="x",Flag="WildWestPredictionLead",Callback=function(v) State.PredictionLeadScale = math.clamp(tonumber(v) or 1, 0.5, 1.5) end})
    CombatTab:CreateLabel("Uses live weapon/ammo power, gravity, fanning and muzzle origin")
    CombatTab:CreateLabel("Exact Seed capture is read-only before the server projectile packet")
    CombatTab:CreateLabel("Auto Visible prefers center mass when weapon accuracy is below 90%")
    CombatTab:CreateSection("Smooth Auto Lock")
    CombatTab:CreateToggle({Name="Player Auto Lock",CurrentValue=false,Flag="WildWestAutoLock",Callback=function(v)
        State.AutoLock = v == true
        if not State.AutoLock then lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil end
    end})
    CombatTab:CreateToggle({Name="Animal Auto Lock",CurrentValue=false,Flag="WildWestAnimalAutoLock",Callback=function(v)
        State.AnimalAutoLock = v == true
        lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil
    end})
    CombatTab:CreateDropdown({Name="Activation",Options={"Right Mouse","Always"},CurrentOption={"Right Mouse"},MultipleOptions=false,Flag="WildWestAimActivation",Callback=function(v)
        local selected = dropdownValue(v, "Right Mouse")
        State.AimActivation = selected:lower() == "always" and "Always" or "Right Mouse"
    end})
    CombatTab:CreateToggle({Name="Sticky Target",CurrentValue=true,Flag="WildWestStickyTarget",Callback=function(v)
        State.StickyTarget = v == true
        if not State.StickyTarget then lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil end
    end})
    CombatTab:CreateToggle({Name="Visible Check",CurrentValue=true,Flag="WildWestVisibleCheck",Callback=function(v)
        State.AimVisibleCheck = v == true
        lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil
    end})
    CombatTab:CreateToggle({Name="Ignore Same Team",CurrentValue=true,Flag="WildWestIgnoreTeam",Callback=function(v)
        State.IgnoreSameTeam = v == true
        lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil
    end})
    CombatTab:CreateToggle({Name="Ignore Same Faction",CurrentValue=true,Flag="WildWestIgnoreFaction",Callback=function(v)
        State.IgnoreSameFaction = v == true
        lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil
    end})
    CombatTab:CreateDropdown({Name="Auto Lock Part",Options={"Auto Visible","Closest Visible","Selected Only"},CurrentOption={"Auto Visible"},MultipleOptions=false,Flag="WildWestAimPartMode",Callback=function(v)
        local selected = dropdownValue(v, "Auto Visible")
        if selected ~= "Closest Visible" and selected ~= "Selected Only" then selected = "Auto Visible" end
        State.AimPartMode = selected
        lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil
    end})
    CombatTab:CreateDropdown({Name="Selected Part",Options={"Head","UpperTorso","LowerTorso"},CurrentOption={"Head"},MultipleOptions=false,Flag="WildWestAimTargetPart",Callback=function(v)
        State.AimTargetPart = dropdownValue(v, "Head")
        lockedTarget, lockedAimPart, lockedTargetLostAt = nil, nil, nil
    end})
    CombatTab:CreateToggle({Name="Adaptive Smoothness",CurrentValue=true,Flag="WildWestAdaptiveSmooth",Callback=function(v) State.AdaptiveSmoothness = v == true end})
    CombatTab:CreateSlider({Name="Aim FOV",Range={40,500},Increment=10,CurrentValue=180,Suffix=" px",Flag="WildWestAimFOV",Callback=function(v) State.AimFOV = v end})
    CombatTab:CreateSlider({Name="Smoothness",Range={0.05,0.6},Increment=0.01,CurrentValue=0.18,Flag="WildWestAimSmooth",Callback=function(v) State.AimSmoothness = v end})
    CombatTab:CreateSection("Silent Aim")
    CombatTab:CreateToggle({Name="Silent Aim",CurrentValue=false,Flag="WildWestSilentAim",Callback=function(v) State.SilentAim = v == true end})
    CombatTab:CreateDropdown({Name="Silent Aim Part",Options={"Head","UpperTorso","HumanoidRootPart"},CurrentOption={"Head"},MultipleOptions=false,Flag="WildWestSilentAimPart",Callback=function(v) State.SilentAimPart = dropdownValue(v, "Head") end})
    CombatTab:CreateSlider({Name="Silent Aim FOV",Range={40,500},Increment=10,CurrentValue=180,Suffix=" px",Flag="WildWestSilentAimFOV",Callback=function(v) State.SilentAimFOV = v end})
    CombatTab:CreateLabel("Silent Aim redirects projectiles toward nearest target")
    CombatTab:CreateLabel("Works with existing Auto Lock target selection")
    CombatTab:CreateSection("Recoil & Spread")
    CombatTab:CreateToggle({Name="No Recoil",CurrentValue=false,Flag="WildWestNoRecoil",Callback=function(v) State.NoRecoil = v == true end})
    CombatTab:CreateToggle({Name="No Spread",CurrentValue=false,Flag="WildWestNoSpread",Callback=function(v) State.NoSpread = v == true end})
    CombatTab:CreateLabel("No Recoil: neutralizes camera kick on fire")
    CombatTab:CreateLabel("No Spread: removes projectile direction deviation")
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

    EspTab:CreateSection("Dropped Items")
    EspTab:CreateToggle({Name="Item ESP",CurrentValue=false,Flag="WildWestItemESP",Callback=function(v) State.ItemESP = v == true end})
    itemFilterDropdown = EspTab:CreateDropdown({Name="Item Filter",Options=itemFilterOptions,CurrentOption={},MultipleOptions=true,Flag="WildWestItemFilter",Callback=function(v)
        State.ItemESPSelected = dropdownValues(v)
    end})
    EspTab:CreateLabel("Empty filter = show every DroppedItem")
    EspTab:CreateSlider({Name="Item ESP Distance",Range={100,3000},Increment=100,CurrentValue=1200,Suffix=" studs",Flag="WildWestItemESPRange",Callback=function(v) State.ItemESPDistance = v end})

    local function buildRespawnOptions()
        local options = {}
        local nameByOption = {}
        local spawnNames = {}
        local sharedData = Global.SharedData
        local spawnInfo = sharedData and sharedData.SpawnInfo
        if type(spawnInfo) == "table" then
            for spawnName in pairs(spawnInfo) do
                if type(spawnName) == "string" then table.insert(spawnNames, spawnName) end
            end
        end
        if #spawnNames == 0 then table.insert(spawnNames, "CanyonCamp") end
        table.sort(spawnNames)

        local playerGui = LP:FindFirstChildOfClass("PlayerGui")
        local spawnGui = playerGui and playerGui:FindFirstChild("NewSpawnUI")
        local screen = spawnGui and spawnGui:FindFirstChild("Screen")
        local sideBar = screen and screen:FindFirstChild("SideBar")
        local body = sideBar and sideBar:FindFirstChild("Body")
        local scroller = body and body:FindFirstChild("ScrollingFrame")
        for _, spawnName in ipairs(spawnNames) do
            local display = spawnName
            local button = scroller and scroller:FindFirstChild(spawnName)
            local container = button and button:FindFirstChild("Container")
            local label = container and container:FindFirstChild("TextLabel")
            if label and label:IsA("TextLabel") and label.Text ~= "" then
                display = string.format("%s [%s]", label.Text, spawnName)
            end
            nameByOption[display] = spawnName
            table.insert(options, display)
        end
        return options, nameByOption
    end

    local AutomationTab = Window:CreateTab("Automation", "zap")
    local respawnOptions, respawnNameByOption = buildRespawnOptions()
    local respawnCurrentOption = respawnOptions[1]
    for option, spawnName in pairs(respawnNameByOption) do
        if spawnName == State.RespawnLocation then
            respawnCurrentOption = option
            break
        end
    end
    if respawnCurrentOption then State.RespawnLocation = respawnNameByOption[respawnCurrentOption] or State.RespawnLocation end
    AutomationTab:CreateSection("Respawn")
    AutomationTab:CreateDropdown({Name="Respawn Location",Options=respawnOptions,CurrentOption={respawnCurrentOption},MultipleOptions=false,Flag="WildWestRespawnLocation",Callback=function(v)
        local option = dropdownValue(v, respawnCurrentOption)
        State.RespawnLocation = respawnNameByOption[option] or State.RespawnLocation
        respawnStreamLocation = nil
        respawnStreamRequestedAt = -math.huge
        lastRespawnAttempt = -math.huge
    end})
    AutomationTab:CreateToggle({Name="Auto Respawn",CurrentValue=false,Flag="WildWestAutoRespawn",Callback=function(v)
        State.AutoRespawn = v == true
        if not State.AutoRespawn then resetRespawnCycle() end
    end})
    AutomationTab:CreateLabel("Flow: RespawnTriggered -> stream selected location -> Respawn")
    AutomationTab:CreateSection("Recovery")
    AutomationTab:CreateToggle({Name="Auto Get Up",CurrentValue=false,Flag="WildWestAutoGetUp",Callback=function(v)
        State.AutoGetUp = v == true
        if not State.AutoGetUp then getUpAttemptedThisFall = false end
    end})
    AutomationTab:CreateToggle({Name="Auto Break Free",CurrentValue=false,Flag="WildWestAutoBreakFree",Callback=function(v)
        State.AutoBreakFree = v == true
        if not State.AutoBreakFree then lastBreakFreeAttempt = -math.huge end
    end})
    AutomationTab:CreateLabel("Get Up: one attempt per real ragdoll, never while tied")
    AutomationTab:CreateLabel("Break Free: only while TiedUp + CanBreakFree, 0.12s gated wiggles")
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
        if seedHookInstalled and seedHookTarget and originalGenerateProjectileSeed and type(hookfunction) == "function" then
            pcall(hookfunction, seedHookTarget, originalGenerateProjectileSeed)
            seedHookInstalled = false
        end
        if recoilHookInstalled and recoilHookTarget and originalAddRecoil and type(hookfunction) == "function" then
            pcall(hookfunction, recoilHookTarget, originalAddRecoil)
            recoilHookInstalled = false
        end
        restoreNoSpreadHook()
        restoreInitProjectilesHook()
        clearPlayerESP()
        clearEntityGroup(EntityESPObjects.animals)
        clearEntityGroup(EntityESPObjects.loot)
        clearEntityGroup(EntityESPObjects.ore)
        clearEntityGroup(EntityESPObjects.items)
        applyFullbright(false)
        applyNoFog(false)
        Camera.FieldOfView = OriginalFOV
        if getgenv().__RAVEN_THE_WILD_WEST and getgenv().__RAVEN_THE_WILD_WEST.State == State then
            getgenv().__RAVEN_THE_WILD_WEST = nil
        end
    end

    getgenv().__RAVEN_THE_WILD_WEST = {Version="v0.1.18",State=State,Destroy=destroy}
    if runtimeInfo and runtimeInfo.registerCleanup then runtimeInfo.registerCleanup(destroy) end
end
