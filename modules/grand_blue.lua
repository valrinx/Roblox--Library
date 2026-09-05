-- ═════════════════════════════════════════════════════════════════
-- Grand Blue | Kronos | RAVEN HUB Module
-- PlaceId: 118635363908336 | GameId: 6215986499
-- Experience: Grand Blue
-- ═════════════════════════════════════════════════════════════════

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local HttpService = game:GetService("HttpService")
    local CollectionService = game:GetService("CollectionService")

    local Player = Players.LocalPlayer
    local Camera = workspace.CurrentCamera
    local environment = getgenv and getgenv() or _G

    -- Cleanup old instance
    if type(environment.__KRONOS_GRAND_BLUE) == "table" and type(environment.__KRONOS_GRAND_BLUE.Destroy) == "function" then
        pcall(environment.__KRONOS_GRAND_BLUE.Destroy)
    end

    local running = true
    local threads = {}
    local espObjects = {}
    local savedPosition = nil
    local previousPosition = nil

    local function getRoot(char)
        char = char or Player.Character
        return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char.PrimaryPart)
    end

    local function getHumanoid(char)
        char = char or Player.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    -- ═════════════════════════════════════════════════════════════════
    --   SETTINGS & STATE
    -- ═════════════════════════════════════════════════════════════════

    local settings = {
        -- Main: Level & Quests
        autoFarmLevel = false,
        selectedQuest = "None",
        autoQuest = false,
        autoWorldBossQuest = false,

        -- Specific Mobs
        selectedMobs = {},
        autoFarmSpecific = false,
        autoFarmClosest = false,

        -- Misc / Lifeskills
        autoFishing = false,
        castDistance = 25,
        recastDelay = 1,
        autoMine = false,

        -- Farm Settings: Teleport & Combat
        teleportMethod = "Instant", -- "Instant" or "Tween"
        teleportStyle = "Above",    -- "Above" or "Around"
        tweenSpeed = 180,
        minTweenTime = 10,          -- 10 * 0.01s = 0.10s
        maxTweenTime = 300,         -- 300 * 0.01s = 3.00s
        tweenEasing = "Linear",     -- "Linear", "Sine", "Quad"
        farmDelay = 5,              -- 5 * 0.01s = 0.05s
        lockOn = false,
        fastAttack = true,

        -- Offsets
        aboveHeight = 6,
        aroundRadius = 8,
        aroundHeight = 2,
        aroundSpeed = 240,

        -- Skills
        useSkills = false,
        selectedSkills = {},
        skillDelay = 25,            -- 25 * 0.01s = 0.25s

        -- Weapon
        weaponType = "Melee",       -- "Melee", "Sword", "Fruit"
        autoEquipWeapon = true,

        -- Stats
        selectedStats = { "Health", "Strength", "Agility", "Precision", "Energy", "Willpower" },
        upgradeMode = "Priority",   -- "Priority" or "Balanced"
        autoUpgradeStats = false,
        priority1 = "Strength",
        priority2 = "Health",
        priority3 = "Agility",
        pointsPerCycle = 1,
        upgradeInterval = 3,        -- 3 * 0.1s = 0.3s
        targetStatLevel = 0,

        -- ESP: Enable
        espPlayers = false,
        espMobs = false,
        espBosses = false,
        espNPCs = false,
        espQuestGivers = false,
        espCurrentQuestTargets = false,
        espOres = false,
        espCookingStations = false,

        -- ESP: Settings
        showNames = true,
        showDistance = true,
        showHealth = true,
        showBoxes = true,
        showTracers = false,
        filledHighlight = false,
        maxDistance = 1500,
        textSize = 13,

        -- Teleport Tab Settings
        teleportIsland = "None",
        teleportNPC = "None",
        teleportPlayer = "None",
        travelMethod = "Instant",
        travelTweenSpeed = 220,
    }

    local Events = ReplicatedStorage:WaitForChild("Events", 10)
    local QuestEvents = Events and Events:FindFirstChild("QuestEvents")
    local ToolRemote = Events and Events:FindFirstChild("ToolRemote")
    local SwingEvent = Events and Events:FindFirstChild("SwingEvent")
    local PickaxeHit = Events and Events:FindFirstChild("PickaxeHit")
    local FishingCutscene = Events and Events:FindFirstChild("FishingCutscene")
    local PromptQuest = Events and Events:FindFirstChild("PromptQuest")
    local BatchDialogue = Events and Events:FindFirstChild("BatchDialogue")
    local ClientQuest = Events and Events:FindFirstChild("ClientQuest")
    local InvestStats = QuestEvents and QuestEvents:FindFirstChild("InvestStats")
    local EquipToolRemote = Events and Events:FindFirstChild("EquipToolRemote")

    local Modules = ReplicatedStorage:FindFirstChild("Modules")
    local HeldClient = nil
    if Modules and Modules:FindFirstChild("HeldClient") then
        pcall(function() HeldClient = require(Modules.HeldClient) end)
    end
    local ClientCache = nil
    if Modules and Modules:FindFirstChild("ClientCache") then
        pcall(function() ClientCache = require(Modules.ClientCache) end)
    end

    -- ═════════════════════════════════════════════════════════════════
    --   THREAD CONTROLLER
    -- ═════════════════════════════════════════════════════════════════

    local function startThread(key, fn)
        threads[key] = nil
        task.spawn(function()
            threads[key] = true
            fn(function() return threads[key] == true and running end)
            threads[key] = nil
        end)
    end

    local function stopThread(key)
        threads[key] = nil
    end

    -- ═════════════════════════════════════════════════════════════════
    --   MOVEMENT & TELEPORTATION
    -- ═════════════════════════════════════════════════════════════════

    local currentTween = nil

    local function cancelTween()
        if currentTween then
            pcall(function() currentTween:Cancel() end)
            currentTween = nil
        end
    end

    local function travelTo(targetCFrame, method, customSpeed)
        local root = getRoot()
        if not root then return end

        local useMethod = method or settings.teleportMethod
        local speed = customSpeed or (method == settings.travelMethod and settings.travelTweenSpeed or settings.tweenSpeed)

        if useMethod == "Instant" then
            cancelTween()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.CFrame = targetCFrame
        else
            -- Tween movement
            local distance = (root.Position - targetCFrame.Position).Magnitude
            local calculatedTime = distance / math.max(25, speed)

            local minTime = (settings.minTweenTime or 10) * 0.01
            local maxTime = (settings.maxTweenTime or 300) * 0.01
            local duration = math.clamp(calculatedTime, minTime, maxTime)

            local easingStyle = Enum.EasingStyle.Linear
            if settings.tweenEasing == "Sine" then
                easingStyle = Enum.EasingStyle.Sine
            elseif settings.tweenEasing == "Quad" then
                easingStyle = Enum.EasingStyle.Quad
            end

            cancelTween()
            local tweenInfo = TweenInfo.new(duration, easingStyle, Enum.EasingDirection.Out)
            currentTween = TweenService:Create(root, tweenInfo, { CFrame = targetCFrame })
            currentTween:Play()
            currentTween.Completed:Wait()
            currentTween = nil
        end
    end

    local aroundAngle = 0
    local function getCombatTargetCFrame(targetRoot)
        if not targetRoot then return nil end
        if settings.teleportStyle == "Above" then
            -- Position slightly above and in reach of target
            local pos = targetRoot.Position + Vector3.new(0, math.min(settings.aboveHeight, 2.5), 0) + (targetRoot.CFrame.LookVector * 2.5)
            return CFrame.new(pos, targetRoot.Position)
        else
            -- Around style (keep within melee spherecast range)
            aroundAngle = (aroundAngle + (settings.aroundSpeed * 0.02)) % 360
            local rad = math.rad(aroundAngle)
            local radius = math.min(settings.aroundRadius, 3.5)
            local offsetX = math.cos(rad) * radius
            local offsetZ = math.sin(rad) * radius
            local pos = targetRoot.Position + Vector3.new(offsetX, math.min(settings.aroundHeight, 1.5), offsetZ)
            return CFrame.new(pos, targetRoot.Position)
        end
    end

    -- ═════════════════════════════════════════════════════════════════
    --   COMBAT & WEAPON HANDLING
    -- ═════════════════════════════════════════════════════════════════

    local function equipWeapon()
        if not settings.autoEquipWeapon then return end
        
        -- In Grand Blue, weapons are equipped via HeldClient.RequestEquip
        local weaponName = "Cutlass"
        if ClientCache and ClientCache.Data and ClientCache.Data.Equipped and ClientCache.Data.Equipped.Weapon1 then
            weaponName = ClientCache.Data.Equipped.Weapon1
        end

        if HeldClient and HeldClient.RequestEquip then
            pcall(function()
                HeldClient.RequestEquip(weaponName)
            end)
            return
        end

        -- Fallback to standard tool equip if HeldClient unavailable
        local char = Player.Character
        local bp = Player:FindFirstChild("Backpack")
        if not char or not bp then return end

        local targetType = settings.weaponType:lower()
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then
                return item
            end
        end

        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                local name = item.Name:lower()
                local isMatch = false
                if targetType == "sword" and (name:find("sword") or name:find("cutlass") or name:find("blade") or name:find("katana")) then
                    isMatch = true
                elseif targetType == "fruit" and (name:find("fruit") or name:find("df")) then
                    isMatch = true
                elseif targetType == "melee" and (name:find("combat") or name:find("fist") or name:find("melee")) then
                    isMatch = true
                else
                    isMatch = true
                end

                if isMatch then
                    item.Parent = char
                    task.wait(0.1)
                    return item
                end
            end
        end
    end

    local function attackTarget(targetModel)
        local targetRoot = getRoot(targetModel)
        local targetHum = getHumanoid(targetModel)
        if not targetRoot or not targetHum or targetHum.Health <= 0 then return end

        equipWeapon()

        local root = getRoot()
        local char = Player.Character
        if not root or not char then return end

        if settings.lockOn then
            root.CFrame = CFrame.new(root.Position, targetRoot.Position)
        end

        -- Look for AttackModule in GC or require
        local attackMod = nil
        pcall(function()
            if getgc then
                for _, item in ipairs(getgc(true)) do
                    if type(item) == "table" and rawget(item, "Swing") and rawget(item, "Spherecast") then
                        attackMod = item
                        break
                    end
                end
            end
        end)

        if attackMod and type(attackMod.Swing) == "function" then
            pcall(function()
                attackMod.Swing(char)
            end)
        else
            -- Direct weapon swing replication fallback
            local weaponStyle = "Cutlass"
            if ClientCache and ClientCache.Data and ClientCache.Data.Equipped and ClientCache.Data.Equipped.Weapon1 then
                weaponStyle = ClientCache.Data.Equipped.Weapon1
            end
            if SwingEvent then
                pcall(function()
                    SwingEvent:FireServer(char, weaponStyle, 1, "LightAttack", "Right", 1)
                end)
            end
        end

        if ToolRemote then
            pcall(function() ToolRemote:FireServer("LightAttack", targetModel) end)
        end

        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            pcall(function() tool:Activate() end)
        end
    end

    -- ═════════════════════════════════════════════════════════════════
    --   DYNAMIC DATA FETCHERS
    -- ═════════════════════════════════════════════════════════════════

    local function getAvailableQuests()
        local questList = {}
        local qi = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("QuestInfo")
        local questFolder = qi and qi:FindFirstChild("Quests")
        if questFolder then
          for _, d in ipairs(questFolder:GetDescendants()) do
            if d:IsA("ModuleScript") then
              if not d.Name:lower():find("debug") and not d.Name:lower():find("test") then
                local ok, mod = pcall(require, d)
                if ok and type(mod) == "table" then
                  local isRepeatable = (mod.Type == "Repeatable" or mod.Repeatable == true)
                  local isAxeTyrant = (d.Name == "Axe-Handed Tyrant" or d.Name == "Tyrannical Captain")
                  if isRepeatable or isAxeTyrant then
                    local minLvl = mod.RequiredLevel or 0
                    local maxLvl = minLvl + 5
                    if type(mod.EXPRange) == "table" and #mod.EXPRange >= 2 then
                      minLvl = mod.EXPRange[1]
                      maxLvl = mod.EXPRange[2]
                    end
                    table.insert(questList, {
                      name = d.Name,
                      minLevel = minLvl,
                      maxLevel = maxLvl,
                      displayName = string.format("[%s] [Lv %d-%d]", d.Name, minLvl, maxLvl),
                      module = d
                    })
                  end
                end
              end
            end
          end
        end

        table.sort(questList, function(a, b)
          if a.minLevel == b.minLevel then
            return a.name < b.name
          end
          return a.minLevel < b.minLevel
        end)

        local options = {}
        for _, q in ipairs(questList) do
          table.insert(options, q.displayName)
        end
        return options, questList
    end

    local function findQuestCommandModule(questName)
        local dialogueNPCsFolder = workspace:FindFirstChild("AA IMPORTANT") and workspace["AA IMPORTANT"]:FindFirstChild("DialogueNPCs")
        if not dialogueNPCsFolder then return nil end

        for _, island in ipairs(dialogueNPCsFolder:GetChildren()) do
            for _, npc in ipairs(island:GetChildren()) do
                local dialogue = npc:FindFirstChild("Dialogue")
                if dialogue then
                    for _, node in ipairs(dialogue:GetChildren()) do
                        local cmd = node:FindFirstChild("Command")
                        if cmd and cmd:IsA("ModuleScript") then
                            local ok, content = pcall(function()
                                return decompile and decompile(cmd) or ""
                            end)
                            if ok and type(content) == "string" and content:find(questName, 1, true) then
                                return cmd
                            end
                        end
                    end
                end
            end
        end
        return nil
    end

    local function getAvailableMobs()
        local mobMap = {}
        local wsEntities = workspace:FindFirstChild("Entities")
        if wsEntities then
          for _, e in ipairs(wsEntities:GetChildren()) do
            if e:IsA("Model") and e ~= Player.Character then
              local isPlayer = Players:GetPlayerFromCharacter(e) ~= nil
              if not isPlayer then
                local hum = e:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                  local clean = e.Name:gsub("%s+%d+$", ""):gsub("%d+$", ""):gsub("%s+$", "")
                  if clean ~= "" then
                    mobMap[clean] = true
                  end
                end
              end
            end
          end
        end

        for _, obj in ipairs(workspace:GetDescendants()) do
          if obj.Name:find("Spawn") or obj.Name:find("Marker") then
            local clean = obj.Name:gsub("Spawn", ""):gsub("Marker", ""):gsub("%s+$", ""):gsub("^%s+", "")
            if clean ~= "" and #clean < 25 then
              mobMap[clean] = true
            end
          end
        end

        local mobList = {}
        for name, _ in pairs(mobMap) do
          table.insert(mobList, name)
        end
        table.sort(mobList)
        return mobList
    end

    local function getEquippedSkills()
        local skills = {}
        local rs = ReplicatedStorage:FindFirstChild("Modules")
        local skillsFolder = rs and rs:FindFirstChild("SkillInformation") and rs.SkillInformation:FindFirstChild("Skills")
        if skillsFolder then
          for _, sc in ipairs(skillsFolder:GetChildren()) do
            if sc:IsA("ModuleScript") then
              local ok, mod = pcall(require, sc)
              if ok and type(mod) == "table" and mod.ModuleType == "Tool" then
                table.insert(skills, sc.Name)
              end
            end
          end
        end
        table.sort(skills)
        return skills
    end

    local function getIslandsList()
        local islands = {}
        local isFolder = workspace:FindFirstChild("Islands")
        if isFolder then
          for _, isl in ipairs(isFolder:GetChildren()) do
            table.insert(islands, isl.Name)
          end
        end
        table.sort(islands)
        return islands
    end

    local function getDialogueNPCs()
        local npcNames = {}
        local seen = {}
        local tagged = CollectionService:GetTagged("Dialogue")
        for _, inst in ipairs(tagged) do
          local name = inst:GetAttribute("NPCName") or inst.Name
          name = name:gsub("%s+%d+$", ""):gsub("%d+$", ""):gsub("%s+$", "")
          if not seen[name] and name ~= "" and not name:find("Gate") then
            seen[name] = true
            table.insert(npcNames, name)
          end
        end
        table.sort(npcNames)
        return npcNames
    end

    local function getServerPlayers()
        local pList = {}
        for _, p in ipairs(Players:GetPlayers()) do
          if p ~= Player then
            table.insert(pList, p.Name)
          end
        end
        table.sort(pList)
        return pList
    end

    -- ═════════════════════════════════════════════════════════════════
    --   FARM ENGINES
    -- ═════════════════════════════════════════════════════════════════

    local function findClosestEntity(filterFn)
        local root = getRoot()
        if not root then return nil end
        local bestModel = nil
        local bestDist = math.huge

        local entities = workspace:FindFirstChild("Entities")
        if entities then
          for _, e in ipairs(entities:GetChildren()) do
            if e:IsA("Model") and e ~= Player.Character and not Players:GetPlayerFromCharacter(e) then
              local eRoot = getRoot(e)
              local hum = getHumanoid(e)
              if eRoot and hum and hum.Health > 0 then
                if not filterFn or filterFn(e) then
                  local dist = (root.Position - eRoot.Position).Magnitude
                  if dist < bestDist then
                    bestDist = dist
                    bestModel = e
                  end
                end
              end
            end
          end
        end
        return bestModel
    end

    local function runAutoFarmStep(targetModel)
        if not targetModel then return end
        local tRoot = getRoot(targetModel)
        local tHum = getHumanoid(targetModel)
        if not tRoot or not tHum or tHum.Health <= 0 then return end

        local destCF = getCombatTargetCFrame(tRoot)
        if destCF then
            travelTo(destCF)
            attackTarget(targetModel)
        end
        task.wait((settings.farmDelay or 5) * 0.01)
    end

    -- ═════════════════════════════════════════════════════════════════
    --   ESP SYSTEM
    -- ═════════════════════════════════════════════════════════════════

    local function clearESP()
        for _, item in pairs(espObjects) do
            if item.Highlight then pcall(function() item.Highlight:Destroy() end) end
            if item.Billboard then pcall(function() item.Billboard:Destroy() end) end
        end
        table.clear(espObjects)
    end

    local function createESP(targetInstance, espType, displayName, color)
        if not targetInstance or espObjects[targetInstance] then return end
        local pPart = targetInstance:IsA("Model") and (targetInstance.PrimaryPart or targetInstance:FindFirstChild("HumanoidRootPart") or targetInstance:FindFirstChildWhichIsA("BasePart")) or targetInstance
        if not pPart or not pPart:IsA("BasePart") then return end

        local bb = Instance.new("BillboardGui")
        bb.Name = "KronosESP"
        bb.Adornee = pPart
        bb.AlwaysOnTop = true
        bb.Size = UDim2.new(0, 150, 0, 40)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.Parent = pPart

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, 0, 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
        textLabel.TextSize = settings.textSize or 13
        textLabel.Font = Enum.Font.GothamBold
        textLabel.TextStrokeTransparency = 0
        textLabel.Text = displayName or targetInstance.Name
        textLabel.Parent = bb

        local hl = nil
        if settings.filledHighlight then
            hl = Instance.new("Highlight")
            hl.Adornee = targetInstance
            hl.FillColor = color or Color3.fromRGB(255, 255, 255)
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.5
            hl.OutlineTransparency = 0
            hl.Parent = targetInstance
        end

        espObjects[targetInstance] = {
            Billboard = bb,
            Highlight = hl,
            Label = textLabel,
            Part = pPart,
            Type = espType,
            Name = displayName or targetInstance.Name
        }
    end

    local function updateESPLabels()
        local root = getRoot()
        local myPos = root and root.Position or Vector3.zero
        for inst, data in pairs(espObjects) do
            if not inst or not inst.Parent or not data.Part or not data.Part.Parent then
                if data.Billboard then pcall(function() data.Billboard:Destroy() end) end
                if data.Highlight then pcall(function() data.Highlight:Destroy() end) end
                espObjects[inst] = nil
            else
                local dist = math.floor((myPos - data.Part.Position).Magnitude)
                if dist > (settings.maxDistance or 1500) then
                    data.Billboard.Enabled = false
                    if data.Highlight then data.Highlight.Enabled = false end
                else
                    data.Billboard.Enabled = true
                    if data.Highlight then data.Highlight.Enabled = true end

                    local str = ""
                    if settings.showNames then str = data.Name end
                    if settings.showHealth and inst:IsA("Model") then
                        local hum = inst:FindFirstChildOfClass("Humanoid")
                        if hum then
                            str = str .. string.format(" [%d/%d]", math.floor(hum.Health), math.floor(hum.MaxHealth))
                        end
                    end
                    if settings.showDistance then
                        str = str .. " (" .. dist .. "m)"
                    end
                    data.Label.Text = str
                end
            end
        end
    end

    -- ═════════════════════════════════════════════════════════════════
    --   UI TABS & CONTROLS
    -- ═════════════════════════════════════════════════════════════════

    -- ─── TAB 1: Main (Farm & lifeskills) ───
    local MainTab = Window:CreateTab("Main", "farm")
    MainTab:CreateSection("Farm & lifeskills")

    MainTab:CreateSection("Automation")

    MainTab:CreateToggle({
        Name = "Auto Farm Level",
        CurrentValue = false,
        Flag = "KronosAutoFarmLevel",
        Callback = function(v)
            settings.autoFarmLevel = v
            if v then
                startThread("autoFarmLevel", function(isActive)
                    while isActive() do
                        local target = findClosestEntity(function(e)
                            local clean = e.Name:gsub("%s+%d+$", ""):gsub("%d+$", ""):gsub("%s+$", "")
                            return not clean:find("Civilian")
                        end)
                        if target then
                            runAutoFarmStep(target)
                        else
                            task.wait(0.5)
                        end
                    end
                end)
            else
                stopThread("autoFarmLevel")
            end
        end,
    })

    MainTab:CreateSection("Quest")

    local dynamicQuestOptions, dynamicQuestData = getAvailableQuests()
    local QuestDropdown = MainTab:CreateDropdown({
        Name = "Select Quest",
        Options = #dynamicQuestOptions > 0 and dynamicQuestOptions or {"None"},
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "KronosSelectQuest",
        Callback = function(value)
            settings.selectedQuest = type(value) == "table" and value[1] or value
        end,
    })

    MainTab:CreateButton({
        Name = "Refresh Quests",
        Callback = function()
            local opts = getAvailableQuests()
            if #opts > 0 then
                QuestDropdown:Refresh(opts, true)
            end
        end,
    })

    MainTab:CreateToggle({
        Name = "Auto Quest",
        CurrentValue = false,
        Flag = "KronosAutoQuest",
        Callback = function(v)
            settings.autoQuest = v
            if v then
                startThread("autoQuest", function(isActive)
                    local cachedCmd = nil
                    local lastQuest = nil

                    while isActive() do
                        if settings.selectedQuest and settings.selectedQuest ~= "None" then
                            local qName = settings.selectedQuest:match("%[(.-)%]") or settings.selectedQuest
                            if qName ~= lastQuest then
                                lastQuest = qName
                                cachedCmd = findQuestCommandModule(qName)
                            end

                            -- Check if quest is already active
                            local hasQuest = false
                            local activeQuestObj = nil
                            if ClientCache and ClientCache.Data and ClientCache.Data.Quests then
                                for _, q in ipairs(ClientCache.Data.Quests) do
                                    if q.Name == qName or q.Title == qName then
                                        hasQuest = true
                                        activeQuestObj = q
                                        break
                                    end
                                end
                            end

                            if not hasQuest then
                                -- Accept Quest via BatchDialogue
                                if cachedCmd and BatchDialogue then
                                    pcall(function()
                                        BatchDialogue:InvokeServer("Run", { cachedCmd }, {})
                                    end)
                                elseif PromptQuest then
                                    pcall(function() PromptQuest:InvokeServer(qName) end)
                                end
                            else
                                -- If quest is active, check if Stage 2 (Return/Talk) is ready
                                if activeQuestObj and activeQuestObj.Stages and #activeQuestObj.Stages >= 2 then
                                    local stage2 = activeQuestObj.Stages[2]
                                    if stage2 and stage2.Conditions and stage2.Conditions[1] then
                                        local cond = stage2.Conditions[1]
                                        if cond.Type == "Talk" and cond.Target and cond.Target.Name then
                                            local npcName = cond.Target.Name
                                            if ClientQuest then
                                                pcall(function()
                                                    ClientQuest:FireServer("Talk", npcName)
                                                end)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        task.wait(1.5)
                    end
                end)
            else
                stopThread("autoQuest")
            end
        end,
    })

    MainTab:CreateSection("In Testing")

    MainTab:CreateToggle({
        Name = "Auto World Boss Quest",
        CurrentValue = false,
        Flag = "KronosAutoWorldBossQuest",
        Callback = function(v)
            settings.autoWorldBossQuest = v
            if v then
                startThread("autoWorldBossQuest", function(isActive)
                    while isActive() do
                        local boss = findClosestEntity(function(e)
                            local hum = getHumanoid(e)
                            return hum and hum.MaxHealth > 1000
                        end)
                        if boss then runAutoFarmStep(boss) end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("autoWorldBossQuest")
            end
        end,
    })

    MainTab:CreateSection("Specific")

    local dynamicMobs = getAvailableMobs()
    local MobsDropdown = MainTab:CreateDropdown({
        Name = "Select Mobs",
        Options = #dynamicMobs > 0 and dynamicMobs or {"None"},
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "KronosSelectMobs",
        Callback = function(value)
            settings.selectedMobs = type(value) == "table" and value or {value}
        end,
    })

    MainTab:CreateButton({
        Name = "Refresh Mobs",
        Callback = function()
            local mList = getAvailableMobs()
            if #mList > 0 then
                MobsDropdown:Refresh(mList, true)
            end
        end,
    })

    MainTab:CreateToggle({
        Name = "Auto Farm Specific",
        CurrentValue = false,
        Flag = "KronosAutoFarmSpecific",
        Callback = function(v)
            settings.autoFarmSpecific = v
            if v then
                startThread("autoFarmSpecific", function(isActive)
                    while isActive() do
                        local target = findClosestEntity(function(e)
                            local clean = e.Name:gsub("%s+%d+$", ""):gsub("%d+$", ""):gsub("%s+$", "")
                            return table.find(settings.selectedMobs, clean) ~= nil
                        end)
                        if target then
                            runAutoFarmStep(target)
                        else
                            task.wait(0.5)
                        end
                    end
                end)
            else
                stopThread("autoFarmSpecific")
            end
        end,
    })

    MainTab:CreateToggle({
        Name = "Auto Farm Closest",
        CurrentValue = false,
        Flag = "KronosAutoFarmClosest",
        Callback = function(v)
            settings.autoFarmClosest = v
            if v then
                startThread("autoFarmClosest", function(isActive)
                    while isActive() do
                        local target = findClosestEntity(function(e)
                            local clean = e.Name:gsub("%s+%d+$", ""):gsub("%d+$", ""):gsub("%s+$", "")
                            return not clean:find("Civilian")
                        end)
                        if target then runAutoFarmStep(target) else task.wait(0.5) end
                    end
                end)
            else
                stopThread("autoFarmClosest")
            end
        end,
    })

    -- ─── TAB 2: Misc (Lifeskills) ───
    local MiscTab = Window:CreateTab("Misc", "tools")
    MiscTab:CreateSection("Lifeskills")

    MiscTab:CreateSection("Fishing")

    MiscTab:CreateToggle({
        Name = "Auto Fishing",
        CurrentValue = false,
        Flag = "KronosAutoFishing",
        Callback = function(v)
            settings.autoFishing = v
            if v then
                startThread("autoFishing", function(isActive)
                    while isActive() do
                        if FishingCutscene then
                            pcall(function() FishingCutscene:FireServer(settings.castDistance) end)
                        end
                        task.wait(settings.recastDelay)
                    end
                end)
            else
                stopThread("autoFishing")
            end
        end,
    })

    MiscTab:CreateSlider({
        Name = "Cast Distance",
        Range = {5, 25},
        Increment = 1,
        CurrentValue = 25,
        Flag = "KronosCastDistance",
        Callback = function(v) settings.castDistance = tonumber(v) or 25 end,
    })

    MiscTab:CreateSlider({
        Name = "Recast Delay",
        Range = {1, 5},
        Increment = 1,
        CurrentValue = 1,
        Flag = "KronosRecastDelay",
        Callback = function(v) settings.recastDelay = tonumber(v) or 1 end,
    })

    MiscTab:CreateSection("Mining")

    MiscTab:CreateToggle({
        Name = "Auto Mine",
        CurrentValue = false,
        Flag = "KronosAutoMine",
        Callback = function(v)
            settings.autoMine = v
            if v then
                startThread("autoMine", function(isActive)
                    while isActive() do
                        local root = getRoot()
                        local oresFolder = workspace:FindFirstChild("Ores")
                        if oresFolder and root then
                            for _, ore in ipairs(oresFolder:GetChildren()) do
                                if ore:IsA("BasePart") or ore:IsA("Model") then
                                    local oPos = ore:IsA("BasePart") and ore.Position or ore:GetPivot().Position
                                    travelTo(CFrame.new(oPos + Vector3.new(0, 3, 0)))
                                    if PickaxeHit then
                                        PickaxeHit:FireServer(ore)
                                    end
                                    task.wait(0.3)
                                    break
                                end
                            end
                        end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("autoMine")
            end
        end,
    })

    -- ─── TAB 3: Settings (Farm settings) ───
    local SettingsTab = Window:CreateTab("Settings", "settings")
    SettingsTab:CreateSection("Farm settings")

    SettingsTab:CreateSection("Main")

    SettingsTab:CreateDropdown({
        Name = "Select Teleport Method",
        Options = {"Instant", "Tween"},
        CurrentOption = {"Instant"},
        MultipleOptions = false,
        Flag = "KronosTeleportMethod",
        Callback = function(v) settings.teleportMethod = type(v) == "table" and v[1] or v end,
    })

    SettingsTab:CreateDropdown({
        Name = "Select Teleport Style",
        Options = {"Above", "Around"},
        CurrentOption = {"Above"},
        MultipleOptions = false,
        Flag = "KronosTeleportStyle",
        Callback = function(v) settings.teleportStyle = type(v) == "table" and v[1] or v end,
    })

    SettingsTab:CreateSlider({
        Name = "Tween Speed",
        Range = {25, 500},
        Increment = 5,
        CurrentValue = 180,
        Suffix = " studs/s",
        Flag = "KronosTweenSpeed",
        Callback = function(v) settings.tweenSpeed = tonumber(v) or 180 end,
    })

    SettingsTab:CreateSlider({
        Name = "Minimum Tween Time",
        Range = {5, 100},
        Increment = 1,
        CurrentValue = 10,
        Suffix = " × 0.01s",
        Flag = "KronosMinTweenTime",
        Callback = function(v) settings.minTweenTime = tonumber(v) or 10 end,
    })

    SettingsTab:CreateSlider({
        Name = "Maximum Tween Time",
        Range = {50, 1000},
        Increment = 10,
        CurrentValue = 300,
        Suffix = " × 0.01s",
        Flag = "KronosMaxTweenTime",
        Callback = function(v) settings.maxTweenTime = tonumber(v) or 300 end,
    })

    SettingsTab:CreateDropdown({
        Name = "Tween Easing",
        Options = {"Linear", "Sine", "Quad"},
        CurrentOption = {"Linear"},
        MultipleOptions = false,
        Flag = "KronosTweenEasing",
        Callback = function(v) settings.tweenEasing = type(v) == "table" and v[1] or v end,
    })

    SettingsTab:CreateSlider({
        Name = "Farm Delay",
        Range = {2, 50},
        Increment = 1,
        CurrentValue = 5,
        Suffix = " × 0.01s",
        Flag = "KronosFarmDelay",
        Callback = function(v) settings.farmDelay = tonumber(v) or 5 end,
    })

    SettingsTab:CreateToggle({
        Name = "Lock On",
        CurrentValue = false,
        Flag = "KronosLockOn",
        Callback = function(v) settings.lockOn = v end,
    })

    SettingsTab:CreateToggle({
        Name = "Fast Attack",
        CurrentValue = true,
        Flag = "KronosFastAttack",
        Callback = function(v) settings.fastAttack = v end,
    })

    SettingsTab:CreateSection("Offsets")

    SettingsTab:CreateSlider({
        Name = "Above Height",
        Range = {3, 30},
        Increment = 1,
        CurrentValue = 6,
        Suffix = " studs",
        Flag = "KronosAboveHeight",
        Callback = function(v) settings.aboveHeight = tonumber(v) or 6 end,
    })

    SettingsTab:CreateSlider({
        Name = "Around Radius",
        Range = {3, 25},
        Increment = 1,
        CurrentValue = 8,
        Suffix = " studs",
        Flag = "KronosAroundRadius",
        Callback = function(v) settings.aroundRadius = tonumber(v) or 8 end,
    })

    SettingsTab:CreateSlider({
        Name = "Around Height",
        Range = {-5, 20},
        Increment = 1,
        CurrentValue = 2,
        Suffix = " studs",
        Flag = "KronosAroundHeight",
        Callback = function(v) settings.aroundHeight = tonumber(v) or 2 end,
    })

    SettingsTab:CreateSlider({
        Name = "Around Speed",
        Range = {10, 240},
        Increment = 5,
        CurrentValue = 240,
        Suffix = " deg/s",
        Flag = "KronosAroundSpeed",
        Callback = function(v) settings.aroundSpeed = tonumber(v) or 240 end,
    })

    SettingsTab:CreateSection("Skills")

    SettingsTab:CreateToggle({
        Name = "Use Skills",
        CurrentValue = false,
        Flag = "KronosUseSkills",
        Callback = function(v)
            settings.useSkills = v
            if v then
                startThread("useSkills", function(isActive)
                    while isActive() do
                        local skillsToUse = #settings.selectedSkills > 0 and settings.selectedSkills or getEquippedSkills()
                        for _, skName in ipairs(skillsToUse) do
                            if not isActive() then break end
                            local char = Player.Character
                            local tool = char and char:FindFirstChild(skName) or (Player:FindFirstChild("Backpack") and Player.Backpack:FindFirstChild(skName))
                            if tool then
                                if tool.Parent ~= char then tool.Parent = char task.wait(0.05) end
                                pcall(function() tool:Activate() end)
                                task.wait((settings.skillDelay or 25) * 0.01)
                            end
                        end
                        task.wait(0.5)
                    end
                end)
            else
                stopThread("useSkills")
            end
        end,
    })

    local dynamicSkills = getEquippedSkills()
    local SkillsDropdown = SettingsTab:CreateDropdown({
        Name = "Select Skills",
        Options = #dynamicSkills > 0 and dynamicSkills or {"None"},
        CurrentOption = {},
        MultipleOptions = true,
        Flag = "KronosSelectSkills",
        Callback = function(v) settings.selectedSkills = type(v) == "table" and v or {v} end,
    })

    SettingsTab:CreateButton({
        Name = "Refresh Skills",
        Callback = function()
            local sList = getEquippedSkills()
            if #sList > 0 then
                SkillsDropdown:Refresh(sList, true)
            end
        end,
    })

    SettingsTab:CreateSlider({
        Name = "Skill Delay",
        Range = {10, 200},
        Increment = 5,
        CurrentValue = 25,
        Suffix = " × 0.01s",
        Flag = "KronosSkillDelay",
        Callback = function(v) settings.skillDelay = tonumber(v) or 25 end,
    })

    SettingsTab:CreateSection("Weapon")

    SettingsTab:CreateDropdown({
        Name = "Weapon Type",
        Options = {"Melee", "Sword", "Fruit"},
        CurrentOption = {"Melee"},
        MultipleOptions = false,
        Flag = "KronosWeaponType",
        Callback = function(v) settings.weaponType = type(v) == "table" and v[1] or v end,
    })

    SettingsTab:CreateToggle({
        Name = "Auto Equip Weapon",
        CurrentValue = true,
        Flag = "KronosAutoEquipWeapon",
        Callback = function(v) settings.autoEquipWeapon = v end,
    })

    -- ─── TAB 4: Stats (Stat points) ───
    local StatsTab = Window:CreateTab("Stats", "player")
    StatsTab:CreateSection("Stat points")

    StatsTab:CreateSection("Auto stats")

    local STAT_NAMES = {"Health", "Strength", "Agility", "Precision", "Energy", "Willpower"}

    local function upgradeStat(statName, amount)
        amount = amount or settings.pointsPerCycle or 1
        if InvestStats then
            pcall(function() InvestStats:FireServer(statName, amount) end)
        end
    end

    StatsTab:CreateDropdown({
        Name = "Select Stats",
        Options = STAT_NAMES,
        CurrentOption = STAT_NAMES,
        MultipleOptions = true,
        Flag = "KronosSelectStats",
        Callback = function(v) settings.selectedStats = type(v) == "table" and v or {v} end,
    })

    StatsTab:CreateDropdown({
        Name = "Upgrade Mode",
        Options = {"Priority", "Balanced"},
        CurrentOption = {"Priority"},
        MultipleOptions = false,
        Flag = "KronosUpgradeMode",
        Callback = function(v) settings.upgradeMode = type(v) == "table" and v[1] or v end,
    })

    StatsTab:CreateToggle({
        Name = "Auto Upgrade Stats",
        CurrentValue = false,
        Flag = "KronosAutoUpgradeStats",
        Callback = function(v)
            settings.autoUpgradeStats = v
            if v then
                startThread("autoUpgradeStats", function(isActive)
                    while isActive() do
                        if settings.upgradeMode == "Priority" then
                            upgradeStat(settings.priority1)
                            task.wait((settings.upgradeInterval or 3) * 0.1)
                            upgradeStat(settings.priority2)
                            task.wait((settings.upgradeInterval or 3) * 0.1)
                            upgradeStat(settings.priority3)
                        else
                            for _, s in ipairs(settings.selectedStats) do
                                upgradeStat(s)
                                task.wait((settings.upgradeInterval or 3) * 0.1)
                            end
                        end
                        task.wait(1.0)
                    end
                end)
            else
                stopThread("autoUpgradeStats")
            end
        end,
    })

    StatsTab:CreateButton({
        Name = "Upgrade Selected Once",
        Callback = function()
            for _, s in ipairs(settings.selectedStats) do
                upgradeStat(s, settings.pointsPerCycle or 1)
            end
        end,
    })

    StatsTab:CreateSection("Priority")

    StatsTab:CreateDropdown({
        Name = "Priority 1",
        Options = STAT_NAMES,
        CurrentOption = {"Strength"},
        MultipleOptions = false,
        Flag = "KronosPriority1",
        Callback = function(v) settings.priority1 = type(v) == "table" and v[1] or v end,
    })

    StatsTab:CreateDropdown({
        Name = "Priority 2",
        Options = STAT_NAMES,
        CurrentOption = {"Health"},
        MultipleOptions = false,
        Flag = "KronosPriority2",
        Callback = function(v) settings.priority2 = type(v) == "table" and v[1] or v end,
    })

    StatsTab:CreateDropdown({
        Name = "Priority 3",
        Options = STAT_NAMES,
        CurrentOption = {"Agility"},
        MultipleOptions = false,
        Flag = "KronosPriority3",
        Callback = function(v) settings.priority3 = type(v) == "table" and v[1] or v end,
    })

    StatsTab:CreateSlider({
        Name = "Points Per Cycle",
        Range = {1, 10},
        Increment = 1,
        CurrentValue = 1,
        Suffix = " point",
        Flag = "KronosPointsPerCycle",
        Callback = function(v) settings.pointsPerCycle = tonumber(v) or 1 end,
    })

    StatsTab:CreateSlider({
        Name = "Upgrade Interval",
        Range = {1, 20},
        Increment = 1,
        CurrentValue = 3,
        Suffix = " × 0.1s",
        Flag = "KronosUpgradeInterval",
        Callback = function(v) settings.upgradeInterval = tonumber(v) or 3 end,
    })

    StatsTab:CreateSlider({
        Name = "Target Stat Level",
        Range = {0, 500},
        Increment = 5,
        CurrentValue = 0,
        Suffix = " (0 = No Cap)",
        Flag = "KronosTargetStatLevel",
        Callback = function(v) settings.targetStatLevel = tonumber(v) or 0 end,
    })

    -- ─── TAB 5: Esp (ESP options) ───
    local EspTab = Window:CreateTab("Esp", "esp")
    EspTab:CreateSection("ESP options")

    EspTab:CreateSection("Entities")

    EspTab:CreateToggle({
        Name = "Players Esp",
        CurrentValue = false,
        Flag = "KronosEspPlayers",
        Callback = function(v)
            settings.espPlayers = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateToggle({
        Name = "Mobs Esp",
        CurrentValue = false,
        Flag = "KronosEspMobs",
        Callback = function(v)
            settings.espMobs = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateToggle({
        Name = "Bosses Esp",
        CurrentValue = false,
        Flag = "KronosEspBosses",
        Callback = function(v)
            settings.espBosses = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateToggle({
        Name = "NPCs Esp",
        CurrentValue = false,
        Flag = "KronosEspNPCs",
        Callback = function(v)
            settings.espNPCs = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateSection("Quest")

    EspTab:CreateToggle({
        Name = "Quest Givers Esp",
        CurrentValue = false,
        Flag = "KronosEspQuestGivers",
        Callback = function(v)
            settings.espQuestGivers = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateToggle({
        Name = "Current Quest Targets Esp",
        CurrentValue = false,
        Flag = "KronosEspQuestTargets",
        Callback = function(v)
            settings.espCurrentQuestTargets = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateSection("World")

    EspTab:CreateToggle({
        Name = "Ores Esp",
        CurrentValue = false,
        Flag = "KronosEspOres",
        Callback = function(v)
            settings.espOres = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateToggle({
        Name = "Cooking Stations Esp",
        CurrentValue = false,
        Flag = "KronosEspCookingStations",
        Callback = function(v)
            settings.espCookingStations = v
            if not v then clearESP() end
        end,
    })

    EspTab:CreateSection("Display")

    EspTab:CreateToggle({
        Name = "Show Names",
        CurrentValue = true,
        Flag = "KronosShowNames",
        Callback = function(v) settings.showNames = v end,
    })

    EspTab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Flag = "KronosShowDistance",
        Callback = function(v) settings.showDistance = v end,
    })

    EspTab:CreateToggle({
        Name = "Show Health",
        CurrentValue = true,
        Flag = "KronosShowHealth",
        Callback = function(v) settings.showHealth = v end,
    })

    EspTab:CreateToggle({
        Name = "Show Boxes",
        CurrentValue = true,
        Flag = "KronosShowBoxes",
        Callback = function(v) settings.showBoxes = v end,
    })

    EspTab:CreateToggle({
        Name = "Show Tracers",
        CurrentValue = false,
        Flag = "KronosShowTracers",
        Callback = function(v) settings.showTracers = v end,
    })

    EspTab:CreateSection("Style")

    EspTab:CreateToggle({
        Name = "Filled Highlight",
        CurrentValue = false,
        Flag = "KronosFilledHighlight",
        Callback = function(v)
            settings.filledHighlight = v
            clearESP()
        end,
    })

    EspTab:CreateSlider({
        Name = "Max Distance",
        Range = {100, 5000},
        Increment = 50,
        CurrentValue = 1500,
        Suffix = " studs",
        Flag = "KronosMaxDistance",
        Callback = function(v) settings.maxDistance = tonumber(v) or 1500 end,
    })

    EspTab:CreateSlider({
        Name = "Text Size",
        Range = {10, 22},
        Increment = 1,
        CurrentValue = 13,
        Flag = "KronosTextSize",
        Callback = function(v)
            settings.textSize = tonumber(v) or 13
            for _, d in pairs(espObjects) do
                if d.Label then d.Label.TextSize = settings.textSize end
            end
        end,
    })

    startThread("espLoop", function(isActive)
        while isActive() do
            if settings.espPlayers then
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= Player and p.Character then
                        createESP(p.Character, "Player", p.Name, Color3.fromRGB(0, 255, 120))
                    end
                end
            end

            if settings.espMobs or settings.espBosses then
                local entities = workspace:FindFirstChild("Entities")
                if entities then
                    for _, e in ipairs(entities:GetChildren()) do
                        if e:IsA("Model") and not Players:GetPlayerFromCharacter(e) then
                            local hum = getHumanoid(e)
                            if hum and hum.Health > 0 then
                                if hum.MaxHealth > 500 and settings.espBosses then
                                    createESP(e, "Boss", "👑 " .. e.Name, Color3.fromRGB(255, 50, 50))
                                elseif settings.espMobs then
                                    createESP(e, "Mob", e.Name, Color3.fromRGB(255, 200, 50))
                                end
                            end
                        end
                    end
                end
            end

            if settings.espNPCs or settings.espQuestGivers then
                for _, inst in ipairs(CollectionService:GetTagged("Dialogue")) do
                    local name = inst:GetAttribute("NPCName") or inst.Name
                    createESP(inst, "NPC", "💬 " .. name, Color3.fromRGB(120, 200, 255))
                end
            end

            if settings.espCookingStations then
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d.Name:lower():find("kitchen") or d.Name:lower():find("cook") then
                        createESP(d, "Cooking", "🍳 Cooking Station", Color3.fromRGB(255, 150, 0))
                    end
                end
            end

            updateESPLabels()
            task.wait(0.2)
        end
    end)

    -- ─── TAB 6: Teleport (Move quickly) ───
    local TeleportTab = Window:CreateTab("Teleport", "movement")
    TeleportTab:CreateSection("Move quickly")

    TeleportTab:CreateSection("Islands")

    local dynamicIslands = getIslandsList()
    local IslandDropdown = TeleportTab:CreateDropdown({
        Name = "Select Island",
        Options = #dynamicIslands > 0 and dynamicIslands or {"None"},
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "KronosSelectIsland",
        Callback = function(v) settings.teleportIsland = type(v) == "table" and v[1] or v end,
    })

    TeleportTab:CreateButton({
        Name = "Refresh Islands",
        Callback = function()
            local isList = getIslandsList()
            if #isList > 0 then IslandDropdown:Refresh(isList, true) end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To Island",
        Callback = function()
            local isFolder = workspace:FindFirstChild("Islands")
            local targetIsland = isFolder and isFolder:FindFirstChild(settings.teleportIsland)
            if targetIsland then
                local spawnPart = targetIsland:FindFirstChild("SpawnLocation") or targetIsland:FindFirstChildWhichIsA("BasePart", true)
                if spawnPart then
                    travelTo(CFrame.new(spawnPart.Position + Vector3.new(0, 5, 0)), settings.travelMethod, settings.travelTweenSpeed)
                end
            end
        end,
    })

    TeleportTab:CreateSection("NPCs")

    local dynamicNPCs = getDialogueNPCs()
    local NPCDropdown = TeleportTab:CreateDropdown({
        Name = "Select NPC",
        Options = #dynamicNPCs > 0 and dynamicNPCs or {"None"},
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "KronosSelectNPC",
        Callback = function(v) settings.teleportNPC = type(v) == "table" and v[1] or v end,
    })

    TeleportTab:CreateButton({
        Name = "Refresh NPCs",
        Callback = function()
            local nList = getDialogueNPCs()
            if #nList > 0 then NPCDropdown:Refresh(nList, true) end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To NPC",
        Callback = function()
            for _, inst in ipairs(CollectionService:GetTagged("Dialogue")) do
                local name = inst:GetAttribute("NPCName") or inst.Name
                if name:find(settings.teleportNPC) then
                    local pPart = inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")) or inst
                    if pPart and pPart:IsA("BasePart") then
                        travelTo(CFrame.new(pPart.Position + Vector3.new(0, 3, 0)), settings.travelMethod, settings.travelTweenSpeed)
                        break
                    end
                end
            end
        end,
    })

    TeleportTab:CreateSection("Quest travel")

    TeleportTab:CreateButton({
        Name = "Teleport To Quest Giver",
        Callback = function()
            for _, inst in ipairs(CollectionService:GetTagged("Dialogue")) do
                if inst:FindFirstChild("Head") and inst.Head:FindFirstChild("QuestIndicator") then
                    local pPart = inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")) or inst
                    if pPart then
                        travelTo(CFrame.new(pPart.Position + Vector3.new(0, 3, 0)), settings.travelMethod, settings.travelTweenSpeed)
                        break
                    end
                end
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To Quest Target",
        Callback = function()
            local target = findClosestEntity()
            if target then
                local tRoot = getRoot(target)
                if tRoot then travelTo(CFrame.new(tRoot.Position + Vector3.new(0, 5, 0)), settings.travelMethod, settings.travelTweenSpeed) end
            end
        end,
    })

    TeleportTab:CreateSection("Quick")

    TeleportTab:CreateButton({
        Name = "Teleport To Closest Mob",
        Callback = function()
            local target = findClosestEntity(function(e)
                local hum = getHumanoid(e)
                return hum and hum.Health > 0 and hum.MaxHealth <= 500
            end)
            if target then
                local tRoot = getRoot(target)
                if tRoot then travelTo(CFrame.new(tRoot.Position + Vector3.new(0, 5, 0)), settings.travelMethod, settings.travelTweenSpeed) end
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To Closest Boss",
        Callback = function()
            local target = findClosestEntity(function(e)
                local hum = getHumanoid(e)
                return hum and hum.Health > 0 and hum.MaxHealth > 500
            end)
            if target then
                local tRoot = getRoot(target)
                if tRoot then travelTo(CFrame.new(tRoot.Position + Vector3.new(0, 5, 0)), settings.travelMethod, settings.travelTweenSpeed) end
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To Closest Ore",
        Callback = function()
            local oresFolder = workspace:FindFirstChild("Ores")
            if oresFolder then
                local ore = oresFolder:FindFirstChildWhichIsA("BasePart", true)
                if ore then travelTo(CFrame.new(ore.Position + Vector3.new(0, 4, 0)), settings.travelMethod, settings.travelTweenSpeed) end
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To Closest Cooking Station",
        Callback = function()
            for _, d in ipairs(workspace:GetDescendants()) do
                if d.Name:lower():find("kitchen") or d.Name:lower():find("cook") then
                    local p = d:IsA("BasePart") and d.Position or d:GetPivot().Position
                    travelTo(CFrame.new(p + Vector3.new(0, 4, 0)), settings.travelMethod, settings.travelTweenSpeed)
                    break
                end
            end
        end,
    })

    TeleportTab:CreateSection("Players")

    local dynamicPlayers = getServerPlayers()
    local PlayerDropdown = TeleportTab:CreateDropdown({
        Name = "Select Player",
        Options = #dynamicPlayers > 0 and dynamicPlayers or {"None"},
        CurrentOption = {"None"},
        MultipleOptions = false,
        Flag = "KronosSelectPlayer",
        Callback = function(v) settings.teleportPlayer = type(v) == "table" and v[1] or v end,
    })

    TeleportTab:CreateButton({
        Name = "Refresh Players",
        Callback = function()
            local pList = getServerPlayers()
            if #pList > 0 then PlayerDropdown:Refresh(pList, true) end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To Player",
        Callback = function()
            local targetP = Players:FindFirstChild(settings.teleportPlayer)
            if targetP and targetP.Character then
                local tRoot = getRoot(targetP.Character)
                if tRoot then
                    travelTo(CFrame.new(tRoot.Position + Vector3.new(0, 3, 0)), settings.travelMethod, settings.travelTweenSpeed)
                end
            end
        end,
    })

    TeleportTab:CreateSection("Saved spots")

    TeleportTab:CreateButton({
        Name = "Save Position",
        Callback = function()
            local root = getRoot()
            if root then savedPosition = root.CFrame end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport To Saved Position",
        Callback = function()
            if savedPosition then
                local root = getRoot()
                if root then previousPosition = root.CFrame end
                travelTo(savedPosition, settings.travelMethod, settings.travelTweenSpeed)
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "Teleport Back",
        Callback = function()
            if previousPosition then
                travelTo(previousPosition, settings.travelMethod, settings.travelTweenSpeed)
            end
        end,
    })

    TeleportTab:CreateSection("Movement")

    TeleportTab:CreateDropdown({
        Name = "Teleport Method",
        Options = {"Instant", "Tween"},
        CurrentOption = {"Instant"},
        MultipleOptions = false,
        Flag = "KronosTravelMethod",
        Callback = function(v) settings.travelMethod = type(v) == "table" and v[1] or v end,
    })

    TeleportTab:CreateSlider({
        Name = "Tween Speed",
        Range = {25, 500},
        Increment = 5,
        CurrentValue = 220,
        Suffix = " studs/s",
        Flag = "KronosTravelTweenSpeed",
        Callback = function(v) settings.travelTweenSpeed = tonumber(v) or 220 end,
    })

    -- ─── TAB 7: Settings (Built-in MacLib Settings) ───
    local MacSettingsTab = Window:CreateTab("Settings", "settings")
    MacSettingsTab:CreateSection("Configuration")
    pcall(function()
        if type(MacSettingsTab.InsertConfigSection) == "function" then
            MacSettingsTab:InsertConfigSection("Left")
        end
    end)

    -- ═════════════════════════════════════════════════════════════════
    --   LIFECYCLE & CLEANUP
    -- ═════════════════════════════════════════════════════════════════

    local cleanInstance = {
        Destroy = function()
            running = false
            for k, _ in pairs(threads) do
                threads[k] = nil
            end
            cancelTween()
            clearESP()
        end,
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(cleanInstance.Destroy)
    end

    environment.__KRONOS_GRAND_BLUE = cleanInstance
    return cleanInstance
end
