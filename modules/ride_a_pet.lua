--[[
    RAVEN HUB Module - Ride A Pet v1.1.0
    Game: Ride A Pet (PlaceId: 124216119978534 / GameId: 10035204815)
    Developer: this game is gud

    v1.1.0:
    - Fixed "Can't Teleport While Carrying Eggs" anti-cheat kick
    - Replaced instant teleport with 100% safe Glide Fly (TweenService)
    - Removed TeleportToPlot remote during egg transport
    - Safe arrival delay for server position replication


    Features:
    - 🥚 Egg Sniper / Auto Farm:
      * Live scanner connected directly to ReplicatedStorage.ServerData.ActiveEggs
      * Filter by Tier (Divine, Ethereal, Mythic, Legendary, Epic, Rare, Common)
      * Priority sorting (Rarest First or Closest First)
      * Instant TP or Smooth Tween movement
      * Auto basket capacity management
    - 🐣 Plot & Nest Automation:
      * Auto deposit eggs to available nests
      * Auto claim / pet management
    - 🐾 Progression & Economy:
      * Auto Rebirth
      * Auto Claim Index Rewards
      * Auto Feed Pets
    - 👁️ Visuals:
      * 100% Drawing API Egg ESP & Tracers (Color-coded by rarity)
      * Rarity filter & distance limit
    - ⚡ Teleports & Movement:
      * Instant TP to Player Plot
      * Live list of rare eggs in server with 1-click TP
      * Speed Boost, Infinite Jump, Noclip, Anti-AFK
]]--

