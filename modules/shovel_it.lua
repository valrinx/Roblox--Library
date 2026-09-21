--[[
    RAVEN HUB | Experience Module
    Game: [Update 0.5] Shovel It!
    PlaceId: 133832344745984
    UniverseId: 9226697658
    Features: Fast Auto Dig | Auto Sell Snow | Auto Claim Rewards | Drills Manager | Teleports | Speed/Jump Boost | Drawing ESP
    Version: v1.0.0
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Camera = workspace.CurrentCamera

    local player = Players.LocalPlayer
    local env = (type(getgenv) == "function" and getgenv()) or _G

    -- Cleanup any existing instance of this module
    if type(env.__RAVEN_SHOVEL_IT) == "table" and type(env.__RAVEN_SHOVEL_IT.Destroy) == "function" then
        pcall(env.__RAVEN_SHOVEL_IT.Destroy)
    end

    local running = true
    local cleanupTasks = {}

    local function trackTask(fn)
        table.insert(cleanupTasks, fn)
    end

    -- Knit framework discovery
    local Knit
    pcall(function()
        Knit = require(RS:WaitForChild("Packages"):WaitForChild("Knit"))
    end)

    local ShovelController = Knit and Knit.GetController("ShovelController")
    local SnowController = Knit and Knit.GetController("SnowController")
    local CharController = Knit and Knit.GetController("CharacterController")
    local DataController = Knit and Knit.GetController("DataController")
    local DebounceController = Knit and Knit.GetController("DebounceController")

    local ShovelService = Knit and Knit.GetService("ShovelService")
    local SnowService = Knit and Knit.GetService("SnowService")
    local ItemService = Knit and Knit.GetService("ItemService")
    local InventoryService = Knit and Knit.GetService("InventoryService")
    local PlayerService = Knit and Knit.GetService("PlayerService")
    local DailyRewardsService = Knit and Knit.GetService("DailyRewardsService")
    local DrillService = Knit and Knit.GetService("DrillService")
    local SettingsService = Knit and Knit.GetService("SettingsService")

    -- Module State
    local state = {
        autoDig = false,
        digAura = false,
        digAuraRadius = 25,
        digAuraDelay = 0.05,
        mapVacuum = false,
        mapVacuumSpeed = 0.08,
        autoSell = false,
        autoClaim = false,
        autoDrill = false,
        speedMultiplier = 1,
        jumpMultiplier = 1,
        infiniteJump = false,
        noclip = false,
        espEnabled = false,
        espMaxDist = 300,
    }

    local function getRoot()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid()
        local char = player.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 1. AUTOMATION LOOPS
    -- ═══════════════════════════════════════════════════════════════

    -- Helper: Ensure Shovel is equipped in Slot 1
    local function ensureShovelEquipped()
        pcall(function()
            if player:FindFirstChild("SelectedSlot") and player.SelectedSlot.Value ~= 1 then
                if InventoryService then
                    InventoryService:SelectSlot(1):expect()
                end
            end
            if ShovelController and not ShovelController.Shovel then
                local char = player.Character
                if char and char:FindFirstChild("Shovel") then
                    ShovelController.Shovel = char.Shovel
                end
            end
        end)
    end

    -- Fast Auto Dig (Instant hit on current connected snow)
    task.spawn(function()
        while running do
            if state.autoDig and ShovelService then
                ensureShovelEquipped()
                local cs = SnowController and SnowController.ConnectedSnow
                if cs and cs.ID then
                    pcall(function()
                        ShovelService:Hit(cs.ID, workspace:GetServerTimeNow())
                    end)
                end
                task.wait(0.05)
            else
                task.wait(0.3)
            end
        end
    end)

    -- Proximity Dig Aura (Surrounding 25-stud vacuum burst with ProcessTouch)
    task.spawn(function()
        while running do
            if state.digAura and ShovelService and SnowController and type(SnowController.SnowParts) == "table" then
                ensureShovelEquipped()
                local root = getRoot()
                local rootPos = root and root.Position
                if rootPos then
                    local now = workspace:GetServerTimeNow()
                    local params = SnowController.Params
                    local parts = (params and workspace:GetPartBoundsInRadius(rootPos, state.digAuraRadius, params)) or {}
                    for _, v in ipairs(parts) do
                        if not state.digAura or not running then break end
                        local p = SnowController.Paths and SnowController.Paths[tonumber(v.Name)]
                        if p then
                            local g = SnowController.SnowGrid and SnowController.SnowGrid[p[1]]
                            if g then
                                local cell = g[p[2]] and g[p[2]][p[3]]
                                if cell and not cell.Broken then
                                    pcall(function()
                                        SnowController:ProcessTouch({ Bound = g, Snow = cell, Path = p })
                                        ShovelService:Hit(cell.ID, now)
                                    end)
                                end
                            end
                        end
                    end
                end
                task.wait(state.digAuraDelay)
            else
                task.wait(0.3)
            end
        end
    end)

    -- Ultra Fast Map Farm (High-Profit Grid Cluster Sweep + Instant Auto Sell)
    task.spawn(function()
        local startCFrame = nil
        while running do
            if state.mapVacuum and ShovelService and SnowController and type(SnowController.SnowGrid) == "table" then
                ensureShovelEquipped()
                local root = getRoot()
                if root and not startCFrame then
                    startCFrame = root.CFrame
                end

                -- Target high-multiplier grids (Sidewalk x98.9, Road x17.3, Construction x8.6)
                local highValueGrids = {}
                for _, g in pairs(SnowController.SnowGrid) do
                    if g.Center and (g.Type == "Sidewalk" or g.Type == "Road" or g.Type == "Construction") then
                        table.insert(highValueGrids, g)
                    end
                end

                for i, g in ipairs(highValueGrids) do
                    if not state.mapVacuum or not running then break end
                    root = getRoot()
                    if root and g.Center then
                        root.CFrame = CFrame.new(g.Center.X, g.Center.Y + 3.5, g.Center.Z)
                        task.wait(state.mapVacuumSpeed)

                        local now = workspace:GetServerTimeNow()
                        local params = SnowController.Params
                        local parts = (params and workspace:GetPartBoundsInRadius(root.Position, 25, params)) or {}
                        for _, v in ipairs(parts) do
                            local p = SnowController.Paths and SnowController.Paths[tonumber(v.Name)]
                            if p then
                                local grid = SnowController.SnowGrid[p[1]]
                                if grid then
                                    local cell = grid[p[2]] and grid[p[2]][p[3]]
                                    if cell and not cell.Broken then
                                        pcall(function()
                                            SnowController:ProcessTouch({ Bound = grid, Snow = cell, Path = p })
                                            ShovelService:Hit(cell.ID, now)
                                        end)
                                    end
                                end
                            end
                        end

                        -- Auto sell every 5 grids so inventory never caps
                        if i % 5 == 0 then
                            pcall(function()
                                if ItemService then ItemService:SellEverything():expect() end
                                if SnowService then SnowService:SellSnow():expect() end
                            end)
                        end
                    end
                end

                if not state.mapVacuum and startCFrame then
                    local r = getRoot()
                    if r then r.CFrame = startCFrame end
                    startCFrame = nil
                end
                task.wait(0.3)
            else
                if startCFrame then
                    local r = getRoot()
                    if r then r.CFrame = startCFrame end
                    startCFrame = nil
                end
                task.wait(0.3)
            end
        end
    end)

    -- Auto Sell Everything Loop (Snow + Items every 2.5s)
    task.spawn(function()
        while running do
            if state.autoSell then
                pcall(function()
                    if ItemService then
                        ItemService:SellEverything():expect()
                    end
                    if SnowService then
                        SnowService:SellSnow():expect()
                    end
                end)
                task.wait(2.5)
            else
                task.wait(1)
            end
        end
    end)

    -- Auto Claim Free Rewards & Daily Loop (Every 10 seconds)
    task.spawn(function()
        while running do
            if state.autoClaim then
                pcall(function()
                    if DailyRewardsService then
                        DailyRewardsService:ClaimDailyReward():expect()
                    end
                end)
                pcall(function()
                    if PlayerService then
                        for rewardId = 1, 9 do
                            PlayerService:ClaimPlayTimeReward(rewardId):expect()
                        end
                    end
                end)
                task.wait(10)
            else
                task.wait(2)
            end
        end
    end)

    -- Auto Drill Rewards Loop (Every 15 seconds)
    task.spawn(function()
        while running do
            if state.autoDrill and DrillService then
                pcall(function()
                    local drills = DrillService:GetDrills():expect()
                    if type(drills) == "table" then
                        for _, drill in ipairs(drills) do
                            local drillId = type(drill) == "table" and (drill.Id or drill.ID or drill.id) or drill
                            if drillId then
                                DrillService:ClaimDrillRewards(drillId):expect()
                            end
                        end
                    end
                end)
                task.wait(15)
            else
                task.wait(3)
            end
        end
    end)

    -- Character Mobility Loop (Speed & Jump Boost)
    local mobilityConn = RunService.Heartbeat:Connect(function()
        if not running then return end
        if CharController then
            if state.speedMultiplier > 1 then
                CharController.SpeedBoost = state.speedMultiplier
            end
            if state.jumpMultiplier > 1 then
                CharController.JumpBoost = state.jumpMultiplier
            end
        end

        if state.noclip then
            local char = player.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end
    end)
    trackTask(function() mobilityConn:Disconnect() end)

    -- Infinite Jump
    local jumpConn = UserInputService.JumpRequest:Connect(function()
        if state.infiniteJump and running then
            local hum = getHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)
    trackTask(function() jumpConn:Disconnect() end)

    -- ═══════════════════════════════════════════════════════════════
    -- 2. TELEPORTS DATA
    -- ═══════════════════════════════════════════════════════════════

    local teleportLocations = {
        -- Areas
        ["[Area] Spawn"] = Vector3.new(197.6, 5.0, 50.5),
        ["[Area] Sell Center"] = Vector3.new(12.7, 5.0, 0.0),
        ["[Area] Construction Site"] = Vector3.new(111.9, 5.0, 312.1),
        ["[Area] Toxic Border"] = Vector3.new(-25.9, 5.0, -756.3),

        -- Shops
        ["[Shop] Shovel Shop"] = Vector3.new(115.8, 5.0, 85.3),
        ["[Shop] Bag Shop"] = Vector3.new(178.5, 5.0, 95.2),
        ["[Shop] Gear Shop"] = Vector3.new(196.2, 5.0, -68.1),
        ["[Shop] Crafting Station"] = Vector3.new(241.0, 5.0, -69.5),
        ["[Shop] Mobile Shop"] = Vector3.new(154.7, 5.0, -61.4),
        ["[Shop] Vehicles"] = Vector3.new(127.8, 5.0, -58.0),

        -- NPCs & Upgrades
        ["[NPC] Upgrades"] = Vector3.new(141.4, 5.0, 90.2),
        ["[NPC] Relics"] = Vector3.new(18.9, 5.0, 16.9),
        ["[NPC] Blessings"] = Vector3.new(178.6, 5.0, 85.9),
        ["[NPC] Border Guard"] = Vector3.new(1.7, 5.0, -778.2),
        ["[NPC] Border Mechanic"] = Vector3.new(12.7, 5.0, -767.6),

        -- Quests
        ["[Quest] Main Quests"] = Vector3.new(18.4, 5.0, -16.1),
        ["[Quest] Grandma Quests"] = Vector3.new(-644.4, 5.0, -153.0),
        ["[Quest] Lumber Quests"] = Vector3.new(766.1, 5.0, -854.6),
        ["[Quest] Scientist Quests"] = Vector3.new(-1.2, 5.0, -745.5),
        ["[Quest] Farmers Quests"] = Vector3.new(182.3, 5.0, 685.4),
        ["[Quest] Construction Quests"] = Vector3.new(128.7, 5.0, 380.1),
        ["[Quest] Rex Quests"] = Vector3.new(576.0, 5.0, 295.0),
        ["[Quest] Tiger Quests"] = Vector3.new(-612.7, 5.0, 644.4),
        ["[Quest] Secret Quests (High)"] = Vector3.new(153.5, 162.0, 391.8),
    }

    local teleportOptions = {}
    for name in pairs(teleportLocations) do
        table.insert(teleportOptions, name)
    end
    table.sort(teleportOptions)

    local selectedTpTarget = teleportOptions[1]

    local function teleportTo(pos)
        local root = getRoot()
        if root then
            root.CFrame = CFrame.new(pos)
        end
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 3. DRAWING ESP (NPCs & Quests)
    -- ═══════════════════════════════════════════════════════════════

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local espCache = {}

    local function clearEsp()
        for _, entry in pairs(espCache) do
            if entry.text then pcall(function() entry.text:Remove() end) end
            if entry.dot then pcall(function() entry.dot:Remove() end) end
        end
        table.clear(espCache)
    end
    trackTask(clearEsp)

    if hasDrawing then
        local espConn = RunService.RenderStepped:Connect(function()
            if not running or not state.espEnabled then
                for _, entry in pairs(espCache) do
                    if entry.text then entry.text.Visible = false end
                    if entry.dot then entry.dot.Visible = false end
                end
                return
            end

            local root = getRoot()
            if not root then return end
            local rootPos = root.Position

            for name, worldPos in pairs(teleportLocations) do
                local entry = espCache[name]
                if not entry then
                    local text = Drawing.new("Text")
                    text.Size = 13
                    text.Center = true
                    text.Outline = true
                    text.Color = Color3.fromRGB(120, 220, 255)
                    text.OutlineColor = Color3.fromRGB(10, 10, 20)

                    local dot = Drawing.new("Circle")
                    dot.Radius = 3
                    dot.Filled = true
                    dot.Color = Color3.fromRGB(255, 200, 50)

                    entry = {text = text, dot = dot}
                    espCache[name] = entry
                end

                local dist = (worldPos - rootPos).Magnitude
                if dist <= state.espMaxDist then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(worldPos)
                    if onScreen and screenPos.Z > 0 then
                        entry.text.Position = Vector2.new(screenPos.X, screenPos.Y - 16)
                        entry.text.Text = string.format("%s [%dm]", name:gsub("%[.-%]%s*", ""), math.floor(dist))
                        entry.text.Visible = true

                        entry.dot.Position = Vector2.new(screenPos.X, screenPos.Y)
                        entry.dot.Visible = true
                    else
                        entry.text.Visible = false
                        entry.dot.Visible = false
                    end
                else
                    entry.text.Visible = false
                    entry.dot.Visible = false
                end
            end
        end)
        trackTask(function() espConn:Disconnect() end)
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 4. USER INTERFACE (TABS & CONTROLS)
    -- ═══════════════════════════════════════════════════════════════

    -- Tab: Automation
    local AutoTab = Window:CreateTab("Automation", 4483362458)
    AutoTab:CreateSection("Auto Shovel & Instant Dig")

    AutoTab:CreateToggle({
        Name = "Fast Auto Dig (Instant Hit)",
        CurrentValue = state.autoDig,
        Callback = function(val)
            state.autoDig = val
            if val and SettingsService then
                pcall(function()
                    SettingsService:SetSetting("AutoShovel", true):expect()
                end)
            end
        end,
    })

    AutoTab:CreateSection("⚡ Proximity Dig Aura (Surrounding Vacuum)")

    AutoTab:CreateToggle({
        Name = "Dig Aura (Surrounding Vacuum)",
        CurrentValue = state.digAura,
        Callback = function(val)
            state.digAura = val
        end,
    })

    AutoTab:CreateSlider({
        Name = "Aura Radius (Max 25 Studs)",
        Range = {5, 25},
        Increment = 1,
        CurrentValue = state.digAuraRadius,
        Callback = function(val)
            state.digAuraRadius = val
        end,
    })

    AutoTab:CreateSlider({
        Name = "Aura Delay (Seconds)",
        Range = {0.02, 0.3},
        Increment = 0.01,
        CurrentValue = state.digAuraDelay,
        Callback = function(val)
            state.digAuraDelay = val
        end,
    })

    AutoTab:CreateSection("🚀 Map-Wide Farm (Vacuum Map)")

    AutoTab:CreateToggle({
        Name = "Map Vacuum Aura (Whole Map Farm)",
        CurrentValue = state.mapVacuum,
        Callback = function(val)
            state.mapVacuum = val
        end,
    })

    AutoTab:CreateSlider({
        Name = "Sweep Step Speed",
        Range = {0.03, 0.2},
        Increment = 0.01,
        CurrentValue = state.mapVacuumSpeed,
        Callback = function(val)
            state.mapVacuumSpeed = val
        end,
    })

    AutoTab:CreateSection("💰 Auto Sell (Items & Snow)")

    AutoTab:CreateToggle({
        Name = "Auto Sell Everything (Snow + Items)",
        CurrentValue = state.autoSell,
        Callback = function(val)
            state.autoSell = val
        end,
    })

    AutoTab:CreateButton({
        Name = "Sell Everything Now",
        Callback = function()
            pcall(function()
                if ItemService then
                    ItemService:SellEverything():expect()
                end
                if SnowService then
                    SnowService:SellSnow():expect()
                end
            end)
        end,
    })

    AutoTab:CreateSection("Free Rewards & Drills")

    AutoTab:CreateToggle({
        Name = "Auto Claim Rewards (Playtime & Daily)",
        CurrentValue = state.autoClaim,
        Callback = function(val)
            state.autoClaim = val
        end,
    })

    AutoTab:CreateToggle({
        Name = "Auto Claim Drill Rewards",
        CurrentValue = state.autoDrill,
        Callback = function(val)
            state.autoDrill = val
        end,
    })

    -- Tab: Visuals
    local VisualsTab = Window:CreateTab("Visuals", 4483362458)
    VisualsTab:CreateSection("World & NPC ESP")

    VisualsTab:CreateToggle({
        Name = "Locations & NPCs ESP",
        CurrentValue = state.espEnabled,
        Callback = function(val)
            state.espEnabled = val
        end,
    })

    VisualsTab:CreateSlider({
        Name = "ESP Max Distance",
        Range = {100, 1500},
        Increment = 50,
        CurrentValue = state.espMaxDist,
        Callback = function(val)
            state.espMaxDist = val
        end,
    })

    -- Tab: Teleport
    local TeleportTab = Window:CreateTab("Teleport", 4483362458)
    TeleportTab:CreateSection("Map Teleports")

    TeleportTab:CreateDropdown({
        Name = "Target Location",
        Options = teleportOptions,
        CurrentOption = {selectedTpTarget},
        MultipleOptions = false,
        Callback = function(val)
            if type(val) == "table" and val[1] then
                selectedTpTarget = val[1]
            elseif type(val) == "string" then
                selectedTpTarget = val
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport to Selected",
        Callback = function()
            local pos = teleportLocations[selectedTpTarget]
            if pos then
                teleportTo(pos)
            end
        end,
    })

    TeleportTab:CreateSection("Quick Travel")

    TeleportTab:CreateButton({
        Name = "Go to Spawn",
        Callback = function()
            teleportTo(teleportLocations["[Area] Spawn"])
        end,
    })

    TeleportTab:CreateButton({
        Name = "Go to Sell Center",
        Callback = function()
            teleportTo(teleportLocations["[Area] Sell Center"])
        end,
    })

    TeleportTab:CreateButton({
        Name = "Go to Shovel Shop",
        Callback = function()
            teleportTo(teleportLocations["[Shop] Shovel Shop"])
        end,
    })

    TeleportTab:CreateButton({
        Name = "Go to Toxic Border",
        Callback = function()
            teleportTo(teleportLocations["[Area] Toxic Border"])
        end,
    })

    -- Tab: Player
    local PlayerTab = Window:CreateTab("Player", 4483362458)
    PlayerTab:CreateSection("Mobility & Enhancements")

    PlayerTab:CreateSlider({
        Name = "Speed Multiplier",
        Range = {1, 4},
        Increment = 0.5,
        CurrentValue = state.speedMultiplier,
        Callback = function(val)
            state.speedMultiplier = val
            if CharController and val == 1 then
                CharController.SpeedBoost = 1
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Jump Multiplier",
        Range = {1, 4},
        Increment = 0.5,
        CurrentValue = state.jumpMultiplier,
        Callback = function(val)
            state.jumpMultiplier = val
            if CharController and val == 1 then
                CharController.JumpBoost = 1
            end
        end,
    })

    PlayerTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = state.infiniteJump,
        Callback = function(val)
            state.infiniteJump = val
        end,
    })

    PlayerTab:CreateToggle({
        Name = "Noclip",
        CurrentValue = state.noclip,
        Callback = function(val)
            state.noclip = val
        end,
    })

    -- Sort tabs cleanly and select Automation tab
    pcall(function()
        if type(Window.SortTabs) == "function" then
            Window:SortTabs({"Overview", "Automation", "Visuals", "Teleport", "Player", "Settings"})
        end
        if type(AutoTab.Select) == "function" then
            AutoTab:Select()
        end
    end)

    -- Cleanup on unload
    local function destroyModule()
        running = false
        if CharController then
            CharController.SpeedBoost = 1
            CharController.JumpBoost = 1
        end
        for _, cleanup in ipairs(cleanupTasks) do
            pcall(cleanup)
        end
        table.clear(cleanupTasks)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyModule)
    end

    env.__RAVEN_SHOVEL_IT = {
        Destroy = destroyModule
    }
end
