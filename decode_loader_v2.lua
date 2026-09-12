--[[
    Decode ContainerLab2 Loader strings
    Paste this into executor BEFORE running the Loader
    It hooks the __index metamethod to print decoded strings
]]

-- Save original environment
local originalDecode = nil

-- Hook approach: execute the Loader's first IIFE and capture results
local ok, loaderCode = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/ContainerLab2/Container/refs/heads/main/Loader")
end)

if not ok or not loaderCode then
    warn("Failed to fetch Loader")
    return
end

-- Extract just the first decode IIFE (between the two `local` declarations)
local start = loaderCode:find("local _O_IOIIIOI_0lOI00l_0OIIII1=")
local finish = loaderCode:find("local __l101lI1II_0OlO__101_l=")

if not start or not finish then
    warn("Could not find decode boundaries")
    return
end

-- Get just the first IIFE
local firstIIFE = loaderCode:sub(start, finish - 1)

-- Add print hooks
local patched = firstIIFE:gsub(
    "return _I0I0I11llOIIO0I0I1_0O10OO1l1_0 end",
    [[
    -- Print all decoded strings
    print("=== ContainerLab2 Loader Decoded Strings ===")
    for k, v in pairs(_I0I0I11llOIIO0I0I1_0O10OO1l1_0) do
        if type(v) == "string" then
            print(string.format("[%s] = %s", tostring(k), v))
        end
    end
    print("=== End ===")
    return _I0I0I11llOIIO0I0I1_0O10OO1l1_0 end]]
)

-- Execute
local fn, err = loadstring(patched)
if fn then
    local result = fn()
    if result then
        -- Trigger lazy decode by accessing all keys
        print("\n=== Triggering lazy decode ===")
        for i = 1, 93 do
            local v = result[i]
            if v then
                print(string.format("  [%2d] = %s", i, v))
            end
        end
    end
else
    warn("Loadstring failed: " .. tostring(err))
end
