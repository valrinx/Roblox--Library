-- ============================================================
--   RAVEN HUB  |  100% Drawing API Menu Engine v1.2.0
--   Anti-Cheat Ghost Architecture (Zero ScreenGui / Zero Instances)
--   BAC / Frog Anti-Cheat Compliant (100% Immune to Object Injection)
-- ============================================================

local DrawingUI = {}
DrawingUI.__index = DrawingUI
DrawingUI.Flags = {}

local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local StarterGui       = game:GetService("StarterGui")

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

local function sanitizeText(str)
    if type(str) ~= "string" then return tostring(str or "") end
    -- Strip 4-byte emojis and unsupported glyphs that break Drawing API
    local clean = str:gsub("[ð-ô][€-¿][€-¿][€-¿]", "")
    clean = clean:gsub("[â][š-Ÿ][€-¿]", "")
    clean = clean:gsub("[â][­-¯][€-¿]", "")
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
--   WINDOW CONSTRUCTOR
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
    self.subtitle = sanitizeText(tostring(config.LoadingSubtitle or config.Subtitle or "Ghost Architecture (100% Drawing)"))
    self.toggleKey = config.Keybind or config.ToggleKey or Enum.KeyCode.RightShift

    self.visible = true
    self.running = true
    self.tabs = {}
    self.activeTabIndex = 1

    -- Window Layout Parameters
    self.pos = config.Position or Vector2.new(50, 50)
    self.size = config.Size or Vector2.new(530, 440)
    self.headerHeight = 38
    self.tabBarHeight = 30

    -- Stealth Dark Theme
    self.theme = {
        bg = Color3.fromRGB(18, 19, 23),
        bgHeader = Color3.fromRGB(24, 26, 31),
        bgTabs = Color3.fromRGB(21, 22, 27),
        border = Color3.fromRGB(44, 47, 56),
        borderHighlight = Color3.fromRGB(0, 170, 255),
        title = Color3.fromRGB(255, 255, 255),
        subtitle = Color3.fromRGB(135, 140, 155),
        tabInactive = Color3.fromRGB(130, 135, 145),
        tabActive = Color3.fromRGB(0, 190, 255),
        sectionTitle = Color3.fromRGB(0, 170, 255),
        text = Color3.fromRGB(225, 230, 240),
        textMuted = Color3.fromRGB(120, 125, 140),
        controlBg = Color3.fromRGB(27, 29, 36),
        controlBorder = Color3.fromRGB(48, 52, 62),
        toggleActive = Color3.fromRGB(0, 210, 120),
        toggleInactive = Color3.fromRGB(210, 55, 60),
        sliderBar = Color3.fromRGB(0, 170, 255),
        accent = Color3.fromRGB(0, 170, 255),
    }

    -- Root Drawing Primitives
    self.drawings = {}

    self.drawings.bg = safeDrawing("Square")
    if self.drawings.bg then
        self.drawings.bg.Filled = true
        self.drawings.bg.Color = self.theme.bg
        self.drawings.bg.Thickness = 1
        self.drawings.bg.Visible = false
    end

    self.drawings.border = safeDrawing("Square")
    if self.drawings.border then
        self.drawings.border.Filled = false
        self.drawings.border.Color = self.theme.border
        self.drawings.border.Thickness = 1
        self.drawings.border.Visible = false
    end

    self.drawings.header = safeDrawing("Square")
    if self.drawings.header then
        self.drawings.header.Filled = true
        self.drawings.header.Color = self.theme.bgHeader
        self.drawings.header.Thickness = 1
        self.drawings.header.Visible = false
    end

    self.drawings.title = safeDrawing("Text")
    if self.drawings.title then
        self.drawings.title.Size = 14
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

    self.drawings.tabBar = safeDrawing("Square")
    if self.drawings.tabBar then
        self.drawings.tabBar.Filled = true
        self.drawings.tabBar.Color = self.theme.bgTabs
        self.drawings.tabBar.Thickness = 1
        self.drawings.tabBar.Visible = false
    end

    self.drawings.hint = safeDrawing("Text")
    if self.drawings.hint then
        self.drawings.hint.Size = 11
        self.drawings.hint.Outline = true
        self.drawings.hint.OutlineColor = Color3.fromRGB(0, 0, 0)
        self.drawings.hint.Color = self.theme.textMuted
        self.drawings.hint.Text = "[RShift] Hide"
        self.drawings.hint.Visible = false
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
--   TAB & SECTION ARCHITECTURE
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
        tabBtn = safeDrawing("Text"),
        tabLine = safeDrawing("Line"),
    }, TabMethods)

    if tab.tabBtn then
        tab.tabBtn.Size = 12
        tab.tabBtn.Outline = true
        tab.tabBtn.OutlineColor = Color3.fromRGB(0, 0, 0)
        tab.tabBtn.Text = tab.name
        tab.tabBtn.Visible = false
    end

    if tab.tabLine then
        tab.tabLine.Thickness = 2
        tab.tabLine.Color = self.theme.tabActive
        tab.tabLine.Visible = false
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
        lineDrawing = safeDrawing("Line"),
    }, SectionMethods)

    if sec.titleDrawing then
        sec.titleDrawing.Size = 11
        sec.titleDrawing.Outline = true
        sec.titleDrawing.OutlineColor = Color3.fromRGB(0, 0, 0)
        sec.titleDrawing.Color = self.window.theme.sectionTitle
        sec.titleDrawing.Text = string.upper(sec.name)
        sec.titleDrawing.Visible = false
    end

    if sec.lineDrawing then
        sec.lineDrawing.Thickness = 1
        sec.lineDrawing.Color = self.window.theme.border
        sec.lineDrawing.Visible = false
    end

    self._currentSection = sec
    table.insert(self.sections, sec)
    return sec
