-- ============================================================
--   RAVEN HUB  |  MacLib macOS Edition (100% Drawing API Engine)
--   Authentic Apple macOS Aesthetic | Smooth Rounded Corners
--   Proportional Modern Typography | macOS Capsule Toggles
--   100% BAC / Frog Compliant (Zero Object Injection)
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
    local res = clean:gsub("^%s+", ""):gsub("%s+$", "")
    return res
end

local function setObjVisible(obj, visible)
    if obj then
        pcall(function()
            obj.Visible = visible
        end)
    end
end

local function removeObj(obj)
    if obj then
        pcall(function()
            obj.Visible = false
            obj:Remove()
        end)
    end
end

-- ============================================================
--   ROUNDED GEOMETRY HELPERS (Drawing API Smooth macOS Shapes)
-- ============================================================
local function createRoundedCard()
    local card = {
        mid   = safeDrawing("Square"),
        left  = safeDrawing("Square"),
        right = safeDrawing("Square"),
        tl    = safeDrawing("Circle"),
        tr    = safeDrawing("Circle"),
        bl    = safeDrawing("Circle"),
        br    = safeDrawing("Circle"),
    }

    for _, obj in pairs(card) do
        if obj then
            obj.Filled = true
            obj.Thickness = 1
            obj.Visible = false
        end
    end

    function card:Update(pos, size, radius, color, visible)
        if not visible then
            for _, o in pairs(self) do
                if type(o) == "userdata" or type(o) == "table" then
                    setObjVisible(o, false)
                end
            end
            return
        end

        local r = radius
        -- Middle rectangle
        if self.mid then
            self.mid.Position = Vector2.new(pos.X + r, pos.Y)
            self.mid.Size = Vector2.new(math.max(1, size.X - 2 * r), size.Y)
            self.mid.Color = color
            self.mid.Visible = true
        end
        -- Left rectangle
        if self.left then
            self.left.Position = Vector2.new(pos.X, pos.Y + r)
            self.left.Size = Vector2.new(r, math.max(1, size.Y - 2 * r))
            self.left.Color = color
            self.left.Visible = true
        end
        -- Right rectangle
        if self.right then
            self.right.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
            self.right.Size = Vector2.new(r, math.max(1, size.Y - 2 * r))
            self.right.Color = color
            self.right.Visible = true
        end
        -- Corners
        if self.tl then
            self.tl.Radius = r
            self.tl.Position = Vector2.new(pos.X + r, pos.Y + r)
            self.tl.Color = color
            self.tl.Visible = true
        end
        if self.tr then
            self.tr.Radius = r
            self.tr.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
            self.tr.Color = color
            self.tr.Visible = true
        end
        if self.bl then
            self.bl.Radius = r
            self.bl.Position = Vector2.new(pos.X + r, pos.Y + size.Y - r)
            self.bl.Color = color
            self.bl.Visible = true
        end
        if self.br then
            self.br.Radius = r
            self.br.Position = Vector2.new(pos.X + size.X - r, pos.Y + size.Y - r)
            self.br.Color = color
            self.br.Visible = true
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

local function createPillSwitch()
    local pill = {
        cLeft  = safeDrawing("Circle"),
        cRight = safeDrawing("Circle"),
        mid    = safeDrawing("Square"),
        knob   = safeDrawing("Circle"),
    }

    if pill.cLeft then pill.cLeft.Filled = true; pill.cLeft.Visible = false end
    if pill.cRight then pill.cRight.Filled = true; pill.cRight.Visible = false end
    if pill.mid then pill.mid.Filled = true; pill.mid.Thickness = 1; pill.mid.Visible = false end
    if pill.knob then pill.knob.Filled = true; pill.knob.Visible = false end

    function pill:Update(pos, size, value, colorOn, colorOff, knobColor, visible)
        if not visible then
            setObjVisible(self.cLeft, false)
            setObjVisible(self.cRight, false)
            setObjVisible(self.mid, false)
            setObjVisible(self.knob, false)
            return
        end

        local r = size.Y / 2
        local bgCol = value and colorOn or colorOff

        if self.cLeft then
            self.cLeft.Radius = r
            self.cLeft.Position = Vector2.new(pos.X + r, pos.Y + r)
            self.cLeft.Color = bgCol
            self.cLeft.Visible = true
        end

        if self.cRight then
            self.cRight.Radius = r
            self.cRight.Position = Vector2.new(pos.X + size.X - r, pos.Y + r)
            self.cRight.Color = bgCol
            self.cRight.Visible = true
        end

        if self.mid then
            self.mid.Position = Vector2.new(pos.X + r, pos.Y)
            self.mid.Size = Vector2.new(math.max(1, size.X - 2 * r), size.Y)
            self.mid.Color = bgCol
            self.mid.Visible = true
        end

        if self.knob then
            local knobR = r - 2.5
            local knobX = value and (pos.X + size.X - r) or (pos.X + r)
            self.knob.Radius = knobR
            self.knob.Position = Vector2.new(knobX, pos.Y + r)
            self.knob.Color = knobColor
            self.knob.Visible = true
        end
    end

    function pill:Remove()
        removeObj(self.cLeft)
        removeObj(self.cRight)
        removeObj(self.mid)
        removeObj(self.knob)
    end

    return pill
