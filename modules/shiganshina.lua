--// Shiganshina v1 — Auto Farm Script
--// Game: Training Grounds (AoT)
--// PlaceId: 13379349730

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

--// Local Player
local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local Root = Char:WaitForChild("HumanoidRootPart")
local Humanoid = Char:WaitForChild("Humanoid")

--// Rayfield
local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
local Window = Rayfield:CreateWindow({
    Name = "Shiganshina v1",
    LoadingTitle = "Shiganshina v1",
    LoadingSubtitle = "by Codebuff",
    ConfigurationSaving = { Enabled = true, FolderName = "Shiganshina", FileName = "Config" },
    KeySystem = false
})

--// Find Remotes
local POST, GET
for _, v in ReplicatedStorage:GetDescendants() do
    if v.Name == "POST" and v:IsA("RemoteEvent") then POST = v end
    if v.Name == "GET" and v:IsA("RemoteFunction") then GET = v end
end

--// Find Titians Folder
local TitansFolder = Workspace:WaitForChild("Titans")

--// States
local Config = {
    AutoFarm = false,
    AutoGrabEscape = false,
    AutoReloadBlades = false,
    AutoFullReload = false,
    InfiniteSpear = false,
    AutoUseSkill = false,
    MultiHit = false,
    MultiHitRadius = 50,
    BossBurst = false,
    NapeExtender = false,
    TitanESP = false,
    FarmDelay = 0.15,
    ReloadThreshold = 0.5,
}

local ESPObjects = {}
local ActiveThreads = {}

--// ==================== UTILITY FUNCTIONS ====================

local function getCharacter()
    Char = LP.Character
    if not Char then return nil, nil, nil end
    Root = Char:FindFirstChild("HumanoidRootPart")
    Humanoid = Char:FindFirstChildOfClass("Humanoid")
    return Char, Root, Humanoid
end

local function getNape(titan)
    -- Check Hitboxes/Hit/Nape first, then direct Nape
    local hitboxes = titan:FindFirstChild("Hitboxes")
    if hitboxes then
        local hit = hitboxes:FindFirstChild("Hit")
        if hit then
            local nape = hit:FindFirstChild("Nape")
            if nape and nape:IsA("BasePart") then return nape end
        end
    end
    -- Fallback: direct Nape
    local nape = titan:FindFirstChild("Nape", true)
    if nape and nape:IsA("BasePart") then return nape end
    return nil
end

local function getTitanHealth(titan)
    local hum = titan:FindFirstChildOfClass("Humanoid")
    if hum then
        return hum.Health, hum.MaxHealth
    end
    return 0, 0
end

local function isBoss(titan)
    local nape = getNape(titan)
    if nape and nape.Size.X > 25 then return true end
    local hum = titan:FindFirstChildOfClass("Humanoid")
    if hum and hum.MaxHealth > 100 then return true end
    return false
end

local function getAliveTitans()
    local alive = {}
    for _, titan in TitansFolder:GetChildren() do
        if titan:IsA("Model") then
            local hp, maxHp = getTitanHealth(titan)
            local nape = getNape(titan)
            if hp > 0 and nape then
                table.insert(alive, { titan = titan, nape = nape, hp = hp, maxHp = maxHp, isBoss = isBoss(titan) })
            end
        end
    end
    return alive
end

local function getNearestTitan()
    local _, root = getCharacter()
    if not root then return nil end
    
    local nearest = nil
    local minDist = math.huge
    
    for _, info in getAliveTitans() do
        local dist = (root.Position - info.nape.Position).Magnitude
        if dist < minDist then
            minDist = dist
            nearest = info
        end
    end
    
    return nearest, minDist
end

local function needReload()
    local char = getCharacter()
    if not char then return false end
    
    local rig = Workspace:FindFirstChild("Rig_" .. char.Name, true)
    if not rig then rig = char end
    
    local found = false
    for _, blade in rig:GetDescendants() do
        if blade.Name:sub(1, 6) == "Blade_" then
            found = true
            if blade:GetAttribute("Broken") == true then
                return true
            end
        end
    end
    
    return found == false
end

