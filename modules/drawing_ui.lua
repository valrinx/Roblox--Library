-- ============================================================
--   RAVEN HUB  |  MacLib macOS Edition (100% Drawing API Engine)
--   Apple Dark Mode Aesthetic | Zero Instance Injection
--   Traffic Lights (🔴🟡🟢), Left Sidebar, macOS Pill Toggles
--   100% BAC / Frog Compliant (Zero Object Injection)
-- ============================================================

local DrawingUI = {}
DrawingUI.__index = DrawingUI
DrawingUI.Flags = {}

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local StarterGui       = game:GetService("StarterGui")
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
    local clean = str:gsub("[^\x20-\x7E]", "")
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

local function hideItem(item)
    for _, prop in pairs(item) do
        if type(prop) == "userdata" or type(prop) == "table" then
            setObjVisible(prop, false)
        end
    end
    item.hitBox = nil
end

local function removeItem(item)
    for _, prop in pairs(item) do
        if type(prop) == "userdata" or type(prop) == "table" then
            removeObj(prop)
        end
    end
end

-- ============================================================
--   APPLE macOS DARK THEME PALETTE
-- ============================================================
local MAC_THEME = {
    bg             = Color3.fromRGB(22, 23, 27),
    bgSidebar      = Color3.fromRGB(17, 18, 22),
    bgHeader       = Color3.fromRGB(28, 30, 36),
    border         = Color3.fromRGB(46, 49, 60),
    divider        = Color3.fromRGB(38, 40, 50),

    -- macOS Window Traffic Lights
    trafficRed     = Color3.fromRGB(255, 95, 87),
    trafficYellow  = Color3.fromRGB(254, 188, 46),
    trafficGreen   = Color3.fromRGB(40, 200, 64),
    trafficBorder  = Color3.fromRGB(0, 0, 0),

    -- Typography & Highlights
    title          = Color3.fromRGB(250, 250, 250),
    subtitle       = Color3.fromRGB(130, 135, 150),
    tabInactive    = Color3.fromRGB(145, 150, 165),
    tabActive      = Color3.fromRGB(255, 255, 255),
    tabActiveBg    = Color3.fromRGB(34, 38, 50),
    tabActiveBar   = Color3.fromRGB(10, 132, 255), -- Apple Blue

    -- Controls & Cards
    cardBg         = Color3.fromRGB(26, 28, 35),
    cardBorder     = Color3.fromRGB(40, 43, 54),
    sectionTitle   = Color3.fromRGB(10, 132, 255),
    text           = Color3.fromRGB(230, 235, 245),
    textMuted      = Color3.fromRGB(130, 135, 150),

    controlBg      = Color3.fromRGB(32, 35, 44),
    controlBorder  = Color3.fromRGB(50, 54, 68),

    -- Apple Switches & Sliders
    toggleOn       = Color3.fromRGB(48, 209, 88),  -- Apple Green
    toggleOff      = Color3.fromRGB(48, 51, 62),
    knob           = Color3.fromRGB(255, 255, 255),
    sliderTrack    = Color3.fromRGB(38, 41, 52),
    sliderFill     = Color3.fromRGB(10, 132, 255),
    accent         = Color3.fromRGB(10, 132, 255),
}

-- ============================================================
--   NOTIFICATIONS
-- ============================================================
function DrawingUI.Notify(options)
    options = options or {}
    local title = sanitizeText(tostring(options.Title or "RAVEN HUB"))
    local content = sanitizeText(tostring(options.Content or options.Description or options.Text or ""))
    local duration = tonumber(options.Duration or options.Lifetime) or 5

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = content:sub(1, 150),
            Duration = duration,
        })
    end)
end

function DrawingUI:Notify(options)
    DrawingUI.Notify(options)
end

function DrawingUI:LoadAutoLoadConfig()
    return true
end

