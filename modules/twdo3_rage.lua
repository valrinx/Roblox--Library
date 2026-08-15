-- ============================================================
--   RAVEN HUB | TWDO3 Rage Module
--   No Recoil, Speed, Fullbright, Silent Aim, TP Loot, Fly
-- ============================================================
return function(context)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Lighting = game:GetService("Lighting")
    local TweenService = game:GetService("TweenService")

    local Window = context.Window
    local localPlayer = context.localPlayer or Players.LocalPlayer
    local settings = context.settings or {}
    local notify = context.notify or function() end
    local scriptRunning = true
    local connections = {}
    local originalValues = {}

    local function disconnect(con)
        if con then pcall(function() con:Disconnect() end) end
    end

    local function getCharacter()
        return localPlayer.Character
    end

    local function getHumanoid()
        local char = getCharacter()
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot()
        local char = getCharacter()
        return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso"))
    end

    -- ============================================================
    --   NO RECOIL + NO SPREAD
    -- ============================================================

    local noRecoilActive = false
    local spreadHookId = nil

    local function enableNoRecoil()
        if noRecoilActive then return end
        noRecoilActive = true

        -- Method 1: Hook the dynamic crosshair system
        -- The crosshair gap is controlled by u7 table values
        -- We override SetSpread remote and lock spread to 0
        local ok = pcall(function()
            -- Find and zero-out the crosshair spread via GC scan
            for _, obj in ipairs(getgc(true)) do
                if type(obj) == "table" and rawget(obj, "FireAmount") and rawget(obj, "ADSFireAmount") and rawget(obj, "RecoverySpeed") then
                    originalValues.spreadTable = {
                        FireAmount = obj.FireAmount,
                        ADSFireAmount = obj.ADSFireAmount,
                        FireMaximum = obj.FireMaximum,
                        JumpAmount = obj.JumpAmount,
                        LandingBaseAmount = obj.LandingBaseAmount,
                        MovementMaximum = obj.MovementMaximum,
                        RecoverySpeed = obj.RecoverySpeed,
                        Offset = obj.Offset,
                    }
                    obj.FireAmount = 0
                    obj.ADSFireAmount = 0
                    obj.FireMaximum = 0
                    obj.JumpAmount = 0
                    obj.LandingBaseAmount = 0
                    obj.LandingMaximumAmount = 0
                    obj.MovementMaximum = 0
                    obj.RecoverySpeed = 999
                    obj.Offset = 0
                    break
                end
            end
        end)

        -- Method 2: Hook CameraShaker to suppress recoil shake
        pcall(function()
            local CameraShaker = require(game.ReplicatedStorage.CLIENT_MODULES.CameraShaker)
            if CameraShaker and CameraShaker.ShakeOnce then
                local origShakeOnce = CameraShaker.ShakeOnce
                CameraShaker.ShakeOnce = function(self, ...)
                    if noRecoilActive then
                        return -- suppress all camera shake
                    end
                    return origShakeOnce(self, ...)
                end
                originalValues.shakeOnce = origShakeOnce
            end
        end)

        notify("Rage", "No Recoil + No Spread enabled")
    end

    local function disableNoRecoil()
        if not noRecoilActive then return end
        noRecoilActive = false

        -- Restore spread table
        pcall(function()
            if originalValues.spreadTable then
                for _, obj in ipairs(getgc(true)) do
                    if type(obj) == "table" and rawget(obj, "FireAmount") ~= nil and rawget(obj, "RecoverySpeed") == 999 then
                        for k, v in pairs(originalValues.spreadTable) do
                            obj[k] = v
                        end
                        break
                    end
                end
            end
        end)

        -- Restore CameraShaker
        pcall(function()
            if originalValues.shakeOnce then
                local CameraShaker = require(game.ReplicatedStorage.CLIENT_MODULES.CameraShaker)
                if CameraShaker then
                    CameraShaker.ShakeOnce = originalValues.shakeOnce
                end
            end
        end)

        notify("Rage", "No Recoil + No Spread disabled")
    end

    -- ============================================================
    --   SPEED HACK
    -- ============================================================

    local speedActive = false
    local speedValue = 32
    local originalWalkSpeed = 21
    local speedConnection = nil

    local function enableSpeed()
        if speedActive then return end
        speedActive = true

        local hum = getHumanoid()
        if hum then
            originalWalkSpeed = hum.WalkSpeed
            hum.WalkSpeed = speedValue
        end

        -- Keep applying on respawn and if server resets it
        speedConnection = RunService.Heartbeat:Connect(function()
            if not speedActive then return end
            local h = getHumanoid()
            if h and h.WalkSpeed ~= speedValue then
                h.WalkSpeed = speedValue
            end
        end)
        table.insert(connections, speedConnection)

        notify("Rage", "Speed: " .. speedValue)
    end

    local function disableSpeed()
        if not speedActive then return end
        speedActive = false
        disconnect(speedConnection)
        speedConnection = nil

        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = originalWalkSpeed
        end

        notify("Rage", "Speed restored")
    end

    -- ============================================================
    --   FULLBRIGHT + NO FOG
    -- ============================================================

    local fullbrightActive = false

    local function enableFullbright()
        if fullbrightActive then return end
        fullbrightActive = true

        -- Save originals
        originalValues.lighting = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd,
            FogStart = Lighting.FogStart,
            GlobalShadows = Lighting.GlobalShadows,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            Ambient = Lighting.Ambient,
        }

        -- Apply fullbright
        Lighting.Brightness = 2
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
        Lighting.Ambient = Color3.fromRGB(180, 180, 180)

        -- Remove Atmosphere and other effects
        originalValues.atmosphereParent = {}
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("BlurEffect")
                or child:IsA("ColorCorrectionEffect") or child:IsA("DepthOfFieldEffect") then
                originalValues.atmosphereParent[child] = child.Parent
                child.Parent = nil
            end
        end

        -- Also remove sky fog from workspace if present
        pcall(function()
            local sky = Lighting:FindFirstChildOfClass("Sky")
            if sky then
                originalValues.sky = sky
                sky.Parent = nil
            end
        end)

        notify("Rage", "Fullbright + No Fog enabled")
    end

    local function disableFullbright()
        if not fullbrightActive then return end
        fullbrightActive = false

        -- Restore lighting
        if originalValues.lighting then
            for k, v in pairs(originalValues.lighting) do
                pcall(function() Lighting[k] = v end)
            end
        end

        -- Restore effects
        if originalValues.atmosphereParent then
            for child, parent in pairs(originalValues.atmosphereParent) do
                pcall(function() child.Parent = parent end)
            end
        end

        if originalValues.sky then
            pcall(function() originalValues.sky.Parent = Lighting end)
        end

        notify("Rage", "Fullbright disabled")
    end

    -- ============================================================
    --   SILENT AIM
    -- ============================================================

    local silentAimActive = false
    local silentAimPlayers = true
    local silentAimWalkers = true
    local silentAimFov = 250
    local silentAimRange = 1500

    local function getClosestTarget()
        local camera = workspace.CurrentCamera
        if not camera then return nil end

        local myRoot = getRoot()
        if not myRoot then return nil end

        local screenCenter = camera.ViewportSize / 2
        local bestTarget = nil
        local bestDist = silentAimFov

        -- Check players
        if silentAimPlayers then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= localPlayer and player.Character then
                    local head = player.Character:FindFirstChild("Head")
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
                    if head and root and humanoid and humanoid.Health > 0 then
                        local dist3D = (root.Position - myRoot.Position).Magnitude
                        if dist3D <= silentAimRange then
                            local screenPos, onScreen = camera:WorldToViewportPoint(head.Position)
                            if onScreen then
                                local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                                if screenDist < bestDist then
                                    bestDist = screenDist
                                    bestTarget = head
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Check walkers
        if silentAimWalkers then
            local ai = workspace:FindFirstChild("AI")
            local walkerFolder = ai and ai:FindFirstChild("Walkers")
            if walkerFolder then
                for _, walker in ipairs(walkerFolder:GetChildren()) do
                    if walker:IsA("Model") then
                        local head = walker:FindFirstChild("Head")
                        local root = walker:FindFirstChild("HumanoidRootPart") or walker:FindFirstChild("Torso")
                        local humanoid = walker:FindFirstChildOfClass("Humanoid")
                        local attrHealth = walker:GetAttribute("Health")
                        local alive = (attrHealth == nil or attrHealth > 0) and (not humanoid or humanoid.Health > 0)
                        if head and root and alive then
                            local dist3D = (root.Position - myRoot.Position).Magnitude
                            if dist3D <= silentAimRange then
                                local screenPos, onScreen = camera:WorldToViewportPoint(head.Position)
                                if onScreen then
                                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
                                    if screenDist < bestDist then
                                        bestDist = screenDist
                                        bestTarget = head
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestTarget
    end

    local silentAimHook = nil

    local function enableSilentAim()
        if silentAimActive then return end
        silentAimActive = true

        -- Hook the mouse hit/target or raycast used by GunClient
        -- TWDO3 uses camera:ScreenPointToRay or mouse.Hit for aim direction
        -- We hook __namecall on WorldRoot:Raycast to redirect the direction
        local oldNamecall = nil
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            local method = getnamecallmethod()

            if silentAimActive and method == "Raycast" and self == workspace then
                local target = getClosestTarget()
                if target and target.Parent then
                    local args = {...}
                    local origin = args[1]
                    if typeof(origin) == "Vector3" then
                        local direction = (target.Position - origin).Unit * (args[2] and args[2].Magnitude or 1000)
                        return oldNamecall(self, origin, direction, select(3, ...))
                    end
                end
            end

            return oldNamecall(self, ...)
        end))

        originalValues.namecall = oldNamecall
        notify("Rage", "Silent Aim enabled (FOV: " .. silentAimFov .. ")")
    end

    local function disableSilentAim()
        if not silentAimActive then return end
        silentAimActive = false

        -- Restore namecall
        if originalValues.namecall then
            pcall(function()
                hookmetamethod(game, "__namecall", originalValues.namecall)
            end)
        end

        notify("Rage", "Silent Aim disabled")
    end

    -- NOTE: INVENTORY_REMOTES (GiveItem/SpawnItem/ForcePickup) are SERVER-VALIDATED
    -- Firing them directly results in PERMANENT BAN. Do NOT use.

    -- ============================================================
    --   FLY + NOCLIP
    -- ============================================================

    local flyActive = false
    local noclipActive = false
    local flySpeed = 60
    local flyConnection = nil
    local noclipConnection = nil
    local bodyVelocity = nil
    local bodyGyro = nil

    local function enableFly()
        if flyActive then return end
        flyActive = true

        local root = getRoot()
        local humanoid = getHumanoid()
        if not root or not humanoid then
            notify("Rage", "Character not found")
            flyActive = false
            return
        end

        -- Create BodyVelocity + BodyGyro
        bodyVelocity = Instance.new("BodyVelocity")
        bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bodyVelocity.Velocity = Vector3.zero
        bodyVelocity.Parent = root

        bodyGyro = Instance.new("BodyGyro")
        bodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bodyGyro.D = 600
        bodyGyro.P = 10000
        bodyGyro.Parent = root

        humanoid.PlatformStand = true

        flyConnection = RunService.Heartbeat:Connect(function()
            if not flyActive then return end
            local r = getRoot()
            if not r or not bodyVelocity or not bodyVelocity.Parent then return end

            local camera = workspace.CurrentCamera
            local moveDir = Vector3.zero

            -- WASD
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                moveDir = moveDir + camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                moveDir = moveDir - camera.CFrame.LookVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                moveDir = moveDir - camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                moveDir = moveDir + camera.CFrame.RightVector
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                moveDir = moveDir + Vector3.new(0, 1, 0)
            end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
                moveDir = moveDir - Vector3.new(0, 1, 0)
            end

            if moveDir.Magnitude > 0 then
                moveDir = moveDir.Unit * flySpeed
            end

            bodyVelocity.Velocity = moveDir
            bodyGyro.CFrame = camera.CFrame
        end)
        table.insert(connections, flyConnection)

        notify("Rage", "Fly enabled (speed: " .. flySpeed .. ")")
    end

    local function disableFly()
        if not flyActive then return end
        flyActive = false

        disconnect(flyConnection)
        flyConnection = nil

        if bodyVelocity then bodyVelocity:Destroy() bodyVelocity = nil end
        if bodyGyro then bodyGyro:Destroy() bodyGyro = nil end

        local humanoid = getHumanoid()
        if humanoid then
            humanoid.PlatformStand = false
        end

        notify("Rage", "Fly disabled")
    end

    local function enableNoclip()
        if noclipActive then return end
        noclipActive = true

        noclipConnection = RunService.Stepped:Connect(function()
            if not noclipActive then return end
            local char = getCharacter()
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end)
        table.insert(connections, noclipConnection)

        notify("Rage", "NoClip enabled")
    end

    local function disableNoclip()
        if not noclipActive then return end
        noclipActive = false

        disconnect(noclipConnection)
        noclipConnection = nil

        -- Restore collisions
        local char = getCharacter()
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                end
            end
        end

        notify("Rage", "NoClip disabled")
    end

    -- ============================================================
    --   UI TAB
    -- ============================================================

    local RageTab = Window:CreateTab("Rage", 4483362458)

    -- No Recoil
    RageTab:CreateSection("Combat")
    RageTab:CreateToggle({
        Name = "No Recoil + No Spread",
        CurrentValue = false,
        Flag = "TWDO3NoRecoil",
        Callback = function(v)
            if v then enableNoRecoil() else disableNoRecoil() end
        end,
    })

    -- Silent Aim
    RageTab:CreateToggle({
        Name = "Silent Aim",
        CurrentValue = false,
        Flag = "TWDO3SilentAim",
        Callback = function(v)
            if v then enableSilentAim() else disableSilentAim() end
        end,
    })
    RageTab:CreateToggle({
        Name = "Aim at Players",
        CurrentValue = true,
        Flag = "TWDO3SilentAimPlayers",
        Callback = function(v) silentAimPlayers = v end,
    })
    RageTab:CreateToggle({
        Name = "Aim at Walkers",
        CurrentValue = true,
        Flag = "TWDO3SilentAimWalkers",
        Callback = function(v) silentAimWalkers = v end,
    })
    RageTab:CreateSlider({
        Name = "Aim FOV (px)",
        Range = {50, 800},
        Increment = 25,
        CurrentValue = 250,
        Flag = "TWDO3SilentAimFov",
        Callback = function(v) silentAimFov = v end,
    })
    RageTab:CreateSlider({
        Name = "Aim Range (studs)",
        Range = {100, 3000},
        Increment = 100,
        CurrentValue = 1500,
        Flag = "TWDO3SilentAimRange",
        Callback = function(v) silentAimRange = v end,
    })

    -- Speed
    RageTab:CreateSection("Movement")
    RageTab:CreateToggle({
        Name = "Speed Hack",
        CurrentValue = false,
        Flag = "TWDO3Speed",
        Callback = function(v)
            if v then enableSpeed() else disableSpeed() end
        end,
    })
    RageTab:CreateSlider({
        Name = "Speed Value",
        Range = {21, 120},
        Increment = 1,
        CurrentValue = 32,
        Suffix = " studs/s",
        Flag = "TWDO3SpeedValue",
        Callback = function(v)
            speedValue = v
            if speedActive then
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = v end
            end
        end,
    })

    -- Fly
    RageTab:CreateToggle({
        Name = "Fly",
        CurrentValue = false,
        Flag = "TWDO3Fly",
        Callback = function(v)
            if v then enableFly() else disableFly() end
        end,
    })
    RageTab:CreateSlider({
        Name = "Fly Speed",
        Range = {20, 200},
        Increment = 10,
        CurrentValue = 60,
        Flag = "TWDO3FlySpeed",
        Callback = function(v) flySpeed = v end,
    })
    RageTab:CreateToggle({
        Name = "NoClip",
        CurrentValue = false,
        Flag = "TWDO3NoClip",
        Callback = function(v)
            if v then enableNoclip() else disableNoclip() end
        end,
    })

    -- Visual
    RageTab:CreateSection("Visual")
    RageTab:CreateToggle({
        Name = "Fullbright + No Fog",
        CurrentValue = false,
        Flag = "TWDO3Fullbright",
        Callback = function(v)
            if v then enableFullbright() else disableFullbright() end
        end,
    })

    -- ============================================================
    --   CLEANUP
    -- ============================================================

    local controller = {}

    function controller:Destroy()
        scriptRunning = false
        disableNoRecoil()
        disableSpeed()
        disableFullbright()
        disableSilentAim()
        disableFly()
        disableNoclip()

        for _, con in ipairs(connections) do
            disconnect(con)
        end
        table.clear(connections)
    end

    return controller
end
