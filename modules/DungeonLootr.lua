-- VoltScriptZ | Dungeon Lootr | RAVEN HUB Module (v3.5.0)
-- Converted to RAVEN HUB (MacLib Adapter)
-- PlaceIds: 132285059959516, 135245842886361 | GameIds: 9656201728, 8410525651

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local StarterGui = game:GetService("StarterGui")
    local LocalPlayer = Players.LocalPlayer
    local Knit = require(ReplicatedStorage.Packages.Knit)

    local running = true

    local AttackRemote = nil
    local SkillRemote = nil
    local DashRemote = nil

    local function getAttackRemote()
        if AttackRemote and AttackRemote.Parent then return AttackRemote end
        pcall(function() AttackRemote = ReplicatedStorage.Player.Remotes.Inputs.Attack end)
        return AttackRemote
    end

    local function getSkillRemote()
        if SkillRemote and SkillRemote.Parent then return SkillRemote end
        pcall(function() SkillRemote = ReplicatedStorage.Player.Remotes.Inputs.Skill end)
        return SkillRemote
    end

    local function getDashRemote()
        if DashRemote and DashRemote.Parent then return DashRemote end
        pcall(function() DashRemote = ReplicatedStorage.Player.Remotes.Inputs.Dash end)
        return DashRemote
    end
    AttackRemote = getAttackRemote()
    SkillRemote = getSkillRemote()
    DashRemote = getDashRemote()

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
    AutoLootChests = true,
    AutoUnlockSecretRooms = true,
    AutoLootSecretChests = true,
    AutoPotion = false,
    PotionHealthPercent = 60,
    AutoRefillPotion = false,
    AutoStats = false,
    StatMode = "Game Recommended (Auto)",
    StatTarget = "Strength (STR)",
    AutoEquipBest = false,
    MobESP = false,
    ChestESP = false,
    AutoReplay = false,
    AutoReturn = false,
    CreateDungeon = "Bandits Den",
    CreateDifficulty = "Easy",
    AutoCreateDungeon = false,
    AutoBestDungeon = false,
    AutoCreateChallenger = false,
    ChallengerBoss = "Scarlet Knight",
    AutoCreateBossRush = false,
    AutoBlessing = true,
    BlessingPriority = "Damage (ATK)",
    AutoSummonSpecialBoss = true,
    AutoExtractEndless = false,
    EndlessExtractDepth = 15,
    AutoSellGear = false,
    SellMaxRarity = "Rare",
    AutoClaimRewards = false,
    StreamerMode = false,
    AutoReroll = false,
    RerollSpinType = "Normal",
    RerollTargetSlot = 1,
    RerollTargetClasses = {},
    AutoDodge = true,
    DodgeMode = "Dash & Evade",
    DodgeRadius = 24,
    DodgeDuration = 1.4,
    DodgeDistance = 32,
    WebhookEnabled = false,
    WebhookUrl = "",
    WebhookOnVictory = true,
    WebhookOnDefeat = true
}

local function getGeneratedFolder()
    for _,v in ipairs(workspace:GetChildren()) do if v.Name:match("^Generated_") and v:IsA("Folder") then return v end end
    return nil
end

local function getHRP(model)
    if not model or not model:IsA("Instance") then return nil end
    local hrp = model:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name == "HumanoidRootPart" then
            return desc
        end
    end
    local fallback = (model:IsA("Model") and model.PrimaryPart) or model:FindFirstChild("Torso") or model:FindFirstChild("Head")
    if fallback and fallback:IsA("BasePart") then return fallback end
    return model:FindFirstChildWhichIsA("BasePart", true)
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
        -- StreamingEnabled Fix: ตรวจสอบ BasePart ด้วย getHRP เพื่อกัน Pose หรือชิ้นส่วนอนิเมชั่น
        local hrp = getHRP(model)
        if not hrp then
            local isInNpcFolder = model.Parent and model.Parent.Name == "NPCs"
            local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
            if not isInNpcFolder and not anyPart then return false end
        end
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

local function getActiveDungeonZone()
    -- ดึงลำดับ Zone ตรงจาก Completion_Progress Data ของ DungeonHUDController (ตรงตามรูปดาว HUD 100%)
    if getgc and debug and debug.getupvalues then
        for _, v in ipairs(getgc()) do
            if type(v) == "function" and islclosure(v) then
                local info = debug.getinfo(v)
                if info.name == "CPBuild" or info.name == "CPMoveCurrentToPos" then
                    for _, u in ipairs(debug.getupvalues(v)) do
                        if type(u) == "table" and rawget(u, "Zones") and rawget(u, "ByIndex") then
                            local curZone = u.Zones[u.CurrentPos]
                            if curZone then
                                return curZone.Index, u.CurrentPos, u.Zones
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil
end

local function getCombatRoomCenters()
    local gen = getGeneratedFolder() if not gen then return {} end
    local activeIdx, curPos, zones = getActiveDungeonZone()
    local out = {}

    -- 1. ถ้าดึงจาก Completion_Progress Data ได้ ใช้ลำดับ Zone ตามเกม 100% (Room_2 -> 6 -> 8 -> 10 -> 14 -> 16 -> 20 -> 22)
    if zones and #zones > 0 then
        for _, z in ipairs(zones) do
            local rName = "Room_" .. tostring(z.Index)
            local room = gen:FindFirstChild(rName)
            if room then
                local cf, sz = nil, nil
                pcall(function() cf, sz = room:GetBoundingBox() end)
                if cf then
                    local floorY = cf.Position.Y
                    if sz and sz.Y > 10 then
                        floorY = cf.Position.Y - (sz.Y / 2) + 6
                    end
                    local roomCF = CFrame.new(Vector3.new(cf.Position.X, floorY, cf.Position.Z))
                    table.insert(out, {
                        idx = z.Index,
                        cf = roomCF,
                        name = rName,
                        isBoss = z.IsBoss == true,
                        done = z.Done == true
                    })
                end
            end
        end
        if #out > 0 then return out end
    end

    -- 2. Fallback: หาเฉพาะห้องที่มี Enemy_Spawn หรือเป็นห้อง Boss (ไม่เอาทางเดินว่างเปล่า)
    for _, room in ipairs(gen:GetChildren()) do
        if room:IsA("Model") or room:IsA("Folder") then
            if not room.Name:match("^Room_%d+$") then continue end
            local spawns = room:FindFirstChild("Spawns")
            local hasSpawn = false
            if spawns then
                for _, s in ipairs(spawns:GetChildren()) do
                    if s.Name == "Enemy_Spawn" or s.Name:find("Boss") then hasSpawn = true break end
                end
            end
            local idx = room:GetAttribute("RoomIndex") or tonumber(room.Name:match("%d+")) or 999
            if hasSpawn or idx == 22 then
                local cf, sz = nil, nil
                pcall(function() cf, sz = room:GetBoundingBox() end)
                if cf then
                    local floorY = cf.Position.Y
                    if sz and sz.Y > 10 then
                        floorY = cf.Position.Y - (sz.Y / 2) + 6
                    end
                    local roomCF = CFrame.new(Vector3.new(cf.Position.X, floorY, cf.Position.Z))
                    table.insert(out, {idx = idx, cf = roomCF, name = room.Name, isBoss = (idx == 22)})
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.idx or 999) < (b.idx or 999) end)
    return out
end

local function getRoomCenters()
    return getCombatRoomCenters()
end

local function isZoneClear()
    local ok = false
    pcall(function()
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local dc = pgui and pgui:FindFirstChild("Main", true) and pgui.Main:FindFirstChild("HUD", true) and pgui.Main.HUD:FindFirstChild("Dungeon_Container", true)
        if dc then
            local notif = dc:FindFirstChild("Notification_Canvas", true)
            local zc = notif and notif:FindFirstChild("Zone_Cleared")
            if zc and zc.Visible then
                ok = true
            end
        end
    end)
    return ok
end

local nextRoomPointer=2

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
    local r = getAttackRemote()
    if not r then return end
    local d = dir or Vector3.new(0,-1,0)
    pcall(function() r:FireServer(d) end)
    if d~=Vector3.new(0,0,0) then pcall(function() r:FireServer(Vector3.new(0,0,0)) end) end
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
    if not isValidChar() then return end
    local char=LocalPlayer.Character if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart") if not hrp then return end
    hoverConn=RunService.Heartbeat:Connect(function()
        if not State.AutoFarm then return end
        if lockConn then return end -- ถ้าล็อคมอนอยู่ให้ lock คุมแทน
        if isDodgingNow then return end -- กำลังหลบ AoE อยู่ ให้ระงับการ hover ชั่วคราว
        if not isValidChar() then stopHover() return end
        local c=LocalPlayer.Character
        local h=c and c:FindFirstChild("HumanoidRootPart")
        if not h then return end
        h.CFrame=hoverCF
        h.AssemblyLinearVelocity=Vector3.new(0,0,0)
        h.AssemblyAngularVelocity=Vector3.new(0,0,0)
        h.Velocity=Vector3.new(0,0,0)
    end)
end
local function stopHover()
    if hoverConn then pcall(function() hoverConn:Disconnect() end) hoverConn=nil end
end
local function startLock(targetHRP)
    curTargetHRP=targetHRP
    stopHover()
    if lockConn then pcall(function() lockConn:Disconnect() end) lockConn=nil end
    if not isValidChar() then return end
    local char=LocalPlayer.Character if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart") local hum=char:FindFirstChildOfClass("Humanoid") if not hrp or not hum then return end
    pcall(function() hrp.Anchored=false hum.PlatformStand=false hum:ChangeState(Enum.HumanoidStateType.Physics) end)
    local _, initCF = getPositionForMode(curTargetHRP, State.Position, State.Distance)
    pcall(function() hrp.CFrame=initCF hrp.AssemblyLinearVelocity=Vector3.new(0,0,0) hrp.AssemblyAngularVelocity=Vector3.new(0,0,0) hrp.Velocity=Vector3.new(0,0,0) end)
    hoverCF=initCF
    local hb, rs
    hb=RunService.Heartbeat:Connect(function()
        if not State.AutoFarm or not State.CFrameLock then return end
        if isDodgingNow then return end -- กำลังหลบ AoE อยู่ ให้ระงับการล็อกตำแหน่งชั่วคราว
        if not isValidChar() then stopLock() return end
        local c=LocalPlayer.Character
        local h=c and c:FindFirstChild("HumanoidRootPart")
        if not curTargetHRP or not curTargetHRP.Parent or not h then return end
        local _, cf = getPositionForMode(curTargetHRP, State.Position, State.Distance)
        hoverCF=cf
        h.CFrame=cf
        h.AssemblyLinearVelocity=Vector3.new(0,0,0)
        h.AssemblyAngularVelocity=Vector3.new(0,0,0)
        h.Velocity=Vector3.new(0,0,0)
    end)
    rs=RunService.Stepped:Connect(function()
        if not State.AutoFarm or not State.CFrameLock then return end
        if isDodgingNow then return end -- กำลังหลบ AoE อยู่ ให้ระงับการล็อกตำแหน่งชั่วคราว
        if not isValidChar() then stopLock() return end
        local c=LocalPlayer.Character
        local h=c and c:FindFirstChild("HumanoidRootPart")
        if not curTargetHRP or not curTargetHRP.Parent or not h then return end
        h.AssemblyLinearVelocity=Vector3.new(0,0,0)
        h.Velocity=Vector3.new(0,0,0)
    end)
    lockConn={Disconnect=function() pcall(function() hb:Disconnect() rs:Disconnect() end) end}
end
local function stopLock()
    local lastCF=nil
    if isValidChar() then
        local char=LocalPlayer.Character
        local hrp=char and char:FindFirstChild("HumanoidRootPart")
        if hrp then lastCF=hrp.CFrame end
    end
    curTargetHRP=nil
    if lockConn then pcall(function() lockConn:Disconnect() end) lockConn=nil end
    if lastCF and isValidChar() then startHover(lastCF) end
end

local function safeWarp(cf)
    stopHover()
    if not isValidChar() then return end
    local char=LocalPlayer.Character if not char then return end
    local hrp=char:FindFirstChild("HumanoidRootPart") if not hrp then return end
    hoverCF=cf
    pcall(function() hrp.CFrame=cf hrp.AssemblyLinearVelocity=Vector3.new(0,0,0) hrp.AssemblyAngularVelocity=Vector3.new(0,0,0) hrp.Velocity=Vector3.new(0,0,0) end)
    -- ลอยนิ่งต่อ 0.6วิ กันร่วงช่วงสลับมอน แล้วค้าง hover ไว้จนกว่าจะ lock มอนตัวถัดไป
    local t0=tick()
    while tick()-t0 < 0.6 do
        if not State.AutoFarm or not isValidChar() then break end
        local c=LocalPlayer.Character
        local h=c and c:FindFirstChild("HumanoidRootPart")
        if not h then break end
        pcall(function() h.CFrame=hoverCF h.AssemblyLinearVelocity=Vector3.new(0,0,0) h.Velocity=Vector3.new(0,0,0) end)
        RunService.Heartbeat:Wait()
    end
    if isValidChar() then
        startHover(hoverCF)
    end
end

local function isInRoom(m, roomIdx, roomCenter)
    if m:GetAttribute("RoomIndex") == roomIdx then return true end
    local hrpM = getHRP(m)
    if hrpM and roomCenter and (hrpM.Position - roomCenter.cf.Position).Magnitude < 130 then return true end
    return false
