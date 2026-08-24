-- RAVEN HUB | Train Your Fish to Race v1.2.0
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local VirtualUser = game:GetService("VirtualUser")

    local player = Players.LocalPlayer
    local env = getgenv()
    if type(env.__RAVEN_TRAIN_YOUR_FISH) == "table" and type(env.__RAVEN_TRAIN_YOUR_FISH.Destroy) == "function" then
        pcall(env.__RAVEN_TRAIN_YOUR_FISH.Destroy)
    end

    local running = true
    local connections = {}
    local settings = { smartLoop = false, antiAfk = true, autoOnlineReward = false, autoDailySign = false, autoSpin = false, autoRaceReward = false }

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local eventFolder = remotes and remotes:FindFirstChild("Event")
    local gameRun = eventFolder and eventFolder:FindFirstChild("GameRun")
    local changeAuto = gameRun and gameRun:FindFirstChild("[C-S]PlayerTryChangeAuto")
    local raceCount = ReplicatedStorage:FindFirstChild("RaceCount")
    local raceFlag = raceCount and raceCount:FindFirstChild("Raceing")
    local raceCounter = raceCount and raceCount:FindFirstChild("Count")
    local functionFolder = remotes and remotes:FindFirstChild("Function")
    local gameRunFunctions = functionFolder and functionFolder:FindFirstChild("GameRun")
    local dailyEvents = eventFolder and eventFolder:FindFirstChild("DailySign")
    local dailyFunctions = functionFolder and functionFolder:FindFirstChild("DailySign")
    local spinEvents = eventFolder and eventFolder:FindFirstChild("Spin")
    local spinFunctions = functionFolder and functionFolder:FindFirstChild("Spin")
    local onlineRewardFunction = gameRunFunctions and gameRunFunctions:FindFirstChild("[C-S]TryGetOnlineReward")
    local dailySignEvent = dailyEvents and dailyEvents:FindFirstChild("[C-S]PlayerTrySign")
    local dailyDataFunction = dailyFunctions and dailyFunctions:FindFirstChild("[C-S]TryGetDailySignData")
    local dailyCanFunction = dailyFunctions and dailyFunctions:FindFirstChild("[C-S]PlayerIsCanSign")
    local freeSpinEvent = spinEvents and spinEvents:FindFirstChild("[C-S]PlayerTryFreeGetDrawNumber")
    local spinLoadFunction = spinFunctions and spinFunctions:FindFirstChild("[C-S]PlayerLoadSpin")
    local spinUseFunction = spinFunctions and spinFunctions:FindFirstChild("[C-S]PlayerTryUserSpin")
    local raceRewardEvent = gameRun and gameRun:FindFirstChild("[C-S]PlayerTryGetRaceReward")
    local showRaceRewardEvent = gameRun and gameRun:FindFirstChild("[S-C]ShowRaceBoxReward")

    local function connect(signal, callback)
        local c = signal:Connect(callback)
        table.insert(connections, c)
        return c
    end

    local function notify(title, text)
        local hub = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if hub and type(hub.Notify) == "function" then
            pcall(function() hub:Notify({Title = title, Content = text, Duration = 5}) end)
        end
    end

    local function roots()
        return {player, player.Character, workspace:FindFirstChild(player.Name), player:FindFirstChildOfClass("PlayerGui")}
    end

    local valueCache = {}
    local function findValue(name, className)
        local key = name .. ":" .. (className or "ValueBase")
        local cached = valueCache[key]
        if cached and cached.Parent and cached:IsA(className or "ValueBase") then return cached end
        valueCache[key] = nil
        for _, root in ipairs(roots()) do
            if root then
                for _, item in ipairs(root:GetDescendants()) do
                    if item.Name == name and item:IsA(className or "ValueBase") then valueCache[key] = item; return item end
                end
            end
        end
        return nil
    end

    local function readBool(name)
        local value = findValue(name, "BoolValue")
        if value then return value.Value == true, value end
        return nil, nil
    end

    local function setNativeAuto(name, desired)
        local current = readBool(name)
        if current == desired then return true end
        if not changeAuto then
            notify("Train Your Fish", "Native auto remote is unavailable")
            return false
        end
        local ok = pcall(function() changeAuto:FireServer(name) end)
        return ok
    end

    local function getRoot()
        local char = player.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid()
        local char = player.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function fmt(value)
        local n = tonumber(value) or 0
        if math.abs(n) >= 1e9 then return string.format("%.2fB", n / 1e9) end
        if math.abs(n) >= 1e6 then return string.format("%.2fM", n / 1e6) end
        if math.abs(n) >= 1e3 then return string.format("%.2fK", n / 1e3) end
        return string.format("%.0f", n)
    end

    local rewardCooldown = {}
    local function rewardReady(key, delay)
        local now = os.clock()
        if (rewardCooldown[key] or 0) > now then return false end
        rewardCooldown[key] = now + delay
        return true
    end

    local function tryOnlineRewards()
        if not onlineRewardFunction or not rewardReady("online", 2) then return end
        local gui = player:FindFirstChildOfClass("PlayerGui")
        local main = gui and gui:FindFirstChild("Main")
        local rewardGui = main and main:FindFirstChild("OnlineReward")
        local holder = rewardGui and rewardGui:FindFirstChild("Holder")
        if not holder then return end
        for _, button in ipairs(holder:GetChildren()) do
            local timer = button:FindFirstChild("Timer")
            if button:IsA("GuiButton") and timer and timer:IsA("IntValue") and timer.Value == 0 then
                pcall(function() onlineRewardFunction:InvokeServer(button.Name) end)
                task.wait(0.15)
            end
        end
    end

    local function tryDailySign()
        if not dailyCanFunction or not dailyDataFunction or not dailySignEvent or not rewardReady("daily", 10) then return end
        local okCan, canSign = pcall(function() return dailyCanFunction:InvokeServer() end)
        if not okCan or canSign ~= true then return end
        local okData, data = pcall(function() return dailyDataFunction:InvokeServer() end)
        if not okData or type(data) ~= "table" then return end
        local day = math.clamp(#data + 1, 1, 7)
        pcall(function() dailySignEvent:FireServer(tostring(day)) end)
    end

    local function trySpinReward()
        if not spinLoadFunction or not rewardReady("spin", 3) then return end
        local ok, data = pcall(function() return spinLoadFunction:InvokeServer() end)
        if not ok or type(data) ~= "table" then return end
        local timeLeft = tonumber(data.Time)
        if settings.autoSpin and freeSpinEvent and timeLeft and timeLeft <= 0 then pcall(function() freeSpinEvent:FireServer() end) end
        local spin = type(data.Spin) == "table" and data.Spin or nil
        if settings.autoSpin and spinUseFunction and spin and (tonumber(spin.have) or 0) > 0 then pcall(function() spinUseFunction:InvokeServer(1) end) end
    end

    local AutomationTab = Window:CreateTab("Automation", "automation")
    AutomationTab:CreateSection("Native Automation")
    local nativeToggles = {}
    local syncingToggle = {}
    local function syncNativeToggle(name, value)
        local toggle = nativeToggles[name]
        if not toggle or type(toggle.Set) ~= "function" then return end
        syncingToggle[name] = true
        toggle:Set(value == true)
        syncingToggle[name] = nil
    end
    local function requestNativeAuto(name, desired)
        if syncingToggle[name] then return end
        setNativeAuto(name, desired)
        task.delay(0.5, function()
            if not running then return end
            local actual = readBool(name)
            if actual ~= nil then syncNativeToggle(name, actual) end
        end)
    end
    nativeToggles.AutoTrain = AutomationTab:CreateToggle({
        Name = "Native Auto Train",
        CurrentValue = readBool("AutoTrain") == true,
        Flag = "TYFAutoTrain",
        Callback = function(value) requestNativeAuto("AutoTrain", value == true) end,
    })
    nativeToggles.AutoRace = AutomationTab:CreateToggle({
        Name = "Native Auto Race",
        CurrentValue = readBool("AutoRace") == true,
        Flag = "TYFAutoRace",
        Callback = function(value) requestNativeAuto("AutoRace", value == true) end,
    })
    for name, toggle in pairs(nativeToggles) do
        local _, valueObject = readBool(name)
        if valueObject then connect(valueObject.Changed, function(value) if running then syncNativeToggle(name, value) end end) end
    end
    AutomationTab:CreateToggle({
        Name = "Smart Train + Race Loop",
        CurrentValue = false,
        Flag = "TYFSmartLoop",
        Callback = function(value)
            settings.smartLoop = value == true
            if settings.smartLoop then
                local racing = raceFlag and raceFlag.Value == true
                if not racing then setNativeAuto("AutoTrain", true) end
                setNativeAuto("AutoRace", true)
            end
        end,
    })
    AutomationTab:CreateButton({
        Name = "Enable Both Native Autos",
        Callback = function()
            setNativeAuto("AutoTrain", true)
            task.wait(0.15)
            setNativeAuto("AutoRace", true)
        end,
    })
    AutomationTab:CreateButton({
        Name = "Disable Both Native Autos",
        Callback = function()
            setNativeAuto("AutoTrain", false)
            task.wait(0.15)
            setNativeAuto("AutoRace", false)
        end,
    })

    local RewardsTab = Window:CreateTab("Auto Rewards", "gift")
    RewardsTab:CreateSection("Ready Rewards")
    RewardsTab:CreateToggle({Name = "Auto Online Rewards", CurrentValue = false, Flag = "TYFAutoOnlineReward", Callback = function(v) settings.autoOnlineReward = v == true end})
    RewardsTab:CreateToggle({Name = "Auto Daily Sign", CurrentValue = false, Flag = "TYFAutoDailySign", Callback = function(v) settings.autoDailySign = v == true end})
    RewardsTab:CreateToggle({Name = "Auto Spin + Free Spin", CurrentValue = false, Flag = "TYFAutoSpin", Callback = function(v) settings.autoSpin = v == true end})
    RewardsTab:CreateToggle({Name = "Auto Race Reward", CurrentValue = false, Flag = "TYFAutoRaceReward", Callback = function(v) settings.autoRaceReward = v == true end})
    RewardsTab:CreateButton({Name = "Claim Ready Rewards Now", Callback = function() tryOnlineRewards(); tryDailySign(); trySpinReward() end})

    local StatsTab = Window:CreateTab("Race HUD", "overview")
    StatsTab:CreateSection("Live Race")
    local modeLabel = StatsTab:CreateLabel("Mode: loading...")
    local speedLabel = StatsTab:CreateLabel("Speed: 0")
    local raceLabel = StatsTab:CreateLabel("Race: -")
    local autoLabel = StatsTab:CreateLabel("Native Auto: -")
    StatsTab:CreateSection("Progress")
    local progressLabel = StatsTab:CreateLabel("Level: -")
    local mountLabel = StatsTab:CreateLabel("Mount: -")
    local boostLabel = StatsTab:CreateLabel("Power Boost: -")

    local MiscTab = Window:CreateTab("Utility", "misc")
    MiscTab:CreateSection("Quality of Life")
    MiscTab:CreateToggle({
        Name = "Anti AFK",
        CurrentValue = true,
        Flag = "TYFAntiAFK",
        Callback = function(value) settings.antiAfk = value == true end,
    })
    MiscTab:CreateButton({
        Name = "Sync Native Auto States",
        Callback = function()
            local train = readBool("AutoTrain")
            local race = readBool("AutoRace")
            notify("Native Auto", "Train=" .. tostring(train) .. " | Race=" .. tostring(race))
        end,
    })

    connect(player.Idled, function()
        if settings.antiAfk then
            pcall(function()
                VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
                task.wait(0.1)
                VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
            end)
        end
    end)

    task.spawn(function()
        while running do
            if settings.smartLoop then
                local racing = raceFlag and raceFlag.Value == true
                local race = readBool("AutoRace")
                if race == false then setNativeAuto("AutoRace", true) end
                if not racing then
                    local train = readBool("AutoTrain")
                    if train == false then setNativeAuto("AutoTrain", true) end
                end
            end
            task.wait(1.25)
        end
    end)

    if showRaceRewardEvent then
        connect(showRaceRewardEvent.OnClientEvent, function()
            if settings.autoRaceReward and raceRewardEvent and rewardReady("race", 1) then
                task.delay(0.2, function() if running then pcall(function() raceRewardEvent:FireServer("10") end) end end)
            end
        end)
    end

    task.spawn(function()
        while running do
            if settings.autoOnlineReward then tryOnlineRewards() end
            if settings.autoDailySign then tryDailySign() end
            if settings.autoSpin then trySpinReward() end
            task.wait(1)
        end
    end)

    local accumulator = 0
    connect(RunService.Heartbeat, function(dt)
        if not running then return end
        accumulator = accumulator + dt
        if accumulator < 0.25 then return end
        accumulator = 0

        local racing = raceFlag and raceFlag.Value == true
        local training = readBool("Train") == true
        local root = getRoot()
        local humanoid = getHumanoid()
        local speed = root and root.AssemblyLinearVelocity.Magnitude or 0
        local autoTrain = readBool("AutoTrain")
        local autoRace = readBool("AutoRace")
        local raceNum = raceCounter and raceCounter.Value or player:GetAttribute("RaceRound") or 0
        local character = player.Character
        local level = (character and character:GetAttribute("Level")) or player:GetAttribute("Level") or 0
        local evolution = (character and character:GetAttribute("Evolution")) or player:GetAttribute("Evolution") or 0
        local mount = (character and character:GetAttribute("MountsId")) or player:GetAttribute("MountsId") or "None"
        local boostEnd = tonumber(player:GetAttribute("PowerBoost"))
        local boostLeft = boostEnd and math.max(0, boostEnd - os.time()) or 0

        modeLabel:Set("Mode: " .. (racing and "RACING" or (training and "TRAINING" or "IDLE")))
        speedLabel:Set("Speed: " .. fmt(speed) .. " studs/s | WalkSpeed " .. fmt(humanoid and humanoid.WalkSpeed or 0))
        raceLabel:Set("Race Count/Round: " .. tostring(raceNum))
        autoLabel:Set("Native Auto: Train " .. tostring(autoTrain) .. " | Race " .. tostring(autoRace))
        progressLabel:Set("Level: " .. tostring(level) .. " | Evolution: " .. tostring(evolution))
        mountLabel:Set("Mount: " .. tostring(mount))
        boostLabel:Set("Power Boost: " .. (boostLeft > 0 and (tostring(math.floor(boostLeft)) .. "s") or "inactive"))
    end)

    local function destroyScript()
        if not running then return end
        running = false
        settings.smartLoop = false
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        table.clear(connections)
    end

    env.__RAVEN_TRAIN_YOUR_FISH = {Destroy = destroyScript}
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end
    notify("Train Your Fish v1.2.0", "Native automation and Auto Rewards loaded")
end
