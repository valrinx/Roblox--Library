--[[
    RAVEN HUB | TTK Testing [MAP VOTING]
    PlaceId: 120189115846709 | GameId: 10090256806
    Version: v1.0.0

    Player ESP | Match Dashboard | Map Tracker | Visibility QoL
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local RunService = game:GetService("RunService")
    local CoreGui = game:GetService("CoreGui")
    local VirtualUser = game:GetService("VirtualUser")

    local player = Players.LocalPlayer
    local environment = getgenv()
    if type(environment.__RAVEN_TTK) == "table" and type(environment.__RAVEN_TTK.Destroy) == "function" then
        pcall(environment.__RAVEN_TTK.Destroy)
    end

    local running = true
    local connections = {}
    local settings = {
        playerEsp = false, visibleCheck = true, showDistance = true, showHealth = true,
        espMaxDistance = 1500, fullbright = false, removeSmudges = false,
        fovOverride = false, fieldOfView = 86, antiAfk = true,
    }
    local originalLighting = {
        Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient, GlobalShadows = Lighting.GlobalShadows,
    }

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function() ui:Notify({Title = title, Content = content, Duration = 5}) end)
        end
    end

    local function characterRoot(character)
        return character and (character:FindFirstChild("HumanoidRootPart")
            or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"))
    end

    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenTTKESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui
    local espObjects = {}

    local function removeEsp(target)
        local data = espObjects[target]
        if not data then return end
        pcall(function() data.highlight:Destroy() end)
        pcall(function() data.billboard:Destroy() end)
        for _, adornment in ipairs(data.adornments or {}) do pcall(function() adornment:Destroy() end) end
        espObjects[target] = nil
    end

    local function clearEsp()
        for target in pairs(espObjects) do removeEsp(target) end
    end

    local function addEsp(targetPlayer)
        local character = targetPlayer.Character
        local root = characterRoot(character)
        if not character or not root then return end
        local mercPlayers = workspace:FindFirstChild("MercPlayers")
        local visualModel = mercPlayers and mercPlayers:FindFirstChild("MercVisual_" .. targetPlayer.Name)
        local chamModel = visualModel or character
        local highlight = Instance.new("Highlight")
        highlight.Name = "RavenTTKPlayer"
        highlight.Adornee = chamModel
        highlight.FillColor = Color3.fromRGB(255, 70, 70)
        highlight.FillTransparency = 0.78
        highlight.OutlineColor = Color3.fromRGB(255, 235, 235)
        highlight.OutlineTransparency = 0.05
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = espFolder
        local adornments = {}
        for _, part in ipairs(chamModel:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local box = Instance.new("BoxHandleAdornment")
                box.Name = "RavenTTKCham"
                box.Adornee = part
                box.Size = part.Size + Vector3.new(0.03, 0.03, 0.03)
                box.Color3 = Color3.fromRGB(255, 70, 70)
                box.Transparency = 0.72
                box.AlwaysOnTop = true
                box.ZIndex = 5
                box.Parent = espFolder
                adornments[#adornments + 1] = box
            end
        end
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RavenTTKLabel"
        billboard.Adornee = root
        billboard.Size = UDim2.fromOffset(220, 48)
        billboard.StudsOffset = Vector3.new(0, 3.6, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = settings.espMaxDistance
        billboard.Parent = espFolder
        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextColor3 = Color3.fromRGB(255, 100, 100)
        label.TextStrokeTransparency = 0.15
        label.TextWrapped = true
        label.Parent = billboard
        espObjects[targetPlayer] = {highlight = highlight, billboard = billboard, label = label, character = character, visualModel = visualModel, adornments = adornments}
    end

    local function isCharacterVisible(character)
        if not settings.visibleCheck then return true end
        local camera = workspace.CurrentCamera
        if not camera then return false end
        local origin = camera.CFrame.Position
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = {player.Character, camera, espFolder}
        rayParams.IgnoreWater = true
        local candidates = {
            character:FindFirstChild("Head"), character:FindFirstChild("UpperTorso"),
            character:FindFirstChild("Torso"), character:FindFirstChild("HumanoidRootPart"),
        }
        local mercPlayers = workspace:FindFirstChild("MercPlayers")
        local owner = Players:GetPlayerFromCharacter(character)
        local visualModel = owner and mercPlayers and mercPlayers:FindFirstChild("MercVisual_" .. owner.Name)
        local hitboxModel = owner and mercPlayers and mercPlayers:FindFirstChild("MercHitboxes_" .. owner.Name)
        for _, part in ipairs(candidates) do
            if part and part:IsA("BasePart") then
                local result = workspace:Raycast(origin, part.Position - origin, rayParams)
                if not result or result.Instance:IsDescendantOf(character)
                    or (visualModel and result.Instance:IsDescendantOf(visualModel))
                    or (hitboxModel and result.Instance:IsDescendantOf(hitboxModel)) then return true end
            end
        end
        return false
    end

    local function refreshPlayerEsp()
        if not settings.playerEsp then clearEsp() return end
        local localRoot = characterRoot(player.Character)
        if not localRoot then return end
        local seen = {}
        for _, target in ipairs(Players:GetPlayers()) do
            if target ~= player then
                local root = characterRoot(target.Character)
                local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
                if root and humanoid and humanoid.Health > 0 then
                    local distance = (root.Position - localRoot.Position).Magnitude
                    if distance <= settings.espMaxDistance then
                        seen[target] = true
                        local data = espObjects[target]
                        if not data or data.character ~= target.Character then
                            removeEsp(target)
                            addEsp(target)
                            data = espObjects[target]
                        end
                        if data then
                            local visible = isCharacterVisible(target.Character)
                            local color = visible and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 70, 70)
                            local parts = {target.DisplayName}
                            if settings.showHealth then parts[#parts + 1] = string.format("HP %d", math.max(0, math.floor(humanoid.Health))) end
                            if settings.showDistance then parts[#parts + 1] = string.format("%dm", math.floor(distance / 3.571)) end
                            if settings.visibleCheck then parts[#parts + 1] = visible and "VISIBLE" or "HIDDEN" end
                            data.label.Text = table.concat(parts, " | ")
                            data.label.TextColor3 = color
                            data.highlight.FillColor = color
                            data.highlight.OutlineColor = color
                            for _, adornment in ipairs(data.adornments) do adornment.Color3 = color end
                            data.billboard.MaxDistance = settings.espMaxDistance
                        end
                    end
                end
            end
        end
        for target in pairs(espObjects) do if not seen[target] then removeEsp(target) end end
    end

    local function applyFullbright()
        if settings.fullbright then
            Lighting.Brightness = 3
            Lighting.Ambient = Color3.fromRGB(180, 180, 180)
            Lighting.OutdoorAmbient = Color3.fromRGB(180, 180, 180)
            Lighting.GlobalShadows = false
        else
            for property, value in pairs(originalLighting) do pcall(function() Lighting[property] = value end) end
        end
    end

    local function applySmudges()
        local gui = player:FindFirstChildOfClass("PlayerGui")
        local smudges = gui and gui:FindFirstChild("Smudges")
        if smudges and smudges:IsA("ScreenGui") then smudges.Enabled = not settings.removeSmudges end
    end

    local EspTab = Window:CreateTab("👁 ESP", "eye")
    EspTab:CreateSection("Players — FFA")
    EspTab:CreateToggle({Name = "Player ESP", CurrentValue = false, Flag = "TTKPlayerEsp", Callback = function(v) settings.playerEsp = v; if not v then clearEsp() end end})
    EspTab:CreateToggle({Name = "Visible Check", CurrentValue = true, Flag = "TTKVisibleCheck", Callback = function(v) settings.visibleCheck = v end})
    EspTab:CreateToggle({Name = "Show Health", CurrentValue = true, Flag = "TTKEspHealth", Callback = function(v) settings.showHealth = v end})
    EspTab:CreateToggle({Name = "Show Distance", CurrentValue = true, Flag = "TTKEspDistance", Callback = function(v) settings.showDistance = v end})
    EspTab:CreateSlider({Name = "ESP Distance", Range = {100, 3000}, Increment = 100, CurrentValue = 1500, Suffix = " studs", Flag = "TTKEspMax", Callback = function(v) settings.espMaxDistance = v end})

    local VisualTab = Window:CreateTab("🌙 Visual", "sun")
    VisualTab:CreateSection("Visibility")
    VisualTab:CreateToggle({Name = "Fullbright", CurrentValue = false, Flag = "TTKFullbright", Callback = function(v) settings.fullbright = v; applyFullbright() end})
    VisualTab:CreateToggle({Name = "Remove Screen Smudges", CurrentValue = false, Flag = "TTKSmudges", Callback = function(v) settings.removeSmudges = v; applySmudges() end})
    VisualTab:CreateToggle({Name = "FOV Override", CurrentValue = false, Flag = "TTKFovOverride", Callback = function(v) settings.fovOverride = v end})
    VisualTab:CreateSlider({Name = "Field of View", Range = {60, 120}, Increment = 1, CurrentValue = 86, Suffix = "°", Flag = "TTKFov", Callback = function(v) settings.fieldOfView = v end})

    local MatchTab = Window:CreateTab("📊 Match", "activity")
    MatchTab:CreateSection("Live State")
    local matchLabel = MatchTab:CreateLabel("Match: loading...")
    local scoreLabel = MatchTab:CreateLabel("Score: loading...")
    local weaponLabel = MatchTab:CreateLabel("Weapon: loading...")
    MatchTab:CreateSection("Map Voting")
    local mapLabel = MatchTab:CreateLabel("Map: loading...")

    local UtilityTab = Window:CreateTab("⚙ Utility", "settings")
    UtilityTab:CreateSection("Player")
    UtilityTab:CreateToggle({Name = "Anti AFK", CurrentValue = true, Flag = "TTKAntiAfk", Callback = function(v) settings.antiAfk = v end})
    UtilityTab:CreateButton({Name = "Copy Server JobId", Callback = function() pcall(function() if setclipboard then setclipboard(game.JobId) end end); notify("TTK", "Server JobId copied") end})

    connections[#connections + 1] = player.Idled:Connect(function()
        if settings.antiAfk then
            pcall(function()
                VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
                task.wait(0.2)
                VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
            end)
        end
    end)
    connections[#connections + 1] = RunService.RenderStepped:Connect(function()
        if settings.fovOverride and workspace.CurrentCamera then workspace.CurrentCamera.FieldOfView = settings.fieldOfView end
    end)

    task.spawn(function()
        local espAt, statusAt, visualAt = 0, 0, 0
        while running do
            local now = os.clock()
            if now - espAt >= 0.5 then espAt = now; pcall(refreshPlayerEsp) end
            if now - visualAt >= 2 then visualAt = now; if settings.fullbright then applyFullbright() end; applySmudges() end
            if now - statusAt >= 0.5 then
                statusAt = now
                local phase = workspace:GetAttribute("Flow_Phase") or workspace:GetAttribute("MatchState") or "Unknown"
                local mode = workspace:GetAttribute("Flow_Mode") or workspace:GetAttribute("GameMode") or "Unknown"
                local map = workspace:GetAttribute("Flow_Map") or workspace:GetAttribute("CurrentMapName") or "Unknown"
                local limit = workspace:GetAttribute("ModeScoreLimit") or "?"
                local endsAt = tonumber(workspace:GetAttribute("MapRoundEndsAt"))
                local remaining = endsAt and math.max(0, math.floor(endsAt - workspace:GetServerTimeNow())) or 0
                pcall(function() matchLabel:Set(string.format("%s | %s | %02d:%02d", tostring(phase), tostring(mode), math.floor(remaining / 60), remaining % 60)) end)
                pcall(function() scoreLabel:Set(string.format("Kills: %s | Deaths: %s | Limit: %s", tostring(player:GetAttribute("Kills") or 0), tostring(player:GetAttribute("Deaths") or 0), tostring(limit))) end)
                pcall(function() weaponLabel:Set(string.format("Weapon: %s | Slot: %s | Flashbang: %s", tostring(player:GetAttribute("CurrentWeapon") or "None"), tostring(player:GetAttribute("SelectedSlot") or "None"), tostring(player:GetAttribute("ThrowableAmmo_Flashbang") or 0))) end)
                pcall(function() mapLabel:Set(string.format("Map: %s | Location: %s", tostring(map), tostring(workspace:GetAttribute("Flow_Location") or "Unknown"))) end)
            end
            task.wait(0.1)
        end
    end)

    local function destroy()
        if not running then return end
        running = false
        clearEsp()
        settings.fullbright = false
        applyFullbright()
        settings.removeSmudges = false
        pcall(applySmudges)
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        pcall(function() if espFolder.Parent then espFolder:Destroy() end end)
        if environment.__RAVEN_TTK and environment.__RAVEN_TTK.Settings == settings then environment.__RAVEN_TTK = nil end
    end

    environment.__RAVEN_TTK = {Version = "v1.0.0", Settings = settings, Destroy = destroy, RefreshESP = refreshPlayerEsp}
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then scriptInfo.registerCleanup(destroy) end
    notify("🎯 TTK Testing", "v1.0.0 loaded — FFA ESP, match dashboard and visibility tools")
end
