local AutoMineSystem = {}

function AutoMineSystem.randomRange(minValue, maxValue)
    return minValue + (maxValue - minValue) * math.random()
end

function AutoMineSystem.hasNearbyPlayers(localPlayer, playersService, rootPart, radius)
    if not rootPart or not playersService then
        return false
    end
    for _, otherPlayer in ipairs(playersService:GetPlayers()) do
        if otherPlayer ~= localPlayer and otherPlayer.Character then
            local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
            if otherRoot and otherRoot.Position and rootPart and rootPart.Position and (otherRoot.Position - rootPart.Position).Magnitude <= radius then
                return true
            end
        end
    end
    return false
end

function AutoMineSystem.normalizeMadCommId(value)
    local n = tonumber(value)
    if not n then
        return nil
    end
    return math.floor(n + 0.5)
end

function AutoMineSystem.isMadCommIdAllowed(idNum, invalidMadCommIds)
    local n = AutoMineSystem.normalizeMadCommId(idNum)
    if not n then
        return false
    end
    if type(invalidMadCommIds) ~= "table" then
        return true
    end
    return not invalidMadCommIds[n]
end

function AutoMineSystem.getMadCommIdFromRemote(remote)
    if not remote or not remote.Parent then
        return nil
    end
    return AutoMineSystem.normalizeMadCommId(remote.Parent.Name)
end

function AutoMineSystem.markMadCommRemoteInvalid(remote, invalidMadCommIds)
    if type(invalidMadCommIds) ~= "table" then
        return
    end
    local idNum = AutoMineSystem.getMadCommIdFromRemote(remote)
    if idNum then
        invalidMadCommIds[idNum] = true
    end
end

function AutoMineSystem.collectNumericMadCommActivateEntries(madCommEvents, invalidMadCommIds)
    local entries = {}
    if not madCommEvents then
        return entries
    end
    for _, child in ipairs(madCommEvents:GetChildren()) do
        local idNum = AutoMineSystem.normalizeMadCommId(child.Name)
        if idNum and not (type(invalidMadCommIds) == "table" and invalidMadCommIds[idNum]) then
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

function AutoMineSystem.resolveToolMadCommId(tool)
    if not tool then
        return nil
    end
    local directId = AutoMineSystem.normalizeMadCommId(tool:GetAttribute("MadCommId"))
    if directId then
        return directId
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
                    local n = AutoMineSystem.normalizeMadCommId(v)
                    if n then
                        return n
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
                        local n = AutoMineSystem.normalizeMadCommId(child.Value)
                        if n then
                            return n
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- CURRENT PATCH: ToolBase & PickaxeClient Native Integration
-- ============================================================
function AutoMineSystem.ensurePickaxeEquipped(localPlayer)
    local character = localPlayer and localPlayer.Character
    if not character then return end
    for _, model in ipairs(character:GetChildren()) do
        if model:IsA("Model") and model:FindFirstChild("EquipRemote") and model:GetAttribute("ToolId") then
            if model:GetAttribute("Equipped") ~= true then
                pcall(function()
                    model.EquipRemote:FireServer(true)
                end)
            end
        end
    end
end

function AutoMineSystem.getPickaxeComponent(localPlayer)
    local RS = game:GetService("ReplicatedStorage")
    local packages = RS:FindFirstChild("Packages")
    local innoTools = packages and packages:FindFirstChild("InnoTools")
    local toolBaseMod = innoTools and innoTools:FindFirstChild("ToolBase")
    if not toolBaseMod then return nil end

    local ok, ToolBase = pcall(require, toolBaseMod)
    if not ok or type(ToolBase) ~= "table" or not ToolBase.ToolsByModel then return nil end

    local character = localPlayer and localPlayer.Character
    if not character then return nil end

    for model, obj in pairs(ToolBase.ToolsByModel) do
        if obj.EquippedCharacter == character then
            local comp = obj.FindComponentByName and obj:FindComponentByName("PickaxeClient")
            if comp then
                return comp, obj
            end
        end
    end
    return nil
end

function AutoMineSystem.getPickaxeRange(localPlayer)
    local comp, obj = AutoMineSystem.getPickaxeComponent(localPlayer)
    if obj and obj.Definition and obj.Definition.Stats and obj.Definition.Stats.Range then
        local r = tonumber(obj.Definition.Stats.Range)
        if r and r > 0 then return r end
    end
    if comp and comp.Tool and comp.Tool.Definition and comp.Tool.Definition.Stats and comp.Tool.Definition.Stats.Range then
        local r = tonumber(comp.Tool.Definition.Stats.Range)
        if r and r > 0 then return r end
    end
    return 20
