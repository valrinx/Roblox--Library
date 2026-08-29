-- ═══════════════════════════════════════════════════════════════════
-- Dungeon Quest Reborn | Rayfield UI | v3.0 Complete
-- Live-verified remotes + GUI paths from Raven MCP inspection
-- ═══════════════════════════════════════════════════════════════════

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local TP = game:GetService("TeleportService")
local VU = game:GetService("VirtualUser")
local LP = Players.LocalPlayer
local PG = LP.PlayerGui

-- ═══════════════════════════════════════════════════════════════════
-- SETTINGS
-- ═══════════════════════════════════════════════════════════════════
local S = {
    KillAura = false, KillAuraRange = 15,
    AutoSkill = false, AutoSkillRange = 30,
    AutoFarm = false, FarmRange = 50,
    MonsterESP = false,
    AutoStartDungeon = false, AutoReadyUp = false, AutoReplay = false,
    AutoSell = false, AutoSellRarity = "All",
    AutoEquipBest = false,
    AutoUpgrade = false, UpgradePriority = "Physical",
    AutoSpendSP = false, SpendSPPriority = "Physical",
    NoClip = false, InfiniteJump = false, UseSpeed = false,
    WalkSpeed = 16,
    AntiAFK = false,
    FPSBoost = false,
    LeaveAtWave = 0,
    SelectedDungeon = "Desert Temple",
    SelectedDifficulty = "Easy",
}

local Conn = {}
local Flags = {
    inDungeon = false, attacking = false, lastAttack = 0,
    lastSkill = {}, dodgeCooldown = 0,
}

-- ═══════════════════════════════════════════════════════════════════
-- CORE UTILITIES
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

local function randDelay(base, jit)
    jit = jit or 0.15
    return base * (1 + (math.random() * 2 - 1) * jit)
end

local function getVal(name)
    local v = LP:FindFirstChild(name)
    return v and v.Value
end

local function getRem(name, className)
    local rem = RS:FindFirstChild("remotes")
    if rem then
        local r = rem:FindFirstChild(name)
        if r and (not className or r:IsA(className)) then return r end
    end
    return nil
end

local function fire(name, ...)
    local args = {...}
    local r = getRem(name, "RemoteEvent")
    if r then pcall(function() r:FireServer(unpack(args)) end) end
end

local function invoke(name, ...)
    local args = {...}
    local r = getRem(name, "RemoteFunction")
    if r then
        local ok, res = pcall(function() return r:InvokeServer(unpack(args)) end)
        return ok and res or nil
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════
-- ENEMY SCANNING
-- ═══════════════════════════════════════════════════════════════════

local function getEnemies()
    local list = {}
    local dun = workspace:FindFirstChild("dungeon")
    if not dun then return list end
    for _, room in ipairs(dun:GetChildren()) do
        local ef = room:FindFirstChild("enemyFolder")
        if ef then
            for _, e in ipairs(ef:GetChildren()) do
                local hrp = e:FindFirstChild("HumanoidRootPart") or e:FindFirstChild("Torso")
                local hum = e:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    table.insert(list, {
                        model = e, root = hrp, hum = hum,
                        hp = hum.Health, maxHp = hum.MaxHealth, pos = hrp.Position,
                    })
                end
            end
        end
    end
    return list
end

local function getClosest(maxR)
    local my = getRoot()
    if not my then return nil, math.huge end
    local c, d = nil, maxR or math.huge
    for _, e in ipairs(getEnemies()) do
        local dist = (e.root.Position - my.Position).Magnitude
        if dist < d then c, d = e, dist end
    end
    return c, d
end

local function getInRange(maxR)
    local my = getRoot()
    if not my then return {} end
    local r = {}
    for _, e in ipairs(getEnemies()) do
        if (e.root.Position - my.Position).Magnitude <= maxR then
            table.insert(r, e)
        end
    end
    return r
end

local function getAlive()
    local r = {}
    for _, e in ipairs(getEnemies()) do
        if e.hp > 0 then table.insert(r, e) end
    end
    return r
end

