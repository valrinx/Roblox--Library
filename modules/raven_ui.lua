--[[
    RAVEN UI Library
    Original native Roblox interface for RAVEN HUB.
    API-compatible with the Rayfield controls currently used by this repository.
]]

local Raven = {
    Version = "1.0.1",
    Flags = {},
}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LOCAL_PLAYER = Players.LocalPlayer
local GUI_NAME = "RavenUI"

local THEME = {
    Background = Color3.fromRGB(8, 10, 13),
    Surface = Color3.fromRGB(13, 17, 21),
    SurfaceRaised = Color3.fromRGB(17, 22, 27),
    SurfaceHover = Color3.fromRGB(22, 28, 34),
    Border = Color3.fromRGB(37, 44, 52),
    BorderSoft = Color3.fromRGB(28, 34, 40),
    Text = Color3.fromRGB(242, 245, 247),
    Muted = Color3.fromRGB(135, 145, 156),
    Dim = Color3.fromRGB(92, 101, 112),
    Accent = Color3.fromRGB(183, 255, 60),
    AccentDark = Color3.fromRGB(94, 132, 24),
    Cyan = Color3.fromRGB(63, 190, 239),
    Danger = Color3.fromRGB(255, 92, 92),
}

local activeWindow = nil
local connections = {}
local keybinds = {}
local configState = {
    enabled = false,
    folder = "RAVENHUB",
    file = "HubConfig",
    values = {},
}

local function create(className, properties, children)
    local instance = Instance.new(className)
    local requestedParent = properties and properties.Parent
    for property, value in pairs(properties or {}) do
        if property ~= "Parent" then
            local ok, err = pcall(function()
                instance[property] = value
            end)
            if not ok then
                warn(string.format(
                    "[RAVEN UI] Skipped unsupported %s.%s: %s",
                    className,
                    tostring(property),
                    tostring(err)
                ))
            end
        end
    end
    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end
    if requestedParent then
        instance.Parent = requestedParent
    end
    return instance
end

local function corner(radius)
    return create("UICorner", {CornerRadius = UDim.new(0, radius)})
end

local function stroke(color, transparency, thickness)
    return create("UIStroke", {
        Color = color or THEME.Border,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function padding(left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or left or 0),
        PaddingBottom = UDim.new(0, bottom or top or left or 0),
    })
end

local function label(properties)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        TextColor3 = THEME.Text,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }
    for key, value in pairs(properties or {}) do
        defaults[key] = value
    end
    return create("TextLabel", defaults)
end

