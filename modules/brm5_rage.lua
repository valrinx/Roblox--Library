--[[
    RAVEN HUB v3.2 — BRM5 (Blackhawk Rescue Mission 5)
    PlaceId: 3701546109
    
    Features:
    - No Recoil + No Sway (GC patch)
    - Speed Hack (Heartbeat-based)
    - NoClip (Stepped-based)
    - Fullbright + No Fog
    - ESP v8 (Player + NPC/AI detection)
    
    UI: MacLib
    Executor: Potassium compatible (no 'continue' keyword)
    
    IMPORTANT: No server-validated remotes are fired.
    All features are client-side only.
]]

-- ═══════════════════════════════════════════════
-- CLEANUP PREVIOUS INSTANCE
-- ═══════════════════════════════════════════════
if getgenv().__RAVEN_CLEANUP then
    for _, fn in ipairs(getgenv().__RAVEN_CLEANUP) do
        pcall(fn)
    end
end
getgenv().__RAVEN_CLEANUP = {}
getgenv().__RAVEN_NORECOIL_ACTIVE = false
getgenv().__RAVEN_ESP_ACTIVE = false

task.wait(0.5)

-- ═══════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ═══════════════════════════════════════════════
-- LOAD MACLIB UI
-- ═══════════════════════════════════════════════
local MacLib = loadstring(game:HttpGet("https://github.com/biggaboy212/Maclib/releases/latest/download/maclib.txt"))()

local Window = MacLib.Window({
    Title = "RAVEN HUB",
    Subtitle = "BRM5 v3.2",
    Author = "valrinx",
    Size = UDim2.fromOffset(580, 460),
    DragStyle = 1,
    DisableMinimize = false,
})

-- Tabs
local TabOverview = Window:Tab({ Name = "Overview", Image = "rbxassetid://7733960981" })
local TabCombat = Window:Tab({ Name = "Combat", Image = "rbxassetid://7734053495" })
local TabESP = Window:Tab({ Name = "ESP", Image = "rbxassetid://7734009413" })

-- Overview Section
local SectionInfo = TabOverview:Section({ Name = "Info", Side = "Left" })
SectionInfo:Label({ Text = "RAVEN HUB v3.2 — BRM5" })
SectionInfo:Label({ Text = "No Recoil | Speed | NoClip | Fullbright | ESP" })
SectionInfo:Label({ Text = "All features are CLIENT-SIDE only." })
SectionInfo:Label({ Text = "Player: " .. (lp and lp.Name or "N/A") })

-- ═══════════════════════════════════════════════
-- COMBAT TAB
-- ═══════════════════════════════════════════════
local SectionRecoil = TabCombat:Section({ Name = "Weapon", Side = "Left" })
local SectionMovement = TabCombat:Section({ Name = "Movement", Side = "Right" })

-- ───────────────────────────────────────────────
-- NO RECOIL + NO SWAY (GC Patch Loop)
-- ───────────────────────────────────────────────
local recoilConn = nil

local function startNoRecoil()
    getgenv().__RAVEN_NORECOIL_ACTIVE = true
    recoilConn = task.spawn(function()
        while getgenv().__RAVEN_NORECOIL_ACTIVE do
            pcall(function()
                for _, obj in ipairs(getgc(true)) do
                    if type(obj) == "table" and rawget(obj, "_recoilSpring") then
                        local rs = rawget(obj, "_recoilSpring")
                        if type(rs) == "table" then
                            for k, _ in pairs(rs) do
                                if type(rs[k]) == "number" then
                                    rawset(rs, k, 0)
                                end
                            end
                        end
                    end
                    if type(obj) == "table" and rawget(obj, "_doSway") ~= nil then
                        rawset(obj, "_doSway", false)
                    end
                    if type(obj) == "table" and rawget(obj, "_recoilAmount") ~= nil then
                        rawset(obj, "_recoilAmount", 0)
                    end
                    if type(obj) == "table" and rawget(obj, "_swayAmount") ~= nil then
                        rawset(obj, "_swayAmount", 0)
                    end
                end
            end)
            task.wait(3)
        end
    end)
end

local function stopNoRecoil()
    getgenv().__RAVEN_NORECOIL_ACTIVE = false