local function getRoomPriority()
    local dun = workspace:FindFirstChild("dungeon")
    if not dun then return {} end
    local rooms = {}
    for _, room in ipairs(dun:GetChildren()) do
        local ef = room:FindFirstChild("enemyFolder")
        if ef then
            local cnt, hp = 0, 0
            for _, e in ipairs(ef:GetChildren()) do
                local h = e:FindFirstChildOfClass("Humanoid")
                if h and h.Health > 0 then cnt = cnt + 1; hp = hp + h.Health end
            end
            if cnt > 0 then table.insert(rooms, {name = room.Name, count = cnt, totalHp = hp}) end
        end
    end
    table.sort(rooms, function(a, b) return a.count > b.count end)
    return rooms
end

-- ═══════════════════════════════════════════════════════════════════
-- DUNGEON STATE
-- ═══════════════════════════════════════════════════════════════════

local function isInDungeon()
    return workspace:FindFirstChild("dungeon") ~= nil
end

local function getCurrentWave()
    local ds = PG:FindFirstChild("dungeonStatsGui")
    if ds then
        local wave = ds:FindFirstChild("wave")
        if wave and wave:IsA("TextLabel") then
            local n = wave.Text:match("WAVE (%d+)")
            return tonumber(n) or 0
        end
    end
    return 0
end

-- ═══════════════════════════════════════════════════════════════════
-- WEAPON & SKILL HELPERS
-- ═══════════════════════════════════════════════════════════════════

local function getWeaponSwing()
    local c = LP.Character
    if not c then return nil end
    for _, v in ipairs(c:GetChildren()) do
        if v:IsA("Accessory") then
            local sw = v:FindFirstChild("swing")
            if sw and sw:IsA("RemoteEvent") then return sw, v end
        end
    end
    return nil
end

local function getSkills()
    local skills = {}
    local bp = LP:FindFirstChild("Backpack")
    local c = LP.Character
    for _, cont in ipairs({bp, c}) do
        if cont then
            for _, t in ipairs(cont:GetChildren()) do
                if t:IsA("Tool") then
                    local spell = t:FindFirstChild("spellEvent")
                    if spell and spell:IsA("RemoteEvent") then
                        local cd = t:FindFirstChild("cooldown")
                        table.insert(skills, {
                            tool = t, remote = spell,
                            cooldown = cd,
                            cdVal = cd and cd.Value or 0,
                            name = t.Name,
                        })
                    end
                end
            end
        end
    end
    return skills
end

local function isSkillReady(s)
    if s.cooldown then return s.cooldown.Value <= 0 end
    return true
end

local function equipTool(tool)
    local bp = LP:FindFirstChild("Backpack")
    if bp and tool and tool.Parent == bp then
        tool.Parent = LP.Character or LP
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- TELEGRAPH DETECTION + DODGE (Ouroboros pattern)
-- ═══════════════════════════════════════════════════════════════════

local function isAttackTelegraph(m)
    if not m then return false end
    local names = {"telegraph","warning","danger","attack","aoe","marker","indicator","precast","circleprecast"}
    for _, d in ipairs(m:GetDescendants()) do
        local nl = string.lower(d.Name)
        for _, tn in ipairs(names) do
            if string.find(nl, tn) and d:IsA("BasePart") and d.Transparency < 0.8 then
                return true
            end
        end
        if d:IsA("BasePart") and d.Transparency < 0.8 then
            local r, g, b = d.Color.R, d.Color.G, d.Color.B
            if (r > 0.7 and g < 0.4 and b < 0.4) or (r > 0.8 and g > 0.3 and g < 0.6 and b < 0.3) then
                return true
            end
        end
    end
    return false
end

local function dodgeAway(m, dist)
    local my = getRoot()
    if not my or not m then return end
    local er = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
    if not er then return end
    local dir = (my.Position - er.Position).Unit
    my.CFrame = CFrame.new(my.Position + dir * (dist or 20), my.Position + dir * (dist or 20) + dir)
end

-- ═══════════════════════════════════════════════════════════════════
-- TELEPORT UTILITY
-- ═══════════════════════════════════════════════════════════════════

local function teleportTo(pos)
    local my = getRoot()
    if not my then return end
    my.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
end

local function faceTarget(targetPos)
    local my = getRoot()
    if not my then return end
    local dir = (targetPos - my.Position)
    local flat = Vector3.new(dir.X, 0, dir.Z)
    if flat.Magnitude > 0.1 then
        my.CFrame = CFrame.new(my.Position, my.Position + flat.Unit)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- MONSTER ESP
-- ═══════════════════════════════════════════════════════════════════

local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "DQR_ESP"
ESPFolder.Parent = workspace.CurrentCamera

