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

    -- Dumpster positions (sell locations) - calculated safe spots OUTSIDE the prop
    local DUMPSTER_POSITIONS = {}
    pcall(function()
        local dumpsterFolder = workspace.Map.Dumpsters
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {player.Character or Instance.new("Folder")}

        for _, d in ipairs(dumpsterFolder:GetChildren()) do
            if d:IsA("Model") then
                local cf, size = d:GetBoundingBox()
                local center = cf.Position
                -- Stand outside the bounding box (+X side) with floor raycast
                local standOffset = size.X / 2 + 3.5
                local testPos = center + Vector3.new(standOffset, 5, 0)
                params.FilterDescendantsInstances = {player.Character or Instance.new("Folder"), d}
                local hit = workspace:Raycast(testPos, Vector3.new(0, -20, 0), params)
                local safeY = hit and (hit.Position.Y + 3) or (center.Y + 1)
                table.insert(DUMPSTER_POSITIONS, Vector3.new(center.X + standOffset, safeY, center.Z))
            end
        end
    end)
    -- Hardcoded fallback (safe positions confirmed via raycast)
    if #DUMPSTER_POSITIONS == 0 then
        DUMPSTER_POSITIONS = {
            Vector3.new(128, 65.3, -52.7),
            Vector3.new(154.8, 65.3, -118),
            Vector3.new(55.2, 65.3, -50.3),
        }
    end

    -- Settings
    local settings = {
        autoCollect = false,
        collectInterval = 0.5,
        collectRadius = 30,
        noCooldown = false,
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

    -- TRUE AURA COLLECT: supports multiple tools
    -- Hand: calls tryCollect (1-3 per grab, 0.5s cooldown)
    -- Vacuum: calls LeafSim.vacuumAim (30+ per second, fastest)
    -- Rake: calls LeafSim.rake to pile leaves then Hand collects
    local VIM = game:GetService("VirtualInputManager")
    local tryCollectFunc = nil
    local U16_INDEX = 1 -- upvalue index for the "hovered leaf" in tryCollect
    local LeafSimModule = nil

    -- Find tryCollect from LeafHover in GC
    pcall(function()
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "function" and not isexecutorclosure(obj) then
                local ok, constants = pcall(debug.getconstants, obj)
                if ok then
                    local has1, has2 = false, false
                    for _, c in pairs(constants) do
                        if c == "HandCooldown" then has1 = true end
                        if c == "collectMany" then has2 = true end
                    end
                    if has1 and has2 then
                        local info = debug.getinfo(obj)
                        if info and info.source and info.source:find("LeafHover") then
                            tryCollectFunc = obj
                            break
                        end
                    end
                end
            end
        end
    end)

    pcall(function()
        LeafSimModule = require(player.PlayerScripts:WaitForChild("LeafSim", 5))
    end)

    local function collectLeaves()
        if isBagFull() then return 0 end

        local _, _, root = getCharacter()
        if not root then return 0 end

        local leavesFolder = workspace:FindFirstChild("Leaves")
        if not leavesFolder then return 0 end

        local collectMethod = settings.autoEquipTool

        -- VACUUM METHOD: fastest (30+ leaves/sec)
        if collectMethod == "LeafVacuum" and LeafSimModule and LeafSimModule.vacuumAim then
            player:SetAttribute("SelectedTool", "LeafVacuum")
            player:SetAttribute("OwnsLeafVacuum", true)
            LeafSimModule.vacuumAim(root.Position + root.CFrame.LookVector * 5)
            task.wait(0.3)
            LeafSimModule.vacuumStop()
            return 10

        -- RAKE METHOD: pile leaves then hand-collect
        elseif collectMethod == "Rake" and LeafSimModule and LeafSimModule.rake then
            player:SetAttribute("SelectedTool", "Rake")
            LeafSimModule.rake(root.Position)
            task.wait(0.2)
            -- After raking, do a hand collect on the pile
            if tryCollectFunc then
                local nearest
                for _, leaf in ipairs(leavesFolder:GetChildren()) do
                    if leaf:IsA("BasePart") and leaf.Parent and (leaf.Position - root.Position).Magnitude <= 5 then
                        nearest = leaf
                        break
                    end
                end
                if nearest then
                    local orig = player:GetAttribute("SelectedTool")
                    player:SetAttribute("SelectedTool", "Hand")
                    debug.setupvalue(tryCollectFunc, U16_INDEX, nearest)
                    tryCollectFunc()
                    player:SetAttribute("SelectedTool", orig or "Rake")
                end
            end
            return 5

        -- HAND METHOD: aura via tryCollect (1-3 per grab)
        else
            if not tryCollectFunc then return 0 end
            if player:GetAttribute("HandCooldown") then
                if settings.noCooldown then
                    player:SetAttribute("HandCooldown", false)
                else
                    return -1
                end
            end

            local nearest, nearestDist
            for _, leaf in ipairs(leavesFolder:GetChildren()) do
                if leaf:IsA("BasePart") and leaf.Parent then
                    local dist = (leaf.Position - root.Position).Magnitude
                    if dist <= settings.collectRadius and (not nearestDist or dist < nearestDist) then
                        nearest = leaf
                        nearestDist = dist
                    end
                end
            end
            if not nearest then return 0 end

            local originalTool = player:GetAttribute("SelectedTool") or "Hand"
            if originalTool ~= "Hand" then
                player:SetAttribute("SelectedTool", "Hand")
            end

            debug.setupvalue(tryCollectFunc, U16_INDEX, nearest)
            tryCollectFunc()

            if originalTool ~= "Hand" then
                player:SetAttribute("SelectedTool", originalTool)
            end

            if settings.noCooldown then
                player:SetAttribute("HandCooldown", false)
            end
            return 1
        end
    end

    -- Sell leaves: TP within 15 studs of unlocked dumpster and fire EmptyBackpack.
    -- Server proximity check is ~15 studs. No need to enter the dumpster or click.
    local function sellLeaves()
        if getCurrentLeaves() <= 0 then return false end

        local _, _, root = getCharacter()
        if not root then return false end

        -- Find Frontyard dumpster (nearest to spawn, always unlocked)
        local spawnPos = Vector3.new(58, 62, -74)
        local nearestModel, nearestDist
        pcall(function()
            for _, d in ipairs(workspace.Map.Dumpsters:GetChildren()) do
                if d:IsA("Model") then
                    local dist = (d:GetPivot().Position - spawnPos).Magnitude
                    if not nearestDist or dist < nearestDist then
                        nearestModel = d
                        nearestDist = dist
                    end
                end
            end
        end)

        if not nearestModel then return false end

        local center = nearestModel:GetPivot().Position
        local distToPlayer = (center - root.Position).Magnitude

        -- Only TP if too far (>14 studs from dumpster)
        local savedPos
        if distToPlayer > 14 then
            savedPos = root.CFrame
            teleportTo(center + Vector3.new(10, 1.5, 0)) -- 10 studs away, safe
            task.wait(0.3)
        end

        -- Fire sell remote
        pcall(function()
            EmptyBackpackRemote:FireServer()
        end)
        task.wait(0.3)

        -- TP back to original position if we moved
        if savedPos then
            teleportTo(savedPos)
        end

        return getCurrentLeaves() == 0
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

    FarmTab:CreateDropdown({
        Name = "Collect Method",
        Options = {"Hand (1-3/grab)", "LeafVacuum (FAST 30+/s)", "Rake (pile+grab)"},
        CurrentOption = {"Hand (1-3/grab)"},
        Flag = "LeafGameCollectMethod",
        Callback = function(v)
            local val = type(v) == "table" and v[1] or v
            if val:find("Vacuum") then
                settings.autoEquipTool = "LeafVacuum"
            elseif val:find("Rake") then
                settings.autoEquipTool = "Rake"
            else
                settings.autoEquipTool = "Hand"
            end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Collect Leaves",
        CurrentValue = false,
        Flag = "LeafGameAutoCollect",
        Callback = function(v) settings.autoCollect = v end,
    })
    FarmTab:CreateSlider({
        Name = "Collect Interval",
        Range = {0.1, 3},
        Increment = 0.05,
        CurrentValue = 0.5,
        Suffix = " s",
        Flag = "LeafGameCollectInterval",
        Callback = function(v) settings.collectInterval = v end,
    })
    FarmTab:CreateToggle({
        Name = "No Cooldown (Instant Grab)",
        CurrentValue = false,
        Flag = "LeafGameNoCooldown",
        Callback = function(v) settings.noCooldown = v end,
    })
    FarmTab:CreateLabel("Collects 1-3 leaves per grab (Hand Grasp upgrade)")
    FarmTab:CreateSlider({
        Name = "Collect Radius (Aura)",
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
