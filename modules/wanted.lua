-- ============================================================
--   RAVEN HUB  |  Wanted
--   UniverseId: 4987856151  |  PlaceId: 14438406081
--   Player ESP + ATM ESP + NPC/Vehicle ESP + Wanted HUD + Aimbot
--   v1.1.0 — 100% Drawing API (zero instances), no hooks, no remotes
--   Read-only visuals + mouse-driven aim.
--   v1.2.9: teleport 70m hops/0.8s (proven reliable, was 40m/0.25s flaky).
--   v1.2.8: sell = E opens Ofy dialog then press 1 ([Sell Loot]).
--   v1.2.7: PawnOfy part pos; teleport steps in 40m hops (long tp blocked).
--   v1.2.6: teleport uses char:PivotTo (direct hrp.CFrame blocked by game).
--   v1.2.4: destroy() cleans lootCache+cashCache; auto-rob skips PelicanCase.
--   v1.2.3: loot ESP hides all markers first (stale-marker cleanup fix).
--   v1.2.2: stuck-target detection (E 3x no progress -> 5min cooldown).
--   v1.2.1: loot ESP capped at 150m (was showing 300m+ clutter).
--   v1.2.0: skip broken ATMs (red alarm / cooldown timer); auto-rob Lootables +
--   PelicanCases (uncommon first, items -> bag -> pawn); Loot ESP.
--   v1.1.2: scanCash ignores cash >150m away (bank cluster rubber-band fix).
--   v1.1.1: ATM cash -> cash attribute directly (not the bag); faster loop
--   (0.3s/1.0s) + session earnings in the status label.
--   v1.1.0: Auto-Rob (new Robbery tab) — punch ATMs via legit E keypress
--   (VirtualInputManager), collect highest-value dropped cash first, auto-sell
--   at pawn NPC Ofy when bag is full. Cash ESP shows $ values.
--   v1.0.9: box thickness back to 2; wanted stars as * (ASCII).
--   v1.0.8: wanted stars as ★ icons (was [Wn]); bigger name text (16),
--   thicker box (3) for readability.
--   v1.0.7: team-colored player ESP (police=blue, syndicate=red, none=amber)
--   via the game's currentTeam attribute; box + name use the team color,
--   wanted stars shown as [Wn] prefix; thicker box + larger text.
--   v1.0.6 fix: mouse wheel over the menu also zoomed the game camera —
--   added Enum.UserInputType.MouseWheel to the CAS sink (Change state);
--   the menu's own scroll uses raw InputChanged and ignores the processed
--   flag, so it keeps scrolling normally.
--   v1.0.5 fix: CAS sink alone could not stop the gun (the game's Shooter
--   sets tool.shooting through its own CAS action). The game's own fire gate
--   returns early while LocalPlayer:GetAttribute("gunsDisabled") is truthy,
--   so the module now sets that attribute while the menu is open and restores
--   the previous value on close/destroy.
--   v1.0.4 fixes: (1) ESP bled through the menu because the executor's default
--   Drawing ZIndex is 1, equal to the menu chassis — all module drawings now
--   use ZIndex 0 (below the menu). (2) The UI library never blocked input, so
--   clicks on the menu also hit the game — added ContextActionService sink at
--   priority 3000 while the menu is open and the cursor is over it; aimbot
--   also pauses while the menu is open.
--   Tested live 2026-09-29 on N3zuui/Potassium (Wanted placeId 14438406081):
--   compile OK, marker 1.0.0, tabs Visuals/HUD/Combat, 7 ATMs found,
--   13/13 player ESP entries, HUD "Cash: $24,410 | Bounty: none",
--   aimbot target lock OK (SIUPINOBB), destroy + reload OK, no errors.
-- ============================================================

