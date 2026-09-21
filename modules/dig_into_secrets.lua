--[[
    RAVEN HUB | Experience Module
    Game: [W2] Dig Into Secrets (World 1 & World 2)
    PlaceIds: 119409763193569, 86641960184547
    UniverseId: 10685312778
    Features: Auto Mine | Auto Collect Current Depth | Auto Sell | Drawing Ore ESP | Auto Pets & Freebies
    Version: v1.0
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local Camera = workspace.CurrentCamera

    local player = Players.LocalPlayer
    local environment = (type(getgenv) == "function" and getgenv()) or _G

    -- Cleanup previous instance
    if type(environment.__RAVEN_DIS) == "table" and type(environment.__RAVEN_DIS.Destroy) == "function" then
        pcall(environment.__RAVEN_DIS.Destroy)
    end

    local running = true
    local connections = {}

    -- Services & Controllers
    local clientScripts = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
    local net = require(clientScripts:WaitForChild("Net"):WaitForChild("ClientNet"))
    local msgNames = require(RS:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("MessageNames"))
    local mineClient = require(clientScripts:WaitForChild("Common"):WaitForChild("MineClient"))
    local uiMgr = require(clientScripts:WaitForChild("UI"):WaitForChild("Module"):WaitForChild("UIManager"))
    local oreDefs = require(RS.Shared.Config.MineItemDefsConfig).OreDefs or {}

    -- Settings
    local settings = {
        autoCollect = false,
        autoMine = false,
        autoSell = true,
        autoClaimRewards = true,
        autoEquipBest = true,
        oreEsp = true,
        espMaxDist = 300,
        espMinRarity = 1,
    }

    -- ═══════════════════════════════════════════════════════════════
    -- 1. UTILITY & NAVIGATION
    -- ═══════════════════════════════════════════════════════════════

    local function getRoot()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getSellPart()
        local four = workspace:FindFirstChild("四个摊位")
        if four then
            local booth = four:FindFirstChild("摊位")
            if booth and booth:FindFirstChild("CheckPart") then
                return booth.CheckPart
            end
        end
        return nil
    end

    local function safeMoveTo(targetPos, duration)
        local root = getRoot()
        if not root then return false end
        local start = root.Position
        local steps = math.max(5, math.floor((duration or 0.3) * 30))
        for i = 1, steps do
            if not running then break end
            local alpha = i / steps
            root.CFrame = CFrame.new(start:Lerp(targetPos, alpha))
            task.wait((duration or 0.3) / steps)
        end
        root.CFrame = CFrame.new(targetPos)
        return true
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 2. AUTO SELL LOGIC
    -- ═══════════════════════════════════════════════════════════════

    local isSelling = false
    local function executeSell()
        if isSelling then return end
        isSelling = true

        local sellPart = getSellPart()
        local root = getRoot()
        if not sellPart or not root then
            isSelling = false
            return
        end

        local savedPos = root.CFrame
        local targetSellPos = sellPart.Position + Vector3.new(0, 3, 0)

        -- Smoothly move to sell stand
        safeMoveTo(targetSellPos, 0.4)
        task.wait(0.15)

        -- Trigger UI Sell All
        pcall(function()
            local sellPop = uiMgr.open("SellPop")
            if sellPop and type(sellPop.onClickSellAll) == "function" then
                sellPop:onClickSellAll()
            end
            task.wait(0.2)
            uiMgr.close("SellPop")
        end)

        task.wait(0.2)
        -- Return to previous position
        if root and root.Parent then
            root.CFrame = savedPos
        end

        isSelling = false
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 3. AUTO COLLECT (Current Unlocked Depth)
    -- ═══════════════════════════════════════════════════════════════

    local isCollecting = false
    local function collectCurrentStageOres()
        if isCollecting or isSelling then return end
        isCollecting = true

        local state = mineClient.getState()
        if not state then
            isCollecting = false
            return
        end

        -- Check backpack
        if settings.autoSell and state.backpackUsed >= state.backpackCapacity then
            executeSell()
            isCollecting = false
            return
        end

        local curDepth = state.depth or 1
        local stageFolder = workspace:FindFirstChild("GeneratedStages")
        local curStage = stageFolder and stageFolder:FindFirstChild("Stage_" .. tostring(curDepth))
        local oresFolder = curStage and curStage:FindFirstChild("Ores")

        if oresFolder then
            local root = getRoot()
            local ores = oresFolder:GetChildren()
            for _, oreModel in ipairs(ores) do
                if not running or not settings.autoCollect or isSelling then break end
                
                -- Check if backpack became full during loop
                local curState = mineClient.getState()
                if settings.autoSell and curState.backpackUsed >= curState.backpackCapacity then
                    executeSell()
                    break
                end

                local prompt = oreModel:FindFirstChild("CollectPrompt", true)
                if prompt and prompt.Enabled and root then
                    local orePos = oreModel:GetPivot().Position
                    local standPos = orePos + Vector3.new(0, 2, 3)

                    -- Move right next to ore
                    safeMoveTo(standPos, 0.15)
                    task.wait(0.05)

                    -- Trigger Collect
                    if type(fireproximityprompt) == "function" then
                        fireproximityprompt(prompt)
                    else
                        prompt:InputHoldBegin()
                        task.wait((prompt.HoldDuration or 0.6) + 0.05)
                        prompt:InputHoldEnd()
                    end
                    task.wait(0.1)
                end
            end
        end

        isCollecting = false
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 4. AUTO MINE (Slate Layer Fast Breaker)
    -- ═══════════════════════════════════════════════════════════════

    local isMining = false
    local function executeAutoMine()
        if isMining or isCollecting or isSelling then return end
        isMining = true

        local lm = workspace:FindFirstChild("LocalMine_" .. tostring(player.UserId))
        if lm then
            local root = getRoot()
            local targetBlock = nil
            for _, layer in ipairs(lm:GetChildren()) do
                if layer:IsA("Folder") and layer.Name:find("SlateLayer") then
                    for _, block in ipairs(layer:GetChildren()) do
                        if block:IsA("BasePart") then
                            targetBlock = block
                            break
                        end
                    end
                    if targetBlock then break end
                end
            end

            if targetBlock and root then
                local standPos = targetBlock.Position + Vector3.new(0, 2, 0)
                if (root.Position - standPos).Magnitude > 8 then
                    safeMoveTo(standPos, 0.2)
                else
                    root.CFrame = CFrame.new(standPos)
                end
            end
        end

        isMining = false
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 5. 100% DRAWING API ORE ESP
    -- ═══════════════════════════════════════════════════════════════

    local espCache = {}
    local function cleanEspEntry(entry)
        if entry.text then entry.text:Remove() end
        if entry.box then entry.box:Remove() end
    end

    local function clearAllEsp()
        for inst, entry in pairs(espCache) do
            cleanEspEntry(entry)
        end
        table.clear(espCache)
    end

    local function updateDrawingEsp()
        if not settings.oreEsp or type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
            clearAllEsp()
            return
        end

        local root = getRoot()
        if not root then
            clearAllEsp()
            return
        end

        local rootPos = root.Position
        local stages = workspace:FindFirstChild("GeneratedStages")
        local activeOres = {}

        if stages then
            for _, stage in ipairs(stages:GetChildren()) do
                local oresFolder = stage:FindFirstChild("Ores")
                if oresFolder then
                    for _, ore in ipairs(oresFolder:GetChildren()) do
                        local oreId = ore:GetAttribute("OreId")
                        if oreId and oreDefs[oreId] then
                            local def = oreDefs[oreId]
                            local rarity = def.rarity or 1
                            if rarity >= settings.espMinRarity then
                                local cf = ore:GetPivot()
                                local dist = (cf.Position - rootPos).Magnitude
                                if dist <= settings.espMaxDist then
                                    activeOres[ore] = {
                                        pos = cf.Position,
                                        name = def.name or ore.Name,
                                        rarity = rarity,
                                        val = def.value or def.price or 0,
                                        dist = dist
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Update or create drawing elements
        for ore, info in pairs(activeOres) do
            local screenPos, onScreen = Camera:WorldToViewportPoint(info.pos)
            local entry = espCache[ore]

            if onScreen and screenPos.Z > 0 then
                if not entry then
                    entry = {
                        text = Drawing.new("Text"),
                        box = Drawing.new("Square")
                    }
                    entry.text.Size = 13
                    entry.text.Center = true
                    entry.text.Outline = true
                    entry.text.OutlineColor = Color3.new(0, 0, 0)

                    entry.box.Thickness = 1
                    entry.box.Filled = false
                    espCache[ore] = entry
                end

                local color = Color3.fromHSV(math.clamp((info.rarity * 15) % 360 / 360, 0, 1), 0.8, 1)
                entry.text.Color = color
                entry.box.Color = color

                local valStr = info.val > 1e12 and string.format("%.1fT", info.val / 1e12)
                    or info.val > 1e9 and string.format("%.1fB", info.val / 1e9)
                    or info.val > 1e6 and string.format("%.1fM", info.val / 1e6)
                    or tostring(info.val)

                entry.text.Text = string.format("[%s]\n$%s | %dm", info.name, valStr, math.floor(info.dist))
                entry.text.Position = Vector2.new(screenPos.X, screenPos.Y - 20)
                entry.text.Visible = true

                local boxSize = math.clamp(1000 / screenPos.Z, 10, 40)
                entry.box.Size = Vector2.new(boxSize, boxSize)
                entry.box.Position = Vector2.new(screenPos.X - boxSize / 2, screenPos.Y - boxSize / 2)
                entry.box.Visible = true
            else
                if entry then
                    entry.text.Visible = false
                    entry.box.Visible = false
                end
            end
        end

        -- Cleanup removed ores
        for ore, entry in pairs(espCache) do
            if not activeOres[ore] or not ore.Parent then
                cleanEspEntry(entry)
                espCache[ore] = nil
            end
        end
    end

    -- ═══════════════════════════════════════════════════════════════
    -- 6. BACKGROUND AUTOMATION LOOPS
    -- ═══════════════════════════════════════════════════════════════

    -- Render Loop for ESP
    local espConn = RunService.RenderStepped:Connect(function()
        if running then
            pcall(updateDrawingEsp)
        end
    end)
    table.insert(connections, espConn)

    -- Auto Collect / Mine Loop
    task.spawn(function()
        while running do
            if settings.autoCollect then
                pcall(collectCurrentStageOres)
            end
            if settings.autoMine and not settings.autoCollect then
                pcall(executeAutoMine)
            end
            task.wait(0.35)
        end
    end)

    -- Auto Claim / Freebies Loop
    task.spawn(function()
        while running do
            if settings.autoClaimRewards then
                pcall(function()
                    net.send(msgNames.OnlineReward_Claim)
                    net.send(msgNames.SignBonus_Claim)
                    net.send(msgNames.OfflineReward_Claim)
                end)
            end
            if settings.autoEquipBest then
                pcall(function()
                    net.send(msgNames.EquipBestPets)
                end)
            end
            task.wait(15)
        end
    end)

    -- ═══════════════════════════════════════════════════════════════
    -- 7. UI TABS & SECTIONS
    -- ═══════════════════════════════════════════════════════════════

    local MainTab = Window:CreateTab("Dig Into Secrets", 4483362458)

    MainTab:CreateSection("Mining & Farming")

    MainTab:CreateToggle({
        Name = "Auto Collect Current Depth Ores",
        CurrentValue = settings.autoCollect,
        Flag = "DIS_AutoCollect",
        Callback = function(val)
            settings.autoCollect = val
        end,
    })

    MainTab:CreateToggle({
        Name = "Auto Mine (Break Blocks & Progress)",
        CurrentValue = settings.autoMine,
        Flag = "DIS_AutoMine",
        Callback = function(val)
            settings.autoMine = val
        end,
    })

    MainTab:CreateToggle({
        Name = "Auto Sell on Full Backpack",
        CurrentValue = settings.autoSell,
        Flag = "DIS_AutoSell",
        Callback = function(val)
            settings.autoSell = val
        end,
    })

    MainTab:CreateButton({
        Name = "Sell All Ores Now",
        Callback = function()
            task.spawn(executeSell)
        end,
    })

    MainTab:CreateSection("Visuals & Ore ESP (100% Drawing)")

    MainTab:CreateToggle({
        Name = "Enable Ore ESP",
        CurrentValue = settings.oreEsp,
        Flag = "DIS_OreEsp",
        Callback = function(val)
            settings.oreEsp = val
            if not val then clearAllEsp() end
        end,
    })

    MainTab:CreateSlider({
        Name = "ESP Max Distance",
        Range = {50, 1500},
        Increment = 25,
        Suffix = "studs",
        CurrentValue = settings.espMaxDist,
        Flag = "DIS_EspMaxDist",
        Callback = function(val)
            settings.espMaxDist = val
        end,
    })

    MainTab:CreateSlider({
        Name = "ESP Min Rarity",
        Range = {1, 21},
        Increment = 1,
        Suffix = "Tier",
        CurrentValue = settings.espMinRarity,
        Flag = "DIS_EspMinRarity",
        Callback = function(val)
            settings.espMinRarity = val
        end,
    })

    MainTab:CreateSection("Pets & Automation")

    MainTab:CreateToggle({
        Name = "Auto Claim Free Rewards & Sign-in",
        CurrentValue = settings.autoClaimRewards,
        Flag = "DIS_AutoClaim",
        Callback = function(val)
            settings.autoClaimRewards = val
        end,
    })

    MainTab:CreateToggle({
        Name = "Auto Equip Best Pets",
        CurrentValue = settings.autoEquipBest,
        Flag = "DIS_AutoEquip",
        Callback = function(val)
            settings.autoEquipBest = val
        end,
    })

    MainTab:CreateSection("Teleports")

    MainTab:CreateButton({
        Name = "Teleport to Surface (Spawn)",
        Callback = function()
            local surf = workspace:FindFirstChild("AllPos") and workspace.AllPos:FindFirstChild("SurfacePos")
            local root = getRoot()
            if surf and root then
                root.CFrame = CFrame.new(surf.WorldPosition + Vector3.new(0, 3, 0))
            end
        end,
    })

    MainTab:CreateButton({
        Name = "Teleport to Sell Stand",
        Callback = function()
            local sellPart = getSellPart()
            local root = getRoot()
            if sellPart and root then
                root.CFrame = CFrame.new(sellPart.Position + Vector3.new(0, 3, 0))
            end
        end,
    })

    MainTab:CreateButton({
        Name = "Teleport to Current Mine Depth",
        Callback = function()
            local state = mineClient.getState()
            local curDepth = state and state.depth or 1
            local stageFolder = workspace:FindFirstChild("GeneratedStages")
            local curStage = stageFolder and stageFolder:FindFirstChild("Stage_" .. tostring(curDepth))
            local root = getRoot()
            if curStage and root then
                root.CFrame = curStage:GetPivot() + Vector3.new(0, 4, 0)
            end
        end,
    })

    -- ═══════════════════════════════════════════════════════════════
    -- 8. CLEANUP & REGISTRATION
    -- ═══════════════════════════════════════════════════════════════

    local function destroyModule()
        running = false
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        clearAllEsp()
        environment.__RAVEN_DIS = nil
    end

    environment.__RAVEN_DIS = {
        Destroy = destroyModule
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyModule)
    end
end
