-- ============================================================
--   RAVEN HUB | Wood Carving Tycoon
--   Instant 100% Accuracy Auto Carve & Farm Automation
-- ============================================================

return function(Window, runtimeInfo)
    local Players = game:GetService("Players")
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
                0,
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

    -- Trigger Carve Next button click safely
    local function clickCarveNext()
        local ctx = getLatheContext()
        if not ctx or not ctx.confirmButton then return false end

        for _, conn in ipairs(getconnections(ctx.confirmButton.MouseButton1Click)) do
            conn:Fire()
        end
        for _, conn in ipairs(getconnections(ctx.confirmButton.Activated)) do
            conn:Fire()
        end
        stats.CarvedCount = stats.CarvedCount + 1
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

    tab:CreateSection("Tycoon Lathe Automation")

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
            if prompt and fireproximityprompt then
                fireproximityprompt(prompt)
                pcall(function()
                    Window:Notify({
                        Title = "Wood Stack",
                        Content = "Triggered Deposit All Carved Wood!",
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
                stats.Status = "Carving on Lathe"
                local ctx = getLatheContext()
                if ctx and ctx.lathe and ctx.lathe.TargetProfile then
                    local currentAcc = ctx.lathe.AccuracyResult and ctx.lathe.AccuracyResult.Accuracy or 0
                    stats.CurrentAccuracy = currentAcc
                    stats.CurrentWood = tostring(ctx.lathe:GetActiveWoodId() or "Unknown")

                    if settings.AutoCarve and currentAcc < 100 then
                        performInstant100Carve()
                        currentAcc = 100
                    end

                    if settings.AutoCarveNext and currentAcc >= 100 then
                        if now - lastNextClick >= settings.NextDelay then
                            lastNextClick = now
                            clickCarveNext()
                        end
                    end
                end
            else
                stats.Status = "Walking / Idle"
                stats.CurrentAccuracy = 0

                -- Auto enter lathe if enabled and prompt is near
                if settings.AutoEnterLathe and now - lastEnterPrompt >= 1.0 then
                    lastEnterPrompt = now
                    local tycoon = getMyTycoon()
                    local lathePrompt = tycoon and tycoon:FindFirstChild("WoodLathePrompt", true)
                    if lathePrompt and lathePrompt.Enabled and fireproximityprompt then
                        local char = localPlayer.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local part = lathePrompt.Parent
                        if root and part and part:IsA("BasePart") then
                            local dist = (root.Position - part.Position).Magnitude
                            if dist <= (lathePrompt.MaxActivationDistance or 15) + 2 then
                                fireproximityprompt(lathePrompt)
                            end
                        end
                    end
                end

                -- Auto deposit carved wood if enabled
                if settings.AutoDepositCarved and now - lastDepositPrompt >= 3.0 then
                    lastDepositPrompt = now
                    local tycoon = getMyTycoon()
                    local depPrompt = tycoon and tycoon:FindFirstChild("DepositAllCarvedWoodPrompt", true)
                    if depPrompt and depPrompt.Enabled and fireproximityprompt then
                        local char = localPlayer.Character
                        local root = char and char:FindFirstChild("HumanoidRootPart")
                        local part = depPrompt.Parent
                        if root and part and part:IsA("BasePart") then
                            local dist = (root.Position - part.Position).Magnitude
                            if dist <= (depPrompt.MaxActivationDistance or 15) + 2 then
                                fireproximityprompt(depPrompt)
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
        Version = "v1.0.0",
        Settings = settings,
        Stats = stats,
        PerformInstant100Carve = performInstant100Carve,
        ClickCarveNext = clickCarveNext,
        GetLatheContext = getLatheContext,
        Destroy = destroy,
    }

    if runtimeInfo and type(runtimeInfo.registerCleanup) == "function" then
        runtimeInfo.registerCleanup(destroy)
    end
end
