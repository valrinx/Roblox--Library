--[[
    Blackhawk Rescue Mission 5 - ESP System
    Modular ESP with Player, Zombie, and AI detection
--]]

local ESP = {}
ESP.__index = ESP

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

-- Config
ESP.Config = {
    Enabled = true,
    PlayerESP = true,
    ZombieESP = true,
    AIESP = true,
    
    -- Visual Settings
    PlayerColor = Color3.fromRGB(0, 162, 255),
    ZombieColor = Color3.fromRGB(255, 50, 50),
    AIColor = Color3.fromRGB(255, 200, 50),
    
    TextSize = 14,
    MaxDistance = 2000,
    
    -- Features
    ShowName = true,
    ShowDistance = true,
    ShowHealth = true,
    ShowBox = true,
    ShowTracer = false,
}

-- Internal State
ESP.Connections = {}
ESP.Objects = {}
ESP.ScreenGui = nil

-- Utility: Create Drawing Object
local function CreateDrawing(Type, Properties)
    local Object = Drawing.new(Type)
    for Property, Value in pairs(Properties or {}) do
        Object[Property] = Value
    end
    return Object
end

-- Utility: Get Character Position
local function GetCharacterPosition(Character)
    if not Character then return nil end
    local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
    if HumanoidRootPart then
        return HumanoidRootPart.Position
    end
    local Head = Character:FindFirstChild("Head")
    if Head then
        return Head.Position
    end
    return nil
end

-- Utility: Get Humanoid
local function GetHumanoid(Character)
    if not Character then return nil end
    return Character:FindFirstChildOfClass("Humanoid")
end

-- Utility: World to Screen
local function WorldToScreen(Position)
    local Camera = Workspace.CurrentCamera
    local ScreenPos, OnScreen = Camera:WorldToViewportPoint(Position)
    return Vector2.new(ScreenPos.X, ScreenPos.Y), OnScreen, ScreenPos.Z
end

-- Create ESP Object
function ESP:CreateESPObject(Target, Type)
    local Object = {
        Target = Target,
        Type = Type,
        Drawings = {},
    }
    
    local Color = self.Config.PlayerColor
    if Type == "Zombie" then
        Color = self.Config.ZombieColor
    elseif Type == "AI" then
        Color = self.Config.AIColor
    end
    
    -- Name Text
    Object.Drawings.Name = CreateDrawing("Text", {
        Text = "",
        Size = self.Config.TextSize,
        Center = true,
        Outline = true,
        Color = Color,
        Visible = false,
    })
    
    -- Distance Text
    Object.Drawings.Distance = CreateDrawing("Text", {
        Text = "",
        Size = self.Config.TextSize - 2,
        Center = true,
        Outline = true,
        Color = Color3.fromRGB(200, 200, 200),
        Visible = false,
    })
    
    -- Health Text
    Object.Drawings.Health = CreateDrawing("Text", {
        Text = "",
        Size = self.Config.TextSize - 2,
        Center = true,
        Outline = true,
        Color = Color3.fromRGB(0, 255, 100),
        Visible = false,
    })
    
    -- Box
    Object.Drawings.Box = CreateDrawing("Square", {
        Thickness = 1,
        Filled = false,
        Color = Color,
        Visible = false,
    })
    
    -- Tracer
    Object.Drawings.Tracer = CreateDrawing("Line", {
        Thickness = 1,
        Color = Color,
        Visible = false,
    })
    
    table.insert(self.Objects, Object)
    return Object
end

-- Remove ESP Object
function ESP:RemoveESPObject(Object)
    for _, Drawing in pairs(Object.Drawings) do
        Drawing:Remove()
    end
    
    for i, Obj in ipairs(self.Objects) do
        if Obj == Object then
            table.remove(self.Objects, i)
            break
        end
    end
end

