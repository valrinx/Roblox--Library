-- ============================================================
--   PROBE: Find Players & Characters
--   Run in Command Bar or Script
-- ============================================================

local Players = game:GetService("Players")
local workspace = game:GetService("Workspace")

print("=== Players Service ===")
for _, player in Players:GetPlayers() do
    print("  Player:", player.Name, "| UserId:", player.UserId)
end

print("\n=== LocalPlayer Character ===")
local lp = Players.LocalPlayer
if lp.Character then
    print("  FullPath:", lp.Character:GetFullName())
    print("  PrimaryPart:", lp.Character.PrimaryPart and lp.Character.PrimaryPart.Name or "nil")
else
    print("  No character loaded")
end

print("\n=== All Characters (via Players) ===")
for _, player in Players:GetPlayers() do
    if player.Character then
        print("  " .. player.Name .. " → " .. player.Character:GetFullName())
    else
        print("  " .. player.Name .. " → (no character)")
    end
end

print("\n=== Root Models in Workspace ===")
for _, child in workspace:GetChildren() do
    if child:IsA("Model") then
        print("  Root Model:", child.Name, "| Class:", child.ClassName)
    end
end

print("\n=== Player Characters by Owner ===")
for _, obj in workspace:GetDescendants() do
    if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
        local owner = Players:GetPlayerFromCharacter(obj)
        if owner then
            print("  [PLAYER]", owner.Name, "→", obj:GetFullName())
        end
    end
end

print("\n=== NPCs / Non-Player Models ===")
for _, obj in workspace:GetDescendants() do
    if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
        local owner = Players:GetPlayerFromCharacter(obj)
        if not owner then
            print("  [NPC]", obj:GetFullName())
        end
    end
end

print("\n=== Done ===")
