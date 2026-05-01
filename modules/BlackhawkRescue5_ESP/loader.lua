--[[
    Blackhawk Rescue Mission 5 - ESP Loader
    Simple loader to initialize the ESP system
--]]

-- Load ESP Module
local ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/valrinx/Roblox--Library/main/modules/BlackhawkRescue5_ESP/main.lua"))()

-- Initialize
ESP:Initialize()

-- Example hotkeys (using your preferred input method)
--[[
    Toggle ESP: F1
    Toggle Player ESP: F2
    Toggle Zombie ESP: F3
    Toggle AI ESP: F4
--]]

-- Optional: Create simple UI or connect to existing UI framework
print("[Blackhawk Loader] ESP loaded successfully!")
print("[Blackhawk Loader] Commands available:")
print("  ESP:Toggle() - Toggle all ESP")
print("  ESP:TogglePlayerESP() - Toggle Player ESP")
print("  ESP:ToggleZombieESP() - Toggle Zombie ESP")
print("  ESP:ToggleAIESP() - Toggle AI ESP")
