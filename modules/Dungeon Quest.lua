-- VoltScriptZ | Map: Dungeon Quest
-- Auto Farm Tween (Overhead / Below / Behind) - NO AGGRO + STABILIZED
-- Fluent UI - Fix เด้ง/กลิ้ง/ลอย

local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

do
    local ok, _old = pcall(function() return hookfunction end)
    if ok and _old then
        local _oldHttpGet = hookfunction(game.HttpGet, function(self, url, ...)
            if type(url) == "string" and url:find("Darker%.lua") then
                -- directly return modified Darker theme with dark purple
                return [[return {
    Name = "Darker",
    Accent = Color3.fromRGB(110, 30, 160),
    AcrylicMain = Color3.fromRGB(12, 12, 12),
    AcrylicBorder = Color3.fromRGB(45, 25, 75),
    AcrylicGradient = ColorSequence.new(Color3.fromRGB(28, 14, 48), Color3.fromRGB(12, 10, 18)),
    AcrylicNoise = 0.9,
    TitleBarLine = Color3.fromRGB(75, 35, 115),
    Tab = Color3.fromRGB(190, 150, 235),
    Element = Color3.fromRGB(110, 30, 160),
    ElementBorder = Color3.fromRGB(55, 30, 85),
    InElementBorder = Color3.fromRGB(75, 40, 115),
    ElementTransparency = 0.08,
    ToggleSlider = Color3.fromRGB(110, 30, 160),
    ToggleToggled = Color3.fromRGB(18, 12, 28),
    SliderRail = Color3.fromRGB(110, 30, 160),
    DropdownFrame = Color3.fromRGB(38, 22, 62),
    DropdownHolder = Color3.fromRGB(22, 14, 36),
    DropdownBorder = Color3.fromRGB(55, 30, 85),
    DropdownOption = Color3.fromRGB(110, 30, 160),
    Keybind = Color3.fromRGB(110, 30, 160),
    Input = Color3.fromRGB(110, 30, 160),
    InputFocused = Color3.fromRGB(18, 12, 28),
    InputIndicator = Color3.fromRGB(145, 70, 220),
    Dialog = Color3.fromRGB(28, 16, 48),
    DialogHolder = Color3.fromRGB(20, 12, 36),
    DialogHolderLine = Color3.fromRGB(35, 20, 60),
    DialogButton = Color3.fromRGB(38, 22, 62),
    DialogButtonBorder = Color3.fromRGB(75, 40, 115),
    DialogBorder = Color3.fromRGB(65, 35, 105),
    DialogInput = Color3.fromRGB(45, 26, 72),
    DialogInputLine = Color3.fromRGB(145, 70, 220),
    Text = Color3.fromRGB(240, 240, 245),
    SubText = Color3.fromRGB(165, 155, 180),
    Hover = Color3.fromRGB(110, 30, 160),
    HoverChange = 0.06,
}]]
            end
            return _oldHttpGet(self, url, ...)
        end)
    end
end

local Window = Fluent:CreateWindow({
    Title = "VoltScriptZ | Dungeon Quest Reborn ",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = false,
    Theme = "Darker",
    MinimizeKey = Enum.KeyCode.LeftControl
})
Fluent:ToggleTransparency(false)

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "home" }),
    Dungeon = Window:AddTab({ Title = "Dungeon", Icon = "swords" }),
    Shop = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- recolor toggles to dark purple - every frame, no blue flash
task.spawn(function()
    while RunService.Heartbeat:Wait() do
        if Fluent.Unloaded then break end
        for _, v in ipairs(game.CoreGui:GetDescendants()) do
            if v:IsA("Frame") and v.BackgroundColor3 then
                local c = v.BackgroundColor3
                if c.B > 0.4 and c.R < 0.55 and c.B > c.R then
                    v.BackgroundColor3 = Color3.fromRGB(110, 30, 160)
                end
            end
            if v:IsA("ImageLabel") and v.ImageColor3 then
                local c = v.ImageColor3
                if c.B > 0.4 and c.R < 0.55 and c.B > c.R then
                    v.ImageColor3 = Color3.fromRGB(110, 30, 160)
                end
            end
            if v:IsA("TextButton") and v.BackgroundColor3 then
                local c = v.BackgroundColor3
                if c.B > 0.4 and c.R < 0.55 then
                    v.BackgroundColor3 = Color3.fromRGB(110, 30, 160)
                end
            end
            if v:IsA("UIStroke") and v.Color then
                local c = v.Color
                if c.B > 0.4 and c.R < 0.55 then
                    v.Color = Color3.fromRGB(110, 30, 160)
                end
            end
        end
    end
end)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local Workspace = game:GetService("Workspace")

