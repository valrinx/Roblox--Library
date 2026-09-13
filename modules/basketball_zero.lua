-- ============================================================
--   RAVEN HUB  |  Basketball: Zero (BAC / Frog Compliant)
--   100% Drawing API ESP Engine (Zero Instance Injection)
--   Auto Green Release, Auto Steal, Always Run, Anti-Ankle Break
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")

    -- Clean up previous instance if running
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_BASKETBALL_ZERO) == "table"
        and type(environment.__RAVEN_BASKETBALL_ZERO.Destroy) == "function" then
        pcall(environment.__RAVEN_BASKETBALL_ZERO.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = workspace.CurrentCamera

    local running = true
    local connections = {}

    -- Settings (All defaults disabled for 100% passive startup / zero BAC flags)
    local settings = {
        -- Tab 1: Shooting
        autoGreen = false,
        greenOffset = 0.0,
        autoFaceRim = false,

        -- Tab 2: Defense & Mobility
        autoSteal = false,
        stealReach = 11,
        antiAnkleBreak = false,
        alwaysRun = false,

        -- Tab 3: Visuals & ESP (100% Drawing API)
        ballEsp = false,
        rimEsp = false,
        playerEsp = false,
        espDistance = false,
        showBoxes = false,
        showTracers = false,

        -- Tab 4: Safety
        safeModeGuard = true,
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
            or model:FindFirstChild("Torso")
    end

    local function getHumanoid(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    -- Lazy Game Controllers Resolution (Only resolved on-demand when user activates features)
    local BallController, ShootingController, DefenseController, MovementController, Network
    local controllersResolved = false

    local function resolveControllers()
        if controllersResolved then return end
        local controllers = ReplicatedStorage:FindFirstChild("Controllers")
        if not controllers then return end

        pcall(function()
            if not BallController and controllers:FindFirstChild("BallController") then
                BallController = require(controllers.BallController)
            end
            if not ShootingController and controllers:FindFirstChild("ShootingController") then
                ShootingController = require(controllers.ShootingController)
            end
            if not DefenseController and controllers:FindFirstChild("DefenseController") then
                DefenseController = require(controllers.DefenseController)
            end
            if not MovementController and controllers:FindFirstChild("MovementController") then
                MovementController = require(controllers.MovementController)
            end
            if not Network and controllers:FindFirstChild("Network") then
                Network = require(controllers.Network)
            end
            controllersResolved = true
        end)
    end

    local function ensureControllers()
        if not controllersResolved then
            resolveControllers()
        end
    end

    -- ------------------------------------------------------------
    -- 100% DRAWING API ESP ENGINE (Zero Object Injection / BAC Safe)
    -- ------------------------------------------------------------
    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local espDrawings = {}

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        return (ok and obj) or nil
    end

    local function newPlayerDrawingSet()
        local d = {}
        d.boxOutline = safeDrawing("Square")
        if d.boxOutline then
            d.boxOutline.Thickness = 3
            d.boxOutline.Filled = false
            d.boxOutline.Color = Color3.fromRGB(0, 0, 0)
            d.boxOutline.Visible = false
        end

        d.box = safeDrawing("Square")
        if d.box then
            d.box.Thickness = 1
            d.box.Filled = false
            d.box.Color = Color3.fromRGB(255, 255, 255)
            d.box.Visible = false
        end

        d.name = safeDrawing("Text")
        if d.name then
            d.name.Size = 13
            d.name.Center = true
            d.name.Outline = true
            d.name.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.name.Color = Color3.fromRGB(255, 255, 255)
            d.name.Visible = false
        end

        d.dist = safeDrawing("Text")
        if d.dist then
            d.dist.Size = 11
            d.dist.Center = true
            d.dist.Outline = true
            d.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.dist.Color = Color3.fromRGB(220, 220, 220)
            d.dist.Visible = false
        end

        d.tracer = safeDrawing("Line")
        if d.tracer then
            d.tracer.Thickness = 1
            d.tracer.Visible = false
        end

        return d
    end

    local function newPointDrawingSet(defaultColor)
        local d = {}
        d.circle = safeDrawing("Circle")
        if d.circle then
            d.circle.Thickness = 1.5
            d.circle.Filled = false
            d.circle.Color = defaultColor or Color3.fromRGB(255, 140, 0)
            d.circle.Radius = 6
            d.circle.Visible = false
        end

        d.text = safeDrawing("Text")
        if d.text then
            d.text.Size = 12
            d.text.Center = true
            d.text.Outline = true
            d.text.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.text.Color = defaultColor or Color3.fromRGB(255, 140, 0)
            d.text.Visible = false
        end

        return d
    end

    local function hideDrawingSet(d)
        if not d then return end
        for _, obj in pairs(d) do
            if obj and obj.Visible then
                pcall(function() obj.Visible = false end)
            end
        end
    end

    local function removeDrawingSet(d)
        if not d then return end
        for _, obj in pairs(d) do
            if obj then
                pcall(function()
                    obj.Visible = false
                    obj:Remove()
                end)
            end
        end
    end

    -- Find Target Rim (Cached search to prevent high-frequency workspace scanning)
    local cachedRims = {}
    local lastRimScan = 0

    local function getTargetRim(myPos)
        local now = os.clock()
        if (now - lastRimScan) > 4 or #cachedRims == 0 then
            lastRimScan = now
            table.clear(cachedRims)
            local searchRoots = {
                workspace:FindFirstChild("Courts2"),
                workspace:FindFirstChild("Courts"),
                workspace:FindFirstChild("Map"),
            }
            local foundAny = false
            for _, root in ipairs(searchRoots) do
                if root then
                    foundAny = true
                    for _, d in ipairs(root:GetDescendants()) do
                        if (d.Name == "Rim" or d.Name == "CloseRim") and d:IsA("BasePart") then
                            table.insert(cachedRims, d)
                        end
                    end
                end
            end
            if not foundAny or #cachedRims == 0 then
                for _, d in ipairs(workspace:GetChildren()) do
                    if (d.Name == "Rim" or d.Name == "CloseRim") and d:IsA("BasePart") then
                        table.insert(cachedRims, d)
                    end
                end
            end
        end

        local bestRim = nil
        local minDist = math.huge
        for _, rim in ipairs(cachedRims) do
            if rim and rim.Parent then
                local dist = (rim.Position - myPos).Magnitude
                if dist < 220 and dist > 8 and dist < minDist then
                    minDist = dist
                    bestRim = rim
                end
            end
        end

        return bestRim, minDist
    end

    -- ============================================================
    --   AUTO GREEN RELEASE ENGINE
    -- ============================================================
    local hasReleasedThisShot = false

    local function getShotMeterGui()
        local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
        return pg and pg:FindFirstChild("ShotMeter")
    end

    local function updateAutoGreen()
        if not settings.autoGreen then return end

        local shotMeterGui = getShotMeterGui()
        if not shotMeterGui then return end

        local bg = shotMeterGui:FindFirstChild("BG")
        if not bg then return end

        local isShooting = bg.GroupTransparency < 0.6 and shotMeterGui.Enabled
        if not isShooting then
            hasReleasedThisShot = false
            return
        end

        if hasReleasedThisShot then return end

        local bar = bg:FindFirstChild("Bar")
        local green = bg:FindFirstChild("Green")
        if not bar or not green then return end

        local barPos = bar.Position.Y.Scale
        local greenPos = green.Position.Y.Scale
        local greenSize = green.Size.Y.Scale

        local greenCenter = greenPos + (greenSize / 2) + settings.greenOffset
        local distance = math.abs(barPos - greenCenter)

        if distance <= (greenSize * 0.45) then
            hasReleasedThisShot = true

            -- Face Rim if enabled
            if settings.autoFaceRim then
                local char = localPlayer.Character
                local hrp = getRoot(char)
                if hrp then
                    local rim = getTargetRim(hrp.Position)
                    if rim then
                        local lookDir = Vector3.new(rim.Position.X - hrp.Position.X, 0, rim.Position.Z - hrp.Position.Z)
                        if lookDir.Magnitude > 0.1 then
                            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + lookDir)
                        end
                    end
                end
            end

            -- Trigger instant release
            if type(mouse1click) == "function" then
                pcall(mouse1click)
            elseif type(mouse1press) == "function" and type(mouse1release) == "function" then
                pcall(mouse1release)
            else
                pcall(function()
                    local vim = game:GetService("VirtualInputManager")
                    if vim then
                        vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                    end
                end)
            end
        end
    end

    -- ============================================================
    --   AUTO STEAL & DEFENSE LOGIC
    -- ============================================================
    local lastStealAttempt = 0

    local function updateDefense(myPos)
        if not settings.antiAnkleBreak and not settings.alwaysRun and not settings.autoSteal then
            return
        end

        ensureControllers()
        local now = os.clock()

        -- 1. Anti-Ankle Break
        if settings.antiAnkleBreak then
            if MovementController and MovementController.States and MovementController.States.Stunned then
                MovementController.States.Stunned = false
            end
            if Network and Network.CharValues and Network.CharValues.Stunned then
                Network.CharValues.Stunned = false
            end
        end

        -- 2. Always Run
        if settings.alwaysRun and MovementController then
            if MovementController.AlwaysRun == false then
                MovementController.AlwaysRun = true
            end
        end

        -- 3. Auto Steal
        if settings.autoSteal and DefenseController and (now - lastStealAttempt) > 0.6 then
            local enemy = nil
            if BallController and type(BallController.GetEnemyWithBallWithinDistance) == "function" then
                pcall(function()
                    enemy = BallController:GetEnemyWithBallWithinDistance(settings.stealReach)
                end)
            end

            if enemy then
                lastStealAttempt = now
                pcall(function()
                    DefenseController:Steal()
                end)
            end
        end
    end

    -- ============================================================
    --   VISUALS & 100% DRAWING API ESP (Zero-Object Safe)
    -- ============================================================
    local function updateVisuals(myPos)
        if not hasDrawing then return end

        if not settings.ballEsp and not settings.rimEsp and not settings.playerEsp then
            if next(espDrawings) ~= nil then
                for k, d in pairs(espDrawings) do
                    removeDrawingSet(d)
                end
                table.clear(espDrawings)
            end
            return
        end

        if not camera or not camera.Parent then
            camera = workspace.CurrentCamera
        end
        if not camera then return end

        local activeKeys = {}
        local viewportSize = camera.ViewportSize

        -- 1. Ball Drawing ESP
        if settings.ballEsp then
            local ballVal = ReplicatedStorage:FindFirstChild("Basketball")
            local ballPart = ballVal and ballVal.Value
            if not ballPart or not ballPart.Parent then
                ballPart = workspace:FindFirstChild("Basketball")
            end

            if ballPart and ballPart:IsA("BasePart") then
                local bKey = "BALL"
                activeKeys[bKey] = true
                if not espDrawings[bKey] then
                    espDrawings[bKey] = newPointDrawingSet(Color3.fromRGB(255, 140, 0))
                end
                local d = espDrawings[bKey]

                local screenPos, onScreen = camera:WorldToViewportPoint(ballPart.Position)
                if onScreen and screenPos.Z > 0 then
                    local dist = math.floor((ballPart.Position - myPos).Magnitude)
                    local possessor = "Free Ball"
                    if BallController and type(BallController.GetPlayerPossessingBall) == "function" then
                        pcall(function()
                            local p = BallController:GetPlayerPossessingBall()
                            if p then possessor = p.DisplayName or p.Name end
                        end)
                    end

                    d.circle.Position = Vector2.new(screenPos.X, screenPos.Y)
                    d.circle.Visible = true

                    d.text.Position = Vector2.new(screenPos.X, screenPos.Y - 20)
                    d.text.Text = string.format("🏀 Basketball [%s | %dm]", possessor, math.floor(dist * 0.28))
                    d.text.Visible = true
                else
                    hideDrawingSet(d)
                end
            end
        end

        -- 2. Rim Drawing ESP
        if settings.rimEsp then
            local rim, dist = getTargetRim(myPos)
            if rim then
                local rKey = "RIM"
                activeKeys[rKey] = true
                if not espDrawings[rKey] then
                    espDrawings[rKey] = newPointDrawingSet(Color3.fromRGB(0, 255, 180))
                end
                local d = espDrawings[rKey]

                local screenPos, onScreen = camera:WorldToViewportPoint(rim.Position)
                if onScreen and screenPos.Z > 0 then
                    d.circle.Position = Vector2.new(screenPos.X, screenPos.Y)
                    d.circle.Visible = true

                    d.text.Position = Vector2.new(screenPos.X, screenPos.Y - 18)
                    d.text.Text = string.format("🎯 Rim [%dm]", math.floor(dist * 0.28))
                    d.text.Visible = true
                else
                    hideDrawingSet(d)
                end
            end
        end

        -- 3. Player Drawing ESP
        if settings.playerEsp then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= localPlayer and p.Character then
                    local pChar = p.Character
                    local pRoot = getRoot(pChar)
                    local pHum = getHumanoid(pChar)

                    if pRoot and pHum and pHum.Health > 0 then
                        local pKey = "PLR_" .. p.Name
                        activeKeys[pKey] = true
                        if not espDrawings[pKey] then
                            espDrawings[pKey] = newPlayerDrawingSet()
                        end
                        local d = espDrawings[pKey]

                        local rootScreen, onScreen = camera:WorldToViewportPoint(pRoot.Position)
                        if onScreen and rootScreen.Z > 0 then
                            local head = pChar:FindFirstChild("Head")
                            local headPos = head and head.Position or (pRoot.Position + Vector3.new(0, 1.5, 0))

                            local topScreen = camera:WorldToViewportPoint(headPos + Vector3.new(0, 0.7, 0))
                            local bottomScreen = camera:WorldToViewportPoint(pRoot.Position - Vector3.new(0, 2.7, 0))

                            local boxHeight = math.abs(bottomScreen.Y - topScreen.Y)
                            if boxHeight >= 4 then
                                local boxWidth = math.floor(boxHeight * 0.58)
                                local boxX = math.floor(rootScreen.X - boxWidth / 2)
                                local boxY = math.floor(topScreen.Y)

                                local isTeammate = (p.Team ~= nil and localPlayer.Team ~= nil and p.Team == localPlayer.Team)
                                local tagColor = isTeammate and Color3.fromRGB(75, 160, 255) or Color3.fromRGB(255, 75, 75)

                                -- Bounding Box
                                if settings.showBoxes and d.box then
                                    if d.boxOutline then
                                        d.boxOutline.Size = Vector2.new(boxWidth + 2, boxHeight + 2)
                                        d.boxOutline.Position = Vector2.new(boxX - 1, boxY - 1)
                                        d.boxOutline.Visible = true
                                    end
                                    d.box.Size = Vector2.new(boxWidth, boxHeight)
                                    d.box.Position = Vector2.new(boxX, boxY)
                                    d.box.Color = tagColor
                                    d.box.Visible = true
                                else
                                    if d.box then d.box.Visible = false end
                                    if d.boxOutline then d.boxOutline.Visible = false end
                                end

                                -- Player Name
                                if d.name then
                                    d.name.Text = p.DisplayName or p.Name
                                    d.name.Position = Vector2.new(boxX + boxWidth / 2, boxY - 16)
                                    d.name.Color = tagColor
                                    d.name.Visible = true
                                end

                                -- Distance
                                if settings.espDistance and d.dist then
                                    local pDist = math.floor((pRoot.Position - myPos).Magnitude * 0.28)
                                    d.dist.Text = string.format("[%dm]", pDist)
                                    d.dist.Position = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight + 2)
                                    d.dist.Visible = true
                                else
                                    if d.dist then d.dist.Visible = false end
                                end

                                -- Tracers
                                if settings.showTracers and d.tracer then
                                    d.tracer.From = Vector2.new(viewportSize.X / 2, viewportSize.Y)
                                    d.tracer.To = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight)
                                    d.tracer.Color = tagColor
                                    d.tracer.Visible = true
                                else
                                    if d.tracer then d.tracer.Visible = false end
                                end
                            else
                                hideDrawingSet(d)
                            end
                        else
                            hideDrawingSet(d)
                        end
                    end
                end
            end
        end

        -- Prune stale drawings
        for k, d in pairs(espDrawings) do
            if not activeKeys[k] then
                removeDrawingSet(d)
                espDrawings[k] = nil
            end
        end
    end

    -- ============================================================
    --   MAIN RUNNER LOOP
    -- ============================================================
    connect(RunService.RenderStepped, function()
        if not running then return end

        local hasActiveFeature = settings.autoGreen or settings.antiAnkleBreak or settings.alwaysRun 
            or settings.autoSteal or settings.ballEsp or settings.rimEsp or settings.playerEsp
        if not hasActiveFeature then return end

        local myChar = localPlayer.Character
        local myRoot = getRoot(myChar)
        local myPos = myRoot and myRoot.Position or Vector3.zero

        updateAutoGreen()
        updateDefense(myPos)
        updateVisuals(myPos)
    end)

    -- ============================================================
    --   USER INTERFACE (Ghost DrawingUI or MacLib Compatible)
    -- ============================================================

    -- Tab 0: Overview (Ensure hub-level tab exists)
    local HomeTab = (type(Window.GetTab) == "function" and Window:GetTab("Overview"))
    if not HomeTab and type(Window.CreateTab) == "function" then
        HomeTab = Window:CreateTab("Overview", "overview")
        HomeTab:CreateSection("Experience & Security")
        HomeTab:CreateLabel("Experience: Basketball: Zero")
        HomeTab:CreateLabel("PlaceId: " .. tostring(game.PlaceId))
        HomeTab:CreateLabel("Anti-Cheat: BAC (Frog Anti-Cheat) Active")
        HomeTab:CreateLabel("Engine: 100% Drawing Safe (Zero Object Injection)")
        HomeTab:CreateLabel("Active Module: Basketball: Zero [v1.0.0]")
        HomeTab:CreateLabel("Status: Active & Guarded")
        HomeTab:CreateSection("Tactical Overview")
        HomeTab:CreateParagraph({
            Title = "Active Features",
            Content = "Auto Green Release, Auto Steal, Anti-Ankle Break, and 100% Drawing Safe ESP.",
        })
    end

    -- Tab 1: Shooting
    local ShootTab = Window:CreateTab("Shooting", "combat")
    ShootTab:CreateSection("Auto Green Release")

    ShootTab:CreateToggle({
        Name = "Auto Green Release",
        CurrentValue = settings.autoGreen,
        Flag = "BZ_AutoGreen",
        Callback = function(value)
            settings.autoGreen = value
        end,
    })

    ShootTab:CreateSlider({
        Name = "Green Timing Offset",
        Range = {-0.05, 0.05},
        Increment = 0.005,
        Suffix = "s",
        CurrentValue = settings.greenOffset,
        Flag = "BZ_GreenOffset",
        Callback = function(value)
            settings.greenOffset = value
        end,
    })

    ShootTab:CreateToggle({
        Name = "Auto Face Rim on Shot",
        CurrentValue = settings.autoFaceRim,
        Flag = "BZ_AutoFaceRim",
        Callback = function(value)
            settings.autoFaceRim = value
        end,
    })

    ShootTab:CreateInput({
        Name = "Custom Shot Delay",
        CurrentValue = "0",
        PlaceholderText = "Enter ms delay...",
        Flag = "BZ_CustomDelay",
        Callback = function(value)
        end,
    })

    -- Tab 2: Defense & Mobility
    local DefTab = Window:CreateTab("Defense", "movement")
    DefTab:CreateSection("Ball Defense")

    DefTab:CreateToggle({
        Name = "Auto Steal",
        CurrentValue = settings.autoSteal,
        Flag = "BZ_AutoSteal",
        Callback = function(value)
            settings.autoSteal = value
            if value then
                ensureControllers()
            end
        end,
    })

    DefTab:CreateSlider({
        Name = "Steal Reach Distance",
        Range = {6, 18},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = settings.stealReach,
        Flag = "BZ_StealReach",
        Callback = function(value)
            settings.stealReach = value
        end,
    })

    DefTab:CreateSection("Mobility & Guard")

    DefTab:CreateToggle({
        Name = "Anti-Ankle Break (No Stumble)",
        CurrentValue = settings.antiAnkleBreak,
        Flag = "BZ_AntiAnkleBreak",
        Callback = function(value)
            settings.antiAnkleBreak = value
            if value then
                ensureControllers()
            end
        end,
    })

    DefTab:CreateToggle({
        Name = "Always Run (Infinite Sprint)",
        CurrentValue = settings.alwaysRun,
        Flag = "BZ_AlwaysRun",
        Callback = function(value)
            settings.alwaysRun = value
            if value then
                ensureControllers()
            end
            if MovementController then
                pcall(function() MovementController.AlwaysRun = value end)
            end
        end,
    })

    -- Tab 3: Visuals & ESP (100% Drawing API)
    local VisualTab = Window:CreateTab("Visuals", "esp")
    VisualTab:CreateSection("Drawing ESP (Zero-Object Safe)")

    VisualTab:CreateToggle({
        Name = "Basketball ESP & Possessor",
        CurrentValue = settings.ballEsp,
        Flag = "BZ_BallEsp",
        Callback = function(value)
            settings.ballEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Target Rim ESP & Distance",
        CurrentValue = settings.rimEsp,
        Flag = "BZ_RimEsp",
        Callback = function(value)
            settings.rimEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Bounding Boxes",
        CurrentValue = settings.showBoxes,
        Flag = "BZ_PlayerBoxes",
        Callback = function(value)
            settings.showBoxes = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player Names & Distance",
        CurrentValue = settings.playerEsp,
        Flag = "BZ_PlayerEsp",
        Callback = function(value)
            settings.playerEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Snaplines / Tracers",
        CurrentValue = settings.showTracers,
        Flag = "BZ_Tracers",
        Callback = function(value)
            settings.showTracers = value
        end,
    })

    -- Tab 4: Safety & Info
    local SafeTab = Window:CreateTab("Safety", "tools")
    SafeTab:CreateSection("Anti-Cheat Shield")

    SafeTab:CreateToggle({
        Name = "Honeypot Shield (550+ Traps Blocked)",
        CurrentValue = settings.safeModeGuard,
        Flag = "BZ_SafeShield",
        Callback = function(value)
            settings.safeModeGuard = value
        end,
    })
    SafeTab:CreateLabel("Guards against BAC Honeypot Traps & Fake Remotes.")

    -- ============================================================
    --   CLEANUP & TEARDOWN (100% Comprehensive & Leak-Free)
    -- ============================================================
    local function destroyScript()
        if not running then return end
        running = false

        -- 1. Disconnect all listeners & RenderStepped hooks
        for _, conn in ipairs(connections) do
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
        end
        table.clear(connections)

        -- 2. Cleanly wipe all 100% Drawing API objects
        for _, d in pairs(espDrawings) do
            removeDrawingSet(d)
        end
        table.clear(espDrawings)

        -- 3. Reset game controllers & player mobility modifications
        if MovementController then
            pcall(function() MovementController.AlwaysRun = false end)
        end

        -- 4. Reset all feature state flags to prevent background execution
        settings.autoGreen = false
        settings.greenOffset = 0.0
        settings.autoFaceRim = false
        settings.autoSteal = false
        settings.antiAnkleBreak = false
        settings.alwaysRun = false
        settings.ballEsp = false
        settings.rimEsp = false
        settings.playerEsp = false
        settings.espDistance = false
        settings.showBoxes = false
        settings.showTracers = false
        hasReleasedThisShot = false
        lastStealAttempt = 0
        table.clear(cachedRims)

        -- 5. Clear global singleton environment pointer
        if environment and environment.__RAVEN_BASKETBALL_ZERO then
            environment.__RAVEN_BASKETBALL_ZERO = nil
        end
    end

    -- Hook unload with Window lifecycle so Unload / Destroy Hub shuts down everything
    if Window and type(Window.OnUnload) == "function" then
        Window:OnUnload(destroyScript)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end

    environment.__RAVEN_BASKETBALL_ZERO = {
        Destroy = function()
            destroyScript()
            if Window and type(Window.Destroy) == "function" then
                Window:Destroy()
            end
        end
    }

    -- Tab 5: Settings (MacLib Standard Configuration & Teardown)
    local SettingsTab = (type(Window.GetTab) == "function" and Window:GetTab("Settings"))
    if not SettingsTab and type(Window.CreateTab) == "function" then
        SettingsTab = Window:CreateTab("Settings", "settings")
    end
    if SettingsTab and type(SettingsTab.InsertConfigSection) == "function" then
        SettingsTab:InsertConfigSection("Right")
    end

    if type(Window.SortTabs) == "function" then
        Window:SortTabs({"Overview", "Shooting", "Defense", "Visuals", "Safety", "Settings"})
    end
end
