-- ═════════════════════════════════════════════════════════════════
-- Zoo Hatchers! 🥚 | RAVEN HUB Module v1.8.0
-- PlaceId: 126870639873289, 127715053457585 | GameId: 10690360998, 7181313677
-- Features: Auto Steal Best Eggs (Strict Jump Power Check | Auto-Unequip Clean Hands | Multi-Floor Filter | Buffs & Sizes | Backpack Stash Mode on Full Plot) | Auto Event (Fossils & Meteors) | Anti-Mob
-- ═════════════════════════════════════════════════════════════════

return function(Window, scriptInfo)
    local Players           = game:GetService("Players")
    local Workspace         = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService        = game:GetService("RunService")

    local LocalPlayer = Players.LocalPlayer
    local Remotes     = ReplicatedStorage:WaitForChild("Remotes", 15)

    local environment = getgenv and getgenv() or _G
    if type(environment.__RAVEN_ZOO_HATCHERS) == "table"
        and type(environment.__RAVEN_ZOO_HATCHERS.Destroy) == "function" then
        pcall(environment.__RAVEN_ZOO_HATCHERS.Destroy)
    end

    local running = true
    local threads = {}
    local connections = {}

    local function startThread(key, func)
        threads[key] = nil
        task.spawn(function()
            threads[key] = true
            func(function() return threads[key] == true and running end)
            threads[key] = nil
        end)
    end

    local function stopThread(key)
        threads[key] = nil
    end

    -- ═══════════ Settings ═══════════
    local settings = {
        autoStealBest     = false,
        allowedStages     = {}, -- Populated with all stages by default
        disableMobs       = true,
        antiRagdoll       = true,
        autoFarmFossils   = false,
        autoBuyFossilEggs = false,
        autoSquat         = false,
        autoClaim         = false,
        speedEnabled      = false,
        walkSpeed         = 32,
        selectedStage     = "Floor 10: Savannah",
    }

    local RARITY_SCORES = {
        Eternal   = 50000,
        Celestial = 30000,
        Divine    = 20000,
        Godly     = 10000,
        Secret    = 8000,
        Exclusive = 6000,
        Mythic    = 3000,
        Legendary = 1000,
        Epic      = 400,
        Rare      = 150,
        Uncommon  = 50,
        Common    = 10,
    }

    local STAGE_FLOOR_INDEX = {
        ["Meadow"]            = 1,
        ["Coral Reef"]        = 2,
        ["Winter"]            = 3,
        ["Desert"]            = 4,
        ["Crystal Mines"]     = 5,
        ["Jungle"]            = 6,
        ["Mystic Isles"]      = 7,
        ["Prehistoric"]       = 8,
        ["Celestial Heights"] = 9,
        ["Savannah"]          = 10,
    }

    local MUTATION_SCORES = {
        ["Gold"]          = 4000, -- 4x CPS, golden model
        ["Permafrost"]    = 3000, -- 3x CPS
        ["Comet"]         = 2000, -- 2x CPS
        ["Solar"]         = 1750, -- 1.75x CPS
        ["Shocked"]       = 1500, -- 1.5x CPS
        ["Purple Aurora"] = 1250, -- 1.25x CPS + Gold grant
    }

    local function getEggBuffScore(egg)
        local mutList = egg:GetAttribute("MutationList") or ""
        local evMut = egg:GetAttribute("EventMutation") or ""
        local score = 0
        local buffsFound = {}

        for mutName, mScore in pairs(MUTATION_SCORES) do
            if string.find(mutList, mutName) or string.find(evMut, mutName) then
                score = score + mScore
                table.insert(buffsFound, mutName)
            end
        end

        if #buffsFound == 0 and ((mutList ~= "" and mutList ~= "None") or (evMut ~= "" and evMut ~= "None")) then
            score = score + 1000
            table.insert(buffsFound, mutList ~= "" and mutList or evMut)
        end

        return score, table.concat(buffsFound, " + ")
    end

    local function getEggSizeCategory(sizeMult)
        sizeMult = tonumber(sizeMult) or 1
        if sizeMult >= 2.5 then
            return "Maximum (" .. string.format("%.2fx", sizeMult) .. ")"
        elseif sizeMult >= 1.5 then
            return "Huge (" .. string.format("%.2fx", sizeMult) .. ")"
        elseif sizeMult >= 1.05 then
            return "Large (" .. string.format("%.2fx", sizeMult) .. ")"
        elseif sizeMult < 0.99 then
            return "Smaller (" .. string.format("%.2fx", sizeMult) .. ")"
        else
            return "Normal (1.00x)"
        end
    end

    local function calculateEggScore(egg, stageName)
        local r = egg:GetAttribute("Rarity") or "Common"
        local rScore = RARITY_SCORES[r] or 10
        local stageIndex = STAGE_FLOOR_INDEX[stageName] or 1
        local sizeMult = tonumber(egg:GetAttribute("SizeMultiplier")) or 1
        local cpsMult = tonumber(egg:GetAttribute("CPSMultiplier")) or 1
        local buffScore, buffName = getEggBuffScore(egg)

        -- Size bonus: Huge (>=1.5) or Maximum (>=2.5) gives huge score boost!
        local sizeBonus = 0
        if sizeMult >= 2.5 then
            sizeBonus = 3000 * (sizeMult / 2.5)
        elseif sizeMult >= 1.5 then
            sizeBonus = 1500 * (sizeMult / 1.5)
        elseif sizeMult >= 1.05 then
            sizeBonus = 400 * sizeMult
        else
            sizeBonus = sizeMult * 50
        end

        -- Stage floor bonus: Floor 10 >> Floor 9 >> ... >> Floor 1
        local floorBonus = stageIndex * 2000

        -- Total composite score: High Rarity + High Floor + Mutations (Gold/Permafrost) + Size + CPS
        local totalScore = (rScore * 10) + floorBonus + buffScore + sizeBonus + (cpsMult * 200)

        return totalScore, {
            rarity = r,
            rarityScore = rScore,
            stage = stageName,
            floor = stageIndex,
            sizeMult = sizeMult,
            sizeCat = getEggSizeCategory(sizeMult),
            cpsMult = cpsMult,
            buffScore = buffScore,
            buffName = buffName,
            totalScore = totalScore,
        }
    end

    local STAGES_DATA = {
        { name = "Savannah",          floor = 10, label = "Floor 10: Savannah",         pos = Vector3.new(0, 4957, -1315) },
        { name = "Celestial Heights", floor = 9,  label = "Floor 9: Celestial Heights", pos = Vector3.new(-1, 3240, -1176) },
        { name = "Prehistoric",       floor = 8,  label = "Floor 8: Prehistoric",       pos = Vector3.new(0, 2053, -1041) },
        { name = "Mystic Isles",      floor = 7,  label = "Floor 7: Mystic Isles",      pos = Vector3.new(-1, 1408, -899) },
        { name = "Jungle",            floor = 6,  label = "Floor 6: Jungle",            pos = Vector3.new(-1, 911, -758) },
        { name = "Crystal Mines",     floor = 5,  label = "Floor 5: Crystal Mines",     pos = Vector3.new(-1, 546, -618) },
        { name = "Desert",            floor = 4,  label = "Floor 4: Desert",            pos = Vector3.new(-1, 260, -478) },
        { name = "Winter",            floor = 3,  label = "Floor 3: Winter",            pos = Vector3.new(0, 78, -337) },
        { name = "Coral Reef",        floor = 2,  label = "Floor 2: Coral Reef",        pos = Vector3.new(0, 20, -197) },
        { name = "Meadow",            floor = 1,  label = "Floor 1: Meadow",            pos = Vector3.new(-1, 3, -74) },
    }

    local STAGE_OPTIONS = {}
    for _, s in ipairs(STAGES_DATA) do
        table.insert(STAGE_OPTIONS, s.label)
        settings.allowedStages[s.name] = true
    end

    local function isStageAllowed(stageName)
        if not settings.allowedStages or next(settings.allowedStages) == nil then
            return false
        end
        return settings.allowedStages[stageName] == true
    end

    -- Recommended Jump Power definitions for each Area + Spawner
    local function unequipAllTools()
        pcall(function()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum:UnequipTools()
            end
        end)
    end

    local function setupCharacterUnequip(char)
        if not char then return end
        local conn = char.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and child:GetAttribute("IsEggTool") then
                task.defer(function()
                    task.wait(0.05)
                    unequipAllTools()
                end)
            end
        end)
        table.insert(connections, conn)
    end

    if LocalPlayer.Character then
        setupCharacterUnequip(LocalPlayer.Character)
    end
    local charAddedConn = LocalPlayer.CharacterAdded:Connect(setupCharacterUnequip)
    table.insert(connections, charAddedConn)

    local RECOMMENDED_JUMPS = {
        ["Coral Reef1"] = 60,
        ["Coral Reef2"] = 80,
        ["Winter1"] = 115,
        ["Winter2"] = 150,
        ["Desert1"] = 180,
        ["Desert2"] = 205,
        ["Crystal Mines1"] = 210,
        ["Crystal Mines2"] = 230,
        ["Jungle1"] = 245,
        ["Jungle2"] = 265,
        ["Mystic Isles1"] = 285,
        ["Mystic Isles2"] = 305,
        ["Prehistoric1"] = 325,
        ["Prehistoric2"] = 395,
        ["Celestial Heights1"] = 450,
        ["Celestial Heights2"] = 510,
        ["Savannah1"] = 575,
        ["Savannah2"] = 640,
    }

    local JUMP_POWER_GRACE = 25 -- NaturalSpawnJumpPowerGrace from Areas settings

    local function getPlayerJumpPower()
        local jp = LocalPlayer:FindFirstChild("JumpPower")
        if jp and jp:IsA("ValueBase") then
            return tonumber(jp.Value) or 50
        end
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        return hum and hum.JumpPower or 50
    end

    local function getEggRequiredJump(egg, stageName)
        local area = egg:GetAttribute("AreaName") or stageName or ""
        local spawner = egg:GetAttribute("SpawnerName") or "1"
        local key = tostring(area) .. tostring(spawner)
        local rec = RECOMMENDED_JUMPS[key] or 0
        local minReq = math.max(0, rec - JUMP_POWER_GRACE)
        return minReq, rec
    end

    local function canStealEgg(egg, stageName)
        local minReq = getEggRequiredJump(egg, stageName)
        local playerJump = getPlayerJumpPower()
        return playerJump >= minReq
    end

    local function getCharacter()
        return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    end

    local function getHRP()
        local char = getCharacter()
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getMyPlot()
        local plots = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Plots")
        if not plots then return nil end
        for _, plot in ipairs(plots:GetChildren()) do
            local owner = plot:GetAttribute("OwnerUserId") or (plot:FindFirstChild("Owner") and plot.Owner.Value)
            if owner == LocalPlayer.UserId or owner == LocalPlayer.Name then
                return plot
            end
        end
        return nil
    end

    local function getIncubatingCount(plot)
        local pe = plot and plot:FindFirstChild("PlacedEggs")
        return pe and #pe:GetChildren() or 0
    end

    local function getFragmentsCount()
        local f = LocalPlayer:FindFirstChild("Fragments")
        return f and f:IsA("IntValue") and f.Value or 0
    end

    local function getMeteorStatus()
        local map = Workspace:FindFirstChild("Map")
        if not map then return "Unknown" end
        local active = map:GetAttribute("MeteorShowerActive") == true
        if active then
            return "🔥 ACTIVE NOW! (Raining Fossils)"
        end
        local nextAt = tonumber(map:GetAttribute("NextMeteorShowerAt")) or 0
        local now = Workspace:GetServerTimeNow()
        local diff = math.max(0, math.floor(nextAt - now))
        local h = math.floor(diff / 3600)
        local m = math.floor((diff % 3600) / 60)
        local s = diff % 60
        return string.format("in %dh %dm %ds", h, m, s)
    end

    -- ═════════════════════════════════════════════════════════════════
    --   ANTI-MOB / GUARD IMMUNITY ENGINE
    -- ═════════════════════════════════════════════════════════════════
    local function disableGuards()
        if not settings.disableMobs then return end
        pcall(function()
            local map = Workspace:FindFirstChild("Map")
            if not map then return end

            local cg = map:FindFirstChild("ClientGuards")
            if cg then cg:Destroy() end
            local cs = map:FindFirstChild("ClientSkeletons")
            if cs then cs:Destroy() end
            map:SetAttribute("GuardStunnedUntil", 9999999999)
        end)
    end

    pcall(function()
        if hookmetamethod and not environment.__RAVEN_DROP_EGG_HOOKED then
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                if method == "FireServer" and tostring(self) == "DropEggRequest" then
                    return nil
                end
                return oldNamecall(self, ...)
            end)
            environment.__RAVEN_DROP_EGG_HOOKED = true
        end
    end)

    startThread("MobImmunity", function(isAlive)
        while isAlive() do
            if settings.disableMobs then
                disableGuards()
            end

            if settings.antiRagdoll then
                pcall(function()
                    local char = getCharacter()
                    local hum = char and char:FindFirstChildOfClass("Humanoid")
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if hum and hum.PlatformStand then
                        hum.PlatformStand = false
                        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                    if hrp and hrp.AssemblyLinearVelocity.Magnitude > 100 then
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                    end
                end)
            end
            task.wait(0.5)
        end
    end)

    pcall(function()
        local map = Workspace:FindFirstChild("Map")
        if map then
            local conn = map.ChildAdded:Connect(function(child)
                if settings.disableMobs and (child.Name == "ClientGuards" or child.Name == "ClientSkeletons") then
                    task.defer(function() child:Destroy() end)
                end
            end)
            table.insert(connections, conn)
        end
    end)

    -- ═════════════════════════════════════════════════════════════════
    --   STAGE TELEPORT ENGINE
    -- ═════════════════════════════════════════════════════════════════
    local function teleportToStageByLabel(label)
        local targetStage = nil
        for _, s in ipairs(STAGES_DATA) do
            if s.label == label or s.name == label or string.find(label, s.name) then
                targetStage = s
                break
            end
        end
        if not targetStage then return false end

        local hrp = getHRP()
        if not hrp then return false end

        disableGuards()

        local map = Workspace:FindFirstChild("Map")
        local stagesFolder = map and map:FindFirstChild("Stages")
        local stageModel = stagesFolder and stagesFolder:FindFirstChild(targetStage.name)

        if stageModel then
            local spawners = stageModel:FindFirstChild("Spawners")
            local p = spawners and (spawners:FindFirstChild("1") or spawners:FindFirstChildWhichIsA("BasePart", true))
            if not p then p = stageModel:FindFirstChildWhichIsA("BasePart", true) end
            if p then
                hrp.CFrame = CFrame.new(p.Position + Vector3.new(0, 4, 0))
                return true
            end
        end

        hrp.CFrame = CFrame.new(targetStage.pos)
        return true
    end

    -- ═════════════════════════════════════════════════════════════════
    --   EGG SCAN & STEAL ENGINE
    -- ═════════════════════════════════════════════════════════════════
    local function placeHeldEgg(myPlot)
        local char = getCharacter()
        if not char then return false end
        local humanoid = char:FindFirstChildOfClass("Humanoid")

        local eggTool = nil
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute("IsEggTool") then
                eggTool = t
                break
            end
        end
        if not eggTool then
            for _, t in ipairs(LocalPlayer.Backpack:GetChildren()) do
                if t:IsA("Tool") and t:GetAttribute("IsEggTool") then
                    eggTool = t
                    break
                end
            end
        end

        if not eggTool then return false end

        local eggId = eggTool:GetAttribute("EggId")
        local remote = Remotes and Remotes:FindFirstChild("PlaceEggRequest")
        if not remote or not eggId then return false end

        local rx = -145.0 + math.random(-8, 8)
        local rz = 60.0 + math.random(-8, 8)
        local groundPos = Vector3.new(rx, -2.0000019, rz)

        remote:FireServer(eggId, groundPos)
        task.wait(0.3)
        unequipAllTools()
        return true
    end

    local function getBestSpawnedEgg()
        local bestEgg = nil
        local bestScore = -1

        local stages = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Stages")
        if not stages then return nil end

        for _, st in ipairs(stages:GetChildren()) do
            -- Filter only stages selected by the user
            if isStageAllowed(st.Name) then
                local se = st:FindFirstChild("SpawnedEggs")
                if se then
                    for _, egg in ipairs(se:GetChildren()) do
                        local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
                        local root = egg:FindFirstChild("EggRoot") or egg:FindFirstChildWhichIsA("BasePart")
                        if prompt and root and prompt.Enabled then
                            -- Automatically validates player Jump Power vs egg requirement
                            if canStealEgg(egg, st.Name) then
                                local totalScore, meta = calculateEggScore(egg, st.Name)
                                if totalScore > bestScore then
                                    local minJump, recJump = getEggRequiredJump(egg, st.Name)
                                    bestScore = totalScore
                                    bestEgg = {
                                        model = egg,
                                        prompt = prompt,
                                        root = root,
                                        name = egg.Name,
                                        rarity = meta.rarity,
                                        cps = meta.cpsMult,
                                        sizeMult = meta.sizeMult,
                                        sizeCat = meta.sizeCat,
                                        buffScore = meta.buffScore,
                                        buffName = meta.buffName,
                                        stage = st.Name,
                                        floor = meta.floor,
                                        pos = root.Position,
                                        requiredJump = minJump,
                                        recJump = recJump,
                                        totalScore = totalScore
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
        return bestEgg
    end

    local function openReadyIncubatedEggs(myPlot)
        pcall(function()
            if not myPlot or not myPlot:FindFirstChild("PlacedEggs") then return end
            for _, egg in ipairs(myPlot.PlacedEggs:GetChildren()) do
                if egg:GetAttribute("HatchReady") == true then
                    local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and prompt.Enabled then
                        if fireproximityprompt then
                            fireproximityprompt(prompt, 0)
                        else
                            prompt:InputHoldBegin()
                            task.wait(prompt.HoldDuration + 0.05)
                            prompt:InputHoldEnd()
                        end
                        task.wait(0.2)
                    end
                end
            end
        end)
    end

    local function executeStealCycle(bestEgg, myPlot, hrp, shouldPlaceInPlot)
        if not bestEgg or not hrp then return false end

        local previousCFrame = hrp.CFrame
        disableGuards()

        -- 0. Ensure hands are completely empty before starting steal
        unequipAllTools()
        task.wait(0.05)

        -- 1. Teleport to target best egg position
        hrp.CFrame = CFrame.new(bestEgg.pos + Vector3.new(0, 1.5, 0))
        task.wait(0.15)

        -- Ensure hands are clean at egg
        unequipAllTools()

        -- 2. Pick up egg (Egg goes straight into Backpack / Character Inventory)
        if fireproximityprompt then
            fireproximityprompt(bestEgg.prompt, 0)
        else
            bestEgg.prompt:InputHoldBegin()
            task.wait(math.min(bestEgg.prompt.HoldDuration, 0.5) + 0.05)
            bestEgg.prompt:InputHoldEnd()
        end

        -- Active wait for egg arrival and immediately stash to backpack
        local t0 = tick()
        while tick() - t0 < 1.2 do
            local hasEgg = false
            local c = LocalPlayer.Character
            if c then
                for _, item in ipairs(c:GetChildren()) do
                    if item:IsA("Tool") and item:GetAttribute("IsEggTool") then
                        hasEgg = true
                        break
                    end
                end
            end
            if hasEgg then
                unequipAllTools()
                break
            end
            task.wait(0.08)
        end
        unequipAllTools()

        -- 3. Check condition: If Plot has space and shouldPlaceInPlot is true -> Deposit to Plot at Floor 1
        if shouldPlaceInPlot and myPlot then
            local detector = myPlot:FindFirstChild("Detector")
            local returnPos = detector and (detector.Position + Vector3.new(0, 4, 0)) or Vector3.new(-141.8, 5, 65.4)
            hrp.CFrame = CFrame.new(returnPos)
            task.wait(0.25)

            -- Place egg in incubator
            placeHeldEgg(myPlot)
            task.wait(0.3)

            -- Auto-open ready incubated eggs
            openReadyIncubatedEggs(myPlot)
            task.wait(0.2)

            unequipAllTools()

            -- Return to farming stage
            if settings.selectedStage then
                teleportToStageByLabel(settings.selectedStage)
            else
                hrp.CFrame = previousCFrame
            end
        else
            -- 4. PLOT IS FULL! Egg stays directly in Backpack!
            -- DO NOT WARP TO FLOOR 1! Stay or return to current farming stage!
            unequipAllTools()
            if settings.selectedStage then
                teleportToStageByLabel(settings.selectedStage)
            else
                hrp.CFrame = previousCFrame
            end
        end

        task.wait(0.1)
        unequipAllTools()
        return true
    end

    -- ═════════════════════════════════════════════════════════════════
    --   FOSSIL & METEOR EVENT ENGINE
    -- ═════════════════════════════════════════════════════════════════
    local function getBestSpawnedFossil()
        local stages = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Stages")
        if not stages then return nil end

        local hrp = getHRP()
        local myPos = hrp and hrp.Position or Vector3.zero
        local bestFossil = nil
        local minDistance = math.huge

        for _, s in ipairs(stages:GetChildren()) do
            local sf = s:FindFirstChild("SpawnedFossils")
            if sf then
                for _, f in ipairs(sf:GetChildren()) do
                    local p = f:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if p and p.Enabled then
                        local fPos = f:GetPivot().Position
                        local dist = (fPos - myPos).Magnitude
                        if dist < minDistance then
                            minDistance = dist
                            bestFossil = {
                                model = f,
                                prompt = p,
                                pos = fPos,
                                stage = s.Name,
                                name = f.Name
                            }
                        end
                    end
                end
            end
        end
        return bestFossil
    end

    local function runFossilCycle()
        local hrp = getHRP()
        if not hrp then return false end

        disableGuards()

        local carried = tonumber(LocalPlayer:GetAttribute("CarriedFossilCount")) or 0
        local pending = LocalPlayer:GetAttribute("PendingFossilName") or ""

        local fe = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("FossilEvent")
        local tableModel = fe and fe:FindFirstChild("Station") and fe.Station:FindFirstChild("ResearchTable")
        local placePrompt = tableModel and tableModel:FindFirstChildWhichIsA("ProximityPrompt", true)
        local tablePos = tableModel and tableModel:GetPivot().Position or Vector3.new(58, 2, -38)

        if pending ~= "" then
            hrp.CFrame = CFrame.new(tablePos + Vector3.new(0, 3, 3))
            task.wait(0.4)

            local startedAt = tonumber(LocalPlayer:GetAttribute("PendingFossilStartedAt")) or 0
            local now = Workspace:GetServerTimeNow()
            local elapsed = now - startedAt
            if elapsed < 8.5 then
                task.wait(8.5 - elapsed)
            end

            local fRemote = Remotes and Remotes:FindFirstChild("Fossil")
            if fRemote then
                fRemote:FireServer("Finish")
                task.wait(0.8)
            end
            return true
        end

        if carried > 0 then
            hrp.CFrame = CFrame.new(tablePos + Vector3.new(0, 3, 3))
            task.wait(0.4)

            if placePrompt then
                if fireproximityprompt then
                    fireproximityprompt(placePrompt, 0)
                else
                    placePrompt:InputHoldBegin()
                    task.wait(placePrompt.HoldDuration + 0.1)
                    placePrompt:InputHoldEnd()
                end
            end
            task.wait(0.5)

            task.wait(8.5)
            local fRemote = Remotes and Remotes:FindFirstChild("Fossil")
            if fRemote then
                fRemote:FireServer("Finish")
                task.wait(0.8)
            end
            return true
        end

        local best = getBestSpawnedFossil()
        if not best then return false end

        hrp.CFrame = CFrame.new(best.pos + Vector3.new(0, 2, 0))
        task.wait(0.3)

        if fireproximityprompt then
            fireproximityprompt(best.prompt, 0)
        else
            best.prompt:InputHoldBegin()
            task.wait(best.prompt.HoldDuration + 0.1)
            best.prompt:InputHoldEnd()
        end
        task.wait(0.4)

        hrp.CFrame = CFrame.new(tablePos + Vector3.new(0, 3, 3))
        task.wait(0.4)

        if placePrompt then
            if fireproximityprompt then
                fireproximityprompt(placePrompt, 0)
            else
                placePrompt:InputHoldBegin()
                task.wait(placePrompt.HoldDuration + 0.1)
                placePrompt:InputHoldEnd()
            end
        end
        task.wait(0.5)

        task.wait(8.5)
        local fRemote = Remotes and Remotes:FindFirstChild("Fossil")
        if fRemote then
            fRemote:FireServer("Finish")
            task.wait(0.8)
        end
        return true
    end

    local function buyFossiledEgg()
        local hrp = getHRP()
        local myPlot = getMyPlot()
        if not hrp or not myPlot then return false end

        local fe = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("FossilEvent")
        local eggStand = fe and fe:FindFirstChild("EggStand")
        local buyPrompt = eggStand and eggStand:FindFirstChildWhichIsA("ProximityPrompt", true)
        local standPos = eggStand and eggStand:GetPivot().Position or Vector3.new(49, 2, -42)

        hrp.CFrame = CFrame.new(standPos + Vector3.new(0, 3, 3))
        task.wait(0.3)

        if buyPrompt then
            if fireproximityprompt then
                fireproximityprompt(buyPrompt, 0)
            else
                buyPrompt:InputHoldBegin()
                task.wait(buyPrompt.HoldDuration + 0.1)
                buyPrompt:InputHoldEnd()
            end
        end
        task.wait(0.5)

        local detector = myPlot:FindFirstChild("Detector")
        local returnPos = detector and (detector.Position + Vector3.new(0, 4, 0)) or Vector3.new(-141.8, 5, 65.4)
        hrp.CFrame = CFrame.new(returnPos)
        task.wait(0.3)

        placeHeldEgg(myPlot)
        return true
    end

    -- ═════════════════════════════════════════════════════════════════
    --   UI TABS & CONTROLS
    -- ═════════════════════════════════════════════════════════════════

    -- ─── Tab 1: Auto Steal ───
    local StealTab = Window:CreateTab("Auto Steal", 10723346959)

    StealTab:CreateSection("👑 Auto Steal Best Eggs")

    local JumpStatusLabel = StealTab:CreateLabel("Player JumpPower: " .. tostring(getPlayerJumpPower()))
    local PlotStatusLabel = StealTab:CreateLabel("Plot Status: Scanning...")
    local BestEggStatusLabel = StealTab:CreateLabel("Target Egg: Scanning selected floors...")

    startThread("StealStatusTracker", function(isAlive)
        while isAlive() do
            pcall(function()
                if JumpStatusLabel and JumpStatusLabel.Set then
                    JumpStatusLabel:Set("Player JumpPower: " .. tostring(getPlayerJumpPower()))
                end
                local myPlot = getMyPlot()
                local incCount = myPlot and getIncubatingCount(myPlot) or 0
                if PlotStatusLabel and PlotStatusLabel.Set then
                    if incCount >= 8 then
                        PlotStatusLabel:Set(string.format("Plot Status: %d/8 (Full) 🎒 Collecting to Backpack only!", incCount))
                    else
                        PlotStatusLabel:Set(string.format("Plot Status: %d/8 (Incubating 🥚) -> Auto-placing in plot", incCount))
                    end
                end
                if BestEggStatusLabel and BestEggStatusLabel.Set then
                    local best = getBestSpawnedEgg()
                    if best then
                        local buffStr = best.buffName ~= "" and (" | " .. best.buffName) or ""
                        local modeStr = incCount >= 8 and " [Mode: Backpack Only]" or " [Mode: Plot Incubate]"
                        local txt = string.format("Best: %s [%s] @ %s (%s)%s%s", best.name, best.rarity, best.stage, best.sizeCat, buffStr, modeStr)
                        BestEggStatusLabel:Set(txt)
                    else
                        local count = 0
                        for _ in pairs(settings.allowedStages or {}) do count = count + 1 end
                        if count == 0 then
                            BestEggStatusLabel:Set("Target Egg: ⚠️ No floors selected! Select floors below.")
                        else
                            BestEggStatusLabel:Set("Target Egg: None reachable in selected floors")
                        end
                    end
                end
            end)
            task.wait(2)
        end
    end)

    StealTab:CreateToggle({
        Name = "Auto Steal Best Eggs (Loop)",
        CurrentValue = false,
        Flag = "ZH_AutoStealBest",
        Callback = function(val)
            settings.autoStealBest = val
            if val then
                startThread("AutoSteal", function(isAlive)
                    while isAlive() do
                        local myPlot = getMyPlot()
                        local hrp = getHRP()
                        local char = getCharacter()
                        local humanoid = char and char:FindFirstChildOfClass("Humanoid")

                        local incCount = myPlot and getIncubatingCount(myPlot) or 8
                        local plotHasSpace = (incCount < 8)

                        unequipAllTools()

                        -- Check if currently holding an egg tool
                        local holdingEgg = false
                        if char then
                            for _, c in ipairs(char:GetChildren()) do
                                if c:IsA("Tool") and c:GetAttribute("IsEggTool") then
                                    holdingEgg = true
                                    break
                                end
                            end
                        end

                        -- If plot has space and player has an unplaced egg, deposit it
                        if plotHasSpace and holdingEgg and myPlot and hrp then
                            local detector = myPlot:FindFirstChild("Detector")
                            local returnPos = detector and (detector.Position + Vector3.new(0, 4, 0)) or Vector3.new(-141.8, 5, 65.4)
                            hrp.CFrame = CFrame.new(returnPos)
                            task.wait(0.25)
                            placeHeldEgg(myPlot)
                            task.wait(0.3)
                            openReadyIncubatedEggs(myPlot)
                            task.wait(0.2)
                            unequipAllTools()
                            if settings.selectedStage then
                                teleportToStageByLabel(settings.selectedStage)
                            end
                        else
                            unequipAllTools()

                            -- Find the best egg in allowed floors
                            local best = getBestSpawnedEgg()
                            if best and hrp then
                                -- shouldPlaceInPlot = true ONLY when plot has space (< 8)
                                -- When plot is full (>= 8), shouldPlaceInPlot = false -> Keeps egg in backpack only without warping to Floor 1!
                                executeStealCycle(best, myPlot, hrp, plotHasSpace)
                            end
                        end

                        unequipAllTools()

                        -- If plot is full, periodically open ready eggs so slots can free up
                        if not plotHasSpace and myPlot then
                            openReadyIncubatedEggs(myPlot)
                        end

                        task.wait(1.5)
                    end
                end)
            else
                stopThread("AutoSteal")
            end
        end,
    })

    StealTab:CreateDropdown({
        Name = "Select Floors to Steal From",
        Options = STAGE_OPTIONS,
        CurrentOption = STAGE_OPTIONS,
        MultipleOptions = true,
        Flag = "ZH_AllowedFloors",
        Callback = function(selectedList)
            settings.allowedStages = {}
            if type(selectedList) == "table" then
                for _, label in ipairs(selectedList) do
                    for _, s in ipairs(STAGES_DATA) do
                        if s.label == label or s.name == label or string.find(label, s.name) then
                            settings.allowedStages[s.name] = true
                        end
                    end
                end
            end
        end,
    })

    StealTab:CreateButton({
        Name = "⚡ Steal Best Egg Instantly (Once)",
        Callback = function()
            unequipAllTools()
            local myPlot = getMyPlot()
            local hrp = getHRP()
            if not hrp then return end

            local incCount = myPlot and getIncubatingCount(myPlot) or 8
            local plotHasSpace = (incCount < 8)

            local best = getBestSpawnedEgg()
            if best then
                executeStealCycle(best, myPlot, hrp, plotHasSpace)
            end
            unequipAllTools()
        end,
    })

    StealTab:CreateSection("ℹ️ Smart Auto Steal Features")
    StealTab:CreateLabel("• Multi-Floor: Pick exactly which floors you want to steal from!")
    StealTab:CreateLabel("• Plot Full Detection: When plot is 8/8 full, collects straight to Backpack!")
    StealTab:CreateLabel("• No Floor 1 Warp on Full: Stays on your farming floor collecting eggs endlessly.")
    StealTab:CreateLabel("• Strict Jump Validation: Never targets eggs exceeding your current Jump Power!")
    StealTab:CreateLabel("• Clean Hands Engine: Auto-stashes eggs to Backpack so next steal never blocks!")

    StealTab:CreateSection("🛡️ Anti-Mob Protection")

    StealTab:CreateToggle({
        Name = "Disable Guard Mobs (God Mode)",
        CurrentValue = true,
        Flag = "ZH_DisableMobs",
        Callback = function(val)
            settings.disableMobs = val
            if val then disableGuards() end
        end,
    })

    StealTab:CreateToggle({
        Name = "Anti-Ragdoll / Anti-Fling",
        CurrentValue = true,
        Flag = "ZH_AntiRagdoll",
        Callback = function(val)
            settings.antiRagdoll = val
        end,
    })

    -- ─── Tab 2: Event (Fossils & Meteor Shower) ───
    local EventTab = Window:CreateTab("Event", 10723346959)

    EventTab:CreateSection("☄️ Meteor Shower & Fossil Status")

    local FragLabel = EventTab:CreateLabel("Fragments: " .. tostring(getFragmentsCount()))
    local MeteorLabel = EventTab:CreateLabel("Meteor Shower: " .. getMeteorStatus())

    startThread("EventStatusTracker", function(isAlive)
        while isAlive() do
            pcall(function()
                if FragLabel and FragLabel.Set then
                    FragLabel:Set("Fragments: " .. tostring(getFragmentsCount()))
                end
                if MeteorLabel and MeteorLabel.Set then
                    MeteorLabel:Set("Meteor Shower: " .. getMeteorStatus())
                end
            end)
            task.wait(1)
        end
    end)

    EventTab:CreateSection("🦴 Fossil Automation (Dig -> Clean -> Fragments)")

    EventTab:CreateToggle({
        Name = "Auto Farm Fossils (Dig & Clean)",
        CurrentValue = false,
        Flag = "ZH_AutoFarmFossils",
        Callback = function(val)
            settings.autoFarmFossils = val
            if val then
                startThread("AutoFarmFossils", function(isAlive)
                    while isAlive() do
                        runFossilCycle()
                        task.wait(1.5)
                    end
                end)
            else
                stopThread("AutoFarmFossils")
            end
        end,
    })

    EventTab:CreateToggle({
        Name = "Auto Buy Fossiled Egg (at 500 Frags)",
        CurrentValue = false,
        Flag = "ZH_AutoBuyFossilEggs",
        Callback = function(val)
            settings.autoBuyFossilEggs = val
            if val then
                startThread("AutoBuyFossilEggs", function(isAlive)
                    while isAlive() do
                        local frags = getFragmentsCount()
                        if frags >= 500 then
                            local myPlot = getMyPlot()
                            if myPlot and getIncubatingCount(myPlot) < 8 then
                                buyFossiledEgg()
                            end
                        end
                        task.wait(3)
                    end
                end)
            else
                stopThread("AutoBuyFossilEggs")
            end
        end,
    })

    EventTab:CreateSection("⚡ Instant Actions")

    EventTab:CreateButton({
        Name = "⛏️ Dig & Clean 1 Nearest Fossil (Once)",
        Callback = function()
            task.spawn(runFossilCycle)
        end,
    })

    EventTab:CreateButton({
        Name = "🥚 Buy 1 Fossiled Egg Now (Costs 500)",
        Callback = function()
            task.spawn(buyFossiledEgg)
        end,
    })

    EventTab:CreateButton({
        Name = "📍 Teleport to Fossil Station & Egg Stand",
        Callback = function()
            local hrp = getHRP()
            if hrp then
                disableGuards()
                hrp.CFrame = CFrame.new(58, 4, -38)
            end
        end,
    })

    -- ─── Tab 3: Stage Teleports (วาร์ปชั้น) ───
    local TpTab = Window:CreateTab("Teleports", 10723346959)

    TpTab:CreateSection("🏰 Stage / Floor Teleport")

    TpTab:CreateDropdown({
        Name = "Select Floor / Stage",
        Options = STAGE_OPTIONS,
        CurrentOption = { "Floor 1: Meadow" },
        MultipleOptions = false,
        Flag = "ZH_SelectedStage",
        Callback = function(opt)
            local val = type(opt) == "table" and opt[1] or opt
            settings.selectedStage = val
        end,
    })

    TpTab:CreateButton({
        Name = "🚀 Teleport to Selected Floor",
        Callback = function()
            teleportToStageByLabel(settings.selectedStage)
        end,
    })

    TpTab:CreateSection("📍 Quick Locations")

    TpTab:CreateButton({
        Name = "🏠 Teleport to My Pen / Plot",
        Callback = function()
            local myPlot = getMyPlot()
            local hrp = getHRP()
            if myPlot and hrp then
                local detector = myPlot:FindFirstChild("Detector")
                if detector then
                    hrp.CFrame = CFrame.new(detector.Position + Vector3.new(0, 4, 0))
                else
                    hrp.CFrame = CFrame.new(-141.8, 5, 65.4)
                end
            end
        end,
    })

    TpTab:CreateButton({
        Name = "🚩 Teleport to Spawn / Lobby",
        Callback = function()
            local hrp = getHRP()
            if hrp then
                local map = Workspace:FindFirstChild("Map")
                local startPart = map and (map:FindFirstChild("Start") or map:FindFirstChild("SpawnLocation"))
                if startPart then
                    hrp.CFrame = CFrame.new(startPart.Position + Vector3.new(0, 4, 0))
                else
                    hrp.CFrame = CFrame.new(0, 5, 0)
                end
            end
        end,
    })

    -- ─── Tab 4: Farm & Automation ───
    local FarmTab = Window:CreateTab("Automation", 10723346959)

    FarmTab:CreateSection("🧘 Squat & Multiplier Farm")

    FarmTab:CreateToggle({
        Name = "Auto Squat Boost (Train Multiplier)",
        CurrentValue = false,
        Flag = "ZH_AutoSquat",
        Callback = function(val)
            settings.autoSquat = val
            if val then
                startThread("AutoSquat", function(isAlive)
                    while isAlive() do
                        if Remotes then
                            local req = Remotes:FindFirstChild("SquatTrainingRequest")
                            local bonus = Remotes:FindFirstChild("SquatBonusRequest")
                            if req then pcall(function() req:FireServer() end) end
                            if bonus then pcall(function() bonus:FireServer() end) end
                        end
                        task.wait(0.2)
                    end
                end)
            else
                stopThread("AutoSquat")
            end
        end,
    })

    FarmTab:CreateSection("🎁 Claim Rewards")

    FarmTab:CreateToggle({
        Name = "Auto Claim Rewards (Offline / Index / Wheel)",
        CurrentValue = false,
        Flag = "ZH_AutoClaim",
        Callback = function(val)
            settings.autoClaim = val
            if val then
                startThread("AutoClaim", function(isAlive)
                    while isAlive() do
                        if Remotes then
                            local idxRemote = Remotes:FindFirstChild("ClaimAnimalIndexReward")
                            if idxRemote then pcall(function() idxRemote:FireServer() end) end

                            local offRemote = Remotes:FindFirstChild("OfflineRewards")
                            if offRemote then pcall(function() offRemote:FireServer() end) end

                            local wheelRemote = Remotes:FindFirstChild("Wheelspin")
                            if wheelRemote then pcall(function() wheelRemote:FireServer() end) end
                        end
                        task.wait(10)
                    end
                end)
            else
                stopThread("AutoClaim")
            end
        end,
    })

    -- ─── Tab 5: Movement ───
    local MiscTab = Window:CreateTab("Movement", 10723346959)

    MiscTab:CreateSection("⚡ Movement Enhancements")

    MiscTab:CreateToggle({
        Name = "WalkSpeed Boost",
        CurrentValue = false,
        Flag = "ZH_SpeedEnabled",
        Callback = function(val)
            settings.speedEnabled = val
            local char = getCharacter()
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then
                hum.WalkSpeed = val and settings.walkSpeed or 16
            end
        end,
    })

    MiscTab:CreateSlider({
        Name = "Speed Amount",
        Range = {16, 150},
        Increment = 1,
        CurrentValue = 32,
        Flag = "ZH_WalkSpeed",
        Callback = function(val)
            settings.walkSpeed = val
            if settings.speedEnabled then
                local char = getCharacter()
                local hum = char and char:FindFirstChild("Humanoid")
                if hum then hum.WalkSpeed = val end
            end
        end,
    })

    -- Cleanup on unload
    if scriptInfo and scriptInfo.registerCleanup then
        scriptInfo.registerCleanup(function()
            running = false
            for k in pairs(threads) do
                threads[k] = nil
            end
            for _, c in ipairs(connections) do
                pcall(function() c:Disconnect() end)
            end
            local char = getCharacter()
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then hum.WalkSpeed = 16 end
        end)
    end

    environment.__RAVEN_ZOO_HATCHERS = {
        Destroy = function()
            running = false
            for k in pairs(threads) do
                threads[k] = nil
            end
            for _, c in ipairs(connections) do
                pcall(function() c:Disconnect() end)
            end
        end
    }
end
