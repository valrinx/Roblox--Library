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
<<<<<<< HEAD
        -- Weapon
        ReducedRecoil = false,
        RecoilReduction = 60,
        NoGunKick = false,
        NoSway = false,
        NoCameraShake = false,
        WeaponStats = false,
        -- Awareness
        RadarEnabled = false,
        RadarSize = 150,
        RadarRange = 200,
        SoundESP = false,
        SoundESPRange = 50,
        ProximityWarning = false,
        ProximityRange = 30,
        Snaplines = false,
        -- Customization
        CustomCrosshair = false,
        CrosshairStyle = "Cross",
        CrosshairSize = 10,
        CrosshairColor = Color3.fromRGB(0, 255, 0),
        ESPColorVisible = Color3.fromRGB(255, 30, 30),
        ESPColorHidden = Color3.fromRGB(0, 255, 80),
        ThirdPersonFOV = false,
        ThirdPersonFOVValue = 90,
=======
>>>>>>> fc2643ec8a9e557b67369b8f0792c20911009566
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
    local function getClosestEnemyToCrosshair()
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
            if dist2D < closestDist then
                closestDist = dist2D
                closestPlayer = player
            end
        end
        return closestPlayer
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

        local target = getClosestEnemyToCrosshair()
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
<<<<<<< HEAD
    -- Weapon System (Recoil, Sway, Camera Shake)
    ---------------------------------------------------------------------------

    local originalRecoilConfigs = {}
    local currentWeaponName = nil

    local function applyReducedRecoil(enabled, reduction)
        local char = getCharacter(LP)
        if not char then return end
        local tool = nil
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then tool = child; break end
        end
        if not tool then return end

        local configModule = WCM:FindFirstChild(tool.Name)
        if not configModule then return end

        if not originalRecoilConfigs[tool.Name] then
            local ok, data = pcall(require, configModule)
            if ok and data[1] and data[1].Recoil then
                originalRecoilConfigs[tool.Name] = {}
                for k, v in pairs(data[1].Recoil) do
                    originalRecoilConfigs[tool.Name][k] = v
                end
            end
        end

        local ok, data = pcall(require, configModule)
        if not ok or not data[1] or not data[1].Recoil then return end

        local orig = originalRecoilConfigs[tool.Name]
        if not orig then return end

        if enabled then
            local factor = 1 - (reduction / 100)
            data[1].Recoil.CameraRecoilVertical = orig.CameraRecoilVertical * factor
            data[1].Recoil.CameraRecoilHorizontal = orig.CameraRecoilHorizontal * factor
        else
            data[1].Recoil.CameraRecoilVertical = orig.CameraRecoilVertical
            data[1].Recoil.CameraRecoilHorizontal = orig.CameraRecoilHorizontal
        end
    end

    local function applyNoGunKick(enabled)
        local char = getCharacter(LP)
        if not char then return end
        local tool = nil
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then tool = child; break end
        end
        if not tool then return end

        local configModule = WCM:FindFirstChild(tool.Name)
        if not configModule then return end

        if not originalRecoilConfigs[tool.Name] then
            local ok, data = pcall(require, configModule)
            if ok and data[1] and data[1].Recoil then
                originalRecoilConfigs[tool.Name] = {}
                for k, v in pairs(data[1].Recoil) do
                    originalRecoilConfigs[tool.Name][k] = v
                end
            end
        end

        local ok, data = pcall(require, configModule)
        if not ok or not data[1] or not data[1].Recoil then return end

        local orig = originalRecoilConfigs[tool.Name]
        if not orig then return end

        if enabled then
            data[1].Recoil.GunRecoilVertical = 0
            data[1].Recoil.GunRecoilHorizontal = 0
            data[1].Recoil.RecoilKick = 0
        else
            data[1].Recoil.GunRecoilVertical = orig.GunRecoilVertical
            data[1].Recoil.GunRecoilHorizontal = orig.GunRecoilHorizontal
            data[1].Recoil.RecoilKick = orig.RecoilKick
        end
    end

    -- No Sway: neutralize Spring-based weapon sway
    local originalSwayWeight = nil
    local function applyNoSway(enabled)
        local char = getCharacter(LP)
        if not char then return end
        local tool = nil
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") then tool = child; break end
        end
        if not tool then return end

        local configModule = WCM:FindFirstChild(tool.Name)
        if not configModule then return end
        local ok, data = pcall(require, configModule)
        if not ok or not data[1] then return end

        if enabled then
            if not originalSwayWeight then
                originalSwayWeight = data[1].Weight
            end
            data[1].Weight = 0
        else
            if originalSwayWeight then
                data[1].Weight = originalSwayWeight
            end
        end
    end

    -- No Camera Shake
    local cameraShakeDisabled = false
    local originalShakeFunc = nil
    local function applyNoCameraShake(enabled)
        local csModule = game.ReplicatedStorage.Client.Camera:FindFirstChild("CameraShakeModule")
        if not csModule then return end
        local ok, csMod = pcall(require, csModule)
        if not ok or type(csMod) ~= "table" then return end

        if enabled then
            if not originalShakeFunc and csMod.Shake then
                originalShakeFunc = csMod.Shake
            end
            csMod.Shake = function() end
            cameraShakeDisabled = true
        else
            if originalShakeFunc then
                csMod.Shake = originalShakeFunc
            end
            cameraShakeDisabled = false
        end
    end

    -- Weapon Stats Overlay (Drawing API)
    local weaponStatsText = nil
    local function createWeaponStats()
        if weaponStatsText then return end
        weaponStatsText = Drawing.new("Text")
        weaponStatsText.Size = 14
        weaponStatsText.Font = Drawing.Fonts.Monospace
        weaponStatsText.Color = Color3.fromRGB(200, 200, 200)
        weaponStatsText.Outline = true
        weaponStatsText.OutlineColor = Color3.new(0, 0, 0)
        weaponStatsText.Position = Vector2.new(10, Camera.ViewportSize.Y - 100)
        weaponStatsText.Visible = false
    end

    local function destroyWeaponStats()
        if weaponStatsText then weaponStatsText:Remove(); weaponStatsText = nil end
    end

    local function updateWeaponStats()
        if not State.WeaponStats then
            if weaponStatsText then weaponStatsText.Visible = false end
            return
        end
        createWeaponStats()
        local wCfg = getCurrentWeaponConfig()
        if wCfg then
            local dropAt100 = getBulletDrop(getBulletTravelTime(100, wCfg.MuzzleVelocity, wCfg.Drag))
            local dropAt200 = getBulletDrop(getBulletTravelTime(200, wCfg.MuzzleVelocity, wCfg.Drag))
            weaponStatsText.Text = string.format(
                "%s | DMG:? | Vel:%d | Spread:%.1f | Drop@100:%.1f | Drop@200:%.1f",
                wCfg.Name, math.floor(wCfg.MuzzleVelocity), wCfg.Spread, dropAt100, dropAt200
            )
            weaponStatsText.Position = Vector2.new(10, Camera.ViewportSize.Y - 60)
            weaponStatsText.Visible = true
        else
            weaponStatsText.Visible = false
        end
    end

    -- Track weapon changes to re-apply mods
    local function onWeaponChanged()
        local char = getCharacter(LP)
        if not char then return end
        local toolName = nil
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") and WCM:FindFirstChild(child.Name) then
                toolName = child.Name
                break
            end
        end
        if toolName and toolName ~= currentWeaponName then
            currentWeaponName = toolName
            if State.ReducedRecoil then applyReducedRecoil(true, State.RecoilReduction) end
            if State.NoGunKick then applyNoGunKick(true) end
            if State.NoSway then applyNoSway(true) end
        end
    end

    ---------------------------------------------------------------------------
    -- Awareness System (Radar, Sound ESP, Proximity, Snaplines)
    ---------------------------------------------------------------------------

    -- Radar/Minimap
    local radarBackground = nil
    local radarBorder = nil
    local radarDots = {}
    local radarPlayerDot = nil
    local radarText = nil

    local function createRadar()
        if radarBackground then return end
        local size = State.RadarSize
        local pos = Vector2.new(Camera.ViewportSize.X - size - 15, 15)

        radarBackground = Drawing.new("Circle")
        radarBackground.Position = pos + Vector2.new(size/2, size/2)
        radarBackground.Radius = size / 2
        radarBackground.Color = Color3.fromRGB(0, 0, 0)
        radarBackground.Filled = true
        radarBackground.Transparency = 0.7
        radarBackground.Visible = false

        radarBorder = Drawing.new("Circle")
        radarBorder.Position = pos + Vector2.new(size/2, size/2)
        radarBorder.Radius = size / 2
        radarBorder.Color = Color3.fromRGB(100, 100, 100)
        radarBorder.Filled = false
        radarBorder.Thickness = 2
        radarBorder.Transparency = 1
        radarBorder.Visible = false

        radarPlayerDot = Drawing.new("Circle")
        radarPlayerDot.Position = pos + Vector2.new(size/2, size/2)
        radarPlayerDot.Radius = 3
        radarPlayerDot.Color = Color3.fromRGB(0, 200, 255)
        radarPlayerDot.Filled = true
        radarPlayerDot.Transparency = 1
        radarPlayerDot.Visible = false

        radarText = Drawing.new("Text")
        radarText.Position = pos + Vector2.new(size/2, size + 5)
        radarText.Text = "RADAR"
        radarText.Size = 11
        radarText.Center = true
        radarText.Color = Color3.fromRGB(150, 150, 150)
        radarText.Outline = true
        radarText.OutlineColor = Color3.new(0, 0, 0)
        radarText.Visible = false
    end

    local function destroyRadar()
        if radarBackground then radarBackground:Remove(); radarBackground = nil end
        if radarBorder then radarBorder:Remove(); radarBorder = nil end
        if radarPlayerDot then radarPlayerDot:Remove(); radarPlayerDot = nil end
        if radarText then radarText:Remove(); radarText = nil end
        for _, dot in pairs(radarDots) do dot:Remove() end
        radarDots = {}
    end

    local function updateRadar()
        if not State.RadarEnabled then
            if radarBackground then radarBackground.Visible = false end
            if radarBorder then radarBorder.Visible = false end
            if radarPlayerDot then radarPlayerDot.Visible = false end
            if radarText then radarText.Visible = false end
            for _, dot in pairs(radarDots) do dot.Visible = false end
            return
        end

        createRadar()
        radarBackground.Visible = true
        radarBorder.Visible = true
        radarPlayerDot.Visible = true
        radarText.Visible = true

        local size = State.RadarSize
        local center = Vector2.new(Camera.ViewportSize.X - size/2 - 15, size/2 + 15)
        radarBackground.Position = center
        radarBorder.Position = center
        radarPlayerDot.Position = center

        local myHRP = getMyHRP()
        if not myHRP then return end
        local myPos = myHRP.Position
        local _, camRotY, _ = Camera.CFrame:ToEulerAnglesYXZ()

        local dotIndex = 0
        for _, player in ipairs(Players:GetPlayers()) do
            if not isEnemy(player) then continue end
            local hrp = getHRP(player)
            if not hrp then continue end

            local offset = hrp.Position - myPos
            local dist = offset.Magnitude
            if dist > State.RadarRange then continue end

            dotIndex += 1

            -- Rotate relative to camera
            local angle = math.atan2(offset.X, offset.Z) - camRotY
            local scale = (dist / State.RadarRange) * (size / 2 - 8)
            local dotPos = center + Vector2.new(math.sin(angle) * scale, -math.cos(angle) * scale)

            if not radarDots[dotIndex] then
                radarDots[dotIndex] = Drawing.new("Circle")
                radarDots[dotIndex].Radius = 3
                radarDots[dotIndex].Filled = true
                radarDots[dotIndex].Transparency = 1
            end
            radarDots[dotIndex].Position = dotPos
            radarDots[dotIndex].Color = Color3.fromRGB(255, 50, 50)
            radarDots[dotIndex].Visible = true
        end

        -- Hide unused dots
        for i = dotIndex + 1, #radarDots do
            if radarDots[i] then radarDots[i].Visible = false end
        end
    end

    -- Sound ESP
    local lastSoundESPTime = 0
    local function updateSoundESP()
        if not State.SoundESP then return end
        if tick() - lastSoundESPTime < 0.5 then return end -- throttle
        lastSoundESPTime = tick()

        local myHRP = getMyHRP()
        if not myHRP then return end

        for _, player in ipairs(Players:GetPlayers()) do
            if not isEnemy(player) then continue end
            local hrp = getHRP(player)
            if not hrp then continue end
            local dist = (myHRP.Position - hrp.Position).Magnitude
            if dist <= State.SoundESPRange then
                -- Play a subtle ping
                local sound = Instance.new("Sound")
                sound.SoundId = "rbxassetid://6042053626"
                sound.Volume = math.clamp(1 - (dist / State.SoundESPRange), 0.1, 0.8)
                sound.PlaybackSpeed = 1.5
                sound.Parent = game:GetService("SoundService")
                sound:Play()
                game:GetService("Debris"):AddItem(sound, 1)
                break -- only ping for closest
            end
        end
    end

    -- Proximity Warning
    local proximityArrow = nil
    local proximityText2 = nil
    local function createProximityWarning()
        if proximityArrow then return end
        proximityArrow = Drawing.new("Triangle")
        proximityArrow.Color = Color3.fromRGB(255, 50, 50)
        proximityArrow.Filled = true
        proximityArrow.Transparency = 1
        proximityArrow.Visible = false

        proximityText2 = Drawing.new("Text")
        proximityText2.Size = 16
        proximityText2.Center = true
        proximityText2.Color = Color3.fromRGB(255, 80, 80)
        proximityText2.Outline = true
        proximityText2.OutlineColor = Color3.new(0, 0, 0)
        proximityText2.Font = Drawing.Fonts.Monospace
        proximityText2.Visible = false
    end

    local function destroyProximityWarning()
        if proximityArrow then proximityArrow:Remove(); proximityArrow = nil end
        if proximityText2 then proximityText2:Remove(); proximityText2 = nil end
    end

    local function updateProximityWarning()
        if not State.ProximityWarning then
            if proximityArrow then proximityArrow.Visible = false end
            if proximityText2 then proximityText2.Visible = false end
            return
        end

        createProximityWarning()
        local myHRP = getMyHRP()
        if not myHRP then proximityArrow.Visible = false; proximityText2.Visible = false; return end

        local closestDist = math.huge
        local closestHRP = nil
        for _, player in ipairs(Players:GetPlayers()) do
            if not isEnemy(player) then continue end
            local hrp = getHRP(player)
            if not hrp then continue end
            local dist = (myHRP.Position - hrp.Position).Magnitude
            if dist < closestDist and dist <= State.ProximityRange then
                closestDist = dist
                closestHRP = hrp
            end
        end

        if closestHRP then
            local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
            local dir = (closestHRP.Position - myHRP.Position).Unit
            local _, camRotY, _ = Camera.CFrame:ToEulerAnglesYXZ()
            local angle = math.atan2(dir.X, dir.Z) - camRotY

            local arrowDist = 80
            local arrowPos = screenCenter + Vector2.new(math.sin(angle) * arrowDist, -math.cos(angle) * arrowDist)

            local sz = 12
            local perpX = math.cos(angle) * sz
            local perpY = math.sin(angle) * sz
            local tipX = math.sin(angle) * sz
            local tipY = -math.cos(angle) * sz

            proximityArrow.PointA = arrowPos + Vector2.new(tipX, tipY)
            proximityArrow.PointB = arrowPos + Vector2.new(-perpX/2, -perpY/2)
            proximityArrow.PointC = arrowPos + Vector2.new(perpX/2, perpY/2)
            proximityArrow.Visible = true

            proximityText2.Position = screenCenter + Vector2.new(0, -110)
            proximityText2.Text = string.format("⚠ ENEMY %dm", math.floor(closestDist))
            proximityText2.Visible = true
        else
            proximityArrow.Visible = false
            proximityText2.Visible = false
        end
    end

    -- Snaplines
    local snaplineDrawings = {}
    local function updateSnaplines()
        local idx = 0
        if not State.Snaplines then
            for _, line in pairs(snaplineDrawings) do line.Visible = false end
            return
        end

        local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)

        for _, player in ipairs(Players:GetPlayers()) do
            if not isEnemy(player) then continue end
            local hrp = getHRP(player)
            if not hrp then continue end

            local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
            if not onScreen then continue end

            idx += 1
            if not snaplineDrawings[idx] then
                snaplineDrawings[idx] = Drawing.new("Line")
                snaplineDrawings[idx].Thickness = 1
                snaplineDrawings[idx].Transparency = 0.7
            end
            snaplineDrawings[idx].From = screenCenter
            snaplineDrawings[idx].To = Vector2.new(screenPos.X, screenPos.Y)
            snaplineDrawings[idx].Color = State.ESPColorVisible
            snaplineDrawings[idx].Visible = true
        end

        for i = idx + 1, #snaplineDrawings do
            if snaplineDrawings[i] then snaplineDrawings[i].Visible = false end
        end
    end

    ---------------------------------------------------------------------------
    -- Customization (Crosshair, ESP Colors, Third Person FOV)
    ---------------------------------------------------------------------------

    local crosshairDrawings = {}
    local function createCrosshair()
        if #crosshairDrawings > 0 then return end
        for i = 1, 4 do
            crosshairDrawings[i] = Drawing.new("Line")
            crosshairDrawings[i].Thickness = 2
            crosshairDrawings[i].Color = State.CrosshairColor
            crosshairDrawings[i].Transparency = 1
            crosshairDrawings[i].Visible = false
        end
        -- Center dot
        crosshairDrawings[5] = Drawing.new("Circle")
        crosshairDrawings[5].Radius = 2
        crosshairDrawings[5].Filled = true
        crosshairDrawings[5].Color = State.CrosshairColor
        crosshairDrawings[5].Transparency = 1
        crosshairDrawings[5].Visible = false
    end

    local function destroyCrosshair()
        for _, d in pairs(crosshairDrawings) do d:Remove() end
        crosshairDrawings = {}
    end

    local function updateCrosshair()
        if not State.CustomCrosshair then
            for _, d in pairs(crosshairDrawings) do d.Visible = false end
            return
        end

        createCrosshair()
        local cx = Camera.ViewportSize.X / 2
        local cy = Camera.ViewportSize.Y / 2
        local sz = State.CrosshairSize
        local gap = 4
        local col = State.CrosshairColor

        for _, d in pairs(crosshairDrawings) do
            if d:IsA("Line") or d.From then d.Color = col end
            if d.Radius then d.Color = col end
        end

        if State.CrosshairStyle == "Cross" then
            crosshairDrawings[1].From = Vector2.new(cx - sz, cy)
            crosshairDrawings[1].To = Vector2.new(cx - gap, cy)
            crosshairDrawings[2].From = Vector2.new(cx + gap, cy)
            crosshairDrawings[2].To = Vector2.new(cx + sz, cy)
            crosshairDrawings[3].From = Vector2.new(cx, cy - sz)
            crosshairDrawings[3].To = Vector2.new(cx, cy - gap)
            crosshairDrawings[4].From = Vector2.new(cx, cy + gap)
            crosshairDrawings[4].To = Vector2.new(cx, cy + sz)
            for i = 1, 4 do crosshairDrawings[i].Visible = true end
            crosshairDrawings[5].Position = Vector2.new(cx, cy)
            crosshairDrawings[5].Visible = true
        elseif State.CrosshairStyle == "Dot" then
            for i = 1, 4 do crosshairDrawings[i].Visible = false end
            crosshairDrawings[5].Position = Vector2.new(cx, cy)
            crosshairDrawings[5].Radius = sz / 3
            crosshairDrawings[5].Visible = true
        elseif State.CrosshairStyle == "Circle" then
            for i = 1, 4 do crosshairDrawings[i].Visible = false end
            crosshairDrawings[5].Position = Vector2.new(cx, cy)
            crosshairDrawings[5].Radius = sz
            crosshairDrawings[5].Filled = false
            crosshairDrawings[5].Visible = true
        end
    end

    -- Update ESP colors from customization
    local function updateESPColors()
        COLOR_VISIBLE = State.ESPColorVisible
        COLOR_HIDDEN = State.ESPColorHidden
        COLOR_TEXT_VISIBLE = State.ESPColorVisible
        COLOR_TEXT_HIDDEN = State.ESPColorHidden
    end

    ---------------------------------------------------------------------------
