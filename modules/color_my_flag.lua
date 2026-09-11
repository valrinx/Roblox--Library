-- ═════════════════════════════════════════════════════════════════
-- Color My Flag 🎨 | RAVEN HUB Module v1.0.0
-- PlaceId: 132173349090360 | GameId: 10630800860
-- Features: 100% Accuracy Auto Solver | Auto Reveal | Auto Submit | Auto Play AI | Auto Rematch | Auto Sit Table
-- ═════════════════════════════════════════════════════════════════

return function(Window, scriptInfo)
    local Players           = game:GetService("Players")
    local Workspace         = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService        = game:GetService("RunService")

    local LocalPlayer = Players.LocalPlayer
    local Remotes     = ReplicatedStorage:WaitForChild("Shared", 15):WaitForChild("Remotes", 15)

    local environment = getgenv and getgenv() or _G
    if type(environment.__RAVEN_COLOR_MY_FLAG) == "table"
        and type(environment.__RAVEN_COLOR_MY_FLAG.Destroy) == "function" then
        pcall(environment.__RAVEN_COLOR_MY_FLAG.Destroy)
    end

    local running = true
    local threads = {}
    local connections = {}

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

    -- ═══════════ Settings ═══════════
    local settings = {
        autoSolve        = false,
        submitDelay      = 0.5,   -- Delay in seconds before auto-submitting
        autoPlayAI       = false, -- Auto click Play AI if waiting for player
        autoRematch      = false, -- Auto accept rematch after game ends
        autoSit          = false, -- Auto sit back at chosen table tier
        tableTier        = "Any", -- "Any", "Standard", "Pro", "Hardcore"
        preventBlackout  = true,  -- Remove Blinded blackout overlay
    }

    local stats = {
        flagsSolved = 0,
        currentFlag = "None",
        accuracy    = 0,
        status      = "Idle",
    }

    -- ═══════════ Safe References ═══════════
    local function getGameController()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local ctrl = ps and ps:FindFirstChild("Controllers") and ps.Controllers:FindFirstChild("GameController")
        if ctrl then
            local ok, mod = pcall(require, ctrl)
            if ok and type(mod) == "table" then return mod end
        end
        return nil
    end

    local function getFlagEditorController()
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local ctrl = ps and ps:FindFirstChild("Controllers") and ps.Controllers:FindFirstChild("FlagEditorController")
        if ctrl then
            local ok, mod = pcall(require, ctrl)
            if ok and type(mod) == "table" then return mod end
        end
        return nil
    end

    local function getCharacter()
        return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    end

    local function getHRP()
        local char = getCharacter()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function isSeated()
        local char = getCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart ~= nil and hum:GetState() == Enum.HumanoidStateType.Seated
    end

    local function getCurrentSeat()
        local char = getCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        return hum and hum.SeatPart
    end

    local function getTopFlagText()
        local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
        local top = sg and sg:FindFirstChild("Top")
        local flagLabel = top and top:FindFirstChild("Flag")
        if flagLabel and flagLabel.Visible and flagLabel.Text ~= "" then
            return flagLabel.Text
        end
        return nil
    end

    local function getMatchTimerText()
        local sg = LocalPlayer.PlayerGui:FindFirstChild("ScreenGui")
        local top = sg and sg:FindFirstChild("Top")
        local timer = top and top:FindFirstChild("Timer")
        if timer and timer.Visible then
            return timer.Text
        end
        return nil
    end

    local function isMatchActive()
        local fe = getFlagEditorController()
        if fe and fe.IsRunning and fe.IsRunning() then
            return true
        end
        local flag = getTopFlagText()
        local timer = getMatchTimerText()
        return flag ~= nil and timer ~= nil
    end

    -- ═══════════ Auto Solver Engine ═══════════
    local function solveFlag100()
        local fe = getFlagEditorController()
        if not fe then return false, "FlagEditorController unavailable" end

        if not fe.IsRunning() then
            return false, "Flag Editor is not running"
        end

        local ok, err = pcall(function()
            fe.RevealAll()
        end)
        if not ok then return false, err end

        task.wait(0.15)

        local acc = 100
        if fe.ComputeLocalAccuracy then
            pcall(function()
                acc = fe.ComputeLocalAccuracy()
            end)
        end
        stats.accuracy = acc
        return true, acc
    end

    local function submitFlag()
        local fe = getFlagEditorController()
        if not fe then return false end

        local encodedColors = fe.GetEncodedColors and fe.GetEncodedColors()
        local gameAction = Remotes and Remotes:FindFirstChild("GameAction")
        if not gameAction or not encodedColors then return false end

        -- Safe legitimate Remote call matching client GameController
        gameAction:FireServer({
            Action = "SubmitColors",
            Colors = encodedColors
        })
        return true
    end

    -- ═══════════ Table Seating Engine ═══════════
    local function findAvailableSeat(tier)
        local stands = Workspace:FindFirstChild("Stands")
        if not stands then return nil end

        for _, stand in ipairs(stands:GetChildren()) do
            local standName = stand.Name
            local matchesTier = (tier == "Any") 
                or (tier == "Standard" and standName == "Stand")
                or (tier == "Pro" and standName == "Pro")
                or (tier == "Hardcore" and standName == "Hardcore")

            if matchesTier then
                local func = stand:FindFirstChild("Functional")
                if func then
                    -- Stand has RedChair and BlueChair
                    for _, chairName in ipairs({"BlueChair", "RedChair"}) do
                        local chair = func:FindFirstChild(chairName)
                        local basic = chair and chair:FindFirstChildWhichIsA("Model") or chair
                        local seat = basic and basic:FindFirstChildWhichIsA("Seat")
                        if seat and seat.Occupant == nil then
                            return seat, standName
                        end
                    end
                end
            end
        end
        return nil
    end

    local function sitAtSeat(seat)
        if not seat then return false end
        local hrp = getHRP()
        local char = getCharacter()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then return false end

        -- Teleport directly onto the seat
        hrp.CFrame = seat.CFrame + Vector3.new(0, 1.5, 0)
        task.wait(0.1)
        seat:Sit(hum)
        return true
    end

    -- ═══════════ Protection / Anti-Blind ═══════════
    local function clearBlackout()
        if not settings.preventBlackout then return end
        local gameUI = LocalPlayer.PlayerGui:FindFirstChild("GameUI")
        local blinded = gameUI and gameUI:FindFirstChild("Blinded")
        if blinded and blinded.Visible then
            blinded.Visible = false
            local block = blinded:FindFirstChild("Block")
            if block then block.Visible = false end
        end
    end

    -- ═════════════════════════════════════════════════════════════════
    --   GUI CREATION
    -- ═════════════════════════════════════════════════════════════════

    local SolverTab = Window:CreateTab("Auto Solver", 10734950309)

    SolverTab:CreateSection("🏆 Auto Solver Controls (100% Accuracy)")

    SolverTab:CreateToggle({
        Name = "⚡ Auto Solve & Submit (Loop)",
        CurrentValue = false,
        Flag = "CMF_AutoSolve",
        Callback = function(val)
            settings.autoSolve = val
            if val then
                startThread("AutoSolveLoop", function(isAlive)
                    local lastSolvedFlag = ""
                    while isAlive() do
                        clearBlackout()

                        if isMatchActive() then
                            local currentFlag = getTopFlagText() or "Unknown"
                            stats.currentFlag = currentFlag
                            stats.status = "In Match (" .. currentFlag .. ")"

                            if lastSolvedFlag ~= currentFlag then
                                -- Instant 100% color reveal
                                local ok, acc = solveFlag100()
                                if ok then
                                    stats.status = string.format("Solved 100%% (%s)", currentFlag)
                                    task.wait(math.max(0.1, settings.submitDelay))
                                    submitFlag()
                                    stats.flagsSolved = stats.flagsSolved + 1
                                    lastSolvedFlag = currentFlag
                                    stats.status = string.format("Submitted (%s)", currentFlag)
                                end
                            end
                        else
                            stats.status = isSeated() and "Waiting for Match" or "Not Seated"
                            lastSolvedFlag = ""
                        end

                        task.wait(0.3)
                    end
                end)
            else
                stopThread("AutoSolveLoop")
            end
        end,
    })

    SolverTab:CreateSlider({
        Name = "Submit Delay (Seconds)",
        Range = {0.1, 5},
        Increment = 0.1,
        CurrentValue = 0.5,
        Flag = "CMF_SubmitDelay",
        Callback = function(val)
            settings.submitDelay = val
        end,
    })

    SolverTab:CreateButton({
        Name = "🎯 Solve Current Flag (Once - 100% Acc)",
        Callback = function()
            clearBlackout()
            local ok, acc = solveFlag100()
            if ok then
                stats.flagsSolved = stats.flagsSolved + 1
            end
        end,
    })

    SolverTab:CreateButton({
        Name = "📤 Submit Colors (Once)",
        Callback = function()
            submitFlag()
        end,
    })

    SolverTab:CreateSection("🤖 Match QoL & Automation")

    SolverTab:CreateToggle({
        Name = "Auto Play AI (Instant Solo Match)",
        CurrentValue = false,
        Flag = "CMF_AutoPlayAI",
        Callback = function(val)
            settings.autoPlayAI = val
            if val then
                startThread("AutoPlayAILoop", function(isAlive)
                    while isAlive() do
                        if isSeated() and not isMatchActive() then
                            local gameUI = LocalPlayer.PlayerGui:FindFirstChild("GameUI")
                            local pd = gameUI and gameUI:FindFirstChild("PlayDown")
                            local playAI = pd and pd:FindFirstChild("Hold") and pd.Hold:FindFirstChild("PlayAI")
                            local clickBtn = playAI and playAI:FindFirstChild("Click")
                            if playAI and playAI.Visible and clickBtn then
                                if firesignal then
                                    firesignal(clickBtn.MouseButton1Click)
                                else
                                    clickBtn:Click()
                                end
                                task.wait(1.5)
                            end
                        end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("AutoPlayAILoop")
            end
        end,
    })

    SolverTab:CreateToggle({
        Name = "Auto Rematch (Accept Rematches)",
        CurrentValue = false,
        Flag = "CMF_AutoRematch",
        Callback = function(val)
            settings.autoRematch = val
            if val then
                startThread("AutoRematchLoop", function(isAlive)
                    while isAlive() do
                        local gameUI = LocalPlayer.PlayerGui:FindFirstChild("GameUI")
                        local top = gameUI and gameUI:FindFirstChild("Top")
                        local rematch = top and top:FindFirstChild("Rematch")
                        if rematch and rematch.Visible then
                            local yesBtn = rematch:FindFirstChild("HoldButtons") and rematch.HoldButtons:FindFirstChild("Yes") and rematch.HoldButtons.Yes:FindFirstChild("Click")
                            if yesBtn then
                                if firesignal then
                                    firesignal(yesBtn.MouseButton1Click)
                                else
                                    yesBtn:Click()
                                end
                                task.wait(1)
                            end
                        end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("AutoRematchLoop")
            end
        end,
    })

    SolverTab:CreateToggle({
        Name = "Anti-Blind (Remove Blackout / Flash)",
        CurrentValue = true,
        Flag = "CMF_PreventBlackout",
        Callback = function(val)
            settings.preventBlackout = val
            if val then clearBlackout() end
        end,
    })

    SolverTab:CreateSection("🪑 Table Seating Engine")

    SolverTab:CreateDropdown({
        Name = "Table Tier Target",
        Options = {"Any", "Standard", "Pro", "Hardcore"},
        CurrentOption = "Any",
        MultipleOptions = false,
        Flag = "CMF_TableTier",
        Callback = function(opt)
            settings.tableTier = opt
        end,
    })

    SolverTab:CreateToggle({
        Name = "Auto Sit Available Table",
        CurrentValue = false,
        Flag = "CMF_AutoSit",
        Callback = function(val)
            settings.autoSit = val
            if val then
                startThread("AutoSitLoop", function(isAlive)
                    while isAlive() do
                        if not isSeated() then
                            local seat, tierName = findAvailableSeat(settings.tableTier)
                            if seat then
                                sitAtSeat(seat)
                                task.wait(1)
                            end
                        end
                        task.wait(1)
                    end
                end)
            else
                stopThread("AutoSitLoop")
            end
        end,
    })

    SolverTab:CreateButton({
        Name = "🪑 Sit Available Table (Once)",
        Callback = function()
            local seat, tierName = findAvailableSeat(settings.tableTier)
            if seat then
                sitAtSeat(seat)
            end
        end,
    })

    -- ═══════════ Status Tracker Tab ═══════════
    SolverTab:CreateSection("📊 Live Match Stats")
    local StatusLabel = SolverTab:CreateLabel("Status: " .. stats.status)
    local FlagLabel   = SolverTab:CreateLabel("Target Flag: " .. stats.currentFlag)
    local AccLabel    = SolverTab:CreateLabel("Last Accuracy: 100%")
    local SolvedLabel = SolverTab:CreateLabel("Flags Solved: 0")

    startThread("StatsTracker", function(isAlive)
        while isAlive() do
            pcall(function()
                if StatusLabel and StatusLabel.Set then
                    StatusLabel:Set("Status: " .. stats.status)
                end
                if FlagLabel and FlagLabel.Set then
                    FlagLabel:Set("Target Flag: " .. (getTopFlagText() or stats.currentFlag or "None"))
                end
                if AccLabel and AccLabel.Set then
                    AccLabel:Set("Last Accuracy: " .. tostring(stats.accuracy) .. "%")
                end
                if SolvedLabel and SolvedLabel.Set then
                    SolvedLabel:Set("Flags Solved: " .. tostring(stats.flagsSolved))
                end
            end)
            task.wait(0.5)
        end
    end)

    -- ═══════════ Cleanup / Destroy Handler ═══════════
    environment.__RAVEN_COLOR_MY_FLAG = {
        Destroy = function()
            running = false
            for k, _ in pairs(threads) do
                threads[k] = nil
            end
            for _, c in ipairs(connections) do
                pcall(function() c:Disconnect() end)
            end
            table.clear(connections)
        end
    }
end
