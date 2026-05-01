local AutoMineLoop = {}

function AutoMineLoop.start(ctx)
    if not ctx then
        error("AutoMineLoop.start requires ctx table")
    end

    local LocalPlayer = ctx.localPlayer
    local Players = ctx.playersService
    local ReplicatedStorage = ctx.replicatedStorage
    local Workspace = ctx.workspaceService or game:GetService("Workspace")

    local lockedTarget = nil
    local lastTargetSignature = nil
    local sameTargetLoops = 0
    local oreSwitchHitLimit = 2
    local blockedTargetUntil = {}
    local nextMineAllowedAt = 0
    local nextEquipAllowedAt = 0
    local lastMineFiredAt = 0
    local remoteMinInterval = 0.12
    local remoteBackoffInterval = 0.35
    local remoteClientDrainConnections = {}
    local oreContainers = {
        Workspace:FindFirstChild("PlacedOre"),
        Workspace:FindFirstChild("SpawnedBlocks"),
    }
    local nextContainersRefreshAt = 0
    local lastProgressTargetKey = nil
    local lastProgressDurability = nil
    local staleProgressHits = 0
    local targetLockedAt = 0
    local firedHitsOnTarget = 0
    local mineMadCommAlternateCounter = 0
    local invalidMadCommIds = {}
    local drillPacketNonce = 22000
    local drillCollectDisabled = false
    local nextTargetSearchAt = 0
    local targetSearchActiveInterval = 0.08
    local targetSearchIdleInterval = 0.28
    local noTargetLoopSleep = 0.14
    local lastAutoMineStatusText = nil

    local function randomRange(minValue, maxValue)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.randomRange) == "function" then
            return ctx.autoMineHelper.randomRange(minValue, maxValue)
        end
        return minValue + (maxValue - minValue) * math.random()
    end

    local function setAutoMineStatus(text)
        if lastAutoMineStatusText == text then
            return
        end
        lastAutoMineStatusText = text
        if type(ctx.setStatus) == "function" then
            ctx.setStatus(text)
        end
    end

    local function hasNearbyPlayers(rootPart, radius)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.hasNearbyPlayers) == "function" then
            return ctx.autoMineHelper.hasNearbyPlayers(LocalPlayer, Players, rootPart, radius)
        end
        if not rootPart then return false end
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer ~= LocalPlayer and otherPlayer.Character then
                local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
                if otherRoot and otherRoot.Position and rootPart and rootPart.Position and (otherRoot.Position - rootPart.Position).Magnitude <= radius then
                    return true
                end
            end
        end
        return false
    end

    local function collectNumericMadCommActivateEntries(madCommEvents)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.collectNumericMadCommActivateEntries) == "function" then
            return ctx.autoMineHelper.collectNumericMadCommActivateEntries(madCommEvents, invalidMadCommIds)
        end
        local entries = {}
        if not madCommEvents then
            return entries
        end
        for _, child in ipairs(madCommEvents:GetChildren()) do
            local idNum = tonumber(child.Name)
            if idNum and not invalidMadCommIds[idNum] then
                local act = child:FindFirstChild("Activate")
                if act and act:IsA("RemoteEvent") then
                    table.insert(entries, {
                        idNum = idNum,
                        remote = act,
                    })
                end
            end
        end
        table.sort(entries, function(a, b)
            return a.idNum < b.idNum
        end)
        return entries
    end

    local function getMadCommIdFromRemote(remote)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.getMadCommIdFromRemote) == "function" then
            return ctx.autoMineHelper.getMadCommIdFromRemote(remote)
        end
        if not remote or not remote.Parent then
            return nil
        end
        local n = tonumber(remote.Parent.Name)
        if not n then
            return nil
        end
        return math.floor(n + 0.5)
    end

    local function isMadCommIdAllowed(idNum)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.isMadCommIdAllowed) == "function" then
            return ctx.autoMineHelper.isMadCommIdAllowed(idNum, invalidMadCommIds)
        end
        local n = tonumber(idNum)
        if not n then
            return false
        end
        n = math.floor(n + 0.5)
        return not invalidMadCommIds[n]
    end

    local function markMadCommRemoteInvalid(remote)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.markMadCommRemoteInvalid) == "function" then
            ctx.autoMineHelper.markMadCommRemoteInvalid(remote, invalidMadCommIds)
            return
        end
        local idNum = getMadCommIdFromRemote(remote)
        if idNum then
            invalidMadCommIds[idNum] = true
        end
    end

    local function resolveToolMadCommId(tool)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.resolveToolMadCommId) == "function" then
            return ctx.autoMineHelper.resolveToolMadCommId(tool)
        end
        if not tool then return nil end
        local id = tonumber(tool:GetAttribute("MadCommId"))
        if id then
            return math.floor(id + 0.5)
        end
        local queue = { tool }
        local qi = 1
        while qi <= #queue do
            local node = queue[qi]
            qi = qi + 1
            if node and node.GetAttributes then
                local attrs = node:GetAttributes()
                for k, v in pairs(attrs) do
                    if type(k) == "string" and string.find(string.lower(k), "madcomm", 1, true) then
                        local n = tonumber(v)
                        if n then
                            return math.floor(n + 0.5)
                        end
                    end
                end
            end
            if node and node.GetChildren then
                for _, child in ipairs(node:GetChildren()) do
                    table.insert(queue, child)
                    if child:IsA("IntValue") or child:IsA("NumberValue") or child:IsA("StringValue") then
                        local ln = string.lower(tostring(child.Name))
                        if string.find(ln, "madcomm", 1, true) then
                            local n = tonumber(child.Value)
                            if n then
                                return math.floor(n + 0.5)
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function resolveActivateRemote(tool)
        local madCommEvents = ReplicatedStorage:FindFirstChild("MadCommEvents")
        if ctx.autoMineHelper and type(ctx.autoMineHelper.resolveActivateRemote) == "function" then
            return ctx.autoMineHelper.resolveActivateRemote(
                tool,
                madCommEvents,
                ctx.forceMadCommId,
                isMadCommIdAllowed,
                resolveToolMadCommId,
                function(events)
                    return collectNumericMadCommActivateEntries(events)
                end
            )
        end
        if ctx.forceMadCommId > 0 and madCommEvents then
            local forcedFolder = madCommEvents:FindFirstChild(tostring(ctx.forceMadCommId))
            local forcedRemote = forcedFolder and forcedFolder:FindFirstChild("Activate")
            if forcedRemote and forcedRemote:IsA("RemoteEvent") and isMadCommIdAllowed(ctx.forceMadCommId) then
                return forcedRemote
            end
        end
        if tool then
            local madCommId = resolveToolMadCommId(tool)
            if madCommId and madCommEvents then
                local commFolder = madCommEvents:FindFirstChild(tostring(madCommId))
                local remote = commFolder and commFolder:FindFirstChild("Activate")
                if remote and isMadCommIdAllowed(madCommId) then
                    return remote
                end
            end
            local nested = tool:FindFirstChild("Activate", true)
            if nested then
                return nested
            end
        end
        if madCommEvents then
            local discovered = collectNumericMadCommActivateEntries(madCommEvents)
            if #discovered > 0 then
                return discovered[1].remote
            end
        end
        return nil
    end

    local function pickMineActivateRemoteAlternateDiscovered(tool)
        local madCommEvents = ReplicatedStorage:FindFirstChild("MadCommEvents")
        if ctx.autoMineHelper and type(ctx.autoMineHelper.pickMineActivateRemoteAlternateDiscovered) == "function" then
            local remote, nextCounter = ctx.autoMineHelper.pickMineActivateRemoteAlternateDiscovered(
                tool,
                madCommEvents,
                ctx.forceMadCommId,
                isMadCommIdAllowed,
                resolveToolMadCommId,
                function(events)
                    return collectNumericMadCommActivateEntries(events)
                end,
                mineMadCommAlternateCounter
            )
            mineMadCommAlternateCounter = tonumber(nextCounter) or mineMadCommAlternateCounter
            return remote
        end
        if ctx.forceMadCommId > 0 and madCommEvents then
            local forcedFolder = madCommEvents:FindFirstChild(tostring(ctx.forceMadCommId))
            local forcedRemote = forcedFolder and forcedFolder:FindFirstChild("Activate")
            if forcedRemote and forcedRemote:IsA("RemoteEvent") and isMadCommIdAllowed(ctx.forceMadCommId) then
                return forcedRemote
            end
        end
        if tool and madCommEvents then
            local madCommId = resolveToolMadCommId(tool)
            if madCommId then
                local folder = madCommEvents:FindFirstChild(tostring(madCommId))
                local bound = folder and folder:FindFirstChild("Activate")
                if bound and bound:IsA("RemoteEvent") and isMadCommIdAllowed(madCommId) then
                    return bound
                end
            end
            local nested = tool:FindFirstChild("Activate", true)
            if nested and nested:IsA("RemoteEvent") then
                return nested
            end
        end
        local discovered = madCommEvents and collectNumericMadCommActivateEntries(madCommEvents) or {}
        if #discovered >= 2 then
            mineMadCommAlternateCounter = mineMadCommAlternateCounter + 1
            local idx = ((mineMadCommAlternateCounter - 1) % #discovered) + 1
            return discovered[idx].remote
        end
        if #discovered == 1 then
            return discovered[1].remote
        end
        return resolveActivateRemote(tool)
    end

    local function mineGridForActivateRemote(gridPos)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.mineGridForActivateRemote) == "function" then
            return ctx.autoMineHelper.mineGridForActivateRemote(gridPos)
        end
        local x = math.floor(tonumber(gridPos.X or gridPos.x) or 0)
        local y = math.floor(tonumber(gridPos.Y or gridPos.y) or 0)
        local z = math.floor(tonumber(gridPos.Z or gridPos.z) or 0)
        return Vector3int16.new(x, y, z)
    end

    local function buildGridCandidates(primaryGridPos, renderPart)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.buildGridCandidates) == "function" then
            return ctx.autoMineHelper.buildGridCandidates(primaryGridPos, renderPart)
        end
        local candidates = {}
        local seen = {}
        local function addCandidate(pos)
            if not pos then return end
            local vec = mineGridForActivateRemote(pos)
            local key = tostring(vec.X) .. "|" .. tostring(vec.Y) .. "|" .. tostring(vec.Z)
            if seen[key] then return end
            seen[key] = true
            table.insert(candidates, vec)
        end

        addCandidate(primaryGridPos)
        if renderPart then
            local worldPos = renderPart.Position
            if worldPos then
                addCandidate(Vector3int16.new(
                    math.floor(worldPos.X),
                    math.floor(worldPos.Y),
                    math.floor(worldPos.Z)
                ))
                addCandidate(Vector3int16.new(
                    math.floor(worldPos.X / 4),
                    math.floor(worldPos.Y / 4),
                    math.floor(worldPos.Z / 4)
                ))
            end
        end
        return candidates
    end

    local function ensureRemoteClientDrain(remote)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.ensureRemoteClientDrain) == "function" then
            ctx.autoMineHelper.ensureRemoteClientDrain(remote, remoteClientDrainConnections, ctx.trackConnection)
            return
        end
        if not remote or not remote:IsA("RemoteEvent") then
            return
        end
        if remoteClientDrainConnections[remote] then
            return
        end
        local conn = remote.OnClientEvent:Connect(function()
            -- Intentionally ignored.
        end)
        remoteClientDrainConnections[remote] = conn
        if type(ctx.trackConnection) == "function" then
            ctx.trackConnection(conn)
        end
    end

    local function nextDrillPacketNonce(step)
        if ctx.autoMineHelper and type(ctx.autoMineHelper.nextDrillPacketNonce) == "function" then
            drillPacketNonce = ctx.autoMineHelper.nextDrillPacketNonce(drillPacketNonce, step)
            return drillPacketNonce
        end
        local s = tonumber(step) or 1
        drillPacketNonce = drillPacketNonce + math.max(1, math.floor(s))
        return drillPacketNonce
    end

    local function isKnownDrillVehicle(humanoid)
        if not humanoid or not humanoid.SeatPart then
            return false
        end
        local seat = humanoid.SeatPart
        local names = {
            "minimuncher",
            "exadrill",
            "speedminer",
        }
        local function matches(name)
            local ln = string.lower(tostring(name or ""))
            for _, token in ipairs(names) do
                if string.find(ln, token, 1, true) then
                    return true
                end
            end
            return false
        end
        if matches(seat.Name) then
            return true
        end
        local node = seat.Parent
        local depth = 0
        while node and depth < 7 do
            if matches(node.Name) then
                return true
            end
            node = node.Parent
            depth = depth + 1
        end
        return false
    end

    local function resolveDrillRemotes()
        local madCommEvents = ReplicatedStorage:FindFirstChild("MadCommEvents")
        if not madCommEvents then
            return nil, nil, nil
        end
        local folder = madCommEvents:FindFirstChild("1313")
        if not folder and ctx.forceMadCommId > 0 then
            folder = madCommEvents:FindFirstChild(tostring(ctx.forceMadCommId))
        end
        local collectFolder = madCommEvents:FindFirstChild("1358")
        local drillCollectToggle = collectFolder and collectFolder:FindFirstChild("DrillOreCollectToggle")
        if drillCollectToggle and not drillCollectToggle:IsA("RemoteEvent") then
            drillCollectToggle = nil
        end
        if not folder then
            return nil, nil, drillCollectToggle
        end
        local drillActivate = folder:FindFirstChild("DrillActivate")
        local drillMine = folder:FindFirstChild("DrillMine")
        local folderIdNum = tonumber(folder.Name)
        if folderIdNum and not isMadCommIdAllowed(folderIdNum) then
            return nil, nil, drillCollectToggle
        end
        if drillActivate and drillActivate:IsA("RemoteEvent")
            and drillMine and drillMine:IsA("RemoteEvent")
        then
            return drillActivate, drillMine, drillCollectToggle
        end
        return nil, nil, drillCollectToggle
    end

    local function getDescendantGridPosition(target)
        if not target or not target.GetDescendants then return nil end
        for _, desc in ipairs(target:GetDescendants()) do
            if desc:IsA("Instance") then
                local p = desc:GetAttribute("ChunkPosition") or desc:GetAttribute("GridPosition")
                if p then return p end
            end
        end
        return nil
    end

    local function getTargetGridPositionDeep(target, renderPart)
        local gridPos = ctx.getTargetGridPosition(target, renderPart)
        if gridPos then return gridPos end
        gridPos = getDescendantGridPosition(target)
        if gridPos then return gridPos end
        if renderPart then
            gridPos = getDescendantGridPosition(renderPart)
            if gridPos then return gridPos end
        end
        return nil
    end

    local function GetTool(characterOnly)
        for _,v in pairs(LocalPlayer.Character:GetChildren()) do
            if v:FindFirstChild("EquipRemote") and string.lower(v.Name):find("pickaxe") then
                return v
            end
        end
        if characterOnly then
            return nil
        end
        for _,v in pairs(LocalPlayer:FindFirstChild("InnoBackpack") and LocalPlayer.InnoBackpack:GetChildren() or {}) do
            if v:FindFirstChild("EquipRemote") and string.lower(v.Name):find("pickaxe") then
                return v
            end
        end
        return nil
    end

    local function getNumberLike(value)
        if type(value) == "number" then return value end
        if typeof(value) == "number" then return value end
        if type(value) == "string" then
            local n = tonumber(value)
            if n then return n end
        end
        return nil
    end

    local function getNumericByKeys(instance, keys)
        if not instance or type(keys) ~= "table" then return nil end
        for _, key in ipairs(keys) do
            local attr = instance:GetAttribute(key)
            local n = getNumberLike(attr)
            if n then return n end
        end
        for _, key in ipairs(keys) do
            local child = instance:FindFirstChild(key, true)
            if child then
                local n = nil
                if child:IsA("NumberValue") or child:IsA("IntValue") or child:IsA("DoubleValue") then
                    n = child.Value
                elseif child:IsA("StringValue") then
                    n = tonumber(child.Value)
                end
                if n then return n end
            end
        end
        return nil
    end

    local function getOreEconomyForAutoMine(oreName, target, renderPart)
        local canonical = ctx.canonicalizeOreName(oreName) or ctx.pickKnownOreFromText(oreName) or oreName
        local row = canonical and ctx.oreReferenceFromList[canonical]
        if not row then
            return {
                price = nil,
                required = nil,
                canonical = canonical,
            }
        end
        return {
            price = row.price,
            required = row.required,
            canonical = canonical,
        }
    end

    local function pickaxeCanMineOre(pickaxeDamage, economy)
        if ctx.forceDamage > 0 then
            return true
        end
        if type(economy) ~= "table" then return true end
        if economy.required == nil then return true end
        return (tonumber(pickaxeDamage) or 0) >= economy.required
    end

    local function resolvePickaxeDamage(tool)
        if not tool then return 10 end
        local pickaxeStrengthByName = {
            ["rusty pickaxe"] = 7,
            ["copper pickaxe"] = 12,
            ["iron pickaxe"] = 20,
            ["steel pickaxe"] = 35,
            ["platinum pickaxe"] = 60,
            ["titanium pickaxe"] = 100,
            ["infernum pickaxe"] = 200,
            ["diamond pickaxe"] = 400,
            ["mithril pickaxe"] = 600,
            ["adamantium pickaxe"] = 800,
            ["unobtainium pickaxe"] = 1000,
        }
        local damageKeys = {
            "Damage", "MineDamage", "MiningDamage", "Power", "MiningPower", "Strength", "HitPower",
        }
        local damage = getNumericByKeys(tool, damageKeys)
        if not damage and tool.Parent then
            damage = getNumericByKeys(tool.Parent, damageKeys)
        end
        if not damage and tool.GetDescendants then
            local bestCandidate = nil
            for _, desc in ipairs(tool:GetDescendants()) do
                if desc:IsA("NumberValue") or desc:IsA("IntValue") or desc:IsA("DoubleValue") or desc:IsA("StringValue") then
                    local ln = string.lower(tostring(desc.Name))
                    if string.find(ln, "damage", 1, true)
                        or string.find(ln, "mining", 1, true)
                        or string.find(ln, "power", 1, true)
                        or string.find(ln, "strength", 1, true)
                    then
                        local raw = desc:IsA("StringValue") and tonumber(desc.Value) or tonumber(desc.Value)
                        if raw and raw > 0 then
                            if not bestCandidate then
                                bestCandidate = raw
                            else
                                if (raw <= 1500 and (bestCandidate > 1500 or raw > bestCandidate))
                                    or (bestCandidate > 1500 and raw < bestCandidate)
                                then
                                    bestCandidate = raw
                                end
                            end
                        end
                    end
                end
            end
            damage = bestCandidate
        end
        if not damage then
            local key = string.lower(tostring(tool.Name))
            damage = pickaxeStrengthByName[key]
        end
        damage = tonumber(damage) or 10
        return math.clamp(damage, 1, 9999)
    end

    local function getTargetDurability(target, renderPart)
        local hpKeys = {
            "Health", "HP", "HitPoints", "Hitpoints", "Durability", "MineHealth", "OreHealth", "Integrity",
        }
        local durability = getNumericByKeys(target, hpKeys)
        if durability == nil and renderPart then
            durability = getNumericByKeys(renderPart, hpKeys)
        end
        if durability == nil and target and target.GetDescendants then
            for _, desc in ipairs(target:GetDescendants()) do
                if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                    local n = string.lower(desc.Name)
                    if string.find(n, "health", 1, true)
                        or string.find(n, "durability", 1, true)
                        or string.find(n, "hp", 1, true)
                    then
                        durability = desc.Value
                        break
                    end
                end
            end
        end
        return tonumber(durability)
    end

    local function isIgnoredOre(oreName)
        if type(ctx.oreIgnoreList) ~= "table" then return false end
        if type(oreName) ~= "string" or oreName == "" then return false end
        local canonical = ctx.canonicalizeOreName(oreName) or ctx.normalizeOreToken(oreName) or oreName
        if ctx.oreIgnoreList[canonical] == true or ctx.oreIgnoreList[oreName] == true then
            return true
        end
        return table.find(ctx.oreIgnoreList, canonical) ~= nil or table.find(ctx.oreIgnoreList, oreName) ~= nil
    end

    local function isTargetValid(target, rootPart, pickaxeDamage)
        if not target or not target.Parent or not rootPart then
            return false
        end
        local renderPart = ctx.getOreRenderPart(target)
        if not renderPart or not renderPart.Parent then
            return false
        end
        local oreName = ctx.getOreNameForEsp(target, renderPart)
        if isIgnoredOre(oreName) then
            return false
        end
        local economy = getOreEconomyForAutoMine(oreName, target, renderPart)
        if not pickaxeCanMineOre(pickaxeDamage, economy) then
            return false
        end
        local dist = (rootPart.Position - renderPart.Position).Magnitude
        return dist <= (ctx.range + 8)
    end

    local function markTargetLoop(target, renderPart)
        local sig = ctx.makeOreSignature(target, renderPart) or tostring(target)
        if sig == lastTargetSignature then
            sameTargetLoops = sameTargetLoops + 1
        else
            lastTargetSignature = sig
            sameTargetLoops = 1
        end
    end

    local function resetTargetLock()
        lockedTarget = nil
        lastTargetSignature = nil
        sameTargetLoops = 0
        targetLockedAt = 0
        firedHitsOnTarget = 0
    end

    local function getTargetKey(target, renderPart)
        return ctx.makeOreSignature(target, renderPart) or tostring(target)
    end

    local function isTargetTemporarilyBlocked(target, renderPart)
        local key = getTargetKey(target, renderPart)
        local t = blockedTargetUntil[key]
        if not t then return false end
        if t <= os.clock() then
            blockedTargetUntil[key] = nil
            return false
        end
        return true
    end

    local function blockTargetTemporarily(target, renderPart, seconds)
        local key = getTargetKey(target, renderPart)
        blockedTargetUntil[key] = os.clock() + (seconds or 2.0)
    end

    return task.spawn(function()
        while ctx.enabled do
            if not LocalPlayer then task.wait(0.1) continue end
            local Character = LocalPlayer.Character
            if not Character then task.wait(0.1) continue end
            local humanoid = Character:FindFirstChildOfClass("Humanoid")
            local inVehicleDrill = isKnownDrillVehicle(humanoid)
            if not inVehicleDrill then
                drillCollectDisabled = false
            end
            local noTargetMode = false
            local Tool = GetTool()
            local isPickaxe = Tool and string.lower(Tool.Name):find("pickaxe") ~= nil
            if not inVehicleDrill and Tool and Tool.Parent == LocalPlayer.InnoBackpack and isPickaxe then
                local equipRemote = Tool:FindFirstChild("EquipRemote")
                local canEquip = true
                if ctx.safeProfile and os.clock() < nextEquipAllowedAt then
                    canEquip = false
                end
                if equipRemote and canEquip then
                    equipRemote:FireServer(true)
                    if ctx.safeProfile then
                        nextEquipAllowedAt = os.clock() + randomRange(0.8, 1.5)
                    end
                    setAutoMineStatus("Auto Mine Status: equipping pickaxe")
                    task.wait(0.22)
                end
            end
            Tool = GetTool(true)
            if not inVehicleDrill and not Tool then
                if type(ctx.clearVisual) == "function" then
                    ctx.clearVisual()
                end
                resetTargetLock()
                setAutoMineStatus("Auto Mine Status: waiting pickaxe equip")
                task.wait(0.1)
                continue
            end
            local root = Character and Character:FindFirstChild("HumanoidRootPart")
            if root then
                if ctx.safeProfile and ctx.safeNearbyPause and hasNearbyPlayers(root, ctx.safeNearbyRadius) then
                    resetTargetLock()
                    if type(ctx.clearVisual) == "function" then
                        ctx.clearVisual()
                    end
                    setAutoMineStatus("Auto Mine Status: paused (players nearby)")
                    task.wait(randomRange(0.3, 0.7))
                    continue
                end
                local pickaxeDamage = inVehicleDrill and 9999 or resolvePickaxeDamage(Tool)
                if ctx.forceDamage > 0 then
                    pickaxeDamage = ctx.forceDamage
                end
                local closestBlock, closestDist = nil, math.huge
                local weakPickaxeNoTargets = false

                local now = os.clock()
                if now >= nextContainersRefreshAt then
                    oreContainers[1] = Workspace:FindFirstChild("PlacedOre")
                    oreContainers[2] = Workspace:FindFirstChild("SpawnedBlocks")
                    nextContainersRefreshAt = now + 1.5
                end

                if isTargetValid(lockedTarget, root, pickaxeDamage) then
                    closestBlock = lockedTarget
                    nextTargetSearchAt = now + targetSearchActiveInterval
                else
                    resetTargetLock()
                    if type(ctx.clearVisual) == "function" then
                        ctx.clearVisual()
                    end
                    if now >= nextTargetSearchAt then
                        closestBlock = nil
                        closestDist = math.huge
                        local bestPrice = -math.huge
                        local anyInRange = false
                        local anyMineable = false
                        for _, container in ipairs(oreContainers) do
                            if container then
                                for _, v in pairs(container:GetChildren()) do
                                    local renderPart = ctx.getOreRenderPart(v)
                                    if not renderPart then continue end
                                    if isTargetTemporarilyBlocked(v, renderPart) then continue end
                                    local oreName = ctx.getOreNameForEsp(v, renderPart)
                                    if isIgnoredOre(oreName) then continue end
                                    local dist = (root.Position - renderPart.Position).Magnitude
                                    if dist <= ctx.range then
                                        anyInRange = true
                                        local economy = getOreEconomyForAutoMine(oreName, v, renderPart)
                                        if pickaxeCanMineOre(pickaxeDamage, economy) then
                                            anyMineable = true
                                            local p = economy.price
                                            if p == nil then
                                                p = -1
                                            end
                                            if p > bestPrice or (p == bestPrice and dist < closestDist) then
                                                bestPrice = p
                                                closestDist = dist
                                                closestBlock = v
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if not closestBlock and anyInRange and not anyMineable then
                            weakPickaxeNoTargets = true
                        end
                        lockedTarget = closestBlock
                        if lockedTarget then
                            targetLockedAt = os.clock()
                            firedHitsOnTarget = 0
                            nextTargetSearchAt = now + targetSearchActiveInterval
                        else
                            nextTargetSearchAt = now + targetSearchIdleInterval
                        end
                    end
                end

                if closestBlock then
                    local renderPart = ctx.getOreRenderPart(closestBlock)
                    if not renderPart or not renderPart.Parent then
                        if type(ctx.clearVisual) == "function" then
                            ctx.clearVisual()
                        end
                        setAutoMineStatus("Auto Mine Status: switching ore (no render part)")
                        resetTargetLock()
                        task.wait(0.08)
                        continue
                    end
                    if type(ctx.setVisual) == "function" then
                        ctx.setVisual(closestBlock, renderPart)
                    end
                    local oreName = ctx.getOreNameForEsp(closestBlock, renderPart)
                    local targetKey = getTargetKey(closestBlock, renderPart)
                    local targetDurability = getTargetDurability(closestBlock, renderPart)
                    if lastProgressTargetKey == targetKey
                        and lastProgressDurability ~= nil
                        and targetDurability ~= nil
                        and firedHitsOnTarget >= 1
                    then
                        local prevD = lastProgressDurability
                        local jumpEps = math.max(2, prevD * 0.035)
                        if targetDurability > prevD + jumpEps then
                            setAutoMineStatus("Auto Mine Status: ore HP reset (server) — skip block")
                            lastProgressTargetKey = nil
                            lastProgressDurability = nil
                            staleProgressHits = 0
                            blockTargetTemporarily(closestBlock, renderPart, 12.0)
                            if type(ctx.clearVisual) == "function" then
                                ctx.clearVisual()
                            end
                            resetTargetLock()
                            task.wait(0.12)
                            continue
                        end
                    end
                    local adaptiveMinInterval = math.clamp(0.9 / math.max(1, pickaxeDamage), 0.08, 0.55)
                    local elapsedOnTarget = (targetLockedAt > 0) and (os.clock() - targetLockedAt) or 0
                    local nowMine = os.clock()
                    local readyToFireAt = math.max(nextMineAllowedAt, lastMineFiredAt + adaptiveMinInterval)
                    local canCountStale = nowMine >= readyToFireAt - 0.02
                    if lastProgressTargetKey ~= targetKey or not lastProgressDurability or not targetDurability then
                        staleProgressHits = 0
                        firedHitsOnTarget = 0
                    elseif canCountStale then
                        if targetDurability >= (lastProgressDurability - 0.001) then
                            staleProgressHits = staleProgressHits + 1
                        else
                            staleProgressHits = 0
                            firedHitsOnTarget = 0
                        end
                    end
                    if staleProgressHits > 0 then
                        adaptiveMinInterval = math.min(0.95, adaptiveMinInterval + (staleProgressHits * 0.06))
                    end
                    local expectedHits = nil
                    if targetDurability and targetDurability > 0 and pickaxeDamage > 0 then
                        expectedHits = math.max(1, math.ceil(targetDurability / pickaxeDamage))
                    end
                    local hitSwitchLimit = oreSwitchHitLimit
                    if expectedHits then
                        hitSwitchLimit = math.ceil(expectedHits * 1.9 + 18)
                        hitSwitchLimit = math.clamp(hitSwitchLimit, oreSwitchHitLimit, 1200)
                    end
                    local hardHitLimit
                    if expectedHits then
                        hardHitLimit = math.ceil(expectedHits * 2.25 + 36)
                        hardHitLimit = math.clamp(hardHitLimit, 40, 1800)
                    else
                        hardHitLimit = math.clamp(math.ceil(480 / math.max(1, pickaxeDamage)), 24, 160)
                    end
                    local perHitDelayEst = math.max(ctx.delay, adaptiveMinInterval, 0.1)
                    local targetTimeLimit
                    if expectedHits then
                        targetTimeLimit = math.clamp(expectedHits * perHitDelayEst * 4.2 + 16, 20, 720)
                    else
                        targetTimeLimit = math.clamp(14 * perHitDelayEst * 2.2, 10, 120)
                    end
                    local staleProgressCap = 4
                    if expectedHits and expectedHits > 45 then
                        staleProgressCap = 18
                    elseif expectedHits and expectedHits > 18 then
                        staleProgressCap = 12
                    end
                    local staleGraceHits = expectedHits and math.clamp(math.floor(expectedHits * 0.45) + 8, 10, 220) or 10
                    local staleMinElapsed = expectedHits and math.clamp(perHitDelayEst * math.min(expectedHits * 0.4, 70), 2.5, 34) or 2.8
                    local canSwitchFromNoProgress = staleProgressHits >= staleProgressCap
                        and firedHitsOnTarget >= staleGraceHits
                        and elapsedOnTarget >= staleMinElapsed
                    if canSwitchFromNoProgress then
                        setAutoMineStatus("Auto Mine Status: switching ore (no progress)")
                        blockTargetTemporarily(closestBlock, renderPart, 3.0)
                        if type(ctx.clearVisual) == "function" then
                            ctx.clearVisual()
                        end
                        resetTargetLock()
                        task.wait(0.08)
                        continue
                    end
                    if elapsedOnTarget > targetTimeLimit then
                        setAutoMineStatus("Auto Mine Status: switching ore (too long)")
                        blockTargetTemporarily(closestBlock, renderPart, 2.8)
                        if type(ctx.clearVisual) == "function" then
                            ctx.clearVisual()
                        end
                        resetTargetLock()
                        task.wait(0.08)
                        continue
                    end
                    if firedHitsOnTarget >= hardHitLimit then
                        setAutoMineStatus("Auto Mine Status: switching ore (no effect)")
                        blockTargetTemporarily(closestBlock, renderPart, 3.0)
                        if type(ctx.clearVisual) == "function" then
                            ctx.clearVisual()
                        end
                        resetTargetLock()
                        task.wait(0.08)
                        continue
                    end
                    local gridPos = getTargetGridPositionDeep(closestBlock, renderPart)
                    if not gridPos then
                        local worldPos = renderPart and renderPart.Position
                        if not worldPos then
                            if type(ctx.clearVisual) == "function" then
                                ctx.clearVisual()
                            end
                            setAutoMineStatus("Auto Mine Status: target no position")
                            task.wait(0.03)
                            continue
                        end
                        gridPos = Vector3int16.new(
                            math.floor(worldPos.X / 4),
                            math.floor(worldPos.Y / 4),
                            math.floor(worldPos.Z / 4)
                        )
                    end
                    local gridCandidates = buildGridCandidates(gridPos, renderPart)
                    local gridForRemote = gridCandidates[1] or mineGridForActivateRemote(gridPos)
                    if #gridCandidates >= 2 and staleProgressHits >= 2 then
                        local altIdx = (firedHitsOnTarget % #gridCandidates) + 1
                        gridForRemote = gridCandidates[altIdx]
                    end
                    local firedOk = false
                    local attemptedFire = false
                    local fireFailed = false
                    local mineModeText = "pickaxe"
                    local firedActivateRemote = nil
                    local firedMineRemote = nil
                    local now = os.clock()
                    local minReadyAt = math.max(nextMineAllowedAt, lastMineFiredAt + adaptiveMinInterval)
                    if now < minReadyAt then
                        task.wait(math.max(0.03, minReadyAt - now))
                        continue
                    end
                    if inVehicleDrill then
                        local drillActivateRemote, drillMineRemote, drillCollectToggleRemote = resolveDrillRemotes()
                        if drillActivateRemote and drillMineRemote then
                            attemptedFire = true
                            firedActivateRemote = drillActivateRemote
                            firedMineRemote = drillMineRemote
                            ensureRemoteClientDrain(drillActivateRemote)
                            ensureRemoteClientDrain(drillMineRemote)
                            if drillCollectToggleRemote then
                                ensureRemoteClientDrain(drillCollectToggleRemote)
                                if not drillCollectDisabled then
                                    pcall(function()
                                        drillCollectToggleRemote:FireServer(false)
                                    end)
                                    drillCollectDisabled = true
                                end
                            end
                            local activateNonce = nextDrillPacketNonce(5)
                            local mineNonce = nextDrillPacketNonce(5)
                            local okFire = pcall(function()
                                drillActivateRemote:FireServer(activateNonce, true)
                                drillMineRemote:FireServer(mineNonce, gridForRemote)
                            end)
                            firedOk = okFire
                            fireFailed = not okFire
                            mineModeText = "drill"
                        end
                    else
                        local activateRemote = pickMineActivateRemoteAlternateDiscovered(Tool)
                        local args = { pickaxeDamage, gridForRemote }
                        if activateRemote then
                            attemptedFire = true
                            firedActivateRemote = activateRemote
                            ensureRemoteClientDrain(activateRemote)
                            local okFire = pcall(function()
                                activateRemote:FireServer(table.unpack(args))
                            end)
                            firedOk = okFire
                            fireFailed = not okFire
                        end
                    end
                    if firedOk then
                        lastMineFiredAt = os.clock()
                        firedHitsOnTarget = firedHitsOnTarget + 1
                        lastProgressTargetKey = targetKey
                        lastProgressDurability = targetDurability
                        markTargetLoop(closestBlock, renderPart)
                        if sameTargetLoops >= hitSwitchLimit then
                            setAutoMineStatus("Auto Mine Status: switching ore (hit limit)")
                            blockTargetTemporarily(closestBlock, renderPart, 2.5)
                            if type(ctx.clearVisual) == "function" then
                                ctx.clearVisual()
                            end
                            resetTargetLock()
                            task.wait(0.08)
                            continue
                        end
                        local hpText = targetDurability and (" | hp~" .. tostring(math.floor(targetDurability + 0.5))) or ""
                        local mineEcon = getOreEconomyForAutoMine(oreName, closestBlock, renderPart)
                        local econText = ""
                        if mineEcon.price then
                            econText = econText .. " | $" .. tostring(mineEcon.price)
                        end
                        if mineEcon.required then
                            econText = econText .. " need≥" .. tostring(mineEcon.required)
                        end
                        setAutoMineStatus("Auto Mine Status: mining " .. tostring(oreName) .. " (" .. mineModeText .. " | dmg " .. tostring(math.floor(pickaxeDamage + 0.5)) .. hpText .. econText .. ")")
                    else
                        if attemptedFire and fireFailed then
                            if inVehicleDrill then
                                markMadCommRemoteInvalid(firedActivateRemote)
                                markMadCommRemoteInvalid(firedMineRemote)
                            else
                                markMadCommRemoteInvalid(firedActivateRemote)
                            end
                            nextMineAllowedAt = os.clock() + remoteBackoffInterval
                            setAutoMineStatus("Auto Mine Status: backoff (remote busy)")
                            task.wait(0.08)
                            continue
                        end
                        setAutoMineStatus("Auto Mine Status: mine remote missing")
                        if type(ctx.clearVisual) == "function" then
                            ctx.clearVisual()
                        end
                        resetTargetLock()
                    end
                    local waitDelay = ctx.delay
                    if ctx.safeProfile then
                        waitDelay = math.max(waitDelay, 0.45) + randomRange(0.06, 0.38)
                    end
                    waitDelay = math.max(waitDelay, adaptiveMinInterval)
                    nextMineAllowedAt = os.clock() + waitDelay
                    task.wait(waitDelay)
                    continue
                else
                    if type(ctx.clearVisual) == "function" then
                        ctx.clearVisual()
                    end
                    resetTargetLock()
                    noTargetMode = true
                    if weakPickaxeNoTargets then
                        setAutoMineStatus("Auto Mine Status: pickaxe too weak for nearby ores")
                    else
                        setAutoMineStatus("Auto Mine Status: no target in range")
                    end
                end
            end
            if noTargetMode then
                if ctx.safeProfile then
                    task.wait(math.max(noTargetLoopSleep, randomRange(0.12, 0.22)))
                else
                    task.wait(noTargetLoopSleep)
                end
            elseif ctx.safeProfile then
                task.wait(randomRange(0.06, 0.14))
            else
                task.wait(0.03)
            end
        end
        if type(ctx.clearVisual) == "function" then
            ctx.clearVisual()
        end
    end)
end

return AutoMineLoop
