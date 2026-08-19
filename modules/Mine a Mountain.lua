--[[
    RAVEN HUB | Experience Module
    Game: Mine a Mountain (PlaceId: 125927821145949, GameId: 10187294555)
    Features: Crystal ESP (6 tiers + Mutations) | Auto Mine | Auto Sell | Auto Bomb | Teleport | Auto Pickup | Stat Tracker
    Version: v1.0
]]
-- RAVEN HUB | ⛰️ Mine a Mountain — Ultimate automation suite
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RS = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local CoreGui = game:GetService("CoreGui")
    local VirtualUser = game:GetService("VirtualUser")
    local TeleportService = game:GetService("TeleportService")

    local player = Players.LocalPlayer
    local environment = getgenv()

    -- Cleanup previous instance
    if type(environment.__RAVEN_MAM) == "table"
        and type(environment.__RAVEN_MAM.Destroy) == "function" then
        pcall(environment.__RAVEN_MAM.Destroy)
    end

    local running = true
    local connections = {}

    -- Remotes
    local Remotes = RS:WaitForChild("Remotes", 5)
    local DigRequest = Remotes and Remotes:FindFirstChild("DigRequest")
    local SellRequest = Remotes and Remotes:FindFirstChild("SellRequest")
    local CrystalDropRequest = Remotes and Remotes:FindFirstChild("CrystalDropRequest")
    local CrystalDroppedPickup = Remotes and Remotes:FindFirstChild("CrystalDroppedPickup")

    -- ============================================================
    -- TIER DATA
    -- ============================================================
    local TIERS = {
        {name = "Common",    color = Color3.fromRGB(220, 195, 140)},
        {name = "Uncommon",  color = Color3.fromRGB(110, 190, 240)},
        {name = "Rare",      color = Color3.fromRGB(80, 240, 220)},
        {name = "Epic",      color = Color3.fromRGB(170, 100, 255)},
        {name = "Legendary", color = Color3.fromRGB(255, 80, 180)},
        {name = "Mythic",    color = Color3.fromRGB(190, 70, 255)},
    }

    local MUTATIONS = {
        Fire = Color3.fromRGB(255, 100, 30),
        Poison = Color3.fromRGB(50, 255, 80),
    }

    -- ============================================================
    -- SETTINGS
    -- ============================================================
    local settings = {
        -- ESP
        espEnabled = true,
        espMaxDist = 500,
        espMinTier = 1,
        espMinValue = 0,
        espShowDropped = true,
        espShowMap = true,
        espShowMutation = true,
        -- Auto Mine
        autoMine = false,
        mineInterval = 0.35,
        mineRandomOffset = 2,
        -- Auto Sell
        autoSell = false,
        sellInterval = 5,
        -- Auto Bomb
        autoBomb = false,
        bombInterval = 8,
        -- Teleport
        autoTP = false,
        tpMinTier = 4,
        tpMinValue = 10000,
        tpCooldown = 3,
        -- Auto Pickup
        autoPickup = false,
        pickupRadius = 30,
        pickupMinTier = 3,
        -- Utility
        antiAfk = true,
        autoRejoin = false,
    }

    -- ============================================================
    -- UTILITIES
    -- ============================================================
    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 5})
            end)
        end
    end

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    local function getCharacter()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        return character, humanoid, root
    end

    local function teleportTo(position)
        local _, _, root = getCharacter()
        if not root then return false end
        if typeof(position) == "CFrame" then
            root.CFrame = position
        else
            root.CFrame = CFrame.new(position)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    local function fmtNum(n)
        if not n then return "?" end
        n = tonumber(n)
        if not n then return "?" end
        if n >= 1e6 then return string.format("$%.1fM", n / 1e6) end
        if n >= 1e3 then return string.format("$%.1fK", n / 1e3) end
        return "$" .. tostring(math.floor(n))
    end

    local function readCrystalAttribs(inst)
        return {
            tier = inst:GetAttribute("Tier") or 0,
            tierName = inst:GetAttribute("TierName") or "?",
            name = inst:GetAttribute("CrystalName") or inst.Name,
            value = inst:GetAttribute("Value"),
            weight = inst:GetAttribute("WeightKg"),
            sizeClass = inst:GetAttribute("SizeClass") or "S",
            mutation = inst:GetAttribute("Mutation"),
            uid = inst:GetAttribute("UID"),
            colorR = inst:GetAttribute("TierColorR"),
            colorG = inst:GetAttribute("TierColorG"),
            colorB = inst:GetAttribute("TierColorB"),
        }
    end

    -- ============================================================
    -- ESP SYSTEM
    -- ============================================================
    local espObjects = {}
    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenMaM_ESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui

    local function createESP(part, data)
        if espObjects[part] then return end
        local tier = tonumber(data.tier) or 1
        local tierInfo = TIERS[tier] or TIERS[1]
        local color = tierInfo.color
        if data.colorR and data.colorG and data.colorB then
            color = Color3.fromRGB(data.colorR, data.colorG, data.colorB)
        end

        local bb = Instance.new("BillboardGui")
        bb.Name = "ESP_" .. (data.uid or part.Name)
        bb.Adornee = part
        bb.Size = UDim2.new(0, 200, 0, 50)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        bb.MaxDistance = settings.espMaxDist
        bb.Parent = espFolder

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.TextColor3 = color
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextStrokeTransparency = 0.3
        label.TextWrapped = true
        label.Parent = bb

        -- Mutation indicator
        if data.mutation and MUTATIONS[data.mutation] then
            local ml = Instance.new("TextLabel")
            ml.Size = UDim2.new(1, 0, 0, 12)
            ml.Position = UDim2.new(0, 0, 1, 0)
            ml.BackgroundTransparency = 1
            ml.Font = Enum.Font.GothamBold
            ml.TextSize = 10
            ml.TextColor3 = MUTATIONS[data.mutation]
            ml.TextStrokeTransparency = 0.3
            ml.Text = (data.mutation == "Fire" and "🔥" or "☠️") .. " " .. data.mutation
            ml.Parent = bb
        end

        espObjects[part] = {bb = bb, label = label, data = data}
    end

    local function removeESP(part)
        local obj = espObjects[part]
        if obj then
            if obj.bb then obj.bb:Destroy() end
            espObjects[part] = nil
        end
    end

    local function clearAllESP()
        for part, _ in pairs(espObjects) do
            removeESP(part)
        end
    end

    local function updateESP()
        if not settings.espEnabled then return end
        local _, _, root = getCharacter()
        if not root then return end
        local rootPos = root.Position

        for part, obj in pairs(espObjects) do
            if not part.Parent then
                removeESP(part)
            elseif obj.bb and obj.label then
                local d = (rootPos - part.Position).Magnitude
                local data = obj.data
                local tier = tonumber(data.tier) or 1
                local val = tonumber(data.value) or 0

                if tier < settings.espMinTier or val < settings.espMinValue then
                    obj.bb.Enabled = false
                else
                    obj.bb.Enabled = true
                    local txt = string.format("[%s] %s", data.sizeClass, data.name or "?")
                    if data.value then txt = txt .. " | " .. fmtNum(data.value) end
                    txt = txt .. " | " .. math.floor(d) .. "m"
                    obj.label.Text = txt
                end
            end
        end
    end

    local function scanCrystals()
        if not settings.espEnabled then return end

        -- Scan DroppedCrystals
        if settings.espShowDropped then
            local dc = workspace:FindFirstChild("DroppedCrystals")
            if dc then
                for _, c in ipairs(dc:GetChildren()) do
                    if c:IsA("BasePart") and not espObjects[c] then
                        local data = readCrystalAttribs(c)
                        if (tonumber(data.tier) or 0) >= settings.espMinTier then
                            createESP(c, data)
                        end
                    end
                end
            end
        end

        -- Scan Map crystals
        if settings.espShowMap then
            local map = workspace:FindFirstChild("Map")
            if map then
                for _, c in ipairs(map:GetChildren()) do
                    if c:IsA("BasePart") and c.Name:match("^T%d") and not espObjects[c] then
                        local data = readCrystalAttribs(c)
                        if (tonumber(data.tier) or 0) >= settings.espMinTier then
                            createESP(c, data)
                        end
                    end
                end
            end
        end
    end

    -- Watch for new crystals
    local function watchFolder(folder)
        if not folder then return end
        connect(folder.ChildAdded, function(child)
            if child:IsA("BasePart") and settings.espEnabled then
                task.wait(0.1)
                local data = readCrystalAttribs(child)
                if (tonumber(data.tier) or 0) >= settings.espMinTier then
                    createESP(child, data)
                end
            end
        end)
        connect(folder.ChildRemoved, function(child)
            removeESP(child)
        end)
    end

    local dcFolder = workspace:FindFirstChild("DroppedCrystals")
    if dcFolder then watchFolder(dcFolder) end
    connect(workspace.ChildAdded, function(child)
        if child.Name == "DroppedCrystals" then watchFolder(child) end
    end)

    -- ============================================================
    -- AUTO MINE
    -- ============================================================
    local lastDig = 0
    local totalDigs = 0

    local function doAutoMine()
        if not settings.autoMine then return end
        if not DigRequest then return end
        local now = os.clock()
        if now - lastDig < settings.mineInterval then return end

        local _, _, root = getCharacter()
        if not root then return end

        local offset = Vector3.new(
            (math.random() - 0.5) * settings.mineRandomOffset,
            -(math.random() * 2 + 1),
            (math.random() - 0.5) * settings.mineRandomOffset
        )
        DigRequest:FireServer(root.Position + offset)
        lastDig = now
        totalDigs += 1
    end

    -- ============================================================
    -- AUTO SELL
    -- ============================================================
    local lastSell = 0
    local totalSells = 0

    local function doAutoSell()
        if not settings.autoSell then return end
        if not SellRequest then return end
        local now = os.clock()
        if now - lastSell < settings.sellInterval then return end

        SellRequest:FireServer()
        lastSell = now
        totalSells += 1
    end

    -- ============================================================
    -- AUTO BOMB
    -- ============================================================
    local lastBomb = 0

    local function doAutoBomb()
        if not settings.autoBomb then return end
        local now = os.clock()
        if now - lastBomb < settings.bombInterval then return end

        local char = player.Character
        if not char then return end

        local bomb = nil
        for _, tool in ipairs(player.Backpack:GetChildren()) do
            if tool:IsA("Tool") and tool.Name:find("Bomb") then
                bomb = tool
                break
            end
        end
        if not bomb then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and c.Name:find("Bomb") then
                    bomb = c
                    break
                end
            end
        end

        if bomb then
            if bomb.Parent == player.Backpack then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum:EquipTool(bomb) end
                task.wait(0.3)
            end
            if bomb.Parent == char then
                bomb:Activate()
                lastBomb = now
            end
        end
    end

    -- ============================================================
    -- AUTO TELEPORT TO CRYSTALS
    -- ============================================================
    local lastTP = 0

    local function doAutoTP()
        if not settings.autoTP then return end
        local now = os.clock()
        if now - lastTP < settings.tpCooldown then return end

        local _, _, root = getCharacter()
        if not root then return end

        local best, bestVal = nil, 0
        local dc = workspace:FindFirstChild("DroppedCrystals")
        if dc then
            for _, c in ipairs(dc:GetChildren()) do
                if c:IsA("BasePart") then
                    local tier = c:GetAttribute("Tier") or 0
                    local val = c:GetAttribute("Value") or 0
                    if tier >= settings.tpMinTier and val >= settings.tpMinValue and val > bestVal then
                        bestVal = val
                        best = c
                    end
                end
            end
        end

        if best then
            teleportTo(best.Position + Vector3.new(0, 5, 0))
            lastTP = now
            notify("⛰️ MaM", "Teleported to " .. (best:GetAttribute("CrystalName") or "crystal") .. " (" .. fmtNum(bestVal) .. ")")
        end
    end

    -- ============================================================
    -- AUTO PICKUP
    -- ============================================================
    local function doAutoPickup()
        if not settings.autoPickup then return end
        if not CrystalDroppedPickup then return end

        local _, _, root = getCharacter()
        if not root then return end

        local dc = workspace:FindFirstChild("DroppedCrystals")
        if not dc then return end

        for _, c in ipairs(dc:GetChildren()) do
            if c:IsA("BasePart") then
                local tier = c:GetAttribute("Tier") or 0
                local dist = (c.Position - root.Position).Magnitude
                if tier >= settings.pickupMinTier and dist <= settings.pickupRadius then
                    local uid = c:GetAttribute("UID")
                    if uid then
                        pcall(function()
                            CrystalDroppedPickup:FireServer(uid)
                        end)
                    end
                end
            end
        end
    end

    -- ============================================================
    -- UI TABS
    -- ============================================================

    -- MINING TAB
    local MineTab = Window:CreateTab("Mining", "automation")

    MineTab:CreateSection("Auto Mine")
    local mineStatus = MineTab:CreateLabel("Mine: idle")

    MineTab:CreateToggle({
        Name = "Auto Mine (Dig Terrain)",
        CurrentValue = false,
        Flag = "MaMAutoMine",
        Callback = function(v) settings.autoMine = v end,
    })
    MineTab:CreateSlider({
        Name = "Dig Interval",
        Range = {0.1, 2},
        Increment = 0.05,
        CurrentValue = 0.35,
        Suffix = " s",
        Flag = "MaMMineInterval",
        Callback = function(v) settings.mineInterval = v end,
    })
    MineTab:CreateSlider({
        Name = "Random Offset (Anti-detect)",
        Range = {0, 10},
        Increment = 0.5,
        CurrentValue = 2,
        Suffix = " studs",
        Flag = "MaMMineOffset",
        Callback = function(v) settings.mineRandomOffset = v end,
    })

    MineTab:CreateSection("Auto Sell")
    MineTab:CreateToggle({
        Name = "Auto Sell Crystals",
        CurrentValue = false,
        Flag = "MaMAutoSell",
        Callback = function(v) settings.autoSell = v end,
    })
    MineTab:CreateSlider({
        Name = "Sell Interval",
        Range = {1, 30},
        Increment = 1,
        CurrentValue = 5,
        Suffix = " s",
        Flag = "MaMSellInterval",
        Callback = function(v) settings.sellInterval = v end,
    })
    MineTab:CreateButton({
        Name = "🛒 Sell Now",
        Callback = function()
            if SellRequest then
                SellRequest:FireServer()
                notify("⛰️ MaM", "Sell request sent!")
            end
        end,
    })

    MineTab:CreateSection("Auto Bomb")
    MineTab:CreateToggle({
        Name = "Auto Use Bomb",
        CurrentValue = false,
        Flag = "MaMAutoBomb",
        Callback = function(v) settings.autoBomb = v end,
    })
    MineTab:CreateSlider({
        Name = "Bomb Interval",
        Range = {3, 30},
        Increment = 1,
        CurrentValue = 8,
        Suffix = " s",
        Flag = "MaMBombInterval",
        Callback = function(v) settings.bombInterval = v end,
    })

    MineTab:CreateSection("Auto Pickup")
    MineTab:CreateToggle({
        Name = "Auto Pickup Nearby Crystals",
        CurrentValue = false,
        Flag = "MaMAutoPickup",
        Callback = function(v) settings.autoPickup = v end,
    })
    MineTab:CreateSlider({
        Name = "Pickup Radius",
        Range = {5, 100},
        Increment = 5,
        CurrentValue = 30,
        Suffix = " studs",
        Flag = "MaMPickupRadius",
        Callback = function(v) settings.pickupRadius = v end,
    })
    MineTab:CreateSlider({
        Name = "Pickup Min Tier",
        Range = {1, 6},
        Increment = 1,
        CurrentValue = 3,
        Suffix = "",
        Flag = "MaMPickupMinTier",
        Callback = function(v) settings.pickupMinTier = v end,
    })

    -- ESP TAB
    local EspTab = Window:CreateTab("Crystal ESP", "esp")

    EspTab:CreateSection("ESP Settings")
    EspTab:CreateToggle({
        Name = "Crystal ESP",
        CurrentValue = true,
        Flag = "MaMEspEnabled",
        Callback = function(v)
            settings.espEnabled = v
            if not v then clearAllESP() end
        end,
    })
    EspTab:CreateSlider({
        Name = "Max Distance",
        Range = {50, 2000},
        Increment = 50,
        CurrentValue = 500,
        Suffix = " studs",
        Flag = "MaMEspMaxDist",
        Callback = function(v) settings.espMaxDist = v end,
    })
    EspTab:CreateSlider({
        Name = "Min Tier Filter",
        Range = {1, 6},
        Increment = 1,
        CurrentValue = 1,
        Suffix = "",
        Flag = "MaMEspMinTier",
        Callback = function(v) settings.espMinTier = v end,
    })
    EspTab:CreateSlider({
        Name = "Min Value Filter",
        Range = {0, 100000},
        Increment = 1000,
        CurrentValue = 0,
        Suffix = "",
        Flag = "MaMEspMinValue",
        Callback = function(v) settings.espMinValue = v end,
    })
    EspTab:CreateToggle({
        Name = "Show Dropped Crystals",
        CurrentValue = true,
        Flag = "MaMEspDropped",
        Callback = function(v) settings.espShowDropped = v end,
    })
    EspTab:CreateToggle({
        Name = "Show Map Crystals",
        CurrentValue = true,
        Flag = "MaMEspMap",
        Callback = function(v) settings.espShowMap = v end,
    })
    EspTab:CreateToggle({
        Name = "Show Mutation Indicator",
        CurrentValue = true,
        Flag = "MaMEspMutation",
        Callback = function(v) settings.espShowMutation = v end,
    })

    local espCountLabel = EspTab:CreateLabel("ESP Crystals: 0")

    -- TELEPORT TAB
    local TpTab = Window:CreateTab("Teleport", "movement")

    TpTab:CreateSection("Auto Teleport")
    TpTab:CreateToggle({
        Name = "Auto TP to Best Crystal",
        CurrentValue = false,
        Flag = "MaMAutoTP",
        Callback = function(v) settings.autoTP = v end,
    })
    TpTab:CreateSlider({
        Name = "TP Min Tier",
        Range = {1, 6},
        Increment = 1,
        CurrentValue = 4,
        Suffix = "",
        Flag = "MaMTpMinTier",
        Callback = function(v) settings.tpMinTier = v end,
    })
    TpTab:CreateSlider({
        Name = "TP Min Value",
        Range = {0, 500000},
        Increment = 5000,
        CurrentValue = 10000,
        Suffix = "",
        Flag = "MaMTpMinValue",
        Callback = function(v) settings.tpMinValue = v end,
    })
    TpTab:CreateSlider({
        Name = "TP Cooldown",
        Range = {1, 30},
        Increment = 1,
        CurrentValue = 3,
        Suffix = " s",
        Flag = "MaMTpCooldown",
        Callback = function(v) settings.tpCooldown = v end,
    })

    TpTab:CreateSection("Quick Teleport")
    TpTab:CreateButton({
        Name = "🏔️ TP to Mountain Top",
        Callback = function()
            -- Mountain center is around x:70 z:1070, go high
            teleportTo(Vector3.new(70, 500, 1070))
            notify("⛰️ MaM", "Teleported to mountain top area")
        end,
    })
    TpTab:CreateButton({
        Name = "🏠 TP to Base/Spawn",
        Callback = function()
            teleportTo(Vector3.new(-14, 35, 1076))
            notify("⛰️ MaM", "Teleported to base")
        end,
    })
    TpTab:CreateButton({
        Name = "💰 TP to Sell Area",
        Callback = function()
            -- SellProx position
            teleportTo(Vector3.new(-44, 32, 1067))
            notify("⛰️ MaM", "Teleported to sell area")
        end,
    })
    TpTab:CreateButton({
        Name = "🛒 TP to Shop",
        Callback = function()
            teleportTo(Vector3.new(17, 32, 1086))
            notify("⛰️ MaM", "Teleported to shop")
        end,
    })
    TpTab:CreateButton({
        Name = "💎 TP to Best Dropped Crystal",
        Callback = function()
            local _, _, root = getCharacter()
            if not root then return end
            local best, bestVal = nil, 0
            local dc = workspace:FindFirstChild("DroppedCrystals")
            if dc then
                for _, c in ipairs(dc:GetChildren()) do
                    if c:IsA("BasePart") then
                        local val = c:GetAttribute("Value") or 0
                        if val > bestVal then bestVal = val; best = c end
                    end
                end
            end
            if best then
                teleportTo(best.Position + Vector3.new(0, 5, 0))
                notify("⛰️ MaM", "TP to " .. (best:GetAttribute("CrystalName") or "crystal") .. " " .. fmtNum(bestVal))
            else
                notify("⛰️ MaM", "No dropped crystals found")
            end
        end,
    })

    -- UTILITY TAB
    local UtilTab = Window:CreateTab("Utility", "misc")

    UtilTab:CreateSection("Stability")
    UtilTab:CreateToggle({
        Name = "Anti AFK",
        CurrentValue = true,
        Flag = "MaMAntiAfk",
        Callback = function(v) settings.antiAfk = v end,
    })
    UtilTab:CreateToggle({
        Name = "Auto Rejoin On Disconnect",
        CurrentValue = false,
        Flag = "MaMAutoRejoin",
        Callback = function(v) settings.autoRejoin = v end,
    })

    UtilTab:CreateSection("Info")
    local infoLabel = UtilTab:CreateLabel("Loading stats...")

    UtilTab:CreateSection("Actions")
    UtilTab:CreateButton({
        Name = "🔄 Rescan Crystals",
        Callback = function()
            clearAllESP()
            scanCrystals()
            local count = 0
            for _ in pairs(espObjects) do count += 1 end
            notify("⛰️ MaM", "Rescanned: " .. count .. " crystals found")
        end,
    })
    UtilTab:CreateButton({
        Name = "🧹 Clear ESP",
        Callback = function()
            clearAllESP()
            notify("⛰️ MaM", "ESP cleared")
        end,
    })

    -- ============================================================
    -- ANTI AFK
    -- ============================================================
    connect(player.Idled, function()
        if settings.antiAfk then
            VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
            task.wait(0.3)
            VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
        end
    end)

    -- ============================================================
    -- AUTO REJOIN
    -- ============================================================
    local rejoinPending = false
    connect(game:GetService("GuiService").ErrorMessageChanged, function(message)
        if settings.autoRejoin and not rejoinPending and message and message ~= "" then
            rejoinPending = true
            task.delay(2, function()
                local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, game.JobId, player)
                if not ok then
                    pcall(TeleportService.Teleport, TeleportService, game.PlaceId, player)
                end
                rejoinPending = false
            end)
        end
    end)

    -- ============================================================
    -- MAIN LOOP
    -- ============================================================
    local tickCount = 0
    local startTime = os.clock()

    task.spawn(function()
        -- Initial scan
        scanCrystals()

        while running do
            local iterOk, iterErr = xpcall(function()
                tickCount += 1

                -- Auto Mine (every frame check)
                doAutoMine()

                -- Auto Sell (every 30 ticks)
                if tickCount % 30 == 0 then
                    doAutoSell()
                    doAutoBomb()
                    doAutoTP()
                    doAutoPickup()
                end

                -- ESP update (every 3 ticks)
                if tickCount % 3 == 0 then
                    updateESP()
                end

                -- Rescan (every 90 ticks)
                if tickCount % 90 == 0 then
                    scanCrystals()
                end

                -- Update UI labels (every 120 ticks)
                if tickCount % 120 == 0 then
                    local espCount = 0
                    for _ in pairs(espObjects) do espCount += 1 end
                    pcall(function() espCountLabel:Set("ESP Crystals: " .. espCount) end)

                    local ls = player:FindFirstChild("leaderstats")
                    local coins = ls and ls:FindFirstChild("Coins") and ls.Coins.Value or "?"
                    local height = ls and ls:FindFirstChild("Height") and ls.Height.Value or "?"
                    local best = ls and ls:FindFirstChild("Best") and ls.Best.Value or "?"
                    local elapsed = math.floor((os.clock() - startTime) / 60)

                    pcall(function()
                        mineStatus:Set(string.format("Digs: %d | Sells: %d | %dm", totalDigs, totalSells, elapsed))
                    end)
                    pcall(function()
                        infoLabel:Set(string.format("💰 %s | 📏 %s | 🏆 %s", coins, height, best))
                    end)
                end
            end, function(err)
                warn("[RAVEN / MaM] loop error: " .. tostring(err))
            end)

            task.wait(1 / 60) -- ~60 Hz
        end
    end)

    -- ============================================================
    -- CLEANUP / DESTROY
    -- ============================================================
    local function Destroy()
        running = false
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        connections = {}
        clearAllESP()
        if espFolder and espFolder.Parent then espFolder:Destroy() end
        environment.__RAVEN_MAM = nil
    end

    environment.__RAVEN_MAM = {Destroy = Destroy}

    -- Unload hook
    if Window and type(Window.OnUnload) == "function" then
        Window:OnUnload(Destroy)
    end

    notify("⛰️ Mine a Mountain", "Module loaded! " .. tostring(select(2, next(espObjects)) and "ESP active" or "Scanning..."))
end
