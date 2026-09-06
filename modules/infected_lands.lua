-- ===========================================================================
-- RAVEN HUB | Infected Lands Module
-- Game: Infected Lands (PlaceId: 122789100578830, Universe: 8468366390)
-- Architecture: Safe Client-Side Visuals, Aimbot, and Environmental Utilities
-- ===========================================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")

    local LP = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- Connection & instance cleaner
    local connections = {}
    local espObjects = {}

    local function trackConnection(connection)
        table.insert(connections, connection)
        return connection
    end

    ---------------------------------------------------------------------------
    -- Settings State
    ---------------------------------------------------------------------------
    local settings = {
        -- ESP Settings
        espPlayers = true,
        espZombies = true,
        espGroundItems = true,
        espVehicles = true,
        espCorpses = true,
        espMaxDistance = 1200,
        espShowDistance = true,
        espShowHealth = true,

        -- Aimbot Settings
        aimbotEnabled = true,
        aimbotTarget = "Head", -- "Head" or "Torso"
        aimbotTargetType = "Both", -- "Zombies", "Players", "Both"
        aimbotFOV = 150,
        aimbotSmoothness = 0.25,
        aimbotShowFOV = true,

        -- Visuals & Lighting
        fullBright = false,
        noFog = false,

        -- Utility
        instantPrompt = false,
    }

    ---------------------------------------------------------------------------
    -- Original Lighting Cache
    ---------------------------------------------------------------------------
    local origLighting = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ExposureCompensation = Lighting.ExposureCompensation,
    }

    ---------------------------------------------------------------------------
    -- Drawing FOV Circle
    ---------------------------------------------------------------------------
    local fovCircle = nil
    if Drawing and type(Drawing.new) == "function" then
        pcall(function()
            fovCircle = Drawing.new("Circle")
            fovCircle.Thickness = 1.5
            fovCircle.NumSides = 36
            fovCircle.Radius = settings.aimbotFOV
            fovCircle.Filled = false
            fovCircle.Color = Color3.fromRGB(80, 220, 120)
            fovCircle.Transparency = 0.75
            fovCircle.Visible = false
        end)
    end

    ---------------------------------------------------------------------------
    -- Entity & Root Finding Utilities
    ---------------------------------------------------------------------------
    local function getRoot(model)
        if not model then return nil end
        if model:IsA("BasePart") then return model end
        if not model:IsA("Model") then return nil end

        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("LowerTorso")
            or model:FindFirstChild("Head")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart")
    end

    local function getHumanoid(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    ---------------------------------------------------------------------------
    -- ESP Rendering Functions
    ---------------------------------------------------------------------------
    local function createESP(inst, color, title, isModel, tag)
        if espObjects[inst] then return end

        local highlight = Instance.new("Highlight")
        highlight.FillColor = color
        highlight.OutlineColor = Color3.new(1, 1, 1)
        highlight.FillTransparency = 0.65
        highlight.OutlineTransparency = 0.2
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = inst
        pcall(function() highlight.Parent = inst end)

        local bbPart = inst
        if isModel then
            bbPart = inst:FindFirstChild("Head") or inst:FindFirstChild("HumanoidRootPart") or inst:FindFirstChild("Torso") or inst.PrimaryPart
            if not bbPart then
                bbPart = inst:FindFirstChildWhichIsA("BasePart")
            end
        end

        local billboard = nil
        local titleLabel = nil
        local subLabel = nil

        if bbPart then
            billboard = Instance.new("BillboardGui")
            billboard.Name = "RAVEN_ESP"
            billboard.Size = UDim2.new(0, 150, 0, 34)
            billboard.StudsOffset = Vector3.new(0, 2.5, 0)
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 1500
            billboard.Adornee = bbPart
            pcall(function() billboard.Parent = bbPart end)

            titleLabel = Instance.new("TextLabel")
            titleLabel.Name = "Title"
            titleLabel.Text = title
            titleLabel.Font = Enum.Font.GothamBold
            titleLabel.TextSize = 12
            titleLabel.TextColor3 = color
            titleLabel.TextStrokeTransparency = 0.2
            titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Size = UDim2.new(1, 0, 0.5, 0)
            titleLabel.Position = UDim2.new(0, 0, 0, 0)
            titleLabel.Parent = billboard

            subLabel = Instance.new("TextLabel")
            subLabel.Name = "Sub"
            subLabel.Text = ""
            subLabel.Font = Enum.Font.Gotham
            subLabel.TextSize = 10
            subLabel.TextColor3 = Color3.fromRGB(225, 225, 225)
            subLabel.TextStrokeTransparency = 0.3
            subLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            subLabel.BackgroundTransparency = 1
            subLabel.Size = UDim2.new(1, 0, 0.5, 0)
            subLabel.Position = UDim2.new(0, 0, 0.5, 0)
            subLabel.Parent = billboard
        end

        espObjects[inst] = {
            highlight = highlight,
            billboard = billboard,
            titleLabel = titleLabel,
            subLabel = subLabel,
            tag = tag,
            color = color,
            inst = inst
        }
    end

    local function removeESP(inst)
        local data = espObjects[inst]
        if not data then return end
        if data.highlight then pcall(function() data.highlight:Destroy() end) end
        if data.billboard then pcall(function() data.billboard:Destroy() end) end
        espObjects[inst] = nil
    end

    local function clearESPByTag(tag)
        local toRemove = {}
        for inst, data in pairs(espObjects) do
            if data.tag == tag then
                table.insert(toRemove, inst)
            end
        end
        for _, inst in ipairs(toRemove) do
            removeESP(inst)
        end
    end

    local function clearAllESP()
        for inst, _ in pairs(espObjects) do
            removeESP(inst)
        end
    end

    ---------------------------------------------------------------------------
    -- Active Entity Resolution
    ---------------------------------------------------------------------------
    local function getActivePlayers()
        local list = {}
        local pFolder = Workspace:FindFirstChild("Players")
        if pFolder then
            for _, ch in ipairs(pFolder:GetChildren()) do
                if ch:IsA("Model") and ch ~= LP.Character then
                    local hum = getHumanoid(ch)
                    local root = getRoot(ch)
                    if hum and root and hum.Health > 0 then
                        table.insert(list, {model = ch, humanoid = hum, root = root})
                    end
                end
            end
        end
        return list
    end

    local function getActiveZombies()
        local list = {}
        local zFolder = Workspace:FindFirstChild("Zombies")
        if zFolder then
            for _, ch in ipairs(zFolder:GetChildren()) do
                if ch:IsA("Model") then
                    local root = getRoot(ch)
                    local hum = getHumanoid(ch)
                    local isDead = ch:GetAttribute("Dead") == true
                    local health = ch:GetAttribute("Health") or (hum and hum.Health) or 100
                    local maxHealth = ch:GetAttribute("MaxHealth") or (hum and hum.MaxHealth) or 100

                    if root and not isDead and health > 0 then
                        table.insert(list, {
                            model = ch,
                            humanoid = hum,
                            root = root,
                            health = health,
                            maxHealth = maxHealth
                        })
                    end
                end
            end
        end
        return list
    end

    ---------------------------------------------------------------------------
    -- Core ESP Update Loop
    ---------------------------------------------------------------------------
    local function updateESP()
        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        local myPos = myRoot and myRoot.Position or Vector3.zero

        -- 1. Players ESP
        if settings.espPlayers then
            local players = getActivePlayers()
            for _, info in ipairs(players) do
                local dist = (info.root.Position - myPos).Magnitude
                if dist <= settings.espMaxDistance then
                    if not espObjects[info.model] then
                        createESP(info.model, Color3.fromRGB(60, 160, 255), "👤 " .. info.model.Name, true, "player")
                    end
                    local data = espObjects[info.model]
                    if data and data.subLabel then
                        local parts = {}
                        if settings.espShowDistance then table.insert(parts, math.floor(dist) .. "m") end
                        if settings.espShowHealth then table.insert(parts, "HP: " .. math.floor(info.humanoid.Health)) end
                        data.subLabel.Text = table.concat(parts, " | ")
                    end
                else
                    if espObjects[info.model] then removeESP(info.model) end
                end
            end
        else
            clearESPByTag("player")
        end

        -- 2. Zombies ESP
        if settings.espZombies then
            local zombies = getActiveZombies()
            for _, info in ipairs(zombies) do
                local dist = (info.root.Position - myPos).Magnitude
                if dist <= settings.espMaxDistance then
                    if not espObjects[info.model] then
                        local zName = info.model.Name
                        if zName:find("Police") then
                            zName = "Police Zombie"
                        elseif zName:find("Firefighter") then
                            zName = "Firefighter Zombie"
                        elseif zName:find("Casual") or zName:find("Farmer") then
                            zName = "Farmer Zombie"
                        elseif zName:find("EMS") then
                            zName = "EMS Zombie"
                        elseif zName:find("Construction") then
                            zName = "Construction Zombie"
                        elseif zName:find("Hazmat") then
                            zName = "Hazmat Zombie"
                        else
                            zName = "Zombie"
                        end
                        createESP(info.model, Color3.fromRGB(255, 80, 80), "🧟 " .. zName, true, "zombie")
                    end
                    local data = espObjects[info.model]
                    if data and data.subLabel then
                        local parts = {}
                        if settings.espShowDistance then table.insert(parts, math.floor(dist) .. "m") end
                        if settings.espShowHealth then table.insert(parts, "HP: " .. math.floor(info.health)) end
                        data.subLabel.Text = table.concat(parts, " | ")
                    end
                else
                    if espObjects[info.model] then removeESP(info.model) end
                end
            end
        else
            clearESPByTag("zombie")
        end

        -- 3. Ground Items ESP
        local gFolder = Workspace:FindFirstChild("grounditems")
        if settings.espGroundItems and gFolder then
            for _, item in ipairs(gFolder:GetChildren()) do
                local root = getRoot(item)
                if root then
                    local dist = (root.Position - myPos).Magnitude
                    if dist <= settings.espMaxDistance then
                        if not espObjects[item] then
                            local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                            local itemName = (prompt and prompt.ObjectText ~= "" and prompt.ObjectText) or item.Name:gsub("^%w+%-?%w*%-?%w*%-?%w*%-?%w*", "")
                            if itemName == "" then itemName = item.Name end

                            createESP(item, Color3.fromRGB(255, 215, 0), "📦 " .. itemName, item:IsA("Model"), "item")
                        end
                        local data = espObjects[item]
                        if data and data.subLabel and settings.espShowDistance then
                            data.subLabel.Text = math.floor(dist) .. "m"
                        end
                    else
                        if espObjects[item] then removeESP(item) end
                    end
                end
            end
        else
            clearESPByTag("item")
        end

        -- 4. Vehicles ESP
        local vFolder = Workspace:FindFirstChild("Vehicles")
        if settings.espVehicles and vFolder then
            for _, veh in ipairs(vFolder:GetChildren()) do
                local root = getRoot(veh)
                if root then
                    local dist = (root.Position - myPos).Magnitude
                    if dist <= settings.espMaxDistance * 1.5 then
                        if not espObjects[veh] then
                            createESP(veh, Color3.fromRGB(130, 220, 255), "🚗 " .. veh.Name, true, "vehicle")
                        end
                        local data = espObjects[veh]
                        if data and data.subLabel and settings.espShowDistance then
                            data.subLabel.Text = math.floor(dist) .. "m"
                        end
                    else
                        if espObjects[veh] then removeESP(veh) end
                    end
                end
            end
        else
            clearESPByTag("vehicle")
        end

        -- 5. Corpses ESP
        local cFolder = Workspace:FindFirstChild("PlayerCorpses")
        if settings.espCorpses and cFolder then
            for _, corpse in ipairs(cFolder:GetChildren()) do
                local root = getRoot(corpse)
                if root then
                    local dist = (root.Position - myPos).Magnitude
                    if dist <= settings.espMaxDistance then
                        if not espObjects[corpse] then
                            createESP(corpse, Color3.fromRGB(200, 130, 255), "💀 " .. corpse.Name, true, "corpse")
                        end
                        local data = espObjects[corpse]
                        if data and data.subLabel and settings.espShowDistance then
                            data.subLabel.Text = math.floor(dist) .. "m"
                        end
                    else
                        if espObjects[corpse] then removeESP(corpse) end
                    end
                end
            end
        else
            clearESPByTag("corpse")
        end

        -- Cleanup dead or destroyed entities
        for inst, data in pairs(espObjects) do
            if not inst.Parent then
                removeESP(inst)
            elseif data.tag == "player" then
                local hum = getHumanoid(inst)
                if not hum or hum.Health <= 0 then
                    removeESP(inst)
                end
            elseif data.tag == "zombie" then
                local isDead = inst:GetAttribute("Dead") == true
                local health = inst:GetAttribute("Health")
                if isDead or (health and health <= 0) then
                    removeESP(inst)
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Safe Mouse / Camera Aimbot
    ---------------------------------------------------------------------------
    local function getClosestAimTarget()
        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return nil end

        local mousePos = UserInputService:GetMouseLocation()
        local bestTargetPart = nil
        local bestDist = settings.aimbotFOV

        local candidates = {}
        if settings.aimbotTargetType == "Zombies" or settings.aimbotTargetType == "Both" then
            for _, z in ipairs(getActiveZombies()) do
                table.insert(candidates, z.model)
            end
        end
        if settings.aimbotTargetType == "Players" or settings.aimbotTargetType == "Both" then
            for _, p in ipairs(getActivePlayers()) do
                table.insert(candidates, p.model)
            end
        end

        for _, model in ipairs(candidates) do
            local hum = getHumanoid(model)
            local isDead = model:GetAttribute("Dead") == true
            local health = model:GetAttribute("Health") or (hum and hum.Health) or 100
            local targetPart = model:FindFirstChild(settings.aimbotTarget) or getRoot(model)

            if not isDead and health > 0 and targetPart then
                local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                if onScreen then
                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if screenDist < bestDist then
                        bestDist = screenDist
                        bestTargetPart = targetPart
                    end
                end
            end
        end

        return bestTargetPart
    end

    ---------------------------------------------------------------------------
    -- Environmental Lighting Mods
    ---------------------------------------------------------------------------
    local function applyLighting()
        if settings.fullBright then
            Lighting.Brightness = 2.5
            Lighting.ClockTime = 14
            Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 150)
            Lighting.ExposureCompensation = 0.5
        end

        if settings.noFog then
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
        end
    end

    local function restoreLighting()
        Lighting.Brightness = origLighting.Brightness
        Lighting.ClockTime = origLighting.ClockTime
        Lighting.FogEnd = origLighting.FogEnd
        Lighting.GlobalShadows = origLighting.GlobalShadows
        Lighting.OutdoorAmbient = origLighting.OutdoorAmbient
        Lighting.ExposureCompensation = origLighting.ExposureCompensation
    end

    ---------------------------------------------------------------------------
    -- Instant ProximityPrompt Interaction
    ---------------------------------------------------------------------------
    local function hookPrompts()
        trackConnection(Workspace.DescendantAdded:Connect(function(desc)
            if settings.instantPrompt and desc:IsA("ProximityPrompt") then
                desc.HoldDuration = 0
            end
        end))

        if settings.instantPrompt then
            for _, desc in ipairs(Workspace:GetDescendants()) do
                if desc:IsA("ProximityPrompt") then
                    desc.HoldDuration = 0
                end
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Render & Input Loops
    ---------------------------------------------------------------------------
    trackConnection(RunService.RenderStepped:Connect(function()
        -- 1. FOV Circle positioning
        if fovCircle then
            fovCircle.Visible = settings.aimbotEnabled and settings.aimbotShowFOV
            fovCircle.Radius = settings.aimbotFOV
            fovCircle.Position = UserInputService:GetMouseLocation()
        end

        -- 2. Smooth Aimbot on Right Click (MouseButton2)
        if settings.aimbotEnabled and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local targetPart = getClosestAimTarget()
            if targetPart then
                local targetPos = targetPart.Position
                local camCF = Camera.CFrame
                local targetCF = CFrame.new(camCF.Position, targetPos)
                Camera.CFrame = camCF:Lerp(targetCF, math.clamp(settings.aimbotSmoothness, 0.05, 1))
            end
        end

        -- 3. Lighting check
        if settings.fullBright or settings.noFog then
            applyLighting()
        end
    end))

    -- Throttled ESP Loop (10 Hz for minimal CPU load)
    task.spawn(function()
        while true do
            pcall(updateESP)
            task.wait(0.1)
        end
    end)

    hookPrompts()

    ---------------------------------------------------------------------------
    -- MacLib UI Construction
    ---------------------------------------------------------------------------
    local CombatTab = Window:Tab({
        Name = "Combat",
        Image = "rbxassetid://10723415903"
    })

    local VisualsTab = Window:Tab({
        Name = "Visuals (ESP)",
        Image = "rbxassetid://10723346959"
    })

    local WorldTab = Window:Tab({
        Name = "World & QoL",
        Image = "rbxassetid://10734950309"
    })

    ---------------------------------------------------------------------------
    -- Combat Tab Elements
    ---------------------------------------------------------------------------
    CombatTab:Section({ Title = "Aimbot Settings (Smooth Camera)" })

    CombatTab:Toggle({
        Name = "Aimbot Enabled (Hold RMB)",
        Default = settings.aimbotEnabled,
        Callback = function(val)
            settings.aimbotEnabled = val
        end
    })

    CombatTab:Dropdown({
        Name = "Target Type",
        Multi = false,
        Required = true,
        Options = {"Both", "Zombies", "Players"},
        Default = settings.aimbotTargetType,
        Callback = function(val)
            settings.aimbotTargetType = val
        end
    })

    CombatTab:Dropdown({
        Name = "Target Bone",
        Multi = false,
        Required = true,
        Options = {"Head", "Torso"},
        Default = settings.aimbotTarget,
        Callback = function(val)
            settings.aimbotTarget = val
        end
    })

    CombatTab:Slider({
        Name = "Aimbot FOV",
        Min = 30,
        Max = 400,
        Default = settings.aimbotFOV,
        Precision = 0,
        Callback = function(val)
            settings.aimbotFOV = val
            if fovCircle then fovCircle.Radius = val end
        end
    })

    CombatTab:Slider({
        Name = "Smoothness Speed",
        Min = 0.05,
        Max = 0.8,
        Default = settings.aimbotSmoothness,
        Precision = 2,
        Callback = function(val)
            settings.aimbotSmoothness = val
        end
    })

    CombatTab:Toggle({
        Name = "Show FOV Circle",
        Default = settings.aimbotShowFOV,
        Callback = function(val)
            settings.aimbotShowFOV = val
        end
    })

    ---------------------------------------------------------------------------
    -- Visuals Tab Elements
    ---------------------------------------------------------------------------
    VisualsTab:Section({ Title = "Entity ESP" })

    VisualsTab:Toggle({
        Name = "Player ESP",
        Default = settings.espPlayers,
        Callback = function(val)
            settings.espPlayers = val
            if not val then clearESPByTag("player") end
        end
    })

    VisualsTab:Toggle({
        Name = "Zombie ESP",
        Default = settings.espZombies,
        Callback = function(val)
            settings.espZombies = val
            if not val then clearESPByTag("zombie") end
        end
    })

    VisualsTab:Toggle({
        Name = "Ground Items / Loot ESP",
        Default = settings.espGroundItems,
        Callback = function(val)
            settings.espGroundItems = val
            if not val then clearESPByTag("item") end
        end
    })

    VisualsTab:Toggle({
        Name = "Vehicles ESP",
        Default = settings.espVehicles,
        Callback = function(val)
            settings.espVehicles = val
            if not val then clearESPByTag("vehicle") end
        end
    })

    VisualsTab:Toggle({
        Name = "Player Corpses ESP",
        Default = settings.espCorpses,
        Callback = function(val)
            settings.espCorpses = val
            if not val then clearESPByTag("corpse") end
        end
    })

    VisualsTab:Section({ Title = "Display Details" })

    VisualsTab:Toggle({
        Name = "Show Distance",
        Default = settings.espShowDistance,
        Callback = function(val)
            settings.espShowDistance = val
        end
    })

    VisualsTab:Toggle({
        Name = "Show Health (HP)",
        Default = settings.espShowHealth,
        Callback = function(val)
            settings.espShowHealth = val
        end
    })

    VisualsTab:Slider({
        Name = "Max ESP Distance",
        Min = 100,
        Max = 1500,
        Default = settings.espMaxDistance,
        Precision = 0,
        Callback = function(val)
            settings.espMaxDistance = val
        end
    })

    ---------------------------------------------------------------------------
    -- World Tab Elements
    ---------------------------------------------------------------------------
    WorldTab:Section({ Title = "Lighting & Atmosphere" })

    WorldTab:Toggle({
        Name = "FullBright / Night Vision",
        Default = settings.fullBright,
        Callback = function(val)
            settings.fullBright = val
            if not val then restoreLighting() end
        end
    })

    WorldTab:Toggle({
        Name = "No Fog / Clear Vision",
        Default = settings.noFog,
        Callback = function(val)
            settings.noFog = val
            if not val then restoreLighting() end
        end
    })

    WorldTab:Section({ Title = "Quality of Life" })

    WorldTab:Toggle({
        Name = "Instant Proximity Prompt (Instant E)",
        Default = settings.instantPrompt,
        Callback = function(val)
            settings.instantPrompt = val
            if val then hookPrompts() end
        end
    })

    ---------------------------------------------------------------------------
    -- Cleanup on Unload
    ---------------------------------------------------------------------------
    local function cleanup()
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        clearAllESP()
        restoreLighting()
        if fovCircle then
            pcall(function() fovCircle:Remove() end)
        end
    end

    return {
        cleanup = cleanup,
        settings = settings
    }
end
