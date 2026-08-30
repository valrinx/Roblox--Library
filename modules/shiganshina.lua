--// Shiganshina v7 — Auto Farm Script
--// Game: Training Grounds (AoT)
--// PlaceId: 13379349730
--// Uses MacLib from RAVEN HUB

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

return function(Window, runtimeInfo)
    local LP = Players.LocalPlayer
    local Char = LP.Character or LP.CharacterAdded:Wait()
    local Root = Char:WaitForChild("HumanoidRootPart")
    local Humanoid = Char:FindFirstChildOfClass("Humanoid")

    --// Find Remotes
    local POST, GET
    for _, v in ReplicatedStorage:GetDescendants() do
        if v.Name == "POST" and v:IsA("RemoteEvent") then POST = v end
        if v.Name == "GET" and v:IsA("RemoteFunction") then GET = v end
    end

    local TitansFolder = Workspace:WaitForChild("Titans")

    --// Config
    local Config = {
        AutoFarm = false,
        AutoGrabEscape = false,
        AutoRetry = false,
        AutoReloadBlades = false,
        AutoFullReload = false,
        InfiniteSpear = false,
        AutoUseSkill = false,
        MultiHit = false,
        MultiHitRadius = 50,
        BossBurst = false,
        NapeExtender = false,
        TitanESP = false,
        FarmDelay = 0.15,
    }

    local ESPObjects = {}
    local ActiveThreads = {}
    local RetryState = {
        pending = false,
        waitingForRound = false,
        lastClickAt = -math.huge,
        nextAttemptAt = 0,
        clickMode = 1,
        deathConnection = nil,
    }
    local RetryClickCooldown = 1.25
    local RetryWaitTimeout = 5

    --// ==================== UTILITY ====================

    local function getCharacter()
        Char = LP.Character
        if not Char then return nil, nil, nil end
        Root = Char:FindFirstChild("HumanoidRootPart")
        Humanoid = Char:FindFirstChildOfClass("Humanoid")
        return Char, Root, Humanoid
    end

    local function isGuiHierarchyVisible(gui)
        local node = gui
        while node do
            if node:IsA("GuiObject") and not node.Visible then return false end
            if node:IsA("ScreenGui") and not node.Enabled then return false end
            node = node.Parent
        end
        return true
    end

    local function isGuiButtonUsable(button)
        if not button or not button:IsA("GuiButton") then return false end
        if not button.Visible then return false end
        -- Don't reject on Active/Interactable — games often set these
        -- on retry/confirm buttons even when they are meant to be clicked.
        -- Also skip parent-frame visibility check: the Retry button often
        -- exists inside a hidden Rewards frame that becomes clickable
        -- independently once the mission ends.
        return true
    end

    -- Use one activation mechanism per attempt. Executors differ in which
    -- GuiButton signal they expose, so Auto Retry rotates through the safe
    -- options and finally falls back to a real mouse click at the button.
    local function clickButton(button, mode)
        if not isGuiButtonUsable(button) then return false end
        local clickMode = mode or 1
        local center = button.AbsolutePosition + (button.AbsoluteSize / 2)
        local x, y = center.X, center.Y
        if clickMode == 1 then
            return pcall(function() button:Activate() end)
        elseif clickMode == 2 then
            return pcall(function() button.MouseButton1Click:Fire() end)
        elseif clickMode == 3 then
            return pcall(function() button.Activated:Fire() end)
        elseif clickMode == 4 then
            -- Fire MouseButton1Down then MouseButton1Up separately
            return pcall(function()
                button.MouseButton1Down:Fire()
                button.MouseButton1Up:Fire()
            end)
        elseif clickMode == 5 then
            -- Try executor-level mouse click (mouse1click) if available
            local ok = pcall(function() mouse1click(x, y) end)
            if ok then return true end
            -- Fallback: try mouse1press + mouse1release
            pcall(function() mouse1press(x, y) end)
            pcall(function() task.wait(0.05) end)
            pcall(function() mouse1release(x, y) end)
            return true
        elseif clickMode == 6 then
            -- Try keyboard shortcut: press Enter/Return key
            local ok1 = pcall(function() keypress(0x0D) end) -- VK_RETURN
            pcall(function() task.wait(0.05) end)
            local ok2 = pcall(function() keyrelease(0x0D) end)
            return ok1 or ok2
        elseif clickMode == 7 then
            -- Use game:GetService("Players"):GetMouse() to click at position
            local mouse = game:GetService("Players").LocalPlayer:GetMouse()
            return pcall(function()
                mouse.Button1Down = true
                mouse.Button1Down = false
            end)
        end

        -- Fallback: VirtualInputManager mouse click
        local virtualInput
        local inputOk = pcall(function()
            virtualInput = game:GetService("VirtualInputManager")
        end)
        if not inputOk or not virtualInput then return false end
        return pcall(function()
            virtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
            virtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end

    local function bindRetryDeath(character)
        if RetryState.deathConnection then
            pcall(function() RetryState.deathConnection:Disconnect() end)
            RetryState.deathConnection = nil
        end
        if not character then return end
        local hum = character:FindFirstChildOfClass("Humanoid")
        if not hum then
            hum = character:WaitForChild("Humanoid", 5)
        end
        if hum then
            RetryState.deathConnection = hum.Died:Connect(function()
                if Config.AutoRetry then RetryState.pending = true end
            end)
        end
    end

    bindRetryDeath(Char)

    local function getNape(titan)
        local hitboxes = titan:FindFirstChild("Hitboxes")
        if hitboxes then
            local hit = hitboxes:FindFirstChild("Hit")
            if hit then
                local nape = hit:FindFirstChild("Nape")
                if nape and nape:IsA("BasePart") then return nape end
            end
        end
        local nape = titan:FindFirstChild("Nape", true)
        if nape and nape:IsA("BasePart") then return nape end
        return nil
    end

    local function getTitanHealth(titan)
        local hum = titan:FindFirstChildOfClass("Humanoid")
        if hum then return hum.Health, hum.MaxHealth end
        return 0, 0
    end

    local function isBoss(titan)
        local nape = getNape(titan)
        if nape and nape.Size.X > 25 then return true end
        local hum = titan:FindFirstChildOfClass("Humanoid")
        if hum and hum.MaxHealth > 100 then return true end
        return false
    end

    local function getAliveTitans()
        local alive = {}
        for _, titan in TitansFolder:GetChildren() do
            if titan:IsA("Model") then
                local hp, maxHp = getTitanHealth(titan)
                local nape = getNape(titan)
                if hp > 0 and nape then
                    table.insert(alive, { titan = titan, nape = nape, hp = hp, maxHp = maxHp, isBoss = isBoss(titan) })
                end
            end
        end
        return alive
    end

    local function getNearestTitan()
        local _, root = getCharacter()
        if not root then return nil end
        local nearest, minDist = nil, math.huge
        for _, info in getAliveTitans() do
            local dist = (root.Position - info.nape.Position).Magnitude
            if dist < minDist then minDist = dist; nearest = info end
        end
        return nearest, minDist
    end

    --// ==================== BLADE UI DETECTION ====================
    -- The game has two separate blade systems:
    --   หลอด (durability bar): 6 segments, controlled by Bar/Gradient.Offset.X
    --     Offset.X = 1.0 → full (6/6)
    --     Offset.X = 0.0 → empty (0/6) → needs reload (remote)
    --   ใบดาบ (blade sets): 3 sets, shown in Sets.Text (e.g. "2 / 3")
    --     "0 / 3" → needs refill (station)

    local function getBladesUI()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return nil end
        local iface = pg:FindFirstChild("Interface")
        local hud = iface and iface:FindFirstChild("HUD")
        local main = hud and hud:FindFirstChild("Main")
        local top = main and main:FindFirstChild("Top")
        local top7 = top and top:FindFirstChild("7")
        return top7 and top7:FindFirstChild("Blades")
    end

    --- Returns the durability bar fill as a 0-1 scale.
    --- 1.0 = full, 0.0 = empty.
    local function getDurabilityBar()
        local blades = getBladesUI()
        if not blades then return 1 end
        local inner = blades:FindFirstChild("Inner")
        local bar = inner and inner:FindFirstChild("Bar")
        local barInner = bar and bar:FindFirstChild("Inner")
        if not barInner then return 1 end
        -- The bar gradient Offset.X goes from 1 (full) to 0 (empty)
        local gradient = bar:FindFirstChild("Gradient")
        if gradient then
            local ok, ox = pcall(function() return gradient.Offset.X end)
            if ok and type(ox) == "number" then
                -- Offset.X = 0 means full bar, Offset.X = 1 means empty
                -- So durability = 1 - offsetX
                return math.clamp(1 - ox, 0, 1)
            end
        end
        return 1
    end

    --- Returns the number of blade sets remaining and the max sets.
    local function getBladeSets()
        local blades = getBladesUI()
        if not blades then return 3, 3 end
        local sets = blades:FindFirstChild("Sets")
        if not sets or not sets:IsA("TextLabel") then return 3, 3 end
        local text = sets.Text or ""
        local remaining, total = text:match("(%d+)%s*/%s*(%d+)")
        if remaining and total then
            return tonumber(remaining) or 0, tonumber(total) or 3
        end
        return 3, 3
    end

    local function needsBarReload()
        return getDurabilityBar() <= 0
    end

    local function needsSetRefill()
        local remaining, _ = getBladeSets()
        return remaining <= 0
    end

    local function doRemoteReload()
        if GET then
            pcall(function() GET:InvokeServer("Blades", "Reload") end)
        end
    end

    local function getRefillStation()
        local _, root = getCharacter()
        if not root then return nil end
        local station, minDist = nil, math.huge
        for _, part in Workspace:GetDescendants() do
            if part.Name == "Refill" and part:IsA("BasePart") then
                local dist = (root.Position - part.Position).Magnitude
                if dist < minDist then minDist = dist; station = part end
            end
        end
        return station
    end

    --// ==================== COMBAT ====================

    local function doSlash(nape)
        if POST then
            POST:FireServer("Attacks", "Slash", true)
            task.wait(0.05)
            POST:FireServer("Hitboxes", "Register", nape, Config.MultiHit and Config.MultiHitRadius or 50, 0)
        end
    end

    local function doStationReload()
        local _, root = getCharacter()
        if not root then return end
        local station = getRefillStation()
        if not station then return end
        local old = root.CFrame
        -- Teleport to station
        root.CFrame = station.CFrame * CFrame.new(0, 5, 0)
        task.wait(0.3)
        -- Fire reload at station
        if POST then
            pcall(function() POST:FireServer("Attacks", "Reload", station) end)
        end
        task.wait(2)
        -- Reload blades
        if GET then
            pcall(function() GET:InvokeServer("Blades", "Reload") end)
        end
        task.wait(0.3)
        -- Return to original position
        local _, root2 = getCharacter()
        if root2 then root2.CFrame = old end
    end

    --// ==================== GRAB ESCAPE ====================

    local function isGrabbed()
        local char, root, hum = getCharacter()
        if not char or not root or not hum then return false end
        -- Check 0: QTE visible (grab mini game)
        local pg = LP:FindFirstChild("PlayerGui")
        if pg then
            local iface = pg:FindFirstChild("Interface")
            if iface then
                local qte = iface:FindFirstChild("QTE")
                if qte and qte.Visible then return true end
            end
        end
        -- Check 1: PlatformStand set by server
        if hum.PlatformStand then return true end
        -- Check 2: State is PlatformStanding or Seated
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.PlatformStanding then return true end
        if state == Enum.HumanoidStateType.Seated then return true end
        -- Check 3: Weld connecting player to any Titan part
        for _, v in char:GetDescendants() do
            if v:IsA("Weld") or v:IsA("WeldConstraint") then
                if (v.Part0 and v.Part0:IsDescendantOf(TitansFolder))
                    or (v.Part1 and v.Part1:IsDescendantOf(TitansFolder)) then
                    return true
                end
            end
        end
        -- Check 4: BodyPosition (not BodyVelocity which is always present)
        for _, v in char:GetDescendants() do
            if v:IsA("BodyPosition") then return true end
        end
        return false
    end

    local function getQTEKey()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return nil end
        local iface = pg:FindFirstChild("Interface")
        if not iface then return nil end
        local qte = iface:FindFirstChild("QTE")
        if not qte or not qte.Visible then return nil end
        local main = qte:FindFirstChild("Main")
        if not main then return nil end
        local button = main:FindFirstChild("Button")
        if not button then return nil end
        local key = button:FindFirstChild("Key")
        if key and key:IsA("TextLabel") then
            return key.Text
        end
        return nil
    end

    local function pressKey(keyName)
        if not keyName or #keyName == 0 then return end
        local key = keyName:upper()
        -- Map key names to KeyCode
        local keyMap = {
            ["A"] = Enum.KeyCode.A, ["B"] = Enum.KeyCode.B, ["C"] = Enum.KeyCode.C,
            ["D"] = Enum.KeyCode.D, ["E"] = Enum.KeyCode.E, ["F"] = Enum.KeyCode.F,
            ["G"] = Enum.KeyCode.G, ["H"] = Enum.KeyCode.H, ["I"] = Enum.KeyCode.I,
            ["J"] = Enum.KeyCode.J, ["K"] = Enum.KeyCode.K, ["L"] = Enum.KeyCode.L,
            ["M"] = Enum.KeyCode.M, ["N"] = Enum.KeyCode.N, ["O"] = Enum.KeyCode.O,
            ["P"] = Enum.KeyCode.P, ["Q"] = Enum.KeyCode.Q, ["R"] = Enum.KeyCode.R,
            ["S"] = Enum.KeyCode.S, ["T"] = Enum.KeyCode.T, ["U"] = Enum.KeyCode.U,
            ["V"] = Enum.KeyCode.V, ["W"] = Enum.KeyCode.W, ["X"] = Enum.KeyCode.X,
            ["Y"] = Enum.KeyCode.Y, ["Z"] = Enum.KeyCode.Z,
        }
        local keyCode = keyMap[key]
        if not keyCode then return end
        -- Simulate key press
        local vim = game:GetService("VirtualInputManager")
        if vim then
            pcall(function() vim:SendKeyEvent(true, keyCode, false, nil) end)
            task.wait(0.05)
            pcall(function() vim:SendKeyEvent(false, keyCode, false, nil) end)
        end
    end

    local function doEscape()
        local char, root, hum = getCharacter()
        if not char or not hum then return end
        -- Step 1: If QTE visible, press the key
        local qteKey = getQTEKey()
        if qteKey then
            pressKey(qteKey)
            -- Also try clicking the QTE button
            local pg = LP:FindFirstChild("PlayerGui")
            if pg then
                local iface = pg:FindFirstChild("Interface")
                if iface then
                    local qte = iface:FindFirstChild("QTE")
                    if qte then
                        local main = qte:FindFirstChild("Main")
                        if main then
                            local btn = main:FindFirstChild("Button")
                            if btn then clickButton(btn) end
                        end
                    end
                end
            end
        end
        -- Step 2: Remove extra BodyMovers
        local bvCount = 0
        for _, v in char:GetDescendants() do
            if v:IsA("BodyVelocity") then bvCount = bvCount + 1 end
        end
        if bvCount > 1 then
            local count = 0
            for _, v in char:GetDescendants() do
                if v:IsA("BodyVelocity") then
                    count = count + 1
                    if count > 1 then pcall(function() v:Destroy() end) end
                end
            end
        end
        for _, v in char:GetDescendants() do
            if v:IsA("BodyPosition") or v:IsA("BodyGyro") or v:IsA("BodyForce") then
                pcall(function() v:Destroy() end)
            end
        end
        -- Step 3: Remove welds to Titans
        for _, v in char:GetDescendants() do
            if v:IsA("Weld") or v:IsA("WeldConstraint") then
                if (v.Part0 and v.Part0:IsDescendantOf(TitansFolder))
                    or (v.Part1 and v.Part1:IsDescendantOf(TitansFolder)) then
                    pcall(function() v:Destroy() end)
                end
            end
        end
        -- Step 4: Reset humanoid
        hum.PlatformStand = false
        hum.Sit = false
        hum:ChangeState(Enum.HumanoidStateType.GettingUp)
        task.wait(0.05)
        hum:ChangeState(Enum.HumanoidStateType.Running)
        -- Step 5: Try escape remote
        if POST then
            pcall(function() POST:FireServer("Escape") end)
            pcall(function() POST:FireServer("Grab", "Escape") end)
            pcall(function() POST:FireServer("Grab", false) end)
        end
        -- Step 6: Teleport up
        if root then
            root.CFrame = root.CFrame + Vector3.new(0, 20, 0)
        end
    end

    local function autoGrabEscapeLoop()
        while Config.AutoGrabEscape do
            if isGrabbed() then
                for _ = 1, 30 do
                    if not isGrabbed() then break end
                    doEscape()
                    task.wait(0.03)
                end
            end
            task.wait(0.03)
        end
    end

    --// ==================== AUTO RETRY ====================

    -- Walk the full GUI tree to find a Retry button regardless of
    -- the exact hierarchy path, which the game may change between updates.
    local function findRetryButtonRecursive(parent, depth)
        if not parent or depth > 8 then return nil end
        for _, child in parent:GetChildren() do
            if child:IsA("GuiButton") and child.Visible
                and child.Name:lower():find("retry") then
                if isGuiHierarchyVisible(child) then return child end
            end
            local found = findRetryButtonRecursive(child, depth + 1)
            if found then return found end
        end
        return nil
    end

    local function getVisibleRetryButton()
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return nil end

        -- Primary path: Interface.Rewards.Main.Info.Main.Buttons.Retry
        local iface = pg:FindFirstChild("Interface")
        if iface then
            local rewards = iface:FindFirstChild("Rewards")
            local main = rewards and rewards:FindFirstChild("Main")
            local info = main and main:FindFirstChild("Info")
            local content = info and info:FindFirstChild("Main")
            local buttons = content and content:FindFirstChild("Buttons")
            local retry = buttons and buttons:FindFirstChild("Retry")
            -- The Retry button is often visible and clickable even when
            -- the Rewards parent frame is hidden by the game. Check the
            -- button directly and skip parent-frame visibility.
            if retry and retry:IsA("GuiButton") and retry.Visible then
                return retry
            end
        end

        -- Fallback: search the entire PlayerGui tree for any visible
        -- button whose name contains "retry".
        local fallback = findRetryButtonRecursive(pg, 0)
        if fallback then return fallback end

        return nil
    end

    local function autoRetryLoop()
        while Config.AutoRetry do
            local now = os.clock()
            local char, _, hum = getCharacter()

            -- Death is a state transition. Remember it and wait for the
            -- Rewards screen to expose its Retry button.
            if not char or not hum or hum.Health <= 0 then
                RetryState.pending = true
            end

            local retry = getVisibleRetryButton()
            if retry then RetryState.pending = true end
            if RetryState.waitingForRound then
                -- A successful retry normally hides Rewards and creates a
                -- fresh character. If either signal is delayed, allow one
                -- later fallback attempt instead of clicking every frame.
                -- If after waiting the rewards screen is STILL visible,
                -- the click didn't work — keep retrying immediately.
                if not retry then
                    RetryState.waitingForRound = false
                elseif now - RetryState.lastClickAt >= 1.5 then
                    -- After 1.5s, check if rewards screen is still there
                    -- If yes, the previous click failed — keep clicking
                    RetryState.waitingForRound = false
                end
            end

            if retry and RetryState.pending and not RetryState.waitingForRound and now >= RetryState.nextAttemptAt then
                local mode = RetryState.clickMode
                local clicked = clickButton(retry, mode)
                RetryState.clickMode = (mode % 7) + 1
                RetryState.lastClickAt = now
                RetryState.nextAttemptAt = now + RetryClickCooldown
                if clicked then
                    RetryState.pending = false
                    RetryState.waitingForRound = true
                end
            end
            task.wait(0.15)
        end
    end

    --// ==================== LOOPS ====================

    local function autoFarmLoop()
        while Config.AutoFarm do
            local char, root, humanoid = getCharacter()
            if not char or not root or not humanoid or humanoid.Health <= 0 then
                task.wait(1); continue
            end
            -- Check grab during farm
            if Config.AutoGrabEscape and isGrabbed() then
                doEscape()
                task.wait(0.2)
                continue
            end
            local info = getNearestTitan()
            if not info then task.wait(0.5); continue end
            if info.isBoss and Config.BossBurst then
                for _ = 1, 5 do doSlash(info.nape); task.wait(0.05) end
            end
            local tween = TweenService:Create(root,
                TweenInfo.new(0.25, Enum.EasingStyle.Quad),
                {CFrame = info.nape.CFrame * CFrame.new(0, 0, 5)})
            tween:Play()
            tween.Completed:Wait()
            doSlash(info.nape)
            if Config.NapeExtender then
                task.wait(0.05)
                if POST then POST:FireServer("Hitboxes", "Register", info.nape, 100, 0) end
            end
            task.wait(Config.FarmDelay)
        end
    end

    local function autoReloadLoop()
        while Config.AutoReloadBlades do
            local bar = getDurabilityBar()
            local remaining, total = getBladeSets()
            -- Durability bar empty → remote reload
            if bar <= 0 then
                doRemoteReload()
            end
            -- Blade sets empty → station refill
            if remaining <= 0 then
                doStationReload()
            end
            task.wait(0.5)
        end
    end

    local function infiniteSpearLoop()
        while Config.InfiniteSpear do
            if GET then pcall(function() GET:InvokeServer("Spears", "Reload") end) end
            task.wait(5)
        end
    end

    local function autoSkillLoop()
        while Config.AutoUseSkill do
            local info = getNearestTitan()
            if info and POST then
                pcall(function() POST:FireServer("Skills", "Use", info.nape) end)
            end
            task.wait(2)
        end
    end

    local function multiHitLoop()
        while Config.MultiHit do
            local info = getNearestTitan()
            if info then
                for _, other in getAliveTitans() do
                    if other.nape then
                        local dist = (info.nape.Position - other.nape.Position).Magnitude
                        if dist <= Config.MultiHitRadius then doSlash(other.nape) end
                    end
                end
            end
            task.wait(0.5)
        end
    end

    --// ==================== ESP ====================

    local function createESP(titan, nape)
        if ESPObjects[titan] then return end
        local bb = Instance.new("BillboardGui")
        bb.Name = "TitanESP"
        bb.Size = UDim2.new(0, 200, 0, 50)
        bb.StudsOffset = Vector3.new(0, 5, 0)
        bb.AlwaysOnTop = true
        bb.Adornee = nape
        local f = Instance.new("Frame", bb)
        f.Size = UDim2.new(1, 0, 1, 0)
        f.BackgroundColor3 = isBoss(titan) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 165, 0)
        f.BackgroundTransparency = 0.5
        local lbl = Instance.new("TextLabel", f)
        lbl.Size = UDim2.new(1, 0, 0.5, 0); lbl.BackgroundTransparency = 1
        lbl.Text = isBoss(titan) and "BOSS" or "TITAN"
        lbl.TextColor3 = Color3.new(1, 1, 1); lbl.TextScaled = true
        local hpLbl = Instance.new("TextLabel", f)
        hpLbl.Size = UDim2.new(1, 0, 0.5, 0); hpLbl.Position = UDim2.new(0, 0, 0.5, 0)
        hpLbl.BackgroundTransparency = 1
        local hp, maxHp = getTitanHealth(titan)
        hpLbl.Text = math.floor(hp) .. "/" .. math.floor(maxHp)
        hpLbl.TextColor3 = Color3.new(1, 1, 1); hpLbl.TextScaled = true
        bb.Parent = nape
        ESPObjects[titan] = bb
    end

    local function removeESP(titan)
        if ESPObjects[titan] then ESPObjects[titan]:Destroy(); ESPObjects[titan] = nil end
    end

    local function espLoop()
        while Config.TitanESP do
            for titan, esp in pairs(ESPObjects) do
                if not titan or not titan.Parent then removeESP(titan)
                else
                    local hp = getTitanHealth(titan)
                    if hp <= 0 then removeESP(titan) end
                end
            end
            for _, titan in TitansFolder:GetChildren() do
                if titan:IsA("Model") then
                    local hp, maxHp = getTitanHealth(titan)
                    local nape = getNape(titan)
                    if hp > 0 and nape and not ESPObjects[titan] then createESP(titan, nape) end
                end
            end
            task.wait(1)
        end
    end

    --// ==================== THREAD HELPERS ====================

    local function startThread(name, func)
        if ActiveThreads[name] then return end
        ActiveThreads[name] = task.spawn(func)
    end

    local function stopThread(name)
        if ActiveThreads[name] then task.cancel(ActiveThreads[name]); ActiveThreads[name] = nil end
    end

    --// ==================== UI (MacLib) ====================

    local FarmTab = Window:CreateTab("Farm")
    local CombatTab = Window:CreateTab("Combat")
    local ESPTab = Window:CreateTab("ESP")
    local MiscTab = Window:CreateTab("Misc")

    --// Farm Tab
    FarmTab:CreateSection("Farm Status")
    local StatusLabel = FarmTab:CreateLabel("Status: Idle")

    FarmTab:CreateSection("Auto Farm")
    FarmTab:CreateToggle({
        Name = "Toggle Auto Farm",
        CurrentValue = false,
        Flag = "ShigAutoFarm",
        Callback = function(v)
            Config.AutoFarm = v
            if v then StatusLabel:Set("Status: Farming..."); startThread("AutoFarm", autoFarmLoop)
            else StatusLabel:Set("Status: Idle"); stopThread("AutoFarm") end
        end,
    })

    FarmTab:CreateSection("Farm Settings")
    FarmTab:CreateToggle({
        Name = "Auto Grab Escape",
        CurrentValue = false,
        Flag = "ShigGrabEscape",
        Callback = function(v)
            Config.AutoGrabEscape = v
            if v then startThread("GrabEscape", autoGrabEscapeLoop) else stopThread("GrabEscape") end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Retry",
        CurrentValue = false,
        Flag = "ShigAutoRetry",
        Callback = function(v)
            Config.AutoRetry = v
            if v then
                startThread("AutoRetry", autoRetryLoop)
            else
                stopThread("AutoRetry")
                RetryState.pending = false
                RetryState.waitingForRound = false
                RetryState.nextAttemptAt = 0
            end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Reload Blades",
        CurrentValue = false,
        Flag = "ShigAutoReload",
        Callback = function(v)
            Config.AutoReloadBlades = v
            if v then startThread("AutoReload", autoReloadLoop) else stopThread("AutoReload") end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Full Reload",
        CurrentValue = false,
        Flag = "ShigFullReload",
        Callback = function(v) Config.AutoFullReload = v end,
    })
    FarmTab:CreateToggle({
        Name = "Infinite Spear",
        CurrentValue = false,
        Flag = "ShigInfiniteSpear",
        Callback = function(v)
            Config.InfiniteSpear = v
            if v then startThread("InfiniteSpear", infiniteSpearLoop) else stopThread("InfiniteSpear") end
        end,
    })
    FarmTab:CreateToggle({
        Name = "Auto Use Skill",
        CurrentValue = false,
        Flag = "ShigAutoSkill",
        Callback = function(v)
            Config.AutoUseSkill = v
            if v then startThread("AutoSkill", autoSkillLoop) else stopThread("AutoSkill") end
        end,
    })

    --// Combat Tab
    CombatTab:CreateSection("Combat Settings")
    CombatTab:CreateToggle({
        Name = "Multi Hit",
        CurrentValue = false,
        Flag = "ShigMultiHit",
        Callback = function(v)
            Config.MultiHit = v
            if v then startThread("MultiHit", multiHitLoop) else stopThread("MultiHit") end
        end,
    })
    CombatTab:CreateSlider({
        Name = "Multi Hit Radius",
        Range = {10, 200},
        Increment = 5,
        Suffix = " studs",
        CurrentValue = 50,
        Flag = "ShigMultiHitRadius",
        Callback = function(v) Config.MultiHitRadius = v end,
    })
    CombatTab:CreateToggle({
        Name = "Boss Burst",
        CurrentValue = false,
        Flag = "ShigBossBurst",
        Callback = function(v) Config.BossBurst = v end,
    })
    CombatTab:CreateToggle({
        Name = "Nape Extender",
        CurrentValue = false,
        Flag = "ShigNapeExtender",
        Callback = function(v) Config.NapeExtender = v end,
    })

    --// ESP Tab
    ESPTab:CreateSection("Titan ESP")
    ESPTab:CreateToggle({
        Name = "Titan ESP",
        CurrentValue = false,
        Flag = "ShigTitanESP",
        Callback = function(v)
            Config.TitanESP = v
            if v then startThread("ESP", espLoop)
            else stopThread("ESP"); for titan in pairs(ESPObjects) do removeESP(titan) end end
        end,
    })

    --// Misc Tab
    MiscTab:CreateSection("Character")
    MiscTab:CreateSlider({
        Name = "WalkSpeed",
        Range = {16, 100},
        Increment = 1,
        CurrentValue = 16,
        Flag = "ShigWalkSpeed",
        Callback = function(v) local _, _, h = getCharacter(); if h then h.WalkSpeed = v end end,
    })
    MiscTab:CreateToggle({
        Name = "NoClip",
        CurrentValue = false,
        Flag = "ShigNoClip",
        Callback = function(v) Config.NoClip = v end,
    })
    MiscTab:CreateToggle({
        Name = "Infinite Jump",
        CurrentValue = false,
        Flag = "ShigInfJump",
        Callback = function(v) Config.InfiniteJump = v end,
    })

    --// ==================== HANDLERS ====================

    RunService.Stepped:Connect(function()
        if Config.NoClip then
            local char = getCharacter()
            if char then
                for _, part in char:GetDescendants() do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
    end)

    game:GetService("UserInputService").JumpRequest:Connect(function()
        if Config.InfiniteJump then
            local _, _, h = getCharacter()
            if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end)

    LP.CharacterAdded:Connect(function(c)
        Char = c; Root = c:WaitForChild("HumanoidRootPart"); Humanoid = c:WaitForChild("Humanoid")
        RetryState.pending = false
        RetryState.waitingForRound = false
        RetryState.nextAttemptAt = 0
        RetryState.clickMode = 1
        bindRetryDeath(c)
    end)

    --// Cleanup
    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            for name in pairs(ActiveThreads) do stopThread(name) end
            for titan in pairs(ESPObjects) do removeESP(titan) end
            if RetryState.deathConnection then
                pcall(function() RetryState.deathConnection:Disconnect() end)
                RetryState.deathConnection = nil
            end
        end)
    end
end
