--[[
    Blackhawk Rescue Mission 5 - Entity Detector
    Specialized entity detection for BRM5 game mechanics
--]]

local EntityDetector = {}
EntityDetector.__index = EntityDetector

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- BRM5 Specific Detection Patterns
EntityDetector.Patterns = {
    -- Zombie/Infected patterns
    Zombies = {
        "zombie",
        "infected",
        "undead",
        "walker",
        "infection",
        "zmb",
        "z_",
        "_zombie",
        "infected_",
    },
    
    -- AI/Enemy patterns
    AI = {
        "ai",
        "npc",
        "bot",
        "enemy",
        "hostile",
        "terrorist",
        "insurgent",
        "bandit",
        "raider",
        "soldier",
        "military",
        " hostile_",
        "_ai",
        "_npc",
    },
    
    -- BRM5 specific entity folders/names
    BRM5Folders = {
        "Enemies",
        "Zombies",
        "AI",
        "NPCs",
        "Infected",
        "Hostiles",
        "MissionAI",
        "WaveEnemies",
        "Spawners",
    },
}

-- Check if name matches patterns
function EntityDetector:MatchesPatterns(Name, Patterns)
    Name = Name:lower()
    for _, Pattern in ipairs(Patterns) do
        if Name:find(Pattern:lower()) then
            return true
        end
    end
    return false
end

-- Determine entity type for BRM5
function EntityDetector:GetBRM5EntityType(Model)
    if not Model or not Model:IsA("Model") then return nil end
    
    local Name = Model.Name
    local Parent = Model.Parent
    local ParentName = Parent and Parent.Name or ""
    
    -- Check if it's a player first
    local Player = Players:GetPlayerFromCharacter(Model)
    if Player then
        return "Player", Player
    end
    
    -- Check parent folder names (BRM5 might organize enemies in specific folders)
    for _, FolderName in ipairs(self.Patterns.BRM5Folders) do
        if ParentName:lower():find(FolderName:lower()) then
            if FolderName:lower():find("zombie") or FolderName:lower():find("infected") then
                return "Zombie", nil
            else
                return "AI", nil
            end
        end
    end
    
    -- Check model name patterns
    if self:MatchesPatterns(Name, self.Patterns.Zombies) then
        return "Zombie", nil
    end
    
    if self:MatchesPatterns(Name, self.Patterns.AI) then
        return "AI", nil
    end
    
    -- Check for Humanoid and other indicators
    local Humanoid = Model:FindFirstChildOfClass("Humanoid")
    if not Humanoid then return nil end
    
    -- Check if it has a specific team or faction value
    local Team = Model:FindFirstChild("Team")
    local Faction = Model:FindFirstChild("Faction")
    local EnemyTag = Model:FindFirstChild("Enemy") or Model:FindFirstChild("Hostile")
    
    if EnemyTag then
        return "AI", nil
    end
    
    -- Check attributes
    if Model:GetAttribute("Type") == "Zombie" or Model:GetAttribute("EnemyType") == "Zombie" then
        return "Zombie", nil
    end
    
    if Model:GetAttribute("Type") == "AI" or Model:GetAttribute("EnemyType") == "AI" then
        return "AI", nil
    end
    
    if Model:GetAttribute("IsEnemy") or Model:GetAttribute("Hostile") then
        return "AI", nil
    end
    
    -- Default: if it has Humanoid but no player, classify as AI
    return "AI", nil
end

