-- ═════════════════════════════════════════════════════════════════
-- Greedy Growers 🌱 | RAVEN HUB Module v4.2.0
-- PlaceId: 74102906764176 | GameId: 10440833423
-- High-Multiplier Hunter (1.1x–500x) + True Live Metrics + Knit Full Automation
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
    local connections = {}

    -- ═══════════ Knit Services ═══════════
    local knitRoot = ReplicatedStorage:WaitForChild("Packages", 5)
        and ReplicatedStorage.Packages:WaitForChild("_Index", 5)
    local knitIndex = knitRoot and knitRoot:FindFirstChild("sleitnick_knit@1.6.0")
    local knitServices = knitIndex and knitIndex.knit:FindFirstChild("Services")

    local pps = knitServices and knitServices:FindFirstChild("PlayerPlotService")
    local prs = knitServices and knitServices:FindFirstChild("PlantRoundService")
    local sss = knitServices and knitServices:FindFirstChild("SellStandService")
    local scs = knitServices and knitServices:FindFirstChild("SeedConveyorService")

    local Knit = nil
    pcall(function()
        Knit = require(ReplicatedStorage.Packages.Knit)
    end)

    -- ═══════════ Seed & Fertilizer Constants ═══════════
    local SEED_LIST = {
        "Oak", "Pine", "Apple", "Peach", "Fig", "Orange", "Lemon",
        "Avocado", "Cherry", "Mango", "Coconut", "Banana", "Starfruit",
        "DragonFruit", "Mushroom", "Glowshroom", "Magic", "Spirit",
        "Inferno", "Prismatic", "Astral", "Elder"
    }

    local FERTILIZER_LIST = {
        "None", "Basic", "Better", "Premium", "Super", "Magic"
    }

    -- ═══════════ Settings ═══════════
    local settings = {
        -- Harvest Engine
        autoHarvest = true,
        harvestStrategy = "Custom Target", -- "Custom Target", "High Hunter", "Ladder"
        targetMultiplier = 5.0,            -- Target multiplier to cash out (up to 2500x)
        pingCompensation = true,
        latencyBuffer = 0.05,
        riskPreset = "🟠 Solid Profit (5.0x)",

        -- Advanced Hunting Strategies
        ladderMode = false,                -- Auto Escalator (เพิ่มเป้าหมายอัตโนมัติตามสเต็ป)
        ladderStep = 2.0,                  -- Step increment per cashout
        ladderMax = 50.0,                  -- Max ceiling for ladder mode
        trailingMode = false,              -- Trailing Stop (ถ้าโตเกิน X แล้วให้ปล่อยไหล)
        trailingTrigger = 10.0,            -- Start trailing after 10x
        trailingDrop = 1.0,                -- Cash out if drop/stagnant

        -- Automation Loop
        masterAutoFarm = false,
        selectedSeed = "Oak",
        selectedFertilizer = "None",
        autoPlant = false,
        plantDelay = 0.8,
        autoCollectDeadWood = true,  -- Auto CollectDeadTree if struck by lightning
        autoCollectFruits = true,
        collectInterval = 1.5,
        autoSell = false,
        sellInterval = 5.0,
        autoBuySeed = false,
        buySeedDelay = 2.0,

        -- Player
        autoSpeed = false,
        walkSpeed = 32,
    }

    -- ═══════════ Live Statistics ═══════════
    local stats = {
        status = "Idle",
        currentMult = 1.0,
        peakMult = 1.0,
        lastCashoutMult = 0,
        totalRounds = 0,
        successfulHarvests = 0,
        crashedRounds = 0,
    }

    -- ═══════════ Round Tracking State ═══════════
    local currentMyRound = {
        active = false,
        roundId = nil,
        startTime = 0,
        seedType = "Oak",
        harvested = false,
        crashed = false,
    }

    -- ═══════════ Helper Functions ═══════════
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
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3.0, 0))
            task.wait(0.12)
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
            if fireproximityprompt then
                fireproximityprompt(prompt, 0)
            end
        end)
    end

    -- ═══════════ Multiplier Sensor (Ultra-Precise) ═══════════
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

    local function getMyLiveMultiplier()
        local plantModel = getMyPlantModel()
        local rb = Player.PlayerGui:FindFirstChild("RoundBillboards")

        -- 1. Primary: RoundBillboards in PlayerGui
        if rb and plantModel then
            local myMd = plantModel:FindFirstChild("MultDisplay")
            for _, b in ipairs(rb:GetChildren()) do
                if b:IsA("BillboardGui") and (b.Adornee == myMd or (myMd and b.Adornee and b.Adornee:IsDescendantOf(plantModel))) then
                    local mf = b:FindFirstChild("MainFrame")
                    if mf then
                        for _, desc in ipairs(mf:GetChildren()) do
                            if desc:IsA("TextLabel") and desc.Text and desc.Text ~= "" then
                                local clean = desc.Text:gsub("[xX,%s]", ""):match("[%d%.]+")
                                local val = tonumber(clean)
                                if val and val > 0 then
                                    return val, desc.Text, plantModel
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 2. Secondary: TextLabels inside tree model descendants
        if plantModel then
            for _, desc in ipairs(plantModel:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Text and (desc.Text:find("x") or desc.Text:find("X")) then
                    local clean = desc.Text:gsub("[xX,%s]", ""):match("[%d%.]+")
                    local val = tonumber(clean)
                    if val and val > 0 then
                        return val, desc.Text, plantModel
                    end
                end
            end
        end

        -- 3. Tertiary: Fallback if round is marked active
        if currentMyRound.active and currentMyRound.startTime > 0 then
            local elapsed = math.max(0, workspace:GetServerTimeNow() - currentMyRound.startTime)
            local estimated = 1.0 + (elapsed * 0.18)
            return estimated, string.format("%.2fx (est)", estimated), plantModel
        end

        return 0, "0.00x", nil
    end

    -- ═══════════ Plot Location ═══════════
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
                        return seedPlot:GetPivot()
                    end
                    return plot:GetPivot()
                end
            end
        end
        return nil
    end

    -- ═══════════ Execution Primitives ═══════════
    local function doHarvestNow(reason)
        if currentMyRound.harvested then return true end
        currentMyRound.harvested = true
        currentMyRound.active = false

        local harvestedMult = stats.currentMult
        stats.lastCashoutMult = harvestedMult
        stats.status = "Harvested (" .. string.format("%.2f", harvestedMult) .. "x)"
        stats.successfulHarvests = stats.successfulHarvests + 1

        -- 1. Fast Invoke via PlantRoundService RF
        task.spawn(function()
            if Knit then
                pcall(function() Knit.GetService("PlantRoundService"):StopPlant():await() end)
            end
            if prs and prs:FindFirstChild("RF") and prs.RF:FindFirstChild("StopPlant") then
                pcall(function() prs.RF.StopPlant:InvokeServer() end)
            end
        end)

        -- 2. Fallback: Proximity prompt on tree model
        local bf = workspace:FindFirstChild("BigField")
        if bf then
            local prefix = "PlantRound_" .. Player.UserId .. "_"
            for _, c in ipairs(bf:GetChildren()) do
                if c.Name:sub(1, #prefix) == prefix then
                    local prompt = c:FindFirstChildOfClass("ProximityPrompt", true)
                    if prompt and prompt.Enabled then
                        safeFirePrompt(prompt)
                    end
                end
            end
        end

        pcall(function()
            Window:Notify({
                Title = "⚡ Precision Harvest!",
                Content = string.format("Cashed out safely at %.2fx! (%s)", harvestedMult, reason or "Target Reached"),
                Duration = 3.0,
            })
        end)

        return true
    end

    local function doCollectDeadTreeNow()
        if Knit then
            pcall(function() Knit.GetService("PlantRoundService"):CollectDeadTree():await() end)
        elseif prs and prs:FindFirstChild("RF") and prs.RF:FindFirstChild("CollectDeadTree") then
            pcall(function() prs.RF.CollectDeadTree:InvokeServer() end)
        end
    end

    local function doPlantNow(seedType, fertilizer)
        local seed = seedType or settings.selectedSeed or "Oak"
        local fert = fertilizer or settings.selectedFertilizer or "None"

        local plotCF = getPlotCFrame()
        if plotCF then
            tpTo(plotCF.Position)
            task.wait(0.2)
        end

        local ok, ret = false, nil
        if Knit then
            ok, ret = pcall(function()
                return Knit.GetService("PlantRoundService"):StartRound(seed, fert):await()
            end)
        end
        if not ok or ret == false then
            if prs and prs:FindFirstChild("RF") and prs.RF:FindFirstChild("StartRound") then
                ok, ret = pcall(function()
                    return prs.RF.StartRound:InvokeServer(seed, fert)
                end)
            end
        end

        if ok and (ret == true or ret == nil) then
            currentMyRound.active = true
            currentMyRound.harvested = false
            currentMyRound.crashed = false
            currentMyRound.seedType = seed
            currentMyRound.startTime = workspace:GetServerTimeNow()
            stats.status = "Growing (" .. seed .. ")"
            stats.totalRounds = stats.totalRounds + 1
            return true
        end
        return false
    end

    local function doCollectAllFruits()
        if pps and pps:FindFirstChild("RF") and pps.RF:FindFirstChild("CollectAllFruits") then
            pcall(function() pps.RF.CollectAllFruits:InvokeServer() end)
        end

        local bf = workspace:FindFirstChild("BigField")
        local plots = bf and bf:FindFirstChild("PlayerPlots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                if plot:GetAttribute("OwnerUserId") == Player.UserId then
                    local ca = plot:FindFirstChild("CollectAll")
                    local pp = ca and ca:FindFirstChildOfClass("ProximityPrompt", true)
                    if pp and pp.Enabled then
                        safeFirePrompt(pp)
                    end
                end
            end
        end
    end

    local function doSellAllNow()
        if sss and sss:FindFirstChild("RF") and sss.RF:FindFirstChild("SellAll") then
            pcall(function() sss.RF.SellAll:InvokeServer() end)
            return true
        end

        local hud = Player:FindFirstChild("PlayerGui") and Player.PlayerGui:FindFirstChild("HUD")
        if hud then
            local sellStuff = hud:FindFirstChild("Center") and hud.Center:FindFirstChild("SellStuff")
            if sellStuff and sellStuff:FindFirstChild("SellAll") and sellStuff.SellAll:FindFirstChild("Button") then
                firesignal(sellStuff.SellAll.Button.Activated)
                return true
            end
        end
        return false
    end

    -- ═══════════ Event Listeners for Live Synchronization ═══════════
    if prs and prs:FindFirstChild("RE") then
        local re = prs.RE

        if re:FindFirstChild("RoundStartedAll") then
            connections.roundStarted = re.RoundStartedAll.OnClientEvent:Connect(function(userId, plantPos, startTime, roundId, p5, seedType, mutationKey)
                if userId == Player.UserId then
                    currentMyRound.active = true
                    currentMyRound.harvested = false
                    currentMyRound.crashed = false
                    currentMyRound.roundId = roundId
                    currentMyRound.startTime = tonumber(startTime) or workspace:GetServerTimeNow()
                    currentMyRound.seedType = seedType or settings.selectedSeed
                    stats.totalRounds = stats.totalRounds + 1
                    stats.status = string.format("🌱 Growing %s (Target: %.2fx)", currentMyRound.seedType, settings.targetMultiplier)
                end
            end)
        end

        if re:FindFirstChild("PlantStoppedAll") then
            connections.plantStopped = re.PlantStoppedAll.OnClientEvent:Connect(function(userId, stoppedAt)
                if userId == Player.UserId then
                    currentMyRound.active = false
                    currentMyRound.harvested = true
                    local finalMult = tonumber(stoppedAt) or stats.currentMult
                    stats.lastCashoutMult = finalMult
                    stats.successfulHarvests = stats.successfulHarvests + 1
                    stats.status = string.format("💰 Harvested at %.2fx", finalMult)

                    -- Auto Escalator: if won, bump target up by ladderStep
                    if settings.ladderMode then
                        local nextTarget = math.min(settings.ladderMax, settings.targetMultiplier + settings.ladderStep)
                        settings.targetMultiplier = nextTarget
                    end
                end
            end)
        end

        if re:FindFirstChild("CrashedAll") then
            connections.crashed = re.CrashedAll.OnClientEvent:Connect(function(userId, rId)
                if userId == Player.UserId then
                    currentMyRound.active = false
                    currentMyRound.crashed = true
                    stats.crashedRounds = stats.crashedRounds + 1
                    stats.status = string.format("⚡ Lightning Struck at %.2fx", stats.currentMult)

                    -- Auto Escalator: if crashed, reset to safe base
                    if settings.ladderMode then
                        settings.targetMultiplier = 3.0
                    end

                    if settings.autoCollectDeadWood then
                        task.delay(0.2, doCollectDeadTreeNow)
                    end
                end
            end)
        end
    end

    -- ═══════════ Precision Auto Harvest Engine (Heartbeat) ═══════════
    connections.heartbeatHarvest = RunService.Heartbeat:Connect(function()
        if not running then return end

        local curMult, rawText, plantModel = getMyLiveMultiplier()
        if plantModel or currentMyRound.active then
            if curMult > 0 then
                stats.currentMult = curMult
                if curMult > stats.peakMult then
                    stats.peakMult = curMult
                end
            end

            if settings.autoHarvest and not currentMyRound.harvested and not currentMyRound.crashed then
                local effectiveTarget = settings.targetMultiplier
                if settings.pingCompensation then
                    effectiveTarget = math.max(1.05, settings.targetMultiplier - settings.latencyBuffer)
                end

                if stats.currentMult >= effectiveTarget and stats.currentMult > 1.0 then
                    local reason = string.format("Target Reached (%.2fx / Target %.2fx)", stats.currentMult, settings.targetMultiplier)
                    doHarvestNow(reason)
                end
            end
        else
            if not currentMyRound.active then
                stats.currentMult = 1.0
            end
        end
    end)

    -- ═══════════ Thread Manager ═══════════
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

    -- ─── Tab 1: Harvest Engine ───
    local HarvestTab = Window:CreateTab("Auto Harvest", "zap")

    HarvestTab:CreateSection("⚡ Precision Auto Harvest (หนีฟ้าผ่า)")

    HarvestTab:CreateToggle({
        Name = "Auto Harvest (Smart Cash Out)",
        CurrentValue = true,
        Flag = "GGAutoHarvest",
        Callback = function(v)
            settings.autoHarvest = v
        end,
    })

    HarvestTab:CreateDropdown({
        Name = "Risk Presets (ระดับความเสี่ยง / เป้าหมายล่าตัวคูณ)",
        Options = {
            "🟢 Ultra-Safe (1.8x - ชนะ 85% ฟาร์มเงินชัวร์)",
            "🟡 Balanced (3.0x - กลางๆ ฟาร์มเรื่อยๆ)",
            "🟠 Solid Profit (5.0x - เก็บกำไรชัวร์)",
            "💎 High Roller (10.0x - กำไรคูณสิบ)",
            "🚀 Moonshot (25.0x - ลุ้นแตะ 25x)",
            "🔥 Mega Moonshot (50.0x - แจ็คพอต 50x)",
            "⚡ Century Jackpot (100.0x - ปล่อยไหล 100x)",
            "👑 Godly Multiplier (500.0x - ล่าหลักล้าน)",
            "🌌 Ultra Godly (750.0x+ - ตามรูป $15M!)",
            "🎯 Custom Slider (กำหนดเองด้านล่าง)"
        },
        CurrentOption = {"🟠 Solid Profit (5.0x - เก็บกำไรชัวร์)"},
        MultipleOptions = false,
        Flag = "GGRiskPreset",
        Callback = function(value)
            local opt = type(value) == "table" and value[1] or value
            settings.riskPreset = opt
            if opt:find("1.8x") then
                settings.targetMultiplier = 1.8
            elseif opt:find("3.0x") then
                settings.targetMultiplier = 3.0
            elseif opt:find("5.0x") then
                settings.targetMultiplier = 5.0
            elseif opt:find("10.0x") then
                settings.targetMultiplier = 10.0
            elseif opt:find("25.0x") then
                settings.targetMultiplier = 25.0
            elseif opt:find("50.0x") then
                settings.targetMultiplier = 50.0
            elseif opt:find("100.0x") then
                settings.targetMultiplier = 100.0
            elseif opt:find("500.0x") then
                settings.targetMultiplier = 500.0
            elseif opt:find("750.0x") then
                settings.targetMultiplier = 750.0
            end
        end,
    })

    HarvestTab:CreateSlider({
        Name = "Target Multiplier (ตัวคูณเป้าหมายหนีฟ้าผ่า)",
        Range = {1.1, 2500.0},
        Increment = 0.5,
        CurrentValue = 5.0,
        Suffix = "x",
        Flag = "GGTargetMultiplier",
        Callback = function(v)
            settings.targetMultiplier = tonumber(v) or 5.0
        end,
    })

    HarvestTab:CreateSection("🪜 Auto Escalator (ไต่ระดับตัวคูณอัตโนมัติ)")

    HarvestTab:CreateToggle({
        Name = "Auto Escalator Ladder (ชนะแล้วขยับเป้าหมายขึ้น)",
        CurrentValue = false,
        Flag = "GGLadderMode",
        Callback = function(v)
            settings.ladderMode = v
        end,
    })

    HarvestTab:CreateSlider({
        Name = "Ladder Step (+X ทุกรอบที่ชนะ)",
        Range = {0.5, 10.0},
        Increment = 0.5,
        CurrentValue = 2.0,
        Suffix = "x",
        Flag = "GGLadderStep",
        Callback = function(v)
            settings.ladderStep = tonumber(v) or 2.0
        end,
    })

    HarvestTab:CreateSlider({
        Name = "Ladder Max Ceiling (เพดานการไต่ระดับ)",
        Range = {10.0, 500.0},
        Increment = 5.0,
        CurrentValue = 50.0,
        Suffix = "x",
        Flag = "GGLadderMax",
        Callback = function(v)
            settings.ladderMax = tonumber(v) or 50.0
        end,
    })

    HarvestTab:CreateSection("🛡️ Latency & Safety Buffer")

    HarvestTab:CreateToggle({
        Name = "Ping / Latency Compensation (ชดเชยดีเลย์เน็ต)",
        CurrentValue = true,
        Flag = "GGPingComp",
        Callback = function(v)
            settings.pingCompensation = v
        end,
    })

    HarvestTab:CreateSlider({
        Name = "Early Cashout Buffer (โดดออกก่อนถึงเป้าหมาย)",
        Range = {0.01, 0.25},
        Increment = 0.01,
        CurrentValue = 0.05,
        Suffix = "x",
        Flag = "GGLatencyBuffer",
        Callback = function(v)
            settings.latencyBuffer = tonumber(v) or 0.05
        end,
    })

    HarvestTab:CreateToggle({
        Name = "Auto Collect Dead Wood (เก็บซากไม้เมื่อฟ้าผ่า)",
        CurrentValue = true,
        Flag = "GGAutoDeadWood",
        Callback = function(v)
            settings.autoCollectDeadWood = v
        end,
    })

    HarvestTab:CreateButton({
        Name = "🚨 Emergency Cash Out Now (กดเก็บทันที)",
        Callback = function()
            doHarvestNow("Manual Emergency Button")
        end,
    })

    HarvestTab:CreateSection("📊 Live Status & Metrics")
    local statusLabel = HarvestTab:CreateLabel("Status: Idle")
    local multLabel = HarvestTab:CreateLabel("Live Multiplier: 1.00x (Peak: 1.00x | Last: 0.00x)")
    local winRateLabel = HarvestTab:CreateLabel("Win Rate: 100% (0 Cashed / 0 Crashed)")

    task.spawn(function()
        while running do
            pcall(function()
                if statusLabel and statusLabel.Set then
                    local s = stats.status
                    if currentMyRound.active then
                        s = string.format("🌱 Growing %s (Target: %.2fx)", currentMyRound.seedType, settings.targetMultiplier)
                    end
                    statusLabel:Set("Status: " .. s)
                end
                if multLabel and multLabel.Set then
                    multLabel:Set(string.format("Live Multiplier: %.2fx (Peak: %.2fx | Last: %.2fx)", stats.currentMult, stats.peakMult, stats.lastCashoutMult))
                end
                if winRateLabel and winRateLabel.Set then
                    local total = stats.successfulHarvests + stats.crashedRounds
                    local rate = total > 0 and math.floor((stats.successfulHarvests / total) * 100) or 100
                    winRateLabel:Set(string.format("Win Rate: %d%% (%d Cashed / %d Crashed)", rate, stats.successfulHarvests, stats.crashedRounds))
                end
            end)
            task.wait(0.25)
        end
    end)

    -- ─── Tab 2: Full Automation (Auto Farm) ───
    local FarmTab = Window:CreateTab("Automation", "sprout")

    FarmTab:CreateSection("🌾 Auto Re-Plant & Full Farm Loop")

    FarmTab:CreateToggle({
        Name = "Master Auto Farm Loop (Plant + Harvest + Collect)",
        CurrentValue = false,
        Flag = "GGMasterFarm",
        Callback = function(v)
            settings.masterAutoFarm = v
            if v then
                startThread("masterFarm", function(isActive)
                    while isActive() do
                        local plantModel = getMyPlantModel()
                        local isRoundActive = (plantModel ~= nil) or currentMyRound.active

                        if not isRoundActive then
                            stats.status = "Planting " .. settings.selectedSeed .. "..."
                            local planted = doPlantNow(settings.selectedSeed, settings.selectedFertilizer)
                            task.wait(settings.plantDelay)
                        else
                            local waitStart = os.clock()
                            while isActive() and (getMyPlantModel() ~= nil or currentMyRound.active) and not currentMyRound.harvested and not currentMyRound.crashed do
                                if os.clock() - waitStart > 60 then
                                    doHarvestNow("Safety Timeout (60s)")
                                    break
                                end
                                RunService.Heartbeat:Wait()
                            end

                            task.wait(0.4)

                            if settings.autoCollectFruits then
                                doCollectAllFruits()
                            end

                            if settings.autoSell then
                                doSellAllNow()
                            end
                        end
                        task.wait(0.6)
                    end
                end)
            else
                stopThread("masterFarm")
            end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Select Seed (เลือกเมล็ด)",
        Options = SEED_LIST,
        CurrentOption = {"Oak"},
        MultipleOptions = false,
        Flag = "GGSelectedSeed",
        Callback = function(value)
            settings.selectedSeed = type(value) == "table" and value[1] or value
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Select Fertilizer (ปุ๋ย)",
        Options = FERTILIZER_LIST,
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "GGSelectedFert",
        Callback = function(value)
            settings.selectedFertilizer = type(value) == "table" and value[1] or value
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Collect Dead Tree (เก็บฟืนเมื่อโดนฟ้าผ่า)",
        CurrentValue = true,
        Flag = "GGCollectDeadWood",
        Callback = function(v)
            settings.autoCollectDeadWood = v
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Collect Fruits (เก็บผลไม้ในแปลง)",
        CurrentValue = true,
        Flag = "GGCollectFruits",
        Callback = function(v)
            settings.autoCollectFruits = v
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Sell All (ขายผลไม้อัตโนมัติ)",
        CurrentValue = false,
        Flag = "GGAutoSell",
        Callback = function(v)
            settings.autoSell = v
        end,
    })

    FarmTab:CreateButton({
        Name = "Plant Seed Now (ปลูกเมล็ดทันที)",
        Callback = function()
            local ok = doPlantNow(settings.selectedSeed, settings.selectedFertilizer)
            pcall(function()
                Window:Notify({
                    Title = "Planting",
                    Content = ok and "Seed planted successfully!" or "Failed to plant seed",
                    Duration = 2,
                })
            end)
        end,
    })

    FarmTab:CreateButton({
        Name = "Collect All Fruits Now",
        Callback = function()
            doCollectAllFruits()
        end,
    })

    FarmTab:CreateButton({
        Name = "Sell All Now",
        Callback = function()
            doSellAllNow()
        end,
    })

    -- ─── Tab 3: Player ───
    local PlayerTab = Window:CreateTab("Player", "user")

    PlayerTab:CreateSection("Movement Speed")

    PlayerTab:CreateToggle({
        Name = "WalkSpeed Override",
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
        Range = {16, 150},
        Increment = 2,
        CurrentValue = 32,
        Suffix = " spd",
        Flag = "GGWalkSpeed",
        Callback = function(v)
            settings.walkSpeed = v
            local hum = getHumanoid()
            if hum and settings.autoSpeed then hum.WalkSpeed = v end
        end,
    })

    -- ─── Tab 4: Teleports ───
    local TpTab = Window:CreateTab("Teleports", "map-pin")

    TpTab:CreateSection("Fast Teleports")

    TpTab:CreateButton({
        Name = "Teleport to My Plot (ไปที่แปลงปลูก)",
        Callback = function()
            local plotCF = getPlotCFrame()
            if plotCF then tpTo(plotCF.Position) end
        end,
    })

    TpTab:CreateButton({
        Name = "Teleport to Seed Conveyor (สายพานซื้อเมล็ด)",
        Callback = function()
            local bf = workspace:FindFirstChild("BigField")
            local conveyor = bf and bf:FindFirstChild("Conveyor")
            if conveyor then tpTo(conveyor.Position + Vector3.new(0, 3, 0)) end
        end,
    })

    TpTab:CreateButton({
        Name = "Teleport to Sell Stand (ร้านขายผลไม้)",
        Callback = function()
            local bf = workspace:FindFirstChild("BigField")
            local sellStand = bf and bf:FindFirstChild("SellStand")
            if sellStand then tpTo(sellStand:GetPivot().Position) end
        end,
    })

    -- ─── Tab 5: Settings ───
    local SettingsTab = Window:CreateTab("Settings", "settings")

    SettingsTab:CreateSection("Module Information")
    SettingsTab:CreateLabel("Greedy Growers 🌱 v4.1.0 | RAVEN HUB")
    SettingsTab:CreateLabel("Author: valrinx / LILBIG4DEV")
    SettingsTab:CreateLabel("Dynamic Crash Sniping Engine active")

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

    -- ═══════════ Cleanup Lifecycle ═══════════
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
        Version = "4.1.0",
        CurrentRound = currentMyRound,
        Settings = settings,
        Stats = stats,
        HarvestNow = doHarvestNow,
        PlantNow = doPlantNow,
        CollectFruits = doCollectAllFruits,
        SellAll = doSellAllNow,
    }

    pcall(function()
        Window:Notify({
            Title = "Greedy Growers 🌱 v4.1.0",
            Content = "Loaded! Dynamic Crash Sniping is ready (Up to 500x).",
            Duration = 3,
        })
    end)
end
