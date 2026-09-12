-- ============================================================
--   RAVEN HUB  |  Universal Drawing API ESP Engine v1.0.0
--   Anti-Cheat Compliant (Zero Object Injection / 100% Drawing API)
--   High-Performance 2D Projection, Memory-Safe Lifecycle
-- ============================================================

local DrawingESP = {}
DrawingESP.__index = DrawingESP

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

-- Safe Drawing Instantiation
local function safeDrawing(drawingType)
    if not hasDrawing then return nil end
    local ok, obj = pcall(Drawing.new, drawingType)
    return (ok and obj) or nil
end

-- Dynamic HSV Health Color Lerp (0 = Red, 0.16 = Yellow, 0.33 = Green)
local function getHealthColor(hpRatio)
    local clamped = math.clamp(hpRatio, 0, 1)
    return Color3.fromHSV(clamped * 0.33, 0.9, 1.0)
end

-- Drawing Set Factory
local function createDrawingEntry()
    local d = {}

    d.boxOutline = safeDrawing("Square")
    if d.boxOutline then
        d.boxOutline.Thickness = 3
        d.boxOutline.Filled = false
        d.boxOutline.Color = Color3.fromRGB(0, 0, 0)
        d.boxOutline.Visible = false
    end

    d.box = safeDrawing("Square")
    if d.box then
        d.box.Thickness = 1
        d.box.Filled = false
        d.box.Color = Color3.fromRGB(255, 255, 255)
        d.box.Visible = false
    end

    d.name = safeDrawing("Text")
    if d.name then
        d.name.Size = 13
        d.name.Center = true
        d.name.Outline = true
        d.name.OutlineColor = Color3.fromRGB(0, 0, 0)
        d.name.Color = Color3.fromRGB(255, 255, 255)
        d.name.Visible = false
    end

    d.dist = safeDrawing("Text")
    if d.dist then
        d.dist.Size = 11
        d.dist.Center = true
        d.dist.Outline = true
        d.dist.OutlineColor = Color3.fromRGB(0, 0, 0)
        d.dist.Color = Color3.fromRGB(220, 220, 220)
        d.dist.Visible = false
    end

    d.hpBg = safeDrawing("Square")
    if d.hpBg then
        d.hpBg.Thickness = 1
        d.hpBg.Filled = true
        d.hpBg.Color = Color3.fromRGB(20, 20, 20)
        d.hpBg.Visible = false
    end

    d.hp = safeDrawing("Square")
    if d.hp then
        d.hp.Thickness = 1
        d.hp.Filled = true
        d.hp.Color = Color3.fromRGB(0, 255, 100)
        d.hp.Visible = false
    end

    d.hpText = safeDrawing("Text")
    if d.hpText then
        d.hpText.Size = 10
        d.hpText.Center = false
        d.hpText.Outline = true
        d.hpText.OutlineColor = Color3.fromRGB(0, 0, 0)
        d.hpText.Color = Color3.fromRGB(255, 255, 255)
        d.hpText.Visible = false
    end

    d.subText = safeDrawing("Text")
    if d.subText then
        d.subText.Size = 11
        d.subText.Center = true
        d.subText.Outline = true
        d.subText.OutlineColor = Color3.fromRGB(0, 0, 0)
        d.subText.Color = Color3.fromRGB(255, 220, 80)
        d.subText.Visible = false
    end

    d.head = safeDrawing("Circle")
    if d.head then
        d.head.Thickness = 1
        d.head.Filled = false
        d.head.Radius = 3
        d.head.Color = Color3.fromRGB(255, 255, 255)
        d.head.Visible = false
    end

    d.tracer = safeDrawing("Line")
    if d.tracer then
        d.tracer.Thickness = 1
        d.tracer.Color = Color3.fromRGB(255, 90, 90)
        d.tracer.Visible = false
    end

    return d
end

local function hideDrawingEntry(d)
    if not d then return end
    for _, obj in pairs(d) do
        if obj and obj.Visible then
            pcall(function() obj.Visible = false end)
        end
    end
end

local function removeDrawingEntry(d)
    if not d then return end
    for _, obj in pairs(d) do
        if obj then
            pcall(function()
                obj.Visible = false
                obj:Remove()
            end)
        end
    end
end

-- ============================================================
--   CONSTRUCTOR
-- ============================================================
function DrawingESP.new(options)
    local self = setmetatable({}, DrawingESP)

    self.options = {
        enabled = true,
        showBoxes = true,
        boxOutline = true,
        showNames = true,
        showDistance = true,
        showHealth = true,
        showHealthText = true,
        showSubText = true,
        showHeadDot = false,
        showTracers = false,
        teamCheck = false,
        maxDistance = 2000,
        tracerOrigin = "bottom", -- "bottom" or "center"

        -- Colors
        enemyColor = Color3.fromRGB(255, 65, 65),
        teamColor = Color3.fromRGB(65, 220, 120),
        objectColor = Color3.fromRGB(240, 200, 40),
        headColor = Color3.fromRGB(255, 255, 255),
    }

    if type(options) == "table" then
        for k, v in pairs(options) do
            self.options[k] = v
        end
    end

    self.targets = {}       -- id -> target definition
    self.drawings = {}      -- id -> drawing objects set
    self.connections = {}
    self.running = true

    -- Render Loop
    self.connections.render = RunService.RenderStepped:Connect(function()
        self:Render()
    end)

    return self
