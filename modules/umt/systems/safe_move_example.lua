-- Example: How to use safe_move.lua
-- This is a usage example, not for direct loading

local SafeMove = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/valrinx/Roblox--Library/refs/heads/main/modules/umt/systems/safe_move.lua"
))()

-- ============================================================
-- EXAMPLE 1: Simple physics movement (SAFEST)
-- ============================================================
local function example1()
    local target = Vector3.new(100, 0, 100)
    
    local success, msg = SafeMove.physicsMove(target, {
        speed = 16  -- Normal walk speed
    })
    
    print("Moved:", success, msg)
end

-- ============================================================
-- EXAMPLE 2: Smart approach + remote action (RECOMMENDED)
-- ============================================================
local function example2()
    local orePosition = Vector3.new(200, 0, 200)
    
    -- Move close to ore, then use remote to mine
    local success, msg = SafeMove.smartApproach(orePosition, function()
        -- This is called when you're in range
        -- Use your remote here
        ReplicatedStorage:FindFirstChild("MineOre"):FireServer(oreId)
        return true, "Mined!"
    end, {
        remoteRange = 10,  -- Stay 10 studs away
        speed = 16
    })
    
    print("Result:", success, msg)
end

-- ============================================================
-- EXAMPLE 3: Humanoid-based movement
-- ============================================================
local function example3()
    local shopPosition = Vector3.new(500, 0, 300)
    
    local success, msg = SafeMove.humanoidMove(shopPosition, {
        direct = false  -- Break into waypoints for long distances
    })
    
    print("Arrived at shop:", success, msg)
end

-- ============================================================
-- EXAMPLE 4: Integration with auto mine (UMT style)
-- ============================================================
local function safeAutoMineExample()
    local oreContainers = {
        workspace:FindFirstChild("PlacedOre"),
        workspace:FindFirstChild("SpawnedBlocks"),
    }
    
    for _, container in ipairs(oreContainers) do
        if container then
            for _, ore in pairs(container:GetChildren()) do
                local renderPart = ore:FindFirstChildWhichIsA("BasePart", true)
                if renderPart then
                    -- Approach safely, then mine
                    SafeMove.smartApproach(renderPart.Position, function()
                        -- Your mine logic here
                        -- Example: fire remote or proximity prompt
                        print("Mining ore at", renderPart.Position)
                    end, {
                        remoteRange = 8,
                        speed = 16
                    })
                    
                    -- Wait between ores (human-like delay)
                    task.wait(math.random(5, 15) / 10)
                end
            end
        end
    end
end

-- ============================================================
-- EXAMPLE 5: Emergency stop
-- ============================================================
local function emergencyStop()
    local player = game:GetService("Players").LocalPlayer
    SafeMove.stop(player.Character)
end

-- ============================================================
-- KEY DIFFERENCES FROM TWEEN (Why this is safer):
-- ============================================================
--[[
1. Uses Roblox Physics Engine (LinearVelocity)
   - Server sees natural physics, not position snaps
   - Has momentum, velocity, deceleration

2. Human randomization:
   - Speed varies slightly (-3 to +3 studs/sec)
   - Position has small offset (imperfection)
   - Pauses between segments
   - Decelerates when approaching target

3. No perfect straight lines:
   - Natural drift and correction
   - Slight zigzag from offset

4. Respects physics:
   - Can be blocked by walls (if not noclip)
   - Falls if no ground
   - Other players see smooth movement

5. Hybrid approach:
   - Physics move to safe range
   - Remote for actual action
   - Never teleports or snaps
--]]

return {
    SafeMove = SafeMove,
    examples = {
        simpleMove = example1,
        smartApproach = example2,
        humanoidMove = example3,
        autoMine = safeAutoMineExample,
        stop = emergencyStop,
    }
}
