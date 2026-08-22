--[[
    RAVEN HUB Module - Cold War [MOUNTED MGs]
    Game: Cold War (PlaceId: 13687899540, GameId: 4750561026)
    Developer: Grip Studios

    Features:
    - Enemy ESP (Highlight + Name + Distance + Wall Check)
    - Aim Prediction (Bullet Drop + Drag + Lead + Auto Weapon Detect)
    - Team auto-detect (NATO vs PACT)
    - Fullbright
    - No Fog
    - FOV Changer
    - Characters folder support (game uses workspace.Characters)
    - v1.1 Smooth Auto Aim, Match Dashboard, Tactical Radar

    Module format: returns function(Window, runtimeInfo) for RAVENHUB loader
]]

return function(Window, runtimeInfo)
    pcall(function()
        local previous = getgenv().__RAVEN_COLD_WAR
        if previous and type(previous.Destroy) == "function" then previous.Destroy() end
    end)
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local UserInputService = game:GetService("UserInputService")
    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    -- State
    local State = {
        ESP = false,
        ESPDistance = true,
        ESPNames = true,
        ESPWallCheck = true,
        Fullbright = false,
        NoFog = false,
        FOVEnabled = false,
        FOVValue = 90,
        MaxDistance = 2000,
        -- Aim Prediction
        AimPrediction = false,
        PredictDotSize = 6,
        PredictTargetPart = "Head",
        AutoAim = false,
        AimFOV = 180,
        AimSmoothness = 0.18,
        AimVisibleCheck = true,
        AimActivation = "Right Mouse",
        StickyTarget = true,
        Radar = false,
        RadarRange = 700,
        RadarSize = 150,
    }
    local Connections = {}
    local ESPObjects = {}
    local rightMouseDown = false
    local lockedTarget = nil

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
    -- Visibility Check (Raycast)
    ---------------------------------------------------------------------------

    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude

    local COLOR_VISIBLE = Color3.fromRGB(255, 30, 30)
    local COLOR_HIDDEN  = Color3.fromRGB(0, 255, 80)
    local COLOR_TEXT_VISIBLE = Color3.fromRGB(255, 60, 60)
    local COLOR_TEXT_HIDDEN  = Color3.fromRGB(0, 255, 100)

    local function buildRayFilter()
        local ignore = {}
        local chars = workspace:FindFirstChild("Characters")
        if chars then table.insert(ignore, chars) end
        local myChar = getCharacter(LP)
        if myChar then table.insert(ignore, myChar) end
        for _, name in ipairs({"Ignore", "Effects", "Debris"}) do
            local folder = workspace:FindFirstChild(name)
            if folder then table.insert(ignore, folder) end
        end
        RayParams.FilterDescendantsInstances = ignore
    end

    local function isVisible(fromPos, toPos)
        buildRayFilter()
        local direction = toPos - fromPos
        local result = workspace:Raycast(fromPos, direction, RayParams)
        return result == nil
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
        highlight.FillColor = COLOR_VISIBLE
        highlight.FillTransparency = 0.65
        highlight.OutlineColor = COLOR_VISIBLE
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
        nameLabel.TextColor3 = COLOR_TEXT_VISIBLE
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

                    if State.ESPWallCheck and myHRP then
                        local camPos = Camera.CFrame.Position
                        local visible = isVisible(camPos, hrp.Position)
                        if visible then
                            esp.highlight.FillColor = COLOR_VISIBLE
                            esp.highlight.OutlineColor = COLOR_VISIBLE
                            esp.nameLabel.TextColor3 = COLOR_TEXT_VISIBLE
                        else
                            esp.highlight.FillColor = COLOR_HIDDEN
                            esp.highlight.OutlineColor = COLOR_HIDDEN
                            esp.nameLabel.TextColor3 = COLOR_TEXT_HIDDEN
                        end
                    else
                        esp.highlight.FillColor = COLOR_VISIBLE
                        esp.highlight.OutlineColor = COLOR_VISIBLE
                        esp.nameLabel.TextColor3 = COLOR_TEXT_VISIBLE
                    end

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
    -- Aim Prediction System
    ---------------------------------------------------------------------------

    local GRAVITY = workspace.Gravity -- 75 studs/s^2
    local WCM = game.ReplicatedStorage.Shared.WeaponConfigManager

    -- Cache weapon configs
    local WeaponCache = {}
    local function getWeaponConfig(weaponName)
        if WeaponCache[weaponName] then return WeaponCache[weaponName] end
        local configModule = WCM:FindFirstChild(weaponName)
        if not configModule then return nil end
        local ok, data = pcall(require, configModule)
        if not ok or type(data) ~= "table" then return nil end
        local cfg = data[1]
        if not cfg or not cfg.BulletSettings or not cfg.BulletSettings[1] then return nil end
        local bs = cfg.BulletSettings[1]
        local result = {
            MuzzleVelocity = bs.MuzzleVelocity or 3000,
            Drag = bs.Drag or 1,
            Spread = cfg.Spread or 1,
            Name = weaponName,
        }
        WeaponCache[weaponName] = result
        return result
    end

    -- Detect current equipped weapon
    local function getCurrentWeaponConfig()
        local char = getCharacter(LP)
        if not char then return nil end
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then
                local cfg = getWeaponConfig(child.Name)
                if cfg then return cfg end
            end
        end
        return nil
    end

    -- Calculate bullet travel time with drag (exponential decay model)
    local function getBulletTravelTime(distance, muzzleVelocity, drag)
        local dragFactor = drag * 0.3
        local t = 0
        for _ = 1, 2000 do
            local pos = (muzzleVelocity / dragFactor) * (1 - math.exp(-dragFactor * t))
            if pos >= distance then return t end
            t = t + 0.01
        end
        return t
    end

    -- Calculate bullet drop at given time
    local function getBulletDrop(time)
        return 0.5 * GRAVITY * time * time
    end

    -- Get target velocity (movement prediction)
    local lastPositions = {}
    local lastPositionTimes = {}

    local function getTargetVelocity(player)
        local hrp = getHRP(player)
        if not hrp then return Vector3.zero end

        local currentPos = hrp.Position
        local currentTime = tick()
        local lastPos = lastPositions[player]
        local lastTime = lastPositionTimes[player]

        lastPositions[player] = currentPos
        lastPositionTimes[player] = currentTime

        if lastPos and lastTime then
            local dt = currentTime - lastTime
            if dt > 0 and dt < 1 then
                return (currentPos - lastPos) / dt
            end
        end
        return Vector3.zero
    end

    -- Calculate predicted aim point
    local function getPredictedPosition(targetPos, targetVelocity, weaponConfig, shooterPos)
        if not weaponConfig then return targetPos, 0 end

        local direction = targetPos - shooterPos
        local horizontalDist = Vector3.new(direction.X, 0, direction.Z).Magnitude

        local travelTime = getBulletTravelTime(horizontalDist, weaponConfig.MuzzleVelocity, weaponConfig.Drag)
        local leadOffset = targetVelocity * travelTime
        local drop = getBulletDrop(travelTime)

        local predicted = targetPos + leadOffset + Vector3.new(0, drop, 0)
        return predicted, travelTime
    end

    -- Prediction dot (Drawing API)
    local predictionDot = nil
    local predictionCircle = nil
    local predictionText = nil

    local function createPredictionDot()
        if predictionDot then return end
        predictionDot = Drawing.new("Circle")
        predictionDot.Color = Color3.fromRGB(255, 255, 0)
        predictionDot.Filled = true
        predictionDot.Thickness = 1
        predictionDot.Radius = State.PredictDotSize
        predictionDot.Transparency = 1
        predictionDot.Visible = false

        predictionCircle = Drawing.new("Circle")
        predictionCircle.Color = Color3.fromRGB(255, 255, 0)
        predictionCircle.Filled = false
        predictionCircle.Thickness = 2
        predictionCircle.Radius = State.PredictDotSize + 4
        predictionCircle.Transparency = 1
        predictionCircle.Visible = false

        predictionText = Drawing.new("Text")
        predictionText.Color = Color3.fromRGB(255, 255, 100)
        predictionText.Size = 14
        predictionText.Center = true
        predictionText.Outline = true
        predictionText.OutlineColor = Color3.new(0, 0, 0)
        predictionText.Font = Drawing.Fonts.Monospace
        predictionText.Visible = false
    end

    local function destroyPredictionDot()
        if predictionDot then predictionDot:Remove(); predictionDot = nil end
        if predictionCircle then predictionCircle:Remove(); predictionCircle = nil end
        if predictionText then predictionText:Remove(); predictionText = nil end
    end

    -- Find closest enemy to crosshair
    local function getClosestEnemyToCrosshair(maxPixels, requireVisible)
        local closestPlayer = nil
        local closestDist = math.huge
        local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

        for _, player in ipairs(Players:GetPlayers()) do
            if not isEnemy(player) then continue end
            local char = getCharacter(player)
            if not char then continue end
            local targetPart = char:FindFirstChild(State.PredictTargetPart) or char:FindFirstChild("Head")
            if not targetPart then continue end

            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if not onScreen then continue end

            local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
            if (not maxPixels or dist2D <= maxPixels) and dist2D < closestDist
                and (not requireVisible or isVisible(Camera.CFrame.Position, targetPart.Position)) then
                closestDist = dist2D
                closestPlayer = player
            end
        end
        return closestPlayer
    end

    local function aimActive()
        return State.AutoAim and (State.AimActivation == "Always" or rightMouseDown)
    end

    local function validAimTarget(player)
        if not player or not isEnemy(player) then return false end
        local char = getCharacter(player)
        local part = char and (char:FindFirstChild(State.PredictTargetPart) or char:FindFirstChild("Head"))
        if not part then return false end
        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then return false end
        local center = Camera.ViewportSize * 0.5
        if (Vector2.new(point.X, point.Y) - center).Magnitude > State.AimFOV then return false end
        return not State.AimVisibleCheck or isVisible(Camera.CFrame.Position, part.Position)
    end

    local function updateAutoAim()
        if not aimActive() then lockedTarget = nil return end
        if not State.StickyTarget or not validAimTarget(lockedTarget) then
            lockedTarget = getClosestEnemyToCrosshair(State.AimFOV, State.AimVisibleCheck)
        end
        if not lockedTarget then return end
        local char = getCharacter(lockedTarget)
        local part = char and (char:FindFirstChild(State.PredictTargetPart) or char:FindFirstChild("Head"))
        if not part then return end
        local cfg = getCurrentWeaponConfig()
        local predicted = getPredictedPosition(part.Position, getTargetVelocity(lockedTarget), cfg, Camera.CFrame.Position)
        local point, onScreen = Camera:WorldToViewportPoint(predicted)
        if not onScreen then return end
        local center = Camera.ViewportSize * 0.5
        local delta = Vector2.new(point.X, point.Y) - center
        if type(mousemoverel) == "function" then
            pcall(mousemoverel, delta.X * State.AimSmoothness, delta.Y * State.AimSmoothness)
        else
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, predicted), State.AimSmoothness)
        end
    end

    local aimFovCircle = Drawing.new("Circle")
    aimFovCircle.Filled = false
    aimFovCircle.Thickness = 1.5
    aimFovCircle.Color = Color3.fromRGB(255, 90, 90)
    aimFovCircle.Transparency = 0.65
    aimFovCircle.Visible = false

    local radarCircle = Drawing.new("Circle")
    radarCircle.Filled = true
    radarCircle.Color = Color3.fromRGB(12, 16, 22)
    radarCircle.Transparency = 0.65
    radarCircle.Visible = false
    local radarOutline = Drawing.new("Circle")
    radarOutline.Filled = false
    radarOutline.Thickness = 2
    radarOutline.Color = Color3.fromRGB(120, 180, 255)
    radarOutline.Visible = false
    local radarBlips = {}

    local function hideRadarBlips()
        for _, blip in pairs(radarBlips) do blip.Visible = false end
    end

    local function updateRadar()
        local center = Vector2.new(State.RadarSize + 24, Camera.ViewportSize.Y - State.RadarSize - 44)
        radarCircle.Position, radarOutline.Position = center, center
        radarCircle.Radius, radarOutline.Radius = State.RadarSize, State.RadarSize
        radarCircle.Visible, radarOutline.Visible = State.Radar, State.Radar
        if not State.Radar then hideRadarBlips() return end
        local myRoot = getMyHRP()
        if not myRoot then hideRadarBlips() return end
        local active = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if isEnemy(player) then
                local root = getHRP(player)
                if root then
                    local relative = myRoot.CFrame:VectorToObjectSpace(root.Position - myRoot.Position)
                    local planar = Vector2.new(relative.X, relative.Z)
                    if planar.Magnitude <= State.RadarRange then
                        local blip = radarBlips[player]
                        if not blip then
                            blip = Drawing.new("Circle")
                            blip.Filled, blip.Radius = true, 3.5
                            radarBlips[player] = blip
                        end
                        local scaled = planar / State.RadarRange * (State.RadarSize - 6)
                        blip.Position = center + Vector2.new(scaled.X, scaled.Y)
                        blip.Color = isVisible(Camera.CFrame.Position, root.Position)
                            and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 190, 60)
                        blip.Visible = true
                        active[player] = true
                    end
                end
            end
        end
        for player, blip in pairs(radarBlips) do if not active[player] then blip.Visible = false end end
    end

    -- Update prediction dot each frame
    local function updateAimPrediction()
        if not State.AimPrediction then
            if predictionDot then predictionDot.Visible = false end
            if predictionCircle then predictionCircle.Visible = false end
            if predictionText then predictionText.Visible = false end
            return
        end

        createPredictionDot()

        local weaponConfig = getCurrentWeaponConfig()
        if not weaponConfig then
            predictionDot.Visible = false
            predictionCircle.Visible = false
            predictionText.Visible = false
            return
        end

        local target = getClosestEnemyToCrosshair(nil, false)
        if not target then
            predictionDot.Visible = false
            predictionCircle.Visible = false
            predictionText.Visible = false
            return
        end

        local char = getCharacter(target)
        if not char then
            predictionDot.Visible = false
            predictionCircle.Visible = false
            predictionText.Visible = false
            return
        end

        local targetPart = char:FindFirstChild(State.PredictTargetPart) or char:FindFirstChild("Head")
        if not targetPart then
            predictionDot.Visible = false
            predictionCircle.Visible = false
            predictionText.Visible = false
            return
        end

        local shooterPos = Camera.CFrame.Position
        local targetPos = targetPart.Position
        local targetVelocity = getTargetVelocity(target)

        local predictedPos, travelTime = getPredictedPosition(targetPos, targetVelocity, weaponConfig, shooterPos)
        local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)

        if onScreen then
            local pos2D = Vector2.new(screenPos.X, screenPos.Y)
            predictionDot.Position = pos2D
            predictionDot.Radius = State.PredictDotSize
            predictionDot.Visible = true

            predictionCircle.Position = pos2D
            predictionCircle.Radius = State.PredictDotSize + 4
            predictionCircle.Visible = true

            predictionText.Position = pos2D + Vector2.new(0, -(State.PredictDotSize + 16))
            predictionText.Text = string.format("%s | %.0fms", weaponConfig.Name, travelTime * 1000)
            predictionText.Visible = true

            -- Color based on spread
            local spread = weaponConfig.Spread
            if spread <= 0.5 then
                predictionDot.Color = Color3.fromRGB(0, 255, 100)
                predictionCircle.Color = Color3.fromRGB(0, 255, 100)
                predictionText.Color = Color3.fromRGB(0, 255, 100)
            elseif spread <= 2 then
                predictionDot.Color = Color3.fromRGB(255, 255, 0)
                predictionCircle.Color = Color3.fromRGB(255, 255, 0)
                predictionText.Color = Color3.fromRGB(255, 255, 100)
            else
                predictionDot.Color = Color3.fromRGB(255, 100, 0)
                predictionCircle.Color = Color3.fromRGB(255, 100, 0)
                predictionText.Color = Color3.fromRGB(255, 150, 50)
            end
        else
            predictionDot.Visible = false
            predictionCircle.Visible = false
            predictionText.Visible = false
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
        if radarBlips[p] then radarBlips[p]:Remove(); radarBlips[p] = nil end
    end)

    Connections.inputBegan = UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.UserInputType == Enum.UserInputType.MouseButton2 then rightMouseDown = true end
    end)
    Connections.inputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then rightMouseDown = false end
    end)

    Connections.render = RunService.RenderStepped:Connect(function()
        updateESP()
        updateAimPrediction()
        updateAutoAim()
        updateRadar()
        aimFovCircle.Position = Camera.ViewportSize * 0.5
        aimFovCircle.Radius = State.AimFOV
        aimFovCircle.Visible = State.AutoAim
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

    VisualsTab:CreateToggle({
        Name = "Wall Check (Red=Visible, Green=Hidden)",
        CurrentValue = true,
        Callback = function(v)
            State.ESPWallCheck = v
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

    -- Aim Prediction Tab
    local AimTab = Window:CreateTab("Aim Predict", "crosshair")

    AimTab:CreateSection("Aim Prediction")

    AimTab:CreateToggle({
        Name = "Enable Aim Prediction",
        CurrentValue = false,
        Callback = function(v)
            State.AimPrediction = v
            if not v then
                destroyPredictionDot()
            end
        end,
    })

    AimTab:CreateDropdown({
        Name = "Target Part",
        Options = {"Head", "HumanoidRootPart"},
        CurrentOption = {"Head"},
        MultipleOptions = false,
        Callback = function(v)
            State.PredictTargetPart = v[1] or v
        end,
    })

    AimTab:CreateSlider({
        Name = "Dot Size",
        Range = {3, 15},
        Increment = 1,
        CurrentValue = 6,
        Callback = function(v)
            State.PredictDotSize = v
        end,
    })

    AimTab:CreateSection("Info")
    AimTab:CreateLabel("Dot = where to aim (drop + lead)")
    AimTab:CreateLabel("Auto-detects weapon ballistics")
    AimTab:CreateLabel("Green=accurate | Yellow=medium | Orange=spread")
    AimTab:CreateLabel("Targets closest enemy to crosshair")

    AimTab:CreateSection("Smooth Auto Aim")
    AimTab:CreateToggle({Name="Enable Auto Aim",CurrentValue=false,Callback=function(v) State.AutoAim=v if not v then lockedTarget=nil end end})
    AimTab:CreateDropdown({Name="Activation",Options={"Right Mouse","Always"},CurrentOption={"Right Mouse"},MultipleOptions=false,Callback=function(v) State.AimActivation=type(v)=="table"and v[1]or v end})
    AimTab:CreateToggle({Name="Sticky Target",CurrentValue=true,Callback=function(v) State.StickyTarget=v end})
    AimTab:CreateToggle({Name="Aim Visible Check",CurrentValue=true,Callback=function(v) State.AimVisibleCheck=v end})
    AimTab:CreateSlider({Name="Aim FOV",Range={40,500},Increment=10,CurrentValue=180,Suffix=" px",Callback=function(v) State.AimFOV=v end})
    AimTab:CreateSlider({Name="Smoothness",Range={0.05,0.6},Increment=0.01,CurrentValue=0.18,Callback=function(v) State.AimSmoothness=v end})

    local TacticalTab = Window:CreateTab("Tactical", "radar")
    TacticalTab:CreateSection("Match Dashboard")
    local matchModeLabel = TacticalTab:CreateLabel("Mode: loading...")
    local matchTicketsLabel = TacticalTab:CreateLabel("Tickets: loading...")
    local matchDeathsLabel = TacticalTab:CreateLabel("Deaths: loading...")
    local spawnLabel = TacticalTab:CreateLabel("Spawn: loading...")
    TacticalTab:CreateSection("Radar")
    TacticalTab:CreateToggle({Name="Tactical Radar",CurrentValue=false,Callback=function(v) State.Radar=v end})
    TacticalTab:CreateSlider({Name="Radar Range",Range={100,2000},Increment=50,CurrentValue=700,Suffix=" studs",Callback=function(v) State.RadarRange=v end})
    TacticalTab:CreateSlider({Name="Radar Size",Range={80,240},Increment=10,CurrentValue=150,Suffix=" px",Callback=function(v) State.RadarSize=v end})

    local matchFolder = workspace:FindFirstChild("Match")
    local function updateMatchDashboard()
        if not matchFolder then return end
        local function value(name, fallback) local item=matchFolder:FindFirstChild(name) return item and item.Value or fallback end
        pcall(function()
            matchModeLabel:Set("Mode: " .. tostring(value("CurrentMode", "?")))
            matchTicketsLabel:Set(string.format("Tickets | PACT %s : NATO %s", tostring(value("PACT_Tickets", "?")), tostring(value("NATO_Tickets", "?"))))
            matchDeathsLabel:Set(string.format("Deaths | PACT %s : NATO %s", tostring(value("PACT_Deaths", "?")), tostring(value("NATO_Deaths", "?"))))
            spawnLabel:Set("Can Spawn: " .. tostring(value("CanSpawn", false)))
        end)
    end
    updateMatchDashboard()
    Connections.matchDashboard = RunService.Heartbeat:Connect(function()
        if math.floor(os.clock()*2) ~= math.floor((os.clock()-1/60)*2) then updateMatchDashboard() end
    end)

    -- Info Tab
    local InfoTab = Window:CreateTab("Info", "info")

    InfoTab:CreateSection("Cold War")
    InfoTab:CreateLabel("Team: " .. tostring(getMyTeam() and getMyTeam().Name or "Unknown"))
    InfoTab:CreateLabel("Player: " .. LP.DisplayName)
    InfoTab:CreateLabel("Class: " .. tostring(LP:GetAttribute("ClassType") or "Unknown"))

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    local destroyed = false
    local function destroy()
            if destroyed then return end
            destroyed = true
            for _, conn in pairs(Connections) do
                pcall(function() conn:Disconnect() end)
            end
            clearAllESP()
            destroyPredictionDot()
            pcall(function() aimFovCircle:Remove() end)
            pcall(function() radarCircle:Remove() end)
            pcall(function() radarOutline:Remove() end)
            for _, blip in pairs(radarBlips) do pcall(function() blip:Remove() end) end
            espFolder:Destroy()
            applyFullbright(false)
            applyNoFog(false)
            applyFOV(false)
            if getgenv().__RAVEN_COLD_WAR and getgenv().__RAVEN_COLD_WAR.State == State then
                getgenv().__RAVEN_COLD_WAR = nil
            end
    end
    getgenv().__RAVEN_COLD_WAR = {Version="v1.1",State=State,Destroy=destroy}
    if runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(destroy)
    end
end