local function getRefillStation()
    local _, root = getCharacter()
    if not root then return nil end
    
    local station = nil
    local minDist = math.huge
    
    for _, part in Workspace:GetDescendants() do
        if part.Name == "Refill" and part:IsA("BasePart") then
            local dist = (root.Position - part.Position).Magnitude
            if dist < minDist then
                minDist = dist
                station = part
            end
        end
    end
    
    return station
end

--// ==================== COMBAT FUNCTIONS ====================

local function doSlash(nape)
    if POST then
        POST:FireServer("Attacks", "Slash", true)
        task.wait(0.05)
        POST:FireServer("Hitboxes", "Register", nape, Config.MultiHit and Config.MultiHitRadius or 50, 0)
    end
end

local function doReload(station)
    if not POST or not GET then return end
    
    local _, root = getCharacter()
    if not root then return end
    
    local old = root.CFrame
    
    if station then
        root.CFrame = station.CFrame * CFrame.new(0, 5, 0)
        task.wait(0.2)
        POST:FireServer("Attacks", "Reload", station)
        task.wait(2)
    end
    
    GET:InvokeServer("Blades", "Reload")
    task.wait(0.1)
    
    local _, root2 = getCharacter()
    if root2 then
        root2.CFrame = old
    end
end

local function doFullReload()
    if GET then
        GET:InvokeServer("Blades", "Reload")
        task.wait(0.1)
    end
end

--// ==================== AUTO FARM ====================

local function autoFarmLoop()
    while Config.AutoFarm do
        local char, root, humanoid = getCharacter()
        if not char or not root or not humanoid or humanoid.Health <= 0 then
            task.wait(1)
            continue
        end
        
        -- Check reload
        if Config.AutoReloadBlades and needReload() then
            if Config.AutoFullReload then
                doFullReload()
            else
                local station = getRefillStation()
                doReload(station)
            end
            task.wait(0.2)
        end
        
        -- Get nearest titan
        local info, dist = getNearestTitan()
        if not info then
            task.wait(0.5)
            continue
        end
        
        -- Boss Burst: if boss, use special attack
        if info.isBoss and Config.BossBurst then
            -- Register multiple hits on boss nape
            for i = 1, 5 do
                doSlash(info.nape)
                task.wait(0.05)
            end
        end
        
        -- Tween to nape
        local tween = TweenService:Create(
            root,
            TweenInfo.new(0.25, Enum.EasingStyle.Quad),
            {CFrame = info.nape.CFrame * CFrame.new(0, 0, 5)}
        )
        tween:Play()
        tween.Completed:Wait()
        
        -- Slash
        doSlash(info.nape)
        
        -- Nape Extender: if enabled, register additional hits with larger radius
        if Config.NapeExtender then
            task.wait(0.05)
            if POST then
                POST:FireServer("Hitboxes", "Register", info.nape, 100, 0)
            end
        end
        
        task.wait(Config.FarmDelay)
    end
end

--// ==================== AUTO RELOAD ====================

local function autoReloadLoop()
    while Config.AutoReloadBlades do
        if needReload() then
            if Config.AutoFullReload then
                doFullReload()
            else
                local station = getRefillStation()
                doReload(station)
            end
        end
        task.wait(1)
    end
end

--// ==================== INFINITE SPEAR ====================

local function infiniteSpearLoop()
    while Config.InfiniteSpear do
        -- Reset spear count by firing reload
        if GET then
            pcall(function()
                GET:InvokeServer("Spears", "Reload")
            end)
        end
        task.wait(5)
    end
end

--// ==================== AUTO SKILL ====================

local function autoSkillLoop()
    while Config.AutoUseSkill do
        local info = getNearestTitan()
        if info then
            -- Try to use skill via POST
            if POST then
                pcall(function()
                    POST:FireServer("Skills", "Use", info.nape)
                end)
            end
        end
        task.wait(2)
    end
end

--// ==================== TITAN ESP ====================

local function createESP(titan, nape)
    if ESPObjects[titan] then return end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "TitanESP"
    billboard.Size = UDim2.new(0, 200, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 5, 0)
    billboard.AlwaysOnTop = true
    billboard.Adornee = nape
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = isBoss(titan) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 165, 0)
    frame.BackgroundTransparency = 0.5
    frame.Parent = billboard
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0.5, 0)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = isBoss(titan) and "BOSS" or "TITAN"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextScaled = true
    label.Parent = frame
    
    local hpLabel = Instance.new("TextLabel")
    hpLabel.Size = UDim2.new(1, 0, 0.5, 0)
    hpLabel.Position = UDim2.new(0, 0, 0.5, 0)
    hpLabel.BackgroundTransparency = 1
    local hp, maxHp = getTitanHealth(titan)
    hpLabel.Text = math.floor(hp) .. "/" .. math.floor(maxHp)
    hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpLabel.TextScaled = true
    hpLabel.Parent = frame
    
    billboard.Parent = nape
    ESPObjects[titan] = billboard
