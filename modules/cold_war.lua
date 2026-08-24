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
    - v1.6.0 configurable auto-lock restricted to shootable body parts

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
        AdaptiveSmoothness = true,
        AimSwayCompensation = true,
        AimVisibleCheck = true,
        AimPartMode = "Auto Visible",
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
    local predictionFrame = 0
    local predictionCache = {}

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

    local VISIBILITY_PARTS = {
        "Head", "Torso", "UpperTorso", "LowerTorso",
        "Left Arm", "Right Arm", "Left Leg", "Right Leg",
        "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg",
    }
    local visibilityCache = {}
    local visibilityFrame = 0
    local rayFilterFrame = -1

    local COLOR_VISIBLE = Color3.fromRGB(255, 30, 30)
    local COLOR_HIDDEN  = Color3.fromRGB(0, 255, 80)
    local COLOR_TEXT_VISIBLE = Color3.fromRGB(255, 60, 60)
    local COLOR_TEXT_HIDDEN  = Color3.fromRGB(0, 255, 100)

    local function buildRayFilter()
        if rayFilterFrame == visibilityFrame then return end
        local ignore = {}
        local myChar = getCharacter(LP)
        if myChar then table.insert(ignore, myChar) end
        for _, name in ipairs({"Ignore", "Effects", "Debris"}) do
            local folder = workspace:FindFirstChild(name)
            if folder then table.insert(ignore, folder) end
        end
        RayParams.FilterDescendantsInstances = ignore
        rayFilterFrame = visibilityFrame
    end

    local function rayReachesTarget(fromPos, toPos, targetCharacter)
        local direction = toPos - fromPos
        local result = workspace:Raycast(fromPos, direction, RayParams)
        if not result then return true end
        return targetCharacter ~= nil and result.Instance:IsDescendantOf(targetCharacter)
    end

    local function isPointVisible(fromPos, toPos, targetCharacter)
        buildRayFilter()
        return rayReachesTarget(fromPos, toPos, targetCharacter)
    end

    local function isCharacterVisible(fromPos, targetCharacter)
        if not targetCharacter then return false end

        local cached = visibilityCache[targetCharacter]
        if cached and cached.frame == visibilityFrame then
            return cached.visible, cached.parts
        end

        local parts = {}
        for _, partName in ipairs(VISIBILITY_PARTS) do
            local part = targetCharacter:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                table.insert(parts, part)
            end
        end

        if #parts == 0 then return false, {} end

        cached = cached or {partIndex = 1, parts = {}}
        cached.parts = cached.parts or {}
        local partIndex = math.clamp(cached.partIndex or 1, 1, #parts)
        local part = parts[partIndex]
        local partState = cached.parts[part] or {sampleIndex = 1, visible = false, cycleVisible = false}
        local halfX = part.Size.X * 0.42
        local halfY = part.Size.Y * 0.42
        local offsets = {
            Vector3.zero,
            Vector3.new(halfX, 0, 0),
            Vector3.new(-halfX, 0, 0),
            Vector3.new(0, halfY, 0),
            Vector3.new(0, -halfY, 0),
        }
        local sampleIndex = math.clamp(partState.sampleIndex or 1, 1, #offsets)
        buildRayFilter()
        local sampleVisible = rayReachesTarget(
            fromPos, part.CFrame:PointToWorldSpace(offsets[sampleIndex]), targetCharacter
        )
        partState.cycleVisible = partState.cycleVisible or sampleVisible
        if sampleVisible then partState.visible = true end
        sampleIndex += 1
        if sampleIndex > #offsets then
            partState.visible = partState.cycleVisible
            partState.cycleVisible = false
            sampleIndex = 1
            partIndex = partIndex % #parts + 1
        end
        partState.sampleIndex = sampleIndex
        cached.parts[part] = partState
        cached.partIndex = partIndex
        local anyVisible = false
        for _, state in pairs(cached.parts) do
            if state.visible then anyVisible = true break end
        end
        cached.visible = anyVisible
        cached.frame = visibilityFrame
        visibilityCache[targetCharacter] = cached
        return cached.visible, cached.parts
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
            partBoxes = {},
        }
    end

    local function hidePartBoxes(esp)
        for _, box in pairs(esp.partBoxes or {}) do box.Visible = false end
    end

    local function updatePartBoxes(esp, character, partStates)
        local active = {}
        for part, state in pairs(partStates or {}) do
            if part.Parent and part:IsDescendantOf(character) then
                local box = esp.partBoxes[part]
                if not box then
                    box = Instance.new("BoxHandleAdornment")
                    box.Name = "PartVisibility"
                    box.AlwaysOnTop = true
                    box.ZIndex = 5
                    box.Transparency = 0.72
                    box.Adornee = part
                    box.Parent = espFolder
                    esp.partBoxes[part] = box
                end
                box.Size = part.Size + Vector3.new(0.04, 0.04, 0.04)
                box.Color3 = state.visible and COLOR_VISIBLE or COLOR_HIDDEN
                box.Visible = true
                active[part] = true
            end
        end
        for part, box in pairs(esp.partBoxes) do
            if not active[part] then
                box.Visible = false
                if not part.Parent then
                    box:Destroy()
                    esp.partBoxes[part] = nil
                end
            end
        end
    end

    local function removeESP(player)
        local obj = ESPObjects[player]
        if obj then
            for _, box in pairs(obj.partBoxes or {}) do box:Destroy() end
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
                hidePartBoxes(esp)
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
                hidePartBoxes(esp)
                continue
            end

            local hrp = getHRP(player)
            if hrp then
                local dist = myHRP and (myHRP.Position - hrp.Position).Magnitude or 0

                if dist <= State.MaxDistance then
                    local char = getCharacter(player)
                    esp.highlight.Adornee = nil
                    esp.highlight.Enabled = false
                    esp.billboard.Adornee = hrp
                    esp.billboard.Enabled = true

                    if State.ESPWallCheck and myHRP then
                        local camPos = Camera.CFrame.Position
                        local visible, partStates = isCharacterVisible(camPos, char)
                        updatePartBoxes(esp, char, partStates)
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
                        hidePartBoxes(esp)
                        esp.highlight.Adornee = char
                        esp.highlight.Enabled = true
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
                    hidePartBoxes(esp)
                end
            else
                esp.highlight.Enabled = false
                esp.billboard.Enabled = false
                hidePartBoxes(esp)
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
    local Trajectory = require(game.ReplicatedStorage.Shared.Ballistics.Trajectory)
    local STUDS_PER_METER = 3.57 -- Cold War's ZeroSolver constant

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
            ZeroMeters = (cfg.Zeroing and cfg.Zeroing.Aimpoint1 and cfg.Zeroing.Aimpoint1.Default) or 0,
            Recoil = cfg.Recoil or {},
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

    -- Use the game's own trajectory implementation. In Cold War, BulletSettings.Drag
    -- is passed to Trajectory as K; applying another scale makes long-range zeroing drift.
    local function getBulletTravelTime(distance, muzzleVelocity, drag)
        local ok, result = pcall(function()
            local trajectory = Trajectory.new({
                Origin = Vector3.zero,
                Direction = Vector3.new(0, 0, -1),
                MuzzleSpeed = muzzleVelocity,
                K = drag,
                Gravity = GRAVITY,
            })
            return Trajectory.GetTimeForDistance(trajectory, math.max(distance, 0))
        end)
        return ok and type(result) == "number" and result or (distance / math.max(muzzleVelocity, 1))
    end

    -- Calculate bullet drop at given time
    local function getBulletDrop(time)
        return 0.5 * GRAVITY * time * time
    end

    -- Get target velocity (movement prediction)
    local lastPositions = {}
    local lastPositionTimes = {}
    local smoothedVelocities = {}

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
                local measured = (currentPos - lastPos) / dt
                local assembly = hrp.AssemblyLinearVelocity
                if assembly.Magnitude < 250 then measured = measured:Lerp(assembly, 0.45) end
                local previous = smoothedVelocities[player] or measured
                local alpha = 1 - math.exp(-dt * 12)
                local smoothed = previous:Lerp(measured, alpha)
                smoothedVelocities[player] = smoothed
                return smoothed
            end
        end
        return Vector3.zero
    end

    -- Calculate predicted aim point
    local function getPredictedPosition(targetPos, targetVelocity, weaponConfig, shooterPos)
        if not weaponConfig then return targetPos, 0 end

        local travelTime = 0
        local leadOffset = Vector3.zero
        -- Re-solve distance after lead. Two extra iterations converge for normal
        -- infantry speeds without adding a per-frame simulation loop.
        for _ = 1, 3 do
            leadOffset = targetVelocity * travelTime
            local futureDirection = targetPos + leadOffset - shooterPos
            local forwardDistance = Vector3.new(futureDirection.X, 0, futureDirection.Z).Magnitude
            travelTime = getBulletTravelTime(forwardDistance, weaponConfig.MuzzleVelocity, weaponConfig.Drag)
        end
        leadOffset = targetVelocity * travelTime
        local zeroDistance = (weaponConfig.ZeroMeters or 0) * STUDS_PER_METER
        local zeroTime = zeroDistance > 0
            and getBulletTravelTime(zeroDistance, weaponConfig.MuzzleVelocity, weaponConfig.Drag) or 0
        local drop = getBulletDrop(travelTime) - getBulletDrop(zeroTime)

        local predicted = targetPos + leadOffset + Vector3.new(0, drop, 0)
        return predicted, travelTime
    end

    -- Prediction Dot and Auto Aim must consume the exact same ballistic sample.
    -- Sampling target velocity twice in one frame produces a near-zero second delta
    -- and makes the displayed point disagree with the position Auto Aim follows.
    local function getSharedPrediction(player, weaponConfig, selectedPart)
        if not player or not weaponConfig then return nil end
        local char = getCharacter(player)
        local targetPart = selectedPart
            or (char and (char:FindFirstChild(State.PredictTargetPart) or char:FindFirstChild("Head")))
        if not targetPart then return nil end
        local cached = predictionCache[player]
        if cached and cached.frame == predictionFrame and cached.part == targetPart
            and cached.weapon == weaponConfig.Name then
            return cached
        end
        local velocity = getTargetVelocity(player)
        local predicted, travelTime = getPredictedPosition(
            targetPart.Position, velocity, weaponConfig, Camera.CFrame.Position
        )
        cached = {
            frame = predictionFrame,
            player = player,
            part = targetPart,
            weapon = weaponConfig.Name,
            velocity = velocity,
            position = predicted,
            travelTime = travelTime,
        }
        predictionCache[player] = cached
        return cached
    end

    -- Prediction dot (Drawing API)
    local predictionDot = nil
    local predictionCircle = nil
    local predictionText = nil
    local predictionDisplayPosition = nil
    local predictionDisplayTarget = nil

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
        predictionDisplayPosition = nil
        predictionDisplayTarget = nil
    end

    local resolveAimPart

    -- Find closest enemy to crosshair
    local function getClosestEnemyToCrosshair(maxPixels, requireVisible)
        local closestPlayer = nil
        local closestDist = math.huge
        local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

        for _, player in ipairs(Players:GetPlayers()) do
            if not isEnemy(player) then continue end
            local targetPart = resolveAimPart(player, requireVisible)
            if not targetPart then continue end

            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            if not onScreen then continue end

            local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
            if (not maxPixels or dist2D <= maxPixels) and dist2D < closestDist then
                closestDist = dist2D
                closestPlayer = player
            end
        end
        return closestPlayer
    end

    local function aimActive()
        if not State.AutoAim then return false end
        if State.AimActivation == "Always" then return true end
        local ok, held = pcall(function()
            return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end)
        -- Both sources must agree. This prevents a stale event or a UI callback
        -- with an unexpected value from engaging aim on its own.
        return rightMouseDown and ok and held == true
    end

    local function getAimResponse(screenError)
        local response = math.max(1, State.AimSmoothness * 60)
        if State.AdaptiveSmoothness then
            local normalizedError = math.clamp((screenError or 0) / math.max(State.AimFOV, 1), 0, 1)
            response *= 1 + normalizedError * 2.5
        end
        return response
    end

    resolveAimPart = function(player, requireVisible)
        local character = getCharacter(player)
        if not character then return nil end
        local preferred = character:FindFirstChild(State.PredictTargetPart) or character:FindFirstChild("Head")
        if not requireVisible then return preferred end

        local _, states = isCharacterVisible(Camera.CFrame.Position, character)
        local function visible(part)
            local state = part and states and states[part]
            return part and part:IsA("BasePart") and state and state.visible
        end
        if State.AimPartMode == "Selected Only" then
            return visible(preferred) and preferred or nil
        end

        local candidates = {
            preferred,
            character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"),
            character:FindFirstChild("LowerTorso"),
            character:FindFirstChild("Head"),
            character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftUpperArm"),
            character:FindFirstChild("Right Arm") or character:FindFirstChild("RightUpperArm"),
            character:FindFirstChild("Left Leg") or character:FindFirstChild("LeftUpperLeg"),
            character:FindFirstChild("Right Leg") or character:FindFirstChild("RightUpperLeg"),
        }
        local best, bestDistance = nil, math.huge
        local center = Camera.ViewportSize * 0.5
        local seen = {}
        for _, part in ipairs(candidates) do
            if visible(part) and not seen[part] then
                seen[part] = true
                if State.AimPartMode == "Auto Visible" then return part end
                local point, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and point.Z > 0 then
                    local distance = (Vector2.new(point.X, point.Y) - center).Magnitude
                    if distance < bestDistance then best, bestDistance = part, distance end
                end
            end
        end
        return best
    end

    local function validAimTarget(player)
        if not player or not isEnemy(player) then return false end
        local part = resolveAimPart(player, State.AimVisibleCheck)
        if not part then return false end
        local point, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 then return false end
        local center = Camera.ViewportSize * 0.5
        if (Vector2.new(point.X, point.Y) - center).Magnitude > State.AimFOV then return false end
        return true
    end

    local function updateAutoAim(dt)
        local inputActive = aimActive()
        State.AimInputActive = inputActive
        State.AimEngaged = false
        State.AimLockedPart = nil
        if not inputActive then lockedTarget = nil return end
        if not State.StickyTarget or not validAimTarget(lockedTarget) then
            lockedTarget = getClosestEnemyToCrosshair(State.AimFOV, State.AimVisibleCheck)
        end
        if not lockedTarget then return end
        local part = resolveAimPart(lockedTarget, State.AimVisibleCheck)
        if not part then return end
        State.AimLockedPart = part.Name
        local cfg = getCurrentWeaponConfig()
        local sample = getSharedPrediction(lockedTarget, cfg, part)
        if not sample then return end
        local point, onScreen = Camera:WorldToViewportPoint(sample.position)
        if not onScreen then return end
        State.AimEngaged = true
        if State.AimSwayCompensation then
            local desired = CFrame.lookAt(Camera.CFrame.Position, sample.position, Camera.CFrame.UpVector)
            local center = Camera.ViewportSize * 0.5
            local response = getAimResponse((Vector2.new(point.X, point.Y) - center).Magnitude)
            local alpha = 1 - math.exp(-response * math.max(dt or 1 / 60, 1 / 240))
            Camera.CFrame = Camera.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))
        else
            local center = Camera.ViewportSize * 0.5
            local delta = Vector2.new(point.X, point.Y) - center
            if type(mousemoverel) == "function" then
                pcall(mousemoverel, delta.X * State.AimSmoothness, delta.Y * State.AimSmoothness)
            else
                Camera.CFrame = Camera.CFrame:Lerp(CFrame.lookAt(Camera.CFrame.Position, sample.position), State.AimSmoothness)
            end
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
                        blip.Color = isCharacterVisible(Camera.CFrame.Position, getCharacter(player))
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
    local function updateAimPrediction(dt)
        if not State.AimPrediction then
            if predictionDot then predictionDot.Visible = false end
            if predictionCircle then predictionCircle.Visible = false end
            if predictionText then predictionText.Visible = false end
            predictionDisplayPosition = nil
            predictionDisplayTarget = nil
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

        local requireShootable = State.AutoAim and aimActive() and State.AimVisibleCheck
        local target = lockedTarget
        if not target or (requireShootable and not validAimTarget(target)) then
            target = getClosestEnemyToCrosshair(nil, requireShootable)
        end
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

        local targetPart = resolveAimPart(target, requireShootable)
        if not targetPart then
            predictionDot.Visible = false
            predictionCircle.Visible = false
            predictionText.Visible = false
            return
        end

        local shooterPos = Camera.CFrame.Position
        local targetPos = targetPart.Position
        local sample = getSharedPrediction(target, weaponConfig, targetPart)
        if not sample then return end
        local predictedPos, travelTime = sample.position, sample.travelTime
        local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)

        if onScreen then
            local rawPos2D = Vector2.new(screenPos.X, screenPos.Y)
            local pos2D = rawPos2D
            if State.AutoAim and aimActive() then
                if predictionDisplayTarget ~= target or predictionDisplayPosition == nil then
                    predictionDisplayPosition = Camera.ViewportSize * 0.5
                end
                local center = Camera.ViewportSize * 0.5
                local response = getAimResponse((rawPos2D - center).Magnitude)
                local alpha = 1 - math.exp(-response * math.max(dt or 1 / 60, 1 / 240))
                predictionDisplayPosition = predictionDisplayPosition:Lerp(rawPos2D, math.clamp(alpha, 0, 1))
                predictionDisplayTarget = target
                pos2D = predictionDisplayPosition
            else
                predictionDisplayPosition = nil
                predictionDisplayTarget = nil
            end
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
        local character = getCharacter(p)
        if character then visibilityCache[character] = nil end
        removeESP(p)
        if radarBlips[p] then radarBlips[p]:Remove(); radarBlips[p] = nil end
    end)

    Connections.inputBegan = UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2
            and UserInputService:GetFocusedTextBox() == nil then
            rightMouseDown = true
        end
    end)
    Connections.inputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then rightMouseDown = false end
    end)

    local aimRenderStepName = "RavenColdWarAim_" .. tostring(LP.UserId)
    RunService:BindToRenderStep(aimRenderStepName, Enum.RenderPriority.Camera.Value + 10, function(dt)
        visibilityFrame += 1
        predictionFrame += 1
        updateESP()
        updateAimPrediction(dt)
        updateAutoAim(dt)
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
        Name = "Part Visible Check (Red=Visible, Green=Hidden)",
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
    AimTab:CreateToggle({Name="Enable Auto Aim",CurrentValue=false,Flag="ColdWarAutoAim",Callback=function(v) State.AutoAim=v == true if not State.AutoAim then lockedTarget=nil end end})
    AimTab:CreateDropdown({Name="Activation",Options={"Right Mouse","Always"},CurrentOption={"Right Mouse"},MultipleOptions=false,Flag="ColdWarAimActivationV2",Callback=function(v)
        local selected = v
        if type(v) == "table" then
            selected = v[1]
            if selected == nil then
                for key, value in pairs(v) do
                    selected = value == true and key or value
                    break
                end
            end
        end
        selected = tostring(selected or "Right Mouse")
        State.AimActivation = selected:lower() == "always" and "Always" or "Right Mouse"
    end})
    AimTab:CreateToggle({Name="Sticky Target",CurrentValue=true,Callback=function(v) State.StickyTarget=v end})
    AimTab:CreateToggle({Name="Aim Visible Check",CurrentValue=true,Callback=function(v) State.AimVisibleCheck=v end})
    AimTab:CreateDropdown({Name="Auto Lock Part",Options={"Auto Visible","Closest Visible","Selected Only"},CurrentOption={"Auto Visible"},MultipleOptions=false,Flag="ColdWarAimPartMode",Callback=function(v)
        local selected = v
        if type(v) == "table" then
            selected = v[1]
            if selected == nil then
                for key, value in pairs(v) do
                    selected = value == true and key or value
                    break
                end
            end
        end
        selected = tostring(selected or "Auto Visible")
        if selected ~= "Closest Visible" and selected ~= "Selected Only" then selected = "Auto Visible" end
        State.AimPartMode = selected
        lockedTarget = nil
    end})
    AimTab:CreateToggle({Name="Recoil / Sway Compensation",CurrentValue=true,Callback=function(v) State.AimSwayCompensation=v end})
    AimTab:CreateToggle({Name="Adaptive Smoothness",CurrentValue=true,Flag="ColdWarAdaptiveSmoothness",Callback=function(v) State.AdaptiveSmoothness=v == true end})
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
            pcall(function() RunService:UnbindFromRenderStep(aimRenderStepName) end)
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
    getgenv().__RAVEN_COLD_WAR = {Version="v1.6.0",State=State,Destroy=destroy}
    if runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(destroy)
    end
end
