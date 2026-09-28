-- ============================================================
--   RAVEN HUB  |  Frisbee Frenzy
--   UniverseId: 10230942274  |  PlaceId: 106986181033085
--   Player ESP + Combat State ESP + Auto-Block | 100% Drawing API (zero instances)
--   v1.1.0 — read-only visuals, no hooks, no remotes
--   Auto-Block: triggers the game's own "Blocking" status effect via
--   character state functions when an enemy M1 is detected nearby.
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    -- Clean up previous instance
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_FRISBEE_FRENZY) == "table"
        and type(environment.__RAVEN_FRISBEE_FRENZY.Destroy) == "function" then
        pcall(environment.__RAVEN_FRISBEE_FRENZY.Destroy)
    end
    environment.RAVEN_FRISBEE_FRENZY_VER = "1.1.0"

    local running = true
    local connections = {}
    local espCache = {}

    local settings = {
        espEnabled = true,
        boxEsp = true,
        nameEsp = true,
        healthEsp = true,
        combatEsp = true,
        distanceEsp = true,
        maxDistance = 2000,
        autoBlock = false,
        blockRange = 15,
        reactWindow = 0.5,
    }

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        return (ok and obj) or nil
    end

    local function getHealthColor(ratio)
        return Color3.fromHSV(math.clamp(ratio, 0, 1) * 0.33, 0.9, 1)
    end

    local function getEntry(p)
        local e = espCache[p]
        if e then return e end
        e = {}
        e.box = safeDrawing("Square")
        if e.box then e.box.Thickness = 1; e.box.Filled = false; e.box.Visible = false end
        e.barBack = safeDrawing("Square")
        if e.barBack then
            e.barBack.Thickness = 1; e.barBack.Filled = true
            e.barBack.Color = Color3.new(0, 0, 0); e.barBack.Transparency = 0.5
            e.barBack.Visible = false
        end
        e.bar = safeDrawing("Square")
        if e.bar then e.bar.Thickness = 1; e.bar.Filled = true; e.bar.Visible = false end
        e.name = safeDrawing("Text")
        if e.name then
            e.name.Size = 13; e.name.Center = true; e.name.Outline = true
            e.name.Color = Color3.new(1, 1, 1); e.name.Visible = false
        end
        e.info = safeDrawing("Text")
        if e.info then
            e.info.Size = 12; e.info.Center = true; e.info.Outline = true
            e.info.Color = Color3.new(1, 0.85, 0.3); e.info.Visible = false
        end
        espCache[p] = e
        return e
    end

    local function hideEntry(e)
        for _, k in ipairs({"box", "barBack", "bar", "name", "info"}) do
            local d = e[k]
            if d then pcall(function() d.Visible = false end) end
        end
    end

    local function destroyEntry(p)
        local e = espCache[p]
        if e then
            for _, k in ipairs({"box", "barBack", "bar", "name", "info"}) do
                local d = e[k]
                if d then pcall(function() d:Remove() end) end
            end
            espCache[p] = nil
        end
    end

    -- Combat state from live character attributes (read-only).
    -- AbilityName = current element; InRagdoll / M1Immunity / StarMode = status.
    local function getStatusText(ch)
        local parts = {}
        local ok, elem = pcall(ch.GetAttribute, ch, "AbilityName")
        if ok and type(elem) == "string" and elem ~= "" then
            table.insert(parts, elem)
        end
        local ok2, rag = pcall(ch.GetAttribute, ch, "InRagdoll")
        if ok2 and rag == true then table.insert(parts, "RAGDOLL") end
        local ok3, imm = pcall(ch.GetAttribute, ch, "M1Immunity")
        if ok3 and imm == true then table.insert(parts, "M1-IMM") end
        local ok4, star = pcall(ch.GetAttribute, ch, "StarMode")
        if ok4 and star == true then table.insert(parts, "STAR") end
        local ok5, combo = pcall(ch.GetAttribute, ch, "Combo")
        if ok5 and type(combo) == "number" and combo > 1 then
            table.insert(parts, "x" .. tostring(combo))
        end
        return table.concat(parts, " | ")
    end

    local function updateEsp()
        if not running or not settings.espEnabled then
            for _, e in pairs(espCache) do hideEntry(e) end
            return
        end
        camera = Workspace.CurrentCamera
        local myChar = localPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not camera or not myRoot then
            for _, e in pairs(espCache) do hideEntry(e) end
            return
        end
        local seen = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                local drawn = false
                local ch = p.Character
                local root = ch and ch:FindFirstChild("HumanoidRootPart")
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                local head = ch and ch:FindFirstChild("Head")
                if root and hum and hum.Health > 0 and head then
                    local dist = (myRoot.Position - root.Position).Magnitude
                    if dist <= settings.maxDistance then
                        local topPos, topOn = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.6, 0))
                        local botPos, botOn = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                        if topOn and botOn then
                            drawn = true
                            seen[p] = true
                            local e = getEntry(p)
                            local h = math.abs(botPos.Y - topPos.Y)
                            local w = h * 0.55
                            local x0 = topPos.X - w / 2
                            local y0 = topPos.Y
                            if e.box then
                                e.box.Visible = settings.boxEsp
                                if settings.boxEsp then
                                    e.box.Position = Vector2.new(x0, y0)
                                    e.box.Size = Vector2.new(w, h)
                                    e.box.Color = Color3.new(1, 1, 1)
                                end
                            end
                            local ratio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                            if e.barBack then
                                e.barBack.Visible = settings.healthEsp
                                if settings.healthEsp then
                                    e.barBack.Position = Vector2.new(x0 - 5, y0)
                                    e.barBack.Size = Vector2.new(3, h)
                                end
                            end
                            if e.bar then
                                e.bar.Visible = settings.healthEsp
                                if settings.healthEsp then
                                    local bh = math.max(h * ratio, 1)
                                    e.bar.Position = Vector2.new(x0 - 5, y0 + (h - bh))
                                    e.bar.Size = Vector2.new(3, bh)
                                    e.bar.Color = getHealthColor(ratio)
                                end
                            end
                            if e.name then
                                e.name.Visible = settings.nameEsp
                                if settings.nameEsp then
                                    local txt = p.DisplayName
                                    if settings.distanceEsp then
                                        txt = txt .. " [" .. math.floor(dist) .. "m]"
                                    end
                                    e.name.Text = txt
                                    e.name.Position = Vector2.new(topPos.X, y0 - 16)
                                end
                            end
                            if e.info then
                                e.info.Visible = settings.combatEsp
                                if settings.combatEsp then
                                    e.info.Text = getStatusText(ch)
                                    e.info.Position = Vector2.new(topPos.X, y0 + h + 2)
                                end
                            end
                        end
                    end
                end
                if not drawn then
                    local e = espCache[p]
                    if e then hideEntry(e) end
                end
            end
        end
        for p, e in pairs(espCache) do
            if not seen[p] then hideEntry(e) end
        end
    end

    -- [[ Auto-Block ]]
    -- The game tracks blocking as a "Blocking" status effect on the character
    -- (IsCharacterBlocking = HasStatusEffect(ch, "Blocking")). We trigger and
    -- release it through the game's own character-state functions — the same
    -- path the game uses internally. No remotes, no hooks.
    local blockHolder = nil
    local function getBlockHolder()
        if blockHolder then return blockHolder end
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" then
                pcall(function()
                    if rawget(v, "IsCharacterBlocking") ~= nil then
                        blockHolder = v
                    end
                end)
                if blockHolder then break end
            end
        end
        return blockHolder
    end

    local function getMyChar()
        return localPlayer.Character
    end

    local function isBlocking()
        local h = getBlockHolder()
        local ch = getMyChar()
        if not h or not ch then return false end
        local ok, res = pcall(h.IsCharacterBlocking, ch)
        return ok and res == true
    end

    local function startBlock()
        local h = getBlockHolder()
        local ch = getMyChar()
        if not h or not ch or isBlocking() then return end
        pcall(h.AddStatusEffect, ch, "Blocking")
    end

    local function stopBlock()
        local h = getBlockHolder()
        local ch = getMyChar()
        if not h or not ch or not isBlocking() then return end
        local ok, effs = pcall(h.GetStatusEffects, ch)
        if not ok or type(effs) ~= "table" then return end
        local copy = {}
        for _, e in ipairs(effs) do table.insert(copy, e) end
        for _, e in ipairs(copy) do
            local isB = false
            pcall(function() isB = (type(e) == "table" and e.Name == "Blocking") end)
            if isB then pcall(h.RemoveStatusEffect, ch, e) end
        end
    end

    local function safeAttr(inst, name)
        local ok, v = pcall(inst.GetAttribute, inst, name)
        return ok and v or nil
    end

    -- Threat detection: an enemy is swinging if their M1Count just increased
    -- or their LastM1Time (Unix epoch, matches DateTime.now()) is within
    -- the reaction window. NOTE: LastM1Time is NOT on tick() epoch
    -- (differs by ~7h); must use DateTime/os.time epoch.
    local lastM1Count = {}
    local function updateAutoBlock()
        if not running or not settings.autoBlock then return end
        local ch = getMyChar()
        local myRoot = ch and ch:FindFirstChild("HumanoidRootPart")
        if not myRoot then stopBlock() return end
        local myPos = myRoot.Position
        local now = DateTime.now().UnixTimestampMillis / 1000
        local threat = false
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer and p.Character then
                local ech = p.Character
                local m1c = safeAttr(ech, "M1Count")
                local lm1t = safeAttr(ech, "LastM1Time")
                local prev = lastM1Count[p]
                local freshSwing = false
                if type(m1c) == "number" and type(prev) == "number" and m1c > prev then
                    freshSwing = true
                end
                if type(lm1t) == "number" and (now - lm1t) < settings.reactWindow then
                    freshSwing = true
                end
                if type(m1c) == "number" then lastM1Count[p] = m1c end
                if freshSwing then
                    local eroot = ech:FindFirstChild("HumanoidRootPart")
                    if eroot and (eroot.Position - myPos).Magnitude <= settings.blockRange then
                        threat = true
                        break
                    end
                end
            end
        end
        if threat then startBlock() else stopBlock() end
    end

    -- [[ UI ]]
    local VisualsTab = Window:CreateTab("Visuals", 4483362458)
    VisualsTab:CreateSection("Player ESP")

    VisualsTab:CreateToggle({
        Name = "Enable ESP",
        CurrentValue = true,
        Flag = "FF_ESPEnabled",
        Callback = function(v) settings.espEnabled = v end,
    })

    VisualsTab:CreateToggle({
        Name = "Box",
        CurrentValue = true,
        Flag = "FF_BoxEsp",
        Callback = function(v) settings.boxEsp = v end,
    })

    VisualsTab:CreateToggle({
        Name = "Name + Distance",
        CurrentValue = true,
        Flag = "FF_NameEsp",
        Callback = function(v)
            settings.nameEsp = v
            settings.distanceEsp = v
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Health Bar",
        CurrentValue = true,
        Flag = "FF_HealthEsp",
        Callback = function(v) settings.healthEsp = v end,
    })

    VisualsTab:CreateToggle({
        Name = "Combat Info (Element / Status)",
        CurrentValue = true,
        Flag = "FF_CombatEsp",
        Callback = function(v) settings.combatEsp = v end,
    })

    VisualsTab:CreateSlider({
        Name = "Max Distance",
        Range = {100, 5000},
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 2000,
        Flag = "FF_MaxDistance",
        Callback = function(v) settings.maxDistance = v end,
    })

    -- [[ Connections ]]
    table.insert(connections, RunService.RenderStepped:Connect(updateEsp))
    table.insert(connections, Players.PlayerRemoving:Connect(function(p)
        destroyEntry(p)
        lastM1Count[p] = nil
    end))

    -- Auto-block ticker (10 Hz is plenty for M1 reactions)
    task.spawn(function()
        while running do
            local ok, err = pcall(updateAutoBlock)
            task.wait(0.1)
        end
    end)

    local CombatTab = Window:CreateTab("Combat", 4483362458)
    CombatTab:CreateSection("Defense")

    CombatTab:CreateToggle({
        Name = "Auto-Block",
        CurrentValue = false,
        Flag = "FF_AutoBlock",
        Callback = function(v)
            settings.autoBlock = v
            if not v then stopBlock() end
        end,
    })

    CombatTab:CreateSlider({
        Name = "Block Range",
        Range = {5, 30},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = 15,
        Flag = "FF_BlockRange",
        Callback = function(v) settings.blockRange = v end,
    })

    CombatTab:CreateSlider({
        Name = "Reaction Window",
        Range = {0.2, 1.0},
        Increment = 0.05,
        Suffix = "s",
        CurrentValue = 0.5,
        Flag = "FF_ReactWindow",
        Callback = function(v) settings.reactWindow = v end,
    })

    local api = {}
    function api.Destroy()
        running = false
        pcall(stopBlock)
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        for p, _ in pairs(espCache) do destroyEntry(p) end
        environment.__RAVEN_FRISBEE_FRENZY = nil
    end
    function api.SetAutoBlock(v)
        settings.autoBlock = v and true or false
        if not settings.autoBlock then stopBlock() end
    end
    function api.IsBlocking() return isBlocking() end
    function api.StartBlock() startBlock() end
    function api.StopBlock() stopBlock() end
    environment.__RAVEN_FRISBEE_FRENZY = api

    return api
end