end

-- ============================================================
--   SECTION CONTROLS
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
        box = safeDrawing("Square"),
        boxCheck = safeDrawing("Square"),
        statusText = safeDrawing("Text"),
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

    if item.boxCheck then
        item.boxCheck.Thickness = 1
        item.boxCheck.Filled = true
        item.boxCheck.Visible = false
    end

    if item.statusText then
        item.statusText.Size = 11
        item.statusText.Outline = true
        item.statusText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.statusText.Visible = false
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
        valText = safeDrawing("Text"),
        barBg = safeDrawing("Square"),
        barFill = safeDrawing("Square"),
    }

    if item.label then
        item.label.Size = 12
        item.label.Outline = true
        item.label.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.label.Color = tab.window.theme.text
        item.label.Text = item.name
        item.label.Visible = false
    end

    if item.valText then
        item.valText.Size = 11
        item.valText.Outline = true
        item.valText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.valText.Color = tab.window.theme.textMuted
        item.valText.Visible = false
    end

    if item.barBg then
        item.barBg.Thickness = 1
        item.barBg.Filled = true
        item.barBg.Color = tab.window.theme.controlBg
        item.barBg.Visible = false
    end

    if item.barFill then
        item.barFill.Thickness = 1
        item.barFill.Filled = true
        item.barFill.Color = tab.window.theme.sliderBar
        item.barFill.Visible = false
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
        label = safeDrawing("Text"),
        box = safeDrawing("Square"),
    }

    if item.box then
        item.box.Thickness = 1
        item.box.Filled = true
        item.box.Color = tab.window.theme.controlBg
        item.box.Visible = false
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
        titleText = safeDrawing("Text"),
        descText = safeDrawing("Text"),
    }

    if item.titleText then
        item.titleText.Size = 12
        item.titleText.Outline = true
        item.titleText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.titleText.Color = tab.window.theme.text
        item.titleText.Text = item.title
        item.titleText.Visible = false
    end

    if item.descText then
        item.descText.Size = 11
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
        item.line.Color = tab.window.theme.border
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

    if item.selectedText then
        item.selectedText.Size = 11
        item.selectedText.Outline = true
        item.selectedText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.selectedText.Color = tab.window.theme.textMuted
        item.selectedText.Text = item.selected
        item.selectedText.Visible = false
    end

    if item.arrow then
        item.arrow.Size = 11
        item.arrow.Outline = true
        item.arrow.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.arrow.Color = tab.window.theme.textMuted
        item.arrow.Text = ">"
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
            if #textVal > 18 then textVal = textVal:sub(1, 16) .. ".." end
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

    if item.keyText then
        item.keyText.Size = 11
        item.keyText.Outline = true
        item.keyText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.keyText.Color = tab.window.theme.textMuted
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
            item.keyText.Color = tab.window.theme.textMuted
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
        callback = cfg.Callback or function() end,
        flag = cfg.Flag,
        label = safeDrawing("Text"),
        box = safeDrawing("Square"),
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

    if item.inputText then
        item.inputText.Size = 11
        item.inputText.Outline = true
        item.inputText.OutlineColor = Color3.fromRGB(0, 0, 0)
        item.inputText.Color = tab.window.theme.textMuted
        item.inputText.Text = #item.text > 0 and item.text or item.placeholder
        item.inputText.Visible = false
    end

    function item:Set(val)
        item.text = sanitizeText(tostring(val or ""))
        if item.inputText then
            item.inputText.Text = #item.text > 0 and item.text or item.placeholder
        end
        if item.flag then
            DrawingUI.Flags[item.flag] = item.text
        end
        pcall(item.callback, item.text)
    end

    if item.flag then
        DrawingUI.Flags[item.flag] = item.text
    end

    table.insert(self.items, item)
    return item