-- Scan specific BRM5 locations
function EntityDetector:ScanBRM5Locations()
    local Entities = {
        Players = {},
        Zombies = {},
        AI = {},
    }
    
    -- Common BRM5 enemy containers
    local CommonPaths = {
        Workspace:FindFirstChild("Enemies"),
        Workspace:FindFirstChild("Zombies"),
        Workspace:FindFirstChild("AI"),
        Workspace:FindFirstChild("NPCs"),
        Workspace:FindFirstChild("Hostiles"),
        Workspace:FindFirstChild("MissionEntities"),
        Workspace:FindFirstChild("Spawners"),
        ReplicatedStorage:FindFirstChild("Enemies"),
    }
    
    -- Scan specific containers
    for _, Container in ipairs(CommonPaths) do
        if Container then
            for _, Model in ipairs(Container:GetDescendants()) do
                if Model:IsA("Model") then
                    local EntityType, Player = self:GetBRM5EntityType(Model)
                    if EntityType then
                        if EntityType == "Player" then
                            table.insert(Entities.Players, {Model = Model, Player = Player})
                        elseif EntityType == "Zombie" then
                            table.insert(Entities.Zombies, Model)
                        elseif EntityType == "AI" then
                            table.insert(Entities.AI, Model)
                        end
                    end
                end
            end
        end
    end
    
    -- Scan entire workspace for any missed entities
    for _, Model in ipairs(Workspace:GetDescendants()) do
        if Model:IsA("Model") and Model:FindFirstChild("Humanoid") then
            -- Check if already tracked
            local AlreadyTracked = false
            for _, P in ipairs(Entities.Players) do
                if P.Model == Model then AlreadyTracked = true break end
            end
            for _, Z in ipairs(Entities.Zombies) do
                if Z == Model then AlreadyTracked = true break end
            end
            for _, A in ipairs(Entities.AI) do
                if A == Model then AlreadyTracked = true break end
            end
            
            if not AlreadyTracked then
                local EntityType, Player = self:GetBRM5EntityType(Model)
                if EntityType then
                    if EntityType == "Player" then
                        table.insert(Entities.Players, {Model = Model, Player = Player})
                    elseif EntityType == "Zombie" then
                        table.insert(Entities.Zombies, Model)
                    elseif EntityType == "AI" then
                        table.insert(Entities.AI, Model)
                    end
                end
            end
        end
    end
    
    return Entities
end

-- Get nearby entities
function EntityDetector:GetNearbyEntities(Range)
    Range = Range or 1000
    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer or not LocalPlayer.Character then return {} end
    
    local LocalPosition = LocalPlayer.Character:GetPivot().Position
    local AllEntities = self:ScanBRM5Locations()
    local Nearby = {}
    
    local function CheckDistance(Model)
        local Position = nil
        if Model:FindFirstChild("HumanoidRootPart") then
            Position = Model.HumanoidRootPart.Position
        elseif Model:FindFirstChild("Head") then
            Position = Model.Head.Position
        elseif Model:FindFirstChild("Torso") then
            Position = Model.Torso.Position
        end
        
        if Position then
            local Distance = (Position - LocalPosition).Magnitude
            if Distance <= Range then
                return Distance
            end
        end
        return nil
    end
    
    -- Check players
    for _, P in ipairs(AllEntities.Players) do
        local Distance = CheckDistance(P.Model)
        if Distance then
            table.insert(Nearby, {
                Type = "Player",
                Model = P.Model,
                Player = P.Player,
                Distance = Distance,
            })
        end
    end
    
    -- Check zombies
    for _, Z in ipairs(AllEntities.Zombies) do
        local Distance = CheckDistance(Z)
        if Distance then
            table.insert(Nearby, {
                Type = "Zombie",
                Model = Z,
                Distance = Distance,
            })
        end
    end
    
    -- Check AI
    for _, A in ipairs(AllEntities.AI) do
        local Distance = CheckDistance(A)
        if Distance then
            table.insert(Nearby, {
                Type = "AI",
                Model = A,
                Distance = Distance,
            })
        end
    end
    
    -- Sort by distance
    table.sort(Nearby, function(a, b) return a.Distance < b.Distance end)
    
    return Nearby
end

-- Monitor for new entities
function EntityDetector:StartMonitoring(Callback)
    local MonitoredEntities = {}
    
    local function CheckNewEntities()
        local Current = self:ScanBRM5Locations()
        
        local function ProcessEntity(Model, Type)
            if not MonitoredEntities[Model] then
                MonitoredEntities[Model] = true
                if Callback then
                    Callback(Model, Type, "Added")
                end
                
                -- Monitor removal
                Model.AncestryChanged:Connect(function(_, Parent)
                    if not Parent then
                        MonitoredEntities[Model] = nil
                        if Callback then
                            Callback(Model, Type, "Removed")
                        end
                    end
                end)
            end
        end
        
        -- Process all entities
        for _, P in ipairs(Current.Players) do
            ProcessEntity(P.Model, "Player")
        end
        for _, Z in ipairs(Current.Zombies) do
            ProcessEntity(Z, "Zombie")
        end
        for _, A in ipairs(Current.AI) do
            ProcessEntity(A, "AI")
        end
    end
    
    -- Initial scan
    CheckNewEntities()
    
    return CheckNewEntities
end

return EntityDetector
