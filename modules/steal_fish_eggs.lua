--[[
    RAVEN HUB Module - Steal Fish Eggs v1.1.0
    Game: Steal Fish Eggs (PlaceId: 99183404085821, GameId: 10718240577)
    Developer: fishy fish fish!

    v1.1.0 — Responsive State & Instant Abort:
    - Fixed toggle-off lingering bug (instant abort for AutoSteal, AutoTreadPool, ESP)
    - Interruptible tweening (50ms responsive polling with immediate activeTween:Cancel)
    - Clean thread cancellation (task.cancel on background workers)
    - Safe base spawn recovery when exiting TreadPool
    - Immediate Drawing API visual wipe on ESP disable
]]--

return function(Window, runtimeInfo)
    pcall(function()
        local prev = getgenv().__RAVEN_STEAL_FISH_EGGS
        if prev and type(prev.Destroy) == "function" then
            prev.Destroy()
        end
    end)

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local UserInputService = game:GetService("UserInputService")
    local VirtualUser = game:GetService("VirtualUser")
    local Workspace = game:GetService("Workspace")

    local LP = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

    ----------------------------------------------------------------
    --  RARITY DATA & COLORS
    ----------------------------------------------------------------
    local RarityRanks = {
        ["All"] = 0,
        ["Basic"] = 1,
        ["Rare"] = 2,
        ["Epic"] = 3,
        ["Legendary"] = 4,
        ["Mythic"] = 5,
        ["Abyssal"] = 6,
        ["Astral"] = 7,
    }

    local RarityColors = {
        ["Basic"] = Color3.fromRGB(180, 180, 180),
        ["Rare"] = Color3.fromRGB(50, 200, 255),
        ["Epic"] = Color3.fromRGB(180, 70, 255),
        ["Legendary"] = Color3.fromRGB(255, 170, 0),
        ["Mythic"] = Color3.fromRGB(255, 50, 80),
        ["Abyssal"] = Color3.fromRGB(20, 255, 180),
        ["Astral"] = Color3.fromRGB(255, 220, 80),
        ["Default"] = Color3.fromRGB(255, 255, 255),
    }

    ----------------------------------------------------------------
    --  STATE
    ----------------------------------------------------------------
    local State = {
        AutoSteal = false,
        MinRarity = "Basic",
        StealSpeed = 75,
        AutoReturnBase = true,
        AutoTreadPool = false,
        AutoEquipBest = false,
        EggESP = true,
        EggESPRarity = "Basic",
        EggESPDistance = 2500,
        PlayerESP = true,
        ChaserESP = true,
        ESPDistance = 2000,
        WalkSpeed = 38,
        CustomSpeedEnabled = false,
        InfiniteJump = false,
        AntiAFK = true,
    }

    local Connections = {}
    local DrawingObjects = {
        Eggs = {},
        Players = {},
        Chasers = {},
    }

    local isDestroyed = false
    local isStealing = false
    local activeTween = nil
    local stealThread = nil
    local lastBestFishCheck = 0
    local lastTreadPoolCheck = 0

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(Connections, conn)
        return conn
    end

    ----------------------------------------------------------------
    --  UTILITY FUNCTIONS
    ----------------------------------------------------------------
    local function getCharacter()
        return LP.Character or LP.CharacterAdded:Wait()
    end

    local function getRoot()
        local char = getCharacter()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid()
        local char = getCharacter()
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function isAlive()
        local hum = getHumanoid()
        return hum and hum.Health > 0
    end

    local function getMyBase()
        local baseName = LP:GetAttribute("BaseName")
        if baseName and Workspace.Bases:FindFirstChild(baseName) then
            return Workspace.Bases[baseName]
        end
        for _, base in ipairs(Workspace.Bases:GetChildren()) do
            if base:GetAttribute("OwnerUserId") == LP.UserId then
                return base
            end
        end
        return nil
    end

    local function getBaseDepositZone()
        local myBase = getMyBase()
        if myBase then
            local zone = myBase:FindFirstChild("EggPlacementZone")
            if zone then return zone.Position end
        end
        return nil
    end

    local function getOwnTreadPool()
        local ltp = Workspace:FindFirstChild("LocalTreadPools")
        if ltp and ltp:FindFirstChild("OwnTreadPool") then
            return ltp.OwnTreadPool
        end
        return nil
    end

    local function safeCrossTheLine()
        local root = getRoot()
        local lineFolder = Workspace:FindFirstChild("TheLine")
        local linePart = lineFolder and lineFolder:FindFirstChild("TheLinePart")
        if root and linePart then
            if type(firetouchinterest) == "function" then
                firetouchinterest(root, linePart, 0)
                task.wait(0.05)
                firetouchinterest(root, linePart, 1)
            end
        end
    end

    ----------------------------------------------------------------
    --  INTERRUPTIBLE TWEEN & CANCELLATION
    ----------------------------------------------------------------
    local function stopActiveTween()
        if activeTween then
            pcall(function()
                activeTween:Cancel()
            end)
            activeTween = nil
        end
    end

    local function tweenTo(targetPos, speedOverride, isCancelRequested)
        local root = getRoot()
        if not root or not targetPos then return false end

        local dist = (root.Position - targetPos).Magnitude
        if dist < 4 then return true end

        local speed = speedOverride or State.StealSpeed
        local duration = math.clamp(dist / speed, 0.1, 8.0)
        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)

        stopActiveTween()
        activeTween = TweenService:Create(root, tweenInfo, {
            CFrame = CFrame.new(targetPos + Vector3.new(0, 1.5, 0))
        })
        activeTween:Play()

        local elapsed = 0
        while elapsed < duration do
            task.wait(0.05)
            elapsed += 0.05

            -- Instant interrupt check
            if isCancelRequested and isCancelRequested() then
                stopActiveTween()
                return false
            end
            if isDestroyed or not isAlive() then
                stopActiveTween()
                return false
            end
        end

        stopActiveTween()
        return true
    end

    local function abortSteal()
        State.AutoSteal = false
        stopActiveTween()
        if stealThread then
            pcall(task.cancel, stealThread)
            stealThread = nil
        end
        isStealing = false
    end

    local function exitTreadPool()
        State.AutoTreadPool = false
        stopActiveTween()
        local myBase = getMyBase()
        local spawnPart = myBase and myBase:FindFirstChild("SpawnPoint")
        local root = getRoot()
        local hum = getHumanoid()

        if root and spawnPart then
            root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
        end
        pcall(function()
            LP:SetAttribute("TreadPoolTraining", false)
        end)
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            hum.Jump = true
        end
    end

    ----------------------------------------------------------------
    --  DRAWING API HELPERS
    ----------------------------------------------------------------
    local function createDrawing(dType, props)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, dType)
        if ok and obj then
            for k, v in pairs(props or {}) do
                pcall(function() obj[k] = v end)
            end
            return obj
        end
        return nil
    end

    local function destroyDrawing(obj)
        if obj then
            pcall(function()
                obj.Visible = false
                obj.Text = ""
                obj:Remove()
            end)
        end
    end

    local function clearDrawingGroup(group)
        for k, entry in pairs(group) do
            if type(entry) == "table" then
                for _, drawObj in pairs(entry) do
                    destroyDrawing(drawObj)
                end
            else
                destroyDrawing(entry)
            end
            group[k] = nil
        end
    end

    ----------------------------------------------------------------
    --  EGG ESP
    ----------------------------------------------------------------
    local function updateEggESP()
        if not State.EggESP or not hasDrawing or isDestroyed then
            clearDrawingGroup(DrawingObjects.Eggs)
            return
        end

        local root = getRoot()
        if not root then return end

        local minRank = RarityRanks[State.EggESPRarity] or 0
        local seen = {}

        local spawned = Workspace:FindFirstChild("SpawnedEggs")
        if spawned then
            for _, egg in ipairs(spawned:GetChildren()) do
                local prim = egg:FindFirstChild("PrimaryPart") or egg.PrimaryPart
                if prim then
                    seen[egg] = true
                    local pos = prim.Position
                    local dist = (root.Position - pos).Magnitude

                    local rarity = egg:GetAttribute("Rarity") or "Basic"
                    local eggRank = RarityRanks[rarity] or 1

                    if dist <= State.EggESPDistance and eggRank >= minRank then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                        local entry = DrawingObjects.Eggs[egg]
                        if not entry then
                            entry = {
                                text = createDrawing("Text", {
                                    Size = 13,
                                    Center = true,
                                    Outline = true,
                                    OutlineColor = Color3.fromRGB(0, 0, 0),
                                }),
                            }
                            DrawingObjects.Eggs[egg] = entry
                        end

                        if onScreen and entry.text then
                            local displayName = egg:GetAttribute("DisplayName") or egg.Name
                            local kg = egg:GetAttribute("Kg") or 0
                            local col = RarityColors[rarity] or RarityColors.Default

                            entry.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                            entry.text.Text = string.format("[%s] %s (%.0f kg) [%dm]", rarity, displayName, kg, math.floor(dist))
                            entry.text.Color = col
                            entry.text.Visible = true
                        elseif entry.text then
                            entry.text.Visible = false
                        end
                    else
                        if DrawingObjects.Eggs[egg] then
                            destroyDrawing(DrawingObjects.Eggs[egg].text)
                            DrawingObjects.Eggs[egg] = nil
                        end
                    end
                end
            end
        end

        for egg, entry in pairs(DrawingObjects.Eggs) do
            if not seen[egg] or not egg.Parent then
                destroyDrawing(entry.text)
                DrawingObjects.Eggs[egg] = nil
            end
        end
    end

    ----------------------------------------------------------------
    --  PLAYER ESP
    ----------------------------------------------------------------
    local function updatePlayerESP()
        if not State.PlayerESP or not hasDrawing or isDestroyed then
            clearDrawingGroup(DrawingObjects.Players)
            return
        end

        local root = getRoot()
        if not root then return end

        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP and plr.Character then
                local char = plr.Character
                local pHrp = char:FindFirstChild("HumanoidRootPart")
                local pHum = char:FindFirstChildOfClass("Humanoid")
                if pHrp and pHum and pHum.Health > 0 then
                    seen[plr] = true
                    local dist = (root.Position - pHrp.Position).Magnitude
                    if dist <= State.ESPDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(pHrp.Position)
                        local entry = DrawingObjects.Players[plr]
                        if not entry then
                            entry = {
                                text = createDrawing("Text", {
                                    Size = 13,
                                    Center = true,
                                    Outline = true,
                                    OutlineColor = Color3.fromRGB(0, 0, 0),
                                }),
                            }
                            DrawingObjects.Players[plr] = entry
                        end

                        if onScreen and entry.text then
                            local isCarrying = plr:GetAttribute("CarryingEgg")
                            local label = plr.DisplayName or plr.Name
                            local col = isCarrying and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 255, 255)
                            local carryTag = isCarrying and " [CARRYING]" or ""

                            entry.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                            entry.text.Text = string.format("%s%s [%dm]", label, carryTag, math.floor(dist))
                            entry.text.Color = col
                            entry.text.Visible = true
                        elseif entry.text then
                            entry.text.Visible = false
                        end
                    else
                        if DrawingObjects.Players[plr] then
                            destroyDrawing(DrawingObjects.Players[plr].text)
                            DrawingObjects.Players[plr] = nil
                        end
                    end
                end
            end
        end

        for plr, entry in pairs(DrawingObjects.Players) do
            if not seen[plr] or not plr.Parent then
                destroyDrawing(entry.text)
                DrawingObjects.Players[plr] = nil
            end
        end
    end

    ----------------------------------------------------------------
    --  CHASER FISH ESP
    ----------------------------------------------------------------
    local function updateChaserESP()
        if not State.ChaserESP or not hasDrawing or isDestroyed then
            clearDrawingGroup(DrawingObjects.Chasers)
            return
        end

        local root = getRoot()
        if not root then return end

        local seen = {}
        local chasersFolder = Workspace:FindFirstChild("ActiveChaserFishes")
        if chasersFolder then
            for _, chaser in ipairs(chasersFolder:GetChildren()) do
                local cPart = chaser:FindFirstChild("PrimaryPart") or chaser:FindFirstChildWhichIsA("BasePart")
                if cPart then
                    seen[chaser] = true
                    local dist = (root.Position - cPart.Position).Magnitude
                    if dist <= State.ESPDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(cPart.Position)
                        local entry = DrawingObjects.Chasers[chaser]
                        if not entry then
                            entry = {
                                text = createDrawing("Text", {
                                    Size = 13,
                                    Center = true,
                                    Outline = true,
                                    OutlineColor = Color3.fromRGB(0, 0, 0),
                                }),
                            }
                            DrawingObjects.Chasers[chaser] = entry
                        end

                        if onScreen and entry.text then
                            entry.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                            entry.text.Text = string.format("[!] CHASER FISH [%dm]", math.floor(dist))
                            entry.text.Color = Color3.fromRGB(255, 60, 60)
                            entry.text.Visible = true
                        elseif entry.text then
                            entry.text.Visible = false
                        end
                    else
                        if DrawingObjects.Chasers[chaser] then
                            destroyDrawing(DrawingObjects.Chasers[chaser].text)
                            DrawingObjects.Chasers[chaser] = nil
                        end
                    end
                end
            end
        end

        for chaser, entry in pairs(DrawingObjects.Chasers) do
            if not seen[chaser] or not chaser.Parent then
                destroyDrawing(entry.text)
                DrawingObjects.Chasers[chaser] = nil
            end
        end
    end

    ----------------------------------------------------------------
    --  AUTO STEAL ENGINE
    ----------------------------------------------------------------
    local function getBestEgg()
        local root = getRoot()
        if not root then return nil end

        local spawned = Workspace:FindFirstChild("SpawnedEggs")
        if not spawned then return nil end

        local minRank = RarityRanks[State.MinRarity] or 0
        local candidates = {}

        for _, egg in ipairs(spawned:GetChildren()) do
            local prim = egg:FindFirstChild("PrimaryPart") or egg.PrimaryPart
            local prompt = prim and prim:FindFirstChildOfClass("ProximityPrompt")
            if prim and prompt and not egg:GetAttribute("PromptBusy") then
                local rarity = egg:GetAttribute("Rarity") or "Basic"
                local rank = RarityRanks[rarity] or 1
                if rank >= minRank then
                    local kg = egg:GetAttribute("Kg") or 0
                    local dist = (root.Position - prim.Position).Magnitude
                    table.insert(candidates, {
                        egg = egg,
                        prim = prim,
                        prompt = prompt,
                        rank = rank,
                        kg = kg,
                        dist = dist,
                    })
                end
            end
        end

        if #candidates == 0 then return nil end

        table.sort(candidates, function(a, b)
            if a.rank ~= b.rank then
                return a.rank > b.rank
            elseif a.kg ~= b.kg then
                return a.kg > b.kg
            else
                return a.dist < b.dist
            end
        end)

        return candidates[1]
    end

    local function runStealCycle()
        if isStealing or not State.AutoSteal or not isAlive() then return end
        isStealing = true

        local isCancel = function()
            return not State.AutoSteal or isDestroyed or not isAlive()
        end

        local success, err = pcall(function()
            -- 1. Check if already carrying an egg
            if LP:GetAttribute("CarryingEgg") then
                local depositPos = getBaseDepositZone()
                if depositPos then
                    local reached = tweenTo(depositPos, State.StealSpeed, isCancel)
                    if reached and not isCancel() then
                        task.wait(1.0)
                    end
                end
                return
            end

            if isCancel() then return end

            -- 2. Validate ocean entry
            safeCrossTheLine()
            if isCancel() then return end

            -- 3. Target top priority egg
            local target = getBestEgg()
            if not target then
                task.wait(1.0)
                return
            end

            -- 4. Fly to egg with responsive abort
            local reached = tweenTo(target.prim.Position + Vector3.new(0, 1.2, 0), State.StealSpeed, isCancel)
            if not reached or isCancel() then return end

            -- 5. Wait briefly for prompt sync
            task.wait(0.35)
            if isCancel() then return end

            -- 6. Trigger capture hold
            if target.prompt and target.prompt.Parent then
                target.prompt:InputHoldBegin()
                local holdTime = target.prompt.HoldDuration or 1
                local elapsed = 0
                while elapsed < (holdTime + 0.2) do
                    task.wait(0.05)
                    elapsed += 0.05
                    if isCancel() then
                        target.prompt:InputHoldEnd()
                        return
                    end
                end
                target.prompt:InputHoldEnd()
            end

            task.wait(0.5)
            if isCancel() then return end

            -- 7. Return to base and deposit
            if LP:GetAttribute("CarryingEgg") and State.AutoReturnBase then
                local depositPos = getBaseDepositZone()
                if depositPos then
                    local reachedBase = tweenTo(depositPos, State.StealSpeed, isCancel)
                    if reachedBase and not isCancel() then
                        task.wait(1.0)
                    end
                end
            end
        end)

        if not success and err then
            warn("[RAVEN / StealFishEggs] Steal cycle error: " .. tostring(err))
        end

        isStealing = false
    end

    ----------------------------------------------------------------
    --  AUTO TREADPOOL (AFK SWIM SPEED FARM)
    ----------------------------------------------------------------
    local function runTreadPoolFarm()
        if not State.AutoTreadPool or not isAlive() or isStealing or isDestroyed then return end

        local tread = getOwnTreadPool()
        local act = tread and tread:FindFirstChild("ActivationPart")
        local root = getRoot()

        if not act or not root then return end

        local dist = (root.Position - act.Position).Magnitude
        local isTraining = LP:GetAttribute("TreadPoolTraining")

        if dist > 8 or not isTraining then
            root.CFrame = act.CFrame + Vector3.new(0, 1.5, 0)
            task.wait(0.3)
        end
    end

    ----------------------------------------------------------------
    --  AUTO EQUIP BEST FISH
    ----------------------------------------------------------------
    local function runAutoEquipBest()
        if not State.AutoEquipBest or isDestroyed then return end
        local now = os.clock()
        if now - lastBestFishCheck >= 10 then
            lastBestFishCheck = now
            pcall(function()
                local equipRemote = ReplicatedStorage.FishSystem:FindFirstChild("EquipBestFish")
                if equipRemote then
                    equipRemote:FireServer()
                end
            end)
        end
    end

    ----------------------------------------------------------------
    --  MOVEMENT & SPEED HOOK
    ----------------------------------------------------------------
    local function applyMovement()
        local hum = getHumanoid()
        if hum then
            if State.CustomSpeedEnabled then
                hum.WalkSpeed = State.WalkSpeed
            end
        end
    end

    connect(UserInputService.JumpRequest, function()
        if State.InfiniteJump and isAlive() then
            local hum = getHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    ----------------------------------------------------------------
    --  ANTI-AFK
    ----------------------------------------------------------------
    connect(LP.Idled, function()
        if State.AntiAFK then
            pcall(function()
                VirtualUser:Button2Down(Vector2.zero, Camera.CFrame)
                task.wait(1)
                VirtualUser:Button2Up(Vector2.zero, Camera.CFrame)
            end)
        end
    end)

    ----------------------------------------------------------------
    --  MAIN TICK LOOP
    ----------------------------------------------------------------
    local espAccum = 0
    connect(RunService.Heartbeat, function(dt)
        if isDestroyed then return end

        espAccum += dt
        if espAccum >= 0.1 then
            espAccum = 0
            pcall(updateEggESP)
            pcall(updatePlayerESP)
            pcall(updateChaserESP)
        end

        applyMovement()
        runAutoEquipBest()

        if State.AutoSteal and not isStealing then
            stealThread = task.spawn(runStealCycle)
        elseif State.AutoTreadPool and not State.AutoSteal then
            local now = os.clock()
            if now - lastTreadPoolCheck >= 2 then
                lastTreadPoolCheck = now
                task.spawn(runTreadPoolFarm)
            end
        end
    end)

    ----------------------------------------------------------------
    --  UI CONSTRUCTION (MacLib / Rayfield compatible)
    ----------------------------------------------------------------
    local FarmTab = Window:CreateTab("Farm", 4483362458)

    FarmTab:CreateSection("Auto Steal Eggs")
    FarmTab:CreateToggle({
        Name = "Auto Steal Best Eggs",
        CurrentValue = false,
        Flag = "SFE_AutoSteal",
        Callback = function(v)
            if v then
                State.AutoTreadPool = false
                State.AutoSteal = true
            else
                abortSteal()
            end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Minimum Egg Rarity",
        Options = {"Basic", "Rare", "Epic", "Legendary", "Mythic", "Abyssal", "Astral"},
        CurrentOption = "Basic",
        Flag = "SFE_MinRarity",
        Callback = function(v)
            local selected = type(v) == "table" and v[1] or v
            State.MinRarity = tostring(selected)
        end,
    })

    FarmTab:CreateSlider({
        Name = "Tween Flight Speed",
        Range = {30, 150},
        Increment = 5,
        Suffix = " studs/s",
        CurrentValue = 75,
        Flag = "SFE_StealSpeed",
        Callback = function(v) State.StealSpeed = v end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Return to Base & Place",
        CurrentValue = true,
        Flag = "SFE_AutoReturnBase",
        Callback = function(v) State.AutoReturnBase = v end,
    })

    FarmTab:CreateSection("AFK TreadPool Training")
    FarmTab:CreateToggle({
        Name = "Auto TreadPool (Infinite Swim Speed)",
        CurrentValue = false,
        Flag = "SFE_AutoTreadPool",
        Callback = function(v)
            if v then
                abortSteal()
                State.AutoTreadPool = true
                task.spawn(runTreadPoolFarm)
            else
                exitTreadPool()
            end
        end,
    })

    FarmTab:CreateSection("Automations")
    FarmTab:CreateToggle({
        Name = "Auto Equip Best Fish (Cash/s)",
        CurrentValue = false,
        Flag = "SFE_AutoEquipBest",
        Callback = function(v) State.AutoEquipBest = v end,
    })

    FarmTab:CreateButton({
        Name = "Equip Best Fish Now",
        Callback = function()
            pcall(function()
                ReplicatedStorage.FishSystem.EquipBestFish:FireServer()
            end)
        end,
    })

    local VisualTab = Window:CreateTab("Visuals", 4483362458)

    VisualTab:CreateSection("Drawing API ESP")
    VisualTab:CreateToggle({
        Name = "Egg ESP",
        CurrentValue = true,
        Flag = "SFE_EggESP",
        Callback = function(v)
            State.EggESP = v
            if not v then clearDrawingGroup(DrawingObjects.Eggs) end
        end,
    })

    VisualTab:CreateDropdown({
        Name = "Egg ESP Minimum Rarity",
        Options = {"Basic", "Rare", "Epic", "Legendary", "Mythic", "Abyssal", "Astral"},
        CurrentOption = "Basic",
        Flag = "SFE_EggESPRarity",
        Callback = function(v)
            local selected = type(v) == "table" and v[1] or v
            State.EggESPRarity = tostring(selected)
            clearDrawingGroup(DrawingObjects.Eggs)
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player ESP (Egg Carrier Highlight)",
        CurrentValue = true,
        Flag = "SFE_PlayerESP",
        Callback = function(v)
            State.PlayerESP = v
            if not v then clearDrawingGroup(DrawingObjects.Players) end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Chaser Fish Radar / ESP",
        CurrentValue = true,
        Flag = "SFE_ChaserESP",
        Callback = function(v)
            State.ChaserESP = v
            if not v then clearDrawingGroup(DrawingObjects.Chasers) end
        end,
    })

    VisualTab:CreateSlider({
        Name = "ESP Max Render Distance",
        Range = {300, 5000},
        Increment = 100,
        Suffix = " studs",
        CurrentValue = 2500,
        Flag = "SFE_ESPDistance",
        Callback = function(v)
            State.EggESPDistance = v
            State.ESPDistance = v
        end,
    })

    local MoveTab = Window:CreateTab("Movement", 4483362458)

    MoveTab:CreateSection("Character Mods")
    MoveTab:CreateToggle({
        Name = "Enable Custom WalkSpeed",
        CurrentValue = false,
        Flag = "SFE_CustomSpeed",
        Callback = function(v)
            State.CustomSpeedEnabled = v
            if not v then
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = 38 end
            end
        end,
    })

    MoveTab:CreateSlider({
        Name = "WalkSpeed",
        Range = {38, 150},
        Increment = 2,
        Suffix = " speed",
        CurrentValue = 38,
        Flag = "SFE_WalkSpeed",
        Callback = function(v)
            State.WalkSpeed = v
            if State.CustomSpeedEnabled then
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = v end
            end
        end,
    })

    MoveTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = false,
        Flag = "SFE_InfiniteJump",
        Callback = function(v) State.InfiniteJump = v end,
    })

    MoveTab:CreateToggle({
        Name = "Anti-AFK Protection",
        CurrentValue = true,
        Flag = "SFE_AntiAFK",
        Callback = function(v) State.AntiAFK = v end,
    })

    MoveTab:CreateSection("Quick Teleports")
    MoveTab:CreateButton({
        Name = "Teleport to Own Base",
        Callback = function()
            abortSteal()
            local depositPos = getBaseDepositZone()
            local root = getRoot()
            if depositPos and root then
                root.CFrame = CFrame.new(depositPos + Vector3.new(0, 3, 0))
            end
        end,
    })

    MoveTab:CreateButton({
        Name = "Teleport to TreadPool",
        Callback = function()
            abortSteal()
            local tread = getOwnTreadPool()
            local act = tread and tread:FindFirstChild("ActivationPart")
            local root = getRoot()
            if act and root then
                root.CFrame = act.CFrame + Vector3.new(0, 2, 0)
            end
        end,
    })

    local BiomePositions = {
        ["Coral Reef"] = Vector3.new(15.7, 117.0, -145.2),
        ["Jelly Ocean"] = Vector3.new(-120.5, 118.0, -560.8),
        ["Atlantis"] = Vector3.new(350.2, 118.5, -920.4),
        ["Snowy Sea"] = Vector3.new(-420.0, 119.0, -1250.0),
        ["Volcanic Sea"] = Vector3.new(510.5, 120.0, -1680.0),
        ["Pearl Lagoon"] = Vector3.new(160.0, 118.0, -320.0),
        ["Deep Ocean"] = Vector3.new(-280.0, 117.5, -780.0),
        ["Sunken Ruins"] = Vector3.new(220.0, 118.0, -1420.0),
    }

    for bName, bPos in pairs(BiomePositions) do
        MoveTab:CreateButton({
            Name = "Teleport: " .. bName,
            Callback = function()
                abortSteal()
                safeCrossTheLine()
                task.wait(0.1)
                local root = getRoot()
                if root then
                    root.CFrame = CFrame.new(bPos)
                end
            end,
        })
    end

    ----------------------------------------------------------------
    --  CLEANUP / DESTROY HOOK
    ----------------------------------------------------------------
    local ModuleInstance = {
        Destroy = function()
            isDestroyed = true
            abortSteal()
            exitTreadPool()

            for _, conn in ipairs(Connections) do
                pcall(function() conn:Disconnect() end)
            end
            table.clear(Connections)

            clearDrawingGroup(DrawingObjects.Eggs)
            clearDrawingGroup(DrawingObjects.Players)
            clearDrawingGroup(DrawingObjects.Chasers)

            local hum = getHumanoid()
            if hum then hum.WalkSpeed = 38 end

            getgenv().__RAVEN_STEAL_FISH_EGGS = nil
        end
    }

    getgenv().__RAVEN_STEAL_FISH_EGGS = ModuleInstance
    return ModuleInstance
end