return function(Window, ctx)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    -- Clean up previous instance (ghost UI prevention)
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_WANTED) == "table"
        and type(environment.__RAVEN_WANTED.Destroy) == "function" then
        pcall(environment.__RAVEN_WANTED.Destroy)
    end
    pcall(function()
        if type(environment.__RAVEN_WINDOW) == "table"
            and type(environment.__RAVEN_WINDOW.Destroy) == "function" then
            environment.__RAVEN_WINDOW.Destroy()
        end
    end)
    environment.RAVEN_WANTED_VER = "1.2.9"

    local running = true
    local connections = {}
    local uiSections = {} -- sections this module created (for clean reload)
    local espCache = {}
    local npcCache = {}
    local vehCache = {}
    local atmCache = {}
    local atmList = {}
    local lastAtmScan = 0

    local settings = {
        espEnabled = true,
        boxEsp = true,
        nameEsp = true,
        healthEsp = true,
        distanceEsp = true,
        teamColors = true,
        maxDistance = 2000,
        npcEsp = true,
        vehicleEsp = true,
        atmEsp = true,
        hudEnabled = true,
        showCash = true,
        showBounty = true,
        aimbot = false,
        aimMaxDist = 500,
        aimFov = 150,
        aimSmooth = 0.35,
        autoRob = false,
        autoSell = true,
        cashEsp = true,
        autoLoot = true,
        lootEsp = true,
    }

    -- Track every section we create so destroy() can remove them from the
    -- tab. The UI library reuses tabs by name (CreateTab returns the existing
    -- tab), so without this a module reload would stack duplicate sections.
    local function trackSection(tab, name)
        local sec = tab:CreateSection(name)
        table.insert(uiSections, sec)
        return sec
    end

    local function removeUiSections()
        for _, sec in ipairs(uiSections) do
            pcall(function()
                local tab = sec.tab
                if tab and type(tab.sections) == "table" then
                    for i, s in ipairs(tab.sections) do
                        if s == sec then
                            table.remove(tab.sections, i)
                            break
                        end
                    end
                    if tab._currentSection == sec then
                        tab._currentSection = nil
                    end
                end
                -- Hide every Drawing (userdata) owned by the section; skip
                -- tab/window back-references so the rest of the UI survives.
                local seen = {}
                local function hideDeep(t)
                    if type(t) ~= "table" or seen[t] then return end
                    seen[t] = true
                    for k, v in pairs(t) do
                        if k ~= "tab" and k ~= "window" then
                            if type(v) == "userdata" then
                                pcall(function() v.Visible = false end)
                            elseif type(v) == "table" then
                                hideDeep(v)
                            end
                        end
                    end
                end
                hideDeep(sec)
            end)
        end
        uiSections = {}
    end

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        if ok and obj then
            -- v1.0.4: executor default ZIndex is 1, same as the menu chassis,
            -- so ESP used to render through the menu. Keep every module
            -- drawing strictly below the menu (min ZIndex 1).
            pcall(function() obj.ZIndex = 0 end)
        end
        return (ok and obj) or nil
    end

    local function getHealthColor(ratio)
        return Color3.fromHSV(math.clamp(ratio, 0, 1) * 0.33, 0.9, 1)
    end

    -- v1.0.7: team colors from the game's currentTeam player attribute.
    -- police = blue, syndicate = red, anything else (none/civilian) = amber.
    local TEAM_COLORS = {
        police = Color3.fromRGB(90, 170, 255),
        syndicate = Color3.fromRGB(255, 90, 90),
    }
    local DEFAULT_ESP_COLOR = Color3.fromRGB(255, 200, 60)
    local function getTeamColor(p)
        if not settings.teamColors then return DEFAULT_ESP_COLOR end
        local t = p:GetAttribute("currentTeam")
        if type(t) == "string" then
            local c = TEAM_COLORS[string.lower(t)]
            if c then return c end
        end
        return DEFAULT_ESP_COLOR
    end

    local function worldPosOf(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then
            local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
            return pp and pp.Position or nil
        end
        return nil
    end

    -- [[ Player ESP entries (Drawing API, zero instances) ]]
    local function getEntry(p)
        local e = espCache[p]
        if e then return e end
        e = {
            box = safeDrawing("Square"),
            name = safeDrawing("Text"),
            hpBack = safeDrawing("Square"),
            hpFill = safeDrawing("Square"),
        }
        if e.box then
            e.box.Thickness = 2
            e.box.Filled = false
            e.box.Color = Color3.fromRGB(255, 200, 60)
            e.box.Visible = false
        end
        if e.name then
            e.name.Size = 16
            e.name.Center = true
            e.name.Outline = true
            e.name.Color = Color3.fromRGB(255, 255, 255)
            e.name.Visible = false
        end
        if e.hpBack then
            e.hpBack.Filled = true
            e.hpBack.Color = Color3.fromRGB(20, 20, 20)
            e.hpBack.Visible = false
        end
        if e.hpFill then
            e.hpFill.Filled = true
            e.hpFill.Visible = false
        end
        espCache[p] = e
        return e
    end

    local function hideEntry(e)
        for _, d in pairs(e) do
            if d ~= nil then pcall(function() d.Visible = false end) end
        end
    end

    local function destroyEntry(p)
        local e = espCache[p]
        if e then
            for _, d in pairs(e) do
                if d ~= nil then pcall(function() d:Remove() end) end
            end
            espCache[p] = nil
        end
    end

    -- [[ Generic single-text marker (NPC / vehicle / ATM) ]]
    local function getMarker(cache, key, color)
        local m = cache[key]
        if m then return m end
        m = safeDrawing("Text")
        if m then
            m.Size = 13
            m.Center = true
            m.Outline = true
            m.Color = color or Color3.fromRGB(120, 220, 255)
            m.Visible = false
        end
        cache[key] = m
        return m
    end

    local function hideMarkers(cache)
        for _, m in pairs(cache) do
            if m ~= nil then pcall(function() m.Visible = false end) end
        end
    end

    local function projectLabel(drawing, worldPos, text, color)
        if not drawing then return end
        local v, on = camera:WorldToViewportPoint(worldPos)
        if on and v.Z > 0 then
            drawing.Position = Vector2.new(v.X, v.Y)
            drawing.Text = text
            if color then drawing.Color = color end
            drawing.Visible = true
        else
            drawing.Visible = false
        end
    end

    local function updatePlayerEsp()
        if not settings.espEnabled then
            for _, e in pairs(espCache) do hideEntry(e) end
            return
        end
        local camPos = camera.CFrame.Position
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                local e = getEntry(p)
                local ch = p.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    local dist = (hrp.Position - camPos).Magnitude
                    if dist <= settings.maxDistance then
                        local top, topOn = camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                        local bot, botOn = camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                        if topOn and botOn then
                            local h = math.abs(top.Y - bot.Y)
                            local w = h * 0.55
                            local teamColor = getTeamColor(p)
                            if e.box then
                                e.box.Size = Vector2.new(w, h)
                                e.box.Position = Vector2.new(top.X - w / 2, top.Y)
                                e.box.Color = teamColor
                                e.box.Visible = settings.boxEsp
                            end
                            if e.name then
                                local txt = p.Name
                                local stars = math.floor(tonumber(p:GetAttribute("stars")) or 0)
                                if stars > 0 then
                                    txt = string.rep("*", math.min(stars, 5)) .. " " .. txt
                                end
                                if settings.distanceEsp then
                                    txt = txt .. " [" .. math.floor(dist) .. "m]"
                                end
                                e.name.Text = txt
                                e.name.Color = teamColor
                                e.name.Position = Vector2.new(top.X, top.Y - 20)
                                e.name.Visible = settings.nameEsp
                            end
                            local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                            if e.hpBack then
                                e.hpBack.Size = Vector2.new(4, h)
                                e.hpBack.Position = Vector2.new(top.X - w / 2 - 6, top.Y)
                                e.hpBack.Visible = settings.healthEsp
                            end
                            if e.hpFill then
                                e.hpFill.Size = Vector2.new(2, h * ratio)
                                e.hpFill.Position = Vector2.new(top.X - w / 2 - 5, top.Y + h * (1 - ratio))
                                e.hpFill.Color = getHealthColor(ratio)
                                e.hpFill.Visible = settings.healthEsp
                            end
                        else
                            hideEntry(e)
                        end
                    else
                        hideEntry(e)
                    end
                else
                    hideEntry(e)
                end
            end
        end
    end

    -- NPC list is cached and rescanned every few seconds. Scanning
    -- Workspace:GetDescendants() every frame cost ~4.3ms on 53k instances
    -- (measured 2026-09-29) and was the main lag source in v1.0.0.
    local npcList = {}
    local lastNpcScan = 0
    local NPC_SCAN_INTERVAL = 4

    local function scanNpcs()
        npcList = {}
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Humanoid") then
                local model = d.Parent
                if model and model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
                    local hrp = model:FindFirstChild("HumanoidRootPart")
                    if hrp and d.Health > 0 then
                        table.insert(npcList, { model = model, hrp = hrp })
                    end
                end
            end
        end
        lastNpcScan = os.clock()
    end

    local function updateNpcEsp()
        if not settings.npcEsp then hideMarkers(npcCache) return end
        if os.clock() - lastNpcScan > NPC_SCAN_INTERVAL then scanNpcs() end
        local camPos = camera.CFrame.Position
        local seen = {}
        for _, npc in ipairs(npcList) do
            local model, hrp = npc.model, npc.hrp
            if model.Parent and hrp.Parent then
                local dist = (hrp.Position - camPos).Magnitude
                if dist <= settings.maxDistance then
                    seen[model] = true
                    local m = getMarker(npcCache, model, Color3.fromRGB(255, 120, 120))
                    projectLabel(m, hrp.Position + Vector3.new(0, 3, 0),
                        "BOT [" .. math.floor(dist) .. "m]")
                end
            end
        end
        for model, m in pairs(npcCache) do
            if not seen[model] and m ~= nil then
                pcall(function() m.Visible = false end)
            end
        end
    end

    local function updateVehicleEsp()
        if not settings.vehicleEsp then hideMarkers(vehCache) return end
        local camPos = camera.CFrame.Position
        local folder = Workspace:FindFirstChild("Vehicles")
        if not folder then hideMarkers(vehCache) return end
        local seen = {}
        for _, v in ipairs(folder:GetChildren()) do
            local pos = worldPosOf(v)
            if pos then
                local dist = (pos - camPos).Magnitude
                if dist <= settings.maxDistance then
                    seen[v] = true
                    local m = getMarker(vehCache, v, Color3.fromRGB(120, 255, 150))
                    projectLabel(m, pos + Vector3.new(0, 3, 0),
                        "CAR [" .. math.floor(dist) .. "m]")
                end
            end
        end
        for v, m in pairs(vehCache) do
            if not seen[v] and m ~= nil then
                pcall(function() m.Visible = false end)
            end
        end
    end

    local function scanAtms()
        atmList = {}
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name == "ATM" then
                local pos = worldPosOf(d)
                if pos then table.insert(atmList, { model = d, pos = pos }) end
            end
        end
        lastAtmScan = os.clock()
    end

    local function updateAtmEsp()
        if not settings.atmEsp then hideMarkers(atmCache) return end
        if os.clock() - lastAtmScan > 8 then scanAtms() end
        local camPos = camera.CFrame.Position
        for i, a in ipairs(atmList) do
            local m = getMarker(atmCache, "atm" .. i, Color3.fromRGB(255, 220, 80))
            local dist = (a.pos - camPos).Magnitude
            if dist <= settings.maxDistance then
                projectLabel(m, a.pos + Vector3.new(0, 4, 0),
                    "ATM [" .. math.floor(dist) .. "m]")
            elseif m then
                pcall(function() m.Visible = false end)
            end
        end
        -- hide stale markers beyond current atm count
        local i = #atmList + 1
        while atmCache["atm" .. i] ~= nil do
            local m = atmCache["atm" .. i]
            pcall(function() m.Visible = false end)
            i = i + 1
        end
    end

    local function teleportToNearestAtm()
        if os.clock() - lastAtmScan > 8 then scanAtms() end
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return "no character" end
        local best, bestDist = nil, math.huge
        for _, a in ipairs(atmList) do
            local d = (a.pos - hrp.Position).Magnitude
            if d < bestDist then best, bestDist = a, d end
        end
        if not best then return "no ATM found" end
        hrp.CFrame = CFrame.new(best.pos + Vector3.new(0, 4, 0))
        hrp.Velocity = Vector3.new(0, 0, 0)
        return "teleported (" .. math.floor(bestDist) .. "m)"
    end

    -- [[ Auto-Rob: punch ATMs -> collect cash (highest $ first) -> sell at pawn ]]
    -- 100% legit input path: VirtualInputManager E-press (real engine input,
    -- not a remote/hook) + CFrame teleport (same as the TP button).
    local OFY_POS = Vector3.new(-2821, 37, 1740) -- PawnOfy part, verified live
    local cashCache = {}
    local cashList = {}
    local lastCashScan = 0
    local robStatus = "idle"
    local robThread = nil
    local vim = nil
    pcall(function() vim = game:GetService("VirtualInputManager") end)

    local function pressE()
        if not vim then return false end
        return pcall(function()
            vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.12)
            vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end)
    end
    local function pressKey(key)
        if not vim then return false end
        return pcall(function()
            vim:SendKeyEvent(true, key, false, game)
            task.wait(0.12)
            vim:SendKeyEvent(false, key, false, game)
        end)
    end

    local function teleportNear(pos, dy)
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not hrp then return false end
        -- PivotTo: direct hrp.CFrame is silently blocked by the game.
        -- Long jumps (>~85m) get rubber-banded; rapid jumps get ignored.
        -- Proven: 70m hops with 0.8s settle between each.
        local target = pos + Vector3.new(0, dy or 3, 0)
        local startPos = hrp.Position
        local dist = (Vector3.new(target.X, target.Y, target.Z) - Vector3.new(startPos.X, startPos.Y, startPos.Z)).Magnitude
        if dist > 75 then
            local steps = math.ceil(dist / 70)
            for i = 1, steps do
                if not running then return false end
                local wp = startPos:Lerp(target, i / steps) + Vector3.new(0, 3, 0)
                pcall(function() char:PivotTo(CFrame.new(wp)) end)
                task.wait(0.8)
            end
        else
            pcall(function() char:PivotTo(CFrame.new(target)) end)
        end
        local hrp2 = char:FindFirstChild("HumanoidRootPart")
        if hrp2 then pcall(function() hrp2.Velocity = Vector3.new(0, 0, 0) end) end
        return true
    end

    -- stuck-target tracking: E with no progress -> cooldown the target
    local failCount = {}
    local cooldownUntil = {}
    local function targetId(model)
        return model and tostring(model:GetAttribute('objectId') or model:GetFullName()) or '?'
    end
    local function isOnCooldown(model)
        local id = targetId(model)
        return cooldownUntil[id] and os.clock() < cooldownUntil[id]
    end
    local function recordFail(model)
        local id = targetId(model)
        failCount[id] = (failCount[id] or 0) + 1
        if failCount[id] >= 3 then
            cooldownUntil[id] = os.clock() + 300
            failCount[id] = 0
        end
    end
    local function recordSuccess(model)
        failCount[targetId(model)] = 0
    end

    -- broken ATM: screen shows cooldown timer (not 00:00:00), alarm red
    local function isAtmBroken(atmModel)
        for _, c in ipairs(atmModel:GetDescendants()) do
            if c:IsA("TextLabel") then
                local txt = c.Text or ""
                if string.find(txt, "%d+:%d+") and txt ~= "00:00:00" then
                    return true
                end
            end
        end
        return false
    end

    -- lootables (shop items -> bag) + pelican cases, uncommon first
    local lootCache = {}
    local lootList = {}
    local lastLootScan = 0
    local RARITY_SCORE = { Uncommon = 2, Common = 1 }
    local function scanLoot()
        lootList = {}
        local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myPos = hrp and hrp.Position or nil
        for _, d in ipairs(Workspace:GetDescendants()) do
            local gt = d:GetAttribute("gizmoType")
            if gt == "Lootable" or gt == "PelicanCase" then
                local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
                if pp and not isOnCooldown(d) and (not myPos or (pp.Position - myPos).Magnitude <= 500) then
                    local rar = tostring(d:GetAttribute("rarity") or (gt == "PelicanCase" and "Rare" or "?"))
                    table.insert(lootList, { model = d, pos = pp.Position,
                        name = d.Name, rarity = rar,
                        score = RARITY_SCORE[rar] or (gt == "PelicanCase" and 3 or 0) })
                end
            end
        end
        table.sort(lootList, function(a, b)
            if a.score ~= b.score then return a.score > b.score end
            if myPos then
                return (a.pos - myPos).Magnitude < (b.pos - myPos).Magnitude
            end
            return false
        end)
        lastLootScan = os.clock()
    end

    local function updateLootEsp()
        if not settings.lootEsp then hideMarkers(lootCache) return end
        if os.clock() - lastLootScan > 8 then scanLoot() end
        local camPos = camera.CFrame.Position
        local colors = { Rare = Color3.fromRGB(255, 170, 0), Uncommon = Color3.fromRGB(120, 200, 255),
            Common = Color3.fromRGB(160, 160, 160) }
        -- hide all first (kills stale markers from older scans)
        for j = 1, 40 do
            local hm = lootCache["loot" .. j]
            if hm then pcall(function() hm.Visible = false end) end
        end
        local shown = 0
        for _, l in ipairs(lootList) do
            if shown >= 30 then break end
            local dist = (l.pos - camPos).Magnitude
            if dist <= 150 then
                shown = shown + 1
                local col = colors[l.rarity] or Color3.fromRGB(200, 200, 200)
                local m = getMarker(lootCache, "loot" .. shown, col)
                if m then
                    projectLabel(m, l.pos + Vector3.new(0, 2, 0),
                        l.name .. " [" .. math.floor(dist) .. "m]", col)
                end
            end
        end
    end

    local function scanCash()
        cashList = {}
        local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        local myPos = hrp and hrp.Position or nil
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("Model") and d.Name == "Cash" then
                local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
                if pp and (not myPos or (pp.Position - myPos).Magnitude <= 150) then
                    local value = 0
                    for _, c in ipairs(d:GetDescendants()) do
                        if c:IsA("TextLabel") then
                            local num = tonumber(string.match(c.Text or "", "%d+"))
                            if num then value = num break end
                        end
                    end
                    table.insert(cashList, { model = d, pos = pp.Position, value = value })
                end
            end
        end
        table.sort(cashList, function(a, b) return a.value > b.value end)
        lastCashScan = os.clock()
    end

    local function updateCashEsp()
        if not settings.cashEsp then hideMarkers(cashCache) return end
        if os.clock() - lastCashScan > 5 then scanCash() end
        local camPos = camera.CFrame.Position
        for i, c in ipairs(cashList) do
            local m = getMarker(cashCache, "cash" .. i, Color3.fromRGB(80, 255, 120))
            if m then
                local dist = (c.pos - camPos).Magnitude
                if dist <= settings.maxDistance then
                    projectLabel(m, c.pos + Vector3.new(0, 2, 0),
                        "$" .. c.value .. " [" .. math.floor(dist) .. "m]",
                        Color3.fromRGB(80, 255, 120))
                else
                    pcall(function() m.Visible = false end)
                end
            end
        end
        local i = #cashList + 1
        while cashCache["cash" .. i] ~= nil do
            local m = cashCache["cash" .. i]
            pcall(function() m.Visible = false end)
            i = i + 1
        end
    end

    local function isBagFull()
        return localPlayer:GetAttribute("isBagFull") == true
    end

    local function nearestAtmPos()
        if os.clock() - lastAtmScan > 8 then scanAtms() end
        local hrp = localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil, 0 end
        local best, bestDist, skipped = nil, math.huge, 0
        for _, a in ipairs(atmList) do
            if isOnCooldown(a.model) then
                skipped = skipped + 1
            elseif isAtmBroken(a.model) then
                skipped = skipped + 1
            else
                local d = (a.pos - hrp.Position).Magnitude
                if d < bestDist then best, bestDist = a, d end
            end
        end
        return best and best.pos or nil, skipped
    end

    local function autoRobLoop()
        local startCash = tonumber(localPlayer:GetAttribute("cash")) or 0
        local function earned()
            return (tonumber(localPlayer:GetAttribute("cash")) or 0) - startCash
        end
        while settings.autoRob and running do
            -- ATM cash goes straight to the cash attribute, not the bag.
            -- The bag is for shop/bank loot: sell whenever it fills up.
            if settings.autoSell and isBagFull() then
                robStatus = "bag full -> selling at pawn"
                if teleportNear(OFY_POS, 3) then
                    task.wait(0.8)
                    for i = 1, 3 do
                        if not isBagFull() then break end
                        pressE() -- open Ofy dialog
                        task.wait(1.0)
                        pressKey(Enum.KeyCode.One) -- 1 = [Sell Loot]
                        task.wait(1.5)
                    end
                end
                robStatus = isBagFull() and "sell failed?" or "sold! (+" .. earned() .. ")"
                task.wait(0.5)
            else
                scanCash()
                if #cashList > 0 then
                    local c = cashList[1]
                    robStatus = "collecting $" .. c.value .. " (+" .. earned() .. ")"
                    if teleportNear(c.pos, 2) then
                        task.wait(0.3)
                        pressE()
                        task.wait(0.5)
                    end
                else
                    local didLoot = false
                    if settings.autoLoot and not isBagFull() then
                        scanLoot()
                        local l = nil
                        for _, cand in ipairs(lootList) do
                            if cand.model:GetAttribute('gizmoType') == 'Lootable' then
                                l = cand break
                            end
                        end
                        if l then
                            robStatus = "stealing " .. l.name .. " (" .. l.rarity .. ")"
                            if teleportNear(l.pos, 2.5) then
                                local hadBag = localPlayer:GetAttribute("hasLootBag")
                                task.wait(0.4)
                                pressE()
                                task.wait(1.0)
                                if l.model.Parent == nil or localPlayer:GetAttribute("hasLootBag") ~= hadBag
                                    or isBagFull() then
                                    recordSuccess(l.model)
                                else
                                    recordFail(l.model)
                                    robStatus = "skip " .. l.name .. " (no progress)"
                                end
                            end
                            didLoot = true
                        end
                    end
                    if not didLoot then
                        local atmTarget, skipped = nearestAtmPos()
                        if atmTarget then
                            robStatus = "robbing ATM... (+" .. earned() .. ")"
                            if teleportNear(atmTarget, 2.5) then
                                local before = tonumber(localPlayer:GetAttribute("cash")) or 0
                                task.wait(0.3)
                                pressE()
                                task.wait(1.0)
                                local atmModel = nil
                                for _, a in ipairs(atmList) do
                                    if (a.pos - atmTarget).Magnitude < 5 then atmModel = a.model break end
                                end
                                if atmModel then
                                    if (tonumber(localPlayer:GetAttribute("cash")) or 0) > before then
                                        recordSuccess(atmModel)
                                    else
                                        recordFail(atmModel)
                                    end
                                end
                            end
                        else
                            robStatus = skipped > 0 and ("all ATMs broken (" .. skipped .. ")") or "no ATM found"
                            task.wait(2)
                        end
                    end
                end
            end
        end
        robStatus = "idle"
    end

    local function setAutoRob(v)
        settings.autoRob = v
        if v and not robThread then
            robThread = task.spawn(function()
                pcall(autoRobLoop)
                robThread = nil
            end)
        end
    end

    -- [[ Wanted HUD (reads the game's own GUI, client-side only) ]]
    local hudText = safeDrawing("Text")
    if hudText then
        hudText.Size = 15
        hudText.Center = false
        hudText.Outline = true
        hudText.Color = Color3.fromRGB(255, 230, 120)
        hudText.Position = Vector2.new(16, 40)
        hudText.Visible = false
    end

    local function readGuiText(...)
        local inst = localPlayer
        for _, name in ipairs({ ... }) do
            inst = inst and inst:FindFirstChild(name) or nil
        end
        if inst and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
            return inst.Text
        end
        return nil
    end

    local function updateHud()
        if not hudText then return end
        if not settings.hudEnabled then
            pcall(function() hudText.Visible = false end)
            return
        end
        local lines = {}
        if settings.showCash then
            local cash = readGuiText("PlayerGui", "TopbarScreen", "TopbarFrame", "CashFrame", "CashLabel")
            if cash and #cash > 0 then
                table.insert(lines, "Cash: " .. cash)
            end
        end
        if settings.showBounty then
            local bounty = readGuiText("PlayerGui", "WantedScreen", "Stars", "BountyLabel")
            if bounty and #bounty > 0 and bounty:find("BOUNTY") then
                table.insert(lines, "Bounty: " .. bounty)
            else
                table.insert(lines, "Bounty: none")
            end
            local cd = readGuiText("PlayerGui", "WantedScreen", "Stars", "CountdownLabel")
            if cd and #cd > 0 then
                local lbl = localPlayer.PlayerGui
                    and localPlayer.PlayerGui:FindFirstChild("WantedScreen")
                local stars = lbl and lbl:FindFirstChild("Stars")
                local cdl = stars and stars:FindFirstChild("CountdownLabel")
                if cdl and cdl.Visible then
                    table.insert(lines, "Wanted clears in: " .. cd)
                end
            end
        end
        hudText.Text = table.concat(lines, "   |   ")
        hudText.Visible = #lines > 0
    end

    -- [[ Aimbot: mouse-driven (no hitbox edits, no hooks, no remotes) ]]
    -- v1.0.2: drives the real mouse via mousemoverel() so the game's own
    -- camera turns toward the target. Writing Camera.CFrame directly does NOT
    -- work in this game (the camera controller overwrites it every frame).
    -- Target = head closest to crosshair within FOV, smoothed per-tick.
    local function getAimTarget()
        local best, bestPx = nil, settings.aimFov
        local center = camera.ViewportSize / 2
        local camPos = camera.CFrame.Position
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                local ch = p.Character
                local head = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if head and hum and hum.Health > 0 then
                    if (head.Position - camPos).Magnitude <= settings.aimMaxDist then
                        local v, on = camera:WorldToViewportPoint(head.Position)
                        if on and v.Z > 0 then
                            local px = (Vector2.new(v.X, v.Y) - center).Magnitude
                            if px < bestPx then
                                best, bestPx = head, px
                            end
                        end
                    end
                end
            end
        end
        return best
    end

    local fovCircle = safeDrawing("Circle")
    if fovCircle then
        fovCircle.Visible = false
        fovCircle.Thickness = 1
        fovCircle.Filled = false
        fovCircle.Transparency = 1
        fovCircle.Color = Color3.fromRGB(255, 255, 255)
    end

    local function updateFovCircle()
        if not fovCircle then return end
        if settings.aimbot then
            local vs = camera.ViewportSize
            fovCircle.Position = Vector2.new(vs.X / 2, vs.Y / 2)
            fovCircle.Radius = settings.aimFov
            fovCircle.Visible = true
        else
            fovCircle.Visible = false
        end
    end

    local hasMouseMove = type(mousemoverel) == "function"
    local AIM_MAX_STEP = 60

    -- [[ Menu-aware input blocking (v1.0.4) ]]
    -- The UI library never sinks input, so clicks on the open menu also
    -- reached the game (firing weapons, etc.). While the menu is open and the
    -- cursor is over it, sink MB1/MB2/Touch at high priority via
    -- ContextActionService. This only flips gameProcessedEvent for the game's
    -- InputBegan handlers; the menu itself reads raw UserInputService input
    -- and keeps working.
    local ContextActionService = game:GetService("ContextActionService")
    local inputBlockBound = false
    local menuOpen = false

    -- [[ Game-native gun disable (v1.0.5) ]]
    -- The CAS sink alone could not stop the gun: the game's Shooter sets
    -- tool.shooting through its own CAS action no matter what. But the game's
    -- own fire gate (Shooter in ReplicatedStorage.Client.Wanted.Objects.
    -- ClientTool.Components.Tools.Guns.Shooter) returns early without firing
    -- while LocalPlayer:GetAttribute("gunsDisabled") is truthy -- this is the
    -- exact attribute the game itself uses to disable guns in its own menus.
    -- While our menu is open we set it; on close/destroy we restore whatever
    -- value was there before, so we never fight the game's own state.
    local savedGunsDisabled = nil
    local gunsDisabledByUs = false

    local function setGunsDisabled(v)
        if v then
            if not gunsDisabledByUs then
                savedGunsDisabled = nil
                pcall(function() savedGunsDisabled = localPlayer:GetAttribute("gunsDisabled") end)
                gunsDisabledByUs = true
            end
            pcall(function() localPlayer:SetAttribute("gunsDisabled", true) end)
        else
            if gunsDisabledByUs then
                gunsDisabledByUs = false
                local prev = savedGunsDisabled
                savedGunsDisabled = nil
                pcall(function()
                    if prev then
                        localPlayer:SetAttribute("gunsDisabled", prev)
                    else
                        localPlayer:SetAttribute("gunsDisabled", nil)
                    end
                end)
            end
        end
    end

    local function menuRect()
        local ok, pos, size = pcall(function() return Window.pos, Window.size end)
        if not ok or typeof(pos) ~= "Vector2" or typeof(size) ~= "Vector2" then
            return nil
        end
        return pos.X, pos.Y, size.X, size.Y
    end

    local function mouseOverMenu()
        local x, y, w, h = menuRect()
        if not x then return false end
        local m = nil
        pcall(function() m = UserInputService:GetMouseLocation() end)
        if not m then return false end
        local pad = 10
        return m.X >= x - pad and m.Y >= y - pad and m.X <= x + w + pad and m.Y <= y + h + pad
    end

    local function setInputBlock(on)
        if on == inputBlockBound then return end
        inputBlockBound = on
        if on then
            pcall(function()
                ContextActionService:BindActionAtPriority("RAVEN_WANTED_MENU_BLOCK",
                    function(_, state, input)
                        if state == Enum.UserInputState.Begin then
                            return Enum.ContextActionResult.Sink
                        end
                        -- MouseWheel only arrives as Change; sinking it stops the
                        -- camera zoom while the menu keeps its own scroll (the UI
                        -- lib reads raw InputChanged and ignores the processed
                        -- flag). Other inputs keep passing on End/Change so the
                        -- game always sees button releases.
                        if state == Enum.UserInputState.Change
                            and input
                            and input.UserInputType == Enum.UserInputType.MouseWheel then
                            return Enum.ContextActionResult.Sink
                        end
                        return Enum.ContextActionResult.Pass
                    end,
                    false, 3000,
                    Enum.UserInputType.MouseButton1,
                    Enum.UserInputType.MouseButton2,
                    Enum.UserInputType.Touch,
                    Enum.UserInputType.MouseWheel)
            end)
        else
            pcall(function()
                ContextActionService:UnbindAction("RAVEN_WANTED_MENU_BLOCK")
            end)
        end
    end

    local function updateMenuState()
        local open = false
        pcall(function() open = Window.visible == true end)
        if open ~= menuOpen then
            menuOpen = open
            setGunsDisabled(open) -- game-native gun disable while menu is open
        end
        setInputBlock(open and mouseOverMenu())
    end

    local function updateAimbot()
        if not settings.aimbot then return end
        if menuOpen then return end -- don't fight the user while configuring
        local aiming = false
        pcall(function()
            aiming = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        end)
        if not aiming or not hasMouseMove then return end
        local target = getAimTarget()
        if target then
            local v, on = camera:WorldToViewportPoint(target.Position)
            if on and v.Z > 0 then
                local center = camera.ViewportSize / 2
                local dx = math.clamp((v.X - center.X) * settings.aimSmooth, -AIM_MAX_STEP, AIM_MAX_STEP)
                local dy = math.clamp((v.Y - center.Y) * settings.aimSmooth, -AIM_MAX_STEP, AIM_MAX_STEP)
                if math.abs(dx) > 0.5 or math.abs(dy) > 0.5 then
                    pcall(mousemoverel, dx, dy)
                end
            end
        end
    end

    local tpStatus = "idle"
    local tpLabel = nil
    local robLabel = nil

    local function refreshTpLabel()
        if tpLabel ~= nil then
            pcall(function()
                if type(tpLabel.SetText) == "function" then
                    tpLabel:SetText("TP: " .. tpStatus)
                elseif type(tpLabel.Update) == "function" then
                    tpLabel:Update("TP: " .. tpStatus)
                end
            end)
        end
    end

    -- [[ UI ]]
    local VisualsTab = Window:CreateTab("Visuals", 4483362458)
    trackSection(VisualsTab, "Player ESP")

    VisualsTab:CreateToggle({
        Name = "ESP Enabled",
        CurrentValue = true,
        Flag = "WTD_EspEnabled",
        Callback = function(v) settings.espEnabled = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Box",
        CurrentValue = true,
        Flag = "WTD_BoxEsp",
        Callback = function(v) settings.boxEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Name + Distance",
        CurrentValue = true,
        Flag = "WTD_NameEsp",
        Callback = function(v)
            settings.nameEsp = v
            settings.distanceEsp = v
        end,
    })
    VisualsTab:CreateToggle({
        Name = "Health Bar",
        CurrentValue = true,
        Flag = "WTD_HealthEsp",
        Callback = function(v) settings.healthEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Team Colors",
        CurrentValue = true,
        Flag = "WTD_TeamColors",
        Callback = function(v) settings.teamColors = v end,
    })
    VisualsTab:CreateSlider({
        Name = "Max Distance",
        Range = { 100, 5000 },
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 2000,
        Flag = "WTD_MaxDistance",
        Callback = function(v) settings.maxDistance = v end,
    })

    trackSection(VisualsTab, "World ESP")
    VisualsTab:CreateToggle({
        Name = "ATM ESP",
        CurrentValue = true,
        Flag = "WTD_AtmEsp",
        Callback = function(v) settings.atmEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "NPC / Bot ESP",
        CurrentValue = true,
        Flag = "WTD_NpcEsp",
        Callback = function(v) settings.npcEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Vehicle ESP",
        CurrentValue = true,
        Flag = "WTD_VehicleEsp",
        Callback = function(v) settings.vehicleEsp = v end,
    })
    VisualsTab:CreateButton({
        Name = "Teleport to Nearest ATM",
        Callback = function()
            local ok, res = pcall(teleportToNearestAtm)
            tpStatus = ok and tostring(res) or "error"
            refreshTpLabel()
        end,
    })

    local HudTab = Window:CreateTab("HUD", 4483362458)
    trackSection(HudTab, "Wanted HUD")
    HudTab:CreateToggle({
        Name = "HUD Enabled",
        CurrentValue = true,
        Flag = "WTD_HudEnabled",
        Callback = function(v) settings.hudEnabled = v end,
    })
    HudTab:CreateToggle({
        Name = "Show Cash",
        CurrentValue = true,
        Flag = "WTD_ShowCash",
        Callback = function(v) settings.showCash = v end,
    })
    HudTab:CreateToggle({
        Name = "Show Bounty",
        CurrentValue = true,
        Flag = "WTD_ShowBounty",
        Callback = function(v) settings.showBounty = v end,
    })

    local CombatTab = Window:CreateTab("Combat", 4483362458)
    trackSection(CombatTab, "Aimbot (Camera Lock)")
    CombatTab:CreateToggle({
        Name = "Aimbot Enabled",
        CurrentValue = false,
        Flag = "WTD_Aimbot",
        Callback = function(v) settings.aimbot = v end,
    })
    CombatTab:CreateSlider({
        Name = "Aim Max Distance",
        Range = { 50, 2000 },
        Increment = 25,
        Suffix = " studs",
        CurrentValue = 500,
        Flag = "WTD_AimMaxDist",
        Callback = function(v) settings.aimMaxDist = v end,
    })
    CombatTab:CreateSlider({
        Name = "Aim FOV",
        Range = { 50, 400 },
        Increment = 10,
        Suffix = " px",
        CurrentValue = 150,
        Flag = "WTD_AimFov",
        Callback = function(v) settings.aimFov = v end,
    })
    pcall(function()
        if type(CombatTab.CreateLabel) == "function" then
            CombatTab:CreateLabel("Hold RIGHT MOUSE to lock camera on nearest enemy")
        end
    end)
    local RobberyTab = Window:CreateTab("Robbery", 4483362458)
    trackSection(RobberyTab, "Auto Rob")
    RobberyTab:CreateToggle({
        Name = "Auto-Rob ATMs",
        CurrentValue = false,
        Flag = "WTD_AutoRob",
        Callback = function(v) setAutoRob(v) end,
    })
    RobberyTab:CreateToggle({
        Name = "Auto-Sell at Pawn (bag full)",
        CurrentValue = true,
        Flag = "WTD_AutoSell",
        Callback = function(v) settings.autoSell = v end,
    })
    RobberyTab:CreateToggle({
        Name = "Cash ESP ($ values)",
        CurrentValue = true,
        Flag = "WTD_CashEsp",
        Callback = function(v) settings.cashEsp = v end,
    })
    RobberyTab:CreateToggle({
        Name = "Auto-Rob Loot (shops)",
        CurrentValue = true,
        Flag = "WTD_AutoLoot",
        Callback = function(v) settings.autoLoot = v end,
    })
    RobberyTab:CreateToggle({
        Name = "Loot ESP",
        CurrentValue = true,
        Flag = "WTD_LootEsp",
        Callback = function(v) settings.lootEsp = v end,
    })
    pcall(function()
        if type(RobberyTab.CreateLabel) == "function" then
            robLabel = RobberyTab:CreateLabel("Rob: idle")
        end
    end)
    task.spawn(function()
        while running do
            pcall(function()
                if robLabel ~= nil then
                    if type(robLabel.SetText) == "function" then
                        robLabel:SetText("Rob: " .. robStatus)
                    elseif type(robLabel.Update) == "function" then
                        robLabel:Update("Rob: " .. robStatus)
                    end
                end
            end)
            task.wait(0.5)
        end
    end)

    pcall(function()
        if type(VisualsTab.CreateLabel) == "function" then
            tpLabel = VisualsTab:CreateLabel("TP: idle")
        end
    end)

    pcall(function()
        if type(Window.SortTabs) == "function" then
            Window:SortTabs({ "Visuals", "HUD", "Combat", "Robbery" })
        end
    end)

    -- [[ Connections ]]
    table.insert(connections, RunService.RenderStepped:Connect(function()
        pcall(updateMenuState)
        pcall(updatePlayerEsp)
        pcall(updateNpcEsp)
        pcall(updateVehicleEsp)
        pcall(updateAtmEsp)
        pcall(updateCashEsp)
        pcall(updateLootEsp)
        pcall(updateFovCircle)
        pcall(updateAimbot)
    end))
    table.insert(connections, Players.PlayerRemoving:Connect(function(p)
        destroyEntry(p)
    end))

    task.spawn(function()
        while running do
            pcall(updateHud)
            task.wait(0.5)
        end
    end)

    local function destroy()
        running = false
        pcall(function() setInputBlock(false) end)
        pcall(function() setGunsDisabled(false) end)
        for _, c in ipairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        pcall(removeUiSections)
        if fovCircle ~= nil then pcall(function() fovCircle:Remove() end) end
        for p in pairs(espCache) do destroyEntry(p) end
        espCache = {}
        for _, cache in ipairs({ npcCache, vehCache }) do
            for _, m in pairs(cache) do
                if m ~= nil then pcall(function() m:Remove() end) end
            end
        end
        for k, m in pairs(atmCache) do
            if m ~= nil then
                pcall(function() m:Remove() end)
            end
        end
        for _, cache in ipairs({ lootCache, cashCache }) do
            for _, m in pairs(cache) do
                if m ~= nil then pcall(function() m:Remove() end) end
            end
        end
        if hudText ~= nil then pcall(function() hudText:Remove() end) end
    end

    environment.__RAVEN_WANTED = { Destroy = destroy }

    -- Test hook (only when loaded with ctx.__test); does not affect hub usage
    if type(ctx) == "table" and ctx.__test == true then
        environment.__RAVEN_WANTED._test = {
            settings = settings,
            atmCount = function() return #atmList end,
            espPlayers = function()
                local n = 0
                for _ in pairs(espCache) do n = n + 1 end
                return n
            end,
            hud = function() return hudText and hudText.Text or nil end,
            hudVisible = function() return hudText and hudText.Visible or false end,
            aimTarget = function()
                local t = getAimTarget()
                return t and t.Parent and t.Parent.Name or nil
            end,
            fovVisible = function() return fovCircle and fovCircle.Visible or false end,
            hasMouseMove = function() return hasMouseMove end,
            drawZ = function()
                local ez = nil
                for _, e in pairs(espCache) do
                    if e.box then ez = e.box.ZIndex break end
                end
                return {
                    esp = ez,
                    hud = (hudText and hudText.ZIndex or nil),
                    fov = (fovCircle and fovCircle.ZIndex or nil),
                }
            end,
            menuOpen = function() return menuOpen end,
            robStatus = function() return robStatus end,
            cashCount = function() scanCash() return #cashList end,
            topCash = function() scanCash() return cashList[1] and cashList[1].value or 0 end,
            bagFull = function() return isBagFull() end,
            setAutoRob = function(v) setAutoRob(v) end,
            lootCount = function() scanLoot() return #lootList end,
            brokenAtms = function()
                local n = 0
                for _, a in ipairs(atmList) do
                    if isAtmBroken(a.model) then n = n + 1 end
                end
                return n
            end,
            setAutoRob = function(v) setAutoRob(v) end,
            blockBound = function() return inputBlockBound end,
            setBlock = function(on) setInputBlock(on) end,
            espTeamColors = function()
                local rows = {}
                for p, e in pairs(espCache) do
                    if e.box and e.box.Visible then
                        local c = e.box.Color
                        table.insert(rows, { name = p.Name,
                            team = tostring(p:GetAttribute("currentTeam")),
                            box = string.format("%d,%d,%d", math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5)),
                            text = e.name and e.name.Text or nil })
                    end
                    if #rows >= 12 then break end
                end
                return rows
            end,
        }
    end

    return environment.__RAVEN_WANTED
end
