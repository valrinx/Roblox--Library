--[[
    RAVEN HUB | Fishing Chef
    PlaceId: 88599461076137 | GameId: 8955905923
    Version: v1.1.0

    All-In-One Auto Farm Money:
    🎣 Auto Fish -> 📦 Check Orders / Stock -> 🍳 Auto Cook / Deposit -> 🍽️ Auto Serve Customers -> 💰 Collect Profit
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local VirtualUser = game:GetService("VirtualUser")
    local UserInputService = game:GetService("UserInputService")

    local player = Players.LocalPlayer
    local environment = getgenv()

    -- Teardown old instance
    if type(environment.__RAVEN_FISHING_CHEF) == "table"
        and type(environment.__RAVEN_FISHING_CHEF.Destroy) == "function" then
        pcall(environment.__RAVEN_FISHING_CHEF.Destroy)
    end

    local running = true
    local connections = {}

    -- Settings
    local settings = {
        allInOneFarm = false,
        farmMode = "Chef & Restaurant Loop", -- "Chef & Restaurant Loop" or "Instant Sell Farm"
        targetFishCount = 5, -- Custom target fish count before returning to restaurant
        autoFish = false,
        instantReel = true,
        autoSell = false,
        sellThreshold = 5,
        autoDepositStock = false,
        autoServeCustomers = true,
        autoCollectEarnings = true,
        autoClaimDaily = false,
        autoInstantCook = true, -- Auto-solve minigames with 100% Perfect quality instantly
        walkSpeed = 16,
        jumpPower = 50,
        infiniteJump = false,
        noclip = false,
        antiAfk = true,
    }

    local liveFarmState = "OFF"
    local liveFarmStatus = "[OFF] Idle"
    local sessionFishCaught = 0

    -- Controllers & Services
    local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Client"):WaitForChild("Controllers")
    local fishingCtrl = require(controllers:WaitForChild("FishingController"))
    local biteMinigame = require(controllers:WaitForChild("FishingController"):WaitForChild("BiteMinigame"))
    local castValidation = require(controllers:WaitForChild("FishingController"):WaitForChild("CastValidation"))
    local dataCtrl = require(controllers:WaitForChild("DataController"))
    local rsc = require(controllers:WaitForChild("RestaurantStockController"))

    local knitServices = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")
    local dailyRewardsService = knitServices:FindFirstChild("DailyRewardsService")

    -- Positions
    local PIER_SPOT = {
        pos = Vector3.new(456.09, 9.88, -904),
        look = Vector3.new(456.09, 9.88, -930)
    }
    local RESTAURANT_SPOT = {
        pos = Vector3.new(528.98, 10.45, -693.04),
        look = Vector3.new(523.69, 9.82, -701.15)
    }

    local FISHING_SPOTS = {
        ["Starting Dock Pier (Auto Farm)"] = PIER_SPOT,
        ["My Restaurant Stall"] = RESTAURANT_SPOT,
        ["Koi Pond"] = {pos = Vector3.new(-122.9, 19.5, -1337.3), look = Vector3.new(-120, 19.5, -1350)},
        ["Moon Tuna"] = {pos = Vector3.new(-10.1, 20.3, -754.3), look = Vector3.new(0, 20.3, -770)},
        ["Dragon Hunt"] = {pos = Vector3.new(-83.1, 135.0, -1334.8), look = Vector3.new(-83, 135.0, -1350)},
        ["Megalodon Area"] = {pos = Vector3.new(2.3, 20.3, 209.1), look = Vector3.new(10, 20.3, 220)},
        ["Prehistoric Island"] = {pos = Vector3.new(-1528.2, 99.4, -1773.5), look = Vector3.new(-1520, 99.4, -1790)},
        ["Bamboo Forest"] = {pos = Vector3.new(-2309.2, 18.2, -778.2), look = Vector3.new(-2300, 18.2, -790)},
        ["Razor Reef"] = {pos = Vector3.new(-1314.3, 19.5, 1625.3), look = Vector3.new(-1310, 19.5, 1640)}
    }

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function() ui:Notify({Title = title, Content = content, Duration = 4}) end)
        end
    end

    local function getCharacter()
        return player.Character or player.CharacterAdded:Wait()
    end

    local function teleportTo(cframe)
        local char = getCharacter()
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = cframe end
    end

    local function equipRod()
        local char = getCharacter()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end

        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:find("Rod") then return true end
        end

        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:find("Rod") then
                hum:EquipTool(tool)
                task.wait(0.2)
                return true
            end
        end
        return false
    end

    local function equipPlateTool()
        local char = getCharacter()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end

        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and (tool.Name:find("Nigiri") or tool.Name:find("Sushi") or tool.Name:find("Sashimi")) then
                return true
            end
        end

        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") and (tool.Name:find("Nigiri") or tool.Name:find("Sushi") or tool.Name:find("Sashimi")) then
                hum:EquipTool(tool)
                task.wait(0.2)
                return true
            end
        end
        return false
    end

    local function getFishCount()
        local ok, data = pcall(function() return dataCtrl:GetData() end)
        if ok and data and data.Fish then return #data.Fish end
        return 0
    end

    local function getCash()
        local ok, data = pcall(function() return dataCtrl:GetData() end)
        if ok and data and data.Cash then return data.Cash end
        return 0
    end

    local function getLevel()
        local ok, data = pcall(function() return dataCtrl:GetData() end)
        if ok and data and data.Level then return data.Level end
        return 1
    end

    local internalCast = nil
    local function resolveCastFunction()
        if internalCast then return internalCast end
        pcall(function()
            local ups = debug.getupvalues(fishingCtrl.SetAutoFishEnabled)
            local loopFunc = ups[10]
            if type(loopFunc) == "function" then
                local cfUps = debug.getupvalues(loopFunc)
                if type(cfUps[7]) == "function" then
                    internalCast = cfUps[7]
                end
            end
        end)
        return internalCast
    end

    local function sellAllFish()
        pcall(function() fishingCtrl:SellFish("all") end)
    end

    local function depositAllFish()
        pcall(function()
            if rsc and rsc.Server and rsc.Server.DepositAll then
                rsc.Server.DepositAll:Fire()
            end
        end)
    end

    local function collectEarnings()
        pcall(function()
            if fishingCtrl.PlotServer and fishingCtrl.PlotServer.CollectOfflineEarnings then
                fishingCtrl.PlotServer.CollectOfflineEarnings:Fire()
            end
        end)
    end

    local function claimDaily()
        pcall(function()
            if dailyRewardsService and dailyRewardsService:FindFirstChild("RF") and dailyRewardsService.RF:FindFirstChild("Claim") then
                dailyRewardsService.RF.Claim:InvokeServer()
            end
        end)
    end

    -- Find customer 3D model in workspace corresponding to ActiveNPCs.Customer
    local function findCustomerModel(customerNpc)
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj:IsA("Model") and (obj.Name == "" or obj.Name == "Customer") then
                local fb = obj:FindFirstChild("Fallback")
                if fb and fb.Value == customerNpc then
                    return obj
                end
            end
        end
        return nil
    end

    -- Real instant cook from inventory fish into plates
    local function cookDish(recipe)
        local ok, data = pcall(function() return dataCtrl:GetData() end)
        if not (ok and data and data.Fish and #data.Fish > 0) then
            return false, "No fish"
        end

        local fish = data.Fish[1]
        local fishID = fish.ID

        -- Start cut session
        pcall(function()
            local prom = fishingCtrl.Server:StartCutSession()
            if prom and prom.await then prom:await() end
        end)

        -- Cut fish (score 3)
        local cutOk = false
        pcall(function()
            local prom = fishingCtrl.Server:CutFish(fishID, 3)
            if prom and prom.await then
                local s, res = prom:await()
                cutOk = s
            end
        end)
        if not cutOk then return false, "CutFish failed" end

        -- Request Restaurant Data to get filet
        local filet = nil
        pcall(function()
            local prom = fishingCtrl.Server:RequestRestaurauntData()
            if prom and prom.await then
                local s, res = prom:await()
                if s and res and #res > 0 then
                    filet = res[#res]
                end
            end
        end)
        if not filet then return false, "No filet found" end

        -- Cook meal
        local cookOk = false
        pcall(function()
            local prom = fishingCtrl.Server:Cook(recipe, filet, recipe == "Sashimi" and 3 or nil)
            if prom and prom.await then
                local s, res = prom:await()
                cookOk = s
            end
        end)

        task.wait(0.3)
        return cookOk
    end

    -- Equip plate matching the dish order
    local function equipPlateForDish(dishName)
        local ok, data = pcall(function() return dataCtrl:GetData() end)
        if not (ok and data and data.Plates) then return false end

        local targetPlate = nil
        for _, p in ipairs(data.Plates) do
            if p.Name == dishName then
                targetPlate = p
                break
            end
        end

        if not targetPlate then return false end

        -- Fire EquipPlate
        pcall(function()
            fishingCtrl.Server.EquipPlate:Fire(targetPlate.ID)
        end)
        task.wait(0.3)

        -- Equip the tool from backpack to character
        local char = getCharacter()
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end

        for _, tool in ipairs(char:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:find(dishName) then
                return true
            end
        end

        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:find(dishName) then
                hum:EquipTool(tool)
                task.wait(0.2)
                return true
            end
        end

        return false
    end

    -- Serve customers waiting at player's restaurant
    local function serveWaitingCustomers()
        local active = workspace:FindFirstChild("Code") and workspace.Code:FindFirstChild("ActiveNPCs")
        if not active then return 0 end

        local char = getCharacter()
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return 0 end

        local servedCount = 0

        for _, c in ipairs(active:GetChildren()) do
            local ownerVal = c:FindFirstChild("Owner") and c.Owner.Value
            if ownerVal == player.Name and c:GetAttribute("WaitingForFood") == true then
                local order = c:GetAttribute("Order")
                if order and order ~= "" then
                    -- 1. Ensure we have the plate equipped
                    local hasPlate = equipPlateForDish(order)
                    if not hasPlate then
                        -- Cook dish from fish
                        liveFarmStatus = string.format("[COOKING] Cooking %s...", tostring(order))
                        local cooked = cookDish(order)
                        if cooked then
                            hasPlate = equipPlateForDish(order)
                        end
                    end

                    if hasPlate then
                        -- Teleport to customer
                        liveFarmStatus = string.format("[SERVE] Delivering %s...", tostring(order))
                        local model = findCustomerModel(c)
                        local loc = model and model:GetPivot().Position or (c:FindFirstChild("Location") and c.Location.Value and c.Location.Value.Position)
                        if loc then
                            hrp.CFrame = CFrame.new(loc + Vector3.new(0, 1.2, 2), loc)
                            task.wait(0.3)

                            c:SetAttribute("PendingFeed", true)
                            pcall(function()
                                fishingCtrl.Server.StoreFood:Fire(c)
                            end)

                            local prompt = model and model:FindFirstChildWhichIsA("ProximityPrompt", true)
                            if prompt then
                                prompt.Enabled = true
                                if fireproximityprompt then
                                    fireproximityprompt(prompt)
                                else
                                    prompt:InputHoldBegin()
                                    task.wait(prompt.HoldDuration)
                                    prompt:InputHoldEnd()
                                end
                            end

                            task.wait(0.8)
                            servedCount = servedCount + 1
                        end
                    end
                end
            end
        end
        return servedCount
    end

    -- Get list of current active orders at restaurant
    local function getActiveCustomerOrders()
        local active = workspace:FindFirstChild("Code") and workspace.Code:FindFirstChild("ActiveNPCs")
        if not active then return {} end

        local list = {}
        for _, c in ipairs(active:GetChildren()) do
            local ownerVal = c:FindFirstChild("Owner") and c.Owner.Value
            if ownerVal == player.Name then
                table.insert(list, {
                    order = c:GetAttribute("Order") or "None",
                    orderText = c:GetAttribute("OrderText") or "Ordering...",
                    waiting = c:GetAttribute("WaitingForFood") == true,
                    delivered = c:GetAttribute("PlateDelivered") == true,
                    reward = c:GetAttribute("RewardDisplay_Cash") or c:GetAttribute("PlateValue") or "Pending"
                })
            end
        end
        return list
    end

    local function getRestaurantCFrame()
        local ok, plotCtrl = pcall(function()
            local Knit = require(ReplicatedStorage.Packages.Knit)
            return Knit.GetController("PlotController")
        end)
        if ok and plotCtrl then
            local plot = plotCtrl.Plot or (workspace:FindFirstChild("Code") and workspace.Code.Plots:FindFirstChild(player.Name))
            local cs = plot and plot:FindFirstChild("STALL") and plot.STALL:FindFirstChild("CookingStation")
            if cs then
                return cs:GetPivot() + Vector3.new(0, 3, 5)
            end
            if plotCtrl.PlotPos then
                return CFrame.new(plotCtrl.PlotPos + Vector3.new(0, 3, 5))
            end
        end
        return CFrame.lookAt(RESTAURANT_SPOT.pos, RESTAURANT_SPOT.look)
    end

    -- ============================================================
    --   MASTER ALL-IN-ONE FARM LOOP
    -- ============================================================
    task.spawn(function()
        local state = "FISH" -- "FISH", "COOK_DEPOSIT", "SERVE", "COLLECT"
        local fishCycleCount = 0

        while running do
            task.wait(0.3)

            if settings.allInOneFarm then
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")

                if hrp then
                    if settings.farmMode == "Instant Sell Farm" then
                        -- FAST SELL MODE: Pier -> Native AutoFish -> Instant Reel -> Auto Sell
                        liveFarmState = "FAST_SELL"
                        liveFarmStatus = string.format("[FAST SELL] Fish: %d / %d", getFishCount(), settings.targetFishCount)
                        local spot = PIER_SPOT
                        if (hrp.Position - spot.pos).Magnitude > 10 then
                            teleportTo(CFrame.lookAt(spot.pos, spot.look))
                            task.wait(0.5)
                        end

                        equipRod()
                        pcall(function() fishingCtrl:SetAutoFishEnabled(true) end)

                        if biteMinigame.InProgress then
                            biteMinigame.ProgressValue = 1
                            pcall(function() biteMinigame:End(true) end)
                            task.wait(0.4)
                        end

                        if getFishCount() >= settings.targetFishCount then
                            pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)
                            sellAllFish()
                            task.wait(0.4)
                        end

                    elseif settings.farmMode == "Chef & Restaurant Loop" then
                        local fishCount = getFishCount()
                        local platesCount = 0
                        local okP, dataP = pcall(function() return dataCtrl:GetData() end)
                        if okP and dataP and dataP.Plates then platesCount = #dataP.Plates end

                        -- 1. FISH STATE: Catch fish at pier until targetFishCount is reached
                        if state == "FISH" then
                            if fishCount >= settings.targetFishCount then
                                pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)
                                state = "GO_RESTAURANT"
                                liveFarmState = "GO_RESTAURANT"
                                liveFarmStatus = string.format("[WAIT ORDER] Target reached (%d/%d). Returning to Restaurant...", fishCount, settings.targetFishCount)
                            else
                                liveFarmState = "FISH"
                                liveFarmStatus = string.format("[FISHING] Caught: %d / %d", fishCount, settings.targetFishCount)
                                local spot = PIER_SPOT
                                if (hrp.Position - spot.pos).Magnitude > 10 then
                                    teleportTo(CFrame.lookAt(spot.pos, spot.look))
                                    task.wait(0.5)
                                end

                                equipRod()
                                pcall(function() fishingCtrl:SetAutoFishEnabled(true) end)

                                if biteMinigame.InProgress then
                                    biteMinigame.ProgressValue = 1
                                    pcall(function() biteMinigame:End(true) end)
                                    task.wait(0.4)
                                end
                            end

                        -- 2. GO_RESTAURANT STATE: Travel back to restaurant
                        elseif state == "GO_RESTAURANT" then
                            pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)
                            liveFarmState = "GO_RESTAURANT"
                            liveFarmStatus = string.format("[WAIT ORDER] Returning to Restaurant (%d fish)...", fishCount)
                            local stallCf = getRestaurantCFrame()
                            teleportTo(stallCf)
                            task.wait(0.6)
                            state = "SERVE_UNTIL_EMPTY"

                        -- 3. SERVE_UNTIL_EMPTY STATE: Wait order -> Cook dish -> Serve until bag is empty
                        elseif state == "SERVE_UNTIL_EMPTY" then
                            pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)

                            if fishCount <= 0 and platesCount <= 0 then
                                liveFarmState = "FISH"
                                liveFarmStatus = "[FISHING] Fish depleted! Returning to pier to catch more..."
                                notify("Auto Farm", "Fish depleted! Returning to Pier to fish...")
                                state = "FISH"
                                task.wait(0.5)
                            else
                                local activeOrders = getActiveCustomerOrders()
                                local waitingCount = 0
                                for _, o in ipairs(activeOrders) do
                                    if o.waiting then waitingCount = waitingCount + 1 end
                                end

                                if waitingCount > 0 then
                                    liveFarmState = "COOK_AND_SERVE"
                                    local served = serveWaitingCustomers()
                                    if served > 0 then
                                        collectEarnings()
                                    end
                                    task.wait(0.5)
                                else
                                    liveFarmState = "WAIT_ORDER"
                                    liveFarmStatus = string.format("[WAIT ORDER] Standing by at stall... (%d fish remaining)", fishCount)
                                    local stallCf = getRestaurantCFrame()
                                    if (hrp.Position - stallCf.Position).Magnitude > 15 then
                                        teleportTo(stallCf)
                                    end
                                    collectEarnings()
                                    task.wait(1)
                                end
                            end
                        end
                    end
                end
            else
                liveFarmState = "OFF"
                liveFarmStatus = "[OFF] Idle"
                -- When AllInOne is toggled off, ensure native auto fish is disabled
                if not settings.autoFish then
                    pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)
                end
            end
        end
    end)

    -- Separate Standalone Auto Fish Loop (PURE FISHING ONLY - NO RESTAURANT / NO COOK / NO SELL)
    task.spawn(function()
        local lastFishCount = getFishCount()
        while running do
            task.wait(0.25)
            if settings.autoFish and not settings.allInOneFarm then
                local char = player.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")

                if hrp then
                    equipRod()
                    pcall(function() fishingCtrl:SetAutoFishEnabled(true) end)

                    if biteMinigame.InProgress then
                        if settings.instantReel then
                            biteMinigame.ProgressValue = 1
                            pcall(function() biteMinigame:End(true) end)
                            task.wait(0.3)
                        else
                            biteMinigame:SetAutoClickEnabled(true)
                        end
                    end

                    -- Track session catches purely for display
                    local currentCount = getFishCount()
                    if currentCount > lastFishCount then
                        sessionFishCaught = sessionFishCaught + (currentCount - lastFishCount)
                    end
                    lastFishCount = currentCount
                end
            elseif not settings.allInOneFarm then
                pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)
            end
        end
    end)

    -- Background Earnings & Daily
    task.spawn(function()
        local lastEarnAt, lastDailyAt = 0, 0
        while running do
            task.wait(1)
            local now = os.clock()
            if settings.autoCollectEarnings and now - lastEarnAt >= 10 then
                lastEarnAt = now
                collectEarnings()
            end
            if settings.autoClaimDaily and now - lastDailyAt >= 60 then
                lastDailyAt = now
                claimDaily()
            end
        end
    end)

    -- Auto Instant Perfect Minigames (Cutting & Cooking)
    task.spawn(function()
        local vim = game:GetService("VirtualInputManager")
        while running do
            task.wait(0.1)
            if settings.autoInstantCook then
                -- 1. Keep fast cooking active to skip stove/cooking minigames instantly
                pcall(function()
                    player:SetAttribute("FastCookingUntil", workspace:GetServerTimeNow() + 86400)
                end)

                -- 2. If CutMinigame GUI is visible, auto-hit 100% Perfect
                pcall(function()
                    local cm = player.PlayerGui:FindFirstChild("Main") and player.PlayerGui.Main:FindFirstChild("Frames") and player.PlayerGui.Main.Frames:FindFirstChild("CutMinigame")
                    if cm and cm.Visible then
                        local bar = cm:FindFirstChild("Bar")
                        local cursor = bar and bar:FindFirstChild("Cursor")
                        local innerBar = bar and bar:FindFirstChild("Bar")
                        local fade = innerBar and innerBar:FindFirstChild("Fade")
                        if cursor and fade then
                            cursor.Position = fade.Position
                            task.wait(0.04)
                            vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                            task.wait(0.04)
                            vim:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                            task.wait(0.12)
                        end
                    end
                end)
            end
        end
    end)

    -- Utility Connections
    table.insert(connections, player.Idled:Connect(function()
        if settings.antiAfk then
            pcall(function()
                VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
                task.wait(0.2)
                VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
            end)
        end
    end))

    table.insert(connections, UserInputService.JumpRequest:Connect(function()
        if settings.infiniteJump then
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end))

    table.insert(connections, RunService.Stepped:Connect(function()
        if settings.noclip then
            local char = player.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end
    end))

    -- ============================================================
    --   USER INTERFACE
    -- ============================================================

    -- TAB 1: 💰 ALL IN ONE FARM (MONEY LOOP)
    local FarmTab = Window:CreateTab("💰 Auto Farm", "dollar-sign")
    FarmTab:CreateSection("All-In-One Money Machine")

    FarmTab:CreateToggle({
        Name = "Enable All-In-One Farm",
        CurrentValue = false,
        Flag = "FC_AllInOne",
        Callback = function(val)
            settings.allInOneFarm = val
            if val then
                settings.autoFish = false
                notify("Auto Farm", "All-In-One Money Machine Started! Mode: " .. settings.farmMode)
            else
                notify("Auto Farm", "Stopped.")
            end
        end
    })

    FarmTab:CreateDropdown({
        Name = "Farm Routine",
        Options = {"Chef & Restaurant Loop", "Instant Sell Farm"},
        CurrentOption = "Chef & Restaurant Loop",
        Flag = "FC_FarmRoutine",
        Callback = function(opt)
            settings.farmMode = opt
            notify("Routine", "Switched to: " .. opt)
        end
    })

    FarmTab:CreateSlider({
        Name = "Target Fish Count (Fish to Catch)",
        Range = {1, 50},
        Increment = 1,
        CurrentValue = 5,
        Suffix = " fish",
        Flag = "FC_TargetFish",
        Callback = function(val)
            settings.targetFishCount = val
            settings.sellThreshold = val
        end
    })

    FarmTab:CreateSection("One-Click Batch Actions")

    FarmTab:CreateButton({
        Name = "Serve All Waiting Customers Now 🍽️",
        Callback = function()
            local served = serveWaitingCustomers()
            notify("Restaurant", string.format("Served %d customer(s)!", served))
        end
    })

    FarmTab:CreateButton({
        Name = "Deposit All Fish to Kitchen Stock 📦",
        Callback = function()
            local count = getFishCount()
            depositAllFish()
            notify("Kitchen", string.format("Deposited %d fish to stock!", count))
        end
    })

    FarmTab:CreateButton({
        Name = "Collect Restaurant Earnings 💵",
        Callback = function()
            collectEarnings()
            notify("Earnings", "Earnings collected to wallet!")
        end
    })

    FarmTab:CreateSection("Workflow Status & Active Orders")
    local statusLabel = FarmTab:CreateLabel("Workflow: [OFF] Idle")
    local ordersLabel = FarmTab:CreateLabel("Active Orders: Scanning...")

    task.spawn(function()
        while running do
            task.wait(1)
            pcall(function()
                if statusLabel and type(statusLabel.Set) == "function" then
                    statusLabel:Set("Workflow: " .. liveFarmStatus)
                end
                if ordersLabel and type(ordersLabel.Set) == "function" then
                    local orders = getActiveCustomerOrders()
                    if #orders == 0 then
                        ordersLabel:Set("Active Orders: No customers seated.")
                    else
                        local lines = {}
                        for i, o in ipairs(orders) do
                            local st = o.waiting and "Waiting" or (o.delivered and "Served" or "Ordering")
                            table.insert(lines, string.format("#%d: %s [%s] ($%s)", i, o.orderText, st, tostring(o.reward)))
                        end
                        ordersLabel:Set("Active Orders:\n" .. table.concat(lines, "\n"))
                    end
                end
            end)
        end
    end)

    -- TAB 2: 🎣 Standalone Fishing
    local FishTab = Window:CreateTab("🎣 Fishing", "fish")
    FishTab:CreateSection("Live Fish Inventory")
    local fishStatusLabel = FishTab:CreateLabel("Fish in Bag: Checking...")

    task.spawn(function()
        while running do
            task.wait(1)
            pcall(function()
                if fishStatusLabel and type(fishStatusLabel.Set) == "function" then
                    local count = getFishCount()
                    fishStatusLabel:Set(string.format("Fish in Bag: %d items | Session Caught: %d", count, sessionFishCaught))
                end
            end)
        end
    end)

    FishTab:CreateSection("Standalone Fishing Controls")

    FishTab:CreateToggle({
        Name = "Auto Fish (Continuous)",
        CurrentValue = false,
        Flag = "FC_AutoFish",
        Callback = function(val)
            settings.autoFish = val
            if val then
                settings.allInOneFarm = false
                equipRod()
                pcall(function() fishingCtrl:SetAutoFishEnabled(true) end)
                notify("Fishing", "Standalone Auto Fish started! Fishing continuously.")
            else
                pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)
                notify("Fishing", "Auto Fish stopped.")
            end
        end
    })

    FishTab:CreateToggle({
        Name = "Instant Reel (Fast Catch)",
        CurrentValue = true,
        Flag = "FC_InstantReel",
        Callback = function(val) settings.instantReel = val end
    })

    FishTab:CreateButton({
        Name = "TP to Best Pier Spot",
        Callback = function()
            teleportTo(CFrame.lookAt(PIER_SPOT.pos, PIER_SPOT.look))
            notify("Travel", "Arrived at Pier!")
        end
    })

    FishTab:CreateButton({
        Name = "Sell All Fish Now 💰",
        Callback = function()
            local count = getFishCount()
            sellAllFish()
            notify("Sell Fish", string.format("Sold all fish! (Bag had %d)", count))
        end
    })

    -- TAB 3: 🍳 Kitchen & Cooking
    local CookTab = Window:CreateTab("🍳 Kitchen", "coffee")
    CookTab:CreateSection("Auto Minigame Solvers")

    CookTab:CreateToggle({
        Name = "Auto Perfect Cooking (Minigames)",
        CurrentValue = true,
        Flag = "FC_AutoPerfectCook",
        Callback = function(val)
            settings.autoInstantCook = val
            if val then
                notify("Kitchen", "Auto Perfect minigame solver enabled!")
            else
                notify("Kitchen", "Auto Perfect minigame solver disabled.")
            end
        end
    })

    CookTab:CreateSection("Instant Recipe Cooking")

    CookTab:CreateButton({
        Name = "Cook Nigiri (Instant Perfect) 🍣",
        Callback = function()
            local ok, err = cookDish("Nigiri")
            if ok then
                notify("Kitchen", "Cooked Nigiri (Perfect Quality)!")
            else
                notify("Kitchen", "Cook failed: " .. tostring(err or "No fish"))
            end
        end
    })

    CookTab:CreateButton({
        Name = "Cook Sashimi (Instant Perfect) 🐟",
        Callback = function()
            local ok, err = cookDish("Sashimi")
            if ok then
                notify("Kitchen", "Cooked Sashimi (Perfect Quality)!")
            else
                notify("Kitchen", "Cook failed: " .. tostring(err or "No fish"))
            end
        end
    })

    CookTab:CreateButton({
        Name = "Cook Sushi (Instant Perfect) 🍱",
        Callback = function()
            local ok, err = cookDish("Sushi")
            if ok then
                notify("Kitchen", "Cooked Sushi (Perfect Quality)!")
            else
                notify("Kitchen", "Cook failed: " .. tostring(err or "No fish"))
            end
        end
    })

    CookTab:CreateButton({
        Name = "Cook All Fish into Dishes (Batch) ⚡",
        Callback = function()
            local initialCount = getFishCount()
            if initialCount <= 0 then
                notify("Kitchen", "No fish in bag to cook!")
                return
            end
            notify("Kitchen", string.format("Cooking %d fish into dishes...", initialCount))
            local cooked = 0
            while getFishCount() > 0 do
                local ok = cookDish("Sashimi")
                if not ok then
                    ok = cookDish("Nigiri")
                end
                if ok then
                    cooked = cooked + 1
                    task.wait(0.2)
                else
                    break
                end
            end
            notify("Kitchen", string.format("Successfully cooked %d dishes!", cooked))
        end
    })

    CookTab:CreateSection("Stall & Restaurant")

    CookTab:CreateButton({
        Name = "TP to My Restaurant",
        Callback = function()
            local stallCf = getRestaurantCFrame()
            teleportTo(stallCf)
            notify("Travel", "Arrived at Restaurant!")
        end
    })

    -- TAB 4: 🎁 Rewards
    local RewardTab = Window:CreateTab("🎁 Rewards", "gift")
    RewardTab:CreateSection("Daily & Free Spins")

    RewardTab:CreateToggle({
        Name = "Auto Claim Daily",
        CurrentValue = false,
        Flag = "FC_AutoDaily",
        Callback = function(val) settings.autoClaimDaily = val end
    })

    RewardTab:CreateButton({
        Name = "Claim Daily Reward Now",
        Callback = function()
            claimDaily()
            notify("Rewards", "Daily reward claim sent!")
        end
    })

    RewardTab:CreateButton({
        Name = "Spin Wheel (Free Spin)",
        Callback = function()
            pcall(function() knitServices.Spin.RE.RequestSpin:FireServer() end)
            notify("Spin", "Spin request sent!")
        end
    })

    -- TAB 5: 📍 Teleports
    local TravelTab = Window:CreateTab("📍 Teleport", "map-pin")
    TravelTab:CreateSection("Fishing Biomes")

    for spotName, spotData in pairs(FISHING_SPOTS) do
        TravelTab:CreateButton({
            Name = spotName,
            Callback = function()
                teleportTo(CFrame.lookAt(spotData.pos, spotData.look))
                notify("Travel", "Teleported to " .. spotName)
            end
        })
    end

    -- TAB 6: ⚙ Utility
    local UtilTab = Window:CreateTab("⚙ Utility", "sliders")
    UtilTab:CreateSection("Movement & Player Mods")

    UtilTab:CreateSlider({
        Name = "WalkSpeed",
        Range = {16, 150},
        Increment = 1,
        CurrentValue = 16,
        Suffix = " studs/s",
        Flag = "FC_WalkSpeed",
        Callback = function(val)
            settings.walkSpeed = val
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed = val end
        end
    })

    UtilTab:CreateSlider({
        Name = "JumpPower",
        Range = {50, 200},
        Increment = 5,
        CurrentValue = 50,
        Suffix = " power",
        Flag = "FC_JumpPower",
        Callback = function(val)
            settings.jumpPower = val
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.UseJumpPower = true
                hum.JumpPower = val
            end
        end
    })

    UtilTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = false,
        Flag = "FC_InfiniteJump",
        Callback = function(val) settings.infiniteJump = val end
    })

    UtilTab:CreateToggle({
        Name = "Noclip",
        CurrentValue = false,
        Flag = "FC_Noclip",
        Callback = function(val) settings.noclip = val end
    })

    UtilTab:CreateToggle({
        Name = "Anti-AFK",
        CurrentValue = true,
        Flag = "FC_AntiAfk",
        Callback = function(val) settings.antiAfk = val end
    })

    UtilTab:CreateSection("Live Stats")
    local statsLabel = UtilTab:CreateLabel(string.format("Cash: $%d | Level: %d | Fish: %d", getCash(), getLevel(), getFishCount()))

    task.spawn(function()
        while running do
            task.wait(2)
            pcall(function()
                if statsLabel and type(statsLabel.Set) == "function" then
                    statsLabel:Set(string.format("Cash: $%d | Level: %d | Fish: %d", getCash(), getLevel(), getFishCount()))
                end
            end)
        end
    end)

    -- Tab Sorting
    pcall(function()
        if Window.SortTabs then
            Window:SortTabs({"💰 Auto Farm", "🎣 Fishing", "🍳 Kitchen", "🎁 Rewards", "📍 Teleport", "⚙ Utility"})
        end
    end)

    -- Teardown
    local moduleHandle = {
        Settings = settings,
        Destroy = function()
            running = false
            pcall(function() fishingCtrl:SetAutoFishEnabled(false) end)
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            table.clear(connections)
        end
    }

    environment.__RAVEN_FISHING_CHEF = moduleHandle
    return moduleHandle
end
