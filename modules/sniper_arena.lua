-- RAVEN HUB | Sniper Arena - automatic aimlock, trigger bot, entity ESP
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local VirtualInputManager = game:GetService("VirtualInputManager")

    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}
    local espObjects = {}
    local lockedTarget = nil
    local triggerPending = false
    local triggerToken = 0
    local lastTriggerAt = 0
    local espAccumulator = 0
    local mouseHeld = false
    local bindingName = "RavenSniperArenaAim_" .. tostring(localPlayer.UserId)

    local settings = {
        aimlock = false,
        aimPart = "Head",
        fov = 200,
        smoothness = 1,
        triggerBot = false,
        triggerDelay = 0.03,
        triggerCooldown = 0.16,
        esp = false,
        espShowDistance = true,
        espShowHealth = true,
        teamCheck = true,
    }

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getCamera()
        return workspace.CurrentCamera
    end

    local function getHumanoid(model)
        return model and model:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot(model)
        return model and (model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("UpperTorso")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true))
    end

    local function getAimPart(model)
        if not model then return nil end
        if settings.aimPart == "Head" then
            return model:FindFirstChild("Head") or getRoot(model)
        end
        return model:FindFirstChild("HumanoidRootPart") or getRoot(model)
    end

    local function modelAlive(model)
        if not model or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
            return false
        end
        local humanoid = getHumanoid(model)
        return humanoid ~= nil and humanoid.Health > 0 and getAimPart(model) ~= nil
    end

    local function getEnemyHolder()
        local highlight = workspace:FindFirstChild("Highlight")
        local enemy = highlight and highlight:FindFirstChild("Enemy")
        return enemy and enemy:FindFirstChild("HighlightHolder")
    end

    local function playerIsEnemy(player)
        if player == localPlayer then return false end
        if not settings.teamCheck then return true end
        if localPlayer.Team == nil or player.Team == nil then return true end
        return player.Team ~= localPlayer.Team
    end

    local function collectEnemyModels()
        local models = {}
        local seen = {}
        local localCharacter = localPlayer.Character

        local function add(model, player)
            if model ~= localCharacter and not seen[model] and modelAlive(model) then
                seen[model] = true
                table.insert(models, {model = model, player = player or Players:GetPlayerFromCharacter(model)})
            end
        end

        local holder = getEnemyHolder()
        if holder then
            for _, child in ipairs(holder:GetChildren()) do
                if child:IsA("Model") then
                    add(child)
                end
            end
        end

        for _, player in ipairs(Players:GetPlayers()) do
            if playerIsEnemy(player) then
                add(player.Character, player)
            end
        end

        return models
    end

    local function projectPart(part)
        local camera = getCamera()
        if not camera or not part then return nil, false, math.huge end
        local point, onScreen = camera:WorldToViewportPoint(part.Position)
        if point.Z <= 0 then onScreen = false end
        local center = Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
        return Vector2.new(point.X, point.Y), onScreen, (Vector2.new(point.X, point.Y) - center).Magnitude
    end

    local function buildTarget(entity)
        local part = getAimPart(entity.model)
        if not part then return nil end
        local _, onScreen, screenDistance = projectPart(part)
        if not onScreen then return nil end
        return {
            model = entity.model,
            player = entity.player,
            part = part,
            screenDistance = screenDistance,
        }
    end

    local function getBestTarget(fovOverride)
        local best = nil
        local bestDistance = fovOverride or settings.fov
        for _, entity in ipairs(collectEnemyModels()) do
            local target = buildTarget(entity)
            if target and target.screenDistance < bestDistance then
                best = target
                bestDistance = target.screenDistance
            end
        end
        return best
    end

    local function refreshTarget(target)
        if not target or not modelAlive(target.model) then return nil end
        target.part = getAimPart(target.model)
        local _, onScreen, screenDistance = projectPart(target.part)
        if not onScreen or screenDistance > settings.fov then return nil end
        target.screenDistance = screenDistance
        return target
    end

    local function aimAt(target, deltaTime)
        local camera = getCamera()
        if not camera or not target or not target.part then return end
        local origin = camera.CFrame.Position
        if (target.part.Position - origin).Magnitude < 0.01 then return end
        local goal = CFrame.lookAt(origin, target.part.Position)
        local strength = math.clamp(settings.smoothness, 0.05, 1)
        local alpha = 1 - math.pow(1 - strength, math.max(deltaTime * 60, 0.01))
        camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
    end

    local function targetVisible(target)
        local camera = getCamera()
        if not camera or not target or not target.part then return false end
        local direction = target.part.Position - camera.CFrame.Position
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local filter = {}
        if localPlayer.Character then table.insert(filter, localPlayer.Character) end
        table.insert(filter, camera)
        params.FilterDescendantsInstances = filter
        local result = workspace:Raycast(camera.CFrame.Position, direction, params)
        return result == nil or result.Instance:IsDescendantOf(target.model)
    end

    local function releaseMouse()
        if not mouseHeld then return end
        mouseHeld = false
        local camera = getCamera()
        if camera then
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(
                    camera.ViewportSize.X * 0.5,
                    camera.ViewportSize.Y * 0.5,
                    0,
                    false,
                    game,
                    0
                )
            end)
        end
        if type(mouse1release) == "function" then
            pcall(mouse1release)
        end
    end

    local function fireWeaponInput()
        if type(mouse1click) == "function" then
            local ok = pcall(mouse1click)
            if ok then return true end
        end

        local camera = getCamera()
        if not camera then return false end
        local ok = pcall(function()
            mouseHeld = true
            VirtualInputManager:SendMouseButtonEvent(
                camera.ViewportSize.X * 0.5,
                camera.ViewportSize.Y * 0.5,
                0,
                true,
                game,
                0
            )
            task.wait(0.02)
            releaseMouse()
        end)
        if not ok then releaseMouse() end
        return ok
    end

    local function queueTrigger(target)
        if triggerPending or not settings.triggerBot then return end
        if not target or target.screenDistance > 20 or not targetVisible(target) then return end
        local now = os.clock()
        if now - lastTriggerAt < settings.triggerCooldown then return end

        lastTriggerAt = now
        triggerPending = true
        triggerToken = triggerToken + 1
        local token = triggerToken
        local model = target.model
        task.delay(settings.triggerDelay, function()
            if token ~= triggerToken then return end
            triggerPending = false
            if running and settings.triggerBot and modelAlive(model) then
                local current = buildTarget({model = model, player = Players:GetPlayerFromCharacter(model)})
                if current and current.screenDistance <= 24 and targetVisible(current) then
                    fireWeaponInput()
                end
            end
        end)
    end

    local function createEsp(model, player)
        if espObjects[model] then return espObjects[model] end

        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenSniperArenaESP"
        highlight.FillColor = Color3.fromRGB(255, 55, 65)
        highlight.OutlineColor = Color3.fromRGB(255, 180, 185)
        highlight.FillTransparency = 0.72
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = model
        highlight.Parent = model

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenSniperArenaInfo"
        billboard.Size = UDim2.fromOffset(190, 38)
        billboard.StudsOffset = Vector3.new(0, 3.3, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 5000
        billboard.Parent = model

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 100, 105)
        label.TextStrokeTransparency = 0.35
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.Parent = billboard

        local objects = {highlight = highlight, billboard = billboard, label = label, player = player}
        espObjects[model] = objects
        return objects
    end

    local function removeEsp(model)
        local objects = espObjects[model]
        if not objects then return end
        pcall(function() objects.highlight:Destroy() end)
        pcall(function() objects.billboard:Destroy() end)
        espObjects[model] = nil
    end

    local function clearAllEsp()
        local models = {}
        for model in pairs(espObjects) do table.insert(models, model) end
        for _, model in ipairs(models) do removeEsp(model) end
    end

    local function updateEsp()
        if not settings.esp then
            clearAllEsp()
            return
        end

        local active = {}
        local myRoot = getRoot(localPlayer.Character)
        for _, entity in ipairs(collectEnemyModels()) do
            local model = entity.model
            local root = getRoot(model)
            local humanoid = getHumanoid(model)
            if root and humanoid and humanoid.Health > 0 then
                active[model] = true
                local objects = createEsp(model, entity.player)
                objects.highlight.Adornee = model
                objects.highlight.Enabled = true
                objects.billboard.Adornee = root
                objects.billboard.Enabled = true

                local displayName = entity.player and entity.player.DisplayName or model.Name
                local text = displayName
                if settings.espShowDistance and myRoot then
                    text = text .. " [" .. math.floor((root.Position - myRoot.Position).Magnitude) .. "m]"
                end
                if settings.espShowHealth then
                    text = text .. " " .. math.floor(humanoid.Health) .. "hp"
                end
                objects.label.Text = text
            end
        end

        local stale = {}
        for model in pairs(espObjects) do
            if not active[model] then table.insert(stale, model) end
        end
        for _, model in ipairs(stale) do removeEsp(model) end
    end

    pcall(function() RunService:UnbindFromRenderStep(bindingName) end)
    RunService:BindToRenderStep(bindingName, 10000, function(deltaTime)
        if not running then return end

        if settings.aimlock then
            lockedTarget = refreshTarget(lockedTarget)
            if not lockedTarget then
                lockedTarget = getBestTarget()
            end
            if lockedTarget then
                aimAt(lockedTarget, deltaTime)
                lockedTarget = refreshTarget(lockedTarget)
            end
        else
            lockedTarget = nil
        end

        if settings.triggerBot then
            local triggerTarget = lockedTarget or getBestTarget(20)
            if triggerTarget then
                triggerTarget = refreshTarget(triggerTarget)
                queueTrigger(triggerTarget)
            end
        end
    end)

    connect(RunService.Heartbeat, function(deltaTime)
        if not running then return end
        espAccumulator = espAccumulator + deltaTime
        if espAccumulator >= 0.1 then
            espAccumulator = 0
            updateEsp()
        end
    end)

    local CombatTab = Window:CreateTab("Combat", "combat")
    CombatTab:CreateSection("Automatic Aimlock")
    CombatTab:CreateToggle({
        Name = "Auto Lock",
        CurrentValue = false,
        Flag = "SAAutoLock",
        Callback = function(value)
            settings.aimlock = value
            lockedTarget = value and getBestTarget() or nil
        end,
    })
    CombatTab:CreateDropdown({
        Name = "Aim Part",
        Options = {"Head", "HumanoidRootPart"},
        CurrentOption = {"Head"},
        MultipleOptions = false,
        Flag = "SAAimPart",
        Callback = function(value)
            settings.aimPart = type(value) == "table" and value[1] or tostring(value)
            lockedTarget = nil
        end,
    })
    CombatTab:CreateSlider({
        Name = "Lock FOV",
        Range = {40, 500},
        Increment = 10,
        Suffix = " px",
        CurrentValue = 200,
        Flag = "SAFOV",
        Callback = function(value) settings.fov = value end,
    })
    CombatTab:CreateSlider({
        Name = "Aim Speed",
        Range = {5, 100},
        Increment = 5,
        Suffix = "%",
        CurrentValue = 100,
        Flag = "SAAimSpeed",
        Callback = function(value) settings.smoothness = value / 100 end,
    })
    CombatTab:CreateToggle({
        Name = "Team Check",
        CurrentValue = true,
        Flag = "SATeamCheck",
        Callback = function(value)
            settings.teamCheck = value
            lockedTarget = nil
        end,
    })

    CombatTab:CreateSection("Trigger Bot")
    CombatTab:CreateToggle({
        Name = "Trigger Bot",
        CurrentValue = false,
        Flag = "SATriggerBot",
        Callback = function(value)
            settings.triggerBot = value
            if not value then
                triggerToken = triggerToken + 1
                triggerPending = false
                releaseMouse()
            end
        end,
    })
    CombatTab:CreateSlider({
        Name = "Trigger Delay",
        Range = {0, 200},
        Increment = 10,
        Suffix = " ms",
        CurrentValue = 30,
        Flag = "SATriggerDelay",
        Callback = function(value) settings.triggerDelay = value / 1000 end,
    })

    local VisualTab = Window:CreateTab("Visual", "esp")
    VisualTab:CreateSection("Entity ESP")
    VisualTab:CreateToggle({
        Name = "ESP",
        CurrentValue = false,
        Flag = "SAESP",
        Callback = function(value)
            settings.esp = value
            if value then updateEsp() else clearAllEsp() end
        end,
    })
    VisualTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "SAESPDistance",
        Callback = function(value) settings.espShowDistance = value end,
    })
    VisualTab:CreateToggle({
        Name = "Show Health",
        CurrentValue = true,
        Flag = "SAESPHealth",
        Callback = function(value) settings.espShowHealth = value end,
    })

    local MiscTab = Window:CreateTab("Misc", "misc")
    MiscTab:CreateSection("Utilities")
    MiscTab:CreateButton({
        Name = "Rejoin",
        Callback = function()
            pcall(function()
                game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId)
            end)
        end,
    })
    MiscTab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId) end)
        end,
    })

    local function destroyScript()
        if not running then return end
        running = false
        settings.aimlock = false
        settings.triggerBot = false
        settings.esp = false
        lockedTarget = nil
        triggerToken = triggerToken + 1
        triggerPending = false
        pcall(function() RunService:UnbindFromRenderStep(bindingName) end)
        releaseMouse()
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