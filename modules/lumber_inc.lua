--[[
    RAVEN HUB | Lumber INC.
    PlaceId: 3344967357 | GameId: 1200145783
    Version: v1.0.0

    Features:
    🪓 Smart Auto Chop & Aura Farm
    🌲 Wood Type & Minimum Price Value Filter ($100 - $600)
    🪵 Auto Deliver Logs to Sawmill Intake
    🚛 Infinite Nitro & Vehicle Auto Flip Mod
    👁️ 100% Drawing API Tree & Log ESP with Rarity Colors
    📍 Precision Teleports to all POIs & Biomes
    🏃 Player Utilities (WalkSpeed, Noclip, Anti-Poison, Instant Prompt)
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")

    local player = Players.LocalPlayer
    local env = (type(getgenv) == "function" and getgenv()) or _G

    -- Teardown old session if re-executing
    if type(env.__RAVEN_LUMBER_INC) == "table" and type(env.__RAVEN_LUMBER_INC.Destroy) == "function" then
        pcall(env.__RAVEN_LUMBER_INC.Destroy)
        env.__RAVEN_LUMBER_INC = nil
    end

    local running = true
    local connections = {}
    local drawingCache = {}

    -- Configuration Settings
    local settings = {
        -- Farm
        autoChop = false,
        instantChop = true, -- Fast/Instant server tick rate
        chopMode = "Teleport", -- "Teleport" or "Aura (In-Place)"
        autoEquipAxe = true,
        minWoodPrice = 140,
        targetWoodType = "All Trees",
        chopDelay = 0.05, -- Instant swing rate
        breakLumber = true,
        autoDeliverLogs = false,
        deliverInterval = 3,

        -- Vehicles
        infiniteNitro = false,
        autoFlipVehicle = false,

        -- Player & World
        walkSpeed = 16,
        walkSpeedEnabled = false,
        infiniteJump = false,
        noclip = false,
        antiPoison = true,
        instantPrompt = true,
        autoPaycheque = true,

        -- Visuals
        treeEsp = false,
        treeEspMaxDist = 450,
        treeEspFilterMode = "All Trees", -- "All Trees", "👑 Maximum Price Only ($580 - $600)", "⭐ High Tier ($400+)", "Custom Min Price Slider"
        treeEspMinPrice = 140,
        highlightMaxTree = true,
        logEsp = false,
        logEspMaxDist = 250,
        poiEsp = true,
    }

    local liveStats = {
        currentTarget = "None",
        targetHp = "0 / 0",
        woodPrice = "$0",
        treesCut = 0,
        logsDelivered = 0,
    }

    -- References
    local map = Workspace:WaitForChild("Map")
    local forest = map:WaitForChild("Forest")
    local logsFolder = map:WaitForChild("Logs")
    local lumberFolder = map:FindFirstChild("Lumber")
    local sawmill = map:FindFirstChild("SawMill")
    local logIntake = sawmill and (sawmill:FindFirstChild("LogIntake") or sawmill:FindFirstChild("Parts"))
    local INTAKE_DEFAULT_POS = Vector3.new(-196.9, 29.2, 0.9)
    local currentCamera = Workspace.CurrentCamera

    -- Networking remotes resolver
    local netRemotes = {}
    pcall(function()
        local pgui = player:FindFirstChild("PlayerGui")
        local main = pgui and pgui:FindFirstChild("Main")
        local garage = main and main:FindFirstChild("Garage")
        local gc = garage and garage:FindFirstChild("GarageClient")
        if gc then
            local m = require(gc)
            if m and m.libs and m.libs.Networking and m.libs.Networking.Remotes then
                netRemotes = m.libs.Networking.Remotes.list or {}
            end
        end
    end)

    -- Wood Color Palette by Value
    local WOOD_COLORS = {
        ["Jacaranda"]   = Color3.fromRGB(255, 60, 220),   -- $580 Legendary
        ["Pine"]        = Color3.fromRGB(60, 230, 255),   -- $600 High tier
        ["Osakazuki"]   = Color3.fromRGB(255, 75, 75),    -- $400 High tier
        ["Ash"]         = Color3.fromRGB(255, 170, 50),   -- $310 Mid tier
        ["Amur Cork"]   = Color3.fromRGB(240, 230, 70),   -- $290 Mid tier
        ["Sakura"]      = Color3.fromRGB(255, 180, 210),  -- $260 Mid tier
        ["Piney"]       = Color3.fromRGB(100, 220, 140),  -- $250 Common
        ["Birch"]       = Color3.fromRGB(220, 240, 255),  -- $200 Common
        ["Shumard oak"] = Color3.fromRGB(180, 140, 90),   -- $190 Common
        ["Oak"]         = Color3.fromRGB(160, 200, 110),  -- $140 Starter
    }

    -- POI Coordinates
    local POI_LOCATIONS = {
        ["Sawmill Log Intake"] = Vector3.new(-196.9, 29.2, 0.9),
        ["Sawmill Main"]       = Vector3.new(-150.0, 24.5, 2.0),
        ["Train Station"]      = Vector3.new(-169.1, 29.1, 517.2),
        ["Vehicle Dealership"] = Vector3.new(414.6, 23.0, -37.3),
        ["Steel Axe Store"]    = Vector3.new(-409.3, 212.0, -1608.9),
        ["Trailer Store 24H"]  = Vector3.new(383.9, 23.5, 1198.6),
        ["Pallet Factory"]     = Vector3.new(64.4, 23.5, 1179.4),
        ["Hollow Tree"]        = Vector3.new(175.6, 27.7, 257.1),
        ["Spawn Point"]        = Vector3.new(336.2, 25.0, 73.3),
    }

    -- Biome Locations
    local BIOME_LOCATIONS = {
        ["Autumn Biome"]    = Vector3.new(-2179.1, 423.0, -1770.9),
        ["Osakazuki Biome"] = Vector3.new(-1752.1, 457.3, -823.8),
        ["Valley Biome"]    = Vector3.new(-1085.7, 25.0, -1925.3),
        ["Cave Swamp"]      = Vector3.new(-2385.9, 90.7, -2215.9),
    }

    -- Helper Utilities
    local function getCharacter()
        return player.Character or player.CharacterAdded:Wait()
    end

    local function getRootPart()
        local char = getCharacter()
        return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    end

    local function getEquippedAxe()
        local char = player.Character
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and item:FindFirstChild("SetActive") and item:FindFirstChild("SetTarget") then
                    return item
                end
            end
        end
        return nil
    end

    local function equipBestAxe()
        local char = player.Character
        local backpack = player:FindFirstChild("Backpack")
        if not char or not backpack then return nil end

        local equipped = getEquippedAxe()
        if equipped then return equipped end

        local bestTool = nil
        local maxDamage = -1

        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") and tool:FindFirstChild("SetActive") and tool:FindFirstChild("SetTarget") then
                local dmg = tool:GetAttribute("Damage") or 1
                if dmg > maxDamage then
                    maxDamage = dmg
                    bestTool = tool
                end
            end
        end

        if bestTool and char:FindFirstChildOfClass("Humanoid") then
            char.Humanoid:EquipTool(bestTool)
            task.wait(0.15)
            return bestTool
        end
        return nil
    end

    local function safeTeleport(targetPos)
        local root = getRootPart()
        if not root then return false end
        root.CFrame = CFrame.new(targetPos)
        return true
    end

    -- Vehicle & Log Selling Helpers
    local function getMySpawnedVehicle()
        local vehs = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Vehicles")
        if not vehs then return nil end
        local myIdStr = tostring(player.UserId)
        local myName = player.Name
        for _, v in ipairs(vehs:GetChildren()) do
            local owner = tostring(v:GetAttribute("Owner"))
            if owner == myIdStr or owner == myName then
                return v
            end
        end
        return nil
    end

    local function spawnTruck(vehId)
        vehId = vehId or 10
        local vSpawn = netRemotes["VehicleSpawn"]
        if vSpawn then
            local success, res = pcall(function()
                return vSpawn:InvokeServer(tonumber(vehId))
            end)
            return success and (res == true or res == "true")
        end
        return false
    end

    local function enterMyVehicleSeat()
        local veh = getMySpawnedVehicle()
        if not veh then
            spawnTruck(10)
            task.wait(0.25)
            veh = getMySpawnedVehicle()
        end
        if not veh then return false end
        local seat = veh:FindFirstChildWhichIsA("VehicleSeat", true)
        local root = getRootPart()
        if seat and root then
            root.CFrame = seat.CFrame + Vector3.new(0, 1.5, 0)
            return true
        end
        return false
    end

    local function bringVehicleToMe()
        local veh = getMySpawnedVehicle()
        if not veh then
            spawnTruck(10)
            task.wait(0.25)
            veh = getMySpawnedVehicle()
        end
        local root = getRootPart()
        if not veh or not root then return false end
        local seat = veh:FindFirstChildWhichIsA("VehicleSeat", true)
        local targetCF = root.CFrame * CFrame.new(0, 1, -10)
        if seat then
            local oldCF = root.CFrame
            root.CFrame = seat.CFrame + Vector3.new(0, 1, 0)
            task.wait(0.15)
            veh:PivotTo(targetCF)
            task.wait(0.1)
            root.CFrame = oldCF
            return true
        else
            veh:PivotTo(targetCF)
            return true
        end
    end

    local function teleportTruckToSawmill()
        local veh = getMySpawnedVehicle()
        if not veh then return false end
        local seat = veh:FindFirstChildWhichIsA("VehicleSeat", true)
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = getRootPart()
        local dropOffPos = Vector3.new(-180, 27, 10)
        if seat and hum and root then
            if not hum.Sit or hum.SeatPart ~= seat then
                root.CFrame = seat.CFrame + Vector3.new(0, 1.5, 0)
                task.wait(0.2)
            end
            veh:PivotTo(CFrame.new(dropOffPos))
            return true
        end
        return false
    end

    local function deliverLogToSawmill(log)
        if not log or not log:IsA("BasePart") or not log.Parent then return false end
        local candrag = netRemotes["Candrag"]
        if not candrag then return false end
        local root = getRootPart()
        if not root then return false end

        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then hum:UnequipTools() end

        local oldCF = root.CFrame
        local targetIntakePos = (logIntake and logIntake:IsA("BasePart") and logIntake.Position) or INTAKE_DEFAULT_POS
        local intakePos = targetIntakePos + Vector3.new(0, 3, 0)

        -- 1. Teleport near log to satisfy server proximity check
        root.CFrame = CFrame.new(log.Position + Vector3.new(0, 3, 0))
        task.wait(0.08)

        -- 2. Claim drag ownership
        local claimOk = false
        pcall(function()
            claimOk = candrag:InvokeServer(log, true)
        end)

        if claimOk then
            -- 3. Teleport into intake with the log
            root.CFrame = CFrame.new(intakePos + Vector3.new(0, 2, 0))
            log.CFrame = CFrame.new(intakePos)
            log.Velocity = Vector3.new(0, -10, 0)
            task.wait(0.12)

            -- 4. Release drag to let Sawmill conveyor consume it
            pcall(function()
                candrag:InvokeServer(log, false)
            end)
            liveStats.logsDelivered = liveStats.logsDelivered + 1
            task.wait(0.08)
        end

        -- 5. Return player
        root.CFrame = oldCF
        return claimOk
    end

    local function sellAllOwnedLogs()
        local myName = player.Name
        local count = 0
        for _, log in ipairs(logsFolder:GetChildren()) do
            if log:IsA("BasePart") then
                local cutted = log:GetAttribute("Cutted")
                local dragged = log:GetAttribute("Dragged")
                local hauled = log:GetAttribute("Hauled")
                if cutted == myName or dragged == myName or hauled == myName then
                    local ok = deliverLogToSawmill(log)
                    if ok then
                        count = count + 1
                        task.wait(0.12)
                    end
                end
            end
        end
        return count
    end

    local function loadLogsIntoTruckBed()
        local veh = getMySpawnedVehicle()
        if not veh then return 0 end
        local bedPos = veh:GetPivot().Position + Vector3.new(0, 3, 4)
        local myName = player.Name
        local candrag = netRemotes["Candrag"]
        local loaded = 0
        local root = getRootPart()
        if not root or not candrag then return 0 end

        for _, log in ipairs(logsFolder:GetChildren()) do
            if log:IsA("BasePart") then
                local cutted = log:GetAttribute("Cutted")
                local dragged = log:GetAttribute("Dragged")
                if cutted == myName or dragged == myName then
                    local oldCF = root.CFrame
                    root.CFrame = CFrame.new(log.Position + Vector3.new(0, 3, 0))
                    task.wait(0.08)
                    pcall(function() candrag:InvokeServer(log, true) end)
                    log.CFrame = CFrame.new(bedPos + Vector3.new(math.random(-1, 1), loaded * 0.8, math.random(-1, 1)))
                    task.wait(0.1)
                    pcall(function() candrag:InvokeServer(log, false) end)
                    loaded = loaded + 1
                    root.CFrame = oldCF
                    task.wait(0.1)
                end
            end
        end
        return loaded
    end

    -- Tree Targeting Helper
    local function getTreePrimary(tree)
        if not tree then return nil end
        if tree.PrimaryPart then return tree.PrimaryPart end
        local trunks = tree:FindFirstChild("Trunks")
        if trunks then
            for _, part in ipairs(trunks:GetChildren()) do
                if part:IsA("BasePart") then return part end
            end
        end
        for _, descendant in ipairs(tree:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Name:find("Trunk") then
                return descendant
            end
        end
        return nil
    end

    local function findHighestPriceTree()
        local trees = forest:GetChildren()
        local maxPrice = -1
        local highestTree = nil
        local highestPart = nil

        for _, tree in ipairs(trees) do
            local hp = tree:GetAttribute("Health") or 0
            if hp > 0 then
                local price = tree:GetAttribute("DefaultPrice") or 0
                if price > maxPrice then
                    local part = getTreePrimary(tree)
                    if part then
                        maxPrice = price
                        highestTree = tree
                        highestPart = part
                    end
                end
            end
        end
        return highestTree, highestPart, maxPrice
    end

    local function findBestTree()
        local root = getRootPart()
        if not root then return nil, nil end

        local trees = forest:GetChildren()
        local bestTree = nil
        local bestPart = nil
        local bestScore = -math.huge
        local myPos = root.Position

        for _, tree in ipairs(trees) do
            local hp = tree:GetAttribute("Health") or 0
            if hp > 0 then
                local price = tree:GetAttribute("DefaultPrice") or 0
                local name = tree.Name

                local matchesType = false
                if settings.targetWoodType == "All Trees" then
                    matchesType = true
                elseif settings.targetWoodType == "👑 Maximum Price Only ($580 - $600)" then
                    matchesType = (price >= 580)
                elseif settings.targetWoodType == "⭐ High Tier ($400+)" then
                    matchesType = (price >= 400)
                else
                    matchesType = (settings.targetWoodType == name)
                end

                local matchesPrice = (price >= settings.minWoodPrice)

                if matchesType and matchesPrice then
                    local part = getTreePrimary(tree)
                    if part then
                        local dist = (part.Position - myPos).Magnitude
                        -- In Aura mode, strictly check distance <= 18 studs
                        if settings.chopMode == "Aura (In-Place)" and dist > 18 then
                            continue
                        end

                        -- Score formula: prioritize value heavily, then proximity
                        local score = (price * 3) - (dist * 0.3)
                        if score > bestScore then
                            bestScore = score
                            bestTree = tree
                            bestPart = part
                        end
                    end
                end
            end
        end

        return bestTree, bestPart
    end

    -- ============================================================
    --   BACKGROUND LOOPS
    -- ============================================================

    -- UserInputHandler GetHit Hook for 100% Autonomous Aimlock (No mouse hovering needed)
    local activeTargetPart = nil
    local originalGetHit = nil
    local uihInstance = nil

    pcall(function()
        local pgui = player:FindFirstChild("PlayerGui")
        local main = pgui and pgui:FindFirstChild("Main")
        local chopMod = main and main:FindFirstChild("TreeChopping") and main.TreeChopping:FindFirstChild("ChopTool")
        if chopMod then
            local chopLib = require(chopMod)
            if chopLib and chopLib.libs and chopLib.libs.UserInputHandler then
                uihInstance = chopLib.libs.UserInputHandler
                originalGetHit = uihInstance.GetHit
                uihInstance.GetHit = function(rayParams, screenPos)
                    if settings.autoChop and activeTargetPart and activeTargetPart.Parent then
                        return activeTargetPart, CFrame.new(activeTargetPart.Position), Vector3.new(0, 1, 0)
                    end
                    if originalGetHit then
                        return originalGetHit(rayParams, screenPos)
                    end
                    return nil, nil, nil
                end
            end
        end
    end)

    -- 1. Auto Chop & Continuous Fast Felling Loop
    task.spawn(function()
        local currentLockedTree = nil
        local currentLockedPart = nil

        while running do
            if settings.autoChop then
                local axe = getEquippedAxe()
                if not axe and settings.autoEquipAxe then
                    axe = equipBestAxe()
                end

                if axe then
                    -- Check if existing locked target is still valid and alive
                    local stillValid = false
                    if currentLockedTree and currentLockedTree.Parent and currentLockedTree:IsDescendantOf(forest) then
                        local hp = currentLockedTree:GetAttribute("Health") or 0
                        if hp > 0 and currentLockedPart and currentLockedPart.Parent then
                            stillValid = true
                        end
                    end

                    -- If previous tree fell or is invalid, clean up and pick new target
                    if not stillValid then
                        if currentLockedTree then
                            local setTarget = axe:FindFirstChild("SetTarget")
                            local setActive = axe:FindFirstChild("SetActive")
                            if setActive then pcall(function() setActive:FireServer(false) end) end
                            if setTarget then pcall(function() setTarget:InvokeServer(nil) end) end
                            liveStats.treesCut = liveStats.treesCut + 1
                            currentLockedTree = nil
                            currentLockedPart = nil
                            activeTargetPart = nil
                        end

                        currentLockedTree, currentLockedPart = findBestTree()
                    end

                    if currentLockedTree and currentLockedPart then
                        local root = getRootPart()
                        if root then
                            activeTargetPart = currentLockedPart
                            local hp = currentLockedTree:GetAttribute("Health") or 0
                            local maxHp = currentLockedTree:GetAttribute("MaxHealth") or hp
                            local price = currentLockedTree:GetAttribute("DefaultPrice") or 0
                            liveStats.currentTarget = currentLockedTree.Name
                            liveStats.targetHp = string.format("%d / %d", math.ceil(hp), maxHp)
                            liveStats.woodPrice = "$" .. tostring(price)

                            local setTarget = axe:FindFirstChild("SetTarget")
                            local setActive = axe:FindFirstChild("SetActive")

                            if setTarget and setActive then
                                -- Proximity Ground Raycasting Stance
                                local trunkPos = currentLockedPart.Position
                                if settings.chopMode == "Teleport" then
                                    local rayOrigin = trunkPos + Vector3.new(2.8, 6, 2.8)
                                    local rayRes = Workspace:Raycast(rayOrigin, Vector3.new(0, -25, 0))
                                    local groundY = rayRes and (rayRes.Position.Y + 3.0) or (trunkPos.Y + 0.5)
                                    local standPos = Vector3.new(trunkPos.X + 2.8, groundY, trunkPos.Z + 2.8)
                                    root.CFrame = CFrame.new(standPos, trunkPos)
                                end

                                -- Lock target directly (1 argument)
                                pcall(function()
                                    setTarget:InvokeServer(currentLockedPart)
                                    setActive:FireServer(true)
                                end)

                                -- Instant Chop mode: triggers tool activation & fast frame loops
                                if settings.instantChop then
                                    pcall(function()
                                        axe:Activate()
                                    end)
                                    task.wait(settings.chopDelay)
                                else
                                    task.wait(settings.chopDelay)
                                end
                            end
                        end
                    else
                        activeTargetPart = nil
                        liveStats.currentTarget = "Searching..."
                        task.wait(0.3)
                    end
                else
                    activeTargetPart = nil
                    liveStats.currentTarget = "No Axe Equipped"
                    task.wait(0.4)
                end
            else
                if currentLockedTree then
                    local axe = getEquippedAxe()
                    if axe then
                        local setTarget = axe:FindFirstChild("SetTarget")
                        local setActive = axe:FindFirstChild("SetActive")
                        if setActive then pcall(function() setActive:FireServer(false) end) end
                        if setTarget then pcall(function() setTarget:InvokeServer(nil) end) end
                    end
                    currentLockedTree = nil
                    currentLockedPart = nil
                    activeTargetPart = nil
                end
                task.wait(0.2)
            end
        end
    end)

    -- 2. Auto Deliver Logs to Sawmill Intake
    task.spawn(function()
        while running do
            if settings.autoDeliverLogs then
                local logs = logsFolder:GetChildren()
                local myName = player.Name
                for _, log in ipairs(logs) do
                    if not running or not settings.autoDeliverLogs then break end
                    if log:IsA("BasePart") then
                        local cutted = log:GetAttribute("Cutted")
                        local dragged = log:GetAttribute("Dragged")
                        local hauled = log:GetAttribute("Hauled")
                        if cutted == myName or dragged == myName or hauled == myName then
                            local ok = deliverLogToSawmill(log)
                            if ok then
                                task.wait(settings.deliverInterval)
                            end
                        end
                    end
                end
                task.wait(1.5)
            else
                task.wait(0.5)
            end
        end
    end)

    -- 3. Vehicle & Nitro Mod Loop
    task.spawn(function()
        while running do
            if settings.infiniteNitro then
                pcall(function()
                    player:SetAttribute("Nitro", 100)
                end)
            end

            if settings.autoFlipVehicle then
                local vContext = netRemotes["VehicleContext"]
                if vContext then
                    local char = player.Character
                    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
                    if humanoid and humanoid.Sit then
                        local seat = humanoid.SeatPart
                        if seat and seat:IsA("VehicleSeat") then
                            local upVector = seat.CFrame.UpVector
                            -- If tilted more than ~60 degrees upside down
                            if upVector.Y < 0.3 then
                                pcall(function()
                                    vContext:FireServer("Flip", true)
                                end)
                                task.wait(0.8)
                            end
                        end
                    end
                end
            end
            task.wait(0.2)
        end
    end)

    -- 4. Player Attribute & Environment Handlers
    task.spawn(function()
        while running do
            -- Anti-Poison: keep Poisoning attribute at 0
            if settings.antiPoison then
                pcall(function()
                    if player:GetAttribute("Poisoning") and player:GetAttribute("Poisoning") > 0 then
                        player:SetAttribute("Poisoning", 0)
                    end
                end)
            end

            -- Auto Paycheque: automatic earnings claim
            if settings.autoPaycheque then
                pcall(function()
                    if not player:GetAttribute("AutoPaycheque") then
                        player:SetAttribute("AutoPaycheque", true)
                    end
                end)
            end

            -- Instant ProximityPrompts
            if settings.instantPrompt then
                for _, prompt in ipairs(Workspace:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") and prompt.HoldDuration > 0 then
                        prompt.HoldDuration = 0
                    end
                end
            end

            -- WalkSpeed Enforcement
            if settings.walkSpeedEnabled then
                local char = player.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.WalkSpeed ~= settings.walkSpeed then
                    hum.WalkSpeed = settings.walkSpeed
                end
            end

            task.wait(0.4)
        end
    end)

    -- 5. Infinite Jump Connection
    table.insert(connections, UserInputService.JumpRequest:Connect(function()
        if settings.infiniteJump then
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end))

    -- 6. Noclip Connection
    table.insert(connections, RunService.Stepped:Connect(function()
        if settings.noclip then
            local char = player.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end
    end))

    -- ============================================================
    --   100% DRAWING API VISUALS & ESP
    -- ============================================================

    local function createDrawing(drawType, properties)
        if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then
            return nil
        end
        local obj = Drawing.new(drawType)
        for k, v in pairs(properties) do
            obj[k] = v
        end
        table.insert(drawingCache, obj)
        return obj
    end

    local treeDrawingMap = {}
    local logDrawingMap = {}
    local poiDrawingMap = {}

    -- POI Drawing markers
    for poiName, poiPos in pairs(POI_LOCATIONS) do
        local label = createDrawing("Text", {
            Text = "[POI] " .. poiName,
            Size = 13,
            Center = true,
            Outline = true,
            Color = Color3.fromRGB(255, 215, 0),
            Visible = false,
            ZIndex = 2,
        })
        poiDrawingMap[poiName] = { drawing = label, position = poiPos }
    end

    -- Render Loop for Drawing Visuals
    table.insert(connections, RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        local root = getRootPart()
        local myPos = root and root.Position or (cam and cam.CFrame.Position)

        -- 1. POI ESP
        for _, item in pairs(poiDrawingMap) do
            if settings.poiEsp and item.drawing then
                local screenPos, onScreen = cam:WorldToViewportPoint(item.position)
                if onScreen and screenPos.Z > 0 then
                    local dist = math.floor((item.position - myPos).Magnitude)
                    item.drawing.Position = Vector2.new(screenPos.X, screenPos.Y)
                    item.drawing.Text = string.format("%s\n[%dm]", item.drawing.Text:split("\n")[1], dist)
                    item.drawing.Visible = true
                else
                    item.drawing.Visible = false
                end
            elseif item.drawing then
                item.drawing.Visible = false
            end
        end

        -- 2. Tree ESP
        if settings.treeEsp then
            local trees = forest:GetChildren()
            local activeTrees = {}

            for _, tree in ipairs(trees) do
                local hp = tree:GetAttribute("Health") or 0
                if hp > 0 then
                    local part = getTreePrimary(tree)
                    if part then
                        local dist = (part.Position - myPos).Magnitude
                        if dist <= settings.treeEspMaxDist then
                            local price = tree:GetAttribute("DefaultPrice") or 0
                            local passFilter = true
                            if settings.treeEspFilterMode == "👑 Maximum Price Only ($580 - $600)" then
                                passFilter = (price >= 580)
                            elseif settings.treeEspFilterMode == "⭐ High Tier ($400+)" then
                                passFilter = (price >= 400)
                            elseif settings.treeEspFilterMode == "Custom Min Price Slider" then
                                passFilter = (price >= settings.treeEspMinPrice)
                            end

                            if passFilter then
                                activeTrees[tree] = true
                                local entry = treeDrawingMap[tree]
                                if not entry then
                                    entry = {
                                        label = createDrawing("Text", {
                                            Size = 13,
                                            Center = true,
                                            Outline = true,
                                            Visible = false,
                                            ZIndex = 3,
                                        }),
                                    }
                                    treeDrawingMap[tree] = entry
                                end

                                local screenPos, onScreen = cam:WorldToViewportPoint(part.Position + Vector3.new(0, 3, 0))
                                if onScreen and screenPos.Z > 0 then
                                    local maxHp = tree:GetAttribute("MaxHealth") or hp
                                    local col = WOOD_COLORS[tree.Name] or Color3.fromRGB(220, 220, 220)
                                    if price >= 580 then
                                        col = Color3.fromRGB(255, 215, 0)
                                        entry.label.Text = string.format("👑 %s [$%d - MAX PRICE] 👑\nHP: %d/%d [%dm]", tree.Name, price, math.ceil(hp), maxHp, math.floor(dist))
                                    elseif price >= 400 then
                                        entry.label.Text = string.format("⭐ %s [$%d]\nHP: %d/%d [%dm]", tree.Name, price, math.ceil(hp), maxHp, math.floor(dist))
                                    else
                                        entry.label.Text = string.format("🌲 %s [$%d]\nHP: %d/%d [%dm]", tree.Name, price, math.ceil(hp), maxHp, math.floor(dist))
                                    end
                                    entry.label.Color = col
                                    entry.label.Position = Vector2.new(screenPos.X, screenPos.Y)
                                    entry.label.Visible = true
                                else
                                    entry.label.Visible = false
                                end
                            end
                        end
                    end
                end
            end

            -- Clean up inactive trees
            for tree, entry in pairs(treeDrawingMap) do
                if not activeTrees[tree] then
                    if entry.label then entry.label.Visible = false end
                end
            end
        else
            for _, entry in pairs(treeDrawingMap) do
                if entry.label then entry.label.Visible = false end
            end
        end

        -- 3. Log ESP
        if settings.logEsp then
            local logs = logsFolder:GetChildren()
            local activeLogs = {}

            for _, log in ipairs(logs) do
                if log:IsA("BasePart") then
                    local dist = (log.Position - myPos).Magnitude
                    if dist <= settings.logEspMaxDist then
                        activeLogs[log] = true
                        local entry = logDrawingMap[log]
                        if not entry then
                            entry = {
                                label = createDrawing("Text", {
                                    Size = 12,
                                    Center = true,
                                    Outline = true,
                                    Color = Color3.fromRGB(210, 160, 100),
                                    Visible = false,
                                    ZIndex = 2,
                                }),
                            }
                            logDrawingMap[log] = entry
                        end

                        local screenPos, onScreen = cam:WorldToViewportPoint(log.Position)
                        if onScreen and screenPos.Z > 0 then
                            local price = log:GetAttribute("DefaultPrice") or 0
                            local weight = math.floor(log:GetAttribute("Weight") or 0)
                            entry.label.Position = Vector2.new(screenPos.X, screenPos.Y)
                            entry.label.Text = string.format("🪵 %s [$%d | %dlbs] [%dm]", log.Name, price, weight, math.floor(dist))
                            entry.label.Visible = true
                        else
                            entry.label.Visible = false
                        end
                    end
                end
            end

            for log, entry in pairs(logDrawingMap) do
                if not activeLogs[log] then
                    if entry.label then entry.label.Visible = false end
                end
            end
        else
            for _, entry in pairs(logDrawingMap) do
                if entry.label then entry.label.Visible = false end
            end
        end
    end))

    -- ============================================================
    --   BUILD USER INTERFACE (TABS & CONTROLS)
    -- ============================================================

    local ChopTab      = Window:CreateTab("Chop & Farm")
    local SawmillTab   = Window:CreateTab("Sawmill & Cargo")
    local VehiclesTab  = Window:CreateTab("Vehicles")
    local VisualsTab   = Window:CreateTab("Visuals & ESP")
    local WorldTab     = Window:CreateTab("Teleport & Misc")

    -- ------------------------------------------------------------
    -- [Dashboard & Quick Actions]
    -- ------------------------------------------------------------
    local statsSection = ChopTab:CreateSection("Live Farm Dashboard")
    local statsPara = statsSection:CreateParagraph({
        Title = "🌳 Lumber INC. Dashboard",
        Content = "Target: None\nTrees Harvested: 0\nLogs Delivered: 0\nCash: $0",
    })

    task.spawn(function()
        while running do
            local cash = player:GetAttribute("Cash") or 0
            local nitro = player:GetAttribute("Nitro") or 0
            statsPara:Set(string.format(
                "Target: %s (%s | %s)\nTrees Harvested: %d\nLogs Delivered: %d\nCash: $%s | Nitro: %d%%",
                liveStats.currentTarget,
                liveStats.targetHp,
                liveStats.woodPrice,
                liveStats.treesCut,
                liveStats.logsDelivered,
                tostring(cash),
                nitro
            ))
            task.wait(1)
        end
    end)

    local quickSection = ChopTab:CreateSection("Quick Actions")
    quickSection:CreateButton({
        Name = "💰 Sell All My Logs (Instant Tele-Sell)",
        Callback = function()
            task.spawn(function()
                local count = sellAllOwnedLogs()
                print(string.format("[Lumber INC] Delivered & sold %d logs to Sawmill!", count))
            end)
        end,
    })
    quickSection:CreateButton({
        Name = "🚚 Spawn My Truck (Timber Wolf)",
        Callback = function()
            local ok = spawnTruck(10)
            if ok then
                print("[Lumber INC] Timber Wolf spawned successfully!")
            end
        end,
    })
    quickSection:CreateButton({
        Name = "👑 Teleport to Highest Price Tree ($580-$600)",
        Callback = function()
            local tree, part, price = findHighestPriceTree()
            if part then
                safeTeleport(part.Position + Vector3.new(2.8, 3, 2.8))
                print(string.format("[Lumber INC] Teleported to highest price tree: %s ($%d)", tree and tree.Name or "Unknown", price or 0))
            end
        end,
    })
    quickSection:CreateButton({
        Name = "Equip Best Axe in Backpack",
        Callback = function()
            local axe = equipBestAxe()
            if axe then
                print("[Lumber INC] Equipped best axe: " .. axe.Name)
            end
        end,
    })
    quickSection:CreateButton({
        Name = "Teleport to Sawmill",
        Callback = function()
            safeTeleport(POI_LOCATIONS["Sawmill Main"])
        end,
    })
    quickSection:CreateButton({
        Name = "Teleport to Train Station",
        Callback = function()
            safeTeleport(POI_LOCATIONS["Train Station"])
        end,
    })

    -- ------------------------------------------------------------
    -- [Chop & Farm Settings]
    -- ------------------------------------------------------------
    local chopSection = ChopTab:CreateSection("Auto Tree Farm")
    chopSection:CreateToggle({
        Name = "Auto Chop Trees",
        CurrentValue = settings.autoChop,
        Callback = function(v)
            settings.autoChop = v
        end,
    })

    chopSection:CreateToggle({
        Name = "Instant Chop (Multi-Pulse Fast Break)",
        CurrentValue = settings.instantChop,
        Callback = function(v)
            settings.instantChop = v
        end,
    })

    chopSection:CreateDropdown({
        Name = "Chop Farming Mode",
        Options = {"Teleport", "Aura (In-Place)"},
        CurrentOption = {settings.chopMode},
        Callback = function(opt)
            settings.chopMode = type(opt) == "table" and opt[1] or opt
        end,
    })

    chopSection:CreateToggle({
        Name = "Auto Equip Axe",
        CurrentValue = settings.autoEquipAxe,
        Callback = function(v)
            settings.autoEquipAxe = v
        end,
    })

    chopSection:CreateSlider({
        Name = "Chop Swing Delay (s)",
        Range = {0.02, 0.4},
        Increment = 0.02,
        CurrentValue = settings.chopDelay,
        Callback = function(v)
            settings.chopDelay = v
        end,
    })

    local filterSection = ChopTab:CreateSection("Wood Value & Rarity Filters")
    filterSection:CreateSlider({
        Name = "Minimum Tree Price ($)",
        Range = {100, 600},
        Increment = 20,
        CurrentValue = settings.minWoodPrice,
        Callback = function(v)
            settings.minWoodPrice = v
        end,
    })

    filterSection:CreateDropdown({
        Name = "Target Tree Species",
        Options = {
            "All Trees",
            "👑 Maximum Price Only ($580 - $600)",
            "⭐ High Tier ($400+)",
            "Pine ($600)",
            "Jacaranda ($580)",
            "Osakazuki ($400)",
            "Ash ($310)",
            "Amur Cork ($290)",
            "Sakura ($260)",
            "Piney ($250)",
            "Birch ($200)",
            "Shumard oak ($190)",
            "Oak ($140)"
        },
        CurrentOption = {settings.targetWoodType},
        Callback = function(opt)
            settings.targetWoodType = type(opt) == "table" and opt[1] or opt
        end,
    })

    -- ------------------------------------------------------------
    -- [Sawmill & Cargo Tab]
    -- ------------------------------------------------------------
    local sawmillSection = SawmillTab:CreateSection("Log Tele-Sell (No Vehicle Needed)")
    sawmillSection:CreateToggle({
        Name = "Auto Tele-Sell Logs to Sawmill Intake",
        CurrentValue = settings.autoDeliverLogs,
        Callback = function(v)
            settings.autoDeliverLogs = v
        end,
    })

    sawmillSection:CreateButton({
        Name = "💰 Sell All My Logs Now (Instant Tele-Sell)",
        Callback = function()
            task.spawn(function()
                local count = sellAllOwnedLogs()
                print(string.format("[Lumber INC] Manually sold %d logs to Sawmill!", count))
            end)
        end,
    })

    sawmillSection:CreateSlider({
        Name = "Delivery Interval (Seconds)",
        Range = {1, 10},
        Increment = 1,
        CurrentValue = settings.deliverInterval,
        Callback = function(v)
            settings.deliverInterval = v
        end,
    })

    local chequeSection = SawmillTab:CreateSection("Income & Automation")
    chequeSection:CreateToggle({
        Name = "Auto Claim Paycheque",
        CurrentValue = settings.autoPaycheque,
        Callback = function(v)
            settings.autoPaycheque = v
            pcall(function() player:SetAttribute("AutoPaycheque", v) end)
        end,
    })

    chequeSection:CreateToggle({
        Name = "Instant ProximityPrompts (0s Hold)",
        CurrentValue = settings.instantPrompt,
        Callback = function(v)
            settings.instantPrompt = v
        end,
    })

    -- ------------------------------------------------------------
    -- [Vehicles Tab]
    -- ------------------------------------------------------------
    local vehSpawnSection = VehiclesTab:CreateSection("My Truck & Quick Spawner")
    vehSpawnSection:CreateButton({
        Name = "🚚 Spawn My Truck (Timber Wolf - Free Starter)",
        Callback = function()
            local ok = spawnTruck(10)
            if ok then
                print("[Lumber INC] Timber Wolf spawned successfully!")
            end
        end,
    })

    vehSpawnSection:CreateButton({
        Name = "🚗 Teleport into Driver's Seat",
        Callback = function()
            local ok = enterMyVehicleSeat()
            if ok then
                print("[Lumber INC] Teleported into driver seat!")
            end
        end,
    })

    vehSpawnSection:CreateButton({
        Name = "⚡ Spawn & Enter Truck Instantly",
        Callback = function()
            spawnTruck(10)
            task.wait(0.25)
            enterMyVehicleSeat()
        end,
    })

    vehSpawnSection:CreateButton({
        Name = "📍 Bring Truck to My Location",
        Callback = function()
            local ok = bringVehicleToMe()
            if ok then
                print("[Lumber INC] Brought truck to player!")
            end
        end,
    })

    vehSpawnSection:CreateButton({
        Name = "🏭 Teleport Truck to Sawmill Drop-off",
        Callback = function()
            local ok = teleportTruckToSawmill()
            if ok then
                print("[Lumber INC] Teleported truck to Sawmill!")
            end
        end,
    })

    vehSpawnSection:CreateButton({
        Name = "📦 Load My Logs into Truck Bed",
        Callback = function()
            task.spawn(function()
                local count = loadLogsIntoTruckBed()
                print(string.format("[Lumber INC] Loaded %d logs into truck bed!", count))
            end)
        end,
    })

    local dealershipSection = VehiclesTab:CreateSection("Dealership (1-Click Buy)")
    dealershipSection:CreateButton({
        Name = "🛒 Buy Brello (Forklift - $200)",
        Callback = function()
            local vPur = netRemotes["VehiclePurchase"]
            if vPur then
                local res = vPur:InvokeServer(20)
                print("[Lumber INC] Purchase Brello result: " .. tostring(res))
            end
        end,
    })

    dealershipSection:CreateButton({
        Name = "🛒 Buy Laiser (Scout - $550)",
        Callback = function()
            local vPur = netRemotes["VehiclePurchase"]
            if vPur then
                local res = vPur:InvokeServer(36)
                print("[Lumber INC] Purchase Laiser result: " .. tostring(res))
            end
        end,
    })

    dealershipSection:CreateButton({
        Name = "🛒 Buy Zazik (Scout - $899)",
        Callback = function()
            local vPur = netRemotes["VehiclePurchase"]
            if vPur then
                local res = vPur:InvokeServer(37)
                print("[Lumber INC] Purchase Zazik result: " .. tostring(res))
            end
        end,
    })

    local vehicleSection = VehiclesTab:CreateSection("Vehicle Enhancements & Physics")
    vehicleSection:CreateToggle({
        Name = "Infinite Nitro Boost",
        CurrentValue = settings.infiniteNitro,
        Callback = function(v)
            settings.infiniteNitro = v
        end,
    })

    vehicleSection:CreateToggle({
        Name = "Auto Flip Vehicle (Anti-Rollover)",
        CurrentValue = settings.autoFlipVehicle,
        Callback = function(v)
            settings.autoFlipVehicle = v
        end,
    })

    vehicleSection:CreateButton({
        Name = "Manual Flip Vehicle Now",
        Callback = function()
            local vContext = netRemotes["VehicleContext"]
            if vContext then
                pcall(function() vContext:FireServer("Flip", true) end)
            end
        end,
    })

    vehicleSection:CreateButton({
        Name = "Toggle Vehicle Lights",
        Callback = function()
            local vContext = netRemotes["VehicleContext"]
            if vContext then
                pcall(function() vContext:FireServer("Lights", true) end)
            end
        end,
    })

    -- ------------------------------------------------------------
    -- [Visuals Tab]
    -- ------------------------------------------------------------
    local visualSection = VisualsTab:CreateSection("Tree ESP & Max Price Filters")
    visualSection:CreateToggle({
        Name = "Tree ESP (Names, HP & Prices)",
        CurrentValue = settings.treeEsp,
        Callback = function(v)
            settings.treeEsp = v
        end,
    })

    visualSection:CreateDropdown({
        Name = "Tree Price Filter Mode",
        Options = {
            "All Trees",
            "👑 Maximum Price Only ($580 - $600)",
            "⭐ High Tier ($400+)",
            "Custom Min Price Slider"
        },
        CurrentOption = {settings.treeEspFilterMode},
        Callback = function(opt)
            settings.treeEspFilterMode = type(opt) == "table" and opt[1] or opt
        end,
    })

    visualSection:CreateSlider({
        Name = "Tree ESP Min Price ($)",
        Range = {100, 600},
        Increment = 20,
        CurrentValue = settings.treeEspMinPrice,
        Callback = function(v)
            settings.treeEspMinPrice = v
        end,
    })

    visualSection:CreateSlider({
        Name = "Tree ESP Max Distance",
        Range = {100, 1000},
        Increment = 50,
        CurrentValue = settings.treeEspMaxDist,
        Callback = function(v)
            settings.treeEspMaxDist = v
        end,
    })

    visualSection:CreateToggle({
        Name = "Log ESP (Fallen Wood on Ground)",
        CurrentValue = settings.logEsp,
        Callback = function(v)
            settings.logEsp = v
        end,
    })

    visualSection:CreateToggle({
        Name = "Points of Interest ESP (POIs)",
        CurrentValue = settings.poiEsp,
        Callback = function(v)
            settings.poiEsp = v
        end,
    })

    -- ------------------------------------------------------------
    -- [Teleport & Misc Tab]
    -- ------------------------------------------------------------
    local poiSection = WorldTab:CreateSection("Map Teleports")
    for name, pos in pairs(POI_LOCATIONS) do
        poiSection:CreateButton({
            Name = "Teleport: " .. name,
            Callback = function()
                safeTeleport(pos + Vector3.new(0, 3, 0))
            end,
        })
    end

    local biomeSection = WorldTab:CreateSection("Biome Teleports")
    for name, pos in pairs(BIOME_LOCATIONS) do
        biomeSection:CreateButton({
            Name = "Teleport: " .. name,
            Callback = function()
                safeTeleport(pos + Vector3.new(0, 3, 0))
            end,
        })
    end

    local utilSection = WorldTab:CreateSection("Player Utilities")
    utilSection:CreateToggle({
        Name = "WalkSpeed Multiplier",
        CurrentValue = settings.walkSpeedEnabled,
        Callback = function(v)
            settings.walkSpeedEnabled = v
            if not v then
                local char = player.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = 16 end
            end
        end,
    })

    utilSection:CreateSlider({
        Name = "WalkSpeed Value",
        Range = {16, 120},
        Increment = 4,
        CurrentValue = settings.walkSpeed,
        Callback = function(v)
            settings.walkSpeed = v
        end,
    })

    utilSection:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = settings.infiniteJump,
        Callback = function(v)
            settings.infiniteJump = v
        end,
    })

    utilSection:CreateToggle({
        Name = "Noclip",
        CurrentValue = settings.noclip,
        Callback = function(v)
            settings.noclip = v
        end,
    })

    utilSection:CreateToggle({
        Name = "Anti-Poison (Swamp Hazard Immune)",
        CurrentValue = settings.antiPoison,
        Callback = function(v)
            settings.antiPoison = v
        end,
    })

    -- Sort tabs cleanly
    if type(Window.SortTabs) == "function" then
        Window:SortTabs({
            "Overview",
            "Chop & Farm",
            "Sawmill & Cargo",
            "Vehicles",
            "Visuals & ESP",
            "Teleport & Misc",
            "Settings",
        })
    end

    -- Cleanup object on reload
    local cleanupObj = {
        Destroy = function()
            running = false
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            for _, draw in ipairs(drawingCache) do
                pcall(function()
                    draw.Visible = false
                    draw:Remove()
                end)
            end
            local char = player.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = 16
            end
            if uihInstance and originalGetHit then
                uihInstance.GetHit = originalGetHit
            end
        end
    }

    env.__RAVEN_LUMBER_INC = cleanupObj
    return cleanupObj
end
