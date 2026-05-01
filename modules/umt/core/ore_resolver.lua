local OreResolver = {}

local defaultKnownOreNames = {
    "Tin", "Iron", "Lead", "Cobalt", "Aluminium", "Silver", "Unknown", "Uranium", "Vanadium",
    "Tungsten", "Gold", "Titanium", "Molybdenum", "Palladium", "Plutonium", "Mithril", "Thorium",
    "Iridium", "Adamantium", "Rhodium", "Unobtanium", "EXPLOSIVES", "Blue Chalk", "Green Chalk", "Red Chalk",
    "Topaz", "Emerald", "Sapphire",
    "Ruby", "Diamond", "Poudretteite", "Zultanite", "Grandidierite", "Musgravite", "Painite",
}

local defaultKnownOreCanonical = {
    ["tin"] = "Tin", ["iron"] = "Iron", ["lead"] = "Lead", ["cobalt"] = "Cobalt", ["aluminium"] = "Aluminium",
    ["silver"] = "Silver", ["unknown"] = "Unknown", ["uranium"] = "Uranium", ["vanadium"] = "Vanadium",
    ["tungsten"] = "Tungsten", ["gold"] = "Gold", ["titanium"] = "Titanium", ["molybdenum"] = "Molybdenum",
    ["palladium"] = "Palladium", ["plutonium"] = "Plutonium", ["mithril"] = "Mithril", ["thorium"] = "Thorium",
    ["iridium"] = "Iridium",
    ["adamantium"] = "Adamantium", ["rhodium"] = "Rhodium", ["unobtanium"] = "Unobtanium",
    ["explosives"] = "EXPLOSIVES",
    ["blue chalk"] = "Blue Chalk", ["green chalk"] = "Green Chalk", ["red chalk"] = "Red Chalk",
    ["topaz"] = "Topaz", ["emerald"] = "Emerald", ["sapphire"] = "Sapphire", ["ruby"] = "Ruby", ["diamond"] = "Diamond",
    ["poudretteite"] = "Poudretteite", ["zultanite"] = "Zultanite", ["grandidierite"] = "Grandidierite",
    ["musgravite"] = "Musgravite", ["painite"] = "Painite",
}

local defaultGenericOreNames = {
    ["Part"] = true,
    ["MeshPart"] = true,
    ["Model"] = true,
    ["Unknown"] = true,
    ["SurfaceAppearance"] = true,
    ["OreMesh"] = true,
    ["CrystallineMetalOre"] = true,
    ["CubicBlockMetal"] = true,
    ["ShaleMetalBlock"] = true,
    ["GemBlockMesh"] = true,
}

function OreResolver.normalizeOreToken(value)
    if value == nil then return nil end
    local text = tostring(value)
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    return text
end

function OreResolver.normalizeNameForMatch(name)
    local text = OreResolver.normalizeOreToken(name)
    if not text then return nil end
    text = text:gsub("([a-z])([A-Z])", "%1 %2")
    text = text:gsub("[_%-%./]", " ")
    text = text:gsub("%d+", " ")
    text = text:gsub("%s+", " ")
    return string.lower(text)
end

function OreResolver.colorToShortString(color)
    if typeof(color) ~= "Color3" then
        return "0,0,0"
    end
    return string.format(
        "%d,%d,%d",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5)
    )
end

function OreResolver.colorDistanceSq(a, b)
    if typeof(a) ~= "Color3" or typeof(b) ~= "Color3" then
        return math.huge
    end
    local ar, ag, ab = a.R * 255, a.G * 255, a.B * 255
    local br, bg, bb = b.R * 255, b.G * 255, b.B * 255
    local dr, dg, db = ar - br, ag - bg, ab - bb
    return (dr * dr) + (dg * dg) + (db * db)
end

function OreResolver.numberToShortString(n)
    if type(n) ~= "number" then return "0" end
    return string.format("%.2f", n)
end

function OreResolver.isInstance(value)
    return typeof(value) == "Instance"
end

