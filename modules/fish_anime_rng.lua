--[[
    RAVEN HUB | Fish an Anime RNG
    PlaceId: 74729868188364 | GameId: 9582986239
    Version: v1.0.0

    Native Auto Fish | Backpack | Performance | Teleport | ESP
]]
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local CoreGui = game:GetService("CoreGui")
    local VirtualUser = game:GetService("VirtualUser")

    local player = Players.LocalPlayer
    local environment = getgenv()
    if type(environment.__RAVEN_FISH_ANIME) == "table"
        and type(environment.__RAVEN_FISH_ANIME.Destroy) == "function" then
        pcall(environment.__RAVEN_FISH_ANIME.Destroy)
    end

    local running = true
    local connections = {}
    local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
    local settings = {
        autoFish = false,
        autoEquipBest = false,
        autoSellAll = false,
        sellAtPercent = 95,
        performanceMode = false,
        characterEsp = false,
        pondEsp = false,
        espDistance = 750,
        antiAfk = true,
    }

    local function remote(name)
        return Remotes and Remotes:FindFirstChild(name)
    end

    local function call(name, ...)
        local object = remote(name)
        if not object then return false end
        local arguments = table.pack(...)
        if object:IsA("RemoteEvent") then
            return pcall(function() object:FireServer(unpack(arguments, 1, arguments.n)) end)
        elseif object:IsA("RemoteFunction") then
            local ok, result = pcall(function()
                return object:InvokeServer(unpack(arguments, 1, arguments.n))
            end)
            return ok, result
        end
        return false
    end

    local function notify(title, content)
        local ui = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if ui and type(ui.Notify) == "function" then
            pcall(function() ui:Notify({Title = title, Content = content, Duration = 5}) end)
        end
    end

    local nativeAutoFishSetter
    local function resolveNativeAutoFishSetter()
        if type(nativeAutoFishSetter) == "function" then return nativeAutoFishSetter end
        if type(getgc) ~= "function" or not debug or type(debug.info) ~= "function" then return nil end
        for _, value in ipairs(getgc(true)) do
            if type(value) == "function" then
                local ok, name = pcall(debug.info, value, "n")
                if ok and name == "setAutoFishEnabled" then
                    nativeAutoFishSetter = value
                    return value
                end
            end
        end
        return nil
    end

    local function setNativeAutoFish(enabled)
        settings.autoFish = enabled
        local setter = rawget(_G, "__AF_SetForcedAutoFish") or resolveNativeAutoFishSetter()
        if type(setter) == "function" then
            local ok = pcall(setter, enabled)
            if not enabled then call("FishingCancel") end
            return ok
        end
        if not enabled then call("FishingCancel") end
        return false
    end

    local function backpackUsage()
        return tonumber(player:GetAttribute("OwnedCharacters")) or 0,
            tonumber(player:GetAttribute("BackpackCap")) or 0
    end

    local function getPlot()
        local plotName = player:GetAttribute("PlotName")
        if plotName then
            for _, object in ipairs(workspace:GetDescendants()) do
                if object:IsA("Model") and object.Name == tostring(plotName) then return object end
            end
        end
        return nil
    end

    local function pivotPosition(object)
        if object:IsA("BasePart") then return object.Position end
        if object:IsA("Model") then return object:GetPivot().Position end
        local part = object:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function teleportToObject(object)
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local position = object and pivotPosition(object)
        if not root or not position then return false end
        root.CFrame = CFrame.new(position + Vector3.new(0, 4, 0))
        root.AssemblyLinearVelocity = Vector3.zero
        return true
    end

    local function findNamedObject(names)
        for _, object in ipairs(workspace:GetDescendants()) do
            local lower = object.Name:lower()
            for _, wanted in ipairs(names) do
                if lower:find(wanted, 1, true) and pivotPosition(object) then return object end
            end
        end
        return nil
    end

    local espFolder = Instance.new("Folder")
    espFolder.Name = "RavenFishAnimeESP"
    espFolder.Parent = (type(gethui) == "function" and gethui()) or CoreGui
    local espObjects = {}

    local function clearEsp(category)
        for object, data in pairs(espObjects) do
            if not category or data.category == category then
                pcall(function() data.highlight:Destroy() end)
                pcall(function() data.billboard:Destroy() end)
                espObjects[object] = nil
            end
        end
    end

    local function addEsp(object, category, text, color)
        if espObjects[object] or not object.Parent then return end
        local adornee = object:IsA("Model") and object or object:FindFirstAncestorOfClass("Model") or object
        local part = object:IsA("BasePart") and object or object:FindFirstChildWhichIsA("BasePart", true)
        if not part then return end
        local highlight = Instance.new("Highlight")
        highlight.Adornee = adornee
        highlight.FillColor = color
        highlight.FillTransparency = 0.75
        highlight.OutlineColor = color
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Parent = espFolder
        local billboard = Instance.new("BillboardGui")
        billboard.Adornee = part
        billboard.Size = UDim2.fromOffset(210, 34)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = settings.espDistance
        billboard.Parent = espFolder
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 13
        label.TextColor3 = color
        label.TextStrokeTransparency = 0.2
        label.Text = text
        label.Parent = billboard
        espObjects[object] = {category = category, highlight = highlight, billboard = billboard}
    end

    local function refreshEsp()
        clearEsp()
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        if settings.pondEsp then
            for _, object in ipairs(workspace:GetDescendants()) do
                if object:IsA("BasePart") and (object.Name == "PONDAREA1" or object.Name == "PONDAREA2")
                    and (object.Position - root.Position).Magnitude <= settings.espDistance then
                    addEsp(object, "pond", "[POND] " .. object.Name, Color3.fromRGB(70, 190, 255))
                end
            end
        end
        if settings.characterEsp then
            for _, object in ipairs(workspace:GetChildren()) do
                if object ~= character and (object.Name == "FishBall" or object:GetAttribute("Rarity")) then
                    local position = pivotPosition(object)
                    if position and (position - root.Position).Magnitude <= settings.espDistance then
                        local rarity = object:GetAttribute("Rarity")
                        addEsp(object, "character", "[CATCH] " .. object.Name .. (rarity and " | " .. rarity or ""), Color3.fromRGB(255, 210, 70))
                    end
                end
            end
        end
    end

    local MainTab = Window:CreateTab("🎣 Fishing", "fish")
    MainTab:CreateSection("Native Fishing")
    local fishStatus = MainTab:CreateLabel("Auto Fish: OFF")
    MainTab:CreateToggle({
        Name = "Auto Fish (Game Native)", CurrentValue = false, Flag = "FishAnimeAutoFish",
        Callback = function(value)
            local ok = setNativeAutoFish(value)
            fishStatus:Set("Auto Fish: " .. (value and ok and "ON" or "OFF"))
            if value and not ok then notify("🎣 Auto Fish", "Game fishing controller is not ready") end
        end,
    })
    MainTab:CreateButton({Name = "Cancel Current Cast", Callback = function() call("FishingCancel") end})

    local BackpackTab = Window:CreateTab("🎒 Backpack", "backpack")
    BackpackTab:CreateSection("Character Storage")
    local backpackLabel = BackpackTab:CreateLabel("Characters: loading...")
    BackpackTab:CreateToggle({
        Name = "Auto Equip Best", CurrentValue = false, Flag = "FishAnimeEquipBest",
        Callback = function(value) settings.autoEquipBest = value end,
    })
    BackpackTab:CreateToggle({
        Name = "Auto Sell All When Full", CurrentValue = false, Flag = "FishAnimeSellAll",
        Callback = function(value) settings.autoSellAll = value end,
    })
    BackpackTab:CreateSlider({
        Name = "Sell At", Range = {70, 100}, Increment = 5, CurrentValue = 95,
        Suffix = "%", Flag = "FishAnimeSellPercent",
        Callback = function(value) settings.sellAtPercent = value end,
    })
    BackpackTab:CreateButton({Name = "Equip Best Now", Callback = function() call("BackpackEquipBest") end})
    BackpackTab:CreateButton({Name = "Sell All Now", Callback = function() call("BackpackSellAllRequest") end})

    local VisualTab = Window:CreateTab("👁 Visual", "eye")
    VisualTab:CreateSection("ESP")
    VisualTab:CreateToggle({Name = "Pond ESP", CurrentValue = false, Flag = "FishAnimePondEsp", Callback = function(v) settings.pondEsp = v; if not v then clearEsp("pond") end end})
    VisualTab:CreateToggle({Name = "Catch ESP", CurrentValue = false, Flag = "FishAnimeCatchEsp", Callback = function(v) settings.characterEsp = v; if not v then clearEsp("character") end end})
    VisualTab:CreateSlider({Name = "ESP Distance", Range = {100, 2000}, Increment = 50, CurrentValue = 750, Suffix = " studs", Flag = "FishAnimeEspDistance", Callback = function(v) settings.espDistance = v end})
    VisualTab:CreateSection("Performance")
    VisualTab:CreateToggle({
        Name = "Game Performance Mode", CurrentValue = false, Flag = "FishAnimePerformance",
        Callback = function(value)
            settings.performanceMode = value
            call("SetPerformanceModeSetting", value)
        end,
    })

    local TravelTab = Window:CreateTab("📍 Travel", "map-pin")
    TravelTab:CreateSection("Teleport")
    TravelTab:CreateButton({Name = "My Plot", Callback = function() if not teleportToObject(getPlot()) then notify("Travel", "Plot not found") end end})
    TravelTab:CreateButton({Name = "Nearest Pond", Callback = function() teleportToObject(findNamedObject({"pondarea"})) end})
    TravelTab:CreateButton({Name = "Upgrades", Callback = function() teleportToObject(findNamedObject({"upgrade"})) end})
    TravelTab:CreateButton({Name = "Rebirth", Callback = function() teleportToObject(findNamedObject({"rebirth"})) end})
    TravelTab:CreateButton({Name = "Research", Callback = function() teleportToObject(findNamedObject({"research"})) end})

    local UtilityTab = Window:CreateTab("⚙ Utility", "settings")
    UtilityTab:CreateSection("Status")
    local statusLabel = UtilityTab:CreateLabel("Loading...")
    UtilityTab:CreateToggle({Name = "Anti AFK", CurrentValue = true, Flag = "FishAnimeAntiAfk", Callback = function(v) settings.antiAfk = v end})

    table.insert(connections, player.Idled:Connect(function()
        if settings.antiAfk then
            pcall(function()
                VirtualUser:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
                task.wait(0.2)
                VirtualUser:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame)
            end)
        end
    end))

    task.spawn(function()
        local actionAt, espAt, statusAt = 0, 0, 0
        while running do
            local now = os.clock()
            if now - actionAt >= 5 then
                actionAt = now
                local used, capacity = backpackUsage()
                if settings.autoEquipBest then call("BackpackEquipBest") end
                if settings.autoSellAll and capacity > 0 and used / capacity * 100 >= settings.sellAtPercent then
                    call("BackpackSellAllRequest")
                end
            end
            if now - espAt >= 2 and (settings.pondEsp or settings.characterEsp) then
                espAt = now
                pcall(refreshEsp)
            end
            if now - statusAt >= 1 then
                statusAt = now
                local used, capacity = backpackUsage()
                pcall(function() backpackLabel:Set(string.format("Characters: %d / %d", used, capacity)) end)
                pcall(function()
                    statusLabel:Set(string.format("Cash: %s | Gems: %s | Rebirths: %s",
                        tostring(player:GetAttribute("CashNumber") or 0),
                        tostring(player:GetAttribute("GemsNumber") or 0),
                        tostring(player:GetAttribute("Rebirths") or 0)))
                end)
            end
            task.wait(0.1)
        end
    end)

    local function destroy()
        if not running then return end
        running = false
        setNativeAutoFish(false)
        clearEsp()
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        pcall(function() if espFolder.Parent then espFolder:Destroy() end end)
        if environment.__RAVEN_FISH_ANIME and environment.__RAVEN_FISH_ANIME.Settings == settings then
            environment.__RAVEN_FISH_ANIME = nil
        end
    end

    environment.__RAVEN_FISH_ANIME = {
        Version = "v1.0.0", Settings = settings, Destroy = destroy,
        SetAutoFish = setNativeAutoFish, GetBackpackUsage = backpackUsage,
    }
    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then scriptInfo.registerCleanup(destroy) end
    notify("🎣 Fish an Anime RNG", "v1.0.0 loaded — native Auto Fish and low-rate automation")
end