local function createESP(enemy)
    if enemy.model:FindFirstChild("DQR_ESPBillboard") then return end
    local bb = Instance.new("BillboardGui")
    bb.Name = "DQR_ESPBillboard"
    bb.Size = UDim2.new(0, 120, 0, 40)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = enemy.root
    bb.Parent = enemy.model

    local name = Instance.new("TextLabel")
    name.Size = UDim2.new(1, 0, 0.5, 0)
    name.BackgroundTransparency = 1
    name.Text = enemy.model.Name
    name.TextColor3 = Color3.fromRGB(255, 80, 80)
    name.TextStrokeTransparency = 0.3
    name.TextScaled = true
    name.Font = Enum.Font.GothamBold
    name.Parent = bb

    local hp = Instance.new("TextLabel")
    hp.Size = UDim2.new(1, 0, 0.5, 0)
    hp.Position = UDim2.new(0, 0, 0.5, 0)
    hp.BackgroundTransparency = 1
    hp.Text = math.floor(enemy.hp) .. "/" .. math.floor(enemy.maxHp)
    hp.TextColor3 = Color3.fromRGB(80, 255, 80)
    hp.TextStrokeTransparency = 0.3
    hp.TextScaled = true
    hp.Font = Enum.Font.Gotham
    hp.Parent = bb
end

local function removeESP()
    for _, d in ipairs(ESPFolder:GetChildren()) do d:Destroy() end
    for _, m in ipairs(workspace:GetDescendants()) do
        local bb = m:FindFirstChild("DQR_ESPBillboard")
        if bb then bb:Destroy() end
    end
end

local function updateESP()
    if not S.MonsterESP then removeESP() return end
    local alive = getAlive()
    -- Remove ESP from dead
    for _, d in ipairs(ESPFolder:GetChildren()) do d:Destroy() end
    for _, m in ipairs(workspace:GetDescendants()) do
        local bb = m:FindFirstChild("DQR_ESPBillboard")
        if bb then
            local stillAlive = false
            for _, e in ipairs(alive) do
                if e.model == m then stillAlive = true break end
            end
            if not stillAlive then bb:Destroy() end
        end
    end
    -- Create ESP for alive
    for _, e in ipairs(alive) do createESP(e) end
end

-- ═══════════════════════════════════════════════════════════════════
-- RAYFIELD UI
-- ═══════════════════════════════════════════════════════════════════

local Window = Rayfield:CreateWindow({
    Name = "Dungeon Quest Reborn",
    LoadingTitle = "DQR Hub v3.0",
    LoadingSubtitle = "Full-auto by Raven",
    ConfigurationSaving = {Enabled = false},
    KeySystem = false,
})

-- ═══════════════════════════════════════════════════════════════════
-- COMBAT TAB
-- ═══════════════════════════════════════════════════════════════════

local CT = Window:CreateTab("⚔️ Combat", 4483362458)
CT:CreateSection("Kill Aura (Teleport + Swing)")

CT:CreateToggle({
    Name = "Kill Aura",
    CurrentValue = false,
    Callback = function(v)
        S.KillAura = v
        if v then
            Conn["KillAura"] = RunService.Heartbeat:Connect(function()
                if not S.KillAura or not isAlive() or not isInDungeon() then return end
                if Flags.attacking then return end
                local sw = getWeaponSwing()
                if not sw then return end
                local enemies = getAlive()
                if #enemies == 0 then return end
                -- Sort by distance (closest first)
                local my = getRoot()
                if not my then return end
                table.sort(enemies, function(a, b)
                    return (a.root.Position - my.Position).Magnitude < (b.root.Position - my.Position).Magnitude
                end)
                Flags.attacking = true
                for _, e in ipairs(enemies) do
                    if not S.KillAura then break end
                    if e.hum.Health > 0 then
                        if isAttackTelegraph(e.model) then
                            dodgeAway(e.model, 20)
                            task.wait(randDelay(0.2, 0.3))
                        end
                        teleportTo(e.root.Position + Vector3.new(0, 0, 3))
                        task.wait(randDelay(0.05, 0.15))
                        faceTarget(e.root.Position)
                        sw:FireServer()
                        task.wait(randDelay(0.1, 0.15))
                    end
                end
                Flags.attacking = false
            end)
        else
            if Conn["KillAura"] then Conn["KillAura"]:Disconnect(); Conn["KillAura"] = nil end
            Flags.attacking = false
        end
    end,
})

