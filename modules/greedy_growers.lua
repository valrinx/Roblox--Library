-- ═══════════════════════════════════════════════════════════
-- Greedy Growers | RAVEN HUB Module
-- Features: Auto Collect, Auto Sell, Auto Plant, Anti-Meteor, Auto Buy
-- ═══════════════════════════════════════════════════════════
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local M = { Tabs = {}, Connections = {} }

-- ═══════════ Utility ═══════════
local function getChar()
    return Player.Character or Player.CharacterAdded:Wait()
end

local function getRoot()
    local c = getChar()
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function tpTo(pos)
    local root = getRoot()
    if root then root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) end
end

local function distTo(pos)
    local root = getRoot()
    return root and (root.Position - pos).Magnitude or 999
end

local function safeFire(pp)
    if not pp then return end
    pcall(function()
        fireproximityprompt(pp, 0)
    end)
end

local function toggleConnection(key, enabled, func)
    if M.Connections[key] then
        M.Connections[key]:Disconnect()
        M.Connections[key] = nil
    end
    if enabled and func then
        M.Connections[key] = RunService.Heartbeat:Connect(func)
    end
end

-- ═══════════ Config ═══════════
M.Config = {
    -- Collect
    autoCollect = false,
    collectDelay = 0.3,
    -- Sell
    autoSell = false,
    sellInterval = 5,
    -- Plant
    autoPlant = false,
    -- Anti-Meteor
    antiMeteor = false,
    meteorFleeDist = 80,
    -- Buy
    autoBuySeed = false,
    selectedSeed = "Pine",
    buyDelay = 2,
    -- Misc
    autoGrowAll = false,
    collectAll = false,
    walkSpeed = 32,
    autoSpeed = false,
}

-- ═══════════ Fruit / Tree Scanning ═══════════
function M.getFruitSpawns()
    local fruits = {}
    -- Scan all ProximityPrompts with "Collect" action
    for _, pp in ipairs(Workspace:GetDescendants()) do
        if pp:IsA("ProximityPrompt") and pp.ActionText == "Collect" then
            local spawn = pp:FindFirstAncestorWhichIsA("BasePart")
            if spawn then
                table.insert(fruits, {prompt = pp, part = spawn})
            end
        end
    end
    return fruits
end

function M.getSellStand()
    for _, pp in ipairs(Workspace:GetDescendants()) do
        if pp:IsA("ProximityPrompt") and pp.ActionText == "Sell" then
            return pp
        end
    end
    return nil
end

function M.getSeedHolders()
    local seeds = {}
    for _, pp in ipairs(Workspace:GetDescendants()) do
        if pp:IsA("ProximityPrompt") and pp.ActionText == "Buy" then
            local holder = pp:FindFirstAncestorWhichIsA("Model")
            local part = pp:FindFirstAncestorWhichIsA("BasePart")
            if holder and part then
                table.insert(seeds, {
                    prompt = pp,
                    part = part,
                    name = pp.ObjectText
                })
            end
        end
    end
    return seeds
end

function M.getPlantPrompts()
    local prompts = {}
    for _, pp in ipairs(Workspace:GetDescendants()) do
        if pp:IsA("ProximityPrompt") and pp.ActionText == "Plant Seed" then
            local part = pp:FindFirstAncestorWhichIsA("BasePart")
            if part then
                table.insert(prompts, {prompt = pp, part = part})
            end
        end
    end
    return prompts
end

function M.getGrowAll()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.ActionText == "Buy" and obj.ObjectText == "Grow All Fruits" then
            return obj
        end
    end
    return nil
end

function M.getCollectAll()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.ActionText == "Buy" and obj.ObjectText == "Collect All Fruits" then
            return obj
        end
    end
    return nil
end

-- ═══════════ Weather Detection ═══════════
function M.getCurrentWeather()
    -- Check Workspace for weather effects or surface GUI
    for _, obj in ipairs(Workspace:GetChildren()) do
        local name = obj.Name:lower()
        if name:find("rain") or name:find("storm") or name:find("meteor") or name:find("weather") then
            return obj.Name
        end
    end
    -- Check ScreenGui for weather indicator
    local gui = PlayerGui:FindFirstChild("MainUI") or PlayerGui:FindFirstChild("HUD")
    if gui then
        for _, label in ipairs(gui:GetDescendants()) do
            if label:IsA("TextLabel") or label:IsA("Frame") then
                local txt = label.Text or label.Name
                if txt:lower():find("meteor") or txt:lower():find("storm") then
                    return txt
                end
            end
        end
    end
    -- Check surface gui on map
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("SurfaceGui") then
            for _, child in ipairs(desc:GetChildren()) do
                if child:IsA("TextLabel") then
                    local t = child.Text:lower()
                    if t:find("meteor") or t:find("storm") or t:find("weather") then
                        return child.Text
                    end
                end
            end
        end
    end
    return nil
