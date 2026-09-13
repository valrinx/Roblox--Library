-- ============================================================
--   RAVEN HUB  |  Racket Rivals (Starter & Ranked)
--   High-Performance 100% Drawing API Engine (Zero Injection / Clean Architecture)
--   Multi-Layer Ball Acquisition, Approach-Filtered Auto Parry,
--   Movement & Infinite Stamina, Clean Auto Serve, Full Visuals
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local Workspace = game:GetService("Workspace")

    -- Clean up previous instance if running
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_RACKET_RIVALS) == "table"
        and type(environment.__RAVEN_RACKET_RIVALS.Destroy) == "function" then
        pcall(environment.__RAVEN_RACKET_RIVALS.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    local running = true
    local connections = {}

    -- Settings
    local settings = {
        -- Tab 1: Combat (Auto Parry / Auto Swing)
        autoParry = true,
        hitRadius = 24,
        cooldown = 0.35,
        approachFilter = true,
        autoAimBall = false,

        -- Tab 2: Movement & Mobility
        speedBoost = false,
        speedMultiplier = 1.35,
        infiniteStamina = false,
        fastDash = false,

        -- Tab 3: Visuals & ESP (100% Drawing API)
        ballEsp = true,
        ballTracer = true,
        reachCircle = true,
        playerEsp = false,
        espDistance = true,
        showBoxes = false,
        showTracers = false,
        maxDistance = 300,

        -- Tab 4: Automation
        autoServe = false,
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
            d.box.Color = Color3.fromRGB(0, 255, 170)
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
            d.dist.Color = Color3.fromRGB(200, 210, 225)
            d.dist.Visible = false
        end

        if d.tracer then
            d.tracer.Thickness = 1
            d.tracer.Color = Color3.fromRGB(0, 255, 170)
            d.tracer.Visible = false
        end

        return d
    end

    local function newBallDrawingSet()
        local d = {
            circle = safeDrawing("Circle"),
            text = safeDrawing("Text"),
            tracer = safeDrawing("Line"),
            reachCircle = safeDrawing("Circle"),
            visible = false,
        }

        if d.circle then
            d.circle.Thickness = 2
            d.circle.Filled = true
            d.circle.Color = Color3.fromRGB(255, 50, 80)
            d.circle.Radius = 7
            d.circle.Visible = false
        end

        if d.text then
            d.text.Size = 12
            d.text.Center = true
            d.text.Outline = true
            d.text.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.text.Color = Color3.fromRGB(255, 255, 255)
            d.text.Visible = false
        end

        if d.tracer then
            d.tracer.Thickness = 1.2
            d.tracer.Color = Color3.fromRGB(255, 50, 80)
            d.tracer.Visible = false
        end

        if d.reachCircle then
            d.reachCircle.Thickness = 1.5
            d.reachCircle.Filled = false
            d.reachCircle.Color = Color3.fromRGB(255, 220, 40)
            d.reachCircle.NumSides = 36
            d.reachCircle.Visible = false
        end

        return d
    end

    local ballDrawing = newBallDrawingSet()

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
        if d.reachCircle and d.reachCircle.Visible then d.reachCircle.Visible = false end
    end

    local function removeDrawingSet(d)
        if not d then return end
        d.visible = false
        for _, obj in pairs(d) do
            if type(obj) == "table" or type(obj) == "userdata" then
                pcall(function()
                    obj.Visible = false
                    obj:Remove()
                end)
            end
        end
    end

    -- ------------------------------------------------------------
    -- MOVEMENT & STAMINA INTERNAL HANDLER
    -- ------------------------------------------------------------
    local cachedMovementHandler = nil
    local function getMovementHandler()
        if cachedMovementHandler and cachedMovementHandler.Character == localPlayer.Character then
            return cachedMovementHandler
        end
        if type(getgc) == "function" then
            for _, obj in ipairs(getgc(true)) do
                if type(obj) == "table" and rawget(obj, "Stamina") and rawget(obj, "MaxStamina") then
                    if obj.Character == localPlayer.Character or obj.RootPart then
                        cachedMovementHandler = obj
                        return obj
                    end
                end
            end
        end
        return nil
    end

    -- ------------------------------------------------------------
    -- MULTI-LAYER BALL ACQUISITION SYSTEM
    -- ------------------------------------------------------------
    local cachedLBallClass = nil
    local function getActiveLBall()
        if cachedLBallClass and cachedLBallClass.CURRENT_ACTIVE_BALL then
            return cachedLBallClass.CURRENT_ACTIVE_BALL
        end
        if type(getloadedmodules) == "function" and type(getupvalue) == "function" then
            for _, mod in ipairs(getloadedmodules()) do
                if mod.Name == "lBall" then
                    local ok, lBall = pcall(require, mod)
                    if ok and type(lBall) == "function" then
                        for i = 1, 10 do
                            local okUp, val = pcall(getupvalue, lBall, i)
                            if okUp and type(val) == "table" and rawget(val, "CURRENT_ACTIVE_BALL") ~= nil then
                                cachedLBallClass = val
                                return val.CURRENT_ACTIVE_BALL
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function scanWorkspaceForBall()
        -- 1. Scan direct children of Workspace (primary location created by lBall:CreateBody)
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("BasePart") or child:IsA("Model") then
                if child:FindFirstChild("DeflectParticles", true)
                    or child:FindFirstChild("DeflectPerfect", true)
                    or child:FindFirstChild("BoostVFX", true) then
                    local part = child:IsA("BasePart") and child or child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
                    if part then return part end
                end

                if child:FindFirstChildOfClass("Highlight") then
                    local part = child:IsA("BasePart") and child or child:FindFirstChildWhichIsA("BasePart")
                    if part and part.CanCollide == false and (part.Name == "Default" or part.Name == "Normal" or part.Name:lower():find("ball")) then
                        return part
                    end
                end
            end
        end

        -- 2. Scan Workspace.FX
        local fx = Workspace:FindFirstChild("FX")
        if fx then
            for _, child in ipairs(fx:GetChildren()) do
                if child:IsA("BasePart") and not child.Name:find("Shadow") and not child.Name:find("Trail") then
                    if child.Name == "Default" or child.Name:lower():find("ball") then
                        return child
                    end
                end
            end
        end

        -- 3. Scan Courts as fallback
        local courts = Workspace:FindFirstChild("Courts")
        if courts then
            for _, court in ipairs(courts:GetChildren()) do
                for _, desc in ipairs(court:GetDescendants()) do
                    if (desc:IsA("BasePart") or desc:IsA("Model")) and not desc.Name:find("Balloon") and not desc.Name:find("Shadow") then
                        if desc:FindFirstChild("DeflectParticles", true) or desc:FindFirstChild("DeflectPerfect", true) then
                            local part = desc:IsA("BasePart") and desc or desc:FindFirstChildWhichIsA("BasePart")
                            if part then return part end
                        end
                    end
                end
            end
        end

        return nil
    end

    local function findActiveBall()
        -- 1. Authoritative beam target position from Workspace.FX.BallShadow.A1
        local fx = Workspace:FindFirstChild("FX")
        local shadow = fx and fx:FindFirstChild("BallShadow")
        local a1 = shadow and shadow:FindFirstChild("A1")
        if a1 and typeof(a1.WorldPosition) == "Vector3" then
            return { Position = a1.WorldPosition }
        end

        -- 2. Physical MeshPart: Workspace.Part or any child in Workspace with DeflectParticles / DeflectPerfect
        for _, child in ipairs(Workspace:GetChildren()) do
            if (child:IsA("MeshPart") or child:IsA("BasePart")) and (
                child:FindFirstChild("DeflectParticles", true) or 
                child:FindFirstChild("DeflectPerfect", true) or 
                child:FindFirstChild("BoostActiveVFX", true) or
                child:FindFirstChildOfClass("Highlight")
            ) then
                return child
            end
        end

        -- 3. Authoritative lBall internal instance fallback
        local lBallObj = getActiveLBall()
        if lBallObj then
            if lBallObj.Body and lBallObj.Body.Parent then
                local part = lBallObj.Body:IsA("BasePart") and lBallObj.Body or lBallObj.Body:FindFirstChildWhichIsA("BasePart")
                if part then return part end
            end
            if typeof(lBallObj.Position) == "Vector3" then
                return { Position = lBallObj.Position }
            end
        end

        return nil
    end

    -- ------------------------------------------------------------
    -- COMBAT EXECUTION ENGINE (SWING SIMULATOR)
    -- ------------------------------------------------------------
    local lastSwingTime = 0
    local lastServeTime = 0
    local lastBallPos = nil
    local lastBallTime = 0
    local ballVelocity = Vector3.zero

    local function triggerSwing(ballPos)
        local now = os.clock()
        if (now - lastSwingTime) < settings.cooldown then return end
        lastSwingTime = now

        local char = localPlayer.Character
        local root = getRoot(char)

        -- Smooth horizontal face ball (no camera snap / no screen twitch)
        if settings.autoAimBall and ballPos and root then
            local flatBall = Vector3.new(ballPos.X, root.Position.Y, ballPos.Z)
            pcall(function()
                root.CFrame = CFrame.lookAt(root.Position, flatBall)
            end)
        end

        local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local centerX = math.floor(vp.X / 2)
        local centerY = math.floor(vp.Y / 2)

        -- Send Mouse Left Click + Press Key F for 100% actuation
        VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 0)
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.delay(0.04, function()
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 0)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end)
    end

    -- ------------------------------------------------------------
    -- RUNTIME ENGINE LOOP
    -- ------------------------------------------------------------
    connect(RunService.RenderStepped, function()
        if not running then return end

        local char = localPlayer.Character
        local root = getRoot(char)
        local humanoid = getHumanoid(char)
        local myPos = root and root.Position or (camera and camera.CFrame.Position)

        -- 1. Movement & Stamina updates
        if humanoid and root then
            local moveHandler = getMovementHandler()

            if settings.speedBoost then
                if moveHandler and type(moveHandler.OverrideMoveSpeed) == "function" then
                    pcall(function()
                        moveHandler:OverrideMoveSpeed("RavenSpeed", 8 * settings.speedMultiplier)
                    end)
                else
                    humanoid.WalkSpeed = 16 * settings.speedMultiplier
                end
            end

            if settings.infiniteStamina and moveHandler then
                moveHandler.Stamina = moveHandler.MaxStamina or 1
            end

            if settings.fastDash and moveHandler then
                moveHandler.CanDash = true
                if moveHandler.DashLock and type(moveHandler.DashLock.Remove) == "function" then
                    pcall(function()
                        moveHandler.DashLock:Remove("Cooldown")
                    end)
                end
            end
        end

        -- 2. Auto Serve handler
        if settings.autoServe then
            local now = os.clock()
            if (now - lastServeTime) > 1.2 then
                pcall(function()
                    local values = ReplicatedStorage:FindFirstChild("Values")
                    if values and values:IsA("ModuleScript") then
                        local vTable = require(values)
                        if vTable and vTable.PLAYER_SERVE_STATE and vTable.PLAYER_SERVE_STATE:Get() == true then
                            lastServeTime = now
                            triggerSwing(nil)
                        end
                    end
                end)
            end
        end

        -- 3. Ball Tracking & Auto Parry
        local activeBall, lBallObj = findActiveBall()
        if activeBall and root and myPos then
            local ballPos = activeBall.Position
            local now = os.clock()
            local dt = now - lastBallTime

            -- Compute smoothed velocity
            if lastBallPos and dt > 0 and dt < 0.2 then
                local instantVel = (ballPos - lastBallPos) / dt
                ballVelocity = ballVelocity:Lerp(instantVel, 0.4)
            end
            lastBallPos = ballPos
            lastBallTime = now

            local dist = (ballPos - myPos).Magnitude
            local toPlayer = (myPos - ballPos).Unit
            -- Ball is moving toward or near player when dot product > -5
            local isApproaching = not settings.approachFilter or (ballVelocity:Dot(toPlayer) > -5)

            -- Auto Parry Trigger
            if settings.autoParry and dist <= settings.hitRadius and isApproaching then
                triggerSwing(ballPos)
            end

            -- Visuals: Ball ESP & Reach Zone
            if hasDrawing and (settings.ballEsp or settings.reachCircle) then
                local screenPos, onScreen = camera:WorldToViewportPoint(ballPos)

                -- Racket Reach Zone circle
                if settings.reachCircle and ballDrawing.reachCircle then
                    local rootScreen, rootOnScreen = camera:WorldToViewportPoint(myPos)
                    if rootOnScreen then
                        local edgeScreen = camera:WorldToViewportPoint(myPos + Vector3.new(settings.hitRadius, 0, 0))
                        ballDrawing.reachCircle.Position = Vector2.new(rootScreen.X, rootScreen.Y)
                        ballDrawing.reachCircle.Radius = math.abs(edgeScreen.X - rootScreen.X)
                        ballDrawing.reachCircle.Visible = true
                    else
                        ballDrawing.reachCircle.Visible = false
                    end
                elseif ballDrawing.reachCircle then
                    ballDrawing.reachCircle.Visible = false
                end

                -- Ball Dot & Text
                if settings.ballEsp and onScreen then
                    local isParryReady = dist <= settings.hitRadius
                    local speedKmH = math.floor(ballVelocity.Magnitude * 3.6 / 3.571)

                    if ballDrawing.circle then
                        ballDrawing.circle.Position = Vector2.new(screenPos.X, screenPos.Y)
                        ballDrawing.circle.Color = isParryReady and Color3.fromRGB(255, 40, 70) or Color3.fromRGB(0, 255, 170)
                        ballDrawing.circle.Visible = true
                    end

                    if ballDrawing.text then
                        ballDrawing.text.Position = Vector2.new(screenPos.X, screenPos.Y - 22)
                        ballDrawing.text.Text = string.format("[ BALL: %.1fm | %d km/h ]", dist, speedKmH)
                        ballDrawing.text.Color = isParryReady and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
                        ballDrawing.text.Visible = true
                    end

                    if settings.ballTracer and ballDrawing.tracer then
                        ballDrawing.tracer.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                        ballDrawing.tracer.To = Vector2.new(screenPos.X, screenPos.Y)
                        ballDrawing.tracer.Color = isParryReady and Color3.fromRGB(255, 40, 70) or Color3.fromRGB(0, 255, 170)
                        ballDrawing.tracer.Visible = true
                    elseif ballDrawing.tracer then
                        ballDrawing.tracer.Visible = false
                    end
                    ballDrawing.visible = true
                else
                    if ballDrawing.circle then ballDrawing.circle.Visible = false end
                    if ballDrawing.text then ballDrawing.text.Visible = false end
                    if ballDrawing.tracer then ballDrawing.tracer.Visible = false end
                end
            end
        else
            lastBallPos = nil
            hideDrawingSet(ballDrawing)
        end

        -- 4. Player ESP
        if hasDrawing and (settings.playerEsp or settings.showBoxes or settings.showTracers) then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer then
                    local pChar = player.Character
                    local pRoot = getRoot(pChar)
                    local d = espDrawings[player]

                    if not d then
                        d = newPlayerDrawingSet()
                        espDrawings[player] = d
                    end

                    if pRoot and myPos then
                        local pPos = pRoot.Position
                        local dist = (pPos - myPos).Magnitude

                        if dist <= settings.maxDistance then
                            local screenPos, onScreen = camera:WorldToViewportPoint(pPos)
                            if onScreen then
                                local head = pChar:FindFirstChild("Head")
                                local headPos = head and head.Position or (pPos + Vector3.new(0, 2, 0))
                                local topScreen = camera:WorldToViewportPoint(headPos + Vector3.new(0, 0.6, 0))
                                local bottomScreen = camera:WorldToViewportPoint(pPos - Vector3.new(0, 3, 0))

                                local boxHeight = math.abs(bottomScreen.Y - topScreen.Y)
                                local boxWidth = boxHeight * 0.65
                                local boxLeft = screenPos.X - (boxWidth / 2)
                                local boxTop = topScreen.Y

                                if settings.showBoxes then
                                    if d.boxOutline then
                                        d.boxOutline.Position = Vector2.new(boxLeft, boxTop)
                                        d.boxOutline.Size = Vector2.new(boxWidth, boxHeight)
                                        d.boxOutline.Visible = true
                                    end
                                    if d.box then
                                        d.box.Position = Vector2.new(boxLeft, boxTop)
                                        d.box.Size = Vector2.new(boxWidth, boxHeight)
                                        d.box.Visible = true
                                    end
                                else
                                    if d.boxOutline then d.boxOutline.Visible = false end
                                    if d.box then d.box.Visible = false end
                                end

                                if settings.playerEsp and d.name then
                                    d.name.Position = Vector2.new(screenPos.X, boxTop - 15)
                                    d.name.Text = player.DisplayName or player.Name
                                    d.name.Visible = true
                                else
                                    if d.name then d.name.Visible = false end
                                end

                                if settings.espDistance and d.dist then
                                    d.dist.Position = Vector2.new(screenPos.X, boxTop + boxHeight + 2)
                                    d.dist.Text = string.format("[ %.0fm ]", dist)
                                    d.dist.Visible = true
                                else
                                    if d.dist then d.dist.Visible = false end
                                end

                                if settings.showTracers and d.tracer then
                                    d.tracer.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                                    d.tracer.To = Vector2.new(screenPos.X, boxTop + boxHeight)
                                    d.tracer.Visible = true
                                else
                                    if d.tracer then d.tracer.Visible = false end
                                end

                                d.visible = true
                            else
                                hideDrawingSet(d)
                            end
                        else
                            hideDrawingSet(d)
                        end
                    else
                        hideDrawingSet(d)
                    end
                end
            end
        else
            for _, d in pairs(espDrawings) do
                hideDrawingSet(d)
            end
        end
    end)

    connect(Players.PlayerRemoving, function(player)
        if espDrawings[player] then
            removeDrawingSet(espDrawings[player])
            espDrawings[player] = nil
        end
    end)

    -- ------------------------------------------------------------
    -- USER INTERFACE BUILD (RAVEN HUB Standard)
    -- ------------------------------------------------------------
    local CombatTab = Window:CreateTab("Combat", "crosshair")
    CombatTab:CreateSection("Auto Parry & Swing")

    CombatTab:CreateToggle({
        Name = "Auto Parry (Auto Swing)",
        CurrentValue = settings.autoParry,
        Flag = "RR_AutoParry",
        Callback = function(value)
            settings.autoParry = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Approach Direction Filter",
        CurrentValue = settings.approachFilter,
        Flag = "RR_ApproachFilter",
        Callback = function(value)
            settings.approachFilter = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Hit Trigger Radius",
        Range = {12, 35},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = settings.hitRadius,
        Flag = "RR_HitRadius",
        Callback = function(value)
            settings.hitRadius = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Swing Cooldown Debounce",
        Range = {0.2, 0.8},
        Increment = 0.05,
        Suffix = "s",
        CurrentValue = settings.cooldown,
        Flag = "RR_Cooldown",
        Callback = function(value)
            settings.cooldown = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Face Ball On Strike",
        CurrentValue = settings.autoAimBall,
        Flag = "RR_AutoAim",
        Callback = function(value)
            settings.autoAimBall = value
        end,
    })

    CombatTab:CreateSection("Automation")

    CombatTab:CreateToggle({
        Name = "Auto Serve (Instant Release)",
        CurrentValue = settings.autoServe,
        Flag = "RR_AutoServe",
        Callback = function(value)
            settings.autoServe = value
        end,
    })

    local MoveTab = Window:CreateTab("Movement", "gauge")
    MoveTab:CreateSection("Mobility Tweaks")

    MoveTab:CreateToggle({
        Name = "WalkSpeed Multiplier",
        CurrentValue = settings.speedBoost,
        Flag = "RR_SpeedBoost",
        Callback = function(value)
            settings.speedBoost = value
            if not value and localPlayer.Character then
                local h = getHumanoid(localPlayer.Character)
                if h then h.WalkSpeed = 16 end
                local moveHandler = getMovementHandler()
                if moveHandler and type(moveHandler.RemoveSpeedMultiplier) == "function" then
                    pcall(function() moveHandler:RemoveSpeedMultiplier("RavenSpeed") end)
                end
            end
        end,
    })

    MoveTab:CreateSlider({
        Name = "Speed Multiplier",
        Range = {1.0, 2.5},
        Increment = 0.05,
        Suffix = "x",
        CurrentValue = settings.speedMultiplier,
        Flag = "RR_SpeedMultiplier",
        Callback = function(value)
            settings.speedMultiplier = value
        end,
    })

    MoveTab:CreateToggle({
        Name = "Infinite Stamina",
        CurrentValue = settings.infiniteStamina,
        Flag = "RR_InfStamina",
        Callback = function(value)
            settings.infiniteStamina = value
        end,
    })

    MoveTab:CreateToggle({
        Name = "Fast Dash (No Cooldown)",
        CurrentValue = settings.fastDash,
        Flag = "RR_FastDash",
        Callback = function(value)
            settings.fastDash = value
        end,
    })

    local VisualTab = Window:CreateTab("Visuals", "eye")
    VisualTab:CreateSection("Ball Visuals")

    VisualTab:CreateToggle({
        Name = "Ball ESP (Dot, Speed & Distance)",
        CurrentValue = settings.ballEsp,
        Flag = "RR_BallEsp",
        Callback = function(value)
            settings.ballEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Ball Tracer Line",
        CurrentValue = settings.ballTracer,
        Flag = "RR_BallTracer",
        Callback = function(value)
            settings.ballTracer = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Racket Reach Zone Circle",
        CurrentValue = settings.reachCircle,
        Flag = "RR_ReachCircle",
        Callback = function(value)
            settings.reachCircle = value
        end,
    })

    VisualTab:CreateSection("Player ESP (Zero Lag)")

    VisualTab:CreateToggle({
        Name = "Player Bounding Boxes",
        CurrentValue = settings.showBoxes,
        Flag = "RR_PlayerBoxes",
        Callback = function(value)
            settings.showBoxes = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Names",
        CurrentValue = settings.playerEsp,
        Flag = "RR_PlayerNames",
        Callback = function(value)
            settings.playerEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Distance",
        CurrentValue = settings.espDistance,
        Flag = "RR_PlayerDist",
        Callback = function(value)
            settings.espDistance = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Tracers",
        CurrentValue = settings.showTracers,
        Flag = "RR_PlayerTracers",
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
        Flag = "RR_MaxDist",
        Callback = function(value)
            settings.maxDistance = value
        end,
    })

    local function destroyScript()
        if not running then return end
        running = false

        for _, conn in ipairs(connections) do
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
        end
        table.clear(connections)

        if ballDrawing then
            removeDrawingSet(ballDrawing)
        end

        for _, d in pairs(espDrawings) do
            removeDrawingSet(d)
        end
        table.clear(espDrawings)

        if localPlayer.Character then
            local h = getHumanoid(localPlayer.Character)
            if h then h.WalkSpeed = 16 end
        end

        local moveHandler = getMovementHandler()
        if moveHandler and type(moveHandler.RemoveSpeedMultiplier) == "function" then
            pcall(function() moveHandler:RemoveSpeedMultiplier("RavenSpeed") end)
        end

        if environment and environment.__RAVEN_RACKET_RIVALS then
            environment.__RAVEN_RACKET_RIVALS = nil
        end
    end

    if Window and type(Window.OnUnload) == "function" then
        Window:OnUnload(destroyScript)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end

    environment.__RAVEN_RACKET_RIVALS = {
        Destroy = function()
            destroyScript()
            if Window and type(Window.Destroy) == "function" then
                Window:Destroy()
            end
        end
    }

    local SettingsTab = (type(Window.GetTab) == "function" and Window:GetTab("Settings"))
    if not SettingsTab and type(Window.CreateTab) == "function" then
        SettingsTab = Window:CreateTab("Settings", "settings")
    end
    if SettingsTab and type(SettingsTab.InsertConfigSection) == "function" then
        SettingsTab:InsertConfigSection("Right")
    end

    if type(Window.SortTabs) == "function" then
        Window:SortTabs({"Overview", "Combat", "Movement", "Visuals", "Settings"})
    end
end
