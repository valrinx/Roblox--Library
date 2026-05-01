local Sell = {}

function Sell.getNumericByKeys(instance, keys)
    if not instance or type(keys) ~= "table" then return nil end
    for _, key in ipairs(keys) do
        local attr = instance:GetAttribute(key)
        if type(attr) == "number" then return attr end
        local child = instance:FindFirstChild(key)
        if child then
            if child:IsA("NumberValue") or child:IsA("IntValue") or child:IsA("DoubleValue") then
                return child.Value
            elseif child:IsA("StringValue") then
                local n = tonumber(child.Value)
                if n then return n end
            end
        end
    end
    return nil
end

function Sell.countCarriedOres(player)
    local count = 0
    local playerWorkspace = workspace:FindFirstChild(player and player.Name or "")
    if playerWorkspace then
        local orePackCargo = playerWorkspace:FindFirstChild("OrePackCargo")
        if orePackCargo then
            for _, child in pairs(orePackCargo:GetChildren()) do
                if not child:IsA("Weld") and not child:IsA("Motor6D") and not child:IsA("Attachment") then
                    count = count + 1
                end
            end
        end
    end
    return count
end

function Sell.findSellTargets()
    local factoryGridItemsServer = workspace:FindFirstChild("FactoryGridItemsServer")
    if not factoryGridItemsServer then
        return nil, nil, "FactoryGridItemsServer not found!"
    end
    local factoryGridItemsClient = workspace:FindFirstChild("FactoryGridItemsClient")

    for _, folder in pairs(factoryGridItemsServer:GetChildren()) do
        if folder:IsA("Folder") then
            local cargoVolume = folder:FindFirstChild("CargoVolume") or folder:FindFirstChild("Unloader")
            if not cargoVolume then
                cargoVolume = folder:FindFirstChild("CargoVolume", true)
            end

            if cargoVolume then
                local foundPrompt = cargoVolume:FindFirstChild("CargoPrompt")
                    or cargoVolume:FindFirstChildOfClass("ProximityPrompt")
                    or cargoVolume:FindFirstChild("CargoPrompt", true)
                if not foundPrompt then
                    for _, desc in pairs(cargoVolume:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") then
                            foundPrompt = desc
                            break
                        end
                    end
                end
                if foundPrompt then
                    local positionCargoVolume = nil
                    if factoryGridItemsClient then
                        local clientFolder = factoryGridItemsClient:FindFirstChild(folder.Name)
                        if clientFolder then
                            local clientSubFolder = clientFolder:FindFirstChild(folder.Name)
                            if clientSubFolder then
                                positionCargoVolume = clientSubFolder:FindFirstChild("Unloader1")
                                    and clientSubFolder.Unloader1:FindFirstChild("CargoVolume")
                                    or clientSubFolder:FindFirstChild("CargoVolume", true)
                            end
                        end
                    end
                    return foundPrompt, positionCargoVolume, nil
                end
            end
        end
    end

    return nil, nil, "No working CargoVolume with ProximityPrompt found! Make sure someone has built an unloader."
end

function Sell.sellFromAnywhere(opts)
    opts = type(opts) == "table" and opts or {}
    local verifyCount = opts.verifyCount ~= false
    local overrideDistance = tonumber(opts.overrideDistance) or 1024

    local player = game.Players.LocalPlayer
    local cargoPrompt, _, err = Sell.findSellTargets()
    if not cargoPrompt then
        return false, err or "No working CargoVolume found!", 0
    end

    local oreCountBefore = 0
    if verifyCount then
        oreCountBefore = Sell.countCarriedOres(player)
    end

    local oldHold = cargoPrompt.HoldDuration
    local oldDistance = cargoPrompt.MaxActivationDistance
    local oldLos = cargoPrompt.RequiresLineOfSight

    pcall(function()
        cargoPrompt.HoldDuration = 0
        cargoPrompt.MaxActivationDistance = math.max(overrideDistance, tonumber(oldDistance) or 0)
        cargoPrompt.RequiresLineOfSight = false
    end)

    local okFire, fireErr = pcall(function()
        fireproximityprompt(cargoPrompt)
    end)

    pcall(function()
        cargoPrompt.HoldDuration = oldHold
        cargoPrompt.MaxActivationDistance = oldDistance
        cargoPrompt.RequiresLineOfSight = oldLos
    end)

    if not okFire then
        return false, tostring(fireErr), oreCountBefore
    end

    if not verifyCount then
        return true, nil, 0
    end

    task.wait(0.35)
    local oreCountAfter = Sell.countCarriedOres(player)
    local soldCount = math.max(0, oreCountBefore - oreCountAfter)
    if oreCountBefore > 0 and soldCount <= 0 then
        return false, "Remote sell blocked by server distance check.", oreCountBefore
    end
    return true, nil, soldCount > 0 and soldCount or oreCountBefore
end

function Sell.getBagCapacity(player)
    if not player then return nil end
    local maxOres = nil
    local stats = player:FindFirstChild("Stats")
    if stats then
        maxOres = Sell.getNumericByKeys(stats, {
            "MaxOres", "MaxOre", "BagCapacity", "Capacity", "OreCapacity", "MaxCargo", "CargoLimit"
        })
    end
    if not maxOres then
        local leaderstats = player:FindFirstChild("leaderstats")
        if leaderstats then
            maxOres = Sell.getNumericByKeys(leaderstats, {
                "MaxOres", "MaxOre", "BagCapacity", "Capacity", "OreCapacity"
            })
        end
    end
    local backpack = player:FindFirstChild("InnoBackpack")
    if backpack and not maxOres then
        maxOres = Sell.getNumericByKeys(backpack, {
            "MaxOres", "MaxOre", "Capacity", "BagCapacity", "Limit", "MaxItems"
        })
    end
    return maxOres
end

function Sell.isBagFull(player, thresholdPercent)
    thresholdPercent = tonumber(thresholdPercent) or 100
    local current = Sell.countCarriedOres(player)
    local maxCapacity = Sell.getBagCapacity(player)
    if not maxCapacity or maxCapacity <= 0 then
        return false, current, nil
    end
    local thresholdCount = math.floor(maxCapacity * (thresholdPercent / 100))
    local isFull = current >= thresholdCount
    return isFull, current, maxCapacity
end

function Sell.getSupportedMethods()
    return {"Remote (No TP / No Tween)"}
end

function Sell.sellByMethod(method, opts)
    method = tostring(method or "Remote")
    if method:find("Remote") then
        return Sell.sellFromAnywhere(opts)
    end
    return false, "Unsupported sell method: " .. method, 0
end

return Sell
