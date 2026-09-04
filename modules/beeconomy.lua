-- ═══════════════════════════════════════════════════════════
-- Beeconomy! | RAVEN HUB Module v1.2.0
-- PlaceId: 101558830312092 | GameId: 7000989941
-- Features: Auto Farm Pollen (Whole-Field Lawn Mower / Sweep / Orbit), Auto Orbs Magnet,
--           Auto Honey Convert (Auto Re-equip Shovel), Infinite Stamina, Auto Fish, ESP
-- Tested live on client via Raven MCP
-- ═══════════════════════════════════════════════════════════
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")
    local Lighting = game:GetService("Lighting")
    local UserInputService = game:GetService("UserInputService")

    local Player = Players.LocalPlayer
    local running = true
    local threads = {}
    local connections = {}

    -- ═══════════ Controller & Systems Discovery ═══════════
    local clientController = nil
    local reelMinigameObj = nil

    local function findControllers()
        local gc = getgc(true)
        for _, item in ipairs(gc) do
            if type(item) == "table" then
                if not clientController and rawget(item, "Network") and rawget(item, "PlayerData") and rawget(item, "ScooperTool") then
                    clientController = item
                end
                if not reelMinigameObj and rawget(item, "HandleInputBegan") and rawget(item, "_finishGame") and rawget(item, "Start") then
                    reelMinigameObj = item
                end
            end
        end
    end
    findControllers()

    -- ═══════════ Coordinates & Map Data ═══════════
    local FIELDS = {
        ["Dandylion Field"]     = Vector3.new(1315.0, -24.1, 425.6),
        ["Sunflower Field"]     = Vector3.new(1410.6, -19.4, 433.6),
        ["Mushroom Field"]      = Vector3.new(1428.4, -19.5, 579.9),
        ["Magic Field"]         = Vector3.new(1591.9, -19.9, 482.5),
        ["Magic Field 2"]       = Vector3.new(1681.6, -15.2, 425.9),
        ["Magic Field 3"]       = Vector3.new(1733.5, -14.0, 559.5),
        ["Pumpkin Field"]       = Vector3.new(1694.2, 2.1, 330.5),
        ["White Pumpkin Field"] = Vector3.new(1829.9, 6.5, 217.4),
        ["Corn Field"]          = Vector3.new(1866.4, 1.5, 327.2),
        ["Desert Field 1"]      = Vector3.new(1919.0, 20.1, 338.6),
        ["Desert Field 2"]      = Vector3.new(1985.3, 19.9, 117.4),
        ["Jungle Field 1"]      = Vector3.new(2003.7, 19.7, 588.7),
        ["Jungle Field 2"]      = Vector3.new(1877.1, 19.5, 448.6),
        ["Jungle Field 3"]      = Vector3.new(1738.5, 19.7, 707.3),
        ["Snow Field"]          = Vector3.new(1885.9, 82.5, 859.3),
        ["Snow Field 2"]        = Vector3.new(1616.7, 107.5, 900.3),
        ["Snow Field 3"]        = Vector3.new(1596.8, 108.2, 1087.1),
        ["Cave Field"]          = Vector3.new(2242.8, 53.5, 613.5),
        ["Cave Field 2"]        = Vector3.new(2353.5, 52.1, 530.8),
        ["City Central Field"]  = Vector3.new(1217.6, 130.8, 888.4),
        ["City Side Field"]     = Vector3.new(1347.9, 130.8, 1088.6),
        ["Ember Field 1"]       = Vector3.new(2195.1, 83.4, 912.8),
        ["Ember Field 2"]       = Vector3.new(2167.7, 83.4, 1130.5),
    }

    local FIELD_NAMES = {}
    for name in pairs(FIELDS) do
        table.insert(FIELD_NAMES, name)
    end
    table.sort(FIELD_NAMES)

    local CONVERTERS = {
        ["Starter (Grassy Grove)"] = Vector3.new(1271.6, -17.5, 459.3),
        ["Magic Meadow"]           = Vector3.new(1548.8, -14.5, 561.5),
        ["Haunted / Desert"]       = Vector3.new(1876.0, 11.9, 401.2),
        ["Desert Far"]             = Vector3.new(2029.7, 25.0, 143.4),
        ["Jungle"]                 = Vector3.new(1957.7, 34.1, 464.8),
        ["Stoney Sanctum"]         = Vector3.new(2174.1, 79.6, 546.5),
        ["Ember Expanse"]          = Vector3.new(2121.5, 87.5, 1093.5),
        ["Swarm City"]             = Vector3.new(1282.1, 156.7, 936.5),
    }

    local CHESTS = {
        ["Basic Chest"]         = Vector3.new(1381.1, 1.1, 374.6),
        ["Group Rewards"]       = Vector3.new(1447.7, -13.7, 398.8),
        ["Magic Chest"]         = Vector3.new(1630.4, -8.3, 612.4),
        ["Jungle Chest"]        = Vector3.new(1799.6, 22.7, 586.0),
        ["Frozen Chest"]        = Vector3.new(1729.3, 97.9, 1099.8),
        ["Cobblestone Chest"]   = Vector3.new(2295.1, 58.9, 580.3),
    }

    local LANDMARKS = {
        ["Spawn Location"]         = Vector3.new(1239.1, -21.0, 488.6),
        ["Matilda's Market (Shop)"] = Vector3.new(1295.7, 9.2, 627.9),
        ["Porky's Pawnshop (Shop)"] = Vector3.new(2183.7, 46.0, 104.1),
        ["Grassy Grove Mastery"]   = Vector3.new(1443.0, -11.0, 540.7),
        ["Magic Meadow Mastery"]   = Vector3.new(1660.1, 3.0, 457.6),
        ["Jade Jungle Mastery"]    = Vector3.new(1851.6, 9.4, 604.3),
        ["Haunted Hills Mastery"]  = Vector3.new(1697.3, 14.9, 209.4),
        ["Dusty Desert Mastery"]   = Vector3.new(1975.6, 27.4, 386.5),
        ["Stoney Sanctum Mastery"] = Vector3.new(2108.1, 60.4, 583.2),
        ["Polar Pinnacle Mastery"] = Vector3.new(1833.4, 91.3, 1070.5),
        ["Ember Expanse Mastery"]  = Vector3.new(2153.3, 91.0, 886.1),
        ["Swarm City Mastery"]     = Vector3.new(1295.5, 138.3, 1081.9),
    }

    local FISHING_SPOTS = {
        ["Starter Pond"]           = Vector3.new(1315.8, -31.7, 543.6),
        ["Star Pond"]              = Vector3.new(1666.9, -19.4, 589.1),
        ["Haunted Pond"]           = Vector3.new(1748.4, -0.1, 133.3),
        ["Polar Pond 1"]           = Vector3.new(1729.4, 93.5, 867.8),
        ["Polar Pond 2"]           = Vector3.new(1875.6, 78.7, 1031.5),
        ["Cave Pond 1"]            = Vector3.new(1287.5, 127.2, 989.1),
        ["Cave Pond 2"]            = Vector3.new(2091.0, 78.3, 1045.0),
        ["Cave Pond 3"]            = Vector3.new(2269.9, 48.6, 516.6),
        ["Desert Pond"]            = Vector3.new(1929.2, 16.9, 271.0),
        ["Jungle / Haunted Pond"]  = Vector3.new(1908.4, 13.6, 724.3),
    }

    -- ═══════════ Settings ═══════════
    local settings = {
        autoFarm = false,
        selectedField = "Dandylion Field",
        forceEquipShovel = true,
        movementMode = "Lawn Mower",
        roamRadius = 18,
        roamSpeed = 1.6,
        fieldMargin = 0.85,
        infiniteStamina = true,
        autoCollectOrbs = true,
        autoConvert = true,
        farmDelay = 0.22,
        autoWinFishing = true,
        autoFish = false,
        unlockFishPass = true,
        walkSpeed = 16,
        autoSpeed = false,
        infiniteJump = false,
        fullbright = false,
        fieldEsp = false,
        chestEsp = false,
        playerEsp = false,
    }

    -- ═══════════ Thread Helpers ═══════════
    local function startThread(name, fn)
        threads[name] = true
        task.spawn(function()
            local ok, err = pcall(fn, function() return running and threads[name] == true end)
            if not ok and running then
                warn("[RAVEN HUB / Beeconomy] thread error (" .. name .. "): " .. tostring(err))
            end
        end)
    end

    local function stopThread(name)
        threads[name] = nil
    end

    -- ═══════════ Utility Functions ═══════════
    local function getCharacter()
        return Player.Character
    end

    local function getRoot()
        local c = getCharacter()
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid()
        local c = getCharacter()
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function tpTo(pos)
        local root = getRoot()
        if not root then return false end
        if typeof(pos) == "CFrame" then
            root.CFrame = pos
        else
            root.CFrame = CFrame.new(pos)
        end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        return true
    end

    local function notify(title, content)
        pcall(function()
            Window:Notify({
                Title = title,
                Content = content,
                Duration = 4,
            })
        end)
    end

    -- ═══════════ Field Bounds Discovery ═══════════
    local function getFieldData(fieldName)
        local stripped = (fieldName or ""):gsub("%s+", "")
        local fieldsFolder = workspace:FindFirstChild("World1") and workspace.World1:FindFirstChild("World") and workspace.World1.World:FindFirstChild("Fields")
        if fieldsFolder then
            local folder = fieldsFolder:FindFirstChild(stripped)
            if not folder then
                for _, c in ipairs(fieldsFolder:GetChildren()) do
                    if c.Name:lower() == stripped:lower() then
                        folder = c
                        break
                    end
                end
            end
            if folder then
                local base = folder:FindFirstChild("Base")
                if base and base:IsA("BasePart") then
                    local margin = settings.fieldMargin or 0.85
                    return {
                        cframe = base.CFrame,
                        position = base.Position,
                        size = base.Size,
                        halfW = math.max(6, (base.Size.X * 0.5) * margin),
                        halfL = math.max(6, (base.Size.Z * 0.5) * margin)
                    }
                end
            end
        end
        local fallbackPos = FIELDS[fieldName] or Vector3.new(1315.0, -24.1, 425.6)
        local margin = settings.fieldMargin or 0.85
        return {
            cframe = CFrame.new(fallbackPos),
            position = fallbackPos,
            size = Vector3.new(60, 0, 40),
            halfW = 30 * margin,
            halfL = 20 * margin
        }
    end

    local function ensureShovelEquipped()
        local char = getCharacter()
        if not char then return end
        local hum = getHumanoid()
        local tm = clientController and clientController.ToolsManager
        local st = clientController and clientController.ScooperTool
        local hud = clientController and clientController.HudVisibility
        local im = clientController and (clientController.InteractablesManager or clientController.MachineActivation)

        -- 1. Ensure convert prompt / hud lock is completely dismissed
        if im and im.pollenConvertorPromptVisible then
            pcall(function() im:hidePollenConvertorPrompt() end)
            im.pollenConvertorPromptVisible = false
        end
        if hud and hud.blocksWorldInteract and hud:blocksWorldInteract() then
            pcall(function() hud:show("pollenConvert") end)
            pcall(function() hud:revealGameplay() end)
        end
        if workspace.CurrentCamera and workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        end

        -- 2. Ensure Player attributes expected by ToolsManager
        if Player:GetAttribute("ShovelEquipped") ~= true then
            pcall(function() Player:SetAttribute("ShovelEquipped", true) end)
        end
        if Player:GetAttribute("GripHoldKind") ~= "shovel" then
            pcall(function() Player:SetAttribute("GripHoldKind", "shovel") end)
        end

        -- 3. Equip through ToolsManager
        if tm then
            if tm.isScooperInputEquipped and not tm:isScooperInputEquipped() then
                pcall(function() tm:equipTool() end)
                pcall(function() tm:setHeldKind("tool", true) end)
                if tm.selectHotbarGear then
                    pcall(function() tm:selectHotbarGear("tool", tm.confirmedGearId or "basic_shovel") end)
                end
            end
            tm.confirmedKind = "tool"
        end

        -- 4. Equip tool from Backpack fallback
        local tool = char:FindFirstChild("Scooper") or char:FindFirstChildWhichIsA("Tool")
        if not tool or tool.Name ~= "Scooper" then
            local bpScooper = Player.Backpack:FindFirstChild("Scooper")
            if bpScooper and hum then
                hum:EquipTool(bpScooper)
            end
            if tm and tm.equipTool then
                pcall(function() tm:equipTool() end)
            end
        end

        -- 5. Sync ScooperTool internal state
        if st then
            st.scooperEquippedCache = true
            st.stamina = 100
        end
    end

    -- ═══════════ Active Orbs Access ═══════════
    local function getActiveOrbsTable()
        if clientController and clientController.PollenOrbs and clientController.PollenOrbs.destroy then
            local u = getupvalues(clientController.PollenOrbs.destroy)
            if u and u[2] and type(u[2]) == "table" then
                return u[2]
            end
        end
        return nil
    end

    -- ═══════════ Honey Conversion Logic ═══════════
    local function getNearestConverter(pos)
        local nearestPos = CONVERTERS["Starter (Grassy Grove)"]
        local shortestDist = math.huge
        for _, cPos in pairs(CONVERTERS) do
            local dist = (pos - cPos).Magnitude
            if dist < shortestDist then
                shortestDist = dist
                nearestPos = cPos
            end
        end
        return nearestPos
    end

    local isConverting = false
    local function doConvertHoney()
        if not clientController then findControllers() end
        local pd = clientController and clientController.PlayerData
        local im = clientController and (clientController.InteractablesManager or clientController.MachineActivation)
        local hud = clientController and clientController.HudVisibility
        local tm = clientController and clientController.ToolsManager
        local root = getRoot()

        if not root or not pd or (pd.pollen or 0) <= 0 then
            notify("Convert Honey", "No pollen in backpack to convert!")
            return false
        end

        local savedPos = root.Position
        local targetConverter = getNearestConverter(savedPos)

        notify("Auto Convert", "Teleporting to Converter machine...")
        tpTo(targetConverter + Vector3.new(0, 3, 0))
        task.wait(0.3)

        if im then
            im.pollenConvertorPromptVisible = true
            pcall(function()
                im:activatePollenConvertorPrompt()
            end)
        end
        if clientController and clientController.Network then
            pcall(function()
                clientController.Network:send("ConvertPollenAtMachine")
            end)
        end

        local startWait = tick()
        while tick() - startWait < 4.5 do
            if (pd.pollen or 0) == 0 then break end
            task.wait(0.2)
        end
        task.wait(0.3)

        -- Clean up convert cinematic & machine prompt
        if im then
            pcall(function() im:hidePollenConvertorPrompt() end)
            im.pollenConvertorPromptVisible = false
        end
        if hud then
            pcall(function() hud:show("pollenConvert") end)
            pcall(function() hud:revealGameplay() end)
        end
        if workspace.CurrentCamera and workspace.CurrentCamera.CameraType ~= Enum.CameraType.Custom then
            workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
        end

        notify("Auto Convert", "Conversion complete! Returning to farm field.")
        if savedPos and running then
            tpTo(savedPos)
            task.wait(0.2)
        end

        -- Immediately re-equip shovel and restore ToolsManager state
        ensureShovelEquipped()
        if tm and tm.equipTool then
            pcall(function() tm:equipTool() end)
            pcall(function() tm:setHeldKind("tool", true) end)
        end

        return true
    end

    -- ═══════════ Infinite Stamina Hook ═══════════
    local origCanScoop = nil
    local function applyInfiniteStamina(enabled)
        if not clientController then findControllers() end
        local st = clientController and clientController.ScooperTool
        if not st then return end

        if enabled then
            if not origCanScoop and type(st.canScoop) == "function" then
                origCanScoop = st.canScoop
            end
            st.canScoop = function() return true end
            st.stamina = 100
        else
            if origCanScoop then
                st.canScoop = origCanScoop
                origCanScoop = nil
            end
        end
    end

    -- ═══════════ Fishing Hook & Auto Win ═══════════
    local origReelStart = nil
    local function applyFishingHooks(enabled)
        if not reelMinigameObj then findControllers() end
        if not reelMinigameObj then return end

        if enabled then
            if not origReelStart and type(reelMinigameObj.Start) == "function" then
                origReelStart = reelMinigameObj.Start
                reelMinigameObj.Start = function(self, ...)
                    local res = origReelStart(self, ...)
                    if settings.autoWinFishing then
                        task.delay(0.18, function()
                            if not self.isFinished then
                                self.qualityScore = 1
                                self.currentProgress = 1
                                pcall(function()
                                    self:_finishGame(true)
                                end)
                            end
                        end)
                    end
                    return res
                end
            end
        else
            if origReelStart then
                reelMinigameObj.Start = origReelStart
                origReelStart = nil
            end
        end
    end

    local function applyAutoFishPerk(enabled)
        if not clientController then findControllers() end
        local pd = clientController and clientController.PlayerData
        if pd then
            if not pd.gamepassBenefits then
                pd.gamepassBenefits = {}
            end
            pd.gamepassBenefits.autoFish = enabled
        end
    end

    -- ═══════════ Fullbright & Character Mods ═══════════
    local origBrightness = Lighting.Brightness
    local origClockTime = Lighting.ClockTime
    local origFogEnd = Lighting.FogEnd
    local origGlobalShadows = Lighting.GlobalShadows
    local origAmbient = Lighting.Ambient
    local origOutdoorAmbient = Lighting.OutdoorAmbient

    local function applyFullbright(enabled)
        if enabled then
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            Lighting.Ambient = Color3.fromRGB(255, 255, 255)
            Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        else
            Lighting.Brightness = origBrightness
            Lighting.ClockTime = origClockTime
            Lighting.FogEnd = origFogEnd
            Lighting.GlobalShadows = origGlobalShadows
            Lighting.Ambient = origAmbient
            Lighting.OutdoorAmbient = origOutdoorAmbient
        end
    end

    local jumpConn = nil
    local function applyInfiniteJump(enabled)
        if jumpConn then
            jumpConn:Disconnect()
            jumpConn = nil
        end
        if enabled then
            jumpConn = UserInputService.JumpRequest:Connect(function()
                local hum = getHumanoid()
                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
            table.insert(connections, jumpConn)
        end
    end

    -- ═══════════ ESP Subsystem ═══════════
    local espFolder = Instance.new("Folder")
    espFolder.Name = "Beeconomy_ESP"
    espFolder.Parent = workspace

    local function clearEsp(prefix)
        for _, child in ipairs(espFolder:GetChildren()) do
            if not prefix or child.Name:sub(1, #prefix) == prefix then
                child:Destroy()
            end
        end
    end

    local function createEspLabel(name, position, color, prefix)
        local part = Instance.new("Part")
        part.Name = (prefix or "ESP_") .. name
        part.Size = Vector3.new(1, 1, 1)
        part.Position = position
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 1
        part.Parent = espFolder

        local bb = Instance.new("BillboardGui")
        bb.Name = "Label"
        bb.Adornee = part
        bb.Size = UDim2.new(0, 140, 0, 40)
        bb.StudsOffset = Vector3.new(0, 2, 0)
        bb.AlwaysOnTop = true
        bb.Parent = part

        local text = Instance.new("TextLabel")
        text.Size = UDim2.new(1, 0, 1, 0)
        text.BackgroundTransparency = 1
        text.Text = name
        text.TextColor3 = color or Color3.fromRGB(255, 255, 255)
        text.TextStrokeTransparency = 0.2
        text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        text.TextScaled = true
        text.Font = Enum.Font.GothamBold
        text.Parent = bb

        return part, text
    end

    -- ═══════════ Tab 1: Farming (Main) ═══════════
    local FarmTab = Window:CreateTab("Farming", "farm")
    FarmTab:CreateSection("Auto Harvest & Scoop")

    FarmTab:CreateToggle({
        Name = "Auto Farm Pollen",
        CurrentValue = false,
        Flag = "BeeAutoFarm",
        Callback = function(v)
            settings.autoFarm = v
            if v then
                local lastRandomTarget = nil
                local lastRandomTime = 0
                startThread("autoFarm", function(isActive)
                    while isActive() do
                        if not isConverting then
                            local pd = clientController and clientController.PlayerData
                            local st = clientController and clientController.ScooperTool
                            local root = getRoot()

                            -- 1. Force Equip Shovel
                            if settings.forceEquipShovel then
                                ensureShovelEquipped()
                            end

                            -- 2. Auto Convert if bag full
                            local currentPollen = pd and pd.pollen or 0
                            local maxP = pd and pd:getMaxPollen() or 1000
                            if settings.autoConvert and currentPollen >= (maxP * 0.95) and currentPollen > 0 then
                                isConverting = true
                                doConvertHoney()
                                isConverting = false
                            else
                                -- 3. Autonomous Whole-Field Movement
                                local fData = getFieldData(settings.selectedField)
                                if fData and root then
                                    local distFromCenter = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(fData.position.X, 0, fData.position.Z)).Magnitude
                                    local maxDim = math.max(fData.halfW, fData.halfL) + 35
                                    if distFromCenter > maxDim then
                                        tpTo(fData.position + Vector3.new(0, 3, 0))
                                        task.wait(0.2)
                                    end

                                    local mode = settings.movementMode
                                    local hum = getHumanoid()
                                    local speed = settings.roamSpeed or 1.6

                                    if mode == "Lawn Mower" then
                                        -- Systematic snake / boustrophedon sweep across the entire field
                                        local periodX = math.max(2.5, 5.0 / speed)
                                        local numLanes = 5
                                        local t = tick()
                                        local progressX = (t % periodX) / periodX
                                        local dirX = math.floor(t / periodX) % 2
                                        local normX = dirX == 0 and (-1 + progressX * 2) or (1 - progressX * 2)

                                        local laneT = (t % (periodX * numLanes)) / (periodX * numLanes)
                                        local laneDir = math.floor(t / (periodX * numLanes)) % 2
                                        local normZ = -1 + laneT * 2
                                        if laneDir == 1 then normZ = -normZ end

                                        local localPos = Vector3.new(normX * fData.halfW, 0, normZ * fData.halfL)
                                        local targetPos = fData.cframe:PointToWorldSpace(localPos)
                                        if hum then hum:MoveTo(targetPos) end

                                    elseif mode == "Smooth Sweep" then
                                        -- Continuous Lissajous wave covering all quadrants smoothly
                                        local t = tick() * speed
                                        local localPos = Vector3.new(
                                            math.sin(t * 0.7) * fData.halfW,
                                            0,
                                            math.sin(t * 0.23 + 1.0) * fData.halfL
                                        )
                                        local targetPos = fData.cframe:PointToWorldSpace(localPos)
                                        if hum then hum:MoveTo(targetPos) end

                                    elseif mode == "Circle Walk" then
                                        local angle = (tick() * speed) % (2 * math.pi)
                                        local r = math.min(settings.roamRadius, math.min(fData.halfW, fData.halfL))
                                        local localPos = Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
                                        local targetPos = fData.cframe:PointToWorldSpace(localPos)
                                        if hum then hum:MoveTo(targetPos) end

                                    elseif mode == "Glide Roam" then
                                        local t = tick() * speed
                                        local localPos = Vector3.new(
                                            math.sin(t * 0.6) * fData.halfW,
                                            1,
                                            math.sin(t * 0.25 + 0.8) * fData.halfL
                                        )
                                        local targetPos = fData.cframe:PointToWorldSpace(localPos)
                                        root.CFrame = CFrame.new(targetPos, fData.position)

                                    elseif mode == "Random Bounce" then
                                        if not lastRandomTarget or (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(lastRandomTarget.X, 0, lastRandomTarget.Z)).Magnitude < 4 or (tick() - (lastRandomTime or 0)) > 4 then
                                            local rx = (math.random() * 2 - 1) * fData.halfW
                                            local rz = (math.random() * 2 - 1) * fData.halfL
                                            lastRandomTarget = fData.cframe:PointToWorldSpace(Vector3.new(rx, 0, rz))
                                            lastRandomTime = tick()
                                        end
                                        if hum and lastRandomTarget then hum:MoveTo(lastRandomTarget) end
                                    end
                                end

                                -- 4. Dig / Scoop Flowers
                                if st then
                                    st.stamina = 100
                                    pcall(function()
                                        st:onScoopInput()
                                    end)
                                end
                            end
                        end
                        task.wait(settings.farmDelay)
                    end
                end)
            else
                stopThread("autoFarm")
                local hum = getHumanoid()
                local root = getRoot()
                if hum and root then
                    hum:MoveTo(root.Position)
                end
            end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Farm Field",
        Options = FIELD_NAMES,
        CurrentOption = "Dandylion Field",
        Flag = "BeeFarmField",
        Callback = function(option)
            local chosen = type(option) == "table" and option[1] or option
            if FIELDS[chosen] then
                settings.selectedField = chosen
            end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Movement Mode",
        Options = {"Lawn Mower", "Smooth Sweep", "Circle Walk", "Glide Roam", "Random Bounce", "Stay Center"},
        CurrentOption = "Lawn Mower",
        Flag = "BeeMoveMode",
        Callback = function(opt)
            local chosen = type(opt) == "table" and opt[1] or opt
            settings.movementMode = chosen
            if chosen == "Stay Center" then
                local hum = getHumanoid()
                local root = getRoot()
                if hum and root then hum:MoveTo(root.Position) end
            end
        end,
    })

    FarmTab:CreateSlider({
        Name = "Roam Speed",
        Range = {0.5, 3.5},
        Increment = 0.1,
        CurrentValue = 1.6,
        Suffix = "x",
        Flag = "BeeRoamSpeed",
        Callback = function(v)
            settings.roamSpeed = v
        end,
    })

    FarmTab:CreateSlider({
        Name = "Field Margin",
        Range = {50, 95},
        Increment = 5,
        CurrentValue = 85,
        Suffix = "%",
        Flag = "BeeFieldMargin",
        Callback = function(v)
            settings.fieldMargin = v / 100
        end,
    })

    FarmTab:CreateSlider({
        Name = "Circle Radius (For Circle Walk)",
        Range = {8, 35},
        Increment = 1,
        CurrentValue = 18,
        Suffix = " studs",
        Flag = "BeeRoamRadius",
        Callback = function(v)
            settings.roamRadius = v
        end,
    })

    FarmTab:CreateToggle({
        Name = "Force Equip Shovel",
        CurrentValue = true,
        Flag = "BeeForceShovel",
        Callback = function(v)
            settings.forceEquipShovel = v
            if v then ensureShovelEquipped() end
        end,
    })

    FarmTab:CreateToggle({
        Name = "Infinite Scoop Stamina",
        CurrentValue = true,
        Flag = "BeeInfStamina",
        Callback = function(v)
            settings.infiniteStamina = v
            applyInfiniteStamina(v)
        end,
    })
    applyInfiniteStamina(true)

    FarmTab:CreateSlider({
        Name = "Farm Delay",
        Range = {0.15, 0.6},
        Increment = 0.02,
        CurrentValue = 0.22,
        Suffix = " s",
        Flag = "BeeFarmDelay",
        Callback = function(v)
            settings.farmDelay = v
        end,
    })

    FarmTab:CreateSection("Orbs Magnet")

    FarmTab:CreateToggle({
        Name = "Auto Collect Pollen Orbs",
        CurrentValue = true,
        Flag = "BeeAutoCollectOrbs",
        Callback = function(v)
            settings.autoCollectOrbs = v
            if v then
                startThread("autoOrbs", function(isActive)
                    while isActive() do
                        local orbs = getActiveOrbsTable()
                        if orbs then
                            for _, orb in pairs(orbs) do
                                if not orb.collected then
                                    orb.pickupDistance = 1000
                                    orb.pickupDelay = 0
                                end
                            end
                        end
                        task.wait(0.12)
                    end
                end)
            else
                stopThread("autoOrbs")
            end
        end,
    })
    -- Start auto collect orbs thread immediately since default is true
    startThread("autoOrbs", function(isActive)
        while isActive() do
            if settings.autoCollectOrbs then
                local orbs = getActiveOrbsTable()
                if orbs then
                    for _, orb in pairs(orbs) do
                        if not orb.collected then
                            orb.pickupDistance = 1000
                            orb.pickupDelay = 0
                        end
                    end
                end
            end
            task.wait(0.12)
        end
    end)

    FarmTab:CreateSection("Honey Conversion")

    FarmTab:CreateToggle({
        Name = "Auto Convert at 95% Full",
        CurrentValue = true,
        Flag = "BeeAutoConvert",
        Callback = function(v)
            settings.autoConvert = v
        end,
    })

    FarmTab:CreateButton({
        Name = "Convert to Honey Now",
        Callback = function()
            task.spawn(doConvertHoney)
        end,
    })

    -- ═══════════ Tab 2: Fishing ═══════════
    local FishTab = Window:CreateTab("Fishing", "loot")
    FishTab:CreateSection("Minigame Automation")

    FishTab:CreateToggle({
        Name = "Auto Win Reel Minigame (Perfect Catch)",
        CurrentValue = true,
        Flag = "BeeAutoWinFish",
        Callback = function(v)
            settings.autoWinFishing = v
            applyFishingHooks(v)
        end,
    })
    applyFishingHooks(true)

    FishTab:CreateToggle({
        Name = "Unlock Auto-Fish Gamepass Perk",
        CurrentValue = true,
        Flag = "BeeAutoFishPerk",
        Callback = function(v)
            settings.unlockFishPass = v
            applyAutoFishPerk(v)
        end,
    })
    applyAutoFishPerk(true)

    FishTab:CreateSection("Auto Cast Fishing Loop")

    FishTab:CreateToggle({
        Name = "Auto Fish (Auto Cast & Reel)",
        CurrentValue = false,
        Flag = "BeeAutoFishLoop",
        Callback = function(v)
            settings.autoFish = v
            if v then
                applyAutoFishPerk(true)
                startThread("autoFishLoop", function(isActive)
                    while isActive() do
                        local char = getCharacter()
                        -- Ensure fishing rod is equipped
                        if char and not char:FindFirstChildWhichIsA("Tool") and Player.Backpack:FindFirstChildWhichIsA("Tool") then
                            for _, tool in ipairs(Player.Backpack:GetChildren()) do
                                if tool.Name:lower():find("rod") or tool.Name:lower():find("fishing") then
                                    local hum = getHumanoid()
                                    if hum then hum:EquipTool(tool) end
                                    break
                                end
                            end
                        end

                        -- Trigger cast prompt if nearby water
                        local prompt = workspace:FindFirstChild("World1")
                            and workspace.World1:FindFirstChild("Water")
                            and workspace.World1.Water:FindFirstChild("FishingPromptAnchor")
                        if prompt then
                            local root = getRoot()
                            if root and (root.Position - prompt.Position).Magnitude <= 20 then
                                for _, desc in ipairs(prompt:GetDescendants()) do
                                    if desc:IsA("ProximityPrompt") and desc.Enabled then
                                        pcall(function()
                                            fireproximityprompt(desc)
                                        end)
                                    end
                                end
                            end
                        end
                        task.wait(1.5)
                    end
                end)
            else
                stopThread("autoFishLoop")
            end
        end,
    })

    FishTab:CreateSection("Teleport to Fishing Spots")
    for pondName, pondPos in pairs(FISHING_SPOTS) do
        FishTab:CreateButton({
            Name = "Go to " .. pondName,
            Callback = function()
                tpTo(pondPos + Vector3.new(0, 3, 0))
            end,
        })
    end

    -- ═══════════ Tab 3: Teleports ═══════════
    local TpTab = Window:CreateTab("Teleports", "movement")

    TpTab:CreateSection("Fields (23 Areas)")
    local selectedTpField = "Dandylion Field"
    TpTab:CreateDropdown({
        Name = "Select Field",
        Options = FIELD_NAMES,
        CurrentOption = "Dandylion Field",
        Flag = "BeeTpFieldChoice",
        Callback = function(opt)
            selectedTpField = type(opt) == "table" and opt[1] or opt
        end,
    })

    TpTab:CreateButton({
        Name = "Teleport to Selected Field",
        Callback = function()
            local pos = FIELDS[selectedTpField]
            if pos then
                tpTo(pos + Vector3.new(0, 3, 0))
            end
        end,
    })

    TpTab:CreateSection("Pollen Converters")
    for name, pos in pairs(CONVERTERS) do
        TpTab:CreateButton({
            Name = name .. " Machine",
            Callback = function()
                tpTo(pos + Vector3.new(0, 3, 0))
            end,
        })
    end

    TpTab:CreateSection("Shops & Spawns")
    for name, pos in pairs(LANDMARKS) do
        TpTab:CreateButton({
            Name = name,
            Callback = function()
                tpTo(pos + Vector3.new(0, 3, 0))
            end,
        })
    end

    TpTab:CreateSection("Chests")
    for name, pos in pairs(CHESTS) do
        TpTab:CreateButton({
            Name = name,
            Callback = function()
                tpTo(pos + Vector3.new(0, 3, 0))
            end,
        })
    end

    -- ═══════════ Tab 4: Movement & World ═══════════
    local MoveTab = Window:CreateTab("Movement", "player")
    MoveTab:CreateSection("Player Speed")

    MoveTab:CreateToggle({
        Name = "Custom WalkSpeed",
        CurrentValue = false,
        Flag = "BeeCustomSpeed",
        Callback = function(v)
            settings.autoSpeed = v
            if v then
                startThread("walkSpeed", function(isActive)
                    while isActive() do
                        local hum = getHumanoid()
                        if hum then hum.WalkSpeed = settings.walkSpeed end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("walkSpeed")
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = 16 end
            end
        end,
    })

    MoveTab:CreateSlider({
        Name = "WalkSpeed Value",
        Range = {16, 120},
        Increment = 2,
        CurrentValue = 16,
        Suffix = " spd",
        Flag = "BeeSpeedVal",
        Callback = function(v)
            settings.walkSpeed = v
            local hum = getHumanoid()
            if hum and settings.autoSpeed then hum.WalkSpeed = v end
        end,
    })

    MoveTab:CreateSection("Mobility & Lighting")

    MoveTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = false,
        Flag = "BeeInfJump",
        Callback = function(v)
            settings.infiniteJump = v
            applyInfiniteJump(v)
        end,
    })

    MoveTab:CreateToggle({
        Name = "Fullbright (No Shadows / Clear View)",
        CurrentValue = false,
        Flag = "BeeFullbright",
        Callback = function(v)
            settings.fullbright = v
            applyFullbright(v)
        end,
    })

    -- ═══════════ Tab 5: Visuals / ESP ═══════════
    local VisualTab = Window:CreateTab("Visuals", "visual")
    VisualTab:CreateSection("World & Object ESP")

    VisualTab:CreateToggle({
        Name = "Field ESP",
        CurrentValue = false,
        Flag = "BeeFieldEsp",
        Callback = function(v)
            settings.fieldEsp = v
            clearEsp("FIELD_")
            if v then
                for name, pos in pairs(FIELDS) do
                    createEspLabel(name, pos + Vector3.new(0, 10, 0), Color3.fromRGB(255, 220, 60), "FIELD_")
                end
            end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Chest ESP",
        CurrentValue = false,
        Flag = "BeeChestEsp",
        Callback = function(v)
            settings.chestEsp = v
            clearEsp("CHEST_")
            if v then
                for name, pos in pairs(CHESTS) do
                    createEspLabel(name, pos + Vector3.new(0, 4, 0), Color3.fromRGB(60, 200, 255), "CHEST_")
                end
            end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = false,
        Flag = "BeePlayerEsp",
        Callback = function(v)
            settings.playerEsp = v
            clearEsp("PLAYER_")
            if v then
                startThread("playerEsp", function(isActive)
                    while isActive() do
                        clearEsp("PLAYER_")
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p ~= Player and p.Character then
                                local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                                if hrp then
                                    local dist = math.floor((hrp.Position - (getRoot() and getRoot().Position or hrp.Position)).Magnitude)
                                    createEspLabel(p.DisplayName .. " [" .. dist .. "m]", hrp.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 100, 100), "PLAYER_")
                                end
                            end
                        end
                        task.wait(1.5)
                    end
                end)
            else
                stopThread("playerEsp")
                clearEsp("PLAYER_")
            end
        end,
    })

    -- ═══════════ Tab 6: Info & Utilities ═══════════
    local InfoTab = Window:CreateTab("Overview", "overview")
    InfoTab:CreateSection("Game Info")
    InfoTab:CreateLabel("Experience: [🔥UPDATE 1] Beeconomy!")
    InfoTab:CreateLabel("Module Version: v1.0.0")
    InfoTab:CreateLabel("Author: valrinx | RAVEN HUB")

    InfoTab:CreateSection("Server Actions")
    InfoTab:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            TeleportService:Teleport(game.PlaceId, Player)
        end,
    })

    InfoTab:CreateButton({
        Name = "Server Hop",
        Callback = function()
            pcall(function()
                local tps = HttpService:JSONDecode(
                    game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=10")
                )
                if tps and tps.data then
                    for _, srv in ipairs(tps.data) do
                        if srv.id ~= game.JobId and srv.playing < srv.maxPlayers then
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, srv.id, Player)
                            break
                        end
                    end
                end
            end)
        end,
    })

    -- ═══════════ Cleanup Handler ═══════════
    local function destroy()
        running = false
        for key in pairs(threads) do threads[key] = nil end
        for _, conn in ipairs(connections) do
            if conn and typeof(conn) == "RBXScriptConnection" then
                pcall(function() conn:Disconnect() end)
            end
        end
        applyInfiniteStamina(false)
        applyFishingHooks(false)
        applyFullbright(false)
        applyInfiniteJump(false)
        if espFolder then pcall(function() espFolder:Destroy() end) end
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end

    notify("Beeconomy!", "v1.0.0 Loaded successfully! Enjoy farming.")
end
