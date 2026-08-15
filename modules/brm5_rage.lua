-- ============================================================
--   RAVEN HUB | BRM5 Rage Module (Skeleton)
--   Blackhawk Rescue Mission 5
--   Place ID: 2916899287
-- ============================================================
-- NOTES:
--   BRM5 uses a completely custom engine:
--   - No standard Roblox Character/Humanoid
--   - Custom CharacterController with physics
--   - Single RemoteEvent/RemoteFunction pattern
--   - Custom BulletService + TrajectoryService
--   - Character is at Workspace.Model > Male > Root
--   - 3,974 loaded modules (Knit-style framework)
--   - Recoil tables exist in GC (type = table)
--   - Speed system is NOT WalkSpeed-based (custom _accelerate/_decelerate)
--
-- SAFE FEATURES (client-side only):
--   ✅ Fullbright + No Fog
--   ✅ No Recoil (once recoil table is fully mapped)
--   ✅ ESP (custom — no Humanoid, use Male > Root parts)
--   ⚠️ Speed (needs CharacterController reverse engineering)
--   ⚠️ Silent Aim (needs BulletService/TrajectoryService RE)
--
-- DANGEROUS (server-validated, DO NOT USE):
--   ❌ Any direct RemoteEvent:FireServer calls
--   ❌ Item/weapon spawning
-- ============================================================

