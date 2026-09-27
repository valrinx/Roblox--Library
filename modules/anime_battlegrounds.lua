-- ============================================================
--   RAVEN HUB  |  Anime Battlegrounds
--   UniverseId: 10399136326  |  PlaceId: 105692919293481
--   High-Performance Combat, 100% Drawing API ESP & Mobility Engine
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Workspace = game:GetService("Workspace")
    local VirtualInputManager = game:GetService("VirtualInputManager")
    local Debris = game:GetService("Debris")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    -- Clean up previous instance
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_ANIME_BATTLEGROUNDS) == "table"
        and type(environment.__RAVEN_ANIME_BATTLEGROUNDS.Destroy) == "function" then
        pcall(environment.__RAVEN_ANIME_BATTLEGROUNDS.Destroy)
    end

    -- Retire transient prototypes so only the repository module owns aim hooks/UI.
    if type(environment.RAVEN_SKILL_AIM_V3) == "table"
        and type(environment.RAVEN_SKILL_AIM_V3.Stop) == "function" then
        pcall(function() environment.RAVEN_SKILL_AIM_V3:Stop() end)
    end

    local running = true
    local connections = {}
    local espObjects = {}

    -- Settings
    local settings = {
        -- Combat
        -- Legacy target-finder defaults are retained for reach/backstab systems.
        aimlockPart = "HumanoidRootPart",
        aimlockMaxDist = 350,
        reachEnabled = true,
        reachDistance = 12,
        allAroundHit = true,
        wallCheckBypass = false,
        autoM1 = false,
        autoM1Range = 12,
        autoM1Interval = 0.25,

        -- Visuals
        espEnabled = false,
        boxEsp = true,
        nameEsp = true,
        healthEsp = true,
        movesetEsp = true,
        distanceEsp = true,
        nativeHitboxDebug = false,

        -- Mobility
        speedEnabled = false,
        speedValue = 35,
        infiniteDash = false,
        dashDistance = 11,
        infiniteJump = false,
        antiRagdoll = false,

        -- Backstab Dash (Legit Movement)
        backstabKey = Enum.KeyCode.V,
        backstabDistance = 2.5,
        backstabMaxRange = 250,
        backstabDashSpeed = 120,
        backstabAutoFace = true,
        backstabAutoAttack = true,
        backstabAlignCam = true,
        backstabPlaySound = true,
        backstabPlayAnim = true,
    }

    local lastM1Time = 0

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function()
                ui:Notify({Title = title, Content = content, Duration = 4})
            end)
        end
    end

    local function connect(signal, callback)
        local conn = signal:Connect(callback)
        table.insert(connections, conn)
        return conn
    end

    local function getLocalRoot()
        local char = localPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getLocalHumanoid()
        local char = localPlayer.Character
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function isTargetAlive(player)
        if not player or not player.Character then return false end
        local hum = player.Character:FindFirstChildOfClass("Humanoid")
        local root = player.Character:FindFirstChild("HumanoidRootPart")
        return hum and hum.Health > 0 and root ~= nil
    end

    -- Closest Enemy Finder
    local function getClosestEnemy(maxDist, requireOnScreen)
        local closest = nil
        local shortestDist = maxDist or settings.aimlockMaxDist
        local myRoot = getLocalRoot()
        if not myRoot then return nil end

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer and isTargetAlive(p) then
                local targetRoot = p.Character:FindFirstChild(settings.aimlockPart) or p.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot then
                    local dist = (myRoot.Position - targetRoot.Position).Magnitude
                    if dist <= shortestDist then
                        if requireOnScreen then
                            local _, onScreen = camera:WorldToViewportPoint(targetRoot.Position)
                            if onScreen then
                                shortestDist = dist
                                closest = p
                            end
                        else
                            shortestDist = dist
                            closest = p
                        end
                    end
                end
            end
        end
        return closest
    end

    -- [[ SKILL AIM V4: payload direction only; never steer camera/character ]]
    -- Shared targets work across movesets. The server remains authoritative over range and hits.
    local CollectionService = game:GetService("CollectionService")
    local skillAim = {
        Enabled = true, Fov = 175, Prediction = 0.07, LockUntil = 0,
        RangeAware = true, RangeMargin = 0.95, RangeInfo = nil,
        ActiveAbilityId = nil, ProfileUntil = 0, Registry = nil,
        Target = nil, VisualTarget = nil, LastScan = 0, ScanInterval = 0.2,
        Original = {}, Wrappers = {}, Packets = nil, Aim = nil,
        Stats = {acquired = 0, redirected = 0, passed = 0, outOfRange = 0},
    }
    local function aimTargetValid(target)
        if not target or not target.model or not target.model.Parent then return nil end
        local root = target.model:FindFirstChild("HumanoidRootPart")
        local hum = target.model:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 or target.model:GetAttribute("IsGhost") then return nil end
        if target.player and target.player ~= localPlayer and not localPlayer.Neutral
            and not target.player.Neutral and localPlayer.Team and target.player.Team == localPlayer.Team then
            return nil
        end
        return root
    end
    local function aimPoint(target)
        local root = aimTargetValid(target)
        if not root then return nil end
        local velocity = root.AssemblyLinearVelocity * skillAim.Prediction
        if velocity.Magnitude > 5 then velocity = velocity.Unit * 5 end
        return root.Position + Vector3.new(0, 1.35, 0) + velocity
    end
    -- Resolve declared reach separately from movement distances and hitbox dimensions.
    -- A range hint is not necessarily a server-enforced maximum.
    local explicitRangeKeys = {
        "TravelDistance", "MaxTravel", "MaxRange", "AimRange", "MaxDistance",
        "ExtendDistance", "DetectRadius", "SeekRadius", "AttackRange",
        "GrabRange", "GrabRadius", "GrabDistance", "Reach", "M1Reach",
        "SwordReach", "HandReach",
    }
    local hintRangeKeys = {
        "DashDistance", "RunDistance", "TeleportDistance", "HopDistance",
        "SwoopDistance", "CarryDistance", "HoldRadius", "SpawnDistance",
        "HitboxSize", "Hitbox", "FireHitbox", "FinalHitbox", "SlamHitbox",
    }
    local function skillRangeProfile(config)
        if type(config) ~= "table" then
            return {classification = "unknown", max = nil, key = nil}
        end
        for _, key in ipairs(explicitRangeKeys) do
            local n = tonumber(config[key])
            if n and n > 0 then
                return {classification = "declared", max = n, key = key}
            end
        end
        for _, key in ipairs(hintRangeKeys) do
            local v = config[key]
            if v ~= nil then
                return {classification = "hint-only", hint = v, key = key}
            end
        end
        return {classification = "unknown", max = nil, key = nil}
    end
    local function setSkillRange(abilityId, packetName)
        local config
        if abilityId ~= nil and skillAim.Registry then
            local ok, ability = pcall(skillAim.Registry.GetAbilityById, abilityId)
            if ok and type(ability) == "table" then config = ability.Config end
        end
        if not config and type(packetName) == "string" then
            local kind = packetName:match("^([%w_]+)Cast$")
                or packetName:match("^([%w_]+)Fire$")
            local module = kind and ReplicatedStorage.Shared.Abilities.Config:FindFirstChild(kind)
            if module and module:IsA("ModuleScript") then
                local ok, value = pcall(require, module)
                if ok then config = value end
            end
        end
        skillAim.ActiveAbilityId = abilityId
        skillAim.RangeInfo = skillRangeProfile(config)
        skillAim.ProfileUntil = os.clock() + math.max(5, (config and config.CastTimeout) or 5)
        return skillAim.RangeInfo
    end
    local function activeSkillRange()
        if skillAim.RangeAware and os.clock() <= skillAim.ProfileUntil then
            local info = skillAim.RangeInfo
            if info and info.classification == "declared" then
                return info.max * skillAim.RangeMargin
            end
        end
        return nil
    end
    local function chooseSkillTarget()
        local cam = Workspace.CurrentCamera
        if not cam or not getLocalRoot() then return nil end
        local center, closest, chosen = cam.ViewportSize / 2, skillAim.Fov, nil
        local ownRoot, range = getLocalRoot(), activeSkillRange()
        local function consider(model, player, name)
            local candidate = {model = model, player = player, name = name}
            local point = aimPoint(candidate)
            if not point then return end
            if range and (point - ownRoot.Position).Magnitude > range then
                skillAim.Stats.outOfRange += 1
                return
            end
            local view, onScreen = cam:WorldToViewportPoint(point)
            local pixels = (Vector2.new(view.X, view.Y) - center).Magnitude
            if not onScreen or view.Z <= 0 or pixels >= closest then return end
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = localPlayer.Character and {localPlayer.Character} or {}
            local ray = Workspace:Raycast(cam.CFrame.Position, point - cam.CFrame.Position, params)
            if ray and not ray.Instance:IsDescendantOf(model) then return end
            closest, chosen = pixels, candidate
        end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                consider(player.Character, player, player.DisplayName)
            end
        end
        for _, dummy in ipairs(CollectionService:GetTagged("Dummy")) do
            if dummy:IsA("Model") then consider(dummy, nil, dummy.Name) end
        end
        return chosen
    end
    local function acquireSkillTarget()
        if not skillAim.Enabled then return nil end
        local target = chooseSkillTarget()
        skillAim.Target = target
        skillAim.LockUntil = target and os.clock() + 5 or 0
        if target then skillAim.Stats.acquired += 1 end
        return target
    end
    local function currentSkillPoint(reacquire)
        if not skillAim.Enabled then return nil end
        if os.clock() > skillAim.LockUntil or not aimTargetValid(skillAim.Target) then
            skillAim.Target = nil
        end
        local point, ownRoot = aimPoint(skillAim.Target), getLocalRoot()
        local range = activeSkillRange()
        if point and range and ownRoot and (point - ownRoot.Position).Magnitude > range then
            skillAim.Stats.outOfRange += 1
            skillAim.Target, point = nil, nil
        end
        if not point and reacquire then
            acquireSkillTarget()
            point = aimPoint(skillAim.Target)
        end
        return point
    end
    local function restoreSkillAim()
        if skillAim.Aim then
            if skillAim.Aim.Point == skillAim.Wrappers.Point then
                skillAim.Aim.Point = skillAim.Original.Point
            end
            if skillAim.Aim.Direction == skillAim.Wrappers.Direction then
                skillAim.Aim.Direction = skillAim.Original.Direction
            end
        end
        if skillAim.Packets then
            for name, wrapper in pairs(skillAim.Wrappers) do
                local packet = skillAim.Packets[name]
                if packet and packet.send == wrapper then packet.send = skillAim.Original[name] end
            end
        end
        skillAim.Target = nil
        skillAim.ActiveAbilityId, skillAim.RangeInfo, skillAim.ProfileUntil = nil, nil, 0
        skillAim.Enabled = false
    end
    local function installSkillAim()
        if not skillAim.Enabled then return end
        local ok, shared = pcall(function() return ReplicatedStorage:WaitForChild("Shared", 3) end)
        if not ok or not shared then return end
        local okAim, aim = pcall(function() return require(shared.Client.Aim) end)
        local okNetwork, network = pcall(function() return require(shared.Network) end)
        if not okAim or not okNetwork or type(aim) ~= "table"
            or type(aim.Point) ~= "function" or type(aim.Direction) ~= "function"
            or type(network) ~= "table" or not network.Combat then return end
        local packets = network.Combat.packets
        if type(packets) ~= "table" then return end
        local okRegistry, registry = pcall(function()
            return require(shared.Abilities.Registry)
        end)
        if okRegistry and type(registry) == "table" then skillAim.Registry = registry end
        skillAim.Aim, skillAim.Packets = aim, packets
        skillAim.Original.Point, skillAim.Original.Direction = aim.Point, aim.Direction
        skillAim.Wrappers.Point = function(...)
            local point = currentSkillPoint(false)
            if point then return point end
            return skillAim.Original.Point(...)
        end
        skillAim.Wrappers.Direction = function(...)
            local point, cam = currentSkillPoint(false), Workspace.CurrentCamera
            if point and cam then
                local direction = point - cam.CFrame.Position
                if direction.Magnitude > 0.01 then return direction.Unit end
            end
            return skillAim.Original.Direction(...)
        end
        aim.Point, aim.Direction = skillAim.Wrappers.Point, skillAim.Wrappers.Direction
        for name, packet in pairs(packets) do
            local outgoing = type(name) == "string" and (name == "AbilityCast" or name == "AbilityCharge"
                or name == "AbilityFire" or name:match("Cast$") or name:match("Fire$")
                or name:match("Fired$") or name:match("Shoot$") or name:match("Shot$")
                or name:match("Aim$") or name:match("Release$"))
            if outgoing and type(packet) == "table" and type(packet.send) == "function" then
                local original = packet.send
                skillAim.Original[name] = original
                local wrapper = function(payload, ...)
                    if skillAim.Enabled and type(payload) == "table" then
                        if name == "AbilityCast" and payload.AbilityId ~= nil then
                            setSkillRange(payload.AbilityId, nil)
                            acquireSkillTarget()
                        elseif name == "AbilityCharge" and payload.AbilityId ~= nil then
                            if payload.AbilityId ~= skillAim.ActiveAbilityId then
                                setSkillRange(payload.AbilityId, nil)
                            end
                            if not aimTargetValid(skillAim.Target) then acquireSkillTarget() end
                            if skillAim.Target then skillAim.LockUntil = os.clock() + 5 end
                        elseif name:match("Cast$") and name ~= "AbilityCast" then
                            setSkillRange(payload.AbilityId, name)
                            acquireSkillTarget()
                        end
                        if typeof(payload.Look) == "Vector3" then
                            local point, own = currentSkillPoint(true), getLocalRoot()
                            if point and own then
                                local delta = point - own.Position
                                local flat = Vector3.new(delta.X, 0, delta.Z)
                                if flat.Magnitude > 0.01 then
                                    local copy = table.clone(payload)
                                    -- Preserve vertical aiming only for packets that already use it.
                                    copy.Look = math.abs(payload.Look.Y) > 0.05 and delta.Unit or flat.Unit
                                    skillAim.Stats.redirected += 1
                                    skillAim.LockUntil = os.clock() + 2.5
                                    return original(copy, ...)
                                end
                            end
                            skillAim.Stats.passed += 1
                        end
                    end
                    return original(payload, ...)
                end
                skillAim.Wrappers[name] = wrapper
                packet.send = wrapper
            end
        end
    end

    -- Classic Smooth HUD: scan every 0.2s; move only the target brackets each frame.
    local function createSkillAimHUD()
        local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        local stale = pg:FindFirstChild("RAVEN_SkillAim_V4")
        if stale then stale:Destroy() end
        local gui = Instance.new("ScreenGui")
        gui.Name = "RAVEN_SkillAim_V4"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 180
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
        gui.Parent = pg
        local ring = Instance.new("Frame")
        ring.Name = "FOVRing"
        ring.Size = UDim2.fromOffset(skillAim.Fov * 2, skillAim.Fov * 2)
        ring.Position = UDim2.fromScale(0.5, 0.5)
        ring.AnchorPoint = Vector2.new(0.5, 0.5)
        ring.BackgroundTransparency = 1
        ring.BorderSizePixel = 0
        ring.Parent = gui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = ring
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 2.4
        stroke.Transparency = 0.06
        stroke.Color = Color3.fromRGB(255, 212, 69)
        stroke.Parent = ring
        local ticks = Instance.new("Frame")
        ticks.Name = "Ticks"
        ticks.Size = UDim2.fromScale(1, 1)
        ticks.BackgroundTransparency = 1
        ticks.Parent = gui
        for i = 1, 36 do
            local angle = i * math.pi * 2 / 36
            local tick = Instance.new("Frame")
            tick.Size = UDim2.fromOffset(i % 3 == 0 and 4 or 3, i % 3 == 0 and 4 or 3)
            tick.AnchorPoint = Vector2.new(0.5, 0.5)
            tick.Position = UDim2.new(0.5, math.cos(angle) * skillAim.Fov,
                0.5, math.sin(angle) * skillAim.Fov)
            tick.BackgroundColor3 = stroke.Color
            tick.BorderSizePixel = 0
            tick.Parent = ticks
        end
        local label = Instance.new("TextLabel")
        label.Name = "AimStatus"
        label.AnchorPoint = Vector2.new(0.5, 0)
        label.Position = UDim2.new(0.5, 0, 0.5, skillAim.Fov + 10)
        label.Size = UDim2.fromOffset(315, 27)
        label.BackgroundColor3 = Color3.fromRGB(20, 24, 27)
        label.BackgroundTransparency = 0.26
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.TextColor3 = stroke.Color
        label.TextStrokeTransparency = 1
        label.Text = "SKILL AIM  -  NO TARGET"
        label.Parent = gui
        local lc = Instance.new("UICorner")
        lc.CornerRadius = UDim.new(0, 6)
        lc.Parent = label
        local marker = Instance.new("Frame")
        marker.Name = "TargetBrackets"
        marker.AnchorPoint = Vector2.new(0.5, 0.5)
        marker.Size = UDim2.fromOffset(62, 62)
        marker.BackgroundTransparency = 1
        marker.Visible = false
        marker.Parent = gui
        for x = 0, 1 do
            for y = 0, 1 do
                local horizontal = Instance.new("Frame")
                horizontal.Size = UDim2.fromOffset(17, 3)
                horizontal.Position = UDim2.new(x, x == 0 and 0 or -17,
                    y, y == 0 and 0 or -3)
                horizontal.BackgroundColor3 = Color3.fromRGB(80, 255, 149)
                horizontal.BorderSizePixel = 0
                horizontal.Parent = marker
                local vertical = Instance.new("Frame")
                vertical.Size = UDim2.fromOffset(3, 17)
                vertical.Position = UDim2.new(x, x == 0 and 0 or -3,
                    y, y == 0 and 0 or -17)
                vertical.BackgroundColor3 = horizontal.BackgroundColor3
                vertical.BorderSizePixel = 0
                vertical.Parent = marker
            end
        end
        skillAim.Gui, skillAim.Ring, skillAim.Ticks = gui, ring, ticks
        skillAim.Label, skillAim.Marker = label, marker
    end
    local function updateSkillAimHUD()
        if not skillAim.Gui then return end
        local now = os.clock()
        if now - skillAim.LastScan >= skillAim.ScanInterval then
            skillAim.LastScan = now
            skillAim.VisualTarget = skillAim.Enabled and chooseSkillTarget() or nil
            local locked = aimTargetValid(skillAim.Target) and now <= skillAim.LockUntil
            local target = locked and skillAim.Target or skillAim.VisualTarget
            skillAim.Label.Text = not skillAim.Enabled and "SKILL AIM  -  OFF"
                or (target and ("SKILL AIM  -  " .. (locked and "LOCKED  " or "READY  ")
                    .. target.name) or "SKILL AIM  -  NO TARGET")
        end
        local locked = aimTargetValid(skillAim.Target) and now <= skillAim.LockUntil
        local target = locked and skillAim.Target or skillAim.VisualTarget
        local cam = Workspace.CurrentCamera
        local point = target and aimPoint(target)
        local marker = skillAim.Marker
        marker.Visible = false
        if not skillAim.Enabled or not cam or not point then return end
        local screen, onScreen = cam:WorldToViewportPoint(point)
        local center = cam.ViewportSize / 2
        if onScreen and screen.Z > 0
            and (Vector2.new(screen.X, screen.Y) - center).Magnitude <= skillAim.Fov then
            marker.Position = UDim2.fromOffset(screen.X, screen.Y)
            marker.Visible = true
        end
    end

    local aimInstalled, aimError = pcall(installSkillAim)
    if not aimInstalled or not skillAim.Aim then
        restoreSkillAim()
        warn("[RAVEN Skill Aim] Unavailable:", aimError)
    end
    createSkillAimHUD()

    -- [[ FAST CAST: accelerate owned ability Start animations only ]]
    -- FireArrow one-cast trial: 2.5x animation; server Shoot at ~0.34s
    -- versus ~0.74s baseline. This does not reduce server cooldown or damage.
    local fastCast = {
        Enabled = true, Multiplier = 2.5, Running = true,
        Accelerated = 0, Eligible = 0, Bound = false,
        ActiveTracks = setmetatable({}, {__mode = "k"}),
        TrackConnections = setmetatable({}, {__mode = "k"}),
        AnimationConnection = nil, CharacterConnection = nil,
    }
    local animRoot = ReplicatedStorage:FindFirstChild("Assets")
    animRoot = animRoot and animRoot:FindFirstChild("Animations")
    local function isAbilityStartAnimation(animation)
        if not animation or not animation:IsA("Animation") or animation.Name ~= "Start" then
            return false
        end
        local abilityFolder = animation.Parent
        local movesetFolder = abilityFolder and abilityFolder.Parent
        if not animRoot or not movesetFolder or movesetFolder.Parent ~= animRoot
            or movesetFolder.Name ~= localPlayer:GetAttribute("Moveset") then
            return false
        end
        local registry = skillAim.Registry
        if not registry then return false end
        local ok, moveset = pcall(registry.GetMoveset, movesetFolder.Name)
        if not ok or type(moveset) ~= "table" then return false end
        for _, ability in ipairs(moveset.Abilities or {}) do
            if ability.Key == abilityFolder.Name and ability.Config
                and ability.Config.Kind ~= "Attack" and ability.Config.Kind ~= "Melee" then
                return true
            end
        end
        return false
    end
    local function restoreActiveCastTracks()
        for track, original in pairs(fastCast.ActiveTracks) do
            if track.IsPlaying then
                pcall(function() track:AdjustSpeed(original) end)
            end
            local conn = fastCast.TrackConnections[track]
            if conn then pcall(function() conn:Disconnect() end) end
            fastCast.TrackConnections[track] = nil
            fastCast.ActiveTracks[track] = nil
        end
    end
    local function bindFastCastCharacter(character)
        if fastCast.AnimationConnection then
            fastCast.AnimationConnection:Disconnect()
            fastCast.AnimationConnection = nil
        end
        fastCast.Bound = false
        local hum = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 8)
        local animator = hum and (hum:FindFirstChildOfClass("Animator")
            or hum:WaitForChild("Animator", 8))
        if not fastCast.Running or character ~= localPlayer.Character or not animator then return end
        fastCast.AnimationConnection = animator.AnimationPlayed:Connect(function(track)
            if not fastCast.Enabled or not fastCast.Running
                or not isAbilityStartAnimation(track.Animation) then return end
            fastCast.Eligible += 1
            -- Defer until the game's normal animation setup has run; no input/packet hooks.
            task.defer(function()
                if not fastCast.Running or not fastCast.Enabled
                    or character ~= localPlayer.Character or not track.IsPlaying
                    or fastCast.ActiveTracks[track] then return end
                local original = track.Speed
                fastCast.ActiveTracks[track] = original
                local con
                con = track.Stopped:Connect(function()
                    if con then con:Disconnect() end
                    fastCast.TrackConnections[track] = nil
                    fastCast.ActiveTracks[track] = nil
                end)
                fastCast.TrackConnections[track] = con
                local boosted = math.min(3, math.max(original, 1) * fastCast.Multiplier)
                local ok = pcall(function() track:AdjustSpeed(boosted) end)
                if ok then fastCast.Accelerated += 1 end
            end)
        end)
        fastCast.Bound = true
    end
    local function stopFastCast()
        fastCast.Enabled = false
        fastCast.Running = false
        if fastCast.AnimationConnection then
            fastCast.AnimationConnection:Disconnect()
            fastCast.AnimationConnection = nil
        end
        if fastCast.CharacterConnection then
            fastCast.CharacterConnection:Disconnect()
            fastCast.CharacterConnection = nil
        end
        restoreActiveCastTracks()
        fastCast.Bound = false
    end
    fastCast.CharacterConnection = localPlayer.CharacterAdded:Connect(function(character)
        task.spawn(bindFastCastCharacter, character)
    end)
    if localPlayer.Character then task.spawn(bindFastCastCharacter, localPlayer.Character) end

    -- [[ DRAWING ESP SYSTEM ]]
    local function createDrawingESP(player)
        if espObjects[player] then return end

        local drawings = {
            BoxOutline = Drawing.new("Square"),
            Box = Drawing.new("Square"),
            Name = Drawing.new("Text"),
            Info = Drawing.new("Text"),
        }

        drawings.BoxOutline.Thickness = 3
        drawings.BoxOutline.Filled = false
        drawings.BoxOutline.Color = Color3.fromRGB(0, 0, 0)
        drawings.BoxOutline.Visible = false

        drawings.Box.Thickness = 1
        drawings.Box.Filled = false
        drawings.Box.Color = Color3.fromRGB(255, 75, 75)
        drawings.Box.Visible = false

        drawings.Name.Size = 13
        drawings.Name.Center = true
        drawings.Name.Outline = true
        drawings.Name.Color = Color3.fromRGB(255, 255, 255)
        drawings.Name.Visible = false

        drawings.Info.Size = 11
        drawings.Info.Center = true
        drawings.Info.Outline = true
        drawings.Info.Color = Color3.fromRGB(220, 220, 220)
        drawings.Info.Visible = false

        espObjects[player] = drawings
    end

    local function removeDrawingESP(player)
        if espObjects[player] then
            for _, d in pairs(espObjects[player]) do
                pcall(function() d:Remove() end)
            end
            espObjects[player] = nil
        end
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer then
            createDrawingESP(p)
        end
    end

    connect(Players.PlayerAdded, function(p)
        if p ~= localPlayer then
            createDrawingESP(p)
        end
    end)

    connect(Players.PlayerRemoving, function(p)
        removeDrawingESP(p)
    end)

    -- [[ COMBAT REACH & HITBOX QUERY HOOK ]]
    local hitUtil = nil
    local origQueryFront = nil
    local origInReach = nil
    local origOccluded = nil
    local combatConfig = nil
    local ImpulseUtil = nil

    pcall(function()
        hitUtil = require(ReplicatedStorage.Shared.Util.HitboxUtil)
        combatConfig = require(ReplicatedStorage.Shared.Config)
        ImpulseUtil = require(ReplicatedStorage.Shared.Util.ImpulseUtil)
        origQueryFront = hitUtil.QueryFront
        origInReach = hitUtil.InReach
        origOccluded = hitUtil.Occluded
    end)

    local function setupHitboxHooks()
        if not hitUtil or not origQueryFront or not origInReach then return end

        hitUtil.InReach = function(cframe, targetPos, reach, coneDot, verticalTol)
            if settings.reachEnabled then
                local effectiveReach = math.max(reach, settings.reachDistance + 3)
                local effectiveCone = settings.allAroundHit and -1 or coneDot
                local effectiveVert = verticalTol and math.max(verticalTol, 20) or 20
                return origInReach(cframe, targetPos, effectiveReach, effectiveCone, effectiveVert)
            end
            return origInReach(cframe, targetPos, reach, coneDot, verticalTol)
        end

        hitUtil.QueryFront = function(cframe, reach, size, exclude, canHitImmune, verticalOffset)
            if settings.reachEnabled then
                local HitboxSink = (combatConfig and combatConfig.Combat and combatConfig.Combat.HitboxSink) or 2
                local effectiveReach = math.max(reach, settings.reachDistance)
                local effectiveSize = Vector3.new(
                    math.max(size.X, effectiveReach * 2),
                    math.max(size.Y, effectiveReach * 2),
                    effectiveReach * 2
                )
                local queryCF = cframe
                if settings.allAroundHit then
                    queryCF = cframe * CFrame.new(0, 0, (effectiveReach - HitboxSink) / 2)
                end
                return origQueryFront(queryCF, effectiveReach, effectiveSize, exclude, canHitImmune, verticalOffset)
            end
            return origQueryFront(cframe, reach, size, exclude, canHitImmune, verticalOffset)
        end

        if origOccluded then
            hitUtil.Occluded = function(origin, targetPos, exclude)
                if settings.reachEnabled and settings.wallCheckBypass then
                    return false
                end
                return origOccluded(origin, targetPos, exclude)
            end
        end
    end

    local function restoreHitboxHooks()
        if hitUtil then
            if origQueryFront then hitUtil.QueryFront = origQueryFront end
            if origInReach then hitUtil.InReach = origInReach end
            if origOccluded then hitUtil.Occluded = origOccluded end
        end
    end

    local origDashCharges = (combatConfig and combatConfig.Dash and combatConfig.Dash.Charges) or 1
    local origDashCooldown = (combatConfig and combatConfig.Dash and combatConfig.Dash.Cooldown) or 2
    local origDashDistance = (combatConfig and combatConfig.Dash and combatConfig.Dash.Distance) or 11

    local function applyDashSettings()
        if not combatConfig or not combatConfig.Dash then return end
        if settings.infiniteDash then
            combatConfig.Dash.Charges = 99
            combatConfig.Dash.Cooldown = 0.05
            combatConfig.Dash.Distance = settings.dashDistance
        else
            combatConfig.Dash.Charges = origDashCharges
            combatConfig.Dash.Cooldown = origDashCooldown
            combatConfig.Dash.Distance = origDashDistance
        end
    end

    local function restoreDashSettings()
        if combatConfig and combatConfig.Dash then
            combatConfig.Dash.Charges = origDashCharges
            combatConfig.Dash.Cooldown = origDashCooldown
            combatConfig.Dash.Distance = origDashDistance
        end
    end

    setupHitboxHooks()

    -- [[ TACTICAL BACKSTAB DASH ]]
    local isBackstabDashing = false

    local function playDashVfx(root, hum)
        if settings.backstabPlaySound and root then
            pcall(function()
                local dashFolder = ReplicatedStorage.Assets.Sounds:FindFirstChild("Dash")
                if dashFolder then
                    local sounds = dashFolder:GetChildren()
                    if #sounds > 0 then
                        local s = sounds[math.random(1, #sounds)]:Clone()
                        s.Parent = root
                        s:Play()
                        Debris:AddItem(s, 1.2)
                    end
                end
            end)
        end
        if settings.backstabPlayAnim and hum then
            pcall(function()
                local anim = ReplicatedStorage.Assets.Animations.DefaultMovement:FindFirstChild("DashFront")
                if anim then
                    local animator = hum:FindFirstChildOfClass("Animator") or hum
                    local track = animator:LoadAnimation(anim)
                    track.Priority = Enum.AnimationPriority.Action
                    track:Play(0.02, 1, 1.8)
                end
            end)
        end
    end

    local function executeBackstab()
        if isBackstabDashing then return false end

        local target = getClosestEnemy(settings.backstabMaxRange, false)
        local myRoot = getLocalRoot()
        local myHum = getLocalHumanoid()
        if not (target and target.Character and myRoot and myHum and myHum.Health > 0) then
            notify("Backstab Dash", "No target found within " .. tostring(settings.backstabMaxRange) .. " studs!")
            return false
        end

        local enemyRoot = target.Character:FindFirstChild("HumanoidRootPart")
        local enemyHum = target.Character:FindFirstChildOfClass("Humanoid")
        if not (enemyRoot and enemyHum and enemyHum.Health > 0) then
            notify("Backstab Dash", "Target is invalid or defeated!")
            return false
        end

        isBackstabDashing = true

        local startPos = myRoot.Position
        local enemyLook = enemyRoot.CFrame.LookVector
        local flatEnemyLook = Vector3.new(enemyLook.X, 0, enemyLook.Z)
        flatEnemyLook = (flatEnemyLook.Magnitude > 0.001) and flatEnemyLook.Unit or Vector3.new(0, 0, -1)

        local targetBehindPos = enemyRoot.Position - (flatEnemyLook * settings.backstabDistance)
        targetBehindPos = Vector3.new(targetBehindPos.X, enemyRoot.Position.Y, targetBehindPos.Z)

        local travelVec = targetBehindPos - startPos
        local initialDist = travelVec.Magnitude

        -- Sound & animation feedback
        playDashVfx(myRoot, myHum)

        -- Native impulse dash
        local dashSpeed = settings.backstabDashSpeed or 120
        local duration = math.clamp(initialDist / dashSpeed, 0.08, 0.22)

        if ImpulseUtil and typeof(ImpulseUtil.Dash) == "function" and initialDist > 0.5 then
            pcall(function()
                ImpulseUtil.Dash(myRoot, travelVec.Unit, initialDist / duration, duration)
            end)
        end

        -- Dynamic trajectory glide with sine ease-out
        local t0 = os.clock()
        local dashConnection
        dashConnection = RunService.Heartbeat:Connect(function()
            if not running or not isTargetAlive(target) or not myRoot or not myHum or myHum.Health <= 0 then
                if dashConnection then dashConnection:Disconnect() end
                dashConnection = nil
                isBackstabDashing = false
                return
            end

            local elapsed = os.clock() - t0
            local alpha = math.clamp(elapsed / duration, 0, 1)
            local ease = math.sin(alpha * (math.pi * 0.5))

            local curLook = enemyRoot.CFrame.LookVector
            local curFlat = Vector3.new(curLook.X, 0, curLook.Z)
            curFlat = (curFlat.Magnitude > 0.001) and curFlat.Unit or Vector3.new(0, 0, -1)
            local currentBehind = enemyRoot.Position - (curFlat * settings.backstabDistance)
            currentBehind = Vector3.new(currentBehind.X, enemyRoot.Position.Y, currentBehind.Z)

            local currentPos = startPos:Lerp(currentBehind, ease)

            if alpha < 1 then
                -- Orient towards dash trajectory while moving
                myRoot.CFrame = CFrame.lookAt(currentPos, currentBehind + (curFlat * 4))
            else
                dashConnection:Disconnect()
                dashConnection = nil

                -- Arrival: Lock orientation behind enemy
                if settings.backstabAutoFace then
                    myRoot.CFrame = CFrame.lookAt(currentBehind, enemyRoot.Position)
                else
                    myRoot.CFrame = CFrame.new(currentBehind) * (enemyRoot.CFrame - enemyRoot.Position)
                end
                myRoot.AssemblyLinearVelocity = Vector3.zero

                -- Align camera directly at enemy
                if settings.backstabAlignCam and camera then
                    camera.CFrame = CFrame.lookAt(camera.CFrame.Position, enemyRoot.Position)
                end

                -- Auto M1 strike immediately on arrival
                if settings.backstabAutoAttack then
                    task.spawn(function()
                        task.wait(0.03)
                        pcall(function()
                            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                            task.wait(0.02)
                            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                        end)
                    end)
                end

                notify("Backstab Dash", "Dashed behind " .. target.DisplayName .. " (" .. string.format("%.1f", initialDist) .. " studs) 🗡️💨")

                task.delay(0.08, function()
                    isBackstabDashing = false
                end)
            end
        end)

        return true
    end

    -- [[ INPUT HANDLING ]]
    connect(UserInputService.InputBegan, function(input, processed)
        if processed then return end

        if input.KeyCode == settings.backstabKey then
            executeBackstab()
        elseif input.KeyCode == Enum.KeyCode.Space and settings.infiniteJump then
            local hum = getLocalHumanoid()
            if hum then
                hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end
    end)

    -- [[ RENDER LOOP ]]
    connect(RunService.RenderStepped, function()
        if not running then return end

        -- HUD target acquisition is throttled; bracket position alone tracks each frame.
        updateSkillAimHUD()

        -- 2. Speed Boost
        if settings.speedEnabled then
            local hum = getLocalHumanoid()
            if hum then
                hum.WalkSpeed = settings.speedValue
            end
        end

        -- 4. Anti-Ragdoll / Quick Stand
        if settings.antiRagdoll then
            local hum = getLocalHumanoid()
            if hum then
                local state = hum:GetState()
                if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown then
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end
        end

        -- 5. Auto M1 in Range
        if settings.autoM1 and (tick() - lastM1Time >= settings.autoM1Interval) then
            local target = getClosestEnemy(settings.autoM1Range, false)
            if target then
                lastM1Time = tick()
                pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                    task.wait(0.02)
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
                end)
            end
        end

        -- 6. ESP Rendering
        local myRoot = getLocalRoot()
        for player, drawings in pairs(espObjects) do
            if settings.espEnabled and isTargetAlive(player) then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                local head = player.Character:FindFirstChild("Head")
                local hum = player.Character:FindFirstChildOfClass("Humanoid")

                if root and head and hum then
                    local rootPos, onScreen = camera:WorldToViewportPoint(root.Position)
                    if onScreen then
                        local headPos = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.5, 0))
                        local legPos = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                        local height = legPos.Y - headPos.Y
                        local width = height / 1.8

                        -- Box
                        if settings.boxEsp then
                            drawings.BoxOutline.Size = Vector2.new(width, height)
                            drawings.BoxOutline.Position = Vector2.new(rootPos.X - width / 2, headPos.Y)
                            drawings.BoxOutline.Visible = true

                            drawings.Box.Size = Vector2.new(width, height)
                            drawings.Box.Position = Vector2.new(rootPos.X - width / 2, headPos.Y)
                            drawings.Box.Visible = true
                        else
                            drawings.Box.Visible = false
                            drawings.BoxOutline.Visible = false
                        end

                        -- Name
                        if settings.nameEsp then
                            drawings.Name.Text = player.DisplayName .. " (@" .. player.Name .. ")"
                            drawings.Name.Position = Vector2.new(rootPos.X, headPos.Y - 16)
                            drawings.Name.Visible = true
                        else
                            drawings.Name.Visible = false
                        end

                        -- Bottom Info
                        local infoParts = {}
                        if settings.movesetEsp then
                            local moveset = player:GetAttribute("Moveset") or "Unknown"
                            table.insert(infoParts, "[" .. tostring(moveset) .. "]")
                        end
                        if settings.healthEsp then
                            table.insert(infoParts, math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth) .. " HP")
                        end
                        if settings.distanceEsp and myRoot then
                            local dist = math.floor((myRoot.Position - root.Position).Magnitude)
                            table.insert(infoParts, dist .. "m")
                        end

                        drawings.Info.Text = table.concat(infoParts, " • ")
                        drawings.Info.Position = Vector2.new(rootPos.X, legPos.Y + 2)
                        drawings.Info.Visible = true
                    else
                        drawings.Box.Visible = false
                        drawings.BoxOutline.Visible = false
                        drawings.Name.Visible = false
                        drawings.Info.Visible = false
                    end
                else
                    drawings.Box.Visible = false
                    drawings.BoxOutline.Visible = false
                    drawings.Name.Visible = false
                    drawings.Info.Visible = false
                end
            else
                drawings.Box.Visible = false
                drawings.BoxOutline.Visible = false
                drawings.Name.Visible = false
                drawings.Info.Visible = false
            end
        end
    end)

    -- [[ UI CONSTRUCTION ]]
    -- Tab 1: Combat
    local CombatTab = Window:CreateTab("Combat", 4483362458)
    CombatTab:CreateSection("Skill Aim - Classic Smooth")

    CombatTab:CreateToggle({
        Name = "Skill Aim (FOV, no camera lock)",
        CurrentValue = true,
        Flag = "AB_SkillAim",
        Callback = function(value)
            skillAim.Enabled = value
            skillAim.Target = nil
            skillAim.LockUntil = 0
            notify("Skill Aim", value and "Enabled - aim at a target and cast normally"
                or "Disabled - original skill directions preserved")
        end,
    })

    CombatTab:CreateSlider({
        Name = "Skill Aim FOV",
        Range = {60, 400},
        Increment = 5,
        Suffix = " px",
        CurrentValue = 175,
        Flag = "AB_SkillAimFov",
        Callback = function(value)
            skillAim.Fov = value
            if skillAim.Ring then
                skillAim.Ring.Size = UDim2.fromOffset(value * 2, value * 2)
            end
            if skillAim.Label then
                skillAim.Label.Position = UDim2.new(0.5, 0, 0.5, value + 10)
            end
            if skillAim.Ticks then
                for i, tick in ipairs(skillAim.Ticks:GetChildren()) do
                    if tick:IsA("Frame") then
                        local angle = i * math.pi * 2 / 36
                        tick.Position = UDim2.new(0.5, math.cos(angle) * value,
                            0.5, math.sin(angle) * value)
                    end
                end
            end
        end,
    })

    CombatTab:CreateToggle({
        Name = "Range-aware Skill Aim (declared ranges)",
        CurrentValue = true,
        Flag = "AB_SkillAimRangeAware",
        Callback = function(value)
            skillAim.RangeAware = value
            skillAim.Target = nil
            skillAim.LockUntil = 0
        end,
    })

    CombatTab:CreateSlider({
        Name = "Skill Aim Prediction",
        Range = {0, 0.2},
        Increment = 0.01,
        Suffix = " s",
        CurrentValue = 0.07,
        Flag = "AB_SkillAimPredict",
        Callback = function(value) skillAim.Prediction = value end,
    })

    CombatTab:CreateSection("Fast Cast - animation timing")

    CombatTab:CreateToggle({
        Name = "Fast Cast (skill Start animations only)",
        CurrentValue = true,
        Flag = "AB_FastCast",
        Callback = function(value)
            fastCast.Enabled = value
            if not value then restoreActiveCastTracks() end
            notify("Fast Cast", value and "Enabled - normal skill inputs, faster windup"
                or "Disabled - animation speeds restored")
        end,
    })

    CombatTab:CreateSlider({
        Name = "Fast Cast Speed",
        Range = {1, 3},
        Increment = 0.25,
        Suffix = "x",
        CurrentValue = 2.5,
        Flag = "AB_FastCastSpeed",
        Callback = function(value) fastCast.Multiplier = math.clamp(value, 1, 3) end,
    })

    CombatTab:CreateSection("Extended Attack Reach / Query Hook")

    CombatTab:CreateToggle({
        Name = "⚔️ Extended Attack Reach",
        CurrentValue = true,
        Flag = "AB_ReachEnabled",
        Callback = function(v)
            settings.reachEnabled = v
        end,
    })

    CombatTab:CreateSlider({
        Name = "Attack Reach Distance",
        Range = {4, 25},
        Increment = 1,
        Suffix = " Studs",
        CurrentValue = 12,
        Flag = "AB_ReachDist",
        Callback = function(v)
            settings.reachDistance = v
        end,
    })

    CombatTab:CreateToggle({
        Name = "🔄 360° All-Around Hit",
        CurrentValue = true,
        Flag = "AB_360Hit",
        Callback = function(v)
            settings.allAroundHit = v
        end,
    })

    CombatTab:CreateToggle({
        Name = "🧱 Wall Penetration (Bypass Occlusion)",
        CurrentValue = false,
        Flag = "AB_WallBypass",
        Callback = function(v)
            settings.wallCheckBypass = v
        end,
    })

    CombatTab:CreateSection("Auto Combat")

    CombatTab:CreateToggle({
        Name = "🥊 Auto M1 In Range",
        CurrentValue = false,
        Flag = "AB_AutoM1",
        Callback = function(v)
            settings.autoM1 = v
        end,
    })

    CombatTab:CreateSlider({
        Name = "M1 Trigger Range",
        Range = {6, 25},
        Increment = 1,
        Suffix = " Studs",
        CurrentValue = 12,
        Flag = "AB_AutoM1Range",
        Callback = function(v)
            settings.autoM1Range = v
        end,
    })

    CombatTab:CreateSlider({
        Name = "M1 Attack Speed / Interval",
        Range = {0.2, 0.5},
        Increment = 0.05,
        Suffix = "s",
        CurrentValue = 0.25,
        Flag = "AB_AutoM1Interval",
        Callback = function(v)
            settings.autoM1Interval = v
        end,
    })

    -- Tab 2: Visuals (ESP)
    local VisualTab = Window:CreateTab("Visuals", 4483362458)
    VisualTab:CreateSection("Drawing API ESP")

    VisualTab:CreateToggle({
        Name = "👁️ Master ESP",
        CurrentValue = false,
        Flag = "AB_MasterESP",
        Callback = function(v)
            settings.espEnabled = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "📦 Box ESP",
        CurrentValue = true,
        Flag = "AB_BoxESP",
        Callback = function(v)
            settings.boxEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "🏷️ Name ESP",
        CurrentValue = true,
        Flag = "AB_NameESP",
        Callback = function(v)
            settings.nameEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "❤️ Health ESP",
        CurrentValue = true,
        Flag = "AB_HealthESP",
        Callback = function(v)
            settings.healthEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "🥋 Moveset Tracker ESP",
        CurrentValue = true,
        Flag = "AB_MovesetESP",
        Callback = function(v)
            settings.movesetEsp = v
        end,
    })

    VisualTab:CreateToggle({
        Name = "📏 Distance ESP",
        CurrentValue = true,
        Flag = "AB_DistESP",
        Callback = function(v)
            settings.distanceEsp = v
        end,
    })

    VisualTab:CreateSection("Game Engine Debug")

    VisualTab:CreateToggle({
        Name = "🛠️ Game Native Hitbox Visualizer",
        CurrentValue = false,
        Flag = "AB_NativeHitbox",
        Callback = function(v)
            settings.nativeHitboxDebug = v
            localPlayer:SetAttribute("HitboxDebug", v)
            notify("Hitbox Debug", v and "Game hitbox visualization active" or "Hitbox visualization off")
        end,
    })

    -- Tab 3: Mobility
    local MobilityTab = Window:CreateTab("Mobility", 4483362458)
    MobilityTab:CreateSection("Speed & Movement")

    MobilityTab:CreateToggle({
        Name = "⚡ WalkSpeed Modifier",
        CurrentValue = false,
        Flag = "AB_SpeedToggle",
        Callback = function(v)
            settings.speedEnabled = v
            if not v then
                local hum = getLocalHumanoid()
                if hum then hum.WalkSpeed = 22 end
            end
        end,
    })

    MobilityTab:CreateSlider({
        Name = "WalkSpeed Value",
        Range = {22, 100},
        Increment = 1,
        Suffix = " Speed",
        CurrentValue = 35,
        Flag = "AB_SpeedVal",
        Callback = function(v)
            settings.speedValue = v
        end,
    })

    MobilityTab:CreateSection("Dash Enhancements")

    MobilityTab:CreateToggle({
        Name = "🚀 Infinite Dash (No Cooldown)",
        CurrentValue = false,
        Flag = "AB_InfDash",
        Callback = function(v)
            settings.infiniteDash = v
            applyDashSettings()
        end,
    })

    MobilityTab:CreateSlider({
        Name = "Dash Distance",
        Range = {11, 40},
        Increment = 1,
        Suffix = " Studs",
        CurrentValue = 11,
        Flag = "AB_DashDist",
        Callback = function(v)
            settings.dashDistance = v
            if settings.infiniteDash then
                applyDashSettings()
            end
        end,
    })

    MobilityTab:CreateSection("Acrobatics")

    MobilityTab:CreateToggle({
        Name = "🦘 Infinite Jump",
        CurrentValue = false,
        Flag = "AB_InfJump",
        Callback = function(v)
            settings.infiniteJump = v
        end,
    })

    MobilityTab:CreateToggle({
        Name = "🛡️ Anti-Ragdoll / Quick Stand",
        CurrentValue = false,
        Flag = "AB_AntiRagdoll",
        Callback = function(v)
            settings.antiRagdoll = v
        end,
    })

    -- Tab 4: Teleport
    local TeleportTab = Window:CreateTab("Teleport", 4483362458)
    TeleportTab:CreateSection("🗡️ Tactical Backstab Dash (Legit Movement)")

    TeleportTab:CreateKeybind({
        Name = "🗡️ Backstab Hotkey",
        CurrentKeybind = "V",
        HoldToInteract = false,
        Flag = "AB_BackstabKey",
        Callback = function(key)
            if typeof(key) == "EnumItem" then
                settings.backstabKey = key
                notify("Backstab Dash", "Hotkey bound to [" .. tostring(key.Name) .. "]")
            end
        end,
    })

    TeleportTab:CreateSlider({
        Name = "Offset Distance Behind Target",
        Range = {1, 10},
        Increment = 0.5,
        Suffix = " Studs Behind",
        CurrentValue = 2.5,
        Flag = "AB_BackstabDist",
        Callback = function(v)
            settings.backstabDistance = v
        end,
    })

    TeleportTab:CreateSlider({
        Name = "Dash Glide Speed",
        Range = {60, 250},
        Increment = 10,
        Suffix = " Studs/s",
        CurrentValue = 120,
        Flag = "AB_BackstabSpeed",
        Callback = function(v)
            settings.backstabDashSpeed = v
        end,
    })

    TeleportTab:CreateSlider({
        Name = "Max Target Search Range",
        Range = {50, 500},
        Increment = 25,
        Suffix = " Studs",
        CurrentValue = 250,
        Flag = "AB_BackstabRange",
        Callback = function(v)
            settings.backstabMaxRange = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "🔊 Dash Audio VFX",
        CurrentValue = true,
        Flag = "AB_BackstabAudio",
        Callback = function(v)
            settings.backstabPlaySound = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "🏃 Dash Character Anim",
        CurrentValue = true,
        Flag = "AB_BackstabAnim",
        Callback = function(v)
            settings.backstabPlayAnim = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "🎯 Auto Face Target Back",
        CurrentValue = true,
        Flag = "AB_BackstabAutoFace",
        Callback = function(v)
            settings.backstabAutoFace = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "📷 Align Camera With Target",
        CurrentValue = true,
        Flag = "AB_BackstabCam",
        Callback = function(v)
            settings.backstabAlignCam = v
        end,
    })

    TeleportTab:CreateToggle({
        Name = "🥊 Auto M1 Strike On Arrival",
        CurrentValue = true,
        Flag = "AB_BackstabAutoM1",
        Callback = function(v)
            settings.backstabAutoAttack = v
        end,
    })

    TeleportTab:CreateButton({
        Name = "⚡ Execute Backstab Dash",
        Callback = function()
            executeBackstab()
        end,
    })

    TeleportTab:CreateButton({
        Name = "☁️ Safe Sky Escape (+250 Studs Up)",
        Callback = function()
            local myRoot = getLocalRoot()
            if myRoot then
                myRoot.CFrame = myRoot.CFrame + Vector3.new(0, 250, 0)
                myRoot.AssemblyLinearVelocity = Vector3.zero
                notify("Escape", "Teleported to safe sky!")
            end
        end,
    })

    TeleportTab:CreateSection("Locations")

    TeleportTab:CreateButton({
        Name = "🏟️ Teleport to Map Spawns",
        Callback = function()
            local myRoot = getLocalRoot()
            if myRoot then
                myRoot.CFrame = CFrame.new(71.4, 398, -213.4)
                myRoot.AssemblyLinearVelocity = Vector3.zero
                notify("Teleport", "Teleported to Spawn")
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "🏠 Teleport to Lobby Leaderboards",
        Callback = function()
            local myRoot = getLocalRoot()
            if myRoot then
                myRoot.CFrame = CFrame.new(75, 412, -850)
                myRoot.AssemblyLinearVelocity = Vector3.zero
                notify("Teleport", "Teleported to Lobby")
            end
        end,
    })

    local selectedPlayer = nil
    local function getPlayerNames()
        local list = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                table.insert(list, p.DisplayName .. " (@" .. p.Name .. ")")
            end
        end
        if #list == 0 then table.insert(list, "None") end
        return list
    end

    TeleportTab:CreateSection("Player Teleport")

    local playerDropdown = TeleportTab:CreateDropdown({
        Name = "Select Player",
        Options = getPlayerNames(),
        CurrentOption = {getPlayerNames()[1] or "None"},
        Flag = "AB_SelectPlayer",
        Callback = function(v)
            local chosen = type(v) == "table" and v[1] or v
            for _, p in ipairs(Players:GetPlayers()) do
                if (p.DisplayName .. " (@" .. p.Name .. ")") == chosen then
                    selectedPlayer = p
                    break
                end
            end
        end,
    })

    TeleportTab:CreateButton({
        Name = "🚀 Teleport To Selected Player",
        Callback = function()
            local myRoot = getLocalRoot()
            if selectedPlayer and selectedPlayer.Character and myRoot then
                local targetRoot = selectedPlayer.Character:FindFirstChild("HumanoidRootPart")
                if targetRoot then
                    myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, 3)
                    myRoot.AssemblyLinearVelocity = Vector3.zero
                    notify("Teleport", "Teleported to " .. selectedPlayer.DisplayName)
                    return
                end
            end
            notify("Teleport", "Player not available or invalid")
        end,
    })

    TeleportTab:CreateButton({
        Name = "🔄 Refresh Player List",
        Callback = function()
            if playerDropdown and type(playerDropdown.Set) == "function" then
                playerDropdown:Set(getPlayerNames())
                notify("Teleport", "Player list refreshed!")
            end
        end,
    })

    -- Cleanup object
    local hubInstance = {
        GetFastCastStatus = function()
            return {enabled = fastCast.Enabled, bound = fastCast.Bound,
                running = fastCast.Running, multiplier = fastCast.Multiplier,
                eligible = fastCast.Eligible, accelerated = fastCast.Accelerated,
                serverCooldownChanged = false}
        end,
        GetSkillAimStatus = function()
            local profile = skillAim.RangeInfo or {classification = "unknown"}
            return {enabled = skillAim.Enabled, installed = skillAim.Aim ~= nil,
                fov = skillAim.Fov, rangeAware = skillAim.RangeAware,
                activeAbilityId = skillAim.ActiveAbilityId,
                rangeClass = profile.classification, rangeKey = profile.key,
                rangeMax = activeSkillRange(), acquired = skillAim.Stats.acquired,
                redirected = skillAim.Stats.redirected, passed = skillAim.Stats.passed,
                outOfRange = skillAim.Stats.outOfRange}
        end,
        GetSkillRangeProfile = function(abilityId)
            local registry = skillAim.Registry
            if not registry then return nil, "registry unavailable" end
            local ok, ability = pcall(registry.GetAbilityById, abilityId)
            if not ok or type(ability) ~= "table" then return nil, "ability not found" end
            local config = ability.Config
            local info = skillRangeProfile(config)
            return {id = ability.Id, key = ability.Key, moveset = ability.Moveset,
                name = config.Name, cooldown = config.Cooldown, damage = config.Damage,
                classification = info.classification, rangeKey = info.key,
                declaredRange = info.max, hint = info.hint}
        end,
        Destroy = function()
            running = false
            for _, conn in ipairs(connections) do
                pcall(function() conn:Disconnect() end)
            end
            for player, _ in pairs(espObjects) do
                removeDrawingESP(player)
            end
            stopFastCast()
            restoreSkillAim()
            if skillAim.Gui then pcall(function() skillAim.Gui:Destroy() end) end
            restoreHitboxHooks()
            restoreDashSettings()
            local hum = getLocalHumanoid()
            if hum then hum.WalkSpeed = 22 end
            localPlayer:SetAttribute("HitboxDebug", false)
            environment.__RAVEN_ANIME_BATTLEGROUNDS = nil
        end
    }

    environment.__RAVEN_ANIME_BATTLEGROUNDS = hubInstance
    notify("Anime Battlegrounds", "Module loaded successfully! 🐀⚡")
    return hubInstance
end
