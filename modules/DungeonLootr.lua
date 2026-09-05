-- VoltScriptZ | Dungeon Lootr | RAVEN HUB Module
-- Converted to RAVEN HUB (MacLib Adapter)
-- PlaceIds: 132285059959516, 135245842886361 | GameIds: 9656201728, 8410525651

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local LocalPlayer = Players.LocalPlayer
    local Knit = require(ReplicatedStorage.Packages.Knit)

    local running = true

local AttackRemote = nil
local SkillRemote = nil
pcall(function() AttackRemote = ReplicatedStorage:WaitForChild("Player"):WaitForChild("Remotes"):WaitForChild("Inputs"):WaitForChild("Attack") end)
if not AttackRemote then pcall(function() AttackRemote = ReplicatedStorage.Player.Remotes.Inputs.Attack end) end
pcall(function() SkillRemote = ReplicatedStorage:WaitForChild("Player"):WaitForChild("Remotes"):WaitForChild("Inputs"):WaitForChild("Skill") end)
if not SkillRemote then pcall(function() SkillRemote = ReplicatedStorage.Player.Remotes.Inputs.Skill end) end

local State = {
    AutoFarm = false,
    Position = "Above",
    Distance = 15,
    AttackDelay = 0.12,
    TeleportDelay = 0.01,
    Noclip = true,
    CFrameLock = true,
    AutoSkill = false,
    Skill1 = true,
    Skill2 = true,
    Skill3 = true,
    Skill4 = true,
    SkipChest = false,
    AutoPotion = false,
    AutoRefillPotion = false,
    AutoReplay = false,
    AutoReturn = false,
    CreateDungeon = "Bandits Den",
    CreateDifficulty = "Easy",
    AutoCreateDungeon = false,
    AutoBestDungeon = false,
    AutoCreateChallenger = false,
    ChallengerBoss = "Scarlet Knight",
    BossRushBoss = "Cursed King",
    AutoCreateBossRush = false
}

local function getGeneratedFolder()
    for _,v in ipairs(workspace:GetChildren()) do if v.Name:match("^Generated_") and v:IsA("Folder") then return v end end
    return nil
end

local function getMonsters()
    local gen = getGeneratedFolder()
    local list = {}
    local seen = {}
    local function isAlive(model)
        if not model:IsA("Model") then return false end
        if model.Name == LocalPlayer.Name then return false end
        local hasHealth = model:GetAttribute("HealthOverride") ~= nil or model:GetAttribute("IsFodder")==true or model:GetAttribute("IsBoss")==true or model:FindFirstChildOfClass("Humanoid") ~= nil
        if not hasHealth then return false end
        if model.Parent and model.Parent.Name=="PlayerModels" then return false end
        local hrp = model:FindFirstChild("HumanoidRootPart", true)
        if not hrp then hrp = model:FindFirstChild("HumanoidRootPart") end
        if not hrp then return false end
        local hum = model:FindFirstChildOfClass("Humanoid")
        if hum then return hum.Health > 0
        else local hp = model:GetAttribute("HealthOverride") if hp ~= nil then return hp > 0 end return true end
    end
    local function add(m) if not seen[m] and isAlive(m) then seen[m]=true table.insert(list,m) end end
    if gen then
        local npcFolder = gen:FindFirstChild("NPCs")
        if npcFolder then for _,m in ipairs(npcFolder:GetChildren()) do add(m) end end
        -- Visit Every Room Fix: กวาดทุก Room ใน Generated เสมอ ไม่ใช่แค่ตอน NPCs ว่าง เพื่อให้ byRoom ครบทุกห้อง
        for _,room in ipairs(gen:GetChildren()) do
            if room:IsA("Model") or room:IsA("Folder") then
                for _,m in ipairs(room:GetDescendants()) do
                    if m:IsA("Model") and (m:GetAttribute("IsFodder")==true or m:GetAttribute("IsBoss")==true) then add(m) end
                end
            end
        end
        -- เผื่อบอส/มอนอยู่นอก Room แต่อยู่ใน Generated โดยตรง
        if #list==0 then for _,m in ipairs(gen:GetDescendants()) do if m:IsA("Model") and m:GetAttribute("IsBoss")==true then add(m) end end end
    end
    if #list==0 then for _,m in ipairs(workspace:GetDescendants()) do if m:IsA("Model") and (m:GetAttribute("IsFodder")==true or m:GetAttribute("IsBoss")==true) then add(m) if #list>40 then break end end end end
    return list
end

local function getOrderedZones()
    local ok, ctrl = pcall(function() return Knit.GetController("DungeonHUDController") end)
    if ok and ctrl then
        local zones=nil
        pcall(function() zones = ctrl.Zones or ctrl._Zones end)
        if zones and #zones>0 then
            local out={}
            for _,z in ipairs(zones) do if z.IsBoss~=true and z.HasTreasure~=true then table.insert(out, z.Index) end end
            table.sort(out)
            return out
        end
    end
    return nil
end

