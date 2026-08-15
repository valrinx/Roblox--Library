--[[
    RAVEN HUB — BRM5 Module v3.2
    Blackhawk Rescue Mission 5 (PlaceId: 3701546109 / 2916899287)
    
    Features:
    - No Recoil + No Sway (GC patch)
    - Speed Hack (Heartbeat-based)
    - NoClip (Stepped-based)
    - Fullbright + No Fog
    - ESP v8 (Player + NPC/AI detection, Workspace-only scan)
    
    Module format: returns function(Window, info)
    Uses Rayfield-style API via maclib_adapter
    
    IMPORTANT: No server-validated remotes are fired.
    All features are client-side only.
]]

return function(Window, info)
    -- ═══════════════════════════════════════════════
    -- CLEANUP PREVIOUS INSTANCE
    -- ═══════════════════════════════════════════════
    if getgenv().__RAVEN_CLEANUP then
        for _, fn in ipairs(getgenv().__RAVEN_CLEANUP) do
            pcall(fn)
        end
    end
    getgenv().__RAVEN_CLEANUP = {}
    getgenv().__RAVEN_NORECOIL_ACTIVE = false
    getgenv().__RAVEN_ESP_ACTIVE = false

    -- ═══════════════════════════════════════════════
    -- SERVICES
    -- ═══════════════════════════════════════════════
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local lp = Players.LocalPlayer
    local camera = workspace.CurrentCamera

    -- ═══════════════════════════════════════════════
    -- TABS (Rayfield-style API via maclib_adapter)
    -- ═══════════════════════════════════════════════
    local TabCombat = Window:CreateTab("Combat", "rbxassetid://7734053495")
    local TabESP = Window:CreateTab("ESP", "rbxassetid://7734009413")

    -- ═══════════════════════════════════════════════
    -- COMBAT TAB
    -- ═══════════════════════════════════════════════
    TabCombat:CreateSection("Weapon")

    -- ───────────────────────────────────────────────
    -- NO RECOIL + NO SWAY (GC Patch Loop)
    -- ───────────────────────────────────────────────
    local recoilThread = nil

    local function startNoRecoil()
        getgenv().__RAVEN_NORECOIL_ACTIVE = true
        recoilThread = task.spawn(function()
            local cachedSprings = {}
            local cachedTables = {}
            local lastFullScan = 0

            while getgenv().__RAVEN_NORECOIL_ACTIVE do
                pcall(function()
                    local now = tick()
                    -- Full GC scan every 10s to find new tables, quick patch every 0.1s
                    if now - lastFullScan > 10 or #cachedSprings == 0 then
                        lastFullScan = now
                        cachedSprings = {}
                        cachedTables = {}
                        for _, obj in ipairs(getgc(true)) do
                            if type(obj) == "table" then
                                if rawget(obj, "_recoilSpring") then
                                    cachedSprings[#cachedSprings + 1] = obj
                                end
                                if rawget(obj, "_doSway") ~= nil or rawget(obj, "_recoilAmount") ~= nil or rawget(obj, "_swayAmount") ~= nil then
                                    cachedTables[#cachedTables + 1] = obj
                                end
                            end
                        end
                    end

                    -- Quick patch cached refs (very fast, no GC walk)
                    for i = 1, #cachedSprings do
                        local rs = rawget(cachedSprings[i], "_recoilSpring")
                        if type(rs) == "table" then
                            for k, v in pairs(rs) do
                                if type(v) == "number" then
                                    rawset(rs, k, 0)
                                end
                            end
                        end
                    end
                    for i = 1, #cachedTables do
                        local obj = cachedTables[i]
                        if rawget(obj, "_doSway") ~= nil then
                            rawset(obj, "_doSway", false)
                        end
                        if rawget(obj, "_recoilAmount") ~= nil then
                            rawset(obj, "_recoilAmount", 0)
                        end
                        if rawget(obj, "_swayAmount") ~= nil then
                            rawset(obj, "_swayAmount", 0)
                        end
                    end
                end)
                task.wait(0.1)
            end
        end)
    end

    local function stopNoRecoil()
        getgenv().__RAVEN_NORECOIL_ACTIVE = false
    end

    TabCombat:CreateToggle({
        Name = "No Recoil + No Sway",
        CurrentValue = true,
        Callback = function(state)
            if state then
                startNoRecoil()
            else
                stopNoRecoil()
            end
        end,
    })

    -- Start by default
    startNoRecoil()

    -- ───────────────────────────────────────────────
    -- FULLBRIGHT + NO FOG
    -- ───────────────────────────────────────────────
    local function applyFullbright()
        pcall(function()
            Lighting.Brightness = 3
            Lighting.ClockTime = 14
            Lighting.FogEnd = 1000000
            Lighting.GlobalShadows = false
            for _, v in ipairs(Lighting:GetDescendants()) do
                if v:IsA("Atmosphere") then
                    v.Density = 0
                    v.Offset = 0
                end
                if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") then
                    v.Enabled = false
                end
            end
        end)
    end

    TabCombat:CreateToggle({
        Name = "Fullbright + No Fog",
        CurrentValue = false,
        Callback = function(state)
            if state then applyFullbright() end
        end,
    })

    -- ───────────────────────────────────────────────
    -- MOVEMENT SECTION
    -- ───────────────────────────────────────────────
    TabCombat:CreateSection("Movement")

    -- SPEED HACK (Heartbeat)
    local speedConn = nil
    local speedEnabled = false
    local speedValue = 24

    local function updateSpeed()
        if speedConn then speedConn:Disconnect(); speedConn = nil end
        if speedEnabled then
            speedConn = RunService.Heartbeat:Connect(function()
                pcall(function()
                    local wm = lp:FindFirstChild("WorldModel")
                    if wm then
                        for _, child in ipairs(wm:GetChildren()) do
                            if child:IsA("Model") then
                                local hum = child:FindFirstChildOfClass("Humanoid")
                                if hum then hum.WalkSpeed = speedValue end
                            end
                        end
                    end
                end)
            end)
        end
    end

    TabCombat:CreateToggle({
        Name = "Speed Hack",
        CurrentValue = false,
        Callback = function(state)
            speedEnabled = state
            updateSpeed()
        end,
    })

    TabCombat:CreateSlider({
        Name = "Walk Speed",
        Range = {16, 60},
        Increment = 1,
        CurrentValue = 24,
        Callback = function(val)
            speedValue = val
        end,
    })

    -- NOCLIP (Stepped)
    local noclipConn = nil

    TabCombat:CreateToggle({
        Name = "NoClip",
        CurrentValue = false,
        Callback = function(state)
            if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
            if state then
                noclipConn = RunService.Stepped:Connect(function()
                    pcall(function()
                        local myPos = camera.CFrame.Position
                        local closestDist = 9999
                        local selfModel = nil
                        for _, desc in ipairs(workspace:GetDescendants()) do
                            if desc.Name == "Root" and desc:IsA("BasePart") then
                                local model = desc.Parent
                                if model and model:IsA("Model") and (model.Name == "Male" or model.Name == "Female") then
                                    local dist = (desc.Position - myPos).Magnitude
                                    if dist < closestDist then
                                        closestDist = dist
                                        selfModel = model
                                    end
                                end
                            end
                        end
                        if selfModel then
                            for _, part in ipairs(selfModel:GetDescendants()) do
                                if part:IsA("BasePart") then
                                    part.CanCollide = false
                                end
                            end
                        end
                        local wm = lp:FindFirstChild("WorldModel")
                        if wm then
                            for _, child in ipairs(wm:GetDescendants()) do
                                if child:IsA("BasePart") then
                                    child.CanCollide = false
                                end
                            end
                        end
                    end)
                end)
            end
        end,
    })

    -- ═══════════════════════════════════════════════
    -- ESP TAB
    -- ═══════════════════════════════════════════════
    TabESP:CreateSection("ESP Settings")

    -- ESP State
    getgenv().__RAVEN_ESP_SETTINGS = {
        enabled = false,
        showBox = true,
        showName = true,
        showDistance = true,
        showHealth = true,
        maxDistance = 1500,
    }
    getgenv().__RAVEN_ESP_DRAWINGS = {}

    local espSettings = getgenv().__RAVEN_ESP_SETTINGS
    local drawings = getgenv().__RAVEN_ESP_DRAWINGS

    -- Colors
    local COLOR_PLAYER = Color3.fromRGB(0, 200, 255)   -- Cyan = Players
    local COLOR_NPC = Color3.fromRGB(255, 100, 50)     -- Red-Orange = NPC/AI

    local function newDrawingSet()
        local s = {}
        s.boxO = Drawing.new("Square"); s.boxO.Thickness = 3; s.boxO.Color = Color3.new(0,0,0); s.boxO.Filled = false; s.boxO.Visible = false
        s.box = Drawing.new("Square"); s.box.Thickness = 1; s.box.Filled = false; s.box.Visible = false
        s.txt = Drawing.new("Text"); s.txt.Size = 14; s.txt.Center = true; s.txt.Outline = true; s.txt.Visible = false
        s.hp = Drawing.new("Square"); s.hp.Thickness = 1; s.hp.Filled = true; s.hp.Visible = false
        s.hpBg = Drawing.new("Square"); s.hpBg.Thickness = 1; s.hpBg.Filled = true; s.hpBg.Color = Color3.fromRGB(30,30,30); s.hpBg.Visible = false
        return s
    end

    local function hideSet(s)
        for _, d in pairs(s) do pcall(function() d.Visible = false end) end
    end

    local function startESP()
        getgenv().__RAVEN_ESP_ACTIVE = true

        -- Cached target list (updated every 0.5s in separate thread)
        local cachedTargets = {}
        local cachedSelf = nil

        -- Find the character container (the "Model" instance with Male children)
        local function findCharContainer()
            for _, child in ipairs(workspace:GetChildren()) do
                if child.Name == "Model" and child:IsA("Model") then
                    for _, c in ipairs(child:GetChildren()) do
                        if c.Name == "Male" and c:IsA("Model") then
                            return child
                        end
                    end
                end
            end
            return nil
        end

        -- Target scan thread (runs every 0.5s, NOT every frame)
        task.spawn(function()
            while getgenv().__RAVEN_ESP_ACTIVE do
                local ok2, _ = pcall(function()
                    if not espSettings.enabled then
                        cachedTargets = {}
                        cachedSelf = nil
                        task.wait(0.5)
                        return
                    end

                    local myPos = camera.CFrame.Position
                    local container = findCharContainer()
                    local closestDist = 9999
                    local selfModel = nil
                    local newTargets = {}

                    if container then
                        for _, model in ipairs(container:GetChildren()) do
                            if model:IsA("Model") and (model.Name == "Male" or model.Name == "Female") then
                                local root = model:FindFirstChild("Root")
                                if root and root:IsA("BasePart") then
                                    local dist = (root.Position - myPos).Magnitude
                                    if dist < closestDist then
                                        closestDist = dist
                                        selfModel = model
                                    end
                                    if dist <= espSettings.maxDistance then
                                        local hasAI = false
                                        for _, child in ipairs(model:GetChildren()) do
                                            if string.sub(child.Name, 1, 3) == "AI_" then
                                                hasAI = true
                                                break
                                            end
                                        end
                                        newTargets[#newTargets + 1] = {
                                            model = model,
                                            root = root,
                                            head = model:FindFirstChild("Head"),
                                            hum = model:FindFirstChildOfClass("Humanoid"),
                                            dist = dist,
                                            isPlayer = not hasAI,
                                        }
                                    end
                                end
                            end
                        end
                    end

                    -- Sort by distance and limit to closest 30 targets for performance
                    table.sort(newTargets, function(a, b) return a.dist < b.dist end)
                    if #newTargets > 30 then
                        local limited = {}
                        for idx = 1, 30 do
                            limited[idx] = newTargets[idx]
                        end
                        newTargets = limited
                    end

                    cachedTargets = newTargets
                    cachedSelf = selfModel
                end)

                task.wait(0.5)
            end
        end)

        -- Render thread (lightweight, only draws cached targets)
        task.spawn(function()
            while getgenv().__RAVEN_ESP_ACTIVE do
                local ok, err = pcall(function()
                    RunService.RenderStepped:Wait()

                    if not espSettings.enabled then
                        for _, s in pairs(drawings) do hideSet(s) end
                        return
                    end

                    local myPos = camera.CFrame.Position
                    local activeModels = {}
                    local targets = cachedTargets
                    local selfModel = cachedSelf

                    for i = 1, #targets do
                        local t = targets[i]
                        if t.model ~= selfModel and t.root and t.root.Parent then
                            activeModels[t.model] = true
                            if not drawings[t.model] then drawings[t.model] = newDrawingSet() end
                            local s = drawings[t.model]

                            local espColor = t.isPlayer and COLOR_PLAYER or COLOR_NPC
                            local dist = (t.root.Position - myPos).Magnitude

                            local rootScreen, onScreen = camera:WorldToViewportPoint(t.root.Position)

                            if onScreen and rootScreen.Z > 0 then
                                local headPos = t.head and (t.head.Position + Vector3.new(0, 1.5, 0)) or (t.root.Position + Vector3.new(0, 3, 0))
                                local feetPos = t.root.Position - Vector3.new(0, 3, 0)
                                local headScreen = camera:WorldToViewportPoint(headPos)
                                local feetScreen = camera:WorldToViewportPoint(feetPos)
                                local boxH = math.abs(headScreen.Y - feetScreen.Y)
                                local boxW = boxH * 0.55

                                if boxH >= 4 then
                                    s.boxO.Size = Vector2.new(boxW+2, boxH+2)
                                    s.boxO.Position = Vector2.new(rootScreen.X - boxW/2 - 1, headScreen.Y - 1)
                                    s.boxO.Visible = espSettings.showBox

                                    s.box.Size = Vector2.new(boxW, boxH)
                                    s.box.Position = Vector2.new(rootScreen.X - boxW/2, headScreen.Y)
                                    s.box.Color = espColor
                                    s.box.Visible = espSettings.showBox

                                    local label = t.isPlayer and "[P] " or "[AI] "
                                    label = label .. math.floor(dist) .. "m"

                                    if t.hum then
                                        label = label .. " | " .. math.floor(t.hum.Health) .. "HP"
                                    end

                                    s.txt.Position = Vector2.new(rootScreen.X, headScreen.Y - 18)
                                    s.txt.Text = label
                                    s.txt.Color = espColor
                                    s.txt.Visible = espSettings.showName

                                    if t.hum and espSettings.showHealth then
                                        local pct = math.clamp(t.hum.Health / t.hum.MaxHealth, 0, 1)
                                        local barX = rootScreen.X - boxW/2 - 6
                                        s.hpBg.Size = Vector2.new(3, boxH)
                                        s.hpBg.Position = Vector2.new(barX, headScreen.Y)
                                        s.hpBg.Visible = true
                                        s.hp.Size = Vector2.new(3, boxH * pct)
                                        s.hp.Position = Vector2.new(barX, headScreen.Y + boxH*(1-pct))
                                        s.hp.Color = Color3.fromRGB(math.floor(255*(1-pct)), math.floor(255*pct), 0)
                                        s.hp.Visible = true
                                    else
                                        s.hp.Visible = false
                                        s.hpBg.Visible = false
                                    end
                                else
                                    hideSet(s)
                                end
                            else
                                hideSet(s)
                            end
                        end
                    end

                    -- Hide despawned models
                    for model, s in pairs(drawings) do
                        if not activeModels[model] then hideSet(s) end
                    end
                end)

                if not ok then
                    task.wait(0.5)
                end
            end

            -- Cleanup ESP drawings
            for _, s in pairs(drawings) do
                for _, d in pairs(s) do pcall(function() d:Remove() end) end
            end
            getgenv().__RAVEN_ESP_DRAWINGS = {}
        end)
    end

    -- ESP UI Controls
    TabESP:CreateToggle({
        Name = "Enable ESP",
        CurrentValue = false,
        Callback = function(state)
            espSettings.enabled = state
        end,
    })

    TabESP:CreateToggle({
        Name = "Show Box",
        CurrentValue = true,
        Callback = function(state)
            espSettings.showBox = state
        end,
    })

    TabESP:CreateToggle({
        Name = "Show Name + Distance",
        CurrentValue = true,
        Callback = function(state)
            espSettings.showName = state
        end,
    })

    TabESP:CreateToggle({
        Name = "Show Health Bar",
        CurrentValue = true,
        Callback = function(state)
            espSettings.showHealth = state
        end,
    })

    TabESP:CreateSlider({
        Name = "Max Distance",
        Range = {50, 2000},
        Increment = 50,
        CurrentValue = 1500,
        Callback = function(val)
            espSettings.maxDistance = val
        end,
    })

    -- Start ESP loop
    startESP()

    -- ═══════════════════════════════════════════════
    -- CLEANUP REGISTRATION
    -- ═══════════════════════════════════════════════
    local function cleanup()
        getgenv().__RAVEN_NORECOIL_ACTIVE = false
        getgenv().__RAVEN_ESP_ACTIVE = false
        if speedConn then speedConn:Disconnect() end
        if noclipConn then noclipConn:Disconnect() end
        if recoilThread then pcall(task.cancel, recoilThread) end
        for _, s in pairs(getgenv().__RAVEN_ESP_DRAWINGS or {}) do
            for _, d in pairs(s) do pcall(function() d:Remove() end) end
        end
        getgenv().__RAVEN_ESP_DRAWINGS = {}
    end

    table.insert(getgenv().__RAVEN_CLEANUP, cleanup)

    -- Register with RAVENHUB cleanup system
    if info and info.registerCleanup then
        info.registerCleanup(cleanup)
    end
end
