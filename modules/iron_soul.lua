--[[
    RAVEN HUB | Iron Soul: Dungeon
    Lobby PlaceId: 117533937949084 | Starless Forest: 116456628154258
    GameId: 9910245722 | Version: v1.2.6
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
    local clearObservedAt, clearObservedRound = nil, nil

    pcall(function()
        local old = getgenv().__RAVEN_IRON_SOUL
        if old and type(old.Destroy) == "function" then old.Destroy() end
    end)

    local settings = {
        enemyEsp = true, maxDistance = 1500, showHp = true,
        targetMode = "Nearest", stickyTarget = true,
        autoFarm = false, autoAttack = true, autoSkills = false,
        farmMode = "Approach", farmDistance = 7, heightAbove = 8, actionDelay = 0.18,
        autoDodge = false, dodgeMargin = 3, dodgeDistance = 16, dodgeCooldown = 0.55,
        portalEsp = true, portalDistance = 2500,
        autoOpenDoor = false, autoNextPortal = false, progressOnlyWhenClear = true, progressCooldown = 2,
        progressMovement = "Teleport", progressOffset = 3, clearDelay = 2.5,
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
        local cfg=game:GetService("ReplicatedStorage"):FindFirstChild("GameRoundCfg")
        local officialRound=cfg and tonumber(cfg:GetAttribute("GameRound"))
        local bestPart,bestRound,bestDistance=nil,nil,math.huge
        if root and respawns then
            for _,part in ipairs(respawns:GetChildren()) do
                local round=part:IsA("BasePart") and tonumber(part.Name:match("%d+"))
                if round and (not officialRound or round==officialRound) then local d=(part.Position-root.Position).Magnitude; if d<bestDistance then bestPart,bestRound,bestDistance=part,round,d end end
            end
        end
        return officialRound or bestRound,bestPart
    end
    local function officialRoundClear()
        local cfg=game:GetService("ReplicatedStorage"):FindFirstChild("GameRoundCfg")
        local round=cfg and tonumber(cfg:GetAttribute("GameRound")); local complete=cfg and tonumber(cfg:GetAttribute("GameRoundComplete"))
        return round~=nil and complete~=nil and complete>=round,round,complete
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
        if controller and pcall(function() controller:PerformAction("BaseAttack") end) then return end
        local camera=workspace.CurrentCamera; local size=camera and camera.ViewportSize or Vector2.new(960,540)
        VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,true,game,0)
        task.delay(.03,function() pcall(function() VirtualInputManager:SendMouseButtonEvent(size.X/2,size.Y/2,0,false,game,0) end) end)
    end
    local function useReadySkills()
        local gui=LP:FindFirstChild("PlayerGui"); local input=gui and gui:FindFirstChild("ScreenInput")
        local pc=input and input:FindFirstChild("PCInput"); local skills=pc and pc:FindFirstChild("Skills")
        if not skills then return end
        local controller=getController()
        for _,name in ipairs({"Skill1","Skill2","SkillU","SkillAW"}) do
            local button=skills:FindFirstChild(name); local cool=button and button:FindFirstChild("Cool")
            local key=button and button:FindFirstChild("Key",true); local text=key and key:FindFirstChildWhichIsA("TextLabel",true)
            local keyCode=text and Enum.KeyCode[text.Text]
            if button and button.Visible and button:GetAttribute("OnCD")~=true and not (cool and cool.Visible) and keyCode then
                local performed=controller and pcall(function() controller:PerformAction(name) end)
                if not performed then pcall(function() button:Activate() end); tapKey(keyCode) end
            end
        end
    end

    local function removeVisual(key)
        local v=visuals[key]; if not v then return end
        pcall(function() v.highlight:Destroy() end); pcall(function() v.billboard:Destroy() end); visuals[key]=nil
    end
    local function ensureVisual(key, adornee, part, color)
        local v=visuals[key]
        if v and v.adornee==adornee and v.part==part then return v end
        removeVisual(key)
        local h=Instance.new("Highlight"); h.Adornee=adornee; h.FillTransparency=.78; h.OutlineTransparency=.05
        h.FillColor=color; h.OutlineColor=color; h.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; h.Parent=folder
        local b=Instance.new("BillboardGui"); b.Adornee=part; b.AlwaysOnTop=true; b.Size=UDim2.fromOffset(240,44); b.StudsOffset=Vector3.new(0,3,0); b.Parent=folder
        local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Size=UDim2.fromScale(1,1); l.Font=Enum.Font.GothamSemibold
        l.TextSize=13; l.TextStrokeTransparency=.2; l.TextColor3=color; l.Parent=b
        v={adornee=adornee,part=part,highlight=h,billboard=b,label=l}; visuals[key]=v; return v
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

    local Dashboard=Window:CreateTab("Dungeon", "activity")
    Dashboard:CreateSection("Iron Soul v1.2.6")
    local roundLabel=Dashboard:CreateLabel("Round: scanning...")
    local enemyCountLabel=Dashboard:CreateLabel("Enemies: scanning...")
    local targetLabel=Dashboard:CreateLabel("Target: none")
    local dodgeLabel=Dashboard:CreateLabel("Redzone: clear")

    local Combat=Window:CreateTab("Combat Intel", "crosshair")
    Combat:CreateSection("Enemy ESP")
    Combat:CreateToggle({Name="Enemy ESP",CurrentValue=true,Flag="IronSoulEnemyESP",Callback=function(v) settings.enemyEsp=v end})
    Combat:CreateToggle({Name="Show HP",CurrentValue=true,Flag="IronSoulShowHP",Callback=function(v) settings.showHp=v end})
    Combat:CreateSlider({Name="ESP Distance",Range={100,4000},Increment=100,CurrentValue=1500,Suffix=" studs",Flag="IronSoulESPDistance",Callback=function(v) settings.maxDistance=v end})
    Combat:CreateSection("Target")
    Combat:CreateDropdown({Name="Target Mode",Options={"Nearest","Lowest HP"},CurrentOption={"Nearest"},MultipleOptions=false,Flag="IronSoulTargetMode",Callback=function(v) settings.targetMode=type(v)=="table"and v[1]or v selectedTarget=nil end})
    Combat:CreateToggle({Name="Sticky Target",CurrentValue=true,Flag="IronSoulSticky",Callback=function(v) settings.stickyTarget=v if not v then selectedTarget=nil end end})
    Combat:CreateToggle({Name="Spectate Current Target",CurrentValue=false,Flag="IronSoulSpectate",Callback=function(v) spectating=v end})

    local Farm=Window:CreateTab("Autofarm", "swords")
    Farm:CreateSection("Target Based Autofarm")
    Farm:CreateToggle({Name="Auto Farm Target",CurrentValue=false,Flag="IronSoulAutoFarm",Callback=function(v) settings.autoFarm=v end})
    Farm:CreateToggle({Name="Auto Base Attack",CurrentValue=true,Flag="IronSoulAutoAttack",Callback=function(v) settings.autoAttack=v end})
    Farm:CreateToggle({Name="Auto Skills (Ready Only)",CurrentValue=false,Flag="IronSoulAutoSkills",Callback=function(v) settings.autoSkills=v end})
    Farm:CreateDropdown({Name="Farm Position",Options={"Approach","Above Target"},CurrentOption={"Approach"},MultipleOptions=false,Flag="IronSoulFarmMode",Callback=function(v) settings.farmMode=type(v)=="table"and v[1]or v end})
    Farm:CreateSlider({Name="Attack Distance",Range={3,30},Increment=1,CurrentValue=7,Suffix=" studs",Flag="IronSoulFarmDistance",Callback=function(v) settings.farmDistance=v end})
    Farm:CreateSlider({Name="Height Above Target",Range={3,30},Increment=1,CurrentValue=8,Suffix=" studs",Flag="IronSoulFarmHeight",Callback=function(v) settings.heightAbove=v end})
    Farm:CreateSlider({Name="Action Delay",Range={0.1,0.8},Increment=.02,CurrentValue=.18,Suffix="s",Flag="IronSoulActionDelay",Callback=function(v) settings.actionDelay=v end})

    local Dodge=Window:CreateTab("Dodge", "shield")
    Dodge:CreateSection("RedShow Avoidance")
    Dodge:CreateToggle({Name="Auto Dodge Redzone",CurrentValue=false,Flag="IronSoulAutoDodge",Callback=function(v) settings.autoDodge=v end})
    Dodge:CreateSlider({Name="Safety Margin",Range={0,12},Increment=1,CurrentValue=3,Suffix=" studs",Flag="IronSoulDodgeMargin",Callback=function(v) settings.dodgeMargin=v end})
    Dodge:CreateSlider({Name="Dodge Distance",Range={6,30},Increment=1,CurrentValue=16,Suffix=" studs",Flag="IronSoulDodgeDistance",Callback=function(v) settings.dodgeDistance=v end})
    Dodge:CreateSlider({Name="Dodge Cooldown",Range={0.2,1.5},Increment=.05,CurrentValue=.55,Suffix="s",Flag="IronSoulDodgeCooldown",Callback=function(v) settings.dodgeCooldown=v end})

    local Progress=Window:CreateTab("Progress", "map")
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

    local lastDodge,lastAction,lastProgress,scanAt,statusAt=0,0,0,0,0
    local cachedEnemies={}
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
                    v.label.Text=string.format("%s%s | %dm",enemyName(e.model),hp,math.floor(e.distance)); v.label.TextColor3=color
                    v.highlight.FillColor=color; v.highlight.OutlineColor=color
                end
            end
            for key in pairs(visuals) do if typeof(key)=="Instance" and key.Parent==workspace:FindFirstChild("EnemyNpc") and not active[key] then removeVisual(key) end end
        end

        local root=myRoot(); local red=workspace:FindFirstChild("RedShow"); local danger=nil
        if root and red then
            for _,zone in ipairs(red:GetDescendants()) do
                if zone:IsA("BasePart") and zone.Transparency<1 then
                    local localPos=zone.CFrame:PointToObjectSpace(root.Position)
                    if math.abs(localPos.X)<=zone.Size.X/2+settings.dodgeMargin and math.abs(localPos.Z)<=zone.Size.Z/2+settings.dodgeMargin then danger=zone break end
                end
            end
        end
        if danger and settings.autoDodge and now-lastDodge>=settings.dodgeCooldown and root then
            lastDodge=now
            local away=Vector3.new(root.Position.X-danger.Position.X,0,root.Position.Z-danger.Position.Z)
            if away.Magnitude<.1 then away=root.CFrame.RightVector end
            local humanoid=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid:MoveTo(root.Position+away.Unit*settings.dodgeDistance) end
        end

        local farmPart=getPart(selectedTarget)
        if settings.autoFarm and not danger and root and farmPart then
            local humanoid=LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            if settings.farmMode=="Above Target" then
                local desired=farmPart.Position+Vector3.new(0,settings.heightAbove,0)
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
        end

        local officiallyClear,officialRound,completedRound=officialRoundClear()
        if officiallyClear then
            if clearObservedRound~=officialRound then clearObservedRound=officialRound; clearObservedAt=now end
        else
            clearObservedRound=nil; clearObservedAt=nil
        end
        local clearConfirmed=officiallyClear and clearObservedAt and now-clearObservedAt>=settings.clearDelay
        local canProgress=not settings.progressOnlyWhenClear or clearConfirmed
        local progressState
        if clearConfirmed then progressState="official clear confirmed"
        elseif officiallyClear then progressState=string.format("confirming game clear | %.1fs",math.max(0,settings.clearDelay-(now-(clearObservedAt or now))))
        else progressState=string.format("waiting for game clear | round %s, completed %s",tostring(officialRound or "?"),tostring(completedRound or "?")) end
        if canProgress and root and now-lastProgress>=settings.progressCooldown then
            local currentRound,roundSpawn=currentRoundInfo()
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
                            usedDoors[bestPrompt]=true; doorHandledRound=currentRound; used=true; lastProgress=now
                            task.delay(.15,function() if running and bestPrompt.Parent and type(fireproximityprompt)=="function" then pcall(fireproximityprompt,bestPrompt) end end)
                            progressState="teleported and opening Round"..tostring(currentRound).." door"
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
                for _,portal in ipairs(progressPortals()) do
                    local pp=getPart(portal); local round=pp and (pp:GetAttribute("RoundNum") or portal:GetAttribute("RoundNum")); local d=distance(pp)
                    if pp and pp:FindFirstChildOfClass("TouchTransmitter") and round==currentRound and d<bestDistance then bestPortal,bestDistance=pp,d end
                end
                if bestPortal then
                    if bestDistance>8 then
                        if settings.progressMovement=="Teleport" then
                            root.CFrame=bestPortal.CFrame*CFrame.new(0,2,-settings.progressOffset)
                            used=true; lastProgress=now
                            local portalRoot,boundRoot=bestPortal,root
                            task.delay(.15,function()
                                if running and portalRoot.Parent and boundRoot.Parent and type(firetouchinterest)=="function" then
                                    pcall(firetouchinterest,boundRoot,portalRoot,0); pcall(firetouchinterest,boundRoot,portalRoot,1)
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
                            v.label.Text=string.format("Portal%s | %dm",round~=nil and " R"..tostring(round) or "",math.floor(d))
                            v.label.TextColor3=color; v.highlight.FillColor=color; v.highlight.OutlineColor=color
                        end
                    end
            end
            for key in pairs(visuals) do
                if typeof(key)=="Instance" and key.Name=="Portal" and not activePortals[key] and key.Parent==workspace:FindFirstChild("RoundDoor") then removeVisual(key) end
            end
            local doors=workspace:FindFirstChild("RoundDoor"); local officialClear,gameRound,gameRoundComplete=officialRoundClear()
            pcall(function()
                roundLabel:Set(string.format("Game round: %s | completed: %s%s",tostring(gameRound or "?"),tostring(gameRoundComplete or "?"),officialClear and " | CLEAR" or ""))
                enemyCountLabel:Set("Enemies alive: "..tostring(#cachedEnemies))
                targetLabel:Set(selectedTarget and string.format("Target: %s | HP %d/%d | %dm",enemyName(selectedTarget),math.floor(targetHum.Health),math.floor(targetHum.MaxHealth),math.floor(distance(targetPart))) or "Target: none")
                dodgeLabel:Set(danger and "Redzone: DANGER" or "Redzone: clear")
                portalLabel:Set(nearestPortal and string.format("Nearest portal: %dm | %d in range",math.floor(nearestDistance),portalCount) or "Nearest portal: none")
                doorLabel:Set("Round doors: "..tostring(doors and #doors:GetChildren() or 0))
                progressStateLabel:Set("Automation: "..progressState)
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
        for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        for key in pairs(visuals) do removeVisual(key) end
        pcall(function() folder:Destroy() end)
        local camera=workspace.CurrentCamera; if camera and LP.Character then camera.CameraSubject=LP.Character:FindFirstChildOfClass("Humanoid") end
        if getgenv().__RAVEN_IRON_SOUL and getgenv().__RAVEN_IRON_SOUL.Settings==settings then getgenv().__RAVEN_IRON_SOUL=nil end
    end
    getgenv().__RAVEN_IRON_SOUL={Version="v1.2.6",Settings=settings,Destroy=destroy}
    if runtimeInfo and type(runtimeInfo.registerCleanup)=="function" then runtimeInfo.registerCleanup(destroy) end
end
