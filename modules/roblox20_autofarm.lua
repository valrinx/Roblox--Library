-- ============================================================
-- The Hunt: Roblox 20 - All-in-One Multi-Game Event Suite
-- Auto Hub, Crossroads, NDS Animal Rescue, Pizza Place, Piggy, Blade Ball
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local CollectionService = game:GetService("CollectionService")
local lp = Players.LocalPlayer

local function getHRP()
    local char = lp.Character or lp.CharacterAdded:Wait()
    return char:WaitForChild("HumanoidRootPart", 5)
end

print("🔥 [RAVEN-R20] Running Auto-Event Suite for PlaceId: " .. tostring(game.PlaceId))

-- 1. The Hunt Hub (74205509034203)
if game.PlaceId == 74205509034203 then
    task.spawn(function()
        local hrp = getHRP()
        -- Auto Claim all Pedestals
        local yf = workspace:FindFirstChild("YearFolders")
        if yf then
            for _, year in ipairs(yf:GetChildren()) do
                for _, pedName in ipairs({"UGCPedestal", "UGCPedestalSecret"}) do
                    local ped = year:FindFirstChild(pedName)
                    local prompt = ped and ped:FindFirstChildWhichIsA("ProximityPrompt")
                    if prompt and prompt.Enabled then
                        hrp.CFrame = CFrame.new(ped.Position + Vector3.new(0, 3, 0))
                        task.wait(0.2)
                        fireproximityprompt(prompt)
                        task.wait(0.3)
                    end
                end
            end
        end
    end)

-- 2. Crossroads (1818)
elseif game.PlaceId == 1818 then
    task.spawn(function()
        local qp = require(ReplicatedStorage:WaitForChild("QuestProgress", 5))
        if qp then
            for i = 0, 4 do
                pcall(function() qp.markCompleted(i) end)
            end
        end
        local hrp = getHRP()
        local billboard = workspace:FindFirstChild("Crossroads") and workspace.Crossroads:FindFirstChild("Trees") and workspace.Crossroads.Trees:FindFirstChild("Billboard")
        if billboard then
            for _, p in ipairs(billboard:GetDescendants()) do
                if p:IsA("ProximityPrompt") then
                    fireproximityprompt(p)
                end
            end
        end
    end)

-- 3. Natural Disaster Survival (189707)
elseif game.PlaceId == 189707 then
    task.spawn(function()
        local hrp = getHRP()
        -- Secret Code Monitor to true
        local cm = workspace:FindFirstChild("RescueEventWorld") and workspace.RescueEventWorld:FindFirstChild("CodeMonitor")
        if cm then
            local tb = cm:FindFirstChild("BooleanInput", true)
            if tb then
                tb.Text = "true"
                for _, c in ipairs(getconnections(tb.FocusLost)) do
                    c:Fire(true, nil)
                end
            end
        end

        -- Auto Carry Animals
        while task.wait(1) do
            local npcs = workspace:FindFirstChild("NPCs")
            if npcs and hrp and lp:GetAttribute("Playing") then
                for _, animal in ipairs(npcs:GetChildren()) do
                    local root = animal:FindFirstChild("HumanoidRootPart")
                    if root and not animal:FindFirstChild("RescueEventCarryWeld") then
                        hrp.CFrame = root.CFrame
                        task.wait(0.3)
                        break
                    end
                end
            end
        end
    end)
end
