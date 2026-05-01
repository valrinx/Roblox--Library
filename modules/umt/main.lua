return function(Window, scriptInfo)
    local BASE_URL = "https://raw.githubusercontent.com/valrinx/Roblox--Library/refs/heads/main/modules/umt/"

    local function notify(message)
        local rayfield = scriptInfo and scriptInfo.hubRayfield
        if not rayfield or type(rayfield.Notify) ~= "function" then
            return
        end
        pcall(function()
            rayfield:Notify({
                Title = "Ultimate Mining Tycoon",
                Content = tostring(message),
                Duration = 5,
                Image = "circle-alert",
            })
        end)
    end

    local function loadRemote(relativePath)
        local separator = string.find(relativePath, "?", 1, true) and "&" or "?"
        local versionedPath = relativePath .. separator .. "v=umt-modular-1"
        local raw = game:HttpGet(BASE_URL .. versionedPath)
        local chunk, compileErr = loadstring(raw)
        assert(chunk, "compile failed for " .. relativePath .. ": " .. tostring(compileErr))
        return chunk()
    end

    local okLoad, bridgeOrErr = pcall(function()
        return loadRemote("legacy_bridge.lua")
    end)
    if not okLoad then
        warn("[Ultimate Mining Tycoon] entry load failed: " .. tostring(bridgeOrErr))
        notify("Entry load failed: " .. tostring(bridgeOrErr))
        return
    end

    if type(bridgeOrErr) ~= "function" then
        warn("[Ultimate Mining Tycoon] legacy bridge must return function.")
        notify("Bridge format invalid.")
        return
    end

    local okRun, runErr = pcall(function()
        bridgeOrErr(Window, scriptInfo)
    end)
    if not okRun then
        warn("[Ultimate Mining Tycoon] runtime failed: " .. tostring(runErr))
        -- Try to get more details about the error
        local errStr = tostring(runErr)
        if errStr:find("attempt to perform arithmetic") then
            warn("[DEBUG] Arithmetic error detected. Stack trace:")
            warn(debug.traceback())
        end
        notify("Runtime failed: " .. errStr:sub(1, 100))
    end
end
