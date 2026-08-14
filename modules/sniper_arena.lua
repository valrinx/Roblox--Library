-- RAVEN HUB | Sniper Arena - Aimlock, Trigger Bot, ESP
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local camera = workspace.CurrentCamera
    local localPlayer = Players.LocalPlayer
    local running = true
    local connections = {}
    local espObjects = {}

    local settings = {
        aimlock = false,
        aimlockKey = Enum.KeyCode.E,
        aimPart = "Head",
        fov = 120,
        smoothness = 1,
        triggerBot = false,
        triggerDelay = 0.05,
        esp = false,
        espShowDistance = true,
        espShowHealth = true,
        teamCheck = true,
    }

    local locked = nil
    local lastTrigger = 0

    local function connect(signal, callback)
        local c = signal:Connect(callback)
        table.insert(connections, c)
        return c
    end

    local function getCharacter(plr)
        local c = plr and plr.Character
        return c and c.Parent and c or nil
    end

    local function getRoot(c) return c and c:FindFirstChild("HumanoidRootPart") end
    local function getHead(c) return c and c:FindFirstChild("Head") end
    local function getHumanoid(c) return c and c:FindFirstChildOfClass("Humanoid") end

    local function isEnemy(plr)
        if not settings.teamCheck then return true end
        if not plr.Team or not localPlayer.Team then return true end
        return plr.Team ~= localPlayer.Team
    end

    local function isAlive(plr)
        local c = getCharacter(plr)
        local h = getHumanoid(c)
        return c and h and h.Health > 0
    end

    local function getAimPart(c)
        if settings.aimPart == "Head" then
            return getHead(c) or getRoot(c)
        end
        return getRoot(c)
    end

    local function worldToScreen(pos)
        local vec, onScreen = camera:WorldToViewportPoint(pos)
        return Vector2.new(vec.X, vec.Y), onScreen, vec.Z
    end

    local function getAngle(screenPos)
        local center = Vector2.new(camera.ViewportSize.X/2, camera.ViewportSize.Y/2)
        return (screenPos - center).Magnitude
    end

    local function getBestTarget()
        local best = nil
        local bestAngle = settings.fov
        local myRoot = getRoot(getCharacter(localPlayer))
        if not myRoot then return nil end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= localPlayer and isEnemy(plr) and isAlive(plr) then
                local c = getCharacter(plr)
                local part = getAimPart(c)
                if part then
                    local screen, onScreen = worldToScreen(part.Position)
                    if onScreen then
                        local angle = getAngle(screen)
                        if angle < bestAngle then
                            bestAngle = angle
                            best = {player = plr, character = c, part = part, angle = angle}
                        end
                    end
                end
            end
        end
        return best
    end

    -- ============================================================
    --   AIMLOCK
    -- ============================================================

    local function aimAt(target)
        if not target or not target.part or not target.part.Parent then
            locked = nil
            return
        end
        local targetPos = target.part.Position
        camera.CFrame = CFrame.lookAt(camera.CFrame.Position, targetPos)
    end

    -- ============================================================
    --   TRIGGER BOT
    -- ============================================================

    local function checkTrigger()
        if not settings.triggerBot then return end
        if tick() - lastTrigger < 0.3 then return end

        local myRoot = getRoot(getCharacter(localPlayer))
        if not myRoot then return end

        local ray = Ray.new(camera.CFrame.Position, camera.CFrame.LookVector * 1000)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {localPlayer.Character}

        local result = workspace:Raycast(camera.CFrame.Position, camera.CFrame.LookVector * 1000, params)
        if result and result.Instance then
            local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
            if hitChar then
                local hitPlr = Players:GetPlayerFromCharacter(hitChar)
                if hitPlr and hitPlr ~= localPlayer and isEnemy(hitPlr) and isAlive(hitPlr) then
                    lastTrigger = tick()
                    task.delay(settings.triggerDelay, function()
                        mouse1click()
                    end)
                end
            end
        end
    end

    -- ============================================================
    --   ESP
    -- ============================================================

    local function createEsp(plr)
        if plr == localPlayer or espObjects[plr] then return end
        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenESP"
        highlight.FillTransparency = 0.7
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Enabled = false

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenESPInfo"
        billboard.Size = UDim2.fromOffset(160, 40)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Enabled = false

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.fromRGB(255, 80, 80)
        label.TextStrokeTransparency = 0.4
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.Text = plr.Name
        label.Parent = billboard

        espObjects[plr] = {highlight = highlight, billboard = billboard, label = label}
    end

    local function removeEsp(plr)
        local o = espObjects[plr]
        if o then
            pcall(function() o.highlight:Destroy() end)
            pcall(function() o.billboard:Destroy() end)
            espObjects[plr] = nil
        end
    end

    local function clearAllEsp()
        for plr in pairs(espObjects) do removeEsp(plr) end
    end

    local function updateEsp()
        if not settings.esp then clearAllEsp(); return end
        local myRoot = getRoot(getCharacter(localPlayer))
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= localPlayer and isEnemy(plr) then
                createEsp(plr)
                local o = espObjects[plr]
                local c = getCharacter(plr)
                local root = getRoot(c)
                local hum = getHumanoid(c)
                if o and c and root then
                    local alive = hum and hum.Health > 0
                    o.highlight.Adornee = c
                    o.highlight.Parent = c
                    o.highlight.Enabled = true
                    o.highlight.FillColor = alive and Color3.fromRGB(255,50,50) or Color3.fromRGB(100,100,100)
                    o.highlight.OutlineColor = alive and Color3.fromRGB(255,150,150) or Color3.fromRGB(80,80,80)
                    o.billboard.Adornee = root
                    o.billboard.Parent = c
                    o.billboard.Enabled = alive
                    local text = plr.DisplayName
                    if settings.espShowDistance and myRoot then
                        text = text .. " [" .. math.floor((root.Position - myRoot.Position).Magnitude) .. "m]"
                    end
                    if settings.espShowHealth and hum then
                        text = text .. " " .. math.floor(hum.Health) .. "hp"
                    end
                    o.label.Text = text
                elseif o then
                    o.highlight.Enabled = false
                    o.billboard.Enabled = false
                end
            end
        end
        for plr in pairs(espObjects) do
            if not plr.Parent then removeEsp(plr) end
        end
    end

    -- ============================================================
    --   MAIN LOOP
    -- ============================================================

    connect(RunService.RenderStepped, function()
        if not running then return end
        if settings.aimlock and locked then
            if isAlive(locked.player) then
                locked.part = getAimPart(getCharacter(locked.player))
                aimAt(locked)
            else
                locked = nil
            end
        end
        checkTrigger()
        updateEsp()
    end)

    -- Aimlock key handler
    connect(UserInputService.InputBegan, function(input, gpe)
        if gpe then return end
        if input.KeyCode == settings.aimlockKey then
            if locked then
                locked = nil
            else
                locked = getBestTarget()
            end
        end
    end)

    connect(Players.PlayerRemoving, function(plr) removeEsp(plr) end)

    -- ============================================================
    --   UI
    -- ============================================================

    local CombatTab = Window:CreateTab("Combat", "combat")
    CombatTab:CreateSection("Aimlock")
    CombatTab:CreateToggle({Name="Aimlock",CurrentValue=false,Flag="SAaimlock",Callback=function(v) settings.aimlock=v; if not v then locked=nil end end})
    CombatTab:CreateDropdown({Name="Aim Part",Options={"Head","HumanoidRootPart"},CurrentOption={"Head"},MultipleOptions=false,Flag="SAaimPart",Callback=function(v) settings.aimPart=type(v)=="table" and v[1] or v end})
    CombatTab:CreateSlider({Name="FOV",Range={30,360},Increment=10,Suffix=" px",CurrentValue=120,Flag="SAfov",Callback=function(v) settings.fov=v end})
    CombatTab:CreateToggle({Name="Team Check",CurrentValue=true,Flag="SAteamCheck",Callback=function(v) settings.teamCheck=v end})

    CombatTab:CreateSection("Trigger Bot")
    CombatTab:CreateToggle({Name="Trigger Bot",CurrentValue=false,Flag="SAtrigger",Callback=function(v) settings.triggerBot=v end})
    CombatTab:CreateSlider({Name="Trigger Delay",Range={0,200},Increment=10,Suffix=" ms",CurrentValue=50,Flag="SAtriggerDelay",Callback=function(v) settings.triggerDelay=v/1000 end})

    local VisualTab = Window:CreateTab("Visual", "esp")
    VisualTab:CreateSection("ESP")
    VisualTab:CreateToggle({Name="ESP",CurrentValue=false,Flag="SAesp",Callback=function(v) settings.esp=v; if not v then clearAllEsp() end end})
    VisualTab:CreateToggle({Name="Show Distance",CurrentValue=true,Flag="SAespDist",Callback=function(v) settings.espShowDistance=v end})
    VisualTab:CreateToggle({Name="Show Health",CurrentValue=true,Flag="SAespHP",Callback=function(v) settings.espShowHealth=v end})

    local MiscTab = Window:CreateTab("Misc", "misc")
    MiscTab:CreateSection("Utilities")
    MiscTab:CreateButton({Name="Rejoin",Callback=function() pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId,game.JobId) end) end})
    MiscTab:CreateButton({Name="Server Hop",Callback=function() pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId) end) end})

    local function destroyScript()
        if not running then return end
        running = false; locked = nil
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
        table.clear(connections); clearAllEsp()
    end
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroyScript)
    end
end