end

local function hasMobsInRoom(roomIdx, roomCenter)
    local mons = getMonsters()
    for _, m in ipairs(mons) do
        if isInRoom(m, roomIdx, roomCenter) then return true end
    end
    return false
end

local function collectRoomChests(roomIdx, roomCenter)
    if not State.AutoLootChests then return end
    -- กฎสำคัญ: ต้องเคลียร์มอนสเตอร์ในห้องให้หมด 100% ก่อน ห้ามวาร์ปไปหากล่องถ้ายังมีมอนสเตอร์อยู่
    if roomIdx and roomCenter and hasMobsInRoom(roomIdx, roomCenter) then return end
    if not roomIdx and #getMonsters() > 0 then return end

    local gen = getGeneratedFolder()
    if not gen then return end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local chestsToLoot = {}
    for _, obj in ipairs(gen:GetChildren()) do
        if obj:IsA("Model") and (obj.Name:find("DungeonChest") or obj:GetAttribute("DungeonChest") == true) then
            local chestRoomIdx = obj:GetAttribute("RoomIndex")
            local cf = nil
            pcall(function() cf = obj:GetBoundingBox() end)
            local inRoom = false
            if roomIdx then
                if chestRoomIdx == roomIdx or chestRoomIdx == (1000 + roomIdx) then
                    inRoom = true
                elseif roomCenter and cf and (cf.Position - roomCenter.cf.Position).Magnitude < 70 then
                    inRoom = true
                end
            else
                inRoom = true
            end

            if inRoom then
                local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                -- กล่องต้องปลดล็อคแล้ว (Enabled = true) เท่านั้น
                if prompt and prompt.Enabled then
                    table.insert(chestsToLoot, {model = obj, cf = cf, prompt = prompt})
                end
            end
        end
    end

    if #chestsToLoot == 0 then return end

    stopLock()
    stopHover()

    for _, cData in ipairs(chestsToLoot) do
        if not State.AutoFarm or not State.AutoLootChests then break end
        if cData.prompt and cData.prompt.Parent and cData.prompt.Enabled then
            local promptPos = nil
            local pPart = cData.prompt.Parent
            if pPart:IsA("BasePart") then
                promptPos = pPart.Position
            elseif pPart:IsA("Attachment") then
                promptPos = pPart.WorldPosition
            elseif cData.cf then
                promptPos = cData.cf.Position
            end

            if promptPos then
                local standPos = promptPos + Vector3.new(0, 2, 3)
                safeWarp(CFrame.new(standPos, promptPos))
                task.wait(0.2)
                pcall(function()
                    fireproximityprompt(cData.prompt)
                end)
                task.wait(0.35)
            end
        end
    end
end

-- ระบบปลดล็อคห้องลับ (Secret / Locked Rooms) และเก็บกล่องลับ
-- ตรวจสอบเงื่อนไขอย่างเคร่งครัด:
-- 1. ต้องมีกุญแจสำหรับห้องนั้น (Prompt.Enabled == true) ถ้าไม่มีกุญแจจะข้ามทันทีเพื่อไม่ให้ติดค้าง
-- 2. เคลียร์มอนสเตอร์/Mimic ที่อยู่ในห้องลับให้หมดก่อน (ถ้ามี)
-- 3. กล่องต้องปลดล็อคแล้ว (ไม่มี Chest_Lock หรือ Prompt.Enabled == true) จึงจะเก็บ
local function processSecretRoom(parentRoomIdx, parentRoomCenter)
    if not State.AutoUnlockSecretRooms and not State.AutoLootSecretChests then return end
    local gen = getGeneratedFolder()
    if not gen then return end
    local char = LocalPlayer.Character
    local hrp = char and getHRP(char)
    if not hrp then return end

    -- ค้นหาห้องลับที่เป็นห้องลูกของห้องปัจจุบัน (ParentRoomIndex ตรงกัน หรืออยู่ใกล้ห้องนี้)
    for _, ch in ipairs(gen:GetChildren()) do
        if ch.Name:match("^Locked_") then
            local pIdx = ch:GetAttribute("ParentRoomIndex")
            local isMatching = false
            if parentRoomIdx and pIdx == parentRoomIdx then
                isMatching = true
            elseif parentRoomCenter then
                local roomPivot = ch:GetPivot()
                if (roomPivot.Position - parentRoomCenter.cf.Position).Magnitude < 140 then
                    isMatching = true
                end
            end

            if isMatching then
                -- 1. ตรวจสอบสวิตช์/แท่นไขกุญแจ (KeyModel)
                local km = ch:FindFirstChild("KeyModel", true)
                local keyPrompt = km and km:FindFirstChildOfClass("ProximityPrompt")

                -- ถ้าประตูลับยังไม่เปิด (มี keyPrompt อยู่)
                if keyPrompt and State.AutoUnlockSecretRooms then
                    -- เช็คเงื่อนไขสำคัญ: ผู้เล่นต้องมีกุญแจตรงตามที่กำหนด (Prompt.Enabled == true)
                    -- หากไม่มีกุญแจ (Enabled == false) ให้ข้ามห้องลับนี้ทันที ไม่ติดค้าง!
                    if keyPrompt.Enabled then
                        local kmPivot = km:GetPivot()
                        safeWarp(CFrame.new(kmPivot.Position + Vector3.new(0, 2, 3), kmPivot.Position))
                        task.wait(0.2)
                        pcall(function() fireproximityprompt(keyPrompt) end)
                        task.wait(0.5)
                        -- รอเปิดประตูสักครู่
                        local waitOpen = 0
                        while waitOpen < 2 and keyPrompt.Enabled do
                            task.wait(0.2) waitOpen += 0.2
                        end
                    end
                end

                -- 2. ตรวจสอบมอนสเตอร์ / Mimic ภายในห้องลับนี้
                -- หากมีมอนสเตอร์สปอนออกมา ต้องกำจัดให้หมด 100% ก่อนถึงจะเก็บกล่องได้
                local roomPivot = ch:GetPivot()
                local secretMobs = {}
                for _, m in ipairs(getMonsters()) do
                    local mHrp = getHRP(m)
                    if mHrp and (mHrp.Position - roomPivot.Position).Magnitude < 70 then
                        table.insert(secretMobs, m)
                    end
                end

                if #secretMobs > 0 and State.AutoFarm then
                    for _, mob in ipairs(secretMobs) do
                        if not State.AutoFarm or not isValidChar() then break end
                        local targetHRP = getHRP(mob)
                        if targetHRP and mob.Parent then
                            if State.CFrameLock then
                                startLock(targetHRP)
                                local hum = mob:FindFirstChildOfClass("Humanoid")
                                while State.AutoFarm and mob.Parent do
                                    if not isValidChar() then break end
                                    local dead = false
                                    if hum then dead = hum.Health <= 0
                                    else local hp = mob:GetAttribute("HealthOverride") if hp ~= nil then dead = hp <= 0 end end
                                    if dead then break end
                                    local dir = State.Position=="Above" and Vector3.new(0,-1,0) or State.Position=="Below" and Vector3.new(0,1,0) or Vector3.new(0,0,-1)
                                    fireM1(dir) task.wait(State.AttackDelay)
                                end
                                stopLock()
                            else
                                local _, cf = getPositionForMode(targetHRP, State.Position, State.Distance)
                                pcall(function() hrp.CFrame = cf end)
                                for i=1,4 do
                                    if not State.AutoFarm or not isValidChar() then break end
                                    fireM1() task.wait(State.AttackDelay)
                                end
                            end
                            task.wait(0.2)
                        end
                    end
                end

                -- 3. เก็บกล่องในห้องลับ (ถ้ามอนสเตอร์ในห้องลับตายหมดแล้ว และกล่องปลดล็อคแล้ว)
                if State.AutoLootSecretChests then
                    -- เช็คอีกครั้งว่าไม่มีมอนในห้องลับหลงเหลืออยู่
                    local remainingMobs = 0
                    for _, m in ipairs(getMonsters()) do
                        local mHrp = getHRP(m)
                        if mHrp and (mHrp.Position - roomPivot.Position).Magnitude < 70 then
                            remainingMobs += 1
                        end
                    end

                    if remainingMobs == 0 then
                        for _, c in ipairs(gen:GetChildren()) do
                            if c.Name:match("^DungeonChest_") then
                                local cPos = c:GetPivot().Position
                                if (cPos - roomPivot.Position).Magnitude < 70 then
                                    local hasLock = c:FindFirstChild("Chest_Lock") ~= nil
                                    local prompt = c:FindFirstChildWhichIsA("ProximityPrompt", true)
                                    -- กล่องต้องปลดล็อคแล้ว (ไม่มี Chest_Lock และ Prompt.Enabled == true)
                                    if not hasLock and prompt and prompt.Enabled then
                                        stopLock()
                                        stopHover()
                                        local standPos = cPos + Vector3.new(0, 2, 3)
                                        safeWarp(CFrame.new(standPos, cPos))
                                        task.wait(0.2)
                                        pcall(function() fireproximityprompt(prompt) end)
                                        task.wait(0.35)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- 1. ฟังก์ชันรับบัฟจากแท่น Altar (Blessing Altar)
local function selectBlessingCardNow()
    local ok, boostCtrl = pcall(function() return Knit.GetController("BoostSelectionController") end)
    if not ok or not boostCtrl then return false end
    if not boostCtrl._active or not boostCtrl._candidates or #boostCtrl._candidates == 0 then return false end

    local pickIndex = 1
    local priority = State.BlessingPriority or "Damage (ATK)"
    for idx, c in ipairs(boostCtrl._candidates) do
        local t = (c.Title or ""):lower()
        local d = (c.Description or ""):lower()
        local id = (c.Id or ""):lower()
        if priority == "Damage (ATK)" then
            if t:find("attack") or t:find("damage") or t:find("crit") or t:find("flowstate") or t:find("cooldown") or id:find("cd") or id:find("atk") or id:find("crit") or d:find("damage") or d:find("attack") then
                pickIndex = idx
                break
            end
        elseif priority == "Defense / Health" then
            if t:find("health") or t:find("defense") or t:find("armor") or t:find("bloodlust") or id:find("hp") or id:find("def") or d:find("health") or d:find("shield") then
                pickIndex = idx
                break
            end
        elseif priority == "Speed / Haste" then
            if t:find("speed") or t:find("haste") or t:find("fleetfoot") or id:find("move") or id:find("speed") or d:find("speed") then
                pickIndex = idx
                break
            end
        end
    end

    -- ปรับตัวแปร controller ให้พร้อมคลิกทันที (Bypass UI delay)
    boostCtrl._ready = true
    boostCtrl._selecting = false
    pcall(function() boostCtrl:_OnCardClicked(pickIndex) end)

    -- Fallback: เผื่อ controller ไม่ตอบสนอง เรียกผ่าน Knit Service โดยตรง
    task.defer(function()
        task.wait(0.6)
        if boostCtrl and boostCtrl._active then
            pcall(function() Knit.GetService("DungeonBuffService"):SelectBuff(pickIndex) end)
        end
    end)
    return true
end

local function processAltarBlessing(roomIdx, roomCenter)
    if not State.AutoBlessing then return end
    local gen = getGeneratedFolder()
    if not gen then return end
    local char = LocalPlayer.Character
    local hrp = char and getHRP(char)
    if not hrp then return end

    -- ถ้าหน้าต่างเลือกการ์ดค้างอยู่แล้ว ให้กดเลือกทันที!
    if selectBlessingCardNow() then
        task.wait(0.5)
        return
    end

    -- ค้นหาแท่น Altar ในห้องนี้
    local targetAltarPrompt = nil
    local targetAltarPos = nil
    for _, desc in ipairs(gen:GetDescendants()) do
        local n = desc.Name:lower()
        if n:find("altar") or n:find("blessing") then
            local pos = desc:IsA("Model") and desc:GetPivot().Position or (desc:IsA("BasePart") and desc.Position)
            if pos then
                local inThisRoom = false
                if roomCenter and (pos - roomCenter.cf.Position).Magnitude < 140 then
                    inThisRoom = true
                elseif not roomCenter then
                    inThisRoom = true
                end

                if inThisRoom then
                    local prompt = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and prompt.Enabled then
                        local act = (prompt.ActionText or ""):lower()
                        local obj = (prompt.ObjectText or ""):lower()
                        if act:find("blessing") or act:find("receive") or obj:find("altar") or obj:find("blessing") then
                            targetAltarPrompt = prompt
                            targetAltarPos = pos
                            break
                        end
                    end
                end
            end
        end
    end

    if targetAltarPrompt and targetAltarPos then
        stopLock()
        stopHover()
        local standPos = targetAltarPos + Vector3.new(0, 2, 3)
        safeWarp(CFrame.new(standPos, targetAltarPos))
        task.wait(0.2)
        pcall(function() fireproximityprompt(targetAltarPrompt) end)

        -- รอจนกว่าหน้าต่าง Boost Selection จะปรากฏ (รอสูงสุด 2.5 วินาที)
        local waited = 0
        local chosen = false
        while waited < 2.5 and State.AutoBlessing do
            task.wait(0.25)
            waited += 0.25
            if selectBlessingCardNow() then
                chosen = true
                break
            end
        end
        task.wait(0.3)
    end
end

