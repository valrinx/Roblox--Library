--[[
    RAVEN HUB Module - Cordon
    Game: Cordon (PlaceId: 112318794071351, Universe / GameId: 10074335448)
    Experience: Cordon / ZONE OF DECAY
    Architecture: Safe Client-Side Visuals, Chams, Recoil Removal, and Movement Bypasses
    Compatible UI: MacLib Adapter Standard
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local CoreGui = game:GetService("CoreGui")
    local Lighting = game:GetService("Lighting")

    local LP = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- Original lighting & atmosphere state cache
    local origLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
        GlobalShadows = Lighting.GlobalShadows,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        Ambient = Lighting.Ambient,
        ExposureCompensation = Lighting.ExposureCompensation,
    }
    local origAtmosphere = {}
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("Atmosphere") then
            origAtmosphere[child] = {
                Density = child.Density,
                Haze = child.Haze,
                Glare = child.Glare,
                Offset = child.Offset,
            }
        end
    end

    -- Lifecycle & cleanup tracking
    local running = true
    local connections = {}
    local espObjects = {}
    local adornmentObjects = {}

    local function trackConnection(conn)
        table.insert(connections, conn)
        return conn
    end

    -- Clean old containers if left over
    pcall(function()
        local oldHolder = CoreGui:FindFirstChild("RAVEN_CORDON_CHAMS") or CoreGui:FindFirstChild("LILBIG_CORE_CHAMS")
        if oldHolder then oldHolder:Destroy() end
        local oldEsp = Workspace:FindFirstChild("RAVEN_CORDON_ESP") or Workspace:FindFirstChild("LILBIG_ESP_HOLDER")
        if oldEsp then oldEsp:Destroy() end
    end)

    -- Dedicated Adornment & Billboard containers
    local chamsContainer = Instance.new("Folder")
    chamsContainer.Name = "RAVEN_CORDON_CHAMS"
    chamsContainer.Parent = CoreGui

    local espContainer = Instance.new("Folder")
    espContainer.Name = "RAVEN_CORDON_ESP"
    espContainer.Parent = Workspace

    -- Settings State (registered with MacLib config flags)
    local settings = {
        -- Combat
        noRecoil = true,
        noCamShake = true,

        -- Visuals: Players
        espPlayers = true,
        chamsPlayers = true,
        playerMaxDist = 1500,

        -- Visuals: Hostile Bandits
        espBandits = true,
        chamsBandits = true,
        banditMaxDist = 800,

        -- Visuals: Mutants
        espMutants = true,
        chamsMutants = true,
        mutantMaxDist = 600,

        -- Visuals: Items & Drops
        espItems = true,
        chamsItems = true,
        itemMaxDist = 400,

        -- Visuals: Traders & NPCs
        espTraders = true,
        chamsTraders = true,
        traderMaxDist = 500,

        -- Visuals: World & Lighting
        fullBright = true,
        noFog = true,

        -- Movement
        noExhaustion = true,
        instantAccel = true,
        enableCustomSpeed = false,
        customWalkSpeed = 16,
    }

    local function applyLightingModifiers()
        if settings.fullBright then
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
            Lighting.Ambient = Color3.fromRGB(180, 180, 180)
            Lighting.ExposureCompensation = 0.5
        else
            Lighting.Brightness = origLighting.Brightness
            Lighting.ClockTime = origLighting.ClockTime
            Lighting.GlobalShadows = origLighting.GlobalShadows
            Lighting.OutdoorAmbient = origLighting.OutdoorAmbient
            Lighting.Ambient = origLighting.Ambient
            Lighting.ExposureCompensation = origLighting.ExposureCompensation
        end

        if settings.noFog then
            Lighting.FogEnd = 1000000
            Lighting.FogStart = 0
            for child, _ in pairs(origAtmosphere) do
                if child.Parent == Lighting then
                    child.Density = 0
                    child.Haze = 0
                    child.Glare = 0
                end
            end
        else
            Lighting.FogEnd = origLighting.FogEnd
            Lighting.FogStart = origLighting.FogStart
            for child, orig in pairs(origAtmosphere) do
                if child.Parent == Lighting then
                    child.Density = orig.Density
                    child.Haze = orig.Haze
                    child.Glare = orig.Glare
                end
            end
        end
    end
    applyLightingModifiers()

    -- Color Palette
    local COLOR_TEAM    = Color3.fromRGB(0, 220, 255)   -- Cyan
    local COLOR_ENEMY   = Color3.fromRGB(255, 30, 30)    -- Bright Red
    local COLOR_BANDIT  = Color3.fromRGB(255, 130, 0)   -- Orange
    local COLOR_MUTANT  = Color3.fromRGB(255, 0, 140)   -- Neon Pink
    local COLOR_TRADER  = Color3.fromRGB(0, 255, 100)   -- Green
    local COLOR_ITEM    = Color3.fromRGB(200, 80, 255)  -- Violet

    local ALLOWED_HUMAN_LIMBS = {
        ["Head"] = true, ["Torso"] = true,
        ["Left Arm"] = true, ["Right Arm"] = true,
        ["Left Leg"] = true, ["Right Leg"] = true
    }

    ---------------------------------------------------------------------------
    -- Adornment System (BoxHandleAdornment - High-Performance)
    ---------------------------------------------------------------------------
    local function createBoxAdornment(part, color, customSize, customCFrame, category)
        if not part or not part:IsA("BasePart") then return end
        local adorn = Instance.new("BoxHandleAdornment")
        adorn.Name = "CHAM_" .. part.Name
        adorn.Adornee = part
        adorn.Size = customSize or (part.Size + Vector3.new(0.04, 0.04, 0.04))
        if customCFrame then adorn.CFrame = customCFrame end
        adorn.Color3 = color
        adorn.Transparency = 0.42
        adorn.AlwaysOnTop = true
        adorn.ZIndex = 10
        adorn.Parent = chamsContainer

        table.insert(adornmentObjects, {inst = adorn, part = part, category = category, color = color})
        return adorn
    end

    local function attachHumanoidChams(model, color, category)
        for _, child in ipairs(model:GetChildren()) do
            if child:IsA("BasePart") and ALLOWED_HUMAN_LIMBS[child.Name] then
                createBoxAdornment(child, color, nil, nil, category)
            end
        end
    end

    local function attachMutantChams(model, color)
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp then
            -- Exact bounding box calibrated for Flesh & Quadruped mutant meshes
            createBoxAdornment(hrp, color, Vector3.new(4.2, 3.8, 4.5), CFrame.new(0, -0.5, 0), "mutants")
        end
    end

    ---------------------------------------------------------------------------
    -- Billboard Tag ESP
    ---------------------------------------------------------------------------
    local function createTag(model, root, color, prefix, category, maxDist, customOffset)
        if not model or not root then return end
        local bg = Instance.new("BillboardGui")
        bg.Name = "TAG_" .. model.Name
        bg.Adornee = root
        bg.Size = UDim2.new(0, 180, 0, 28)
        bg.StudsOffset = customOffset or Vector3.new(0, 2.2, 0)
        bg.AlwaysOnTop = true
        bg.MaxDistance = maxDist or 500
        bg.Parent = espContainer

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = color
        lbl.TextStrokeTransparency = 0.15
        lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.Text = prefix .. " " .. model.Name
        lbl.Parent = bg

        table.insert(espObjects, {
            model = model,
            root = root,
            prefix = prefix,
            category = category,
            bg = bg,
            lbl = lbl,
            maxDist = maxDist or 500
        })
    end

    ---------------------------------------------------------------------------
    -- Entity Hooking
    ---------------------------------------------------------------------------
    local hookedModels = {}

    local function hookPlayer(p)
        if p == LP then return end
        local function onChar(char)
            task.wait(0.4)
            if not char.Parent or hookedModels[char] then return end
            hookedModels[char] = true

            local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
            if root then
                local isTeam = (LP.Team and p.Team and LP.Team == p.Team)
                local col = isTeam and COLOR_TEAM or COLOR_ENEMY
                local prefix = isTeam and "[TEAM]" or "[ENEMY]"
                attachHumanoidChams(char, col, "players")
                createTag(char, root, col, prefix, "players", settings.playerMaxDist)
            end
        end
        if p.Character then onChar(p.Character) end
        trackConnection(p.CharacterAdded:Connect(onChar))
    end

    for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
    trackConnection(Players.PlayerAdded:Connect(hookPlayer))

    local function scanWorldEntities()
        -- 1. Bandits (Hostile NPCs)
        local hostiles = Workspace:FindFirstChild("PlayerCharacters") and Workspace.PlayerCharacters:FindFirstChild("HostileNPCs")
        if hostiles then
            for _, mob in ipairs(hostiles:GetChildren()) do
                if mob:IsA("Model") and not hookedModels[mob] then
                    hookedModels[mob] = true
                    local root = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Head")
                    local w = mob:FindFirstChildWhichIsA("Tool")
                    local prefix = w and ("[BANDIT " .. w.Name .. "]") or "[BANDIT]"
                    attachHumanoidChams(mob, COLOR_BANDIT, "bandits")
                    createTag(mob, root, COLOR_BANDIT, prefix, "bandits", settings.banditMaxDist)
                end
            end
        end

        -- 2. Mutants
        local mutants = Workspace:FindFirstChild("Mutants")
        if mutants then
            for _, mut in ipairs(mutants:GetChildren()) do
                if mut:IsA("Model") and not hookedModels[mut] then
                    hookedModels[mut] = true
                    local root = mut:FindFirstChild("HumanoidRootPart")
                    if root then
                        attachMutantChams(mut, COLOR_MUTANT)
                        createTag(mut, root, COLOR_MUTANT, "[MUTANT]", "mutants", settings.mutantMaxDist, Vector3.new(0, 2.5, 0))
                    end
                end
            end
        end

        -- 3. Traders & NPCs
        local npcs = Workspace:FindFirstChild("NPCs")
        if npcs then
            for _, n in ipairs(npcs:GetDescendants()) do
                if n:IsA("Model") and not hookedModels[n] and (n:FindFirstChild("Humanoid") or n:FindFirstChild("Head")) then
                    hookedModels[n] = true
                    local root = n:FindFirstChild("HumanoidRootPart") or n:FindFirstChild("Head")
                    attachHumanoidChams(n, COLOR_TRADER, "traders")
                    createTag(n, root, COLOR_TRADER, "[NPC]", "traders", settings.traderMaxDist)
                end
            end
        end

        -- 4. Ground Drops & Items
        local drops = Workspace:FindFirstChild("Drops")
        if drops then
            for _, d in ipairs(drops:GetChildren()) do
                if not hookedModels[d] then
                    hookedModels[d] = true
                    local root = d:IsA("BasePart") and d or d:FindFirstChildWhichIsA("BasePart")
                    if root then
                        createBoxAdornment(root, COLOR_ITEM, nil, nil, "items")
                        createTag(d, root, COLOR_ITEM, "[ITEM]", "items", settings.itemMaxDist)
                    end
                end
            end
        end
    end
    scanWorldEntities()

    -- Periodic rescan for newly spawned entities
    local scanTimer = 0
    trackConnection(RunService.Heartbeat:Connect(function(dt)
        scanTimer = scanTimer + dt
        if scanTimer >= 3.0 then
            scanTimer = 0
            scanWorldEntities()
        end
    end))

    ---------------------------------------------------------------------------
    -- Movement & Stamina Bypasses
    ---------------------------------------------------------------------------
    local origMomentumConfig = nil
    local function applyMovementPhysics()
        local mMod = ReplicatedStorage:FindFirstChild("Modules")
            and ReplicatedStorage.Modules:FindFirstChild("InertiaController")
            and ReplicatedStorage.Modules.InertiaController:FindFirstChild("Momentum")
        local momentum = mMod and require(mMod)
        if momentum and momentum.Config then
            if not origMomentumConfig then
                origMomentumConfig = {
                    BaseAcceleration = momentum.Config.BaseAcceleration,
                    MoveAcceleration = momentum.Config.MoveAcceleration,
                    SprintAcceleration = momentum.Config.SprintAcceleration,
                    ExhaustedAcceleration = momentum.Config.ExhaustedAcceleration,
                }
            end
            if settings.instantAccel then
                momentum.Config.BaseAcceleration = 30
                momentum.Config.MoveAcceleration = 30
                momentum.Config.SprintAcceleration = 25
                momentum.Config.ExhaustedAcceleration = 25
            elseif origMomentumConfig then
                momentum.Config.BaseAcceleration = origMomentumConfig.BaseAcceleration
                momentum.Config.MoveAcceleration = origMomentumConfig.MoveAcceleration
                momentum.Config.SprintAcceleration = origMomentumConfig.SprintAcceleration
                momentum.Config.ExhaustedAcceleration = origMomentumConfig.ExhaustedAcceleration
            end
        end

        if LP.Character and settings.noExhaustion then
            LP.Character:SetAttribute("SpeedCap_Stamina", nil)
        end
    end
    applyMovementPhysics()

    ---------------------------------------------------------------------------
    -- Weapon Modifications (Recoil & CamShake Suppression)
    ---------------------------------------------------------------------------
    local function applyWeaponMods()
        if not settings.noRecoil then return end
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" and rawget(obj, "recoilMod") ~= nil then
                rawset(obj, "recoilMod", 0)
                rawset(obj, "gunRecoilMod", 0)
                rawset(obj, "vertical", 0)
                rawset(obj, "horizontal", 0)
                rawset(obj, "camShake", 0)
                rawset(obj, "spread", 0)
            end
        end
    end
    applyWeaponMods()

    ---------------------------------------------------------------------------
    -- Main Update Loop
    ---------------------------------------------------------------------------
    trackConnection(RunService.Heartbeat:Connect(function()
        if not running then return end

        local myChar = LP.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end
        local myPos = myHrp.Position

        -- Enforce Stamina SpeedCap neutralization
        if settings.noExhaustion and myChar:GetAttribute("SpeedCap_Stamina") ~= nil then
            myChar:SetAttribute("SpeedCap_Stamina", nil)
        end

        -- Enforce Fullbright & No Fog continuously
        if settings.fullBright then
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(220, 220, 220)
            Lighting.Ambient = Color3.fromRGB(200, 200, 200)
            Lighting.ExposureCompensation = 0.5
        end
        if settings.noFog then
            Lighting.FogEnd = 1000000
            Lighting.FogStart = 0
            for child, _ in pairs(origAtmosphere) do
                if child.Parent == Lighting then
                    child.Density = 0
                    child.Haze = 0
                    child.Glare = 0
                end
            end
        end

        -- Custom WalkSpeed if enabled
        if settings.enableCustomSpeed then
            local hum = myChar:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed ~= settings.customWalkSpeed then
                hum.WalkSpeed = settings.customWalkSpeed
            end
        end

        -- Update Billboard tags
        for i = #espObjects, 1, -1 do
            local entry = espObjects[i]
            if not entry.model.Parent or not entry.root.Parent then
                if entry.bg.Parent then entry.bg:Destroy() end
                table.remove(espObjects, i)
            else
                local dist = math.floor((entry.root.Position - myPos).Magnitude)
                local enabled = false
                local maxDist = 500

                if entry.category == "players" then
                    enabled = settings.espPlayers
                    maxDist = settings.playerMaxDist
                elseif entry.category == "bandits" then
                    enabled = settings.espBandits
                    maxDist = settings.banditMaxDist
                elseif entry.category == "mutants" then
                    enabled = settings.espMutants
                    maxDist = settings.mutantMaxDist
                elseif entry.category == "items" then
                    enabled = settings.espItems
                    maxDist = settings.itemMaxDist
                elseif entry.category == "traders" then
                    enabled = settings.espTraders
                    maxDist = settings.traderMaxDist
                end

                entry.bg.MaxDistance = maxDist
                entry.bg.Enabled = enabled and (dist <= maxDist)
                if entry.bg.Enabled then
                    entry.lbl.Text = string.format("%s %s [%dm]", entry.prefix, entry.model.Name, dist)
                end
            end
        end

        -- Update Adornments
        for i = #adornmentObjects, 1, -1 do
            local a = adornmentObjects[i]
            if not a.part.Parent then
                if a.inst.Parent then a.inst:Destroy() end
                table.remove(adornmentObjects, i)
            else
                local enabled = false
                if a.category == "players" then
                    enabled = settings.chamsPlayers
                elseif a.category == "bandits" then
                    enabled = settings.chamsBandits
                elseif a.category == "mutants" then
                    enabled = settings.chamsMutants
                elseif a.category == "items" then
                    enabled = settings.chamsItems
                elseif a.category == "traders" then
                    enabled = settings.chamsTraders
                end

                local dist = (a.part.Position - myPos).Magnitude
                local maxDist = (a.category == "players" and settings.playerMaxDist)
                    or (a.category == "bandits" and settings.banditMaxDist)
                    or (a.category == "mutants" and settings.mutantMaxDist)
                    or (a.category == "items" and settings.itemMaxDist)
                    or (a.category == "traders" and settings.traderMaxDist)
                    or 500

                a.inst.Transparency = (enabled and dist <= maxDist) and 0.42 or 1
            end
        end
    end))

    ---------------------------------------------------------------------------
    -- User Interface (MacLib Standard Window & Tabs)
    ---------------------------------------------------------------------------

    -- Tab 1: Visuals & ESP
    local VisualTab = Window:CreateTab("Visuals", 104811813262009)

    VisualTab:CreateSection("Players & Factions")
    VisualTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = settings.espPlayers,
        Flag = "Cordon_PlayerESP",
        Callback = function(val) settings.espPlayers = val end,
    })
    VisualTab:CreateToggle({
        Name = "Player Skeleton Chams",
        CurrentValue = settings.chamsPlayers,
        Flag = "Cordon_PlayerChams",
        Callback = function(val) settings.chamsPlayers = val end,
    })
    VisualTab:CreateSlider({
        Name = "Player Max Distance",
        Range = {100, 2500},
        Increment = 50,
        CurrentValue = settings.playerMaxDist,
        Flag = "Cordon_PlayerMaxDist",
        Callback = function(val) settings.playerMaxDist = val end,
    })

    VisualTab:CreateSection("Mutants & Hostiles")
    VisualTab:CreateToggle({
        Name = "Hostile Bandits ESP",
        CurrentValue = settings.espBandits,
        Flag = "Cordon_BanditESP",
        Callback = function(val) settings.espBandits = val end,
    })
    VisualTab:CreateToggle({
        Name = "Hostile Bandits Chams",
        CurrentValue = settings.chamsBandits,
        Flag = "Cordon_BanditChams",
        Callback = function(val) settings.chamsBandits = val end,
    })
    VisualTab:CreateToggle({
        Name = "Mutant ESP (Flesh / Mobs)",
        CurrentValue = settings.espMutants,
        Flag = "Cordon_MutantESP",
        Callback = function(val) settings.espMutants = val end,
    })
    VisualTab:CreateToggle({
        Name = "Mutant Body Chams (Accurate Mesh)",
        CurrentValue = settings.chamsMutants,
        Flag = "Cordon_MutantChams",
        Callback = function(val) settings.chamsMutants = val end,
    })
    VisualTab:CreateSlider({
        Name = "Hostiles Max Distance",
        Range = {100, 1500},
        Increment = 50,
        CurrentValue = settings.banditMaxDist,
        Flag = "Cordon_HostilesMaxDist",
        Callback = function(val)
            settings.banditMaxDist = val
            settings.mutantMaxDist = val
        end,
    })

    VisualTab:CreateSection("Loot & Traders")
    VisualTab:CreateToggle({
        Name = "Loot & Dropped Items ESP",
        CurrentValue = settings.espItems,
        Flag = "Cordon_ItemESP",
        Callback = function(val) settings.espItems = val end,
    })
    VisualTab:CreateToggle({
        Name = "Item Box Chams",
        CurrentValue = settings.chamsItems,
        Flag = "Cordon_ItemChams",
        Callback = function(val) settings.chamsItems = val end,
    })
    VisualTab:CreateToggle({
        Name = "Traders & Safezone NPCs ESP",
        CurrentValue = settings.espTraders,
        Flag = "Cordon_TraderESP",
        Callback = function(val) settings.espTraders = val end,
    })
    VisualTab:CreateSlider({
        Name = "Loot Max Distance",
        Range = {50, 1000},
        Increment = 25,
        CurrentValue = settings.itemMaxDist,
        Flag = "Cordon_ItemMaxDist",
        Callback = function(val) settings.itemMaxDist = val end,
    })

    VisualTab:CreateSection("World & Lighting")
    VisualTab:CreateToggle({
        Name = "Fullbright (Clear Daylight)",
        CurrentValue = settings.fullBright,
        Flag = "Cordon_Fullbright",
        Callback = function(val)
            settings.fullBright = val
            applyLightingModifiers()
        end,
    })
    VisualTab:CreateToggle({
        Name = "No Fog (Remove Atmosphere & Haze)",
        CurrentValue = settings.noFog,
        Flag = "Cordon_NoFog",
        Callback = function(val)
            settings.noFog = val
            applyLightingModifiers()
        end,
    })

    -- Tab 2: Movement & Bypasses
    local MoveTab = Window:CreateTab("Movement", 121700697298748)

    MoveTab:CreateSection("Stamina & Acceleration")
    MoveTab:CreateToggle({
        Name = "Infinite Stamina (No Exhaustion Bypass)",
        CurrentValue = settings.noExhaustion,
        Flag = "Cordon_NoExhaustion",
        Callback = function(val)
            settings.noExhaustion = val
            applyMovementPhysics()
        end,
    })
    MoveTab:CreateToggle({
        Name = "Instant Acceleration (Max Sprint Response)",
        CurrentValue = settings.instantAccel,
        Flag = "Cordon_InstantAccel",
        Callback = function(val)
            settings.instantAccel = val
            applyMovementPhysics()
        end,
    })

    MoveTab:CreateSection("WalkSpeed Control")
    MoveTab:CreateToggle({
        Name = "Enable Custom WalkSpeed",
        CurrentValue = settings.enableCustomSpeed,
        Flag = "Cordon_EnableSpeed",
        Callback = function(val)
            settings.enableCustomSpeed = val
            if not val and LP.Character then
                local hum = LP.Character:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = 10 end
            end
        end,
    })
    MoveTab:CreateSlider({
        Name = "Custom WalkSpeed",
        Range = {10, 45},
        Increment = 1,
        CurrentValue = settings.customWalkSpeed,
        Flag = "Cordon_CustomSpeed",
        Callback = function(val) settings.customWalkSpeed = val end,
    })

    -- Tab 3: Combat
    local CombatTab = Window:CreateTab("Combat", 99275039709063)

    CombatTab:CreateSection("Recoil & Handling")
    CombatTab:CreateToggle({
        Name = "No Recoil / Zero Spread",
        CurrentValue = settings.noRecoil,
        Flag = "Cordon_NoRecoil",
        Callback = function(val)
            settings.noRecoil = val
            applyWeaponMods()
        end,
    })

    -- Sort Tabs: Overview -> Visuals -> Movement -> Combat -> Settings
    pcall(function()
        if type(Window.SortTabs) == "function" then
            Window:SortTabs({"Overview", "Visuals", "Movement", "Combat", "Settings"})
        end
    end)

    -- Cleanup Registration
    if type(scriptInfo) == "table" and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(function()
            running = false
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            if chamsContainer.Parent then pcall(function() chamsContainer:Destroy() end) end
            if espContainer.Parent then pcall(function() espContainer:Destroy() end) end
            if origMomentumConfig then
                local mMod = ReplicatedStorage:FindFirstChild("Modules")
                    and ReplicatedStorage.Modules:FindFirstChild("InertiaController")
                    and ReplicatedStorage.Modules.InertiaController:FindFirstChild("Momentum")
                local momentum = mMod and require(mMod)
                if momentum and momentum.Config then
                    momentum.Config.BaseAcceleration = origMomentumConfig.BaseAcceleration
                    momentum.Config.MoveAcceleration = origMomentumConfig.MoveAcceleration
                    momentum.Config.SprintAcceleration = origMomentumConfig.SprintAcceleration
                    momentum.Config.ExhaustedAcceleration = origMomentumConfig.ExhaustedAcceleration
                end
            end
            -- Restore original lighting & atmospheres
            Lighting.Brightness = origLighting.Brightness
            Lighting.ClockTime = origLighting.ClockTime
            Lighting.GlobalShadows = origLighting.GlobalShadows
            Lighting.OutdoorAmbient = origLighting.OutdoorAmbient
            Lighting.Ambient = origLighting.Ambient
            Lighting.ExposureCompensation = origLighting.ExposureCompensation
            Lighting.FogEnd = origLighting.FogEnd
            Lighting.FogStart = origLighting.FogStart
            for child, orig in pairs(origAtmosphere) do
                if child.Parent == Lighting then
                    child.Density = orig.Density
                    child.Haze = orig.Haze
                    child.Glare = orig.Glare
                end
            end
        end)
    end
end