local LP = Players.LocalPlayer

local Config = {
    AutoFarm = false,
    Position = "Overhead",
    TweenSpeed = 30,
    FarmDistance = 10, -- Overhead/Below/Behind distance
    AttackDelay = 0.14,
    Noclip = true,
    BringHeight = 2,
    Stabilize = true,
    AutoSkill = false,
    SkillQ = true,
    SkillE = true,
    SkillDelay = 0.6,
    AutoStart = true,
    AutoRejoin = false,
    AutoLobby = false,
    AutoCreate = false,
    SelectedDungeon = "Desert Temple",
    SelectedDifficulty = "Easy",
    AutoCreateBest = false,
    AutoSell = false,
    SellItemRarities = {common=true, uncommon=true, rare=false, epic=false, legendary=false, ultimate=false},
    SellSkillRarities = {common=true, uncommon=false, rare=false, epic=false, legendary=false, ultimate=false},
    SellDelay = 1,
}

local State = {
    Tween = nil,
    NoclipConn = nil,
    HeartbeatConn = nil,
}

local function getHRP()
    local char = LP.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local char = LP.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function isAlive(model)
    local h = model:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function getEnemies()
    local out = {}
    for _, v in ipairs(Workspace:GetDescendants()) do
        if v:IsA("Model") and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChildOfClass("Humanoid") then
            if Players:FindFirstChild(v.Name) then continue end
            local hum = v:FindFirstChildOfClass("Humanoid")
            if hum.Health <= 0 then continue end
            if v == LP.Character then continue end
            table.insert(out, v)
        end
    end
    return out
end

local function getClosestMob()
    local hrp = getHRP()
    if not hrp then return nil end
    local enemies = getEnemies()
    local closest, dist = nil, math.huge
    for _, m in ipairs(enemies) do
        local mhrp = m:FindFirstChild("HumanoidRootPart")
        if mhrp then
            local d = (hrp.Position - mhrp.Position).Magnitude
            if d < dist then
                dist = d
                closest = m
            end
        end
    end
    return closest, dist
end

local function tweenTo(cf, speed)
    local hrp = getHRP()
    if not hrp then return end
    if State.Tween then
        pcall(function() State.Tween:Cancel() end)
        State.Tween = nil
    end
    local dist = (hrp.Position - cf.Position).Magnitude
    local duration = dist / math.max(1, speed)
    local tw = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = cf})
    State.Tween = tw
    tw:Play()
    local start = tick()
    repeat
        task.wait()
        if not Config.AutoFarm or Fluent.Unloaded then
            pcall(function() tw:Cancel() end)
            break
        end
        if not hrp.Parent then break end
        if (hrp.Position - cf.Position).Magnitude < 3.5 then break end
    until tick() - start >= duration + 0.4
end

local function setNoclip(state)
    if State.NoclipConn then
        State.NoclipConn:Disconnect()
        State.NoclipConn = nil
    end
    if State.HeartbeatConn then
        State.HeartbeatConn:Disconnect()
        State.HeartbeatConn = nil
    end
    if state then
        State.NoclipConn = RunService.Stepped:Connect(function()
            local char = LP.Character
            if not char then return end
            for _, v in ipairs(char:GetDescendants()) do
                if v:IsA("BasePart") then
                    v.CanCollide = false
                end
            end
        end)
        -- Stabilizer: ผูกกับ AutoFarm โดยตรง (ไม่ต้องรอ toggle)
        State.HeartbeatConn = RunService.Heartbeat:Connect(function()
            if not Config.AutoFarm then return end
            local hrp = getHRP()
            local hum = getHumanoid()
            if not hrp or not hum then return end
            -- Overhead/ Below ต้องก้ม/เงย 90° ต้อง PlatformStand=true ถึงจะไม่กลิ้ง/เด้ง (มุดดินด้วย)
            if Config.Position == "Overhead" or Config.Position == "Below" then
                hum.PlatformStand = true
                hum.AutoRotate = false
            else
                if hum.PlatformStand then hum.PlatformStand = false end
                hum.AutoRotate = false
                if hum:GetState() == Enum.HumanoidStateType.FallingDown or hum:GetState() == Enum.HumanoidStateType.Ragdoll then
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
            -- ล็อคความเร็วไม่ให้เด้ง
            hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
            hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
        end)
    else
        local hum = getHumanoid()
        if hum then hum.AutoRotate = true end
    end
end

