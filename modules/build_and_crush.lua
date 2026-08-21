--[[
    RAVEN HUB | Build and Crush
    PlaceId: 123581964009368 | GameId: 8723526551
    Version: v0.1

    Read-only first release: chest/objective/vehicle awareness, manual travel,
    lightweight progression telemetry, performance controls, and anti-AFK.
    ZAP remotes are intentionally not fired until their schemas are verified.
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
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

    local settings = {
        chestEsp = false,
        objectiveEsp = false,
        vehicleEsp = false,
        espDistance = 1500,
        performanceMode = false,
        antiAfk = true,
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
        local adornee = instance:IsA("Model") and instance
            or instance:FindFirstAncestorOfClass("Model")
            or instance
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
        billboard.Adornee = instance:IsA("BasePart") and instance
            or instance:FindFirstChildWhichIsA("BasePart", true)
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
        for _, folder in ipairs(foldersForCategory(category)) do
            if folder then
                for _, instance in ipairs(folder:GetChildren()) do
                    if instance:IsA("Model") or instance:IsA("BasePart") then
                        seen[instance] = true
                        addEsp(instance, category)
                    end
                end
            end
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
                    and (instance:GetAttribute("OwnerName") or instance:GetAttribute("Owner"))
                local text = string.format("[%s] %s", string.upper(entry.category), displayName(instance))
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
        for _, folder in ipairs(foldersForCategory(category)) do
            if folder then
                for _, instance in ipairs(folder:GetChildren()) do
                    local position = getPosition(instance)
                    if position then
                        local distance = (root.Position - position).Magnitude
                        if not bestDistance or distance < bestDistance then
                            best, bestDistance = instance, distance
                        end
                    end
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
    UtilityTab:CreateLabel("ZAP automation is disabled until packet schemas are verified.")

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
        while running do
            local now = os.clock()
            if now - espAt >= 1 then
                espAt = now
                refreshCategory("chest")
                refreshCategory("objective")
                refreshCategory("vehicle")
                updateEspLabels()
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
                local research = player:GetAttribute("ResearchLevel")
                    or player:GetAttribute("GarageResearchLevel") or "?"
                local plot = player:GetAttribute("PlotId") or player:GetAttribute("Plot") or "?"
                pcall(function()
                    playerStatus:Set(string.format("Coins: %s | Research: %s | Plot: %s", tostring(coins), tostring(research), tostring(plot)))
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
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    notify("Build and Crush", "v0.1 loaded — awareness and utility tools are ready")
end