local function getCurrentOrderedPointer(ordered)
    -- ดาวเขียวในรูปคือห้องแรกที่ spawn เข้าดันมา → ต้อง Next Room ไปห้องถัดไป
    local ok, ctrl = pcall(function() return Knit.GetController("DungeonHUDController") end)
    if ok and ctrl and ordered then
        local curPos, zones = nil, nil
        pcall(function()
            curPos = ctrl.CurrentPos or ctrl._CurrentPos
            zones = ctrl.Zones or ctrl._Zones
        end)
        if curPos and zones and zones[curPos] then
            local curIdx = zones[curPos].Index
            for i, idx in ipairs(ordered) do if idx==curIdx then return (i % #ordered)+1 end end -- Next Room
        end
        if curPos and ordered then for i, idx in ipairs(ordered) do if idx==curPos then return (i % #ordered)+1 end end end
    end
    return 1
end

local function getRoomCenters()
    -- เดินทุก Room: คืนทุก Room_* เรียงตาม idx
    local gen=getGeneratedFolder() if not gen then return {} end
    local out={}
    for _,room in ipairs(gen:GetChildren()) do
        if room:IsA("Model") or room:IsA("Folder") then
            if not room.Name:match("^Room_%d+$") then continue end
            local cf=nil pcall(function() cf=room:GetBoundingBox() end)
            if cf then
                local idx = room:GetAttribute("RoomIndex") or tonumber(room.Name:match("%d+")) or 999
                table.insert(out,{idx=idx, cf=cf, name=room.Name})
            end
        end
    end
    table.sort(out,function(a,b) return (a.idx or 999)<(b.idx or 999) end)
    local seen={} local filtered={}
    for _,v in ipairs(out) do if not seen[v.name] then seen[v.name]=true table.insert(filtered,v) end end
    return filtered
end

local function getSpawnCenters()
    -- ห้องสปอนมอนจริง (มี Enemy_Spawn) ไว้เช็คว่าห้องไหนต้องเคลียร์
    local gen=getGeneratedFolder() if not gen then return {} end
    local out={}
    for _,room in ipairs(gen:GetChildren()) do
        if room:IsA("Model") or room:IsA("Folder") then
            if not room.Name:match("^Room_%d+$") then continue end
            local spawns=room:FindFirstChild("Spawns")
            local has=false if spawns then for _,s in ipairs(spawns:GetChildren()) do if s.Name=="Enemy_Spawn" then has=true break end end end
            if not has then continue end
            local cf=nil pcall(function() cf=room:GetBoundingBox() end)
            if cf then local idx=room:GetAttribute("RoomIndex") or tonumber(room.Name:match("%d+")) or 999 table.insert(out,{idx=idx, cf=cf, name=room.Name}) end
        end
    end
    table.sort(out,function(a,b) return (a.idx or 999)<(b.idx or 999) end)
    return out
end

local function getSpawnRoomIndices()
    -- คืน set ของ idx ที่เป็น spawn room เพื่อกรอง byRoom
    local centers=getRoomCenters()
    local set={}
    for _,c in ipairs(centers) do set[c.idx]=true end
    return set
end

local function isZoneClear()
    local ok=false
    pcall(function()
        for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if gui:IsA("TextLabel") and gui.Visible and gui.Text:find("Zone Clear") then ok=true break end
        end
    end)
    return ok
end

local nextRoomPointer=2

local function getHRP(model)
    local hrp = model:FindFirstChild("HumanoidRootPart") if hrp then return hrp end
    hrp = model:FindFirstChild("HumanoidRootPart", true) if hrp then return hrp end
    return model.PrimaryPart or model:FindFirstChild("Torso", true) or model:FindFirstChild("Head", true)
end

local function getClosest(list, fromPos)
    local best,bestDist=nil,math.huge
    for _,m in ipairs(list) do local hrp=getHRP(m) if hrp then local d=(hrp.Position-fromPos).Magnitude if d<bestDist then bestDist=d best=m end end end
    return best,bestDist
end

local function isValidChar()
    local c=LocalPlayer.Character if not c then return false end
    local hrp=c:FindFirstChild("HumanoidRootPart") local hum=c:FindFirstChildOfClass("Humanoid") if not hrp or not hum then return false end if hum.Health<=0 then return false end return true
end

local noclipConn=nil
local function setNoclip(state)
    if state then
        if noclipConn then return end
        noclipConn=RunService.Stepped:Connect(function()
            if not State.AutoFarm or not State.Noclip then return end
            local c=LocalPlayer.Character if c then for _,part in ipairs(c:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide=false end end end
        end)
    else if noclipConn then noclipConn:Disconnect() noclipConn=nil end end
end

local function fireM1(dir)
    if not AttackRemote then return end
    local d = dir or Vector3.new(0,-1,0)
    pcall(function() AttackRemote:FireServer(d) end)
    if d~=Vector3.new(0,0,0) then pcall(function() AttackRemote:FireServer(Vector3.new(0,0,0)) end) end
end

local function getPositionForMode(targetHRP, mode, dist)
    local tPos = targetHRP.Position
    local tCF = targetHRP.CFrame
    if mode == "Above" then
        local pos = tPos + Vector3.new(0, dist, 0)
        local cf = CFrame.lookAt(pos, tPos)
        return pos, cf
    elseif mode == "Behind" then
        local look = tCF.LookVector
        if look.Magnitude < 0.1 then look = Vector3.new(0,0,1) end
        local pos = tPos - look * dist + Vector3.new(0, 2, 0)
        local cf = CFrame.lookAt(pos, tPos)
        return pos, cf
    elseif mode == "Below" then
        local pos = tPos - Vector3.new(0, dist, 0)
        local cf = CFrame.lookAt(pos, tPos)
        return pos, cf
    end
    return tPos + Vector3.new(0, dist, 0), CFrame.lookAt(tPos + Vector3.new(0, dist, 0), tPos)
end

local function wakeMonster(target)
    local char=LocalPlayer.Character; if not char then return false end
    local hrp=char:FindFirstChild("HumanoidRootPart"); if not hrp then return false end
    local targetHRP=getHRP(target); if not targetHRP then return false end
    local tPos=targetHRP.Position
    if target:GetAttribute("IsDormant")==false or target:GetAttribute("IsDormant")==nil then
        if target:GetAttribute("State")=="Aggro" then return true end
    end
    local wakePos=tPos+Vector3.new(7,2,7)
    pcall(function() hrp.Anchored=false end)
    pcall(function() char:FindFirstChildOfClass("Humanoid").PlatformStand=false end)
    hrp.CFrame=CFrame.new(wakePos, tPos)
    hrp.AssemblyLinearVelocity=Vector3.new(0,0,0)
    local start=tick()
    while tick()-start < 0.6 do
        task.wait(0.1)
        local state=target:GetAttribute("State")
        local dormant=target:GetAttribute("IsDormant")
        if state=="Aggro" or dormant==false then return true end
        pcall(function() hrp.CFrame=CFrame.new(tPos+Vector3.new(4,2,4), tPos) end)
    end
    return true
end

local lockConn=nil
local curTargetHRP=nil
local hoverConn=nil
local hoverCF=nil
local function startHover(cf)
    if hoverConn then pcall(function() hoverConn:Disconnect() end) hoverConn=nil end
    hoverCF=cf
    local char=LocalPlayer.Character if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart") if not hrp then return end
    hoverConn=RunService.Heartbeat:Connect(function()
        if not State.AutoFarm then return end
        if lockConn then return end -- ถ้าล็อคมอนอยู่ให้ lock คุมแทน
        if not hrp.Parent then return end
        hrp.CFrame=hoverCF
        hrp.AssemblyLinearVelocity=Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity=Vector3.new(0,0,0)
        hrp.Velocity=Vector3.new(0,0,0)
    end)
end
local function stopHover()
    if hoverConn then pcall(function() hoverConn:Disconnect() end) hoverConn=nil end
end
local function startLock(targetHRP)
    curTargetHRP=targetHRP
    stopHover()
    if lockConn then pcall(function() lockConn:Disconnect() end) lockConn=nil end
    local char=LocalPlayer.Character if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart") local hum=char:FindFirstChildOfClass("Humanoid") if not hrp or not hum then return end
    pcall(function() hrp.Anchored=false hum.PlatformStand=false hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    local _, initCF = getPositionForMode(curTargetHRP, State.Position, State.Distance)
    pcall(function() hrp.CFrame=initCF hrp.AssemblyLinearVelocity=Vector3.new(0,0,0) hrp.AssemblyAngularVelocity=Vector3.new(0,0,0) hrp.Velocity=Vector3.new(0,0,0) end)
    hoverCF=initCF
    local hb, rs
    hb=RunService.Heartbeat:Connect(function()
        if not State.AutoFarm or not State.CFrameLock then return end
        if not curTargetHRP or not curTargetHRP.Parent or not hrp.Parent then return end
        local _, cf = getPositionForMode(curTargetHRP, State.Position, State.Distance)
        hoverCF=cf
        hrp.CFrame=cf
        hrp.AssemblyLinearVelocity=Vector3.new(0,0,0)
        hrp.AssemblyAngularVelocity=Vector3.new(0,0,0)
        hrp.Velocity=Vector3.new(0,0,0)
    end)
    rs=RunService.Stepped:Connect(function()
        if not State.AutoFarm or not State.CFrameLock then return end
        if not curTargetHRP or not curTargetHRP.Parent or not hrp.Parent then return end
        hrp.AssemblyLinearVelocity=Vector3.new(0,0,0)
        hrp.Velocity=Vector3.new(0,0,0)
    end)
    lockConn={Disconnect=function() pcall(function() hb:Disconnect() rs:Disconnect() end) end}
end
local function stopLock()
    local char=LocalPlayer.Character
    local lastCF=nil
    if char then local hrp=char:FindFirstChild("HumanoidRootPart") if hrp then lastCF=hrp.CFrame end end
    curTargetHRP=nil
    if lockConn then pcall(function() lockConn:Disconnect() end) lockConn=nil end
    if lastCF then startHover(lastCF) end
end

local function safeWarp(cf)
    stopHover()
    local char=LocalPlayer.Character if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart") if not hrp then return end
    hoverCF=cf
    pcall(function() hrp.CFrame=cf hrp.AssemblyLinearVelocity=Vector3.new(0,0,0) hrp.AssemblyAngularVelocity=Vector3.new(0,0,0) hrp.Velocity=Vector3.new(0,0,0) end)
    -- ลอยนิ่งต่อ 0.6วิ กันร่วงช่วงสลับมอน แล้วค้าง hover ไว้จนกว่าจะ lock มอนตัวถัดไป
    local t0=tick()
    while tick()-t0 < 0.6 do
        if not State.AutoFarm then break end
        pcall(function() hrp.CFrame=hoverCF hrp.AssemblyLinearVelocity=Vector3.new(0,0,0) hrp.Velocity=Vector3.new(0,0,0) end)
        RunService.Heartbeat:Wait()
    end
    startHover(hoverCF)
end

local farmThread=nil
-- ใหม่: เคลียร์ครบทุกห้องสปอนก่อน Boss จะเกิด (ห้ามข้าม / ห้ามรอเวฟมั่ว)
local function startFarm()
    if farmThread then return end
    farmThread=task.spawn(function()
        setNoclip(true)
        _G.__farmStarted=nil
        nextRoomPointer=2 -- เริ่มห้องหน้าจุดเกิด (Room_2) ไม่ข้าม
        local lastRoomIndex=nil
        local clearedRooms={}
        local function markCleared(idx) clearedRooms[idx]=true end
        local function isCleared(idx) return clearedRooms[idx]==true end
        local function allSpawnCleared()
            local centers=getRoomCenters()
            for _,c in ipairs(centers) do if not isCleared(c.idx) then return false end end
            return #centers>0
        end
        while State.AutoFarm do
            if (not running) then break end
            if not isValidChar() then stopLock() task.wait(1) continue end
            local char=LocalPlayer.Character local hrp=char:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.5) continue end
            local centers=getRoomCenters()
            if #centers==0 then task.wait(1) continue end
            if nextRoomPointer>#centers then nextRoomPointer=2 end
            if not _G.__farmStarted then
                _G.__farmStarted=true
                local bestDist=math.huge local bestIdx=nextRoomPointer
                for i, c in ipairs(centers) do
                    local d=(c.cf.Position - hrp.Position).Magnitude
                    if d < bestDist then bestDist=d bestIdx=i end
                end
                nextRoomPointer=bestIdx
            end
            local allMons=getMonsters()
            -- Boss ธรรมดาถือเป็นมอนแต่ต้องวาร์ปหาได้แม้อยู่คนละ RoomIndex (Boss arena ไม่ใช่ Room_*) เลย priority ทั้ง IsBoss/IsMapBoss
            local boss=nil for _,m in ipairs(allMons) do if m:GetAttribute("IsBoss")==true or m:GetAttribute("IsMapBoss")==true or m:GetAttribute("BossType")~=nil then boss=m break end end
            if boss then
                local targetHRP=getHRP(boss)
                if targetHRP then
                    lastRoomIndex=nil
                    startLock(targetHRP)
                    local hum=boss:FindFirstChildOfClass("Humanoid")
                    while State.AutoFarm and boss.Parent do
                        local dead=false if hum then dead=hum.Health<=0 else local hp=boss:GetAttribute("HealthOverride") if hp~=nil then dead=hp<=0 end end
                        if dead then break end
                        local dir = State.Position=="Above" and Vector3.new(0,-1,0) or State.Position=="Below" and Vector3.new(0,1,0) or Vector3.new(0,0,-1)
                        fireM1(dir) task.wait(State.AttackDelay)
                    end
                    stopLock()
                    task.wait(0.5)
                    -- บอสตายรีเซ็ตให้เริ่มเวฟใหม่ที่ Room_2
                    nextRoomPointer=2 clearedRooms={} lastRoomIndex=nil
                    continue
                end
            end
            -- ห้องปัจจุบันที่ต้องเคลียร์ตามลำดับ Room_2→6→10→14→18
            local curCenter=centers[nextRoomPointer]
            local curIdx=curCenter.idx
            -- หามอนในห้องนี้โดยตรง
            local monsInRoom={}
            local function isInRoom(m, roomIdx, roomCenter)
                if m:GetAttribute("RoomIndex")==roomIdx then return true end
                -- fallback: มอนไม่มี RoomIndex หรือ 999 แต่อยู่ใกล้กลางห้อง <80 studs นับด้วย กันย้ายห้องก่อนมอนตายหมด
                local hrpM=getHRP(m)
                if hrpM and roomCenter and (hrpM.Position - roomCenter.cf.Position).Magnitude < 80 then return true end
                return false
            end
            for _,m in ipairs(allMons) do if isInRoom(m, curIdx, curCenter) then table.insert(monsInRoom, m) end end
            if #monsInRoom==0 then
                local isSpawn=false
                do local gen=getGeneratedFolder() local room=gen and gen:FindFirstChild(curCenter.name) local sp=room and room:FindFirstChild("Spawns") if sp then for _,s in ipairs(sp:GetChildren()) do if s.Name=="Enemy_Spawn" then isSpawn=true break end end end end
                local groundCF=nil
                do
                    local roomForGround=getGeneratedFolder() and getGeneratedFolder():FindFirstChild(curCenter.name)
                    if roomForGround then
                        local ok, cf2, sz2 = pcall(function() return roomForGround:GetBoundingBox() end)
                        if ok and cf2 and sz2 then
                            groundCF = CFrame.new(Vector3.new(curCenter.cf.Position.X, cf2.Position.Y - sz2.Y/2 + 8, curCenter.cf.Position.Z))
                        end
                    end
                    if not groundCF then
                        local params=RaycastParams.new() params.FilterDescendantsInstances={LocalPlayer.Character} params.FilterType=Enum.RaycastFilterType.Exclude
                        local res=workspace:Raycast(curCenter.cf.Position+Vector3.new(0,50,0), Vector3.new(0,-200,0), params)
                        if res then groundCF=CFrame.new(res.Position+Vector3.new(0,0.5,0)) else groundCF=curCenter.cf+Vector3.new(0,0.5,0) end
                    end
                end
                if isSpawn then
                    if (hrp.Position - groundCF.Position).Magnitude > 8 then
                        safeWarp(groundCF)
                    end
                    if #monsInRoom==0 then
                        local waited=0
                        while waited < 3 do
                            task.wait(0.5) waited+=0.5
                            local chk=getMonsters()
                            local has=false for _,m in ipairs(chk) do if isInRoom(m, curIdx, curCenter) then has=true break end end
                            if has then break end
                            safeWarp(groundCF)
                        end
                        local chk2=getMonsters() local stillEmpty=true for _,m in ipairs(chk2) do if isInRoom(m, curIdx, curCenter) then stillEmpty=false break end end
                        if stillEmpty then
                            nextRoomPointer+=1
                    if nextRoomPointer>#centers then nextRoomPointer=2 end
                    continue
                        end
                        -- มีมอนเกิดแล้วให้ไปตีต่อ ไม่ข้าม
                        monsInRoom={}
                        for _,m in ipairs(chk2) do if isInRoom(m, curIdx, curCenter) then table.insert(monsInRoom, m) end end
                        if #monsInRoom==0 then
                            nextRoomPointer+=1
                    if nextRoomPointer>#centers then nextRoomPointer=2 end
                    continue
                        end
                    end
                else
                    markCleared(curIdx)
                    if (hrp.Position - groundCF.Position).Magnitude > 8 then
                        safeWarp(groundCF) task.wait(0.3)
                    end
                    nextRoomPointer+=1
                    if nextRoomPointer>#centers then nextRoomPointer=2 end
                    continue
                end
            end
            -- มีมอนในห้องนี้ → ตีทีละตัวจนหมดห้อง
            local target=getClosest(monsInRoom, hrp.Position)
            if not target then task.wait(0.2) continue end
            lastRoomIndex=curIdx
            local targetHRP=getHRP(target) if not targetHRP then task.wait(0.2) continue end
            if State.CFrameLock then
                startLock(targetHRP)
                local hum=target:FindFirstChildOfClass("Humanoid")
                while State.AutoFarm and target.Parent do
                    local dead=false if hum then dead=hum.Health<=0 else local hp=target:GetAttribute("HealthOverride") if hp~=nil then dead=hp<=0 end end
                    if dead then break end
                    local dir = State.Position=="Above" and Vector3.new(0,-1,0) or State.Position=="Below" and Vector3.new(0,1,0) or Vector3.new(0,0,-1)
                    fireM1(dir) task.wait(State.AttackDelay)
                end
                stopLock()
            else
                local _, cf = getPositionForMode(targetHRP, State.Position, State.Distance)
                pcall(function() hrp.CFrame=cf end)
                for i=1,4 do if not State.AutoFarm then break end fireM1() task.wait(State.AttackDelay) end
            end
            task.wait(0.4)
            local chkAfter=getMonsters()
            local remain=0 for _,m in ipairs(chkAfter) do if isInRoom(m, curIdx, curCenter) then remain+=1 end end
            if remain==0 then
                -- ถ้าเป็น Rush/Survive/Might ต้องรอเงื่อนไขสำเร็จ (Zone Clear) ก่อนย้าย
                local waited=0
                while State.AutoFarm and waited < 12 do
                    if isZoneClear() then break end
                    -- ห้องปกติ Zone Clear จะมาทันทีหลังมอนหมด 0.5-1วิ, Rush/Survive รอนานกว่า
                    -- ถ้าไม่มี Zone Clear แต่ห้องนี้ไม่มีมอนเกิน 3วิก็ถือว่าเคลียร์สำหรับห้องปกติ
                    if waited>3 then
                        local c2=getMonsters() local r2=0 for _,m in ipairs(c2) do if isInRoom(m, curIdx, curCenter) then r2+=1 end end
                        if r2==0 and not (curCenter.name:find("Room")) then break end
                        -- ถ้าเป็นห้องธรรมดา (ไม่ใช่ Rush/Survive) ให้ไปต่อได้หลัง 3วิ
                        -- เช็คแบบง่าย: ถ้าไม่มีมอน 3วิและยังไม่ Zone Clear ให้รอดูอีกนิดสำหรับ Rush/Survive
                        if r2==0 then
                            -- ดูว่ามี GUI Rush/Survive ค้างไหม ถ้าไม่มีก็ไปต่อ
                            local hasSpecial=false
                            pcall(function()
                                for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                                    if gui:IsA("TextLabel") and gui.Visible and (gui.Text:find("Rush") or gui.Text:find("Survive") or gui.Text:find("Survivor") or gui.Text:find("Might")) then hasSpecial=true end
                                end
                            end)
                            if not hasSpecial and waited>3 then break end
                        end
                    end
                    task.wait(0.5) waited+=0.5
                end
                markCleared(curIdx)
                if allSpawnCleared() then
                    local waitedBoss=0
                    while waitedBoss < 8 and State.AutoFarm do
                        task.wait(0.5) waitedBoss+=0.5
                        if isZoneClear() then
                            local chk=getMonsters()
                            local hasBoss=false
                            for _,m in ipairs(chk) do if m:GetAttribute("IsBoss")==true or m:GetAttribute("IsMapBoss")==true or m:GetAttribute("BossType")~=nil then hasBoss=true break end end
                            if hasBoss then break end
                            if #chk==0 and waitedBoss >= 8 then
                                pcall(function()
                                    local svc=Knit.GetService("DungeonRunService")
                                    if svc then
                                        if svc.RequestReturn then pcall(function() svc:RequestReturn():await() end) end
                                        if svc.RequestLeave then pcall(function() svc:RequestLeave():await() end) end
                                    end
                                    -- fallback กดปุ่ม Return
                                    for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                                        if gui:IsA("TextLabel") and gui.Visible and (gui.Text=="Return" or gui.Text=="Leave") then
                                            local btn=gui.Parent
                                            while btn and not (btn:IsA("TextButton") or btn:IsA("ImageButton")) do btn=btn.Parent end
                                            if btn and btn.Visible and btn.Active then pcall(function() btn:Activate() end) break end
                                        end
                                    end
                                end)
                                break
                            end
                        end
                    end
                end
                nextRoomPointer+=1
                if nextRoomPointer>#centers then
                    task.wait(0.1)
                    nextRoomPointer=2
                else
                    local nxt=centers[nextRoomPointer]
                    -- หาพื้นจริงจาก BoundingBox กันโดนหลังคา (Raycast โดนเพดานก่อน)
                    local dest=nil
                    local gen2=getGeneratedFolder()
                    local room2=gen2 and gen2:FindFirstChild(nxt.name)
                    if room2 then
                        local ok, cf2, sz2 = pcall(function() return room2:GetBoundingBox() end)
                        if ok and cf2 and sz2 then
                            dest = CFrame.new(Vector3.new(nxt.cf.Position.X, cf2.Position.Y - sz2.Y/2 + 8, nxt.cf.Position.Z))
                        end
                    end
                    dest = dest or nxt.cf+Vector3.new(0,1,0)
                    safeWarp(dest) task.wait(0.1)
                end
            else
                task.wait(State.TeleportDelay)
            end
        end
        stopLock() stopHover() setNoclip(false) farmThread=nil
    end)
end
local function stopFarm()
    State.AutoFarm=false
    _G.__farmStarted=nil
    stopLock() stopHover()
    local char=LocalPlayer.Character
    if char then
        local hrp=char:FindFirstChild("HumanoidRootPart") local hum=char:FindFirstChildOfClass("Humanoid")
        if hrp and hum then
            pcall(function() hrp.Anchored=false hum.PlatformStand=false end)
            local params=RaycastParams.new() params.FilterDescendantsInstances={char} params.FilterType=Enum.RaycastFilterType.Exclude
            local res=workspace:Raycast(hrp.Position, Vector3.new(0,-500,0), params)
            if res and res.Position then
                hrp.CFrame=CFrame.new(res.Position+Vector3.new(0,1,0))
                hrp.AssemblyLinearVelocity=Vector3.new(0,0,0) hrp.Velocity=Vector3.new(0,0,0)
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
        end
    end
    setNoclip(false)
end

local skillThread=nil
local function startSkill()
    if skillThread then State.AutoSkill=false task.wait(0.2) end
    State.AutoSkill=true
    skillThread=task.spawn(function()
        while State.AutoSkill do
            if (not running) then break end
            if isValidChar() and SkillRemote then
                if State.Skill1 then pcall(function() SkillRemote:FireServer(1, "tap", Vector3.new(0,0,0)) end) end
                task.wait(0.15) if not State.AutoSkill then break end
                if State.Skill2 then pcall(function() SkillRemote:FireServer(2, "tap", Vector3.new(0,0,0)) end) end
                task.wait(0.15) if not State.AutoSkill then break end
                if State.Skill3 then pcall(function() SkillRemote:FireServer(3, "tap", Vector3.new(0,0,0)) end) end
                task.wait(0.15) if not State.AutoSkill then break end
                if State.Skill4 then pcall(function() SkillRemote:FireServer(4, "tap", Vector3.new(0,0,0)) end) end
                task.wait(0.15)
            end
            task.wait(0.6)
        end
        skillThread=nil
    end)
end
local function stopSkill()
    State.AutoSkill=false
    if skillThread then pcall(function() task.cancel(skillThread) end) skillThread=nil end
end

local chestConn=nil
local function setSkipChest(enabled)
    State.SkipChest=enabled
    if enabled then
        if chestConn then chestConn:Disconnect() end
        -- ใช้ task.spawn loop แทน Heartbeat+wait จะได้ไม่ yield ใน Heartbeat
        chestConn=task.spawn(function()
            while State.SkipChest do
                if (not running) then break end
                local ok, ctrl = pcall(function() return Knit.GetController("ChestSelectionController") end)
                if ok and ctrl and ctrl._active and ctrl._ready and ctrl._candidates then
                    if not (ctrl._selectedCount and ctrl._selectedCount >= (ctrl._maxPicks or 2)) then
                        local maxPicks = ctrl._maxPicks or 2
                        for i=1, #ctrl._chests do
                            if not State.SkipChest then break end
                            if not ctrl._selected[i] and ctrl._selectedCount < maxPicks then
                                pcall(function() ctrl:_OnChestClicked(i) end)
                                task.wait(0.15)
                            end
                            if ctrl._selectedCount >= maxPicks then break end
                        end
                        task.wait(0.3)
                        if ctrl._selectedCount >= maxPicks and ctrl._finish then
                            pcall(function() ctrl:_OnFinish() end)
                        end
                    end
                end
                task.wait(0.25)
            end
        end)
        -- เก็บ handle ไว้ยกเลิก (เช็คชนิด)
        local realConn=chestConn
        chestConn={Disconnect=function() State.SkipChest=false if realConn then pcall(function() task.cancel(realConn) end) end end}
    else
        if chestConn then pcall(function() chestConn:Disconnect() end) chestConn=nil end
    end
end

local potionThread=nil
local lastPotion=0
local function setAutoPotion(enabled)
    State.AutoPotion=enabled
    if enabled then
        if potionThread then pcall(function() task.cancel(potionThread) end) end
        potionThread=task.spawn(function()
            while State.AutoPotion do
                if (not running) then break end
                if tick()-lastPotion >= 3 then
                    local char=LocalPlayer.Character local hum=char and char:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health>0 and hum.Health/hum.MaxHealth < 0.6 then
                        lastPotion=tick()
                        local used=false
                        pcall(function()
                            local pd=Knit.Registry:Get("PlayerData")
                            local pid=pd and pd.Data and pd.Data.EquippedPotion or "SmallHealPercent"
                            local svc=Knit.GetService("PotionService")
                            if svc then
                                if svc.UsePotion then used=pcall(function() svc:UsePotion(pid):await() end) end
                                if not used and svc.ConsumePotion then used=pcall(function() svc:ConsumePotion(pid):await() end) end
                            end
                        end)
                        if not used then
                            pcall(function()
                                local bp=LocalPlayer:FindFirstChild("Backpack")
                                local tool=nil
                                if bp then for _,t in ipairs(bp:GetChildren()) do if t:IsA("Tool") and t.Name:lower():find("potion") then tool=t break end end end
                                if tool then
                                    hum:EquipTool(tool) task.wait(0.2)
                                    if tool.Activate then tool:Activate() end
                                    -- บางเกมใช้ VirtualInput
                                    pcall(function() game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.Q, false, game) task.wait(0.1) game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.Q, false, game) end)
                                    used=true
                                end
                            end)
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
    else
        if potionThread then pcall(function() task.cancel(potionThread) end) potionThread=nil end
    end
end

local continueConn=nil
local function setAutoContinue(enabled)
    State.AutoContinue=enabled
    if enabled then
        if continueConn then pcall(function() continueConn:Disconnect() end) end
        local ok, svc = pcall(function() return Knit.GetService("DungeonRunService") end)
        if ok and svc and svc.EndlessDecision then
            continueConn=svc.EndlessDecision:Connect(function(data)
                if not State.AutoContinue then return end
                task.wait(0.8)
                -- อัตโนมัติกด Continue ในโหมด Endless
                pcall(function() svc:SubmitEndlessChoice(true) end)
            end)
        end
        -- fallback ดัก Warning prompt ถ้า event ไม่มา
        if not continueConn then
            continueConn=task.spawn(function()
                while State.AutoContinue do
                    if (not running) then break end
                    local done=false
                    pcall(function()
                        for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                            if gui:IsA("TextLabel") and gui.Visible and gui.Text:find("Checkpoint %d+ cleared!") then
                                local svc2=Knit.GetService("DungeonRunService")
                                svc2:SubmitEndlessChoice(true) done=true
                            end
                        end
                    end)
                    if done then task.wait(2) end
                    task.wait(0.5)
                end
            end)
            local real=continueConn
            continueConn={Disconnect=function() pcall(function() task.cancel(real) end) end}
        end
    else
        if continueConn then pcall(function() continueConn:Disconnect() end) continueConn=nil end
    end
end

local refillThread=nil
local lastRefill=0
local function setAutoRefillPotion(enabled)
    State.AutoRefillPotion=enabled
    if enabled then
        if refillThread then pcall(function() task.cancel(refillThread) end) end
        refillThread=task.spawn(function()
            while State.AutoRefillPotion do
                if (not running) then break end
                if tick()-lastRefill >= 5 then
                    local need=false
                    local pid="SmallHealPercent"
                    local cnt=nil
                    pcall(function()
                        local pd=Knit.Registry:Get("PlayerData")
                        local data=pd and pd.Data
                        if data then
                            pid=data.EquippedPotion or "SmallHealPercent"
                            local pot=data.Potions[pid]
                            cnt=type(pot)=="number" and pot or 0
                        end
                    end)
                    if cnt~=nil and cnt<=1 then need=true end
                    if need then
                        lastRefill=tick()
                        -- ต้องวาร์ปไป Potion Station ถึงจะเติมได้ (ลองไม่วาร์ปแล้วไม่ขึ้น 0→2)
                        local gen=getGeneratedFolder()
                        local st=gen and gen:FindFirstChild("Potion_Station") or workspace:FindFirstChild("Potion_Station",true)
                        local part=st and (st:FindFirstChild("Part",true) or st.PrimaryPart)
                        local prompt=st and st:FindFirstChildWhichIsA("ProximityPrompt",true)
                        if st and part and prompt then
                            local before=nil pcall(function() before=Knit.Registry:Get("PlayerData").Data.Potions[pid] end)
                            safeWarp(part.CFrame+Vector3.new(0,1,0)) task.wait(0.5)
                            pcall(function() fireproximityprompt(prompt) end) task.wait(0.8)
                        else
                        end
                    end
                end
                task.wait(1)
            end
        end)
    else
        if refillThread then pcall(function() task.cancel(refillThread) end) refillThread=nil end
    end
end

local replayConn=nil
local lastReplay=0
local function setAutoReplay(enabled)
    State.AutoReplay=enabled
    if enabled then
        if replayConn then pcall(function() replayConn:Disconnect() end) end
        replayConn=task.spawn(function()
            while State.AutoReplay do
                if (not running) then break end
                if tick() - lastReplay >= 5 then
                    local btn = nil
                    pcall(function() btn = game.Players.LocalPlayer.PlayerGui.Main.HUD.Dungeon_Container.Completion_Info.Content.ActionButtons.ReplayButton end)
                    if btn and btn.Visible then
                        local ok, chestCtrl = pcall(function() return Knit.GetController("ChestSelectionController") end)
                        if not (ok and chestCtrl and chestCtrl._active) then
                            local comp = game.Players.LocalPlayer.PlayerGui.Main.HUD.Dungeon_Container.Completion_Info
                            if comp and comp.Visible then
                                lastReplay=tick()
                                pcall(function() if btn.Active then btn:Activate() end end)
                                task.wait(0.2)
                                pcall(function() local svc=Knit.GetService("DungeonRunService") if svc and svc.RequestReplay then svc:RequestReplay() end end)
                            end
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
        local real=replayConn
        replayConn={Disconnect=function() State.AutoReplay=false pcall(function() task.cancel(real) end) end}
    else
        if replayConn then pcall(function() replayConn:Disconnect() end) replayConn=nil end
    end
end

local returnConn=nil
local lastReturn=0
local function setAutoReturn(enabled)
    State.AutoReturn=enabled
    if enabled then
        if returnConn then pcall(function() returnConn:Disconnect() end) end
        returnConn=task.spawn(function()
            while State.AutoReturn do
                if (not running) then break end
                if tick() - lastReturn >= 5 then
                    local btn=nil
                    pcall(function() btn=game.Players.LocalPlayer.PlayerGui.Main.HUD.Dungeon_Container.Completion_Info.Content.ActionButtons.ReturnButton end)
                    if btn and btn.Visible then
                        local ok,chestCtrl=pcall(function() return Knit.GetController("ChestSelectionController") end)
                        if not (ok and chestCtrl and chestCtrl._active) then
                            local comp=game.Players.LocalPlayer.PlayerGui.Main.HUD.Dungeon_Container.Completion_Info
                            if comp and comp.Visible then
                                lastReturn=tick()
                                pcall(function() if btn.Active then btn:Activate() end end)
                                task.wait(0.2)
                                pcall(function()
                                    local svc=Knit.GetService("DungeonRunService")
                                    if svc and svc.RequestReturn then svc:RequestReturn() end
                                end)
                            end
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
        local real=returnConn
        returnConn={Disconnect=function() State.AutoReturn=false pcall(function() task.cancel(real) end) end}
    else
        if returnConn then returnConn:Disconnect() returnConn=nil end
    end
end

local function getBestDungeon()
    local lvl = LocalPlayer:GetAttribute("PlayerLevel") or 1
    pcall(function()
        local reg = Knit.Registry
        if reg then
            local pd = reg:Get("PlayerData")
            if pd and pd.Data and pd.Data.PlayerLevel then lvl = pd.Data.PlayerLevel end
        end
    end)
    local DungeonData = require(ReplicatedStorage.GameInfo.DungeonData)
    local bestName, bestTier, bestDiff = nil, -1, "Easy"
    local diffOrder = {"Endless","Nightmare","Hard","Normal","Easy"}
    local playerData = nil
    pcall(function() playerData = Knit.Registry:Get("PlayerData") end)
    for name, data in pairs(DungeonData.Dungeons) do
        if data.HideFromSelect then continue end
        local canEnter = false
        pcall(function() canEnter = DungeonData.CanEnter(playerData, name) end)
        if not canEnter then continue end
        if canEnter and data.Tier and data.Tier > bestTier then
            local diffToUse = "Easy"
            pcall(function()
                local svc = Knit.GetService("DungeonQueueService")
                local ok, success, unlocks = pcall(function() return svc:GetUnlockedDifficulties(name):await() end)
                if ok and success and unlocks then
                    for _,d in ipairs(diffOrder) do
                        if unlocks[d] and unlocks[d].Unlocked then diffToUse=d break end
                    end
                end
            end)
            bestName=name bestTier=data.Tier bestDiff=diffToUse
        end
    end
    if not bestName then
        for i=#DungeonData.DisplayOrder,1,-1 do
            local n=DungeonData.DisplayOrder[i]
            local d=DungeonData.Dungeons[n]
            if d and not d.HideFromSelect then
                local can=false pcall(function() can=DungeonData.CanEnter(playerData, n) end)
                if can then bestName=n bestDiff="Easy" break end
            end
        end
    end
    return bestName or "Bandits Den", bestDiff or "Easy", lvl
end

local challengerConn=nil
local function setAutoCreateChallenger(enabled)
    State.AutoCreateChallenger=enabled
    if enabled then
        if challengerConn then pcall(function() task.cancel(challengerConn) end) end
        challengerConn=task.spawn(function()
            while State.AutoCreateChallenger do
                if (not running) then break end
                local inDungeon=LocalPlayer:GetAttribute("InDungeon")==true or LocalPlayer:GetAttribute("InChallenge")==true or LocalPlayer:GetAttribute("InBossRush")==true
                if not inDungeon then
                    pcall(function()
                        local hrp=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                        if not hrp then return end
                        local part=nil local bestDist=math.huge
                        local pc=workspace:FindFirstChild("pods_challenge")
                        if pc then
                            for _,pz in ipairs(pc:GetDescendants()) do
                                if pz.Name=="Touch" and pz:IsA("BasePart") then
                                    local d=(pz.Position-hrp.Position).Magnitude
                                    local isFull=false
                                    local att=pz.Parent:FindFirstChild("GuiAttachment", true)
                                    if att then
                                        local bb=att:FindFirstChildWhichIsA("BillboardGui")
                                        if bb then
                                            local lbl=bb:FindFirstChildWhichIsA("TextLabel")
                                            if lbl and lbl.Text:find("4/4") then isFull=true end
                                        end
                                    end
                                    if not isFull and d<bestDist then bestDist=d part=pz end
                                end
                            end
                        end
                        if not part then
                            for _,pz in ipairs(workspace:GetDescendants()) do
                                if pz.Name=="Touch" and pz:IsA("BasePart") and pz:GetFullName():lower():find("challenge") then
                                    local d=(pz.Position-hrp.Position).Magnitude
                                    if d<bestDist then bestDist=d part=pz end
                                end
                            end
                        end
                        if hrp and part then
                            hrp.CFrame=part.CFrame+Vector3.new(0,3,0) task.wait(0.4)
                            hrp.CFrame=part.CFrame+Vector3.new(0,3,0) task.wait(0.5)
                            pcall(function() firetouchinterest(hrp, part, 0) task.wait(0.1) firetouchinterest(hrp, part, 1) end)
                        end
                    end)
                    task.wait(1.5)
                    pcall(function()
                        local dq=Knit.GetService("DungeonQueueService")
                        if dq then
                            pcall(function() dq:RequestSelectMode("Challenge"):await() end)
                            task.wait(0.4)
                            pcall(function()
                                local ChallengeData=require(game.ReplicatedStorage.GameInfo.ChallengeData)
                                if ChallengeData and ChallengeData.FEATURED_DUNGEON then
                                    dq:RequestSelectDungeon(ChallengeData.FEATURED_DUNGEON):await()
                                end
                            end)
                            task.wait(0.3)
                            pcall(function() dq:RequestSelectFinalBoss(State.ChallengerBoss):await() end)
                            task.wait(0.3)
                        end
                        -- เลื่อน carousel แบบกดปุ่มจริง (เหมือน Boss Rush) โดย bypass leader check
                        pcall(function()
                            local frames=LocalPlayer.PlayerGui:FindFirstChild("Main") and LocalPlayer.PlayerGui.Main:FindFirstChild("Frames")
                            local ch=frames and frames:FindFirstChild("ChallengeDungeon")
                            if not ch then return end
                            local left=ch:FindFirstChild("Content") and ch.Content:FindFirstChild("LeftFrame")
                            if not left then return end
                            local display=left:FindFirstChild("Display")
                            local bossLabel=display and display:FindFirstChild("BossName")
                            local cycleF=left:FindFirstChild("CycleForward")
                            if not bossLabel or not cycleF then return end
                            local desired=State.ChallengerBoss
                            -- รอ UI โหลด
                            for _=1,8 do if bossLabel.Text and bossLabel.Text~="" then break end task.wait(0.3) end
                            local attempts=0
                            while attempts<12 do
                                local cur=bossLabel.Text
                                if cur==desired or cur:find(desired,1,true) or desired:find(cur,1,true) then break end
                                local conns=getconnections(cycleF.Activated)
                                if #conns>0 then
                                    local f=conns[1].Function
                                    -- bypass isLeader check (upvalue 1)
                                    pcall(function() debug.setupvalue(f,1,true) end)
                                    pcall(function() debug.setupvalue(f,2,true) end)
                                    -- กดเลื่อนจริงเหมือน Boss Rush
                                    pcall(function() cycleF:Activate() end)
                                    pcall(function() f() end)
                                else
                                    pcall(function() cycleF:Activate() end)
                                end
                                attempts+=1
                                task.wait(0.7)
                            end
                        end)
                        task.wait(0.5)
                        pcall(function()
                            local dq=Knit.GetService("DungeonQueueService")
                            if dq then
                                if dq.RequestStartPodQueue then pcall(function() dq:RequestStartPodQueue():await() end) end
                                task.wait(0.5)
                                if dq.RequestStartNow then pcall(function() dq:RequestStartNow():await() end) end
                                if dq.RequestStartSoloRun then pcall(function() dq:RequestStartSoloRun():await() end) end
                            end
                        end)
                        task.wait(0.5)
                        pcall(function()
                            for i=1,6 do
                                local pressed=false
                                for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                                    if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                                        local lbl=gui:FindFirstChildWhichIsA("TextLabel",true)
                                        local txt=(lbl and lbl.Text) or gui.Text or ""
                                        if (txt=="ENTER" or txt=="START" or txt=="PLAY") and gui.Visible and gui.Active then
                                            pcall(function() gui:Activate() end)
                                            pressed=true
                                        end
                                    end
                                    if gui:IsA("TextLabel") and (gui.Text=="ENTER" or gui.Text=="START") and gui.Visible then
                                        local btn=gui.Parent
                                        if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible and btn.Active then
                                            pcall(function() btn:Activate() end) pressed=true
                                        end
                                    end
                                end
                                if pressed then break end
                                task.wait(0.4)
                            end
                        end)
                    end)
                    task.wait(5)
                else task.wait(3) end
                if not State.AutoCreateChallenger then break end
            end
        end)
    else
        if challengerConn then pcall(function() task.cancel(challengerConn) end) challengerConn=nil end
    end
end





local bossRushConn=nil
local function setAutoCreateBossRush(enabled)
    State.AutoCreateBossRush=enabled
    if enabled then
        if bossRushConn then pcall(function() task.cancel(bossRushConn) end) end
        bossRushConn=task.spawn(function()
            while State.AutoCreateBossRush do
                if (not running) then break end
                local inDungeon=LocalPlayer:GetAttribute("InDungeon")==true or LocalPlayer:GetAttribute("InBossRush")==true or LocalPlayer:GetAttribute("BossRush")==true
                if not inDungeon then
                    pcall(function()
                        local hrp=LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                        local part=nil local bestDist=math.huge
                        local function findBossRushPod()
                            for _,pz in ipairs(workspace:GetDescendants()) do
                                if pz.Name=="Touch" and pz:IsA("BasePart") then
                                    local full=pz:GetFullName():lower()
                                    if full:find("bossrush") or full:find("boss_rush") or full:find("boss rush") then
                                        local d=(pz.Position-hrp.Position).Magnitude
                                        if d<bestDist then bestDist=d part=pz end
                                    end
                                end
                            end
                            if part then return part end
                            -- fallback กวาดหา Pod_Zone ที่เกี่ยวกับ Boss Rush หรือ Dungeon pods ทั่วไป
                            for _,pz in ipairs(workspace:GetDescendants()) do
                                if pz.Name=="Touch" and pz:IsA("BasePart") and pz.Parent.Name=="Pod_Zone" then
                                    local full=pz:GetFullName():lower()
                                    if full:find("rush") then
                                        local d=(pz.Position-hrp.Position).Magnitude
                                        if d<bestDist then bestDist=d part=pz end
                                    end
                                end
                            end
                            if part then return part end
                            local cand=workspace:FindFirstChild("BossRush_Prompt",true) or workspace:FindFirstChild("BossRushPod",true) or workspace:FindFirstChild("BossRush",true)
                            if cand then
                                if cand:IsA("BasePart") then return cand end
                                local touch=cand:FindFirstChild("Touch",true) or cand:FindFirstChildWhichIsA("BasePart",true)
                                if touch then return touch end
                            end
                            return nil
                        end
                        part=findBossRushPod()
                        if hrp and part then hrp.CFrame=part.CFrame+Vector3.new(0,3,0) task.wait(0.4) hrp.CFrame=part.CFrame+Vector3.new(0,3,0) end
                    end)
                    pcall(function()
                        local selected=false
                        -- ลองเลือกบอสผ่าน BossRushSelectController
                        local ctrl=nil
                        pcall(function() ctrl=Knit.GetController("BossRushSelectController") end)
                        if ctrl then
                            if ctrl.SelectBoss then selected=pcall(function() ctrl:SelectBoss(State.BossRushBoss) end) or selected end
                            -- บางเวอร์ชั่นใช้ SelectFinalBoss
                            if ctrl.SelectFinalBoss then selected=pcall(function() ctrl:SelectFinalBoss(State.BossRushBoss) end) or selected end
                            task.wait(0.4)
                        end
                        -- ลองเลือกผ่าน DungeonQueueService / BossRushService
                        pcall(function()
                            local dq=Knit.GetService("DungeonQueueService")
                            if dq then
                                if dq.RequestSelectMode then pcall(function() dq:RequestSelectMode("BossRush"):await() end) end
                                if dq.RequestSelectFinalBoss then pcall(function() dq:RequestSelectFinalBoss(State.BossRushBoss):await() end) end
                                task.wait(0.3)
                            end
                            local brs=Knit.GetService("BossRushService")
                            if brs and brs.RequestSelectFinalBoss then pcall(function() brs:RequestSelectFinalBoss(State.BossRushBoss):await() end) end
                            if brs and brs.SelectFinalBoss then pcall(function() brs:SelectFinalBoss(State.BossRushBoss) end) end
                        end)
                        -- fallback กดปุ่ม Boss ใน GUI
                        if not selected then
                            for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                                if gui:IsA("TextLabel") and gui.Visible and gui.Text==State.BossRushBoss then
                                    local btn=gui.Parent
                                    while btn and not (btn:IsA("TextButton") or btn:IsA("ImageButton")) do btn=btn.Parent end
                                    if btn and btn.Visible and btn.Active then pcall(function() btn:Activate() end) selected=true task.wait(0.4) break end
                                end
                            end
                        end
                        -- กด START / ENTER
                        pcall(function()
                            local dq=Knit.GetService("DungeonQueueService")
                            if dq then
                                if dq.RequestStartPodQueue then pcall(function() dq:RequestStartPodQueue():await() end) end
                                task.wait(0.5)
                                if dq.RequestStartNow then pcall(function() dq:RequestStartNow():await() end) end
                                if dq.RequestStartSoloRun then pcall(function() dq:RequestStartSoloRun():await() end) end
                            end
                        end)
                        pcall(function()
                            for i=1,6 do
                                local pressed=false
                                for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                                    if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                                        local lbl=gui:FindFirstChildWhichIsA("TextLabel",true)
                                        local txt=(lbl and lbl.Text) or gui.Text or ""
                                        if (txt=="START" or txt=="ENTER" or txt=="PLAY") and gui.Visible and gui.Active then
                                            pcall(function() gui:Activate() end)
                                            pressed=true
                                        end
                                    end
                                    if gui:IsA("TextLabel") and (gui.Text=="START" or gui.Text=="ENTER" or gui.Text=="PLAY") and gui.Visible then
                                        local btn=gui.Parent
                                        if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) and btn.Visible and btn.Active then
                                            pcall(function() btn:Activate() end) pressed=true
                                        end
                                    end
                                end
                                if pressed then break end
                                task.wait(0.4)
                            end
                        end)
                    end)
                    task.wait(5)
                else task.wait(3) end
                if not State.AutoCreateBossRush then break end
            end
        end)
    else
        if bossRushConn then pcall(function() task.cancel(bossRushConn) end) bossRushConn=nil end
    end
end

local bestConn=nil
local function setAutoBest(enabled)
    State.AutoBestDungeon=enabled
    if enabled then
        if bestConn then pcall(function() bestConn:Disconnect() end) end
        bestConn=task.spawn(function()
            while State.AutoBestDungeon do
                if (not running) then break end
                if LocalPlayer:GetAttribute("InDungeon")~=true then
                    local best, diff, lvl = getBestDungeon()
                    if best then
                        if State.CreateDungeon ~= best or State.CreateDifficulty ~= diff then
                            State.CreateDungeon=best State.CreateDifficulty=diff
                        end
                        if not State.AutoCreateDungeon then
                            pcall(function()
                                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                                local part = nil
                                local bestDist=math.huge
                                for _,pz in ipairs(workspace.pods:GetDescendants()) do
                                    if pz.Name=="Touch" and pz:IsA("BasePart") and pz.Parent.Name=="Pod_Zone" then
                                        local d=(pz.Position-hrp.Position).Magnitude
                                        local isFull=false
                                        local att=pz.Parent:FindFirstChild("GuiAttachment", true)
                                        if att then
                                            local bb=att:FindFirstChildWhichIsA("BillboardGui")
                                            if bb then
                                                local lbl=bb:FindFirstChildWhichIsA("TextLabel")
                                                if lbl and lbl.Text:find("4/4") then isFull=true end
                                            end
                                        end
                                        if not isFull and d<bestDist then bestDist=d part=pz end
                                    end
                                end
                                if not part then part=workspace:FindFirstChild("Prompts") and workspace.Prompts:FindFirstChild("Dungeon_Select") end
                                if hrp and part then hrp.CFrame=part.CFrame+Vector3.new(0,3,0) task.wait(0.4) hrp.CFrame=part.CFrame+Vector3.new(0,3,0) end
                            end)
                            pcall(function()
                                local ctrl=Knit.GetController("DungeonSelectController")
                                ctrl:SelectDungeon(best) task.wait(0.4) ctrl:SelectDifficulty(diff) task.wait(0.6)
                                local svc=Knit.GetService("DungeonQueueService")
                                local ok,res=pcall(function() return svc:RequestStartPodQueue():await() end)
                                if not ok or not res then pcall(function() svc:RequestStartSoloRun():await() end) end
                                task.wait(1) pcall(function() svc:RequestStartNow():await() end)
                            end)
                        end
                    end
                end
                task.wait(5)
            end
        end)
        local real=bestConn
        bestConn={Disconnect=function() State.AutoBestDungeon=false pcall(function() task.cancel(real) end) end}
    else
        if bestConn then pcall(function() bestConn:Disconnect() end) bestConn=nil end
    end
end

    -- =================================================================
    --   UI SETUP (MacLib Adapter)
    -- =================================================================
    local MainTab = Window:CreateTab("Main", "swords")
    local DungeonTab = Window:CreateTab("Dungeon", "map")
    local SettingsTab = Window:CreateTab("Settings", "settings")

    -- Main Tab: Auto Farm
    MainTab:CreateSection("Auto Farm")
    MainTab:CreateToggle({
        Name = "Auto Farm",
        CurrentValue = State.AutoFarm,
        Flag = "DungeonLootrAutoFarm",
        Callback = function(v)
            State.AutoFarm = v
            if v then startFarm() else stopFarm() end
        end
    })
    MainTab:CreateDropdown({
        Name = "Position",
        Options = {"Above", "Behind", "Below"},
        CurrentOption = {State.Position},
        MultipleOptions = false,
        Flag = "DungeonLootrPosition",
        Callback = function(v)
            State.Position = type(v) == "table" and v[1] or v
        end
    })
    MainTab:CreateSlider({
        Name = "Distance",
        Range = {3, 18},
        Increment = 1,
        CurrentValue = State.Distance,
        Suffix = " studs",
        Flag = "DungeonLootrDistance",
        Callback = function(v)
            State.Distance = tonumber(v) or 15
        end
    })

    -- Main Tab: Auto Skill
    MainTab:CreateSection("Auto Skill")
    MainTab:CreateToggle({
        Name = "Auto Skill",
        CurrentValue = State.AutoSkill,
        Flag = "DungeonLootrAutoSkill",
        Callback = function(v)
            if v then startSkill() else stopSkill() end
        end
    })
    MainTab:CreateDropdown({
        Name = "Select Skills",
        Options = {"Skill 1", "Skill 2", "Skill 3", "Skill 4"},
        CurrentOption = {"Skill 1", "Skill 2", "Skill 3", "Skill 4"},
        MultipleOptions = true,
        Flag = "DungeonLootrSkills",
        Callback = function(v)
            local selected = type(v) == "table" and v or {}
            local hasSkill = {}
            for _, s in ipairs(selected) do hasSkill[s] = true end
            State.Skill1 = hasSkill["Skill 1"] == true
            State.Skill2 = hasSkill["Skill 2"] == true
            State.Skill3 = hasSkill["Skill 3"] == true
            State.Skill4 = hasSkill["Skill 4"] == true
        end
    })

    -- Main Tab: Chest & Run
    MainTab:CreateSection("Chest")
    MainTab:CreateToggle({
        Name = "Skip Chest",
        CurrentValue = State.SkipChest,
        Flag = "DungeonLootrSkipChest",
        Callback = function(v) setSkipChest(v) end
    })
    MainTab:CreateToggle({
        Name = "Auto Continue",
        CurrentValue = State.AutoContinue,
        Flag = "DungeonLootrAutoContinue",
        Callback = function(v) setAutoContinue(v) end
    })
    MainTab:CreateToggle({
        Name = "Auto Replay",
        CurrentValue = State.AutoReplay,
        Flag = "DungeonLootrAutoReplay",
        Callback = function(v) setAutoReplay(v) end
    })
    MainTab:CreateToggle({
        Name = "Auto Return",
        CurrentValue = State.AutoReturn,
        Flag = "DungeonLootrAutoReturn",
        Callback = function(v) setAutoReturn(v) end
    })

    -- Main Tab: Potion
    MainTab:CreateSection("Potion")
    MainTab:CreateToggle({
        Name = "Auto Use Potion",
        CurrentValue = State.AutoPotion,
        Flag = "DungeonLootrAutoPotion",
        Callback = function(v) setAutoPotion(v) end
    })

    -- Dungeon Tab: Create Dungeon
    DungeonTab:CreateSection("Create Dungeon")
    local dungeonList = {"Bandits Den", "Goblins", "Knights", "Catacombs", "Snow", "Demon", "Throne Room", "Double Dungeon"}
    local diffList = {"Easy", "Normal", "Hard", "Nightmare", "Endless"}
    DungeonTab:CreateDropdown({
        Name = "Dungeon",
        Options = dungeonList,
        CurrentOption = {State.CreateDungeon},
        MultipleOptions = false,
        Flag = "DungeonLootrCreateDungeon",
        Callback = function(v)
            State.CreateDungeon = type(v) == "table" and v[1] or v
        end
    })
    DungeonTab:CreateDropdown({
        Name = "Difficulty",
        Options = diffList,
        CurrentOption = {State.CreateDifficulty},
        MultipleOptions = false,
        Flag = "DungeonLootrCreateDiff",
        Callback = function(v)
            State.CreateDifficulty = type(v) == "table" and v[1] or v
        end
    })
    DungeonTab:CreateToggle({
        Name = "Auto Create Dungeon",
        CurrentValue = State.AutoCreateDungeon,
        Flag = "DungeonLootrAutoCreateDungeon",
        Callback = function(v)
            State.AutoCreateDungeon = v
            if v then
                task.spawn(function()
                    while State.AutoCreateDungeon and running do
                        local inDungeon = LocalPlayer:GetAttribute("InDungeon") == true
                        if not inDungeon then
                            pcall(function()
                                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                                local part = nil
                                local bestDist = math.huge
                                for _, pz in ipairs(workspace.pods:GetDescendants()) do
                                    if pz.Name == "Touch" and pz:IsA("BasePart") and pz.Parent.Name == "Pod_Zone" then
                                        local d = (pz.Position - hrp.Position).Magnitude
                                        local isFull = false
                                        local att = pz.Parent:FindFirstChild("GuiAttachment", true)
                                        if att then
                                            local bb = att:FindFirstChildWhichIsA("BillboardGui")
                                            if bb then
                                                local lbl = bb:FindFirstChildWhichIsA("TextLabel")
                                                if lbl and lbl.Text:find("4/4") then isFull = true end
                                            end
                                        end
                                        if not isFull and d < bestDist then bestDist = d part = pz end
                                    end
                                end
                                if not part then part = workspace:FindFirstChild("Prompts") and workspace.Prompts:FindFirstChild("Dungeon_Select") end
                                if hrp and part then hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0) task.wait(0.4) hrp.CFrame = part.CFrame + Vector3.new(0, 3, 0) end
                            end)
                            pcall(function()
                                local ctrl = Knit.GetController("DungeonSelectController")
                                ctrl:SelectDungeon(State.CreateDungeon)
                                task.wait(0.4)
                                ctrl:SelectDifficulty(State.CreateDifficulty)
                                task.wait(0.6)
                                local svc = Knit.GetService("DungeonQueueService")
                                local ok, res = pcall(function() return svc:RequestStartPodQueue():await() end)
                                if not ok or not res then
                                    pcall(function() svc:RequestStartSoloRun():await() end)
                                end
                                task.wait(1)
                                pcall(function() local svc2 = Knit.GetService("DungeonQueueService") svc2:RequestStartNow():await() end)
                                pcall(function()
                                    for _, gui in ipairs(game.Players.LocalPlayer.PlayerGui:GetDescendants()) do
                                        if gui:IsA("TextLabel") and gui.Visible then
                                            if gui.Text == "ENTER" or gui.Text == "START" then
                                                local btn = gui.Parent
                                                if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) then pcall(function() btn:Activate() end) end
                                            end
                                        end
                                    end
                                end)
                            end)
                            task.wait(5)
                        else
                            task.wait(3)
                        end
                        if not State.AutoCreateDungeon then break end
                    end
                end)
            end
        end
    })
    DungeonTab:CreateToggle({
        Name = "Auto Best Dungeon",
        CurrentValue = State.AutoBestDungeon,
        Flag = "DungeonLootrAutoBestDungeon",
        Callback = function(v) setAutoBest(v) end
    })

    -- Dungeon Tab: Create Challenger
    DungeonTab:CreateSection("Create Challenger")
    local bossList = {"Scarlet Knight", "Imperator", "Shadow Knight", "Unrestricted EX", "Awakened Devil", "Frigid Monarch"}
    DungeonTab:CreateDropdown({
        Name = "Boss",
        Options = bossList,
        CurrentOption = {State.ChallengerBoss},
        MultipleOptions = false,
        Flag = "DungeonLootrChallengerBoss",
        Callback = function(v)
            State.ChallengerBoss = type(v) == "table" and v[1] or v
        end
    })
    DungeonTab:CreateToggle({
        Name = "Auto Create Challenger",
        CurrentValue = State.AutoCreateChallenger,
        Flag = "DungeonLootrAutoCreateChallenger",
        Callback = function(v) setAutoCreateChallenger(v) end
    })

    -- Dungeon Tab: Create Boss Rush
    DungeonTab:CreateSection("Create Boss Rush")
    local bossRushList = {"Cursed King", "Satori", "Anti Mage", "Great Mage"}
    DungeonTab:CreateDropdown({
        Name = "Boss ",
        Options = bossRushList,
        CurrentOption = {State.BossRushBoss},
        MultipleOptions = false,
        Flag = "DungeonLootrBossRushBoss",
        Callback = function(v)
            State.BossRushBoss = type(v) == "table" and v[1] or v
        end
    })
    DungeonTab:CreateToggle({
        Name = "Auto Create Boss Rush",
        CurrentValue = State.AutoCreateBossRush,
        Flag = "DungeonLootrAutoCreateBossRush",
        Callback = function(v) setAutoCreateBossRush(v) end
    })

    -- Settings Tab: Config
    SettingsTab:CreateSection("Configuration")
    pcall(function()
        if type(SettingsTab.InsertConfigSection) == "function" then
            SettingsTab:InsertConfigSection("Left")
        end
    end)

    -- =================================================================
    --   LIFECYCLE & CLEANUP
    -- =================================================================
    local function stopAll()
        running = false
        State.AutoFarm = false
        State.AutoSkill = false
        State.AutoCreateDungeon = false
        State.AutoBestDungeon = false
        State.AutoCreateChallenger = false
        State.AutoCreateBossRush = false
        stopFarm()
        stopSkill()
        setSkipChest(false)
        setAutoContinue(false)
        setAutoReplay(false)
        setAutoReturn(false)
        setAutoPotion(false)
        setAutoBest(false)
        setAutoCreateChallenger(false)
        setAutoCreateBossRush(false)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(stopAll)
    end

    return {
        Destroy = stopAll
    }
end
