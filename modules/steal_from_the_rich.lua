--[[
    RAVEN HUB | Steal From The Rich!
    PlaceId: 120475074479690 | GameId: 10753751277
    Version: v1.3.1

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
    local SAFEZONE_POS = Vector3.new(2465.0, 5.0, -940.0)

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
        matchCarryTier      = true, -- Match player CarryStat so bot never targets impossible crates
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
        disableGuards       = true, -- Freeze and displace all zone guards and bosses to the void
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
        if DismountRemote and player:GetAttribute("OnTreadmill") == true then
            pcall(function() DismountRemote:FireServer() end)
            task.wait(0.12)
        end
        player:SetAttribute("OnTreadmill", false)
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") and p.Anchored then
                    p.Anchored = false
                end
            end
        end
        if root then
            root.Anchored = false
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

    -- ============================================================
    --  ZONE GUARDS DISABLER (FREEZE & VOID DISPLACEMENT)
    -- ============================================================
    local ZONE_GUARDS = {
        "Archeologist", "Gold Tycoon", "Museum Worker", "Mafia Boss", "Pirate",
        "Bodyguard 1", "Bodyguard 2", "Demon Dragon", "Fan 1", "dinosaur (active)",
        "Jeweler", "Astronaut", "demon king", "Celebirty NPC", "Angel Queen", "Angel Beast (chaser)"
    }

    local function disableZoneGuards()
        for _, name in ipairs(ZONE_GUARDS) do
            local m = Workspace:FindFirstChild(name)
            if m and m:IsA("Model") then
                for _, p in ipairs(m:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.CanCollide = false
                        p.CanTouch = false
                        p.CanQuery = false
                        p.CFrame = CFrame.new(0, -2500, 0)
                        p.Anchored = true
                    end
                end
                local hum = m:FindFirstChildOfClass("Humanoid")
                if hum and hum.WalkSpeed > 0 then
                    hum.WalkSpeed = 0
                end
            end
        end
    end

    -- ============================================================
    --  CRATE OFFLOADING & PLACEMENT (UNBLOCK HANDS)
    -- ============================================================
    local function getInventoryCrate()
        local char = player.Character
        if char then
            for _, t in ipairs(char:GetChildren()) do
                if t:IsA("Tool") and (t.Name == "Crate" or t:GetAttribute("CrateUid")) then
                    return t
                end
            end
        end
        if player.Backpack then
            for _, t in ipairs(player.Backpack:GetChildren()) do
                if t:IsA("Tool") and (t.Name == "Crate" or t:GetAttribute("CrateUid")) then
                    return t
                end
            end
        end
        return nil
    end

    local cachedTryPlace = nil
    local function getTryPlaceFunction()
        if cachedTryPlace then return cachedTryPlace end
        if type(getgc) ~= "function" then return nil end
        for _, f in ipairs(getgc(false)) do
            if type(f) == "function" and not isexecutorclosure(f) then
                local src, name = debug.info(f, "sn")
                if src and src:find("LBTHPlacementMarkerClient") and name == "tryPlace" then
                    cachedTryPlace = f
                    return f
                end
            end
        end
        return nil
    end

    local function offloadInventoryCrate()
        local crateTool = getInventoryCrate()
        if not crateTool then return false end

        local char, hum, root = getCharacter()
        local plot, floor = getPlayerPlot()

        -- 1. Auto open any ready appraisal crates first to free up slots
        if settings.autoOpenCrates and CrateTimersFunc then
            pcall(function()
                local list = CrateTimersFunc:InvokeServer("list")
                if type(list) == "table" then
                    for _, item in ipairs(list) do
                        if item.Ready then
                            CrateTimersFunc:InvokeServer("open", item.Uid)
                        end
                    end
                end
            end)
        end

        -- 2. Auto sell items to clear stands if enabled
        if settings.autoSell and SellDoRemote then
            pcall(function() SellDoRemote:FireServer("all") end)
        end

        if plot and floor and root then
            -- Equip crate tool so it can be placed
            if hum and crateTool.Parent ~= char then
                hum:EquipTool(crateTool)
                task.wait(0.12)
            end

            -- Fast Glide to plot floor center
            local plotCenter = floor.Position + Vector3.new(0, 3, 0)
            moveToTarget(plotCenter, "Fast Glide", 450)

            -- Gather all existing fixtures/stands/crates on the plot floor
            local obstacles = {}
            for _, child in ipairs(floor:GetChildren()) do
                if child:IsA("PVInstance") then
                    local pName = child.Name
                    if pName == "AppraisingCrate" or pName == "ItemStand" or pName == "PlayerSpawn" or pName == "treadmill sign" then
                        table.insert(obstacles, child:GetPivot().Position)
                    end
                end
            end

            local topY = floor.Position.Y + floor.Size.Y / 2
            local halfX = math.max(floor.Size.X / 2 - 3, 2)
            local halfZ = math.max(floor.Size.Z / 2 - 3, 2)

            -- Grid scan for collision-free candidate positions
            local candidates = {}
            for ox = -halfX, halfX, 3.2 do
                for oz = -halfZ, halfZ, 3.2 do
                    local worldPos = floor.CFrame:PointToWorldSpace(Vector3.new(ox, floor.Size.Y / 2, oz))
                    local collides = false
                    for _, obsPos in ipairs(obstacles) do
                        local dx = obsPos.X - worldPos.X
                        local dz = obsPos.Z - worldPos.Z
                        if dx * dx + dz * dz < 12.25 then -- distance < 3.5 studs
                            collides = true
                            break
                        end
                    end
                    if not collides then
                        table.insert(candidates, worldPos)
                    end
                end
            end

            -- Sort candidates by distance to plot center
            table.sort(candidates, function(a, b)
                return (a - floor.Position).Magnitude < (b - floor.Position).Magnitude
            end)

            local placed = false
            for i = 1, math.min(#candidates, 4) do
                local slotPos = candidates[i]
                root.CFrame = CFrame.new(slotPos + Vector3.new(0, 2.5, 0))
                root.AssemblyLinearVelocity = Vector3.zero

                local cam = Workspace.CurrentCamera
                if cam then
                    cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(0, 1.5, 0), slotPos)
                end
                task.wait(0.08)

                if PlaceAtRemote then
                    pcall(function() PlaceAtRemote:FireServer(slotPos, 0) end)
                    task.wait(0.25)
                end

                placed = (crateTool.Parent == nil or (crateTool.Parent ~= char and crateTool.Parent ~= player.Backpack))
                if placed then break end
            end

            -- Fallback 1: Try LBTHPlacementMarkerClient tryPlace function
            if not placed then
                local tryPlace = getTryPlaceFunction()
                if tryPlace then
                    pcall(tryPlace)
                    task.wait(0.25)
                    placed = (crateTool.Parent == nil or (crateTool.Parent ~= char and crateTool.Parent ~= player.Backpack))
                end
            end

            -- Fallback 2: Unequip tools to Backpack so character hands are NEVER clogged
            if hum then
                hum:UnequipTools()
            end

            return placed
        else
            -- If no plot found, unequip to backpack so hands are free
            if hum then
                hum:UnequipTools()
            end
        end

        return false
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

    local failedCrates = {}
    local function cleanFailedCrates()
        local now = os.clock()
        for c, expire in pairs(failedCrates) do
            if now >= expire then
                failedCrates[c] = nil
            end
        end
    end

    local function findBestCrate()
        cleanFailedCrates()
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

        local now = os.clock()
        local candidates = {}
        for _, crate in ipairs(crates:GetChildren()) do
            if crate:IsA("Model") then
                local failedUntil = failedCrates[crate]
                if not (failedUntil and now < failedUntil) then
                    local prompt = crate:FindFirstChildWhichIsA("ProximityPrompt", true)
                    local part = (prompt and prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent)
                        or crate:FindFirstChild("Cube")
                        or crate:FindFirstChildWhichIsA("BasePart")

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
        end

        -- Fallback: If no candidate matched due to strict filters or blacklists, find any non-blacklisted crate
        if #candidates == 0 then
            for _, crate in ipairs(crates:GetChildren()) do
                if crate:IsA("Model") then
                    local failedUntil = failedCrates[crate]
                    if not (failedUntil and now < failedUntil) then
                        local prompt = crate:FindFirstChildWhichIsA("ProximityPrompt", true)
                        local part = (prompt and prompt.Parent and prompt.Parent:IsA("BasePart") and prompt.Parent)
                            or crate:FindFirstChild("Cube")
                            or crate:FindFirstChildWhichIsA("BasePart")

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
                -- 1. If player has a Crate tool in hand or backpack, offload it onto plot so hands are 100% free
                if settings.autoPlaceCrates and getInventoryCrate() then
                    offloadInventoryCrate()
                end

                local isCarrying = player:GetAttribute("CarryingStolen") == true

                -- Auto-dismiss any modal dialogs (SellDialogUI, LBTHPurchaseThanks, etc.)
                local pgui = player:FindFirstChild("PlayerGui")
                if pgui then
                    for _, dName in ipairs({"SellDialogUI", "LBTHPurchaseThanks"}) do
                        local dlg = pgui:FindFirstChild(dName)
                        if dlg and dlg:IsA("ScreenGui") and dlg.Enabled then
                            local closeBtn = dlg:FindFirstChild("Close", true) or dlg:FindFirstChild("Exit", true) or dlg:FindFirstChild("Cancel", true)
                            if closeBtn and closeBtn:IsA("GuiButton") and type(getconnections) == "function" then
                                for _, c in ipairs(getconnections(closeBtn.MouseButton1Click) or {}) do
                                    pcall(function() c:Fire() end)
                                end
                            end
                        end
                    end
                end

                -- 2. Steal & Bank Execution
                if isCarrying then
                    -- Carrying stolen crate -> Glide to SafeZone to bank it into cash!
                    moveToTarget(SAFEZONE_POS + Vector3.new(0, 1.5, 0), "Fast Glide", 400)
                    local t0 = os.clock()
                    while running and settings.autoSteal and player:GetAttribute("CarryingStolen") == true and (os.clock() - t0 < 3.5) do
                        task.wait(0.1)
                    end
                    task.wait(0.2)
                    -- Immediately offload any rewarded crate tool to plot floor so hands stay free
                    if settings.autoPlaceCrates and getInventoryCrate() then
                        offloadInventoryCrate()
                    end
                    -- Auto sell after banking if enabled
                    if settings.autoSell then
                        if SellAllFunc then pcall(function() SellAllFunc:InvokeServer() end) end
                        if SellDoRemote then pcall(function() SellDoRemote:FireServer("all") end) end
                    end
                else
                    -- Not carrying crate -> Find best crate and steal
                    local bestCrate, prompt, worldPos, cubePart = findBestCrate()
                    if bestCrate and prompt and cubePart then
                        local targetPos = cubePart.Position
                        local okMove = moveToTarget(targetPos + Vector3.new(0, 1.2, 0), "Fast Glide", 400)
                        if okMove then
                            task.wait(0.08)
                            local _, humPart, rootPart = getCharacter()
                            if humPart then
                                humPart:UnequipTools()
                            end
                            local cam = Workspace.CurrentCamera
                            if rootPart then
                                local diff = (rootPart.Position - targetPos)
                                local flatDir = Vector3.new(diff.X, 0, diff.Z)
                                if flatDir.Magnitude < 0.1 then
                                    flatDir = Vector3.new(0, 0, 1)
                                end
                                local standPos = targetPos + flatDir.Unit * 2.2
                                rootPart.CFrame = CFrame.lookAt(Vector3.new(standPos.X, targetPos.Y + 1.2, standPos.Z), targetPos)
                                rootPart.AssemblyLinearVelocity = Vector3.zero
                            end
                            if cam and rootPart then
                                cam.CFrame = CFrame.lookAt(rootPart.Position + Vector3.new(0, 1.5, 0), targetPos)
                            end
                            task.wait(0.05)

                            -- Trigger ProximityPrompt (Potassium & standard executor compatible)
                            local holdSec = prompt.HoldDuration or 1
                            if type(fireproximityprompt) == "function" then
                                pcall(function() fireproximityprompt(prompt) end)
                                pcall(function() fireproximityprompt(prompt, 0) end)
                                pcall(function() fireproximityprompt(prompt, prompt.MaxActivationDistance or 12) end)
                            else
                                local VIM = pcall(function() return game:GetService("VirtualInputManager") end) and game:GetService("VirtualInputManager")
                                if VIM then
                                    pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
                                end
                                pcall(function() prompt:InputHoldBegin() end)
                            end

                            local holdT0 = os.clock()
                            local holdMax = math.max(holdSec + 0.4, 1.2)
                            while running and settings.autoSteal and (os.clock() - holdT0 < holdMax) do
                                if player:GetAttribute("CarryingStolen") == true then
                                    break
                                end
                                if type(fireproximityprompt) == "function" then
                                    pcall(function() fireproximityprompt(prompt) end)
                                end
                                task.wait(0.1)
                            end

                            if type(fireproximityprompt) ~= "function" then
                                pcall(function() prompt:InputHoldEnd() end)
                                local VIM = pcall(function() return game:GetService("VirtualInputManager") end) and game:GetService("VirtualInputManager")
                                if VIM then
                                    pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
                                end
                            end

                            -- If crate pickup failed or was rejected by server, blacklist it for 25s
                            if player:GetAttribute("CarryingStolen") ~= true then
                                failedCrates[bestCrate] = os.clock() + 25
                            end
                            task.wait(0.08)
                        end
                    else
                        task.wait(0.3)
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
                    pcall(function() SellDoRemote:FireServer("all") end)
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

        -- Zone Guards & Bosses Disabler (Freeze to Void)
        if settings.disableGuards then
            disableZoneGuards()
        end

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
    local OverviewTab = (Window.GetTab and Window:GetTab("Overview")) or Window:CreateTab("Overview", "home")
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
        Name = "Smart Match Carry Tier",
        CurrentValue = false,
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
    StealTab:CreateToggle({
        Name = "Disable Zone Guards & Bosses (Void Freeze)",
        CurrentValue = true,
        Flag = "StealDisableGuards",
        Callback = function(v)
            settings.disableGuards = v
            if v then
                notify("Guards", "Zone Guards & Bosses Disabled 😈")
            end
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
    CombatTab:CreateToggle({
        Name = "Disable Zone Guards & Bosses (Void Freeze)",
        CurrentValue = true,
        Flag = "CombatDisableGuards",
        Callback = function(v)
            settings.disableGuards = v
            if v then
                notify("Guards", "Zone Guards & Bosses Disabled 😈")
            end
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
            Window:SortTabs({"Overview", "Steal Farm", "Speed Farm", "Economy", "Combat", "Visuals", "Teleports", "Settings"})
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

    notify("RAVEN HUB", "Steal From The Rich! v1.3.0 Loaded 😈")
    return environment.__RAVEN_STEAL_RICH
end
