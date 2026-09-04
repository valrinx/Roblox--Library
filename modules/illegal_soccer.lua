-- ============================================================
--   RAVEN HUB  |  Illegal Soccer
--   Infinite Stamina, Ball & Player ESP, Movement Utilities
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService = game:GetService("TweenService")

    local localPlayer = Players.LocalPlayer
    local camera = workspace.CurrentCamera

    local running = true
    local connections = {}
    local espObjects = {}

    -- Settings
    local settings = {
        infiniteStamina = true,
        alwaysSprint = false,
        customSpeed = false,
        walkSpeed = 25.6,
        infiniteJump = false,
        autoGoalkeeper = false,
        gkAutoPosition = true,
        gkAutoDive = true,
        gkAutoPunch = true,
        gkDiveReach = 22,
        noBallSlowdown = true,
        fullSpeedCharge = true,
        instantCharge = true,
        autoPass = true,
        magneticPass = true,
        ballEsp = true,
        playerEsp = true,
        playerEspShowDistance = true,
        playerEspShowHealth = true,
        goalEsp = true,
        fullbright = false,
        fieldOfView = 75,
    }

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getRoot(model)
        if not model then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("UpperTorso")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getHumanoid(model)
        if not model then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    -- ============================================================
    --   INFINITE STAMINA ENGINE
    -- ============================================================
    local SprintModule = nil
    local origHasUnlimited = nil
    local origGetDrain = nil
    local origGetSpend = nil
    local cachedStaminaTable = nil

    pcall(function()
        SprintModule = require(ReplicatedStorage.Modules.Actions.Sprint)
        if SprintModule then
            origHasUnlimited = SprintModule.HasUnlimitedStamina
            origGetDrain = SprintModule.GetDrainAmount
            origGetSpend = SprintModule.GetSpendAmount
        end
    end)

    local function findStaminaTable()
        if type(getgc) ~= "function" then return nil end
        local gc = getgc(true)
        for _, item in ipairs(gc) do
            if type(item) == "table" and rawget(item, "HasUnlimitedStamina") ~= nil and rawget(item, "Stamina") ~= nil then
                return item
            end
        end
        return nil
    end

    local function enableInfiniteStamina()
        if not running or not settings.infiniteStamina then return end

        if SprintModule then
            SprintModule.HasUnlimitedStamina = function() return true end
            SprintModule.GetDrainAmount = function() return 0 end
            SprintModule.GetSpendAmount = function() return 0 end

            local char = localPlayer.Character
            if char then
                pcall(function()
                    SprintModule.SetUnlimitedStamina(char, "RavenSoccerMod", true)
                end)
            end
        end

        if not cachedStaminaTable then
            cachedStaminaTable = findStaminaTable()
        end

        if cachedStaminaTable then
            cachedStaminaTable.HasUnlimitedStamina = true
            cachedStaminaTable.Stamina = 1
            cachedStaminaTable.CanStartSprinting = true
        end
    end

    local function restoreStaminaState()
        cachedStaminaTable = nil
        if SprintModule then
            if origHasUnlimited then SprintModule.HasUnlimitedStamina = origHasUnlimited end
            if origGetDrain then SprintModule.GetDrainAmount = origGetDrain end
            if origGetSpend then SprintModule.GetSpendAmount = origGetSpend end

            local char = localPlayer.Character
            if char and type(SprintModule.ClearUnlimitedStaminaSource) == "function" then
                pcall(function()
                    SprintModule.ClearUnlimitedStaminaSource("RavenSoccerMod")
                end)
            end
        end
    end

    -- Initial stamina hook
    if settings.infiniteStamina then
        enableInfiniteStamina()
    end

    -- ============================================================
    --   MOVEMENT, BALL CONTROL & PASSING ENGINE
    -- ============================================================
    local ActionMovement = nil
    local ShootModule = nil
    local PassModule = nil
    local AssistedPassModule = nil
    local KickCore = nil
    local ActionCommands = nil
    local ActionRemoteProtocol = nil

    local origGetChargeAlpha = nil
    local origGetMinimumReleaseDelaySeconds = nil
    local origIsFullyCharged = nil
    local origIsFullPower = nil
    local origCmdKick = nil
    local origCmdTackleKick = nil
    local origCmdVolley = nil
    local origCmdThrow = nil
    local origCmdAssistedPass = nil
    local origRemoteRelease = nil

    pcall(function()
        ActionMovement = require(ReplicatedStorage.Modules.Actions.ActionMovement)
        ShootModule = require(ReplicatedStorage.Modules.Actions.Shoot)
        PassModule = require(ReplicatedStorage.Modules.Actions.Pass)
        AssistedPassModule = require(ReplicatedStorage.Modules.Actions.AssistedPass)
        KickCore = require(ReplicatedStorage.Modules.Actions.KickCore)
        ActionCommands = require(ReplicatedStorage.Modules.Actions.ActionCommands)
        ActionRemoteProtocol = require(ReplicatedStorage.Modules.Actions.ActionRemoteProtocol)

        if KickCore then
            origGetChargeAlpha = KickCore.GetChargeAlpha
            origGetMinimumReleaseDelaySeconds = KickCore.GetMinimumReleaseDelaySeconds
            origIsFullyCharged = KickCore.IsFullyCharged
            origIsFullPower = KickCore.IsFullPower

            KickCore.GetChargeAlpha = function(chargeSeconds, constants)
                if running and settings.instantCharge then
                    return 1
                end
                if origGetChargeAlpha then
                    return origGetChargeAlpha(chargeSeconds, constants)
                end
                return 1
            end

            KickCore.GetMinimumReleaseDelaySeconds = function(chargeSeconds, constants)
                if running and settings.instantCharge then
                    return 0
                end
                if origGetMinimumReleaseDelaySeconds then
                    return origGetMinimumReleaseDelaySeconds(chargeSeconds, constants)
                end
                return 0
            end

            KickCore.IsFullyCharged = function(chargeSeconds, constants)
                if running and settings.instantCharge then
                    return true
                end
                if origIsFullyCharged then
                    return origIsFullyCharged(chargeSeconds, constants)
                end
                return true
            end

            KickCore.IsFullPower = function(chargeSeconds, constants, mult)
                if running and settings.instantCharge then
                    return true
                end
                if origIsFullPower then
                    return origIsFullPower(chargeSeconds, constants, mult)
                end
                return true
            end
        end

        if ActionCommands then
            origCmdKick = ActionCommands.Kick
            origCmdTackleKick = ActionCommands.TackleKick
            origCmdVolley = ActionCommands.Volley
            origCmdThrow = ActionCommands.Throw
            origCmdAssistedPass = ActionCommands.AssistedPass

            ActionCommands.Kick = function(data)
                local cmd = origCmdKick(data)
                if running and settings.instantCharge and cmd then
                    local maxSec = cmd.MaximumChargeSeconds or (ShootModule and ShootModule.Constants.Kick.MaximumChargeSeconds) or 0.4
                    cmd.ChargeSeconds = maxSec
                    cmd.HoldSeconds = maxSec
                end
                return cmd
            end

            ActionCommands.TackleKick = function(data)
                local cmd = origCmdTackleKick(data)
                if running and settings.instantCharge and cmd then
                    local maxSec = cmd.MaximumChargeSeconds or (ShootModule and ShootModule.Constants.Kick.MaximumChargeSeconds) or 0.4
                    cmd.ChargeSeconds = maxSec
                    cmd.HoldSeconds = maxSec
                end
                return cmd
            end

            ActionCommands.Volley = function(data)
                local cmd = origCmdVolley(data)
                if running and settings.instantCharge and cmd then
                    local maxSec = cmd.MaximumChargeSeconds or (ShootModule and ShootModule.Constants.Kick.MaximumChargeSeconds) or 0.4
                    cmd.ChargeSeconds = maxSec
                    cmd.HoldSeconds = maxSec
                end
                return cmd
            end

            ActionCommands.Throw = function(data)
                local cmd = origCmdThrow(data)
                if running and settings.instantCharge and cmd then
                    local maxSec = cmd.MaximumChargeSeconds or (ShootModule and ShootModule.Constants.Kick.MaximumChargeSeconds) or 0.4
                    cmd.ChargeSeconds = maxSec
                    cmd.HoldSeconds = maxSec
                end
                return cmd
            end

            ActionCommands.AssistedPass = function(data)
                local cmd = origCmdAssistedPass(data)
                if running and settings.instantCharge and cmd then
                    local maxSec = cmd.MaximumChargeSeconds or (PassModule and PassModule.Constants.Kick.MaximumChargeSeconds) or 0.3
                    cmd.ChargeSeconds = maxSec
                    cmd.HoldSeconds = maxSec
                end
                return cmd
            end
        end

        if ActionRemoteProtocol then
            origRemoteRelease = ActionRemoteProtocol.Release
            ActionRemoteProtocol.Release = function(cmd)
                if running and settings.instantCharge and type(cmd) == "table" then
                    local maxSec = cmd.MaximumChargeSeconds or (cmd.PassType == "Pass" and 0.3 or 0.4)
                    cmd.ChargeSeconds = maxSec
                    cmd.HoldSeconds = maxSec
                    cmd.ChargeStartedAt = (cmd.ShotTime or workspace:GetServerTimeNow()) - maxSec - 0.05
                end
                return origRemoteRelease(cmd)
            end
        end
    end)

    local function applyMovementEnhancements()
        if not running then return end

        if ActionMovement then
            if settings.noBallSlowdown then
                ActionMovement.Constants.BallCarrierJogSpeedMultiplier = 1.0
                ActionMovement.Constants.BallCarrierRunSpeedMultiplier = 1.0
            else
                ActionMovement.Constants.BallCarrierJogSpeedMultiplier = 0.9
                ActionMovement.Constants.BallCarrierRunSpeedMultiplier = 0.8
            end

            if settings.fullSpeedCharge then
                ActionMovement.Constants.ChargingWalkSpeedMultiplier = 1.0
                ActionMovement.Constants.ChargingRecoverySeconds = 0
            else
                ActionMovement.Constants.ChargingWalkSpeedMultiplier = 0.5
                ActionMovement.Constants.ChargingRecoverySeconds = 0.5
            end
        end

        if ShootModule and PassModule then
            -- Keep genuine official maximum charge constants intact
            ShootModule.Constants.Kick.MaximumChargeSeconds = 0.4
            PassModule.Constants.Kick.MaximumChargeSeconds = 0.3
            ShootModule.Constants.Kick.MinimumChargeSeconds = 0.2
            PassModule.Constants.Kick.MinimumChargeSeconds = 0.1
        end

        if AssistedPassModule then
            if settings.autoPass or settings.magneticPass then
                AssistedPassModule.Constants.NearAimAngleDegrees = 180
                AssistedPassModule.Constants.FarAimAngleDegrees = 180
                AssistedPassModule.Constants.MaximumTargetDistance = 150
            else
                AssistedPassModule.Constants.NearAimAngleDegrees = 20
                AssistedPassModule.Constants.FarAimAngleDegrees = 0
                AssistedPassModule.Constants.MaximumTargetDistance = 110
            end
        end

        if cachedStaminaTable and settings.noBallSlowdown then
            cachedStaminaTable.IgnoreBallCarrierSpeedPenalty = true
        end
    end

    local function restoreMovementEnhancements()
        if ActionMovement then
            ActionMovement.Constants.BallCarrierJogSpeedMultiplier = 0.9
            ActionMovement.Constants.BallCarrierRunSpeedMultiplier = 0.8
            ActionMovement.Constants.ChargingWalkSpeedMultiplier = 0.5
            ActionMovement.Constants.ChargingRecoverySeconds = 0.5
        end
        if ShootModule and PassModule then
            ShootModule.Constants.Kick.MaximumChargeSeconds = 0.4
            PassModule.Constants.Kick.MaximumChargeSeconds = 0.3
            ShootModule.Constants.Kick.MinimumChargeSeconds = 0.2
            PassModule.Constants.Kick.MinimumChargeSeconds = 0.1
        end
        if AssistedPassModule then
            AssistedPassModule.Constants.NearAimAngleDegrees = 20
            AssistedPassModule.Constants.FarAimAngleDegrees = 0
            AssistedPassModule.Constants.MaximumTargetDistance = 110
        end
        if KickCore then
            if origGetChargeAlpha then KickCore.GetChargeAlpha = origGetChargeAlpha end
            if origGetMinimumReleaseDelaySeconds then KickCore.GetMinimumReleaseDelaySeconds = origGetMinimumReleaseDelaySeconds end
            if origIsFullyCharged then KickCore.IsFullyCharged = origIsFullyCharged end
            if origIsFullPower then KickCore.IsFullPower = origIsFullPower end
        end
        if ActionCommands then
            if origCmdKick then ActionCommands.Kick = origCmdKick end
            if origCmdTackleKick then ActionCommands.TackleKick = origCmdTackleKick end
            if origCmdVolley then ActionCommands.Volley = origCmdVolley end
            if origCmdThrow then ActionCommands.Throw = origCmdThrow end
            if origCmdAssistedPass then ActionCommands.AssistedPass = origCmdAssistedPass end
        end
        if ActionRemoteProtocol then
            if origRemoteRelease then ActionRemoteProtocol.Release = origRemoteRelease end
        end
    end

    local function findBestTeammate()
        local myChar = localPlayer.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return nil end

        local myJersey = myChar:FindFirstChild("TeamJersey")
        local myColor = myJersey and myJersey:FindFirstChild("Handle") and myJersey.Handle.Color

        local bestTeammate = nil
        local bestDist = math.huge

        local charFolder = workspace:FindFirstChild("Characters") and workspace.Characters:FindFirstChild("Players")
        if charFolder then
            for _, char in ipairs(charFolder:GetChildren()) do
                if char:IsA("Model") and char ~= myChar then
                    local root = getRoot(char)
                    local hum = getHumanoid(char)
                    if root and hum and hum.Health > 0 then
                        local jersey = char:FindFirstChild("TeamJersey")
                        local col = jersey and jersey:FindFirstChild("Handle") and jersey.Handle.Color
                        local isTeammate = false
                        if myColor and col then
                            local diff = math.abs(myColor.R - col.R) + math.abs(myColor.G - col.G) + math.abs(myColor.B - col.B)
                            isTeammate = (diff < 0.1)
                        end

                        if isTeammate then
                            local dist = (root.Position - myRoot.Position).Magnitude
                            if dist < bestDist and dist > 8 then
                                bestDist = dist
                                bestTeammate = char
                            end
                        end
                    end
                end
            end
        end
        return bestTeammate
    end

    local function executeAutoPass()
        local target = findBestTeammate()
        if not target then return end
        local targetRoot = getRoot(target)
        local myRoot = getRoot(localPlayer.Character)
        if not targetRoot or not myRoot then return end

        pcall(function()
            myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z))
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, Enum.KeyCode.R, false, game)
            task.delay(0.05, function()
                vim:SendKeyEvent(false, Enum.KeyCode.R, false, game)
            end)
        end)
    end

    applyMovementEnhancements()

    -- ============================================================
    --   ESP SYSTEM
    -- ============================================================
    local function createBillboard(name, adornee, color, text, offset)
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "Raven_" .. name
        billboard.Adornee = adornee
        billboard.Size = UDim2.new(0, 160, 0, 45)
        billboard.StudsOffset = offset or Vector3.new(0, 2.5, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 800

        local label = Instance.new("TextLabel")
        label.Name = "MainText"
        label.Parent = billboard
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
        label.TextStrokeTransparency = 0.2
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.Text = text or name
        label.RichText = true

        pcall(function()
            if type(gethui) == "function" then
                billboard.Parent = gethui()
            else
                billboard.Parent = game:GetService("CoreGui")
            end
        end)
        if not billboard.Parent then
            billboard.Parent = localPlayer:FindFirstChildOfClass("PlayerGui")
        end

        return billboard, label
    end

    local function createHighlight(adornee, fillCol, outlineCol)
        local hl = Instance.new("Highlight")
        hl.Name = "Raven_Highlight"
        hl.Adornee = adornee
        hl.FillColor = fillCol or Color3.fromRGB(255, 255, 255)
        hl.OutlineColor = outlineCol or Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0.1
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

        pcall(function()
            if type(gethui) == "function" then
                hl.Parent = gethui()
            else
                hl.Parent = game:GetService("CoreGui")
            end
        end)
        if not hl.Parent then
            hl.Parent = localPlayer:FindFirstChildOfClass("PlayerGui")
        end

        return hl
    end

    local function clearEspEntry(id)
        if espObjects[id] then
            for _, obj in pairs(espObjects[id]) do
                if typeof(obj) == "Instance" then
                    pcall(function() obj:Destroy() end)
                end
            end
            espObjects[id] = nil
        end
    end

    local function clearAllEsp()
        for id, _ in pairs(espObjects) do
            clearEspEntry(id)
        end
    end

    -- ============================================================
    --   UPDATE LOOPS
    -- ============================================================

    -- ============================================================
    --   GOALKEEPER AUTOMATION ENGINE
    -- ============================================================
    local lastDiveTime = 0
    local lastPunchTime = 0

    local function getMyGoalTeam()
        local char = localPlayer.Character
        local root = getRoot(char)
        if not root then return "Team1", Vector3.new(0, 1.5, -145.5) end
        local t1Dist = (root.Position - Vector3.new(0, 7, -155)).Magnitude
        local t2Dist = (root.Position - Vector3.new(0, 7, 155)).Magnitude
        if t2Dist < t1Dist then
            return "Team2", Vector3.new(0, 1.5, 145.5)
        else
            return "Team1", Vector3.new(0, 1.5, -145.5)
        end
    end

    local function updateAutoGoalkeeper()
        if not running or not settings.autoGoalkeeper then return end
        local char = localPlayer.Character
        local root = getRoot(char)
        local hum = getHumanoid(char)
        if not root or not hum or hum.Health <= 0 then return end

        local visuals = workspace:FindFirstChild("Misc") and workspace.Misc:FindFirstChild("Visuals")
        local ball = visuals and visuals:FindFirstChild("ClientBall_MainMatch")
        if not ball or not ball:IsA("BasePart") then return end

        local myTeam, homePos = getMyGoalTeam()
        local goalZ = (myTeam == "Team1") and -155 or 155
        local ballPos = ball.Position
        local ballVel = ball.AssemblyLinearVelocity
        local distToBall = (ballPos - root.Position).Magnitude
        local now = os.clock()

        -- 1. Check for incoming shot on goal (Shot Prediction)
        local isShotIncoming = false
        local timeToGoal = 0
        if myTeam == "Team1" and ballVel.Z < -6 then
            timeToGoal = (goalZ - ballPos.Z) / ballVel.Z
            isShotIncoming = (timeToGoal > 0 and timeToGoal < 1.6)
        elseif myTeam == "Team2" and ballVel.Z > 6 then
            timeToGoal = (goalZ - ballPos.Z) / ballVel.Z
            isShotIncoming = (timeToGoal > 0 and timeToGoal < 1.6)
        end

        local interceptX = ballPos.X + ballVel.X * timeToGoal

        -- Auto Dive / Save
        if settings.gkAutoDive and isShotIncoming and math.abs(interceptX) <= 24 and distToBall <= settings.gkDiveReach then
            if (now - lastDiveTime) > 1.8 then
                lastDiveTime = now
                pcall(function()
                    root.CFrame = CFrame.lookAt(root.Position, Vector3.new(ballPos.X, root.Position.Y, ballPos.Z))
                    local vim = game:GetService("VirtualInputManager")
                    vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.delay(0.08, function()
                        vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    end)
                end)
                return
            end
        end

        -- Auto Punch / Clear loose ball
        if settings.gkAutoPunch and distToBall <= 8 and (now - lastPunchTime) > 0.8 then
            lastPunchTime = now
            pcall(function()
                root.CFrame = CFrame.lookAt(root.Position, Vector3.new(ballPos.X, root.Position.Y, ballPos.Z))
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                task.delay(0.05, function()
                    vim:SendMouseButtonEvent(0, 0, 0, false, game, 1)
                end)
            end)
            return
        end

        -- Auto Positioning along the net
        if settings.gkAutoPosition then
            local clampedX = math.clamp(ballPos.X * 0.7, -18, 18)
            local zOffset = (ballPos.Z - homePos.Z) * 0.08
            local targetPos = Vector3.new(clampedX, homePos.Y, homePos.Z + zOffset)
            if (root.Position - targetPos).Magnitude > 2 then
                hum:MoveTo(targetPos)
            end
        end
    end

    -- Update Loops
    connect(RunService.Heartbeat, function()
        if not running then return end

        -- Lightweight stamina lock (zero allocations)
        if settings.infiniteStamina then
            if cachedStaminaTable then
                cachedStaminaTable.HasUnlimitedStamina = true
                cachedStaminaTable.Stamina = 1
                cachedStaminaTable.CanStartSprinting = true
            else
                cachedStaminaTable = findStaminaTable()
            end
        end

        -- Custom WalkSpeed handling
        if settings.customSpeed then
            local char = localPlayer.Character
            local hum = getHumanoid(char)
            if hum and hum.WalkSpeed ~= settings.walkSpeed then
                hum.WalkSpeed = settings.walkSpeed
            end
        end

        -- Always Sprint handling
        if settings.alwaysSprint and SprintModule then
            local char = localPlayer.Character
            if char and type(SprintModule.SetCharacterIsSprinting) == "function" then
                pcall(function()
                    SprintModule.SetCharacterIsSprinting(char, true)
                end)
            end
        end

        -- Auto Goalkeeper update
        if settings.autoGoalkeeper then
            updateAutoGoalkeeper()
        end
    end)

    -- Character respawn handler
    connect(localPlayer.CharacterAdded, function(newChar)
        cachedStaminaTable = nil
        task.wait(0.5)
        if settings.infiniteStamina then
            enableInfiniteStamina()
        end
        applyMovementEnhancements()
    end)

    -- Auto Pass Keybind handler (Key: Z)
    connect(UserInputService.InputBegan, function(input, gameProcessed)
        if gameProcessed or not running then return end
        if input.KeyCode == Enum.KeyCode.Z and settings.autoPass then
            executeAutoPass()
        end
    end)

    -- Infinite Jump handler
    connect(UserInputService.JumpRequest, function()
        if not running or not settings.infiniteJump then return end
        local char = localPlayer.Character
        local hum = getHumanoid(char)
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    -- Main Visual / ESP Render Loop
    connect(RunService.RenderStepped, function()
        if not running then return end
        local myRoot = getRoot(localPlayer.Character)
        local myPos = myRoot and myRoot.Position or (camera and camera.CFrame.Position) or Vector3.zero

        -- 1. Ball ESP
        if settings.ballEsp then
            local visuals = workspace:FindFirstChild("Misc") and workspace.Misc:FindFirstChild("Visuals")
            local ball = visuals and visuals:FindFirstChild("ClientBall_MainMatch")
            if not ball and visuals then
                for _, child in ipairs(visuals:GetChildren()) do
                    if string.find(string.lower(child.Name), "ball") and child:IsA("BasePart") then
                        ball = child
                        break
                    end
                end
            end

            if ball and ball:IsA("BasePart") and ball.Parent then
                local dist = math.floor((ball.Position - myPos).Magnitude)
                local id = "Ball_Main"
                if not espObjects[id] then
                    local bb, lbl = createBillboard(id, ball, Color3.fromRGB(255, 215, 0), "⚽ Ball", Vector3.new(0, 2, 0))
                    local hl = createHighlight(ball, Color3.fromRGB(255, 215, 0), Color3.fromRGB(255, 255, 255))
                    espObjects[id] = { billboard = bb, label = lbl, highlight = hl }
                else
                    espObjects[id].label.Text = string.format("⚽ <b>Ball</b>\n<font size='11' color='#FFFFFF'>[%d studs]</font>", dist)
                end
            else
                clearEspEntry("Ball_Main")
            end
        else
            clearEspEntry("Ball_Main")
        end

        -- 2. Goal ESP
        if settings.goalEsp then
            local mapData = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Data")
            if mapData then
                for _, teamName in ipairs({"Team1", "Team2"}) do
                    local teamFolder = mapData:FindFirstChild(teamName)
                    local goal = teamFolder and teamFolder:FindFirstChild("Goal")
                    local id = "Goal_" .. teamName
                    if goal and goal:IsA("BasePart") then
                        local dist = math.floor((goal.Position - myPos).Magnitude)
                        local col = (teamName == "Team1") and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(255, 85, 85)
                        if not espObjects[id] then
                            local bb, lbl = createBillboard(id, goal, col, "🥅 " .. teamName .. " Goal", Vector3.new(0, 6, 0))
                            espObjects[id] = { billboard = bb, label = lbl }
                        else
                            espObjects[id].label.Text = string.format("🥅 <b>%s Goal</b>\n<font size='11' color='#FFFFFF'>[%d studs]</font>", teamName, dist)
                        end
                    else
                        clearEspEntry(id)
                    end
                end
            end
        else
            clearEspEntry("Goal_Team1")
            clearEspEntry("Goal_Team2")
        end

        -- 3. Player ESP
        if settings.playerEsp then
            local charFolder = workspace:FindFirstChild("Characters") and workspace.Characters:FindFirstChild("Players")
            if charFolder then
                local validIds = {}
                for _, char in ipairs(charFolder:GetChildren()) do
                    if char:IsA("Model") and char ~= localPlayer.Character then
                        local root = getRoot(char)
                        local hum = getHumanoid(char)
                        if root and hum and hum.Health > 0 then
                            local id = "Player_" .. char.Name
                            validIds[id] = true
                            local dist = math.floor((root.Position - myPos).Magnitude)

                            -- Detect team jersey color
                            local jerseyCol = Color3.fromRGB(255, 255, 255)
                            local jersey = char:FindFirstChild("TeamJersey")
                            if jersey and jersey:FindFirstChild("Handle") and jersey.Handle:IsA("BasePart") then
                                jerseyCol = jersey.Handle.Color
                            end

                            if not espObjects[id] then
                                local bb, lbl = createBillboard(id, root, jerseyCol, char.Name, Vector3.new(0, 3.2, 0))
                                local hl = createHighlight(char, jerseyCol, Color3.fromRGB(255, 255, 255))
                                espObjects[id] = { billboard = bb, label = lbl, highlight = hl }
                            else
                                local infoText = "<b>" .. char.Name .. "</b>"
                                if settings.playerEspShowDistance then
                                    infoText = infoText .. string.format("\n<font size='10' color='#CCCCCC'>[%d studs]</font>", dist)
                                end
                                if settings.playerEspShowHealth then
                                    infoText = infoText .. string.format(" <font size='10' color='#55FF55'>[HP %d]</font>", math.floor(hum.Health))
                                end
                                espObjects[id].label.Text = infoText
                                espObjects[id].label.TextColor3 = jerseyCol
                                if espObjects[id].highlight then
                                    espObjects[id].highlight.FillColor = jerseyCol
                                end
                            end
                        end
                    end
                end

                for id, _ in pairs(espObjects) do
                    if string.sub(id, 1, 7) == "Player_" and not validIds[id] then
                        clearEspEntry(id)
                    end
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

    -- Fullbright / Lighting
    local origAmbient = game:GetService("Lighting").Ambient
    local origBrightness = game:GetService("Lighting").Brightness
    local origClockTime = game:GetService("Lighting").ClockTime

    local function applyFullbright(enabled)
        local lighting = game:GetService("Lighting")
        if enabled then
            lighting.Ambient = Color3.fromRGB(255, 255, 255)
            lighting.Brightness = 2
            lighting.ClockTime = 14
        else
            lighting.Ambient = origAmbient
            lighting.Brightness = origBrightness
            lighting.ClockTime = origClockTime
        end
    end

    -- ============================================================
    --   USER INTERFACE TABS (MacLib)
    -- ============================================================

    local MainTab = Window:CreateTab("Movement", 4483362458)
    MainTab:CreateSection("Stamina & Dash")

    MainTab:CreateToggle({
        Name = "Infinite Stamina",
        CurrentValue = settings.infiniteStamina,
        Flag = "Soccer_InfStamina",
        Callback = function(value)
            settings.infiniteStamina = value
            if value then
                enableInfiniteStamina()
            else
                restoreStaminaState()
            end
        end,
    })

    MainTab:CreateToggle({
        Name = "Always Sprint",
        CurrentValue = settings.alwaysSprint,
        Flag = "Soccer_AlwaysSprint",
        Callback = function(value)
            settings.alwaysSprint = value
        end,
    })

    MainTab:CreateSection("Speed & Jump")

    MainTab:CreateToggle({
        Name = "Custom WalkSpeed",
        CurrentValue = settings.customSpeed,
        Flag = "Soccer_CustomSpeed",
        Callback = function(value)
            settings.customSpeed = value
            if not value then
                local char = localPlayer.Character
                local hum = getHumanoid(char)
                if hum then hum.WalkSpeed = 25.6 end
            end
        end,
    })

    MainTab:CreateSlider({
        Name = "WalkSpeed Value",
        Range = {16, 100},
        Increment = 1,
        CurrentValue = settings.walkSpeed,
        Flag = "Soccer_SpeedValue",
        Callback = function(value)
            settings.walkSpeed = value
            if settings.customSpeed then
                local char = localPlayer.Character
                local hum = getHumanoid(char)
                if hum then hum.WalkSpeed = value end
            end
        end,
    })

    MainTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = settings.infiniteJump,
        Flag = "Soccer_InfJump",
        Callback = function(value)
            settings.infiniteJump = value
        end,
    })

    MainTab:CreateSection("Ball Control & Mechanics")

    MainTab:CreateToggle({
        Name = "No Ball Slowdown (Full Dribble Speed)",
        CurrentValue = settings.noBallSlowdown,
        Flag = "Soccer_NoBallSlowdown",
        Callback = function(value)
            settings.noBallSlowdown = value
            applyMovementEnhancements()
        end,
    })

    MainTab:CreateToggle({
        Name = "Full Speed Charge (No Kick Slowdown)",
        CurrentValue = settings.fullSpeedCharge,
        Flag = "Soccer_FullSpeedCharge",
        Callback = function(value)
            settings.fullSpeedCharge = value
            applyMovementEnhancements()
        end,
    })

    MainTab:CreateToggle({
        Name = "Instant Max Charge Power",
        CurrentValue = settings.instantCharge,
        Flag = "Soccer_InstantCharge",
        Callback = function(value)
            settings.instantCharge = value
            applyMovementEnhancements()
        end,
    })

    MainTab:CreateSection("Passing Assist")

    MainTab:CreateToggle({
        Name = "Auto Pass / Magnetic Lock (360°)",
        CurrentValue = settings.autoPass,
        Flag = "Soccer_AutoPass",
        Callback = function(value)
            settings.autoPass = value
            settings.magneticPass = value
            applyMovementEnhancements()
        end,
    })

    MainTab:CreateButton({
        Name = "Pass to Best Teammate (Key: Z)",
        Callback = function()
            executeAutoPass()
        end,
    })

    -- Goalkeeper Tab
    local GKTab = Window:CreateTab("Goalkeeper", 4483362458)
    GKTab:CreateSection("Auto Goalkeeper (GK)")

    GKTab:CreateToggle({
        Name = "Enable Auto Goalkeeper",
        CurrentValue = settings.autoGoalkeeper,
        Flag = "Soccer_AutoGK",
        Callback = function(value)
            settings.autoGoalkeeper = value
        end,
    })

    GKTab:CreateToggle({
        Name = "Auto Positioning (Track Ball)",
        CurrentValue = settings.gkAutoPosition,
        Flag = "Soccer_GKPosition",
        Callback = function(value)
            settings.gkAutoPosition = value
        end,
    })

    GKTab:CreateToggle({
        Name = "Auto Dive (Save Shots)",
        CurrentValue = settings.gkAutoDive,
        Flag = "Soccer_GKDive",
        Callback = function(value)
            settings.gkAutoDive = value
        end,
    })

    GKTab:CreateToggle({
        Name = "Auto Punch / Clear Ball",
        CurrentValue = settings.gkAutoPunch,
        Flag = "Soccer_GKPunch",
        Callback = function(value)
            settings.gkAutoPunch = value
        end,
    })

    GKTab:CreateSection("Tuning")

    GKTab:CreateSlider({
        Name = "Dive Reach Distance",
        Range = {10, 35},
        Increment = 1,
        CurrentValue = settings.gkDiveReach,
        Flag = "Soccer_GKDiveReach",
        Callback = function(value)
            settings.gkDiveReach = value
        end,
    })

    -- Visual Tab
    local VisualTab = Window:CreateTab("Visuals", 4483362458)
    VisualTab:CreateSection("ESP Options")

    VisualTab:CreateToggle({
        Name = "Ball ESP (⚽ Gold Marker)",
        CurrentValue = settings.ballEsp,
        Flag = "Soccer_BallESP",
        Callback = function(value)
            settings.ballEsp = value
            if not value then clearEspEntry("Ball_Main") end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Goal ESP (🥅 Net Marker)",
        CurrentValue = settings.goalEsp,
        Flag = "Soccer_GoalESP",
        Callback = function(value)
            settings.goalEsp = value
            if not value then
                clearEspEntry("Goal_Team1")
                clearEspEntry("Goal_Team2")
            end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player ESP (Jersey Colors)",
        CurrentValue = settings.playerEsp,
        Flag = "Soccer_PlayerESP",
        Callback = function(value)
            settings.playerEsp = value
            if not value then
                for id, _ in pairs(espObjects) do
                    if string.sub(id, 1, 7) == "Player_" then clearEspEntry(id) end
                end
            end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = settings.playerEspShowDistance,
        Flag = "Soccer_ESPDist",
        Callback = function(value)
            settings.playerEspShowDistance = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Show Health",
        CurrentValue = settings.playerEspShowHealth,
        Flag = "Soccer_ESPHealth",
        Callback = function(value)
            settings.playerEspShowHealth = value
        end,
    })

    VisualTab:CreateSection("World & Camera")

    VisualTab:CreateToggle({
        Name = "Fullbright (No Shadows)",
        CurrentValue = settings.fullbright,
        Flag = "Soccer_Fullbright",
        Callback = function(value)
            settings.fullbright = value
            applyFullbright(value)
        end,
    })

    VisualTab:CreateSlider({
        Name = "Field Of View",
        Range = {70, 120},
        Increment = 1,
        CurrentValue = camera.FieldOfView,
        Flag = "Soccer_FOV",
        Callback = function(value)
            settings.fieldOfView = value
            if camera then camera.FieldOfView = value end
        end,
    })

    -- Misc Tab
    local MiscTab = Window:CreateTab("Misc", 4483362458)
    MiscTab:CreateSection("Server Utilities")

    MiscTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            pcall(function()
                game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, localPlayer)
            end)
        end,
    })

    MiscTab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            pcall(function()
                game:GetService("TeleportService"):Teleport(game.PlaceId, localPlayer)
            end)
        end,
    })

    -- Cleanup Handler
    local function destroyScript()
        if not running then return end
        running = false

        restoreStaminaState()
        restoreMovementEnhancements()
        applyFullbright(false)
        clearAllEsp()

        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end
end
