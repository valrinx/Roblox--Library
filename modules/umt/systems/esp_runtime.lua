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

return EspRuntime