end

function M.isDangerousWeather()
    local w = M.getCurrentWeather()
    if not w then return false end
    local wl = w:lower()
    return wl:find("meteor") ~= nil or wl:find("storm") ~= nil or wl:find("lightning") ~= nil
end

-- ═══════════ TAB: Collect ═══════════
M.Tabs[#M.Tabs + 1] = {
    name = "Collect",
    {
        type = "toggle",
        label = "Auto Collect",
        key = "autoCollect",
        callback = function(v)
            M.Config.autoCollect = v
            toggleConnection("autoCollect", v, function()
                if not M.Config.autoCollect then return end
                local fruits = M.getFruitSpawns()
                for _, f in ipairs(fruits) do
                    if not M.Config.autoCollect then break end
                    tpTo(f.part.Position)
                    task.wait(0.15)
                    safeFire(f.prompt)
                    task.wait(M.Config.collectDelay)
                end
            end)
        end
    },
    {
        type = "slider",
        label = "Collect Delay",
        key = "collectDelay",
        min = 0.1,
        max = 2,
        default = 0.3,
        callback = function(v) M.Config.collectDelay = v end
    },
    {
        type = "button",
        label = "Collect All (One-shot)",
        callback = function()
            local pp = M.getCollectAll()
            if pp then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(pp)
            else
                -- Fallback: collect each fruit
                local fruits = M.getFruitSpawns()
                for _, f in ipairs(fruits) do
                    tpTo(f.part.Position)
                    task.wait(0.15)
                    safeFire(f.prompt)
                    task.wait(0.2)
                end
            end
        end
    },
}

-- ═══════════ TAB: Sell ═══════════
M.Tabs[#M.Tabs + 1] = {
    name = "Sell",
    {
        type = "toggle",
        label = "Auto Sell",
        key = "autoSell",
        callback = function(v)
            M.Config.autoSell = v
            toggleConnection("autoSell", v, function()
                if not M.Config.autoSell then return end
                local pp = M.getSellStand()
                if pp then
                    local part = pp:FindFirstAncestorWhichIsA("BasePart")
                    if part then tpTo(part.Position) end
                    task.wait(0.2)
                    safeFire(pp)
                    task.wait(M.Config.sellInterval)
                end
            end)
        end
    },
    {
        type = "slider",
        label = "Sell Interval (s)",
        key = "sellInterval",
        min = 1,
        max = 15,
        default = 5,
        callback = function(v) M.Config.sellInterval = v end
    },
    {
        type = "button",
        label = "Sell Now",
        callback = function()
            local pp = M.getSellStand()
            if pp then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(pp)
            end
        end
    },
}

-- ═══════════ TAB: Plant ═══════════
M.Tabs[#M.Tabs + 1] = {
    name = "Plant",
    {
        type = "toggle",
        label = "Auto Plant",
        key = "autoPlant",
        callback = function(v)
            M.Config.autoPlant = v
            toggleConnection("autoPlant", v, function()
                if not M.Config.autoPlant then return end
                local prompts = M.getPlantPrompts()
                for _, p in ipairs(prompts) do
                    if not M.Config.autoPlant then break end
                    tpTo(p.part.Position)
                    task.wait(0.15)
                    safeFire(p.prompt)
                    task.wait(0.5)
                end
            end)
        end
    },
    {
        type = "button",
        label = "Grow All",
        callback = function()
            local pp = M.getGrowAll()
            if pp then
                local part = pp:FindFirstAncestorWhichIsA("BasePart")
                if part then tpTo(part.Position); task.wait(0.2) end
                safeFire(pp)
            end
        end
    },
    {
        type = "button",
        label = "Plant All (One-shot)",
        callback = function()
            local prompts = M.getPlantPrompts()
            for _, p in ipairs(prompts) do
                tpTo(p.part.Position)
                task.wait(0.15)
                safeFire(p.prompt)
                task.wait(0.5)
            end
        end
    },
}

