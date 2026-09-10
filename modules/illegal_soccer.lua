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
        gkPredictArc = true,
        gkAutoJump = true,
        gkAutoPunch = false,
        gkDiveReach = 32,
        gkOpHitbox = true,
        gkInstantDive = true,
        gkAssistMagnet = true,
        gkFastRecovery = true,
        noBallSlowdown = true,
        fullSpeedCharge = true,
        instantCharge = true,
        autoPass = true,
        magneticPass = true,
        autoDribble = true,
        dribbleDistance = 18,
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
    --   GOALKEEPER AUTOMATION & BALL RESOLUTION ENGINE
    -- ============================================================
    local Renderer = nil
    local PracticeSession = nil
    local GoalkeeperRole = nil
    local GoalkeeperPrediction = nil
    local ActorTeams = nil
    local GoalkeeperDive = nil
    local ActionMotion = nil

    pcall(function()
        Renderer = require(ReplicatedStorage.Client.Gameplay.Ball.Renderer)
    end)
    pcall(function()
        PracticeSession = require(ReplicatedStorage.Client.Gameplay.PracticeSession)
    end)
    pcall(function()
        GoalkeeperRole = require(ReplicatedStorage.Client.Gameplay.Player.GoalkeeperRole)
    end)
    pcall(function()
        GoalkeeperPrediction = require(ReplicatedStorage.Modules.Gameplay.GoalkeeperPrediction)
    end)
    pcall(function()
        ActorTeams = require(ReplicatedStorage.Client.Gameplay.ActorTeams)
    end)
    pcall(function()
        GoalkeeperDive = require(ReplicatedStorage.Modules.Actions.GoalkeeperDive)
    end)
    pcall(function()
        ActionMotion = require(ReplicatedStorage.Modules.Actions.ActionMotion)
    end)
    local TurnControl = nil
    pcall(function()
        TurnControl = require(ReplicatedStorage.Client.Gameplay.Player.TurnControl)
    end)
    local GoalkeeperDiveAssist = nil
    pcall(function()
        GoalkeeperDiveAssist = require(ReplicatedStorage.Modules.Actions.GoalkeeperDiveAssist)
    end)
    local BallPhysics = nil
    pcall(function()
        BallPhysics = require(ReplicatedStorage.Modules.Ball.Physics)
    end)
    local HitboxSettingsModule = nil
    pcall(function()
        HitboxSettingsModule = require(ReplicatedStorage.Modules.Gameplay.HitboxSettings)
    end)
    local GoalkeeperActions = nil
    pcall(function()
        GoalkeeperActions = require(ReplicatedStorage.Modules.Actions.GoalkeeperActions)
    end)
    local ActorTargeting = nil
    pcall(function()
        ActorTargeting = require(ReplicatedStorage.Modules.Items.ActorTargeting)
    end)

    -- ============================================================
    --   OP GOALKEEPER ENHANCEMENT ENGINE (HITBOX, COOLDOWN, ASSIST)
    -- ============================================================
    local origAirReceiveSize = nil
    local origAirReceiveOffset = nil
    local origAssistedReceiveSize = nil
    local origReceiveSize = nil
    local origGkDiveConstants = {}
    local origGkAssistConstants = {}

    local function applyGoalkeeperEnhancements()
        if not running then return end

        -- 1. OP Save & Catch Hitboxes (Legit Athletic Vertical Coverage)
        if HitboxSettingsModule then
            if settings.gkOpHitbox then
                if HitboxSettingsModule.AirReceive then
                    if not origAirReceiveSize then origAirReceiveSize = HitboxSettingsModule.AirReceive.Size end
                    if not origAirReceiveOffset then origAirReceiveOffset = HitboxSettingsModule.AirReceive.CFrameOffset end
                    HitboxSettingsModule.AirReceive.Size = Vector3.new(20, 24, 20)
                    HitboxSettingsModule.AirReceive.CFrameOffset = CFrame.new(0, 4, 0)
                end
                if HitboxSettingsModule.AssistedReceive then
                    if not origAssistedReceiveSize then origAssistedReceiveSize = HitboxSettingsModule.AssistedReceive.Size end
                    HitboxSettingsModule.AssistedReceive.Size = Vector3.new(22, 24, 22)
                end
                if HitboxSettingsModule.Receive then
                    if not origReceiveSize then origReceiveSize = HitboxSettingsModule.Receive.Size end
                    HitboxSettingsModule.Receive.Size = Vector3.new(18, 18, 18)
                end
            else
                if origAirReceiveSize and HitboxSettingsModule.AirReceive then
                    HitboxSettingsModule.AirReceive.Size = origAirReceiveSize
                    HitboxSettingsModule.AirReceive.CFrameOffset = origAirReceiveOffset or CFrame.new(0, -0.5, 0)
                end
                if origAssistedReceiveSize and HitboxSettingsModule.AssistedReceive then
                    HitboxSettingsModule.AssistedReceive.Size = origAssistedReceiveSize
                end
                if origReceiveSize and HitboxSettingsModule.Receive then
                    HitboxSettingsModule.Receive.Size = origReceiveSize
                end
            end
        end

        -- 2. Dive Physics & Reach Constants (Legit Pro Goalkeeper Scale)
        if GoalkeeperDive and GoalkeeperDive.Constants then
            local c = GoalkeeperDive.Constants
            if not origGkDiveConstants.MaximumSaveHeight then
                origGkDiveConstants.MaximumSaveHeight = c.MaximumSaveHeight
                origGkDiveConstants.SaveContactPadding = c.SaveContactPadding
                origGkDiveConstants.Distance = c.Distance
                origGkDiveConstants.RepeatDelaySeconds = c.RepeatDelaySeconds
                origGkDiveConstants.CaughtMovementRestoreStartsAtSeconds = c.CaughtMovementRestoreStartsAtSeconds
                origGkDiveConstants.MovementRestoreStartsAtSeconds = c.MovementRestoreStartsAtSeconds
                origGkDiveConstants.InitialVerticalVelocity = c.InitialVerticalVelocity
                origGkDiveConstants.GravityStudsPerSecondSquared = c.GravityStudsPerSecondSquared
            end

            if settings.gkOpHitbox then
                c.MaximumSaveHeight = 22 -- Covers crossbar + 5 studs headroom without flying into orbit
                c.SaveContactPadding = 4
                c.Distance = origGkDiveConstants.Distance or 20
            else
                c.MaximumSaveHeight = origGkDiveConstants.MaximumSaveHeight
                c.SaveContactPadding = origGkDiveConstants.SaveContactPadding
                c.Distance = origGkDiveConstants.Distance
            end

            if settings.gkInstantDive then
                c.RepeatDelaySeconds = 0.35
            else
                c.RepeatDelaySeconds = origGkDiveConstants.RepeatDelaySeconds
            end

            if settings.gkFastRecovery then
                c.CaughtMovementRestoreStartsAtSeconds = 0.12
                c.MovementRestoreStartsAtSeconds = 0.4
            else
                c.CaughtMovementRestoreStartsAtSeconds = origGkDiveConstants.CaughtMovementRestoreStartsAtSeconds
                c.MovementRestoreStartsAtSeconds = origGkDiveConstants.MovementRestoreStartsAtSeconds
            end
        end

        -- 3. Dive Magnet Assist (Natural Athletic Guidance)
        if GoalkeeperDiveAssist and GoalkeeperDiveAssist.Constants then
            local ac = GoalkeeperDiveAssist.Constants
            if not origGkAssistConstants.FullAssistMissStuds then
                origGkAssistConstants.FullAssistMissStuds = ac.FullAssistMissStuds
                origGkAssistConstants.ZeroAssistMissStuds = ac.ZeroAssistMissStuds
                origGkAssistConstants.MaximumAssistDistance = ac.MaximumAssistDistance
                origGkAssistConstants.MaximumExtraReachStuds = ac.MaximumExtraReachStuds
                origGkAssistConstants.MaximumTravelScale = ac.MaximumTravelScale
                origGkAssistConstants.MaximumYawDegrees = ac.MaximumYawDegrees
                origGkAssistConstants.MaximumVerticalVelocityChange = ac.MaximumVerticalVelocityChange
                origGkAssistConstants.HighBallAlignmentDropStuds = ac.HighBallAlignmentDropStuds
                origGkAssistConstants.LiftGravityPerStud = ac.LiftGravityPerStud
            end

            if settings.gkAssistMagnet then
                ac.FullAssistMissStuds = 8
                ac.ZeroAssistMissStuds = 20
                ac.MaximumAssistDistance = 150
                ac.MaximumExtraReachStuds = 4
                ac.MaximumTravelScale = 1.18
                ac.MaximumYawDegrees = 32
                ac.MaximumVerticalVelocityChange = 22
                ac.HighBallAlignmentDropStuds = 1.0
                ac.LiftGravityPerStud = 12
            else
                ac.FullAssistMissStuds = origGkAssistConstants.FullAssistMissStuds
                ac.ZeroAssistMissStuds = origGkAssistConstants.ZeroAssistMissStuds
                ac.MaximumAssistDistance = origGkAssistConstants.MaximumAssistDistance
                ac.MaximumExtraReachStuds = origGkAssistConstants.MaximumExtraReachStuds
                ac.MaximumTravelScale = origGkAssistConstants.MaximumTravelScale
                ac.MaximumYawDegrees = origGkAssistConstants.MaximumYawDegrees
                ac.MaximumVerticalVelocityChange = origGkAssistConstants.MaximumVerticalVelocityChange
                ac.HighBallAlignmentDropStuds = origGkAssistConstants.HighBallAlignmentDropStuds
                ac.LiftGravityPerStud = origGkAssistConstants.LiftGravityPerStud
            end
        end
    end

    local function restoreGoalkeeperEnhancements()
        if HitboxSettingsModule then
            if origAirReceiveSize and HitboxSettingsModule.AirReceive then
                HitboxSettingsModule.AirReceive.Size = origAirReceiveSize
                HitboxSettingsModule.AirReceive.CFrameOffset = origAirReceiveOffset or CFrame.new(0, -0.5, 0)
            end
            if origAssistedReceiveSize and HitboxSettingsModule.AssistedReceive then HitboxSettingsModule.AssistedReceive.Size = origAssistedReceiveSize end
            if origReceiveSize and HitboxSettingsModule.Receive then HitboxSettingsModule.Receive.Size = origReceiveSize end
        end
        if GoalkeeperDive and GoalkeeperDive.Constants and origGkDiveConstants.MaximumSaveHeight then
            local c = GoalkeeperDive.Constants
            c.MaximumSaveHeight = origGkDiveConstants.MaximumSaveHeight
            c.SaveContactPadding = origGkDiveConstants.SaveContactPadding
            c.Distance = origGkDiveConstants.Distance
            c.RepeatDelaySeconds = origGkDiveConstants.RepeatDelaySeconds
            c.CaughtMovementRestoreStartsAtSeconds = origGkDiveConstants.CaughtMovementRestoreStartsAtSeconds
            c.MovementRestoreStartsAtSeconds = origGkDiveConstants.MovementRestoreStartsAtSeconds
            c.InitialVerticalVelocity = origGkDiveConstants.InitialVerticalVelocity
            c.GravityStudsPerSecondSquared = origGkDiveConstants.GravityStudsPerSecondSquared
        end
        if GoalkeeperDiveAssist and GoalkeeperDiveAssist.Constants and origGkAssistConstants.FullAssistMissStuds then
            local ac = GoalkeeperDiveAssist.Constants
            ac.FullAssistMissStuds = origGkAssistConstants.FullAssistMissStuds
            ac.ZeroAssistMissStuds = origGkAssistConstants.ZeroAssistMissStuds
            ac.MaximumAssistDistance = origGkAssistConstants.MaximumAssistDistance
            ac.MaximumExtraReachStuds = origGkAssistConstants.MaximumExtraReachStuds
            ac.MaximumTravelScale = origGkAssistConstants.MaximumTravelScale
            ac.MaximumYawDegrees = origGkAssistConstants.MaximumYawDegrees
            ac.MaximumVerticalVelocityChange = origGkAssistConstants.MaximumVerticalVelocityChange
            ac.HighBallAlignmentDropStuds = origGkAssistConstants.HighBallAlignmentDropStuds
            ac.LiftGravityPerStud = origGkAssistConstants.LiftGravityPerStud
        end
    end

    -- Initial application of Goalkeeper constants
    applyGoalkeeperEnhancements()

    -- Hook GoalkeeperActions.FindDiveSaveContact to remove hardcoded 7.75 MaximumSaveHeight clamp on high balls
    if GoalkeeperActions and type(GoalkeeperActions.FindDiveSaveContact) == "function" then
        local origFindSave = GoalkeeperActions.FindDiveSaveContact
        GoalkeeperActions.FindDiveSaveContact = function(actor, p1, p2, options)
            local root = ActorTargeting and ActorTargeting.GetActorRoot(actor)
            if not root then return origFindSave(actor, p1, p2, options) end
            local AirReceive = HitboxSettingsModule and HitboxSettingsModule.AirReceive
            if not AirReceive then return origFindSave(actor, p1, p2, options) end
            local pad = (not options or options.ContactPadding == nil) and 3.5 or (options.ContactPadding + 2.0)
            local hitbox = {
                CFrameOffset = AirReceive.CFrameOffset,
                Shape = AirReceive.Shape,
                Size = AirReceive.Size + Vector3.new(pad, pad, pad)
            }
            local rootOffset = options and options.RootOffset or Vector3.new(0, 0, 0)
            local alpha = HitboxSettingsModule.GetSegmentEnterAlpha(root, hitbox, p1 - rootOffset, p2 - rootOffset)
            if not alpha then return nil end
            local contactPos = p1:Lerp(p2, alpha)
            -- Allow saves up to 24 studs high without 7.75 clamp!
            if (contactPos.Y - (root.Position.Y + rootOffset.Y)) <= 24 then
                return {
                    Alpha = alpha,
                    Position = contactPos
                }
            end
            return nil
        end
    end

    local forcedDiveChoice = nil
    local forcedWorldDirection = nil
    local forcedDiveUntil = 0

    if GoalkeeperDive and type(GoalkeeperDive.GetDirectionChoice) == "function" then
        local origGetChoice = GoalkeeperDive.GetDirectionChoice
        GoalkeeperDive.GetDirectionChoice = function(moveVec, camCF, lookVec)
            if forcedDiveChoice and os.clock() <= forcedDiveUntil then
                local choice = forcedDiveChoice
                return choice
            end
            forcedDiveChoice = nil
            return origGetChoice(moveVec, camCF, lookVec)
        end
    end

    if GoalkeeperDive and type(GoalkeeperDive.GetWorldDirection) == "function" then
        local origGetWorldDir = GoalkeeperDive.GetWorldDirection
        GoalkeeperDive.GetWorldDirection = function(choice, camCF, fallbackLook)
            if forcedWorldDirection and os.clock() <= forcedDiveUntil then
                return forcedWorldDirection
            end
            return origGetWorldDir(choice, camCF, fallbackLook)
        end
    end

    -- Hook TurnControl.HasAutoRotateLock so performDive does not force "F" when diving backwards or laterally
    if TurnControl and type(TurnControl.HasAutoRotateLock) == "function" then
        local origHasLock = TurnControl.HasAutoRotateLock
        TurnControl.HasAutoRotateLock = function(...)
            if forcedDiveChoice and os.clock() <= forcedDiveUntil then
                return true
            end
            return origHasLock(...)
        end
    end

    local lastDiveTime = 0
    local lastPunchTime = 0
    local lastBallPos = nil
    local lastBallPosTime = 0
    local lastBallInstance = nil
    local trackedBallVel = Vector3.zero

    local function getActiveBall(rootPos)
        -- Priority 1: Game's authoritative Ball Renderer
        if Renderer and type(Renderer.GetBall) == "function" then
            local s, b = pcall(Renderer.GetBall)
            if s and b and b:IsA("BasePart") and b.Parent then
                return b
            end
        end

        local visuals = workspace:FindFirstChild("Misc") and workspace.Misc:FindFirstChild("Visuals")
        if not visuals then return nil end

        -- Priority 2: Practice Session local ball
        if PracticeSession and type(PracticeSession.IsActive) == "function" and PracticeSession.IsActive() then
            local sId, pId = pcall(PracticeSession.GetLocalPracticeBallId)
            if sId and pId then
                local pBall = visuals:FindFirstChild("ClientBall_" .. tostring(pId))
                if pBall and pBall:IsA("BasePart") then return pBall end
            end
        end

        -- Priority 3: Main match ball if within reasonable range
        local mainBall = visuals:FindFirstChild("ClientBall_MainMatch")
        if mainBall and mainBall:IsA("BasePart") then
            if not rootPos or (mainBall.Position - rootPos).Magnitude < 350 then
                return mainBall
            end
        end

        -- Priority 4: Closest ball part in Visuals
        local bestBall = nil
        local bestDist = math.huge
        for _, child in ipairs(visuals:GetChildren()) do
            if child:IsA("BasePart") and string.find(string.lower(child.Name), "ball") then
                local d = rootPos and (child.Position - rootPos).Magnitude or 0
                if d < bestDist then
                    bestDist = d
                    bestBall = child
                end
            end
        end
        return bestBall
    end

    local function getDefendedGoalInfo(rootPos)
        local isPractice = false
        if PracticeSession and type(PracticeSession.IsActive) == "function" then
            pcall(function() isPractice = PracticeSession.IsActive() end)
        end
        if not isPractice and rootPos and rootPos.X > 300 then
            isPractice = true
        end

        if isPractice then
            -- Practice Mode (Defense Goal in Lobby)
            local defGoal = nil
            if PracticeSession and type(PracticeSession.GetDefendedGoalPart) == "function" then
                pcall(function() defGoal = PracticeSession.GetDefendedGoalPart() end)
            end
            if not defGoal then
                local lobby = workspace:FindFirstChild("Lobby")
                defGoal = lobby and lobby:FindFirstChild("Practice")
                    and lobby.Practice:FindFirstChild("Goals")
                    and lobby.Practice.Goals:FindFirstChild("Defence")
                    and lobby.Practice.Goals.Defence:FindFirstChild("Goal")
            end

            local goalPos = defGoal and defGoal.Position or Vector3.new(583.5, 39.2, -0.2)
            -- goalForward points OUTWARDS from the goal toward the field (away from net)
            local goalForward = Vector3.new(-1, 0, 0)
            local goalRight = Vector3.new(0, 0, 1)

            local homePart = workspace:FindFirstChild("Lobby") and workspace.Lobby:FindFirstChild("Practice") and workspace.Lobby.Practice:FindFirstChild("Goalkeeper")
            local homePos = homePart and homePart.Position or Vector3.new(574.2, 34.0, -0.3)

            return goalPos, goalForward, goalRight, homePos, true
        else
            -- Main Match Stadium Mode
            local mapData = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Data")
            local teamName = nil
            if ActorTeams and type(ActorTeams.GetCharacterTeamName) == "function" then
                pcall(function() teamName = ActorTeams.GetCharacterTeamName(localPlayer.Character) end)
            end
            if not teamName and localPlayer.Team then
                teamName = localPlayer.Team.Name
            end
            if not teamName and rootPos then
                local t1Dist = (rootPos - Vector3.new(0, 7, -155)).Magnitude
                local t2Dist = (rootPos - Vector3.new(0, 7, 155)).Magnitude
                teamName = (t2Dist < t1Dist) and "Team2" or "Team1"
            end

            if teamName == "Team2" then
                local goalPart = mapData and mapData:FindFirstChild("Team2") and mapData.Team2:FindFirstChild("Goal")
                local goalPos = goalPart and goalPart.Position or Vector3.new(0, 7, 155)
                local goalForward = Vector3.new(0, 0, -1)
                local goalRight = Vector3.new(-1, 0, 0)
                local homePart = mapData and mapData:FindFirstChild("Team2") and mapData.Team2:FindFirstChild("Positions") and mapData.Team2.Positions:FindFirstChild("Goalkeeper")
                local homePos = homePart and homePart.Position or Vector3.new(0, 1.5, 145.5)
                return goalPos, goalForward, goalRight, homePos, false
            else
                local goalPart = mapData and mapData:FindFirstChild("Team1") and mapData.Team1:FindFirstChild("Goal")
                local goalPos = goalPart and goalPart.Position or Vector3.new(0, 7, -155)
                local goalForward = Vector3.new(0, 0, 1)
                local goalRight = Vector3.new(1, 0, 0)
                local homePart = mapData and mapData:FindFirstChild("Team1") and mapData.Team1:FindFirstChild("Positions") and mapData.Team1.Positions:FindFirstChild("Goalkeeper")
                local homePos = homePart and homePart.Position or Vector3.new(0, 1.5, -145.5)
                return goalPos, goalForward, goalRight, homePos, false
            end
        end
    end

    local function triggerDive(targetLookPos, isHighShot, targetDist)
        local char = localPlayer.Character
        local root = getRoot(char)
        local hum = getHumanoid(char)
        if not root or not hum then return false end

        local cam = workspace.CurrentCamera
        local camCF = cam and cam.CFrame or root.CFrame
        local camFlatForward = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
        if camFlatForward.Magnitude > 0.01 then
            camFlatForward = camFlatForward.Unit
        else
            camFlatForward = Vector3.new(0, 0, 1)
        end
        local camFlatRight = Vector3.new(-camFlatForward.Z, 0, camFlatForward.X)

        -- Calculate exact flat vector from keeper root to target intercept position
        local toTarget = targetLookPos - root.Position
        local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
        local dist = targetDist or flatToTarget.Magnitude
        local targetDir = (flatToTarget.Magnitude > 0.05) and flatToTarget.Unit or camFlatForward

        -- Mathematical lock: inject exact direction into GoalkeeperDive hook
        forcedWorldDirection = targetDir
        forcedDiveUntil = os.clock() + 0.60

        -- Dynamic dive distance & legit athletic vertical leap adaptation
        local diffY = targetLookPos.Y - root.Position.Y
        if GoalkeeperDive and GoalkeeperDive.Constants then
            local desiredDist = math.clamp(dist + 2.0, 14, 24)
            GoalkeeperDive.Constants.Distance = desiredDist
            if isHighShot or diffY > 1.2 then
                -- Ball is elevated: athletic vertical leap matching crossbar apex with natural gravity
                local athleticVel = math.clamp(math.sqrt(2 * 65 * math.min(diffY, 7.5)) + 4, 18, 30)
                GoalkeeperDive.Constants.InitialVerticalVelocity = athleticVel
                GoalkeeperDive.Constants.GravityStudsPerSecondSquared = -65 -- Natural realistic gravity (zero floating)
            else
                GoalkeeperDive.Constants.InitialVerticalVelocity = origGkDiveConstants.InitialVerticalVelocity or 15
                GoalkeeperDive.Constants.GravityStudsPerSecondSquared = origGkDiveConstants.GravityStudsPerSecondSquared or -65
            end
        end

        -- Project target direction onto camera plane to find relative direction (F, L, R, LF, RF)
        local forwardDot = targetDir:Dot(camFlatForward)
        local rightDot = targetDir:Dot(camFlatRight)

        local dirName = "F"
        if math.abs(rightDot) > 0.35 then
            if forwardDot > 0.35 then
                dirName = (rightDot > 0) and "RF" or "LF"
            else
                dirName = (rightDot > 0) and "R" or "L"
            end
        else
            dirName = "F"
        end

        -- Prime the game's direction choice
        if GoalkeeperDive and type(GoalkeeperDive.GetDirectionChoiceByName) == "function" then
            pcall(function()
                forcedDiveChoice = GoalkeeperDive.GetDirectionChoiceByName(dirName)
            end)
        end

        -- Physically snap root orientation directly facing intercept vector
        pcall(function()
            root.CFrame = CFrame.lookAt(root.Position, root.Position + targetDir)
        end)

        -- Set humanoid movement towards target so native move direction aligns
        pcall(function()
            hum:Move(targetDir, false)
        end)

        -- If ball is elevated, trigger jump concurrently with dive so character achieves maximum vertical reach instantly
        if isHighShot and settings.gkAutoJump then
            pcall(function()
                hum.Jump = true
            end)
        end

        -- Execute dive: prioritize native GoalkeeperRole.Dive(), fallback to inputs
        local triggered = false
        if GoalkeeperRole and type(GoalkeeperRole.Dive) == "function" then
            pcall(function() triggered = GoalkeeperRole.Dive() end)
        end
        if not triggered and type(mouse2click) == "function" then
            local s = pcall(mouse2click)
            if s then triggered = true end
        end
        if not triggered and type(keyclick) == "function" then
            pcall(function() keyclick(Enum.KeyCode.E.Value); triggered = true end)
        end
        if not triggered and type(keypress) == "function" then
            pcall(function()
                keypress(0x45)
                task.delay(0.05, function() pcall(keyrelease, 0x45) end)
                triggered = true
            end)
        end
        if not triggered then
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.delay(0.05, function() vim:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
                triggered = true
            end)
        end

        -- Clean up movement direction and restore dive physics constants after impulse
        task.delay(0.65, function()
            pcall(function()
                hum:Move(Vector3.zero, false)
                if GoalkeeperDive and GoalkeeperDive.Constants and origGkDiveConstants.InitialVerticalVelocity then
                    GoalkeeperDive.Constants.InitialVerticalVelocity = origGkDiveConstants.InitialVerticalVelocity
                    GoalkeeperDive.Constants.GravityStudsPerSecondSquared = origGkDiveConstants.GravityStudsPerSecondSquared
                end
            end)
        end)

        return triggered
    end

    local function triggerPunch(targetLookPos)
        local char = localPlayer.Character
        local root = getRoot(char)
        if root and targetLookPos then
            pcall(function()
                root.CFrame = CFrame.lookAt(root.Position, Vector3.new(targetLookPos.X, root.Position.Y, targetLookPos.Z))
            end)
        end

        local triggered = false
        if type(mouse1click) == "function" then
            local s = pcall(mouse1click)
            if s then triggered = true end
        end
        if not triggered then
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                task.delay(0.05, function() vim:SendMouseButtonEvent(0, 0, 0, false, game, 1) end)
                triggered = true
            end)
        end
        return triggered
    end

    local function updateAutoGoalkeeper()
        if not running or not settings.autoGoalkeeper then return end
        local char = localPlayer.Character
        local root = getRoot(char)
        local hum = getHumanoid(char)
        if not root or not hum or hum.Health <= 0 then return end

        local ball = getActiveBall(root.Position)
        if not ball or not ball:IsA("BasePart") then return end

        local ballPos = ball.Position
        local now = os.clock()

        -- Reset delta velocity if ball instance changed
        if lastBallInstance ~= ball then
            lastBallInstance = ball
            lastBallPos = ballPos
            lastBallPosTime = now
            trackedBallVel = Vector3.zero
        elseif lastBallPos and lastBallPosTime > 0 then
            local dt = now - lastBallPosTime
            if dt > 0.005 and dt < 0.25 then
                local rawVel = (ballPos - lastBallPos) / dt
                if rawVel.Magnitude > 1.5 then
                    trackedBallVel = rawVel
                else
                    trackedBallVel = trackedBallVel * 0.75
                end
            end
            lastBallPos = ballPos
            lastBallPosTime = now
        else
            lastBallPos = ballPos
            lastBallPosTime = now
        end

        -- Query authoritative physics velocity & movement state
        local ballVel = trackedBallVel
        local ballMovementState = nil
        if Renderer and type(Renderer.GetMovementState) == "function" then
            pcall(function()
                local mv = Renderer.GetMovementState()
                if mv then
                    ballMovementState = mv
                    if mv.Velocity and mv.Velocity.Magnitude > 1.5 then
                        ballVel = mv.Velocity
                    elseif mv.Velocity then
                        ballVel = Vector3.zero
                    end
                end
            end)
        end
        if not ballMovementState and Renderer and type(Renderer.GetAuthoritativeMovementState) == "function" then
            pcall(function()
                local mv = Renderer.GetAuthoritativeMovementState()
                if mv then
                    ballMovementState = mv
                    if mv.Velocity and mv.Velocity.Magnitude > 1.5 then
                        ballVel = mv.Velocity
                    end
                end
            end)
        end

        local distToBall = (ballPos - root.Position).Magnitude
        local ballSpeed = ballVel.Magnitude

        -- Avoid diving if player is already holding / controlling the ball
        if distToBall < 3.2 and ballSpeed < 3.0 then
            return
        end

        local goalPos, goalForward, goalRight, homePos, isPractice = getDefendedGoalInfo(root.Position)

        -- 1. Precision Aerodynamic Plane Crossing (Analytical Solver)
        local netForward = -goalForward
        local forwardSpeed = ballVel:Dot(netForward)
        local distInFrontOfGoal = (ballPos - goalPos):Dot(goalForward)

        local timeToGoal = nil
        if GoalkeeperPrediction and type(GoalkeeperPrediction.GetPlaneTime) == "function" and ballMovementState then
            pcall(function()
                timeToGoal = GoalkeeperPrediction.GetPlaneTime(ballMovementState, goalPos, goalForward, 1.0)
            end)
        end
        if not timeToGoal or timeToGoal <= 0 then
            if forwardSpeed > 1.5 and distInFrontOfGoal > 0.3 then
                timeToGoal = distInFrontOfGoal / forwardSpeed
            end
        end

        -- 2. Exact Goal Crossing Point
        local goalCrossingPos = nil
        local isShotOnGoal = false
        if timeToGoal and timeToGoal > 0 and timeToGoal < 3.5 then
            if GoalkeeperPrediction and type(GoalkeeperPrediction.GetBallPositionAtTime) == "function" and ballMovementState then
                pcall(function()
                    goalCrossingPos = GoalkeeperPrediction.GetBallPositionAtTime(ballMovementState, timeToGoal)
                end)
            end
            if not goalCrossingPos then
                local grav = (BallPhysics and BallPhysics.Gravity) or workspace.Gravity or 65
                goalCrossingPos = ballPos + (ballVel * timeToGoal) - Vector3.new(0, 0.5 * grav * (timeToGoal ^ 2), 0)
            end

            if goalCrossingPos then
                local latOffset = (goalCrossingPos - goalPos):Dot(goalRight)
                local vertOffset = goalCrossingPos.Y - goalPos.Y
                -- Goal bounds: +-23.5 studs lateral, -1.5 to 19 studs height (covers crossbar and upper 90)
                if math.abs(latOffset) <= 23.5 and vertOffset >= -1.5 and vertOffset <= 19 then
                    isShotOnGoal = true
                end
            end
        end

        -- 3. In-Flight Trajectory Sampling (Find earliest reachable 3D point along curve)
        local chosenInterceptPos = goalCrossingPos
        local chosenArrivalTime = timeToGoal or 999
        local canInterceptInFlight = false

        local maxScanTime = timeToGoal and math.min(timeToGoal, 1.6) or 1.3
        if ballSpeed > 12 and forwardSpeed > 1.0 then
            local scanSteps = math.clamp(math.floor(maxScanTime / 0.05), 2, 26)
            for step = 1, scanSteps do
                local t = step * 0.05
                local samplePos = nil
                if GoalkeeperPrediction and type(GoalkeeperPrediction.GetBallPositionAtTime) == "function" and ballMovementState then
                    pcall(function()
                        samplePos = GoalkeeperPrediction.GetBallPositionAtTime(ballMovementState, t)
                    end)
                end
                if not samplePos then
                    local grav = (BallPhysics and BallPhysics.Gravity) or 65
                    samplePos = ballPos + (ballVel * t) - Vector3.new(0, 0.5 * grav * (t ^ 2), 0)
                end

                local sampleDist = (samplePos - root.Position).Magnitude
                local vertDiff = samplePos.Y - root.Position.Y
                local estTransit = math.clamp(sampleDist / 30, 0.10, 0.65)

                if sampleDist <= (settings.gkDiveReach + 6) and vertDiff >= -2 and vertDiff <= 18 then
                    if t >= (estTransit - 0.08) then
                        chosenInterceptPos = samplePos
                        chosenArrivalTime = t
                        canInterceptInFlight = true
                        break
                    end
                end
            end
        end

        -- 4. Shot Interception Assessment
        local isShotIncoming = (isShotOnGoal or canInterceptInFlight) and (chosenInterceptPos ~= nil)
        local targetIntercept = chosenInterceptPos

        -- 5. Auto Dive / Save incoming shot (Synchronized Arrival Execution)
        if settings.gkAutoDive and isShotIncoming and targetIntercept then
            local interceptDist = (targetIntercept - root.Position).Magnitude
            local diveTransitTime = math.clamp(interceptDist / 30, 0.12, 0.62)
            local arrivalTime = chosenArrivalTime or 0.45
            local isHighShot = (targetIntercept.Y - root.Position.Y > 1.2) or (ballPos.Y - root.Position.Y > 1.8)

            -- Synchronization: dive ONLY when transit time matches arrival time!
            -- timeDiff > 0.18 means ball is still too far; do not dive prematurely!
            local timeDiff = arrivalTime - diveTransitTime
            local shouldTriggerNow = (timeDiff <= 0.18) or (interceptDist <= 7.0 and arrivalTime <= 0.40)

            if shouldTriggerNow then
                local diveCooldown = settings.gkInstantDive and 0.35 or 0.95
                if (now - lastDiveTime) > diveCooldown then
                    lastDiveTime = now
                    triggerDive(targetIntercept, isHighShot, interceptDist)
                    return
                end
            else
                -- Angle Cutting & Staging: Strafe/move on foot toward intercept line while waiting
                local stagingPos = Vector3.new(targetIntercept.X, root.Position.Y, targetIntercept.Z)
                if (root.Position - stagingPos).Magnitude > 0.8 then
                    hum:MoveTo(stagingPos)
                end
            end
        end

        -- 6. Auto Punch / Clear loose ball
        if settings.gkAutoPunch and distToBall <= 12 and (now - lastPunchTime) > 0.38 then
            lastPunchTime = now
            triggerPunch(ballPos)
            return
        end

        -- 7. Auto Positioning along the net (Magnetic net guarding & angle cutting)
        if settings.gkAutoPosition and not isShotIncoming then
            local ballLateral = (ballPos - homePos):Dot(goalRight)
            local keeperLateral = math.clamp(ballLateral * 0.75, -17, 17)
            local keeperDepth = math.clamp((45 - distToBall) * 0.12, 0, 5.5)

            local targetPos = homePos + (goalRight * keeperLateral) + (goalForward * keeperDepth)
            if (root.Position - targetPos).Magnitude > 0.9 then
                hum:MoveTo(targetPos)
            end
        end
    end

    -- ============================================================
    --   AUTO DRIBBLE / ANTI-TACKLE ENGINE
    -- ============================================================
    local ActionRemoteProtocol = nil
    local ActionCommands = nil
    local DodgeModule = nil
    local ControlsModule = nil
    pcall(function()
        ActionRemoteProtocol = require(ReplicatedStorage.Modules.Actions.ActionRemoteProtocol)
    end)
    pcall(function()
        ActionCommands = require(ReplicatedStorage.Modules.Actions.ActionCommands)
    end)
    pcall(function()
        DodgeModule = require(ReplicatedStorage.Modules.Actions.Dodge)
    end)
    pcall(function()
        ControlsModule = require(ReplicatedStorage.Modules.Gameplay.Controls)
    end)

    local lastDribbleTime = 0

    local function executeDribble(evadeDir)
        local myChar = localPlayer.Character
        local myRoot = getRoot(myChar)
        local now = workspace:GetServerTimeNow()
        local aimDir = evadeDir or (myRoot and myRoot.CFrame.LookVector) or Vector3.new(0, 0, 1)
        if aimDir.Magnitude > 0.01 then
            aimDir = aimDir.Unit
        end

        -- 1. Send network Dodge action if protocol available
        if ActionRemoteProtocol and ActionCommands and type(ActionCommands.Dodge) == "function" then
            pcall(function()
                local cmd = ActionCommands.Dodge()
                ActionRemoteProtocol.Send(cmd, {
                    AimDirection = aimDir,
                    ShotTime = now
                })
            end)
        end

        -- 2. Trigger native input key (Space) for local animation, audio & speed boost
        if type(keypress) == "function" then
            pcall(keypress, 0x20)
            task.delay(0.05, function() pcall(keyrelease, 0x20) end)
        elseif type(keyclick) == "function" then
            pcall(keyclick, Enum.KeyCode.Space.Value)
        else
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
                task.delay(0.05, function()
                    vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                end)
            end)
        end
    end

    local function updateAutoDribble()
        if not running or not settings.autoDribble then return end
        local myChar = localPlayer.Character
        local myRoot = getRoot(myChar)
        local myHum = getHumanoid(myChar)
        if not myRoot or not myHum or myHum.Health <= 0 then return end

        local nowClock = os.clock()
        if (nowClock - lastDribbleTime) < 1.0 then return end

        -- Check if already dribbling
        if DodgeModule and type(DodgeModule.IsDribbling) == "function" then
            local isDribbling = false
            pcall(function() isDribbling = DodgeModule.IsDribbling(myChar) end)
            if isDribbling then return end
        end

        -- Identify team color for enemy differentiation
        local myJersey = myChar:FindFirstChild("TeamJersey")
        local myColor = myJersey and myJersey:FindFirstChild("Handle") and myJersey.Handle.Color

        local charFolder = workspace:FindFirstChild("Characters") and workspace.Characters:FindFirstChild("Players")
        local enemyTackling = false
        local evadeDir = nil

        local function checkEnemy(char)
            if not char or char == myChar then return end
            local enemyRoot = getRoot(char)
            local enemyHum = getHumanoid(char)
            if not enemyRoot or not enemyHum or enemyHum.Health <= 0 then return end

            -- Team check: Ignore teammates
            local enemyJersey = char:FindFirstChild("TeamJersey")
            local enemyColor = enemyJersey and enemyJersey:FindFirstChild("Handle") and enemyJersey.Handle.Color
            if myColor and enemyColor then
                local diff = math.abs(myColor.R - enemyColor.R) + math.abs(myColor.G - enemyColor.G) + math.abs(myColor.B - enemyColor.B)
                if diff < 0.1 then return end -- Teammate
            end

            local toMe = myRoot.Position - enemyRoot.Position
            local dist = toMe.Magnitude
            if dist > settings.dribbleDistance then return end

            local nowServer = workspace:GetServerTimeNow()
            local slidingUntil = char:GetAttribute("SlidingUntil")
            local isSliding = slidingUntil and (tonumber(slidingUntil) > nowServer)

            -- Check if enemy is charging/rushing towards us
            local enemyVel = enemyRoot.AssemblyLinearVelocity
            local isRushingAtMe = false
            if dist <= 14 and enemyVel.Magnitude > 12 then
                local approachSpeed = enemyVel:Dot(toMe.Unit)
                if approachSpeed > 10 then
                    isRushingAtMe = true
                end
            end

            if isSliding or isRushingAtMe then
                enemyTackling = true
                -- Calculate perpendicular escape vector (left or right relative to enemy attack vector)
                local flatAttack = Vector3.new(toMe.X, 0, toMe.Z)
                if flatAttack.Magnitude > 0.01 then
                    flatAttack = flatAttack.Unit
                else
                    flatAttack = Vector3.new(0, 0, 1)
                end
                local leftEvade = Vector3.new(-flatAttack.Z, 0, flatAttack.X)
                local rightEvade = Vector3.new(flatAttack.Z, 0, -flatAttack.X)

                -- Prefer dodge direction aligning with player current movement
                local moveDir = myHum.MoveDirection
                if moveDir.Magnitude > 0.1 and moveDir:Dot(leftEvade) > moveDir:Dot(rightEvade) then
                    evadeDir = leftEvade
                else
                    evadeDir = rightEvade
                end
            end
        end

        if charFolder then
            for _, char in ipairs(charFolder:GetChildren()) do
                if enemyTackling then break end
                checkEnemy(char)
            end
        end

        if not enemyTackling then
            for _, p in ipairs(Players:GetPlayers()) do
                if enemyTackling then break end
                if p ~= localPlayer and p.Character then
                    checkEnemy(p.Character)
                end
            end
        end

        if enemyTackling then
            lastDribbleTime = nowClock
            executeDribble(evadeDir)
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

        -- Auto Dribble / Anti-Tackle update
        if settings.autoDribble then
            updateAutoDribble()
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
            local ball = getActiveBall(myPos)
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
            local isPractice = (PracticeSession and PracticeSession.IsActive and PracticeSession.IsActive()) or (myPos.X > 300)
            if isPractice then
                local lobby = workspace:FindFirstChild("Lobby")
                local pGoals = lobby and lobby:FindFirstChild("Practice") and lobby.Practice:FindFirstChild("Goals")
                if pGoals then
                    for _, side in ipairs({"Defence", "Offense"}) do
                        local sideFolder = pGoals:FindFirstChild(side)
                        local goal = sideFolder and sideFolder:FindFirstChild("Goal")
                        local id = "Goal_Practice_" .. side
                        if goal and goal:IsA("BasePart") then
                            local dist = math.floor((goal.Position - myPos).Magnitude)
                            local col = (side == "Defence") and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(255, 85, 85)
                            if not espObjects[id] then
                                local bb, lbl = createBillboard(id, goal, col, "🥅 " .. side .. " Goal", Vector3.new(0, 6, 0))
                                espObjects[id] = { billboard = bb, label = lbl }
                            else
                                espObjects[id].label.Text = string.format("🥅 <b>%s Goal</b>\n<font size='11' color='#FFFFFF'>[%d studs]</font>", side, dist)
                            end
                        else
                            clearEspEntry(id)
                        end
                    end
                end
            else
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
            end
        else
            clearEspEntry("Goal_Team1")
            clearEspEntry("Goal_Team2")
            clearEspEntry("Goal_Practice_Defence")
            clearEspEntry("Goal_Practice_Offense")
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

    MainTab:CreateSection("Dribble & Evasion")

    MainTab:CreateToggle({
        Name = "Auto Dribble / Anti-Tackle",
        CurrentValue = settings.autoDribble,
        Flag = "Soccer_AutoDribble",
        Callback = function(value)
            settings.autoDribble = value
        end,
    })

    MainTab:CreateSlider({
        Name = "Anti-Tackle Detection Range",
        Range = {10, 30},
        Increment = 1,
        CurrentValue = settings.dribbleDistance,
        Flag = "Soccer_DribbleDistance",
        Callback = function(value)
            settings.dribbleDistance = value
        end,
    })

    MainTab:CreateButton({
        Name = "Manual Dribble / Dodge (Space)",
        Callback = function()
            executeDribble()
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
        Name = "Predict Ball Arc (Parabolic Gravity)",
        CurrentValue = settings.gkPredictArc,
        Flag = "Soccer_GKPredictArc",
        Callback = function(value)
            settings.gkPredictArc = value
        end,
    })

    GKTab:CreateToggle({
        Name = "Auto Jump on High Balls",
        CurrentValue = settings.gkAutoJump,
        Flag = "Soccer_GKAutoJump",
        Callback = function(value)
            settings.gkAutoJump = value
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

    GKTab:CreateSection("OP Enhancements (Unstoppable)")

    GKTab:CreateToggle({
        Name = "OP Hitbox & Super Reach",
        CurrentValue = settings.gkOpHitbox,
        Flag = "Soccer_GKOpHitbox",
        Callback = function(value)
            settings.gkOpHitbox = value
            applyGoalkeeperEnhancements()
        end,
    })

    GKTab:CreateToggle({
        Name = "Instant Dive / Zero Cooldown",
        CurrentValue = settings.gkInstantDive,
        Flag = "Soccer_GKInstantDive",
        Callback = function(value)
            settings.gkInstantDive = value
            applyGoalkeeperEnhancements()
        end,
    })

    GKTab:CreateToggle({
        Name = "Dive Magnet Assist (Auto-Curve)",
        CurrentValue = settings.gkAssistMagnet,
        Flag = "Soccer_GKAssistMagnet",
        Callback = function(value)
            settings.gkAssistMagnet = value
            applyGoalkeeperEnhancements()
        end,
    })

    GKTab:CreateToggle({
        Name = "Fast Recovery (Instant Getup)",
        CurrentValue = settings.gkFastRecovery,
        Flag = "Soccer_GKFastRecovery",
        Callback = function(value)
            settings.gkFastRecovery = value
            applyGoalkeeperEnhancements()
        end,
    })

    GKTab:CreateSection("Tuning")

    GKTab:CreateSlider({
        Name = "Dive Reach Distance",
        Range = {10, 50},
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
        restoreGoalkeeperEnhancements()
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