CT:CreateSection("Auto Skill (spellEvent + abilityUsed)")

CT:CreateToggle({
    Name = "Auto Skill",
    CurrentValue = false,
    Callback = function(v)
        S.AutoSkill = v
        if v then
            Conn["AutoSkill"] = RunService.Heartbeat:Connect(function()
                if not S.AutoSkill or not isAlive() or not isInDungeon() then return end
                local enemy = getClosest(math.huge)
                if not enemy then return end
                local skills = getSkills()
                for _, sk in ipairs(skills) do
                    if isSkillReady(sk) then
                        faceTarget(enemy.root.Position)
                        equipTool(sk.tool)
                        task.wait(randDelay(0.03, 0.1))
                        pcall(function() sk.remote:FireServer() end)
                        local au = getRem("abilityUsed", "RemoteEvent")
                        if au then pcall(function() au:FireServer(sk.name, sk.tool) end) end
                        task.wait(randDelay(0.08, 0.15))
                        break
                    end
                end
            end)
        else
            if Conn["AutoSkill"] then Conn["AutoSkill"]:Disconnect(); Conn["AutoSkill"] = nil end
        end
    end,
})

-- ═══════════════════════════════════════════════════════════════════
-- FARM TAB
-- ═══════════════════════════════════════════════════════════════════

local FT = Window:CreateTab("🌾 Farm", 4483362458)
FT:CreateSection("Auto Farm (Room Priority)")

FT:CreateToggle({
    Name = "Auto Farm",
    CurrentValue = false,
    Callback = function(v)
        S.AutoFarm = v
        if v then
            Conn["AutoFarm"] = RunService.Heartbeat:Connect(function()
                if not S.AutoFarm or not isAlive() or not isInDungeon() then return end
                if Flags.attacking then return end
                local allEnemies = getAlive()
                if #allEnemies == 0 then return end
                local my = getRoot()
                if not my then return end
                -- Find closest across ALL rooms (no range limit)
                local closest = nil
                local closestD = math.huge
                for _, e in ipairs(allEnemies) do
                    local d = (e.root.Position - my.Position).Magnitude
                    if d < closestD then closest = e; closestD = d end
                end
                if not closest then return end
                if isAttackTelegraph(closest.model) then
                    dodgeAway(closest.model, 20)
                    task.wait(randDelay(0.3, 0.3))
                    return
                end
                local sw = getWeaponSwing()
                if sw then
                    teleportTo(closest.root.Position + Vector3.new(0, 0, 3))
                    task.wait(randDelay(0.05, 0.15))
                    faceTarget(closest.root.Position)
                    sw:FireServer()
                    task.wait(randDelay(0.1, 0.15))
                end
            end)
        else
            if Conn["AutoFarm"] then Conn["AutoFarm"]:Disconnect(); Conn["AutoFarm"] = nil end
        end
    end,
})

FT:CreateSection("Monster ESP")

FT:CreateToggle({
    Name = "Monster ESP",
    CurrentValue = false,
    Callback = function(v)
        S.MonsterESP = v
        if v then
            Conn["MonsterESP"] = RunService.Heartbeat:Connect(updateESP)
        else
            if Conn["MonsterESP"] then Conn["MonsterESP"]:Disconnect(); Conn["MonsterESP"] = nil end
            removeESP()
        end
    end,
})

-- ═══════════════════════════════════════════════════════════════════
-- DUNGEON TAB
-- ═══════════════════════════════════════════════════════════════════

local DT = Window:CreateTab("🏰 Dungeon", 4483362458)
DT:CreateSection("Dungeon Selection")

DT:CreateDropdown({
    Name = "Dungeon",
    Options = {"Tutorial Dungeon","Desert Temple","Winter Outpost","Pirate Island","King's Castle","The Underworld","Samurai Palace","The Canals","Steampunk Sewers","Krampus","Ghastly Harbor","Orbital Outpost","Volcanic Chambers","Enchanted Forest","Aquatic Temple","Northern Lands","Oni Dungeon","Gilded Skies","Egg Island"},
    CurrentOption = {"Desert Temple"},
    Callback = function(v) S.SelectedDungeon = v end,
})

DT:CreateDropdown({
    Name = "Difficulty",
    Options = {"Easy","Medium","Hard","Insane","Nightmare"},
    CurrentOption = {"Easy"},
    Callback = function(v) S.SelectedDifficulty = v end,
})

