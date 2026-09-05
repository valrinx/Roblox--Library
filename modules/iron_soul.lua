--[[
    RAVEN HUB | Iron Soul: Dungeon
    Lobby PlaceId: 117533937949084 | Starless Forest: 116456628154258
    GameId: 9910245722 | Version: v1.6.2
]]
return function(Window, runtimeInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local CoreGui = game:GetService("CoreGui")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local CollectionService = game:GetService("CollectionService")
    local LP = Players.LocalPlayer
    local running = true
    local connections, visuals = {}, {}
    local selectedTarget, spectating = nil, false
    local controllerCache = nil
    local directController = nil
    local controllerModuleRef = nil
    local controllerCharacter = nil
    local currentEnemy = nil
    local attackBusy = false
    local skillActionBusy = false
    local farmWorkerToken = 0
    local combatWorkerToken = 0
    local collectionWorkerToken = 0
    local autoPlayWorkerToken = 0
    local autoWeaponWorkerToken = 0
    local autoSellWorkerToken = 0
    local autoDungeonWorkerToken = 0
    local autoDungeonLastAttempt = 0
    local autoDungeonStatus = "Disabled"
    local autoDungeonStatusLabel = nil
    local Framework, DataUtil, EquipmentUtil, ForgeUtil, RarityTiers, TranslationUtil, MaterialUtil
    local originalSetWalkSpeed = nil
    local dodgeLockUntil, dodgeSafePosition = 0, nil
    local redzoneDanger = false
    local collectedChests, collectedEggs = setmetatable({}, {__mode="k"}), setmetatable({}, {__mode="k"})
    local collectionCandidatesCache = {chests={}, eggs={}, expires={chests=0, eggs=0}}
    local collectionNextAt = 0
    local CollectingChests, CollectingEggs = false, false

    pcall(function()
        local old = getgenv().__RAVEN_IRON_SOUL
        if old and type(old.Destroy) == "function" then old.Destroy() end
    end)

    local settings = {
        enemyEsp = true, maxDistance = 1500, showHp = true,
        targetMode = "Nearest", stickyTarget = true,
        autoFarm = false, autoUseSkill = false,
        distanceX = 0, distanceY = 0, distanceZ = 10, pitch = 45,
        autoDodge = false, dodgeMode = "Air", dodgeMargin = 3, dodgeDistance = 16, dodgeVertical = 50, dodgeCooldown = 0.55, dodgeHold = 1.4,
        autoPlayAgain = false, autoSwitchWeapon = false,
        autoEnterDungeon = false, autoDungeonWorld = "World1", autoDungeonDifficulty = 1,
        bringMobs = false,
        autoCollectChests = false, autoCollectEggs = false,
        changeWalkSpeed = false, walkSpeed = false, walkSpeedValue = 16,
        cameraChange = false, allowCameraChange = false, cameraDistance = 70,
        autoSell = false, sellEquipmentRarities = {}, sellOres = {}, sellCrystals = {},
    }

    local guiRoot = (type(gethui) == "function" and gethui()) or CoreGui
    local folder = Instance.new("Folder")
    folder.Name = "RavenIronSoul"
    folder.Parent = guiRoot
    local TargetHighlight = Instance.new("Highlight")
    TargetHighlight.Name = "AutofarmTarget"
    TargetHighlight.Enabled = false
    TargetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    TargetHighlight.FillTransparency = 0.5
    TargetHighlight.FillColor = Color3.fromRGB(0, 0, 255)
    TargetHighlight.OutlineTransparency = 0
    TargetHighlight.OutlineColor = Color3.fromRGB(0, 200, 40)
    TargetHighlight.Parent = folder

    local function connect(signal, callback)
        local c = signal:Connect(callback); table.insert(connections, c); return c
    end
    local function myRoot()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end
    local function getPart(model)
        return model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true))
    end
    local function getHumanoid(model)
        return model and (model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true))
    end
    local function distance(part)
        local root = myRoot(); return root and part and (part.Position-root.Position).Magnitude or math.huge
    end
    local function enemyName(model)
        local id = tostring(model:GetAttribute("NpcId") or "Enemy")
        return id:gsub("^NPC_", ""):gsub("_", " ")
    end
    local function SetCurrentEnemy(enemy)
        currentEnemy=enemy and getPart(enemy) or nil
        TargetHighlight.Adornee=enemy
        TargetHighlight.Enabled=enemy~=nil
    end
    local function roundState()
        local cfg=game:GetService("ReplicatedStorage"):FindFirstChild("GameRoundCfg")
        local round=cfg and tonumber(cfg:GetAttribute("GameRound")); local complete=cfg and tonumber(cfg:GetAttribute("GameRoundComplete"))
        return round,complete
    end
    local function tapKey(keyCode)
        VirtualInputManager:SendKeyEvent(true,keyCode,false,game)
        task.delay(.03,function() pcall(function() VirtualInputManager:SendKeyEvent(false,keyCode,false,game) end) end)
    end
    local function guiObjectVisible(object)
        if not object or not object.Parent then return false end
        if object:IsA("GuiObject") and not object.Visible then return false end
        local parent=object.Parent
        while parent and parent~=game do
            if parent:IsA("GuiObject") and not parent.Visible then return false end
            if parent:IsA("ScreenGui") and not parent.Enabled then return false end
            parent=parent.Parent
        end
        return true
    end
    local function buttonKeyCode(button)
        local key=button and button:FindFirstChild("Key",true)
        local text=key and key:FindFirstChildWhichIsA("TextLabel",true)
        local value=text and tostring(text.Text or ""):upper()
        if not value or value=="" then return nil end
        local enumOk,enumValue=pcall(function() return Enum.KeyCode[value] end)
        return enumOk and enumValue or nil
    end
    local function activateGuiButton(button)
        if not button or not button:IsA("GuiButton") or not guiObjectVisible(button) then return false end
        if type(firesignal)=="function" then
            local ok=pcall(function() firesignal(button.MouseButton1Down) end)
            if ok then
                task.wait(0.02)
                pcall(function() firesignal(button.MouseButton1Up) end)
                return true
            end
        end
        local pos=button.AbsolutePosition+button.AbsoluteSize/2
        local clicked=pcall(function()
            VirtualInputManager:SendMouseMoveEvent(pos.X,pos.Y,game)
            VirtualInputManager:SendMouseButtonEvent(pos.X,pos.Y,0,true,game,0)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(pos.X,pos.Y,0,false,game,0)
        end)
        if clicked then return true end
        local ok=pcall(function() button:Activate() end)
        if ok then return true end
        local keyCode=buttonKeyCode(button)
        if keyCode then tapKey(keyCode); return true end
        return false
    end
    local function buildController()
        local character=LP.Character
        if not character then return nil end
        local manager=character:FindFirstChild("LocalControlMgr")
        local ActionFolder=manager and manager:FindFirstChild("Action")
        local controllerModule=manager and manager:FindFirstChild("Controller")
        if not ActionFolder or not controllerModule then return nil end
        local ActionModules={}
        for _,module in ipairs(ActionFolder:GetChildren()) do
            if module:IsA("ModuleScript") then
                local ok,action=pcall(require,module)
                if ok then ActionModules[module.Name]=action end
            end
        end
        local ok,Controller=pcall(require,controllerModule)
        if not ok or type(Controller)~="table" or type(Controller.new)~="function" then return nil end
        local created,instance=pcall(function() return Controller.new(character,ActionModules) end)
        if not created then return nil end
        directController,controllerCharacter=instance,character
        controllerModuleRef=Controller
        controllerCache=instance
        return instance
    end
    local function getController()
        if directController and controllerCharacter==LP.Character and type(directController.PerformAction)=="function" then return directController end
        directController=nil; controllerCharacter=nil; controllerModuleRef=nil
        local built=buildController(); if built then return built end
        if controllerCache and rawget(controllerCache,"Character")==LP.Character then return controllerCache end
        controllerCache=nil
        if type(getgc)~="function" then return nil end
        for _,value in ipairs(getgc(true)) do
            if type(value)=="table" and rawget(value,"Character")==LP.Character and type(rawget(value,"ActionModules"))=="table" and type(value.PerformAction)=="function" then
                controllerCache=value; break
            end
        end
        return controllerCache
    end
    local useReadySkills
    local function Attack(bool)
        bool=bool or false
        if attackBusy then return false end
        attackBusy=true
        local controller=getController()
        local ok=false
        if controller then ok=pcall(function() controller:PerformAction("BaseAttack") end) end
        if ok then
            task.wait()
            if running then pcall(function() controller:StopAction("BaseAttack") end) end
        else
            local camera=workspace.CurrentCamera; local size=camera and camera.ViewportSize or Vector2.new(960,540)
            pcall(function() VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,true,game,0) end)
            task.wait(.03)
            pcall(function() VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,false,game,0) end)
            ok=true
        end
        if bool and running then task.spawn(useReadySkills) end
        attackBusy=false
        return ok
    end
    local function stopAttack()
        local controller=getController()
        if controller then pcall(function() controller:StopAction("BaseAttack") end) end
    end
    local skillOrder={"Skill1","Skill2","SkillU","SkillAW"}
    local function getSkillButtons()
        local gui=LP:FindFirstChild("PlayerGui"); local input=gui and gui:FindFirstChild("ScreenInput")
        local pc=input and input:FindFirstChild("PCInput"); local skills=pc and pc:FindFirstChild("Skills")
        if not skills then return nil end
        local result={}
        for _,name in ipairs(skillOrder) do
            local button=skills:FindFirstChild(name)
            if button then result[name]=button end
        end
        result.SwitchWpn=skills:FindFirstChild("SwitchWpn")
        return result
    end
    local function skillIsReady(button,name)
        if not button or not guiObjectVisible(button) or button:GetAttribute("OnCD")==true then return false end
        local cool=button:FindFirstChild("Cool")
        if cool and cool:IsA("GuiObject") and cool.Visible then return false end
        return name~="SkillU" or button:GetAttribute("FullCharge")==true
    end
    local function performSkill(button,name)
        local controller=getController()
        if controller then
            local ok=pcall(function() controller:PerformAction(name) end)
            if ok then return true end
        end
        return activateGuiButton(button)
    end
    local function useAllReadySkills()
        if skillActionBusy then return false end
        skillActionBusy=true
        local buttons=getSkillButtons()
        if not buttons then skillActionBusy=false; return false end
        local used=false
        for _,name in ipairs(skillOrder) do
            local button=buttons[name]
            if skillIsReady(button,name) and performSkill(button,name) then
                used=true
                task.wait(0.05)
            end
        end
        skillActionBusy=false
        return used
    end
    useReadySkills = function()
        useAllReadySkills()
    end
    local function getCurrentWeaponSlot(buttons)
        local switch=buttons and buttons.SwitchWpn
        local weapon2=switch and switch:FindFirstChild("Weapon2")
        if weapon2 then return guiObjectVisible(weapon2) and 2 or 1 end
        if DataUtil then
            local ok,data=pcall(function() return DataUtil:GetPlayerData(LP) end)
            local slot=ok and data and data.Equipment and data.Equipment.CurWeaponSlot
            if slot=="Weapon2" or slot=="ExtraWeapon" then return 2 end
        end
        return 1
    end
    local function hasSecondWeapon(buttons)
        if DataUtil then
            local ok,data=pcall(function() return DataUtil:GetPlayerData(LP) end)
            local slots=ok and data and data.Equipment and data.Equipment.EquipSlots
            if slots then return slots.Weapon2~=nil end
        end
        local switch=buttons and buttons.SwitchWpn
        local weapon2=switch and switch:FindFirstChild("Weapon2")
        local image=weapon2 and weapon2:FindFirstChildWhichIsA("ImageLabel",true)
        return image and image.Image~=""
    end
    local function switchWeapon(buttons,expectedSlot)
        local switch=buttons and buttons.SwitchWpn
        if not switch or not guiObjectVisible(switch) or getCurrentWeaponSlot(buttons)~=expectedSlot then return false end
        local keyCode=buttonKeyCode(switch)
        if keyCode then
            tapKey(keyCode)
            local deadline=os.clock()+1.2
            repeat task.wait(0.05) until not running or getCurrentWeaponSlot(buttons)~=expectedSlot or os.clock()>=deadline
            if getCurrentWeaponSlot(buttons)~=expectedSlot then return true end
        end
        local candidates={switch,switch:FindFirstChild("Switch")}
        for _,button in ipairs(candidates) do
            if activateGuiButton(button) then
                local deadline=os.clock()+1.2
                repeat
                    task.wait(0.05)
                until not running or getCurrentWeaponSlot(buttons)~=expectedSlot or os.clock()>=deadline
                if getCurrentWeaponSlot(buttons)~=expectedSlot then return true end
            end
        end
        if keyCode then
            tapKey(keyCode)
            local deadline=os.clock()+1.2
            repeat task.wait(0.05) until not running or getCurrentWeaponSlot(buttons)~=expectedSlot or os.clock()>=deadline
        end
        return getCurrentWeaponSlot(buttons)~=expectedSlot
    end
    local function runAutoWeaponWorker()
        autoWeaponWorkerToken=autoWeaponWorkerToken+1
        local token=autoWeaponWorkerToken
        task.spawn(function()
            local hasSecond=false
            local nextWeaponDataAt=0
            while running and token==autoWeaponWorkerToken do
                if settings.autoSwitchWeapon then
                    local buttons=getSkillButtons()
                    if buttons and os.clock()>=nextWeaponDataAt then
                        hasSecond=hasSecondWeapon(buttons)
                        nextWeaponDataAt=os.clock()+0.75
                    end
                    if buttons and hasSecond then
                        local currentSlot=getCurrentWeaponSlot(buttons)
                        if useAllReadySkills() then
                            task.wait(0.1)
                            if currentSlot == 1 then
                                if switchWeapon(buttons,1) then currentSlot = 2 end
                            elseif currentSlot == 2 then
                                if switchWeapon(buttons,2) then currentSlot = 1 end
                            end
                            task.wait(0.15)
                        else
                            task.wait(0.1)
                        end
                    else
                        task.wait(0.5)
                    end
                else
                    task.wait(0.25)
                end
            end
        end)
    end

    -- Framework integration (from Potassium reference).  Loading a game
    -- ModuleScript can yield; defer it until after all MacLib tabs have been
    -- built so the loader thread retains its Plugin capability.
    local function loadFramework()
        if Framework then return true end
        local replicated=game:GetService("ReplicatedStorage")
        local frameworkModule=replicated:FindFirstChild("Framework")
        if not frameworkModule then return false end
        local ok, loaded=pcall(require,frameworkModule)
        if not ok or type(loaded)~="table" then return false end
        Framework=loaded
        local modules=Framework.Modules or {}
        DataUtil=modules.DataUtil
        EquipmentUtil=modules.EquipmentUtil
        ForgeUtil=modules.ForgeUtil
        RarityTiers=modules.RarityTiers
        TranslationUtil=modules.TranslationUtil
        MaterialUtil=modules.MaterialUtil
        return true
    end
    local function getRarityTiers()
        loadFramework()
        if RarityTiers and RarityTiers.Tiers then
            local t = {}
            for _, v in ipairs(RarityTiers.Tiers) do table.insert(t, v.Name) end
            if #t > 0 then return t end
        end
        return {"Common","Uncommon","Rare","Epic","Legendary","Mythic","Secret","Heavenly","Pinnacle"}
    end
    local function getRarityName(rarity)
        if not RarityTiers then loadFramework() end
        if not RarityTiers or not RarityTiers.Tiers then return "Unknown" end
        return RarityTiers.Tiers[rarity] and RarityTiers.Tiers[rarity].Name or "Unknown"
    end
    local function getEquipment()
        loadFramework()
        if not DataUtil or not EquipmentUtil then return {} end
        local result = {}
        local ok, playerData = pcall(function() return DataUtil:GetPlayerData(LP) end)
        if not ok or not playerData then return result end
        local owned = playerData.Equipment and playerData.Equipment.Owned
        if not owned then return result end
        local equipped = (playerData.Equipment and playerData.Equipment.Equipped) or {}
        for uuid, itemData in pairs(owned) do
            local isEquipped = equipped[uuid] == true
            local def = EquipmentUtil:GetDef(itemData.ID)
            if def then
                local name = TranslationUtil and TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID)) or def.ID
                local rarity = EquipmentUtil:GetOreRarity(itemData.MaxOre)
                table.insert(result, { UUID = uuid, ID = itemData.ID, Name = name, Rarity = getRarityName(rarity), Type = itemData.Type, Equipped = isEquipped, Level = EquipmentUtil:GetLvByInfo(itemData, def) })
            end
        end
        return result
    end
    local function getAllOreNames()
        loadFramework()
        local names = {}
        if ForgeUtil and TranslationUtil and type(debug) == "table" and type(debug.getupvalues) == "function" then
            pcall(function()
                for _, uv in ipairs(debug.getupvalues(ForgeUtil.GetDef)) do
                    if type(uv) == "table" and uv.Hexbane then
                        for _, def in pairs(uv) do
                            if type(def) == "table" and def.ID then
                                local name = TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID))
                                if name and not table.find(names, name) then table.insert(names, name) end
                            end
                        end
                    end
                end
            end)
        end
        if #names == 0 and DataUtil and ForgeUtil and TranslationUtil then
            local ok, pData = pcall(function() return DataUtil:GetPlayerData(LP) end)
            if ok and pData and pData.Ores then
                for oreId, _ in pairs(pData.Ores) do
                    local def = ForgeUtil:GetDef(oreId)
                    if def then
                        local name = TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID))
                        if name and not table.find(names, name) then table.insert(names, name) end
                    end
                end
            end
        end
        table.sort(names)
        return names
    end
    local function getAllCrystalNames()
        loadFramework()
        local names = {}
        if MaterialUtil and TranslationUtil and type(debug) == "table" and type(debug.getupvalues) == "function" then
            pcall(function()
                for _, uv in ipairs(debug.getupvalues(MaterialUtil.GetDef)) do
                    if type(uv) == "table" and uv.CrystalPrism then
                        for _, def in pairs(uv) do
                            if type(def) == "table" and def.ID then
                                local name = TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID))
                                if name and not table.find(names, name) then table.insert(names, name) end
                            end
                        end
                    end
                end
            end)
        end
        if #names == 0 and DataUtil and MaterialUtil and TranslationUtil then
            local ok, pData = pcall(function() return DataUtil:GetPlayerData(LP) end)
            if ok and pData and pData.Crystals then
                for crystalId, _ in pairs(pData.Crystals) do
                    local def = MaterialUtil:GetDef(crystalId)
                    if def then
                        local name = TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID))
                        if name and not table.find(names, name) then table.insert(names, name) end
                    end
                end
            end
        end
        table.sort(names)
        return names
    end
    local function getOres()
        loadFramework()
        if not DataUtil or not ForgeUtil or not TranslationUtil then return {} end
        local result = {}
        local ok, playerData = pcall(function() return DataUtil:GetPlayerData(LP) end)
        if not ok or not playerData or not playerData.Ores then return result end
        for oreId, amount in pairs(playerData.Ores) do
            local def = ForgeUtil:GetDef(oreId)
            if def then
                local name = TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID))
                local rarity = RarityTiers and RarityTiers.Tiers[def.Rarity] and RarityTiers.Tiers[def.Rarity].Name or "Unknown"
                table.insert(result, { ID = oreId, Name = name, Amount = amount, Rarity = rarity })
            end
        end
        return result
    end
    local function getCrystals()
        loadFramework()
        if not DataUtil or not MaterialUtil or not TranslationUtil then return {} end
        local result = {}
        local ok, playerData = pcall(function() return DataUtil:GetPlayerData(LP) end)
        if not ok or not playerData or not playerData.Crystals then return result end
        for crystalId, amount in pairs(playerData.Crystals) do
            local def = MaterialUtil:GetDef(crystalId)
            if def then
                local name = TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID))
                local rarity = RarityTiers and RarityTiers.Tiers[def.Rarity] and RarityTiers.Tiers[def.Rarity].Name or "Unknown"
                table.insert(result, { ID = crystalId, Name = name, Amount = amount, Rarity = rarity })
            end
        end
        return result
    end
    local function sellEquipmentByRarity(rarities)
        loadFramework()
        if not EquipmentUtil then return end
        local items = getEquipment()
        for _, item in ipairs(items) do
            if not item.Equipped then
                for _, r in ipairs(rarities) do
                    if item.Rarity == r then
                        pcall(function()
                            game:GetService("ReplicatedStorage").Framework.Gameplay.EquipmentSystem.EquipmentRE:FireServer("Sell", { item.UUID })
                        end)
                        task.wait(0.1)
                        break
                    end
                end
            end
        end
    end
    local function sellOres(oreNames)
        loadFramework()
        if not ForgeUtil then return end
        local ores = getOres()
        local toSell = {}
        for _, ore in ipairs(ores) do
            for _, name in ipairs(oreNames) do
                if ore.Name == name then toSell[ore.ID] = math.max(1, tonumber(ore.Amount) or 1); break end
            end
        end
        if next(toSell) then
            pcall(function()
                game:GetService("ReplicatedStorage").Framework.Gameplay.EquipmentSystem.ForgeRF:InvokeServer("Sell", toSell)
            end)
        end
    end
    local function sellCrystals(crystalNames)
        loadFramework()
        if not MaterialUtil then return end
        local crystals = getCrystals()
        local toSell = {}
        for _, c in ipairs(crystals) do
            for _, name in ipairs(crystalNames) do
                if c.Name == name then toSell[c.ID] = math.max(1, tonumber(c.Amount) or 1); break end
            end
        end
        if next(toSell) then
            pcall(function()
                game:GetService("ReplicatedStorage").Framework.Gameplay.EquipmentSystem.MaterialUtil.RemoteEvent:FireServer("Sell", toSell, {})
            end)
        end
    end
    local function interactableRoot(model)
        if not model then return nil end
        local root=model:FindFirstChild("Root")
        if root and root:IsA("BasePart") then return root end
        root=model:FindFirstChild("Root",true)
        if root and root:IsA("BasePart") then return root end
        return getPart(model)
    end
    local function interactionPrompt(model, root)
        local prompt=root and root:FindFirstChildWhichIsA("ProximityPrompt", true)
        if not prompt and model then prompt=model:FindFirstChildWhichIsA("ProximityPrompt", true) end
        return prompt
    end
    local function hasTouchTransmitter(part)
        return part and (part:FindFirstChildOfClass("TouchTransmitter") or part:FindFirstChild("TouchInterest", true)) ~= nil
    end
    local function isDragonEggModel(model)
        if not model or not model:IsA("Model") then return false end
        local tagged=false
        pcall(function() tagged=CollectionService:HasTag(model,"DragonEgg") end)
        return tagged or model.Name=="DragonEgg" or model:FindFirstChild("DragonEgg")~=nil
    end
    local function isChestModel(model)
        if not model or not model:IsA("Model") then return false end
        local tagged=false
        pcall(function() tagged=CollectionService:HasTag(model,"TreasureChest") or CollectionService:HasTag(model,"Chest") end)
        return tagged or string.lower(model.Name):find("chest",1,true)~=nil or model:FindFirstChild("Chest")~=nil
    end
    local function collectionCandidates(kind)
        local now=os.clock()
        if now<(collectionCandidatesCache.expires[kind] or 0) then return collectionCandidatesCache[kind] end
        local result={}; local seen=setmetatable({}, {__mode="k"})
        local function visit(value)
            if not value or not value:IsA("Model") or seen[value] then return end
            seen[value]=true
            if kind=="chests" then
                if isChestModel(value) then table.insert(result,value) end
            elseif isDragonEggModel(value) then
                table.insert(result,value)
            end
        end
        local function scan(container)
            if not container then return end
            visit(container)
            for _,value in ipairs(container:GetDescendants()) do visit(value) end
        end
        if kind=="chests" then
            scan(workspace:FindFirstChild("TreasureChests"))
            -- Both containers can exist at once; scanning World only when the
            -- first container is empty misses valid chests in mixed layouts.
            scan(workspace:FindFirstChild("World"))
            for _,value in ipairs(CollectionService:GetTagged("TreasureChest")) do visit(value) end
            for _,value in ipairs(CollectionService:GetTagged("Chest")) do visit(value) end
        end
        if kind=="eggs" then
            scan(workspace:FindFirstChild("DragonEggs"))
            for _,value in ipairs(CollectionService:GetTagged("DragonEgg")) do visit(value) end
        end
        for _,value in ipairs(workspace:GetChildren()) do
            if value:IsA("Model") then visit(value) end
        end
        collectionCandidatesCache[kind]=result; collectionCandidatesCache.expires[kind]=now+0.35
        return result
    end
    local function activateCollectable(model, root)
        local prompt=interactionPrompt(model,root)
        if prompt and prompt.Enabled and type(fireproximityprompt)=="function" then
            pcall(fireproximityprompt,prompt)
            return true
        end
        if root and hasTouchTransmitter(root) and type(firetouchinterest)=="function" then
            pcall(firetouchinterest,myRoot(),root,0); pcall(firetouchinterest,myRoot(),root,1)
            return true
        end
        return prompt==nil
    end
    -- Chests consume one BaseAttack per hit.  Keep this bounded so a stale or
    -- replicated HitCount cannot trap the worker on one chest forever.
    local CHEST_HIT_LIMIT = 3
    local function chestHitCount(model, root)
        local value=model and model:GetAttribute("HitCount")
        if value==nil and root then value=root:GetAttribute("HitCount") end
        return tonumber(value) or 0
    end
    local function hitChest(model, root)
        if not model or not root or not model.Parent or not root.Parent then return false end
        -- Wait for an earlier attack to finish; otherwise Attack's busy guard
        -- would silently drop one of the three required hits.
        local deadline=os.clock()+0.75
        while attackBusy and os.clock()<deadline do task.wait() end
        if attackBusy then return false end
        Attack(false)
        deadline=os.clock()+0.75
        while attackBusy and os.clock()<deadline do task.wait() end
        return not attackBusy
    end
    local function collectChests()
        local root=myRoot(); if not root then return end
        local finalDistance=CFrame.new(settings.distanceX,settings.distanceY,settings.distanceZ)*CFrame.Angles(math.rad(settings.pitch),math.rad(180),0)
        -- Potassium's chest contract scans the live workspace models and keeps
        -- the player on a chest until its HitCount reaches zero.
        for _,v in ipairs(workspace:GetChildren()) do
            if isChestModel(v) then
                local chestRoot=v:FindFirstChild("Root") or interactableRoot(v)
                local hitCount=chestHitCount(v,chestRoot)
                if chestRoot and hitCount and hitCount>0 then
                    CollectingChests=true
                    local chestHits=0
                    while settings.autoCollectChests and hitCount>0 and chestHits<CHEST_HIT_LIMIT do
                        if not root.Parent or not v.Parent or not chestRoot.Parent then break end
                        root.CFrame=chestRoot.CFrame*finalDistance
                        if not hitChest(v,chestRoot) then break end
                        chestHits=chestHits+1
                        task.wait()
                        hitCount=chestHitCount(v,chestRoot)
                    end
                    CollectingChests=false
                    collectedChests[v]=nil
                    collectionNextAt=os.clock()+0.1
                    return
                end
            end
        end
        -- Keep the reference-compatible fallback for servers that nest chests.
        local now=os.clock(); if now<collectionNextAt then return end
        for _,v in ipairs(collectionCandidates("chests")) do
            if v.Parent and not collectedChests[v] then
                local chestRoot=interactableRoot(v); local prompt=interactionPrompt(v,chestRoot)
                if chestRoot and (not prompt or prompt.Enabled) then
                    local hitCount=chestHitCount(v,chestRoot)
                    if hitCount>0 then
                        CollectingChests=true
                        local chestHits=0
                        while settings.autoCollectChests and hitCount>0 and chestHits<CHEST_HIT_LIMIT do
                            if not root.Parent or not v.Parent or not chestRoot.Parent then break end
                            root.CFrame=chestRoot.CFrame*finalDistance
                            if not hitChest(v,chestRoot) then break end
                            chestHits=chestHits+1
                            task.wait()
                            hitCount=chestHitCount(v,chestRoot)
                        end
                        CollectingChests=false
                    else
                        root.CFrame=chestRoot.CFrame*finalDistance
                        activateCollectable(v,chestRoot)
                    end
                    collectedChests[v]=true; collectionNextAt=now+0.2
                    return
                end
            end
        end
    end
    local function collectDragonEggs()
        local now=os.clock(); if now<collectionNextAt then return end
        local root=myRoot(); if not root then return end
        -- Potassium's egg contract is a direct workspace scan.  The visible
        -- EggModel is the teleport target, while the parent Root owns the
        -- interaction prompt.
        for _,v in ipairs(workspace:GetChildren()) do
            local dragonEgg=v:IsA("Model") and v:FindFirstChild("DragonEgg")
            local eggModel=dragonEgg and dragonEgg:FindFirstChild("EggModel")
            local visualRoot=eggModel and eggModel:FindFirstChild("Root")
            local interactRoot=v:FindFirstChild("Root") or (dragonEgg and dragonEgg:FindFirstChild("Root"))
            local active=v:GetAttribute("Active")
            if active==nil and dragonEgg then active=dragonEgg:GetAttribute("Active") end
            local prompt=interactionPrompt(v,interactRoot)
            if dragonEgg and visualRoot and interactRoot and active~=true and (not prompt or prompt.Enabled) then
                CollectingEggs=true
                root.CFrame=visualRoot.CFrame
                task.wait(0.1)
                local exactPrompt=interactRoot:FindFirstChild("Interact_ProximityPrompt") or prompt
                if exactPrompt and type(fireproximityprompt)=="function" then pcall(fireproximityprompt,exactPrompt) end
                CollectingEggs=false
                collectionNextAt=os.clock()+0.15
                return
            end
        end
        -- Fallback for builds that expose DragonEgg as the top-level model.
        for _,v in ipairs(collectionCandidates("eggs")) do
            if v.Parent and not collectedEggs[v] then
                local interactRoot=v:FindFirstChild("Root")
                if not (interactRoot and interactRoot:IsA("BasePart")) then interactRoot=interactableRoot(v) end
                local visualModel=v:FindFirstChild("EggModel",true); local visualRoot=visualModel and visualModel:FindFirstChild("Root") or interactRoot
                local prompt=interactionPrompt(v,interactRoot)
                local active=v:GetAttribute("Active")
                if active~=true and interactRoot and visualRoot and visualRoot:IsA("BasePart") and (not prompt or prompt.Enabled) then
                    root.CFrame=visualRoot.CFrame*CFrame.new(0,2,0)
                    activateCollectable(v,interactRoot); collectedEggs[v]=true; collectionNextAt=now+0.2
                    return
                end
            end
        end
    end
    local function clearWhiteEffect()
        local playerGui=LP:FindFirstChildOfClass("PlayerGui")
        local design=playerGui and playerGui:FindFirstChild("ScreenDesign")
        local white=design and design:FindFirstChild("WhiteEffect")
        if white then pcall(function() white:Destroy() end) end
    end

    local LOBBY_PLACE_ID = 117533937949084
    local AUTO_DUNGEON_RETRY = 5
    local function setAutoDungeonStatus(text)
        autoDungeonStatus = tostring(text or "Idle")
        if autoDungeonStatusLabel then
            pcall(function() autoDungeonStatusLabel:Set("Auto Dungeon: " .. autoDungeonStatus) end)
        end
    end
    local function isEmptyMatchRoom(room)
        if not room then return false end
        local playersCount = tonumber(room:GetAttribute("PlayersCount"))
        if playersCount and playersCount > 0 then return false end
        local roomState = room:GetAttribute("RoomState")
        if roomState == nil or roomState == 0 or tostring(roomState) == "Empty" then return true end
        return string.lower(tostring(roomState)) == "empty"
    end
    local function findTouchPart(room)
        local touch = room and (room:FindFirstChild("Touch") or room:FindFirstChild("Touch", true))
        if not touch then return nil end
        if touch:IsA("BasePart") then return touch end
        for _, value in ipairs(touch:GetDescendants()) do
            if value:IsA("BasePart") then return value end
        end
        return nil
    end
    local function findFreeMatchRoom()
        local matchRoom = workspace:FindFirstChild("MatchRoom")
        if not matchRoom then return nil, nil end
        local rooms={}
        for _,room in ipairs(matchRoom:GetChildren()) do
            local index=tonumber(tostring(room.Name):match("^Room(%d+)$"))
            if index then table.insert(rooms,{index=index,room=room}) end
        end
        table.sort(rooms,function(a,b) return a.index<b.index end)
        local modeKnown=false
        for _,entry in ipairs(rooms) do
            if entry.room:GetAttribute("Mode")~=nil then
                modeKnown=true
                break
            end
        end
        for _,entry in ipairs(rooms) do
            local room = entry.room
            local isStory = (not modeKnown) or tostring(room:GetAttribute("Mode"))=="Story"
            local touch = room and isStory and isEmptyMatchRoom(room) and findTouchPart(room)
            if room and touch then return room, touch end
        end
        return nil, nil
    end
    local function touchMatchRoom(room, touch)
        local root=myRoot()
        if not root or not room or not touch or not touch.Parent then return false end
        local targetPos = (room:FindFirstChild("Root") and room.Root.Position + Vector3.new(0, 3, 0)) or (touch.Position + Vector3.new(0, 3, 0))
        root.CFrame = CFrame.new(targetPos)
        root.AssemblyLinearVelocity = Vector3.zero
        if type(firetouchinterest)=="function" then
            pcall(firetouchinterest, root, touch, 0)
            local touchFolder = room:FindFirstChild("Touch")
            if touchFolder and touchFolder:IsA("Folder") or touchFolder:IsA("Model") then
                for _, part in ipairs(touchFolder:GetDescendants()) do
                    if part:IsA("BasePart") and part ~= touch then
                        pcall(firetouchinterest, root, part, 0)
                    end
                end
            end
        end
        return true
    end
    local function guiObjectVisible(object)
        if not object or not object.Parent then return false end
        if object:IsA("GuiObject") and not object.Visible then return false end
        local parent=object.Parent
        while parent and parent~=game do
            if parent:IsA("GuiObject") and not parent.Visible then return false end
            parent=parent.Parent
        end
        return true
    end
    local function getScreenMatch()
        local gui=LP:FindFirstChildOfClass("PlayerGui")
        local main=gui and gui:FindFirstChild("MainGui")
        local screen=main and main:FindFirstChild("ScreenMatch")
        if not screen and gui then screen=gui:FindFirstChild("ScreenMatch",true) end
        return screen
    end
    local function getDungeonMatchCount(screen)
        local countLabel=screen and screen:FindFirstChild("MatchCount",true)
        local count=countLabel and tonumber(countLabel.Text)
        if not count then return 1 end
        return math.max(1,math.floor(count))
    end
    local function findDungeonRemotes()
        local replicated=game:GetService("ReplicatedStorage")
        local framework=replicated:FindFirstChild("Framework")
        local gameplay=framework and framework:FindFirstChild("Gameplay")
        local worldPlace=gameplay and gameplay:FindFirstChild("WorldPlace")
        local worldUtil=worldPlace and worldPlace:FindFirstChild("WorldUtil")
        local worldRemote=worldUtil and worldUtil:FindFirstChild("RemoteEvent")
        local remotes=replicated:FindFirstChild("Remotes")
        local matchRemote=remotes and remotes:FindFirstChild("GameMatchRE")
        return worldRemote, matchRemote
    end
    local function closeDungeonScreen(screen)
        local replicated=game:GetService("ReplicatedStorage")
        local framework=replicated:FindFirstChild("Framework")
        local systems=framework and framework:FindFirstChild("Systems")
        local guiLib=systems and systems:FindFirstChild("GUILib")
        local windowModule=guiLib and guiLib:FindFirstChild("WindowUtil")
        local closed=false
        if windowModule then
            local ok,WindowUtil=pcall(require,windowModule)
            if ok and WindowUtil and type(WindowUtil.Close)=="function" then
                closed=pcall(function() WindowUtil:Close("ScreenMatch") end)
            end
        end
        if not closed and screen then
            pcall(function()
                screen.Visible=false
                screen.Active=false
            end)
        end
    end
    local function requestDungeonEntry(force)
        if not force and not settings.autoEnterDungeon then return false end
        if game.PlaceId~=LOBBY_PLACE_ID then return false end
        local screen=getScreenMatch()
        local inRoomId = LP:GetAttribute("EnterRoomId")
        if not inRoomId and (not screen or not guiObjectVisible(screen)) then
            local room,touch=findFreeMatchRoom()
            if not room or not touch then
                setAutoDungeonStatus("Waiting empty room")
                return false
            end
            setAutoDungeonStatus("Opening " .. room.Name)
            touchMatchRoom(room,touch)
            return false
        end
        local now=os.clock()
        if now-autoDungeonLastAttempt<AUTO_DUNGEON_RETRY then return false end
        local worldRemote,matchRemote=findDungeonRemotes()
        if not worldRemote or not matchRemote then
            setAutoDungeonStatus("Waiting dungeon remotes")
            return false
        end
        autoDungeonLastAttempt=now
        local worldOk=pcall(function()
            worldRemote:FireServer("SelectWorld",settings.autoDungeonWorld,settings.autoDungeonDifficulty)
        end)
        if not worldOk then
            setAutoDungeonStatus("Select failed")
            return false
        end
        task.wait(.35)
        local matchCount=getDungeonMatchCount(screen)
        local sharedStart=nil
        pcall(function()
            if shared and type(shared.ProServer_StartMatch)=="function" then
                sharedStart=shared.ProServer_StartMatch
            end
        end)
        local createOk
        if sharedStart then
            createOk=pcall(sharedStart,settings.autoDungeonWorld,settings.autoDungeonDifficulty)
        else
            createOk=pcall(function()
                matchRemote:FireServer("CreatRoom",settings.autoDungeonWorld,settings.autoDungeonDifficulty,matchCount)
            end)
        end
        setAutoDungeonStatus(createOk and ("Creating " .. settings.autoDungeonWorld .. " / " .. tostring(settings.autoDungeonDifficulty)) or "Create failed")
        return createOk
    end
    local function runAutoDungeonWorker()
        autoDungeonWorkerToken=autoDungeonWorkerToken+1
        local token=autoDungeonWorkerToken
        task.spawn(function()
            while running and token==autoDungeonWorkerToken do
                if game.PlaceId==117533937949084 and settings.autoEnterDungeon then
                    pcall(requestDungeonEntry)
                elseif not settings.autoEnterDungeon then
                    if autoDungeonStatus~="Disabled" then setAutoDungeonStatus("Disabled") end
                elseif game.PlaceId~=117533937949084 then
                    if autoDungeonStatus~="In dungeon" then setAutoDungeonStatus("In dungeon") end
                end
                task.wait(.25)
            end
        end)
    end
    local function runPotassiumAutofarm()
        farmWorkerToken=farmWorkerToken+1
        local token=farmWorkerToken
        task.spawn(function()
            while running and token==farmWorkerToken do
                if game.PlaceId==117533937949084 then
                    SetCurrentEnemy(nil)
                elseif settings.autoFarm then
                    local ok,err=pcall(function()
                        clearWhiteEffect()
                        if CollectingChests then return end
                        if CollectingEggs then return end
                        if not workspace.EnemyNpc:FindFirstChildOfClass("Model") then
                            local root=myRoot()
                            if workspace:GetAttribute("GameMode")=="" then
                                if root then
                                    root.CFrame=CFrame.new(8561.28906,273.670654,-3727.4563,0.589069664,-2.59408957e-08,0.808082283,-6.4901144e-08,1,7.9412942e-08,-0.808082283,-9.92252183e-08,0.589069664)
                                end
                                return
                            end
                            local oldCFrame=root and root.CFrame
                            local respawns=workspace:FindFirstChild("PlayerRespawn")
                            if root and respawns then
                                for _,v in ipairs(respawns:GetChildren()) do
                                    if v:IsA("Part") then
                                        root.CFrame=v.CFrame
                                        task.wait(1)
                                    end
                                end
                                if root.Parent and oldCFrame then root.CFrame=oldCFrame end
                            end
                        end
                        for _,v in ipairs(workspace.EnemyNpc:GetChildren()) do
                            if v:IsA("Model") and v:FindFirstChild("Humanoid") and v.Humanoid.Health>0 and v:FindFirstChild("HumanoidRootPart") then
                                local MaxNum,MaxNum2=1000,100
                                local Counting,Counting2=0,0
                                repeat task.wait()
                                    local FinalDistance=CFrame.new(settings.distanceX,settings.distanceY,settings.distanceZ)*CFrame.Angles(math.rad(0),math.rad(0),math.rad(settings.pitch))
                                    if v:GetAttribute("LevelType")=="Boss" then
                                        FinalDistance=CFrame.new(settings.distanceX*1.5,settings.distanceY*1.5,settings.distanceZ*1.5)*CFrame.Angles(math.rad(0),math.rad(0),math.rad(settings.pitch))
                                    end
                                    local root=myRoot(); local enemyRoot=v:FindFirstChild("HumanoidRootPart")
                                    if root and enemyRoot and (root.Position-enemyRoot.Position).Magnitude<=math.huge then currentEnemy=enemyRoot end
                                    if currentEnemy then SetCurrentEnemy(currentEnemy.Parent) end
                                    Counting=Counting+1
                                    if Counting>MaxNum then
                                        if root and currentEnemy then root.CFrame=currentEnemy.CFrame end
                                        task.wait(.1)
                                        Counting=0
                                        return
                                    end
                                    if root and currentEnemy then root.CFrame=currentEnemy.CFrame*FinalDistance end
                                until not settings.autoFarm or v.Humanoid.Health<=0 or not v:FindFirstChild("HumanoidRootPart")
                            elseif v and v:IsA("Model") and not v:FindFirstChild("HumanoidRootPart") then
                                local root=myRoot(); if root then root.CFrame=v:GetPivot() end
                            end
                        end
                    end)
                    if not ok then warn(err) end
                else
                    SetCurrentEnemy(nil)
                end
                task.wait()
            end
            SetCurrentEnemy(nil)
        end)
    end
    local CAMERA_BACK = 50
    local function runPotassiumCombat()
        combatWorkerToken=combatWorkerToken+1
        local token=combatWorkerToken
        task.spawn(function()
            while running and token==combatWorkerToken do
                if game.PlaceId~=117533937949084 and settings.autoFarm then
                    local ok,err=pcall(function()
                        task.spawn(function()
                            for _,v in ipairs(workspace.EnemyNpc:GetChildren()) do
                                local enemyRoot=v:IsA("Model") and v:FindFirstChild("HumanoidRootPart")
                                local humanoid=v:IsA("Model") and v:FindFirstChild("Humanoid")
                                if currentEnemy and enemyRoot and humanoid and humanoid.Health>0 and (currentEnemy.Position-enemyRoot.Position).Magnitude<=100 and settings.bringMobs then
                                    task.wait()
                                    enemyRoot.CFrame=currentEnemy.CFrame
                                end
                            end
                        end)
                        task.spawn(function()
                            for _,v in ipairs(workspace:GetChildren()) do
                                local dragonEgg=v:FindFirstChild("DragonEgg")
                                local eggModel=dragonEgg and dragonEgg:FindFirstChild("EggModel")
                                local eggRoot=eggModel and eggModel:FindFirstChild("Root")
                                local interactRoot=v:FindFirstChild("Root")
                                if dragonEgg and eggRoot and interactRoot and not v:GetAttribute("Active") then
                                    CollectingEggs=true
                                    local root=myRoot()
                                    if root then root.CFrame=eggRoot.CFrame end
                                    task.wait(0.1)
                                    local prompt=interactRoot:FindFirstChild("Interact_ProximityPrompt") or interactionPrompt(v,interactRoot)
                                    if prompt and type(fireproximityprompt)=="function" then pcall(fireproximityprompt,prompt) end
                                    CollectingEggs=false
                                end
                            end
                        end)
                        task.spawn(function()
                            local success2,err2=pcall(function()
                                if not (settings.allowCameraChange or settings.cameraChange) then return end
                                local character=LP.Character; local root=character and character:FindFirstChild("HumanoidRootPart")
                                local camera=workspace.CurrentCamera
                                if not root or not camera then return end
                                camera.CameraType=Enum.CameraType.Scriptable
                                camera.CameraSubject=nil
                                local targetPosition=root.Position
                                local cameraPosition=targetPosition+Vector3.new(0,settings.cameraDistance,CAMERA_BACK)
                                TweenService:Create(camera,TweenInfo.new(.3,Enum.EasingStyle.Quad),{CFrame=CFrame.lookAt(cameraPosition,targetPosition)}):Play()
                                camera.Focus=CFrame.new(targetPosition)
                            end)
                            if not success2 then warn("Camera: ",err2) end
                        end)
                        task.spawn(function() Attack(settings.autoUseSkill) end)
                    end)
                    if not ok then warn(err) end
                end
                task.wait()
            end
        end)
    end
    local function runCollectionWorker()
        collectionWorkerToken=collectionWorkerToken+1
        local token=collectionWorkerToken
        task.spawn(function()
            while running and token==collectionWorkerToken do
                if settings.autoCollectChests then pcall(collectChests) end
                task.wait()
            end
        end)
        task.spawn(function()
            while running and token==collectionWorkerToken do
                if settings.autoCollectEggs and not settings.autoFarm then pcall(collectDragonEggs) end
                task.wait()
            end
        end)
    end
    local function runAutoPlayAgainWorker()
        autoPlayWorkerToken=autoPlayWorkerToken+1
        local token=autoPlayWorkerToken
        task.spawn(function()
            while running and token==autoPlayWorkerToken do
                if settings.autoPlayAgain then
                    pcall(function()
                        local gui=LP:FindFirstChildOfClass("PlayerGui")
                        local revive=gui and gui:FindFirstChild("BattleHUD") and gui.BattleHUD:FindFirstChild("PlayerRevive")
                        local reviveFrame=revive and revive:FindFirstChild("ReviveFrame")
                        if reviveFrame and reviveFrame.Visible then
                            local remotes=game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
                            local gamePlayer=remotes and remotes:FindFirstChild("GamePlayerRE")
                            if gamePlayer then gamePlayer:FireServer("ExitSettlement") end
                        end
                        local result=gui and gui:FindFirstChild("ResultGui")
                        local settlement=result and result:FindFirstChild("ScreenSettlement")
                        if settlement and settlement.Visible then
                            local remotes=game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
                            local gameRound=remotes and remotes:FindFirstChild("GameRoundRE")
                            if gameRound then gameRound:FireServer("VotePlayAgain") end
                        end
                    end)
                end
                task.wait(.25)
            end
        end)
    end
    local function runAutoSellWorker()
        autoSellWorkerToken=autoSellWorkerToken+1
        local token=autoSellWorkerToken
        task.spawn(function()
            while running and token==autoSellWorkerToken do
                if settings.autoSell then
                    if #settings.sellEquipmentRarities>0 then pcall(function() sellEquipmentByRarity(settings.sellEquipmentRarities) end) end
                    if #settings.sellOres>0 then pcall(function() sellOres(settings.sellOres) end) end
                    if #settings.sellCrystals>0 then pcall(function() sellCrystals(settings.sellCrystals) end) end
                end
                task.wait(2)
            end
        end)
    end
    local function removeVisual(key)
        local v=visuals[key]; if not v then return end
        pcall(function() v.highlight:Destroy() end); pcall(function() v.billboard:Destroy() end); visuals[key]=nil
    end
    local function ensureVisual(key, adornee, part, color)
        local v=visuals[key]
        if v and v.adornee==adornee and v.part==part then return v end
        removeVisual(key)
        local ok,result=pcall(function()
            local h=Instance.new("Highlight"); h.Adornee=adornee; h.FillTransparency=.78; h.OutlineTransparency=.05
            h.FillColor=color; h.OutlineColor=color; h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Parent=folder
            local b=Instance.new("BillboardGui"); b.Adornee=part; b.AlwaysOnTop=true; b.Size=UDim2.fromOffset(240,44); b.StudsOffset=Vector3.new(0,3,0); b.Parent=folder
            local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Size=UDim2.fromScale(1,1); l.Font=Enum.Font.GothamSemibold
            l.TextSize=13; l.TextStrokeTransparency=.2; l.TextColor3=color; l.Parent=b
            return {adornee=adornee,part=part,highlight=h,billboard=b,label=l}
        end)
        if not ok then return nil end
        visuals[key]=result; return result
    end

    local function collectEnemies()
        local out={}; local ef=workspace:FindFirstChild("EnemyNpc")
        if not ef then return out end
        for _,m in ipairs(ef:GetChildren()) do
            local p,h=getPart(m),getHumanoid(m)
            if p and h and h.Health>0 then table.insert(out,{model=m,part=p,humanoid=h,distance=distance(p)}) end
        end
        return out
    end
    local function chooseTarget(enemies)
        if settings.stickyTarget and selectedTarget and selectedTarget.Parent then
            local h=getHumanoid(selectedTarget); if h and h.Health>0 then return selectedTarget end
        end
        table.sort(enemies,function(a,b)
            if settings.targetMode=="Lowest HP" then
                if a.humanoid.Health==b.humanoid.Health then return a.distance<b.distance end
                return a.humanoid.Health<b.humanoid.Health
            end
            return a.distance<b.distance
        end)
        return enemies[1] and enemies[1].model or nil
    end

    -- Keep tab creation on the loader's original call stack.  Yielding here
    -- can drop the executor's Plugin capability before RAVENHUB creates its
    -- own Settings tab.
    local function createTab(name, icon)
        return Window:CreateTab(name, icon)
    end

    local Dashboard=createTab("Dungeon", "activity")
    Dashboard:CreateSection("Iron Soul v1.6.2")
    local roundLabel=Dashboard:CreateLabel("Round: scanning...")
    local enemyCountLabel=Dashboard:CreateLabel("Enemies: scanning...")
    local targetLabel=Dashboard:CreateLabel("Target: none")
    local dodgeLabel=Dashboard:CreateLabel("Redzone: clear")
    Dashboard:CreateSection("Auto Dungeon")
    autoDungeonStatusLabel=Dashboard:CreateLabel("Auto Dungeon: Disabled")
    local autoWorldOptions={"World1 | Starless Forest","World2 | Frozen Valley","World3 | Oathlost Castle"}
    local autoDifficultyOptions={"1 | Trial","2 | Challenge","3 | Penitent","4 | Torment","5 | Inferno","6 | Hell Trial","7 | Hell Challenge","8 | Hell Penitent","9 | Hell Torment","10 | Hell Inferno"}
    Dashboard:CreateDropdown({Name="Dungeon World",Options=autoWorldOptions,CurrentOption={autoWorldOptions[1]},MultipleOptions=false,Flag="IronSoulAutoDungeonWorld",Callback=function(v)
        local value=type(v)=="table" and v[1] or v
        local world=tostring(value):match("^(World%d+)")
        if world then settings.autoDungeonWorld=world end
    end})
    Dashboard:CreateDropdown({Name="Dungeon Difficulty",Options=autoDifficultyOptions,CurrentOption={autoDifficultyOptions[1]},MultipleOptions=false,Flag="IronSoulAutoDungeonDifficulty",Callback=function(v)
        local value=type(v)=="table" and v[1] or v
        local difficulty=tonumber(tostring(value):match("^(%d+)") or "")
        if difficulty then settings.autoDungeonDifficulty=difficulty end
    end})
    Dashboard:CreateToggle({Name="Auto Enter Dungeon",CurrentValue=false,Flag="IronSoulAutoEnterDungeon",Callback=function(v) settings.autoEnterDungeon=v end})
    Dashboard:CreateButton({Name="Enter Dungeon Now",Callback=function() requestDungeonEntry(true) end})

    local Combat=createTab("ESP", "crosshair")
    Combat:CreateSection("Enemy ESP")
    Combat:CreateToggle({Name="Enemy ESP",CurrentValue=true,Flag="IronSoulEnemyESP",Callback=function(v) settings.enemyEsp=v end})
    Combat:CreateToggle({Name="Show HP",CurrentValue=true,Flag="IronSoulShowHP",Callback=function(v) settings.showHp=v end})
    Combat:CreateSlider({Name="ESP Distance",Range={100,4000},Increment=100,CurrentValue=1500,Suffix=" studs",Flag="IronSoulESPDistance",Callback=function(v) settings.maxDistance=v end})
    Combat:CreateSection("Target")
    Combat:CreateDropdown({Name="Target Mode",Options={"Nearest","Lowest HP"},CurrentOption={"Nearest"},MultipleOptions=false,Flag="IronSoulTargetMode",Callback=function(v) settings.targetMode=type(v)=="table"and v[1]or v selectedTarget=nil end})
    Combat:CreateToggle({Name="Sticky Target",CurrentValue=true,Flag="IronSoulSticky",Callback=function(v) settings.stickyTarget=v if not v then selectedTarget=nil end end})
    Combat:CreateToggle({Name="Spectate Current Target",CurrentValue=false,Flag="IronSoulSpectate",Callback=function(v) spectating=v end})

    local Farm=createTab("Autofarm", "swords")
    Farm:CreateSection("Potassium Autofarm")
    Farm:CreateToggle({Name="Autofarm",CurrentValue=false,Flag="IronSoulAutoFarm",Callback=function(v) settings.autoFarm=v end})
    Farm:CreateToggle({Name="Auto Use Skill",CurrentValue=false,Flag="IronSoulAutoUseSkill",Callback=function(v) settings.autoUseSkill=v end})
    Farm:CreateToggle({Name="Auto Switch Weapon",CurrentValue=false,Flag="IronSoulAutoSwitchWeapon",Callback=function(v) settings.autoSwitchWeapon=v end})
    Farm:CreateSlider({Name="Distance X",Range={-20,20},Increment=1,CurrentValue=0,Suffix=" studs",Flag="IronSoulDistanceX",Callback=function(v) settings.distanceX=v end})
    Farm:CreateSlider({Name="Distance Y",Range={-20,20},Increment=1,CurrentValue=0,Suffix=" studs",Flag="IronSoulDistanceY",Callback=function(v) settings.distanceY=v end})
    Farm:CreateSlider({Name="Distance Z",Range={-20,30},Increment=1,CurrentValue=10,Suffix=" studs",Flag="IronSoulDistanceZ",Callback=function(v) settings.distanceZ=v end})
    Farm:CreateSlider({Name="Pitch",Range={-180,180},Increment=1,CurrentValue=45,Suffix=" deg",Flag="IronSoulPitch",Callback=function(v) settings.pitch=v end})
    Farm:CreateSection("Mob Management")
    Farm:CreateToggle({Name="BringMobs",CurrentValue=false,Flag="IronSoulBringMobs",Callback=function(v) settings.bringMobs=v end})
    Farm:CreateSection("Reference Controls")
    Farm:CreateToggle({Name="Allow Camera Change",CurrentValue=false,Flag="IronSoulAllowCameraChange",Callback=function(v) settings.allowCameraChange=v settings.cameraChange=v if not v then workspace.CurrentCamera.CameraType=Enum.CameraType.Custom workspace.CurrentCamera.CameraSubject=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end end})
    Farm:CreateSlider({Name="Camera Distance",Range={0,100},Increment=5,CurrentValue=70,Suffix=" studs",Flag="IronSoulCamDist",Callback=function(v) settings.cameraDistance=v end})
    Farm:CreateToggle({Name="Change WalkSpeed",CurrentValue=false,Flag="IronSoulChangeWalkSpeed",Callback=function(v) settings.changeWalkSpeed=v settings.walkSpeed=v end})
    Farm:CreateSlider({Name="WalkSpeed",Range={1,100},Increment=1,CurrentValue=16,Suffix="",Flag="IronSoulWalkSpeedVal",Callback=function(v) settings.walkSpeedValue=v end})
    Farm:CreateSection("Collection")
    Farm:CreateToggle({Name="Auto Collect Chests",CurrentValue=false,Flag="IronSoulCollectChests",Callback=function(v) settings.autoCollectChests=v end})
    Farm:CreateToggle({Name="Auto Collect Dragon Eggs",CurrentValue=false,Flag="IronSoulCollectEggs",Callback=function(v) settings.autoCollectEggs=v end})
    Farm:CreateToggle({Name="Auto Play Again",CurrentValue=false,Flag="IronSoulAutoPlayAgain",Callback=function(v) settings.autoPlayAgain=v end})

    local Dodge=createTab("Dodge", "shield")
    Dodge:CreateSection("RedShow Avoidance")
    Dodge:CreateToggle({Name="Auto Dodge Redzone",CurrentValue=false,Flag="IronSoulAutoDodge",Callback=function(v) settings.autoDodge=v end})
    Dodge:CreateDropdown({Name="Escape Mode",Options={"Underground","Air","Nearest Edge"},CurrentOption={"Air"},MultipleOptions=false,Flag="IronSoulDodgeMode",Callback=function(v) settings.dodgeMode=type(v)=="table"and v[1]or v end})
    Dodge:CreateSlider({Name="Safety Margin",Range={0,12},Increment=1,CurrentValue=3,Suffix=" studs",Flag="IronSoulDodgeMargin",Callback=function(v) settings.dodgeMargin=v end})
    Dodge:CreateSlider({Name="Dodge Distance",Range={6,30},Increment=1,CurrentValue=16,Suffix=" studs",Flag="IronSoulDodgeDistance",Callback=function(v) settings.dodgeDistance=v end})
    Dodge:CreateSlider({Name="Vertical Escape",Range={15,80},Increment=5,CurrentValue=50,Suffix=" studs",Flag="IronSoulDodgeVertical",Callback=function(v) settings.dodgeVertical=v end})
    Dodge:CreateSlider({Name="Dodge Cooldown",Range={0.2,1.5},Increment=.05,CurrentValue=.55,Suffix="s",Flag="IronSoulDodgeCooldown",Callback=function(v) settings.dodgeCooldown=v end})
    Dodge:CreateSlider({Name="Dodge Hold",Range={0.5,10},Increment=.1,CurrentValue=1.4,Suffix="s",Flag="IronSoulDodgeHold",Callback=function(v) settings.dodgeHold=v end})

    local Sell=createTab("Auto Sell", "dollar-sign")
    Sell:CreateSection("Sell by Rarity")
    local rarityOptions = getRarityTiers()
    Sell:CreateDropdown({Name="Equipment Rarity",Options=rarityOptions,CurrentOption={},MultipleOptions=true,Flag="IronSoulSellRarity",Callback=function(v) settings.sellEquipmentRarities=type(v)=="table"and v or{v} end})
    local oreDropdown = Sell:CreateDropdown({Name="Ores",Options=getAllOreNames(),CurrentOption={},MultipleOptions=true,Flag="IronSoulSellOres",Callback=function(v) settings.sellOres=type(v)=="table"and v or{v} end})
    Sell:CreateButton({Name="Refresh Ores List",Callback=function()
        if oreDropdown and type(oreDropdown.Refresh)=="function" then
            oreDropdown:Refresh(getAllOreNames(), true)
        end
    end})
    local crystalDropdown = Sell:CreateDropdown({Name="Crystals",Options=getAllCrystalNames(),CurrentOption={},MultipleOptions=true,Flag="IronSoulSellCrystals",Callback=function(v) settings.sellCrystals=type(v)=="table"and v or{v} end})
    Sell:CreateButton({Name="Refresh Crystals List",Callback=function()
        if crystalDropdown and type(crystalDropdown.Refresh)=="function" then
            crystalDropdown:Refresh(getAllCrystalNames(), true)
        end
    end})
    Sell:CreateToggle({Name="Auto Sell",CurrentValue=false,Flag="IronSoulAutoSell",Callback=function(v) settings.autoSell=v end})

    loadFramework()

    local lastDodge,scanAt,statusAt=0,0,0
    connect(LP.CharacterAdded,function()
        directController=nil
        controllerModuleRef=nil
        controllerCharacter=nil
        controllerCache=nil
        currentEnemy=nil
        task.defer(function() if running then getController() end end)
    end)
    runPotassiumAutofarm()
    runPotassiumCombat()
    runCollectionWorker()
    runAutoWeaponWorker()
    runAutoPlayAgainWorker()
    runAutoSellWorker()
    runAutoDungeonWorker()
    local cachedEnemies={}
    local redFolder=workspace:FindFirstChild("RedShow")
    if redFolder then
        connect(redFolder.DescendantAdded,function(instance)
            if not running or not settings.autoDodge or not instance:IsA("BasePart") then return end
            task.defer(function()
                if not running or not settings.autoDodge or not instance.Parent then return end
                local root=myRoot(); if not root then return end
                local now=os.clock()
                local direction=settings.dodgeMode=="Air" and 1 or -1
                if settings.dodgeMode=="Nearest Edge" then direction=-1 end
                local safe=root.Position+Vector3.new(0,direction*settings.dodgeVertical,0)
                local rotation=root.CFrame-root.Position
                root.CFrame=CFrame.new(safe)*rotation
                dodgeSafePosition=safe
                dodgeLockUntil=now+settings.dodgeHold
                lastDodge=now
                stopAttack()
            end)
        end)
    end
    connect(RunService.Heartbeat,function()
        if not running then return end
        local now=os.clock()
        if now-scanAt>=.25 then
            scanAt=now; cachedEnemies=collectEnemies(); selectedTarget=chooseTarget(cachedEnemies)
            local active={}
            for _,e in ipairs(cachedEnemies) do
                if settings.enemyEsp and e.distance<=settings.maxDistance then
                    active[e.model]=true
                    local color=e.model==selectedTarget and Color3.fromRGB(255,215,70) or Color3.fromRGB(255,75,75)
                    local v=ensureVisual(e.model,e.model,e.part,color)
                    local hp=settings.showHp and string.format(" | HP %d/%d",math.floor(e.humanoid.Health),math.floor(e.humanoid.MaxHealth)) or ""
                    if v then
                        v.label.Text=string.format("%s%s | %dm",enemyName(e.model),hp,math.floor(e.distance)); v.label.TextColor3=color
                        v.highlight.FillColor=color; v.highlight.OutlineColor=color
                    end
                end
            end
            for key in pairs(visuals) do
                local ok,isOld=pcall(function() return key.Parent==workspace:FindFirstChild("EnemyNpc") and not active[key] end)
                if ok and isOld then removeVisual(key) end
            end
        end

        local root=myRoot(); local red=workspace:FindFirstChild("RedShow"); local danger,dodgePosition=nil,nil
        if root and red then
            local zones={}
            for _,zone in ipairs(red:GetDescendants()) do
                if zone:IsA("BasePart") then
                    local localPos=zone.CFrame:PointToObjectSpace(root.Position)
                    local halfX=zone.Size.X/2+settings.dodgeMargin
                    local halfZ=zone.Size.Z/2+settings.dodgeMargin
                    local verticalRange=math.max(zone.Size.Y/2+8,10)
                    if math.abs(localPos.X)<=halfX and math.abs(localPos.Z)<=halfZ and math.abs(localPos.Y)<=verticalRange then
                        danger=zone
                    end
                    table.insert(zones,zone)
                end
            end
            if danger then
                if settings.dodgeMode=="Underground" then
                    dodgePosition=root.Position-Vector3.new(0,settings.dodgeVertical,0)
                elseif settings.dodgeMode=="Air" then
                    dodgePosition=root.Position+Vector3.new(0,settings.dodgeVertical,0)
                else
                    dodgePosition=root.Position
                    -- Resolve overlapping telegraphs repeatedly so the final point is
                    -- outside every active rectangle, not merely the first one found.
                    for _=1,3 do
                        for _,zone in ipairs(zones) do
                            local localPos=zone.CFrame:PointToObjectSpace(dodgePosition)
                            local halfX=zone.Size.X/2+settings.dodgeMargin
                            local halfZ=zone.Size.Z/2+settings.dodgeMargin
                            local verticalRange=math.max(zone.Size.Y/2+8,10)
                            if math.abs(localPos.X)<=halfX and math.abs(localPos.Z)<=halfZ and math.abs(localPos.Y)<=verticalRange then
                                local exitX=halfX-math.abs(localPos.X)
                                local exitZ=halfZ-math.abs(localPos.Z)
                                if exitX<=exitZ then
                                    local direction=localPos.X>=0 and 1 or -1
                                    localPos=Vector3.new(direction*(halfX+settings.dodgeDistance),localPos.Y,localPos.Z)
                                else
                                    local direction=localPos.Z>=0 and 1 or -1
                                    localPos=Vector3.new(localPos.X,localPos.Y,direction*(halfZ+settings.dodgeDistance))
                                end
                                dodgePosition=zone.CFrame:PointToWorldSpace(localPos)
                            end
                        end
                    end
                end
            end
        end
        redzoneDanger=danger~=nil
        if danger and dodgePosition and settings.autoDodge and now-lastDodge>=settings.dodgeCooldown and root then
            lastDodge=now
            local humanoid=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            local rotation=root.CFrame-root.Position
            root.CFrame=CFrame.new(dodgePosition)*rotation
            if humanoid then humanoid:MoveTo(dodgePosition) end
            dodgeSafePosition=dodgePosition
            dodgeLockUntil=now+settings.dodgeHold
        end

        local dodgeLocked=settings.autoDodge and dodgeSafePosition~=nil and now<dodgeLockUntil
        if dodgeLocked and root then
            if (root.Position-dodgeSafePosition).Magnitude>2.5 then
                local rotation=root.CFrame-root.Position
                root.CFrame=CFrame.new(dodgeSafePosition)*rotation
            end
            local humanoid=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:MoveTo(dodgeSafePosition) end
        elseif now>=dodgeLockUntil then
            dodgeSafePosition=nil
        end

        -- Autofarm, chest/egg collection and replay are driven by the
        -- reference-compatible worker loops below.  Heartbeat remains a light
        -- UI/ESP update path so it cannot stall on task.wait().
        if not settings.autoFarm then stopAttack() end
        if settings.changeWalkSpeed or settings.walkSpeed then
            local hum=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            local controller=getController()
            local controllerOwner=controllerModuleRef or controller
            if controllerOwner and type(controllerOwner.SetWalkSpeed)=="function" and not originalSetWalkSpeed then
                originalSetWalkSpeed=controllerOwner.SetWalkSpeed
            end
            if controllerOwner then
                controllerOwner.SetWalkSpeed=function(_,_) if hum then hum.WalkSpeed=settings.walkSpeedValue end end
            end
            if hum then hum.WalkSpeed=settings.walkSpeedValue end
        elseif originalSetWalkSpeed then
            local controllerOwner=controllerModuleRef or getController()
            if controllerOwner then controllerOwner.SetWalkSpeed=originalSetWalkSpeed end
            originalSetWalkSpeed=nil
        end
        if now-statusAt>=.35 then
            statusAt=now
            local targetPart=getPart(selectedTarget); local targetHum=getHumanoid(selectedTarget)
            local targetText="Target: none"
            if selectedTarget and targetPart and targetHum then
                targetText=string.format("Target: %s | HP %d/%d | %dm",enemyName(selectedTarget),math.floor(targetHum.Health),math.floor(targetHum.MaxHealth),math.floor(distance(targetPart)))
            end
            local gameRound,gameRoundComplete=roundState()
            pcall(function()
                roundLabel:Set(string.format("Game round: %s | completed: %s",tostring(gameRound or "?"),tostring(gameRoundComplete or "?")))
                enemyCountLabel:Set("Enemies alive: "..tostring(#cachedEnemies))
                targetLabel:Set(targetText)
                dodgeLabel:Set(danger and "Redzone: DODGING" or dodgeLocked and string.format("Redzone: holding safe %.1fs",math.max(0,dodgeLockUntil-now)) or "Redzone: clear")
            end)
        end
    end)

    connect(RunService.RenderStepped,function()
        local camera=workspace.CurrentCamera
        if not camera then return end
        if spectating and selectedTarget then camera.CameraSubject=getHumanoid(selectedTarget) or getPart(selectedTarget)
        elseif not spectating and LP.Character then camera.CameraSubject=LP.Character:FindFirstChildOfClass("Humanoid") end
    end)

    local function destroy()
        if not running then return end; running=false
        stopAttack()
        for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        for key in pairs(visuals) do removeVisual(key) end
        if originalSetWalkSpeed then
            local controllerOwner=controllerModuleRef or getController()
            if controllerOwner then controllerOwner.SetWalkSpeed=originalSetWalkSpeed end
            originalSetWalkSpeed=nil
        end
        TargetHighlight.Adornee=nil
        TargetHighlight.Enabled=false
        pcall(function() folder:Destroy() end)
        local camera=workspace.CurrentCamera; if camera and LP.Character then camera.CameraSubject=LP.Character:FindFirstChildOfClass("Humanoid") end
        if getgenv().__RAVEN_IRON_SOUL and getgenv().__RAVEN_IRON_SOUL.Settings==settings then getgenv().__RAVEN_IRON_SOUL=nil end
    end
    getgenv().__RAVEN_IRON_SOUL={Version="v1.6.2",Settings=settings,Destroy=destroy}
    if runtimeInfo and type(runtimeInfo.registerCleanup)=="function" then runtimeInfo.registerCleanup(destroy) end
end
