--[[
    RAVEN HUB | The Sea
    PlaceId: 139802517550914 | GameId: 9167377564
    Version: v1.0

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
        return candidates
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
    Dashboard:CreateSection("Live Status")
    local survivalLabel = Dashboard:CreateLabel("Survival: loading...")
    local currencyLabel = Dashboard:CreateLabel("Currency: loading...")
    local objectiveLabel = Dashboard:CreateLabel("Objectives: loading...")
    local nearestLabel = Dashboard:CreateLabel("Nearest: scanning...")
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
    Esp:CreateSlider({Name="ESP Distance",Range={500,8000},Increment=250,CurrentValue=3500,Suffix=" studs",Flag="TheSeaESPDistance",Callback=function(v) settings.maxDistance=v end})
    Esp:CreateSlider({Name="Max Treasure",Range={5,80},Increment=5,CurrentValue=40,Flag="TheSeaMaxChests",Callback=function(v) settings.maxChests=v end})
    Esp:CreateSlider({Name="Max Items",Range={10,100},Increment=5,CurrentValue=50,Flag="TheSeaMaxItems",Callback=function(v) settings.maxItems=v end})

    local Visuals = Window:CreateTab("Visuals", "sun")
    Visuals:CreateSection("Local Visuals")
    Visuals:CreateToggle({Name="Fullbright",CurrentValue=false,Flag="TheSeaFullbright",Callback=function(v) settings.fullbright=v end})
    Visuals:CreateToggle({Name="Custom FOV",CurrentValue=false,Flag="TheSeaCustomFOV",Callback=function(v) settings.customFov=v end})
    Visuals:CreateSlider({Name="Field of View",Range={60,120},Increment=1,CurrentValue=85,Suffix="°",Flag="TheSeaFOV",Callback=function(v) settings.fov=v end})
    Visuals:CreateLabel("All lighting and camera changes are restored when the module closes.")

    pcall(function() RunService:UnbindFromRenderStep(fovBinding) end)
    RunService:BindToRenderStep(fovBinding, Enum.RenderPriority.Camera.Value + 2, function()
        if not running then return end
        local camera = workspace.CurrentCamera
        if camera and settings.customFov then camera.FieldOfView = settings.fov end
    end)

    local scanAt, statusAt = 0, 0
    local lastCandidates = {}
    local fullbrightApplied = false
    connect(RunService.Heartbeat, function()
        if not running then return end
        local now = os.clock()
        if now - scanAt >= 0.75 then
            scanAt = now
            lastCandidates = scanWorld()
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
            pcall(function()
                survivalLabel:Set(string.format("%s | HP %d | Food %d%% | O2 %d%% | Class %s Lv.%s",
                    day, humanoid and math.floor(humanoid.Health) or 0, math.floor(food), math.floor(o2),
                    tostring(localPlayer:GetAttribute("Class") or "?"), tostring(localPlayer:GetAttribute("ClassLevel") or "?")))
                currencyLabel:Set(string.format("Pearls %s | Doubloons %s | Streak %s | Seed %s",
                    tostring(localPlayer:GetAttribute("Pearls") or 0), tostring(localPlayer:GetAttribute("Doubloons") or 0),
                    tostring(localPlayer:GetAttribute("Streak") or 0), tostring(localPlayer:GetAttribute("DisplaySeed") or "?")))
                objectiveLabel:Set("Objectives: " .. objectiveSummary())
                nearestLabel:Set(nearest and string.format("Nearest: %s (%dm)", nearest.label, math.floor(nearest.distance)) or "Nearest: none in range")
                warningLabel:Set(#warnings > 0 and ("WARNING: " .. table.concat(warnings, " + ")) or "Warnings: none")
            end)
        end
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