DT:CreateSection("Automation")

DT:CreateToggle({
    Name = "Auto Dungeon",
    CurrentValue = false,
    Callback = function(v)
        S.AutoStartDungeon = v
        if v then
            -- Enable kill aura + auto skill + auto replay automatically
            S.KillAura = true
            S.AutoSkill = true
            S.AutoReplay = true
            -- Start kill aura connection if not already
            if not Conn["KillAura"] then
                Conn["KillAura"] = RunService.Heartbeat:Connect(function()
                    if not S.KillAura or not isAlive() or not isInDungeon() then return end
                    if Flags.attacking then return end
                    local sw = getWeaponSwing()
                    if not sw then return end
                    local enemies = getAlive()
                    if #enemies == 0 then return end
                    local my = getRoot()
                    if not my then return end
                    table.sort(enemies, function(a, b)
                        return (a.root.Position - my.Position).Magnitude < (b.root.Position - my.Position).Magnitude
                    end)
                    Flags.attacking = true
                    for _, e in ipairs(enemies) do
                        if not S.KillAura then break end
                        if e.hum.Health > 0 then
                            if isAttackTelegraph(e.model) then
                                dodgeAway(e.model, 20)
                                task.wait(randDelay(0.2, 0.3))
                            end
                            teleportTo(e.root.Position + Vector3.new(0, 0, 3))
                            task.wait(randDelay(0.05, 0.15))
                            faceTarget(e.root.Position)
                            sw:FireServer()
                            task.wait(randDelay(0.1, 0.15))
                        end
                    end
                    Flags.attacking = false
                end)
            end
            -- Start auto skill connection
            if not Conn["AutoSkill"] then
                Conn["AutoSkill"] = RunService.Heartbeat:Connect(function()
                    if not S.AutoSkill or not isAlive() or not isInDungeon() then return end
                    local enemy = getClosest(math.huge)
                    if not enemy then return end
                    local skills = getSkills()
                    for _, sk in ipairs(skills) do
                        if isSkillReady(sk) then
                            faceTarget(enemy.root.Position)
                            equipTool(sk.tool)
                            task.wait(randDelay(0.03, 0.1))
                            pcall(function() sk.remote:FireServer() end)
                            local au = getRem("abilityUsed", "RemoteEvent")
                            if au then pcall(function() au:FireServer(sk.name, sk.tool) end) end
                            task.wait(randDelay(0.08, 0.15))
                            break
                        end
                    end
                end)
            end
            -- Main dungeon flow loop
            Conn["AutoStart"] = RunService.Heartbeat:Connect(function()
                if not S.AutoStartDungeon then return end
                if isInDungeon() then return end
                -- Step 0: Handle ReplayConfirmation if visible
                local rc = PG:FindFirstChild("ReplayConfirmation")
                if rc and rc.Enabled then
                    local yes = rc:FindFirstChild("YES")
                    if yes and yes:IsA("TextButton") then
                        pcall(function() yes:Activate() end)
                        task.wait(2)
                        return
                    end
                end
                -- Step 1: Open queue GUI via playButton
                local mi = PG:FindFirstChild("mainInterface")
                if mi then
                    local btns = mi:FindFirstChild("buttons")
                    if btns then
                        local playBtn = btns:FindFirstChild("playButton")
                        if playBtn then
                            local tb = playBtn:FindFirstChildOfClass("TextButton")
                            if tb then pcall(function() tb:Activate() end) end
                        end
                    end
                end
                task.wait(1)
                -- Step 2: Click "Create Dungeon" on selectOption
                local qg = PG:FindFirstChild("queueGui")
                if qg then
                    local sel = qg:FindFirstChild("selectOption")
                    if sel and sel.Visible then
                        local cg = sel.Frame:FindFirstChild("createGame")
                        if cg then pcall(function() cg:Activate() end) end
                        task.wait(0.5)
                        return
                    end
                end
                -- Step 3: Select dungeon from list
                if qg then
                    local cd = qg:FindFirstChild("chooseDungeon")
                    if cd and cd.Visible then
                        local left = cd:FindFirstChild("backgroundFillLeft")
                        if left then
                            local scroll = left:FindFirstChild("ScrollingFrame")
                            if scroll then
                                local dungeonFrame = scroll:FindFirstChild(S.SelectedDungeon or "Desert Temple")
                                if dungeonFrame then
                                    local btn = dungeonFrame:FindFirstChild("TextButton")
                                    if btn then pcall(function() btn:Activate() end) end
                                end
                            end
                        end
                        task.wait(0.3)
                        -- Step 4: Select difficulty
                        local right = cd:FindFirstChild("backgroundFillRight")
                        if right then
                            local diffFrame = right:FindFirstChild(S.SelectedDifficulty or "Easy")
                            if diffFrame then
                                local btn = diffFrame:FindFirstChild("TextButton")
                                if btn then pcall(function() btn:Activate() end) end
                            end
                        end
                        task.wait(0.3)
                        -- Step 5: Click "Create Lobby"
                        local mid = cd:FindFirstChild("backgroundFillMiddle")
                        if mid then
                            local startMain = mid:FindFirstChild("startMain")
                            if startMain then
                                local btn = startMain:FindFirstChild("TextButton")
                                if btn then pcall(function() btn:Activate() end) end
                            end
                        end
                        task.wait(1)
                        return
                    end
                end
                -- Step 6: Click "Start" in lobbyInfo
                if qg then
                    local li = qg:FindFirstChild("lobbyInfo")
                    if li and li.Visible then
                        local sb = li:FindFirstChild("startBackground")
                        if sb then
                            local sf = sb:FindFirstChild("startFrame")
                            if sf then
                                local btn = sf:FindFirstChild("startButton")
                                if btn then pcall(function() btn:Activate() end) end
                            end
                        end
                        task.wait(2)
                        return
                    end
                end
            end)
        else
            if Conn["AutoStart"] then Conn["AutoStart"]:Disconnect(); Conn["AutoStart"] = nil end
        end
    end,
})

