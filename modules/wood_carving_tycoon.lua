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
    }

    local stats = {
        CarvedCount = 0,
        CurrentAccuracy = 0,
        CurrentWood = "None",
        Status = "Idle",
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

    -- Helper: reliably trigger ProximityPrompt
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
                root.CFrame = CFrame.new(promptPos + Vector3.new(0, 2, 0))
                task.wait(0.1)
            end
        end

        local oldHold = prompt.HoldDuration
        pcall(function() prompt.HoldDuration = 0 end)
        pcall(function() fireproximityprompt(prompt, 0) end)
        pcall(function() fireproximityprompt(prompt, 1) end)
        pcall(function() fireproximityprompt(prompt) end)

        task.delay(0.15, function()
            pcall(function() prompt.HoldDuration = oldHold end)
            if savedCF and root then
                pcall(function() root.CFrame = savedCF end)
            end
        end)

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

    -- Main Automation Worker Loop
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
            end

            -- Refresh Status Label
            pcall(function()
                statusLabel:Set(string.format(
                    "Status: %s | Wood: %s | Acc: %d%% | Carved: %d",
                    stats.Status,
                    stats.CurrentWood,
                    math.floor(stats.CurrentAccuracy),
                    stats.CarvedCount
                ))
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
        Version = "v1.1.0",
        Settings = settings,
        Stats = stats,
        PerformInstant100Carve = performInstant100Carve,
        SaveAndCarveNext = saveAndCarveNext,
        TriggerPrompt = triggerPrompt,
        GetLatheContext = getLatheContext,
        Destroy = destroy,
    }

    if runtimeInfo and type(runtimeInfo.registerCleanup) == "function" then
        runtimeInfo.registerCleanup(destroy)
    end
end