return function(Window, runtimeInfo)
    pcall(function()
        local prev = getgenv().__RAVEN_RIDE_A_PET
        if prev and type(prev.Destroy) == "function" then
            prev.Destroy()
        end
    end)

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TeleportService = game:GetService("TeleportService")
    local UserInputService = game:GetService("UserInputService")
    local VirtualUser = game:GetService("VirtualUser")

    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    ----------------------------------------------------------------
    --  TIER & RARITY DATA
    ----------------------------------------------------------------
    local EGG_TIERS = {
        ["Galaxy Egg"] = "Divine",
        ["Aurora Egg"] = "Divine",
        ["Blackhole Egg"] = "Ethereal",
        ["Dragon Egg"] = "Ethereal",
        ["Giant Egg"] = "Ethereal",
        ["Cherub Egg"] = "Ethereal",
        ["Dominus Egg"] = "Mythic",
        ["Asteroid Egg"] = "Mythic",
        ["Diamond Egg"] = "Mythic",
        ["Crystal Egg"] = "Mythic",
        ["Soul Egg"] = "Mythic",
        ["Sinister Egg"] = "Mythic",
        ["Skull Egg"] = "Mythic",
        ["Flaming Egg"] = "Mythic",
        ["Golden Egg"] = "Legendary",
        ["Glass Egg"] = "Legendary",
        ["Slime Egg"] = "Epic",
        ["Flower Egg"] = "Epic",
        ["Ice Egg"] = "Epic",
        ["Mushroom Egg"] = "Epic",
        ["Leaf Egg"] = "Rare",
        ["Cracked Egg"] = "Rare",
        ["Stone Egg"] = "Rare",
        ["Easter Egg"] = "Rare",
        ["White Egg"] = "Common",
        ["Brown Egg"] = "Common",
    }

    local TIER_RANK = {
        Divine = 7,
        Ethereal = 6,
        Mythic = 5,
        Legendary = 4,
        Epic = 3,
        Rare = 2,
        Common = 1,
        Unknown = 0,
    }

    local TIER_COLORS = {
        Divine = Color3.fromRGB(0, 255, 255),
        Ethereal = Color3.fromRGB(255, 0, 255),
        Mythic = Color3.fromRGB(255, 50, 50),
        Legendary = Color3.fromRGB(255, 215, 0),
        Epic = Color3.fromRGB(170, 50, 255),
        Rare = Color3.fromRGB(40, 150, 255),
        Common = Color3.fromRGB(210, 210, 210),
        Unknown = Color3.fromRGB(160, 160, 160),
    }

    local BASKET_CAPACITIES = {
        Wooden = 1,
        Infinite = 999999,
    }

    ----------------------------------------------------------------
    --  REMOTES (live verified)
    ----------------------------------------------------------------
    local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
    local GameRemotes = RemotesFolder and RemotesFolder:WaitForChild("Game", 10)

    local EggPickupRemote = GameRemotes and GameRemotes:FindFirstChild("EggPickup")
    local EggPlacedRemote = GameRemotes and GameRemotes:FindFirstChild("EggPlaced")
    local RebirthRemote = GameRemotes and GameRemotes:FindFirstChild("Rebirth")
    local ClaimIndexRemote = GameRemotes and GameRemotes:FindFirstChild("ClaimIndexReward")
    local FeedPetRemote = GameRemotes and GameRemotes:FindFirstChild("FeedPet")
    local TeleportToPlotRemote = GameRemotes and GameRemotes:FindFirstChild("TeleportToPlot")

    local ServerData = ReplicatedStorage:FindFirstChild("ServerData")
    local ActiveEggsFolder = ServerData and ServerData:FindFirstChild("ActiveEggs")

    ----------------------------------------------------------------
    --  STATE
    ----------------------------------------------------------------
    local State = {
        -- Farm
        AutoFarmEggs = false,
        FarmPriority = "Rarest First", -- "Rarest First", "Closest First"
        FarmMethod = "Glide Fly (Safe)", -- "Glide Fly (Safe)", "Instant Teleport (Risky)"
        TweenSpeed = 135,
        ReturnSpeed = 135,
        AutoDeposit = true,
        AutoReturnWhenFull = true,
        FarmCooldown = 0.35,

        -- Tiers Whitelist
        Tiers = {
            Divine = true,
            Ethereal = true,
            Mythic = true,
            Legendary = true,
            Epic = true,
            Rare = true,
            Common = false,
        },

        -- Base & Hatch
        AutoPlaceNests = true,

        -- Progression
        AutoRebirth = false,
        AutoClaimIndex = true,

        -- ESP
        EggESP = true,
        EggTracers = false,
        ESPMinTier = "Rare+",
        ESPMaxDist = 3000,

        -- Movement
        SpeedBoost = false,
        SpeedValue = 120,
        InfiniteJump = false,
        Noclip = false,
        AntiAFK = true,
    }

    local Connections = {}
    local DrawingObjects = {}
    local destroyed = false
    local currentTween = nil
    local isFarmingCycle = false

    ----------------------------------------------------------------
    --  HELPERS
    ----------------------------------------------------------------
    local function getRoot()
        local char = LP.Character
        return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char.PrimaryPart)
    end

    local function getHumanoid()
        local char = LP.Character
        return char and char:FindFirstChildWhichIsA("Humanoid")
    end

    local function getEggTier(name)
        return EGG_TIERS[name] or "Unknown"
    end

    local function getMyPlot()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end
        for _, p in ipairs(plots:GetChildren()) do
            local data = p:FindFirstChild("Data")
            local owner = data and data:FindFirstChild("Owner")
            if owner and (owner.Value == LP or owner.Value == LP.Name) then
                return p
            end
        end
        return nil
    end

    local function getBasketCount()
        local basket = LP:FindFirstChild("Basket")
        return basket and #basket:GetChildren() or 0
    end

    local function getBasketMax()
        local saved = LP:FindFirstChild("SavedData")
        local equipped = saved and saved:FindFirstChild("EquippedEggBasket")
        local bName = equipped and equipped.Value or "Wooden"
        return BASKET_CAPACITIES[bName] or 1
    end

    local function isBasketFull()
        return getBasketCount() >= getBasketMax()
    end

    local function stopTween()
        if currentTween then
            pcall(function() currentTween:Cancel() end)
            currentTween = nil
        end
    end

    local function teleportToPos(targetPos, method)
        local root = getRoot()
        if not root then return false end

        stopTween()

        if method == "Instant Teleport (Risky)" or method == "Instant Teleport" then
            if LP.Character then
                LP.Character:PivotTo(CFrame.new(targetPos + Vector3.new(0, 2.5, 0)))
            else
                root.CFrame = CFrame.new(targetPos + Vector3.new(0, 2.5, 0))
            end
            task.wait(0.2)
            return true
        else
            -- Glide Fly (Safe): smooth linear flight via TweenService
            local startPos = root.Position
            local dist = (startPos - targetPos).Magnitude
            local speed = math.clamp(State.TweenSpeed or 135, 40, 160)
            local duration = math.max(0.15, dist / speed)

            local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
            currentTween = TweenService:Create(root, tweenInfo, {
                CFrame = CFrame.new(targetPos + Vector3.new(0, 2.5, 0))
            })
            currentTween:Play()
            currentTween.Completed:Wait()
            currentTween = nil
            task.wait(0.2)
            return true
        end
    end

    local function returnToPlot(isCarryingEgg)
        local plot = getMyPlot()
        if not plot then return false end
        local base = plot:FindFirstChild("Baseplate") or plot:GetPivot()
        local targetPos = typeof(base) == "CFrame" and base.Position or (base:IsA("BasePart") and base.Position or plot:GetPivot().Position)

        local carrying = isCarryingEgg or (getBasketCount() > 0)
        if carrying then
            -- When carrying eggs, NEVER instant teleport or fire TeleportToPlot (triggers egg return!)
            -- Use safe Glide Fly directly into plot:
            return teleportToPos(targetPos + Vector3.new(0, 3, 0), "Glide Fly (Safe)")
        else
            return teleportToPos(targetPos + Vector3.new(0, 4, 0), State.FarmMethod)
        end
    end


    local function getAvailableNest()
        local plot = getMyPlot()
        if not plot then return nil end
        local nests = plot:FindFirstChild("Nests")
        local eggs = plot:FindFirstChild("Eggs")
        if not nests then return nil end

        for _, nest in ipairs(nests:GetChildren()) do
            local nPos = nest:GetPivot().Position
            local occupied = false
            if eggs then
                for _, egg in ipairs(eggs:GetChildren()) do
                    if (egg:GetPivot().Position - nPos).Magnitude < 4 then
                        occupied = true
                        break
                    end
                end
            end
            if not occupied then
                return nest
            end
        end
        return nil
    end

    local function depositEggs()
        local plot = getMyPlot()
        if not plot then return end

        while not destroyed and getBasketCount() > 0 do
            local nest = getAvailableNest()
            if not nest then
                break
            end

            local nestPos = nest:GetPivot().Position
            local root = getRoot()
            local hum = getHumanoid()

            if root and hum then
                hum:MoveTo(nestPos)
                local startWait = tick()
                while not destroyed and (root.Position - nestPos).Magnitude > 8 and (tick() - startWait) < 3 do
                    task.wait(0.05)
                end
            end

            if EggPlacedRemote then
                pcall(function()
                    EggPlacedRemote:FireServer({
                        NestId = nest.Name
                    })
                end)
            end
            task.wait(0.35)
        end
    end

    ----------------------------------------------------------------
    --  EGG SCANNER & AUTOFARM LOOP
    ----------------------------------------------------------------
    local function getFilteredEggs()
        if not ActiveEggsFolder then
            ServerData = ReplicatedStorage:FindFirstChild("ServerData")
            ActiveEggsFolder = ServerData and ServerData:FindFirstChild("ActiveEggs")
            if not ActiveEggsFolder then return {} end
        end

        local root = getRoot()
        local myPos = root and root.Position or Vector3.zero
        local list = {}

        for _, eggInst in ipairs(ActiveEggsFolder:GetChildren()) do
            local eggName = eggInst:GetAttribute("Egg") or "Unknown"
            local tier = getEggTier(eggName)
            local pos = eggInst:GetAttribute("Position")

            if pos and State.Tiers[tier] == true then
                local dist = (pos - myPos).Magnitude
                table.insert(list, {
                    uuid = eggInst.Name,
                    name = eggName,
                    tier = tier,
                    rank = TIER_RANK[tier] or 0,
                    pos = pos,
                    dist = dist,
                })
            end
        end

        if State.FarmPriority == "Rarest First" then
            table.sort(list, function(a, b)
                if a.rank ~= b.rank then
                    return a.rank > b.rank
                end
                return a.dist < b.dist
            end)
        else
            table.sort(list, function(a, b)
                return a.dist < b.dist
            end)
        end

        return list
    end

    task.spawn(function()
        while not destroyed do
            task.wait(0.15)
            if State.AutoFarmEggs and not isFarmingCycle then
                isFarmingCycle = true

                pcall(function()
                    -- Step 1: Check basket
                    if isBasketFull() then
                        if State.AutoDeposit then
                            returnToPlot(true)
                            depositEggs()
                        end
                    else
                        -- Step 2: Grab best egg
                        local eggs = getFilteredEggs()
                        if #eggs > 0 then
                            local target = eggs[1]
                            local ok = teleportToPos(target.pos, State.FarmMethod)
                            if ok and not destroyed then
                                task.wait(0.25) -- allow server position sync
                                if EggPickupRemote then
                                    pcall(function()
                                        EggPickupRemote:FireServer(target.uuid)
                                    end)
                                end
                                task.wait(State.FarmCooldown or 0.4)

                                -- After pickup, if basket has eggs and auto deposit enabled, return safely
                                if getBasketCount() > 0 and State.AutoDeposit then
                                    returnToPlot(true)
                                    depositEggs()
                                end
                            end
                        else
                            -- No target eggs found, return to plot if carrying egg
                            if State.AutoReturnWhenFull and getBasketCount() > 0 and State.AutoDeposit then
                                returnToPlot(true)
                                depositEggs()
                            end
                        end
                    end
                end)


                isFarmingCycle = false
            end
        end
    end)

    ----------------------------------------------------------------
    --  PLOT / PROGRESSION LOOPS
    ----------------------------------------------------------------
    -- Auto Place / Deposit background check
    task.spawn(function()
        while not destroyed do
            task.wait(1.5)
            if State.AutoPlaceNests and not State.AutoFarmEggs and getBasketCount() > 0 then
                pcall(depositEggs)
            end
        end
    end)

    -- Auto Rebirth loop
    task.spawn(function()
        while not destroyed do
            task.wait(2.0)
            if State.AutoRebirth and RebirthRemote then
                pcall(function()
                    RebirthRemote:FireServer()
                end)
            end
        end
    end)

    -- Auto Claim Index Rewards loop
    task.spawn(function()
        while not destroyed do
            task.wait(3.0)
            if State.AutoClaimIndex and ClaimIndexRemote then
                pcall(function()
                    ClaimIndexRemote:FireServer()
                end)
            end
        end
    end)

    ----------------------------------------------------------------
    --  DRAWING API ESP
    ----------------------------------------------------------------
    local function minTierPassed(tier)
        local rank = TIER_RANK[tier] or 0
        if State.ESPMinTier == "All" then
            return true
        elseif State.ESPMinTier == "Rare+" then
            return rank >= TIER_RANK.Rare
        elseif State.ESPMinTier == "Epic+" then
            return rank >= TIER_RANK.Epic
        elseif State.ESPMinTier == "Legendary+" then
            return rank >= TIER_RANK.Legendary
        elseif State.ESPMinTier == "Mythic+" then
            return rank >= TIER_RANK.Mythic
        end
        return true
    end

    local function getOrCreateDrawing(uuid)
        if DrawingObjects[uuid] then
            return DrawingObjects[uuid]
        end

        local text = Drawing.new("Text")
        text.Size = 13
        text.Center = true
        text.Outline = true
        text.OutlineColor = Color3.new(0, 0, 0)
        text.Visible = false

        local tracer = Drawing.new("Line")
        tracer.Thickness = 1
        tracer.Transparency = 0.8
        tracer.Visible = false

        local entry = {Text = text, Tracer = tracer}
        DrawingObjects[uuid] = entry
        return entry
    end

    local function removeDrawing(uuid)
        local entry = DrawingObjects[uuid]
        if entry then
            pcall(function() entry.Text:Remove() end)
            pcall(function() entry.Tracer:Remove() end)
            DrawingObjects[uuid] = nil
        end
    end

    local function clearAllESP()
        for uuid, entry in pairs(DrawingObjects) do
            pcall(function() entry.Text:Remove() end)
            pcall(function() entry.Tracer:Remove() end)
        end
        table.clear(DrawingObjects)
    end

    local espConn = RunService.RenderStepped:Connect(function()
        if destroyed or not State.EggESP or not ActiveEggsFolder then
            for _, entry in pairs(DrawingObjects) do
                entry.Text.Visible = false
                entry.Tracer.Visible = false
            end
            return
        end

        local root = getRoot()
        local myPos = root and root.Position or Vector3.zero
        local screenBottom = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        local activeUUIDs = {}

        for _, eggInst in ipairs(ActiveEggsFolder:GetChildren()) do
            local uuid = eggInst.Name
            activeUUIDs[uuid] = true

            local eggName = eggInst:GetAttribute("Egg") or "Unknown"
            local tier = getEggTier(eggName)
            local pos = eggInst:GetAttribute("Position")

            if pos and minTierPassed(tier) then
                local dist = (pos - myPos).Magnitude
                if dist <= State.ESPMaxDist then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                    local entry = getOrCreateDrawing(uuid)
                    local color = TIER_COLORS[tier] or Color3.fromRGB(200, 200, 200)

                    if onScreen then
                        entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                        entry.Text.Color = color
                        entry.Text.Text = string.format("[%s] %s\n(%dm)", tier, eggName, math.floor(dist))
                        entry.Text.Visible = true

                        if State.EggTracers then
                            entry.Tracer.From = screenBottom
                            entry.Tracer.To = Vector2.new(screenPos.X, screenPos.Y)
                            entry.Tracer.Color = color
                            entry.Tracer.Visible = true
                        else
                            entry.Tracer.Visible = false
                        end
                    else
                        entry.Text.Visible = false
                        entry.Tracer.Visible = false
                    end
                else
                    if DrawingObjects[uuid] then
                        DrawingObjects[uuid].Text.Visible = false
                        DrawingObjects[uuid].Tracer.Visible = false
                    end
                end
            else
                if DrawingObjects[uuid] then
                    DrawingObjects[uuid].Text.Visible = false
                    DrawingObjects[uuid].Tracer.Visible = false
                end
            end
        end

        -- Clean up orphaned drawings
        for uuid, _ in pairs(DrawingObjects) do
            if not activeUUIDs[uuid] then
                removeDrawing(uuid)
            end
        end
    end)
    table.insert(Connections, espConn)

    ----------------------------------------------------------------
    --  MOVEMENT & CHARACTER ENHANCEMENTS
    ----------------------------------------------------------------
    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if destroyed then return end

        local hum = getHumanoid()
        if hum and State.SpeedBoost then
            hum.WalkSpeed = State.SpeedValue
        end

        if State.Noclip and LP.Character then
            for _, part in ipairs(LP.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end)
    table.insert(Connections, heartbeatConn)

    local jumpConn = UserInputService.JumpRequest:Connect(function()
        if State.InfiniteJump then
            local hum = getHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)
    table.insert(Connections, jumpConn)

    local idledConn = LP.Idled:Connect(function()
        if State.AntiAFK then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end
    end)
    table.insert(Connections, idledConn)

    ----------------------------------------------------------------
    --  USER INTERFACE (Window Tabs)
    ----------------------------------------------------------------
    local FarmTab = Window:CreateTab("Automation", "egg")
    local VisualsTab = Window:CreateTab("Visuals", "eye")
    local TeleportsTab = Window:CreateTab("Teleports", "map-pin")
    local MovementTab = Window:CreateTab("Movement", "zap")
    local MiscTab = Window:CreateTab("Misc", "settings")

    -- Tab 1: Automation
    FarmTab:CreateSection("Egg Sniper & Auto Farm")
    FarmTab:CreateToggle({
        Name = "Auto Farm Eggs",
        CurrentValue = State.AutoFarmEggs,
        Flag = "RAP_AutoFarmEggs",
        Callback = function(val)
            State.AutoFarmEggs = val
            if not val then
                stopTween()
            end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Farm Priority",
        Options = {"Rarest First", "Closest First"},
        CurrentOption = {State.FarmPriority},
        MultipleOptions = false,
        Flag = "RAP_FarmPriority",
        Callback = function(opt)
            local choice = type(opt) == "table" and opt[1] or opt
            if choice then State.FarmPriority = choice end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Movement Method",
        Options = {"Glide Fly (Safe)", "Instant Teleport (Risky)"},
        CurrentOption = {State.FarmMethod},
        MultipleOptions = false,
        Flag = "RAP_FarmMethod",
        Callback = function(opt)
            local choice = type(opt) == "table" and opt[1] or opt
            if choice then State.FarmMethod = choice end
        end,
    })

    FarmTab:CreateSlider({
        Name = "Glide Fly Speed",
        Range = {60, 160},
        Increment = 5,
        Suffix = " studs/s",
        CurrentValue = State.TweenSpeed,
        Flag = "RAP_TweenSpeed",
        Callback = function(val)
            State.TweenSpeed = val
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Deposit When Full",
        CurrentValue = State.AutoDeposit,
        Flag = "RAP_AutoDeposit",
        Callback = function(val)
            State.AutoDeposit = val
        end,
    })



    FarmTab:CreateSection("Tier Whitelist")
    for _, tier in ipairs({"Divine", "Ethereal", "Mythic", "Legendary", "Epic", "Rare", "Common"}) do
        FarmTab:CreateToggle({
            Name = tier .. " Eggs",
            CurrentValue = State.Tiers[tier] == true,
            Flag = "RAP_Tier_" .. tier,
            Callback = function(val)
                State.Tiers[tier] = val
            end,
        })
    end

    FarmTab:CreateSection("Plot & Base Automation")
    FarmTab:CreateToggle({
        Name = "Auto Place Eggs into Nests",
        CurrentValue = State.AutoPlaceNests,
        Flag = "RAP_AutoPlaceNests",
        Callback = function(val)
            State.AutoPlaceNests = val
        end,
    })

    FarmTab:CreateButton({
        Name = "Deposit All Basket Eggs Now",
        Callback = function()
            task.spawn(function()
                returnToPlot()
                depositEggs()
            end)
        end,
    })

    FarmTab:CreateSection("Progression & Economy")
    FarmTab:CreateToggle({
        Name = "Auto Rebirth",
        CurrentValue = State.AutoRebirth,
        Flag = "RAP_AutoRebirth",
        Callback = function(val)
            State.AutoRebirth = val
        end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Claim Index Rewards",
        CurrentValue = State.AutoClaimIndex,
        Flag = "RAP_AutoClaimIndex",
        Callback = function(val)
            State.AutoClaimIndex = val
        end,
    })

    -- Tab 2: Visuals
    VisualsTab:CreateSection("Drawing ESP")
    VisualsTab:CreateToggle({
        Name = "Egg ESP",
        CurrentValue = State.EggESP,
        Flag = "RAP_EggESP",
        Callback = function(val)
            State.EggESP = val
            if not val then
                clearAllESP()
            end
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Egg Tracers",
        CurrentValue = State.EggTracers,
        Flag = "RAP_EggTracers",
        Callback = function(val)
            State.EggTracers = val
        end,
    })

    VisualsTab:CreateDropdown({
        Name = "ESP Minimum Tier",
        Options = {"All", "Rare+", "Epic+", "Legendary+", "Mythic+"},
        CurrentOption = {State.ESPMinTier},
        MultipleOptions = false,
        Flag = "RAP_ESPMinTier",
        Callback = function(opt)
            local choice = type(opt) == "table" and opt[1] or opt
            if choice then State.ESPMinTier = choice end
        end,
    })

    VisualsTab:CreateSlider({
        Name = "Max ESP Distance",
        Range = {200, 5000},
        Increment = 100,
        Suffix = " studs",
        CurrentValue = State.ESPMaxDist,
        Flag = "RAP_ESPMaxDist",
        Callback = function(val)
            State.ESPMaxDist = val
        end,
    })

    -- Tab 3: Teleports
    TeleportsTab:CreateSection("Quick Teleports")
    TeleportsTab:CreateButton({
        Name = "Teleport to My Plot",
        Callback = function()
            returnToPlot()
        end,
    })

    TeleportsTab:CreateSection("Server Rare Eggs Tracker")
    local rareEggOptions = {"Refresh List"}
    local rareEggMap = {}

    local function refreshRareEggs()
        table.clear(rareEggOptions)
        table.clear(rareEggMap)
        if ActiveEggsFolder then
            for _, eggInst in ipairs(ActiveEggsFolder:GetChildren()) do
                local name = eggInst:GetAttribute("Egg") or "Unknown"
                local tier = getEggTier(name)
                local rank = TIER_RANK[tier] or 0
                local pos = eggInst:GetAttribute("Position")
                if pos and rank >= TIER_RANK.Legendary then
                    local label = string.format("[%s] %s (%s)", tier, name, string.sub(eggInst.Name, 1, 6))
                    table.insert(rareEggOptions, label)
                    rareEggMap[label] = pos
                end
            end
        end
        if #rareEggOptions == 0 then
            table.insert(rareEggOptions, "No Rare Eggs Active")
        end
    end
    refreshRareEggs()

    local selectedRareEggLabel = rareEggOptions[1]
    local rareDropdown = TeleportsTab:CreateDropdown({
        Name = "Active Rare Eggs",
        Options = rareEggOptions,
        CurrentOption = {selectedRareEggLabel},
        MultipleOptions = false,
        Flag = "RAP_ActiveRareEggs",
        Callback = function(opt)
            local choice = type(opt) == "table" and opt[1] or opt
            if choice then selectedRareEggLabel = choice end
        end,
    })

    TeleportsTab:CreateButton({
        Name = "Fly to Selected Egg (Safe)",
        Callback = function()
            local pos = rareEggMap[selectedRareEggLabel]
            if pos then
                teleportToPos(pos, "Glide Fly (Safe)")
            end
        end,
    })

    TeleportsTab:CreateButton({
        Name = "Teleport to Selected Egg (Instant / Risky)",
        Callback = function()
            local pos = rareEggMap[selectedRareEggLabel]
            if pos then
                teleportToPos(pos, "Instant Teleport (Risky)")
            end
        end,
    })


    TeleportsTab:CreateButton({
        Name = "Refresh Egg List",
        Callback = function()
            refreshRareEggs()
            pcall(function()
                rareDropdown:Refresh(rareEggOptions, true)
            end)
        end,
    })

    -- Tab 4: Movement
    MovementTab:CreateSection("Character Enhancements")
    MovementTab:CreateToggle({
        Name = "Speed Boost",
        CurrentValue = State.SpeedBoost,
        Flag = "RAP_SpeedBoost",
        Callback = function(val)
            State.SpeedBoost = val
            if not val then
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = 16 end
            end
        end,
    })

    MovementTab:CreateSlider({
        Name = "WalkSpeed (Safe <= 160)",
        Range = {16, 160},
        Increment = 5,
        Suffix = " spd",
        CurrentValue = State.SpeedValue,
        Flag = "RAP_SpeedValue",
        Callback = function(val)
            State.SpeedValue = val
        end,
    })


    MovementTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = State.InfiniteJump,
        Flag = "RAP_InfiniteJump",
        Callback = function(val)
            State.InfiniteJump = val
        end,
    })

    MovementTab:CreateToggle({
        Name = "Noclip",
        CurrentValue = State.Noclip,
        Flag = "RAP_Noclip",
        Callback = function(val)
            State.Noclip = val
        end,
    })

    -- Tab 5: Misc
    MiscTab:CreateSection("Session & Safety")
    MiscTab:CreateToggle({
        Name = "Anti-AFK",
        CurrentValue = State.AntiAFK,
        Flag = "RAP_AntiAFK",
        Callback = function(val)
            State.AntiAFK = val
        end,
    })

    MiscTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
            end)
        end,
    })

    MiscTab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            pcall(function()
                TeleportService:Teleport(game.PlaceId, LP)
            end)
        end,
    })

    ----------------------------------------------------------------
    --  SORT TABS
    ----------------------------------------------------------------
    pcall(function()
        if type(Window.SortTabs) == "function" then
            Window:SortTabs({"Overview", "Automation", "Visuals", "Teleports", "Movement", "Misc", "Settings"})
        end
    end)

    ----------------------------------------------------------------
    --  CLEANUP
    ----------------------------------------------------------------
    local function destroy()
        if destroyed then return end
        destroyed = true
        State.AutoFarmEggs = false
        State.EggESP = false
        stopTween()
        clearAllESP()

        for _, conn in ipairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(Connections)

        local hum = getHumanoid()
        if hum then hum.WalkSpeed = 16 end

        pcall(function()
            local env = getgenv()
            if env.__RAVEN_RIDE_A_PET and env.__RAVEN_RIDE_A_PET.Settings == State then
                env.__RAVEN_RIDE_A_PET = nil
            end
        end)
    end

    getgenv().__RAVEN_RIDE_A_PET = {
        Version = "v1.1.0",
        Settings = State,
        GetFilteredEggs = getFilteredEggs,
        ReturnToPlot = returnToPlot,
        DepositEggs = depositEggs,
        Destroy = destroy,
    }

    if runtimeInfo and type(runtimeInfo.registerCleanup) == "function" then
        runtimeInfo.registerCleanup(destroy)
    end
end