local blessingConn = nil
local function setAutoBlessing(enabled)
    State.AutoBlessing = enabled
    if enabled then
        if blessingConn then pcall(function() blessingConn:Disconnect() end) end
        local ok, dbs = pcall(function() return Knit.GetService("DungeonBuffService") end)
        if ok and dbs and dbs.BuffSelection then
            blessingConn = dbs.BuffSelection:Connect(function()
                if not State.AutoBlessing then return end
                task.wait(0.4)
                selectBlessingCardNow()
            end)
        end
        -- Fallback loop: ตรวจสอบหน้าต่าง BoostSelectionController ตลอดเวลา
        task.spawn(function()
            while State.AutoBlessing and running do
                pcall(function()
                    local boostCtrl = Knit.GetController("BoostSelectionController")
                    if boostCtrl and boostCtrl._active and boostCtrl._candidates and #boostCtrl._candidates > 0 then
                        selectBlessingCardNow()
                    end
                end)
                task.wait(0.5)
            end
        end)
    else
        if blessingConn then pcall(function() blessingConn:Disconnect() end) blessingConn = nil end
    end
end

-- 2. ฟังก์ชันอัญเชิญ Special Boss จากแท่น Skull_Totem (ใช้ 7x Platinum Key)
local function processSpecialBossSummon()
    if not State.AutoSummonSpecialBoss then return end
    local gen = getGeneratedFolder()
    if not gen then return end
    local char = LocalPlayer.Character
    local hrp = char and getHRP(char)
    if not hrp then return end

    -- ตรวจสอบว่ามีแท่น Skull_Totem ในดันเจี้ยนหรือไม่
    local totem = nil
    for _, desc in ipairs(gen:GetDescendants()) do
        if desc.Name == "Skull_Totem" and desc:IsA("Model") then
            local p = desc:FindFirstChildWhichIsA("ProximityPrompt", true)
            if p and p.Enabled then
                totem = { model = desc, prompt = p, pos = desc:GetPivot().Position }
                break
            end
        end
    end

    if not totem then return end

    -- ตรวจสอบว่าผู้เล่นมีกุญแจ Platinum Key >= 7 หรือไม่
    local canSummon = false
    pcall(function()
        local ks = Knit.GetService("KeyService")
        if ks and ks.GetAllKeys then
            local keys = ks:GetAllKeys():await()
            if keys and (keys.T4 and keys.T4 >= 7 or keys.Platinum and keys.Platinum >= 7 or keys.Master and keys.Master >= 1) then
                canSummon = true
            end
        end
    end)

    if canSummon and totem.prompt.Enabled then
        stopLock()
        stopHover()
        local standPos = totem.pos + Vector3.new(0, 2, 3)
        safeWarp(CFrame.new(standPos, totem.pos))
        task.wait(0.2)
        pcall(function() fireproximityprompt(totem.prompt) end)
        task.wait(1)
    end
end