end

-- ============================================================
-- CURRENT PATCH: Terrain WorldToCell Ore Mapping
-- ============================================================
function AutoMineSystem.getOreCell(renderPart)
    if not renderPart then return nil end
    local terrain = workspace.Terrain
    if terrain and type(terrain.WorldToCell) == "function" then
        return terrain:WorldToCell(renderPart.Position)
    end
    local pos = renderPart.Position
    return Vector3int16.new(
        math.floor(pos.X / 4),
        math.floor(pos.Y / 4),
        math.floor(pos.Z / 4)
    )
end

function AutoMineSystem.mineGridForActivateRemote(gridPos)
    local x = math.floor(tonumber(gridPos.X or gridPos.x) or 0)
    local y = math.floor(tonumber(gridPos.Y or gridPos.y) or 0)
    local z = math.floor(tonumber(gridPos.Z or gridPos.z) or 0)
    return Vector3int16.new(x, y, z)
end

function AutoMineSystem.buildGridCandidates(primaryGridPos, renderPart)
    local candidates = {}
    local seen = {}
    local function addCandidate(pos)
        if not pos then return end
        local vec = AutoMineSystem.mineGridForActivateRemote(pos)
        local key = tostring(vec.X) .. "|" .. tostring(vec.Y) .. "|" .. tostring(vec.Z)
        if seen[key] then return end
        seen[key] = true
        table.insert(candidates, vec)
    end

    if renderPart then
        local terrainCell = AutoMineSystem.getOreCell(renderPart)
        if terrainCell then
            addCandidate(terrainCell)
        end
    end

    addCandidate(primaryGridPos)
    if renderPart then
        local worldPos = renderPart.Position
        if worldPos then
            addCandidate(Vector3int16.new(
                math.floor(worldPos.X / 4),
                math.floor(worldPos.Y / 4),
                math.floor(worldPos.Z / 4)
            ))
            addCandidate(Vector3int16.new(
                math.floor(worldPos.X),
                math.floor(worldPos.Y),
                math.floor(worldPos.Z)
            ))
        end
    end
    return candidates
end

-- ============================================================
-- CURRENT PATCH: Native Block Mining via PickaxeClient MineBlock
-- ============================================================
local lastBreakSoundAt = 0

function AutoMineSystem.mineBlock(pickaxeComp, cellVector3int16)
    if not cellVector3int16 then return false, "no cell" end
    local cell = Vector3int16.new(cellVector3int16.X, cellVector3int16.Y, cellVector3int16.Z)

    if pickaxeComp then
        -- Primary: Native client MineBlock method (instantly updates client terrain, generates around, invokes server, handles rollback)
        if type(pickaxeComp.MineBlock) == "function" then
            local ok, res = pcall(function()
                return pickaxeComp:MineBlock(Vector3.new(cell.X, cell.Y, cell.Z))
            end)
            if ok then
                local now = os.clock()
                if now - lastBreakSoundAt >= 0.12 then
                    lastBreakSoundAt = now
                    pcall(function()
                        if pickaxeComp.BreakSound and type(pickaxeComp.BreakSound.Play) == "function" then
                            pickaxeComp.BreakSound:Play()
                        end
                    end)
                end
                return true, res
            end
        end

        -- Secondary: InvokeServer on ActivateRemote (MadComm RemoteFunction wrapper)
        if pickaxeComp.ActivateRemote and type(pickaxeComp.ActivateRemote.InvokeServer) == "function" then
            local ok, promOrRes = pcall(function()
                return pickaxeComp.ActivateRemote:InvokeServer(cell)
            end)
            if ok then
                return true, promOrRes
            end
        end
    end

    return false, "no pickaxe component"
end

function AutoMineSystem.ensureRemoteClientDrain(remote, remoteClientDrainConnections, trackConnectionFn)
    if not remote or not remote:IsA("RemoteEvent") then
        return
    end
    if type(remoteClientDrainConnections) ~= "table" then
        return
    end
    if remoteClientDrainConnections[remote] then
        return
    end
    local conn = remote.OnClientEvent:Connect(function()
        -- Intentionally ignored; this drains server->client queue.
    end)
    remoteClientDrainConnections[remote] = conn
    if type(trackConnectionFn) == "function" then
        trackConnectionFn(conn)
    end
end

function AutoMineSystem.nextDrillPacketNonce(currentNonce, step)
    local s = tonumber(step) or 1
    local base = tonumber(currentNonce) or 0
    return base + math.max(1, math.floor(s))