DT:CreateToggle({
    Name = "Auto Ready Up",
    CurrentValue = false,
    Callback = function(v)
        S.AutoReadyUp = v
        if v then
            Conn["AutoReady"] = RunService.Heartbeat:Connect(function()
                if not S.AutoReadyUp then return end
                fire("readyUp")
            end)
        else
            if Conn["AutoReady"] then Conn["AutoReady"]:Disconnect(); Conn["AutoReady"] = nil end
        end
    end,
})

DT:CreateToggle({
    Name = "Auto Replay",
    CurrentValue = false,
    Callback = function(v)
        S.AutoReplay = v
        if v then
            Conn["AutoReplay"] = RunService.Heartbeat:Connect(function()
                if not S.AutoReplay then return end
                -- Click ReplayConfirmation YES
                local rc = PG:FindFirstChild("ReplayConfirmation")
                if rc and rc.Enabled then
                    local yes = rc:FindFirstChild("YES")
                    if yes and yes:IsA("TextButton") then pcall(function() yes:Activate() end) end
                end
                -- Also try mainInterface ReplayDungeonButton
                local mi = PG:FindFirstChild("mainInterface")
                if mi then
                    local btns = mi:FindFirstChild("buttons") and mi.buttons:FindFirstChild("optionsButton")
                    if btns then
                        local rb = btns:FindFirstChild("ReplayDungeonButton")
                        if rb then pcall(function() rb:Activate() end) end
                    end
                end
                -- Fallback: replayDungeon remote
                fire("replayDungeon")
            end)
        else
            if Conn["AutoReplay"] then Conn["AutoReplay"]:Disconnect(); Conn["AutoReplay"] = nil end
        end
    end,
})

DT:CreateSection("Wave Control")

DT:CreateSlider({
    Name = "Leave At Wave (0=off)",
    Range = {0, 50}, Increment = 1, Suffix = "",
    CurrentValue = 0,
    Callback = function(v) S.LeaveAtWave = v end,
})

DT:CreateToggle({
    Name = "Auto Leave At Wave",
    CurrentValue = false,
    Callback = function(v)
        if v then
            Conn["LeaveWave"] = RunService.Heartbeat:Connect(function()
                if S.LeaveAtWave <= 0 then return end
                local wave = getCurrentWave()
                if wave >= S.LeaveAtWave then
                    fire("ReturnToLobbyEvent")
                    fire("teleToLobby")
                end
            end)
        else
            if Conn["LeaveWave"] then Conn["LeaveWave"]:Disconnect(); Conn["LeaveWave"] = nil end
        end
    end,
})

DT:CreateSection("Sell & Upgrade")

