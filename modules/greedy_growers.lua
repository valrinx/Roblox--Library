-- ═════════════════════════════════════════════════════════════════
-- Greedy Growers 🌱 | RAVEN HUB Module v3.3.0
-- PlaceId: 74102906764176 | GameId: 10440833423
-- Full Knit Service integration + ProximityPrompt support
-- Flow: Buy Seed → Equip Seed → Plant Round → Auto Harvest → Collect → Sell
-- ═════════════════════════════════════════════════════════════════

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")

    local Player = Players.LocalPlayer
    local environment = getgenv and getgenv() or _G

    -- Cleanup previous instance if running
    if type(environment.__RAVEN_GREEDY_GROWERS) == "table"
        and type(environment.__RAVEN_GREEDY_GROWERS.Destroy) == "function" then
        pcall(environment.__RAVEN_GREEDY_GROWERS.Destroy)
    end

    local running = true
    local threads = {}

    -- ═══════════ Knit Services ═══════════
    local knitRoot = ReplicatedStorage:WaitForChild("Packages", 5)
        and ReplicatedStorage.Packages:WaitForChild("_Index", 5)
    local knitIndex = knitRoot and knitRoot:FindFirstChild("sleitnick_knit@1.6.0")
    local knitServices = knitIndex and knitIndex.knit:FindFirstChild("Services")

    local pps = knitServices and knitServices:FindFirstChild("PlayerPlotService")
    local prs = knitServices and knitServices:FindFirstChild("PlantRoundService")
    local sss = knitServices and knitServices:FindFirstChild("SellStandService")
    local scs = knitServices and knitServices:FindFirstChild("SeedConveyorService")

    -- Seed list
    local SEED_LIST = {
        "Pine", "Oak", "Apple", "Peach", "Fig", "Orange", "Lemon",
        "Avocado", "Cherry", "Mango", "Coconut", "Banana", "Starfruit", "Dragon Fruit"
    }

    local FERTILIZER_LIST = {
        "None", "Basic", "Better", "Premium", "Super", "Magic"
    }

    -- ═══════════ Settings ═══════════
    local settings = {
        -- Auto Farm
        autoFarm = false,
        harvestMode = "Target Multiplier", -- "Target Multiplier" (safe guaranteed cash out) or "Shock (Pre-Lightning)"
        targetMultiplier = 2.5,
        shockSafetyMargin = 0.08,
        selectedSeed = "Pine",
        selectedFertilizer = "Basic",
        autoPlant = false,
        plantDelay = 1.0,
        autoHarvest = false,
        autoCollect = true,
        collectInterval = 0.5,
        autoSell = false,
        sellInterval = 3,
        autoBuySeed = true,
        buySeedDelay = 1,
        -- Weather / Anti-Meteor
        antiMeteor = false,
        autoHarvestOnMeteor = true,
        fleeDistance = 100,
        -- Player
        autoSpeed = false,
        walkSpeed = 32,
    }

    -- ═══════════ Real-Time Round Tracking for Shock Harvest ═══════════
    local currentMyRound = {
        active = false,
        roundId = nil,
        startTime = 0,
        crashPoint = 5.95,
        estimatedCrashTime = 0,
        seedType = "Pine",
        harvested = false,
        lastMult = 0,
    }

    local connections = {}

    local function getMyPlantModel()
        local bf = workspace:FindFirstChild("BigField")
        if not bf then return nil end
        local prefix = "PlantRound_" .. Player.UserId .. "_"
        for _, c in ipairs(bf:GetChildren()) do
            if c.Name:sub(1, #prefix) == prefix then
                return c
            end
        end
        return nil
    end

    local function getMyPlantDisplayInfo()
        local model = getMyPlantModel()
        if not model then return nil end
        local md = model:FindFirstChild("MultDisplay")
        local bg = md and md:FindFirstChild("BillboardGui")
        local mf = bg and bg:FindFirstChild("MainFrame")
        if not mf then return nil end

        local multLabel = mf:FindFirstChild("Mult")
        local warnLabel = mf:FindFirstChild("Warning")
        local multVal = 0
        if multLabel and multLabel:IsA("TextLabel") then
            multVal = tonumber((multLabel.Text:gsub("x", ""):gsub(" ", ""))) or 0
        end

        local isWarning = false
        if warnLabel and warnLabel:IsA("TextLabel") and warnLabel.Visible and warnLabel.Text:find("⚠️") then
            isWarning = true
        end

        return {
            model = model,
            mult = multVal,
            warning = isWarning
        }
    end

    local function getPlotCFrame()
        local bf = workspace:FindFirstChild("BigField")
        local plots = bf and bf:FindFirstChild("PlayerPlots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                if plot:GetAttribute("OwnerUserId") == Player.UserId then
                    local seedPlot = plot:FindFirstChild("SeedPlot")
                    if seedPlot then
                        local dirt = seedPlot:FindFirstChild("Dirt")
                        if dirt and dirt:IsA("BasePart") then
                            return dirt.CFrame
                        end
                        local primary = seedPlot.PrimaryPart or seedPlot:FindFirstChildWhichIsA("BasePart")
                        if primary then
                            return primary.CFrame
                        end
                        return seedPlot:GetPivot()
                    end
                    local primary = plot.PrimaryPart or plot:FindFirstChildWhichIsA("BasePart")
                    if primary then
                        return primary.CFrame
                    end
                end
            end
        end
        return nil
    end
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
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            task.wait(0.05)
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end

    local function safeFirePrompt(prompt)
        if not prompt or not prompt.Enabled then return end
        pcall(function()
            local cons = getconnections and getconnections(prompt.Triggered)
            if cons then
                for _, c in ipairs(cons) do
                    if c.Function then pcall(c.Function) end
                end
            end
            fireproximityprompt(prompt, 0)
        end)
    end

    -- ═══════════ Seed Operations ═══════════
    local function getEquippedOrInventorySeed(seedName)
        local targetName = (seedName or ""):lower()
        -- 1. Check Character (equipped)
        local char = Player.Character
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and item:GetAttribute("IsSeed") then
                    if targetName == "" or item.Name:lower():find(targetName) then
                        return item
                    end
                end
            end
        end
        -- 2. Check Backpack
        local bp = Player:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if item:IsA("Tool") and item:GetAttribute("IsSeed") then
                    if targetName == "" or item.Name:lower():find(targetName) then
                        item.Parent = Player.Character
                        task.wait(0.25)
                        return item
                    end
                end
            end
            -- Any seed fallback if specific not found
            for _, item in ipairs(bp:GetChildren()) do
                if item:IsA("Tool") and item:GetAttribute("IsSeed") then
                    item.Parent = Player.Character
                    task.wait(0.25)
                    return item
                end
            end
        end
        return nil
    end

    local function buySeedFromConveyor(seedName)
        local conveyor = workspace:FindFirstChild("BigField") and workspace.BigField:FindFirstChild("ConveyorSeeds")
        if not conveyor then return false end

        local targetPrompt = nil
        local targetPos = nil
        for _, holder in ipairs(conveyor:GetChildren()) do
            local prompt = holder:FindFirstChildOfClass("ProximityPrompt", true)
            if prompt and prompt.Enabled and prompt.ActionText == "Buy" then
                if prompt.ObjectText:lower():find(seedName:lower()) then
                    targetPrompt = prompt
                    local part = prompt:FindFirstAncestorWhichIsA("BasePart")
                    targetPos = part and part.Position
                    break
                end
            end
        end

        if targetPrompt and targetPos then
            tpTo(targetPos)
            task.wait(0.2)
            safeFirePrompt(targetPrompt)
            task.wait(0.3)
            return true
        end
        return false
    end

    -- ═══════════ Event Listeners for Shock Prediction ═══════════
    if prs and prs:FindFirstChild("RE") then
        local re = prs.RE
        if re:FindFirstChild("RoundStartedAll") then
            connections.roundStarted = re.RoundStartedAll.OnClientEvent:Connect(function(userId, plantPos, startTime, roundId, crashPoint, seedType, mutationKey)
                if userId == Player.UserId then
                    currentMyRound.active = true
                    currentMyRound.roundId = roundId
                    currentMyRound.startTime = tonumber(startTime) or workspace:GetServerTimeNow()
                    currentMyRound.seedType = seedType or "Pine"
                    currentMyRound.harvested = false
                end
            end)
        end

        if re:FindFirstChild("PlantStoppedAll") then
            connections.plantStopped = re.PlantStoppedAll.OnClientEvent:Connect(function(userId, stoppedAt)
                if userId == Player.UserId then
                    currentMyRound.active = false
                    currentMyRound.harvested = true
                    currentMyRound.estimatedCrashTime = 0
                end
            end)
        end

        if re:FindFirstChild("CrashedAll") then
            connections.crashed = re.CrashedAll.OnClientEvent:Connect(function(userId, crashPoint)
                if userId == Player.UserId then
                    currentMyRound.active = false
                    currentMyRound.harvested = true
                    currentMyRound.estimatedCrashTime = 0
                end
            end)
        end
    end

    -- ═══════════ Core Game Actions ═══════════
    local function doPlant(seedName, fertilizer)
        -- 1. Ensure we have seed in hand or inventory
        local seedTool = getEquippedOrInventorySeed(seedName)
        if not seedTool and settings.autoBuySeed then
            buySeedFromConveyor(seedName)
            task.wait(0.5)
            seedTool = getEquippedOrInventorySeed(seedName)
        end

        if not seedTool then
            seedTool = getEquippedOrInventorySeed("Oak") or getEquippedOrInventorySeed("")
        end

        if not seedTool then return false end

        -- 2. Walk/Teleport directly to player's SeedPlot Dirt
        local plotCF = getPlotCFrame()
        if plotCF then
            tpTo(plotCF.Position)
            task.wait(0.2)
        end

        -- 3. Ensure seed tool is equipped in Character
        if seedTool.Parent ~= Player.Character then
            seedTool.Parent = Player.Character
            task.wait(0.25)
        end

        local actualSeedType = seedTool:GetAttribute("SeedType") or seedName
        local fert = fertilizer or "None"

        if prs and prs:FindFirstChild("RF") and prs.RF:FindFirstChild("StartRound") then
            for attempt = 1, 3 do
                local ok, ret = pcall(function()
                    return prs.RF.StartRound:InvokeServer(actualSeedType, fert)
                end)
                if ok and ret == true then
                    currentMyRound.active = true
                    currentMyRound.harvested = false
                    currentMyRound.startTime = workspace:GetServerTimeNow()
                    return true
                end
                task.wait(0.3)
            end
        end
        return false
    end

    local function doHarvest()
        if currentMyRound.harvested then return true end
        if prs and prs:FindFirstChild("RF") and prs.RF:FindFirstChild("StopPlant") then
            local ok, ret = pcall(function()
                return prs.RF.StopPlant:InvokeServer()
            end)
            if ok and ret then
                currentMyRound.harvested = true
                currentMyRound.active = false
                return true
            end
        end

        -- Fallback: Harvest prompt on player's round tree
        local bf = workspace:FindFirstChild("BigField")
        if bf then
            local myUserId = tostring(Player.UserId)
            for _, c in ipairs(bf:GetChildren()) do
                if c.Name:find("PlantRound_" .. myUserId) then
                    local p = c:FindFirstChildOfClass("ProximityPrompt", true)
                    if p and p.Enabled then
                        local part = p:FindFirstAncestorWhichIsA("BasePart")
                        if part then tpTo(part.Position); task.wait(0.1) end
                        safeFirePrompt(p)
                        currentMyRound.harvested = true
                        currentMyRound.active = false
                        return true
                    end
                end
            end
        end
        return false
    end

    local function doCollectAll()
        -- 1. Direct Server Remote (Instant full plot collection)
        if pps and pps:FindFirstChild("RF") and pps.RF:FindFirstChild("CollectAllFruits") then
            local ok = pcall(function()
                return pps.RF.CollectAllFruits:InvokeServer()
            end)
            if ok then return true end
        end

        -- 2. Physical Prompts fallback
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.Enabled and obj.ActionText == "Collect" then
                local part = obj:FindFirstAncestorWhichIsA("BasePart")
                if part then
                    tpTo(part.Position)
                    task.wait(0.08)
                    safeFirePrompt(obj)
                end
            end
        end
        return true
    end

    local function doSellAll()
        -- 1. Direct SellStandService Remote
        if sss and sss:FindFirstChild("RF") and sss.RF:FindFirstChild("SellAll") then
            local ok, ret = pcall(function()
                return sss.RF.SellAll:InvokeServer()
            end)
            if ok and ret then return true end
        end

        -- 2. HUD Sell Button fallback
        local hud = Player:FindFirstChild("PlayerGui") and Player.PlayerGui:FindFirstChild("HUD")
        if hud then
            local sellStuff = hud:FindFirstChild("Center") and hud.Center:FindFirstChild("SellStuff")
            if sellStuff and sellStuff:FindFirstChild("SellAll") and sellStuff.SellAll:FindFirstChild("Button") then
                firesignal(sellStuff.SellAll.Button.Activated)
                return true
            end
            local topSell = hud:FindFirstChild("TopButtons") and hud.TopButtons:FindFirstChild("Center")
                and hud.TopButtons.Center:FindFirstChild("Buttons") and hud.TopButtons.Center.Buttons:FindFirstChild("Sell")
            if topSell and topSell:FindFirstChild("Button") then
                firesignal(topSell.Button.Activated)
                task.wait(0.15)
                if sellStuff and sellStuff:FindFirstChild("SellAll") and sellStuff.SellAll:FindFirstChild("Button") then
                    firesignal(sellStuff.SellAll.Button.Activated)
                    return true
                end
            end
        end
        return false
    end

    local function isMeteorWeather()
        -- Check WeatherController if available
        local rs = game:GetService("ReplicatedStorage")
        local wcMod = rs:FindFirstChild("Client") and rs.Client:FindFirstChild("Controllers")
            and rs.Client.Controllers:FindFirstChild("WeatherController")
        if wcMod then
            local ok, wc = pcall(require, wcMod)
            if ok and wc and type(wc.GetCurrent) == "function" then
                local cur = wc:GetCurrent()
                if cur and (tostring(cur):lower():find("meteor") or tostring(cur):lower():find("lightning")) then
                    return true
                end
            end
        end

        for _, obj in ipairs(workspace:GetChildren()) do
            local n = obj.Name:lower()
            if n:find("meteor") or n:find("storm") or n:find("lightning") then
                return true
            end
        end
        return false
    end

    local function getActiveMyRound()
        if not prs or not prs:FindFirstChild("RF") or not prs.RF:FindFirstChild("GetActiveRounds") then
            return nil
        end
        local ok, rounds = pcall(function() return prs.RF.GetActiveRounds:InvokeServer() end)
        if ok and type(rounds) == "table" then
            for _, r in pairs(rounds) do
                if type(r) == "table" and r.userId == Player.UserId and not r.stopped and not r.crashed then
                    return r
                end
            end
        end
        return nil
    end

    -- ═══════════ Thread Control ═══════════
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

    -- ═════════════════════════════════════════════════════════════════
    --   UI TABS & CONTROLS
    -- ═════════════════════════════════════════════════════════════════

    -- ─── Tab 1: Farm ───
    local FarmTab = Window:CreateTab("Farm", "sprout")

    FarmTab:CreateSection("⚡ Full Automation")

    FarmTab:CreateToggle({
        Name = "Master Auto Farm Loop (Shock Flow)",
        CurrentValue = false,
        Flag = "GGMasterAutoFarm",
        Callback = function(v)
            settings.autoFarm = v
            if v then
                startThread("autoFarmLoop", function(isActive)
                    while isActive() do
                        -- 1. Check if we have an active round
                        local activeRound = getActiveMyRound()
                        if not activeRound and not currentMyRound.active then
                            -- Step 1: Walk/Teleport to plot and plant seed
                            doPlant(settings.selectedSeed, settings.selectedFertilizer)
                            task.wait(settings.plantDelay)
                        else
                            -- Step 2: Active round running!
                            local waitStart = os.clock()
                            while isActive() and (currentMyRound.active or getActiveMyRound()) and not currentMyRound.harvested do
                                local displayInfo = getMyPlantDisplayInfo()
                                local curMult = displayInfo and displayInfo.mult or 0

                                if settings.harvestMode == "Target Multiplier" then
                                    if curMult >= settings.targetMultiplier then
                                        doHarvest()
                                        break
                                    end
                                else
                                    -- Shock (Pre-Lightning) Mode:
                                    -- 1. Check BillboardGui warning ⚠️
                                    if displayInfo and displayInfo.warning then
                                        doHarvest()
                                        break
                                    end

                                    -- 2. Server Time countdown check
                                    local now = workspace:GetServerTimeNow()
                                    if currentMyRound.estimatedCrashTime > 0 and currentMyRound.estimatedCrashTime > currentMyRound.startTime then
                                        local timeLeft = currentMyRound.estimatedCrashTime - now
                                        if timeLeft <= settings.shockSafetyMargin then
                                            doHarvest()
                                            break
                                        end
                                    end

                                    -- 3. Proximity to crash multiplier
                                    if currentMyRound.crashPoint > 0 and curMult > 0 then
                                        if curMult >= (currentMyRound.crashPoint - 0.15) then
                                            doHarvest()
                                            break
                                        end
                                    end
                                end

                                -- Fallback safety timeout (60s max for extreme rounds)
                                if os.clock() - waitStart > 60 then
                                    doHarvest()
                                    break
                                end

                                RunService.Heartbeat:Wait()
                            end

                            task.wait(0.3)
                            -- Step 3: Collect ripe shocked fruits from plot
                            if settings.autoCollect then
                                doCollectAll()
                            end

                            task.wait(0.3)
                            -- Step 4: Sell all if enabled
                            if settings.autoSell then
                                doSellAll()
                            end
                        end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("autoFarmLoop")
            end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Harvest Mode",
        Options = {"Target Multiplier", "Shock (Pre-Lightning)"},
        CurrentOption = {"Target Multiplier"},
        MultipleOptions = false,
        Flag = "GGHarvestMode",
        Callback = function(value)
            settings.harvestMode = type(value) == "table" and value[1] or value
        end,
    })

    FarmTab:CreateSlider({
        Name = "Target Multiplier",
        Range = {1.5, 500.0},
        Increment = 0.5,
        CurrentValue = 2.5,
        Suffix = "x",
        Flag = "GGTargetMultiplier",
        Callback = function(v)
            settings.targetMultiplier = tonumber(v) or 10.0
        end,
    })

    FarmTab:CreateSlider({
        Name = "Lightning Pre-Harvest Margin",
        Range = {0.02, 0.30},
        Increment = 0.01,
        CurrentValue = 0.08,
        Suffix = " sec",
        Flag = "GGShockMargin",
        Callback = function(v)
            settings.shockSafetyMargin = tonumber(v) or 0.08
        end,
    })

    FarmTab:CreateSection("🌱 Planting & Seeds")

    FarmTab:CreateDropdown({
        Name = "Seed Type",
        Options = SEED_LIST,
        CurrentOption = {"Pine"},
        MultipleOptions = false,
        Flag = "GGSeedType",
        Callback = function(value)
            settings.selectedSeed = type(value) == "table" and value[1] or value
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Fertilizer",
        Options = FERTILIZER_LIST,
        CurrentOption = {"Basic"},
        MultipleOptions = false,
        Flag = "GGFertilizerType",
        Callback = function(value)
            settings.selectedFertilizer = type(value) == "table" and value[1] or value
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Plant Seeds (At Plot)",
        CurrentValue = false,
        Flag = "GGAutoPlant",
        Callback = function(v)
            settings.autoPlant = v
            if v then
                startThread("autoPlant", function(isActive)
                    while isActive() do
                        local active = getActiveMyRound()
                        if not active and not currentMyRound.active then
                            doPlant(settings.selectedSeed, settings.selectedFertilizer)
                        end
                        task.wait(settings.plantDelay)
                    end
                end)
            else
                stopThread("autoPlant")
            end
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Buy Seeds from Belt",
        CurrentValue = true,
        Flag = "GGAutoBuySeed",
        Callback = function(v)
            settings.autoBuySeed = v
            if v then
                startThread("autoBuySeed", function(isActive)
                    while isActive() do
                        buySeedFromConveyor(settings.selectedSeed)
                        task.wait(settings.buySeedDelay)
                    end
                end)
            else
                stopThread("autoBuySeed")
            end
        end,
    })

    FarmTab:CreateSection("🌾 Harvest (Cash Out)")

    FarmTab:CreateToggle({
        Name = "Auto Harvest (Smart Cash Out)",
        CurrentValue = false,
        Flag = "GGAutoHarvest",
        Callback = function(v)
            settings.autoHarvest = v
            if v then
                startThread("autoHarvest", function(isActive)
                    while isActive() do
                        local active = getActiveMyRound() or currentMyRound.active
                        if active and not currentMyRound.harvested then
                            local displayInfo = getMyPlantDisplayInfo()
                            local curMult = displayInfo and displayInfo.mult or 0

                            if settings.harvestMode == "Target Multiplier" then
                                if curMult >= settings.targetMultiplier then
                                    doHarvest()
                                end
                            else
                                -- Shock (Pre-Lightning) Mode
                                local shouldHarvest = false
                                if displayInfo and displayInfo.warning then
                                    shouldHarvest = true
                                end

                                local now = workspace:GetServerTimeNow()
                                if currentMyRound.estimatedCrashTime > 0 and currentMyRound.estimatedCrashTime > currentMyRound.startTime then
                                    local timeLeft = currentMyRound.estimatedCrashTime - now
                                    if timeLeft <= settings.shockSafetyMargin then
                                        shouldHarvest = true
                                    end
                                end

                                if currentMyRound.crashPoint > 0 and curMult > 0 then
                                    if curMult >= (currentMyRound.crashPoint - 0.15) then
                                        shouldHarvest = true
                                    end
                                end

                                if shouldHarvest then
                                    doHarvest()
                                end
                            end
                        end
                        RunService.Heartbeat:Wait()
                    end
                end)
            else
                stopThread("autoHarvest")
            end
        end,
    })

    FarmTab:CreateButton({
        Name = "Harvest Now (Cash Out)",
        Callback = function()
            local ok = doHarvest()
            pcall(function()
                Window:Notify({
                    Title = "Harvest",
                    Content = ok and "Cashed out successfully!" or "No active tree round",
                    Duration = 3,
                })
            end)
        end,
    })

    FarmTab:CreateSection("💰 Collect & Sell")

    FarmTab:CreateToggle({
        Name = "Auto Collect All Fruits",
        CurrentValue = false,
        Flag = "GGAutoCollect",
        Callback = function(v)
            settings.autoCollect = v
            if v then
                startThread("autoCollect", function(isActive)
                    while isActive() do
                        doCollectAll()
                        task.wait(settings.collectInterval)
                    end
                end)
            else
                stopThread("autoCollect")
            end
        end,
    })

    FarmTab:CreateButton({
        Name = "Collect All Fruits Now",
        Callback = function()
            doCollectAll()
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Sell",
        CurrentValue = false,
        Flag = "GGAutoSell",
        Callback = function(v)
            settings.autoSell = v
            if v then
                startThread("autoSell", function(isActive)
                    while isActive() do
                        doSellAll()
                        task.wait(settings.sellInterval)
                    end
                end)
            else
                stopThread("autoSell")
            end
        end,
    })

    FarmTab:CreateButton({
        Name = "Sell All Now",
        Callback = function()
            local ok = doSellAll()
            pcall(function()
                Window:Notify({
                    Title = "Sell",
                    Content = ok and "Items sold!" or "Nothing to sell",
                    Duration = 3,
                })
            end)
        end,
    })

    -- ─── Tab 2: Weather ───
    local WeatherTab = Window:CreateTab("Weather", "cloud-lightning")

    WeatherTab:CreateSection("⚡ Meteor & Lightning Defense")

    WeatherTab:CreateToggle({
        Name = "Auto Harvest on Meteor (Anti-Crash)",
        CurrentValue = false,
        Flag = "GGAntiMeteor",
        Callback = function(v)
            settings.antiMeteor = v
            if v then
                startThread("antiMeteor", function(isActive)
                    while isActive() do
                        if isMeteorWeather() then
                            -- Instant emergency cash out!
                            doHarvest()
                            task.wait(0.2)
                            doCollectAll()
                            task.wait(0.2)
                            doSellAll()

                            -- Flee if still active
                            if isMeteorWeather() then
                                local root = getRoot()
                                if root then
                                    local fleeOffset = root.CFrame.LookVector * settings.fleeDistance
                                    tpTo(root.Position + fleeOffset)
                                end
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
        Range = {30, 250}, Increment = 10, CurrentValue = 100,
        Suffix = " studs", Flag = "GGFleeDistance",
        Callback = function(v) settings.fleeDistance = v end,
    })

    WeatherTab:CreateButton({
        Name = "Check Current Weather",
        Callback = function()
            local active = isMeteorWeather()
            pcall(function()
                Window:Notify({
                    Title = "Weather Status",
                    Content = active and "⚠️ DANGER: Meteor / Storm Active!" or "✅ Weather is calm",
                    Duration = 4,
                })
            end)
        end,
    })

    -- ─── Tab 3: Player ───
    local PlayerTab = Window:CreateTab("Player", "user")

    PlayerTab:CreateSection("WalkSpeed")

    PlayerTab:CreateToggle({
        Name = "Auto WalkSpeed",
        CurrentValue = false,
        Flag = "GGAutoSpeed",
        Callback = function(v)
            settings.autoSpeed = v
            if v then
                startThread("autoSpeed", function(isActive)
                    while isActive() do
                        local hum = getHumanoid()
                        if hum then hum.WalkSpeed = settings.walkSpeed end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("autoSpeed")
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = 16 end
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "WalkSpeed Value",
        Range = {16, 200}, Increment = 2, CurrentValue = 32,
        Suffix = " spd", Flag = "GGWalkSpeed",
        Callback = function(v)
            settings.walkSpeed = v
            local hum = getHumanoid()
            if hum and settings.autoSpeed then hum.WalkSpeed = v end
        end,
    })

    -- ─── Tab 4: Settings ───
    local SettingsTab = Window:CreateTab("Settings", "settings")

    SettingsTab:CreateSection("Module Info")
    SettingsTab:CreateLabel("Greedy Growers v3.0.0 | RAVEN HUB")
    SettingsTab:CreateLabel("Author: valrinx")

    SettingsTab:CreateSection("Server Utilities")
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
        for key, _ in pairs(threads) do
            threads[key] = nil
        end
        for _, conn in pairs(connections) do
            if typeof(conn) == "RBXScriptConnection" then
                pcall(function() conn:Disconnect() end)
            end
        end
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = 16 end
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    environment.__RAVEN_GREEDY_GROWERS = {
        Destroy = destroy,
        Version = "3.1.0",
        CurrentRound = currentMyRound,
        Settings = settings
    }

    pcall(function()
        Window:Notify({
            Title = "Greedy Growers",
            Content = "v3.1.0 Loaded | Shock Harvest Mode Ready!",
            Duration = 3,
        })
    end)
end
