--[[
    RAVEN HUB | Gym Star Simulator
    PlaceId: 70906625936847 | GameId: 6443367640
    Version: v1.0.0

    Auto Training | Auto Competition | Auto Eggs | Auto Rewards | ESP | Teleport
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local VirtualUser = game:GetService("VirtualUser")
    local CoreGui = game:GetService("CoreGui")
    local TeleportService = game:GetService("TeleportService")

    local player = Players.LocalPlayer
    local environment = getgenv()

    -- Cleanup previous instance
    if type(environment.__RAVEN_GYM_SIM) == "table"
        and type(environment.__RAVEN_GYM_SIM.Destroy) == "function" then
        pcall(environment.__RAVEN_GYM_SIM.Destroy)
    end

    local running = true
    local connections = {}

    -- ============================================================
    --  REMOTE REFERENCES
    -- ============================================================
    local MsgFolder = ReplicatedStorage:WaitForChild("Msg", 5)
    local ServerMsgFolder = ReplicatedStorage:WaitForChild("ServerMsg", 5)

    -- Training remotes
    local ClickRemote = MsgFolder and MsgFolder:FindFirstChild("Click")
    local CompititionClick = MsgFolder and MsgFolder:FindFirstChild("CompititionClick")
    local PerformanceRemote = MsgFolder and MsgFolder:FindFirstChild("Performance")

    -- Server remotes
    local SettingRemote = ServerMsgFolder and ServerMsgFolder:FindFirstChild("Setting")

    -- ============================================================
    --  SETTINGS
    -- ============================================================
    local settings = {
        -- Auto Training
        autoTrain = false,
        trainInterval = 0.05,
        trainMode = "Click", -- Click, Competition, Both
        -- Auto Competition
        autoCompetition = false,
        competitionInterval = 0.05,
        -- Auto Eggs
        autoEgg = false,
        -- Auto Rewards
        autoRewards = false,
        autoRewardsInterval = 30,
        -- ESP
        playerEsp = false,
        espMaxDist = 500,
        -- Teleport
        -- Auto Click (built-in)
        autoClickEnabled = false,
        -- Anti AFK
        antiAfk = true,
    }

    -- ============================================================
    --  UTILITIES
    -- ============================================================
    local function formatNumber(n)
        if n >= 1e15 then return string.format("%.1fQ", n / 1e15)
        elseif n >= 1e12 then return string.format("%.1fT", n / 1e12)
        elseif n >= 1e9 then return string.format("%.1fB", n / 1e9)
        elseif n >= 1e6 then return string.format("%.1fM", n / 1e6)
        elseif n >= 1e3 then return string.format("%.1fK", n / 1e3)
        else return tostring(math.floor(n)) end
    end

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 5})
            end)
        end
    end

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getCharacter()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return character, humanoid, root
    end

    local function teleportTo(position)
        local _, _, root = getCharacter()
        if not root then return false end
        if typeof(position) == "CFrame" then
            root.CFrame = position
        else
            root.CFrame = CFrame.new(position)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    local function getFolderValue(folderName, valueName, default)
        local folder = player:FindFirstChild(folderName)
        local value = folder and folder:FindFirstChild(valueName)
        if value and value:IsA("ValueBase") then return value.Value end
        return default
    end

    local function getBagValue(n)
        local bag = player:FindFirstChild("Bag")
        local v = bag and bag:FindFirstChild(tostring(n))
        return v and v:IsA("ValueBase") and v.Value or 0
    end

    local function fireRemote(remote, ...)
        if remote and typeof(remote) == "Instance" then
            if remote:IsA("RemoteEvent") then
                pcall(function() remote:FireServer(...) end)
                return true
            elseif remote:IsA("RemoteFunction") then
                local ok, result = pcall(function() return remote:InvokeServer(...) end)
                return ok and result or nil
            end
        end
        return false
    end

    -- ============================================================
    --  GAME STATE READERS
    -- ============================================================
    local function getEnergy() return getBagValue(1) end
    local function getMuscle() return getBagValue(11) end
    local function getStamina() return getBagValue(12) end
    local function getPower() return getBagValue(13) end
    local function getRank() return getFolderValue("leaderstats", "Rank", 0) end
    local function isCompeting()
        local comp = player:FindFirstChild("竞赛信息")
        return comp and comp:FindFirstChild("是否正在竞赛") and comp["是否正在竞赛"].Value or false
    end

    -- ============================================================
    --  ESP SYSTEM
    -- ============================================================
    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenGymSimESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local espObjects = {}

    local function removeEsp(instance)
        local entry = espObjects[instance]
        if not entry then return end
        if entry.highlight then pcall(function() entry.highlight:Destroy() end) end
        if entry.billboard then pcall(function() entry.billboard:Destroy() end) end
        espObjects[instance] = nil
    end

    local function clearEsp(category)
        for instance, entry in pairs(espObjects) do
            if not category or entry.category == category then
                removeEsp(instance)
            end
        end
    end

    local function addPlayerEsp(plr)
        if espObjects[plr] or plr == player then return end
        local character = plr.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return end

        local color = Color3.fromRGB(100, 200, 255)

        local ok, highlight = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = "RavenPlayerESP"
            h.Adornee = character
            h.FillColor = color
            h.FillTransparency = 0.7
            h.OutlineColor = color
            h.OutlineTransparency = 0.3
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = espFolder
            return h
        end)
        if not ok then return end

        local ok2, billboard = pcall(function()
            local b = Instance.new("BillboardGui")
            b.Name = "RavenPlayerLabel"
            b.Adornee = root
            b.Size = UDim2.fromOffset(200, 40)
            b.StudsOffset = Vector3.new(0, 4, 0)
            b.AlwaysOnTop = true
            b.MaxDistance = settings.espMaxDist
            b.Parent = espFolder
            return b
        end)
        if not ok2 then highlight:Destroy() return end

        local ok3, label = pcall(function()
            local l = Instance.new("TextLabel")
            l.Size = UDim2.fromScale(1, 1)
            l.BackgroundTransparency = 1
            l.Font = Enum.Font.GothamBold
            l.TextSize = 12
            l.TextColor3 = color
            l.TextStrokeTransparency = 0.25
            l.TextWrapped = true
            l.Text = plr.Name
            l.Parent = b
            return l
        end)

        espObjects[plr] = {category = "player", highlight = highlight, billboard = billboard, label = label}
    end

    local function refreshPlayerEsp()
        if not settings.playerEsp then clearEsp("player") return end
        local _, _, root = getCharacter()
        if not root then return end
        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player then
                local char = plr.Character
                local plrRoot = char and char:FindFirstChild("HumanoidRootPart")
                if plrRoot then
                    local dist = (plrRoot.Position - root.Position).Magnitude
                    if dist <= settings.espMaxDist then
                        seen[plr] = true
                        if not espObjects[plr] then addPlayerEsp(plr) end
                    end
                end
            end
        end
        for plr, entry in pairs(espObjects) do
            if entry.category == "player" and not seen[plr] then removeEsp(plr) end
        end
    end

    -- ============================================================
    --  AUTO TRAINING
    -- ============================================================
    local lastTrainTick = 0
    local totalClicks = 0

    local function performTraining()
        if not running or not settings.autoTrain then return end
        local now = os.clock()
        if now - lastTrainTick < settings.trainInterval then return end
        lastTrainTick = now

        -- CompititionClick is the primary training mechanism
        if CompititionClick then
            totalClicks = totalClicks + 1
            pcall(function() CompititionClick:FireServer() end)
        end

        -- Also fire Click for additional training
        if settings.trainMode == "Both" and ClickRemote then
            pcall(function() ClickRemote:FireServer(totalClicks) end)
        end
    end

    -- ============================================================
    --  AUTO COMPETITION
    -- ============================================================
    local lastCompTick = 0

    local function performAutoCompetition()
        if not running or not settings.autoCompetition then return end
        local now = os.clock()
        if now - lastCompTick < settings.competitionInterval then return end
        lastCompTick = now

        if CompititionClick then
            pcall(function() CompititionClick:FireServer() end)
        end
    end

    -- ============================================================
    --  AUTO REWARDS
    -- ============================================================
    local lastRewardsTick = 0

    local function performAutoRewards()
        if not running or not settings.autoRewards then return end
        local now = os.clock()
        if now - lastRewardsTick < settings.autoRewardsInterval then return end
        lastRewardsTick = now

        -- Try to claim online rewards via remote
        local claimRemote = ReplicatedStorage:FindFirstChild("Remotes")
        if claimRemote then
            local tryClaim = claimRemote:FindFirstChild("TryToClaimReward")
            if tryClaim then
                pcall(function() tryClaim:InvokeServer() end)
            end
        end
    end

    -- ============================================================
    --  AUTO CLICK (built-in setting)
    -- ============================================================
    local function setAutoClick(enabled)
        if SettingRemote then
            pcall(function() SettingRemote:InvokeServer("isAutoClick", enabled and 1 or 0) end)
        end
        settings.autoClickEnabled = enabled
    end

    -- ============================================================
    --  UI TABS
    -- ============================================================

    -- Tab 1: Training
    local TrainTab = Window:CreateTab("🏋 Training", "dumbbell")
    TrainTab:CreateSection("Auto Training")
    local trainStatus = TrainTab:CreateLabel("Clicks: 0 | Energy: 0")

    TrainTab:CreateToggle({
        Name = "Auto Train",
        CurrentValue = false,
        Flag = "GymSimAutoTrain",
        Callback = function(v) settings.autoTrain = v end,
    })
    TrainTab:CreateDropdown({
        Name = "Train Mode",
        Options = {"Click", "Competition", "Both"},
        CurrentOption = {"Click"},
        Flag = "GymSimTrainMode",
        Callback = function(v) settings.trainMode = type(v) == "table" and v[1] or v end,
    })
    TrainTab:CreateSlider({
        Name = "Train Interval",
        Range = {0.02, 1},
        Increment = 0.01,
        CurrentValue = 0.05,
        Suffix = " s",
        Flag = "GymSimTrainInterval",
        Callback = function(v) settings.trainInterval = v end,
    })

    TrainTab:CreateSection("Built-in Auto Click")
    TrainTab:CreateToggle({
        Name = "Enable Game Auto Click",
        CurrentValue = false,
        Flag = "GymSimGameAutoClick",
        Callback = function(v) setAutoClick(v) end,
    })

    TrainTab:CreateSection("Auto Competition")
    TrainTab:CreateToggle({
        Name = "Auto Competition Click",
        CurrentValue = false,
        Flag = "GymSimAutoComp",
        Callback = function(v) settings.autoCompetition = v end,
    })
    TrainTab:CreateSlider({
        Name = "Competition Interval",
        Range = {0.02, 1},
        Increment = 0.01,
        CurrentValue = 0.05,
        Suffix = " s",
        Flag = "GymSimCompInterval",
        Callback = function(v) settings.competitionInterval = v end,
    })

    -- Tab 2: Rewards
    local RewardTab = Window:CreateTab("🎁 Rewards", "gift")
    RewardTab:CreateSection("Auto Rewards")
    RewardTab:CreateToggle({
        Name = "Auto Claim Rewards",
        CurrentValue = false,
        Flag = "GymSimAutoRewards",
        Callback = function(v) settings.autoRewards = v end,
    })
    RewardTab:CreateSlider({
        Name = "Reward Check Interval",
        Range = {10, 60},
        Increment = 5,
        CurrentValue = 30,
        Suffix = " s",
        Flag = "GymSimRewardsInterval",
        Callback = function(v) settings.autoRewardsInterval = v end,
    })

    -- Tab 3: ESP
    local EspTab = Window:CreateTab("👁 ESP", "eye")
    EspTab:CreateSection("Player ESP")
    EspTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "GymSimPlayerEsp",
        Callback = function(v) settings.playerEsp = v; if not v then clearEsp("player") end end,
    })
    EspTab:CreateSlider({
        Name = "ESP Max Distance",
        Range = {50, 2000},
        Increment = 50,
        CurrentValue = 500,
        Suffix = " studs",
        Flag = "GymSimEspMaxDist",
        Callback = function(v) settings.espMaxDist = v end,
    })

    -- Tab 4: Teleport
    local TravelTab = Window:CreateTab("🗺 Travel", "map-pin")
    TravelTab:CreateSection("Teleport")

    TravelTab:CreateButton({
        Name = "TP: Spawn",
        Callback = function()
            local spawn = workspace:FindFirstChild("SpawnLocation")
            if spawn then
                teleportTo(spawn.Position + Vector3.new(0, 5, 0))
                notify("Travel", "Teleported to Spawn")
            end
        end,
    })

    -- Tab 5: Utility
    local UtilTab = Window:CreateTab("⚙ Utility", "settings")
    UtilTab:CreateSection("Status")
    local statusLabel = UtilTab:CreateLabel("Loading...")
    local statsLabel = UtilTab:CreateLabel("Loading...")

    UtilTab:CreateSection("Stability")
    UtilTab:CreateToggle({
        Name = "Anti AFK",
        CurrentValue = true,
        Flag = "GymSimAntiAfk",
        Callback = function(v) settings.antiAfk = v end,
    })

    UtilTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            pcall(function()
                TeleportService:Teleport(game.PlaceId, player)
            end)
            notify("Utility", "Rejoining...")
        end,
    })

    -- ============================================================
    --  ANTI AFK
    -- ============================================================
    connect(player.Idled, function()
        if not settings.antiAfk then return end
        pcall(function()
            VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
            task.wait(0.3)
            VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
        end)
    end)

    -- ============================================================
    --  MAIN LOOP
    -- ============================================================
    task.spawn(function()
        local trainAt = 0
        local compAt = 0
        local rewardsAt = 0
        local espAt = 0
        local statusAt = 0

        while running do
            local iterOk, iterErr = xpcall(function()
                local now = os.clock()

                -- Auto Training
                if settings.autoTrain and now - trainAt >= settings.trainInterval then
                    trainAt = now
                    performTraining()
                end

                -- Auto Competition
                if settings.autoCompetition and now - compAt >= settings.competitionInterval then
                    compAt = now
                    performAutoCompetition()
                end

                -- Auto Rewards
                if settings.autoRewards and now - rewardsAt >= settings.autoRewardsInterval then
                    rewardsAt = now
                    performAutoRewards()
                end

                -- ESP Refresh
                if settings.playerEsp and now - espAt >= 1 then
                    espAt = now
                    refreshPlayerEsp()
                end

                -- Status Update
                if now - statusAt >= 0.5 then
                    statusAt = now
                    local energy = getEnergy()
                    local muscle = getMuscle()
                    local stamina = getStamina()
                    local power = getPower()
                    local rank = getRank()

                    pcall(function()
                        trainStatus:Set(string.format(
                            "Clicks: %s | Energy: %s | Mode: %s",
                            formatNumber(totalClicks),
                            formatNumber(energy),
                            settings.trainMode
                        ))
                    end)

                    pcall(function()
                        statusLabel:Set(string.format(
                            "Train: %s | Comp: %s | AutoClick: %s",
                            settings.autoTrain and "ON" or "OFF",
                            settings.autoCompetition and "ON" or "OFF",
                            settings.autoClickEnabled and "ON" or "OFF"
                        ))
                    end)

                    pcall(function()
                        statsLabel:Set(string.format(
                            "Muscle: %s | Stamina: %s | Power: %s | Rank: %s",
                            formatNumber(muscle),
                            formatNumber(stamina),
                            formatNumber(power),
                            tostring(rank)
                        ))
                    end)
                end

            end, function(msg)
                return debug.traceback(tostring(msg), 2)
            end)

            if not iterOk then
                warn("[RAVEN HUB][Gym Sim] loop error: " .. tostring(iterErr))
            end

            task.wait(0.05)
        end
    end)

    -- ============================================================
    --  CLEANUP
    -- ============================================================
    local function destroy()
        if not running then return end
        running = false
        clearEsp()
        setAutoClick(false)
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
        if espFolder.Parent then
            pcall(function() espFolder:Destroy() end)
        end
        if environment.__RAVEN_GYM_SIM
            and environment.__RAVEN_GYM_SIM.Settings == settings then
            environment.__RAVEN_GYM_SIM = nil
        end
    end

    environment.__RAVEN_GYM_SIM = {
        Settings = settings,
        Destroy = destroy,
        TeleportTo = teleportTo,
        GetEnergy = getEnergy,
        GetMuscle = getMuscle,
        GetStamina = getStamina,
        GetPower = getPower,
        RefreshESP = function() refreshPlayerEsp() end,
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    notify("🏋 Gym Sim", "v1.0.0 loaded — Auto Train + Competition + ESP ready!")
end