DT:CreateToggle({
    Name = "Auto Sell",
    CurrentValue = false,
    Callback = function(v)
        S.AutoSell = v
        if v then
            Conn["AutoSell"] = RunService.Heartbeat:Connect(function()
                if not S.AutoSell then return end
                -- Open sell shop
                fire("openSellShop")
                task.wait(1)
                -- Click rarity filter buttons
                local ss = PG:FindFirstChild("sellShop")
                if ss then
                    local left = ss:FindFirstChild("Frame") and ss.Frame:FindFirstChild("innerFrame")
                        and ss.Frame.innerFrame:FindFirstChild("leftSide")
                    if left then
                        local rar = left:FindFirstChild("rarityButtonsFrame")
                        if rar then
                            -- Click all rarity buttons to select all items
                            for _, name in ipairs({"CommonButton","UncommonButton","RareButton","EpicButton","LegendaryButton","UltimateButton"}) do
                                local btn = rar:FindFirstChild(name)
                                if btn then pcall(function() btn:Activate() end) end
                            end
                        end
                        task.wait(0.5)
                        -- Click sell button
                        local sellMain = left:FindFirstChild("sellMain")
                        if sellMain then
                            local sb = sellMain:FindFirstChild("sellButton")
                            if sb then pcall(function() sb:Activate() end) end
                        end
                    end
                end
                task.wait(0.5)
                -- Close shop
                if ss then
                    local xf = ss:FindFirstChild("Frame") and ss.Frame:FindFirstChild("xFrame")
                    if xf then
                        local xb = xf:FindFirstChild("xButton")
                        if xb then pcall(function() xb:Activate() end) end
                    end
                end
                task.wait(5)
            end)
        else
            if Conn["AutoSell"] then Conn["AutoSell"]:Disconnect(); Conn["AutoSell"] = nil end
        end
    end,
})

DT:CreateToggle({
    Name = "Auto Upgrade Items",
    CurrentValue = false,
    Callback = function(v)
        S.AutoUpgrade = v
        if v then
            Conn["AutoUpgrade"] = RunService.Heartbeat:Connect(function()
                if not S.AutoUpgrade then return end
                task.wait(3)
                fire("upgradeItem")
                task.wait(1)
            end)
        else
            if Conn["AutoUpgrade"] then Conn["AutoUpgrade"]:Disconnect(); Conn["AutoUpgrade"] = nil end
        end
    end,
})

DT:CreateDropdown({
    Name = "Upgrade Priority",
    Options = {"Physical", "Spell", "Health"},
    CurrentOption = {"Physical"},
    Callback = function(v) S.UpgradePriority = v end,
})

DT:CreateToggle({
    Name = "Auto Spend Skill Points",
    CurrentValue = false,
    Callback = function(v)
        S.AutoSpendSP = v
        if v then
            Conn["AutoSP"] = RunService.Heartbeat:Connect(function()
                if not S.AutoSpendSP then return end
                local sp = getVal("skillPoints")
                if not sp or sp <= 0 then return end
                -- spendSkillPoint:FireServer("Physical") / "Spell" / "Health"
                fire("spendSkillPoint", S.UpgradePriority)
                task.wait(0.5)
            end)
        else
            if Conn["AutoSP"] then Conn["AutoSP"]:Disconnect(); Conn["AutoSP"] = nil end
        end
    end,
})

DT:CreateDropdown({
    Name = "Skill Point Priority",
    Options = {"Physical", "Spell", "Health"},
    CurrentOption = {"Physical"},
    Callback = function(v) S.UpgradePriority = v; S.SpendSPPriority = v end,
})

DT:CreateButton({
    Name = "Equip Best Items",
    Callback = function()
        invoke("equipItem")
    end,
})

-- ═══════════════════════════════════════════════════════════════════
-- MISC TAB
-- ═══════════════════════════════════════════════════════════════════

local MT = Window:CreateTab("⚙️ Misc", 4483362458)
MT:CreateSection("Movement")

MT:CreateToggle({
    Name = "NoClip",
    CurrentValue = false,
    Callback = function(v)
        S.NoClip = v
        if v then
            Conn["NoClip"] = RunService.Stepped:Connect(function()
                if not S.NoClip then return end
                local c = LP.Character
                if c then
                    for _, p in ipairs(c:GetDescendants()) do
                        if p:IsA("BasePart") then p.CanCollide = false end
                    end
                end
            end)
        else
            if Conn["NoClip"] then Conn["NoClip"]:Disconnect(); Conn["NoClip"] = nil end
        end
    end,
})

