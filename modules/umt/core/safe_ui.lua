local SafeUI = {}

function SafeUI.wrapNotify(rawRayfieldNotify)
    if type(rawRayfieldNotify) ~= "function" then
        return function() end
    end
    return function(payload)
        pcall(function()
            rawRayfieldNotify(nil, payload)
        end)
    end
end

function SafeUI.patchRayfield(Rayfield)
    local raw = Rayfield and Rayfield.Notify
    if type(raw) ~= "function" then
        return
    end
    Rayfield.Notify = function(_, payload)
        pcall(function()
            raw(_, payload)
        end)
    end
end

function SafeUI.safeSetText(element, text)
    if not element or type(element.Set) ~= "function" then
        return false
    end
    local ok = pcall(function()
        element:Set(tostring(text or ""))
    end)
    return ok
end

return SafeUI