end

-- ============================================================
--   INPUT & INTERACTION HANDLERS
-- ============================================================
function DrawingUI:InitInputHandlers()
    local conn1 = UserInputService.InputBegan:Connect(function(input, gpe)
        if self.activeKeybindListener then
            if input.UserInputType == Enum.UserInputType.Keyboard then
                local listener = self.activeKeybindListener
                self.activeKeybindListener = nil
                listener:Set(input.KeyCode.Name)
                return
            end
        end

        if input.KeyCode == self.toggleKey then
            self.visible = not self.visible
            return
        end

        if not self.visible then return end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local mouse = UserInputService:GetMouseLocation()

            -- 1. Window Dragging
            if pointInBox(mouse, self.pos, Vector2.new(self.size.X, self.headerHeight)) then
                self.dragging = true
                self.dragStart = mouse
                self.posStart = self.pos
                return
            end

            -- 2. Tab Bar Switching
            local tabY = self.pos.Y + self.headerHeight
            if pointInBox(mouse, Vector2.new(self.pos.X, tabY), Vector2.new(self.size.X, self.tabBarHeight)) then
                local tabCount = math.max(#self.tabs, 1)
                local tabWidth = math.floor(self.size.X / tabCount)
                for i, tab in ipairs(self.tabs) do
                    local tX = self.pos.X + (i - 1) * tabWidth
                    if pointInBox(mouse, Vector2.new(tX, tabY), Vector2.new(tabWidth, self.tabBarHeight)) then
                        self.activeTabIndex = i
                        return
                    end
                end
            end

            -- 3. Active Tab Controls
            local activeTab = self.tabs[self.activeTabIndex]
            if activeTab then
                for _, sec in ipairs(activeTab.sections) do
                    for _, item in ipairs(sec.items) do
                        if item.hitBox and pointInBox(mouse, item.hitBox.pos, item.hitBox.size) then
                            if item.type == "toggle" then
                                item:Set(not item.value)
                                return
                            elseif item.type == "button" then
                                item:Click()
                                return
                            elseif item.type == "dropdown" then
                                item:CycleNext()
                                return
                            elseif item.type == "keybind" then
                                item.listening = true
                                if item.keyText then
                                    item.keyText.Text = "[...]"
                                    item.keyText.Color = self.theme.accent
                                end
                                self.activeKeybindListener = item
                                return
                            elseif item.type == "slider" then
                                self.activeSlider = item
                                local relX = math.clamp((mouse.X - item.hitBox.pos.X) / item.hitBox.size.X, 0, 1)
                                local rawVal = item.min + (item.max - item.min) * relX
                                local steppedVal = math.floor(rawVal / item.increment + 0.5) * item.increment
                                item:Set(steppedVal)
                                return
                            end
                        end
                    end
                end
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
        if input.UserInputType == Enum.UserInputType.MouseWheel then
            local mouse = UserInputService:GetMouseLocation()
            if pointInBox(mouse, self.pos, self.size) then
                local activeTab = self.tabs[self.activeTabIndex]
                if activeTab then
                    local newOffset = (activeTab.scrollOffset or 0) - (input.Position.Z * 25)
                    activeTab.scrollOffset = math.clamp(newOffset, 0, activeTab.maxScroll or 0)
                end
            end
        end
    end)

    local conn4 = RunService.RenderStepped:Connect(function()
        if not self.running then return end

        if self.dragging then
            local mouse = UserInputService:GetMouseLocation()
            local delta = mouse - self.dragStart
            self.pos = self.posStart + delta
        end

        if self.activeSlider then
            local mouse = UserInputService:GetMouseLocation()
            local item = self.activeSlider
            if item.hitBox then
                local relX = math.clamp((mouse.X - item.hitBox.pos.X) / item.hitBox.size.X, 0, 1)
                local rawVal = item.min + (item.max - item.min) * relX
                local steppedVal = math.floor(rawVal / item.increment + 0.5) * item.increment
                item:Set(steppedVal)
            end
        end

        self:Render()
    end)

    table.insert(self.connections, conn1)
    table.insert(self.connections, conn2)
    table.insert(self.connections, conn3)
    table.insert(self.connections, conn4)
end

-- ============================================================
--   MAIN RENDER LOOP
-- ============================================================
function DrawingUI:Render()
    -- 0. Handle Hidden Window
    if not self.visible then
        for _, d in pairs(self.drawings) do
            setObjVisible(d, false)
        end
        for _, tab in ipairs(self.tabs) do
            setObjVisible(tab.tabBtn, false)
            setObjVisible(tab.tabLine, false)
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.titleDrawing, false)
                setObjVisible(sec.lineDrawing, false)
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
        return
    end

    -- 1. Window Frame & Header
    if self.drawings.bg then
        self.drawings.bg.Position = self.pos
        self.drawings.bg.Size = self.size
        self.drawings.bg.Visible = true
    end

    if self.drawings.border then
        self.drawings.border.Position = self.pos
        self.drawings.border.Size = self.size
        self.drawings.border.Visible = true
    end

    if self.drawings.header then
        self.drawings.header.Position = self.pos
        self.drawings.header.Size = Vector2.new(self.size.X, self.headerHeight)
        self.drawings.header.Visible = true
    end

    if self.drawings.title then
        self.drawings.title.Position = self.pos + Vector2.new(14, 6)
        self.drawings.title.Text = self.title
        self.drawings.title.Visible = true
    end

    if self.drawings.subtitle then
        self.drawings.subtitle.Position = self.pos + Vector2.new(14, 21)
        self.drawings.subtitle.Text = self.subtitle
        self.drawings.subtitle.Visible = true
    end

    if self.drawings.hint then
        self.drawings.hint.Position = self.pos + Vector2.new(self.size.X - 100, 13)
        self.drawings.hint.Visible = true
    end

    -- 2. Tab Bar
    local tabY = self.pos.Y + self.headerHeight
    if self.drawings.tabBar then
        self.drawings.tabBar.Position = Vector2.new(self.pos.X, tabY)
        self.drawings.tabBar.Size = Vector2.new(self.size.X, self.tabBarHeight)
        self.drawings.tabBar.Visible = true
    end

    local tabCount = math.max(#self.tabs, 1)
    local tabWidth = math.floor(self.size.X / tabCount)

    for i, tab in ipairs(self.tabs) do
        local isCurrent = (i == self.activeTabIndex)
        local tX = self.pos.X + (i - 1) * tabWidth

        if tab.tabBtn then
            tab.tabBtn.Position = Vector2.new(tX + tabWidth / 2, tabY + 7)
            tab.tabBtn.Center = true
            tab.tabBtn.Color = isCurrent and self.theme.tabActive or self.theme.tabInactive
            tab.tabBtn.Visible = true
        end

        if tab.tabLine then
            tab.tabLine.From = Vector2.new(tX, tabY + self.tabBarHeight - 1)
            tab.tabLine.To = Vector2.new(tX + tabWidth, tabY + self.tabBarHeight - 1)
            tab.tabLine.Color = isCurrent and self.theme.tabActive or self.theme.border
            tab.tabLine.Visible = true
        end
    end

    -- 3. Body Viewport Clipping Bounds
    local clipTop = tabY + self.tabBarHeight
    local clipBottom = self.pos.Y + self.size.Y - 6
    local marginX = 16
    local contentWidth = self.size.X - (marginX * 2)

    for i, tab in ipairs(self.tabs) do
        local isCurrent = (i == self.activeTabIndex)
        if isCurrent then
            local cursorY = clipTop + 10 - (tab.scrollOffset or 0)
            local startY = cursorY

            for _, sec in ipairs(tab.sections) do
                local secVisible = (cursorY >= clipTop - 15 and cursorY <= clipBottom - 10)

                if sec.titleDrawing then
                    sec.titleDrawing.Position = Vector2.new(self.pos.X + marginX, cursorY)
                    sec.titleDrawing.Visible = secVisible
                end

                if sec.lineDrawing then
                    sec.lineDrawing.From = Vector2.new(self.pos.X + marginX + 110, cursorY + 6)
                    sec.lineDrawing.To = Vector2.new(self.pos.X + marginX + contentWidth, cursorY + 6)
                    sec.lineDrawing.Visible = secVisible
                end

                cursorY = cursorY + 18

                for _, item in ipairs(sec.items) do
                    local itemH = 22
                    if item.type == "slider" then
                        itemH = 32
                    elseif item.type == "paragraph" then
                        itemH = (item.content and #item.content > 0) and 34 or 18
                    elseif item.type == "dropdown" then
                        itemH = 24
                    elseif item.type == "divider" then
                        itemH = 8
                    end

                    local isItemInView = (cursorY >= clipTop - 5 and (cursorY + itemH) <= clipBottom + 10)

                    if item.type == "toggle" then
                        local toggleBoxSize = 14
                        local boxX = self.pos.X + marginX + contentWidth - toggleBoxSize
                        local boxY = cursorY + 4

                        if item.label then
                            item.label.Position = Vector2.new(self.pos.X + marginX, cursorY + 4)
                            item.label.Visible = isItemInView
                        end

                        if item.box then
                            item.box.Position = Vector2.new(boxX, boxY)
                            item.box.Size = Vector2.new(toggleBoxSize, toggleBoxSize)
                            item.box.Visible = isItemInView
                        end

                        if item.boxCheck then
                            item.boxCheck.Position = Vector2.new(boxX + 2, boxY + 2)
                            item.boxCheck.Size = Vector2.new(toggleBoxSize - 4, toggleBoxSize - 4)
                            item.boxCheck.Color = item.value and self.theme.toggleActive or self.theme.toggleInactive
                            item.boxCheck.Visible = isItemInView
                        end

                        if item.statusText then
                            item.statusText.Text = item.value and "[ON]" or "[OFF]"
                            item.statusText.Color = item.value and self.theme.toggleActive or self.theme.toggleInactive
                            item.statusText.Position = Vector2.new(boxX - 34, cursorY + 4)
                            item.statusText.Visible = isItemInView
                        end

                        if isItemInView then
                            item.hitBox = {
                                pos = Vector2.new(self.pos.X + marginX, cursorY),
                                size = Vector2.new(contentWidth, itemH)
                            }
                        else
                            item.hitBox = nil
                        end

                        cursorY = cursorY + itemH + 2

                    elseif item.type == "slider" then
                        local sliderH = 6
                        local sliderW = contentWidth
                        local sX = self.pos.X + marginX
                        local sY = cursorY + 18

                        if item.label then
                            item.label.Position = Vector2.new(sX, cursorY + 2)
                            item.label.Visible = isItemInView
                        end

                        if item.valText then
                            item.valText.Text = tostring(item.value) .. item.suffix
                            item.valText.Position = Vector2.new(sX + contentWidth - 60, cursorY + 2)
                            item.valText.Visible = isItemInView
                        end

                        if item.barBg then
                            item.barBg.Position = Vector2.new(sX, sY)
                            item.barBg.Size = Vector2.new(sliderW, sliderH)
                            item.barBg.Visible = isItemInView
                        end

                        if item.barFill then
                            local ratio = math.clamp((item.value - item.min) / math.max(item.max - item.min, 1), 0, 1)
                            item.barFill.Position = Vector2.new(sX, sY)
                            item.barFill.Size = Vector2.new(math.floor(sliderW * ratio), sliderH)
                            item.barFill.Visible = isItemInView
                        end

                        if isItemInView then
                            item.hitBox = {
                                pos = Vector2.new(sX, sY - 4),
                                size = Vector2.new(sliderW, sliderH + 8)
                            }
                        else
                            item.hitBox = nil
                        end

                        cursorY = cursorY + itemH + 2

                    elseif item.type == "dropdown" then
                        local dropW = 160
                        local dropX = self.pos.X + marginX + contentWidth - dropW
                        local dropY = cursorY + 2
                        local dropH = 20

                        if item.label then
                            item.label.Position = Vector2.new(self.pos.X + marginX, cursorY + 4)
                            item.label.Visible = isItemInView
                        end

                        if item.box then
                            item.box.Position = Vector2.new(dropX, dropY)
                            item.box.Size = Vector2.new(dropW, dropH)
                            item.box.Visible = isItemInView
                        end

                        if item.selectedText then
                            local textVal = item.selected
                            if #textVal > 18 then textVal = textVal:sub(1, 16) .. ".." end
                            item.selectedText.Text = textVal
                            item.selectedText.Position = Vector2.new(dropX + 6, dropY + 3)
                            item.selectedText.Visible = isItemInView
                        end

                        if item.arrow then
                            item.arrow.Position = Vector2.new(dropX + dropW - 14, dropY + 3)
                            item.arrow.Visible = isItemInView
                        end

                        if isItemInView then
                            item.hitBox = {
                                pos = Vector2.new(self.pos.X + marginX, cursorY),
                                size = Vector2.new(contentWidth, itemH)
                            }
                        else
                            item.hitBox = nil
                        end

                        cursorY = cursorY + itemH + 2

                    elseif item.type == "keybind" then
                        local kbW = 90
                        local kbX = self.pos.X + marginX + contentWidth - kbW
                        local kbY = cursorY + 2
                        local kbH = 20

                        if item.label then
                            item.label.Position = Vector2.new(self.pos.X + marginX, cursorY + 4)
                            item.label.Visible = isItemInView
                        end

                        if item.box then
                            item.box.Position = Vector2.new(kbX, kbY)
                            item.box.Size = Vector2.new(kbW, kbH)
                            item.box.Visible = isItemInView
                        end

                        if item.keyText then
                            item.keyText.Position = Vector2.new(kbX + 6, kbY + 3)
                            item.keyText.Visible = isItemInView
                        end

                        if isItemInView then
                            item.hitBox = {
                                pos = Vector2.new(self.pos.X + marginX, cursorY),
                                size = Vector2.new(contentWidth, itemH)
                            }
                        else
                            item.hitBox = nil
                        end

                        cursorY = cursorY + itemH + 2

                    elseif item.type == "input" then
                        local inW = 140
                        local inX = self.pos.X + marginX + contentWidth - inW
                        local inY = cursorY + 2
                        local inH = 20

                        if item.label then
                            item.label.Position = Vector2.new(self.pos.X + marginX, cursorY + 4)
                            item.label.Visible = isItemInView
                        end

                        if item.box then
                            item.box.Position = Vector2.new(inX, inY)
                            item.box.Size = Vector2.new(inW, inH)
                            item.box.Visible = isItemInView
                        end

                        if item.inputText then
                            item.inputText.Position = Vector2.new(inX + 6, inY + 3)
                            item.inputText.Visible = isItemInView
                        end

                        if isItemInView then
                            item.hitBox = {
                                pos = Vector2.new(self.pos.X + marginX, cursorY),
                                size = Vector2.new(contentWidth, itemH)
                            }
                        else
                            item.hitBox = nil
                        end

                        cursorY = cursorY + itemH + 2

                    elseif item.type == "paragraph" then
                        if item.titleText then
                            item.titleText.Position = Vector2.new(self.pos.X + marginX, cursorY + 2)
                            item.titleText.Visible = isItemInView
                        end

                        if item.descText then
                            if item.content and #item.content > 0 then
                                item.descText.Position = Vector2.new(self.pos.X + marginX, cursorY + 18)
                                item.descText.Visible = isItemInView
                            else
                                item.descText.Visible = false
                            end
                        end

                        cursorY = cursorY + itemH + 2

                    elseif item.type == "button" then
                        local bX = self.pos.X + marginX
                        local bY = cursorY + 2
                        local bW = contentWidth
                        local bH = 22

                        if item.box then
                            item.box.Position = Vector2.new(bX, bY)
                            item.box.Size = Vector2.new(bW, bH)
                            item.box.Visible = isItemInView
                        end

                        if item.label then
                            item.label.Position = Vector2.new(bX + bW / 2, bY + 4)
                            item.label.Visible = isItemInView
                        end

                        if isItemInView then
                            item.hitBox = {
                                pos = Vector2.new(bX, bY),
                                size = Vector2.new(bW, bH)
                            }
                        else
                            item.hitBox = nil
                        end

                        cursorY = cursorY + itemH + 2

                    elseif item.type == "divider" then
                        if item.line then
                            item.line.From = Vector2.new(self.pos.X + marginX, cursorY + 4)
                            item.line.To = Vector2.new(self.pos.X + marginX + contentWidth, cursorY + 4)
                            item.line.Visible = isItemInView
                        end
                        cursorY = cursorY + itemH
                    end
                end

                cursorY = cursorY + 6
            end

            local totalHeight = cursorY - startY
            local viewportH = clipBottom - clipTop
            tab.maxScroll = math.max(0, totalHeight - viewportH + 20)

        else
            -- Non-active tab: ONLY hide sections and control items
            -- DO NOT hide tab.tabBtn or tab.tabLine!
            if sec and sec.titleDrawing then sec.titleDrawing.Visible = false end
            if sec and sec.lineDrawing then sec.lineDrawing.Visible = false end
            for _, sec in ipairs(tab.sections) do
                setObjVisible(sec.titleDrawing, false)
                setObjVisible(sec.lineDrawing, false)
                for _, item in ipairs(sec.items) do
                    hideItem(item)
                end
            end
        end
    end
end

-- ============================================================
--   TEARDOWN & CLEANUP
-- ============================================================
function DrawingUI:Destroy()
    self.running = false

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

    for _, tab in ipairs(self.tabs) do
        removeObj(tab.tabBtn)
        removeObj(tab.tabLine)
        for _, sec in ipairs(tab.sections) do
            removeObj(sec.titleDrawing)
            removeObj(sec.lineDrawing)
            for _, item in ipairs(sec.items) do
                removeItem(item)
            end
        end
    end
    table.clear(self.tabs)
end

return DrawingUI