end

-- ============================================================
--   TARGET MANAGEMENT
-- ============================================================

--[[
    targetData options:
    - part (BasePart or function returning BasePart) [Required]
    - model (Model or Instance) [Optional]
    - name (string or function returning string) [Optional]
    - subText (string or function returning string) [Optional]
    - getHealth (function returning hp, maxHp) [Optional]
    - isTeammate (boolean or function returning boolean) [Optional]
    - isDead (boolean or function returning boolean) [Optional]
    - color (Color3 or function returning Color3) [Optional]
    - headPart (BasePart or function) [Optional]
]]
function DrawingESP:AddTarget(id, targetData)
    if not id or not targetData then return end
    self.targets[id] = targetData
end

function DrawingESP:RemoveTarget(id)
    if self.drawings[id] then
        removeDrawingEntry(self.drawings[id])
        self.drawings[id] = nil
    end
    self.targets[id] = nil
end

function DrawingESP:ClearTargets()
    for id, d in pairs(self.drawings) do
        removeDrawingEntry(d)
    end
    table.clear(self.drawings)
    table.clear(self.targets)
end

-- ============================================================
--   RENDER PIPELINE
-- ============================================================
function DrawingESP:Render()
    if not self.running or not hasDrawing then return end

    local camera = Workspace.CurrentCamera
    if not camera then return end

    if not self.options.enabled then
        for _, d in pairs(self.drawings) do
            hideDrawingEntry(d)
        end
        return
    end

    local myPos = camera.CFrame.Position
    local viewportSize = camera.ViewportSize
    local activeIds = {}

    for id, target in pairs(self.targets) do
        activeIds[id] = true

        if not self.drawings[id] then
            self.drawings[id] = createDrawingEntry()
        end
        local d = self.drawings[id]

        -- 1. Check dead / validity
        local isDead = false
        if type(target.isDead) == "function" then
            isDead = target.isDead() == true
        elseif target.isDead ~= nil then
            isDead = target.isDead == true
        end

        if isDead then
            hideDrawingEntry(d)
            continue
        end

        -- 2. Resolve Root Part
        local part = target.part
        if type(part) == "function" then part = part() end
        if not part or not part.Parent or not part:IsA("BasePart") then
            hideDrawingEntry(d)
            continue
        end

        -- 3. Distance check
        local rootPos3D = part.Position
        local dist = (rootPos3D - myPos).Magnitude
        if dist > self.options.maxDistance then
            hideDrawingEntry(d)
            continue
        end

        -- 4. Teammate check
        local isTeammate = false
        if type(target.isTeammate) == "function" then
            isTeammate = target.isTeammate() == true
        elseif target.isTeammate ~= nil then
            isTeammate = target.isTeammate == true
        end

        if self.options.teamCheck and isTeammate then
            hideDrawingEntry(d)
            continue
        end

        -- 5. Screen projection
        local rootScreen, onScreen = camera:WorldToViewportPoint(rootPos3D)
        if not onScreen or rootScreen.Z <= 0 then
            hideDrawingEntry(d)
            continue
        end

        -- Head calculation
        local headPart = target.headPart
        if type(headPart) == "function" then headPart = headPart() end
        local headPos3D = headPart and headPart.Position or (rootPos3D + Vector3.new(0, 1.5, 0))

        local topWorld = headPos3D + Vector3.new(0, 0.7, 0)
        local bottomWorld = rootPos3D - Vector3.new(0, 2.7, 0)

        local topScreen = camera:WorldToViewportPoint(topWorld)
        local bottomScreen = camera:WorldToViewportPoint(bottomWorld)

        local boxHeight = math.abs(bottomScreen.Y - topScreen.Y)
        if boxHeight < 4 then
            hideDrawingEntry(d)
            continue
        end

        local boxWidth = math.floor(boxHeight * 0.58)
        local boxX = math.floor(rootScreen.X - boxWidth / 2)
        local boxY = math.floor(topScreen.Y)

        -- Color resolution
        local mainColor = self.options.objectColor
        if target.color then
            mainColor = type(target.color) == "function" and target.color() or target.color
        elseif target.isTeammate ~= nil then
            mainColor = isTeammate and self.options.teamColor or self.options.enemyColor
        end

        -- 1. Bounding Box
        if self.options.showBoxes and d.box then
            if self.options.boxOutline and d.boxOutline then
                d.boxOutline.Size = Vector2.new(boxWidth + 2, boxHeight + 2)
                d.boxOutline.Position = Vector2.new(boxX - 1, boxY - 1)
                d.boxOutline.Visible = true
            elseif d.boxOutline then
                d.boxOutline.Visible = false
            end

            d.box.Size = Vector2.new(boxWidth, boxHeight)
            d.box.Position = Vector2.new(boxX, boxY)
            d.box.Color = mainColor
            d.box.Visible = true
        else
            if d.box then d.box.Visible = false end
            if d.boxOutline then d.boxOutline.Visible = false end
        end

        -- 2. Target Name
        if self.options.showNames and d.name then
            local nameText = target.name
            if type(nameText) == "function" then nameText = nameText() end
            d.name.Text = tostring(nameText or part.Name)
            d.name.Position = Vector2.new(boxX + boxWidth / 2, boxY - 16)
            d.name.Color = mainColor
            d.name.Visible = true
        else
            if d.name then d.name.Visible = false end
        end

        -- 3. Distance Label
        if self.options.showDistance and d.dist then
            local meters = math.floor(dist * 0.28)
            d.dist.Text = string.format("[%dm]", meters)
            d.dist.Position = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight + 2)
            d.dist.Visible = true
        else
            if d.dist then d.dist.Visible = false end
        end

        -- 4. Health Bar
        if self.options.showHealth and target.getHealth and d.hp and d.hpBg then
            local hp, maxHp = target.getHealth()
            hp = tonumber(hp) or 100
            maxHp = tonumber(maxHp) or 100

            local hpRatio = math.clamp(hp / math.max(maxHp, 1), 0, 1)
            local barWidth = 3
            local barX = boxX - barWidth - 3

            d.hpBg.Size = Vector2.new(barWidth, boxHeight + 2)
            d.hpBg.Position = Vector2.new(barX, boxY - 1)
            d.hpBg.Visible = true

            local fillHeight = math.floor(boxHeight * hpRatio)
            d.hp.Size = Vector2.new(barWidth, fillHeight)
            d.hp.Position = Vector2.new(barX, boxY + (boxHeight - fillHeight))
            d.hp.Color = getHealthColor(hpRatio)
            d.hp.Visible = true

            if self.options.showHealthText and d.hpText and hp < maxHp then
                d.hpText.Text = tostring(math.floor(hp))
                d.hpText.Position = Vector2.new(barX - 22, boxY + (boxHeight - fillHeight) - 2)
                d.hpText.Visible = true
            else
                if d.hpText then d.hpText.Visible = false end
            end
        else
            if d.hp then d.hp.Visible = false end
            if d.hpBg then d.hpBg.Visible = false end
            if d.hpText then d.hpText.Visible = false end
        end

        -- 5. SubText (Weapon / Rarity / Value)
        if self.options.showSubText and target.subText and d.subText then
            local sub = target.subText
            if type(sub) == "function" then sub = sub() end
            if sub and sub ~= "" then
                d.subText.Text = tostring(sub)
                local offsetY = self.options.showDistance and 15 or 2
                d.subText.Position = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight + offsetY)
                d.subText.Visible = true
            else
                d.subText.Visible = false
            end
        else
            if d.subText then d.subText.Visible = false end
        end

        -- 6. Head Dot / Circle
        if self.options.showHeadDot and d.head then
            local headScreen, headOnScreen = camera:WorldToViewportPoint(headPos3D)
            if headOnScreen and headScreen.Z > 0 then
                d.head.Position = Vector2.new(headScreen.X, headScreen.Y)
                d.head.Radius = math.clamp(boxWidth * 0.16, 2, 7)
                d.head.Color = self.options.headColor
                d.head.Visible = true
            else
                d.head.Visible = false
            end
        else
            if d.head then d.head.Visible = false end
        end

        -- 7. Snaplines / Tracers
        if self.options.showTracers and d.tracer then
            local originY = (self.options.tracerOrigin == "center") and (viewportSize.Y / 2) or viewportSize.Y
            d.tracer.From = Vector2.new(viewportSize.X / 2, originY)
            d.tracer.To = Vector2.new(boxX + boxWidth / 2, boxY + boxHeight)
            d.tracer.Color = mainColor
            d.tracer.Visible = true
        else
            if d.tracer then d.tracer.Visible = false end
        end
    end

    -- Cleanup missing targets from drawing cache
    for id, d in pairs(self.drawings) do
        if not activeIds[id] then
            removeDrawingEntry(d)
            self.drawings[id] = nil
        end
    end
end

-- ============================================================
--   LIFECYCLE & TEARDOWN
-- ============================================================
function DrawingESP:Destroy()
    self.running = false
    for _, conn in pairs(self.connections) do
        if conn and conn.Disconnect then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(self.connections)

    for _, d in pairs(self.drawings) do
        removeDrawingEntry(d)
    end
    table.clear(self.drawings)
    table.clear(self.targets)
end

return DrawingESP
