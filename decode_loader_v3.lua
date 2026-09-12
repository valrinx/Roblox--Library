--[[
    Decode ContainerLab2 Loader - Simple Method
    1. Run this script first
    2. It fetches and executes the Loader in a safe environment
    3. All decoded strings are printed to console
]]

print("Fetching ContainerLab2 Loader...")
local ok, code = pcall(function()
    return game:HttpGet("https://raw.githubusercontent.com/ContainerLab2/Container/refs/heads/main/Loader")
end)

if not ok or not code then
    warn("Failed to fetch: " .. tostring(code))
    return
end

print("Loader fetched (" .. #code .. " bytes)")
print("Executing with string decode monitoring...")
print("")

-- Execute the Loader but intercept decoded strings
-- The Loader returns a function when called with ({},{}) args
local chunk, err = loadstring(code)
if not chunk then
    warn("Loadstring error: " .. tostring(err))
    return
end

-- The Loader's first IIFE creates a decode table
-- We can hook it by running with a fake environment
local result = chunk()

-- If it returns a table of decoded strings, print them
if type(result) == "table" then
    print("=== Decoded Strings ===")
    for k, v in pairs(result) do
        if type(v) == "string" then
            local safe = v:gsub("[\0-\31]", ".")
            print(string.format("  [%s] = %s", tostring(k), safe))
        end
    end
elseif type(result) == "function" then
    -- It returned a loader function - call it to trigger all decodes
    print("Loader returned a function, triggering decode...")
    pcall(result, {}, {registerCleanup = function() end})
    print("Done - check above output for decoded strings")
else
    print("Unexpected return type: " .. type(result))
end
