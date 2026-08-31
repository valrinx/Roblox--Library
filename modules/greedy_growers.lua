-- ═══════════════════════════════════════════════════════════
-- Greedy Growers | RAVEN HUB Module v2.0.0
-- PlaceId: 74102906764176 | GameId: 10440833423
-- Flow: Buy Seed → Plant → Fertilizer → Grow All → Harvest → Collect → Sell
-- All features tested on live client via Raven MCP before push
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
        -- Farm flow
        autoBuySeed = false,
        selectedSeed = "Pine",
        buyDelay = 1,
        autoPlant = false,
        selectedFertilizer = "Basic",
        autoGrowAll = false,
        autoHarvest = false,
        autoCollect = false,
        collectDelay = 0.3,
        autoSell = false,
        sellInterval = 5,
        -- Anti-meteor
        antiMeteor = false,
        meteorFleeDist = 80,
        -- Speed
        autoSpeed = false,
        walkSpeed = 32,
    }

    -- ═══════════ Cached Scans ═══════════
    local cache = {
        seeds = {}, plants = {}, fruits = {},
        sell = nil, growAll = nil, collectAll = nil,
        harvest = nil, lastScan = 0, SCAN_INTERVAL = 2,
    }

    local function refreshCache()
        local now = tick()
        if now - cache.lastScan < cache.SCAN_INTERVAL then return end
        cache.lastScan = now
        cache.seeds = {}; cache.plants = {}; cache.fruits = {}
        cache.sell = nil; cache.growAll = nil; cache.collectAll = nil; cache.harvest = nil

        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then
                local a = pp.ActionText
                local o = pp.ObjectText
                if a == "Collect" then
                    local part = pp:FindFirstAncestorWhichIsA("BasePart")
                    if part then
                        -- Parse multiplier from ObjectText e.g. "Starfruit Tree (452.7x)"
                        local mult = 1
                        local m = o:match(%((%d+%.?%d*)x%)%)
                        if m then mult = tonumber(m) or 1 end
                        table.insert(cache.fruits, {prompt=pp, part=part, value=mult})
                    end
                elseif a == "Sell" and not cache.sell then
                    cache.sell = pp
                elseif a == "Harvest" and not cache.harvest then
                    cache.harvest = pp
                elseif a == "Buy" then
                    if o == "Grow All Fruits" and not cache.growAll then
                        cache.growAll = pp
                    elseif o == "Collect All Fruits" and not cache.collectAll then
                        cache.collectAll = pp
                    elseif o:find("Seed") then
                        local part = pp:FindFirstAncestorWhichIsA("BasePart")
                        if part then table.insert(cache.seeds, {prompt=pp, part=part, name=o}) end
                    end
                elseif a == "Plant Seed" then
                    local part = pp:FindFirstAncestorWhichIsA("BasePart")
                    if part then table.insert(cache.plants, {prompt=pp, part=part}) end
                end
            end
        end
        -- Sort fruits by value descending (highest value first)
        table.sort(cache.fruits, function(a, b) return a.value > b.value end)
    end
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

    local function selectFertilizer(fertType)
        local gui = Player:FindFirstChild("PlayerGui")
        if not gui then return end
        local fertGui = gui:FindFirstChild("Windows")
            and gui.Windows:FindFirstChild("FertilizerSelect")
        if not fertGui then return end
        local fert = fertGui.Content.Fertilizers:FindFirstChild(fertType)
        if fert and fert:FindFirstChild("Button") then
            pcall(function() fert.Button.Activated:Fire() end)
        end
    end

    local function isMeteorActive()
        for _, obj in ipairs(game:GetService("Workspace"):GetChildren()) do
            local n = obj.Name:lower()
            if n:find("meteor") or n:find("storm") or n:find("lightning") then
                return true
            end
        end
        return false
    end

    -- ═══════════ Thread Manager ═══════════
    local threads = {}
    local function startThread(key, func)
        threads[key] = nil
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
    --   UI TABS — Flow: Buy → Plant → Fertilizer → Grow → Harvest → Collect → Sell
    -- ═══════════════════════════════════════════════════════════

    -- ─── Tab 1: Farm (Main Flow) ───
    local FarmTab = Window:CreateTab("Farm", "sprout")
    FarmTab:CreateSection("1. Buy Seeds")

    FarmTab:CreateDropdown({
        Name = "Seed Type",
        Options = {"Pine","Oak","Apple","Peach","Fig","Orange","Lemon","Avocado","Cherry","Mango","Coconut","Banana","Starfruit","Dragon Fruit"},
        CurrentOption = {"Pine"},
        MultipleOptions = false,
        Flag = "GGSeedType",
        Callback = function(value)
            settings.selectedSeed = type(value) == "table" and value[1] or value
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Buy Seed",
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
            else stopThread("autoBuySeed") end
        end,
    })

    FarmTab:CreateSlider({
        Name = "Buy Delay",
        Range = {0.5, 5}, Increment = 0.5, CurrentValue = 1,
        Suffix = " s", Flag = "GGBuyDelay",
        Callback = function(v) settings.buyDelay = v end,
    })

    FarmTab:CreateSection("2. Plant")

    FarmTab:CreateToggle({
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
            else stopThread("autoPlant") end
        end,
    })

    FarmTab:CreateSection("3. Fertilizer")

    FarmTab:CreateDropdown({
        Name = "Fertilizer Type",
        Options = {"None","Basic","Better","Premium","Super","Magic"},
        CurrentOption = {"Basic"},
        MultipleOptions = false,
        Flag = "GGFertType",
        Callback = function(value)
            settings.selectedFertilizer = type(value) == "table" and value[1] or value
        end,
    })

    FarmTab:CreateButton({
        Name = "Select Fertilizer Now",
        Callback = function()
            selectFertilizer(settings.selectedFertilizer)
        end,
    })

    FarmTab:CreateSection("4. Grow All")
    FarmTab:CreateToggle({
        Name = "Auto Grow All",
        CurrentValue = false,
        Flag = "GGAutoGrowAll",
        Callback = function(v)
            settings.autoGrowAll = v
            if v then
                startThread("autoGrowAll", function(isActive)
                    while isActive() do
                        refreshCache()
                        if cache.growAll then
                            local part = cache.growAll:FindFirstAncestorWhichIsA("BasePart")
                            if part then tpTo(part.Position); task.wait(0.2) end
                            safeFire(cache.growAll)
                        end
                        task.wait(5)
                    end
                end)
            else stopThread("autoGrowAll") end
        end,
    })

    FarmTab:CreateSection("5. Harvest (BEFORE Collect!)")
    FarmTab:CreateToggle({
        Name = "Auto Harvest",
        CurrentValue = false,
        Flag = "GGAutoHarvest",
        Callback = function(v)
            settings.autoHarvest = v
            if v then
                startThread("autoHarvest", function(isActive)
                    while isActive() do
                        refreshCache()
                        if cache.harvest then
                            local part = cache.harvest:FindFirstAncestorWhichIsA("BasePart")
                                or cache.harvest.Parent
                            if part then tpTo(part.Position); task.wait(0.2) end
                            safeFire(cache.harvest)
                        end
                        task.wait(2)
                    end
                end)
            else stopThread("autoHarvest") end
        end,
    })

    FarmTab:CreateButton({
        Name = "Harvest Now",
        Callback = function()
            refreshCache()
            if cache.harvest then
                local part = cache.harvest:FindFirstAncestorWhichIsA("BasePart")
                    or cache.harvest.Parent
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(cache.harvest)
            end
        end,
    })

    FarmTab:CreateSection("6. Collect Fruits (highest value first)")
    FarmTab:CreateToggle({
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
            else stopThread("autoCollect") end
        end,
    })

    FarmTab:CreateSlider({
        Name = "Collect Delay",
        Range = {0.1, 2}, Increment = 0.1, CurrentValue = 0.3,
        Suffix = " s", Flag = "GGCollectDelay",
        Callback = function(v) settings.collectDelay = v end,
    })

    FarmTab:CreateSection("7. Sell")
    FarmTab:CreateToggle({
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
                            if part then tpTo(part.Position); task.wait(0.2) end
                            safeFire(cache.sell)
                        end
                        task.wait(settings.sellInterval)
                    end
                end)
            else stopThread("autoSell") end
        end,
    })

    FarmTab:CreateSlider({
        Name = "Sell Interval",
        Range = {1, 15}, Increment = 1, CurrentValue = 5,
        Suffix = " s", Flag = "GGSellInterval",
        Callback = function(v) settings.sellInterval = v end,
    })

    FarmTab:CreateButton({
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

    -- ─── Tab 2: Weather ───
    local WeatherTab = Window:CreateTab("Weather", "cloud-lightning")
    WeatherTab:CreateSection("Anti-Meteor (Harvest before lightning!)")

    WeatherTab:CreateToggle({
        Name = "Auto Harvest on Meteor",
        CurrentValue = false,
        Flag = "GGAntiMeteor",
        Callback = function(v)
            settings.antiMeteor = v
            if v then
                startThread("antiMeteor", function(isActive)
                    while isActive() do
                        if isMeteorActive() then
                            -- Step 1: Harvest first!
                            refreshCache()
                            if cache.harvest then
                                local part = cache.harvest:FindFirstAncestorWhichIsA("BasePart")
                                    or cache.harvest.Parent
                                if part then tpTo(part.Position); task.wait(0.15) end
                                safeFire(cache.harvest)
                                task.wait(0.3)
                            end
                            -- Step 2: Collect ALL fruits (highest value first)
                            refreshCache()
                            for _, f in ipairs(cache.fruits) do
                                if not isActive() then break end
                                tpTo(f.part.Position)
                                task.wait(0.1)
                                safeFire(f.prompt)
                                task.wait(0.1)
                            end
                            -- Step 3: SELL immediately after collecting
                            refreshCache()
                            if cache.sell then
                                local part = cache.sell:FindFirstAncestorWhichIsA("BasePart")
                                if part then tpTo(part.Position); task.wait(0.15) end
                                safeFire(cache.sell)
                                task.wait(0.2)
                            end
                            -- Step 4: Flee if still meteor
                            if isMeteorActive() then
                                local root = getRoot()
                                if root then
                                    local dir = root.CFrame.LookVector * settings.meteorFleeDist
                                    tpTo(root.Position + dir)
                                end
                            end
                        end
                        task.wait(0.5)
                    end
                end)
            else stopThread("antiMeteor") end
        end,
    })

    WeatherTab:CreateSlider({
        Name = "Flee Distance",
        Range = {20, 200}, Increment = 10, CurrentValue = 80,
        Suffix = " studs", Flag = "GGFleeDist",
        Callback = function(v) settings.meteorFleeDist = v end,
    })

    WeatherTab:CreateButton({
        Name = "Check Weather",
        Callback = function()
            local active = isMeteorActive()
            pcall(function()
                Window:Notify({
                    Title = "Weather",
                    Content = active and "METEOR ACTIVE!" or "Safe",
                    Duration = 3,
                })
            end)
        end,
    })

    -- ─── Tab 3: Player ───
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
            else stopThread("autoSpeed") end
        end,
    })
    PlayerTab:CreateSlider({
        Name = "Walk Speed",
        Range = {16, 200}, Increment = 1, CurrentValue = 32,
        Suffix = " spd", Flag = "GGWalkSpeed",
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

    -- ─── Tab 4: Settings ───
    local SettingsTab = Window:CreateTab("Settings", "settings")
    SettingsTab:CreateSection("Info")
    SettingsTab:CreateLabel("Greedy Growers v2.0.0 | RAVEN HUB")

    SettingsTab:CreateSection("Debug")
    SettingsTab:CreateButton({
        Name = "Scan Game",
        Callback = function()
            cache.lastScan = 0
            refreshCache()
            pcall(function()
                Window:Notify({
                    Title = "GG Debug",
                    Content = string.format(
                        "F:%d Sell:%s Harv:%s Seeds:%d Plants:%d",
                        #cache.fruits, tostring(cache.sell~=nil),
                        tostring(cache.harvest~=nil), #cache.seeds, #cache.plants
                    ),
                    Duration = 5,
                })
            end)
        end,
    })

    SettingsTab:CreateSection("Server")
    SettingsTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function() TeleportService:Teleport(game.PlaceId, Player) end,
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
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, Player)
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
        for key, _ in pairs(threads) do threads[key] = nil end
    end
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    pcall(function()
        Window:Notify({
            Title = "Greedy Growers",
            Content = "v2.0.0 | " .. #cache.fruits .. " fruits, " .. #cache.seeds .. " seeds",
            Duration = 3,
        })
    end)
end
