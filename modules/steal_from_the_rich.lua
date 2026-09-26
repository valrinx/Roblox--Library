--[[
    RAVEN HUB | Steal From The Rich!
    PlaceId: 120475074479690 | GameId: 10753751277
    Version: v1.1.0

    Features:
      • Auto Steal Crate (Anti-Rubberband Smooth Fast Mover, Priority Rarity Sniper, Auto SafeZone Escape)
      • Auto Dismount Treadmill on Demand & Anti-Anchor Bypass
      • Infinite Speed Farm (Remote Speed Upgrade, Treadmill Lock, Auto Rebirth)
      • Economy & Base (Remote Sell, Auto Plot Income Collect, Auto Slot Upgrade)
      • Free Claims (Index Claim All, Free Gift Chest Snatcher, Spin Wheel, Offline Income)
      • Combat & Defense (Bat Slap Aura, Anti-Ragdoll, Anti-Slowdown Bypass)
      • 100% Drawing API Crate ESP (Keyword-based Rarity Detection, Real WorldPosition Adornee)
      • Waypoint Teleports with Anti-Rubberband Multi-Step Interpolation
]]

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local RunService = game:GetService("RunService")
    local TweenService = game:GetService("TweenService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")

    local player = Players.LocalPlayer
    local environment = (type(getgenv) == "function" and getgenv()) or _G

    -- Cleanup any existing instance
    if type(environment.__RAVEN_STEAL_RICH) == "table"
        and type(environment.__RAVEN_STEAL_RICH.Destroy) == "function" then
        pcall(environment.__RAVEN_STEAL_RICH.Destroy)
        environment.__RAVEN_STEAL_RICH = nil
    end

    local running = true
    local connections = {}
    local drawingObjects = {}

    -- ============================================================
    --  NETWORK REMOTES
    -- ============================================================
    local Packages = ReplicatedStorage:WaitForChild("Shared", 5)
        and ReplicatedStorage.Shared:WaitForChild("Packages", 5)
    local Network = Packages and Packages:WaitForChild("Network", 5)

    -- Speed & Treadmill
    local SpeedUpgradeRemote = Network and Network:FindFirstChild("rev_SPEED_UPGRADE")
    local TreadmillUpgradeRemote = ReplicatedStorage:FindFirstChild("re_TREADMILL_UPGRADE")
    local DismountRemote = Network and Network:FindFirstChild("rev_TREADMILL_DISMOUNT")
    local RebirthRemote = Network and Network:FindFirstChild("rev_RebirthRequest")

    -- Steal & Interact Network Remotes
    local StealRemote = Network and Network:FindFirstChild("rev_S_Steal")
    local InteractRemote = Network and Network:FindFirstChild("rev_S_Interact")
    local CrateDropRemote = Network and Network:FindFirstChild("rev_CRATE_DROP")

    -- Economy & Base
    local SellDoRemote = ReplicatedStorage:FindFirstChild("re_SELL_DO")
    local SellAllFunc = Network and Network:FindFirstChild("ref_B_SellAll")
    local BaseCollectRemote = Network and Network:FindFirstChild("rev_B_Collect")
    local SlotUpgradeRemote = Network and Network:FindFirstChild("rev_bs_upgrade")
    local PlotUpgradeRemote = ReplicatedStorage:FindFirstChild("re_PLOT_UPGRADE")
    local PlaceAtRemote = ReplicatedStorage:FindFirstChild("re_PLACE_AT")
    local CrateTimersFunc = ReplicatedStorage:FindFirstChild("rf_CRATE_TIMERS")

    -- Free Rewards
    local IndexClaimAllRemote = Network and Network:FindFirstChild("rev_INDEX_CLAIM_ALL")
    local FreeGiftRemote = Network and Network:FindFirstChild("rev_ClaimFree")
    local OfflineClaimRemote = Network and Network:FindFirstChild("rev_Offline_Claim")
    local SpinWheelRemote = Network and Network:FindFirstChild("rev_RequestSpin")

    -- Combat & Tools
    local BatSwingRemote = Network and Network:FindFirstChild("rev_BAT_SWING")
    local BearTrapRemote = Network and Network:FindFirstChild("rev_BEAR_TRAP_PLACE")

    -- ============================================================
    --  CONSTANTS & WAYPOINTS
    -- ============================================================
    local SAFEZONE_POS = Vector3.new(2435.0, 5.0, -940.0)

    local ZONE_WAYPOINTS = {
        ["Grandpa (👴 Common)"]           = Vector3.new(2364.4, 4.5, -984.7),
        ["Jeweler (💎 Uncommon)"]        = Vector3.new(2203.3, 5.5, -881.6),
        ["Archeologist (🦖 Uncommon)"]   = Vector3.new(2003.0, 5.5, -993.3),
        ["Mafia Boss (🕶️ Epic)"]         = Vector3.new(1757.6, 5.5, -896.6),
        ["Celebrity (⭐ Epic/Cosmic)"]    = Vector3.new(1439.4, 6.0, -983.5),
        ["Pirate (🏴‍☠️ Mythic)"]           = Vector3.new(1097.7, 6.0, -914.8),
        ["Museum Worker (🏛️ Epic)"]       = Vector3.new(598.4, 6.8, -977.9),
        ["Gold Tycoon (💰 Mythic)"]       = Vector3.new(121.5, 6.8, -897.0),
        ["Astronaut (🚀 Cosmic)"]        = Vector3.new(-108.2, 8.9, -976.4),
        ["Demon King (😈 Mythic)"]       = Vector3.new(-1069.0, 8.5, -915.7),
    }

    local RARITY_ORDER = {
        "Divine", "Cosmic", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common"
    }

    local RARITY_WEIGHTS = {
        ["Common"]    = 1,
        ["Uncommon"]  = 2,
        ["Rare"]      = 3,
        ["Epic"]      = 4,
        ["Legendary"] = 5,
        ["Mythic"]    = 6,
        ["Cosmic"]    = 7,
        ["Divine"]    = 8,
    }

    local RARITY_COLORS = {
        ["Common"]    = Color3.fromRGB(220, 220, 220),
        ["Uncommon"]  = Color3.fromRGB(80, 220, 100),
        ["Rare"]      = Color3.fromRGB(50, 160, 255),
        ["Epic"]      = Color3.fromRGB(180, 60, 255),
        ["Legendary"] = Color3.fromRGB(255, 200, 30),
        ["Mythic"]    = Color3.fromRGB(255, 45, 45),
        ["Cosmic"]    = Color3.fromRGB(0, 245, 255),
        ["Divine"]    = Color3.fromRGB(255, 230, 140),
        ["Unknown"]   = Color3.fromRGB(200, 200, 200),
    }

    -- ============================================================
    --  SETTINGS STATE
    -- ============================================================
    local settings = {
        -- Steal Farm
        autoSteal           = false,
        minRarity           = "All",
        matchCarryTier      = true, -- Prioritizes crates matching player's current CarryStat (Common if tier 1, etc.)
        vacuumCrates        = true, -- Rapid remote steal combined with proximity prompt hold
        stealMethod         = "Fast Glide", -- "Fast Glide", "Instant Snap", "Walk"
        glideSpeed          = 350,
        autoReturnSafeZone  = true,
        bypassSlowdown      = true,

        -- Speed Farm
        autoSpeedUpgrade    = false,
        speedUpgradeDelay   = 0.1,
        autoTreadmillUpgrade= false,
        autoTreadmillLock   = false,
        autoRebirth         = false,
        rebirthThreshold    = 100000,

        -- Economy & Base
        autoSell            = false,
        sellInterval        = 3,
        autoBaseCollect     = false,
        baseCollectInterval = 2,
        autoSlotUpgrade     = false,
        autoPlaceCrates     = true,
        autoOpenCrates      = true,

        -- Free Claims
        autoIndexClaim      = false,
        indexClaimInterval  = 10,
        autoFreeGift        = false,
        freeGiftInterval    = 15,
        autoOfflineClaim    = false,
        offlineClaimInterval= 30,
        autoSpin            = false,
        spinInterval        = 20,

        -- Combat
        batSlapAura         = false,
        batAuraRange        = 22,
        antiRagdoll         = true,

        -- ESP
        crateEsp            = false,
        crateEspMinRarity   = "All",
        crateEspMaxDist     = 3500,
        playerEsp           = false,
        playerEspMaxDist    = 1500,
    }

    -- ============================================================
    --  UTILITIES
    -- ============================================================
    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(connections, conn)
        return conn
    end

    local function getCharacter()
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        return char, hum, root
    end

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 4})
            end)
        end
    end

    local function forceDismountAndUnanchor()
        local char, hum, root = getCharacter()
        if DismountRemote then pcall(function() DismountRemote:FireServer() end) end
        player:SetAttribute("OnTreadmill", false)
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.Anchored then
                    p.Anchored = false
                end
            end
        end
        if hum and hum.WalkSpeed < 16 then
            local runSpeed = tonumber(player:GetAttribute("RunSpeed")) or 50
            hum.WalkSpeed = math.max(runSpeed, 35)
        end
    end

    local function getMyBeltCFrame()
        local personal = Workspace:FindFirstChild("Treadmills")
            and Workspace.Treadmills:FindFirstChild("PersonalTreadmill_" .. player.UserId)
        local belt = personal and personal:FindFirstChild("Belt")
        if belt then
            return belt.CFrame * CFrame.new(0, 3, 0)
        end
        return nil
    end

    local function getPlayerPlot()
        for _, child in ipairs(Workspace:GetChildren()) do
            if child.Name:match("^Plot Building %d+$") then
                local floor = child:FindFirstChild("floor")
                if floor and floor:GetAttribute("OwnerUserId") == player.UserId then
                    return child, floor
                end
            end
        end
        return nil, nil
    end

    local function moveToTarget(targetPos, method, speedOverride)
        local char, hum, root = getCharacter()
        if not root then return false end

        forceDismountAndUnanchor()

        local startPos = root.Position
        local dist = (startPos - targetPos).Magnitude
        if dist < 3.5 then return true end

        -- Step glide with 14 studs per step, keeping height >= 4 to glide smoothly over treadmill rail hitboxes
        local steps = math.max(math.ceil(dist / 14), 2)
        for i = 1, steps do
            if not running then break end
            local alpha = i / steps
            local currentPos = startPos:Lerp(targetPos, alpha)
            root.CFrame = CFrame.new(currentPos.X, math.max(currentPos.Y, 4.2), currentPos.Z)
            root.AssemblyLinearVelocity = Vector3.zero
            task.wait(0.015)
        end
        root.CFrame = CFrame.new(targetPos.X, math.max(targetPos.Y, 3.8), targetPos.Z)
        root.AssemblyLinearVelocity = Vector3.zero
        return true
    end

    local function parseCrateInfo(crate)
        local name = crate.Name
        local rarity = "Common"
        for _, r in ipairs(RARITY_ORDER) do
            if name:find(r) then
                rarity = r
                break
            end
        end
        local zone = name:match("Crate_([^_]+)") or "Rich"
        local weight = RARITY_WEIGHTS[rarity] or 1
        return zone, rarity, weight
    end

    local function getPromptWorldPosition(prompt)
        if not prompt then return nil end
        local parent = prompt.Parent
        if parent:IsA("Attachment") then
            return parent.WorldPosition
        elseif parent:IsA("BasePart") then
            return parent.Position
        else
            local model = prompt:FindFirstAncestorOfClass("Model")
            return model and model:GetPivot().Position or nil
        end
    end

    local function getCratesFolder()
        return Workspace:FindFirstChild("Crates")
    end

    local function findBestCrate()
        local crates = getCratesFolder()
        if not crates then return nil, nil end

        local _, _, root = getCharacter()
        if not root then return nil, nil end

        local playerCarry = tonumber(player:GetAttribute("CarryStat")) or 1

        local minWeight = 1
        if settings.minRarity == "Uncommon+" then minWeight = 2
        elseif settings.minRarity == "Rare+" then minWeight = 3
        elseif settings.minRarity == "Epic+" then minWeight = 4
        elseif settings.minRarity == "Legendary+" then minWeight = 5
        elseif settings.minRarity == "Mythic+" then minWeight = 6
        elseif settings.minRarity == "Cosmic+" then minWeight = 7
        end

        local candidates = {}
        for _, crate in ipairs(crates:GetChildren()) do
            if crate:IsA("Model") then
                local prompt = crate:FindFirstChildWhichIsA("ProximityPrompt", true)
                local part = crate:FindFirstChild("Cube") or crate:FindFirstChildWhichIsA("BasePart")
                if prompt and prompt.Enabled and part then
                    local worldPos = part.Position
                    local zone, rarity, weight = parseCrateInfo(crate)
                    local isTutorial = crate:GetAttribute("TutorialCrate") or string.find(crate.Name, "tutorial")
                    local isGrandpa = (crate:GetAttribute("AreaId") == "Grandpa") or (zone == "Grandpa")

                    -- If matchCarryTier is true, reject crates that require higher tier than player currently has
                    local canCarry = (not settings.matchCarryTier) or (weight <= playerCarry)

                    if not isTutorial and canCarry and weight >= minWeight then
                        local dist = (root.Position - worldPos).Magnitude
                        table.insert(candidates, {
                            crate = crate,
                            prompt = prompt,
                            part = part,
                            worldPos = worldPos,
                            weight = weight,
                            dist = dist,
                            rarity = rarity,
                            zone = zone,
                            isGrandpa = isGrandpa and 1 or 0
                        })
                    end
                end
            end
        end

        -- Fallback: If no candidate matched due to strict carry tier filter, find any available crate
        if #candidates == 0 then
            for _, crate in ipairs(crates:GetChildren()) do
                if crate:IsA("Model") then
                    local prompt = crate:FindFirstChildWhichIsA("ProximityPrompt", true)
                    local part = crate:FindFirstChild("Cube") or crate:FindFirstChildWhichIsA("BasePart")
                    if prompt and prompt.Enabled and part then
                        local worldPos = part.Position
                        local zone, rarity, weight = parseCrateInfo(crate)
                        local isTutorial = crate:GetAttribute("TutorialCrate") or string.find(crate.Name, "tutorial")
                        if not isTutorial then
                            local dist = (root.Position - worldPos).Magnitude
                            table.insert(candidates, {
                                crate = crate,
                                prompt = prompt,
                                part = part,
                                worldPos = worldPos,
                                weight = weight,
                                dist = dist,
                                rarity = rarity,
                                zone = zone,
                                isGrandpa = (zone == "Grandpa") and 1 or 0
                            })
                        end
                    end
                end
            end
        end

        if #candidates == 0 then return nil, nil, nil, nil end

        table.sort(candidates, function(a, b)
            -- Prioritize highest allowed rarity first
            if a.weight ~= b.weight then
                return a.weight > b.weight
            end
            -- Prioritize Grandpa if early tier
            if a.isGrandpa ~= b.isGrandpa and playerCarry <= 2 then
                return a.isGrandpa > b.isGrandpa
            end
            return a.dist < b.dist -- closer first
        end)

        return candidates[1].crate, candidates[1].prompt, candidates[1].worldPos, candidates[1].part
    end

    -- ============================================================
    --  100% DRAWING API ESP SYSTEM
    -- ============================================================
    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local espCache = {}

    local function createDrawing(dType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, dType)
        if ok and obj then
            table.insert(drawingObjects, obj)
            return obj
        end
        return nil
    end

    local function removeEspEntry(key)
        local entry = espCache[key]
        if not entry then return end
        if entry.text then pcall(function() entry.text:Remove() end) end
        espCache[key] = nil
    end

    local function clearAllEsp()
        for k in pairs(espCache) do
            removeEspEntry(k)
        end
    end

    local function updateCrateEsp()
        if not settings.crateEsp or not hasDrawing then
            for k, entry in pairs(espCache) do
                if entry.kind == "crate" then removeEspEntry(k) end
            end
            return
        end

        local crates = getCratesFolder()
        if not crates then return end

        local camera = Workspace.CurrentCamera
        if not camera then return end

        local minWeight = 1
        if settings.crateEspMinRarity == "Uncommon+" then minWeight = 2
        elseif settings.crateEspMinRarity == "Rare+" then minWeight = 3
        elseif settings.crateEspMinRarity == "Epic+" then minWeight = 4
        elseif settings.crateEspMinRarity == "Legendary+" then minWeight = 5
        elseif settings.crateEspMinRarity == "Mythic+" then minWeight = 6
        end

        local currentCrates = {}
        for _, crate in ipairs(crates:GetChildren()) do
            local zone, rarity, weight = parseCrateInfo(crate)
            if weight >= minWeight then
                local prompt = crate:FindFirstChildWhichIsA("ProximityPrompt", true)
                local worldPos = getPromptWorldPosition(prompt) or crate:GetPivot().Position
                if worldPos then
                    currentCrates[crate] = true
                    local entry = espCache[crate]
                    if not entry then
                        local text = createDrawing("Text")
                        if text then
                            text.Size = 13
                            text.Center = true
                            text.Outline = true
                            text.OutlineColor = Color3.new(0, 0, 0)
                            espCache[crate] = {
                                kind = "crate",
                                text = text,
                                rarity = rarity,
                                zone = zone
                            }
                            entry = espCache[crate]
                        end
                    end

                    if entry and entry.text then
                        local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
                        local dist = (camera.CFrame.Position - worldPos).Magnitude

                        if onScreen and screenPos.Z > 0 and dist <= settings.crateEspMaxDist then
                            local col = RARITY_COLORS[rarity] or RARITY_COLORS["Unknown"]
                            entry.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                            entry.text.Color = col
                            entry.text.Text = string.format("[%s - %s] %dm", zone, rarity, math.floor(dist * 0.28))
                            entry.text.Visible = true
                        else
                            entry.text.Visible = false
                        end
                    end
                end
            end
        end

        for inst, entry in pairs(espCache) do
            if entry.kind == "crate" and not currentCrates[inst] then
                removeEspEntry(inst)
            end
        end
    end

    local function updatePlayerEsp()
        if not settings.playerEsp or not hasDrawing then
            for k, entry in pairs(espCache) do
                if entry.kind == "player" then removeEspEntry(k) end
            end
            return
        end

        local camera = Workspace.CurrentCamera
        if not camera then return end

        local currentPlrs = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player then
                local char = plr.Character
                local root = char and char:FindFirstChild("HumanoidRootPart")
                if root then
                    currentPlrs[plr] = true
                    local entry = espCache[plr]
                    if not entry then
                        local text = createDrawing("Text")
                        if text then
                            text.Size = 13
                            text.Center = true
                            text.Outline = true
                            text.OutlineColor = Color3.new(0, 0, 0)
                            espCache[plr] = {
                                kind = "player",
                                text = text
                            }
                            entry = espCache[plr]
                        end
                    end

                    if entry and entry.text then
                        local screenPos, onScreen = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.5, 0))
                        local dist = (camera.CFrame.Position - root.Position).Magnitude

                        if onScreen and screenPos.Z > 0 and dist <= settings.playerEspMaxDist then
                            local isCarrying = plr:GetAttribute("CarryingStolen") == true
                            local tag = isCarrying and " [🎒 CARRIER]" or ""
                            local col = isCarrying and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(120, 200, 255)

                            entry.text.Position = Vector2.new(screenPos.X, screenPos.Y)
                            entry.text.Color = col
                            entry.text.Text = string.format("%s%s (%dm)", plr.Name, tag, math.floor(dist * 0.28))
                            entry.text.Visible = true
                        else
                            entry.text.Visible = false
                        end
                    end
                end
            end
        end

        for p, entry in pairs(espCache) do
            if entry.kind == "player" and not currentPlrs[p] then
                removeEspEntry(p)
            end
        end
    end

    -- ============================================================
    --  BACKGROUND FARM LOOPS
    -- ============================================================

    -- Steal Loop
    task.spawn(function()
        while running do
            if settings.autoSteal then
                local isCarrying = player:GetAttribute("CarryingStolen") == true
                local bankedCount = tonumber(player:GetAttribute("BankedCrateCount")) or 0

                -- 1. Check if we need to offload banked crates to Plot first
                if bankedCount > 0 and settings.autoPlaceCrates and PlaceAtRemote then
                    local plot, floor = getPlayerPlot()
                    local char, _, root = getCharacter()
                    if plot and floor and root then
                        -- Equip crate tool
                        local crateTool = char:FindFirstChildWhichIsA("Tool")
                        if not (crateTool and crateTool:GetAttribute("CrateUid")) then
                            crateTool = nil
                            for _, t in ipairs(player.Backpack:GetChildren()) do
                                if t:GetAttribute("CrateUid") then
                                    crateTool = t
                                    t.Parent = char
                                    task.wait(0.15)
                                    break
                                end
                            end
                        end

                        if crateTool then
                            -- Glide to plot floor
                            local plotPos = floor.Position + Vector3.new(0, 3, 0)
                            moveToTarget(plotPos, "Fast Glide", 450)
                            task.wait(0.2)

                            -- Place on plot
                            local placeSpot = floor.Position + Vector3.new(math.random(-6, 6), floor.Size.Y / 2, math.random(-6, 6))
                            PlaceAtRemote:FireServer(placeSpot, 0)
                            task.wait(0.35)

                            -- Auto open/appraise if enabled
                            if settings.autoOpenCrates and CrateTimersFunc then
                                pcall(function()
                                    local list = CrateTimersFunc:InvokeServer("list")
                                    if type(list) == "table" then
                                        for _, item in ipairs(list) do
                                            CrateTimersFunc:InvokeServer("open", item.Uid)
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end

                -- 2. Steal & Bank Execution
                if isCarrying then
                    -- Carrying stolen crate -> Fly/Glide to SafeZone to bank it!
                    if settings.autoReturnSafeZone then
                        moveToTarget(SAFEZONE_POS + Vector3.new(0, 1.5, 0), "Fast Glide", 400)
                        local t0 = os.clock()
                        while running and settings.autoSteal and player:GetAttribute("CarryingStolen") == true and (os.clock() - t0 < 3.0) do
                            task.wait(0.1)
                        end
                        task.wait(0.2)
                        -- Auto sell after banking if enabled
                        if settings.autoSell then
                            if SellAllFunc then pcall(function() SellAllFunc:InvokeServer() end) end
                            if SellDoRemote then pcall(function() SellDoRemote:FireServer() end) end
                        end
                    else
                        task.wait(0.3)
                    end
                else
                    -- Not carrying crate -> Find best crate and steal
                    local bestCrate, prompt, worldPos, cubePart = findBestCrate()
                    if bestCrate and prompt and cubePart then
                        local targetPos = cubePart.Position
                        local okMove = moveToTarget(targetPos + Vector3.new(0, 1.2, 0), "Fast Glide", 400)
                        if okMove then
                            task.wait(0.12)
                            -- Align camera and character facing directly at crate prompt so Roblox registers line of sight and focus
                            local _, _, rootPart = getCharacter()
                            local cam = Workspace.CurrentCamera
                            if rootPart then
                                rootPart.CFrame = CFrame.lookAt(targetPos + Vector3.new(0, 1.2, 2.5), targetPos)
                            end
                            if cam and rootPart then
                                cam.CFrame = CFrame.lookAt(rootPart.Position + Vector3.new(0, 1.5, 0), targetPos)
                            end
                            task.wait(0.08)

                            -- Direct network remote steal burst
                            if StealRemote then
                                pcall(function() StealRemote:FireServer(bestCrate) end)
                                pcall(function() StealRemote:FireServer(cubePart) end)
                            end
                            if InteractRemote then
                                pcall(function() InteractRemote:FireServer(bestCrate) end)
                            end

                            -- Trigger prompt hold & VIM key E simulation
                            local VIM = pcall(function() return game:GetService("VirtualInputManager") end) and game:GetService("VirtualInputManager")
                            if VIM then
                                pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
                            end
                            pcall(function() prompt:InputHoldBegin() end)

                            local holdT0 = os.clock()
                            local holdMax = math.max(prompt.HoldDuration + 0.6, 2.2)
                            while running and settings.autoSteal and (os.clock() - holdT0 < holdMax) do
                                if player:GetAttribute("CarryingStolen") == true then
                                    break
                                end
                                -- Continuously pulse direct remotes while holding
                                if StealRemote and math.random() > 0.5 then
                                    pcall(function() StealRemote:FireServer(bestCrate) end)
                                end
                                task.wait(0.08)
                            end

                            pcall(function() prompt:InputHoldEnd() end)
                            if VIM then
                                pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
                            end
                            task.wait(0.15)
                        end
                    else
                        task.wait(0.4)
                    end
                end
            else
                task.wait(0.3)
            end
            task.wait(0.04)
        end
    end)

    -- Speed Farm Loop
    task.spawn(function()
        while running do
            if settings.autoSpeedUpgrade and SpeedUpgradeRemote then
                pcall(function() SpeedUpgradeRemote:FireServer() end)
            end
            if settings.autoTreadmillUpgrade and TreadmillUpgradeRemote then
                pcall(function() TreadmillUpgradeRemote:FireServer() end)
            end
            if settings.autoRebirth and RebirthRemote then
                local spd = player:GetAttribute("SpeedLevel") or 0
                if spd >= settings.rebirthThreshold then
                    pcall(function() RebirthRemote:FireServer() end)
                end
            end
            task.wait(settings.speedUpgradeDelay or 0.1)
        end
    end)

    -- Treadmill Lock Loop
    task.spawn(function()
        while running do
            if settings.autoTreadmillLock and not settings.autoSteal then
                local beltCF = getMyBeltCFrame()
                local _, _, root = getCharacter()
                if beltCF and root then
                    local dist = (root.Position - beltCF.Position).Magnitude
                    if dist > 3 then
                        root.CFrame = beltCF
                        root.AssemblyLinearVelocity = Vector3.zero
                    end
                end
            end
            task.wait(0.5)
        end
    end)

    -- Economy & Sell Loop
    task.spawn(function()
        while running do
            if settings.autoSell then
                if SellAllFunc then
                    pcall(function() SellAllFunc:InvokeServer() end)
                end
                if SellDoRemote then
                    pcall(function() SellDoRemote:FireServer() end)
                end
            end
            task.wait(settings.sellInterval or 3)
        end
    end)

    -- Base Collect & Slot Upgrade Loop
    task.spawn(function()
        while running do
            if settings.autoBaseCollect and BaseCollectRemote then
                pcall(function() BaseCollectRemote:FireServer() end)
            end
            if settings.autoSlotUpgrade and SlotUpgradeRemote then
                pcall(function() SlotUpgradeRemote:FireServer() end)
            end
            task.wait(settings.baseCollectInterval or 2)
        end
    end)

    -- Free Claims Loop
    task.spawn(function()
        local lastIndex = 0
        local lastFreeGift = 0
        local lastOffline = 0
        local lastSpin = 0

        while running do
            local now = os.clock()
            if settings.autoIndexClaim and IndexClaimAllRemote and (now - lastIndex > settings.indexClaimInterval) then
                lastIndex = now
                pcall(function() IndexClaimAllRemote:FireServer() end)
            end
            if settings.autoFreeGift and FreeGiftRemote and (now - lastFreeGift > settings.freeGiftInterval) then
                lastFreeGift = now
                pcall(function() FreeGiftRemote:FireServer() end)
            end
            if settings.autoOfflineClaim and OfflineClaimRemote and (now - lastOffline > settings.offlineClaimInterval) then
                lastOffline = now
                pcall(function() OfflineClaimRemote:FireServer() end)
            end
            if settings.autoSpin and SpinWheelRemote and (now - lastSpin > settings.spinInterval) then
                lastSpin = now
                pcall(function() SpinWheelRemote:FireServer() end)
            end
            task.wait(1)
        end
    end)

    -- Combat (Bat Slap Aura) Loop
    task.spawn(function()
        while running do
            if settings.batSlapAura and BatSwingRemote then
                local inSafe = player:GetAttribute("InSafeZone") == true
                if not inSafe then
                    local _, _, myRoot = getCharacter()
                    if myRoot then
                        local hasNearbyEnemy = false
                        for _, plr in ipairs(Players:GetPlayers()) do
                            if plr ~= player then
                                local pChar = plr.Character
                                local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
                                if pRoot then
                                    local dist = (myRoot.Position - pRoot.Position).Magnitude
                                    if dist <= settings.batAuraRange then
                                        hasNearbyEnemy = true
                                        break
                                    end
                                end
                            end
                        end

                        if hasNearbyEnemy then
                            local bat = player.Backpack:FindFirstChild("Bat PVP")
                            local _, hum = getCharacter()
                            if bat and hum then
                                hum:EquipTool(bat)
                            end
                            pcall(function() BatSwingRemote:FireServer() end)
                            task.wait(0.2)
                        end
                    end
                end
            end
            task.wait(0.15)
        end
    end)

    -- Anti-Slowdown & Anti-Ragdoll (Heartbeat)
    connect(RunService.Heartbeat, function()
        if not running then return end
        local _, hum, root = getCharacter()
        if not hum or not root then return end

        -- Anti-Ragdoll
        if settings.antiRagdoll then
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
            if hum.PlatformStand then hum.PlatformStand = false end
        end

        -- Bypass Carry Slowdown
        if settings.bypassSlowdown then
            local isCarrying = player:GetAttribute("CarryingStolen") == true
            if isCarrying then
                local runSpeed = tonumber(player:GetAttribute("RunSpeed")) or 50
                if hum.WalkSpeed < runSpeed then
                    hum.WalkSpeed = runSpeed
                end
            end
        end

        -- Render ESP
        updateCrateEsp()
        updatePlayerEsp()
    end)

    -- ============================================================
    --  UI TABS & SECTIONS
    -- ============================================================

    -- 1. OVERVIEW TAB
    local OverviewTab = Window:CreateTab("Overview", "home")
    OverviewTab:CreateSection("Live Player Stats")
    local statLabelSpeed = OverviewTab:CreateLabel("Speed Level: Loading...")
    local statLabelCash = OverviewTab:CreateLabel("Cash Record: Loading...")
    local statLabelState = OverviewTab:CreateLabel("Status: Ready")

    task.spawn(function()
        while running do
            local spd = player:GetAttribute("SpeedLevel") or 0
            local cash = player:GetAttribute("LBTHCashRecord") or 0
            local carrying = player:GetAttribute("CarryingStolen") == true
            local safe = player:GetAttribute("InSafeZone") == true

            if statLabelSpeed and statLabelSpeed.SetText then
                statLabelSpeed:SetText(string.format("Speed Level: %s", tostring(spd)))
            end
            if statLabelCash and statLabelCash.SetText then
                statLabelCash:SetText(string.format("Cash Record: $%s", tostring(cash)))
            end
            if statLabelState and statLabelState.SetText then
                local st = safe and "In SafeZone" or "In Combat Zone"
                if carrying then st = st .. " [🎒 Carrying Crate!]" end
                statLabelState:SetText("Status: " .. st)
            end
            task.wait(0.5)
        end
    end)

    OverviewTab:CreateSection("Quick Actions")
    OverviewTab:CreateButton({
        Name = "Teleport to SafeZone",
        Callback = function()
            moveToTarget(SAFEZONE_POS, "Fast Glide")
            notify("Travel", "Teleported to SafeZone!")
        end
    })
    OverviewTab:CreateButton({
        Name = "Claim All Index Rewards Now",
        Callback = function()
            if IndexClaimAllRemote then
                pcall(function() IndexClaimAllRemote:FireServer() end)
                notify("Rewards", "Index rewards claimed!")
            end
        end
    })
    OverviewTab:CreateButton({
        Name = "Sell All Loot Now",
        Callback = function()
            if SellAllFunc then pcall(function() SellAllFunc:InvokeServer() end) end
            if SellDoRemote then pcall(function() SellDoRemote:FireServer() end) end
            notify("Economy", "Items sold!")
        end
    })

    -- 2. STEAL FARM TAB
    local StealTab = Window:CreateTab("Steal Farm", "box")
    StealTab:CreateSection("Automated Crate Heist")
    StealTab:CreateToggle({
        Name = "Auto Steal Crates",
        CurrentValue = false,
        Flag = "StealAutoCrate",
        Callback = function(v)
            settings.autoSteal = v
            if v then
                settings.autoTreadmillLock = false
                forceDismountAndUnanchor()
                notify("Auto Steal", "Steal Loop Activated 😈")
            end
        end
    })
    StealTab:CreateDropdown({
        Name = "Minimum Rarity Filter",
        Options = {"All", "Uncommon+", "Rare+", "Epic+", "Legendary+", "Mythic+", "Cosmic+"},
        CurrentOption = {"All"},
        Flag = "StealMinRarity",
        Callback = function(v)
            settings.minRarity = type(v) == "table" and v[1] or v
        end
    })
    StealTab:CreateToggle({
        Name = "Smart Match Carry Tier (Anti-Reject)",
        CurrentValue = true,
        Flag = "StealMatchCarryTier",
        Callback = function(v)
            settings.matchCarryTier = v
        end
    })
    StealTab:CreateDropdown({
        Name = "Movement Method",
        Options = {"Instant Flash Vacuum (ดึงเข้าตัว)", "Fast Glide", "Instant Snap", "Walk"},
        CurrentOption = {"Instant Flash Vacuum (ดึงเข้าตัว)"},
        Flag = "StealMoveMethod",
        Callback = function(v)
            settings.stealMethod = type(v) == "table" and v[1] or v
        end
    })
    StealTab:CreateSlider({
        Name = "Glide Flight Speed",
        Range = {100, 600},
        Increment = 25,
        CurrentValue = 350,
        Suffix = " studs/s",
        Flag = "StealGlideSpd",
        Callback = function(v)
            settings.glideSpeed = v
        end
    })
    StealTab:CreateToggle({
        Name = "Auto Escape to SafeZone",
        CurrentValue = true,
        Flag = "StealAutoReturn",
        Callback = function(v)
            settings.autoReturnSafeZone = v
        end
    })
    StealTab:CreateToggle({
        Name = "Bypass Carry Slowdown",
        CurrentValue = true,
        Flag = "StealBypassSlow",
        Callback = function(v)
            settings.bypassSlowdown = v
        end
    })
    StealTab:CreateToggle({
        Name = "Auto Place Banked Crates to Plot",
        CurrentValue = true,
        Flag = "StealAutoPlacePlot",
        Callback = function(v)
            settings.autoPlaceCrates = v
        end
    })
    StealTab:CreateToggle({
        Name = "Auto Instant Open / Appraise Crates",
        CurrentValue = true,
        Flag = "StealAutoOpenPlot",
        Callback = function(v)
            settings.autoOpenCrates = v
        end
    })

    -- 3. SPEED FARM TAB
    local SpeedTab = Window:CreateTab("Speed Farm", "zap")
    SpeedTab:CreateSection("Speed & Treadmill Automation")
    SpeedTab:CreateToggle({
        Name = "Auto Remote Speed Upgrade",
        CurrentValue = false,
        Flag = "SpeedAutoUpgrade",
        Callback = function(v)
            settings.autoSpeedUpgrade = v
            if v then notify("Speed", "Auto Speed Upgrade Started ⚡") end
        end
    })
    SpeedTab:CreateSlider({
        Name = "Speed Upgrade Delay",
        Range = {0.05, 1},
        Increment = 0.05,
        CurrentValue = 0.1,
        Suffix = " s",
        Flag = "SpeedUpgradeDelay",
        Callback = function(v)
            settings.speedUpgradeDelay = v
        end
    })
    SpeedTab:CreateToggle({
        Name = "Auto Treadmill Upgrade",
        CurrentValue = false,
        Flag = "SpeedTreadmillUpgrade",
        Callback = function(v)
            settings.autoTreadmillUpgrade = v
        end
    })
    SpeedTab:CreateToggle({
        Name = "Lock to Personal Treadmill",
        CurrentValue = false,
        Flag = "SpeedLockTreadmill",
        Callback = function(v)
            settings.autoTreadmillLock = v
            if v then
                local beltCF = getMyBeltCFrame()
                if beltCF then moveToTarget(beltCF.Position, "Fast Glide") end
            end
        end
    })
    SpeedTab:CreateSection("Auto Rebirth")
    SpeedTab:CreateToggle({
        Name = "Auto Rebirth",
        CurrentValue = false,
        Flag = "SpeedAutoRebirth",
        Callback = function(v)
            settings.autoRebirth = v
        end
    })
    SpeedTab:CreateSlider({
        Name = "Rebirth Target Speed",
        Range = {10000, 500000},
        Increment = 10000,
        CurrentValue = 100000,
        Suffix = " spd",
        Flag = "SpeedRebirthTarget",
        Callback = function(v)
            settings.rebirthThreshold = v
        end
    })

    -- 4. ECONOMY & BASE TAB
    local EconTab = Window:CreateTab("Economy", "dollar-sign")
    EconTab:CreateSection("Auto Sales & Plot Upgrades")
    EconTab:CreateToggle({
        Name = "Auto Remote Sell",
        CurrentValue = false,
        Flag = "EconAutoSell",
        Callback = function(v)
            settings.autoSell = v
        end
    })
    EconTab:CreateSlider({
        Name = "Sell Check Interval",
        Range = {1, 15},
        Increment = 1,
        CurrentValue = 3,
        Suffix = " s",
        Flag = "EconSellInterval",
        Callback = function(v)
            settings.sellInterval = v
        end
    })
    EconTab:CreateToggle({
        Name = "Auto Base Income Collect",
        CurrentValue = false,
        Flag = "EconBaseCollect",
        Callback = function(v)
            settings.autoBaseCollect = v
        end
    })
    EconTab:CreateToggle({
        Name = "Auto Base Slot Upgrade",
        CurrentValue = false,
        Flag = "EconSlotUpgrade",
        Callback = function(v)
            settings.autoSlotUpgrade = v
        end
    })
    EconTab:CreateSection("Free Gifts & Index")
    EconTab:CreateToggle({
        Name = "Auto Index Claim All",
        CurrentValue = false,
        Flag = "EconAutoIndex",
        Callback = function(v)
            settings.autoIndexClaim = v
        end
    })
    EconTab:CreateToggle({
        Name = "Auto Free Gift Chest",
        CurrentValue = false,
        Flag = "EconFreeGift",
        Callback = function(v)
            settings.autoFreeGift = v
        end
    })
    EconTab:CreateToggle({
        Name = "Auto Offline Income Claim",
        CurrentValue = false,
        Flag = "EconOfflineClaim",
        Callback = function(v)
            settings.autoOfflineClaim = v
        end
    })
    EconTab:CreateToggle({
        Name = "Auto Spin Wheel",
        CurrentValue = false,
        Flag = "EconSpinWheel",
        Callback = function(v)
            settings.autoSpin = v
        end
    })

    -- 5. COMBAT TAB
    local CombatTab = Window:CreateTab("Combat", "shield")
    CombatTab:CreateSection("PVP Defense")
    CombatTab:CreateToggle({
        Name = "Bat Slap Aura (Outside SafeZone)",
        CurrentValue = false,
        Flag = "CombatBatAura",
        Callback = function(v)
            settings.batSlapAura = v
        end
    })
    CombatTab:CreateSlider({
        Name = "Bat Aura Distance",
        Range = {10, 35},
        Increment = 1,
        CurrentValue = 22,
        Suffix = " studs",
        Flag = "CombatBatDist",
        Callback = function(v)
            settings.batAuraRange = v
        end
    })
    CombatTab:CreateToggle({
        Name = "Anti-Ragdoll / Anti-Tumble",
        CurrentValue = true,
        Flag = "CombatAntiRagdoll",
        Callback = function(v)
            settings.antiRagdoll = v
        end
    })
    CombatTab:CreateButton({
        Name = "Drop Bear Trap Here",
        Callback = function()
            local trap = player.Backpack:FindFirstChild("Bear Trap")
            local _, hum = getCharacter()
            if trap and hum then
                hum:EquipTool(trap)
                task.wait(0.1)
            end
            if BearTrapRemote then
                pcall(function() BearTrapRemote:FireServer() end)
            end
        end
    })

    -- 6. VISUALS TAB
    local VisualsTab = Window:CreateTab("Visuals", "eye")
    VisualsTab:CreateSection("Crate Visuals (Drawing API)")
    VisualsTab:CreateToggle({
        Name = "Crate ESP",
        CurrentValue = false,
        Flag = "EspCrateToggle",
        Callback = function(v)
            settings.crateEsp = v
            if not v then
                for k, entry in pairs(espCache) do
                    if entry.kind == "crate" then removeEspEntry(k) end
                end
            end
        end
    })
    VisualsTab:CreateDropdown({
        Name = "Crate ESP Filter",
        Options = {"All", "Uncommon+", "Rare+", "Epic+", "Legendary+", "Mythic+"},
        CurrentOption = {"All"},
        Flag = "EspCrateFilter",
        Callback = function(v)
            settings.crateEspMinRarity = type(v) == "table" and v[1] or v
        end
    })
    VisualsTab:CreateSlider({
        Name = "Crate ESP Max Distance",
        Range = {500, 5000},
        Increment = 250,
        CurrentValue = 3500,
        Suffix = " studs",
        Flag = "EspCrateMaxDist",
        Callback = function(v)
            settings.crateEspMaxDist = v
        end
    })
    VisualsTab:CreateSection("Player Visuals")
    VisualsTab:CreateToggle({
        Name = "Player Carrier ESP",
        CurrentValue = false,
        Flag = "EspPlayerToggle",
        Callback = function(v)
            settings.playerEsp = v
            if not v then
                for k, entry in pairs(espCache) do
                    if entry.kind == "player" then removeEspEntry(k) end
                end
            end
        end
    })

    -- 7. TELEPORTS TAB
    local TeleportTab = Window:CreateTab("Teleports", "map-pin")
    TeleportTab:CreateSection("Base Waypoints")
    TeleportTab:CreateButton({
        Name = "TP to SafeZone Lobby",
        Callback = function()
            moveToTarget(SAFEZONE_POS, "Fast Glide")
            notify("Travel", "Teleported to SafeZone!")
        end
    })
    TeleportTab:CreateButton({
        Name = "TP to Personal Treadmill",
        Callback = function()
            local beltCF = getMyBeltCFrame()
            if beltCF then
                moveToTarget(beltCF.Position, "Fast Glide")
            else
                notify("Travel", "Personal treadmill not found")
            end
        end
    })
    TeleportTab:CreateSection("Rich Zone Teleports")
    for zoneName, coords in pairs(ZONE_WAYPOINTS) do
        TeleportTab:CreateButton({
            Name = "TP: " .. zoneName,
            Callback = function()
                moveToTarget(coords, "Fast Glide")
                notify("Travel", "Arrived at " .. zoneName)
            end
        })
    end

    -- ============================================================
    --  TAB ORDERING & CLEANUP
    -- ============================================================
    if Window and type(Window.SortTabs) == "function" then
        pcall(function()
            Window:SortTabs({"Overview", "Steal Farm", "Speed Farm", "Economy", "Combat", "Visuals", "Teleports"})
        end)
    end

    local function destroy()
        running = false
        for _, conn in ipairs(connections) do
            pcall(function() conn:Disconnect() end)
        end
        clearAllEsp()
        for _, d in ipairs(drawingObjects) do
            pcall(function() d:Remove() end)
        end
    end

    environment.__RAVEN_STEAL_RICH = {
        Destroy = destroy,
        settings = settings,
        moveToTarget = moveToTarget,
        forceDismount = forceDismountAndUnanchor,
    }

    notify("RAVEN HUB", "Steal From The Rich! v1.1.0 Loaded 😈")
    return environment.__RAVEN_STEAL_RICH
end
