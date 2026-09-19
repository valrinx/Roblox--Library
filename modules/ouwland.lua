--[[
    RAVEN HUB Module - Ouwland
    Game: Ouwland (PlaceId: 136406881576517, UniverseId: 5595353122)
    Version: v1.0.0

    Features:
    - 🏋️ Auto Training (Squat Rack, Pushups, Meditation, Boulder Push, Boulder Split, Cup Game, Aim Training)
    - ⚔️ Combat & Farm (Mob Farm, Boss Farm, Kill Aura, Attack Speed, Hitbox Expander)
    - 👁️ Visuals / ESP (Mobs & Bosses, Players, Chests & Snow Mounds, Shrines & Puzzles, Training Stations)
    - 🏃 Player Utilities (WalkSpeed, JumpPower, Infinite Stamina, Sun Damage Immunity, Anti-Ragdoll, Noclip, Fly)
    - 📍 Teleports (All Villages, Shrines, Puzzles, Training Spots, Active Bosses)
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
        Training = {},
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
        -- Combat & Farm
        AutoAttack = false,
        FastAttack = false,
        AutoFarmMobs = false,
        FarmTarget = "All Mobs", -- "All Mobs", "Demons", "Lancers", "Slayers", "Civilian", "Bosses"
        FarmMode = "Underground", -- "Underground", "Backstab", "Above"
        FarmDistance = 8,
        FarmAbove = 1.5,
        UndergroundDepth = 2.2,
        HitboxExpander = false,
        HitboxSize = 8,
        KillAura = false,
        KillAuraRadius = 20,
        KillAuraSnap = true,

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

        -- Visuals (ESP)
        ESPMobs = true,
        ESPPlayers = true,
        ESPChests = true,
        ESPPuzzles = true,
        ESPTraining = false,
        MaxESPDistance = 1200,

        -- Player Utilities
        CustomWalkSpeed = false,
        WalkSpeed = 28,
        CustomJumpPower = false,
        JumpPower = 65,
        InfiniteStamina = true,
        SunDamageImmunity = true,
        AntiRagdoll = true,
        Noclip = false,
        InfiniteJump = false,
        Fly = false,
        FlySpeed = 50,
        InstantPrompt = true,

        -- Teleport Stabilization
        TweenTeleport = false,
        TweenSpeed = 180,
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
                task.wait(0.05)
                prompt:InputHoldEnd()
            end
        end)
    end

    ----------------------------------------------------------------
    --  COMBAT & AUTO ATTACK SYSTEM
    ----------------------------------------------------------------
    --  COMBAT & AUTO ATTACK SYSTEM
    ----------------------------------------------------------------
    local InputHandler = nil
    pcall(function()
        InputHandler = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Client"):WaitForChild("Components"):WaitForChild("Client"):WaitForChild("InputHandler"))
    end)

    local CombatPresets = nil
    pcall(function()
        CombatPresets = require(ReplicatedStorage:WaitForChild("CAM"):WaitForChild("Global"):WaitForChild("Combat_presets"))
    end)

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

    -- Fast Attack speed controller via CombatPresets
    local originalPresetDefaults = {}
    local function setFastAttackMode(enabled)
        if not CombatPresets or not CombatPresets.Presets then return end
        for name, preset in pairs(CombatPresets.Presets) do
            if enabled then
                if not originalPresetDefaults[name] then
                    originalPresetDefaults[name] = {default = preset.default, final = preset.final}
                end
                preset.default = 0.12
                preset.final = 0.22
            elseif originalPresetDefaults[name] then
                preset.default = originalPresetDefaults[name].default
                preset.final = originalPresetDefaults[name].final
            end
        end
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
                task.delay(0.03, function()
                    pcall(function()
                        InputHandler.VirtualRelease("Combat")
                    end)
                end)
            end)
            return 0.25
        end

        return 0.3
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
    --  MOB SCANNING & AUTO FARM
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
                                local isBoss = (region.Name == "Misc") or (npc.Name:find("Datai") or npc.Name:find("Gyutai") or npc.Name:find("Reaper") or npc.Name:find("Sumari") or npc.Name:find("Saneri") or npc.Name:find("Zuko") or npc.Name:find("Hoyuzo") or npc.Name:find("Sabito") or npc.Name:find("Giyen") or npc.Name:find("Enru"))
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

    local function getClosestEnemy()
        local root = getRoot()
        if not root then return nil end

        local enemies = getActiveEnemies()
        local closest = nil
        local minDist = math.huge

        for _, enemy in ipairs(enemies) do
            local passFilter = true
            local lowerName = enemy.Name:lower()

            if State.FarmTarget == "Demons" and not lowerName:find("demon") then
                passFilter = false
            elseif State.FarmTarget == "Lancers" and not lowerName:find("lancer") then
                passFilter = false
            elseif State.FarmTarget == "Slayers" and not (lowerName:find("slayer") or lowerName:find("trainee") or lowerName:find("mizuno")) then
                passFilter = false
            elseif State.FarmTarget == "Civilian" and not lowerName:find("civilian") then
                passFilter = false
            elseif State.FarmTarget == "Bosses" and not enemy.IsBoss then
                passFilter = false
            end

            if passFilter then
                local dist = (root.Position - enemy.Root.Position).Magnitude
                if dist < minDist then
                    minDist = dist
                    closest = enemy
                end
            end
        end
        return closest
    end

    -- Auto Farm Loop (Safe Underground / Backstab / Top Anchor + Jitter-Free Lock)
    task.spawn(function()
        while not isDestroyed do
            if State.AutoFarmMobs and isAlive() then
                local target = getClosestEnemy()
                local root = getRoot()

                if target and root and target.Root and target.Humanoid.Health > 0 then
                    local targetPos = target.Root.Position
                    local lookAt = targetPos
                    local farmPos

                    if State.FarmMode == "Underground" then
                        -- Position directly under the mob (2.2 studs default)
                        local depth = math.clamp(State.UndergroundDepth or 2.2, 1.0, 4.0)
                        farmPos = targetPos - Vector3.new(0, depth, 0)
                        lookAt = targetPos
                    elseif State.FarmMode == "Above" then
                        farmPos = targetPos + Vector3.new(0, math.clamp(State.FarmAbove, 1, 3.5), 0)
                        lookAt = targetPos
                    else
                        -- Default: Backstab anchor (2.0 studs behind target)
                        farmPos = targetPos - target.Root.CFrame.LookVector * 2.0 + Vector3.new(0, math.clamp(State.FarmAbove, -0.5, 2.5), 0)
                        lookAt = targetPos
                    end

                    currentFarmLockCF = CFrame.lookAt(farmPos, lookAt)
                    root.CFrame = currentFarmLockCF
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero

                    -- Attack mob
                    local cd = doPunch()
                    local waitTime = (State.FastAttack and 0.12) or (cd and cd > 0.1 and cd) or 0.28
                    task.wait(waitTime)
                else
                    currentFarmLockCF = nil
                    task.wait(0.4)
                end
            else
                currentFarmLockCF = nil
                task.wait(0.4)
            end
        end
    end)

    -- Kill Aura Loop (Snap Melee & Directional Cone Hits)
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

                        -- Snap to target if enabled and within radius
                        if State.KillAuraSnap and dist > 3.5 then
                            local snapPos = enemyPos - closest.Root.CFrame.LookVector * 2.0
                            root.CFrame = CFrame.lookAt(snapPos, enemyPos)
                            root.AssemblyLinearVelocity = Vector3.zero
                            task.wait(0.04)
                        else
                            local targetLook = Vector3.new(enemyPos.X, root.Position.Y, enemyPos.Z)
                            root.CFrame = CFrame.lookAt(root.Position, targetLook)
                        end

                        local cd = doPunch()
                        local waitTime = (State.FastAttack and 0.12) or (cd and cd > 0.1 and cd) or 0.28
                        task.wait(waitTime)
                    else
                        task.wait(0.3)
                    end
                else
                    task.wait(0.5)
                end
            else
                task.wait(0.5)
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

                        if prompt and prompt.Enabled and dist <= State.ChestFarmRadius then
                            -- Teleport directly onto chest and trigger
                            root.CFrame = cf + Vector3.new(0, 2.5, 0)
                            root.AssemblyLinearVelocity = Vector3.zero
                            task.wait(0.15)
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

    ----------------------------------------------------------------
    --  AUTO TRAINING MINIGAMES (ALL STATIONS SOLVER)
    ----------------------------------------------------------------
    local function solveTrainingMinigames()
        if not State.AutoTraining then return end

        local playerGui = LP:FindFirstChild("PlayerGui")
        local misc = playerGui and playerGui:FindFirstChild("Misc")
        local root = getRoot()

        -- 1. Check Squat / BarKeepup (Balance Bar)
        if State.AutoSquat and misc then
            local barKeepup = misc:FindFirstChild("BarKeepup") or misc:FindFirstChild("Minigame")
            if barKeepup and barKeepup:IsA("ScreenGui") and barKeepup.Enabled then
                pcall(function()
                    VirtualUser:Button1Down(Vector2.new(0, 0), Camera.CFrame)
                    task.wait(0.04)
                    VirtualUser:Button1Up(Vector2.new(0, 0), Camera.CFrame)
                end)
            end
        end

        -- 2. Cup Game Auto Solver (Clicks ball cup or triggers win signal)
        if State.AutoCupGame then
            local cupFolder = Workspace:FindFirstChild("Training") and Workspace.Training:FindFirstChild("Cup Game")
            if cupFolder then
                local ball = cupFolder:FindFirstChild("Ball", true)
                if ball and ball:IsA("BasePart") then
                    local prompt = cupFolder:FindFirstChildWhichIsA("ProximityPrompt", true)
                    if prompt and prompt.Enabled then
                        triggerPrompt(prompt)
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

        -- 4. Target Shooting / Aim Trainer
        if State.AutoTargetShooting and misc then
            local targetGui = misc:FindFirstChild("TargetShooting") or misc:FindFirstChild("AimTraining")
            if targetGui and targetGui:IsA("ScreenGui") and targetGui.Enabled then
                pcall(function()
                    VirtualUser:Button1Down(Vector2.new(0, 0), Camera.CFrame)
                    task.wait(0.05)
                    VirtualUser:Button1Up(Vector2.new(0, 0), Camera.CFrame)
                end)
            end
        end
    end

    ----------------------------------------------------------------
    --  PLAYER UTILITIES (IMMUNITY, STAMINA, ETC.)
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
        end

        -- Infinite Stamina
        if State.InfiniteStamina then
            pcall(function()
                local values = ReplicatedStorage:FindFirstChild("Player_Service")
                    and ReplicatedStorage.Player_Service:FindFirstChild("Values")
                    and ReplicatedStorage.Player_Service.Values:FindFirstChild(LP.Name)
                if values then
                    local stamina = values:FindFirstChild("Stamina")
                    if stamina and stamina:IsA("ValueBase") then
                        stamina.Value = 100
                    end
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

    -- Noclip & Stable Farm Lock (Rock-solid positioning, zero camera shake, zero rubberband)
    connect(RunService.Stepped, function()
        local isUnderground = (State.AutoFarmMobs and State.FarmMode == "Underground")
        if State.Noclip or isUnderground then
            local char = getChar()
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end

        if currentFarmLockCF and State.AutoFarmMobs and isAlive() then
            local root = getRoot()
            if root then
                root.CFrame = currentFarmLockCF
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)

    -- Fly System
    local flyBodyGyro, flyBodyVelocity
    local function setFly(enabled)
        local root = getRoot()
        if not root then return end

        if enabled then
            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.P = 9e4
            flyBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyBodyGyro.CFrame = root.CFrame
            flyBodyGyro.Parent = root

            flyBodyVelocity = Instance.new("BodyVelocity")
            flyBodyVelocity.Velocity = Vector3.zero
            flyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBodyVelocity.Parent = root
        else
            if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
            if flyBodyVelocity then flyBodyVelocity:Destroy(); flyBodyVelocity = nil end
        end
    end

    local function updateFly()
        if not State.Fly or not flyBodyVelocity or not flyBodyGyro then return end
        local root = getRoot()
        if not root then return end

        flyBodyGyro.CFrame = Camera.CFrame
        local moveDir = Vector3.zero

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            moveDir = moveDir + (Camera.CFrame.LookVector)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = moveDir - (Camera.CFrame.LookVector)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            moveDir = moveDir - (Camera.CFrame.RightVector)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = moveDir + (Camera.CFrame.RightVector)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDir = moveDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            moveDir = moveDir - Vector3.new(0, 1, 0)
        end

        if moveDir.Magnitude > 0 then
            flyBodyVelocity.Velocity = moveDir.Unit * State.FlySpeed
        else
            flyBodyVelocity.Velocity = Vector3.zero
        end
    end

    ----------------------------------------------------------------
    --  DRAWING API ESP ENGINE
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

            -- Cleanup dead/removed mobs
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

        -- 4. Puzzles & Weapon Shrines ESP
        if State.ESPPuzzles then
            local puzzlesFolder = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("Puzzles")
            local currentKeys = {}
            if puzzlesFolder then
                for _, puzzle in ipairs(puzzlesFolder:GetChildren()) do
                    currentKeys[puzzle] = true
                    local part = puzzle:IsA("BasePart") and puzzle or puzzle:FindFirstChildWhichIsA("BasePart")
                    if part then
                        local dist = math.floor((Camera.CFrame.Position - part.Position).Magnitude)
                        if dist <= State.MaxESPDistance then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                            local entry = DrawingObjects.Puzzles[puzzle]
                            if not entry then
                                local txt = Drawing.new("Text")
                                txt.Size = 12
                                txt.Center = true
                                txt.Outline = true
                                txt.Color = Color3.fromRGB(230, 130, 255)
                                entry = { Text = txt }
                                DrawingObjects.Puzzles[puzzle] = entry
                            end

                            if onScreen then
                                entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                entry.Text.Text = string.format("✨ [Shrine/Puzzle] %s [%dm]", puzzle.Name, dist)
                                entry.Text.Visible = true
                            else
                                entry.Text.Visible = false
                            end
                        end
                    end
                end
            end

            for puzzle, entry in pairs(DrawingObjects.Puzzles) do
                if not currentKeys[puzzle] then
                    if entry.Text then pcall(function() entry.Text:Remove() end) end
                    DrawingObjects.Puzzles[puzzle] = nil
                end
            end
        else
            clearDrawings(DrawingObjects.Puzzles)
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
                local duration = math.clamp(dist / math.max(State.TweenSpeed or 180, 50), 0.2, 5.0)

                -- Temporary noclip during tween
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
                -- Instant Stable TP (Rock-solid, zero camera jitter or rubberbanding)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero

                if hum then
                    hum:ChangeState(Enum.HumanoidStateType.Physics)
                end

                root.CFrame = destCF
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero

                -- Hold position for 3 frames to let physics and streaming catch up
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

    -- TAB 2: ⚔️ Combat & Auto Farm
    local CombatTab = Window:CreateTab("Combat", "combat")
    CombatTab:CreateSection("Auto Attack & Aura")

    CombatTab:CreateToggle({
        Name = "Fast Attack Mode",
        CurrentValue = State.FastAttack,
        Flag = "OWL_FastAttack",
        Callback = function(v)
            State.FastAttack = v
            setFastAttackMode(v)
        end,
    })

    CombatTab:CreateToggle({
        Name = "Kill Aura (Radius Attack)",
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

    CombatTab:CreateSection("Mob & Boss Farm")

    CombatTab:CreateToggle({
        Name = "Auto Farm Mobs",
        CurrentValue = State.AutoFarmMobs,
        Flag = "OWL_AutoFarm",
        Callback = function(v) State.AutoFarmMobs = v end,
    })

    CombatTab:CreateDropdown({
        Name = "Farm Position Mode",
        Options = {"Underground", "Backstab", "Above"},
        CurrentOption = State.FarmMode,
        Flag = "OWL_FarmMode",
        Callback = function(v) State.FarmMode = v end,
    })

    CombatTab:CreateSlider({
        Name = "Underground Depth (Studs)",
        Min = 1.0,
        Max = 4.0,
        Default = State.UndergroundDepth,
        Increment = 0.1,
        Flag = "OWL_UnderDepth",
        Callback = function(v) State.UndergroundDepth = v end,
    })

    CombatTab:CreateDropdown({
        Name = "Farm Target Filter",
        Options = {"All Mobs", "Demons", "Lancers", "Slayers", "Civilian", "Bosses"},
        CurrentOption = State.FarmTarget,
        Flag = "OWL_FarmTarget",
        Callback = function(v) State.FarmTarget = v end,
    })

    CombatTab:CreateSlider({
        Name = "Hover Height (Above/Backstab)",
        Min = -1,
        Max = 4,
        Default = State.FarmAbove,
        Increment = 0.5,
        Flag = "OWL_FarmAbove",
        Callback = function(v) State.FarmAbove = v end,
    })

    CombatTab:CreateSection("Hitbox Modifiers")

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
        Max = 18,
        Default = State.HitboxSize,
        Increment = 1,
        Flag = "OWL_HitboxSize",
        Callback = function(v) State.HitboxSize = v end,
    })

    -- TAB 3: 👁️ Visuals (ESP)
    local VisualTab = Window:CreateTab("Visuals", "visuals")
    VisualTab:CreateSection("Entity ESP")

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

    VisualTab:CreateSection("World & Puzzle ESP")

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
        Name = "Auto Loot Chests & Snow Mounds",
        CurrentValue = State.AutoChests,
        Flag = "OWL_AutoChests",
        Callback = function(v) State.AutoChests = v end,
    })

    VisualTab:CreateToggle({
        Name = "Weapon Shrines & Puzzles ESP",
        CurrentValue = State.ESPPuzzles,
        Flag = "OWL_ESPPuzzles",
        Callback = function(v)
            State.ESPPuzzles = v
            if not v then clearDrawings(DrawingObjects.Puzzles) end
        end,
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

    -- TAB 4: 🏃 Player & Movement
    local PlayerTab = Window:CreateTab("Player", "defense")
    PlayerTab:CreateSection("Character Buffs")

    PlayerTab:CreateToggle({
        Name = "Infinite Stamina",
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

    -- TAB 5: 📍 Teleports
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

    TeleportTab:CreateSection("Regions & Towns")

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

    -- Order & Sort Tabs
    pcall(function()
        if Window.SortTabs then
            Window:SortTabs({"Overview", "Training", "Combat", "Visuals", "Player", "Teleport", "Settings"})
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
            restoreHitboxes()

            clearDrawings(DrawingObjects.Mobs)
            clearDrawings(DrawingObjects.Players)
            clearDrawings(DrawingObjects.Chests)
            clearDrawings(DrawingObjects.Puzzles)
            clearDrawings(DrawingObjects.Training)

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
