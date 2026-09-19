--[[
    RAVEN HUB Module - Pull An Egg v1.0.0
    Game: Pull An Egg (PlaceId: 70640255604878 / GameId: 10649255304)
    Developer: Future Cooks

    Features:
    - 🏋️ Auto Farm & Train:
      * Auto Train (Dumbell): Fires `Activate Dumbell` remote continuously
      * Auto Collect Cash: Sweeps `Collect Earnings` across all stands on plot instantly
      * Auto Rebirth: Automatically rebirthes as soon as Strength requirement is met
      * Auto Buy Best Dumbell: Scans database for highest affordable dumbell and equips it
      * Auto Hatch Ready: Instantly opens completed eggs on plot (`Open Lucky Block`)
    - 🥚 Auto Steal & Egg Sniper:
      * Target Rarities multi-filter (Secret, Divine, Mythic, etc.)
      * Steal Mode: Instant Teleport (with auto-return) or Manual nearest steal
      * Anti-Trip: Holds egg and safely brings back to base
    - 👁️ Visuals (100% Drawing API):
      * Egg ESP & Tracers with live distance & tier color coding
      * Filter by minimum rarity or specific egg types
    - ⚡ Teleports & Movement:
      * TP to Plot Base
      * TP to Any World (Galaxy, Heaven, Hell, Neon, etc.)
      * WalkSpeed & JumpPower multipliers
      * Anti-AFK & Server Utilities
]]--