local farmThread=nil
-- ใหม่: เคลียร์ครบทุกห้องสปอนก่อน Boss จะเกิด (ห้ามข้าม / ห้ามรอเวฟมั่ว)
local farmThread=nil
local function startFarm()
    if farmThread then return end
    farmThread=task.spawn(function()
        setNoclip(true)
        _G.__farmStarted=nil
        local lastRoomIndex=nil
        local clearedRooms={}
        local function markCleared(idx) clearedRooms[idx]=true end
        local function isCleared(idx) return clearedRooms[idx]==true end

        while State.AutoFarm do
            if (not running) then break end
            if not isValidChar() then stopLock() task.wait(1) continue end
            local char=LocalPlayer.Character local hrp=char:FindFirstChild("HumanoidRootPart")
            if not hrp then task.wait(0.5) continue end

            local combatCenters = getCombatRoomCenters()
            if #combatCenters == 0 then task.wait(1) continue end

            -- ค้นหาห้องเป้าหมายตามลำดับดาว HUD ของเกมโดยตรง (ห้ามข้ามห้อง)
            local activeRoomIdx, curZonePos, zones = getActiveDungeonZone()
            local curCenter = nil

            -- ถ้า activeRoomIdx ยังไม่ถูกเคลียร์ ให้เล็ง activeRoomIdx ก่อน
            if activeRoomIdx and not isCleared(activeRoomIdx) then
                for _, c in ipairs(combatCenters) do
                    if c.idx == activeRoomIdx then
                        curCenter = c
                        break
                    end
                end
            end

            -- ถ้า activeRoomIdx ถูกเคลียร์ไปแล้ว หรือหาไม่เจอ ให้เดินหน้าไปยังห้องถัดไปในลำดับที่ยังไม่เคลียร์
            if not curCenter then
                for _, c in ipairs(combatCenters) do
                    if not isCleared(c.idx) and not c.done then
                        curCenter = c
                        break
                    end
                end
            end

            if not curCenter then
                curCenter = combatCenters[#combatCenters] -- ห้องสุดท้าย (Boss)
            end

            local curIdx = curCenter.idx

            -- Boss handling: ถ้าห้องนี้เป็น Boss หรือมีบอสเกิด
            local allMons = getMonsters()
            local boss = nil
            for _, m in ipairs(allMons) do
                if m:GetAttribute("IsBoss") == true or m:GetAttribute("IsMapBoss") == true or m:GetAttribute("BossType") ~= nil then
                    boss = m
                    break
                end
            end

            if boss and (curCenter.isBoss or (curIdx == 22)) then
                local targetHRP = getHRP(boss)
                if not targetHRP then
                    safeWarp(curCenter.cf + Vector3.new(0, 10, 0))
                    task.wait(0.4)
                    targetHRP = getHRP(boss)
                end
                if targetHRP then
                    startLock(targetHRP)
                    local hum = boss:FindFirstChildOfClass("Humanoid")
                    while State.AutoFarm and boss.Parent do
                        if not isValidChar() then break end
                        local dead = false
                        if hum then dead = hum.Health <= 0
                        else local hp = boss:GetAttribute("HealthOverride") if hp ~= nil then dead = hp <= 0 end end
                        if dead then break end
                        local dir = State.Position=="Above" and Vector3.new(0,-1,0) or State.Position=="Below" and Vector3.new(0,1,0) or Vector3.new(0,0,-1)
                        fireM1(dir) task.wait(State.AttackDelay)
                    end
                    stopLock()
                    if not isValidChar() then task.wait(1) continue end
                    task.wait(0.5)
                    -- บอสตายแล้ว ตรวจสอบว่าไม่มีมอนเหลือแล้ว จึงเก็บกล่องทั้งหมด
                    if #getMonsters() == 0 then
                        collectRoomChests(nil, nil)
                    end
                    task.wait(1)
                    continue
                end
            end

            -- หามอนในห้องปัจจุบัน
            local monsInRoom = {}
            for _, m in ipairs(allMons) do
                if isInRoom(m, curIdx, curCenter) then
                    table.insert(monsInRoom, m)
                end
            end

            -- ถ้าตัวละครอยู่ห่างจากห้องเป้าหมาย (>40 studs) ให้วาร์ปเข้าห้องก่อนเพื่อให้ Roblox stream in
            if (hrp.Position - curCenter.cf.Position).Magnitude > 40 then
                safeWarp(curCenter.cf + Vector3.new(0, 3, 0))
                task.wait(0.3)
                hrp = getHRP(LocalPlayer.Character) or hrp
            end

            -- 1. ถ้ายังมีมอนในห้องนี้ → ตีทีละตัวจนหมดห้อง (ห้ามข้ามห้องและห้ามไปหากล่อง)
            if #monsInRoom > 0 then
                local target = getClosest(monsInRoom, hrp.Position) or monsInRoom[1]
                local targetHRP = getHRP(target)
                if not targetHRP then
                    safeWarp(curCenter.cf + Vector3.new(0, 3, 0))
                    task.wait(0.3)
                    targetHRP = getHRP(target)
                end
                if targetHRP then
                    if State.CFrameLock then
                        startLock(targetHRP)
                        local hum = target:FindFirstChildOfClass("Humanoid")
                        while State.AutoFarm and target.Parent do
                            if not isValidChar() then break end
                            local dead = false
                            if hum then dead = hum.Health <= 0
                            else local hp = target:GetAttribute("HealthOverride") if hp ~= nil then dead = hp <= 0 end end
                            if dead then break end
                            local dir = State.Position=="Above" and Vector3.new(0,-1,0) or State.Position=="Below" and Vector3.new(0,1,0) or Vector3.new(0,0,-1)
                            fireM1(dir) task.wait(State.AttackDelay)
                        end
                        stopLock()
                    else
                        local _, cf = getPositionForMode(targetHRP, State.Position, State.Distance)
                        pcall(function() hrp.CFrame = cf end)
                        for i=1,4 do
                            if not State.AutoFarm or not isValidChar() then break end
                            fireM1() task.wait(State.AttackDelay)
                        end
                    end
                end
                if not isValidChar() then task.wait(1) continue end
                task.wait(0.2)
                continue -- ตีมอนตัวถัดไปในห้องนี้ทันที ห้ามไปทำอย่างอื่น
            end

            -- 2. ถ้า #monsInRoom == 0 (มอนปัจจุบันหมดแล้ว)
            -- รอเช็ค Wave สปอนถัดไป (2.5 วิ) กันกรณีมอนเวฟ 2 กำลังจะเกิด ไม่รีบไปหากล่อง
            local moreWave = false
            local waitTime = 0
            while State.AutoFarm and waitTime < 2.5 do
                task.wait(0.5)
                waitTime += 0.5
                if hasMobsInRoom(curIdx, curCenter) then
                    moreWave = true
                    break
                end
            end
            if moreWave then
                continue -- มีเวฟใหม่เกิดมา ลุยตีต่อ ไม่ไปหากล่อง
            end

            -- ถ้าเป็น Rush/Survive/Might หรือห้องพิเศษ
            local waited = 0
            while State.AutoFarm and waited < 8 do
                if isZoneClear() then break end
                if not hasMobsInRoom(curIdx, curCenter) and waited >= 2 then break end
                task.wait(0.5) waited += 0.5
            end

            -- เคลียร์มอนหมดห้องแน่นอนแล้ว 100% จึงเก็บกล่องของห้องนี้
            if not hasMobsInRoom(curIdx, curCenter) then
                collectRoomChests(curIdx, curCenter)
                -- ตรวจสอบและปลดล็อคห้องลับ (ถ้ามีกุญแจ) พร้อมจัดการมอนสเตอร์และเก็บกล่องลับ
                processSecretRoom(curIdx, curCenter)
                -- ตรวจสอบและรับบัฟจากแท่น Altar (ถ้ามีในห้องนี้)
                processAltarBlessing(curIdx, curCenter)
                -- ตรวจสอบและเสกบอสพิเศษจากแท่น Skull_Totem (ถ้ามีกุญแจ 7x Platinum Key)
                processSpecialBossSummon()
            end
            markCleared(curIdx)

            -- ตรวจสอบการจบดันเจี้ยนเมื่อถึงห้องบอส (ห้องสุดท้ายของดันเจี้ยน)
            local isLastRoom = (curCenter == combatCenters[#combatCenters]) or (curIdx == 22)
            if isLastRoom and (curCenter.isBoss or curIdx == 22 or #combatCenters == 1) then
                local waitedBoss = 0
                while waitedBoss < 8 and State.AutoFarm do
                    task.wait(0.5) waitedBoss += 0.5
                    if #getMonsters() == 0 and waitedBoss >= 6 then
                        pcall(function()
                            local svc = Knit.GetService("DungeonRunService")
                            if svc then
                                if svc.RequestReturn then pcall(function() svc:RequestReturn():await() end) end
                                if svc.RequestLeave then pcall(function() svc:RequestLeave():await() end) end
                            end
                            for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                                if gui:IsA("TextLabel") and gui.Visible and (gui.Text=="Return" or gui.Text=="Leave") then
                                    local btn = gui.Parent
                                    while btn and not (btn:IsA("TextButton") or btn:IsA("ImageButton")) do btn = btn.Parent end
                                    if btn and btn.Visible and btn.Active then pcall(function() btn:Activate() end) break end
                                end
                            end
                        end)
                        break
                    end
                end
            else
                -- หากไม่ใช่ห้องบอส ให้พาตัวละครวาร์ปมุ่งหน้าไปยังห้องถัดไปทันที
                local nextTarget = nil
                for _, c in ipairs(combatCenters) do
                    if not isCleared(c.idx) and not c.done then
                        nextTarget = c
                        break
                    end
                end
                if nextTarget and nextTarget.cf then
                    stopLock()
                    safeWarp(nextTarget.cf + Vector3.new(0, 3, 0))
                    task.wait(0.3)
                end
            end

            task.wait(0.3)
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
    if skillThread then return end
    State.AutoSkill=true
    skillThread=task.spawn(function()
        while State.AutoSkill and running do
            if not isValidChar() then
                task.wait(1)
            else
                local remote = getSkillRemote()
                if remote then
                    if State.Skill1 and isValidChar() then pcall(function() remote:FireServer(1, "tap", Vector3.new(0,0,0)) end) end
                    task.wait(0.15) if not State.AutoSkill or not isValidChar() then task.wait(0.5) continue end
                    if State.Skill2 and isValidChar() then pcall(function() remote:FireServer(2, "tap", Vector3.new(0,0,0)) end) end
                    task.wait(0.15) if not State.AutoSkill or not isValidChar() then task.wait(0.5) continue end
                    if State.Skill3 and isValidChar() then pcall(function() remote:FireServer(3, "tap", Vector3.new(0,0,0)) end) end
                    task.wait(0.15) if not State.AutoSkill or not isValidChar() then task.wait(0.5) continue end
                    if State.Skill4 and isValidChar() then pcall(function() remote:FireServer(4, "tap", Vector3.new(0,0,0)) end) end
                    task.wait(0.15)
                end
                task.wait(0.6)
            end
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
                    local threshold = (State.PotionHealthPercent or 60) / 100
                    if hum and hum.Health>0 and (hum.Health/hum.MaxHealth) <= threshold then
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

local statsThread = nil
local statKeyMap = {
    ["Strength (STR)"] = "STR",
    ["Dexterity (DEX)"] = "DEX",
    ["Intelligence (INT)"] = "INT",
    ["Vitality (VIT)"] = "VIT"
}

local function setAutoStats(enabled)
    State.AutoStats = enabled
    if enabled then
        if statsThread then pcall(function() task.cancel(statsThread) end) end
        statsThread = task.spawn(function()
            while State.AutoStats and running do
                pcall(function()
                    local pd = Knit.Registry:Get("PlayerData")
                    local unspent = pd and pd.Data and (pd.Data.UnspentSkillPoints or pd.Data.SP or 0) or 0
                    if unspent > 0 then
                        local svc = Knit.GetService("StatService")
                        if svc then
                            if State.StatMode == "Game Recommended (Auto)" then
                                svc:AutoAllocate():await()
                            else
                                local key = statKeyMap[State.StatTarget] or "STR"
                                svc:AllocatePoints(key, unspent):await()
                            end
                        end
                    end
                end)
                task.wait(2)
            end
        end)
    else
        if statsThread then pcall(function() task.cancel(statsThread) end) statsThread = nil end
    end
end

local equipBestThread = nil
local function setAutoEquipBest(enabled)
    State.AutoEquipBest = enabled
    if enabled then
        if equipBestThread then pcall(function() task.cancel(equipBestThread) end) end
        equipBestThread = task.spawn(function()
            while State.AutoEquipBest and running do
                pcall(function()
                    local inv = require(LocalPlayer.PlayerScripts.Client.UI.Inventory)
                    if inv and type(inv.OnEquipBestClicked) == "function" then
                        inv.OnEquipBestClicked()
                    end
                end)
                task.wait(3)
            end
        end)
    else
        if equipBestThread then pcall(function() task.cancel(equipBestThread) end) equipBestThread = nil end
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
                if not State.AutoContinue and not State.AutoExtractEndless then return end
                task.wait(0.8)
                local curDepth = data and (data.ExtensionIndex or 0) + 1 or 1
                local shouldExtract = State.AutoExtractEndless and (curDepth >= (State.EndlessExtractDepth or 15))
                -- ถ้าเปิด AutoExtractEndless และถึงระดับ Depth ที่กำหนด ให้กด Extract (false)
                -- ถ้าไม่ใช่ ให้กด Continue (true)
                pcall(function() svc:SubmitEndlessChoice(not shouldExtract) end)
            end)
        end
        -- fallback ดัก Warning prompt ถ้า event ไม่มา
        if not continueConn then
            continueConn=task.spawn(function()
                while State.AutoContinue or State.AutoExtractEndless do
                    if (not running) then break end
                    local done=false
                    pcall(function()
                        for _,gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                            if gui:IsA("TextLabel") and gui.Visible and gui.Text:find("Checkpoint %d+ cleared!") then
                                local num = tonumber(gui.Text:match("Checkpoint (%d+) cleared!")) or 1
                                local shouldExtract = State.AutoExtractEndless and (num >= (State.EndlessExtractDepth or 15))
                                local svc2=Knit.GetService("DungeonRunService")
                                svc2:SubmitEndlessChoice(not shouldExtract)
                                done=true
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

    local ACTIVE_CODES = {
        "UPDATE1",
        "WEEKENDBUFFS",
        "15KCCU",
        "COURAGE",
        "LOVETHISGAME",
        "RAIDTIME",
        "FORGESKIP",
        "10KFAV",
        "8KLIKE",
        "FULLRELEASE",
        "LOOTRISBACK",
        "JACKPOT",
        "20KPLAYERS",
        "GIVEMEGEMSPLEASE",
        "LOOTR"
    }

    local function redeemAllCodes()
        local count = 0
        local successCount = 0
        pcall(function()
            local ks = Knit.GetService("CodesService")
            local remote = ks and ks.RF and ks.RF:FindFirstChild("RedeemCode")
            if not remote then
                remote = game:GetService("ReplicatedStorage").Packages._Index["sleitnick_knit@1.7.0"].knit.Services.CodesService.RF.RedeemCode
            end
            if remote then
                for _, code in ipairs(ACTIVE_CODES) do
                    local ok, res = pcall(function() return remote:InvokeServer(code) end)
                    count += 1
                    if ok and res == true then successCount += 1 end
                    task.wait(0.25)
                end
            end
        end)
        return successCount, count
    end

    -- =================================================================
    --   AUTO STAT UPGRADES
    -- =================================================================
    local STAT_NAME_MAP = {
        ["Strength (STR)"] = "STR",
        ["Dexterity (DEX)"] = "DEX",
        ["Intelligence (INT)"] = "INT",
        ["Vitality (VIT)"] = "VIT"
    }

    local function upgradeStatsNow()
        pcall(function()
            local statService = Knit.GetService("StatService")
            if not statService then return end

            local pd = Knit.Registry:Get("PlayerData")
            local statPoints = pd and pd.Data and (pd.Data.StatPoints or pd.Data.AvailableStatPoints or pd.Data.Points) or 0
            if statPoints <= 0 then return end

            if State.StatMode == "Game Recommended (Auto)" then
                if statService.AutoAllocate then
                    statService:AutoAllocate():await()
                end
            else
                local target = STAT_NAME_MAP[State.StatTarget] or "STR"
                if statService.AllocatePoints then
                    statService:AllocatePoints({ [target] = statPoints }):await()
                elseif statService.AllocatePoint then
                    for _ = 1, math.min(statPoints, 20) do
                        statService:AllocatePoint(target):await()
                        task.wait(0.05)
                    end
                end
            end
        end)
    end

    local autoStatsConn = nil
    local function setAutoStats(enabled)
        State.AutoStats = enabled
        if enabled then
            if autoStatsConn then pcall(function() task.cancel(autoStatsConn) end) end
            autoStatsConn = task.spawn(function()
                while State.AutoStats and running do
                    upgradeStatsNow()
                    task.wait(5)
                end
            end)
        else
            if autoStatsConn then pcall(function() task.cancel(autoStatsConn) end) autoStatsConn = nil end
        end
    end

    -- =================================================================
    --   AUTO SELL GEAR & AUTO CLAIM REWARDS & STREAMER MODE
    -- =================================================================
    local RARITY_RANK = {
        ["Common"] = 1,
        ["Uncommon"] = 2,
        ["Rare"] = 3,
        ["Epic"] = 4,
        ["Legendary"] = 5,
        ["Mythic"] = 6,
        ["Celestial"] = 7,
        ["Impossible"] = 8,
        ["Exotic"] = 9,
        ["Admin"] = 10,
        ["Owner"] = 11
    }

    local function sellGearNow()
        local maxRank = RARITY_RANK[State.SellMaxRarity] or 3
        local soldCount = 0
        pcall(function()
            local pd = Knit.Registry:Get("PlayerData")
            local eqInv = pd and pd.Data and pd.Data.EquipmentInventory
            if not eqInv then return end

            local guidsToSell = {}
            for _, item in pairs(eqInv) do
                if type(item) == "table" and item.GUID and not item.Locked and not item.Equipped then
                    local r = item.Rarity or "Common"
                    local rank = RARITY_RANK[r] or 1
                    if rank <= maxRank then
                        table.insert(guidsToSell, item.GUID)
                    end
                end
            end

            if #guidsToSell > 0 then
                soldCount = #guidsToSell
                local shopService = Knit.GetService("ShopService")
                if shopService and shopService.SellEquipment then
                    shopService:SellEquipment(guidsToSell):await()
                end
            end
        end)
        return soldCount
    end

    local autoSellConn = nil
    local function setAutoSellGear(enabled)
        State.AutoSellGear = enabled
        if enabled then
            if autoSellConn then pcall(function() task.cancel(autoSellConn) end) end
            autoSellConn = task.spawn(function()
                while State.AutoSellGear and running do
                    sellGearNow()
                    task.wait(6)
                end
            end)
        else
            if autoSellConn then pcall(function() task.cancel(autoSellConn) end) autoSellConn = nil end
        end
    end

    local function claimAllRewardsNow()
        local claimedAny = 0
        -- 1. Achievements ClaimAll
        pcall(function()
            local achService = Knit.GetService("AchievementService")
            if achService and achService.ClaimAll then
                local ok, res = pcall(function() return achService:ClaimAll():await() end)
                if ok and res then claimedAny += 1 end
            end
        end)

        -- 2. Quests (Daily & Weekly)
        pcall(function()
            local questService = Knit.GetService("QuestService")
            local pd = Knit.Registry:Get("PlayerData")
            local quests = pd and pd.Data and (pd.Data.Quests or pd.Data.QuestData)
            if quests and questService and questService.ClaimQuest then
                for groupName, groupData in pairs(quests) do
                    local activeList = groupData and groupData.Active
                    if type(activeList) == "table" then
                        for idx, q in ipairs(activeList) do
                            if q and q.Completed and not q.Claimed then
                                pcall(function()
                                    questService:ClaimQuest(groupName, idx):await()
                                    claimedAny += 1
                                end)
                                task.wait(0.2)
                            end
                        end
                    end
                end
            end
        end)

        -- 3. Battlepass Quests & Rewards
        pcall(function()
            local bpService = Knit.GetService("BattlepassService")
            local pd = Knit.Registry:Get("PlayerData")
            local bpData = pd and pd.Data and pd.Data.Battlepass
            if bpService and bpData then
                -- Quests
                if bpData.Quests and bpService.ClaimQuest then
                    for idx, q in pairs(bpData.Quests) do
                        if q and q.Completed and not q.Claimed then
                            pcall(function()
                                bpService:ClaimQuest(idx):await()
                                claimedAny += 1
                            end)
                            task.wait(0.2)
                        end
                    end
                end
                -- Tiers Free/Premium
                local curTier = bpData.Tier or 0
                local claimedFree = bpData.ClaimedFree or {}
                if bpService.ClaimReward then
                    for t = 1, curTier do
                        if not claimedFree[t] and not claimedFree[tostring(t)] then
                            pcall(function()
                                bpService:ClaimReward(t, "Free"):await()
                                claimedAny += 1
                            end)
                            task.wait(0.2)
                        end
                    end
                end
            end
        end)

        -- 4. Inventory Index Rewards
        pcall(function()
            local invService = Knit.GetService("InventoryService")
            if invService and invService.ClaimAllIndexRewards then
                pcall(function() invService:ClaimAllIndexRewards():await() end)
            end
        end)

        return claimedAny
    end

    -- =================================================================
    --   AUTO REROLL (Class Reroll / Spins)
    -- =================================================================
    local autoRerollThread = nil
    local spinStatusLabel = nil
    local slotInfoLabel = nil

    local function getSummoningService()
        local svc = nil
        pcall(function() svc = Knit.GetService("SummoningService") end)
        return svc
    end

    local function fetchSpinCounts()
        local normalSpins = 0
        local luckySpins = 0
        pcall(function()
            local svc = getSummoningService()
            if svc then
                local res = svc:GetSpinCounts()
                local data = (typeof(res) == "table" and res.await) and select(2, res:await()) or res
                if type(data) == "table" then
                    normalSpins = tonumber(data.Normal) or 0
                    luckySpins = tonumber(data.Lucky) or 0
                end
            end
        end)
        return normalSpins, luckySpins
    end

    local function fetchSlotData()
        local slots = {}
        local activeIdx = 1
        pcall(function()
            local svc = getSummoningService()
            if svc then
                local res = svc:GetSlotData()
                local data = (typeof(res) == "table" and res.await) and select(2, res:await()) or res
                if type(data) == "table" then
                    slots = data.Slots or {}
                    activeIdx = tonumber(data.ActiveIndex) or 1
                end
            end
        end)
        return slots, activeIdx
    end

    local function updateRerollLabels()
        local nSpins, lSpins = fetchSpinCounts()
        local slots, activeIdx = fetchSlotData()

        if spinStatusLabel and type(spinStatusLabel.Set) == "function" then
            pcall(function()
                spinStatusLabel:Set(string.format("Normal Spins: %d | Lucky Spins: %d", nSpins, lSpins))
            end)
        end

        if slotInfoLabel and type(slotInfoLabel.Set) == "function" then
            pcall(function()
                local targetSlot = tonumber(State.RerollTargetSlot) or 1
                local targetClass = slots[targetSlot] or "None"
                local activeTag = (targetSlot == activeIdx) and " (Active)" or ""
                slotInfoLabel:Set(string.format("Slot %d: [%s]%s", targetSlot, tostring(targetClass), activeTag))
            end)
        end
    end

    local function setAutoReroll(enabled)
        State.AutoReroll = enabled
        if enabled then
            if autoRerollThread then pcall(function() task.cancel(autoRerollThread) end) end
            autoRerollThread = task.spawn(function()
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "Auto Reroll",
                        Text = "เริ่มการ Auto Reroll...",
                        Duration = 3
                    })
                end)

                local svc = getSummoningService()
                if not svc then
                    warn("[Dungeon Lootr] SummoningService not found")
                    State.AutoReroll = false
                    return
                end

                -- 1. ตรวจสอบ Slot ก่อนเริ่มสุ่ม ถ้ายังไม่ได้เลือก Slot เป้าหมาย ให้สลับไปที่ Slot นั้นก่อน
                local targetSlot = tonumber(State.RerollTargetSlot) or 1
                local slots, activeIdx = fetchSlotData()
                if activeIdx ~= targetSlot then
                    pcall(function()
                        svc:SwitchSlot(targetSlot):await()
                    end)
                    task.wait(0.5)
                end

                updateRerollLabels()

                -- ตรวจสอบคลาสปัจจุบันใน Slot ถ้าตรงกับที่เลือกไว้แล้วให้หยุดทันที
                local currentClass = slots[targetSlot]
                local targetClassMap = {}
                for _, name in ipairs(State.RerollTargetClasses or {}) do
                    targetClassMap[name] = true
                end

                if currentClass and targetClassMap[currentClass] then
                    pcall(function()
                        StarterGui:SetCore("SendNotification", {
                            Title = "Auto Reroll",
                            Text = string.format("Slot %d มีคลาส %s อยู่แล้ว! หยุดทำงาน", targetSlot, currentClass),
                            Duration = 5
                        })
                    end)
                    State.AutoReroll = false
                    return
                end

                while State.AutoReroll and running do
                    -- ตรวจสอบจำนวนสปินที่เหลือ
                    local nSpins, lSpins = fetchSpinCounts()
                    local spinType = State.RerollSpinType or "Normal"
                    local available = (spinType == "Lucky") and lSpins or nSpins

                    if available <= 0 then
                        pcall(function()
                            StarterGui:SetCore("SendNotification", {
                                Title = "Auto Reroll",
                                Text = string.format("%s Spin หมดแล้ว! หยุดทำงาน", spinType),
                                Duration = 5
                            })
                        end)
                        State.AutoReroll = false
                        break
                    end

                    -- สุ่ม Spin
                    local ok, spinRes = pcall(function()
                        return svc:Spin(spinType, false):await()
                    end)

                    local newClass = nil
                    if ok and type(spinRes) == "table" then
                        newClass = spinRes.ClassName
                    end

                    -- ดึง Slot Data ล่าสุดเพื่อยืนยันชื่อคลาส
                    local updatedSlots = fetchSlotData()
                    local slotClass = updatedSlots[targetSlot] or newClass

                    updateRerollLabels()

                    -- ตรวจสอบเงื่อนไขการหยุด: ได้คลาสใดคลาสหนึ่งใน targetClassMap หรือไม่
                    if slotClass and targetClassMap[slotClass] then
                        pcall(function()
                            StarterGui:SetCore("SendNotification", {
                                Title = "Auto Reroll Success!",
                                Text = string.format("🎉 ได้รับ %s ใน Slot %d แล้ว! หยุดการสุ่ม", slotClass, targetSlot),
                                Duration = 8
                            })
                        end)
                        State.AutoReroll = false
                        break
                    end

                    task.wait(0.35)
                end
            end)
        else
            if autoRerollThread then
                pcall(function() task.cancel(autoRerollThread) end)
                autoRerollThread = nil
            end
        end
    end

    -- =================================================================
    --   AUTO DODGE (AoE & Boss Telegraphs) (v3.4.0)
    -- =================================================================
    local autoDodgeThread = nil
    local isDodgingNow = false
    local lastDodgeTick = 0
    local dodgeReturnCF = nil

    local function getDangerousAoEs()
        local list = {}
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return list end
        local myPos = hrp.Position

        -- 1. Scan Workspace.SpellTelegraphs
        local st = workspace:FindFirstChild("SpellTelegraphs")
        if st then
            for _, ch in ipairs(st:GetChildren()) do
                local pos = nil
                if ch:IsA("BasePart") then
                    pos = ch.Position
                elseif ch:IsA("Model") then
                    local p = ch.PrimaryPart or ch:FindFirstChildWhichIsA("BasePart", true)
                    if p then pos = p.Position end
                end
                if pos then
                    local dist = (pos - myPos).Magnitude
                    if dist <= (State.DodgeRadius or 24) then
                        table.insert(list, { source = "SpellTelegraph", name = ch.Name, pos = pos, dist = dist })
                    end
                end
            end
        end

        -- 2. Scan Workspace.Effects for danger instances
        local eff = workspace:FindFirstChild("Effects")
        local dangerousNames = {
            ["Telegraph_Root"] = true, ["AoE_Telegraph"] = true, ["Wide_Length_Telegraph"] = true,
            ["Light_Explosion"] = true, ["Fire_Pillar"] = true, ["Lightning_Crash"] = true,
            ["Gravity_Well"] = true, ["Arrow_Rain"] = true, ["Blackhole"] = true,
            ["GroundEffect"] = true, ["AD_Slash"] = true, ["Chains"] = true
        }
        if eff then
            for _, ch in ipairs(eff:GetChildren()) do
                if dangerousNames[ch.Name] or ch.Name:find("Telegraph") or ch.Name:find("Explod") then
                    local pos = nil
                    if ch:IsA("BasePart") then
                        pos = ch.Position
                    elseif ch:IsA("Model") then
                        local p = ch.PrimaryPart or ch:FindFirstChildWhichIsA("BasePart", true)
                        if p then pos = p.Position end
                    end
                    if pos then
                        local dist = (pos - myPos).Magnitude
                        if dist <= (State.DodgeRadius or 24) then
                            table.insert(list, { source = "Effect", name = ch.Name, pos = pos, dist = dist })
                        end
                    end
                end
            end
        end

        -- 3. Scan Workspace directly for spawned Telegraph / Placed effects
        for _, ch in ipairs(workspace:GetChildren()) do
            if dangerousNames[ch.Name] or ch.Name:find("Telegraph") then
                local pos = nil
                if ch:IsA("BasePart") then
                    pos = ch.Position
                elseif ch:IsA("Model") then
                    local p = ch.PrimaryPart or ch:FindFirstChildWhichIsA("BasePart", true)
                    if p then pos = p.Position end
                end
                if pos then
                    local dist = (pos - myPos).Magnitude
                    if dist <= (State.DodgeRadius or 24) then
                        table.insert(list, { source = "WorkspaceRoot", name = ch.Name, pos = pos, dist = dist })
                    end
                end
            end
        end

        return list
    end

    local function performDodge(dangerPos)
        if isDodgingNow then return end
        if tick() - lastDodgeTick < 0.65 then return end
        lastDodgeTick = tick()
        isDodgingNow = true

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then isDodgingNow = false return end

        dodgeReturnCF = hrp.CFrame

        -- คำนวณทิศทางการหลบหนีออกจากศูนย์กลางอันตราย
        local myPos = hrp.Position
        local awayDir = (myPos - dangerPos)
        awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)
        if awayDir.Magnitude < 0.5 then
            awayDir = hrp.CFrame.LookVector * -1
            awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)
        end
        if awayDir.Magnitude > 0 then
            awayDir = awayDir.Unit
        else
            awayDir = Vector3.new(0, 0, 1)
        end

        local mode = State.DodgeMode or "Dash & Evade"
        local duration = tonumber(State.DodgeDuration) or 1.4
        local dodgeDist = tonumber(State.DodgeDistance) or 32

        -- 1. เรียก Dash Remote ของเกมตามทิศทางหลบ
        pcall(function()
            local dash = getDashRemote()
            if dash then
                dash:FireServer(awayDir)
            end
        end)

        -- 2. เคลื่อนย้ายตำแหน่งฉุกเฉินและค้างไว้ในจุดปลอดภัย
        local safeCF = nil
        if mode == "Blink (Upwards)" then
            -- ยกตัวลอยขึ้นฟ้าเหนือวงอันตราย 32 studs (พ้นการระเบิดบนพื้น 100%)
            safeCF = hrp.CFrame + Vector3.new(0, dodgeDist, 0)
        elseif mode == "Blink (Backwards)" then
            -- ถอยหลังพ้นรัศมีวง 32 studs
            safeCF = hrp.CFrame + (awayDir * dodgeDist)
        else
            -- "Dash & Evade": ผสมผสาน Dash + วาร์ปพ้นรัศมีวง 32 studs พร้อมยกสูงขึ้น 6 studs
            safeCF = hrp.CFrame + (awayDir * dodgeDist) + Vector3.new(0, 6, 0)
        end

        if safeCF then
            pcall(function()
                hrp.CFrame = safeCF
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.Velocity = Vector3.new(0, 0, 0)
            end)
        end

        -- 3. ค้างตัวในตำแหน่งปลอดภัยตลอดช่วงสกิลระเบิด (Dodge Duration)
        local elapsed = 0
        while elapsed < duration and running do
            task.wait(0.1)
            elapsed += 0.1
            -- ค้างตำแหน่งให้มั่นคง ไม่ร่วงหรือโดนดูด
            if isValidChar() and safeCF then
                local h = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if h then
                    pcall(function()
                        h.CFrame = safeCF
                        h.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        h.Velocity = Vector3.new(0, 0, 0)
                    end)
                end
            end
        end

        -- 4. ตรวจสอบว่ายังมี AoE ตกค้างอยู่ไหม ถ้ายังมีอยู่ให้รอต่ออีกจนกว่าจะหมดไป (สูงสุดอีก 1.5 วินาที)
        local extraWait = 0
        while extraWait < 1.5 and running do
            local remainingDangers = getDangerousAoEs()
            if #remainingDangers == 0 then
                break
            end
            task.wait(0.2)
            extraWait += 0.2
            if isValidChar() and safeCF then
                local h = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if h then pcall(function() h.CFrame = safeCF end) end
            end
        end

        -- 5. เมื่อปลอดภัยสมบูรณ์แล้ว ให้คืนตำแหน่งกลับไปตีมอนสเตอร์ต่ออย่างราบรื่น
        if isValidChar() and dodgeReturnCF and State.AutoFarm then
            local h = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if h then
                pcall(function()
                    h.CFrame = dodgeReturnCF
                    h.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    h.Velocity = Vector3.new(0, 0, 0)
                end)
            end
        end

        isDodgingNow = false
    end

    local function setAutoDodge(enabled)
        State.AutoDodge = enabled
        if enabled then
            if autoDodgeThread then pcall(function() task.cancel(autoDodgeThread) end) end
            autoDodgeThread = task.spawn(function()
                while State.AutoDodge and running do
                    if isValidChar() and not isDodgingNow then
                        local dangers = getDangerousAoEs()
                        if #dangers > 0 then
                            -- มีอันตรายใกล้ตัว สั่งหลบทันที
                            performDodge(dangers[1].pos)
                        end
                    end
                    task.wait(0.08)
                end
            end)
        else
            if autoDodgeThread then
                pcall(function() task.cancel(autoDodgeThread) end)
                autoDodgeThread = nil
            end
            isDodgingNow = false
        end
    end

    local autoClaimConn = nil
    local function setAutoClaimRewards(enabled)
        State.AutoClaimRewards = enabled
        if enabled then
            if autoClaimConn then pcall(function() task.cancel(autoClaimConn) end) end
            autoClaimConn = task.spawn(function()
                while State.AutoClaimRewards and running do
                    claimAllRewardsNow()
                    task.wait(15)
                end
            end)
        else
            if autoClaimConn then pcall(function() task.cancel(autoClaimConn) end) autoClaimConn = nil end
        end
    end

    local streamerTask = nil
    local streamerDescConn = nil
    local function setStreamerMode(enabled)
        State.StreamerMode = enabled
        if enabled then
            local function anonymizeLabel(lbl)
                if not lbl:IsA("TextLabel") then return end
                local t = lbl.Text
                if t and (t:find(LocalPlayer.Name) or t:find(LocalPlayer.DisplayName)) then
                    lbl.Text = t:gsub(LocalPlayer.Name, "Anonymous"):gsub(LocalPlayer.DisplayName, "Anonymous")
                end
            end

            local function hideCharTags(char)
                if not char then return end
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("BillboardGui") then
                        d.Enabled = false
                    end
                end
            end

            hideCharTags(LocalPlayer.Character)

            -- ดักจับเฉพาะ Label ใหม่ที่ถูกเพิ่มเข้ามา แทนการสแกนทุกเฟรม
            local pgui = LocalPlayer:FindFirstChild("PlayerGui")
            if pgui and not streamerDescConn then
                streamerDescConn = pgui.DescendantAdded:Connect(function(d)
                    if State.StreamerMode and d:IsA("TextLabel") then
                        task.defer(function() anonymizeLabel(d) end)
                    end
                end)
            end

            -- รันตรวจสอบแค่ทุกๆ 1.5 วินาที เพื่อกิน CPU 0% ไม่กระตุกแน่นอน
            if streamerTask then pcall(function() task.cancel(streamerTask) end) end
            streamerTask = task.spawn(function()
                while State.StreamerMode and running do
                    pcall(function()
                        hideCharTags(LocalPlayer.Character)
                        local curPgui = LocalPlayer:FindFirstChild("PlayerGui")
                        if curPgui then
                            for _, lbl in ipairs(curPgui:GetDescendants()) do
                                if lbl:IsA("TextLabel") and lbl.Visible then
                                    anonymizeLabel(lbl)
                                end
                            end
                        end
                    end)
                    task.wait(1.5)
                end
            end)
        else
            if streamerTask then pcall(function() task.cancel(streamerTask) end) streamerTask = nil end
            if streamerDescConn then pcall(function() streamerDescConn:Disconnect() end) streamerDescConn = nil end
            pcall(function()
                local char = LocalPlayer.Character
                if char then
                    for _, d in ipairs(char:GetDescendants()) do
                        if d:IsA("BillboardGui") then d.Enabled = true end
                    end
                end
            end)
        end
    end

    -- =================================================================
    --   DISCORD WEBHOOK SYSTEM (Post-Dungeon Stats & Loot by Rarity)
    -- =================================================================
    local dungeonStartTime = os.time()
    local dungeonStartLoot = {}
    local dungeonStartMaterials = {}
    local lastDungeonReportTick = 0

    local function getHttpRequestFunc()
        if type(syn) == "table" and type(syn.request) == "function" then
            return syn.request
        elseif type(http) == "table" and type(http.request) == "function" then
            return http.request
        elseif type(http_request) == "function" then
            return http_request
        elseif type(request) == "function" then
            return request
        end
        return nil
    end

    local function snapshotLootBag()
        local snapshot = {}
        pcall(function()
            local pd = Knit.Registry:Get("PlayerData")
            local lootBag = pd and pd.Data and pd.Data.LootBag
            if type(lootBag) == "table" then
                for k, v in pairs(lootBag) do
                    if type(v) == "table" and v.GUID then
                        snapshot[v.GUID] = {
                            ItemId = v.ItemId or "Unknown",
                            Rarity = v.Rarity or "Common",
                            LevelReq = v.LevelReq or 0,
                            Slot = v.Slot or "Equipment"
                        }
                    end
                end
            end
        end)
        return snapshot
    end

    dungeonStartLoot = snapshotLootBag()

    local RARITY_EMOJIS = {
        ["Common"] = "⚪",
        ["Uncommon"] = "🟢",
        ["Rare"] = "🔵",
        ["Epic"] = "🟣",
        ["Legendary"] = "🟡",
        ["Mythic"] = "🔴",
        ["Celestial"] = "🌟",
        ["Impossible"] = "✨",
        ["Exotic"] = "🔮",
        ["Admin"] = "👑",
        ["Owner"] = "⚡"
    }

    local RARITY_ORDER = {
        "Owner", "Admin", "Exotic", "Impossible", "Celestial", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common"
    }

    local function sendDiscordWebhook(summaryData)
        local url = tostring(State.WebhookUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if url == "" or not (url:find("^https://discord%.com/api/webhooks/") or url:find("^https://discordapp%.com/api/webhooks/")) then
            return false, "Invalid or empty Webhook URL"
        end

        local req = getHttpRequestFunc()
        if not req then
            return false, "Executor does not support HTTP requests"
        end

        local isVictory = summaryData.isVictory == true
        local isDefeat = not isVictory
        if isVictory and not State.WebhookOnVictory then return false, "Victory webhook disabled" end
        if isDefeat and not State.WebhookOnDefeat then return false, "Defeat webhook disabled" end

        local embedColor = isVictory and 0x2ecc71 or 0xe74c3c
        local outcomeTitle = isVictory and "🏆 DUNGEON VICTORY (ชนะ)" or "💀 DUNGEON DEFEAT (แพ้)"

        -- Format Loot by Rarity
        local lootFields = {}
        local itemsByRarity = {}
        local totalLootCount = 0

        if type(summaryData.lootItems) == "table" then
            for _, item in ipairs(summaryData.lootItems) do
                local r = item.Rarity or "Common"
                if not itemsByRarity[r] then itemsByRarity[r] = {} end
                local name = tostring(item.DisplayName or item.ItemId or "Item")
                itemsByRarity[r][name] = (itemsByRarity[r][name] or 0) + 1
                totalLootCount += 1
            end
        end

        local lootDescriptionParts = {}
        for _, r in ipairs(RARITY_ORDER) do
            local items = itemsByRarity[r]
            if items and next(items) then
                local emoji = RARITY_EMOJIS[r] or "📦"
                local itemLines = {}
                for name, count in pairs(items) do
                    if count > 1 then
                        table.insert(itemLines, string.format("• **%s** x%d", name, count))
                    else
                        table.insert(itemLines, string.format("• **%s**", name))
                    end
                end
                table.insert(lootDescriptionParts, string.format("%s **%s**:\n%s", emoji, r, table.concat(itemLines, "\n")))
            end
        end

        -- Check any rarities not in RARITY_ORDER
        for r, items in pairs(itemsByRarity) do
            if not table.find(RARITY_ORDER, r) and items and next(items) then
                local itemLines = {}
                for name, count in pairs(items) do
                    table.insert(itemLines, string.format("• **%s** x%d", name, count))
                end
                table.insert(lootDescriptionParts, string.format("📦 **%s**:\n%s", r, table.concat(itemLines, "\n")))
            end
        end

        local lootText = (#lootDescriptionParts > 0) and table.concat(lootDescriptionParts, "\n\n") or "ไม่มีไอเทมใหม่ในรอบนี้"
        if #lootText > 1024 then
            lootText = lootText:sub(1, 1020) .. "..."
        end

        local durationStr = string.format("%dm %02ds", math.floor(summaryData.duration / 60), summaryData.duration % 60)

        local fields = {
            {
                name = "📊 ผลการลงดัน (Outcome)",
                value = outcomeTitle,
                inline = true
            },
            {
                name = "⏱️ ระยะเวลาที่ใช้ (Time Taken)",
                value = durationStr,
                inline = true
            },
            {
                name = "🗺️ ดันเจี้ยน (Dungeon)",
                value = string.format("%s (%s)", tostring(summaryData.dungeonName or "Unknown"), tostring(summaryData.difficulty or "Normal")),
                inline = true
            }
        }

        if summaryData.mobsKilled and summaryData.mobsKilled > 0 then
            table.insert(fields, {
                name = "⚔️ กำจัดมอนสเตอร์ (Mobs Killed)",
                value = tostring(summaryData.mobsKilled),
                inline = true
            })
        end

        if summaryData.starsEarned and summaryData.starsEarned > 0 then
            table.insert(fields, {
                name = "⭐ ดาวที่ได้รับ (Stars)",
                value = tostring(summaryData.starsEarned),
                inline = true
            })
        end

        table.insert(fields, {
            name = string.format("🎒 ไอเทมที่ได้รับ (%d ชิ้น แยกตามระดับแรร์)", totalLootCount),
            value = lootText,
            inline = false
        })

        local payload = {
            username = "RAVEN HUB | Dungeon Lootr",
            avatar_url = "https://i.imgur.com/8QfXk9R.png",
            embeds = {
                {
                    title = string.format("Dungeon Summary - %s", tostring(summaryData.dungeonName or "Dungeon")),
                    description = string.format("รายงานสรุปผลการลงดันเจี้ยนของ `%s`", LocalPlayer.Name),
                    color = embedColor,
                    fields = fields,
                    footer = {
                        text = string.format("RAVEN HUB v3.5.0 • %s", os.date("%Y-%m-%d %H:%M:%S"))
                    }
                }
            }
        }

        local jsonBody = game:GetService("HttpService"):JSONEncode(payload)
        local success, res = pcall(function()
            return req({
                Url = url,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = jsonBody
            })
        end)

        return success, res
    end

    local function triggerPostDungeonWebhook(completionInfo)
        if not State.WebhookEnabled then return end
        if tick() - lastDungeonReportTick < 8 then return end
        lastDungeonReportTick = tick()

        local duration = math.max(1, os.time() - dungeonStartTime)
        local status = completionInfo and completionInfo.Status or "Completed"
        local isVictory = status ~= "Failed" and status ~= "Defeat"
        local dungeonName = completionInfo and completionInfo.DungeonName or "Dungeon"
        local difficulty = completionInfo and completionInfo.Difficulty or "Normal"
        local mobsKilled = completionInfo and (completionInfo.MobsKilled or completionInfo.TotalMobsKilled) or 0

        -- Collect newly acquired loot from LootBag
        local currentLoot = snapshotLootBag()
        local newItems = {}
        for guid, item in pairs(currentLoot) do
            if not dungeonStartLoot[guid] then
                -- Lookup DisplayName if EquipmentTemplates is available
                local displayName = item.ItemId
                pcall(function()
                    local eqMod = ReplicatedStorage:FindFirstChild("GameInfo") and ReplicatedStorage.GameInfo:FindFirstChild("EquipmentTemplates")
                    if eqMod then
                        local eqTemplates = require(eqMod)
                        if eqTemplates and eqTemplates.GetTemplate then
                            local t = eqTemplates.GetTemplate(item.ItemId)
                            if t and t.DisplayName then
                                displayName = t.DisplayName
                            end
                        end
                    end
                end)
                table.insert(newItems, {
                    ItemId = item.ItemId,
                    DisplayName = displayName,
                    Rarity = item.Rarity or "Common",
                    LevelReq = item.LevelReq or 0
                })
            end
        end

        -- Check Stars Earned from HUD or PlayerData
        local starsEarned = 0
        pcall(function()
            local pgui = LocalPlayer:FindFirstChild("PlayerGui")
            local comp = pgui and pgui:FindFirstChild("Main", true) and pgui.Main:FindFirstChild("HUD", true) and pgui.Main.HUD:FindFirstChild("Dungeon_Container", true) and pgui.Main.HUD.Dungeon_Container:FindFirstChild("Completion_Info", true)
            if comp and comp.Visible then
                local rew = comp:FindFirstChild("Rewards", true) or comp:FindFirstChild("Content", true)
                if rew then
                    for _, d in ipairs(rew:GetDescendants()) do
                        if d:IsA("TextLabel") and d.Name == "Amount" and d.Parent and d.Parent:FindFirstChild("ItemName") and d.Parent.ItemName.Text:find("Star") then
                            local s = d.Text:match("%d+")
                            if s then starsEarned = tonumber(s) or 0 end
                        end
                    end
                end
            end
        end)

        task.spawn(function()
            sendDiscordWebhook({
                isVictory = isVictory,
                duration = duration,
                dungeonName = dungeonName,
                difficulty = difficulty,
                mobsKilled = mobsKilled,
                starsEarned = starsEarned,
                lootItems = newItems
            })
        end)

        -- Reset snapshot for subsequent run
        dungeonStartTime = os.time()
        dungeonStartLoot = currentLoot
    end

    -- Hook DungeonRunService & DungeonService completion events
    task.spawn(function()
        pcall(function()
            local drService = Knit.GetService("DungeonRunService")
            if drService and drService.DungeonComplete then
                drService.DungeonComplete:Connect(function(data)
                    triggerPostDungeonWebhook(data)
                end)
            end
        end)
        pcall(function()
            local dService = Knit.GetService("DungeonService")
            if dService and dService.DungeonComplete then
                dService.DungeonComplete:Connect(function(data)
                    triggerPostDungeonWebhook(data)
                end)
            end
        end)
    end)

    -- Fallback HUD completion watcher (in case of Challenge / Raid or missed signals)
    task.spawn(function()
        local wasCompVisible = false
        while running do
            pcall(function()
                local pgui = LocalPlayer:FindFirstChild("PlayerGui")
                local comp = pgui and pgui:FindFirstChild("Main", true) and pgui.Main:FindFirstChild("HUD", true) and pgui.Main.HUD:FindFirstChild("Dungeon_Container", true) and pgui.Main.HUD.Dungeon_Container:FindFirstChild("Completion_Info", true)
                if comp and comp.Visible and not wasCompVisible then
                    wasCompVisible = true
                    -- Extract dungeon info from UI labels
                    local dName = "Dungeon"
                    local diff = "Normal"
                    local mobs = 0
                    local status = "Completed"
                    pcall(function()
                        local title = comp:FindFirstChild("Header", true) and comp.Header:FindFirstChild("Title", true)
                        if title and title.Text then
                            if title.Text:upper():find("FAILED") or title.Text:upper():find("DEFEAT") then
                                status = "Failed"
                            end
                        end
                        local lvl = comp:FindFirstChild("Level", true)
                        if lvl then
                            local lt = lvl:FindFirstChild("Title")
                            if lt and lt.Text then dName = lt.Text end
                            local ld = lvl:FindFirstChild("Difficulty", true) and lvl.Difficulty:FindFirstChild("Dificulty", true)
                            if ld and ld.Text then diff = ld.Text end
                        end
                        local stats = comp:FindFirstChild("Stats", true)
                        if stats then
                            local mk = stats:FindFirstChild("Stat_MobsKilled", true) and stats.Stat_MobsKilled:FindFirstChild("StatValue", true)
                            if mk and mk.Text then mobs = tonumber(mk.Text) or 0 end
                        end
                    end)

                    triggerPostDungeonWebhook({
                        Status = status,
                        DungeonName = dName,
                        Difficulty = diff,
                        MobsKilled = mobs
                    })
                elseif comp and not comp.Visible then
                    wasCompVisible = false
                end
            end)
            task.wait(1.5)
        end
    end)

    local CoreGui = game:GetService("CoreGui")
    local function getEspContainer()
        local container = nil
        pcall(function()
            local root = (type(gethui) == "function" and gethui()) or CoreGui
            container = root:FindFirstChild("RavenDungeonLootrESP")
            if not container or not container.Parent then
                container = Instance.new("ScreenGui")
                container.Name = "RavenDungeonLootrESP"
                container.ResetOnSpawn = false
                container.Parent = root
            end
        end)
        if not container or not container.Parent then
            pcall(function()
                local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui") or CoreGui
                container = pgui:FindFirstChild("RavenDungeonLootrESP")
                if not container or not container.Parent then
                    container = Instance.new("ScreenGui")
                    container.Name = "RavenDungeonLootrESP"
                    container.ResetOnSpawn = false
                    container.Parent = pgui
                end
            end)
        end
        return container
    end

    local activeEspObjects = {}

    local function clearEsp(category)
        for obj, data in pairs(activeEspObjects) do
            if not category or data.category == category then
                if data.highlight then pcall(function() data.highlight:Destroy() end) end
                if data.billboard then pcall(function() data.billboard:Destroy() end) end
                activeEspObjects[obj] = nil
            end
        end
    end

    local function createEsp(object, category, title, color, getDynamicText)
        if activeEspObjects[object] or not object.Parent then return end
        local adornee = object:IsA("Model") and object or object:FindFirstAncestorOfClass("Model") or object
        local part = object:IsA("BasePart") and object
            or (object:IsA("Model") and (object.PrimaryPart or getHRP(object) or object:FindFirstChildWhichIsA("BasePart", true)))
        if not part and object:IsA("Model") then
            -- Fallback: check attachments if parts are streaming
            local att = object:FindFirstChildWhichIsA("Attachment", true)
            if att and att.Parent and att.Parent:IsA("BasePart") then
                part = att.Parent
            end
        end
        if not part then return end

        local container = getEspContainer()
        if not container then return end

        local highlight = Instance.new("Highlight")
        highlight.Adornee = adornee
        highlight.FillColor = color
        highlight.FillTransparency = 0.75
        highlight.OutlineColor = color
        highlight.OutlineTransparency = 0.2
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        pcall(function() highlight.Parent = container end)

        local billboard = Instance.new("BillboardGui")
        billboard.Adornee = part
        billboard.Size = UDim2.fromOffset(200, 36)
        billboard.StudsOffset = Vector3.new(0, 3.5, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 1500
        billboard.LightInfluence = 0
        pcall(function() billboard.Parent = container end)

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextColor3 = color
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextStrokeTransparency = 0.2
        label.Text = title
        label.Parent = billboard

        activeEspObjects[object] = {
            category = category,
            highlight = highlight,
            billboard = billboard,
            label = label,
            part = part,
            getDynamicText = getDynamicText
        }
    end

    local espThread = nil
    local function updateEspLoop()
        while (State.MobESP or State.ChestESP) and running do
            local char = LocalPlayer.Character
            local myHrp = char and char:FindFirstChild("HumanoidRootPart")
            local myPos = myHrp and myHrp.Position or Vector3.zero

            -- Clean up deleted or dead objects
            for obj, data in pairs(activeEspObjects) do
                local alive = false
                if obj and obj.Parent then
                    if data.category == "mob" then
                        local hum = obj:FindFirstChildOfClass("Humanoid")
                        local hp = hum and hum.Health or obj:GetAttribute("HealthOverride")
                        if (hp and hp > 0) or (hp == nil and obj:GetAttribute("IsFodder") == true) then
                            alive = true
                        end
                    elseif data.category == "chest" then
                        -- Chest is alive if model exists and has prompt or hasn't been collected
                        local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                        if prompt and prompt.Parent then
                            alive = true
                        end
                    end
                end

                if not alive then
                    if data.highlight then pcall(function() data.highlight:Destroy() end) end
                    if data.billboard then pcall(function() data.billboard:Destroy() end) end
                    activeEspObjects[obj] = nil
                else
                    if data.getDynamicText and data.label and data.part then
                        local dist = math.floor((data.part.Position - myPos).Magnitude)
                        pcall(function()
                            data.label.Text = data.getDynamicText(obj, dist)
                        end)
                    end
                end
            end

            -- Scan for Mobs if enabled
            if State.MobESP then
                local monsters = getMonsters()
                for _, m in ipairs(monsters) do
                    if not activeEspObjects[m] then
                        local isBoss = m:GetAttribute("IsBoss") == true or m:GetAttribute("IsMapBoss") == true or m:GetAttribute("BossType") ~= nil
                        local color = isBoss and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(255, 140, 40)
                        local prefix = isBoss and "[BOSS] " or "[MOB] "
                        createEsp(m, "mob", prefix .. m.Name, color, function(model, dist)
                            local hum = model:FindFirstChildOfClass("Humanoid")
                            local hp = hum and math.floor(hum.Health) or model:GetAttribute("HealthOverride") or "?"
                            local rIdx = model:GetAttribute("RoomIndex")
                            local roomStr = rIdx and (" (R" .. tostring(rIdx) .. ")") or ""
                            return string.format("%s%s%s [%s HP] [%dm]", prefix, model.Name, roomStr, tostring(hp), dist)
                        end)
                    end
                end
            else
                clearEsp("mob")
            end

            -- Scan for Chests if enabled
            if State.ChestESP then
                local gen = getGeneratedFolder()
                if gen then
                    for _, obj in ipairs(gen:GetChildren()) do
                        if obj:IsA("Model") and (obj.Name:find("DungeonChest") or obj:GetAttribute("DungeonChest") == true) then
                            local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                            if prompt and not activeEspObjects[obj] then
                                createEsp(obj, "chest", "[CHEST] " .. obj.Name, Color3.fromRGB(255, 215, 0), function(chestModel, dist)
                                    local rIdx = chestModel:GetAttribute("RoomIndex")
                                    local roomStr = rIdx and (" (R" .. tostring(rIdx) .. ")") or ""
                                    local hasLock = chestModel:FindFirstChild("Chest_Lock") ~= nil
                                    local statusStr = hasLock and " [🔒LOCKED]" or " [OPEN]"
                                    return string.format("[CHEST%s] %s%s [%dm]", statusStr, chestModel.Name, roomStr, dist)
                                end)
                            end
                        end
                    end
                end
            else
                clearEsp("chest")
            end

            task.wait(0.4)
        end
        clearEsp()
        espThread = nil
    end

    local function setMobESP(enabled)
        State.MobESP = enabled
        if enabled then
            if not espThread then espThread = task.spawn(updateEspLoop) end
        else
            clearEsp("mob")
        end
    end

    local function setChestESP(enabled)
        State.ChestESP = enabled
        if enabled then
            if not espThread then espThread = task.spawn(updateEspLoop) end
        else
            clearEsp("chest")
        end
    end

    -- =================================================================
    --   UI SETUP (MacLib Adapter)
    -- =================================================================
    local MainTab = Window:CreateTab("Main", "swords")
    local DungeonTab = Window:CreateTab("Dungeon", "map")
    local ESPTab = Window:CreateTab("ESP", "esp")
    local MiscTab = Window:CreateTab("Misc", "misc")

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

    -- Main Tab: Auto Dodge (v3.4.0)
    MainTab:CreateSection("Auto Dodge (หลบ AoE บอส)")
    MainTab:CreateToggle({
        Name = "Auto Dodge (หลบวงสกิล / การโจมตีอันตราย)",
        CurrentValue = State.AutoDodge,
        Flag = "DungeonLootrAutoDodge",
        Callback = function(v) setAutoDodge(v) end
    })
    MainTab:CreateDropdown({
        Name = "Dodge Mode (รูปแบบการหลบ)",
        Options = {"Dash & Evade", "Blink (Upwards)", "Blink (Backwards)"},
        CurrentOption = {State.DodgeMode},
        MultipleOptions = false,
        Flag = "DungeonLootrDodgeMode",
        Callback = function(v)
            State.DodgeMode = type(v) == "table" and v[1] or v
        end
    })
    MainTab:CreateSlider({
        Name = "Dodge Radius (ระยะตรวจจับวงอันตราย)",
        Range = {12, 45},
        Increment = 1,
        CurrentValue = State.DodgeRadius,
        Suffix = " studs",
        Flag = "DungeonLootrDodgeRadius",
        Callback = function(v)
            State.DodgeRadius = tonumber(v) or 24
        end
    })
    MainTab:CreateSlider({
        Name = "Dodge Duration (เวลารอให้สกิลจบ)",
        Range = {0.8, 3.5},
        Increment = 0.1,
        CurrentValue = State.DodgeDuration,
        Suffix = " s",
        Flag = "DungeonLootrDodgeDuration",
        Callback = function(v)
            State.DodgeDuration = tonumber(v) or 1.4
        end
    })
    MainTab:CreateSlider({
        Name = "Dodge Distance (ระยะกระโดดหลบ)",
        Range = {20, 60},
        Increment = 2,
        CurrentValue = State.DodgeDistance,
        Suffix = " studs",
        Flag = "DungeonLootrDodgeDistance",
        Callback = function(v)
            State.DodgeDistance = tonumber(v) or 32
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
        Name = "Auto Loot Dropped Chests",
        CurrentValue = State.AutoLootChests,
        Flag = "DungeonLootrAutoLootChests",
        Callback = function(v) State.AutoLootChests = v end
    })
    MainTab:CreateToggle({
        Name = "Auto Unlock Secret Rooms (เปิดห้องลับถ้ามีกุญแจ)",
        CurrentValue = State.AutoUnlockSecretRooms,
        Flag = "DungeonLootrAutoUnlockSecretRooms",
        Callback = function(v) State.AutoUnlockSecretRooms = v end
    })
    MainTab:CreateToggle({
        Name = "Auto Loot Secret Chests (เก็บกล่องห้องลับ)",
        CurrentValue = State.AutoLootSecretChests,
        Flag = "DungeonLootrAutoLootSecretChests",
        Callback = function(v) State.AutoLootSecretChests = v end
    })
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

    -- Main Tab: Blessing & Special Boss (v3.1.0)
    MainTab:CreateSection("Blessing & Special")
    MainTab:CreateToggle({
        Name = "Auto Blessing (รับบัฟแท่น Altar)",
        CurrentValue = State.AutoBlessing,
        Flag = "DungeonLootrAutoBlessing",
        Callback = function(v) setAutoBlessing(v) end
    })
    MainTab:CreateDropdown({
        Name = "Blessing Priority (สายบัฟที่เลือก)",
        Options = {"Damage (ATK)", "Defense / Health", "Speed / Haste"},
        CurrentOption = {State.BlessingPriority},
        MultipleOptions = false,
        Flag = "DungeonLootrBlessingPriority",
        Callback = function(v)
            State.BlessingPriority = type(v) == "table" and v[1] or v
        end
    })
    MainTab:CreateToggle({
        Name = "Auto Summon Special Boss (เสกบอสลับ 7x Platinum Key)",
        CurrentValue = State.AutoSummonSpecialBoss,
        Flag = "DungeonLootrAutoSummonSpecialBoss",
        Callback = function(v) State.AutoSummonSpecialBoss = v end
    })
    MainTab:CreateToggle({
        Name = "Auto Extract Endless (ถอนตัว Endless ปลอดภัย)",
        CurrentValue = State.AutoExtractEndless,
        Flag = "DungeonLootrAutoExtractEndless",
        Callback = function(v) State.AutoExtractEndless = v end
    })
    MainTab:CreateSlider({
        Name = "Endless Extract Depth (ถอนตัวที่ชั้น)",
        Range = {5, 50},
        Increment = 1,
        CurrentValue = State.EndlessExtractDepth,
        Suffix = " waves",
        Flag = "DungeonLootrEndlessExtractDepth",
        Callback = function(v) State.EndlessExtractDepth = tonumber(v) or 15 end
    })

    -- Main Tab: Potion
    MainTab:CreateSection("Potion")
    MainTab:CreateToggle({
        Name = "Auto Use Potion",
        CurrentValue = State.AutoPotion,
        Flag = "DungeonLootrAutoPotion",
        Callback = function(v) setAutoPotion(v) end
    })
    MainTab:CreateSlider({
        Name = "Heal At Health %",
        Range = {10, 95},
        Increment = 5,
        CurrentValue = State.PotionHealthPercent,
        Suffix = "%",
        Flag = "DungeonLootrPotionHealthPercent",
        Callback = function(v) State.PotionHealthPercent = tonumber(v) or 60 end
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

    -- Misc Tab: Auto stats & Auto Equip best
    MiscTab:CreateSection("Auto stats")
    MiscTab:CreateToggle({
        Name = "Auto Stat Upgrades",
        CurrentValue = State.AutoStats,
        Flag = "DungeonLootrAutoStats",
        Callback = function(v) setAutoStats(v) end
    })
    MiscTab:CreateDropdown({
        Name = "Upgrade Mode",
        Options = {"Game Recommended (Auto)", "Custom Specific Stat"},
        CurrentOption = {State.StatMode},
        MultipleOptions = false,
        Flag = "DungeonLootrStatMode",
        Callback = function(v)
            State.StatMode = type(v) == "table" and v[1] or v
        end
    })
    MiscTab:CreateDropdown({
        Name = "Select Specific Stat",
        Options = {"Strength (STR)", "Dexterity (DEX)", "Intelligence (INT)", "Vitality (VIT)"},
        CurrentOption = {State.StatTarget},
        MultipleOptions = false,
        Flag = "DungeonLootrStatTarget",
        Callback = function(v)
            State.StatTarget = type(v) == "table" and v[1] or v
        end
    })

    -- ESP Tab: Visuals
    ESPTab:CreateSection("ESP Visuals")
    ESPTab:CreateToggle({
        Name = "ESP Mob",
        CurrentValue = State.MobESP,
        Flag = "DungeonLootrMobESP",
        Callback = function(v) setMobESP(v) end
    })
    ESPTab:CreateToggle({
        Name = "ESP Chest (กล่อง)",
        CurrentValue = State.ChestESP,
        Flag = "DungeonLootrChestESP",
        Callback = function(v) setChestESP(v) end
    })

    MiscTab:CreateSection("Auto Equip best")
    MiscTab:CreateToggle({
        Name = "Auto Equip Best",
        CurrentValue = State.AutoEquipBest,
        Flag = "DungeonLootrAutoEquipBest",
        Callback = function(v) setAutoEquipBest(v) end
    })

    MiscTab:CreateSection("Auto Sell Gear")
    MiscTab:CreateToggle({
        Name = "Auto Sell Gear (ขายอุปกรณ์ขยะ)",
        CurrentValue = State.AutoSellGear,
        Flag = "DungeonLootrAutoSellGear",
        Callback = function(v) setAutoSellGear(v) end
    })
    MiscTab:CreateDropdown({
        Name = "Max Sell Rarity (ขายสูงสุดไม่เกินระดับ)",
        Options = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Celestial"},
        CurrentOption = {State.SellMaxRarity},
        MultipleOptions = false,
        Flag = "DungeonLootrSellMaxRarity",
        Callback = function(v)
            State.SellMaxRarity = type(v) == "table" and v[1] or v
        end
    })
    MiscTab:CreateButton({
        Name = "Sell Now (กดขายทันที 1 ครั้ง)",
        Callback = function()
            local count = sellGearNow()
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Auto Sell",
                    Text = string.format("ขายไอเทมสำเร็จ %d ชิ้น!", count),
                    Duration = 4
                })
            end)
        end
    })

    MiscTab:CreateSection("Auto Claim Rewards")
    MiscTab:CreateToggle({
        Name = "Auto Claim Rewards (รับเควสต์ / ความสำเร็จ)",
        CurrentValue = State.AutoClaimRewards,
        Flag = "DungeonLootrAutoClaimRewards",
        Callback = function(v) setAutoClaimRewards(v) end
    })
    MiscTab:CreateButton({
        Name = "Claim All Now (กดรับรางวัลทั้งหมดทันที)",
        Callback = function()
            local count = claimAllRewardsNow()
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Claim Rewards",
                    Text = string.format("กดรับรางวัลสำเร็จ %d รายการ!", count),
                    Duration = 4
                })
            end)
        end
    })

    -- =================================================================
    --   MISC TAB: AUTO REROLL (CLASS SPINS)
    -- =================================================================
    MiscTab:CreateSection("Auto Reroll (Class Spins)")

    spinStatusLabel = MiscTab:CreateLabel("Normal Spins: 0 | Lucky Spins: 0")
    slotInfoLabel = MiscTab:CreateLabel("Slot 1: [Loading...]")

    MiscTab:CreateToggle({
        Name = "Auto Reroll (สุ่มคลาสอัตโนมัติ)",
        CurrentValue = State.AutoReroll,
        Flag = "DungeonLootrAutoReroll",
        Callback = function(v) setAutoReroll(v) end
    })

    MiscTab:CreateDropdown({
        Name = "Spin Type (ประเภทการสุ่ม)",
        Options = {"Normal", "Lucky"},
        CurrentOption = {State.RerollSpinType},
        MultipleOptions = false,
        Flag = "DungeonLootrRerollSpinType",
        Callback = function(v)
            State.RerollSpinType = type(v) == "table" and v[1] or v
            updateRerollLabels()
        end
    })

    MiscTab:CreateDropdown({
        Name = "Target Slot (เลือก Slot ที่จะสุ่ม)",
        Options = {"Slot 1", "Slot 2", "Slot 3", "Slot 4"},
        CurrentOption = {"Slot " .. tostring(State.RerollTargetSlot)},
        MultipleOptions = false,
        Flag = "DungeonLootrRerollTargetSlot",
        Callback = function(v)
            local chosen = type(v) == "table" and v[1] or v
            local slotNum = tonumber(chosen:match("%d+")) or 1
            State.RerollTargetSlot = slotNum
            pcall(function()
                local svc = getSummoningService()
                if svc then svc:SwitchSlot(slotNum):await() end
            end)
            updateRerollLabels()
        end
    })

    local rerollClassList = {
        "Artemis", "Vacio", "Azure Devil", "Forge Archon", "Demonbane", "Streamline", "Unrestricted",
        "Wanderer", "Divergent", "Cursed Child", "Oathbreaker",
        "Shinobi", "Witch Gunner", "Archer", "Kage",
        "Assassin", "Flame Bastion", "Boxer",
        "Greatsword", "Bowman", "Ronin",
        "Sinister Trigger", "Dark Professor", "Cryomancer", "Awakened Devil EX", "Founder", "Cursed King", "Anti Magic", "Jetstream", "Shadow Vagrant", "Honored One", "Dreadlord", "Prisma", "Framebreaker", "Coyote", "Spell Breaker", "Mori"
    }

    MiscTab:CreateDropdown({
        Name = "Target Classes (เลือกคลาสที่ต้องการ - หยุดเมื่อได้)",
        Options = rerollClassList,
        CurrentOption = State.RerollTargetClasses,
        MultipleOptions = true,
        Flag = "DungeonLootrRerollTargetClasses",
        Callback = function(v)
            State.RerollTargetClasses = type(v) == "table" and v or {v}
        end
    })

    MiscTab:CreateButton({
        Name = "Refresh Spin & Slot Info (รีเฟรชข้อมูลคลาส)",
        Callback = function()
            updateRerollLabels()
            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title = "Auto Reroll",
                    Text = "อัปเดตข้อมูล Spin และ Slot สำเร็จ!",
                    Duration = 3
                })
            end)
        end
    })

    -- เรียกอัปเดตข้อมูลตั้งต้น
    task.defer(function()
        task.wait(1)
        updateRerollLabels()
    end)

    MiscTab:CreateSection("Streamer Mode")
    MiscTab:CreateToggle({
        Name = "Streamer Mode (ซ่อนชื่อ / ป้องกันการแบน)",
        CurrentValue = State.StreamerMode,
        Flag = "DungeonLootrStreamerMode",
        Callback = function(v) setStreamerMode(v) end
    })

    MiscTab:CreateSection("Game Codes")
    MiscTab:CreateButton({
        Name = "Redeem All Active Codes (แลกโค้ดทั้งหมด)",
        Callback = function()
            task.spawn(function()
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "Dungeon Lootr Codes",
                        Text = "กำลังแลกโค้ดทั้งหมด...",
                        Duration = 3
                    })
                end)
                local successCount, total = redeemAllCodes()
                pcall(function()
                    StarterGui:SetCore("SendNotification", {
                        Title = "Dungeon Lootr Codes",
                        Text = string.format("แลกสำเร็จ %d / %d โค้ด!", successCount, total),
                        Duration = 5
                    })
                end)
            end)
        end
    })

    -- =================================================================
    --   SETTINGS TAB (Webhook Controls)
    -- =================================================================
    local SettingsTab = (scriptInfo and scriptInfo.hubSettingsTab)
    if not SettingsTab and Window and type(Window.GetTab) == "function" then
        SettingsTab = Window:GetTab("Settings")
    end
    if not SettingsTab and Window and type(Window.CreateTab) == "function" then
        SettingsTab = Window:CreateTab("Settings", "settings")
    end

    if SettingsTab then
        SettingsTab:CreateSection("Discord Webhook (แจ้งเตือนหลังจบดัน)")

        SettingsTab:CreateInput({
            Name = "Webhook URL",
            CurrentValue = State.WebhookUrl,
            PlaceholderText = "https://discord.com/api/webhooks/...",
            Flag = "DungeonLootrWebhookUrl",
            Callback = function(v)
                State.WebhookUrl = tostring(v or "")
            end
        })

        SettingsTab:CreateToggle({
            Name = "Enable Webhook (เปิดแจ้งเตือน Discord)",
            CurrentValue = State.WebhookEnabled,
            Flag = "DungeonLootrWebhookEnabled",
            Callback = function(v)
                State.WebhookEnabled = v
            end
        })

        SettingsTab:CreateToggle({
            Name = "Send on Victory (ส่งเมื่อชนะ / ชนะบอส)",
            CurrentValue = State.WebhookOnVictory,
            Flag = "DungeonLootrWebhookOnVictory",
            Callback = function(v)
                State.WebhookOnVictory = v
            end
        })

        SettingsTab:CreateToggle({
            Name = "Send on Defeat (ส่งเมื่อแพ้)",
            CurrentValue = State.WebhookOnDefeat,
            Flag = "DungeonLootrWebhookOnDefeat",
            Callback = function(v)
                State.WebhookOnDefeat = v
            end
        })

        SettingsTab:CreateButton({
            Name = "Test Webhook (ทดสอบส่งข้อความ)",
            Callback = function()
                task.spawn(function()
                    pcall(function()
                        StarterGui:SetCore("SendNotification", {
                            Title = "Discord Webhook",
                            Text = "กำลังส่งข้อความทดสอบ...",
                            Duration = 3
                        })
                    end)

                    local ok, err = sendDiscordWebhook({
                        isVictory = true,
                        duration = 142,
                        dungeonName = "Bandits Den (Test)",
                        difficulty = "Easy",
                        mobsKilled = 48,
                        starsEarned = 15,
                        lootItems = {
                            { ItemId = "RunicPlate", DisplayName = "Runic Plate", Rarity = "Legendary" },
                            { ItemId = "GlacialPlate", DisplayName = "Glacial Plate", Rarity = "Epic" },
                            { ItemId = "IronSword", DisplayName = "Iron Sword", Rarity = "Common" }
                        }
                    })

                    pcall(function()
                        if ok then
                            StarterGui:SetCore("SendNotification", {
                                Title = "Discord Webhook",
                                Text = "ส่งข้อความสำเร็จ! ตรวจสอบที่ Discord",
                                Duration = 5
                            })
                        else
                            StarterGui:SetCore("SendNotification", {
                                Title = "Discord Webhook Error",
                                Text = "เกิดข้อผิดพลาด: " .. tostring(err or "Failed"),
                                Duration = 6
                            })
                        end
                    end)
                end)
            end
        })
    end

    local function applyTabOrder()
        local desired = {"Overview", "Main", "Dungeon", "ESP", "Misc", "Settings"}
        pcall(function()
            local root = type(gethui) == "function" and gethui() or game:GetService("CoreGui")
            for _, child in ipairs(root:GetChildren()) do
                if child:IsA("ScreenGui") and (child.Name == "RavenMacLib" or child:FindFirstChild("Base")) then
                    for _, desc in ipairs(child:GetDescendants()) do
                        if desc:IsA("TextLabel") and desc.Name == "TabSwitcherName" then
                            local btn = desc.Parent
                            local txt = desc.Text
                            for idx, name in ipairs(desired) do
                                if txt == name or txt:lower() == name:lower() then
                                    btn.LayoutOrder = idx
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end)
        if Window and type(Window.SortTabs) == "function" then
            pcall(function() Window:SortTabs(desired) end)
        end
    end
    applyTabOrder()
    task.defer(applyTabOrder)
    task.spawn(function()
        for i = 1, 10 do
            task.wait(0.3)
            applyTabOrder()
        end
    end)

    -- =================================================================
    --   LIFECYCLE & CLEANUP
    -- =================================================================
    local charAddedConn = nil
    charAddedConn = LocalPlayer.CharacterAdded:Connect(function(newChar)
        if not running then return end
        stopLock()
        stopHover()
        task.defer(function()
            newChar:WaitForChild("HumanoidRootPart", 5)
            newChar:WaitForChild("Humanoid", 5)
        end)
    end)

    local function stopAll()
        running = false
        if charAddedConn then pcall(function() charAddedConn:Disconnect() end) charAddedConn = nil end
        State.AutoFarm = false
        State.AutoSkill = false
        State.AutoCreateDungeon = false
        State.AutoBestDungeon = false
        State.AutoCreateChallenger = false
        State.AutoCreateBossRush = false
        State.AutoEquipBest = false
        State.MobESP = false
        State.ChestESP = false
        setMobESP(false)
        setChestESP(false)
        clearEsp()
        if espFolder then pcall(function() espFolder:Destroy() end) end
        stopFarm()
        stopSkill()
        setSkipChest(false)
        setAutoContinue(false)
        setAutoReplay(false)
        setAutoReturn(false)
        setAutoPotion(false)
        setAutoStats(false)
        setAutoEquipBest(false)
        setAutoBest(false)
        setAutoCreateChallenger(false)
        setAutoCreateBossRush(false)
        setAutoBlessing(false)
        setAutoSellGear(false)
        setAutoClaimRewards(false)
        setAutoReroll(false)
        setAutoDodge(false)
        setStreamerMode(false)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(stopAll)
    end

    return {
        Destroy = stopAll
    }
end
