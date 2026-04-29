return function(Window, scriptInfo)
    -- Keep legacy behavior intact while transitioning to modular files.
    local legacyUrl = "https://raw.githubusercontent.com/valrinx/Roblox--Library/refs/heads/main/modules/Ultimate%20Mining%20Tycoon?v=umt-legacy-bridge-1"
    local raw = game:HttpGet(legacyUrl)
    local compiled, compileErr = loadstring(raw)
    assert(compiled, "legacy compile failed: " .. tostring(compileErr))

    local legacyModule = compiled()
    assert(type(legacyModule) == "function", "legacy module must return function")
    return legacyModule(Window, scriptInfo)
end
