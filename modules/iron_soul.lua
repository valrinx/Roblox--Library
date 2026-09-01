--[[
    RAVEN HUB | Iron Soul: Dungeon
    Lobby PlaceId: 117533937949084 | Starless Forest: 116456628154258
    GameId: 9910245722 | Version: v1.4.1
]]
return function(Window, runtimeInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local CoreGui = game:GetService("CoreGui")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local LP = Players.LocalPlayer
    local running = true
    local connections, visuals = {}, {}
    local selectedTarget, spectating = nil, false
    local usedDoors = setmetatable({}, {__mode="k"})
    local controllerCache = nil
    local lastKnownRound, doorHandledRound = nil, nil
    local clearObservedAt, lastCompletedRound, pendingProgressRound, handledCompletedRound = nil, nil, nil, nil
    local lastEndAction, endActionState = 0, "waiting for dungeon result"
    local dodgeLockUntil, dodgeSafePosition = 0, nil

    pcall(function()
        local old = getgenv().__RAVEN_IRON_SOUL
        if old and type(old.Destroy) == "function" then old.Destroy() end
    end)

    local settings = {
        enemyEsp = true, maxDistance = 1500, showHp = true,
        targetMode = "Nearest", stickyTarget = true,
        autoFarm = false, autoAttack = true, autoSkills = false,
        farmMode = "Approach", farmDistance = 7, heightAbove = 8, actionDelay = 0.18,
        autoDodge = false, dodgeMode = "Air", dodgeMargin = 3, dodgeDistance = 16, dodgeVertical = 50, dodgeCooldown = 0.55, dodgeHold = 1.4,
        portalEsp = true, portalDistance = 2500,
        autoOpenDoor = false, autoNextPortal = false, progressOnlyWhenClear = true, progressCooldown = 2,
        progressMovement = "Teleport", progressOffset = 3, clearDelay = 2.5,
        endAction = "Off", endActionDelay = 3,
        bringMobs = false, bringMobsRange = 100,
        autoCollectChests = false, autoCollectEggs = false,
        walkSpeed = false, walkSpeedValue = 26,
        cameraChange = false, cameraDistance = 70, cameraBack = 50,
        autoSell = false, sellEquipmentRarities = {}, sellOres = {}, sellCrystals = {},
    }

    local guiRoot = (type(gethui) == "function" and gethui()) or CoreGui
    local folder = Instance.new("Folder")
    folder.Name = "RavenIronSoul"
    folder.Parent = guiRoot

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
    local function currentRoundInfo()
        local root=myRoot(); local respawns=workspace:FindFirstChild("PlayerRespawn")
        local bestPart,bestRound,bestDistance=nil,nil,math.huge
        if root and respawns then
            for _,part in ipairs(respawns:GetChildren()) do
                local round=part:IsA("BasePart") and tonumber(part.Name:match("%d+"))
                if round then local d=(part.Position-root.Position).Magnitude; if d<bestDistance then bestPart,bestRound,bestDistance=part,round,d end end
            end
        end
        return bestRound,bestPart
    end
    local function roundState()
        local cfg=game:GetService("ReplicatedStorage"):FindFirstChild("GameRoundCfg")
        local round=cfg and tonumber(cfg:GetAttribute("GameRound")); local complete=cfg and tonumber(cfg:GetAttribute("GameRoundComplete"))
        return round,complete
    end
    local function spawnForRound(round)
        local respawns=workspace:FindFirstChild("PlayerRespawn")
        return respawns and respawns:FindFirstChild("Round"..tostring(round)) or nil
    end
    local function progressPortals()
        local out={}; local holder=workspace:FindFirstChild("RoundDoor")
        if holder then for _,model in ipairs(holder:GetChildren()) do if model.Name=="Portal" and getPart(model) then table.insert(out,model) end end end
        return out
    end
    local function tapKey(keyCode)
        VirtualInputManager:SendKeyEvent(true,keyCode,false,game)
        task.delay(.03,function() pcall(function() VirtualInputManager:SendKeyEvent(false,keyCode,false,game) end) end)
    end
    local function getController()
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
    local function tapAttack()
        local controller=getController()
        if controller and pcall(function() controller:PerformAction("BaseAttack") end) then
            task.delay(.08,function() if running and controller==controllerCache then pcall(function() controller:StopAction("BaseAttack") end) end end)
            return
        end
        local camera=workspace.CurrentCamera; local size=camera and camera.ViewportSize or Vector2.new(960,540)
        VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,true,game,0)
        task.delay(.03,function() pcall(function() VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,false,game,0) end) end)
    end
    local function stopAttack()
        local controller=getController()
        if controller then pcall(function() controller:StopAction("BaseAttack") end) end
    end
    local function useReadySkills()
        local gui=LP:FindFirstChild("PlayerGui"); local input=gui and gui:FindFirstChild("ScreenInput")
        local pc=input and input:FindFirstChild("PCInput"); local skills=pc and pc:FindFirstChild("Skills")
        if not skills then return end
        local controller=getController()
        -- Priority 1: FullCharge → use SkillU (ultimate) only
        local skillU=skills:FindFirstChild("SkillU")
        if skillU and skillU.Visible and skillU:GetAttribute("OnCD")~=true and skillU:GetAttribute("FullCharge")==true then
            if controller then pcall(function() controller:PerformAction("SkillU") end) end
            task.wait(0.05)
            return
        end
        -- Priority 2: use available skills sequentially with delay
        for _,name in ipairs({"Skill1","Skill2","SkillAW"}) do
            local button=skills:FindFirstChild(name); local cool=button and button:FindFirstChild("Cool")
            if button and button.Visible and button:GetAttribute("OnCD")~=true and not (cool and cool.Visible) then
                if controller then
                    pcall(function() controller:PerformAction(name) end)
                else
                    local key=button:FindFirstChild("Key",true); local text=key and key:FindFirstChildWhichIsA("TextLabel",true)
                    local keyCode=text and Enum.KeyCode[text.Text]
                    pcall(function() button:Activate() end)
                    if keyCode then tapKey(keyCode) end
                end
                task.wait(0.05)
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
    local function collectChests()
        local root = myRoot(); if not root then return end
        for _, v in ipairs(workspace:GetChildren()) do
            if v:IsA("Model") and v.Name:find("Chest") and v:FindFirstChild("Root") and (v:GetAttribute("HitCount") or 0) > 0 then
                local chestRoot = v.Root
                root.CFrame = chestRoot.CFrame
                task.wait(0.15)
            end
        end
    end
    local function collectDragonEggs()
        local root = myRoot(); if not root then return end
        for _, v in ipairs(workspace:GetChildren()) do
            if v:FindFirstChild("DragonEgg") and v.DragonEgg:FindFirstChild("EggModel") and v.DragonEgg.EggModel:FindFirstChild("Root") and v:FindFirstChild("Root") and not v:GetAttribute("Active") then
                root.CFrame = v.DragonEgg.EggModel.Root.CFrame
                task.wait(0.1)
                if type(fireproximityprompt) == "function" and v.Root:FindFirstChild("Interact_ProximityPrompt") then
                    pcall(fireproximityprompt, v.Root.Interact_ProximityPrompt)
                end
            end
        end
    end
    local function bringMobsToTarget()
        local root = myRoot(); if not root then return end
        local targetPart = getPart(selectedTarget)
        if not targetPart then return end
        for _, v in ipairs(workspace.EnemyNpc:GetChildren()) do
            if v:IsA("Model") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                if (targetPart.Position - v.HumanoidRootPart.Position).Magnitude <= settings.bringMobsRange then
                    v.HumanoidRootPart.CFrame = targetPart.CFrame
                end
            end
        end
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
    Dashboard:CreateSection("Iron Soul v1.4.1")
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
    Farm:CreateToggle({Name="Auto Skills (Ready Only)",CurrentValue=false,Flag="IronSoulAutoSkills",Callback=function(v) settings.autoSkills=v end})
    Farm:CreateDropdown({Name="Farm Position",Options={"Approach","Above Target","Below Target"},CurrentOption={"Approach"},MultipleOptions=false,Flag="IronSoulFarmMode",Callback=function(v) settings.farmMode=type(v)=="table"and v[1]or v end})
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
    Utility:CreateToggle({Name="Custom WalkSpeed",CurrentValue=false,Flag="IronSoulWalkSpeed",Callback=function(v) settings.walkSpeed=v end})
    Utility:CreateSlider({Name="WalkSpeed Value",Range={1,100},Increment=1,CurrentValue=26,Suffix="",Flag="IronSoulWalkSpeedVal",Callback=function(v) settings.walkSpeedValue=v end})
    Utility:CreateSection("Camera")
    Utility:CreateToggle({Name="Custom Camera (AFK View)",CurrentValue=false,Flag="IronSoulCamera",Callback=function(v) settings.cameraChange=v if not v then workspace.CurrentCamera.CameraType=Enum.CameraType.Custom workspace.CurrentCamera.CameraSubject=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid") end end})
    Utility:CreateSlider({Name="Camera Distance",Range={10,150},Increment=5,CurrentValue=70,Suffix=" studs",Flag="IronSoulCamDist",Callback=function(v) settings.cameraDistance=v end})

    local Sell=createTab("Auto Sell", "dollar-sign")
    Sell:CreateSection("Sell by Rarity")
    local rarityOptions = getRarityTiers()
    Sell:CreateDropdown({Name="Equipment Rarity",Options=rarityOptions,CurrentOption={},MultipleOptions=true,Flag="IronSoulSellRarity",Callback=function(v) settings.sellEquipmentRarities=type(v)=="table"and v or{v} end})
    Sell:CreateDropdown({Name="Ores",Options=(function() local t={} for _,o in ipairs(getOres()) do table.insert(t,o.Name) end return t end)(),CurrentOption={},MultipleOptions=true,Flag="IronSoulSellOres",Callback=function(v) settings.sellOres=type(v)=="table"and v or{v} end})
    Sell:CreateDropdown({Name="Crystals",Options=(function() local t={} for _,c in ipairs(getCrystals()) do table.insert(t,c.Name) end return t end)(),CurrentOption={},MultipleOptions=true,Flag="IronSoulSellCrystals",Callback=function(v) settings.sellCrystals=type(v)=="table"and v or{v} end})
    Sell:CreateToggle({Name="Auto Sell",CurrentValue=false,Flag="IronSoulAutoSell",Callback=function(v) settings.autoSell=v end})

    local Progress=createTab("Progress", "map")
    Progress:CreateSection("Round / Portal")
    Progress:CreateToggle({Name="Portal ESP",CurrentValue=true,Flag="IronSoulPortalESP",Callback=function(v) settings.portalEsp=v end})
    Progress:CreateSlider({Name="Portal Distance",Range={250,6000},Increment=250,CurrentValue=2500,Suffix=" studs",Flag="IronSoulPortalDistance",Callback=function(v) settings.portalDistance=v end})
    local portalLabel=Progress:CreateLabel("Nearest portal: scanning...")
    local doorLabel=Progress:CreateLabel("Round doors: scanning...")
    local progressStateLabel=Progress:CreateLabel("Automation: idle")
    Progress:CreateSection("Progress Automation")
    Progress:CreateToggle({Name="Auto Open Round Door",CurrentValue=false,Flag="IronSoulAutoDoor",Callback=function(v) settings.autoOpenDoor=v end})
    Progress:CreateToggle({Name="Auto Next Round Portal",CurrentValue=false,Flag="IronSoulAutoPortal",Callback=function(v) settings.autoNextPortal=v end})
    Progress:CreateToggle({Name="Only When Enemies Clear",CurrentValue=true,Flag="IronSoulProgressClear",Callback=function(v) settings.progressOnlyWhenClear=v end})
    Progress:CreateDropdown({Name="Movement Mode",Options={"Teleport","Walk"},CurrentOption={"Teleport"},MultipleOptions=false,Flag="IronSoulProgressMovement",Callback=function(v) settings.progressMovement=type(v)=="table"and v[1]or v end})
    Progress:CreateSlider({Name="Teleport Offset",Range={1,8},Increment=.5,CurrentValue=3,Suffix=" studs",Flag="IronSoulProgressOffset",Callback=function(v) settings.progressOffset=v end})
    Progress:CreateSlider({Name="Clear Confirmation Delay",Range={0.5,6},Increment=.5,CurrentValue=2.5,Suffix="s",Flag="IronSoulClearDelay",Callback=function(v) settings.clearDelay=v end})
    Progress:CreateSlider({Name="Progress Cooldown",Range={1,8},Increment=.5,CurrentValue=2,Suffix="s",Flag="IronSoulProgressCooldown",Callback=function(v) settings.progressCooldown=v end})
    Progress:CreateSection("Dungeon End v1.3")
    Progress:CreateDropdown({Name="After Dungeon",Options={"Off","Replay","Return Lobby"},CurrentOption={"Off"},MultipleOptions=false,Flag="IronSoulEndAction",Callback=function(v) settings.endAction=type(v)=="table"and v[1]or v end})
    Progress:CreateSlider({Name="End Screen Delay",Range={1,12},Increment=.5,CurrentValue=3,Suffix="s",Flag="IronSoulEndActionDelay",Callback=function(v) settings.endActionDelay=v end})

    local lastDodge,lastAction,lastProgress,lastEntryRecovery,scanAt,statusAt=0,0,0,0,0,0
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

        local farmPart=getPart(selectedTarget)
        if settings.autoFarm and not danger and not dodgeLocked and root and farmPart then
            local humanoid=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if settings.farmMode=="Above Target" then
                local desired=farmPart.Position+Vector3.new(0,settings.heightAbove,0)
                root.CFrame=CFrame.lookAt(desired,farmPart.Position)
            elseif settings.farmMode=="Below Target" then
                local desired=farmPart.Position-Vector3.new(0,settings.heightAbove,0)
                root.CFrame=CFrame.lookAt(desired,farmPart.Position)
            else
                local flat=Vector3.new(root.Position.X-farmPart.Position.X,0,root.Position.Z-farmPart.Position.Z)
                if flat.Magnitude<.1 then flat=-farmPart.CFrame.LookVector end
                local desired=farmPart.Position+flat.Unit*settings.farmDistance
                if humanoid and (root.Position-desired).Magnitude>2 then humanoid:MoveTo(desired) end
                root.CFrame=CFrame.lookAt(root.Position,Vector3.new(farmPart.Position.X,root.Position.Y,farmPart.Position.Z))
            end
            if distance(farmPart)<=math.max(settings.farmDistance+4,12) and now-lastAction>=settings.actionDelay then
                lastAction=now
                if settings.autoAttack then tapAttack() end
                if settings.autoSkills then useReadySkills() end
            end
        else
            stopAttack()
        end

        if settings.bringMobs and selectedTarget and root then bringMobsToTarget() end
        if settings.autoCollectChests and #cachedEnemies==0 then pcall(collectChests) end
        if settings.autoCollectEggs and #cachedEnemies==0 then pcall(collectDragonEggs) end
        if settings.walkSpeed then
            local hum=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.WalkSpeed=settings.walkSpeedValue end
        end
        if settings.cameraChange and root then
            local cam=workspace.CurrentCamera; cam.CameraType=Enum.CameraType.Scriptable; cam.CameraSubject=nil
            local camPos=root.Position+Vector3.new(0,settings.cameraDistance,settings.cameraBack)
            pcall(function() cam.CFrame=CFrame.lookAt(camPos,root.Position) end)
        end
        if settings.autoSell and now-lastAction>=2 then
            if #settings.sellEquipmentRarities>0 then pcall(function() sellEquipmentByRarity(settings.sellEquipmentRarities) end) end
            if #settings.sellOres>0 then pcall(function() sellOres(settings.sellOres) end) end
            if #settings.sellCrystals>0 then pcall(function() sellCrystals(settings.sellCrystals) end) end
        end

        local officialRound,completedRound=roundState()
        local locationRound=currentRoundInfo()
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
        if settings.autoNextPortal and #cachedEnemies==0 and root and officialRound and completedRound and completedRound==officialRound-1 and now-lastProgress>=settings.progressCooldown then
            local targetRound=officialRound
            local nearestPortal,portalDistance=nil,math.huge
            local fallbackPortal,fallbackDistance=nil,math.huge
            for _,portal in ipairs(progressPortals()) do local pp=getPart(portal); if pp and pp:FindFirstChildOfClass("TouchTransmitter") then
                local portalRound=pp:GetAttribute("RoundNum") or portal:GetAttribute("RoundNum")
                local d=distance(pp)
                if portalRound==targetRound and d<portalDistance then nearestPortal,portalDistance=pp,d end
                if d<fallbackDistance then fallbackPortal,fallbackDistance=pp,d end
            end end
            if not nearestPortal and fallbackPortal then nearestPortal=fallbackPortal; portalDistance=fallbackDistance end
            local holder=workspace:FindFirstChild("RoundDoor"); local openDoorDistance=math.huge
            if holder then for _,prompt in ipairs(holder:GetDescendants()) do if prompt:IsA("ProximityPrompt") and not prompt.Enabled then local parent=prompt.Parent; local part=parent and (parent:IsA("BasePart") and parent or parent.Parent); if part and part:IsA("BasePart") then openDoorDistance=math.min(openDoorDistance,distance(part)) end end end end
            if nearestPortal and (portalDistance<=35 or (not nearestPortal:GetAttribute("RoundNum") and fallbackDistance<=60)) and openDoorDistance<=45 then
                lastProgress=now; handledCompletedRound=completedRound
                root.CFrame=nearestPortal.CFrame*CFrame.new(0,2,-math.min(settings.progressOffset,2))
                local portalRoot,boundRoot=nearestPortal,root
                task.delay(.15,function() if running and portalRoot.Parent and boundRoot.Parent and type(firetouchinterest)=="function" then pcall(firetouchinterest,boundRoot,portalRoot,0); pcall(firetouchinterest,boundRoot,portalRoot,1) end end)
            end
        end
        if settings.autoOpenDoor and #cachedEnemies==0 and root and officialRound and now-lastEntryRecovery>=3 then
            local holder=workspace:FindFirstChild("RoundDoor"); local nearestOpenDoor=math.huge
            if holder then
                for _,prompt in ipairs(holder:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") and not prompt.Enabled then
                        local parent=prompt.Parent; local part=parent and (parent:IsA("BasePart") and parent or parent.Parent)
                        if part and part:IsA("BasePart") then nearestOpenDoor=math.min(nearestOpenDoor,distance(part)) end
                    end
                end
            end
            local destination=spawnForRound(officialRound)
            if destination and nearestOpenDoor<=25 then
                lastEntryRecovery=now; root.CFrame=destination.CFrame*CFrame.new(0,3,0)
            end
        end
        if completedRound then
            if lastCompletedRound==nil then lastCompletedRound=completedRound end
            if completedRound>lastCompletedRound then
                lastCompletedRound=completedRound; handledCompletedRound=nil; pendingProgressRound=completedRound; clearObservedAt=now
            elseif not pendingProgressRound and handledCompletedRound~=completedRound and #cachedEnemies==0 and locationRound==completedRound and officialRound and completedRound<officialRound then
                pendingProgressRound=completedRound; clearObservedAt=now
            end
        end
        if pendingProgressRound and locationRound and locationRound~=pendingProgressRound and #cachedEnemies>0 then
            pendingProgressRound=nil; clearObservedAt=nil
        end
        local clearConfirmed=pendingProgressRound~=nil and clearObservedAt~=nil and now-clearObservedAt>=settings.clearDelay
        local canProgress=not settings.progressOnlyWhenClear or clearConfirmed
        local progressState
        if clearConfirmed then progressState="Round"..tostring(pendingProgressRound).." clear confirmed"
        elseif pendingProgressRound then progressState=string.format("confirming Round%s clear | %.1fs",tostring(pendingProgressRound),math.max(0,settings.clearDelay-(now-(clearObservedAt or now))))
        else progressState=string.format("waiting for game clear | round %s, completed %s",tostring(officialRound or "?"),tostring(completedRound or "?")) end
        if canProgress and root and now-lastProgress>=settings.progressCooldown then
            local currentRound=pendingProgressRound or locationRound or officialRound
            local roundSpawn=spawnForRound(currentRound)
            if currentRound~=lastKnownRound then lastKnownRound=currentRound; doorHandledRound=nil; table.clear(usedDoors) end
            local used=false
            local matchingDoorExists=false
            if settings.autoOpenDoor then
                local doors=workspace:FindFirstChild("RoundDoor"); local bestPrompt,bestDistance=nil,math.huge
                local reference=roundSpawn and roundSpawn.Position or root.Position
                if doors then
                    for _,prompt in ipairs(doors:GetDescendants()) do
                        if prompt:IsA("ProximityPrompt") then
                            local parent=prompt.Parent; local part=parent and (parent:IsA("BasePart") and parent or parent.Parent)
                            local doorRound=part and part:GetAttribute("RoundNum")
                            if part and part:IsA("BasePart") and doorRound==currentRound then
                                matchingDoorExists=true
                                if prompt.Enabled and not usedDoors[prompt] and doorHandledRound~=currentRound then
                                    local d=(part.Position-reference).Magnitude; if d<bestDistance then bestPrompt,bestDistance=prompt,d end
                                end
                            end
                        end
                    end
                end
                if bestPrompt then
                    local parent=bestPrompt.Parent; local part=parent and (parent:IsA("BasePart") and parent or parent.Parent)
                    local playerDistance=part and distance(part) or math.huge
                    if playerDistance>10 and part and part:IsA("BasePart") then
                        if settings.progressMovement=="Teleport" then
                            root.CFrame=part.CFrame*CFrame.new(0,0,-settings.progressOffset)
                            local flat=Vector3.new(part.Position.X-reference.X,0,part.Position.Z-reference.Z)
                            if flat.Magnitude<.1 then flat=part.CFrame.LookVector end
                            local entryPos=part.Position+flat.Unit*18; entryPos=Vector3.new(entryPos.X,(roundSpawn and roundSpawn.Position.Y or root.Position.Y)+3,entryPos.Z)
                            local entryCFrame=CFrame.lookAt(entryPos,entryPos+flat.Unit)
                            usedDoors[bestPrompt]=true; doorHandledRound=currentRound; handledCompletedRound=currentRound; used=true; lastProgress=now
                            task.delay(.15,function() if running and bestPrompt.Parent and type(fireproximityprompt)=="function" then pcall(fireproximityprompt,bestPrompt) end end)
                            task.delay(.45,function() if running and root.Parent then root.CFrame=entryCFrame end end)
                            progressState="opening and entering beyond Round"..tostring(currentRound).." door"
                        else
                            local humanoid=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                            if humanoid then humanoid:MoveTo(part.Position) end
                            progressState=string.format("walking to door | %dm",math.floor(playerDistance))
                        end
                    elseif type(fireproximityprompt)=="function" then
                        pcall(fireproximityprompt,bestPrompt); usedDoors[bestPrompt]=true; doorHandledRound=currentRound; used=true; progressState="opened Round"..tostring(currentRound).." door; waiting for room change"
                    end
                elseif matchingDoorExists and doorHandledRound==currentRound then
                    progressState="door handled; waiting to enter next room"
                end
            end
            if not used and not matchingDoorExists and doorHandledRound~=currentRound and settings.autoNextPortal and type(firetouchinterest)=="function" then
                local bestPortal,bestDistance=nil,math.huge
                local fallbackPortal,fallbackDistance=nil,math.huge; local reference=roundSpawn and roundSpawn.Position or root.Position
                for _,portal in ipairs(progressPortals()) do
                    local pp=getPart(portal); local round=pp and (pp:GetAttribute("RoundNum") or portal:GetAttribute("RoundNum")); local d=distance(pp)
                    if pp and pp:FindFirstChildOfClass("TouchTransmitter") and round==currentRound and d<bestDistance then bestPortal,bestDistance=pp,d end
                    if pp and pp:FindFirstChildOfClass("TouchTransmitter") then local rd=(pp.Position-reference).Magnitude; if rd<fallbackDistance then fallbackPortal,fallbackDistance=pp,rd end end
                end
                if not bestPortal and fallbackPortal then bestPortal= fallbackPortal; bestDistance=distance(fallbackPortal); progressState="using nearest real portal fallback" end
                if bestPortal then
                    if bestDistance>8 then
                        if settings.progressMovement=="Teleport" then
                            root.CFrame=bestPortal.CFrame*CFrame.new(0,2,-settings.progressOffset)
                            used=true; lastProgress=now
                            local portalRoot,boundRoot=bestPortal,root
                            task.delay(.15,function()
                                if running and portalRoot.Parent and boundRoot.Parent and type(firetouchinterest)=="function" then
                                    pcall(firetouchinterest,boundRoot,portalRoot,0); pcall(firetouchinterest,boundRoot,portalRoot,1)
                                    handledCompletedRound=pendingProgressRound; pendingProgressRound=nil; clearObservedAt=nil
                                end
                            end)
                            progressState="teleported and entering portal R"..tostring(bestPortal:GetAttribute("RoundNum") or "?")
                        else
                            local humanoid=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                            if humanoid then humanoid:MoveTo(bestPortal.Position) end
                            progressState=string.format("walking to portal R%s | %dm",tostring(bestPortal:GetAttribute("RoundNum") or "?"),math.floor(bestDistance))
                        end
                    else
                        pcall(firetouchinterest,root,bestPortal,0); pcall(firetouchinterest,root,bestPortal,1); used=true; progressState="entered next portal"
                    end
                end
            end
            if used then lastProgress=now end
        end

        if now-statusAt>=.35 then
            statusAt=now
            local targetPart=getPart(selectedTarget); local targetHum=getHumanoid(selectedTarget)
            local nearestPortal,nearestDistance=nil,math.huge; local portalCount=0
            local activePortals={}
            for _,p in ipairs(progressPortals()) do
                    local pp=getPart(p); local d=distance(pp)
                    if d<nearestDistance then nearestPortal,nearestDistance=p,d end
                    if d<=settings.portalDistance then
                        portalCount+=1
                        if settings.portalEsp and pp then
                            activePortals[p]=true
                            local color=Color3.fromRGB(95,190,255)
                            local v=ensureVisual(p,p,pp,color)
                            local round=pp:GetAttribute("RoundNum") or p:GetAttribute("RoundNum")
                            if v then
                                v.label.Text=string.format("Portal%s | %dm",round~=nil and " R"..tostring(round) or "",math.floor(d))
                                v.label.TextColor3=color; v.highlight.FillColor=color; v.highlight.OutlineColor=color
                            end
                        end
                    end
            end
            for key in pairs(visuals) do
                local ok,isOld=pcall(function() return key.Name=="Portal" and not activePortals[key] and key.Parent==workspace:FindFirstChild("RoundDoor") end)
                if ok and isOld then removeVisual(key) end
            end
            local doors=workspace:FindFirstChild("RoundDoor"); local gameRound,gameRoundComplete=roundState()
            pcall(function()
                roundLabel:Set(string.format("Game round: %s | completed: %s%s",tostring(gameRound or "?"),tostring(gameRoundComplete or "?"),pendingProgressRound and " | MOVE R"..tostring(pendingProgressRound) or ""))
                enemyCountLabel:Set("Enemies alive: "..tostring(#cachedEnemies))
                targetLabel:Set(selectedTarget and string.format("Target: %s | HP %d/%d | %dm",enemyName(selectedTarget),math.floor(targetHum.Health),math.floor(targetHum.MaxHealth),math.floor(distance(targetPart))) or "Target: none")
                dodgeLabel:Set(danger and "Redzone: DODGING" or dodgeLocked and string.format("Redzone: holding safe %.1fs",math.max(0,dodgeLockUntil-now)) or "Redzone: clear")
                portalLabel:Set(nearestPortal and string.format("Nearest portal: %dm | %d in range",math.floor(nearestDistance),portalCount) or "Nearest portal: none")
                doorLabel:Set("Round doors: "..tostring(doors and #doors:GetChildren() or 0))
                progressStateLabel:Set("Automation: "..progressState)
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
        pcall(function() folder:Destroy() end)
        local camera=workspace.CurrentCamera; if camera and LP.Character then camera.CameraSubject=LP.Character:FindFirstChildOfClass("Humanoid") end
        if getgenv().__RAVEN_IRON_SOUL and getgenv().__RAVEN_IRON_SOUL.Settings==settings then getgenv().__RAVEN_IRON_SOUL=nil end
    end
    getgenv().__RAVEN_IRON_SOUL={Version="v1.4.0",Settings=settings,Destroy=destroy}
    if runtimeInfo and type(runtimeInfo.registerCleanup)=="function" then runtimeInfo.registerCleanup(destroy) end
end
