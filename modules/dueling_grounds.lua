-- RAVEN HUB | Dueling Grounds combat assist and marker-driven auto parry
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local VirtualInputManager = game:GetService("VirtualInputManager")

    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}
    local currentTarget = nil
    local guardHeldByHub = false
    local guardReleaseToken = 0
    local lastParryAt = 0
    local lastLookReplication = 0
    local parryCount = 0
    local scanAccumulator = 0
    local statusAccumulator = 0

    local settings = {
        autoParry = false,
        parryRange = 14,
        reactionLead = 0.09,
        pingCompensation = true,
        guardHold = 0.07,
        requireFacing = true,
        combatAssist = false,
        assistRange = 28,
        assistFov = 140,
        assistStrength = 0.32,
        targetPriority = "Crosshair",
        showTarget = true,
    }

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local playerCharacterRemotes = remotes and remotes:FindFirstChild("PlayerCharacter")
    local requestRemotes = playerCharacterRemotes and playerCharacterRemotes:FindFirstChild("Request")
    local desiredLookRemote = requestRemotes and requestRemotes:FindFirstChild("SetDesiredLookDirection")

    local inputActions = ReplicatedStorage:FindFirstChild("Controllers")
    inputActions = inputActions and inputActions:FindFirstChild("PlayerInputController")
    inputActions = inputActions and inputActions:FindFirstChild("InputActions")
    local characterContext = inputActions and inputActions:FindFirstChild("CharacterGameplayContext")
    local weaponContext = characterContext and characterContext:FindFirstChild("EquippedWeaponContext")
    local guardAction = weaponContext and weaponContext:FindFirstChild("GuardAction")

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

    local attackCatalog = {}
    local catalogModuleCount = 0

    local function addAttackConfig(moduleScript, weaponName)
        local ok, config = pcall(require, moduleScript)
        if not ok or type(config) ~= "table" then
            return
        end
        local animation = config.animation
        local animationId = animation and normalizeAssetId(animation.AnimationId)
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
            local basicAttacks = weaponModule:FindFirstChild("BasicAttackTypes")
            if basicAttacks then
                for _, moduleScript in ipairs(basicAttacks:GetChildren()) do
                    if moduleScript:IsA("ModuleScript") then
                        addAttackConfig(moduleScript, weaponModule.Name)
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
        return (root.Position - localRoot.Position).Magnitude <= maxRange
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
                    local distance = (root.Position - localRoot.Position).Magnitude
                    if distance <= maxRange then
                        local angle = targetAngle(camera, root.Position)
                        if angle <= fov * 0.5 then
                            local score = settings.targetPriority == "Distance" and distance or angle
                            if score < bestScore then
                                bestScore = score
                                bestTarget = {
                                    player = player,
                                    character = character,
                                    root = root,
                                    distance = distance,
                                }
                            end
                        end
                    end
                end
            end
        end
        return bestTarget
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
        return math.clamp((tonumber(value) or 0) / 2000, 0, 0.1)
    end

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

    local function tapGuard()
        local now = os.clock()
        if now - lastParryAt < 0.12 then
            return false
        end
        lastParryAt = now
        parryCount += 1
        guardReleaseToken += 1
        local token = guardReleaseToken

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

    local seenTrackMarkers = setmetatable({}, {__mode = "k"})

    local function opponentFacingLocal(opponentRoot, localRoot)
        if not settings.requireFacing then
            return true
        end
        local offset = localRoot.Position - opponentRoot.Position
        if offset.Magnitude < 0.001 then
            return true
        end
        return opponentRoot.CFrame.LookVector:Dot(offset.Unit) >= 0.05
    end

    local function scanOpponentAttacks()
        local localCharacter = getCharacter(localPlayer)
        local localRoot = getRoot(localCharacter)
        if not localRoot or not characterAlive(localCharacter)
            or localCharacter:GetAttribute("InSafeZone") == true then
            return
        end

        local realLead = settings.reactionLead + getPingSeconds()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then
                local character = getCharacter(player)
                local root = getRoot(character)
                if root and targetValid({character = character}, settings.parryRange)
                    and opponentFacingLocal(root, localRoot) then
                    local humanoid = character:FindFirstChildOfClass("Humanoid")
                    local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
                    if animator then
                        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                            local animationId = track.Animation and normalizeAssetId(track.Animation.AnimationId)
                            local attack = animationId and attackCatalog[animationId]
                            if attack then
                                local seen = seenTrackMarkers[track]
                                if not seen then
                                    seen = {}
                                    seenTrackMarkers[track] = seen
                                end
                                local speed = math.max(math.abs(track.Speed), 0.01)
                                local animationLead = realLead * speed
                                for _, marker in ipairs(attack.markers) do
                                    local triggerTime = math.max(0, marker.time - animationLead)
                                    if not seen[marker.index]
                                        and track.TimePosition >= triggerTime
                                        and track.TimePosition <= marker.time + 0.035 * speed then
                                        seen[marker.index] = true
                                        tapGuard()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

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

    local CombatTab = Window:CreateTab("Combat", "swords")
    CombatTab:CreateSection("Auto Parry")
    local statusLabel = CombatTab:CreateLabel("Attack catalog: " .. tostring(catalogModuleCount) .. " animations")

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
        Range = {5, 30},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = 14,
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
        Name = "Guard Hold",
        Range = {40, 130},
        Increment = 5,
        Suffix = " ms",
        CurrentValue = 70,
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
        Name = "Require Enemy Facing You",
        CurrentValue = true,
        Flag = "DGRequireFacing",
        Callback = function(value)
            settings.requireFacing = value
        end,
    })
    CombatTab:CreateButton({
        Name = "Reload Attack Catalog",
        Callback = buildAttackCatalog,
    })

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
    CombatTab:CreateLabel("Auto Parry reads each weapon's real impact marker; no hard-coded animation list is required.")

    table.insert(connections, RunService.RenderStepped:Connect(function(deltaTime)
        if not running then
            return
        end
        scanAccumulator += deltaTime
        statusAccumulator += deltaTime

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

        if settings.autoParry then
            scanOpponentAttacks()
        end

        if statusAccumulator >= 0.25 then
            statusAccumulator = 0
            local targetName = currentTarget and currentTarget.player and currentTarget.player.Name or "none"
            pcall(function()
                statusLabel:Set(string.format(
                    "Catalog: %d | Target: %s | Parries: %d",
                    catalogModuleCount,
                    targetName,
                    parryCount
                ))
            end)
        end
    end))

    local function destroyScript()
        if not running then
            return
        end
        running = false
        guardReleaseToken += 1
        releaseGuard()
        currentTarget = nil
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
