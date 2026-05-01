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

return AutoMineSystem
