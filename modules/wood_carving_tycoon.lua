-- ============================================================
--   RAVEN HUB | Wood Carving Tycoon
--   Instant 100% Accuracy Auto Carve & Farm Automation
-- ============================================================

return function(Window, runtimeInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local ReplicatedFirst = game:GetService("ReplicatedFirst")
    local localPlayer = Players.LocalPlayer

    local environment = getgenv()
    if type(environment.__RAVEN_WOOD_CARVING) == "table"
        and type(environment.__RAVEN_WOOD_CARVING.Destroy) == "function" then
        pcall(environment.__RAVEN_WOOD_CARVING.Destroy)
    end

    local settings = {
        AutoCarve = true,
        AutoCarveNext = true,
        NextDelay = 0.35,
        AutoEnterLathe = false,
        AutoDepositCarved = false,
        AutoRerollSeeds = false,
        RerollDelay = 2.0,
        AutoCollectSeeds = false,
        MinCollectRarity = "All",
        AutoWoodChipper = false,
        MaxChipRarity = "Common",
    }

    local stats = {
        CarvedCount = 0,
        CurrentAccuracy = 0,
        CurrentWood = "None",
        Status = "Idle",
        PedestalSeedsText = "None",
    }

    local running = true
    local lastNextClick = 0
    local lastEnterPrompt = 0
    local lastDepositPrompt = 0
    local isSaving = false

    -- Safe patch for Client.AskServer and Client.TellServer
    -- Disables honeypot / getfenv().writefile checks that crash executor calls with attempt to index nil with 'FireServer'
    pcall(function()
        local Client = require(ReplicatedFirst.Client)
        local REM = ReplicatedStorage:WaitForChild("REM", 5)
        if not Client or not REM then return end

        if not Client.__RavenPatched then
            Client.AskServer = function(self, remoteName, payload, callback)
                local hash = self:CreateKeyHash(remoteName)
                local remoteId = self.CachedRemotes[hash]
                if not remoteId then
                    local start = os.clock()
                    while not self.CachedRemotes[hash] and os.clock() - start < 2 do
                        task.wait()
                    end
                    remoteId = self.CachedRemotes[hash]
                end
                local remote = remoteId and REM:FindFirstChild(remoteId)
                if remote then
                    task.spawn(function()
                        local ok, ret = pcall(function()
                            return remote:InvokeServer(payload)
                        end)
                        if ok and callback then
                            pcall(callback, ret)
                        end
                    end)
                end
            end

            Client.TellServer = function(self, remoteName, payload)
                local hash = self:CreateKeyHash(remoteName)
                local remoteId = self.CachedRemotes[hash]
                if not remoteId then
                    local start = os.clock()
                    while not self.CachedRemotes[hash] and os.clock() - start < 2 do
                        task.wait()
                    end
                    remoteId = self.CachedRemotes[hash]
                end
                local remote = remoteId and REM:FindFirstChild(remoteId)
                if remote then
                    task.spawn(function()
                        pcall(function()
                            remote:FireServer(payload)
                        end)
                    end)
                end
            end

            Client.__RavenPatched = true
        end
    end)

    -- Helper: get Tycoon folder for current player
    local function getMyTycoon()
        local tycoonId = localPlayer:GetAttribute("TycoonId")
        local tycoonName = localPlayer:GetAttribute("TycoonName")
        local tycoons = workspace:FindFirstChild("Tycoons")
        if not tycoons then return nil end

        if tycoonName and tycoons:FindFirstChild(tycoonName) then
            return tycoons[tycoonName]
        end
        if tycoonId and tycoons:FindFirstChild("Tycoon" .. tostring(tycoonId)) then
            return tycoons["Tycoon" .. tostring(tycoonId)]
        end
        return nil
    end

    -- Helper: get world position of any ProximityPrompt
    local function getPromptPosition(prompt)
        if not prompt or not prompt.Parent then return nil end
        local parent = prompt.Parent
        if parent:IsA("BasePart") then
            return parent.Position
        elseif parent:IsA("Attachment") then
            return parent.WorldPosition
        elseif parent.Parent and parent.Parent:IsA("BasePart") then
            return parent.Parent.Position
        end
        return nil
    end

    -- Helper: reliably trigger ProximityPrompt without visible teleporting (Micro-spoof)
    local function triggerPrompt(prompt, forceNearby)
        if not prompt or not fireproximityprompt then return false end

        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local promptPos = getPromptPosition(prompt)

        local savedCF = nil
        if forceNearby and root and promptPos then
            local dist = (root.Position - promptPos).Magnitude
            if dist > (prompt.MaxActivationDistance or 12) then
                savedCF = root.CFrame
                -- Micro-spoof: shift CFrame directly adjacent for only milliseconds
                root.CFrame = CFrame.new(promptPos + Vector3.new(0, 2, 0))
                task.wait(0.04)
            end
        end

        local oldHold = prompt.HoldDuration
        pcall(function() prompt.HoldDuration = 0 end)
        pcall(function() fireproximityprompt(prompt, 0) end)
        task.wait(0.04)
        pcall(function() fireproximityprompt(prompt) end)
        pcall(function() prompt.HoldDuration = oldHold end)

        if savedCF and root then
            root.CFrame = savedCF
        end

        return true
    end

    -- Helper: check if player is holding or carrying carved wood
    local function hasCarvedWoodInInventory()
        local bp = localPlayer:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if item:IsA("Tool") and item.Name ~= "Bronze Axe" and not item.Name:lower():find("axe") then
                    return true
                end
            end
        end
        local char = localPlayer.Character
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and item.Name ~= "Bronze Axe" and not item.Name:lower():find("axe") then
                    return true
                end
            end
        end
        return false
    end

    -- ============================================================
    --   Seed Economy & Pedestal Reroll Helpers
    -- ============================================================
    local RARITY_RANK = {
        ["Common"] = 1,
        ["Uncommon"] = 2,
        ["Rare"] = 3,
        ["Epic"] = 4,
        ["Legendary"] = 5,
        ["Mythical"] = 6,
        ["Sacred"] = 7,
        ["Ethereal"] = 8,
        ["Celestial"] = 9,
        ["Secret"] = 10,
        ["Cosmic"] = 11,
        ["Transcendent"] = 12,
        ["Super Secret"] = 13,
    }

    local RARITY_PRICES = {
        ["Common"] = 100,
        ["Uncommon"] = 200,
        ["Rare"] = 400,
        ["Epic"] = 800,
        ["Legendary"] = 1600,
        ["Mythical"] = 2500,
        ["Sacred"] = 4500,
        ["Ethereal"] = 6667,
        ["Celestial"] = 40000,
        ["Secret"] = 140000,
        ["Cosmic"] = 200000,
        ["Transcendent"] = 800000,
        ["Super Secret"] = 4000000,
    }

    local function formatPrice(val)
        if not val or val <= 0 then return "$0" end
        if val >= 1000000 then
            return string.format("$%.1fM", val / 1000000):gsub("%.0M", "M")
        elseif val >= 1000 then
            return string.format("$%.1fK", val / 1000):gsub("%.0K", "K")
        end
        return "$" .. tostring(val)
    end

    local function getPedestalSeeds()
        local tycoon = getMyTycoon()
        if not tycoon then return {} end
        local genSeedsFolder = tycoon:FindFirstChild("GeneratedSeeds")
        if not genSeedsFolder then return {} end

        local WoodEconomy
        pcall(function()
            WoodEconomy = require(ReplicatedStorage.Shared.WoodEconomy)
        end)

        local seeds = {}
        for _, s in ipairs(genSeedsFolder:GetChildren()) do
            local prompt = s:FindFirstChild("GrabSeedPrompt", true)
            if prompt then
                local treeType = s:GetAttribute("GeneratedTreeType") or s.Name
                local rarity = "Common"
                if WoodEconomy and WoodEconomy.NormalizeWoodId and WoodEconomy.GetWoodRarity then
                    local norm = WoodEconomy.NormalizeWoodId(treeType)
                    rarity = WoodEconomy.GetWoodRarity(norm) or "Common"
                end
                local rank = RARITY_RANK[rarity] or 1
                local price = RARITY_PRICES[rarity] or 100

                table.insert(seeds, {
                    Model = s,
                    Prompt = prompt,
                    Name = s.Name,
                    TreeType = treeType,
                    Rarity = rarity,
                    Rank = rank,
                    Price = price,
                    FormattedPrice = formatPrice(price)
                })
            end
        end

        table.sort(seeds, function(a, b)
            return a.Name < b.Name
        end)

        return seeds
    end

    local function collectSeed(seedInfo)
        if not seedInfo or not seedInfo.Prompt then return false end
        return triggerPrompt(seedInfo.Prompt, true)
    end

    local function confirmRerollProtectedModal()
        pcall(function()
            local SeedReroll = require(ReplicatedFirst.Client.SeedReroll)
            if SeedReroll and type(SeedReroll.ConfirmProtectedReroll) == "function" then
                SeedReroll:ConfirmProtectedReroll()
            end
        end)
    end

    local function pullRerollLever()
        local tycoon = getMyTycoon()
        if not tycoon then return false end
        local rerollFolder = tycoon:FindFirstChild("TycoonRoot") and tycoon.TycoonRoot:FindFirstChild("Reroll")
        local leverPrompt = rerollFolder and rerollFolder:FindFirstChild("ProximityPrompt", true)
        if not leverPrompt then return false end

        local success = triggerPrompt(leverPrompt, true)
        task.delay(0.3, confirmRerollProtectedModal)
        return success
    end

    -- ============================================================
    --   Wood Chipper (Seed Destroyer) Helpers
    -- ============================================================
    local function getBackpackSeedsForChipper(maxRarityName)
        local maxRank = maxRarityName == "All" and 999 or (RARITY_RANK[maxRarityName] or 1)
        local bp = localPlayer:FindFirstChild("Backpack")
        local char = localPlayer.Character
        local matches = {}

        local function checkItem(tool)
            if not tool:IsA("Tool") then return end
            local isSeed = tool:GetAttribute("TreeSeed") == true or tool.Name:find("Seed") ~= nil
            if not isSeed then return end

            local rarity = tool:GetAttribute("SeedRarity")
            if not rarity then
                local treeType = tool:GetAttribute("TreeType")
                if treeType then
                    local WoodEconomy = require(ReplicatedStorage.Shared.WoodEconomy)
                    rarity = WoodEconomy.GetWoodRarity(WoodEconomy.NormalizeWoodId(treeType))
                end
            end
            rarity = rarity or "Common"
            local rank = RARITY_RANK[rarity] or 1

            if rank <= maxRank then
                table.insert(matches, {
                    Tool = tool,
                    Name = tool.Name,
                    Rarity = rarity,
                    Rank = rank
                })
            end
        end

        if bp then
            for _, t in ipairs(bp:GetChildren()) do checkItem(t) end
        end
        if char then
            for _, t in ipairs(char:GetChildren()) do checkItem(t) end
        end

        return matches
    end

    local function chipSeedTool(seedTool)
        local tycoon = getMyTycoon()
        if not tycoon then return false end
        local chipper = tycoon:FindFirstChild("WoodChipper", true)
        local prompt = chipper and chipper:FindFirstChild("WoodChipperPrompt", true)
        if not prompt or not prompt.Enabled then return false end

        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum then return false end

        -- 1. Equip seed
        if seedTool.Parent == localPlayer:FindFirstChild("Backpack") then
            hum:EquipTool(seedTool)
            task.wait(0.2)
        end

        -- 2. Micro-spoof to chipper to trigger prompt
        local chipperPos = getPromptPosition(prompt)
        local savedCF = root.CFrame
        if chipperPos and (root.Position - chipperPos).Magnitude > 10 then
            root.CFrame = CFrame.new(chipperPos + Vector3.new(0, 2, 2))
            task.wait(0.04)
        end

        -- 3. Fire prompt
        local oldHold = prompt.HoldDuration
        pcall(function() prompt.HoldDuration = 0 end)
        pcall(function() fireproximityprompt(prompt, 0) end)
        task.wait(0.04)
        pcall(function() fireproximityprompt(prompt) end)
        pcall(function() prompt.HoldDuration = oldHold end)

        -- Instantly restore original player position so player never visually walks/stays at chipper
        if savedCF and root then
            root.CFrame = savedCF
        end

        -- 4. Auto-confirm via WoodChipperBulk GUI (GUI is local and remains open)
        local pg = localPlayer:FindFirstChild("PlayerGui")
        local confirmed = false
        local startTime = os.clock()

        while os.clock() - startTime < 1.8 do
            local bulkGui = pg and pg:FindFirstChild("WoodChipperBulk")
            if bulkGui and bulkGui.Enabled then
                local allBtn, chipBtn
                for _, d in ipairs(bulkGui:GetDescendants()) do
                    if d:IsA("TextButton") then
                        local lbl = d:FindFirstChildOfClass("TextLabel") or d.Parent:FindFirstChildOfClass("TextLabel")
                        local t = lbl and lbl.Text or d.Text
                        if t == "All" then
                            allBtn = d
                        elseif t:find("Chip") then
                            chipBtn = d
                        end
                    end
                end

                if allBtn then
                    for _, c in ipairs(getconnections(allBtn.MouseButton1Click)) do c:Fire() end
                    for _, c in ipairs(getconnections(allBtn.Activated)) do c:Fire() end
                    task.wait(0.1)
                end

                if chipBtn then
                    for _, c in ipairs(getconnections(chipBtn.MouseButton1Click)) do c:Fire() end
                    for _, c in ipairs(getconnections(chipBtn.Activated)) do c:Fire() end
                    confirmed = true
                    break
                end
            end
            task.wait(0.05)
        end

        return confirmed
    end

    -- Helper: get active Lathe context from WoodCarvingMain UI
    local function getLatheContext()
        local pg = localPlayer:FindFirstChild("PlayerGui")
        if not pg then return nil, "No PlayerGui" end

        local woodGui = pg:FindFirstChild("WoodCarvingMain")
        if not woodGui then return nil, "No WoodCarvingMain" end

        local confirmFrame = woodGui:FindFirstChild("Confirm", true)
        local carveNext = confirmFrame and confirmFrame:FindFirstChild("CarveNext", true)
        local button = carveNext and carveNext:FindFirstChild("Button", true)
        if not button then return nil, "No CarveNext button" end

        local conns = getconnections(button.MouseButton1Click)
        if #conns == 0 then conns = getconnections(button.Activated) end
        if #conns == 0 then return nil, "No button connections" end

        local accuracyUI = getupvalue(conns[1].Function, 1)
        if not accuracyUI or not accuracyUI.OnConfirm then return nil, "No AccuracyUI" end

        local wcController = getupvalue(accuracyUI.OnConfirm, 1)
        if not wcController or not wcController.Lathe then return nil, "No wcController" end

        local lathe = wcController.Lathe
        if not lathe.TargetProfile or not lathe.Cylinder then return nil, "Workpiece not ready" end

        return {
            gui = woodGui,
            accuracyUI = accuracyUI,
            wcController = wcController,
            lathe = lathe,
            confirmButton = button
        }
    end

    -- Core function: Perform instant 100% carve
    local function performInstant100Carve()
        local ctx, err = getLatheContext()
        if not ctx then
            return false, err or "Lathe not accessible"
        end

        local lathe = ctx.lathe
        local targetRadii = lathe.TargetProfile.Profile and lathe.TargetProfile.Profile.Radii
        local cylProfile = lathe.Cylinder.Profile
        if not targetRadii or not cylProfile or not cylProfile.Radii then
            return false, "Profiles not initialized"
        end

        local modified = lathe.Cylinder.ModifiedSlices or {}
        lathe.Cylinder.ModifiedSlices = modified

        -- 1. Overwrite all slice radii with target shape
        for i, targetRadius in ipairs(targetRadii) do
            cylProfile.Radii[i] = targetRadius
            modified[i] = true
        end

        lathe.HasModifiedWood = true

        -- 2. Update 3D mesh slices on lathe bench
        pcall(function()
            lathe.Cylinder:UpdateSlices()
        end)

        -- 3. Calculate 100% accuracy
        local calcResult = lathe.AccuracyCalculator:Calculate()
        lathe.AccuracyResult = calcResult

        -- 4. Update UI to 100% and enable Carve Next
        pcall(function()
            ctx.accuracyUI:SetConfirmEnabled(true)
            ctx.accuracyUI:Update(
                calcResult,
                lathe:GetActiveWoodId(),
                lathe:GetActiveMutation(),
                lathe:IsActiveWoodMega()
            )
        end)

        local progressLabel = ctx.gui:FindFirstChild("ProgressLabel", true)
        if progressLabel then
            progressLabel.Text = "100% Accuracy"
        end

        stats.CurrentAccuracy = calcResult.Accuracy or 100
        stats.CurrentWood = tostring(lathe:GetActiveWoodId() or "Unknown")

        return true, calcResult.Accuracy
    end

    -- Direct, safe save and carve next handler
    -- Prevents saving hangs and advances to the next workpiece smoothly
    local function saveAndCarveNext()
        if isSaving then return false end

        local ctx = getLatheContext()
        if not ctx then return false end

        local wcController = ctx.wcController
        local lathe = ctx.lathe

        -- Clear stuck SavePending if needed
        wcController.SavePending = false
        isSaving = true
        stats.Status = "Saving Carved Log..."

        task.spawn(function()
            -- 1. Ensure 100% accuracy carve applied
            performInstant100Carve()

            -- 2. Build complete serialized payload
            local woodId = lathe:GetActiveWoodId()
            local variantId = lathe:GetActiveVariantId()
            local Ser = require(ReplicatedStorage.Shared.WoodCarving.Serializer)
            local cylSer = Ser.SerializeCarvedLog(lathe)
            local targetSer = Ser.SerializeCarvedLog(lathe:GetTargetProfile(), woodId)

            local payload = {
                SessionId = wcController.LatheSessionId,
                WorkpieceId = wcController.LatheWorkpieceId,
                WoodId = woodId,
                VariantId = variantId,
                Mutation = lathe:GetActiveMutation() or "None",
                Serialized = cylSer,
                TargetSerialized = targetSer
            }

            -- 3. Invoke SaveCarvedWood RemoteFunction
            local client = wcController.Client or require(ReplicatedFirst.Client)
            local hash = client:CreateKeyHash("SaveCarvedWood")
            local remId = client.CachedRemotes and client.CachedRemotes[hash]
            local rem = remId and ReplicatedStorage.REM:FindFirstChild(remId)

            local ok, serverResp = pcall(function()
                if rem then
                    return rem:InvokeServer(payload)
                else
                    return ReplicatedStorage.REM["3adbf815-b8cf-4125-86df-7c71dc04a533"]:InvokeServer(payload)
                end
            end)

            wcController.SavePending = false

            if ok and type(serverResp) == "table" then
                if serverResp.RawWoodVariants then
                    pcall(function() wcController:ApplyServerRawWoodVariants(serverResp.RawWoodVariants) end)
                end
                pcall(function() wcController:OptimisticallyConsumeRawWood(payload.WoodId, payload.VariantId) end)

                if serverResp.Success then
                    stats.CarvedCount = stats.CarvedCount + 1
                    stats.Status = "Carved Successfully!"

                    -- Mount next uncut log
                    local nextWood = wcController:GetFirstAvailableRawWoodVariantId()
                    if nextWood then
                        pcall(function() wcController:BeginLocalCarvingWorkpiece(nextWood) end)
                    else
                        -- No logs left in inventory, exit lathe gracefully
                        stats.Status = "No Uncut Logs Left"
                        pcall(function() wcController:ResetLathe() end)
                        pcall(function() wcController:ExitLathe() end)
                    end
                else
                    -- Handle server error (e.g., already saved or out of sync)
                    local nextWood = wcController:GetFirstAvailableRawWoodVariantId()
                    if nextWood then
                        pcall(function() wcController:BeginLocalCarvingWorkpiece(nextWood) end)
                    else
                        stats.Status = "Lathe Finished"
                        pcall(function() wcController:ResetLathe() end)
                        pcall(function() wcController:ExitLathe() end)
                    end
                end
            else
                -- Fallback via button connections if remote invocation fails
                pcall(function()
                    for _, conn in ipairs(getconnections(ctx.confirmButton.MouseButton1Click)) do
                        conn:Fire()
                    end
                    for _, conn in ipairs(getconnections(ctx.confirmButton.Activated)) do
                        conn:Fire()
                    end
                end)
            end

            task.wait(settings.NextDelay)
            isSaving = false
        end)

        return true
    end

    -- Build MacLib / RAVENHUB UI
    local tab = Window:CreateTab("Wood Carving", "hammer")
    tab:CreateSection("Auto Carve 100%")

    local statusLabel = tab:CreateLabel("Status: Idle | Accuracy: 0% | Carved: 0")

    tab:CreateToggle({
        Name = "Auto Carve 100% Accuracy",
        CurrentValue = settings.AutoCarve,
        Flag = "WCT_AutoCarve",
        Callback = function(value)
            settings.AutoCarve = (value == true)
        end,
    })

    tab:CreateToggle({
        Name = "Auto Click 'Carve Next'",
        CurrentValue = settings.AutoCarveNext,
        Flag = "WCT_AutoCarveNext",
        Callback = function(value)
            settings.AutoCarveNext = (value == true)
        end,
    })

    tab:CreateSlider({
        Name = "Carve Next Delay",
        Range = {0.1, 1.5},
        Increment = 0.05,
        CurrentValue = settings.NextDelay,
        Suffix = " s",
        Flag = "WCT_NextDelay",
        Callback = function(value)
            settings.NextDelay = value
        end,
    })

    tab:CreateButton({
        Name = "Carve 100% Now (Manual Trigger)",
        Callback = function()
            local ok, accOrErr = performInstant100Carve()
            if ok then
                pcall(function()
                    Window:Notify({
                        Title = "Auto Carve",
                        Content = "Successfully carved to 100% Accuracy!",
                        Duration = 3,
                    })
                end)
            else
                pcall(function()
                    Window:Notify({
                        Title = "Auto Carve",
                        Content = "Cannot carve: " .. tostring(accOrErr),
                        Duration = 3,
                    })
                end)
            end
        end,
    })

    tab:CreateButton({
        Name = "Save & Carve Next Now (Manual Trigger)",
        Callback = function()
            saveAndCarveNext()
        end,
    })

    tab:CreateSection("Tycoon Lathe & Wood Automation")

    tab:CreateToggle({
        Name = "Auto Re-enter Lathe (Proximity)",
        CurrentValue = settings.AutoEnterLathe,
        Flag = "WCT_AutoEnterLathe",
        Callback = function(value)
            settings.AutoEnterLathe = (value == true)
        end,
    })

    tab:CreateToggle({
        Name = "Auto Deposit All Carved Wood",
        CurrentValue = settings.AutoDepositCarved,
        Flag = "WCT_AutoDepositCarved",
        Callback = function(value)
            settings.AutoDepositCarved = (value == true)
        end,
    })

    tab:CreateButton({
        Name = "Deposit All Carved Wood Now",
        Callback = function()
            local tycoon = getMyTycoon()
            local prompt = tycoon and tycoon:FindFirstChild("DepositAllCarvedWoodPrompt", true)
            if prompt then
                local success = triggerPrompt(prompt, true)
                pcall(function()
                    Window:Notify({
                        Title = "Wood Stack",
                        Content = success and "Triggered Deposit All Carved Wood!" or "Failed to trigger prompt.",
                        Duration = 2.5,
                    })
                end)
            else
                pcall(function()
                    Window:Notify({
                        Title = "Wood Stack",
                        Content = "DepositAllCarvedWoodPrompt not found in Tycoon.",
                        Duration = 2.5,
                    })
                end)
            end
        end,
    })

    -- ============================================================
    --   Seed Farm & Reroll Section
    -- ============================================================
    tab:CreateSection("Seed Farm & Reroll")

    local seedStatusLabel = tab:CreateLabel("Seeds: Inspecting pedestals...")

    tab:CreateToggle({
        Name = "Auto Collect Seeds",
        CurrentValue = settings.AutoCollectSeeds,
        Flag = "WCT_AutoCollectSeeds",
        Callback = function(value)
            settings.AutoCollectSeeds = (value == true)
        end,
    })

    tab:CreateDropdown({
        Name = "Min Rarity to Collect",
        Options = {
            "All",
            "Common",
            "Uncommon",
            "Rare",
            "Epic",
            "Legendary",
            "Mythical",
            "Sacred",
            "Ethereal",
            "Celestial",
            "Secret",
            "Cosmic",
            "Transcendent",
        },
        CurrentValue = settings.MinCollectRarity,
        Flag = "WCT_MinCollectRarity",
        Callback = function(value)
            settings.MinCollectRarity = value
        end,
    })

    tab:CreateToggle({
        Name = "Auto Reroll Seeds",
        CurrentValue = settings.AutoRerollSeeds,
        Flag = "WCT_AutoRerollSeeds",
        Callback = function(value)
            settings.AutoRerollSeeds = (value == true)
        end,
    })

    tab:CreateSlider({
        Name = "Reroll Delay",
        Range = {1.5, 5.0},
        Increment = 0.1,
        CurrentValue = settings.RerollDelay,
        Suffix = " s",
        Flag = "WCT_RerollDelay",
        Callback = function(value)
            settings.RerollDelay = value
        end,
    })

    tab:CreateButton({
        Name = "Collect Matching Seeds Now",
        Callback = function()
            local seeds = getPedestalSeeds()
            local targetRank = settings.MinCollectRarity == "All" and 0 or (RARITY_RANK[settings.MinCollectRarity] or 0)
            local collected = 0
            for _, s in ipairs(seeds) do
                if s.Rank >= targetRank then
                    if collectSeed(s) then
                        collected = collected + 1
                        task.wait(0.1)
                    end
                end
            end
            pcall(function()
                Window:Notify({
                    Title = "Seed Collector",
                    Content = string.format("Collected %d seeds matching >= %s", collected, settings.MinCollectRarity),
                    Duration = 2.5,
                })
            end)
        end,
    })

    tab:CreateButton({
        Name = "Collect All Seeds Now",
        Callback = function()
            local seeds = getPedestalSeeds()
            local collected = 0
            for _, s in ipairs(seeds) do
                if collectSeed(s) then
                    collected = collected + 1
                    task.wait(0.1)
                end
            end
            pcall(function()
                Window:Notify({
                    Title = "Seed Collector",
                    Content = string.format("Collected all %d seeds!", collected),
                    Duration = 2.5,
                })
            end)
        end,
    })

    tab:CreateButton({
        Name = "Reroll Seeds Now (Pull Lever)",
        Callback = function()
            local ok = pullRerollLever()
            pcall(function()
                Window:Notify({
                    Title = "Seed Reroll",
                    Content = ok and "Reroll lever pulled!" or "Could not pull reroll lever.",
                    Duration = 2.5,
                })
            end)
        end,
    })

    -- ============================================================
    --   Wood Chipper (Seed Destroyer) Section
    -- ============================================================
    tab:CreateSection("Wood Chipper (Destroy Seeds)")

    tab:CreateToggle({
        Name = "Auto Wood Chipper (Destroy Seeds)",
        CurrentValue = settings.AutoWoodChipper,
        Flag = "WCT_AutoWoodChipper",
        Callback = function(value)
            settings.AutoWoodChipper = (value == true)
        end,
    })

    tab:CreateDropdown({
        Name = "Max Rarity to Destroy (<= Level)",
        Options = {
            "Common",
            "Uncommon",
            "Rare",
            "Epic",
            "Legendary",
            "Mythical",
            "Sacred",
            "Ethereal",
            "Celestial",
            "Secret",
            "Cosmic",
            "Transcendent",
            "All",
        },
        CurrentValue = settings.MaxChipRarity,
        Flag = "WCT_MaxChipRarity",
        Callback = function(value)
            settings.MaxChipRarity = value
        end,
    })

    tab:CreateButton({
        Name = "Destroy Matching Seeds Now",
        Callback = function()
            local matches = getBackpackSeedsForChipper(settings.MaxChipRarity)
            if #matches == 0 then
                pcall(function()
                    Window:Notify({
                        Title = "Wood Chipper",
                        Content = "No seeds found matching <= " .. tostring(settings.MaxChipRarity),
                        Duration = 2.5,
                    })
                end)
                return
            end

            local chippedCount = 0
            for _, m in ipairs(matches) do
                if chipSeedTool(m.Tool) then
                    chippedCount = chippedCount + 1
                    task.wait(0.3)
                end
            end

            pcall(function()
                Window:Notify({
                    Title = "Wood Chipper",
                    Content = string.format("Chipped %d seed types!", chippedCount),
                    Duration = 2.5,
                })
            end)
        end,
    })

    -- Main Automation Worker Loop
    local lastRerollTime = 0
    local lastSeedScanTime = 0
    local lastChipTime = 0

    task.spawn(function()
        while running do
            local isCarving = localPlayer:GetAttribute("WoodCarvingActive") == true
            local now = os.clock()

            if isCarving then
                local ctx = getLatheContext()
                if ctx and ctx.lathe and ctx.lathe.TargetProfile then
                    local currentAcc = ctx.lathe.AccuracyResult and ctx.lathe.AccuracyResult.Accuracy or 0
                    stats.CurrentAccuracy = currentAcc
                    stats.CurrentWood = tostring(ctx.lathe:GetActiveWoodId() or "Unknown")

                    if not isSaving then
                        stats.Status = "Carving on Lathe"

                        -- 1. Auto Carve to 100%
                        if settings.AutoCarve and currentAcc < 100 then
                            performInstant100Carve()
                            currentAcc = 100
                        end

                        -- 2. Auto Save & Carve Next
                        if settings.AutoCarveNext and currentAcc >= 100 then
                            if now - lastNextClick >= settings.NextDelay then
                                lastNextClick = now
                                saveAndCarveNext()
                            end
                        end
                    end
                end
            else
                if not isSaving then
                    stats.Status = "Idle / Roaming"
                end
                stats.CurrentAccuracy = 0

                -- Auto enter lathe if enabled and prompt is near
                if settings.AutoEnterLathe and now - lastEnterPrompt >= 1.0 then
                    lastEnterPrompt = now
                    local tycoon = getMyTycoon()
                    local lathePrompt = tycoon and tycoon:FindFirstChild("WoodLathePrompt", true)
                    if lathePrompt and lathePrompt.Enabled then
                        local char = localPlayer.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local pos = getPromptPosition(lathePrompt)
                        if root and pos then
                            local dist = (root.Position - pos).Magnitude
                            if dist <= (lathePrompt.MaxActivationDistance or 10) + 3 then
                                triggerPrompt(lathePrompt, false)
                            end
                        end
                    end
                end

                -- Auto deposit carved wood if enabled and player holds/has carved wood
                if settings.AutoDepositCarved and now - lastDepositPrompt >= 2.0 then
                    lastDepositPrompt = now
                    local tycoon = getMyTycoon()
                    local depPrompt = tycoon and tycoon:FindFirstChild("DepositAllCarvedWoodPrompt", true)
                    if depPrompt and (depPrompt.Enabled or hasCarvedWoodInInventory()) then
                        local char = localPlayer.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local pos = getPromptPosition(depPrompt)
                        if root and pos then
                            local dist = (root.Position - pos).Magnitude
                            if dist <= (depPrompt.MaxActivationDistance or 12) + 4 then
                                triggerPrompt(depPrompt, false)
                            end
                        end
                    end
                end

                -- ============================================================
                --   Seed Farming & Reroll Automation
                -- ============================================================
                local pedestalSeeds = getPedestalSeeds()
                local seedDescriptions = {}
                local targetRank = settings.MinCollectRarity == "All" and 0 or (RARITY_RANK[settings.MinCollectRarity] or 0)
                local uncollectedMatchingSeeds = {}

                for idx, s in ipairs(pedestalSeeds) do
                    table.insert(seedDescriptions, string.format("[%s: %s (%s)]", s.TreeType, s.Rarity, s.FormattedPrice))
                    if s.Rank >= targetRank then
                        table.insert(uncollectedMatchingSeeds, s)
                    end
                end

                if #seedDescriptions > 0 then
                    stats.PedestalSeedsText = table.concat(seedDescriptions, " ")
                else
                    stats.PedestalSeedsText = "None (Rerolling...)"
                end

                -- Auto collect matching seeds
                if settings.AutoCollectSeeds and #uncollectedMatchingSeeds > 0 then
                    for _, s in ipairs(uncollectedMatchingSeeds) do
                        collectSeed(s)
                        task.wait(0.12)
                    end
                    -- Update pedestal list after collection
                    pedestalSeeds = getPedestalSeeds()
                    uncollectedMatchingSeeds = {}
                    for _, s in ipairs(pedestalSeeds) do
                        if s.Rank >= targetRank then
                            table.insert(uncollectedMatchingSeeds, s)
                        end
                    end
                end

                -- Auto reroll seeds (only when all wanted seeds have been collected)
                if settings.AutoRerollSeeds and #uncollectedMatchingSeeds == 0 then
                    if now - lastRerollTime >= settings.RerollDelay then
                        lastRerollTime = now
                        pullRerollLever()
                    end
                end

                -- Auto wood chipper (destroy seeds in backpack matching <= MaxChipRarity)
                if settings.AutoWoodChipper and now - lastChipTime >= 1.5 then
                    lastChipTime = now
                    local chipMatches = getBackpackSeedsForChipper(settings.MaxChipRarity)
                    if #chipMatches > 0 then
                        chipSeedTool(chipMatches[1].Tool)
                    end
                end
            end

            -- Refresh Status Labels
            pcall(function()
                statusLabel:Set(string.format(
                    "Status: %s | Wood: %s | Acc: %d%% | Carved: %d",
                    stats.Status,
                    stats.CurrentWood,
                    math.floor(stats.CurrentAccuracy),
                    stats.CarvedCount
                ))
            end)

            pcall(function()
                seedStatusLabel:Set("Seeds: " .. tostring(stats.PedestalSeedsText or "None"))
            end)

            task.wait(0.2)
        end
    end)

    -- Cleanup on destroy
    local function destroy()
        if not running then return end
        running = false
        if environment.__RAVEN_WOOD_CARVING
            and environment.__RAVEN_WOOD_CARVING.Settings == settings then
            environment.__RAVEN_WOOD_CARVING = nil
        end
    end

    environment.__RAVEN_WOOD_CARVING = {
        Version = "v1.2.0",
        Settings = settings,
        Stats = stats,
        PerformInstant100Carve = performInstant100Carve,
        SaveAndCarveNext = saveAndCarveNext,
        TriggerPrompt = triggerPrompt,
        GetLatheContext = getLatheContext,
        GetBackpackSeedsForChipper = getBackpackSeedsForChipper,
        ChipSeedTool = chipSeedTool,
        Destroy = destroy,
    }

    if runtimeInfo and type(runtimeInfo.registerCleanup) == "function" then
        runtimeInfo.registerCleanup(destroy)
    end
end
