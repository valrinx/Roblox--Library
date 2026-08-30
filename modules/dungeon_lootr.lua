-- ═══════════════════════════════════════════════════════════════════
--   Dungeon Lootr  |  RAVEN HUB Module  |  v1.0.0
--   Live-verified UI paths from Raven MCP inspection
--   PlaceId: 106484206883664  |  GameId: 9656201728
-- ═══════════════════════════════════════════════════════════════════
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TeleportService = game:GetService("TeleportService")
    local VirtualUser = game:GetService("VirtualUser")
    local MarketplaceService = game:GetService("MarketplaceService")
    local HttpService = game:GetService("HttpService")

    local LP = Players.LocalPlayer
    local PG = LP.PlayerGui

    -- ═══════════════════════════════════════════════════════════════════
    --  SETTINGS
    -- ═══════════════════════════════════════════════════════════════════
    local CFG = {
        -- Queue Settings
        Dungeon = "Default",
        Difficulty = "Normal",
        Mode = "Standard",
        StartType = "Auto",

        -- Auto Queue
        AutoQueue = false,
        AutoReplay = false,
        AutoReturn = false,

        -- Mob Farm
        TargetMob = "",
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
        SpeedValue = 24,
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
        MerchantItem = "",
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
        ForgeItem = "",
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
        CurrentWave = 0,
    }

    local CONNS = {}
    local FLAGS = { attacking = false, lastAttack = 0 }

    -- ═══════════════════════════════════════════════════════════════════
    --  REMOTE DISCOVERY (Runtime Scanner)
    -- ═══════════════════════════════════════════════════════════════════
    local RemoteCache = { Events = {}, Functions = {} }

    local function scanRemotes()
        RemoteCache = { Events = {}, Functions = {} }
        -- Scan ReplicatedStorage and descendants
        local roots = { ReplicatedStorage }
        for _, root in ipairs(roots) do
            for _, desc in ipairs(root:GetDescendants()) do
                if desc:IsA("RemoteEvent") then
                    RemoteCache.Events[string.lower(desc.Name)] = desc
                elseif desc:IsA("RemoteFunction") then
                    RemoteCache.Functions[string.lower(desc.Name)] = desc
                end
            end
        end
        -- Also scan workspace for game-specific remotes
        for _, desc in ipairs(workspace:GetDescendants()) do
            if desc:IsA("RemoteEvent") then
                RemoteCache.Events[string.lower(desc.Name)] = desc
            elseif desc:IsA("RemoteFunction") then
                RemoteCache.Functions[string.lower(desc.Name)] = desc
            end
        end
    end
    scanRemotes()

    local function getEvent(name)
        return RemoteCache.Events[string.lower(name)]
    end

    local function getFunc(name)
        return RemoteCache.Functions[string.lower(name)]
    end

    local function fireEvent(name, ...)
        local r = getEvent(name)
        if r then pcall(function() r:FireServer(...) end) end
    end

    local function invokeFunc(name, ...)
        local r = getFunc(name)
        if r then
            local ok, res = pcall(function() return r:InvokeServer(...) end)
            return ok and res or nil
        end
        return nil
    end

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
    -- ═══════════════════════════════════════════════════════════════════
    local function getEnemies()
        local list = {}
        -- Scan common enemy folders
        local folders = { workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Mobs"),
            workspace:FindFirstChild("Monsters"), workspace:FindFirstChild("Dungeon"),
            workspace:FindFirstChild("NPCs") }
        for _, folder in ipairs(folders) do
            if folder then
                for _, obj in ipairs(folder:GetDescendants()) do
                    local hrp = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChild("Torso")
                    local hum = obj:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 and obj ~= LP.Character then
                        table.insert(list, {
                            model = obj, root = hrp, hum = hum,
                            hp = hum.Health, maxHp = hum.MaxHealth, pos = hrp.Position,
                        })
                    end
                end
            end
        end
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
    -- ═══════════════════════════════════════════════════════════════════
    local function isInDungeon()
        -- Check various dungeon indicators
        local indicators = {
            PG:FindFirstChild("DungeonHUD"),
            PG:FindFirstChild("InDungeon"),
            workspace:FindFirstChild("Dungeon"),
            workspace:FindFirstChild("DungeonArena"),
        }
        for _, ind in ipairs(indicators) do
            if ind then return true end
        end
        return false
    end

    local function getDungeonGui()
        return PG:FindFirstChild("Main") and PG.Main:FindFirstChild("HUD")
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  SKILL BAR (Verified: HUD/Actions/Bottom/Actions/1-4)
    -- ═══════════════════════════════════════════════════════════════════
    local function clickSkillSlot(slotNum)
        local hud = getDungeonGui()
        if not hud then return end
        local actions = hud:FindFirstChild("Actions") and hud.Actions:FindFirstChild("Bottom")
            and hud.Actions.Bottom:FindFirstChild("Actions")
        if not actions then return end
        local slot = actions:FindFirstChild(tostring(slotNum))
        if slot and slot:IsA("GuiButton") then
            pcall(function() slot:Activate() end)
        end
    end

    local function isSkillReady(slotNum)
        local hud = getDungeonGui()
        if not hud then return false end
        local actions = hud:FindFirstChild("Actions") and hud.Actions:FindFirstChild("Bottom")
            and hud.Actions.Bottom:FindFirstChild("Actions")
        if not actions then return false end
        local slot = actions:FindFirstChild(tostring(slotNum))
        if not slot then return false end
        -- Check cooldown indicator
        local cd = slot:FindFirstChild("Cooldown") or slot:FindFirstChild("CD")
        if cd and cd:IsA("Frame") then
            return cd.Size.X.Scale < 0.05
        end
        return true
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  UI BUTTON CLICKER (Verified paths from Raven MCP)
    -- ═══════════════════════════════════════════════════════════════════
    local function clickGuiButton(path)
        local ok, obj = pcall(function()
            local parts = string.split(path, "/")
            local node = PG
            for _, part in ipairs(parts) do
                node = node and node:FindFirstChild(part)
            end
            return node
        end)
        if ok and obj and (obj:IsA("TextButton") or obj:IsA("ImageButton")) then
            pcall(function() obj:Activate() end)
            return true
        end
        return false
    end

    local function clickAreaButton(areaName)
        -- Verified: PlayerGui/Areas/<AreaName>/Frame/ImageButton
        return clickGuiButton("Areas/" .. areaName .. "/Frame/ImageButton")
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  AUTO POTION (Verified: HUD/Actions/Bottom/Actions/Health)
    -- ═══════════════════════════════════════════════════════════════════
    local function usePotion()
        local hud = getDungeonGui()
        if not hud then return end
        local actions = hud:FindFirstChild("Actions") and hud.Actions:FindFirstChild("Bottom")
            and hud.Actions.Bottom:FindFirstChild("Actions")
        if not actions then return end
        local healthSlot = actions:FindFirstChild("Health")
        if healthSlot and healthSlot:IsA("GuiButton") then
            pcall(function() healthSlot:Activate() end)
        end
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  SHOP / SELL / INVENTORY (Verified: Left/Buttons)
    -- ═══════════════════════════════════════════════════════════════════
    local function openShop()
        clickAreaButton("Play")
        task.wait(0.3)
        clickGuiButton("Main/HUD/Actions/Left/Buttons/Shop")
    end

    local function openInventory()
        clickGuiButton("Main/HUD/Actions/Left/Buttons/Inventory")
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
            -- Use syn_request or http_request if available
            if syn and syn.request then
                syn.request({ Url = CFG.WebhookURL, Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode(payload) })
            elseif http_request then
                http_request({ Url = CFG.WebhookURL, Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode(payload) })
            end
        end)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  RARITY HELPERS
    -- ═══════════════════════════════════════════════════════════════════
    local RARITY_ORDER = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }

    local function isRarityAbove(itemRarity, minRarity)
        return (RARITY_ORDER[itemRarity] or 0) >= (RARITY_ORDER[minRarity] or 0)
    end

    -- ═══════════════════════════════════════════════════════════════════
    --  UI
    -- ═══════════════════════════════════════════════════════════════════

    -- ───────── Queue Tab ─────────
    local QT = Window:CreateTab("Queue", 4483362458)
    QT:CreateSection("Queue Settings")

    QT:CreateDropdown({
        Name = "Dungeon",
        Options = {"Default","Forest","Desert","Ice","Volcano","Shadow","Crystal","Void","Inferno","Ancient"},
        CurrentOption = {"Default"},
        Callback = function(v) CFG.Dungeon = v end,
    })

    QT:CreateDropdown({
        Name = "Difficulty",
        Options = {"Normal","Hard","Nightmare","Infernal","Mythic"},
        CurrentOption = {"Normal"},
        Callback = function(v) CFG.Difficulty = v end,
    })

    QT:CreateDropdown({
        Name = "Mode",
        Options = {"Standard","Boss Rush","Challenge","Endless"},
        CurrentOption = {"Standard"},
        Callback = function(v) CFG.Mode = v end,
    })

    QT:CreateDropdown({
        Name = "Start Type",
        Options = {"Auto","Manual"},
        CurrentOption = {"Auto"},
        Callback = function(v) CFG.StartType = v end,
    })

    QT:CreateSection("Automation")

    QT:CreateToggle({
        Name = "Auto Queue",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoQueue = v
            if v then
                CONNS["AutoQueue"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoQueue then return end
                    if not CFG.AutoReplay and isInDungeon() then return end
                    -- Try to find and click queue/play buttons
                    fireEvent("queueDungeon", CFG.Dungeon, CFG.Difficulty, CFG.Mode)
                    task.wait(2)
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
                CONNS["AutoReplay"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoReplay then return end
                    -- Look for replay/continue buttons
                    local replayGui = PG:FindFirstChild("ReplayGui") or PG:FindFirstChild("ResultGui")
                    if replayGui then
                        local btn = replayGui:FindFirstChild("ReplayButton") or replayGui:FindFirstChild("Continue")
                        if btn then pcall(function() btn:Activate() end) end
                    end
                    fireEvent("replayDungeon")
                    fireEvent("continueDungeon")
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
                CONNS["AutoReturn"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoReturn then return end
                    if not isInDungeon() then return end
                    fireEvent("returnToLobby")
                    fireEvent("leaveDungeon")
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
                CONNS["KillAura"] = RunService.Heartbeat:Connect(function()
                    if not CFG.KillAura or not isAlive() or FLAGS.attacking then return end
                    local my = getRoot()
                    if not my then return end
                    local enemies = getEnemies()
                    if #enemies == 0 then return end
                    -- Sort by distance
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
                            -- Click attack/skill slot 1
                            clickSkillSlot(1)
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
                CONNS["AutoSkills"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoSkills or not CFG.AutoSkillsToggle or not isAlive() then return end
                    -- Try all 4 skill slots
                    for slot = 1, 4 do
                        if isSkillReady(slot) then
                            clickSkillSlot(slot)
                            task.wait(randDelay(0.1, 0.15))
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

    -- ───────── Farm Config Tab ─────────
    local FT = Window:CreateTab("Farm", 4483362458)
    FT:CreateSection("Mob Farm")

    FT:CreateToggle({
        Name = "Farm Mobs",
        CurrentValue = false,
        Callback = function(v)
            CFG.FarmMobs = v
            if v then
                CONNS["FarmMobs"] = RunService.Heartbeat:Connect(function()
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
                        clickSkillSlot(1)
                    end
                end)
            else
                if CONNS["FarmMobs"] then CONNS["FarmMobs"]:Disconnect(); CONNS["FarmMobs"] = nil end
            end
        end,
    })

    FT:CreateDropdown({
        Name = "Target Mob",
        Options = {"Any","Closest","Boss","Elite","Minion"},
        CurrentOption = {"Closest"},
        Callback = function(v) CFG.TargetMob = v end,
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
                CONNS["AutoPotion"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoPotion or not isAlive() then return end
                    if getHPPercent() <= CFG.UseAtHpPercent then
                        usePotion()
                        task.wait(1)
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
        Name = "Auto Select Chests",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoSelectChests = v
            if v then
                CONNS["AutoChests"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoSelectChests then return end
                    -- Scan for chest UIs and click them
                    for _, desc in ipairs(PG:GetDescendants()) do
                        if desc:IsA("GuiButton") and (
                            string.find(string.lower(desc.Name), "chest") or
                            string.find(string.lower(desc.Name), "select") or
                            string.find(string.lower(desc.Name), "claim")
                        ) then
                            pcall(function() desc:Activate() end)
                        end
                    end
                end)
            else
                if CONNS["AutoChests"] then CONNS["AutoChests"]:Disconnect(); CONNS["AutoChests"] = nil end
            end
        end,
    })

    FT:CreateToggle({
        Name = "Auto Mid-Run Chests",
        CurrentValue = false,
        Callback = function(v) CFG.AutoMidRunChests = v end,
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
                if h then h.WalkSpeed = 16 end
            end
        end,
    })

    MT:CreateSlider({
        Name = "Speed Value",
        Range = {16, 200}, Increment = 1, Suffix = " studs/s",
        CurrentValue = 24,
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

    -- ───────── Player Misc Tab ─────────
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
        Options = {"Common","Uncommon","Rare","Epic","Legendary","Mythic"},
        CurrentOption = {"Common"},
        Callback = function(v) CFG.SellBelow = v end,
    })

    ST:CreateButton({
        Name = "Sell Now",
        Callback = function()
            fireEvent("sellItems", CFG.SellBelow)
            openShop()
            task.wait(1)
        end,
    })

    ST:CreateToggle({
        Name = "Auto Sell",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoSell = v
            if v then
                CONNS["AutoSell"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoSell then return end
                    task.wait(10)
                    fireEvent("sellItems", CFG.SellBelow)
                end)
            else
                if CONNS["AutoSell"] then CONNS["AutoSell"]:Disconnect(); CONNS["AutoSell"] = nil end
            end
        end,
    })

    ST:CreateSection("Loot Bag")

    ST:CreateDropdown({
        Name = "Sell Rarity",
        Options = {"Common","Uncommon","Rare","Epic","Legendary","Mythic","All"},
        CurrentOption = {"Common"},
        Callback = function(v) CFG.SellRarity = v end,
    })

    ST:CreateButton({
        Name = "Sell Rarity from Bag",
        Callback = function() fireEvent("sellLootBag", CFG.SellRarity) end,
    })

    ST:CreateButton({
        Name = "Sell All Loot Bag",
        Callback = function() fireEvent("sellAllLootBag") end,
    })

    -- ───────── Merchant Tab ─────────
    local MT2 = Window:CreateTab("Merchant", 4483362458)
    MT2:CreateSection("Merchant")

    MT2:CreateDropdown({
        Name = "Item",
        Options = {"Health Potion","Mana Potion","Damage Boost","Shield","Teleport Scroll","Revive Token","Gold Booster","XP Booster"},
        CurrentOption = {"Health Potion"},
        Callback = function(v) CFG.MerchantItem = v end,
    })

    MT2:CreateButton({
        Name = "Refresh Stock",
        Callback = function() fireEvent("refreshMerchant") end,
    })

    MT2:CreateButton({
        Name = "Buy Selected",
        Callback = function() fireEvent("buyMerchant", CFG.MerchantItem) end,
    })

    MT2:CreateSection("Auto Buy")
    MT2:CreateDropdown({
        Name = "Min Rarity",
        Options = {"Common","Uncommon","Rare","Epic","Legendary","Mythic"},
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoBuyMinRarity = v end,
    })

    MT2:CreateToggle({
        Name = "Auto Buy",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoBuy = v
            if v then
                CONNS["AutoBuy"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoBuy then return end
                    task.wait(30)
                    fireEvent("autoBuyMerchant", CFG.AutoBuyMinRarity)
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
        Options = {"Common","Uncommon","Rare","Epic","Legendary","Mythic"},
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoStoreMinRarity = v end,
    })

    ST2:CreateButton({
        Name = "Store Now",
        Callback = function() fireEvent("storeItems", CFG.AutoStoreMinRarity) end,
    })

    ST2:CreateToggle({
        Name = "Auto Store",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoStore = v
            if v then
                CONNS["AutoStore"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoStore then return end
                    task.wait(15)
                    fireEvent("storeItems", CFG.AutoStoreMinRarity)
                end)
            else
                if CONNS["AutoStore"] then CONNS["AutoStore"]:Disconnect(); CONNS["AutoStore"] = nil end
            end
        end,
    })

    ST2:CreateSection("Auto Withdraw")

    ST2:CreateDropdown({
        Name = "Min Rarity",
        Options = {"Common","Uncommon","Rare","Epic","Legendary","Mythic"},
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoWithdrawMinRarity = v end,
    })

    ST2:CreateButton({
        Name = "Withdraw Now",
        Callback = function() fireEvent("withdrawItems", CFG.AutoWithdrawMinRarity) end,
    })

    ST2:CreateButton({
        Name = "Withdraw All",
        Callback = function() fireEvent("withdrawAll") end,
    })

    -- ───────── Forge Tab ─────────
    local FT2 = Window:CreateTab("Forge", 4483362458)
    FT2:CreateSection("Forge")

    FT2:CreateDropdown({
        Name = "Item",
        Options = {"Weapon","Armor","Accessory","Material","Gem","Scroll"},
        CurrentOption = {"Weapon"},
        Callback = function(v) CFG.ForgeItem = v end,
    })

    FT2:CreateButton({
        Name = "Refresh Items",
        Callback = function() fireEvent("refreshForge") end,
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
            fireEvent("forgeItem", CFG.ForgeItem, CFG.UseProtectionScroll, CFG.UseEnhance)
        end,
    })

    FT2:CreateSection("Auto Forge")

    FT2:CreateDropdown({
        Name = "Min Rarity",
        Options = {"Common","Uncommon","Rare","Epic","Legendary","Mythic"},
        CurrentOption = {"Common"},
        Callback = function(v) CFG.AutoForgeMinRarity = v end,
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
                CONNS["AutoForge"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoForge then return end
                    task.wait(5)
                    fireEvent("autoForge", CFG.AutoForgeMinRarity, CFG.AutoForgeMaxLevel)
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
        Callback = function() fireEvent("claimAllQuests") end,
    })

    QT2:CreateToggle({
        Name = "Auto Claim Quests",
        CurrentValue = false,
        Callback = function(v)
            CFG.AutoClaimQuests = v
            if v then
                CONNS["AutoQuests"] = RunService.Heartbeat:Connect(function()
                    if not CFG.AutoClaimQuests then return end
                    task.wait(5)
                    fireEvent("claimAllQuests")
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
                CONNS["LootWebhook"] = RunService.Heartbeat:Connect(function()
                    if not CFG.LootWebhook then return end
                    task.wait(30)
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
        Name = "Rescan Remotes",
        Callback = function()
            scanRemotes()
            local count = 0
            for _ in pairs(RemoteCache.Events) do count = count + 1 end
            for _ in pairs(RemoteCache.Functions) do count = count + 1 end
            pcall(function()
                Window:Notify({Title = "Remote Scan", Content = "Found " .. count .. " remotes", Duration = 3})
            end)
        end,
    })

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

    -- Character respawn handler
    LP.CharacterAdded:Connect(function(char)
        task.wait(1)
        local h = char:FindFirstChildOfClass("Humanoid")
        if h and CFG.Speed then h.WalkSpeed = CFG.SpeedValue end
        if CFG.Fly then startFly() end
    end)

    -- Initial notification
    pcall(function()
        Window:Notify({
            Title = "Dungeon Lootr",
            Content = "Module loaded! v1.0.0 | Rescan Remotes in Settings tab",
            Duration = 5,
        })
    end)
end
