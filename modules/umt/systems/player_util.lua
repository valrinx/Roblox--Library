local PlayerUtil = {}

function PlayerUtil.getHumanoid(player)
    if not player then
        return nil
    end
    local character = player.Character or player.CharacterAdded:Wait()
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

function PlayerUtil.setWalkSpeed(player, speed)
    local humanoid = PlayerUtil.getHumanoid(player)
    if humanoid then
        humanoid.WalkSpeed = speed
        return true
    end
    return false
end

function PlayerUtil.applyWalkSpeedOnSpawn(player, targetSpeed)
    if not player then
        return nil
    end
    targetSpeed = tonumber(targetSpeed) or 16
    local conn = player.CharacterAdded:Connect(function(character)
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.WalkSpeed = targetSpeed
        end
    end)
    return conn
end

function PlayerUtil.startInfiniteJump()
    local UserInputService = game:GetService("UserInputService")
    local connection = UserInputService.JumpRequest:Connect(function()
        local player = game.Players.LocalPlayer
        local character = player and (player.Character or player.CharacterAdded:Wait())
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                rootPart.Velocity = Vector3.new(rootPart.Velocity.X, 50, rootPart.Velocity.Z)
            end
        end
    end)
    return connection
end

function PlayerUtil.stopConnection(connection)
    if connection and type(connection.Disconnect) == "function" then
        pcall(function()
            connection:Disconnect()
        end)
    end
    return nil
end

function PlayerUtil.getRootPart(player)
    if not player then
        return nil
    end
    local character = player.Character
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

return PlayerUtil
