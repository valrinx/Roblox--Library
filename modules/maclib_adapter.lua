--[[
    RAVEN HUB - MacLib compatibility adapter

    The interface itself is provided by MacLib. This adapter only translates the
    Rayfield-style control API used by the existing game modules into MacLib's
    Window -> TabGroup -> Tab -> Section API.
]]

return function(MacLib)
    assert(type(MacLib) == "table" and type(MacLib.Window) == "function", "MacLib is unavailable")

    local Adapter = {
        Version = "maclib-adapter-1.1.3",
        Flags = MacLib.Options or {},
        _maclib = MacLib,
        _window = nil,
    }

    local TAB_ICONS = {
        overview = "rbxassetid://18821914323",
        home = "rbxassetid://18821914323",
        main = "rbxassetid://18821914323",
        automation = "rbxassetid://99275039709063",
        farm = "rbxassetid://99275039709063",
        combat = "rbxassetid://99275039709063",
        boss = "rbxassetid://99275039709063",
        visual = "rbxassetid://104811813262009",
        esp = "rbxassetid://104811813262009",
        awareness = "rbxassetid://104811813262009",
        movement = "rbxassetid://121700697298748",
        mobile = "rbxassetid://121700697298748",
        player = "rbxassetid://121700697298748",
        loot = "rbxassetid://88238578565569",
        scripts = "rbxassetid://125500743878117",
        library = "rbxassetid://125500743878117",
        quest = "rbxassetid://125500743878117",
        misc = "rbxassetid://71732494649961",
        tools = "rbxassetid://71732494649961",
        credits = "rbxassetid://110807522910450",
        settings = "rbxassetid://10734950309",
    }

    local function safeCallback(callback, ...)
        if type(callback) ~= "function" then
            return
        end
        local ok, err = pcall(callback, ...)
        if not ok then
            warn("[RAVEN HUB / MacLib] callback failed: " .. tostring(err))
        end
    end

    local function normalizeOptions(options)
        local result = {}
        for _, value in ipairs(type(options) == "table" and options or {}) do
            table.insert(result, tostring(value))
        end
        return result
    end

    local function normalizeSelection(value)
        if type(value) == "table" then
            local result = {}
            for _, selected in ipairs(value) do
                table.insert(result, tostring(selected))
            end
            return result
        end
        if value == nil or value == "" then
            return {}
        end
        return {tostring(value)}
    end

    local function keyCodeFrom(value)
        if typeof(value) == "EnumItem" then
            return value
        end
        local name = tostring(value or "Unknown"):gsub("Enum.KeyCode.", "")
        local ok, keyCode = pcall(function()
            return Enum.KeyCode[name]
        end)
        return ok and keyCode or Enum.KeyCode.Unknown
    end

    local function resolveTabIcon(name, icon)
        if type(icon) == "string" then
            if icon:match("^rbxassetid://%d+$") then
                return icon
            end
            if icon:match("^%d+$") then
                return "rbxassetid://" .. icon
            end
        end

        local key = string.lower(tostring(icon or "") .. " " .. tostring(name or ""))
        local orderedKeys = {
            "settings", "credits", "awareness", "visual", "esp", "movement", "mobile",
            "player", "automation", "farm", "combat", "boss", "loot", "quest", "scripts",
            "library", "tools", "misc", "overview", "home", "main",
        }
        for _, candidate in ipairs(orderedKeys) do
            if key:find(candidate, 1, true) then
                return TAB_ICONS[candidate]
            end
        end
        return TAB_ICONS.main
    end

    local function configFlag(flag)
        if flag == nil or tostring(flag) == "" then
            return nil
        end
        return tostring(flag)
    end

    -- MacLib creates its configured folder and /settings child, but executor
    -- makefolder implementations are not guaranteed to create missing parent
    -- directories recursively. Build each relative path segment first.
    local function ensureFolderTree(folder)
        if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
            return
        end

        local path = ""
        for segment in string.gmatch(tostring(folder or ""), "[^/\\\\]+") do
            path = path == "" and segment or path .. "/" .. segment
            pcall(function()
                if not isfolder(path) then
                    makefolder(path)
                end
            end)
        end
    end

    local function installExactConfigLoader()
        local HttpService = game:GetService("HttpService")

        function MacLib:SaveConfig(path)
            if type(writefile) ~= "function" then
                return false, "Config system unavailable."
            end
            if path == nil or tostring(path) == "" then
                return false, "Please select a config file."
            end

            ensureFolderTree(self.Folder .. "/settings")
            local fullPath = self.Folder .. "/settings/" .. tostring(path) .. ".json"

            local data = {
                objects = {}
            }

            local function Color3ToHex(color)
                return string.format("#%02X%02X%02X", math.floor(color.R * 255), math.floor(color.G * 255), math.floor(color.B * 255))
            end

            for flag, option in next, (self.Options or {}) do
                if type(option) == "table" and not option.IgnoreConfig then
                    local class = option.Class
                    local flagStr = tostring(flag)
                    local entry = nil

                    if class == "Toggle" then
                        entry = {
                            type = "Toggle",
                            flag = flagStr,
                            state = (option.GetState and option:GetState()) or option.State or false
                        }
                    elseif class == "Slider" then
                        local val = option.GetValue and option:GetValue() or option.Value or 0
                        entry = {
                            type = "Slider",
                            flag = flagStr,
                            value = tostring(val)
                        }
                    elseif class == "Input" then
                        entry = {
                            type = "Input",
                            flag = flagStr,
                            text = tostring(option.Text or "")
                        }
                    elseif class == "Keybind" then
                        local bindName = (typeof(option.Bind) == "EnumItem" and option.Bind.Name) or (type(option.Bind) == "string" and option.Bind) or nil
                        entry = {
                            type = "Keybind",
                            flag = flagStr,
                            bind = bindName
                        }
                    elseif class == "Dropdown" then
                        entry = {
                            type = "Dropdown",
                            flag = flagStr,
                            value = option.Value
                        }
                    elseif class == "Colorpicker" then
                        entry = {
                            type = "Colorpicker",
                            flag = flagStr,
                            color = option.Color and Color3ToHex(option.Color) or nil,
                            alpha = option.Alpha
                        }
                    end

                    if entry then
                        table.insert(data.objects, entry)
                    end
                end
            end

            local success, encoded = pcall(HttpService.JSONEncode, HttpService, data)
            if not success then
                return false, "Unable to encode JSON data: " .. tostring(encoded)
            end

            local writeOk, writeErr = pcall(writefile, fullPath, encoded)
            if not writeOk then
                return false, "Failed to write file: " .. tostring(writeErr)
            end

            return true
        end

        -- MacLib's bundled loader skips Toggle values when the saved state is
        -- false. Replaying every supported value explicitly also makes loading
        -- deterministic once all module flags have been registered.
        function MacLib:LoadConfig(path)
            if type(isfile) ~= "function" or type(readfile) ~= "function" then
                return false, "Config system unavailable."
            end
            if path == nil or tostring(path) == "" then
                return false, "Please select a config file."
            end

            local file = self.Folder .. "/settings/" .. tostring(path) .. ".json"
            if not isfile(file) then
                return false, "Invalid file"
            end

            local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, readfile(file))
            if not decodedOk or type(decoded) ~= "table" or type(decoded.objects) ~= "table" then
                return false, "Unable to decode JSON data."
            end

            for _, saved in ipairs(decoded.objects) do
                local option = self.Options[tostring(saved.flag or "")]
                if option then
                    local applied, applyError = pcall(function()
                        if saved.type == "Toggle" then
                            option:UpdateState(saved.state == true)
                        elseif saved.type == "Slider" and saved.value ~= nil then
                            option:UpdateValue(tonumber(saved.value) or saved.value)
                            -- MacLib updates the slider display/value without
                            -- replaying its callback during config loads. Keep
                            -- the game module's runtime settings in sync too.
                            local callback = option.Settings and option.Settings.Callback
                            if type(callback) == "function" then
                                callback(option:GetValue())
                            end
                        elseif saved.type == "Input" and saved.text ~= nil then
                            option:UpdateText(tostring(saved.text))
                        elseif saved.type == "Keybind" and saved.bind then
                            local keyCode = Enum.KeyCode[tostring(saved.bind)]
                            if keyCode then
                                option:Bind(keyCode)
                            end
                        elseif saved.type == "Dropdown" and saved.value ~= nil then
                            option:UpdateSelection(saved.value)
                        elseif saved.type == "Colorpicker" and saved.color then
                            local hex = tostring(saved.color):gsub("#", "")
                            if #hex == 6 then
                                option:SetColor(Color3.fromRGB(
                                    tonumber(hex:sub(1, 2), 16) or 255,
                                    tonumber(hex:sub(3, 4), 16) or 255,
                                    tonumber(hex:sub(5, 6), 16) or 255
                                ))
                            end
                            if saved.alpha ~= nil then
                                option:SetAlpha(saved.alpha)
                            end
                        end
                    end)
                    if not applied then
                        warn("[RAVEN HUB / MacLib] config flag '" .. tostring(saved.flag)
                            .. "' failed: " .. tostring(applyError))
                    end
                end
            end

            return true
        end
    end

    local TabMethods = {}
    local WindowMethods = {}

    function TabMethods:_newSection(name)
        self._sectionCount = self._sectionCount + 1
        local side = self._sectionCount % 2 == 1 and "Left" or "Right"
        local nativeSection = self._native:Section({Side = side})
        if name and tostring(name) ~= "" then
            nativeSection:Header({Name = tostring(name)})
        end
        self._currentSection = nativeSection
        return nativeSection
    end

    function TabMethods:_ensureSection()
        return self._currentSection or self:_newSection("Controls")
    end

    function TabMethods:CreateSection(name)
        return self:_newSection(name)
    end

    function TabMethods:CreateLabel(text)
        local native = self:_ensureSection():Label({Text = tostring(text or "")})
        return {
            Set = function(_, value)
                native:UpdateName(tostring(value or ""))
            end,
        }
    end

    function TabMethods:CreateParagraph(options)
        options = options or {}
        local native = self:_ensureSection():Paragraph({
            Header = tostring(options.Title or options.Header or "Information"),
            Body = tostring(options.Content or options.Body or ""),
        })
        return {
            Set = function(_, value)
                native:UpdateBody(tostring(value or ""))
            end,
            _native = native,
        }
    end

    function TabMethods:CreateDivider()
        return self:_ensureSection():Divider()
    end

    function TabMethods:CreateStatus(options)
        options = options or {}
        local native = self:_ensureSection():Paragraph({
            Header = tostring(options.Title or "Experience module"),
            Body = tostring(options.Content or "Checking for a compatible game module..."),
        })
        return {
            Set = function(_, value)
                local text = tostring(value or "")
                local lower = string.lower(text)
                local title = tostring(options.Title or "Experience module")
                if lower:find("failed", 1, true) then
                    title = "Module failed to load"
                elseif lower:find("loaded", 1, true) then
                    title = "Experience module ready"
                elseif lower:find("no matching", 1, true) then
                    title = "No module for this experience"
                elseif lower:find("loading", 1, true) then
                    title = "Loading experience module"
                end
                native:UpdateHeader(title)
                native:UpdateBody(text)
            end,
        }
    end

    function TabMethods:CreateButton(options)
        options = options or {}
        local native = self:_ensureSection():Button({
            Name = tostring(options.Name or "Button"),
            Callback = function()
                safeCallback(options.Callback)
            end,
        }, configFlag(options.Flag))
        return native
    end

    function TabMethods:CreateToggle(options)
        options = options or {}
        local native = self:_ensureSection():Toggle({
            Name = tostring(options.Name or "Toggle"),
            Default = options.CurrentValue == true,
            Callback = function(value)
                safeCallback(options.Callback, value == true)
            end,
        }, configFlag(options.Flag))
        return {
            Set = function(_, value)
                native:UpdateState(value == true)
            end,
            Get = function()
                return native:GetState()
            end,
            _native = native,
        }
    end

    function TabMethods:CreateSlider(options)
        options = options or {}
        local range = type(options.Range) == "table" and options.Range or {0, 100}
        local minimum = tonumber(range[1]) or 0
        local maximum = tonumber(range[2]) or 100
        local increment = math.abs(tonumber(options.Increment) or 1)
        local precision = 0
        local precisionProbe = increment
        while precision < 4 and math.abs(precisionProbe - math.floor(precisionProbe + 0.5)) > 0.00001 do
            precision = precision + 1
            precisionProbe = precisionProbe * 10
        end

        local native
        local snapping = false
        native = self:_ensureSection():Slider({
            Name = tostring(options.Name or "Slider"),
            Default = tonumber(options.CurrentValue) or minimum,
            Minimum = minimum,
            Maximum = maximum,
            Precision = precision,
            Suffix = tostring(options.Suffix or ""),
            Callback = function(value)
                local numeric = tonumber(value) or minimum
                local snapped = math.clamp(
                    minimum + math.floor(((numeric - minimum) / increment) + 0.5) * increment,
                    minimum,
                    maximum
                )
                if not snapping and native and math.abs(snapped - numeric) > 0.00001 then
                    snapping = true
                    native:UpdateValue(snapped)
                    snapping = false
                    return
                end
                safeCallback(options.Callback, snapped)
            end,
        }, configFlag(options.Flag))
        return {
            Set = function(_, value)
                native:UpdateValue(tonumber(value) or minimum)
            end,
            Get = function()
                return native:GetValue()
            end,
            _native = native,
        }
    end

    function TabMethods:CreateDropdown(options)
        options = options or {}
        local section = self:_ensureSection()
        local choices = normalizeOptions(options.Options)
        local multiple = options.MultipleOptions == true
        local selection = normalizeSelection(options.CurrentOption or options.CurrentValue)
        if not multiple and #selection == 0 and choices[1] then
            selection = {choices[1]}
        end

        local default
        if multiple then
            default = selection
        else
            default = table.find(choices, selection[1]) or (#choices > 0 and 1 or nil)
        end

        local function emit(value)
            if multiple then
                local ordered = {}
                for _, choice in ipairs(choices) do
                    if type(value) == "table" and value[choice] then
                        table.insert(ordered, choice)
                    end
                end
                selection = ordered
            else
                selection = value and {tostring(value)} or {}
            end
            safeCallback(options.Callback, selection)
        end

        local native = section:Dropdown({
            Name = tostring(options.Name or "Dropdown"),
            Multi = multiple,
            Required = not multiple and #choices > 0,
            Search = #choices > 8,
            Options = choices,
            Default = default,
            Callback = emit,
        }, configFlag(options.Flag))

        local element = {_native = native}
        function element:Set(value)
            local nextSelection = normalizeSelection(value)
            self._native:UpdateSelection(multiple and nextSelection or nextSelection[1])
        end
        function element:Refresh(nextOptions, keepSelection)
            local previous = selection
            choices = normalizeOptions(nextOptions)
            self._native:ClearOptions()
            self._native:InsertOptions(choices)
            local nextSelection = {}
            if keepSelection then
                for _, selected in ipairs(previous) do
                    if table.find(choices, selected) then
                        table.insert(nextSelection, selected)
                    end
                end
            elseif not multiple and choices[1] then
                nextSelection = {choices[1]}
            end
            self._native:UpdateSelection(multiple and nextSelection or nextSelection[1])
        end
        return element
    end

    function TabMethods:CreateInput(options)
        options = options or {}
        local native = self:_ensureSection():Input({
            Name = tostring(options.Name or "Input"),
            Default = tostring(options.CurrentValue or ""),
            Placeholder = tostring(options.PlaceholderText or "Type here..."),
            AcceptedCharacters = "All",
            Callback = function(value)
                safeCallback(options.Callback, tostring(value or ""))
            end,
        }, configFlag(options.Flag))
        return {
            Set = function(_, value)
                native:UpdateText(tostring(value or ""))
            end,
            _native = native,
        }
    end

    function TabMethods:CreateKeybind(options)
        options = options or {}
        local holdToInteract = options.HoldToInteract == true
        local native = self:_ensureSection():Keybind({
            Name = tostring(options.Name or "Keybind"),
            Default = keyCodeFrom(options.CurrentKeybind),
            Callback = function()
                if not holdToInteract then
                    safeCallback(options.Callback)
                end
            end,
            onBindHeld = function(held)
                if holdToInteract then
                    safeCallback(options.Callback, held == true)
                end
            end,
        }, configFlag(options.Flag))
        return {
            Set = function(_, value)
                native:Bind(keyCodeFrom(value))
            end,
            _native = native,
        }
    end

    function TabMethods:InsertConfigSection(side)
        if type(self._native.InsertConfigSection) == "function" then
            self._native:InsertConfigSection(side or "Right")
        end
    end

    function TabMethods:Select()
        self._native:Select()
    end

    function WindowMethods:CreateTab(name, icon)
        local native = self._tabGroup:Tab({
            Name = tostring(name or "Tab"),
            Image = resolveTabIcon(name, icon),
        })
        local tab = setmetatable({
            _native = native,
            _sectionCount = 0,
            _currentSection = nil,
        }, {__index = TabMethods})
        if not self._selectedFirstTab then
            self._selectedFirstTab = true
            native:Select()
        end
        return tab
    end

    function WindowMethods:CreatePlaceholderTab(name, icon, message)
        local tab = self:CreateTab(name, icon)
        tab:CreateSection(tostring(name or "Unavailable"))
        tab:CreateStatus({
            Title = tostring(name or "Feature") .. " unavailable",
            Content = tostring(message or "No compatible module is loaded for this experience."),
        })
        return tab
    end

    function WindowMethods:Notify(options)
        options = options or {}
        self._native:Notify({
            Title = tostring(options.Title or "RAVEN HUB"),
            Description = tostring(options.Content or options.Description or ""),
            Lifetime = tonumber(options.Duration or options.Lifetime) or 5,
        })
    end

    function WindowMethods:OnUnload(callback)
        if type(callback) == "function" then
            table.insert(self._unloadCallbacks, callback)
        end
    end

    function WindowMethods:Destroy()
        if self._destroyed then
            return
        end
        self._destroyed = true
        self._native:Unload()
    end

    function Adapter:CreateWindow(options)
        options = options or {}
        if self._window then
            self._window:Destroy()
        end

        local native = MacLib:Window({
            Title = tostring(options.Name or "RAVEN HUB"),
            Subtitle = tostring(options.LoadingSubtitle or "MacLib interface"),
            Size = UDim2.fromOffset(868, 650),
            DragStyle = 1,
            DisabledWindowControls = {},
            ShowUserInfo = true,
            Keybind = Enum.KeyCode.RightShift,
            AcrylicBlur = true,
        })

        pcall(function()
            local root = type(gethui) == "function" and gethui() or game:GetService("CoreGui")
            for _, child in ipairs(root:GetChildren()) do
                if child:IsA("ScreenGui")
                    and child.Name == "ScreenGui"
                    and child:FindFirstChild("Base")
                    and child:FindFirstChild("Notifications") then
                    child.Name = "RavenMacLib"
                end
            end
        end)

        local saving = type(options.ConfigurationSaving) == "table" and options.ConfigurationSaving or {}
        if saving.Enabled ~= false then
            ensureFolderTree(tostring(saving.FolderName or "RAVENHUB"))
            MacLib:SetFolder(tostring(saving.FolderName or "RAVENHUB"))
        end
        -- MacLib defines its config methods inside MacLib:Window, so install
        -- the deterministic loader only after the native window exists.
        installExactConfigLoader()

        native:GlobalSetting({
            Name = "UI Blur",
            Default = native:GetAcrylicBlurState(),
            Callback = function(value)
                native:SetAcrylicBlurState(value)
            end,
        })
        native:GlobalSetting({
            Name = "Notifications",
            Default = native:GetNotificationsState(),
            Callback = function(value)
                native:SetNotificationsState(value)
            end,
        })
        native:GlobalSetting({
            Name = "Show User Info",
            Default = native:GetUserInfoState(),
            Callback = function(value)
                native:SetUserInfoState(value)
            end,
        })

        local window = setmetatable({
            _native = native,
            _tabGroup = native:TabGroup(),
            _selectedFirstTab = false,
            _unloadCallbacks = {},
            _destroyed = false,
        }, {__index = WindowMethods})

        native.onUnloaded(function()
            for _, callback in ipairs(window._unloadCallbacks) do
                safeCallback(callback)
            end
            if Adapter._window == window then
                Adapter._window = nil
            end
        end)

        self._window = window
        return window
    end

    function Adapter:Notify(options)
        if self._window then
            self._window:Notify(options)
        end
    end

    function Adapter:LoadAutoLoadConfig()
        return MacLib:LoadAutoLoadConfig()
    end

    function Adapter:Destroy()
        if self._window then
            self._window:Destroy()
            self._window = nil
        end
    end

    return Adapter
end