MT:CreateToggle({
    Name = "Infinite Jump",
    CurrentValue = false,
    Callback = function(v)
        S.InfiniteJump = v
        if v then
            Conn["InfJump"] = UIS.JumpRequest:Connect(function()
                if not S.InfiniteJump then return end
                local h = getHum()
                if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
            end)
        else
            if Conn["InfJump"] then Conn["InfJump"]:Disconnect(); Conn["InfJump"] = nil end
        end
    end,
})

MT:CreateSlider({
    Name = "Walk Speed",
    Range = {16, 100}, Increment = 1, Suffix = " studs/s",
    CurrentValue = 16,
    Callback = function(v)
        S.WalkSpeed = v
        local h = getHum()
        if h then h.WalkSpeed = v end
    end,
})

MT:CreateSection("Performance")

MT:CreateToggle({
    Name = "FPS Boost",
    CurrentValue = false,
    Callback = function(v)
        S.FPSBoost = v
        if v then
            pcall(function()
                local g = game:GetService("Lighting")
                g.GlobalShadows = false
                g.FogEnd = 999999
                g.Brightness = 0
                settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("ParticleEmitter") then d.Enabled = false end
                    if d:IsA("Trail") then d.Enabled = false end
                    if d:IsA("Beam") then d.Enabled = false end
                end
                pcall(function() settings().Physics.PhysicsEnvironmentalThrottle = Enum.EnviromentalThrottleState.Enhanced end)
            end)
        else
            pcall(function()
                local g = game:GetService("Lighting")
                g.GlobalShadows = true
                g.FogEnd = 100000
                g.Brightness = 2
                settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("ParticleEmitter") then d.Enabled = true end
                    if d:IsA("Trail") then d.Enabled = true end
                    if d:IsA("Beam") then d.Enabled = true end
                end
            end)
        end
    end,
})

MT:CreateSection("Anti-AFK")

MT:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Callback = function(v)
        S.AntiAFK = v
        if v then
            Conn["AntiAFK"] = LP.Idled:Connect(function()
                VU:CaptureController()
                VU:ClickButton2(Vector2.new())
            end)
        else
            if Conn["AntiAFK"] then Conn["AntiAFK"]:Disconnect(); Conn["AntiAFK"] = nil end
        end
    end,
})

MT:CreateSection("Server")

MT:CreateButton({
    Name = "Rejoin Server",
    Callback = function()
        TP:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end,
})

MT:CreateButton({
    Name = "Server Hop",
    Callback = function()
        local ok, servers = pcall(function()
            return game:GetService("HttpService"):JSONDecode(
                game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
            )
        end)
        if ok and servers and servers.data then
            for _, s in ipairs(servers.data) do
                if s.id ~= game.JobId and s.playing < s.maxPlayers then
                    TP:TeleportToPlaceInstance(game.PlaceId, s.id, LP)
                    break
                end
            end
        end
    end,
})

MT:CreateButton({
    Name = "Return to Lobby",
    Callback = function()
        fire("ReturnToLobbyEvent")
        fire("teleToLobby")
    end,
})

MT:CreateButton({
    Name = "Reset Skill Points",
    Callback = function()
        fire("resetSkillPoints")
    end,
})

MT:CreateSection("Stats Display")

MT:CreateLabel("XP: " .. tostring(getVal("XP") or 0) .. " / " .. tostring(getVal("XPNeeded") or 0))
MT:CreateLabel("Skill Points: " .. tostring(getVal("skillPoints") or 0))
MT:CreateLabel("Physical: " .. tostring(getVal("physicalPower") or 0))
MT:CreateLabel("Spell Power: " .. tostring(getVal("spellPower") or 0))

-- ═══════════════════════════════════════════════════════════════════
-- RESPONSIVE CONNECTIONS
-- ═══════════════════════════════════════════════════════════════════

LP.CharacterAdded:Connect(function(char)
    task.wait(1)
    local h = char:FindFirstChildOfClass("Humanoid")
    if h and S.UseSpeed then h.WalkSpeed = S.WalkSpeed end
end)

RunService.Heartbeat:Connect(function()
    Flags.inDungeon = isInDungeon()
end)

-- ═══════════════════════════════════════════════════════════════════
-- LOAD
-- ═══════════════════════════════════════════════════════════════════

Rayfield:LoadConfiguration()