function OreResolver.getOreRenderPart(target)
    if not OreResolver.isInstance(target) then return nil end
    if target:IsA("BasePart") then return target end
    if target:IsA("Model") then
        if target.PrimaryPart and target.PrimaryPart:IsA("BasePart") then
            return target.PrimaryPart
        end
        local mesh = target:FindFirstChildWhichIsA("MeshPart", true)
        if mesh then
            return mesh
        end
        local bestPart = nil
        local bestSize = -1
        for _, desc in ipairs(target:GetDescendants()) do
            if desc:IsA("BasePart") then
                local s = desc.Size
                local score = (s.X * s.Y * s.Z)
                if score > bestSize then
                    bestSize = score
                    bestPart = desc
                end
            end
        end
        if bestPart then
            return bestPart
        end
        return target:FindFirstChildWhichIsA("BasePart", true)
    end
    if target.FindFirstChildWhichIsA then
        return target:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

function OreResolver.getStringAttribute(instance, key)
    if not instance then return nil end
    local ok, value = pcall(function()
        return instance:GetAttribute(key)
    end)
    if not ok then return nil end
    return OreResolver.normalizeOreToken(value)
end

function OreResolver.canonicalizeOreName(name, knownOreCanonical)
    local normalized = OreResolver.normalizeNameForMatch(name)
    if not normalized then return nil end
    local tableRef = knownOreCanonical or defaultKnownOreCanonical
    return tableRef[normalized] or nil
end

function OreResolver.pickKnownOreFromText(name, knownOreNames)
    local normalized = OreResolver.normalizeNameForMatch(name)
    if not normalized then return nil end
    local list = knownOreNames or defaultKnownOreNames
    if type(list) ~= "table" then return nil end
    for _, ore in ipairs(list) do
        local token = string.lower(ore)
        if normalized == token or normalized:find("%f[%a]" .. token .. "%f[^%a]") then
            return ore
        end
    end
    return nil
end

function OreResolver.makeOreSignature(target, renderPart)
    local ok, signature = pcall(function()
        local part = OreResolver.isInstance(renderPart) and renderPart or nil
        if not part then
            local okRender, resolvedPart = pcall(OreResolver.getOreRenderPart, target)
            if okRender and OreResolver.isInstance(resolvedPart) then
                part = resolvedPart
            end
        end
        if not OreResolver.isInstance(part) then
            return nil
        end

        local className = part.ClassName or "Part"
        local nodeName = OreResolver.normalizeOreToken(part.Name) or "Unknown"
        local material = tostring(part.Material or "Plastic")
        local color = OreResolver.colorToShortString(part.Color)
        local size = part.Size
        local sizeText = "0,0,0"
        if typeof(size) == "Vector3" then
            sizeText = table.concat({
                OreResolver.numberToShortString(size.X),
                OreResolver.numberToShortString(size.Y),
                OreResolver.numberToShortString(size.Z),
            }, ",")
        end

        local meshId = ""
        local textureId = ""
        if part:IsA("MeshPart") then
            meshId = OreResolver.normalizeOreToken(part.MeshId) or ""
            textureId = OreResolver.normalizeOreToken(part.TextureID) or ""
        end

        return table.concat({
            className,
            nodeName,
            material,
            color,
            sizeText,
            meshId,
            textureId,
        }, "|")
    end)

    if not ok then
        return nil
    end
    return signature
end

function OreResolver.makeOreSignatureCoarse(target, renderPart)
    local signature = OreResolver.makeOreSignature(target, renderPart)
    if not signature then
        return nil
    end
    local parts = {}
    for part in string.gmatch(signature, "([^|]+)") do
        table.insert(parts, part)
    end
    if #parts < 7 then
        return signature
    end
    return table.concat({
        parts[1] or "",
        parts[3] or "",
        parts[4] or "",
        parts[6] or "",
        parts[7] or "",
    }, "|")
end

function OreResolver.makeOreColorSignature(target, renderPart)
    local part = renderPart
    if not OreResolver.isInstance(part) then
        part = OreResolver.getOreRenderPart(target)
    end
    if not OreResolver.isInstance(part) then
        return nil
    end

    local className = part.ClassName or "Part"
    local material = tostring(part.Material or "Plastic")
    local color = OreResolver.colorToShortString(part.Color)
    local meshId = ""
    if part:IsA("MeshPart") then
        meshId = OreResolver.normalizeOreToken(part.MeshId) or ""
    end
    return table.concat({ className, material, color, meshId }, "|")
