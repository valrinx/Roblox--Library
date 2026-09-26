--[[
    RAVEN HUB Module - Ouwland (Project Slayer 2)
    Game: Ouwland (PlaceId: 136406881576517, UniverseId: 5595353122)
    Version: v2.0.0
    Build: 100% Native Architecture (Keyless / Anti-Detection / Zero Bugs)

    Integrated Systems & Features:
    - 🏋️ Auto Training & Minigames (Squat Rack, Pushups, Meditation, Boulder Push, Boulder Split, Cup Game, Aim Training)
    - ⚔️ Combat & Auto Attack (CU.Combat Punch, Combat_presets Fast Attack, Auto Skills, Kill Aura, Hitbox Expander, God Mode)
    - 🌾 Automation & Farming (Auto Farm Mobs, Auto Boss Target Farm, Auto Quest Level Ladder, Auto Fishing Loop, Auto Dungeon)
    - 🏃 Character & Movement Buffs (No Dash CD, No Stamina Dash, No Drown Underwater, Infinite Stamina, Noclip, Fly, Speed/Jump)
    - 🐎 Mounts & Economy (Auto Tame Wild Horses, Infinite Horse Stamina, Black Market Sniper, Auto Gear/Weapon Equip)
    - 👁️ 100% Drawing Visuals (Mobs, Bosses, Players + Clan, Chests, Shrines, Muzan, Spider Lily, Wild Horses)
    - 🛡️ Safety & Mod Detector (Auto Kick on Staff Join, Boss Spawn Sound & Notification, Anti-AFK)
    - 📍 Teleports (All Towns, NPCs, Shrines, Puzzles, Training Spots, Active Boss Locations)
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local TweenService = game:GetService("TweenService")
    local VirtualUser = game:GetService("VirtualUser")

    local LP = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera

    -- Teardown previous instance if running
    pcall(function()
        local prev = getgenv().__RAVEN_OUWLAND
        if prev and type(prev.Destroy) == "function" then
            prev.Destroy()
        end
    end)

    local isDestroyed = false
    local Connections = {}
    local DrawingObjects = {
        Mobs = {},
        Players = {},
        Chests = {},
        Puzzles = {},
        Special = {},
    }

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

    local function connect(signal, fn)
        local conn = signal:Connect(fn)
        table.insert(Connections, conn)
        return conn
    end

    local currentFarmLockCF = nil

    ----------------------------------------------------------------
    --  STATE & CONFIGURATION
    ----------------------------------------------------------------
    local State = {
        -- Combat & Attack
        FastAttack = true,
        AutoAttack = false,
        AutoSkill = false,
        KillAura = false,
        KillAuraRadius = 22,
        KillAuraSnap = true,
        HitboxExpander = false,
        HitboxSize = 10,
        GodMode = false,
        GodModeThreshold = 50,
        EquipBestWeapon = true,
        HitMethod = "Game Punch", -- "Game Punch", "Weapon", "Virtual Input"

        -- Mob & Boss Farming (TerdsakHUB Exact Hover System)
        AutoFarmMobs = false,
        FarmTarget = "All Mobs", -- "All Mobs", "Bandits", "Bears", "Demons", "Lancers", "Slayers", "Kaiden", "Civilian", "Snow Demons", "Yeti", "Bosses"
        FarmMode = "Above (Hover)", -- "Above (Hover)", "Behind (Backstab)", "Underground"
        HoverHeight = 5.0,
        HoverSideOffset = 1.0,
        UndergroundDepth = 2.4,
        AutoBoss = false,
        BossTarget = "All", -- "All", "Zuko", "Hoyuzo", "Sabito", "Giyen", "Enru", "Datai", "Gyutai", "Reaper", "Sumari", "Saneri"

        -- Auto Quest Progression
        AutoQuest = false,
        AutoQuestMode = "Auto Level", -- "Auto Level", "Bandits", "Bears", "Kaiden", "Hoyuzo", "Guards"

        -- Survival & Farm Utilities
        AutoPotion = false,
        PotionThreshold = 50,
        TPBackOnDeath = true,
        AntiAFK = true,

        -- Auto Fishing Loop
        AutoFish = false,
        AutoBuyBait = true,
        AutoSellFish = true,
        FishSellCap = 10,
        FishStatus = "Idle",

        -- Auto Training
        AutoTraining = false,
        AutoSquat = true,
        AutoPushups = true,
        AutoMeditation = true,
        AutoBoulderPush = true,
        AutoBoulderSplit = true,
        AutoCupGame = true,
        AutoTargetShooting = true,

        -- World & Loot
        AutoChests = false,
        ChestFarmRadius = 500,

        -- Character & Movement Modifications
        NoDashCooldown = true,
        NoStaminaDash = true,
        NoDrown = true,
        InfiniteStamina = true,
        SunDamageImmunity = true,
        AntiRagdoll = true,
        InstantPrompt = true,
        CustomWalkSpeed = false,
        WalkSpeed = 28,
        CustomJumpPower = false,
        JumpPower = 65,
        InfiniteJump = false,
        Noclip = false,
        Fly = false,
        FlySpeed = 60,

        -- Horse System
        AutoTameHorse = false,
        InfiniteHorseStamina = true,

        -- Safety & Utilities
        ModDetector = false,
        ModAction = "Kick", -- "Kick", "Notify"
        BossNotifier = true,
        TPBackOnDeath = false,
        BlackMarketSniper = false,

        -- Visuals (100% Drawing ESP)
        ESPMobs = true,
        ESPPlayers = true,
        ESPChests = true,
        ESPPuzzles = true,
        ESPSpecial = true, -- Muzan, Spider Lily, Wild Horses
        MaxESPDistance = 1500,

        -- Teleport Stabilization
        TweenTeleport = false,
        TweenSpeed = 200,
    }

    ----------------------------------------------------------------
    --  HELPER GETTERS
    ----------------------------------------------------------------
    local function getChar()
        return LP.Character
    end

    local function getRoot()
        local c = getChar()
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function getHumanoid()
        local c = getChar()
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function isAlive()
        local hum = getHumanoid()
        return hum and hum.Health > 0
    end

    local function triggerPrompt(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then return end
        pcall(function()
            if State.InstantPrompt then
                prompt.HoldDuration = 0
            end
            if type(fireproximityprompt) == "function" then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait(0.04)
                prompt:InputHoldEnd()
            end
        end)
    end

    ----------------------------------------------------------------
    --  GAME ENGINE SUBSETS & CONTROLLERS
    ----------------------------------------------------------------
    local Utility = nil
    pcall(function()
        Utility = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Global"):WaitForChild("Utility"))
    end)

    local SignalEvent = nil
    pcall(function()
        SignalEvent = require(ReplicatedStorage:WaitForChild("Communication"):WaitForChild("ServerAndClient"):WaitForChild("Signals"):WaitForChild("SignalEvent"))
    end)

    local SignalFunction = nil
    pcall(function()
        SignalFunction = require(ReplicatedStorage:WaitForChild("Communication"):WaitForChild("ServerAndClient"):WaitForChild("Signals"):WaitForChild("SignalFunction"))
    end)

    local InputHandler = nil
    pcall(function()
        InputHandler = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Client"):WaitForChild("Components"):WaitForChild("Client"):WaitForChild("InputHandler"))
    end)

    local CombatPresets = nil
    pcall(function()
        CombatPresets = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Global"):WaitForChild("Combat_presets"))
    end)

    local ManageCd = nil
    pcall(function()
        ManageCd = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Global"):WaitForChild("Subsets"):WaitForChild("Gameplay"):WaitForChild("manage_cd"))
    end)

    local MinigameSettings = nil
    pcall(function()
        MinigameSettings = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Global"):WaitForChild("MinigameSettings"))
    end)

    local QuestsModule = nil
    pcall(function()
        QuestsModule = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Global"):WaitForChild("Subsets"):WaitForChild("Gameplay"):WaitForChild("Quests"))
    end)

    local SkillController = nil
    pcall(function()
        SkillController = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Client"):WaitForChild("Controllers"):WaitForChild("Skill_Controller"))
    end)

    ----------------------------------------------------------------
    --  CORE ENGINE HOOKS (ZERO COOLDOWN, DROWN IMMUNITY, STAMINA)
    ----------------------------------------------------------------
    local originalSetCd = nil
    local originalFetchCd = nil
    if ManageCd and type(ManageCd.set_skill_cd) == "function" then
        originalSetCd = ManageCd.set_skill_cd
        originalFetchCd = ManageCd.fetch

        ManageCd.set_skill_cd = function(player, skill, duration, ...)
            if State.NoDashCooldown and (skill == "Dash" or skill == "Double_Jump") then
                return originalSetCd(player, skill, 0, ...)
            end
            return originalSetCd(player, skill, duration, ...)
        end

        ManageCd.fetch = function(player, skill, ...)
            if State.NoDashCooldown and (skill == "Dash" or skill == "Double_Jump") then
                return 0
            end
            return originalFetchCd(player, skill, ...)
        end
    end

    local originalMinigameGet = nil
    if MinigameSettings and type(MinigameSettings.Get) == "function" then
        originalMinigameGet = MinigameSettings.Get
        MinigameSettings.Get = function(settingName, ...)
            if State.NoDrown and settingName == "NoDrowning" then
                return true
            end
            return originalMinigameGet(settingName, ...)
        end
    end

    -- Fast Attack speed controller via CombatPresets
    local originalPresetDefaults = {}
    local function setFastAttackMode(enabled)
        if not CombatPresets or not CombatPresets.Presets then return end
        for name, preset in pairs(CombatPresets.Presets) do
            if enabled then
                if not originalPresetDefaults[name] then
                    originalPresetDefaults[name] = {default = preset.default, final = preset.final}
                end
                preset.default = 0.10
                preset.final = 0.18
            elseif originalPresetDefaults[name] then
                preset.default = originalPresetDefaults[name].default
                preset.final = originalPresetDefaults[name].final
            end
        end
    end

    setFastAttackMode(true)

    ----------------------------------------------------------------
    --  COMBAT EXECUTION
    ----------------------------------------------------------------
    local cachedPunch = nil
    local function getPunchFunc()
        if cachedPunch then return cachedPunch end
        pcall(function()
            for _, v in ipairs(getgc()) do
                if type(v) == "function" and not isexecutorclosure(v) then
                    local info = debug.getinfo(v)
                    if info.name == "punch" and string.find(tostring(info.source), "CU.Combat") then
                        cachedPunch = v
                        break
                    end
                end
            end
        end)
        return cachedPunch
    end

    local function doPunch()
        local p = getPunchFunc()
        if p then
            local success, cd = pcall(p)
            if success and type(cd) == "number" then
                return cd
            end
        end

        if InputHandler then
            pcall(function()
                InputHandler.VirtualPress("Combat")
                task.delay(0.02, function()
                    pcall(function()
                        InputHandler.VirtualRelease("Combat")
                    end)
                end)
            end)
            return 0.22
        end

        return 0.26
    end

    local lastSkillTime = 0
    local function doAutoSkills()
        if not State.AutoSkill then return end
        local now = os.clock()
        if now - lastSkillTime < 0.6 then return end

        pcall(function()
            -- Attempt skill activations (1-5, Z, X, C, V)
            for _, skillName in ipairs({"1", "2", "3", "4", "5"}) do
                if SkillController and SkillController.Attempt_Hold then
                    local executed = SkillController.Attempt_Hold(skillName)
                    if executed then
                        task.delay(0.08, function()
                            pcall(SkillController.StopHold, skillName)
                        end)
                        lastSkillTime = now
                        break
                    end
                end
            end
        end)
    end

    -- Hitbox Expander for Enemies (Safe NPC parts only)
    local originalSizes = {}
    local function applyHitboxExpander()
        if not State.HitboxExpander then return end
        local humanoidsFolder = Workspace:FindFirstChild("Humanoids")
        if not humanoidsFolder then return end

        local regions = humanoidsFolder:FindFirstChild("Regions")
        if not regions then return end

        for _, region in ipairs(regions:GetChildren()) do
            local activeNpcs = region:FindFirstChild("ActiveNpcs")
            if activeNpcs then
                for _, category in ipairs(activeNpcs:GetChildren()) do
                    for _, npc in ipairs(category:GetChildren()) do
                        if npc:IsA("Model") and npc ~= getChar() then
                            local hrp = npc:FindFirstChild("HumanoidRootPart")
                            if hrp and hrp:IsA("BasePart") then
                                if not originalSizes[hrp] then
                                    originalSizes[hrp] = hrp.Size
                                end
                                hrp.Size = Vector3.new(State.HitboxSize, State.HitboxSize, State.HitboxSize)
                                hrp.Transparency = 0.7
                                hrp.CanCollide = false
                            end
                        end
                    end
                end
            end
        end
    end

    local function restoreHitboxes()
        for part, origSize in pairs(originalSizes) do
            pcall(function()
                if part and part.Parent then
                    part.Size = origSize
                    part.Transparency = 1
                end
            end)
        end
        table.clear(originalSizes)
    end

    ----------------------------------------------------------------
    --  MOB & BOSS SCANNING
    ----------------------------------------------------------------
    local function getActiveEnemies()
        local enemies = {}
        local humanoidsFolder = Workspace:FindFirstChild("Humanoids")
        if not humanoidsFolder then return enemies end

        local regions = humanoidsFolder:FindFirstChild("Regions")
        if not regions then return enemies end

        for _, region in ipairs(regions:GetChildren()) do
            local activeNpcs = region:FindFirstChild("ActiveNpcs")
            if activeNpcs then
                for _, category in ipairs(activeNpcs:GetChildren()) do
                    for _, npc in ipairs(category:GetChildren()) do
                        if npc:IsA("Model") and npc ~= getChar() then
                            local hum = npc:FindFirstChildOfClass("Humanoid")
                            local hrp = npc:FindFirstChild("HumanoidRootPart")
                            if hum and hum.Health > 0 and hrp then
                                local isBoss = (region.Name == "Misc") or (
                                    npc.Name:find("Datai") or npc.Name:find("Gyutai") or
                                    npc.Name:find("Reaper") or npc.Name:find("Sumari") or
                                    npc.Name:find("Saneri") or npc.Name:find("Zuko") or
                                    npc.Name:find("Hoyuzo") or npc.Name:find("Sabito") or
                                    npc.Name:find("Giyen") or npc.Name:find("Enru")
                                )
                                table.insert(enemies, {
                                    Model = npc,
                                    Humanoid = hum,
                                    Root = hrp,
                                    Name = npc.Name,
                                    Region = region.Name,
                                    IsBoss = isBoss,
                                })
                            end
                        end
                    end
                end
            end
        end
        return enemies
    end

    local function getEquippedWeapon()
        local char = getChar()
        if not char then return nil end
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Tool") and not child.Name:find("Rod") and not child.Name:find("Bait") and not child.Name:find("Potion") then
                return child
            end
        end
        return nil
    end

    local function equipBestWeapon()
        local hum = getHumanoid()
        if not hum then return end
        if getEquippedWeapon() then return end
        local bp = LP:FindFirstChild("Backpack")
        if bp then
            for _, tool in ipairs(bp:GetChildren()) do
                if tool:IsA("Tool") and not tool.Name:find("Rod") and not tool.Name:find("Bait") and not tool.Name:find("Potion") then
                    pcall(function() hum:EquipTool(tool) end)
                    break
                end
            end
        end
    end

    local lastPotionUse = 0
    local function usePotion()
        local now = os.clock()
        if now - lastPotionUse < 2.0 then return end
        lastPotionUse = now
        pcall(function()
            local bp = LP:FindFirstChild("Backpack")
            local pot = nil
            if bp then
                for _, item in ipairs(bp:GetChildren()) do
                    if item:IsA("Tool") and (item.Name:find("Potion") or item.Name:find("Gourd") or item.Name:find("Heal") or item.Name:find("Bandage") or item.Name:find("Food")) then
                        pot = item
                        break
                    end
                end
            end
            if pot then
                local hum = getHumanoid()
                if hum then
                    hum:EquipTool(pot)
                    task.wait(0.08)
                    pot:Activate()
                end
            end
        end)
    end

    local function getQuestMobKeyword(questName)
        if not questName then return nil end
        local lower = questName:lower()
        if lower:find("bandit") then return "Bandit"
        elseif lower:find("bear") then return "Bear"
        elseif lower:find("hoyuzo") then return "Hoyuzo"
        elseif lower:find("kaiden") then return "Kaiden"
        elseif lower:find("guard") then return "Guard"
        elseif lower:find("subordinate") then return "Slayer"
        elseif lower:find("demon") then return "Demon"
        elseif lower:find("frost") then return "Snow"
        end
        return nil
    end

    local function getClosestEnemy(overrideKeyword)
        local root = getRoot()
        if not root then return nil end

        local enemies = getActiveEnemies()
        local closest = nil
        local minDist = math.huge

        for _, enemy in ipairs(enemies) do
            local passTarget = true

            if overrideKeyword then
                if not enemy.Name:find(overrideKeyword) then passTarget = false end
            elseif State.FarmTarget == "Bosses" or State.AutoBoss then
                if not enemy.IsBoss then passTarget = false end
                if State.AutoBoss and State.BossTarget ~= "All" then
                    if not enemy.Name:find(State.BossTarget) then passTarget = false end
                end
            elseif State.FarmTarget == "Bandits" then
                if not enemy.Name:find("Bandit") then passTarget = false end
            elseif State.FarmTarget == "Bears" then
                if not enemy.Name:find("Bear") then passTarget = false end
            elseif State.FarmTarget == "Demons" then
                if not (enemy.Name:find("Demon") or enemy.Region == "Windy Peak") then passTarget = false end
            elseif State.FarmTarget == "Lancers" then
                if not enemy.Name:find("Lancer") then passTarget = false end
            elseif State.FarmTarget == "Slayers" then
                if not enemy.Name:find("Slayer") then passTarget = false end
            elseif State.FarmTarget == "Kaiden" then
                if not enemy.Name:find("Kaiden") then passTarget = false end
            elseif State.FarmTarget == "Snow Demons" then
                if not enemy.Name:find("Snow") then passTarget = false end
            elseif State.FarmTarget == "Yeti" then
                if not enemy.Name:find("Yeti") then passTarget = false end
            elseif State.FarmTarget == "Civilian" then
                if not enemy.Name:find("Civilian") then passTarget = false end
            end

            if passTarget and enemy.Root and enemy.Humanoid.Health > 0 then
                local dist = (root.Position - enemy.Root.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    closest = enemy
                end
            end
        end

        return closest
    end

    ----------------------------------------------------------------
    --  TELEPORT ENGINE (SMOOTH GLIDE OR ROCK-SOLID SNAP)
    ----------------------------------------------------------------
    local isTeleporting = false
    local function teleportTo(targetCF)
        local root = getRoot()
        local hum = getHumanoid()
        if not root or not targetCF then return end

        local destCF = (typeof(targetCF) == "CFrame" and targetCF or targetCF.CFrame) + Vector3.new(0, 2.5, 0)
        if isTeleporting then return end
        isTeleporting = true

        pcall(function()
            local char = getChar()
            if State.TweenTeleport then
                local dist = (root.Position - destCF.Position).Magnitude
                local duration = math.clamp(dist / math.max(State.TweenSpeed or 200, 50), 0.2, 5.0)

                local tweenConn = RunService.Stepped:Connect(function()
                    if char then
                        for _, part in ipairs(char:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.CanCollide = false
                            end
                        end
                    end
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)

                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Physics)
                end

                local tween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = destCF})
                tween:Play()
                tween.Completed:Wait()

                if tweenConn then tweenConn:Disconnect() end
                root.CFrame = destCF
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero

                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                end
            else
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero

                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Physics)
                end

                root.CFrame = destCF
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero

                for _ = 1, 3 do
                    task.wait(0.04)
                    root.CFrame = destCF
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end

                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Running)
                end
            end
        end)

        isTeleporting = false
    end

    ----------------------------------------------------------------
    --  AUTO QUEST ENGINE (LEVEL LADDER & AUTO COMPLETION)
    ----------------------------------------------------------------
    local function getPlayerLevel()
        local lv = 1
        pcall(function()
            local pg = LP:FindFirstChild("PlayerGui")
            local expLabel = pg and pg:FindFirstChild("ComponentsHolder") and pg.ComponentsHolder:FindFirstChild("LeftCenterFramesHolder")
            -- Check Character attributes
            local char = getChar()
            if char and char:GetAttribute("Level") then
                lv = tonumber(char:GetAttribute("Level")) or lv
            end
        end)
        return lv
    end

    local function getBestQuestName()
        if State.AutoQuestMode ~= "Auto Level" then
            if State.AutoQuestMode == "Bandits" then return "Ill take 3 bandits"
            elseif State.AutoQuestMode == "Bears" then return "Ill drive the bears back(Lv 10)"
            elseif State.AutoQuestMode == "Kaiden" then return "Ill deal with Kaiden(Lv 34)"
            elseif State.AutoQuestMode == "Hoyuzo" then return "I will take care of Hoyuzo(Lv 50)"
            elseif State.AutoQuestMode == "Guards" then return "I will clear out his guards(Lv 40)"
            end
        end

        local lv = getPlayerLevel()
        local ladder = {
            {Lv = 125, Name = "Ill haul in the deep catch(Lv 125)"},
            {Lv = 115, Name = "Ill put out the blaze(Lv 115)"},
            {Lv = 105, Name = "Ill drive back the frost(Lv 105)"},
            {Lv = 90,  Name = "Ill help you defeat them(Lv 90)"},
            {Lv = 75,  Name = "Ill thin them out(Lv 75)"},
            {Lv = 62,  Name = "Ill clear the cave(Lv 62)"},
            {Lv = 50,  Name = "I will take care of Hoyuzo(Lv 50)"},
            {Lv = 40,  Name = "I will clear out his guards(Lv 40)"},
            {Lv = 26,  Name = "Ill clear out his subordinates(Lv 26)"},
            {Lv = 10,  Name = "Ill drive the bears back(Lv 10)"},
            {Lv = 1,   Name = "Ill take 3 bandits"},
        }

        for _, item in ipairs(ladder) do
            if lv >= item.Lv then
                return item.Name
            end
        end
        return "Ill take 3 bandits"
    end

    local function handleAutoQuest()
        if not State.AutoQuest or not isAlive() then return end
        pcall(function()
            local questName = getBestQuestName()
            if SignalEvent and SignalEvent.ToServer then
                SignalEvent.ToServer("Quest", "Accept", questName)
            end
        end)
    end

    ----------------------------------------------------------------
    --  AUTO FISHING LOOP (JESO -> DOCK -> GINZO)
    ----------------------------------------------------------------
    local FISHING_DOCK = CFrame.new(890.3, 1055.4, -610.2)
    local GINZO_POS = CFrame.new(875.2, 1056.1, -625.4)

    local function runAutoFishingStep()
        if not State.AutoFish or not isAlive() then return end
        pcall(function()
            local root = getRoot()
            if not root then return end

            -- 1. Ensure equipped rod
            local char = getChar()
            local rod = char and (char:FindFirstChild("Rare Fishing Rod") or char:FindFirstChild("Basic Fishing Rod") or char:FindFirstChild("Legendary Fishing Rod"))
            if not rod then
                local bp = LP:FindFirstChild("Backpack")
                rod = bp and (bp:FindFirstChild("Rare Fishing Rod") or bp:FindFirstChild("Basic Fishing Rod") or bp:FindFirstChild("Legendary Fishing Rod"))
                if rod then
                    getHumanoid():EquipTool(rod)
                    task.wait(0.2)
                else
                    State.FishStatus = "Buying Rod from Jeso..."
                    teleportTo(FISHING_DOCK)
                    return
                end
            end

            -- 2. Teleport to fishing dock
            if (root.Position - FISHING_DOCK.Position).Magnitude > 20 then
                State.FishStatus = "Moving to Dock..."
                teleportTo(FISHING_DOCK)
                task.wait(0.8)
                return
            end

            -- 3. Cast and Reel
            State.FishStatus = "Fishing at Dock..."
            if rod and rod:IsA("Tool") then
                rod:Activate()
                task.wait(1.5)
                if SignalEvent and SignalEvent.ToServer then
                    SignalEvent.ToServer("Fishing", "Reel")
                end
            end
        end)
    end

    ----------------------------------------------------------------
    --  HORSE AUTO TAME & INFINITE STAMINA
    ----------------------------------------------------------------
    local function handleHorseAutomation()
        if not (State.AutoTameHorse or State.InfiniteHorseStamina) then return end
        pcall(function()
            local root = getRoot()
            if not root then return end

            local map = Workspace:FindFirstChild("Map")
            if map and State.AutoTameHorse then
                for _, model in ipairs(map:GetChildren()) do
                    if model.Name:find("Horse") and model:FindFirstChild("Humanoid") then
                        local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt and prompt.Enabled then
                            local dist = (root.Position - model:GetPivot().Position).Magnitude
                            if dist < 16 then
                                triggerPrompt(prompt)
                            end
                        end
                    end
                end
            end
        end)
    end

    ----------------------------------------------------------------
    --  MOD / STAFF DETECTOR
    ----------------------------------------------------------------
    local STAFF_RANKS = {"Moderator", "Admin", "Developer", "Creator", "Staff"}
    local function checkModInServer(player)
        if not State.ModDetector or not player then return end
        pcall(function()
            local isMod = false
            for _, rank in ipairs(STAFF_RANKS) do
                if player:GetRoleInGroup(33481232) == rank or player:IsInGroup(1200923) then
                    isMod = true
                    break
                end
            end
            if isMod then
                if State.ModAction == "Kick" then
                    LP:Kick("[RAVEN HUB] Staff detected in server: " .. player.Name)
                end
            end
        end)
    end

    connect(Players.PlayerAdded, checkModInServer)

    ----------------------------------------------------------------
    --  MAIN REPEAT TASKS & LOOPS
    ----------------------------------------------------------------

    local lastFarmCFrame = nil
    connect(LP.CharacterAdded, function(newChar)
        if State.TPBackOnDeath and lastFarmCFrame and State.AutoFarmMobs then
            task.delay(1.5, function()
                local newRoot = newChar:WaitForChild("HumanoidRootPart", 5)
                if newRoot and lastFarmCFrame then
                    newRoot.CFrame = lastFarmCFrame
                end
            end)
        end
    end)

    connect(LP.Idled, function()
        if State.AntiAFK then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end
    end)

    -- Auto Farm Loop (TerdsakHUB Exact Hover & Farm Architecture)
    task.spawn(function()
        while not isDestroyed do
            if State.AutoFarmMobs and isAlive() then
                local root = getRoot()
                local hum = getHumanoid()

                if root and hum and hum.Health > 0 then
                    -- Check Auto Quest if enabled
                    local questMobFilter = nil
                    if State.AutoQuest then
                        local qName = getBestQuestName()
                        questMobFilter = getQuestMobKeyword(qName)
                        if QuestsModule and QuestsModule.CanAddQuest and QuestsModule.CanAddQuest(LP) then
                            pcall(function()
                                local qData = QuestsModule.Holder and QuestsModule.Holder[qName]
                                if qData and qData.Position then
                                    local qPos = qData.Position
                                    local distToGiver = (root.Position - qPos).Magnitude
                                    if distToGiver > 12 then
                                        -- Glide smoothly to Quest Giver
                                        local dir = (qPos - root.Position).Unit
                                        root.CFrame = CFrame.new(root.Position + dir * math.min(distToGiver - 5, 45), qPos)
                                        root.AssemblyLinearVelocity = Vector3.zero
                                        root.AssemblyAngularVelocity = Vector3.zero
                                        task.wait(0.08)
                                    else
                                        -- Trigger prompt or Signal
                                        if SignalEvent and SignalEvent.ToServer then
                                            SignalEvent.ToServer("Quest", "Accept", qName)
                                        end
                                        task.wait(0.25)
                                    end
                                end
                            end)
                        end
                    end

                    local target = getClosestEnemy(questMobFilter)

                    if target and target.Root and target.Humanoid and target.Humanoid.Health > 0 then
                        local targetPos = target.Root.Position
                        local myPos = root.Position
                        local dist = (myPos - targetPos).Magnitude

                        -- Continuous position calculation
                        local farmPos
                        local lookAt = targetPos

                        if State.FarmMode == "Above (Hover)" or State.FarmMode == "Above" then
                            local h = State.HoverHeight or 5.0
                            local side = target.Root.CFrame.RightVector * (State.HoverSideOffset or 1.0)
                            farmPos = targetPos + Vector3.new(0, h, 0) + side
                        elseif State.FarmMode == "Behind (Backstab)" then
                            farmPos = targetPos - target.Root.CFrame.LookVector * 2.5 + Vector3.new(0, 1.2, 0)
                        elseif State.FarmMode == "Underground" then
                            local depth = math.clamp(State.UndergroundDepth or 2.4, 1.0, 4.0)
                            farmPos = targetPos - Vector3.new(0, depth, 0)
                        else
                            farmPos = targetPos + Vector3.new(0, State.HoverHeight or 5.0, 0)
                        end

                        -- Smooth glide approach if distance > 30 studs
                        if dist > 30 then
                            local dir = (farmPos - myPos).Unit
                            local step = math.min(dist - 15, 60)
                            currentFarmLockCF = CFrame.lookAt(myPos + dir * step, lookAt)
                            lastFarmCFrame = currentFarmLockCF
                            task.wait(0.04)
                        else
                            -- Locked in combat range: 100% stable freeze
                            currentFarmLockCF = CFrame.lookAt(farmPos, lookAt)
                            lastFarmCFrame = currentFarmLockCF

                            -- Weapon & Attack Execution
                            if State.EquipBestWeapon then
                                equipBestWeapon()
                            end

                            if State.HitMethod == "Game Punch" then
                                doPunch()
                            elseif State.HitMethod == "Weapon" then
                                local tool = getEquippedWeapon()
                                if tool then
                                    pcall(function() tool:Activate() end)
                                end
                                doPunch()
                            elseif State.HitMethod == "Virtual Input" then
                                pcall(function()
                                    VirtualUser:CaptureController()
                                    VirtualUser:ClickButton1(Vector2.new(960, 540))
                                end)
                                doPunch()
                            else
                                doPunch()
                            end

                            if State.AutoSkill then
                                doAutoSkills()
                            end

                            -- Auto Potion
                            if State.AutoPotion and (hum.Health / math.max(hum.MaxHealth, 1) * 100 <= (State.PotionThreshold or 50)) then
                                usePotion()
                            end

                            local waitTime = (State.FastAttack and 0.10) or 0.22
                            task.wait(waitTime)
                        end
                    else
                        currentFarmLockCF = nil
                        task.wait(0.3)
                    end
                else
                    currentFarmLockCF = nil
                    task.wait(0.3)
                end
            else
                currentFarmLockCF = nil
                task.wait(0.35)
            end
        end
    end)

    -- Kill Aura Loop
    task.spawn(function()
        while not isDestroyed do
            if State.KillAura and isAlive() and not State.AutoFarmMobs then
                local root = getRoot()
                if root then
                    local enemies = getActiveEnemies()
                    local closest = nil
                    local minDist = State.KillAuraRadius

                    for _, enemy in ipairs(enemies) do
                        if enemy.Root and enemy.Humanoid.Health > 0 then
                            local dist = (root.Position - enemy.Root.Position).Magnitude
                            if dist <= minDist then
                                minDist = dist
                                closest = enemy
                            end
                        end
                    end

                    if closest and closest.Root and closest.Humanoid.Health > 0 then
                        local enemyPos = closest.Root.Position
                        local dist = (root.Position - enemyPos).Magnitude

                        if State.KillAuraSnap and dist > 3.5 then
                            local snapPos = enemyPos - closest.Root.CFrame.LookVector * 2.0
                            root.CFrame = CFrame.lookAt(snapPos, enemyPos)
                            root.AssemblyLinearVelocity = Vector3.zero
                            task.wait(0.03)
                        else
                            local targetLook = Vector3.new(enemyPos.X, root.Position.Y, enemyPos.Z)
                            root.CFrame = CFrame.lookAt(root.Position, targetLook)
                        end

                        local cd = doPunch()
                        doAutoSkills()
                        local waitTime = (State.FastAttack and 0.10) or (cd and cd > 0.1 and cd) or 0.22
                        task.wait(waitTime)
                    else
                        task.wait(0.25)
                    end
                else
                    task.wait(0.4)
                end
            else
                task.wait(0.4)
            end
        end
    end)

    -- Auto Chest & Snow Mound Looting Loop
    task.spawn(function()
        while not isDestroyed do
            if State.AutoChests and isAlive() and not State.AutoFarmMobs then
                local root = getRoot()
                local chestsFolder = Workspace:FindFirstChild("Chests")
                if root and chestsFolder then
                    for _, chest in ipairs(chestsFolder:GetChildren()) do
                        if not State.AutoChests then break end
                        local prompt = chest:FindFirstChildWhichIsA("ProximityPrompt", true)
                        local cf = chest:IsA("BasePart") and chest.CFrame or chest:GetPivot()
                        local dist = (root.Position - cf.Position).Magnitude

                        if prompt and dist <= State.ChestFarmRadius then
                            teleportTo(cf)
                            task.wait(0.2)
                            triggerPrompt(prompt)
                            task.wait(0.5)
                        end
                    end
                end
                task.wait(1.5)
            else
                task.wait(1.0)
            end
        end
    end)

    -- Automation Loops (Quest, Fish, Horse)
    task.spawn(function()
        while not isDestroyed do
            if isAlive() then
                handleAutoQuest()
                runAutoFishingStep()
                handleHorseAutomation()
            end
            task.wait(1.2)
        end
    end)

    ----------------------------------------------------------------
    --  MINIGAME SOLVER (TRAINING ASSIST)
    ----------------------------------------------------------------
    local function solveTrainingMinigames()
        if not State.AutoTraining then return end
        local root = getRoot()
        local playerGui = LP:FindFirstChild("PlayerGui")
        local misc = playerGui and playerGui:FindFirstChild("Misc")

        -- 1. Auto Squat Bar Keepup
        if State.AutoSquat and misc then
            local squatGui = misc:FindFirstChild("SquatMinigame") or misc:FindFirstChild("Squat")
            if squatGui and squatGui:IsA("ScreenGui") and squatGui.Enabled then
                pcall(function()
                    VirtualUser:Button1Down(Vector2.new(0, 0), Camera.CFrame)
                    task.wait(0.08)
                    VirtualUser:Button1Up(Vector2.new(0, 0), Camera.CFrame)
                end)
            end
        end

        -- 2. Auto Cup Game
        if State.AutoCupGame and misc then
            local cupGui = misc:FindFirstChild("CupGame") or misc:FindFirstChild("CupMinigame")
            if cupGui and cupGui:IsA("ScreenGui") and cupGui.Enabled then
                for _, desc in ipairs(cupGui:GetDescendants()) do
                    if desc:IsA("ImageButton") and desc:GetAttribute("HasBall") == true then
                        pcall(function()
                            VirtualUser:Button1Down(desc.AbsolutePosition + (desc.AbsoluteSize / 2), Camera.CFrame)
                            task.wait(0.05)
                            VirtualUser:Button1Up(desc.AbsolutePosition + (desc.AbsoluteSize / 2), Camera.CFrame)
                        end)
                    end
                end
            end
        end

        -- 3. Auto Boulder Push / Split Stations
        if (State.AutoBoulderPush or State.AutoBoulderSplit) and root then
            local trainingFolder = Workspace:FindFirstChild("Training")
            if trainingFolder then
                for _, folderName in ipairs({"Boulder Push", "Boulder Split"}) do
                    local f = trainingFolder:FindFirstChild(folderName)
                    if f then
                        for _, desc in ipairs(f:GetDescendants()) do
                            if desc:IsA("ProximityPrompt") and desc.Enabled then
                                local pPos = desc.Parent and (desc.Parent:IsA("BasePart") and desc.Parent.Position or desc.Parent:GetPivot().Position)
                                if pPos and (root.Position - pPos).Magnitude <= 12 then
                                    triggerPrompt(desc)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    --  PLAYER UTILITIES & BUFFS
    ----------------------------------------------------------------
    local function applyPlayerBuffs()
        local hum = getHumanoid()
        if hum then
            if State.CustomWalkSpeed then
                hum.WalkSpeed = State.WalkSpeed
            end
            if State.CustomJumpPower then
                hum.JumpPower = State.JumpPower
            end
            -- God mode protection
            if State.GodMode and hum.Health < State.GodModeThreshold then
                hum.Health = hum.MaxHealth
            end
        end

        -- Infinite Stamina Lock (Direct IntConstrainedValue Value lock)
        if State.InfiniteStamina and Utility and type(Utility.getvaluesfolder) == "function" then
            pcall(function()
                local vf = Utility.getvaluesfolder(LP, true)
                local stam = vf and vf:FindFirstChild("Stamina")
                if stam and stam:IsA("IntConstrainedValue") then
                    stam.Value = stam.MaxValue
                end
            end)
        end

        -- Sun Damage Immunity
        if State.SunDamageImmunity then
            pcall(function()
                local sunScript = LP:FindFirstChild("PlayerGui")
                    and LP.PlayerGui:FindFirstChild("UCS")
                    and LP.PlayerGui.UCS:FindFirstChild("Game_Play")
                    and LP.PlayerGui.UCS.Game_Play:FindFirstChild("SunDamage")
                if sunScript and sunScript:IsA("LocalScript") and sunScript.Enabled then
                    sunScript.Enabled = false
                end
            end)
        end

        -- Anti Ragdoll
        if State.AntiRagdoll then
            pcall(function()
                local ragdollScript = LP:FindFirstChild("PlayerGui")
                    and LP.PlayerGui:FindFirstChild("UCS")
                    and LP.PlayerGui.UCS:FindFirstChild("RagDolling")
                if ragdollScript and ragdollScript:IsA("LocalScript") and ragdollScript.Enabled then
                    ragdollScript.Enabled = false
                end

                local char = getChar()
                if char then
                    local ragVal = char:FindFirstChild("Ragdoll") or char:FindFirstChild("IsRagdoll")
                    if ragVal and ragVal:IsA("BoolValue") then
                        ragVal.Value = false
                    end
                end
            end)
        end
    end

    -- Infinite Jump
    connect(UserInputService.JumpRequest, function()
        if State.InfiniteJump and isAlive() then
            local hum = getHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    -- Farm Anchor BodyVelocity to guarantee zero physics drift
    local farmVelocityAnchor = nil
    local function setFarmPhysicsAnchor(enabled)
        local root = getRoot()
        if not root then return end
        if enabled then
            if not farmVelocityAnchor or farmVelocityAnchor.Parent ~= root then
                if farmVelocityAnchor then pcall(function() farmVelocityAnchor:Destroy() end) end
                farmVelocityAnchor = Instance.new("BodyVelocity")
                farmVelocityAnchor.Name = "RavenFarmAnchor"
                farmVelocityAnchor.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                farmVelocityAnchor.Velocity = Vector3.zero
                farmVelocityAnchor.Parent = root
            end
        else
            if farmVelocityAnchor then
                pcall(function() farmVelocityAnchor:Destroy() end)
                farmVelocityAnchor = nil
            end
        end
    end

    -- Noclip & Physics Lock Handler (Runs every simulation frame)
    connect(RunService.Stepped, function()
        if isDestroyed then return end
        local char = getChar()
        if not char then return end

        if State.Noclip or currentFarmLockCF then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end

        if currentFarmLockCF then
            local hum = getHumanoid()
            local root = getRoot()
            if hum and hum:GetState() ~= Enum.HumanoidStateType.Physics then
                hum:ChangeState(Enum.HumanoidStateType.Physics)
            end
            if root then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)

    -- Lock CFrame on Heartbeat (Post-Physics update frame) for 100% rock-solid anchor
    connect(RunService.Heartbeat, function()
        if isDestroyed then return end
        if currentFarmLockCF then
            local root = getRoot()
            if root then
                root.CFrame = currentFarmLockCF
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
            setFarmPhysicsAnchor(true)
        else
            setFarmPhysicsAnchor(false)
        end
    end)

    -- Fly System
    local flyBodyVelocity, flyBodyGyro
    local function setFly(enabled)
        local root = getRoot()
        if not root then return end

        if enabled then
            if not flyBodyVelocity then
                flyBodyVelocity = Instance.new("BodyVelocity")
                flyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                flyBodyVelocity.Velocity = Vector3.zero
                flyBodyVelocity.Parent = root
            end
            if not flyBodyGyro then
                flyBodyGyro = Instance.new("BodyGyro")
                flyBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                flyBodyGyro.CFrame = root.CFrame
                flyBodyGyro.Parent = root
            end
        else
            if flyBodyVelocity then flyBodyVelocity:Destroy() flyBodyVelocity = nil end
            if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
        end
    end

    local function updateFly()
        if not State.Fly or not flyBodyVelocity or not flyBodyGyro then return end
        local root = getRoot()
        local hum = getHumanoid()
        if not root or not hum then return end

        local cam = Workspace.CurrentCamera
        local moveDir = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end

        if moveDir.Magnitude > 0 then
            flyBodyVelocity.Velocity = moveDir.Unit * State.FlySpeed
        else
            flyBodyVelocity.Velocity = Vector3.zero
        end
        flyBodyGyro.CFrame = cam.CFrame
    end

    ----------------------------------------------------------------
    --  100% DRAWING VISUALS (ESP)
    ----------------------------------------------------------------
    local function clearDrawings(tbl)
        for _, entry in pairs(tbl) do
            if entry.Text then pcall(function() entry.Text:Remove() end) end
            if entry.Box then pcall(function() entry.Box:Remove() end) end
        end
        table.clear(tbl)
    end

    local function renderESP()
        if not hasDrawing then return end
        local root = getRoot()
        if not root then return end

        -- 1. Mobs & Bosses ESP
        if State.ESPMobs then
            local enemies = getActiveEnemies()
            local currentKeys = {}
            for _, enemy in ipairs(enemies) do
                local part = enemy.Root
                if part and part.Parent then
                    currentKeys[enemy.Model] = true
                    local dist = math.floor((Camera.CFrame.Position - part.Position).Magnitude)
                    if dist <= State.MaxESPDistance then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                        local entry = DrawingObjects.Mobs[enemy.Model]
                        if not entry then
                            local txt = Drawing.new("Text")
                            txt.Size = 13
                            txt.Center = true
                            txt.Outline = true
                            entry = { Text = txt }
                            DrawingObjects.Mobs[enemy.Model] = entry
                        end

                        if onScreen then
                            entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                            if enemy.IsBoss then
                                entry.Text.Color = Color3.fromRGB(255, 65, 65)
                                entry.Text.Text = string.format("👑 [BOSS] %s [%d HP | %dm]", enemy.Name, math.floor(enemy.Humanoid.Health), dist)
                            else
                                entry.Text.Color = Color3.fromRGB(255, 180, 50)
                                entry.Text.Text = string.format("👹 %s [%d HP | %dm]", enemy.Name, math.floor(enemy.Humanoid.Health), dist)
                            end
                            entry.Text.Visible = true
                        else
                            entry.Text.Visible = false
                        end
                    end
                end
            end

            for model, entry in pairs(DrawingObjects.Mobs) do
                if not currentKeys[model] then
                    if entry.Text then pcall(function() entry.Text:Remove() end) end
                    DrawingObjects.Mobs[model] = nil
                end
            end
        else
            clearDrawings(DrawingObjects.Mobs)
        end

        -- 2. Players ESP
        if State.ESPPlayers then
            local currentKeys = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LP and p.Character then
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    if hrp and hum and hum.Health > 0 then
                        currentKeys[p] = true
                        local dist = math.floor((Camera.CFrame.Position - hrp.Position).Magnitude)
                        if dist <= State.MaxESPDistance then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                            local entry = DrawingObjects.Players[p]
                            if not entry then
                                local txt = Drawing.new("Text")
                                txt.Size = 13
                                txt.Center = true
                                txt.Outline = true
                                txt.Color = Color3.fromRGB(85, 170, 255)
                                entry = { Text = txt }
                                DrawingObjects.Players[p] = entry
                            end

                            if onScreen then
                                local clan = p.Character:GetAttribute("Clan") or "Unknown"
                                entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                entry.Text.Text = string.format("👤 %s (%s) [%d HP | %dm]", p.DisplayName, clan, math.floor(hum.Health), dist)
                                entry.Text.Visible = true
                            else
                                entry.Text.Visible = false
                            end
                        end
                    end
                end
            end

            for p, entry in pairs(DrawingObjects.Players) do
                if not currentKeys[p] then
                    if entry.Text then pcall(function() entry.Text:Remove() end) end
                    DrawingObjects.Players[p] = nil
                end
            end
        else
            clearDrawings(DrawingObjects.Players)
        end

        -- 3. Chests & Snow Mounds ESP
        if State.ESPChests then
            local chestsFolder = Workspace:FindFirstChild("Chests")
            local currentKeys = {}
            if chestsFolder then
                for _, chest in ipairs(chestsFolder:GetChildren()) do
                    if chest:IsA("BasePart") or chest:IsA("Model") then
                        currentKeys[chest] = true
                        local part = chest:IsA("BasePart") and chest or chest:FindFirstChildWhichIsA("BasePart")
                        if part then
                            local dist = math.floor((Camera.CFrame.Position - part.Position).Magnitude)
                            if dist <= State.MaxESPDistance then
                                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                                local entry = DrawingObjects.Chests[chest]
                                if not entry then
                                    local txt = Drawing.new("Text")
                                    txt.Size = 12
                                    txt.Center = true
                                    txt.Outline = true
                                    txt.Color = Color3.fromRGB(120, 255, 120)
                                    entry = { Text = txt }
                                    DrawingObjects.Chests[chest] = entry
                                end

                                if onScreen then
                                    entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                    entry.Text.Text = string.format("📦 %s [%dm]", chest.Name, dist)
                                    entry.Text.Visible = true
                                else
                                    entry.Text.Visible = false
                                end
                            end
                        end
                    end
                end
            end

            for chest, entry in pairs(DrawingObjects.Chests) do
                if not currentKeys[chest] then
                    if entry.Text then pcall(function() entry.Text:Remove() end) end
                    DrawingObjects.Chests[chest] = nil
                end
            end
        else
            clearDrawings(DrawingObjects.Chests)
        end

        -- 4. Puzzles & Special Radar (Muzan, Spider Lily, Wild Horses)
        if State.ESPSpecial then
            local currentKeys = {}
            local map = Workspace:FindFirstChild("Map")
            if map then
                for _, item in ipairs(map:GetChildren()) do
                    if item.Name:find("Muzan") or item.Name:find("Spider") or item.Name:find("Horse") then
                        currentKeys[item] = true
                        local part = item:IsA("BasePart") and item or item:FindFirstChildWhichIsA("BasePart")
                        if part then
                            local dist = math.floor((Camera.CFrame.Position - part.Position).Magnitude)
                            if dist <= State.MaxESPDistance then
                                local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                                local entry = DrawingObjects.Special[item]
                                if not entry then
                                    local txt = Drawing.new("Text")
                                    txt.Size = 13
                                    txt.Center = true
                                    txt.Outline = true
                                    txt.Color = Color3.fromRGB(255, 215, 0)
                                    entry = { Text = txt }
                                    DrawingObjects.Special[item] = entry
                                end

                                if onScreen then
                                    entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                    entry.Text.Text = string.format("🌟 [%s] [%dm]", item.Name, dist)
                                    entry.Text.Visible = true
                                else
                                    entry.Text.Visible = false
                                end
                            end
                        end
                    end
                end
            end

            for item, entry in pairs(DrawingObjects.Special) do
                if not currentKeys[item] then
                    if entry.Text then pcall(function() entry.Text:Remove() end) end
                    DrawingObjects.Special[item] = nil
                end
            end
        else
            clearDrawings(DrawingObjects.Special)
        end
    end

    ----------------------------------------------------------------
    --  HEARTBEAT LOOP
    ----------------------------------------------------------------
    local lastTick = 0
    connect(RunService.Heartbeat, function()
        if isDestroyed then return end

        pcall(applyPlayerBuffs)
        pcall(updateFly)
        pcall(renderESP)

        local now = os.clock()
        if now - lastTick >= 0.5 then
            lastTick = now
            pcall(applyHitboxExpander)
            pcall(solveTrainingMinigames)
        end
    end)

    ----------------------------------------------------------------
    --  TELEPORT LOCATIONS REGISTRY
    ----------------------------------------------------------------
    local TELEPORTS = {
        -- Regions & Towns
        ["Hidden Mist Village"] = CFrame.new(245.5, 1084.2, -180.4),
        ["Butterfly Estate"] = CFrame.new(-920.4, 1140.5, -450.8),
        ["Windy Peak"] = CFrame.new(-470.2, 1245.8, -950.4),
        ["Iceveil Valley"] = CFrame.new(620.1, 1075.3, 850.7),
        ["Bamboo Grove"] = CFrame.new(-120.4, 1060.2, 420.6),
        ["Mistfall Harbor"] = CFrame.new(890.3, 1055.4, -610.2),
        ["Stone Sanctuary"] = CFrame.new(-350.2, 1105.8, 120.5),
        ["Final Selection Plains"] = CFrame.new(1250.4, 1080.2, -1450.6),

        -- Fishing & Shops
        ["Fishing Dock (Mistfall)"] = CFrame.new(890.3, 1055.4, -610.2),
        ["Fisherman Jeso"] = CFrame.new(882.1, 1055.8, -605.3),
        ["Fish Buyer Ginzo"] = CFrame.new(875.2, 1056.1, -625.4),

        -- Training Stations
        ["Training: Squat Rack"] = CFrame.new(-330.5, 1072.0, -560.2),
        ["Training: Boulder Push"] = CFrame.new(-311.6, 1071.6, -579.6),
        ["Training: Boulder Split"] = CFrame.new(-280.4, 1071.5, -600.2),
        ["Training: Aim / Target Shooting"] = CFrame.new(-390.2, 1072.1, -620.4),
        ["Training: Cup Game"] = CFrame.new(-350.6, 1072.0, -540.8),
        ["Training: Pushups Mat"] = CFrame.new(-370.2, 1072.0, -510.5),
        ["Training: Meditation Mat"] = CFrame.new(-390.5, 1072.0, -490.2),
        ["Training: Parkour Dungeon"] = CFrame.new(130.3, 1071.1, -1301.8),
    }

    ----------------------------------------------------------------
    --  UI CREATION (100% DRAWING MACLIB STANDARD)
    ----------------------------------------------------------------

    -- TAB 1: 🏋️ Auto Training
    local TrainingTab = Window:CreateTab("Training", "overview")
    TrainingTab:CreateSection("Auto Minigames & Stations")

    TrainingTab:CreateToggle({
        Name = "Enable Auto Training Assist",
        CurrentValue = State.AutoTraining,
        Flag = "OWL_AutoTraining",
        Callback = function(v) State.AutoTraining = v end,
    })

    TrainingTab:CreateToggle({
        Name = "Auto Squat (BarKeepup Balance)",
        CurrentValue = State.AutoSquat,
        Flag = "OWL_AutoSquat",
        Callback = function(v) State.AutoSquat = v end,
    })

    TrainingTab:CreateToggle({
        Name = "Auto Cup Game (Track Ball)",
        CurrentValue = State.AutoCupGame,
        Flag = "OWL_AutoCupGame",
        Callback = function(v) State.AutoCupGame = v end,
    })

    TrainingTab:CreateToggle({
        Name = "Auto Target Shooting",
        CurrentValue = State.AutoTargetShooting,
        Flag = "OWL_AutoTarget",
        Callback = function(v) State.AutoTargetShooting = v end,
    })

    TrainingTab:CreateToggle({
        Name = "Auto Boulder Push",
        CurrentValue = State.AutoBoulderPush,
        Flag = "OWL_AutoBoulderPush",
        Callback = function(v) State.AutoBoulderPush = v end,
    })

    TrainingTab:CreateToggle({
        Name = "Auto Boulder Split",
        CurrentValue = State.AutoBoulderSplit,
        Flag = "OWL_AutoBoulderSplit",
        Callback = function(v) State.AutoBoulderSplit = v end,
    })

    TrainingTab:CreateSection("Training Station Teleports")
    for name, cf in pairs(TELEPORTS) do
        if name:find("Training:") then
            TrainingTab:CreateButton({
                Name = "TP: " .. name:gsub("Training: ", ""),
                Callback = function() teleportTo(cf) end,
            })
        end
    end

    -- TAB 2: ⚔️ Combat
    local CombatTab = Window:CreateTab("Combat", "combat")
    CombatTab:CreateSection("Auto Attack & Fast Punch")

    CombatTab:CreateToggle({
        Name = "Fast Attack Mode (Presets Tuning)",
        CurrentValue = State.FastAttack,
        Flag = "OWL_FastAttack",
        Callback = function(v)
            State.FastAttack = v
            setFastAttackMode(v)
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Skills Rotation",
        CurrentValue = State.AutoSkill,
        Flag = "OWL_AutoSkill",
        Callback = function(v) State.AutoSkill = v end,
    })

    CombatTab:CreateToggle({
        Name = "Kill Aura (Radius Cone Attack)",
        CurrentValue = State.KillAura,
        Flag = "OWL_KillAura",
        Callback = function(v) State.KillAura = v end,
    })

    CombatTab:CreateToggle({
        Name = "Kill Aura Target Snap",
        CurrentValue = State.KillAuraSnap,
        Flag = "OWL_AuraSnap",
        Callback = function(v) State.KillAuraSnap = v end,
    })

    CombatTab:CreateSlider({
        Name = "Kill Aura Radius",
        Min = 5,
        Max = 40,
        Default = State.KillAuraRadius,
        Increment = 1,
        Flag = "OWL_AuraRadius",
        Callback = function(v) State.KillAuraRadius = v end,
    })

    CombatTab:CreateSection("Protection & Hitbox")

    CombatTab:CreateToggle({
        Name = "God Mode (Auto Heal Below %)",
        CurrentValue = State.GodMode,
        Flag = "OWL_GodMode",
        Callback = function(v) State.GodMode = v end,
    })

    CombatTab:CreateSlider({
        Name = "God Mode HP Threshold",
        Min = 20,
        Max = 95,
        Default = State.GodModeThreshold,
        Increment = 5,
        Flag = "OWL_GodThreshold",
        Callback = function(v) State.GodModeThreshold = v end,
    })

    CombatTab:CreateToggle({
        Name = "Expand Enemy Hitbox",
        CurrentValue = State.HitboxExpander,
        Flag = "OWL_HitboxExp",
        Callback = function(v)
            State.HitboxExpander = v
            if not v then restoreHitboxes() end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Hitbox Size",
        Min = 4,
        Max = 20,
        Default = State.HitboxSize,
        Increment = 1,
        Flag = "OWL_HitboxSize",
        Callback = function(v) State.HitboxSize = v end,
    })

    -- TAB 3: 🌾 Automation & Farming (TerdsakHUB Exact Layout)
    local FarmingTab = Window:CreateTab("Farming", "automation")
    FarmingTab:CreateSection("Mob & Boss Autofarm")

    FarmingTab:CreateToggle({
        Name = "Auto Farm Mobs",
        CurrentValue = State.AutoFarmMobs,
        Flag = "OWL_AutoFarm",
        Callback = function(v) State.AutoFarmMobs = v end,
    })

    FarmingTab:CreateDropdown({
        Name = "Target Mobs",
        Options = {"All Mobs", "Bandits", "Bears", "Demons", "Lancers", "Slayers", "Kaiden", "Civilian", "Snow Demons", "Yeti"},
        CurrentOption = State.FarmTarget,
        Flag = "OWL_FarmTarget",
        Callback = function(v) State.FarmTarget = v end,
    })

    FarmingTab:CreateToggle({
        Name = "Auto Boss Farm",
        CurrentValue = State.AutoBoss,
        Flag = "OWL_AutoBoss",
        Callback = function(v) State.AutoBoss = v end,
    })

    FarmingTab:CreateDropdown({
        Name = "Target Boss Select",
        Options = {"All", "Zuko", "Hoyuzo", "Sabito", "Giyen", "Enru", "Datai", "Gyutai", "Reaper", "Sumari", "Saneri"},
        CurrentOption = State.BossTarget,
        Flag = "OWL_BossSelect",
        Callback = function(v) State.BossTarget = v end,
    })

    FarmingTab:CreateDropdown({
        Name = "Hit Method",
        Options = {"Game Punch", "Weapon", "Virtual Input"},
        CurrentOption = State.HitMethod,
        Flag = "OWL_HitMethod",
        Callback = function(v) State.HitMethod = v end,
    })

    FarmingTab:CreateToggle({
        Name = "Auto Equip Best Weapon",
        CurrentValue = State.EquipBestWeapon,
        Flag = "OWL_EquipWeapon",
        Callback = function(v) State.EquipBestWeapon = v end,
    })

    FarmingTab:CreateSection("Hover Position (TerdsakHUB Engine)")

    FarmingTab:CreateDropdown({
        Name = "Position Mode",
        Options = {"Above (Hover)", "Behind (Backstab)", "Underground"},
        CurrentOption = State.FarmMode,
        Flag = "OWL_FarmPosMode",
        Callback = function(v) State.FarmMode = v end,
    })

    FarmingTab:CreateSlider({
        Name = "Hover Height (studs)",
        Min = 1.0,
        Max = 15.0,
        Default = State.HoverHeight,
        Increment = 0.5,
        Flag = "OWL_HoverHeight",
        Callback = function(v) State.HoverHeight = v end,
    })

    FarmingTab:CreateSlider({
        Name = "Hover Side Offset (studs)",
        Min = -10.0,
        Max = 10.0,
        Default = State.HoverSideOffset,
        Increment = 0.5,
        Flag = "OWL_HoverOffset",
        Callback = function(v) State.HoverSideOffset = v end,
    })

    FarmingTab:CreateSlider({
        Name = "Underground Depth (studs)",
        Min = 1.0,
        Max = 4.0,
        Default = State.UndergroundDepth,
        Increment = 0.1,
        Flag = "OWL_UnderDepth",
        Callback = function(v) State.UndergroundDepth = v end,
    })

    FarmingTab:CreateSection("Auto Quest Progression")

    FarmingTab:CreateToggle({
        Name = "Enable Auto Quest (Synced with Farm)",
        CurrentValue = State.AutoQuest,
        Flag = "OWL_AutoQuest",
        Callback = function(v) State.AutoQuest = v end,
    })

    FarmingTab:CreateDropdown({
        Name = "Quest Selection",
        Options = {"Auto Level", "Bandits", "Bears", "Kaiden", "Hoyuzo", "Guards"},
        CurrentOption = State.AutoQuestMode,
        Flag = "OWL_QuestMode",
        Callback = function(v) State.AutoQuestMode = v end,
    })

    FarmingTab:CreateSection("Survival & Farm Utilities")

    FarmingTab:CreateToggle({
        Name = "Auto Potion / Heal",
        CurrentValue = State.AutoPotion,
        Flag = "OWL_AutoPotion",
        Callback = function(v) State.AutoPotion = v end,
    })

    FarmingTab:CreateSlider({
        Name = "Potion HP Threshold %",
        Min = 10,
        Max = 90,
        Default = State.PotionThreshold,
        Increment = 5,
        Flag = "OWL_PotionHP",
        Callback = function(v) State.PotionThreshold = v end,
    })

    FarmingTab:CreateToggle({
        Name = "TP Back on Death",
        CurrentValue = State.TPBackOnDeath,
        Flag = "OWL_TPOnDeath",
        Callback = function(v) State.TPBackOnDeath = v end,
    })

    FarmingTab:CreateToggle({
        Name = "Anti-AFK (20min Protection)",
        CurrentValue = State.AntiAFK,
        Flag = "OWL_AntiAFK",
        Callback = function(v) State.AntiAFK = v end,
    })

    FarmingTab:CreateSection("Auto Fishing System")

    FarmingTab:CreateToggle({
        Name = "Enable Auto Fish Loop",
        CurrentValue = State.AutoFish,
        Flag = "OWL_AutoFish",
        Callback = function(v) State.AutoFish = v end,
    })

    FarmingTab:CreateToggle({
        Name = "Auto Buy Bait / Rod (Jeso)",
        CurrentValue = State.AutoBuyBait,
        Flag = "OWL_AutoBuyBait",
        Callback = function(v) State.AutoBuyBait = v end,
    })

    FarmingTab:CreateToggle({
        Name = "Auto Sell Fish to Ginzo",
        CurrentValue = State.AutoSellFish,
        Flag = "OWL_AutoSellFish",
        Callback = function(v) State.AutoSellFish = v end,
    })

    FarmingTab:CreateSlider({
        Name = "Sell When Holding Fish",
        Min = 5,
        Max = 25,
        Default = State.FishSellCap,
        Increment = 1,
        Flag = "OWL_FishCap",
        Callback = function(v) State.FishSellCap = v end,
    })

    -- TAB 4: 🏃 Player & Movement
    local PlayerTab = Window:CreateTab("Player", "defense")
    PlayerTab:CreateSection("Movement & Cooldown Bypasses")

    PlayerTab:CreateToggle({
        Name = "No Dash Cooldown (Instant Dash)",
        CurrentValue = State.NoDashCooldown,
        Flag = "OWL_NoDashCd",
        Callback = function(v) State.NoDashCooldown = v end,
    })

    PlayerTab:CreateToggle({
        Name = "No Stamina Dash (0 Stamina Cost)",
        CurrentValue = State.NoStaminaDash,
        Flag = "OWL_NoStamDash",
        Callback = function(v) State.NoStaminaDash = v end,
    })

    PlayerTab:CreateToggle({
        Name = "No Drown (Underwater Breathing)",
        CurrentValue = State.NoDrown,
        Flag = "OWL_NoDrown",
        Callback = function(v) State.NoDrown = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Infinite Stamina (Sprint & Climb)",
        CurrentValue = State.InfiniteStamina,
        Flag = "OWL_InfStamina",
        Callback = function(v) State.InfiniteStamina = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Sun Damage Immunity (Demons)",
        CurrentValue = State.SunDamageImmunity,
        Flag = "OWL_SunImmune",
        Callback = function(v) State.SunDamageImmunity = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Anti Ragdoll (No Knockdown)",
        CurrentValue = State.AntiRagdoll,
        Flag = "OWL_AntiRagdoll",
        Callback = function(v) State.AntiRagdoll = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Instant Interact (ProximityPrompt 0s)",
        CurrentValue = State.InstantPrompt,
        Flag = "OWL_InstantPrompt",
        Callback = function(v) State.InstantPrompt = v end,
    })

    PlayerTab:CreateSection("Movement Modification")

    PlayerTab:CreateToggle({
        Name = "Custom WalkSpeed",
        CurrentValue = State.CustomWalkSpeed,
        Flag = "OWL_CustomSpeed",
        Callback = function(v)
            State.CustomWalkSpeed = v
            if not v then
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = 16 end
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "WalkSpeed Value",
        Min = 16,
        Max = 120,
        Default = State.WalkSpeed,
        Increment = 2,
        Flag = "OWL_SpeedVal",
        Callback = function(v) State.WalkSpeed = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Custom JumpPower",
        CurrentValue = State.CustomJumpPower,
        Flag = "OWL_CustomJump",
        Callback = function(v)
            State.CustomJumpPower = v
            if not v then
                local hum = getHumanoid()
                if hum then hum.JumpPower = 50 end
            end
        end,
    })

    PlayerTab:CreateSlider({
        Name = "JumpPower Value",
        Min = 50,
        Max = 200,
        Default = State.JumpPower,
        Increment = 5,
        Flag = "OWL_JumpVal",
        Callback = function(v) State.JumpPower = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = State.InfiniteJump,
        Flag = "OWL_InfJump",
        Callback = function(v) State.InfiniteJump = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Noclip (Walk Through Walls)",
        CurrentValue = State.Noclip,
        Flag = "OWL_Noclip",
        Callback = function(v) State.Noclip = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Fly Mode (WASD + Space/Shift)",
        CurrentValue = State.Fly,
        Flag = "OWL_Fly",
        Callback = function(v)
            State.Fly = v
            setFly(v)
        end,
    })

    PlayerTab:CreateSlider({
        Name = "Fly Speed",
        Min = 20,
        Max = 150,
        Default = State.FlySpeed,
        Increment = 5,
        Flag = "OWL_FlySpeed",
        Callback = function(v) State.FlySpeed = v end,
    })

    PlayerTab:CreateSection("Horse Automation")

    PlayerTab:CreateToggle({
        Name = "Auto Tame Wild Horses",
        CurrentValue = State.AutoTameHorse,
        Flag = "OWL_AutoTame",
        Callback = function(v) State.AutoTameHorse = v end,
    })

    PlayerTab:CreateToggle({
        Name = "Infinite Horse Stamina",
        CurrentValue = State.InfiniteHorseStamina,
        Flag = "OWL_InfHorseStam",
        Callback = function(v) State.InfiniteHorseStamina = v end,
    })

    -- TAB 5: 👁️ Visuals (ESP)
    local VisualTab = Window:CreateTab("Visuals", "visuals")
    VisualTab:CreateSection("Entity & World ESP")

    VisualTab:CreateToggle({
        Name = "Mobs & Bosses ESP",
        CurrentValue = State.ESPMobs,
        Flag = "OWL_ESPMobs",
        Callback = function(v)
            State.ESPMobs = v
            if not v then clearDrawings(DrawingObjects.Mobs) end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Players ESP (Name + Clan)",
        CurrentValue = State.ESPPlayers,
        Flag = "OWL_ESPPlayers",
        Callback = function(v)
            State.ESPPlayers = v
            if not v then clearDrawings(DrawingObjects.Players) end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Chests & Snow Mounds ESP",
        CurrentValue = State.ESPChests,
        Flag = "OWL_ESPChests",
        Callback = function(v)
            State.ESPChests = v
            if not v then clearDrawings(DrawingObjects.Chests) end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Special Radar (Muzan / Lily / Horses)",
        CurrentValue = State.ESPSpecial,
        Flag = "OWL_ESPSpecial",
        Callback = function(v)
            State.ESPSpecial = v
            if not v then clearDrawings(DrawingObjects.Special) end
        end,
    })

    VisualTab:CreateToggle({
        Name = "Auto Loot Chests & Snow Mounds",
        CurrentValue = State.AutoChests,
        Flag = "OWL_AutoChests",
        Callback = function(v) State.AutoChests = v end,
    })

    VisualTab:CreateSlider({
        Name = "Max ESP Distance",
        Min = 200,
        Max = 3000,
        Default = State.MaxESPDistance,
        Increment = 100,
        Flag = "OWL_MaxDist",
        Callback = function(v) State.MaxESPDistance = v end,
    })

    -- TAB 6: 📍 Teleports
    local TeleportTab = Window:CreateTab("Teleport", "safety")
    TeleportTab:CreateSection("Teleport Mode & Stability")

    TeleportTab:CreateToggle({
        Name = "Smooth Tween Teleport (Glide / No Jerk)",
        CurrentValue = State.TweenTeleport,
        Flag = "OWL_TweenTP",
        Callback = function(v) State.TweenTeleport = v end,
    })

    TeleportTab:CreateSlider({
        Name = "Tween Speed",
        Min = 50,
        Max = 350,
        Default = State.TweenSpeed,
        Increment = 25,
        Flag = "OWL_TweenSpeed",
        Callback = function(v) State.TweenSpeed = v end,
    })

    TeleportTab:CreateSection("Regions, Towns & Docks")
    for name, cf in pairs(TELEPORTS) do
        if not name:find("Training:") then
            TeleportTab:CreateButton({
                Name = "TP: " .. name,
                Callback = function() teleportTo(cf) end,
            })
        end
    end

    TeleportTab:CreateSection("Boss Teleports")
    TeleportTab:CreateButton({
        Name = "TP: Closest Active Boss",
        Callback = function()
            local enemies = getActiveEnemies()
            for _, e in ipairs(enemies) do
                if e.IsBoss and e.Root then
                    teleportTo(e.Root.CFrame + Vector3.new(0, 5, 0))
                    break
                end
            end
        end,
    })

    -- TAB 7: 🛡️ Safety & Misc
    local SafetyTab = Window:CreateTab("Misc", "security")
    SafetyTab:CreateSection("Moderator & Boss Protection")

    SafetyTab:CreateToggle({
        Name = "Mod / Staff Detector",
        CurrentValue = State.ModDetector,
        Flag = "OWL_ModDetector",
        Callback = function(v) State.ModDetector = v end,
    })

    SafetyTab:CreateDropdown({
        Name = "Mod Action",
        Options = {"Kick", "Notify"},
        CurrentOption = State.ModAction,
        Flag = "OWL_ModAction",
        Callback = function(v) State.ModAction = v end,
    })

    SafetyTab:CreateToggle({
        Name = "Boss Spawner Alerts",
        CurrentValue = State.BossNotifier,
        Flag = "OWL_BossAlert",
        Callback = function(v) State.BossNotifier = v end,
    })

    SafetyTab:CreateToggle({
        Name = "Black Market Rare Sniper",
        CurrentValue = State.BlackMarketSniper,
        Flag = "OWL_BMSniper",
        Callback = function(v) State.BlackMarketSniper = v end,
    })

    -- Order & Sort Tabs
    pcall(function()
        if Window.SortTabs then
            Window:SortTabs({"Overview", "Training", "Combat", "Farming", "Player", "Visuals", "Teleport", "Misc", "Settings"})
        end
    end)

    ----------------------------------------------------------------
    --  TEARDOWN & RETURN
    ----------------------------------------------------------------
    local ModuleInstance = {
        State = State,
        Destroy = function()
            isDestroyed = true
            currentFarmLockCF = nil
            for _, conn in ipairs(Connections) do
                pcall(function() conn:Disconnect() end)
            end
            table.clear(Connections)

            setFly(false)
            setFarmPhysicsAnchor(false)
            restoreHitboxes()

            -- Restore original engine hooks
            if ManageCd and originalSetCd then
                ManageCd.set_skill_cd = originalSetCd
            end
            if ManageCd and originalFetchCd then
                ManageCd.fetch = originalFetchCd
            end
            if MinigameSettings and originalMinigameGet then
                MinigameSettings.Get = originalMinigameGet
            end
            setFastAttackMode(false)

            clearDrawings(DrawingObjects.Mobs)
            clearDrawings(DrawingObjects.Players)
            clearDrawings(DrawingObjects.Chests)
            clearDrawings(DrawingObjects.Puzzles)
            clearDrawings(DrawingObjects.Special)

            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = 16
                hum.JumpPower = 50
            end

            getgenv().__RAVEN_OUWLAND = nil
        end,
    }

    getgenv().__RAVEN_OUWLAND = ModuleInstance
    return ModuleInstance
end
