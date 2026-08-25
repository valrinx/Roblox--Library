-- RAVEN HUB | Anime Card Farm v0.1.1
return function(Window, scriptInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService = game:GetService("TweenService")

    local player = Players.LocalPlayer
    local env = getgenv()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local conveyorRE = remotes and remotes:FindFirstChild("ConveyorRE")
    if type(env.__RAVEN_ANIME_CARD_FARM) == "table"
        and type(env.__RAVEN_ANIME_CARD_FARM.Destroy) == "function" then
        pcall(env.__RAVEN_ANIME_CARD_FARM.Destroy)
    end

    local running = true
    local settings = {
        autoCarry = false,
        autoSell = false,
        autoPackHunt = false,
        rarityLock = "Any",
        mutationLock = "Any",
        maxPackPrice = 0,
        cashReserve = 0,
        tweenSpeed = 45,
    }
    local lastAction = {
        carry = 0,
        sell = 0,
        pack = 0,
    }
    local warnedPromptSupport = false
    local movementBusy = false
    local activeTween = nil
    local purchaseInFlight = false
    local pendingItemId = nil
    local itemCooldown = {}

    local function notify(text)
        local hub = scriptInfo and (scriptInfo.hubUI or scriptInfo.hubRayfield)
        if hub and type(hub.Notify) == "function" then
            pcall(function()
                hub:Notify({
                    Title = "Anime Card Farm",
                    Content = tostring(text),
                    Duration = 5,
                })
            end)
        end
    end

    local function ready(key, delaySeconds)
        local now = os.clock()
        if now < (lastAction[key] or 0) then
            return false
        end
        lastAction[key] = now + delaySeconds
        return true
    end

    local function getPlotNumber()
        local value = player:FindFirstChild("PlotNumber")
        return value and tonumber(value.Value) or nil
    end

    local function getOwnPlot()
        local plotNumber = getPlotNumber()
        local map = workspace:FindFirstChild("MAP")
        local plots = map and map:FindFirstChild("Plots")
        local plotFolder = plots and plotNumber and plots:FindFirstChild(tostring(plotNumber))
        if not plotFolder then
            return nil
        end
        return plotFolder:FindFirstChild("Plot_N0") or plotFolder
    end

    local function parseMoneyText(text)
        local cleaned = tostring(text or ""):gsub("[$,%s]", "")
        local suffix = cleaned:sub(-1):upper()
        local multiplier = 1
        if suffix == "K" then
            multiplier = 1e3
        elseif suffix == "M" then
            multiplier = 1e6
        elseif suffix == "B" then
            multiplier = 1e9
        elseif suffix == "T" then
            multiplier = 1e12
        end
        if multiplier ~= 1 then
            cleaned = cleaned:sub(1, -2)
        end
        return (tonumber(cleaned) or 0) * multiplier
    end

    local function getCarryPrompt()
        local plot = getOwnPlot()
        local boxBase = plot and plot:FindFirstChild("BoxBaseModel")
        local proxiBox = boxBase and boxBase:FindFirstChild("ProxiBox")
        local prompt = proxiBox and proxiBox:FindFirstChildOfClass("ProximityPrompt")
        if prompt
            and prompt.Enabled
            and string.find(string.lower(prompt.ActionText or ""), "carry", 1, true)
            and parseMoneyText(prompt.ObjectText) > 0 then
            return prompt
        end
        return nil
    end

    local function getSellPrompt()
        local plot = getOwnPlot()
        local sellPart = plot and plot:FindFirstChild("SellPart")
        local prompt = sellPart and sellPart:FindFirstChildOfClass("ProximityPrompt")
        if prompt and prompt.Enabled and string.find(string.lower(prompt.ActionText or ""), "sell", 1, true) then
            return prompt
        end
        return nil
    end

    local function findTool(predicate)
        local character = player.Character
        local backpack = player:FindFirstChildOfClass("Backpack")
        for _, container in ipairs({character, backpack}) do
            if container then
                for _, child in ipairs(container:GetChildren()) do
                    if child:IsA("Tool") and predicate(child) then
                        return child
                    end
                end
            end
        end
        return nil
    end

    local function findBoxTool()
        return findTool(function(tool)
            return tool:GetAttribute("BoxValue") ~= nil
        end)
    end

    local function equipTool(tool)
        if not tool then
            return false
        end
        local character = player.Character
        if character and tool.Parent == character then
            return true
        end
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then
            return false
        end
        return pcall(function()
            humanoid:EquipTool(tool)
        end)
    end

    local function getPromptPart(prompt)
        if not prompt then
            return nil
        end
        local part = prompt.Parent
        if part and part:IsA("BasePart") then
            return part
        end
        return part and part:FindFirstAncestorWhichIsA("BasePart") or nil
    end

    local function tweenToPrompt(prompt)
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local promptPart = getPromptPart(prompt)
        if not root or not promptPart then
            return false
        end
        local distance = (root.Position - promptPart.Position).Magnitude
        local duration = math.clamp(distance / math.max(settings.tweenSpeed, 1), 0.12, 5)
        activeTween = TweenService:Create(
            root,
            TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            {CFrame = promptPart.CFrame * CFrame.new(0, 3, 0)}
        )
        activeTween:Play()
        local ok = pcall(function()
            activeTween.Completed:Wait()
        end)
        activeTween = nil
        return ok and running
    end

    local function firePrompt(prompt)
        if not prompt then
            return false
        end
        local fn = rawget(env, "fireproximityprompt")
        if type(fn) ~= "function" then
            if not warnedPromptSupport then
                warnedPromptSupport = true
                notify("fireproximityprompt is unavailable in this executor")
            end
            return false
        end
        return pcall(fn, prompt)
    end

    local function moveAndPrompt(prompt)
        if movementBusy or not prompt then
            return false
        end
        movementBusy = true
        local moved = tweenToPrompt(prompt)
        local triggered = false
        if moved and running then
            task.wait(0.08)
            triggered = firePrompt(prompt)
            task.wait(0.18)
        end
        movementBusy = false
        return triggered
    end

    local function tryAutoSell()
        if not ready("sell", 0.5) then
            return
        end
        local boxTool = findTool(function(tool)
            return (tonumber(tool:GetAttribute("BoxValue")) or 0) > 0
        end)
        if not boxTool or not equipTool(boxTool) then
            return
        end
        moveAndPrompt(getSellPrompt())
    end

    local function tryAutoCarry()
        if not ready("carry", 0.5) or findBoxTool() then
            return
        end
        moveAndPrompt(getCarryPrompt())
    end

    local function lockMatches(value, wanted)
        local selected = tostring(wanted or "Any"):match("^%s*(.-)%s*$")
        if selected == "" or string.lower(selected) == "any" then
            return true
        end
        return string.lower(tostring(value or "")) == string.lower(selected)
    end

    local function getPackCandidate()
        if not conveyorRE then
            return nil
        end
        local cashValue = player:FindFirstChild("CashValue")
        local cash = cashValue and tonumber(cashValue.Value) or nil
        if not cash then
            return nil
        end
        local now = os.clock()
        for _, model in ipairs(workspace:GetChildren()) do
            if model:IsA("Model") then
                local itemId = model:GetAttribute("ItemId")
                local price = tonumber(model:GetAttribute("Price"))
                local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
                local action = prompt and string.lower(prompt.ActionText or "") or ""
                if itemId ~= nil and price and prompt and prompt.Enabled and string.find(action, "buy", 1, true) then
                    local key = tostring(itemId)
                    local rarity = model:GetAttribute("Rarity")
                    local mutation = model:GetAttribute("Mutation")
                    local maxPriceOk = settings.maxPackPrice <= 0 or price <= settings.maxPackPrice
                    local cashOk = cash >= price and (cash - price) >= settings.cashReserve
                    local cooldownOk = (itemCooldown[key] or 0) <= now
                    if maxPriceOk
                        and cashOk
                        and cooldownOk
                        and lockMatches(rarity, settings.rarityLock)
                        and lockMatches(mutation, settings.mutationLock) then
                        return {
                            itemId = itemId,
                            key = key,
                            price = price,
                            rarity = rarity,
                            mutation = mutation,
                            name = model.Name,
                        }
                    end
                end
            end
        end
        return nil
    end

    local function tryAutoPackHunt()
        if purchaseInFlight or not ready("pack", 0.25) then
            return
        end
        local candidate = getPackCandidate()
        if not candidate then
            return
        end
        purchaseInFlight = true
        pendingItemId = candidate.key
        itemCooldown[candidate.key] = os.clock() + 2
        local ok = pcall(function()
            conveyorRE:FireServer("TryBuy", {ItemId = candidate.itemId})
        end)
        if not ok then
            purchaseInFlight = false
            pendingItemId = nil
            return
        end
        task.delay(1.25, function()
            if pendingItemId == candidate.key then
                purchaseInFlight = false
                pendingItemId = nil
            end
        end)
    end

    local AutomationTab = Window:CreateTab("Automation", "automation")
    AutomationTab:CreateSection("Card Box")
    AutomationTab:CreateToggle({
        Name = "Auto Carry Card Box",
        CurrentValue = false,
        Flag = "ACFAutoCarry",
        Callback = function(value)
            settings.autoCarry = value == true
        end,
    })
    AutomationTab:CreateToggle({
        Name = "Auto Sell Card Box",
        CurrentValue = false,
        Flag = "ACFAutoSell",
        Callback = function(value)
            settings.autoSell = value == true
        end,
    })

    AutomationTab:CreateSlider({
        Name = "Tween Speed",
        Range = {15, 100},
        Increment = 5,
        CurrentValue = settings.tweenSpeed,
        Flag = "ACFTweenSpeed",
        Callback = function(value)
            settings.tweenSpeed = tonumber(value) or 45
        end,
    })

    AutomationTab:CreateSection("Pack Hunt")
    AutomationTab:CreateToggle({
        Name = "Auto Pack Hunt",
        CurrentValue = false,
        Flag = "ACFAutoPackHunt",
        Callback = function(value)
            settings.autoPackHunt = value == true
        end,
    })
    AutomationTab:CreateInput({
        Name = "Rarity Lock",
        CurrentValue = "Any",
        PlaceholderText = "Any or exact rarity",
        RemoveTextAfterFocusLost = false,
        Flag = "ACFRarityLock",
        Callback = function(value)
            settings.rarityLock = tostring(value or "Any")
        end,
    })
    AutomationTab:CreateInput({
        Name = "Mutation / Effect Lock",
        CurrentValue = "Any",
        PlaceholderText = "Any or exact mutation",
        RemoveTextAfterFocusLost = false,
        Flag = "ACFMutationLock",
        Callback = function(value)
            settings.mutationLock = tostring(value or "Any")
        end,
    })
    AutomationTab:CreateInput({
        Name = "Max Pack Price (0 = No Limit)",
        CurrentValue = "0",
        PlaceholderText = "0",
        RemoveTextAfterFocusLost = false,
        Flag = "ACFMaxPackPrice",
        Callback = function(value)
            settings.maxPackPrice = math.max(0, tonumber(value) or 0)
        end,
    })
    AutomationTab:CreateInput({
        Name = "Cash Reserve",
        CurrentValue = "0",
        PlaceholderText = "Money to keep after buying",
        RemoveTextAfterFocusLost = false,
        Flag = "ACFCashReserve",
        Callback = function(value)
            settings.cashReserve = math.max(0, tonumber(value) or 0)
        end,
    })

    task.spawn(function()
        while running do
            if settings.autoSell then
                tryAutoSell()
            end
            if settings.autoCarry then
                tryAutoCarry()
            end
            if settings.autoPackHunt then
                tryAutoPackHunt()
            end
            task.wait(0.12)
        end
    end)

    local destroyed = false
    local function destroy()
        if destroyed then
            return
        end
        destroyed = true
        running = false
        settings.autoCarry = false
        settings.autoSell = false
        settings.autoPackHunt = false
        if activeTween then
            pcall(function() activeTween:Cancel() end)
            activeTween = nil
        end
        if env.__RAVEN_ANIME_CARD_FARM and env.__RAVEN_ANIME_CARD_FARM.Destroy == destroy then
            env.__RAVEN_ANIME_CARD_FARM = nil
        end
    end

    env.__RAVEN_ANIME_CARD_FARM = {
        Destroy = destroy,
        Settings = settings,
    }

    if scriptInfo and type(scriptInfo.registerCleanup) == "function" then
        scriptInfo.registerCleanup(destroy)
    end
end