-- ============================================================
--   WINDOW CONSTRUCTOR (MacLib macOS Architecture)
-- ============================================================
function DrawingUI.CreateWindow(selfOrConfig, maybeConfig)
    local config
    if type(maybeConfig) == "table" then
        config = maybeConfig
    elseif type(selfOrConfig) == "table" and not selfOrConfig.CreateWindow then
        config = selfOrConfig
    else
        config = maybeConfig or selfOrConfig or {}
    end

    local self = setmetatable({}, DrawingUI)

    self.title = sanitizeText(tostring(config.Name or config.Title or "RAVEN HUB"))
    self.subtitle = sanitizeText(tostring(config.LoadingSubtitle or config.Subtitle or "MacLib macOS Edition"))
    self.toggleKey = config.Keybind or config.ToggleKey or Enum.KeyCode.RightShift

    self.visible = true
    self.running = true
    self.tabs = {}
    self.activeTabIndex = 1

    -- macOS Window Geometry
    self.pos = config.Position or Vector2.new(60, 60)
    self.size = config.Size or Vector2.new(680, 480)
    self.headerHeight = 42
    self.sidebarWidth = 160

    self.theme = MAC_THEME

    -- Root Window Drawing Elements
    self.drawings = {}

    -- Main Window Body
    self.drawings.bg = safeDrawing("Square")
    if self.drawings.bg then
        self.drawings.bg.Filled = true
        self.drawings.bg.Color = self.theme.bg
        self.drawings.bg.Thickness = 1
        self.drawings.bg.Visible = false
    end

    -- Window Outer Border
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

    -- Traffic Lights: Red (Close/Unload)
    self.drawings.trafficRed = safeDrawing("Circle")
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Filled = true
        self.drawings.trafficRed.Color = self.theme.trafficRed
        self.drawings.trafficRed.Radius = 5.5
        self.drawings.trafficRed.Visible = false
    end

    -- Traffic Lights: Yellow (Minimize/Hide)
    self.drawings.trafficYellow = safeDrawing("Circle")
    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Filled = true
        self.drawings.trafficYellow.Color = self.theme.trafficYellow
        self.drawings.trafficYellow.Radius = 5.5
        self.drawings.trafficYellow.Visible = false
    end

    -- Traffic Lights: Green (Expand/Active)
    self.drawings.trafficGreen = safeDrawing("Circle")
    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Filled = true
        self.drawings.trafficGreen.Color = self.theme.trafficGreen
        self.drawings.trafficGreen.Radius = 5.5
        self.drawings.trafficGreen.Visible = false
    end

    -- Header Title & Subtitle
    self.drawings.title = safeDrawing("Text")
    if self.drawings.title then
        self.drawings.title.Size = 13
        self.drawings.title.Outline = true
        self.drawings.title.OutlineColor = Color3.fromRGB(0, 0, 0)
        self.drawings.title.Color = self.theme.title
        self.drawings.title.Text = self.title
        self.drawings.title.Visible = false
    end

    self.drawings.subtitle = safeDrawing("Text")
    if self.drawings.subtitle then
        self.drawings.subtitle.Size = 11
        self.drawings.subtitle.Outline = true
        self.drawings.subtitle.OutlineColor = Color3.fromRGB(0, 0, 0)
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
        self.drawings.hint.Size = 10
        self.drawings.hint.Outline = true
        self.drawings.hint.OutlineColor = Color3.fromRGB(0, 0, 0)
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

    -- User Info Profile Card (Bottom of Sidebar)
    self.drawings.userCard = safeDrawing("Square")
    if self.drawings.userCard then
        self.drawings.userCard.Filled = true
        self.drawings.userCard.Color = self.theme.cardBg
        self.drawings.userCard.Thickness = 1
        self.drawings.userCard.Visible = false
    end

    self.drawings.userDot = safeDrawing("Circle")
    if self.drawings.userDot then
        self.drawings.userDot.Filled = true
        self.drawings.userDot.Color = self.theme.toggleOn
        self.drawings.userDot.Radius = 4
        self.drawings.userDot.Visible = false
    end

    self.drawings.userName = safeDrawing("Text")
    if self.drawings.userName then
        self.drawings.userName.Size = 11
        self.drawings.userName.Outline = true
        self.drawings.userName.OutlineColor = Color3.fromRGB(0, 0, 0)
        self.drawings.userName.Color = self.theme.text
        local lp = Players.LocalPlayer
        self.drawings.userName.Text = lp and (lp.DisplayName or lp.Name) or "User"
        self.drawings.userName.Visible = false
    end

    self.drawings.userStatus = safeDrawing("Text")
    if self.drawings.userStatus then
        self.drawings.userStatus.Size = 9
        self.drawings.userStatus.Outline = true
        self.drawings.userStatus.OutlineColor = Color3.fromRGB(0, 0, 0)
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
        tabBtn = safeDrawing("Square"),
        tabBar = safeDrawing("Square"),
        tabText = safeDrawing("Text"),
    }, TabMethods)

    if tab.tabBtn then
        tab.tabBtn.Filled = true
        tab.tabBtn.Color = self.theme.tabActiveBg
        tab.tabBtn.Thickness = 1
        tab.tabBtn.Visible = false
    end

    if tab.tabBar then
        tab.tabBar.Filled = true
        tab.tabBar.Color = self.theme.tabActiveBar
        tab.tabBar.Thickness = 1
        tab.tabBar.Visible = false
    end

    if tab.tabText then
        tab.tabText.Size = 12
        tab.tabText.Outline = true
        tab.tabText.OutlineColor = Color3.fromRGB(0, 0, 0)
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
    for idx, n in ipairs(orderedNames) do
        orderMap[sanitizeText(tostring(n)):lower()] = idx
    end

    table.sort(self.tabs, function(a, b)
        local orderA = orderMap[a.name:lower()] or 999
        local orderB = orderMap[b.name:lower()] or 999
        return orderA < orderB
    end)