return function(Window, runtimeInfo)
    pcall(function()
        local prev = getgenv().__RAVEN_PULL_AN_EGG
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
    --  DATABASES & REMOTES
    ----------------------------------------------------------------
    local SharedModules = ReplicatedStorage:WaitForChild("SharedModules")
    local RemotesFolder = SharedModules:WaitForChild("Network"):WaitForChild("Remotes")
    local Database = SharedModules:WaitForChild("Database")

    local DumbellsDB = require(Database:WaitForChild("Dumbells"))
    local RebirthsDB = require(Database:WaitForChild("Rebirths"))
    local WorldsDB = require(Database:WaitForChild("Worlds"))
    local FriendsDB = require(Database:WaitForChild("Friends"))

    local Remotes = {
        ActivateDumbell = RemotesFolder:WaitForChild("Activate Dumbell"),
        CollectEarnings = RemotesFolder:WaitForChild("Collect Earnings"),
        Rebirth = RemotesFolder:WaitForChild("Rebirth"),
        BuyDumbell = RemotesFolder:WaitForChild("Buy Dumbell"),
        EquipDumbell = RemotesFolder:WaitForChild("Equip Dumbell"),
        OpenLuckyBlock = RemotesFolder:WaitForChild("Open Lucky Block"),
        PlaceFriend = RemotesFolder:WaitForChild("Place Friend"),
        AFKReset = RemotesFolder:WaitForChild("AFK Idle Reset Request"),
    }

    local DataController = nil
    pcall(function()
        DataController = require(LP.PlayerScripts._G.Important.Data)
    end)

    local function getPlayerData()
        if DataController and type(DataController.Get) == "function" then
            local ok, d = pcall(DataController.Get, DataController)
            if ok and d then return d end
        end
        return nil
    end

    ----------------------------------------------------------------
    --  RARITY DATA & COLORS
    ----------------------------------------------------------------
    local RarityRanks = {
        ["Common"] = 1,
        ["Rare"] = 2,
        ["Epic"] = 3,
        ["Legendary"] = 4,
        ["Mythic"] = 5,
        ["OG"] = 6,
        ["Ancient"] = 7,
        ["Divine"] = 8,
        ["Transcendent"] = 9,
        ["Secret"] = 10,
        ["Brainrot God"] = 11,
        ["Unknown"] = 0,
    }

    local RarityColors = {
        ["Common"] = Color3.fromRGB(180, 180, 180),
        ["Rare"] = Color3.fromRGB(85, 170, 255),
        ["Epic"] = Color3.fromRGB(190, 75, 255),
        ["Legendary"] = Color3.fromRGB(255, 215, 0),
        ["Mythic"] = Color3.fromRGB(255, 60, 60),
        ["OG"] = Color3.fromRGB(255, 140, 0),
        ["Ancient"] = Color3.fromRGB(210, 180, 140),
        ["Divine"] = Color3.fromRGB(0, 240, 255),
        ["Transcendent"] = Color3.fromRGB(255, 105, 180),
        ["Secret"] = Color3.fromRGB(50, 50, 50),
        ["Brainrot God"] = Color3.fromRGB(0, 255, 127),
        ["Unknown"] = Color3.fromRGB(255, 255, 255),
    }

    local EggRarityCache = {}
    local function getEggRarity(eggName)
        if EggRarityCache[eggName] then return EggRarityCache[eggName] end
        for _, f in pairs(FriendsDB) do
            if f.Name == eggName or (f.Model and f.Model.Name == eggName) then
                local r = f.Rarity or "Unknown"
                EggRarityCache[eggName] = r
                return r
            end
        end
        EggRarityCache[eggName] = "Unknown"
        return "Unknown"
    end

    ----------------------------------------------------------------
    --  STATE
    ----------------------------------------------------------------
    local State = {
        -- Farm
        AutoTrain = false,
        TrainInterval = 0.5,
        AutoCollectCash = false,
        CollectInterval = 1.0,
        AutoRebirth = false,
        AutoBuyDumbell = false,
        AutoHatchReady = false,

        -- Steal
        AutoSteal = false,
        StealSelectedOnly = false,
        TargetRarities = {
            ["Common"] = false,
            ["Rare"] = false,
            ["Epic"] = false,
            ["Legendary"] = true,
            ["Mythic"] = true,
            ["OG"] = true,
            ["Ancient"] = true,
            ["Divine"] = true,
            ["Transcendent"] = true,
            ["Secret"] = true,
            ["Brainrot God"] = true,
        },
        StealDelay = 1.5,
        AutoReturnBase = true,

        -- Visuals
        EggESP = false,
        EggTracers = false,
        ESPMaxDist = 2500,
        ESPMinRarity = "Common",

        -- Guard & Protection
        DisableGuard = true,
        AntiRagdoll = true,

        -- Movement & Misc
        WalkSpeed = 24,
        CustomSpeed = false,
        JumpPower = 50,
        CustomJump = false,
        Noclip = false,
        AntiAFK = true,
    }

    local Connections = {}
    local DrawingObjects = {}
    local destroyed = false
    local isStealing = false

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(Connections, conn)
        return conn
    end

    ----------------------------------------------------------------
    --  CHARACTER UTILITIES
    ----------------------------------------------------------------
    local function getCharacter()
        return LP.Character or LP.CharacterAdded:Wait()
    end

    local function getHumanoid()
        local char = LP.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot()
        local char = LP.Character
        return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    end

    local function getMyPlot()
        local plot = _G.MyPlot
        if plot and plot.Parent then return plot end
        local plots = workspace:FindFirstChild("Plots")
        if plots then
            for _, p in ipairs(plots:GetChildren()) do
                local owner = p:FindFirstChild("owner")
                if owner and owner.Value == LP.Name then
                    _G.MyPlot = p
                    return p
                end
            end
        end
        return nil
    end

    local function getBaseCFrame()
        local plot = getMyPlot()
        if plot then
            local base = plot:FindFirstChild("Base")
            if base then
                return base.CFrame + Vector3.new(0, 3.5, 0)
            end
            return plot:GetPivot() + Vector3.new(0, 3.5, 0)
        end
        return nil
    end

    ----------------------------------------------------------------
    --  GUARD NEUTRALIZER & DEFENSE SUITE
    ----------------------------------------------------------------
    local function neutralizeGuardModel(guard)
        if not guard or not guard:IsA("Model") then return end
        for _, part in ipairs(guard:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanTouch = false
                part.CanCollide = false
                part.CanQuery = false
            end
        end
    end

    local function applyGuardDisabler()
        local gFolder = workspace:FindFirstChild("Live") and workspace.Live:FindFirstChild("Guardians")
        if not gFolder then return end

        for _, g in ipairs(gFolder:GetChildren()) do
            neutralizeGuardModel(g)
        end
    end

    local gFolderRef = workspace:FindFirstChild("Live") and workspace.Live:FindFirstChild("Guardians")
    if gFolderRef then
        connect(gFolderRef.ChildAdded, function(c)
            if State.DisableGuard then
                task.wait(0.05)
                neutralizeGuardModel(c)
            end
        end)
    end

    -- Guard Defense Heartbeat: Keeps collision/touch off and prevents Ragdoll
    connect(RunService.Heartbeat, function()
        if destroyed then return end

        if State.DisableGuard then
            applyGuardDisabler()
        end

        if State.AntiRagdoll then
            local char = LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                local rag = char:FindFirstChild("Ragdoll Client")
                if rag and not rag.Disabled then
                    rag.Disabled = true
                end

                local ragVal = char:FindFirstChild("Ragdolled")
                if ragVal and ragVal.Value == true then
                    ragVal.Value = false
                end

                if hum and (hum:GetState() == Enum.HumanoidStateType.Physics or hum:GetState() == Enum.HumanoidStateType.Ragdoll) then
                    hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end
    end)

    ----------------------------------------------------------------
    --  AUTO FARM IMPLEMENTATION
    ----------------------------------------------------------------
    -- 1. Auto Train (Fast Dumbell)
    task.spawn(function()
        while not destroyed do
            if State.AutoTrain and Remotes.ActivateDumbell then
                pcall(function()
                    Remotes.ActivateDumbell:FireServer()
                end)
            end
            task.wait(State.TrainInterval)
        end
    end)

    -- 2. Auto Collect Plot Cash
    task.spawn(function()
        while not destroyed do
            if State.AutoCollectCash and Remotes.CollectEarnings then
                local data = getPlayerData()
                if data and data.PlotFriends then
                    for standId, _ in pairs(data.PlotFriends) do
                        pcall(function()
                            Remotes.CollectEarnings:FireServer(tostring(standId))
                        end)
                    end
                end
            end
            task.wait(State.CollectInterval)
        end
    end)

    -- 3. Auto Rebirth
    task.spawn(function()
        while not destroyed do
            if State.AutoRebirth and Remotes.Rebirth then
                local data = getPlayerData()
                if data then
                    local curRebirth = data.Rebirth or 0
                    local nextInfo = RebirthsDB[curRebirth + 1]
                    if nextInfo and nextInfo.StrengthRequirement then
                        local curStr = data.TotalStrength or data.Strength or 0
                        if curStr >= nextInfo.StrengthRequirement then
                            pcall(function()
                                Remotes.Rebirth:FireServer()
                            end)
                        end
                    end
                end
            end
            task.wait(2.0)
        end
    end)

    -- 4. Auto Buy Best Dumbell
    task.spawn(function()
        while not destroyed do
            if State.AutoBuyDumbell and Remotes.BuyDumbell and Remotes.EquipDumbell then
                local data = getPlayerData()
                if data then
                    local currentCash = data.Cash or 0
                    local equipped = data.EquippedDumbell or "Dumbell_1"
                    local bestCandidate = nil
                    local bestStrength = DumbellsDB[equipped] and DumbellsDB[equipped].Strength or 0

                    for id, info in pairs(DumbellsDB) do
                        if info.Price and info.Strength and info.Price <= currentCash then
                            if info.Strength > bestStrength then
                                if not bestCandidate or info.Strength > bestCandidate.Strength then
                                    bestCandidate = { id = id, Strength = info.Strength }
                                end
                            end
                        end
                    end

                    if bestCandidate then
                        pcall(function()
                            Remotes.BuyDumbell:FireServer(bestCandidate.id)
                            task.wait(0.2)
                            Remotes.EquipDumbell:FireServer(bestCandidate.id)
                        end)
                    end
                end
            end
            task.wait(2.5)
        end
    end)

    -- 5. Auto Hatch Ready Eggs on Plot
    task.spawn(function()
        while not destroyed do
            if State.AutoHatchReady and Remotes.OpenLuckyBlock then
                local data = getPlayerData()
                if data and data.PlotFriends then
                    local now = workspace:GetServerTimeNow()
                    for uid, info in pairs(data.PlotFriends) do
                        if info.incubating and info.finishTime and info.finishTime <= now then
                            pcall(function()
                                Remotes.OpenLuckyBlock:FireServer(uid)
                            end)
                        end
                    end
                end
            end
            task.wait(1.0)
        end
    end)

    ----------------------------------------------------------------
    --  AUTO STEAL & SNIPER
    ----------------------------------------------------------------
    local function getAvailableEggs()
        local list = {}
        local friendsFolder = workspace:FindFirstChild("Live") and workspace.Live:FindFirstChild("Friends")
        if not friendsFolder then return list end

        local root = getRoot()
        local myPos = root and root.Position or Vector3.zero

        for _, egg in ipairs(friendsFolder:GetChildren()) do
            if egg:IsA("Model") then
                local prompt = egg:FindFirstChild("StealPrompt", true)
                if prompt and prompt:IsA("ProximityPrompt") then
                    local rarity = getEggRarity(egg.Name)
                    local dist = (egg:GetPivot().Position - myPos).Magnitude
                    table.insert(list, {
                        model = egg,
                        name = egg.Name,
                        rarity = rarity,
                        rank = RarityRanks[rarity] or 0,
                        prompt = prompt,
                        distance = dist,
                        cframe = egg:GetPivot(),
                    })
                end
            end
        end

        table.sort(list, function(a, b)
            if a.rank ~= b.rank then
                return a.rank > b.rank
            end
            return a.distance < b.distance
        end)

        return list
    end

    local function stealEgg(eggData)
        local root = getRoot()
        if not root or not eggData or not eggData.prompt then return false end

        isStealing = true
        local prevCF = root.CFrame
        local baseCF = getBaseCFrame()

        -- Teleport to egg
        root.CFrame = eggData.cframe + Vector3.new(0, 2, 0)
        task.wait(0.15)

        -- Trigger steal prompt
        if type(fireproximityprompt) == "function" then
            pcall(fireproximityprompt, eggData.prompt, 0)
        end
        task.wait(0.25)

        -- Return to base if requested, or back to previous position
        if State.AutoReturnBase and baseCF then
            root.CFrame = baseCF
        else
            root.CFrame = prevCF
        end
        task.wait(0.2)

        isStealing = false
        return true
    end

    task.spawn(function()
        while not destroyed do
            if State.AutoSteal and not isStealing then
                local eggs = getAvailableEggs()
                local target = nil
                for _, e in ipairs(eggs) do
                    if State.TargetRarities[e.rarity] == true then
                        target = e
                        break
                    end
                end

                if target then
                    stealEgg(target)
                end
            end
            task.wait(State.StealDelay)
        end
    end)

    ----------------------------------------------------------------
    --  DRAWING API EGG ESP
    ----------------------------------------------------------------
    local function getOrCreateDrawing(id)
        if DrawingObjects[id] then return DrawingObjects[id] end

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

        local entry = { Text = text, Tracer = tracer }
        DrawingObjects[id] = entry
        return entry
    end

    local function clearAllESP()
        for _, entry in pairs(DrawingObjects) do
            pcall(function() entry.Text:Remove() end)
            pcall(function() entry.Tracer:Remove() end)
        end
        table.clear(DrawingObjects)
    end

    connect(RunService.RenderStepped, function()
        if destroyed or not State.EggESP then
            for _, entry in pairs(DrawingObjects) do
                entry.Text.Visible = false
                entry.Tracer.Visible = false
            end
            return
        end

        local friendsFolder = workspace:FindFirstChild("Live") and workspace.Live:FindFirstChild("Friends")
        if not friendsFolder then return end

        local root = getRoot()
        local myPos = root and root.Position or Vector3.zero
        local screenBottom = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        local minRank = RarityRanks[State.ESPMinRarity] or 0
        local activeIds = {}

        for _, egg in ipairs(friendsFolder:GetChildren()) do
            if egg:IsA("Model") then
                local id = egg:GetDebugId()
                activeIds[id] = true

                local rarity = getEggRarity(egg.Name)
                local rank = RarityRanks[rarity] or 0

                if rank >= minRank then
                    local pos = egg:GetPivot().Position
                    local dist = (pos - myPos).Magnitude

                    if dist <= State.ESPMaxDist then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                        local entry = getOrCreateDrawing(id)
                        local col = RarityColors[rarity] or Color3.new(1, 1, 1)

                        if onScreen then
                            entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                            entry.Text.Color = col
                            entry.Text.Text = string.format("[%s] %s\n[%dm]", rarity, egg.Name, math.floor(dist))
                            entry.Text.Visible = true

                            if State.EggTracers then
                                entry.Tracer.From = screenBottom
                                entry.Tracer.To = Vector2.new(screenPos.X, screenPos.Y)
                                entry.Tracer.Color = col
                                entry.Tracer.Visible = true
                            else
                                entry.Tracer.Visible = false
                            end
                        else
                            entry.Text.Visible = false
                            entry.Tracer.Visible = false
                        end
                    else
                        local entry = DrawingObjects[id]
                        if entry then
                            entry.Text.Visible = false
                            entry.Tracer.Visible = false
                        end
                    end
                end
            end
        end

        for id, entry in pairs(DrawingObjects) do
            if not activeIds[id] then
                entry.Text.Visible = false
                entry.Tracer.Visible = false
            end
        end
    end)

    ----------------------------------------------------------------
    --  CHARACTER MODS (Speed, Jump, Noclip)
    ----------------------------------------------------------------
    connect(RunService.Stepped, function()
        if destroyed then return end
        if State.Noclip then
            local char = LP.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end

        local hum = getHumanoid()
        if hum then
            if State.CustomSpeed and hum.WalkSpeed ~= State.WalkSpeed then
                hum.WalkSpeed = State.WalkSpeed
            end
            if State.CustomJump and hum.JumpPower ~= State.JumpPower then
                hum.JumpPower = State.JumpPower
            end
        end
    end)

    -- Anti-AFK
    connect(LP.Idled, function()
        if State.AntiAFK then
            pcall(function()
                if Remotes.AFKReset then Remotes.AFKReset:FireServer() end
                VirtualUser:Button2Down(Vector2.zero, Camera.CFrame)
                task.wait(1)
                VirtualUser:Button2Up(Vector2.zero, Camera.CFrame)
            end)
        end
    end)

    ----------------------------------------------------------------
    --  UI CREATION
    ----------------------------------------------------------------
    if not Window or type(Window.CreateTab) ~= "function" then
        local dummy = {}
        function dummy:CreateTab()
            local tab = {}
            function tab:CreateSection() end
            function tab:CreateToggle() end
            function tab:CreateDropdown() end
            function tab:CreateSlider() end
            function tab:CreateButton() end
            return tab
        end
        Window = dummy
    end

    local FarmTab = Window:CreateTab("Farm", 4483362458)
    local StealTab = Window:CreateTab("Steal", 4483362458)
    local VisualTab = Window:CreateTab("Visuals", 4483362458)
    local TeleportTab = Window:CreateTab("Teleports", 4483362458)
    local MiscTab = Window:CreateTab("Misc", 4483362458)

    -- ==================== Farm Tab ====================
    FarmTab:CreateSection("Auto Training & Progression")
    FarmTab:CreateToggle({
        Name = "Auto Train (Fast Dumbell)",
        CurrentValue = false,
        Flag = "PAE_AutoTrain",
        Callback = function(v) State.AutoTrain = v end,
    })
    FarmTab:CreateSlider({
        Name = "Train Delay",
        Range = {0.1, 2.0},
        Increment = 0.1,
        Suffix = "s",
        CurrentValue = 0.5,
        Flag = "PAE_TrainDelay",
        Callback = function(v) State.TrainInterval = v end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Collect Plot Cash",
        CurrentValue = false,
        Flag = "PAE_AutoCollectCash",
        Callback = function(v) State.AutoCollectCash = v end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Rebirth",
        CurrentValue = false,
        Flag = "PAE_AutoRebirth",
        Callback = function(v) State.AutoRebirth = v end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Buy Best Dumbell",
        CurrentValue = false,
        Flag = "PAE_AutoBuyDumbell",
        Callback = function(v) State.AutoBuyDumbell = v end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Hatch Ready Eggs",
        CurrentValue = false,
        Flag = "PAE_AutoHatchReady",
        Callback = function(v) State.AutoHatchReady = v end,
    })

    -- ==================== Steal Tab ====================
    StealTab:CreateSection("Guard & Defense Bypass")
    StealTab:CreateToggle({
        Name = "Disable Guards (ปิดตัวเฝ้า/ตัดชน)",
        CurrentValue = true,
        Flag = "PAE_DisableGuard",
        Callback = function(v) State.DisableGuard = v end,
    })
    StealTab:CreateToggle({
        Name = "Anti-Ragdoll / Anti-Trip",
        CurrentValue = true,
        Flag = "PAE_AntiRagdoll",
        Callback = function(v) State.AntiRagdoll = v end,
    })

    StealTab:CreateSection("Egg Steal & Pulling")
    StealTab:CreateToggle({
        Name = "Auto Steal Targeted Eggs",
        CurrentValue = false,
        Flag = "PAE_AutoSteal",
        Callback = function(v) State.AutoSteal = v end,
    })
    StealTab:CreateToggle({
        Name = "Auto Return to Plot Base",
        CurrentValue = true,
        Flag = "PAE_AutoReturnBase",
        Callback = function(v) State.AutoReturnBase = v end,
    })
    StealTab:CreateSlider({
        Name = "Steal Delay",
        Range = {0.5, 5.0},
        Increment = 0.5,
        Suffix = "s",
        CurrentValue = 1.5,
        Flag = "PAE_StealDelay",
        Callback = function(v) State.StealDelay = v end,
    })

    StealTab:CreateSection("Target Rarities")
    local rarityOptions = {
        "Brainrot God", "Secret", "Transcendent", "Divine",
        "Ancient", "OG", "Mythic", "Legendary", "Epic", "Rare", "Common"
    }
    for _, r in ipairs(rarityOptions) do
        StealTab:CreateToggle({
            Name = "Steal " .. r,
            CurrentValue = State.TargetRarities[r] or false,
            Flag = "PAE_Target_" .. r:gsub("%s+", ""),
            Callback = function(v) State.TargetRarities[r] = v end,
        })
    end

    StealTab:CreateButton({
        Name = "Steal Best Egg Now",
        Callback = function()
            local eggs = getAvailableEggs()
            if #eggs > 0 then
                stealEgg(eggs[1])
            end
        end,
    })

    -- ==================== Visual Tab ====================
    VisualTab:CreateSection("Egg Visuals (100% Drawing API)")
    VisualTab:CreateToggle({
        Name = "Egg ESP",
        CurrentValue = false,
        Flag = "PAE_EggESP",
        Callback = function(v) State.EggESP = v end,
    })
    VisualTab:CreateToggle({
        Name = "Egg Tracers",
        CurrentValue = false,
        Flag = "PAE_EggTracers",
        Callback = function(v) State.EggTracers = v end,
    })
    VisualTab:CreateDropdown({
        Name = "Minimum Rarity Filter",
        Options = {"Common", "Rare", "Epic", "Legendary", "Mythic", "OG", "Ancient", "Divine", "Transcendent", "Secret"},
        CurrentOption = "Common",
        Flag = "PAE_ESPMinRarity",
        Callback = function(v) State.ESPMinRarity = v end,
    })
    VisualTab:CreateSlider({
        Name = "ESP Max Distance",
        Range = {200, 5000},
        Increment = 100,
        Suffix = " studs",
        CurrentValue = 2500,
        Flag = "PAE_ESPDist",
        Callback = function(v) State.ESPMaxDist = v end,
    })

    -- ==================== Teleport Tab ====================
    TeleportTab:CreateSection("Base & Worlds")
    TeleportTab:CreateButton({
        Name = "Teleport to My Plot",
        Callback = function()
            local cf = getBaseCFrame()
            local root = getRoot()
            if cf and root then
                root.CFrame = cf
            end
        end,
    })

    local worldList = {}
    for worldName, _ in pairs(WorldsDB) do
        table.insert(worldList, worldName)
    end
    table.sort(worldList)

    TeleportTab:CreateSection("World Teleports")
    for _, w in ipairs(worldList) do
        TeleportTab:CreateButton({
            Name = "Go to " .. w,
            Callback = function()
                pcall(function()
                    RemotesFolder:WaitForChild("Teleport To World"):FireServer(w)
                end)
            end,
        })
    end

    -- ==================== Misc Tab ====================
    MiscTab:CreateSection("Character & Movement")
    MiscTab:CreateToggle({
        Name = "Custom WalkSpeed",
        CurrentValue = false,
        Flag = "PAE_CustomSpeed",
        Callback = function(v)
            State.CustomSpeed = v
            local hum = getHumanoid()
            if not v and hum then hum.WalkSpeed = 24 end
        end,
    })
    MiscTab:CreateSlider({
        Name = "WalkSpeed",
        Range = {16, 200},
        Increment = 2,
        Suffix = " studs/s",
        CurrentValue = 24,
        Flag = "PAE_WalkSpeed",
        Callback = function(v) State.WalkSpeed = v end,
    })
    MiscTab:CreateToggle({
        Name = "Custom JumpPower",
        CurrentValue = false,
        Flag = "PAE_CustomJump",
        Callback = function(v)
            State.CustomJump = v
            local hum = getHumanoid()
            if not v and hum then hum.JumpPower = 50 end
        end,
    })
    MiscTab:CreateSlider({
        Name = "JumpPower",
        Range = {50, 250},
        Increment = 5,
        Suffix = " studs/s",
        CurrentValue = 50,
        Flag = "PAE_JumpPower",
        Callback = function(v) State.JumpPower = v end,
    })
    MiscTab:CreateToggle({
        Name = "Noclip",
        CurrentValue = false,
        Flag = "PAE_Noclip",
        Callback = function(v) State.Noclip = v end,
    })
    MiscTab:CreateToggle({
        Name = "Anti-AFK",
        CurrentValue = true,
        Flag = "PAE_AntiAFK",
        Callback = function(v) State.AntiAFK = v end,
    })

    MiscTab:CreateSection("Server Utilities")
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
    --  TAB SORTING
    ----------------------------------------------------------------
    pcall(function()
        if type(Window.SortTabs) == "function" then
            Window:SortTabs({"Overview", "Farm", "Steal", "Visuals", "Teleports", "Misc", "Settings"})
        end
    end)

    ----------------------------------------------------------------
    --  CLEANUP
    ----------------------------------------------------------------
    local function destroy()
        if destroyed then return end
        destroyed = true
        State.AutoTrain = false
        State.AutoCollectCash = false
        State.AutoRebirth = false
        State.AutoBuyDumbell = false
        State.AutoHatchReady = false
        State.AutoSteal = false
        State.EggESP = false

        clearAllESP()

        for _, conn in ipairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
        table.clear(Connections)

        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = 24
            hum.JumpPower = 50
        end

        pcall(function()
            local env = getgenv()
            if env.__RAVEN_PULL_AN_EGG and env.__RAVEN_PULL_AN_EGG.Settings == State then
                env.__RAVEN_PULL_AN_EGG = nil
            end
        end)
    end

    getgenv().__RAVEN_PULL_AN_EGG = {
        Version = "v1.0.0",
        Settings = State,
        StealEgg = stealEgg,
        GetAvailableEggs = getAvailableEggs,
        Destroy = destroy,
    }

    if runtimeInfo and type(runtimeInfo.registerCleanup) == "function" then
        runtimeInfo.registerCleanup(destroy)
    end
end
