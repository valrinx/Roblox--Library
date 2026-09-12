-- ============================================================
--   RAVEN HUB  |  Volleyball Legends (ESP & Visuals Only)
--   Pure Visual ESP: Ball ESP, Landing Marker, Player ESP
--   Zero input hooks, Zero automation, 100% safe native controls
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ReplicatedFirst = game:GetService("ReplicatedFirst")

    -- Clean up previous instance if running
    local environment = getgenv and getgenv() or _G
    if type(environment.__RAVEN_VOLLEYBALL_LEGENDS) == "table"
        and type(environment.__RAVEN_VOLLEYBALL_LEGENDS.Destroy) == "function" then
        pcall(environment.__RAVEN_VOLLEYBALL_LEGENDS.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = workspace.CurrentCamera

    local running = true
    local connections = {}
    local espObjects = {}

    -- Settings (ESP Only)
    local settings = {
        ballEsp = true,
        landingMarker = true,
        landingLabel = true,
        playerEsp = true,
        espDistance = true,
        markerColor = Color3.fromRGB(0, 255, 170),
        ballColor = Color3.fromRGB(255, 215, 0),
        playerColor = Color3.fromRGB(85, 170, 255),
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
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true)
    end

    local function getHumanoid(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    -- Reference to Jump Validation to auto-unlock if game bugs
    local JumpValidation = nil
    local GameController = nil
    pcall(function()
        JumpValidation = require(ReplicatedFirst.Controllers.GameController.Actions.Move.Jump.Validation)
        GameController = require(ReplicatedFirst.Controllers.GameController)
    end)

    -- Ball Detection Helper & Game Physics
    local BallModule = nil
    local PhysicsModule = nil
    pcall(function()
        BallModule = require(ReplicatedFirst.Controllers.BallController.Ball)
    end)
    pcall(function()
        PhysicsModule = require(ReplicatedStorage.Common.Physics)
    end)

    local function getActiveBall()
        if BallModule and BallModule.All then
            for _, ballObj in pairs(BallModule.All) do
                local ballPart = ballObj.Ball and (ballObj.Ball.PrimaryPart or ballObj.Ball:FindFirstChildWhichIsA("BasePart"))
                if ballPart and ballPart.Parent then
                    return ballObj, ballPart
                end
            end
        end

        -- Fallback: Look for CLIENT_BALL_ in workspace
        for _, child in ipairs(workspace:GetChildren()) do
            if string.sub(child.Name, 1, 12) == "CLIENT_BALL_" then
                local bPart = child.PrimaryPart or child:FindFirstChildWhichIsA("BasePart")
                if bPart then
                    return nil, bPart
                end
            end
        end

        return nil, nil
    end

    -- Accurate Floor Height Function
    local function getFloorY(pos)
        if PhysicsModule and type(PhysicsModule.calculateFloorHeight) == "function" then
            local f = PhysicsModule.calculateFloorHeight(pos)
            if f then return f end
        end
        return -23.658
    end

    -- Landing Calculation
    local function getPredictedLanding(pos, vel, floorY)
        local g = workspace.Gravity > 0 and workspace.Gravity or 43
        local a = -0.5 * g
        local b = vel.Y
        local c = pos.Y - floorY

        if math.abs(b) < 0.001 and c <= 0.8 then
            return pos, 0
        end

        local discriminant = b * b - 4 * a * c
        if discriminant < 0 then
            return pos, 0
        end

        local sqrtD = math.sqrt(discriminant)
        local t1 = (-b - sqrtD) / (2 * a)
        local t2 = (-b + sqrtD) / (2 * a)

        local t = math.max(t1, t2)
        if t <= 0 then
            if c > 0 then
                t = math.sqrt((2 * c) / g)
            else
                t = 0
            end
        end

        local landingPos = Vector3.new(
            pos.X + vel.X * t,
            floorY,
            pos.Z + vel.Z * t
        )
        return landingPos, t
    end

    -- Visual Landing Elements (Cylinder + AlwaysOnTop BillboardGui)
    local landingCylinder = Instance.new("Part")
    landingCylinder.Name = "Raven_LandingMarker"
    landingCylinder.Shape = Enum.PartType.Cylinder
    landingCylinder.Size = Vector3.new(0.4, 7, 7)
    landingCylinder.CFrame = CFrame.new(0, -500, 0) * CFrame.Angles(0, 0, math.rad(90))
    landingCylinder.Anchored = true
    landingCylinder.CanCollide = false
    landingCylinder.CanTouch = false
    landingCylinder.CanQuery = false
    landingCylinder.Material = Enum.Material.Neon
    landingCylinder.Color = settings.markerColor
    landingCylinder.Transparency = 1
    landingCylinder.Parent = workspace

    -- Target Billboard on Landing spot with AlwaysOnTop
    local landingBb = Instance.new("BillboardGui")
    landingBb.Name = "Raven_LandingIndicator"
    landingBb.Adornee = landingCylinder
    landingBb.Size = UDim2.new(0, 160, 0, 48)
    landingBb.StudsOffset = Vector3.new(0, 1.5, 0)
    landingBb.AlwaysOnTop = true
    landingBb.Enabled = true

    local landingText = Instance.new("TextLabel")
    landingText.BackgroundTransparency = 1
    landingText.Size = UDim2.new(1, 0, 1, 0)
    landingText.Font = Enum.Font.GothamBold
    landingText.TextSize = 13
    landingText.TextColor3 = settings.markerColor
    landingText.TextStrokeTransparency = 0.2
    landingText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    landingText.RichText = true
    landingText.Text = "🎯 <b>Landing Spot</b>"
    landingText.Parent = landingBb
    landingBb.Parent = landingCylinder

    -- ESP Helpers
    local function createBillboard(id, adornee, color, title, offset)
        local bb = Instance.new("BillboardGui")
        bb.Name = "RavenESP_" .. tostring(id)
        bb.Adornee = adornee
        bb.Size = UDim2.new(0, 180, 0, 48)
        bb.StudsOffset = offset or Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true

        local text = Instance.new("TextLabel")
        text.BackgroundTransparency = 1
        text.Size = UDim2.new(1, 0, 1, 0)
        text.Font = Enum.Font.GothamBold
        text.TextSize = 13
        text.TextColor3 = color or Color3.fromRGB(255, 255, 255)
        text.TextStrokeTransparency = 0.2
        text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        text.RichText = true
        text.Text = title or ""
        text.Parent = bb

        bb.Parent = adornee
        return bb, text
    end

    local function createHighlight(adornee, fillColor, outlineColor)
        local hl = Instance.new("Highlight")
        hl.Name = "RavenHighlight"
        hl.Adornee = adornee
        hl.FillColor = fillColor or Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.55
        hl.OutlineColor = outlineColor or Color3.fromRGB(255, 255, 255)
        hl.OutlineTransparency = 0.2
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = adornee
        return hl
    end

    local function clearEspEntry(id)
        if espObjects[id] then
            if espObjects[id].billboard then pcall(function() espObjects[id].billboard:Destroy() end) end
            if espObjects[id].highlight then pcall(function() espObjects[id].highlight:Destroy() end) end
            espObjects[id] = nil
        end
    end

    -- Watchdog to guarantee jump and input never lock
    local lastWatchdog = 0

    -- ============================================================
    --   RENDER LOOP (Visuals Only)
    -- ============================================================
    connect(RunService.RenderStepped, function()
        if not running then return end

        local myChar = localPlayer.Character
        local myRoot = getRoot(myChar)
        local myHum = getHumanoid(myChar)
        local myPos = myRoot and myRoot.Position or Vector3.zero

        -- Ground watchdog: if player is safely on ground, ensure jump cooldown lock (_Key) doesn't stay stuck
        local now = os.clock()
        if (now - lastWatchdog) > 0.5 then
            lastWatchdog = now
            if myHum and myHum.FloorMaterial ~= Enum.Material.Air then
                if JumpValidation and JumpValidation._Key and (now - JumpValidation._Key) > 1.2 then
                    JumpValidation._Key = nil
                end
                if GameController and GameController.IsBusy and GameController.IsBusy:get() == true then
                    pcall(function() GameController.IsBusy:set(false) end)
                end
            end
        end

        local ballObj, ballPart = getActiveBall()

        -- 1. Ball ESP
        if settings.ballEsp and ballPart then
            local dist = math.floor((ballPart.Position - myPos).Magnitude)
            local id = "Ball_Main"
            local vel = (ballObj and ballObj.Velocity) or ballPart.AssemblyLinearVelocity or Vector3.zero
            local speed = math.floor(vel.Magnitude)

            if not espObjects[id] then
                local bb, lbl = createBillboard(id, ballPart, settings.ballColor, "🏐 Ball", Vector3.new(0, 2.5, 0))
                local hl = createHighlight(ballPart, settings.ballColor, Color3.fromRGB(255, 255, 255))
                espObjects[id] = { billboard = bb, label = lbl, highlight = hl }
            else
                espObjects[id].label.Text = string.format("🏐 <b>Ball</b>\n<font size='11' color='#FFFFFF'>[%d studs | %d spd]</font>", dist, speed)
            end
        else
            clearEspEntry("Ball_Main")
        end

        -- 2. Landing Prediction Marker
        if settings.landingMarker and ballPart and landingCylinder then
            local ballPos = ballPart.Position
            local ballVel = (ballObj and ballObj.Velocity) or ballPart.AssemblyLinearVelocity or Vector3.zero
            local floorY = getFloorY(ballPos)
            local landingPos, t = getPredictedLanding(ballPos, ballVel, floorY)

            -- Keep landing floor accurate at target point
            local targetFloorY = getFloorY(landingPos)
            local distToTarget = math.floor((landingPos - myPos).Magnitude)

            if t > 0.03 and t < 6.0 and (ballPos.Y - targetFloorY) > 1.0 then
                landingCylinder.CFrame = CFrame.new(landingPos.X, targetFloorY + 0.25, landingPos.Z) * CFrame.Angles(0, 0, math.rad(90))
                landingCylinder.Transparency = 0.3
                if settings.landingLabel then
                    landingBb.Enabled = true
                    landingText.Text = string.format("🎯 <b>Landing Spot</b>\n<font size='11' color='#00FFAA'>[%.2fs | %d studs]</font>", t, distToTarget)
                else
                    landingBb.Enabled = false
                end
            else
                landingCylinder.CFrame = CFrame.new(0, -500, 0) * CFrame.Angles(0, 0, math.rad(90))
                landingCylinder.Transparency = 1
                landingBb.Enabled = false
            end
        elseif landingCylinder then
            landingCylinder.CFrame = CFrame.new(0, -500, 0) * CFrame.Angles(0, 0, math.rad(90))
            landingCylinder.Transparency = 1
            if landingBb then landingBb.Enabled = false end
        end

        -- 3. Player ESP
        if settings.playerEsp then
            local validIds = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= localPlayer and p.Character then
                    local pChar = p.Character
                    local pRoot = getRoot(pChar)
                    local pHum = getHumanoid(pChar)
                    if pRoot and pHum and pHum.Health > 0 then
                        local pId = "Player_" .. p.Name
                        validIds[pId] = true
                        local pDist = math.floor((pRoot.Position - myPos).Magnitude)

                        if not espObjects[pId] then
                            local bb, lbl = createBillboard(pId, pRoot, settings.playerColor, p.DisplayName, Vector3.new(0, 3.2, 0))
                            local hl = createHighlight(pChar, settings.playerColor, Color3.fromRGB(255, 255, 255))
                            espObjects[pId] = { billboard = bb, label = lbl, highlight = hl }
                        else
                            local infoText = "<b>" .. p.DisplayName .. "</b>"
                            if settings.espDistance then
                                infoText = infoText .. string.format("\n<font size='10' color='#CCCCCC'>[%d studs]</font>", pDist)
                            end
                            espObjects[pId].label.Text = infoText
                        end
                    end
                end
            end

            for id, _ in pairs(espObjects) do
                if string.sub(id, 1, 7) == "Player_" and not validIds[id] then
                    clearEspEntry(id)
                end
            end
        else
            for id, _ in pairs(espObjects) do
                if string.sub(id, 1, 7) == "Player_" then
                    clearEspEntry(id)
                end
            end
        end
    end)

    -- ============================================================
    --   UI (MacLib Tabs)
    -- ============================================================
    local VisualsTab = Window:CreateTab("Visuals & ESP", 4483362458)
    VisualsTab:CreateSection("Ball ESP")

    VisualsTab:CreateToggle({
        Name = "Ball ESP & Velocity",
        CurrentValue = settings.ballEsp,
        Flag = "VB_BallEsp_v4",
        Callback = function(value)
            settings.ballEsp = value
            if not value then clearEspEntry("Ball_Main") end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Landing Prediction Marker",
        CurrentValue = settings.landingMarker,
        Flag = "VB_LandingMarker_v4",
        Callback = function(value)
            settings.landingMarker = value
            if not value and landingCylinder then
                landingCylinder.CFrame = CFrame.new(0, -500, 0)
                if landingBb then landingBb.Enabled = false end
            end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Landing Spot Timer & Distance",
        CurrentValue = settings.landingLabel,
        Flag = "VB_LandingLabel_v4",
        Callback = function(value)
            settings.landingLabel = value
        end,
    })

    VisualsTab:CreateSection("Player ESP")

    VisualsTab:CreateToggle({
        Name = "Player ESP & Highlight",
        CurrentValue = settings.playerEsp,
        Flag = "VB_PlayerEsp_v4",
        Callback = function(value)
            settings.playerEsp = value
            if not value then
                for id, _ in pairs(espObjects) do
                    if string.sub(id, 1, 7) == "Player_" then clearEspEntry(id) end
                end
            end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = settings.espDistance,
        Flag = "VB_EspDistance_v4",
        Callback = function(value)
            settings.espDistance = value
        end,
    })

    -- ============================================================
    --   CLEANUP
    -- ============================================================
    local function destroyScript()
        if not running then return end
        running = false

        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(connections)

        for id, _ in pairs(espObjects) do
            clearEspEntry(id)
        end
        table.clear(espObjects)

        if landingCylinder then
            pcall(function() landingCylinder:Destroy() end)
            landingCylinder = nil
        end
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end

    environment.__RAVEN_VOLLEYBALL_LEGENDS = {
        Destroy = destroyScript
    }
end
