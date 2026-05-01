local EspRuntime = {}

function EspRuntime.destroyVisualEntry(entry)
    if type(entry) ~= "table" then
        return
    end
    if entry.visual and entry.visual.Parent then
        entry.visual:Destroy()
    end
    if entry.billboard and entry.billboard.Parent then
        entry.billboard:Destroy()
    end
end

function EspRuntime.clearAll(espState)
    if type(espState) ~= "table" then
        return
    end
    if type(espState.activeVisuals) == "table" then
        for _, entry in pairs(espState.activeVisuals) do
            EspRuntime.destroyVisualEntry(entry)
        end
    end
    espState.activeVisuals = {}
    espState.activeRenderParts = {}
    if type(espState.connections) == "table" then
        for _, conn in ipairs(espState.connections) do
            if conn and conn.Disconnect then
                conn:Disconnect()
            end
        end
    end
    espState.connections = {}
end

function EspRuntime.setVisualVisibility(entry, isVisible)
    if type(entry) ~= "table" then
        return
    end
    if entry.visual and entry.visual:IsA("Highlight") then
        entry.visual.Enabled = isVisible
    elseif entry.visual and entry.visual:IsA("BoxHandleAdornment") then
        entry.visual.Visible = isVisible
    end
    if entry.billboard then
        entry.billboard.Enabled = isVisible
    end
end

function EspRuntime.syncVisualStyle(entry, color, renderPart)
    if type(entry) ~= "table" then
        return
    end
    if entry.visual then
        if entry.visual:IsA("Highlight") then
            entry.visual.FillColor = color
            entry.visual.OutlineColor = color
            entry.visual.FillTransparency = 0.78
            entry.visual.OutlineTransparency = 0.05
        elseif entry.visual:IsA("BoxHandleAdornment") then
            entry.visual.Color3 = color
            entry.visual.Transparency = 0.72
            if renderPart and renderPart:IsA("BasePart") then
                entry.visual.Size = renderPart.Size + Vector3.new(0.05, 0.05, 0.05)
            end
        end
    end
    if entry.label then
        entry.label.TextColor3 = color
    end
end

function EspRuntime.scanAll(workspaceRef, applyTargetFn, resolveTargetFromInstanceFn)
    if not workspaceRef or type(applyTargetFn) ~= "function" then
        return
    end
    local folders = {
        workspaceRef:FindFirstChild("PlacedOre"),
        workspaceRef:FindFirstChild("SpawnedBlocks"),
    }
    local seen = {}
    local function tryApplyTarget(target)
        if not target or seen[target] then return end
        if target:IsA("BasePart") or target:IsA("Model") then
            seen[target] = true
            applyTargetFn(target)
        end
    end
    for _, folder in ipairs(folders) do
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("BasePart") or child:IsA("Model") then
                    tryApplyTarget(child)
                else
                    for _, desc in ipairs(child:GetDescendants()) do
                        if desc:IsA("BasePart") then
                            local candidate = resolveTargetFromInstanceFn and resolveTargetFromInstanceFn(desc) or desc
                            tryApplyTarget(candidate or desc)
                        elseif desc:IsA("Model") then
                            tryApplyTarget(desc)
                        end
                    end
                end
            end
        end
    end
end

function EspRuntime.createOreVisuals(renderPart, target, color, oreName, useAdornment)
    local visual = nil
    if useAdornment then
        local box = Instance.new("BoxHandleAdornment")
        box.Name = "UH_ESP_Box"
        box.Adornee = renderPart
        box.AlwaysOnTop = true
        box.ZIndex = 10
        box.Color3 = color
        box.Transparency = 0.72
        box.Size = renderPart.Size + Vector3.new(0.05, 0.05, 0.05)
        box.Parent = renderPart
        visual = box
    else
        local hl = Instance.new("Highlight")
        hl.Name                = "UH_ESP_Highlight"
        hl.FillColor           = color
        hl.OutlineColor        = color
        hl.FillTransparency    = 0.78
        hl.OutlineTransparency = 0.05
        hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee             = target
        hl.Parent              = target
        visual = hl
    end

    local bb = Instance.new("BillboardGui")
    bb.Name        = "UH_ESP_Billboard"
    bb.Size        = UDim2.new(0, 120, 0, 36)
    bb.StudsOffset = Vector3.new(0, 3.8, 0)
    bb.AlwaysOnTop = true
    bb.Adornee     = renderPart
    bb.Parent      = target

    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3             = color
    lbl.TextStrokeColor3       = Color3.new(0, 0, 0)
    lbl.TextStrokeTransparency = 0
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = 13
    lbl.TextScaled             = false
    lbl.Text                   = oreName
    lbl.Parent                 = bb

    return { visual = visual, billboard = bb, label = lbl }
end

function EspRuntime.bindFolder(folder, isEnabledFn, applyTargetFn, resolveTargetFromInstanceFn)
    local conns = {}
    if not folder or type(applyTargetFn) ~= "function" then
        return conns
    end

    local function enabled()
        if type(isEnabledFn) ~= "function" then
            return true
        end
        return isEnabledFn() == true
    end

    conns[#conns + 1] = folder.ChildAdded:Connect(function(child)
        if not enabled() then return end
        if child:IsA("BasePart") or child:IsA("Model") then
            task.wait(0.1)
            applyTargetFn(child)
        else
            task.delay(0.12, function()
                if not enabled() then return end
                if not child or not child.Parent then return end
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        local candidate = resolveTargetFromInstanceFn and resolveTargetFromInstanceFn(desc) or desc
                        applyTargetFn(candidate or desc)
                    elseif desc:IsA("Model") then
                        applyTargetFn(desc)
                    end
                end
            end)
        end
    end)

    conns[#conns + 1] = folder.DescendantAdded:Connect(function(desc)
        if not enabled() then return end
        if not (desc:IsA("BasePart") or desc:IsA("Model")) then return end
        task.defer(function()
            if not enabled() then return end
            if not desc or not desc.Parent then return end
            local candidate = resolveTargetFromInstanceFn and resolveTargetFromInstanceFn(desc) or desc
            applyTargetFn(candidate or desc)
        end)
    end)

    return conns
end

return EspRuntime
