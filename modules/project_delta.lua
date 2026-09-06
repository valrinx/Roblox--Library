--[[
    RAVEN HUB Module - Project Delta
    Game: Project Delta (PlaceIds: 7336302630, 7353845952, GameId: 2862098693)
    Experience: Project Delta / Estonian Border
    Developer: Vikings Studio

    Features:
    - Player & AI ESP (Highlights, Names, Health, Distance, Faction tags)
    - Loot & Item ESP (Keycards, Keys, Meds, Weapons, Rare Items, Containers)
    - Combat:
        - Silent Aim / Target Lock with customizable FOV Circle
        - Camera Shake Removal / Recoil Stabilizer
        - Target Selection (Head / HumanoidRootPart)
    - Visuals:
        - Built-in Night Vision (NVG Simulation)
        - Fullbright & Fog Removal (UltimateWeather suppression)
        - FOV Changer
    - Survival & QoL:
        - Fast Loot / Proximity Auto Pickup (Keys, Meds, Valuables)
        - WalkSpeed Booster & Infinite Jump
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Lighting = game:GetService("Lighting")
    local TweenService = game:GetService("TweenService")

    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    local running = true
    local connections = {}
    local espObjects = {}

    -- Settings State
    local settings = {
        -- Combat
        aimbot = false,
        aimbotFOV = 120,
        aimbotTarget = "Head", -- "Head" or "HumanoidRootPart"
        aimbotTeamCheck = false,
        noRecoil = true,
        noCamShake = true,

        -- Visuals: Players & AI
        espPlayers = true,
        espAI = true,
        espShowHealth = true,
        espShowDistance = true,
        espShowFaction = true,
        espMaxDistance = 1500,

        -- Visuals: Loot & Items
        espItems = true,
        espKeysOnly = false,
        espContainers = true,
        itemMaxDistance = 300,

        -- Visuals: World
        nightVision = false,
        fullbright = false,
        noFog = true,
        customFOV = false,
        fovValue = 90,

        -- Survival & Misc
        fastLoot = false,
        lootRange = 25,
        customSpeed = false,
        walkSpeed = 16,
        infiniteJump = false,
    }

    -- Clean connection helper
    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    ---------------------------------------------------------------------------
    -- Lighting & Weather Original Cache
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
    -- FOV Circle for Aimbot
    ---------------------------------------------------------------------------
    local fovCircle = nil
    if Drawing and type(Drawing.new) == "function" then
        pcall(function()
            fovCircle = Drawing.new("Circle")
            fovCircle.Thickness = 1.5
            fovCircle.NumSides = 36
            fovCircle.Radius = settings.aimbotFOV
            fovCircle.Filled = false
            fovCircle.Color = Color3.fromRGB(255, 60, 60)
            fovCircle.Transparency = 0.75
            fovCircle.Visible = false
        end)
    end

    ---------------------------------------------------------------------------
    -- Utility Functions
    ---------------------------------------------------------------------------
    local function getRoot(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("UpperTorso")
            or model.PrimaryPart
    end

    local function getHumanoid(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    local function getDistance(pos)
        local char = LP.Character
        local root = getRoot(char)
        if not root or not pos then return 99999 end
        return (root.Position - pos).Magnitude
    end

    ---------------------------------------------------------------------------
    -- High-Performance ESP System
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
            bbPart = inst:FindFirstChild("Head") or inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
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
            billboard.Size = UDim2.new(0, 160, 0, 36)
            billboard.StudsOffset = Vector3.new(0, 2.8, 0)
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 2500
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
            subLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
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
    -- ESP Updaters
    ---------------------------------------------------------------------------
    local valuableKeywords = {
        "card", "key", "ticket", "battery", "nvg", "thermal", "military",
        "rifle", "ammo", "med", "ai2", "bandage", "morphine"
    }

    local function isValuableItem(name)
        local n = string.lower(name)
        for _, kw in ipairs(valuableKeywords) do
            if string.find(n, kw) then return true end
        end
        return false
    end

    local function updateESP()
        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        local myPos = myRoot and myRoot.Position or Vector3.zero

        -- 1. Character ESP (Players & AI)
        for _, model in ipairs(workspace:GetChildren()) do
            if model:IsA("Model") and model ~= myChar then
                local hum = model:FindFirstChildOfClass("Humanoid")
                local root = getRoot(model)

                if hum and root and hum.Health > 0 then
                    local player = Players:GetPlayerFromCharacter(model)
                    local dist = (root.Position - myPos).Magnitude

                    if dist <= settings.espMaxDistance then
                        local isPlayer = (player ~= nil)
                        local shouldShow = (isPlayer and settings.espPlayers) or (not isPlayer and settings.espAI)

                        if shouldShow then
                            local tag = isPlayer and "player" or "ai"
                            local faction = model:GetAttribute("Faction") or (isPlayer and "Player" or "Scav/AI")
                            local color = isPlayer and Color3.fromRGB(70, 160, 255) or Color3.fromRGB(255, 90, 90)

                            if not espObjects[model] then
                                local nameText = isPlayer and (player.DisplayName .. " (@" .. player.Name .. ")") or model.Name
                                createESP(model, color, nameText, true, tag)
                            end

                            local data = espObjects[model]
                            if data and data.subLabel then
                                local subParts = {}
                                if settings.espShowDistance then
                                    table.insert(subParts, math.floor(dist) .. "m")
                                end
                                if settings.espShowHealth then
                                    table.insert(subParts, "HP: " .. math.floor(hum.Health))
                                end
                                if settings.espShowFaction and faction then
                                    table.insert(subParts, "[" .. tostring(faction) .. "]")
                                end
                                data.subLabel.Text = table.concat(subParts, " | ")
                            end
                        else
                            if espObjects[model] then removeESP(model) end
                        end
                    else
                        if espObjects[model] then removeESP(model) end
                    end
                else
                    if espObjects[model] then removeESP(model) end
                end
            end
        end

        -- Clean up dead characters
        for inst, data in pairs(espObjects) do
            if data.tag == "player" or data.tag == "ai" then
                if not inst.Parent or not inst:FindFirstChildOfClass("Humanoid") then
                    removeESP(inst)
                end
            end
        end

        -- 2. Loot & Dropped Items ESP
        local droppedFolder = workspace:FindFirstChild("DroppedItems")
        if settings.espItems and droppedFolder then
            for _, item in ipairs(droppedFolder:GetChildren()) do
                local pos = item:IsA("BasePart") and item.Position or (item:FindFirstChildWhichIsA("BasePart") and item:FindFirstChildWhichIsA("BasePart").Position)
                if pos then
                    local dist = (pos - myPos).Magnitude
                    if dist <= settings.itemMaxDistance then
                        local isValuable = isValuableItem(item.Name)
                        local canShow = not settings.espKeysOnly or isValuable

                        if canShow then
                            if not espObjects[item] then
                                local color = isValuable and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(120, 255, 140)
                                createESP(item, color, "📦 " .. item.Name, true, "item")
                            end

                            local data = espObjects[item]
                            if data and data.subLabel then
                                data.subLabel.Text = math.floor(dist) .. "m"
                            end
                        else
                            if espObjects[item] then removeESP(item) end
                        end
                    else
                        if espObjects[item] then removeESP(item) end
                    end
                end
            end
        else
            clearESPByTag("item")
        end

        -- 3. Containers ESP
        local containersFolder = workspace:FindFirstChild("Containers")
        if settings.espContainers and containersFolder then
            for _, container in ipairs(containersFolder:GetChildren()) do
                local pos = container:IsA("BasePart") and container.Position or (container:FindFirstChildWhichIsA("BasePart") and container:FindFirstChildWhichIsA("BasePart").Position)
                if pos then
                    local dist = (pos - myPos).Magnitude
                    if dist <= settings.itemMaxDistance then
                        if not espObjects[container] then
                            createESP(container, Color3.fromRGB(200, 160, 255), "🧰 " .. container.Name, true, "container")
                        end
                        local data = espObjects[container]
                        if data and data.subLabel then
                            data.subLabel.Text = math.floor(dist) .. "m"
                        end
                    else
                        if espObjects[container] then removeESP(container) end
                    end
                end
            end
        else
            clearESPByTag("container")
        end
    end

    ---------------------------------------------------------------------------
    -- Combat & Silent Aim Engine
    ---------------------------------------------------------------------------
    local function getClosestAimTarget()
        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return nil end

        local mousePos = UserInputService:GetMouseLocation()
        local bestTarget = nil
        local bestDist = settings.aimbotFOV

        for _, model in ipairs(workspace:GetChildren()) do
            if model:IsA("Model") and model ~= myChar then
                local hum = model:FindFirstChildOfClass("Humanoid")
                local targetPart = model:FindFirstChild(settings.aimbotTarget) or getRoot(model)

                if hum and hum.Health > 0 and targetPart then
                    local player = Players:GetPlayerFromCharacter(model)
                    local isEnemy = true

                    if settings.aimbotTeamCheck and player then
                        local myFaction = myChar:GetAttribute("Faction")
                        local theirFaction = model:GetAttribute("Faction")
                        if myFaction and theirFaction and myFaction == theirFaction then
                            isEnemy = false
                        end
                    end

                    if isEnemy then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                        if onScreen then
                            local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                            if screenDist < bestDist then
                                bestDist = screenDist
                                bestTarget = targetPart
                            end
                        end
                    end
                end
            end
        end

        return bestTarget
    end

    -- Hook CameraShaker to eliminate weapon recoil shaking
    local CameraShaker = nil
    pcall(function()
        CameraShaker = require(ReplicatedStorage.Modules.CameraShaker)
        if CameraShaker and type(CameraShaker.Shake) == "function" then
            local origShake = CameraShaker.Shake
            CameraShaker.Shake = function(self, ...)
                if settings.noCamShake then return end
                return origShake(self, ...)
            end
        end
        if CameraShaker and type(CameraShaker.ShakeOnce) == "function" then
            local origShakeOnce = CameraShaker.ShakeOnce
            CameraShaker.ShakeOnce = function(self, ...)
                if settings.noCamShake then return end
                return origShakeOnce(self, ...)
            end
        end
    end)

    ---------------------------------------------------------------------------
    -- Fast Proximity Loot / Auto Pickup
    ---------------------------------------------------------------------------
    local lastLootTime = 0
    local function processFastLoot()
        if not settings.fastLoot or (os.clock() - lastLootTime) < 0.25 then return end
        lastLootTime = os.clock()

        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return end

        local droppedFolder = workspace:FindFirstChild("DroppedItems")
        local takeRemote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Take")
        if not droppedFolder or not takeRemote then return end

        for _, item in ipairs(droppedFolder:GetChildren()) do
            local pos = item:IsA("BasePart") and item.Position or (item:FindFirstChildWhichIsA("BasePart") and item:FindFirstChildWhichIsA("BasePart").Position)
            if pos and (myRoot.Position - pos).Magnitude <= settings.lootRange then
                pcall(function()
                    takeRemote:FireServer(item)
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    -- Visual Modifications (Night Vision, Fullbright, Weather)
    ---------------------------------------------------------------------------
    local function applyVisualModifiers()
        if settings.nightVision then
            Lighting.ExposureCompensation = 3.2
            Lighting.Brightness = 2.5
            Lighting.OutdoorAmbient = Color3.fromRGB(150, 180, 150)
        elseif settings.fullbright then
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
            Lighting.ExposureCompensation = 0.5
        else
            Lighting.Brightness = origLighting.Brightness
            Lighting.ClockTime = origLighting.ClockTime
            Lighting.FogEnd = origLighting.FogEnd
            Lighting.GlobalShadows = origLighting.GlobalShadows
            Lighting.OutdoorAmbient = origLighting.OutdoorAmbient
            Lighting.ExposureCompensation = origLighting.ExposureCompensation
        end

        if settings.noFog then
            Lighting.FogEnd = 100000
            for _, child in ipairs(Lighting:GetChildren()) do
                if child:IsA("Atmosphere") then
                    child.Density = 0
                    child.Haze = 0
                end
            end
        end

        if settings.customFOV then
            Camera.FieldOfView = settings.fovValue
        end
    end

    ---------------------------------------------------------------------------
    -- Main Update Loops
    ---------------------------------------------------------------------------
    connect(RunService.RenderStepped, function()
        if not running then return end

        -- Update FOV circle position & visibility
        if fovCircle then
            fovCircle.Visible = settings.aimbot
            fovCircle.Radius = settings.aimbotFOV
            fovCircle.Position = UserInputService:GetMouseLocation()
        end

        -- Smooth Aimbot Tracking
        if settings.aimbot and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            local targetPart = getClosestAimTarget()
            if targetPart then
                local targetPos = targetPart.Position
                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, targetPos)
            end
        end

        -- Visual modifications
        applyVisualModifiers()
    end)

    local espTimer = 0
    connect(RunService.Heartbeat, function(dt)
        if not running then return end

        -- Heartbeat ESP updater (every 0.08s for maximum smooth FPS)
        espTimer = espTimer + dt
        if espTimer >= 0.08 then
            espTimer = 0
            updateESP()
        end

        -- Fast loot processor
        if settings.fastLoot then
            processFastLoot()
        end

        -- Movement tweaks
        local char = LP.Character
        local hum = getHumanoid(char)
        if hum then
            if settings.customSpeed and hum.WalkSpeed ~= settings.walkSpeed then
                hum.WalkSpeed = settings.walkSpeed
            end
        end
    end)

    -- Infinite Jump Handler
    connect(UserInputService.JumpRequest, function()
        if not running or not settings.infiniteJump then return end
        local char = LP.Character
        local hum = getHumanoid(char)
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)

    ---------------------------------------------------------------------------
    -- User Interface (MacLib / MacLib Adapter Standard)
    ---------------------------------------------------------------------------

    -- Tab 1: Combat
    local CombatTab = Window:CreateTab("Combat", 4483362458)
    CombatTab:CreateSection("Target Assistance & Aimbot")

    CombatTab:CreateToggle({
        Name = "Enable Aimbot (Hold Right Click)",
        CurrentValue = settings.aimbot,
        Flag = "Delta_Aimbot",
        Callback = function(value)
            settings.aimbot = value
        end,
    })

    CombatTab:CreateDropdown({
        Name = "Target Bone",
        Options = {"Head", "HumanoidRootPart"},
        CurrentOption = settings.aimbotTarget,
        Flag = "Delta_AimTarget",
        Callback = function(option)
            settings.aimbotTarget = option
        end,
    })

    CombatTab:CreateSlider({
        Name = "Aimbot FOV Radius",
        Range = {30, 400},
        Increment = 5,
        CurrentValue = settings.aimbotFOV,
        Flag = "Delta_AimFOV",
        Callback = function(value)
            settings.aimbotFOV = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Faction / Team Check",
        CurrentValue = settings.aimbotTeamCheck,
        Flag = "Delta_TeamCheck",
        Callback = function(value)
            settings.aimbotTeamCheck = value
        end,
    })

    CombatTab:CreateSection("Recoil & Stabilization")

    CombatTab:CreateToggle({
        Name = "No Camera Shake (Suppression / Shake Removal)",
        CurrentValue = settings.noCamShake,
        Flag = "Delta_NoShake",
        Callback = function(value)
            settings.noCamShake = value
        end,
    })

    -- Tab 2: Visuals & ESP
    local VisualTab = Window:CreateTab("Visuals", 4483362458)
    VisualTab:CreateSection("Player & AI ESP")

    VisualTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = settings.espPlayers,
        Flag = "Delta_PlayerESP",
        Callback = function(value)
            settings.espPlayers = value
            if not value then clearESPByTag("player") end
        end,
    })

    VisualTab:CreateToggle({
        Name = "AI / Scav ESP",
        CurrentValue = settings.espAI,
        Flag = "Delta_AIESP",
        Callback = function(value)
            settings.espAI = value
            if not value then clearESPByTag("ai") end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = settings.espShowDistance,
        Flag = "Delta_ShowDist",
        Callback = function(value)
            settings.espShowDistance = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Show Health & Faction",
        CurrentValue = settings.espShowHealth,
        Flag = "Delta_ShowHP",
        Callback = function(value)
            settings.espShowHealth = value
            settings.espShowFaction = value
        end,
    })

    VisualTab:CreateSlider({
        Name = "Entity ESP Max Distance",
        Range = {100, 3000},
        Increment = 50,
        CurrentValue = settings.espMaxDistance,
        Flag = "Delta_ESPMaxDist",
        Callback = function(value)
            settings.espMaxDistance = value
        end,
    })

    VisualTab:CreateSection("Loot & Item ESP")

    VisualTab:CreateToggle({
        Name = "Loot Items ESP",
        CurrentValue = settings.espItems,
        Flag = "Delta_ItemESP",
        Callback = function(value)
            settings.espItems = value
            if not value then clearESPByTag("item") end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Valuables & Keys Only",
        CurrentValue = settings.espKeysOnly,
        Flag = "Delta_KeysOnly",
        Callback = function(value)
            settings.espKeysOnly = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Containers & Crates ESP",
        CurrentValue = settings.espContainers,
        Flag = "Delta_ContainerESP",
        Callback = function(value)
            settings.espContainers = value
            if not value then clearESPByTag("container") end
        end,
    })

    VisualTab:CreateSlider({
        Name = "Loot ESP Max Distance",
        Range = {50, 1000},
        Increment = 25,
        CurrentValue = settings.itemMaxDistance,
        Flag = "Delta_LootMaxDist",
        Callback = function(value)
            settings.itemMaxDistance = value
        end,
    })

    VisualTab:CreateSection("World & Lighting")

    VisualTab:CreateToggle({
        Name = "Night Vision (Built-in NVG)",
        CurrentValue = settings.nightVision,
        Flag = "Delta_NVG",
        Callback = function(value)
            settings.nightVision = value
            applyVisualModifiers()
        end,
    })

    VisualTab:CreateToggle({
        Name = "Fullbright (No Shadows)",
        CurrentValue = settings.fullbright,
        Flag = "Delta_Fullbright",
        Callback = function(value)
            settings.fullbright = value
            applyVisualModifiers()
        end,
    })

    VisualTab:CreateToggle({
        Name = "Remove Fog / Atmospheric Haze",
        CurrentValue = settings.noFog,
        Flag = "Delta_NoFog",
        Callback = function(value)
            settings.noFog = value
            applyVisualModifiers()
        end,
    })

    VisualTab:CreateSlider({
        Name = "Field Of View (FOV)",
        Range = {60, 120},
        Increment = 1,
        CurrentValue = settings.fovValue,
        Flag = "Delta_FOVVal",
        Callback = function(value)
            settings.fovValue = value
            settings.customFOV = true
            Camera.FieldOfView = value
        end,
    })

    -- Tab 3: Survival & Movement
    local SurvivalTab = Window:CreateTab("Survival", 4483362458)
    SurvivalTab:CreateSection("Fast Looting")

    SurvivalTab:CreateToggle({
        Name = "Auto Fast Pickup Nearby Items",
        CurrentValue = settings.fastLoot,
        Flag = "Delta_FastLoot",
        Callback = function(value)
            settings.fastLoot = value
        end,
    })

    SurvivalTab:CreateSlider({
        Name = "Pickup Range (Studs)",
        Range = {5, 50},
        Increment = 1,
        CurrentValue = settings.lootRange,
        Flag = "Delta_LootRange",
        Callback = function(value)
            settings.lootRange = value
        end,
    })

    SurvivalTab:CreateSection("Movement Utilities")

    SurvivalTab:CreateToggle({
        Name = "Custom WalkSpeed",
        CurrentValue = settings.customSpeed,
        Flag = "Delta_CustomSpeed",
        Callback = function(value)
            settings.customSpeed = value
            if not value then
                local char = LP.Character
                local hum = getHumanoid(char)
                if hum then hum.WalkSpeed = 9 end
            end
        end,
    })

    SurvivalTab:CreateSlider({
        Name = "WalkSpeed Value",
        Range = {9, 50},
        Increment = 1,
        CurrentValue = settings.walkSpeed,
        Flag = "Delta_SpeedValue",
        Callback = function(value)
            settings.walkSpeed = value
            if settings.customSpeed then
                local char = LP.Character
                local hum = getHumanoid(char)
                if hum then hum.WalkSpeed = value end
            end
        end,
    })

    SurvivalTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = settings.infiniteJump,
        Flag = "Delta_InfJump",
        Callback = function(value)
            settings.infiniteJump = value
        end,
    })

    ---------------------------------------------------------------------------
    -- Cleanup on Unload
    ---------------------------------------------------------------------------
    local function cleanup()
        running = false
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        clearAllESP()
        if fovCircle then
            pcall(function() fovCircle:Remove() end)
        end
        -- Restore lighting
        Lighting.Brightness = origLighting.Brightness
        Lighting.ClockTime = origLighting.ClockTime
        Lighting.FogEnd = origLighting.FogEnd
        Lighting.GlobalShadows = origLighting.GlobalShadows
        Lighting.OutdoorAmbient = origLighting.OutdoorAmbient
        Lighting.ExposureCompensation = origLighting.ExposureCompensation
    end

    return {
        cleanup = cleanup,
        settings = settings
    }
end
