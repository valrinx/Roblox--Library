-- RAVEN HUB | TWDO3 combat targeting and reversible hitbox controls
return function(context)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")

    local Window = context.Window
    local localPlayer = context.localPlayer
    local settings = context.settings
    local scriptRunning = true
    local connections = {}
    local originalHitboxes = {}
    local currentTarget = nil
    local rmbHeld = false
    local keybindHeld = false
    local scanAccumulator = 0
    local hitboxAccumulator = 0
    local statusAccumulator = 0
    local triggerPending = false
    local lastTrigger = 0
    local triggerUnsupportedNotified = false

    local function applyDefault(key, value)
        if settings[key] == nil then
            settings[key] = value
        end
    end

    applyDefault("aimPlayers", false)
    applyDefault("aimWalkers", false)
    applyDefault("autoLock", false)
    applyDefault("stickyTarget", true)
    applyDefault("aimWhileRmb", true)
    applyDefault("targetBone", "Head")
    applyDefault("aimStrength", 0.22)
    applyDefault("aimFov", 180)
    applyDefault("aimRange", 1200)
    applyDefault("targetPriority", "Crosshair")
    applyDefault("predictionEnabled", true)
    applyDefault("predictionTime", 0.12)
    applyDefault("predictionDistanceScale", 0.08)
    applyDefault("aimWallCheck", true)
    applyDefault("ignoreTeammates", true)
    applyDefault("ignoreFriends", true)
    applyDefault("triggerBot", false)
    applyDefault("triggerDelay", 0.08)
    applyDefault("triggerRadius", 10)
    applyDefault("showFovCircle", true)
    applyDefault("showTargetIndicator", true)
    applyDefault("bigHeadPlayers", false)
    applyDefault("bigHeadWalkers", false)
    applyDefault("bigHeadSize", 4)
    applyDefault("bigHeadTransparency", 0.65)
    applyDefault("teammateEsp", true)

    local function disconnect(connection)
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    local friendCache = {}
    local friendCacheTime = {}
    local FRIEND_CACHE_TTL = 30 -- seconds

    local function isFriend(player)
        if not player or player == localPlayer then
            return false
        end
        local userId = player.UserId
        local now = os.clock()
        if friendCache[userId] ~= nil and (now - (friendCacheTime[userId] or 0)) < FRIEND_CACHE_TTL then
            return friendCache[userId]
        end
        local ok, result = pcall(function()
            return localPlayer:IsFriendsWith(userId)
        end)
        if ok then
            friendCache[userId] = result
            friendCacheTime[userId] = now
            return result
        end
        return friendCache[userId] or false
    end

    local function isTeammate(player)
        return player
            and player ~= localPlayer
            and localPlayer.Team ~= nil
            and player.Team == localPlayer.Team
    end

    local function shouldIgnorePlayer(player)
        if not player or player == localPlayer then
            return true
        end
        if settings.ignoreTeammates and isTeammate(player) then
            return true
        end
        if settings.ignoreFriends and isFriend(player) then
            return true
        end
        return false
    end

    local function getWalkerFolder()
        local ai = workspace:FindFirstChild("AI")
        return ai and ai:FindFirstChild("Walkers")
    end

    local function getTargetPart(model)
        if not model then
            return nil
        end
        if settings.targetBone == "Head" then
            return model:FindFirstChild("Head")
                or model:FindFirstChild("HeadHitbox")
                or model:FindFirstChild("HumanoidRootPart")
        end
        return model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("HumanoidRootPart")
    end

    local function getRoot(model)
        return model and (model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso"))
    end

    local function isAlive(model)
        local humanoid = model and model:FindFirstChildOfClass("Humanoid")
        return humanoid ~= nil and humanoid.Health > 0
    end

    local function getPredictedPosition(target)
        local part = getTargetPart(target.model)
        if not part or not part:IsA("BasePart") then
            return nil
        end
        local position = part.Position
        if settings.predictionEnabled then
            local root = getRoot(target.model) or part
            local camera = workspace.CurrentCamera
            local distance = camera and (part.Position - camera.CFrame.Position).Magnitude or 0
            local leadTime = settings.predictionTime
                + (distance / 1000) * settings.predictionDistanceScale
            position += root.AssemblyLinearVelocity * leadTime
        end
        return position
    end

    local function hasLineOfSight(target, position)
        if not settings.aimWallCheck then
            return true
        end
        local camera = workspace.CurrentCamera
        if not camera or not position then
            return false
        end
        local exclusions = {context.espFolder}
        if localPlayer.Character then
            table.insert(exclusions, localPlayer.Character)
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = exclusions
        params.IgnoreWater = true
        params.RespectCanCollide = false
        local direction = position - camera.CFrame.Position
        for _ = 1, 8 do
            local result = workspace:Raycast(camera.CFrame.Position, direction, params)
            if not result then
                return true
            end
            if result.Instance == target.model or result.Instance:IsDescendantOf(target.model) then
                return true
            end
            local canSkip = result.Instance:IsA("BasePart")
                and (not result.Instance.CanCollide or result.Instance.Transparency >= 0.95)
            if not canSkip then
                return false
            end
            table.insert(exclusions, result.Instance)
            params.FilterDescendantsInstances = exclusions
        end
        return false
    end

    local function targetValid(target, requireFov)
        if not target or not target.model or not target.model.Parent or not isAlive(target.model) then
            return false
        end
        if target.kind == "player" then
            if not settings.aimPlayers or not target.player or target.player.Parent ~= Players then
                return false
            end
            if shouldIgnorePlayer(target.player) then
                return false
            end
        elseif not settings.aimWalkers then
            return false
        end

        local camera = workspace.CurrentCamera
        local _, _, localRoot = context.getCharacterParts(localPlayer)
        local position = getPredictedPosition(target)
        if not camera or not localRoot or not position then
            return false
        end
        local distance = (position - localRoot.Position).Magnitude
        if distance > settings.aimRange or not hasLineOfSight(target, position) then
            return false
        end
        if requireFov then
            local point, onScreen = camera:WorldToViewportPoint(position)
            local center = camera.ViewportSize * 0.5
            if not onScreen or point.Z <= 0
                or (Vector2.new(point.X, point.Y) - center).Magnitude > settings.aimFov then
                return false
            end
        end
        return true
    end

    local function scoreTarget(target, camera, localRoot)
        local position = getPredictedPosition(target)
        if not position then
            return nil
        end
        local distance = (position - localRoot.Position).Magnitude
        if distance > settings.aimRange or not hasLineOfSight(target, position) then
            return nil
        end
        local point, onScreen = camera:WorldToViewportPoint(position)
        if not onScreen or point.Z <= 0 then
            return nil
        end
        local center = camera.ViewportSize * 0.5
        local crosshairDistance = (Vector2.new(point.X, point.Y) - center).Magnitude
        if crosshairDistance > settings.aimFov then
            return nil
        end
        return settings.targetPriority == "Distance" and distance or crosshairDistance
    end

    local function findBestTarget()
        local camera = workspace.CurrentCamera
        local _, _, localRoot = context.getCharacterParts(localPlayer)
        if not camera or not localRoot then
            return nil
        end
        local best = nil
        local bestScore = math.huge

        if settings.aimPlayers then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer and not shouldIgnorePlayer(player) then
                    local model = player.Character
                    if model and isAlive(model) and getTargetPart(model) then
                        local target = {kind = "player", player = player, model = model}
                        local score = scoreTarget(target, camera, localRoot)
                        if score and score < bestScore then
                            best = target
                            bestScore = score
                        end
                    end
                end
            end
        end

        if settings.aimWalkers then
            local folder = getWalkerFolder()
            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    if model:IsA("Model") and isAlive(model) and getTargetPart(model) then
                        local target = {kind = "walker", model = model}
                        local score = scoreTarget(target, camera, localRoot)
                        if score and score < bestScore then
                            best = target
                            bestScore = score
                        end
                    end
                end
            end
        end
        return best
    end

    local function targetLabel(target)
        if not target then
            return "none"
        end
        if target.kind == "player" and target.player then
            return context.playerLabel(target.player)
        end
        return "Walker"
    end

    local previousGui = nil
    local guiParent = localPlayer:WaitForChild("PlayerGui")
    pcall(function()
        if type(gethui) == "function" then
            guiParent = gethui()
        end
        previousGui = guiParent:FindFirstChild("RavenHub_TWDO3_Combat")
    end)
    if previousGui then
        previousGui:Destroy()
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "RavenHub_TWDO3_Combat"
    screenGui.IgnoreGuiInset = true
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 901
    screenGui.Parent = guiParent

    local fovCircle = Instance.new("Frame")
    fovCircle.Name = "FOVCircle"
    fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCircle.BackgroundTransparency = 1
    fovCircle.ZIndex = 50
    fovCircle.Parent = screenGui
    local fovCorner = Instance.new("UICorner")
    fovCorner.CornerRadius = UDim.new(1, 0)
    fovCorner.Parent = fovCircle
    local fovStroke = Instance.new("UIStroke")
    fovStroke.Color = Color3.fromRGB(110, 180, 255)
    fovStroke.Transparency = 0.25
    fovStroke.Thickness = 1
    fovStroke.Parent = fovCircle

    local targetIndicator = Instance.new("TextLabel")
    targetIndicator.Name = "TargetIndicator"
    targetIndicator.AnchorPoint = Vector2.new(0.5, 0)
    targetIndicator.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
    targetIndicator.BackgroundTransparency = 0.25
    targetIndicator.BorderSizePixel = 0
    targetIndicator.Size = UDim2.fromOffset(220, 24)
    targetIndicator.Font = Enum.Font.GothamBold
    targetIndicator.TextColor3 = Color3.fromRGB(230, 235, 245)
    targetIndicator.TextSize = 11
    targetIndicator.Text = "TARGET: none"
    targetIndicator.ZIndex = 51
    targetIndicator.Parent = screenGui
    local indicatorCorner = Instance.new("UICorner")
    indicatorCorner.CornerRadius = UDim.new(0, 6)
    indicatorCorner.Parent = targetIndicator

    local function updateOverlay()
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end
        local center = camera.ViewportSize * 0.5
        fovCircle.Position = UDim2.fromOffset(center.X, center.Y)
        fovCircle.Size = UDim2.fromOffset(settings.aimFov * 2, settings.aimFov * 2)
        fovCircle.Visible = settings.showFovCircle and (settings.aimPlayers or settings.aimWalkers)
        fovStroke.Color = currentTarget and Color3.fromRGB(255, 95, 75) or Color3.fromRGB(110, 180, 255)
        targetIndicator.Position = UDim2.fromOffset(center.X, center.Y + settings.aimFov + 12)
        targetIndicator.Visible = settings.showTargetIndicator and (settings.aimPlayers or settings.aimWalkers)
        targetIndicator.Text = "TARGET: " .. targetLabel(currentTarget)
    end

    local function restoreHitbox(part)
        local original = originalHitboxes[part]
        if not original then
            return
        end
        if part.Parent then
            pcall(function()
                part.Size = original.Size
                part.Transparency = original.Transparency
                part.CanCollide = original.CanCollide
                part.Massless = original.Massless
            end)
        end
        originalHitboxes[part] = nil
    end

    local function restoreAllHitboxes()
        local parts = {}
        for part in pairs(originalHitboxes) do
            table.insert(parts, part)
        end
        for _, part in ipairs(parts) do
            restoreHitbox(part)
        end
    end

    local function applyHitbox(part)
        if not part or not part:IsA("BasePart") then
            return
        end
        if not originalHitboxes[part] then
            originalHitboxes[part] = {
                Size = part.Size,
                Transparency = part.Transparency,
                CanCollide = part.CanCollide,
                Massless = part.Massless,
            }
        end
        local size = settings.bigHeadSize
        pcall(function()
            part.Size = Vector3.new(size, size, size)
            part.Transparency = settings.bigHeadTransparency
            part.CanCollide = false
            part.Massless = true
        end)
    end

    local function syncHitboxes()
        local desired = {}
        if settings.bigHeadPlayers then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer and not shouldIgnorePlayer(player) then
                    local character = player.Character
                    local head = character and character:FindFirstChild("Head")
                    if head and isAlive(character) then
                        desired[head] = true
                        applyHitbox(head)
                    end
                end
            end
        end
        if settings.bigHeadWalkers then
            local folder = getWalkerFolder()
            if folder then
                for _, model in ipairs(folder:GetChildren()) do
                    if model:IsA("Model") and isAlive(model) then
                        local head = model:FindFirstChild("Head") or model:FindFirstChild("HeadHitbox")
                        if head then
                            desired[head] = true
                            applyHitbox(head)
                        end
                    end
                end
            end
        end
        local stale = {}
        for part in pairs(originalHitboxes) do
            if not desired[part] then
                table.insert(stale, part)
            end
        end
        for _, part in ipairs(stale) do
            restoreHitbox(part)
        end
    end

    local function fireMouse()
        if UserInputService:GetFocusedTextBox() then
            return false
        end
        local clickFunction = nil
        pcall(function()
            if type(getgenv) == "function" then
                clickFunction = getgenv().mouse1click
            end
        end)
        if type(clickFunction) == "function" then
            return pcall(clickFunction)
        end
        local virtualInput = nil
        pcall(function()
            virtualInput = game:GetService("VirtualInputManager")
        end)
        if virtualInput then
            local camera = workspace.CurrentCamera
            local center = camera and camera.ViewportSize * 0.5 or Vector2.zero
            local ok = pcall(function()
                virtualInput:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                task.delay(0.02, function()
                    pcall(function()
                        virtualInput:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
                    end)
                end)
            end)
            return ok
        end
        return false
    end

    local function triggerReady(target)
        if not settings.triggerBot or not targetValid(target, false) then
            return false
        end
        local camera = workspace.CurrentCamera
        local position = getPredictedPosition(target)
        if not camera or not position then
            return false
        end
        local point, onScreen = camera:WorldToViewportPoint(position)
        local center = camera.ViewportSize * 0.5
        return onScreen and point.Z > 0
            and (Vector2.new(point.X, point.Y) - center).Magnitude <= settings.triggerRadius
    end

    local function scheduleTrigger(target)
        if triggerPending or os.clock() - lastTrigger < settings.triggerDelay then
            return
        end
        triggerPending = true
        local scheduledTarget = target
        task.delay(settings.triggerDelay, function()
            triggerPending = false
            if not scriptRunning or currentTarget ~= scheduledTarget or not triggerReady(scheduledTarget) then
                return
            end
            if fireMouse() then
                lastTrigger = os.clock()
            elseif not triggerUnsupportedNotified then
                triggerUnsupportedNotified = true
                context.notify("Trigger Bot", "Mouse injection is unavailable in this executor")
            end
        end)
    end

    local function shouldAim()
        return settings.autoLock or keybindHeld or (settings.aimWhileRmb and rmbHeld)
    end

    local function aimAtTarget(target, deltaTime)
        local camera = workspace.CurrentCamera
        local position = getPredictedPosition(target)
        if not camera or not position then
            return
        end
        local desired = CFrame.lookAt(camera.CFrame.Position, position)
        local alpha = 1 - math.pow(1 - math.clamp(settings.aimStrength, 0.01, 1), deltaTime * 60)
        camera.CFrame = camera.CFrame:Lerp(desired, math.clamp(alpha, 0, 1))
    end

    local CombatTab = Window:CreateTab("Combat", 4483362458)
    local combatStatus = CombatTab:CreateLabel("Target: none | Aim idle")

    CombatTab:CreateSection("Targets / Lock")
    CombatTab:CreateToggle({
        Name = "Aimbot Players",
        CurrentValue = false,
        Flag = "TWDO3AimbotPlayers",
        Callback = function(value)
            settings.aimPlayers = value
            if not value and currentTarget and currentTarget.kind == "player" then
                currentTarget = nil
            end
        end,
    })
    CombatTab:CreateToggle({
        Name = "Aimbot Walkers",
        CurrentValue = false,
        Flag = "TWDO3AimbotWalkers",
        Callback = function(value)
            settings.aimWalkers = value
            if not value and currentTarget and currentTarget.kind == "walker" then
                currentTarget = nil
            end
        end,
    })
    CombatTab:CreateToggle({
        Name = "Auto Lock",
        CurrentValue = false,
        Flag = "TWDO3AutoLock",
        Callback = function(value)
            settings.autoLock = value
        end,
    })
    CombatTab:CreateToggle({
        Name = "Sticky Target",
        CurrentValue = true,
        Flag = "TWDO3StickyTarget",
        Callback = function(value)
            settings.stickyTarget = value
        end,
    })
    CombatTab:CreateToggle({
        Name = "Aim While Holding RMB",
        CurrentValue = true,
        Flag = "TWDO3AimRMB",
        Callback = function(value)
            settings.aimWhileRmb = value
        end,
    })
    CombatTab:CreateKeybind({
        Name = "Aim Hold Key",
        CurrentKeybind = "Q",
        HoldToInteract = true,
        Flag = "TWDO3AimHoldKey",
        Callback = function(value)
            keybindHeld = value == true
        end,
    })
    CombatTab:CreateDropdown({
        Name = "Target Part",
        Options = {"Head", "Body"},
        CurrentOption = {"Head"},
        MultipleOptions = false,
        Flag = "TWDO3AimTargetPart",
        Callback = function(value)
            settings.targetBone = context.getDropdownValue(value) or "Head"
        end,
    })
    CombatTab:CreateDropdown({
        Name = "Target Priority",
        Options = {"Crosshair", "Distance"},
        CurrentOption = {"Crosshair"},
        MultipleOptions = false,
        Flag = "TWDO3AimPriority",
        Callback = function(value)
            settings.targetPriority = context.getDropdownValue(value) or "Crosshair"
        end,
    })
    CombatTab:CreateToggle({
        Name = "Ignore Teammates",
        CurrentValue = true,
        Flag = "TWDO3AimIgnoreTeam",
        Callback = function(value)
            settings.ignoreTeammates = value
        end,
    })
    CombatTab:CreateToggle({
        Name = "Ignore Friends",
        CurrentValue = true,
        Flag = "TWDO3AimIgnoreFriends",
        Callback = function(value)
            settings.ignoreFriends = value
        end,
    })
    CombatTab:CreateToggle({
        Name = "Aim Wall Check",
        CurrentValue = true,
        Flag = "TWDO3AimWallCheck",
        Callback = function(value)
            settings.aimWallCheck = value
        end,
    })

    CombatTab:CreateSection("Aim Tuning")
    CombatTab:CreateSlider({
        Name = "Aimbot Strength",
        Range = {1, 100},
        Increment = 1,
        Suffix = "%",
        CurrentValue = 22,
        Flag = "TWDO3AimStrength",
        Callback = function(value)
            settings.aimStrength = value / 100
        end,
    })
    CombatTab:CreateSlider({
        Name = "Aim FOV",
        Range = {30, 500},
        Increment = 10,
        Suffix = " px",
        CurrentValue = 180,
        Flag = "TWDO3AimFOV",
        Callback = function(value)
            settings.aimFov = value
        end,
    })
    CombatTab:CreateSlider({
        Name = "Target Range",
        Range = {100, 3000},
        Increment = 100,
        Suffix = " studs",
        CurrentValue = 1200,
        Flag = "TWDO3AimRange",
        Callback = function(value)
            settings.aimRange = value
        end,
    })
    CombatTab:CreateToggle({
        Name = "Manual Aim Prediction",
        CurrentValue = true,
        Flag = "TWDO3AimPrediction",
        Callback = function(value)
            settings.predictionEnabled = value
        end,
    })
    CombatTab:CreateSlider({
        Name = "Prediction Time",
        Range = {0, 500},
        Increment = 10,
        Suffix = " ms",
        CurrentValue = 120,
        Flag = "TWDO3AimPredictionTime",
        Callback = function(value)
            settings.predictionTime = value / 1000
        end,
    })
    CombatTab:CreateSlider({
        Name = "Distance Prediction Scale",
        Range = {0, 300},
        Increment = 10,
        Suffix = " ms / 1000 studs",
        CurrentValue = 80,
        Flag = "TWDO3AimDistancePrediction",
        Callback = function(value)
            settings.predictionDistanceScale = value / 1000
        end,
    })
    CombatTab:CreateToggle({
        Name = "Show FOV Circle",
        CurrentValue = true,
        Flag = "TWDO3ShowAimFOV",
        Callback = function(value)
            settings.showFovCircle = value
        end,
    })
    CombatTab:CreateToggle({
        Name = "Show Target Indicator",
        CurrentValue = true,
        Flag = "TWDO3ShowTargetIndicator",
        Callback = function(value)
            settings.showTargetIndicator = value
        end,
    })

    CombatTab:CreateSection("Trigger Bot")
    CombatTab:CreateToggle({
        Name = "Trigger Bot",
        CurrentValue = false,
        Flag = "TWDO3TriggerBot",
        Callback = function(value)
            settings.triggerBot = value
        end,
    })
    CombatTab:CreateSlider({
        Name = "Trigger Delay",
        Range = {0, 500},
        Increment = 10,
        Suffix = " ms",
        CurrentValue = 80,
        Flag = "TWDO3TriggerDelay",
        Callback = function(value)
            settings.triggerDelay = value / 1000
        end,
    })
    CombatTab:CreateSlider({
        Name = "Trigger Radius",
        Range = {2, 40},
        Increment = 1,
        Suffix = " px",
        CurrentValue = 10,
        Flag = "TWDO3TriggerRadius",
        Callback = function(value)
            settings.triggerRadius = value
        end,
    })

    CombatTab:CreateSection("Big Head Hitbox")
    CombatTab:CreateToggle({
        Name = "Big Head Players",
        CurrentValue = false,
        Flag = "TWDO3BigHeadPlayers",
        Callback = function(value)
            settings.bigHeadPlayers = value
            if not value and not settings.bigHeadWalkers then
                restoreAllHitboxes()
            end
        end,
    })
    CombatTab:CreateToggle({
        Name = "Big Head Walkers",
        CurrentValue = false,
        Flag = "TWDO3BigHeadWalkers",
        Callback = function(value)
            settings.bigHeadWalkers = value
            if not value and not settings.bigHeadPlayers then
                restoreAllHitboxes()
            end
        end,
    })
    CombatTab:CreateSlider({
        Name = "Head Hitbox Size",
        Range = {2, 12},
        Increment = 0.5,
        Suffix = " studs",
        CurrentValue = 4,
        Flag = "TWDO3BigHeadSize",
        Callback = function(value)
            settings.bigHeadSize = value
        end,
    })
    CombatTab:CreateSlider({
        Name = "Head Transparency",
        Range = {0, 100},
        Increment = 5,
        Suffix = "%",
        CurrentValue = 65,
        Flag = "TWDO3BigHeadTransparency",
        Callback = function(value)
            settings.bigHeadTransparency = value / 100
        end,
    })
    CombatTab:CreateButton({
        Name = "Reset All Hitboxes",
        Callback = restoreAllHitboxes,
    })

    CombatTab:CreateSection("Team ESP")
    CombatTab:CreateToggle({
        Name = "Show Teammates in ESP",
        CurrentValue = true,
        Flag = "TWDO3TeammateESP",
        Callback = function(value)
            settings.teammateEsp = value
        end,
    })
    CombatTab:CreateLabel("Big Head is client-side and is restored automatically when disabled or reloaded")

    table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.UserInputType == Enum.UserInputType.MouseButton2 then
            rmbHeld = true
        end
    end))
    table.insert(connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            rmbHeld = false
        end
    end))
    table.insert(connections, RunService.RenderStepped:Connect(function(deltaTime)
        if not scriptRunning then
            return
        end
        scanAccumulator += deltaTime
        hitboxAccumulator += deltaTime
        statusAccumulator += deltaTime
        local active = shouldAim()
        local needsTarget = active or settings.triggerBot

        if needsTarget then
            local valid = targetValid(currentTarget, true)
            if scanAccumulator >= 0.1 and (not valid or not settings.stickyTarget) then
                currentTarget = findBestTarget()
                scanAccumulator = 0
            end
        else
            currentTarget = nil
        end

        if active and currentTarget and targetValid(currentTarget, true) then
            aimAtTarget(currentTarget, deltaTime)
        end
        if currentTarget and triggerReady(currentTarget) then
            scheduleTrigger(currentTarget)
        end
        if hitboxAccumulator >= 0.5 then
            hitboxAccumulator = 0
            syncHitboxes()
        end
        updateOverlay()
        if statusAccumulator >= 0.25 then
            statusAccumulator = 0
            pcall(function()
                combatStatus:Set(string.format(
                    "Target: %s | Aim %s | Wall check %s",
                    targetLabel(currentTarget),
                    active and "ACTIVE" or "idle",
                    settings.aimWallCheck and "ON" or "OFF"
                ))
            end)
        end
    end))

    local controller = {}
    function controller:Destroy()
        if not scriptRunning then
            return
        end
        scriptRunning = false
        currentTarget = nil
        triggerPending = false
        restoreAllHitboxes()
        for _, connection in ipairs(connections) do
            disconnect(connection)
        end
        table.clear(connections)
        screenGui:Destroy()
    end

    return controller
end