end

function OreResolver.isMeaningfulOreName(name, genericOreNames)
    local n = OreResolver.normalizeOreToken(name)
    if not n then return false end
    local generics = genericOreNames or defaultGenericOreNames
    if type(generics) ~= "table" then return true end
    return not generics[n]
end

function OreResolver.getNameFromAttributes(instance, genericOreNames)
    if not instance then return nil end
    local keys = { "OreName", "MineId", "OreId", "ResourceName", "DisplayName", "ItemName", "Name" }
    for _, key in ipairs(keys) do
        local value = OreResolver.getStringAttribute(instance, key)
        if OreResolver.isMeaningfulOreName(value, genericOreNames) then
            return value
        end
    end
    for _, key in ipairs(keys) do
        local value = OreResolver.getStringAttribute(instance, key)
        if value then
            return value
        end
    end
    return nil
end

function OreResolver.getOreIdentifier(instance)
    if not OreResolver.isInstance(instance) then return nil end
    local keys = { "MineId", "OreId", "ResourceId", "BlockId", "Id" }
    for _, key in ipairs(keys) do
        local value = OreResolver.getStringAttribute(instance, key)
        if value then
            return value
        end
    end
    return nil
end

function OreResolver.getOreIdentifierDeep(target, renderPart)
    local direct = OreResolver.getOreIdentifier(target) or OreResolver.getOreIdentifier(renderPart)
    if direct then return direct end

    local function scanDescendants(instance)
        if not instance or not instance.GetDescendants then return nil end
        for _, desc in ipairs(instance:GetDescendants()) do
            local found = OreResolver.getOreIdentifier(desc)
            if found then
                return found
            end
        end
        return nil
    end

    return scanDescendants(target) or scanDescendants(renderPart)
end

function OreResolver.getNameFromValueObjects(instance, genericOreNames)
    if not instance then return nil end
    local preferred = { "OreName", "MineId", "OreId", "ResourceName", "DisplayName", "ItemName" }
    for _, key in ipairs(preferred) do
        local valueObj = instance:FindFirstChild(key, true)
        if valueObj and valueObj:IsA("StringValue") then
            local value = OreResolver.normalizeOreToken(valueObj.Value)
            if OreResolver.isMeaningfulOreName(value, genericOreNames) then
                return value
            end
        end
    end
    return nil
end

function OreResolver.getNameFromDescendantHints(instance, knownOreNames, knownOreCanonical)
    if not OreResolver.isInstance(instance) or not instance.GetDescendants then
        return nil
    end

    for _, desc in ipairs(instance:GetDescendants()) do
        if desc:IsA("StringValue") then
            local n = string.lower(desc.Name or "")
            local nameLooksRelevant = n:find("ore", 1, true)
                or n:find("mine", 1, true)
                or n:find("resource", 1, true)
                or n:find("id", 1, true)
            if nameLooksRelevant then
                local fromValueName = OreResolver.pickKnownOreFromText(desc.Name, knownOreNames)
                if fromValueName then
                    return fromValueName
                end
            end
            local fromStringValue = OreResolver.pickKnownOreFromText(desc.Value, knownOreNames)
            if fromStringValue then
                return fromStringValue
            end
        end
    end

    return nil
end

function OreResolver.findOreTargetFromInstance(instance)
    local node = instance
    local placedOre = workspace:FindFirstChild("PlacedOre")
    local spawnedBlocks = workspace:FindFirstChild("SpawnedBlocks")
    local lastRenderable = nil
    while node and node.Parent do
        if node:IsA("BasePart") or node:IsA("Model") then
            lastRenderable = node
        end
        if (placedOre and node.Parent == placedOre) or (spawnedBlocks and node.Parent == spawnedBlocks) then
            if lastRenderable and lastRenderable ~= placedOre and lastRenderable ~= spawnedBlocks then
                return lastRenderable
            end
            return node
        end
        node = node.Parent
    end
    return nil
