--[[
    RAVEN HUB | +1 Drain Water Per Click
    PlaceId: 103883942725157 | GameId: 10561352230
    Version: v1.0.0

    Auto Crack Water | Fish/Pet/Egg ESP | Auto Sell | Stage Tracker | Teleport | Anti-AFK
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local VirtualUser = game:GetService("VirtualUser")
    local CoreGui = game:GetService("CoreGui")
    local StarterGui = game:GetService("StarterGui")

    local player = Players.LocalPlayer
    local environment = getgenv()

    -- Cleanup previous instance
    if type(environment.__RAVEN_DRAIN_WATER) == "table"
        and type(environment.__RAVEN_DRAIN_WATER.Destroy) == "function" then
        pcall(environment.__RAVEN_DRAIN_WATER.Destroy)
    end

    local running = true
    local connections = {}

    -- ============================================================
    --  REMOTE REFERENCES
    -- ============================================================
    local RemoteFolder = ReplicatedStorage:WaitForChild("Remote", 5)
    local EventFolder = RemoteFolder and RemoteFolder:WaitForChild("Event", 5)
    local FunctionFolder = RemoteFolder and RemoteFolder:WaitForChild("Function", 5)

    -- Pump remotes
    local PumpFolder = EventFolder and EventFolder:WaitForChild("Pump", 5)
    local BuyCashPump = PumpFolder and PumpFolder:FindFirstChild("[C-S]BuyCashPump")
    local EquipPump = PumpFolder and PumpFolder:FindFirstChild("[C-S]EquipPump")
    local GetPumpData = FunctionFolder and FunctionFolder:FindFirstChild("Pump")
        and FunctionFolder.Pump:FindFirstChild("[C-S]GetPumpData")

    -- Stage remotes
    local StageFolder = EventFolder and EventFolder:WaitForChild("Stage", 5)
    local StandingWater = StageFolder and StageFolder:FindFirstChild("[C-S]StandingWater")

    -- Upgrade remotes
    local UpgradeFolder = EventFolder and EventFolder:WaitForChild("Upgrade", 5)
    local BuyCashUpgrade = UpgradeFolder and UpgradeFolder:FindFirstChild("[C-S]BuyCashUpgrade")

    -- Fish remotes
    local FishFolder = EventFolder and EventFolder:WaitForChild("Fish", 5)
    local SellAllFish = FunctionFolder and FunctionFolder:FindFirstChild("Fish")
        and FunctionFolder.Fish:FindFirstChild("[C-S]SellAllFish")
    local SellFish = FunctionFolder and FunctionFolder.Fish
        and FunctionFolder.Fish:FindFirstChild("[C-S]SellFish")
    local GetFishData = FunctionFolder and FunctionFolder.Fish
        and FunctionFolder.Fish:FindFirstChild("[C-S]GetFishData")

    -- Egg remotes
    local EggFolder = EventFolder and EventFolder:WaitForChild("Egg", 5)
    local EggClientReady = EggFolder and EggFolder:FindFirstChild("[C-S]EggClientReady")

    -- Pet remotes
    local PetFolder = EventFolder and EventFolder:WaitForChild("Pet", 5)

    -- Aura remotes
    local AuraFolder = EventFolder and EventFolder:WaitForChild("Aura", 5)

    -- ============================================================
    --  SETTINGS
    -- ============================================================
    local settings = {
        -- Auto Crack
        autoCrack = false,
        crackInterval = 0.15,
        crackSpeed = 100,
        -- Auto Sell Fish
        autoSellFish = false,
        sellFishInterval = 5,
        -- Auto Buy Pump
        autoBuyPump = false,
        -- Auto Buy Upgrade
        autoBuyUpgrade = false,
        upgradeInterval = 3,
        -- ESP
        fishEsp = false,
        petEsp = false,
        eggEsp = false,
        exerciseEsp = false,
        espMaxDist = 500,
        -- Stage
        autoAdvanceStage = false,
        -- Teleport
        autoTpToNearestExercise = false,
        -- Anti AFK
        antiAfk = true,
    }

    -- ============================================================
    --  UTILITIES
    -- ============================================================
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

    local function getAttribute(name, default)
        local value = player:GetAttribute(name)
        return value ~= nil and value or default
    end

    local function fireRemote(remote, ...)
        local args = {...}
        if remote and typeof(remote) == "Instance" then
            if remote:IsA("RemoteEvent") then
                pcall(function() remote:FireServer(unpack(args)) end)
                return true
            elseif remote:IsA("RemoteFunction") then
                local ok, result = pcall(function() return remote:InvokeServer(unpack(args)) end)
                return ok and result or nil
            end
        end
        return false
    end

    -- ============================================================
    --  ESP SYSTEM
    -- ============================================================
    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenDrainWaterESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local espObjects = {}

    local ESP_COLORS = {
        fish = Color3.fromRGB(70, 200, 255),
        pet = Color3.fromRGB(255, 180, 50),
        egg = Color3.fromRGB(180, 100, 255),
        exercise = Color3.fromRGB(100, 255, 100),
    }

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

    local function addEsp(instance, category, label)
        if espObjects[instance] or not instance.Parent then return end
        local adornee = instance:IsA("Model") and instance
            or instance:FindFirstAncestorOfClass("Model")
            or instance
        local color = ESP_COLORS[category]

        local ok, highlight = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = "Raven_" .. category
            h.Adornee = adornee
            h.FillColor = color
            h.FillTransparency = 0.72
            h.OutlineColor = color
            h.OutlineTransparency = 0.08
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Parent = espFolder
            return h
        end)
        if not ok then return end

        local part = instance:IsA("BasePart") and instance
            or (instance:IsA("Model") and instance.PrimaryPart)
            or instance:FindFirstChildWhichIsA("BasePart", true)

        local ok2, billboard = pcall(function()
            local b = Instance.new("BillboardGui")
            b.Name = "RavenLabel_" .. category
            b.Adornee = part or adornee
            b.Size = UDim2.fromOffset(200, 36)
            b.StudsOffset = Vector3.new(0, 4, 0)
            b.AlwaysOnTop = true
            b.MaxDistance = settings.espMaxDist
            b.Parent = espFolder
            return b
        end)
        if not ok2 then highlight:Destroy() return end

        local ok3, labelObj = pcall(function()
            local l = Instance.new("TextLabel")
            l.Size = UDim2.fromScale(1, 1)
            l.BackgroundTransparency = 1
            l.Font = Enum.Font.GothamBold
            l.TextSize = 12
            l.TextColor3 = color
            l.TextStrokeTransparency = 0.25
            l.TextWrapped = true
            l.Text = label or instance.Name
            l.Parent = b
            return l
        end)

        espObjects[instance] = {
            category = category,
            highlight = highlight,
            billboard = billboard,
            label = labelObj,
        }
    end

    -- ============================================================
    --  GAME STATE READERS
    -- ============================================================
    local function getWaterLevel()
        return getAttribute("WaterLevel", 0)
    end

    local function getCrackRate()
        return getAttribute("CrackRate", 1)
    end

    local function getStage()
        return getAttribute("CurrentStage", 1)
    end

    local function isStageCompleted(stageNum)
        return getAttribute("StageCompleted_" .. stageNum, false)
    end

    local function getEquippedPumpId()
        return getAttribute("EquippedPumpId", 0)
    end

    local function getSpeedUpgrade()
        return getAttribute("SpeedUpgradeLevel", 0)
    end

    local function isAutoClickOwned()
        return getAttribute("AutoClickOwned", false)
    end

    local function getCoins()
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            local coins = leaderstats:FindFirstChild("Coins") or leaderstats:FindFirstChild("Cash")
            if coins and coins:IsA("ValueBase") then return coins.Value end
        end
        return getAttribute("Coins", 0)
    end

    local function getWins()
        return getAttribute("Wins", 0)
    end

    -- ============================================================
    --  AUTO CRACK
    -- ============================================================
    local lastCrackTick = 0
    local totalCracked = 0

    local function performCrack()
        if not running then return end
        local now = os.clock()
        if now - lastCrackTick < settings.crackInterval then return end
        lastCrackTick = now

        -- Fire the StandingWater remote to drain water
        if StandingWater then
            pcall(function()
                StandingWater:FireServer(settings.crackSpeed)
            end)
            totalCracked = totalCracked + settings.crackSpeed
        end
    end

    -- ============================================================
    --  AUTO SELL FISH
    -- ============================================================
    local lastSellTick = 0

    local function performAutoSell()
        if not running or not settings.autoSellFish then return end
        local now = os.clock()
        if now - lastSellTick < settings.sellFishInterval then return end
        lastSellTick = now

        if SellAllFish then
            local ok, result = pcall(function() return SellAllFish:InvokeServer() end)
            if ok and result then
                -- Successfully sold
            end
        end
    end

    -- ============================================================
    --  AUTO BUY PUMP
    -- ============================================================
    local lastPumpBuyTick = 0

    local function performAutoBuyPump()
        if not running or not settings.autoBuyPump then return end
        local now = os.clock()
        if now - lastPumpBuyTick < 2 then return end
        lastPumpBuyTick = now

        if BuyCashPump then
            pcall(function() BuyCashPump:FireServer() end)
        end
    end

    -- ============================================================
    --  AUTO BUY UPGRADE
    -- ============================================================
    local lastUpgradeTick = 0

    local function performAutoUpgrade()
        if not running or not settings.autoBuyUpgrade then return end
        local now = os.clock()
        if now - lastUpgradeTick < settings.upgradeInterval then return end
        lastUpgradeTick = now

        if BuyCashUpgrade then
            pcall(function() BuyCashUpgrade:FireServer() end)
        end
    end

    -- ============================================================
    --  FISH ESP
    -- ============================================================
    local function refreshFishEsp()
        if not settings.fishEsp then
            clearEsp("fish")
            return
        end

        local _, _, root = getCharacter()
        if not root then return end

        local seen = {}
        local fishRain = workspace:FindFirstChild("FishRain")
        if fishRain then
            for _, fish in ipairs(fishRain:GetChildren()) do
                if fish:IsA("BasePart") or fish:IsA("Model") then
                    seen[fish] = true
                    local dist = (fish.Position - root.Position).Magnitude
                    if dist <= settings.espMaxDist and not espObjects[fish] then
                        addEsp(fish, "fish", "[FISH] " .. fish.Name)
                    end
                end
            end
        end

        -- Also check for dropped fish in workspace
        for _, descendant in ipairs(workspace:GetChildren()) do
            if descendant:IsA("Model") and descendant.Name:lower():find("fish") then
                seen[descendant] = true
                local primaryPart = descendant.PrimaryPart or descendant:FindFirstChildWhichIsA("BasePart")
                if primaryPart then
                    local dist = (primaryPart.Position - root.Position).Magnitude
                    if dist <= settings.espMaxDist and not espObjects[descendant] then
                        addEsp(descendant, "fish", "[FISH] " .. descendant.Name)
                    end
                end
            end
        end

        -- Remove stale
        for instance, entry in pairs(espObjects) do
            if entry.category == "fish" and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end

    -- ============================================================
    --  PET ESP
    -- ============================================================
    local function refreshPetEsp()
        if not settings.petEsp then
            clearEsp("pet")
            return
        end

        local _, _, root = getCharacter()
        if not root then return end

        local seen = {}
        local petFolder = workspace:FindFirstChild("PetClient")
        if petFolder then
            for _, pet in ipairs(petFolder:GetChildren()) do
                if pet:IsA("Model") then
                    seen[pet] = true
                    local primaryPart = pet.PrimaryPart or pet:FindFirstChildWhichIsA("BasePart")
                    if primaryPart then
                        local dist = (primaryPart.Position - root.Position).Magnitude
                        if dist <= settings.espMaxDist and not espObjects[pet] then
                            addEsp(pet, "pet", "[PET] #" .. pet.Name)
                        end
                    end
                end
            end
        end

        -- Remove stale
        for instance, entry in pairs(espObjects) do
            if entry.category == "pet" and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end

    -- ============================================================
    --  EGG ESP
    -- ============================================================
    local function refreshEggEsp()
        if not settings.eggEsp then
            clearEsp("egg")
            return
        end

        local _, _, root = getCharacter()
        if not root then return end

        local seen = {}
        local uiopen = workspace:FindFirstChild("UIOPEN")
        if uiopen then
            for _, child in ipairs(uiopen:GetChildren()) do
                if child.Name:match("^Egg%d+$") and (child:IsA("BasePart") or child:IsA("Model")) then
                    seen[child] = true
                    local dist = (child.Position - root.Position).Magnitude
                    if dist <= settings.espMaxDist and not espObjects[child] then
                        addEsp(child, "egg", "[EGG] " .. child.Name)
                    end
                end
            end
        end

        -- Remove stale
        for instance, entry in pairs(espObjects) do
            if entry.category == "egg" and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end

    -- ============================================================
    --  EXERCISE AREA ESP
    -- ============================================================
    local function refreshExerciseEsp()
        if not settings.exerciseEsp then
            clearEsp("exercise")
            return
        end

        local _, _, root = getCharacter()
        if not root then return end

        local seen = {}
        local exerciseArea = workspace:FindFirstChild("ExerciseArea")
        if exerciseArea then
            for _, zone in ipairs(exerciseArea:GetChildren()) do
                if zone:IsA("BasePart") then
                    seen[zone] = true
                    local dist = (zone.Position - root.Position).Magnitude
                    if dist <= settings.espMaxDist and not espObjects[zone] then
                        addEsp(zone, "exercise", "[TRAIN] Zone " .. zone.Name .. " | " .. math.floor(dist) .. "m")
                    end
                end
            end
        end

        -- Remove stale
        for instance, entry in pairs(espObjects) do
            if entry.category == "exercise" and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end

    -- ============================================================
    --  UI TABS
    -- ============================================================

    -- Tab 1: Crack / Farm
    local FarmTab = Window:CreateTab("💧 Water Farm", "droplet")
    FarmTab:CreateSection("Auto Crack Water")
    local crackStatus = FarmTab:CreateLabel("Crack: idle | Total: 0")

    FarmTab:CreateToggle({
        Name = "Auto Crack Water",
        CurrentValue = false,
        Flag = "DrainWaterAutoCrack",
        Callback = function(v) settings.autoCrack = v end,
    })
    FarmTab:CreateSlider({
        Name = "Crack Speed",
        Range = {1, 1000},
        Increment = 10,
        CurrentValue = 100,
        Suffix = "/click",
        Flag = "DrainWaterCrackSpeed",
        Callback = function(v) settings.crackSpeed = v end,
    })
    FarmTab:CreateSlider({
        Name = "Crack Interval",
        Range = {0.05, 2},
        Increment = 0.05,
        CurrentValue = 0.15,
        Suffix = " s",
        Flag = "DrainWaterCrackInterval",
        Callback = function(v) settings.crackInterval = v end,
    })

    FarmTab:CreateSection("Auto Buy")
    FarmTab:CreateToggle({
        Name = "Auto Buy Pump",
        CurrentValue = false,
        Flag = "DrainWaterAutoBuyPump",
        Callback = function(v) settings.autoBuyPump = v end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Buy Upgrade",
        CurrentValue = false,
        Flag = "DrainWaterAutoBuyUpgrade",
        Callback = function(v) settings.autoBuyUpgrade = v end,
    })
    FarmTab:CreateSlider({
        Name = "Upgrade Interval",
        Range = {1, 10},
        Increment = 1,
        CurrentValue = 3,
        Suffix = " s",
        Flag = "DrainWaterUpgradeInterval",
        Callback = function(v) settings.upgradeInterval = v end,
    })

    -- Tab 2: Fish
    local FishTab = Window:CreateTab("🐟 Fish", "fish")
    FishTab:CreateSection("Auto Sell")
    FishTab:CreateToggle({
        Name = "Auto Sell Fish",
        CurrentValue = false,
        Flag = "DrainWaterAutoSellFish",
        Callback = function(v) settings.autoSellFish = v end,
    })
    FishTab:CreateSlider({
        Name = "Sell Interval",
        Range = {2, 30},
        Increment = 1,
        CurrentValue = 5,
        Suffix = " s",
        Flag = "DrainWaterSellFishInterval",
        Callback = function(v) settings.sellFishInterval = v end,
    })
    FishTab:CreateButton({
        Name = "Sell All Fish Now",
        Callback = function()
            if SellAllFish then
                local ok, result = pcall(function() return SellAllFish:InvokeServer() end)
                notify("🐟 Fish", ok and "All fish sold!" or "Sell failed")
            else
                notify("🐟 Fish", "Sell remote not found")
            end
        end,
    })

    -- Tab 3: ESP
    local EspTab = Window:CreateTab("👁 ESP", "eye")
    EspTab:CreateSection("World ESP")
    local espStatus = EspTab:CreateLabel("ESP: scanning...")

    EspTab:CreateToggle({
        Name = "Fish ESP",
        CurrentValue = false,
        Flag = "DrainWaterFishEsp",
        Callback = function(v) settings.fishEsp = v; if not v then clearEsp("fish") end end,
    })
    EspTab:CreateToggle({
        Name = "Pet ESP",
        CurrentValue = false,
        Flag = "DrainWaterPetEsp",
        Callback = function(v) settings.petEsp = v; if not v then clearEsp("pet") end end,
    })
    EspTab:CreateToggle({
        Name = "Egg ESP",
        CurrentValue = false,
        Flag = "DrainWaterEggEsp",
        Callback = function(v) settings.eggEsp = v; if not v then clearEsp("egg") end end,
    })
    EspTab:CreateToggle({
        Name = "Training Area ESP",
        CurrentValue = false,
        Flag = "DrainWaterExerciseEsp",
        Callback = function(v) settings.exerciseEsp = v; if not v then clearEsp("exercise") end end,
    })
    EspTab:CreateSlider({
        Name = "ESP Max Distance",
        Range = {50, 2000},
        Increment = 50,
        CurrentValue = 500,
        Suffix = " studs",
        Flag = "DrainWaterEspMaxDist",
        Callback = function(v) settings.espMaxDist = v end,
    })

    -- Tab 4: Travel
    local TravelTab = Window:CreateTab("🗺 Travel", "map-pin")
    TravelTab:CreateSection("Teleport")

    -- Exercise areas
    TravelTab:CreateButton({
        Name = "TP: Nearest Training Area",
        Callback = function()
            local _, _, root = getCharacter()
            if not root then return end
            local exerciseArea = workspace:FindFirstChild("ExerciseArea")
            if not exerciseArea then notify("Travel", "Training area not found") return end
            local best, bestDist
            for _, zone in ipairs(exerciseArea:GetChildren()) do
                if zone:IsA("BasePart") then
                    local dist = (zone.Position - root.Position).Magnitude
                    if not bestDist or dist < bestDist then
                        best, bestDist = zone, dist
                    end
                end
            end
            if best then
                teleportTo(best.Position + Vector3.new(0, 5, 0))
                notify("Travel", "Teleported to Training Zone " .. best.Name)
            end
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Shop",
        Callback = function()
            local shop = workspace:FindFirstChild("Shop")
            if shop then
                teleportTo(shop.Position + Vector3.new(0, 5, 0))
                notify("Travel", "Teleported to Shop")
            else
                notify("Travel", "Shop not found")
            end
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Egg Area",
        Callback = function()
            local uiopen = workspace:FindFirstChild("UIOPEN")
            local egg = uiopen and uiopen:FindFirstChild("Egg1")
            if egg then
                teleportTo(egg.Position + Vector3.new(0, 5, 0))
                notify("Travel", "Teleported to Egg Area")
            else
                notify("Travel", "Egg area not found")
            end
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Upgrade Station",
        Callback = function()
            local uiopen = workspace:FindFirstChild("UIOPEN")
            local upgrade = uiopen and uiopen:FindFirstChild("Upgrade")
            if upgrade then
                teleportTo(upgrade.Position + Vector3.new(0, 5, 0))
                notify("Travel", "Teleported to Upgrade Station")
            else
                notify("Travel", "Upgrade station not found")
            end
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Sell Area",
        Callback = function()
            local uiopen = workspace:FindFirstChild("UIOPEN")
            local sell = uiopen and uiopen:FindFirstChild("sell")
            if sell then
                teleportTo(sell.Position + Vector3.new(0, 5, 0))
                notify("Travel", "Teleported to Sell Area")
            else
                notify("Travel", "Sell area not found")
            end
        end,
    })

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
    local stageLabel = UtilTab:CreateLabel("Stage: loading...")
    local coinLabel = UtilTab:CreateLabel("Coins: loading...")

    UtilTab:CreateSection("Stability")
    UtilTab:CreateToggle({
        Name = "Anti AFK",
        CurrentValue = true,
        Flag = "DrainWaterAntiAfk",
        Callback = function(v) settings.antiAfk = v end,
    })

    UtilTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            pcall(function()
                game:GetService("TeleportService"):Teleport(game.PlaceId, player)
            end)
            notify("Utility", "Rejoining...")
        end,
    })

    UtilTab:CreateButton({
        Name = "Copy Game Link",
        Callback = function()
            pcall(function()
                if setclipboard then
                    setclipboard("https://www.roblox.com/games/" .. game.PlaceId)
                end
            end)
            notify("Utility", "Game link copied!")
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
        local crackAt = 0
        local sellAt = 0
        local upgradeAt = 0
        local pumpAt = 0
        local espAt = 0
        local statusAt = 0

        while running do
            local iterOk, iterErr = xpcall(function()
                local now = os.clock()

                -- Auto Crack
                if settings.autoCrack and now - crackAt >= settings.crackInterval then
                    crackAt = now
                    performCrack()
                end

                -- Auto Sell Fish
                if settings.autoSellFish and now - sellAt >= settings.sellFishInterval then
                    sellAt = now
                    performAutoSell()
                end

                -- Auto Buy Pump
                if settings.autoBuyPump and now - pumpAt >= 2 then
                    pumpAt = now
                    performAutoBuyPump()
                end

                -- Auto Buy Upgrade
                if settings.autoBuyUpgrade and now - upgradeAt >= settings.upgradeInterval then
                    upgradeAt = now
                    performAutoUpgrade()
                end

                -- ESP Refresh
                if (settings.fishEsp or settings.petEsp or settings.eggEsp or settings.exerciseEsp)
                    and now - espAt >= 1.5 then
                    espAt = now
                    refreshFishEsp()
                    refreshPetEsp()
                    refreshEggEsp()
                    refreshExerciseEsp()
                end

                -- Status Update
                if now - statusAt >= 0.5 then
                    statusAt = now
                    local water = getWaterLevel()
                    local rate = getCrackRate()
                    local stage = getStage()
                    local coins = getCoins()
                    local wins = getWins()
                    local pumpId = getEquippedPumpId()
                    local speed = getSpeedUpgrade()

                    pcall(function()
                        statusLabel:Set(string.format(
                            "Crack: %s | Rate: %s | Pump #%s | Speed Lv.%s",
                            settings.autoCrack and "ON" or "OFF",
                            tostring(rate),
                            tostring(pumpId),
                            tostring(speed)
                        ))
                    end)

                    -- Stage progress
                    local completed = 0
                    for i = 1, 18 do
                        if isStageCompleted(i) then completed = completed + 1 end
                    end
                    pcall(function()
                        stageLabel:Set(string.format(
                            "Stage: %d/18 completed | Current: %d",
                            completed, stage
                        ))
                    end)

                    pcall(function()
                        coinLabel:Set(string.format(
                            "Coins: %s | Wins: %s",
                            tostring(coins),
                            tostring(wins)
                        ))
                    end)

                    -- ESP count
                    local espCount = 0
                    for _ in pairs(espObjects) do espCount = espCount + 1 end
                    if espCount > 0 or settings.fishEsp or settings.petEsp or settings.eggEsp or settings.exerciseEsp then
                        pcall(function()
                            espStatus:Set(string.format(
                                "Active: %d objects | Fish: %s | Pet: %s | Egg: %s | Train: %s",
                                espCount,
                                settings.fishEsp and "ON" or "off",
                                settings.petEsp and "ON" or "off",
                                settings.eggEsp and "ON" or "off",
                                settings.exerciseEsp and "ON" or "off"
                            ))
                        end)
                    end
                end

            end, function(msg)
                return debug.traceback(tostring(msg), 2)
            end)

            if not iterOk then
                warn("[RAVEN HUB][💧 Drain Water] loop error: " .. tostring(iterErr))
            end

            task.wait(0.1)
        end
    end)

    -- ============================================================
    --  CLEANUP
    -- ============================================================
    local function destroy()
        if not running then return end
        running = false
        clearEsp()
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
        if espFolder.Parent then
            pcall(function() espFolder:Destroy() end)
        end
        if environment.__RAVEN_DRAIN_WATER
            and environment.__RAVEN_DRAIN_WATER.Settings == settings then
            environment.__RAVEN_DRAIN_WATER = nil
        end
    end

    environment.__RAVEN_DRAIN_WATER = {
        Settings = settings,
        Destroy = destroy,
        PerformCrack = performCrack,
        PerformAutoSell = performAutoSell,
        TeleportTo = teleportTo,
        GetWaterLevel = getWaterLevel,
        GetCrackRate = getCrackRate,
        GetStage = getStage,
        IsStageCompleted = isStageCompleted,
        GetCoins = getCoins,
        RefreshESP = function()
            refreshFishEsp()
            refreshPetEsp()
            refreshEggEsp()
            refreshExerciseEsp()
        end,
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    notify("💧 Drain Water", "v1.0.0 loaded — Auto Crack + ESP + Auto Sell ready!")
end
