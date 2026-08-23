--[[
    RAVEN HUB | [UPD] Load The Truck!
    PlaceId: 120491560796071 | GameId: 10417812127
    Version: v1.0.3

    Auto Boxes | Worker Mgmt | Upgrades | Scanner | Rewards | Teleport | ESP
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local VirtualUser = game:GetService("VirtualUser")
    local CoreGui = game:GetService("CoreGui")

    local player = Players.LocalPlayer
    local environment = getgenv()

    -- Cleanup previous instance
    if type(environment.__RAVEN_LOAD_TRUCK) == "table"
        and type(environment.__RAVEN_LOAD_TRUCK.Destroy) == "function" then
        pcall(environment.__RAVEN_LOAD_TRUCK.Destroy)
    end

    local running = true
    local connections = {}

    -- ============================================================
    --  REMOTE REFERENCES
    -- ============================================================
    local Events = ReplicatedStorage:WaitForChild("Events", 5)

    -- Upgrade remotes
    local Upgrade = Events and Events:FindFirstChild("Upgrade")
    local UnlockConveyor = Events and Events:FindFirstChild("UnlockConveyor")
    local UnlockFloor = Events and Events:FindFirstChild("UnlockFloor")
    local UnlockParking = Events and Events:FindFirstChild("UnlockParking")

    -- Worker remotes
    local HireWorker = Events and Events:FindFirstChild("HireWorker")
    local WakeWorker = Events and Events:FindFirstChild("WakeWorker")
    local AssignWorkerZone = Events and Events:FindFirstChild("AssignWorkerZone")

    -- Scanner remotes
    local BoxScanned = Events and Events:FindFirstChild("BoxScanned")
    local ScannerUpgrade = Events and Events:FindFirstChild("ScannerUpgrade")
    local UnlockScanner = Events and Events:FindFirstChild("UnlockScanner")

    -- Box / Tier
    local BoxTier = Events and Events:FindFirstChild("BoxTier")
    local TrashBoxes = Events and Events:FindFirstChild("TrashBoxes")

    -- Rebirth
    local Rebirth = Events and Events:FindFirstChild("Rebirth")

    -- Rewards
    local ClaimDailyReward = Events and Events:FindFirstChild("ClaimDailyReward")
    local ClaimLeaveReward = Events and Events:FindFirstChild("ClaimLeaveReward")
    local ClaimFreeReward = Events and Events:FindFirstChild("ClaimFreeReward")
    local ClaimGroupReward = Events and Events:FindFirstChild("ClaimGroupReward")
    local CheckLeaveReward = Events and Events:FindFirstChild("CheckLeaveReward")

    -- Lucky Block
    local OpenLuckyBlock = Events and Events:FindFirstChild("OpenLuckyBlock")

    -- Teleport
    local TeleportToPlot = Events and Events:FindFirstChild("TeleportToPlot")

    -- Settings / Tutorial
    local UpdateSettings = Events and Events:FindFirstChild("UpdateSettings")
    local SkipTutorial = Events and Events:FindFirstChild("SkipTutorial")

    -- ============================================================
    --  SETTINGS
    -- ============================================================
    local settings = {
        -- Box Farm
        autoCollectBoxes = false,
        autoDeposit = false,
        collectInterval = 0.5,
        -- Workers
        autoHireWorker = false,
        autoWakeWorker = false,
        autoAssignZone = false,
        workerInterval = 3,
        -- Upgrades
        autoUpgrade = false,
        autoUnlockConveyor = false,
        autoUnlockFloor = false,
        autoUnlockParking = false,
        upgradeInterval = 5,
        -- Scanner
        autoScan = false,
        autoUpgradeScanner = false,
        autoUnlockScanner = false,
        scannerInterval = 3,
        -- Rewards
        autoClaimDaily = false,
        autoClaimLeave = false,
        autoClaimFree = false,
        autoClaimGroup = false,
        autoOpenLuckyBlock = false,
        autoRebirth = false,
        autoTrashBoxes = false,
        rewardInterval = 10,
        -- ESP
        workerEsp = false,
        truckEsp = false,
        conveyorEsp = false,
        luckyBlockEsp = false,
        espMaxDist = 500,
        -- Anti AFK
        antiAfk = true,
    }

    -- ============================================================
    --  UTILITIES
    -- ============================================================
    local function formatNumber(n)
        if type(n) == "string" then return n end
        n = tonumber(n) or 0
        if n >= 1e9 then return string.format("%.1fB", n / 1e9)
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

    local function fireRemote(remote, args)
        args = args or {}
        local argumentCount = args.n or #args
        if remote and typeof(remote) == "Instance" then
            if remote:IsA("RemoteEvent") then
                local ok = pcall(function() remote:FireServer(unpack(args, 1, argumentCount)) end)
                return ok
            elseif remote:IsA("RemoteFunction") then
                local ok, result = pcall(function()
                    return remote:InvokeServer(unpack(args, 1, argumentCount))
                end)
                return ok and result or nil
            end
        end
        return false
    end

    local function getAttribute(name, default)
        local value = player:GetAttribute(name)
        return value ~= nil and value or default
    end

    local function getPlayerCash()
        local ls = player:FindFirstChild("leaderstats")
        local cash = ls and ls:FindFirstChild("Cash")
        return cash and cash:IsA("ValueBase") and cash.Value or "0"
    end

    local function getPlayerRebirths()
        local ls = player:FindFirstChild("leaderstats")
        local r = ls and ls:FindFirstChild("Rebirths")
        return r and r:IsA("ValueBase") and (tonumber(r.Value) or 0) or 0
    end

    local function getMyPlot()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end
        for _, plot in ipairs(plots:GetChildren()) do
            if tostring(plot:GetAttribute("Owner")) == tostring(player.UserId) then
                return plot
            end
        end
        return nil
    end

    local function getNextConveyorIndex()
        local plot = getMyPlot()
        local unlocks = plot and plot:FindFirstChild("ConveyorUnlocks")
        if not unlocks then return nil end
        local best
        for _, unlock in ipairs(unlocks:GetChildren()) do
            local index = tonumber(unlock.Name:match("(%d+)$"))
            local surface = unlock:FindFirstChild("SurfacePart")
            if index and surface and surface:IsA("BasePart") and surface.Transparency < 0.5
                and (not best or index < best) then
                best = index
            end
        end
        return best
    end

    local function getOwnedConveyorIndices()
        local nextIndex = getNextConveyorIndex() or 16
        local result = {}
        for index = 1, math.max(1, nextIndex - 1) do result[#result + 1] = index end
        return result
    end

    local function getNextBoxTier()
        local gui = player:FindFirstChildOfClass("PlayerGui")
        local frames = gui and gui:FindFirstChild("Frames")
        local boxTiers = frames and frames:FindFirstChild("BoxTiers")
        local scrolling = boxTiers and boxTiers:FindFirstChild("ScrollingFrame")
        local holder = scrolling and scrolling:FindFirstChild("Holder")
        if not holder then return nil end
        for _, row in ipairs(holder:GetChildren()) do
            local cash = row:FindFirstChild("Cash")
            local equip = row:FindFirstChild("Equip")
            local locked = row:FindFirstChild("LockedFrame")
            if cash and cash:IsA("GuiButton") and cash.Visible
                and (not locked or not locked.Visible) and (not equip or not equip.Visible) then
                return row.Name
            end
        end
        return nil
    end

    -- ============================================================
    --  ESP SYSTEM
    -- ============================================================
    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenLoadTruckESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local espObjects = {}

    local ESP_COLORS = {
        worker = Color3.fromRGB(100, 255, 100),
        truck = Color3.fromRGB(255, 180, 50),
        conveyor = Color3.fromRGB(70, 200, 255),
        luckyBlock = Color3.fromRGB(180, 100, 255),
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

        pcall(function()
            local l = Instance.new("TextLabel")
            l.Size = UDim2.fromScale(1, 1)
            l.BackgroundTransparency = 1
            l.Font = Enum.Font.GothamBold
            l.TextSize = 12
            l.TextColor3 = color
            l.TextStrokeTransparency = 0.25
            l.TextWrapped = true
            l.Text = label or instance.Name
            l.Parent = billboard
        end)

        espObjects[instance] = {
            category = category,
            highlight = highlight,
            billboard = billboard,
        }
    end

    -- ============================================================
    --  GAME STATE READERS
    -- ============================================================
    local function getWorkerCount()
        local workers = workspace:FindFirstChild("ActiveWorkers")
        if not workers then return 0 end
        local count = 0
        for _, worker in ipairs(workers:GetChildren()) do
            if tostring(worker:GetAttribute("OwnerUserId")) == tostring(player.UserId) then
                count += 1
            end
        end
        return count
    end

    local function getTruckCount()
        local vehicles = workspace:FindFirstChild("ActiveVehicles")
        if not vehicles then return 0 end
        local count = 0
        for _, vehicle in ipairs(vehicles:GetChildren()) do
            local owner = vehicle:GetAttribute("OwnerUserId") or vehicle:GetAttribute("Owner")
            if tostring(owner) == tostring(player.UserId) then count += 1 end
        end
        return count
    end

    local function getManagerCount()
        local managers = workspace:FindFirstChild("ActiveManagers")
        if not managers then return 0 end
        local count = 0
        for _, manager in ipairs(managers:GetChildren()) do
            if tostring(manager:GetAttribute("OwnerUserId")) == tostring(player.UserId) then count += 1 end
        end
        return count
    end

    local function getBoxCount()
        return getAttribute("BoxCount", 0)
    end

    local function getRebirthCount()
        return getPlayerRebirths()
    end

    local function getCash()
        return getPlayerCash()
    end

    -- ============================================================
    --  TAB 1: BOX FARM
    -- ============================================================
    local totalCollected = 0

    local function performAutoCollect()
        if not running or not settings.autoCollectBoxes then return end
        local _, _, root = getCharacter()
        if not root then return end

        local plot = getMyPlot()
        local collectZone = plot and plot:FindFirstChild("CollectZone")
        if collectZone and collectZone:IsA("BasePart") then
            local before = getBoxCount()
            teleportTo(collectZone.Position + Vector3.new(0, 3, 0))
            task.delay(0.25, function()
                if running and getBoxCount() ~= before then totalCollected += 1 end
            end)
        end
    end

    local function performAutoDeposit()
        if not running or not settings.autoDeposit then return end
        local _, _, root = getCharacter()
        if not root then return end

        local plotRoot = workspace:FindFirstChild("Plots")
        if not plotRoot then return end

        -- Find truck zone or deposit area
        local truckZone = workspace:FindFirstChild("TruckZone")
        if truckZone and truckZone:IsA("BasePart") then
            local dist = (truckZone.Position - root.Position).Magnitude
            if dist > 5 then
                teleportTo(truckZone.Position + Vector3.new(0, 3, 0))
            end
        end
    end

    local FarmTab = Window:CreateTab("📦 Box Farm", "package")
    FarmTab:CreateSection("Auto Collect & Deposit")
    local boxStatus = FarmTab:CreateLabel("Boxes: 0 | Collected: 0")

    FarmTab:CreateToggle({
        Name = "Auto Collect Boxes",
        CurrentValue = false,
        Flag = "LoadTruckAutoCollect",
        Callback = function(v) settings.autoCollectBoxes = v end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Deposit to Truck",
        CurrentValue = false,
        Flag = "LoadTruckAutoDeposit",
        Callback = function(v) settings.autoDeposit = v end,
    })
    FarmTab:CreateSlider({
        Name = "Collect Interval",
        Range = {0.1, 5},
        Increment = 0.1,
        CurrentValue = 0.5,
        Suffix = " s",
        Flag = "LoadTruckCollectInterval",
        Callback = function(v) settings.collectInterval = v end,
    })

    FarmTab:CreateSection("Box Tier")
    FarmTab:CreateButton({
        Name = "Upgrade Box Tier",
        Callback = function()
            local tier = getNextBoxTier()
            if tier then
                fireRemote(BoxTier, {"Buy", tier})
                task.delay(0.5, function() if running then fireRemote(BoxTier, {"Equip", tier}) end end)
                notify("📦 Box", "Buying box tier: " .. tier)
            else
                notify("📦 Box", "No purchasable box tier found")
            end
        end,
    })
    FarmTab:CreateButton({
        Name = "Trash All Boxes",
        Callback = function()
            fireRemote(TrashBoxes, {})
            notify("📦 Box", "Boxes trashed")
        end,
    })

    -- ============================================================
    --  TAB 2: WORKERS & TRUCKS
    -- ============================================================
    local function performAutoHireWorker()
        if not running or not settings.autoHireWorker then return end
        fireRemote(HireWorker, {})
    end

    local workerWakeAt = setmetatable({}, {__mode = "k"})
    local function performAutoWakeWorker()
        if not running or not settings.autoWakeWorker then return end
        local myId = tostring(player.UserId)
        local workers = workspace:FindFirstChild("ActiveWorkers")
        if workers then
            for _, worker in ipairs(workers:GetChildren()) do
                if worker:IsA("Model") then
                    local owner = tostring(worker:GetAttribute("OwnerUserId") or "")
                    local working = worker:GetAttribute("Working")
                    local stamina = worker:GetAttribute("Stamina") or 0

                    -- Only wake my workers that are sleeping (Working=false or Stamina=0)
                    local now = os.clock()
                    if owner == myId and (working == false or stamina == 0)
                        and now - (workerWakeAt[worker] or -math.huge) >= 5 then
                        fireRemote(WakeWorker, {worker})
                        workerWakeAt[worker] = now
                    end
                end
            end
        end
    end

    local assignedWorkers = {}
    local function performAutoAssignZone()
        if not running or not settings.autoAssignZone then return end
        local workers = workspace:FindFirstChild("ActiveWorkers")
        if not workers then return end
        for _, worker in ipairs(workers:GetChildren()) do
            if tostring(worker:GetAttribute("OwnerUserId")) == tostring(player.UserId) then
                local index = tonumber(worker.Name:match("_Worker_(%d+)$"))
                if index and not assignedWorkers[index] then
                    fireRemote(AssignWorkerZone, table.pack("Worker", nil, index, "Auto"))
                    assignedWorkers[index] = true
                end
            end
        end
    end

    local WorkerTab = Window:CreateTab("👷 Workers", "users")
    WorkerTab:CreateSection("Worker Management")
    local workerStatus = WorkerTab:CreateLabel("Workers: 0 | Managers: 0")

    WorkerTab:CreateToggle({
        Name = "Auto Hire Worker",
        CurrentValue = false,
        Flag = "LoadTruckAutoHire",
        Callback = function(v) settings.autoHireWorker = v end,
    })
    WorkerTab:CreateToggle({
        Name = "Auto Wake Workers",
        CurrentValue = false,
        Flag = "LoadTruckAutoWake",
        Callback = function(v) settings.autoWakeWorker = v end,
    })
    WorkerTab:CreateToggle({
        Name = "Auto Assign Zone",
        CurrentValue = false,
        Flag = "LoadTruckAutoAssign",
        Callback = function(v) settings.autoAssignZone = v end,
    })
    WorkerTab:CreateSlider({
        Name = "Worker Action Interval",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = 3,
        Suffix = " s",
        Flag = "LoadTruckWorkerInterval",
        Callback = function(v) settings.workerInterval = v end,
    })

    WorkerTab:CreateSection("Worker ESP")
    WorkerTab:CreateToggle({
        Name = "Worker ESP",
        CurrentValue = false,
        Flag = "LoadTruckWorkerEsp",
        Callback = function(v) settings.workerEsp = v; if not v then clearEsp("worker") end end,
    })
    WorkerTab:CreateToggle({
        Name = "Truck ESP",
        CurrentValue = false,
        Flag = "LoadTruckTruckEsp",
        Callback = function(v) settings.truckEsp = v; if not v then clearEsp("truck") end end,
    })

    -- ============================================================
    --  TAB 3: UPGRADES
    -- ============================================================
    local upgradeNames = {
        "ProductionRate", "WalkSpeed", "StackSize", "Luck", "BoxFlySpeed",
        "WorkerSpeed", "WorkerStackSize", "WorkerLuck", "WorkerEnergy",
        "TruckSpeed", "TruckSpawnRate",
    }
    local upgradeCursor = 0
    local function performAutoUpgrade()
        if not running or not settings.autoUpgrade then return end
        upgradeCursor = upgradeCursor % #upgradeNames + 1
        fireRemote(Upgrade, {upgradeNames[upgradeCursor], "Cash"})
    end

    local function performAutoUnlockConveyor()
        if not running or not settings.autoUnlockConveyor then return end
        local index = getNextConveyorIndex()
        if index then fireRemote(UnlockConveyor, {index}) end
    end

    local function unlockNextFloor()
        local plot = getMyPlot()
        if not plot then return end
        for floor, signName in ipairs({"SecondFloorUnlockSign", "ThirdFloorUnlockSign"}) do
            local sign = plot:FindFirstChild(signName)
            local part = sign and sign:FindFirstChildWhichIsA("BasePart", true)
            if part and part.Transparency < 0.5 then
                fireRemote(UnlockFloor, {floor + 1})
                return
            end
        end
    end

    local function performAutoUnlockFloor()
        if not running or not settings.autoUnlockFloor then return end
        unlockNextFloor()
    end

    local function performAutoUnlockParking()
        if not running or not settings.autoUnlockParking then return end
        local plot = getMyPlot()
        local unlocks = plot and (plot:FindFirstChild("ParkingUnlocks") or plot:FindFirstChild("VehicleStopUnlocks"))
        if not unlocks then return end
        for _, unlock in ipairs(unlocks:GetChildren()) do
            local index = tonumber(unlock.Name:match("(%d+)$"))
            local part = unlock:FindFirstChildWhichIsA("BasePart", true)
            if index and part and part.Transparency < 0.5 then
                fireRemote(UnlockParking, {index})
                return
            end
        end
    end

    local UpgradeTab = Window:CreateTab("⬆️ Upgrades", "arrow-up")
    UpgradeTab:CreateSection("Auto Upgrade")
    local upgradeStatus = UpgradeTab:CreateLabel("Upgrades: idle")

    UpgradeTab:CreateToggle({
        Name = "Auto Upgrade",
        CurrentValue = false,
        Flag = "LoadTruckAutoUpgrade",
        Callback = function(v) settings.autoUpgrade = v end,
    })
    UpgradeTab:CreateToggle({
        Name = "Auto Unlock Conveyor",
        CurrentValue = false,
        Flag = "LoadTruckAutoUnlockConveyor",
        Callback = function(v) settings.autoUnlockConveyor = v end,
    })
    UpgradeTab:CreateToggle({
        Name = "Auto Unlock Floor (2F/3F)",
        CurrentValue = false,
        Flag = "LoadTruckAutoUnlockFloor",
        Callback = function(v) settings.autoUnlockFloor = v end,
    })
    UpgradeTab:CreateToggle({
        Name = "Auto Unlock Parking",
        CurrentValue = false,
        Flag = "LoadTruckAutoUnlockParking",
        Callback = function(v) settings.autoUnlockParking = v end,
    })
    UpgradeTab:CreateSlider({
        Name = "Upgrade Interval",
        Range = {1, 20},
        Increment = 1,
        CurrentValue = 5,
        Suffix = " s",
        Flag = "LoadTruckUpgradeInterval",
        Callback = function(v) settings.upgradeInterval = v end,
    })

    UpgradeTab:CreateSection("Manual Upgrade")
    UpgradeTab:CreateButton({
        Name = "Upgrade Now",
        Callback = function()
            fireRemote(Upgrade, {"ProductionRate", "Cash"})
            notify("⬆️ Upgrade", "Upgrade requested")
        end,
    })
    UpgradeTab:CreateButton({
        Name = "Unlock Next Conveyor",
        Callback = function()
            local index = getNextConveyorIndex()
            if index then fireRemote(UnlockConveyor, {index}) end
            notify("⬆️ Upgrade", "Conveyor unlock requested")
        end,
    })
    UpgradeTab:CreateButton({
        Name = "Unlock Next Floor",
        Callback = function()
            unlockNextFloor()
            notify("⬆️ Upgrade", "Floor unlock requested")
        end,
    })

    -- ============================================================
    --  TAB 4: SCANNER
    -- ============================================================
    local function performAutoScan()
        if not running or not settings.autoScan then return end
        fireRemote(BoxScanned, {})
    end

    local scannerCursor = 0
    local function nextScannerIndex()
        local indices = getOwnedConveyorIndices()
        scannerCursor = scannerCursor % #indices + 1
        return indices[scannerCursor]
    end

    local function performAutoUpgradeScanner()
        if not running or not settings.autoUpgradeScanner then return end
        local index = nextScannerIndex()
        fireRemote(ScannerUpgrade, {index, "ScanCooldown", "Cash"})
        fireRemote(ScannerUpgrade, {index, "CashMultiplier", "Cash"})
    end


    local function performAutoUnlockScanner()
        if running and settings.autoUnlockScanner then
            fireRemote(UnlockScanner, {nextScannerIndex()})
        end
    end

    local ScannerTab = Window:CreateTab("📡 Scanner", "radio")
    ScannerTab:CreateSection("Auto Scanner")
    local scannerStatus = ScannerTab:CreateLabel("Scanner: idle")

    ScannerTab:CreateToggle({
        Name = "Auto Scan Boxes",
        CurrentValue = false,
        Flag = "LoadTruckAutoScan",
        Callback = function(v) settings.autoScan = v end,
    })
    ScannerTab:CreateToggle({
        Name = "Auto Upgrade Scanner",
        CurrentValue = false,
        Flag = "LoadTruckAutoUpgradeScanner",
        Callback = function(v) settings.autoUpgradeScanner = v end,
    })
    ScannerTab:CreateToggle({
        Name = "Auto Unlock Scanner",
        CurrentValue = false,
        Flag = "LoadTruckAutoUnlockScanner",
        Callback = function(v) settings.autoUnlockScanner = v end,
    })
    ScannerTab:CreateSlider({
        Name = "Scanner Interval",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = 3,
        Suffix = " s",
        Flag = "LoadTruckScannerInterval",
        Callback = function(v) settings.scannerInterval = v end,
    })

    ScannerTab:CreateSection("Manual Scanner")
    ScannerTab:CreateButton({
        Name = "Scan Now",
        Callback = function()
            fireRemote(BoxScanned, {})
            notify("📡 Scanner", "Box scan triggered")
        end,
    })
    ScannerTab:CreateButton({
        Name = "Upgrade Scanner",
        Callback = function()
            fireRemote(ScannerUpgrade, {"ScanCooldown", "Cash"})
            notify("📡 Scanner", "Scanner upgrade requested")
        end,
    })
    ScannerTab:CreateButton({
        Name = "Unlock Scanner",
        Callback = function()
            fireRemote(UnlockScanner, {})
            notify("📡 Scanner", "Scanner unlock requested")
        end,
    })

    -- ============================================================
    --  TAB 5: TRAVEL & ESP
    -- ============================================================
    local TravelTab = Window:CreateTab("🗺 Travel", "map-pin")
    TravelTab:CreateSection("Teleport")

    TravelTab:CreateButton({
        Name = "TP: Truck Zone",
        Callback = function()
            local tz = workspace:FindFirstChild("TruckZone")
            if tz and tz:IsA("BasePart") then
                teleportTo(tz.Position + Vector3.new(0, 5, 0))
                notify("🗺 Travel", "Teleported to Truck Zone")
            else
                notify("🗺 Travel", "Truck Zone not found")
            end
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Spawn",
        Callback = function()
            local spawn = workspace:FindFirstChild("SpawnLocation")
            if spawn then
                teleportTo(spawn.Position + Vector3.new(0, 5, 0))
                notify("🗺 Travel", "Teleported to Spawn")
            end
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Nearest Plot",
        Callback = function()
            local _, _, root = getCharacter()
            if not root then return end
            local plots = workspace:FindFirstChild("Plots")
            if not plots then notify("🗺 Travel", "No plots found") return end
            local best, bestDist
            for _, plot in ipairs(plots:GetChildren()) do
                local part = plot:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    local dist = (part.Position - root.Position).Magnitude
                    if not bestDist or dist < bestDist then
                        best, bestDist = plot, dist
                    end
                end
            end
            if best then
                local part = best:FindFirstChildWhichIsA("BasePart", true)
                if part then
                    teleportTo(part.Position + Vector3.new(0, 5, 0))
                    notify("🗺 Travel", "Teleported to " .. best.Name)
                end
            end
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Collect Zone",
        Callback = function()
            local _, _, root = getCharacter()
            if not root then return end
            local plots = workspace:FindFirstChild("Plots")
            if not plots then return end
            for _, plot in ipairs(plots:GetChildren()) do
                local cz = plot:FindFirstChild("CollectZone")
                if cz and cz:IsA("BasePart") then
                    teleportTo(cz.Position + Vector3.new(0, 3, 0))
                    notify("🗺 Travel", "Teleported to Collect Zone")
                    return
                end
            end
            notify("🗺 Travel", "Collect Zone not found")
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Airfield",
        Callback = function()
            local _, _, root = getCharacter()
            if not root then return end
            local plots = workspace:FindFirstChild("Plots")
            if not plots then return end
            for _, plot in ipairs(plots:GetChildren()) do
                local airfield = plot:FindFirstChild("Airfield")
                if airfield then
                    local part = airfield:FindFirstChildWhichIsA("BasePart")
                    if part then
                        teleportTo(part.Position + Vector3.new(0, 5, 0))
                        notify("🗺 Travel", "Teleported to Airfield")
                        return
                    end
                end
            end
            notify("🗺 Travel", "Airfield not found")
        end,
    })

    TravelTab:CreateButton({
        Name = "TP: Worker Wait Zone",
        Callback = function()
            local _, _, root = getCharacter()
            if not root then return end
            local plots = workspace:FindFirstChild("Plots")
            if not plots then return end
            for _, plot in ipairs(plots:GetChildren()) do
                local wwz = plot:FindFirstChild("WorkerWaitZone")
                if wwz and wwz:IsA("BasePart") then
                    teleportTo(wwz.Position + Vector3.new(0, 3, 0))
                    notify("🗺 Travel", "Teleported to Worker Wait Zone")
                    return
                end
            end
            notify("🗺 Travel", "Worker Wait Zone not found")
        end,
    })

    TravelTab:CreateSection("ESP")
    TravelTab:CreateToggle({
        Name = "Worker ESP",
        CurrentValue = false,
        Flag = "LoadTruckWorkerEsp2",
        Callback = function(v) settings.workerEsp = v; if not v then clearEsp("worker") end end,
    })
    TravelTab:CreateToggle({
        Name = "Truck ESP",
        CurrentValue = false,
        Flag = "LoadTruckTruckEsp2",
        Callback = function(v) settings.truckEsp = v; if not v then clearEsp("truck") end end,
    })
    TravelTab:CreateToggle({
        Name = "Lucky Block ESP",
        CurrentValue = false,
        Flag = "LoadTruckLuckyBlockEsp",
        Callback = function(v) settings.luckyBlockEsp = v; if not v then clearEsp("luckyBlock") end end,
    })
    TravelTab:CreateToggle({
        Name = "Conveyor ESP",
        CurrentValue = false,
        Flag = "LoadTruckConveyorEsp",
        Callback = function(v) settings.conveyorEsp = v; if not v then clearEsp("conveyor") end end,
    })
    TravelTab:CreateSlider({
        Name = "ESP Max Distance",
        Range = {50, 2000},
        Increment = 50,
        CurrentValue = 500,
        Suffix = " studs",
        Flag = "LoadTruckEspMaxDist",
        Callback = function(v)
            settings.espMaxDist = v
            for _, entry in pairs(espObjects) do
                if entry.billboard then entry.billboard.MaxDistance = v end
            end
        end,
    })

    -- ============================================================
    --  TAB 6: REWARDS
    -- ============================================================
    local lastRewardTick = 0

    local function performAutoRewards()
        if not running then return end
        local now = os.clock()
        if now - lastRewardTick < settings.rewardInterval then return end
        lastRewardTick = now

        if settings.autoClaimDaily then fireRemote(ClaimDailyReward, {}) end
        if settings.autoClaimFree then fireRemote(ClaimFreeReward, {}) end
        if settings.autoClaimGroup then fireRemote(ClaimGroupReward, {}) end
        if settings.autoOpenLuckyBlock then fireRemote(OpenLuckyBlock, {}) end
        if settings.autoTrashBoxes then fireRemote(TrashBoxes, {}) end
    end

    local function performAutoRebirth()
        if not running or not settings.autoRebirth then return end
        fireRemote(Rebirth, {})
    end

    local RewardTab = Window:CreateTab("🎁 Rewards", "gift")
    RewardTab:CreateSection("Auto Claim Rewards")
    local rewardStatus = RewardTab:CreateLabel("Rewards: idle")

    RewardTab:CreateToggle({
        Name = "Auto Claim Daily Reward",
        CurrentValue = false,
        Flag = "LoadTruckAutoClaimDaily",
        Callback = function(v) settings.autoClaimDaily = v end,
    })
    RewardTab:CreateToggle({
        Name = "Auto Claim Leave Reward",
        CurrentValue = false,
        Flag = "LoadTruckAutoClaimLeave",
        Callback = function(v) settings.autoClaimLeave = v end,
    })
    RewardTab:CreateToggle({
        Name = "Auto Claim Free Reward",
        CurrentValue = false,
        Flag = "LoadTruckAutoClaimFree",
        Callback = function(v) settings.autoClaimFree = v end,
    })
    RewardTab:CreateToggle({
        Name = "Auto Claim Group Reward",
        CurrentValue = false,
        Flag = "LoadTruckAutoClaimGroup",
        Callback = function(v) settings.autoClaimGroup = v end,
    })
    RewardTab:CreateToggle({
        Name = "Auto Open Lucky Block",
        CurrentValue = false,
        Flag = "LoadTruckAutoOpenLucky",
        Callback = function(v) settings.autoOpenLuckyBlock = v end,
    })
    RewardTab:CreateToggle({
        Name = "Auto Rebirth",
        CurrentValue = false,
        Flag = "LoadTruckAutoRebirth",
        Callback = function(v) settings.autoRebirth = v end,
    })
    RewardTab:CreateToggle({
        Name = "Auto Trash Boxes",
        CurrentValue = false,
        Flag = "LoadTruckAutoTrash",
        Callback = function(v) settings.autoTrashBoxes = v end,
    })
    RewardTab:CreateSlider({
        Name = "Reward Check Interval",
        Range = {5, 60},
        Increment = 5,
        CurrentValue = 10,
        Suffix = " s",
        Flag = "LoadTruckRewardInterval",
        Callback = function(v) settings.rewardInterval = v end,
    })

    RewardTab:CreateSection("Manual Claim")
    RewardTab:CreateButton({
        Name = "Claim Daily Reward",
        Callback = function()
            fireRemote(ClaimDailyReward, {})
            notify("🎁 Rewards", "Daily reward claimed")
        end,
    })
    RewardTab:CreateButton({
        Name = "Claim Leave Reward",
        Callback = function()
            fireRemote(ClaimLeaveReward, {})
            notify("🎁 Rewards", "Leave reward claimed")
        end,
    })
    RewardTab:CreateButton({
        Name = "Claim Free Reward",
        Callback = function()
            fireRemote(ClaimFreeReward, {})
            notify("🎁 Rewards", "Free reward claimed")
        end,
    })
    RewardTab:CreateButton({
        Name = "Claim Group Reward",
        Callback = function()
            fireRemote(ClaimGroupReward, {})
            notify("🎁 Rewards", "Group reward claimed")
        end,
    })
    RewardTab:CreateButton({
        Name = "Rebirth Now",
        Callback = function()
            fireRemote(Rebirth, {})
            notify("🎁 Rewards", "Rebirth attempted")
        end,
    })

    -- ============================================================
    --  TAB 7: UTILITY
    -- ============================================================
    local UtilTab = Window:CreateTab("⚙ Utility", "settings")
    UtilTab:CreateSection("Status")
    local statusLabel = UtilTab:CreateLabel("Loading...")
    local workerLabel = UtilTab:CreateLabel("Workers: loading...")
    local truckLabel = UtilTab:CreateLabel("Trucks: loading...")

    UtilTab:CreateSection("Stability")
    UtilTab:CreateToggle({
        Name = "Anti AFK",
        CurrentValue = true,
        Flag = "LoadTruckAntiAfk",
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
    --  ESP REFRESH FUNCTIONS
    -- ============================================================
    local function refreshWorkerEsp()
        if not settings.workerEsp then clearEsp("worker") return end
        local _, _, root = getCharacter()
        if not root then return end

        local seen = {}
        local workers = workspace:FindFirstChild("ActiveWorkers")
        if workers then
            for _, worker in ipairs(workers:GetChildren()) do
                if worker:IsA("Model") then
                    local part = worker.PrimaryPart or worker:FindFirstChildWhichIsA("BasePart")
                    if part then
                        local dist = (part.Position - root.Position).Magnitude
                        if dist <= settings.espMaxDist then
                            seen[worker] = true
                            if not espObjects[worker] then addEsp(worker, "worker", "[WORKER] " .. worker.Name) end
                        end
                    end
                end
            end
        end

        for instance, entry in pairs(espObjects) do
            if entry.category == "worker" and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end

    local function refreshTruckEsp()
        if not settings.truckEsp then clearEsp("truck") return end
        local _, _, root = getCharacter()
        if not root then return end

        local seen = {}
        local vehicles = workspace:FindFirstChild("ActiveVehicles")
        if vehicles then
            for _, vehicle in ipairs(vehicles:GetChildren()) do
                if vehicle:IsA("Model") then
                    local part = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart")
                    if part then
                        local dist = (part.Position - root.Position).Magnitude
                        if dist <= settings.espMaxDist then
                            seen[vehicle] = true
                            if not espObjects[vehicle] then addEsp(vehicle, "truck", "[TRUCK] " .. vehicle.Name) end
                        end
                    end
                end
            end
        end

        for instance, entry in pairs(espObjects) do
            if entry.category == "truck" and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end

    local function refreshLuckyBlockEsp()
        if not settings.luckyBlockEsp then clearEsp("luckyBlock") return end
        local _, _, root = getCharacter()
        if not root then return end

        local seen = {}
        local blocks = workspace:FindFirstChild("ActiveWorldLuckyBlocks")
        if blocks then
            for _, block in ipairs(blocks:GetChildren()) do
                if block:IsA("Model") or block:IsA("BasePart") then
                    local part = block:IsA("BasePart") and block
                        or block.PrimaryPart or block:FindFirstChildWhichIsA("BasePart")
                    if part then
                        local dist = (part.Position - root.Position).Magnitude
                        if dist <= settings.espMaxDist then
                            seen[block] = true
                            if not espObjects[block] then addEsp(block, "luckyBlock", "[LUCKY] " .. block.Name) end
                        end
                    end
                end
            end
        end

        for instance, entry in pairs(espObjects) do
            if entry.category == "luckyBlock" and (not instance.Parent or not seen[instance]) then
                removeEsp(instance)
            end
        end
    end


    local function refreshConveyorEsp()
        if not settings.conveyorEsp then clearEsp("conveyor") return end
        local _, _, root = getCharacter()
        local plot = getMyPlot()
        if not root or not plot then return end
        local seen = {}
        local conveyors = plot:FindFirstChild("Conveyors")
        if conveyors then
            for _, conveyor in ipairs(conveyors:GetChildren()) do
                local part = conveyor:IsA("BasePart") and conveyor
                    or (conveyor:IsA("Model") and conveyor.PrimaryPart)
                    or conveyor:FindFirstChildWhichIsA("BasePart", true)
                if part and (part.Position - root.Position).Magnitude <= settings.espMaxDist then
                    seen[conveyor] = true
                    if not espObjects[conveyor] then addEsp(conveyor, "conveyor", "[CONVEYOR] " .. conveyor.Name) end
                end
            end
        end
        for instance, entry in pairs(espObjects) do
            if entry.category == "conveyor" and (not instance.Parent or not seen[instance]) then removeEsp(instance) end
        end
    end

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
        local collectAt = 0
        local workerAt = 0
        local upgradeAt = 0
        local scannerAt = 0
        local rewardAt = 0
        local depositAt = 0
        local rebirthAt = 0
        local leaveRewardAt = 0
        local espAt = 0
        local statusAt = 0

        while running do
            local iterOk, iterErr = xpcall(function()
                local now = os.clock()

                -- Auto Collect Boxes
                if settings.autoCollectBoxes and now - collectAt >= settings.collectInterval then
                    collectAt = now
                    performAutoCollect()
                end

                -- Auto Deposit
                if settings.autoDeposit and now - depositAt >= settings.collectInterval * 2 then
                    depositAt = now
                    performAutoDeposit()
                end

                -- Workers
                if (settings.autoHireWorker or settings.autoWakeWorker or settings.autoAssignZone)
                    and now - workerAt >= settings.workerInterval then
                    workerAt = now
                    performAutoHireWorker()
                    performAutoWakeWorker()
                    performAutoAssignZone()
                end

                -- Upgrades
                if (settings.autoUpgrade or settings.autoUnlockConveyor
                    or settings.autoUnlockFloor or settings.autoUnlockParking)
                    and now - upgradeAt >= settings.upgradeInterval then
                    upgradeAt = now
                    performAutoUpgrade()
                    performAutoUnlockConveyor()
                    performAutoUnlockFloor()
                    performAutoUnlockParking()
                end

                -- Scanner
                if (settings.autoScan or settings.autoUpgradeScanner or settings.autoUnlockScanner)
                    and now - scannerAt >= settings.scannerInterval then
                    scannerAt = now
                    performAutoScan()
                    performAutoUpgradeScanner()
                    performAutoUnlockScanner()
                end

                -- Rewards
                if (settings.autoClaimDaily or settings.autoClaimFree
                    or settings.autoClaimGroup or settings.autoOpenLuckyBlock
                    or settings.autoTrashBoxes)
                    and now - rewardAt >= settings.rewardInterval then
                    rewardAt = now
                    performAutoRewards()
                end

                -- Auto Rebirth
                if settings.autoRebirth and now - rebirthAt >= settings.rewardInterval then
                    rebirthAt = now
                    performAutoRebirth()
                end

                -- Auto Leave Reward (separate timer)
                if settings.autoClaimLeave and now - leaveRewardAt >= settings.rewardInterval then
                    leaveRewardAt = now
                    fireRemote(CheckLeaveReward, {})
                    fireRemote(ClaimLeaveReward, {})
                end

                -- ESP Refresh
                if (settings.workerEsp or settings.truckEsp or settings.luckyBlockEsp or settings.conveyorEsp)
                    and now - espAt >= 1.5 then
                    espAt = now
                    refreshWorkerEsp()
                    refreshTruckEsp()
                    refreshLuckyBlockEsp()
                    refreshConveyorEsp()
                end

                -- Status Update
                if now - statusAt >= 1 then
                    statusAt = now
                    local cash = getCash()
                    local rebirths = getRebirthCount()
                    local boxes = getBoxCount()
                    local workers = getWorkerCount()
                    local trucks = getTruckCount()
                    local managers = getManagerCount()

                    pcall(function()
                        statusLabel:Set(string.format(
                            "Cash: $%s | Rebirths: %d | Boxes: %d",
                            tostring(cash), rebirths, boxes
                        ))
                    end)

                    pcall(function()
                        workerLabel:Set(string.format(
                            "Workers: %d | Managers: %d",
                            workers, managers
                        ))
                    end)

                    pcall(function()
                        truckLabel:Set(string.format(
                            "Trucks/Vehicles: %d",
                            trucks
                        ))
                    end)

                    -- Reward status
                    local rewardParts = {}
                    if settings.autoClaimDaily then table.insert(rewardParts, "Daily") end
                    if settings.autoClaimFree then table.insert(rewardParts, "Free") end
                    if settings.autoClaimGroup then table.insert(rewardParts, "Group") end
                    if settings.autoOpenLuckyBlock then table.insert(rewardParts, "Lucky") end
                    if settings.autoRebirth then table.insert(rewardParts, "Rebirth") end
                    pcall(function()
                        rewardStatus:Set(string.format(
                            "Active: %s | Workers: %d | Trucks: %d",
                            #rewardParts > 0 and table.concat(rewardParts, ", ") or "none",
                            workers, trucks
                        ))
                    end)

                    -- Upgrade status
                    local upgParts = {}
                    if settings.autoUpgrade then table.insert(upgParts, "Upgrade") end
                    if settings.autoUnlockConveyor then table.insert(upgParts, "Conveyor") end
                    if settings.autoUnlockFloor then table.insert(upgParts, "Floor") end
                    if settings.autoUnlockParking then table.insert(upgParts, "Parking") end
                    pcall(function()
                        upgradeStatus:Set(string.format(
                            "Active: %s",
                            #upgParts > 0 and table.concat(upgParts, ", ") or "none"
                        ))
                    end)

                    -- Scanner status
                    local scanParts = {}
                    if settings.autoScan then table.insert(scanParts, "Scan") end
                    if settings.autoUpgradeScanner then table.insert(scanParts, "Upgrade") end
                    if settings.autoUnlockScanner then table.insert(scanParts, "Unlock") end
                    pcall(function()
                        scannerStatus:Set(string.format(
                            "Active: %s",
                            #scanParts > 0 and table.concat(scanParts, ", ") or "none"
                        ))
                    end)

                    -- Box status
                    pcall(function()
                        boxStatus:Set(string.format(
                            "Boxes: %d | Collected: %d | Auto: %s",
                            boxes, totalCollected,
                            settings.autoCollectBoxes and "ON" or "OFF"
                        ))
                    end)
                end

            end, function(msg)
                return debug.traceback(tostring(msg), 2)
            end)

            if not iterOk then
                warn("[RAVEN HUB][📦 Load The Truck] loop error: " .. tostring(iterErr))
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
        if environment.__RAVEN_LOAD_TRUCK
            and environment.__RAVEN_LOAD_TRUCK.Settings == settings then
            environment.__RAVEN_LOAD_TRUCK = nil
        end
    end

    environment.__RAVEN_LOAD_TRUCK = {
        Version = "v1.0.3",
        Settings = settings,
        Destroy = destroy,
        TeleportTo = teleportTo,
        GetCash = getCash,
        GetRebirthCount = getRebirthCount,
        GetWorkerCount = getWorkerCount,
        GetTruckCount = getTruckCount,
        GetBoxCount = getBoxCount,
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    notify("📦 Load The Truck", "v1.0.3 loaded — remotes fixed and repeated calls reduced")
end