end

local function hideItem(item)
    if item.pill then
        pcall(function() item.pill:Update(Vector2.zero, Vector2.zero, false, Color3.new(), Color3.new(), Color3.new(), false) end)
    end
    if item.card then
        pcall(function() item.card:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), false) end)
    end
    for k, prop in pairs(item) do
        if k ~= "pill" and k ~= "card" then
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
    for k, prop in pairs(item) do
        if k ~= "pill" and k ~= "card" then
            removeObj(prop)
        end
    end
end

-- ============================================================
--   APPLE macOS DARK THEME PALETTE (1:1 MacLib Fidelity)
-- ============================================================
local MAC_THEME = {
    bg             = Color3.fromRGB(15, 16, 20),      -- Sleek macOS Charcoal
    bgSidebar      = Color3.fromRGB(12, 13, 16),      -- Ultra Dark Sidebar
    bgHeader       = Color3.fromRGB(18, 19, 24),      -- Top Window Header
    border         = Color3.fromRGB(44, 48, 60),      -- Window 1px Outer Stroke
    divider        = Color3.fromRGB(34, 37, 48),      -- Subtle Dividers

    -- macOS Window Traffic Lights (1:1 MacLib Values)
    trafficRed     = Color3.fromRGB(250, 93, 86),
    trafficYellow  = Color3.fromRGB(252, 190, 57),
    trafficGreen   = Color3.fromRGB(119, 174, 94),

    -- Typography & Highlights (Proportional Font 0 / Clean Antialiased)
    title          = Color3.fromRGB(255, 255, 255),    -- Pure White Header
    subtitle       = Color3.fromRGB(140, 145, 160),    -- Clear Slate Grey
    tabInactive    = Color3.fromRGB(155, 160, 175),    -- High-Legibility Inactive Tab
    tabActive      = Color3.fromRGB(255, 255, 255),    -- Pure White Active Tab
    tabActiveBg    = Color3.fromRGB(28, 34, 48),       -- Active Tab Background Pill
    tabActiveBar   = Color3.fromRGB(59, 130, 246),     -- Apple Vivid Blue Indicator

    -- Controls & Cards
    cardBg         = Color3.fromRGB(22, 25, 32),       -- Individual Card Background
    cardBorder     = Color3.fromRGB(42, 46, 58),       -- Card Border Stroke
    sectionTitle   = Color3.fromRGB(56, 139, 253),     -- Vibrant Apple Blue Section Header
    text           = Color3.fromRGB(245, 245, 247),    -- Crisp Soft White Labels
    textMuted      = Color3.fromRGB(155, 160, 175),    -- High-Contrast Muted Values

    controlBg      = Color3.fromRGB(22, 25, 32),       -- Buttons & Badges Background
    controlBorder  = Color3.fromRGB(42, 46, 58),       -- Buttons & Badges Stroke

    -- Apple Switches & Sliders
    toggleOn       = Color3.fromRGB(52, 199, 89),      -- Vivid Apple iOS Green
    toggleOff      = Color3.fromRGB(44, 46, 56),       -- Dark Slate Switch
    knob           = Color3.fromRGB(255, 255, 255),    -- Pure White Knob
    sliderTrack    = Color3.fromRGB(36, 40, 52),       -- Slider Track
    sliderFill     = Color3.fromRGB(56, 139, 253),     -- Apple Blue Slider Fill
    accent         = Color3.fromRGB(56, 139, 253),
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
    self.headerHeight = 42
    self.sidebarWidth = 165

    self.drawings = {}

    -- Window Outer Background
    self.drawings.bg = safeDrawing("Square")
    if self.drawings.bg then
        self.drawings.bg.Filled = true
        self.drawings.bg.Color = self.theme.bg
        self.drawings.bg.Thickness = 1
        self.drawings.bg.Visible = false
    end

    -- Window Outer 1px macOS Border
    self.drawings.border = safeDrawing("Square")
    if self.drawings.border then
        self.drawings.border.Filled = false
        self.drawings.border.Color = self.theme.border
        self.drawings.border.Thickness = 1
        self.drawings.border.Visible = false
    end

    -- Header Bar
    self.drawings.header = safeDrawing("Square")
    if self.drawings.header then
        self.drawings.header.Filled = true
        self.drawings.header.Color = self.theme.bgHeader
        self.drawings.header.Thickness = 1
        self.drawings.header.Visible = false
    end

    self.drawings.headerLine = safeDrawing("Line")
    if self.drawings.headerLine then
        self.drawings.headerLine.Thickness = 1
        self.drawings.headerLine.Color = self.theme.divider
        self.drawings.headerLine.Visible = false
    end

    -- Traffic Lights: Red (Close/Destroy)
    self.drawings.trafficRed = safeDrawing("Circle")
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Filled = true
        self.drawings.trafficRed.Color = self.theme.trafficRed
        self.drawings.trafficRed.Radius = 6.5
        self.drawings.trafficRed.Visible = false
    end

    -- Traffic Lights: Yellow (Minimize/Hide)
    self.drawings.trafficYellow = safeDrawing("Circle")
    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Filled = true
        self.drawings.trafficYellow.Color = self.theme.trafficYellow
        self.drawings.trafficYellow.Radius = 6.5
        self.drawings.trafficYellow.Visible = false
    end

    -- Traffic Lights: Green (Expand/Active)
    self.drawings.trafficGreen = safeDrawing("Circle")
    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Filled = true
        self.drawings.trafficGreen.Color = self.theme.trafficGreen
        self.drawings.trafficGreen.Radius = 6.5
        self.drawings.trafficGreen.Visible = false
    end

    -- Header Title & Subtitle (Proportional Font 0, Size 16/13, Clean Antialiased)
    self.drawings.title = safeDrawing("Text")
    if self.drawings.title then
        self.drawings.title.Font = 0
        self.drawings.title.Size = 16
        self.drawings.title.Outline = false
        self.drawings.title.Color = self.theme.title
        self.drawings.title.Text = self.title
        self.drawings.title.Visible = false
    end

    self.drawings.subtitle = safeDrawing("Text")
    if self.drawings.subtitle then
        self.drawings.subtitle.Font = 0
        self.drawings.subtitle.Size = 13
        self.drawings.subtitle.Outline = false
        self.drawings.subtitle.Color = self.theme.subtitle
        self.drawings.subtitle.Text = self.subtitle
        self.drawings.subtitle.Visible = false
    end

    -- Keybind Badge on Top-Right
    self.drawings.keyBadgeBg = safeDrawing("Square")
    if self.drawings.keyBadgeBg then
        self.drawings.keyBadgeBg.Filled = true
        self.drawings.keyBadgeBg.Color = self.theme.controlBg
        self.drawings.keyBadgeBg.Thickness = 1
        self.drawings.keyBadgeBg.Visible = false
    end

    self.drawings.keyBadgeBorder = safeDrawing("Square")
    if self.drawings.keyBadgeBorder then
        self.drawings.keyBadgeBorder.Filled = false
        self.drawings.keyBadgeBorder.Color = self.theme.controlBorder
        self.drawings.keyBadgeBorder.Thickness = 1
        self.drawings.keyBadgeBorder.Visible = false
    end

    self.drawings.hint = safeDrawing("Text")
    if self.drawings.hint then
        self.drawings.hint.Font = 0
        self.drawings.hint.Size = 12
        self.drawings.hint.Outline = false
        self.drawings.hint.Color = self.theme.textMuted
        self.drawings.hint.Text = "[RShift] Toggle"
        self.drawings.hint.Center = true
        self.drawings.hint.Visible = false
    end

    -- Left Sidebar
    self.drawings.sidebarBg = safeDrawing("Square")
    if self.drawings.sidebarBg then
        self.drawings.sidebarBg.Filled = true
        self.drawings.sidebarBg.Color = self.theme.bgSidebar
        self.drawings.sidebarBg.Thickness = 1
        self.drawings.sidebarBg.Visible = false
    end

    self.drawings.sidebarLine = safeDrawing("Line")
    if self.drawings.sidebarLine then
        self.drawings.sidebarLine.Thickness = 1
        self.drawings.sidebarLine.Color = self.theme.divider
        self.drawings.sidebarLine.Visible = false
    end

    -- Active Tab Rounded Pill Highlight
    self.activeTabPill = createRoundedCard()

    -- Active Tab Accent Left Line
    self.activeTabBar = safeDrawing("Square")
    if self.activeTabBar then
        self.activeTabBar.Filled = true
        self.activeTabBar.Color = self.theme.tabActiveBar
        self.activeTabBar.Thickness = 1
        self.activeTabBar.Visible = false
    end

    -- User Info Profile Card (Bottom of Sidebar)
    self.userCardPill = createRoundedCard()

    self.drawings.userDot = safeDrawing("Circle")
    if self.drawings.userDot then
        self.drawings.userDot.Filled = true
        self.drawings.userDot.Color = self.theme.toggleOn
        self.drawings.userDot.Radius = 4.5
        self.drawings.userDot.Visible = false
    end

    self.drawings.userName = safeDrawing("Text")
    if self.drawings.userName then
        self.drawings.userName.Font = 0
        self.drawings.userName.Size = 13
        self.drawings.userName.Outline = false
        self.drawings.userName.Color = self.theme.text
        local lp = Players.LocalPlayer
        self.drawings.userName.Text = lp and (lp.DisplayName or lp.Name) or "User"
        self.drawings.userName.Visible = false
    end

    self.drawings.userStatus = safeDrawing("Text")
    if self.drawings.userStatus then
        self.drawings.userStatus.Font = 0
        self.drawings.userStatus.Size = 11
        self.drawings.userStatus.Outline = false
        self.drawings.userStatus.Color = self.theme.textMuted
        self.drawings.userStatus.Text = "MacLib • Protected"
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
    -- Compatibility stub
end

-- ============================================================
--   TAB & SECTION ARCHITECTURE (Sidebar Navigation)
-- ============================================================
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

    local tab = setmetatable({
        name = sanitizeText(tostring(name or "Tab")),
        icon = icon,
        sections = {},
        window = self,
        scrollOffset = 0,
        maxScroll = 0,
        _currentSection = nil,
        tabText = safeDrawing("Text"),
    }, TabMethods)

    if tab.tabText then
        tab.tabText.Font = 0
        tab.tabText.Size = 15
        tab.tabText.Outline = false
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
        titleDrawing = safeDrawing("Text"),
    }, SectionMethods)

    if sec.titleDrawing then
        sec.titleDrawing.Font = 0
        sec.titleDrawing.Size = 13
        sec.titleDrawing.Outline = false
        sec.titleDrawing.Color = self.window.theme.sectionTitle
        sec.titleDrawing.Text = "- " .. string.upper(sec.name)
        sec.titleDrawing.Visible = false
    end

    self._currentSection = sec
    table.insert(self.sections, sec)
    return sec
