-- ═══════════════════════════════════════════════════════════
-- Greedy Growers | RAVEN HUB Module v1.0.1
-- Features: Auto Collect, Auto Sell, Auto Plant, Auto Buy Seeds,
--           Anti-Meteor, Speed, Grow All, Collect All
-- PlaceId: 74102906764176 | GameId: 10440833423
-- ═══════════════════════════════════════════════════════════
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")

    local Player = Players.LocalPlayer
    local PlayerGui = Player:WaitForChild("PlayerGui")

    local running = true
    local connections = {}

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

    -- ═══════════ Utility ═══════════
    local function getChar()
        return Player.Character or Player.CharacterAdded:Wait()
    end

    local function getRoot()
        local c = getChar()
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid()
        local c = getChar()
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function tpTo(pos)
        local root = getRoot()
        if root then root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
    end

    local function safeFire(pp)
        if not pp then return end
        pcall(function()
            fireproximityprompt(pp, 0)
        end)
    end

    local function toggleConn(key, enabled, func)
        if connections[key] then
            connections[key]:Disconnect()
            connections[key] = nil
        end
        if enabled and func then
            connections[key] = RunService.Heartbeat:Connect(func)
        end
    end

    -- ═══════════ Scanners (game:GetDescendants for full coverage) ═══════════
    local function getFruitSpawns()
        local fruits = {}
        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") and pp.ActionText == "Collect" then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then
                    table.insert(fruits, {prompt = pp, part = part})
                end
            end
        end
        return fruits
    end

    local function getSellStand()
        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") and pp.ActionText == "Sell" then
                return pp
            end
        end
        return nil
    end

    local function getSeedHolders()
        local seeds = {}
        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") and pp.ActionText == "Buy" then
                local objText = pp.ObjectText
                if objText:find("Seed") then
                    local part = pp:FindFirstAncestorWhichIsA("BasePart")
                    if part then
                        table.insert(seeds, {
                            prompt = pp,
                            part = part,
                            name = objText,
                        })
                    end
                end
            end
        end
        return seeds
    end

    local function getPlantPrompts()
        local prompts = {}
        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") and pp.ActionText == "Plant Seed" then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then
                    table.insert(prompts, {prompt = pp, part = part})
                end
            end
        end
        return prompts
    end

    local function getGrowAll()
        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") and pp.ActionText == "Buy"
                and pp.ObjectText == "Grow All Fruits" then
                return pp
            end
        end
        return nil
    end

    local function getCollectAll()
        for _, pp in ipairs(game:GetDescendants()) do
            if pp:IsA("ProximityPrompt") and pp.ActionText == "Buy"
                and pp.ObjectText == "Collect All Fruits" then
                return pp
            end
        end
        return nil
    end

    local function isDangerousWeather()
        for _, obj in ipairs(Workspace:GetChildren()) do
            local n = obj.Name:lower()
            if n:find("meteor") or n:find("storm") or n:find("lightning") then
                return true
            end
        end
        return false
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
            toggleConn("autoCollect", v, function()
                if not settings.autoCollect then return end
                local fruits = getFruitSpawns()
                for _, f in ipairs(fruits) do
                    if not settings.autoCollect then break end
                    tpTo(f.part.Position)
                    task.wait(0.15)
                    safeFire(f.prompt)
                    task.wait(settings.collectDelay)
                end
            end)
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
            local pp = getCollectAll()
            if pp then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(pp)
            else
                local fruits = getFruitSpawns()
                for _, f in ipairs(fruits) do
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
            toggleConn("autoSell", v, function()
                if not settings.autoSell then return end
                local pp = getSellStand()
                if pp then
                    local part = pp:FindFirstAncestorWhichIsA("BasePart")
                    if part then tpTo(part.Position) end
                    task.wait(0.2)
                    safeFire(pp)
                    task.wait(settings.sellInterval)
                end
            end)
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
            local pp = getSellStand()
            if pp then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(pp)
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
            toggleConn("autoPlant", v, function()
                if not settings.autoPlant then return end
                local prompts = getPlantPrompts()
                for _, p in ipairs(prompts) do
                    if not settings.autoPlant then break end
                    tpTo(p.part.Position)
                    task.wait(0.15)
                    safeFire(p.prompt)
                    task.wait(0.5)
                end
            end)
        end,
    })

    PlantTab:CreateButton({
        Name = "Grow All",
        Callback = function()
            local pp = getGrowAll()
            if pp then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(pp)
            end
        end,
    })

    PlantTab:CreateButton({
        Name = "Plant All (One-shot)",
        Callback = function()
            local prompts = getPlantPrompts()
            for _, p in ipairs(prompts) do
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
            toggleConn("autoBuySeed", v, function()
                if not settings.autoBuySeed then return end
                local seeds = getSeedHolders()
                for _, s in ipairs(seeds) do
                    if not settings.autoBuySeed then break end
                    if s.name:lower():find(settings.selectedSeed:lower()) then
                        tpTo(s.part.Position)
                        task.wait(0.15)
                        safeFire(s.prompt)
                        task.wait(settings.buyDelay)
                    end
                end
            end)
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
            local seeds = getSeedHolders()
            for _, s in ipairs(seeds) do
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
            toggleConn("antiMeteor", v, function()
                if not settings.antiMeteor then return end
                if isDangerousWeather() then
                    local root = getRoot()
                    if root then
                        local fleeDir = root.CFrame.LookVector * settings.meteorFleeDist
                        tpTo(root.Position + fleeDir)
                    end
                end
            end)
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
            local danger = isDangerousWeather()
            pcall(function()
                Window:Notify({
                    Title = "Weather",
                    Content = danger and "DANGER: Meteor/Storm detected!" or "Safe: No danger weather",
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
            toggleConn("autoSpeed", v, function()
                if not settings.autoSpeed then return end
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = settings.walkSpeed end
            end)
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

    SettingsTab:CreateLabel("Greedy Growers v1.0.1 | RAVEN HUB")

    SettingsTab:CreateSection("Debug")

    SettingsTab:CreateButton({
        Name = "Scan Game (Debug)",
        Callback = function()
            local fruits = getFruitSpawns()
            local sell = getSellStand()
            local seeds = getSeedHolders()
            local plants = getPlantPrompts()
            pcall(function()
                Window:Notify({
                    Title = "GG Debug",
                    Content = string.format(
                        "Fruits: %d | Sell: %s | Seeds: %d | Plants: %d",
                        #fruits, tostring(sell ~= nil), #seeds, #plants
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
        for key, conn in pairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        connections = {}
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    -- Notify loaded
    pcall(function()
        Window:Notify({
            Title = "Greedy Growers",
            Content = "v1.0.1 loaded! " .. #getFruitSpawns() .. " fruits detected",
            Duration = 3,
        })
    end)
end