end

local function removeESP(titan)
    if ESPObjects[titan] then
        ESPObjects[titan]:Destroy()
        ESPObjects[titan] = nil
    end
end

local function updateESP()
    -- Remove ESP from dead titans
    for titan, esp in pairs(ESPObjects) do
        if not titan or not titan.Parent then
            removeESP(titan)
        else
            local hp, maxHp = getTitanHealth(titan)
            if hp <= 0 then
                removeESP(titan)
            else
                -- Update HP label
                local frame = esp:FindFirstChild("Frame")
                if frame then
                    local hpLabel = frame:FindFirstChildOfClass("TextLabel", 2)
                    if hpLabel then
                        hpLabel.Text = math.floor(hp) .. "/" .. math.floor(maxHp)
                    end
                end
            end
        end
    end
    
    -- Add ESP to alive titans
    if Config.TitanESP then
        for _, titan in TitansFolder:GetChildren() do
            if titan:IsA("Model") then
                local hp, maxHp = getTitanHealth(titan)
                local nape = getNape(titan)
                if hp > 0 and nape and not ESPObjects[titan] then
                    createESP(titan, nape)
                end
            end
        end
    end
end

local function espLoop()
    while Config.TitanESP do
        updateESP()
        task.wait(1)
    end
end

--// ==================== MULTI HIT ====================

local function multiHitLoop()
    while Config.MultiHit do
        local info = getNearestTitan()
        if info then
            -- Register hit on all titans in radius
            for _, other in getAliveTitans() do
                if other.nape then
                    local dist = (info.nape.Position - other.nape.Position).Magnitude
                    if dist <= Config.MultiHitRadius then
                        doSlash(other.nape)
                    end
                end
            end
        end
        task.wait(0.5)
    end
end

--// ==================== START/STOP FUNCTIONS ====================

local function startThread(name, func)
    if ActiveThreads[name] then return end
    ActiveThreads[name] = task.spawn(func)
end

local function stopThread(name)
    if ActiveThreads[name] then
        task.cancel(ActiveThreads[name])
        ActiveThreads[name] = nil
    end
end

--// ==================== UI TABS ====================

--// Farm Tab
local FarmTab = Window:CreateTab("Farm", 4483362458)

local FarmSection = FarmTab:CreateSection("Farm Status")

local StatusLabel = FarmTab:CreateLabel("Status: Idle")

local AutoFarmToggle = FarmTab:CreateToggle({
    Name = "Toggle Auto Farm",
    CurrentValue = false,
    Flag = "AutoFarm",
    Callback = function(Value)
        Config.AutoFarm = Value
        if Value then
            StatusLabel:Set("Status: Farming...")
            startThread("AutoFarm", autoFarmLoop)
        else
            StatusLabel:Set("Status: Idle")
            stopThread("AutoFarm")
        end
    end,
})

local FarmSettingsSection = FarmTab:CreateSection("Farm Settings")

local AutoGrabEscapeToggle = FarmTab:CreateToggle({
    Name = "Auto Grab Escape",
    CurrentValue = false,
    Flag = "AutoGrabEscape",
    Callback = function(Value)
        Config.AutoGrabEscape = Value
    end,
})

local AutoReloadBladesToggle = FarmTab:CreateToggle({
    Name = "Auto Reload Blades",
    CurrentValue = false,
    Flag = "AutoReloadBlades",
    Callback = function(Value)
        Config.AutoReloadBlades = Value
        if Value then
            startThread("AutoReload", autoReloadLoop)
        else
            stopThread("AutoReload")
        end
    end,
})

local AutoFullReloadToggle = FarmTab:CreateToggle({
    Name = "Auto Full Reload",
    CurrentValue = false,
    Flag = "AutoFullReload",
    Callback = function(Value)
        Config.AutoFullReload = Value
    end,
})