end

SectionRecoil:Toggle({
    Name = "No Recoil + No Sway",
    Default = true,
    Callback = function(state)
        if state then
            startNoRecoil()
        else
            stopNoRecoil()
        end
    end,
})

-- Start by default
startNoRecoil()

-- ───────────────────────────────────────────────
-- SPEED HACK (Heartbeat)
-- ───────────────────────────────────────────────
local speedConn = nil
local speedEnabled = false
local speedValue = 24

local function updateSpeed()
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    if speedEnabled then
        speedConn = RunService.Heartbeat:Connect(function()
            pcall(function()
                local char = lp.Character or lp:FindFirstChild("WorldModel")
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then hum.WalkSpeed = speedValue end
                end
                -- Also check WorldModel for BRM5
                local wm = lp:FindFirstChild("WorldModel")
                if wm then
                    for _, child in ipairs(wm:GetChildren()) do
                        if child:IsA("Model") then
                            local hum2 = child:FindFirstChildOfClass("Humanoid")
                            if hum2 then hum2.WalkSpeed = speedValue end
                        end
                    end
                end
            end)
        end)
    end
end

SectionMovement:Toggle({
    Name = "Speed Hack",
    Default = false,
    Callback = function(state)
        speedEnabled = state
        updateSpeed()
    end,
})

SectionMovement:Slider({
    Name = "Walk Speed",
    Default = 24,
    Min = 16,
    Max = 60,
    Callback = function(val)
        speedValue = val
    end,
})

-- ───────────────────────────────────────────────
-- NOCLIP (Stepped)
-- ───────────────────────────────────────────────
local noclipConn = nil
local noclipEnabled = false

SectionMovement:Toggle({
    Name = "NoClip",
    Default = false,
    Callback = function(state)
        noclipEnabled = state
        if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
        if state then
            noclipConn = RunService.Stepped:Connect(function()
                pcall(function()
                    -- Check workspace for our model (closest to camera)
                    local myPos = camera.CFrame.Position
                    local closestDist = 9999
                    local selfModel = nil
                    for _, desc in ipairs(workspace:GetDescendants()) do
                        if desc.Name == "Root" and desc:IsA("BasePart") then
                            local model = desc.Parent
                            if model and model:IsA("Model") and (model.Name == "Male" or model.Name == "Female") then
                                local dist = (desc.Position - myPos).Magnitude
                                if dist < closestDist then
                                    closestDist = dist
                                    selfModel = model
                                end
                            end
                        end
                    end
                    if selfModel then
                        for _, part in ipairs(selfModel:GetDescendants()) do
                            if part:IsA("BasePart") then
                                part.CanCollide = false
                            end
                        end
                    end
                    -- Also WorldModel
                    local wm = lp:FindFirstChild("WorldModel")
                    if wm then
                        for _, child in ipairs(wm:GetDescendants()) do
                            if child:IsA("BasePart") then
                                child.CanCollide = false
                            end
                        end
                    end
                end)
            end)
        end
    end,
})

-- ───────────────────────────────────────────────
-- FULLBRIGHT + NO FOG
-- ───────────────────────────────────────────────
local fullbrightEnabled = false

local function applyFullbright()
    pcall(function()
        Lighting.Brightness = 3
        Lighting.ClockTime = 14
        Lighting.FogEnd = 1000000
        Lighting.GlobalShadows = false
        for _, v in ipairs(Lighting:GetDescendants()) do
            if v:IsA("Atmosphere") then
                v.Density = 0
                v.Offset = 0
            end
            if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") then
                v.Enabled = false
            end
        end
    end)
end

SectionRecoil:Toggle({
    Name = "Fullbright + No Fog",
    Default = false,
    Callback = function(state)
        fullbrightEnabled = state
        if state then applyFullbright() end
    end,
})

-- ═══════════════════════════════════════════════
-- ESP TAB
-- ═══════════════════════════════════════════════
local SectionESP = TabESP:Section({ Name = "ESP Settings", Side = "Left" })

-- ESP State
getgenv().__RAVEN_ESP_SETTINGS = {
    enabled = false,
    showBox = true,
    showName = true,
    showDistance = true,
    showHealth = true,
    maxDistance = 500,
}
getgenv().__RAVEN_ESP_DRAWINGS = {}

