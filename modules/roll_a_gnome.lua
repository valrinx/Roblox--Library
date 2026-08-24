-- RAVEN HUB | Roll A Gnome v1
return function(Window, runtimeInfo)
    local Players = game:GetService("Players")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local player = Players.LocalPlayer
    local environment = getgenv()
    if type(environment.__RAVEN_ROLL_A_GNOME) == "table"
        and type(environment.__RAVEN_ROLL_A_GNOME.Destroy) == "function" then
        pcall(environment.__RAVEN_ROLL_A_GNOME.Destroy)
    end

    local Library = require(ReplicatedStorage:WaitForChild("Library"))
    local Network = Library.get("Network")
    assert(type(Network) == "table", "Roll A Gnome Network unavailable")

    local settings = {
        AutoCollect = false,
        AutoSell = false,
        CollectInterval = 0.75,
        SellInterval = 8,
        BatchSize = 8,
        RetryCooldown = 15,
    }
    local running = true
    local lastCollect = 0
    local lastSell = 0
    local stats = {Collected = 0, Sold = 0, LastError = nil}
    local attemptedFruitAt = {}

    local function getPlot()
        local plots = workspace:FindFirstChild("Plots")
        local plot = plots and plots:FindFirstChild("Plot_" .. tostring(player.UserId))
        if plot and plot:GetAttribute("TakenBy") == player.Name then return plot end
        return nil
    end

    local function getReadyPlants(limit)
        local plot = getPlot()
        local plants = plot and plot:FindFirstChild("Plants")
        local result = {}
        if not plants then return result end
        for _, plant in ipairs(plants:GetChildren()) do
            local ownerUserId = plant:GetAttribute("OwnerUserId")
            local hasReadyFruit = false
            local fruitFolder = plant:FindFirstChild("Fruit")
            if fruitFolder then
                for _, fruit in ipairs(fruitFolder:GetChildren()) do
                    if fruit:IsA("Model") and fruit:GetAttribute("READY") == true then
                        local fruitId = fruit:GetAttribute("FruitId")
                        local attemptedAt = fruitId and attemptedFruitAt[fruitId]
                        if not attemptedAt or os.clock() - attemptedAt >= settings.RetryCooldown then
                            hasReadyFruit = true
                            break
                        end
                    end
                end
            end
            if (ownerUserId == nil or ownerUserId == player.UserId) and hasReadyFruit then
                table.insert(result, plant)
                if #result >= (limit or settings.BatchSize) then break end
            end
        end
        return result
    end

    local function getReadyFruitCount()
        local count = 0
        local plot = getPlot()
        local plants = plot and plot:FindFirstChild("Plants")
        if not plants then return 0 end
        for _, plant in ipairs(plants:GetChildren()) do
            local folder = plant:FindFirstChild("Fruit")
            if folder then
                for _, fruit in ipairs(folder:GetChildren()) do
                    if fruit:IsA("Model") and fruit:GetAttribute("READY") == true then count += 1 end
                end
            end
        end
        return count
    end

    local function getSpawnedFruitCount()
        local count = 0
        local plot = getPlot()
        local plants = plot and plot:FindFirstChild("Plants")
        if not plants then return 0 end
        for _, plant in ipairs(plants:GetChildren()) do
            local folder = plant:FindFirstChild("Fruit")
            if folder then
                for _, fruit in ipairs(folder:GetChildren()) do
                    if fruit:IsA("Model") and fruit:GetAttribute("FruitId") ~= nil then count += 1 end
                end
            end
        end
        return count
    end

    local function getGrowingFruitCount()
        local count = 0
        local plot = getPlot()
        local plants = plot and plot:FindFirstChild("Plants")
        if not plants then return 0 end
        for _, plant in ipairs(plants:GetChildren()) do
            local folder = plant:FindFirstChild("Fruit")
            if folder then
                for _, fruit in ipairs(folder:GetChildren()) do
                    if fruit:IsA("Model") and fruit:GetAttribute("FruitId") ~= nil
                        and fruit:GetAttribute("READY") ~= true then
                        count += 1
                    end
                end
            end
        end
        return count
    end

    local function getInventoryCount()
        local count = 0
        for _, item in ipairs(player.Backpack:GetChildren()) do
            if item:IsA("Tool") then count += 1 end
        end
        local character = player.Character
        if character then
            for _, item in ipairs(character:GetChildren()) do
                if item:IsA("Tool") then count += 1 end
            end
        end
        return count
    end

    local function collectReady(limit)
        local inventoryBefore = getInventoryCount()
        local originalCanCollect = player:GetAttribute("CanCollect")
        player:SetAttribute("CanCollect", true)

        local loopOk, loopError = pcall(function()
            for _, plant in ipairs(getReadyPlants(limit)) do
                local fruitIds = {}
                local folder = plant:FindFirstChild("Fruit")
                if folder then
                    for _, fruit in ipairs(folder:GetChildren()) do
                        if fruit:IsA("Model") and fruit:GetAttribute("READY") == true then
                            local fruitId = fruit:GetAttribute("FruitId")
                            if fruitId then table.insert(fruitIds, fruitId) end
                        end
                    end
                end

                local ok, response = pcall(function()
                    return Network:InvokeServer("CollectPlant", plant)
                end)
                if not ok then
                    stats.LastError = tostring(response)
                elseif response == false then
                    stats.LastError = "CollectPlant returned false"
                else
                    local attemptedAt = os.clock()
                    for _, fruitId in ipairs(fruitIds) do
                        attemptedFruitAt[fruitId] = attemptedAt
                    end
                end
            end
        end)

        player:SetAttribute("CanCollect", originalCanCollect)
        if not loopOk then
            stats.LastError = tostring(loopError)
        end

        task.wait(0.1)
        local collected = math.max(0, getInventoryCount() - inventoryBefore)
        stats.Collected += collected
        return collected
    end

    local function sellAll()
        local ok, response = pcall(function()
            return Network:InvokeServer("SellAll")
        end)
        if not ok then
            stats.LastError = tostring(response)
            return false, response
        end
        if response ~= false and response ~= "No Plants" then stats.Sold += 1 end
        return response ~= false, response
    end

    local tab = Window:CreateTab("Gnome Farm", 4483362458)
    tab:CreateSection("Fruit Automation")
    local status = tab:CreateLabel("Growing: 0 | Ready: 0 | Collected: 0 | Sold: 0")
    tab:CreateToggle({
        Name = "Auto Collect Ready Fruit",
        CurrentValue = false,
        Flag = "RollAGnomeAutoCollect",
        Callback = function(value) settings.AutoCollect = value == true end,
    })
    tab:CreateSlider({
        Name = "Collect Interval",
        Range = {0.25, 3},
        Increment = 0.25,
        CurrentValue = 0.75,
        Suffix = " s",
        Flag = "RollAGnomeCollectInterval",
        Callback = function(value) settings.CollectInterval = value end,
    })
    tab:CreateSlider({
        Name = "Plants Per Batch",
        Range = {1, 20},
        Increment = 1,
        CurrentValue = 8,
        Flag = "RollAGnomeBatchSize",
        Callback = function(value) settings.BatchSize = value end,
    })
    tab:CreateSlider({
        Name = "Same Fruit Retry",
        Range = {5, 60},
        Increment = 5,
        CurrentValue = 15,
        Suffix = " s",
        Flag = "RollAGnomeRetryCooldown",
        Callback = function(value) settings.RetryCooldown = value end,
    })
    tab:CreateButton({Name = "Collect Ready Now", Callback = function() collectReady() end})

    tab:CreateSection("Selling")
    tab:CreateToggle({
        Name = "Auto Sell Inventory",
        CurrentValue = false,
        Flag = "RollAGnomeAutoSell",
        Callback = function(value) settings.AutoSell = value == true end,
    })
    tab:CreateSlider({
        Name = "Sell Interval",
        Range = {3, 30},
        Increment = 1,
        CurrentValue = 8,
        Suffix = " s",
        Flag = "RollAGnomeSellInterval",
        Callback = function(value) settings.SellInterval = value end,
    })
    tab:CreateButton({Name = "Sell Inventory Now", Callback = function() sellAll() end})

    task.spawn(function()
        while running do
            local now = os.clock()
            if settings.AutoCollect and now - lastCollect >= settings.CollectInterval then
                lastCollect = now
                collectReady()
            end
            if settings.AutoSell and now - lastSell >= settings.SellInterval then
                lastSell = now
                sellAll()
            end
            pcall(function()
                status:Set(string.format("Growing: %d | Ready: %d | Collected: %d | Sold: %d",
                    getGrowingFruitCount(), getReadyFruitCount(), stats.Collected, stats.Sold))
            end)
            task.wait(0.2)
        end
    end)

    local function destroy()
        if not running then return end
        running = false
        if environment.__RAVEN_ROLL_A_GNOME
            and environment.__RAVEN_ROLL_A_GNOME.Settings == settings then
            environment.__RAVEN_ROLL_A_GNOME = nil
        end
    end

    environment.__RAVEN_ROLL_A_GNOME = {
        Version = "v1.0.8",
        Settings = settings,
        Stats = stats,
        GetPlot = getPlot,
        GetReadyPlants = getReadyPlants,
        GetReadyFruitCount = getReadyFruitCount,
        GetSpawnedFruitCount = getSpawnedFruitCount,
        GetGrowingFruitCount = getGrowingFruitCount,
        GetInventoryCount = getInventoryCount,
        AttemptedFruitAt = attemptedFruitAt,
        CollectReady = collectReady,
        SellAll = sellAll,
        Destroy = destroy,
    }
    if runtimeInfo and type(runtimeInfo.registerCleanup) == "function" then
        runtimeInfo.registerCleanup(destroy)
    end
end