-- Update ESP Object
function ESP:UpdateESPObject(Object)
    local Target = Object.Target
    local Drawings = Object.Drawings
    
    -- Validate target
    if not Target or not Target.Parent then
        self:SetESPVisible(Object, false)
        return
    end
    
    -- Get position
    local Position = GetCharacterPosition(Target)
    if not Position then
        self:SetESPVisible(Object, false)
        return
    end
    
    -- Check distance
    local Camera = Workspace.CurrentCamera
    local Distance = (Camera.CFrame.Position - Position).Magnitude
    if Distance > self.Config.MaxDistance then
        self:SetESPVisible(Object, false)
        return
    end
    
    -- World to screen
    local ScreenPos, OnScreen, Depth = WorldToScreen(Position)
    if not OnScreen or Depth < 0 then
        self:SetESPVisible(Object, false)
        return
    end
    
    -- Get color based on type
    local Color = self.Config.PlayerColor
    if Object.Type == "Zombie" then
        Color = self.Config.ZombieColor
    elseif Object.Type == "AI" then
        Color = self.Config.AIColor
    end
    
    -- Get humanoid info
    local Humanoid = GetHumanoid(Target)
    local Health = Humanoid and Humanoid.Health or 0
    local MaxHealth = Humanoid and Humanoid.MaxHealth or 100
    local IsAlive = Health > 0
    
    if not IsAlive then
        self:SetESPVisible(Object, false)
        return
    end
    
    -- Update Name
    if self.Config.ShowName then
        local Name = Target.Name
        if Object.Type == "Player" then
            local Player = Players:GetPlayerFromCharacter(Target)
            if Player then
                Name = Player.DisplayName or Player.Name
            end
        end
        Drawings.Name.Text = Name
        Drawings.Name.Position = Vector2.new(ScreenPos.X, ScreenPos.Y - 40)
        Drawings.Name.Color = Color
        Drawings.Name.Visible = true
    else
        Drawings.Name.Visible = false
    end
    
    -- Update Distance
    if self.Config.ShowDistance then
        Drawings.Distance.Text = string.format("[%dm]", math.floor(Distance))
        Drawings.Distance.Position = Vector2.new(ScreenPos.X, ScreenPos.Y - 25)
        Drawings.Distance.Visible = true
    else
        Drawings.Distance.Visible = false
    end
    
    -- Update Health
    if self.Config.ShowHealth then
        Drawings.Health.Text = string.format("%d/%d HP", math.floor(Health), math.floor(MaxHealth))
        Drawings.Health.Position = Vector2.new(ScreenPos.X, ScreenPos.Y - 10)
        local HealthPercent = Health / MaxHealth
        Drawings.Health.Color = Color3.fromRGB(255 * (1 - HealthPercent), 255 * HealthPercent, 0)
        Drawings.Health.Visible = true
    else
        Drawings.Health.Visible = false
    end
    
    -- Update Box
    if self.Config.ShowBox then
        local BoxSize = Vector2.new(40, 60)
        Drawings.Box.Size = BoxSize
        Drawings.Box.Position = Vector2.new(ScreenPos.X - BoxSize.X / 2, ScreenPos.Y - BoxSize.Y / 2)
        Drawings.Box.Color = Color
        Drawings.Box.Visible = true
    else
        Drawings.Box.Visible = false
    end
    
    -- Update Tracer
    if self.Config.ShowTracer then
        local ScreenSize = Camera.ViewportSize
        Drawings.Tracer.From = Vector2.new(ScreenSize.X / 2, ScreenSize.Y)
        Drawings.Tracer.To = ScreenPos
        Drawings.Tracer.Color = Color
        Drawings.Tracer.Visible = true
    else
        Drawings.Tracer.Visible = false
    end
end

-- Set ESP Visibility
function ESP:SetESPVisible(Object, Visible)
    for _, Drawing in pairs(Object.Drawings) do
        Drawing.Visible = Visible
    end
end

-- Check if character is already tracked
function ESP:IsTracked(Character)
    for _, Object in ipairs(self.Objects) do
        if Object.Target == Character then
            return true
        end
    end
    return false
end

