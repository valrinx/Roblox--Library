--[[
    RAVEN HUB Module - Steal An Egg v1.2.0
    Game: Steal An Egg (PlaceId: 107778070777162)
    Developer: and Collect Rare Pets

    v1.2.0 — NO hookmetamethod (Byfron-safe)
    - Removed all hookmetamethod calls (caused BAC-6336 kick)
    - Pure passive approach: no metamethod hooks
    - Humanized PathfindingService movement
    - Humanized jitter delays ±15%

    Live Game Structure (verified 2026-08-28):
    - workspace.__OBJECTS.Areas.GuardAreas = 10 biomes
    - ReplicatedStorage.Shared.Remotes = nested table ModuleScript
    - EggWorld remotes: AskFieldEggCarry, AskHatch, AskFinishHatch, AskPlaceEgg, etc.
]]--

return function(Window, runtimeInfo)
    pcall(function()
        local prev = getgenv().__RAVEN_STEAL_AN_EGG
        if prev and type(prev.Destroy) == "function" then prev.Destroy() end
    end)

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local PathfindingService = game:GetService("PathfindingService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TeleportService = game:GetService("TeleportService")
    local VirtualUser = game:GetService("VirtualUser")

    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    ----------------------------------------------------------------
    --  REMOTES (live verified — NO hooks)
    ----------------------------------------------------------------
    local Remotes = {}

    local function getRemotes()
        local ok, rem = pcall(require, ReplicatedStorage.Shared.Remotes)
        if ok and type(rem) == "table" then
            Remotes = rem
            return rem
        end
        return nil
    end
    pcall(getRemotes)

    local function getRemote(module, key)
        if not Remotes then pcall(getRemotes) end
        local mod = Remotes and Remotes[module]
        if mod and typeof(mod[key]) == "Instance" then
            return mod[key]
        end
        return nil
    end

    local function fireRemote(module, key, ...)
        local remote = getRemote(module, key)
        if not remote then return false end
        local ok, err
        if remote:IsA("RemoteEvent") then
            ok, err = pcall(remote.FireServer, remote, ...)
        elseif remote:IsA("RemoteFunction") then
            ok, err = pcall(remote.InvokeServer, remote, ...)
        end
        return ok, err
    end

    ----------------------------------------------------------------
    --  GUARD AREAS DATA (live verified)
    ----------------------------------------------------------------
    local BiomeData = {
        Forest = {
            guardPos = Vector3.new(596.6, 69.3, -317.1),
            exitPos = Vector3.new(590.0, 68.4, -309.2),
        },
        Desert = {
            guardPos = Vector3.new(950, 69.0, -311.5),
            exitPos = Vector3.new(930.8, 67.5, -320.6),
        },
        Snow = {
            guardPos = Vector3.new(1492.3, 75.1, -303.8),
            exitPos = Vector3.new(1473.2, 68.8, -312.4),
        },
        Jungle = {
            guardPos = Vector3.new(1187.9, 68.5, -424.4),
            exitPos = Vector3.new(1171.9, 67.3, -412.5),
        },
        Volcano = {
            guardPos = Vector3.new(1876.0, 71.3, -415.4),
            exitPos = Vector3.new(1863.1, 68.0, -399.5),
        },
        ["Abyss Ocean"] = {
            guardPos = Vector3.new(2283.0, 74.1, -311.7),
            exitPos = Vector3.new(2266.0, 67.6, -324.6),
        },
        Prehistoric = {
            guardPos = Vector3.new(2809.1, 70.9, -416.7),
            exitPos = Vector3.new(2797.7, 68.4, -398.5),
        },
        Cosmic = {
            guardPos = Vector3.new(3392.6, 79.6, -311.7),
            exitPos = Vector3.new(3376.8, 68.4, -322.7),
        },
        Lake = {
            guardPos = Vector3.new(743.3, 69.6, -419.0),
            exitPos = Vector3.new(726.0, 67.7, -409.9),
        },
        ["Cherry Blossom"] = {
            guardPos = Vector3.new(4030.0, 77.1, -412.3),
            exitPos = Vector3.new(4010.7, 68.5, -397.2),
        },
    }

    ----------------------------------------------------------------
    --  STATE
    ----------------------------------------------------------------
    local State = {
        AutoSteal = false,
        StealDelay = 2.5,
        AutoHatch = false,
        HatchInterval = 3,
        AutoPlace = false,
        PlaceInterval = 2,
        PlayerESP = false,
        PlayerESPDistance = 1500,
        EggESP = false,
        EggESPDistance = 2000,
        GuardESP = false,
        GuardESPDistance = 800,
        AntiAFK = true,
        ShowSpeed = true,
    }

    local Connections = {}
    local destroyed = false
    local espObjects = { players = {}, eggs = {}, guards = {} }
    local lastStealAttempt = 0
    local lastHatchAttempt = 0
    local lastPlaceAttempt = 0
    local isMoving = false

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(Connections, conn)
        return conn
    end

    ----------------------------------------------------------------
    --  UTILITY
    ----------------------------------------------------------------
    local function getCharacter()
        return LP.Character or LP.CharacterAdded:Wait()
    end

    local function getHumanoid(model)
        return model and model:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot(model)
        return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    end

    local function getMyRoot()
        return getRoot(getCharacter())
    end

    local function getMyHumanoid()
        return getHumanoid(getCharacter())
    end

    local function isAlive()
        local hum = getMyHumanoid()
        return hum and hum.Health > 0
    end

    local function getDistanceTo(pos)
        local root = getMyRoot()
        if not root or not pos then return math.huge end
        return (root.Position - pos).Magnitude
    end

    local function getBasePart(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then return instance end
        if instance:IsA("Model") and instance.PrimaryPart then return instance.PrimaryPart end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end

    local function humanWait(baseTime)
        local jitter = baseTime * (0.85 + math.random() * 0.3)
        task.wait(jitter)
    end

    ----------------------------------------------------------------
    --  GAME STRUCTURE SCANNER (passive, no hooks)
    ----------------------------------------------------------------
    local cachedStructure = nil
    local lastStructureScan = 0

    local function scanGameStructure()
        local now = os.clock()
        if cachedStructure and (now - lastStructureScan) < 3 then
            return cachedStructure
        end
        lastStructureScan = now

        local structure = {
            guardAreas = {},
            fieldEggs = {},
            nests = {},
            guards = {},
        }

        local ga = workspace:FindFirstChild("__OBJECTS")
            and workspace.__OBJECTS:FindFirstChild("Areas")
            and workspace.__OBJECTS.Areas:FindFirstChild("GuardAreas")
        if ga then
            for _, area in ipairs(ga:GetChildren()) do
                if area:IsA("Model") then
                    local name = area.Name
                    local nests = area:FindFirstChild("Nests")
                    local guard = area:FindFirstChild("Guard")
                    local exit = area:FindFirstChild("ClosestExitPoint")
                    structure.guardAreas[name] = {
                        nests = nests, guard = guard, exit = exit,
                    }
                    if nests then
                        for _, nest in ipairs(nests:GetChildren()) do
                            local part = getBasePart(nest)
                            if part then
                                table.insert(structure.nests, {
                                    model = nest, biome = name, position = part.Position,
                                })
                            end
                        end
                    end
                    if guard then
                        table.insert(structure.guards, {
                            model = guard, biome = name,
                            position = guard.PrimaryPart and guard.PrimaryPart.Position,
                        })
                    end
                end
            end
        end

        local aes = workspace:FindFirstChild("AreaEggSlotsClient")
        if aes then
            for _, slot in ipairs(aes:GetChildren()) do
                if slot:IsA("Model") then
                    local hitbox = slot:FindFirstChild("Hitbox")
                    if hitbox then
                        table.insert(structure.fieldEggs, {
                            model = slot, hitbox = hitbox, position = hitbox.Position,
                        })
                    end
                end
            end
        end

        cachedStructure = structure
        return structure
    end

    ----------------------------------------------------------------
    --  MOVEMENT: Humanized Pathfinding (no WalkSpeed hack)
    ----------------------------------------------------------------
    local function moveToPosition(targetPos, timeout)
        if not targetPos or not isAlive() then return false end
        local root = getMyRoot()
        local humanoid = getMyHumanoid()
        if not root or not humanoid then return false end

        timeout = timeout or 15
        isMoving = true

        local path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = false,
            WaypointSpacing = 4,
        })

        local success = pcall(function()
            path:ComputeAsync(root.Position, targetPos)
        end)

        if not success or path.Status ~= Enum.PathStatus.Success then
            humanoid:MoveTo(targetPos)
            local elapsed = 0
            while isAlive() and elapsed < timeout do
                if getDistanceTo(targetPos) < 4 then break end
                task.wait(0.1)
                elapsed += 0.1
            end
            isMoving = false
            return getDistanceTo(targetPos) < 6
        end

        local waypoints = path:GetWaypoints()
        for _, waypoint in ipairs(waypoints) do
            if not isAlive() or not isMoving then break end
            humanoid:MoveTo(waypoint.Position)
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            local elapsed = 0
            while isAlive() and isMoving and elapsed < 3 do
                if getDistanceTo(waypoint.Position) < 3 then break end
                task.wait(0.05)
                elapsed += 0.05
            end
        end

        isMoving = false
        return getDistanceTo(targetPos) < 6
    end

    local function stopMoving()
        isMoving = false
        local humanoid = getMyHumanoid()
        if humanoid then
            humanoid:MoveTo(getMyRoot() and getMyRoot().Position or Vector3.zero)
        end
    end

    ----------------------------------------------------------------
    --  AUTO STEAL
    ----------------------------------------------------------------
    local function findNearestBiomeExit()
        local root = getMyRoot()
        if not root then return nil end
        local bestName, bestDist = nil, math.huge
        for name, data in pairs(BiomeData) do
            local dist = (root.Position - data.exitPos).Magnitude
            if dist < bestDist then
                bestDist = dist
                bestName = name
            end
        end
        return bestName
    end

    local function findNearestFieldEgg()
        local structure = scanGameStructure()
        local root = getMyRoot()
        if not root then return nil end

        local bestEgg, bestDist = nil, math.huge
        for _, egg in ipairs(structure.fieldEggs) do
            if egg.hitbox and egg.hitbox.Parent then
                local dist = (root.Position - egg.hitbox.Position).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestEgg = egg
                end
            end
        end
        return bestEgg
    end

    local function tryStealEgg()
        if not State.AutoSteal or not isAlive() or isMoving then return end
        local now = os.clock()
        if now - lastStealAttempt < State.StealDelay then return end
        lastStealAttempt = now

        -- Find nearest stealable field egg
        local egg = findNearestFieldEgg()
        if egg then
            local reached = moveToPosition(egg.hitbox.Position, 10)
            if not reached then return end
            humanWait(0.5)

            -- Carry the egg (primary steal method)
            fireRemote("EggWorld", "AskFieldEggCarry", egg.model)
            humanWait(0.8)

            -- Run to exit
            local biomeName = findNearestBiomeExit()
            if biomeName then
                local exit = BiomeData[biomeName] and BiomeData[biomeName].exitPos
                if exit then
                    moveToPosition(exit, 15)
                    humanWait(0.5)
                end
            end
            return
        end

        -- No eggs visible — request snapshot
        fireRemote("EggWorld", "AskFieldEggSnapshot")
    end

    local function returnToBase()
        if not isAlive() or isMoving then return end
        local biomeName = findNearestBiomeExit()
        if biomeName then
            local exit = BiomeData[biomeName] and BiomeData[biomeName].exitPos
            if exit then
                moveToPosition(exit, 20)
            end
        end
    end

    ----------------------------------------------------------------
    --  AUTO HATCH
    ----------------------------------------------------------------
    local function tryHatch()
        if not State.AutoHatch or not isAlive() then return end
        local now = os.clock()
        if now - lastHatchAttempt < State.HatchInterval then return end
        lastHatchAttempt = now

        fireRemote("EggWorld", "AskHatch")
        humanWait(1.5)
        fireRemote("EggWorld", "AskFinishHatch")
    end

    ----------------------------------------------------------------
    --  AUTO PLACE
    ----------------------------------------------------------------
    local function tryPlace()
        if not State.AutoPlace or not isAlive() then return end
        local now = os.clock()
        if now - lastPlaceAttempt < State.PlaceInterval then return end
        lastPlaceAttempt = now

        fireRemote("EggWorld", "AskPlaceEgg")
    end

    ----------------------------------------------------------------
    --  ESP SYSTEM (passive — Instance.new only)
    ----------------------------------------------------------------
    local function createHighlight(owner, color, name)
        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenSAE_" .. (name or "ESP")
        highlight.FillTransparency = 0.80
        highlight.OutlineTransparency = 0.1
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.Enabled = false
        highlight.Parent = owner
        return highlight
    end

    local function createBillboard(owner, part, text, color)
        local bb = Instance.new("BillboardGui")
        bb.Name = "RavenSAELabel"
        bb.Size = UDim2.new(0, 200, 0, 22)
        bb.StudsOffset = Vector3.new(0, 2.5, 0)
        bb.AlwaysOnTop = true
        bb.Enabled = false
        bb.Parent = part

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0.3
        lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
        lbl.TextSize = 12
        lbl.Font = Enum.Font.GothamBold
        lbl.Text = text or ""
        lbl.Parent = bb
        return bb, lbl
    end

    local function removeESP(group, key)
        local obj = group[key]
        if not obj then return end
        pcall(function() if obj.highlight then obj.highlight:Destroy() end end)
        pcall(function() if obj.billboard then obj.billboard:Destroy() end end)
        group[key] = nil
    end

    local function clearAllESP()
        for group in pairs(espObjects) do
            local keys = {}
            for k in pairs(espObjects[group]) do table.insert(keys, k) end
            for _, k in ipairs(keys) do removeESP(espObjects[group], k) end
        end
    end

    local function updatePlayerESP()
        if not State.PlayerESP then
            for k in pairs(espObjects.players) do removeESP(espObjects.players, k) end
            return
        end
        local myRoot = getMyRoot()
        local active = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP and player.Character then
                local model = player.Character
                local root = getRoot(model)
                local humanoid = getHumanoid(model)
                if root and humanoid and humanoid.Health > 0 then
                    local dist = myRoot and (myRoot.Position - root.Position).Magnitude or math.huge
                    if dist <= State.PlayerESPDistance then
                        active[player] = true
                        local obj = espObjects.players[player]
                        if not obj then
                            local hl = createHighlight(model, Color3.fromRGB(80, 180, 255), "Player")
                            local bb, lbl = createBillboard(model, root, "", Color3.fromRGB(80, 180, 255))
                            espObjects.players[player] = { highlight = hl, billboard = bb, label = lbl }
                            obj = espObjects.players[player]
                        end
                        obj.highlight.Enabled = true
                        obj.billboard.Enabled = true
                        obj.billboard.Adornee = root
                        obj.label.Text = string.format("%s [%dm] %dh",
                            player.DisplayName or player.Name,
                            math.floor(dist), math.floor(humanoid.Health))
                    end
                end
            end
        end
        for k in pairs(espObjects.players) do
            if not active[k] then removeESP(espObjects.players, k) end
        end
    end

    local function updateEggESP()
        if not State.EggESP then
            for k in pairs(espObjects.eggs) do removeESP(espObjects.eggs, k) end
            return
        end
        local myRoot = getMyRoot()
        local structure = scanGameStructure()
        local active = {}
        for i, egg in ipairs(structure.fieldEggs) do
            if egg.hitbox and egg.hitbox.Parent then
                local dist = myRoot and (myRoot.Position - egg.hitbox.Position).Magnitude or math.huge
                if dist <= State.EggESPDistance then
                    active[i] = true
                    local obj = espObjects.eggs[i]
                    if not obj then
                        local hl = createHighlight(egg.model, Color3.fromRGB(255, 215, 0), "Egg")
                        local bb, lbl = createBillboard(egg.model, egg.hitbox, egg.model.Name, Color3.fromRGB(255, 215, 0))
                        espObjects.eggs[i] = { highlight = hl, billboard = bb, label = lbl }
                        obj = espObjects.eggs[i]
                    end
                    obj.highlight.Enabled = true
                    obj.billboard.Enabled = true
                    obj.billboard.Adornee = egg.hitbox
                    obj.label.Text = string.format("🥚 [%dm]", math.floor(dist))
                end
            end
        end
        for k in pairs(espObjects.eggs) do
            if not active[k] then removeESP(espObjects.eggs, k) end
        end
    end

    local function updateGuardESP()
        if not State.GuardESP then
            for k in pairs(espObjects.guards) do removeESP(espObjects.guards, k) end
            return
        end
        local myRoot = getMyRoot()
        local structure = scanGameStructure()
        local active = {}
        for i, guard in ipairs(structure.guards) do
            if guard.model and guard.model.Parent then
                local part = getBasePart(guard.model)
                if part then
                    local dist = myRoot and (myRoot.Position - part.Position).Magnitude or math.huge
                    if dist <= State.GuardESPDistance then
                        active[i] = true
                        local obj = espObjects.guards[i]
                        if not obj then
                            local hl = createHighlight(guard.model, Color3.fromRGB(255, 50, 50), "Guard")
                            local bb, lbl = createBillboard(guard.model, part, "⚠ " .. guard.biome, Color3.fromRGB(255, 50, 50))
                            espObjects.guards[i] = { highlight = hl, billboard = bb, label = lbl }
                            obj = espObjects.guards[i]
                        end
                        obj.highlight.Enabled = true
                        obj.billboard.Enabled = true
                        obj.billboard.Adornee = part
                        obj.label.Text = string.format("⚠ %s [%dm]", guard.biome, math.floor(dist))
                    end
                end
            end
        end
        for k in pairs(espObjects.guards) do
            if not active[k] then removeESP(espObjects.guards, k) end
        end
    end

    ----------------------------------------------------------------
    --  SPEED DISPLAY
    ----------------------------------------------------------------
    local speedLabel = nil

    local function createSpeedDisplay()
        if speedLabel then return end
        pcall(function()
            speedLabel = Instance.new("ScreenGui")
            speedLabel.Name = "RavenSAESpeedDisplay"
            speedLabel.ResetOnSpawn = false
            speedLabel.DisplayOrder = 999
            local parent = gethui and gethui() or LP:FindFirstChildOfClass("PlayerGui") or game:GetService("CoreGui")
            speedLabel.Parent = parent

            local frame = Instance.new("Frame")
            frame.Size = UDim2.new(0, 180, 0, 36)
            frame.Position = UDim2.new(0.5, -90, 0, 8)
            frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
            frame.BackgroundTransparency = 0.3
            frame.BorderSizePixel = 0
            frame.Parent = speedLabel

            Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

            local text = Instance.new("TextLabel")
            text.Size = UDim2.fromScale(1, 1)
            text.BackgroundTransparency = 1
            text.TextColor3 = Color3.fromRGB(0, 255, 150)
            text.TextStrokeTransparency = 0.5
            text.TextStrokeColor3 = Color3.new(0, 0, 0)
            text.Font = Enum.Font.GothamBold
            text.TextSize = 14
            text.Text = "Speed: ..."
            text.Parent = frame
        end)
    end

    local function updateSpeedDisplay()
        if not State.ShowSpeed then
            if speedLabel then speedLabel.Enabled = false end
            return
        end
        createSpeedDisplay()
        if speedLabel then speedLabel.Enabled = true end
        pcall(function()
            local textLabel = speedLabel and speedLabel:FindFirstChild("Frame")
                and speedLabel.Frame:FindFirstChildOfClass("TextLabel")
            if textLabel then
                local humanoid = getMyHumanoid()
                local speed = humanoid and math.floor(humanoid.WalkSpeed) or 0
                textLabel.Text = string.format("Speed: %d", speed)
            end
        end)
    end

    ----------------------------------------------------------------
    --  ANTI-AFK
    ----------------------------------------------------------------
    connect(LP.Idled, function()
        pcall(function()
            VirtualUser:Button2Down(Vector2.zero, Camera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.zero, Camera.CFrame)
        end)
    end)

    ----------------------------------------------------------------
    --  MAIN LOOP
    ----------------------------------------------------------------
    local espAccum = 0

    connect(RunService.Heartbeat, function(dt)
        if destroyed then return end

        espAccum += dt
        if espAccum >= 0.5 then
            espAccum = 0
            updatePlayerESP()
            updateEggESP()
            updateGuardESP()
            updateSpeedDisplay()
        end

        if State.AutoSteal and isAlive() and not isMoving then
            task.spawn(tryStealEgg)
        end
        if State.AutoHatch and isAlive() then
            task.spawn(tryHatch)
        end
        if State.AutoPlace and isAlive() then
            task.spawn(tryPlace)
        end
    end)

    ----------------------------------------------------------------
    --  UI TABS
    ----------------------------------------------------------------
    local FarmTab = Window:CreateTab("Farm", 4483362458)
    FarmTab:CreateSection("Auto Steal (Byfron-safe v1.2)")
    FarmTab:CreateToggle({
        Name = "Auto Steal Eggs",
        CurrentValue = false,
        Flag = "SAEAutoSteal",
        Callback = function(value)
            State.AutoSteal = value
            if not value then stopMoving() end
        end,
    })
    FarmTab:CreateSlider({
        Name = "Steal Delay",
        Range = {1, 8},
        Increment = 0.5,
        Suffix = " s",
        CurrentValue = 2.5,
        Flag = "SAEStealDelay",
        Callback = function(value) State.StealDelay = value end,
    })
    FarmTab:CreateButton({
        Name = "Steal Nearest Egg Now",
        Callback = function()
            State.AutoSteal = true
            task.spawn(tryStealEgg)
        end,
    })
    FarmTab:CreateButton({
        Name = "Return to Base",
        Callback = function() task.spawn(returnToBase) end,
    })

    FarmTab:CreateSection("Auto Hatch & Place")
    FarmTab:CreateToggle({
        Name = "Auto Hatch",
        CurrentValue = false,
        Flag = "SAEAutoHatch",
        Callback = function(value) State.AutoHatch = value end,
    })
    FarmTab:CreateSlider({
        Name = "Hatch Interval",
        Range = {1, 10},
        Increment = 1,
        Suffix = " s",
        CurrentValue = 3,
        Flag = "SAEHatchInterval",
        Callback = function(value) State.HatchInterval = value end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Place Egg",
        CurrentValue = false,
        Flag = "SAEAutoPlace",
        Callback = function(value) State.AutoPlace = value end,
    })

    local VisualTab = Window:CreateTab("Visual", 4483362458)
    VisualTab:CreateSection("ESP")
    VisualTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "SAEPlayerESP",
        Callback = function(value) State.PlayerESP = value end,
    })
    VisualTab:CreateSlider({
        Name = "Player ESP Distance",
        Range = {200, 3000},
        Increment = 100,
        Suffix = " m",
        CurrentValue = 1500,
        Flag = "SAEPlayerESPDist",
        Callback = function(value) State.PlayerESPDistance = value end,
    })
    VisualTab:CreateToggle({
        Name = "Egg ESP",
        CurrentValue = false,
        Flag = "SAEEggESP",
        Callback = function(value) State.EggESP = value end,
    })
    VisualTab:CreateSlider({
        Name = "Egg ESP Distance",
        Range = {200, 3000},
        Increment = 100,
        Suffix = " m",
        CurrentValue = 2000,
        Flag = "SAEEggESPDist",
        Callback = function(value) State.EggESPDistance = value end,
    })
    VisualTab:CreateToggle({
        Name = "Guard ESP",
        CurrentValue = false,
        Flag = "SAEGuardESP",
        Callback = function(value) State.GuardESP = value end,
    })
    VisualTab:CreateSlider({
        Name = "Guard ESP Distance",
        Range = {100, 1500},
        Increment = 100,
        Suffix = " m",
        CurrentValue = 800,
        Flag = "SAEGuardESPDist",
        Callback = function(value) State.GuardESPDistance = value end,
    })

    local MiscTab = Window:CreateTab("Misc", 4483362458)
    MiscTab:CreateSection("Utilities")
    MiscTab:CreateToggle({
        Name = "Anti-AFK",
        CurrentValue = true,
        Flag = "SAEAntiAFK",
        Callback = function(value) State.AntiAFK = value end,
    })
    MiscTab:CreateToggle({
        Name = "Speed Display",
        CurrentValue = true,
        Flag = "SAESpeedDisplay",
        Callback = function(value)
            State.ShowSpeed = value
            if not value and speedLabel then speedLabel.Enabled = false end
        end,
    })
    MiscTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
            end)
        end,
    })
    MiscTab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            pcall(function()
                TeleportService:Teleport(game.PlaceId)
            end)
        end,
    })

    ----------------------------------------------------------------
    --  CLEANUP
    ----------------------------------------------------------------
    local function destroy()
        if destroyed then return end
        destroyed = true
        State.AutoSteal = false
        State.AutoHatch = false
        State.AutoPlace = false
        stopMoving()
        clearAllESP()
        if speedLabel then pcall(function() speedLabel:Destroy() end) end
        speedLabel = nil
        for _, conn in ipairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(Connections)
        pcall(function()
            local env = getgenv()
            if env.__RAVEN_STEAL_AN_EGG and env.__RAVEN_STEAL_AN_EGG.Settings == State then
                env.__RAVEN_STEAL_AN_EGG = nil
            end
        end)
    end

    getgenv().__RAVEN_STEAL_AN_EGG = {
        Version = "v1.2.0",
        Settings = State,
        State = State,
        BiomeData = BiomeData,
        ScanGameStructure = scanGameStructure,
        GetRemotes = getRemotes,
        FireRemote = fireRemote,
        FindNearestFieldEgg = findNearestFieldEgg,
        FindNearestBiomeExit = findNearestBiomeExit,
        TryStealEgg = tryStealEgg,
        ReturnToBase = returnToBase,
        TryHatch = tryHatch,
        TryPlace = tryPlace,
        Destroy = destroy,
    }

    if runtimeInfo and type(runtimeInfo.registerCleanup) == "function" then
        runtimeInfo.registerCleanup(destroy)
    end
end