=======
>>>>>>> fc2643ec8a9e557b67369b8f0792c20911009566
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
        updateAimPrediction()
<<<<<<< HEAD
        updateRadar()
        updateSoundESP()
        updateProximityWarning()
        updateSnaplines()
        updateCrosshair()
        updateWeaponStats()
        onWeaponChanged()
=======
>>>>>>> fc2643ec8a9e557b67369b8f0792c20911009566
        if State.FOVEnabled then
            Camera.FieldOfView = State.FOVValue
        end
        if State.ThirdPersonFOV and not State.FOVEnabled then
            -- Only apply third person FOV when not ADS
            local char = getCharacter(LP)
            if char then
                local tool = char:FindFirstChildOfClass("Tool")
                if not tool then
                    Camera.FieldOfView = State.ThirdPersonFOVValue
                end
            end
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

    -- Info Tab
    local InfoTab = Window:CreateTab("Info", "info")

    InfoTab:CreateSection("Cold War")
    InfoTab:CreateLabel("Team: " .. tostring(getMyTeam() and getMyTeam().Name or "Unknown"))
    InfoTab:CreateLabel("Player: " .. LP.DisplayName)
    InfoTab:CreateLabel("Class: " .. tostring(LP:GetAttribute("ClassType") or "Unknown"))

    -- Weapon Tab
    local WeaponTab = Window:CreateTab("Weapon", "gun")

    WeaponTab:CreateSection("Recoil Control")

    WeaponTab:CreateToggle({
        Name = "Reduced Recoil (Camera)",
        CurrentValue = false,
        Callback = function(v)
            State.ReducedRecoil = v
            applyReducedRecoil(v, State.RecoilReduction)
        end,
    })

    WeaponTab:CreateSlider({
        Name = "Recoil Reduction %",
        Range = {20, 80},
        Increment = 10,
        CurrentValue = 60,
        Callback = function(v)
            State.RecoilReduction = v
            if State.ReducedRecoil then
                applyReducedRecoil(true, v)
            end
        end,
    })

    WeaponTab:CreateToggle({
        Name = "No Gun Kick (Visual)",
        CurrentValue = false,
        Callback = function(v)
            State.NoGunKick = v
            applyNoGunKick(v)
        end,
    })

    WeaponTab:CreateToggle({
        Name = "No Sway",
        CurrentValue = false,
        Callback = function(v)
            State.NoSway = v
            applyNoSway(v)
        end,
    })

    WeaponTab:CreateToggle({
        Name = "No Camera Shake",
        CurrentValue = false,
        Callback = function(v)
            State.NoCameraShake = v
            applyNoCameraShake(v)
        end,
    })

    WeaponTab:CreateSection("Info")

    WeaponTab:CreateToggle({
        Name = "Weapon Stats Overlay",
        CurrentValue = false,
        Callback = function(v)
            State.WeaponStats = v
            if not v then destroyWeaponStats() end
        end,
    })

    -- Awareness Tab
    local AwareTab = Window:CreateTab("Awareness", "radar")

    AwareTab:CreateSection("Radar / Minimap")

    AwareTab:CreateToggle({
        Name = "Radar",
        CurrentValue = false,
        Callback = function(v)
            State.RadarEnabled = v
            if not v then destroyRadar() end
        end,
    })

    AwareTab:CreateSlider({
        Name = "Radar Range (studs)",
        Range = {50, 500},
        Increment = 25,
        CurrentValue = 200,
        Callback = function(v)
            State.RadarRange = v
        end,
    })

    AwareTab:CreateSlider({
        Name = "Radar Size (px)",
        Range = {80, 250},
        Increment = 10,
        CurrentValue = 150,
        Callback = function(v)
            State.RadarSize = v
            destroyRadar()
        end,
    })

    AwareTab:CreateSection("Alerts")

    AwareTab:CreateToggle({
        Name = "Sound ESP (Beep)",
        CurrentValue = false,
        Callback = function(v)
            State.SoundESP = v
        end,
    })

    AwareTab:CreateSlider({
        Name = "Sound ESP Range",
        Range = {20, 150},
        Increment = 10,
        CurrentValue = 50,
        Callback = function(v)
            State.SoundESPRange = v
        end,
    })

    AwareTab:CreateToggle({
        Name = "Proximity Warning",
        CurrentValue = false,
        Callback = function(v)
            State.ProximityWarning = v
            if not v then destroyProximityWarning() end
        end,
    })

    AwareTab:CreateSlider({
        Name = "Proximity Range",
        Range = {10, 100},
        Increment = 5,
        CurrentValue = 30,
        Callback = function(v)
            State.ProximityRange = v
        end,
    })

    AwareTab:CreateToggle({
        Name = "Snaplines",
        CurrentValue = false,
        Callback = function(v)
            State.Snaplines = v
        end,
    })

    -- Customization Tab
    local CustomTab = Window:CreateTab("Customize", "palette")

    CustomTab:CreateSection("Crosshair")

    CustomTab:CreateToggle({
        Name = "Custom Crosshair",
        CurrentValue = false,
        Callback = function(v)
            State.CustomCrosshair = v
            if not v then destroyCrosshair() end
        end,
    })

    CustomTab:CreateDropdown({
        Name = "Crosshair Style",
        Options = {"Cross", "Dot", "Circle"},
        CurrentOption = {"Cross"},
        MultipleOptions = false,
        Callback = function(v)
            State.CrosshairStyle = v[1] or v
        end,
    })

    CustomTab:CreateSlider({
        Name = "Crosshair Size",
        Range = {5, 30},
        Increment = 1,
        CurrentValue = 10,
        Callback = function(v)
            State.CrosshairSize = v
        end,
    })

    CustomTab:CreateSection("ESP Colors")

    CustomTab:CreateDropdown({
        Name = "Visible Color",
        Options = {"Red", "Green", "Blue", "Yellow", "Purple", "Cyan", "White"},
        CurrentOption = {"Red"},
        MultipleOptions = false,
        Callback = function(v)
            local colors = {
                Red = Color3.fromRGB(255, 30, 30),
                Green = Color3.fromRGB(0, 255, 80),
                Blue = Color3.fromRGB(30, 100, 255),
                Yellow = Color3.fromRGB(255, 255, 0),
                Purple = Color3.fromRGB(180, 50, 255),
                Cyan = Color3.fromRGB(0, 255, 255),
                White = Color3.fromRGB(255, 255, 255),
            }
            local pick = v[1] or v
            State.ESPColorVisible = colors[pick] or Color3.fromRGB(255, 30, 30)
            updateESPColors()
        end,
    })

    CustomTab:CreateDropdown({
        Name = "Hidden Color (Behind Wall)",
        Options = {"Green", "Red", "Blue", "Yellow", "Purple", "Cyan", "White"},
        CurrentOption = {"Green"},
        MultipleOptions = false,
        Callback = function(v)
            local colors = {
                Red = Color3.fromRGB(255, 30, 30),
                Green = Color3.fromRGB(0, 255, 80),
                Blue = Color3.fromRGB(30, 100, 255),
                Yellow = Color3.fromRGB(255, 255, 0),
                Purple = Color3.fromRGB(180, 50, 255),
                Cyan = Color3.fromRGB(0, 255, 255),
                White = Color3.fromRGB(255, 255, 255),
            }
            local pick = v[1] or v
            State.ESPColorHidden = colors[pick] or Color3.fromRGB(0, 255, 80)
            updateESPColors()
        end,
    })

    CustomTab:CreateSection("Camera")

    CustomTab:CreateToggle({
        Name = "Third Person FOV",
        CurrentValue = false,
        Callback = function(v)
            State.ThirdPersonFOV = v
            if not v then Camera.FieldOfView = OriginalFOV end
        end,
    })

    CustomTab:CreateSlider({
        Name = "3rd Person FOV Value",
        Range = {70, 120},
        Increment = 5,
        CurrentValue = 90,
        Callback = function(v)
            State.ThirdPersonFOVValue = v
        end,
    })

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    if runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            for _, conn in pairs(Connections) do
                pcall(function() conn:Disconnect() end)
            end
            clearAllESP()
            destroyPredictionDot()
