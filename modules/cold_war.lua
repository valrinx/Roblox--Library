--[[
    RAVEN HUB Module - Cold War [MOUNTED MGs]
    Game: Cold War (PlaceId: 13687899540, GameId: 4750561026)
    Developer: Grip Studios

    Features:
    - Enemy ESP (Highlight + Name + Distance)
    - Team auto-detect (NATO vs PACT)
    - Fullbright
    - No Fog
    - FOV Changer
    - Characters folder support (game uses workspace.Characters)

    Module format: returns function(Window, runtimeInfo) for RAVENHUB loader
]]

return function(Window, runtimeInfo)
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    -- State
    local State = {
        ESP = false,
        ESPDistance = true,
        ESPNames = true,
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 90,
        MaxDistance = 2000,
    }
    local Connections = {}
    local ESPObjects = {}

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
    local OriginalAtmosphere = {}

    -- Cache atmosphere
    for _, eff in ipairs(Lighting:GetChildren()) do
        if eff:IsA("Atmosphere") then
            OriginalAtmosphere.Density = eff.Density
            OriginalAtmosphere.Offset = eff.Offset
            OriginalAtmosphere.instance = eff
            break
        end
    end

    ---------------------------------------------------------------------------
    -- Utility
    ---------------------------------------------------------------------------

    local function getCharacter(player)
        local chars = workspace:FindFirstChild("Characters")
        if chars then
            return chars:FindFirstChild(player.Name)
        end
        return player.Character
    end

    local function getMyTeam()
        return LP.Team
    end

    local function isEnemy(player)
        if player == LP then return false end
        if not player.Team then return false end
        local myTeam = getMyTeam()
        if not myTeam then return false end
        return player.Team ~= myTeam and player.Team.Name ~= "Neutral"
    end

    local function getHRP(player)
        local char = getCharacter(player)
        if char then
            return char:FindFirstChild("HumanoidRootPart")
        end
        return nil
    end

    local function getMyHRP()
        local char = getCharacter(LP)
        if char then
            return char:FindFirstChild("HumanoidRootPart")
        end
        return nil
    end

    ---------------------------------------------------------------------------
    -- ESP System
    ---------------------------------------------------------------------------

    local espFolder = Instance.new("Folder")
    espFolder.Name = "ColdWar_ESP"
    espFolder.Parent = game:GetService("CoreGui")

    local function createESP(player)
        if ESPObjects[player] then return end

        local highlight = Instance.new("Highlight")
        highlight.FillColor = Color3.fromRGB(255, 30, 30)
        highlight.FillTransparency = 0.65
        highlight.OutlineColor = Color3.fromRGB(255, 60, 60)
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Enabled = false
        highlight.Parent = espFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Size = UDim2.new(0, 200, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
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
        nameLabel.Text = player.DisplayName
        nameLabel.Parent = billboard

        local distLabel = Instance.new("TextLabel")
        distLabel.Size = UDim2.new(1, 0, 0.5, 0)
        distLabel.Position = UDim2.new(0, 0, 0.5, 0)
        distLabel.BackgroundTransparency = 1
        distLabel.TextColor3 = Color3.fromRGB(255, 200, 200)
        distLabel.TextStrokeTransparency = 0.2
        distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        distLabel.TextScaled = true
        distLabel.Font = Enum.Font.Gotham
        distLabel.Text = ""
        distLabel.Parent = billboard

        ESPObjects[player] = {
            highlight = highlight,
            billboard = billboard,
            nameLabel = nameLabel,
            distLabel = distLabel,
        }
    end

    local function removeESP(player)
        local obj = ESPObjects[player]
        if obj then
            obj.highlight:Destroy()
            obj.billboard:Destroy()
            ESPObjects[player] = nil
        end
    end

    local function clearAllESP()
        for player, _ in pairs(ESPObjects) do
            removeESP(player)
        end
    end

    local function updateESP()
        if not State.ESP then
            for _, esp in pairs(ESPObjects) do
                esp.highlight.Enabled = false
                esp.billboard.Enabled = false
            end
            return
        end

        local myHRP = getMyHRP()

        -- Add new enemies
        for _, player in ipairs(Players:GetPlayers()) do
            if isEnemy(player) and not ESPObjects[player] then
                createESP(player)
            end
        end

        for player, esp in pairs(ESPObjects) do
            if not player.Parent then
                removeESP(player)
                continue
            end

            if not isEnemy(player) then
                esp.highlight.Enabled = false
                esp.billboard.Enabled = false
                continue
            end

            local hrp = getHRP(player)
            if hrp then
                local dist = myHRP and (myHRP.Position - hrp.Position).Magnitude or 0

                if dist <= State.MaxDistance then
                    local char = getCharacter(player)
                    esp.highlight.Adornee = char
                    esp.highlight.Enabled = true
                    esp.billboard.Adornee = hrp
                    esp.billboard.Enabled = true

                    esp.nameLabel.Visible = State.ESPNames
                    esp.distLabel.Visible = State.ESPDistance

                    if State.ESPDistance and myHRP then
                        esp.distLabel.Text = string.format("[%dm]", math.floor(dist))
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
    end

    ---------------------------------------------------------------------------
    -- Fullbright / No Fog / FOV
    ---------------------------------------------------------------------------

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
            Lighting.FogEnd = 1000000
            Lighting.FogStart = 1000000
            if OriginalAtmosphere.instance then
                OriginalAtmosphere.instance.Density = 0
            end
        else
            Lighting.FogEnd = OriginalLighting.FogEnd
            Lighting.FogStart = OriginalLighting.FogStart
            if OriginalAtmosphere.instance and OriginalAtmosphere.Density then
                OriginalAtmosphere.instance.Density = OriginalAtmosphere.Density
            end
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
    -- Connections
    ---------------------------------------------------------------------------

    -- Init existing enemies
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p) then createESP(p) end
    end

    Connections.playerAdded = Players.PlayerAdded:Connect(function(p)
        task.wait(1)
        if isEnemy(p) then createESP(p) end
    end)

    Connections.playerRemoving = Players.PlayerRemoving:Connect(function(p)
        removeESP(p)
    end)

    Connections.render = RunService.RenderStepped:Connect(function()
        updateESP()
        if State.FOVEnabled then
            Camera.FieldOfView = State.FOVValue
        end
    end)

    ---------------------------------------------------------------------------
    -- UI Tabs (MacLib via RAVENHUB)
    ---------------------------------------------------------------------------

    local hubUI = runtimeInfo.hubUI or runtimeInfo.hubRayfield

    -- Visuals Tab
    local VisualsTab = Window:CreateTab("Visuals", "eye")

    VisualsTab:CreateSection("Enemy ESP")

    VisualsTab:CreateToggle({
        Name = "Enemy ESP",
        CurrentValue = false,
        Callback = function(v)
            State.ESP = v
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Names",
        CurrentValue = true,
        Callback = function(v)
            State.ESPNames = v
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Callback = function(v)
            State.ESPDistance = v
        end,
    })

    VisualsTab:CreateSlider({
        Name = "Max Distance (studs)",
        Range = {100, 5000},
        Increment = 100,
        CurrentValue = 2000,
        Callback = function(v)
            State.MaxDistance = v
        end,
    })

    VisualsTab:CreateSection("Environment")

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
        Range = {30, 120},
        Increment = 5,
        CurrentValue = 90,
        Callback = function(v)
            State.FOVValue = v
            if State.FOVEnabled then
                Camera.FieldOfView = v
            end
        end,
    })

    -- Info Tab
    local InfoTab = Window:CreateTab("Info", "info")

    InfoTab:CreateSection("Cold War")
    InfoTab:CreateLabel("Team: " .. tostring(getMyTeam() and getMyTeam().Name or "Unknown"))
    InfoTab:CreateLabel("Player: " .. LP.DisplayName)
    InfoTab:CreateLabel("Class: " .. tostring(LP:GetAttribute("ClassType") or "Unknown"))

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    if runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            for _, conn in pairs(Connections) do
                pcall(function() conn:Disconnect() end)
            end
            clearAllESP()
            espFolder:Destroy()
            applyFullbright(false)
            applyNoFog(false)
            applyFOV(false)
        end)
    end
end