local function doAttack()
    local char = LP.Character
    if not char then return end
    if char:FindFirstChild("busyCasting") and char.busyCasting.Value == true then return end
    if LP:FindFirstChild("peaceful") and LP.peaceful.Value == true then return end
    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") and acc:FindFirstChild("Weapon") then
            local re = acc:FindFirstChildOfClass("RemoteEvent")
            if re then
                pcall(function() re:FireServer() end)
            end
        end
    end
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if remotes then
        local w = remotes:FindFirstChild("weaponUsed")
        if w then
            pcall(function() w:FireServer() end)
        end
    end
end

local function isSlotOnCooldown(slot)
    for _, v in ipairs(LP.Backpack:GetChildren()) do
        if v:FindFirstChild("abilitySlot") and v.abilitySlot.Value == slot then
            local cd = v:FindFirstChild("cooldown")
            if cd and cd.Value > 0 then return true end
        end
    end
    if not LP.Character then return false end
    for _, v in ipairs(LP.Character:GetChildren()) do
        if v:IsA("Tool") and v:FindFirstChild("abilitySlot") and v.abilitySlot.Value == slot then
            local cd = v:FindFirstChild("cooldown")
            if cd and cd.Value > 0 then return true end
        end
    end
    return false
end

local function useSkill(slot)
    if isSlotOnCooldown(slot) then return end
    local tool = nil
    for _, v in ipairs(LP.Backpack:GetChildren()) do
        if v:FindFirstChild("abilitySlot") and v.abilitySlot.Value == slot then tool = v; break end
    end
    if not tool and LP.Character then
        for _, v in ipairs(LP.Character:GetChildren()) do
            if v:IsA("Tool") and v:FindFirstChild("abilitySlot") and v.abilitySlot.Value == slot then tool = v; break end
        end
    end
    if not tool then return end
    local le = tool:FindFirstChild("localEvent")
    if le then pcall(function() le:Fire() end) end
    local remotes = ReplicatedStorage:FindFirstChild("remotes")
    if remotes and remotes:FindFirstChild("abilityUsed") then
        pcall(function() remotes.abilityUsed:FireServer(slot, tool) end)
    end
end

-- horizontal look: มองมอนแบบไม่ก้ม/เงย (กันกลิ้ง)
local function flatLook(pos, targetPos)
    local dir = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
    if dir.Magnitude < 0.1 then
        return CFrame.new(pos)
    end
    return CFrame.lookAt(pos, pos + dir)
end

local function getGroundY(pos)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LP.Character}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local res = Workspace:Raycast(pos + Vector3.new(0,5,0), Vector3.new(0,-30,0), params)
    if res then
        return res.Position.Y
    end
    return nil
end

local function getFarmCFrame(targetHRP)
    local base = targetHRP.Position
    local look = targetHRP.CFrame.LookVector
    if Config.Position == "Overhead" then
        local pos = base + Vector3.new(0, Config.FarmDistance, 0)
        return CFrame.new(pos, base)
    elseif Config.Position == "Below" then
        local pos = base + Vector3.new(0, -Config.FarmDistance, 0)
        return CFrame.new(pos, base)
    elseif Config.Position == "Behind" then
        local behindPos = base - look * Config.FarmDistance + Vector3.new(0, 2, 0)
        return flatLook(behindPos, base)
    end
    local pos = base + Vector3.new(0, Config.FarmDistance, 0)
    return flatLook(pos, base)
end

local function getBestDungeon()
    local lvl = LP:FindFirstChild("leaderstats") and LP.leaderstats:FindFirstChild("Level") and LP.leaderstats.Level.Value or 1
    local dungeons = {"Desert Temple","Winter Outpost","Pirate Island","King's Castle","The Underworld","Samurai Palace","The Canals","Ghastly Harbor","Steampunk Sewers","Orbital Outpost","Volcanic Chambers","Aquatic Temple","Enchanted Forest","Northern Lands","Gilded Skies","Oni Dungeon","Egg Island"}
    local diffs = {"Nightmare","Insane","Hard","Medium","Easy"}
    local best = {dungeon = "Desert Temple", diff = "Easy", req = -1}
    for _, dName in ipairs(dungeons) do
        local ok, stats = pcall(function() return ReplicatedStorage.remotes.getDungeonStats:InvokeServer(dName) end)
        if ok and type(stats) == "table" then
            for _, diff in ipairs(diffs) do
                local data = stats[diff]
                if data and data.levelReq and data.levelReq <= lvl then
                    if data.levelReq > best.req then
                        best = {dungeon = dName, diff = diff, req = data.levelReq}
                    end
                    break
                end
            end
        end
    end
    return best.dungeon, best.diff
end

