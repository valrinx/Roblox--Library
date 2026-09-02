--[[
    RAVEN HUB | Iron Soul: Dungeon
    Lobby PlaceId: 117533937949084 | Starless Forest: 116456628154258
    GameId: 9910245722 | Version: v1.6.0
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
    local farmWorkerToken = 0
    local collectionWorkerToken = 0
    local autoPlayWorkerToken = 0
    local autoSellWorkerToken = 0
    local originalSetWalkSpeed = nil
    local cameraNextAt = 0
    local lastEndAction, endActionState = 0, "waiting for dungeon result"
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
        autoFarm = false, autoAttack = true, autoSkills = false, autoUseSkill = false,
        distanceX = 0, distanceY = 0, distanceZ = 10, pitch = 45,
        farmMode = "Source", farmDistance = 7, heightAbove = 8, actionDelay = 0.18,
        autoDodge = false, dodgeMode = "Air", dodgeMargin = 3, dodgeDistance = 16, dodgeVertical = 50, dodgeCooldown = 0.55, dodgeHold = 1.4,
        autoPlayAgain = false,
        endAction = "Off", endActionDelay = 3,
        bringMobs = false, bringMobsRange = 100,
        autoCollectChests = false, autoCollectEggs = false,
        changeWalkSpeed = false, walkSpeed = false, walkSpeedValue = 16,
        cameraChange = false, allowCameraChange = false, cameraDistance = 70, cameraBack = 50,
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
        if attackBusy then return end
        attackBusy=true
        task.spawn(function()
            local controller=getController()
            if controller and pcall(function() controller:PerformAction("BaseAttack") end) then
                task.wait()
                if running then pcall(function() controller:StopAction("BaseAttack") end) end
            else
                local camera=workspace.CurrentCamera; local size=camera and camera.ViewportSize or Vector2.new(960,540)
                pcall(function() VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,true,game,0) end)
                task.wait(.03)
                pcall(function() VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,false,game,0) end)
            end
            if bool and running then useReadySkills() end
            attackBusy=false
        end)
    end
    local function stopAttack()
        local controller=getController()
        if controller then pcall(function() controller:StopAction("BaseAttack") end) end
    end
    useReadySkills = function()
        local gui=LP:FindFirstChild("PlayerGui"); local input=gui and gui:FindFirstChild("ScreenInput")
        local pc=input and input:FindFirstChild("PCInput"); local skills=pc and pc:FindFirstChild("Skills")
        if not skills then return end
        local controller=getController()
        -- Potassium's original contract: a ready ImageButton with FullCharge
        -- uses SkillU; otherwise the three normal skills are fired in order.
        for _,button in ipairs(skills:GetChildren()) do
            if button:IsA("ImageButton") and button:GetAttribute("OnCD")==false then
                if button:GetAttribute("FullCharge")==true then
                    if controller then pcall(function() controller:PerformAction("SkillU") end) end
                    task.wait(0.05)
                    return
                end
                for _,name in ipairs({"Skill1","Skill2","SkillAW"}) do
                    local skill=skills:FindFirstChild(name); local cool=skill and skill:FindFirstChild("Cool")
                    if skill and skill:GetAttribute("OnCD")~=true and not (cool and cool.Visible) then
                        if controller then
                            pcall(function() controller:PerformAction(name) end)
                        else
                            local key=skill:FindFirstChild("Key",true); local text=key and key:FindFirstChildWhichIsA("TextLabel",true)
                            local keyCode=text and Enum.KeyCode[text.Text]
                            pcall(function() skill:Activate() end)
                            if keyCode then tapKey(keyCode) end
                        end
                        task.wait(0.05)
                    end
                end
                return
            end
        end
    end

    -- Framework integration (from Potassium reference)
    local Framework, DataUtil, EquipmentUtil, ForgeUtil, RarityTiers, TranslationUtil, MaterialUtil
    pcall(function()
        Framework = require(game:GetService("ReplicatedStorage"):WaitForChild("Framework"))
        DataUtil = Framework.Modules.DataUtil
        EquipmentUtil = Framework.Modules.EquipmentUtil
        ForgeUtil = Framework.Modules.ForgeUtil
        RarityTiers = Framework.Modules.RarityTiers
        TranslationUtil = Framework.Modules.TranslationUtil
        MaterialUtil = Framework.Modules.MaterialUtil
    end)
    local function getRarityTiers()
        if not RarityTiers then return {} end
        local t = {}
        for _, v in pairs(RarityTiers.Tiers) do table.insert(t, v.Name) end
        return t
    end
    local function getRarityName(rarity)
        if not RarityTiers then return "Unknown" end
        return RarityTiers.Tiers[rarity] and RarityTiers.Tiers[rarity].Name or "Unknown"
    end
    local function getEquipment()
        if not DataUtil or not EquipmentUtil then return {} end
        local result = {}
        local ok, playerData = pcall(function() return DataUtil:GetPlayerData(LP) end)
        if not ok or not playerData then return result end
        local owned = playerData.Equipment and playerData.Equipment.Owned
        if not owned then return result end
        for uuid, itemData in pairs(owned) do
            local def = EquipmentUtil:GetDef(itemData.ID)
            if def then
                local name = TranslationUtil:TranslateByKey("K_" .. string.upper(def.ID))
                local rarity = EquipmentUtil:GetOreRarity(itemData.MaxOre)
                table.insert(result, { UUID = uuid, ID = itemData.ID, Name = name, Rarity = getRarityName(rarity), Type = itemData.Type, Level = EquipmentUtil:GetLvByInfo(itemData, def) })
            end
        end
        return result
    end
    local function getOres()
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
        if not EquipmentUtil then return end
        local items = getEquipment()
        for _, item in ipairs(items) do
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
    local function sellOres(oreNames)
        if not ForgeUtil then return end
        local ores = getOres()
        local toSell = {}
        for _, ore in ipairs(ores) do
            for _, name in ipairs(oreNames) do
                if ore.Name == name then toSell[ore.ID] = 1; break end
            end
        end
        if next(toSell) then
            pcall(function()
                game:GetService("ReplicatedStorage").Framework.Gameplay.EquipmentSystem.ForgeRF:InvokeServer("Sell", toSell)
            end)
        end
    end
    local function sellCrystals(crystalNames)
        if not MaterialUtil then return end
        local crystals = getCrystals()
        local toSell = {}
        for _, c in ipairs(crystals) do
            for _, name in ipairs(crystalNames) do
                if c.Name == name then toSell[c.ID] = 1; break end
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
            if #result==0 then scan(workspace:FindFirstChild("World")) end
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
    local function collectChests()
        local root=myRoot(); if not root then return end
        local finalDistance=CFrame.new(settings.distanceX,settings.distanceY,settings.distanceZ)*CFrame.Angles(math.rad(settings.pitch),math.rad(180),0)
        -- Potassium's chest contract scans the live workspace models and keeps
        -- the player on a chest until its HitCount reaches zero.
        for _,v in ipairs(workspace:GetChildren()) do
            if v:IsA("Model") and string.find(v.Name,"Chest") then
                local chestRoot=v:FindFirstChild("Root") or interactableRoot(v)
                local hitCount=tonumber(v:GetAttribute("HitCount") or (chestRoot and chestRoot:GetAttribute("HitCount")))
                if chestRoot and hitCount and hitCount>0 then
                    CollectingChests=true
                    repeat
                        if not root.Parent or not v.Parent or not chestRoot.Parent then break end
                        root.CFrame=chestRoot.CFrame*finalDistance
                        task.wait()
                        hitCount=tonumber(v:GetAttribute("HitCount") or (chestRoot and chestRoot:GetAttribute("HitCount"))) or 0
                    until not settings.autoCollectChests or hitCount<=0
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
                    root.CFrame=chestRoot.CFrame*finalDistance
                    activateCollectable(v,chestRoot); collectedChests[v]=true; collectionNextAt=now+0.2
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
    local function bringMobsToTarget()
        local root = myRoot(); if not root then return end
        local targetPart = currentEnemy or getPart(selectedTarget)
        if not targetPart then return end
        local enemyFolder=workspace:FindFirstChild("EnemyNpc")
        if not enemyFolder then return end
        for _, v in ipairs(enemyFolder:GetChildren()) do
            if v:IsA("Model") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                if (targetPart.Position - v.HumanoidRootPart.Position).Magnitude <= math.min(settings.bringMobsRange,100) then
                    v.HumanoidRootPart.CFrame = targetPart.CFrame
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
    local function sourceFarmDistance(model)
        local x,y,z=settings.distanceX,settings.distanceY,settings.distanceZ
        if model and model:GetAttribute("LevelType")=="Boss" then x,y,z=x*1.5,y*1.5,z*1.5 end
        return CFrame.new(x,y,z)*CFrame.Angles(0,0,math.rad(settings.pitch))
    end
    local function farmCFrame(model,root,enemyRoot)
        if settings.farmMode=="Source" then return enemyRoot.CFrame*sourceFarmDistance(model) end
        if settings.farmMode=="Above Target" then
            local desired=enemyRoot.Position+Vector3.new(0,settings.heightAbove,0)
            return CFrame.lookAt(desired,enemyRoot.Position)
        end
        if settings.farmMode=="Below Target" then
            local desired=enemyRoot.Position-Vector3.new(0,settings.heightAbove,0)
            return CFrame.lookAt(desired,enemyRoot.Position)
        end
        local flat=Vector3.new(root.Position.X-enemyRoot.Position.X,0,root.Position.Z-enemyRoot.Position.Z)
        if flat.Magnitude<.1 then flat=-enemyRoot.CFrame.LookVector end
        local desired=enemyRoot.Position+flat.Unit*settings.farmDistance
        return CFrame.lookAt(desired,enemyRoot.Position)
    end
    local function recoverWithoutEnemies(root)
        if not root then return end
        if workspace:GetAttribute("GameMode")=="" then
            root.CFrame=CFrame.new(8561.28906,273.670654,-3727.4563,0.589069664,-2.59408957e-08,0.808082283,-6.4901144e-08,1,7.9412942e-08,-0.808082283,-9.92252183e-08,0.589069664)
            return
        end
        local respawns=workspace:FindFirstChild("PlayerRespawn")
        if not respawns then return end
        local oldCFrame=root.CFrame
        for _,spawnPart in ipairs(respawns:GetChildren()) do
            if not running or not settings.autoFarm then break end
            if spawnPart:IsA("BasePart") then
                root.CFrame=spawnPart.CFrame
                task.wait(1)
            end
        end
        if root.Parent then root.CFrame=oldCFrame end
    end
    local function runPotassiumAutofarm()
        farmWorkerToken=farmWorkerToken+1
        local token=farmWorkerToken
        task.spawn(function()
            while running and token==farmWorkerToken do
                if not settings.autoFarm then
                    SetCurrentEnemy(nil)
                    task.wait(.1)
                elseif game.PlaceId==117533937949084 then
                    SetCurrentEnemy(nil)
                    task.wait(.25)
                elseif redzoneDanger and settings.autoDodge then
                    task.wait(.05)
                elseif CollectingChests or CollectingEggs then
                    task.wait()
                else
                    local ok,err=pcall(function()
                        clearWhiteEffect()
                        local enemyFolder=workspace.EnemyNpc or workspace:FindFirstChild("EnemyNpc")
                        local models=enemyFolder and enemyFolder:GetChildren() or {}
                        local found=false
                        for _,v in ipairs(models) do
                            local humanoid=getHumanoid(v); local enemyRoot=v:FindFirstChild("HumanoidRootPart")
                            if v:IsA("Model") and humanoid and humanoid.Health>0 and enemyRoot then
                                found=true; currentEnemy=enemyRoot; SetCurrentEnemy(v)
                                local count=0
                                repeat
                                    if not running or not settings.autoFarm or CollectingChests or CollectingEggs or (redzoneDanger and settings.autoDodge) then break end
                                    local rootNow=myRoot(); if not rootNow or not enemyRoot.Parent then break end
                                    count=count+1
                                    if count>1000 then
                                        rootNow.CFrame=enemyRoot.CFrame
                                        task.wait(.1)
                                        count=0
                                        break
                                    end
                                    rootNow.CFrame=farmCFrame(v,rootNow,enemyRoot)
                                    if settings.autoAttack then Attack(settings.autoUseSkill or settings.autoSkills) end
                                    if settings.bringMobs then bringMobsToTarget() end
                                    task.wait()
                                    humanoid=getHumanoid(v); enemyRoot=v:FindFirstChild("HumanoidRootPart")
                                until not settings.autoFarm or not humanoid or humanoid.Health<=0 or not enemyRoot
                            elseif v and v:IsA("Model") and not v:FindFirstChild("HumanoidRootPart") then
                                local rootNow=myRoot(); if rootNow then rootNow.CFrame=v:GetPivot() end
                            end
                        end
                        if not found then recoverWithoutEnemies(myRoot()) end
                    end)
                    if not ok then warn(err) end
                    task.wait()
                end
            end
            SetCurrentEnemy(nil)
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
                if settings.autoCollectEggs or settings.autoFarm then pcall(collectDragonEggs) end
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
    local function normalizedGuiText(button)
        local values={button.Name}
        if button:IsA("TextButton") then table.insert(values,button.Text) end
        for _,child in ipairs(button:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") then table.insert(values,child.Text) end
        end
        return string.lower(table.concat(values," ")):gsub("[%p%s]+","")
    end
    local function guiIsVisible(gui)
        if not gui:IsA("GuiObject") or not gui.Visible or gui.AbsoluteSize.X<2 or gui.AbsoluteSize.Y<2 then return false end
        local parent=gui.Parent
        while parent do
            if parent:IsA("GuiObject") and not parent.Visible then return false end
            if parent:IsA("ScreenGui") then return parent.Enabled end
            parent=parent.Parent
        end
        return true
    end
    local function endActionButton(mode)
        local playerGui=LP:FindFirstChildOfClass("PlayerGui"); if not playerGui then return nil end
        local resultGui=playerGui:FindFirstChild("ResultGui")
        local settlement=resultGui and resultGui:FindFirstChild("ScreenSettlement")
        local group=settlement and settlement:FindFirstChild("BtnGroup")
        local exact=group and group:FindFirstChild(mode=="Replay" and "PlayAgainBtn" or "ReturnToLobbyBtn")
        if exact and exact:IsA("GuiButton") and guiIsVisible(exact) then return exact end
        local replayWords={"replay","retry","playagain","again","rechallenge"}
        local lobbyWords={"returnlobby","backtolobby","lobby","returnhome","backhome"}
        local words=mode=="Replay" and replayWords or lobbyWords
        local best,bestScore=nil,-math.huge
        for _,button in ipairs(playerGui:GetDescendants()) do
            if button:IsA("GuiButton") and guiIsVisible(button) then
                local text=normalizedGuiText(button)
                for index,word in ipairs(words) do
                    if text:find(word,1,true) then
                        local score=100-index*5+button.AbsoluteSize.X*button.AbsoluteSize.Y/10000
                        if score>bestScore then best,bestScore=button,score end
                        break
                    end
                end
            end
        end
        return best
    end
    local function activateGuiButton(button)
        if not button or not button.Parent then return false end
        local activated=false
        if type(firesignal)=="function" then
            for _,signal in ipairs({button.MouseButton1Down,button.MouseButton1Click,button.MouseButton1Up,button.Activated}) do
                if pcall(firesignal,signal) then activated=true end
            end
        end
        if pcall(function() button:Activate() end) then activated=true end
        local pos=button.AbsolutePosition+button.AbsoluteSize/2
        if pcall(function()
            VirtualInputManager:SendMouseMoveEvent(pos.X,pos.Y,game)
            VirtualInputManager:SendMouseButtonEvent(pos.X,pos.Y,0,true,game,0)
            task.wait(.04)
            VirtualInputManager:SendMouseButtonEvent(pos.X,pos.Y,0,false,game,0)
        end) then activated=true end
        return activated
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

    -- MacLib creates a large batch of Instances for every tab.  Potassium can
    -- temporarily revoke the Instance capability when several tabs are built
    -- back-to-back in one scheduler slice.  Yield once per tab so the UI
    -- builder gets a fresh slice and never aborts halfway through the module.
    local function createTab(name, icon)
        task.wait()
        return Window:CreateTab(name, icon)
    end

    local Dashboard=createTab("Dungeon", "activity")
    Dashboard:CreateSection("Iron Soul v1.6.0")
    local roundLabel=Dashboard:CreateLabel("Round: scanning...")
    local enemyCountLabel=Dashboard:CreateLabel("Enemies: scanning...")
    local targetLabel=Dashboard:CreateLabel("Target: none")
    local dodgeLabel=Dashboard:CreateLabel("Redzone: clear")
    local endActionLabel=Dashboard:CreateLabel("End action: waiting for dungeon result")

    local Combat=createTab("Combat Intel", "crosshair")
    Combat:CreateSection("Enemy ESP")
    Combat:CreateToggle({Name="Enemy ESP",CurrentValue=true,Flag="IronSoulEnemyESP",Callback=function(v) settings.enemyEsp=v end})
    Combat:CreateToggle({Name="Show HP",CurrentValue=true,Flag="IronSoulShowHP",Callback=function(v) settings.showHp=v end})
    Combat:CreateSlider({Name="ESP Distance",Range={100,4000},Increment=100,CurrentValue=1500,Suffix=" studs",Flag="IronSoulESPDistance",Callback=function(v) settings.maxDistance=v end})
    Combat:CreateSection("Target")
    Combat:CreateDropdown({Name="Target Mode",Options={"Nearest","Lowest HP"},CurrentOption={"Nearest"},MultipleOptions=false,Flag="IronSoulTargetMode",Callback=function(v) settings.targetMode=type(v)=="table"and v[1]or v selectedTarget=nil end})
    Combat:CreateToggle({Name="Sticky Target",CurrentValue=true,Flag="IronSoulSticky",Callback=function(v) settings.stickyTarget=v if not v then selectedTarget=nil end end})
    Combat:CreateToggle({Name="Spectate Current Target",CurrentValue=false,Flag="IronSoulSpectate",Callback=function(v) spectating=v end})

    local Farm=createTab("Autofarm", "swords")
    Farm:CreateSection("Target Based Autofarm")
    Farm:CreateToggle({Name="Auto Farm Target",CurrentValue=false,Flag="IronSoulAutoFarm",Callback=function(v) settings.autoFarm=v end})
    Farm:CreateToggle({Name="Auto Base Attack",CurrentValue=true,Flag="IronSoulAutoAttack",Callback=function(v) settings.autoAttack=v end})
    Farm:CreateToggle({Name="Auto Use Skill",CurrentValue=false,Flag="IronSoulAutoUseSkill",Callback=function(v) settings.autoUseSkill=v settings.autoSkills=v end})
    Farm:CreateToggle({Name="Auto Skills (Ready Only)",CurrentValue=false,Flag="IronSoulAutoSkills",Callback=function(v) settings.autoSkills=v settings.autoUseSkill=v end})
    Farm:CreateDropdown({Name="Farm Position",Options={"Source","Approach","Above Target","Below Target"},CurrentOption={"Source"},MultipleOptions=false,Flag="IronSoulFarmMode",Callback=function(v) settings.farmMode=type(v)=="table"and v[1]or v end})
    Farm:CreateSlider({Name="Distance X",Range={-20,20},Increment=1,CurrentValue=0,Suffix=" studs",Flag="IronSoulDistanceX",Callback=function(v) settings.distanceX=v end})
    Farm:CreateSlider({Name="Distance Y",Range={-20,20},Increment=1,CurrentValue=0,Suffix=" studs",Flag="IronSoulDistanceY",Callback=function(v) settings.distanceY=v end})
    Farm:CreateSlider({Name="Distance Z",Range={-20,30},Increment=1,CurrentValue=10,Suffix=" studs",Flag="IronSoulDistanceZ",Callback=function(v) settings.distanceZ=v end})
    Farm:CreateSlider({Name="Pitch",Range={-180,180},Increment=1,CurrentValue=45,Suffix=" deg",Flag="IronSoulPitch",Callback=function(v) settings.pitch=v end})
    Farm:CreateSlider({Name="Attack Distance",Range={3,30},Increment=1,CurrentValue=7,Suffix=" studs",Flag="IronSoulFarmDistance",Callback=function(v) settings.farmDistance=v end})
    Farm:CreateSlider({Name="Height Above Target",Range={3,30},Increment=1,CurrentValue=8,Suffix=" studs",Flag="IronSoulFarmHeight",Callback=function(v) settings.heightAbove=v end})
    Farm:CreateSlider({Name="Action Delay",Range={0.1,0.8},Increment=.02,CurrentValue=.18,Suffix="s",Flag="IronSoulActionDelay",Callback=function(v) settings.actionDelay=v end})
    Farm:CreateSection("Mob Management")
    Farm:CreateToggle({Name="Bring Mobs to Target",CurrentValue=false,Flag="IronSoulBringMobs",Callback=function(v) settings.bringMobs=v end})
    Farm:CreateSlider({Name="Bring Range",Range={20,200},Increment=10,CurrentValue=100,Suffix=" studs",Flag="IronSoulBringRange",Callback=function(v) settings.bringMobsRange=v end})
    Farm:CreateSection("Collection")
    Farm:CreateToggle({Name="Auto Collect Chests",CurrentValue=false,Flag="IronSoulCollectChests",Callback=function(v) settings.autoCollectChests=v end})
    Farm:CreateToggle({Name="Auto Collect Dragon Eggs",CurrentValue=false,Flag="IronSoulCollectEggs",Callback=function(v) settings.autoCollectEggs=v end})

    local Dodge=createTab("Dodge", "shield")
    Dodge:CreateSection("RedShow Avoidance")
    Dodge:CreateToggle({Name="Auto Dodge Redzone",CurrentValue=false,Flag="IronSoulAutoDodge",Callback=function(v) settings.autoDodge=v end})
    Dodge:CreateDropdown({Name="Escape Mode",Options={"Underground","Air","Nearest Edge"},CurrentOption={"Air"},MultipleOptions=false,Flag="IronSoulDodgeMode",Callback=function(v) settings.dodgeMode=type(v)=="table"and v[1]or v end})
    Dodge:CreateSlider({Name="Safety Margin",Range={0,12},Increment=1,CurrentValue=3,Suffix=" studs",Flag="IronSoulDodgeMargin",Callback=function(v) settings.dodgeMargin=v end})
    Dodge:CreateSlider({Name="Dodge Distance",Range={6,30},Increment=1,CurrentValue=16,Suffix=" studs",Flag="IronSoulDodgeDistance",Callback=function(v) settings.dodgeDistance=v end})
    Dodge:CreateSlider({Name="Vertical Escape",Range={15,80},Increment=5,CurrentValue=50,Suffix=" studs",Flag="IronSoulDodgeVertical",Callback=function(v) settings.dodgeVertical=v end})
    Dodge:CreateSlider({Name="Dodge Cooldown",Range={0.2,1.5},Increment=.05,CurrentValue=.55,Suffix="s",Flag="IronSoulDodgeCooldown",Callback=function(v) settings.dodgeCooldown=v end})
    Dodge:CreateSlider({Name="Dodge Hold",Range={0.5,3},Increment=.1,CurrentValue=1.4,Suffix="s",Flag="IronSoulDodgeHold",Callback=function(v) settings.dodgeHold=v end})

    local Utility=createTab("Utility", "settings")
    Utility:CreateSection("Movement")
    Utility:CreateToggle({Name="Change WalkSpeed",CurrentValue=false,Flag="IronSoulChangeWalkSpeed",Callback=function(v) settings.changeWalkSpeed=v settings.walkSpeed=v end})
    Utility:CreateToggle({Name="Custom WalkSpeed",CurrentValue=false,Flag="IronSoulWalkSpeed",Callback=function(v) settings.walkSpeed=v settings.changeWalkSpeed=v end})
    Utility:CreateSlider({Name="WalkSpeed Value",Range={1,100},Increment=1,CurrentValue=16,Suffix="",Flag="IronSoulWalkSpeedVal",Callback=function(v) settings.walkSpeedValue=v end})
    Utility:CreateSection("Camera")
    Utility:CreateToggle({Name="Allow Camera Change",CurrentValue=false,Flag="IronSoulAllowCameraChange",Callback=function(v) settings.allowCameraChange=v settings.cameraChange=v if not v then workspace.CurrentCamera.CameraType=Enum.CameraType.Custom workspace.CurrentCamera.CameraSubject=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end end})
    Utility:CreateToggle({Name="Custom Camera (AFK View)",CurrentValue=false,Flag="IronSoulCamera",Callback=function(v) settings.cameraChange=v settings.allowCameraChange=v if not v then workspace.CurrentCamera.CameraType=Enum.CameraType.Custom workspace.CurrentCamera.CameraSubject=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end end})
    Utility:CreateSlider({Name="Camera Distance",Range={0,100},Increment=5,CurrentValue=70,Suffix=" studs",Flag="IronSoulCamDist",Callback=function(v) settings.cameraDistance=v end})
    Utility:CreateSlider({Name="Camera Back",Range={0,100},Increment=5,CurrentValue=50,Suffix=" studs",Flag="IronSoulCamBack",Callback=function(v) settings.cameraBack=v end})

    local Sell=createTab("Auto Sell", "dollar-sign")
    Sell:CreateSection("Sell by Rarity")
    local rarityOptions = getRarityTiers()
    Sell:CreateDropdown({Name="Equipment Rarity",Options=rarityOptions,CurrentOption={},MultipleOptions=true,Flag="IronSoulSellRarity",Callback=function(v) settings.sellEquipmentRarities=type(v)=="table"and v or{v} end})
    Sell:CreateDropdown({Name="Ores",Options=(function() local t={} for _,o in ipairs(getOres()) do table.insert(t,o.Name) end return t end)(),CurrentOption={},MultipleOptions=true,Flag="IronSoulSellOres",Callback=function(v) settings.sellOres=type(v)=="table"and v or{v} end})
    Sell:CreateDropdown({Name="Crystals",Options=(function() local t={} for _,c in ipairs(getCrystals()) do table.insert(t,c.Name) end return t end)(),CurrentOption={},MultipleOptions=true,Flag="IronSoulSellCrystals",Callback=function(v) settings.sellCrystals=type(v)=="table"and v or{v} end})
    Sell:CreateToggle({Name="Auto Sell",CurrentValue=false,Flag="IronSoulAutoSell",Callback=function(v) settings.autoSell=v end})

    local Progress=createTab("Progress", "map")
    Progress:CreateSection("Dungeon End")
    Progress:CreateToggle({Name="Auto Play Again",CurrentValue=false,Flag="IronSoulAutoPlayAgain",Callback=function(v) settings.autoPlayAgain=v end})
    Progress:CreateDropdown({Name="After Dungeon",Options={"Off","Replay","Return Lobby"},CurrentOption={"Off"},MultipleOptions=false,Flag="IronSoulEndAction",Callback=function(v) settings.endAction=type(v)=="table"and v[1]or v end})
    Progress:CreateSlider({Name="End Screen Delay",Range={1,12},Increment=.5,CurrentValue=3,Suffix="s",Flag="IronSoulEndActionDelay",Callback=function(v) settings.endActionDelay=v end})

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
    runCollectionWorker()
    runAutoPlayAgainWorker()
    runAutoSellWorker()
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
        if (settings.allowCameraChange or settings.cameraChange) and root and now>=cameraNextAt then
            cameraNextAt=now+.3
            local cam=workspace.CurrentCamera; cam.CameraType=Enum.CameraType.Scriptable; cam.CameraSubject=nil
            local camPos=root.Position+Vector3.new(0,settings.cameraDistance,settings.cameraBack)
            pcall(function()
                TweenService:Create(cam,TweenInfo.new(.3,Enum.EasingStyle.Quad),{CFrame=CFrame.lookAt(camPos,root.Position)}):Play()
                cam.Focus=CFrame.new(root.Position)
            end)
        end
        if settings.endAction~="Off" and #cachedEnemies==0 and now-lastEndAction>=math.max(settings.endActionDelay,1) then
            local button=endActionButton(settings.endAction)
            if button then
                lastEndAction=now
                local description=normalizedGuiText(button)
                if activateGuiButton(button) then
                    endActionState="activated "..settings.endAction.." ("..button.Name..")"
                else
                    endActionState="found result button but activation failed: "..description
                end
            else
                endActionState="waiting for "..settings.endAction.." result button"
            end
        elseif settings.endAction=="Off" then
            endActionState="off"
        elseif #cachedEnemies>0 then
            endActionState="dungeon active; waiting for victory"
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
                endActionLabel:Set("End action: "..endActionState)
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
    getgenv().__RAVEN_IRON_SOUL={Version="v1.6.0",Settings=settings,Destroy=destroy}
    if runtimeInfo and type(runtimeInfo.registerCleanup)=="function" then runtimeInfo.registerCleanup(destroy) end
end