end

function AutoMineSystem.resolveActivateRemote(tool, madCommEvents, forceMineMadCommId, isMadCommIdAllowedFn, resolveToolMadCommIdFn, collectEntriesFn)
    local function isAllowed(idNum)
        if type(isMadCommIdAllowedFn) ~= "function" then
            return true
        end
        return isMadCommIdAllowedFn(idNum) == true
    end

    if forceMineMadCommId and forceMineMadCommId > 0 and madCommEvents then
        local forcedFolder = madCommEvents:FindFirstChild(tostring(forceMineMadCommId))
        local forcedRemote = forcedFolder and forcedFolder:FindFirstChild("Activate")
        if forcedRemote and forcedRemote:IsA("RemoteEvent") and isAllowed(forceMineMadCommId) then
            return forcedRemote
        end
    end

    if tool then
        local resolveFn = resolveToolMadCommIdFn or AutoMineSystem.resolveToolMadCommId
        local madCommId = resolveFn(tool)
        if madCommId and madCommEvents then
            local commFolder = madCommEvents:FindFirstChild(tostring(madCommId))
            local remote = commFolder and commFolder:FindFirstChild("Activate")
            if remote and isAllowed(madCommId) then
                return remote
            end
        end
        local nested = tool:FindFirstChild("Activate", true)
        if nested then
            return nested
        end
    end

    local collectFn = collectEntriesFn or AutoMineSystem.collectNumericMadCommActivateEntries
    local discovered = madCommEvents and collectFn(madCommEvents, nil) or {}
    if #discovered > 0 then
        return discovered[1].remote
    end
    return nil
end