-- // Main Farm Loop - NO AGGRO + Stabilized - ห้ามใช้ใน Lobby
task.spawn(function()
    while task.wait(0.05) do
        if Fluent.Unloaded then break end
        if not Config.AutoFarm then continue end
        if game.PlaceId == 77649408247578 then continue end
        local hrp = getHRP()
        local hum = getHumanoid()
        if not hrp or not hum then continue end
        local target = getClosestMob()
        if not target or not target.Parent then
            task.wait(0.3)
            continue
        end
        local thrp = target:FindFirstChild("HumanoidRootPart")
        if not thrp then continue end

        -- กันมอนเด้งเรา: ปิด collide มอนชั่วคราวฝั่ง client
        pcall(function()
            for _, p in ipairs(target:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)

        local farmCF = getFarmCFrame(thrp)
        tweenTo(farmCF, Config.TweenSpeed)

        local startAtk = tick()
        while Config.AutoFarm and target.Parent and isAlive(target) and thrp.Parent do
            if Fluent.Unloaded then break end
            local curFarm = getFarmCFrame(thrp)
            local dist = (hrp.Position - curFarm.Position).Magnitude
            if dist > 5 then
                tweenTo(curFarm, Config.TweenSpeed)
            else
                -- ล็อคตำแหน่งแบบไม่ก้ม/ไม่กลิ้ง
                hrp.CFrame = curFarm
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0)
                hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
            end
            doAttack()
            task.wait(Config.AttackDelay)
            if tick() - startAtk > 0.7 then
                local newClosest = getClosestMob()
                if newClosest and newClosest ~= target then
                    local nd = (hrp.Position - newClosest.HumanoidRootPart.Position).Magnitude
                    local cd = (hrp.Position - thrp.Position).Magnitude
                    if nd + 10 < cd then
                        break
                    end
                end
                startAtk = tick()
            end
        end
    end
end)

-- Auto Skill loop
task.spawn(function()
    while task.wait(Config.SkillDelay) do
        if Fluent.Unloaded then break end
        if not Config.AutoSkill then continue end
        if Config.SkillQ then useSkill("q") task.wait(0.05) end
        if Config.SkillE then useSkill("e") end
    end
end)

-- Auto Start (Dungeon)
task.spawn(function()
    while task.wait(0.5) do
        if Fluent.Unloaded then break end
        if not Config.AutoStart then continue end
        local ok, btn = pcall(function() return game.Players.LocalPlayer.PlayerGui:FindFirstChild("startButton") end)
        if not ok or not btn then continue end
        local tb = btn:FindFirstChild("Frame") and btn.Frame:FindFirstChild("3d") and btn.Frame["3d"]:FindFirstChild("Frame") and btn.Frame["3d"].Frame:FindFirstChild("TextButton")
        if tb and tb.Visible and tb.Parent and tb.Parent.Parent.Visible then
            local wsStart = workspace:FindFirstChild("start")
            if wsStart and wsStart.Value == false then
                pcall(function() game.ReplicatedStorage.remotes.changeStartValue:FireServer() end)
            elseif not wsStart then
                pcall(function() game.ReplicatedStorage.remotes.changeStartValue:FireServer() end)
            end
        end
    end
end)

-- Auto Rejoin (Replay)
local function collectReplayData()
    local v1 = {}
    local dn = workspace:FindFirstChild("dungeonName")
    if dn and dn:IsA("StringValue") then v1.dungeonName = dn.Value end
    local dp = workspace:FindFirstChild("dungeonProgress")
    if dp and dp:IsA("StringValue") then v1.dungeonProgress = dp.Value end
    local ds = workspace:FindFirstChild("dungeonStarted")
    if ds and ds:IsA("BoolValue") then v1.dungeonStarted = ds.Value end
    local hc = workspace:FindFirstChild("hardcore")
    if hc and hc:IsA("BoolValue") then v1.hardcore = hc.Value; v1.isHardcore = hc.Value end
    local dungeon = workspace:FindFirstChild("dungeon")
    if dungeon then
        for _, v in ipairs(dungeon:GetChildren()) do if v:IsA("ValueBase") then v1[v.Name] = v.Value end end
        local bossRoom = dungeon:FindFirstChild("bossRoom")
        if bossRoom then for _, v in ipairs(bossRoom:GetChildren()) do if v:IsA("ValueBase") then v1[v.Name] = v.Value end end end
    end
    return v1
end

