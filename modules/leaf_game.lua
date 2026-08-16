-- RAVEN HUB | 🍂 Game automation suite
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local VirtualUser = game:GetService("VirtualUser")
    local TeleportService = game:GetService("TeleportService")

    local player = Players.LocalPlayer
    local environment = getgenv()

    -- Cleanup previous instance
    if type(environment.__RAVEN_LEAF_GAME) == "table"
        and type(environment.__RAVEN_LEAF_GAME.Destroy) == "function" then
        pcall(environment.__RAVEN_LEAF_GAME.Destroy)
    end

    local running = true
    local connections = {}

    -- Remotes
    local Remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
    local CollectLeafRemote = Remotes and Remotes:FindFirstChild("CollectLeaf")
    local EmptyBackpackRemote = Remotes and Remotes:FindFirstChild("EmptyBackpack")
    local EquipToolRemote = Remotes and Remotes:FindFirstChild("EquipTool")

    -- Zone data from Leave_Locations
    local ZONES = {
        "Frontyard", "Porch", "Shed", "Garage", "Court",
        "Rooftop", "Backyard", "Pool", "Maze", "Farm", "Basement"
    }

    -- Dumpster positions (sell locations)
    local DUMPSTER_POSITIONS = {}
    pcall(function()
        local dumpsterFolder = workspace.Map.Dumpsters
        for _, d in ipairs(dumpsterFolder:GetChildren()) do
            if d:IsA("Model") then
                local primary = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
                if primary then
                    table.insert(DUMPSTER_POSITIONS, primary.Position + Vector3.new(0, 3, 0))
                end
            end
        end
    end)
    -- Hardcoded fallback if streaming hasn't loaded them
    if #DUMPSTER_POSITIONS == 0 then
        DUMPSTER_POSITIONS = {
            Vector3.new(124, 67, -52),
            Vector3.new(151, 65, -118),
            Vector3.new(51, 65, -50),
        }
    end

    -- Settings
    local settings = {
        autoCollect = false,
        collectInterval = 0.5,
        collectRadius = 30,
        autoSell = false,
        sellThreshold = 0.9, -- sell at 90% capacity
        autoFarmLoop = false,
        farmZone = "Frontyard",
        teleportSpeed = 100,
        leafEsp = false,
        dumpsterEsp = false,
        antiAfk = true,
        autoRejoin = false,
        autoEquipTool = "Hand",
    }

    -- Utility functions
    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 5})
            end)
        end
    end

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getCharacter()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return character, humanoid, root
    end

    local function teleportTo(position)
        local _, _, root = getCharacter()
        if not root then return false end
        if typeof(position) == "CFrame" then
            root.CFrame = position
        else
            root.CFrame = CFrame.new(position)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    local function getLeafCapacity()
        return player:GetAttribute("LeafCapacity") or 25
    end

    local function getCurrentLeaves()
        return player:GetAttribute("Leaves") or 0
    end

    local function isBagFull()
        return getCurrentLeaves() >= getLeafCapacity()
    end

    local function isBagAtThreshold()
        return getCurrentLeaves() >= math.floor(getLeafCapacity() * settings.sellThreshold)
    end

    -- Get nearby leaves sorted by distance
    local function getNearbyLeaves(maxRadius, maxCount)
        local _, _, root = getCharacter()
        if not root then return {}, {} end
        local leavesFolder = workspace:FindFirstChild("Leaves")
        if not leavesFolder then return {}, {} end

        local children = leavesFolder:GetChildren()
        local candidates = {}
        local rootPos = root.Position

        for i, leaf in ipairs(children) do
            if leaf:IsA("BasePart") then
                local dist = (leaf.Position - rootPos).Magnitude
                if dist <= maxRadius then
                    table.insert(candidates, {index = i, leaf = leaf, distance = dist})
                end
            end
        end

        table.sort(candidates, function(a, b)
            return a.distance < b.distance
        end)

        local indices = {}
        local leaves = {}
        for i = 1, math.min(maxCount or 10, #candidates) do
            table.insert(indices, candidates[i].index)
            table.insert(leaves, candidates[i].leaf)
        end
        return indices, leaves
    end

    -- Collect leaves by simulating the Hand tool click.
    -- The game's LeafSim client script handles the full pipeline:
    -- click → grab nearby leaves via physics → fly to player → fire CollectLeaf remote
    -- We cannot raw-fire the remote because the server validates client grab state.
    local function collectLeaves()
        if isBagFull() then return 0 end

        local _, _, root = getCharacter()
        if not root then return 0 end

        -- Check if there are leaves nearby
        local indices, leaves = getNearbyLeaves(settings.collectRadius, 10)
        if #leaves == 0 then return 0 end

        -- Check Hand cooldown
        if player:GetAttribute("HandCooldown") then return -1 end

        -- Simulate the Hand tool click via the toolbar button
        local gui = player:FindFirstChildOfClass("PlayerGui")
        local gameGui = gui and gui:FindFirstChild("Gui")
        local toolbar = gameGui and gameGui:FindFirstChild("Toolbar")
        local handFrame = toolbar and toolbar:FindFirstChild("Hand")
        local clickBtn = handFrame and handFrame:FindFirstChild("Click")

        if clickBtn and clickBtn:IsA("GuiButton") then
            local fired = false
            if type(firesignal) == "function" then
                pcall(firesignal, clickBtn.MouseButton1Click)
                fired = true
            elseif type(getconnections) == "function" then
                for _, conn in ipairs(getconnections(clickBtn.MouseButton1Click)) do
                    pcall(function()
                        if conn.Function then conn.Function() else conn:Fire() end
                    end)
                    fired = true
                end
            end
            if not fired then
                -- Fallback: VirtualInputManager click
                local VIM = game:GetService("VirtualInputManager")
                pcall(function()
                    VIM:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    task.wait(0.05)
                    VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end)
                fired = true
            end
            return fired and #leaves or 0
        end

        return 0
    end

    -- Sell leaves at nearest dumpster
    local function sellLeaves()
        if not EmptyBackpackRemote then return false end
        if getCurrentLeaves() <= 0 then return false end

        -- Find nearest dumpster
        local _, _, root = getCharacter()
        if not root then return false end

        local nearest, nearestDist
        for _, pos in ipairs(DUMPSTER_POSITIONS) do
            local dist = (pos - root.Position).Magnitude
            if not nearestDist or dist < nearestDist then
                nearest = pos
                nearestDist = dist
            end
        end

        if not nearest then return false end

        -- Teleport to dumpster if too far
        if nearestDist > 15 then
            teleportTo(nearest)
            task.wait(0.3)
        end

        -- Fire sell remote
        pcall(function()
            EmptyBackpackRemote:FireServer()
        end)
        return true
    end

    -- Equip a tool
    local function equipTool(toolName)
        if not EquipToolRemote then return false end
        pcall(function()
            EquipToolRemote:FireServer(toolName)
        end)
        return true
    end

    -- Get zone center position
    local function getZoneCenter(zoneName)
        local map = workspace:FindFirstChild("Map")
        local locations = map and map:FindFirstChild("Leave_Locations")
        local zone = locations and locations:FindFirstChild(zoneName)
        if not zone then return nil end

        -- Average the positions of zone children to find center
        local total = Vector3.zero
        local count = 0
        for _, child in ipairs(zone:GetChildren()) do
            if child:IsA("BasePart") then
                total = total + child.Position
                count = count + 1
            end
        end
        if count > 0 then
            return total / count + Vector3.new(0, 3, 0)
        end
        return nil
    end

    -- ESP highlights
    local highlights = {}

    local function clearHighlights()
        for obj, hl in pairs(highlights) do
            if hl and hl.Parent then hl:Destroy() end
            highlights[obj] = nil
        end
    end

    local function refreshEsp()
        local wanted = {}

        if settings.leafEsp then
            local _, leaves = getNearbyLeaves(settings.collectRadius, 50)
            for _, leaf in ipairs(leaves) do
                wanted[leaf] = Color3.fromRGB(100, 200, 50)
            end
        end

        if settings.dumpsterEsp then
            local dumpsterFolder = workspace:FindFirstChild("Map")
                and workspace.Map:FindFirstChild("Dumpsters")
            if dumpsterFolder then
                for _, d in ipairs(dumpsterFolder:GetChildren()) do
                    if d:IsA("Model") then
                        wanted[d] = Color3.fromRGB(255, 180, 50)
                    end
                end
            end
        end

        -- Add new highlights
        for obj, color in pairs(wanted) do
            if obj.Parent and not highlights[obj] then
                local hl = Instance.new("Highlight")
                hl.Name = "RavenLeafESP"
                hl.FillColor = color
                hl.FillTransparency = 0.7
                hl.OutlineColor = color
                hl.OutlineTransparency = 0.3
                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                hl.Adornee = obj
                hl.Parent = obj
                highlights[obj] = hl
            end
        end

        -- Remove stale highlights
        for obj, hl in pairs(highlights) do
            if not wanted[obj] or not obj.Parent then
                hl:Destroy()
                highlights[obj] = nil
            end
        end
    end

    -- ============================================================
    --   UI TABS
    -- ============================================================

    local FarmTab = Window:CreateTab("Leaf Farm", 4483362458)

    FarmTab:CreateSection("Auto Collect")
    local collectStatus = FarmTab:CreateLabel("Collect: idle")

    FarmTab:CreateToggle({
        Name = "Auto Collect Leaves",
        CurrentValue = false,
        Flag = "LeafGameAutoCollect",
        Callback = function(v) settings.autoCollect = v end,
    })
    FarmTab:CreateSlider({
        Name = "Collect Interval",
        Range = {0.3, 3},
        Increment = 0.1,
        CurrentValue = 0.5,
        Suffix = " s",
        Flag = "LeafGameCollectInterval",
        Callback = function(v) settings.collectInterval = v end,
    })
    FarmTab:CreateSlider({
        Name = "Collect Radius (TP to leaves)",
        Range = {10, 200},
        Increment = 5,
        CurrentValue = 30,
        Suffix = " studs",
        Flag = "LeafGameCollectRadius",
        Callback = function(v) settings.collectRadius = v end,
    })

    FarmTab:CreateSection("Auto Sell")
    FarmTab:CreateToggle({
        Name = "Auto Sell When Bag Full",
        CurrentValue = false,
        Flag = "LeafGameAutoSell",
        Callback = function(v) settings.autoSell = v end,
    })
    FarmTab:CreateSlider({
        Name = "Sell Threshold",
        Range = {0.5, 1},
        Increment = 0.05,
        CurrentValue = 0.9,
        Suffix = "x capacity",
        Flag = "LeafGameSellThreshold",
        Callback = function(v) settings.sellThreshold = v end,
    })
    FarmTab:CreateButton({
        Name = "Sell Now (Teleport to Dumpster)",
        Callback = function()
            local sold = sellLeaves()
            notify("🍂 Game", sold and "Sold leaves!" or "Nothing to sell")
        end,
    })

    FarmTab:CreateSection("Farm Loop")
    local farmStatus = FarmTab:CreateLabel("Farm: idle")

    FarmTab:CreateDropdown({
        Name = "Farm Zone",
        Options = ZONES,
        CurrentOption = {"Frontyard"},
        Flag = "LeafGameFarmZone",
        Callback = function(v) settings.farmZone = type(v) == "table" and v[1] or v end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Farm Loop (Collect > Sell > Repeat)",
        CurrentValue = false,
        Flag = "LeafGameAutoFarm",
        Callback = function(v)
            settings.autoFarmLoop = v
            -- Enable collect and sell together
            if v then
                settings.autoCollect = true
                settings.autoSell = true
            end
        end,
    })

    -- Tools tab
    local ToolTab = Window:CreateTab("Tools & Travel", 4483362458)

    ToolTab:CreateSection("Tool Select")
    local toolOptions = {"Hand", "Rake", "LeafBlower", "LeafVacuum", "Molotov", "LeafMower"}
    ToolTab:CreateDropdown({
        Name = "Equip Tool",
        Options = toolOptions,
        CurrentOption = {"Hand"},
        Flag = "LeafGameEquipTool",
        Callback = function(v)
            local tool = type(v) == "table" and v[1] or v
            settings.autoEquipTool = tool
            equipTool(tool)
        end,
    })

    ToolTab:CreateSection("Teleport")
    for _, zoneName in ipairs(ZONES) do
        ToolTab:CreateButton({
            Name = "TP: " .. zoneName,
            Callback = function()
                local pos = getZoneCenter(zoneName)
                if pos then
                    teleportTo(pos)
                    notify("🍂 Game", "Teleported to " .. zoneName)
                else
                    notify("🍂 Game", zoneName .. " not loaded yet")
                end
            end,
        })
    end

    ToolTab:CreateButton({
        Name = "TP: Nearest Dumpster",
        Callback = function()
            local _, _, root = getCharacter()
            if not root then return end
            local nearest, nearestDist
            for _, pos in ipairs(DUMPSTER_POSITIONS) do
                local dist = (pos - root.Position).Magnitude
                if not nearestDist or dist < nearestDist then
                    nearest = pos
                    nearestDist = dist
                end
            end
            if nearest then
                teleportTo(nearest)
                notify("🍂 Game", "Teleported to dumpster")
            end
        end,
    })

    -- Utility tab
    local UtilTab = Window:CreateTab("Utility", 4483362458)

    UtilTab:CreateSection("ESP")
    UtilTab:CreateToggle({
        Name = "Leaf ESP (Nearby)",
        CurrentValue = false,
        Flag = "LeafGameLeafEsp",
        Callback = function(v)
            settings.leafEsp = v
            if not v then clearHighlights() end
        end,
    })
    UtilTab:CreateToggle({
        Name = "Dumpster ESP",
        CurrentValue = false,
        Flag = "LeafGameDumpsterEsp",
        Callback = function(v)
            settings.dumpsterEsp = v
            if not v then clearHighlights() end
        end,
    })

    UtilTab:CreateSection("Stability")
    UtilTab:CreateToggle({
        Name = "Anti AFK",
        CurrentValue = true,
        Flag = "LeafGameAntiAfk",
        Callback = function(v) settings.antiAfk = v end,
    })
    UtilTab:CreateToggle({
        Name = "Auto Rejoin On Disconnect",
        CurrentValue = false,
        Flag = "LeafGameAutoRejoin",
        Callback = function(v) settings.autoRejoin = v end,
    })

    UtilTab:CreateSection("Info")
    local infoLabel = UtilTab:CreateLabel("Leaves: 0/25 | Cash: $0")

    -- ============================================================
    --   ANTI AFK
    -- ============================================================

    connect(player.Idled, function()
        if settings.antiAfk then
            VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
            task.wait(0.3)
            VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
        end
    end)

    -- ============================================================
    --   AUTO REJOIN
    -- ============================================================

    local rejoinPending = false
    connect(game:GetService("GuiService").ErrorMessageChanged, function(message)
        if settings.autoRejoin and not rejoinPending and message and message ~= "" then
            rejoinPending = true
            task.delay(2, function()
                local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, game.JobId, player)
                if not ok then
                    pcall(TeleportService.Teleport, TeleportService, game.PlaceId, player)
                end
                rejoinPending = false
            end)
        end
    end)

    -- ============================================================
    --   MAIN LOOP
    -- ============================================================

    local collectAt = 0
    local sellAt = 0
    local espAt = 0
    local returnPosition = nil
    local farmState = "idle" -- idle | collecting | selling | returning

    task.spawn(function()
        while running do
            local iterOk, iterErr = xpcall(function()
                local now = os.clock()
                local leaves = getCurrentLeaves()
                local capacity = getLeafCapacity()
                local cash = player:GetAttribute("Cash") or 0

                -- Update info
                pcall(function()
                    infoLabel:Set(string.format("Leaves: %d/%d | Cash: $%.2f | Zone: %s",
                        leaves, capacity, cash, player:GetAttribute("CurrentZone") or "None"))
                end)

                -- Auto Farm Loop logic
                if settings.autoFarmLoop then
                    if farmState == "idle" or farmState == "collecting" then
                        farmState = "collecting"
                        if isBagAtThreshold() then
                            -- Remember position and go sell
                            local _, _, root = getCharacter()
                            if root then returnPosition = root.CFrame end
                            farmState = "selling"
                            pcall(function()
                                farmStatus:Set("Farm: bag full → selling")
                            end)
                        else
                            -- Collect
                            if now - collectAt >= settings.collectInterval then
                                collectAt = now
                                local collected = collectLeaves()
                                pcall(function()
                                    collectStatus:Set(string.format("Collect: %d/%d | %d leaves nearby",
                                        leaves, capacity, collected))
                                end)
                                pcall(function()
                                    farmStatus:Set(string.format("Farm: collecting (%d/%d)",
                                        leaves, capacity))
                                end)
                            end
                        end
                    elseif farmState == "selling" then
                        local sold = sellLeaves()
                        if sold then
                            task.wait(0.5)
                            if getCurrentLeaves() <= 0 then
                                farmState = "returning"
                                pcall(function()
                                    farmStatus:Set("Farm: sold → returning to zone")
                                end)
                            end
                        end
                    elseif farmState == "returning" then
                        -- Return to farm zone or saved position
                        if returnPosition then
                            teleportTo(returnPosition)
                            returnPosition = nil
                        else
                            local pos = getZoneCenter(settings.farmZone)
                            if pos then teleportTo(pos) end
                        end
                        task.wait(0.3)
                        farmState = "collecting"
                        pcall(function()
                            farmStatus:Set("Farm: returned → collecting")
                        end)
                    end
                else
                    -- Standalone auto collect
                    if settings.autoCollect and now - collectAt >= settings.collectInterval then
                        collectAt = now
                        local collected = collectLeaves()
                        pcall(function()
                            collectStatus:Set(string.format("Collect: %d/%d | batch %d",
                                leaves, capacity, collected))
                        end)
                    elseif not settings.autoCollect then
                        pcall(function() collectStatus:Set("Collect: idle") end)
                    end

                    -- Standalone auto sell
                    if settings.autoSell and isBagAtThreshold() and now - sellAt >= 2 then
                        sellAt = now
                        sellLeaves()
                    end

                    if not settings.autoFarmLoop then
                        pcall(function() farmStatus:Set("Farm: idle") end)
                    end
                end

                -- ESP refresh
                if (settings.leafEsp or settings.dumpsterEsp) and now - espAt >= 1 then
                    espAt = now
                    refreshEsp()
                end

            end, function(msg)
                return debug.traceback(tostring(msg), 2)
            end)

            if not iterOk then
                warn("[RAVEN HUB][🍂 Game] loop error: " .. tostring(iterErr))
            end

            task.wait(0.15)
        end
    end)

    -- ============================================================
    --   CLEANUP
    -- ============================================================

    local function destroy()
        if not running then return end
        running = false
        clearHighlights()
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(connections)
        if environment.__RAVEN_LEAF_GAME and environment.__RAVEN_LEAF_GAME.Settings == settings then
            environment.__RAVEN_LEAF_GAME = nil
        end
    end

    environment.__RAVEN_LEAF_GAME = {
        Settings = settings,
        Destroy = destroy,
        CollectLeaves = collectLeaves,
        SellLeaves = sellLeaves,
        EquipTool = equipTool,
        TeleportTo = teleportTo,
        GetZoneCenter = getZoneCenter,
        GetNearbyLeaves = getNearbyLeaves,
        RefreshESP = refreshEsp,
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    notify("🍂 Game", "Module loaded! Open the Leaf Farm tab to begin.")
end
