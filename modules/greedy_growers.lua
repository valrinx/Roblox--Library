-- ═══════════════════════════════════════════════════════════
-- Greedy Growers | RAVEN HUB Module v1.0.2
-- PlaceId: 74102906764176 | GameId: 10440833423
-- FIX: task.wait loops instead of Heartbeat (no lag)
-- FIX: cached scans refresh every 2s (not every frame)
-- ═══════════════════════════════════════════════════════════
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")

    local Player = Players.LocalPlayer
    local running = true

    -- ═══════════ Settings ═══════════
    local settings = {
        autoCollect = false,
        collectDelay = 0.3,
        autoSell = false,
        sellInterval = 5,
        autoPlant = false,
        autoBuySeed = false,
        selectedSeed = "Pine",
        buyDelay = 2,
        antiMeteor = false,
        meteorFleeDist = 80,
        autoSpeed = false,
        walkSpeed = 32,
    }

    -- ═══════════ Cached Scans ═══════════
    local cache = {
        fruits = {},
        sell = nil,
        seeds = {},
        plants = {},
        growAll = nil,
        collectAll = nil,
        lastScan = 0,
        SCAN_INTERVAL = 2,
    }

    local function refreshCache()
        local now = tick()
        if now - cache.lastScan < cache.SCAN_INTERVAL then return end
        cache.lastScan = now

        cache.fruits = {}
        cache.seeds = {}
        cache.plants = {}
        cache.sell = nil
        cache.growAll = nil
        cache.collectAll = nil

        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local action = pp.ActionText
                local obj = pp.ObjectText
                if action == "Collect" then
                    local part = pp:FindFirstAncestorWhichIsA("BasePart")
                    if part then
                        table.insert(cache.fruits, {prompt = pp, part = part})
                    end
                elseif action == "Sell" and not cache.sell then
                    cache.sell = pp
                elseif action == "Buy" then
                    if obj == "Grow All Fruits" and not cache.growAll then
                        cache.growAll = pp
                    elseif obj == "Collect All Fruits" and not cache.collectAll then
                        cache.collectAll = pp
                    elseif obj:find("Seed") then
                        local part = pp:FindFirstAncestorWhichIsA("BasePart")
                        if part then
                            table.insert(cache.seeds, {prompt = pp, part = part, name = obj})
                        end
                    end
                elseif action == "Plant Seed" then
                    local part = pp:FindFirstAncestorWhichIsA("BasePart")
                    if part then
                        table.insert(cache.plants, {prompt = pp, part = part})
                    end
                end
            end
        end
    end

    -- Force first scan immediately
    cache.lastScan = 0
    refreshCache()

    -- ═══════════ Utility ═══════════
    local function getRoot()
        local c = Player.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid()
        local c = Player.Character
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function tpTo(pos)
        local root = getRoot()
        if root then root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
    end

    local function safeFire(pp)
        if not pp then return end
        pcall(function() fireproximityprompt(pp, 0) end)
    end

    -- ═══════════ Thread Manager ═══════════
    local threads = {}
    local function startThread(key, func)
        if threads[key] then
            threads[key] = nil  -- signal old thread to stop
        end
        task.spawn(function()
            threads[key] = true
            func(function() return threads[key] == true and running end)
            threads[key] = nil
        end)
    end

    local function stopThread(key)
        threads[key] = nil
    end

    -- ═══════════════════════════════════════════════════════════
    --   UI TABS
    -- ═══════════════════════════════════════════════════════════

    -- ─── Tab 1: Collect ───
    local CollectTab = Window:CreateTab("Collect", "apple")
    CollectTab:CreateSection("Auto Collect Fruit")

    CollectTab:CreateToggle({
        Name = "Auto Collect",
        CurrentValue = false,
        Flag = "GGAutoCollect",
        Callback = function(v)
            settings.autoCollect = v
            if v then
                startThread("autoCollect", function(isActive)
                    while isActive() do
                        refreshCache()
                        for _, f in ipairs(cache.fruits) do
                            if not isActive() then break end
                            tpTo(f.part.Position)
                            task.wait(0.15)
                            safeFire(f.prompt)
                            task.wait(settings.collectDelay)
                        end
                        task.wait(1)
                    end
                end)
            else
                stopThread("autoCollect")
            end
        end,
    })

    CollectTab:CreateSlider({
        Name = "Collect Delay",
        Range = {0.1, 2},
        Increment = 0.1,
        CurrentValue = 0.3,
        Suffix = " s",
        Flag = "GGCollectDelay",
        Callback = function(v) settings.collectDelay = v end,
    })

    CollectTab:CreateButton({
        Name = "Collect All (One-shot)",
        Callback = function()
            refreshCache()
            if cache.collectAll then
                local part = cache.collectAll:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(cache.collectAll)
            else
                for _, f in ipairs(cache.fruits) do
                    tpTo(f.part.Position)
                    task.wait(0.15)
                    safeFire(f.prompt)
                    task.wait(0.2)
                end
            end
        end,
    })

    -- ─── Tab 2: Sell ───
    local SellTab = Window:CreateTab("Sell", "dollar-sign")
    SellTab:CreateSection("Auto Sell")

    SellTab:CreateToggle({
        Name = "Auto Sell",
        CurrentValue = false,
        Flag = "GGAutoSell",
        Callback = function(v)
            settings.autoSell = v
            if v then
                startThread("autoSell", function(isActive)
                    while isActive() do
                        refreshCache()
                        if cache.sell then
                            local part = cache.sell:FindFirstAncestorWhichIsA("BasePart")
                            if part then tpTo(part.Position) end
                            task.wait(0.2)
                            safeFire(cache.sell)
                        end
                        task.wait(settings.sellInterval)
                    end
                end)
            else
                stopThread("autoSell")
            end
        end,
    })

    SellTab:CreateSlider({
        Name = "Sell Interval",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = 5,
        Suffix = " s",
        Flag = "GGSellInterval",
        Callback = function(v) settings.sellInterval = v end,
    })

    SellTab:CreateButton({
        Name = "Sell Now",
        Callback = function()
            refreshCache()
            if cache.sell then
                local part = cache.sell:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(cache.sell)
            end
        end,
    })

    -- ─── Tab 3: Plant ───
    local PlantTab = Window:CreateTab("Plant", "sprout")
    PlantTab:CreateSection("Auto Plant")

    PlantTab:CreateToggle({
        Name = "Auto Plant Seeds",
        CurrentValue = false,
        Flag = "GGAutoPlant",
        Callback = function(v)
            settings.autoPlant = v
            if v then
                startThread("autoPlant", function(isActive)
                    while isActive() do
                        refreshCache()
                        for _, p in ipairs(cache.plants) do
                            if not isActive() then break end
                            tpTo(p.part.Position)
                            task.wait(0.15)
                            safeFire(p.prompt)
                            task.wait(0.5)
                        end
                        task.wait(1)
                    end
                end)
            else
                stopThread("autoPlant")
            end
        end,
    })

    PlantTab:CreateButton({
        Name = "Grow All",
        Callback = function()
            refreshCache()
            if cache.growAll then
                local part = cache.growAll:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(cache.growAll)
            end
        end,
    })

    PlantTab:CreateButton({
        Name = "Plant All (One-shot)",
        Callback = function()
            refreshCache()
            for _, p in ipairs(cache.plants) do
                tpTo(p.part.Position)
                task.wait(0.15)
                safeFire(p.prompt)
                task.wait(0.5)
            end
        end,
    })

    -- ─── Tab 4: Buy Seeds ───
    local BuyTab = Window:CreateTab("Buy Seeds", "shopping-cart")
    BuyTab:CreateSection("Auto Buy Seeds")

    BuyTab:CreateDropdown({
        Name = "Seed Type",
        Options = {"Pine", "Oak", "Lemon", "Mango", "Apple", "Fig"},
        CurrentOption = {"Pine"},
        MultipleOptions = false,
        Flag = "GGSeedType",
        Callback = function(value)
            settings.selectedSeed = type(value) == "table" and value[1] or value
        end,
    })

    BuyTab:CreateToggle({
        Name = "Auto Buy Selected Seed",
        CurrentValue = false,
        Flag = "GGAutoBuySeed",
        Callback = function(v)
            settings.autoBuySeed = v
            if v then
                startThread("autoBuySeed", function(isActive)
                    while isActive() do
                        refreshCache()
                        for _, s in ipairs(cache.seeds) do
                            if not isActive() then break end
                            if s.name:lower():find(settings.selectedSeed:lower()) then
                                tpTo(s.part.Position)
                                task.wait(0.15)
                                safeFire(s.prompt)
                                task.wait(settings.buyDelay)
                            end
                        end
                        task.wait(1)
                    end
                end)
            else
                stopThread("autoBuySeed")
            end
        end,
    })

    BuyTab:CreateSlider({
        Name = "Buy Delay",
        Range = {1, 10},
        Increment = 1,
        CurrentValue = 2,
        Suffix = " s",
        Flag = "GGBuyDelay",
        Callback = function(v) settings.buyDelay = v end,
    })

    BuyTab:CreateButton({
        Name = "Buy Selected Seed Now",
        Callback = function()
            refreshCache()
            for _, s in ipairs(cache.seeds) do
                if s.name:lower():find(settings.selectedSeed:lower()) then
                    tpTo(s.part.Position)
                    task.wait(0.15)
                    safeFire(s.prompt)
                    break
                end
            end
        end,
    })

    -- ─── Tab 5: Weather ───
    local WeatherTab = Window:CreateTab("Weather", "cloud-lightning")
    WeatherTab:CreateSection("Anti-Meteor")

    WeatherTab:CreateToggle({
        Name = "Anti-Meteor (Auto Flee)",
        CurrentValue = false,
        Flag = "GGAntiMeteor",
        Callback = function(v)
            settings.antiMeteor = v
            if v then
                startThread("antiMeteor", function(isActive)
                    while isActive() do
                        for _, obj in ipairs(game:GetService("Workspace"):GetChildren()) do
                            if not isActive() then break end
                            local n = obj.Name:lower()
                            if n:find("meteor") or n:find("storm") or n:find("lightning") then
                                local root = getRoot()
                                if root then
                                    local fleeDir = root.CFrame.LookVector * settings.meteorFleeDist
                                    tpTo(root.Position + fleeDir)
                                end
                                break
                            end
                        end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("antiMeteor")
            end
        end,
    })

    WeatherTab:CreateSlider({
        Name = "Flee Distance",
        Range = {20, 200},
        Increment = 10,
        CurrentValue = 80,
        Suffix = " studs",
        Flag = "GGFleeDist",
        Callback = function(v) settings.meteorFleeDist = v end,
    })

    WeatherTab:CreateButton({
        Name = "Check Weather",
        Callback = function()
            local danger = false
            for _, obj in ipairs(game:GetService("Workspace"):GetChildren()) do
                local n = obj.Name:lower()
                if n:find("meteor") or n:find("storm") or n:find("lightning") then
                    danger = true; break
                end
            end
            pcall(function()
                Window:Notify({
                    Title = "Weather",
                    Content = danger and "DANGER: Meteor/Storm!" or "Safe",
                    Duration = 3,
                })
            end)
        end,
    })

    -- ─── Tab 6: Player ───
    local PlayerTab = Window:CreateTab("Player", "user")
    PlayerTab:CreateSection("Speed")

    PlayerTab:CreateToggle({
        Name = "Auto Set Speed",
        CurrentValue = false,
        Flag = "GGAutoSpeed",
        Callback = function(v)
            settings.autoSpeed = v
            if v then
                startThread("autoSpeed", function(isActive)
                    while isActive() do
                        local hum = getHumanoid()
                        if hum then hum.WalkSpeed = settings.walkSpeed end
                        task.wait(1)
                    end
                end)
            else
                stopThread("autoSpeed")
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Walk Speed",
        Range = {16, 200},
        Increment = 1,
        CurrentValue = 32,
        Suffix = " spd",
        Flag = "GGWalkSpeed",
        Callback = function(v)
            settings.walkSpeed = v
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = v end
        end,
    })

    PlayerTab:CreateButton({
        Name = "Set Speed Now",
        Callback = function()
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = settings.walkSpeed end
        end,
    })

    -- ─── Tab 7: Settings ───
    local SettingsTab = Window:CreateTab("Settings", "settings")
    SettingsTab:CreateSection("Info")
    SettingsTab:CreateLabel("Greedy Growers v1.0.2 | RAVEN HUB")

    SettingsTab:CreateSection("Debug")
    SettingsTab:CreateButton({
        Name = "Scan Game",
        Callback = function()
            refreshCache()
            pcall(function()
                Window:Notify({
                    Title = "GG Debug",
                    Content = string.format(
                        "Fruits:%d Sell:%s Seeds:%d Plants:%d",
                        #cache.fruits, tostring(cache.sell ~= nil),
                        #cache.seeds, #cache.plants
                    ),
                    Duration = 5,
                })
            end)
        end,
    })

    SettingsTab:CreateSection("Server")
    SettingsTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            TeleportService:Teleport(game.PlaceId, Player)
        end,
    })

    SettingsTab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            pcall(function()
                local tps = HttpService:JSONDecode(
                    game:HttpGet("https://games.roblox.com/v1/games/"
                        .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=10")
                )
                if tps and tps.data then
                    for _, srv in ipairs(tps.data) do
                        if srv.id ~= game.JobId and srv.playing < srv.maxPlayers then
                            TeleportService:TeleportToPlaceInstance(
                                game.PlaceId, srv.id, Player
                            )
                            break
                        end
                    end
                end
            end)
        end,
    })

    -- ═══════════ Cleanup ═══════════
    local function destroy()
        running = false
        for key, _ in pairs(threads) do
            threads[key] = nil
        end
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    pcall(function()
        Window:Notify({
            Title = "Greedy Growers",
            Content = "v1.0.2 loaded! " .. #cache.fruits .. " fruits",
            Duration = 3,
        })
    end)
end
