-- ============================================================
--   RAVEN HUB  |  MacLib macOS Edition (100% Drawing API Engine)
--   Authentic Apple macOS Aesthetic | 1:1 MacLib Visual Fidelity
--   High-Contrast Bold Typography | macOS Section Container Cards
--   Apple Capsule Switches | 100% BAC / Frog Anti-Cheat Compliant
-- ============================================================

local DrawingUI = {}
DrawingUI.__index = DrawingUI
DrawingUI.Flags = {}

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")

local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"

local function safeDrawing(drawingType)
    if not hasDrawing then return nil end
    local ok, obj = pcall(Drawing.new, drawingType)
    return (ok and obj) or nil
end

local function pointInBox(pt, boxPos, boxSize)
    return pt.X >= boxPos.X and pt.X <= (boxPos.X + boxSize.X)
       and pt.Y >= boxPos.Y and pt.Y <= (boxPos.Y + boxSize.Y)
end

local function pointInCircle(pt, center, radius)
    local dx = pt.X - center.X
    local dy = pt.Y - center.Y
    return (dx * dx + dy * dy) <= (radius * radius)
end

local function sanitizeText(str)
    if type(str) ~= "string" then return tostring(str or "") end
    local clean = str:gsub("[^ -~]", "")
    clean = clean:gsub("%s+", " ")
    clean = clean:gsub("^%s*[:%-]%s*", "")
    local res = clean:gsub("^%s+", ""):gsub("%s+$", "")
    return res
end

local function setObjVisible(obj, visible)
    if obj and (type(obj) == "userdata" or type(obj) == "table") then
        pcall(function()
            obj.Visible = visible
        end)
    end
end

local function removeObj(obj)
    if obj and (type(obj) == "userdata" or type(obj) == "table") then
        pcall(function()
            obj.Visible = false
            if type(obj.Remove) == "function" then
                obj:Remove()
            end
        end)
    end
end

-- ============================================================
--   CRISP HIGH-CONTRAST TYPOGRAPHY (Native Drawing API Engine)
--   Font 2 = IBM Plex Sans: Naturally bold, thick, zero blur
-- ============================================================
local function createBoldText(baseZIndex, isHeavy)
    baseZIndex = baseZIndex or 6
    local t = safeDrawing("Text")
    if t then
        t.Font = 2 -- IBM Plex Sans: Solid stem geometry, zero subpixel blur
        t.Outline = false
        t.Color = Color3.fromRGB(255, 255, 255)
        pcall(function() t.ZIndex = baseZIndex end)
    end
    return t
end

-- ============================================================
--   ROUNDED GEOMETRY HELPERS (Drawing API Smooth macOS Shapes)
-- ============================================================
local function createRoundedCard(baseZIndex, isNeumorphic)
    baseZIndex = baseZIndex or 1
    local card = {
        -- Neumorphic Extruded Shadow (Underneath, Layer baseZIndex - 1)
        neuDropMid   = safeDrawing("Square"),
        neuDropBR    = safeDrawing("Circle"),

        -- Specular Top-Left Bevel Line (Light Highlight)
        neuLightTop  = safeDrawing("Line"),
        neuLightLeft = safeDrawing("Line"),

        -- Ambient Bottom-Right Shadow Line (Deep Occlusion)
        neuDarkBot   = safeDrawing("Line"),
        neuDarkRight = safeDrawing("Line"),

        -- Outer border stroke (optional)
        borderMid   = safeDrawing("Square"),
        borderLeft  = safeDrawing("Square"),
        borderRight = safeDrawing("Square"),
        borderTL    = safeDrawing("Circle"),
        borderTR    = safeDrawing("Circle"),
        borderBL    = safeDrawing("Circle"),
        borderBR    = safeDrawing("Circle"),

        -- Inner card fill
        bgMid       = safeDrawing("Square"),
        bgLeft      = safeDrawing("Square"),
        bgRight     = safeDrawing("Square"),
        bgTL        = safeDrawing("Circle"),
        bgTR        = safeDrawing("Circle"),
        bgBL        = safeDrawing("Circle"),
        bgBR        = safeDrawing("Circle"),
    }

    for k, obj in pairs(card) do
        if obj then
            obj.Filled = true
            obj.Thickness = 1
            obj.Visible = false
            if k == "neuDropMid" or k == "neuDropBR" then
                pcall(function() obj.ZIndex = math.max(0, baseZIndex - 1) end)
            elseif k == "neuLightTop" or k == "neuLightLeft" or k == "neuDarkBot" or k == "neuDarkRight" then
                pcall(function() obj.ZIndex = baseZIndex + 1 end)
            else
                pcall(function() obj.ZIndex = baseZIndex end)
            end
        end
    end

    function card:Update(pos, size, radius, bgColor, borderColor, visible, neuStyle)
        if not visible or size.X <= 0 or size.Y <= 0 then
            for _, o in pairs(self) do
                if type(o) == "userdata" or type(o) == "table" then
                    setObjVisible(o, false)
                end
            end
            return
        end

        local r = math.clamp(radius or 8, 1, math.floor(math.min(size.X, size.Y) / 2))

        -- 1. Neumorphic Extruded Drop Shadow (Layer - 1)
        if neuStyle == "raised" then
            if self.neuDropMid then
                self.neuDropMid.Position = Vector2.new(pos.X + 2, pos.Y + 2)
                self.neuDropMid.Size = size
                self.neuDropMid.Color = Color3.fromRGB(8, 9, 12)
                self.neuDropMid.Visible = true
            end
        else
            setObjVisible(self.neuDropMid, false)
            setObjVisible(self.neuDropBR, false)
        end

        -- 2. Outer Border Stroke (when borderColor provided)
        if borderColor then
            if self.borderMid then
                self.borderMid.Position = Vector2.new(pos.X + r, pos.Y)
                self.borderMid.Size = Vector2.new(math.max(1, size.X - 2 * r), size.Y)
                self.borderMid.Color = borderColor
                self.borderMid.Visible = true
            end
            if self.borderLeft then
                self.borderLeft.Position = Vector2.new(pos.X, pos.Y + r)
                self.borderLeft.Size = Vector2.new(r, math.max(1, size.Y - 2 * r))
                self.borderLeft.Color = borderColor
                self.borderLeft.Visible = true
            end
            if self.borderRight then
                self.borderRight.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
                self.borderRight.Size = Vector2.new(r, math.max(1, size.Y - 2 * r))
                self.borderRight.Color = borderColor
                self.borderRight.Visible = true
            end
            if self.borderTL then
                self.borderTL.Radius = r
                self.borderTL.Position = Vector2.new(pos.X + r, pos.Y + r)
                self.borderTL.Color = borderColor
                self.borderTL.Visible = true
            end
            if self.borderTR then
                self.borderTR.Radius = r
                self.borderTR.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
                self.borderTR.Color = borderColor
                self.borderTR.Visible = true
            end
            if self.borderBL then
                self.borderBL.Radius = r
                self.borderBL.Position = Vector2.new(pos.X + r, pos.Y + size.Y - r)
                self.borderBL.Color = borderColor
                self.borderBL.Visible = true
            end
            if self.borderBR then
                self.borderBR.Radius = r
                self.borderBR.Position = Vector2.new(pos.X + size.X - r, pos.Y + size.Y - r)
                self.borderBR.Color = borderColor
                self.borderBR.Visible = true
            end
        else
            setObjVisible(self.borderMid, false)
            setObjVisible(self.borderLeft, false)
            setObjVisible(self.borderRight, false)
            setObjVisible(self.borderTL, false)
            setObjVisible(self.borderTR, false)
            setObjVisible(self.borderBL, false)
            setObjVisible(self.borderBR, false)
        end

        -- 3. Inner Card Fill (1px inset if border is present)
        local inset = borderColor and 1 or 0
        local innerPos = pos + Vector2.new(inset, inset)
        local innerSize = size - Vector2.new(inset * 2, inset * 2)
        local innerR = math.max(1, r - inset)

        if self.bgMid then
            self.bgMid.Position = Vector2.new(innerPos.X + innerR, innerPos.Y)
            self.bgMid.Size = Vector2.new(math.max(1, innerSize.X - 2 * innerR), innerSize.Y)
            self.bgMid.Color = bgColor
            self.bgMid.Visible = true
        end
        if self.bgLeft then
            self.bgLeft.Position = Vector2.new(innerPos.X, innerPos.Y + innerR)
            self.bgLeft.Size = Vector2.new(innerR, math.max(1, innerSize.Y - 2 * innerR))
            self.bgLeft.Color = bgColor
            self.bgLeft.Visible = true
        end
        if self.bgRight then
            self.bgRight.Position = Vector2.new(innerPos.X + innerSize.X - innerR, innerPos.Y + innerR)
            self.bgRight.Size = Vector2.new(innerR, math.max(1, innerSize.Y - 2 * innerR))
            self.bgRight.Color = bgColor
            self.bgRight.Visible = true
        end
        if self.bgTL then
            self.bgTL.Radius = innerR
            self.bgTL.Position = Vector2.new(innerPos.X + innerR, innerPos.Y + innerR)
            self.bgTL.Color = bgColor
            self.bgTL.Visible = true
        end
        if self.bgTR then
            self.bgTR.Radius = innerR
            self.bgTR.Position = Vector2.new(innerPos.X + innerSize.X - innerR, innerPos.Y + innerR)
            self.bgTR.Color = bgColor
            self.bgTR.Visible = true
        end
        if self.bgBL then
            self.bgBL.Radius = innerR
            self.bgBL.Position = Vector2.new(innerPos.X + innerR, innerPos.Y + innerSize.Y - innerR)
            self.bgBL.Color = bgColor
            self.bgBL.Visible = true
        end
        if self.bgBR then
            self.bgBR.Radius = innerR
            self.bgBR.Position = Vector2.new(innerPos.X + innerSize.X - innerR, innerPos.Y + innerSize.Y - innerR)
            self.bgBR.Color = bgColor
            self.bgBR.Visible = true
        end

        -- 4. Neumorphic Dual-Bevel Lighting (Specular Light Top-Left & Ambient Shadow Bottom-Right)
        if neuStyle == "raised" then
            local highlightCol = Color3.fromRGB(56, 64, 86)
            local shadowCol = Color3.fromRGB(10, 11, 15)

            if self.neuLightTop then
                self.neuLightTop.From = Vector2.new(pos.X + r, pos.Y)
                self.neuLightTop.To = Vector2.new(pos.X + size.X - r, pos.Y)
                self.neuLightTop.Color = highlightCol
                self.neuLightTop.Visible = true
            end
            if self.neuLightLeft then
                self.neuLightLeft.From = Vector2.new(pos.X, pos.Y + r)
                self.neuLightLeft.To = Vector2.new(pos.X, pos.Y + size.Y - r)
                self.neuLightLeft.Color = highlightCol
                self.neuLightLeft.Visible = true
            end
            if self.neuDarkBot then
                self.neuDarkBot.From = Vector2.new(pos.X + r, pos.Y + size.Y)
                self.neuDarkBot.To = Vector2.new(pos.X + size.X - r, pos.Y + size.Y)
                self.neuDarkBot.Color = shadowCol
                self.neuDarkBot.Visible = true
            end
            if self.neuDarkRight then
                self.neuDarkRight.From = Vector2.new(pos.X + size.X, pos.Y + r)
                self.neuDarkRight.To = Vector2.new(pos.X + size.X, pos.Y + size.Y - r)
                self.neuDarkRight.Color = shadowCol
                self.neuDarkRight.Visible = true
            end
        else
            setObjVisible(self.neuLightTop, false)
            setObjVisible(self.neuLightLeft, false)
            setObjVisible(self.neuDarkBot, false)
            setObjVisible(self.neuDarkRight, false)
        end
    end

    function card:Remove()
        for _, o in pairs(self) do
            if type(o) == "userdata" or type(o) == "table" then
                removeObj(o)
            end
        end
    end

    return card
