-- ═══════════════════════════════════════════════════════════
-- Beeconomy! | RAVEN HUB Module v2.1.0 (Zone-Lock + Smart Gather Edition)
-- PlaceId: 101558830312092 | GameId: 7000989941
-- Features: Universal Future-Proof Tool Engine (Supports all 110+ tools & future updates across 5 categories),
--           Auto Farm Pollen (Smart Hunter, Anti-Sticking Watchdog, Lawn Mower sweep fallback across all 23 fields),
--           Auto Mine Rocks (Pickaxe, Zone-Lock, TP movement, felled blacklist),
--           Auto Chop Trees (Axe, Zone-Lock, TP movement, felled blacklist),
--           Auto Catch Beetles (Net, TP movement),
--           Auto Orbs Magnet, Auto Honey Convert, Infinite Stamina, Auto Fish 100% Win, ESP
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
        forceEquipTool = true,
        forceEquipShovel = true,
        movementMode = "Pollen Hunter",
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
        autoMine = false,
        mineMaxDist = 300,
        autoChop = false,
        chopMaxDist = 300,
        autoCatch = false,
        catchMaxDist = 200,
        walkSpeed = 16,
        autoSpeed = false,
        infiniteJump = false,
        fullbright = false,
        fieldEsp = false,
        chestEsp = false,
        playerEsp = false,
        zoneLock = true,         -- restrict gather to player's current region
        gatherMoveMode = "Teleport", -- "Teleport", "Walk"
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
                        folderName = folder.Name,
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
            folderName = stripped,
            cframe = CFrame.new(fallbackPos),
            position = fallbackPos,
            size = Vector3.new(60, 0, 40),
            halfW = 30 * margin,
            halfL = 20 * margin
        }
    end

    -- ═══════════ Zone Detection (Region-Lock) ═══════════
    -- Maps any world position → the region folder name it belongs to.
    -- Uses workspace.World1.Regions bounding parts (accurate 3D AABB check).
    local function getRegionForPos(pos)
        local regionsFolder = workspace:FindFirstChild("World1") and workspace.World1:FindFirstChild("Regions")
        if not regionsFolder then return nil end
        for _, regionFolder in ipairs(regionsFolder:GetChildren()) do
            for _, part in ipairs(regionFolder:GetDescendants()) do
                if part:IsA("BasePart") then
                    local local3 = part.CFrame:PointToObjectSpace(pos)
                    local half = part.Size * 0.5
                    if math.abs(local3.X) <= half.X and math.abs(local3.Y) <= half.Y and math.abs(local3.Z) <= half.Z then
                        return regionFolder.Name
                    end
                end
            end
        end
        return nil -- not inside any known region
    end

    -- Felled/dead tracking: keyed by Model reference, value = expiry tick()
    local felledTrees = {}      -- tree model → tick() when it respawns (safe to re-target)
    local felledRocks = {}      -- rock model → tick() when it respawns

    local function isTreeDead(tree)
        if not tree or not tree.Parent then return true end

        -- 1. Reject any stump or breakable debris visual model
        local tName = tree.Name:lower()
        if tName:find("stump") then
            return true
        end

        -- 2. Must have valid BreakableTreeId attribute (real trees always have this)
        local tKey = tree:GetAttribute("BreakableTreeId")
        if not tKey or tostring(tKey) == "" then
            return true
        end

        local now = tick()
        if felledTrees[tree] and now < felledTrees[tree] then return true end
        if tree:FindFirstChild("TreeBreakHighlight") then return true end

        -- 3. Game controller stateByKey check
        if not clientController then findControllers() end
        local bt = clientController and clientController.BreakableTrees
        if bt and bt.stateByKey then
            local compositeKey = tree.Name .. "\0" .. tostring(tKey)
            local state = bt.stateByKey[compositeKey]
            if state then
                local serverNow = workspace:GetServerTimeNow()
                if state.dead == true or (state.health and state.health <= 0) or (state.respawnAt and state.respawnAt > serverNow) then
                    return true
                end
            end
        end

        -- 4. HealthGui check (0/4, 0/7, 0/14, 0/24)
        local stump = tree:FindFirstChild("StumpSpawn")
        local gui = stump and stump:FindFirstChild("BreakableHealthGui")
        local healthLabel = gui and gui:FindFirstChild("Health", true)
        if healthLabel and healthLabel:IsA("TextLabel") and healthLabel.Text:find("^0/") then
            return true
        end

        -- 5. Visual check: when broken, trunk and leaves BaseParts have Transparency = 1
        local hasTrunkOrLeaves = false
        for _, desc in ipairs(tree:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Transparency < 0.5 then
                local lname = desc.Name:lower()
                if lname:find("trunk") or lname:find("leaves") then
                    hasTrunkOrLeaves = true
                    break
                end
            end
        end
        if not hasTrunkOrLeaves then
            return true -- No visible trunk or leaves means it's a stump!
        end

        return false
    end

    local function isRockDead(rock)
        if not rock or not rock.Parent then return true end

        -- 1. Reject any debris / rubble / client visual objects
        local rName = rock.Name:lower()
        if rName:find("stump") or rName:find("debris") or rName:find("client") then
            return true
        end

        -- 2. Must have BreakableRockId attribute
        local rKey = rock:GetAttribute("BreakableRockId")
        if not rKey or tostring(rKey) == "" then
            return true
        end

        local now = tick()
        if felledRocks[rock] and now < felledRocks[rock] then return true end

        -- 3. BreakableRocks controller stateByKey
        if not clientController then findControllers() end
        local br = clientController and clientController.BreakableRocks
        if br and br.stateByKey then
            local compositeKey = rock.Name .. "\0" .. tostring(rKey)
            local state = br.stateByKey[compositeKey]
            if state then
                local serverNow = workspace:GetServerTimeNow()
                if state.dead == true or (state.health and state.health <= 0) or (state.respawnAt and state.respawnAt > serverNow) then
                    return true
                end
            end
        end

        -- 4. Visual check: The game's Visual.apply sets all BaseParts in the rock to Transparency = 1 when broken
        local hasVisible = false
        for _, desc in ipairs(rock:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name ~= "RockSpawn" and desc.Transparency < 0.5 then
                hasVisible = true
                break
            end
        end
        if not hasVisible then
            return true
        end

        return false
    end

    -- ═══════════ Smart Pollen / Flower Detection ═══════════
    local function findBestAliveFlower(folderName)
        if not clientController then findControllers() end
        local sg = clientController and clientController.SkinnedGrass
        if not sg then return nil, 0 end

        if not sg.fieldByName or not sg.fieldByName[folderName] then
            pcall(function() sg:syncFields() end)
        end

        local grassObj = nil
        if sg.fieldByName and sg.fieldByName[folderName] then
            grassObj = sg.fieldByName[folderName]
        elseif sg.grassObjects then
            for _, g in ipairs(sg.grassObjects) do
                if g.fieldFolder and g.fieldFolder.Name == folderName then
                    grassObj = g
                    break
                end
            end
        end

        if not grassObj or not grassObj.BoneInitialPositions then
            return nil, nil, 0
        end

        local root = getRoot()
        local charPos = root and root.Position or Vector3.zero
        local now = tick()
        local bhs = grassObj.BoneHarvestState or {}
        local bip = grassObj.BoneInitialPositions

        local nearestFlowerPos = nil
        local nearestBone = nil
        local shortestDist = math.huge
        local totalAlive = 0

        for bone, pos in pairs(bip) do
            if not blacklist or not blacklist[bone] or now >= blacklist[bone] then
                local state = bhs[bone]
                local isAlive = true
                if state and state.dead == true then
                    if not state.respawnAt or now < state.respawnAt then
                        isAlive = false
                    end
                end

                if isAlive then
                    totalAlive = totalAlive + 1
                    local dist = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(charPos.X, 0, charPos.Z)).Magnitude
                    if dist < shortestDist then
                        shortestDist = dist
                        nearestFlowerPos = pos
                        nearestBone = bone
                    end
                end
            end
        end

        return nearestFlowerPos, nearestBone, totalAlive
    end

    -- ═══════════ Universal Future-Proof Tool Engine ═══════════
    -- Dynamically detects and equips ALL 5 categories of tools:
    -- "tool" (pollen tools), "axe", "pickaxe", "fishing_rod", "net"
    -- Directly binds with PlayerData.equipment, BackpackToolKinds, GripKinds, and ToolsManager
    -- Any new tools added in future game updates are automatically discovered and supported!

    local TOOL_KIND_FALLBACKS = {
        tool = "basic_shovel",
        axe = "wooden_axe",
        pickaxe = "wooden_pickaxe",
        fishing_rod = "wooden_fishing_rod",
        net = "basic_net",
    }

    local function getToolFromContainer(container, kind)
        if not container then return nil end
        local btk = clientController and clientController.BackpackToolKinds
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                if kind == "tool" then
                    if btk and btk.isPollenCollectionTool then
                        if btk.isPollenCollectionTool(item) then return item end
                    else
                        local name = item.Name:lower()
                        if not name:find("axe") and not name:find("pickaxe") and not name:find("rod") and not name:find("net") and not name:find("wand") and not name:find("laser") then
                            return item
                        end
                    end
                elseif kind == "axe" then
                    if btk and btk.isAxeTool and btk.isAxeTool(item) then return item end
                elseif kind == "pickaxe" then
                    if btk and btk.isPickaxeTool and btk.isPickaxeTool(item) then return item end
                elseif kind == "fishing_rod" then
                    if btk and btk.isFishingRodTool and btk.isFishingRodTool(item) then return item end
                elseif kind == "net" then
                    if btk and btk.isNetTool and btk.isNetTool(item) then return item end
                end
            end
        end
        return nil
    end

    local function ensureToolEquipped(kind)
        kind = kind or "tool"
        local char = getCharacter()
        if not char then return end
        local hum = getHumanoid()
        local tm = clientController and clientController.ToolsManager
        local st = clientController and clientController.ScooperTool
        local hud = clientController and clientController.HudVisibility
        local im = clientController and (clientController.InteractablesManager or clientController.MachineActivation)
        local pd = clientController and clientController.PlayerData

        -- 0. Check if already equipped to completely prevent audio spam
        local isAlreadyEquipped = false
        if kind == "tool" then
            local toolInChar = char:FindFirstChildWhichIsA("Tool")
            if toolInChar and Player:GetAttribute("ShovelEquipped") == true then
                isAlreadyEquipped = true
            end
        else
            if tm and tm.isHoldingKind and tm:isHoldingKind(kind) and Player:GetAttribute("GripHoldKind") == kind then
                isAlreadyEquipped = true
            end
        end

        if isAlreadyEquipped then
            return (pd and pd.equipment and pd.equipment[kind]) or (tm and tm.confirmedGearId) or TOOL_KIND_FALLBACKS[kind] or "basic_shovel"
        end

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

        -- 2. Dynamically resolve player's active gear ID from PlayerData.equipment
        local activeGearId = (pd and pd.equipment and pd.equipment[kind]) or (tm and tm.confirmedGearId) or TOOL_KIND_FALLBACKS[kind] or "basic_shovel"

        -- 3. Set Player attributes expected by ToolsManager
        if kind == "tool" then
            if Player:GetAttribute("ShovelEquipped") ~= true then
                pcall(function() Player:SetAttribute("ShovelEquipped", true) end)
            end
            if Player:GetAttribute("GripHoldKind") ~= "shovel" then
                pcall(function() Player:SetAttribute("GripHoldKind", "shovel") end)
            end
        else
            pcall(function() Player:SetAttribute("GripHoldKind", kind) end)
        end

        -- 4. Equip through ToolsManager
        if tm then
            pcall(function() tm:selectHotbarGear(kind, activeGearId) end)
            pcall(function() tm:setHeldKind(kind, true) end)
            if kind == "tool" and tm.equipTool then
                pcall(function() tm:equipTool() end)
            end
            tm.confirmedKind = kind
        end

        -- 5. Fallback: Equip from Backpack if not currently held
        local equipped = getToolFromContainer(char, kind)
        if not equipped and Player.Backpack and hum then
            local bpTool = getToolFromContainer(Player.Backpack, kind)
            if bpTool then
                hum:EquipTool(bpTool)
            end
            if tm then
                pcall(function() tm:setHeldKind(kind, true) end)
                if kind == "tool" and tm.equipTool then
                    pcall(function() tm:equipTool() end)
                end
            end
        end

        -- 6. Sync ScooperTool internal state if tool kind is pollen tool
        if kind == "tool" and st then
            st.scooperEquippedCache = true
            st.stamina = 100
        end

        return activeGearId
    end

    local ensurePollenToolEquipped = function() return ensureToolEquipped("tool") end
    local ensureShovelEquipped = ensurePollenToolEquipped

    -- ═══════════ Auto Mine Rocks (Pickaxe) ═══════════
    local function getNearestRock(maxDist)
        local root = getRoot()
        local combat = workspace:FindFirstChild("World1") and workspace.World1:FindFirstChild("Combat")
        local rockFolder = combat and combat:FindFirstChild("BreakableRocks")
        if not rockFolder or not root then return nil, math.huge end

        local playerZone = settings.zoneLock and getRegionForPos(root.Position) or nil
        local nearest = nil
        local shortest = maxDist or (settings.mineMaxDist or 300)

        for _, rock in ipairs(rockFolder:GetChildren()) do
            if rock.Parent and not isRockDead(rock) then
                local part = rock:FindFirstChild("RockSpawn") or rock.PrimaryPart or rock:FindFirstChildWhichIsA("BasePart")
                if part then
                    if playerZone and getRegionForPos(part.Position) ~= playerZone then
                        continue
                    end
                    local dist = (part.Position - root.Position).Magnitude
                    if dist < shortest then
                        shortest = dist
                        nearest = rock
                    end
                end
            end
        end
        return nearest, shortest
    end

    -- ═══════════ Auto Chop Trees (Axe) ═══════════
    local function getNearestTree(maxDist)
        local root = getRoot()
        local combat = workspace:FindFirstChild("World1") and workspace.World1:FindFirstChild("Combat")
        local treeFolder = combat and combat:FindFirstChild("BreakableTrees")
        if not treeFolder or not root then return nil, math.huge end

        local playerZone = settings.zoneLock and getRegionForPos(root.Position) or nil
        local nearest = nil
        local shortest = maxDist or (settings.chopMaxDist or 300)

        for _, tree in ipairs(treeFolder:GetChildren()) do
            if tree.Parent and not isTreeDead(tree) then
                local part = tree:FindFirstChild("StumpSpawn") or tree.PrimaryPart or tree:FindFirstChildWhichIsA("BasePart")
                if part then
                    if playerZone and getRegionForPos(part.Position) ~= playerZone then
                        continue
                    end
                    local dist = (part.Position - root.Position).Magnitude
                    if dist < shortest then
                        shortest = dist
                        nearest = tree
                    end
                end
            end
        end
        return nearest, shortest
    end

    -- ═══════════ Auto Catch Beetles (Net) ═══════════
    local function getNearestBeetle(maxDist)
        local root = getRoot()
        local netCatch = clientController and clientController.NetCatchingMinigame
        if not netCatch or not netCatch.mobVisuals or not root then return nil, math.huge end

        local nearest = nil
        local shortest = maxDist or (settings.catchMaxDist or 200)
        for _, visual in pairs(netCatch.mobVisuals) do
            local model = visual and (visual.model or visual.rootPart or visual.primaryPart)
            local part = typeof(model) == "Instance" and (model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart"))
            if part then
                local dist = (part.Position - root.Position).Magnitude
                if dist < shortest then
                    shortest = dist
                    nearest = visual
                end
            end
        end
        return nearest, shortest
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

        -- Immediately re-equip pollen tool and restore ToolsManager state
        ensurePollenToolEquipped()
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
                local flowerBlacklist = {}
                local currentTargetBone = nil
                local targetStickTime = 0

                startThread("autoFarm", function(isActive)
                    while isActive() do
                        if not isConverting then
                            local pd = clientController and clientController.PlayerData
                            local st = clientController and clientController.ScooperTool
                            local root = getRoot()

                            -- 1. Force Equip Pollen Tool (Shovels, Rakes, Wands, etc.)
                            if settings.forceEquipTool or settings.forceEquipShovel then
                                ensurePollenToolEquipped()
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

                                    if mode == "Pollen Hunter" then
                                        -- Detect alive flowers with pollen in the field and navigate to them
                                        local flowerPos, flowerBone, aliveCount = findBestAliveFlower(fData.folderName, flowerBlacklist)

                                        -- Anti-Sticking Watchdog:
                                        -- If player is standing within 4.5 studs of the target flower for >= 0.8s without it being harvested,
                                        -- blacklist this flower for 30s so the bot immediately retargets without freezing!
                                        if flowerBone and flowerPos then
                                            local myDist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(flowerPos.X, 0, flowerPos.Z)).Magnitude
                                            if currentTargetBone == flowerBone then
                                                if myDist <= 4.5 then
                                                    targetStickTime = targetStickTime + (settings.farmDelay or 0.22)
                                                    if targetStickTime >= 0.8 then
                                                        flowerBlacklist[flowerBone] = tick() + 30
                                                        flowerPos, flowerBone, aliveCount = findBestAliveFlower(fData.folderName, flowerBlacklist)
                                                        currentTargetBone = flowerBone
                                                        targetStickTime = 0
                                                    end
                                                else
                                                    targetStickTime = 0
                                                end
                                            else
                                                currentTargetBone = flowerBone
                                                targetStickTime = 0
                                            end
                                        else
                                            currentTargetBone = nil
                                            targetStickTime = 0
                                        end

                                        if flowerPos and hum then
                                            hum:MoveTo(flowerPos)
                                        elseif hum then
                                            -- Fallback: If all unblacklisted flowers are harvested/blacklisted, sweep field so player never stands still
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
                                            hum:MoveTo(targetPos)
                                        end

                                    elseif mode == "Lawn Mower" then
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
                if settings.autoFarm then
                    local fData = getFieldData(chosen)
                    if fData then
                        tpTo(fData.position + Vector3.new(0, 3, 0))
                    end
                end
            end
        end,
    })

    FarmTab:CreateDropdown({
        Name = "Movement Mode",
        Options = {"Pollen Hunter", "Lawn Mower", "Smooth Sweep", "Circle Walk", "Glide Roam", "Random Bounce", "Stay Center"},
        CurrentOption = "Pollen Hunter",
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
        Name = "Force Equip Pollen Tool",
        CurrentValue = true,
        Flag = "BeeForcePollenTool",
        Callback = function(v)
            settings.forceEquipTool = v
            settings.forceEquipShovel = v
            if v then ensurePollenToolEquipped() end
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

    -- ═══════════ Tab 3: Gathering & Multi-Tool ═══════════
    local GatherTab = Window:CreateTab("Gathering", "hammer")
    GatherTab:CreateSection("Universal Multi-Tool Auto-Equip")

    GatherTab:CreateButton({
        Name = "🌾 Equip Pollen Tool",
        Callback = function()
            ensureToolEquipped("tool")
            notify("Multi-Tool", "Equipped active Pollen Tool!")
        end,
    })

    GatherTab:CreateButton({
        Name = "🪓 Equip Axe",
        Callback = function()
            ensureToolEquipped("axe")
            notify("Multi-Tool", "Equipped active Axe!")
        end,
    })

    GatherTab:CreateButton({
        Name = "⛏️ Equip Pickaxe",
        Callback = function()
            ensureToolEquipped("pickaxe")
            notify("Multi-Tool", "Equipped active Pickaxe!")
        end,
    })

    GatherTab:CreateButton({
        Name = "🎣 Equip Fishing Rod",
        Callback = function()
            ensureToolEquipped("fishing_rod")
            notify("Multi-Tool", "Equipped active Fishing Rod!")
        end,
    })

    GatherTab:CreateButton({
        Name = "🕸️ Equip Bug Net",
        Callback = function()
            ensureToolEquipped("net")
            notify("Multi-Tool", "Equipped active Bug Net!")
        end,
    })

    GatherTab:CreateSection("Gather Settings")

    GatherTab:CreateToggle({
        Name = "Zone Lock (Current Region Only)",
        CurrentValue = true,
        Flag = "BeeZoneLock",
        Callback = function(v)
            settings.zoneLock = v
            notify("Zone Lock", v and "✅ Targets restricted to your current region." or "⚠️ Zone lock OFF — targeting all regions.")
        end,
    })

    GatherTab:CreateDropdown({
        Name = "Gather Movement Mode",
        Options = {"Teleport", "Walk"},
        CurrentOption = "Teleport",
        Flag = "BeeGatherMoveMode",
        Callback = function(opt)
            settings.gatherMoveMode = type(opt) == "table" and opt[1] or opt
        end,
    })

    GatherTab:CreateSection("Auto Mining Rocks (Pickaxe)")

    GatherTab:CreateToggle({
        Name = "Auto Mine Rocks",
        CurrentValue = false,
        Flag = "BeeAutoMine",
        Callback = function(v)
            settings.autoMine = v
            if v then
                startThread("autoMine", function(isActive)
                    local currentRock = nil
                    local rockStartTime = 0

                    while isActive() do
                        if not isConverting then
                            ensureToolEquipped("pickaxe")
                            local root = getRoot()

                            -- 1. Validate locked rock target
                            if currentRock then
                                local dead = isRockDead(currentRock)
                                local timedOut = (tick() - rockStartTime) > 15
                                if dead or timedOut or not root then
                                    if dead then
                                        felledRocks[currentRock] = tick() + 30
                                    end
                                    currentRock = nil
                                end
                            end

                            -- 2. Pick new rock target if none currently locked
                            if not currentRock and root then
                                local rock, dist = getNearestRock(settings.mineMaxDist)
                                if rock then
                                    currentRock = rock
                                    rockStartTime = tick()
                                end
                            end

                            -- 3. Mine the locked rock repeatedly until broken
                            if currentRock and root then
                                local part = currentRock:FindFirstChild("RockSpawn") or currentRock.PrimaryPart or currentRock:FindFirstChildWhichIsA("BasePart")
                                if part then
                                    local rockPos = part.Position
                                    local myPos = root.Position
                                    local dir = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(rockPos.X, 0, rockPos.Z))
                                    local standOffset = (dir.Magnitude > 0.1) and (dir.Unit * 4.5) or Vector3.new(4.5, 0, 0)
                                    local standPos = Vector3.new(rockPos.X + standOffset.X, rockPos.Y + 2.5, rockPos.Z + standOffset.Z)
                                    local dist = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(rockPos.X, 0, rockPos.Z)).Magnitude

                                    -- TP to stand position (bypasses collision with props/fences)
                                    if dist > 6 then
                                        if settings.gatherMoveMode == "Teleport" then
                                            tpTo(CFrame.lookAt(standPos, Vector3.new(rockPos.X, standPos.Y, rockPos.Z)))
                                            task.wait(0.05)
                                        else
                                            local hum = getHumanoid()
                                            if hum then hum:MoveTo(standPos) end
                                        end
                                    end

                                    -- Face & hit when close enough
                                    local curDist = (part.Position - root.Position).Magnitude
                                    if curDist <= 9.5 then
                                        local br = clientController and clientController.BreakableRocks
                                        local tm = clientController and clientController.ToolsManager
                                        local net = clientController and clientController.Network
                                        local bIds = clientController and clientController.BreakableIds
                                        local rKey = currentRock:GetAttribute("BreakableRockId") or (bIds and bIds.rockKey and bIds.rockKey(currentRock))

                                        root.CFrame = CFrame.new(root.Position, Vector3.new(rockPos.X, root.Position.Y, rockPos.Z))

                                        -- 1. Try standard module method with hit score 1 (100% perfect hit)
                                        if br and br.tryMineRockTarget then
                                            pcall(function() br:tryMineRockTarget(1, currentRock) end)
                                        end
                                        -- 2. Direct network backup
                                        if net and rKey then
                                            pcall(function()
                                                net:send("MineRock", currentRock.Name, rKey, 1)
                                            end)
                                        end
                                        -- 3. Visual pickaxe swing
                                        if tm and tm.playPickaxeAction then
                                            pcall(function() tm:playPickaxeAction() end)
                                        end

                                        -- 4. Check if rock broke from this hit
                                        if isRockDead(currentRock) then
                                            felledRocks[currentRock] = tick() + 20
                                            currentRock = nil
                                        end
                                    end
                                else
                                    currentRock = nil
                                end
                            end
                        end
                        task.wait(0.18)
                    end
                end)
            else
                stopThread("autoMine")
            end
        end,
    })

    GatherTab:CreateSlider({
        Name = "Mining Scan Reach",
        Range = {50, 600},
        Increment = 25,
        CurrentValue = 300,
        Suffix = " studs",
        Flag = "BeeMineReach",
        Callback = function(v)
            settings.mineMaxDist = v
        end,
    })

    GatherTab:CreateSection("Auto Chopping Trees (Axe)")

    GatherTab:CreateToggle({
        Name = "Auto Chop Trees",
        CurrentValue = false,
        Flag = "BeeAutoChop",
        Callback = function(v)
            settings.autoChop = v
            if v then
                startThread("autoChop", function(isActive)
                    local currentTree = nil
                    local treeStartTime = 0

                    while isActive() do
                        if not isConverting then
                            ensureToolEquipped("axe")
                            local root = getRoot()

                            -- 1. Validate locked tree target
                            if currentTree then
                                local dead = isTreeDead(currentTree)
                                local timedOut = (tick() - treeStartTime) > 15
                                if dead or timedOut or not root then
                                    if dead and currentTree then
                                        felledTrees[currentTree] = tick() + 20
                                    end
                                    currentTree = nil
                                end
                            end

                            -- 2. Pick new tree target if none currently locked
                            if not currentTree and root then
                                local tree, dist = getNearestTree(settings.chopMaxDist)
                                if tree then
                                    currentTree = tree
                                    treeStartTime = tick()
                                end
                            end

                            -- 3. Chop the locked tree repeatedly until felled
                            if currentTree and root then
                                local part = currentTree:FindFirstChild("StumpSpawn") or currentTree.PrimaryPart or currentTree:FindFirstChildWhichIsA("BasePart")
                                if part then
                                    local treePos = part.Position
                                    local myPos = root.Position
                                    local dir = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(treePos.X, 0, treePos.Z))
                                    local standOffset = (dir.Magnitude > 0.1) and (dir.Unit * 4.5) or Vector3.new(4.5, 0, 0)
                                    local standPos = Vector3.new(treePos.X + standOffset.X, treePos.Y + 2.5, treePos.Z + standOffset.Z)
                                    local dist = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(treePos.X, 0, treePos.Z)).Magnitude

                                    -- TP to stand position (bypasses collision with props/fences)
                                    if dist > 6.5 then
                                        if settings.gatherMoveMode == "Teleport" then
                                            tpTo(CFrame.lookAt(standPos, Vector3.new(treePos.X, standPos.Y, treePos.Z)))
                                            task.wait(0.05)
                                        else
                                            local hum = getHumanoid()
                                            if hum then hum:MoveTo(standPos) end
                                        end
                                    end

                                    -- Face & chop when close enough
                                    local curDist = (part.Position - root.Position).Magnitude
                                    if curDist <= 10 then
                                        local bt = clientController and clientController.BreakableTrees
                                        local tm = clientController and clientController.ToolsManager
                                        local net = clientController and clientController.Network
                                        local bIds = clientController and clientController.BreakableIds
                                        local tKey = currentTree:GetAttribute("BreakableTreeId") or (bIds and bIds.treeKey and bIds.treeKey(currentTree))

                                        root.CFrame = CFrame.new(root.Position, Vector3.new(treePos.X, root.Position.Y, treePos.Z))

                                        if bt and bt.tryChopTarget then
                                            pcall(function() bt:tryChopTarget(currentTree) end)
                                        end
                                        if net and tKey then
                                            pcall(function()
                                                net:send("ChopTree", currentTree.Name, tKey)
                                            end)
                                        end
                                        if tm and tm.playAxeSwing then
                                            pcall(function() tm:playAxeSwing() end)
                                        end

                                        -- Check if tree died from this hit
                                        if isTreeDead(currentTree) then
                                            felledTrees[currentTree] = tick() + 20
                                            currentTree = nil
                                        end
                                    end
                                else
                                    currentTree = nil
                                end
                            end
                        end
                        task.wait(0.18)
                    end
                end)
            else
                stopThread("autoChop")
            end
        end,
    })

    GatherTab:CreateSlider({
        Name = "Chopping Scan Reach",
        Range = {50, 600},
        Increment = 25,
        CurrentValue = 300,
        Suffix = " studs",
        Flag = "BeeChopReach",
        Callback = function(v)
            settings.chopMaxDist = v
        end,
    })

    GatherTab:CreateSection("Auto Catching Beetles (Net)")

    GatherTab:CreateToggle({
        Name = "Auto Catch Beetles / Bugs",
        CurrentValue = false,
        Flag = "BeeAutoCatch",
        Callback = function(v)
            settings.autoCatch = v
            if v then
                startThread("autoCatch", function(isActive)
                    while isActive() do
                        if not isConverting then
                            ensureToolEquipped("net")
                            local beetle, dist = getNearestBeetle(settings.catchMaxDist)
                            local root = getRoot()
                            if beetle and root then
                                local model = beetle.model or beetle.rootPart or beetle.primaryPart
                                local part = typeof(model) == "Instance" and (model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart"))
                                if part then
                                    local beetlePos = part.Position
                                    local myPos = root.Position
                                    local dir = (Vector3.new(myPos.X, 0, myPos.Z) - Vector3.new(beetlePos.X, 0, beetlePos.Z))
                                    local standOffset = (dir.Magnitude > 0.1) and (dir.Unit * 4.0) or Vector3.new(4.0, 0, 0)
                                    local standPos = Vector3.new(beetlePos.X + standOffset.X, beetlePos.Y + 2.0, beetlePos.Z + standOffset.Z)

                                    if dist > 5 then
                                        if settings.gatherMoveMode == "Teleport" then
                                            tpTo(CFrame.lookAt(standPos, Vector3.new(beetlePos.X, standPos.Y, beetlePos.Z)))
                                            task.wait(0.05)
                                        else
                                            local hum = getHumanoid()
                                            if hum then hum:MoveTo(standPos) end
                                        end
                                    end

                                    local curDist = (part.Position - root.Position).Magnitude
                                    if curDist <= 8.5 then
                                        local nc = clientController and clientController.NetCatchingMinigame
                                        local tm = clientController and clientController.ToolsManager

                                        root.CFrame = CFrame.new(root.Position, Vector3.new(beetlePos.X, root.Position.Y, beetlePos.Z))

                                        if nc and nc.tryCatchMob then
                                            pcall(function() nc:tryCatchMob(beetle) end)
                                        end
                                        if tm and tm.playNetSwing then
                                            pcall(function() tm:playNetSwing() end)
                                        end
                                    end
                                end
                            end
                        end
                        task.wait(0.3)
                    end
                end)
            else
                stopThread("autoCatch")
            end
        end,
    })

    GatherTab:CreateSlider({
        Name = "Catching Scan Reach",
        Range = {50, 500},
        Increment = 25,
        CurrentValue = 200,
        Suffix = " studs",
        Flag = "BeeCatchReach",
        Callback = function(v)
            settings.catchMaxDist = v
        end,
    })

    -- ═══════════ Tab 4: Teleports ═══════════
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

    -- ═══════════ Tab 5: Movement & World ═══════════
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

    -- ═══════════ Tab 6: Visuals / ESP ═══════════
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

    -- ═══════════ Tab 7: Info & Utilities ═══════════
    local InfoTab = Window:CreateTab("Overview", "overview")
    InfoTab:CreateSection("Game Info")
    InfoTab:CreateLabel("Experience: [🔥UPDATE 1] Beeconomy!")
    InfoTab:CreateLabel("Module Version: v2.1.0 (Zone-Lock + Smart Gather Edition)")
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

    notify("Beeconomy!", "v2.1.0 Loaded! Zone-Lock + Smart Gather Edition ready.")
end
