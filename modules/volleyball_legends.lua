-- ============================================================
--   RAVEN HUB  |  Volleyball Legends (Combat & Visuals)
--   Hitbox Expander, 3D Visualizer, Ball ESP & Landing Marker
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ReplicatedFirst = game:GetService("ReplicatedFirst")

    -- Clean up previous instance if running
    local environment = getgenv and getgenv() or _G
    if type(environment.__RAVEN_VOLLEYBALL_LEGENDS) == "table"
        and type(environment.__RAVEN_VOLLEYBALL_LEGENDS.Destroy) == "function" then
        pcall(environment.__RAVEN_VOLLEYBALL_LEGENDS.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = workspace.CurrentCamera

    local running = true
    local connections = {}
    local espObjects = {}

    -- Settings (ESP & Combat)
    local settings = {
        ballEsp = true,
        landingMarker = true,
        landingLabel = true,
        playerEsp = true,
        espDistance = true,
        markerColor = Color3.fromRGB(0, 255, 170),
        ballColor = Color3.fromRGB(255, 215, 0),
        playerColor = Color3.fromRGB(85, 170, 255),
        -- Hitbox Expander & Dimensions
        hitboxExpander = true,
        hitboxMultiplier = 1.0,
        hitboxWidthScale = 0.85,
        hitboxHeightScale = 1.0,
        hitboxDepthScale = 1.0,
        hitboxVisualizer = true,
        -- Cooldown & Auto-Hit
        noCooldown = true,
        autoHit = true,
        autoHitDistance = 35,
        autoHitMargin = 3.5,
        autoHitDebounce = 0.50,
        autoGroundMode = "Smart",
        autoSpike = true,
        autoDive = true,
        -- Power & Mobility
        alwaysMaxPower = true,
        customPowerValue = 1.0,
        superDive = true,
        diveSpeedMultiplier = 2.0,
        speedBoost = false,
        speedMultiplier = 1.3,
        -- Aerial & Recovery
        superJump = false,
        jumpMultiplier = 1.4,
        airDoubleJump = true,
        antiStun = true,
        bypassBackRank = true,
        -- Auto-Reposition & Assists
        autoReposition = false,
        autoRepositionDist = 28,
        autoFaceBall = false,
        courtOutCheck = true,
        repositionHumanized = true,
        repositionMargin = 2.5,
        -- Gacha & Misc
        instantSpinSkip = true,
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
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getHumanoid(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    -- Reference to Jump Validation to auto-unlock if game bugs
    local JumpValidation = nil
    local GameController = nil
    pcall(function()
        JumpValidation = require(ReplicatedFirst.Controllers.GameController.Actions.Move.Jump.Validation)
        GameController = require(ReplicatedFirst.Controllers.GameController)
    end)

    -- Ball Detection Helper & Game Physics
    local BallModule = nil
    local PhysicsModule = nil
    pcall(function()
        BallModule = require(ReplicatedFirst.Controllers.BallController.Ball)
    end)
    pcall(function()
        PhysicsModule = require(ReplicatedStorage.Common.Physics)
    end)

    -- Hitbox References & Management
    local HitboxTool = nil
    local GameConfig = nil
    local ClientHitbox = nil
    pcall(function()
        HitboxTool = require(ReplicatedStorage.Tools.Hitbox)
        GameConfig = require(ReplicatedStorage.Configuration.Game)
        ClientHitbox = require(ReplicatedFirst.Controllers.GameController.Actions.Move.DoMove.ClientHitbox)
    end)

    -- True Vanilla Base Sizes (hardcoded to prevent multiplier compounding)
    local TRUE_BASE_HITBOXES = {
        Set = Vector3.new(9, 8.905414581298828, 7.821842193603516),
        BumpServe = Vector3.new(9, 4.91381311416626, 7.803236961364746),
        JumpSet = Vector3.new(9, 8.905414581298828, 7.821842193603516),
        Bump = Vector3.new(9, 8.905414581298828, 7.803236961364746),
        Serve = Vector3.new(9, 7.90541410446167, 8.803236961364746),
        Dive = Vector3.new(7, 7, 10),
        Block = Vector3.new(6.5, 9.904999732971191, 6.052999973297119),
        Spike = Vector3.new(7.5, 8.904999732971191, 6.4710001945495605),
        SteelBlock = Vector3.new(7.5, 9.904999732971191, 6.052999973297119),
    }

    local function applyHitboxSettings()
        if GameConfig then
            GameConfig._DebugHitboxes = settings.hitboxVisualizer
        end

        local scale = settings.hitboxExpander and (settings.hitboxMultiplier or 1.0) or 1.0
        local wScale = settings.hitboxExpander and (settings.hitboxWidthScale or 1.0) or 1.0
        local hScale = settings.hitboxExpander and (settings.hitboxHeightScale or 1.0) or 1.0
        local dScale = settings.hitboxExpander and (settings.hitboxDepthScale or 1.0) or 1.0

        -- 1. Modify Asset Part templates in ReplicatedStorage
        pcall(function()
            local assemblies = ReplicatedStorage.Assets.HitboxesNew.Default.Assemblies
            for name, baseSize in pairs(TRUE_BASE_HITBOXES) do
                local folder = assemblies:FindFirstChild(name)
                if folder then
                    local part = folder:FindFirstChild("Part")
                    if part and part:IsA("BasePart") then
                        part.Size = Vector3.new(
                            baseSize.X * scale * wScale,
                            baseSize.Y * scale * hScale,
                            baseSize.Z * scale * dScale
                        )
                    end
                end
            end
        end)

        -- 2. Modify cached data in HitboxTool
        if HitboxTool then
            for moveName, baseSize in pairs(TRUE_BASE_HITBOXES) do
                local ok, hitboxData = pcall(function()
                    return HitboxTool.get({ MoveId = moveName })
                end)
                if ok and hitboxData then
                    hitboxData.Size = Vector3.new(
                        baseSize.X * scale * wScale,
                        baseSize.Y * scale * hScale,
                        baseSize.Z * scale * dScale
                    )
                end
            end
        end

        -- 3. Flush ClientHitbox cached instance
        if ClientHitbox and ClientHitbox._cachedHitbox then
            ClientHitbox._cachedHitbox = nil
        end
    end

    -- Automation & Controller References
    local Orchestrator = nil
    local InputController = nil
    local DoMoveBinding = nil
    pcall(function()
        local Knit = require(ReplicatedStorage.Packages.Knit)
        InputController = Knit.GetController("InputController")
        Orchestrator = require(ReplicatedFirst.Controllers.GameController.Actions.Move.DoMove.Orchestrator)
        DoMoveBinding = require(ReplicatedFirst.Controllers.GameController.Actions.Binding.Registry.DoMove)
    end)

    local vim = game:GetService("VirtualInputManager")
    local function triggerMove(actionName, isAerial)
        -- 1. Primary & safest: Native VirtualInputManager (runs in engine input thread, eliminates RobloxScript require errors)
        if vim then
            local binds = InputController and InputController.Keybinds and InputController.Keybinds[actionName]
            local targetKeyCode = nil
            local isMouse = false

            if binds then
                for _, b in ipairs(binds) do
                    if typeof(b) == "EnumItem" then
                        if b.EnumType == Enum.KeyCode then
                            targetKeyCode = b
                            break
                        elseif b == Enum.UserInputType.MouseButton1 then
                            isMouse = true
                            break
                        end
                    end
                end
            end

            -- Default fallbacks if keybinds not detected
            if not targetKeyCode and not isMouse then
                if actionName == "Set" then
                    targetKeyCode = Enum.KeyCode.Q
                elseif actionName == "Dive" then
                    targetKeyCode = Enum.KeyCode.LeftControl
                elseif actionName == "Spike" or actionName == "Bump" then
                    isMouse = true
                end
            end

            if isMouse then
                local vp = camera and camera.ViewportSize or Vector2.new(800, 600)
                vim:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, true, game, 0)
                task.delay(0.05, function()
                    pcall(function() vim:SendMouseButtonEvent(vp.X / 2, vp.Y / 2, 0, false, game, 0) end)
                end)
                return true
            elseif targetKeyCode then
                vim:SendKeyEvent(true, targetKeyCode, false, game)
                task.delay(0.05, function()
                    pcall(function() vim:SendKeyEvent(false, targetKeyCode, false, game) end)
                end)
                return true
            end
        end

        -- 2. Fallback: UI Button activation via firesignal
        local pgui = localPlayer:FindFirstChild("PlayerGui")
        local actionsBar = pgui and pgui:FindFirstChild("Interface")
            and pgui.Interface:FindFirstChild("Game")
            and pgui.Interface.Game:FindFirstChild("InGameActionsBar")
            and pgui.Interface.Game.InGameActionsBar:FindFirstChild("Actions")
        local btn = actionsBar and actionsBar:FindFirstChild(actionName)
        if btn and btn:IsA("GuiButton") and type(firesignal) == "function" then
            firesignal(btn.Activated)
            return true
        end

        -- 3. Last-resort fallback: Direct method call with identity 2
        local ok = false
        local oldId = getthreadidentity and getthreadidentity()
        if setthreadidentity then setthreadidentity(2) end
        if InputController and type(InputController.PerformAction) == "function" then
            ok = pcall(function() InputController:PerformAction(actionName) end)
        end
        if not ok and DoMoveBinding and type(DoMoveBinding.onMoveRequest) == "function" then
            ok = pcall(function()
                DoMoveBinding.onMoveRequest({
                    ActionName = actionName,
                    InputState = Enum.UserInputState.Begin,
                    IsAerial = isAerial or false
                })
            end)
        end
        if setthreadidentity and oldId then setthreadidentity(oldId) end
        return ok
    end

    local originalIsOnCooldown = nil
    local originalApplyCooldown = nil
    if Orchestrator then
        originalIsOnCooldown = Orchestrator.isOnCooldown
        originalApplyCooldown = Orchestrator._applyCooldown
    end

    local function applyCooldownSettings()
        if not Orchestrator then return end
        if settings.noCooldown then
            Orchestrator.isOnCooldown = function() return false end
            Orchestrator._applyCooldown = function() Orchestrator._cooldownExpiryTime = 0 end
            Orchestrator._cooldownExpiryTime = 0
            if Orchestrator.clearBusyState then
                pcall(Orchestrator.clearBusyState)
            end
        else
            if originalIsOnCooldown then Orchestrator.isOnCooldown = originalIsOnCooldown end
            if originalApplyCooldown then Orchestrator._applyCooldown = originalApplyCooldown end
        end
    end

    -- Power & Impact References
    local DoMoveGame = nil
    pcall(function()
        DoMoveGame = require(ReplicatedFirst.Controllers.GameController.Actions.Move.DoMove.Game)
    end)

    local originalGetPowerAndReset = nil
    if DoMoveGame then
        originalGetPowerAndReset = DoMoveGame.getPowerAndReset
    end

    local originalPlayerAttributes = {
        Multiplier_DiveSpeed = localPlayer:GetAttribute("Multiplier_DiveSpeed"),
        Multiplier_Speed = localPlayer:GetAttribute("Multiplier_Speed"),
    }

    local function applyPowerSettings()
        if not DoMoveGame then return end
        if settings.alwaysMaxPower then
            DoMoveGame.getPowerAndReset = function(...)
                return settings.customPowerValue or 1.0
            end
        else
            if originalGetPowerAndReset then
                DoMoveGame.getPowerAndReset = originalGetPowerAndReset
            end
        end
    end

    local function applyMobilitySettings()
        if not localPlayer then return end
        if settings.superDive then
            local base = originalPlayerAttributes.Multiplier_DiveSpeed or 1.4
            localPlayer:SetAttribute("Multiplier_DiveSpeed", base * settings.diveSpeedMultiplier)
        else
            if originalPlayerAttributes.Multiplier_DiveSpeed then
                localPlayer:SetAttribute("Multiplier_DiveSpeed", originalPlayerAttributes.Multiplier_DiveSpeed)
            end
        end

        if settings.speedBoost then
            local base = originalPlayerAttributes.Multiplier_Speed or 1.1
            localPlayer:SetAttribute("Multiplier_Speed", base * settings.speedMultiplier)
        else
            if originalPlayerAttributes.Multiplier_Speed then
                localPlayer:SetAttribute("Multiplier_Speed", originalPlayerAttributes.Multiplier_Speed)
            end
        end
    end

    -- Aerial & Recovery References
    local JumpValidation = nil
    local JumpPhysics = nil
    local GameControllerMod = nil
    pcall(function()
        JumpValidation = require(ReplicatedFirst.Controllers.GameController.Actions.Move.Jump.Validation)
    end)
    pcall(function()
        JumpPhysics = require(ReplicatedFirst.Controllers.GameController.Actions.Move.Jump.Physics)
    end)
    pcall(function()
        GameControllerMod = require(ReplicatedFirst.Controllers.GameController)
    end)

    local originalLaunchSpeed = JumpPhysics and JumpPhysics.LaunchSpeed or 30
    local originalCanDoubleJump = JumpValidation and JumpValidation.canDoubleJump or nil
    local originalIsBackRank = JumpValidation and JumpValidation._isBackRank or nil
    local originalIsStunnedGet = (GameControllerMod and GameControllerMod.IsStunned) and GameControllerMod.IsStunned.get or nil

    local function applyAerialSettings()
        if JumpPhysics then
            if settings.superJump then
                JumpPhysics.LaunchSpeed = originalLaunchSpeed * (settings.jumpMultiplier or 1.0)
            else
                JumpPhysics.LaunchSpeed = originalLaunchSpeed
            end
        end

        if JumpValidation then
            if settings.airDoubleJump then
                JumpValidation.canDoubleJump = function(...)
                    return true
                end
            else
                if originalCanDoubleJump then
                    JumpValidation.canDoubleJump = originalCanDoubleJump
                end
            end

            if settings.bypassBackRank then
                JumpValidation._isBackRank = function(...)
                    return false
                end
            else
                if originalIsBackRank then
                    JumpValidation._isBackRank = originalIsBackRank
                end
            end
        end

        if GameControllerMod and GameControllerMod.IsStunned then
            if settings.antiStun then
                GameControllerMod.IsStunned.get = function(...)
                    return false
                end
            else
                if originalIsStunnedGet then
                    GameControllerMod.IsStunned.get = originalIsStunnedGet
                end
            end
        end
    end

    -- Gacha & Spin Skip References
    local AbilityController = nil
    local StyleController = nil
    pcall(function()
        AbilityController = require(ReplicatedFirst.Controllers.AbilityController)
    end)
    pcall(function()
        StyleController = require(ReplicatedFirst.Controllers.StyleController)
    end)

    local origAbilityCanSkip = AbilityController and AbilityController.CanSkip and AbilityController.CanSkip.get or nil
    local origStyleCanSkip = StyleController and StyleController.CanSkip and StyleController.CanSkip.get or nil

    local function applyGachaSettings()
        if settings.instantSpinSkip then
            if AbilityController and AbilityController.CanSkip then
                AbilityController.CanSkip.get = function(...) return true end
            end
            if StyleController and StyleController.CanSkip then
                StyleController.CanSkip.get = function(...) return true end
            end
        else
            if AbilityController and AbilityController.CanSkip and origAbilityCanSkip then
                AbilityController.CanSkip.get = origAbilityCanSkip
            end
            if StyleController and StyleController.CanSkip and origStyleCanSkip then
                StyleController.CanSkip.get = origStyleCanSkip
            end
        end
    end

    -- Court Boundary Detection
    local cachedCourt = nil
    local function getCourtPart()
        if cachedCourt and cachedCourt.Parent then return cachedCourt end
        local map = workspace:FindFirstChild("Map")
        local c = map and map:FindFirstChild("Court")
        if c and c:IsA("BasePart") then
            cachedCourt = c
            return c
        end
        return nil
    end

    local function isInsideCourt(worldPos, margin)
        local court = getCourtPart()
        if not court then return true end -- fallback if court not found
        margin = margin or 0
        local rel = court.CFrame:PointToObjectSpace(worldPos)
        local halfX = (court.Size.X / 2) + margin
        local halfZ = (court.Size.Z / 2) + margin
        return math.abs(rel.X) <= halfX and math.abs(rel.Z) <= halfZ
    end

    -- Accurate Floor Height Function
    local function getFloorY(pos)
        if PhysicsModule and type(PhysicsModule.calculateFloorHeight) == "function" then
            local f = PhysicsModule.calculateFloorHeight(pos)
            if f then return f end
        end
        return -23.658
    end

    -- Landing Calculation
    local function getPredictedLanding(pos, vel, floorY)
        local g = workspace.Gravity > 0 and workspace.Gravity or 43
        local a = -0.5 * g
        local b = vel.Y
        local c = pos.Y - floorY

        if math.abs(b) < 0.001 and c <= 0.8 then
            return pos, 0
        end

        local discriminant = b * b - 4 * a * c
        if discriminant < 0 then
            return pos, 0
        end

        local sqrtD = math.sqrt(discriminant)
        local t1 = (-b - sqrtD) / (2 * a)
        local t2 = (-b + sqrtD) / (2 * a)

        local t = math.max(t1, t2)
        if t <= 0 then
            if c > 0 then
                t = math.sqrt((2 * c) / g)
            else
                t = 0
            end
        end

        local landingPos = Vector3.new(
            pos.X + vel.X * t,
            floorY,
            pos.Z + vel.Z * t
        )
        return landingPos, t
    end

    local function getActiveBall()
        if BallModule and BallModule.All then
            for _, ballObj in pairs(BallModule.All) do
                local ballPart = ballObj.Ball and (ballObj.Ball.PrimaryPart or ballObj.Ball:FindFirstChildWhichIsA("BasePart"))
                if ballPart and ballPart.Parent then
                    return ballObj, ballPart
                end
            end
        end

        -- Fallback: Look for CLIENT_BALL_ in workspace
        for _, child in ipairs(workspace:GetChildren()) do
            if string.sub(child.Name, 1, 12) == "CLIENT_BALL_" then
                local bPart = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
                if bPart then
                    return nil, bPart
                end
            end
        end

        return nil, nil
    end

    local function getMoveHitbox(moveName)
        if HitboxTool then
            local ok, data = pcall(function() return HitboxTool.get({ MoveId = moveName }) end)
            if ok and data and data.Size then
                return data.Size, (data.Offset or CFrame.identity)
            end
        end
        local assemblies = ReplicatedStorage:FindFirstChild("Assets")
            and ReplicatedStorage.Assets:FindFirstChild("HitboxesNew")
            and ReplicatedStorage.Assets.HitboxesNew.Default.Assemblies
        local folder = assemblies and assemblies:FindFirstChild(moveName)
        local part = folder and folder:FindFirstChild("Part")
        if part and part:IsA("BasePart") then
            return part.Size, part.CFrame
        end

        local base = TRUE_BASE_HITBOXES[moveName] or Vector3.new(8, 8, 8)
        local scale = settings.hitboxExpander and (settings.hitboxMultiplier or 1.0) or 1.0
        local wScale = settings.hitboxExpander and (settings.hitboxWidthScale or 1.0) or 1.0
        local hScale = settings.hitboxExpander and (settings.hitboxHeightScale or 1.0) or 1.0
        local dScale = settings.hitboxExpander and (settings.hitboxDepthScale or 1.0) or 1.0
        return Vector3.new(base.X * scale * wScale, base.Y * scale * hScale, base.Z * scale * dScale), CFrame.identity
    end

    local lastAutoHit = 0
    local function handleAutoHit(ballPart, ballVel, myRoot, myHum)
        pcall(function()
            if not settings.autoHit or not ballPart or not myHum or myHum.Health <= 0 or not myRoot then return end

            local now = os.clock()
            local debounceTime = settings.autoHitDebounce or 0.50
            if (now - lastAutoHit) < debounceTime then return end

            local ballPos = ballPart.Position
            local delta = ballPos - myRoot.Position
            local dist = delta.Magnitude

            -- Upper cap search distance
            if dist > (settings.autoHitDistance or 35) then return end

            -- If ball was already struck and is moving away from player at speed, ignore it
            local vel = ballVel or Vector3.zero
            local isMovingAway = vel.Magnitude > 4.0 and (delta:Dot(vel) > 0)
            if isMovingAway and dist > 3.5 then return end

            local isAerial = (myHum.FloorMaterial == Enum.Material.Air)
            local targetMove = nil

            if isAerial and settings.autoSpike then
                targetMove = "Spike"
            elseif not isAerial then
                local floorY = getFloorY(ballPos)
                local ballHeight = ballPos.Y - floorY
                if settings.autoDive and ballHeight < 4.5 and dist > 5.5 then
                    targetMove = "Dive"
                elseif settings.autoGroundMode == "Set" then
                    targetMove = "Set"
                elseif settings.autoGroundMode == "Bump" then
                    targetMove = "Bump"
                else -- "Smart"
                    local myHeight = myRoot.Position.Y
                    if ballPos.Y >= (myHeight + 0.5) then
                        targetMove = "Set"
                    else
                        targetMove = "Bump"
                    end
                end
            end

            if not targetMove then return end

            -- Dynamic Hitbox Checking: Calculate distance from ball to actual Hitbox boundary
            local hbSize, hbOffset = getMoveHitbox(targetMove)
            local hbCFrame = myRoot.CFrame * hbOffset
            local relPos = hbCFrame:PointToObjectSpace(ballPos)

            local halfX = hbSize.X * 0.5
            local halfY = hbSize.Y * 0.5
            local halfZ = hbSize.Z * 0.5

            local margin = settings.autoHitMargin or 3.5
            local dx = math.max(0, math.abs(relPos.X) - halfX)
            local dy = math.max(0, math.abs(relPos.Y) - halfY)
            local dz = math.max(0, math.abs(relPos.Z) - halfZ)
            local distToHitbox = math.sqrt(dx * dx + dy * dy + dz * dz)

            -- Forward prediction for high-speed balls (100ms window)
            local nextBallPos = ballPos + vel * 0.10
            local nextRelPos = hbCFrame:PointToObjectSpace(nextBallPos)
            local ndx = math.max(0, math.abs(nextRelPos.X) - halfX)
            local ndy = math.max(0, math.abs(nextRelPos.Y) - halfY)
            local ndz = math.max(0, math.abs(nextRelPos.Z) - halfZ)
            local nextDistToHitbox = math.sqrt(ndx * ndx + ndy * ndy + ndz * ndz)

            -- Hit only if ball is contacting/inside hitbox bounds or about to enter
            if distToHitbox <= margin or nextDistToHitbox <= margin then
                lastAutoHit = now
                triggerMove(targetMove, isAerial)
            end
        end)
    end

    -- Visual Landing Elements (Cylinder + AlwaysOnTop BillboardGui)
    local landingCylinder = Instance.new("Part")
    landingCylinder.Name = "Raven_LandingMarker"
    landingCylinder.Shape = Enum.PartType.Cylinder
    landingCylinder.Size = Vector3.new(0.4, 7, 7)
    landingCylinder.CFrame = CFrame.new(0, -500, 0) * CFrame.Angles(0, 0, math.rad(90))
    landingCylinder.Anchored = true
    landingCylinder.CanCollide = false
    landingCylinder.CanTouch = false
    landingCylinder.CanQuery = false
    landingCylinder.Material = Enum.Material.Neon
    landingCylinder.Color = settings.markerColor
    landingCylinder.Transparency = 1
    landingCylinder.Parent = workspace

    -- Target Billboard on Landing spot with AlwaysOnTop
    local landingBb = Instance.new("BillboardGui")
    landingBb.Name = "Raven_LandingIndicator"
    landingBb.Adornee = landingCylinder
    landingBb.Size = UDim2.new(0, 160, 0, 48)
    landingBb.StudsOffset = Vector3.new(0, 1.5, 0)
    landingBb.AlwaysOnTop = true
    landingBb.Enabled = true

    local landingText = Instance.new("TextLabel")
    landingText.BackgroundTransparency = 1
    landingText.Size = UDim2.new(1, 0, 1, 0)
    landingText.Font = Enum.Font.GothamBold
    landingText.TextSize = 13
    landingText.TextColor3 = settings.markerColor
    landingText.TextStrokeTransparency = 0.2
    landingText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    landingText.RichText = true
    landingText.Text = "🎯 <b>Landing Spot</b>"
    landingText.Parent = landingBb
    landingBb.Parent = landingCylinder

    -- ESP Helpers
    local function createBillboard(id, adornee, color, title, offset)
        local bb = Instance.new("BillboardGui")
        bb.Name = "RavenESP_" .. tostring(id)
        bb.Adornee = adornee
        bb.Size = UDim2.new(0, 180, 0, 48)
        bb.StudsOffset = offset or Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true

        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.Size = UDim2.new(1, 0, 1, 0)
        text.Font = Enum.Font.GothamBold
        text.TextSize = 13
        text.TextColor3 = color or Color3.fromRGB(255, 255, 255)
        text.TextStrokeTransparency = 0.2
        text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        text.RichText = true
        text.Text = title or ""
        text.Parent = bb

        bb.Parent = adornee
        return bb, text
    end

    local function createHighlight(adornee, fillColor, outlineColor)
        local hl = Instance.new("Highlight")
        hl.Name = "RavenHighlight"
        hl.Adornee = adornee
        hl.FillColor = fillColor or Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.55
        hl.OutlineColor = outlineColor or Color3.fromRGB(255, 255, 255)
        hl.OutlineTransparency = 0.2
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = adornee
        return hl
    end

    local function clearEspEntry(id)
        if espObjects[id] then
            if espObjects[id].billboard then pcall(function() espObjects[id].billboard:Destroy() end) end
            if espObjects[id].highlight then pcall(function() espObjects[id].highlight:Destroy() end) end
            espObjects[id] = nil
        end
    end

    -- Watchdog to guarantee jump and input never lock
    local lastWatchdog = 0

    -- ============================================================
    --   RENDER LOOP (Visuals Only)
    -- ============================================================
    connect(RunService.RenderStepped, function()
        if not running then return end

        local myChar = localPlayer.Character
        local myRoot = getRoot(myChar)
        local myHum = getHumanoid(myChar)
        local myPos = myRoot and myRoot.Position or Vector3.zero

        -- Ground watchdog: if player is safely on ground, ensure jump cooldown lock (_Key) doesn't stay stuck
        local now = os.clock()
        if (now - lastWatchdog) > 0.5 then
            lastWatchdog = now
            if myHum and myHum.FloorMaterial ~= Enum.Material.Air then
                if JumpValidation and JumpValidation._Key and (now - JumpValidation._Key) > 1.2 then
                    JumpValidation._Key = nil
                end
                if GameController and GameController.IsBusy and GameController.IsBusy:get() == true then
                    pcall(function() GameController.IsBusy:set(false) end)
                end
            end
        end

        -- Cooldown & State Maintenance
        if settings.noCooldown and Orchestrator then
            Orchestrator._cooldownExpiryTime = 0
            if Orchestrator.clearBusyState then
                pcall(Orchestrator.clearBusyState)
            end
        end

        local ballObj, ballPart = getActiveBall()

        -- 1. Ball Tracking & Predictions
        local ballPos = ballPart and ballPart.Position
        local ballVel = ballPart and ((ballObj and ballObj.Velocity) or ballPart.AssemblyLinearVelocity or Vector3.zero) or Vector3.zero
        local floorY = ballPos and getFloorY(ballPos) or -23.658
        local landingPos, t = nil, 0
        if ballPos then
            landingPos, t = getPredictedLanding(ballPos, ballVel, floorY)
        end
        local isLandingInCourt = true
        if landingPos and settings.courtOutCheck then
            isLandingInCourt = isInsideCourt(landingPos, settings.repositionMargin or 2.5)
        end

        -- Smart Auto-Hit / Reaction (Checks Hitbox Bounds Directly)
        if ballPart and myHum and myRoot then
            handleAutoHit(ballPart, ballVel, myRoot, myHum)
        end

        if settings.ballEsp and ballPart then
            local dist = math.floor((ballPart.Position - myPos).Magnitude)
            local id = "Ball_Main"
            local speed = math.floor(ballVel.Magnitude)

            local statusTag = ""
            if settings.courtOutCheck and t and t > 0.1 then
                if isLandingInCourt then
                    statusTag = " <font color='#00FF88'>[IN]</font>"
                else
                    statusTag = " <font color='#FF4444'>[OUT]</font>"
                end
            end

            if not espObjects[id] then
                local bb, lbl = createBillboard(id, ballPart, settings.ballColor, "🏐 Ball", Vector3.new(0, 2.5, 0))
                local hl = createHighlight(ballPart, settings.ballColor, Color3.fromRGB(255, 255, 255))
                espObjects[id] = { billboard = bb, label = lbl, highlight = hl }
            else
                espObjects[id].label.Text = string.format("🏐 <b>Ball</b>%s\n<font size='11' color='#FFFFFF'>[%d studs | %d spd]</font>", statusTag, dist, speed)
            end
        else
            clearEspEntry("Ball_Main")
        end

        -- 2. Landing Prediction Marker
        if settings.landingMarker and ballPart and landingCylinder and landingPos then
            -- Keep landing floor accurate at target point
            local targetFloorY = getFloorY(landingPos)
            local distToTarget = math.floor((landingPos - myPos).Magnitude)

            if t and t > 0.03 and t < 6.0 and (ballPos.Y - targetFloorY) > 1.0 then
                landingCylinder.CFrame = CFrame.new(landingPos.X, targetFloorY + 0.25, landingPos.Z) * CFrame.Angles(0, 0, math.rad(90))
                landingCylinder.Transparency = isLandingInCourt and 0.3 or 0.65
                landingCylinder.Color = isLandingInCourt and settings.markerColor or Color3.fromRGB(255, 60, 60)

                if settings.landingLabel then
                    landingBb.Enabled = true
                    if isLandingInCourt then
                        landingText.Text = string.format("🎯 <b>Landing Spot</b> <font color='#00FFAA'>[IN]</font>\n<font size='11' color='#00FFAA'>[%.2fs | %d studs]</font>", t, distToTarget)
                    else
                        landingText.Text = string.format("🚫 <b>OUT OF BOUNDS</b> <font color='#FF4444'>[OUT]</font>\n<font size='11' color='#FF8888'>[%.2fs | %d studs]</font>", t, distToTarget)
                    end
                else
                    landingBb.Enabled = false
                end

                -- Auto-Reposition & Auto-Face Assist
                if myHum and myHum.Health > 0 and myRoot then
                    local delta = Vector3.new(landingPos.X - myPos.X, 0, landingPos.Z - myPos.Z)
                    local hDist = delta.Magnitude

                    -- Only reposition if ball is landing IN COURT (or court check disabled)
                    local shouldTrack = settings.autoReposition
                    if settings.courtOutCheck and not isLandingInCourt then
                        shouldTrack = false
                    end

                    if shouldTrack and hDist > 2.0 and hDist <= settings.autoRepositionDist then
                        if myHum.FloorMaterial ~= Enum.Material.Air then
                            if settings.repositionHumanized then
                                -- Humanized speed scaling: sprint when far, decelerate smoothly when nearing landing spot
                                local moveDir = delta.Unit
                                if hDist < 6.0 then
                                    local approachFactor = math.clamp(hDist / 6.0, 0.45, 1.0)
                                    myHum:Move(moveDir * approachFactor, false)
                                else
                                    myHum:Move(moveDir, false)
                                end
                            else
                                myHum:Move(delta.Unit, false)
                            end
                        end
                    end

                    if settings.autoFaceBall and hDist <= 32 then
                        local lookTarget = Vector3.new(ballPos.X, myRoot.Position.Y, ballPos.Z)
                        if (lookTarget - myRoot.Position).Magnitude > 0.5 then
                            local targetCF = CFrame.lookAt(myRoot.Position, lookTarget)
                            -- Humanized smooth turn rate (0.16)
                            myRoot.CFrame = myRoot.CFrame:Lerp(targetCF, 0.16)
                        end
                    end
                end
            else
                landingCylinder.CFrame = CFrame.new(0, -500, 0) * CFrame.Angles(0, 0, math.rad(90))
                landingCylinder.Transparency = 1
                landingBb.Enabled = false
            end
        elseif landingCylinder then
            landingCylinder.CFrame = CFrame.new(0, -500, 0) * CFrame.Angles(0, 0, math.rad(90))
            landingCylinder.Transparency = 1
            if landingBb then landingBb.Enabled = false end
        end

        -- 3. Player ESP
        if settings.playerEsp then
            local validIds = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= localPlayer and p.Character then
                    local pChar = p.Character
                    local pRoot = getRoot(pChar)
                    local pHum = getHumanoid(pChar)
                    if pRoot and pHum and pHum.Health > 0 then
                        local pId = "Player_" .. p.Name
                        validIds[pId] = true
                        local pDist = math.floor((pRoot.Position - myPos).Magnitude)

                        if not espObjects[pId] then
                            local bb, lbl = createBillboard(pId, pRoot, settings.playerColor, p.DisplayName, Vector3.new(0, 3.2, 0))
                            local hl = createHighlight(pChar, settings.playerColor, Color3.fromRGB(255, 255, 255))
                            espObjects[pId] = { billboard = bb, label = lbl, highlight = hl }
                        else
                            local infoText = "<b>" .. p.DisplayName .. "</b>"
                            if settings.espDistance then
                                infoText = infoText .. string.format("\n<font size='10' color='#CCCCCC'>[%d studs]</font>", pDist)
                            end
                            espObjects[pId].label.Text = infoText
                        end
                    end
                end
            end

            for id, _ in pairs(espObjects) do
                if string.sub(id, 1, 7) == "Player_" and not validIds[id] then
                    clearEspEntry(id)
                end
            end
        else
            for id, _ in pairs(espObjects) do
                if string.sub(id, 1, 7) == "Player_" then
                    clearEspEntry(id)
                end
            end
        end
    end)

    -- ============================================================
    --   UI (MacLib Tabs)
    -- ============================================================
    local VisualsTab = Window:CreateTab("Visuals & ESP", 4483362458)
    VisualsTab:CreateSection("Ball ESP")

    VisualsTab:CreateToggle({
        Name = "Ball ESP & Velocity",
        CurrentValue = settings.ballEsp,
        Flag = "VB_BallEsp_v4",
        Callback = function(value)
            settings.ballEsp = value
            if not value then clearEspEntry("Ball_Main") end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Landing Prediction Marker",
        CurrentValue = settings.landingMarker,
        Flag = "VB_LandingMarker_v4",
        Callback = function(value)
            settings.landingMarker = value
            if not value and landingCylinder then
                landingCylinder.CFrame = CFrame.new(0, -500, 0)
                if landingBb then landingBb.Enabled = false end
            end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Landing Spot Timer & Distance",
        CurrentValue = settings.landingLabel,
        Flag = "VB_LandingLabel_v4",
        Callback = function(value)
            settings.landingLabel = value
        end,
    })

    VisualsTab:CreateSection("Player ESP")

    VisualsTab:CreateToggle({
        Name = "Player ESP & Highlight",
        CurrentValue = settings.playerEsp,
        Flag = "VB_PlayerEsp_v4",
        Callback = function(value)
            settings.playerEsp = value
            if not value then
                for id, _ in pairs(espObjects) do
                    if string.sub(id, 1, 7) == "Player_" then clearEspEntry(id) end
                end
            end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = settings.espDistance,
        Flag = "VB_EspDistance_v4",
        Callback = function(value)
            settings.espDistance = value
        end,
    })

    -- ============================================================
    --   UI: Combat & Hitbox Tab
    -- ============================================================
    local CombatTab = Window:CreateTab("Combat & Hitbox", 4483362458)
    CombatTab:CreateSection("Hitbox Expansion")

    CombatTab:CreateToggle({
        Name = "Hitbox Expander",
        CurrentValue = settings.hitboxExpander,
        Flag = "VB_HitboxExpander_v4",
        Callback = function(value)
            settings.hitboxExpander = value
            applyHitboxSettings()
        end,
    })

    CombatTab:CreateSlider({
        Name = "Overall Scale (ขนาดรวม)",
        Range = {0.3, 3.0},
        Increment = 0.05,
        Suffix = "x",
        CurrentValue = settings.hitboxMultiplier,
        Flag = "VB_HitboxMultiplier_v4",
        Callback = function(value)
            settings.hitboxMultiplier = value
            if settings.hitboxExpander then
                applyHitboxSettings()
            end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Width Scale (ความกว้าง ซ้าย-ขวา)",
        Range = {0.3, 2.5},
        Increment = 0.05,
        Suffix = "x",
        CurrentValue = settings.hitboxWidthScale,
        Flag = "VB_HitboxWidth_v4",
        Callback = function(value)
            settings.hitboxWidthScale = value
            if settings.hitboxExpander then
                applyHitboxSettings()
            end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Height Scale (ความสูง แนวดิ่ง)",
        Range = {0.5, 2.5},
        Increment = 0.05,
        Suffix = "x",
        CurrentValue = settings.hitboxHeightScale,
        Flag = "VB_HitboxHeight_v4",
        Callback = function(value)
            settings.hitboxHeightScale = value
            if settings.hitboxExpander then
                applyHitboxSettings()
            end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Forward Reach (ระยะเอื้อม หน้า-หลัง)",
        Range = {0.5, 2.5},
        Increment = 0.05,
        Suffix = "x",
        CurrentValue = settings.hitboxDepthScale,
        Flag = "VB_HitboxDepth_v4",
        Callback = function(value)
            settings.hitboxDepthScale = value
            if settings.hitboxExpander then
                applyHitboxSettings()
            end
        end,
    })

    CombatTab:CreateToggle({
        Name = "Show 3D Hitbox Visualizer",
        CurrentValue = settings.hitboxVisualizer,
        Flag = "VB_HitboxVisualizer_v4",
        Callback = function(value)
            settings.hitboxVisualizer = value
            if GameConfig then
                GameConfig._DebugHitboxes = value
            end
        end,
    })

    CombatTab:CreateSection("Cooldown Bypass")

    CombatTab:CreateToggle({
        Name = "No Move Cooldown (Instant Spam)",
        CurrentValue = settings.noCooldown,
        Flag = "VB_NoCooldown_v4",
        Callback = function(value)
            settings.noCooldown = value
            applyCooldownSettings()
        end,
    })

    CombatTab:CreateSection("Smart Auto-Hit (Auto Reaction)")

    CombatTab:CreateToggle({
        Name = "Auto-Hit / Reaction",
        CurrentValue = settings.autoHit,
        Flag = "VB_AutoHit_v4",
        Callback = function(value)
            settings.autoHit = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Hitbox Trigger Reach (Margin)",
        Range = {0, 8},
        Increment = 0.5,
        Suffix = " studs",
        CurrentValue = settings.autoHitMargin,
        Flag = "VB_AutoHitMargin_v4",
        Callback = function(value)
            settings.autoHitMargin = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Max Search Distance",
        Range = {10, 60},
        Increment = 2,
        Suffix = " studs",
        CurrentValue = settings.autoHitDistance,
        Flag = "VB_AutoHitDist_v4",
        Callback = function(value)
            settings.autoHitDistance = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Spike (In Air)",
        CurrentValue = settings.autoSpike,
        Flag = "VB_AutoSpike_v4",
        Callback = function(value)
            settings.autoSpike = value
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Ground Receive Mode",
        Options = {"Smart (Auto Set/Bump)", "Set Only (Q)", "Bump Only (LeftClick)"},
        CurrentOption = { settings.autoGroundMode == "Set" and "Set Only (Q)" or (settings.autoGroundMode == "Bump" and "Bump Only (LeftClick)" or "Smart (Auto Set/Bump)") },
        Flag = "VB_AutoGroundMode_v4",
        Callback = function(value)
            local opt = type(value) == "table" and value[1] or value
            if string.find(opt, "Set Only") then
                settings.autoGroundMode = "Set"
            elseif string.find(opt, "Bump Only") then
                settings.autoGroundMode = "Bump"
            else
                settings.autoGroundMode = "Smart"
            end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Hit Reaction Debounce",
        Range = {0.3, 1.0},
        Increment = 0.05,
        Suffix = "s",
        CurrentValue = settings.autoHitDebounce,
        Flag = "VB_AutoHitDebounce_v4",
        Callback = function(value)
            settings.autoHitDebounce = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Dive (Low Ball)",
        CurrentValue = settings.autoDive,
        Flag = "VB_AutoDive_v4",
        Callback = function(value)
            settings.autoDive = value
        end,
    })

    CombatTab:CreateSection("Power & Impact")

    CombatTab:CreateToggle({
        Name = "Always 100% Max Power",
        CurrentValue = settings.alwaysMaxPower,
        Flag = "VB_MaxPower_v4",
        Callback = function(value)
            settings.alwaysMaxPower = value
            applyPowerSettings()
        end,
    })

    CombatTab:CreateSlider({
        Name = "Power Scale",
        Range = {0.5, 3.0},
        Increment = 0.1,
        Suffix = "x",
        CurrentValue = settings.customPowerValue,
        Flag = "VB_PowerScale_v4",
        Callback = function(value)
            settings.customPowerValue = value
            applyPowerSettings()
        end,
    })

    CombatTab:CreateSection("Mobility Booster")

    CombatTab:CreateToggle({
        Name = "Super Dive (Long Range)",
        CurrentValue = settings.superDive,
        Flag = "VB_SuperDive_v4",
        Callback = function(value)
            settings.superDive = value
            applyMobilitySettings()
        end,
    })

    CombatTab:CreateSlider({
        Name = "Dive Speed Multiplier",
        Range = {1.0, 4.0},
        Increment = 0.1,
        Suffix = "x",
        CurrentValue = settings.diveSpeedMultiplier,
        Flag = "VB_DiveSpeed_v4",
        Callback = function(value)
            settings.diveSpeedMultiplier = value
            if settings.superDive then
                applyMobilitySettings()
            end
        end,
    })

    CombatTab:CreateToggle({
        Name = "Movement Speed Booster",
        CurrentValue = settings.speedBoost,
        Flag = "VB_SpeedBoost_v4",
        Callback = function(value)
            settings.speedBoost = value
            applyMobilitySettings()
        end,
    })

    CombatTab:CreateSlider({
        Name = "Speed Multiplier",
        Range = {1.0, 3.0},
        Increment = 0.1,
        Suffix = "x",
        CurrentValue = settings.speedMultiplier,
        Flag = "VB_SpeedMult_v4",
        Callback = function(value)
            settings.speedMultiplier = value
            if settings.speedBoost then
                applyMobilitySettings()
            end
        end,
    })

    CombatTab:CreateSection("Aerial & Recovery")

    CombatTab:CreateToggle({
        Name = "Super Jump (High Spike)",
        CurrentValue = settings.superJump,
        Flag = "VB_SuperJump_v4",
        Callback = function(value)
            settings.superJump = value
            applyAerialSettings()
        end,
    })

    CombatTab:CreateSlider({
        Name = "Jump Multiplier",
        Range = {1.0, 3.0},
        Increment = 0.1,
        Suffix = "x",
        CurrentValue = settings.jumpMultiplier,
        Flag = "VB_JumpMult_v4",
        Callback = function(value)
            settings.jumpMultiplier = value
            if settings.superJump then
                applyAerialSettings()
            end
        end,
    })

    CombatTab:CreateToggle({
        Name = "Infinite / Air Double Jump",
        CurrentValue = settings.airDoubleJump,
        Flag = "VB_DoubleJump_v4",
        Callback = function(value)
            settings.airDoubleJump = value
            applyAerialSettings()
        end,
    })

    CombatTab:CreateToggle({
        Name = "Anti-Stun / Instant Recovery",
        CurrentValue = settings.antiStun,
        Flag = "VB_AntiStun_v4",
        Callback = function(value)
            settings.antiStun = value
            applyAerialSettings()
        end,
    })

    CombatTab:CreateToggle({
        Name = "Bypass Back-Rank Attack Limit",
        CurrentValue = settings.bypassBackRank,
        Flag = "VB_BypassBackRank_v4",
        Callback = function(value)
            settings.bypassBackRank = value
            applyAerialSettings()
        end,
    })

    CombatTab:CreateSection("Ball Magnet & Reposition Assist")

    CombatTab:CreateToggle({
        Name = "Auto-Reposition (Walk to Ball)",
        CurrentValue = settings.autoReposition,
        Flag = "VB_AutoReposition_v4",
        Callback = function(value)
            settings.autoReposition = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Reposition Distance",
        Range = {10, 45},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = settings.autoRepositionDist,
        Flag = "VB_AutoRepoDist_v4",
        Callback = function(value)
            settings.autoRepositionDist = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Face Ball (Aim Assist)",
        CurrentValue = settings.autoFaceBall,
        Flag = "VB_AutoFaceBall_v4",
        Callback = function(value)
            settings.autoFaceBall = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Ignore Out-of-Bounds (ไม่ตามบอลออก)",
        CurrentValue = settings.courtOutCheck,
        Flag = "VB_CourtOutCheck_v4",
        Callback = function(value)
            settings.courtOutCheck = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Humanized Movement (เดินเนียนแบบคน)",
        CurrentValue = settings.repositionHumanized,
        Flag = "VB_HumanizedRepo_v4",
        Callback = function(value)
            settings.repositionHumanized = value
        end,
    })

    CombatTab:CreateSection("Gacha & Spins")

    CombatTab:CreateToggle({
        Name = "Instant Spin / Skip Gacha Cutscene",
        CurrentValue = settings.instantSpinSkip,
        Flag = "VB_InstantSpinSkip_v4",
        Callback = function(value)
            settings.instantSpinSkip = value
            applyGachaSettings()
        end,
    })

    -- Initial apply
    applyHitboxSettings()
    applyCooldownSettings()
    applyPowerSettings()
    applyMobilitySettings()
    applyAerialSettings()
    applyGachaSettings()

    -- ============================================================
    --   CLEANUP
    -- ============================================================
    local function destroyScript()
        if not running then return end
        running = false

        -- Restore gacha skip
        pcall(function()
            if AbilityController and AbilityController.CanSkip and origAbilityCanSkip then
                AbilityController.CanSkip.get = origAbilityCanSkip
            end
            if StyleController and StyleController.CanSkip and origStyleCanSkip then
                StyleController.CanSkip.get = origStyleCanSkip
            end
        end)

        -- Restore aerial & recovery
        pcall(function()
            if JumpPhysics and originalLaunchSpeed then
                JumpPhysics.LaunchSpeed = originalLaunchSpeed
            end
            if JumpValidation then
                if originalCanDoubleJump then JumpValidation.canDoubleJump = originalCanDoubleJump end
                if originalIsBackRank then JumpValidation._isBackRank = originalIsBackRank end
            end
            if GameControllerMod and GameControllerMod.IsStunned and originalIsStunnedGet then
                GameControllerMod.IsStunned.get = originalIsStunnedGet
            end
        end)

        -- Restore power & mobility
        pcall(function()
            if DoMoveGame and originalGetPowerAndReset then
                DoMoveGame.getPowerAndReset = originalGetPowerAndReset
            end
            if localPlayer then
                if originalPlayerAttributes.Multiplier_DiveSpeed then
                    localPlayer:SetAttribute("Multiplier_DiveSpeed", originalPlayerAttributes.Multiplier_DiveSpeed)
                end
                if originalPlayerAttributes.Multiplier_Speed then
                    localPlayer:SetAttribute("Multiplier_Speed", originalPlayerAttributes.Multiplier_Speed)
                end
            end
        end)

        -- Restore cooldown handlers
        pcall(function()
            if Orchestrator then
                if originalIsOnCooldown then Orchestrator.isOnCooldown = originalIsOnCooldown end
                if originalApplyCooldown then Orchestrator._applyCooldown = originalApplyCooldown end
            end
        end)

        -- Restore original hitboxes & visualizer
        pcall(function()
            if GameConfig then
                GameConfig._DebugHitboxes = false
            end
            local assemblies = ReplicatedStorage.Assets.HitboxesNew.Default.Assemblies
            for name, baseSize in pairs(TRUE_BASE_HITBOXES) do
                local folder = assemblies:FindFirstChild(name)
                if folder then
                    local part = folder:FindFirstChild("Part")
                    if part and part:IsA("BasePart") then
                        part.Size = baseSize
                    end
                end
                if HitboxTool then
                    local ok, hitboxData = pcall(function()
                        return HitboxTool.get({ MoveId = name })
                    end)
                    if ok and hitboxData then
                        hitboxData.Size = baseSize
                    end
                end
            end
            if ClientHitbox and ClientHitbox._cachedHitbox then
                ClientHitbox._cachedHitbox = nil
            end
        end)

        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(connections)

        for id, _ in pairs(espObjects) do
            clearEspEntry(id)
        end
        table.clear(espObjects)

        if landingCylinder then
            pcall(function() landingCylinder:Destroy() end)
            landingCylinder = nil
        end
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end

    environment.__RAVEN_VOLLEYBALL_LEGENDS = {
        Destroy = destroyScript
    }
end