end

function OreResolver.getLookedOreTarget()
    local players = game:GetService("Players")
    local localPlayer = players.LocalPlayer
    local camera = workspace.CurrentCamera
    if not localPlayer or not camera then return nil end

    local viewport = camera.ViewportSize
    local ray = camera:ViewportPointToRay(viewport.X * 0.5, viewport.Y * 0.5)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = { localPlayer.Character }

    local hit = workspace:Raycast(ray.Origin, ray.Direction * 700, params)
    if hit and hit.Instance then
        return OreResolver.findOreTargetFromInstance(hit.Instance)
    end

    local mouse = localPlayer:GetMouse()
    if mouse and mouse.Target then
        return OreResolver.findOreTargetFromInstance(mouse.Target)
    end
    return nil
end

function OreResolver.getTargetGridPosition(target, renderPart)
    if not OreResolver.isInstance(target) then return nil end
    local gridPos = target:GetAttribute("ChunkPosition") or target:GetAttribute("GridPosition")
    if not gridPos and renderPart then
        gridPos = renderPart:GetAttribute("ChunkPosition") or renderPart:GetAttribute("GridPosition")
    end
    return gridPos
end

function OreResolver.isMineableTarget(target, renderPart)
    if not target then return false end
    if target:GetAttribute("MineId") or target:GetAttribute("OreId") then
        return true
    end
    if renderPart and (renderPart:GetAttribute("MineId") or renderPart:GetAttribute("OreId")) then
        return true
    end
    return OreResolver.getTargetGridPosition(target, renderPart) ~= nil
end

function OreResolver.getMappedOreNameOnly(target, renderPart, mappings, useStrictColorRules)
    mappings = mappings or {}
    local ok, mapped, source = pcall(function()
        local oreId = OreResolver.getOreIdentifierDeep(target, renderPart)
        if oreId and mappings.oreNameById and mappings.oreNameById[oreId] then
            return mappings.oreNameById[oreId], "id"
        end
        local colorSignature = OreResolver.makeOreColorSignature(target, renderPart)
        if colorSignature and mappings.oreNameByStaticColorSignature and mappings.oreNameByStaticColorSignature[colorSignature] then
            return mappings.oreNameByStaticColorSignature[colorSignature], "static-color"
        end
        if colorSignature and mappings.sharedOreNameByColorSignature and mappings.sharedOreNameByColorSignature[colorSignature] then
            return mappings.sharedOreNameByColorSignature[colorSignature], "shared-color"
        end
        if useStrictColorRules then
            if colorSignature and mappings.oreNameByColorSignature and mappings.oreNameByColorSignature[colorSignature] then
                return mappings.oreNameByColorSignature[colorSignature], "color"
            end
            return nil, nil
        end
        local signature = OreResolver.makeOreSignature(target, renderPart)
        if signature and mappings.oreNameBySignature and mappings.oreNameBySignature[signature] then
            return mappings.oreNameBySignature[signature], "signature"
        end
        local coarseSignature = OreResolver.makeOreSignatureCoarse(target, renderPart)
        if coarseSignature and mappings.oreNameBySignatureCoarse and mappings.oreNameBySignatureCoarse[coarseSignature] then
            return mappings.oreNameBySignatureCoarse[coarseSignature], "coarse"
        end
        if colorSignature and mappings.oreNameByColorSignature and mappings.oreNameByColorSignature[colorSignature] then
            return mappings.oreNameByColorSignature[colorSignature], "color"
        end
        local runtimeName = OreResolver.normalizeOreToken(OreResolver.isInstance(target) and target.Name or nil)
        local genericRuntime = runtimeName == "OreMesh" or runtimeName == "CrystallineMetalOre" or runtimeName == "CubicBlockMetal" or runtimeName == "ShaleMetalBlock" or runtimeName == "GemBlockMesh"
        if runtimeName and not genericRuntime and mappings.oreNameByRuntime and mappings.oreNameByRuntime[runtimeName] then
            return mappings.oreNameByRuntime[runtimeName], "runtime"
        end
        return nil, nil
    end)
    if not ok then
        return nil, nil
    end
    return mapped, source
