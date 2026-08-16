--[[
    RAVEN HUB Module - Phantom Forces
    Game: Phantom Forces (PlaceId: 292439477, GameId: 113491250)
    Developer: StyLiS Studios

    Features:
    - Enemy ESP (Box + Distance via Drawing API)
    - Team detection (auto-detect via closest model)
    - Safe implementation (no metatable hooks — undetectable)

    Module format: returns function(Window, runtimeInfo) for RAVENHUB loader

    NOTES:
    - PF uses obfuscated character names inside workspace/Players/[TeamFolder]/[Model]
    - PF does NOT use standard player.Character
    - PF detects __newindex/__namecall hooks on game metatable → DO NOT hook
    - Drawing API is safe and invisible to server
]]

return function(Window, runtimeInfo)
    -- Services
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local LP = Players.LocalPlayer
    local Camera = workspace.CurrentCamera

    -- State
    local State = {
        ESP = false,
        ESPDistance = true,
        ESPBoxes = true,
        ESPWallCheck = true,
        ESPHealthBar = true,
        MaxDistance = 1500,
        AutoSpot = false,
        AutoSpotInterval = 0.8,
    }
    local Connections = {}
    local Drawings = {}
    local MyTeamName = nil -- locked on first enable

    -- Raycast params for wall check
    local RayParams = RaycastParams.new()
    RayParams.FilterType = Enum.RaycastFilterType.Exclude
    local function buildRayFilter()
        local ignore = {}
        local pf = getPlayersFolder()
        if pf then table.insert(ignore, pf) end
        local ig = workspace:FindFirstChild("Ignore")
        if ig then table.insert(ignore, ig) end
        local roots = workspace:FindFirstChild("Roots")
        if roots then table.insert(ignore, roots) end
        RayParams.FilterDescendantsInstances = ignore
    end

    ---------------------------------------------------------------------------
    -- Utility
    ---------------------------------------------------------------------------

    local function getPlayersFolder()
        return workspace:FindFirstChild("Players")
    end

    local function detectMyTeam()
        -- PF uses obfuscated team folder names.
        -- Strategy: Check multiple close models. The team with the MOST
        -- models within 50 studs of camera is our team (we see teammates nearby).
        -- Fallback: single closest model.
        local pf = getPlayersFolder()
        if not pf then return nil end

        local myPos = Camera.CFrame.Position
        local NEARBY_RADIUS = 80
        local teamScores = {}

        for _, teamFolder in ipairs(pf:GetChildren()) do
            if not teamFolder:IsA("Folder") then continue end
            local nearbyCount = 0
            local closestInTeam = math.huge

            for _, model in ipairs(teamFolder:GetChildren()) do
                if model:IsA("Model") then
                    for _, part in ipairs(model:GetChildren()) do
                        if part:IsA("BasePart") then
                            local d = (part.Position - myPos).Magnitude
                            if d < NEARBY_RADIUS then
                                nearbyCount += 1
                            end
                            if d < closestInTeam then
                                closestInTeam = d
                            end
                            break
                        end
                    end
                end
            end

            teamScores[teamFolder.Name] = {
                nearby = nearbyCount,
                closest = closestInTeam,
            }
        end

        -- Pick team with most nearby models (teammates tend to be around us)
        local bestTeam, bestScore = nil, -1
        for name, score in pairs(teamScores) do
            if score.nearby > bestScore then
                bestScore = score.nearby
                bestTeam = name
            elseif score.nearby == bestScore then
                -- Tiebreak: closest model
                if score.closest < teamScores[bestTeam].closest then
                    bestTeam = name
                end
            end
        end

        return bestTeam
    end

    local function getModelBounds(model)
        local total = Vector3.zero
        local maxY, minY = -math.huge, math.huge
        local count = 0

        for _, c in ipairs(model:GetChildren()) do
            if c:IsA("BasePart") then
                local pos = c.Position
                total = total + pos
                if pos.Y > maxY then maxY = pos.Y end
                if pos.Y < minY then minY = pos.Y end
                count += 1
            end
        end

        if count == 0 then return nil end
        local center = total / count
        return {
            head = Vector3.new(center.X, maxY + 1.5, center.Z),
            feet = Vector3.new(center.X, minY - 0.5, center.Z),
            center = center,
        }
    end

    local function isVisible(targetPos)
        local origin = Camera.CFrame.Position
        local direction = targetPos - origin
        local dist = direction.Magnitude
        if dist < 1 then return true end
        local result = workspace:Raycast(origin, direction.Unit * (dist - 1), RayParams)
        return result == nil
    end

    ---------------------------------------------------------------------------
    -- Drawing ESP
    ---------------------------------------------------------------------------

    local function createDrawingESP()
        local esp = {
            box = Drawing.new("Square"),
            dist = Drawing.new("Text"),
            healthBar = Drawing.new("Line"),
            healthBg = Drawing.new("Line"),
        }
        esp.box.Thickness = 1.5
        esp.box.Filled = false
        esp.box.Color = Color3.fromRGB(255, 50, 50)
        esp.box.Visible = false

        esp.dist.Size = 12
        esp.dist.Center = true
        esp.dist.Outline = true
        esp.dist.Color = Color3.fromRGB(255, 255, 255)
        esp.dist.Visible = false

        esp.healthBar.Thickness = 2
        esp.healthBar.Color = Color3.fromRGB(50, 255, 50)
        esp.healthBar.Visible = false

        esp.healthBg.Thickness = 4
        esp.healthBg.Color = Color3.fromRGB(30, 30, 30)
        esp.healthBg.Visible = false

        return esp
    end

    local function hideDrawing(esp)
        for _, d in pairs(esp) do
            d.Visible = false
        end
    end

    local function removeAllDrawings()
        for key, esp in pairs(Drawings) do
            for _, d in pairs(esp) do
                pcall(function() d:Remove() end)
            end
        end
        Drawings = {}
    end

    ---------------------------------------------------------------------------
    -- ESP Update Loop
    ---------------------------------------------------------------------------

    local function startESP()
        if Connections.espLoop then return end

        -- Lock team on first enable
        if not MyTeamName then
            MyTeamName = detectMyTeam()
        end

        -- Build raycast filter
        buildRayFilter()

        Connections.espLoop = RunService.RenderStepped:Connect(function()
            if not State.ESP then
                for _, esp in pairs(Drawings) do hideDrawing(esp) end
                return
            end

            local pf = getPlayersFolder()
            if not pf then return end

            -- Re-detect team periodically if somehow nil
            if not MyTeamName then
                MyTeamName = detectMyTeam()
                if not MyTeamName then return end
            end

            -- Hide all first
            for _, esp in pairs(Drawings) do hideDrawing(esp) end

            local myPos = Camera.CFrame.Position

            for _, teamFolder in ipairs(pf:GetChildren()) do
                if not teamFolder:IsA("Folder") then continue end
                if teamFolder.Name == MyTeamName then continue end -- skip my team

                for _, model in ipairs(teamFolder:GetChildren()) do
                    if not model:IsA("Model") then continue end

                    local key = model.Name
                    if not Drawings[key] then
                        Drawings[key] = createDrawingESP()
                    end
                    local esp = Drawings[key]

                    local bounds = getModelBounds(model)
                    if not bounds then continue end

                    local dist = (bounds.center - myPos).Magnitude
                    if dist > State.MaxDistance or dist < 3 then continue end

                    local headScreen, onScreen = Camera:WorldToViewportPoint(bounds.head)
                    local feetScreen = Camera:WorldToViewportPoint(bounds.feet)

                    if not onScreen then continue end

                    local boxHeight = math.abs(feetScreen.Y - headScreen.Y)
                    local boxWidth = boxHeight * 0.45
                    if boxHeight < 4 then continue end

                    -- Wall check: green = visible, red = behind wall
                    local visible = true
                    if State.ESPWallCheck then
                        visible = isVisible(bounds.center)
                    end
                    local boxColor = visible
                        and Color3.fromRGB(50, 255, 50)
                        or Color3.fromRGB(255, 50, 50)

                    -- Box
                    if State.ESPBoxes then
                        esp.box.Size = Vector2.new(boxWidth, boxHeight)
                        esp.box.Position = Vector2.new(headScreen.X - boxWidth / 2, headScreen.Y)
                        esp.box.Color = boxColor
                        esp.box.Visible = true
                    end

                    -- Distance
                    if State.ESPDistance then
                        esp.dist.Text = math.floor(dist) .. "m"
                        esp.dist.Position = Vector2.new(headScreen.X, feetScreen.Y + 2)
                        esp.dist.Visible = true
                    end

                    -- Health bar (visual only — PF does not expose HP to client)
                    if State.ESPHealthBar then
                        local barX = headScreen.X - boxWidth / 2 - 5
                        esp.healthBg.From = Vector2.new(barX, feetScreen.Y)
                        esp.healthBg.To = Vector2.new(barX, headScreen.Y)
                        esp.healthBg.Visible = true

                        esp.healthBar.From = Vector2.new(barX, feetScreen.Y)
                        esp.healthBar.To = Vector2.new(barX, headScreen.Y)
                        esp.healthBar.Color = Color3.fromRGB(50, 255, 50)
                        esp.healthBar.Visible = true
                    end
                end
            end
        end)
    end

    local function stopESP()
        if Connections.espLoop then
            Connections.espLoop:Disconnect()
            Connections.espLoop = nil
        end
        removeAllDrawings()
    end

    ---------------------------------------------------------------------------
    -- UI (MacLib Tab)
    ---------------------------------------------------------------------------

    local Tab = Window:CreateTab("Phantom Forces", "rbxassetid://7733960981")

    -- ESP Section
    Tab:CreateSection("ESP")

    Tab:CreateToggle({
        Name = "Enemy ESP",
        CurrentValue = State.ESP,
        Callback = function(value)
            State.ESP = value
            if value then
                startESP()
            else
                for _, esp in pairs(Drawings) do hideDrawing(esp) end
            end
        end,
    })

    Tab:CreateToggle({
        Name = "Show Boxes",
        CurrentValue = State.ESPBoxes,
        Callback = function(value)
            State.ESPBoxes = value
        end,
    })

    Tab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = State.ESPDistance,
        Callback = function(value)
            State.ESPDistance = value
        end,
    })

    Tab:CreateToggle({
        Name = "Wall Check (Green/Red)",
        CurrentValue = State.ESPWallCheck,
        Callback = function(value)
            State.ESPWallCheck = value
        end,
    })

    Tab:CreateToggle({
        Name = "Health Bar",
        CurrentValue = State.ESPHealthBar,
        Callback = function(value)
            State.ESPHealthBar = value
        end,
    })

    Tab:CreateSlider({
        Name = "Max Distance",
        Range = {100, 3000},
        Increment = 50,
        CurrentValue = State.MaxDistance,
        Suffix = "studs",
        Callback = function(value)
            State.MaxDistance = value
        end,
    })

    -- Team Section
    Tab:CreateSection("Team")

    Tab:CreateButton({
        Name = "Re-detect My Team",
        Callback = function()
            MyTeamName = detectMyTeam()
            if runtimeInfo and runtimeInfo.hubUI then
                pcall(function()
                    game:GetService("StarterGui"):SetCore("SendNotification", {
                        Title = "RAVEN HUB",
                        Text = "Team locked: " .. tostring(MyTeamName and MyTeamName:sub(1, 8) or "nil"),
                        Duration = 3,
                    })
                end)
            end
        end,
    })

    -- Info Section
    Tab:CreateSection("Info")
    Tab:CreateLabel("PF ESP uses Drawing API (safe)")
    Tab:CreateLabel("No metatable hooks (undetectable)")
    Tab:CreateLabel("Team auto-detected on first enable")

    ---------------------------------------------------------------------------
    -- Auto Spot
    ---------------------------------------------------------------------------

    local VIM = game:GetService("VirtualInputManager")
    local UIS = game:GetService("UserInputService")
    local AutoSpotThread = nil

    local function startAutoSpot()
        if AutoSpotThread then return end
        AutoSpotThread = task.spawn(function()
            while State.AutoSpot do
                -- Only spot when not shooting and not ADS
                local shooting = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                local aiming = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

                if not shooting and not aiming then
                    VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end

                task.wait(State.AutoSpotInterval)
            end
        end)
    end

    local function stopAutoSpot()
        State.AutoSpot = false
        if AutoSpotThread then
            pcall(function() task.cancel(AutoSpotThread) end)
            AutoSpotThread = nil
        end
    end

    Tab:CreateSection("Auto Spot")

    Tab:CreateToggle({
        Name = "Auto Spot (E key)",
        CurrentValue = State.AutoSpot,
        Callback = function(value)
            State.AutoSpot = value
            if value then
                startAutoSpot()
            else
                stopAutoSpot()
            end
        end,
    })

    Tab:CreateSlider({
        Name = "Spot Interval",
        Range = {0.3, 3},
        Increment = 0.1,
        CurrentValue = State.AutoSpotInterval,
        Suffix = "s",
        Callback = function(value)
            State.AutoSpotInterval = value
        end,
    })

    Tab:CreateLabel("⚠️ Spots only when not shooting/ADS")
    Tab:CreateLabel("⚠️ Has brief arm animation (PF limitation)")

    ---------------------------------------------------------------------------
    -- Cleanup
    ---------------------------------------------------------------------------

    local function cleanup()
        stopESP()
        stopAutoSpot()
        for _, conn in pairs(Connections) do
            pcall(function() conn:Disconnect() end)
        end
        Connections = {}
    end

    -- Register cleanup with RAVENHUB
    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(cleanup)
    end

    return cleanup
end