function AutoMineSystem.pickMineActivateRemoteAlternateDiscovered(tool, madCommEvents, forceMineMadCommId, isMadCommIdAllowedFn, resolveToolMadCommIdFn, collectEntriesFn, alternateCounter)
    local function isAllowed(idNum)
        if type(isMadCommIdAllowedFn) ~= "function" then
            return true
        end
        return isMadCommIdAllowedFn(idNum) == true
    end

    if forceMineMadCommId and forceMineMadCommId > 0 and madCommEvents then
        local forcedFolder = madCommEvents:FindFirstChild(tostring(forceMineMadCommId))
        local forcedRemote = forcedFolder and forcedFolder:FindFirstChild("Activate")
        if forcedRemote and forcedRemote:IsA("RemoteEvent") and isAllowed(forceMineMadCommId) then
            return forcedRemote, alternateCounter
        end
    end

    if tool and madCommEvents then
        local resolveFn = resolveToolMadCommIdFn or AutoMineSystem.resolveToolMadCommId
        local madCommId = resolveFn(tool)
        if madCommId then
            local folder = madCommEvents:FindFirstChild(tostring(madCommId))
            local bound = folder and folder:FindFirstChild("Activate")
            if bound and bound:IsA("RemoteEvent") and isAllowed(madCommId) then
                return bound, alternateCounter
            end
        end
        local nested = tool:FindFirstChild("Activate", true)
        if nested and nested:IsA("RemoteEvent") then
            return nested, alternateCounter
        end
    end

    local collectFn = collectEntriesFn or AutoMineSystem.collectNumericMadCommActivateEntries
    local discovered = madCommEvents and collectFn(madCommEvents, nil) or {}
    local counter = tonumber(alternateCounter) or 0
    if #discovered >= 2 then
        counter = counter + 1
        local idx = ((counter - 1) % #discovered) + 1
        return discovered[idx].remote, counter
    end
    if #discovered == 1 then
        return discovered[1].remote, counter
    end

    return AutoMineSystem.resolveActivateRemote(
        tool,
        madCommEvents,
        forceMineMadCommId,
        isMadCommIdAllowedFn,
        resolveToolMadCommIdFn,
        collectEntriesFn
    ), counter
end

local _terrainScanCache = {
    lastScanAt = 0,
    lastPlayerPos = nil,
    cells = {},
    scanInterval = 0.35,
}

function AutoMineSystem.clearTerrainCache()
    _terrainScanCache.lastScanAt = 0
    _terrainScanCache.lastPlayerPos = nil
    _terrainScanCache.cells = {}
end

function AutoMineSystem.getNearbyTerrainBlock(localPlayer, effectiveRange, isIgnoredOreFn, pickaxeDamage)
    local RS = game:GetService("ReplicatedStorage")
    local packages = RS:FindFirstChild("Packages")
    local miningPkg = packages and packages:FindFirstChild("Mining")
    local mineTerrainMod = miningPkg and miningPkg:FindFirstChild("MineTerrain")
    if not mineTerrainMod then return nil end

    local ok, MineTerrain = pcall(require, mineTerrainMod)
    if not ok or not MineTerrain or type(MineTerrain.GetInstance) ~= "function" then return nil end

    local inst = MineTerrain.GetInstance()
    local char = localPlayer and localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local terrain = workspace.Terrain
    if not terrain or type(terrain.WorldToCell) ~= "function" then return nil end

    local now = os.clock()
    local playerPos = hrp.Position
    local maxRange = effectiveRange or 25

    -- Fast-path: Check cached candidate cells before doing an expensive 3D loop
    if #_terrainScanCache.cells > 0 and (now - _terrainScanCache.lastScanAt < _terrainScanCache.scanInterval) and _terrainScanCache.lastPlayerPos and (playerPos - _terrainScanCache.lastPlayerPos).Magnitude < 8 then
        for i = #_terrainScanCache.cells, 1, -1 do
            local item = _terrainScanCache.cells[i]
            local d = inst:Get(item.cell)
            if d and d.Ore and d.Block and d.Block ~= "Air" then
                local ignored = false
                if type(isIgnoredOreFn) == "function" then
                    ignored = isIgnoredOreFn(item.oreName) or isIgnoredOreFn(d.Ore)
                end
                if not ignored then
                    local worldPos = terrain:CellCenterToWorld(item.cell.X, item.cell.Y, item.cell.Z)
                    local dist = (playerPos - worldPos).Magnitude
                    if dist <= maxRange then
                        return {
                            isTerrainCell = true,
                            cell = item.cell,
                            oreName = item.oreName,
                            dist = dist,
                        }
                    end
                end
            else
                table.remove(_terrainScanCache.cells, i)
            end
        end
    end

    -- Throttle fresh full scans so we don't spam 2000+ checks every 10ms
    if now - _terrainScanCache.lastScanAt < 0.25 and _terrainScanCache.lastPlayerPos and (playerPos - _terrainScanCache.lastPlayerPos).Magnitude < 4 then
        return nil
    end

    _terrainScanCache.lastScanAt = now
    _terrainScanCache.lastPlayerPos = playerPos
    _terrainScanCache.cells = {}

    local playerCell = terrain:WorldToCell(playerPos)
    local maxRadiusCells = math.clamp(math.floor(maxRange / 4), 1, 8)
    local maxDistSq = maxRadiusCells * maxRadiusCells

    local blockDefsMod = RS:FindFirstChild("Definitions") and RS.Definitions:FindFirstChild("BlockDefinitions")
    local okDefs, BlockDefinitions = pcall(require, blockDefsMod)
    local blockDefs = okDefs and BlockDefinitions or nil

    local bestOre = nil
    local bestOreDist = math.huge

    for dy = -maxRadiusCells, maxRadiusCells do
        for dx = -maxRadiusCells, maxRadiusCells do
            for dz = -maxRadiusCells, maxRadiusCells do
                local distSq = dx * dx + dy * dy + dz * dz
                if distSq <= maxDistSq then
                    local cell = Vector3int16.new(playerCell.X + dx, playerCell.Y + dy, playerCell.Z + dz)
                    local data = inst:Get(cell)
                    -- MUST BE AN ORE: data.Ore is required! Never mine plain stone or boundary blocks
                    if data and data.Ore and data.Block and data.Block ~= "Air" and data.Block ~= "BottomBoundary" and data.Block ~= "TopBoundary" and data.Block ~= "Ravine" and data.Block ~= "Cave" then
                        local blockId = data.Ore
                        local def = blockDefs and (blockDefs[blockId] or blockDefs[data.Block])
                        -- Only consider blocks that have valid Hardness (minable)
                        if not def or (def.Hardness and not (def.Types and def.Types.Boundary)) then
                            local oreName = (def and def.Name) or blockId
                            local ignored = false
                            if type(isIgnoredOreFn) == "function" then
                                ignored = isIgnoredOreFn(oreName) or isIgnoredOreFn(blockId)
                            end
                            if not ignored then
                                local cellDist = math.sqrt(distSq) * 4
                                local entry = {
                                    cell = cell,
                                    oreName = oreName,
                                    dist = cellDist,
                                }
                                table.insert(_terrainScanCache.cells, entry)
                                if cellDist < bestOreDist then
                                    bestOreDist = cellDist
                                    bestOre = {
                                        isTerrainCell = true,
                                        cell = cell,
                                        oreName = oreName,
                                        dist = cellDist,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return bestOre
end

return AutoMineSystem