task.spawn(function()
    while task.wait(0.8) do
        if Fluent.Unloaded then break end
        if not Config.AutoRejoin then continue end
        local finished = false
        local bossRoom = workspace:FindFirstChild("dungeon") and workspace.dungeon:FindFirstChild("bossRoom")
        if bossRoom and bossRoom:FindFirstChild("dungeonFinished") and bossRoom.dungeonFinished:IsA("BoolValue") and bossRoom.dungeonFinished.Value then
            finished = true
        end
        local dp = workspace:FindFirstChild("dungeonProgress")
        if dp and dp:IsA("StringValue") and dp.Value == "bossKilled" then finished = true end
        if not finished then continue end
        -- ถ้าจบแล้ว ให้กด Rejoin อัตโนมัติ (ไม่กลับ Lobby)
        local pg = LP.PlayerGui
        local replayGui = pg:FindFirstChild("ReplayConfirmation")
        if replayGui and replayGui.Enabled then
            task.wait(0.4)
            pcall(function() game.ReplicatedStorage.remotes.replayDungeon:FireServer(collectReplayData()) end)
            replayGui.Enabled = false
        else
            -- ไม่มี popup แต่จบแล้ว ยิงตรงเลย
            pcall(function() game.ReplicatedStorage.remotes.replayDungeon:FireServer(collectReplayData()) end)
            task.wait(3)
        end
    end
end)

-- Auto Back to Lobby
task.spawn(function()
    while task.wait(0.8) do
        if Fluent.Unloaded then break end
        if not Config.AutoLobby then continue end
        if Config.AutoRejoin then continue end
        local finished = false
        local bossRoom = workspace:FindFirstChild("dungeon") and workspace.dungeon:FindFirstChild("bossRoom")
        if bossRoom and bossRoom:FindFirstChild("dungeonFinished") and bossRoom.dungeonFinished:IsA("BoolValue") and bossRoom.dungeonFinished.Value then
            finished = true
        end
        local dp = workspace:FindFirstChild("dungeonProgress")
        if dp and dp:IsA("StringValue") and dp.Value == "bossKilled" then finished = true end
        if not finished then continue end
        -- กด Back to Lobby อัตโนมัติ
        local pg = LP.PlayerGui
        local lobbyGui = pg:FindFirstChild("ReturnConfirmation") or pg:FindFirstChild("LobbyTeleport")
        if lobbyGui and lobbyGui.Enabled then
            task.wait(0.4)
            pcall(function() game.ReplicatedStorage.remotes.ReturnToLobbyEvent:FireServer() end)
            lobbyGui.Enabled = false
        else
            pcall(function() game.ReplicatedStorage.remotes.ReturnToLobbyEvent:FireServer() end)
            task.wait(3)
        end
    end
end)

-- Auto Create Dungeon - only in Lobby
task.spawn(function()
    while task.wait(2) do
        if Fluent.Unloaded then break end
        if not Config.AutoCreate and not Config.AutoCreateBest then continue end
        if game.PlaceId ~= 77649408247578 then continue end
        -- ถ้าอยู่ใน lobby แล้ว (มีห้องของตัวเอง) ไม่ต้องสร้างใหม่
        local inLobby = false
        for _, v in ipairs(workspace.games.inLobby:GetChildren()) do
            for _, p in ipairs(v:GetChildren()) do
                if p.Name == LP.Name then inLobby = true break end
            end
            if inLobby then break end
        end
        if inLobby then continue end
        local inGame = false
        for _, v in ipairs(workspace.games.inGame:GetChildren()) do
            for _, p in ipairs(v:GetChildren()) do
                if p.Name == LP.Name then inGame = true break end
            end
            if inGame then break end
        end
        if inGame then continue end
        local pg = LP.PlayerGui
        local queueGui = pg:FindFirstChild("queueGui")
        if not queueGui then continue end
        local lobbyInfo = queueGui:FindFirstChild("lobbyInfo")
        if lobbyInfo and lobbyInfo.Visible then continue end
        local chooseDungeon = queueGui:FindFirstChild("chooseDungeon")
        local lvl = 1
        if chooseDungeon then
            local lvlText = chooseDungeon:FindFirstChild("levelReq") and chooseDungeon.levelReq:FindFirstChild("Frame") and chooseDungeon.levelReq.Frame:FindFirstChild("TextBox")
            lvl = lvlText and tonumber(lvlText.Text) or 1
        end
        local targetDungeon, targetDiff = Config.SelectedDungeon, Config.SelectedDifficulty
        if Config.AutoCreateBest then
            targetDungeon, targetDiff = getBestDungeon()
            -- sync level to best dungeon's requirement
            local ok2, stats = pcall(function() return ReplicatedStorage.remotes.getDungeonStats:InvokeServer(targetDungeon) end)
            if ok2 and stats and stats[targetDiff] and stats[targetDiff].levelReq then
                lvl = stats[targetDiff].levelReq
            end
        end
        local ok, res = pcall(function()
            return game.ReplicatedStorage.remotes.createLobby:InvokeServer(targetDungeon, targetDiff, lvl, false, false, false)
        end)
        if ok and res == true then
            pcall(function()
                local pg2 = LP.PlayerGui:FindFirstChild("queueGui")
                if pg2 then
                    if pg2:FindFirstChild("chooseDungeon") then pg2.chooseDungeon.Visible = false end
                    if pg2:FindFirstChild("lobbyInfo") then pg2.lobbyInfo.Visible = true; pg2.lobbyInfo.startBackground.Visible = true end
                end
            end)
            task.wait(1.2)
            pcall(function() game.ReplicatedStorage.remotes.startDungeon:FireServer() end)
            task.wait(3)
        end
    end
end)