-- Get Entity Type for Blackhawk Rescue Mission 5
function ESP:GetEntityType(Character)
    -- Check if it's a player
    local Player = Players:GetPlayerFromCharacter(Character)
    if Player then
        return self.Config.PlayerESP and "Player" or nil
    end
    
    -- Check name patterns for zombies
    local Name = Character.Name:lower()
    if Name:find("zombie") or Name:find("infected") or Name:find("undead") then
        return self.Config.ZombieESP and "Zombie" or nil
    end
    
    -- Check for AI/NPC patterns
    if Name:find("ai") or Name:find("npc") or Name:find("bot") or Name:find("enemy") then
        return self.Config.AIESP and "AI" or nil
    end
    
    -- Default: Check if has Humanoid but no player
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if Humanoid and not Player then
        -- Could be AI or Zombie - check further attributes if available
        return self.Config.AIESP and "AI" or nil
    end
    
    return nil
end

-- Scan for entities
function ESP:ScanEntities()
    if not self.Config.Enabled then return end
    
    -- Scan Workspace
    for _, Model in ipairs(Workspace:GetDescendants()) do
        if Model:IsA("Model") and Model:FindFirstChild("Humanoid") then
            if not self:IsTracked(Model) then
                local EntityType = self:GetEntityType(Model)
                if EntityType then
                    self:CreateESPObject(Model, EntityType)
                end
            end
        end
    end
end

-- Clean up invalid objects
function ESP:CleanUp()
    for i = #self.Objects, 1, -1 do
        local Object = self.Objects[i]
        local Target = Object.Target
        
        if not Target or not Target.Parent then
            self:RemoveESPObject(Object)
        end
    end
end

-- Initialize ESP
function ESP:Initialize()
    -- Connect to RunService for updates
    local UpdateConnection = RunService.RenderStepped:Connect(function()
        if not self.Config.Enabled then
            for _, Object in ipairs(self.Objects) do
                self:SetESPVisible(Object, false)
            end
            return
        end
        
        -- Periodic scan (every 60 frames ~ 1 second)
        if tick() % 1 < 0.017 then
            self:ScanEntities()
            self:CleanUp()
        end
        
        -- Update all ESP objects
        for _, Object in ipairs(self.Objects) do
            self:UpdateESPObject(Object)
        end
    end)
    
    table.insert(self.Connections, UpdateConnection)
    
    -- Handle player added
    local PlayerAdded = Players.PlayerAdded:Connect(function(Player)
        local CharacterAdded = Player.CharacterAdded:Connect(function(Character)
            if self.Config.PlayerESP then
                if not self:IsTracked(Character) then
                    self:CreateESPObject(Character, "Player")
                end
            end
        end)
        table.insert(self.Connections, CharacterAdded)
    end)
    table.insert(self.Connections, PlayerAdded)
    
    -- Handle existing players
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player.Character then
            if self.Config.PlayerESP and not self:IsTracked(Player.Character) then
                self:CreateESPObject(Player.Character, "Player")
            end
        end
        
        local CharacterAdded = Player.CharacterAdded:Connect(function(Character)
            if self.Config.PlayerESP then
                if not self:IsTracked(Character) then
                    self:CreateESPObject(Character, "Player")
                end
            end
        end)
        table.insert(self.Connections, CharacterAdded)
    end
    
    print("[Blackhawk ESP] Initialized successfully")
end

-- Toggle ESP
function ESP:Toggle(State)
    self.Config.Enabled = State ~= nil and State or not self.Config.Enabled
    print("[Blackhawk ESP] Enabled:", self.Config.Enabled)
end

-- Toggle specific ESP types
function ESP:TogglePlayerESP(State)
    self.Config.PlayerESP = State ~= nil and State or not self.Config.PlayerESP
end

function ESP:ToggleZombieESP(State)
    self.Config.ZombieESP = State ~= nil and State or not self.Config.ZombieESP
end

function ESP:ToggleAIESP(State)
    self.Config.AIESP = State ~= nil and State or not self.Config.AIESP
end

-- Cleanup
function ESP:Cleanup()
    for _, Connection in ipairs(self.Connections) do
        Connection:Disconnect()
    end
    self.Connections = {}
    
    for i = #self.Objects, 1, -1 do
        self:RemoveESPObject(self.Objects[i])
    end
    
    print("[Blackhawk ESP] Cleaned up")
end

-- Return module
return ESP