-- ═══════════ TAB: Buy Seeds ═══════════
M.Tabs[#M.Tabs + 1] = {
    name = "Buy Seeds",
    {
        type = "dropdown",
        label = "Seed Type",
        key = "selectedSeed",
        options = {"Pine", "Oak", "Lemon", "Mango", "Apple", "Fig"},
        callback = function(v) M.Config.selectedSeed = v end
    },
    {
        type = "toggle",
        label = "Auto Buy Seed",
        key = "autoBuySeed",
        callback = function(v)
            M.Config.autoBuySeed = v
            toggleConnection("autoBuySeed", v, function()
                if not M.Config.autoBuySeed then return end
                local seeds = M.getSeedHolders()
                for _, s in ipairs(seeds) do
                    if not M.Config.autoBuySeed then break end
                    if s.name:lower():find(M.Config.selectedSeed:lower()) then
                        tpTo(s.part.Position)
                        task.wait(0.15)
                        safeFire(s.prompt)
                        task.wait(M.Config.buyDelay)
                    end
                end
            end)
        end
    },
    {
        type = "slider",
        label = "Buy Delay (s)",
        key = "buyDelay",
        min = 1,
        max = 10,
        default = 2,
        callback = function(v) M.Config.buyDelay = v end
    },
    {
        type = "button",
        label = "Buy Selected Seed",
        callback = function()
            local seeds = M.getSeedHolders()
            for _, s in ipairs(seeds) do
                if s.name:lower():find(M.Config.selectedSeed:lower()) then
                    tpTo(s.part.Position)
                    task.wait(0.15)
                    safeFire(s.prompt)
                    break
                end
            end
        end
    },
}

-- ═══════════ TAB: Weather ═══════════
M.Tabs[#M.Tabs + 1] = {
    name = "Weather",
    {
        type = "toggle",
        label = "Anti-Meteor (Auto Flee)",
        key = "antiMeteor",
        callback = function(v)
            M.Config.antiMeteor = v
            toggleConnection("antiMeteor", v, function()
                if not M.Config.antiMeteor then return end
                if M.isDangerousWeather() then
                    local root = getRoot()
                    if root then
                        -- Flee by moving far away
                        local fleeDir = root.CFrame.LookVector * M.Config.meteorFleeDist
                        tpTo(root.Position + fleeDir)
                    end
                end
            end)
        end
    },
    {
        type = "label",
        text = "Current Weather: Checking..."
    },
    {
        type = "button",
        label = "Refresh Weather",
        callback = function()
            local w = M.getCurrentWeather()
            print("[GG] Weather: " .. (w or "None"))
        end
    },
}

-- ═══════════ TAB: Player ═══════════
M.Tabs[#M.Tabs + 1] = {
    name = "Player",
    {
        type = "toggle",
        label = "Auto Set Speed",
        key = "autoSpeed",
        callback = function(v)
            M.Config.autoSpeed = v
            toggleConnection("autoSpeed", v, function()
                if not M.Config.autoSpeed then return end
                local hum = getHumanoid()
                if hum then hum.WalkSpeed = M.Config.walkSpeed end
            end)
        end
    },
    {
        type = "slider",
        label = "Walk Speed",
        key = "walkSpeed",
        min = 16,
        max = 200,
        default = 32,
        callback = function(v)
            M.Config.walkSpeed = v
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = v end
        end
    },
    {
        type = "button",
        label = "Set Speed Now",
        callback = function()
            local hum = getHumanoid()
            if hum then hum.WalkSpeed = M.Config.walkSpeed end
        end
    },
}

-- ═══════════ TAB: Settings ═══════════
M.Tabs[#M.Tabs + 1] = {
    name = "Settings",
    {
        type = "label",
        text = "Greedy Growers v1.0 | RAVEN HUB"
    },
    {
        type = "button",
        label = "Scan Game (Debug)",
        callback = function()
            local fruits = M.getFruitSpawns()
            local sell = M.getSellStand()
            local seeds = M.getSeedHolders()
            local plants = M.getPlantPrompts()
            print(string.format("[GG] Fruits: %d | Sell: %s | Seeds: %d | Plants: %d",
                #fruits, tostring(sell ~= nil), #seeds, #plants))
        end
    },
    {
        type = "button",
        label = "Rejoin Server",
        callback = function()
            local ts = game:GetService("TeleportService")
            ts:Teleport(game.PlaceId, Player)
        end
    },
    {
        type = "button",
        label = "Server Hop",
        callback = function()
            pcall(function()
                local HttpService = game:GetService("HttpService")
                local tp = game:GetService("TeleportService")
                local tps = HttpService:JSONDecode(
                    game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=10")
                )
                if tps and tps.data then
                    for _, srv in ipairs(tps.data) do
                        if srv.id ~= game.JobId and srv.playing < srv.maxPlayers then
                            tp:TeleportToPlaceInstance(game.PlaceId, srv.id, Player)
                            break
                        end
                    end
                end
            end)
        end
    },
}

-- ═══════════ Init ═══════════
function M.init()
    print("[GG] Greedy Growers module loaded!")
    print("[GG] Fruits: " .. #M.getFruitSpawns())
end

return M
