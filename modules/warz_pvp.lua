-- ============================================================
--   RAVEN HUB  |  WarZPVP
--   UniverseId: 10763998990  |  PlaceId: 135187059974536
--   Player ESP (Box/Name/Distance/HP/Weapon) + Aimbot (mouse-driven)
--   v1.3.0 — Self ESP toggle; custom aim-key button binds MB1/MB2/MB3 + keys
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
    environment.RAVEN_WARZPVP_VER = "1.0.0"

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

    -- Skeleton bones anchored at R15 RigAttachments (exact joint pivots, so
    -- the lines sit on the model's real joints instead of floating between
    -- part centers). Verified live on WarZPVP characters: 0 missing.
    -- Falls back to part centers if a game ever strips attachments.
    local SKELETON_BONES = {
        { "Head", "NeckRigAttachment", "UpperTorso", "NeckRigAttachment" },
        { "UpperTorso", "WaistRigAttachment", "LowerTorso", "WaistRigAttachment" },
        { "UpperTorso", "LeftShoulderRigAttachment", "LeftUpperArm", "LeftShoulderRigAttachment" },
        { "LeftUpperArm", "LeftElbowRigAttachment", "LeftLowerArm", "LeftElbowRigAttachment" },
        { "LeftLowerArm", "LeftWristRigAttachment", "LeftHand", "LeftWristRigAttachment" },
        { "UpperTorso", "RightShoulderRigAttachment", "RightUpperArm", "RightShoulderRigAttachment" },
        { "RightUpperArm", "RightElbowRigAttachment", "RightLowerArm", "RightElbowRigAttachment" },
        { "RightLowerArm", "RightWristRigAttachment", "RightHand", "RightWristRigAttachment" },
        { "LowerTorso", "LeftHipRigAttachment", "LeftUpperLeg", "LeftHipRigAttachment" },
        { "LeftUpperLeg", "LeftKneeRigAttachment", "LeftLowerLeg", "LeftKneeRigAttachment" },
        { "LeftLowerLeg", "LeftAnkleRigAttachment", "LeftFoot", "LeftAnkleRigAttachment" },
        { "LowerTorso", "RightHipRigAttachment", "RightUpperLeg", "RightHipRigAttachment" },
        { "RightUpperLeg", "RightKneeRigAttachment", "RightLowerLeg", "RightKneeRigAttachment" },
        { "RightLowerLeg", "RightAnkleRigAttachment", "RightFoot", "RightAnkleRigAttachment" },
    }

    local function boneWorldPos(part, att)
        if att ~= nil then
            local ok, wp = pcall(function() return att.WorldPosition end)
            if ok and typeof(wp) == "Vector3" then return wp end
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
        for i = 1, #SKELETON_BONES do
            local ln = safeDrawing("Line")
            if ln then
                ln.Thickness = 1
                ln.Color = ESP_COLOR
                ln.Visible = false
                e.bones[i] = ln
            end
        end
        espCache[p] = e
        return e
    end

    local function hideEntry(e)
        for _, d in pairs(e) do
            if type(d) == "table" then
                for _, l in pairs(d) do
                    if typeof(l) ~= "Instance" then
                        pcall(function() l.Visible = false end)
                    end
                end
            elseif d ~= nil and typeof(d) ~= "Instance" then
                pcall(function() d.Visible = false end)
            end
        end
    end

    local function destroyEntry(p)
        local e = espCache[p]
        if e then
            for _, d in pairs(e) do
                if type(d) == "table" then
                    for _, l in pairs(d) do
                        if typeof(l) ~= "Instance" then
                            pcall(function() l:Remove() end)
                        end
                    end
                elseif d ~= nil and typeof(d) ~= "Instance" then
                    pcall(function() d:Remove() end)
                end
            end
            espCache[p] = nil
        end
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
                            -- Skeleton: resolve bone parts once per character,
                            -- then project each bone to screen every frame.
                            if e.ch ~= ch then
                                e.ch = ch
                                e.boneParts = {}
                                for i, b in ipairs(SKELETON_BONES) do
                                    local pa = ch:FindFirstChild(b[1])
                                    local pb = ch:FindFirstChild(b[3])
                                    local aa = pa and pa:FindFirstChild(b[2]) or nil
                                    local ab = pb and pb:FindFirstChild(b[4]) or nil
                                    e.boneParts[i] = (pa and pb) and { pa, pb, aa, ab } or false
                                end
                            end
                            if settings.skeletonEsp then
                                for i, bp in ipairs(e.boneParts) do
                                    local ln = e.bones[i]
                                    if ln then
                                        if bp then
                                            local va, ona = camera:WorldToViewportPoint(boneWorldPos(bp[1], bp[3]))
                                            local vb, onb = camera:WorldToViewportPoint(boneWorldPos(bp[2], bp[4]))
                                            if ona and onb and va.Z > 0 and vb.Z > 0 then
                                                ln.From = Vector2.new(va.X, va.Y)
                                                ln.To = Vector2.new(vb.X, vb.Y)
                                                ln.Visible = true
                                            else
                                                ln.Visible = false
                                            end
                                        else
                                            ln.Visible = false
                                        end
                                    end
                                end
                            else
                                for _, ln in ipairs(e.bones) do
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

    -- [[ Aimbot: mouse-driven (no hitbox edits, no hooks, no remotes) ]]
    -- Drives the real mouse via mousemoverel() so the game's own camera
    -- turns toward the target. Target = head closest to crosshair within FOV.
    -- Target lock: once aiming starts, stick to the locked player until the
    -- lock goes invalid (dead / respawned / left FOV / out of range). Without
    -- this the "nearest head" scan flickers between close targets and the
    -- crosshair whips back and forth at high response.
    local aimLockPlayer = nil
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
        local listening = false
        pcall(function() listening = Window.activeKeybindListener ~= nil end)
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

    -- Aimbot keybind: MouseButton1/2/3 or any KeyCode, by name.
    local function isAimKeyHeld()
        local kn = settings.aimKeyName
        if kn == "MouseButton1" or kn == "MouseButton2" or kn == "MouseButton3" then
            local ok, held = pcall(function()
                return UserInputService:IsMouseButtonPressed(Enum.UserInputType[kn])
            end)
            return ok and held or false
        end
        -- Keyboard key: never fire while typing in chat / a textbox.
        local focused = nil
        pcall(function() focused = UserInputService:GetFocusedTextBox() end)
        if focused ~= nil then return false end
        local kc = nil
        pcall(function() kc = Enum.KeyCode[kn] end)
        if kc then
            local ok, held = pcall(function() return UserInputService:IsKeyDown(kc) end)
            return ok and held or false
        end
        return false
    end

    local function updateAimbot(dt)
        if not settings.aimbot then aimLockPlayer = nil return end
        if capturingAimKey then return end
        if menuOpen then return end -- don't fight the user while configuring
        local aiming = isAimKeyHeld()
        if not aiming or not hasMouseMove then aimLockPlayer = nil return end
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

    local CombatTab = Window:CreateTab("Combat", 4483362458)
    trackSection(CombatTab, "Aimbot")
    CombatTab:CreateToggle({
        Name = "Aimbot Enabled",
        CurrentValue = false,
        Flag = "WZP_Aimbot",
        Callback = function(v) settings.aimbot = v end,
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
        pcall(function() Window.activeKeybindListener = nil end)
        refreshAimKeyLabel()
    end
    aimKeyBtn = CombatTab:CreateButton({
        Name = "Aim Key: [MouseButton2]",
        Callback = function()
            if capturingAimKey then return end
            capturingAimKey = true
            captureArmedAt = os.clock()
            -- Drop the menu input block while listening (same signal the
            -- library keybind uses), so mouse buttons reach our capture.
            pcall(function() Window.activeKeybindListener = aimKeyProxy end)
            refreshAimKeyLabel()
        end,
    })
    pcall(function()
        if Window.itemsByFlag then
            Window.itemsByFlag["WZP_AimKey"] = aimKeyProxy
        end
    end)
    table.insert(connections, UserInputService.InputBegan:Connect(function(input, gpe)
        if not capturingAimKey then return end
        if gpe then return end
        -- Ignore the click that opened capture (button fires on press).
        if os.clock() - captureArmedAt < 0.25 then return end
        local name = resolveInputName(input)
        aimKeyProxy:Set(name or aimKeyProxy.key)
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
        pcall(updateFovCircle)
        pcall(updateAimbot, dt)
    end))
    table.insert(connections, Players.PlayerRemoving:Connect(function(p)
        if p == aimLockPlayer then aimLockPlayer = nil end
        destroyEntry(p)
    end))

    local function destroy()
        running = false
        pcall(function() setInputBlock(false) end)
        for _, c in ipairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        pcall(removeUiSections)
        if fovCircle ~= nil then pcall(function() fovCircle:Remove() end) end
        for p in pairs(espCache) do destroyEntry(p) end
        espCache = {}
    end

    environment.__RAVEN_WARZPVP = { Destroy = destroy }

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
        }
    end

    return environment.__RAVEN_WARZPVP
end
