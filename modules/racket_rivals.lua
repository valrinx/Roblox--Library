-- ============================================================
--   RAVEN HUB  |  Racket Rivals (Starter & Ranked)
--   High-Performance 100% Drawing API Engine (Zero Injection / Clean Architecture)
--   Features:
--     - Auto Hit (Parry / Swing with approach direction filter)
--     - Auto Smash (Airborne spike on high balls)
--     - Auto Dash (Smart ball interception)
--     - Auto Jump (High ball interception)
--     - Right Click Binding for Dash (Instant manual Q trigger)
--     - Silent Aim (Smart court corner & weak spot deflection)
--     - Auto Set (High arching lob using E key)
--     - Auto Hinari (Automatic Overheat Ability 1 ignition)
--     - 100% Drawing API Visuals (Ball ESP, Reach Circle, Silent Aim Target, Player ESP)
--     - Infinite Stamina & Speed Multiplier
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
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
        -- Auto Hit / Auto Parry
        autoHit = true,
        hitRadius = 24,
        cooldown = 0.35,
        approachFilter = true,
        autoFaceBall = false,

        -- Auto Smash & Jump
        autoSmash = true,
        smashMinHeight = 4.0,
        autoJump = true,
        jumpHeightThreshold = 5.0,

        -- Auto Dash & Right Click Dash
        autoDash = false,
        dashMinDist = 20,
        dashMaxDist = 60,
        dashCooldown = 1.2,
        rightClickDash = true,
        fastDash = false,

        -- Silent Aim
        silentAim = true,
        silentAimMode = "Opponent Far Corner", -- "Opponent Far Corner", "Opponent Weak Side", "Court Baseline"
        silentAimVisual = true,

        -- Auto Set
        autoSet = false,
        setMode = "Always", -- "Always", "Low Ball Only"

        -- Auto Hinari (Overheat Ability 1)
        autoHinari = false,
        hinariCooldown = 3.0,

        -- Movement & Mobility
        speedBoost = false,
        speedMultiplier = 1.35,
        infiniteStamina = false,

        -- Visuals & ESP (100% Drawing API)
        ballEsp = true,
        ballTracer = true,
        reachCircle = true,
        playerEsp = false,
        espDistance = true,
        showBoxes = false,
        showTracers = false,
        maxDistance = 300,

        -- Automation
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
            aimCircle = safeDrawing("Circle"),
            aimTracer = safeDrawing("Line"),
            aimText = safeDrawing("Text"),
            visible = false,
        }

        if d.circle then
            d.circle.Thickness = 2
            d.circle.Filled = true
            d.circle.Radius = 6
            d.circle.Color = Color3.fromRGB(0, 255, 170)
            d.circle.Visible = false
        end

        if d.text then
            d.text.Size = 13
            d.text.Center = true
            d.text.Outline = true
            d.text.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.text.Color = Color3.fromRGB(255, 255, 255)
            d.text.Visible = false
        end

        if d.tracer then
            d.tracer.Thickness = 1.5
            d.tracer.Color = Color3.fromRGB(0, 255, 170)
            d.tracer.Visible = false
        end

        if d.reachCircle then
            d.reachCircle.Thickness = 1.5
            d.reachCircle.Filled = false
            d.reachCircle.NumSides = 48
            d.reachCircle.Color = Color3.fromRGB(0, 255, 170)
            d.reachCircle.Visible = false
        end

        if d.aimCircle then
            d.aimCircle.Thickness = 1.5
            d.aimCircle.Filled = false
            d.aimCircle.NumSides = 24
            d.aimCircle.Radius = 8
            d.aimCircle.Color = Color3.fromRGB(255, 180, 0)
            d.aimCircle.Visible = false
        end

        if d.aimTracer then
            d.aimTracer.Thickness = 1.5
            d.aimTracer.Color = Color3.fromRGB(255, 180, 0)
            d.aimTracer.Visible = false
        end

        if d.aimText then
            d.aimText.Size = 11
            d.aimText.Center = true
            d.aimText.Outline = true
            d.aimText.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.aimText.Color = Color3.fromRGB(255, 200, 50)
            d.aimText.Visible = false
        end

        return d
    end

    local ballDrawing = newBallDrawingSet()

    local function hideDrawingSet(d)
        if not d then return end
        d.visible = false
        for _, obj in pairs(d) do
            if type(obj) == "table" or type(obj) == "userdata" then
                pcall(function() obj.Visible = false end)
            end
        end
    end

    local function removeDrawingSet(d)
        if not d then return end
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
        pcall(function()
            local pc = require(ReplicatedFirst.Classes.PlayerControl)
            if pc and pc.Movement then
                cachedMovementHandler = pc.Movement
            end
        end)
        if cachedMovementHandler then return cachedMovementHandler end

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
    -- MOUSE REPLICATOR (SILENT AIM INTERNAL ENGINE)
    -- ------------------------------------------------------------
    local cachedMouseReplicator = nil
    local function getMouseReplicator()
        if cachedMouseReplicator then return cachedMouseReplicator end
        pcall(function()
            local mrMod = require(ReplicatedFirst.Classes.MouseReplicator)
            if mrMod and type(mrMod) == "table" then
                cachedMouseReplicator = mrMod
            end
        end)
        return cachedMouseReplicator
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
    -- SMART SILENT AIM TARGET CALCULATOR
    -- ------------------------------------------------------------
    local function calculateSilentAimTarget(myPos, ballPos)
        local opponentRoot = nil
        local minOpponentDist = math.huge

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer and p.Character then
                local r = getRoot(p.Character)
                if r then
                    local d = (r.Position - myPos).Magnitude
                    if d < minOpponentDist then
                        minOpponentDist = d
                        opponentRoot = r
                    end
                end
            end
        end

        local courtForward = camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
        courtForward = Vector3.new(courtForward.X, 0, courtForward.Z).Unit
        local courtRight = Vector3.new(-courtForward.Z, 0, courtForward.X).Unit

        if opponentRoot then
            local oppPos = opponentRoot.Position
            local toOpp = oppPos - myPos
            local oppLateral = toOpp:Dot(courtRight)
            local oppDepth = toOpp:Dot(courtForward)

            local targetSide = (oppLateral >= 0) and -1 or 1
            local targetDistForward = math.clamp(oppDepth + 15, 35, 75)
            local targetDistLateral = targetSide * 18

            if settings.silentAimMode == "Opponent Weak Side" then
                targetDistForward = math.clamp(oppDepth + 5, 30, 65)
                targetDistLateral = targetSide * 22
            elseif settings.silentAimMode == "Court Baseline" then
                targetDistForward = 70
                targetDistLateral = targetSide * 15
            end

            return myPos + (courtForward * targetDistForward) + (courtRight * targetDistLateral)
        end

        return myPos + (courtForward * 55) + (courtRight * 16)
    end

    -- ------------------------------------------------------------
    -- COMBAT & MOBILITY ACTION EXECUTORS
    -- ------------------------------------------------------------
    local lastSwingTime = 0
    local lastServeTime = 0
    local lastDashTime = 0
    local lastHinariTime = 0
    local lastBallPos = nil
    local lastBallTime = 0
    local ballVelocity = Vector3.zero
    local currentAimTarget = nil

    local function executeDash()
        local moveHandler = getMovementHandler()
        if moveHandler and type(moveHandler.Dash) == "function" then
            pcall(function() moveHandler:Dash() end)
        else
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
            task.delay(0.04, function()
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
            end)
        end
    end

    local function executeHinari()
        local now = os.clock()
        if (now - lastHinariTime) < settings.hinariCooldown then return end
        lastHinariTime = now

        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.One, false, game)
        task.delay(0.04, function()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.One, false, game)
        end)
    end

    local function triggerHit(ballPos, isSmash, isSet)
        local now = os.clock()
        if (now - lastSwingTime) < settings.cooldown then return end
        lastSwingTime = now

        local char = localPlayer.Character
        local root = getRoot(char)

        -- 1. Auto Hinari trigger right before contact
        if settings.autoHinari then
            executeHinari()
        end

        -- 2. Silent Aim Calculation & Replicator Override
        if settings.silentAim and root and ballPos then
            currentAimTarget = calculateSilentAimTarget(root.Position, ballPos)
            if currentAimTarget then
                local mr = getMouseReplicator()
                if mr then
                    pcall(function()
                        if type(mr.SetOverride) == "function" then
                            mr:SetOverride(currentAimTarget)
                        end
                        mr.CurrentMouseLocation = currentAimTarget
                    end)
                end
            end
        end

        -- 3. Smooth horizontal face ball (no camera snap / no screen twitch)
        if settings.autoFaceBall and ballPos and root then
            local flatBall = Vector3.new(ballPos.X, root.Position.Y, ballPos.Z)
            pcall(function()
                root.CFrame = CFrame.lookAt(root.Position, flatBall)
            end)
        end

        local vp = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local centerX = math.floor(vp.X / 2)
        local centerY = math.floor(vp.Y / 2)

        -- 4. Actuation
        if isSet then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.delay(0.04, function()
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end)
        else
            VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 0)
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
            task.delay(0.04, function()
                VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 0)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
            end)
        end
    end

    -- ------------------------------------------------------------
    -- USER INPUT: RIGHT CLICK BINDING FOR DASH
    -- ------------------------------------------------------------
    connect(UserInputService.InputBegan, function(input, gameProcessed)
        if gameProcessed then return end
        if settings.rightClickDash and input.UserInputType == Enum.UserInputType.MouseButton2 then
            if not UserInputService:GetFocusedTextBox() then
                executeDash()
            end
        end
    end)

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
                            triggerHit(nil, false, false)
                        end
                    end
                end)
            end
        end

        -- 3. Ball Tracking & Combat Automation
        local activeBall = findActiveBall()
        if activeBall and root and myPos and humanoid then
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
            local horizontalDist = (Vector2.new(ballPos.X, ballPos.Z) - Vector2.new(myPos.X, myPos.Z)).Magnitude
            local heightDiff = ballPos.Y - myPos.Y
            local toPlayer = (myPos - ballPos).Unit
            local isApproaching = not settings.approachFilter or (ballVelocity:Dot(toPlayer) > -5)

            -- AUTO DASH (Intercept ball if outside reach but incoming fast)
            if settings.autoDash and isApproaching and dist >= settings.dashMinDist and dist <= settings.dashMaxDist then
                if (now - lastDashTime) >= settings.dashCooldown then
                    lastDashTime = now
                    pcall(function()
                        root.CFrame = CFrame.lookAt(root.Position, Vector3.new(ballPos.X, root.Position.Y, ballPos.Z))
                    end)
                    executeDash()
                end
            end

            -- AUTO JUMP (Meet airborne high balls in time)
            if settings.autoJump and isApproaching and heightDiff >= settings.jumpHeightThreshold and horizontalDist <= (settings.hitRadius + 6) then
                if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
                    humanoid.Jump = true
                end
            end

            -- AUTO SMASH / AUTO SET / AUTO HIT DECISION
            local isSmashReady = settings.autoSmash and (heightDiff >= settings.smashMinHeight)
            local isSetReady = settings.autoSet and (settings.setMode == "Always" or (settings.setMode == "Low Ball Only" and heightDiff < 2.0))

            if settings.autoHit and dist <= settings.hitRadius and isApproaching then
                if isSmashReady then
                    if humanoid:GetState() ~= Enum.HumanoidStateType.Freefall and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping then
                        humanoid.Jump = true
                    end
                    triggerHit(ballPos, true, false)
                elseif isSetReady then
                    triggerHit(ballPos, false, true)
                else
                    triggerHit(ballPos, false, false)
                end
            end

            -- VISUALS: Ball ESP, Reach Zone, & Silent Aim Target
            if hasDrawing and (settings.ballEsp or settings.reachCircle or settings.silentAimVisual) then
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
                    local statusTag = isSmashReady and " [SMASH]" or (isSetReady and " [SET]" or "")

                    if ballDrawing.circle then
                        ballDrawing.circle.Position = Vector2.new(screenPos.X, screenPos.Y)
                        ballDrawing.circle.Color = isParryReady and Color3.fromRGB(255, 40, 70) or Color3.fromRGB(0, 255, 170)
                        ballDrawing.circle.Visible = true
                    end

                    if ballDrawing.text then
                        ballDrawing.text.Position = Vector2.new(screenPos.X, screenPos.Y - 22)
                        ballDrawing.text.Text = string.format("[ BALL: %.1fm | %d km/h%s ]", dist, speedKmH, statusTag)
                        ballDrawing.text.Color = isParryReady and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(255, 255, 255)
                        ballDrawing.text.Visible = true
                    end

                    if settings.ballTracer and ballDrawing.tracer then
                        ballDrawing.tracer.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
                        ballDrawing.tracer.To = Vector2.new(screenPos.X, screenPos.Y)
                        ballDrawing.tracer.Visible = true
                    elseif ballDrawing.tracer then
                        ballDrawing.tracer.Visible = false
                    end
                else
                    if ballDrawing.circle then ballDrawing.circle.Visible = false end
                    if ballDrawing.text then ballDrawing.text.Visible = false end
                    if ballDrawing.tracer then ballDrawing.tracer.Visible = false end
                end

                -- Silent Aim Target Visual
                if settings.silentAim and settings.silentAimVisual and currentAimTarget then
                    local aimScreen, aimOnScreen = camera:WorldToViewportPoint(currentAimTarget)
                    if aimOnScreen and ballDrawing.aimCircle and ballDrawing.aimTracer and ballDrawing.aimText then
                        ballDrawing.aimCircle.Position = Vector2.new(aimScreen.X, aimScreen.Y)
                        ballDrawing.aimCircle.Visible = true

                        ballDrawing.aimTracer.From = Vector2.new(screenPos.X, screenPos.Y)
                        ballDrawing.aimTracer.To = Vector2.new(aimScreen.X, aimScreen.Y)
                        ballDrawing.aimTracer.Visible = onScreen

                        ballDrawing.aimText.Position = Vector2.new(aimScreen.X, aimScreen.Y + 12)
                        ballDrawing.aimText.Text = "[ SILENT AIM TARGET ]"
                        ballDrawing.aimText.Visible = true
                    else
                        if ballDrawing.aimCircle then ballDrawing.aimCircle.Visible = false end
                        if ballDrawing.aimTracer then ballDrawing.aimTracer.Visible = false end
                        if ballDrawing.aimText then ballDrawing.aimText.Visible = false end
                    end
                else
                    if ballDrawing.aimCircle then ballDrawing.aimCircle.Visible = false end
                    if ballDrawing.aimTracer then ballDrawing.aimTracer.Visible = false end
                    if ballDrawing.aimText then ballDrawing.aimText.Visible = false end
                end
            end
        else
            hideDrawingSet(ballDrawing)
        end

        -- 4. Player ESP
        if hasDrawing and (settings.playerEsp or settings.showBoxes or settings.showTracers) then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer then
                    local pChar = player.Character
                    local pRoot = getRoot(pChar)
                    local pHum = getHumanoid(pChar)

                    if not espDrawings[player] then
                        espDrawings[player] = newPlayerDrawingSet()
                    end
                    local d = espDrawings[player]

                    if pChar and pRoot and pHum and pHum.Health > 0 then
                        local dist = (pRoot.Position - myPos).Magnitude
                        if dist <= settings.maxDistance then
                            local screenPos, onScreen = camera:WorldToViewportPoint(pRoot.Position)
                            if onScreen then
                                local headPos = pChar:FindFirstChild("Head") and pChar.Head.Position or (pRoot.Position + Vector3.new(0, 2, 0))
                                local headScreen = camera:WorldToViewportPoint(headPos + Vector3.new(0, 0.5, 0))
                                local legScreen = camera:WorldToViewportPoint(pRoot.Position - Vector3.new(0, 3, 0))

                                local boxHeight = math.abs(headScreen.Y - legScreen.Y)
                                local boxWidth = math.max(boxHeight * 0.55, 8)
                                local boxLeft = screenPos.X - (boxWidth / 2)
                                local boxTop = headScreen.Y

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

    CombatTab:CreateSection("Auto Hit & Parry")

    CombatTab:CreateToggle({
        Name = "Auto Hit (Auto Parry)",
        CurrentValue = settings.autoHit,
        Flag = "RR_AutoHit",
        Callback = function(value)
            settings.autoHit = value
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
        Range = {0.15, 0.8},
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
        CurrentValue = settings.autoFaceBall,
        Flag = "RR_AutoFace",
        Callback = function(value)
            settings.autoFaceBall = value
        end,
    })

    CombatTab:CreateSection("Smash & Jump System")

    CombatTab:CreateToggle({
        Name = "Auto Smash (Airborne Spike)",
        CurrentValue = settings.autoSmash,
        Flag = "RR_AutoSmash",
        Callback = function(value)
            settings.autoSmash = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Smash Min Height",
        Range = {2.5, 8.0},
        Increment = 0.5,
        Suffix = " studs",
        CurrentValue = settings.smashMinHeight,
        Flag = "RR_SmashHeight",
        Callback = function(value)
            settings.smashMinHeight = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Jump (High Ball Intercept)",
        CurrentValue = settings.autoJump,
        Flag = "RR_AutoJump",
        Callback = function(value)
            settings.autoJump = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Jump Height Threshold",
        Range = {3.5, 10.0},
        Increment = 0.5,
        Suffix = " studs",
        CurrentValue = settings.jumpHeightThreshold,
        Flag = "RR_JumpHeight",
        Callback = function(value)
            settings.jumpHeightThreshold = value
        end,
    })

    CombatTab:CreateSection("Set & Ability Automation")

    CombatTab:CreateToggle({
        Name = "Auto Set (Lob / E Key)",
        CurrentValue = settings.autoSet,
        Flag = "RR_AutoSet",
        Callback = function(value)
            settings.autoSet = value
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Set Trigger Condition",
        Options = {"Always", "Low Ball Only"},
        CurrentOption = {settings.setMode},
        MultipleOptions = false,
        Callback = function(option)
            settings.setMode = type(option) == "table" and option[1] or option
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Hinari (Overheat Ability 1)",
        CurrentValue = settings.autoHinari,
        Flag = "RR_AutoHinari",
        Callback = function(value)
            settings.autoHinari = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Hinari Ability Cooldown",
        Range = {1.5, 6.0},
        Increment = 0.5,
        Suffix = "s",
        CurrentValue = settings.hinariCooldown,
        Flag = "RR_HinariCD",
        Callback = function(value)
            settings.hinariCooldown = value
        end,
    })

    CombatTab:CreateSection("Silent Aim")

    CombatTab:CreateToggle({
        Name = "Silent Aim (Smart Court Deflection)",
        CurrentValue = settings.silentAim,
        Flag = "RR_SilentAim",
        Callback = function(value)
            settings.silentAim = value
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Silent Aim Placement",
        Options = {"Opponent Far Corner", "Opponent Weak Side", "Court Baseline"},
        CurrentOption = {settings.silentAimMode},
        MultipleOptions = false,
        Callback = function(option)
            settings.silentAimMode = type(option) == "table" and option[1] or option
        end,
    })

    local MoveTab = Window:CreateTab("Movement", "gauge")

    MoveTab:CreateSection("Dash System")

    MoveTab:CreateToggle({
        Name = "Right Click Binding for Dash",
        CurrentValue = settings.rightClickDash,
        Flag = "RR_RightClickDash",
        Callback = function(value)
            settings.rightClickDash = value
        end,
    })

    MoveTab:CreateToggle({
        Name = "Auto Dash (Intercept Distant Ball)",
        CurrentValue = settings.autoDash,
        Flag = "RR_AutoDash",
        Callback = function(value)
            settings.autoDash = value
        end,
    })

    MoveTab:CreateSlider({
        Name = "Auto Dash Min Distance",
        Range = {15, 35},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = settings.dashMinDist,
        Flag = "RR_DashMinDist",
        Callback = function(value)
            settings.dashMinDist = value
        end,
    })

    MoveTab:CreateSlider({
        Name = "Auto Dash Max Distance",
        Range = {36, 80},
        Increment = 2,
        Suffix = " studs",
        CurrentValue = settings.dashMaxDist,
        Flag = "RR_DashMaxDist",
        Callback = function(value)
            settings.dashMaxDist = value
        end,
    })

    MoveTab:CreateSlider({
        Name = "Auto Dash Cooldown",
        Range = {0.5, 3.0},
        Increment = 0.1,
        Suffix = "s",
        CurrentValue = settings.dashCooldown,
        Flag = "RR_DashCD",
        Callback = function(value)
            settings.dashCooldown = value
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

    local VisualTab = Window:CreateTab("Visuals", "eye")
    VisualTab:CreateSection("Ball & Aim Visuals")

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

    VisualTab:CreateToggle({
        Name = "Silent Aim Target Marker",
        CurrentValue = settings.silentAimVisual,
        Flag = "RR_SilentAimVisual",
        Callback = function(value)
            settings.silentAimVisual = value
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

    local AutomationTab = Window:CreateTab("Automation", "bot")
    AutomationTab:CreateSection("Match & Serve")

    AutomationTab:CreateToggle({
        Name = "Auto Serve (Instant Release)",
        CurrentValue = settings.autoServe,
        Flag = "RR_AutoServe",
        Callback = function(value)
            settings.autoServe = value
        end,
    })

    AutomationTab:CreateButton({
        Name = "Reset Ball Tracker State",
        Callback = function()
            lastBallPos = nil
            ballVelocity = Vector3.zero
            cachedLBallClass = nil
            currentAimTarget = nil
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

    if type(Window.SortTabs) == "function" then
        Window:SortTabs({"Overview", "Combat", "Movement", "Visuals", "Automation", "Settings"})
    end
end
