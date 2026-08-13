-- ============================================================
--   RAVEN HUB | The Walking Dead Online 3
--   Optimized Player / Walker / Loot ESP + Spectate
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")

    local localPlayer = Players.LocalPlayer
    local scriptRunning = true
    local cleanupConnections = {}
    local playerConnections = {}
    local records = {
        player = {},
        walker = {},
        loot = {},
    }
    local lootIndex = {}
    local lootIndexCount = 0
    local lootIndexReady = false
    local selectedUserId = nil
    local playerByLabel = {}
    local spectateEnabled = false
    local spectateCharacterConnection = nil

    local settings = {
        playerEnabled = false,
        walkerEnabled = false,
        lootEnabled = false,
        showNames = true,
        showDistance = true,
        showHealth = true,
        throughWalls = true,
        useTeamColor = true,
        fillTransparency = 0.78,
        textSize = 12,
        healthBarWidth = 120,
        playerDistance = 2500,
        walkerDistance = 800,
        lootDistance = 600,
        maxWalkers = 40,
        maxLoot = 40,
        lootCategories = {
            military = true,
            medical = true,
            supply = true,
            general = false,
        },
    }

    local COLORS = {
        player = Color3.fromRGB(235, 72, 72),
        walker = Color3.fromRGB(255, 151, 46),
        military = Color3.fromRGB(255, 74, 74),
        medical = Color3.fromRGB(78, 220, 130),
        supply = Color3.fromRGB(255, 210, 74),
        general = Color3.fromRGB(94, 185, 255),
    }

    local function disconnect(connection)
        if connection then
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

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

    local previousPlayerFolder = workspace:FindFirstChild("RavenHub_TWDO3_PlayerESP")
    if previousPlayerFolder then
        previousPlayerFolder:Destroy()
    end
    local previousEspFolder = workspace:FindFirstChild("RavenHub_TWDO3_ESP")
    if previousEspFolder then
        previousEspFolder:Destroy()
    end

    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenHub_TWDO3_ESP"
    espFolder.Parent = workspace

    local function getCharacterParts(player)
        local character = player and player.Character
        if not character then
            return nil, nil, nil, nil
        end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Torso")
            or character:FindFirstChild("UpperTorso")
        local head = character:FindFirstChild("Head") or root
        return character, humanoid, root, head
    end

    local function findAdornee(target)
        if not target then
            return nil
        end
        if target:IsA("BasePart") then
            return target
        end
        if target:IsA("Model") and target.PrimaryPart then
            return target.PrimaryPart
        end
        return target:FindFirstChild("HumanoidRootPart", true)
            or target:FindFirstChild("Torso", true)
            or target:FindFirstChildWhichIsA("BasePart", true)
    end

    local function safePosition(target, preferredPart)
        if preferredPart and preferredPart.Parent then
            return preferredPart.Position
        end
        if not target or not target.Parent then
            return nil
        end
        if target:IsA("BasePart") then
            return target.Position
        end
        if target:IsA("Model") then
            local ok, pivot = pcall(target.GetPivot, target)
            if ok then
                return pivot.Position
            end
        end
        return nil
    end

    local function playerLabel(player)
        if player.DisplayName == player.Name then
            return "@" .. player.Name
        end
        return player.DisplayName .. " (@" .. player.Name .. ")"
    end

    local function cleanLootName(name)
        local cleaned = tostring(name or "Loot")
        cleaned = cleaned:gsub("^Loot_", "")
        cleaned = cleaned:gsub("_", " ")
        return cleaned
    end

    local function classifyLoot(name)
        local lower = string.lower(tostring(name or ""))
        if lower:find("military", 1, true)
            or lower:find("police", 1, true)
            or lower:find("gun", 1, true)
            or lower:find("ammo", 1, true) then
            return "military"
        end
        if lower:find("medical", 1, true)
            or lower:find("hospital", 1, true)
            or lower:find("med", 1, true) then
            return "medical"
        end
        if lower:find("supply", 1, true)
            or lower:find("kitchen", 1, true)
            or lower:find("fridge", 1, true)
            or lower:find("food", 1, true) then
            return "supply"
        end
        return "general"
    end

    local function getPlayerColor(player)
        if settings.useTeamColor and player and player.Team then
            return player.TeamColor.Color
        end
        return COLORS.player
    end

    local function getRange(category)
        if category == "player" then
            return settings.playerDistance
        elseif category == "walker" then
            return settings.walkerDistance
        end
        return settings.lootDistance
    end

    local function destroyRecord(category, key)
        local record = records[category][key]
        if not record then
            return
        end
        if record.highlight then
            record.highlight:Destroy()
        end
        if record.billboard then
            record.billboard:Destroy()
        end
        if record.marker then
            record.marker:Destroy()
        end
        records[category][key] = nil
    end

    local function clearCategory(category)
        local keys = {}
        for key in pairs(records[category]) do
            table.insert(keys, key)
        end
        for _, key in ipairs(keys) do
            destroyRecord(category, key)
        end
    end

    local function clearAllVisuals()
        clearCategory("player")
        clearCategory("walker")
        clearCategory("loot")
    end

    local function createRecord(category, key, target, options)
        destroyRecord(category, key)
        if not target or not target.Parent then
            return nil
        end

        local adornee = options.adornee or findAdornee(target)
        local position = safePosition(target, adornee) or options.position
        if not position then
            return nil
        end

        local marker = nil
        if not adornee then
            marker = Instance.new("Part")
            marker.Name = "ESPMarker"
            marker.Anchored = true
            marker.CanCollide = false
            marker.CanQuery = false
            marker.CanTouch = false
            marker.Size = Vector3.new(0.1, 0.1, 0.1)
            marker.Transparency = 1
            marker.Position = position
            marker.Parent = espFolder
            adornee = marker
        end

        local color = options.color
        local highlight = nil
        if target:IsA("Model") or target:IsA("BasePart") then
            highlight = Instance.new("Highlight")
            highlight.Name = category .. "Highlight"
            highlight.Adornee = target
            highlight.DepthMode = settings.throughWalls
                and Enum.HighlightDepthMode.AlwaysOnTop
                or Enum.HighlightDepthMode.Occluded
            highlight.FillColor = color
            highlight.FillTransparency = settings.fillTransparency
            highlight.OutlineColor = color
            highlight.OutlineTransparency = 0
            highlight.Parent = espFolder
        end

        local billboard = Instance.new("BillboardGui")
        billboard.Name = category .. "Tag"
        billboard.Adornee = adornee
        billboard.AlwaysOnTop = settings.throughWalls
        billboard.LightInfluence = 0
        billboard.MaxDistance = getRange(category)
        billboard.Size = UDim2.fromOffset(260, 56)
        billboard.StudsOffsetWorldSpace = Vector3.new(0, options.height or 3.2, 0)
        billboard.Parent = espFolder

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.BackgroundTransparency = 1
        nameLabel.Size = UDim2.new(1, 0, 0, 18)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextColor3 = color
        nameLabel.TextSize = settings.textSize
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        nameLabel.TextStrokeTransparency = 0.15
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = billboard

        local detailLabel = Instance.new("TextLabel")
        detailLabel.Name = "Details"
        detailLabel.BackgroundTransparency = 1
        detailLabel.Position = UDim2.fromOffset(0, 18)
        detailLabel.Size = UDim2.new(1, 0, 0, 15)
        detailLabel.Font = Enum.Font.GothamSemibold
        detailLabel.TextColor3 = color
        detailLabel.TextSize = math.max(settings.textSize - 1, 8)
        detailLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        detailLabel.TextStrokeTransparency = 0.2
        detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
        detailLabel.Parent = billboard

        local healthBackground = Instance.new("Frame")
        healthBackground.Name = "HealthBackground"
        healthBackground.AnchorPoint = Vector2.new(0.5, 0)
        healthBackground.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        healthBackground.BackgroundTransparency = 0.15
        healthBackground.BorderSizePixel = 0
        healthBackground.Position = UDim2.new(0.5, 0, 0, 37)
        healthBackground.Size = UDim2.fromOffset(settings.healthBarWidth, 4)
        healthBackground.Visible = options.humanoid ~= nil and settings.showHealth
        healthBackground.Parent = billboard

        local healthFill = Instance.new("Frame")
        healthFill.Name = "Fill"
        healthFill.BackgroundColor3 = Color3.fromRGB(70, 230, 105)
        healthFill.BorderSizePixel = 0
        healthFill.Size = UDim2.fromScale(1, 1)
        healthFill.Parent = healthBackground

        local record = {
            category = category,
            target = target,
            adornee = adornee,
            root = options.root or adornee,
            humanoid = options.humanoid,
            player = options.player,
            label = options.label,
            color = color,
            marker = marker,
            highlight = highlight,
            billboard = billboard,
            nameLabel = nameLabel,
            detailLabel = detailLabel,
            healthBackground = healthBackground,
            healthFill = healthFill,
            staticPosition = options.position,
        }
        records[category][key] = record
        return record
    end

    local function updateRecord(record, localPosition)
        if not record.target or not record.target.Parent then
            return false
        end

        if record.category == "player" then
            local character, humanoid, root, head = getCharacterParts(record.player)
            if character ~= record.target or not humanoid or not root or not head then
                return false
            end
            record.humanoid = humanoid
            record.root = root
            record.color = getPlayerColor(record.player)
        elseif record.category == "walker" then
            local humanoid = record.target:FindFirstChildOfClass("Humanoid")
            local root = record.target:FindFirstChild("HumanoidRootPart")
                or record.target:FindFirstChild("Torso")
                or findAdornee(record.target)
            if not humanoid or not root then
                return false
            end
            record.humanoid = humanoid
            record.root = root
        end

        local position = record.staticPosition or safePosition(record.target, record.root)
        if not position then
            return false
        end
        if record.marker then
            record.marker.Position = position
        end

        local distance = localPosition and (position - localPosition).Magnitude or 0
        local alive = not record.humanoid or record.humanoid.Health > 0
        local visible = alive and (not localPosition or distance <= getRange(record.category))
        local color = record.color

        record.billboard.Enabled = visible
        record.billboard.MaxDistance = getRange(record.category)
        record.billboard.AlwaysOnTop = settings.throughWalls
        record.nameLabel.TextColor3 = color
        record.nameLabel.TextSize = settings.textSize
        record.detailLabel.TextColor3 = color
        record.detailLabel.TextSize = math.max(settings.textSize - 1, 8)
        if record.highlight then
            record.highlight.Enabled = visible
            record.highlight.DepthMode = settings.throughWalls
                and Enum.HighlightDepthMode.AlwaysOnTop
                or Enum.HighlightDepthMode.Occluded
            record.highlight.FillColor = color
            record.highlight.FillTransparency = settings.fillTransparency
            record.highlight.OutlineColor = color
        end

        local detailParts = {}
        if settings.showDistance then
            table.insert(detailParts, string.format("%.0f studs", distance))
        end
        if settings.showHealth and record.humanoid then
            table.insert(detailParts, string.format("HP %.0f/%.0f", record.humanoid.Health, record.humanoid.MaxHealth))
        end
        record.nameLabel.Text = record.label
        record.nameLabel.Visible = settings.showNames
        record.detailLabel.Text = table.concat(detailParts, "  |  ")
        record.detailLabel.Visible = #detailParts > 0

        local showHealthBar = settings.showHealth and record.humanoid ~= nil
        record.healthBackground.Visible = showHealthBar
        record.healthBackground.Size = UDim2.fromOffset(settings.healthBarWidth, 4)
        if showHealthBar then
            local maxHealth = math.max(record.humanoid.MaxHealth, 1)
            local ratio = math.clamp(record.humanoid.Health / maxHealth, 0, 1)
            record.healthFill.Size = UDim2.fromScale(ratio, 1)
            record.healthFill.BackgroundColor3 = Color3.fromHSV(ratio * 0.33, 0.85, 1)
        end
        return true
    end

    local function ensurePlayerRecord(player)
        if not settings.playerEnabled or player == localPlayer then
            return
        end
        local character, humanoid, root, head = getCharacterParts(player)
        local current = records.player[player]
        if current and current.target == character then
            return
        end
        if not character or not humanoid or not root or not head then
            return
        end
        createRecord("player", player, character, {
            player = player,
            humanoid = humanoid,
            root = root,
            adornee = head,
            label = playerLabel(player),
            color = getPlayerColor(player),
            height = 3.2,
        })
    end

    local function refreshPlayers()
        if not settings.playerEnabled then
            clearCategory("player")
            return
        end
        for _, player in ipairs(Players:GetPlayers()) do
            ensurePlayerRecord(player)
        end
    end

    local function collectNearestWalkers(localPosition)
        local candidates = {}
        local ai = workspace:FindFirstChild("AI")
        local walkerFolder = ai and ai:FindFirstChild("Walkers")
        if not walkerFolder or not localPosition then
            return candidates
        end
        for _, walker in ipairs(walkerFolder:GetChildren()) do
            if walker:IsA("Model") then
                local humanoid = walker:FindFirstChildOfClass("Humanoid")
                local root = walker:FindFirstChild("HumanoidRootPart")
                    or walker:FindFirstChild("Torso")
                    or findAdornee(walker)
                if humanoid and root and humanoid.Health > 0 then
                    local distance = (root.Position - localPosition).Magnitude
                    if distance <= settings.walkerDistance then
                        table.insert(candidates, {
                            target = walker,
                            humanoid = humanoid,
                            root = root,
                            distance = distance,
                        })
                    end
                end
            end
        end
        table.sort(candidates, function(left, right)
            return left.distance < right.distance
        end)
        return candidates
    end

    local function syncWalkers(localPosition)
        if not settings.walkerEnabled then
            clearCategory("walker")
            return
        end
        local candidates = collectNearestWalkers(localPosition)
        local desired = {}
        for index = 1, math.min(#candidates, settings.maxWalkers) do
            local item = candidates[index]
            desired[item.target] = true
            if not records.walker[item.target] then
                createRecord("walker", item.target, item.target, {
                    humanoid = item.humanoid,
                    root = item.root,
                    adornee = item.root,
                    label = "Walker",
                    color = COLORS.walker,
                    height = 3.5,
                })
            end
        end
        local stale = {}
        for walker in pairs(records.walker) do
            if not desired[walker] then
                table.insert(stale, walker)
            end
        end
        for _, walker in ipairs(stale) do
            destroyRecord("walker", walker)
        end
    end

    local function indexLoot(target)
        if not target:IsA("Model") and not target:IsA("BasePart") then
            return
        end
        local adornee = findAdornee(target)
        local position = safePosition(target, adornee)
        if not position then
            return
        end
        lootIndex[target] = {
            target = target,
            adornee = adornee,
            position = position,
            category = classifyLoot(target.Name),
            label = cleanLootName(target.Name),
        }
        lootIndexCount += 1
    end

    local function removeLootIndex(target)
        if lootIndex[target] then
            lootIndex[target] = nil
            lootIndexCount = math.max(lootIndexCount - 1, 0)
        end
        destroyRecord("loot", target)
    end

    local function collectNearestLoot(localPosition)
        local candidates = {}
        if not localPosition then
            return candidates
        end
        for target, item in pairs(lootIndex) do
            if not target.Parent then
                removeLootIndex(target)
            elseif settings.lootCategories[item.category] then
                local distance = (item.position - localPosition).Magnitude
                if distance <= settings.lootDistance then
                    item.distance = distance
                    table.insert(candidates, item)
                end
            end
        end
        table.sort(candidates, function(left, right)
            return left.distance < right.distance
        end)
        return candidates
    end

    local function syncLoot(localPosition)
        if not settings.lootEnabled then
            clearCategory("loot")
            return
        end
        local candidates = collectNearestLoot(localPosition)
        local desired = {}
        for index = 1, math.min(#candidates, settings.maxLoot) do
            local item = candidates[index]
            desired[item.target] = true
            if not records.loot[item.target] then
                createRecord("loot", item.target, item.target, {
                    adornee = item.adornee,
                    position = item.position,
                    label = item.label,
                    color = COLORS[item.category],
                    height = 2.2,
                })
            end
        end
        local stale = {}
        for target in pairs(records.loot) do
            if not desired[target] then
                table.insert(stale, target)
            end
        end
        for _, target in ipairs(stale) do
            destroyRecord("loot", target)
        end
    end

    local function countRecords(category)
        local count = 0
        for _ in pairs(records[category]) do
            count += 1
        end
        return count
    end

    local EspTab = Window:CreateTab("ESP", 4483362458)
    local statusLabel = EspTab:CreateLabel("ESP: P 0 | W 0 | L 0 | Loot index: starting")
    EspTab:CreateSection("Main ESP")

    EspTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "TWDO3PlayerESP",
        Callback = function(value)
            settings.playerEnabled = value
            refreshPlayers()
        end,
    })

    EspTab:CreateToggle({
        Name = "Walker ESP",
        CurrentValue = false,
        Flag = "TWDO3WalkerESP",
        Callback = function(value)
            settings.walkerEnabled = value
            if not value then
                clearCategory("walker")
            end
        end,
    })

    EspTab:CreateToggle({
        Name = "Loot ESP",
        CurrentValue = false,
        Flag = "TWDO3LootESP",
        Callback = function(value)
            settings.lootEnabled = value
            if not value then
                clearCategory("loot")
            end
        end,
    })

    EspTab:CreateSection("Visuals")
    EspTab:CreateToggle({
        Name = "Show Names",
        CurrentValue = true,
        Flag = "TWDO3ESPNames",
        Callback = function(value)
            settings.showNames = value
        end,
    })
    EspTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "TWDO3ESPDistance",
        Callback = function(value)
            settings.showDistance = value
        end,
    })
    EspTab:CreateToggle({
        Name = "Show Health + Bar",
        CurrentValue = true,
        Flag = "TWDO3ESPHealth",
        Callback = function(value)
            settings.showHealth = value
        end,
    })
    EspTab:CreateToggle({
        Name = "Visible Through Walls",
        CurrentValue = true,
        Flag = "TWDO3ESPThroughWalls",
        Callback = function(value)
            settings.throughWalls = value
        end,
    })
    EspTab:CreateToggle({
        Name = "Use Player Team Color",
        CurrentValue = true,
        Flag = "TWDO3ESPTeamColor",
        Callback = function(value)
            settings.useTeamColor = value
        end,
    })
    EspTab:CreateSlider({
        Name = "Highlight Fill Transparency",
        Range = {0, 100},
        Increment = 5,
        Suffix = "%",
        CurrentValue = 80,
        Flag = "TWDO3ESPFillTransparency",
        Callback = function(value)
            settings.fillTransparency = math.clamp(value / 100, 0, 1)
        end,
    })
    EspTab:CreateSlider({
        Name = "ESP Text Size",
        Range = {8, 18},
        Increment = 1,
        CurrentValue = 12,
        Flag = "TWDO3ESPTextSize",
        Callback = function(value)
            settings.textSize = value
        end,
    })
    EspTab:CreateSlider({
        Name = "Health Bar Width",
        Range = {60, 200},
        Increment = 10,
        Suffix = " px",
        CurrentValue = 120,
        Flag = "TWDO3ESPHealthBarWidth",
        Callback = function(value)
            settings.healthBarWidth = value
        end,
    })

    EspTab:CreateSection("Distances / Limits")
    EspTab:CreateSlider({
        Name = "Player Distance",
        Range = {100, 5000},
        Increment = 100,
        Suffix = " studs",
        CurrentValue = 2500,
        Flag = "TWDO3PlayerDistance",
        Callback = function(value)
            settings.playerDistance = value
        end,
    })
    EspTab:CreateSlider({
        Name = "Walker Distance",
        Range = {100, 2000},
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 800,
        Flag = "TWDO3WalkerDistance",
        Callback = function(value)
            settings.walkerDistance = value
        end,
    })
    EspTab:CreateSlider({
        Name = "Maximum Walkers",
        Range = {5, 100},
        Increment = 5,
        CurrentValue = 40,
        Flag = "TWDO3MaxWalkers",
        Callback = function(value)
            settings.maxWalkers = value
        end,
    })
    EspTab:CreateSlider({
        Name = "Loot Distance",
        Range = {50, 1500},
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 600,
        Flag = "TWDO3LootDistance",
        Callback = function(value)
            settings.lootDistance = value
        end,
    })
    EspTab:CreateSlider({
        Name = "Maximum Loot Markers",
        Range = {5, 100},
        Increment = 5,
        CurrentValue = 40,
        Flag = "TWDO3MaxLoot",
        Callback = function(value)
            settings.maxLoot = value
        end,
    })

    EspTab:CreateSection("Loot Categories")
    local lootCategoryControls = {
        {key = "military", name = "Military / Police", default = true},
        {key = "medical", name = "Medical", default = true},
        {key = "supply", name = "Food / Supply", default = true},
        {key = "general", name = "General Containers", default = false},
    }
    for _, control in ipairs(lootCategoryControls) do
        local categoryKey = control.key
        EspTab:CreateToggle({
            Name = control.name,
            CurrentValue = control.default,
            Flag = "TWDO3LootCategory_" .. categoryKey,
            Callback = function(value)
                settings.lootCategories[categoryKey] = value
            end,
        })
    end

    local PlayersTab = Window:CreateTab("Spectate", 4483362458)
    local playerDropdown

    local function getDropdownValue(value)
        if type(value) ~= "table" then
            return value
        end
        if type(value[1]) == "string" then
            return value[1]
        end
        for key, selected in pairs(value) do
            if type(key) == "string" and selected == true then
                return key
            elseif type(selected) == "string" then
                return selected
            end
        end
        return nil
    end

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

    local function setCameraToLocalPlayer()
        spectateEnabled = false
        disconnect(spectateCharacterConnection)
        spectateCharacterConnection = nil
        local camera = workspace.CurrentCamera
        local _, humanoid = getCharacterParts(localPlayer)
        if camera and humanoid then
            camera.CameraType = Enum.CameraType.Custom
            camera.CameraSubject = humanoid
        end
    end

    local function spectatePlayer(player)
        if not player or player == localPlayer then
            setCameraToLocalPlayer()
            notify("Spectate", "Select another player first")
            return
        end
        local _, humanoid = getCharacterParts(player)
        if not humanoid then
            notify("Spectate", "Target character is not ready")
            return
        end
        disconnect(spectateCharacterConnection)
        spectateEnabled = true
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
        workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        workspace.CurrentCamera.CameraSubject = humanoid
        notify("Spectate", "Watching " .. playerLabel(player))
    end

    local initialOptions = collectPlayerOptions()
    playerDropdown = PlayersTab:CreateDropdown({
        Name = "Select Player",
        Options = initialOptions,
        CurrentOption = {initialOptions[1]},
        MultipleOptions = false,
        Flag = "TWDO3SpectatePlayer",
        Callback = function(value)
            selectedUserId = playerByLabel[getDropdownValue(value)]
            if spectateEnabled and selectedUserId then
                spectatePlayer(Players:GetPlayerByUserId(selectedUserId))
            end
        end,
    })
    PlayersTab:CreateButton({
        Name = "Refresh Player List",
        Callback = function()
            refreshPlayerDropdown()
            notify("Players", "Player list refreshed")
        end,
    })
    PlayersTab:CreateButton({
        Name = "Spectate Selected Player",
        Callback = function()
            spectatePlayer(selectedUserId and Players:GetPlayerByUserId(selectedUserId))
        end,
    })
    PlayersTab:CreateButton({
        Name = "Return Camera To Me",
        Callback = function()
            setCameraToLocalPlayer()
            notify("Spectate", "Camera returned to your character")
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
                if scriptRunning then
                    ensurePlayerRecord(player)
                end
            end)
        end)
        ensurePlayerRecord(player)
    end

    for _, player in ipairs(Players:GetPlayers()) do
        trackPlayer(player)
    end
    table.insert(cleanupConnections, Players.PlayerAdded:Connect(function(player)
        trackPlayer(player)
        task.defer(refreshPlayerDropdown)
    end))
    table.insert(cleanupConnections, Players.PlayerRemoving:Connect(function(player)
        destroyRecord("player", player)
        disconnect(playerConnections[player])
        playerConnections[player] = nil
        if selectedUserId == player.UserId then
            selectedUserId = nil
            if spectateEnabled then
                setCameraToLocalPlayer()
            end
        end
        task.defer(refreshPlayerDropdown)
    end))

    local lootFolder = workspace:FindFirstChild("Lootables")
    if lootFolder then
        table.insert(cleanupConnections, lootFolder.ChildAdded:Connect(function(child)
            task.defer(indexLoot, child)
        end))
        table.insert(cleanupConnections, lootFolder.ChildRemoved:Connect(removeLootIndex))
        task.spawn(function()
            local children = lootFolder:GetChildren()
            for index, target in ipairs(children) do
                if not scriptRunning then
                    return
                end
                indexLoot(target)
                if index % 200 == 0 then
                    pcall(function()
                        statusLabel:Set(string.format("Indexing loot: %d / %d", index, #children))
                    end)
                    task.wait()
                end
            end
            lootIndexReady = true
            notify("ESP", "Loot index ready: " .. tostring(lootIndexCount) .. " containers")
        end)
    else
        lootIndexReady = true
    end

    local fastAccumulator = 0
    local scanAccumulator = 0
    table.insert(cleanupConnections, RunService.Heartbeat:Connect(function(deltaTime)
        if not scriptRunning then
            return
        end
        fastAccumulator += deltaTime
        scanAccumulator += deltaTime
        if fastAccumulator >= 0.1 then
            fastAccumulator = 0
            local _, _, localRoot = getCharacterParts(localPlayer)
            local localPosition = localRoot and localRoot.Position
            refreshPlayers()
            for category, categoryRecords in pairs(records) do
                local stale = {}
                for key, record in pairs(categoryRecords) do
                    if not updateRecord(record, localPosition) then
                        table.insert(stale, key)
                    end
                end
                for _, key in ipairs(stale) do
                    destroyRecord(category, key)
                end
            end
        end
        if scanAccumulator >= 0.75 then
            scanAccumulator = 0
            local _, _, localRoot = getCharacterParts(localPlayer)
            local localPosition = localRoot and localRoot.Position
            syncWalkers(localPosition)
            if lootIndexReady or lootIndexCount > 0 then
                syncLoot(localPosition)
            end
            pcall(function()
                statusLabel:Set(string.format(
                    "ESP: P %d | W %d | L %d | Indexed %d",
                    countRecords("player"),
                    countRecords("walker"),
                    countRecords("loot"),
                    lootIndexCount
                ))
            end)
        end
    end))

    local function destroyScript()
        if not scriptRunning then
            return
        end
        scriptRunning = false
        setCameraToLocalPlayer()
        clearAllVisuals()
        for _, connection in ipairs(cleanupConnections) do
            disconnect(connection)
        end
        for _, connection in pairs(playerConnections) do
            disconnect(connection)
        end
        table.clear(playerConnections)
        table.clear(lootIndex)
        espFolder:Destroy()
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end
end
