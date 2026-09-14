-- ============================================================
--   RAVEN HUB  |  Fight, Fight, Fight! (Tactical Army Overlord)
--   MacLib UI + 100% Drawing API + Dual-Mode Mounted Flight
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local Workspace = game:GetService("Workspace")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    -- Clean up previous instance if running
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_FIGHT_FIGHT_FIGHT) == "table"
        and type(environment.__RAVEN_FIGHT_FIGHT_FIGHT.Destroy) == "function" then
        pcall(environment.__RAVEN_FIGHT_FIGHT_FIGHT.Destroy)
    end

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    local running = true
    local connections = {}

    -- Remotes
    local Shared = ReplicatedStorage:FindFirstChild("Shared")
    local Remotes = Shared and Shared:FindFirstChild("Remotes")

    local PlayerCombatRequest = Remotes and Remotes:FindFirstChild("PlayerCombatRequest")
    local RushRequest = Remotes and Remotes:FindFirstChild("RushRequest")
    local AimArrowFire = Remotes and Remotes:FindFirstChild("AimArrowFire")
    local AimVolleyState = Remotes and Remotes:FindFirstChild("AimVolleyState")
    local FormationPlacementRequest = Remotes and Remotes:FindFirstChild("FormationPlacementRequest")
    local DeathRetreatRequest = Remotes and Remotes:FindFirstChild("DeathRetreatRequest")
    local MountRequest = Remotes and Remotes:FindFirstChild("MountRequest")

    -- Settings
    local settings = {
        -- Combat
        killAura = false,
        auraRange = 32,
        attackCooldown = 0.28,
        faceTarget = true,
        targetPlayers = true,
        targetTroops = true,
        autoParry = false,
        parryDistance = 18,
        autoDodge = false,
        dodgeHpThreshold = 25,
        autoHeal = false,
        healHpThreshold = 40,

        -- Troops
        autoRush = false,
        autoRushRange = 75,
        autoTroopAttack = false,
        troopAttackRange = 80,
        autoRetreat = false,
        autoVolley = false,
        volleyRange = 300,

        -- Movement and Speed Overclock
        flightEnabled = false,
        flightSpeed = 55,
        speedHackEnabled = false,
        customWalkSpeed = 35,
        customRunSpeed = 55,
        infiniteStamina = false,
        horseNitroEnabled = false,
        customHorseSpeed = 85,
        infiniteMountStamina = false,

        -- Visuals (Drawing API)
        playerEsp = false,
        troopEsp = false,
        espBoxes = true,
        espHealth = true,
        espDistance = true,
        supplyPointEsp = false,
        maxEspDistance = 1500,

        -- Safety
        integrityShield = true,
    }

    local myUserId = tostring(localPlayer.UserId)
    local lastAttackTick = 0
    local isBlocking = false
    local lastRushTick = 0
    local lastVolleyTick = 0
    local lastTroopAttackTick = 0

    local function connect(signal, callback)
        local connection = signal:Connect(callback)
        table.insert(connections, connection)
        return connection
    end

    -- ============================================================
    --   HELPER FUNCTIONS & CONTROLLERS
    -- ============================================================

    local function getLocalRoot()
        local char = localPlayer.Character
        return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    end

    local function getLocalHumanoid()
        local char = localPlayer.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function getLocalHorse()
        local mounts = Workspace:FindFirstChild("Mounts")
        if not mounts then return nil end
        return mounts:FindFirstChild("Horse_" .. localPlayer.Name)
    end

    local function isMounted()
        return localPlayer:GetAttribute("MountState") == "Mounted"
    end

    local function getActiveMovementRoot()
        if isMounted() then
            local horse = getLocalHorse()
            if horse then
                return horse.PrimaryPart or horse:FindFirstChild("HumanoidRootPart") or horse:FindFirstChild("Hitbox")
            end
        end
        return getLocalRoot()
    end

    local function getMatchUI()
        local pGui = localPlayer:FindFirstChild("PlayerGui")
        return pGui and pGui:FindFirstChild("MatchUI")
    end

    local function getPlayerActionButton(name)
        local matchUI = getMatchUI()
        if not matchUI then return nil end
        local playerUI = matchUI:FindFirstChild("PlayerUI")
        local list = playerUI and playerUI:FindFirstChild("List")
        return list and list:FindFirstChild(name)
    end

    local function getTroopActionButton(name)
        local matchUI = getMatchUI()
        if not matchUI then return nil end
        local troop = matchUI:FindFirstChild("Troop")
        local states = troop and troop:FindFirstChild("TroopStates")
        return states and states:FindFirstChild(name)
    end

    local function triggerActionButton(button)
        if not button then return false end
        if typeof(firesignal) == "function" then
            firesignal(button.Activated)
            return true
        elseif typeof(getconnections) == "function" then
            for _, conn in ipairs(getconnections(button.Activated)) do
                pcall(conn.Fire, conn)
            end
            return true
        end
        return false
    end

    -- ============================================================
    --   TARGETING & SCANNING ENGINE
    -- ============================================================

    local function getEnemyTeam()
        local myTeam = localPlayer:GetAttribute("SelectedTeam")
        if not myTeam or myTeam == "" then
            if localPlayer.Team then
                myTeam = localPlayer.Team.Name
            end
        end
        if not myTeam or myTeam == "" then
            myTeam = "Attackers"
        end
        return (myTeam == "Attackers") and "Defenders" or "Attackers", myTeam
    end

    local function getEnemyTroopFolders()
        local enemyFolders = {}
        local troopsRoot = Workspace:FindFirstChild("Troops")
        if not troopsRoot then return enemyFolders end

        local enemyTeam, myTeam = getEnemyTeam()

        for _, folder in ipairs(troopsRoot:GetChildren()) do
            if folder.Name ~= myUserId then
                if folder.Name:find("AI_" .. enemyTeam) then
                    table.insert(enemyFolders, folder)
                else
                    local uid = tonumber(folder.Name)
                    if uid and uid ~= localPlayer.UserId then
                        local p = Players:GetPlayerByUserId(uid)
                        if p then
                            local pTeam = p:GetAttribute("SelectedTeam") or (p.Team and p.Team.Name)
                            if pTeam == enemyTeam then
                                table.insert(enemyFolders, folder)
                            end
                        end
                    end
                end
            end
        end
        return enemyFolders
    end

    local function getClosestTarget(maxDist)
        local root = getActiveMovementRoot()
        if not root then return nil, nil, false end
        local rootPos = root.Position

        local closestTarget = nil
        local closestDist = maxDist or math.huge
        local isPlayer = false

        local enemyTeam, _ = getEnemyTeam()

        -- 1. Check Enemy Players
        if settings.targetPlayers then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Character then
                    local pTeam = player:GetAttribute("SelectedTeam") or (player.Team and player.Team.Name)
                    if pTeam == enemyTeam then
                        local pRoot = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
                        local hum = player.Character:FindFirstChildOfClass("Humanoid")
                        if pRoot and hum and hum.Health > 0 then
                            local dist = (pRoot.Position - rootPos).Magnitude
                            if dist < closestDist then
                                closestDist = dist
                                closestTarget = pRoot
                                isPlayer = true
                            end
                        end
                    end
                end
            end
        end

        -- 2. Check Enemy Troops
        if settings.targetTroops then
            for _, folder in ipairs(getEnemyTroopFolders()) do
                for _, troop in ipairs(folder:GetChildren()) do
                    if troop:IsA("Model") and not troop.Name:find("_Visual") then
                        local tRoot = troop:FindFirstChild("HumanoidRootPart") or troop.PrimaryPart
                        local hum = troop:FindFirstChildOfClass("Humanoid")
                        if tRoot and hum and hum.Health > 0 then
                            local dist = (tRoot.Position - rootPos).Magnitude
                            if dist < closestDist then
                                closestDist = dist
                                closestTarget = tRoot
                                isPlayer = false
                            end
                        end
                    end
                end
            end
        end

        return closestTarget, closestDist, isPlayer
    end

    -- ============================================================
    --   TACTICAL ACTIONS & MACROS
    -- ============================================================

    local function airDropTroops()
        local target, dist = getClosestTarget(500)
        if not target then return end

        if FormationPlacementRequest then
            local snapCFrame = target.CFrame * CFrame.new(0, 0, 5)
            FormationPlacementRequest:FireServer("Line", snapCFrame)
        end
    end

    local function triggerRushNuke()
        local rushBtn = getTroopActionButton("Rush")
        if rushBtn then
            triggerActionButton(rushBtn)
        elseif RushRequest then
            local root = getActiveMovementRoot()
            local target, dist = getClosestTarget(settings.autoRushRange or 100)
            if root and target then
                local origin = root.Position
                local targetPos = target.Position
                local direction = (targetPos - origin).Unit
                RushRequest:FireServer(direction, targetPos)
            end
        end
    end

    local function triggerTroopAttack()
        local atkBtn = getTroopActionButton("Attack")
        if atkBtn then
            triggerActionButton(atkBtn)
        end
    end

    local function triggerTroopFollow()
        local fBtn = getTroopActionButton("Follow")
        if fBtn then
            triggerActionButton(fBtn)
        end
    end

    local function triggerTroopHold()
        local hBtn = getTroopActionButton("Hold")
        if hBtn then
            triggerActionButton(hBtn)
        end
    end

    local function triggerArrowVolley()
        local aimBtn = getTroopActionButton("Aim")
        if aimBtn then
            triggerActionButton(aimBtn)
        elseif AimArrowFire and AimVolleyState then
            local target, dist = getClosestTarget(settings.volleyRange or 350)
            if target then
                AimVolleyState:FireServer(true)
                AimArrowFire:FireServer(target.Position + Vector3.new(0, 2, 0))
                task.delay(0.5, function()
                    if running and AimVolleyState then
                        AimVolleyState:FireServer(false)
                    end
                end)
            end
        end
    end

    local function triggerAttackSwing(target)
        if settings.faceTarget and target then
            local char = localPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                local lookPos = Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
                root.CFrame = CFrame.lookAt(root.Position, lookPos)
            end
        end

        local attackBtn = getPlayerActionButton("Attack")
        if attackBtn then
            triggerActionButton(attackBtn)
        elseif PlayerCombatRequest then
            PlayerCombatRequest:FireServer("Attack")
        end
    end

    local function setBlockState(shouldBlock)
        if isBlocking == shouldBlock then return end
        isBlocking = shouldBlock
        if PlayerCombatRequest then
            PlayerCombatRequest:FireServer("Block", shouldBlock)
        end
    end

    -- ============================================================
    --   MAIN AUTOMATION & COMBAT LOOP
    -- ============================================================

    connect(RunService.RenderStepped, function(deltaTime)
        if not running then return end
        local root = getActiveMovementRoot()
        local hum = getLocalHumanoid()
        if not root or not hum then return end

        local target, dist, isPlayer = getClosestTarget(math.max(settings.auraRange, settings.parryDistance))

        -- 1. Auto Parry / Smart Block
        if settings.autoParry then
            if target and dist <= settings.parryDistance then
                if not isBlocking then
                    setBlockState(true)
                end
            else
                if isBlocking then
                    setBlockState(false)
                end
            end
        end

        -- 2. Kill Aura Attack
        if settings.killAura and target and dist <= settings.auraRange then
            local now = os.clock()
            if now - lastAttackTick >= settings.attackCooldown then
                lastAttackTick = now
                if isBlocking then
                    setBlockState(false)
                end
                triggerAttackSwing(target)
            end
        end

        -- 3. Auto Dodge Roll on Critical HP (only on foot)
        if settings.autoDodge and not isMounted() and hum.Health > 0 and (hum.Health / hum.MaxHealth) * 100 <= settings.dodgeHpThreshold then
            local isRolling = localPlayer:GetAttribute("IsRolling")
            if not isRolling then
                local rollBtn = getPlayerActionButton("Roll")
                if rollBtn then
                    triggerActionButton(rollBtn)
                elseif PlayerCombatRequest then
                    PlayerCombatRequest:FireServer("Roll")
                end
            end
        end

        -- 4. Auto Heal
        if settings.autoHeal and hum.Health > 0 and (hum.Health / hum.MaxHealth) * 100 <= settings.healHpThreshold then
            local healCd = localPlayer:GetAttribute("HealCooldownEndsAt") or 0
            if os.clock() >= healCd then
                local healBtn = getPlayerActionButton("Heal")
                if healBtn then
                    triggerActionButton(healBtn)
                end
            end
        end

        -- 5. Auto Rush on Proximity
        if settings.autoRush and target and dist <= settings.autoRushRange then
            local now = os.clock()
            if now - lastRushTick >= 3.0 then
                lastRushTick = now
                triggerRushNuke()
            end
        end

        -- 6. Auto Troop Attack
        if settings.autoTroopAttack and target and dist <= settings.troopAttackRange then
            local now = os.clock()
            if now - lastTroopAttackTick >= 2.5 then
                lastTroopAttackTick = now
                triggerTroopAttack()
            end
        end

        -- 7. Auto Archer Volley
        if settings.autoVolley and target and dist <= settings.volleyRange then
            local now = os.clock()
            if now - lastVolleyTick >= 4.5 then
                lastVolleyTick = now
                triggerArrowVolley()
            end
        end

        -- 8. Auto Retreat Low HP Troops
        if settings.autoRetreat and DeathRetreatRequest then
            local totalHp = localPlayer:GetAttribute("CurrentUnitTotalHealth") or 0
            local maxHp = localPlayer:GetAttribute("CurrentUnitTotalMaxHealth") or 1
            if maxHp > 0 and (totalHp / maxHp) <= 0.15 and totalHp > 0 then
                DeathRetreatRequest:FireServer()
            end
        end

        -- 9. Speed Hack and Infinite Stamina
        if settings.speedHackEnabled then
            if localPlayer:GetAttribute("WalkSpeed") ~= settings.customWalkSpeed then
                localPlayer:SetAttribute("WalkSpeed", settings.customWalkSpeed)
            end
            if localPlayer:GetAttribute("RunSpeed") ~= settings.customRunSpeed then
                localPlayer:SetAttribute("RunSpeed", settings.customRunSpeed)
            end
            if hum and hum.WalkSpeed < settings.customWalkSpeed then
                hum.WalkSpeed = settings.customWalkSpeed
            end
        end

        if settings.infiniteStamina then
            local stamina = localPlayer:GetAttribute("Stamina")
            if stamina and stamina < 95 then
                localPlayer:SetAttribute("Stamina", 100)
            end
        end

        -- 10. Horse Nitro and Mount Stamina Guard
        if settings.horseNitroEnabled then
            if localPlayer:GetAttribute("MountRunSpeed") ~= settings.customHorseSpeed then
                localPlayer:SetAttribute("MountRunSpeed", settings.customHorseSpeed)
            end
            local halfSpeed = math.floor(settings.customHorseSpeed * 0.45)
            if localPlayer:GetAttribute("MountWalkSpeed") ~= halfSpeed then
                localPlayer:SetAttribute("MountWalkSpeed", halfSpeed)
            end
        end

        if settings.infiniteMountStamina then
            local stamina = localPlayer:GetAttribute("MountStamina")
            if stamina and stamina < 95 then
                localPlayer:SetAttribute("MountStamina", 105)
            end
        end

        -- 10. Flight Engine (Seamless Mounted & On-Foot)
        if settings.flightEnabled then
            local char = localPlayer.Character
            local horse = isMounted() and getLocalHorse()
            local targetModel = (isMounted() and horse) or char
            local flightRoot = targetModel and (targetModel.PrimaryPart or targetModel:FindFirstChild("HumanoidRootPart"))

            if flightRoot then
                flightRoot.AssemblyLinearVelocity = Vector3.zero

                local camCF = camera.CFrame
                local moveDir = Vector3.zero

                if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camCF.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camCF.LookVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camCF.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camCF.RightVector end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end

                if moveDir.Magnitude > 0 then
                    local delta = moveDir.Unit * (settings.flightSpeed * deltaTime)
                    targetModel:PivotTo(targetModel:GetPivot() + delta)
                end
            end
        end
    end)

    -- ============================================================
    --   DRAWING API ESP (100% CoreGui Clean)
    -- ============================================================

    local espCache = {}

    local function removeEspEntry(id)
        local entry = espCache[id]
        if entry then
            if entry.Box then pcall(function() entry.Box:Remove() end) end
            if entry.Text then pcall(function() entry.Text:Remove() end) end
            espCache[id] = nil
        end
    end

    local function clearAllEsp()
        for id, _ in pairs(espCache) do
            removeEspEntry(id)
        end
        table.clear(espCache)
    end

    connect(RunService.RenderStepped, function()
        if not running or not Drawing then return end
        if not settings.playerEsp and not settings.troopEsp and not settings.supplyPointEsp then
            clearAllEsp()
            return
        end

        local root = getActiveMovementRoot()
        local rootPos = root and root.Position or camera.CFrame.Position
        local activeIds = {}
        local enemyTeam, _ = getEnemyTeam()

        -- 1. Player ESP
        if settings.playerEsp then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Character then
                    local pTeam = player:GetAttribute("SelectedTeam") or (player.Team and player.Team.Name)
                    local isEnemy = (pTeam == enemyTeam)
                    local pRoot = player.Character:FindFirstChild("HumanoidRootPart") or player.Character.PrimaryPart
                    local hum = player.Character:FindFirstChildOfClass("Humanoid")

                    if pRoot and hum and hum.Health > 0 then
                        local dist = (pRoot.Position - rootPos).Magnitude
                        if dist <= settings.maxEspDistance then
                            local id = "P_" .. player.Name
                            activeIds[id] = true
                            local screenPos, onScreen = camera:WorldToViewportPoint(pRoot.Position)

                            local entry = espCache[id]
                            if not entry then
                                entry = {
                                    Text = Drawing.new("Text"),
                                    Box = Drawing.new("Square")
                                }
                                entry.Text.Size = 13
                                entry.Text.Center = true
                                entry.Text.Outline = true
                                entry.Box.Thickness = 1
                                entry.Box.Filled = false
                                espCache[id] = entry
                            end

                            local col = isEnemy and Color3.fromRGB(255, 65, 65) or Color3.fromRGB(65, 160, 255)
                            entry.Text.Color = col
                            entry.Box.Color = col

                            if onScreen then
                                local hp = math.floor(hum.Health)
                                local text = player.DisplayName
                                if settings.espHealth then text = text .. " [" .. hp .. " HP]" end
                                if settings.espDistance then text = text .. " (" .. math.floor(dist) .. "m)" end

                                entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y - 22)
                                entry.Text.Text = text
                                entry.Text.Visible = true

                                if settings.espBoxes then
                                    local boxHeight = math.clamp(1200 / dist, 18, 90)
                                    local boxWidth = boxHeight * 0.65
                                    entry.Box.Size = Vector2.new(boxWidth, boxHeight)
                                    entry.Box.Position = Vector2.new(screenPos.X - boxWidth / 2, screenPos.Y - boxHeight / 2)
                                    entry.Box.Visible = true
                                else
                                    entry.Box.Visible = false
                                end
                            else
                                entry.Text.Visible = false
                                entry.Box.Visible = false
                            end
                        end
                    end
                end
            end
        end

        -- 2. Troop ESP
        if settings.troopEsp then
            for _, folder in ipairs(getEnemyTroopFolders()) do
                for _, troop in ipairs(folder:GetChildren()) do
                    if troop:IsA("Model") and not troop.Name:find("_Visual") then
                        local tRoot = troop:FindFirstChild("HumanoidRootPart") or troop.PrimaryPart
                        local hum = troop:FindFirstChildOfClass("Humanoid")
                        if tRoot and hum and hum.Health > 0 then
                            local dist = (tRoot.Position - rootPos).Magnitude
                            if dist <= math.min(settings.maxEspDistance, 800) then
                                local id = "T_" .. folder.Name .. "_" .. troop.Name
                                activeIds[id] = true
                                local screenPos, onScreen = camera:WorldToViewportPoint(tRoot.Position)

                                local entry = espCache[id]
                                if not entry then
                                    entry = {
                                        Text = Drawing.new("Text"),
                                        Box = Drawing.new("Square")
                                    }
                                    entry.Text.Size = 11
                                    entry.Text.Center = true
                                    entry.Text.Outline = true
                                    entry.Text.Color = Color3.fromRGB(255, 120, 50)
                                    entry.Box.Thickness = 1
                                    entry.Box.Filled = false
                                    entry.Box.Color = Color3.fromRGB(255, 120, 50)
                                    espCache[id] = entry
                                end

                                if onScreen then
                                    local hp = math.floor(hum.Health)
                                    local text = "Troop [" .. hp .. " HP]"
                                    if settings.espDistance then text = text .. " (" .. math.floor(dist) .. "m)" end

                                    entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y - 18)
                                    entry.Text.Text = text
                                    entry.Text.Visible = true

                                    if settings.espBoxes then
                                        local boxHeight = math.clamp(900 / dist, 12, 60)
                                        local boxWidth = boxHeight * 0.6
                                        entry.Box.Size = Vector2.new(boxWidth, boxHeight)
                                        entry.Box.Position = Vector2.new(screenPos.X - boxWidth / 2, screenPos.Y - boxHeight / 2)
                                        entry.Box.Visible = true
                                    else
                                        entry.Box.Visible = false
                                    end
                                else
                                    entry.Text.Visible = false
                                    entry.Box.Visible = false
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 3. Supply Point ESP
        if settings.supplyPointEsp then
            local mapRoot = Workspace:FindFirstChild("Map") or Workspace:FindFirstChild("Lobby")
            if mapRoot then
                for _, obj in ipairs(mapRoot:GetDescendants()) do
                    if obj:IsA("BasePart") and (obj.Name:find("SupplyPoint") or obj.Name:find("Objective") or obj.Name:find("Gate")) then
                        local dist = (obj.Position - rootPos).Magnitude
                        if dist <= settings.maxEspDistance then
                            local id = "SP_" .. obj:GetDebugId()
                            activeIds[id] = true
                            local screenPos, onScreen = camera:WorldToViewportPoint(obj.Position)

                            local entry = espCache[id]
                            if not entry then
                                entry = { Text = Drawing.new("Text") }
                                entry.Text.Size = 12
                                entry.Text.Center = true
                                entry.Text.Outline = true
                                entry.Text.Color = Color3.fromRGB(255, 220, 60)
                                espCache[id] = entry
                            end

                            if onScreen then
                                entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                entry.Text.Text = string.format("[%s] (%dm)", obj.Name, math.floor(dist))
                                entry.Text.Visible = true
                            else
                                entry.Text.Visible = false
                            end
                        end
                    end
                end
            end
        end

        -- Purge stale drawings
        for id, _ in pairs(espCache) do
            if not activeIds[id] then
                removeEspEntry(id)
            end
        end
    end)

    -- ============================================================
    --   MACLIB UI SETUP
    -- ============================================================

    -- Tab 1: Combat
    local CombatTab = Window:CreateTab("Combat", "swords")
    CombatTab:CreateSection("Melee Combat Aura", "Left")

    CombatTab:CreateToggle({
        Name = "Kill Aura (Auto Attack)",
        CurrentValue = settings.killAura,
        Flag = "FFF_KillAura",
        Callback = function(value)
            settings.killAura = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Aura Reach Range",
        Range = {12, 60},
        Increment = 2,
        Suffix = " studs",
        CurrentValue = settings.auraRange,
        Flag = "FFF_AuraRange",
        Callback = function(value)
            settings.auraRange = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Attack Delay Cooldown",
        Range = {0.1, 0.5},
        Increment = 0.02,
        Suffix = "s",
        CurrentValue = settings.attackCooldown,
        Flag = "FFF_AttackDelay",
        Callback = function(value)
            settings.attackCooldown = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Face Target on Swing",
        CurrentValue = settings.faceTarget,
        Flag = "FFF_FaceTarget",
        Callback = function(value)
            settings.faceTarget = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Target Enemy Players",
        CurrentValue = settings.targetPlayers,
        Flag = "FFF_TargetPlayers",
        Callback = function(value)
            settings.targetPlayers = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Target Enemy Troops",
        CurrentValue = settings.targetTroops,
        Flag = "FFF_TargetTroops",
        Callback = function(value)
            settings.targetTroops = value
        end,
    })

    CombatTab:CreateSection("Defense & Recovery", "Right")

    CombatTab:CreateToggle({
        Name = "Auto Parry (Smart Block)",
        CurrentValue = settings.autoParry,
        Flag = "FFF_AutoParry",
        Callback = function(value)
            settings.autoParry = value
            if not value and isBlocking then
                setBlockState(false)
            end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Parry Distance",
        Range = {8, 30},
        Increment = 2,
        Suffix = " studs",
        CurrentValue = settings.parryDistance,
        Flag = "FFF_ParryDistance",
        Callback = function(value)
            settings.parryDistance = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Heal on Low HP",
        CurrentValue = settings.autoHeal,
        Flag = "FFF_AutoHeal",
        Callback = function(value)
            settings.autoHeal = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Heal HP Threshold",
        Range = {20, 70},
        Increment = 5,
        Suffix = "%",
        CurrentValue = settings.healHpThreshold,
        Flag = "FFF_HealHp",
        Callback = function(value)
            settings.healHpThreshold = value
        end,
    })

    CombatTab:CreateToggle({
        Name = "Auto Dodge Roll (Foot Only)",
        CurrentValue = settings.autoDodge,
        Flag = "FFF_AutoDodge",
        Callback = function(value)
            settings.autoDodge = value
        end,
    })

    CombatTab:CreateSlider({
        Name = "Dodge HP Threshold",
        Range = {10, 50},
        Increment = 5,
        Suffix = "%",
        CurrentValue = settings.dodgeHpThreshold,
        Flag = "FFF_DodgeHp",
        Callback = function(value)
            settings.dodgeHpThreshold = value
        end,
    })

    -- Tab 2: Troops
    local TroopTab = Window:CreateTab("Troops", "users")
    TroopTab:CreateSection("Tactical Commands (Macros)", "Left")

    TroopTab:CreateButton({
        Name = "Instant Rush Nuke [K]",
        Callback = function()
            triggerRushNuke()
        end,
    })

    TroopTab:CreateButton({
        Name = "Troop Charge / Attack",
        Callback = function()
            triggerTroopAttack()
        end,
    })

    TroopTab:CreateButton({
        Name = "Troop Follow Player",
        Callback = function()
            triggerTroopFollow()
        end,
    })

    TroopTab:CreateButton({
        Name = "Troop Hold Position",
        Callback = function()
            triggerTroopHold()
        end,
    })

    TroopTab:CreateButton({
        Name = "Air-Drop Formation to Target [U]",
        Callback = function()
            airDropTroops()
        end,
    })

    TroopTab:CreateButton({
        Name = "Satellite Arrow Rain",
        Callback = function()
            triggerArrowVolley()
        end,
    })

    TroopTab:CreateSection("Troop Automation", "Right")

    TroopTab:CreateToggle({
        Name = "Auto Rush on Enemy Proximity",
        CurrentValue = settings.autoRush,
        Flag = "FFF_AutoRush",
        Callback = function(value)
            settings.autoRush = value
        end,
    })

    TroopTab:CreateSlider({
        Name = "Auto Rush Range",
        Range = {30, 150},
        Increment = 5,
        Suffix = " studs",
        CurrentValue = settings.autoRushRange,
        Flag = "FFF_RushRange",
        Callback = function(value)
            settings.autoRushRange = value
        end,
    })

    TroopTab:CreateToggle({
        Name = "Auto Charge / Attack",
        CurrentValue = settings.autoTroopAttack,
        Flag = "FFF_AutoTroopAtk",
        Callback = function(value)
            settings.autoTroopAttack = value
        end,
    })

    TroopTab:CreateSlider({
        Name = "Troop Attack Range",
        Range = {30, 150},
        Increment = 5,
        Suffix = " studs",
        CurrentValue = settings.troopAttackRange,
        Flag = "FFF_TroopAtkRange",
        Callback = function(value)
            settings.troopAttackRange = value
        end,
    })

    TroopTab:CreateToggle({
        Name = "Auto Satellite Volley",
        CurrentValue = settings.autoVolley,
        Flag = "FFF_AutoVolley",
        Callback = function(value)
            settings.autoVolley = value
        end,
    })

    TroopTab:CreateToggle({
        Name = "Auto Retreat Dying Troops (<15% HP)",
        CurrentValue = settings.autoRetreat,
        Flag = "FFF_AutoRetreat",
        Callback = function(value)
            settings.autoRetreat = value
        end,
    })

    -- Tab 3: Movement
    local MoveTab = Window:CreateTab("Movement", "wind")
    MoveTab:CreateSection("Dual-Mode Flight Engine", "Left")

    MoveTab:CreateToggle({
        Name = "Flight Mode [J]",
        CurrentValue = settings.flightEnabled,
        Flag = "FFF_Flight",
        Callback = function(value)
            settings.flightEnabled = value
            local root = getActiveMovementRoot()
            if root and not value then
                root.AssemblyLinearVelocity = Vector3.zero
            end
        end,
    })

    MoveTab:CreateSlider({
        Name = "Flight Speed",
        Range = {20, 150},
        Increment = 5,
        Suffix = " studs/s",
        CurrentValue = settings.flightSpeed,
        Flag = "FFF_FlightSpeed",
        Callback = function(value)
            settings.flightSpeed = value
        end,
    })
    MoveTab:CreateLabel("Controls: W/S (Fwd/Back), A/D (Strafe), Space (Up), L-Ctrl (Down).")
    MoveTab:CreateLabel("Seamless: Works whether mounted on horse or on foot.")

    MoveTab:CreateSection("Speed Hack and Stamina (Overclock)", "Right")

    MoveTab:CreateToggle({
        Name = "Player Speed Hack",
        CurrentValue = settings.speedHackEnabled,
        Flag = "FFF_SpeedHack",
        Callback = function(value)
            settings.speedHackEnabled = value
            if not value then
                localPlayer:SetAttribute("WalkSpeed", 15)
                localPlayer:SetAttribute("RunSpeed", 20)
                local hum = getLocalHumanoid()
                if hum then hum.WalkSpeed = 15 end
            end
        end,
    })

    MoveTab:CreateSlider({
        Name = "WalkSpeed Multiplier",
        Range = {15, 70},
        Increment = 2,
        Suffix = " studs/s",
        CurrentValue = settings.customWalkSpeed,
        Flag = "FFF_WalkSpeed",
        Callback = function(value)
            settings.customWalkSpeed = value
        end,
    })

    MoveTab:CreateSlider({
        Name = "Sprint Speed Multiplier",
        Range = {20, 90},
        Increment = 5,
        Suffix = " studs/s",
        CurrentValue = settings.customRunSpeed,
        Flag = "FFF_RunSpeed",
        Callback = function(value)
            settings.customRunSpeed = value
        end,
    })

    MoveTab:CreateToggle({
        Name = "Infinite Player Stamina (No Exhaustion)",
        CurrentValue = settings.infiniteStamina,
        Flag = "FFF_InfPlayerStamina",
        Callback = function(value)
            settings.infiniteStamina = value
        end,
    })

    MoveTab:CreateSection("Horse Nitro and Mount Overclock", "Left")

    MoveTab:CreateToggle({
        Name = "Horse Nitro Speed",
        CurrentValue = settings.horseNitroEnabled,
        Flag = "FFF_HorseNitro",
        Callback = function(value)
            settings.horseNitroEnabled = value
            if not value then
                localPlayer:SetAttribute("MountWalkSpeed", 17.8)
                localPlayer:SetAttribute("MountRunSpeed", 41.8)
            end
        end,
    })

    MoveTab:CreateSlider({
        Name = "Horse Max Run Speed",
        Range = {40, 130},
        Increment = 5,
        Suffix = " studs/s",
        CurrentValue = settings.customHorseSpeed,
        Flag = "FFF_HorseSpeed",
        Callback = function(value)
            settings.customHorseSpeed = value
        end,
    })

    MoveTab:CreateToggle({
        Name = "Infinite Mount Stamina",
        CurrentValue = settings.infiniteMountStamina,
        Flag = "FFF_InfMountStamina",
        Callback = function(value)
            settings.infiniteMountStamina = value
        end,
    })

    MoveTab:CreateButton({
        Name = "Instant Call / Mount Horse",
        Callback = function()
            local mountBtn = getPlayerActionButton("Mount")
            if mountBtn then
                triggerActionButton(mountBtn)
            elseif MountRequest then
                MountRequest:FireServer()
            end
        end,
    })

    MoveTab:CreateSection("Tactical Teleport (Objectives)", "Right")

    local function tpToPosition(targetPos)
        local targetModel = isMounted() and getLocalHorse() or localPlayer.Character
        if targetModel then
            targetModel:PivotTo(CFrame.new(targetPos + Vector3.new(0, 4, 0)))
        end
    end

    MoveTab:CreateButton({
        Name = "Teleport to Point A (Castle Wall)",
        Callback = function()
            local pointA = workspace:FindFirstChild("ActiveMap", true)
                and workspace.ActiveMap:FindFirstChild("Points", true)
                and workspace.ActiveMap.Castle.Interactable.Points:FindFirstChild("PointA")
            if pointA then
                tpToPosition(pointA:GetPivot().Position)
            else
                tpToPosition(Vector3.new(-206, 91, -307))
            end
        end,
    })

    MoveTab:CreateButton({
        Name = "Teleport to Point B (Castle Courtyard)",
        Callback = function()
            local pointB = workspace:FindFirstChild("ActiveMap", true)
                and workspace.ActiveMap:FindFirstChild("Points", true)
                and workspace.ActiveMap.Castle.Interactable.Points:FindFirstChild("PointB")
            if pointB then
                tpToPosition(pointB:GetPivot().Position)
            else
                tpToPosition(Vector3.new(-206, 33, -30))
            end
        end,
    })

    MoveTab:CreateButton({
        Name = "Teleport to Castle Gate / Throne Base",
        Callback = function()
            local base = workspace:FindFirstChild("ActiveMap", true)
                and workspace.ActiveMap:FindFirstChild("Points", true)
                and workspace.ActiveMap.Castle.Interactable.Points:FindFirstChild("Base")
            if base then
                tpToPosition(base:GetPivot().Position)
            else
                tpToPosition(Vector3.new(-204, 58, 145))
            end
        end,
    })

    -- Tab 4: Visuals
    local VisualTab = Window:CreateTab("Visuals", "eye")
    VisualTab:CreateSection("Entity ESP (Drawing API)", "Left")

    VisualTab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = settings.playerEsp,
        Flag = "FFF_PlayerEsp",
        Callback = function(value)
            settings.playerEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Troop ESP (Enemy)",
        CurrentValue = settings.troopEsp,
        Flag = "FFF_TroopEsp",
        Callback = function(value)
            settings.troopEsp = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Bounding Boxes",
        CurrentValue = settings.espBoxes,
        Flag = "FFF_EspBoxes",
        Callback = function(value)
            settings.espBoxes = value
        end,
    })

    VisualTab:CreateToggle({
        Name = "Show Health & Distance",
        CurrentValue = settings.espHealth,
        Flag = "FFF_EspStats",
        Callback = function(value)
            settings.espHealth = value
            settings.espDistance = value
        end,
    })

    VisualTab:CreateSlider({
        Name = "Max ESP Distance",
        Range = {200, 2500},
        Increment = 100,
        Suffix = " studs",
        CurrentValue = settings.maxEspDistance,
        Flag = "FFF_MaxEspDist",
        Callback = function(value)
            settings.maxEspDistance = value
        end,
    })

    VisualTab:CreateSection("Objective ESP", "Right")

    VisualTab:CreateToggle({
        Name = "Supply Point & Flag ESP",
        CurrentValue = settings.supplyPointEsp,
        Flag = "FFF_SupplyEsp",
        Callback = function(value)
            settings.supplyPointEsp = value
        end,
    })

    -- Tab 5: Safety
    local SafeTab = Window:CreateTab("Safety", "shield")
    SafeTab:CreateSection("Anti-Cheat Shield", "Left")

    SafeTab:CreateToggle({
        Name = "Integrity Shield Active",
        CurrentValue = settings.integrityShield,
        Flag = "FFF_SafeShield",
        Callback = function(value)
            settings.integrityShield = value
        end,
    })
    SafeTab:CreateLabel("Zero CoreGui Footprint (100% Drawing API).")
    SafeTab:CreateLabel("Honeypot Shield: Blocks AdminAbuse, GiveMeCash, AddXP.")

    -- Safe Keybinds Handler (No collisions with game native keys)
    connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.J then
            settings.flightEnabled = not settings.flightEnabled
            local root = getActiveMovementRoot()
            if root and not settings.flightEnabled then
                root.AssemblyLinearVelocity = Vector3.zero
            end
        elseif input.KeyCode == Enum.KeyCode.U then
            airDropTroops()
        elseif input.KeyCode == Enum.KeyCode.K then
            triggerRushNuke()
        end
    end)

    -- ============================================================
    --   CLEANUP & TEARDOWN
    -- ============================================================

    local function destroyScript()
        if not running then return end
        running = false

        for _, conn in ipairs(connections) do
            if conn and conn.Disconnect then
                pcall(function() conn:Disconnect() end)
            end
        end
        table.clear(connections)

        clearAllEsp()

        if isBlocking then
            setBlockState(false)
        end

        local root = getActiveMovementRoot()
        if root then
            pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)
        end

        pcall(function()
            localPlayer:SetAttribute("WalkSpeed", 15)
            localPlayer:SetAttribute("RunSpeed", 20)
            localPlayer:SetAttribute("MountWalkSpeed", 17.8)
            localPlayer:SetAttribute("MountRunSpeed", 41.8)
            local hum = getLocalHumanoid()
            if hum then hum.WalkSpeed = 15 end
        end)

        if environment and environment.__RAVEN_FIGHT_FIGHT_FIGHT then
            environment.__RAVEN_FIGHT_FIGHT_FIGHT = nil
        end
    end

    if Window and type(Window.OnUnload) == "function" then
        Window:OnUnload(destroyScript)
    end

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end

    environment.__RAVEN_FIGHT_FIGHT_FIGHT = {
        Destroy = function()
            destroyScript()
            if Window and type(Window.Destroy) == "function" then
                Window:Destroy()
            end
        end
    }

    if type(Window.SortTabs) == "function" then
        Window:SortTabs({"Overview", "Combat", "Troops", "Movement", "Visuals", "Safety", "Settings"})
    end

    -- Automatically select Movement tab so the user lands straight on the active controls
    pcall(function()
        if type(Window.SelectTab) == "function" then
            Window:SelectTab("Movement")
        elseif type(Window.SetActiveTab) == "function" then
            Window:SetActiveTab("Movement")
        elseif type(Window.activeTabIndex) == "number" and Window.tabs then
            for i, t in ipairs(Window.tabs) do
                local tabName = tostring(t.name or t.title or t.Title or "")
                if tabName:lower() == "movement" then
                    Window.activeTabIndex = i
                    break
                end
            end
        end
    end)
end