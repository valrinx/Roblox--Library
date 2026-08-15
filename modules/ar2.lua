--[[
    RAVEN HUB Module - Apocalypse Rising 2
    Game: Apocalypse Rising 2 (PlaceId: 863266079, GameId: 358276974)
    Developer: Dualpoint Interactive
    
    Features:
    - Player ESP (Highlight + Distance + Health)
    - Zombie ESP (Highlight + Distance)
    - Loot Container ESP (Highlight nearby containers)
    - Vehicle ESP (Highlight vehicles)
    - Fullbright (Remove darkness)
    - No Fog (Remove atmospheric fog)
    - FOV Changer (Adjustable field of view)
    - No Recoil (Visual camera recoil suppression)
    
    Module format: returns function(Window, runtimeInfo) for RAVENHUB loader
]]

return function(Window, runtimeInfo)
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local CollectionService = game:GetService("CollectionService")
    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    -- State
    local State = {
        ESP_Players = false,
        ESP_Zombies = false,
        ESP_Loot = false,
        ESP_Vehicles = false,
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 90,
        NoRecoil = false,
        LootRadius = 150,
    }
    local Connections = {}
    local ESPObjects = {}

    -- Original values
    local OriginalLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows,
        OutdoorAmbient = Lighting.OutdoorAmbient,
    }
    local OriginalFOV = Camera.FieldOfView
    local OriginalAtmosphere = {}

    -- Cache atmosphere settings
    for _, eff in Lighting:GetChildren() do
        if eff:IsA("Atmosphere") then
            OriginalAtmosphere.Density = eff.Density
            OriginalAtmosphere.Offset = eff.Offset
            OriginalAtmosphere.Glare = eff.Glare
            OriginalAtmosphere.Haze = eff.Haze
            OriginalAtmosphere.Instance = eff
        end
    end

    ---------------------------------------------------------------------------
    -- Utility
    ---------------------------------------------------------------------------
    local function getDistance(pos)
        local char = LP.Character
        if not char then return 9999 end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return 9999 end
        return (hrp.Position - pos).Magnitude
    end

    local function getModelPosition(model)
        if model:IsA("Model") then
            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp then return hrp.Position end
            local primary = model.PrimaryPart
            if primary then return primary.Position end
            -- Fallback: find any BasePart
            for _, part in model:GetDescendants() do
                if part:IsA("BasePart") then return part.Position end
            end
        elseif model:IsA("BasePart") then
            return model.Position
        end
        return nil
    end

    ---------------------------------------------------------------------------
    -- ESP System
    ---------------------------------------------------------------------------
    local function createESP(inst, color, text, showDistance)
        if ESPObjects[inst] then return end

        local highlight = Instance.new("Highlight")
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.FillTransparency = 0.75
        highlight.OutlineTransparency = 0.3
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = inst

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RAVEN_ESP"
        billboard.Size = UDim2.new(0, 160, 0, 36)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = inst

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"
        nameLabel.Text = text
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 12
        nameLabel.TextColor3 = color
        nameLabel.TextStrokeTransparency = 0.3
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.Position = UDim2.new(0, 0, 0, 0)
        nameLabel.Parent = billboard

        local distLabel = Instance.new("TextLabel")
        distLabel.Name = "DistLabel"
        distLabel.Text = ""
        distLabel.Font = Enum.Font.Gotham
        distLabel.TextSize = 10
        distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        distLabel.TextStrokeTransparency = 0.4
        distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        distLabel.BackgroundTransparency = 1
        distLabel.Size = UDim2.new(1, 0, 0.5, 0)
        distLabel.Position = UDim2.new(0, 0, 0.5, 0)
        distLabel.Parent = billboard

        ESPObjects[inst] = {
            highlight = highlight,
            billboard = billboard,
            nameLabel = nameLabel,
            distLabel = distLabel,
            showDistance = showDistance,
            color = color,
        }
    end

    local function removeESP(inst)
        if not ESPObjects[inst] then return end
        pcall(function() ESPObjects[inst].highlight:Destroy() end)
        pcall(function() ESPObjects[inst].billboard:Destroy() end)
        ESPObjects[inst] = nil
    end

    local function clearESPByTag(tag)
        local toRemove = {}
        for inst, data in pairs(ESPObjects) do
            if data.tag == tag then
                table.insert(toRemove, inst)
            end
        end
        for _, inst in toRemove do
            removeESP(inst)
        end
    end

    local function createTaggedESP(inst, color, text, showDistance, tag)
        if ESPObjects[inst] then return end
        createESP(inst, color, text, showDistance)
        if ESPObjects[inst] then
            ESPObjects[inst].tag = tag
        end
    end

    ---------------------------------------------------------------------------
    -- Player ESP
    ---------------------------------------------------------------------------
    local function updatePlayerESP()
        if not State.ESP_Players then
            clearESPByTag("player")
            return
        end
        for _, player in Players:GetPlayers() do
            if player ~= LP and player.Character then
                local char = player.Character
                if not ESPObjects[char] then
                    local color = Color3.fromRGB(85, 170, 255) -- Blue
                    createTaggedESP(char, color, player.DisplayName, true, "player")
                end
            end
        end
        -- Remove ESP for dead/left players
        for inst, data in pairs(ESPObjects) do
            if data.tag == "player" then
                local isValid = false
                for _, p in Players:GetPlayers() do
                    if p.Character == inst then isValid = true break end
                end
                if not isValid then
                    removeESP(inst)
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Zombie ESP
    ---------------------------------------------------------------------------
    local function updateZombieESP()
        if not State.ESP_Zombies then
            clearESPByTag("zombie")
            return
        end
        local zombieFolder = workspace:FindFirstChild("Zombies")
        if not zombieFolder then return end
        for _, zombie in zombieFolder:GetChildren() do
            if zombie:IsA("Model") and not ESPObjects[zombie] then
                local color = Color3.fromRGB(255, 80, 80) -- Red
                createTaggedESP(zombie, color, zombie.Name:sub(1, 20), true, "zombie")
            end
        end
        -- Cleanup removed zombies
        for inst, data in pairs(ESPObjects) do
            if data.tag == "zombie" and (not inst.Parent or inst.Parent ~= zombieFolder) then
                removeESP(inst)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Loot Container ESP (nearby only for performance)
    ---------------------------------------------------------------------------
    local function updateLootESP()
        if not State.ESP_Loot then
            clearESPByTag("loot")
            return
        end
        
        local myPos = nil
        local char = LP.Character
        if char then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then myPos = hrp.Position end
        end
        if not myPos then return end
        
        -- Get nearby loot containers
        local containers = CollectionService:GetTagged("Loot Container")
        for _, container in containers do
            local pos = getModelPosition(container)
            if pos then
                local dist = (myPos - pos).Magnitude
                if dist <= State.LootRadius then
                    if not ESPObjects[container] then
                        local color = Color3.fromRGB(80, 255, 80) -- Green
                        createTaggedESP(container, color, container.Name:sub(1, 25), true, "loot")
                    end
                else
                    -- Remove if too far
                    if ESPObjects[container] then
                        removeESP(container)
                    end
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Vehicle ESP
    ---------------------------------------------------------------------------
    local function updateVehicleESP()
        if not State.ESP_Vehicles then
            clearESPByTag("vehicle")
            return
        end
        local vehicleFolder = workspace:FindFirstChild("Vehicles")
        if not vehicleFolder then return end
        for _, vehicle in vehicleFolder:GetChildren() do
            if vehicle:IsA("Model") and not ESPObjects[vehicle] then
                local color = Color3.fromRGB(255, 200, 50) -- Yellow/Gold
                createTaggedESP(vehicle, color, vehicle.Name, true, "vehicle")
            end
        end
        -- Cleanup
        for inst, data in pairs(ESPObjects) do
            if data.tag == "vehicle" and (not inst.Parent or inst.Parent ~= vehicleFolder) then
                removeESP(inst)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Distance Updater
    ---------------------------------------------------------------------------
    local function updateDistances()
        for inst, data in pairs(ESPObjects) do
            if data.showDistance and data.distLabel then
                local pos = getModelPosition(inst)
                if pos then
                    local dist = getDistance(pos)
                    data.distLabel.Text = string.format("[%dm]", math.floor(dist))
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Fullbright & No Fog
    ---------------------------------------------------------------------------
    local function setFullbright(enabled)
        if enabled then
            Lighting.Brightness = 3
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
            -- Disable dark effects
            for _, eff in Lighting:GetChildren() do
                if eff:IsA("ColorCorrectionEffect") and eff.Name ~= "DamageFade" then
                    eff.Enabled = false
                end
            end
        else
            Lighting.Brightness = OriginalLighting.Brightness
            Lighting.GlobalShadows = OriginalLighting.GlobalShadows
            Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
            for _, eff in Lighting:GetChildren() do
                if eff:IsA("ColorCorrectionEffect") then
                    eff.Enabled = true
                end
            end
        end
    end

    local function setNoFog(enabled)
        if enabled then
            Lighting.FogEnd = 999999
            Lighting.FogStart = 999999
            if OriginalAtmosphere.Instance then
                OriginalAtmosphere.Instance.Density = 0
                OriginalAtmosphere.Instance.Haze = 0
            end
        else
            Lighting.FogEnd = OriginalLighting.FogEnd
            Lighting.FogStart = OriginalLighting.FogStart
            if OriginalAtmosphere.Instance then
                OriginalAtmosphere.Instance.Density = OriginalAtmosphere.Density or 0.3
                OriginalAtmosphere.Instance.Haze = OriginalAtmosphere.Haze or 0
            end
        end
    end

    ---------------------------------------------------------------------------
    -- FOV Changer
    ---------------------------------------------------------------------------
    local function updateFOV()
        if State.FOVEnabled then
            Camera.FieldOfView = State.FOVValue
        end
    end

    ---------------------------------------------------------------------------
    -- No Recoil (Camera-based visual recoil suppression)
    ---------------------------------------------------------------------------
    local originalCFrame = nil
    local recoilConnection = nil

    local function enableNoRecoil()
        if recoilConnection then return end
        -- Store CFrame each frame and revert sudden camera kicks
        local lastCFrame = Camera.CFrame
        local smoothFactor = 0.95
        
        recoilConnection = RunService.RenderStepped:Connect(function()
            if not State.NoRecoil then return end
            
            -- Calculate rotation difference
            local currentCFrame = Camera.CFrame
            local _, currentY, _ = currentCFrame:ToEulerAnglesYXZ()
            local _, lastY, _ = lastCFrame:ToEulerAnglesYXZ()
            
            -- If camera moved up suddenly (recoil kick), dampen it
            local yDiff = currentY - lastY
            if yDiff > 0.01 then -- Upward kick detected
                -- Suppress vertical recoil by lerping back
                local suppressed = lastCFrame:Lerp(currentCFrame, 1 - smoothFactor)
                Camera.CFrame = CFrame.new(currentCFrame.Position) * CFrame.Angles(suppressed:ToEulerAnglesYXZ())
            end
            
            lastCFrame = Camera.CFrame
        end)
        Connections.recoil = recoilConnection
    end

    local function disableNoRecoil()
        if recoilConnection then
            recoilConnection:Disconnect()
            recoilConnection = nil
            Connections.recoil = nil
        end
    end

    ---------------------------------------------------------------------------
    -- Main Loop
    ---------------------------------------------------------------------------
    local tickCounter = 0
    Connections.main = RunService.Heartbeat:Connect(function()
        tickCounter = tickCounter + 1
        
        -- ESP updates (every 60 frames ~1 second for performance)
        if tickCounter % 60 == 0 then
            if State.ESP_Players then updatePlayerESP() end
            if State.ESP_Zombies then updateZombieESP() end
            if State.ESP_Vehicles then updateVehicleESP() end
        end
        
        -- Loot ESP updates less frequently (every 90 frames)
        if tickCounter % 90 == 0 then
            if State.ESP_Loot then updateLootESP() end
        end
        
        -- Distance updates (every 15 frames)
        if tickCounter % 15 == 0 then
            updateDistances()
        end
        
        -- FOV enforcement
        if State.FOVEnabled then
            updateFOV()
        end
    end)

    ---------------------------------------------------------------------------
    -- UI Tabs
    ---------------------------------------------------------------------------
    -- === VISUALS TAB ===
    local visualsTab = Window:CreateTab("Visuals", "esp")
    
    visualsTab:CreateSection("ESP")
    visualsTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "AR2_PlayerESP",
        Callback = function(value)
            State.ESP_Players = value
            if value then updatePlayerESP() else clearESPByTag("player") end
        end,
    })
    visualsTab:CreateToggle({
        Name = "Zombie ESP",
        CurrentValue = false,
        Flag = "AR2_ZombieESP",
        Callback = function(value)
            State.ESP_Zombies = value
            if value then updateZombieESP() else clearESPByTag("zombie") end
        end,
    })
    visualsTab:CreateToggle({
        Name = "Loot Container ESP",
        CurrentValue = false,
        Flag = "AR2_LootESP",
        Callback = function(value)
            State.ESP_Loot = value
            if value then updateLootESP() else clearESPByTag("loot") end
        end,
    })
    visualsTab:CreateSlider({
        Name = "Loot ESP Radius",
        Range = { 50, 500 },
        Increment = 10,
        CurrentValue = 150,
        Suffix = " studs",
        Flag = "AR2_LootRadius",
        Callback = function(value)
            State.LootRadius = value
        end,
    })
    visualsTab:CreateToggle({
        Name = "Vehicle ESP",
        CurrentValue = false,
        Flag = "AR2_VehicleESP",
        Callback = function(value)
            State.ESP_Vehicles = value
            if value then updateVehicleESP() else clearESPByTag("vehicle") end
        end,
    })

    visualsTab:CreateSection("Lighting")
    visualsTab:CreateToggle({
        Name = "Fullbright",
        CurrentValue = false,
        Flag = "AR2_Fullbright",
        Callback = function(value)
            State.Fullbright = value
            setFullbright(value)
        end,
    })
    visualsTab:CreateToggle({
        Name = "No Fog",
        CurrentValue = false,
        Flag = "AR2_NoFog",
        Callback = function(value)
            State.NoFog = value
            setNoFog(value)
        end,
    })

    visualsTab:CreateSection("Camera")
    visualsTab:CreateToggle({
        Name = "FOV Changer",
        CurrentValue = false,
        Flag = "AR2_FOVEnabled",
        Callback = function(value)
            State.FOVEnabled = value
            if not value then
                Camera.FieldOfView = OriginalFOV
            end
        end,
    })
    visualsTab:CreateSlider({
        Name = "FOV Value",
        Range = { 50, 120 },
        Increment = 1,
        CurrentValue = 90,
        Suffix = "°",
        Flag = "AR2_FOVValue",
        Callback = function(value)
            State.FOVValue = value
            if State.FOVEnabled then updateFOV() end
        end,
    })

    -- === COMBAT TAB ===
    local combatTab = Window:CreateTab("Combat", "combat")
    
    combatTab:CreateSection("Recoil Control")
    combatTab:CreateToggle({
        Name = "No Recoil (Visual)",
        CurrentValue = false,
        Flag = "AR2_NoRecoil",
        Callback = function(value)
            State.NoRecoil = value
            if value then
                enableNoRecoil()
            else
                disableNoRecoil()
            end
        end,
    })
    
    combatTab:CreateSection("Info")
    combatTab:CreateLabel("⚠️ AR2 uses server-side hit validation")
    combatTab:CreateLabel("Aimbot/damage hacks are NOT possible")
    combatTab:CreateLabel("No Recoil only suppresses camera kick")

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------
    local function cleanup()
        -- Disconnect all connections
        for key, conn in pairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
        Connections = {}

        -- Remove all ESP
        for inst, _ in pairs(ESPObjects) do
            removeESP(inst)
        end
        ESPObjects = {}

        -- Restore lighting
        setFullbright(false)
        setNoFog(false)

        -- Restore FOV
        Camera.FieldOfView = OriginalFOV

        -- Disable no recoil
        disableNoRecoil()
    end

    -- Register cleanup with RAVENHUB
    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(cleanup)
    end

    getgenv().__AR2_CLEANUP = cleanup
end