-- Auto Create helper: auto press lobby START after created (for manual create too)
task.spawn(function()
    while task.wait(0.7) do
        if Fluent.Unloaded then break end
        if not Config.AutoCreate and not Config.AutoCreateBest and not Config.AutoStart then continue end
        local pg = LP.PlayerGui
        local queueGui = pg:FindFirstChild("queueGui")
        if not queueGui then continue end
        local lobbyInfo = queueGui:FindFirstChild("lobbyInfo")
        if lobbyInfo and lobbyInfo.Visible and lobbyInfo:FindFirstChild("startBackground") and lobbyInfo.startBackground.Visible then
            local btn = lobbyInfo.startBackground:FindFirstChild("startFrame") and lobbyInfo.startBackground.startFrame:FindFirstChild("startButton")
            if btn and btn.Visible then
                pcall(function() game.ReplicatedStorage.remotes.startDungeon:FireServer() end)
                task.wait(2)
            end
        elseif lobbyInfo and lobbyInfo.Visible then
            pcall(function() game.ReplicatedStorage.remotes.startDungeon:FireServer() end)
        end
    end
end)

-- Auto Sell
task.spawn(function()
    while task.wait(Config.SellDelay) do
        if Fluent.Unloaded then break end
        if not Config.AutoSell then continue end
        local ok, inv = pcall(function() return ReplicatedStorage.remotes.reloadInvy:InvokeServer() end)
        if not ok or not inv then continue end
        local toSell = {weapon = {}, ability = {}, chest = {}, helmet = {}}
        local cnt = 0
        for uid, data in pairs(inv.weapons) do
            if data.equipped == false then
                local rar = data.rarity and string.lower(data.rarity) or "common"
                if Config.SellItemRarities[rar] then
                    table.insert(toSell.weapon, string.sub(uid, 8))
                    cnt = cnt + 1
                end
            end
        end
        for uid, data in pairs(inv.abilities) do
            if data.equipped.q == false and data.equipped.e == false then
                local rar = data.rarity and string.lower(data.rarity) or "common"
                if Config.SellSkillRarities[rar] then
                    table.insert(toSell.ability, string.sub(uid, 9))
                    cnt = cnt + 1
                end
            end
        end
        for uid, data in pairs(inv.chests) do
            if data.equipped == false then
                local rar = data.rarity and string.lower(data.rarity) or "common"
                if Config.SellItemRarities[rar] then
                    table.insert(toSell.chest, string.sub(uid, 7))
                    cnt = cnt + 1
                end
            end
        end
        for uid, data in pairs(inv.helmets) do
            if data.equipped == false then
                local rar = data.rarity and string.lower(data.rarity) or "common"
                if Config.SellItemRarities[rar] then
                    table.insert(toSell.helmet, string.sub(uid, 8))
                    cnt = cnt + 1
                end
            end
        end
        if cnt > 0 then
            pcall(function() ReplicatedStorage.remotes.sellItemEvent:FireServer(toSell) end)
        end
    end
end)

LP.Idled:Connect(function()
    pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
end)

LP.CharacterAdded:Connect(function()
    task.wait(1)
    if Config.AutoFarm then setNoclip(true) end
end)

-- // UI
Tabs.Main:AddSection("AUTO FARM")

local AutoToggle = Tabs.Main:AddToggle("AutoFarm", {Title = "Auto Farm", Default = false})
AutoToggle:OnChanged(function(v)
    if v and game.PlaceId == 77649408247578 then
        task.spawn(function() task.wait(0.05) pcall(function() AutoToggle:SetValue(false) end) end)
        Config.AutoFarm = false
        return
    end
    Config.AutoFarm = v
    if v then
        Config.Noclip = true
        Config.Stabilize = true
        setNoclip(true)
        local hum = getHumanoid()
        if hum then hum.AutoRotate = false end
    else
        if State.Tween then pcall(function() State.Tween:Cancel() end) end
        local hrp = getHRP()
        if hrp then hrp.AssemblyLinearVelocity = Vector3.new(0,0,0) end
        local hum = getHumanoid()
        if hum then hum.AutoRotate = true; if hum.PlatformStand then hum.PlatformStand = false end end
        setNoclip(false)
    end
end)

