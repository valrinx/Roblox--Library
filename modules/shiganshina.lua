--// Shiganshina v1 — Auto Farm Script
--// Game: Training Grounds (AoT)
--// PlaceId: 13379349730
--// Uses MacLib from RAVEN HUB

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

return function(Window, runtimeInfo)
    local LP = Players.LocalPlayer
    local Char = LP.Character or LP.CharacterAdded:Wait()
    local Root = Char:WaitForChild("HumanoidRootPart")
    local Humanoid = Char:FindFirstChildOfClass("Humanoid")

    --// Find Remotes
    local POST, GET
    for _, v in ReplicatedStorage:GetDescendants() do
        if v.Name == "POST" and v:IsA("RemoteEvent") then POST = v end
        if v.Name == "GET" and v:IsA("RemoteFunction") then GET = v end
    end

    local TitansFolder = Workspace:WaitForChild("Titans")

    --// Config
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
    }

    local ESPObjects = {}
    local ActiveThreads = {}

    --// ==================== UTILITY ====================

    local function getCharacter()
        Char = LP.Character
        if not Char then return nil, nil, nil end
        Root = Char:FindFirstChild("HumanoidRootPart")
        Humanoid = Char:FindFirstChildOfClass("Humanoid")
        return Char, Root, Humanoid
    end

    local function getNape(titan)
        local hitboxes = titan:FindFirstChild("Hitboxes")
        if hitboxes then
            local hit = hitboxes:FindFirstChild("Hit")
            if hit then
                local nape = hit:FindFirstChild("Nape")
                if nape and nape:IsA("BasePart") then return nape end
            end
        end
        local nape = titan:FindFirstChild("Nape", true)
        if nape and nape:IsA("BasePart") then return nape end
        return nil
    end

    local function getTitanHealth(titan)
        local hum = titan:FindFirstChildOfClass("Humanoid")
        if hum then return hum.Health, hum.MaxHealth end
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
        local nearest, minDist = nil, math.huge
        for _, info in getAliveTitans() do
            local dist = (root.Position - info.nape.Position).Magnitude
            if dist < minDist then minDist = dist; nearest = info end
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
                if blade:GetAttribute("Broken") == true then return true end
            end
        end
        return not found
    end

    local function getRefillStation()
        local _, root = getCharacter()
        if not root then return nil end
        local station, minDist = nil, math.huge
        for _, part in Workspace:GetDescendants() do
            if part.Name == "Refill" and part:IsA("BasePart") then
                local dist = (root.Position - part.Position).Magnitude
                if dist < minDist then minDist = dist; station = part end
            end
        end
        return station
    end

    --// ==================== COMBAT ====================

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
        if root2 then root2.CFrame = old end
    end

    local function doFullReload()
        if GET then
            GET:InvokeServer("Blades", "Reload")
            task.wait(0.1)
        end
    end

    --// ==================== GRAB ESCAPE ====================

    local function isGrabbed()
        local _, _, hum = getCharacter()
        if not hum then return false end
        if hum.PlatformStand then return true end
        if hum:GetState() == Enum.HumanoidStateType.PlatformStanding then return true end
        return false
    end

    local function doEscape()
        local char, root, hum = getCharacter()
        if not char or not hum then return end

        -- Remove all movement constraints (BodyVelocity, BodyPosition, BodyGyro, AlignPosition)
        for _, v in char:GetDescendants() do
            if v:IsA("BodyVelocity") or v:IsA("BodyPosition") or v:IsA("BodyGyro")
                or v:IsA("AlignPosition") or v:IsA("AlignOrientation") then
                pcall(function() v:Destroy() end)
            end
        end

        -- Reset humanoid state
        hum.PlatformStand = false
        hum:ChangeState(Enum.HumanoidStateType.Running)
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)

        -- Try remote escape
        if POST then
            pcall(function() POST:FireServer("Escape") end)
            pcall(function() POST:FireServer("Grab", "Escape") end)
            pcall(function() POST:FireServer("Grab", false) end)
        end

        -- Teleport up to break free
        if root then
            root.CFrame = root.CFrame + Vector3.new(0, 10, 0)
        end
    end

    local function autoGrabEscapeLoop()
        while Config.AutoGrabEscape do
            if isGrabbed() then
                doEscape()
                task.wait(0.1)
                -- Keep trying until not grabbed anymore
                for _ = 1, 10 do
                    if not isGrabbed() then break end
                    doEscape()
                    task.wait(0.05)
                end
            end
            task.wait(0.1)
        end
    end

    --// ==================== LOOPS ====================

    local function autoFarmLoop()
        while Config.AutoFarm do
            local char, root, humanoid = getCharacter()
            if not char or not root or not humanoid or humanoid.Health <= 0 then
                task.wait(1); continue
            end
            -- Check grab during farm
            if Config.AutoGrabEscape and isGrabbed() then
                doEscape()
                task.wait(0.2)
                continue
            end
            if Config.AutoReloadBlades and needReload() then
                if Config.AutoFullReload then doFullReload()
                else doReload(getRefillStation()) end
                task.wait(0.2)
            end
            local info = getNearestTitan()
            if not info then task.wait(0.5); continue end
            if info.isBoss and Config.BossBurst then
                for _ = 1, 5 do doSlash(info.nape); task.wait(0.05) end
            end
            local tween = TweenService:Create(root,
                TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                {CFrame = info.nape.CFrame * CFrame.new(0, 0, 5)})
            tween:Play()
            tween.Completed:Wait()
            doSlash(info.nape)
            if Config.NapeExtender then
                task.wait(0.05)
                if POST then POST:FireServer("Hitboxes", "Register", info.nape, 100, 0) end
            end
            task.wait(Config.FarmDelay)
        end
    end

    local function autoReloadLoop()
        while Config.AutoReloadBlades do
            if needReload() then
                if Config.AutoFullReload then doFullReload()
                else doReload(getRefillStation()) end
            end
            task.wait(1)
        end
    end

    local function infiniteSpearLoop()
        while Config.InfiniteSpear do
            if GET then pcall(function() GET:InvokeServer("Spears", "Reload") end) end
            task.wait(5)
        end
    end

    local function autoSkillLoop()
        while Config.AutoUseSkill do
            local info = getNearestTitan()
            if info and POST then
                pcall(function() POST:FireServer("Skills", "Use", info.nape) end)
            end
            task.wait(2)
        end
    end

    local function multiHitLoop()
        while Config.MultiHit do
            local info = getNearestTitan()
            if info then
                for _, other in getAliveTitans() do
                    if other.nape then
                        local dist = (info.nape.Position - other.nape.Position).Magnitude
                        if dist <= Config.MultiHitRadius then doSlash(other.nape) end
                    end
                end
            end
            task.wait(0.5)
        end
    end

    --// ==================== ESP ====================

    local function createESP(titan, nape)
        if ESPObjects[titan] then return end
        local bb = Instance.new("BillboardGui")
        bb.Name = "TitanESP"
        bb.Size = UDim2.new(0, 200, 0, 50)
        bb.StudsOffset = Vector3.new(0, 5, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = nape
        local f = Instance.new("Frame", bb)
        f.Size = UDim2.new(1, 0, 1, 0)
        f.BackgroundColor3 = isBoss(titan) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 165, 0)
        f.BackgroundTransparency = 0.5
        local lbl = Instance.new("TextLabel", f)
        lbl.Size = UDim2.new(1, 0, 0.5, 0); lbl.BackgroundTransparency = 1
        lbl.Text = isBoss(titan) and "BOSS" or "TITAN"
        lbl.TextColor3 = Color3.new(1, 1, 1); lbl.TextScaled = true
        local hpLbl = Instance.new("TextLabel", f)
        hpLbl.Size = UDim2.new(1, 0, 0.5, 0); hpLbl.Position = UDim2.new(0, 0, 0.5, 0)
        hpLbl.BackgroundTransparency = 1
        local hp, maxHp = getTitanHealth(titan)
        hpLbl.Text = math.floor(hp) .. "/" .. math.floor(maxHp)
        hpLbl.TextColor3 = Color3.new(1, 1, 1); hpLbl.TextScaled = true
        bb.Parent = nape
        ESPObjects[titan] = bb
    end

    local function removeESP(titan)
        if ESPObjects[titan] then ESPObjects[titan]:Destroy(); ESPObjects[titan] = nil end
    end

    local function espLoop()
        while Config.TitanESP do
            for titan, esp in pairs(ESPObjects) do
                if not titan or not titan.Parent then removeESP(titan)
                else
                    local hp = getTitanHealth(titan)
                    if hp <= 0 then removeESP(titan) end
                end
            end
            for _, titan in TitansFolder:GetChildren() do
                if titan:IsA("Model") then
                    local hp, maxHp = getTitanHealth(titan)
                    local nape = getNape(titan)
                    if hp > 0 and nape and not ESPObjects[titan] then createESP(titan, nape) end
                end
            end
            task.wait(1)
        end
    end

    --// ==================== THREAD HELPERS ====================

    local function startThread(name, func)
        if ActiveThreads[name] then return end
        ActiveThreads[name] = task.spawn(func)
    end

    local function stopThread(name)
        if ActiveThreads[name] then task.cancel(ActiveThreads[name]); ActiveThreads[name] = nil end
    end

    --// ==================== UI (MacLib) ====================

    local FarmTab = Window:CreateTab("Farm")
    local CombatTab = Window:CreateTab("Combat")
    local ESPTab = Window:CreateTab("ESP")
    local MiscTab = Window:CreateTab("Misc")

    --// Farm Tab
    FarmTab:CreateSection("Farm Status")
    local StatusLabel = FarmTab:CreateLabel("Status: Idle")

    FarmTab:CreateSection("Auto Farm")
    FarmTab:CreateToggle({
        Name = "Toggle Auto Farm",
        CurrentValue = false,
        Callback = function(v)
            Config.AutoFarm = v
            if v then StatusLabel:Set("Status: Farming..."); startThread("AutoFarm", autoFarmLoop)
            else StatusLabel:Set("Status: Idle"); stopThread("AutoFarm") end
        end,
    })

    FarmTab:CreateSection("Farm Settings")
    FarmTab:CreateToggle({
        Name = "Auto Grab Escape",
        CurrentValue = false,
        Callback = function(v)
            Config.AutoGrabEscape = v
            if v then startThread("GrabEscape", autoGrabEscapeLoop) else stopThread("GrabEscape") end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Reload Blades",
        CurrentValue = false,
        Callback = function(v)
            Config.AutoReloadBlades = v
            if v then startThread("AutoReload", autoReloadLoop) else stopThread("AutoReload") end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Full Reload",
        CurrentValue = false,
        Callback = function(v) Config.AutoFullReload = v end,
    })
    FarmTab:CreateToggle({
        Name = "Infinite Spear",
        CurrentValue = false,
        Callback = function(v)
            Config.InfiniteSpear = v
            if v then startThread("InfiniteSpear", infiniteSpearLoop) else stopThread("InfiniteSpear") end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Use Skill",
        CurrentValue = false,
        Callback = function(v)
            Config.AutoUseSkill = v
            if v then startThread("AutoSkill", autoSkillLoop) else stopThread("AutoSkill") end
        end,
    })

    --// Combat Tab
    CombatTab:CreateSection("Combat Settings")
    CombatTab:CreateToggle({
        Name = "Multi Hit",
        CurrentValue = false,
        Callback = function(v)
            Config.MultiHit = v
            if v then startThread("MultiHit", multiHitLoop) else stopThread("MultiHit") end
        end,
    })
    CombatTab:CreateSlider({
        Name = "Multi Hit Radius",
        Range = {10, 200},
        Increment = 5,
        Suffix = " studs",
        CurrentValue = 50,
        Callback = function(v) Config.MultiHitRadius = v end,
    })
    CombatTab:CreateToggle({
        Name = "Boss Burst",
        CurrentValue = false,
        Callback = function(v) Config.BossBurst = v end,
    })
    CombatTab:CreateToggle({
        Name = "Nape Extender",
        CurrentValue = false,
        Callback = function(v) Config.NapeExtender = v end,
    })

    --// ESP Tab
    ESPTab:CreateSection("Titan ESP")
    ESPTab:CreateToggle({
        Name = "Titan ESP",
        CurrentValue = false,
        Callback = function(v)
            Config.TitanESP = v
            if v then startThread("ESP", espLoop)
            else stopThread("ESP"); for titan in pairs(ESPObjects) do removeESP(titan) end end
        end,
    })

    --// Misc Tab
    MiscTab:CreateSection("Character")
    MiscTab:CreateSlider({
        Name = "WalkSpeed",
        Range = {16, 100},
        Increment = 1,
        CurrentValue = 16,
        Callback = function(v) local _, _, h = getCharacter(); if h then h.WalkSpeed = v end end,
    })
    MiscTab:CreateToggle({
        Name = "NoClip",
        CurrentValue = false,
        Callback = function(v) Config.NoClip = v end,
    })
    MiscTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = false,
        Callback = function(v) Config.InfiniteJump = v end,
    })

    --// ==================== HANDLERS ====================

    RunService.Stepped:Connect(function()
        if Config.NoClip then
            local char = getCharacter()
            if char then
                for _, part in char:GetDescendants() do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
    end)

    game:GetService("UserInputService").JumpRequest:Connect(function()
        if Config.InfiniteJump then
            local _, _, h = getCharacter()
            if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)

    LP.CharacterAdded:Connect(function(c)
        Char = c; Root = c:WaitForChild("HumanoidRootPart"); Humanoid = c:WaitForChild("Humanoid")
    end)

    --// Cleanup
    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            for name in pairs(ActiveThreads) do stopThread(name) end
            for titan in pairs(ESPObjects) do removeESP(titan) end
        end)
    end
end
