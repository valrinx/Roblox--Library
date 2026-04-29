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
            if otherRoot and (otherRoot.Position - rootPart.Position).Magnitude <= radius then
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

function AutoMineSystem.getMadCommIdFromRemote(remote)
    if not remote or not remote.Parent then
        return nil
    end
    return AutoMineSystem.normalizeMadCommId(remote.Parent.Name)
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

return AutoMineSystem
