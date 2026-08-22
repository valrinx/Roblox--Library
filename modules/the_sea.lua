--[[
    RAVEN HUB | The Sea
    PlaceId: 139802517550914 | GameId: 9167377564
    Version: v1.2

    Read-only survival awareness: treasure, debris, islands, merchant,
    objectives, survival telemetry, and reversible local visuals.
    No gameplay remotes are fired.
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")
    local CoreGui = game:GetService("CoreGui")

    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}
    local visuals = {}
    local originalFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
    local originalLighting = {
        Brightness = Lighting.Brightness,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        FogEnd = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
        ClockTime = Lighting.ClockTime,
    }
    local fovBinding = "RavenTheSeaFOV_" .. tostring(localPlayer.UserId)

    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenTheSeaESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local compassGui = Instance.new("ScreenGui")
    compassGui.Name = "RavenTheSeaCompass"
    compassGui.ResetOnSpawn = false
    compassGui.IgnoreGuiInset = true
    compassGui.Parent = espFolder.Parent

    local compassArrow = Instance.new("TextLabel")
    compassArrow.BackgroundTransparency = 1
    compassArrow.AnchorPoint = Vector2.new(0.5, 0.5)
    compassArrow.Position = UDim2.fromScale(0.5, 0.18)
    compassArrow.Size = UDim2.fromOffset(44, 44)
    compassArrow.Font = Enum.Font.GothamBold
    compassArrow.Text = "▲"
    compassArrow.TextSize = 34
    compassArrow.TextColor3 = Color3.fromRGB(255, 215, 75)
    compassArrow.TextStrokeTransparency = 0.2
    compassArrow.Visible = false
    compassArrow.Parent = compassGui

    local compassText = Instance.new("TextLabel")
    compassText.BackgroundColor3 = Color3.fromRGB(15, 18, 24)
    compassText.BackgroundTransparency = 0.25
    compassText.AnchorPoint = Vector2.new(0.5, 0)
    compassText.Position = UDim2.fromScale(0.5, 0.205)
    compassText.Size = UDim2.fromOffset(300, 28)
    compassText.Font = Enum.Font.GothamSemibold
    compassText.TextSize = 13
    compassText.TextColor3 = Color3.fromRGB(245, 245, 250)
    compassText.TextStrokeTransparency = 0.35
    compassText.Visible = false
    compassText.Parent = compassGui

    local settings = {
        chestEsp = true,
        itemEsp = true,
        wood = true,
        metal = true,
        food = true,
        fuel = true,
        islandEsp = true,
        specialIslandsOnly = false,
        merchantEsp = true,
        maxDistance = 3500,
        maxChests = 40,
        maxItems = 50,
        fullbright = false,
        customFov = false,
        fov = 85,
        foodWarning = 30,
        o2Warning = 35,
        compass = true,
        routeCategory = "Treasure",
        routeCount = 5,
        creatureEsp = true,
        creatureVisibleOnly = false,
        creatureDistance = 600,
        maxCreatures = 30,
        meleeAura = false,
        auraRadius = 12,
        auraCooldown = 0.45,
        aimAssist = false,
        autoTrigger = false,
        aimSmoothness = 0.18,
        combatVisibleCheck = true,
    }

    local COLORS = {
        chest = Color3.fromRGB(255, 205, 65),
        wood = Color3.fromRGB(205, 145, 75),
        metal = Color3.fromRGB(135, 205, 255),
        food = Color3.fromRGB(100, 255, 135),
        fuel = Color3.fromRGB(255, 130, 60),
        island = Color3.fromRGB(115, 205, 255),
        specialIsland = Color3.fromRGB(205, 125, 255),
        merchant = Color3.fromRGB(255, 235, 120),
        creature = Color3.fromRGB(255, 90, 90),
        visibleCreature = Color3.fromRGB(100, 255, 145),
    }

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getRoot(instance)
        if not instance then return nil end
        if instance:IsA("BasePart") then return instance end
        if instance:IsA("Model") then
            return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
        end
        return instance:FindFirstChildWhichIsA("BasePart", true)
    end

    local function localRoot()
        local character = localPlayer.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local function distanceTo(part)
        local root = localRoot()
        return root and part and (part.Position - root.Position).Magnitude or math.huge
    end

    local function isVisible(part)
        local camera = workspace.CurrentCamera
        local character = localPlayer.Character
        if not camera or not part or not character then return false end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {character, espFolder}
        params.IgnoreWater = true
        local origin = camera.CFrame.Position
        local result = workspace:Raycast(origin, part.Position - origin, params)
        return not result or result.Instance:IsDescendantOf(part.Parent)
    end

    local function creatureHealth(model)
        local humanoid = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
        if humanoid then return humanoid.Health, humanoid.MaxHealth end
        return tonumber(model:GetAttribute("Health")), tonumber(model:GetAttribute("MaxHealth"))
    end

    local function removeVisual(key)
        local visual = visuals[key]
        if not visual then return end
        if visual.highlight then visual.highlight:Destroy() end
        if visual.billboard then visual.billboard:Destroy() end
        visuals[key] = nil
    end

    local function ensureVisual(key, model, part, color, useHighlight)
        local existing = visuals[key]
        if existing and existing.model == model and existing.part == part then return existing end
        removeVisual(key)

        local highlight = nil
        if useHighlight then
            highlight = Instance.new("Highlight")
            highlight.Name = "RavenTheSeaHighlight"
            highlight.Adornee = model
            highlight.FillColor = color
            highlight.OutlineColor = color
            highlight.FillTransparency = 0.78
            highlight.OutlineTransparency = 0.08
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = espFolder
        end

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenTheSeaLabel"
        billboard.Adornee = part
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = settings.maxDistance
        billboard.Size = UDim2.fromOffset(230, 42)
        billboard.StudsOffset = Vector3.new(0, 2.8, 0)
        billboard.Parent = espFolder

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamSemibold
        label.TextSize = 13
        label.TextStrokeTransparency = 0.22
        label.TextColor3 = color
        label.Parent = billboard

        local visual = {model = model, part = part, highlight = highlight, billboard = billboard, label = label}
        visuals[key] = visual
        return visual
    end

    local function addCandidate(list, instance, category, label, color, useHighlight)
        local part = getRoot(instance)
        if not part then return end
        local distance = distanceTo(part)
        if distance > settings.maxDistance then return end
        table.insert(list, {
            instance = instance,
            part = part,
            category = category,
            label = label,
            color = color,
            highlight = useHighlight,
            distance = distance,
        })
    end

    local function classifyItem(model)
        local item = tostring(model:GetAttribute("Item") or "Unknown Item")
        local resource = tostring(model:GetAttribute("Resource") or "")
        if resource == "Wood" then return settings.wood and "wood" or nil, item, COLORS.wood end
        if resource == "Metal" then return settings.metal and "metal" or nil, item, COLORS.metal end
        if model:GetAttribute("Food") ~= nil then return settings.food and "food" or nil, item, COLORS.food end
        if model:GetAttribute("Fuel") ~= nil or model:GetAttribute("BonfireFuel") ~= nil then
            return settings.fuel and "fuel" or nil, item, COLORS.fuel
        end
        return nil
    end

    local function scanWorld()
        local candidates = {}
        local chestFolder = workspace:FindFirstChild("Chests")
        if settings.chestEsp and chestFolder then
            local chests = {}
            for _, chest in ipairs(chestFolder:GetChildren()) do
                local amount = tonumber(chest:GetAttribute("Amount")) or 1
                addCandidate(chests, chest, "chest", chest.Name .. " x" .. amount, COLORS.chest, true)
            end
            table.sort(chests, function(a, b) return a.distance < b.distance end)
            for i = 1, math.min(#chests, settings.maxChests) do table.insert(candidates, chests[i]) end
        end

        local debris = workspace:FindFirstChild("DebrisField")
        if settings.itemEsp and debris then
            local items = {}
            for _, model in ipairs(debris:GetChildren()) do
                local category, label, color = classifyItem(model)
                if category then
                    local value = model:GetAttribute("Value") or model:GetAttribute("Food") or model:GetAttribute("Fuel")
                    if value then label = label .. " +" .. tostring(value) end
                    addCandidate(items, model, category, label, color, true)
                end
            end
            table.sort(items, function(a, b) return a.distance < b.distance end)
            for i = 1, math.min(#items, settings.maxItems) do table.insert(candidates, items[i]) end
        end

        local islands = workspace:FindFirstChild("IslandContainer")
        if settings.islandEsp and islands then
            for _, island in ipairs(islands:GetChildren()) do
                local islandType = tostring(island:GetAttribute("IslandType") or "Island")
                local special = islandType == "POI" or islandType == "Challenge"
                if special or not settings.specialIslandsOnly then
                    addCandidate(candidates, island, "island", island.Name .. " [" .. islandType .. "]",
                        special and COLORS.specialIsland or COLORS.island, false)
                end
            end
        end

        local merchant = workspace:FindFirstChild("MerchantBoat")
        if settings.merchantEsp and merchant then
            addCandidate(candidates, merchant, "merchant", "MERCHANT BOAT", COLORS.merchant, true)
        end

        local creatures = workspace:FindFirstChild("CreatureContainer")
        if settings.creatureEsp and creatures then
            local found = {}
            for _, creature in ipairs(creatures:GetChildren()) do
                local part = getRoot(creature)
                local distance = distanceTo(part)
                if part and distance <= settings.creatureDistance then
                    local visible = isVisible(part)
                    if visible or not settings.creatureVisibleOnly then
                        local health, maxHealth = creatureHealth(creature)
                        local label = creature.Name
                        if health and maxHealth then
                            label = string.format("%s | HP %d/%d", label, math.max(0, math.floor(health)), math.floor(maxHealth))
                        end
                        addCandidate(found, creature, "creature", label,
                            visible and COLORS.visibleCreature or COLORS.creature, true)
                    end
                end
            end
            table.sort(found, function(a, b) return a.distance < b.distance end)
            for i = 1, math.min(#found, settings.maxCreatures) do table.insert(candidates, found[i]) end
        end

        local active = {}
        for _, candidate in ipairs(candidates) do
            local key = candidate.instance
            active[key] = true
            local visual = ensureVisual(key, candidate.instance, candidate.part, candidate.color, candidate.highlight)
            visual.billboard.MaxDistance = settings.maxDistance
            visual.label.Text = string.format("%s | %dm", candidate.label, math.floor(candidate.distance))
            visual.label.TextColor3 = candidate.color
            if visual.highlight then
                visual.highlight.FillColor = candidate.color
                visual.highlight.OutlineColor = candidate.color
            end
        end
        for key in pairs(visuals) do
            if not active[key] then removeVisual(key) end
        end

        local route = {}
        local routeCategory = settings.routeCategory
        for _, candidate in ipairs(candidates) do
            local matches = routeCategory == "Any Loot"
                and candidate.category ~= "island" and candidate.category ~= "merchant" and candidate.category ~= "creature"
                or routeCategory == "Treasure" and candidate.category == "chest"
                or routeCategory == "Wood" and candidate.category == "wood"
                or routeCategory == "Metal" and candidate.category == "metal"
                or routeCategory == "Food" and candidate.category == "food"
                or routeCategory == "Fuel" and candidate.category == "fuel"
                or routeCategory == "Islands" and candidate.category == "island"
                or routeCategory == "Merchant" and candidate.category == "merchant"
            if matches then table.insert(route, candidate) end
        end
        table.sort(route, function(a, b) return a.distance < b.distance end)
        while #route > settings.routeCount do table.remove(route) end
        return candidates, route
    end

    local function guiText(path, fallback)
        local current = localPlayer:FindFirstChildOfClass("PlayerGui")
        for _, name in ipairs(path) do current = current and current:FindFirstChild(name) end
        if not current then return fallback end
        local ok, value = pcall(function() return current.Text end)
        return ok and value ~= "" and value or fallback
    end

    local function objectiveSummary()
        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        local hud = playerGui and playerGui:FindFirstChild("HUD")
        local objectives = hud and hud:FindFirstChild("Objectives")
        local container = objectives and objectives:FindFirstChild("Container")
        local found = {}
        if container then
            for _, item in ipairs(container:GetChildren()) do
                local description = item:FindFirstChild("Description")
                if description and description:IsA("TextLabel") and description.Text ~= "" then
                    table.insert(found, description.Text)
                end
            end
        end
        return #found > 0 and table.concat(found, " • ") or "No active objectives"
    end

    local Dashboard = Window:CreateTab("Survival", "activity")
    Dashboard:CreateSection("Module")
    Dashboard:CreateLabel("The Sea v1.2 | Combat & Diagnostics")
    Dashboard:CreateSection("Live Status")
    local survivalLabel = Dashboard:CreateLabel("Survival: loading...")
    local currencyLabel = Dashboard:CreateLabel("Currency: loading...")
    local objectiveLabel = Dashboard:CreateLabel("Objectives: loading...")
    local nearestLabel = Dashboard:CreateLabel("Nearest: scanning...")
    local routeLabel = Dashboard:CreateLabel("Route: scanning...")
    local inventoryLabel = Dashboard:CreateLabel("Inventory: scanning...")
    local warningLabel = Dashboard:CreateLabel("Warnings: none")
    Dashboard:CreateSlider({Name="Food Warning",Range={5,75},Increment=5,CurrentValue=30,Suffix="%",Flag="TheSeaFoodWarning",Callback=function(v) settings.foodWarning=v end})
    Dashboard:CreateSlider({Name="O2 Warning",Range={5,75},Increment=5,CurrentValue=35,Suffix="%",Flag="TheSeaO2Warning",Callback=function(v) settings.o2Warning=v end})

    local Esp = Window:CreateTab("World ESP", "eye")
    Esp:CreateSection("Treasure / Items")
    Esp:CreateToggle({Name="Treasure ESP",CurrentValue=true,Flag="TheSeaChestESP",Callback=function(v) settings.chestEsp=v end})
    Esp:CreateToggle({Name="Item ESP",CurrentValue=true,Flag="TheSeaItemESP",Callback=function(v) settings.itemEsp=v end})
    Esp:CreateToggle({Name="Wood",CurrentValue=true,Flag="TheSeaWoodESP",Callback=function(v) settings.wood=v end})
    Esp:CreateToggle({Name="Metal",CurrentValue=true,Flag="TheSeaMetalESP",Callback=function(v) settings.metal=v end})
    Esp:CreateToggle({Name="Food",CurrentValue=true,Flag="TheSeaFoodESP",Callback=function(v) settings.food=v end})
    Esp:CreateToggle({Name="Fuel",CurrentValue=true,Flag="TheSeaFuelESP",Callback=function(v) settings.fuel=v end})
    Esp:CreateSection("Navigation")
    Esp:CreateToggle({Name="Island Navigator",CurrentValue=true,Flag="TheSeaIslandESP",Callback=function(v) settings.islandEsp=v end})
    Esp:CreateToggle({Name="POI / Challenge Only",CurrentValue=false,Flag="TheSeaSpecialIslands",Callback=function(v) settings.specialIslandsOnly=v end})
    Esp:CreateToggle({Name="Merchant Tracker",CurrentValue=true,Flag="TheSeaMerchantESP",Callback=function(v) settings.merchantEsp=v end})
    Esp:CreateSection("Loot Compass / Route")
    Esp:CreateToggle({Name="Loot Compass",CurrentValue=true,Flag="TheSeaCompass",Callback=function(v) settings.compass=v end})
    Esp:CreateDropdown({Name="Route Target",Options={"Treasure","Any Loot","Wood","Metal","Food","Fuel","Islands","Merchant"},CurrentOption={"Treasure"},MultipleOptions=false,Flag="TheSeaRouteCategory",Callback=function(v) settings.routeCategory=type(v)=="table"and v[1]or tostring(v) end})
    Esp:CreateSlider({Name="Route Length",Range={1,10},Increment=1,CurrentValue=5,Flag="TheSeaRouteCount",Callback=function(v) settings.routeCount=v end})
    Esp:CreateSlider({Name="ESP Distance",Range={500,8000},Increment=250,CurrentValue=3500,Suffix=" studs",Flag="TheSeaESPDistance",Callback=function(v) settings.maxDistance=v end})
    Esp:CreateSlider({Name="Max Treasure",Range={5,80},Increment=5,CurrentValue=40,Flag="TheSeaMaxChests",Callback=function(v) settings.maxChests=v end})
    Esp:CreateSlider({Name="Max Items",Range={10,100},Increment=5,CurrentValue=50,Flag="TheSeaMaxItems",Callback=function(v) settings.maxItems=v end})

    local Visuals = Window:CreateTab("Visuals", "sun")
    Visuals:CreateSection("Local Visuals")
    Visuals:CreateToggle({Name="Fullbright",CurrentValue=false,Flag="TheSeaFullbright",Callback=function(v) settings.fullbright=v end})
    Visuals:CreateToggle({Name="Custom FOV",CurrentValue=false,Flag="TheSeaCustomFOV",Callback=function(v) settings.customFov=v end})
    Visuals:CreateSlider({Name="Field of View",Range={60,120},Increment=1,CurrentValue=85,Suffix="°",Flag="TheSeaFOV",Callback=function(v) settings.fov=v end})
    Visuals:CreateLabel("All lighting and camera changes are restored when the module closes.")

    local Combat = Window:CreateTab("Combat", "crosshair")
    Combat:CreateSection("Creature ESP")
    Combat:CreateToggle({Name="Creature ESP",CurrentValue=true,Flag="TheSeaCreatureESP",Callback=function(v) settings.creatureEsp=v end})
    Combat:CreateToggle({Name="Visible Creatures Only",CurrentValue=false,Flag="TheSeaCreatureVisibleOnly",Callback=function(v) settings.creatureVisibleOnly=v end})
    Combat:CreateSlider({Name="Creature Distance",Range={50,1500},Increment=25,CurrentValue=600,Suffix=" studs",Flag="TheSeaCreatureDistance",Callback=function(v) settings.creatureDistance=v end})
    Combat:CreateSlider({Name="Max Creatures",Range={5,60},Increment=5,CurrentValue=30,Flag="TheSeaMaxCreatures",Callback=function(v) settings.maxCreatures=v end})
    Combat:CreateSection("Machete")
    Combat:CreateToggle({Name="Machete Aura",CurrentValue=false,Flag="TheSeaMeleeAura",Callback=function(v) settings.meleeAura=v end})
    Combat:CreateSlider({Name="Aura Radius",Range={5,25},Increment=1,CurrentValue=12,Suffix=" studs",Flag="TheSeaAuraRadius",Callback=function(v) settings.auraRadius=v end})
    Combat:CreateSlider({Name="Aura Cooldown",Range={0.2,1.5},Increment=0.05,CurrentValue=0.45,Suffix="s",Flag="TheSeaAuraCooldown",Callback=function(v) settings.auraCooldown=v end})
    Combat:CreateSection("Ranged Assist")
    Combat:CreateToggle({Name="Aim Assist (Flintlock / Raygun)",CurrentValue=false,Flag="TheSeaAimAssist",Callback=function(v) settings.aimAssist=v end})
    Combat:CreateToggle({Name="Auto Trigger",CurrentValue=false,Flag="TheSeaAutoTrigger",Callback=function(v) settings.autoTrigger=v end})
    Combat:CreateToggle({Name="Combat Visible Check",CurrentValue=true,Flag="TheSeaCombatVisible",Callback=function(v) settings.combatVisibleCheck=v end})
    Combat:CreateSlider({Name="Aim Smoothness",Range={0.05,0.5},Increment=0.01,CurrentValue=0.18,Flag="TheSeaAimSmooth",Callback=function(v) settings.aimSmoothness=v end})
    Combat:CreateLabel("Harpoon remains target-information only in v1.2; its Fire/Retract state machine is not bypassed.")

    Combat:CreateSection("Diagnostics")
    local combatStatusLabel = Combat:CreateLabel("Weapon: none | Target: none")
    local combatReasonLabel = Combat:CreateLabel("Combat assist: disabled")

    pcall(function() RunService:UnbindFromRenderStep(fovBinding) end)
    RunService:BindToRenderStep(fovBinding, Enum.RenderPriority.Camera.Value + 2, function()
        if not running then return end
        local camera = workspace.CurrentCamera
        if camera and settings.customFov then camera.FieldOfView = settings.fov end
    end)

    local scanAt, statusAt, lastAttackAt = 0, 0, 0
    local lastCandidates = {}
    local lastRoute = {}
    local fullbrightApplied = false
    connect(RunService.Heartbeat, function()
        if not running then return end
        local now = os.clock()
        if now - scanAt >= 0.75 then
            scanAt = now
            lastCandidates, lastRoute = scanWorld()
        end

        local character = localPlayer.Character
        local equipped = character and character:FindFirstChildOfClass("Tool")
        local nearestCreature = nil
        for _, candidate in ipairs(lastCandidates) do
            if candidate.category == "creature" and candidate.part and candidate.part.Parent then
                if not nearestCreature or candidate.distance < nearestCreature.distance then nearestCreature = candidate end
            end
        end
        local weaponName = equipped and equipped.Name or "none"
        local targetOkay = nearestCreature and (not settings.combatVisibleCheck or isVisible(nearestCreature.part))
        local reason = "disabled"
        if equipped and weaponName == "Machete" and settings.meleeAura then
            if targetOkay and nearestCreature.distance <= settings.auraRadius then
                reason = "attacking"
                if now - lastAttackAt >= settings.auraCooldown and equipped.Enabled then
                    lastAttackAt = now
                    pcall(function() equipped:Activate() end)
                end
            else
                reason = nearestCreature and "target out of range/covered" or "no creature"
            end
        elseif equipped and (weaponName == "Flintlock" or weaponName == "Raygun") and (settings.aimAssist or settings.autoTrigger) then
            if targetOkay then
                reason = "tracking"
                if settings.aimAssist and workspace.CurrentCamera then
                    local camera = workspace.CurrentCamera
                    local desired = CFrame.lookAt(camera.CFrame.Position, nearestCreature.part.Position)
                    camera.CFrame = camera.CFrame:Lerp(desired, settings.aimSmoothness)
                end
                if settings.autoTrigger and now - lastAttackAt >= 0.3 and equipped.Enabled then
                    lastAttackAt = now
                    pcall(function() equipped:Activate() end)
                end
            else
                reason = nearestCreature and "target covered" or "no creature"
            end
        elseif equipped and weaponName == "Harpoon" then
            reason = nearestCreature and "target info only" or "no creature"
        end

        if settings.fullbright then
            fullbrightApplied = true
            Lighting.Brightness = 3
            Lighting.Ambient = Color3.fromRGB(190, 190, 190)
            Lighting.OutdoorAmbient = Color3.fromRGB(170, 170, 170)
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            Lighting.ClockTime = 12
        elseif fullbrightApplied then
            fullbrightApplied = false
            for property, value in pairs(originalLighting) do Lighting[property] = value end
        end

        if now - statusAt >= 0.35 then
            statusAt = now
            local food = tonumber(localPlayer:GetAttribute("Food")) or 0
            local o2 = tonumber(localPlayer:GetAttribute("O2")) or 0
            local day = guiText({"HUD", "Day Counter"}, "Day ?")
            local nearest = lastCandidates[1]
            for _, candidate in ipairs(lastCandidates) do
                if not nearest or candidate.distance < nearest.distance then nearest = candidate end
            end
            local warnings = {}
            if food <= settings.foodWarning then table.insert(warnings, "LOW FOOD") end
            if o2 <= settings.o2Warning then table.insert(warnings, "LOW O2") end
            local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
            local toolCounts = {}
            for _, container in ipairs({localPlayer.Character, localPlayer:FindFirstChildOfClass("Backpack")}) do
                if container then
                    for _, tool in ipairs(container:GetChildren()) do
                        if tool:IsA("Tool") then toolCounts[tool.Name] = (toolCounts[tool.Name] or 0) + 1 end
                    end
                end
            end
            local inventoryParts = {}
            for name, amount in pairs(toolCounts) do table.insert(inventoryParts, name .. " x" .. amount) end
            table.sort(inventoryParts)
            local sackMax = 0
            for _, container in ipairs({localPlayer.Character, localPlayer:FindFirstChildOfClass("Backpack")}) do
                if container then
                    for _, tool in ipairs(container:GetChildren()) do
                        if tool:IsA("Tool") and tool:GetAttribute("Max") then
                            sackMax = math.max(sackMax, tonumber(tool:GetAttribute("Max")) or 0)
                        end
                    end
                end
            end
            local routeParts = {}
            for index, candidate in ipairs(lastRoute) do
                table.insert(routeParts, string.format("%d.%s %dm", index, candidate.label, math.floor(candidate.distance)))
            end
            pcall(function()
                survivalLabel:Set(string.format("%s | HP %d | Food %d%% | O2 %d%% | Class %s Lv.%s",
                    day, humanoid and math.floor(humanoid.Health) or 0, math.floor(food), math.floor(o2),
                    tostring(localPlayer:GetAttribute("Class") or "?"), tostring(localPlayer:GetAttribute("ClassLevel") or "?")))
                currencyLabel:Set(string.format("Pearls %s | Doubloons %s | Streak %s | Seed %s",
                    tostring(localPlayer:GetAttribute("Pearls") or 0), tostring(localPlayer:GetAttribute("Doubloons") or 0),
                    tostring(localPlayer:GetAttribute("Streak") or 0), tostring(localPlayer:GetAttribute("DisplaySeed") or "?")))
                objectiveLabel:Set("Objectives: " .. objectiveSummary())
                nearestLabel:Set(nearest and string.format("Nearest: %s (%dm)", nearest.label, math.floor(nearest.distance)) or "Nearest: none in range")
                routeLabel:Set(#routeParts > 0 and ("Route: " .. table.concat(routeParts, " → ")) or "Route: no matching targets")
                inventoryLabel:Set(string.format("Inventory %s/%s | %s", tostring(localPlayer:GetAttribute("GroundItems") or "?"), sackMax > 0 and tostring(sackMax) or "?", #inventoryParts > 0 and table.concat(inventoryParts, ", ") or "empty"))
                warningLabel:Set(#warnings > 0 and ("WARNING: " .. table.concat(warnings, " + ")) or "Warnings: none")
                combatStatusLabel:Set(string.format("Weapon: %s | Target: %s", weaponName,
                    nearestCreature and string.format("%s (%dm)", nearestCreature.label, math.floor(nearestCreature.distance)) or "none"))
                combatReasonLabel:Set("Combat assist: " .. reason)
            end)
        end
    end)

    connect(RunService.RenderStepped, function()
        local target = lastRoute[1]
        local camera = workspace.CurrentCamera
        local valid = running and settings.compass and target and target.part and target.part.Parent and camera
        compassArrow.Visible = valid and true or false
        compassText.Visible = valid and true or false
        if not valid then return end
        local point = camera:WorldToViewportPoint(target.part.Position)
        local center = Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
        local offset = Vector2.new(point.X, point.Y) - center
        if point.Z < 0 then offset = -offset end
        compassArrow.Rotation = math.deg(math.atan2(offset.X, -offset.Y))
        compassArrow.TextColor3 = target.color
        compassText.Text = string.format("%s | %dm", target.label, math.floor(distanceTo(target.part)))
    end)

    local function restoreLighting()
        for property, value in pairs(originalLighting) do Lighting[property] = value end
    end

    local function destroy()
        if not running then return end
        running = false
        pcall(function() RunService:UnbindFromRenderStep(fovBinding) end)
        local camera = workspace.CurrentCamera
        if camera then camera.FieldOfView = originalFov end
        restoreLighting()
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        table.clear(connections)
        for key in pairs(visuals) do removeVisual(key) end
        if espFolder.Parent then espFolder:Destroy() end
        if compassGui.Parent then compassGui:Destroy() end
        if getgenv().__RAVEN_THE_SEA and getgenv().__RAVEN_THE_SEA.Settings == settings then
            getgenv().__RAVEN_THE_SEA = nil
        end
    end

    getgenv().__RAVEN_THE_SEA = {
        Settings = settings,
        Refresh = scanWorld,
        Destroy = destroy,
    }
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end
end