task.spawn(function()
    while task.wait(1) do
        if Fluent.Unloaded then break end
        if Config.AutoFarm and game.PlaceId == 77649408247578 then
            Config.AutoFarm = false
            pcall(function() AutoToggle:SetValue(false) end)
            setNoclip(false)
            local hum = getHumanoid()
            if hum then hum.AutoRotate = true; if hum.PlatformStand then hum.PlatformStand = false end end
        end
    end
end)

local PosDrop = Tabs.Main:AddDropdown("FarmPos", {
    Title = "Position",
    Values = {"Overhead", "Below", "Behind"},
    Multi = false,
    Default = 1
})
PosDrop:OnChanged(function(v) Config.Position = v end)

local DistSlider = Tabs.Main:AddSlider("FarmDistance", {
    Title = "Farm Distance",
    Default = 10,
    Min = 5,
    Max = 20,
    Rounding = 0,
})
DistSlider:OnChanged(function(v) Config.FarmDistance = v end)
DistSlider:SetValue(10)

Tabs.Main:AddSection("AUTO SKILL")

local SkillToggle = Tabs.Main:AddToggle("AutoSkill", {Title = "Auto Skill", Default = false})
SkillToggle:OnChanged(function(v) Config.AutoSkill = v end)

local QToggle = Tabs.Main:AddToggle("SkillQ", {Title = "Use Q", Default = true})
QToggle:OnChanged(function(v) Config.SkillQ = v end)

local EToggle = Tabs.Main:AddToggle("SkillE", {Title = "Use E", Default = true})
EToggle:OnChanged(function(v) Config.SkillE = v end)

Tabs.Dungeon:AddSection("Auto Dungeon")

local AutoStartToggle = Tabs.Dungeon:AddToggle("AutoStart", {Title = "Auto Start", Default = true})
AutoStartToggle:OnChanged(function(v)
    if not v then
        task.spawn(function() task.wait(0.05) pcall(function() AutoStartToggle:SetValue(true) end) end)
        Config.AutoStart = true
        return
    end
    Config.AutoStart = true
end)
AutoStartToggle:SetValue(true)
Config.AutoStart = true

local AutoRejoinToggle = Tabs.Dungeon:AddToggle("AutoRejoin", {Title = "Auto Rejoin", Default = false})
AutoRejoinToggle:OnChanged(function(v) Config.AutoRejoin = v end)

local AutoLobbyToggle = Tabs.Dungeon:AddToggle("AutoLobby", {Title = "Auto Back to Lobby", Default = false})
AutoLobbyToggle:OnChanged(function(v) Config.AutoLobby = v end)

Tabs.Dungeon:AddSection("Auto Create Dungeon")

local AutoCreateToggle = Tabs.Dungeon:AddToggle("AutoCreate", {Title = "Auto Create Dungeon", Default = false})
AutoCreateToggle:OnChanged(function(v) Config.AutoCreate = v end)

local DungeonDropdown = Tabs.Dungeon:AddDropdown("SelectedDungeon", {
    Title = "Dungeon",
    Values = {"Desert Temple","Winter Outpost","Pirate Island","King's Castle","The Underworld","Samurai Palace","The Canals","Ghastly Harbor","Steampunk Sewers","Orbital Outpost","Volcanic Chambers","Aquatic Temple","Enchanted Forest","Northern Lands","Gilded Skies","Oni Dungeon","Egg Island"},
    Multi = false,
    Default = 1,
})
DungeonDropdown:OnChanged(function(v) Config.SelectedDungeon = v end)

local DifficultyDropdown = Tabs.Dungeon:AddDropdown("SelectedDifficulty", {
    Title = "Difficulty",
    Values = {"Easy","Medium","Hard","Insane","Nightmare"},
    Multi = false,
    Default = 1,
})
DifficultyDropdown:OnChanged(function(v) Config.SelectedDifficulty = v end)

local BestToggle = Tabs.Dungeon:AddToggle("AutoCreateBest", {Title = "Auto Create Best Dungeon", Default = false})
BestToggle:OnChanged(function(v) Config.AutoCreateBest = v end)

Tabs.Shop:AddSection("Auto Sell")

local AutoSellToggle = Tabs.Shop:AddToggle("AutoSell", {Title = "Auto Sell", Default = false})
AutoSellToggle:OnChanged(function(v) Config.AutoSell = v end)