end

function OreResolver.scoreOreCandidate(bucket, candidate, score)
    if not candidate or not score then return end
    bucket[candidate] = (bucket[candidate] or 0) + score
end

function OreResolver.collectOreCandidatesFromInstance(instance, bucket, baseScore, scanDescendants, knownOreNames, knownOreCanonical)
    if not OreResolver.isInstance(instance) then return end
    local function hasOreKeyHint(text)
        local n = string.lower(tostring(text or ""))
        return n:find("ore", 1, true)
            or n:find("mine", 1, true)
            or n:find("resource", 1, true)
            or n:find("metal", 1, true)
            or n:find("gem", 1, true)
            or n:find("id", 1, true)
            or n:find("type", 1, true)
    end

    local attrKeys = { "OreName", "MineId", "OreId", "ResourceName", "DisplayName", "ItemName" }
    for _, key in ipairs(attrKeys) do
        local value = OreResolver.getStringAttribute(instance, key)
        local fromAttr = OreResolver.canonicalizeOreName(value, knownOreCanonical) or OreResolver.pickKnownOreFromText(value, knownOreNames)
        if fromAttr then
            OreResolver.scoreOreCandidate(bucket, fromAttr, baseScore + 12)
        end
    end

    local function scanOne(desc)
        if not OreResolver.isInstance(desc) then return end
        if desc.Name == "UH_ESP_Billboard" or desc.Name == "UH_ESP_Highlight" then
            return
        end
        if desc:IsA("BillboardGui") or desc:IsA("TextLabel") or desc:IsA("TextButton") then
            return
        end

        if desc:IsA("StringValue") then
            if not hasOreKeyHint(desc.Name) then
                return
            end
            local fromValueName = OreResolver.canonicalizeOreName(desc.Name, knownOreCanonical) or OreResolver.pickKnownOreFromText(desc.Name, knownOreNames)
            local fromValueText = OreResolver.canonicalizeOreName(desc.Value, knownOreCanonical) or OreResolver.pickKnownOreFromText(desc.Value, knownOreNames)
            if fromValueName then OreResolver.scoreOreCandidate(bucket, fromValueName, baseScore + 6) end
            if fromValueText then OreResolver.scoreOreCandidate(bucket, fromValueText, baseScore + 9) end
        elseif desc:IsA("IntValue") or desc:IsA("NumberValue") then
            if not hasOreKeyHint(desc.Name) then
                return
            end
            local fromNumericName = OreResolver.canonicalizeOreName(desc.Name, knownOreCanonical) or OreResolver.pickKnownOreFromText(desc.Name, knownOreNames)
            if fromNumericName then
                OreResolver.scoreOreCandidate(bucket, fromNumericName, baseScore + 4)
            end
        end
    end

    if scanDescendants and instance.GetDescendants then
        local ok, descendants = pcall(function()
            return instance:GetDescendants()
        end)
        if ok and type(descendants) == "table" then
            local limit = math.min(#descendants, 180)
            for i = 1, limit do
                local desc = descendants[i]
                if OreResolver.isInstance(desc) then
                    scanOne(desc)
                end
            end
        end
    end
end

function OreResolver.inferOreNameFromTarget(target, renderPart, knownOreNames, knownOreCanonical)
    local bucket = {}
    OreResolver.collectOreCandidatesFromInstance(target, bucket, 12, true, knownOreNames, knownOreCanonical)
    OreResolver.collectOreCandidatesFromInstance(renderPart, bucket, 10, true, knownOreNames, knownOreCanonical)
    if OreResolver.isInstance(target) and OreResolver.isInstance(target.Parent) then
        OreResolver.collectOreCandidatesFromInstance(target.Parent, bucket, 6, false, knownOreNames, knownOreCanonical)
    end

    local bestName, bestScore = nil, -math.huge
    local secondBest = -math.huge
    for name, score in pairs(bucket) do
        if score > bestScore then
            secondBest = bestScore
            bestScore = score
            bestName = name
        elseif score > secondBest then
            secondBest = score
        end
    end

    if not bestName then
        return nil, 0
    end
    if bestScore < 18 then
        return nil, bestScore
    end
    if bestScore - secondBest < 5 then
        return nil, bestScore
    end
    return bestName, bestScore
end

function OreResolver.getNeighborConsensusName(target, renderPart, mappings, useStrictColorRules)
    if useStrictColorRules then
        return nil
    end
    if not OreResolver.isInstance(target) or not OreResolver.isInstance(renderPart) then
        return nil
    end
    local parent = target.Parent
    if not OreResolver.isInstance(parent) then
        return nil
    end

    local votes = {}
    local total = 0
    for _, neighbor in ipairs(parent:GetChildren()) do
        if neighbor ~= target and (neighbor:IsA("BasePart") or neighbor:IsA("Model")) then
            local neighborRender = OreResolver.getOreRenderPart(neighbor)
            if OreResolver.isInstance(neighborRender) then
                local dist = (neighborRender.Position - renderPart.Position).Magnitude
                if dist <= 14 then
                    local name, source = OreResolver.getMappedOreNameOnly(neighbor, neighborRender, mappings, useStrictColorRules)
                    if name and source ~= "runtime" then
                        votes[name] = (votes[name] or 0) + 1
                        total = total + 1
                    end
                end
            end
        end
    end

    if total < 3 then
        return nil
    end

    local bestName, bestCount = nil, 0
    for name, count in pairs(votes) do
        if count > bestCount then
            bestName = name
            bestCount = count
        end
    end

    if bestName and (bestCount / total) >= 0.7 then
        return bestName
    end
    return nil
end

function OreResolver.classifyOreByDirectColor(target, renderPart, oreNameByColorSignature, useDirectColorClassifier)
    if not useDirectColorClassifier then
        return nil
    end
    if type(oreNameByColorSignature) ~= "table" then
        return nil
    end

    local part = renderPart
    if not OreResolver.isInstance(part) then
        part = OreResolver.getOreRenderPart(target)
    end
    if not OreResolver.isInstance(part) then
        return nil
    end

    local bestName, bestDist = nil, math.huge
    local secondDist = math.huge

    for sig, mappedName in pairs(oreNameByColorSignature) do
        if type(sig) == "string" and type(mappedName) == "string" then
            local r, g, b = string.match(sig, "|(%d+),(%d+),(%d+)|")
            if r and g and b then
                local sampleColor = Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
                local d = OreResolver.colorDistanceSq(part.Color, sampleColor)
                if d < bestDist then
                    secondDist = bestDist
                    bestDist = d
                    bestName = mappedName
                elseif d < secondDist then
                    secondDist = d
                end
            end
        end
    end

    if not bestName then
        return nil
    end
    if bestDist > 2200 then
        return nil
    end
    if (secondDist - bestDist) < 280 then
        return nil
    end
    return bestName
end

function OreResolver.getTargetPosition(target)
    local renderPart = OreResolver.getOreRenderPart(target)
    if renderPart then
        return renderPart.Position
    end
    if typeof(target) == "Instance" and target:IsA("Model") then
        return target:GetPivot().Position
    end
    return nil
end

function OreResolver.countTableEntries(tbl)
    local n = 0
    if type(tbl) ~= "table" then return 0 end
    for _ in pairs(tbl) do
        n = n + 1
    end
    return n
end

function OreResolver.getOreCategory(oreName, oreCategoryByName)
    local map = oreCategoryByName or {}
    return map[oreName] or "Unknown"
end

function OreResolver.getOreColor(target, oreName, renderPart, oreColors, oreCategoryColors, oreCategoryByName)
    local part = renderPart
    if not OreResolver.isInstance(part) then
        part = OreResolver.getOreRenderPart(target)
    end
    if OreResolver.isInstance(part) and typeof(part.Color) == "Color3" then
        return part.Color
    end
    local category = OreResolver.getOreCategory(oreName, oreCategoryByName)
    return oreCategoryColors[category] or oreColors[oreName] or Color3.fromRGB(255, 255, 255)
end

return OreResolver
