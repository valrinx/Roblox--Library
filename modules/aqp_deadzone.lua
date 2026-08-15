--[[
    RAVEN HUB Module - A Quiet Place: Deadzone
    Game: A Quiet Place: Deadzone (PlaceId: 106920577206536, GameId: 9889811676)
    
    Features:
    - Monster ESP (Red highlights + nametags)
    - Item ESP (Green highlights + nametags)
    - Player ESP (Blue highlights + nametags)
    - Fullbright (Remove darkness/fog)
    - Speed Hack (Adjustable WalkSpeed)
    - NoClip (Walk through walls)
    - Infinite Stamina
    - Infinite Hydration
    - Infinite Satiation
    
    Module format: returns function(Window, runtimeInfo) for RAVENHUB loader
]]

return function(Window, runtimeInfo)
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local LP = Players.LocalPlayer

    -- State
    local State = {
        ESP_Monsters = false,
        ESP_Items = false,
        ESP_Players = false,
        InfiniteStamina = false,
        InfiniteHydration = false,
        InfiniteSatiation = false,
        SpeedHack = false,
        SpeedValue = 50,
        Fullbright = false,
        NoClip = false,
    }
    local Connections = {}
    local ESPObjects = {}

    -- Store original lighting values
    local OriginalLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
    }

    ---------------------------------------------------------------------------
    -- ESP System
    ---------------------------------------------------------------------------
    local function createESP(inst, color, text)
        if ESPObjects[inst] then return end

        local highlight = Instance.new("Highlight")
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.FillTransparency = 0.7
        highlight.OutlineTransparency = 0.3
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = inst

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESP_Label"
        billboard.Size = UDim2.new(0, 140, 0, 22)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = inst

        local label = Instance.new("TextLabel")
        label.Text = text
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.4
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.BackgroundTransparency = 1
        label.Size = UDim2.new(1, 0, 1, 0)
        label.Parent = billboard

        ESPObjects[inst] = { highlight, billboard }
    end

    local function removeESP(inst)
        if not ESPObjects[inst] then return end
        for _, obj in pairs(ESPObjects[inst]) do
            pcall(function() obj:Destroy() end)
        end
        ESPObjects[inst] = nil
    end

    local function clearESPByType(espType)
        for inst, _ in pairs(ESPObjects) do
            local shouldRemove = false
            if espType == "Monster" and inst.Parent == workspace:FindFirstChild("_Monsters") then
                shouldRemove = true
            elseif espType == "Item" and inst.Parent == workspace:FindFirstChild("_Items") then
                shouldRemove = true
            elseif espType == "Player" and Players:GetPlayerFromCharacter(inst) then
                shouldRemove = true
            end
            if shouldRemove then
                removeESP(inst)
            end
        end
    end

    local function updateMonsterESP()
        if not State.ESP_Monsters then
            clearESPByType("Monster")
            return
        end
        local folder = workspace:FindFirstChild("_Monsters")
        if not folder then return end
        for _, monster in folder:GetChildren() do
            if monster:IsA("Model") and not ESPObjects[monster] then
                createESP(monster, Color3.fromRGB(255, 55, 55), monster.Name)
            end
        end
    end

    local function updateItemESP()
        if not State.ESP_Items then
            clearESPByType("Item")
            return
        end
        local folder = workspace:FindFirstChild("_Items")
        if not folder then return end
        for _, item in folder:GetChildren() do
            if item:IsA("Model") and not ESPObjects[item] then
                createESP(item, Color3.fromRGB(80, 255, 80), item.Name)
            end
        end
    end

    local function updatePlayerESP()
        if not State.ESP_Players then
            clearESPByType("Player")
            return
        end
        for _, player in Players:GetPlayers() do
            if player ~= LP and player.Character and not ESPObjects[player.Character] then
                createESP(player.Character, Color3.fromRGB(85, 170, 255), player.Name)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Fullbright
    ---------------------------------------------------------------------------
    local function setFullbright(enabled)
        if enabled then
            Lighting.Brightness = 3
            Lighting.ClockTime = 12
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            for _, effect in Lighting:GetDescendants() do
                if effect:IsA("Atmosphere") then effect.Density = 0 end
                if effect:IsA("BloomEffect") then effect.Enabled = false end
                if effect:IsA("ColorCorrectionEffect") then effect.Enabled = false end
            end
        else
            Lighting.Brightness = OriginalLighting.Brightness
            Lighting.ClockTime = OriginalLighting.ClockTime
            Lighting.FogEnd = OriginalLighting.FogEnd
            Lighting.GlobalShadows = OriginalLighting.GlobalShadows
            for _, effect in Lighting:GetDescendants() do
                if effect:IsA("Atmosphere") then effect.Density = 0.3 end
                if effect:IsA("BloomEffect") then effect.Enabled = true end
                if effect:IsA("ColorCorrectionEffect") then effect.Enabled = true end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Core Loops
    ---------------------------------------------------------------------------
    Connections.noclip = RunService.Stepped:Connect(function()
        if not State.NoClip then return end
        local char = LP.Character
        if not char then return end
        for _, part in char:GetDescendants() do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)

    local tickCounter = 0
    Connections.main = RunService.Heartbeat:Connect(function()
        local char = LP.Character
        if not char then return end

        -- Infinite Stats
        local values = char:FindFirstChild("Values")
        if values then
            if State.InfiniteStamina then
                local s = values:FindFirstChild("Stamina")
                if s and s.Value < 100 then s.Value = 100 end
            end
            if State.InfiniteHydration then
                local h = values:FindFirstChild("Hydration")
                if h and h.Value < 100 then h.Value = 100 end
            end
            if State.InfiniteSatiation then
                local st = values:FindFirstChild("Satiation")
                if st and st.Value < 100 then st.Value = 100 end
            end
        end

        -- Speed Hack
        if State.SpeedHack then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.WalkSpeed = State.SpeedValue end
        end

        -- ESP update (every 30 frames to reduce overhead)
        tickCounter = tickCounter + 1
        if tickCounter >= 30 then
            tickCounter = 0
            if State.ESP_Monsters then updateMonsterESP() end
            if State.ESP_Items then updateItemESP() end
            if State.ESP_Players then updatePlayerESP() end
        end
    end)

    ---------------------------------------------------------------------------
    -- UI Tabs
    ---------------------------------------------------------------------------
    local visualsTab = Window:CreateTab("Visuals", "esp")
    visualsTab:CreateSection("ESP")
    visualsTab:CreateToggle({
        Name = "Monster ESP",
        CurrentValue = false,
        Flag = "AQP_MonsterESP",
        Callback = function(value)
            State.ESP_Monsters = value
            if value then updateMonsterESP() else clearESPByType("Monster") end
        end,
    })
    visualsTab:CreateToggle({
        Name = "Item ESP",
        CurrentValue = false,
        Flag = "AQP_ItemESP",
        Callback = function(value)
            State.ESP_Items = value
            if value then updateItemESP() else clearESPByType("Item") end
        end,
    })
    visualsTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "AQP_PlayerESP",
        Callback = function(value)
            State.ESP_Players = value
            if value then updatePlayerESP() else clearESPByType("Player") end
        end,
    })
    visualsTab:CreateSection("Lighting")
    visualsTab:CreateToggle({
        Name = "Fullbright",
        CurrentValue = false,
        Flag = "AQP_Fullbright",
        Callback = function(value)
            State.Fullbright = value
            setFullbright(value)
        end,
    })

    local movementTab = Window:CreateTab("Movement", "movement")
    movementTab:CreateSection("Speed")
    movementTab:CreateToggle({
        Name = "Speed Hack",
        CurrentValue = false,
        Flag = "AQP_SpeedHack",
        Callback = function(value)
            State.SpeedHack = value
            if not value then
                local char = LP.Character
                if char then
                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    if humanoid then humanoid.WalkSpeed = 16 end
                end
            end
        end,
    })
    movementTab:CreateSlider({
        Name = "Speed Value",
        Range = { 16, 200 },
        Increment = 1,
        CurrentValue = 50,
        Suffix = " studs/s",
        Flag = "AQP_SpeedValue",
        Callback = function(value)
            State.SpeedValue = value
        end,
    })
    movementTab:CreateSection("Physics")
    movementTab:CreateToggle({
        Name = "NoClip",
        CurrentValue = false,
        Flag = "AQP_NoClip",
        Callback = function(value)
            State.NoClip = value
        end,
    })

    local playerTab = Window:CreateTab("Player", "player")
    playerTab:CreateSection("Survival Stats")
    playerTab:CreateToggle({
        Name = "Infinite Stamina",
        CurrentValue = false,
        Flag = "AQP_InfStamina",
        Callback = function(value)
            State.InfiniteStamina = value
        end,
    })
    playerTab:CreateToggle({
        Name = "Infinite Hydration",
        CurrentValue = false,
        Flag = "AQP_InfHydration",
        Callback = function(value)
            State.InfiniteHydration = value
        end,
    })
    playerTab:CreateToggle({
        Name = "Infinite Satiation",
        CurrentValue = false,
        Flag = "AQP_InfSatiation",
        Callback = function(value)
            State.InfiniteSatiation = value
        end,
    })

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------
    local function cleanup()
        for _, conn in pairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
        Connections = {}
        for inst, _ in pairs(ESPObjects) do
            removeESP(inst)
        end
        ESPObjects = {}
        setFullbright(false)
        local char = LP.Character
        if char then
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.WalkSpeed = 16 end
        end
    end

    -- Register cleanup with RAVENHUB
    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(cleanup)
    end

    getgenv().__AQP_CLEANUP = function()
        cleanup()
    end
end