end

-- ============================================================
--   APPLE CAPSULE SWITCH (1:1 macOS Pill Toggle)
-- ============================================================
local function createPillSwitch(baseZIndex)
    baseZIndex = baseZIndex or 5
    local pill = {
        borderLeft  = safeDrawing("Circle"),
        borderRight = safeDrawing("Circle"),
        borderMid   = safeDrawing("Square"),
        cLeft       = safeDrawing("Circle"),
        cRight      = safeDrawing("Circle"),
        mid         = safeDrawing("Square"),
        knobShadow  = safeDrawing("Circle"),
        knob        = safeDrawing("Circle"),
    }

    if pill.borderLeft then pill.borderLeft.Filled = true; pill.borderLeft.Visible = false; pcall(function() pill.borderLeft.ZIndex = baseZIndex end) end
    if pill.borderRight then pill.borderRight.Filled = true; pill.borderRight.Visible = false; pcall(function() pill.borderRight.ZIndex = baseZIndex end) end
    if pill.borderMid then pill.borderMid.Filled = true; pill.borderMid.Thickness = 1; pill.borderMid.Visible = false; pcall(function() pill.borderMid.ZIndex = baseZIndex end) end
    if pill.cLeft then pill.cLeft.Filled = true; pill.cLeft.Visible = false; pcall(function() pill.cLeft.ZIndex = baseZIndex + 1 end) end
    if pill.cRight then pill.cRight.Filled = true; pill.cRight.Visible = false; pcall(function() pill.cRight.ZIndex = baseZIndex + 1 end) end
    if pill.mid then pill.mid.Filled = true; pill.mid.Thickness = 1; pill.mid.Visible = false; pcall(function() pill.mid.ZIndex = baseZIndex + 1 end) end
    if pill.knobShadow then pill.knobShadow.Filled = true; pill.knobShadow.Visible = false; pcall(function() pill.knobShadow.ZIndex = baseZIndex + 2 end) end
    if pill.knob then pill.knob.Filled = true; pill.knob.Visible = false; pcall(function() pill.knob.ZIndex = baseZIndex + 3 end) end

    function pill:Update(pos, size, value, colorOn, colorOff, borderColor, knobColor, visible)
        if not visible then
            setObjVisible(self.borderLeft, false)
            setObjVisible(self.borderRight, false)
            setObjVisible(self.borderMid, false)
            setObjVisible(self.cLeft, false)
            setObjVisible(self.cRight, false)
            setObjVisible(self.mid, false)
            setObjVisible(self.knobShadow, false)
            setObjVisible(self.knob, false)
            return
        end

        local r = size.Y / 2
        local bgCol = value and colorOn or colorOff
        local borderCol = value and colorOn or borderColor

        -- 1. Outer Neumorphic Cavity Rim (Sunken well effect)
        local cavityRimCol = value and Color3.fromRGB(44, 180, 78) or Color3.fromRGB(36, 40, 52)
        if self.borderLeft then
            self.borderLeft.Radius = r
            self.borderLeft.Position = Vector2.new(pos.X + r, pos.Y + r)
            self.borderLeft.Color = cavityRimCol
            self.borderLeft.Visible = true
        end
        if self.borderRight then
            self.borderRight.Radius = r
            self.borderRight.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
            self.borderRight.Color = cavityRimCol
            self.borderRight.Visible = true
        end
        if self.borderMid then
            self.borderMid.Position = Vector2.new(pos.X + r, pos.Y)
            self.borderMid.Size = Vector2.new(math.max(1, size.X - 2 * r), size.Y)
            self.borderMid.Color = cavityRimCol
            self.borderMid.Visible = true
        end

        -- 2. Inner Track Fill (Sunken Debossed Cavity)
        local ir = math.max(1, r - 1)
        local trackCol = value and colorOn or Color3.fromRGB(16, 18, 24)
        if self.cLeft then
            self.cLeft.Radius = ir
            self.cLeft.Position = Vector2.new(pos.X + r, pos.Y + r)
            self.cLeft.Color = trackCol
            self.cLeft.Visible = true
        end
        if self.cRight then
            self.cRight.Radius = ir
            self.cRight.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
            self.cRight.Color = trackCol
            self.cRight.Visible = true
        end
        if self.mid then
            self.mid.Position = Vector2.new(pos.X + r, pos.Y + 1)
            self.mid.Size = Vector2.new(math.max(1, size.X - 2 * r), math.max(1, size.Y - 2))
            self.mid.Color = trackCol
            self.mid.Visible = true
        end

        -- 3. Extruded Physical Knob with Dual-Layer Drop Shadow
        local knobR = r - 2.5
        local knobX = value and (pos.X + size.X - r) or (pos.X + r)
        if self.knobShadow then
            self.knobShadow.Radius = knobR + 1.5
            self.knobShadow.Position = Vector2.new(knobX, pos.Y + r + 1)
            self.knobShadow.Color = Color3.fromRGB(6, 7, 10)
            self.knobShadow.Visible = true
        end
        if self.knob then
            self.knob.Radius = knobR
            self.knob.Position = Vector2.new(knobX, pos.Y + r)
            self.knob.Color = knobColor
            self.knob.Visible = true
        end
    end

    function pill:Remove()
        removeObj(self.borderLeft)
        removeObj(self.borderRight)
        removeObj(self.borderMid)
        removeObj(self.cLeft)
        removeObj(self.cRight)
        removeObj(self.mid)
        removeObj(self.knobShadow)
        removeObj(self.knob)
    end

    return pill
end

local function hideItem(item)
    if item.pill then
        pcall(function() item.pill:Update(Vector2.zero, Vector2.zero, false, Color3.new(), Color3.new(), Color3.new(), Color3.new(), false) end)
    end
    if item.card then
        pcall(function() item.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end)
    end
    if item.buttonCard then
        pcall(function() item.buttonCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end)
    end
    for k, prop in pairs(item) do
        if k ~= "pill" and k ~= "card" and k ~= "buttonCard" and type(prop) ~= "function" then
            setObjVisible(prop, false)
        end
    end
    item.hitBox = nil
end

local function removeItem(item)
    if item.pill then
        pcall(function() item.pill:Remove() end)
    end
    if item.card then
        pcall(function() item.card:Remove() end)
    end
    if item.buttonCard then
        pcall(function() item.buttonCard:Remove() end)
    end
    for k, prop in pairs(item) do
        if k ~= "pill" and k ~= "card" and k ~= "buttonCard" and type(prop) ~= "function" then
            removeObj(prop)
        end
    end
end

