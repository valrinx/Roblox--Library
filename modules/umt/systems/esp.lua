local EspSystem = {}

function EspSystem.createConfig(autoSettingsLoaded)
    local settings = autoSettingsLoaded or {}
    local espState = {
        enabled = settings.oreEspEnabled == true,
        maxDistance = math.clamp(tonumber(settings.oreEspDistance) or 100, 0, 500),
        filterOre = settings.oreEspFilter or "All",
        activeVisuals = {},
        activeRenderParts = {},
        connections = {},
        useAdornment = true,
        updateInterval = 1 / 20,
        metaRefreshInterval = 0.22,
        lastUpdateAt = 0,
        applyDistancePadding = 70,
        discoveryInterval = 1.0,
        lastDiscoveryAt = 0,
    }

    local oreColors = {
        ["Tin"] = Color3.fromRGB(123, 133, 133),
        ["Iron"] = Color3.fromRGB(189, 125, 84),
        ["Lead"] = Color3.fromRGB(54, 56, 73),
        ["Cobalt"] = Color3.fromRGB(64, 116, 199),
        ["Aluminium"] = Color3.fromRGB(107, 108, 107),
        ["Silver"] = Color3.fromRGB(133, 171, 185),
        ["Uranium"] = Color3.fromRGB(87, 175, 87),
        ["Vanadium"] = Color3.fromRGB(166, 64, 46),
        ["Tungsten"] = Color3.fromRGB(65, 83, 76),
        ["Gold"] = Color3.fromRGB(241, 213, 121),
        ["Titanium"] = Color3.fromRGB(74, 77, 122),
        ["Molybdenum"] = Color3.fromRGB(138, 159, 153),
        ["Palladium"] = Color3.fromRGB(209, 160, 34),
        ["Plutonium"] = Color3.fromRGB(41, 137, 211),
        ["Mithril"] = Color3.fromRGB(83, 165, 134),
        ["Thorium"] = Color3.fromRGB(97, 130, 109),
        ["Iridium"] = Color3.fromRGB(171, 221, 41),
        ["Adamantium"] = Color3.fromRGB(80, 159, 116),
        ["Rhodium"] = Color3.fromRGB(170, 85, 0),
        ["Unobtanium"] = Color3.fromRGB(189, 80, 211),
        ["Topaz"] = Color3.fromRGB(154, 143, 56),
        ["Emerald"] = Color3.fromRGB(0, 143, 0),
        ["Sapphire"] = Color3.fromRGB(11, 36, 179),
        ["Ruby"] = Color3.fromRGB(193, 11, 11),
        ["Diamond"] = Color3.fromRGB(103, 182, 188),
        ["Poudretteite"] = Color3.fromRGB(202, 67, 200),
        ["Zultanite"] = Color3.fromRGB(202, 134, 117),
        ["Grandidierite"] = Color3.fromRGB(67, 202, 130),
        ["Musgravite"] = Color3.fromRGB(92, 97, 97),
        ["Painite"] = Color3.fromRGB(154, 68, 68),
        ["EXPLOSIVES"] = Color3.fromRGB(15, 12, 20),
    }

    local oreCategoryColors = {
        ["Common Metal"] = Color3.fromRGB(200, 200, 200),
        ["Rare Metal"] = Color3.fromRGB(120, 170, 255),
        ["Radioactive"] = Color3.fromRGB(80, 255, 120),
        ["Precious"] = Color3.fromRGB(255, 210, 90),
        ["Gemstone"] = Color3.fromRGB(255, 120, 220),
        ["Mythic"] = Color3.fromRGB(255, 110, 110),
        ["Unknown"] = Color3.fromRGB(255, 145, 70),
    }

    local oreCategoryByName = {
        ["Tin"] = "Common Metal", ["Iron"] = "Common Metal", ["Lead"] = "Common Metal", ["Aluminium"] = "Common Metal",
        ["Silver"] = "Rare Metal", ["Unknown"] = "Rare Metal", ["Cobalt"] = "Rare Metal", ["Tungsten"] = "Rare Metal", ["Titanium"] = "Rare Metal",
        ["Vanadium"] = "Rare Metal", ["Rhodium"] = "Rare Metal", ["Iridium"] = "Rare Metal", ["Palladium"] = "Rare Metal", ["Molybdenum"] = "Rare Metal",
        ["Uranium"] = "Radioactive", ["Plutonium"] = "Radioactive", ["Thorium"] = "Radioactive",
        ["Gold"] = "Precious",
        ["Topaz"] = "Gemstone", ["Emerald"] = "Gemstone", ["Sapphire"] = "Gemstone", ["Ruby"] = "Gemstone", ["Diamond"] = "Gemstone",
        ["Mithril"] = "Mythic", ["Adamantium"] = "Mythic", ["Unobtanium"] = "Mythic", ["Poudretteite"] = "Mythic",
        ["Zultanite"] = "Mythic", ["Grandidierite"] = "Mythic", ["Musgravite"] = "Mythic", ["Painite"] = "Mythic",
        ["EXPLOSIVES"] = "Unknown",
        ["OreMesh"] = "Rare Metal",
        ["CubicBlockMetal"] = "Common Metal",
        ["ShaleMetalBlock"] = "Rare Metal",
        ["GemBlockMesh"] = "Gemstone",
    }

    return {
        ESP = espState,
        oreColors = oreColors,
        oreCategoryColors = oreCategoryColors,
        oreCategoryByName = oreCategoryByName,
    }
end

function EspSystem.countActiveVisuals(espState)
    local n = 0
    if type(espState) ~= "table" or type(espState.activeVisuals) ~= "table" then
        return n
    end
    for _ in pairs(espState.activeVisuals) do
        n = n + 1
    end
    return n
end

function EspSystem.applyAdaptiveCadence(espState)
    if type(espState) ~= "table" then
        return
    end
    local visualCount = EspSystem.countActiveVisuals(espState)
    if visualCount > 220 then
        espState.updateInterval = 1 / 10
        espState.metaRefreshInterval = 0.5
    elseif visualCount > 120 then
        espState.updateInterval = 1 / 14
        espState.metaRefreshInterval = 0.35
    else
        espState.updateInterval = 1 / 20
        espState.metaRefreshInterval = 0.22
    end
end

return EspSystem
