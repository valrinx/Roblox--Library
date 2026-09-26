return function(Window, scriptInfo)
    -- Keep legacy behavior intact while transitioning to modular files.
    local devUrl = "http://localhost:8999/modules/Ultimate%20Mining%20Tycoon"
    local okDev, devRes = pcall(function()
        return game:HttpGet(devUrl)
    end)
    local raw = nil
    if okDev and type(devRes) == "string" and #devRes > 500 and not devRes:sub(1, 15):find("<!DOCTYPE") then
        raw = devRes
    else
        local legacyUrl = "https://raw.githubusercontent.com/valrinx/Roblox--Library/main/modules/Ultimate%20Mining%20Tycoon?v=" .. tostring(os.time())
        raw = game:HttpGet(legacyUrl)
    end
    local compiled, compileErr = loadstring(raw)
    assert(compiled, "legacy compile failed: " .. tostring(compileErr))

    local legacyModule = compiled()
    assert(type(legacyModule) == "function", "legacy module must return function")
    return legacyModule(Window, scriptInfo)
end
