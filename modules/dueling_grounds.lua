-- RAVEN HUB | Dueling Grounds combat assist, marker-driven auto parry & instant auto counter
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")

    local environment = getgenv and getgenv() or _G
    if type(environment.__RAVEN_DUELING_GROUNDS) == "table"
        and type(environment.__RAVEN_DUELING_GROUNDS.Destroy) == "function" then
        pcall(environment.__RAVEN_DUELING_GROUNDS.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}
    local hooks = {}
    local currentTarget = nil
    local lastAttackingOpponent = nil
    local guardHeldByHub = false
    local guardReleaseToken = 0
    local lastParryAt = 0
    local lastCounterAt = 0
    local lastLookReplication = 0
    local parryCount = 0
    local counterCount = 0
    local successfulParryCount = 0
    local scanAccumulator = 0
    local statusAccumulator = 0

    local settings = {
        -- Auto Parry
        autoParry = false,
        parryRange = 16,
        reactionLead = 0.09,
        guardHold = 0.08,
        pingCompensation = true,
        requireFacing = false,
        closeRange360 = true,
        multiHitParry = true,
        jumpParryAssist = true, -- Special airborne prediction & extended parry window for jump attacks
        autoFaceOnParry = true, -- Automatically face attacker on parry to ensure guard hitbox aligns with incoming strikes

        -- Auto Counter
        autoCounter = true,
        counterType = "Light Attack (M1)",
        counterDelay = 0,
        counterFaceTarget = true,
        counterRange = 16,
        followUpCombo = false,

        -- Combat Assist
        combatAssist = false,
        assistRange = 28,
        assistFov = 140,
        assistStrength = 0.32,
        targetPriority = "Crosshair",
        showTarget = true,
    }

    -- Remotes
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local playerCharacterRemotes = remotes and remotes:FindFirstChild("PlayerCharacter")
    local requestRemotes = playerCharacterRemotes and playerCharacterRemotes:FindFirstChild("Request")
    local desiredLookRemote = requestRemotes and requestRemotes:FindFirstChild("SetDesiredLookDirection")

    -- Character Controller
    local characterControllerModule = ReplicatedStorage:FindFirstChild("Controllers")
    characterControllerModule = characterControllerModule and characterControllerModule:FindFirstChild("CharacterController")
    local CharacterController = nil
    pcall(function()
        if characterControllerModule then
            CharacterController = require(characterControllerModule)
        end
    end)

    -- Input Actions
    local inputActions = ReplicatedStorage:FindFirstChild("Controllers")
    inputActions = inputActions and inputActions:FindFirstChild("PlayerInputController")
    inputActions = inputActions and inputActions:FindFirstChild("InputActions")
    local characterContext = inputActions and inputActions:FindFirstChild("CharacterGameplayContext")
    local weaponContext = characterContext and characterContext:FindFirstChild("EquippedWeaponContext")
    local guardAction = weaponContext and weaponContext:FindFirstChild("GuardAction")
    local lightAttackAction = weaponContext and weaponContext:FindFirstChild("LightAttackAction")
    local heavyAttackAction = weaponContext and weaponContext:FindFirstChild("HeavyAttackAction")
    local dodgeAction = characterContext and characterContext:FindFirstChild("DodgeAction")

    -- Combat Controller & Impact Resolvers
    local combatControllerModule = ReplicatedStorage:FindFirstChild("Controllers")
    combatControllerModule = combatControllerModule and combatControllerModule:FindFirstChild("CombatController")
    local parryImpactsModule = combatControllerModule and combatControllerModule:FindFirstChild("ParryImpacts")

    local getconns = getconnections or (debug and debug.getconnections)

    local function disconnect(connection)
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    local function normalizeAssetId(value)
        return tostring(value or ""):match("(%d+)")
    end

    -- Universal Signal invoker
    local function invokeSignal(signal)
        if not signal then
            return false
        end
        local invoked = false
        if getconns then
            local conns = getconns(signal)
            if conns and #conns > 0 then
                for _, c in ipairs(conns) do
                    if c.Function then
                        pcall(c.Function)
                        invoked = true
                    elseif c.Fire then
                        pcall(function() c:Fire() end)
                        invoked = true
                    end
                end
            end
        end
        if not invoked and type(firesignal) == "function" then
            local ok = pcall(firesignal, signal)
            if ok then
                invoked = true
            end
        end
        return invoked
    end

    -- Dynamic Attack Catalog
    local attackCatalog = {}
    local catalogModuleCount = 0

    local function addAttackConfig(moduleScript, weaponName, categoryName)
        local ok, config = pcall(require, moduleScript)
        if not ok or type(config) ~= "table" then
            return
        end

        local animation = config.animation
        local animationId = animation and normalizeAssetId(animation.AnimationId)
        if not animationId then
            local animObj = config.Animation or config.anim
            animationId = animObj and normalizeAssetId(animObj.AnimationId)
        end

        if not animationId or type(config.impacts) ~= "table" then
            return
        end

        local markers = {}
        for index, impact in ipairs(config.impacts) do
            local markerTime = type(impact) == "table" and tonumber(impact.markerTime)
            if markerTime then
                table.insert(markers, {
                    index = index,
                    time = markerTime,
                })
            end
        end
        if #markers == 0 then
            return
        end

        table.sort(markers, function(a, b)
            return a.time < b.time
        end)

        local modName = moduleScript.Name:lower()
        local isJump = modName:find("jump") ~= nil or modName:find("air") ~= nil or modName:find("slam") ~= nil

        attackCatalog[animationId] = {
            name = moduleScript.Name,
            weapon = weaponName,
            category = isJump and "JumpAttack" or (categoryName or "BasicAttack"),
            isJump = isJump,
            markers = markers,
        }
        catalogModuleCount += 1
    end

    local function buildAttackCatalog()
        table.clear(attackCatalog)
        catalogModuleCount = 0
        local weaponRoot = ReplicatedStorage:FindFirstChild("WeaponModulesShared")
        if not weaponRoot then
            return
        end

        for _, weaponModule in ipairs(weaponRoot:GetChildren()) do
            -- BasicAttackTypes (Lights 1-4, Heavies 1-3, Dash Light/Heavy, Jump, Ult)
            local basicAttacks = weaponModule:FindFirstChild("BasicAttackTypes")
            if basicAttacks then
                for _, moduleScript in ipairs(basicAttacks:GetChildren()) do
                    if moduleScript:IsA("ModuleScript") then
                        addAttackConfig(moduleScript, weaponModule.Name, "BasicAttack")
                    end
                end
            end

            -- CriticalStrikes subfolders
            local critStrikes = weaponModule:FindFirstChild("CriticalStrikes")
            if critStrikes then
                for _, subFolder in ipairs(critStrikes:GetChildren()) do
                    for _, moduleScript in ipairs(subFolder:GetChildren()) do
                        if moduleScript:IsA("ModuleScript") then
                            addAttackConfig(moduleScript, weaponModule.Name, "CriticalStrike")
                        end
                    end
                end
            end

            -- UltimateAbilities subfolders
            local ultAbilities = weaponModule:FindFirstChild("UltimateAbilities")
            if ultAbilities then
                for _, subFolder in ipairs(ultAbilities:GetChildren()) do
                    for _, moduleScript in ipairs(subFolder:GetChildren()) do
                        if moduleScript:IsA("ModuleScript") then
                            addAttackConfig(moduleScript, weaponModule.Name, "Ultimate")
                        end
                    end
                end
            end
        end
    end

    buildAttackCatalog()

    -- Correct local character model resolution (handles Player_Client)
    local function getLocalCharacter()
        if CharacterController and CharacterController.GetLocalCharacterHandler then
            local ok, lch = pcall(CharacterController.GetLocalCharacterHandler, CharacterController)
            if ok and lch and lch.Model and lch.Model.Parent == workspace then
                return lch.Model
            end
        end
        local pc = workspace:FindFirstChild("Player_Client")
        if pc and pc:FindFirstChild("HumanoidRootPart") then
            return pc
        end
        local char = localPlayer and localPlayer.Character
        if char and char.Parent == workspace then
            return char
        end
        return nil
    end

    local function getRoot(model)
        return model and (model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Root")
            or model.PrimaryPart)
    end

    local function modelAlive(model)
        if not model or model.Parent ~= workspace then
            return false
        end
        local healthAttr = tonumber(model:GetAttribute("Health"))
        if healthAttr ~= nil then
            return healthAttr > 0
        end
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        return humanoid == nil or humanoid.Health > 0
    end

    local function isModelFriendly(model, localModel)
        local theirGroup = model and model:GetAttribute("TeamGroup")
        local ourGroup = localModel and localModel:GetAttribute("TeamGroup")
        if theirGroup ~= nil and ourGroup ~= nil then
            return tostring(theirGroup) == tostring(ourGroup)
        end
        return false
    end

    local function modelValidTarget(model, localModel, maxRange)
        local localRoot = getRoot(localModel)
        local targetRoot = getRoot(model)
        if not localRoot or not targetRoot or not modelAlive(model) then
            return false
        end
        if model:GetAttribute("IsUntargetable") == true
            or model:GetAttribute("InSafeZone") == true
            or isModelFriendly(model, localModel) then
            return false
        end
        local delta = targetRoot.Position - localRoot.Position
        if delta.Y > 22 or delta.Y < -16 then
            return false
        end
        -- For elevated/jump attacks, check horizontal strike distance so vertical height doesn't artificially push target out of range
        if delta.Y > 1.5 then
            local flatDistance = Vector2.new(delta.X, delta.Z).Magnitude
            return flatDistance <= maxRange
        end
        return delta.Magnitude <= maxRange
    end

    local function targetAngle(camera, position)
        local offset = position - camera.CFrame.Position
        if offset.Magnitude < 0.001 then
            return 0
        end
        return math.deg(math.acos(math.clamp(camera.CFrame.LookVector:Dot(offset.Unit), -1, 1)))
    end

    local function findBestTarget(maxRange, fov)
        local localModel = getLocalCharacter()
        local localRoot = getRoot(localModel)
        local camera = workspace.CurrentCamera
        if not localRoot or not camera then
            return nil
        end

        local bestTarget = nil
        local bestScore = math.huge
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and obj ~= localModel and obj.Name ~= "Player_Client" then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local root = getRoot(obj)
                if hum and root and modelValidTarget(obj, localModel, maxRange) then
                    local delta = root.Position - localRoot.Position
                    local angle = targetAngle(camera, root.Position)
                    if angle <= fov * 0.5 then
                        local score = settings.targetPriority == "Distance" and delta.Magnitude or angle
                        if score < bestScore then
                            bestScore = score
                            bestTarget = {
                                character = obj,
                                root = root,
                                distance = delta.Magnitude,
                            }
                        end
                    end
                end
            end
        end
        return bestTarget
    end

    local function findNearestOpponent(maxRange)
        local localModel = getLocalCharacter()
        local localRoot = getRoot(localModel)
        if not localRoot then
            return nil
        end

        local nearestTarget = nil
        local nearestDistance = maxRange or settings.counterRange
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and obj ~= localModel and obj.Name ~= "Player_Client" then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local root = getRoot(obj)
                if hum and root and modelValidTarget(obj, localModel, nearestDistance) then
                    local dist = (root.Position - localRoot.Position).Magnitude
                    if dist < nearestDistance then
                        nearestDistance = dist
                        nearestTarget = {
                            character = obj,
                            root = root,
                            distance = dist,
                        }
                    end
                end
            end
        end
        return nearestTarget
    end

    local targetHighlight = Instance.new("Highlight")
    targetHighlight.Name = "RavenDuelingGroundsTarget"
    targetHighlight.FillColor = Color3.fromRGB(215, 65, 80)
    targetHighlight.FillTransparency = 0.72
    targetHighlight.OutlineColor = Color3.fromRGB(255, 225, 225)
    targetHighlight.OutlineTransparency = 0.1
    targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    targetHighlight.Enabled = false
    targetHighlight.Parent = game:GetService("CoreGui")

    local function updateHighlight()
        local character = currentTarget and currentTarget.character
        targetHighlight.Adornee = character
        targetHighlight.Enabled = settings.showTarget and settings.combatAssist and character ~= nil
    end

    local function getPingSeconds()
        if not settings.pingCompensation then
            return 0
        end
        local ok, value = pcall(function()
            local network = Stats:FindFirstChild("Network")
            local serverStats = network and network:FindFirstChild("ServerStatsItem")
            local pingItem = serverStats and serverStats:FindFirstChild("Data Ping")
            return pingItem and pingItem:GetValue() or 0
        end)
        if not ok then
            return 0
        end
        return math.clamp((tonumber(value) or 0) / 2000, 0, 0.12)
    end

    -- Guard Action Execution
    local function fireGuardSignal(signalName)
        if guardAction then
            local signal = guardAction[signalName]
            if signal and invokeSignal(signal) then
                return true
            end
        end
        -- Native input fallback
        if signalName == "Pressed" and type(keypress) == "function" then
            pcall(keypress, 0x46)
            return true
        elseif signalName == "Released" and type(keyrelease) == "function" then
            pcall(keyrelease, 0x46)
            return true
        end
        return false
    end

    local function releaseGuard()
        if not guardHeldByHub then
            return
        end
        guardHeldByHub = false
        fireGuardSignal("Released")
    end

    -- Face target immediately (supporting 360, cross-ups, and vertical head slams)
    local function snapFaceTarget(targetCharacter)
        local localModel = getLocalCharacter()
        local localRoot = getRoot(localModel)
        local targetRoot = getRoot(targetCharacter)
        if not localRoot or not targetRoot then
            return
        end
        local flatTarget = Vector3.new(targetRoot.Position.X, localRoot.Position.Y, targetRoot.Position.Z)
        local direction = flatTarget - localRoot.Position

        -- If target is directly overhead (landing onto head / cross-up with < 0.6 studs horizontal delta),
        -- turn to face opposite to the target's look direction so our guard hitbox faces directly into their strike
        if direction.Magnitude < 0.6 then
            local oppLook = targetRoot.CFrame.LookVector
            local flatOppLook = Vector3.new(oppLook.X, 0, oppLook.Z)
            if flatOppLook.Magnitude > 0.001 then
                direction = -flatOppLook.Unit
            else
                direction = localRoot.CFrame.LookVector
            end
        end

        local flatLookDir = Vector3.new(direction.X, 0, direction.Z)
        if flatLookDir.Magnitude < 0.001 then
            flatLookDir = localRoot.CFrame.LookVector
        else
            flatLookDir = flatLookDir.Unit
        end

        local desiredCFrame = CFrame.lookAt(localRoot.Position, localRoot.Position + flatLookDir)
        localRoot.CFrame = desiredCFrame

        if desiredLookRemote then
            pcall(function()
                desiredLookRemote:FireServer(flatLookDir)
            end)
        end
    end

    local function tapGuard(opponentCharacter, customHold)
        local now = os.clock()
        local minInterval = settings.multiHitParry and 0.04 or 0.08
        if now - lastParryAt < minInterval then
            return false
        end
        lastParryAt = now
        parryCount += 1
        guardReleaseToken += 1
        local token = guardReleaseToken

        if opponentCharacter then
            lastAttackingOpponent = opponentCharacter
            -- Auto snap-face attacker on parry to align shield/weapon hitbox with incoming strike angle
            if settings.autoFaceOnParry ~= false then
                snapFaceTarget(opponentCharacter)
            end
        end

        guardHeldByHub = true
        fireGuardSignal("Pressed")

        local holdTime = customHold or settings.guardHold
        task.delay(holdTime, function()
            if running and token == guardReleaseToken then
                releaseGuard()
            end
        end)
        return true
    end

    -- Attack Action Execution for Auto Counter
    local function fireAttackInput(actionType)
        if actionType == "LightAttackAction" then
            if lightAttackAction and invokeSignal(lightAttackAction.Pressed) then
                task.defer(function()
                    invokeSignal(lightAttackAction.Released)
                end)
                return true
            end
            if type(mouse1click) == "function" then
                pcall(mouse1click)
                return true
            elseif type(mouse1press) == "function" then
                pcall(mouse1press)
                task.defer(function() pcall(mouse1release) end)
                return true
            end
            return false
        elseif actionType == "HeavyAttackAction" then
            if heavyAttackAction and invokeSignal(heavyAttackAction.Pressed) then
                task.defer(function()
                    invokeSignal(heavyAttackAction.Released)
                end)
                return true
            end
            if type(mouse2click) == "function" then
                pcall(mouse2click)
                return true
            elseif type(mouse2press) == "function" then
                pcall(mouse2press)
                task.defer(function() pcall(mouse2release) end)
                return true
            end
            return false
        elseif actionType == "DashAttack" then
            if dodgeAction and invokeSignal(dodgeAction.Pressed) then
                task.defer(function() invokeSignal(dodgeAction.Released) end)
            elseif type(keypress) == "function" then
                pcall(keypress, 0x51)
                task.defer(function() pcall(keyrelease, 0x51) end)
            end
            task.delay(0.06, function()
                if running then
                    fireAttackInput("LightAttackAction")
                end
            end)
            return true
        end
        return false
    end

    -- Smooth face target for combat assist
    local function faceTarget(target, deltaTime)
        local localModel = getLocalCharacter()
        local localRoot = getRoot(localModel)
        local targetRoot = target and getRoot(target.character)
        if not localRoot or not targetRoot then
            return
        end
        local flatTarget = Vector3.new(targetRoot.Position.X, localRoot.Position.Y, targetRoot.Position.Z)
        local direction = flatTarget - localRoot.Position
        if direction.Magnitude < 0.001 then
            return
        end
        local desired = CFrame.lookAt(localRoot.Position, flatTarget)
        local alpha = 1 - math.pow(1 - math.clamp(settings.assistStrength, 0.01, 1), deltaTime * 60)
        localRoot.CFrame = localRoot.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))

        local now = os.clock()
        if desiredLookRemote and now - lastLookReplication >= 0.1 then
            lastLookReplication = now
            pcall(function()
                desiredLookRemote:FireServer(direction.Unit)
            end)
        end
    end

    -- Auto Counter Execution
    local function executeAutoCounter(targetChar)
        local now = os.clock()
        if now - lastCounterAt < 0.22 then
            return
        end
        lastCounterAt = now

        local target = targetChar
        if not target or not modelAlive(target) then
            local nearest = findNearestOpponent(settings.counterRange)
            target = nearest and nearest.character
        end
        if not target or not modelAlive(target) then
            return
        end

        local localModel = getLocalCharacter()
        local localRoot = getRoot(localModel)
        local targetRoot = getRoot(target)
        if not localRoot or not targetRoot then
            return
        end

        local distance = (targetRoot.Position - localRoot.Position).Magnitude
        if distance > settings.counterRange then
            return
        end

        -- Release guard first so counter-attack is not blocked by our own block lag
        guardReleaseToken += 1
        releaseGuard()

        -- Auto face target if enabled
        if settings.counterFaceTarget then
            snapFaceTarget(target)
        end

        local counterAction = "LightAttackAction"
        if settings.counterType == "Heavy Attack (M2)" then
            counterAction = "HeavyAttackAction"
        elseif settings.counterType == "Dash Light" then
            counterAction = "DashAttack"
        elseif settings.counterType == "Auto (Light/Dash)" then
            if distance > 8.5 then
                counterAction = "DashAttack"
            else
                counterAction = "LightAttackAction"
            end
        end

        local function doStrike()
            if not running or not modelAlive(localModel) then
                return
            end
            counterCount += 1
            fireAttackInput(counterAction)

            if settings.followUpCombo and counterAction == "LightAttackAction" then
                task.delay(0.24, function()
                    if running and modelAlive(localModel) then
                        fireAttackInput("LightAttackAction")
                    end
                end)
            end
        end

        if settings.counterDelay > 0 then
            task.delay(settings.counterDelay, doStrike)
        else
            doStrike()
        end
    end

    -- Confirmed Parry Handler (Hook / Signal Callbacks)
    local function onParryConfirmed(attackerChar)
        successfulParryCount += 1
        -- Immediately release guard so we don't remain stuck in block
        guardReleaseToken += 1
        releaseGuard()

        if settings.autoCounter then
            local target = attackerChar or lastAttackingOpponent
            executeAutoCounter(target)
        end
    end

    -- Hook ParryImpacts module for 100% reliable local parry resolution
    local function hookParryImpacts()
        if not parryImpactsModule then
            return
        end
        local ok, pi = pcall(require, parryImpactsModule)
        if not ok or type(pi) ~= "table" then
            return
        end

        -- Hook Parry (standard parry clash)
        if type(pi.Parry) == "function" then
            local originalParry = pi.Parry
            hooks["Parry"] = {target = pi, key = "Parry", orig = originalParry}
            pi.Parry = function(cf, ...)
                onParryConfirmed(lastAttackingOpponent)
                return originalParry(cf, ...)
            end
        end

        -- Hook LightParry
        if type(pi.LightParry) == "function" then
            local originalLightParry = pi.LightParry
            hooks["LightParry"] = {target = pi, key = "LightParry", orig = originalLightParry}
            pi.LightParry = function(...)
                onParryConfirmed(lastAttackingOpponent)
                return originalLightParry(...)
            end
        end

        -- Hook UltimateParry
        if type(pi.UltimateParry) == "function" then
            local originalUltParry = pi.UltimateParry
            hooks["UltimateParry"] = {target = pi, key = "UltimateParry", orig = originalUltParry}
            pi.UltimateParry = function(...)
                onParryConfirmed(lastAttackingOpponent)
                return originalUltParry(...)
            end
        end
    end

    hookParryImpacts()

    -- Connect CombatController.LocalImpactResolved for extra redundancy
    local function connectCombatController()
        if not combatControllerModule then
            return
        end
        local ok, cc = pcall(require, combatControllerModule)
        if not ok or type(cc) ~= "table" then
            return
        end

        local signal = cc.LocalImpactResolved
        if signal and type(signal.Connect) == "function" then
            local conn = signal:Connect(function(arg1, arg2)
                local outcome = tostring(arg1 == "Parry" and arg1 or arg2)
                if outcome == "Parry" then
                    onParryConfirmed(lastAttackingOpponent)
                end
            end)
            table.insert(connections, conn)
        end
    end

    connectCombatController()

    -- Track seen animation markers per cycle to support multi-hits and looping swings
    local trackMarkerSeen = setmetatable({}, {__mode = "k"})

    local function opponentFacingLocal(opponentRoot, localRoot, distance, isAirborne)
        -- Airborne attacks (jumps/slams) have downward AOE cones and cross-up trajectories; auto-grant 360 parry
        if isAirborne or (settings.closeRange360 and distance <= 11) then
            return true
        end
        if not settings.requireFacing then
            return true
        end
        local offset = localRoot.Position - opponentRoot.Position
        local flatOffset = Vector3.new(offset.X, 0, offset.Z)
        if flatOffset.Magnitude < 0.001 then
            return true
        end
        local flatLook = Vector3.new(opponentRoot.CFrame.LookVector.X, 0, opponentRoot.CFrame.LookVector.Z)
        if flatLook.Magnitude < 0.001 then
            return true
        end
        return flatLook.Unit:Dot(flatOffset.Unit) >= -0.35
    end

    -- High-Performance Auto Parry Scanner
    local function scanOpponentAttacks()
        local localModel = getLocalCharacter()
        local localRoot = getRoot(localModel)
        if not localRoot or not modelAlive(localModel)
            or localModel:GetAttribute("InSafeZone") == true
            or localModel:GetAttribute("IsUntargetable") == true then
            return
        end

        local realLead = settings.reactionLead + getPingSeconds()

        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and obj ~= localModel and obj.Name ~= "Player_Client" then
                local hum = obj:FindFirstChildOfClass("Humanoid")
                local root = getRoot(obj)
                if hum and root and modelValidTarget(obj, localModel, settings.parryRange) then
                    local delta = root.Position - localRoot.Position
                    local distance = delta.Magnitude
                    local verticalDist = delta.Y
                    local humState = hum:GetState()
                    local floorMat = hum.FloorMaterial
                    local vel = root.AssemblyLinearVelocity or root.Velocity or Vector3.zero
                    local velY = vel.Y

                    -- Robust multi-layer airborne & vertical jump detection
                    local isAirborne = (verticalDist > 1.2)
                        or (floorMat == Enum.Material.Air)
                        or (humState == Enum.HumanoidStateType.Freefall)
                        or (humState == Enum.HumanoidStateType.Jumping)
                        or (math.abs(velY) > 2)

                    local animator = hum:FindFirstChildOfClass("Animator")
                    if animator then
                        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                            local animationId = track.Animation and normalizeAssetId(track.Animation.AnimationId)
                            local attack = animationId and attackCatalog[animationId]
                            if attack then
                                local isJump = settings.jumpParryAssist and (attack.isJump or isAirborne)

                                if opponentFacingLocal(root, localRoot, distance, isAirborne or isJump) then
                                    local seen = trackMarkerSeen[track]
                                    if not seen then
                                        seen = {}
                                        trackMarkerSeen[track] = seen
                                    end

                                    local speed = math.max(math.abs(track.Speed), 0.05)
                                    local trackPos = track.TimePosition
                                    local animationLead = realLead * speed

                                    for _, marker in ipairs(attack.markers) do
                                        local triggerTime = math.max(0, marker.time - animationLead)
                                        local upperWindow = marker.time + 0.055 * speed
                                        local holdDuration = settings.guardHold

                                        -- Specialized Aerial & Jump Attack Timing Engine
                                        if isJump then
                                            -- Jump attacks strike downwards onto head from above:
                                            -- If opponent is high up (> 6.2 studs) and still ascending/high, wait until they enter strike reach
                                            local inStrikeReach = (verticalDist <= 6.2) or (verticalDist <= 7.5 and velY < -8)

                                            if inStrikeReach then
                                                -- In strike reach! Trigger parry immediately and hold through the full landing impact
                                                triggerTime = 0
                                                upperWindow = math.max(marker.time + 0.35 * speed, 0.40)
                                                holdDuration = math.max(settings.guardHold, 0.26)
                                            else
                                                -- High in air, skip this tick until enemy descends into striking distance
                                                continue
                                            end
                                        elseif marker.time <= 0.15 then
                                            -- Fast startup grounded attacks
                                            triggerTime = 0
                                            upperWindow = math.max(marker.time + 0.20 * speed, 0.26)
                                            holdDuration = math.max(settings.guardHold, 0.14)
                                        end

                                        -- Cycle reset for looping/repeated attacks
                                        if trackPos < triggerTime - 0.1 then
                                            seen[marker.index] = nil
                                        end

                                        if not seen[marker.index]
                                            and trackPos >= triggerTime
                                            and trackPos <= upperWindow then
                                            seen[marker.index] = true
                                            tapGuard(obj, holdDuration)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- UI Creation via MacLib
    local CombatTab = Window:CreateTab("Combat", "swords")

    -- Auto Parry Section (Left Column)
    CombatTab:CreateSection("Auto Parry (Overhauled)", "Left")
    local statusLabel = CombatTab:CreateLabel("Catalog: " .. tostring(catalogModuleCount) .. " attacks loaded")

    CombatTab:CreateToggle({
        Name = "Auto Parry",
        CurrentValue = false,
        Flag = "DGAutoParry",
        Callback = function(value)
            settings.autoParry = value
            if not value then
                guardReleaseToken += 1
                releaseGuard()
            end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Parry Range",
        Range = {6, 30},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = 16,
        Flag = "DGParryRange",
        Callback = function(value)
            settings.parryRange = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Reaction Lead",
        Range = {20, 180},
        Increment = 5,
        Suffix = " ms",
        CurrentValue = 90,
        Flag = "DGReactionLead",
        Callback = function(value)
            settings.reactionLead = value / 1000
        end,
    })

    CombatTab:CreateSlider({
        Name = "Guard Hold Window",
        Range = {35, 150},
        Increment = 5,
        Suffix = " ms",
        CurrentValue = 80,
        Flag = "DGGuardHold",
        Callback = function(value)
            settings.guardHold = value / 1000
        end,
    })

    CombatTab:CreateToggle({
        Name = "Half-Ping Compensation",
        CurrentValue = true,
        Flag = "DGPingCompensation",
        Callback = function(value)
            settings.pingCompensation = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Require Enemy Facing",
        CurrentValue = false,
        Flag = "DGRequireFacing",
        Callback = function(value)
            settings.requireFacing = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Close-Range 360 Parry",
        CurrentValue = true,
        Flag = "DGCloseRange360",
        Callback = function(value)
            settings.closeRange360 = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Multi-Hit Auto Parry",
        CurrentValue = true,
        Flag = "DGMultiHitParry",
        Callback = function(value)
            settings.multiHitParry = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Jump Attack Prediction",
        CurrentValue = true,
        Flag = "DGJumpParryAssist",
        Callback = function(value)
            settings.jumpParryAssist = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Face on Parry",
        CurrentValue = true,
        Flag = "DGAutoFaceOnParry",
        Callback = function(value)
            settings.autoFaceOnParry = value
        end,
    })

    CombatTab:CreateButton({
        Name = "Reload Attack Catalog",
        Callback = function()
            buildAttackCatalog()
        end,
    })

    -- Auto Counter Section (Right Column)
    CombatTab:CreateSection("Auto Counter (Riposte)", "Right")

    CombatTab:CreateToggle({
        Name = "Auto Counter on Parry",
        CurrentValue = true,
        Flag = "DGAutoCounter",
        Callback = function(value)
            settings.autoCounter = value
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Counter Attack Type",
        Options = {
            "Light Attack (M1)",
            "Heavy Attack (M2)",
            "Auto (Light/Dash)",
            "Dash Light",
        },
        CurrentOption = {"Light Attack (M1)"},
        MultipleOptions = false,
        Flag = "DGCounterType",
        Callback = function(value)
            settings.counterType = type(value) == "table" and value[1] or tostring(value)
        end,
    })

    CombatTab:CreateSlider({
        Name = "Counter Delay",
        Range = {0, 150},
        Increment = 5,
        Suffix = " ms",
        CurrentValue = 0,
        Flag = "DGCounterDelay",
        Callback = function(value)
            settings.counterDelay = value / 1000
        end,
    })

    CombatTab:CreateSlider({
        Name = "Counter Max Range",
        Range = {6, 25},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = 16,
        Flag = "DGCounterRange",
        Callback = function(value)
            settings.counterRange = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Face on Counter",
        CurrentValue = true,
        Flag = "DGCounterFaceTarget",
        Callback = function(value)
            settings.counterFaceTarget = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Follow-up Combo (M1 x2)",
        CurrentValue = false,
        Flag = "DGFollowUpCombo",
        Callback = function(value)
            settings.followUpCombo = value
        end,
    })

    -- Combat Assist Section (Right Column)
    CombatTab:CreateSection("Combat Assist", "Right")

    CombatTab:CreateToggle({
        Name = "Auto Face Target",
        CurrentValue = false,
        Flag = "DGCombatAssist",
        Callback = function(value)
            settings.combatAssist = value
            if not value then
                currentTarget = nil
                updateHighlight()
            end
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Target Priority",
        Options = {"Crosshair", "Distance"},
        CurrentOption = {"Crosshair"},
        MultipleOptions = false,
        Flag = "DGTargetPriority",
        Callback = function(value)
            settings.targetPriority = type(value) == "table" and value[1] or tostring(value)
        end,
    })

    CombatTab:CreateSlider({
        Name = "Assist Range",
        Range = {8, 60},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = 28,
        Flag = "DGAssistRange",
        Callback = function(value)
            settings.assistRange = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Assist FOV",
        Range = {30, 360},
        Increment = 5,
        Suffix = " deg",
        CurrentValue = 140,
        Flag = "DGAssistFOV",
        Callback = function(value)
            settings.assistFov = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Turn Strength",
        Range = {5, 100},
        Increment = 5,
        Suffix = "%",
        CurrentValue = 32,
        Flag = "DGAssistStrength",
        Callback = function(value)
            settings.assistStrength = value / 100
        end,
    })

    CombatTab:CreateToggle({
        Name = "Show Target Highlight",
        CurrentValue = true,
        Flag = "DGShowTarget",
        Callback = function(value)
            settings.showTarget = value
            updateHighlight()
        end,
    })

    CombatTab:CreateLabel("Auto Parry catches all lights, heavies, crits & ults. Auto Counter strikes back instantly on parry.")

    -- Main Render Loop
    table.insert(connections, RunService.RenderStepped:Connect(function(deltaTime)
        if not running then
            return
        end
        scanAccumulator += deltaTime
        statusAccumulator += deltaTime

        -- Combat Assist Aim
        if settings.combatAssist then
            if scanAccumulator >= 0.08 or not modelValidTarget(currentTarget and currentTarget.character, getLocalCharacter(), settings.assistRange) then
                scanAccumulator = 0
                currentTarget = findBestTarget(settings.assistRange, settings.assistFov)
                updateHighlight()
            end
            if currentTarget and modelValidTarget(currentTarget.character, getLocalCharacter(), settings.assistRange) then
                faceTarget(currentTarget, deltaTime)
            end
        end

        -- Auto Parry Scan
        if settings.autoParry then
            scanOpponentAttacks()
        end

        -- Status HUD Update
        if statusAccumulator >= 0.3 then
            statusAccumulator = 0
            local targetName = currentTarget and currentTarget.character and currentTarget.character.Name or "none"
            pcall(function()
                statusLabel:Set(string.format(
                    "Catalog: %d | Target: %s | Parries: %d (%d hit) | Counters: %d",
                    catalogModuleCount,
                    targetName,
                    parryCount,
                    successfulParryCount,
                    counterCount
                ))
            end)
        end
    end))

    -- Cleanup
    local function destroyScript()
        if not running then
            return
        end
        running = false
        guardReleaseToken += 1
        releaseGuard()
        currentTarget = nil
        lastAttackingOpponent = nil

        -- Restore all hooks
        for _, h in pairs(hooks) do
            if h.target and h.orig then
                pcall(function()
                    h.target[h.key] = h.orig
                end)
            end
        end
        table.clear(hooks)

        for _, connection in ipairs(connections) do
            disconnect(connection)
        end
        table.clear(connections)
        targetHighlight:Destroy()
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end
    environment.__RAVEN_DUELING_GROUNDS = {
        Destroy = destroyScript
    }
end
