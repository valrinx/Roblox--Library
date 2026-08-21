--[[
    RAVEN HUB | Build and Crush
    PlaceId: 123581964009368 | GameId: 8723526551
    Version: v0.2

    Read-only first release: chest/objective/vehicle awareness, manual travel,
    lightweight progression telemetry, performance controls, and anti-AFK.
    ZAP remotes are intentionally not fired until their schemas are verified.
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local VirtualUser = game:GetService("VirtualUser")
    local CoreGui = game:GetService("CoreGui")

    local player = Players.LocalPlayer
    local environment = getgenv()

    if type(environment.__RAVEN_BUILD_AND_CRUSH) == "table"
        and type(environment.__RAVEN_BUILD_AND_CRUSH.Destroy) == "function" then
        pcall(environment.__RAVEN_BUILD_AND_CRUSH.Destroy)
    end

    local running = true
    local connections = {}
    local espObjects = {}
    local effectState = {}

    local function safeRequire(path)
        local current = ReplicatedStorage
        for segment in string.gmatch(path, "[^/]+") do
            current = current and current:FindFirstChild(segment)
        end
        if not current then return nil end
        local ok, result = pcall(require, current)
        return ok and result or nil
    end

    local crushNet = safeRequire("client/net/crushNet")
    local researchState = safeRequire("shared/state/research")
    local questState = safeRequire("shared/state/quests")
    local plotState = safeRequire("shared/state/plot")
    local researchConfig = safeRequire("shared/config/research")
    local objectiveConfig = safeRequire("shared/config/objectives")

    local settings = {
        chestEsp = false,
        objectiveEsp = false,
        vehicleEsp = false,
        espDistance = 1500,
        performanceMode = false,
        antiAfk = true,
        auraEnabled = false,
        auraMode = "Safe",
        auraRange = 75,
        auraInterval = 0.15,
        auraMaxTargets = 2,
        auraMaxParts = 8,
        auraGoldOnly = false,
        auraFlyingOnly = false,
        auraQuestOnly = false,
    }

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 5})
            end)
        end
    end

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getRoot()
        local character = player.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local function getPosition(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then return instance.Position end
        if instance:IsA("Model") then
            local ok, pivot = pcall(instance.GetPivot, instance)
            return ok and pivot.Position or nil
        end
        local part = instance:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function displayName(instance)
        local rarity = instance:GetAttribute("Rarity")
            or instance:GetAttribute("Tier")
            or instance:GetAttribute("Level")
        if rarity ~= nil then
            return string.format("%s [%s]", instance.Name, tostring(rarity))
        end
        return instance.Name
    end

    local function getObjectiveInfo(instance)
        local config
        if objectiveConfig and type(objectiveConfig.get) == "function" then
            pcall(function() config = objectiveConfig.get(instance.Name) end)
        end
        return {
            name = config and config.name or instance.Name,
            rarity = config and config.rarity or instance:GetAttribute("variantId") or "normal",
            health = instance:GetAttribute("totalObjectiveHealth"),
            difficulty = instance:GetAttribute("difficulty") or (config and config.difficulty),
            dropId = instance:GetAttribute("objectiveDropId"),
            dropQuantity = instance:GetAttribute("objectiveDropQuantity"),
            flying = instance:GetAttribute("isFlying") == true,
            variant = instance:GetAttribute("variantId") or "normal",
        }
    end

    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenBuildAndCrushESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local ESP_COLORS = {
        chest = Color3.fromRGB(255, 205, 70),
        objective = Color3.fromRGB(255, 95, 80),
        vehicle = Color3.fromRGB(75, 190, 255),
    }

    local function removeEsp(instance)
        local entry = espObjects[instance]
        if not entry then return end
        if entry.highlight then entry.highlight:Destroy() end
        if entry.billboard then entry.billboard:Destroy() end
        espObjects[instance] = nil
    end

    local function clearEsp(category)
        for instance, entry in pairs(espObjects) do
            if not category or entry.category == category then
                removeEsp(instance)
            end
        end
    end

    local function addEsp(instance, category)
        if espObjects[instance] or not instance.Parent then return end
        local visual = instance:IsA("Folder") and instance:FindFirstChildWhichIsA("Model") or instance
        if not visual then return end
        local adornee = visual:IsA("Model") and visual
            or visual:FindFirstAncestorOfClass("Model")
            or visual
        local color = ESP_COLORS[category]

        local highlight = Instance.new("Highlight")
        highlight.Name = "Raven_" .. category
        highlight.Adornee = adornee
        highlight.FillColor = color
        highlight.FillTransparency = 0.72
        highlight.OutlineColor = color
        highlight.OutlineTransparency = 0.08
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = espFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenLabel_" .. category
        billboard.Adornee = visual:IsA("BasePart") and visual
            or visual:FindFirstChildWhichIsA("BasePart", true)
        billboard.Size = UDim2.fromOffset(220, 42)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = settings.espDistance
        billboard.Parent = espFolder

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.25
        label.TextWrapped = true
        label.Parent = billboard

        espObjects[instance] = {
            category = category,
            highlight = highlight,
            billboard = billboard,
            label = label,
        }
    end

    local function foldersForCategory(category)
        if category == "chest" then
            return {workspace:FindFirstChild("chests")}
        elseif category == "objective" then
            local map = workspace:FindFirstChild("map")
            return {map and map:FindFirstChild("objectives")}
        elseif category == "vehicle" then
            return {workspace:FindFirstChild("vehicles")}
        end
        return {}
    end


    local function candidatesForCategory(category)
        local candidates = {}
        for _, folder in ipairs(foldersForCategory(category)) do
            if folder then
                for _, instance in ipairs(folder:GetChildren()) do
                    local valid = instance:IsA("Model") or instance:IsA("BasePart")
                        or (category == "chest" and instance:IsA("Folder"))
                    if category == "objective" then
                        valid = valid and instance:GetAttribute("crushable_v2") == true
                    end
                    if valid then table.insert(candidates, instance) end
                end
            end
        end
        return candidates
    end

    local function categoryEnabled(category)
        return (category == "chest" and settings.chestEsp)
            or (category == "objective" and settings.objectiveEsp)
            or (category == "vehicle" and settings.vehicleEsp)
    end

    local function refreshCategory(category)
        if not categoryEnabled(category) then
            clearEsp(category)
            return
        end

        local seen = {}
        for _, instance in ipairs(candidatesForCategory(category)) do
            seen[instance] = true
            addEsp(instance, category)
        end

        for instance, entry in pairs(espObjects) do
            if entry.category == category and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end

    local function updateEspLabels()
        local root = getRoot()
        for instance, entry in pairs(espObjects) do
            if not instance.Parent then
                removeEsp(instance)
            else
                entry.billboard.MaxDistance = settings.espDistance
                local position = getPosition(instance)
                local distance = root and position and (root.Position - position).Magnitude
                local owner = entry.category == "vehicle"
                    and (instance:GetAttribute("ownerId") or instance:GetAttribute("OwnerName") or instance:GetAttribute("Owner"))
                local text = string.format("[%s] %s", string.upper(entry.category), displayName(instance))
                if entry.category == "chest" then
                    local model = instance:FindFirstChildWhichIsA("Model")
                    text = string.format("[CHEST] #%s | %s", instance.Name, model and model.Name:gsub("chest/", "") or "unknown")
                elseif entry.category == "objective" then
                    local info = getObjectiveInfo(instance)
                    text = string.format("[%s] %s | HP %s | %s %s",
                        string.upper(tostring(info.rarity)), info.name, tostring(info.health or "?"),
                        tostring(info.dropQuantity and math.floor(info.dropQuantity) or "?"), tostring(info.dropId or ""))
                end
                if owner then text = text .. "\nOwner: " .. tostring(owner) end
                if distance then text = text .. string.format(" | %dm", math.floor(distance)) end
                entry.label.Text = text
            end
        end
    end

    local function nearest(category)
        local root = getRoot()
        if not root then return nil end
        local best, bestDistance
        for _, instance in ipairs(candidatesForCategory(category)) do
            local position = getPosition(instance)
            if position then
                local distance = (root.Position - position).Magnitude
                if not bestDistance or distance < bestDistance then
                    best, bestDistance = instance, distance
                end
            end
        end
        return best, bestDistance
    end

    local function teleportNear(instance)
        local root = getRoot()
        local position = getPosition(instance)
        if not root or not position then return false end
        root.CFrame = CFrame.new(position + Vector3.new(0, 6, 0))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    local function getPlayerState(module)
        if not module or type(module.atom) ~= "function" then return nil end
        local ok, state = pcall(module.atom)
        return ok and type(state) == "table" and state[player.Name] or nil
    end

    local function getQuestObjectiveId()
        local state = getPlayerState(questState)
        local quest = state and state.conveyorQuest
        return quest and quest.assignmentState == "active" and quest.assignedObjectiveId or nil
    end

    local function objectiveMatchesFilters(instance)
        local info = getObjectiveInfo(instance)
        if settings.auraGoldOnly and info.variant ~= "gold" then return false end
        if settings.auraFlyingOnly and not info.flying then return false end
        local questObjectiveId = settings.auraQuestOnly and getQuestObjectiveId() or nil
        if settings.auraQuestOnly and instance.Name ~= questObjectiveId then return false end
        return true
    end

    local function findDamageSource()
        local vehicleId = player:GetAttribute("ownVehicleState") or player:GetAttribute("driving")
        local vehicles = workspace:FindFirstChild("vehicles")
        local vehicle = vehicles and vehicleId and vehicles:FindFirstChild(tostring(vehicleId))
        if not vehicle then return nil end

        local fallback
        for _, instance in ipairs(vehicle:GetDescendants()) do
            local id = instance:GetAttribute("contactId") or instance:GetAttribute("id")
            if type(id) == "number" then
                fallback = fallback or id
                local itemId = string.lower(tostring(instance:GetAttribute("taggedItemId") or instance.Name))
                if itemId:find("saw") or itemId:find("spike") or itemId:find("bumper")
                    or itemId:find("weapon") or itemId:find("wrecker") then
                    return id
                end
            end
        end
        return fallback
    end

    local function collectObjectivePartIds(objective, limit)
        local ids = {}
        for _, instance in ipairs(objective:GetDescendants()) do
            local id = instance:GetAttribute("id")
            if type(id) == "number" then
                table.insert(ids, id)
                if #ids >= limit then break end
            end
        end
        return ids
    end

    local function damageValueForMode()
        return settings.auraMode == "Fast" and 360 or 250
    end

    local function runObjectiveAura()
        if not settings.auraEnabled or not crushNet or not crushNet.reportDamage
            or type(crushNet.reportDamage.fire) ~= "function" then
            return 0
        end
        local root = getRoot()
        local sourceId = findDamageSource()
        if not root or not sourceId then return 0 end

        local targets = {}
        for _, objective in ipairs(candidatesForCategory("objective")) do
            local position = getPosition(objective)
            if position and objectiveMatchesFilters(objective) then
                local distance = (root.Position - position).Magnitude
                if distance <= settings.auraRange then
                    table.insert(targets, {instance = objective, position = position, distance = distance})
                end
            end
        end
        table.sort(targets, function(a, b) return a.distance < b.distance end)

        local attacked = 0
        for index = 1, math.min(settings.auraMaxTargets, #targets) do
            local target = targets[index]
            local partIds = collectObjectivePartIds(target.instance, settings.auraMaxParts)
            if #partIds > 0 then
                local ok = pcall(crushNet.reportDamage.fire,
                    sourceId, partIds, damageValueForMode(), target.position)
                if ok then attacked = attacked + 1 end
            end
        end
        return attacked
    end

    local function crateSummary()
        local state = getPlayerState(plotState)
        local crates = state and state.crates or {}
        local now = workspace:GetServerTimeNow()
        local count, ready, nearestReady = 0, 0, math.huge
        for _, crate in pairs(crates) do
            count = count + 1
            local progress = (crate.progressAtLastUpdate or 0)
                + math.max(0, now - (crate.lastUpdatedAt or now))
                    * (1 + ((crate.effects and crate.effects.speedBonus) or 0))
            local remaining = math.max(0, (crate.baseDuration or 0) - progress)
            if remaining <= 0 then ready = ready + 1 else nearestReady = math.min(nearestReady, remaining) end
        end
        return count, ready, nearestReady == math.huge and nil or nearestReady
    end

    local function formatDuration(seconds)
        if not seconds then return "—" end
        seconds = math.max(0, math.floor(seconds))
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        return hours > 0 and string.format("%dh %02dm", hours, minutes)
            or string.format("%dm %02ds", minutes, seconds % 60)
    end

    local function setPerformanceMode(enabled)
        settings.performanceMode = enabled
        if enabled then
            local artifacts = workspace:FindFirstChild("_artifacts")
            local roots = {artifacts, workspace:FindFirstChild("crateAnimations")}
            for _, root in ipairs(roots) do
                if root then
                    for _, instance in ipairs(root:GetDescendants()) do
                        if instance:IsA("ParticleEmitter") or instance:IsA("Trail")
                            or instance:IsA("Beam") or instance:IsA("Smoke")
                            or instance:IsA("Fire") or instance:IsA("Sparkles") then
                            if effectState[instance] == nil then
                                effectState[instance] = instance.Enabled
                            end
                            instance.Enabled = false
                        elseif instance:IsA("BasePart") then
                            if effectState[instance] == nil then
                                effectState[instance] = instance.LocalTransparencyModifier
                            end
                            instance.LocalTransparencyModifier = 1
                        end
                    end
                end
            end
        else
            for instance, previous in pairs(effectState) do
                if instance.Parent then
                    if instance:IsA("BasePart") then
                        instance.LocalTransparencyModifier = previous
                    else
                        instance.Enabled = previous
                    end
                end
            end
            table.clear(effectState)
        end
    end

    local function countChildren(path)
        return path and #path:GetChildren() or 0
    end

    local EspTab = Window:CreateTab("Build & Crush", "eye")
    EspTab:CreateSection("World ESP")
    local worldStatus = EspTab:CreateLabel("Chests: 0 | Objectives: 0 | Vehicles: 0")

    EspTab:CreateToggle({
        Name = "Chest ESP",
        CurrentValue = false,
        Flag = "BuildCrushChestEsp",
        Callback = function(value)
            settings.chestEsp = value
            refreshCategory("chest")
        end,
    })
    EspTab:CreateToggle({
        Name = "Objective ESP",
        CurrentValue = false,
        Flag = "BuildCrushObjectiveEsp",
        Callback = function(value)
            settings.objectiveEsp = value
            refreshCategory("objective")
        end,
    })
    EspTab:CreateToggle({
        Name = "Vehicle ESP",
        CurrentValue = false,
        Flag = "BuildCrushVehicleEsp",
        Callback = function(value)
            settings.vehicleEsp = value
            refreshCategory("vehicle")
        end,
    })
    EspTab:CreateSlider({
        Name = "ESP Distance",
        Range = {100, 5000},
        Increment = 100,
        CurrentValue = 1500,
        Suffix = " studs",
        Flag = "BuildCrushEspDistance",
        Callback = function(value) settings.espDistance = value end,
    })

    local AuraTab = Window:CreateTab("Objective Aura", "target")
    AuraTab:CreateSection("Damage Aura")
    local auraStatus = AuraTab:CreateLabel("Aura: idle | Source: not detected")
    AuraTab:CreateToggle({
        Name = "Enable Objective Aura",
        CurrentValue = false,
        Flag = "BuildCrushObjectiveAura",
        Callback = function(value) settings.auraEnabled = value end,
    })
    AuraTab:CreateDropdown({
        Name = "Aura Mode",
        Options = {"Safe", "Fast"},
        CurrentOption = {"Safe"},
        Flag = "BuildCrushAuraMode",
        Callback = function(value)
            settings.auraMode = type(value) == "table" and value[1] or value
        end,
    })
    AuraTab:CreateSlider({
        Name = "Aura Range",
        Range = {10, 300},
        Increment = 5,
        CurrentValue = 75,
        Suffix = " studs",
        Flag = "BuildCrushAuraRange",
        Callback = function(value) settings.auraRange = value end,
    })
    AuraTab:CreateSlider({
        Name = "Attack Interval",
        Range = {0.05, 1},
        Increment = 0.05,
        CurrentValue = 0.15,
        Suffix = " s",
        Flag = "BuildCrushAuraInterval",
        Callback = function(value) settings.auraInterval = value end,
    })
    AuraTab:CreateSlider({
        Name = "Max Targets / Tick",
        Range = {1, 8},
        Increment = 1,
        CurrentValue = 2,
        Flag = "BuildCrushAuraTargets",
        Callback = function(value) settings.auraMaxTargets = value end,
    })
    AuraTab:CreateSlider({
        Name = "Max Parts / Target",
        Range = {1, 30},
        Increment = 1,
        CurrentValue = 8,
        Flag = "BuildCrushAuraParts",
        Callback = function(value) settings.auraMaxParts = value end,
    })

    AuraTab:CreateSection("Target Filters")
    AuraTab:CreateToggle({
        Name = "Quest Objective Only",
        CurrentValue = false,
        Flag = "BuildCrushAuraQuestOnly",
        Callback = function(value) settings.auraQuestOnly = value end,
    })
    AuraTab:CreateToggle({
        Name = "Gold Variant Only",
        CurrentValue = false,
        Flag = "BuildCrushAuraGoldOnly",
        Callback = function(value) settings.auraGoldOnly = value end,
    })
    AuraTab:CreateToggle({
        Name = "Flying Objectives Only",
        CurrentValue = false,
        Flag = "BuildCrushAuraFlyingOnly",
        Callback = function(value) settings.auraFlyingOnly = value end,
    })

    local TravelTab = Window:CreateTab("Travel", "map-pin")
    TravelTab:CreateSection("Manual Teleport")
    for _, option in ipairs({
        {name = "Nearest Chest", category = "chest"},
        {name = "Nearest Objective", category = "objective"},
        {name = "Nearest Vehicle", category = "vehicle"},
    }) do
        TravelTab:CreateButton({
            Name = "TP: " .. option.name,
            Callback = function()
                local target, distance = nearest(option.category)
                if target and teleportNear(target) then
                    notify("Build and Crush", string.format("Teleported to %s (%dm)", target.Name, math.floor(distance or 0)))
                else
                    notify("Build and Crush", "No " .. option.category .. " is currently loaded")
                end
            end,
        })
    end

    local UtilityTab = Window:CreateTab("B&C Utility", "settings")
    UtilityTab:CreateSection("Progress Snapshot")
    local playerStatus = UtilityTab:CreateLabel("Coins: ? | Research: ? | Plot: ?")
    local researchStatus = UtilityTab:CreateLabel("Research: loading...")
    local questStatus = UtilityTab:CreateLabel("Quest: loading...")
    local crateStatus = UtilityTab:CreateLabel("Crates: loading...")
    UtilityTab:CreateLabel("Aura uses the game's decoded crushNet wrapper with a valid owned-vehicle source ID.")

    UtilityTab:CreateSection("Stability")
    UtilityTab:CreateToggle({
        Name = "Performance Mode",
        CurrentValue = false,
        Flag = "BuildCrushPerformance",
        Callback = setPerformanceMode,
    })
    UtilityTab:CreateToggle({
        Name = "Anti AFK",
        CurrentValue = true,
        Flag = "BuildCrushAntiAfk",
        Callback = function(value) settings.antiAfk = value end,
    })

    connect(player.Idled, function()
        if not settings.antiAfk then return end
        local camera = workspace.CurrentCamera
        VirtualUser:Button2Down(Vector2.zero, camera and camera.CFrame or CFrame.new())
        task.wait(0.25)
        VirtualUser:Button2Up(Vector2.zero, camera and camera.CFrame or CFrame.new())
    end)

    task.spawn(function()
        local espAt = 0
        local statusAt = 0
        local auraAt = 0
        while running do
            local now = os.clock()
            if now - espAt >= 1 then
                espAt = now
                refreshCategory("chest")
                refreshCategory("objective")
                refreshCategory("vehicle")
                updateEspLabels()
            end

            if settings.auraEnabled and now - auraAt >= settings.auraInterval then
                auraAt = now
                local attacked = runObjectiveAura()
                pcall(function()
                    auraStatus:Set(string.format("Aura: %s | Targets: %d | Source: %s",
                        settings.auraMode, attacked, tostring(findDamageSource() or "not detected")))
                end)
            elseif not settings.auraEnabled then
                pcall(function()
                    auraStatus:Set("Aura: idle | Source: " .. tostring(findDamageSource() or "not detected"))
                end)
            end

            if now - statusAt >= 0.5 then
                statusAt = now
                local map = workspace:FindFirstChild("map")
                local objectives = map and map:FindFirstChild("objectives")
                local chests = workspace:FindFirstChild("chests")
                local vehicles = workspace:FindFirstChild("vehicles")
                pcall(function()
                    worldStatus:Set(string.format(
                        "Chests: %d | Objectives: %d | Vehicles: %d",
                        countChildren(chests), countChildren(objectives), countChildren(vehicles)
                    ))
                end)

                local coins = player:GetAttribute("Coins")
                    or (player:FindFirstChild("leaderstats")
                        and player.leaderstats:FindFirstChild("Coins")
                        and player.leaderstats.Coins.Value)
                    or "?"
                local currentResearch = getPlayerState(researchState)
                local research = currentResearch and currentResearch.researchLevel or "?"
                local plot = getPlayerState(plotState)
                pcall(function()
                    playerStatus:Set(string.format("Coins: %s | Research: %s | Plot Studs: %s",
                        tostring(coins), tostring(research), tostring(plot and plot.studs or "?")))
                end)

                local progress = currentResearch and currentResearch.studsCollectedDuringTier
                local levelData = researchConfig and researchConfig.researchLevels
                    and type(research) == "number" and researchConfig.researchLevels[research + 1]
                pcall(function()
                    researchStatus:Set(levelData
                        and string.format("Research R%d → R%d: %d / %d studs",
                            research, research + 1, progress or 0, levelData.studsRequired or 0)
                        or string.format("Research R%s: MAX or unavailable", tostring(research)))
                end)

                local quest = getPlayerState(questState)
                local conveyor = quest and quest.conveyorQuest
                pcall(function()
                    questStatus:Set(conveyor and conveyor.assignmentState == "active"
                        and string.format("Quest: %s | Reward: %s", tostring(conveyor.assignedObjectiveId), tostring(conveyor.rewardBaseId))
                        or "Quest: none active")
                end)

                local crateCount, readyCrates, nextReady = crateSummary()
                pcall(function()
                    crateStatus:Set(string.format("Crates: %d | Ready: %d | Next: %s",
                        crateCount, readyCrates, formatDuration(nextReady)))
                end)
            end
            RunService.Heartbeat:Wait()
        end
    end)

    local function destroy()
        if not running then return end
        running = false
        clearEsp()
        setPerformanceMode(false)
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
        if espFolder.Parent then espFolder:Destroy() end
        if environment.__RAVEN_BUILD_AND_CRUSH
            and environment.__RAVEN_BUILD_AND_CRUSH.Settings == settings then
            environment.__RAVEN_BUILD_AND_CRUSH = nil
        end
    end

    environment.__RAVEN_BUILD_AND_CRUSH = {
        Settings = settings,
        Destroy = destroy,
        RefreshESP = function()
            refreshCategory("chest")
            refreshCategory("objective")
            refreshCategory("vehicle")
        end,
        TeleportNearest = function(category)
            local target = nearest(category)
            return target and teleportNear(target) or false
        end,
        RunObjectiveAura = runObjectiveAura,
        GetQuestObjectiveId = getQuestObjectiveId,
        GetDamageSource = findDamageSource,
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    notify("Build and Crush", "v0.2 loaded — trackers and Objective Aura are ready")
end
