-- ============================================================
--   RAVEN HUB  |  RIVALS Modular Suite v1.4.2
--   Universal Native Drawing API ESP & Robust mousemoverel Aimbot
--   PlaceId: 117398147513099 | UniverseId: 6035872082
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local LocalPlayer = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera")

    -- Clean up previous instance
    local env = getgenv and getgenv() or _G
    if type(env.__RAVEN_RIVALS) == "table" and type(env.__RAVEN_RIVALS.Destroy) == "function" then
        pcall(env.__RAVEN_RIVALS.Destroy)
    end

    local running = true
    local connections = {}

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(connections, conn)
        return conn
    end

    -- ------------------------------------------------------------
    -- Configuration State
    -- ------------------------------------------------------------
    local aimbotSettings = {
        enabled = true,
        aimKey = Enum.UserInputType.MouseButton2,
        toggleMode = false,
        targetPart = "Head", -- "Head" or "UpperTorso"
        method = "Mouse", -- "Mouse" or "Camera"
        fov = 150,
        smoothness = 0.25,
        wallCheck = true,
        targetTeammates = false,
        includeDummies = true,
        
        drawFov = true,
        fovColor = Color3.fromRGB(0, 230, 255),
        fovLockedColor = Color3.fromRGB(50, 255, 120),
        fovThickness = 1,
        fovTransparency = 0.75,
        isAiming = false,
        customKey = nil
    }

    local triggerbotSettings = {
        enabled = false,
        mode = "While Aiming (RMB)", -- "Always Active", "While Aiming (RMB)", "Hold Keybind", "Toggle Keybind"
        activationKey = Enum.KeyCode.LeftAlt,
        isActive = false,
        delay = 0.02,
        cooldown = 0.12,
        crosshairTolerance = 14,
        headOnly = false,
        teamCheck = true,
        targetDummies = true,
        lastShot = 0,
        isShooting = false
    }

    local movementSettings = {
        bhopEnabled = false,
        speedBoost = false,
        speedMultiplier = 1.35,
        slideBoost = false,
        infiniteJump = false,
        lastJump = 0
    }

    local function resolveKey(key)
        if typeof(key) == "EnumItem" then return key end
        if type(key) == "string" then
            if key == "MouseButton2" or key == "RMB" or key == "RightClick" then
                return Enum.UserInputType.MouseButton2
            elseif key == "MouseButton1" or key == "LMB" or key == "LeftClick" then
                return Enum.UserInputType.MouseButton1
            elseif key == "MouseButton3" or key == "MMB" or key == "MiddleClick" then
                return Enum.UserInputType.MouseButton3
            end
            local ok, kc = pcall(function() return Enum.KeyCode[key] end)
            if ok and kc then return kc end
        end
        return Enum.UserInputType.MouseButton2
    end

    local function isKeyPressed(k)
        if k == Enum.UserInputType.MouseButton1 or k == Enum.UserInputType.MouseButton2 or k == Enum.UserInputType.MouseButton3 then
            return UserInputService:IsMouseButtonPressed(k)
        elseif typeof(k) == "EnumItem" and k.EnumType == Enum.KeyCode then
            return UserInputService:IsKeyDown(k)
        end
        return false
    end

    local espSettings = {
        enabled = true,
        teamCheck = true,
        showBoxes = true,
        boxOutline = true,
        showNames = true,
        showDistance = true,
        showHealth = true,
        showTracers = true,
        showHeadDot = true,
        includeDummies = false,
        maxDistance = 1500,

        enemyColor = Color3.fromRGB(255, 65, 65),
        teamColor = Color3.fromRGB(65, 180, 255),
        textColor = Color3.fromRGB(255, 255, 255),
        dummyColor = Color3.fromRGB(255, 170, 0),
        headDotColor = Color3.fromRGB(255, 30, 30),
        healthBarGreen = Color3.fromRGB(0, 255, 0),
        healthBarRed = Color3.fromRGB(255, 0, 0)
    }

    -- ------------------------------------------------------------
    -- Drawing API Helpers & Lifecycle
    -- ------------------------------------------------------------
    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local espCache = {}
    local fovCircle = nil

    local function safeDrawing(drawingType, props)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        if ok and obj then
            for k, v in pairs(props or {}) do
                obj[k] = v
            end
            return obj
        end
        return nil
    end

    local function removeEntry(model)
        local entry = espCache[model]
        if entry then
            for _, obj in pairs(entry.Drawings) do
                pcall(function()
                    obj.Visible = false
                    obj:Remove()
                end)
            end
            espCache[model] = nil
        end
    end

    local function addEntry(model, isDummy, isEnemy)
        if espCache[model] then
            local s = espSettings
            local mainColor = isDummy and s.dummyColor or (isEnemy and s.enemyColor or s.teamColor)
            local entry = espCache[model]
            if entry and entry.Drawings then
                if entry.Drawings.box then entry.Drawings.box.Color = mainColor end
                if entry.Drawings.tracer then entry.Drawings.tracer.Color = mainColor end
                if entry.Drawings.headDot then entry.Drawings.headDot.Color = isEnemy and s.headDotColor or mainColor end
            end
            return
        end
        
        local s = espSettings
        local mainColor = isDummy and s.dummyColor or (isEnemy and s.enemyColor or s.teamColor)
        
        local drawings = {
            boxOutline = safeDrawing("Square", { Thickness = 3, Color = Color3.fromRGB(0, 0, 0), Filled = false, Visible = false, ZIndex = 999998 }),
            box = safeDrawing("Square", { Thickness = 1, Color = mainColor, Filled = false, Visible = false, ZIndex = 999999 }),
            name = safeDrawing("Text", { Size = 13, Center = true, Outline = true, Color = s.textColor, Visible = false, ZIndex = 1000000 }),
            distance = safeDrawing("Text", { Size = 11, Center = true, Outline = true, Color = Color3.fromRGB(210, 210, 210), Visible = false, ZIndex = 1000000 }),
            tracer = safeDrawing("Line", { Thickness = 1, Color = mainColor, Visible = false, ZIndex = 999999 }),
            headDot = safeDrawing("Circle", { Radius = 3, Filled = true, Color = isEnemy and s.headDotColor or mainColor, Visible = false, ZIndex = 1000000 }),
            healthOutline = safeDrawing("Line", { Thickness = 3, Color = Color3.fromRGB(0, 0, 0), Visible = false, ZIndex = 999998 }),
            health = safeDrawing("Line", { Thickness = 1, Color = s.healthBarGreen, Visible = false, ZIndex = 999999 })
        }
        
        espCache[model] = {
            Model = model,
            IsDummy = isDummy,
            IsEnemy = isEnemy,
            Drawings = drawings
        }
    end

    -- Create FOV Circle
    fovCircle = safeDrawing("Circle", {
        Radius = aimbotSettings.fov,
        Thickness = aimbotSettings.fovThickness,
        Color = aimbotSettings.fovColor,
        Transparency = aimbotSettings.fovTransparency,
        Filled = false,
        Visible = aimbotSettings.enabled and aimbotSettings.drawFov,
        ZIndex = 999999
    })

    -- Dynamic Camera Getter (Survives round resets and client camera rebinding)
    local function getCamera()
        return Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera") or Camera
    end

    -- ------------------------------------------------------------
    -- Aimbot Target Acquisition (Scope-Adaptive FOV)
    -- ------------------------------------------------------------
    local function getBestAimbotTarget(cam, center, effectiveFov)
        if not aimbotSettings.enabled then return nil end
        
        local myTeam = LocalPlayer:GetAttribute("TeamID")
        local closestTarget = nil
        local shortestDist = effectiveFov or aimbotSettings.fov
        
        -- Real Players
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and plr.Character:IsDescendantOf(Workspace) then
                local team = plr:GetAttribute("TeamID")
                local isTeammate = (myTeam ~= nil and team ~= nil and myTeam == team)
                
                if aimbotSettings.targetTeammates or not isTeammate then
                    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local part = plr.Character:FindFirstChild(aimbotSettings.targetPart) or plr.Character:FindFirstChild("Head") or plr.Character:FindFirstChild("HitboxHead")
                        if part and part:IsDescendantOf(Workspace) then
                            local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                            if onScreen and screenPos.Z > 0 then
                                local diff = Vector2.new(screenPos.X, screenPos.Y) - center
                                if diff.Magnitude < shortestDist then
                                    local canSee = true
                                    if aimbotSettings.wallCheck then
                                        local rayParams = RaycastParams.new()
                                        rayParams.FilterType = Enum.RaycastFilterType.Exclude
                                        local filterList = { LocalPlayer.Character, plr.Character, cam }
                                        local vms = Workspace:FindFirstChild("ViewModels")
                                        if vms then table.insert(filterList, vms) end
                                        rayParams.FilterDescendantsInstances = filterList
                                        
                                        local rayOrigin = cam.CFrame.Position + (cam.CFrame.LookVector * 1.0)
                                        local hit = Workspace:Raycast(rayOrigin, part.Position - rayOrigin, rayParams)
                                        if hit and hit.Instance and hit.Instance.CanCollide and hit.Instance.Transparency < 0.8 then
                                            canSee = false
                                        end
                                    end
                                    
                                    if canSee then
                                        shortestDist = diff.Magnitude
                                        closestTarget = {
                                            model = plr.Character,
                                            part = part,
                                            diff = diff,
                                            worldPos = part.Position
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        -- Dummies in Shooting Range
        if aimbotSettings.includeDummies and not closestTarget then
            local sEntities = Workspace:FindFirstChild("ShootingRangeEntities")
            if sEntities then
                for _, child in ipairs(sEntities:GetChildren()) do
                    if child:IsA("Model") and child:IsDescendantOf(Workspace) and (child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Hitbox")) then
                        local hum = child:FindFirstChildOfClass("Humanoid") or child:FindFirstChild("EnemyHumanoid")
                        if not hum or hum.Health > 0 then
                            local part = child:FindFirstChild(aimbotSettings.targetPart) or child:FindFirstChild("Head") or child:FindFirstChild("HitboxHead") or child:FindFirstChild("HumanoidRootPart")
                            if part and part:IsDescendantOf(Workspace) then
                                local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                                if onScreen and screenPos.Z > 0 then
                                    local diff = Vector2.new(screenPos.X, screenPos.Y) - center
                                    if diff.Magnitude < shortestDist then
                                        local canSee = true
                                        if aimbotSettings.wallCheck then
                                            local rayParams = RaycastParams.new()
                                            rayParams.FilterType = Enum.RaycastFilterType.Exclude
                                            local filterList = { LocalPlayer.Character, child, cam }
                                            local vms = Workspace:FindFirstChild("ViewModels")
                                            if vms then table.insert(filterList, vms) end
                                            rayParams.FilterDescendantsInstances = filterList
                                            
                                            local rayOrigin = cam.CFrame.Position + (cam.CFrame.LookVector * 1.0)
                                            local hit = Workspace:Raycast(rayOrigin, part.Position - rayOrigin, rayParams)
                                            if hit and hit.Instance and hit.Instance.CanCollide and hit.Instance.Transparency < 0.8 then
                                                canSee = false
                                            end
                                        end
                                        
                                        if canSee then
                                            shortestDist = diff.Magnitude
                                            closestTarget = {
                                                model = child,
                                                part = part,
                                                diff = diff,
                                                worldPos = part.Position
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        return closestTarget
    end

    -- ------------------------------------------------------------
    -- Triggerbot Target Acquisition (Dual Precision Detection)
    -- ------------------------------------------------------------
    local function checkTriggerbotTarget(cam, center)
        if not cam then return false end
        
        local myTeam = LocalPlayer:GetAttribute("TeamID")
        local tolerance = triggerbotSettings.crosshairTolerance or 14
        
        -- Raycast Parameters excluding LocalPlayer, ViewModels, and Camera
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        local filter = { LocalPlayer.Character, cam }
        local vms = Workspace:FindFirstChild("ViewModels")
        if vms then table.insert(filter, vms) end
        rayParams.FilterDescendantsInstances = filter
        
        -- 1. Center Viewport Raycast
        local unitRay = cam:ViewportPointToRay(center.X, center.Y)
        local hit = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1500, rayParams)
        if hit and hit.Instance then
            local inst = hit.Instance
            local model = inst:FindFirstAncestorOfClass("Model")
            if model and model:IsDescendantOf(Workspace) then
                local hitPlr = Players:GetPlayerFromCharacter(model)
                if hitPlr and hitPlr ~= LocalPlayer then
                    local team = hitPlr:GetAttribute("TeamID")
                    local isEnemy = (myTeam == nil or team == nil or team ~= myTeam)
                    if isEnemy or not triggerbotSettings.teamCheck then
                        local hum = model:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            if triggerbotSettings.headOnly then
                                if inst.Name == "Head" or inst.Name == "HitboxHead" then
                                    return true
                                end
                            else
                                return true
                            end
                        end
                    end
                elseif triggerbotSettings.targetDummies and model.Parent and model.Parent.Name == "ShootingRangeEntities" then
                    local hum = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChild("EnemyHumanoid")
                    if not hum or hum.Health > 0 then
                        if triggerbotSettings.headOnly then
                            if inst.Name == "Head" or inst.Name == "HitboxHead" then
                                return true
                            end
                        else
                            return true
                        end
                    end
                end
            end
        end
        
        -- 2. Screen-Space Crosshair Proximity (Dual Check fallback)
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character and plr.Character:IsDescendantOf(Workspace) then
                local team = plr:GetAttribute("TeamID")
                local isEnemy = (myTeam == nil or team == nil or team ~= myTeam)
                if isEnemy or not triggerbotSettings.teamCheck then
                    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        local targetPartName = triggerbotSettings.headOnly and "Head" or aimbotSettings.targetPart
                        local part = plr.Character:FindFirstChild(targetPartName) or plr.Character:FindFirstChild("Head") or plr.Character:FindFirstChild("HitboxHead")
                        if part and part:IsDescendantOf(Workspace) then
                            local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                            if onScreen and screenPos.Z > 0 then
                                local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                                if dist <= tolerance then
                                    local canSee = true
                                    if aimbotSettings.wallCheck then
                                        local rayOrigin = cam.CFrame.Position + (cam.CFrame.LookVector * 1.0)
                                        local lineHit = Workspace:Raycast(rayOrigin, part.Position - rayOrigin, rayParams)
                                        if lineHit and lineHit.Instance and lineHit.Instance.CanCollide and lineHit.Instance.Transparency < 0.8 then
                                            canSee = false
                                        end
                                    end
                                    if canSee then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        -- Dummies Proximity Check
        if triggerbotSettings.targetDummies then
            local sEntities = Workspace:FindFirstChild("ShootingRangeEntities")
            if sEntities then
                for _, child in ipairs(sEntities:GetChildren()) do
                    if child:IsA("Model") and child:IsDescendantOf(Workspace) then
                        local hum = child:FindFirstChildOfClass("Humanoid") or child:FindFirstChild("EnemyHumanoid")
                        if not hum or hum.Health > 0 then
                            local targetPartName = triggerbotSettings.headOnly and "Head" or aimbotSettings.targetPart
                            local part = child:FindFirstChild(targetPartName) or child:FindFirstChild("Head") or child:FindFirstChild("HitboxHead") or child:FindFirstChild("HumanoidRootPart")
                            if part and part:IsDescendantOf(Workspace) then
                                local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                                if onScreen and screenPos.Z > 0 then
                                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                                    if dist <= tolerance then
                                        return true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        return false
    end

    -- ------------------------------------------------------------
    -- Main Update Loop
    -- ------------------------------------------------------------
    connect(RunService.RenderStepped, function()
        if not running then return end
        
        local cam = getCamera()
        if not cam then return end
        
        local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
        local myTeam = LocalPlayer:GetAttribute("TeamID")
        
        -- Scope-Adaptive FOV & Mouse Sensitivity Compensation
        local baseFov = 80
        local currentFov = math.clamp(cam.FieldOfView, 10, 120)
        local fovFactor = baseFov / currentFov
        local effectiveFov = aimbotSettings.fov * fovFactor
        
        -- Resolve active aiming state (direct polling prevents GPE swallow)
        local isAimKeyPressed = false
        if aimbotSettings.toggleMode then
            isAimKeyPressed = aimbotSettings.isAiming
        else
            local curKey = resolveKey(aimbotSettings.aimKey)
            isAimKeyPressed = isKeyPressed(curKey) or aimbotSettings.isAiming
        end
        
        -- Aimbot Execution & Dynamic Feedback (pcall protected)
        local activeTarget = nil
        pcall(function()
            if aimbotSettings.enabled and isAimKeyPressed then
                activeTarget = getBestAimbotTarget(cam, center, effectiveFov)
                if activeTarget then
                    if aimbotSettings.method == "Camera" then
                        cam.CFrame = CFrame.new(cam.CFrame.Position, activeTarget.worldPos)
                    else
                        if activeTarget.diff and type(mousemoverel) == "function" then
                            local dx = activeTarget.diff.X
                            local dy = activeTarget.diff.Y
                            if dx == dx and dy == dy and not (dx == 1/0 or dx == -1/0 or dy == 1/0 or dy == -1/0) then
                                local moveMultiplier = aimbotSettings.smoothness * fovFactor
                                local maxMove = 50 * fovFactor
                                local moveX = math.clamp(dx * moveMultiplier, -maxMove, maxMove)
                                local moveY = math.clamp(dy * moveMultiplier, -maxMove, maxMove)
                                if math.abs(moveX) > 0.05 or math.abs(moveY) > 0.05 then
                                    pcall(mousemoverel, moveX, moveY)
                                end
                            end
                        end
                    end
                end
            end
            
            -- Update FOV Circle (Instant visual feedback: Green when locked, Cyan when scanning)
            if fovCircle then
                fovCircle.Position = center
                fovCircle.Radius = effectiveFov
                fovCircle.Color = (activeTarget ~= nil) and aimbotSettings.fovLockedColor or aimbotSettings.fovColor
                fovCircle.Visible = aimbotSettings.enabled and aimbotSettings.drawFov
            end
        end)
        
        -- Triggerbot Execution (pcall protected)
        pcall(function()
            if triggerbotSettings.enabled and not triggerbotSettings.isShooting then
                local shouldCheck = false
                if triggerbotSettings.mode == "Always Active" then
                    shouldCheck = true
                elseif triggerbotSettings.mode == "While Aiming (RMB)" then
                    shouldCheck = isAimKeyPressed
                elseif triggerbotSettings.mode == "Hold Keybind" then
                    local tKey = resolveKey(triggerbotSettings.activationKey)
                    shouldCheck = isKeyPressed(tKey)
                elseif triggerbotSettings.mode == "Toggle Keybind" then
                    shouldCheck = triggerbotSettings.isActive
                end
                
                if shouldCheck then
                    local now = os.clock()
                    if now - triggerbotSettings.lastShot >= triggerbotSettings.cooldown then
                        local hasTarget = checkTriggerbotTarget(cam, center)
                        if hasTarget then
                            triggerbotSettings.lastShot = now
                            triggerbotSettings.isShooting = true
                            task.spawn(function()
                                if triggerbotSettings.delay > 0 then
                                    task.wait(triggerbotSettings.delay)
                                end
                                if type(mouse1click) == "function" then
                                    mouse1click()
                                elseif type(mouse1press) == "function" and type(mouse1release) == "function" then
                                    mouse1press()
                                    task.wait(0.02)
                                    mouse1release()
                                end
                                task.wait(0.04)
                                triggerbotSettings.isShooting = false
                            end)
                        end
                    end
                end
            end
        end)
        
        -- ESP Execution (pcall protected against sudden instance removal)
        pcall(function()
            if not espSettings.enabled then
                for _, entry in pairs(espCache) do
                    for _, obj in pairs(entry.Drawings) do
                        obj.Visible = false
                    end
                end
                return
            end
            
            local validModels = {}
            
            -- Process Players
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr.Character and plr.Character:IsDescendantOf(Workspace) then
                    local model = plr.Character
                    local hum = model:FindFirstChildOfClass("Humanoid")
                    
                    if hum and hum.Health > 0 then
                        local team = plr:GetAttribute("TeamID")
                        local isEnemy = (myTeam == nil or team == nil or team ~= myTeam)
                        
                        if isEnemy or not espSettings.teamCheck then
                            validModels[model] = true
                            if not espCache[model] then
                                addEntry(model, false, isEnemy)
                            end
                            
                            local entry = espCache[model]
                            local hrp = model:FindFirstChild("HumanoidRootPart")
                            local head = model:FindFirstChild("Head") or model:FindFirstChild("HitboxHead")
                            
                            if hrp and head and cam then
                                local distance = (cam.CFrame.Position - hrp.Position).Magnitude
                                if distance <= espSettings.maxDistance then
                                    local hrpScreen, hrpOn = cam:WorldToViewportPoint(hrp.Position)
                                    local headScreen, headOn = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.6, 0))
                                    local footScreen, footOn = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.8, 0))
                                    
                                    -- Robust onScreen: target in front and any key part (head, torso, feet) on screen
                                    local inFront = hrpScreen.Z > 0 or headScreen.Z > 0
                                    local isVisible = inFront and (hrpOn or headOn or footOn)
                                    
                                    if isVisible then
                                        local height = math.abs(headScreen.Y - footScreen.Y)
                                        if height < 8 then height = 8 end
                                        local width = height * 0.65
                                        local midX = headOn and headScreen.X or hrpScreen.X
                                        local boxTopLeft = Vector2.new(midX - width / 2, headScreen.Y)
                                        
                                        local color = isEnemy and espSettings.enemyColor or espSettings.teamColor
                                        
                                        -- Box
                                        if espSettings.showBoxes then
                                            entry.Drawings.box.Size = Vector2.new(width, height)
                                            entry.Drawings.box.Position = boxTopLeft
                                            entry.Drawings.box.Color = color
                                            entry.Drawings.box.Visible = true
                                            
                                            if espSettings.boxOutline then
                                                entry.Drawings.boxOutline.Size = Vector2.new(width, height)
                                                entry.Drawings.boxOutline.Position = boxTopLeft
                                                entry.Drawings.boxOutline.Visible = true
                                            else
                                                entry.Drawings.boxOutline.Visible = false
                                            end
                                        else
                                            entry.Drawings.box.Visible = false
                                            entry.Drawings.boxOutline.Visible = false
                                        end
                                        
                                        -- Name
                                        if espSettings.showNames then
                                            entry.Drawings.name.Text = (isEnemy and "[E] " or "[T] ") .. (plr.DisplayName or plr.Name)
                                            entry.Drawings.name.Position = Vector2.new(midX, headScreen.Y - 16)
                                            entry.Drawings.name.Color = color
                                            entry.Drawings.name.Visible = true
                                        else
                                            entry.Drawings.name.Visible = false
                                        end
                                        
                                        -- Distance
                                        if espSettings.showDistance then
                                            entry.Drawings.distance.Text = math.floor(distance) .. "m"
                                            entry.Drawings.distance.Position = Vector2.new(midX, footScreen.Y + 2)
                                            entry.Drawings.distance.Visible = true
                                        else
                                            entry.Drawings.distance.Visible = false
                                        end
                                        
                                        -- Tracers
                                        if espSettings.showTracers then
                                            entry.Drawings.tracer.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                                            entry.Drawings.tracer.To = Vector2.new(midX, footScreen.Y)
                                            entry.Drawings.tracer.Color = color
                                            entry.Drawings.tracer.Visible = true
                                        else
                                            entry.Drawings.tracer.Visible = false
                                        end
                                        
                                        -- Head Dot
                                        if espSettings.showHeadDot then
                                            local hDotPos, hOn = cam:WorldToViewportPoint(head.Position)
                                            if hOn and hDotPos.Z > 0 then
                                                entry.Drawings.headDot.Position = Vector2.new(hDotPos.X, hDotPos.Y)
                                                entry.Drawings.headDot.Radius = math.clamp(height / 15, 2, 8)
                                                entry.Drawings.headDot.Color = isEnemy and espSettings.headDotColor or color
                                                entry.Drawings.headDot.Visible = true
                                            else
                                                entry.Drawings.headDot.Visible = false
                                            end
                                        else
                                            entry.Drawings.headDot.Visible = false
                                        end
                                        
                                        -- Health Bar
                                        if espSettings.showHealth and hum.MaxHealth > 0 then
                                            local healthRatio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                                            local barX = boxTopLeft.X - 5
                                            local barHeight = height * healthRatio
                                            
                                            entry.Drawings.healthOutline.From = Vector2.new(barX, footScreen.Y)
                                            entry.Drawings.healthOutline.To = Vector2.new(barX, headScreen.Y)
                                            entry.Drawings.healthOutline.Visible = true
                                            
                                            entry.Drawings.health.From = Vector2.new(barX, footScreen.Y)
                                            entry.Drawings.health.To = Vector2.new(barX, footScreen.Y - barHeight)
                                            entry.Drawings.health.Color = espSettings.healthBarRed:Lerp(espSettings.healthBarGreen, healthRatio)
                                            entry.Drawings.health.Visible = true
                                        else
                                            entry.Drawings.healthOutline.Visible = false
                                            entry.Drawings.health.Visible = false
                                        end
                                    else
                                        for _, obj in pairs(entry.Drawings) do obj.Visible = false end
                                    end
                                else
                                    for _, obj in pairs(entry.Drawings) do obj.Visible = false end
                                end
                            end
                        end
                    end
                end
            end
            
            -- Process Dummies
            if espSettings.includeDummies then
                local sEntities = Workspace:FindFirstChild("ShootingRangeEntities")
                if sEntities then
                    for _, child in ipairs(sEntities:GetChildren()) do
                        if child:IsA("Model") and child:IsDescendantOf(Workspace) and (child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Hitbox")) then
                            validModels[child] = true
                            if not espCache[child] then addEntry(child, true, true) end
                            
                            local entry = espCache[child]
                            local hrp = child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("Hitbox")
                            local head = child:FindFirstChild("Head") or child:FindFirstChild("HitboxHead") or hrp
                            
                            if hrp and cam then
                                local hrpScreen, hrpOn = cam:WorldToViewportPoint(hrp.Position)
                                local headScreen, headOn = cam:WorldToViewportPoint(head.Position + Vector3.new(0, 0.6, 0))
                                local footScreen, footOn = cam:WorldToViewportPoint(hrp.Position - Vector3.new(0, 2.5, 0))
                                
                                local inFront = hrpScreen.Z > 0 or headScreen.Z > 0
                                local isVisible = inFront and (hrpOn or headOn or footOn)
                                
                                if isVisible then
                                    local height = math.abs(headScreen.Y - footScreen.Y)
                                    if height < 8 then height = 8 end
                                    local width = height * 0.65
                                    local midX = headOn and headScreen.X or hrpScreen.X
                                    local boxTopLeft = Vector2.new(midX - width / 2, headScreen.Y)
                                    
                                    entry.Drawings.box.Size = Vector2.new(width, height)
                                    entry.Drawings.box.Position = boxTopLeft
                                    entry.Drawings.box.Color = espSettings.dummyColor
                                    entry.Drawings.box.Visible = espSettings.showBoxes
                                    
                                    entry.Drawings.boxOutline.Size = Vector2.new(width, height)
                                    entry.Drawings.boxOutline.Position = boxTopLeft
                                    entry.Drawings.boxOutline.Visible = espSettings.showBoxes
                                    
                                    entry.Drawings.name.Text = "[DUMMY] " .. child.Name
                                    entry.Drawings.name.Position = Vector2.new(midX, headScreen.Y - 16)
                                    entry.Drawings.name.Color = espSettings.dummyColor
                                    entry.Drawings.name.Visible = espSettings.showNames
                                    
                                    entry.Drawings.tracer.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
                                    entry.Drawings.tracer.To = Vector2.new(midX, footScreen.Y)
                                    entry.Drawings.tracer.Color = espSettings.dummyColor
                                    entry.Drawings.tracer.Visible = espSettings.showTracers
                                else
                                    for _, obj in pairs(entry.Drawings) do obj.Visible = false end
                                end
                            end
                        end
                    end
                end
            end
            
            -- Cleanup stale entries (Drawing Object Pooling: hide drawings instead of thrashing obj:Remove)
            for model, entry in pairs(espCache) do
                if not validModels[model] then
                    for _, obj in pairs(entry.Drawings) do
                        if obj then obj.Visible = false end
                    end
                    if not model or not model.Parent or not model:IsDescendantOf(game) then
                        removeEntry(model)
                    end
                end
            end
        end)
    end)

    -- ------------------------------------------------------------
    -- Movement Physics & Velocity Loop
    -- ------------------------------------------------------------
    connect(RunService.Heartbeat, function()
        if not running then return end
        
        local char = LocalPlayer.Character
        if not char or not char:IsDescendantOf(Workspace) then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or hum.Health <= 0 or not hrp then return end
        
        -- Auto Bunny Hop
        pcall(function()
            if movementSettings.bhopEnabled and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                if hum.FloorMaterial ~= Enum.Material.Air then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end
        end)
        
        -- Speed Boost (Velocity injection immune to controller reset)
        pcall(function()
            if movementSettings.speedBoost and movementSettings.speedMultiplier > 1.0 then
                if hum.MoveDirection.Magnitude > 0.1 then
                    local targetSpeed = 21.6 * movementSettings.speedMultiplier
                    local moveDir = hum.MoveDirection.Unit
                    local currentY = hrp.AssemblyLinearVelocity.Y
                    hrp.AssemblyLinearVelocity = Vector3.new(
                        moveDir.X * targetSpeed,
                        currentY,
                        moveDir.Z * targetSpeed
                    )
                end
            end
        end)
        
        -- Slide Boost / Infinite Slide
        pcall(function()
            if movementSettings.slideBoost then
                local isCrouch = UserInputService:IsKeyDown(Enum.KeyCode.C) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                if isCrouch and hum.MoveDirection.Magnitude > 0.1 then
                    local boostSpeed = 21.6 * math.max(movementSettings.speedMultiplier, 1.45)
                    local forwardDir = hum.MoveDirection.Unit
                    hrp.AssemblyLinearVelocity = Vector3.new(
                        forwardDir.X * boostSpeed,
                        hrp.AssemblyLinearVelocity.Y,
                        forwardDir.Z * boostSpeed
                    )
                end
            end
        end)
        
        -- Infinite Jump
        pcall(function()
            if movementSettings.infiniteJump and UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                local now = os.clock()
                if now - movementSettings.lastJump > 0.28 then
                    if hum.FloorMaterial == Enum.Material.Air then
                        movementSettings.lastJump = now
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end
            end
        end)
    end)

    -- ------------------------------------------------------------
    -- Keybind Listeners
    -- ------------------------------------------------------------
    connect(UserInputService.InputBegan, function(input, gpe)
        local curKey = resolveKey(aimbotSettings.aimKey)
        local matches = false
        if curKey == Enum.UserInputType.MouseButton1 or curKey == Enum.UserInputType.MouseButton2 or curKey == Enum.UserInputType.MouseButton3 then
            matches = (input.UserInputType == curKey)
        elseif typeof(curKey) == "EnumItem" and curKey.EnumType == Enum.KeyCode then
            matches = (input.KeyCode == curKey)
        end
        
        if matches then
            if aimbotSettings.toggleMode then
                if not gpe then
                    aimbotSettings.isAiming = not aimbotSettings.isAiming
                end
            else
                aimbotSettings.isAiming = true
            end
        end
        
        -- Triggerbot Keybind
        if triggerbotSettings.mode == "Toggle Keybind" or triggerbotSettings.mode == "Hold Keybind" then
            local tKey = resolveKey(triggerbotSettings.activationKey)
            local tMatches = false
            if tKey == Enum.UserInputType.MouseButton1 or tKey == Enum.UserInputType.MouseButton2 or tKey == Enum.UserInputType.MouseButton3 then
                tMatches = (input.UserInputType == tKey)
            elseif typeof(tKey) == "EnumItem" and tKey.EnumType == Enum.KeyCode then
                tMatches = (input.KeyCode == tKey)
            end
            if tMatches then
                if triggerbotSettings.mode == "Toggle Keybind" then
                    if not gpe then
                        triggerbotSettings.isActive = not triggerbotSettings.isActive
                    end
                else
                    triggerbotSettings.isActive = true
                end
            end
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        local curKey = resolveKey(aimbotSettings.aimKey)
        local matches = false
        if curKey == Enum.UserInputType.MouseButton1 or curKey == Enum.UserInputType.MouseButton2 or curKey == Enum.UserInputType.MouseButton3 then
            matches = (input.UserInputType == curKey)
        elseif typeof(curKey) == "EnumItem" and curKey.EnumType == Enum.KeyCode then
            matches = (input.KeyCode == curKey)
        end
        
        if not aimbotSettings.toggleMode and matches then
            aimbotSettings.isAiming = false
        end
        
        -- Triggerbot Hold Keybind Release
        if triggerbotSettings.mode == "Hold Keybind" then
            local tKey = resolveKey(triggerbotSettings.activationKey)
            local tMatches = false
            if tKey == Enum.UserInputType.MouseButton1 or tKey == Enum.UserInputType.MouseButton2 or tKey == Enum.UserInputType.MouseButton3 then
                tMatches = (input.UserInputType == tKey)
            elseif typeof(tKey) == "EnumItem" and tKey.EnumType == Enum.KeyCode then
                tMatches = (input.KeyCode == tKey)
            end
            if tMatches then
                triggerbotSettings.isActive = false
            end
        end
    end)

    -- ------------------------------------------------------------
    -- RAVEN HUB UI Integration (Zero-Duplication Tab Engine)
    -- ------------------------------------------------------------
    local function clearTab(tab)
        if not tab then return end
        if type(tab.Clear) == "function" then
            pcall(function() tab:Clear() end)
        elseif tab.sections then
            for _, sec in ipairs(tab.sections) do
                if sec.accentBar and type(sec.accentBar.Remove) == "function" then pcall(function() sec.accentBar:Remove() end) end
                if sec.titleDrawing and type(sec.titleDrawing.Remove) == "function" then pcall(function() sec.titleDrawing:Remove() end) end
                if sec.card and type(sec.card.Remove) == "function" then pcall(function() sec.card:Remove() end) end
                if sec.items then
                    for _, item in ipairs(sec.items) do
                        for _, d in pairs(item) do
                            if typeof(d) == "userdata" or (type(d) == "table" and type(d.Remove) == "function") then
                                pcall(function() if d.Remove then d:Remove() elseif d.Destroy then d:Destroy() end end)
                            end
                        end
                    end
                end
            end
            tab.sections = {}
            tab._currentSection = nil
        end
    end

    if Window and type(Window.CreateTab) == "function" then
        -- Tab 1: Combat / Aimbot
        local AimTab = Window:CreateTab("Combat", "crosshair")
        clearTab(AimTab)
        AimTab:CreateSection("Aimbot Master")

        AimTab:CreateToggle({
            Name = "Enable Aimbot",
            CurrentValue = aimbotSettings.enabled,
            Flag = "RIVALS_Aim_Master",
            Callback = function(val)
                aimbotSettings.enabled = val
                if fovCircle then fovCircle.Visible = val and aimbotSettings.drawFov end
            end
        })

        AimTab:CreateDropdown({
            Name = "Target Bone",
            Options = {"Head", "UpperTorso"},
            CurrentOption = aimbotSettings.targetPart,
            Flag = "RIVALS_Aim_Bone",
            Callback = function(val)
                aimbotSettings.targetPart = val
            end
        })

        AimTab:CreateDropdown({
            Name = "Aiming Method",
            Options = {"Mouse Emulation (mousemoverel)", "Direct Camera Look"},
            CurrentOption = (aimbotSettings.method == "Camera") and "Direct Camera Look" or "Mouse Emulation (mousemoverel)",
            Flag = "RIVALS_Aim_Method",
            Callback = function(val)
                if val:find("Camera") then
                    aimbotSettings.method = "Camera"
                else
                    aimbotSettings.method = "Mouse"
                end
            end
        })

        AimTab:CreateToggle({
            Name = "Wall Check (Raycast)",
            CurrentValue = aimbotSettings.wallCheck,
            Flag = "RIVALS_Aim_WallCheck",
            Callback = function(val)
                aimbotSettings.wallCheck = val
            end
        })

        AimTab:CreateToggle({
            Name = "Target Teammates",
            CurrentValue = aimbotSettings.targetTeammates,
            Flag = "RIVALS_Aim_Teammates",
            Callback = function(val)
                aimbotSettings.targetTeammates = val
            end
        })

        AimTab:CreateToggle({
            Name = "Target Dummies (Range Mode)",
            CurrentValue = aimbotSettings.includeDummies,
            Flag = "RIVALS_Aim_Dummies",
            Callback = function(val)
                aimbotSettings.includeDummies = val
            end
        })

        AimTab:CreateSection("Activation & Keybind")

        local keyMap = {
            ["Right Mouse Button (RMB)"] = Enum.UserInputType.MouseButton2,
            ["Left Mouse Button (LMB)"] = Enum.UserInputType.MouseButton1,
            ["Middle Mouse (MMB)"] = Enum.UserInputType.MouseButton3,
            ["Left Alt"] = Enum.KeyCode.LeftAlt,
            ["Left Shift"] = Enum.KeyCode.LeftShift,
            ["Left Control"] = Enum.KeyCode.LeftControl,
            ["E Key"] = Enum.KeyCode.E,
            ["Q Key"] = Enum.KeyCode.Q,
            ["C Key"] = Enum.KeyCode.C,
            ["V Key"] = Enum.KeyCode.V,
            ["X Key"] = Enum.KeyCode.X,
            ["F Key"] = Enum.KeyCode.F,
            ["Z Key"] = Enum.KeyCode.Z,
            ["T Key"] = Enum.KeyCode.T
        }

        AimTab:CreateDropdown({
            Name = "Aim Activation Key",
            Options = {
                "Right Mouse Button (RMB)",
                "Left Mouse Button (LMB)",
                "Left Alt",
                "Left Shift",
                "Left Control",
                "E Key",
                "Q Key",
                "C Key",
                "V Key",
                "X Key",
                "F Key",
                "Middle Mouse (MMB)",
                "Custom Keybind"
            },
            CurrentOption = "Right Mouse Button (RMB)",
            Flag = "RIVALS_Aim_KeyPreset",
            Callback = function(val)
                if val == "Custom Keybind" then
                    if aimbotSettings.customKey then
                        aimbotSettings.aimKey = aimbotSettings.customKey
                    end
                elseif keyMap[val] then
                    aimbotSettings.aimKey = keyMap[val]
                end
            end
        })

        AimTab:CreateKeybind({
            Name = "Custom Keybind (Press to Bind)",
            CurrentKeybind = "MouseButton2",
            Flag = "RIVALS_Aim_CustomKey",
            Callback = function(keyName)
                local resolved = resolveKey(keyName)
                aimbotSettings.customKey = resolved
                aimbotSettings.aimKey = resolved
            end
        })

        AimTab:CreateToggle({
            Name = "Toggle Mode (Click to Lock/Unlock)",
            CurrentValue = aimbotSettings.toggleMode,
            Flag = "RIVALS_Aim_ToggleMode",
            Callback = function(val)
                aimbotSettings.toggleMode = val
                aimbotSettings.isAiming = false
            end
        })

        AimTab:CreateSection("Tuning & Smoothness")

        AimTab:CreateSlider({
            Name = "FOV Radius",
            Range = {30, 450},
            Increment = 5,
            CurrentValue = aimbotSettings.fov,
            Suffix = " px",
            Flag = "RIVALS_Aim_FOV",
            Callback = function(val)
                aimbotSettings.fov = val
            end
        })

        AimTab:CreateSlider({
            Name = "Smoothness (Tracking Speed)",
            Range = {0.05, 1.00},
            Increment = 0.01,
            CurrentValue = aimbotSettings.smoothness,
            Suffix = "x",
            Flag = "RIVALS_Aim_Smoothness",
            Callback = function(val)
                aimbotSettings.smoothness = val
            end
        })

        AimTab:CreateToggle({
            Name = "Show FOV Circle",
            CurrentValue = aimbotSettings.drawFov,
            Flag = "RIVALS_Aim_DrawFOV",
            Callback = function(val)
                aimbotSettings.drawFov = val
                if fovCircle then fovCircle.Visible = val and aimbotSettings.enabled end
            end
        })

        AimTab:CreateSection("Triggerbot (Auto Shoot)")

        AimTab:CreateToggle({
            Name = "Enable Triggerbot",
            CurrentValue = triggerbotSettings.enabled,
            Flag = "RIVALS_Trigger_Master",
            Callback = function(val)
                triggerbotSettings.enabled = val
            end
        })

        AimTab:CreateDropdown({
            Name = "Activation Mode",
            Options = {"While Aiming (RMB)", "Always Active", "Hold Keybind", "Toggle Keybind"},
            CurrentOption = triggerbotSettings.mode,
            Flag = "RIVALS_Trigger_Mode",
            Callback = function(val)
                triggerbotSettings.mode = val
            end
        })

        AimTab:CreateKeybind({
            Name = "Trigger Keybind",
            CurrentKeybind = "LeftAlt",
            Flag = "RIVALS_Trigger_Key",
            Callback = function(keyName)
                local resolved = resolveKey(keyName)
                triggerbotSettings.activationKey = resolved
            end
        })

        AimTab:CreateToggle({
            Name = "Headshot Only",
            CurrentValue = triggerbotSettings.headOnly,
            Flag = "RIVALS_Trigger_HeadOnly",
            Callback = function(val)
                triggerbotSettings.headOnly = val
            end
        })

        AimTab:CreateSlider({
            Name = "Reaction Delay",
            Range = {0, 150},
            Increment = 5,
            CurrentValue = math.floor(triggerbotSettings.delay * 1000),
            Suffix = " ms",
            Flag = "RIVALS_Trigger_Delay",
            Callback = function(val)
                triggerbotSettings.delay = val / 1000
            end
        })

        AimTab:CreateSlider({
            Name = "Crosshair Tolerance",
            Range = {4, 30},
            Increment = 1,
            CurrentValue = triggerbotSettings.crosshairTolerance,
            Suffix = " px",
            Flag = "RIVALS_Trigger_Tolerance",
            Callback = function(val)
                triggerbotSettings.crosshairTolerance = val
            end
        })

        AimTab:CreateToggle({
            Name = "Team Check",
            CurrentValue = triggerbotSettings.teamCheck,
            Flag = "RIVALS_Trigger_TeamCheck",
            Callback = function(val)
                triggerbotSettings.teamCheck = val
            end
        })

        AimTab:CreateToggle({
            Name = "Target Dummies",
            CurrentValue = triggerbotSettings.targetDummies,
            Flag = "RIVALS_Trigger_Dummies",
            Callback = function(val)
                triggerbotSettings.targetDummies = val
            end
        })

        -- Tab: Movement
        local MoveTab = Window:CreateTab("Movement", "zap")
        clearTab(MoveTab)
        MoveTab:CreateSection("Bunny Hop & Air Strafe")

        MoveTab:CreateToggle({
            Name = "Auto Bunny Hop (BHop)",
            CurrentValue = movementSettings.bhopEnabled,
            Flag = "RIVALS_Move_BHop",
            Callback = function(val)
                movementSettings.bhopEnabled = val
            end
        })

        MoveTab:CreateSection("Velocity & Speed Boost")

        MoveTab:CreateToggle({
            Name = "Enable Speed Boost",
            CurrentValue = movementSettings.speedBoost,
            Flag = "RIVALS_Move_SpeedBoost",
            Callback = function(val)
                movementSettings.speedBoost = val
            end
        })

        MoveTab:CreateSlider({
            Name = "Speed Multiplier",
            Range = {1.0, 2.5},
            Increment = 0.05,
            CurrentValue = movementSettings.speedMultiplier,
            Suffix = "x",
            Flag = "RIVALS_Move_Multiplier",
            Callback = function(val)
                movementSettings.speedMultiplier = val
            end
        })

        MoveTab:CreateSection("Slide & Jump Mechanics")

        MoveTab:CreateToggle({
            Name = "Slide Boost / Infinite Slide",
            CurrentValue = movementSettings.slideBoost,
            Flag = "RIVALS_Move_SlideBoost",
            Callback = function(val)
                movementSettings.slideBoost = val
            end
        })

        MoveTab:CreateToggle({
            Name = "Infinite Jump (Air Jump)",
            CurrentValue = movementSettings.infiniteJump,
            Flag = "RIVALS_Move_InfJump",
            Callback = function(val)
                movementSettings.infiniteJump = val
            end
        })

        -- Tab 2: Visuals / ESP
        local EspTab = Window:CreateTab("Visuals", "eye")
        clearTab(EspTab)
        EspTab:CreateSection("Master Controls")

        EspTab:CreateToggle({
            Name = "Enable ESP",
            CurrentValue = espSettings.enabled,
            Flag = "RIVALS_Esp_Master",
            Callback = function(val)
                espSettings.enabled = val
            end
        })

        EspTab:CreateToggle({
            Name = "Enemy Only (Team Check)",
            CurrentValue = espSettings.teamCheck,
            Flag = "RIVALS_Esp_TeamCheck",
            Callback = function(val)
                espSettings.teamCheck = val
            end
        })

        EspTab:CreateSlider({
            Name = "Max Render Distance",
            Range = {100, 3000},
            Increment = 50,
            CurrentValue = espSettings.maxDistance,
            Suffix = "m",
            Flag = "RIVALS_Esp_MaxDist",
            Callback = function(val)
                espSettings.maxDistance = val
            end
        })

        EspTab:CreateSection("Overlays & Visuals")

        EspTab:CreateToggle({
            Name = "2D Bounding Boxes",
            CurrentValue = espSettings.showBoxes,
            Flag = "RIVALS_Esp_Boxes",
            Callback = function(val)
                espSettings.showBoxes = val
            end
        })

        EspTab:CreateToggle({
            Name = "Health Bar",
            CurrentValue = espSettings.showHealth,
            Flag = "RIVALS_Esp_Health",
            Callback = function(val)
                espSettings.showHealth = val
            end
        })

        EspTab:CreateToggle({
            Name = "Head Dot (Precision Marker)",
            CurrentValue = espSettings.showHeadDot,
            Flag = "RIVALS_Esp_HeadDot",
            Callback = function(val)
                espSettings.showHeadDot = val
            end
        })

        EspTab:CreateToggle({
            Name = "Snaplines / Tracers",
            CurrentValue = espSettings.showTracers,
            Flag = "RIVALS_Esp_Tracers",
            Callback = function(val)
                espSettings.showTracers = val
            end
        })

        EspTab:CreateToggle({
            Name = "Player Names",
            CurrentValue = espSettings.showNames,
            Flag = "RIVALS_Esp_Names",
            Callback = function(val)
                espSettings.showNames = val
            end
        })

        EspTab:CreateToggle({
            Name = "Distance Labels",
            CurrentValue = espSettings.showDistance,
            Flag = "RIVALS_Esp_Distance",
            Callback = function(val)
                espSettings.showDistance = val
            end
        })

        EspTab:CreateToggle({
            Name = "Show Shooting Range Dummies",
            CurrentValue = espSettings.includeDummies,
            Flag = "RIVALS_Esp_Dummies",
            Callback = function(val)
                espSettings.includeDummies = val
            end
        })

        -- Tab 3: Automation & Rewards
        local AutoTab = Window:CreateTab("Automation", "gift")
        clearTab(AutoTab)
        AutoTab:CreateSection("Safe Reward Claims")

        AutoTab:CreateButton({
            Name = "Claim Daily Login Reward",
            Callback = function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local dataRemotes = remotes and remotes:FindFirstChild("Data")
                local claimLogin = dataRemotes and dataRemotes:FindFirstChild("ClaimLoginReward")
                if claimLogin then
                    pcall(function() claimLogin:FireServer() end)
                end
            end
        })

        AutoTab:CreateButton({
            Name = "Claim Group Reward",
            Callback = function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local dataRemotes = remotes and remotes:FindFirstChild("Data")
                local claimGroup = dataRemotes and dataRemotes:FindFirstChild("ClaimGroupReward")
                if claimGroup then
                    pcall(function() claimGroup:InvokeServer() end)
                end
            end
        })

        AutoTab:CreateButton({
            Name = "Claim Like & Favorite Rewards",
            Callback = function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local dataRemotes = remotes and remotes:FindFirstChild("Data")
                if dataRemotes then
                    local cLike = dataRemotes:FindFirstChild("ClaimLikeReward")
                    local cFav = dataRemotes:FindFirstChild("ClaimFavoriteReward")
                    if cLike then pcall(function() cLike:FireServer() end) end
                    if cFav then pcall(function() cFav:FireServer() end) end
                end
            end
        })

        AutoTab:CreateSection("Shooting Range Utilities")
        AutoTab:CreateButton({
            Name = "Clear All Trash in Range",
            Callback = function()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                local misc = remotes and remotes:FindFirstChild("Misc")
                local trash = misc and misc:FindFirstChild("ShootingRangeTrashItems")
                if trash then
                    pcall(function() trash:FireServer() end)
                end
            end
        })

        -- Tab 4: Info
        local InfoTab = Window:CreateTab("Info", "info")
        clearTab(InfoTab)
        InfoTab:CreateSection("Session Telemetry")
        InfoTab:CreateParagraph({
            Title = "Game / Session",
            Content = "RIVALS (Nosniy Games)\nPlaceId: 117398147513099\nEngine: Drawing Ghost Native v1.4.2"
        })
        InfoTab:CreateParagraph({
            Title = "Controls & Feedback",
            Content = "Right Mouse Button: Hold to Lock & Track Aim\nFOV Indicator: Cyan (Scanning) / Green (Target Locked)\nTab Order: Overview > Combat > Movement > Visuals > Automation > Settings > Info"
        })

        pcall(function()
            if type(Window.SortTabs) == "function" then
                Window:SortTabs({"Overview", "Combat", "Movement", "Visuals", "Automation", "Settings", "Info"})
            end
        end)
    end

    -- Cleanup object
    local instance = {
        Destroy = function()
            running = false
            for _, conn in ipairs(connections) do
                if conn and conn.Connected then
                    conn:Disconnect()
                end
            end
            connections = {}
            for model, _ in pairs(espCache) do
                removeEntry(model)
            end
            espCache = {}
            if fovCircle then
                pcall(function() fovCircle:Remove() end)
                fovCircle = nil
            end
            env.__RAVEN_RIVALS = nil
        end
    }

    env.__RAVEN_RIVALS = instance
    return instance
end
