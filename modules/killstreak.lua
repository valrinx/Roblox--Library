--[[
    RAVEN HUB | KILLSTREAK!
    PlaceId: 104856666707760 | GameId: 9705384247
    Version: v1.3

    Read-only match awareness for the live KILLSTREAK! experience:
    Hill HUD tracking, player/team ESP, party status, equipment overview,
    and lightweight match diagnostics. No remotes are fired.
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Stats = game:GetService("Stats")
    local CoreGui = game:GetService("CoreGui")
    local UserInputService = game:GetService("UserInputService")

    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}
    local espObjects = {}
    local lockedTarget = nil
    local aimBindingName = "RavenKillstreakAim_" .. tostring(localPlayer.UserId)
    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenKillstreakESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local settings = {
        playerEsp = true,
        showTeam = true,
        showHealth = true,
        showDistance = true,
        throughWalls = true,
        espVisibleCheck = true,
        maxDistance = 1000,
        showHill = true,
        showEquipment = true,
        autoLock = false,
        aimPart = "Head",
        aimFov = 180,
        aimSmoothness = 0.2,
        aimWallCheck = true,
        aimActivation = "Right Mouse",
    }

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function safeText(instance, fallback)
        if not instance then return fallback end
        local ok, value = pcall(function() return instance.Text end)
        return ok and type(value) == "string" and value ~= "" and value or fallback
    end

    local function getCharacter(player)
        return player and player.Character
    end

    local function getRoot(player)
        local character = getCharacter(player)
        return character and character:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid(player)
        local character = getCharacter(player)
        return character and character:FindFirstChildOfClass("Humanoid")
    end

    local function getEquippedTool(player)
        local character = getCharacter(player)
        local equipped = character and character:FindFirstChildOfClass("Tool")
        return equipped and equipped.Name or "Unarmed"
    end

    local function getTeamColor(player)
        local team = player and player.Team
        if team and team.TeamColor then return team.TeamColor.Color end
        return Color3.fromRGB(225, 225, 235)
    end

    local function displayTeam(player)
        return settings.showTeam and (player.Team and player.Team.Name or "Neutral") or nil
    end

    local function isTeammate(player)
        return player ~= nil
            and player ~= localPlayer
            and localPlayer.Team ~= nil
            and player.Team == localPlayer.Team
    end

    local function getAimPart(player)
        local character = getCharacter(player)
        if not character then return nil end
        if settings.aimPart == "Head" then
            return character:FindFirstChild("Head") or getRoot(player)
        end
        return character:FindFirstChild("HumanoidRootPart") or getRoot(player)
    end

    local function isAimTargetValid(player)
        local humanoid = getHumanoid(player)
        return player ~= localPlayer
            and not isTeammate(player)
            and humanoid ~= nil
            and humanoid.Health > 0
            and getAimPart(player) ~= nil
    end

    local function traceVisible(player, part)
        local camera = workspace.CurrentCamera
        if not camera or not part then return false end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local filter = {camera}
        if localPlayer.Character then table.insert(filter, localPlayer.Character) end
        params.FilterDescendantsInstances = filter
        local result = workspace:Raycast(camera.CFrame.Position, part.Position - camera.CFrame.Position, params)
        return result == nil or result.Instance:IsDescendantOf(player.Character)
    end

    local function targetVisible(player, part)
        return not settings.aimWallCheck or traceVisible(player, part)
    end

    local function aimActivationHeld()
        if settings.aimActivation == "Always" then return true end
        local inputType = settings.aimActivation == "Left Mouse"
            and Enum.UserInputType.MouseButton1
            or Enum.UserInputType.MouseButton2
        return UserInputService:IsMouseButtonPressed(inputType)
    end

    local function targetScreenDistance(player)
        local camera = workspace.CurrentCamera
        local part = getAimPart(player)
        if not camera or not part then return nil end
        local point, onScreen = camera:WorldToViewportPoint(part.Position)
        if not onScreen or point.Z <= 0 or not targetVisible(player, part) then return nil end
        local center = Vector2.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5)
        return (Vector2.new(point.X, point.Y) - center).Magnitude
    end

    local function getBestAimTarget()
        local best, bestDistance = nil, settings.aimFov
        for _, player in ipairs(Players:GetPlayers()) do
            if isAimTargetValid(player) then
                local distance = targetScreenDistance(player)
                if distance and distance < bestDistance then
                    best, bestDistance = player, distance
                end
            end
        end
        return best
    end

    local function refreshAimTarget(player)
        if not isAimTargetValid(player) then return nil end
        local distance = targetScreenDistance(player)
        return distance and distance <= settings.aimFov and player or nil
    end

    local function aimAt(player, deltaTime)
        local camera = workspace.CurrentCamera
        local part = getAimPart(player)
        if not camera or not part then return end
        local origin = camera.CFrame.Position
        if (part.Position - origin).Magnitude <= 0.01 then return end
        local goal = CFrame.lookAt(origin, part.Position)
        local strength = math.clamp(settings.aimSmoothness, 0.03, 1)
        local alpha = 1 - math.pow(1 - strength, math.max(deltaTime * 60, 0.01))
        camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
    end

    local function clearPlayerEsp(player)
        local entry = espObjects[player]
        if not entry then return end
        if entry.highlight then entry.highlight:Destroy() end
        if entry.billboard then entry.billboard:Destroy() end
        espObjects[player] = nil
    end

    local function ensurePlayerEsp(player)
        if player == localPlayer then return end
        if isTeammate(player) then
            clearPlayerEsp(player)
            return
        end
        if not settings.playerEsp then
            clearPlayerEsp(player)
            return
        end
        local character = getCharacter(player)
        local root = getRoot(player)
        if not character or not root then
            clearPlayerEsp(player)
            return
        end

        local entry = espObjects[player]
        if entry and entry.character == character then return entry end
        clearPlayerEsp(player)

        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenKillstreakPlayer"
        highlight.Adornee = character
        highlight.FillColor = getTeamColor(player)
        highlight.FillTransparency = 0.78
        highlight.OutlineColor = getTeamColor(player)
        highlight.OutlineTransparency = 0.15
        highlight.DepthMode = settings.throughWalls
            and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded
        highlight.Parent = espFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenKillstreakLabel"
        billboard.Adornee = root
        billboard.AlwaysOnTop = settings.throughWalls
        billboard.Size = UDim2.fromOffset(220, 48)
        billboard.StudsOffset = Vector3.new(0, 3.2, 0)
        billboard.MaxDistance = settings.maxDistance
        billboard.Parent = espFolder

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Size = UDim2.fromScale(1, 1)
        label.Font = Enum.Font.GothamSemibold
        label.TextSize = 13
        label.TextStrokeTransparency = 0.25
        label.TextColor3 = getTeamColor(player)
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.Parent = billboard

        entry = {character = character, highlight = highlight, billboard = billboard, label = label}
        espObjects[player] = entry
        return entry
    end

    local function updatePlayerEsp(player, localRoot)
        local entry = ensurePlayerEsp(player)
        if not entry then return false end
        local root = getRoot(player)
        local humanoid = getHumanoid(player)
        if not root or not humanoid or humanoid.Health <= 0 then
            clearPlayerEsp(player)
            return false
        end

        local visible = not settings.espVisibleCheck or traceVisible(player, root)
        entry.highlight.Enabled = visible
        entry.billboard.Enabled = visible
        if not visible then return false end

        local distance = localRoot and (localRoot.Position - root.Position).Magnitude or nil
        entry.highlight.FillColor = getTeamColor(player)
        entry.highlight.OutlineColor = getTeamColor(player)
        entry.highlight.DepthMode = settings.throughWalls
            and Enum.HighlightDepthMode.AlwaysOnTop
            or Enum.HighlightDepthMode.Occluded
        entry.billboard.Adornee = root
        entry.billboard.AlwaysOnTop = settings.throughWalls
        entry.billboard.MaxDistance = settings.maxDistance

        local rows = {player.DisplayName or player.Name}
        local team = displayTeam(player)
        if team then table.insert(rows, "[" .. team .. "]") end
        if settings.showHealth then
            table.insert(rows, string.format("HP %d/%d", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth)))
        end
        if settings.showDistance and distance then
            table.insert(rows, string.format("%dm", math.floor(distance)))
        end
        entry.label.Text = table.concat(rows, " | ")
        entry.label.TextColor3 = getTeamColor(player)
        return true
    end

    local function getHillStatus()
        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        local hillGui = playerGui and playerGui:FindFirstChild("the Hill")
        local frame = hillGui and hillGui:FindFirstChild("Frame")
        local ownerText = frame and frame:FindFirstChild("ZoneOwnerText")
        local progress = frame and frame:FindFirstChild("ProgressBar")
        local canvas = progress and progress:FindFirstChild("CanvasGroup")
        local fill = canvas and canvas:FindFirstChild("Frame")
        local owner = safeText(ownerText, "Hill HUD unavailable")
        local percent = nil
        if fill and progress then
            local ok, value = pcall(function()
                local width = progress.AbsoluteSize.X
                return width > 0 and math.clamp(fill.AbsoluteSize.X / width, 0, 1) or nil
            end)
            if ok then percent = value end
        end
        return owner, percent
    end

    local function getPing()
        local ok, value = pcall(function()
            local item = Stats.Network.ServerStatsItem["Data Ping"]
            return item and item:GetValue()
        end)
        return ok and tonumber(value) or nil
    end

    local function getEquipment()
        local names, seen = {}, {}
        local character = getCharacter(localPlayer)
        local backpack = localPlayer:FindFirstChildOfClass("Backpack")
        for _, container in ipairs({character, backpack}) do
            if container then
                for _, item in ipairs(container:GetChildren()) do
                    if item:IsA("Tool") and not seen[item.Name] then
                        seen[item.Name] = true
                        table.insert(names, item.Name)
                    end
                end
            end
        end
        table.sort(names)
        return #names > 0 and table.concat(names, ", ") or "No equipment detected"
    end

    local HillTab = Window:CreateTab("Hill", "flag")
    HillTab:CreateSection("Live Objective")
    local hillStatus = HillTab:CreateLabel("Hill: loading...")
    local hillProgress = HillTab:CreateLabel("Progress: —")
    HillTab:CreateToggle({
        Name = "Show Hill Tracker",
        CurrentValue = true,
        Flag = "KillstreakShowHill",
        Callback = function(value) settings.showHill = value end,
    })
    HillTab:CreateLabel("Reads the active The Hill HUD locally; no gameplay remotes are used.")

    local PlayersTab = Window:CreateTab("Players", "users")
    PlayersTab:CreateSection("Player ESP")
    local playerStatus = PlayersTab:CreateLabel("Players: scanning...")
    PlayersTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = true,
        Flag = "KillstreakPlayerESP",
        Callback = function(value) settings.playerEsp = value end,
    })
    PlayersTab:CreateToggle({
        Name = "Through Walls",
        CurrentValue = true,
        Flag = "KillstreakThroughWalls",
        Callback = function(value) settings.throughWalls = value end,
    })
    PlayersTab:CreateToggle({
        Name = "Visible Check",
        CurrentValue = true,
        Flag = "KillstreakESPVisibleCheck",
        Callback = function(value) settings.espVisibleCheck = value end,
    })
    PlayersTab:CreateToggle({
        Name = "Show Team",
        CurrentValue = true,
        Flag = "KillstreakShowTeam",
        Callback = function(value) settings.showTeam = value end,
    })
    PlayersTab:CreateToggle({
        Name = "Show Health",
        CurrentValue = true,
        Flag = "KillstreakShowHealth",
        Callback = function(value) settings.showHealth = value end,
    })
    PlayersTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "KillstreakShowDistance",
        Callback = function(value) settings.showDistance = value end,
    })
    PlayersTab:CreateSlider({
        Name = "ESP Distance",
        Range = {100, 2000},
        Increment = 50,
        CurrentValue = 1000,
        Suffix = " studs",
        Flag = "KillstreakESPDistance",
        Callback = function(value) settings.maxDistance = value end,
    })

    local CombatTab = Window:CreateTab("Combat", "target")
    CombatTab:CreateSection("Smooth Auto Lock")
    CombatTab:CreateToggle({
        Name = "Auto Lock",
        CurrentValue = false,
        Flag = "KillstreakAutoLock",
        Callback = function(value)
            settings.autoLock = value
            lockedTarget = value and getBestAimTarget() or nil
        end,
    })
    CombatTab:CreateDropdown({
        Name = "Aim Part",
        Options = {"Head", "HumanoidRootPart"},
        CurrentOption = {"Head"},
        MultipleOptions = false,
        Flag = "KillstreakAimPart",
        Callback = function(value)
            settings.aimPart = type(value) == "table" and value[1] or tostring(value)
            lockedTarget = nil
        end,
    })
    CombatTab:CreateDropdown({
        Name = "Lock Button",
        Options = {"Left Mouse", "Right Mouse", "Always"},
        CurrentOption = {"Right Mouse"},
        MultipleOptions = false,
        Flag = "KillstreakAimActivation",
        Callback = function(value)
            settings.aimActivation = type(value) == "table" and value[1] or tostring(value)
            lockedTarget = nil
        end,
    })
    CombatTab:CreateSlider({
        Name = "Lock FOV",
        Range = {40, 500},
        Increment = 10,
        CurrentValue = 180,
        Suffix = " px",
        Flag = "KillstreakAimFOV",
        Callback = function(value) settings.aimFov = value end,
    })
    CombatTab:CreateSlider({
        Name = "Aim Speed",
        Range = {3, 100},
        Increment = 1,
        CurrentValue = 20,
        Suffix = "%",
        Flag = "KillstreakAimSpeed",
        Callback = function(value) settings.aimSmoothness = value / 100 end,
    })
    CombatTab:CreateToggle({
        Name = "Visible Check",
        CurrentValue = true,
        Flag = "KillstreakAimWallCheck",
        Callback = function(value)
            settings.aimWallCheck = value
            lockedTarget = nil
        end,
    })
    CombatTab:CreateLabel("Targets enemies only and keeps the current target while it remains inside the FOV.")

    local InfoTab = Window:CreateTab("Match Info", "activity")
    InfoTab:CreateSection("Match Dashboard")
    local matchStatus = InfoTab:CreateLabel("Match: loading...")
    local teamStatus = InfoTab:CreateLabel("Team: loading...")
    local equipmentStatus = InfoTab:CreateLabel("Equipment: loading...")
    local diagnosticsStatus = InfoTab:CreateLabel("Diagnostics: loading...")
    InfoTab:CreateToggle({
        Name = "Show Equipment",
        CurrentValue = true,
        Flag = "KillstreakShowEquipment",
        Callback = function(value) settings.showEquipment = value end,
    })

    local scanAt = 0
    local statusAt = 0
    pcall(function() RunService:UnbindFromRenderStep(aimBindingName) end)
    RunService:BindToRenderStep(aimBindingName, 10000, function(deltaTime)
        if not running then return end
        if not settings.autoLock or not aimActivationHeld() then
            lockedTarget = nil
            return
        end
        lockedTarget = refreshAimTarget(lockedTarget) or getBestAimTarget()
        if lockedTarget then aimAt(lockedTarget, deltaTime) end
    end)

    connect(RunService.Heartbeat, function()
        if not running then return end
        local now = os.clock()
        local localRoot = getRoot(localPlayer)

        if now - scanAt >= 0.35 then
            scanAt = now
            local alive, enemies, nearestName, nearestDistance = 0, 0, "none", math.huge
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer then
                    local humanoid = getHumanoid(player)
                    local root = getRoot(player)
                    if humanoid and humanoid.Health > 0 and root then
                        alive += 1
                        if player.Team ~= localPlayer.Team then enemies += 1 end
                        local distance = localRoot and (localRoot.Position - root.Position).Magnitude or math.huge
                        if distance < nearestDistance then
                            nearestDistance, nearestName = distance, player.DisplayName or player.Name
                        end
                    end
                    updatePlayerEsp(player, localRoot)
                end
            end
            for player in pairs(espObjects) do
                if not player.Parent then clearPlayerEsp(player) end
            end
            pcall(function()
                playerStatus:Set(string.format("Alive: %d | Enemies: %d | Nearest: %s (%dm)",
                    alive, enemies, nearestName, nearestDistance < math.huge and math.floor(nearestDistance) or 0))
            end)
        end

        if now - statusAt >= 0.35 then
            statusAt = now
            local owner, percent = getHillStatus()
            local teamName = localPlayer.Team and localPlayer.Team.Name or "Neutral"
            local humanoid = getHumanoid(localPlayer)
            local health = humanoid and string.format("%d/%d", math.floor(humanoid.Health), math.floor(humanoid.MaxHealth)) or "?"
            local equipped = getEquippedTool(localPlayer)
            local ping = getPing()
            pcall(function()
                hillStatus:Set(settings.showHill and ("Hill: " .. owner) or "Hill: hidden")
                hillProgress:Set(settings.showHill and (percent and string.format("Progress: %d%%", math.floor(percent * 100)) or "Progress: —") or "Progress: hidden")
                matchStatus:Set("Health: " .. health .. " | Equipped: " .. equipped)
                teamStatus:Set("Team: " .. teamName .. " | Players: " .. tostring(#Players:GetPlayers()))
                equipmentStatus:Set(settings.showEquipment and ("Equipment: " .. getEquipment()) or "Equipment: hidden")
                diagnosticsStatus:Set("Ping: " .. (ping and string.format("%dms", math.floor(ping)) or "?") .. " | ESP: " .. tostring(settings.playerEsp))
            end)
        end
    end)

    connect(Players.PlayerRemoving, function(player)
        clearPlayerEsp(player)
    end)

    local function destroy()
        if not running then return end
        running = false
        pcall(function() RunService:UnbindFromRenderStep(aimBindingName) end)
        lockedTarget = nil
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
        for player in pairs(espObjects) do clearPlayerEsp(player) end
        if espFolder.Parent then espFolder:Destroy() end
        if getgenv().__RAVEN_KILLSTREAK
            and getgenv().__RAVEN_KILLSTREAK.Settings == settings then
            getgenv().__RAVEN_KILLSTREAK = nil
        end
    end

    getgenv().__RAVEN_KILLSTREAK = {
        Settings = settings,
        Destroy = destroy,
        Refresh = function()
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer then updatePlayerEsp(player, getRoot(localPlayer)) end
            end
        end,
        GetHillStatus = getHillStatus,
    }
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end
end
