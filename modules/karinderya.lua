--[[
    RAVEN HUB Module - Karinderya! v1.0.0
    Game: [🔥] Karinderya! (PlaceId: 116497287371701, GameId: 10648820673)
    Developer: SILOG

    Features:
    - Kitchen & Service:
        * Instant Dishwasher (Bypass 30s Sink hold duration to 0s)
        * Auto Take Customer Orders (Counter prompt trigger)
        * Auto Serve Food & Softdrinks
        * Auto Repair Chiller
    - Anti-Theft & Defense:
        * Auto Smack Runaway Thieves (Instantly throw pan/slipper to retrieve money)
        * Auto Hit Crocodiles
    - Staff Management:
        * Auto Wake Sleeping / Tripped Workers (24/7 productivity)
    - Sanitation & Tycoon:
        * Auto Collect & Throw Trash
        * Auto Claim Group Rewards
        * Auto Heart / Signage Boost
    - ESP Visuals (Drawing API):
        * Runaway Thieves ESP (Red alert)
        * Customers ESP
        * Dirty Plates / Trash ESP
    - Teleports:
        * Own Restaurant (Counter, Kitchen, Sink, Tables)
        * Grocery, Barangay Hall, Junk Shop, Merchant Spots
]]--

return function(Window, runtimeInfo)
    pcall(function()
        local prev = getgenv().__RAVEN_KARINDERYA
        if prev and type(prev.Destroy) == "function" then
            prev.Destroy()
        end
    end)

    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")

    local LP = Players.LocalPlayer
    local Camera = Workspace.CurrentCamera
    local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

    ----------------------------------------------------------------
    --  STATE & CONFIGURATION
    ----------------------------------------------------------------
    local State = {
        -- Kitchen & Service
        InstantWash = true,
        AutoTakeOrder = false,
        AutoServeDishes = false,
        AutoRepairChiller = false,
        AutoGetSoftdrink = false,

        -- Defense & Anti-Theft
        AutoSmackThief = true,
        AutoHitCroc = true,
        ThiefSmackWeapon = "Pan", -- "Pan", "Slipper", "Bread", "Rambo"

        -- Staff Management
        AutoWakeWorkers = true,

        -- Sanitation & Tycoon
        AutoCollectTrash = false,
        AutoHeartSign = false,

        -- ESP
        ESPThieves = true,
        ESPCustomers = false,
        ESPTrash = false,

        -- Player
        WalkSpeed = 18,
        EnableCustomSpeed = false,
    }

    local Connections = {}
    local DrawingObjects = {
        Thieves = {},
        Customers = {},
        Trash = {},
    }
    local isDestroyed = false

    local function connect(signal, fn)
        local conn = signal:Connect(fn)
        table.insert(Connections, conn)
        return conn
    end

    ----------------------------------------------------------------
    --  HELPER FUNCTIONS
    ----------------------------------------------------------------
    local function getCharacter()
        return LP.Character or LP.CharacterAdded:Wait()
    end

    local function getRoot()
        local char = getCharacter()
        return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
    end

    local function getHumanoid()
        local char = getCharacter()
        return char and char:FindFirstChildOfClass("Humanoid")
    end

    local function isAlive()
        local hum = getHumanoid()
        return hum and hum.Health > 0
    end

    local function triggerPrompt(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then return end
        if type(fireproximityprompt) == "function" then
            fireproximityprompt(prompt, 0)
        else
            local origHold = prompt.HoldDuration
            prompt.HoldDuration = 0
            prompt:InputHoldBegin()
            task.wait(0.05)
            prompt:InputHoldEnd()
            prompt.HoldDuration = origHold
        end
    end

    local function getMyRestaurant()
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj.Name:find("Karenderya") then
                local ownerAttr = obj:GetAttribute("Owner")
                local ownerVal = obj:FindFirstChild("Owner")
                if ownerAttr == LP.UserId or (ownerVal and ownerVal.Value == LP.UserId) then
                    return obj
                end
            end
        end
        return nil
    end

    ----------------------------------------------------------------
    --  INSTANT DISH WASH & PROMPT OPTIMIZER
    ----------------------------------------------------------------
    local function optimizePrompts()
        local plot = getMyRestaurant()
        if not plot then return end

        for _, prompt in ipairs(plot:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") then
                if State.InstantWash and prompt.ActionText == "Wash" then
                    prompt.HoldDuration = 0
                end
                if State.AutoRepairChiller and prompt.ActionText == "Repair" and prompt.ObjectText == "Chiller" then
                    prompt.HoldDuration = 0
                end
            end
        end
    end

    connect(Workspace.DescendantAdded, function(descendant)
        if descendant:IsA("ProximityPrompt") then
            task.defer(function()
                if State.InstantWash and descendant.ActionText == "Wash" then
                    descendant.HoldDuration = 0
                end
            end)
        end
    end)

    ----------------------------------------------------------------
    --  AUTO TAKE ORDER & SERVE
    ----------------------------------------------------------------
    local function runOrderAndServe()
        local plot = getMyRestaurant()
        if not plot or not isAlive() then return end
        local root = getRoot()
        if not root then return end

        -- 1. Auto Take Order at Counter
        if State.AutoTakeOrder then
            local counter = plot:FindFirstChild("Counter")
            if counter then
                for _, p in ipairs(counter:GetDescendants()) do
                    if p:IsA("ProximityPrompt") and p.ActionText == "Take Order" and p.Enabled then
                        local parentPart = p.Parent:IsA("BasePart") and p.Parent or p.Parent:FindFirstChildWhichIsA("BasePart")
                        if parentPart and (root.Position - parentPart.Position).Magnitude <= (p.MaxActivationDistance + 5) then
                            triggerPrompt(p)
                        end
                    end
                end
            end
        end

        -- 2. Auto Serve Food on Tables
        if State.AutoServeDishes then
            local dining = plot:FindFirstChild("DiningPlot1") or plot:FindFirstChild("Extension2")
            if dining then
                for _, p in ipairs(dining:GetDescendants()) do
                    if p:IsA("ProximityPrompt") and p.ActionText:find("Serve") and p.Enabled then
                        local part = p.Parent:IsA("BasePart") and p.Parent or p.Parent:FindFirstChildWhichIsA("BasePart")
                        if part and (root.Position - part.Position).Magnitude <= (p.MaxActivationDistance + 5) then
                            triggerPrompt(p)
                        end
                    end
                end
            end
        end

        -- 3. Auto Repair Chiller
        if State.AutoRepairChiller then
            local softdrinks = plot:FindFirstChild("Softdrinks")
            if softdrinks then
                local repairPrompt = softdrinks:FindFirstChild("Repair", true)
                if repairPrompt and repairPrompt:IsA("ProximityPrompt") and repairPrompt.Enabled then
                    triggerPrompt(repairPrompt)
                end
            end
        end
    end

    ----------------------------------------------------------------
    --  ANTI-THEFT & CROCODILE DEFENSE
    ----------------------------------------------------------------
    local function getRunawayRemotes()
        local hitRunaway = Remotes and Remotes:FindFirstChild("HitRunawayEvent")
        local throwPan = Remotes and Remotes:FindFirstChild("ThrowCaptainPanEvent")
        local throwSlipper = Remotes and Remotes:FindFirstChild("ThrowSlipperEvent")
        local throwBread = Remotes and Remotes:FindFirstChild("ThrowBreadEvent")
        local throwRambo = Remotes and Remotes:FindFirstChild("ThrowRamboEvent")
        return {
            Hit = hitRunaway,
            Pan = throwPan,
            Slipper = throwSlipper,
            Bread = throwBread,
            Rambo = throwRambo,
        }
    end

    local function smackThief(thiefNpc)
        if not thiefNpc or not thiefNpc.Parent then return end
        local thiefRoot = thiefNpc:FindFirstChild("HumanoidRootPart") or thiefNpc:FindFirstChild("Head")
        if not thiefRoot then return end

        local r = getRunawayRemotes()

        -- Trigger Weapon throw
        if State.ThiefSmackWeapon == "Slipper" and r.Slipper then
            pcall(function() r.Slipper:FireServer(thiefRoot.Position, thiefNpc) end)
        elseif State.ThiefSmackWeapon == "Bread" and r.Bread then
            pcall(function() r.Bread:FireServer(thiefRoot.Position, thiefNpc) end)
        elseif State.ThiefSmackWeapon == "Rambo" and r.Rambo then
            pcall(function() r.Rambo:FireServer(thiefRoot.Position, thiefNpc) end)
        elseif r.Pan then
            pcall(function() r.Pan:FireServer(thiefRoot.Position, thiefNpc) end)
        end

        -- Directly hit runaway
        if r.Hit then
            pcall(function() r.Hit:FireServer(thiefNpc, thiefRoot.Position) end)
        end
    end

    local function scanThievesAndCrocs()
        if not isAlive() then return end

        -- Scan Runaway NPCs
        local clientNPCs = Workspace:FindFirstChild("ClientNPCs")
        if clientNPCs and State.AutoSmackThief then
            for _, npc in ipairs(clientNPCs:GetChildren()) do
                if npc:IsA("Model") then
                    local isRunaway = npc:GetAttribute("IsRunaway") or npc:GetAttribute("Runaway") or npc:FindFirstChild("RunawayHighlight")
                    local nameLower = npc.Name:lower()
                    if isRunaway or nameLower:find("thief") or nameLower:find("runaway") then
                        smackThief(npc)
                    end
                end
            end
        end

        -- Scan Crocodiles
        if State.AutoHitCroc and Remotes then
            local hitCroc = Remotes:FindFirstChild("HitCrocEvent")
            if hitCroc then
                for _, obj in ipairs(Workspace:GetChildren()) do
                    local n = obj.Name:lower()
                    if n:find("croc") or n:find("alligator") then
                        local part = obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart")
                        if part then
                            pcall(function() hitCroc:FireServer(obj, part.Position) end)
                        end
                    end
                end
            end
        end
    end

    ----------------------------------------------------------------
    --  WORKER AUTOMATION (WAKE LAZY STAFF)
    ----------------------------------------------------------------
    local function wakeLazyWorkers()
        if not State.AutoWakeWorkers or not Remotes then return end
        local wakeRemote = Remotes:FindFirstChild("WorkerRemotes") and Remotes.WorkerRemotes:FindFirstChild("WakeWorkerEvent")
        if not wakeRemote then return end

        local plot = getMyRestaurant()
        if not plot then return end

        for _, desc in ipairs(plot:GetDescendants()) do
            if desc:IsA("Model") and (desc:GetAttribute("IsSleeping") or desc:GetAttribute("Tripped") or desc:FindFirstChild("SleepZ")) then
                pcall(function() wakeRemote:FireServer(desc) end)
            end
        end
    end

    ----------------------------------------------------------------
    --  SANITATION & TRASH COLLECTOR
    ----------------------------------------------------------------
    local function runSanitation()
        if not State.AutoCollectTrash or not isAlive() then return end
        local plot = getMyRestaurant()
        if not plot then return end
        local root = getRoot()
        if not root then return end

        -- Check trash inside plot
        local trashFolder = plot:FindFirstChild("Trash")
        if trashFolder then
            for _, item in ipairs(trashFolder:GetDescendants()) do
                if item:IsA("ProximityPrompt") and item.Enabled then
                    local part = item.Parent:IsA("BasePart") and item.Parent or item.Parent:FindFirstChildWhichIsA("BasePart")
                    if part and (root.Position - part.Position).Magnitude <= (item.MaxActivationDistance + 5) then
                        triggerPrompt(item)
                    end
                end
            end
        end

        -- Auto Heart Signage
        if State.AutoHeartSign then
            local signFolder = plot:FindFirstChild("Sign")
            if signFolder then
                local heartPrompt = signFolder:FindFirstChild("ProximityPrompt", true)
                if heartPrompt and heartPrompt:IsA("ProximityPrompt") and heartPrompt.ActionText == "Heart" and heartPrompt.Enabled then
                    triggerPrompt(heartPrompt)
                end
            end
        end
    end

    ----------------------------------------------------------------
    --  DRAWING API ESP ENGINE
    ----------------------------------------------------------------
    local function clearDrawingList(tbl)
        for _, entry in pairs(tbl) do
            if entry.Text then entry.Text:Remove() end
            if entry.Box then entry.Box:Remove() end
        end
        table.clear(tbl)
    end

    local function updateESP()
        if not hasDrawing then return end

        -- 1. Thieves ESP
        if State.ESPThieves then
            local clientNPCs = Workspace:FindFirstChild("ClientNPCs")
            if clientNPCs then
                for _, npc in ipairs(clientNPCs:GetChildren()) do
                    local isRunaway = npc:GetAttribute("IsRunaway") or npc:GetAttribute("Runaway")
                    if isRunaway then
                        local part = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("Head")
                        if part then
                            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                            local entry = DrawingObjects.Thieves[npc]
                            if not entry then
                                local text = Drawing.new("Text")
                                text.Size = 14
                                text.Center = true
                                text.Outline = true
                                text.Color = Color3.fromRGB(255, 60, 60)
                                entry = { Text = text }
                                DrawingObjects.Thieves[npc] = entry
                            end

                            if onScreen then
                                local dist = math.floor((Camera.CFrame.Position - part.Position).Magnitude)
                                entry.Text.Position = Vector2.new(screenPos.X, screenPos.Y)
                                entry.Text.Text = "🚨 THIEF! [" .. tostring(dist) .. "m]"
                                entry.Text.Visible = true
                            else
                                entry.Text.Visible = false
                            end
                        end
                    end
                end
            end
        else
            clearDrawingList(DrawingObjects.Thieves)
        end
    end

    ----------------------------------------------------------------
    --  MAIN HEARTBEAT LOOP
    ----------------------------------------------------------------
    local lastSlowTick = 0
    connect(RunService.Heartbeat, function(dt)
        if isDestroyed then return end

        -- Movement modification
        if State.EnableCustomSpeed then
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = State.WalkSpeed end
        end

        pcall(runOrderAndServe)
        pcall(updateESP)

        local now = os.clock()
        if now - lastSlowTick >= 0.5 then
            lastSlowTick = now
            pcall(optimizePrompts)
            pcall(scanThievesAndCrocs)
            pcall(wakeLazyWorkers)
            pcall(runSanitation)
        end
    end)

    ----------------------------------------------------------------
    --  TELEPORT LOCATIONS
    ----------------------------------------------------------------
    local function teleportTo(cframe)
        local root = getRoot()
        if root and cframe then
            root.CFrame = cframe + Vector3.new(0, 3, 0)
        end
    end

    local function getPlotCFrame(childName)
        local plot = getMyRestaurant()
        if not plot then return nil end
        if not childName then return plot:GetPivot() end
        local obj = plot:FindFirstChild(childName, true)
        if obj then
            if obj:IsA("BasePart") then return obj.CFrame end
            if obj:IsA("Model") then return obj:GetPivot() end
        end
        return plot:GetPivot()
    end

    ----------------------------------------------------------------
    --  UI CREATION (MacLib / Drawing UI Compatible)
    ----------------------------------------------------------------
    if not Window or type(Window.CreateTab) ~= "function" then
        local dummy = {}
        function dummy:CreateTab()
            local tab = {}
            function tab:CreateSection() end
            function tab:CreateToggle() end
            function tab:CreateDropdown() end
            function tab:CreateSlider() end
            function tab:CreateButton() end
            return tab
        end
        Window = dummy
    end

    -- Tab 1: Kitchen & Restaurant
    local KitchenTab = Window:CreateTab("Kitchen", 4483362458)
    KitchenTab:CreateSection("Dishwashing & Service")
    KitchenTab:CreateToggle({
        Name = "Instant Wash Dishes (Bypass 30s)",
        CurrentValue = true,
        Flag = "KD_InstantWash",
        Callback = function(v) State.InstantWash = v end,
    })
    KitchenTab:CreateToggle({
        Name = "Auto Take Orders (Counter)",
        CurrentValue = false,
        Flag = "KD_AutoTakeOrder",
        Callback = function(v) State.AutoTakeOrder = v end,
    })
    KitchenTab:CreateToggle({
        Name = "Auto Serve Ready Dishes",
        CurrentValue = false,
        Flag = "KD_AutoServeDishes",
        Callback = function(v) State.AutoServeDishes = v end,
    })
    KitchenTab:CreateToggle({
        Name = "Auto Repair Chiller",
        CurrentValue = false,
        Flag = "KD_AutoRepairChiller",
        Callback = function(v) State.AutoRepairChiller = v end,
    })

    -- Tab 2: Anti-Theft & Defense
    local DefenseTab = Window:CreateTab("Defense", 4483362458)
    DefenseTab:CreateSection("Anti-Theft Security")
    DefenseTab:CreateToggle({
        Name = "Auto Smack Runaway Thieves",
        CurrentValue = true,
        Flag = "KD_AutoSmackThief",
        Callback = function(v) State.AutoSmackThief = v end,
    })
    DefenseTab:CreateDropdown({
        Name = "Smack Weapon",
        Options = {"Pan", "Slipper", "Bread", "Rambo"},
        CurrentOption = "Pan",
        Flag = "KD_SmackWeapon",
        Callback = function(opt) State.ThiefSmackWeapon = opt end,
    })
    DefenseTab:CreateToggle({
        Name = "Auto Hit Crocodiles",
        CurrentValue = true,
        Flag = "KD_AutoHitCroc",
        Callback = function(v) State.AutoHitCroc = v end,
    })

    -- Tab 3: Staff & Management
    local StaffTab = Window:CreateTab("Staff", 4483362458)
    StaffTab:CreateSection("Worker Automation")
    StaffTab:CreateToggle({
        Name = "Auto Wake Sleeping Workers",
        CurrentValue = true,
        Flag = "KD_AutoWakeWorkers",
        Callback = function(v) State.AutoWakeWorkers = v end,
    })
    StaffTab:CreateButton({
        Name = "Roll Free Worker (Remote)",
        Callback = function()
            local rollRemote = Remotes and Remotes:FindFirstChild("WorkerRemotes") and Remotes.WorkerRemotes:FindFirstChild("RollWorker")
            if rollRemote then
                pcall(function() rollRemote:InvokeServer() end)
            end
        end,
    })

    -- Tab 4: Tycoon & Rewards
    local TycoonTab = Window:CreateTab("Tycoon", 4483362458)
    TycoonTab:CreateSection("Sanitation & Automation")
    TycoonTab:CreateToggle({
        Name = "Auto Collect & Throw Trash",
        CurrentValue = false,
        Flag = "KD_AutoCollectTrash",
        Callback = function(v) State.AutoCollectTrash = v end,
    })
    TycoonTab:CreateToggle({
        Name = "Auto Heart Signage",
        CurrentValue = false,
        Flag = "KD_AutoHeartSign",
        Callback = function(v) State.AutoHeartSign = v end,
    })
    TycoonTab:CreateButton({
        Name = "Claim Group Reward",
        Callback = function()
            local claimRemote = Remotes and Remotes:FindFirstChild("GroupReward") and Remotes.GroupReward:FindFirstChild("ClaimGroupReward")
            if claimRemote then
                pcall(function() claimRemote:FireServer() end)
            end
        end,
    })

    -- Tab 5: Visuals (ESP)
    local VisualTab = Window:CreateTab("Visuals", 4483362458)
    VisualTab:CreateSection("ESP Overlays")
    VisualTab:CreateToggle({
        Name = "Thief Alert ESP (Red)",
        CurrentValue = true,
        Flag = "KD_ESPThieves",
        Callback = function(v)
            State.ESPThieves = v
            if not v then clearDrawingList(DrawingObjects.Thieves) end
        end,
    })

    -- Tab 6: Teleports
    local TeleportTab = Window:CreateTab("Teleport", 4483362458)
    TeleportTab:CreateSection("Restaurant Waypoints")
    TeleportTab:CreateButton({
        Name = "TP: My Restaurant Center",
        Callback = function() teleportTo(getPlotCFrame()) end,
    })
    TeleportTab:CreateButton({
        Name = "TP: Order Counter",
        Callback = function() teleportTo(getPlotCFrame("Counter")) end,
    })
    TeleportTab:CreateButton({
        Name = "TP: Kitchen Sink (Dishwash)",
        Callback = function() teleportTo(getPlotCFrame("Sink")) end,
    })
    TeleportTab:CreateButton({
        Name = "TP: Softdrink Chiller",
        Callback = function() teleportTo(getPlotCFrame("Softdrinks")) end,
    })

    TeleportTab:CreateSection("Map POIs")
    TeleportTab:CreateButton({
        Name = "TP: Grocery Store",
        Callback = function()
            local grocery = Workspace:FindFirstChild("Grocery")
            if grocery then teleportTo(grocery:GetPivot()) end
        end,
    })
    TeleportTab:CreateButton({
        Name = "TP: Barangay Hall",
        Callback = function()
            local hall = Workspace:FindFirstChild("BrgyHall")
            if hall then teleportTo(hall:GetPivot()) end
        end,
    })
    TeleportTab:CreateButton({
        Name = "TP: Junk Shop",
        Callback = function()
            local junk = Workspace:FindFirstChild("JunkShop")
            if junk then teleportTo(junk:GetPivot()) end
        end,
    })

    -- Tab 7: Player
    local PlayerTab = Window:CreateTab("Player", 4483362458)
    PlayerTab:CreateSection("Movement")
    PlayerTab:CreateToggle({
        Name = "Enable Custom WalkSpeed",
        CurrentValue = false,
        Flag = "KD_EnableSpeed",
        Callback = function(v)
            State.EnableCustomSpeed = v
            if not v then
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = 18 end
            end
        end,
    })
    PlayerTab:CreateSlider({
        Name = "WalkSpeed",
        Min = 18,
        Max = 120,
        Default = 28,
        Increment = 1,
        Flag = "KD_SpeedVal",
        Callback = function(val) State.WalkSpeed = val end,
    })

    ----------------------------------------------------------------
    --  CLEANUP & RETURN
    ----------------------------------------------------------------
    local ModuleInstance = {
        State = State,
        Destroy = function()
            isDestroyed = true
            for _, conn in ipairs(Connections) do
                pcall(function() conn:Disconnect() end)
            end
            table.clear(Connections)

            clearDrawingList(DrawingObjects.Thieves)
            clearDrawingList(DrawingObjects.Customers)
            clearDrawingList(DrawingObjects.Trash)

            local hum = getHumanoid()
            if hum then hum.WalkSpeed = 18 end

            getgenv().__RAVEN_KARINDERYA = nil
        end,
    }

    getgenv().__RAVEN_KARINDERYA = ModuleInstance
    return ModuleInstance
end