local espSettings = getgenv().__RAVEN_ESP_SETTINGS
local drawings = getgenv().__RAVEN_ESP_DRAWINGS

-- Colors
local COLOR_PLAYER = Color3.fromRGB(0, 200, 255)   -- Cyan = Players
local COLOR_NPC = Color3.fromRGB(255, 100, 50)     -- Red-Orange = NPC/AI

local function newDrawingSet()
    local s = {}
    s.boxO = Drawing.new("Square"); s.boxO.Thickness = 3; s.boxO.Color = Color3.new(0,0,0); s.boxO.Filled = false; s.boxO.Visible = false
    s.box = Drawing.new("Square"); s.box.Thickness = 1; s.box.Filled = false; s.box.Visible = false
    s.txt = Drawing.new("Text"); s.txt.Size = 14; s.txt.Center = true; s.txt.Outline = true; s.txt.Visible = false
    s.hp = Drawing.new("Square"); s.hp.Thickness = 1; s.hp.Filled = true; s.hp.Visible = false
    s.hpBg = Drawing.new("Square"); s.hpBg.Thickness = 1; s.hpBg.Filled = true; s.hpBg.Color = Color3.fromRGB(30,30,30); s.hpBg.Visible = false
    return s
end

local function hideSet(s)
    for _, d in pairs(s) do pcall(function() d.Visible = false end) end
end

local function startESP()
    getgenv().__RAVEN_ESP_ACTIVE = true
    task.spawn(function()
        while getgenv().__RAVEN_ESP_ACTIVE do
            local ok, err = pcall(function()
                RunService.RenderStepped:Wait()
                
                if not espSettings.enabled then
                    for _, s in pairs(drawings) do hideSet(s) end
                    return
                end
                
                local myPos = camera.CFrame.Position
                
                -- BRM5 Structure:
                --   Workspace.Model.Male = Players (has Humanoid)
                --   Workspace.Male = NPCs (no Humanoid, has AnimationController)
                
                local closestDist = 9999
                local selfModel = nil
                local targets = {}
                
                for _, desc in ipairs(workspace:GetDescendants()) do
                    if desc.Name == "Root" and desc:IsA("BasePart") then
                        local model = desc.Parent
                        if model and model:IsA("Model") and (model.Name == "Male" or model.Name == "Female") then
                            local dist = (desc.Position - myPos).Magnitude
                            if dist < closestDist then
                                closestDist = dist
                                selfModel = model
                            end
                            if dist <= espSettings.maxDistance then
                                local isPlayer = (model:FindFirstChildOfClass("Humanoid") ~= nil)
                                targets[#targets + 1] = {
                                    model = model,
                                    root = desc,
                                    dist = dist,
                                    isPlayer = isPlayer,
                                }
                            end
                        end
                    end
                end
                
                local activeModels = {}
                
                for i = 1, #targets do
                    local t = targets[i]
                    if t.model ~= selfModel then
                        activeModels[t.model] = true
                        if not drawings[t.model] then drawings[t.model] = newDrawingSet() end
                        local s = drawings[t.model]
                        
                        local espColor = t.isPlayer and COLOR_PLAYER or COLOR_NPC
                        
                        local head = t.model:FindFirstChild("Head")
                        local rootScreen, onScreen = camera:WorldToViewportPoint(t.root.Position)
                        
                        if onScreen and rootScreen.Z > 0 then
                            local headPos = head and (head.Position + Vector3.new(0, 1.5, 0)) or (t.root.Position + Vector3.new(0, 3, 0))
                            local feetPos = t.root.Position - Vector3.new(0, 3, 0)
                            local headScreen = camera:WorldToViewportPoint(headPos)
                            local feetScreen = camera:WorldToViewportPoint(feetPos)
                            local boxH = math.abs(headScreen.Y - feetScreen.Y)
                            local boxW = boxH * 0.55
                            
                            if boxH >= 4 then
                                -- Box outline
                                s.boxO.Size = Vector2.new(boxW+2, boxH+2)
                                s.boxO.Position = Vector2.new(rootScreen.X - boxW/2 - 1, headScreen.Y - 1)
                                s.boxO.Visible = espSettings.showBox
                                
                                -- Main box
                                s.box.Size = Vector2.new(boxW, boxH)
                                s.box.Position = Vector2.new(rootScreen.X - boxW/2, headScreen.Y)
                                s.box.Color = espColor
                                s.box.Visible = espSettings.showBox
                                
                                -- Label
                                local label = ""
                                if t.isPlayer then
                                    label = "[P] "
                                else
                                    label = "[AI] "
                                end
                                label = label .. math.floor(t.dist) .. "m"
                                
                                local hum = t.model:FindFirstChildOfClass("Humanoid")
                                if hum then
                                    label = label .. " | " .. math.floor(hum.Health) .. "HP"
                                end
                                
                                s.txt.Position = Vector2.new(rootScreen.X, headScreen.Y - 18)
                                s.txt.Text = label
                                s.txt.Color = espColor
                                s.txt.Visible = espSettings.showName
                                
                                -- Health bar
                                if hum and espSettings.showHealth then
                                    local pct = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
                                    local barX = rootScreen.X - boxW/2 - 6
                                    s.hpBg.Size = Vector2.new(3, boxH)
                                    s.hpBg.Position = Vector2.new(barX, headScreen.Y)
                                    s.hpBg.Visible = true
                                    s.hp.Size = Vector2.new(3, boxH * pct)
                                    s.hp.Position = Vector2.new(barX, headScreen.Y + boxH*(1-pct))
                                    s.hp.Color = Color3.fromRGB(math.floor(255*(1-pct)), math.floor(255*pct), 0)
                                    s.hp.Visible = true
                                else
                                    s.hp.Visible = false
                                    s.hpBg.Visible = false
                                end
                            else
                                hideSet(s)
                            end
                        else
                            hideSet(s)
                        end
                    end
                end
                
                -- Hide despawned models
                for model, s in pairs(drawings) do
                    if not activeModels[model] then hideSet(s) end
                end
            end)
            
            if not ok then
                task.wait(0.5)
            end
        end
        
        -- Cleanup ESP drawings
        for _, s in pairs(drawings) do
            for _, d in pairs(s) do pcall(function() d:Remove() end) end
        end
        getgenv().__RAVEN_ESP_DRAWINGS = {}
    end)
