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

return AutoMineSystem