local function button(properties)
    local defaults = {
        AutoButtonColor = false,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        Text = "",
        TextColor3 = THEME.Text,
        TextSize = 14,
    }
    for key, value in pairs(properties or {}) do
        defaults[key] = value
    end
    return create("TextButton", defaults)
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function tween(instance, duration, properties)
    local info = TweenInfo.new(duration or 0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
    local animation = TweenService:Create(instance, info, properties)
    animation:Play()
    return animation
end

local function safeCallback(callback, ...)
    if type(callback) ~= "function" then
        return
    end
    local ok, err = pcall(callback, ...)
    if not ok then
        warn("[RAVEN UI] Callback failed: " .. tostring(err))
    end
end

local function formatClock(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remaining = math.floor(seconds % 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end
    return string.format("%02dm %02ds", minutes, remaining)
end

local function getGuiParents()
    local parents = {}
    local seen = {}
    local function add(candidate)
        if candidate and not seen[candidate] then
            seen[candidate] = true
            table.insert(parents, candidate)
        end
    end

    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and result then
            add(result)
        end
    end

    if LOCAL_PLAYER then
        local ok, playerGui = pcall(function()
            return LOCAL_PLAYER:FindFirstChildOfClass("PlayerGui")
                or LOCAL_PLAYER:WaitForChild("PlayerGui", 3)
        end)
        if ok then
            add(playerGui)
        end
    end

    add(CoreGui)
    return parents
end

local function destroyExistingGuis()
    for _, parent in ipairs(getGuiParents()) do
        pcall(function()
            local existing = parent:FindFirstChild(GUI_NAME)
            if existing then
                existing:Destroy()
            end
        end)
    end
end

local function mountScreenGui(screenGui)
    local failures = {}
    for _, parent in ipairs(getGuiParents()) do
        local ok, err = pcall(function()
            screenGui.Parent = parent
        end)
        if ok and screenGui.Parent == parent then
            return parent
        end
        table.insert(failures, tostring(err))
    end
    error("Unable to mount ScreenGui: " .. table.concat(failures, " | "))
end

local function canUseFiles()
    return type(isfolder) == "function"
        and type(makefolder) == "function"
        and type(isfile) == "function"
        and type(readfile) == "function"
        and type(writefile) == "function"
end

local function configPath()
    return configState.folder .. "/" .. configState.file .. ".json"
end

local function loadConfig()
    if not configState.enabled or not canUseFiles() then
        return
    end
    pcall(function()
        if not isfolder(configState.folder) then
            makefolder(configState.folder)
        end
        if isfile(configPath()) then
            local decoded = HttpService:JSONDecode(readfile(configPath()))
            if type(decoded) == "table" then
                configState.values = decoded
            end
        end
    end)
end

local function saveConfig()
    if not configState.enabled or not canUseFiles() then
        return
    end
    pcall(function()
        if not isfolder(configState.folder) then
            makefolder(configState.folder)
        end
        writefile(configPath(), HttpService:JSONEncode(configState.values))
    end)
end

local function storedValue(flag, fallback)
    if flag and configState.values[flag] ~= nil then
        return configState.values[flag]
    end
    return fallback
end

local function remember(flag, value)
    if not flag then
        return
    end
    Raven.Flags[flag] = value
    configState.values[flag] = value
    saveConfig()
end

local function normalizeOptions(options)
    local result = {}
    for _, value in ipairs(options or {}) do
        table.insert(result, tostring(value))
    end
    return result
end

local function normalizeSelection(value, fallback)
    if type(value) == "table" then
        local result = {}
        for _, item in ipairs(value) do
            table.insert(result, tostring(item))
        end
        return result
    end
    if value ~= nil then
        return {tostring(value)}
    end
    return fallback or {}
end

local function keyCodeFromName(name)
    local normalized = tostring(name or "Unknown"):gsub("Enum.KeyCode.", "")
    local ok, result = pcall(function()
        return Enum.KeyCode[normalized]
    end)
    if ok and result then
        return result
    end
    return Enum.KeyCode.Unknown
end

local function shortName(name)
    local words = {}
    for word in tostring(name):gmatch("[%w]+") do
        table.insert(words, word)
    end
    if #words == 0 then
        return "UI"
    end
    if #words == 1 then
        return string.upper(words[1]:sub(1, 2))
    end
    return string.upper(words[1]:sub(1, 1) .. words[2]:sub(1, 1))
end

local function addHover(target, surface, normalColor, hoverColor)
    connect(target.MouseEnter, function()
        tween(surface, 0.12, {BackgroundColor3 = hoverColor or THEME.SurfaceHover})
    end)
    connect(target.MouseLeave, function()
        tween(surface, 0.12, {BackgroundColor3 = normalColor or THEME.SurfaceRaised})
    end)
end

local WindowMethods = {}
local TabMethods = {}

local function updateScale(window)
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    local viewport = camera.ViewportSize
    local scale = math.min((viewport.X - 24) / 1120, (viewport.Y - 24) / 700, 1)
    window._scale.Scale = math.max(scale, 0.56)
end

local function makeDraggable(window, handle)
    local dragging = false
    local dragStart = nil
    local startPosition = nil
    local activeInput = nil

    connect(handle.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = window._root.Position
            activeInput = input
        end
    end)

    connect(UserInputService.InputChanged, function(input)
        if not dragging or (input ~= activeInput and input.UserInputType ~= Enum.UserInputType.MouseMovement) then
            return
        end
        local delta = input.Position - dragStart
        window._root.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end)

    connect(UserInputService.InputEnded, function(input)
        if input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            activeInput = nil
        end
    end)
end

local function makeLogo(parent)
    local holder = create("Frame", {
        Name = "Logo",
        Parent = parent,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(24, 17),
        Size = UDim2.fromOffset(72, 38),
    })
    local leftWing = create("Frame", {
        Parent = holder,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = THEME.Text,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(25, 19),
        Rotation = 45,
        Size = UDim2.fromOffset(22, 22),
    }, {corner(3)})
    create("Frame", {
        Parent = leftWing,
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(8, -4),
        Rotation = -20,
        Size = UDim2.fromOffset(18, 28),
    })
    local rightWing = create("Frame", {
        Parent = holder,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(47, 19),
        Rotation = 45,
        Size = UDim2.fromOffset(22, 22),
    }, {corner(3)})
    create("Frame", {
        Parent = rightWing,
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(-4, 8),
        Rotation = 20,
        Size = UDim2.fromOffset(28, 18),
    })
end

local function createMetricCard(parent, position, size, title, accent)
    local card = create("Frame", {
        Parent = parent,
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        Position = position,
        Size = size,
    }, {corner(8), stroke(THEME.Border, 0.08, 1)})
    create("Frame", {
        Parent = card,
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 2),
    }, {corner(8)})
    label({
        Parent = card,
        Position = UDim2.fromOffset(18, 14),
        Size = UDim2.new(1, -36, 0, 20),
        Font = Enum.Font.GothamBold,
        Text = string.upper(title),
        TextColor3 = THEME.Muted,
        TextSize = 12,
    })
    return card
end

function WindowMethods:_addActivity(text, kind)
    if not self._activityList then
        return
    end
    local color = kind == "info" and THEME.Cyan or kind == "danger" and THEME.Danger or THEME.Accent
    local row = create("Frame", {
        Parent = self._activityList,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = -math.floor(os.clock() * 1000),
        Size = UDim2.new(1, 0, 0, 48),
    })
    create("Frame", {
        Parent = row,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(16, 24),
        Size = UDim2.fromOffset(9, 9),
    }, {corner(9)})
    label({
        Parent = row,
        Position = UDim2.fromOffset(36, 0),
        Size = UDim2.new(1, -116, 1, 0),
        Text = tostring(text),
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    label({
        Parent = row,
        Position = UDim2.new(1, -78, 0, 0),
        Size = UDim2.fromOffset(66, 48),
        Text = os.date("%H:%M:%S"),
        TextColor3 = THEME.Dim,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    create("Frame", {
        Parent = row,
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = THEME.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
    })

    local rows = {}
    for _, child in ipairs(self._activityList:GetChildren()) do
        if child:IsA("Frame") then
            table.insert(rows, child)
        end
    end
    table.sort(rows, function(a, b)
        return a.LayoutOrder < b.LayoutOrder
    end)
    for index = 6, #rows do
        rows[index]:Destroy()
    end
end

function WindowMethods:_closePopup()
    if self._popup then
        self._popup:Destroy()
        self._popup = nil
    end
end

function WindowMethods:_showToast(title, content, duration, kind)
    local toast = create("Frame", {
        Parent = self._toastHolder,
        BackgroundColor3 = THEME.SurfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 64),
        BackgroundTransparency = 1,
    }, {corner(7), stroke(kind == "danger" and THEME.Danger or THEME.Accent, 0.15, 1)})
    local indicator = create("Frame", {
        Parent = toast,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = kind == "danger" and THEME.Danger or THEME.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 32),
        Size = UDim2.fromOffset(20, 20),
    }, {corner(4)})
    label({
        Parent = indicator,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamBold,
        Text = kind == "danger" and "!" or "✓",
        TextColor3 = THEME.Background,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    label({
        Parent = toast,
        Position = UDim2.fromOffset(44, 8),
        Size = UDim2.new(1, -56, 0, 20),
        Font = Enum.Font.GothamBold,
        Text = tostring(title or "RAVEN UI"),
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    label({
        Parent = toast,
        Position = UDim2.fromOffset(44, 28),
        Size = UDim2.new(1, -56, 0, 28),
        Text = tostring(content or ""),
        TextColor3 = THEME.Muted,
        TextSize = 11,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    tween(toast, 0.18, {BackgroundTransparency = 0})
    self:_addActivity(content or title or "Notification", kind)
    task.delay(tonumber(duration) or 4, function()
        if toast and toast.Parent then
            tween(toast, 0.18, {BackgroundTransparency = 1})
            task.wait(0.2)
            if toast and toast.Parent then
                toast:Destroy()
            end
        end
    end)
end

function WindowMethods:_selectTab(tab)
    if self._activeTab == tab then
        return
    end
    self:_closePopup()
    if self._activeTab then
        self._activeTab._page.Visible = false
        tween(self._activeTab._nav, 0.12, {BackgroundColor3 = THEME.Background})
        self._activeTab._navText.TextColor3 = THEME.Muted
        self._activeTab._navIcon.TextColor3 = THEME.Muted
        self._activeTab._indicator.Visible = false
    end
    self._activeTab = tab
    tab._page.Visible = true
    tween(tab._nav, 0.12, {BackgroundColor3 = THEME.SurfaceHover})
    tab._navText.TextColor3 = THEME.Accent
    tab._navIcon.TextColor3 = THEME.Accent
    tab._indicator.Visible = true
    self._pageTitle.Text = string.upper(tab._name)
    self:_applySearch(self._search.Text)
end

function WindowMethods:_applySearch(query)
    local tab = self._activeTab
    if not tab then
        return
    end
    local needle = string.lower(tostring(query or ""))
    for _, section in ipairs(tab._sections) do
        local anyVisible = needle == "" or string.find(string.lower(section._name), needle, 1, true) ~= nil
        for _, entry in ipairs(section._entries) do
            local matches = needle == ""
                or string.find(string.lower(entry._searchText), needle, 1, true) ~= nil
                or string.find(string.lower(section._name), needle, 1, true) ~= nil
            entry._frame.Visible = matches
            anyVisible = anyVisible or matches
        end
        section._frame.Visible = anyVisible
    end
end

function WindowMethods:CreateTab(name, icon)
    local tab = setmetatable({
        _window = self,
        _name = tostring(name or "Tab"),
        _icon = icon,
        _sections = {},
        _currentSection = nil,
    }, {__index = TabMethods})

    local nav = button({
        Parent = self._navList,
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0,
        LayoutOrder = #self._tabs + 1,
        Size = UDim2.new(1, 0, 0, 64),
    })
    tab._nav = nav
    tab._indicator = create("Frame", {
        Parent = nav,
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 8),
        Size = UDim2.fromOffset(2, 48),
        Visible = false,
    }, {corner(2)})
    tab._navIcon = label({
        Parent = nav,
        Position = UDim2.fromOffset(14, 12),
        Size = UDim2.fromOffset(30, 40),
        Font = Enum.Font.GothamBold,
        Text = shortName(tab._name),
        TextColor3 = THEME.Muted,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    tab._navText = label({
        Parent = nav,
        Position = UDim2.fromOffset(52, 0),
        Size = UDim2.new(1, -58, 1, 0),
        Text = tab._name == "Home" and "Overview" or tab._name,
        TextColor3 = THEME.Muted,
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local page = create("ScrollingFrame", {
        Parent = self._pageHolder,
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = THEME.AccentDark,
        ScrollBarThickness = 3,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
    }, {
        padding(0, 8, 0, 12),
        create("UIListLayout", {
            Padding = UDim.new(0, 10),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    tab._page = page

    addHover(nav, nav, THEME.Background, THEME.SurfaceHover)
    connect(nav.MouseButton1Click, function()
        self:_selectTab(tab)
    end)
    table.insert(self._tabs, tab)
    if not self._activeTab then
        self:_selectTab(tab)
    end
    return tab
end

function WindowMethods:Destroy()
    Raven:Destroy()
end

function TabMethods:_ensureSection()
    if self._currentSection then
        return self._currentSection
    end
    return self:CreateSection("Controls")
end

function TabMethods:CreateSection(name)
    local section = {
        _name = tostring(name or "Section"),
        _entries = {},
    }
    local card = create("Frame", {
        Parent = self._page,
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        LayoutOrder = #self._sections + 1,
        Size = UDim2.new(1, 0, 0, 0),
    }, {
        corner(8),
        stroke(THEME.Border, 0.08, 1),
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
    section._frame = card
    label({
        Parent = card,
        BackgroundColor3 = THEME.Surface,
        BackgroundTransparency = 0,
        LayoutOrder = 0,
        Size = UDim2.new(1, 0, 0, 44),
        Font = Enum.Font.GothamBold,
        Text = "   " .. string.upper(section._name),
        TextColor3 = THEME.Muted,
        TextSize = 11,
    })
    table.insert(self._sections, section)
    self._currentSection = section
    return section
end

function TabMethods:_newEntry(name, height)
    local section = self:_ensureSection()
    local frame = create("Frame", {
        Parent = section._frame,
        BackgroundColor3 = THEME.SurfaceRaised,
        BorderSizePixel = 0,
        LayoutOrder = #section._entries + 1,
        Size = UDim2.new(1, 0, 0, height),
    })
    create("Frame", {
        Parent = frame,
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = THEME.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 16, 1, 0),
        Size = UDim2.new(1, -32, 0, 1),
    })
    local entry = {
        _frame = frame,
        _searchText = tostring(name or ""),
    }
    table.insert(section._entries, entry)
    return frame, entry
end

function TabMethods:CreateLabel(text)
    local frame, entry = self:_newEntry(text, 46)
    local textLabel = label({
        Parent = frame,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -36, 1, 0),
        Text = tostring(text or ""),
        TextColor3 = THEME.Muted,
        TextSize = 12,
        TextWrapped = true,
    })
    local element = {}
    function element:Set(value)
        textLabel.Text = tostring(value or "")
        entry._searchText = textLabel.Text
    end
    return element
end

function TabMethods:CreateButton(options)
    options = options or {}
    local name = tostring(options.Name or "Button")
    local frame = self:_newEntry(name, 56)
    local hitbox = button({
        Parent = frame,
        Size = UDim2.fromScale(1, 1),
    })
    label({
        Parent = frame,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -66, 1, 0),
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextSize = 13,
    })
    label({
        Parent = frame,
        Position = UDim2.new(1, -45, 0, 0),
        Size = UDim2.fromOffset(26, 56),
        Font = Enum.Font.GothamBold,
        Text = "›",
        TextColor3 = THEME.Accent,
        TextSize = 22,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    addHover(hitbox, frame, THEME.SurfaceRaised, THEME.SurfaceHover)
    connect(hitbox.MouseButton1Click, function()
        tween(frame, 0.08, {BackgroundColor3 = THEME.AccentDark})
        task.delay(0.09, function()
            if frame.Parent then
                tween(frame, 0.14, {BackgroundColor3 = THEME.SurfaceRaised})
            end
        end)
        self._window:_addActivity(name .. " activated")
        safeCallback(options.Callback)
    end)
    return {
        Set = function() end,
    }
end

function TabMethods:CreateToggle(options)
    options = options or {}
    local name = tostring(options.Name or "Toggle")
    local flag = options.Flag
    local window = self._window
    local value = storedValue(flag, options.CurrentValue == true) == true
    local frame = self:_newEntry(name, 64)
    local lamp = create("Frame", {
        Parent = frame,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = THEME.Dim,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(18, 32),
        Size = UDim2.fromOffset(9, 9),
    }, {corner(2)})
    label({
        Parent = frame,
        Position = UDim2.fromOffset(38, 0),
        Size = UDim2.new(1, -116, 1, 0),
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextSize = 13,
    })
    local track = create("Frame", {
        Parent = frame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -18, 0.5, 0),
        Size = UDim2.fromOffset(60, 32),
    }, {corner(7), stroke(THEME.Border, 0, 1)})
    local knob = create("Frame", {
        Parent = track,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = THEME.Dim,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 5, 0.5, 0),
        Size = UDim2.fromOffset(23, 23),
    }, {corner(5)})
    local hitbox = button({Parent = frame, Size = UDim2.fromScale(1, 1)})
    local element = {}

    local function render(instant)
        local properties = {
            BackgroundColor3 = value and THEME.Accent or THEME.Dim,
            Position = value and UDim2.new(1, -28, 0.5, 0) or UDim2.new(0, 5, 0.5, 0),
        }
        if instant then
            for key, propertyValue in pairs(properties) do
                knob[key] = propertyValue
            end
        else
            tween(knob, 0.16, properties)
        end
        track.BackgroundColor3 = value and Color3.fromRGB(28, 38, 15) or THEME.Background
        lamp.BackgroundColor3 = value and THEME.Accent or THEME.Dim
    end

    function element:Set(nextValue, skipCallback)
        value = nextValue == true
        render(false)
        remember(flag, value)
        if not skipCallback then
            window:_addActivity(name .. (value and " enabled" or " disabled"))
            safeCallback(options.Callback, value)
        end
    end

    connect(hitbox.MouseButton1Click, function()
        element:Set(not value)
    end)
    addHover(hitbox, frame, THEME.SurfaceRaised, THEME.SurfaceHover)
    Raven.Flags[flag or name] = value
    render(true)
    task.defer(function()
        safeCallback(options.Callback, value)
    end)
    return element
end

function TabMethods:CreateSlider(options)
    options = options or {}
    local name = tostring(options.Name or "Slider")
    local range = options.Range or {0, 100}
    local minimum = tonumber(range[1]) or 0
    local maximum = tonumber(range[2]) or 100
    local increment = tonumber(options.Increment) or 1
    local suffix = tostring(options.Suffix or "")
    local flag = options.Flag
    local value = tonumber(storedValue(flag, options.CurrentValue)) or minimum
    local dragging = false
    local frame = self:_newEntry(name, 88)
    label({
        Parent = frame,
        Position = UDim2.fromOffset(18, 8),
        Size = UDim2.new(1, -150, 0, 30),
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextSize = 13,
    })
    local valueLabel = label({
        Parent = frame,
        Position = UDim2.new(1, -136, 0, 8),
        Size = UDim2.fromOffset(118, 30),
        TextColor3 = THEME.Muted,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    local decrease = button({
        Parent = frame,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0,
        Position = UDim2.fromOffset(18, 60),
        Size = UDim2.fromOffset(28, 28),
        Text = "−",
        TextColor3 = THEME.Muted,
        TextSize = 16,
    })
    corner(5).Parent = decrease
    stroke(THEME.Border, 0, 1).Parent = decrease
    local increase = button({
        Parent = frame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0,
        Position = UDim2.new(1, -18, 0, 60),
        Size = UDim2.fromOffset(28, 28),
        Text = "+",
        TextColor3 = THEME.Muted,
        TextSize = 16,
    })
    corner(5).Parent = increase
    stroke(THEME.Border, 0, 1).Parent = increase
    local track = create("Frame", {
        Parent = frame,
        BackgroundColor3 = Color3.fromRGB(48, 55, 62),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(58, 58),
        Size = UDim2.new(1, -116, 0, 4),
    }, {corner(4)})
    local fill = create("Frame", {
        Parent = track,
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1),
    }, {corner(4)})
    local knob = create("Frame", {
        Parent = track,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(18, 18),
    }, {corner(5), stroke(Color3.fromRGB(205, 255, 116), 0.25, 1)})
    local hitbox = button({
        Parent = track,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 30),
    })
    local element = {}

    local function snap(raw)
        local snapped = math.floor(((raw - minimum) / increment) + 0.5) * increment + minimum
        return math.clamp(snapped, minimum, maximum)
    end

    local function decimals(number)
        if math.abs(number - math.floor(number)) < 0.0001 then
            return tostring(math.floor(number))
        end
        return string.format("%.2f", number):gsub("0+$", ""):gsub("%.$", "")
    end

    local function render()
        local ratio = maximum == minimum and 0 or (value - minimum) / (maximum - minimum)
        fill.Size = UDim2.fromScale(ratio, 1)
        knob.Position = UDim2.fromScale(ratio, 0.5)
        valueLabel.Text = decimals(value) .. suffix
    end

    function element:Set(nextValue, skipCallback)
        value = snap(tonumber(nextValue) or value)
        render()
        remember(flag, value)
        if not skipCallback then
            safeCallback(options.Callback, value)
        end
    end

    local function setFromInput(input)
        local ratio = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        element:Set(minimum + (maximum - minimum) * ratio)
    end

    connect(hitbox.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromInput(input)
        end
    end)
    connect(decrease.MouseButton1Click, function()
        element:Set(value - increment)
    end)
    connect(increase.MouseButton1Click, function()
        element:Set(value + increment)
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setFromInput(input)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            self._window:_addActivity(name .. " set to " .. valueLabel.Text)
        end
    end)
    Raven.Flags[flag or name] = value
    render()
    task.defer(function()
        safeCallback(options.Callback, value)
    end)
    return element
end

function TabMethods:CreateDropdown(options)
    options = options or {}
    local name = tostring(options.Name or "Dropdown")
    local choices = normalizeOptions(options.Options)
    local multiple = options.MultipleOptions == true
    local initial = normalizeSelection(options.CurrentOption, choices[1] and {choices[1]} or {})
    local flag = options.Flag
    local selection = normalizeSelection(storedValue(flag, initial), initial)
    local frame = self:_newEntry(name, 64)
    label({
        Parent = frame,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(0.45, -18, 1, 0),
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local selector = button({
        Parent = frame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0,
        Position = UDim2.new(1, -18, 0.5, 0),
        Size = UDim2.new(0.5, 0, 0, 38),
        Text = "",
    })
    corner(6).Parent = selector
    stroke(THEME.Border, 0, 1).Parent = selector
    local selectedLabel = label({
        Parent = selector,
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -38, 1, 0),
        TextColor3 = THEME.Muted,
        TextSize = 11,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    label({
        Parent = selector,
        Position = UDim2.new(1, -28, 0, 0),
        Size = UDim2.fromOffset(20, 38),
        Font = Enum.Font.GothamBold,
        Text = "⌄",
        TextColor3 = THEME.Muted,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local element = {}

    local function render()
        selectedLabel.Text = #selection > 0 and table.concat(selection, ", ") or "Select..."
    end

    local function emit(skipCallback)
        remember(flag, selection)
        render()
        if string.find(string.lower(name), "performance preset", 1, true) and selection[1] then
            if self._window._profileLabel then
                self._window._profileLabel.Text = selection[1]
            end
            if self._window._profileBadge then
                self._window._profileBadge.Text = selection[1] .. "                 ⌄"
            end
        end
        if not skipCallback then
            safeCallback(options.Callback, selection)
        end
    end

    function element:Set(nextSelection, skipCallback)
        selection = normalizeSelection(nextSelection, {})
        emit(skipCallback)
    end

    function element:Refresh(nextOptions, keepSelection)
        choices = normalizeOptions(nextOptions)
        if not keepSelection then
            selection = choices[1] and {choices[1]} or {}
            emit(false)
        else
            render()
        end
    end

    connect(selector.MouseButton1Click, function()
        local window = self._window
        window:_closePopup()
        local rootPosition = window._root.AbsolutePosition
        local selectorPosition = selector.AbsolutePosition
        local selectorSize = selector.AbsoluteSize
        local uiScale = math.max(window._scale.Scale, 0.01)
        local popupHeight = math.min(math.max(#choices * 36 + 8, 44), 224)
        local popup = create("ScrollingFrame", {
            Parent = window._popupHolder,
            Active = true,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = THEME.SurfaceRaised,
            BorderSizePixel = 0,
            CanvasSize = UDim2.fromOffset(0, 0),
            Position = UDim2.fromOffset(
                (selectorPosition.X - rootPosition.X) / uiScale,
                (selectorPosition.Y - rootPosition.Y + selectorSize.Y) / uiScale + 4
            ),
            ScrollBarImageColor3 = THEME.AccentDark,
            ScrollBarThickness = 3,
            Size = UDim2.fromOffset(selectorSize.X / uiScale, popupHeight),
            ZIndex = 42,
        }, {
            corner(6),
            stroke(THEME.Border, 0, 1),
            padding(4, 4, 4, 4),
            create("UIListLayout", {
                Padding = UDim.new(0, 2),
                SortOrder = Enum.SortOrder.LayoutOrder,
            }),
        })
        window._popup = popup
        if #choices == 0 then
            label({
                Parent = popup,
                Size = UDim2.new(1, 0, 0, 34),
                Text = "No options",
                TextColor3 = THEME.Dim,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Center,
                ZIndex = 43,
            })
        end
        for index, choice in ipairs(choices) do
            local selected = table.find(selection, choice) ~= nil
            local choiceButton = button({
                Parent = popup,
                BackgroundColor3 = selected and Color3.fromRGB(31, 43, 17) or THEME.SurfaceRaised,
                BackgroundTransparency = 0,
                LayoutOrder = index,
                Size = UDim2.new(1, 0, 0, 34),
                Text = (selected and "  ✓  " or "     ") .. choice,
                TextColor3 = selected and THEME.Accent or THEME.Text,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 43,
            })
            corner(4).Parent = choiceButton
            connect(choiceButton.MouseButton1Click, function()
                if multiple then
                    local selectionIndex = table.find(selection, choice)
                    if selectionIndex then
                        table.remove(selection, selectionIndex)
                    else
                        table.insert(selection, choice)
                    end
                else
                    selection = {choice}
                end
                emit(false)
                window:_addActivity(name .. " changed to " .. table.concat(selection, ", "))
                window:_closePopup()
            end)
        end
    end)
    addHover(selector, selector, THEME.Background, THEME.SurfaceHover)
    Raven.Flags[flag or name] = selection
    render()
    task.defer(function()
        safeCallback(options.Callback, selection)
    end)
    return element
end

function TabMethods:CreateInput(options)
    options = options or {}
    local name = tostring(options.Name or "Input")
    local flag = options.Flag
    local value = tostring(storedValue(flag, options.CurrentValue or ""))
    local frame = self:_newEntry(name, 72)
    label({
        Parent = frame,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(0.42, -18, 1, 0),
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local textBox = create("TextBox", {
        Parent = frame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderColor3 = THEME.Dim,
        PlaceholderText = tostring(options.PlaceholderText or "Type here..."),
        Position = UDim2.new(1, -18, 0.5, 0),
        Size = UDim2.new(0.56, 0, 0, 40),
        Text = value,
        TextColor3 = THEME.Text,
        TextSize = 11,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, {corner(6), stroke(THEME.Border, 0, 1), padding(12, 12, 0, 0)})
    local element = {}
    function element:Set(nextValue, skipCallback)
        value = tostring(nextValue or "")
        textBox.Text = value
        remember(flag, value)
        if not skipCallback then
            safeCallback(options.Callback, value)
        end
    end
    connect(textBox.FocusLost, function()
        element:Set(textBox.Text)
        self._window:_addActivity(name .. " updated", "info")
        if options.RemoveTextAfterFocusLost == true then
            textBox.Text = ""
        end
    end)
    Raven.Flags[flag or name] = value
    task.defer(function()
        safeCallback(options.Callback, value)
    end)
    return element
end

function TabMethods:CreateKeybind(options)
    options = options or {}
    local name = tostring(options.Name or "Keybind")
    local flag = options.Flag
    local stored = storedValue(flag, options.CurrentKeybind or "Unknown")
    local currentName = type(stored) == "string" and stored or tostring(options.CurrentKeybind or "Unknown")
    local currentKey = keyCodeFromName(currentName)
    local listening = false
    local frame = self:_newEntry(name, 64)
    label({
        Parent = frame,
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -116, 1, 0),
        Font = Enum.Font.GothamMedium,
        Text = name,
        TextSize = 13,
    })
    local keyButton = button({
        Parent = frame,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0,
        Position = UDim2.new(1, -18, 0.5, 0),
        Size = UDim2.fromOffset(82, 38),
        TextColor3 = THEME.Text,
        TextSize = 11,
    })
    corner(6).Parent = keyButton
    stroke(THEME.Border, 0, 1).Parent = keyButton
    local element = {}

    local function render()
        keyButton.Text = listening and "PRESS KEY" or currentName
        keyButton.TextColor3 = listening and THEME.Accent or THEME.Text
    end

    function element:Set(nextValue)
        currentName = tostring(nextValue or "Unknown"):gsub("Enum.KeyCode.", "")
        currentKey = keyCodeFromName(currentName)
        remember(flag, currentName)
        render()
    end

    connect(keyButton.MouseButton1Click, function()
        listening = true
        render()
    end)
    table.insert(keybinds, {
        getKey = function()
            return currentKey
        end,
        isListening = function()
            return listening
        end,
        capture = function(input)
            if input.KeyCode ~= Enum.KeyCode.Unknown then
                listening = false
                element:Set(input.KeyCode.Name)
                self._window:_addActivity(name .. " bound to " .. currentName, "info")
                return true
            end
            return false
        end,
        hold = options.HoldToInteract == true,
        callback = options.Callback,
    })
    Raven.Flags[flag or name] = currentName
    render()
    return element
end

local function buildDashboard(window, parent)
    local session = createMetricCard(parent, UDim2.new(0, 0, 0, 0), UDim2.new(0.47, 0, 0, 220), "Session", THEME.Cyan)
    label({
        Parent = session,
        Position = UDim2.fromOffset(18, 54),
        Size = UDim2.new(1, -36, 0, 56),
        Font = Enum.Font.Gotham,
        Text = "◷",
        TextColor3 = THEME.Cyan,
        TextSize = 46,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    window._sessionLabel = label({
        Parent = session,
        Position = UDim2.fromOffset(18, 120),
        Size = UDim2.new(1, -36, 0, 48),
        Font = Enum.Font.GothamBold,
        Text = "00m 00s",
        TextSize = 24,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    label({
        Parent = session,
        Position = UDim2.fromOffset(18, 170),
        Size = UDim2.new(1, -36, 0, 24),
        Text = "ACTIVE SESSION",
        TextColor3 = THEME.Dim,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local profile = createMetricCard(parent, UDim2.new(0.49, 0, 0, 0), UDim2.new(0.51, 0, 0, 220), "Profile", THEME.Accent)
    local avatar = create("Frame", {
        Parent = profile,
        AnchorPoint = Vector2.new(0.5, 0),
        BackgroundColor3 = THEME.SurfaceHover,
        BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0, 50),
        Size = UDim2.fromOffset(66, 66),
    }, {corner(66), stroke(THEME.Accent, 0, 2)})
    label({
        Parent = avatar,
        Size = UDim2.fromScale(1, 1),
        Font = Enum.Font.GothamBold,
        Text = LOCAL_PLAYER and string.upper(LOCAL_PLAYER.Name:sub(1, 1)) or "R",
        TextColor3 = THEME.Muted,
        TextSize = 24,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    window._profileLabel = label({
        Parent = profile,
        Position = UDim2.fromOffset(18, 124),
        Size = UDim2.new(1, -36, 0, 34),
        Font = Enum.Font.GothamMedium,
        Text = "Balanced",
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local profileBadge = label({
        Parent = profile,
        BackgroundColor3 = THEME.Background,
        BackgroundTransparency = 0,
        Position = UDim2.fromOffset(18, 166),
        Size = UDim2.new(1, -36, 0, 36),
        Text = "Balanced                 ⌄",
        TextColor3 = THEME.Muted,
        TextSize = 11,
    })
    corner(6).Parent = profileBadge
    stroke(THEME.Border, 0, 1).Parent = profileBadge
    window._profileBadge = profileBadge

    local activity = create("Frame", {
        Parent = parent,
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 232),
        Size = UDim2.new(1, 0, 1, -232),
    }, {corner(8), stroke(THEME.Border, 0.08, 1)})
    label({
        Parent = activity,
        Position = UDim2.fromOffset(18, 10),
        Size = UDim2.new(1, -36, 0, 30),
        Font = Enum.Font.GothamBold,
        Text = "RECENT ACTIVITY",
        TextColor3 = THEME.Muted,
        TextSize = 11,
    })
    create("Frame", {
        Parent = activity,
        BackgroundColor3 = THEME.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 46),
        Size = UDim2.new(1, 0, 0, 1),
    })
    window._activityList = create("Frame", {
        Parent = activity,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(0, 47),
        Size = UDim2.new(1, 0, 1, -47),
    }, {
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })
end

function Raven:CreateWindow(options)
    options = options or {}
    self:Destroy()

    local configuration = options.ConfigurationSaving or {}
    configState.enabled = configuration.Enabled == true
    configState.folder = tostring(configuration.FolderName or "RAVENHUB")
    configState.file = tostring(configuration.FileName or "HubConfig")
    configState.values = {}
    Raven.Flags = {}
    loadConfig()

    destroyExistingGuis()

    local screenGui = create("ScreenGui", {
        Name = GUI_NAME,
        DisplayOrder = 999999,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, screenGui)
    end
    mountScreenGui(screenGui)

    local root = create("Frame", {
        Parent = screenGui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(1120, 700),
    }, {corner(8), stroke(Color3.fromRGB(65, 74, 84), 0, 1)})
    local scale = create("UIScale", {Parent = root, Scale = 1})

    local window = setmetatable({
        _screenGui = screenGui,
        _root = root,
        _scale = scale,
        _tabs = {},
        _activeTab = nil,
        _startedAt = os.clock(),
        _minimized = false,
    }, {__index = WindowMethods})
    activeWindow = window

    local sidebar = create("Frame", {
        Parent = root,
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 136, 1, 0),
    })
    makeLogo(sidebar)
    create("Frame", {
        Parent = sidebar,
        BackgroundColor3 = THEME.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(135, 0),
        Size = UDim2.new(0, 1, 1, 0),
    })
    window._navList = create("ScrollingFrame", {
        Parent = sidebar,
        Active = true,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = UDim2.fromOffset(0, 76),
        ScrollBarThickness = 0,
        Size = UDim2.new(1, 0, 1, -132),
    }, {
        create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    local topbar = create("Frame", {
        Parent = root,
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(136, 0),
        Size = UDim2.new(1, -136, 0, 76),
    })
    create("Frame", {
        Parent = topbar,
        AnchorPoint = Vector2.new(0, 1),
        BackgroundColor3 = THEME.BorderSoft,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 1),
    })
    label({
        Parent = topbar,
        Position = UDim2.fromOffset(22, 0),
        Size = UDim2.fromOffset(178, 76),
        Font = Enum.Font.GothamBold,
        Text = tostring(options.Name or "RAVEN UI"),
        TextSize = 19,
    })

    local experienceName = "Roblox Experience"
    pcall(function()
        experienceName = game.Name
    end)
    local gameBadge = create("Frame", {
        Parent = topbar,
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(198, 16),
        Size = UDim2.fromOffset(250, 44),
    }, {corner(6), stroke(THEME.Border, 0, 1)})
    local cube = label({
        Parent = gameBadge,
        BackgroundColor3 = THEME.SurfaceHover,
        BackgroundTransparency = 0,
        Position = UDim2.fromOffset(7, 7),
        Size = UDim2.fromOffset(30, 30),
        Font = Enum.Font.GothamBold,
        Text = "R",
        TextColor3 = THEME.Muted,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    corner(5).Parent = cube
    label({
        Parent = gameBadge,
        Position = UDim2.fromOffset(46, 0),
        Size = UDim2.new(1, -58, 1, 0),
        Text = experienceName,
        TextSize = 11,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })

    local searchBox = create("TextBox", {
        Parent = topbar,
        BackgroundColor3 = THEME.Background,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        PlaceholderColor3 = THEME.Dim,
        PlaceholderText = "Search commands...",
        Position = UDim2.new(0, 466, 0, 16),
        Size = UDim2.new(1, -720, 0, 44),
        Text = "",
        TextColor3 = THEME.Text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, {corner(6), stroke(THEME.Border, 0, 1), padding(38, 12, 0, 0)})
    window._search = searchBox
    label({
        Parent = searchBox,
        Position = UDim2.fromOffset(-28, 0),
        Size = UDim2.fromOffset(26, 44),
        Text = "⌕",
        TextColor3 = THEME.Muted,
        TextSize = 24,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local connectionDot = create("Frame", {
        Parent = topbar,
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -152, 0.5, 0),
        Size = UDim2.fromOffset(9, 9),
    }, {corner(2)})
    label({
        Parent = topbar,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -66, 0, 0),
        Size = UDim2.fromOffset(78, 76),
        Text = "Connected",
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    connectionDot.Visible = true

    local minimize = button({
        Parent = topbar,
        Position = UDim2.new(1, -58, 0, 0),
        Size = UDim2.fromOffset(28, 76),
        Text = "−",
        TextColor3 = THEME.Muted,
        TextSize = 19,
    })
    local close = button({
        Parent = topbar,
        Position = UDim2.new(1, -30, 0, 0),
        Size = UDim2.fromOffset(28, 76),
        Text = "×",
        TextColor3 = THEME.Muted,
        TextSize = 22,
    })

    local content = create("Frame", {
        Parent = root,
        BackgroundColor3 = THEME.SurfaceRaised,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(136, 76),
        Size = UDim2.new(1, -136, 1, -132),
    })
    window._pageTitle = label({
        Parent = content,
        Position = UDim2.fromOffset(18, 4),
        Size = UDim2.new(0.55, -24, 0, 36),
        Font = Enum.Font.GothamBold,
        Text = "OVERVIEW",
        TextColor3 = THEME.Muted,
        TextSize = 10,
    })
    window._pageHolder = create("Frame", {
        Parent = content,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(18, 40),
        Size = UDim2.new(0.55, -24, 1, -54),
    })
    local dashboard = create("Frame", {
        Parent = content,
        BackgroundTransparency = 1,
        Position = UDim2.new(0.55, 6, 0, 16),
        Size = UDim2.new(0.45, -24, 1, -30),
    })
    buildDashboard(window, dashboard)

    local footer = create("Frame", {
        Parent = root,
        BackgroundColor3 = THEME.Surface,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 136, 1, -56),
        Size = UDim2.new(1, -136, 0, 56),
    })
    create("Frame", {
        Parent = footer,
        BackgroundColor3 = THEME.BorderSoft,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
    })
    create("Frame", {
        Parent = footer,
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(20, 28),
        Size = UDim2.fromOffset(9, 9),
    }, {corner(2)})
    label({
        Parent = footer,
        Position = UDim2.fromOffset(40, 0),
        Size = UDim2.fromOffset(92, 56),
        Text = "Connected",
        TextColor3 = THEME.Muted,
        TextSize = 11,
    })
    label({
        Parent = footer,
        Position = UDim2.fromOffset(138, 0),
        Size = UDim2.fromOffset(90, 56),
        Text = "v" .. Raven.Version,
        TextColor3 = THEME.Dim,
        TextSize = 11,
    })
    label({
        Parent = sidebar,
        Position = UDim2.new(0, 14, 1, -54),
        Size = UDim2.new(1, -28, 0, 38),
        Text = "RightShift  ·  Toggle",
        TextColor3 = THEME.Dim,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    window._popupHolder = create("Frame", {
        Parent = root,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 40,
    })
    window._toastHolder = create("Frame", {
        Parent = screenGui,
        AnchorPoint = Vector2.new(1, 1),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.fromOffset(300, 280),
    }, {
        create("UIListLayout", {
            Padding = UDim.new(0, 8),
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    connect(searchBox:GetPropertyChangedSignal("Text"), function()
        window:_applySearch(searchBox.Text)
    end)
    connect(close.MouseButton1Click, function()
        Raven:Destroy()
    end)
    connect(minimize.MouseButton1Click, function()
        window._minimized = not window._minimized
        content.Visible = not window._minimized
        footer.Visible = not window._minimized
        sidebar.Visible = not window._minimized
        root.Size = window._minimized and UDim2.fromOffset(984, 76) or UDim2.fromOffset(1120, 700)
        topbar.Position = window._minimized and UDim2.fromOffset(0, 0) or UDim2.fromOffset(136, 0)
        topbar.Size = window._minimized and UDim2.fromScale(1, 1) or UDim2.new(1, -136, 0, 76)
    end)
    makeDraggable(window, topbar)

    connect(UserInputService.InputBegan, function(input, processed)
        for _, keybind in ipairs(keybinds) do
            if keybind.isListening() and keybind.capture(input) then
                return
            end
        end
        if processed then
            return
        end
        if input.KeyCode == Enum.KeyCode.RightShift then
            screenGui.Enabled = not screenGui.Enabled
            return
        end
        for _, keybind in ipairs(keybinds) do
            if keybind.getKey() ~= Enum.KeyCode.Unknown and input.KeyCode == keybind.getKey() then
                safeCallback(keybind.callback, keybind.hold and true or nil)
            end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        for _, keybind in ipairs(keybinds) do
            if keybind.hold and input.KeyCode == keybind.getKey() then
                safeCallback(keybind.callback, false)
            end
        end
    end)
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        updateScale(window)
    end)
    if workspace.CurrentCamera then
        connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), function()
            updateScale(window)
        end)
    end
    local lastSessionUpdate = 0
    connect(RunService.Heartbeat, function()
        local now = os.clock()
        if now - lastSessionUpdate < 1 then
            return
        end
        lastSessionUpdate = now
        if window._sessionLabel and window._sessionLabel.Parent then
            window._sessionLabel.Text = formatClock(now - window._startedAt)
        end
    end)

    updateScale(window)
    window:_addActivity("Connected to " .. experienceName, "info")
    task.defer(function()
        window:_showToast(options.LoadingTitle or options.Name or "RAVEN UI", options.LoadingSubtitle or "Interface ready", 3)
    end)
    return window
end

function Raven:Notify(options)
    options = options or {}
    if not activeWindow then
        return
    end
    local content = options.Content or options.Description or ""
    local kind = options.Type == "Error" and "danger" or "success"
    activeWindow:_showToast(options.Title or "RAVEN UI", content, options.Duration, kind)
end

function Raven:Destroy()
    if activeWindow and activeWindow._screenGui then
        activeWindow._screenGui:Destroy()
    end
    activeWindow = nil
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(connections)
    table.clear(keybinds)
end

return Raven