end

-- ESP UI Controls
SectionESP:Toggle({
    Name = "Enable ESP",
    Default = false,
    Callback = function(state)
        espSettings.enabled = state
    end,
})

SectionESP:Toggle({
    Name = "Show Box",
    Default = true,
    Callback = function(state)
        espSettings.showBox = state
    end,
})

SectionESP:Toggle({
    Name = "Show Name + Distance",
    Default = true,
    Callback = function(state)
        espSettings.showName = state
    end,
})

SectionESP:Toggle({
    Name = "Show Health Bar",
    Default = true,
    Callback = function(state)
        espSettings.showHealth = state
    end,
})

SectionESP:Slider({
    Name = "Max Distance",
    Default = 500,
    Min = 50,
    Max = 1000,
    Callback = function(val)
        espSettings.maxDistance = val
    end,
})

-- Start ESP loop
startESP()

-- ═══════════════════════════════════════════════
-- CLEANUP REGISTRATION
-- ═══════════════════════════════════════════════
table.insert(getgenv().__RAVEN_CLEANUP, function()
    getgenv().__RAVEN_NORECOIL_ACTIVE = false
    getgenv().__RAVEN_ESP_ACTIVE = false
    if speedConn then speedConn:Disconnect() end
    if noclipConn then noclipConn:Disconnect() end
    if recoilConn then task.cancel(recoilConn) end
    for _, s in pairs(getgenv().__RAVEN_ESP_DRAWINGS or {}) do
        for _, d in pairs(s) do pcall(function() d:Remove() end) end
    end
    getgenv().__RAVEN_ESP_DRAWINGS = {}
    pcall(function() Window:Destroy() end)
end)

-- ═══════════════════════════════════════════════
-- NOTIFICATION
-- ═══════════════════════════════════════════════
MacLib.Notification({
    Title = "RAVEN HUB",
    Description = "BRM5 v3.2 loaded! All features ready.",
    Duration = 5,
})