end

-- ============================================================
--   SECTION CONTROLS (macOS Capsule Switches, Cards, Sliders)
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
        label = safeDrawing("Text"),
        pill = createPillSwitch(),
    }

    if item.label then
        item.label.Font = 0
        item.label.Size = 15
        item.label.Outline = false
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
    local range = cfg.Range or {0, 100}
    local minVal = tonumber(range[1]) or 0
    local maxVal = tonumber(range[2]) or 100
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
        label = safeDrawing("Text"),
        valBadgeBg = safeDrawing("Square"),
        valBadgeBorder = safeDrawing("Square"),
        valText = safeDrawing("Text"),
        track = safeDrawing("Square"),
        fill = safeDrawing("Square"),
        knob = safeDrawing("Circle"),
    }

    if item.label then
        item.label.Font = 0
        item.label.Size = 15
        item.label.Outline = false
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valBadgeBg then
        item.valBadgeBg.Filled = true
        item.valBadgeBg.Color = tab.window.theme.controlBg
        item.valBadgeBg.Thickness = 1
        item.valBadgeBg.Visible = false
    end

    if item.valBadgeBorder then
        item.valBadgeBorder.Filled = false
        item.valBadgeBorder.Color = tab.window.theme.controlBorder
        item.valBadgeBorder.Thickness = 1
        item.valBadgeBorder.Visible = false
    end

    if item.valText then
        item.valText.Font = 0
        item.valText.Size = 13
        item.valText.Outline = false
        item.valText.Color = tab.window.theme.textMuted
        item.valText.Center = true
        item.valText.Visible = false
    end

    if item.track then
        item.track.Thickness = 1
        item.track.Filled = true
        item.track.Color = tab.window.theme.sliderTrack
        item.track.Visible = false
    end

    if item.fill then
        item.fill.Thickness = 1
        item.fill.Filled = true
        item.fill.Color = tab.window.theme.sliderFill
        item.fill.Visible = false
    end

    if item.knob then
        item.knob.Filled = true
        item.knob.Color = tab.window.theme.knob
        item.knob.Radius = 7.5
        item.knob.Visible = false
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
        card = createRoundedCard(),
        label = safeDrawing("Text"),
    }

    if item.label then
        item.label.Font = 0
        item.label.Size = 14
        item.label.Outline = false
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
        label = safeDrawing("Text"),
    }

    if item.label then
        item.label.Font = 0
        item.label.Size = 14
        item.label.Outline = false
        item.label.Color = tab.window.theme.textMuted
        item.label.Text = item.text
        item.label.Visible = false
    end

    function item:Set(newText)
        item.text = sanitizeText(tostring(newText or ""))
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
        card = createRoundedCard(),
        titleText = safeDrawing("Text"),
        descText = safeDrawing("Text"),
    }

    if item.titleText then
        item.titleText.Font = 0
        item.titleText.Size = 14
        item.titleText.Outline = false
        item.titleText.Color = tab.window.theme.text
        item.titleText.Text = item.title
        item.titleText.Visible = false
    end

    if item.descText then
        item.descText.Font = 0
        item.descText.Size = 12
        item.descText.Outline = false
        item.descText.Color = tab.window.theme.textMuted
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
        item.line.Color = self.tab.window.theme.divider
        item.line.Visible = false
    end
    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateDropdown(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local options = cfg.Options or {"Option 1"}
    local defaultVal = tostring(cfg.CurrentOption or cfg.Default or options[1] or "")

    local item = {
        type = "dropdown",
        name = sanitizeText(tostring(cfg.Name or "Dropdown")),
        options = options,
        current = defaultVal,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        card = createRoundedCard(),
        label = safeDrawing("Text"),
        arrow = safeDrawing("Text"),
    }

    if item.label then
        item.label.Font = 0
        item.label.Size = 14
        item.label.Outline = false
        item.label.Color = tab.window.theme.text
        item.label.Text = string.format("%s:  %s", item.name, item.current)
        item.label.Visible = false
    end

    if item.arrow then
        item.arrow.Font = 0
        item.arrow.Size = 13
        item.arrow.Outline = false
        item.arrow.Color = tab.window.theme.textMuted
        item.arrow.Text = ">"
        item.arrow.Visible = false
    end

    function item:Set(val)
        item.current = tostring(val)
        if item.label then
            item.label.Text = string.format("%s:  %s", item.name, item.current)
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
        label = safeDrawing("Text"),
        badgeBg = safeDrawing("Square"),
        badgeBorder = safeDrawing("Square"),
        keyText = safeDrawing("Text"),
    }

    if item.label then
        item.label.Font = 0
        item.label.Size = 15
        item.label.Outline = false
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.badgeBg then
        item.badgeBg.Filled = true
        item.badgeBg.Color = tab.window.theme.controlBg
        item.badgeBg.Thickness = 1
        item.badgeBg.Visible = false
    end

    if item.badgeBorder then
        item.badgeBorder.Filled = false
        item.badgeBorder.Color = tab.window.theme.controlBorder
        item.badgeBorder.Thickness = 1
        item.badgeBorder.Visible = false
    end

    if item.keyText then
        item.keyText.Font = 0
        item.keyText.Size = 12
        item.keyText.Outline = false
        item.keyText.Color = tab.window.theme.textMuted
        item.keyText.Center = true
        item.keyText.Text = string.format("[%s]", item.key)
        item.keyText.Visible = false
    end

    function item:Set(newKey)
        item.key = tostring(newKey)
        item.listening = false
        if item.keyText then
            item.keyText.Text = string.format("[%s]", item.key)
            item.keyText.Color = tab.window.theme.textMuted
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
        card = createRoundedCard(),
        label = safeDrawing("Text"),
        valText = safeDrawing("Text"),
    }

    if item.label then
        item.label.Font = 0
        item.label.Size = 14
        item.label.Outline = false
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Font = 0
        item.valText.Size = 13
        item.valText.Outline = false
        item.valText.Color = tab.window.theme.textMuted
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
        if input.KeyCode == self.toggleKey then
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
                                local rel = math.clamp((mousePos.X - item.trackPos.X) / item.trackWidth, 0, 1)
                                local rawVal = item.min + (item.max - item.min) * rel
                                local steps = math.round((rawVal - item.min) / item.increment)
                                local steppedVal = item.min + steps * item.increment
                                item:Set(steppedVal)
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
                curTab.scrollOffset = math.clamp(curTab.scrollOffset - (input.Position.Z * 28), 0, curTab.maxScroll)
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
        for _, d in pairs(self.drawings) do
            setObjVisible(d, false)
        end
        if self.activeTabPill then self.activeTabPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), false) end
        setObjVisible(self.activeTabBar, false)
        if self.userCardPill then self.userCardPill:Update(Vector2.zero, Vector2.zero, 0, Color3.new(), false) end

        for _, tab in ipairs(self.tabs) do
            setObjVisible(tab.tabText, false)
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.titleDrawing, false)
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

    -- 1. Main Window Background & Border
    if self.drawings.bg then
        self.drawings.bg.Position = p
        self.drawings.bg.Size = sz
        self.drawings.bg.Visible = true
    end

    if self.drawings.border then
        self.drawings.border.Position = p
        self.drawings.border.Size = sz
        self.drawings.border.Visible = true
    end

    -- 2. Header Bar & Divider
    if self.drawings.header then
        self.drawings.header.Position = p
        self.drawings.header.Size = Vector2.new(sz.X, headH)
        self.drawings.header.Visible = true
    end

    if self.drawings.headerLine then
        self.drawings.headerLine.From = Vector2.new(p.X, p.Y + headH)
        self.drawings.headerLine.To = Vector2.new(p.X + sz.X, p.Y + headH)
        self.drawings.headerLine.Visible = true
    end

    -- 3. Traffic Lights (1:1 macOS Position & Radius)
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Position = Vector2.new(p.X + 18, p.Y + 22)
        self.drawings.trafficRed.Visible = true
    end

    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Position = Vector2.new(p.X + 36, p.Y + 22)
        self.drawings.trafficYellow.Visible = true
    end

    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Position = Vector2.new(p.X + 54, p.Y + 22)
        self.drawings.trafficGreen.Visible = true
    end

    -- 4. Title & Subtitle (Proportional Font 0, Size 16/13)
    if self.drawings.title then
        self.drawings.title.Position = Vector2.new(p.X + 75, p.Y + 13)
        self.drawings.title.Visible = true
    end

    if self.drawings.subtitle then
        self.drawings.subtitle.Position = Vector2.new(p.X + 185, p.Y + 15)
        self.drawings.subtitle.Visible = true
    end

    -- 5. Top-Right Key Badge
    local badgeW = 105
    local badgeH = 22
    local badgeX = p.X + sz.X - badgeW - 14
    local badgeY = p.Y + 10

    if self.drawings.keyBadgeBg then
        self.drawings.keyBadgeBg.Position = Vector2.new(badgeX, badgeY)
        self.drawings.keyBadgeBg.Size = Vector2.new(badgeW, badgeH)
        self.drawings.keyBadgeBg.Visible = true
    end

    if self.drawings.keyBadgeBorder then
        self.drawings.keyBadgeBorder.Position = Vector2.new(badgeX, badgeY)
        self.drawings.keyBadgeBorder.Size = Vector2.new(badgeW, badgeH)
        self.drawings.keyBadgeBorder.Visible = true
    end

    if self.drawings.hint then
        self.drawings.hint.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 4)
        self.drawings.hint.Visible = true
    end

    -- 6. Left Sidebar Background & Vertical Divider
    if self.drawings.sidebarBg then
        self.drawings.sidebarBg.Position = Vector2.new(p.X, p.Y + headH)
        self.drawings.sidebarBg.Size = Vector2.new(sideW, sz.Y - headH)
        self.drawings.sidebarBg.Visible = true
    end

    if self.drawings.sidebarLine then
        self.drawings.sidebarLine.From = Vector2.new(p.X + sideW, p.Y + headH)
        self.drawings.sidebarLine.To = Vector2.new(p.X + sideW, p.Y + sz.Y)
        self.drawings.sidebarLine.Visible = true
    end

    -- 7. Sidebar Footer (Rounded User Profile Card)
    local cardH = 40
    local cardY = p.Y + sz.Y - cardH - 10
    local cardX = p.X + 8
    local cardW = sideW - 16

    if self.userCardPill then
        self.userCardPill:Update(Vector2.new(cardX, cardY), Vector2.new(cardW, cardH), 8, self.theme.cardBg, true)
    end

    if self.drawings.userDot then
        self.drawings.userDot.Position = Vector2.new(cardX + 14, cardY + 20)
        self.drawings.userDot.Visible = true
    end

    if self.drawings.userName then
        self.drawings.userName.Position = Vector2.new(cardX + 26, cardY + 6)
        self.drawings.userName.Visible = true
    end

    if self.drawings.userStatus then
        self.drawings.userStatus.Position = Vector2.new(cardX + 26, cardY + 22)
        self.drawings.userStatus.Visible = true
    end

    -- 8. Render Tabs in Left Sidebar
    local tabStartY = p.Y + headH + 12
    local tabBtnH = 36
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
            -- Active Tab Rounded Pill Highlight
            if self.activeTabPill then
                self.activeTabPill:Update(Vector2.new(tabX, btnY), Vector2.new(tabBtnW, tabBtnH), 8, self.theme.tabActiveBg, true)
            end
            if self.activeTabBar then
                self.activeTabBar.Position = Vector2.new(tabX + 2, btnY + 8)
                self.activeTabBar.Size = Vector2.new(3, tabBtnH - 16)
                self.activeTabBar.Visible = true
            end
        end

        if tab.tabText then
            tab.tabText.Position = Vector2.new(tabX + 16, btnY + 9)
            tab.tabText.Color = isActive and self.theme.tabActive or self.theme.tabInactive
            tab.tabText.Size = isActive and 15 or 14
            tab.tabText.Visible = true
        end
    end

    -- 9. Render Active Tab Content on the Right
    local contentLeft = p.X + sideW + 20
    local contentWidth = sz.X - sideW - 40
    local contentTop = p.Y + headH + 16
    local contentMaxHeight = sz.Y - headH - 32

    for idx, tab in ipairs(self.tabs) do
        if idx ~= self.activeTabIndex then
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.titleDrawing, false)
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end

    if curTab then
        local cursorY = contentTop - curTab.scrollOffset
        local totalContentH = 0

        for _, sec in ipairs(curTab.sections) do
            -- Section Title Header (MacLib Cyan/Blue Style)
            local inHeaderBounds = (cursorY >= (contentTop - 15) and cursorY <= (contentTop + contentMaxHeight))
            if sec.titleDrawing then
                sec.titleDrawing.Position = Vector2.new(contentLeft + 2, cursorY)
                sec.titleDrawing.Visible = inHeaderBounds
            end
            cursorY = cursorY + 24

            -- Render Section Controls
            for _, item in ipairs(sec.items) do
                local itemHeight = 38
                if item.type == "paragraph" then
                    itemHeight = 54
                elseif item.type == "slider" then
                    itemHeight = 48
                elseif item.type == "divider" then
                    itemHeight = 14
                end

                local itemY = cursorY
                local inBounds = (itemY >= (contentTop - 10) and (itemY + itemHeight) <= (contentTop + contentMaxHeight + 10))

                if inBounds then
                    item.hitBox = {
                        pos = Vector2.new(contentLeft, itemY),
                        size = Vector2.new(contentWidth, itemHeight)
                    }

                    if item.type == "toggle" then
                        -- Authentic macOS Rounded Pill Toggle (Capsule)
                        local pillW = 44
                        local pillH = 22
                        local pillX = contentLeft + contentWidth - pillW - 6
                        local pillY = itemY + 8

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 4, itemY + 10)
                            item.label.Visible = true
                        end

                        if item.pill then
                            item.pill:Update(
                                Vector2.new(pillX, pillY),
                                Vector2.new(pillW, pillH),
                                item.value,
                                self.theme.toggleOn,
                                self.theme.toggleOff,
                                self.theme.knob,
                                true
                            )
                        end

                    elseif item.type == "slider" then
                        -- macOS Precise Slider with Rounded Badge & Fill Track
                        local badgeW = 60
                        local badgeH = 22
                        local badgeX = contentLeft + contentWidth - badgeW - 6
                        local badgeY = itemY + 2

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 4, itemY + 4)
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
                            item.valText.Text = string.format("%s%s", tostring(item.value), item.suffix)
                            item.valText.Visible = true
                        end

                        local trackW = contentWidth - 8
                        local trackH = 4
                        local trackX = contentLeft + 4
                        local trackY = itemY + 32
                        local fillW = math.clamp(((item.value - item.min) / (item.max - item.min)) * trackW, 0, trackW)

                        item.trackPos = Vector2.new(trackX, trackY)
                        item.trackWidth = trackW

                        if item.track then
                            item.track.Position = Vector2.new(trackX, trackY)
                            item.track.Size = Vector2.new(trackW, trackH)
                            item.track.Visible = true
                        end

                        if item.fill then
                            item.fill.Position = Vector2.new(trackX, trackY)
                            item.fill.Size = Vector2.new(fillW, trackH)
                            item.fill.Visible = true
                        end

                        if item.knob then
                            item.knob.Position = Vector2.new(trackX + fillW, trackY + 2)
                            item.knob.Visible = true
                        end

                    elseif item.type == "button" then
                        -- Full-Width Rounded macOS Button Card
                        local btnW = contentWidth - 4
                        local btnH = 36
                        local btnX = contentLeft + 2
                        local btnY = itemY + 2

                        if item.card then
                            item.card:Update(Vector2.new(btnX, btnY), Vector2.new(btnW, btnH), 8, self.theme.controlBg, true)
                        end

                        if item.label then
                            item.label.Position = Vector2.new(btnX + btnW / 2, btnY + 9)
                            item.label.Visible = true
                        end

                    elseif item.type == "paragraph" then
                        -- Full-Width Rounded Status / Paragraph Card
                        local pW = contentWidth - 4
                        local pH = 50
                        local pX = contentLeft + 2
                        local pY = itemY + 2

                        if item.card then
                            item.card:Update(Vector2.new(pX, pY), Vector2.new(pW, pH), 8, self.theme.cardBg, true)
                        end

                        if item.titleText then
                            item.titleText.Position = Vector2.new(pX + 14, pY + 8)
                            item.titleText.Visible = true
                        end

                        if item.descText then
                            item.descText.Position = Vector2.new(pX + 14, pY + 28)
                            item.descText.Visible = true
                        end

                    elseif item.type == "label" then
                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 4, itemY + 8)
                            item.label.Visible = true
                        end

                    elseif item.type == "divider" then
                        if item.line then
                            item.line.From = Vector2.new(contentLeft, itemY + 6)
                            item.line.To = Vector2.new(contentLeft + contentWidth, itemY + 6)
                            item.line.Visible = true
                        end

                    elseif item.type == "dropdown" then
                        local dW = contentWidth - 4
                        local dH = 36
                        local dX = contentLeft + 2
                        local dY = itemY + 2

                        if item.card then
                            item.card:Update(Vector2.new(dX, dY), Vector2.new(dW, dH), 8, self.theme.controlBg, true)
                        end

                        if item.label then
                            item.label.Position = Vector2.new(dX + 14, dY + 9)
                            item.label.Visible = true
                        end

                        if item.arrow then
                            item.arrow.Position = Vector2.new(dX + dW - 20, dY + 9)
                            item.arrow.Visible = true
                        end

                    elseif item.type == "keybind" then
                        local badgeW = 70
                        local badgeH = 24
                        local badgeX = contentLeft + contentWidth - badgeW - 6
                        local badgeY = itemY + 6

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 4, itemY + 10)
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
                            item.keyText.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 5)
                            item.keyText.Visible = true
                        end

                    elseif item.type == "input" then
                        local inW = contentWidth - 4
                        local inH = 36
                        local inX = contentLeft + 2
                        local inY = itemY + 2

                        if item.card then
                            item.card:Update(Vector2.new(inX, inY), Vector2.new(inW, inH), 8, self.theme.controlBg, true)
                        end

                        if item.label then
                            item.label.Position = Vector2.new(inX + 14, inY + 9)
                            item.label.Visible = true
                        end

                        if item.valText then
                            item.valText.Position = Vector2.new(inX + inW - 120, inY + 9)
                            item.valText.Visible = true
                        end
                    end
                else
                    hideItem(item)
                end

                cursorY = cursorY + itemHeight + 6
            end

            cursorY = cursorY + 12
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

    for _, conn in ipairs(self.connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(self.connections)

    for _, d in pairs(self.drawings) do
        removeObj(d)
    end
    table.clear(self.drawings)

    if self.activeTabPill then self.activeTabPill:Remove() end
    removeObj(self.activeTabBar)
    if self.userCardPill then self.userCardPill:Remove() end

    for _, tab in ipairs(self.tabs) do
        removeObj(tab.tabText)
        for _, sec in ipairs(tab.sections) do
            removeObj(sec.titleDrawing)
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
