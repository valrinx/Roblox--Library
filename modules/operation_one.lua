--[[
    RAVEN HUB | [SEASON 3] Operation One
    PlaceId: 72920620366355 | GameId: 8307114974
    Version: v1.0

    Cleanup-safe tactical awareness using replicated player, gadget, and HUD state.
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
    local playerVisuals = {}
    local gadgetVisuals = {}
    local originalFov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
    local originalFlashTransparency = nil
    local fovBinding = "RavenOperationOneFOV_" .. tostring(localPlayer.UserId)

    local folder = Instance.new("Folder")
    folder.Name = "RavenOperationOneESP"
    folder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local settings = {
        enemyEsp = true,
        visibleCheck = true,
        throughWalls = true,
        showHealth = true,
        showDistance = true,
        maxDistance = 1200,
        bombEsp = true,
        gadgetEsp = true,
        enemyGadgetsOnly = true,
        flashReduction = false,
        customFov = false,
        fov = 85,
    }

    local gadgetStyles = {
        Bomb = {color = Color3.fromRGB(255, 205, 65), label = "BOMB"},
        Claymore = {color = Color3.fromRGB(255, 75, 75), label = "CLAYMORE"},
        Drone = {color = Color3.fromRGB(90, 190, 255), label = "DRONE"},
        Reinforcement = {color = Color3.fromRGB(190, 130, 255), label = "REINFORCEMENT"},
    }

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function characterRoot(character)
        return character and (character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("collision")
            or character.PrimaryPart
            or character:FindFirstChildWhichIsA("BasePart", true))
    end

    local function modelRoot(model)
        return model and (model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Root")
            or model.PrimaryPart
            or model:FindFirstChildWhichIsA("BasePart", true))
    end

    local function humanoidOf(player)
        return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    end

    local function isEnemy(player)
        if not player or player == localPlayer then return false end
        if localPlayer.Team == nil or player.Team == nil then return true end
        return player.Team ~= localPlayer.Team
    end

    local function isVisible(model, part)
        local camera = workspace.CurrentCamera
        if not camera or not model or not part then return false end
        local filter = {camera, folder}
        if localPlayer.Character then table.insert(filter, localPlayer.Character) end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = filter
        local result = workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
        return result == nil or result.Instance:IsDescendantOf(model)
    end

    local function destroyVisual(store, key)
        local visual = store[key]
        if not visual then return end
        if visual.highlight then visual.highlight:Destroy() end
        if visual.billboard then visual.billboard:Destroy() end
        store[key] = nil
    end

    local function createVisual(store, key, model, part, color, name)
        local existing = store[key]
        if existing and existing.model == model then return existing end
        destroyVisual(store, key)

        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenOperationOneHighlight"
        highlight.Adornee = model
        highlight.FillColor = color
        highlight.OutlineColor = color
        highlight.FillTransparency = 0.78
        highlight.OutlineTransparency = 0.05
        highlight.DepthMode = settings.throughWalls
            and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded
        highlight.Parent = folder

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenOperationOneLabel"
        billboard.Adornee = part
        billboard.AlwaysOnTop = settings.throughWalls
        billboard.MaxDistance = settings.maxDistance
        billboard.Size = UDim2.fromOffset(230, 46)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.Parent = folder

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamSemibold
        label.TextSize = 13
        label.TextStrokeTransparency = 0.25
        label.TextColor3 = color
        label.Text = name
        label.Parent = billboard

        local visual = {model = model, highlight = highlight, billboard = billboard, label = label}
        store[key] = visual
        return visual
    end

    local function updatePlayers()
        local active = {}
        local myRoot = characterRoot(localPlayer.Character)
        for _, player in ipairs(Players:GetPlayers()) do
            if settings.enemyEsp and isEnemy(player) then
                local character = player.Character
                local root = characterRoot(character)
                local humanoid = humanoidOf(player)
                if character and root and humanoid and humanoid.Health > 0 then
                    active[player] = true
                    local visual = createVisual(
                        playerVisuals,
                        player,
                        character,
                        root,
                        Color3.fromRGB(255, 75, 85),
                        player.DisplayName or player.Name
                    )
                    local visible = not settings.visibleCheck or isVisible(character, root)
                    visual.highlight.Enabled = visible
                    visual.billboard.Enabled = visible
                    visual.highlight.DepthMode = settings.throughWalls
                        and Enum.HighlightDepthMode.AlwaysOnTop
                        or Enum.HighlightDepthMode.Occluded
                    visual.billboard.AlwaysOnTop = settings.throughWalls
                    visual.billboard.MaxDistance = settings.maxDistance
                    if visible then
                        local rows = {player.DisplayName or player.Name}
                        if settings.showHealth then
                            table.insert(rows, string.format("HP %d", math.floor(humanoid.Health)))
                        end
                        if settings.showDistance and myRoot then
                            table.insert(rows, string.format("%dm", math.floor((root.Position - myRoot.Position).Magnitude)))
                        end
                        visual.label.Text = table.concat(rows, " | ")
                    end
                end
            end
        end
        for player in pairs(playerVisuals) do
            if not active[player] then destroyVisual(playerVisuals, player) end
        end
    end

    local function gadgetOwner(model)
        local state = model:FindFirstChild("StateObject")
        local ownerValue = state and state:FindFirstChild("owner")
        return ownerValue and ownerValue:IsA("ObjectValue") and ownerValue.Value or nil
    end

    local function gadgetAllowed(model)
        if model.Name == "Bomb" then return settings.bombEsp end
        if not settings.gadgetEsp then return false end
        if not settings.enemyGadgetsOnly then return true end
        local owner = gadgetOwner(model)
        return owner == nil or isEnemy(owner)
    end

    local function gadgetState(model)
        if model.Name == "Claymore" then
            local armed = model:FindFirstChild("armed", true)
            return armed and armed:IsA("BoolValue") and (armed.Value and "ARMED" or "SAFE") or nil
        elseif model.Name == "Drone" then
            local disabled = model:FindFirstChild("disabled", true)
            return disabled and disabled:IsA("NumberValue") and disabled.Value > 0 and "DISABLED" or "ACTIVE"
        elseif model.Name == "Bomb" then
            local enabled = model:FindFirstChild("enabled", true)
            return enabled and enabled:IsA("BoolValue") and (enabled.Value and "ACTIVE" or "DROPPED") or nil
        end
        return nil
    end

    local function updateGadgets()
        local active = {}
        local myRoot = characterRoot(localPlayer.Character)
        for _, model in ipairs(workspace:GetChildren()) do
            local style = gadgetStyles[model.Name]
            if style and model:IsA("Model") and gadgetAllowed(model) then
                local root = modelRoot(model)
                if root then
                    active[model] = true
                    local visual = createVisual(gadgetVisuals, model, model, root, style.color, style.label)
                    visual.highlight.Enabled = true
                    visual.billboard.Enabled = true
                    visual.highlight.DepthMode = settings.throughWalls
                        and Enum.HighlightDepthMode.AlwaysOnTop
                        or Enum.HighlightDepthMode.Occluded
                    visual.billboard.AlwaysOnTop = settings.throughWalls
                    visual.billboard.MaxDistance = settings.maxDistance
                    local rows = {style.label}
                    local owner = gadgetOwner(model)
                    if owner then table.insert(rows, owner.DisplayName or owner.Name) end
                    local state = gadgetState(model)
                    if state then table.insert(rows, state) end
                    if settings.showDistance and myRoot then
                        table.insert(rows, string.format("%dm", math.floor((root.Position - myRoot.Position).Magnitude)))
                    end
                    visual.label.Text = table.concat(rows, " | ")
                end
            end
        end
        for model in pairs(gadgetVisuals) do
            if not active[model] then destroyVisual(gadgetVisuals, model) end
        end
    end

    local function guiText(path, fallback)
        local current = localPlayer:FindFirstChildOfClass("PlayerGui")
        for _, name in ipairs(path) do
            current = current and current:FindFirstChild(name)
        end
        if not current then return fallback end
        local ok, value = pcall(function() return current.Text end)
        return ok and value ~= "" and value or fallback
    end

    local Dashboard = Window:CreateTab("Dashboard", "activity")
    Dashboard:CreateSection("Live Match")
    local matchLabel = Dashboard:CreateLabel("Match: scanning...")
    local objectiveLabel = Dashboard:CreateLabel("Objective: scanning...")
    local playerLabel = Dashboard:CreateLabel("Player: scanning...")
    local gadgetLabel = Dashboard:CreateLabel("Gadgets: scanning...")

    local EspTab = Window:CreateTab("ESP", "eye")
    EspTab:CreateSection("Enemy ESP")
    EspTab:CreateToggle({Name="Enemy ESP",CurrentValue=true,Flag="OperationOneEnemyESP",Callback=function(v) settings.enemyEsp=v end})
    EspTab:CreateToggle({Name="Visible Check",CurrentValue=true,Flag="OperationOneVisibleCheck",Callback=function(v) settings.visibleCheck=v end})
    EspTab:CreateToggle({Name="Through Walls",CurrentValue=true,Flag="OperationOneThroughWalls",Callback=function(v) settings.throughWalls=v end})
    EspTab:CreateToggle({Name="Show Health",CurrentValue=true,Flag="OperationOneShowHealth",Callback=function(v) settings.showHealth=v end})
    EspTab:CreateToggle({Name="Show Distance",CurrentValue=true,Flag="OperationOneShowDistance",Callback=function(v) settings.showDistance=v end})
    EspTab:CreateSlider({Name="ESP Distance",Range={100,2500},Increment=50,CurrentValue=1200,Suffix=" studs",Flag="OperationOneESPDistance",Callback=function(v) settings.maxDistance=v end})
    EspTab:CreateSection("Objective / Gadgets")
    EspTab:CreateToggle({Name="Bomb ESP",CurrentValue=true,Flag="OperationOneBombESP",Callback=function(v) settings.bombEsp=v end})
    EspTab:CreateToggle({Name="Gadget ESP",CurrentValue=true,Flag="OperationOneGadgetESP",Callback=function(v) settings.gadgetEsp=v end})
    EspTab:CreateToggle({Name="Enemy Gadgets Only",CurrentValue=true,Flag="OperationOneEnemyGadgets",Callback=function(v) settings.enemyGadgetsOnly=v end})

    local Visuals = Window:CreateTab("Visuals", "sun")
    Visuals:CreateSection("Camera")
    Visuals:CreateToggle({Name="Custom FOV",CurrentValue=false,Flag="OperationOneCustomFOV",Callback=function(v) settings.customFov=v end})
    Visuals:CreateSlider({Name="Field of View",Range={60,120},Increment=1,CurrentValue=85,Suffix="°",Flag="OperationOneFOV",Callback=function(v) settings.fov=v end})
    Visuals:CreateToggle({Name="Flash Reduction",CurrentValue=false,Flag="OperationOneFlashReduction",Callback=function(v) settings.flashReduction=v end})
    Visuals:CreateLabel("Flash Reduction only changes the local full-screen flash overlay.")

    pcall(function() RunService:UnbindFromRenderStep(fovBinding) end)
    RunService:BindToRenderStep(fovBinding, Enum.RenderPriority.Camera.Value + 2, function()
        if not running then return end
        local camera = workspace.CurrentCamera
        if camera and settings.customFov then camera.FieldOfView = settings.fov end
    end)

    local scanAt, statusAt = 0, 0
    connect(RunService.Heartbeat, function()
        if not running then return end
        local now = os.clock()
        if now - scanAt >= 0.2 then
            scanAt = now
            updatePlayers()
            updateGadgets()
        end

        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        local flash = playerGui and playerGui:FindFirstChild("Flash")
        local flashFrame = flash and flash:FindFirstChild("Frame")
        if flashFrame then
            if originalFlashTransparency == nil then originalFlashTransparency = flashFrame.BackgroundTransparency end
            flashFrame.BackgroundTransparency = settings.flashReduction and 1 or originalFlashTransparency
        end

        if now - statusAt >= 0.35 then
            statusAt = now
            local map = guiText({"Game","Center","Center","Scoreboard","Folder","MapTitle"}, "?")
            local blue = guiText({"Game","Center","Center","Scoreboard","Folder","BlueTeamBanner","Score"}, "?")
            local red = guiText({"Game","Center","Center","Scoreboard","Folder","RedTeamBanner","Score"}, "?")
            local round = guiText({"Game","Center","Center","MatchAnnouncement","Title"}, "Round ?")
            local objective = guiText({"Game","Center","Center","MatchAnnouncement","Subtitle"}, "Objective unavailable")
            local zone = guiText({"Game","Center","Bottom","Zone"}, "Unknown zone")
            local gadgetCount, bombCount = 0, 0
            for _, model in ipairs(workspace:GetChildren()) do
                if gadgetStyles[model.Name] then
                    gadgetCount += 1
                    if model.Name == "Bomb" then bombCount += 1 end
                end
            end
            pcall(function()
                matchLabel:Set(string.format("%s | %s | Blue %s - %s Red", map, round, blue, red))
                objectiveLabel:Set(string.format("%s | Zone: %s", objective, zone))
                playerLabel:Set(string.format("K/D/A %s/%s/%s | Points %s | Ping %sms",
                    tostring(localPlayer:GetAttribute("Kills") or 0),
                    tostring(localPlayer:GetAttribute("Deaths") or 0),
                    tostring(localPlayer:GetAttribute("Assists") or 0),
                    tostring(localPlayer:GetAttribute("Points") or 0),
                    tostring(localPlayer:GetAttribute("Ping") or "?")))
                gadgetLabel:Set(string.format("Tracked objects: %d | Bombs: %d", gadgetCount, bombCount))
            end)
        end
    end)

    connect(Players.PlayerRemoving, function(player)
        destroyVisual(playerVisuals, player)
    end)

    local function destroy()
        if not running then return end
        running = false
        pcall(function() RunService:UnbindFromRenderStep(fovBinding) end)
        local camera = workspace.CurrentCamera
        if camera then camera.FieldOfView = originalFov end
        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        local flash = playerGui and playerGui:FindFirstChild("Flash")
        local flashFrame = flash and flash:FindFirstChild("Frame")
        if flashFrame and originalFlashTransparency ~= nil then
            flashFrame.BackgroundTransparency = originalFlashTransparency
        end
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        table.clear(connections)
        for player in pairs(playerVisuals) do destroyVisual(playerVisuals, player) end
        for model in pairs(gadgetVisuals) do destroyVisual(gadgetVisuals, model) end
        if folder.Parent then folder:Destroy() end
        if getgenv().__RAVEN_OPERATION_ONE and getgenv().__RAVEN_OPERATION_ONE.Settings == settings then
            getgenv().__RAVEN_OPERATION_ONE = nil
        end
    end

    getgenv().__RAVEN_OPERATION_ONE = {
        Settings = settings,
        Refresh = function() updatePlayers(); updateGadgets() end,
        Destroy = destroy,
    }
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end
end