end

function DrawingUI:CreatePlaceholderTab(name, icon, message)
    local tab = self:CreateTab(name, icon)
    local sec = tab:CreateSection(tostring(name or "Unavailable"))
    sec:CreateStatus({
        Title = tostring(name or "Feature") .. " unavailable",
        Content = tostring(message or "No compatible module is loaded."),
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
        cardBg = safeDrawing("Square"),
        cardBorder = safeDrawing("Square"),
    }, SectionMethods)

    if sec.titleDrawing then
        sec.titleDrawing.Size = 11
        sec.titleDrawing.Outline = true
        sec.titleDrawing.OutlineColor = Color3.fromRGB(0, 0, 0)
        sec.titleDrawing.Color = self.window.theme.sectionTitle
        sec.titleDrawing.Text = string.upper(sec.name)
        sec.titleDrawing.Visible = false
    end

    if sec.cardBg then
        sec.cardBg.Filled = true
        sec.cardBg.Color = self.window.theme.cardBg
        sec.cardBg.Thickness = 1
        sec.cardBg.Visible = false
    end

    if sec.cardBorder then
        sec.cardBorder.Filled = false
        sec.cardBorder.Color = self.window.theme.cardBorder
        sec.cardBorder.Thickness = 1
        sec.cardBorder.Visible = false
    end

    self._currentSection = sec
    table.insert(self.sections, sec)
    return sec
end

-- ============================================================
--   SECTION CONTROLS (macOS Pill Switches, Sliders, Dropdowns)
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
        track = safeDrawing("Square"),
        knob = safeDrawing("Circle"),
    }

    if item.label then
        item.label.Size = 12
        item.label.Outline = true
        item.label.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.track then
        item.track.Thickness = 1
        item.track.Filled = true
        item.track.Color = item.value and tab.window.theme.toggleOn or tab.window.theme.toggleOff
        item.track.Visible = false
    end

    if item.knob then
        item.knob.Filled = true
        item.knob.Color = tab.window.theme.knob
        item.knob.Radius = 6
        item.knob.Visible = false
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
        valText = safeDrawing("Text"),
        track = safeDrawing("Square"),
        fill = safeDrawing("Square"),
        knob = safeDrawing("Circle"),
    }

    if item.label then
        item.label.Size = 12
        item.label.Outline = true
        item.label.OutlineColor = Color3.fromRGB(0, 0, 0)
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

    if item.valText then
        item.valText.Size = 10
        item.valText.Outline = true
        item.valText.OutlineColor = Color3.fromRGB(0, 0, 0)
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
        item.knob.Radius = 5.5
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
        box = safeDrawing("Square"),
        boxBorder = safeDrawing("Square"),
        label = safeDrawing("Text"),
    }

    if item.box then
        item.box.Thickness = 1
        item.box.Filled = true
        item.box.Color = tab.window.theme.controlBg
        item.box.Visible = false
    end

    if item.boxBorder then
        item.boxBorder.Thickness = 1
        item.boxBorder.Filled = false
        item.boxBorder.Color = tab.window.theme.controlBorder
        item.boxBorder.Visible = false
    end

    if item.label then
        item.label.Size = 12
        item.label.Outline = true
        item.label.OutlineColor = Color3.fromRGB(0, 0, 0)
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

