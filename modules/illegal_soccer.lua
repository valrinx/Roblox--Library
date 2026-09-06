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
        gkDiveReach = 22,
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

    -- Modestly expand AirReceive hitbox for Goalkeeper so saves register cleanly upon contact
    local origAirReceiveSize = nil
    if HitboxSettingsModule and HitboxSettingsModule.AirReceive then
        origAirReceiveSize = HitboxSettingsModule.AirReceive.Size
        HitboxSettingsModule.AirReceive.Size = Vector3.new(8, 10, 8)
    end

    local forcedDiveChoice = nil
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

    local function triggerDive(targetLookPos, isHighShot)
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

        -- Calculate flat directional vector from keeper to target intercept position
        local toTarget = targetLookPos - root.Position
        local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
        local targetDir = camFlatForward
        if flatToTarget.Magnitude > 0.1 then
            targetDir = flatToTarget.Unit
        end

        -- Project target direction onto camera plane to find relative dive direction (L, R, LF, RF, F, B, LB, RB)
        local forwardDot = targetDir:Dot(camFlatForward)
        local rightDot = targetDir:Dot(camFlatRight)

        local dirName = "F"
        if ActionMotion and type(ActionMotion.GetDirectionName) == "function" then
            pcall(function()
                dirName = ActionMotion.GetDirectionName(forwardDot, rightDot)
            end)
            if string.find(dirName, "B") then
                if string.find(dirName, "R") then
                    dirName = "R"
                elseif string.find(dirName, "L") then
                    dirName = "L"
                else
                    dirName = "F"
                end
            end
        else
            if math.abs(rightDot) > 0.38 then
                if forwardDot > 0.38 then
                    dirName = (rightDot > 0) and "RF" or "LF"
                else
                    dirName = (rightDot > 0) and "R" or "L"
                end
            else
                dirName = "F"
            end
        end

        -- Prime the game's dive direction choice
        forcedDiveUntil = os.clock() + 0.35
        if GoalkeeperDive and type(GoalkeeperDive.GetDirectionChoiceByName) == "function" then
            pcall(function()
                forcedDiveChoice = GoalkeeperDive.GetDirectionChoiceByName(dirName)
            end)
        end

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

        -- Execute dive
        local triggered = false
        if type(mouse2click) == "function" then
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
        if not triggered and GoalkeeperRole and type(GoalkeeperRole.Dive) == "function" then
            pcall(function() triggered = GoalkeeperRole.Dive() end)
        end
        if not triggered then
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.delay(0.05, function() vim:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
            end)
        end

        -- Clean up movement direction after brief impulse
        task.delay(0.18, function()
            pcall(function()
                hum:Move(Vector3.zero, false)
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
                if rawVel.Magnitude > 3.0 then
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

        -- Query authoritative physics velocity if available
        local ballVel = trackedBallVel
        if Renderer and type(Renderer.GetMovementState) == "function" then
            pcall(function()
                local mv = Renderer.GetMovementState()
                if mv and mv.Velocity then
                    if mv.Velocity.Magnitude > 3.0 then
                        ballVel = mv.Velocity
                    else
                        ballVel = Vector3.zero
                    end
                end
            end)
        end

        local goalPos, goalForward, goalRight, homePos, isPractice = getDefendedGoalInfo(root.Position)
        local distToBall = (ballPos - root.Position).Magnitude
        local ballSpeed = ballVel.Magnitude

        -- Shot Prediction Vector Mathematics & Parabolic Trajectory
        -- forwardSpeed is positive when ball is actively flying TOWARDS the defended net
        -- In Practice: goalPos.X ~ 583.5, keeper ~ 572, field is towards -X (goalForward = (-1, 0, 0)), so towards net is +X (-goalForward)
        local netForward = -goalForward
        local forwardSpeed = ballVel:Dot(netForward)

        -- Distance along net axis from ball to goal line (positive when ball is on the field in front of goal)
        local distInFrontOfGoal = (ballPos - goalPos):Dot(goalForward)
        local timeToGoal = (forwardSpeed > 5.0 and distInFrontOfGoal > 1.2) and (distInFrontOfGoal / forwardSpeed) or 999

        -- Estimated intercept time strictly based on arrival at defended goal line
        local estInterceptTime = timeToGoal
        local interceptPos
        if settings.gkPredictArc and estInterceptTime > 0 and estInterceptTime < 2.5 then
            local grav = (BallPhysics and BallPhysics.Gravity) or workspace.Gravity or 65
            local vertDrop = 0.5 * grav * (estInterceptTime ^ 2)
            interceptPos = ballPos + (ballVel * estInterceptTime) - Vector3.new(0, vertDrop, 0)
        else
            interceptPos = ballPos + (ballVel * (estInterceptTime < 999 and estInterceptTime or 0))
        end

        local lateralOffset = (interceptPos - goalPos):Dot(goalRight)
        local interceptDist = (interceptPos - root.Position).Magnitude
        local isHighShot = (interceptPos.Y - root.Position.Y > 2.2) or (ballPos.Y - root.Position.Y > 2.8)

        -- SHOT DETECTION:
        -- 1. Ball moving towards defended net (forwardSpeed > 5 studs/s)
        -- 2. Ball is still in front of the goal line (distInFrontOfGoal > 1.0)
        -- 3. Reaction window: ball will arrive within 0.05s - 1.85s
        -- 4. Intercept point is within net width (+- 24 studs)
        -- 5. Within dive reach distance
        local maxTimeToGoal = isHighShot and 1.85 or 1.55
        local reachAllowance = isHighShot and 7 or 5
        local isShotIncoming = (forwardSpeed > 5.0)
            and (distInFrontOfGoal > 1.0)
            and (timeToGoal > 0.05 and timeToGoal < maxTimeToGoal)
            and (math.abs(lateralOffset) <= 24)
            and (interceptDist <= (settings.gkDiveReach + reachAllowance))

        -- 1. Auto Dive / Save incoming shot
        if settings.gkAutoDive and isShotIncoming then
            if (now - lastDiveTime) > 1.05 then
                lastDiveTime = now
                triggerDive(interceptPos, isHighShot)
                return
            end
        end

        -- 2. Auto Punch / Clear loose ball
        if settings.gkAutoPunch and distToBall <= 9 and (now - lastPunchTime) > 0.6 then
            lastPunchTime = now
            triggerPunch(ballPos)
            return
        end

        -- 3. Auto Positioning along the net
        if settings.gkAutoPosition and not isShotIncoming then
            local ballLateral = (ballPos - homePos):Dot(goalRight)
            local keeperLateral = math.clamp(ballLateral * 0.7, -18, 18)
            local ballForwardDist = (ballPos - homePos):Dot(goalForward)
            local keeperDepth = math.clamp(ballForwardDist * 0.06, -1, 5)

            local targetPos = homePos + (goalRight * keeperLateral) + (goalForward * keeperDepth)
            if (root.Position - targetPos).Magnitude > 1.5 then
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
        if HitboxSettingsModule and HitboxSettingsModule.AirReceive and origAirReceiveSize then
            HitboxSettingsModule.AirReceive.Size = origAirReceiveSize
        end
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
