-- ============================================================
--   RAVEN HUB  |  BloxStrike Modular Suite v1.1.0
--   Anti-Cheat Safe (BAC / Frog Compliant Drawing API ESP)
--   Match Analytics, Live Telemetry & Combat Visuals
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local Stats = game:GetService("Stats")

    -- Clean up previous instance if running
    local env = getgenv and getgenv() or _G
    if type(env.__RAVEN_BLOXSTRIKE) == "table" and type(env.__RAVEN_BLOXSTRIKE.Destroy) == "function" then
        pcall(env.__RAVEN_BLOXSTRIKE.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera")

    local running = true
    local connections = {}

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(connections, conn)
        return conn
    end

    -- ------------------------------------------------------------
    -- Settings & Telemetry State
    -- ------------------------------------------------------------
    local state = {
        fps = 0,
        ping = 0,
        lastTick = os.clock(),
        frameCount = 0,
        playerHealth = 100,
        playerMaxHealth = 100,
        isCrouching = false,
        isWalking = false,
        currentTeam = "Unknown",
        equippedWeapon = "None",
        ctAlive = 0,
        tAlive = 0,
        c4Planted = false,
    }

    local espSettings = {
        enabled = true,
        teamCheck = true,            -- Only show enemies
        showBoxes = true,
        boxOutline = true,
        showNames = true,
        showDistance = true,
        showHealth = true,
        showHealthText = true,
        showWeapon = true,
        showHeadDot = false,
        showTracers = false,
        showC4 = true,
        showBombCarrier = true,
        useTeamColors = false,       -- CT=Blue, T=Orange vs Enemy=Red, Ally=Green
        maxDistance = 1500,

        -- Theme Palette
        enemyColor = Color3.fromRGB(255, 65, 65),
        teamColor = Color3.fromRGB(65, 220, 120),
        ctColor = Color3.fromRGB(65, 155, 255),
        tColor = Color3.fromRGB(255, 160, 45),
        c4Color = Color3.fromRGB(255, 220, 30),
        headColor = Color3.fromRGB(255, 255, 255),
        tracerColor = Color3.fromRGB(255, 90, 90),
    }

    -- ------------------------------------------------------------
    -- Drawing API Helpers & Lifecycle
    -- ------------------------------------------------------------
    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local espDrawings = {}

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        if ok and obj then
            return obj
        end
        return nil
    end

    local function newDrawingSet()
        local d = {}

        d.boxOutline = safeDrawing("Square")
        if d.boxOutline then
            d.boxOutline.Thickness = 3
            d.boxOutline.Filled = false
            d.boxOutline.Color = Color3.fromRGB(0, 0, 0)
            d.boxOutline.Visible = false
        end

        d.box = safeDrawing("Square")
        if d.box then
            d.box.Thickness = 1
            d.box.Filled = false
            d.box.Color = Color3.fromRGB(255, 255, 255)
            d.box.Visible = false
        end

        d.name = safeDrawing("Text")
        if d.name then
            d.name.Size = 13
            d.name.Center = true
            d.name.Outline = true
            d.name.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.name.Color = Color3.fromRGB(255, 255, 255)
            d.name.Visible = false
        end

        d.dist = safeDrawing("Text")
        if d.dist then
            d.dist.Size = 11
            d.dist.Center = true
            d.dist.Outline = true
            d.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.dist.Color = Color3.fromRGB(220, 220, 220)
            d.dist.Visible = false
        end

        d.hpBg = safeDrawing("Square")
        if d.hpBg then
            d.hpBg.Thickness = 1
            d.hpBg.Filled = true
            d.hpBg.Color = Color3.fromRGB(25, 25, 25)
            d.hpBg.Visible = false
        end

        d.hp = safeDrawing("Square")
        if d.hp then
            d.hp.Thickness = 1
            d.hp.Filled = true
            d.hp.Color = Color3.fromRGB(0, 255, 100)
            d.hp.Visible = false
        end

        d.hpText = safeDrawing("Text")
        if d.hpText then
            d.hpText.Size = 10
            d.hpText.Center = false
            d.hpText.Outline = true
            d.hpText.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.hpText.Color = Color3.fromRGB(255, 255, 255)
            d.hpText.Visible = false
        end

        d.weapon = safeDrawing("Text")
        if d.weapon then
            d.weapon.Size = 11
            d.weapon.Center = true
            d.weapon.Outline = true
            d.weapon.OutlineColor = Color3.fromRGB(0, 0, 0)
            d.weapon.Color = Color3.fromRGB(255, 215, 60)
            d.weapon.Visible = false
        end

        d.head = safeDrawing("Circle")
        if d.head then
            d.head.Thickness = 1
            d.head.Filled = false
            d.head.Radius = 3
            d.head.Color = Color3.fromRGB(255, 255, 255)
            d.head.Visible = false
        end

        d.tracer = safeDrawing("Line")
        if d.tracer then
            d.tracer.Thickness = 1
            d.tracer.Color = Color3.fromRGB(255, 90, 90)
            d.tracer.Visible = false
        end

        return d
    end

    local function hideDrawingSet(d)
        if not d then return end
        for _, obj in pairs(d) do
            if obj and obj.Visible then
                pcall(function() obj.Visible = false end)
            end
        end
    end

    local function removeDrawingSet(d)
        if not d then return end
        for _, obj in pairs(d) do
            if obj then
                pcall(function()
                    obj.Visible = false
                    obj:Remove()
                end)
            end
        end
    end

    -- C4 Visual Object
    local c4Visual = {
        txt = safeDrawing("Text"),
        box = safeDrawing("Square"),
    }
    if c4Visual.txt then
        c4Visual.txt.Size = 13
        c4Visual.txt.Center = true
        c4Visual.txt.Outline = true
        c4Visual.txt.OutlineColor = Color3.fromRGB(0, 0, 0)
        c4Visual.txt.Color = espSettings.c4Color
        c4Visual.txt.Visible = false
    end
    if c4Visual.box then
        c4Visual.box.Thickness = 1
        c4Visual.box.Filled = false
        c4Visual.box.Color = espSettings.c4Color
        c4Visual.box.Visible = false
    end

    local function hideC4Visual()
        if c4Visual.txt then c4Visual.txt.Visible = false end
        if c4Visual.box then c4Visual.box.Visible = false end
    end

    -- ------------------------------------------------------------
    -- Telemetry Updater
    -- ------------------------------------------------------------
    local function updateTelemetry()
        -- FPS Calculation
        state.frameCount = state.frameCount + 1
        local now = os.clock()
        if now - state.lastTick >= 1.0 then
            state.fps = math.floor(state.frameCount / (now - state.lastTick))
            state.frameCount = 0
            state.lastTick = now
        end

        -- Ping Calculation
        pcall(function()
            local item = Stats.Network.ServerStatsItem:FindFirstChild("Data Ping")
            if item then
                state.ping = math.floor(item:GetValue())
            end
        end)

        -- Local Character Diagnostics
        local char = localPlayer.Character
        if char then
            state.playerHealth = tonumber(char:GetAttribute("Health")) or (char:FindFirstChildOfClass("Humanoid") and char:FindFirstChildOfClass("Humanoid").Health) or 0
            state.playerMaxHealth = tonumber(char:GetAttribute("MaxHealth")) or 100
            state.isCrouching = char:GetAttribute("IsCrouching") or false
            state.isWalking = char:GetAttribute("IsWalking") or false
            local charType = char:GetAttribute("CharacterName") or ""
            state.currentTeam = charType ~= "" and charType or (localPlayer:GetAttribute("Team") or "Unknown")

            local currentEquipped = localPlayer:GetAttribute("CurrentEquipped")
            if type(currentEquipped) == "string" then
                local wName = string.match(currentEquipped, '"Name"%s*:%s*"([^"]+)"')
                state.equippedWeapon = wName or "Holstered / Knife"
            else
                local equipped = char:FindFirstChildOfClass("Tool")
                state.equippedWeapon = equipped and equipped.Name or "Knife / Holstered"
            end
        end

        -- Match Alive Counts
        local charactersFolder = Workspace:FindFirstChild("Characters")
        if charactersFolder then
            local ctCount = 0
            local tCount = 0
            for _, model in ipairs(charactersFolder:GetChildren()) do
                if model:IsA("Model") then
                    local dead = model:GetAttribute("Dead")
                    if dead == false then
                        local plr = Players:FindFirstChild(model.Name)
                        local team = plr and plr:GetAttribute("Team") or ""
                        if team == "Counter-Terrorists" then
                            ctCount = ctCount + 1
                        elseif team == "Terrorists" then
                            tCount = tCount + 1
                        else
                            local charName = model:GetAttribute("CharacterName") or ""
                            if charName == "IDF" or charName == "SAS" or charName == "FBI" or charName == "GIGN" or charName == "SWAT" then
                                ctCount = ctCount + 1
                            else
                                tCount = tCount + 1
                            end
                        end
                    end
                end
            end
            state.ctAlive = ctCount
            state.tAlive = tCount
        end

        -- C4 Status in Debris
        local debris = Workspace:FindFirstChild("Debris")
        if debris and debris:FindFirstChild("C4") then
            state.c4Planted = true
        else
            state.c4Planted = false
        end
    end

    connect(RunService.Heartbeat, function()
        if not running then return end
        updateTelemetry()
    end)

    -- ------------------------------------------------------------
    -- RenderStepped ESP Engine (Zero Memory Leaks / Frog Safe)
    -- ------------------------------------------------------------
    local function renderESP()
        if not running or not hasDrawing then return end

        if not camera or not camera.Parent then
            camera = Workspace.CurrentCamera or Workspace:FindFirstChildOfClass("Camera")
        end
        if not camera then return end

        if not espSettings.enabled then
            for _, d in pairs(espDrawings) do
                hideDrawingSet(d)
            end
            hideC4Visual()
            return
        end

        local charactersFolder = Workspace:FindFirstChild("Characters")
        if not charactersFolder then
            for _, d in pairs(espDrawings) do
                hideDrawingSet(d)
            end
            hideC4Visual()
            return
        end

        local myPos = camera.CFrame.Position
        local viewportSize = camera.ViewportSize
        local myTeam = localPlayer:GetAttribute("Team")
        local activeSet = {}

        for _, char in ipairs(charactersFolder:GetChildren()) do
            if char:IsA("Model") and char ~= localPlayer.Character and char.Name ~= localPlayer.Name then
                activeSet[char] = true

                if not espDrawings[char] then
                    espDrawings[char] = newDrawingSet()
                end
                local d = espDrawings[char]

                local isDead = char:GetAttribute("Dead") == true
                local hp = tonumber(char:GetAttribute("Health")) or 0
                local maxHp = tonumber(char:GetAttribute("MaxHealth")) or 100

                if isDead or hp <= 0 then
                    hideDrawingSet(d)
                    continue
                end

                -- Team Check
                local plr = Players:FindFirstChild(char.Name)
                local plrTeam = plr and plr:GetAttribute("Team")
                if not plrTeam then
                    local charName = char:GetAttribute("CharacterName") or ""
                    if charName == "IDF" or charName == "SAS" or charName == "FBI" or charName == "GIGN" or charName == "SWAT" then
                        plrTeam = "Counter-Terrorists"
                    else
                        plrTeam = "Terrorists"
                    end
                end

                local isTeammate = (myTeam ~= nil and plrTeam ~= nil and myTeam == plrTeam)
                if espSettings.teamCheck and isTeammate then
                    hideDrawingSet(d)
                    continue
                end

                local rootPart = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
                if not rootPart or not rootPart:IsA("BasePart") then
                    hideDrawingSet(d)
                    continue
                end

                local rootPos3D = rootPart.Position
                local dist = (rootPos3D - myPos).Magnitude
                if dist > espSettings.maxDistance then
                    hideDrawingSet(d)
                    continue
                end

                local head = char:FindFirstChild("Head")
                local headPos3D = head and head.Position or (rootPos3D + Vector3.new(0, 1.5, 0))

                local topWorld = headPos3D + Vector3.new(0, 0.7, 0)
                local bottomWorld = rootPos3D - Vector3.new(0, 2.7, 0)

                local rootScreen, onScreen = camera:WorldToViewportPoint(rootPos3D)
                if not onScreen or rootScreen.Z <= 0 then
                    hideDrawingSet(d)
                    continue
                end

                local topScreen = camera:WorldToViewportPoint(topWorld)
                local bottomScreen = camera:WorldToViewportPoint(bottomWorld)

                local boxHeight = math.abs(bottomScreen.Y - topScreen.Y)
                if boxHeight < 4 then
                    hideDrawingSet(d)
                    continue
                end

                local boxWidth = math.floor(boxHeight * 0.58)
                local boxX = math.floor(rootScreen.X - boxWidth / 2)
                local boxY = math.floor(topScreen.Y)

                -- Color Selection
                local mainColor
                if espSettings.useTeamColors then
                    mainColor = (plrTeam == "Counter-Terrorists") and espSettings.ctColor or espSettings.tColor
                else
                    mainColor = isTeammate and espSettings.teamColor or espSettings.enemyColor
                end

                -- 1. Bounding Box
                if espSettings.showBoxes and d.box then
                    if espSettings.boxOutline and d.boxOutline then
                        d.boxOutline.Size = Vector2.new(boxWidth + 2, boxHeight + 2)
                        d.boxOutline.Position = Vector2.new(boxX - 1, boxY - 1)
                        d.boxOutline.Visible = true
                    elseif d.boxOutline then
                        d.boxOutline.Visible = false
                    end

                    d.box.Size = Vector2.new(boxWidth, boxHeight)
                    d.box.Position = Vector2.new(boxX, boxY)
                    d.box.Color = mainColor
                    d.box.Visible = true
                else
                    if d.box then d.box.Visible = false end
                    if d.boxOutline then d.boxOutline.Visible = false end
                end

                -- 2. Player Name & Carrier Tag
                if espSettings.showNames and d.name then
                    local nameLabel = char.Name
                    if espSettings.showBombCarrier and plr and plr:GetAttribute("Slot5") then
                        local s5 = plr:GetAttribute("Slot5")
                        if type(s5) == "string" and string.find(s5, '"Weapon"%s*:%s*"C4"') then
                            nameLabel = "[BOMB] " .. nameLabel
                        end
                    end
                    d.name.Text = nameLabel
                    d.name.Position = Vector2.new(boxX + boxWidth / 2, boxY - 16)
                    d.name.Color = mainColor
                    d.name.Visible = true
                else
                    if d.name then d.name.Visible = false end
                end

                -- 3. Distance Text
                if espSettings.showDistance and d.dist then
                    local meters = math.floor(dist * 0.28) -- approximate studs to meters conversion
                    d.dist.Text = string.format("[%dm]", meters)
                    d.dist.Position = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight + 2)
                    d.dist.Visible = true
                else
                    if d.dist then d.dist.Visible = false end
                end

                -- 4. Health Bar & HP Text
                if espSettings.showHealth and d.hp and d.hpBg then
                    local hpRatio = math.clamp(hp / math.max(maxHp, 1), 0, 1)
                    local barWidth = 3
                    local barX = boxX - barWidth - 3

                    d.hpBg.Size = Vector2.new(barWidth, boxHeight + 2)
                    d.hpBg.Position = Vector2.new(barX, boxY - 1)
                    d.hpBg.Visible = true

                    local fillHeight = math.floor(boxHeight * hpRatio)
                    d.hp.Size = Vector2.new(barWidth, fillHeight)
                    d.hp.Position = Vector2.new(barX, boxY + (boxHeight - fillHeight))
                    d.hp.Color = Color3.fromHSV(hpRatio * 0.33, 0.9, 1.0)
                    d.hp.Visible = true

                    if espSettings.showHealthText and d.hpText and hp < maxHp then
                        d.hpText.Text = tostring(math.floor(hp))
                        d.hpText.Position = Vector2.new(barX - 22, boxY + (boxHeight - fillHeight) - 2)
                        d.hpText.Visible = true
                    else
                        if d.hpText then d.hpText.Visible = false end
                    end
                else
                    if d.hp then d.hp.Visible = false end
                    if d.hpBg then d.hpBg.Visible = false end
                    if d.hpText then d.hpText.Visible = false end
                end

                -- 5. Equipped Weapon
                if espSettings.showWeapon and d.weapon then
                    local wName = nil
                    if plr then
                        local currentEquipped = plr:GetAttribute("CurrentEquipped")
                        if type(currentEquipped) == "string" then
                            wName = string.match(currentEquipped, '"Name"%s*:%s*"([^"]+)"')
                        end
                    end
                    d.weapon.Text = wName or "Knife"
                    local weaponOffsetY = espSettings.showDistance and 15 or 2
                    d.weapon.Position = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight + weaponOffsetY)
                    d.weapon.Visible = true
                else
                    if d.weapon then d.weapon.Visible = false end
                end

                -- 6. Head Dot / Circle
                if espSettings.showHeadDot and d.head then
                    local headScreen, headOnScreen = camera:WorldToViewportPoint(headPos3D)
                    if headOnScreen and headScreen.Z > 0 then
                        d.head.Position = Vector2.new(headScreen.X, headScreen.Y)
                        d.head.Radius = math.clamp(boxWidth * 0.16, 2, 7)
                        d.head.Color = espSettings.headColor
                        d.head.Visible = true
                    else
                        d.head.Visible = false
                    end
                else
                    if d.head then d.head.Visible = false end
                end

                -- 7. Snaplines / Tracers
                if espSettings.showTracers and d.tracer then
                    d.tracer.From = Vector2.new(viewportSize.X / 2, viewportSize.Y)
                    d.tracer.To = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight)
                    d.tracer.Color = mainColor
                    d.tracer.Visible = true
                else
                    if d.tracer then d.tracer.Visible = false end
                end
            end
        end

        -- Clean up removed models from cache
        for model, d in pairs(espDrawings) do
            if not activeSet[model] or not model.Parent then
                removeDrawingSet(d)
                espDrawings[model] = nil
            end
        end

        -- 8. C4 Objective ESP (Planted or Dropped)
        if espSettings.showC4 and c4Visual.txt then
            local debris = Workspace:FindFirstChild("Debris")
            local c4Obj = debris and debris:FindFirstChild("C4")
            if not c4Obj then
                local map = Workspace:FindFirstChild("Map")
                c4Obj = map and map:FindFirstChild("C4", true)
            end

            if c4Obj then
                local c4Pos = c4Obj:IsA("BasePart") and c4Obj.Position or (c4Obj.PrimaryPart and c4Obj.PrimaryPart.Position) or (c4Obj:FindFirstChildWhichIsA("BasePart") and c4Obj:FindFirstChildWhichIsA("BasePart").Position)
                if c4Pos then
                    local screenPos, onScreen = camera:WorldToViewportPoint(c4Pos)
                    if onScreen and screenPos.Z > 0 then
                        local c4Dist = math.floor((c4Pos - myPos).Magnitude * 0.28)
                        c4Visual.txt.Text = string.format("[C4 BOMB - %dm]", c4Dist)
                        c4Visual.txt.Position = Vector2.new(screenPos.X, screenPos.Y - 10)
                        c4Visual.txt.Visible = true

                        if c4Visual.box then
                            local bSize = math.clamp(300 / screenPos.Z, 10, 40)
                            c4Visual.box.Size = Vector2.new(bSize, bSize)
                            c4Visual.box.Position = Vector2.new(screenPos.X - bSize / 2, screenPos.Y - bSize / 2)
                            c4Visual.box.Visible = true
                        end
                    else
                        hideC4Visual()
                    end
                else
                    hideC4Visual()
                end
            else
                hideC4Visual()
            end
        else
            hideC4Visual()
        end
    end

    connect(RunService.RenderStepped, renderESP)

    -- ============================================================
    --   MACLIB USER INTERFACE
    -- ============================================================

    -- Tab 1: Match Status & Objectives
    local MatchTab = Window:CreateTab("Match Info", "overview")
    MatchTab:CreateSection("Live Match Overview")

    local ctLabel = MatchTab:CreateParagraph({
        Title = "Counter-Terrorists Alive",
        Content = "Calculating..."
    })

    local tLabel = MatchTab:CreateParagraph({
        Title = "Terrorists Alive",
        Content = "Calculating..."
    })

    local c4Label = MatchTab:CreateParagraph({
        Title = "Bomb Status",
        Content = "No C4 Detected"
    })

    -- Tab 2: Visuals / ESP (Drawing API)
    local EspTab = Window:CreateTab("Visuals", "esp")
    EspTab:CreateSection("Master Controls")

    EspTab:CreateToggle({
        Name = "Enable ESP",
        CurrentValue = espSettings.enabled,
        Flag = "BS_Esp_Master",
        Callback = function(val)
            espSettings.enabled = val
        end
    })

    EspTab:CreateToggle({
        Name = "Enemy Only (Team Check)",
        CurrentValue = espSettings.teamCheck,
        Flag = "BS_Esp_TeamCheck",
        Callback = function(val)
            espSettings.teamCheck = val
        end
    })

    EspTab:CreateSlider({
        Name = "Max ESP Distance",
        Range = {100, 3000},
        Increment = 100,
        CurrentValue = espSettings.maxDistance,
        Suffix = " studs",
        Flag = "BS_Esp_MaxDist",
        Callback = function(val)
            espSettings.maxDistance = val
        end
    })

    EspTab:CreateSection("Box & Visual Overlays")

    EspTab:CreateToggle({
        Name = "2D Bounding Box",
        CurrentValue = espSettings.showBoxes,
        Flag = "BS_Esp_Boxes",
        Callback = function(val)
            espSettings.showBoxes = val
        end
    })

    EspTab:CreateToggle({
        Name = "Box Outline",
        CurrentValue = espSettings.boxOutline,
        Flag = "BS_Esp_BoxOutline",
        Callback = function(val)
            espSettings.boxOutline = val
        end
    })

    EspTab:CreateToggle({
        Name = "Health Bar & Indicator",
        CurrentValue = espSettings.showHealth,
        Flag = "BS_Esp_Health",
        Callback = function(val)
            espSettings.showHealth = val
        end
    })

    EspTab:CreateToggle({
        Name = "Head Dot / Circle",
        CurrentValue = espSettings.showHeadDot,
        Flag = "BS_Esp_HeadDot",
        Callback = function(val)
            espSettings.showHeadDot = val
        end
    })

    EspTab:CreateToggle({
        Name = "Snaplines / Tracers",
        CurrentValue = espSettings.showTracers,
        Flag = "BS_Esp_Tracers",
        Callback = function(val)
            espSettings.showTracers = val
        end
    })

    EspTab:CreateSection("Player Info & Objectives")

    EspTab:CreateToggle({
        Name = "Player Names",
        CurrentValue = espSettings.showNames,
        Flag = "BS_Esp_Names",
        Callback = function(val)
            espSettings.showNames = val
        end
    })

    EspTab:CreateToggle({
        Name = "Distance Label",
        CurrentValue = espSettings.showDistance,
        Flag = "BS_Esp_Distance",
        Callback = function(val)
            espSettings.showDistance = val
        end
    })

    EspTab:CreateToggle({
        Name = "Equipped Weapon",
        CurrentValue = espSettings.showWeapon,
        Flag = "BS_Esp_Weapon",
        Callback = function(val)
            espSettings.showWeapon = val
        end
    })

    EspTab:CreateToggle({
        Name = "Bomb Carrier Highlight",
        CurrentValue = espSettings.showBombCarrier,
        Flag = "BS_Esp_Carrier",
        Callback = function(val)
            espSettings.showBombCarrier = val
        end
    })

    EspTab:CreateToggle({
        Name = "C4 Objective ESP",
        CurrentValue = espSettings.showC4,
        Flag = "BS_Esp_C4",
        Callback = function(val)
            espSettings.showC4 = val
        end
    })

    EspTab:CreateToggle({
        Name = "Faction Colors (CT=Blue, T=Orange)",
        CurrentValue = espSettings.useTeamColors,
        Flag = "BS_Esp_FactionColors",
        Callback = function(val)
            espSettings.useTeamColors = val
        end
    })

    -- Tab 3: Player Diagnostics
    local PlayerTab = Window:CreateTab("Player State", "player")
    PlayerTab:CreateSection("Character Telemetry")

    local healthLabel = PlayerTab:CreateParagraph({
        Title = "Health Status",
        Content = "100 / 100"
    })

    local stanceLabel = PlayerTab:CreateParagraph({
        Title = "Stance & Movement",
        Content = "Standing"
    })

    local weaponLabel = PlayerTab:CreateParagraph({
        Title = "Equipped Weapon",
        Content = "None"
    })

    -- Tab 4: Performance & Network
    local PerfTab = Window:CreateTab("Diagnostics", "tools")
    PerfTab:CreateSection("System Performance")

    local fpsLabel = PerfTab:CreateParagraph({
        Title = "Client Framerate",
        Content = "60 FPS"
    })

    local pingLabel = PerfTab:CreateParagraph({
        Title = "Network Latency",
        Content = "0 ms"
    })

    local coordsLabel = PerfTab:CreateParagraph({
        Title = "Current Coordinates",
        Content = "X: 0 | Y: 0 | Z: 0"
    })

    -- Background UI Refresh Loop (Every 0.5s to conserve resources)
    task.spawn(function()
        while running do
            pcall(function()
                if ctLabel and ctLabel.SetDesc then
                    ctLabel:SetDesc(string.format("%d Players Alive", state.ctAlive))
                end
                if tLabel and tLabel.SetDesc then
                    tLabel:SetDesc(string.format("%d Players Alive", state.tAlive))
                end
                if c4Label and c4Label.SetDesc then
                    c4Label:SetDesc(state.c4Planted and "[!] C4 IS ARMED / PLANTED" or "C4 Not Planted")
                end

                if healthLabel and healthLabel.SetDesc then
                    healthLabel:SetDesc(string.format("%d / %d HP", state.playerHealth, state.playerMaxHealth))
                end
                if stanceLabel and stanceLabel.SetDesc then
                    local stance = state.isCrouching and "Crouching" or (state.isWalking and "Walking" or "Running/Standing")
                    stanceLabel:SetDesc(stance)
                end
                if weaponLabel and weaponLabel.SetDesc then
                    weaponLabel:SetDesc(state.equippedWeapon)
                end

                if fpsLabel and fpsLabel.SetDesc then
                    fpsLabel:SetDesc(string.format("%d FPS", state.fps))
                end
                if pingLabel and pingLabel.SetDesc then
                    pingLabel:SetDesc(string.format("%d ms", state.ping))
                end
                if coordsLabel and coordsLabel.SetDesc then
                    local char = localPlayer.Character
                    local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso"))
                    if root then
                        local pos = root.Position
                        coordsLabel:SetDesc(string.format("X: %.1f | Y: %.1f | Z: %.1f", pos.X, pos.Y, pos.Z))
                    end
                end
            end)
            task.wait(0.5)
        end
    end)

    -- Cleanup Handler
    local function cleanup()
        running = false
        for _, conn in ipairs(connections) do
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
        end
        table.clear(connections)

        for _, d in pairs(espDrawings) do
            removeDrawingSet(d)
        end
        table.clear(espDrawings)

        if c4Visual.txt then pcall(function() c4Visual.txt:Remove() end) end
        if c4Visual.box then pcall(function() c4Visual.box:Remove() end) end

        env.__RAVEN_BLOXSTRIKE = nil
    end

    env.__RAVEN_BLOXSTRIKE = {
        Destroy = cleanup
    }

    return {
        Cleanup = cleanup
    }
end
