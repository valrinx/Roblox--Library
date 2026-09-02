-- ═══════════════════════════════════════════════════════════════════
--   Dungeon Lootr  |  RAVEN HUB Module  |  v2.0.1
--   Verified remotes from live Raven MCP inspection
--   PlaceId: 132285059959516  |  GameId: 9656201728
--   Framework: Flat remotes (ReplicatedStorage.Remotes/*)
-- ═══════════════════════════════════════════════════════════════════

local function findChild(parent, name)
    if not parent then return nil end
    local ok, child = pcall(function()
        return parent:FindFirstChild(name)
    end)
    return ok and child or nil
end

local function getChildren(parent)
    if not parent then return {} end
    local ok, children = pcall(function()
        return parent:GetChildren()
    end)
    return ok and children or {}
end

local function getAttribute(instance, name)
    if not instance then return nil end
    local ok, value = pcall(function()
        return instance:GetAttribute(name)
    end)
    if not ok then return nil end
    return value
end

local function normalizeOptionValue(value)
    if type(value) == "table" then
        if value[1] ~= nil then
            return normalizeOptionValue(value[1])
        end
        if value.value ~= nil then
            return normalizeOptionValue(value.value)
        end
        if value.Value ~= nil then
            return normalizeOptionValue(value.Value)
        end
    end
    return value
end

local function resolveRuntimePaths(playerGui)
    local main = findChild(playerGui, "Main")
    local hud = main and findChild(main, "HUD")

    -- Keep the legacy shape as a fallback for older experiences, but prefer
    -- the live Dungeon Lootr hierarchy: PlayerGui/Main/HUD and Main/Frames.
    if not hud then
        local legacyRoot = findChild(playerGui, "HUD")
        local legacyHud = legacyRoot and findChild(legacyRoot, "HUD")
        if legacyHud then
            main = legacyRoot
            hud = legacyHud
        end
    end

    local actions = findChild(hud, "Actions")
    local bottom = findChild(actions, "Bottom")
    local skillActions = findChild(bottom, "Actions")
    local left = findChild(actions, "Left")
    local leftButtons = findChild(left, "Buttons")
    local frames = findChild(main, "Frames")
    local menuButtons = findChild(frames, "MenuButtons")
    local menuContent = findChild(menuButtons, "Content")
    local menuButtonContainer = findChild(menuContent, "ButtonContainer")

    return {
        main = main,
        hud = hud,
        actions = actions,
        skillActions = skillActions,
        healthSlot = findChild(skillActions, "Health"),
        dungeonContainer = findChild(hud, "Dungeon_Container"),
        dungeonLoot = findChild(hud, "Dungeon_Loot"),
        frames = frames,
        questFrame = findChild(frames, "Quests"),
        dungeonSelectFrame = findChild(frames, "Dungeon_Select"),
        inventoryFrame = findChild(frames, "Inventory"),
        storageFrame = findChild(frames, "Storage"),
        forgeFrame = findChild(frames, "Forge"),
        menuButtons = menuButtons,
        menuButton = findChild(leftButtons, "Menu"),
        menuButtonContainer = menuButtonContainer,
    }
end

local function isInDungeonForPaths(paths, player)
    local explicit = getAttribute(player, "InDungeon")
    if type(explicit) == "boolean" then return explicit end

    explicit = getAttribute(player, "DungeonRun")
    if type(explicit) == "boolean" then return explicit end

    return paths and paths.dungeonContainer ~= nil or false
end

local function resolveEnemyRoots(workspaceRoot, dungeonName)
    local roots = {}
    local name = tostring(dungeonName or "")
    if name == "" then return roots end

    local prefix = "Generated_" .. name .. "_"
    for _, child in ipairs(getChildren(workspaceRoot)) do
        if string.sub(tostring(child.Name or ""), 1, #prefix) == prefix then
            table.insert(roots, child)
        end
    end
    return roots
end

return function(Window, scriptInfo)
    if scriptInfo and scriptInfo.testMode then
        scriptInfo.testMode.resolveRuntimePaths = resolveRuntimePaths
        scriptInfo.testMode.isInDungeon = isInDungeonForPaths
        scriptInfo.testMode.normalizeOptionValue = normalizeOptionValue
        scriptInfo.testMode.resolveEnemyRoots = resolveEnemyRoots
        return
    end

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TeleportService = game:GetService("TeleportService")
    local HttpService = game:GetService("HttpService")

    local LP = Players.LocalPlayer
    local PG = LP.PlayerGui

    local function getRuntimePaths()
        return resolveRuntimePaths(PG)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  REMOTE RESOLVER (Flat paths — NOT Knit)
    --  Verified from live inspection:
    --    ReplicatedStorage.Remotes.<name>           (RF or RE)
    --    ReplicatedStorage.Player.Remotes.Inputs.<action>  (RE)
    --  Remote names/types are known; UI-backed actions are preferred where
    --  available because their argument contract is owned by the live client.
    -- ═══════════════════════════════════════════════════════════════════
    local function getRemote(name)
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        return remotes and remotes:FindFirstChild(name)
    end

    local function getCombatInput(action)
        local player = ReplicatedStorage:FindFirstChild("Player")
        local remotes = player and player:FindFirstChild("Remotes")
        local inputs = remotes and remotes:FindFirstChild("Inputs")
        return inputs and inputs:FindFirstChild(action)
    end

    local function invokeRF(name, ...)
        local args = {...}
        local rf = getRemote(name)
        if rf and rf:IsA("RemoteFunction") then
            local ok, res = pcall(function() return rf:InvokeServer(unpack(args)) end)
            return ok and res or nil
        end
        return nil
    end

    local function fireCombat(action, ...)
        local args = {...}
        local r = getCombatInput(action)
        if r then pcall(function() r:FireServer(unpack(args)) end) end
    end

    -- The live dungeon flow is owned by Knit, not by the old flat
    -- TeleportToDungeon RemoteFunction.  The client controller calls these
    -- service methods and awaits their Promises, so keep the same contract.
    local function getKnitService(serviceName)
        local packages = ReplicatedStorage:FindFirstChild("Packages")
        local knitModule = packages and packages:FindFirstChild("Knit")
        if not knitModule then return nil end

        local okKnit, Knit = pcall(require, knitModule)
        if not okKnit or type(Knit) ~= "table" or type(Knit.GetService) ~= "function" then
            return nil
        end

        local okService, service = pcall(function()
            return Knit.GetService(serviceName)
        end)
        return okService and service or nil
    end

    local function requestQueue(methodName, ...)
        local service = getKnitService("DungeonQueueService")
        local method = service and service[methodName]
        if type(method) ~= "function" then return false end

        local args = {...}
        local okCall, result = pcall(function()
            return method(service, unpack(args))
        end)
        if not okCall then return false end

        if result and type(result.await) == "function" then
            local okAwait, awaited = pcall(function()
                return result:await()
            end)
            return okAwait and awaited ~= false
        end

        return result ~= false
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  SETTINGS
    -- ═══════════════════════════════════════════════════════════════════
    local CFG = {
        -- Queue Settings (real dungeon names from ServerState)
        Dungeon = getAttribute(LP, "CurrentDungeon") or "Bandits Den",
        Difficulty = getAttribute(LP, "CurrentDifficultyMode") or "Normal",
        Mode = "Dungeon",
        StartType = "Auto",

        -- Auto Queue
        AutoQueue = false,
        AutoReplay = false,
        AutoReturn = false,

        -- Mob Farm
        TargetMob = "Closest",
        FarmMobs = false,

        -- Combat
        KillAura = false,
        AutoSkills = false,
        AutoSkillsToggle = true,

        -- Farm Config
        Position = "Front",
        XOffset = 0,
        YOffset = 3,
        Distance = 5,

        -- Auto Potion
        UseAtHpPercent = 30,
        AutoPotion = false,

        -- Auto Chests
        AutoSelectChests = false,
        AutoMidRunChests = false,

        -- Movement
        Speed = false,
        SpeedValue = 28,
        Fly = false,
        FlySpeed = 50,

        -- Player Misc
        NoStun = false,
        Noclip = false,

        -- Auto Sell
        SellBelow = "Common",
        SellNow = false,
        AutoSell = false,

        -- Loot Bag
        SellRarity = "Common",
        SellRarityFromBag = false,
        SellAllLootBag = false,

        -- Merchant
        MerchantItem = "Health Potion",
        RefreshStock = false,
        BuySelected = false,

        -- Auto Buy
        AutoBuyMinRarity = "Common",
        AutoBuy = false,

        -- Auto Store
        AutoStoreMinRarity = "Common",
        StoreNow = false,
        AutoStore = false,

        -- Auto Withdraw
        AutoWithdrawMinRarity = "Common",
        WithdrawNow = false,
        WithdrawAll = false,

        -- Forge
        ForgeItem = "Weapon",
        RefreshForgeItems = false,
        UseProtectionScroll = false,
        UseEnhance = false,
        ForgeOnce = false,

        -- Auto Forge
        AutoForgeMinRarity = "Common",
        AutoForgeMaxLevel = 10,
        AutoForge = false,

        -- Quests
        ClaimAllQuests = false,
        AutoClaimQuests = false,

        -- Webhook
        WebhookURL = "",
        LootWebhook = false,

        -- Internal
        InDungeon = false,
    }

    local CONNS = {}
    local FLAGS = { attacking = false }

    -- ═══════════════════════════════════════════════════════════════════
    --  CHARACTER HELPERS
    -- ═══════════════════════════════════════════════════════════════════
    local function getRoot()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function getHum()
        local c = LP.Character
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function isAlive()
        local h = getHum()
        return h and h.Health > 0
    end

    local function getHPPercent()
        local h = getHum()
        if not h then return 100 end
        return (h.Health / h.MaxHealth) * 100
    end

    local function teleportTo(pos)
        local root = getRoot()
        if root then
            root.CFrame = CFrame.new(pos + Vector3.new(0, CFG.YOffset, 0))
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end

    local function faceTarget(targetPos)
        local root = getRoot()
        if root then
            local dir = (targetPos - root.Position)
            local flat = Vector3.new(dir.X, 0, dir.Z)
            if flat.Magnitude > 0.1 then
                root.CFrame = CFrame.new(root.Position, root.Position + flat.Unit)
            end
        end
    end

    local function randDelay(base, jit)
        jit = jit or 0.15
        return base * (1 + (math.random() * 2 - 1) * jit)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  ENEMY SCANNING
    --  Verified: enemies are models with Humanoid inside workspace (dungeon)
    --  In lobby: NPCs folder exists but may be empty
    --  In dungeon: enemies spawn dynamically as models
    -- ═══════════════════════════════════════════════════════════════════
    local enemyCache = { at = 0, list = {} }
    local ENEMY_SCAN_INTERVAL = 0.2

    local function getEnemies(force)
        local now = os.clock()
        if not force and now - enemyCache.at < ENEMY_SCAN_INTERVAL then
            return enemyCache.list
        end

        local list, seen, playerCharacters = {}, {}, {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then playerCharacters[player.Character] = true end
        end

        local function inspect(obj)
            if not obj or seen[obj] or obj == LP.Character then return end
            seen[obj] = true
            if not obj:IsA("Model") then return end

            local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 and not playerCharacters[obj] then
                table.insert(list, {
                    model = obj, root = hrp, hum = hum,
                    hp = hum.Health, maxHp = hum.MaxHealth, pos = hrp.Position,
                })
            end
        end

        local function scanRoot(root)
            if not root then return end
            inspect(root)
            for _, descendant in ipairs(root:GetDescendants()) do
                inspect(descendant)
            end
        end

        local dungeonName = getAttribute(LP, "CurrentDungeon") or CFG.Dungeon
        for _, root in ipairs(resolveEnemyRoots(workspace, dungeonName)) do
            scanRoot(root)
        end
        for _, folderName in ipairs({"Enemies", "NPCs", "Mobs"}) do
            scanRoot(workspace:FindFirstChild(folderName))
        end

        enemyCache.at = now
        enemyCache.list = list
        return list
    end

    local function getClosestEnemy(maxR)
        local my = getRoot()
        if not my then return nil end
        local best, bestD = nil, maxR or math.huge
        for _, e in ipairs(getEnemies()) do
            local d = (e.root.Position - my.Position).Magnitude
            if d < bestD then best, bestD = e, d end
        end
        return best
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  DUNGEON STATE
    --  Verified live shape: PlayerGui.Main.HUD, with a legacy fallback above.
    -- ═══════════════════════════════════════════════════════════════════
    local function isInDungeon()
        return isInDungeonForPaths(getRuntimePaths(), LP)
    end

    local function queueDungeon()
        if isInDungeon() then return false end
        if not requestQueue("RequestSelectDungeon", CFG.Dungeon) then return false end
        if not requestQueue("RequestSelectDifficulty", CFG.Difficulty) then return false end
        if not requestQueue("RequestSelectMode", CFG.Mode) then return false end
        if CFG.StartType == "Manual" then return true end
        if not requestQueue("RequestDungeonChange", CFG.Dungeon) then return false end
        return requestQueue("RequestStartSoloRun")
    end

    local function activateGuiButton(button)
        if not button then return false end
        local ok, isButton = pcall(function() return button:IsA("GuiButton") end)
        if not ok or not isButton then return false end
        if type(firesignal) == "function" then
            for _, signal in ipairs({button.MouseButton1Click, button.Activated, button.MouseButton1Down}) do
                if signal and pcall(firesignal, signal) then return true end
            end
        end
        return pcall(function() button:Activate() end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  SKILL BAR
    --  Verified: Main.HUD.Actions.Bottom.Actions.1-4 (skill slots)
    -- ═══════════════════════════════════════════════════════════════════
    local function clickSkillSlot(slotNum)
        local paths = getRuntimePaths()
        local slot = findChild(paths.skillActions, tostring(slotNum))
        return activateGuiButton(slot)
    end

    local function isSkillReady(slotNum)
        local paths = getRuntimePaths()
        local slot = findChild(paths.skillActions, tostring(slotNum))
        if not slot then return false end
        local cd = slot:FindFirstChild("Cooldown") or slot:FindFirstChild("CD")
        if cd then
            local ok, scale = pcall(function() return cd.Size.X.Scale end)
            if ok then return scale < 0.05 end
        end
        return true
    end

    -- Click a menu button from Main.Frames.MenuButtons.Content.ButtonContainer.
    local function clickMenuButton(name)
        local paths = getRuntimePaths()
        local frames = paths.frames
        local menuButtons = paths.menuButtons or findChild(frames, "MenuButtons")
        local menuContent = findChild(menuButtons, "Content")
        local menuButtonContainer = paths.menuButtonContainer or findChild(menuContent, "ButtonContainer")
        local button = findChild(menuButtonContainer, name)
        if not button and paths.menuButton then
            activateGuiButton(paths.menuButton)
            task.wait(0.25)
            paths = getRuntimePaths()
            button = findChild(paths.menuButtonContainer, name)
        end
        return activateGuiButton(button)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  AUTO POTION
    --  Verified live control: Main.HUD.Actions.Bottom.Actions.Health
    --  Use the game's own health-slot button so cooldown/inventory rules apply.
    -- ═══════════════════════════════════════════════════════════════════
    local function usePotion()
        local paths = getRuntimePaths()
        if activateGuiButton(paths.healthSlot) then return true end
        for _, slot in ipairs(getChildren(paths.skillActions)) do
            local slotName = string.lower(tostring(slot.Name or ""))
            if string.find(slotName, "potion") or string.find(slotName, "health") then
                if activateGuiButton(slot) then return true end
            end
        end
        return false
    end

    local function triggerProximityPrompt(prompt)
        if type(fireproximityprompt) == "function" then
            if pcall(fireproximityprompt, prompt) then return true end
        end

        local holdDuration = 0
        pcall(function() holdDuration = prompt.HoldDuration end)
        local began = pcall(function() prompt:InputHoldBegin() end)
        if not began then return false end
        if holdDuration > 0 then task.wait(holdDuration + 0.05) end
        pcall(function() prompt:InputHoldEnd() end)
        return true
    end

    local function openDungeonChest()
        if not isInDungeon() then return false end
        local myRoot = getRoot()
        if not myRoot then return false end

        local dungeonName = getAttribute(LP, "CurrentDungeon") or CFG.Dungeon
        local nearestPrompt, nearestPosition, nearestDistance
        for _, dungeonRoot in ipairs(resolveEnemyRoots(workspace, dungeonName)) do
            for _, desc in ipairs(dungeonRoot:GetDescendants()) do
                local enabled = false
                pcall(function() enabled = desc:IsA("ProximityPrompt") and desc.Enabled end)
                local chest = desc.Parent and desc.Parent.Parent
                if enabled and desc.Name == "ChestPrompt" and chest and
                    string.sub(tostring(chest.Name or ""), 1, 12) == "DungeonChest" then
                    local position
                    pcall(function() position = desc.Parent.WorldPosition end)
                    if position then
                        local distance = (position - myRoot.Position).Magnitude
                        if not nearestDistance or distance < nearestDistance then
                            nearestPrompt, nearestPosition, nearestDistance = desc, position, distance
                        end
                    end
                end
            end
        end

        if not nearestPrompt then return false end
        local activationDistance = 8
        pcall(function() activationDistance = nearestPrompt.MaxActivationDistance end)
        if nearestDistance > activationDistance then
            teleportTo(nearestPosition)
            task.wait(0.1)
        end
        return triggerProximityPrompt(nearestPrompt)
    end

    local function selectLootReward()
        local paths = getRuntimePaths()
        local root = paths.dungeonLoot
        if not root then return false end
        for _, desc in ipairs(root:GetDescendants()) do
            if desc:IsA("GuiButton") then
                local visible = true
                pcall(function() visible = desc.Parent and desc.Parent.Visible ~= false end)
                local name = string.lower(tostring(desc.Name or ""))
                local text = ""
                pcall(function() text = string.lower(tostring(desc.Text or "")) end)
                if visible and (
                    name == "selection_button" or
                    string.find(name, "chest") or string.find(name, "claim") or
                    string.find(text, "chest") or string.find(text, "claim")
                ) then
                    if activateGuiButton(desc) then return true end
                end
            end
        end
        return false
    end

    local function claimQuestButtons()
        local questFrame = getRuntimePaths().questFrame
        if not questFrame then return false end
        local claimed = false
        for _, desc in ipairs(questFrame:GetDescendants()) do
            if desc:IsA("GuiButton") then
                local name = string.lower(tostring(desc.Name or ""))
                local text = ""
                pcall(function() text = string.lower(tostring(desc.Text or "")) end)
                if string.find(name, "claim") or string.find(text, "claim") then
                    claimed = activateGuiButton(desc) or claimed
                end
            end
        end
        return claimed
    end

    local function connectInterval(name, enabled, interval, callback)
        local running = false
        local nextRun = 0
        return RunService.Heartbeat:Connect(function()
            if running or not enabled() then return end
            local now = os.clock()
            if now < nextRun then return end
            nextRun = now + interval
            running = true
            task.spawn(function()
                local ok, err = pcall(callback)
                if not ok then
                    warn("[Dungeon Lootr] " .. name .. " failed: " .. tostring(err))
                end
                running = false
            end)
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  FLY SYSTEM
    -- ═══════════════════════════════════════════════════════════════════
    local flyBodyVel, flyBodyGyro

    local function startFly()
        local root = getRoot()
        if not root then return end
        flyBodyVel = Instance.new("BodyVelocity")
        flyBodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        flyBodyVel.Velocity = Vector3.zero
        flyBodyVel.Parent = root
        flyBodyGyro = Instance.new("BodyGyro")
        flyBodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        flyBodyGyro.P = 9e4
        flyBodyGyro.Parent = root
    end

    local function stopFly()
        if flyBodyVel then flyBodyVel:Destroy(); flyBodyVel = nil end
        if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
    end

    local function updateFly()
        if not CFG.Fly then return end
        local root = getRoot()
        if not root or not flyBodyVel then return end
        local cam = workspace.CurrentCamera
        local dir = Vector3.zero
        if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
        if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
        if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
        flyBodyVel.Velocity = dir.Magnitude > 0 and dir.Unit * CFG.FlySpeed or Vector3.zero
        flyBodyGyro.CFrame = cam.CFrame
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  NOCLIP
    -- ═══════════════════════════════════════════════════════════════════
    local function updateNoclip()
        if not CFG.Noclip then return end
        local c = LP.Character
        if c then
            for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  WEBHOOK
    -- ═══════════════════════════════════════════════════════════════════
    local function sendWebhook(title, description, color)
        if not CFG.WebhookURL or CFG.WebhookURL == "" then return end
        pcall(function()
            local payload = {
                embeds = {{
                    title = title,
                    description = description,
                    color = color or 3447003,
                    footer = { text = "Dungeon Lootr | RAVEN HUB" },
                    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                }}
            }
            local body = HttpService:JSONEncode(payload)
            if syn and syn.request then
                syn.request({ Url = CFG.WebhookURL, Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = body })
            elseif http_request then
                http_request({ Url = CFG.WebhookURL, Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = body })
            elseif request then
                request({ Url = CFG.WebhookURL, Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = body })
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  RARITY HELPERS
    -- ═══════════════════════════════════════════════════════════════════
    local RARITY_ORDER = {
        Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
        Legendary = 5, Mythic = 6, Celestial = 7, Exotic = 8,
    }

    local RARITY_NAMES = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Celestial","Exotic"}

    -- ═══════════════════════════════════════════════════════════════════
    --  DUNGEON NAMES (from ServerState verified live)
    -- ═══════════════════════════════════════════════════════════════════
    local DUNGEON_NAMES = {
        "Knights", "Bandits Den", "Catacombs", "Goblins",
        "Demon", "Throne Room", "Double Dungeon", "Snow", "Forest Challenge",
    }

    -- ═══════════════════════════════════════════════════════════════════
    --  UI TABS
    -- ═══════════════════════════════════════════════════════════════════

    -- ───────── Queue Tab ─────────
    local QT = Window:CreateTab("Queue", 4483362458)
    QT:CreateSection("Queue Settings")

    QT:CreateDropdown({
        Name = "Dungeon",
        Options = DUNGEON_NAMES,
        CurrentOption = {CFG.Dungeon},
        Callback = function(v) CFG.Dungeon = normalizeOptionValue(v) end,
    })

    QT:CreateDropdown({
        Name = "Difficulty",
        Options = {"Easy","Normal","Hard","Nightmare","Endless"},
        CurrentOption = {CFG.Difficulty},
        Callback = function(v) CFG.Difficulty = normalizeOptionValue(v) end,
    })

    QT:CreateDropdown({
        Name = "Mode",
        Options = {"Dungeon","Challenge","Raids"},
        CurrentOption = {CFG.Mode},
        Callback = function(v) CFG.Mode = normalizeOptionValue(v) end,
    })

    QT:CreateDropdown({
        Name = "Start Type",
        Options = {"Auto","Manual"},
        CurrentOption = {"Auto"},
        Callback = function(v) CFG.StartType = normalizeOptionValue(v) end,
    })

    QT:CreateSection("Automation")

    QT:CreateToggle({
        Name = "Auto Queue",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoQueue = v
            if v then
                CONNS["AutoQueue"] = connectInterval("AutoQueue", function()
                    return CFG.AutoQueue and not isInDungeon()
                end, 3, function()
                    queueDungeon()
                end)
            else
                if CONNS["AutoQueue"] then CONNS["AutoQueue"]:Disconnect(); CONNS["AutoQueue"] = nil end
            end
        end,
    })

    QT:CreateToggle({
        Name = "Auto Replay",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoReplay = v
            if v then
                CONNS["AutoReplay"] = connectInterval("AutoReplay", function()
                    return CFG.AutoReplay and not isInDungeon()
                end, 3, function()
                    queueDungeon()
                end)
            else
                if CONNS["AutoReplay"] then CONNS["AutoReplay"]:Disconnect(); CONNS["AutoReplay"] = nil end
            end
        end,
    })

    QT:CreateToggle({
        Name = "Auto Return",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoReturn = v
            if v then
                CONNS["AutoReturn"] = connectInterval("AutoReturn", function()
                    return CFG.AutoReturn and isInDungeon()
                end, 5, function()
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
                    end)
                end)
            else
                if CONNS["AutoReturn"] then CONNS["AutoReturn"]:Disconnect(); CONNS["AutoReturn"] = nil end
            end
        end,
    })

    -- ───────── Combat Tab ─────────
    local CT = Window:CreateTab("Combat", 4483362458)
    CT:CreateSection("Kill Aura")

    CT:CreateToggle({
        Name = "Kill Aura",
        CurrentValue = false,
        Callback = function(v)
            CFG.KillAura = v
            if v then
                CONNS["KillAura"] = connectInterval("KillAura", function()
                    return CFG.KillAura
                end, 0.15, function()
                    if not CFG.KillAura or not isAlive() or FLAGS.attacking then return end
                    local my = getRoot()
                    if not my then return end
                    local enemies = getEnemies()
                    if #enemies == 0 then return end
                    table.sort(enemies, function(a, b)
                        return (a.root.Position - my.Position).Magnitude <
                               (b.root.Position - my.Position).Magnitude
                    end)
                    FLAGS.attacking = true
                    for _, e in ipairs(enemies) do
                        if not CFG.KillAura then break end
                        if e.hum.Health > 0 then
                            local targetPos = e.root.Position + Vector3.new(
                                CFG.XOffset, 0,
                                (CFG.Position == "Behind" and -CFG.Distance or CFG.Distance)
                            )
                            teleportTo(targetPos)
                            task.wait(randDelay(0.05, 0.1))
                            faceTarget(e.root.Position)
                            fireCombat("Attack")
                            task.wait(randDelay(0.08, 0.12))
                        end
                    end
                    FLAGS.attacking = false
                end)
            else
                if CONNS["KillAura"] then CONNS["KillAura"]:Disconnect(); CONNS["KillAura"] = nil end
                FLAGS.attacking = false
            end
        end,
    })

    CT:CreateSection("Auto Skills")

    CT:CreateToggle({
        Name = "Auto Skills",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoSkills = v
            if v then
                CONNS["AutoSkills"] = connectInterval("AutoSkills", function()
                    return CFG.AutoSkills and CFG.AutoSkillsToggle
                end, 0.12, function()
                    if not CFG.AutoSkills or not CFG.AutoSkillsToggle or not isAlive() then return end
                    for slot = 1, 4 do
                        if isSkillReady(slot) then
                            clickSkillSlot(slot)
                            break
                        end
                    end
                end)
            else
                if CONNS["AutoSkills"] then CONNS["AutoSkills"]:Disconnect(); CONNS["AutoSkills"] = nil end
            end
        end,
    })

    CT:CreateToggle({
        Name = "Auto Skills Toggle",
        CurrentValue = true,
        Callback = function(v) CFG.AutoSkillsToggle = v end,
    })

    -- ───────── Farm Tab ─────────
    local FT = Window:CreateTab("Farm", 4483362458)
    FT:CreateSection("Mob Farm")

    FT:CreateDropdown({
        Name = "Target Mob",
        Options = {"Closest","Any","Boss","Elite","Minion"},
        CurrentOption = {"Closest"},
        Callback = function(v) CFG.TargetMob = v end,
    })

    FT:CreateToggle({
        Name = "Farm Mobs",
        CurrentValue = false,
        Callback = function(v)
            CFG.FarmMobs = v
            if v then
                CONNS["FarmMobs"] = connectInterval("FarmMobs", function()
                    return CFG.FarmMobs
                end, 0.15, function()
                    if not CFG.FarmMobs or not isAlive() then return end
                    local my = getRoot()
                    if not my then return end
                    local enemies = getEnemies()
                    if #enemies == 0 then return end
                    table.sort(enemies, function(a, b)
                        return (a.root.Position - my.Position).Magnitude <
                               (b.root.Position - my.Position).Magnitude
                    end)
                    local target = enemies[1]
                    if target then
                        local pos = target.root.Position + Vector3.new(
                            CFG.XOffset, 0,
                            (CFG.Position == "Behind" and -CFG.Distance or CFG.Distance)
                        )
                        teleportTo(pos)
                        task.wait(randDelay(0.03, 0.1))
                        faceTarget(target.root.Position)
                        fireCombat("Attack")
                    end
                end)
            else
                if CONNS["FarmMobs"] then CONNS["FarmMobs"]:Disconnect(); CONNS["FarmMobs"] = nil end
            end
        end,
    })

    FT:CreateSection("Position Config")
    FT:CreateDropdown({
        Name = "Position",
        Options = {"Front","Behind","Side","Top"},
        CurrentOption = {"Front"},
        Callback = function(v) CFG.Position = v end,
    })

    FT:CreateSlider({
        Name = "X Offset",
        Range = {-20, 20}, Increment = 1, Suffix = "",
        CurrentValue = 0,
        Callback = function(v) CFG.XOffset = v end,
    })

    FT:CreateSlider({
        Name = "Y Offset",
        Range = {0, 20}, Increment = 1, Suffix = "",
        CurrentValue = 3,
        Callback = function(v) CFG.YOffset = v end,
    })

    FT:CreateSlider({
        Name = "Distance",
        Range = {1, 50}, Increment = 1, Suffix = "",
        CurrentValue = 5,
        Callback = function(v) CFG.Distance = v end,
    })

    -- ───────── Auto Potion ─────────
    FT:CreateSection("Auto Potion")

    FT:CreateSlider({
        Name = "Use At HP %",
        Range = {5, 90}, Increment = 5, Suffix = "%",
        CurrentValue = 30,
        Callback = function(v) CFG.UseAtHpPercent = v end,
    })

    FT:CreateToggle({
        Name = "Auto Potion",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoPotion = v
            if v then
                CONNS["AutoPotion"] = connectInterval("AutoPotion", function()
                    return CFG.AutoPotion
                end, 1, function()
                    if not CFG.AutoPotion or not isAlive() then return end
                    if getHPPercent() <= CFG.UseAtHpPercent then
                        usePotion()
                    end
                end)
            else
                if CONNS["AutoPotion"] then CONNS["AutoPotion"]:Disconnect(); CONNS["AutoPotion"] = nil end
            end
        end,
    })

    -- ───────── Auto Chests ─────────
    FT:CreateSection("Auto Chests")

    FT:CreateToggle({
        Name = "Auto Select Loot Rewards",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoSelectChests = v
            if v then
                CONNS["AutoLootSelection"] = connectInterval("AutoLootSelection", function()
                    return CFG.AutoSelectChests
                end, 0.25, selectLootReward)
            else
                if CONNS["AutoLootSelection"] then CONNS["AutoLootSelection"]:Disconnect(); CONNS["AutoLootSelection"] = nil end
            end
        end,
    })

    FT:CreateToggle({
        Name = "Auto Mid-Run Chests",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoMidRunChests = v
            if v then
                CONNS["AutoChests"] = connectInterval("AutoChests", function()
                    return CFG.AutoMidRunChests
                end, 0.5, openDungeonChest)
            else
                if CONNS["AutoChests"] then CONNS["AutoChests"]:Disconnect(); CONNS["AutoChests"] = nil end
            end
        end,
    })

    -- ───────── Movement Tab ─────────
    local MT = Window:CreateTab("Movement", 4483362458)
    MT:CreateSection("Speed")

    MT:CreateToggle({
        Name = "Speed",
        CurrentValue = false,
        Callback = function(v)
            CFG.Speed = v
            if v then
                CONNS["Speed"] = RunService.Heartbeat:Connect(function()
                    if not CFG.Speed then return end
                    local h = getHum()
                    if h then h.WalkSpeed = CFG.SpeedValue end
                end)
            else
                if CONNS["Speed"] then CONNS["Speed"]:Disconnect(); CONNS["Speed"] = nil end
                local h = getHum()
                if h then h.WalkSpeed = 28 end  -- default is 28, not 16
            end
        end,
    })

    MT:CreateSlider({
        Name = "Speed Value",
        Range = {28, 200}, Increment = 1, Suffix = " studs/s",
        CurrentValue = 28,
        Callback = function(v)
            CFG.SpeedValue = v
            if CFG.Speed then
                local h = getHum()
                if h then h.WalkSpeed = v end
            end
        end,
    })

    MT:CreateSection("Fly")

    MT:CreateToggle({
        Name = "Fly",
        CurrentValue = false,
        Callback = function(v)
            CFG.Fly = v
            if v then
                startFly()
                CONNS["Fly"] = RunService.RenderStepped:Connect(updateFly)
            else
                if CONNS["Fly"] then CONNS["Fly"]:Disconnect(); CONNS["Fly"] = nil end
                stopFly()
            end
        end,
    })

    MT:CreateSlider({
        Name = "Fly Speed",
        Range = {10, 200}, Increment = 5, Suffix = "",
        CurrentValue = 50,
        Callback = function(v) CFG.FlySpeed = v end,
    })

    -- ───────── Player Tab ─────────
    local PT = Window:CreateTab("Player", 4483362458)
    PT:CreateSection("Player Misc")

    PT:CreateToggle({
        Name = "No Stun",
        CurrentValue = false,
        Callback = function(v)
            CFG.NoStun = v
            if v then
                CONNS["NoStun"] = RunService.Heartbeat:Connect(function()
                    if not CFG.NoStun then return end
                    local h = getHum()
                    if h then
                        pcall(function() h.PlatformStand = false end)
                        pcall(function() h.Sit = false end)
                    end
                end)
            else
                if CONNS["NoStun"] then CONNS["NoStun"]:Disconnect(); CONNS["NoStun"] = nil end
            end
        end,
    })

    PT:CreateToggle({
        Name = "Noclip",
        CurrentValue = false,
        Callback = function(v)
            CFG.Noclip = v
            if v then
                CONNS["Noclip"] = RunService.Stepped:Connect(updateNoclip)
            else
                if CONNS["Noclip"] then CONNS["Noclip"]:Disconnect(); CONNS["Noclip"] = nil end
            end
        end,
    })

    -- ───────── Sell Tab ─────────
    local ST = Window:CreateTab("Sell", 4483362458)
    ST:CreateSection("Auto Sell")

    ST:CreateDropdown({
        Name = "Sell Below",
        Options = RARITY_NAMES,
        CurrentOption = {"Common"},
        Callback = function(v) CFG.SellBelow = normalizeOptionValue(v) end,
    })

    ST:CreateButton({
        Name = "Sell Now",
        Callback = function()
            -- SellingFunc is the verified remote for selling
            invokeRF("SellingFunc", CFG.SellBelow)
        end,
    })

    ST:CreateToggle({
        Name = "Auto Sell",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoSell = v
            if v then
                CONNS["AutoSell"] = connectInterval("AutoSell", function()
                    return CFG.AutoSell
                end, 10, function()
                    invokeRF("SellingFunc", CFG.SellBelow)
                end)
            else
                if CONNS["AutoSell"] then CONNS["AutoSell"]:Disconnect(); CONNS["AutoSell"] = nil end
            end
        end,
    })

    ST:CreateSection("Loot Bag")

    ST:CreateDropdown({
        Name = "Sell Rarity",
        Options = {"All", unpack(RARITY_NAMES)},
        CurrentOption = {"Common"},
        Callback = function(v) CFG.SellRarity = normalizeOptionValue(v) end,
    })

    ST:CreateButton({
        Name = "Sell Rarity from Bag",
        Callback = function()
            if CFG.SellRarity == "All" then
                invokeRF("SellingFunc", "All")
            else
                invokeRF("SellingFunc", CFG.SellRarity)
            end
        end,
    })

    ST:CreateButton({
        Name = "Sell All Loot Bag",
        Callback = function()
            invokeRF("SellingFunc", "All")
        end,
    })

    -- ───────── Merchant Tab ─────────
    local MT2 = Window:CreateTab("Merchant", 4483362458)
    MT2:CreateSection("Merchant")

    MT2:CreateDropdown({
        Name = "Item",
        Options = {"Health Potion","Mana Potion","Damage Boost","Shield","Teleport Scroll","Revive Token","Gold Booster","XP Booster"},
        CurrentOption = {"Health Potion"},
        Callback = function(v) CFG.MerchantItem = normalizeOptionValue(v) end,
    })

    MT2:CreateButton({
        Name = "Refresh Stock",
        Callback = function() invokeRF("SellingFunc", "Refresh") end,
    })

    MT2:CreateButton({
        Name = "Buy Selected",
        Callback = function() invokeRF("SellingFunc", "Buy", CFG.MerchantItem) end,
    })

    MT2:CreateSection("Auto Buy")
    MT2:CreateDropdown({
        Name = "Min Rarity",
        Options = RARITY_NAMES,
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoBuyMinRarity = normalizeOptionValue(v) end,
    })

    MT2:CreateToggle({
        Name = "Auto Buy",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoBuy = v
            if v then
                CONNS["AutoBuy"] = connectInterval("AutoBuy", function()
                    return CFG.AutoBuy
                end, 30, function()
                    invokeRF("SellingFunc", "Buy", CFG.AutoBuyMinRarity)
                end)
            else
                if CONNS["AutoBuy"] then CONNS["AutoBuy"]:Disconnect(); CONNS["AutoBuy"] = nil end
            end
        end,
    })

    -- ───────── Store Tab ─────────
    local ST2 = Window:CreateTab("Store", 4483362458)
    ST2:CreateSection("Auto Store")

    ST2:CreateDropdown({
        Name = "Min Rarity",
        Options = RARITY_NAMES,
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoStoreMinRarity = normalizeOptionValue(v) end,
    })

    ST2:CreateButton({
        Name = "Store Now",
        Callback = function()
            -- DepositFunc is the verified remote for storing items
            invokeRF("DepositFunc", CFG.AutoStoreMinRarity)
        end,
    })

    ST2:CreateToggle({
        Name = "Auto Store",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoStore = v
            if v then
                CONNS["AutoStore"] = connectInterval("AutoStore", function()
                    return CFG.AutoStore
                end, 15, function()
                    invokeRF("DepositFunc", CFG.AutoStoreMinRarity)
                end)
            else
                if CONNS["AutoStore"] then CONNS["AutoStore"]:Disconnect(); CONNS["AutoStore"] = nil end
            end
        end,
    })

    ST2:CreateSection("Auto Withdraw")

    ST2:CreateDropdown({
        Name = "Min Rarity",
        Options = RARITY_NAMES,
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoWithdrawMinRarity = normalizeOptionValue(v) end,
    })

    ST2:CreateButton({
        Name = "Withdraw Now",
        Callback = function()
            -- DepositFunc with withdraw action
            invokeRF("DepositFunc", "Withdraw", CFG.AutoWithdrawMinRarity)
        end,
    })

    ST2:CreateButton({
        Name = "Withdraw All",
        Callback = function()
            invokeRF("DepositFunc", "Withdraw", "All")
        end,
    })

    -- ───────── Forge Tab ─────────
    local FT2 = Window:CreateTab("Forge", 4483362458)
    FT2:CreateSection("Forge")

    FT2:CreateDropdown({
        Name = "Item",
        Options = {"Weapon","Armor","Accessory","Material","Gem","Scroll"},
        CurrentOption = {"Weapon"},
        Callback = function(v) CFG.ForgeItem = normalizeOptionValue(v) end,
    })

    FT2:CreateButton({
        Name = "Refresh Items",
        Callback = function() invokeRF("GetBase") end,
    })

    FT2:CreateToggle({
        Name = "Use Protection Scroll",
        CurrentValue = false,
        Callback = function(v) CFG.UseProtectionScroll = v end,
    })

    FT2:CreateToggle({
        Name = "Use Enhance",
        CurrentValue = false,
        Callback = function(v) CFG.UseEnhance = v end,
    })

    FT2:CreateButton({
        Name = "Forge Once",
        Callback = function()
            invokeRF("GetBase", "Forge", CFG.ForgeItem, CFG.UseProtectionScroll)
        end,
    })

    FT2:CreateSection("Auto Forge")

    FT2:CreateDropdown({
        Name = "Min Rarity",
        Options = RARITY_NAMES,
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoForgeMinRarity = normalizeOptionValue(v) end,
    })

    FT2:CreateSlider({
        Name = "Max Forge Level",
        Range = {1, 20}, Increment = 1, Suffix = "",
        CurrentValue = 10,
        Callback = function(v) CFG.AutoForgeMaxLevel = v end,
    })

    FT2:CreateToggle({
        Name = "Auto Forge",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoForge = v
            if v then
                CONNS["AutoForge"] = connectInterval("AutoForge", function()
                    return CFG.AutoForge
                end, 5, function()
                    invokeRF("GetBase", "Forge", CFG.AutoForgeMinRarity)
                end)
            else
                if CONNS["AutoForge"] then CONNS["AutoForge"]:Disconnect(); CONNS["AutoForge"] = nil end
            end
        end,
    })

    -- ───────── Quests Tab ─────────
    local QT2 = Window:CreateTab("Quests", 4483362458)
    QT2:CreateSection("Quests")

    QT2:CreateButton({
        Name = "Claim All Quests",
        Callback = function()
            clickMenuButton("Quests")
            task.wait(0.5)
            claimQuestButtons()
        end,
    })

    QT2:CreateToggle({
        Name = "Auto Claim Quests",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoClaimQuests = v
            if v then
                CONNS["AutoQuests"] = connectInterval("AutoQuests", function()
                    return CFG.AutoClaimQuests
                end, 5, function()
                    clickMenuButton("Quests")
                    task.wait(0.25)
                    claimQuestButtons()
                end)
            else
                if CONNS["AutoQuests"] then CONNS["AutoQuests"]:Disconnect(); CONNS["AutoQuests"] = nil end
            end
        end,
    })

    -- ───────── Webhook Tab ─────────
    local WT = Window:CreateTab("Webhook", 4483362458)
    WT:CreateSection("Webhook Settings")

    WT:CreateInput({
        Name = "Webhook URL",
        PlaceholderText = "https://discord.com/api/webhooks/...",
        RemoveTextAfterFocusLost = false,
        Callback = function(v) CFG.WebhookURL = v end,
    })

    WT:CreateToggle({
        Name = "Loot Webhook",
        CurrentValue = false,
        Callback = function(v)
            CFG.LootWebhook = v
            if v then
                CONNS["LootWebhook"] = connectInterval("LootWebhook", function()
                    return CFG.LootWebhook
                end, 30, function()
                    sendWebhook("Dungeon Lootr", "Auto-farm active | HP: " .. math.floor(getHPPercent()) .. "%", 3066993)
                end)
            else
                if CONNS["LootWebhook"] then CONNS["LootWebhook"]:Disconnect(); CONNS["LootWebhook"] = nil end
            end
        end,
    })

    -- ───────── Settings Tab ─────────
    local ST3 = Window:CreateTab("Settings", 4483362458)
    ST3:CreateSection("Configuration")

    ST3:CreateButton({
        Name = "Rejoin Server",
        Callback = function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
        end,
    })

    ST3:CreateButton({
        Name = "Server Hop",
        Callback = function()
            local ok, servers = pcall(function()
                return HttpService:JSONDecode(
                    game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
                )
            end)
            if ok and servers and servers.data then
                for _, s in ipairs(servers.data) do
                    if s.id ~= game.JobId and s.playing < s.maxPlayers then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LP)
                        break
                    end
                end
            end
        end,
    })

    -- ═══════════════════════════════════════════════════════════════════
    --  MAIN LOOP
    -- ═══════════════════════════════════════════════════════════════════
    CONNS["MainLoop"] = RunService.Heartbeat:Connect(function()
        CFG.InDungeon = isInDungeon()
    end)

    LP.CharacterAdded:Connect(function(char)
        task.wait(1)
        local h = char:FindFirstChildOfClass("Humanoid")
        if h and CFG.Speed then h.WalkSpeed = CFG.SpeedValue end
        if CFG.Fly then startFly() end
    end)

    pcall(function()
        Window:Notify({
            Title = "Dungeon Lootr",
            Content = "v2.0.0 | Verified flat remotes loaded",
            Duration = 5,
        })
    end)
end