function SectionMethods:CreateParagraph(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local item = {
        type = "paragraph",
        title = sanitizeText(tostring(cfg.Title or "Paragraph")),
        content = sanitizeText(tostring(cfg.Content or "")),
        card = safeDrawing("Square"),
        titleText = safeDrawing("Text"),
        descText = safeDrawing("Text"),
    }

    if item.card then
        item.card.Thickness = 1
        item.card.Filled = true
        item.card.Color = tab.window.theme.controlBg
        item.card.Visible = false
    end

    if item.titleText then
        item.titleText.Size = 12
        item.titleText.Outline = true
        item.titleText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.titleText.Color = tab.window.theme.text
        item.titleText.Text = item.title
        item.titleText.Visible = false
    end

    if item.descText then
        item.descText.Size = 10
        item.descText.Outline = true
        item.descText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.descText.Color = tab.window.theme.textMuted
        item.descText.Text = item.content
        item.descText.Visible = false
    end

    function item:Set(val)
        item.content = sanitizeText(tostring(val or ""))
        if item.descText then
            item.descText.Text = item.content
        end
    end

    function item:SetTitle(val)
        item.title = sanitizeText(tostring(val or ""))
        if item.titleText then
            item.titleText.Text = item.title
        end
    end

    function item:SetDesc(val)
        item:Set(val)
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateLabel(textOrCfg)
    local title = type(textOrCfg) == "table" and (textOrCfg.Title or textOrCfg.Name or textOrCfg.Text) or tostring(textOrCfg or "")
    return self:CreateParagraph({ Title = title, Content = "" })
end

function SectionMethods:CreateStatus(cfg)
    cfg = cfg or {}
    local item = self:CreateParagraph({
        Title = cfg.Title or "Status",
        Content = cfg.Content or "",
    })

    function item:Set(text)
        local str = tostring(text or "")
        local lower = string.lower(str)
        local title = cfg.Title or "Status"
        if lower:find("failed", 1, true) then
            title = "Module failed to load"
        elseif lower:find("loaded", 1, true) then
            title = "Experience module ready"
        elseif lower:find("no matching", 1, true) then
            title = "No compatible module"
        elseif lower:find("loading", 1, true) then
            title = "Loading module"
        end
        self:SetTitle(title)
        self:SetDesc(str)
    end

    return item
end

function SectionMethods:CreateDivider()
    local tab = self.tab
    local item = {
        type = "divider",
        line = safeDrawing("Line"),
    }
    if item.line then
        item.line.Thickness = 1
        item.line.Color = tab.window.theme.divider
        item.line.Visible = false
    end
    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateDropdown(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local rawOptions = cfg.Options or {}
    local optionsList = {}
    for _, opt in ipairs(rawOptions) do
        table.insert(optionsList, sanitizeText(tostring(opt)))
    end
    if #optionsList == 0 then
        table.insert(optionsList, "Default")
    end

    local initial = cfg.CurrentOption or cfg.Default
    if type(initial) == "table" then
        initial = initial[1]
    end
    initial = sanitizeText(tostring(initial or optionsList[1] or ""))

    local item = {
        type = "dropdown",
        name = sanitizeText(tostring(cfg.Name or "Dropdown")),
        options = optionsList,
        selected = initial,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        label = safeDrawing("Text"),
        box = safeDrawing("Square"),
        boxBorder = safeDrawing("Square"),
        selectedText = safeDrawing("Text"),
        arrow = safeDrawing("Text"),
    }

    if item.label then
        item.label.Size = 12
        item.label.Outline = true
        item.label.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.box then
        item.box.Thickness = 1
        item.box.Filled = true
        item.box.Color = tab.window.theme.controlBg
        item.box.Visible = false
    end

    if item.boxBorder then
        item.boxBorder.Thickness = 1
        item.boxBorder.Filled = false
        item.boxBorder.Color = tab.window.theme.controlBorder
        item.boxBorder.Visible = false
    end

    if item.selectedText then
        item.selectedText.Size = 11
        item.selectedText.Outline = true
        item.selectedText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.selectedText.Color = tab.window.theme.text
        item.selectedText.Text = item.selected
        item.selectedText.Visible = false
    end

    if item.arrow then
        item.arrow.Size = 10
        item.arrow.Outline = true
        item.arrow.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.arrow.Color = tab.window.theme.textMuted
        item.arrow.Text = "v"
        item.arrow.Visible = false
    end

    function item:Set(choice)
        if type(choice) == "table" then
            choice = choice[1]
        end
        choice = sanitizeText(tostring(choice or ""))
        item.selected = choice
        if item.selectedText then
            local textVal = item.selected
            if #textVal > 22 then textVal = textVal:sub(1, 20) .. ".." end
            item.selectedText.Text = textVal
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.selected
        end
        pcall(item.callback, item.selected)
    end

    function item:CycleNext()
        local curIdx = table.find(item.options, item.selected) or 1
        local nextIdx = (curIdx % #item.options) + 1
        item:Set(item.options[nextIdx])
    end

    function item:Refresh(newList, keepCurrent)
        item.options = {}
        for _, opt in ipairs(newList or {}) do
            table.insert(item.options, sanitizeText(tostring(opt)))
        end
        if #item.options == 0 then
            table.insert(item.options, "Default")
        end
        if not keepCurrent or not table.find(item.options, item.selected) then
            item:Set(item.options[1])
        end
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.selected
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateKeybind(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local initialKey = cfg.CurrentKeybind or cfg.Default or Enum.KeyCode.RightShift
    if typeof(initialKey) == "EnumItem" then
        initialKey = initialKey.Name
    end

    local item = {
        type = "keybind",
        name = sanitizeText(tostring(cfg.Name or "Keybind")),
        key = tostring(initialKey),
        listening = false,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        label = safeDrawing("Text"),
        box = safeDrawing("Square"),
        boxBorder = safeDrawing("Square"),
        keyText = safeDrawing("Text"),
    }

    if item.label then
        item.label.Size = 12
        item.label.Outline = true
        item.label.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.box then
        item.box.Thickness = 1
        item.box.Filled = true
        item.box.Color = tab.window.theme.controlBg
        item.box.Visible = false
    end

    if item.boxBorder then
        item.boxBorder.Thickness = 1
        item.boxBorder.Filled = false
        item.boxBorder.Color = tab.window.theme.controlBorder
        item.boxBorder.Visible = false
    end

    if item.keyText then
        item.keyText.Size = 10
        item.keyText.Outline = true
        item.keyText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.keyText.Color = tab.window.theme.accent
        item.keyText.Center = true
        item.keyText.Text = "[" .. item.key .. "]"
        item.keyText.Visible = false
    end

    function item:Set(key)
        if typeof(key) == "EnumItem" then
            key = key.Name
        end
        item.key = tostring(key)
        item.listening = false
        if item.keyText then
            item.keyText.Text = "[" .. item.key .. "]"
            item.keyText.Color = tab.window.theme.accent
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.key
        end
        pcall(item.callback, item.key)
    end

    table.insert(self.items, item)
    return item
end

function SectionMethods:CreateInput(cfg)
    cfg = cfg or {}
    local tab = self.tab
    local initialText = sanitizeText(tostring(cfg.CurrentValue or cfg.Default or ""))

    local item = {
        type = "input",
        name = sanitizeText(tostring(cfg.Name or "Input")),
        text = initialText,
        placeholder = sanitizeText(tostring(cfg.PlaceholderText or "Type here...")),
        listening = false,
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        label = safeDrawing("Text"),
        box = safeDrawing("Square"),
        boxBorder = safeDrawing("Square"),
        inputText = safeDrawing("Text"),
    }

    if item.label then
        item.label.Size = 12
        item.label.Outline = true
        item.label.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.box then
        item.box.Thickness = 1
        item.box.Filled = true
        item.box.Color = tab.window.theme.controlBg
        item.box.Visible = false
    end

    if item.boxBorder then
        item.boxBorder.Thickness = 1
        item.boxBorder.Filled = false
        item.boxBorder.Color = tab.window.theme.controlBorder
        item.boxBorder.Visible = false
    end

    if item.inputText then
        item.inputText.Size = 10
        item.inputText.Outline = true
        item.inputText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.inputText.Color = #item.text > 0 and tab.window.theme.text or tab.window.theme.textMuted
        item.inputText.Text = #item.text > 0 and item.text or item.placeholder
        item.inputText.Visible = false
    end

    function item:Set(val)
        item.text = sanitizeText(tostring(val or ""))
        if item.inputText then
            item.inputText.Text = #item.text > 0 and item.text or item.placeholder
            item.inputText.Color = #item.text > 0 and tab.window.theme.text or tab.window.theme.textMuted
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

            -- 1. Check Traffic Lights
            local trafficRedPos = Vector2.new(self.pos.X + 18, self.pos.Y + 21)
            if pointInCircle(mousePos, trafficRedPos, 8) then
                self:Destroy()
                return
            end

            local trafficYellowPos = Vector2.new(self.pos.X + 36, self.pos.Y + 21)
            if pointInCircle(mousePos, trafficYellowPos, 8) then
                self:Toggle()
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
                curTab.scrollOffset = math.clamp(curTab.scrollOffset - (input.Position.Z * 26), 0, curTab.maxScroll)
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
        for _, tab in ipairs(self.tabs) do
            setObjVisible(tab.tabBtn, false)
            setObjVisible(tab.tabBar, false)
            setObjVisible(tab.tabText, false)
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.titleDrawing, false)
                setObjVisible(sec.cardBg, false)
                setObjVisible(sec.cardBorder, false)
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end
end

-- ============================================================
--   MAIN RENDER PIPELINE (macOS Layout Engine)
-- ============================================================
function DrawingUI:Render()
    if not self.visible then return end

    local p = self.pos
    local sz = self.size
    local sideW = self.sidebarWidth
    local headH = self.headerHeight

    -- 1. Main Background
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

    -- 2. Header Bar
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

    -- 3. Traffic Lights
    if self.drawings.trafficRed then
        self.drawings.trafficRed.Position = Vector2.new(p.X + 18, p.Y + 21)
        self.drawings.trafficRed.Visible = true
    end

    if self.drawings.trafficYellow then
        self.drawings.trafficYellow.Position = Vector2.new(p.X + 36, p.Y + 21)
        self.drawings.trafficYellow.Visible = true
    end

    if self.drawings.trafficGreen then
        self.drawings.trafficGreen.Position = Vector2.new(p.X + 54, p.Y + 21)
        self.drawings.trafficGreen.Visible = true
    end

    -- 4. Title & Subtitle
    if self.drawings.title then
        self.drawings.title.Position = Vector2.new(p.X + 76, p.Y + 14)
        self.drawings.title.Visible = true
    end

    if self.drawings.subtitle then
        self.drawings.subtitle.Position = Vector2.new(p.X + 165, p.Y + 16)
        self.drawings.subtitle.Visible = true
    end

    -- 5. Top-Right Key Badge
    local badgeW = 90
    local badgeH = 20
    local badgeX = p.X + sz.X - badgeW - 12
    local badgeY = p.Y + 11

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

    -- 6. Left Sidebar Background & Divider
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

    -- 7. Sidebar Footer (User Info Card)
    local cardH = 34
    local cardY = p.Y + sz.Y - cardH - 10
    local cardX = p.X + 9
    local cardW = sideW - 18

    if self.drawings.userCard then
        self.drawings.userCard.Position = Vector2.new(cardX, cardY)
        self.drawings.userCard.Size = Vector2.new(cardW, cardH)
        self.drawings.userCard.Visible = true
    end

    if self.drawings.userDot then
        self.drawings.userDot.Position = Vector2.new(cardX + 12, cardY + 17)
        self.drawings.userDot.Visible = true
    end

    if self.drawings.userName then
        self.drawings.userName.Position = Vector2.new(cardX + 22, cardY + 4)
        self.drawings.userName.Visible = true
    end

    if self.drawings.userStatus then
        self.drawings.userStatus.Position = Vector2.new(cardX + 22, cardY + 18)
        self.drawings.userStatus.Visible = true
    end

    -- 8. Render Tabs in Left Sidebar
    local tabStartY = p.Y + headH + 12
    local tabBtnH = 30
    local tabBtnW = sideW - 18

    for idx, tab in ipairs(self.tabs) do
        local isActive = (idx == self.activeTabIndex)
        local btnY = tabStartY + (idx - 1) * (tabBtnH + 4)

        tab.hitBox = {
            pos = Vector2.new(cardX, btnY),
            size = Vector2.new(tabBtnW, tabBtnH)
        }

        if tab.tabBtn then
            tab.tabBtn.Position = Vector2.new(cardX, btnY)
            tab.tabBtn.Size = Vector2.new(tabBtnW, tabBtnH)
            tab.tabBtn.Color = isActive and self.theme.tabActiveBg or self.theme.bgSidebar
            tab.tabBtn.Visible = isActive
        end

        if tab.tabBar then
            tab.tabBar.Position = Vector2.new(cardX, btnY + 4)
            tab.tabBar.Size = Vector2.new(3, tabBtnH - 8)
            tab.tabBar.Visible = isActive
        end

        if tab.tabText then
            tab.tabText.Position = Vector2.new(cardX + 14, btnY + 8)
            tab.tabText.Color = isActive and self.theme.tabActive or self.theme.tabInactive
            tab.tabText.Visible = true
        end
    end

    -- 9. Render Active Tab Content on the Right
    local contentLeft = p.X + sideW + 16
    local contentWidth = sz.X - sideW - 32
    local contentTop = p.Y + headH + 12
    local contentMaxHeight = sz.Y - headH - 24

    for idx, tab in ipairs(self.tabs) do
        if idx ~= self.activeTabIndex then
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.titleDrawing, false)
                setObjVisible(sec.cardBg, false)
                setObjVisible(sec.cardBorder, false)
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end

    local curTab = self.tabs[self.activeTabIndex]
    if curTab then
        local cursorY = contentTop - curTab.scrollOffset
        local totalContentH = 0

        for _, sec in ipairs(curTab.sections) do
            local secStartY = cursorY

            -- Section Header
            if sec.titleDrawing then
                sec.titleDrawing.Position = Vector2.new(contentLeft + 4, cursorY)
                sec.titleDrawing.Visible = (cursorY >= contentTop and cursorY <= contentTop + contentMaxHeight)
            end
            cursorY = cursorY + 20

            local cardContentStartY = cursorY
            local cardPadding = 8

            -- Render Section Items
            for _, item in ipairs(sec.items) do
                local itemHeight = 30
                if item.type == "paragraph" then
                    itemHeight = 44
                end

                local itemY = cursorY
                local inBounds = (itemY >= contentTop and (itemY + itemHeight) <= (contentTop + contentMaxHeight + 10))

                if inBounds then
                    item.hitBox = {
                        pos = Vector2.new(contentLeft, itemY),
                        size = Vector2.new(contentWidth, itemHeight)
                    }

                    if item.type == "toggle" then
                        -- macOS Pill Toggle
                        local pillW = 34
                        local pillH = 18
                        local pillX = contentLeft + contentWidth - pillW - 8
                        local pillY = itemY + (itemHeight - pillH) / 2

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 8, itemY + 8)
                            item.label.Visible = true
                        end

                        if item.track then
                            item.track.Position = Vector2.new(pillX, pillY)
                            item.track.Size = Vector2.new(pillW, pillH)
                            item.track.Color = item.value and self.theme.toggleOn or self.theme.toggleOff
                            item.track.Visible = true
                        end

                        if item.knob then
                            local knobX = item.value and (pillX + pillW - 10) or (pillX + 9)
                            item.knob.Position = Vector2.new(knobX, pillY + pillH / 2)
                            item.knob.Visible = true
                        end

                    elseif item.type == "slider" then
                        -- macOS Thin Slider Track with Knob
                        local badgeW = 55
                        local badgeH = 18
                        local badgeX = contentLeft + contentWidth - badgeW - 8
                        local badgeY = itemY + 2

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 8, itemY + 4)
                            item.label.Visible = true
                        end

                        if item.valBadgeBg then
                            item.valBadgeBg.Position = Vector2.new(badgeX, badgeY)
                            item.valBadgeBg.Size = Vector2.new(badgeW, badgeH)
                            item.valBadgeBg.Visible = true
                        end

                        if item.valText then
                            item.valText.Position = Vector2.new(badgeX + badgeW / 2, badgeY + 4)
                            item.valText.Text = string.format("%s%s", tostring(item.value), item.suffix)
                            item.valText.Visible = true
                        end

                        local trackW = contentWidth - 16
                        local trackH = 4
                        local trackX = contentLeft + 8
                        local trackY = itemY + 22
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
                            item.knob.Position = Vector2.new(trackX + fillW, trackY + trackH / 2)
                            item.knob.Visible = true
                        end

                    elseif item.type == "button" then
                        local btnW = contentWidth - 16
                        local btnH = itemHeight - 4
                        local btnX = contentLeft + 8
                        local btnY = itemY + 2

                        if item.box then
                            item.box.Position = Vector2.new(btnX, btnY)
                            item.box.Size = Vector2.new(btnW, btnH)
                            item.box.Visible = true
                        end

                        if item.boxBorder then
                            item.boxBorder.Position = Vector2.new(btnX, btnY)
                            item.boxBorder.Size = Vector2.new(btnW, btnH)
                            item.boxBorder.Visible = true
                        end

                        if item.label then
                            item.label.Position = Vector2.new(btnX + btnW / 2, btnY + 7)
                            item.label.Visible = true
                        end

                    elseif item.type == "dropdown" then
                        local dropW = 160
                        local dropH = 20
                        local dropX = contentLeft + contentWidth - dropW - 8
                        local dropY = itemY + 5

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 8, itemY + 8)
                            item.label.Visible = true
                        end

                        if item.box then
                            item.box.Position = Vector2.new(dropX, dropY)
                            item.box.Size = Vector2.new(dropW, dropH)
                            item.box.Visible = true
                        end

                        if item.boxBorder then
                            item.boxBorder.Position = Vector2.new(dropX, dropY)
                            item.boxBorder.Size = Vector2.new(dropW, dropH)
                            item.boxBorder.Visible = true
                        end

                        if item.selectedText then
                            item.selectedText.Position = Vector2.new(dropX + 8, dropY + 4)
                            item.selectedText.Visible = true
                        end

                        if item.arrow then
                            item.arrow.Position = Vector2.new(dropX + dropW - 14, dropY + 4)
                            item.arrow.Visible = true
                        end

                    elseif item.type == "keybind" then
                        local bindW = 75
                        local bindH = 20
                        local bindX = contentLeft + contentWidth - bindW - 8
                        local bindY = itemY + 5

                        if item.label then
                            item.label.Position = Vector2.new(contentLeft + 8, itemY + 8)
                            item.label.Visible = true
                        end

                        if item.box then
                            item.box.Position = Vector2.new(bindX, bindY)
                            item.box.Size = Vector2.new(bindW, bindH)
                            item.box.Visible = true
                        end

                        if item.boxBorder then
                            item.boxBorder.Position = Vector2.new(bindX, bindY)
                            item.boxBorder.Size = Vector2.new(bindW, bindH)
                            item.boxBorder.Visible = true
                        end

                        if item.keyText then
                            item.keyText.Position = Vector2.new(bindX + bindW / 2, bindY + 5)
                            item.keyText.Visible = true
                        end

                    elseif item.type == "paragraph" then
                        local pW = contentWidth - 16
                        local pH = itemHeight - 4
                        local pX = contentLeft + 8
                        local pY = itemY + 2

                        if item.card then
                            item.card.Position = Vector2.new(pX, pY)
                            item.card.Size = Vector2.new(pW, pH)
                            item.card.Visible = true
                        end

                        if item.titleText then
                            item.titleText.Position = Vector2.new(pX + 8, pY + 6)
                            item.titleText.Visible = true
                        end

                        if item.descText then
                            item.descText.Position = Vector2.new(pX + 8, pY + 22)
                            item.descText.Visible = true
                        end

                    elseif item.type == "divider" then
                        if item.line then
                            item.line.From = Vector2.new(contentLeft + 8, itemY + itemHeight / 2)
                            item.line.To = Vector2.new(contentLeft + contentWidth - 8, itemY + itemHeight / 2)
                            item.line.Visible = true
                        end
                    end
                else
                    hideItem(item)
                end

                cursorY = cursorY + itemHeight + 4
            end

            -- Card Background enclosing this section
            local cardH = (cursorY - cardContentStartY) + cardPadding
            if sec.cardBg then
                sec.cardBg.Position = Vector2.new(contentLeft, cardContentStartY - 4)
                sec.cardBg.Size = Vector2.new(contentWidth, cardH)
                sec.cardBg.Visible = inBounds
            end
            if sec.cardBorder then
                sec.cardBorder.Position = Vector2.new(contentLeft, cardContentStartY - 4)
                sec.cardBorder.Size = Vector2.new(contentWidth, cardH)
                sec.cardBorder.Visible = inBounds
            end

            cursorY = cursorY + 12
        end

        totalContentH = (cursorY - contentTop) + curTab.scrollOffset
        curTab.maxScroll = math.max(0, totalContentH - contentMaxHeight)
    end
end

-- ============================================================
--   CLEANUP & UNLOAD
-- ============================================================
function DrawingUI:Destroy()
    if not self.running then return end
    self.running = false
    self.visible = false

    for _, conn in ipairs(self.connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(self.connections)

    for _, cb in ipairs(self._unloadCallbacks) do
        pcall(cb)
    end
    table.clear(self._unloadCallbacks)

    for _, d in pairs(self.drawings) do
        removeObj(d)
    end
    table.clear(self.drawings)

    for _, tab in ipairs(self.tabs) do
        removeObj(tab.tabBtn)
        removeObj(tab.tabBar)
        removeObj(tab.tabText)
        for _, sec in ipairs(tab.sections) do
            removeObj(sec.titleDrawing)
            removeObj(sec.cardBg)
            removeObj(sec.cardBorder)
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
