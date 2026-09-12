-- ===========================================================================
-- RAVEN HUB | Desolate Valley Module
-- Game: Desolate Valley / Derelict (PlaceId: 11574110446, Universe: 3615728730)
-- Architecture: Safe Client-Side Visuals, Entity & Forageable ESP, Mob Aimbot,
-- Fast Travel / Waypoints, and Environmental Utilities
-- ===========================================================================

return function(Window, scriptInfo)
    -- Clean previous running instances of Desolate Valley module
    pcall(function()
        local prev = getgenv().__RAVEN_DESOLATE_VALLEY
        if prev and type(prev.Destroy) == "function" then
            prev.Destroy()
        end
    end)

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")

    local LP = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- Connection & instance tracking
    local connections = {}
    local espObjects = {}
    local rightMouseDown = false

    local function trackConnection(conn)
        table.insert(connections, conn)
        return conn
    end

    -- Track RMB input reliably (Cold War Standard)
    trackConnection(UserInputService.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2
            and UserInputService:GetFocusedTextBox() == nil then
            rightMouseDown = true
        end
    end))

    trackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            rightMouseDown = false
        end
    end))

    ---------------------------------------------------------------------------
    -- Settings State
    ---------------------------------------------------------------------------
    local settings = {
        -- Forageable & Item ESP
        espForageables = true,
        forageMaxDist = 1200,
        forageShowDist = true,
        forageFilterType = "All", -- "All", "Mushroom", "Onion", "Thyme"

        -- Mob & Boss ESP
        espMobs = true,
        mobMaxDist = 1500,
        mobShowDist = true,
        mobShowHealth = true,

        -- NPC & Shop ESP
        espNPCs = true,
        npcMaxDist = 2000,
        npcShowDist = true,

        -- Other Players ESP
        espPlayers = true,
        playerMaxDist = 1800,
        playerShowDist = true,
        playerShowHealth = true,

        -- Wall Check & Visibility
        wallCheck = true,
        colorVisible = Color3.fromRGB(255, 50, 50),     -- Red when shootable/visible
        colorBehindWall = Color3.fromRGB(50, 235, 90),  -- Green when behind wall

        -- Mob Combat & Aimbot
        aimbotEnabled = false,
        aimbotActivation = "Right Mouse", -- "Right Mouse" or "Always"
        aimbotTarget = "Head", -- "Head", "HumanoidRootPart"
        aimbotFOV = 220,
        aimbotSmoothness = 0.25,
        aimbotShowFOV = true,

        -- Mob Hitbox Expander & Reach
        hitboxExpander = false,
        hitboxSize = 14,

        -- Forage Automation
        autoCollect = false,
        autoCollectRange = 35,

        -- Movement & Utilities
        infStamina = false,
        noClip = false,
        fullBright = false,
        noFog = false,
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
    -- Static Waypoints for Fast Travel
    ---------------------------------------------------------------------------
    local WAYPOINTS = {
        ["Wilhelm (Hub NPC)"] = Vector3.new(340, -120, 258),
        ["Gideon (Soul Blacksmith)"] = Vector3.new(343, -119, 306),
        ["Wilhelm (Distant Camp)"] = Vector3.new(-756, -116, 492),
        ["Dungeon Gate (Basin)"] = Vector3.new(11, -61, 256),
        ["Dungeon Gate (Mountain)"] = Vector3.new(-108, 47, -364),
        ["Dungeon Exit Portal"] = Vector3.new(-667, -137, 246),
        ["Basin Safe Center"] = Vector3.new(133, -135, 424),
    }

    ---------------------------------------------------------------------------
    -- Entity Helpers
    ---------------------------------------------------------------------------
    local function getRoot(model)
        if not model then return nil end
        if model:IsA("BasePart") then return model end
        if not model:IsA("Model") then return nil end

        return model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("RootPart")
            or model:FindFirstChild("Torso")
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Head")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart")
    end

    local function getHumanoid(model)
        if not model or not model:IsA("Model") then return nil end
        return model:FindFirstChildOfClass("Humanoid")
    end

    local function getInstancedGeometry()
        return Workspace:FindFirstChild("InstancedGeometry")
    end

    ---------------------------------------------------------------------------
    -- Wall Check (Multi-pass Raycast)
    ---------------------------------------------------------------------------
    local MAX_VISION_PASSTHROUGHS = 4

    local function isVisionTransparent(instance)
        if not instance or not instance:IsA("BasePart") then return false end
        return instance.Transparency >= 0.25 or instance.CanCollide == false
    end

    local function isPartVisible(targetPart, targetModel)
        if not targetPart or not targetPart:IsA("BasePart") then return false end
        local camPos = Camera.CFrame.Position
        local targetPos = targetPart.Position
        local direction = targetPos - camPos
        if direction.Magnitude < 0.5 then return true end

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.IgnoreWater = true

        local baseIgnore = {}
        if LP.Character then table.insert(baseIgnore, LP.Character) end
        for _, name in ipairs({"Ignore", "Effects", "Debris", "VFX"}) do
            local f = Workspace:FindFirstChild(name)
            if f then table.insert(baseIgnore, f) end
        end

        local currentIgnore = table.clone(baseIgnore)
        local reachesTarget = false

        for _ = 1, MAX_VISION_PASSTHROUGHS do
            rayParams.FilterDescendantsInstances = currentIgnore
            local result = Workspace:Raycast(camPos, direction, rayParams)
            if not result then
                reachesTarget = true
                break
            end

            if result.Instance == targetPart
                or (targetModel ~= nil and result.Instance:IsDescendantOf(targetModel)) then
                reachesTarget = true
                break
            end

            if not isVisionTransparent(result.Instance) then
                break
            end

            table.insert(currentIgnore, result.Instance)
        end

        return reachesTarget
    end

    ---------------------------------------------------------------------------
    -- Billboard ESP Rendering
    ---------------------------------------------------------------------------
    local function createESP(inst, color, title, isModel, tag)
        if espObjects[inst] then return end

        local highlight = nil
        pcall(function()
            highlight = Instance.new("Highlight")
            highlight.FillColor = color
            highlight.OutlineColor = Color3.new(1, 1, 1)
            highlight.FillTransparency = 0.65
            highlight.OutlineTransparency = 0.25
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Adornee = inst
            highlight.Parent = inst
        end)

        local bbPart = inst
        if isModel then
            bbPart = getRoot(inst)
        end

        local billboard = nil
        local titleLabel = nil
        local subLabel = nil

        if bbPart and bbPart:IsA("BasePart") then
            billboard = Instance.new("BillboardGui")
            billboard.Name = "RAVEN_ESP"
            billboard.Size = UDim2.new(0, 220, 0, 50)
            billboard.StudsOffset = Vector3.new(0, 3.5, 0)
            billboard.AlwaysOnTop = true
            billboard.MaxDistance = 2500
            billboard.Adornee = bbPart
            pcall(function() billboard.Parent = bbPart end)

            local layout = Instance.new("UIListLayout")
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            layout.VerticalAlignment = Enum.VerticalAlignment.Center
            layout.Padding = UDim.new(0, 2)
            layout.Parent = billboard

            titleLabel = Instance.new("TextLabel")
            titleLabel.Name = "Title"
            titleLabel.Text = title
            titleLabel.Font = Enum.Font.GothamBold
            titleLabel.TextSize = 13
            titleLabel.TextColor3 = color
            titleLabel.TextStrokeTransparency = 0.15
            titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            titleLabel.BackgroundTransparency = 1
            titleLabel.Size = UDim2.new(1, 0, 0, 18)
            titleLabel.LayoutOrder = 1
            titleLabel.Parent = billboard

            subLabel = Instance.new("TextLabel")
            subLabel.Name = "Sub"
            subLabel.Text = ""
            subLabel.Font = Enum.Font.GothamMedium
            subLabel.TextSize = 11
            subLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
            subLabel.TextStrokeTransparency = 0.2
            subLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            subLabel.BackgroundTransparency = 1
            subLabel.Size = UDim2.new(1, 0, 0, 16)
            subLabel.LayoutOrder = 2
            subLabel.Parent = billboard
        end

        espObjects[inst] = {
            highlight = highlight,
            billboard = billboard,
            titleLabel = titleLabel,
            subLabel = subLabel,
            tag = tag,
            color = color,
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
        for inst, data in pairs(espObjects) do
            if data.tag == tag then
                removeESP(inst)
            end
        end
    end

    local function clearAllESP()
        for inst in pairs(espObjects) do
            removeESP(inst)
        end
    end

    ---------------------------------------------------------------------------
    -- Active Entity Finders
    ---------------------------------------------------------------------------
    local function getActivePlayers()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and p.Character then
                local hum = getHumanoid(p.Character)
                local root = getRoot(p.Character)
                if root and hum and hum.Health > 0 then
                    table.insert(list, {
                        player = p,
                        model = p.Character,
                        root = root,
                        hum = hum,
                    })
                end
            end
        end
        return list
    end

    local KNOWN_NPCS = {
        ["Wilhelm"] = true,
        ["Gideon"] = true,
        ["Baldwin"] = true,
        ["Clara"] = true,
        ["FeedingMerchant"] = true,
        ["TravellingMerchant"] = true,
        ["SoulRemnantBlacksmith"] = true,
    }

    local function getActiveMobsAndNPCs()
        local ig = getInstancedGeometry()
        local mobs = {}
        local npcs = {}

        if ig and ig:FindFirstChild("Humanoids") then
            for _, ch in ipairs(ig.Humanoids:GetChildren()) do
                if ch:IsA("Model") and not Players:GetPlayerFromCharacter(ch) then
                    local ref = ch:GetAttribute("RefModel") or ch.Name
                    local hum = getHumanoid(ch)
                    local root = getRoot(ch)

                    if KNOWN_NPCS[ref] or KNOWN_NPCS[ch.Name] then
                        table.insert(npcs, {
                            model = ch,
                            name = ref,
                            root = root,
                        })
                    else
                        -- Hostile mob / monster
                        local health = hum and hum.Health or 100
                        local isDead = ch:GetAttribute("Dead") == true or health <= 0
                        if not isDead then
                            table.insert(mobs, {
                                model = ch,
                                name = ref,
                                root = root,
                                hum = hum,
                                health = health,
                                maxHealth = hum and hum.MaxHealth or 100,
                            })
                        end
                    end
                end
            end
        end

        return mobs, npcs
    end

    local function getActiveForageables()
        local ig = getInstancedGeometry()
        local list = {}
        if ig and ig:FindFirstChild("Interactables") then
            for _, ch in ipairs(ig.Interactables:GetChildren()) do
                if ch.Name == "Forageable" or ch.Name == "PickItem" then
                    local fType = ch:GetAttribute("Type") or (ch.Name == "PickItem" and "Loot Item" or "Forage")
                    local active = ch:GetAttribute("Active")
                    if active == nil or active == true or active == "true" then
                        table.insert(list, {
                            instance = ch,
                            fType = fType,
                            name = ch.Name == "PickItem" and "💎 PickItem" or ("🌿 " .. fType),
                        })
                    end
                end
            end
        end
        return list
    end

    ---------------------------------------------------------------------------
    -- ESP Update Loop
    ---------------------------------------------------------------------------
    local function updateESP()
        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return end
        local myPos = myRoot.Position

        -- 1. Forageable & Item ESP
        if settings.espForageables then
            for _, item in ipairs(getActiveForageables()) do
                local inst = item.instance
                local pos = inst:IsA("BasePart") and inst.Position or (getRoot(inst) and getRoot(inst).Position)
                if pos then
                    local dist = (pos - myPos).Magnitude
                    local typeMatch = (settings.forageFilterType == "All")
                        or (settings.forageFilterType == "Mushroom" and item.fType:find("Mushroom"))
                        or (settings.forageFilterType == "Onion" and item.fType:find("Onion"))
                        or (settings.forageFilterType == "Thyme" and item.fType:find("Thyme"))

                    if dist <= settings.forageMaxDist and typeMatch then
                        if not espObjects[inst] then
                            createESP(inst, Color3.fromRGB(240, 195, 75), item.name, inst:IsA("Model"), "forage")
                        end
                        local data = espObjects[inst]
                        if data and data.subLabel then
                            data.subLabel.Text = settings.forageShowDist and (math.floor(dist) .. "m") or ""
                        end
                    else
                        if espObjects[inst] then removeESP(inst) end
                    end
                end
            end
        else
            clearESPByTag("forage")
        end

        -- 2. Mobs and NPCs ESP
        local activeMobs, activeNPCs = getActiveMobsAndNPCs()

        if settings.espMobs then
            for _, mob in ipairs(activeMobs) do
                local root = mob.root
                if root then
                    local dist = (root.Position - myPos).Magnitude
                    if dist <= settings.mobMaxDist then
                        local isVisible = false
                        if settings.wallCheck then
                            isVisible = isPartVisible(root, mob.model)
                        end
                        local targetColor = (settings.wallCheck and (isVisible and settings.colorVisible or settings.colorBehindWall))
                            or Color3.fromRGB(245, 75, 75)

                        if not espObjects[mob.model] then
                            createESP(mob.model, targetColor, "👹 " .. mob.name, true, "mob")
                        end
                        local data = espObjects[mob.model]
                        if data then
                            if data.highlight and data.highlight.FillColor ~= targetColor then
                                data.highlight.FillColor = targetColor
                            end
                            if data.titleLabel and data.titleLabel.TextColor3 ~= targetColor then
                                data.titleLabel.TextColor3 = targetColor
                            end
                            if data.subLabel then
                                local parts = {}
                                if settings.mobShowDist then table.insert(parts, math.floor(dist) .. "m") end
                                if settings.mobShowHealth then table.insert(parts, "HP: " .. math.floor(mob.health)) end
                                if isVisible then table.insert(parts, "[VIS]") end
                                data.subLabel.Text = table.concat(parts, " | ")
                            end
                        end
                    else
                        if espObjects[mob.model] then removeESP(mob.model) end
                    end
                end
            end
        else
            clearESPByTag("mob")
        end

        if settings.espNPCs then
            for _, npc in ipairs(activeNPCs) do
                local root = npc.root
                if root then
                    local dist = (root.Position - myPos).Magnitude
                    if dist <= settings.npcMaxDist then
                        if not espObjects[npc.model] then
                            createESP(npc.model, Color3.fromRGB(60, 180, 255), "💬 " .. npc.name, true, "npc")
                        end
                        local data = espObjects[npc.model]
                        if data and data.subLabel then
                            data.subLabel.Text = settings.npcShowDist and (math.floor(dist) .. "m") or ""
                        end
                    else
                        if espObjects[npc.model] then removeESP(npc.model) end
                    end
                end
            end
        else
            clearESPByTag("npc")
        end

        -- 3. Player ESP
        if settings.espPlayers then
            for _, p in ipairs(getActivePlayers()) do
                local dist = (p.root.Position - myPos).Magnitude
                if dist <= settings.playerMaxDist then
                    if not espObjects[p.model] then
                        createESP(p.model, Color3.fromRGB(0, 230, 210), "👤 " .. p.player.DisplayName, true, "player")
                    end
                    local data = espObjects[p.model]
                    if data and data.subLabel then
                        local parts = {}
                        if settings.playerShowDist then table.insert(parts, math.floor(dist) .. "m") end
                        if settings.playerShowHealth then table.insert(parts, "HP: " .. math.floor(p.hum.Health)) end
                        data.subLabel.Text = table.concat(parts, " | ")
                    end
                else
                    if espObjects[p.model] then removeESP(p.model) end
                end
            end
        else
            clearESPByTag("player")
        end
    end

    ---------------------------------------------------------------------------
    -- Drawing Visuals & Mob Aimbot
    ---------------------------------------------------------------------------
    local fovCircle = nil
    pcall(function()
        fovCircle = Drawing.new("Circle")
        fovCircle.Thickness = 1.5
        fovCircle.NumSides = 36
        fovCircle.Filled = false
        fovCircle.Transparency = 0.8
        fovCircle.Color = Color3.fromRGB(245, 180, 50)
        fovCircle.Visible = false
    end)

    local function getClosestAimTarget()
        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return nil end

        local mousePos = UserInputService:GetMouseLocation()
        local centerPos = Camera.ViewportSize * 0.5
        local bestTargetPart = nil
        local bestDist = settings.aimbotFOV

        local activeMobs = getActiveMobsAndNPCs()
        for _, mob in ipairs(activeMobs) do
            local part = mob.model:FindFirstChild(settings.aimbotTarget) or mob.root
            if part and part:IsA("BasePart") then
                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen and screenPos.Z > 0 then
                    local target2D = Vector2.new(screenPos.X, screenPos.Y)
                    local distToMouse = (target2D - mousePos).Magnitude
                    local distToCenter = (target2D - centerPos).Magnitude
                    local effectiveDist = math.min(distToMouse, distToCenter)

                    if effectiveDist < bestDist then
                        bestDist = effectiveDist
                        bestTargetPart = part
                    end
                end
            end
        end

        return bestTargetPart
    end

    ---------------------------------------------------------------------------
    -- Environment & Lighting Modifiers
    ---------------------------------------------------------------------------
    local function applyLighting()
        if settings.fullBright then
            Lighting.Brightness = 2.5
            Lighting.ClockTime = 14
            Lighting.OutdoorAmbient = Color3.fromRGB(160, 160, 160)
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
    -- Infinite Stamina Implementation (ClientHumanoid.Stats Instance Hook)
    ---------------------------------------------------------------------------
    local origStatsDeduct = nil
    local origStatsGet = nil
    local origStatsChange = nil
    local hookedStatsObj = nil

    local function getClientStats()
        if hookedStatsObj and hookedStatsObj.StatContainers then
            return hookedStatsObj
        end
        pcall(function()
            for _, obj in ipairs(getgc(true)) do
                if type(obj) == "table" and rawget(obj, "ClientHumanoid") ~= nil and type(obj.ClientHumanoid) == "table" then
                    hookedStatsObj = obj.ClientHumanoid.Stats
                    break
                end
            end
        end)
        return hookedStatsObj
    end

    local function applyStaminaBypass()
        local stats = getClientStats()
        if not stats then return end

        local maxStamina = 100
        pcall(function() maxStamina = stats:Get("MaxStamina") end)

        if not origStatsChange and type(stats.Change) == "function" then
            origStatsChange = stats.Change
            stats.Change = function(self, statName, delta, ...)
                if settings.infStamina then
                    local sName = tostring(statName)
                    if sName == "ClientLoanStamina" then
                        return
                    end
                    if (sName == "ClientStamina" or sName == "Stamina") and delta and delta < 0 then
                        return
                    end
                end
                return origStatsChange(self, statName, delta, ...)
            end
        end

        if not origStatsDeduct and type(stats.Deduct) == "function" then
            origStatsDeduct = stats.Deduct
            stats.Deduct = function(self, statName, amount, ...)
                if settings.infStamina and tostring(statName) == "Stamina" then
                    return
                end
                return origStatsDeduct(self, statName, amount, ...)
            end
        end

        if not origStatsGet and type(stats.Get) == "function" then
            origStatsGet = stats.Get
            stats.Get = function(self, statName, ...)
                if settings.infStamina and tostring(statName) == "Stamina" then
                    local mx = maxStamina
                    pcall(function() mx = origStatsGet(self, "MaxStamina") end)
                    return mx or 100
                end
                return origStatsGet(self, statName, ...)
            end
        end

        -- Keep containers locked with valid BaseValue & CachedValue
        pcall(function()
            local loan = stats.StatContainers and stats.StatContainers["ClientLoanStamina"]
            if loan then
                loan.BaseValue = 0
                loan.CachedValue = 0
                loan.ContainerValue = 0
            end
            local restore = stats.StatContainers and stats.StatContainers["ClientRestoreStamina"]
            if restore then
                restore.BaseValue = 0
                restore.CachedValue = 0
                restore.ContainerValue = 0
            end
            local cs = stats.StatContainers and stats.StatContainers["ClientStamina"]
            if cs then
                cs.BaseValue = maxStamina
                cs.CachedValue = maxStamina
                cs.ContainerValue = maxStamina
            end
            if stats.Events and stats.Events.StatChanged then
                stats.Events.StatChanged:Fire("Stamina", maxStamina, maxStamina)
            end
        end)
    end

    local function removeStaminaBypass()
        if hookedStatsObj then
            pcall(function()
                if origStatsChange then
                    hookedStatsObj.Change = origStatsChange
                    origStatsChange = nil
                end
                if origStatsDeduct then
                    hookedStatsObj.Deduct = origStatsDeduct
                    origStatsDeduct = nil
                end
                if origStatsGet then
                    hookedStatsObj.Get = origStatsGet
                    origStatsGet = nil
                end
            end)
            hookedStatsObj = nil
        end
    end

    ---------------------------------------------------------------------------
    -- Hitbox Expander Implementation
    ---------------------------------------------------------------------------
    local origHitboxSizes = {}
    local function updateHitboxes()
        local hitboxesFolder = Workspace:FindFirstChild("InstancedGeometry") and Workspace.InstancedGeometry:FindFirstChild("Hitboxes")
        if not hitboxesFolder then return end

        if settings.hitboxExpander then
            local targetSize = Vector3.new(settings.hitboxSize, settings.hitboxSize, settings.hitboxSize)
            for _, box in ipairs(hitboxesFolder:GetChildren()) do
                if box:IsA("BasePart") then
                    if not origHitboxSizes[box] then
                        origHitboxSizes[box] = box.Size
                    end
                    if box.Size ~= targetSize then
                        box.Size = targetSize
                        box.Transparency = 0.75
                    end
                end
            end
        else
            for box, origSize in pairs(origHitboxSizes) do
                if box and box.Parent then
                    box.Size = origSize
                    box.Transparency = 1
                end
            end
            table.clear(origHitboxSizes)
        end
    end

    ---------------------------------------------------------------------------
    -- Auto Collect Forageables Implementation
    ---------------------------------------------------------------------------
    local lastCollectTime = 0
    local function processAutoCollect()
        if not settings.autoCollect then return end
        local now = tick()
        if now - lastCollectTime < 0.35 then return end
        lastCollectTime = now

        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return end

        local nearestForage = nil
        local nearestDist = settings.autoCollectRange

        local forageFolder = Workspace:FindFirstChild("Forageables")
        if forageFolder then
            for _, item in ipairs(forageFolder:GetChildren()) do
                local part = item:IsA("BasePart") and item or item:FindFirstChildWhichIsA("BasePart")
                if part then
                    local dist = (part.Position - myRoot.Position).Magnitude
                    if dist <= nearestDist then
                        nearestDist = dist
                        nearestForage = item
                    end
                end
            end
        end

        if nearestForage then
            pcall(function()
                local im = getgenv().__RAVEN_INTERACT_MOD
                if not im then
                    local rep = game:GetService("ReplicatedStorage")
                    local mod = rep:FindFirstChild("Modules") and rep.Modules:FindFirstChild("InteractModule")
                    if mod then
                        im = require(mod)
                        getgenv().__RAVEN_INTERACT_MOD = im
                    end
                end
                if im and im.Interactables and im.Interactables[nearestForage] then
                    local action = im.Interactables[nearestForage].Actions and im.Interactables[nearestForage].Actions[1]
                    if action and type(action.Callback) == "function" then
                        action.Callback()
                        return
                    end
                end

                local vim = game:GetService("VirtualInputManager")
                if vim then
                    vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.05)
                    vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end
            end)
        end
    end

    ---------------------------------------------------------------------------
    -- Render & Movement Loops
    ---------------------------------------------------------------------------
    trackConnection(RunService.RenderStepped:Connect(function()
        -- 1. FOV Circle
        if fovCircle then
            fovCircle.Visible = settings.aimbotEnabled and settings.aimbotShowFOV
            fovCircle.Radius = settings.aimbotFOV
            fovCircle.Position = UserInputService:GetMouseLocation()
        end

        -- 2. Mob Aimbot
        if settings.aimbotEnabled then
            local isTriggered = (settings.aimbotActivation == "Always")
                or (settings.aimbotActivation == "Right Mouse" and (rightMouseDown or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)))

            if isTriggered then
                local targetPart = getClosestAimTarget()
                if targetPart then
                    local targetPos = targetPart.Position
                    local currentCF = Camera.CFrame
                    local targetCF = CFrame.new(currentCF.Position, targetPos)
                    local smoothness = math.clamp(settings.aimbotSmoothness, 0.05, 1)
                    Camera.CFrame = currentCF:Lerp(targetCF, smoothness)
                end
            end
        end
    end))

    -- Heartbeat / Stepped for NoClip
    trackConnection(RunService.Stepped:Connect(function()
        if settings.noClip and LP.Character then
            for _, part in ipairs(LP.Character:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
    end))

    -- Heartbeat timer for ESP, Hitboxes, Auto Collect, and Stamina Sync (every 0.25s)
    local espTimer = 0
    trackConnection(RunService.Heartbeat:Connect(function(dt)
        espTimer = espTimer + dt
        if espTimer >= 0.25 then
            espTimer = 0
            updateESP()
            applyLighting()
            updateHitboxes()
            processAutoCollect()
            if settings.infStamina then
                applyStaminaBypass()
            end
        end
    end))

    ---------------------------------------------------------------------------
    -- Teleport Function
    ---------------------------------------------------------------------------
    local function teleportTo(pos)
        local myChar = LP.Character
        local root = getRoot(myChar)
        if root then
            root.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
        end
    end

    ---------------------------------------------------------------------------
    -- UI Construction (Rayfield via maclib_adapter)
    ---------------------------------------------------------------------------

    -- 1. Visuals & ESP Tab
    local VisualsTab = Window:CreateTab("Visuals & ESP", 4483362458)

    VisualsTab:CreateSection("Forageables & Harvest Items")
    VisualsTab:CreateToggle({
        Name = "Enable Forageables ESP",
        CurrentValue = settings.espForageables,
        Flag = "DV_ForageESP",
        Callback = function(v)
            settings.espForageables = v
            if not v then clearESPByTag("forage") end
        end
    })

    VisualsTab:CreateDropdown({
        Name = "Filter Forageable Type",
        Options = {"All", "Mushroom", "Onion", "Thyme"},
        CurrentOption = settings.forageFilterType,
        Flag = "DV_ForageFilter",
        Callback = function(v)
            settings.forageFilterType = v
            clearESPByTag("forage")
        end
    })

    VisualsTab:CreateSlider({
        Name = "Forageable Max Distance",
        Range = {100, 2500},
        Increment = 50,
        CurrentValue = settings.forageMaxDist,
        Flag = "DV_ForageMaxDist",
        Callback = function(v) settings.forageMaxDist = v end
    })

    VisualsTab:CreateSection("Mobs & Monsters ESP")
    VisualsTab:CreateToggle({
        Name = "Enable Mob ESP",
        CurrentValue = settings.espMobs,
        Flag = "DV_MobESP",
        Callback = function(v)
            settings.espMobs = v
            if not v then clearESPByTag("mob") end
        end
    })

    VisualsTab:CreateToggle({
        Name = "Show Mob Distance",
        CurrentValue = settings.mobShowDist,
        Flag = "DV_MobDist",
        Callback = function(v) settings.mobShowDist = v end
    })

    VisualsTab:CreateToggle({
        Name = "Show Mob HP",
        CurrentValue = settings.mobShowHealth,
        Flag = "DV_MobHP",
        Callback = function(v) settings.mobShowHealth = v end
    })

    VisualsTab:CreateSection("NPCs & Other Players")
    VisualsTab:CreateToggle({
        Name = "Enable NPC ESP (Quest & Blacksmith)",
        CurrentValue = settings.espNPCs,
        Flag = "DV_NPCESP",
        Callback = function(v)
            settings.espNPCs = v
            if not v then clearESPByTag("npc") end
        end
    })

    VisualsTab:CreateToggle({
        Name = "Enable Player ESP",
        CurrentValue = settings.espPlayers,
        Flag = "DV_PlayerESP",
        Callback = function(v)
            settings.espPlayers = v
            if not v then clearESPByTag("player") end
        end
    })

    VisualsTab:CreateToggle({
        Name = "Wall Check (Red = Shootable / Green = Behind Wall)",
        CurrentValue = settings.wallCheck,
        Flag = "DV_WallCheck",
        Callback = function(v) settings.wallCheck = v end
    })

    -- 2. Combat Tab
    local CombatTab = Window:CreateTab("Combat", 4483362458)
    CombatTab:CreateSection("Mob Hitbox Expander")

    CombatTab:CreateToggle({
        Name = "Enable Hitbox Expander",
        CurrentValue = settings.hitboxExpander,
        Flag = "DV_HitboxExpander",
        Callback = function(v)
            settings.hitboxExpander = v
            updateHitboxes()
        end
    })

    CombatTab:CreateSlider({
        Name = "Hitbox Expander Size",
        Range = {8, 30},
        Increment = 2,
        CurrentValue = settings.hitboxSize,
        Flag = "DV_HitboxSize",
        Callback = function(v)
            settings.hitboxSize = v
            if settings.hitboxExpander then
                updateHitboxes()
            end
        end
    })

    CombatTab:CreateSection("Mob Aim Assist")
    CombatTab:CreateToggle({
        Name = "Enable Mob Aimbot",
        CurrentValue = settings.aimbotEnabled,
        Flag = "DV_AimEnabled",
        Callback = function(v) settings.aimbotEnabled = v end
    })

    CombatTab:CreateDropdown({
        Name = "Activation Mode",
        Options = {"Right Mouse", "Always"},
        CurrentOption = settings.aimbotActivation,
        Flag = "DV_AimMode",
        Callback = function(v) settings.aimbotActivation = v end
    })

    CombatTab:CreateDropdown({
        Name = "Target Bone",
        Options = {"Head", "HumanoidRootPart"},
        CurrentOption = settings.aimbotTarget,
        Flag = "DV_AimBone",
        Callback = function(v) settings.aimbotTarget = v end
    })

    CombatTab:CreateSlider({
        Name = "Aimbot FOV Radius",
        Range = {50, 450},
        Increment = 10,
        CurrentValue = settings.aimbotFOV,
        Flag = "DV_AimFOV",
        Callback = function(v)
            settings.aimbotFOV = v
            if fovCircle then fovCircle.Radius = v end
        end
    })

    CombatTab:CreateSlider({
        Name = "Aimbot Smoothness (Percent)",
        Range = {5, 80},
        Increment = 5,
        CurrentValue = math.floor(settings.aimbotSmoothness * 100),
        Flag = "DV_AimSmooth",
        Callback = function(v) settings.aimbotSmoothness = v / 100 end
    })

    CombatTab:CreateToggle({
        Name = "Show FOV Circle",
        CurrentValue = settings.aimbotShowFOV,
        Flag = "DV_ShowFOV",
        Callback = function(v) settings.aimbotShowFOV = v end
    })

    -- 3. Teleport & Travel Tab
    local TravelTab = Window:CreateTab("Travel & Map", 4483362458)
    TravelTab:CreateSection("Fast Travel Waypoints")

    local waypointKeys = {}
    for k in pairs(WAYPOINTS) do table.insert(waypointKeys, k) end
    table.sort(waypointKeys)

    local selectedWaypoint = waypointKeys[1]
    TravelTab:CreateDropdown({
        Name = "Select Destination",
        Options = waypointKeys,
        CurrentOption = selectedWaypoint,
        Flag = "DV_WaypointSelect",
        Callback = function(v)
            selectedWaypoint = type(v) == "table" and v[1] or v
        end
    })

    TravelTab:CreateButton({
        Name = "Teleport to Selected Destination",
        Callback = function()
            local wpName = type(selectedWaypoint) == "table" and selectedWaypoint[1] or selectedWaypoint
            local targetPos = WAYPOINTS[wpName]
            if targetPos then
                teleportTo(targetPos)
            end
        end
    })

    TravelTab:CreateSection("Quick Travel Buttons")
    for _, name in ipairs(waypointKeys) do
        local targetPos = WAYPOINTS[name]
        TravelTab:CreateButton({
            Name = "Go to: " .. name,
            Callback = function()
                teleportTo(targetPos)
            end
        })
    end

    -- 4. World & Utilities Tab
    local UtilityTab = Window:CreateTab("Utility", 4483362458)
    UtilityTab:CreateSection("Auto Harvesting & Foraging")

    UtilityTab:CreateToggle({
        Name = "Auto Collect Forageables (Key E)",
        CurrentValue = settings.autoCollect,
        Flag = "DV_AutoCollect",
        Callback = function(v) settings.autoCollect = v end
    })

    UtilityTab:CreateSlider({
        Name = "Auto Collect Reach (Studs)",
        Range = {10, 60},
        Increment = 5,
        CurrentValue = settings.autoCollectRange,
        Flag = "DV_CollectReach",
        Callback = function(v) settings.autoCollectRange = v end
    })

    UtilityTab:CreateSection("Movement & World")

    UtilityTab:CreateToggle({
        Name = "Infinite Stamina (Sprint & Skills Bypass)",
        CurrentValue = settings.infStamina,
        Flag = "DV_InfStamina",
        Callback = function(v)
            settings.infStamina = v
            if v then
                applyStaminaBypass()
            end
        end
    })

    UtilityTab:CreateToggle({
        Name = "NoClip (Pass through walls)",
        CurrentValue = settings.noClip,
        Flag = "DV_NoClip",
        Callback = function(v) settings.noClip = v end
    })

    UtilityTab:CreateSection("Lighting & Visual Clarity")
    UtilityTab:CreateToggle({
        Name = "Fullbright (Clear View in Caves)",
        CurrentValue = settings.fullBright,
        Flag = "DV_Fullbright",
        Callback = function(v)
            settings.fullBright = v
            if v then applyLighting() else restoreLighting() end
        end
    })

    UtilityTab:CreateToggle({
        Name = "No Fog",
        CurrentValue = settings.noFog,
        Flag = "DV_NoFog",
        Callback = function(v)
            settings.noFog = v
            if v then applyLighting() else restoreLighting() end
        end
    })

    ---------------------------------------------------------------------------
    -- Cleanup Handler
    ---------------------------------------------------------------------------
    local moduleInstance = {}
    function moduleInstance.Destroy()
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        clearAllESP()
        if fovCircle then pcall(function() fovCircle:Remove() end) end
        removeStaminaBypass()
        settings.hitboxExpander = false
        updateHitboxes()
        restoreLighting()
        getgenv().__RAVEN_DESOLATE_VALLEY = nil
    end

    getgenv().__RAVEN_DESOLATE_VALLEY = moduleInstance
    return moduleInstance
end
