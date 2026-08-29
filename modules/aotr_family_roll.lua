-- RAVEN HUB | Attack on Titan Revolution Family Roll v1.0.1
-- Uses the Rayfield-style API exposed by RAVEN HUB's MacLib adapter.
-- The controller only activates the visible Family UI button; it does not
-- invoke or replay game remotes directly.

local Players = game:GetService("Players")

local DEFAULT_TARGET = "Yeager"
local ROLL_INTERVAL = 0.35
local FAMILY_OPTIONS = {
    "Yeager",
    "Ackerman",
    "Reiss",
    "Helos",
    "Fritz",
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function normalizeFamilyName(value)
    return string.upper(trim(value))
end

local function parseFamilyTitle(value)
    local text = trim(value)
    local familyName = text:match("^(.-)%s*(%b())$")
    return normalizeFamilyName(familyName or text)
end

local function fireSignalSafely(signal, signalFirer)
    if not signal then
        return false
    end

    if type(signalFirer) == "function" then
        local ok, result = pcall(signalFirer, signal)
        if ok and result ~= false then
            return true
        end
    end

    local fireMethod
    local lookupOk = pcall(function()
        fireMethod = signal.Fire
    end)
    if lookupOk and type(fireMethod) == "function" then
        local ok, result = pcall(fireMethod, signal)
        if ok and result ~= false then
            return true
        end
    end

    return false
end

local function activateButton(button, signalFirer)
    if not button then
        return false, "button unavailable"
    end

    local effectiveSignalFirer = signalFirer
    if effectiveSignalFirer == nil and type(firesignal) == "function" then
        effectiveSignalFirer = firesignal
    end

    -- Potassium exposes firesignal while this client does not expose
    -- GuiButton:Activate(). Prefer the button's normal click signal so the
    -- game's existing callback handles the roll and no remote is guessed.
    if fireSignalSafely(button.MouseButton1Click, effectiveSignalFirer) then
        return true
    end
    if fireSignalSafely(button.Activated, effectiveSignalFirer) then
        return true
    end

    local inputOk, virtualInput = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if inputOk and virtualInput then
        local coordinateOk, position, size = pcall(function()
            return button.AbsolutePosition, button.AbsoluteSize
        end)
        if coordinateOk and position and size then
            local clickOk = pcall(function()
                local center = position + (size / 2)
                virtualInput:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
                virtualInput:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
            end)
            if clickOk then
                return true
            end
        end
    end

    return false, "no supported UI activation method"
end

local function createController(dependencies)
    assert(type(dependencies) == "table", "Family Roll dependencies are required")
    assert(type(dependencies.getCurrentFamily) == "function", "getCurrentFamily is required")
    assert(type(dependencies.activateRoll) == "function", "activateRoll is required")

    local state = {
        target = "",
        enabled = false,
    }

    local controller = {}

    local function notify(message)
        if type(dependencies.notify) == "function" then
            pcall(dependencies.notify, message)
        end
    end

    function controller:setTarget(value)
        state.target = normalizeFamilyName(value)
        return state.target
    end

    function controller:getTarget()
        return state.target
    end

    function controller:setEnabled(value)
        state.enabled = value == true
        return state.enabled
    end

    function controller:isEnabled()
        return state.enabled
    end

    function controller:step()
        if not state.enabled then
            return "disabled"
        end

        if state.target == "" then
            state.enabled = false
            notify("ตั้งชื่อ Family เป้าหมายก่อนเริ่ม")
            return "stopped_invalid_target"
        end

        local currentOk, currentTitle = pcall(dependencies.getCurrentFamily)
        if not currentOk or type(currentTitle) ~= "string" then
            state.enabled = false
            notify("ไม่พบหน้า Family หรือข้อความผลลัพธ์")
            return "stopped_ui_unavailable"
        end

        local observed = parseFamilyTitle(currentTitle)
        if observed == state.target then
            state.enabled = false
            notify("พบ " .. trim(currentTitle) .. " แล้ว หยุด Auto Roll")
            return "matched"
        end

        local rollOk, rollResult, rollError = pcall(dependencies.activateRoll)
        if not rollOk or rollResult == false then
            state.enabled = false
            notify("กด Roll ไม่สำเร็จ: " .. tostring(rollError or rollResult or "ปุ่มไม่พร้อมใช้งาน"))
            return "stopped_roll_error"
        end

        return "rolled"
    end

    return controller
end

return function(Window, runtimeInfo)
    -- Explicit seam used by the live Luau test harness; normal hub loading
    -- never passes testMode.
    if runtimeInfo and runtimeInfo.testMode then
        runtimeInfo.testMode.newController = createController
        runtimeInfo.testMode.activateButton = activateButton
        return
    end

    assert(Window and type(Window.CreateTab) == "function", "RAVEN HUB window is required")

    local player = Players.LocalPlayer
    local destroyed = false
    local loopThread
    local rollInterval = ROLL_INTERVAL

    local FamilyTab = Window:CreateTab("Family Roll")
    FamilyTab:CreateSection("Auto Roll")
    local StatusLabel = FamilyTab:CreateLabel("Status: Idle")
    local CurrentFamilyLabel = FamilyTab:CreateLabel("Current Family: Unknown")

    local function notify(message)
        local text = tostring(message or "")
        pcall(function()
            StatusLabel:Set("Status: " .. text)
        end)
        pcall(function()
            Window:Notify({
                Title = "AOTR Family Roll",
                Content = text,
                Duration = 4,
            })
        end)
    end

    local function getFamilyPanel()
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        local interface = playerGui and playerGui:FindFirstChild("Interface")
        local customisation = interface and interface:FindFirstChild("Customisation")
        return customisation and customisation:FindFirstChild("Family")
    end

    local function isGuiHierarchyVisible(gui)
        local node = gui
        while node do
            if node:IsA("GuiObject") and not node.Visible then
                return false
            end
            if node:IsA("ScreenGui") and not node.Enabled then
                return false
            end
            node = node.Parent
        end
        return true
    end

    local function getRollButton()
        local panel = getFamilyPanel()
        local button = panel and panel:FindFirstChild("Roll", true)
        if not button or not button:IsA("GuiButton") then
            return nil
        end
        if not button.Visible or button.Active == false or not isGuiHierarchyVisible(button) then
            return nil
        end
        return button
    end

    local function getCurrentFamily()
        local panel = getFamilyPanel()
        local family = panel and panel:FindFirstChild("Family")
        local title = family and family:FindFirstChild("Title")
        if not title or not title:IsA("TextLabel") then
            return nil
        end
        return title.Text
    end

    local function refreshCurrentFamily()
        local title = getCurrentFamily()
        pcall(function()
            CurrentFamilyLabel:Set("Current Family: " .. tostring(title or "Unknown"))
        end)
        return title
    end

    local controller = createController({
        getCurrentFamily = getCurrentFamily,
        activateRoll = function()
            local button = getRollButton()
            if not button then
                return false, "Roll button unavailable"
            end
            return activateButton(button)
        end,
        notify = notify,
    })
    controller:setTarget(DEFAULT_TARGET)

    local function stopLoop()
        if loopThread then
            pcall(task.cancel, loopThread)
            loopThread = nil
        end
    end

    local function startLoop()
        stopLoop()
        loopThread = task.spawn(function()
            while not destroyed and controller:isEnabled() do
                refreshCurrentFamily()
                controller:step()
                task.wait(rollInterval)
            end
            loopThread = nil
        end)
    end

    FamilyTab:CreateSection("Target Family")
    local TargetInput = FamilyTab:CreateInput({
        Name = "Target Family",
        PlaceholderText = "เช่น Yeager",
        CurrentValue = DEFAULT_TARGET,
        Flag = "AOTRFamilyRollTarget",
        Callback = function(value)
            local target = controller:setTarget(value)
            if target == "" then
                notify("กรุณาระบุชื่อ Family เป้าหมาย")
            elseif controller:isEnabled() then
                notify("เป้าหมาย: " .. target)
            end
        end,
    })

    FamilyTab:CreateDropdown({
        Name = "Quick Target",
        Options = FAMILY_OPTIONS,
        CurrentOption = {DEFAULT_TARGET},
        MultipleOptions = false,
        Flag = "AOTRFamilyRollQuickTarget",
        Callback = function(value)
            local selected = type(value) == "table" and value[1] or value
            local target = controller:setTarget(selected)
            if TargetInput and type(TargetInput.Set) == "function" then
                pcall(function()
                    TargetInput:Set(selected)
                end)
            end
            if target ~= "" and controller:isEnabled() then
                notify("เป้าหมาย: " .. target)
            end
        end,
    })

    FamilyTab:CreateButton({
        Name = "Refresh Current Family",
        Callback = function()
            local title = refreshCurrentFamily()
            notify("Current Family: " .. tostring(title or "Unknown"))
        end,
    })

    FamilyTab:CreateSlider({
        Name = "Roll Interval",
        Range = {0.2, 2},
        Increment = 0.1,
        Suffix = " sec",
        CurrentValue = ROLL_INTERVAL,
        Flag = "AOTRFamilyRollInterval",
        Callback = function(value)
            rollInterval = math.clamp(tonumber(value) or ROLL_INTERVAL, 0.2, 2)
        end,
    })

    FamilyTab:CreateToggle({
        Name = "Auto Roll Family",
        CurrentValue = false,
        Flag = "AOTRFamilyRollEnabled",
        Callback = function(value)
            if destroyed then
                return
            end
            controller:setEnabled(value == true)
            if value == true then
                notify("เริ่ม Auto Roll เป้าหมาย: " .. (controller:getTarget() ~= "" and controller:getTarget() or "ยังไม่ได้ตั้งค่า"))
                startLoop()
            else
                stopLoop()
                notify("หยุด Auto Roll")
            end
        end,
    })

    FamilyTab:CreateParagraph({
        Title = "วิธีใช้",
        Content = "เปิดหน้า Customisation > Family จากนั้นเลือกหรือพิมพ์ชื่อ Family แล้วเปิด Auto Roll ระบบจะหยุดเมื่อข้อความ Family ตรงกับเป้าหมาย",
    })

    refreshCurrentFamily()

    if runtimeInfo and runtimeInfo.registerCleanup then
        runtimeInfo.registerCleanup(function()
            destroyed = true
            controller:setEnabled(false)
            stopLoop()
        end)
    end
end
