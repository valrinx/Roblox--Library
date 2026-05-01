local SafeMove = {}

-- Configuration
SafeMove.Config = {
    DefaultSpeed = 16,           -- Normal walk speed
    MaxSpeed = 32,              -- Sprint-like max
    StepInterval = 0.1,         -- Physics update frequency
    ArrivalThreshold = 3,       -- Stops when within this distance
    MaxTimePerMove = 30,        -- Safety timeout
    RandomOffset = 2,           -- Max random deviation (human error)
}

-- Get HumanoidRootPart safely
function SafeMove.getHrp(character)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

-- Get Humanoid safely
function SafeMove.getHumanoid(character)
    if not character then return nil end
    return character:FindFirstChildOfClass("Humanoid")
end

-- Calculate safe speed with randomization
function SafeMove.getRandomizedSpeed(baseSpeed)
    local variance = math.random(-3, 3)
    return math.clamp(baseSpeed + variance, 8, SafeMove.Config.MaxSpeed)
end

-- Add small random offset to position (human imperfection)
function SafeMove.addHumanOffset(position)
    local offset = SafeMove.Config.RandomOffset
    return position + Vector3.new(
        math.random(-offset * 10, offset * 10) / 10,
        0,
        math.random(-offset * 10, offset * 10) / 10
    )
end

-- Clean up existing movement instances
function SafeMove.cleanup(character)
    if not character then return end
    local hrp = SafeMove.getHrp(character)
    if not hrp then return end
    
    for _, child in ipairs(hrp:GetChildren()) do
        if child.Name == "SafeMoveVelocity" or child.Name == "SafeMoveAttachment" then
            pcall(function() child:Destroy() end)
        end
    end
end

-- Main physics-based movement function (SAFEST)
function SafeMove.physicsMove(targetPos, options)
    options = options or {}
    local player = game:GetService("Players").LocalPlayer
    local character = player.Character
    if not character then return false, "No character" end
    
    local hrp = SafeMove.getHrp(character)
    local humanoid = SafeMove.getHumanoid(character)
    if not hrp or not humanoid then return false, "No hrp/humanoid" end
    
    -- Clean up any existing movement
    SafeMove.cleanup(character)
    
    -- Setup attachment
    local attachment = hrp:FindFirstChild("RootAttachment")
    if not attachment then
        attachment = Instance.new("Attachment")
        attachment.Name = "SafeMoveAttachment"
        attachment.Parent = hrp
    end
    
    -- Setup LinearVelocity
    local velocity = Instance.new("LinearVelocity")
    velocity.Name = "SafeMoveVelocity"
    velocity.Attachment0 = attachment
    velocity.MaxForce = math.huge
    velocity.VectorVelocity = Vector3.new(0, 0, 0)
    velocity.Parent = hrp
    
    -- Target with human offset
    local actualTarget = SafeMove.addHumanOffset(targetPos)
    local startTime = tick()
    local distance = (actualTarget - hrp.Position).Magnitude
    local estimatedTime = distance / SafeMove.Config.DefaultSpeed
    
    -- Movement loop
    while true do
        local currentPos = hrp.Position
        local remaining = (actualTarget - currentPos).Magnitude
        
        -- Check arrival
        if remaining <= SafeMove.Config.ArrivalThreshold then
            break
        end
        
        -- Safety timeout
        if tick() - startTime > math.max(estimatedTime * 2, SafeMove.Config.MaxTimePerMove) then
            break
        end
        
        -- Calculate direction and speed
        local toTarget = actualTarget - currentPos
        local direction
        if toTarget.Magnitude > 0.001 then
            direction = toTarget.Unit
        else
            direction = Vector3.new(0, 0, 0) -- Already at target
        end
        local speed = SafeMove.getRandomizedSpeed(options.speed or SafeMove.Config.DefaultSpeed)
        
        -- Slow down when approaching target (deceleration)
        if remaining < 10 then
            speed = speed * (remaining / 10)
        end
        
        -- Apply velocity
        velocity.VectorVelocity = direction * speed
        
        -- Random interval for human-like inconsistency
        task.wait(SafeMove.Config.StepInterval + math.random(1, 5) / 100)
    end
    
    -- Cleanup
    velocity.VectorVelocity = Vector3.new(0, 0, 0)
    task.wait(0.1)
    SafeMove.cleanup(character)
    
    return true, "Arrived"
end

-- Humanoid:MoveTo wrapper (safer than tween, uses Roblox pathfinding)
function SafeMove.humanoidMove(targetPos, options)
    options = options or {}
    local player = game:GetService("Players").LocalPlayer
    local character = player.Character
    if not character then return false, "No character" end
    
    local humanoid = SafeMove.getHumanoid(character)
    if not humanoid then return false, "No humanoid" end
    
    local hrp = SafeMove.getHrp(character)
    if not hrp then return false, "No hrp" end
    
    local actualTarget = SafeMove.addHumanOffset(targetPos)
    local startTime = tick()
    
    -- For long distances, break into waypoints
    local currentPos = hrp.Position
    local totalDistance = (actualTarget - currentPos).Magnitude
    
    if totalDistance > 30 and not options.direct then
        -- Multi-segment movement (more human-like)
        local segments = math.floor(totalDistance / 20)
        for i = 1, segments do
            local t = i / segments
            local waypoint = currentPos:Lerp(actualTarget, t)
            waypoint = SafeMove.addHumanOffset(waypoint)
            
            humanoid:MoveTo(waypoint)
            local reached = humanoid.MoveToFinished:Wait()
            
            if not reached then break end
            
            -- Small pause between segments
            if i < segments then
                task.wait(math.random(5, 20) / 100)
            end
        end
    else
        -- Direct move
        humanoid:MoveTo(actualTarget)
        humanoid.MoveToFinished:Wait()
    end
    
    local elapsed = tick() - startTime
    return true, string.format("Moved in %.1fs", elapsed)
end

-- Smart approach: physics move to range, then remote action
function SafeMove.smartApproach(targetPos, remoteAction, options)
    options = options or {}
    local player = game:GetService("Players").LocalPlayer
    local character = player.Character
    if not character then return false, "No character" end
    
    local hrp = SafeMove.getHrp(character)
    if not hrp then return false, "No hrp" end
    
    local currentDistance = (targetPos - hrp.Position).Magnitude
    local remoteRange = options.remoteRange or 10
    
    -- If already in range, just do action
    if currentDistance <= remoteRange then
        if type(remoteAction) == "function" then
            return remoteAction()
        end
        return true, "Already in range"
    end
    
    -- Move to edge of remote range
    local approachDistance = math.max(remoteRange - 2, 5)
    local toTarget = targetPos - hrp.Position
    local direction
    if toTarget.Magnitude > 0.001 then
        direction = toTarget.Unit
    else
        direction = Vector3.new(0, 0, 1)
    end
    local approachPos = targetPos - (direction * approachDistance)
    
    -- Move using physics
    local moved, msg = SafeMove.physicsMove(approachPos, options)
    if not moved then return false, msg end
    
    -- Small pause before action
    task.wait(math.random(10, 30) / 100)
    
    -- Perform remote action
    if type(remoteAction) == "function" then
        return remoteAction()
    end
    
    return true, "Approached and executed"
end

-- Stop all movement immediately
function SafeMove.stop(character)
    SafeMove.cleanup(character)
    local humanoid = SafeMove.getHumanoid(character)
    if humanoid then
        humanoid:Move(Vector3.new(0, 0, 0))
    end
end

return SafeMove
