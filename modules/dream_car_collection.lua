--[[
    RAVEN HUB | Dream Car Collection [12hrs]
    PlaceId: 76841016201110 | GameId: 10667357873
    Version: v1.0.0

    Features:
      • Turbo Auto Clean (Instant Foam Burst + Server-Capped PowerWash Progress Loop)
      • Automated Multi-Car Sweep (Iterates all dirty cars until 100% clean)
      • 12-Hour Cash Boost Keeper (+25% earnings keeper on all owned vehicles)
      • Rarity Priority Sniper (Cleans Mythic, Legendary & Cosmic cars first)
      • Auto Acknowledge & Popup Suppressor (Silently collects Gems without UI disruption)
      • Auto Washer Upgrades (Auto buys PowerWash & FoamSpray when affordable)
      • Live Car Fleet Telemetry (Inspects shine duration, dirty/clean counts, and gems earned)
      • Quick Plot & Wash Station Teleports
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local CollectionService = game:GetService("CollectionService")
    local HttpService = game:GetService("HttpService")

    local player = Players.LocalPlayer
    local environment = (type(getgenv) == "function" and getgenv()) or _G

    -- Cleanup any existing instance to avoid duplicate listeners / loops
    if type(environment.__RAVEN_DREAM_CAR) == "table"
        and type(environment.__RAVEN_DREAM_CAR.Destroy) == "function" then
        pcall(environment.__RAVEN_DREAM_CAR.Destroy)
        environment.__RAVEN_DREAM_CAR = nil
    end

    local running = true
    local connections = {}

    -- ============================================================
    --  GAME SERVICES & PACKAGES
    -- ============================================================
    local Networking = require(ReplicatedStorage:WaitForChild("Networking", 10))
    local PlayerDataShared = require(ReplicatedStorage.Shared.Managers.PlayerDataShared)
    local CarShineUtil = require(ReplicatedStorage.Shared.Utility.CarShineUtil)
    local CarsData = require(ReplicatedStorage.GAMEPLAY.Cars)
    local RarityData = require(ReplicatedStorage.GAMEPLAY.Rarity)
    local primaryFrame = nil
    pcall(function()
        primaryFrame = require(ReplicatedStorage.Client.States.primaryFrame)
    end)

    -- Wait for player data container
    local playerContainer = nil
    task.spawn(function()
        local ok, cont = PlayerDataShared.PlayerDataContainers:WaitForObject(player):await()
        if ok and cont then
            playerContainer = cont
        end
    end)

    -- ============================================================
    --  SETTINGS & STATE
    -- ============================================================
    local settings = {
        autoClean = false,
        priorityRarity = true,
        autoUpgrades = false,
        cleanDelay = 0.5,
        silentMode = true,
    }

    local sessionState = {
        active = false,
        currentCarId = nil,
        currentCarName = "None",
        currentCarRarity = "Common",
        stage = "Idle",
        progress = 0,
        gemsEarnedSession = 0,
        totalCleanedSession = 0,
        statusText = "Idle",
    }

    local RARITY_RANKS = {
        ["Secret"]    = 10,
        ["Cosmic"]    = 9,
        ["Divine"]    = 8,
        ["Mythic"]    = 7,
        ["Legendary"] = 6,
        ["Epic"]      = 5,
        ["Rare"]      = 4,
        ["Uncommon"]  = 3,
        ["Common"]    = 2,
    }

    -- Notification helper
    local function notify(title, msg, duration)
        duration = duration or 4
        pcall(function()
            if Window and Window.Notify then
                Window:Notify({
                    Title = title,
                    Content = msg,
                    Duration = duration
                })
            else
                game:GetService("StarterGui"):SetCore("SendNotification", {
                    Title = title,
                    Text = msg,
                    Duration = duration
                })
            end
        end)
    end

    -- ============================================================
    --  CAR INTEL HELPERS
    -- ============================================================
    local function getCarConfig(templateName)
        if not templateName then return {} end
        return CarsData[templateName] or {}
    end

    local function getOwnedCarsList()
        if not playerContainer then
            local ok, cont = PlayerDataShared.PlayerDataContainers:WaitForObject(player):await()
            if ok and cont then playerContainer = cont else return {} end
        end

        local cars = playerContainer:GetValue("Cars") or {}
        local list = {}
        local now = os.time()

        for carId, carData in pairs(cars) do
            local template = carData.Template or "Unknown"
            local cfg = getCarConfig(template)
            local shinyUntil = CarShineUtil.GetShinyUntil(carData)
            local isClean = now < shinyUntil
            local rarity = cfg.Rarity or "Common"
            local rank = RARITY_RANKS[rarity] or 1

            table.insert(list, {
                id = carId,
                template = template,
                displayName = cfg.Name or cfg.DisplayName or template,
                rarity = rarity,
                rarityRank = rank,
                shinyUntil = shinyUntil,
                isClean = isClean,
                secondsRemaining = math.max(0, shinyUntil - now),
                data = carData
            })
        end

        return list
    end

    local function getDirtyCars()
        local list = getOwnedCarsList()
        local dirty = {}
        for _, car in ipairs(list) do
            if not car.isClean then
                table.insert(dirty, car)
            end
        end

        if settings.priorityRarity then
            table.sort(dirty, function(a, b)
                if a.rarityRank ~= b.rarityRank then
                    return a.rarityRank > b.rarityRank
                end
                return a.displayName < b.displayName
            end)
        end

        return dirty
    end

    -- Suppress full-screen gem popups and menus during silent auto-clean
    local function suppressPopups()
        if settings.silentMode and primaryFrame then
            pcall(function()
                local cur = primaryFrame:get()
                if cur == "CleanCarMenu" or cur == "CleaningCarPicker" or cur == "CleaningGemEarnings" then
                    primaryFrame:set(nil)
                end
            end)
        end
    end

    -- ============================================================
    --  CLEANING PROTOCOL (BYTENET DIRECT CONTROLLER)
    -- ============================================================
    local currentServerSession = {
        active = false,
        stage = "Idle",
        progress = 0,
        carId = nil,
        completed = false,
        stopped = false,
        gems = 0
    }

    -- Listen to ByteNet Cleaning events
    local cleaningListener = Networking.Cleaning.SessionState.listen(function(data)
        if not running or type(data) ~= "table" then return end
        local evt = tostring(data.event or "")

        if evt == "Started" then
            currentServerSession.active = true
            currentServerSession.stage = data.stage or "Foam"
            currentServerSession.progress = data.progress or 0
            currentServerSession.carId = data.carId
            currentServerSession.completed = false
            currentServerSession.stopped = false

            sessionState.active = true
            sessionState.stage = currentServerSession.stage
            sessionState.progress = currentServerSession.progress
            sessionState.statusText = "Washing: " .. sessionState.currentCarName .. " (" .. currentServerSession.stage .. ")"
            suppressPopups()

        elseif evt == "Progress" then
            currentServerSession.progress = data.progress or currentServerSession.progress
            sessionState.progress = currentServerSession.progress
            sessionState.statusText = string.format("Washing: %s [%s %d%%]", sessionState.currentCarName, tostring(data.stage or currentServerSession.stage), sessionState.progress)

        elseif evt == "Stage" then
            currentServerSession.stage = data.stage or "Rinse"
            currentServerSession.progress = 0
            sessionState.stage = currentServerSession.stage
            sessionState.progress = 0
            sessionState.statusText = string.format("Switched to %s for %s", currentServerSession.stage, sessionState.currentCarName)

        elseif evt == "Completed" then
            currentServerSession.completed = true
            currentServerSession.active = false
            currentServerSession.gems = data.gems or 0
            sessionState.progress = 100
            sessionState.gemsEarnedSession = sessionState.gemsEarnedSession + currentServerSession.gems
            sessionState.totalCleanedSession = sessionState.totalCleanedSession + 1
            sessionState.statusText = string.format("Cleaned %s! (+%d Gems | +25%% $/s Active)", sessionState.currentCarName, currentServerSession.gems)
            notify("Car Upgraded ✨", string.format("%s is now Shiny! +25%% Cash/sec for 12h (+%d Gems)", sessionState.currentCarName, currentServerSession.gems), 4)

            -- Automatically acknowledge gem summary to close server modal
            pcall(function()
                Networking.Cleaning.AcknowledgeGemSummary.send()
            end)
            suppressPopups()

        elseif evt == "Stopped" then
            currentServerSession.stopped = true
            currentServerSession.active = false
            sessionState.active = false
            sessionState.statusText = "Session Stopped"
            suppressPopups()
        end
    end)
    table.insert(connections, {
        Disconnect = function()
            pcall(function()
                if type(cleaningListener) == "function" then
                    cleaningListener()
                elseif type(cleaningListener) == "table" and cleaningListener.Disconnect then
                    cleaningListener:Disconnect()
                end
            end)
        end
    })

    -- Clean a single target car
    local function cleanSingleCar(carInfo)
        if not carInfo or not carInfo.id then return false end

        sessionState.currentCarId = carInfo.id
        sessionState.currentCarName = carInfo.displayName
        sessionState.currentCarRarity = carInfo.rarity
        sessionState.stage = "Starting"
        sessionState.progress = 0
        sessionState.statusText = "Starting session for " .. carInfo.displayName .. "..."

        currentServerSession.active = false
        currentServerSession.completed = false
        currentServerSession.stopped = false
        currentServerSession.stage = "Foam"
        currentServerSession.progress = 0

        -- Send start request
        Networking.Cleaning.RequestStart.send({
            mode = "Manual",
            carId = carInfo.id
        })

        -- Wait up to 3s for session to register as Started
        local waitStart = os.clock()
        while running and not currentServerSession.active and not currentServerSession.stopped and (os.clock() - waitStart < 3.5) do
            task.wait(0.1)
        end

        if not currentServerSession.active then
            sessionState.statusText = "Failed to start session for " .. carInfo.displayName
            return false
        end

        -- Active washing loop: send progress at maximum permitted server cadence (~0.18s)
        local sessionStart = os.clock()
        local maxSessionDuration = 60 -- safety timeout per car

        while running and currentServerSession.active and not currentServerSession.completed and not currentServerSession.stopped and (os.clock() - sessionStart < maxSessionDuration) do
            local currentPhase = currentServerSession.stage or "Foam"

            -- Send 100% progress packet for current phase
            pcall(function()
                Networking.Cleaning.Progress.send({
                    phase = currentPhase,
                    progress = 100
                })
            end)

            suppressPopups()
            task.wait(0.18)
        end

        -- Finalize
        pcall(function()
            Networking.Cleaning.AcknowledgeGemSummary.send()
        end)
        suppressPopups()

        local success = currentServerSession.completed
        sessionState.active = false
        return success
    end

    -- ============================================================
    --  AUTO UPGRADE CLEANING TOOLS
    -- ============================================================
    local function tryAutoUpgradeWasher()
        if not settings.autoUpgrades or not Networking.Upgrades then return end
        pcall(function()
            Networking.Upgrades.BuyRequest.send({
                id = "PowerWash",
                buyAll = true
            })
            task.wait(0.1)
            Networking.Upgrades.BuyRequest.send({
                id = "FoamSpray",
                buyAll = true
            })
        end)
    end

    -- ============================================================
    --  MAIN AUTO-CLEAN BACKGROUND WORKER
    -- ============================================================
    task.spawn(function()
        while running do
            if settings.autoClean then
                tryAutoUpgradeWasher()

                local dirtyCars = getDirtyCars()
                if #dirtyCars > 0 then
                    sessionState.statusText = string.format("Found %d dirty car(s). Cleaning...", #dirtyCars)

                    for _, car in ipairs(dirtyCars) do
                        if not running or not settings.autoClean then break end

                        cleanSingleCar(car)
                        tryAutoUpgradeWasher()

                        if settings.cleanDelay > 0 then
                            task.wait(settings.cleanDelay)
                        end
                    end
                else
                    sessionState.statusText = "All cars are Clean (+25% 12h boost active)! Idling..."
                    sessionState.currentCarName = "All Clean"
                    sessionState.stage = "Idle"
                    sessionState.progress = 100
                    task.wait(5)
                end
            else
                task.wait(1)
            end
        end
    end)

    -- ============================================================
    --  TELEPORT HELPERS
    -- ============================================================
    local function getOwnedPlot()
        for _, v in ipairs(CollectionService:GetTagged("Plot")) do
            if v:IsA("Model") and v:GetAttribute("OwnerUserId") == player.UserId then
                return v
            end
        end
        return nil
    end

    local function teleportToPlotStation()
        local plot = getOwnedPlot()
        if not plot then
            notify("Teleport", "Could not locate your personal plot yet.")
            return
        end

        local pw = plot:FindFirstChild("scripted") and plot.scripted:FindFirstChild("Powerwash")
        local promptPos = pw and pw:FindFirstChild("PromptPosition")
        local targetCFrame = (promptPos and promptPos.CFrame * CFrame.new(0, 3, 0)) or (plot:GetPivot() * CFrame.new(0, 3, 0))

        local char = player.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        if root then
            root.CFrame = targetCFrame
            notify("Teleport", "Teleported to Car Wash Station!")
        end
    end

    -- ============================================================
    --  UI TABS & SECTIONS
    -- ============================================================

    -- 1. OVERVIEW TAB
    local OverviewTab = (Window.GetTab and Window:GetTab("Overview")) or Window:CreateTab("Overview", "home")
    OverviewTab:CreateSection("Fleet & Wash Telemetry")

    local labelFleetStats = OverviewTab:CreateLabel("Fleet: Loading...")
    local labelStatus = OverviewTab:CreateLabel("Status: Idle")
    local labelCurrentCar = OverviewTab:CreateLabel("Current Car: None")
    local labelGems = OverviewTab:CreateLabel("Session Gems Earned: 0")

    local function setLabelText(lbl, text)
        if not lbl then return end
        if lbl.Set then
            pcall(function() lbl:Set(text) end)
        elseif lbl.SetText then
            pcall(function() lbl:SetText(text) end)
        end
    end

    -- Update live labels
    task.spawn(function()
        while running do
            local allCars = getOwnedCarsList()
            local cleanCount = 0
            for _, c in ipairs(allCars) do
                if c.isClean then cleanCount = cleanCount + 1 end
            end
            local dirtyCount = #allCars - cleanCount

            setLabelText(labelFleetStats, string.format("Cars Owned: %d  |  Clean (12h Buff): %d  |  Dirty: %d", #allCars, cleanCount, dirtyCount))
            setLabelText(labelStatus, "Status: " .. sessionState.statusText)

            if sessionState.active then
                setLabelText(labelCurrentCar, string.format("Active: %s (%s) [%d%%]", sessionState.currentCarName, sessionState.currentCarRarity, sessionState.progress))
            else
                setLabelText(labelCurrentCar, "Active: None (Idle)")
            end

            setLabelText(labelGems, string.format("Gems Earned: +%d  |  Cleaned: %d cars", sessionState.gemsEarnedSession, sessionState.totalCleanedSession))

            task.wait(0.5)
        end
    end)

    OverviewTab:CreateSection("Quick Actions")
    OverviewTab:CreateButton({
        Name = "Clean All Dirty Cars Once",
        Callback = function()
            task.spawn(function()
                local dirty = getDirtyCars()
                if #dirty == 0 then
                    notify("Auto Clean", "All cars are already clean!")
                    return
                end
                notify("Auto Clean", string.format("Starting batch clean of %d cars...", #dirty))
                for _, car in ipairs(dirty) do
                    if not running then break end
                    cleanSingleCar(car)
                    task.wait(settings.cleanDelay)
                end
                notify("Auto Clean", "Batch clean finished!")
            end)
        end
    })

    OverviewTab:CreateButton({
        Name = "Clean Next Dirty Car",
        Callback = function()
            task.spawn(function()
                local dirty = getDirtyCars()
                local nextCar = dirty[1]
                if not nextCar then
                    notify("Auto Clean", "All cars are already clean!")
                    return
                end
                notify("Auto Clean", "Cleaning " .. nextCar.displayName .. "...")
                cleanSingleCar(nextCar)
            end)
        end
    })

    OverviewTab:CreateButton({
        Name = "Teleport to Wash Station",
        Callback = teleportToPlotStation
    })

    -- 2. AUTO CLEAN TAB
    local CleanTab = Window:CreateTab("Auto Clean", "sparkles")
    CleanTab:CreateSection("Turbo Auto Clean Automation")

    CleanTab:CreateToggle({
        Name = "Auto Clean Loop (All Dirty Cars)",
        CurrentValue = false,
        Flag = "DreamAutoCleanLoop",
        Callback = function(v)
            settings.autoClean = v
            if v then
                notify("Auto Clean", "Turbo Auto Clean Loop Activated 🧼")
            else
                notify("Auto Clean", "Auto Clean Loop Paused")
            end
        end
    })

    CleanTab:CreateToggle({
        Name = "Prioritize High Rarity Cars",
        CurrentValue = true,
        Flag = "DreamPriorityRarity",
        Callback = function(v)
            settings.priorityRarity = v
        end
    })

    CleanTab:CreateToggle({
        Name = "Auto Upgrade Washer (PowerWash & Foam)",
        CurrentValue = false,
        Flag = "DreamAutoUpgrades",
        Callback = function(v)
            settings.autoUpgrades = v
            if v then
                tryAutoUpgradeWasher()
                notify("Upgrades", "Auto Washer Upgrade Enabled!")
            end
        end
    })

    CleanTab:CreateToggle({
        Name = "Silent Mode (Suppress Popups)",
        CurrentValue = true,
        Flag = "DreamSilentMode",
        Callback = function(v)
            settings.silentMode = v
        end
    })

    CleanTab:CreateSlider({
        Name = "Delay Between Cars (Seconds)",
        Range = {0.1, 3.0},
        Increment = 0.1,
        CurrentValue = 0.5,
        Flag = "DreamCleanDelay",
        Callback = function(v)
            settings.cleanDelay = tonumber(v) or 0.5
        end
    })

    CleanTab:CreateSection("Manual Controls")
    CleanTab:CreateButton({
        Name = "Force Stop / Cancel Session",
        Callback = function()
            pcall(function()
                Networking.Cleaning.RequestStop.send({})
            end)
            sessionState.active = false
            sessionState.statusText = "Manually Stopped"
            notify("Clean", "Cleaning session stopped.")
        end
    })

    CleanTab:CreateButton({
        Name = "Buy Max Washer Upgrades Now",
        Callback = function()
            pcall(function()
                Networking.Upgrades.BuyRequest.send({ id = "PowerWash", buyAll = true })
                task.wait(0.1)
                Networking.Upgrades.BuyRequest.send({ id = "FoamSpray", buyAll = true })
                notify("Upgrades", "Bought max affordable washer upgrades!")
            end)
        end
    })

    -- 3. CAR FLEET & SHINE TAB
    local FleetTab = Window:CreateTab("Car Fleet", "car")
    FleetTab:CreateSection("Fleet Shine Status (12h Buff)")

    FleetTab:CreateButton({
        Name = "Log All Cars to Console (F9)",
        Callback = function()
            local list = getOwnedCarsList()
            print("================== DREAM CAR FLEET ==================")
            for i, c in ipairs(list) do
                local status = c.isClean and string.format("CLEAN (%dh %dm left)", math.floor(c.secondsRemaining / 3600), math.floor((c.secondsRemaining % 3600) / 60)) or "DIRTY (Needs Wash)"
                print(string.format("[%d] %s (%s) - %s", i, c.displayName, c.rarity, status))
            end
            print("=====================================================")
            notify("Fleet", "Car details logged to Developer Console (F9)!")
        end
    })

    -- 4. TELEPORT & PLOT TAB
    local TeleportTab = Window:CreateTab("Teleports", "map-pin")
    TeleportTab:CreateSection("Plot & World Locations")

    TeleportTab:CreateButton({
        Name = "My Plot / Car Wash Station",
        Callback = teleportToPlotStation
    })

    TeleportTab:CreateButton({
        Name = "Shops & Dealers",
        Callback = function()
            local shops = Workspace:FindFirstChild("rbx-build") and Workspace["rbx-build"]:FindFirstChild("Shops")
            local part = shops and shops:FindFirstChildWhichIsA("BasePart", true)
            if part and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                player.Character.HumanoidRootPart.CFrame = part.CFrame * CFrame.new(0, 4, 0)
                notify("Teleport", "Teleported to Shops!")
            end
        end
    })

    TeleportTab:CreateButton({
        Name = "Drag Strip",
        Callback = function()
            local ds = Workspace:FindFirstChild("rbx-build") and Workspace["rbx-build"]:FindFirstChild("DragStrip")
            local part = ds and ds:FindFirstChildWhichIsA("BasePart", true)
            if part and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                player.Character.HumanoidRootPart.CFrame = part.CFrame * CFrame.new(0, 4, 0)
                notify("Teleport", "Teleported to Drag Strip!")
            end
        end
    })

    TeleportTab:CreateButton({
        Name = "Leaderboards",
        Callback = function()
            local lb = Workspace:FindFirstChild("rbx-build") and Workspace["rbx-build"]:FindFirstChild("Leaderboards")
            local part = lb and lb:FindFirstChildWhichIsA("BasePart", true)
            if part and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                player.Character.HumanoidRootPart.CFrame = part.CFrame * CFrame.new(0, 4, 0)
                notify("Teleport", "Teleported to Leaderboards!")
            end
        end
    })

    -- Sort tabs cleanly
    if Window.SortTabs then
        pcall(function()
            Window:SortTabs({"Overview", "Auto Clean", "Car Fleet", "Teleports", "Settings"})
        end)
    end

    -- Return cleanup handle
    local moduleHandle = {
        Destroy = function()
            running = false
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
        end
    }

    environment.__RAVEN_DREAM_CAR = moduleHandle
    return moduleHandle
end
