-- ============================================================
--   RAVEN HUB  |  Anime Battlegrounds
--   UniverseId: 10399136326  |  PlaceId: 105692919293481
--   High-Performance Combat, 100% Drawing API ESP & Mobility Engine
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local VirtualInputManager = game:GetService("VirtualInputManager")

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    -- Clean up previous instance
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_ANIME_BATTLEGROUNDS) == "table"
        and type(environment.__RAVEN_ANIME_BATTLEGROUNDS.Destroy) == "function" then
        pcall(environment.__RAVEN_ANIME_BATTLEGROUNDS.Destroy)
    end

    local running = true
    local connections = {}
    local espObjects = {}

    -- Settings
    local settings = {
        -- Combat
        aimlockEnabled = false,
        aimlockKey = Enum.KeyCode.C,
        aimlockPart = "HumanoidRootPart",
        aimlockSmoothness = 0.25,
        aimlockMaxDist = 350,
        reachEnabled = true,
        reachDistance = 12,
        allAroundHit = true,
        wallCheckBypass = false,
        autoM1 = false,
        autoM1Range = 12,
        autoM1Interval = 0.25,

        -- Visuals
        espEnabled = false,
        boxEsp = true,
        nameEsp = true,
        healthEsp = true,
        movesetEsp = true,
        distanceEsp = true,
        nativeHitboxDebug = false,

        -- Mobility
        speedEnabled = false,
        speedValue = 35,
        infiniteDash = false,
        dashDistance = 11,
        infiniteJump = false,
        antiRagdoll = false,

        -- Teleport
        backstabKey = Enum.KeyCode.V,
        backstabDistance = 2.5,
        backstabMaxRange = 250,
        backstabAutoFace = true,
        backstabAutoAttack = true,
        backstabAlignCam = true,
    }

    local isAiming = false
    local lastM1Time = 0

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 4})
            end)
        end
    end

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(connections, conn)
        return conn
    end

    local function getLocalRoot()
        local char = localPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getLocalHumanoid()
        local char = localPlayer.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function isTargetAlive(player)
        if not player or not player.Character then return false end
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        return hum and hum.Health > 0 and root ~= nil
    end

    -- Closest Enemy Finder
    local function getClosestEnemy(maxDist, requireOnScreen)
        local closest = nil
        local shortestDist = maxDist or settings.aimlockMaxDist
        local myRoot = getLocalRoot()
        if not myRoot then return nil end

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer and isTargetAlive(p) then
                local targetRoot = p.Character:FindFirstChild(settings.aimlockPart) or p.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot then
                    local dist = (myRoot.Position - targetRoot.Position).Magnitude
                    if dist <= shortestDist then
                        if requireOnScreen then
                            local _, onScreen = camera:WorldToViewportPoint(targetRoot.Position)
                            if onScreen then
                                shortestDist = dist
                                closest = p
                            end
                        else
                            shortestDist = dist
                            closest = p
                        end
                    end
                end
            end
        end
        return closest
    end

    -- [[ DRAWING ESP SYSTEM ]]
    local function createDrawingESP(player)
        if espObjects[player] then return end

        local drawings = {
            BoxOutline = Drawing.new("Square"),
            Box = Drawing.new("Square"),
            Name = Drawing.new("Text"),
            Info = Drawing.new("Text"),
        }

        drawings.BoxOutline.Thickness = 3
        drawings.BoxOutline.Filled = false
        drawings.BoxOutline.Color = Color3.fromRGB(0, 0, 0)
        drawings.BoxOutline.Visible = false

        drawings.Box.Thickness = 1
        drawings.Box.Filled = false
        drawings.Box.Color = Color3.fromRGB(255, 75, 75)
        drawings.Box.Visible = false

        drawings.Name.Size = 13
        drawings.Name.Center = true
        drawings.Name.Outline = true
        drawings.Name.Color = Color3.fromRGB(255, 255, 255)
        drawings.Name.Visible = false

        drawings.Info.Size = 11
        drawings.Info.Center = true
        drawings.Info.Outline = true
        drawings.Info.Color = Color3.fromRGB(220, 220, 220)
        drawings.Info.Visible = false

        espObjects[player] = drawings
    end

    local function removeDrawingESP(player)
        if espObjects[player] then
            for _, d in pairs(espObjects[player]) do
                pcall(function() d:Remove() end)
            end
            espObjects[player] = nil
        end
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then
            createDrawingESP(p)
        end
    end

    connect(Players.PlayerAdded, function(p)
        if p ~= localPlayer then
            createDrawingESP(p)
        end
    end)

    connect(Players.PlayerRemoving, function(p)
        removeDrawingESP(p)
    end)

    -- [[ COMBAT REACH & HITBOX QUERY HOOK ]]
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local hitUtil = nil
    local origQueryFront = nil
    local origInReach = nil
    local origOccluded = nil
    local combatConfig = nil

    pcall(function()
        hitUtil = require(ReplicatedStorage.Shared.Util.HitboxUtil)
        combatConfig = require(ReplicatedStorage.Shared.Config)
        origQueryFront = hitUtil.QueryFront
        origInReach = hitUtil.InReach
        origOccluded = hitUtil.Occluded
    end)

    local function setupHitboxHooks()
        if not hitUtil or not origQueryFront or not origInReach then return end

        hitUtil.InReach = function(cframe, targetPos, reach, coneDot, verticalTol)
            if settings.reachEnabled then
                local effectiveReach = math.max(reach, settings.reachDistance + 3)
                local effectiveCone = settings.allAroundHit and -1 or coneDot
                local effectiveVert = verticalTol and math.max(verticalTol, 20) or 20
                return origInReach(cframe, targetPos, effectiveReach, effectiveCone, effectiveVert)
            end
            return origInReach(cframe, targetPos, reach, coneDot, verticalTol)
        end

        hitUtil.QueryFront = function(cframe, reach, size, exclude, canHitImmune, verticalOffset)
            if settings.reachEnabled then
                local HitboxSink = (combatConfig and combatConfig.Combat and combatConfig.Combat.HitboxSink) or 2
                local effectiveReach = math.max(reach, settings.reachDistance)
                local effectiveSize = Vector3.new(
                    math.max(size.X, effectiveReach * 2),
                    math.max(size.Y, effectiveReach * 2),
                    effectiveReach * 2
                )
                local queryCF = cframe
                if settings.allAroundHit then
                    queryCF = cframe * CFrame.new(0, 0, (effectiveReach - HitboxSink) / 2)
                end
                return origQueryFront(queryCF, effectiveReach, effectiveSize, exclude, canHitImmune, verticalOffset)
            end
            return origQueryFront(cframe, reach, size, exclude, canHitImmune, verticalOffset)
        end

        if origOccluded then
            hitUtil.Occluded = function(origin, targetPos, exclude)
                if settings.reachEnabled and settings.wallCheckBypass then
                    return false
                end
                return origOccluded(origin, targetPos, exclude)
            end
        end
    end

    local function restoreHitboxHooks()
        if hitUtil then
            if origQueryFront then hitUtil.QueryFront = origQueryFront end
            if origInReach then hitUtil.InReach = origInReach end
            if origOccluded then hitUtil.Occluded = origOccluded end
        end
    end

    local origDashCharges = (combatConfig and combatConfig.Dash and combatConfig.Dash.Charges) or 1
    local origDashCooldown = (combatConfig and combatConfig.Dash and combatConfig.Dash.Cooldown) or 2
    local origDashDistance = (combatConfig and combatConfig.Dash and combatConfig.Dash.Distance) or 11

    local function applyDashSettings()
        if not combatConfig or not combatConfig.Dash then return end
        if settings.infiniteDash then
            combatConfig.Dash.Charges = 99
            combatConfig.Dash.Cooldown = 0.05
            combatConfig.Dash.Distance = settings.dashDistance
        else
            combatConfig.Dash.Charges = origDashCharges
            combatConfig.Dash.Cooldown = origDashCooldown
            combatConfig.Dash.Distance = origDashDistance
        end
    end

    local function restoreDashSettings()
        if combatConfig and combatConfig.Dash then
            combatConfig.Dash.Charges = origDashCharges
            combatConfig.Dash.Cooldown = origDashCooldown
            combatConfig.Dash.Distance = origDashDistance
        end
    end

    setupHitboxHooks()

    -- [[ TACTICAL BACKSTAB ]]
    local function executeBackstab()
        local target = getClosestEnemy(settings.backstabMaxRange, false)
        local myRoot = getLocalRoot()
        if target and target.Character and myRoot then
            local enemyRoot = target.Character:FindFirstChild("HumanoidRootPart")
            if enemyRoot then
                local enemyLook = enemyRoot.CFrame.LookVector
                local flatEnemyLook = Vector3.new(enemyLook.X, 0, enemyLook.Z)
                if flatEnemyLook.Magnitude > 0.001 then
                    flatEnemyLook = flatEnemyLook.Unit
                else
                    flatEnemyLook = Vector3.new(0, 0, -1)
                end

                -- Position behind enemy
                local behindPos = enemyRoot.Position - (flatEnemyLook * settings.backstabDistance)
                
                -- Face directly towards the enemy's back
                if settings.backstabAutoFace then
                    myRoot.CFrame = CFrame.lookAt(behindPos, enemyRoot.Position)
                else
                    myRoot.CFrame = CFrame.new(behindPos) * (enemyRoot.CFrame - enemyRoot.Position)
                end
                myRoot.AssemblyLinearVelocity = Vector3.zero

                -- Align camera directly at target for seamless combat control
                if settings.backstabAlignCam and camera then
                    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, enemyRoot.Position)
                end

                -- Auto M1 immediately after teleporting behind
                if settings.backstabAutoAttack then
                    task.spawn(function()
                        task.wait(0.04)
                        pcall(function()
                            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                            task.wait(0.02)
                            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                        end)
                    end)
                end

                notify("Backstab TP", "Locked behind " .. target.DisplayName .. " (" .. tostring(settings.backstabDistance) .. " studs) 🗡️⚡")
                return true
            end
        end
        notify("Backstab TP", "No target found within " .. tostring(settings.backstabMaxRange) .. " studs!")
        return false
    end

    -- [[ INPUT HANDLING ]]
    connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end

        if input.KeyCode == settings.aimlockKey then
            isAiming = true
        elseif input.KeyCode == settings.backstabKey then
            executeBackstab()
        elseif input.KeyCode == Enum.KeyCode.Space and settings.infiniteJump then
            local hum = getLocalHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    connect(UserInputService.InputEnded, function(input)
        if input.KeyCode == settings.aimlockKey then
            isAiming = false
        end
    end)

    -- [[ RENDER LOOP ]]
    connect(RunService.RenderStepped, function()
        if not running then return end

        -- 1. Aimlock
        if settings.aimlockEnabled and isAiming then
            local target = getClosestEnemy(settings.aimlockMaxDist, true)
            if target and target.Character then
                local part = target.Character:FindFirstChild(settings.aimlockPart) or target.Character:FindFirstChild("HumanoidRootPart")
                if part then
                    local currentCF = camera.CFrame
                    local targetCF = CFrame.new(currentCF.Position, part.Position)
                    camera.CFrame = currentCF:Lerp(targetCF, settings.aimlockSmoothness)
                end
            end
        end

        -- 2. Speed Boost
        if settings.speedEnabled then
            local hum = getLocalHumanoid()
            if hum then
                hum.WalkSpeed = settings.speedValue
            end
        end

        -- 4. Anti-Ragdoll / Quick Stand
        if settings.antiRagdoll then
            local hum = getLocalHumanoid()
            if hum then
                local state = hum:GetState()
                if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end

        -- 5. Auto M1 in Range
        if settings.autoM1 and (tick() - lastM1Time >= settings.autoM1Interval) then
            local target = getClosestEnemy(settings.autoM1Range, false)
            if target then
                lastM1Time = tick()
                pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    task.wait(0.02)
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end)
            end
        end

        -- 6. ESP Rendering
        local myRoot = getLocalRoot()
        for player, drawings in pairs(espObjects) do
            if settings.espEnabled and isTargetAlive(player) then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                local head = player.Character:FindFirstChild("Head")
                local hum = player.Character:FindFirstChildOfClass("Humanoid")

                if root and head and hum then
                    local rootPos, onScreen = camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local headPos = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                        local legPos = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                        local height = legPos.Y - headPos.Y
                        local width = height / 1.8

                        -- Box
                        if settings.boxEsp then
                            drawings.BoxOutline.Size = Vector2.new(width, height)
                            drawings.BoxOutline.Position = Vector2.new(rootPos.X - width / 2, headPos.Y)
                            drawings.BoxOutline.Visible = true

                            drawings.Box.Size = Vector2.new(width, height)
                            drawings.Box.Position = Vector2.new(rootPos.X - width / 2, headPos.Y)
                            drawings.Box.Visible = true
                        else
                            drawings.Box.Visible = false
                            drawings.BoxOutline.Visible = false
                        end

                        -- Name
                        if settings.nameEsp then
                            drawings.Name.Text = player.DisplayName .. " (@" .. player.Name .. ")"
                            drawings.Name.Position = Vector2.new(rootPos.X, headPos.Y - 16)
                            drawings.Name.Visible = true
                        else
                            drawings.Name.Visible = false
                        end

                        -- Bottom Info
                        local infoParts = {}
                        if settings.movesetEsp then
                            local moveset = player:GetAttribute("Moveset") or "Unknown"
                            table.insert(infoParts, "[" .. tostring(moveset) .. "]")
                        end
                        if settings.healthEsp then
                            table.insert(infoParts, math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth) .. " HP")
                        end
                        if settings.distanceEsp and myRoot then
                            local dist = math.floor((myRoot.Position - root.Position).Magnitude)
                            table.insert(infoParts, dist .. "m")
                        end

                        drawings.Info.Text = table.concat(infoParts, " • ")
                        drawings.Info.Position = Vector2.new(rootPos.X, legPos.Y + 2)
                        drawings.Info.Visible = true
                    else
                        drawings.Box.Visible = false
                        drawings.BoxOutline.Visible = false
                        drawings.Name.Visible = false
                        drawings.Info.Visible = false
                    end
                else
                    drawings.Box.Visible = false
                    drawings.BoxOutline.Visible = false
                    drawings.Name.Visible = false
                    drawings.Info.Visible = false
                end
            else
                drawings.Box.Visible = false
                drawings.BoxOutline.Visible = false
                drawings.Name.Visible = false
                drawings.Info.Visible = false
            end
        end
    end)

    -- [[ UI CONSTRUCTION ]]
    -- Tab 1: Combat
    local CombatTab = Window:CreateTab("Combat", 4483362458)
    CombatTab:CreateSection("Target Aimlock")

    CombatTab:CreateToggle({
        Name = "🎯 Smooth Camera Aimlock",
        CurrentValue = false,
        Flag = "AB_Aimlock",
        Callback = function(v)
            settings.aimlockEnabled = v
            if v then
                notify("Combat", "Aimlock ON: Hold [" .. tostring(settings.aimlockKey.Name) .. "] to lock target")
            end
        end,
    })

    CombatTab:CreateKeybind({
        Name = "Aimlock Key",
        CurrentKeybind = "C",
        HoldToInteract = false,
        Flag = "AB_AimlockKey",
        Callback = function(key)
            if typeof(key) == "EnumItem" then
                settings.aimlockKey = key
            end
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Aim Target Part",
        Options = {"HumanoidRootPart", "Head"},
        CurrentOption = {"HumanoidRootPart"},
        Flag = "AB_AimPart",
        Callback = function(v)
            settings.aimlockPart = type(v) == "table" and v[1] or v
        end,
    })

    CombatTab:CreateSlider({
        Name = "Aim Smoothness",
        Range = {0.05, 1.0},
        Increment = 0.05,
        Suffix = " Lerp",
        CurrentValue = 0.25,
        Flag = "AB_AimSmooth",
        Callback = function(v)
            settings.aimlockSmoothness = v
        end,
    })

    CombatTab:CreateSlider({
        Name = "Aimlock Max Distance",
        Range = {50, 500},
        Increment = 10,
        Suffix = " Studs",
        CurrentValue = 350,
        Flag = "AB_AimMaxDist",
        Callback = function(v)
            settings.aimlockMaxDist = v
        end,
    })

    CombatTab:CreateSection("Extended Attack Reach / Query Hook")

    CombatTab:CreateToggle({
        Name = "⚔️ Extended Attack Reach",
        CurrentValue = true,
        Flag = "AB_ReachEnabled",
        Callback = function(v)
            settings.reachEnabled = v
        end,
    })

    CombatTab:CreateSlider({
        Name = "Attack Reach Distance",
        Range = {4, 25},
        Increment = 1,
        Suffix = " Studs",
        CurrentValue = 12,
        Flag = "AB_ReachDist",
        Callback = function(v)
            settings.reachDistance = v
        end,
    })

    CombatTab:CreateToggle({
        Name = "🔄 360° All-Around Hit",
        CurrentValue = true,
        Flag = "AB_360Hit",
        Callback = function(v)
            settings.allAroundHit = v
        end,
    })

    CombatTab:CreateToggle({
        Name = "🧱 Wall Penetration (Bypass Occlusion)",
        CurrentValue = false,
        Flag = "AB_WallBypass",
        Callback = function(v)
            settings.wallCheckBypass = v
        end,
    })

    CombatTab:CreateSection("Auto Combat")

    CombatTab:CreateToggle({
        Name = "🥊 Auto M1 In Range",
        CurrentValue = false,
        Flag = "AB_AutoM1",
        Callback = function(v)
            settings.autoM1 = v
        end,
    })

    CombatTab:CreateSlider({
        Name = "M1 Trigger Range",
        Range = {6, 25},
        Increment = 1,
        Suffix = " Studs",
        CurrentValue = 12,
        Flag = "AB_AutoM1Range",
        Callback = function(v)
            settings.autoM1Range = v
        end,
    })

    CombatTab:CreateSlider({
        Name = "M1 Attack Speed / Interval",
        Range = {0.2, 0.5},
        Increment = 0.05,
        Suffix = "s",
        CurrentValue = 0.25,
        Flag = "AB_AutoM1Interval",
        Callback = function(v)
            settings.autoM1Interval = v
        end,
    })

    -- Tab 2: Visuals (ESP)
    local VisualTab = Window:CreateTab("Visuals", 4483362458)
    VisualTab:CreateSection("Drawing API ESP")

    VisualTab:CreateToggle({
        Name = "👁️ Master ESP",
        CurrentValue = false,
        Flag = "AB_MasterESP",
        Callback = function(v)
            settings.espEnabled = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "📦 Box ESP",
        CurrentValue = true,
        Flag = "AB_BoxESP",
        Callback = function(v)
            settings.boxEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "🏷️ Name ESP",
        CurrentValue = true,
        Flag = "AB_NameESP",
        Callback = function(v)
            settings.nameEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "❤️ Health ESP",
        CurrentValue = true,
        Flag = "AB_HealthESP",
        Callback = function(v)
            settings.healthEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "🥋 Moveset Tracker ESP",
        CurrentValue = true,
        Flag = "AB_MovesetESP",
        Callback = function(v)
            settings.movesetEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "📏 Distance ESP",
        CurrentValue = true,
        Flag = "AB_DistESP",
        Callback = function(v)
            settings.distanceEsp = v
        end,
    })

    VisualTab:CreateSection("Game Engine Debug")

    VisualTab:CreateToggle({
        Name = "🛠️ Game Native Hitbox Visualizer",
        CurrentValue = false,
        Flag = "AB_NativeHitbox",
        Callback = function(v)
            settings.nativeHitboxDebug = v
            localPlayer:SetAttribute("HitboxDebug", v)
            notify("Hitbox Debug", v and "Game hitbox visualization active" or "Hitbox visualization off")
        end,
    })

    -- Tab 3: Mobility
    local MobilityTab = Window:CreateTab("Mobility", 4483362458)
    MobilityTab:CreateSection("Speed & Movement")

    MobilityTab:CreateToggle({
        Name = "⚡ WalkSpeed Modifier",
        CurrentValue = false,
        Flag = "AB_SpeedToggle",
        Callback = function(v)
            settings.speedEnabled = v
            if not v then
                local hum = getLocalHumanoid()
                if hum then hum.WalkSpeed = 22 end
            end
        end,
    })

    MobilityTab:CreateSlider({
        Name = "WalkSpeed Value",
        Range = {22, 100},
        Increment = 1,
        Suffix = " Speed",
        CurrentValue = 35,
        Flag = "AB_SpeedVal",
        Callback = function(v)
            settings.speedValue = v
        end,
    })

    MobilityTab:CreateSection("Dash Enhancements")

    MobilityTab:CreateToggle({
        Name = "🚀 Infinite Dash (No Cooldown)",
        CurrentValue = false,
        Flag = "AB_InfDash",
        Callback = function(v)
            settings.infiniteDash = v
            applyDashSettings()
        end,
    })

    MobilityTab:CreateSlider({
        Name = "Dash Distance",
        Range = {11, 40},
        Increment = 1,
        Suffix = " Studs",
        CurrentValue = 11,
        Flag = "AB_DashDist",
        Callback = function(v)
            settings.dashDistance = v
            if settings.infiniteDash then
                applyDashSettings()
            end
        end,
    })

    MobilityTab:CreateSection("Acrobatics")

    MobilityTab:CreateToggle({
        Name = "🦘 Infinite Jump",
        CurrentValue = false,
        Flag = "AB_InfJump",
        Callback = function(v)
            settings.infiniteJump = v
        end,
    })

    MobilityTab:CreateToggle({
        Name = "🛡️ Anti-Ragdoll / Quick Stand",
        CurrentValue = false,
        Flag = "AB_AntiRagdoll",
        Callback = function(v)
            settings.antiRagdoll = v
        end,
    })

    -- Tab 4: Teleport
    local TeleportTab = Window:CreateTab("Teleport", 4483362458)
    TeleportTab:CreateSection("Tactical Backstab Teleport")

    TeleportTab:CreateKeybind({
        Name = "🗡️ Backstab Hotkey",
        CurrentKeybind = "V",
        HoldToInteract = false,
        Flag = "AB_BackstabKey",
        Callback = function(key)
            if typeof(key) == "EnumItem" then
                settings.backstabKey = key
                notify("Backstab TP", "Hotkey bound to [" .. tostring(key.Name) .. "]")
            end
        end,
    })

    TeleportTab:CreateSlider({
        Name = "Offset Distance Behind Target",
        Range = {1, 10},
        Increment = 0.5,
        Suffix = " Studs Behind",
        CurrentValue = 3,
        Flag = "AB_BackstabDist",
        Callback = function(v)
            settings.backstabDistance = v
        end,
    })

    TeleportTab:CreateSlider({
        Name = "Max Target Search Range",
        Range = {50, 500},
        Increment = 25,
        Suffix = " Studs",
        CurrentValue = 250,
        Flag = "AB_BackstabRange",
        Callback = function(v)
            settings.backstabMaxRange = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "🎯 Auto Face Target Back",
        CurrentValue = true,
        Flag = "AB_BackstabAutoFace",
        Callback = function(v)
            settings.backstabAutoFace = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "📷 Align Camera With Target",
        CurrentValue = true,
        Flag = "AB_BackstabCam",
        Callback = function(v)
            settings.backstabAlignCam = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "🥊 Auto M1 Strike On Arrival",
        CurrentValue = true,
        Flag = "AB_BackstabAutoM1",
        Callback = function(v)
            settings.backstabAutoAttack = v
        end,
    })

    TeleportTab:CreateButton({
        Name = "🚀 Execute Backstab Teleport",
        Callback = function()
            executeBackstab()
        end,
    })

    TeleportTab:CreateButton({
        Name = "☁️ Safe Sky Escape (+250 Studs Up)",
        Callback = function()
            local myRoot = getLocalRoot()
            if myRoot then
                myRoot.CFrame = myRoot.CFrame + Vector3.new(0, 250, 0)
                myRoot.AssemblyLinearVelocity = Vector3.zero
                notify("Escape", "Teleported to safe sky!")
            end
        end,
    })

    TeleportTab:CreateSection("Locations")

    TeleportTab:CreateButton({
        Name = "🏟️ Teleport to Map Spawns",
        Callback = function()
            local myRoot = getLocalRoot()
            if myRoot then
                myRoot.CFrame = CFrame.new(71.4, 398, -213.4)
                myRoot.AssemblyLinearVelocity = Vector3.zero
                notify("Teleport", "Teleported to Spawn")
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "🏠 Teleport to Lobby Leaderboards",
        Callback = function()
            local myRoot = getLocalRoot()
            if myRoot then
                myRoot.CFrame = CFrame.new(75, 412, -850)
                myRoot.AssemblyLinearVelocity = Vector3.zero
                notify("Teleport", "Teleported to Lobby")
            end
        end,
    })

    local selectedPlayer = nil
    local function getPlayerNames()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                table.insert(list, p.DisplayName .. " (@" .. p.Name .. ")")
            end
        end
        if #list == 0 then table.insert(list, "None") end
        return list
    end

    TeleportTab:CreateSection("Player Teleport")

    local playerDropdown = TeleportTab:CreateDropdown({
        Name = "Select Player",
        Options = getPlayerNames(),
        CurrentOption = {getPlayerNames()[1] or "None"},
        Flag = "AB_SelectPlayer",
        Callback = function(v)
            local chosen = type(v) == "table" and v[1] or v
            for _, p in ipairs(Players:GetPlayers()) do
                if (p.DisplayName .. " (@" .. p.Name .. ")") == chosen then
                    selectedPlayer = p
                    break
                end
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "🚀 Teleport To Selected Player",
        Callback = function()
            local myRoot = getLocalRoot()
            if selectedPlayer and selectedPlayer.Character and myRoot then
                local targetRoot = selectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot then
                    myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
                    myRoot.AssemblyLinearVelocity = Vector3.zero
                    notify("Teleport", "Teleported to " .. selectedPlayer.DisplayName)
                    return
                end
            end
            notify("Teleport", "Player not available or invalid")
        end,
    })

    TeleportTab:CreateButton({
        Name = "🔄 Refresh Player List",
        Callback = function()
            if playerDropdown and type(playerDropdown.Set) == "function" then
                playerDropdown:Set(getPlayerNames())
                notify("Teleport", "Player list refreshed!")
            end
        end,
    })

    -- Cleanup object
    local hubInstance = {
        Destroy = function()
            running = false
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            for player, _ in pairs(espObjects) do
                removeDrawingESP(player)
            end
            restoreHitboxHooks()
            restoreDashSettings()
            local hum = getLocalHumanoid()
            if hum then hum.WalkSpeed = 22 end
            localPlayer:SetAttribute("HitboxDebug", false)
            environment.__RAVEN_ANIME_BATTLEGROUNDS = nil
        end
    }

    environment.__RAVEN_ANIME_BATTLEGROUNDS = hubInstance
    notify("Anime Battlegrounds", "Module loaded successfully! 🐀⚡")
    return hubInstance
end