-- ============================================================
--   APPLE macOS DARK THEME PALETTE (1:1 MacLib High-Fidelity)
-- ============================================================
local MAC_THEME = {
    -- Window Surfaces (Neumorphic macOS Dark Slate & Frosted Aluminum)
    bg             = Color3.fromRGB(24, 27, 36),       -- Main Chassis Base Surface (#181B24)
    bgSidebar      = Color3.fromRGB(18, 20, 28),       -- Debossed Inset Sidebar Cavity (#12141C)
    bgHeader       = Color3.fromRGB(26, 29, 39),       -- Header Top Surface (#1A1D27)
    border         = Color3.fromRGB(48, 54, 72),       -- Outer 1px Specular Stroke (#303648)
    divider        = Color3.fromRGB(12, 14, 18),       -- Deep Carved Seam Shadow (#0C0E12)
    dividerLight   = Color3.fromRGB(40, 46, 62),       -- Subtle Bevel Seam Reflection (#282E3E)

    -- Neumorphic Dual-Lighting (Specular Highlights & Ambient Shadows)
    neuHighlight   = Color3.fromRGB(56, 64, 86),       -- Top-Left Specular Rim (Soft Light Bevel)
    neuShadow      = Color3.fromRGB(10, 11, 15),       -- Bottom-Right Deep Ambient Occlusion Shadow
    neuRaisedBg    = Color3.fromRGB(30, 34, 46),       -- Extruded Raised Surface (Cards & Buttons)
    neuRaisedHover = Color3.fromRGB(36, 42, 58),       -- Raised Surface Hover Glow
    neuInsetBg     = Color3.fromRGB(16, 18, 24),       -- Debossed / Sunken Cavity (Tracks & Wells)
    neuDropShadow  = Color3.fromRGB(6, 7, 10),         -- Deep Window Cast Shadow

    -- macOS Window Traffic Lights (1:1 Apple Specifications with Neumorphic Sockets)
    trafficRed     = Color3.fromRGB(255, 95, 87),
    trafficYellow  = Color3.fromRGB(255, 189, 46),
    trafficGreen   = Color3.fromRGB(39, 201, 63),
    trafficSocket  = Color3.fromRGB(14, 16, 22),       -- Recessed Socket Ring

    -- Typography (High-Contrast, Maximum Clarity, 100% Crisp Integer Grid)
    title          = Color3.fromRGB(255, 255, 255),    -- Pure White Window Header (#FFFFFF)
    subtitle       = Color3.fromRGB(168, 180, 204),    -- High-Contrast Slate Grey Subtitle (#A8B4CC)
    outline        = Color3.fromRGB(8, 9, 13),         -- Crisp Dark Shadow Outline
    tabInactive    = Color3.fromRGB(168, 180, 204),    -- High-Legibility Inactive Tab (Bright Slate White)
    tabActive      = Color3.fromRGB(255, 255, 255),    -- Pure White Active Tab
    tabActiveBg    = Color3.fromRGB(38, 44, 60),       -- Active Tab Elevated Neumorphic Pill
    tabActiveBar   = Color3.fromRGB(56, 139, 253),     -- Apple Vivid Blue Tab Accent

    -- Section Container Cards (Grouped Neumorphic Inset/Raised Cards)
    sectionTitle   = Color3.fromRGB(96, 172, 255),     -- Vivid Apple Blue Section Header
    cardBg         = Color3.fromRGB(30, 34, 46),       -- Neumorphic Raised Surface (#1E222E)
    cardBorder     = Color3.fromRGB(48, 54, 72),       -- Top-Left Specular Bevel
    cardShadow     = Color3.fromRGB(10, 11, 15),       -- Bottom-Right Soft Shadow
    rowDivider     = Color3.fromRGB(38, 43, 58),       -- Subtle Inner Row Separator
    rowHover       = Color3.fromRGB(36, 41, 56),       -- Smooth Row Hover Highlight

    -- Controls & Typography (Ultra Crisp 13px)
    text           = Color3.fromRGB(248, 250, 255),    -- Crisp Apple High-Contrast White (Zero Bloom)
    textMuted      = Color3.fromRGB(168, 176, 196),    -- Secondary Values & Descriptions
    controlBg      = Color3.fromRGB(34, 39, 52),       -- Buttons & Badges Raised Surface
    controlBorder  = Color3.fromRGB(52, 60, 80),       -- Specular Bevel Border
    controlShadow  = Color3.fromRGB(12, 14, 18),       -- Ambient Shadow

    -- Apple Switches & Sliders (Neumorphic Inset / Raised)
    toggleOn       = Color3.fromRGB(52, 199, 89),      -- Authentic Apple Green (#34C759)
    toggleOff      = Color3.fromRGB(18, 20, 26),       -- Sunken Dark Cavity Track
    toggleBorder   = Color3.fromRGB(36, 40, 52),       -- Sunken Rim
    knob           = Color3.fromRGB(255, 255, 255),    -- Pure White Solid Knob
    knobShadow     = Color3.fromRGB(8, 9, 12),         -- Drop Shadow for Knob
    sliderTrack    = Color3.fromRGB(16, 18, 24),       -- Inset Groove Track
    sliderFill     = Color3.fromRGB(56, 139, 253),     -- Apple Vivid Blue Fill
    accent         = Color3.fromRGB(56, 139, 253),     -- Apple Vivid Blue Accent
}

-- ============================================================
--   NOTIFICATIONS
-- ============================================================
function DrawingUI.Notify(options)
    options = options or {}
    local title = sanitizeText(tostring(options.Title or "RAVEN HUB"))
    local content = sanitizeText(tostring(options.Content or options.Description or options.Text or ""))
    print(string.format("[RAVEN HUB] %s: %s", title, content))
end

-- ============================================================
--   WINDOW CONSTRUCTOR
-- ============================================================
function DrawingUI:CreateWindow(config)
    config = config or {}
    local self = setmetatable({}, DrawingUI)

    self.title = sanitizeText(tostring(config.Title or config.Name or "RAVEN HUB"))
    self.subtitle = sanitizeText(tostring(config.Subtitle or config.SubTitle or "MacLib macOS Edition"))
    self.size = config.Size or Vector2.new(680, 480)
    self.toggleKey = config.Keybind or config.ToggleKey or Enum.KeyCode.RightShift

    local vpSize = Vector2.new(1920, 1080)
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam and cam.ViewportSize then
            vpSize = cam.ViewportSize
        end
    end)

    self.pos = Vector2.new(
        math.clamp((vpSize.X - self.size.X) / 2, 40, 1400),
        math.clamp((vpSize.Y - self.size.Y) / 2, 40, 900)
    )

    self.visible = true
    self.running = true
    self.theme = MAC_THEME
    self.tabs = {}
    self.activeTabIndex = 1
    self.headerHeight = 44
    self.sidebarWidth = 190

    self.drawings = {}

    -- Floating Ambient Neumorphic Cast Shadow (Layer 0)
    self.windowShadow = createRoundedCard(0)

    -- Main Window 12px Rounded Chassis with Specular Rim (Layer 1)
    self.windowCard = createRoundedCard(1)

    -- Left Sidebar Debossed Cavity Surface (Layer 2)
    self.drawings.sidebarBg = safeDrawing("Square")
    if self.drawings.sidebarBg then
        self.drawings.sidebarBg.Filled = true
        self.drawings.sidebarBg.Color = self.theme.bgSidebar
        self.drawings.sidebarBg.Thickness = 1
        self.drawings.sidebarBg.Visible = false
        pcall(function() self.drawings.sidebarBg.ZIndex = 2 end)
    end

    -- Carved Dual-Line Vertical Seam (Layer 2)
    self.drawings.sidebarLine = safeDrawing("Line")
    if self.drawings.sidebarLine then
        self.drawings.sidebarLine.Thickness = 1
        self.drawings.sidebarLine.Color = self.theme.divider
        self.drawings.sidebarLine.Visible = false
        pcall(function() self.drawings.sidebarLine.ZIndex = 2 end)
    end

    self.drawings.sidebarLineLight = safeDrawing("Line")
    if self.drawings.sidebarLineLight then
        self.drawings.sidebarLineLight.Thickness = 1
        self.drawings.sidebarLineLight.Color = self.theme.dividerLight
        self.drawings.sidebarLineLight.Visible = false
        pcall(function() self.drawings.sidebarLineLight.ZIndex = 2 end)
    end

    -- Carved Dual-Line Header Trench (Layer 10)
    self.drawings.headerLine = safeDrawing("Line")
    if self.drawings.headerLine then
        self.drawings.headerLine.Thickness = 1
        self.drawings.headerLine.Color = self.theme.divider
        self.drawings.headerLine.Visible = false
        pcall(function() self.drawings.headerLine.ZIndex = 10 end)
    end

    self.drawings.headerLineLight = safeDrawing("Line")
    if self.drawings.headerLineLight then
        self.drawings.headerLineLight.Thickness = 1
        self.drawings.headerLineLight.Color = self.theme.dividerLight
        self.drawings.headerLineLight.Visible = false
        pcall(function() self.drawings.headerLineLight.ZIndex = 10 end)
    end

    -- Traffic Lights Recessed Sockets (Neumorphic Inset Rings)
    self.drawings.socketRed = safeDrawing("Circle")
    if self.drawings.socketRed then
        self.drawings.socketRed.Filled = true
        self.drawings.socketRed.Color = self.theme.trafficSocket
        self.drawings.socketRed.Radius = 7.5
        self.drawings.socketRed.Visible = false
        pcall(function() self.drawings.socketRed.ZIndex = 9 end)
    end

    self.drawings.socketYellow = safeDrawing("Circle")
    if self.drawings.socketYellow then
        self.drawings.socketYellow.Filled = true
        self.drawings.socketYellow.Color = self.theme.trafficSocket
        self.drawings.socketYellow.Radius = 7.5
        self.drawings.socketYellow.Visible = false
        pcall(function() self.drawings.socketYellow.ZIndex = 9 end)
    end

    self.drawings.socketGreen = safeDrawing("Circle")
    if self.drawings.socketGreen then
        self.drawings.socketGreen.Filled = true
        self.drawings.socketGreen.Color = self.theme.trafficSocket
        self.drawings.socketGreen.Radius = 7.5
        self.drawings.socketGreen.Visible = false
        pcall(function() self.drawings.socketGreen.ZIndex = 9 end)
    end

    -- Traffic Lights: Red (Close/Destroy) (Layer 10)
    self.drawings.trafficRed = safeDrawing("Circle")
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Filled = true
        self.drawings.trafficRed.Color = self.theme.trafficRed
        self.drawings.trafficRed.Radius = 6.5
        self.drawings.trafficRed.Visible = false
        pcall(function() self.drawings.trafficRed.ZIndex = 10 end)
    end

    -- Traffic Lights: Yellow (Minimize/Hide)
    self.drawings.trafficYellow = safeDrawing("Circle")
    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Filled = true
        self.drawings.trafficYellow.Color = self.theme.trafficYellow
        self.drawings.trafficYellow.Radius = 6.5
        self.drawings.trafficYellow.Visible = false
        pcall(function() self.drawings.trafficYellow.ZIndex = 10 end)
    end

    -- Traffic Lights: Green (Expand/Active)
    self.drawings.trafficGreen = safeDrawing("Circle")
    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Filled = true
        self.drawings.trafficGreen.Color = self.theme.trafficGreen
        self.drawings.trafficGreen.Radius = 6.5
        self.drawings.trafficGreen.Visible = false
        pcall(function() self.drawings.trafficGreen.ZIndex = 10 end)
    end

    -- Header Title & Subtitle (Double-Strike Bold Vector Typography, Layer 10)
    self.drawings.title = createBoldText(10, true)
    if self.drawings.title then
        self.drawings.title.Size = 14
        self.drawings.title.Color = self.theme.title
        self.drawings.title.Text = self.title
        self.drawings.title.Visible = false
    end

    self.drawings.subtitle = createBoldText(10)
    if self.drawings.subtitle then
        self.drawings.subtitle.Size = 13
        self.drawings.subtitle.Color = self.theme.subtitle
        self.drawings.subtitle.Text = self.subtitle
        self.drawings.subtitle.Visible = false
    end

    -- Keybind Badge on Top-Right (Layer 10)
    self.keyBadgeCard = createRoundedCard(10)

    self.drawings.hint = createBoldText(11)
    if self.drawings.hint then
        self.drawings.hint.Size = 12
        self.drawings.hint.Color = self.theme.textMuted
        self.drawings.hint.Text = "[RShift] Toggle"
        self.drawings.hint.Center = true
        self.drawings.hint.Visible = false
    end

    -- Active Tab Rounded Pill Highlight
    self.activeTabPill = createRoundedCard(3)

    -- Active Tab Accent Left Line
    self.activeTabBar = safeDrawing("Square")
    if self.activeTabBar then
        self.activeTabBar.Filled = true
        self.activeTabBar.Color = self.theme.tabActiveBar
        self.activeTabBar.Thickness = 1
        self.activeTabBar.Visible = false
        pcall(function() self.activeTabBar.ZIndex = 4 end)
    end

    -- User Info Profile Card (Bottom of Sidebar)
    self.userCardPill = createRoundedCard(2)

    self.drawings.userDot = safeDrawing("Circle")
    if self.drawings.userDot then
        self.drawings.userDot.Filled = true
        self.drawings.userDot.Color = self.theme.toggleOn
        self.drawings.userDot.Radius = 4.5
        self.drawings.userDot.Visible = false
        pcall(function() self.drawings.userDot.ZIndex = 4 end)
    end

    self.drawings.userName = createBoldText(4, true)
    if self.drawings.userName then
        self.drawings.userName.Size = 13
        self.drawings.userName.Color = self.theme.text
        local lp = Players.LocalPlayer
        self.drawings.userName.Text = lp and (lp.DisplayName or lp.Name) or "User"
        self.drawings.userName.Visible = false
    end

    self.drawings.userStatus = createBoldText(4)
    if self.drawings.userStatus then
        self.drawings.userStatus.Size = 11
        self.drawings.userStatus.Color = self.theme.textMuted
        self.drawings.userStatus.Text = "100% Drawing Safe"
        self.drawings.userStatus.Visible = false
    end

    self.dragging = false
    self.dragStart = Vector2.zero
    self.posStart = Vector2.zero
    self.connections = {}
    self.activeSlider = nil
    self.activeKeybindListener = nil
    self._unloadCallbacks = {}

    self:InitInputHandlers()

    return self
end

function DrawingUI:OnUnload(callback)
    if type(callback) == "function" then
        table.insert(self._unloadCallbacks, callback)
    end
end

function DrawingUI:InsertConfigSection()
    -- MacLib compatibility stub
end

-- ============================================================
--   TAB & SECTION ARCHITECTURE (Sidebar Navigation)
-- ============================================================
-- ============================================================
--   PROCEDURAL VECTOR ICON ENGINE (100% Drawing API, Zero Emojis)
--   Authentic Apple macOS SF Symbols rendered in Direct3D Primitives
-- ============================================================
local function resolveIconType(name, icon)
    local str = tostring(icon or ""):lower()
    local nameStr = tostring(name or ""):lower()

    if str:find("combat") or str:find("shoot") or str:find("aim") or nameStr:find("shoot") or nameStr:find("combat") then
        return "combat"
    elseif str:find("move") or str:find("def") or str:find("shield") or nameStr:find("def") or nameStr:find("move") then
        return "defense"
    elseif str:find("esp") or str:find("vis") or str:find("eye") or nameStr:find("vis") or nameStr:find("esp") then
        return "visuals"
    elseif str:find("tool") or str:find("safe") or str:find("lock") or nameStr:find("safe") then
        return "safety"
    elseif str:find("set") or str:find("pref") or str:find("gear") or nameStr:find("set") then
        return "settings"
    elseif str:find("over") or str:find("home") or str:find("dash") or nameStr:find("over") or nameStr:find("home") then
        return "overview"
    end
    return "overview"
end

local function createVectorIcon(iconType, baseZIndex)
    baseZIndex = baseZIndex or 5
    local icon = {
        type = iconType,
        drawings = {},
    }

    local function line()
        local l = safeDrawing("Line")
        if l then
            l.Thickness = 1.2
            l.Visible = false
            pcall(function() l.ZIndex = baseZIndex end)
            table.insert(icon.drawings, l)
        end
        return l
    end

    local function circle(filled, r)
        local c = safeDrawing("Circle")
        if c then
            c.Filled = (filled == true)
            c.Radius = r or 3
            c.Thickness = 1.2
            c.Visible = false
            pcall(function() c.ZIndex = baseZIndex end)
            table.insert(icon.drawings, c)
        end
        return c
    end

    local function square(filled)
        local s = safeDrawing("Square")
        if s then
            s.Filled = (filled == true)
            s.Thickness = 1.2
            s.Visible = false
            pcall(function() s.ZIndex = baseZIndex end)
            table.insert(icon.drawings, s)
        end
        return s
    end

    if iconType == "combat" then
        -- Tactical Precision Reticle (Outer Ring + Center Dot + 4 Crosshair Ticks)
        icon.ring = circle(false, 5)
        icon.dot = circle(true, 1.5)
        icon.t = line()
        icon.b = line()
        icon.l = line()
        icon.r = line()

    elseif iconType == "defense" then
        -- Tactical Armor Shield (Top + 2 Sides + 2 Diagonal Bevels + Core Dot)
        icon.top = line()
        icon.left = line()
        icon.right = line()
        icon.diagL = line()
        icon.diagR = line()
        icon.dot = circle(true, 1.5)

    elseif iconType == "visuals" then
        -- Sensor Aperture Eye (Iris Ring + Pupil Dot + 4 Eye Arch Rays)
        icon.iris = circle(false, 4)
        icon.pupil = circle(true, 2)
        icon.archT1 = line()
        icon.archT2 = line()
        icon.archB1 = line()
        icon.archB2 = line()

    elseif iconType == "safety" then
        -- Security Padlock (U-Shackle + Solid Rect Body + Keyhole Dot)
        icon.body = square(false)
        icon.shackle = circle(false, 3.5)
        icon.keyhole = circle(true, 1.5)

    elseif iconType == "settings" then
        -- Control Center Sliders (2 Horizontal Rails + 2 Tactile Slider Knobs)
        icon.rail1 = line()
        icon.knob1 = circle(true, 2)
        icon.rail2 = line()
        icon.knob2 = circle(true, 2)

    else -- "overview" (Launchpad 2x2 App Grid)
        icon.b1 = square(true)
        icon.b2 = square(true)
        icon.b3 = square(true)
        icon.b4 = square(true)
    end

    function icon:Update(center, color, visible)
        if not visible then
            for _, d in ipairs(self.drawings) do
                setObjVisible(d, false)
            end
            return
        end

        local cx = center.X
        local cy = center.Y

        if self.type == "combat" then
            if self.ring then self.ring.Position = center; self.ring.Color = color; self.ring.Visible = true end
            if self.dot then self.dot.Position = center; self.dot.Color = color; self.dot.Visible = true end
            if self.t then self.t.From = Vector2.new(cx, cy - 7); self.t.To = Vector2.new(cx, cy - 4); self.t.Color = color; self.t.Visible = true end
            if self.b then self.b.From = Vector2.new(cx, cy + 4); self.b.To = Vector2.new(cx, cy + 7); self.b.Color = color; self.b.Visible = true end
            if self.l then self.l.From = Vector2.new(cx - 7, cy); self.l.To = Vector2.new(cx - 4, cy); self.l.Color = color; self.l.Visible = true end
            if self.r then self.r.From = Vector2.new(cx + 4, cy); self.r.To = Vector2.new(cx + 7, cy); self.r.Color = color; self.r.Visible = true end

        elseif self.type == "defense" then
            if self.top then self.top.From = Vector2.new(cx - 5, cy - 5); self.top.To = Vector2.new(cx + 5, cy - 5); self.top.Color = color; self.top.Visible = true end
            if self.left then self.left.From = Vector2.new(cx - 5, cy - 5); self.left.To = Vector2.new(cx - 5, cy); self.left.Color = color; self.left.Visible = true end
            if self.right then self.right.From = Vector2.new(cx + 5, cy - 5); self.right.To = Vector2.new(cx + 5, cy); self.right.Color = color; self.right.Visible = true end
            if self.diagL then self.diagL.From = Vector2.new(cx - 5, cy); self.diagL.To = Vector2.new(cx, cy + 6); self.diagL.Color = color; self.diagL.Visible = true end
            if self.diagR then self.diagR.From = Vector2.new(cx + 5, cy); self.diagR.To = Vector2.new(cx, cy + 6); self.diagR.Color = color; self.diagR.Visible = true end
            if self.dot then self.dot.Position = Vector2.new(cx, cy - 1); self.dot.Color = color; self.dot.Visible = true end

        elseif self.type == "visuals" then
            if self.iris then self.iris.Position = center; self.iris.Color = color; self.iris.Visible = true end
            if self.pupil then self.pupil.Position = center; self.pupil.Color = color; self.pupil.Visible = true end
            if self.archT1 then self.archT1.From = Vector2.new(cx - 7, cy); self.archT1.To = Vector2.new(cx, cy - 4); self.archT1.Color = color; self.archT1.Visible = true end
            if self.archT2 then self.archT2.From = Vector2.new(cx, cy - 4); self.archT2.To = Vector2.new(cx + 7, cy); self.archT2.Color = color; self.archT2.Visible = true end
            if self.archB1 then self.archB1.From = Vector2.new(cx - 7, cy); self.archB1.To = Vector2.new(cx, cy + 4); self.archB1.Color = color; self.archB1.Visible = true end
            if self.archB2 then self.archB2.From = Vector2.new(cx, cy + 4); self.archB2.To = Vector2.new(cx + 7, cy); self.archB2.Color = color; self.archB2.Visible = true end

        elseif self.type == "safety" then
            if self.body then self.body.Position = Vector2.new(cx - 5, cy - 1); self.body.Size = Vector2.new(10, 7); self.body.Color = color; self.body.Visible = true end
            if self.shackle then self.shackle.Position = Vector2.new(cx, cy - 2); self.shackle.Color = color; self.shackle.Visible = true end
            if self.keyhole then self.keyhole.Position = Vector2.new(cx, cy + 2.5); self.keyhole.Color = color; self.keyhole.Visible = true end

        elseif self.type == "settings" then
            if self.rail1 then self.rail1.From = Vector2.new(cx - 6, cy - 3); self.rail1.To = Vector2.new(cx + 6, cy - 3); self.rail1.Color = color; self.rail1.Visible = true end
            if self.knob1 then self.knob1.Position = Vector2.new(cx - 2, cy - 3); self.knob1.Color = color; self.knob1.Visible = true end
            if self.rail2 then self.rail2.From = Vector2.new(cx - 6, cy + 3); self.rail2.To = Vector2.new(cx + 6, cy + 3); self.rail2.Color = color; self.rail2.Visible = true end
            if self.knob2 then self.knob2.Position = Vector2.new(cx + 2, cy + 3); self.knob2.Color = color; self.knob2.Visible = true end

        elseif self.type == "overview" then
            local sz = Vector2.new(4, 4)
            if self.b1 then self.b1.Position = Vector2.new(cx - 5, cy - 5); self.b1.Size = sz; self.b1.Color = color; self.b1.Visible = true end
            if self.b2 then self.b2.Position = Vector2.new(cx + 1, cy - 5); self.b2.Size = sz; self.b2.Color = color; self.b2.Visible = true end
            if self.b3 then self.b3.Position = Vector2.new(cx - 5, cy + 1); self.b3.Size = sz; self.b3.Color = color; self.b3.Visible = true end
            if self.b4 then self.b4.Position = Vector2.new(cx + 1, cy + 1); self.b4.Size = sz; self.b4.Color = color; self.b4.Visible = true end
        end
    end

    function icon:Remove()
        for _, d in ipairs(self.drawings) do
            removeObj(d)
        end
    end

    return icon
end

local SectionMethods = {}
SectionMethods.__index = SectionMethods

local TabMethods = {}
TabMethods.__index = TabMethods

function TabMethods:_ensureSection()
    if self._currentSection then
        return self._currentSection
    end
    return self:CreateSection("General")
end

function TabMethods:CreateToggle(cfg) return self:_ensureSection():CreateToggle(cfg) end
function TabMethods:CreateSlider(cfg) return self:_ensureSection():CreateSlider(cfg) end
function TabMethods:CreateButton(cfg) return self:_ensureSection():CreateButton(cfg) end
function TabMethods:CreateLabel(cfg) return self:_ensureSection():CreateLabel(cfg) end
function TabMethods:CreateStatus(cfg) return self:_ensureSection():CreateStatus(cfg) end
function TabMethods:CreateParagraph(cfg) return self:_ensureSection():CreateParagraph(cfg) end
function TabMethods:CreateDivider() return self:_ensureSection():CreateDivider() end
function TabMethods:CreateDropdown(cfg) return self:_ensureSection():CreateDropdown(cfg) end
function TabMethods:CreateKeybind(cfg) return self:_ensureSection():CreateKeybind(cfg) end
function TabMethods:CreateInput(cfg) return self:_ensureSection():CreateInput(cfg) end
function TabMethods:InsertConfigSection() end

function TabMethods:Select()
    for idx, t in ipairs(self.window.tabs) do
        if t == self then
            self.window.activeTabIndex = idx
            break
        end
    end
end

function DrawingUI:CreateTab(name, icon)
    local existing = self:GetTab(name)
    if existing then
        return existing
    end

    local resolvedIcon = resolveIconType(name, icon)
    local tab = setmetatable({
        name = sanitizeText(tostring(name or "Tab")),
        icon = icon,
        iconType = resolvedIcon,
        iconObject = createVectorIcon(resolvedIcon, 5),
        sections = {},
        window = self,
        scrollOffset = 0,
        maxScroll = 0,
        _currentSection = nil,
        tabText = createBoldText(4, true),
    }, TabMethods)

    if tab.tabText then
        tab.tabText.Size = 13
        tab.tabText.Color = self.theme.tabInactive
        tab.tabText.Text = tab.name
        tab.tabText.Visible = false
    end

    table.insert(self.tabs, tab)
    return tab
end

function DrawingUI:GetTab(name)
    local target = sanitizeText(tostring(name or "")):lower()
    for _, tab in ipairs(self.tabs) do
        if tab.name and tab.name:lower() == target then
            return tab
        end
    end
    return nil
end

function DrawingUI:SortTabs(orderedNames)
    if type(orderedNames) ~= "table" or #orderedNames == 0 then return end
    local orderMap = {}
    for idx, name in ipairs(orderedNames) do
        orderMap[tostring(name):lower()] = idx
    end

    table.sort(self.tabs, function(a, b)
        local rankA = orderMap[a.name:lower()] or 999
        local rankB = orderMap[b.name:lower()] or 999
        if rankA == rankB then
            return a.name < b.name
        end
        return rankA < rankB
    end)
end

function DrawingUI:CreatePlaceholderTab(name, icon, message)
    local tab = self:CreateTab(name, icon)
    local sec = tab:CreateSection("Information")
    sec:CreateParagraph({
        Title = name,
        Content = message or "This section is currently being updated for zero-injection."
    })
    return tab
end

function TabMethods:CreateSection(secName)
    local sec = setmetatable({
        name = sanitizeText(tostring(secName or "Section")),
        items = {},
        tab = self,
        window = self.window,
        accentBar = safeDrawing("Square"),
        titleDrawing = createBoldText(5, true),
        card = createRoundedCard(3),
    }, SectionMethods)

    if sec.accentBar then
        sec.accentBar.Filled = true
        sec.accentBar.Thickness = 1
        sec.accentBar.Color = self.window.theme.sectionTitle
        sec.accentBar.Visible = false
        pcall(function() sec.accentBar.ZIndex = 5 end)
    end

    if sec.titleDrawing then
        sec.titleDrawing.Size = 13
        sec.titleDrawing.Color = self.window.theme.sectionTitle
        sec.titleDrawing.Text = string.upper(sec.name)
        sec.titleDrawing.Visible = false
    end

    self._currentSection = sec
    table.insert(self.sections, sec)
    return sec
end

-- ============================================================
--   SECTION CONTROLS (1:1 MacLib High-Contrast Controls)
-- ============================================================
function SectionMethods:CreateToggle(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local item = {
        type = "toggle",
        name = sanitizeText(tostring(cfg.Name or "Toggle")),
        value = cfg.CurrentValue == true or cfg.Default == true,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        -- Layering: Backgrounds created first, then foreground text and switch
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        label = createBoldText(6, true),
        pill = createPillSwitch(5),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    function item:Set(val)
        item.value = (val == true)
        if item.flag then
            DrawingUI.Flags[item.flag] = item.value
        end
        pcall(item.callback, item.value)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.value
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateSlider(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local minVal = (cfg.Range and tonumber(cfg.Range[1])) or tonumber(cfg.Min) or 0
    local maxVal = (cfg.Range and tonumber(cfg.Range[2])) or tonumber(cfg.Max) or 100
    local currentVal = tonumber(cfg.CurrentValue or cfg.Default or minVal) or minVal

    local item = {
        type = "slider",
        name = sanitizeText(tostring(cfg.Name or "Slider")),
        min = minVal,
        max = maxVal,
        increment = tonumber(cfg.Increment) or 1,
        suffix = sanitizeText(tostring(cfg.Suffix or "")),
        value = math.clamp(currentVal, minVal, maxVal),
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        -- Layering: Backgrounds first
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        valBadgeBg = safeDrawing("Square"),
        valBadgeBorder = safeDrawing("Square"),
        track = safeDrawing("Square"),
        fill = safeDrawing("Square"),
        knob = safeDrawing("Circle"),
        label = createBoldText(6, true),
        valText = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.valBadgeBg then
        item.valBadgeBg.Filled = true
        item.valBadgeBg.Color = tab.window.theme.controlBg
        item.valBadgeBg.Thickness = 1
        item.valBadgeBg.Visible = false
        pcall(function() item.valBadgeBg.ZIndex = 5 end)
    end

    if item.valBadgeBorder then
        item.valBadgeBorder.Filled = false
        item.valBadgeBorder.Color = tab.window.theme.controlBorder
        item.valBadgeBorder.Thickness = 1
        item.valBadgeBorder.Visible = false
        pcall(function() item.valBadgeBorder.ZIndex = 5 end)
    end

    if item.track then
        item.track.Thickness = 1
        item.track.Filled = true
        item.track.Color = tab.window.theme.sliderTrack
        item.track.Visible = false
        pcall(function() item.track.ZIndex = 5 end)
    end

    if item.fill then
        item.fill.Thickness = 1
        item.fill.Filled = true
        item.fill.Color = tab.window.theme.sliderFill
        item.fill.Visible = false
        pcall(function() item.fill.ZIndex = 5 end)
    end

    if item.knob then
        item.knob.Filled = true
        item.knob.Color = tab.window.theme.knob
        item.knob.Radius = 8
        item.knob.Visible = false
        pcall(function() item.knob.ZIndex = 6 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Size = 13
        item.valText.Color = tab.window.theme.accent
        item.valText.Center = true
        item.valText.Visible = false
    end

    function item:Set(val)
        local num = tonumber(val) or item.min
        item.value = math.clamp(num, item.min, item.max)
        if item.flag then
            DrawingUI.Flags[item.flag] = item.value
        end
        pcall(item.callback, item.value)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.value
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateButton(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local item = {
        type = "button",
        name = sanitizeText(tostring(cfg.Name or "Button")),
        callback = cfg.Callback or function() end,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        buttonCard = createRoundedCard(5),
        label = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Center = true
        item.label.Visible = false
    end

    function item:Click()
        pcall(item.callback)
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateLabel(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local text = sanitizeText(tostring(type(cfg) == "table" and (cfg.Text or cfg.Name) or cfg))
    local item = {
        type = "label",
        text = text,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        label = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.textMuted
        item.label.Text = item.text
        item.label.Visible = false
    end

    function item:Set(newText)
        item.text = sanitizeText(tostring(type(newText) == "table" and (newText.Text or newText.Name) or newText or ""))
        if item.label then
            item.label.Text = item.text
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateStatus(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local title = sanitizeText(tostring(cfg.Title or cfg.Name or "Status"))
    local desc = sanitizeText(tostring(cfg.Description or cfg.Content or cfg.Value or "Ready"))

    local item = {
        type = "paragraph",
        title = title,
        content = desc,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        titleText = createBoldText(6, true),
        descText = createBoldText(6),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.titleText then
        item.titleText.Size = 13
        item.titleText.Color = tab.window.theme.sectionTitle
        item.titleText.Text = item.title
        item.titleText.Visible = false
    end

    if item.descText then
        item.descText.Size = 13
        item.descText.Color = tab.window.theme.text
        item.descText.Text = item.content
        item.descText.Visible = false
    end

    function item:Set(newDesc)
        item.content = sanitizeText(tostring(newDesc or ""))
        if item.descText then
            item.descText.Text = item.content
        end
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateParagraph(cfg)
    return self:CreateStatus(cfg)
end

function SectionMethods:CreateDivider()
    local item = {
        type = "divider",
        line = safeDrawing("Line"),
    }
    if item.line then
        item.line.Thickness = 1
        item.line.Color = self.tab.window.theme.rowDivider
        item.line.Visible = false
        pcall(function() item.line.ZIndex = 4 end)
    end
    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateDropdown(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local rawOptions = cfg.Options or {"Option 1"}
    local options = {}
    for _, opt in ipairs(rawOptions) do
        table.insert(options, tostring(opt))
    end
    if #options == 0 then table.insert(options, "Default") end

    local defaultVal = cfg.CurrentOption or cfg.Default or options[1] or ""
    if type(defaultVal) == "table" then
        defaultVal = defaultVal[1] or options[1] or ""
    end
    defaultVal = tostring(defaultVal)

    local item = {
        type = "dropdown",
        name = sanitizeText(tostring(cfg.Name or "Dropdown")),
        options = options,
        current = defaultVal,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        badgeBg = safeDrawing("Square"),
        badgeBorder = safeDrawing("Square"),
        label = createBoldText(6, true),
        valText = createBoldText(6, true),
        arrow = createBoldText(6),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.badgeBg then
        item.badgeBg.Filled = true
        item.badgeBg.Color = tab.window.theme.controlBg
        item.badgeBg.Thickness = 1
        item.badgeBg.Visible = false
        pcall(function() item.badgeBg.ZIndex = 5 end)
    end

    if item.badgeBorder then
        item.badgeBorder.Filled = false
        item.badgeBorder.Color = tab.window.theme.controlBorder
        item.badgeBorder.Thickness = 1
        item.badgeBorder.Visible = false
        pcall(function() item.badgeBorder.ZIndex = 5 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Size = 13
        item.valText.Color = tab.window.theme.accent
        item.valText.Text = item.current
        item.valText.Visible = false
    end

    if item.arrow then
        item.arrow.Size = 13
        item.arrow.Color = tab.window.theme.textMuted
        item.arrow.Text = "v"
        item.arrow.Visible = false
    end

    function item:Set(val)
        if type(val) == "table" then val = val[1] end
        item.current = tostring(val or "")
        if item.valText then
            item.valText.Text = item.current
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.current
        end
        pcall(item.callback, item.current)
    end

    function item:CycleNext()
        local nextIdx = 1
        for i, opt in ipairs(item.options) do
            if tostring(opt) == item.current then
                nextIdx = (i % #item.options) + 1
                break
            end
        end
        local nextVal = item.options[nextIdx] or item.current
        item:Set(nextVal)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.current
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateKeybind(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local defaultKey = cfg.CurrentKeybind or cfg.Default or "None"
    if typeof(defaultKey) == "EnumItem" then
        defaultKey = defaultKey.Name
    end

    local item = {
        type = "keybind",
        name = sanitizeText(tostring(cfg.Name or "Keybind")),
        key = tostring(defaultKey),
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        listening = false,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        badgeBg = safeDrawing("Square"),
        badgeBorder = safeDrawing("Square"),
        label = createBoldText(6, true),
        keyText = createBoldText(6, true),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.badgeBg then
        item.badgeBg.Filled = true
        item.badgeBg.Color = tab.window.theme.controlBg
        item.badgeBg.Thickness = 1
        item.badgeBg.Visible = false
        pcall(function() item.badgeBg.ZIndex = 5 end)
    end

    if item.badgeBorder then
        item.badgeBorder.Filled = false
        item.badgeBorder.Color = tab.window.theme.controlBorder
        item.badgeBorder.Thickness = 1
        item.badgeBorder.Visible = false
        pcall(function() item.badgeBorder.ZIndex = 5 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.keyText then
        item.keyText.Size = 13
        item.keyText.Color = tab.window.theme.text
        item.keyText.Center = true
        item.keyText.Text = string.format("[%s]", item.key)
        item.keyText.Visible = false
    end

    function item:Set(newKey)
        if typeof(newKey) == "EnumItem" then
            newKey = newKey.Name
        end
        item.key = tostring(newKey or "None")
        item.listening = false
        if item.keyText then
            item.keyText.Text = string.format("[%s]", item.key)
            item.keyText.Color = tab.window.theme.text
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.key
        end
        pcall(item.callback, item.key)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.key
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateInput(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local item = {
        type = "input",
        name = sanitizeText(tostring(cfg.Name or "Input")),
        text = sanitizeText(tostring(cfg.CurrentValue or cfg.Default or "")),
        placeholder = sanitizeText(tostring(cfg.PlaceholderText or "Type here...")),
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        hoverBg = safeDrawing("Square"),
        innerDivider = safeDrawing("Line"),
        badgeBg = safeDrawing("Square"),
        badgeBorder = safeDrawing("Square"),
        label = createBoldText(6, true),
        valText = createBoldText(6),
    }

    if item.hoverBg then
        item.hoverBg.Filled = true
        item.hoverBg.Thickness = 1
        item.hoverBg.Visible = false
        pcall(function() item.hoverBg.ZIndex = 4 end)
    end

    if item.innerDivider then
        item.innerDivider.Thickness = 1
        item.innerDivider.Visible = false
        pcall(function() item.innerDivider.ZIndex = 4 end)
    end

    if item.badgeBg then
        item.badgeBg.Filled = true
        item.badgeBg.Color = tab.window.theme.controlBg
        item.badgeBg.Thickness = 1
        item.badgeBg.Visible = false
        pcall(function() item.badgeBg.ZIndex = 5 end)
    end

    if item.badgeBorder then
        item.badgeBorder.Filled = false
        item.badgeBorder.Color = tab.window.theme.controlBorder
        item.badgeBorder.Thickness = 1
        item.badgeBorder.Visible = false
        pcall(function() item.badgeBorder.ZIndex = 5 end)
    end

    if item.label then
        item.label.Size = 13
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Size = 13
        item.valText.Color = tab.window.theme.text
        item.valText.Text = #item.text > 0 and item.text or item.placeholder
        item.valText.Visible = false
    end

    function item:Set(val)
        item.text = sanitizeText(tostring(val or ""))
        if item.valText then
            item.valText.Text = #item.text > 0 and item.text or item.placeholder
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.text
        end
        pcall(item.callback, item.text)
    end

    table.insert(self.items, item)
    return item
end

-- ============================================================
--   INPUT & INTERACTION SYSTEM
-- ============================================================
function DrawingUI:InitInputHandlers()
    local conn1 = UserInputService.InputBegan:Connect(function(input, processed)
        if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == self.toggleKey then
            self:Toggle()
            return
        end

        if not self.visible then return end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mousePos = UserInputService:GetMouseLocation()

            -- 1. Check Traffic Lights (Radius 9 hitbox)
            local trafficRedPos = Vector2.new(self.pos.X + 18, self.pos.Y + 22)
            if pointInCircle(mousePos, trafficRedPos, 9) then
                self:Destroy()
                return
            end

            local trafficYellowPos = Vector2.new(self.pos.X + 36, self.pos.Y + 22)
            if pointInCircle(mousePos, trafficYellowPos, 9) then
                self:Toggle()
                return
            end

            local trafficGreenPos = Vector2.new(self.pos.X + 54, self.pos.Y + 22)
            if pointInCircle(mousePos, trafficGreenPos, 9) then
                return
            end

            -- 2. Header Dragging
            local headerBoxPos = self.pos
            local headerBoxSize = Vector2.new(self.size.X, self.headerHeight)
            if pointInBox(mousePos, headerBoxPos, headerBoxSize) then
                self.dragging = true
                self.dragStart = mousePos
                self.posStart = self.pos
                return
            end

            -- 3. Sidebar Tab Selection
            for idx, tab in ipairs(self.tabs) do
                if tab.hitBox and pointInBox(mousePos, tab.hitBox.pos, tab.hitBox.size) then
                    self.activeTabIndex = idx
                    return
                end
            end

            -- 4. Content Item Interactions
            local curTab = self.tabs[self.activeTabIndex]
            if curTab then
                for _, sec in ipairs(curTab.sections) do
                    for _, item in ipairs(sec.items) do
                        if item.hitBox and pointInBox(mousePos, item.hitBox.pos, item.hitBox.size) then
                            if item.type == "toggle" then
                                item:Set(not item.value)
                                return
                            elseif item.type == "button" then
                                item:Click()
                                return
                            elseif item.type == "dropdown" then
                                item:CycleNext()
                                return
                            elseif item.type == "slider" then
                                self.activeSlider = item
                                if item.trackPos and item.trackWidth then
                                    local rel = math.clamp((mousePos.X - item.trackPos.X) / item.trackWidth, 0, 1)
                                    local rawVal = item.min + (item.max - item.min) * rel
                                    local steps = math.round((rawVal - item.min) / item.increment)
                                    local steppedVal = item.min + steps * item.increment
                                    item:Set(steppedVal)
                                end
                                return
                            elseif item.type == "keybind" then
                                item.listening = true
                                if item.keyText then
                                    item.keyText.Text = "[...]"
                                    item.keyText.Color = self.theme.accent
                                end
                                self.activeKeybindListener = item
                                return
                            end
                        end
                    end
                end
            end
        end

        -- Keybind Rebinding
        if self.activeKeybindListener and input.UserInputType == Enum.UserInputType.Keyboard then
            local listener = self.activeKeybindListener
            self.activeKeybindListener = nil
            if input.KeyCode ~= Enum.KeyCode.Escape then
                listener:Set(input.KeyCode.Name)
            else
                listener:Set(listener.key)
            end
        end
    end)

    local conn2 = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self.dragging = false
            self.activeSlider = nil
        end
    end)

    local conn3 = UserInputService.InputChanged:Connect(function(input)
        if not self.visible then return end

        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local mousePos = UserInputService:GetMouseLocation()
            if self.dragging then
                self.pos = self.posStart + (mousePos - self.dragStart)
            elseif self.activeSlider then
                local s = self.activeSlider
                if s.trackPos and s.trackWidth then
                    local rel = math.clamp((mousePos.X - s.trackPos.X) / s.trackWidth, 0, 1)
                    local rawVal = s.min + (s.max - s.min) * rel
                    local steps = math.round((rawVal - s.min) / s.increment)
                    local steppedVal = s.min + steps * s.increment
                    s:Set(steppedVal)
                end
            end
        elseif input.UserInputType == Enum.UserInputType.MouseWheel then
            local curTab = self.tabs[self.activeTabIndex]
            if curTab and curTab.maxScroll > 0 then
                curTab.scrollOffset = math.clamp(curTab.scrollOffset - (input.Position.Z * 32), 0, curTab.maxScroll)
            end
        end
    end)

    local conn4 = RunService.RenderStepped:Connect(function()
        if self.running then
            self:Render()
        end
    end)

    table.insert(self.connections, conn1)
    table.insert(self.connections, conn2)
    table.insert(self.connections, conn3)
    table.insert(self.connections, conn4)
end

function DrawingUI:Toggle()
    self.visible = not self.visible
    if not self.visible then
        if self.windowCard then self.windowCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        if self.keyBadgeCard then self.keyBadgeCard:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end

        for _, d in pairs(self.drawings) do
            setObjVisible(d, false)
        end
        if self.activeTabPill then self.activeTabPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
        setObjVisible(self.activeTabBar, false)
        if self.userCardPill then self.userCardPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end

        for _, tab in ipairs(self.tabs) do
            setObjVisible(tab.tabText, false)
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.titleDrawing, false)
                if sec.card then sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false) end
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end
end

-- ============================================================
--   MAIN RENDER PIPELINE (1:1 MacLib Aesthetic & Proportions)
-- ============================================================
function DrawingUI:Render()
    if not self.visible then return end

    local p = self.pos
    local sz = self.size
    local sideW = self.sidebarWidth
    local headH = self.headerHeight

    -- 0. Ambient Floating Neumorphic Drop Shadow
    if self.windowShadow then
        self.windowShadow:Update(p + Vector2.new(4, 6), sz, 14, self.theme.neuDropShadow, nil, true)
    end

    -- 1. Main Window 12px Rounded Chassis with Raised Specular Rim
    if self.windowCard then
        self.windowCard:Update(p, sz, 12, self.theme.bg, self.theme.border, true, "raised")
    end

    -- 2. Left Sidebar Debossed Cavity Surface & Dual-Line Carved Trench
    if self.drawings.sidebarBg then
        self.drawings.sidebarBg.Position = Vector2.new(p.X, p.Y + headH)
        self.drawings.sidebarBg.Size = Vector2.new(sideW, sz.Y - headH - 10)
        self.drawings.sidebarBg.Visible = true
    end

    if self.drawings.sidebarLine then
        self.drawings.sidebarLine.From = Vector2.new(p.X + sideW, p.Y + headH)
        self.drawings.sidebarLine.To = Vector2.new(p.X + sideW, p.Y + sz.Y - 2)
        self.drawings.sidebarLine.Visible = true
    end

    if self.drawings.sidebarLineLight then
        self.drawings.sidebarLineLight.From = Vector2.new(p.X + sideW + 1, p.Y + headH)
        self.drawings.sidebarLineLight.To = Vector2.new(p.X + sideW + 1, p.Y + sz.Y - 2)
        self.drawings.sidebarLineLight.Visible = true
    end

    -- 3. Header Divider (Carved Trench)
    if self.drawings.headerLine then
        self.drawings.headerLine.From = Vector2.new(p.X, p.Y + headH)
        self.drawings.headerLine.To = Vector2.new(p.X + sz.X, p.Y + headH)
        self.drawings.headerLine.Visible = true
    end

    if self.drawings.headerLineLight then
        self.drawings.headerLineLight.From = Vector2.new(p.X, p.Y + headH + 1)
        self.drawings.headerLineLight.To = Vector2.new(p.X + sz.X, p.Y + headH + 1)
        self.drawings.headerLineLight.Visible = true
    end

    -- 4. Traffic Lights with Recessed Sockets
    if self.drawings.socketRed then
        self.drawings.socketRed.Position = Vector2.new(p.X + 18, p.Y + 22)
        self.drawings.socketRed.Visible = true
    end
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Position = Vector2.new(p.X + 18, p.Y + 22)
        self.drawings.trafficRed.Visible = true
    end

    if self.drawings.socketYellow then
        self.drawings.socketYellow.Position = Vector2.new(p.X + 36, p.Y + 22)
        self.drawings.socketYellow.Visible = true
    end
    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Position = Vector2.new(p.X + 36, p.Y + 22)
        self.drawings.trafficYellow.Visible = true
    end

    if self.drawings.socketGreen then
        self.drawings.socketGreen.Position = Vector2.new(p.X + 54, p.Y + 22)
        self.drawings.socketGreen.Visible = true
    end
    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Position = Vector2.new(p.X + 54, p.Y + 22)
        self.drawings.trafficGreen.Visible = true
    end

    -- 5. Title & Subtitle (Crisp Bold Typography)
    if self.drawings.title then
        self.drawings.title.Position = Vector2.new(p.X + 78, p.Y + 14)
        self.drawings.title.Visible = true
    end

    if self.drawings.subtitle then
        self.drawings.subtitle.Position = Vector2.new(p.X + 175, p.Y + 15)
        self.drawings.subtitle.Visible = true
    end

    -- 6. Top-Right Key Badge (Rounded Pill)
    local badgeW = 112
    local badgeH = 26
    local badgeX = p.X + sz.X - badgeW - 14
    local badgeY = p.Y + 9

    if self.keyBadgeCard then
        self.keyBadgeCard:Update(Vector2.new(badgeX, badgeY), Vector2.new(badgeW, badgeH), 6, self.theme.controlBg, self.theme.controlBorder, true, "raised")
    end

    if self.drawings.hint then
        self.drawings.hint.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 5)
        self.drawings.hint.Visible = true
    end

    -- 7. Sidebar Footer (Rounded User Profile Card)
    local cardH = 44
    local cardY = p.Y + sz.Y - cardH - 12
    local cardX = p.X + 8
    local cardW = sideW - 16

    if self.userCardPill then
        self.userCardPill:Update(Vector2.new(cardX, cardY), Vector2.new(cardW, cardH), 8, self.theme.cardBg, self.theme.cardBorder, true, "raised")
    end

    if self.drawings.userDot then
        self.drawings.userDot.Position = Vector2.new(cardX + 14, cardY + 22)
        self.drawings.userDot.Visible = true
    end

    if self.drawings.userName then
        self.drawings.userName.Position = Vector2.new(cardX + 26, cardY + 7)
        self.drawings.userName.Visible = true
    end

    if self.drawings.userStatus then
        self.drawings.userStatus.Position = Vector2.new(cardX + 26, cardY + 24)
        self.drawings.userStatus.Visible = true
    end

    -- 8. Render Tabs in Left Sidebar
    local tabStartY = p.Y + headH + 12
    local tabBtnH = 38
    local tabBtnW = sideW - 16
    local tabX = p.X + 8

    local curTab = self.tabs[self.activeTabIndex]

    for idx, tab in ipairs(self.tabs) do
        local isActive = (idx == self.activeTabIndex)
        local btnY = tabStartY + (idx - 1) * (tabBtnH + 4)

        tab.hitBox = {
            pos = Vector2.new(tabX, btnY),
            size = Vector2.new(tabBtnW, tabBtnH)
        }

        if isActive then
            if self.activeTabPill then
                self.activeTabPill:Update(Vector2.new(tabX, btnY), Vector2.new(tabBtnW, tabBtnH), 8, self.theme.tabActiveBg, nil, true)
            end
            if self.activeTabBar then
                self.activeTabBar.Position = Vector2.new(tabX + 2, btnY + 8)
                self.activeTabBar.Size = Vector2.new(3, tabBtnH - 16)
                self.activeTabBar.Visible = true
            end
        end

        if tab.iconObject then
            local iconCol = isActive and self.theme.tabActiveBar or self.theme.tabInactive
            tab.iconObject:Update(Vector2.new(tabX + 22, btnY + 19), iconCol, true)
        end

        if tab.tabText then
            local textX = tab.iconObject and (tabX + 38) or (tabX + 16)
            tab.tabText.Position = Vector2.new(textX, btnY + 11)
            tab.tabText.Color = isActive and self.theme.tabActive or self.theme.tabInactive
            tab.tabText.Size = 13
            tab.tabText.Visible = true
        end
    end

    -- 9. Render Active Tab Content on the Right
    local contentLeft = p.X + sideW + 18
    local contentWidth = sz.X - sideW - 36
    local contentTop = p.Y + headH + 14
    local contentMaxHeight = sz.Y - headH - 28

    -- Hide non-active tab elements
    for idx, tab in ipairs(self.tabs) do
        if idx ~= self.activeTabIndex then
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.accentBar, false)
                setObjVisible(sec.titleDrawing, false)
                if sec.card then
                    sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
                end
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end

    if curTab then
        local cursorY = contentTop - curTab.scrollOffset
        local mousePos = UserInputService:GetMouseLocation()

        for _, sec in ipairs(curTab.sections) do
            -- Precalculate item heights for this section
            local secItemsH = 0
            local itemHeights = {}

            for i, item in ipairs(sec.items) do
                local h = 44
                if item.type == "slider" then
                    h = 58
                elseif item.type == "paragraph" then
                    h = 64
                elseif item.type == "divider" then
                    h = 12
                elseif item.type == "label" then
                    h = 34
                end
                itemHeights[i] = h
                secItemsH = secItemsH + h
            end

            local secCardH = #sec.items > 0 and (secItemsH + 8) or 0

            -- Section Title Header (macOS Uppercase with Vector Accent Bar)
            local titleY = cursorY
            local inTitleBounds = (titleY >= (contentTop - 10) and titleY <= (contentTop + contentMaxHeight - 16))
            if sec.accentBar then
                sec.accentBar.Position = Vector2.new(contentLeft + 4, titleY + 2)
                sec.accentBar.Size = Vector2.new(3, 11)
                sec.accentBar.Color = self.theme.sectionTitle
                sec.accentBar.Visible = inTitleBounds
            end
            if sec.titleDrawing then
                sec.titleDrawing.Position = Vector2.new(contentLeft + 14, titleY)
                sec.titleDrawing.Visible = inTitleBounds
            end
            cursorY = cursorY + 24

            -- Section Group Container Card with Boundary Clamping (Prevent header overflow)
            local cardY = cursorY
            local cardBottom = cardY + secCardH
            local isCardVisible = (secCardH > 0 and cardBottom > contentTop and cardY < (contentTop + contentMaxHeight))

            if isCardVisible then
                local drawCardY = math.max(cardY, contentTop)
                local drawCardBottom = math.min(cardBottom, contentTop + contentMaxHeight)
                local drawCardH = drawCardBottom - drawCardY

                if drawCardH > 4 and sec.card then
                    local isClipped = (cardY < contentTop or cardBottom > (contentTop + contentMaxHeight))
                    local radius = isClipped and 0 or 10
                    sec.card:Update(
                        Vector2.new(contentLeft, drawCardY),
                        Vector2.new(contentWidth, drawCardH),
                        radius,
                        self.theme.cardBg,
                        self.theme.cardBorder,
                        true,
                        "raised"
                    )
                elseif sec.card then
                    sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
                end
            else
                if sec.card then
                    sec.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), nil, false)
                end
            end

            -- Render controls inside the Section Container Card
            local rowY = cardY + 4

            for idx, item in ipairs(sec.items) do
                local itemHeight = itemHeights[idx] or 44
                local inBounds = (rowY >= contentTop and (rowY + itemHeight) <= (contentTop + contentMaxHeight))

                if inBounds and isCardVisible then
                    item.hitBox = {
                        pos = Vector2.new(contentLeft, rowY),
                        size = Vector2.new(contentWidth, itemHeight)
                    }

                    local isHovered = pointInBox(mousePos, item.hitBox.pos, item.hitBox.size)

                    -- Subtle row hover feedback
                    if item.hoverBg then
                        if isHovered and item.type ~= "divider" then
                            item.hoverBg.Position = Vector2.new(contentLeft + 2, rowY)
                            item.hoverBg.Size = Vector2.new(contentWidth - 4, itemHeight)
                            item.hoverBg.Color = self.theme.rowHover
                            item.hoverBg.Filled = true
                            item.hoverBg.Thickness = 1
                            item.hoverBg.Visible = true
                        else
                            item.hoverBg.Visible = false
                        end
                    end

                    -- Subtle inner divider line between items inside card
                    if item.innerDivider then
                        if idx < #sec.items and item.type ~= "divider" then
                            item.innerDivider.From = Vector2.new(contentLeft + 16, rowY + itemHeight)
                            item.innerDivider.To = Vector2.new(contentLeft + contentWidth - 16, rowY + itemHeight)
                            item.innerDivider.Color = self.theme.rowDivider
                            item.innerDivider.Thickness = 1
                            item.innerDivider.Visible = true
                        else
                            item.innerDivider.Visible = false
                        end
                    end

                    -- Specific item controls
                    if item.type == "toggle" then
                        local pillW = 46
                        local pillH = 24
                        local pillX = contentLeft + contentWidth - pillW - 16
                        local pillY = rowY + math.floor((itemHeight - pillH) / 2)

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Visible = true
                        end

                        if item.pill then
                            item.pill:Update(
                                Vector2.new(pillX, pillY),
                                Vector2.new(pillW, pillH),
                                item.value,
                                self.theme.toggleOn,
                                self.theme.toggleOff,
                                self.theme.toggleBorder,
                                self.theme.knob,
                                true
                            )
                        end

                    elseif item.type == "slider" then
                        local badgeW = 80
                        local badgeH = 22
                        local badgeX = contentLeft + contentWidth - badgeW - 16
                        local badgeY = rowY + 6

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 9)
                            item.label.Visible = true
                        end

                        if item.valBadgeBg then
                            item.valBadgeBg.Position = Vector2.new(badgeX, badgeY)
                            item.valBadgeBg.Size = Vector2.new(badgeW, badgeH)
                            item.valBadgeBg.Visible = true
                        end

                        if item.valBadgeBorder then
                            item.valBadgeBorder.Position = Vector2.new(badgeX, badgeY)
                            item.valBadgeBorder.Size = Vector2.new(badgeW, badgeH)
                            item.valBadgeBorder.Visible = true
                        end

                        if item.valText then
                            item.valText.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 4)
                            local valDisplay = item.value
                            if type(valDisplay) == "number" and valDisplay ~= math.floor(valDisplay) then
                                valDisplay = string.format("%.3f", valDisplay):gsub("%.?0+$", "")
                            end
                            item.valText.Text = string.format("%s%s", tostring(valDisplay), item.suffix)
                            item.valText.Visible = true
                        end

                        local trackW = contentWidth - 32
                        local trackH = 6
                        local trackX = contentLeft + 16
                        local trackY = rowY + 40
                        local fillW = math.clamp(((item.value - item.min) / math.max(0.0001, (item.max - item.min))) * trackW, 0, trackW)

                        item.trackPos = Vector2.new(trackX, trackY)
                        item.trackWidth = trackW

                        if item.track then
                            item.track.Position = Vector2.new(trackX, trackY)
                            item.track.Size = Vector2.new(trackW, trackH)
                            item.track.Color = self.theme.sliderTrack
                            item.track.Visible = true
                        end

                        if item.fill then
                            item.fill.Position = Vector2.new(trackX, trackY)
                            item.fill.Size = Vector2.new(fillW, trackH)
                            item.fill.Color = self.theme.sliderFill
                            item.fill.Visible = true
                        end

                        if item.knob then
                            item.knob.Position = Vector2.new(trackX + fillW, trackY + 3)
                            item.knob.Visible = true
                        end

                    elseif item.type == "button" then
                        local btnW = contentWidth - 32
                        local btnH = 34
                        local btnX = contentLeft + 16
                        local btnY = rowY + 5

                        if item.buttonCard then
                            local btnBg = isHovered and Color3.fromRGB(48, 54, 72) or self.theme.controlBg
                            item.buttonCard:Update(Vector2.new(btnX, btnY), Vector2.new(btnW, btnH), 6, btnBg, self.theme.controlBorder, true, "raised")
                        end

                        if item.label then
                            item.label.Position = Vector2.new(btnX + btnW / 2, btnY + 9)
                            item.label.Visible = true
                        end

                    elseif item.type == "dropdown" then
                        local badgeW = 150
                        local badgeH = 28
                        local badgeX = contentLeft + contentWidth - badgeW - 16
                        local badgeY = rowY + 8

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Visible = true
                        end

                        if item.badgeBg then
                            item.badgeBg.Position = Vector2.new(badgeX, badgeY)
                            item.badgeBg.Size = Vector2.new(badgeW, badgeH)
                            item.badgeBg.Visible = true
                        end

                        if item.badgeBorder then
                            item.badgeBorder.Position = Vector2.new(badgeX, badgeY)
                            item.badgeBorder.Size = Vector2.new(badgeW, badgeH)
                            item.badgeBorder.Visible = true
                        end

                        if item.valText then
                            item.valText.Position = Vector2.new(badgeX + 12, badgeY + 7)
                            item.valText.Text = tostring(item.current)
                            item.valText.Visible = true
                        end

                        if item.arrow then
                            item.arrow.Position = Vector2.new(badgeX + badgeW - 18, badgeY + 7)
                            item.arrow.Visible = true
                        end

                    elseif item.type == "keybind" then
                        local badgeW = 96
                        local badgeH = 26
                        local badgeX = contentLeft + contentWidth - badgeW - 16
                        local badgeY = rowY + 9

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Visible = true
                        end

                        if item.badgeBg then
                            item.badgeBg.Position = Vector2.new(badgeX, badgeY)
                            item.badgeBg.Size = Vector2.new(badgeW, badgeH)
                            item.badgeBg.Visible = true
                        end

                        if item.badgeBorder then
                            item.badgeBorder.Position = Vector2.new(badgeX, badgeY)
                            item.badgeBorder.Size = Vector2.new(badgeW, badgeH)
                            item.badgeBorder.Visible = true
                        end

                        if item.keyText then
                            item.keyText.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 6)
                            item.keyText.Color = item.listening and self.theme.accent or self.theme.text
                            item.keyText.Visible = true
                        end

                    elseif item.type == "paragraph" then
                        if item.titleText then
                            item.titleText.Position = Vector2.new(contentLeft + 16, rowY + 8)
                            item.titleText.Visible = true
                        end

                        if item.descText then
                            item.descText.Position = Vector2.new(contentLeft + 16, rowY + 32)
                            item.descText.Visible = true
                        end

                    elseif item.type == "label" then
                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 9)
                            item.label.Visible = true
                        end

                    elseif item.type == "divider" then
                        if item.line then
                            item.line.From = Vector2.new(contentLeft + 16, rowY + 6)
                            item.line.To = Vector2.new(contentLeft + contentWidth - 16, rowY + 6)
                            item.line.Visible = true
                        end

                    elseif item.type == "input" then
                        local inW = 160
                        local inH = 28
                        local inX = contentLeft + contentWidth - inW - 16
                        local inY = rowY + 8

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 16, rowY + 14)
                            item.label.Visible = true
                        end

                        if item.badgeBg then
                            item.badgeBg.Position = Vector2.new(inX, inY)
                            item.badgeBg.Size = Vector2.new(inW, inH)
                            item.badgeBg.Visible = true
                        end

                        if item.badgeBorder then
                            item.badgeBorder.Position = Vector2.new(inX, inY)
                            item.badgeBorder.Size = Vector2.new(inW, inH)
                            item.badgeBorder.Visible = true
                        end

                        if item.valText then
                            item.valText.Position = Vector2.new(inX + 12, inY + 7)
                            item.valText.Visible = true
                        end
                    end
                else
                    hideItem(item)
                end

                rowY = rowY + itemHeight
            end

            cursorY = cursorY + secCardH + 16
        end

        local totalH = cursorY - (contentTop - curTab.scrollOffset)
        curTab.maxScroll = math.max(0, totalH - contentMaxHeight)
    end
end

-- ============================================================
--   CLEANUP & UNLOAD HANDLERS
-- ============================================================
function DrawingUI:Destroy()
    self.running = false
    self.visible = false

    for _, cb in ipairs(self._unloadCallbacks) do
        pcall(cb)
    end
    table.clear(self._unloadCallbacks)

    for _, conn in ipairs(self.connections) do
        if conn and conn.Disconnect then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(self.connections)

    for _, d in pairs(self.drawings) do
        removeObj(d)
    end
    table.clear(self.drawings)

    if self.windowCard then self.windowCard:Remove() end
    if self.keyBadgeCard then self.keyBadgeCard:Remove() end
    if self.activeTabPill then self.activeTabPill:Remove() end
    removeObj(self.activeTabBar)
    if self.userCardPill then self.userCardPill:Remove() end

    for _, tab in ipairs(self.tabs) do
        removeObj(tab.tabText)
        for _, sec in ipairs(tab.sections) do
            removeObj(sec.titleDrawing)
            if sec.card then sec.card:Remove() end
            for _, item in ipairs(sec.items) do
                removeItem(item)
            end
            table.clear(sec.items)
        end
        table.clear(tab.sections)
    end
    table.clear(self.tabs)
end

return DrawingUI