<<<<<<< HEAD
            destroyRadar()
            destroyProximityWarning()
            destroyCrosshair()
            destroyWeaponStats()
            for _, line in pairs(snaplineDrawings) do pcall(function() line:Remove() end) end
=======
>>>>>>> fc2643ec8a9e557b67369b8f0792c20911009566
            espFolder:Destroy()
            applyFullbright(false)
            applyNoFog(false)
            applyFOV(false)
            applyNoCameraShake(false)
            -- Restore recoil configs
            for weapName, orig in pairs(originalRecoilConfigs) do
                local m = WCM:FindFirstChild(weapName)
                if m then
                    pcall(function()
                        local data = require(m)
                        if data[1] and data[1].Recoil then
                            for k, v in pairs(orig) do
                                data[1].Recoil[k] = v
                            end
                        end
                    end)
                end
            end
            if originalSwayWeight then
                pcall(function()
                    local char = getCharacter(LP)
                    if char then
                        for _, child in ipairs(char:GetChildren()) do
                            if child:IsA("Tool") then
                                local m = WCM:FindFirstChild(child.Name)
                                if m then
                                    local data = require(m)
                                    if data[1] then data[1].Weight = originalSwayWeight end
                                end
                            end
                        end
                    end
                end)
            end
        end)
    end
end
