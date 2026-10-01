-- ============================================================
--   RAVEN HUB  |  WarZPVP
--   UniverseId: 10763998990  |  PlaceId: 135187059974536
--   Player ESP (Box/Name/Distance/HP/Weapon) + Loot ESP + Boss ESP + Aimbot (mouse-driven)
--   v1.4.0 — loot ESP (WarzLoot), boss ESP + spawn alert (WarzBoss), skeleton render fix
--   v1.4.1 - R15 body bounds, validated head/LOS aim and bounded ESP updates.
--   Read-only visuals + mouse-driven aim.
--   WarZ notes: FFA (no Teams), skip dead via WarzDead attribute,
--   character = R15 (Head/HumanoidRootPart), WarzHitboxes folder present.
-- ============================================================

return function(Window, ctx)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
    environment.RAVEN_WARZPVP_VER = "1.4.5"

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
        autoHeal = false,
        healThreshold = 50,
        healSlot = 3,
        healCooldown = 0,
        noRecoil = false,
        instantPickup = false,
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

    -- WarZ renders the visible, animated body in
    -- Workspace.HeroVisualsLocal.Drift_<PlayerName>.LiveAim.
    -- LiveAim contains the real animated Bip01 Bone hierarchy under RootPart.
    -- Use those bones directly: WarzHitboxes uses the same Bip01 names.
    local function getLiveAim(player)
        if not player then return nil end
        local hv = Workspace:FindFirstChild("HeroVisualsLocal")
        if not hv then return nil end
        local drift = hv:FindFirstChild("Drift_" .. player.Name)
        if not drift then return nil end
        return drift:FindFirstChild("LiveAim")
    end

    local LIVEAIM_BONES = {
        { "Bip01_Head", "Bip01_Neck" },
        { "Bip01_Neck", "Bip01_Spine2" },
        { "Bip01_Spine2", "Bip01_Spine1" },
        { "Bip01_Spine1", "Bip01_Spine" },
        { "Bip01_Spine", "Bip01_Pelvis" },

        { "Bip01_Neck", "Bip01_L_Clavicle" },
        { "Bip01_L_Clavicle", "Bip01_L_UpperArm" },
        { "Bip01_L_UpperArm", "Bip01_L_Forearm" },
        { "Bip01_L_Forearm", "Bip01_L_Hand" },

        { "Bip01_Neck", "Bip01_R_Clavicle" },
        { "Bip01_R_Clavicle", "Bip01_R_UpperArm" },
        { "Bip01_R_UpperArm", "Bip01_R_Forearm" },
        { "Bip01_R_Forearm", "Bip01_R_Hand" },

        { "Bip01_Pelvis", "Bip01_L_Thigh" },
        { "Bip01_L_Thigh", "Bip01_L_Calf" },
        { "Bip01_L_Calf", "Bip01_L_Foot" },

        { "Bip01_Pelvis", "Bip01_R_Thigh" },
        { "Bip01_R_Thigh", "Bip01_R_Calf" },
        { "Bip01_R_Calf", "Bip01_R_Foot" },
    }
    local LIVEAIM_BONE_COUNT = #LIVEAIM_BONES

    local function findLiveBone(live, name)
        local root = live and live:FindFirstChild("RootPart")
        if not root then return nil end
        local bone = root:FindFirstChild(name, true)
        return bone and bone:IsA("Bone") and bone or nil
    end

    local function boneWorldPosition(bone)
        if not bone or not bone.Parent then return nil end
        local ok, pos = pcall(function()
            return bone.TransformedWorldCFrame.Position
        end)
        if ok and typeof(pos) == "Vector3" then return pos end
        ok, pos = pcall(function()
            return bone.WorldPosition
        end)
        return (ok and typeof(pos) == "Vector3") and pos or nil
    end

    local function bodyPart(model, name)
        if not model then return nil end
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then
            return part
        end
        return nil
    end

    local function getVisualHead(character)
        local player = Players:GetPlayerFromCharacter(character)
        local live = getLiveAim(player)
        local head = live and live:FindFirstChild("Head")
        if head and head:IsA("BasePart") and head.Transparency < 1 then
            return head, live
        end
        return bodyPart(character, "Head"), live
    end

    -- WarzHitboxes builds its Chest capsule from Bip01_Spine2 -> Bip01_Neck.
    -- Aim at the middle of that exact animated segment instead of guessing
    -- from the merged Body mesh. This stays inside the game's real hit volume.
    local function getAimPoint(character)
        local player = Players:GetPlayerFromCharacter(character)
        local live = getLiveAim(player)
        if live then
            local spine2 = findLiveBone(live, "Bip01_Spine2")
            local neck = findLiveBone(live, "Bip01_Neck")
            local a, b = boneWorldPosition(spine2), boneWorldPosition(neck)
            if a and b then
                return a:Lerp(b, 0.5), "Chest"
            end

            local headBone = findLiveBone(live, "Bip01_Head")
            local headPos = boneWorldPosition(headBone)
            if headPos then
                return headPos, "Head"
            end

            local body = live:FindFirstChild("Body")
            if body and body:IsA("BasePart") and body.Transparency < 1 then
                return body.Position, "Body"
            end
        end

        local torso = bodyPart(character, "UpperTorso")
            or bodyPart(character, "Torso")
            or bodyPart(character, "Head")
        return torso and torso.Position or nil, torso and torso.Name or nil
    end

    local BODY_PARTS = {
        "Head", "UpperTorso", "LowerTorso", "Torso",
        "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperArm", "RightLowerArm", "RightHand",
        "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
        "RightUpperLeg", "RightLowerLeg", "RightFoot",
    }

    local function characterScreenBounds(model)
        local root = bodyPart(model, "HumanoidRootPart") or bodyPart(model, "Torso")
        if not root then return nil end
        local rootView, rootOn = camera:WorldToViewportPoint(root.Position)
        if not rootOn or rootView.Z <= 0 then return nil end

        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local points = 0
        local function add(position)
            local v = camera:WorldToViewportPoint(position)
            if v.Z <= 0 then return end
            points += 1
            minX, minY = math.min(minX, v.X), math.min(minY, v.Y)
            maxX, maxY = math.max(maxX, v.X), math.max(maxY, v.Y)
        end
        local function addPartBounds(part)
            if not part or not part:IsA("BasePart") then return end
            local cf, half = part.CFrame, part.Size * 0.5
            for sx = -1, 1, 2 do
                for sy = -1, 1, 2 do
                    for sz = -1, 1, 2 do
                        add(cf:PointToWorldSpace(Vector3.new(
                            half.X * sx, half.Y * sy, half.Z * sz
                        )))
                    end
                end
            end
        end

        -- Match the rendered WarZ body, not the invisible Character T-pose.
        local _, live = getVisualHead(model)
        if live then
            for _, name in ipairs({ "Head", "Body", "Arms", "Legs" }) do
                local part = live:FindFirstChild(name)
                if part and part:IsA("BasePart") and part.Transparency < 1 then
                    addPartBounds(part)
                end
            end
        end

        -- Fallback while LiveAim has not replicated yet.
        if points == 0 then
            for _, name in ipairs(BODY_PARTS) do
                addPartBounds(bodyPart(model, name))
            end
        end

        if points == 0 then return nil end
        local w, h = maxX - minX, maxY - minY
        local vs = camera.ViewportSize
        if w < 2 or h < 4 or w > vs.X * 2 or h > vs.Y * 2
            or maxX < 0 or minX > vs.X or maxY < 0 or minY > vs.Y then
            return nil
        end
        return {
            x = minX, y = minY, w = w, h = h,
            centerX = (minX + maxX) * 0.5,
        }
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
        for i = 1, LIVEAIM_BONE_COUNT do
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

    local function resolveSkeletonParts(e, ch, player)
        local now = os.clock()
        local live = getLiveAim(player)
        if e.boneCharacter == ch and e.liveAim == live and e.boneReady then return end
        if e.boneCharacter == ch and e.liveAim == live and now < e.boneRetryAt then return end

        e.boneCharacter = ch
        e.liveAim = live
        e.boneRetryAt = now + 0.5
        table.clear(e.boneParts)
        e.boneReady = live ~= nil
        if not live then return end

        for i, segment in ipairs(LIVEAIM_BONES) do
            local a = findLiveBone(live, segment[1])
            local b = findLiveBone(live, segment[2])
            if a and b then
                e.boneParts[i] = { a, b }
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
                        local bounds = characterScreenBounds(ch)
                        if bounds then
                            local h, w = bounds.h, bounds.w
                            local x0, y0 = bounds.x, bounds.y
                            if settings.boxEsp and e.box then
                                e.box.Size = Vector2.new(w, h)
                                e.box.Position = Vector2.new(x0, y0)
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
                                e.name.Position = Vector2.new(bounds.centerX, y0 - 18)
                                e.name.Visible = true
                            elseif e.name then
                                e.name.Visible = false
                            end
                            if settings.healthEsp and e.hpBack and e.hpFill then
                                local hum = ch:FindFirstChildOfClass("Humanoid")
                                local ratio = hum and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
                                local bw = 4
                                e.hpBack.Size = Vector2.new(bw, h)
                                e.hpBack.Position = Vector2.new(x0 - bw - 2, y0)
                                e.hpBack.Visible = true
                                e.hpFill.Size = Vector2.new(bw, h * ratio)
                                e.hpFill.Position = Vector2.new(x0 - bw - 2, y0 + h * (1 - ratio))
                                e.hpFill.Color = getHealthColor(ratio)
                                e.hpFill.Visible = true
                            else
                                if e.hpBack then e.hpBack.Visible = false end
                                if e.hpFill then e.hpFill.Visible = false end
                            end
                            if settings.skeletonEsp then
                                -- Skeleton follows the visible LiveAim rig (animated).
                                -- Retry every 0.5s while LiveAim isn't replicated;
                                -- never draw the invisible Character T-pose.
                                ensureSkeletonDrawings(e)
                                resolveSkeletonParts(e, ch, p)
                                for i = 1, LIVEAIM_BONE_COUNT do
                                    local ln = e.bones[i]
                                    local pair = e.boneParts[i]
                                    if ln then
                                        if pair and e.liveAim and e.liveAim.Parent then
                                            local a = boneWorldPosition(pair[1])
                                            local b = boneWorldPosition(pair[2])
                                            if a and b then
                                                local va, ona = camera:WorldToViewportPoint(a)
                                                local vb, onb = camera:WorldToViewportPoint(b)
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
                                        else
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
        local bounds = characterScreenBounds(model)
        if not bounds then
            hideBossEsp()
            return
        end
        local w, h = bounds.w, bounds.h
        local x0, y0 = bounds.x, bounds.y
        if d.box then
            d.box.Visible = true
            d.box.Size = Vector2.new(w, h)
            d.box.Position = Vector2.new(x0, y0)
        end
        if d.name then
            d.name.Visible = true
            d.name.Position = Vector2.new(bounds.centerX, y0 - 18)
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
    local aimLockCharacter = nil
    local aimHeld = false
    local capturingAimKey = false -- true while the custom aim-key button listens

    local function canSeeAimPart(character, head)
        local origin = camera.CFrame.Position
        local direction = head.Position - origin
        if direction.Magnitude < 0.01 then return false end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local ignored = {}
        if localPlayer.Character then table.insert(ignored, localPlayer.Character) end
        local hitboxes = Workspace:FindFirstChild("WarzHitboxes")
        if hitboxes then table.insert(ignored, hitboxes) end
        params.FilterDescendantsInstances = ignored
        params.IgnoreWater = true
        local hit = Workspace:Raycast(origin, direction, params)
        return not hit or hit.Instance:IsDescendantOf(character)
    end

    local function validAimHead(character, maxFov)
        if not isAlive(character) then return nil, nil end
        local head = getAimPart(character)
        if not head then return nil, nil end
        local position = head.Position
        if (position - camera.CFrame.Position).Magnitude > settings.aimMaxDist then
            return nil, nil
        end
        local view, on = camera:WorldToViewportPoint(position)
        if not on or view.Z <= 0 then return nil, nil end
        local center = camera.ViewportSize / 2
        local pixels = (Vector2.new(view.X, view.Y) - center).Magnitude
        if pixels > maxFov then return nil, nil end
        return head, pixels
    end

    local function scanAimTarget()
        local best, bestP, bestPx = nil, nil, settings.aimFov
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= localPlayer then
                local character = p.Character
                local head, pixels = validAimHead(character, bestPx)
                if head and pixels < bestPx and canSeeAimPart(character, head) then
                    best, bestP, bestPx = head, p, pixels
                end
            end
        end
        return best, bestP
    end

    local function getAimTarget()
        local player = aimLockPlayer
        if player then
            local character = aimLockCharacter
            if character and player.Character == character then
                local head = validAimHead(character, settings.aimFov * 1.25)
                if head and canSeeAimPart(character, head) then
                    return head
                end
            end
            aimLockPlayer, aimLockCharacter = nil, nil
        end
        local best, bestP = scanAimTarget()
        aimLockPlayer = bestP
        aimLockCharacter = bestP and bestP.Character or nil
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
        if not settings.aimbot then aimHeld, aimLockPlayer, aimLockCharacter = false, nil, nil return end
        if capturingAimKey then aimHeld, aimLockPlayer, aimLockCharacter = false, nil, nil return end
        if menuOpen and mouseOverMenu() then aimLockPlayer, aimLockCharacter = nil, nil return end
        if not aimHeld or not hasMouseMove then aimLockPlayer, aimLockCharacter = nil, nil return end
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
            if not v then aimHeld, aimLockPlayer, aimLockCharacter = false, nil, nil end
        end,
    })
    -- Custom aim-key button. The library keybind control cannot capture
    -- MouseButton1 (its rebinding handler has no MB1 branch), so we capture
    -- here: any keyboard key or mouse button (MB1/MB2/MB3) can be bound.
    local captureArmedAt = 0
    local aimKeyBtn
    local function refreshAimKeyLabel()
        local text = capturingAimKey
            and "Aim Key: [...]"
            or ("Aim Key: [" .. settings.aimKeyName .. "]")
        if aimKeyBtn then
            if aimKeyBtn.label then
                pcall(function() aimKeyBtn.label.Text = text end)
            end
            if type(aimKeyBtn.SetName) == "function" then
                pcall(function() aimKeyBtn:SetName(text) end)
            elseif type(aimKeyBtn.Set) == "function" then
                pcall(function() aimKeyBtn:Set({ Name = text }) end)
            end
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
            aimLockPlayer, aimLockCharacter = nil, nil
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
    trackSection(CombatTab, "Auto Heal")
    CombatTab:CreateToggle({
        Name = "Auto Heal",
        CurrentValue = false,
        Flag = "WZP_AutoHeal",
        Callback = function(v) settings.autoHeal = v end,
    })
    CombatTab:CreateSlider({
        Name = "Heal Threshold",
        Range = { 10, 90 },
        Increment = 5,
        Suffix = " HP",
        CurrentValue = 50,
        Flag = "WZP_HealThreshold",
        Callback = function(v) settings.healThreshold = v end,
    })
    CombatTab:CreateSlider({
        Name = "Heal Slot",
        Range = { 1, 9 },
        Increment = 1,
        Suffix = "",
        CurrentValue = 3,
        Flag = "WZP_HealSlot",
        Callback = function(v) settings.healSlot = math.floor(v) end,
    })
    -- No Recoil (Tier 2): modify weapon catalog tables directly
    -- When Recoil <= 0, WarzCamera.ApplyRecoil returns early (no effect). No hooks needed.
    local function applyNoRecoil()
        local ok, cs = pcall(require, localPlayer.PlayerScripts.Client.input.CombatSettings)
        if not ok or not cs then return end
        local catalog
        if type(cs.GetCatalog) == "function" then
            local ok2, cat = pcall(cs.GetCatalog)
            if ok2 then catalog = cat end
        end
        if catalog and catalog.Weapons then
            for _, weapon in pairs(catalog.Weapons) do
                if type(weapon) == "table" then
                    if weapon._origRecoil == nil then
                        weapon._origRecoil = weapon.Recoil or 9
                        weapon._origViewRecoil = weapon.ViewRecoil or 0.38
                    end
                    if settings.noRecoil then
                        weapon.Recoil = 0
                        weapon.ViewRecoil = 0
                    else
                        weapon.Recoil = weapon._origRecoil
                        weapon.ViewRecoil = weapon._origViewRecoil
                    end
                    -- Ensure Spread stays at its original legit value for server-authoritative hits
                    if weapon._origSpread ~= nil then
                        weapon.Spread = weapon._origSpread
                    end
                end
            end
        end
        local okCfg, Config = pcall(require, ReplicatedStorage.Shared.Config)
        if okCfg and Config and type(Config.Shop) == "table" then
            for _, item in pairs(Config.Shop) do
                if type(item) == "table" then
                    if item.Recoil ~= nil and item._origRecoil == nil then
                        item._origRecoil = item.Recoil
                    end
                    if settings.noRecoil and item.Recoil ~= nil then
                        item.Recoil = 0
                    elseif not settings.noRecoil and item._origRecoil ~= nil then
                        item.Recoil = item._origRecoil
                    end
                    if item._origSpread ~= nil then
                        item.Spread = item._origSpread
                    end
                end
            end
        end
    end
    _G.__WZP_ApplyNoRecoil = applyNoRecoil

    trackSection(CombatTab, "No Recoil")
    CombatTab:CreateToggle({
        Name = "No Recoil",
        CurrentValue = false,
        Flag = "WZP_NoRecoil",
        Callback = function(v)
            settings.noRecoil = v
            pcall(applyNoRecoil)
        end,
    })
    CombatTab:CreateToggle({
        Name = "Instant Pickup",
        CurrentValue = false,
        Flag = "WZP_InstantPickup",
        Callback = function(v)
            settings.instantPickup = v
            pcall(applyInstantPickup)
        end,
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
    -- Refresh aim/UI every frame, but bound the heavier ESP work to 30/8/12 Hz.
    -- Do not hold a stale CurrentCamera across death or camera replacement.
    local espTime, lootTime, bossTime = 0, 0, 0
    table.insert(connections, RunService.RenderStepped:Connect(function(dt)
        if not running then return end
        camera = Workspace.CurrentCamera or camera
        local elapsed = math.min(dt or 1 / 60, 0.1)
        espTime += elapsed
        lootTime += elapsed
        bossTime += elapsed
        pcall(updateMenuState)
        pcall(updatePlayerEsp)
        if lootTime >= 1 / 8 then
            lootTime = 0
            pcall(updateLootEsp)
        end
        if bossTime >= 1 / 12 then
            bossTime = 0
            pcall(updateBossEsp)
        end
        pcall(updateFovCircle)
        pcall(updateAimbot, dt)

        -- Keep recoil updated if active
        if settings.noRecoil then
            pcall(applyNoRecoil)
        end

        -- Instant Pickup (Tier 2): patch LootHold.Step to commit instantly
        local _origLootHoldStep = nil
        local function applyInstantPickup()
            local lhMod
            for _, c in ipairs(localPlayer.PlayerScripts.Client:GetDescendants()) do
                if c.Name == "LootHold" and c:IsA("ModuleScript") then
                    local ok, mod = pcall(require, c)
                    if ok and mod then lhMod = mod break end
                end
            end
            if not lhMod then return end
            if settings.instantPickup then
                if not _origLootHoldStep then
                    _origLootHoldStep = lhMod.Step
                    lhMod.Step = function(self, uid, target, holding, t)
                        if self.uid and not self.committed and holding then
                            self.started = t - 2
                            self.nextUse = t - 1
                        end
                        return _origLootHoldStep(self, uid, target, holding, t)
                    end
                end
            else
                if _origLootHoldStep then
                    lhMod.Step = _origLootHoldStep
                    _origLootHoldStep = nil
                end
            end
        end

        -- Auto Heal (Tier 1): via CombatInput.RequestUseMed() (correct signature)
        if settings.autoHeal then
            pcall(function()
                local char = localPlayer.Character
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and hum.Health < settings.healThreshold then
                    local now = os.clock()
                    if now - settings.healCooldown >= 0.5 then
                        local cd = tonumber(localPlayer:GetAttribute("WarzMedCdLeft")) or 0
                        if cd <= 0.05 then
                            local ok, ci = pcall(require, localPlayer.PlayerScripts.Client.input.CombatInput)
                            if ok and ci and type(ci.RequestUseMed) == "function" then
                                pcall(ci.RequestUseMed)
                                settings.healCooldown = now
                            end
                        end
                    end
                end
            end)
        end
    end))
    table.insert(connections, Players.PlayerRemoving:Connect(function(p)
        if p == aimLockPlayer then aimLockPlayer, aimLockCharacter = nil, nil end
        destroyEntry(p)
    end))

    local moduleHandle
    local function destroy()
        if not running then return end
        running = false
        settings.aimbot = false
        aimHeld, aimLockPlayer, aimLockCharacter, capturingAimKey = false, nil, nil, false
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
        pcall(function()
            local ok, cs = pcall(require, localPlayer.PlayerScripts.Client.input.CombatSettings)
            if ok and cs and type(cs.GetCatalog) == "function" then
                local cat = cs.GetCatalog()
                if cat and cat.Weapons then
                    for _, w in pairs(cat.Weapons) do
                        if type(w) == "table" and w._origRecoil ~= nil then
                            w.Recoil = w._origRecoil
                            w.Spread = w._origSpread
                            w.ViewRecoil = w._origViewRecoil
                        end
                    end
                end
            end
        end)
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