return function(Window, runtimeInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Lighting = game:GetService("Lighting")

    local localPlayer = Players.LocalPlayer
    local notify = function(title, msg)
        pcall(function()
            if runtimeInfo and runtimeInfo.hubUI then
                runtimeInfo.hubUI:Notify({Title = title, Content = msg, Duration = 5})
            end
        end)
    end
    local scriptRunning = true
    local connections = {}
    local originalValues = {}

    -- Register cleanup with hub
    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            scriptRunning = false
            -- cleanup will be handled below
        end)
    end

    local function disconnect(con)
        if con then pcall(function() con:Disconnect() end) end
    end

    -- ============================================================
    --   HELPER: Find our character root
    -- ============================================================

    local function getMyRoot()
        local cam = workspace.CurrentCamera
        if not cam then return nil end
        local camPos = cam.CFrame.Position
        for _, desc in ipairs(workspace:GetDescendants()) do
            if desc.Name == "Root" and desc:IsA("BasePart") then
                if (desc.Position - camPos).Magnitude < 15 then
                    return desc
                end
            end
        end
        return nil
    end

    -- ============================================================
    --   FULLBRIGHT + NO FOG
    -- ============================================================

    local fullbrightActive = false

    local function enableFullbright()
        if fullbrightActive then return end
        fullbrightActive = true

        originalValues.lighting = {
            Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime,
            FogEnd = Lighting.FogEnd,
            FogStart = Lighting.FogStart,
            GlobalShadows = Lighting.GlobalShadows,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            Ambient = Lighting.Ambient,
        }

        Lighting.Brightness = 3
        Lighting.FogEnd = 100000
        Lighting.FogStart = 100000
        Lighting.GlobalShadows = false
        Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
        Lighting.Ambient = Color3.fromRGB(180, 180, 180)

        -- Remove atmosphere and post effects
        originalValues.effects = {}
        for _, child in ipairs(Lighting:GetChildren()) do
            if child:IsA("Atmosphere") or child:IsA("BloomEffect") or child:IsA("BlurEffect")
                or child:IsA("ColorCorrectionEffect") or child:IsA("DepthOfFieldEffect") then
                originalValues.effects[child] = child.Parent
                child.Parent = nil
            end
        end

        notify("BRM5", "Fullbright enabled")
    end

    local function disableFullbright()
        if not fullbrightActive then return end
        fullbrightActive = false

        if originalValues.lighting then
            for k, v in pairs(originalValues.lighting) do
                pcall(function() Lighting[k] = v end)
            end
        end

        if originalValues.effects then
            for child, parent in pairs(originalValues.effects) do
                pcall(function() child.Parent = parent end)
            end
        end

        notify("BRM5", "Fullbright disabled")
    end

    -- ============================================================
    --   NO RECOIL (GC-based)
    -- ============================================================

    local noRecoilActive = false
    local recoilOriginals = {}

    local function enableNoRecoil()
        if noRecoilActive then return end
        noRecoilActive = true

        -- Zero out all recoil tables found in GC
        local count = 0
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" and rawget(obj, "Recoil") then
                local recoil = rawget(obj, "Recoil")
                if type(recoil) == "table" then
                    -- Save original and zero
                    local orig = {}
                    for k, v in pairs(recoil) do
                        orig[k] = v
                        if type(v) == "number" then
                            recoil[k] = 0
                        elseif type(v) == "table" then
                            for k2, v2 in pairs(v) do
                                if type(v2) == "number" then
                                    v[k2] = 0
                                end
                            end
                        end
                    end
                    table.insert(recoilOriginals, {table = recoil, original = orig})
                    count += 1
                elseif type(recoil) == "number" then
                    table.insert(recoilOriginals, {table = obj, key = "Recoil", original = recoil})
                    rawset(obj, "Recoil", 0)
                    count += 1
                end
            end
            if count >= 10 then break end
        end

        notify("BRM5", "No Recoil: zeroed " .. count .. " tables")
    end

    local function disableNoRecoil()
        if not noRecoilActive then return end
        noRecoilActive = false

        for _, entry in ipairs(recoilOriginals) do
            pcall(function()
                if entry.key then
                    rawset(entry.table, entry.key, entry.original)
                else
                    for k, v in pairs(entry.original) do
                        entry.table[k] = v
                    end
                end
            end)
        end
        table.clear(recoilOriginals)

        notify("BRM5", "No Recoil disabled")
    end

    -- ============================================================
    --   NOCLIP
    -- ============================================================

    local noclipActive = false
    local noclipConnection = nil

    local function enableNoclip()
        if noclipActive then return end
        noclipActive = true

        noclipConnection = RunService.Stepped:Connect(function()
            if not noclipActive then return end
            -- Find our model and disable collisions
            local root = getMyRoot()
            if root and root.Parent then
                for _, part in ipairs(root.Parent:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                    end
                end
            end
        end)
        table.insert(connections, noclipConnection)

        notify("BRM5", "NoClip enabled")
    end

    local function disableNoclip()
        if not noclipActive then return end
        noclipActive = false
        disconnect(noclipConnection)
        noclipConnection = nil
        notify("BRM5", "NoClip disabled")
    end

    -- ============================================================
    --   UI TAB
    -- ============================================================

    local RageTab = Window:CreateTab("BRM5 Rage", 4483362458)

    -- Combat
    RageTab:CreateSection("Combat")
    RageTab:CreateToggle({
        Name = "No Recoil",
        CurrentValue = false,
        Flag = "BRM5NoRecoil",
        Callback = function(v)
            if v then enableNoRecoil() else disableNoRecoil() end
        end,
    })

    -- Movement
    RageTab:CreateSection("Movement")
    RageTab:CreateToggle({
        Name = "NoClip",
        CurrentValue = false,
        Flag = "BRM5NoClip",
        Callback = function(v)
            if v then enableNoclip() else disableNoclip() end
        end,
    })

    -- Visual
    RageTab:CreateSection("Visual")
    RageTab:CreateToggle({
        Name = "Fullbright + No Fog",
        CurrentValue = false,
        Flag = "BRM5Fullbright",
        Callback = function(v)
            if v then enableFullbright() else disableFullbright() end
        end,
    })

    -- ============================================================
    --   CLEANUP
    -- ============================================================

    -- Register cleanup with hub system
    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            scriptRunning = false
            disableNoRecoil()
            disableFullbright()
            disableNoclip()

            for _, con in ipairs(connections) do
                disconnect(con)
            end
            table.clear(connections)
        end)
    end
end
