-- ═════════════════════════════════════════════════════════════════
-- Guess the Anime Color 🎨 | RAVEN HUB Module v1.0.0
-- PlaceId: 97506470800237 | UniverseId: 10667006841
-- Features:
--   • 100% Perfect Auto Answer (Accurate Character Color Lookup)
--   • Humanized Auto Guess (Configurable Delay & Accuracy % Variation)
--   • Instant Manual Answer Button (Sets ColorPicker to exact color)
--   • Auto Collect Coins (Instant Touch & Magnet Loop across map)
--   • Auto Claim All Rewards (Daily, Playtime, Group, Soccer Minigame)
--   • Auto Queue / Duel vs AI Farm (Fast Win & Cash Loop)
--   • Answer HUD / Character Color Preview
-- ═════════════════════════════════════════════════════════════════

return function(Window, scriptInfo)
    local Players           = game:GetService("Players")
    local Workspace         = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService        = game:GetService("RunService")

    local LocalPlayer = Players.LocalPlayer
    local GTCFolder   = ReplicatedStorage:WaitForChild("GuessTheColor", 10)
    local GTCRemotes  = ReplicatedStorage:WaitForChild("GTC_Remotes", 10)

    local CharMod     = GTCFolder and GTCFolder:FindFirstChild("Characters")
    local Characters  = CharMod and require(CharMod) or {}

    -- Build Fast Lookup Dictionary: character name (lowercase) -> data
    local CharLookup = {}
    for _, c in pairs(Characters) do
        if type(c) == "table" and c.name and c.color then
            CharLookup[string.lower(string.gsub(c.name, "%s+", ""))] = c
            CharLookup[string.lower(c.name)] = c
        end
    end

    local function findCharacterData(rawName)
        if not rawName or rawName == "" then return nil end
        local clean = string.lower(string.gsub(rawName, "%s+", ""))
        if CharLookup[clean] then return CharLookup[clean] end
        local lower = string.lower(rawName)
        if CharLookup[lower] then return CharLookup[lower] end
        for k, v in pairs(CharLookup) do
            if string.find(clean, k, 1, true) or string.find(k, clean, 1, true) then
                return v
            end
        end
        return nil
    end

    -- Cleanup Previous Instances
    local env = (type(getgenv) == "function" and getgenv()) or _G
    if type(env.__RAVEN_GTC_CLEANUP) == "function" then
        pcall(env.__RAVEN_GTC_CLEANUP)
    end

    local running = true
    local threads = {}
    local connections = {}

    local function startThread(key, fn)
        threads[key] = nil
        task.spawn(function()
            threads[key] = true
            fn(function() return threads[key] == true and running end)
            threads[key] = nil
        end)
    end

    local function stopThread(key)
        threads[key] = nil
    end

    -- ═══════════ Settings ═══════════
    local settings = {
        -- Auto Answer
        autoAnswer       = true,
        answerMode       = "100% Perfect", -- "100% Perfect", "Humanized (95-98%)", "Slight Drift (90-95%)"
        submitDelayMin   = 1.0,
        submitDelayMax   = 2.5,
        
        -- Auto Farm
        autoFarmAI       = false,
        autoCoins        = false,
        autoClaimRewards = true,
        
        -- Visuals
        showAnswerHud    = true,
    }

    -- ═══════════ Helper: Find trySubmit closure ═══════════
    local function getTrySubmitFn()
        if not getgc then return nil end
        for _, obj in ipairs(getgc(true)) do
            if typeof(obj) == "function" and islclosure(obj) then
                local info = debug.getinfo(obj)
                if info.name == "trySubmit" and info.source and string.find(info.source, "GTC_ColorPicker") then
                    return obj
                end
            end
        end
        return nil
    end

    -- ═══════════ Helper: Submit Color ═══════════
    local function submitExactColor(targetColor)
        local fn = getTrySubmitFn()
        if not fn or not debug.setupvalue then
            -- Fallback direct remote fire
            if GTCRemotes and GTCRemotes:FindFirstChild("SubmitGuess") then
                pcall(function()
                    GTCRemotes.SubmitGuess:FireServer(1, targetColor)
                end)
            end
            return false
        end

        local curColor = targetColor
        if settings.answerMode == "Humanized (95-98%)" then
            local drift = (math.random(-2, 2) / 100)
            curColor = Color3.new(
                math.clamp(targetColor.R + drift, 0, 1),
                math.clamp(targetColor.G + drift, 0, 1),
                math.clamp(targetColor.B + drift, 0, 1)
            )
        elseif settings.answerMode == "Slight Drift (90-95%)" then
            local drift = (math.random(-5, 5) / 100)
            curColor = Color3.new(
                math.clamp(targetColor.R + drift, 0, 1),
                math.clamp(targetColor.G + drift, 0, 1),
                math.clamp(targetColor.B + drift, 0, 1)
            )
        end

        pcall(function()
            debug.setupvalue(fn, 4, curColor)
            fn()
        end)
        return true
    end

    -- ═══════════ Auto Answer Engine ═══════════
    local lastSolvedChar = ""
    local isSubmitting = false

    local function runAutoSolverCheck()
        if not settings.autoAnswer or isSubmitting then return end
        
        local pGui = LocalPlayer:FindFirstChild("PlayerGui")
        local picker = pGui and pGui:FindFirstChild("GTC_Picker")
        if not picker or not picker.Enabled then
            lastSolvedChar = ""
            return
        end

        local frame = picker:FindFirstChild("Frame")
        local charNameLabel = frame and frame:FindFirstChild("CharacterName")
        if not charNameLabel or not charNameLabel.Visible or charNameLabel.Text == "" then
            return
        end

        local charText = charNameLabel.Text
        if charText == lastSolvedChar then return end

        local charData = findCharacterData(charText)
        if not charData or not charData.color then return end

        lastSolvedChar = charText
        isSubmitting = true

        task.spawn(function()
            local delayTime = math.random(
                math.floor(settings.submitDelayMin * 10),
                math.floor(settings.submitDelayMax * 10)
            ) / 10
            
            task.wait(delayTime)

            if running and settings.autoAnswer and picker.Enabled and charNameLabel.Text == charText then
                submitExactColor(charData.color)
            end
            isSubmitting = false
        end)
    end

    -- Loop check for round
    startThread("autoAnswerLoop", function(isAlive)
        while isAlive() do
            pcall(runAutoSolverCheck)
            task.wait(0.3)
        end
    end)

    -- Also hook remote for instant response
    if GTCRemotes and GTCRemotes:FindFirstChild("RoundStart") then
        local con = GTCRemotes.RoundStart.OnClientEvent:Connect(function()
            task.wait(0.2)
            runAutoSolverCheck()
        end)
        table.insert(connections, con)
    end

    -- ═══════════ Auto Collect Coins ═══════════
    startThread("autoCoinsLoop", function(isAlive)
        while isAlive() do
            if settings.autoCoins and firetouchinterest then
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                local coins = Workspace:FindFirstChild("Coins")
                if hrp and coins then
                    for _, coin in ipairs(coins:GetChildren()) do
                        if coin:IsA("BasePart") then
                            pcall(function()
                                firetouchinterest(hrp, coin, 0)
                                firetouchinterest(hrp, coin, 1)
                            end)
                        end
                    end
                end
            end
            task.wait(1.5)
        end
    end)

    -- ═══════════ Auto Claim All Rewards ═══════════
    startThread("autoClaimRewardsLoop", function(isAlive)
        while isAlive() do
            if settings.autoClaimRewards and GTCRemotes then
                -- Daily Reward
                pcall(function()
                    if GTCRemotes:FindFirstChild("DailyRewardClaim") then
                        for day = 1, 7 do
                            GTCRemotes.DailyRewardClaim:InvokeServer(day)
                        end
                    end
                end)

                -- Playtime Reward
                pcall(function()
                    if GTCRemotes:FindFirstChild("PlaytimeRewardClaim") then
                        local milestones = {5, 15, 30, 60, 120, 240, 480, 960}
                        for _, m in ipairs(milestones) do
                            GTCRemotes.PlaytimeRewardClaim:InvokeServer(m)
                        end
                    end
                end)

                -- Group Reward
                pcall(function()
                    if GTCRemotes:FindFirstChild("GroupRewardClaim") then
                        GTCRemotes.GroupRewardClaim:InvokeServer()
                    end
                end)

                -- Soccer Minigame Claim
                pcall(function()
                    if GTCRemotes:FindFirstChild("SoccerClaim") then
                        GTCRemotes.SoccerClaim:FireServer()
                    end
                end)
            end
            task.wait(30)
        end
    end)

    -- ═══════════ Auto Farm AI Duels ═══════════
    startThread("autoAIFarmLoop", function(isAlive)
        while isAlive() do
            if settings.autoFarmAI and GTCRemotes and GTCRemotes:FindFirstChild("PlayAI") then
                local pGui = LocalPlayer:FindFirstChild("PlayerGui")
                local picker = pGui and pGui:FindFirstChild("GTC_Picker")
                local isPlaying = picker and picker.Enabled

                if not isPlaying then
                    -- Trigger AI Duel
                    pcall(function()
                        GTCRemotes.PlayAI:FireServer()
                    end)
                end
            end
            task.wait(3)
        end
    end)

    -- ═══════════ Drawing Answer HUD ═══════════
    local hudBox = nil
    local hudText = nil
    local hudColorDot = nil

    if Drawing and Drawing.new then
        pcall(function()
            hudBox = Drawing.new("Square")
            hudBox.Visible = false
            hudBox.Filled = true
            hudBox.Color = Color3.fromRGB(24, 24, 28)
            hudBox.Transparency = 0.9
            hudBox.Size = Vector2.new(220, 50)
            hudBox.Position = Vector2.new(20, 120)

            hudColorDot = Drawing.new("Square")
            hudColorDot.Visible = false
            hudColorDot.Filled = true
            hudColorDot.Size = Vector2.new(34, 34)
            hudColorDot.Position = Vector2.new(28, 128)

            hudText = Drawing.new("Text")
            hudText.Visible = false
            hudText.Size = 14
            hudText.Font = 2
            hudText.Color = Color3.fromRGB(255, 255, 255)
            hudText.Outline = true
            hudText.Position = Vector2.new(70, 130)
        end)
    end

    local renderCon = RunService.RenderStepped:Connect(function()
        if not hudBox or not hudText or not hudColorDot then return end
        
        local pGui = LocalPlayer:FindFirstChild("PlayerGui")
        local picker = pGui and pGui:FindFirstChild("GTC_Picker")
        local isPickerOpen = picker and picker.Enabled
        local charNameLabel = isPickerOpen and picker.Frame and picker.Frame:FindFirstChild("CharacterName")

        if settings.showAnswerHud and isPickerOpen and charNameLabel and charNameLabel.Visible and charNameLabel.Text ~= "" then
            local charData = findCharacterData(charNameLabel.Text)
            if charData and charData.color then
                hudBox.Visible = true
                hudColorDot.Visible = true
                hudColorDot.Color = charData.color
                hudText.Visible = true
                hudText.Text = string.format("%s\nHex: #%s", charData.name or charNameLabel.Text, charData.color:ToHex():upper())
                return
            end
        end

        hudBox.Visible = false
        hudColorDot.Visible = false
        hudText.Visible = false
    end)
    table.insert(connections, renderCon)

    -- ═══════════ Unified Window Adapter ═══════════
    local function createTab(name, icon)
        if Window.CreateTab then
            return Window:CreateTab(name, icon or "layers")
        elseif Window.AddTab then
            return Window:AddTab(name, icon)
        end
        error("Unsupported Window Tab method")
    end

    local function createSection(tab, title)
        if tab.CreateSection then
            return tab:CreateSection(title)
        elseif tab.AddSection then
            return tab:AddSection(title)
        end
        return tab
    end

    local function addToggle(secOrTab, name, default, cb)
        if secOrTab.CreateToggle then
            return secOrTab:CreateToggle({
                Name = name,
                CurrentValue = default,
                Callback = cb
            })
        elseif secOrTab.AddToggle then
            return secOrTab:AddToggle(name, default, cb)
        end
    end

    local function addDropdown(secOrTab, name, options, default, cb)
        if secOrTab.CreateDropdown then
            return secOrTab:CreateDropdown({
                Name = name,
                Options = options,
                CurrentOption = default,
                Callback = function(v)
                    local res = type(v) == "table" and (v[1] or v.Value) or v
                    cb(res)
                end
            })
        elseif secOrTab.AddDropdown then
            return secOrTab:AddDropdown(name, options, default, cb)
        end
    end

    local function addSlider(secOrTab, name, min, max, default, cb)
        if secOrTab.CreateSlider then
            return secOrTab:CreateSlider({
                Name = name,
                Range = {min, max},
                Increment = 0.5,
                CurrentValue = default,
                Callback = cb
            })
        elseif secOrTab.AddSlider then
            return secOrTab:AddSlider(name, min, max, default, cb)
        end
    end

    local function addButton(secOrTab, name, cb)
        if secOrTab.CreateButton then
            return secOrTab:CreateButton({
                Name = name,
                Callback = cb
            })
        elseif secOrTab.AddButton then
            return secOrTab:AddButton(name, cb)
        end
    end

    -- ═══════════ Window Tabs & Controls ═══════════
    local SolverTab   = createTab("Solver", "cpu")
    local FarmTab     = createTab("Auto Farm", "coins")
    local SettingsTab = createTab("Settings", "settings")

    -- Tab: Solver
    local solverSec = createSection(SolverTab, "Auto Answer Engine")
    addToggle(solverSec, "Auto Answer", settings.autoAnswer, function(v)
        settings.autoAnswer = v
    end)

    addDropdown(solverSec, "Answer Accuracy", {"100% Perfect", "Humanized (95-98%)", "Slight Drift (90-95%)"}, settings.answerMode, function(v)
        settings.answerMode = v
    end)

    addSlider(solverSec, "Submit Delay Min (s)", 0, 5, settings.submitDelayMin, function(v)
        settings.submitDelayMin = v
    end)

    addSlider(solverSec, "Submit Delay Max (s)", 0.5, 8, settings.submitDelayMax, function(v)
        settings.submitDelayMax = v
    end)

    addButton(solverSec, "Instant Solve Current Round", function()
        local pGui = LocalPlayer:FindFirstChild("PlayerGui")
        local picker = pGui and pGui:FindFirstChild("GTC_Picker")
        local charNameLabel = picker and picker.Frame and picker.Frame:FindFirstChild("CharacterName")
        if charNameLabel and charNameLabel.Text ~= "" then
            local charData = findCharacterData(charNameLabel.Text)
            if charData and charData.color then
                submitExactColor(charData.color)
            end
        end
    end)

    -- Tab: Auto Farm
    local farmSec = createSection(FarmTab, "Automation & Rewards")
    addToggle(farmSec, "Auto Farm vs AI (Fast Wins/Streak)", settings.autoFarmAI, function(v)
        settings.autoFarmAI = v
    end)

    addToggle(farmSec, "Auto Collect All Coins (Map Magnet)", settings.autoCoins, function(v)
        settings.autoCoins = v
    end)

    addToggle(farmSec, "Auto Claim All Rewards (Daily/Playtime/Soccer)", settings.autoClaimRewards, function(v)
        settings.autoClaimRewards = v
    end)

    addButton(farmSec, "Claim All Rewards Now", function()
        pcall(function()
            if GTCRemotes:FindFirstChild("DailyRewardClaim") then
                for day = 1, 7 do GTCRemotes.DailyRewardClaim:InvokeServer(day) end
            end
            if GTCRemotes:FindFirstChild("PlaytimeRewardClaim") then
                for _, m in ipairs({5, 15, 30, 60, 120, 240, 480, 960}) do
                    GTCRemotes.PlaytimeRewardClaim:InvokeServer(m)
                end
            end
            if GTCRemotes:FindFirstChild("GroupRewardClaim") then
                GTCRemotes.GroupRewardClaim:InvokeServer()
            end
            if GTCRemotes:FindFirstChild("SoccerClaim") then
                GTCRemotes.SoccerClaim:FireServer()
            end
        end)
    end)

    -- Tab: Settings / Visuals
    local visSec = createSection(SettingsTab, "Visuals & HUD")
    addToggle(visSec, "Show Answer Color HUD", settings.showAnswerHud, function(v)
        settings.showAnswerHud = v
    end)

    if Window.SortTabs then
        pcall(function() Window:SortTabs({"Overview", "Solver", "Auto Farm", "Settings"}) end)
    end

    -- Cleanup Routine
    env.__RAVEN_GTC_CLEANUP = function()
        running = false
        for k in pairs(threads) do
            threads[k] = nil
        end
        for _, c in ipairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        if hudBox and hudBox.Remove then pcall(function() hudBox:Remove() end) end
        if hudText and hudText.Remove then pcall(function() hudText:Remove() end) end
        if hudColorDot and hudColorDot.Remove then pcall(function() hudColorDot:Remove() end) end
    end
end
