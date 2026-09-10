-- RAVEN HUB | Dueling Grounds combat assist, marker-driven auto parry & instant auto counter
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local VirtualInputManager = game:GetService("VirtualInputManager")

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
        parryRange = 15,
        reactionLead = 0.09,
        guardHold = 0.065,
        pingCompensation = true,
        requireFacing = true,
        closeRange360 = true,
        multiHitParry = true,

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

        attackCatalog[animationId] = {
            name = moduleScript.Name,
            weapon = weaponName,
            category = categoryName or "BasicAttack",
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

    local function getCharacter(player)
        local character = player and player.Character
        if character and character.Parent == workspace then
            return character
        end
        return nil
    end

    local function getRoot(character)
        return character and (character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Root")
            or character.PrimaryPart)
    end

    local function characterAlive(character)
        if not character or character.Parent ~= workspace then
            return false
        end
        local health = tonumber(character:GetAttribute("Health"))
        if health ~= nil then
            return health > 0
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        return humanoid == nil or humanoid.Health > 0
    end

    local function isFriendly(character, localCharacter)
        local theirGroup = character and character:GetAttribute("TeamGroup")
        local ourGroup = localCharacter and localCharacter:GetAttribute("TeamGroup")
        if theirGroup ~= nil and ourGroup ~= nil then
            return tostring(theirGroup) == tostring(ourGroup)
        end
        return false
    end

    local function targetValid(target, maxRange)
        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
        local character = target and target.character
        local root = getRoot(character)
        if not localRoot or not root or not characterAlive(character) then
            return false
        end
        if character:GetAttribute("IsUntargetable") == true
            or character:GetAttribute("InSafeZone") == true
            or isFriendly(character, localCharacter) then
            return false
        end
        local delta = root.Position - localRoot.Position
        if math.abs(delta.Y) > 14 then
            return false
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
        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
        local camera = workspace.CurrentCamera
        if not localRoot or not camera then
            return nil
        end

        local bestTarget = nil
        local bestScore = math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then
                local character = getCharacter(player)
                local root = getRoot(character)
                if root and characterAlive(character)
                    and character:GetAttribute("IsUntargetable") ~= true
                    and character:GetAttribute("InSafeZone") ~= true
                    and not isFriendly(character, localCharacter) then
                    local delta = root.Position - localRoot.Position
                    if math.abs(delta.Y) <= 14 and delta.Magnitude <= maxRange then
                        local angle = targetAngle(camera, root.Position)
                        if angle <= fov * 0.5 then
                            local score = settings.targetPriority == "Distance" and delta.Magnitude or angle
                            if score < bestScore then
                                bestScore = score
                                bestTarget = {
                                    player = player,
                                    character = character,
                                    root = root,
                                    distance = delta.Magnitude,
                                }
                            end
                        end
                    end
                end
            end
        end
        return bestTarget
    end

    local function findNearestOpponent(maxRange)
        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
        if not localRoot then
            return nil
        end

        local nearestTarget = nil
        local nearestDistance = maxRange or settings.counterRange
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then
                local character = getCharacter(player)
                local root = getRoot(character)
                if root and characterAlive(character)
                    and character:GetAttribute("IsUntargetable") ~= true
                    and character:GetAttribute("InSafeZone") ~= true
                    and not isFriendly(character, localCharacter) then
                    local dist = (root.Position - localRoot.Position).Magnitude
                    if dist < nearestDistance then
                        nearestDistance = dist
                        nearestTarget = {
                            player = player,
                            character = character,
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
        if guardAction and type(firesignal) == "function" then
            local signal = guardAction[signalName]
            if signal then
                local ok = pcall(firesignal, signal)
                if ok then
                    return true
                end
            end
        end
        local isPressed = signalName == "Pressed"
        return pcall(function()
            VirtualInputManager:SendKeyEvent(isPressed, Enum.KeyCode.F, false, game)
        end)
    end

    local function releaseGuard()
        if not guardHeldByHub then
            return
        end
        guardHeldByHub = false
        fireGuardSignal("Released")
    end

    local function tapGuard(opponentCharacter)
        local now = os.clock()
        -- Allow rapid consecutive parries for multi-hit attacks if multiHitParry is enabled
        local minInterval = settings.multiHitParry and 0.045 or 0.09
        if now - lastParryAt < minInterval then
            return false
        end
        lastParryAt = now
        parryCount += 1
        guardReleaseToken += 1
        local token = guardReleaseToken

        if opponentCharacter then
            lastAttackingOpponent = opponentCharacter
        end

        if not guardHeldByHub then
            guardHeldByHub = true
            fireGuardSignal("Pressed")
        end

        task.delay(settings.guardHold, function()
            if running and token == guardReleaseToken then
                releaseGuard()
            end
        end)
        return true
    end

    -- Attack Action Execution for Auto Counter
    local function fireAttackInput(actionType)
        if actionType == "LightAttackAction" then
            if lightAttackAction and type(firesignal) == "function" then
                pcall(firesignal, lightAttackAction.Pressed)
                task.defer(function()
                    pcall(firesignal, lightAttackAction.Released)
                end)
                return true
            end
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                task.defer(function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end)
            end)
            return true
        elseif actionType == "HeavyAttackAction" then
            if heavyAttackAction and type(firesignal) == "function" then
                pcall(firesignal, heavyAttackAction.Pressed)
                task.defer(function()
                    pcall(firesignal, heavyAttackAction.Released)
                end)
                return true
            end
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(0, 0, 1, true, game, 0)
                task.defer(function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 1, false, game, 0)
                end)
            end)
            return true
        elseif actionType == "DashAttack" then
            -- Dodge forward + Light Attack
            if dodgeAction and type(firesignal) == "function" then
                pcall(firesignal, dodgeAction.Pressed)
                task.defer(function()
                    pcall(firesignal, dodgeAction.Released)
                end)
            else
                pcall(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Q, false, game)
                    task.defer(function()
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Q, false, game)
                    end)
                end)
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

    -- Face target immediately
    local function snapFaceTarget(targetCharacter)
        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
        local targetRoot = getRoot(targetCharacter)
        if not localRoot or not targetRoot then
            return
        end
        local flatTarget = Vector3.new(targetRoot.Position.X, localRoot.Position.Y, targetRoot.Position.Z)
        local direction = flatTarget - localRoot.Position
        if direction.Magnitude < 0.001 then
            return
        end
        local desiredCFrame = CFrame.lookAt(localRoot.Position, flatTarget)
        localRoot.CFrame = desiredCFrame

        if desiredLookRemote then
            pcall(function()
                desiredLookRemote:FireServer(direction.Unit)
            end)
        end
    end

    -- Smooth face target for combat assist
    local function faceTarget(target, deltaTime)
        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
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
        if now - lastCounterAt < 0.25 then
            return
        end
        lastCounterAt = now

        local target = targetChar
        if not target or not characterAlive(target) then
            local nearest = findNearestOpponent(settings.counterRange)
            target = nearest and nearest.character
        end
        if not target or not characterAlive(target) then
            return
        end

        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
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
            if not running or not characterAlive(localCharacter) then
                return
            end
            counterCount += 1
            fireAttackInput(counterAction)

            if settings.followUpCombo and counterAction == "LightAttackAction" then
                task.delay(0.24, function()
                    if running and characterAlive(localCharacter) then
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

    local function opponentFacingLocal(opponentRoot, localRoot, distance)
        -- Close quarters (under 8 studs): allow 360 parry if closeRange360 is on
        if settings.closeRange360 and distance <= 8.5 then
            return true
        end
        if not settings.requireFacing then
            return true
        end
        local offset = localRoot.Position - opponentRoot.Position
        if offset.Magnitude < 0.001 then
            return true
        end
        -- Lenient facing threshold for dynamic combat strafing
        return opponentRoot.CFrame.LookVector:Dot(offset.Unit) >= -0.15
    end

    -- High-Performance Auto Parry Scanner
    local function scanOpponentAttacks()
        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
        if not localRoot or not characterAlive(localCharacter)
            or localCharacter:GetAttribute("InSafeZone") == true
            or localCharacter:GetAttribute("IsUntargetable") == true then
            return
        end

        local realLead = settings.reactionLead + getPingSeconds()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then
                local character = getCharacter(player)
                local root = getRoot(character)
                if root and targetValid({character = character}, settings.parryRange) then
                    local distance = (root.Position - localRoot.Position).Magnitude
                    if opponentFacingLocal(root, localRoot, distance) then
                        local humanoid = character:FindFirstChildOfClass("Humanoid")
                        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
                        if animator then
                            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                                local animationId = track.Animation and normalizeAssetId(track.Animation.AnimationId)
                                local attack = animationId and attackCatalog[animationId]
                                if attack then
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
                                        local upperWindow = marker.time + 0.045 * speed

                                        -- Cycle reset for looping attacks
                                        if trackPos < triggerTime - 0.1 then
                                            seen[marker.index] = nil
                                        end

                                        if not seen[marker.index]
                                            and trackPos >= triggerTime
                                            and trackPos <= upperWindow then
                                            seen[marker.index] = true
                                            tapGuard(character)
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

    -- Auto Parry Section
    CombatTab:CreateSection("Auto Parry (Overhauled)")
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
        CurrentValue = 15,
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
        Range = {35, 140},
        Increment = 5,
        Suffix = " ms",
        CurrentValue = 65,
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
        CurrentValue = true,
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

    CombatTab:CreateButton({
        Name = "Reload Attack Catalog",
        Callback = function()
            buildAttackCatalog()
        end,
    })

    -- Auto Counter Section
    CombatTab:CreateSection("Auto Counter (Riposte)")

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

    -- Combat Assist Section
    CombatTab:CreateSection("Combat Assist")

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
            if scanAccumulator >= 0.08 or not targetValid(currentTarget, settings.assistRange) then
                scanAccumulator = 0
                currentTarget = findBestTarget(settings.assistRange, settings.assistFov)
                updateHighlight()
            end
            if targetValid(currentTarget, settings.assistRange) then
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
            local targetName = currentTarget and currentTarget.player and currentTarget.player.Name or "none"
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
end
