-- ============================================================
--   RAVEN HUB  |  8 Ball Duels (God-Tier Pool Engine)
--   Multi-Bounce Extended Guidelines, Cushion Reflection Solver,
--   Auto Aim & Auto Pocket, Ball Trajectory ESP, Max Cue Stats
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")

    -- Clean up previous instance if running
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_8BALL_DUELS) == "table"
        and type(environment.__RAVEN_8BALL_DUELS.Destroy) == "function" then
        pcall(environment.__RAVEN_8BALL_DUELS.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}

    -- Safe connection tracking
    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    -- Core Pool Modules
    local Pool = ReplicatedStorage:WaitForChild("Libraries"):WaitForChild("GameSpecific"):WaitForChild("Pool")
    local PoolConstants = require(Pool:WaitForChild("PoolConstants"))
    local PoolGeometry = require(Pool:WaitForChild("PoolGeometry"))
    local PoolPhysics = require(Pool:WaitForChild("PoolPhysics"))
    local PoolRules = require(Pool:WaitForChild("PoolRules"))
    local PoolAimOverlay = require(Pool:WaitForChild("PoolAimOverlay"))
    local PoolInputController = require(Pool:WaitForChild("PoolInputController"))
    local PoolMatchClient = require(Pool:WaitForChild("PoolMatchClient"))
    local PoolMatchSession = require(Pool:WaitForChild("PoolMatchSession"))

    -- Constants cache
    local BallRadius = PoolConstants.BallRadius
    local BallDiameter = PoolConstants.BallDiameter
    local FrameWidth = PoolConstants.FrameWidth
    local FrameHeight = PoolConstants.FrameHeight
    local CueBallNumber = PoolConstants.CueBallNumber
    local Cushions = PoolGeometry.GetCushions()
    local Pockets = PoolGeometry.GetPockets()

    local cushionsById = {}
    for _, c in ipairs(Cushions) do
        cushionsById[c.Id] = c
    end

    -- Settings
    local settings = {
        -- Tab 1: Extended Guidelines & Physics
        extendedLines = true,
        hideDefaultLines = true,
        fullPhysicsSimulation = true,
        showAllMovingBalls = true,
        showRestingGhostBalls = true,
        maxBounces = 4,
        showObjectBounce = true,
        objectBounces = 2,
        showCueDeflection = true,
        cueDeflectionBounces = 2,
        showCueRestPosition = true,
        showCollisionRing = true,
        showPocketLanding = true,
        lineThickness = 0.55,
        cueColor = Color3.fromRGB(0, 240, 255),
        cushionBounceColor = Color3.fromRGB(180, 100, 255),
        objectColor = Color3.fromRGB(255, 75, 130),
        comboColor = Color3.fromRGB(255, 185, 45),
        cueDeflectColor = Color3.fromRGB(255, 255, 255),
        pocketTargetColor = Color3.fromRGB(50, 255, 120),

        -- Tab 2: Aim Assist & Pocket Solver
        autoAim = false,
        autoAimKey = "E",
        autoShoot = false,
        lockAimOnTarget = true,
        shotPreference = "Prefer Bank (ฉิ่งลงหลุมก่อน)",
        smoothAim = true,
        aimSmoothingSpeed = 8, -- higher = faster smooth glide
        aimHumanOvershoot = true, -- realistic micro human adjustments
        shootPower = 0.70,
        smartPower = true,
        preferCloserBall = true,
        aimTargetBall = "Auto Best", -- "Auto Best", "1", "2", ... "15"

        -- Tab 3: Cue Sticks Modifiers
        godCueStats = true,
        aimMultiplier = 10,
        forceMultiplier = 10,
        spinMultiplier = 10,
        timeMultiplier = 10,

        -- Tab 4: Match Automation
        autoBreak = false,
        breakPower = 1.0,
        autoRematchBot = false,
    }

    -- Backup original cue table values
    local originalCues = {}
    if type(PoolConstants.Cues) == "table" then
        for cueId, cueData in pairs(PoolConstants.Cues) do
            originalCues[cueId] = {
                Aim = cueData.Aim,
                Force = cueData.Force,
                Spin = cueData.Spin,
                Time = cueData.Time,
            }
        end
    end

    -- Apply God Cue stats
    local function applyCueStats()
        if not PoolConstants.Cues then return end
        for cueId, cueData in pairs(PoolConstants.Cues) do
            if settings.godCueStats then
                cueData.Aim = settings.aimMultiplier
                cueData.Force = settings.forceMultiplier
                cueData.Spin = settings.spinMultiplier
                cueData.Time = settings.timeMultiplier
            elseif originalCues[cueId] then
                cueData.Aim = originalCues[cueId].Aim
                cueData.Force = originalCues[cueId].Force
                cueData.Spin = originalCues[cueId].Spin
                cueData.Time = originalCues[cueId].Time
            end
        end
    end
    applyCueStats()

    -- Modify Base Constants
    local origBasePrediction = PoolConstants.BasePredictionLength
    local origMaxBounces = PoolConstants.MaxPredictionBounces
    local origShowCollision = PoolConstants.ShowCollisionOverlay

    local function applyConstants()
        if settings.extendedLines then
            PoolConstants.BasePredictionLength = 200
            PoolConstants.MaxPredictionBounces = settings.maxBounces
            PoolConstants.ShowCollisionOverlay = settings.showCollisionRing
        else
            PoolConstants.BasePredictionLength = origBasePrediction
            PoolConstants.MaxPredictionBounces = origMaxBounces
            PoolConstants.ShowCollisionOverlay = origShowCollision
        end
    end
    applyConstants()

    local activeMatchClient = nil
    local activeInputController = nil
    local activeAimOverlay = nil
    local activeSimulation = nil

    local function resolveActiveControllers()
        if activeInputController and activeSimulation then
            if not activeInputController._ravenShotHooked and activeInputController.Shot then
                activeInputController._ravenShotHooked = true
                connect(activeInputController.Shot, function()
                    activeInputController.AimLocked = false
                    activeInputController.AimAnchor = nil
                end)
            end
            return activeInputController, activeSimulation
        end
        if getgc then
            for _, obj in ipairs(getgc(true)) do
                if type(obj) == "table" and type(rawget(obj, "Direction")) == "userdata" and rawget(obj, "Shot") and rawget(obj, "Simulation") then
                    activeInputController = obj
                    activeSimulation = obj.Simulation
                    if obj.Overlay then activeAimOverlay = obj.Overlay end
                    if not obj._ravenShotHooked and obj.Shot then
                        obj._ravenShotHooked = true
                        connect(obj.Shot, function()
                            obj.AimLocked = false
                            obj.AimAnchor = nil
                        end)
                    end
                    return activeInputController, activeSimulation
                end
            end
        end
        return activeInputController, activeSimulation
    end

    local origMatchClientNew = PoolMatchClient.new
    PoolMatchClient.new = function(...)
        local inst = origMatchClientNew(...)
        activeMatchClient = inst
        if type(inst) == "table" then
            if type(inst.Input) == "table" then activeInputController = inst.Input end
            if type(inst.Overlay) == "table" then activeAimOverlay = inst.Overlay end
            if type(inst.Simulation) == "table" then activeSimulation = inst.Simulation end
        end
        return inst
    end
    resolveActiveControllers()

    -- Hook PoolAimOverlay to completely suppress native short white & yellow guidelines
    local origAimOverlayUpdate = PoolAimOverlay.Update
    PoolAimOverlay.Update = function(self, ...)
        origAimOverlayUpdate(self, ...)
        if settings.hideDefaultLines then
            if self.AimLine then
                self.AimLine.Visible = false
                self.AimLine.ImageTransparency = 1
                self.AimLine.BackgroundTransparency = 1
            end
            if self.ObjectLine then
                self.ObjectLine.Visible = false
                self.ObjectLine.ImageTransparency = 1
                self.ObjectLine.BackgroundTransparency = 1
            end
            if self.CueLine then
                self.CueLine.Visible = false
                self.CueLine.ImageTransparency = 1
                self.CueLine.BackgroundTransparency = 1
            end
            if self.Ghost then
                self.Ghost.Visible = false
                self.Ghost.ImageTransparency = 1
                self.Ghost.BackgroundTransparency = 1
            end
        end
    end

    -- Physics-accurate Cushion Reflection Helper
    -- Replicates PoolPhysics.resolveNormalBounce using CushionFriction & CushionRestitution
    local function computeCushionBounce(inDir, normal)
        local Physics = PoolConstants.Physics
        local v = inDir.Unit
        local n = normal.Unit
        local normalDot = v:Dot(n)
        if normalDot >= 0 then
            -- Glancing or parallel; fallback
            return (v - 2 * normalDot * n).Unit
        end

        local tangential = (v - n * normalDot) * (1 - (Physics and Physics.CushionFriction or 0.2))
        local normalComp = n * (normalDot * (Physics and Physics.CushionRestitution or 0.72))
        local reflected = (tangential - normalComp)
        if reflected.Magnitude > 0.0001 then
            return reflected.Unit
        end
        return (v - 2 * normalDot * n).Unit
    end

    -- Helper to get live UI AimOverlay container
    local function getAimOverlayFrame()
        local pgui = localPlayer:FindFirstChild("PlayerGui")
        if not pgui then return nil end
        local poolUI = pgui:FindFirstChild("PoolGameUI")
        if not poolUI then return nil end
        local tbl = poolUI:FindFirstChild("Table")
        if not tbl then return nil end
        local poolTable = tbl:FindFirstChild("PoolTable")
        if not poolTable then return nil end
        local overlay = poolTable:FindFirstChild("Overlay")
        if not overlay then return nil end
        return overlay:FindFirstChild("AimOverlay")
    end

    -- Suppress native lines on UI overlay
    local function suppressNativeLines()
        if not settings.hideDefaultLines then return end
        local overlay = getAimOverlayFrame()
        if not overlay then return end
        for _, name in ipairs({"AimLine", "ObjectLine", "CueLine", "Ghost"}) do
            local obj = overlay:FindFirstChild(name)
            if obj then
                obj.Visible = false
                if obj:IsA("GuiObject") then
                    obj.BackgroundTransparency = 1
                end
                if obj:IsA("ImageLabel") then
                    obj.ImageTransparency = 1
                end
            end
        end
    end

    -- ============================================================
    --   CUSTOM MULTI-BOUNCE UI RENDERER (ImageLabels in Table Space)
    -- ============================================================
    local customLinePool = {}
    local customMarkerPool = {}

    local function getOrCreateLine(index)
        if customLinePool[index] then return customLinePool[index] end
        local overlay = getAimOverlayFrame()
        if not overlay then return nil end

        local line = Instance.new("Frame")
        line.Name = "RavenTrajectoryLine_" .. tostring(index)
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.BorderSizePixel = 0
        line.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
        line.BackgroundTransparency = 0
        line.ZIndex = 80 + index
        line.Visible = false

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = line

        line.Parent = overlay

        customLinePool[index] = line
        return line
    end

    local function getOrCreateMarker(index)
        if customMarkerPool[index] then return customMarkerPool[index] end
        local overlay = getAimOverlayFrame()
        if not overlay then return nil end

        local marker = Instance.new("ImageLabel")
        marker.Name = "RavenImpactMarker_" .. tostring(index)
        marker.AnchorPoint = Vector2.new(0.5, 0.5)
        marker.BorderSizePixel = 0
        marker.BackgroundTransparency = 1
        marker.ZIndex = 90 + index
        marker.Visible = false

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1.5
        stroke.Color = Color3.fromRGB(255, 255, 255)
        stroke.Parent = marker

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = marker

        marker.Parent = overlay
        customMarkerPool[index] = marker
        return marker
    end

    local function setTableLine(lineObj, p15, p16, thickness, color)
        local v18 = p16 - p15
        local mag = v18.Magnitude
        if mag < 0.001 then
            lineObj.Visible = false
            return
        end
        local mid = (p15 + p16) / 2
        lineObj.Position = UDim2.fromScale(0.5 + mid.X / FrameWidth, 0.5 - mid.Y / FrameHeight)
        lineObj.Size = UDim2.fromScale(mag / FrameWidth, thickness / FrameHeight)
        lineObj.Rotation = math.deg(math.atan2(-v18.Y, v18.X))
        lineObj.BackgroundColor3 = color
        lineObj.Visible = true
    end

    local function setTableMarker(markerObj, centerPos, diameter, color)
        markerObj.Position = UDim2.fromScale(0.5 + centerPos.X / FrameWidth, 0.5 - centerPos.Y / FrameHeight)
        markerObj.Size = UDim2.fromScale(diameter / FrameWidth, diameter / FrameHeight)
        local stroke = markerObj:FindFirstChildOfClass("UIStroke")
        if stroke then stroke.Color = color end
        markerObj.Visible = true
    end

    local function hideAllCustomDrawings()
        for _, l in pairs(customLinePool) do
            if l and l.Visible then l.Visible = false end
        end
        for _, m in pairs(customMarkerPool) do
            if m and m.Visible then m.Visible = false end
        end
    end

    -- ============================================================
    --   MULTI-BOUNCE RAYCAST & COLLISION SOLVER
    -- ============================================================
    local function traceCueBallRay(sim, startPos, startDir, maxBounces)
        local segments = {}
        if not sim or not startPos or not startDir or startDir.Magnitude < 1e-6 then
            return segments, nil
        end
        local currPos = startPos
        local currDir = startDir.Unit
        local finalHit = nil

        for bounce = 1, maxBounces do
            if not sim.Balls or not sim.Balls[CueBallNumber] then break end
            sim.Balls[CueBallNumber].Position = currPos
            sim.Balls[CueBallNumber].Pocketed = false
            sim.Balls[CueBallNumber].Velocity = currDir

            local okCast, cast = pcall(function()
                return PoolPhysics.CastCueBall(sim, currDir)
            end)

            if not okCast or not cast or cast.Kind == "None" or not cast.Ghost then
                local endPoint = currPos + currDir * 70
                table.insert(segments, {
                    from = currPos,
                    to = endPoint,
                    kind = "None",
                    color = (bounce == 1) and settings.cueColor or settings.cushionBounceColor
                })
                break
            end

            local hitPos = cast.Ghost
            local segColor = (bounce == 1) and settings.cueColor or settings.cushionBounceColor
            table.insert(segments, {
                from = currPos,
                to = hitPos,
                kind = cast.Kind,
                other = cast.Other,
                cushionId = cast.CushionId,
                pocketId = cast.PocketId,
                color = segColor
            })
            finalHit = cast

            if cast.Kind == "Ball" or cast.Kind == "Pocket" or cast.Kind == "Tip" then
                break
            elseif cast.Kind == "Cushion" then
                local cushion = cushionsById[cast.CushionId]
                if not cushion then break end
                local reflected = computeCushionBounce(currDir, cushion.Normal)
                currPos = hitPos + reflected * 0.05
                currDir = reflected
            else
                break
            end
        end

        return segments, finalHit
    end

    local function traceObjectBallRay(sim, startPos, startDir, maxBounces, hitBallNum)
        local segments = {}
        if not sim or not startPos or not startDir or startDir.Magnitude < 1e-6 then
            return segments
        end
        local currPos = startPos
        local currDir = startDir.Unit

        -- Temporarily hide the hit object ball to prevent immediate self-collision
        local originalObjPos = nil
        if hitBallNum and sim.Balls and sim.Balls[hitBallNum] then
            originalObjPos = sim.Balls[hitBallNum].Position
            sim.Balls[hitBallNum].Position = Vector2.new(9999, 9999)
        end

        for bounce = 1, maxBounces do
            if not sim.Balls or not sim.Balls[CueBallNumber] then break end
            sim.Balls[CueBallNumber].Position = currPos
            sim.Balls[CueBallNumber].Pocketed = false
            sim.Balls[CueBallNumber].Velocity = currDir

            local okCast, cast = pcall(function()
                return PoolPhysics.CastCueBall(sim, currDir)
            end)

            if not okCast or not cast or cast.Kind == "None" or not cast.Ghost then
                local endPoint = currPos + currDir * 60
                table.insert(segments, {
                    from = currPos,
                    to = endPoint,
                    kind = "None",
                    color = settings.objectColor
                })
                break
            end

            local hitPos = cast.Ghost
            local isPocket = (cast.Kind == "Pocket")
            table.insert(segments, {
                from = currPos,
                to = hitPos,
                kind = cast.Kind,
                other = cast.Other,
                cushionId = cast.CushionId,
                pocketId = cast.PocketId,
                color = isPocket and settings.pocketTargetColor or settings.objectColor
            })

            if cast.Kind == "Ball" or cast.Kind == "Pocket" or cast.Kind == "Tip" then
                break
            elseif cast.Kind == "Cushion" then
                local cushion = cushionsById[cast.CushionId]
                if not cushion then break end
                local reflected = computeCushionBounce(currDir, cushion.Normal)
                currPos = hitPos + reflected * 0.05
                currDir = reflected
            else
                break
            end
        end

        if hitBallNum and originalObjPos and sim.Balls[hitBallNum] then
            sim.Balls[hitBallNum].Position = originalObjPos
        end

        return segments
    end

    -- 3. Trace Cue Ball Deflection (where the cue ball travels after striking the object ball)
    -- Calculates exact physical roll distance based on shot speed, impact cut angle, and table friction
    local function traceCueDeflectionRay(sim, startPos, startDir, maxDistance, maxBounces)
        local segments = {}
        if not sim or not startPos or not startDir or startDir.Magnitude < 1e-6 then
            return segments, startPos or Vector2.zero, false
        end
        local currPos = startPos
        local currDir = startDir.Unit
        local remainingDist = maxDistance or 50
        local finalStopPos = currPos
        local reachedPocket = false

        for bounce = 1, maxBounces do
            if remainingDist <= 0.05 then break end
            if not sim.Balls or not sim.Balls[CueBallNumber] then break end

            sim.Balls[CueBallNumber].Position = currPos
            sim.Balls[CueBallNumber].Pocketed = false
            sim.Balls[CueBallNumber].Velocity = currDir

            local okCast, cast = pcall(function()
                return PoolPhysics.CastCueBall(sim, currDir)
            end)

            if not okCast or not cast or cast.Kind == "None" or not cast.Ghost then
                local endPoint = currPos + currDir * remainingDist
                table.insert(segments, {
                    from = currPos,
                    to = endPoint,
                    kind = "None",
                    color = settings.cueDeflectColor
                })
                finalStopPos = endPoint
                remainingDist = 0
                break
            end

            local hitDist = cast.Distance or (cast.Ghost - currPos).Magnitude
            if hitDist >= remainingDist then
                -- Cue ball decelerates to complete stop before reaching obstacle/cushion
                local endPoint = currPos + currDir * remainingDist
                table.insert(segments, {
                    from = currPos,
                    to = endPoint,
                    kind = "Rest",
                    color = settings.cueDeflectColor
                })
                finalStopPos = endPoint
                remainingDist = 0
                break
            end

            -- Cue ball hits obstacle/cushion/pocket within remaining distance
            local hitPos = cast.Ghost
            local isPocket = (cast.Kind == "Pocket")
            table.insert(segments, {
                from = currPos,
                to = hitPos,
                kind = cast.Kind,
                other = cast.Other,
                cushionId = cast.CushionId,
                pocketId = cast.PocketId,
                color = isPocket and Color3.fromRGB(255, 60, 60) or settings.cueDeflectColor
            })
            finalStopPos = hitPos
            remainingDist = remainingDist - hitDist

            if isPocket then
                reachedPocket = true
                break
            elseif cast.Kind == "Ball" or cast.Kind == "Tip" then
                break
            elseif cast.Kind == "Cushion" then
                local cushion = cushionsById[cast.CushionId]
                if not cushion then break end
                local reflected = computeCushionBounce(currDir, cushion.Normal)
                currPos = hitPos + reflected * 0.05
                currDir = reflected
                local restitution = (PoolConstants.Physics and PoolConstants.Physics.CushionRestitution) or 0.72
                remainingDist = remainingDist * restitution
            else
                break
            end
        end

        return segments, finalStopPos, reachedPocket
    end


    -- ============================================================
    --   LINE OF SIGHT & POCKET SOLVER
    -- ============================================================
    local function isPathClear(sim, fromPos, toPos, ignoreBall1, ignoreBall2)
        local dir = toPos - fromPos
        local dist = dir.Magnitude
        if dist < 0.001 then return true end
        local u = dir / dist

        -- Check other balls obstructing path
        for _, num in ipairs(sim.Order) do
            if num ~= ignoreBall1 and num ~= ignoreBall2 then
                local b = sim.Balls[num]
                if b and not b.Pocketed then
                    local v = b.Position - fromPos
                    local dot = v:Dot(u)
                    if dot > 0 and dot < dist then
                        local perp = math.abs(u.X * v.Y - u.Y * v.X)
                        if perp < BallDiameter then
                            return false
                        end
                    end
                end
            end
        end

        -- Check cushion obstruction
        local cast = PoolPhysics.CastCueBall(sim, u)
        if cast and cast.Distance and cast.Distance < (dist - 0.5) then
            return false
        end

        return true
    end

    -- Accurately determine legal balls based on player's assigned group (Solids vs Stripes vs 8-Ball)
    local function getLegalBalls(sim)
        local legal = {}

        -- 1. Primary method: activeInputController.IsLegalTarget
        if activeInputController and activeInputController.IsLegalTarget then
            for n = 1, 15 do
                local b = sim.Balls[n]
                if b and not b.Pocketed then
                    local ok, isLeg = pcall(function()
                        return activeInputController.IsLegalTarget(n)
                    end)
                    if ok and isLeg then
                        table.insert(legal, n)
                    end
                end
            end
            if #legal > 0 then
                return legal
            end
        end

        -- 2. Fallback: matchClient rules
        if activeMatchClient and type(activeMatchClient.Rules) == "table" then
            local rules = activeMatchClient.Rules
            for n = 1, 15 do
                local b = sim.Balls[n]
                if b and not b.Pocketed then
                    pcall(function()
                        if PoolRules.IsLegalFirstContact(rules, sim, n) then
                            table.insert(legal, n)
                        end
                    end)
                end
            end
            if #legal > 0 then
                return legal
            end
        end

        -- 3. UI Fallback: Read assigned group from HUD chips
        local myGroup = nil
        pcall(function()
            local p = localPlayer
            local pg = p and p:FindFirstChild("PlayerGui")
            local hud = pg and pg:FindFirstChild("PoolGameUI") and pg.PoolGameUI:FindFirstChild("Hud")
            if hud then
                local left = hud:FindFirstChild("LeftPlayer")
                local right = hud:FindFirstChild("RightPlayer")
                local myFrame = nil
                if left and left:FindFirstChild("PlayerName") and left.PlayerName.Text:find(p.Name) then
                    myFrame = left
                elseif right and right:FindFirstChild("PlayerName") and right.PlayerName.Text:find(p.Name) then
                    myFrame = right
                end
                if myFrame and myFrame:FindFirstChild("Chips") then
                    local chips = myFrame.Chips
                    if chips:FindFirstChild("Chip1") and chips.Chip1.Visible then
                        myGroup = "Solid"
                    elseif chips:FindFirstChild("Chip9") and chips.Chip9.Visible then
                        myGroup = "Stripe"
                    end
                end
            end
        end)

        if myGroup == "Solid" then
            local count = 0
            for n = 1, 7 do
                local b = sim.Balls[n]
                if b and not b.Pocketed then
                    table.insert(legal, n)
                    count = count + 1
                end
            end
            if count == 0 then
                local b8 = sim.Balls[8]
                if b8 and not b8.Pocketed then table.insert(legal, 8) end
            end
            return legal
        elseif myGroup == "Stripe" then
            local count = 0
            for n = 9, 15 do
                local b = sim.Balls[n]
                if b and not b.Pocketed then
                    table.insert(legal, n)
                    count = count + 1
                end
            end
            if count == 0 then
                local b8 = sim.Balls[8]
                if b8 and not b8.Pocketed then table.insert(legal, 8) end
            end
            return legal
        end

        -- 4. Open table fallback: balls 1..15 EXCEPT 8
        for n = 1, 15 do
            if n ~= 8 then
                local b = sim.Balls[n]
                if b and not b.Pocketed then
                    table.insert(legal, n)
                end
            end
        end
        return legal
    end

    -- Trajectory simplification helper (reduces straight segments to crisp key vertices)
    local function simplifyTrajectory(pts)
        if #pts <= 2 then return pts end
        local simplified = {pts[1]}
        for i = 2, #pts - 1 do
            local pPrev = simplified[#simplified]
            local pCurr = pts[i]
            local pNext = pts[i + 1]
            local v1 = (pCurr - pPrev)
            local v2 = (pNext - pCurr)
            if v1.Magnitude > 0.05 and v2.Magnitude > 0.05 then
                local dot = v1.Unit:Dot(v2.Unit)
                if dot < 0.998 then
                    table.insert(simplified, pCurr)
                end
            end
        end
        table.insert(simplified, pts[#pts])
        return simplified
    end

    -- Real-Physics Multi-Ball Engine Simulator
    -- Simulates every single ball on the table using the game's native PoolPhysics engine
    local function runFullPhysicsSimulation(sim, dir, power, spin)
        local simClone = PoolPhysics.Clone(sim)
        PoolPhysics.Shoot(simClone, dir, power, spin or Vector2.zero)

        local rawTrajs = {}
        local pocketed = {}
        local initialPos = {}

        for i = 0, 15 do
            local b = simClone.Balls[i]
            if b and not b.Pocketed then
                rawTrajs[i] = {b.Position}
                initialPos[i] = b.Position
            end
        end

        local steps = 0
        local maxSteps = 240
        local dt = 1/35

        while not simClone.Settled and steps < maxSteps do
            PoolPhysics.Step(simClone, dt)
            steps = steps + 1

            for i = 0, 15 do
                local b = simClone.Balls[i]
                if b then
                    if b.Pocketed and not pocketed[i] then
                        pocketed[i] = b.PocketId or "Pocket"
                    end
                    if not b.Pocketed and (steps % 2 == 0) then
                        local list = rawTrajs[i]
                        if list then
                            local last = list[#list]
                            if not last or (b.Position - last).Magnitude > 0.35 then
                                table.insert(list, b.Position)
                            end
                        end
                    end
                end
            end
        end

        local firstContact = nil
        for _, ev in ipairs(simClone.Events or {}) do
            if ev.Kind == "BallHit" then
                firstContact = (ev.Ball == 0 and ev.Other) or (ev.Other == 0 and ev.Ball) or ev.Other
                break
            end
        end

        local movingBalls = {}
        local trajectories = {}
        local finalPositions = {}

        for i = 0, 15 do
            local b = simClone.Balls[i]
            if b then
                finalPositions[i] = b.Position
                local list = rawTrajs[i]
                if list then
                    table.insert(list, b.Position)
                    local init = initialPos[i]
                    if (init and (b.Position - init).Magnitude > 0.45) or pocketed[i] then
                        table.insert(movingBalls, i)
                        trajectories[i] = simplifyTrajectory(list)
                    end
                end
            end
        end

        return {
            steps = steps,
            settled = simClone.Settled,
            cueScratch = (pocketed[0] ~= nil),
            pocketed = pocketed,
            firstContact = firstContact,
            movingBalls = movingBalls,
            trajectories = trajectories,
            finalPositions = finalPositions,
            events = simClone.Events or {}
        }
    end

    -- Calculate optimal power based on distance
    local function calculateOptimalPower(dist)
        if not settings.smartPower then
            return settings.shootPower
        end
        -- Distance ranges from ~10 to 80. Clamp between 0.35 and 0.85 for best stability.
        local normalized = math.clamp(dist / 65, 0.35, 0.85)
        return normalized
    end

    -- Scratch Verification Engine: Determines if any shot would pot or scratch the cue ball
    local function checkWillCueScratch(sim, aimDir, power, spin)
        local simResult = runFullPhysicsSimulation(sim, aimDir, power, spin)
        if simResult.cueScratch then
            return true
        end
        local finalCuePos = simResult.finalPositions[0]
        if finalCuePos then
            for _, p in ipairs(Pockets) do
                if (finalCuePos - p.MouthCentre).Magnitude < (BallDiameter * 1.1) then
                    return true
                end
            end
        end
        return false
    end

    -- Physics-Verified Multi-Tier Pocket & Safety Solver
    -- Guarantees: 1. Zero Cue Ball Scratching, 2. Bank shots if direct blocked, 3. Never goes silent
    local function findBestPocketShot(sim)
        local cue = sim.Balls[CueBallNumber]
        if not cue or cue.Pocketed then return nil end
        local cuePos = cue.Position

        local legalBalls = getLegalBalls(sim)
        if #legalBalls == 0 then return nil end

        -- Filter if specific ball selected
        if settings.aimTargetBall ~= "Auto Best" then
            local targetNum = tonumber(settings.aimTargetBall)
            if targetNum then
                legalBalls = {targetNum}
            end
        end

        local candidates = {}

        -- TIER 1: Direct Potting Shots
        if settings.shotPreference ~= "Bank Only (ฉิ่งเท่านั้น)" then
            for _, ballNum in ipairs(legalBalls) do
                local objBall = sim.Balls[ballNum]
                if objBall and not objBall.Pocketed then
                    local objPos = objBall.Position

                    for _, pocket in ipairs(Pockets) do
                        local toPocket = pocket.MouthCentre - objPos
                        local pocketDist = toPocket.Magnitude
                        if pocketDist > 0.1 then
                            local pocketDir = toPocket / pocketDist

                            -- Ghost ball center where cue ball must land
                            local contactPoint = objPos - pocketDir * BallDiameter
                            local toContact = contactPoint - cuePos
                            local contactDist = toContact.Magnitude

                            if contactDist > 0.1 then
                                local aimDir = toContact / contactDist
                                local cutAngleCos = aimDir:Dot(pocketDir)

                                -- Cut angle must be within reasonable forward angle (> 8 degrees angle)
                                if cutAngleCos > 0.14 then
                                    local cueClear = isPathClear(sim, cuePos, contactPoint, CueBallNumber, ballNum)
                                    local objClear = isPathClear(sim, objPos, pocket.MouthCentre, CueBallNumber, ballNum)

                                    if cueClear and objClear then
                                        local refinedAimDir = aimDir
                                        local optimalPower = calculateOptimalPower(contactDist + pocketDist)
                                        local verifiedPred = PoolPhysics.PredictShot(sim, refinedAimDir, optimalPower, Vector2.zero)

                                        if verifiedPred.Kind == "Ball" and verifiedPred.Other == ballNum and verifiedPred.ObjectDirection then
                                            local objActualDir = verifiedPred.ObjectDirection
                                            local alignmentDot = objActualDir:Dot(pocketDir)

                                            if alignmentDot > 0.94 then
                                                -- MANDATORY ZERO-SCRATCH CHECK
                                                local willScratch = checkWillCueScratch(sim, refinedAimDir, optimalPower, Vector2.zero)
                                                if not willScratch then
                                                    local distPenalty = (pocketDist * 0.45) + (contactDist * 0.25)
                                                    local baseDirectScore = (settings.shotPreference == "Prefer Bank (ฉิ่งลงหลุมก่อน)") and 400 or 500
                                                    local score = (cutAngleCos ^ 1.5) * 100 + (alignmentDot * 50) - distPenalty + baseDirectScore

                                                    table.insert(candidates, {
                                                        target = ballNum,
                                                        pocket = pocket.Id,
                                                        pocketPos = pocket.MouthCentre,
                                                        contactPoint = contactPoint,
                                                        aimDir = refinedAimDir,
                                                        cutAngleCos = cutAngleCos,
                                                        alignmentDot = alignmentDot,
                                                        score = score,
                                                        distance = contactDist + pocketDist,
                                                        power = optimalPower,
                                                        shotType = "Direct"
                                                    })
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
        end

        -- TIER 2: 1-Cushion Bank Potting Shots (Object ball banks off rail into pocket)
        if settings.shotPreference ~= "Direct Only (ยิงตรงเท่านั้น)" then
            local primaryRails = {
                { axis = "Y", val = 22, norm = Vector2.new(0, -1), minT = -40.8, maxT = 40.8, contactY = 22 - BallRadius },
                { axis = "Y", val = -22, norm = Vector2.new(0, 1), minT = -40.8, maxT = 40.8, contactY = -22 + BallRadius },
                { axis = "X", val = -44, norm = Vector2.new(1, 0), minT = -18.8, maxT = 18.8, contactX = -44 + BallRadius },
                { axis = "X", val = 44, norm = Vector2.new(-1, 0), minT = -18.8, maxT = 18.8, contactX = 44 - BallRadius },
            }

            for _, ballNum in ipairs(legalBalls) do
                local objBall = sim.Balls[ballNum]
                if objBall and not objBall.Pocketed then
                    local objPos = objBall.Position

                    for _, pocket in ipairs(Pockets) do
                        local pPos = pocket.MouthCentre
                        for _, rail in ipairs(primaryRails) do
                            local bouncePoint = nil
                            if rail.axis == "Y" then
                                local rY = rail.contactY
                                local mirrorY = 2 * rY - pPos.Y
                                local toMirror = Vector2.new(pPos.X, mirrorY) - objPos
                                if math.abs(toMirror.Y) > 0.1 then
                                    local t = (rY - objPos.Y) / toMirror.Y
                                    if t > 0.02 and t < 0.98 then
                                        local bX = objPos.X + t * toMirror.X
                                        if bX >= rail.minT and bX <= rail.maxT then
                                            bouncePoint = Vector2.new(bX, rY)
                                        end
                                    end
                                end
                            else
                                local rX = rail.contactX
                                local mirrorX = 2 * rX - pPos.X
                                local toMirror = Vector2.new(mirrorX, pPos.Y) - objPos
                                if math.abs(toMirror.X) > 0.1 then
                                    local t = (rX - objPos.X) / toMirror.X
                                    if t > 0.02 and t < 0.98 then
                                        local bY = objPos.Y + t * toMirror.Y
                                        if bY >= rail.minT and bY <= rail.maxT then
                                            bouncePoint = Vector2.new(rX, bY)
                                        end
                                    end
                                end
                            end

                            if bouncePoint then
                                local toBounce = (bouncePoint - objPos)
                                local bounceDist = toBounce.Magnitude
                                if bounceDist > 0.5 then
                                    local objTravelDir = toBounce / bounceDist
                                    local contactPoint = objPos - objTravelDir * BallDiameter
                                    local toContact = contactPoint - cuePos
                                    local contactDist = toContact.Magnitude

                                    if contactDist > 0.5 then
                                        local aimDir = toContact / contactDist
                                        local cutCos = aimDir:Dot(objTravelDir)
                                        if cutCos > 0.10 then
                                            local cueClear = isPathClear(sim, cuePos, contactPoint, CueBallNumber, ballNum)
                                            local objClear = isPathClear(sim, objPos, bouncePoint, CueBallNumber, ballNum)
                                            if cueClear and objClear then
                                                local baseAngle = math.atan2(aimDir.Y, aimDir.X)
                                                local bankPower = math.clamp(calculateOptimalPower(contactDist + bounceDist + 22) + 0.12, 0.50, 0.90)

                                                -- Physics Angle Sweep: Sweeps +-4.5 deg to account for rail friction & restitution
                                                for _, dDeg in ipairs({0, -1.5, 1.5, -3, 3, -4.5, 4.5}) do
                                                    local rad = baseAngle + math.rad(dDeg)
                                                    local testAimDir = Vector2.new(math.cos(rad), math.sin(rad))
                                                    local pred = PoolPhysics.PredictShot(sim, testAimDir, bankPower, Vector2.zero)
                                                    if pred.Kind == "Ball" and pred.Other == ballNum then
                                                        local simRes = runFullPhysicsSimulation(sim, testAimDir, bankPower, Vector2.zero)
                                                        if simRes.pocketed[ballNum] and not simRes.cueScratch then
                                                            local hitCushion = false
                                                            for _, ev in ipairs(simRes.events or {}) do
                                                                local evBall = (type(ev.Ball) == "table" and ev.Ball.Number) or ev.Ball
                                                                if ev.Kind == "CushionHit" and evBall == ballNum then
                                                                    hitCushion = true
                                                                    break
                                                                end
                                                            end

                                                            local bankBonus = (settings.shotPreference == "Prefer Bank (ฉิ่งลงหลุมก่อน)") and 1500 or 520
                                                            table.insert(candidates, {
                                                                target = ballNum,
                                                                pocket = simRes.pocketed[ballNum],
                                                                pocketPos = pocket.MouthCentre,
                                                                contactPoint = contactPoint,
                                                                aimDir = testAimDir,
                                                                score = bankBonus + (cutCos * 60) - (contactDist * 0.2),
                                                                distance = contactDist + bounceDist,
                                                                power = bankPower,
                                                                shotType = hitCushion and "Bank" or "Direct"
                                                            })
                                                            break
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
                end
            end
        end

        -- If potting candidates found, sort and return top choice
        if #candidates > 0 then
            table.sort(candidates, function(a, b) return a.score > b.score end)
            return candidates[1]
        end

        -- TIER 3: Safety / Clean Legal Hit Fallback (Guaranteed Hit, No Silence, Zero Scratch!)
        -- If no ball can be potted, hit the cleanest legal ball to avoid a foul
        local safetyCandidates = {}
        for _, ballNum in ipairs(legalBalls) do
            local objBall = sim.Balls[ballNum]
            if objBall and not objBall.Pocketed then
                local objPos = objBall.Position
                local toBall = objPos - cuePos
                local dist = toBall.Magnitude
                if dist > 0.1 then
                    local directDir = toBall / dist
                    local safePower = 0.45
                    local pred = PoolPhysics.PredictShot(sim, directDir, safePower, Vector2.zero)
                    if pred.Kind == "Ball" and pred.Other == ballNum then
                        local willScratch = checkWillCueScratch(sim, directDir, safePower, Vector2.zero)
                        if not willScratch then
                            table.insert(safetyCandidates, {
                                target = ballNum,
                                aimDir = directDir,
                                distance = dist,
                                power = safePower,
                                score = 100 - dist,
                                shotType = "SafetyDirect"
                            })
                        end
                    end
                end
            end
        end

        -- If direct safety hits are all snookered, kick off rail to hit legal ball
        if #safetyCandidates == 0 then
            for _, ballNum in ipairs(legalBalls) do
                local objBall = sim.Balls[ballNum]
                if objBall and not objBall.Pocketed then
                    for _, rail in ipairs(primaryRails) do
                        local mirrorObj = nil
                        if rail.axis == "Y" then
                            mirrorObj = Vector2.new(objBall.Position.X, 2 * rail.val - objBall.Position.Y)
                        else
                            mirrorObj = Vector2.new(2 * rail.val - objBall.Position.X, objBall.Position.Y)
                        end
                        local toMirror = mirrorObj - cuePos
                        local kickDir = toMirror.Unit
                        local kickPower = 0.50
                        local pred = PoolPhysics.PredictShot(sim, kickDir, kickPower, Vector2.zero)
                        if pred.Kind == "Cushion" then
                            local simClone = PoolPhysics.Clone(sim)
                            local segs, finalHit = traceCueBallRay(simClone, cuePos, kickDir, 3)
                            if finalHit and finalHit.Kind == "Ball" and finalHit.Other == ballNum then
                                local willScratch = checkWillCueScratch(sim, kickDir, kickPower, Vector2.zero)
                                if not willScratch then
                                    table.insert(safetyCandidates, {
                                        target = ballNum,
                                        aimDir = kickDir,
                                        distance = toMirror.Magnitude,
                                        power = kickPower,
                                        score = 50 - toMirror.Magnitude,
                                        shotType = "SafetyKick"
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end

        if #safetyCandidates > 0 then
            table.sort(safetyCandidates, function(a, b) return a.score > b.score end)
            return safetyCandidates[1]
        end

        -- Absolute emergency fallback: Aim directly at closest legal ball
        local closestBall = nil
        local closestDist = math.huge
        for _, ballNum in ipairs(legalBalls) do
            local b = sim.Balls[ballNum]
            if b and not b.Pocketed then
                local d = (b.Position - cuePos).Magnitude
                if d < closestDist then
                    closestDist = d
                    closestBall = ballNum
                end
            end
        end

        if closestBall then
            local b = sim.Balls[closestBall]
            return {
                target = closestBall,
                aimDir = (b.Position - cuePos).Unit,
                distance = closestDist,
                power = 0.40,
                score = 10,
                shotType = "EmergencyFallback"
            }
        end

        return nil
    end

    -- Smooth Human-like Aim Controller
    local isSmoothAiming = false
    local smoothAimThread = nil

    local function slerpDirection(v1, v2, t)
        local dot = math.clamp(v1:Dot(v2), -1, 1)
        if dot > 0.9999 then
            return v2
        end
        local theta = math.acos(dot) * t
        local perp = (v2 - v1 * dot)
        if perp.Magnitude < 0.0001 then return v2 end
        perp = perp.Unit
        return (v1 * math.cos(theta) + perp * math.sin(theta)).Unit
    end

    -- Execute Auto Aim / Shoot (Human-like Smooth Glide & Micro Overshoot)
    local function executeAutoAim(shouldShoot)
        if not activeInputController then return false end
        local sim = activeSimulation or (activeMatchClient and activeMatchClient.Simulation)
        if not sim then return false end

        local bestShot = findBestPocketShot(sim)
        if not bestShot then return false end

        local targetDir = bestShot.aimDir
        local power = bestShot.power or calculateOptimalPower(bestShot.distance)

        -- If Smooth Aim is disabled, snap directly
        if not settings.smoothAim then
            activeInputController.Direction = targetDir
            activeInputController.AimLocked = settings.lockAimOnTarget
            activeInputController.AimAnchor = nil
            activeInputController.Power = power

            if activeInputController.Hud then
                pcall(function()
                    local PoolHudRenderer = require(Pool.PoolHudRenderer)
                    PoolHudRenderer.SetPower(activeInputController.Hud, power)
                end)
            end

            if shouldShoot and activeInputController.ShotBindable then
                local spin = (activeInputController.Hud and activeInputController.Hud.Spin) or Vector2.zero
                pcall(function()
                    activeInputController.ShotBindable:Fire(targetDir, power, spin)
                end)
                activeInputController.AimLocked = false
            else
                if settings.lockAimOnTarget then
                    notify("Aim Assist", "Target Locked! Right-Click to unlock 🔒")
                end
            end
            return true
        end

        -- Human-like Smooth Glide Animation
        if isSmoothAiming and smoothAimThread then
            task.cancel(smoothAimThread)
            isSmoothAiming = false
        end

        smoothAimThread = task.spawn(function()
            isSmoothAiming = true
            local currentDir = activeInputController.Direction and activeInputController.Direction.Unit or targetDir

            -- 1. Calculate natural angle difference
            local startDot = math.clamp(currentDir:Dot(targetDir), -1, 1)
            local angleDist = math.acos(startDot) -- radians

            -- Natural duration scaled by angle: ~0.15s to 0.40s
            local baseDuration = math.clamp(angleDist * 0.35, 0.14, 0.42)
            local elapsed = 0

            -- Micro human overshoot target (slight 0.3 degree natural drift before settling)
            local overshootDir = targetDir
            if settings.aimHumanOvershoot and angleDist > 0.08 then
                local perp = Vector2.new(-targetDir.Y, targetDir.X)
                local jitterSign = (math.random() > 0.5 and 1 or -1)
                overshootDir = (targetDir + perp * (jitterSign * 0.012)).Unit
            end

            -- Phase 1: Fast glide towards overshoot / target with smooth ease-out
            while elapsed < baseDuration and running do
                local dt = task.wait()
                elapsed = elapsed + dt
                local progress = math.clamp(elapsed / baseDuration, 0, 1)
                -- Cubic Ease-Out curve (fast start, gradual deceleration like human hand)
                local easeOut = 1 - (1 - progress) ^ 3
                local interpolated = slerpDirection(currentDir, overshootDir, easeOut)

                activeInputController.Direction = interpolated
                activeInputController.AimLocked = true
            end

            -- Phase 2: Micro settling to exact dead-center (0.05s human micro-correction)
            if settings.aimHumanOvershoot and overshootDir ~= targetDir and running then
                local microElapsed = 0
                local microDuration = 0.08
                local fromOver = activeInputController.Direction.Unit
                while microElapsed < microDuration and running do
                    local dt = task.wait()
                    microElapsed = microElapsed + dt
                    local p = math.clamp(microElapsed / microDuration, 0, 1)
                    local ease = 1 - (1 - p) ^ 2
                    activeInputController.Direction = slerpDirection(fromOver, targetDir, ease)
                    activeInputController.AimLocked = true
                end
            end

            activeInputController.Direction = targetDir
            activeInputController.AimLocked = settings.lockAimOnTarget
            activeInputController.AimAnchor = nil
            activeInputController.Power = power

            if activeInputController.Hud then
                pcall(function()
                    local PoolHudRenderer = require(Pool.PoolHudRenderer)
                    PoolHudRenderer.SetPower(activeInputController.Hud, power)
                end)
            end

            isSmoothAiming = false

            -- If Auto Shoot was triggered, add a human reaction delay (0.08s - 0.15s) before pulling cue
            if shouldShoot and running and activeInputController.ShotBindable then
                task.wait(math.random(8, 14) / 100)
                local spin = (activeInputController.Hud and activeInputController.Hud.Spin) or Vector2.zero
                pcall(function()
                    activeInputController.ShotBindable:Fire(targetDir, power, spin)
                end)
                activeInputController.AimLocked = false
            else
                if settings.lockAimOnTarget then
                    notify("Aim Assist", "Target Locked! Right-Click to unlock 🔒")
                end
            end
        end)

        return true
    end

    -- ============================================================
    --   INPUT LISTENERS
    -- ============================================================
    connect(UserInputService.InputBegan, function(input, gameProcessed)
        -- Right Click immediately releases Aim Lock and restores manual aiming
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            if activeInputController and activeInputController.AimLocked then
                activeInputController.AimLocked = false
                activeInputController.AimAnchor = nil
                notify("Aim Assist", "Aim Lock Released 🔓")
            end
            return
        end

        -- If player clicks or touches screen while smooth aim is animating, yield smooth aim
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if isSmoothAiming and smoothAimThread then
                task.cancel(smoothAimThread)
                isSmoothAiming = false
            end
        end

        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode[settings.autoAimKey] then
            if settings.autoAim then
                executeAutoAim(settings.autoShoot)
            end
        end
    end)

    -- ============================================================
    --   TRAJECTORY ENGINE LOOP
    -- ============================================================
    connect(RunService.RenderStepped, function()
        if not running then return end

        -- Constantly suppress default game short white/yellow lines if enabled
        suppressNativeLines()

        if not settings.extendedLines then
            hideAllCustomDrawings()
            return
        end

        local input, sim = resolveActiveControllers()
        if not input or not sim or not input.Direction or input.Direction.Magnitude < 0.0001 then
            hideAllCustomDrawings()
            return
        end

        local cue = sim.Balls and sim.Balls[CueBallNumber]
        if not cue or cue.Pocketed then
            hideAllCustomDrawings()
            return
        end

        local cuePos = cue.Position
        local cueDir = input.Direction.Unit

        local currentPower = (input.Power and input.Power > 0.01) and input.Power or settings.shootPower
        local spin = (input.Hud and input.Hud.Spin) or Vector2.zero
        local lineIdx = 0
        local markerIdx = 0

        if settings.fullPhysicsSimulation then
            -- FULL NATIVE PHYSICS SIMULATION (Every single ball on the table)
            local simResult = runFullPhysicsSimulation(sim, cueDir, currentPower, spin)

            -- 1. Render Cue Ball Trajectory (Ball 0)
            local cueTraj = simResult.trajectories[0]
            if cueTraj and #cueTraj >= 2 then
                for idx = 1, #cueTraj - 1 do
                    lineIdx = lineIdx + 1
                    local lineObj = getOrCreateLine(lineIdx)
                    if lineObj then
                        setTableLine(lineObj, cueTraj[idx], cueTraj[idx + 1], settings.lineThickness, settings.cueColor)
                    end
                end
            end

            -- Cue Ball Stop Marker or Scratch Marker
            if simResult.cueScratch then
                markerIdx = markerIdx + 1
                local sMarker = getOrCreateMarker(markerIdx)
                if sMarker then
                    local pPos = nil
                    for _, p in ipairs(Pockets) do
                        if p.Id == simResult.pocketed[0] then pPos = p.MouthCentre break end
                    end
                    setTableMarker(sMarker, pPos or cuePos, BallDiameter * 1.35, Color3.fromRGB(255, 30, 30))
                end
            elseif settings.showCueRestPosition and simResult.finalPositions[0] then
                markerIdx = markerIdx + 1
                local restMarker = getOrCreateMarker(markerIdx)
                if restMarker then
                    setTableMarker(restMarker, simResult.finalPositions[0], BallDiameter, settings.cueColor)
                end
            end

            -- 2. Render ALL Moving Object Balls (Balls 1 to 15)
            for _, ballNum in ipairs(simResult.movingBalls) do
                if ballNum ~= 0 then
                    local objTraj = simResult.trajectories[ballNum]
                    local ballColor = settings.objectColor
                    if ballNum == 8 then
                        ballColor = Color3.fromRGB(240, 200, 50) -- Gold for 8-ball
                    elseif ballNum > 8 then
                        ballColor = settings.comboColor or Color3.fromRGB(255, 185, 45) -- Stripes / secondary
                    end

                    if objTraj and #objTraj >= 2 then
                        for idx = 1, #objTraj - 1 do
                            lineIdx = lineIdx + 1
                            local lineObj = getOrCreateLine(lineIdx)
                            if lineObj then
                                setTableLine(lineObj, objTraj[idx], objTraj[idx + 1], settings.lineThickness * 0.9, ballColor)
                            end
                        end
                    end

                    -- If pocketed, highlight pocket; if stopped on felt, draw ghost ball
                    if simResult.pocketed[ballNum] then
                        markerIdx = markerIdx + 1
                        local pMarker = getOrCreateMarker(markerIdx)
                        if pMarker then
                            local pPos = nil
                            for _, p in ipairs(Pockets) do
                                if p.Id == simResult.pocketed[ballNum] then pPos = p.MouthCentre break end
                            end
                            setTableMarker(pMarker, pPos or (objTraj and objTraj[#objTraj]) or simResult.finalPositions[ballNum], BallDiameter * 1.3, settings.pocketTargetColor)
                        end
                    elseif settings.showRestingGhostBalls and simResult.finalPositions[ballNum] then
                        markerIdx = markerIdx + 1
                        local ghostObjMarker = getOrCreateMarker(markerIdx)
                        if ghostObjMarker then
                            setTableMarker(ghostObjMarker, simResult.finalPositions[ballNum], BallDiameter, ballColor)
                        end
                    end
                end
            end
        else
            -- Fallback simplified raycast mode
            local simClone = PoolPhysics.Clone(sim)
            local cueSegs, finalHit = traceCueBallRay(simClone, cuePos, cueDir, settings.maxBounces)

            for _, seg in ipairs(cueSegs) do
                lineIdx = lineIdx + 1
                local lineObj = getOrCreateLine(lineIdx)
                if lineObj then
                    setTableLine(lineObj, seg.from, seg.to, settings.lineThickness, seg.color)
                end
                if seg.kind == "Cushion" then
                    markerIdx = markerIdx + 1
                    local mObj = getOrCreateMarker(markerIdx)
                    if mObj then
                        setTableMarker(mObj, seg.to, BallDiameter * 0.85, settings.cushionBounceColor)
                    end
                end
            end

            if settings.showObjectBounce and finalHit and finalHit.Kind == "Ball" and finalHit.Other then
                local objNum = finalHit.Other
                local hitBall = sim.Balls[objNum]
                if hitBall and not hitBall.Pocketed then
                    local ghostPos = finalHit.Ghost
                    local objDir = finalHit.ObjectDirection or (hitBall.Position - ghostPos).Unit

                    if settings.showCollisionRing then
                        markerIdx = markerIdx + 1
                        local ghostMarker = getOrCreateMarker(markerIdx)
                        if ghostMarker then
                            setTableMarker(ghostMarker, ghostPos, BallDiameter, settings.cueColor)
                        end
                    end

                    local objStartPos = ghostPos + objDir * BallDiameter
                    local objSegs = traceObjectBallRay(simClone, objStartPos, objDir, settings.objectBounces, objNum)

                    for _, oSeg in ipairs(objSegs) do
                        lineIdx = lineIdx + 1
                        local oLine = getOrCreateLine(lineIdx)
                        if oLine then
                            setTableLine(oLine, oSeg.from, oSeg.to, settings.lineThickness, oSeg.color)
                        end

                        if oSeg.kind == "Pocket" and settings.showPocketLanding then
                            markerIdx = markerIdx + 1
                            local pMarker = getOrCreateMarker(markerIdx)
                            if pMarker then
                                setTableMarker(pMarker, oSeg.to, BallDiameter * 1.2, settings.pocketTargetColor)
                            end
                        elseif oSeg.kind == "Cushion" then
                            markerIdx = markerIdx + 1
                            local bMarker = getOrCreateMarker(markerIdx)
                            if bMarker then
                                setTableMarker(bMarker, oSeg.to, BallDiameter * 0.75, settings.cushionBounceColor)
                            end
                        end
                    end

                    if settings.showCueDeflection then
                        local verifiedPred = PoolPhysics.PredictShot(simClone, cueDir, currentPower, spin)
                        local cueDeflectDir = (verifiedPred and verifiedPred.CueDirection) or finalHit.CueDirection
                        local cueMaxDist = (verifiedPred and verifiedPred.CueDistance)

                        if not cueDeflectDir then
                            local impactNormal = (hitBall.Position - ghostPos).Unit
                            local tangent = Vector2.new(-impactNormal.Y, impactNormal.X)
                            if tangent:Dot(cueDir) < 0 then tangent = -tangent end
                            cueDeflectDir = tangent
                        end

                        if not cueMaxDist or cueMaxDist <= 0.01 then
                            local shotSpeed = PoolPhysics.GetShotSpeed(simClone, currentPower)
                            cueMaxDist = PoolPhysics.RollDistance(shotSpeed * 0.4)
                        end

                        if cueDeflectDir and cueDeflectDir.Magnitude > 0.001 then
                            local cueDeflectStart = ghostPos + cueDeflectDir.Unit * (BallDiameter * 0.5)
                            local cueDeflectSegs, cueFinalStopPos, reachedPocket = traceCueDeflectionRay(simClone, cueDeflectStart, cueDeflectDir, cueMaxDist, settings.cueDeflectionBounces)

                            for _, cSeg in ipairs(cueDeflectSegs) do
                                lineIdx = lineIdx + 1
                                local cLine = getOrCreateLine(lineIdx)
                                if cLine then
                                    setTableLine(cLine, cSeg.from, cSeg.to, settings.lineThickness * 0.85, cSeg.color)
                                end
                                if cSeg.kind == "Pocket" then
                                    markerIdx = markerIdx + 1
                                    local sMarker = getOrCreateMarker(markerIdx)
                                    if sMarker then setTableMarker(sMarker, cSeg.to, BallDiameter * 1.3, Color3.fromRGB(255, 30, 30)) end
                                elseif cSeg.kind == "Cushion" then
                                    markerIdx = markerIdx + 1
                                    local cbMarker = getOrCreateMarker(markerIdx)
                                    if cbMarker then setTableMarker(cbMarker, cSeg.to, BallDiameter * 0.7, settings.cueDeflectColor) end
                                end
                            end

                            if cueFinalStopPos and not reachedPocket and settings.showCueRestPosition then
                                markerIdx = markerIdx + 1
                                local restMarker = getOrCreateMarker(markerIdx)
                                if restMarker then
                                    setTableMarker(restMarker, cueFinalStopPos, BallDiameter, settings.cueDeflectColor)
                                end
                            end
                        end
                    end
                end
            end

            if (not finalHit or finalHit.Kind ~= "Ball") and settings.showCueRestPosition then
                local shotSpeed = PoolPhysics.GetShotSpeed(simClone, currentPower)
                local totalRoll = PoolPhysics.RollDistance(shotSpeed)
                local walked = 0
                local stopPoint = nil
                for _, seg in ipairs(cueSegs) do
                    local segLen = (seg.to - seg.from).Magnitude
                    if (walked + segLen) >= totalRoll then
                        local rem = totalRoll - walked
                        stopPoint = seg.from + (seg.to - seg.from).Unit * rem
                        break
                    else
                        walked = walked + segLen
                        stopPoint = seg.to
                    end
                end
                if stopPoint then
                    markerIdx = markerIdx + 1
                    local restMarker = getOrCreateMarker(markerIdx)
                    if restMarker then
                        setTableMarker(restMarker, stopPoint, BallDiameter, settings.cueColor)
                    end
                end
            end
        end

        -- Hide leftover unused drawing objects
        for i = lineIdx + 1, #customLinePool do
            if customLinePool[i] and customLinePool[i].Visible then
                customLinePool[i].Visible = false
            end
        end
        for i = markerIdx + 1, #customMarkerPool do
            if customMarkerPool[i] and customMarkerPool[i].Visible then
                customMarkerPool[i].Visible = false
            end
        end
    end)

    -- ============================================================
    --   USER INTERFACE (RAVEN HUB MACLIB / DRAWING UI)
    -- ============================================================

    -- Tab 0: Overview
    local HomeTab = (type(Window.GetTab) == "function" and Window:GetTab("Overview"))
    if not HomeTab and type(Window.CreateTab) == "function" then
        HomeTab = Window:CreateTab("Overview", "overview")
        HomeTab:CreateSection("Experience & Security")
        HomeTab:CreateLabel("Experience: [GALAXY] 8 Ball Duels")
        HomeTab:CreateLabel("PlaceId: " .. tostring(game.PlaceId))
        HomeTab:CreateLabel("Physics Engine: Multi-Bounce Raycast Extended")
        HomeTab:CreateLabel("Active Module: 8 Ball Duels [v1.0.0]")
        HomeTab:CreateLabel("Status: Active & Operational")
        HomeTab:CreateSection("Feature Summary")
        HomeTab:CreateParagraph({
            Title = "Active Features",
            Content = "Infinite Guideline, Multi-Cushion Reflection, Ghost Ball Indicator, Pocket Landing Predictor, Auto Aim & Max Cue Stats.",
        })
    end

    -- Tab 1: Guidelines & Trajectory
    local GuideTab = Window:CreateTab("Guidelines", "visuals")
    GuideTab:CreateSection("Multi-Bounce Trajectory Engine")

    GuideTab:CreateToggle({
        Name = "Hide Default Game Guidelines",
        CurrentValue = settings.hideDefaultLines,
        Flag = "BD_HideDefaultLines",
        Callback = function(val)
            settings.hideDefaultLines = val
            if not val then
                local overlay = getAimOverlayFrame()
                if overlay then
                    for _, name in ipairs({"AimLine", "ObjectLine", "CueLine", "Ghost"}) do
                        local obj = overlay:FindFirstChild(name)
                        if obj then
                            obj.Visible = true
                            if obj:IsA("GuiObject") then obj.BackgroundTransparency = 0 end
                            if obj:IsA("ImageLabel") then obj.ImageTransparency = 0 end
                        end
                    end
                end
            end
        end,
    })

    GuideTab:CreateToggle({
        Name = "Extended Multi-Bounce Lines",
        CurrentValue = settings.extendedLines,
        Flag = "BD_ExtendedLines",
        Callback = function(val)
            settings.extendedLines = val
            applyConstants()
            if not val then hideAllCustomDrawings() end
        end,
    })

    GuideTab:CreateToggle({
        Name = "Real Engine Physics (All Balls)",
        CurrentValue = settings.fullPhysicsSimulation,
        Flag = "BD_FullPhysics",
        Callback = function(val)
            settings.fullPhysicsSimulation = val
        end,
    })

    GuideTab:CreateToggle({
        Name = "Show All Moving Balls Trajectories",
        CurrentValue = settings.showAllMovingBalls,
        Flag = "BD_ShowAllMoving",
        Callback = function(val)
            settings.showAllMovingBalls = val
        end,
    })

    GuideTab:CreateToggle({
        Name = "Show All Balls Resting Ghost Position",
        CurrentValue = settings.showRestingGhostBalls,
        Flag = "BD_ShowAllResting",
        Callback = function(val)
            settings.showRestingGhostBalls = val
        end,
    })

    GuideTab:CreateSlider({
        Name = "Max Cue Cushion Bounces",
        Range = {1, 6},
        Increment = 1,
        CurrentValue = settings.maxBounces,
        Flag = "BD_MaxBounces",
        Callback = function(val)
            settings.maxBounces = math.floor(val)
            applyConstants()
        end,
    })

    GuideTab:CreateToggle({
        Name = "Predict Target Ball Bank (Object Bounce)",
        CurrentValue = settings.showObjectBounce,
        Flag = "BD_ObjectBounce",
        Callback = function(val)
            settings.showObjectBounce = val
        end,
    })

    GuideTab:CreateSlider({
        Name = "Max Object Ball Bounces",
        Range = {1, 4},
        Increment = 1,
        CurrentValue = settings.objectBounces,
        Flag = "BD_ObjBounces",
        Callback = function(val)
            settings.objectBounces = math.floor(val)
        end,
    })

    GuideTab:CreateSection("Visual Enhancements")

    GuideTab:CreateToggle({
        Name = "Show Ghost Ball (Impact Ring)",
        CurrentValue = settings.showCollisionRing,
        Flag = "BD_CollisionRing",
        Callback = function(val)
            settings.showCollisionRing = val
            applyConstants()
        end,
    })

    GuideTab:CreateToggle({
        Name = "Highlight Target Pocket",
        CurrentValue = settings.showPocketLanding,
        Flag = "BD_PocketLanding",
        Callback = function(val)
            settings.showPocketLanding = val
        end,
    })

    GuideTab:CreateToggle({
        Name = "Show Cue Ball Path (Deflection)",
        CurrentValue = settings.showCueDeflection,
        Flag = "BD_CueDeflect",
        Callback = function(val)
            settings.showCueDeflection = val
        end,
    })

    GuideTab:CreateToggle({
        Name = "Show Cue Ball Stop Position (Physics Rest)",
        CurrentValue = settings.showCueRestPosition,
        Flag = "BD_CueRestPos",
        Callback = function(val)
            settings.showCueRestPosition = val
        end,
    })

    GuideTab:CreateSlider({
        Name = "Max Cue Deflection Bounces",
        Range = {1, 4},
        Increment = 1,
        CurrentValue = settings.cueDeflectionBounces,
        Flag = "BD_CueDeflectBounces",
        Callback = function(val)
            settings.cueDeflectionBounces = math.floor(val)
        end,
    })

    GuideTab:CreateSlider({
        Name = "Line Thickness",
        Range = {0.3, 1.2},
        Increment = 0.05,
        CurrentValue = settings.lineThickness,
        Flag = "BD_Thickness",
        Callback = function(val)
            settings.lineThickness = val
        end,
    })

    -- Tab 2: Aim Assist & Pocket Solver
    local AimTab = Window:CreateTab("Aim Assist", "combat")
    AimTab:CreateSection("Auto Aim & Pocket Solver")

    AimTab:CreateToggle({
        Name = "Auto Aim on Keybind",
        CurrentValue = settings.autoAim,
        Flag = "BD_AutoAim",
        Callback = function(val)
            settings.autoAim = val
        end,
    })

    AimTab:CreateDropdown({
        Name = "Shot Strategy (สไตล์การเล็ง)",
        Options = {
            "Prefer Bank (ฉิ่งลงหลุมก่อน)",
            "Smart Balanced (คำนวณตามความง่าย)",
            "Bank Only (ฉิ่งเท่านั้น)",
            "Direct Only (ยิงตรงเท่านั้น)"
        },
        CurrentOption = settings.shotPreference,
        Flag = "BD_ShotPreference",
        Callback = function(val)
            settings.shotPreference = val
        end,
    })

    AimTab:CreateToggle({
        Name = "Smooth Human-like Aim (Legit)",
        CurrentValue = settings.smoothAim,
        Flag = "BD_SmoothAim",
        Callback = function(val)
            settings.smoothAim = val
        end,
    })

    AimTab:CreateToggle({
        Name = "Human Micro Overshoot / Jitter",
        CurrentValue = settings.aimHumanOvershoot,
        Flag = "BD_AimOvershoot",
        Callback = function(val)
            settings.aimHumanOvershoot = val
        end,
    })

    AimTab:CreateDropdown({
        Name = "Aim Keybind",
        Options = {"E", "Q", "F", "R", "X", "C"},
        CurrentOption = settings.autoAimKey,
        Flag = "BD_AimKey",
        Callback = function(val)
            settings.autoAimKey = val
        end,
    })

    AimTab:CreateToggle({
        Name = "Auto Shoot on Keybind",
        CurrentValue = settings.autoShoot,
        Flag = "BD_AutoShoot",
        Callback = function(val)
            settings.autoShoot = val
        end,
    })

    AimTab:CreateToggle({
        Name = "Lock Aim Angle (No Mouse Drag-Back)",
        CurrentValue = settings.lockAimOnTarget,
        Flag = "BD_LockAim",
        Callback = function(val)
            settings.lockAimOnTarget = val
            if not val and activeInputController then
                activeInputController.AimLocked = false
                activeInputController.AimAnchor = nil
            end
        end,
    })

    AimTab:CreateButton({
        Name = "Release Aim Lock (Or Right-Click) 🔓",
        Callback = function()
            if activeInputController then
                activeInputController.AimLocked = false
                activeInputController.AimAnchor = nil
                notify("Aim Assist", "Aim Lock Released 🔓")
            end
        end,
    })

    AimTab:CreateToggle({
        Name = "Smart Power (Distance Scaled)",
        CurrentValue = settings.smartPower,
        Flag = "BD_SmartPower",
        Callback = function(val)
            settings.smartPower = val
        end,
    })

    AimTab:CreateSlider({
        Name = "Fixed Power Value",
        Range = {0.1, 1.0},
        Increment = 0.05,
        CurrentValue = settings.shootPower,
        Flag = "BD_ShootPower",
        Callback = function(val)
            settings.shootPower = val
        end,
    })

    AimTab:CreateButton({
        Name = "Snap Aim to Best Pocket (Now)",
        Callback = function()
            local success = executeAutoAim(false)
            if not success then
                warn("[8 Ball Duels] No clear pocket shot found or table not in aim mode.")
            end
        end,
    })

    AimTab:CreateButton({
        Name = "Instant Shot (Aim & Fire Best)",
        Callback = function()
            local success = executeAutoAim(true)
            if not success then
                warn("[8 Ball Duels] Cannot fire: No shot available.")
            end
        end,
    })

    -- Tab 3: Cue Sticks Modifier
    local CueTab = Window:CreateTab("Cue Mod", "misc")
    CueTab:CreateSection("God Cue Stats Modifier")

    CueTab:CreateToggle({
        Name = "Enable God Cue Stats",
        CurrentValue = settings.godCueStats,
        Flag = "BD_GodCue",
        Callback = function(val)
            settings.godCueStats = val
            applyCueStats()
        end,
    })

    CueTab:CreateSlider({
        Name = "Cue Aim Stat",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = settings.aimMultiplier,
        Flag = "BD_AimStat",
        Callback = function(val)
            settings.aimMultiplier = val
            applyCueStats()
        end,
    })

    CueTab:CreateSlider({
        Name = "Cue Force Stat",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = settings.forceMultiplier,
        Flag = "BD_ForceStat",
        Callback = function(val)
            settings.forceMultiplier = val
            applyCueStats()
        end,
    })

    CueTab:CreateSlider({
        Name = "Cue Spin Stat",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = settings.spinMultiplier,
        Flag = "BD_SpinStat",
        Callback = function(val)
            settings.spinMultiplier = val
            applyCueStats()
        end,
    })

    CueTab:CreateSlider({
        Name = "Cue Time Stat",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = settings.timeMultiplier,
        Flag = "BD_TimeStat",
        Callback = function(val)
            settings.timeMultiplier = val
            applyCueStats()
        end,
    })

    -- Tab 4: Match Automation
    local MatchTab = Window:CreateTab("Automation", "settings")
    MatchTab:CreateSection("Break Shot & Match Flow")

    MatchTab:CreateButton({
        Name = "Execute Optimal Break Shot",
        Callback = function()
            if not activeInputController then return end
            local sim = activeSimulation or (activeMatchClient and activeMatchClient.Simulation)
            if not sim then return end

            local cue = sim.Balls[CueBallNumber]
            local apex = sim.Balls[1]
            if cue and apex then
                local breakDir = (apex.Position - cue.Position).Unit
                activeInputController.Direction = breakDir
                activeInputController.Power = settings.breakPower
                if activeInputController.ShotBindable then
                    activeInputController.ShotBindable:Fire(breakDir, settings.breakPower, Vector2.zero)
                end
            end
        end,
    })

    -- Cleanup Lifecycle
    local moduleInstance = {
        executeAutoAim = executeAutoAim,
        findBestPocketShot = findBestPocketShot,
        Destroy = function()
            running = false
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            hideAllCustomDrawings()
            for _, l in pairs(customLinePool) do
                pcall(function() l:Destroy() end)
            end
            for _, m in pairs(customMarkerPool) do
                pcall(function() m:Destroy() end)
            end
            PoolMatchClient.new = origMatchClientNew
            PoolAimOverlay.Update = origAimOverlayUpdate
            pcall(function()
                local overlay = getAimOverlayFrame()
                if overlay then
                    for _, name in ipairs({"AimLine", "ObjectLine", "CueLine", "Ghost"}) do
                        local obj = overlay:FindFirstChild(name)
                        if obj then
                            obj.Visible = true
                            if obj:IsA("GuiObject") then obj.BackgroundTransparency = 0 end
                            if obj:IsA("ImageLabel") then obj.ImageTransparency = 0 end
                        end
                    end
                end
            end)
            PoolConstants.BasePredictionLength = origBasePrediction
            PoolConstants.MaxPredictionBounces = origMaxBounces
            PoolConstants.ShowCollisionOverlay = origShowCollision
            settings.godCueStats = false
            applyCueStats()
            if environment.__RAVEN_8BALL_DUELS == moduleInstance then
                environment.__RAVEN_8BALL_DUELS = nil
            end
        end
    }

    environment.__RAVEN_8BALL_DUELS = moduleInstance
    return moduleInstance
end
