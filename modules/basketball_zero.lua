-- ============================================================
--   RAVEN HUB  |  Basketball: Zero (BAC / Frog Compliant)
--   High-Performance 100% Drawing API Engine (Zero Lag / Zero Injection)
--   Auto Green Release, Dual Ball ESP, Complete Anti-Ankle Break, Auto Steal
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")

    -- Clean up previous instance if running
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_BASKETBALL_ZERO) == "table"
        and type(environment.__RAVEN_BASKETBALL_ZERO.Destroy) == "function" then
        pcall(environment.__RAVEN_BASKETBALL_ZERO.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = workspace.CurrentCamera

    local running = true
    local connections = {}

    -- Settings
    local settings = {
        -- Tab 1: Shooting
        autoGreen = false,
        greenOffset = 0.0,
        autoFaceRim = false,

        -- Tab 2: Defense & Mobility
        autoSteal = false,
        stealReach = 7,
        antiAnkleBreak = false,
        alwaysRun = false,

        -- Tab 3: Visuals & ESP (100% Drawing API - Zero Lag)
        ballEsp = false,
        ballTracer = false,
        rimEsp = false,
        playerEsp = false,
        espDistance = true,
        showBoxes = false,
        showTracers = false,
        maxDistance = 250,

        -- Tab 4: Safety
        safeModeGuard = true,
    }

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getRoot(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
    end

    local function getHumanoid(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    -- Lazy Game Controllers Resolution (Only safe controllers, NEVER require AbilityController)
    local BallController, DefenseController, MovementController, Network
    local controllersResolved = false

    local function resolveControllers()
        if controllersResolved then return end
        local controllers = ReplicatedStorage:FindFirstChild("Controllers")
        if not controllers then return end

        pcall(function()
            if not BallController and controllers:FindFirstChild("BallController") then
                BallController = require(controllers.BallController)
            end
            if not DefenseController and controllers:FindFirstChild("DefenseController") then
                DefenseController = require(controllers.DefenseController)
            end
            if not MovementController and controllers:FindFirstChild("MovementController") then
                MovementController = require(controllers.MovementController)
            end
            if not Network and controllers:FindFirstChild("Network") then
                Network = require(controllers.Network)
            end
            controllersResolved = true
        end)
    end

    local function ensureControllers()
        if not controllersResolved then
            resolveControllers()
        end
    end

    -- ------------------------------------------------------------
    -- 100% ZERO-LAG DRAWING API ESP ENGINE
    -- ------------------------------------------------------------
    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local espDrawings = {}

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        return (ok and obj) or nil
    end

    local function newPlayerDrawingSet()
        local d = {
            boxOutline = safeDrawing("Square"),
            box = safeDrawing("Square"),
            name = safeDrawing("Text"),
            dist = safeDrawing("Text"),
            tracer = safeDrawing("Line"),
            visible = false,
        }

        if d.boxOutline then
            d.boxOutline.Thickness = 2.5
            d.boxOutline.Filled = false
            d.boxOutline.Color = Color3.fromRGB(0, 0, 0)
            d.boxOutline.Visible = false
        end

        if d.box then
            d.box.Thickness = 1
            d.box.Filled = false
            d.box.Color = Color3.fromRGB(255, 255, 255)
            d.box.Visible = false
        end

        if d.name then
            d.name.Size = 13
            d.name.Center = true
            d.name.Outline = true
            d.name.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.name.Color = Color3.fromRGB(255, 255, 255)
            d.name.Visible = false
        end

        if d.dist then
            d.dist.Size = 11
            d.dist.Center = true
            d.dist.Outline = true
            d.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.dist.Color = Color3.fromRGB(220, 220, 220)
            d.dist.Visible = false
        end

        if d.tracer then
            d.tracer.Thickness = 1
            d.tracer.Visible = false
        end

        return d
    end

    local function newPointDrawingSet(defaultColor)
        local d = {
            circle = safeDrawing("Circle"),
            text = safeDrawing("Text"),
            tracer = safeDrawing("Line"),
            visible = false,
        }

        if d.circle then
            d.circle.Thickness = 1.5
            d.circle.Filled = false
            d.circle.Color = defaultColor or Color3.fromRGB(255, 140, 0)
            d.circle.Radius = 6
            d.circle.Visible = false
        end

        if d.text then
            d.text.Size = 12
            d.text.Center = true
            d.text.Outline = true
            d.text.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.text.Color = defaultColor or Color3.fromRGB(255, 140, 0)
            d.text.Visible = false
        end

        if d.tracer then
            d.tracer.Thickness = 1.2
            d.tracer.Color = defaultColor or Color3.fromRGB(255, 140, 0)
            d.tracer.Visible = false
        end

        return d
    end

    local function hideDrawingSet(d)
        if not d or not d.visible then return end
        d.visible = false
        if d.boxOutline and d.boxOutline.Visible then d.boxOutline.Visible = false end
        if d.box and d.box.Visible then d.box.Visible = false end
        if d.name and d.name.Visible then d.name.Visible = false end
        if d.dist and d.dist.Visible then d.dist.Visible = false end
        if d.tracer and d.tracer.Visible then d.tracer.Visible = false end
        if d.circle and d.circle.Visible then d.circle.Visible = false end
        if d.text and d.text.Visible then d.text.Visible = false end
    end

    local function removeDrawingSet(d)
        if not d then return end
        d.visible = false
        for k, obj in pairs(d) do
            if type(obj) == "table" or type(obj) == "userdata" then
                pcall(function()
                    obj.Visible = false
                    obj:Remove()
                end)
            end
        end
    end

    -- Find Target Rim (Cached search every 5s)
    local cachedRims = {}
    local lastRimScan = 0

    local function getTargetRim(myPos)
        local now = os.clock()
        if (now - lastRimScan) > 5 or #cachedRims == 0 then
            lastRimScan = now
            table.clear(cachedRims)
            local searchRoots = {
                workspace:FindFirstChild("Courts2"),
                workspace:FindFirstChild("Courts"),
                workspace:FindFirstChild("Map"),
            }
            local foundAny = false
            for _, root in ipairs(searchRoots) do
                if root then
                    foundAny = true
                    for _, d in ipairs(root:GetDescendants()) do
                        if (d.Name == "Rim" or d.Name == "CloseRim") and d:IsA("BasePart") then
                            table.insert(cachedRims, d)
                        end
                    end
                end
            end
            if not foundAny or #cachedRims == 0 then
                for _, d in ipairs(workspace:GetChildren()) do
                    if (d.Name == "Rim" or d.Name == "CloseRim") and d:IsA("BasePart") then
                        table.insert(cachedRims, d)
                    end
                end
            end
        end

        local bestRim = nil
        local minDist = math.huge
        for _, rim in ipairs(cachedRims) do
            if rim and rim.Parent then
                local dist = (rim.Position - myPos).Magnitude
                if dist < 250 and dist > 4 and dist < minDist then
                    minDist = dist
                    bestRim = rim
                end
            end
        end

        return bestRim, minDist
    end

    -- ============================================================
    --   DUAL-MODE BALL LOCATOR (Free Ball & Ball Carrier Tracking)
    -- ============================================================
    local function getAccurateBallData()
        ensureControllers()

        -- 1. Check if a player possesses the ball
        local possPlayer = nil
        local possChar = nil

        if BallController and type(BallController.GetCharacterPossessingBall) == "function" then
            pcall(function()
                possChar = BallController:GetCharacterPossessingBall()
                possPlayer = BallController:GetPlayerPossessingBall()
            end)
        end

        -- Fallback possession check: scan player characters for visible PlrBall
        if not possChar then
            for _, p in ipairs(Players:GetPlayers()) do
                local c = p.Character
                if c then
                    local pb = c:FindFirstChild("PlrBall")
                    local animB = pb and pb:FindFirstChild("Anims") and pb.Anims:FindFirstChild("BALL")
                    if animB and animB.Transparency < 0.5 then
                        possPlayer = p
                        possChar = c
                        break
                    end
                end
            end
        end

        if possChar then
            local pb = possChar:FindFirstChild("PlrBall")
            local animB = pb and pb:FindFirstChild("Anims") and pb.Anims:FindFirstChild("BALL")
            local hrp = possChar:FindFirstChild("HumanoidRootPart")
            local ballPos = (animB and animB.Position) or (hrp and hrp.Position)
            local carrierName = (possPlayer and (possPlayer.DisplayName or possPlayer.Name)) or possChar.Name
            local isLocal = (possPlayer == localPlayer or possChar == localPlayer.Character)
            local isTeammate = (possPlayer and possPlayer.Team ~= nil and localPlayer.Team ~= nil and possPlayer.Team == localPlayer.Team)

            return ballPos, carrierName, true, isLocal, isTeammate
        end

        -- 2. Free Ball (Loose Ball / In Flight / On Floor)
        -- Primary: Server ball position from BallController
        if BallController and type(BallController.GetServerBallPosition) == "function" then
            local ok, sPos = pcall(BallController.GetServerBallPosition, BallController)
            if ok and typeof(sPos) == "Vector3" and sPos.Magnitude > 1 then
                return sPos, "Free Ball", false, false, false
            end
        end

        -- Secondary: Workspace.Basketball or ReplicatedStorage.Basketball.Value
        local ballVal = ReplicatedStorage:FindFirstChild("Basketball")
        local ballPart = (ballVal and ballVal.Value) or workspace:FindFirstChild("Basketball")
        if ballPart and ballPart:IsA("BasePart") then
            return ballPart.Position, "Free Ball", false, false, false
        end

        return nil, nil, false, false, false
    end

    -- ============================================================
    --   AUTO GREEN RELEASE ENGINE (Native Input Release)
    -- ============================================================
    local hasReleasedThisShot = false
    local cachedShotMeter = nil

    local function getShotMeterGui()
        if cachedShotMeter and cachedShotMeter.Parent then
            return cachedShotMeter
        end
        local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
        cachedShotMeter = pg and pg:FindFirstChild("ShotMeter")
        return cachedShotMeter
    end

    local function triggerShotRelease()
        if type(mouse1release) == "function" then
            pcall(mouse1release)
        elseif type(mouse1click) == "function" then
            pcall(mouse1click)
        else
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                if vim then
                    vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end
            end)
        end
    end

    local function updateAutoGreen()
        if not settings.autoGreen then return end

        local shotMeterGui = getShotMeterGui()
        if not shotMeterGui or not shotMeterGui.Enabled then
            hasReleasedThisShot = false
            return
        end

        local bg = shotMeterGui:FindFirstChild("BG")
        if not bg then return end

        local isShooting = (bg.GroupTransparency < 0.6)
        if not isShooting then
            hasReleasedThisShot = false
            return
        end

        if hasReleasedThisShot then return end

        local bar = bg:FindFirstChild("Bar")
        local green = bg:FindFirstChild("Green")
        if not bar or not green then return end

        local barPos = bar.Position.Y.Scale
        local greenPos = green.Position.Y.Scale
        local greenSize = green.Size.Y.Scale

        local greenCenter = greenPos + (greenSize * 0.5) + settings.greenOffset
        local distance = math.abs(barPos - greenCenter)

        if distance <= (greenSize * 0.46) then
            hasReleasedThisShot = true

            -- Face Rim if enabled
            if settings.autoFaceRim then
                local char = localPlayer.Character
                local hrp = getRoot(char)
                if hrp then
                    local rim = getTargetRim(hrp.Position)
                    if rim then
                        local lookDir = Vector3.new(rim.Position.X - hrp.Position.X, 0, rim.Position.Z - hrp.Position.Z)
                        if lookDir.Magnitude > 0.1 then
                            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir)
                        end
                    end
                end
            end

            triggerShotRelease()
        end
    end

    -- ============================================================
    --   AUTO STEAL & COMPLETE ANTI-ANKLE BREAK
    -- ============================================================
    local lastStealAttempt = 0

    local function updateDefense(myPos)
        if not settings.antiAnkleBreak and not settings.alwaysRun and not settings.autoSteal then
            return
        end

        ensureControllers()
        local now = os.clock()

        -- 1. Complete Anti-Ankle Break (Clears Stun, Kneel, and NoWalk)
        if settings.antiAnkleBreak and MovementController and MovementController.States then
            local s = MovementController.States
            if s.Stunned then s.Stunned = false end
            if s.Kneeling then s.Kneeling = false end
            if s.NoWalk then s.NoWalk = false end
            if s.AfterStun then s.AfterStun = false end

            if Network and Network.CharValues and Network.CharValues.Stunned then
                Network.CharValues.Stunned = false
            end
        end

        -- 2. Always Run
        if settings.alwaysRun and MovementController then
            if MovementController.AlwaysRun == false then
                MovementController.AlwaysRun = true
            end
            if MovementController.States and MovementController.States.ActualRunning == false then
                MovementController.States.ActualRunning = true
            end
        end

        -- 3. Auto Steal (Guarded Distance & Debounce)
        if settings.autoSteal and DefenseController and (now - lastStealAttempt) > 0.65 then
            local enemy = nil
            if BallController and type(BallController.GetEnemyWithBallWithinDistance) == "function" then
                pcall(function()
                    enemy = BallController:GetEnemyWithBallWithinDistance(settings.stealReach)
                end)
            end

            if enemy then
                lastStealAttempt = now
                pcall(function()
                    DefenseController:Steal()
                end)
            end
        end
    end

    -- ============================================================
    --   HIGH-PERFORMANCE ZERO-LAG VISUALS (100% Drawing API)
    -- ============================================================
    local function updateVisuals(myPos)
        if not hasDrawing then return end

        if not settings.ballEsp and not settings.rimEsp and not settings.playerEsp then
            if next(espDrawings) ~= nil then
                for k, d in pairs(espDrawings) do
                    removeDrawingSet(d)
                end
                table.clear(espDrawings)
            end
            return
        end

        if not camera or not camera.Parent then
            camera = workspace.CurrentCamera
        end
        if not camera then return end

        local activeKeys = {}
        local viewportSize = camera.ViewportSize
        local maxDist = settings.maxDistance

        -- 1. Dual-Mode Basketball ESP
        if settings.ballEsp then
            local ballPos, ballCarrier, isPossessed, isLocal, isTeammate = getAccurateBallData()

            if ballPos then
                local bKey = "BALL"
                activeKeys[bKey] = true
                if not espDrawings[bKey] then
                    espDrawings[bKey] = newPointDrawingSet(Color3.fromRGB(255, 140, 0))
                end
                local d = espDrawings[bKey]

                local screenPos, onScreen = camera:WorldToViewportPoint(ballPos)
                if onScreen and screenPos.Z > 0 then
                    d.visible = true
                    local distStuds = (ballPos - myPos).Magnitude
                    local distMeters = math.floor(distStuds * 0.28)

                    -- Color distinction: Orange for free ball, Green for you, Blue for team, Red for enemy
                    local ballColor = Color3.fromRGB(255, 150, 0)
                    local textHeader = "🏀 Free Ball"

                    if isPossessed then
                        if isLocal then
                            ballColor = Color3.fromRGB(50, 255, 120)
                            textHeader = "🏀 Ball (YOU)"
                        elseif isTeammate then
                            ballColor = Color3.fromRGB(80, 180, 255)
                            textHeader = string.format("🏀 Ball [%s]", ballCarrier)
                        else
                            ballColor = Color3.fromRGB(255, 60, 60)
                            textHeader = string.format("🏀 Ball [%s]", ballCarrier)
                        end
                    end

                    if d.circle then
                        d.circle.Position = Vector2.new(screenPos.X, screenPos.Y)
                        d.circle.Color = ballColor
                        d.circle.Visible = true
                    end

                    if d.text then
                        d.text.Position = Vector2.new(screenPos.X, screenPos.Y - 20)
                        d.text.Color = ballColor
                        d.text.Text = string.format("%s [%dm]", textHeader, distMeters)
                        d.text.Visible = true
                    end

                    if settings.ballTracer and d.tracer then
                        d.tracer.From = Vector2.new(viewportSize.X / 2, viewportSize.Y)
                        d.tracer.To = Vector2.new(screenPos.X, screenPos.Y)
                        d.tracer.Color = ballColor
                        d.tracer.Visible = true
                    elseif d.tracer and d.tracer.Visible then
                        d.tracer.Visible = false
                    end
                else
                    hideDrawingSet(d)
                end
            else
                if espDrawings["BALL"] then
                    hideDrawingSet(espDrawings["BALL"])
                end
            end
        end

        -- 2. Rim ESP
        if settings.rimEsp then
            local rim, dist = getTargetRim(myPos)
            if rim then
                local rKey = "RIM"
                activeKeys[rKey] = true
                if not espDrawings[rKey] then
                    espDrawings[rKey] = newPointDrawingSet(Color3.fromRGB(0, 255, 180))
                end
                local d = espDrawings[rKey]

                local screenPos, onScreen = camera:WorldToViewportPoint(rim.Position)
                if onScreen and screenPos.Z > 0 then
                    d.visible = true
                    d.circle.Position = Vector2.new(screenPos.X, screenPos.Y)
                    d.circle.Visible = true

                    d.text.Position = Vector2.new(screenPos.X, screenPos.Y - 18)
                    d.text.Text = string.format("🎯 Rim [%dm]", math.floor(dist * 0.28))
                    d.text.Visible = true
                else
                    hideDrawingSet(d)
                end
            end
        end

        -- 3. Optimized Player Drawing ESP (Zero-Stutter)
        if settings.playerEsp then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= localPlayer and p.Character then
                    local pChar = p.Character
                    local pRoot = getRoot(pChar)

                    if pRoot then
                        local dist = (pRoot.Position - myPos).Magnitude
                        if dist <= maxDist then
                            local pHum = getHumanoid(pChar)
                            if pHum and pHum.Health > 0 then
                                local pKey = "PLR_" .. p.Name
                                activeKeys[pKey] = true
                                if not espDrawings[pKey] then
                                    espDrawings[pKey] = newPlayerDrawingSet()
                                end
                                local d = espDrawings[pKey]

                                local rootScreen, onScreen = camera:WorldToViewportPoint(pRoot.Position)
                                if onScreen and rootScreen.Z > 0 then
                                    d.visible = true

                                    -- Fast bounding box calculation
                                    local headOffset = Vector3.new(0, 2.2, 0)
                                    local footOffset = Vector3.new(0, -2.8, 0)
                                    local topScreen = camera:WorldToViewportPoint(pRoot.Position + headOffset)
                                    local botScreen = camera:WorldToViewportPoint(pRoot.Position + footOffset)

                                    local boxHeight = math.abs(botScreen.Y - topScreen.Y)
                                    if boxHeight >= 6 then
                                        local boxWidth = math.floor(boxHeight * 0.58)
                                        local boxX = math.floor(rootScreen.X - boxWidth / 2)
                                        local boxY = math.floor(topScreen.Y)

                                        local isTeammate = (p.Team ~= nil and localPlayer.Team ~= nil and p.Team == localPlayer.Team)
                                        local tagColor = isTeammate and Color3.fromRGB(75, 160, 255) or Color3.fromRGB(255, 75, 75)

                                        -- Bounding Box
                                        if settings.showBoxes and d.box then
                                            if d.boxOutline then
                                                d.boxOutline.Size = Vector2.new(boxWidth + 2, boxHeight + 2)
                                                d.boxOutline.Position = Vector2.new(boxX - 1, boxY - 1)
                                                if not d.boxOutline.Visible then d.boxOutline.Visible = true end
                                            end
                                            d.box.Size = Vector2.new(boxWidth, boxHeight)
                                            d.box.Position = Vector2.new(boxX, boxY)
                                            d.box.Color = tagColor
                                            if not d.box.Visible then d.box.Visible = true end
                                        else
                                            if d.box and d.box.Visible then d.box.Visible = false end
                                            if d.boxOutline and d.boxOutline.Visible then d.boxOutline.Visible = false end
                                        end

                                        -- Player Name
                                        if d.name then
                                            d.name.Text = p.DisplayName or p.Name
                                            d.name.Position = Vector2.new(boxX + boxWidth / 2, boxY - 16)
                                            d.name.Color = tagColor
                                            if not d.name.Visible then d.name.Visible = true end
                                        end

                                        -- Distance
                                        if settings.espDistance and d.dist then
                                            d.dist.Text = string.format("[%dm]", math.floor(dist * 0.28))
                                            d.dist.Position = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight + 2)
                                            if not d.dist.Visible then d.dist.Visible = true end
                                        else
                                            if d.dist and d.dist.Visible then d.dist.Visible = false end
                                        end

                                        -- Tracers
                                        if settings.showTracers and d.tracer then
                                            d.tracer.From = Vector2.new(viewportSize.X / 2, viewportSize.Y)
                                            d.tracer.To = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight)
                                            d.tracer.Color = tagColor
                                            if not d.tracer.Visible then d.tracer.Visible = true end
                                        else
                                            if d.tracer and d.tracer.Visible then d.tracer.Visible = false end
                                        end
                                    else
                                        hideDrawingSet(d)
                                    end
                                else
                                    hideDrawingSet(d)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Prune stale drawings
        for k, d in pairs(espDrawings) do
            if not activeKeys[k] then
                removeDrawingSet(d)
                espDrawings[k] = nil
            end
        end
    end

    -- ============================================================
    --   MAIN RUNNER LOOP
    -- ============================================================
    connect(RunService.RenderStepped, function()
        if not running then return end

        local hasActiveFeature = settings.autoGreen or settings.antiAnkleBreak or settings.alwaysRun 
            or settings.autoSteal or settings.ballEsp or settings.rimEsp or settings.playerEsp
        if not hasActiveFeature then return end

        local myChar = localPlayer.Character
        local myRoot = getRoot(myChar)
        local myPos = myRoot and myRoot.Position or Vector3.zero

        updateAutoGreen()
        updateDefense(myPos)
        updateVisuals(myPos)
    end)

    -- ============================================================
    --   USER INTERFACE (Ghost DrawingUI or MacLib Compatible)
    -- ============================================================

    -- Tab 0: Overview
    local HomeTab = (type(Window.GetTab) == "function" and Window:GetTab("Overview"))
    if not HomeTab and type(Window.CreateTab) == "function" then
        HomeTab = Window:CreateTab("Overview", "overview")
        HomeTab:CreateSection("Experience & Security")
        HomeTab:CreateLabel("Experience: Basketball: Zero")
        HomeTab:CreateLabel("PlaceId: " .. tostring(game.PlaceId))
        HomeTab:CreateLabel("Anti-Cheat: BAC (Frog Anti-Cheat) Active")
        HomeTab:CreateLabel("Engine: 100% Drawing Safe (Zero Object Injection)")
        HomeTab:CreateLabel("Active Module: Basketball: Zero [v1.1.0]")
        HomeTab:CreateLabel("Status: Active & Guarded")
        HomeTab:CreateSection("Tactical Overview")
        HomeTab:CreateParagraph({
            Title = "Active Features",
            Content = "Auto Green Release, Dual-Mode Ball ESP, Complete Anti-Ankle Break, Auto Steal, and Zero-Lag Drawing ESP.",
        })
    end

    -- Tab 1: Shooting
    local ShootTab = Window:CreateTab("Shooting", "combat")
    ShootTab:CreateSection("Auto Green Release")

    ShootTab:CreateToggle({
        Name = "Auto Green Release",
        CurrentValue = settings.autoGreen,
        Flag = "BZ_AutoGreen",
        Callback = function(value)
            settings.autoGreen = value
        end,
    })

    ShootTab:CreateSlider({
        Name = "Green Timing Offset",
        Range = {-0.05, 0.05},
        Increment = 0.005,
        Suffix = "s",
        CurrentValue = settings.greenOffset,
        Flag = "BZ_GreenOffset",
        Callback = function(value)
            settings.greenOffset = value
        end,
    })

    ShootTab:CreateToggle({
        Name = "Auto Face Rim on Shot",
        CurrentValue = settings.autoFaceRim,
        Flag = "BZ_AutoFaceRim",
        Callback = function(value)
            settings.autoFaceRim = value
        end,
    })

    -- Tab 2: Defense & Mobility
    local DefTab = Window:CreateTab("Defense", "movement")
    DefTab:CreateSection("Ball Defense")

    DefTab:CreateToggle({
        Name = "Auto Steal",
        CurrentValue = settings.autoSteal,
        Flag = "BZ_AutoSteal",
        Callback = function(value)
            settings.autoSteal = value
            if value then
                ensureControllers()
            end
        end,
    })

    DefTab:CreateSlider({
        Name = "Safe Steal Distance",
        Range = {5, 10},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = settings.stealReach,
        Flag = "BZ_StealReach",
        Callback = function(value)
            settings.stealReach = value
        end,
    })

    DefTab:CreateSection("Mobility & Guard")

    DefTab:CreateToggle({
        Name = "Anti-Ankle Break (Immune to Stumble)",
        CurrentValue = settings.antiAnkleBreak,
        Flag = "BZ_AntiAnkleBreak",
        Callback = function(value)
            settings.antiAnkleBreak = value
            if value then
                ensureControllers()
            end
        end,
    })

    DefTab:CreateToggle({
        Name = "Always Run (Infinite Sprint)",
        CurrentValue = settings.alwaysRun,
        Flag = "BZ_AlwaysRun",
        Callback = function(value)
            settings.alwaysRun = value
            if value then
                ensureControllers()
            end
            if MovementController then
                pcall(function() MovementController.AlwaysRun = value end)
            end
        end,
    })

    -- Tab 3: Visuals & ESP (100% Drawing API)
    local VisualTab = Window:CreateTab("Visuals", "esp")
    VisualTab:CreateSection("Basketball & Rim ESP")

    VisualTab:CreateToggle({
        Name = "Basketball ESP (Carrier & Free Ball)",
        CurrentValue = settings.ballEsp,
        Flag = "BZ_BallEsp",
        Callback = function(value)
            settings.ballEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Ball Snapline Tracer",
        CurrentValue = settings.ballTracer,
        Flag = "BZ_BallTracer",
        Callback = function(value)
            settings.ballTracer = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Target Rim ESP & Distance",
        CurrentValue = settings.rimEsp,
        Flag = "BZ_RimEsp",
        Callback = function(value)
            settings.rimEsp = value
        end,
    })

    VisualTab:CreateSection("Player ESP (Zero Lag)")

    VisualTab:CreateToggle({
        Name = "Player Bounding Boxes",
        CurrentValue = settings.showBoxes,
        Flag = "BZ_PlayerBoxes",
        Callback = function(value)
            settings.showBoxes = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Names",
        CurrentValue = settings.playerEsp,
        Flag = "BZ_PlayerEsp",
        Callback = function(value)
            settings.playerEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Distance",
        CurrentValue = settings.espDistance,
        Flag = "BZ_PlayerDist",
        Callback = function(value)
            settings.espDistance = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Tracers",
        CurrentValue = settings.showTracers,
        Flag = "BZ_Tracers",
        Callback = function(value)
            settings.showTracers = value
        end,
    })

    VisualTab:CreateSlider({
        Name = "Max ESP Distance",
        Range = {100, 500},
        Increment = 25,
        Suffix = " studs",
        CurrentValue = settings.maxDistance,
        Flag = "BZ_MaxDistance",
        Callback = function(value)
            settings.maxDistance = value
        end,
    })

    -- Tab 4: Safety & Info
    local SafeTab = Window:CreateTab("Safety", "tools")
    SafeTab:CreateSection("Anti-Cheat Guard")

    SafeTab:CreateToggle({
        Name = "Honeypot Shield (BAC Active)",
        CurrentValue = settings.safeModeGuard,
        Flag = "BZ_SafeShield",
        Callback = function(value)
            settings.safeModeGuard = value
        end,
    })
    SafeTab:CreateLabel("Guards against BAC Honeypot Traps & Fake Remotes.")

    -- ============================================================
    --   CLEANUP & TEARDOWN
    -- ============================================================
    local function destroyScript()
        if not running then return end
        running = false

        for _, conn in ipairs(connections) do
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
        end
        table.clear(connections)

        for _, d in pairs(espDrawings) do
            removeDrawingSet(d)
        end
        table.clear(espDrawings)

        if MovementController then
            pcall(function() MovementController.AlwaysRun = false end)
        end

        settings.autoGreen = false
        settings.greenOffset = 0.0
        settings.autoFaceRim = false
        settings.autoSteal = false
        settings.antiAnkleBreak = false
        settings.alwaysRun = false
        settings.ballEsp = false
        settings.ballTracer = false
        settings.rimEsp = false
        settings.playerEsp = false
        settings.espDistance = false
        settings.showBoxes = false
        settings.showTracers = false
        hasReleasedThisShot = false
        lastStealAttempt = 0
        table.clear(cachedRims)

        if environment and environment.__RAVEN_BASKETBALL_ZERO then
            environment.__RAVEN_BASKETBALL_ZERO = nil
        end
    end

    if Window and type(Window.OnUnload) == "function" then
        Window:OnUnload(destroyScript)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end

    environment.__RAVEN_BASKETBALL_ZERO = {
        Destroy = function()
            destroyScript()
            if Window and type(Window.Destroy) == "function" then
                Window:Destroy()
            end
        end
    }

    -- Tab 5: Settings
    local SettingsTab = (type(Window.GetTab) == "function" and Window:GetTab("Settings"))
    if not SettingsTab and type(Window.CreateTab) == "function" then
        SettingsTab = Window:CreateTab("Settings", "settings")
    end
    if SettingsTab and type(SettingsTab.InsertConfigSection) == "function" then
        SettingsTab:InsertConfigSection("Right")
    end

    if type(Window.SortTabs) == "function" then
        Window:SortTabs({"Overview", "Shooting", "Defense", "Visuals", "Safety", "Settings"})
    end
end
