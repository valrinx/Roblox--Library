-- ============================================================
--   RAVEN HUB | The Walking Dead Online 3
--   Player ESP + Spectate
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")

    local localPlayer = Players.LocalPlayer
    local camera = workspace.CurrentCamera
    local scriptRunning = true
    local cleanupConnections = {}
    local playerConnections = {}
    local espRecords = {}
    local playerByLabel = {}
    local selectedUserId = nil
    local spectateEnabled = false
    local spectateCharacterConnection = nil

    local settings = {
        espEnabled = false,
        showNames = true,
        showDistance = true,
        showHealth = true,
        useTeamColor = true,
        maxDistance = 2500,
    }

    local function notify(title, content)
        local Rayfield = scriptInfo and scriptInfo.hubRayfield
        if not Rayfield or type(Rayfield.Notify) ~= "function" then
            return
        end

        pcall(function()
            Rayfield:Notify({
                Title = title,
                Content = content,
                Duration = 3,
            })
        end)
    end

    local function disconnect(connection)
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    local previousEspFolder = workspace:FindFirstChild("RavenHub_TWDO3_PlayerESP")
    if previousEspFolder then
        previousEspFolder:Destroy()
    end

    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenHub_TWDO3_PlayerESP"
    espFolder.Parent = workspace

    local function getCharacterParts(player)
        local character = player and player.Character
        if not character then
            return nil, nil, nil, nil
        end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        local head = character:FindFirstChild("Head") or root
        return character, humanoid, root, head
    end

    local function getEspColor(player)
        if settings.useTeamColor and player.Team then
            return player.TeamColor.Color
        end
        return Color3.fromRGB(235, 72, 72)
    end

    local function destroyEsp(player)
        local record = espRecords[player]
        if not record then
            return
        end

        if record.highlight then
            record.highlight:Destroy()
        end
        if record.billboard then
            record.billboard:Destroy()
        end
        espRecords[player] = nil
    end

    local function createEsp(player)
        destroyEsp(player)
        if not settings.espEnabled or player == localPlayer then
            return
        end

        local character, humanoid, root, head = getCharacterParts(player)
        if not character or not humanoid or not root or not head then
            return
        end

        local color = getEspColor(player)
        local highlight = Instance.new("Highlight")
        highlight.Name = "PlayerHighlight_" .. tostring(player.UserId)
        highlight.Adornee = character
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillColor = color
        highlight.FillTransparency = 0.78
        highlight.OutlineColor = color
        highlight.OutlineTransparency = 0
        highlight.Parent = espFolder

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "PlayerTag_" .. tostring(player.UserId)
        billboard.Adornee = head
        billboard.AlwaysOnTop = true
        billboard.LightInfluence = 0
        billboard.MaxDistance = settings.maxDistance
        billboard.Size = UDim2.fromOffset(240, 54)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
        billboard.Parent = espFolder

        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "Info"
        textLabel.BackgroundTransparency = 1
        textLabel.Size = UDim2.fromScale(1, 1)
        textLabel.Font = Enum.Font.GothamSemibold
        textLabel.TextColor3 = color
        textLabel.TextSize = 14
        textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        textLabel.TextStrokeTransparency = 0.25
        textLabel.TextWrapped = true
        textLabel.Parent = billboard

        espRecords[player] = {
            billboard = billboard,
            character = character,
            highlight = highlight,
            humanoid = humanoid,
            root = root,
            textLabel = textLabel,
        }
    end

    local function clearAllEsp()
        local playersToClear = {}
        for player in pairs(espRecords) do
            table.insert(playersToClear, player)
        end
        for _, player in ipairs(playersToClear) do
            destroyEsp(player)
        end
    end

    local function refreshAllEsp()
        clearAllEsp()
        if not settings.espEnabled then
            return
        end
        for _, player in ipairs(Players:GetPlayers()) do
            createEsp(player)
        end
    end

    local function playerLabel(player)
        if player.DisplayName == player.Name then
            return "@" .. player.Name
        end
        return player.DisplayName .. " (@" .. player.Name .. ")"
    end

    local function getSelectedPlayer()
        if not selectedUserId then
            return nil
        end
        return Players:GetPlayerByUserId(selectedUserId)
    end

    local function getDropdownValue(value)
        if type(value) == "table" then
            if type(value[1]) == "string" then
                return value[1]
            end
            for key, selected in pairs(value) do
                if type(key) == "string" and selected == true then
                    return key
                end
                if type(selected) == "string" then
                    return selected
                end
            end
            return nil
        end
        return value
    end

    local function setCameraToLocalPlayer()
        spectateEnabled = false
        disconnect(spectateCharacterConnection)
        spectateCharacterConnection = nil

        camera = workspace.CurrentCamera
        local _, humanoid = getCharacterParts(localPlayer)
        if camera and humanoid then
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid
        end
    end

    local function spectatePlayer(player)
        if not player or player == localPlayer then
            setCameraToLocalPlayer()
            notify("Spectate", "เลือกผู้เล่นคนอื่นก่อน")
            return false
        end

        local _, humanoid = getCharacterParts(player)
        if not humanoid then
            notify("Spectate", "ตัวละครของผู้เล่นยังไม่พร้อม")
            return false
        end

        disconnect(spectateCharacterConnection)
        spectateCharacterConnection = player.CharacterAdded:Connect(function(character)
            if not scriptRunning or not spectateEnabled then
                return
            end
            local nextHumanoid = character:WaitForChild("Humanoid", 10)
            if nextHumanoid and workspace.CurrentCamera then
                workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
                workspace.CurrentCamera.CameraSubject = nextHumanoid
            end
        end)

        spectateEnabled = true
        camera = workspace.CurrentCamera
        camera.CameraType = Enum.CameraType.Custom
        camera.CameraSubject = humanoid
        notify("Spectate", "กำลังดู " .. playerLabel(player))
        return true
    end

    local PlayersTab = Window:CreateTab("Players", 4483362458)
    PlayersTab:CreateSection("Player ESP")

    PlayersTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "TWDO3PlayerESP",
        Callback = function(value)
            settings.espEnabled = value
            refreshAllEsp()
        end,
    })

    PlayersTab:CreateToggle({
        Name = "Show Names",
        CurrentValue = true,
        Flag = "TWDO3ESPNames",
        Callback = function(value)
            settings.showNames = value
        end,
    })

    PlayersTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "TWDO3ESPDistance",
        Callback = function(value)
            settings.showDistance = value
        end,
    })

    PlayersTab:CreateToggle({
        Name = "Show Health",
        CurrentValue = true,
        Flag = "TWDO3ESPHealth",
        Callback = function(value)
            settings.showHealth = value
        end,
    })

    PlayersTab:CreateToggle({
        Name = "Use Team Color",
        CurrentValue = true,
        Flag = "TWDO3ESPTeamColor",
        Callback = function(value)
            settings.useTeamColor = value
            refreshAllEsp()
        end,
    })

    PlayersTab:CreateSlider({
        Name = "ESP Max Distance",
        Range = {100, 5000},
        Increment = 100,
        Suffix = " studs",
        CurrentValue = 2500,
        Flag = "TWDO3ESPMaxDistance",
        Callback = function(value)
            settings.maxDistance = value
            for _, record in pairs(espRecords) do
                record.billboard.MaxDistance = value
            end
        end,
    })

    PlayersTab:CreateSection("Spectate")

    local playerDropdown
    local function collectPlayerOptions()
        local entries = {}
        playerByLabel = {}

        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer then
                table.insert(entries, player)
            end
        end

        table.sort(entries, function(left, right)
            return string.lower(left.Name) < string.lower(right.Name)
        end)

        local options = {}
        for _, player in ipairs(entries) do
            local label = playerLabel(player)
            playerByLabel[label] = player.UserId
            table.insert(options, label)
        end

        if #options == 0 then
            table.insert(options, "No other players")
        end
        return options
    end

    local function refreshPlayerDropdown()
        local options = collectPlayerOptions()
        if selectedUserId and not Players:GetPlayerByUserId(selectedUserId) then
            selectedUserId = nil
        end

        if playerDropdown then
            pcall(function()
                playerDropdown:Refresh(options)
            end)
        end
        return options
    end

    local initialOptions = collectPlayerOptions()
    playerDropdown = PlayersTab:CreateDropdown({
        Name = "Select Player",
        Options = initialOptions,
        CurrentOption = {initialOptions[1]},
        MultipleOptions = false,
        Flag = "TWDO3SpectatePlayer",
        Callback = function(value)
            local label = getDropdownValue(value)
            selectedUserId = playerByLabel[label]
            if spectateEnabled then
                spectatePlayer(getSelectedPlayer())
            end
        end,
    })

    PlayersTab:CreateButton({
        Name = "Refresh Player List",
        Callback = function()
            local options = refreshPlayerDropdown()
            notify("Players", "อัปเดตรายชื่อแล้ว: " .. tostring(#options) .. " รายการ")
        end,
    })

    PlayersTab:CreateButton({
        Name = "Spectate Selected Player",
        Callback = function()
            spectatePlayer(getSelectedPlayer())
        end,
    })

    PlayersTab:CreateButton({
        Name = "Return Camera To Me",
        Callback = function()
            setCameraToLocalPlayer()
            notify("Spectate", "คืนกล้องกลับตัวละครของคุณแล้ว")
        end,
    })

    local function trackPlayer(player)
        if player == localPlayer then
            return
        end

        disconnect(playerConnections[player])
        playerConnections[player] = player.CharacterAdded:Connect(function(character)
            task.spawn(function()
                character:WaitForChild("HumanoidRootPart", 10)
                character:WaitForChild("Humanoid", 10)
                if scriptRunning and settings.espEnabled then
                    createEsp(player)
                end
            end)
        end)

        if settings.espEnabled then
            createEsp(player)
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        trackPlayer(player)
    end

    table.insert(cleanupConnections, Players.PlayerAdded:Connect(function(player)
        trackPlayer(player)
        task.defer(refreshPlayerDropdown)
    end))

    table.insert(cleanupConnections, Players.PlayerRemoving:Connect(function(player)
        destroyEsp(player)
        disconnect(playerConnections[player])
        playerConnections[player] = nil

        if selectedUserId == player.UserId then
            selectedUserId = nil
            if spectateEnabled then
                setCameraToLocalPlayer()
                notify("Spectate", "ผู้เล่นที่กำลังดูออกจากเซิร์ฟเวอร์")
            end
        end
        task.defer(refreshPlayerDropdown)
    end))

    local updateAccumulator = 0
    table.insert(cleanupConnections, RunService.Heartbeat:Connect(function(deltaTime)
        if not settings.espEnabled then
            return
        end

        updateAccumulator += deltaTime
        if updateAccumulator < 0.1 then
            return
        end
        updateAccumulator = 0

        local _, _, localRoot = getCharacterParts(localPlayer)
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and not espRecords[player] then
                createEsp(player)
            end
        end
        for player, record in pairs(espRecords) do
            local character, humanoid, root = getCharacterParts(player)
            if character ~= record.character or not humanoid or not root then
                destroyEsp(player)
                continue
            end

            local distance = localRoot and (root.Position - localRoot.Position).Magnitude or 0
            local visible = humanoid.Health > 0 and (not localRoot or distance <= settings.maxDistance)
            local color = getEspColor(player)

            record.highlight.Enabled = visible
            record.billboard.Enabled = visible
            record.highlight.FillColor = color
            record.highlight.OutlineColor = color
            record.textLabel.TextColor3 = color

            local lines = {}
            if settings.showNames then
                table.insert(lines, playerLabel(player))
            end
            if settings.showDistance then
                table.insert(lines, string.format("%.0f studs", distance))
            end
            if settings.showHealth then
                table.insert(lines, string.format("HP %.0f / %.0f", humanoid.Health, humanoid.MaxHealth))
            end
            record.textLabel.Text = table.concat(lines, "  |  ")
        end
    end))

    local function destroyScript()
        if not scriptRunning then
            return
        end
        scriptRunning = false
        setCameraToLocalPlayer()
        clearAllEsp()

        for _, connection in ipairs(cleanupConnections) do
            disconnect(connection)
        end
        for _, connection in pairs(playerConnections) do
            disconnect(connection)
        end
        table.clear(playerConnections)
        espFolder:Destroy()
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end
end
