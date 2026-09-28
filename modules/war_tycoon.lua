-- ============================================================
--   RAVEN HUB  |  War Tycoon
--   UniverseId: 1526814825  |  PlaceId: 4639625707
--   Player ESP + Auto-Collect | 100% Drawing API visuals (zero instances)
--   v1.0.0 — read-only ESP, teleport-based cash collect, no hooks, no remotes
--   Auto-Collect: teleports to your base's Collector pad when waiting cash
--   reaches the threshold, then returns you to your original spot.
--   Tested live 2026-09-29: pad stand 4s => +3427 cash (firetouchinterest = 0).
-- ============================================================

return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")

    local localPlayer = Players.LocalPlayer
    local camera = Workspace.CurrentCamera

    -- Clean up previous instance
    local environment = (type(getgenv) == "function" and getgenv()) or _G
    if type(environment.__RAVEN_WAR_TYCOON) == "table"
        and type(environment.__RAVEN_WAR_TYCOON.Destroy) == "function" then
        pcall(environment.__RAVEN_WAR_TYCOON.Destroy)
    end
    environment.RAVEN_WAR_TYCOON_VER = "1.0.0"

    local running = true
    local connections = {}
    local espCache = {}

    local settings = {
        espEnabled = true,
        boxEsp = true,
        nameEsp = true,
        healthEsp = true,
        distanceEsp = true,
        maxDistance = 2000,
        autoCollect = false,
        collectThreshold = 500,
        collectInterval = 5,
    }

    local collectStatus = "idle"
    local statusLabel = nil

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

    local function safeDrawing(drawingType)
        if not hasDrawing then return nil end
        local ok, obj = pcall(Drawing.new, drawingType)
        return (ok and obj) or nil
    end

    local function getHealthColor(ratio)
        return Color3.fromHSV(math.clamp(ratio, 0, 1) * 0.33, 0.9, 1)
    end

    -- [[ Player ESP (Drawing API, zero instances) ]]
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
            e.box.Thickness = 1
            e.box.Filled = false
            e.box.Color = Color3.fromRGB(255, 80, 80)
        end
        if e.name then
            e.name.Size = 13
            e.name.Center = true
            e.name.Outline = true
            e.name.Color = Color3.fromRGB(255, 255, 255)
        end
        if e.hpBack then
            e.hpBack.Filled = true
            e.hpBack.Color = Color3.fromRGB(20, 20, 20)
        end
        if e.hpFill then e.hpFill.Filled = true end
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

    local function updateEsp()
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
                            if e.box then
                                e.box.Size = Vector2.new(w, h)
                                e.box.Position = Vector2.new(top.X - w / 2, top.Y)
                                e.box.Visible = settings.boxEsp
                            end
                            if e.name then
                                local txt = p.Name
                                if settings.distanceEsp then
                                    txt = txt .. " [" .. math.floor(dist) .. "m]"
                                end
                                e.name.Text = txt
                                e.name.Position = Vector2.new(top.X, top.Y - 16)
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

    -- [[ Auto-Collect ]]
    local function parseAmount(text)
        if type(text) ~= "string" then return 0 end
        local num, suffix = text:match("%$([%d%.]+)([kKmM]?)")
        num = tonumber(num)
        if not num then return 0 end
        suffix = string.lower(suffix or "")
        if suffix == "k" then num = num * 1000
        elseif suffix == "m" then num = num * 1000000 end
        return math.floor(num)
    end

    local function getOwnBase()
        local ty = Workspace:FindFirstChild("Tycoon")
        local tycoons = ty and ty:FindFirstChild("Tycoons")
        if not tycoons then return nil end
        for _, b in ipairs(tycoons:GetChildren()) do
            local ov = b:FindFirstChild("Owner")
            if ov and ov.Value == localPlayer then
                return b
            end
        end
        return nil
    end

    local function getCollectors(base)
        local out = {}
        if not base then return out end
        for _, d in ipairs(base:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == "Collector" then
                local amount = 0
                local holder = d.Parent
                if holder then
                    for _, dd in ipairs(holder:GetDescendants()) do
                        if dd:IsA("TextLabel") and dd.Name == "Amount" then
                            amount = parseAmount(dd.Text)
                            break
                        end
                    end
                end
                table.insert(out, { part = d, amount = amount })
            end
        end
        return out
    end

    local function doCollect()
        local char = localPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return "no character" end
        local base = getOwnBase()
        if not base then return "base not found" end
        local cols = getCollectors(base)
        if #cols == 0 then return "no collector pad" end
        table.sort(cols, function(a, b) return a.amount > b.amount end)
        local best = cols[1]
        if best.amount < settings.collectThreshold then
            return "waiting ($" .. best.amount .. ")"
        end
        local orig = hrp.CFrame
        hrp.CFrame = best.part.CFrame + Vector3.new(0, 4, 0)
        hrp.Velocity = Vector3.new(0, 0, 0)
        task.wait(1.0)
        local ch2 = localPlayer.Character
        local hrp2 = ch2 and ch2:FindFirstChild("HumanoidRootPart")
        if hrp2 then
            hrp2.CFrame = orig
            hrp2.Velocity = Vector3.new(0, 0, 0)
        end
        return "collected ~$" .. best.amount
    end

    local function refreshStatusLabel()
        if statusLabel ~= nil then
            pcall(function()
                if type(statusLabel.SetText) == "function" then
                    statusLabel:SetText("Status: " .. collectStatus)
                elseif type(statusLabel.Update) == "function" then
                    statusLabel:Update("Status: " .. collectStatus)
                end
            end)
        end
    end

    -- [[ UI ]]
    local VisualsTab = Window:CreateTab("Visuals", 4483362458)
    VisualsTab:CreateSection("Player ESP")

    VisualsTab:CreateToggle({
        Name = "ESP Enabled",
        CurrentValue = true,
        Flag = "WT_EspEnabled",
        Callback = function(v) settings.espEnabled = v end,
    })

    VisualsTab:CreateToggle({
        Name = "Box",
        CurrentValue = true,
        Flag = "WT_BoxEsp",
        Callback = function(v) settings.boxEsp = v end,
    })

    VisualsTab:CreateToggle({
        Name = "Name + Distance",
        CurrentValue = true,
        Flag = "WT_NameEsp",
        Callback = function(v)
            settings.nameEsp = v
            settings.distanceEsp = v
        end,
    })

    VisualsTab:CreateToggle({
        Name = "Health Bar",
        CurrentValue = true,
        Flag = "WT_HealthEsp",
        Callback = function(v) settings.healthEsp = v end,
    })

    VisualsTab:CreateSlider({
        Name = "Max Distance",
        Range = {100, 5000},
        Increment = 50,
        Suffix = " studs",
        CurrentValue = 2000,
        Flag = "WT_MaxDistance",
        Callback = function(v) settings.maxDistance = v end,
    })

    local FarmTab = Window:CreateTab("Farm", 4483362458)
    FarmTab:CreateSection("Auto-Collect")

    FarmTab:CreateToggle({
        Name = "Auto-Collect Cash",
        CurrentValue = false,
        Flag = "WT_AutoCollect",
        Callback = function(v) settings.autoCollect = v end,
    })

    FarmTab:CreateSlider({
        Name = "Collect Threshold",
        Range = {100, 50000},
        Increment = 100,
        Suffix = " $",
        CurrentValue = 500,
        Flag = "WT_CollectThreshold",
        Callback = function(v) settings.collectThreshold = v end,
    })

    FarmTab:CreateSlider({
        Name = "Check Interval",
        Range = {2, 30},
        Increment = 1,
        Suffix = "s",
        CurrentValue = 5,
        Flag = "WT_CollectInterval",
        Callback = function(v) settings.collectInterval = v end,
    })

    pcall(function()
        if type(FarmTab.CreateLabel) == "function" then
            statusLabel = FarmTab:CreateLabel("Status: idle")
        end
    end)

    -- [[ Connections ]]
    table.insert(connections, RunService.RenderStepped:Connect(function()
        local ok, err = pcall(updateEsp)
    end))
    table.insert(connections, Players.PlayerRemoving:Connect(function(p)
        destroyEntry(p)
    end))

    -- Auto-collect ticker
    task.spawn(function()
        while running do
            if settings.autoCollect then
                local ok, res = pcall(doCollect)
                collectStatus = ok and tostring(res) or "error"
                refreshStatusLabel()
            elseif collectStatus ~= "idle" then
                collectStatus = "idle"
                refreshStatusLabel()
            end
            task.wait(settings.collectInterval)
        end
    end)

    local function destroy()
        running = false
        for _, c in ipairs(connections) do
            pcall(function() c:Disconnect() end)
        end
        for p in pairs(espCache) do destroyEntry(p) end
        espCache = {}
    end

    environment.__RAVEN_WAR_TYCOON = { Destroy = destroy }

    return environment.__RAVEN_WAR_TYCOON
end
