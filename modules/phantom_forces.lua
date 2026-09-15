-- ============================================================
--   RAVEN HUB  |  Phantom Forces Modular Suite v2.2.0
--   PlaceId: 292439477 | GameId: 113491250
--   Anti-Cheat Compliant (Zero Metatable Hooks / 100% Drawing API)
--   Tabs: Overview, Combat, Visuals, Misc
--   Real Player Names (DisplayName / Username) & Dynamic HP Bar
-- ============================================================

return function(Window, runtimeInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")
    local VirtualInputManager = game:GetService("VirtualInputManager")

    -- Clean up previous instance if running
    local env = getgenv and getgenv() or _G
    if type(env.__RAVEN_PF) == "table" and type(env.__RAVEN_PF.Destroy) == "function" then
        pcall(env.__RAVEN_PF.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera")

    local running = true
    local connections = {}

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(connections, conn)
        return conn
    end

    -- ------------------------------------------------------------
    -- Settings & Telemetry State
    -- ------------------------------------------------------------
    local state = {
        myTeamName = nil,
        myTeamType = nil,
        targetCount = 0,
        enemyCount = 0,
    }

    local espSettings = {
        enabled = true,
        teamCheck = true,
        showBoxes = true,
        boxOutline = true,
        showNames = true,
        showHealth = true,
        showDistance = true,
        showTracers = false,
        showHeadDot = true,
        wallCheck = true,
        maxDistance = 2500,

        -- Palette
        enemyVisible = Color3.fromRGB(50, 255, 100),
        enemyHidden = Color3.fromRGB(255, 55, 55),
        teamColor = Color3.fromRGB(65, 160, 255),
        headColor = Color3.fromRGB(255, 255, 255),
        tracerColor = Color3.fromRGB(255, 80, 80),
        nameColor = Color3.fromRGB(255, 255, 255),
    }

    local aimSettings = {
        enabled = false,
        aimKey = Enum.UserInputType.MouseButton2,
        fov = 120,
        showFov = false,
        smoothness = 4,
        targetBone = "Head",
        wallCheck = true,
    }

    local autoSpot = {
        enabled = false,
        interval = 0.8,
        lastSpot = 0,
    }

    -- ------------------------------------------------------------
    -- Drawing API Helpers
    -- ------------------------------------------------------------
    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local espDrawings = {}
    local nameCache = {}
    local hpCache = {}

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        return (ok and obj) or nil
    end

    local function newDrawingSet()
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
            d.box.Color = espSettings.enemyHidden
            d.box.Visible = false
        end

        d.name = safeDrawing("Text")
        if d.name then
            d.name.Size = 13
            d.name.Center = true
            d.name.Outline = true
            d.name.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.name.Color = espSettings.nameColor
            d.name.Visible = false
        end

        d.hpBg = safeDrawing("Square")
        if d.hpBg then
            d.hpBg.Thickness = 1
            d.hpBg.Filled = true
            d.hpBg.Color = Color3.fromRGB(15, 15, 15)
            d.hpBg.Visible = false
        end

        d.hp = safeDrawing("Square")
        if d.hp then
            d.hp.Thickness = 1
            d.hp.Filled = true
            d.hp.Color = Color3.fromRGB(50, 255, 100)
            d.hp.Visible = false
        end

        d.dist = safeDrawing("Text")
        if d.dist then
            d.dist.Size = 12
            d.dist.Center = true
            d.dist.Outline = true
            d.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.dist.Color = Color3.fromRGB(255, 255, 255)
            d.dist.Visible = false
        end

        d.headDot = safeDrawing("Circle")
        if d.headDot then
            d.headDot.Thickness = 1
            d.headDot.NumSides = 16
            d.headDot.Radius = 3
            d.headDot.Filled = true
            d.headDot.Color = espSettings.headColor
            d.headDot.Visible = false
        end

        d.tracer = safeDrawing("Line")
        if d.tracer then
            d.tracer.Thickness = 1
            d.tracer.Color = espSettings.tracerColor
            d.tracer.Visible = false
        end

        return d
    end

    local function hideDrawings(d)
        if not d then return end
        if d.boxOutline then d.boxOutline.Visible = false end
        if d.box then d.box.Visible = false end
        if d.name then d.name.Visible = false end
        if d.hpBg then d.hpBg.Visible = false end
        if d.hp then d.hp.Visible = false end
        if d.dist then d.dist.Visible = false end
        if d.headDot then d.headDot.Visible = false end
        if d.tracer then d.tracer.Visible = false end
    end

    local function destroyDrawings(d)
        if not d then return end
        for _, obj in pairs(d) do
            pcall(function() obj:Remove() end)
        end
    end

    -- FOV Circle
    local fovCircle = safeDrawing("Circle")
    if fovCircle then
        fovCircle.Thickness = 1
        fovCircle.NumSides = 48
        fovCircle.Radius = aimSettings.fov
        fovCircle.Filled = false
        fovCircle.Color = Color3.fromRGB(255, 255, 255)
        fovCircle.Visible = false
    end

    -- ------------------------------------------------------------
    -- Raycast & Visibility Check
    -- ------------------------------------------------------------
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local function updateRayFilter()
        local ignore = {}
        local pf = Workspace:FindFirstChild("Players")
        if pf then table.insert(ignore, pf) end
        local ig = Workspace:FindFirstChild("Ignore")
        if ig then table.insert(ignore, ig) end
        local roots = Workspace:FindFirstChild("Roots")
        if roots then table.insert(ignore, roots) end
        rayParams.FilterDescendantsInstances = ignore
    end

    local function isPointVisible(point3D)
        local camPos = camera.CFrame.Position
        local dir = point3D - camPos
        local dist = dir.Magnitude
        if dist < 2 then return true end
        local hit = Workspace:Raycast(camPos, dir.Unit * (dist - 0.5), rayParams)
        return hit == nil
    end

    -- ------------------------------------------------------------
    -- PF Definitive Team Auto-Detection Engine
    -- ------------------------------------------------------------
    local lastTeamScan = 0

    local function getMyTeamType()
        if localPlayer.TeamColor then
            local tcName = tostring(localPlayer.TeamColor.Name):lower()
            if tcName:find("orange") or tcName:find("red") or tcName:find("brown") or tcName:find("yellow") then
                return "Ghosts"
            elseif tcName:find("blue") or tcName:find("cyan") or tcName:find("teal") then
                return "Phantoms"
            end
        end

        local pgui = localPlayer:FindFirstChild("PlayerGui")
        if pgui then
            local match = pgui:FindFirstChild("MatchScreenGui")
            if match then
                local sm = match:FindFirstChild("DisplayStartMatch")
                local lbl = sm and sm:FindFirstChild("TextTeamName")
                if lbl and lbl.Text ~= "" then
                    local t = lbl.Text:lower()
                    if t:find("ghost") then return "Ghosts" end
                    if t:find("phantom") then return "Phantoms" end
                end
            end
        end

        return nil
    end

    local function scanAndEvaluateTeam()
        local pf = Workspace:FindFirstChild("Players")
        if not pf then return end

        local myTeamType = getMyTeamType()
        if not myTeamType then return end

        for _, teamFolder in ipairs(pf:GetChildren()) do
            if teamFolder:IsA("Folder") then
                local blueCount = 0
                local brownCount = 0

                for _, model in ipairs(teamFolder:GetChildren()) do
                    if model:IsA("Model") then
                        for _, d in ipairs(model:GetDescendants()) do
                            if d:IsA("BasePart") and d.Transparency < 0.95 then
                                local bc = tostring(d.BrickColor):lower()
                                if bc:find("blue") then
                                    blueCount = blueCount + 1
                                elseif bc:find("brown") or bc:find("cocoa") or bc:find("taupe") or bc:find("orange") then
                                    brownCount = brownCount + 1
                                end
                            end
                        end
                    end
                end

                if blueCount > 0 or brownCount > 0 then
                    local folderType = (blueCount > brownCount) and "Phantoms" or "Ghosts"
                    if folderType == myTeamType then
                        state.myTeamName = teamFolder.Name
                        state.myTeamType = myTeamType
                        return
                    end
                end
            end
        end
    end

    -- ------------------------------------------------------------
    -- Model Bounds & Hitbox Resolution + Real Name & Health
    -- ------------------------------------------------------------
    local function getModelData(model)
        local totalPos = Vector3.zero
        local partCount = 0
        local maxY, minY = -math.huge, math.huge
        local highestPart = nil

        local fallbackTotalPos = Vector3.zero
        local fallbackCount = 0
        local fallbackMaxY, fallbackMinY = -math.huge, math.huge

        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                local pPos = d.Position
                fallbackTotalPos = fallbackTotalPos + pPos
                fallbackCount = fallbackCount + 1
                if pPos.Y > fallbackMaxY then fallbackMaxY = pPos.Y end
                if pPos.Y < fallbackMinY then fallbackMinY = pPos.Y end

                if d.Transparency < 0.98 then
                    totalPos = totalPos + pPos
                    partCount = partCount + 1
                    if pPos.Y > maxY then
                        maxY = pPos.Y
                        highestPart = d
                    end
                    if pPos.Y < minY then
                        minY = pPos.Y
                    end
                end
            end
        end

        if partCount == 0 then
            if fallbackCount == 0 then return nil end
            totalPos = fallbackTotalPos
            partCount = fallbackCount
            maxY = fallbackMaxY
            minY = fallbackMinY
        end

        local center = totalPos / partCount
        local headPos = Vector3.new(center.X, maxY + 0.3, center.Z)
        local feetPos = Vector3.new(center.X, minY - 0.2, center.Z)

        -- 1. Real Player Name Resolution via NameTagGui / PlayerTag
        local mKey = model.Name
        local realName = nameCache[mKey]
        local hpRatio = hpCache[mKey] or 1

        local ntg = model:FindFirstChildWhichIsA("BillboardGui", true)
        if ntg then
            local pt = ntg:FindFirstChild("PlayerTag", true)
            if pt and pt.Text and pt.Text ~= "" then
                local rawName = pt.Text
                local plrObj = Players:FindFirstChild(rawName)
                if plrObj and plrObj.DisplayName and plrObj.DisplayName ~= "" and plrObj.DisplayName ~= rawName then
                    realName = plrObj.DisplayName .. " (@" .. rawName .. ")"
                else
                    realName = rawName
                end
                nameCache[mKey] = realName

                -- 2. Real-Time Dynamic Health Resolution via NameTagGui Health Percent Frame
                local hpFrame = pt:FindFirstChild("Health")
                local pctFrame = hpFrame and hpFrame:FindFirstChild("Percent")
                if pctFrame and pctFrame.Size then
                    hpRatio = math.clamp(pctFrame.Size.X.Scale, 0, 1)
                    hpCache[mKey] = hpRatio
                end
            end
        end

        return {
            center = center,
            head = headPos,
            feet = feetPos,
            headPart = highestPart,
            realName = realName or mKey,
            hpRatio = hpRatio,
        }
    end

    -- ------------------------------------------------------------
    -- Aim Assist Engine
    -- ------------------------------------------------------------
    local function getClosestEnemyToCursor()
        local pf = Workspace:FindFirstChild("Players")
        if not pf or not state.myTeamName then return nil end

        local mousePos = UserInputService:GetMouseLocation()
        local bestTarget = nil
        local bestDist = aimSettings.fov

        for _, teamFolder in ipairs(pf:GetChildren()) do
            if teamFolder:IsA("Folder") and teamFolder.Name ~= state.myTeamName then
                for _, model in ipairs(teamFolder:GetChildren()) do
                    if model:IsA("Model") then
                        local mData = getModelData(model)
                        if mData then
                            local aimPoint = (aimSettings.targetBone == "Head") and mData.head or mData.center
                            local screenPos, onScreen = camera:WorldToViewportPoint(aimPoint)

                            if onScreen and screenPos.Z > 0 then
                                if not aimSettings.wallCheck or isPointVisible(aimPoint) then
                                    local dist2D = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                                    if dist2D < bestDist then
                                        bestDist = dist2D
                                        bestTarget = {
                                            pos3D = aimPoint,
                                            pos2D = Vector2.new(screenPos.X, screenPos.Y),
                                            dist2D = dist2D,
                                        }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestTarget
    end

    -- ------------------------------------------------------------
    -- Main Render & Logic Loop
    -- ------------------------------------------------------------
    connect(RunService.RenderStepped, function()
        if not running then return end

        local pf = Workspace:FindFirstChild("Players")
        if not pf then return end

        -- 1. Continuous Auto Team Detection
        if not state.myTeamName or (os.clock() - lastTeamScan >= 1.5) then
            lastTeamScan = os.clock()
            scanAndEvaluateTeam()
        end

        -- 2. FOV Circle Update
        if fovCircle then
            fovCircle.Visible = aimSettings.enabled and aimSettings.showFov
            if fovCircle.Visible then
                fovCircle.Position = UserInputService:GetMouseLocation()
                fovCircle.Radius = aimSettings.fov
            end
        end

        -- 3. Aim Assist Action
        if aimSettings.enabled and UserInputService:IsMouseButtonPressed(aimSettings.aimKey) then
            local target = getClosestEnemyToCursor()
            if target and mousemoverel then
                local mousePos = UserInputService:GetMouseLocation()
                local delta = (target.pos2D - mousePos) / math.max(1, aimSettings.smoothness)
                mousemoverel(delta.X, delta.Y)
            end
        end

        -- 4. Auto Spot Action
        if autoSpot.enabled and (os.clock() - autoSpot.lastSpot >= autoSpot.interval) then
            local shooting = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
            local aiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
            if not shooting and not aiming then
                autoSpot.lastSpot = os.clock()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.delay(0.05, function()
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
            end
        end

        -- 5. ESP Rendering
        if espSettings.wallCheck then
            updateRayFilter()
        end

        local myCamPos = camera.CFrame.Position
        local viewportSize = camera.ViewportSize
        local activeKeys = {}
        local totalEnemies = 0

        if espSettings.enabled then
            for _, teamFolder in ipairs(pf:GetChildren()) do
                if teamFolder:IsA("Folder") then
                    local isEnemyTeam = (teamFolder.Name ~= state.myTeamName)
                    if espSettings.teamCheck and not isEnemyTeam then
                        continue
                    end

                    for _, model in ipairs(teamFolder:GetChildren()) do
                        if model:IsA("Model") then
                            local key = model.Name
                            activeKeys[key] = true
                            totalEnemies = totalEnemies + 1

                            if not espDrawings[key] then
                                espDrawings[key] = newDrawingSet()
                            end
                            local d = espDrawings[key]

                            local mData = getModelData(model)
                            if not mData then
                                hideDrawings(d)
                                continue
                            end

                            local dist = (mData.center - myCamPos).Magnitude
                            if dist > espSettings.maxDistance or dist < 2 then
                                hideDrawings(d)
                                continue
                            end

                            local centerScreen, centerOn = camera:WorldToViewportPoint(mData.center)
                            if centerScreen.Z <= 0 then
                                hideDrawings(d)
                                continue
                            end

                            local headScreen, headOn = camera:WorldToViewportPoint(mData.head)
                            local feetScreen, feetOn = camera:WorldToViewportPoint(mData.feet)

                            local isAnyOnScreen = centerOn or headOn or feetOn
                            if not isAnyOnScreen then
                                if centerScreen.X < -100 or centerScreen.X > viewportSize.X + 100 
                                   or centerScreen.Y < -100 or centerScreen.Y > viewportSize.Y + 100 then
                                    hideDrawings(d)
                                    continue
                                end
                            end

                            local boxHeight = math.abs(feetScreen.Y - headScreen.Y)
                            if boxHeight < 6 then
                                boxHeight = math.clamp(1200 / dist, 10, 400)
                            end

                            local boxWidth = math.floor(boxHeight * 0.55)
                            local boxX = math.floor(centerScreen.X - boxWidth / 2)
                            local boxY = math.floor(centerScreen.Y - boxHeight / 2)

                            local isVisible = true
                            if espSettings.wallCheck then
                                isVisible = isPointVisible(mData.head) or isPointVisible(mData.center)
                            end

                            local boxColor = isEnemyTeam
                                and (isVisible and espSettings.enemyVisible or espSettings.enemyHidden)
                                or espSettings.teamColor

                            -- 1. Bounding Box
                            if espSettings.showBoxes and d.box then
                                if espSettings.boxOutline and d.boxOutline then
                                    d.boxOutline.Size = Vector2.new(boxWidth + 2, boxHeight + 2)
                                    d.boxOutline.Position = Vector2.new(boxX - 1, boxY - 1)
                                    d.boxOutline.Visible = true
                                else
                                    if d.boxOutline then d.boxOutline.Visible = false end
                                end

                                d.box.Size = Vector2.new(boxWidth, boxHeight)
                                d.box.Position = Vector2.new(boxX, boxY)
                                d.box.Color = boxColor
                                d.box.Visible = true
                            else
                                if d.boxOutline then d.boxOutline.Visible = false end
                                if d.box then d.box.Visible = false end
                            end

                            -- 2. Real Player Name (Display Name + User Name)
                            if espSettings.showNames and d.name then
                                d.name.Text = mData.realName or key
                                d.name.Position = Vector2.new(centerScreen.X, boxY - 16)
                                d.name.Color = isVisible and espSettings.nameColor or Color3.fromRGB(180, 180, 180)
                                d.name.Visible = true
                            else
                                if d.name then d.name.Visible = false end
                            end

                            -- 3. Dynamic Real-Time Health Bar (Decreases accurately with damage)
                            if espSettings.showHealth and d.hp and d.hpBg then
                                local barWidth = 3
                                local barX = boxX - barWidth - 3
                                local hpRatio = mData.hpRatio or 1

                                d.hpBg.Size = Vector2.new(barWidth, boxHeight + 2)
                                d.hpBg.Position = Vector2.new(barX, boxY - 1)
                                d.hpBg.Visible = true

                                local fillHeight = math.clamp(math.floor(boxHeight * hpRatio), 1, boxHeight)
                                d.hp.Size = Vector2.new(barWidth, fillHeight)
                                d.hp.Position = Vector2.new(barX, boxY + (boxHeight - fillHeight))

                                -- Dynamic color: Green -> Yellow -> Red
                                local hpColor
                                if hpRatio > 0.6 then
                                    hpColor = Color3.fromRGB(50, 255, 100)
                                elseif hpRatio > 0.25 then
                                    hpColor = Color3.fromRGB(255, 210, 40)
                                else
                                    hpColor = Color3.fromRGB(255, 45, 45)
                                end

                                d.hp.Color = hpColor
                                d.hp.Visible = true
                            else
                                if d.hp then d.hp.Visible = false end
                                if d.hpBg then d.hpBg.Visible = false end
                            end

                            -- 4. Distance Tag (anchored below the box)
                            if espSettings.showDistance and d.dist then
                                d.dist.Text = string.format("%dm", math.floor(dist))
                                d.dist.Position = Vector2.new(centerScreen.X, boxY + boxHeight + 2)
                                d.dist.Visible = true
                            else
                                if d.dist then d.dist.Visible = false end
                            end

                            -- 5. Head Dot
                            if espSettings.showHeadDot and d.headDot then
                                local dotX = headOn and headScreen.X or centerScreen.X
                                local dotY = headOn and headScreen.Y or boxY
                                d.headDot.Position = Vector2.new(dotX, dotY)
                                d.headDot.Color = isVisible and espSettings.headColor or espSettings.enemyHidden
                                d.headDot.Visible = true
                            else
                                if d.headDot then d.headDot.Visible = false end
                            end

                            -- 6. Tracers
                            if espSettings.showTracers and d.tracer then
                                d.tracer.From = Vector2.new(viewportSize.X / 2, viewportSize.Y)
                                d.tracer.To = Vector2.new(centerScreen.X, boxY + boxHeight)
                                d.tracer.Color = boxColor
                                d.tracer.Visible = true
                            else
                                if d.tracer then d.tracer.Visible = false end
                            end
                        end
                    end
                end
            end
        end

        state.enemyCount = totalEnemies

        -- Cleanup inactive drawing sets
        for key, d in pairs(espDrawings) do
            if not activeKeys[key] then
                hideDrawings(d)
                nameCache[key] = nil
                hpCache[key] = nil
            end
        end
    end)

    -- ------------------------------------------------------------
    -- UI Interface: Split Tabs (Overview, Combat, Visuals, Misc)
    -- ------------------------------------------------------------
    local CombatTab = Window:CreateTab("Combat", "combat")
    local VisualsTab = Window:CreateTab("Visuals", "visuals")
    local MiscTab = Window:CreateTab("Misc", "misc")

    -- 1. Visuals Tab
    VisualsTab:CreateSection("Visuals (Drawing API)")

    VisualsTab:CreateToggle({
        Name = "Enable ESP",
        CurrentValue = espSettings.enabled,
        Callback = function(val)
            espSettings.enabled = val
            if not val then
                for _, d in pairs(espDrawings) do hideDrawings(d) end
            end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Team Check (Enemies Only)",
        CurrentValue = espSettings.teamCheck,
        Callback = function(val)
            espSettings.teamCheck = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Player Name",
        CurrentValue = espSettings.showNames,
        Callback = function(val)
            espSettings.showNames = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show HP Bar",
        CurrentValue = espSettings.showHealth,
        Callback = function(val)
            espSettings.showHealth = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show 2D Boxes",
        CurrentValue = espSettings.showBoxes,
        Callback = function(val)
            espSettings.showBoxes = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = espSettings.showDistance,
        Callback = function(val)
            espSettings.showDistance = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Head Dot",
        CurrentValue = espSettings.showHeadDot,
        Callback = function(val)
            espSettings.showHeadDot = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Tracers (Snaplines)",
        CurrentValue = espSettings.showTracers,
        Callback = function(val)
            espSettings.showTracers = val
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Wall Check (Green/Red)",
        CurrentValue = espSettings.wallCheck,
        Callback = function(val)
            espSettings.wallCheck = val
        end,
    })

    VisualsTab:CreateSlider({
        Name = "Max Render Distance",
        Range = {100, 3000},
        Increment = 50,
        CurrentValue = espSettings.maxDistance,
        Suffix = " studs",
        Callback = function(val)
            espSettings.maxDistance = val
        end,
    })

    -- 2. Combat Tab
    CombatTab:CreateSection("Combat & Aim Assist")

    CombatTab:CreateToggle({
        Name = "Smooth Aim Assist",
        CurrentValue = aimSettings.enabled,
        Callback = function(val)
            aimSettings.enabled = val
        end,
    })

    CombatTab:CreateToggle({
        Name = "Show FOV Circle",
        CurrentValue = aimSettings.showFov,
        Callback = function(val)
            aimSettings.showFov = val
        end,
    })

    CombatTab:CreateSlider({
        Name = "Aim FOV Radius",
        Range = {30, 400},
        Increment = 10,
        CurrentValue = aimSettings.fov,
        Suffix = " px",
        Callback = function(val)
            aimSettings.fov = val
        end,
    })

    CombatTab:CreateSlider({
        Name = "Smoothness",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = aimSettings.smoothness,
        Suffix = " factor",
        Callback = function(val)
            aimSettings.smoothness = val
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Target Bone",
        Options = {"Head", "Torso"},
        CurrentOption = aimSettings.targetBone,
        Callback = function(val)
            aimSettings.targetBone = val
        end,
    })

    CombatTab:CreateToggle({
        Name = "Aim Wall Check",
        CurrentValue = aimSettings.wallCheck,
        Callback = function(val)
            aimSettings.wallCheck = val
        end,
    })

    -- 3. Misc Tab
    MiscTab:CreateSection("Auto Spot")

    MiscTab:CreateToggle({
        Name = "Auto Spot (E Key)",
        CurrentValue = autoSpot.enabled,
        Callback = function(val)
            autoSpot.enabled = val
        end,
    })

    MiscTab:CreateSlider({
        Name = "Spot Interval",
        Range = {0.4, 3.0},
        Increment = 0.1,
        CurrentValue = autoSpot.interval,
        Suffix = " s",
        Callback = function(val)
            autoSpot.interval = val
        end,
    })

    MiscTab:CreateSection("Team Detection (100% Auto)")

    local teamStatusLabel = MiscTab:CreateLabel("My Team: Detecting...")
    task.spawn(function()
        while running do
            if teamStatusLabel and type(teamStatusLabel.Set) == "function" then
                local t = state.myTeamName
                local tType = state.myTeamType
                teamStatusLabel:Set("My Team: " .. (tType and (tType .. " (" .. tostring(t):sub(1, 6) .. ")") or "Scanning..."))
            end
            task.wait(1)
        end
    end)

    MiscTab:CreateButton({
        Name = "Force Re-Scan Team",
        Callback = function()
            scanAndEvaluateTeam()
            pcall(function()
                game:GetService("StarterGui"):SetCore("SendNotification", {
                    Title = "RAVEN HUB",
                    Text = "Team: " .. tostring(state.myTeamType or "Scanning..."),
                    Duration = 2,
                })
            end)
        end,
    })

    -- Explicit Tab Sorting
    if type(Window.SortTabs) == "function" then
        Window:SortTabs({"Overview", "Combat", "Visuals", "Misc", "Settings"})
    end

    -- ------------------------------------------------------------
    -- Cleanup Lifecycle
    -- ------------------------------------------------------------
    local function cleanup()
        running = false
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        connections = {}

        if fovCircle then
            pcall(function() fovCircle:Remove() end)
            fovCircle = nil
        end

        for _, d in pairs(espDrawings) do
            destroyDrawings(d)
        end
        espDrawings = {}
        nameCache = {}
        hpCache = {}

        env.__RAVEN_PF = nil
    end

    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(cleanup)
    end

    env.__RAVEN_PF = {
        Destroy = cleanup,
        State = state,
        EspSettings = espSettings,
        AimSettings = aimSettings,
    }

    return cleanup
end
