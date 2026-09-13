--[[
    RAVEN HUB Module - Steal Fish Eggs v1.9.0
    Game: Steal Fish Eggs (PlaceId: 99183404085821, GameId: 10718240577)
    Developer: fishy fish fish!

    v1.9.0 — Multi-Select Egg Rarities & Ultra Lag-Free ESP Engine:
    - Multi-Select Auto Steal Rarities: Select any combination of rarities to steal simultaneously
    - Multi-Select ESP Rarities: Filter ESP display to any subset of egg rarities
    - Lag-Free ESP Engine:
        * Behind-Camera Dot Product Culling (skips 70%+ of projection matrix calls)
        * Squared Distance Culling (avoids math.sqrt calculation on off-range objects)
        * Immutable Metadata Cache (displayName, rarity, colors cached once per egg)
        * Throttled String Formatting (updates .Text only on distance change/timer, preventing GC spikes)
    - Auto Equip Best Fish: Native EquipBestFish hook with instant hatch detection
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
    --  FORWARD DECLARATIONS (PREVENTS NIL CALL ERRORS)
    ----------------------------------------------------------------
    local abortSteal
    local exitTreadPool
    local getOwnTreadPool
    local getBaseDepositZone
    local safeCrossTheLine
    local hopTeleport
    local glideTo
    local runTreadPoolFarm

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
        ["Rare"] = Color3.fromRGB(80, 170, 255),
        ["Epic"] = Color3.fromRGB(185, 75, 255),
        ["Legendary"] = Color3.fromRGB(255, 215, 0),
        ["Mythic"] = Color3.fromRGB(255, 60, 60),
        ["Abyssal"] = Color3.fromRGB(0, 235, 200),
        ["Astral"] = Color3.fromRGB(255, 120, 220),
        ["Default"] = Color3.fromRGB(255, 255, 255),
    }

    ----------------------------------------------------------------
    --  EXACT AUDITED BIOME EGG NEST COORDINATES
    ----------------------------------------------------------------
    local BiomePositions = {
        ["Coral Reef"] = Vector3.new(12.0, 120.2, -116.4),
        ["Deep Ocean"] = Vector3.new(67.4, 117.6, -266.7),
        ["Pearl Lagoon"] = Vector3.new(65.6, 117.3, -451.1),
        ["Snowy Sea"] = Vector3.new(8.3, 117.4, -708.1),
        ["Volcanic Sea"] = Vector3.new(86.7, 117.4, -1034.8),
        ["Jelly Ocean"] = Vector3.new(7.0, 117.7, -1439.3),
        ["Sunken Ruins"] = Vector3.new(55.9, 117.4, -1864.5),
        ["Atlantis"] = Vector3.new(-0.4, 117.3, -2426.9),
    }

    ----------------------------------------------------------------
    --  STATE
    ----------------------------------------------------------------
    local State = {
        AutoSteal = false,
        MinRarity = "Basic",
        TargetRarities = {
            Basic = true,
            Rare = true,
            Epic = true,
            Legendary = true,
            Mythic = true,
            Abyssal = true,
            Astral = true,
        },
        TargetPriority = "Highest Value (Kg)",
        UndergroundTravel = true,
        StealSpeed = 240,
        AutoReturnBase = true,
        AutoTreadPool = false,
        IdleTreadPool = true,
        AutoEquipBest = true,

        -- Guard Defense Suite
        GuardSafeCorridor = true,
        ChaserDodger = false,
        AntiRagdoll = true,
        MuteChaserAlerts = true,

        EggESP = true,
        EggESPRarity = "Basic",
        EggESPRarities = {
            Basic = true,
            Rare = true,
            Epic = true,
            Legendary = true,
            Mythic = true,
            Abyssal = true,
            Astral = true,
        },
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
    local isIdleTraining = false
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
        local bases = Workspace:FindFirstChild("Bases")
        if not bases then return nil end
        local myBaseName = LP:GetAttribute("BaseName")
        if myBaseName then
            local found = bases:FindFirstChild(myBaseName)
            if found then return found end
        end
        for _, b in ipairs(bases:GetChildren()) do
            local owner = b:GetAttribute("OwnerUserId") or b:GetAttribute("Owner")
            if owner == LP.UserId or owner == LP.Name then
                return b
            end
        end
        return nil
    end

    getOwnTreadPool = function()
        local ltp = Workspace:FindFirstChild("LocalTreadPools")
        if ltp then
            local own = ltp:FindFirstChild("OwnTreadPool")
            if own then return own end
        end
        local tp = Workspace:FindFirstChild("TreadPools")
        if tp then
            local myBaseName = LP:GetAttribute("BaseName")
            if myBaseName and tp:FindFirstChild(myBaseName) then
                return tp:FindFirstChild(myBaseName)
            end
        end
        return nil
    end

    getBaseDepositZone = function()
        local myBase = getMyBase()
        if not myBase then return nil end
        local epz = myBase:FindFirstChild("EggPlacementZone")
        if epz then
            return epz.Position + Vector3.new(0, 3, 0)
        end
        local tank = myBase:FindFirstChild("Tank")
        if tank then
            local prim = tank.PrimaryPart or tank:FindFirstChildWhichIsA("BasePart")
            if prim then return prim.Position + Vector3.new(0, 3, 0) end
        end
        local spawnPart = myBase:FindFirstChild("SpawnPoint") or myBase:FindFirstChild("Spawn")
        return spawnPart and spawnPart.Position or nil
    end

    safeCrossTheLine = function()
        local linePart = Workspace:FindFirstChild("TheLinePart", true)
        local root = getRoot()
        if linePart and root then
            if firetouchinterest then
                firetouchinterest(root, linePart, 0)
                task.wait(0.04)
                firetouchinterest(root, linePart, 1)
            end
        end
    end

    ----------------------------------------------------------------
    --  RAPID SKY GLIDE & HOP TELEPORT
    ----------------------------------------------------------------
    glideTo = function(targetPos, isCancelRequested, customSpeed)
        local root = getRoot()
        if not root or not targetPos then return false end

        local hum = getHumanoid()
        if hum then
            pcall(function()
                hum.PlatformStand = false
                hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            end)
        end

        local startPos = root.Position
        local delta = (targetPos - startPos)
        local dist = delta.Magnitude
        if dist < 1.5 then
            root.CFrame = CFrame.new(targetPos)
            root.AssemblyLinearVelocity = Vector3.zero
            return true
        end

        local speed = customSpeed or State.StealSpeed or 240
        local dur = math.max(0.04, dist / speed)

        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bv.Velocity = Vector3.zero
        bv.Parent = root

        local lookDir = dist > 0.1 and delta.Unit or Vector3.new(0, 0, -1)
        local t0 = os.clock()

        while (os.clock() - t0) < dur do
            if isCancelRequested and isCancelRequested() then
                bv:Destroy()
                return false
            end
            if isDestroyed or not isAlive() then
                bv:Destroy()
                return false
            end

            local elapsed = os.clock() - t0
            local alpha = math.clamp(elapsed / dur, 0, 1)
            local cur = startPos:Lerp(targetPos, alpha)
            root.CFrame = CFrame.lookAt(cur, cur + lookDir)
            root.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.015)
        end

        bv:Destroy()
        if isAlive() then
            root.CFrame = CFrame.new(targetPos)
            root.AssemblyLinearVelocity = Vector3.zero
        end
        return true
    end

    hopTeleport = function(targetPos)
        local root = getRoot()
        if not root or not targetPos then return end

        abortSteal()
        safeCrossTheLine()
        task.wait(0.05)

        glideTo(targetPos)
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

    abortSteal = function()
        State.AutoSteal = false
        stopActiveTween()
        if stealThread then
            pcall(task.cancel, stealThread)
            stealThread = nil
        end
        isStealing = false
    end

    exitTreadPool = function()
        State.AutoTreadPool = false
        isIdleTraining = false
        stopActiveTween()

        local myBase = getMyBase()
        local spawnPart = myBase and myBase:FindFirstChild("SpawnPoint")
        local root = getRoot()
        local hum = getHumanoid()

        if root and spawnPart then
            root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
        end
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        task.wait(0.1)
        pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("TreadPools") and ReplicatedStorage.TreadPools:FindFirstChild("TreadPoolRemote")
            if remote then remote:FireServer("Stop") end
        end)
    end

    runTreadPoolFarm = function()
        if not isAlive() or isStealing or isDestroyed then return end

        -- Never jump to TreadPool if player is carrying an egg!
        if LP:GetAttribute("CarryingEgg") then return end

        local tread = getOwnTreadPool()
        local act = tread and tread:FindFirstChild("ActivationPart")
        local root = getRoot()

        if not act or not root then return end

        local isTraining = LP:GetAttribute("TreadPoolTraining")
        if not isTraining then
            root.CFrame = act.CFrame * CFrame.new(0, 1, 0)
            task.wait(0.3)
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
    --  EGG ESP (ULTRA LAG-FREE WITH FAST CULLING & METADATA CACHE)
    ----------------------------------------------------------------
    local eggMetaCache = {}

    local function getEggMeta(egg)
        local cached = eggMetaCache[egg]
        if cached then return cached end

        local rarity = egg:GetAttribute("Rarity") or "Basic"
        local displayName = egg:GetAttribute("DisplayName") or egg.Name
        local kg = tonumber(egg:GetAttribute("Kg")) or 0
        local col = RarityColors[rarity] or RarityColors.Default
        local mut = egg:GetAttribute("Mutation") or egg:GetAttribute("FishMutation") or egg:GetAttribute("Buff")
        local buffTag = ""
        if mut then
            buffTag = string.format(" [%s]", tostring(mut):upper())
        end

        local baseLabel = string.format("[%s]%s %s (%.0f kg)", rarity, buffTag, displayName, kg)
        cached = {
            rarity = rarity,
            col = col,
            baseLabel = baseLabel,
        }
        eggMetaCache[egg] = cached
        return cached
    end

    local function updateEggESP(now)
        if not State.EggESP or not hasDrawing or isDestroyed then
            clearDrawingGroup(DrawingObjects.Eggs)
            return
        end

        local root = getRoot()
        if not root then return end

        now = now or os.clock()
        local maxDist = State.EggESPDistance
        local maxDistSq = maxDist * maxDist
        local rootPos = root.Position

        local camCFrame = Camera.CFrame
        local camPos = camCFrame.Position
        local camLook = camCFrame.LookVector

        local selectedRarities = State.EggESPRarities
        local seen = {}

        local function processEggESP(egg, isDropped)
            local prim = egg:FindFirstChild("PrimaryPart") or egg.PrimaryPart
            if not prim then return end

            local meta = getEggMeta(egg)
            if selectedRarities and not selectedRarities[meta.rarity] then
                if DrawingObjects.Eggs[egg] then
                    DrawingObjects.Eggs[egg].text.Visible = false
                end
                return
            end

            seen[egg] = true
            local pos = prim.Position

            -- 1. Fast Distance Culling (Squared distance avoids math.sqrt)
            local dx = pos.X - rootPos.X
            local dy = pos.Y - rootPos.Y
            local dz = pos.Z - rootPos.Z
            local distSq = dx * dx + dy * dy + dz * dz
            if distSq > maxDistSq then
                if DrawingObjects.Eggs[egg] then
                    DrawingObjects.Eggs[egg].text.Visible = false
                end
                return
            end

            -- 2. Behind Camera Culling (Fast Dot Product skips 70%+ of projection matrix calls)
            local camDx = pos.X - camPos.X
            local camDy = pos.Y - camPos.Y
            local camDz = pos.Z - camPos.Z
            if (camDx * camLook.X + camDy * camLook.Y + camDz * camLook.Z) <= 0 then
                if DrawingObjects.Eggs[egg] then
                    DrawingObjects.Eggs[egg].text.Visible = false
                end
                return
            end

            -- 3. WorldToViewportPoint only for in-front, in-range objects
            local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
            if not onScreen then
                if DrawingObjects.Eggs[egg] then
                    DrawingObjects.Eggs[egg].text.Visible = false
                end
                return
            end

            -- 4. Get or create drawing
            local entry = DrawingObjects.Eggs[egg]
            if not entry then
                entry = {
                    text = createDrawing("Text", {
                        Size = 13,
                        Center = true,
                        Outline = true,
                        OutlineColor = Color3.fromRGB(0, 0, 0),
                        Color = meta.col,
                    }),
                    lastTextUpdate = 0,
                    lastDist = -999,
                    lastStatus = "",
                }
                DrawingObjects.Eggs[egg] = entry
            end

            local txt = entry.text
            if not txt then return end

            -- 5. Screen Position Update
            txt.Position = Vector2.new(screenPos.X, screenPos.Y)
            txt.Visible = true

            -- 6. Throttled text content updates (Prevents GC spikes & frame drops)
            local dist = math.floor(math.sqrt(distSq))
            local isBusy = egg:GetAttribute("PromptBusy") == true
            local statusTag = isDropped and " [DROPPED]" or (isBusy and " [BUSY]" or "")

            if (now - entry.lastTextUpdate) >= 0.2 or math.abs(dist - entry.lastDist) >= 4 or statusTag ~= entry.lastStatus then
                entry.lastTextUpdate = now
                entry.lastDist = dist
                entry.lastStatus = statusTag
                txt.Text = string.format("%s%s [%dm]", meta.baseLabel, statusTag, dist)
            end
        end

        local spawned = Workspace:FindFirstChild("SpawnedEggs")
        if spawned then
            for _, egg in ipairs(spawned:GetChildren()) do
                processEggESP(egg, false)
            end
        end

        local dropped = Workspace:FindFirstChild("DroppedFishEggs")
        if dropped then
            for _, egg in ipairs(dropped:GetChildren()) do
                processEggESP(egg, true)
            end
        end

        for egg, entry in pairs(DrawingObjects.Eggs) do
            if not seen[egg] or not egg.Parent then
                destroyDrawing(entry.text)
                DrawingObjects.Eggs[egg] = nil
                eggMetaCache[egg] = nil
            end
        end
    end

    ----------------------------------------------------------------
    --  PLAYER ESP (OPTIMIZED)
    ----------------------------------------------------------------
    local function updatePlayerESP(now)
        if not State.PlayerESP or not hasDrawing or isDestroyed then
            clearDrawingGroup(DrawingObjects.Players)
            return
        end

        local root = getRoot()
        if not root then return end

        now = now or os.clock()
        local maxDist = State.ESPDistance
        local maxDistSq = maxDist * maxDist
        local rootPos = root.Position

        local camCFrame = Camera.CFrame
        local camPos = camCFrame.Position
        local camLook = camCFrame.LookVector

        local seen = {}

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LP and player.Character then
                local pRoot = player.Character:FindFirstChild("HumanoidRootPart")
                local pHum = player.Character:FindFirstChildOfClass("Humanoid")
                if pRoot and pHum and pHum.Health > 0 then
                    local pos = pRoot.Position
                    local dx = pos.X - rootPos.X
                    local dy = pos.Y - rootPos.Y
                    local dz = pos.Z - rootPos.Z
                    local distSq = dx * dx + dy * dy + dz * dz

                    if distSq <= maxDistSq then
                        local camDx = pos.X - camPos.X
                        local camDy = pos.Y - camPos.Y
                        local camDz = pos.Z - camPos.Z
                        if (camDx * camLook.X + camDy * camLook.Y + camDz * camLook.Z) > 0 then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                            if onScreen then
                                seen[player] = true
                                local entry = DrawingObjects.Players[player]
                                if not entry then
                                    entry = {
                                        text = createDrawing("Text", {
                                            Size = 13,
                                            Center = true,
                                            Outline = true,
                                            OutlineColor = Color3.fromRGB(0, 0, 0),
                                        }),
                                        lastUpdate = 0,
                                        lastText = "",
                                    }
                                    DrawingObjects.Players[player] = entry
                                end

                                if entry.text then
                                    entry.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                    entry.text.Visible = true

                                    if (now - entry.lastUpdate) >= 0.2 then
                                        entry.lastUpdate = now
                                        local carrying = player:GetAttribute("CarryingEgg")
                                        local label = player.DisplayName
                                        if carrying then
                                            label = "[CARRYING EGG] " .. label
                                        end
                                        local dist = math.floor(math.sqrt(distSq))
                                        entry.text.Text = string.format("%s [%dm]", label, dist)
                                        entry.text.Color = carrying and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(255, 255, 255)
                                    end
                                end
                            elseif DrawingObjects.Players[player] then
                                DrawingObjects.Players[player].text.Visible = false
                            end
                        elseif DrawingObjects.Players[player] then
                            DrawingObjects.Players[player].text.Visible = false
                        end
                    elseif DrawingObjects.Players[player] then
                        destroyDrawing(DrawingObjects.Players[player].text)
                        DrawingObjects.Players[player] = nil
                    end
                end
            end
        end

        for player, entry in pairs(DrawingObjects.Players) do
            if not seen[player] or not player.Parent then
                destroyDrawing(entry.text)
                DrawingObjects.Players[player] = nil
            end
        end
    end

    ----------------------------------------------------------------
    --  CHASER FISH RADAR / ESP (OPTIMIZED)
    ----------------------------------------------------------------
    local function updateChaserESP(now)
        if not State.ChaserESP or not hasDrawing or isDestroyed then
            clearDrawingGroup(DrawingObjects.Chasers)
            return
        end

        local root = getRoot()
        if not root then return end

        now = now or os.clock()
        local maxDist = State.ESPDistance
        local maxDistSq = maxDist * maxDist
        local rootPos = root.Position

        local camCFrame = Camera.CFrame
        local camPos = camCFrame.Position
        local camLook = camCFrame.LookVector

        local seen = {}
        local chaserFolder = Workspace:FindFirstChild("ActiveChaserFishes")
        if chaserFolder then
            for _, chaser in ipairs(chaserFolder:GetChildren()) do
                local kraken = chaser:FindFirstChild("KRAKEN") or chaser:FindFirstChildWhichIsA("BasePart")
                if kraken then
                    local pos = kraken.Position
                    local dx = pos.X - rootPos.X
                    local dy = pos.Y - rootPos.Y
                    local dz = pos.Z - rootPos.Z
                    local distSq = dx * dx + dy * dy + dz * dz

                    if distSq <= maxDistSq then
                        local camDx = pos.X - camPos.X
                        local camDy = pos.Y - camPos.Y
                        local camDz = pos.Z - camPos.Z
                        if (camDx * camLook.X + camDy * camLook.Y + camDz * camLook.Z) > 0 then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                            if onScreen then
                                seen[chaser] = true
                                local entry = DrawingObjects.Chasers[chaser]
                                if not entry then
                                    entry = {
                                        text = createDrawing("Text", {
                                            Size = 14,
                                            Center = true,
                                            Outline = true,
                                            OutlineColor = Color3.fromRGB(0, 0, 0),
                                        }),
                                        lastUpdate = 0,
                                    }
                                    DrawingObjects.Chasers[chaser] = entry
                                end

                                if entry.text then
                                    entry.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                    entry.text.Visible = true

                                    if (now - entry.lastUpdate) >= 0.2 then
                                        entry.lastUpdate = now
                                        local aggro = chaser:GetAttribute("ChaserAggroActive")
                                        local speed = math.floor(chaser:GetAttribute("ChaserCurrentSwimSpeed") or 0)
                                        local dist = math.floor(math.sqrt(distSq))
                                        entry.text.Text = string.format("[GUARD %s] Spd:%d [%dm]", aggro and "AGGRO!" or "Calm", speed, dist)
                                        entry.text.Color = aggro and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(255, 160, 40)
                                    end
                                end
                            elseif DrawingObjects.Chasers[chaser] then
                                DrawingObjects.Chasers[chaser].text.Visible = false
                            end
                        elseif DrawingObjects.Chasers[chaser] then
                            DrawingObjects.Chasers[chaser].text.Visible = false
                        end
                    elseif DrawingObjects.Chasers[chaser] then
                        destroyDrawing(DrawingObjects.Chasers[chaser].text)
                        DrawingObjects.Chasers[chaser] = nil
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
    --  AUTO STEAL ENGINE (HIGH-SPEED & DIRECT PLACE REMOTE ACTIVATION)
    ----------------------------------------------------------------
    local function getEggQuality(egg)
        local rarity = egg:GetAttribute("Rarity") or "Basic"
        local rawRank = RarityRanks[rarity] or 1
        local kg = tonumber(egg:GetAttribute("Kg")) or 0
        local scale = tonumber(egg:GetAttribute("Scale")) or 1.0

        -- Detect Buff / Mutation on egg
        local buffMult = 1.0
        local buffName = ""
        local mut = egg:GetAttribute("Mutation") or egg:GetAttribute("FishMutation") or egg:GetAttribute("Buff")
        if mut then
            local s = tostring(mut):lower()
            if s:find("rainbow") then
                buffMult = 4.0
                buffName = "Rainbow"
            elseif s:find("silver") then
                buffMult = 3.0
                buffName = "Silver"
            elseif s:find("gold") then
                buffMult = 1.3
                buffName = "Gold"
            else
                buffMult = 2.0
                buffName = tostring(mut)
            end
        else
            for _, desc in ipairs(egg:GetChildren()) do
                local n = desc.Name:lower()
                if n:find("rainbow") then
                    buffMult = 4.0
                    buffName = "Rainbow"
                    break
                elseif n:find("silver") then
                    buffMult = 3.0
                    buffName = "Silver"
                    break
                elseif n:find("gold") then
                    buffMult = 1.3
                    buffName = "Gold"
                    break
                end
            end
        end

        return {
            rarity = rarity,
            rawRank = rawRank,
            buffMult = buffMult,
            buffName = buffName,
            kg = kg,
            scale = scale
        }
    end

    local function getBestEgg()
        local root = getRoot()
        local spawned = Workspace:FindFirstChild("SpawnedEggs")
        local dropped = Workspace:FindFirstChild("DroppedFishEggs")
        if not root then return nil end

        local minRank = RarityRanks[State.MinRarity] or 1
        local candidates = {}

        -- 1. Check Dropped fish eggs (STRICT: only add if matching target rarities!)
        if dropped then
            for _, egg in ipairs(dropped:GetChildren()) do
                local prim = egg:FindFirstChild("PrimaryPart") or egg.PrimaryPart
                -- Note: Do NOT require prompt.Enabled here because EggWaterAnimations disables prompts when >500 studs away!
                if prim and not egg:GetAttribute("PromptBusy") then
                    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
                    local q = getEggQuality(egg)
                    local dist = (root.Position - prim.Position).Magnitude

                    -- STRICT: Only collect dropped eggs that match chosen rarities!
                    local isTarget = false
                    if State.TargetRarities then
                        isTarget = (State.TargetRarities[q.rarity] == true)
                    else
                        isTarget = (q.rawRank >= minRank)
                    end

                    if isTarget then
                        table.insert(candidates, {
                            egg = egg,
                            prim = prim,
                            prompt = prompt,
                            q = q,
                            dist = dist,
                            isDropped = true
                        })
                    end
                end
            end
        end

        -- 2. Check regular spawned eggs in nests
        if spawned then
            for _, egg in ipairs(spawned:GetChildren()) do
                local prim = egg:FindFirstChild("PrimaryPart") or egg.PrimaryPart
                -- Note: Do NOT require prompt.Enabled here because EggWaterAnimations disables prompts when >500 studs away!
                if prim and not egg:GetAttribute("PromptBusy") then
                    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
                    local q = getEggQuality(egg)
                    local dist = (root.Position - prim.Position).Magnitude

                    -- STRICT: Only add if meeting chosen target rarities!
                    local isTarget = false
                    if State.TargetRarities then
                        isTarget = (State.TargetRarities[q.rarity] == true)
                    else
                        isTarget = (q.rawRank >= minRank)
                    end

                    if isTarget then
                        table.insert(candidates, {
                            egg = egg,
                            prim = prim,
                            prompt = prompt,
                            q = q,
                            dist = dist,
                            isDropped = false
                        })
                    end
                end
            end
        end

        -- ZERO FALLBACK: If no eggs match the chosen rarity, return nil immediately!
        if #candidates == 0 then
            return nil
        end

        -- Smart Best Egg Sorting:
        -- Within same rarity tier: Buff (Rainbow>Silver>Gold) -> Highest Kg -> Largest Scale -> Closest
        table.sort(candidates, function(a, b)
            -- Priority 1: Recover dropped eggs first if of high tier
            if a.isDropped ~= b.isDropped then
                return a.isDropped
            end

            -- Priority 2: Higher tier first (e.g. Astral > Abyssal > Mythic)
            if a.q.rawRank ~= b.q.rawRank then
                return a.q.rawRank > b.q.rawRank
            end

            -- Priority 3: IN THE SAME RARITY TIER:
            -- 3a. If one has Buff / Mutation, prioritize it!
            if a.q.buffMult ~= b.q.buffMult then
                return a.q.buffMult > b.q.buffMult
            end

            -- 3b. If user chose Highest Value (or default), prioritize highest weight/size
            if State.TargetPriority == "Highest Value (Kg)" then
                if a.q.kg ~= b.q.kg then
                    return a.q.kg > b.q.kg
                elseif a.q.scale ~= b.q.scale then
                    return a.q.scale > b.q.scale
                else
                    return a.dist < b.dist
                end
            else
                -- Closest Distance mode
                if a.dist ~= b.dist then
                    return a.dist < b.dist
                elseif a.q.kg ~= b.q.kg then
                    return a.q.kg > b.q.kg
                else
                    return a.q.scale > b.q.scale
                end
            end
        end)

        return candidates[1]
    end

    local function humanWalkTo(targetPos, isCancel, timeout)
        local root = getRoot()
        local hum = getHumanoid()
        if not root or not hum then return false end

        timeout = timeout or 3.5
        local t0 = os.clock()

        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.Running)

        while (os.clock() - t0) < timeout do
            if isCancel and isCancel() then return false end
            if isDestroyed or not isAlive() then return false end

            local curPos = root.Position
            local dist2D = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(curPos.X, 0, curPos.Z)).Magnitude
            if dist2D < 2.0 then
                return true
            end

            hum:MoveTo(targetPos)
            task.wait(0.04)
        end
        return true
    end

    local UNDERGROUND_Y = 45

    local function passThroughSafeGate(isCancel)
        local root = getRoot()
        local hum = getHumanoid()
        if not root then return false end

        local lineFolder = Workspace:FindFirstChild("TheLine")
        local linePart = lineFolder and lineFolder:FindFirstChild("TheLinePart")

        local rootPos = root.Position
        local gateX = linePart and linePart.Position.X or 27.7
        local gateZ = linePart and linePart.Position.Z or -41.8

        -- If player is on ocean side (Z < -35), must cross Safe Zone gate cleanly to register safe return
        if rootPos.Z < -35 then
            -- If still out in deep ocean (Z < -65):
            if rootPos.Z < -65 then
                if State.UndergroundTravel then
                    glideTo(Vector3.new(gateX, UNDERGROUND_Y, -62), isCancel, State.StealSpeed)
                    if isCancel and isCancel() then return false end
                    -- Resurface smoothly right before the gate (ขึ้นมาก่อนถึงประตู)
                    glideTo(Vector3.new(gateX, 119.2, -60), isCancel, 180)
                    if isCancel and isCancel() then return false end
                else
                    glideTo(Vector3.new(gateX, 130, -65), isCancel, State.StealSpeed)
                    if isCancel and isCancel() then return false end
                    glideTo(Vector3.new(gateX, 119.2, -60), isCancel, 120)
                    if isCancel and isCancel() then return false end
                end
            elseif rootPos.Y < 115 then
                -- Resurface to floor level right before the red line
                glideTo(Vector3.new(gateX, 119.2, -60), isCancel, 180)
                if isCancel and isCancel() then return false end
            end

            root.AssemblyLinearVelocity = Vector3.zero

            -- HUMAN WALK across the gate!
            -- Native Humanoid walk across RedPart (Z = -55) and through TheLinePart (Z = -41.8) to Lobby (Z = -25)
            local safeLobbyTarget = Vector3.new(gateX, 119.2, -25)
            if hum then
                hum.PlatformStand = false
                hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end

            humanWalkTo(safeLobbyTarget, isCancel, 3.5)
            if isCancel and isCancel() then return false end

            task.wait(0.15)
        else
            -- If heading out from base into ocean, glide cleanly through gate to start of ocean
            glideTo(Vector3.new(gateX, 119.2, -55), isCancel, State.StealSpeed)
            if isCancel and isCancel() then return false end
        end
        return true
    end
    safeCrossTheLine = passThroughSafeGate

    local function getEggTools()
        local tools = {}
        local char = getCharacter()
        if char then
            for _, item in ipairs(char:GetChildren()) do
                if item:IsA("Tool") and (item:GetAttribute("EggType") ~= nil or (item:GetAttribute("Scale") ~= nil and item:GetAttribute("Kg") ~= nil) or item.Name:lower():find("egg")) then
                    table.insert(tools, { item = item, inChar = true })
                end
            end
        end
        for _, item in ipairs(LP.Backpack:GetChildren()) do
            if item:IsA("Tool") and (item:GetAttribute("EggType") ~= nil or (item:GetAttribute("Scale") ~= nil and item:GetAttribute("Kg") ~= nil) or item.Name:lower():find("egg")) then
                table.insert(tools, { item = item, inChar = false })
            end
        end
        return tools
    end

    local function depositEggAtBase(isCancel)
        local root = getRoot()
        local myBase = getMyBase()
        local epz = myBase and myBase:FindFirstChild("EggPlacementZone")
        local placeEggRemote = ReplicatedStorage:FindFirstChild("EggSystem") and ReplicatedStorage.EggSystem:FindFirstChild("PlaceEgg")

        if not root or not myBase or not epz or not placeEggRemote then return end

        local targetPos = epz.Position + Vector3.new(0, 3, 0)

        -- 1. Must pass through Safe Zone gate (TheLinePart) FIRST to register safe arrival and lock the egg!
        passThroughSafeGate(isCancel)
        if isCancel and isCancel() then return end

        -- 2. Once safely through the gate, warp into base EggPlacementZone
        glideTo(targetPos, isCancel)
        if isCancel and isCancel() then return end

        -- 3. Wait briefly (up to 2.0s) for the server to grant/register the Egg Tool after crossing TheLine
        local char = getCharacter()
        local epzCFrame = epz.CFrame
        local epzSize = epz.Size

        local tWait = os.clock()
        while (os.clock() - tWait) < 2.0 do
            if isCancel and isCancel() then return end
            local currentTools = getEggTools()
            if #currentTools > 0 then break end
            task.wait(0.15)
        end

        -- 4. Equip each stolen egg tool from backpack or character and place into the tank!
        local eggTools = getEggTools()
        for _, entry in ipairs(eggTools) do
            if isCancel and isCancel() then return end
            local item = entry.item
            if item and item.Parent then
                if not entry.inChar then
                    item.Parent = char
                    task.wait(0.2)
                end

                -- Calculate safe placement point on EggPlacementZone top surface
                local randX = (math.random() - 0.5) * (epzSize.X * 0.7)
                local randZ = (math.random() - 0.5) * (epzSize.Z * 0.7)
                local placePoint = epzCFrame:PointToWorldSpace(Vector3.new(randX, epzSize.Y * 0.5, randZ))

                placeEggRemote:FireServer(placePoint)
                task.wait(0.35)
            end
        end

        -- 5. Auto Hatch any eggs that are ready in base
        local hatchEggRemote = ReplicatedStorage:FindFirstChild("EggSystem") and ReplicatedStorage.EggSystem:FindFirstChild("HatchEgg")
        if hatchEggRemote then
            local placedEggs = Workspace:FindFirstChild("PlacedEggs")
            if placedEggs then
                for _, placed in ipairs(placedEggs:GetChildren()) do
                    if placed:GetAttribute("OwnerUserId") == LP.UserId and placed:GetAttribute("HatchReady") == true then
                        hatchEggRemote:FireServer(placed)
                        task.wait(0.2)
                    end
                end
            end
        end

        -- 6. Auto Equip Best Fish: Uses game's native EquipBestFish remote to equip highest CPS fish into tank!
        local equipBestRemote = ReplicatedStorage:FindFirstChild("FishSystem") and ReplicatedStorage.FishSystem:FindFirstChild("EquipBestFish")
        if equipBestRemote then
            pcall(function()
                equipBestRemote:FireServer()
            end)
        end
    end

    local function runStealCycle()
        if isStealing or not State.AutoSteal or not isAlive() then return end
        isStealing = true

        local isCancel = function()
            return not State.AutoSteal or isDestroyed or not isAlive()
        end

        local success, err = pcall(function()
            local root = getRoot()
            if not root then return end

            -- 1. Check if already carrying an egg -> Deposit it first
            if LP:GetAttribute("CarryingEgg") then
                depositEggAtBase(isCancel)
                return
            end

            if isCancel() then return end

            -- 2. Target top priority egg
            local target = getBestEgg()

            -- IDLE FALLBACK: No matching eggs found -> Go to TreadPool and train!
            if not target then
                if State.IdleTreadPool and not isCancel() and not LP:GetAttribute("CarryingEgg") then
                    if not isIdleTraining then
                        isIdleTraining = true
                        runTreadPoolFarm()
                    end
                end
                task.wait(1.0)
                return
            end

            -- Egg found! If we were idle training, exit TreadPool immediately!
            if isIdleTraining then
                exitTreadPool()
                task.wait(0.2)
            end

            if isCancel() then return end

            -- 3. Validate ocean entry
            safeCrossTheLine(isCancel)
            if isCancel() then return end

            -- 4. Travel to egg via Subterranean Flight (ดำดิน @ Y=45)
            local eggTargetPos = target.prim.Position + Vector3.new(0, 1.2, 0)
            local curPos = root.Position
            local reached = false

            if State.UndergroundTravel then
                -- 4a. Plunge subterranean immediately (ดำดิน)
                glideTo(Vector3.new(curPos.X, UNDERGROUND_Y, curPos.Z), isCancel, 320)
                if isCancel() then return end

                -- 4b. Fly underground directly under the target egg at full configured speed
                glideTo(Vector3.new(eggTargetPos.X, UNDERGROUND_Y, eggTargetPos.Z), isCancel, State.StealSpeed)
                if isCancel() then return end

                -- 4c. Resurface straight up into the egg nest
                local approachPos = target.prim.Position + Vector3.new(0, 1.2, 2.4)
                reached = glideTo(approachPos, isCancel, 180)
            else
                local approachPos = target.prim.Position + Vector3.new(0, 1.2, 2.4)
                reached = glideTo(approachPos, isCancel, State.StealSpeed)
            end

            if not reached or isCancel() then return end

            -- 5. Face the egg precisely
            root.CFrame = CFrame.lookAt(root.Position, target.prim.Position)
            task.wait(0.2)
            if isCancel() then return end

            -- 6. Trigger capture hold
            local prompt = target.prompt
            if not prompt or not prompt.Parent or not prompt.Enabled then
                prompt = target.egg:FindFirstChildWhichIsA("ProximityPrompt", true)
            end
            if not prompt or not prompt.Enabled then
                -- Wait a split second for client distance un-culling to re-enable prompt
                task.wait(0.2)
                prompt = target.egg:FindFirstChildWhichIsA("ProximityPrompt", true)
            end

            if prompt and prompt.Parent then
                if fireproximityprompt then
                    pcall(fireproximityprompt, prompt, 0)
                end
                task.wait(0.04)
                prompt:InputHoldBegin()
                local holdTime = prompt.HoldDuration or 1
                local elapsed = 0
                local targetHoldTime = math.max(1.8, holdTime + 0.4)

                while elapsed < targetHoldTime and not LP:GetAttribute("CarryingEgg") do
                    task.wait(0.05)
                    elapsed += 0.05
                    if isCancel() then
                        prompt:InputHoldEnd()
                        return
                    end
                end
                prompt:InputHoldEnd()
            end

            -- 7. Subterranean Return Flight (ดำดิน @ Y=45) & Resurface before gate
            if LP:GetAttribute("CarryingEgg") and State.AutoReturnBase then
                local holdPos = root.Position
                local lineFolder = Workspace:FindFirstChild("TheLine")
                local linePart = lineFolder and lineFolder:FindFirstChild("TheLinePart")
                local gateX = linePart and linePart.Position.X or 27.7

                if State.UndergroundTravel and holdPos.Z < -65 then
                    -- 7a. Plunge subterranean immediately (ดำดิน) at high speed (350 studs/s)
                    glideTo(Vector3.new(holdPos.X, UNDERGROUND_Y, holdPos.Z), isCancel, 350)
                    if isCancel() then return end

                    -- 7b. Fly underground directly to pre-gate coordinate (Z = -62)
                    glideTo(Vector3.new(gateX, UNDERGROUND_Y, -62), isCancel, State.StealSpeed)
                    if isCancel() then return end

                    -- 7c. Resurface smoothly right before the gate (ขึ้นมาก่อนถึงประตู) at Z = -60, Y = 119.2
                    glideTo(Vector3.new(gateX, 119.2, -60), isCancel, 180)
                    if isCancel() then return end
                    root.AssemblyLinearVelocity = Vector3.zero
                elseif holdPos.Z < -75 then
                    -- Ceiling fallback if UndergroundTravel is disabled
                    glideTo(Vector3.new(holdPos.X, 155, holdPos.Z), isCancel, 250)
                    if isCancel() then return end
                    local safeX = math.clamp(holdPos.X, -25, 25)
                    glideTo(Vector3.new(safeX, 155, -75), isCancel)
                    if isCancel() then return end
                end

                depositEggAtBase(isCancel)
            end

            -- 8. Dropped Egg Recovery: If egg was slapped out of hand mid-transit, immediately recover it!
            if not LP:GetAttribute("CarryingEgg") and not isCancel() then
                local droppedFolder = Workspace:FindFirstChild("DroppedFishEggs")
                if droppedFolder and #droppedFolder:GetChildren() > 0 then
                    task.defer(runStealCycle)
                end
            end
        end)

        if not success and err then
            warn("[RAVEN / StealFishEggs] Steal cycle error: " .. tostring(err))
        end

        isStealing = false
    end

    ----------------------------------------------------------------
    --  AUTO EQUIP BEST FISH
    ----------------------------------------------------------------
    local function runAutoEquipBest()
        if not State.AutoEquipBest or isDestroyed then return end
        local now = os.clock()
        if now - lastBestFishCheck >= 5 then
            lastBestFishCheck = now
            pcall(function()
                local equipRemote = ReplicatedStorage.FishSystem:FindFirstChild("EquipBestFish")
                if equipRemote then
                    equipRemote:FireServer()
                end
            end)
        end
    end

    -- Instant hook: Whenever any fish hatches, auto equip best immediately
    pcall(function()
        local fishHatchReward = ReplicatedStorage:FindFirstChild("FishSystem") and ReplicatedStorage.FishSystem:FindFirstChild("FishHatchReward")
        if fishHatchReward and fishHatchReward:IsA("RemoteEvent") then
            connect(fishHatchReward.OnClientEvent, function()
                if State.AutoEquipBest and not isDestroyed then
                    task.delay(0.5, function()
                        pcall(function()
                            local equipRemote = ReplicatedStorage.FishSystem:FindFirstChild("EquipBestFish")
                            if equipRemote then
                                equipRemote:FireServer()
                            end
                        end)
                    end)
                end
            end)
        end
    end)

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
    --  MAIN TICK LOOP (GUARD DEFENSE & SURVEILLANCE)
    ----------------------------------------------------------------
    local espAccum = 0
    connect(RunService.Heartbeat, function(dt)
        if isDestroyed then return end

        -- 1. Anti-Ragdoll & Anti-Knockback Guard Defense
        if State.AntiRagdoll then
            local hum = getHumanoid()
            local root = getRoot()
            if hum and root then
                if LP:GetAttribute("Ragdolled") or hum:GetState() == Enum.HumanoidStateType.PlatformStanding or hum:GetState() == Enum.HumanoidStateType.Physics or hum.PlatformStand then
                    hum.PlatformStand = false
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    root.AssemblyLinearVelocity = Vector3.zero
                    pcall(function() LP:SetAttribute("Ragdolled", false) end)
                end
            end
        end

        -- 2. Auto Chaser Dodger (In-Water Evade)
        if State.ChaserDodger and not isStealing and not LP:GetAttribute("CarryingEgg") then
            local root = getRoot()
            local chasers = Workspace:FindFirstChild("ActiveChaserFishes")
            if root and chasers and root.Position.Y < 155 then
                for _, ch in ipairs(chasers:GetChildren()) do
                    local kraken = ch:FindFirstChild("KRAKEN") or ch:FindFirstChildWhichIsA("BasePart")
                    if kraken then
                        local dist = (root.Position - kraken.Position).Magnitude
                        if dist < 20 then
                            -- Dodge within OceanWater without leaving water boundary (max 158)
                            root.CFrame = CFrame.new(root.Position.X, 158, root.Position.Z)
                            root.AssemblyLinearVelocity = Vector3.zero
                            break
                        end
                    end
                end
            end
        end

        -- 3. Mute Chaser Visuals / Red Siren Pulse
        if State.MuteChaserAlerts then
            local visuals = Workspace:FindFirstChild("LocalChaserFishVisuals")
            if visuals then
                for _, v in ipairs(visuals:GetChildren()) do
                    v:Destroy()
                end
            end
        end

        -- 4. ESP Updates (Butter-smooth position tracking & throttled text formatting)
        local now = os.clock()
        pcall(updateEggESP, now)
        pcall(updatePlayerESP, now)
        pcall(updateChaserESP, now)

        applyMovement()
        runAutoEquipBest()

        if State.AutoSteal and not isStealing then
            stealThread = task.spawn(runStealCycle)
        elseif State.AutoTreadPool and not State.AutoSteal then
            local now = os.clock()
            if now - lastTreadPoolCheck >= 1 then
                lastTreadPoolCheck = now
                task.spawn(runTreadPoolFarm)
            end
        end
    end)

    ----------------------------------------------------------------
    --  UI CONSTRUCTION (MacLib / Rayfield compatible)
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
                if isIdleTraining then exitTreadPool() end
            end
        end,
    })

    FarmTab:CreateToggle({
        Name = "Idle Fallback: Auto TreadPool",
        CurrentValue = true,
        Flag = "SFE_IdleTreadPool",
        Callback = function(v) State.IdleTreadPool = v end,
    })

    FarmTab:CreateDropdown({
        Name = "Target Egg Rarities",
        Options = {"Basic", "Rare", "Epic", "Legendary", "Mythic", "Abyssal", "Astral"},
        CurrentOption = {"Basic", "Rare", "Epic", "Legendary", "Mythic", "Abyssal", "Astral"},
        MultipleOptions = true,
        Flag = "SFE_TargetRarities",
        Callback = function(v)
            local map = {}
            if type(v) == "table" then
                for _, r in ipairs(v) do
                    map[tostring(r)] = true
                end
            elseif v then
                map[tostring(v)] = true
            end
            State.TargetRarities = map
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Target Priority Mode",
        Options = {"Highest Value (Kg)", "Closest Distance"},
        CurrentOption = "Highest Value (Kg)",
        Flag = "SFE_TargetPriority",
        Callback = function(v)
            local selected = type(v) == "table" and v[1] or v
            State.TargetPriority = tostring(selected)
        end,
    })

    FarmTab:CreateSlider({
        Name = "Flight Speed",
        Range = {100, 500},
        Increment = 10,
        Suffix = " speed",
        CurrentValue = 240,
        Flag = "SFE_StealSpeed",
        Callback = function(v) State.StealSpeed = v end,
    })

    FarmTab:CreateToggle({
        Name = "Subterranean Flight (ดำดิน @ Y=45)",
        CurrentValue = true,
        Flag = "SFE_UndergroundTravel",
        Callback = function(v) State.UndergroundTravel = v end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Return to Base & Place",
        CurrentValue = true,
        Flag = "SFE_AutoReturnBase",
        Callback = function(v) State.AutoReturnBase = v end,
    })

    FarmTab:CreateSection("Guard Defense (Anti-Chaser)")
    FarmTab:CreateToggle({
        Name = "Guard Safe Corridor (Sky Flight)",
        CurrentValue = true,
        Flag = "SFE_GuardSafeCorridor",
        Callback = function(v) State.GuardSafeCorridor = v end,
    })

    FarmTab:CreateToggle({
        Name = "Auto Chaser Dodger (In-Water Evade)",
        CurrentValue = true,
        Flag = "SFE_ChaserDodger",
        Callback = function(v) State.ChaserDodger = v end,
    })

    FarmTab:CreateToggle({
        Name = "Anti-Ragdoll & Anti-Knockback",
        CurrentValue = true,
        Flag = "SFE_AntiRagdoll",
        Callback = function(v) State.AntiRagdoll = v end,
    })

    FarmTab:CreateToggle({
        Name = "Mute Guard Screams & Red Pulse",
        CurrentValue = true,
        Flag = "SFE_MuteChaserAlerts",
        Callback = function(v) State.MuteChaserAlerts = v end,
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
        Name = "Auto Equip Best Fish",
        CurrentValue = true,
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
        Name = "Egg ESP Rarities",
        Options = {"Basic", "Rare", "Epic", "Legendary", "Mythic", "Abyssal", "Astral"},
        CurrentOption = {"Basic", "Rare", "Epic", "Legendary", "Mythic", "Abyssal", "Astral"},
        MultipleOptions = true,
        Flag = "SFE_EggESPRarities",
        Callback = function(v)
            local map = {}
            if type(v) == "table" then
                for _, r in ipairs(v) do
                    map[tostring(r)] = true
                end
            elseif v then
                map[tostring(v)] = true
            end
            State.EggESPRarities = map
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

    MoveTab:CreateSection("Quick Teleports (Anti-Rubberband)")
    MoveTab:CreateButton({
        Name = "Teleport: Own Base",
        Callback = function()
            abortSteal()
            if LP:GetAttribute("CarryingEgg") then
                depositEggAtBase()
            else
                passThroughSafeGate()
                local depositPos = getBaseDepositZone()
                local root = getRoot()
                if depositPos and root then
                    root.CFrame = CFrame.new(depositPos)
                end
            end
        end,
    })

    MoveTab:CreateButton({
        Name = "Teleport: TreadPool (Training)",
        Callback = function()
            abortSteal()
            local tread = getOwnTreadPool()
            local act = tread and tread:FindFirstChild("ActivationPart")
            local root = getRoot()
            if act and root then
                root.CFrame = act.CFrame * CFrame.new(0, 1, 0)
            end
        end,
    })

    for bName, bPos in pairs(BiomePositions) do
        MoveTab:CreateButton({
            Name = "Teleport: " .. bName,
            Callback = function()
                hopTeleport(bPos)
            end,
        })
    end

    ----------------------------------------------------------------
    --  CLEANUP / DESTROY HOOK
    ----------------------------------------------------------------
    local ModuleInstance = {
        State = State,
        getBestEgg = getBestEgg,
        runStealCycle = runStealCycle,
        runTreadPoolFarm = runTreadPoolFarm,
        hopTeleport = hopTeleport,
        glideTo = glideTo,
        getMyBase = getMyBase,
        getBaseDepositZone = getBaseDepositZone,
        depositEggAtBase = depositEggAtBase,
        passThroughSafeGate = passThroughSafeGate,
        safeCrossTheLine = passThroughSafeGate,
        humanWalkTo = humanWalkTo,
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
