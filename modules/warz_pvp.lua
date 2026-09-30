-- ============================================================
--   RAVEN HUB  |  WarZPVP
--   UniverseId: 10763998990  |  PlaceId: 135187059974536
--   Player ESP (Box/Name/Distance/HP/Weapon) + Loot ESP + Boss ESP + Aimbot (mouse-driven)
--   v1.4.0 — loot ESP (WarzLoot), boss ESP + spawn alert (WarzBoss), skeleton render fix
--   Read-only visuals + mouse-driven aim.
--   WarZ notes: FFA (no Teams), skip dead via WarzDead attribute,
--   character = R15 (Head/HumanoidRootPart), WarzHitboxes folder present.
-- ============================================================

return function(Window, ctx)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")
    local ContextActionService = game:GetService("ContextActionService")

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    -- Clean up previous instance (ghost UI prevention)
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_WARZPVP) == "table"
        and type(environment.__RAVEN_WARZPVP.Destroy) == "function" then
        pcall(environment.__RAVEN_WARZPVP.Destroy)
    end
    pcall(function()
        if type(environment.__RAVEN_WINDOW) == "table"
            and type(environment.__RAVEN_WINDOW.Destroy) == "function" then
            environment.__RAVEN_WINDOW.Destroy()
        end
    end)
    environment.RAVEN_WARZPVP_VER = "1.4.0"

    local running = true
    local connections = {}
    local uiSections = {} -- sections this module created (for clean reload)
    local espCache = {}

    local settings = {
        espEnabled = true,
        boxEsp = true,
        nameEsp = true,
        distanceEsp = true,
        healthEsp = true,
        weaponEsp = true,
        skeletonEsp = true,
        selfEsp = false,
        maxDistance = 2000,
        lootEsp = true,
        lootMaxDistance = 1500,
        lootCategory = "All",
        bossEsp = true,
        bossAlert = true,
        aimbot = false,
        aimMaxDist = 500,
        aimFov = 150,
        aimResponse = 0.35,
        aimKeyName = "MouseButton2",
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
        -- Visuals/Combat are owned by this module. Use DrawingUI's native
        -- Clear() so the old Drawing objects are actually removed.
        local tabs = {}
        for _, sec in ipairs(uiSections) do
            if sec and sec.tab then tabs[sec.tab] = true end
        end
        for tab in pairs(tabs) do
            if type(tab.Clear) == "function" then
                pcall(function() tab:Clear() end)
            end
        end
        table.clear(uiSections)
    end

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        if ok and obj then
            -- executor default ZIndex is 1, same as the menu chassis,
            -- so ESP used to render through the menu. Keep every module
            -- drawing strictly below the menu.
            pcall(function() obj.ZIndex = 0 end)
        end
        return (ok and obj) or nil
    end

    local function getHealthColor(ratio)
        return Color3.fromHSV(math.clamp(ratio, 0, 1) * 0.33, 0.9, 1)
    end

    -- FFA game: no teams, single ESP color.
    local ESP_COLOR = Color3.fromRGB(255, 200, 60)

    -- Pose-following R15 skeleton. Each segment follows two different points
    -- along the same animated body part (or a short joint branch), avoiding
    -- both zero-length Motor6D attachment pairs and stiff part-center chains.
    local SKELETON_BONES = {
        { "Head", nil, "Head", "NeckRigAttachment" },
        { "UpperTorso", "NeckRigAttachment", "UpperTorso", "WaistRigAttachment" },
        { "UpperTorso", "NeckRigAttachment", "UpperTorso", "LeftShoulderRigAttachment" },
        { "LeftUpperArm", "LeftShoulderRigAttachment", "LeftUpperArm", "LeftElbowRigAttachment" },
        { "LeftLowerArm", "LeftElbowRigAttachment", "LeftLowerArm", "LeftWristRigAttachment" },
        { "LeftHand", "LeftWristRigAttachment", "LeftHand", nil },
        { "UpperTorso", "NeckRigAttachment", "UpperTorso", "RightShoulderRigAttachment" },
        { "RightUpperArm", "RightShoulderRigAttachment", "RightUpperArm", "RightElbowRigAttachment" },
        { "RightLowerArm", "RightElbowRigAttachment", "RightLowerArm", "RightWristRigAttachment" },
        { "RightHand", "RightWristRigAttachment", "RightHand", nil },
        { "LowerTorso", "WaistRigAttachment", "LowerTorso", "LeftHipRigAttachment" },
        { "LeftUpperLeg", "LeftHipRigAttachment", "LeftUpperLeg", "LeftKneeRigAttachment" },
        { "LeftLowerLeg", "LeftKneeRigAttachment", "LeftLowerLeg", "LeftAnkleRigAttachment" },
        { "LeftFoot", "LeftAnkleRigAttachment", "LeftFoot", nil },
        { "LowerTorso", "WaistRigAttachment", "LowerTorso", "RightHipRigAttachment" },
        { "RightUpperLeg", "RightHipRigAttachment", "RightUpperLeg", "RightKneeRigAttachment" },
        { "RightLowerLeg", "RightKneeRigAttachment", "RightLowerLeg", "RightAnkleRigAttachment" },
        { "RightFoot", "RightAnkleRigAttachment", "RightFoot", nil },
    }

    local function skeletonPoint(part, attachmentName)
        if attachmentName then
            local attachment = part:FindFirstChild(attachmentName)
            if attachment and attachment:IsA("Attachment") then
                return attachment.WorldPosition
            end
        end
        return part.Position
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
            e.box.Color = ESP_COLOR
            e.box.Visible = false
        end
        if e.name then
            e.name.Size = 14
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
        e.bones = {}
        e.boneParts = {}
        e.boneCharacter = nil
        e.boneRetryAt = 0
        e.boneReady = false
        espCache[p] = e
        return e
    end

    local function ensureSkeletonDrawings(e)
        if e.bones[1] then return end
        for i = 1, #SKELETON_BONES do
            local ln = safeDrawing("Line")
            if ln then
                ln.Thickness = 2
                ln.Transparency = 1
                ln.Color = ESP_COLOR
                ln.Visible = false
                e.bones[i] = ln
            end
        end
    end

    local function resolveSkeletonParts(e, ch)
        local now = os.clock()
        if e.boneCharacter == ch and e.boneReady then return end
        if e.boneCharacter == ch and now < e.boneRetryAt then return end
        e.boneCharacter = ch
        e.boneRetryAt = now + 0.5
        e.boneReady = true
        for i, b in ipairs(SKELETON_BONES) do
            local pa = ch:FindFirstChild(b[1])
            local pb = ch:FindFirstChild(b[3])
            if pa and pb then
                e.boneParts[i] = { pa, b[2], pb, b[4] }
            else
                e.boneParts[i] = false
                e.boneReady = false
            end
        end
    end

    local function hideEntry(e)
        for _, d in pairs({ e.box, e.name, e.hpBack, e.hpFill }) do
            if d then pcall(function() d.Visible = false end) end
        end
        for _, line in pairs(e.bones or {}) do
            if line then pcall(function() line.Visible = false end) end
        end
    end

    local function destroyEntry(p)
        local e = espCache[p]
        if not e then return end
        for _, d in pairs({ e.box, e.name, e.hpBack, e.hpFill }) do
            if d then pcall(function() d:Remove() end) end
        end
        for _, line in pairs(e.bones or {}) do
            if line then pcall(function() line:Remove() end) end
        end
        espCache[p] = nil
    end

    local function isAlive(ch)
        if not ch then return false end
        if ch:GetAttribute("WarzDead") == true then return false end
        local hum = ch:FindFirstChildOfClass("Humanoid")
        return hum ~= nil and hum.Health > 0
    end

    local function updatePlayerEsp()
        if not settings.espEnabled then
            for _, e in pairs(espCache) do hideEntry(e) end
            return
        end
        local camPos = camera.CFrame.Position
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer or settings.selfEsp then
                local e = getEntry(p)
                local ch = p.Character
                local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
                if hrp and isAlive(ch) then
                    local dist = (hrp.Position - camPos).Magnitude
                    if dist <= settings.maxDistance then
                        local top, topOn = camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 3, 0))
                        local bot, botOn = camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 3, 0))
                        if topOn and botOn and top.Z > 0 and bot.Z > 0 then
                            local h = math.abs(top.Y - bot.Y)
                            local w = h * 0.55
                            if settings.boxEsp and e.box then
                                e.box.Size = Vector2.new(w, h)
                                e.box.Position = Vector2.new(top.X - w / 2, top.Y)
                                e.box.Visible = true
                            elseif e.box then
                                e.box.Visible = false
                            end
                            if (settings.nameEsp or settings.distanceEsp) and e.name then
                                local label = p.Name
                                if settings.weaponEsp then
                                    local wpn = ch:GetAttribute("HeldWeapon")
                                    if type(wpn) == "string" and wpn ~= "" then
                                        label = label .. " [" .. wpn .. "]"
                                    end
                                end
                                if settings.distanceEsp then
                                    label = label .. " " .. math.floor(dist) .. "m"
                                end
                                e.name.Text = label
                                e.name.Position = Vector2.new(top.X, top.Y - 18)
                                e.name.Visible = true
                            elseif e.name then
                                e.name.Visible = false
                            end
                            if settings.healthEsp and e.hpBack and e.hpFill then
                                local hum = ch:FindFirstChildOfClass("Humanoid")
                                local ratio = hum and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
                                local bw = 4
                                e.hpBack.Size = Vector2.new(bw, h)
                                e.hpBack.Position = Vector2.new(top.X - w / 2 - bw - 2, top.Y)
                                e.hpBack.Visible = true
                                e.hpFill.Size = Vector2.new(bw, h * ratio)
                                e.hpFill.Position = Vector2.new(top.X - w / 2 - bw - 2, top.Y + h * (1 - ratio))
                                e.hpFill.Color = getHealthColor(ratio)
                                e.hpFill.Visible = true
                            else
                                if e.hpBack then e.hpBack.Visible = false end
                                if e.hpFill then e.hpFill.Visible = false end
                            end
                            if settings.skeletonEsp then
                                -- Create skeleton drawings only for visible players.
                                -- If a character was only partially replicated when first seen,
                                -- retry missing body parts every 0.5s instead of caching failure forever.
                                ensureSkeletonDrawings(e)
                                resolveSkeletonParts(e, ch)
                                for i = 1, #SKELETON_BONES do
                                    local bp = e.boneParts[i]
                                    local ln = e.bones[i]
                                    if ln then
                                        if bp and bp[1].Parent and bp[3].Parent then
                                            local va, ona = camera:WorldToViewportPoint(
                                                skeletonPoint(bp[1], bp[2])
                                            )
                                            local vb, onb = camera:WorldToViewportPoint(
                                                skeletonPoint(bp[3], bp[4])
                                            )
                                            if ona and onb and va.Z > 0 and vb.Z > 0 then
                                                ln.From = Vector2.new(va.X, va.Y)
                                                ln.To = Vector2.new(vb.X, vb.Y)
                                                ln.Visible = true
                                            else
                                                ln.Visible = false
                                            end
                                        else
                                            e.boneReady = false
                                            ln.Visible = false
                                        end
                                    end
                                end
                            else
                                for _, ln in pairs(e.bones) do
                                    if ln then ln.Visible = false end
                                end
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
            elseif espCache[p] then
                hideEntry(espCache[p])
            end
        end
    end

    -- [[ Loot ESP: read-only labels for drops under Workspace.WarzLoot ]]
    -- Loot models look like "Loot_ARMOR_Rebel_Heavy" / "Loot_HEADHELMET"
    -- with PrimaryPart = "LootMarker". No remotes, no hooks — Drawing only.
    local lootCache = {} -- [model] = { text = drawing }
    local lootCategories = { "All" }
    local lootCategoryDropdown = nil

    local function parseLootName(modelName)
        local rest = modelName
        if rest:sub(1, 5) == "Loot_" then
            rest = rest:sub(6)
        end
        local parts = {}
        for tok in rest:gmatch("[^_]+") do
            table.insert(parts, tok)
        end
        local category = parts[1] or rest
        local itemName = category
        if #parts > 1 then
            itemName = table.concat(parts, " ", 2)
        end
        return category, itemName
    end

    local function lootAnchor(model)
        -- PrimaryPart -> "LootMarker" child -> first BasePart fallback.
        local pp = model.PrimaryPart
        if pp then return pp end
        local marker = model:FindFirstChild("LootMarker")
        if marker then return marker end
        for _, d in ipairs(model:GetChildren()) do
            if d:IsA("BasePart") then return d end
        end
        return nil
    end

    local function lootAnchorPos(anchor)
        if anchor == nil then return nil end
        if anchor:IsA("BasePart") then return anchor.Position end
        return anchor.WorldPosition
    end

    local function lootCategoryAllowed(category)
        return settings.lootCategory == "All" or settings.lootCategory == category
    end

    local function noteLootCategory(category)
        for _, c in ipairs(lootCategories) do
            if c == category then return end
        end
        table.insert(lootCategories, category)
        if lootCategoryDropdown and type(lootCategoryDropdown.SetOptions) == "function" then
            pcall(function() lootCategoryDropdown:SetOptions(lootCategories) end)
        end
    end

    local function updateLootEsp()
        if not settings.lootEsp then
            for _, e in pairs(lootCache) do
                if e.text then pcall(function() e.text.Visible = false end) end
            end
            return
        end
        local folder = Workspace:FindFirstChild("WarzLoot")
        local seen = {}
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") then
                    local anchor = lootAnchor(model)
                    local apos = lootAnchorPos(anchor)
                    if apos then
                        local dist = (apos - camera.CFrame.Position).Magnitude
                        if dist <= settings.lootMaxDistance then
                            local category, itemName = parseLootName(model.Name)
                            noteLootCategory(category)
                            seen[model] = true
                            local e = lootCache[model]
                            if not e then
                                local t = safeDrawing("Text")
                                if t then
                                    t.Size = 13
                                    t.Center = true
                                    t.Outline = true
                                    t.Color = Color3.fromRGB(255, 255, 255)
                                end
                                e = { text = t }
                                lootCache[model] = e
                            end
                            if e.text then
                                if lootCategoryAllowed(category) then
                                    local v, on = camera:WorldToViewportPoint(apos)
                                    if on and v.Z > 0 then
                                        e.text.Visible = true
                                        e.text.Position = Vector2.new(v.X, v.Y)
                                        e.text.Text = string.format("%s [%s] %dm",
                                            itemName, category, math.floor(dist + 0.5))
                                    else
                                        e.text.Visible = false
                                    end
                                else
                                    e.text.Visible = false
                                end
                            end
                        else
                            local e = lootCache[model]
                            if e and e.text then pcall(function() e.text.Visible = false end) end
                        end
                    end
                end
            end
        end
        -- Picked-up / recycled / reparented loot: remove its drawing.
        for model, e in pairs(lootCache) do
            if not seen[model] then
                if e.text then pcall(function() e.text:Remove() end) end
                lootCache[model] = nil
            end
        end
    end

    -- [[ Boss ESP: read-only box + name/distance + HP bar, spawn alert ]]
    -- Boss lives under Workspace.WarzBoss (observed: "SuperZombie", 5000 HP).
    local bossDraw = nil
    local bossAlertText = nil
    local bossWasPresent = false
    local bossAlertUntil = 0

    local function getBossModel()
        local folder = Workspace:FindFirstChild("WarzBoss")
        if not folder then return nil end
        local named = folder:FindFirstChild("SuperZombie")
        if named and named:IsA("Model") then return named end
        for _, c in ipairs(folder:GetChildren()) do
            if c:IsA("Model") and c:FindFirstChildOfClass("Humanoid") then
                return c
            end
        end
        return nil
    end

    local function ensureBossDraw()
        if bossDraw then return bossDraw end
        local box = safeDrawing("Square")
        if box then
            box.Thickness = 2
            box.Filled = false
            box.Color = Color3.fromRGB(255, 60, 60)
        end
        local name = safeDrawing("Text")
        if name then
            name.Size = 14
            name.Center = true
            name.Outline = true
            name.Color = Color3.fromRGB(255, 120, 120)
        end
        local hpBg = safeDrawing("Square")
        if hpBg then
            hpBg.Filled = true
            hpBg.Color = Color3.fromRGB(20, 20, 20)
        end
        local hpFill = safeDrawing("Square")
        if hpFill then
            hpFill.Filled = true
            hpFill.Color = Color3.fromRGB(60, 220, 90)
        end
        bossDraw = { box = box, name = name, hpBg = hpBg, hpFill = hpFill }
        return bossDraw
    end

    local function hideBossEsp()
        if bossDraw then
            for _, d in pairs(bossDraw) do
                if d then pcall(function() d.Visible = false end) end
            end
        end
    end

    local function updateBossEsp()
        if bossAlertText then
            local showAlert = settings.bossAlert and os.clock() < bossAlertUntil
            pcall(function() bossAlertText.Visible = showAlert end)
        end
        local model = settings.bossEsp and getBossModel() or nil
        if not model or not isAlive(model) then
            hideBossEsp()
            bossWasPresent = false
            return
        end
        if not bossWasPresent then
            bossWasPresent = true
            if settings.bossAlert then
                if not bossAlertText then
                    local t = safeDrawing("Text")
                    if t then
                        t.Size = 22
                        t.Center = true
                        t.Outline = true
                        t.Color = Color3.fromRGB(255, 80, 80)
                        local vs = camera.ViewportSize
                        t.Position = Vector2.new(vs.X / 2, vs.Y * 0.25)
                    end
                    bossAlertText = t
                end
                if bossAlertText then
                    bossAlertText.Text = "!! BOSS SPAWNED !!"
                    bossAlertUntil = os.clock() + 5
                    pcall(function() bossAlertText.Visible = true end)
                end
            end
        end
        local d = ensureBossDraw()
        local hrp = model:FindFirstChild("HumanoidRootPart")
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or not hum.MaxHealth or hum.MaxHealth <= 0 then
            hideBossEsp()
            return
        end
        local dist = (hrp.Position - camera.CFrame.Position).Magnitude
        local top, topOn = camera:WorldToViewportPoint(hrp.Position + Vector3.new(0, 4, 0))
        local bot, botOn = camera:WorldToViewportPoint(hrp.Position - Vector3.new(0, 4, 0))
        if not (topOn and botOn and top.Z > 0 and bot.Z > 0) then
            hideBossEsp()
            return
        end
        local h = math.abs(top.Y - bot.Y)
        if h < 4 then
            hideBossEsp()
            return
        end
        local w = h * 0.7
        local x0, y0 = top.X - w / 2, top.Y
        if d.box then
            d.box.Visible = true
            d.box.Size = Vector2.new(w, h)
            d.box.Position = Vector2.new(x0, y0)
        end
        if d.name then
            d.name.Visible = true
            d.name.Position = Vector2.new(top.X, y0 - 18)
            d.name.Text = string.format("%s %dm", model.Name, math.floor(dist + 0.5))
        end
        local frac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        if d.hpBg then
            d.hpBg.Visible = true
            d.hpBg.Position = Vector2.new(x0 - 6, y0)
            d.hpBg.Size = Vector2.new(4, h)
        end
        if d.hpFill then
            d.hpFill.Visible = true
            local fhh = h * frac
            d.hpFill.Position = Vector2.new(x0 - 6, y0 + h - fhh)
            d.hpFill.Size = Vector2.new(4, math.max(fhh, 1))
        end
    end

    -- [[ Aimbot: mouse-driven (no hitbox edits, no hooks, no remotes) ]]
    -- Drives the real mouse via mousemoverel() so the game's own camera
    -- turns toward the target. Target = head closest to crosshair within FOV.
    -- Target lock: once aiming starts, stick to the locked player until the
    -- lock goes invalid (dead / respawned / left FOV / out of range). Without
    -- this the "nearest head" scan flickers between close targets and the
    -- crosshair whips back and forth at high response.
    local aimLockPlayer = nil
    local aimHeld = false
    local capturingAimKey = false -- true while the custom aim-key button listens

    local function scanAimTarget()
        local best, bestP, bestPx = nil, nil, settings.aimFov
        local center = camera.ViewportSize / 2
        local camPos = camera.CFrame.Position
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                local ch = p.Character
                local head = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
                if head and isAlive(ch) then
                    if (head.Position - camPos).Magnitude <= settings.aimMaxDist then
                        local v, on = camera:WorldToViewportPoint(head.Position)
                        if on and v.Z > 0 then
                            local px = (Vector2.new(v.X, v.Y) - center).Magnitude
                            if px < bestPx then
                                best, bestP, bestPx = head, p, px
                            end
                        end
                    end
                end
            end
        end
        return best, bestP
    end

    local function getAimTarget()
        local center = camera.ViewportSize / 2
        local camPos = camera.CFrame.Position
        local p = aimLockPlayer
        if p ~= nil then
            local ch = p.Character
            local head = ch and (ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
            if head and isAlive(ch) then
                if (head.Position - camPos).Magnitude <= settings.aimMaxDist then
                    local v, on = camera:WorldToViewportPoint(head.Position)
                    -- Hysteresis: keep the lock a bit past the FOV edge so it
                    -- doesn't drop/reacquire every frame at the boundary.
                    if on and v.Z > 0
                        and (Vector2.new(v.X, v.Y) - center).Magnitude <= settings.aimFov * 1.25 then
                        return head
                    end
                end
            end
            aimLockPlayer = nil
        end
        local best, bestP = scanAimTarget()
        aimLockPlayer = bestP
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

    -- [[ Menu-aware input blocking ]]
    -- The UI library never sinks input, so clicks on the open menu also
    -- reached the game. While the menu is open and the cursor is over it,
    -- sink MB1/MB2/Touch at high priority via ContextActionService.
    local inputBlockBound = false
    local menuOpen = false

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
                ContextActionService:BindActionAtPriority("RAVEN_WARZPVP_MENU_BLOCK",
                    function(_, state, input)
                        if state == Enum.UserInputState.Begin then
                            return Enum.ContextActionResult.Sink
                        end
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
                ContextActionService:UnbindAction("RAVEN_WARZPVP_MENU_BLOCK")
            end)
        end
    end

    local function updateMenuState()
        local open = false
        pcall(function() open = Window.visible == true end)
        if open ~= menuOpen then
            menuOpen = open
        end
        -- While a keybind is listening for its new key, drop the menu
        -- input block so mouse buttons can be captured for rebinding.
        local listening = capturingAimKey
        if not listening then
            pcall(function() listening = Window.activeKeybindListener ~= nil end)
        end
        setInputBlock(open and mouseOverMenu() and not listening)
    end

    -- Resolve a bindable name from an input object. Keyboard keys arrive via
    -- KeyCode; mouse buttons arrive with KeyCode == Unknown and are
    -- identified by UserInputType instead.
    local function resolveInputName(input)
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            return input.KeyCode.Name
        end
        local uit = input.UserInputType
        if uit == Enum.UserInputType.MouseButton1 then
            return "MouseButton1"
        elseif uit == Enum.UserInputType.MouseButton2 then
            return "MouseButton2"
        elseif uit == Enum.UserInputType.MouseButton3 then
            return "MouseButton3"
        end
        return nil
    end

    local function inputMatchesAimKey(input)
        return resolveInputName(input) == settings.aimKeyName
    end

    local function updateAimbot(dt)
        if not settings.aimbot then aimHeld, aimLockPlayer = false, nil return end
        if capturingAimKey then aimHeld, aimLockPlayer = false, nil return end
        if menuOpen and mouseOverMenu() then aimLockPlayer = nil return end
        if not aimHeld or not hasMouseMove then aimLockPlayer = nil return end
        local target = getAimTarget()
        if target then
            local v, on = camera:WorldToViewportPoint(target.Position)
            if on and v.Z > 0 then
                local center = camera.ViewportSize / 2
                local ox, oy = v.X - center.X, v.Y - center.Y
                -- Deadzone on the raw offset: stops the limit-cycle jitter
                -- that made high response feel "crazy" near the target.
                if ox * ox + oy * oy > 4 then
                    -- Frame-rate independent exponential approach; response
                    -- is the fraction of remaining distance closed per frame
                    -- at 60 fps, so it can never overshoot on its own.
                    local resp = math.clamp(settings.aimResponse, 0.01, 1)
                    local t = 1 - math.pow(1 - resp, (dt or 1 / 60) * 60)
                    local dx = math.clamp(ox * t, -AIM_MAX_STEP, AIM_MAX_STEP)
                    local dy = math.clamp(oy * t, -AIM_MAX_STEP, AIM_MAX_STEP)
                    pcall(mousemoverel, dx, dy)
                end
            end
        end
    end

    -- [[ UI ]]
    local VisualsTab = Window:CreateTab("Visuals", 4483362458)
    trackSection(VisualsTab, "Player ESP")

    VisualsTab:CreateToggle({
        Name = "ESP Enabled",
        CurrentValue = true,
        Flag = "WZP_EspEnabled",
        Callback = function(v) settings.espEnabled = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Box",
        CurrentValue = true,
        Flag = "WZP_BoxEsp",
        Callback = function(v) settings.boxEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Name + Distance",
        CurrentValue = true,
        Flag = "WZP_NameEsp",
        Callback = function(v)
            settings.nameEsp = v
            settings.distanceEsp = v
        end,
    })
    VisualsTab:CreateToggle({
        Name = "Health Bar",
        CurrentValue = true,
        Flag = "WZP_HealthEsp",
        Callback = function(v) settings.healthEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Show Weapon",
        CurrentValue = true,
        Flag = "WZP_WeaponEsp",
        Callback = function(v) settings.weaponEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Skeleton",
        CurrentValue = true,
        Flag = "WZP_SkeletonEsp",
        Callback = function(v) settings.skeletonEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Self ESP",
        CurrentValue = false,
        Flag = "WZP_SelfEsp",
        Callback = function(v) settings.selfEsp = v end,
    })
    VisualsTab:CreateSlider({
        Name = "Max Distance",
        Range = { 100, 5000 },
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 2000,
        Flag = "WZP_MaxDistance",
        Callback = function(v) settings.maxDistance = v end,
    })

    trackSection(VisualsTab, "Loot ESP")
    VisualsTab:CreateToggle({
        Name = "Loot ESP",
        CurrentValue = true,
        Flag = "WZP_LootEsp",
        Callback = function(v) settings.lootEsp = v end,
    })
    VisualsTab:CreateSlider({
        Name = "Loot Max Distance",
        Range = { 100, 3000 },
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 1500,
        Flag = "WZP_LootMaxDistance",
        Callback = function(v) settings.lootMaxDistance = v end,
    })
    lootCategoryDropdown = VisualsTab:CreateDropdown({
        Name = "Loot Category",
        Options = lootCategories,
        CurrentOption = "All",
        Flag = "WZP_LootCategory",
        Callback = function(v) settings.lootCategory = v end,
    })

    trackSection(VisualsTab, "Boss ESP")
    VisualsTab:CreateToggle({
        Name = "Boss ESP",
        CurrentValue = true,
        Flag = "WZP_BossEsp",
        Callback = function(v) settings.bossEsp = v end,
    })
    VisualsTab:CreateToggle({
        Name = "Boss Spawn Alert",
        CurrentValue = true,
        Flag = "WZP_BossAlert",
        Callback = function(v) settings.bossAlert = v end,
    })

    local CombatTab = Window:CreateTab("Combat", 4483362458)
    trackSection(CombatTab, "Aimbot")
    CombatTab:CreateToggle({
        Name = "Aimbot Enabled",
        CurrentValue = false,
        Flag = "WZP_Aimbot",
        Callback = function(v)
            settings.aimbot = v
            if not v then aimHeld, aimLockPlayer = false, nil end
        end,
    })
    -- Custom aim-key button. The library keybind control cannot capture
    -- MouseButton1 (its rebinding handler has no MB1 branch), so we capture
    -- here: any keyboard key or mouse button (MB1/MB2/MB3) can be bound.
    local captureArmedAt = 0
    local aimKeyBtn
    local function refreshAimKeyLabel()
        if aimKeyBtn and aimKeyBtn.label then
            aimKeyBtn.label.Text = capturingAimKey
                and "Aim Key: [...]"
                or ("Aim Key: [" .. settings.aimKeyName .. "]")
        end
    end
    local aimKeyProxy = { type = "keybind", key = settings.aimKeyName }
    function aimKeyProxy:Set(newKey)
        if type(newKey) == "string" and newKey ~= "" and newKey ~= "None" then
            settings.aimKeyName = newKey
            self.key = newKey
        end
        capturingAimKey = false
        aimHeld = false
        refreshAimKeyLabel()
    end
    aimKeyBtn = CombatTab:CreateButton({
        Name = "Aim Key: [MouseButton2]",
        Callback = function()
            if capturingAimKey then return end
            capturingAimKey = true
            captureArmedAt = os.clock()
            -- Release menu input sinking immediately; the next input is the bind.
            setInputBlock(false)
            -- updateMenuState keeps the block disabled while capture is armed.
            refreshAimKeyLabel()
        end,
    })
    pcall(function()
        if Window.itemsByFlag then
            Window.itemsByFlag["WZP_AimKey"] = aimKeyProxy
        end
    end)

    -- Hold-state activation is event driven so mouse and keyboard binds use
    -- the same path. Mouse input is accepted even when Roblox marks it
    -- gameProcessed; keyboard input is ignored while typing in a textbox.
    table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if capturingAimKey or not settings.aimbot then return end
        if not inputMatchesAimKey(input) then return end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if gameProcessed then return end
            local focused = nil
            pcall(function() focused = UserInputService:GetFocusedTextBox() end)
            if focused ~= nil then return end
        end
        aimHeld = true
    end))
    table.insert(connections, UserInputService.InputEnded:Connect(function(input)
        if inputMatchesAimKey(input) then
            aimHeld = false
            aimLockPlayer = nil
        end
    end))

    table.insert(connections, UserInputService.InputBegan:Connect(function(input)
        if not capturingAimKey then return end
        -- Ignore the click that opened capture (button fires on press).
        if os.clock() - captureArmedAt < 0.18 then return end
        if input.KeyCode == Enum.KeyCode.Escape then
            capturingAimKey = false
            refreshAimKeyLabel()
            return
        end
        local name = resolveInputName(input)
        if name then aimKeyProxy:Set(name) end
    end))
    CombatTab:CreateSlider({
        Name = "Aim Max Distance",
        Range = { 50, 2000 },
        Increment = 25,
        Suffix = " studs",
        CurrentValue = 500,
        Flag = "WZP_AimMaxDist",
        Callback = function(v) settings.aimMaxDist = v end,
    })
    CombatTab:CreateSlider({
        Name = "Aim FOV",
        Range = { 50, 400 },
        Increment = 10,
        Suffix = " px",
        CurrentValue = 150,
        Flag = "WZP_AimFov",
        Callback = function(v) settings.aimFov = v end,
    })
    -- Higher = smoother (gentler). Maps to the per-frame response fraction:
    -- 100 -> 0.05 (very soft), 5 -> 0.8 (fast, capped below 1.0 so camera
    -- lag can never turn it into an overshoot oscillator). Default 70 -> 0.35.
    CombatTab:CreateSlider({
        Name = "Aim Smooth",
        Range = { 5, 100 },
        Increment = 5,
        Suffix = "%",
        CurrentValue = 70,
        Flag = "WZP_AimSmooth",
        Callback = function(v) settings.aimResponse = math.min(0.8, (105 - v) / 100) end,
    })
    pcall(function()
        if type(CombatTab.CreateLabel) == "function" then
            CombatTab:CreateLabel("Hold the aim key to aim at nearest head in FOV")
        end
        if type(Window.SortTabs) == "function" then
            Window:SortTabs({ "Overview", "Visuals", "Combat", "Settings" })
        end
    end)

    -- [[ Connections ]]
    table.insert(connections, RunService.RenderStepped:Connect(function(dt)
        pcall(updateMenuState)
        pcall(updatePlayerEsp)
        pcall(updateLootEsp)
        pcall(updateBossEsp)
        pcall(updateFovCircle)
        pcall(updateAimbot, dt)
    end))
    table.insert(connections, Players.PlayerRemoving:Connect(function(p)
        if p == aimLockPlayer then aimLockPlayer = nil end
        destroyEntry(p)
    end))

    local moduleHandle
    local function destroy()
        if not running then return end
        running = false
        settings.aimbot = false
        aimHeld, aimLockPlayer, capturingAimKey = false, nil, false
        pcall(function() setInputBlock(false) end)
        for _, c in ipairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(connections)
        pcall(removeUiSections)
        if fovCircle ~= nil then
            pcall(function() fovCircle:Remove() end)
            fovCircle = nil
        end
        local players = {}
        for p in pairs(espCache) do table.insert(players, p) end
        for _, p in ipairs(players) do destroyEntry(p) end
        table.clear(espCache)
        for model, e in pairs(lootCache) do
            if e.text then pcall(function() e.text:Remove() end) end
            lootCache[model] = nil
        end
        if bossDraw then
            for _, d in pairs(bossDraw) do
                if d then pcall(function() d:Remove() end) end
            end
            bossDraw = nil
        end
        if bossAlertText then
            pcall(function() bossAlertText:Remove() end)
            bossAlertText = nil
        end
        bossWasPresent = false
        if environment.__RAVEN_WARZPVP == moduleHandle then
            environment.__RAVEN_WARZPVP = nil
        end
    end

    local function getStatus()
        local lines, visible, ready, entries = 0, 0, 0, 0
        for _, e in pairs(espCache) do
            entries += 1
            if e.boneReady then ready += 1 end
            for _, line in pairs(e.bones or {}) do
                lines += 1
                local ok, shown = pcall(function() return line.Visible end)
                if ok and shown then visible += 1 end
            end
        end
        return {
            version = environment.RAVEN_WARZPVP_VER,
            running = running,
            aimbot = settings.aimbot,
            aimKey = settings.aimKeyName,
            aimHeld = aimHeld,
            target = aimLockPlayer and aimLockPlayer.Name or nil,
            skeleton = {entries = entries, lines = lines, visible = visible, ready = ready},
            loot = (function()
                local n = 0
                for _ in pairs(lootCache) do n = n + 1 end
                return n
            end)(),
            boss = bossWasPresent,
        }
    end

    moduleHandle = { Destroy = destroy, GetStatus = getStatus }
    environment.__RAVEN_WARZPVP = moduleHandle
    if type(ctx) == "table" and type(ctx.registerCleanup) == "function" then
        ctx.registerCleanup(destroy)
    end

    -- Test hook (only when loaded with ctx.__test); does not affect hub usage
    if type(ctx) == "table" and ctx.__test == true then
        environment.__RAVEN_WARZPVP._test = {
            settings = settings,
            espPlayers = function()
                local n = 0
                for _ in pairs(espCache) do n = n + 1 end
                return n
            end,
            aimTarget = function()
                local t = getAimTarget()
                return t and t.Parent and t.Parent.Name or nil
            end,
            fovVisible = function() return fovCircle and fovCircle.Visible or false end,
            hasMouseMove = function() return hasMouseMove end,
            hasDrawing = function() return hasDrawing end,
            resolveInputName = resolveInputName,
            aimKeyName = function() return settings.aimKeyName end,
            setAimKey = function(name) aimKeyProxy:Set(name) end,
            skeletonStats = function()
                local entries, lines, visible, ready = 0, 0, 0, 0
                for _, e in pairs(espCache) do
                    entries += 1
                    if e.boneReady then ready += 1 end
                    for _, line in pairs(e.bones or {}) do
                        lines += 1
                        local ok, isVisible = pcall(function() return line.Visible end)
                        if ok and isVisible then visible += 1 end
                    end
                end
                return {entries = entries, lines = lines, visible = visible, ready = ready}
            end,
            espNames = function()
                local names = {}
                for plr in pairs(espCache) do
                    table.insert(names, plr.Name)
                end
                return names
            end,
            drawZ = function()
                local ez = nil
                for _, e in pairs(espCache) do
                    if e.box then ez = e.box.ZIndex break end
                end
                return {
                    esp = ez,
                    fov = (fovCircle and fovCircle.ZIndex or nil),
                }
            end,
            menuOpen = function() return menuOpen end,
            blockBound = function() return inputBlockBound end,
            parseLootName = parseLootName,
            lootCategoryAllowed = lootCategoryAllowed,
            updateLootEsp = updateLootEsp,
            updateBossEsp = updateBossEsp,
            getBossModel = getBossModel,
            setLootCategory = function(c) settings.lootCategory = c end,
            lootCount = function()
                local n = 0
                for _ in pairs(lootCache) do n = n + 1 end
                return n
            end,
            bossPresent = function() return bossWasPresent end,
        }
    end

    return environment.__RAVEN_WARZPVP
end