local ItemRarityDropdown = Tabs.Shop:AddDropdown("SellItemRarity", {
    Title = "Item Rarity",
    Values = {"common","uncommon","rare","epic","legendary","ultimate"},
    Multi = true,
    Default = {"common"},
})
ItemRarityDropdown:OnChanged(function(Value)
    local new = {common=false, uncommon=false, rare=false, epic=false, legendary=false, ultimate=false}
    if type(Value) == "table" then
        for k, v in pairs(Value) do
            if type(v) == "boolean" and new[k] ~= nil then new[k] = v
            elseif type(k) == "number" and type(v) == "string" and new[v] ~= nil then new[v] = true end
        end
    end
    Config.SellItemRarities = new
end)

local SkillRarityDropdown = Tabs.Shop:AddDropdown("SellSkillRarity", {
    Title = "Skill Rarity",
    Values = {"common","uncommon","rare","epic","legendary","ultimate"},
    Multi = true,
    Default = {"common"},
})
SkillRarityDropdown:OnChanged(function(Value)
    local new = {common=false, uncommon=false, rare=false, epic=false, legendary=false, ultimate=false}
    if type(Value) == "table" then
        for k, v in pairs(Value) do
            if type(v) == "boolean" and new[k] ~= nil then new[k] = v
            elseif type(k) == "number" and type(v) == "string" and new[v] ~= nil then new[v] = true end
        end
    end
    Config.SellSkillRarities = new
end)

-- Noclip / AntiFling ผูกกับ Auto Farm อัตโนมัติ ไม่ต้องมี Toggle แยก
setNoclip(false)





SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
InterfaceManager:SetFolder("VoltScriptZ")
SaveManager:SetFolder("VoltScriptZ/DungeonQuest")

local section = Tabs.Settings:AddSection("Configuration")
section:AddInput("SaveManager_ConfigName", {Title = "Config name"})
section:AddDropdown("SaveManager_ConfigList", {Title = "Config list", Values = SaveManager:RefreshConfigList(), AllowNull = true})
section:AddButton({Title = "Create config", Callback = function()
    local name = SaveManager.Options.SaveManager_ConfigName.Value
    if name:gsub(" ", "") == "" then return end
    local success = SaveManager:Save(name)
    if success then
        SaveManager.Options.SaveManager_ConfigList:SetValues(SaveManager:RefreshConfigList())
        SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
    end
end})
section:AddButton({Title = "Delete config", Callback = function()
    local name = SaveManager.Options.SaveManager_ConfigList.Value
    if not name or name == "" then return end
    local paths = {
        SaveManager.Folder .. "/settings/" .. name .. ".json",
        SaveManager.Folder .. "/" .. name .. ".json",
        SaveManager.Folder .. "/settings/" .. name,
        SaveManager.Folder .. "/" .. name,
    }
    for _, path in ipairs(paths) do
        if isfile(path) then pcall(function() delfile(path) end) end
    end
    local autoloadPath = SaveManager.Folder .. "/settings/autoload.txt"
    if isfile(autoloadPath) then
        local cur = readfile(autoloadPath)
        if cur == name then pcall(function() delfile(autoloadPath) end) end
    end
    task.wait(0.05)
    SaveManager.Options.SaveManager_ConfigList:SetValues(SaveManager:RefreshConfigList())
    SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
end})
section:AddButton({Title = "Load config", Callback = function()
    local name = SaveManager.Options.SaveManager_ConfigList.Value
    SaveManager:Load(name)
end})
section:AddButton({Title = "Overwrite config", Callback = function()
    local name = SaveManager.Options.SaveManager_ConfigList.Value
    SaveManager:Save(name)
end})
section:AddButton({Title = "Refresh list", Callback = function()
    SaveManager.Options.SaveManager_ConfigList:SetValues(SaveManager:RefreshConfigList())
    SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
end})
local AutoloadButton = section:AddButton({Title = "Set as autoload", Description = "Current autoload config: none", Callback = function()
    local name = SaveManager.Options.SaveManager_ConfigList.Value
    writefile(SaveManager.Folder .. "/settings/autoload.txt", name)
    AutoloadButton:SetDesc("Current autoload config: " .. name)
end})
if isfile(SaveManager.Folder .. "/settings/autoload.txt") then
    local name = readfile(SaveManager.Folder .. "/settings/autoload.txt")
    AutoloadButton:SetDesc("Current autoload config: " .. name)
end
SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName" })

Window:SelectTab(1)
local _oldNotify = Fluent.Notify
Fluent.Notify = function() end
SaveManager:LoadAutoloadConfig()
Fluent.Notify = _oldNotify
task.spawn(function()
    task.wait(0.4)
    pcall(function() AutoStartToggle:SetValue(true) end)
    Config.AutoStart = true
end)
