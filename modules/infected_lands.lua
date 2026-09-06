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
    local rightMouseDown = false

    local function trackConnection(connection)
        table.insert(connections, connection)
        return connection
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
        -- Player ESP
        espPlayers = true,
        playerMaxDist = 1200,
        playerShowDist = true,
        playerShowHealth = true,

        -- Zombie ESP
        espZombies = true,
        zombieMaxDist = 1200,
        zombieShowDist = true,
        zombieShowHealth = true,

        -- Ground Items ESP
        espGroundItems = true,
        itemMaxDist = 300,
        itemShowDist = true,

        -- Vehicles ESP
        espVehicles = true,
        vehMaxDist = 1500,
        vehShowDist = true,

        -- Player Corpses ESP
        espCorpses = true,
        corpseMaxDist = 800,
        corpseShowDist = true,

        -- Wall Check (Visibility Check)
        wallCheck = true,
        showPartBoxes = true,                          -- Show exact shootable body part boxes (Cold War style)
        colorVisible = Color3.fromRGB(255, 45, 45),   -- Red when shootable (Direct Line of Sight)
        colorBehindWall = Color3.fromRGB(45, 235, 85), -- Green when behind wall

        -- Aimbot Settings
        aimbotEnabled = true,
        aimbotActivation = "Right Mouse", -- "Right Mouse" or "Always"
        aimbotTarget = "Auto (Shootable Bone)", -- "Head", "Torso", or "Auto (Shootable Bone)"
        aimbotTargetType = "Both", -- "Zombies", "Players", "Both"
        aimbotVisibleOnly = false, -- Default false so targets can be locked easily or if true use wall check
        aimbotFOV = 250,
        aimbotSmoothness = 0.25,
        aimbotShowFOV = true,

        -- Aim Prediction Settings (Cold War Ballistics Standard)
        aimPrediction = true,                          -- Predict enemy movement + bullet drop
        predictBulletSpeed = 1600,                     -- Studs/sec estimated bullet velocity
        predictGravity = 196.2,                        -- Workspace gravity for drop calculation
        predictDotSize = 6,                            -- Size of prediction reticle dot
        predictShowCircle = true,                      -- Outer ring around prediction dot

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
    -- Drawing FOV Circle & Aim Prediction Dot (Cold War Standard)
    ---------------------------------------------------------------------------
    local fovCircle = nil
    local predictDot = nil
    local predictCircle = nil
    local predictText = nil

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

            -- Prediction Dot (Exact point where bullet will hit with lead + drop)
            predictDot = Drawing.new("Circle")
            predictDot.Thickness = 1
            predictDot.NumSides = 24
            predictDot.Radius = settings.predictDotSize
            predictDot.Filled = true
            predictDot.Color = Color3.fromRGB(0, 255, 120)
            predictDot.Transparency = 0.9
            predictDot.Visible = false

            -- Prediction Outer Ring
            predictCircle = Drawing.new("Circle")
            predictCircle.Thickness = 1.5
            predictCircle.NumSides = 24
            predictCircle.Radius = settings.predictDotSize + 4
            predictCircle.Filled = false
            predictCircle.Color = Color3.fromRGB(0, 255, 120)
            predictCircle.Transparency = 0.8
            predictCircle.Visible = false

            -- Prediction Distance / Time Label
            predictText = Drawing.new("Text")
            predictText.Size = 13
            predictText.Center = true
            predictText.Outline = true
            predictText.Color = Color3.fromRGB(0, 255, 120)
            predictText.Visible = false
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
    -- Wall Check (Line of Sight & Multi-pass Raycast - Cold War standard)
    ---------------------------------------------------------------------------
    local MAX_VISION_PASSTHROUGHS = 4
    local espFolder = Instance.new("Folder")
    espFolder.Name = "RAVEN_PartBoxes"
    pcall(function() espFolder.Parent = Workspace end)

    local function isVisionTransparent(instance)
        if not instance or not instance:IsA("BasePart") then return false end
        -- Pass-through glass, windows, thin fences, or transparent decorative props
        return instance.Transparency >= 0.25 or instance.CanCollide == false
    end

    local function rayReachesTarget(fromPos, toPos, targetCharacter, targetPart)
        local direction = toPos - fromPos
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.IgnoreWater = true

        local baseIgnore = {}
        if LP.Character then
            table.insert(baseIgnore, LP.Character)
        end
        local wsScope = Workspace:FindFirstChild("WeaponSystem_Workspace")
        if wsScope then table.insert(baseIgnore, wsScope) end
        for _, name in ipairs({"Ignore", "Effects", "Debris", "RAVEN_PartBoxes"}) do
            local folder = Workspace:FindFirstChild(name)
            if folder then table.insert(baseIgnore, folder) end
        end

        local currentIgnore = table.clone(baseIgnore)
        local reachesTarget = false

        for _ = 1, MAX_VISION_PASSTHROUGHS do
            rayParams.FilterDescendantsInstances = currentIgnore
            local result = Workspace:Raycast(fromPos, direction, rayParams)
            if not result then
                reachesTarget = true
                break
            end

            if result.Instance == targetPart
                or (targetCharacter ~= nil and result.Instance:IsDescendantOf(targetCharacter)) then
                reachesTarget = true
                break
            end

            -- If hit opaque solid structure, ray is blocked
            if not isVisionTransparent(result.Instance) then
                break
            end

            -- Pass through transparent / non-collidable part and continue ray
            table.insert(currentIgnore, result.Instance)
        end

        return reachesTarget
    end

    local function isPartVisible(targetPart, targetModel)
        if not targetPart or not targetPart:IsA("BasePart") then return false end
        local camPos = Camera.CFrame.Position
        local targetPos = targetPart.Position
        local dir = targetPos - camPos
        if dir.Magnitude < 0.5 then return true end

        -- 1. Check center
        if rayReachesTarget(camPos, targetPos, targetModel, targetPart) then
            return true
        end

        -- 2. Fallback edge sample (0.42 offset like Cold War for peeking targets)
        local halfSize = targetPart.Size * 0.42
        local edgePos = targetPart.CFrame:PointToWorldSpace(Vector3.new(0, halfSize.Y, 0))
        if rayReachesTarget(camPos, edgePos, targetModel, targetPart) then
            return true
        end

        return false
    end

    -- Check multiple body parts for full visibility scan
    local BODY_PARTS_CHECK = {"Head", "Torso", "UpperTorso", "Right Arm", "RightUpperArm", "Left Arm", "LeftUpperArm"}

    local function scanCharacterPartStates(character)
        local states = {}
        local anyVisible = false
        local camPos = Camera.CFrame.Position

        for _, name in ipairs(BODY_PARTS_CHECK) do
            local part = character:FindFirstChild(name)
            if part and part:IsA("BasePart") then
                local vis = isPartVisible(part, character)
                states[part] = vis
                if vis then anyVisible = true end
            end
        end

        return anyVisible, states
    end

    ---------------------------------------------------------------------------
    -- Part Boxes (Detailed Shootable Body Point Indicators)
    ---------------------------------------------------------------------------
    local function updatePartBoxes(espData, character, partStates)
        if not espData.partBoxes then
            espData.partBoxes = {}
        end

        if not settings.showPartBoxes or not settings.wallCheck then
            for _, box in pairs(espData.partBoxes) do
                box.Visible = false
            end
            return
        end

        local active = {}
        for part, isVis in pairs(partStates or {}) do
            if part.Parent and part:IsDescendantOf(character) then
                local box = espData.partBoxes[part]
                if not box then
                    box = Instance.new("BoxHandleAdornment")
                    box.Name = "ShootablePartBox"
                    box.AlwaysOnTop = true
                    box.ZIndex = 5
                    box.Transparency = 0.65
                    box.Adornee = part
                    pcall(function() box.Parent = espFolder end)
                    espData.partBoxes[part] = box
                end
                box.Size = part.Size + Vector3.new(0.06, 0.06, 0.06)
                box.Color3 = isVis and settings.colorVisible or settings.colorBehindWall
                box.Visible = true
                active[part] = true
            end
        end

        for part, box in pairs(espData.partBoxes) do
            if not active[part] then
                box.Visible = false
                if not part.Parent then
                    pcall(function() box:Destroy() end)
                    espData.partBoxes[part] = nil
                end
            end
        end
    end

    local function hidePartBoxes(espData)
        if espData and espData.partBoxes then
            for _, box in pairs(espData.partBoxes) do
                box.Visible = false
            end
        end
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
            billboard.Size = UDim2.new(0, 160, 0, 36)
            billboard.StudsOffset = Vector3.new(0, 2.5, 0)
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
            subLabel.TextColor3 = Color3.fromRGB(225, 225, 225)
            subLabel.TextStrokeTransparency = 0.3
            subLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
            subLabel.BackgroundTransparency = 1
            subLabel.Size = UDim2.new(1, 0, 0.5, 0)
            subLabel.Position = UDim2.new(0, 0, 0, 0.5)
            subLabel.Parent = billboard
        end

        espObjects[inst] = {
            highlight = highlight,
            billboard = billboard,
            titleLabel = titleLabel,
            subLabel = subLabel,
            tag = tag,
            color = color,
            inst = inst,
            partBoxes = {}
        }
    end

    local function removeESP(inst)
        local data = espObjects[inst]
        if not data then return end
        if data.highlight then pcall(function() data.highlight:Destroy() end) end
        if data.billboard then pcall(function() data.billboard:Destroy() end) end
        if data.partBoxes then
            for _, box in pairs(data.partBoxes) do
                pcall(function() box:Destroy() end)
            end
        end
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
                if dist <= settings.playerMaxDist then
                    -- Visibility Wall Check & Part Scan (Cold War style)
                    local isVisible, partStates = false, {}
                    if settings.wallCheck then
                        isVisible, partStates = scanCharacterPartStates(info.model)
                    end
                    local targetColor = isVisible and settings.colorVisible or settings.colorBehindWall
                    if not settings.wallCheck then
                        targetColor = Color3.fromRGB(60, 160, 255)
                    end

                    if not espObjects[info.model] then
                        createESP(info.model, targetColor, "👤 " .. info.model.Name, true, "player")
                    end
                    local data = espObjects[info.model]
                    if data then
                        -- Update color dynamically on wall check
                        if data.highlight and data.highlight.FillColor ~= targetColor then
                            data.highlight.FillColor = targetColor
                        end
                        if data.titleLabel and data.titleLabel.TextColor3 ~= targetColor then
                            data.titleLabel.TextColor3 = targetColor
                        end

                        if data.subLabel then
                            local parts = {}
                            if settings.playerShowDist then table.insert(parts, math.floor(dist) .. "m") end
                            if settings.playerShowHealth then table.insert(parts, "HP: " .. math.floor(info.humanoid.Health)) end
                            if isVisible then table.insert(parts, "[SHOOTABLE]") end
                            data.subLabel.Text = table.concat(parts, " | ")
                        end

                        -- Update detailed shootable body part boxes
                        updatePartBoxes(data, info.model, partStates)
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
                if dist <= settings.zombieMaxDist then
                    -- Visibility Wall Check & Part Scan (Cold War style)
                    local isVisible, partStates = false, {}
                    if settings.wallCheck then
                        isVisible, partStates = scanCharacterPartStates(info.model)
                    end
                    local targetColor = isVisible and settings.colorVisible or settings.colorBehindWall
                    if not settings.wallCheck then
                        targetColor = Color3.fromRGB(255, 80, 80)
                    end

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
                        createESP(info.model, targetColor, "🧟 " .. zName, true, "zombie")
                    end
                    local data = espObjects[info.model]
                    if data then
                        -- Update color dynamically on wall check
                        if data.highlight and data.highlight.FillColor ~= targetColor then
                            data.highlight.FillColor = targetColor
                        end
                        if data.titleLabel and data.titleLabel.TextColor3 ~= targetColor then
                            data.titleLabel.TextColor3 = targetColor
                        end

                        if data.subLabel then
                            local parts = {}
                            if settings.zombieShowDist then table.insert(parts, math.floor(dist) .. "m") end
                            if settings.zombieShowHealth then table.insert(parts, "HP: " .. math.floor(info.health)) end
                            if isVisible then table.insert(parts, "[SHOOTABLE]") end
                            data.subLabel.Text = table.concat(parts, " | ")
                        end

                        -- Update detailed shootable body part boxes
                        updatePartBoxes(data, info.model, partStates)
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
                    if dist <= settings.itemMaxDist then
                        if not espObjects[item] then
                            local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                            local itemName = (prompt and prompt.ObjectText ~= "" and prompt.ObjectText) or item.Name:gsub("^%w+%-?%w*%-?%w*%-?%w*%-?%w*", "")
                            if itemName == "" then itemName = item.Name end

                            createESP(item, Color3.fromRGB(255, 215, 0), "📦 " .. itemName, item:IsA("Model"), "item")
                        end
                        local data = espObjects[item]
                        if data and data.subLabel then
                            data.subLabel.Text = settings.itemShowDist and (math.floor(dist) .. "m") or ""
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
                    if dist <= settings.vehMaxDist then
                        if not espObjects[veh] then
                            createESP(veh, Color3.fromRGB(130, 220, 255), "🚗 " .. veh.Name, true, "vehicle")
                        end
                        local data = espObjects[veh]
                        if data and data.subLabel then
                            data.subLabel.Text = settings.vehShowDist and (math.floor(dist) .. "m") or ""
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
                    if dist <= settings.corpseMaxDist then
                        if not espObjects[corpse] then
                            createESP(corpse, Color3.fromRGB(200, 130, 255), "💀 " .. corpse.Name, true, "corpse")
                        end
                        local data = espObjects[corpse]
                        if data and data.subLabel then
                            data.subLabel.Text = settings.corpseShowDist and (math.floor(dist) .. "m") or ""
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
    -- Safe Mouse / Camera Aimbot with Wall Check Integration
    ---------------------------------------------------------------------------
    local function getClosestAimTarget()
        local myChar = LP.Character
        local myRoot = getRoot(myChar)
        if not myRoot then return nil end

        local mousePos = UserInputService:GetMouseLocation()
        local bestTargetPart = nil
        local bestTargetModel = nil
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

            if not isDead and health > 0 then
                -- Determine bone candidates with prioritized ranking (Cold War style)
                local boneCandidates = {}
                if settings.aimbotTarget == "Auto (Shootable Bone)" then
                    -- Priority 1: Head
                    table.insert(boneCandidates, model:FindFirstChild("Head"))
                    -- Priority 2: Torso
                    table.insert(boneCandidates, model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso"))
                    -- Priority 3: Arms (if peeking around corner)
                    table.insert(boneCandidates, model:FindFirstChild("Right Arm") or model:FindFirstChild("RightUpperArm"))
                    table.insert(boneCandidates, model:FindFirstChild("Left Arm") or model:FindFirstChild("LeftUpperArm"))
                    -- Priority 4: Root
                    table.insert(boneCandidates, getRoot(model))
                else
                    table.insert(boneCandidates, model:FindFirstChild(settings.aimbotTarget) or getRoot(model))
                end

                for _, targetPart in ipairs(boneCandidates) do
                    if targetPart and targetPart:IsA("BasePart") then
                        -- Check wall check if required
                        local canShoot = true
                        if settings.aimbotVisibleOnly then
                            canShoot = isPartVisible(targetPart, model)
                        end

                        if canShoot then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
                            if onScreen and screenPos.Z > 0 then
                                local target2D = Vector2.new(screenPos.X, screenPos.Y)
                                local screenCenter = Camera.ViewportSize * 0.5
                                local distToMouse = (target2D - mousePos).Magnitude
                                local distToCenter = (target2D - screenCenter).Magnitude
                                local screenDist = math.min(distToMouse, distToCenter)

                                if screenDist < bestDist then
                                    bestDist = screenDist
                                    bestTargetPart = targetPart
                                    bestTargetModel = model
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestTargetPart, bestTargetModel
    end

    ---------------------------------------------------------------------------
    -- Aim Prediction Ballistics Engine (Cold War Standard)
    ---------------------------------------------------------------------------
    local lastPositions = {}
    local lastPositionTimes = {}
    local smoothedVelocities = {}

    local function getTargetVelocity(model, rootPart)
        if not rootPart or not rootPart:IsA("BasePart") then return Vector3.zero end

        local currentPos = rootPart.Position
        local currentTime = tick()
        local lastPos = lastPositions[model]
        local lastTime = lastPositionTimes[model]

        lastPositions[model] = currentPos
        lastPositionTimes[model] = currentTime

        if lastPos and lastTime then
            local dt = currentTime - lastTime
            if dt > 0 and dt < 1 then
                local measured = (currentPos - lastPos) / dt
                local assembly = rootPart.AssemblyLinearVelocity
                if assembly and assembly.Magnitude < 250 then
                    measured = measured:Lerp(assembly, 0.45)
                end
                local previous = smoothedVelocities[model] or measured
                local alpha = 1 - math.exp(-dt * 12)
                local smoothed = previous:Lerp(measured, alpha)
                smoothedVelocities[model] = smoothed
                return smoothed
            end
        end
        return rootPart.AssemblyLinearVelocity or Vector3.zero
    end

    local function getBulletTravelTime(distance, muzzleVelocity)
        return distance / math.max(muzzleVelocity or settings.predictBulletSpeed, 1)
    end

    local function getBulletDrop(time)
        return 0.5 * (settings.predictGravity or 196.2) * time * time
    end

    -- Iterative convergence calculation (Cold War 3-step convergence)
    local function getPredictedAimPoint(targetPart, targetModel, shooterPos)
        if not targetPart or not targetPart:IsA("BasePart") then return nil end
        local root = getRoot(targetModel) or targetPart
        local velocity = getTargetVelocity(targetModel, root)
        local targetPos = targetPart.Position
        local muzzleVelocity = settings.predictBulletSpeed

        local travelTime = 0
        local leadOffset = Vector3.zero
        for _ = 1, 3 do
            leadOffset = velocity * travelTime
            local futurePos = targetPos + leadOffset
            local dist = (futurePos - shooterPos).Magnitude
            travelTime = getBulletTravelTime(dist, muzzleVelocity)
        end

        leadOffset = velocity * travelTime
        local drop = getBulletDrop(travelTime)
        local predictedPos = targetPos + leadOffset + Vector3.new(0, drop, 0)

        return predictedPos, travelTime, velocity
    end

    local function hidePredictionDisplay()
        if predictDot then predictDot.Visible = false end
        if predictCircle then predictCircle.Visible = false end
        if predictText then predictText.Visible = false end
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

        -- 2. Aim Prediction & Aimbot Target Resolution (Cold War Standard)
        local targetPart, targetModel = getClosestAimTarget()
        local aimTargetPoint = targetPart and targetPart.Position or nil

        if targetPart and targetModel and (settings.aimPrediction or settings.aimbotEnabled) then
            local predictedPos, travelTime, velocity = getPredictedAimPoint(targetPart, targetModel, Camera.CFrame.Position)
            if predictedPos then
                aimTargetPoint = predictedPos

                -- Update Drawing Prediction Dot
                if settings.aimPrediction and predictDot then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(predictedPos)
                    if onScreen then
                        local pos2D = Vector2.new(screenPos.X, screenPos.Y)
                        predictDot.Position = pos2D
                        predictDot.Radius = settings.predictDotSize
                        predictDot.Visible = true

                        if predictCircle then
                            predictCircle.Position = pos2D
                            predictCircle.Radius = settings.predictDotSize + 4
                            predictCircle.Visible = settings.predictShowCircle
                        end

                        if predictText then
                            predictText.Position = pos2D + Vector2.new(0, -(settings.predictDotSize + 18))
                            local distStuds = (targetPart.Position - Camera.CFrame.Position).Magnitude
                            local distMeters = math.floor(distStuds / 3.5714)
                            local ms = math.floor(travelTime * 1000)
                            predictText.Text = string.format("PREDICT: %dm | %dms", distMeters, ms)
                            predictText.Visible = true
                        end
                    else
                        hidePredictionDisplay()
                    end
                else
                    hidePredictionDisplay()
                end
            else
                hidePredictionDisplay()
            end
        else
            hidePredictionDisplay()
        end

        -- 3. Smooth Aimbot Activation (Cold War Standard)
        local isAimActive = false
        if settings.aimbotEnabled then
            if settings.aimbotActivation == "Always" then
                isAimActive = true
            else
                local ok, pressed = pcall(function()
                    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
                end)
                isAimActive = (ok and pressed == true) or rightMouseDown
            end
        end

        if isAimActive and aimTargetPoint then
            local camCF = Camera.CFrame
            local targetCF = CFrame.lookAt(camCF.Position, aimTargetPoint)
            Camera.CFrame = camCF:Lerp(targetCF, math.clamp(settings.aimbotSmoothness, 0.05, 1))
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
    -- User Interface (MacLib / MacLib Adapter Standard)
    ---------------------------------------------------------------------------
    local CombatTab = Window:CreateTab("Combat", 4483362458)
    CombatTab:CreateSection("Aimbot Settings (Smooth Camera)")

    CombatTab:CreateToggle({
        Name = "Aimbot Enabled (Hold RMB)",
        CurrentValue = settings.aimbotEnabled,
        Flag = "Infected_Aimbot",
        Callback = function(val)
            settings.aimbotEnabled = val
        end
    })

    CombatTab:CreateDropdown({
        Name = "Activation Mode",
        Options = {"Right Mouse", "Always"},
        CurrentOption = settings.aimbotActivation,
        Flag = "Infected_AimActivation",
        Callback = function(val)
            settings.aimbotActivation = val
        end
    })

    CombatTab:CreateToggle({
        Name = "Visible Only (Wall Check Target)",
        CurrentValue = settings.aimbotVisibleOnly,
        Flag = "Infected_AimVisibleOnly",
        Callback = function(val)
            settings.aimbotVisibleOnly = val
        end
    })

    CombatTab:CreateDropdown({
        Name = "Target Type",
        Options = {"Both", "Zombies", "Players"},
        CurrentOption = settings.aimbotTargetType,
        Flag = "Infected_TargetType",
        Callback = function(val)
            settings.aimbotTargetType = val
        end
    })

    CombatTab:CreateDropdown({
        Name = "Target Bone",
        Options = {"Head", "Torso", "Auto (Shootable Bone)"},
        CurrentOption = settings.aimbotTarget,
        Flag = "Infected_TargetBone",
        Callback = function(val)
            settings.aimbotTarget = val
        end
    })

    CombatTab:CreateSlider({
        Name = "Aimbot FOV Radius",
        Range = {30, 400},
        Increment = 5,
        CurrentValue = settings.aimbotFOV,
        Flag = "Infected_AimFOV",
        Callback = function(val)
            settings.aimbotFOV = val
            if fovCircle then fovCircle.Radius = val end
        end
    })

    CombatTab:CreateSlider({
        Name = "Smoothness Speed (Percent)",
        Range = {5, 80},
        Increment = 5,
        CurrentValue = math.floor(settings.aimbotSmoothness * 100),
        Flag = "Infected_Smooth",
        Callback = function(val)
            settings.aimbotSmoothness = val / 100
        end
    })

    CombatTab:CreateToggle({
        Name = "Show FOV Circle",
        CurrentValue = settings.aimbotShowFOV,
        Flag = "Infected_ShowFOV",
        Callback = function(val)
            settings.aimbotShowFOV = val
        end
    })

    -- Section: Ballistics Aim Prediction (Cold War Standard)
    CombatTab:CreateSection("Ballistics Aim Prediction (Drop + Lead)")

    CombatTab:CreateToggle({
        Name = "Enable Aim Prediction",
        CurrentValue = settings.aimPrediction,
        Flag = "Infected_AimPrediction",
        Callback = function(val)
            settings.aimPrediction = val
            if not val then
                hidePredictionDisplay()
            end
        end
    })

    CombatTab:CreateToggle({
        Name = "Show Prediction Ring",
        CurrentValue = settings.predictShowCircle,
        Flag = "Infected_PredictCircle",
        Callback = function(val)
            settings.predictShowCircle = val
        end
    })

    CombatTab:CreateSlider({
        Name = "Prediction Reticle Size",
        Range = {3, 14},
        Increment = 1,
        CurrentValue = settings.predictDotSize,
        Flag = "Infected_PredictDotSize",
        Callback = function(val)
            settings.predictDotSize = val
        end
    })

    CombatTab:CreateSlider({
        Name = "Estimated Bullet Velocity",
        Range = {800, 3000},
        Increment = 100,
        CurrentValue = settings.predictBulletSpeed,
        Flag = "Infected_PredictSpeed",
        Callback = function(val)
            settings.predictBulletSpeed = val
        end
    })

    ---------------------------------------------------------------------------
    -- Visuals Tab Elements
    ---------------------------------------------------------------------------
    local VisualsTab = Window:CreateTab("Visuals", 4483362458)

    -- Section: Wall Check / Line of Sight
    VisualsTab:CreateSection("Wall Check & Visibility (Red = Shootable / Green = Behind Wall)")

    VisualsTab:CreateToggle({
        Name = "Enable Wall Check Colors",
        CurrentValue = settings.wallCheck,
        Flag = "Infected_WallCheck",
        Callback = function(val)
            settings.wallCheck = val
        end
    })

    VisualsTab:CreateToggle({
        Name = "Show Shootable Body Part Boxes",
        CurrentValue = settings.showPartBoxes,
        Flag = "Infected_PartBoxes",
        Callback = function(val)
            settings.showPartBoxes = val
            if not val then
                for _, data in pairs(espObjects) do
                    hidePartBoxes(data)
                end
            end
        end
    })

    -- Section: Player ESP
    VisualsTab:CreateSection("Player ESP Settings")

    VisualsTab:CreateToggle({
        Name = "Enable Player ESP",
        CurrentValue = settings.espPlayers,
        Flag = "Infected_PlayerESP",
        Callback = function(val)
            settings.espPlayers = val
            if not val then clearESPByTag("player") end
        end
    })

    VisualsTab:CreateToggle({
        Name = "Player Show Distance",
        CurrentValue = settings.playerShowDist,
        Flag = "Infected_PlayerDist",
        Callback = function(val)
            settings.playerShowDist = val
        end
    })

    VisualsTab:CreateToggle({
        Name = "Player Show Health (HP)",
        CurrentValue = settings.playerShowHealth,
        Flag = "Infected_PlayerHP",
        Callback = function(val)
            settings.playerShowHealth = val
        end
    })

    VisualsTab:CreateSlider({
        Name = "Player Max Distance",
        Range = {100, 2500},
        Increment = 50,
        CurrentValue = settings.playerMaxDist,
        Flag = "Infected_PlayerMaxDist",
        Callback = function(val)
            settings.playerMaxDist = val
        end
    })

    -- Section: Zombie ESP
    VisualsTab:CreateSection("Zombie ESP Settings")

    VisualsTab:CreateToggle({
        Name = "Enable Zombie ESP",
        CurrentValue = settings.espZombies,
        Flag = "Infected_ZombieESP",
        Callback = function(val)
            settings.espZombies = val
            if not val then clearESPByTag("zombie") end
        end
    })

    VisualsTab:CreateToggle({
        Name = "Zombie Show Distance",
        CurrentValue = settings.zombieShowDist,
        Flag = "Infected_ZombieDist",
        Callback = function(val)
            settings.zombieShowDist = val
        end
    })

    VisualsTab:CreateToggle({
        Name = "Zombie Show Health (HP)",
        CurrentValue = settings.zombieShowHealth,
        Flag = "Infected_ZombieHP",
        Callback = function(val)
            settings.zombieShowHealth = val
        end
    })

    VisualsTab:CreateSlider({
        Name = "Zombie Max Distance",
        Range = {100, 2500},
        Increment = 50,
        CurrentValue = settings.zombieMaxDist,
        Flag = "Infected_ZombieMaxDist",
        Callback = function(val)
            settings.zombieMaxDist = val
        end
    })

    -- Section: Ground Items ESP
    VisualsTab:CreateSection("Ground Items / Loot ESP")

    VisualsTab:CreateToggle({
        Name = "Enable Ground Items ESP",
        CurrentValue = settings.espGroundItems,
        Flag = "Infected_GroundESP",
        Callback = function(val)
            settings.espGroundItems = val
            if not val then clearESPByTag("item") end
        end
    })

    VisualsTab:CreateToggle({
        Name = "Item Show Distance",
        CurrentValue = settings.itemShowDist,
        Flag = "Infected_ItemDist",
        Callback = function(val)
            settings.itemShowDist = val
        end
    })

    VisualsTab:CreateSlider({
        Name = "Item Max Distance",
        Range = {50, 1000},
        Increment = 25,
        CurrentValue = settings.itemMaxDist,
        Flag = "Infected_ItemMaxDist",
        Callback = function(val)
            settings.itemMaxDist = val
        end
    })

    -- Section: Vehicles & Corpses ESP
    VisualsTab:CreateSection("Vehicles & Corpses ESP")

    VisualsTab:CreateToggle({
        Name = "Vehicles ESP",
        CurrentValue = settings.espVehicles,
        Flag = "Infected_VehESP",
        Callback = function(val)
            settings.espVehicles = val
            if not val then clearESPByTag("vehicle") end
        end
    })

    VisualsTab:CreateSlider({
        Name = "Vehicle Max Distance",
        Range = {100, 3000},
        Increment = 100,
        CurrentValue = settings.vehMaxDist,
        Flag = "Infected_VehMaxDist",
        Callback = function(val)
            settings.vehMaxDist = val
        end
    })

    VisualsTab:CreateToggle({
        Name = "Player Corpses ESP",
        CurrentValue = settings.espCorpses,
        Flag = "Infected_CorpseESP",
        Callback = function(val)
            settings.espCorpses = val
            if not val then clearESPByTag("corpse") end
        end
    })

    VisualsTab:CreateSlider({
        Name = "Corpse Max Distance",
        Range = {100, 2000},
        Increment = 50,
        CurrentValue = settings.corpseMaxDist,
        Flag = "Infected_CorpseMaxDist",
        Callback = function(val)
            settings.corpseMaxDist = val
        end
    })

    ---------------------------------------------------------------------------
    -- World Tab Elements
    ---------------------------------------------------------------------------
    local WorldTab = Window:CreateTab("World", 4483362458)
    WorldTab:CreateSection("Lighting & Atmosphere")

    WorldTab:CreateToggle({
        Name = "FullBright / Night Vision",
        CurrentValue = settings.fullBright,
        Flag = "Infected_FullBright",
        Callback = function(val)
            settings.fullBright = val
            if not val then restoreLighting() end
        end
    })

    WorldTab:CreateToggle({
        Name = "No Fog / Clear Vision",
        CurrentValue = settings.noFog,
        Flag = "Infected_NoFog",
        Callback = function(val)
            settings.noFog = val
            if not val then restoreLighting() end
        end
    })

    WorldTab:CreateSection("Quality of Life")

    WorldTab:CreateToggle({
        Name = "Instant Proximity Prompt (Instant E)",
        CurrentValue = settings.instantPrompt,
        Flag = "Infected_InstantE",
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
        if predictDot then
            pcall(function() predictDot:Remove() end)
        end
        if predictCircle then
            pcall(function() predictCircle:Remove() end)
        end
        if predictText then
            pcall(function() predictText:Remove() end)
        end
        if espFolder then
            pcall(function() espFolder:Destroy() end)
        end
    end

    return {
        cleanup = cleanup,
        settings = settings
    }
end