local InfiniteSpearToggle = FarmTab:CreateToggle({
    Name = "Infinite Spear",
    CurrentValue = false,
    Flag = "InfiniteSpear",
    Callback = function(Value)
        Config.InfiniteSpear = Value
        if Value then
            startThread("InfiniteSpear", infiniteSpearLoop)
        else
            stopThread("InfiniteSpear")
        end
    end,
})

local AutoUseSkillToggle = FarmTab:CreateToggle({
    Name = "Auto Use Skill",
    CurrentValue = false,
    Flag = "AutoUseSkill",
    Callback = function(Value)
        Config.AutoUseSkill = Value
        if Value then
            startThread("AutoSkill", autoSkillLoop)
        else
            stopThread("AutoSkill")
        end
    end,
})

--// Combat Tab
local CombatTab = Window:CreateTab("Combat", 4483362458)

local CombatSection = CombatTab:CreateSection("Combat Settings")

local MultiHitToggle = CombatTab:CreateToggle({
    Name = "Multi Hit",
    CurrentValue = false,
    Flag = "MultiHit",
    Callback = function(Value)
        Config.MultiHit = Value
        if Value then
            startThread("MultiHit", multiHitLoop)
        else
            stopThread("MultiHit")
        end
    end,
})

local MultiHitRadiusSlider = CombatTab:CreateSlider({
    Name = "Multi Hit Radius",
    Range = {10, 200},
    Increment = 5,
    Suffix = " studs",
    CurrentValue = 50,
    Flag = "MultiHitRadius",
    Callback = function(Value)
        Config.MultiHitRadius = Value
    end,
})

local BossBurstToggle = CombatTab:CreateToggle({
    Name = "Boss Burst",
    CurrentValue = false,
    Flag = "BossBurst",
    Callback = function(Value)
        Config.BossBurst = Value
    end,
})

local NapeExtenderToggle = CombatTab:CreateToggle({
    Name = "Nape Extender",
    CurrentValue = false,
    Flag = "NapeExtender",
    Callback = function(Value)
        Config.NapeExtender = Value
    end,
})

--// ESP Tab
local ESPTab = Window:CreateTab("ESP", 4483362458)

local ESPSection = ESPTab:CreateSection("Titan ESP")

local TitanESPToggle = ESPTab:CreateToggle({
    Name = "Titan ESP",
    CurrentValue = false,
    Flag = "TitanESP",
    Callback = function(Value)
        Config.TitanESP = Value
        if Value then
            startThread("ESP", espLoop)
        else
            stopThread("ESP")
            -- Remove all ESP
            for titan, esp in pairs(ESPObjects) do
                removeESP(titan)
            end
        end
    end,
})

--// Misc Tab
local MiscTab = Window:CreateTab("Misc", 4483362458)

local MiscSection = MiscTab:CreateSection("Character")

local SpeedSlider = MiscTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 100},
    Increment = 1,
    Suffix = "",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(Value)
        local _, _, hum = getCharacter()
        if hum then hum.WalkSpeed = Value end
    end,
})

local NoClipToggle = MiscTab:CreateToggle({
    Name = "NoClip",
    CurrentValue = false,
    Flag = "NoClip",
    Callback = function(Value)
        Config.NoClip = Value
    end,
})

local InfiniteJumpToggle = MiscTab:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Flag = "InfiniteJump",
    Callback = function(Value)
        Config.InfiniteJump = Value
    end,
})

--// NoClip Handler
RunService.Stepped:Connect(function()
    if Config.NoClip then
        local char = getCharacter()
        if char then
            for _, part in char:GetDescendants() do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end
end)

--// Infinite Jump Handler
game:GetService("UserInputService").JumpRequest:Connect(function()
    if Config.InfiniteJump then
        local _, _, hum = getCharacter()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

--// Character Respawn Handler
LP.CharacterAdded:Connect(function(newChar)
    Char = newChar
    Root = newChar:WaitForChild("HumanoidRootPart")
    Humanoid = newChar:WaitForChild("Humanoid")
end)

--// ==================== NOTIFICATION ====================
Rayfield:CreateNotification({
    Name = "Shiganshina v1",
    Content = "Script loaded! Use the tabs to configure.",
    Duration = 5
})
