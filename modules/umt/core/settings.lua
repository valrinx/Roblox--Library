local Settings = {}

local function isStringMap(tbl)
    if type(tbl) ~= "table" then return false end
    for k, v in pairs(tbl) do
        if type(k) ~= "string" or type(v) ~= "string" then
            return false
        end
    end
    return true
end

local function copyStringMap(src)
    local out = {}
    if type(src) ~= "table" then
        return out
    end
    for k, v in pairs(src) do
        if type(k) == "string" and type(v) == "string" and k ~= "" and v ~= "" then
            out[k] = v
        end
    end
    return out
end

local function mergeStringMap(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then return end
    for k, v in pairs(src) do
        if type(k) == "string" and type(v) == "string" and k ~= "" and v ~= "" then
            dst[k] = v
        end
    end
end

local function sanitizeStringArray(src)
    local out = {}
    if type(src) ~= "table" then
        return out
    end
    for _, value in ipairs(src) do
        if type(value) == "string" and value ~= "" then
            table.insert(out, value)
        end
    end
    return out
end

function Settings.buildDefaults(currentVersion)
    return {
        settingsVersion = tonumber(currentVersion) or 1,
        autoMineEnabled = false,
        autoMineRange = 10,
        autoMineDelay = 1.2,
        forceMineDamage = 0,
        forceMineMadCommId = 0,
        safeProfileEnabled = true,
        safeNearbyPauseEnabled = true,
        safeNearbyRadius = 70,
        safeSellCooldown = 6,
        oreIgnoreList = {},
        autoSellEnabled = false,
        autoSellOreCount = 8,
        autoSellMethod = "Remote",
        walkSpeed = 16,
        infiniteJumpEnabled = false,
        sellOreKey = "",
        oreEspEnabled = false,
        oreEspDistance = 100,
        oreEspFilter = "All",
        oreNameById = {},
        oreNameByRuntime = {},
        oreNameBySignature = {},
        oreNameBySignatureCoarse = {},
        oreNameByColorSignature = {},
        sharedOreNameByColorSignature = {},
    }
end

function Settings.unwrapPayload(decoded)
    if type(decoded) ~= "table" then
        return nil
    end
    if decoded.kind == "UMTFullSettings" and type(decoded.data) == "table" then
        return decoded.data
    end
    return decoded
end

local HttpService = game:GetService("HttpService")
local saveTaskId = 0

function Settings.saveAsync(settingsFile, canWrite, getPayload, onComplete)
    if not canWrite then
        if type(onComplete) == "function" then
            onComplete(false, "writefile unavailable")
        end
        return
    end
    saveTaskId = saveTaskId + 1
    local currentTaskId = saveTaskId
    task.delay(0.2, function()
        if currentTaskId ~= saveTaskId then
            return
        end
        local payload = nil
        if type(getPayload) == "function" then
            payload = getPayload()
        end
        local okWrite, errWrite = pcall(function()
            writefile(settingsFile, HttpService:JSONEncode(payload))
        end)
        if type(onComplete) == "function" then
            onComplete(okWrite, okWrite and nil or (errWrite and tostring(errWrite) or "unknown"))
        end
    end)
end

function Settings.applyDecoded(defaults, decoded, currentVersion)
    if type(defaults) ~= "table" or type(decoded) ~= "table" then
        return defaults, false
    end
    defaults.settingsVersion = tonumber(decoded.settingsVersion) or 1
    defaults.autoMineEnabled = decoded.autoMineEnabled == true
    defaults.autoMineRange = tonumber(decoded.autoMineRange) or defaults.autoMineRange
    defaults.autoMineDelay = tonumber(decoded.autoMineDelay) or defaults.autoMineDelay
    defaults.forceMineDamage = tonumber(decoded.forceMineDamage) or defaults.forceMineDamage
    defaults.forceMineMadCommId = tonumber(decoded.forceMineMadCommId) or defaults.forceMineMadCommId
    if decoded.safeProfileEnabled ~= nil then
        defaults.safeProfileEnabled = decoded.safeProfileEnabled == true
    end
    if decoded.safeNearbyPauseEnabled ~= nil then
        defaults.safeNearbyPauseEnabled = decoded.safeNearbyPauseEnabled == true
    end
    defaults.safeNearbyRadius = tonumber(decoded.safeNearbyRadius) or defaults.safeNearbyRadius
    defaults.safeSellCooldown = tonumber(decoded.safeSellCooldown) or defaults.safeSellCooldown
    defaults.oreIgnoreList = sanitizeStringArray(decoded.oreIgnoreList)
    defaults.autoSellEnabled = decoded.autoSellEnabled == true
    defaults.autoSellOreCount = tonumber(decoded.autoSellOreCount) or defaults.autoSellOreCount
    defaults.autoSellMethod = "Remote"
    defaults.walkSpeed = tonumber(decoded.walkSpeed) or defaults.walkSpeed
    defaults.infiniteJumpEnabled = decoded.infiniteJumpEnabled == true
    if type(decoded.sellOreKey) == "string" then
        defaults.sellOreKey = decoded.sellOreKey
    end
    defaults.oreEspEnabled = decoded.oreEspEnabled == true
    defaults.oreEspDistance = tonumber(decoded.oreEspDistance) or defaults.oreEspDistance
    if type(decoded.oreEspFilter) == "string" and decoded.oreEspFilter ~= "" then
        defaults.oreEspFilter = decoded.oreEspFilter
    end
    defaults.oreNameById = copyStringMap(decoded.oreNameById)
    defaults.oreNameByRuntime = copyStringMap(decoded.oreNameByRuntime)
    defaults.oreNameBySignature = copyStringMap(decoded.oreNameBySignature)
    defaults.oreNameBySignatureCoarse = copyStringMap(decoded.oreNameBySignatureCoarse)
    defaults.oreNameByColorSignature = copyStringMap(decoded.oreNameByColorSignature)
    defaults.sharedOreNameByColorSignature = copyStringMap(decoded.sharedOreNameByColorSignature)

    if defaults.settingsVersion < (tonumber(currentVersion) or defaults.settingsVersion) then
        defaults.settingsVersion = tonumber(currentVersion) or defaults.settingsVersion
    end
    return defaults, true
end

return Settings
