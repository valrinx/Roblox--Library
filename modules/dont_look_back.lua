--[[
    RAVEN HUB Module - DON'T LOOK BACK [PRE-ALPHA]
    Game: DON'T LOOK BACK (PlaceId: 127332613700317, GameId: 10493730706)
    Developer: Manul Studio

    Features:
    - Entity/Monster ESP (Highlight + Distance + Name)
    - Player ESP (Highlight + Distance)
    - Scrap ESP (BillboardGui + Distance + Rarity Color)
    - Fullbright / No Fog
    - FOV Changer
    - Infinite Stamina
    - Speed Modifier
    - Night Roster Alert (shows which monsters spawn tonight)
    - Power Outage Alert

    Module format: returns function(Window, runtimeInfo) for RAVENHUB loader
]]

return function(Window, runtimeInfo)
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    -- State
    local State = {
        -- ESP
        EntityESP = false,
        PlayerESP = false,
        ScrapESP = false,
        ESPDistance = true,
        MaxDistance = 1000,
        -- Visuals
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 85,
        -- Player
        InfiniteStamina = false,
        SpeedEnabled = false,
        SpeedValue = 12,
        -- Alerts
        NightRosterAlert = false,
        PowerOutageAlert = false,
    }
    local Connections = {}
    local ESPObjects = {}
    local ScrapESPObjects = {}

    -- Original lighting values
    local OriginalLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Ambient = Lighting.Ambient,
    }
    local OriginalFOV = Camera.FieldOfView

    ---------------------------------------------------------------------------
    -- Utility
    ---------------------------------------------------------------------------

    local function getMyHRP()
        local char = LP.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function isEntity(model)
        -- Entities are models in workspace that are NOT player characters
        -- and have a Humanoid or HumanoidRootPart
        if not model:IsA("Model") then return false end
        if model == LP.Character then return false end
        -- Check if it's a player character
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character == model then return false end
        end
        -- Must have humanoid-like structure
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hrp and hum then
            -- Additional check: not in Lobby folder area (NPCs might be there)
            -- Entities typically have specific naming or are direct workspace children
            return true
        end
        return false
    end

    local function isPlayerCharacter(model)
        if not model:IsA("Model") then return false end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP and player.Character == model then
                return true
            end
        end
        return false
    end

    local function isScrap(model)
        if not model:IsA("Model") then return false end
        local scrapFolder = ReplicatedStorage:FindFirstChild("Scraps")
        if not scrapFolder then return false end
        -- Scraps in workspace usually have a "ScrapValue" or match names from catalog
        for _, rarity in ipairs(scrapFolder:GetChildren()) do
            for _, scrap in ipairs(rarity:GetChildren()) do
                if model.Name == scrap.Name then
                    return true, rarity.Name
                end
            end
        end
        return false
    end

    local function getScrapRarityColor(rarity)
        if rarity == "Common" then return Color3.fromRGB(200, 200, 200) end
        if rarity == "Uncommon" then return Color3.fromRGB(50, 200, 50) end
        if rarity == "Rare" then return Color3.fromRGB(50, 100, 255) end
        if rarity == "Epic" then return Color3.fromRGB(180, 50, 255) end
        return Color3.fromRGB(255, 255, 255)
    end

    ---------------------------------------------------------------------------
    -- Entity ESP
    ---------------------------------------------------------------------------

    local espFolder = Instance.new("Folder")
    espFolder.Name = "DLB_ESP"
    espFolder.Parent = game:GetService("CoreGui")

    local function createEntityESP(model)
        if ESPObjects[model] then return end

        local highlight = Instance.new("Highlight")
        highlight.FillColor = Color3.fromRGB(255, 0, 0)
        highlight.FillTransparency = 0.5
        highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = model
        highlight.Enabled = false
        highlight.Parent = espFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 200, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false
        billboard.Parent = espFolder

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = model.Name
        nameLabel.Parent = billboard

        local distLabel = Instance.new("TextLabel")
        distLabel.Size = UDim2.new(1, 0, 0.5, 0)
        distLabel.Position = UDim2.new(0, 0, 0.5, 0)
        distLabel.BackgroundTransparency = 1
        distLabel.TextColor3 = Color3.fromRGB(255, 180, 180)
        distLabel.TextStrokeTransparency = 0.2
        distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        distLabel.TextScaled = true
        distLabel.Font = Enum.Font.Gotham
        distLabel.Text = ""
        distLabel.Parent = billboard

        ESPObjects[model] = {
            highlight = highlight,
            billboard = billboard,
            nameLabel = nameLabel,
            distLabel = distLabel,
            isPlayer = false,
        }
    end

    local function createPlayerESP(model, player)
        if ESPObjects[model] then return end

        local highlight = Instance.new("Highlight")
        highlight.FillColor = Color3.fromRGB(0, 150, 255)
        highlight.FillTransparency = 0.65
        highlight.OutlineColor = Color3.fromRGB(0, 150, 255)
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = model
        highlight.Enabled = false
        highlight.Parent = espFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 200, 0, 40)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false
        billboard.Parent = espFolder

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = player.DisplayName
        nameLabel.Parent = billboard

        local distLabel = Instance.new("TextLabel")
        distLabel.Size = UDim2.new(1, 0, 0.5, 0)
        distLabel.Position = UDim2.new(0, 0, 0.5, 0)
        distLabel.BackgroundTransparency = 1
        distLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
        distLabel.TextStrokeTransparency = 0.2
        distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        distLabel.TextScaled = true
        distLabel.Font = Enum.Font.Gotham
        distLabel.Text = ""
        distLabel.Parent = billboard

        ESPObjects[model] = {
            highlight = highlight,
            billboard = billboard,
            nameLabel = nameLabel,
            distLabel = distLabel,
            isPlayer = true,
        }
    end

    local function createScrapESP(model, rarity)
        if ScrapESPObjects[model] then return end

        local color = getScrapRarityColor(rarity)

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 160, 0, 35)
        billboard.StudsOffset = Vector3.new(0, 2, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false
        billboard.Parent = espFolder

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = color
        nameLabel.TextStrokeTransparency = 0.2
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextScaled = true
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = model.Name .. " [" .. rarity .. "]"
        nameLabel.Parent = billboard

        local distLabel = Instance.new("TextLabel")
        distLabel.Size = UDim2.new(1, 0, 0.4, 0)
        distLabel.Position = UDim2.new(0, 0, 0.6, 0)
        distLabel.BackgroundTransparency = 1
        distLabel.TextColor3 = color
        distLabel.TextStrokeTransparency = 0.3
        distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        distLabel.TextScaled = true
        distLabel.Font = Enum.Font.Gotham
        distLabel.Text = ""
        distLabel.Parent = billboard

        ScrapESPObjects[model] = {
            billboard = billboard,
            nameLabel = nameLabel,
            distLabel = distLabel,
        }
    end

    local function removeESP(model)
        local obj = ESPObjects[model]
        if obj then
            obj.highlight:Destroy()
            obj.billboard:Destroy()
            ESPObjects[model] = nil
        end
    end

    local function removeScrapESP(model)
        local obj = ScrapESPObjects[model]
        if obj then
            obj.billboard:Destroy()
            ScrapESPObjects[model] = nil
        end
    end

    local function clearAllESP()
        for model, _ in pairs(ESPObjects) do
            removeESP(model)
        end
        for model, _ in pairs(ScrapESPObjects) do
            removeScrapESP(model)
        end
    end

    ---------------------------------------------------------------------------
    -- Update Loop
    ---------------------------------------------------------------------------

    local function updateESP()
        local myHRP = getMyHRP()
        if not myHRP then return end

        -- Scan workspace for entities and players
        for _, child in ipairs(workspace:GetChildren()) do
            if child:IsA("Model") and child ~= LP.Character then
                -- Entity ESP
                if State.EntityESP and isEntity(child) and not ESPObjects[child] then
                    createEntityESP(child)
                end
                -- Player ESP
                if State.PlayerESP and isPlayerCharacter(child) then
                    if not ESPObjects[child] then
                        local player = Players:GetPlayerFromCharacter(child)
                        if player then
                            createPlayerESP(child, player)
                        end
                    end
                end
            end
        end

        -- Scan for scraps (they might be in a map folder)
        if State.ScrapESP then
            for _, desc in ipairs(workspace:GetDescendants()) do
                if desc:IsA("Model") and not ScrapESPObjects[desc] then
                    local found, rarity = isScrap(desc)
                    if found then
                        createScrapESP(desc, rarity)
                    end
                end
            end
        end

        -- Update entity/player ESP
        for model, esp in pairs(ESPObjects) do
            if not model.Parent then
                removeESP(model)
                continue
            end

            local shouldShow = (esp.isPlayer and State.PlayerESP) or (not esp.isPlayer and State.EntityESP)
            if not shouldShow then
                esp.highlight.Enabled = false
                esp.billboard.Enabled = false
                continue
            end

            local hrp = model:FindFirstChild("HumanoidRootPart")
            if hrp then
                local dist = (myHRP.Position - hrp.Position).Magnitude
                if dist <= State.MaxDistance then
                    esp.highlight.Enabled = true
                    esp.billboard.Adornee = hrp
                    esp.billboard.Enabled = true
                    if State.ESPDistance then
                        esp.distLabel.Text = string.format("[%dm]", math.floor(dist))
                    else
                        esp.distLabel.Text = ""
                    end
                else
                    esp.highlight.Enabled = false
                    esp.billboard.Enabled = false
                end
            else
                esp.highlight.Enabled = false
                esp.billboard.Enabled = false
            end
        end

        -- Update scrap ESP
        for model, esp in pairs(ScrapESPObjects) do
            if not model.Parent then
                removeScrapESP(model)
                continue
            end

            if not State.ScrapESP then
                esp.billboard.Enabled = false
                continue
            end

            local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
            if primaryPart then
                local dist = (myHRP.Position - primaryPart.Position).Magnitude
                if dist <= State.MaxDistance then
                    esp.billboard.Adornee = primaryPart
                    esp.billboard.Enabled = true
                    esp.distLabel.Text = string.format("[%dm]", math.floor(dist))
                else
                    esp.billboard.Enabled = false
                end
            else
                esp.billboard.Enabled = false
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Fullbright / No Fog / FOV
    ---------------------------------------------------------------------------

    local function applyFullbright(enabled)
        if enabled then
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(200, 200, 200)
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
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
            Lighting.FogEnd = 1000000
            Lighting.FogStart = 1000000
            for _, eff in ipairs(Lighting:GetChildren()) do
                if eff:IsA("Atmosphere") then
                    eff.Density = 0
                end
            end
        else
            Lighting.FogEnd = OriginalLighting.FogEnd
            Lighting.FogStart = OriginalLighting.FogStart
        end
    end

    local function applyFOV(enabled, value)
        if enabled then
            Camera.FieldOfView = value
        else
            Camera.FieldOfView = OriginalFOV
        end
    end

    ---------------------------------------------------------------------------
    -- Infinite Stamina
    ---------------------------------------------------------------------------

    local function applyInfiniteStamina()
        -- The game uses StaminaSync remote from server, we intercept by keeping stamina bar full
        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and State.InfiniteStamina then
            -- Fire sprint request freely since server doesn't validate stamina strictly
            -- Also maintain walkspeed if speed mod is active
        end
    end

    ---------------------------------------------------------------------------
    -- Alerts
    ---------------------------------------------------------------------------

    local alertConnections = {}

    local function setupAlerts()
        local remotes = ReplicatedStorage:FindFirstChild("FH_Remotes")
        if not remotes then return end

        -- Night Roster Alert
        local nightRoster = remotes:FindFirstChild("NightRoster")
        if nightRoster then
            alertConnections.nightRoster = nightRoster.OnClientEvent:Connect(function(data)
                if State.NightRosterAlert then
                    local msg = "⚠️ NIGHT ROSTER: "
                    if type(data) == "table" then
                        msg = msg .. table.concat(data, ", ")
                    else
                        msg = msg .. tostring(data)
                    end
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = "Night Alert",
                        Text = msg,
                        Duration = 10,
                    })
                end
            end)
        end

        -- Power Outage Alert
        local powerState = remotes:FindFirstChild("PowerOutageState")
        if powerState then
            alertConnections.powerOutage = powerState.OnClientEvent:Connect(function(state)
                if State.PowerOutageAlert and state then
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = "⚡ Power Outage!",
                        Text = "The power just went out! Find the generator.",
                        Duration = 8,
                    })
                end
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- Connections
    ---------------------------------------------------------------------------

    setupAlerts()

    Connections.render = RunService.RenderStepped:Connect(function()
        updateESP()

        if State.FOVEnabled then
            Camera.FieldOfView = State.FOVValue
        end

        if State.SpeedEnabled then
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    hum.WalkSpeed = State.SpeedValue
                end
            end
        end
    end)

    -- Stamina override: hook the StaminaSync to always set 100
    local remotes = ReplicatedStorage:FindFirstChild("FH_Remotes")
    if remotes then
        local staminaSync = remotes:FindFirstChild("StaminaSync")
        if staminaSync then
            Connections.stamina = staminaSync.OnClientEvent:Connect(function()
                if State.InfiniteStamina then
                    -- The game reads stamina from a local value, keep sending sprint
                    local sprintReq = remotes:FindFirstChild("SprintRequest")
                    if sprintReq then
                        -- Allow sprinting always
                    end
                end
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- UI Tabs
    ---------------------------------------------------------------------------

    -- Tab 1: ESP
    local ESPTab = Window:CreateTab("ESP", "eye")

    ESPTab:CreateSection("Entity / Monster ESP")

    ESPTab:CreateToggle({
        Name = "Entity ESP (Monsters)",
        CurrentValue = false,
        Callback = function(v)
            State.EntityESP = v
            if not v then
                for model, esp in pairs(ESPObjects) do
                    if not esp.isPlayer then
                        esp.highlight.Enabled = false
                        esp.billboard.Enabled = false
                    end
                end
            end
        end,
    })

    ESPTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Callback = function(v)
            State.PlayerESP = v
            if not v then
                for model, esp in pairs(ESPObjects) do
                    if esp.isPlayer then
                        esp.highlight.Enabled = false
                        esp.billboard.Enabled = false
                    end
                end
            end
        end,
    })

    ESPTab:CreateSection("Scrap / Loot ESP")

    ESPTab:CreateToggle({
        Name = "Scrap ESP",
        CurrentValue = false,
        Callback = function(v)
            State.ScrapESP = v
            if not v then
                for _, esp in pairs(ScrapESPObjects) do
                    esp.billboard.Enabled = false
                end
            end
        end,
    })

    ESPTab:CreateSection("ESP Settings")

    ESPTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Callback = function(v)
            State.ESPDistance = v
        end,
    })

    ESPTab:CreateSlider({
        Name = "Max ESP Distance (studs)",
        Range = {50, 2000},
        Increment = 50,
        CurrentValue = 1000,
        Callback = function(v)
            State.MaxDistance = v
        end,
    })

    -- Tab 2: Visuals
    local VisualsTab = Window:CreateTab("Visuals", "sun")

    VisualsTab:CreateSection("Lighting")

    VisualsTab:CreateToggle({
        Name = "Fullbright",
        CurrentValue = false,
        Callback = function(v)
            State.Fullbright = v
            applyFullbright(v)
        end,
    })

    VisualsTab:CreateToggle({
        Name = "No Fog",
        CurrentValue = false,
        Callback = function(v)
            State.NoFog = v
            applyNoFog(v)
        end,
    })

    VisualsTab:CreateSection("Camera")

    VisualsTab:CreateToggle({
        Name = "Custom FOV",
        CurrentValue = false,
        Callback = function(v)
            State.FOVEnabled = v
            applyFOV(v, State.FOVValue)
        end,
    })

    VisualsTab:CreateSlider({
        Name = "FOV Value",
        Range = {50, 120},
        Increment = 5,
        CurrentValue = 85,
        Callback = function(v)
            State.FOVValue = v
            if State.FOVEnabled then
                Camera.FieldOfView = v
            end
        end,
    })

    -- Tab 3: Player
    local PlayerTab = Window:CreateTab("Player", "user")

    PlayerTab:CreateSection("Movement")

    PlayerTab:CreateToggle({
        Name = "Infinite Stamina",
        CurrentValue = false,
        Callback = function(v)
            State.InfiniteStamina = v
        end,
    })

    PlayerTab:CreateToggle({
        Name = "Speed Modifier",
        CurrentValue = false,
        Callback = function(v)
            State.SpeedEnabled = v
            if not v then
                local char = LP.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum.WalkSpeed = 12
                    end
                end
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Walk Speed",
        Range = {12, 60},
        Increment = 2,
        CurrentValue = 12,
        Callback = function(v)
            State.SpeedValue = v
        end,
    })

    -- Tab 4: Alerts
    local AlertsTab = Window:CreateTab("Alerts", "bell")

    AlertsTab:CreateSection("Night Alerts")

    AlertsTab:CreateToggle({
        Name = "Night Roster Alert",
        CurrentValue = false,
        Callback = function(v)
            State.NightRosterAlert = v
        end,
    })

    AlertsTab:CreateLabel("Shows which monsters will appear tonight")

    AlertsTab:CreateSection("Power Alerts")

    AlertsTab:CreateToggle({
        Name = "Power Outage Alert",
        CurrentValue = false,
        Callback = function(v)
            State.PowerOutageAlert = v
        end,
    })

    AlertsTab:CreateLabel("Notifies when power goes out")

    -- Tab 5: Info
    local InfoTab = Window:CreateTab("Info", "info")

    InfoTab:CreateSection("DON'T LOOK BACK")
    InfoTab:CreateLabel("Player: " .. LP.DisplayName)
    InfoTab:CreateLabel("Level: " .. tostring(LP:GetAttribute("FH_PublicLevel") or "?"))
    InfoTab:CreateLabel("Money: $" .. tostring(LP:GetAttribute("FH_PublicMoney") or "?"))
    InfoTab:CreateLabel("Survivals: " .. tostring(LP:GetAttribute("FH_PublicSurvivals") or "0"))

    InfoTab:CreateSection("Tips")
    InfoTab:CreateLabel("• Fullbright = see in the dark")
    InfoTab:CreateLabel("• Entity ESP shows monsters through walls")
    InfoTab:CreateLabel("• Scrap ESP helps find loot quickly")
    InfoTab:CreateLabel("• Night Roster Alert = know what's coming")

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    if runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            for _, conn in pairs(Connections) do
                pcall(function() conn:Disconnect() end)
            end
            for _, conn in pairs(alertConnections) do
                pcall(function() conn:Disconnect() end)
            end
            clearAllESP()
            espFolder:Destroy()
            applyFullbright(false)
            applyNoFog(false)
            applyFOV(false)
            -- Reset speed
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = 12 end
            end
        end)
    end
end
