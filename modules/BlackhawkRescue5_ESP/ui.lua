--[[
    Blackhawk Rescue Mission 5 - ESP UI
    Rayfield integration for ESP controls
--]]

local ESP = require(script.Parent.main)

local function CreateUI(Window, runtimeInfo)
    local Tab = Window:CreateTab("ESP", 4483362458)
    
    -- Main Toggle
    Tab:CreateToggle({
        Name = "ESP Enabled",
        CurrentValue = true,
        Callback = function(Value)
            ESP:Toggle(Value)
        end
    })
    
    Tab:CreateSection("ESP Types")
    
    -- Player ESP Toggle
    Tab:CreateToggle({
        Name = "Player ESP",
        CurrentValue = true,
        Callback = function(Value)
            ESP:TogglePlayerESP(Value)
        end
    })
    
    -- Zombie ESP Toggle
    Tab:CreateToggle({
        Name = "Zombie ESP",
        CurrentValue = true,
        Callback = function(Value)
            ESP:ToggleZombieESP(Value)
        end
    })
    
    -- AI ESP Toggle
    Tab:CreateToggle({
        Name = "AI / NPC ESP",
        CurrentValue = true,
        Callback = function(Value)
            ESP:ToggleAIESP(Value)
        end
    })
    
    Tab:CreateSection("Visual Options")
    
    -- Show Name Toggle
    Tab:CreateToggle({
        Name = "Show Name",
        CurrentValue = true,
        Callback = function(Value)
            ESP.Config.ShowName = Value
        end
    })
    
    -- Show Distance Toggle
    Tab:CreateToggle({
        Name = "Show Distance",
        CurrentValue = true,
        Callback = function(Value)
            ESP.Config.ShowDistance = Value
        end
    })
    
    -- Show Health Toggle
    Tab:CreateToggle({
        Name = "Show Health",
        CurrentValue = true,
        Callback = function(Value)
            ESP.Config.ShowHealth = Value
        end
    })
    
    -- Show Box Toggle
    Tab:CreateToggle({
        Name = "Show Box",
        CurrentValue = true,
        Callback = function(Value)
            ESP.Config.ShowBox = Value
        end
    })
    
    -- Show Tracer Toggle
    Tab:CreateToggle({
        Name = "Show Tracer (Line to target)",
        CurrentValue = false,
        Callback = function(Value)
            ESP.Config.ShowTracer = Value
        end
    })
    
    Tab:CreateSection("Settings")
    
    -- Max Distance Slider
    Tab:CreateSlider({
        Name = "Max Distance",
        Range = {100, 5000},
        Increment = 100,
        CurrentValue = 2000,
        Callback = function(Value)
            ESP.Config.MaxDistance = Value
        end
    })
    
    -- Text Size Slider
    Tab:CreateSlider({
        Name = "Text Size",
        Range = {8, 24},
        Increment = 1,
        CurrentValue = 14,
        Callback = function(Value)
            ESP.Config.TextSize = Value
            -- Update existing text objects
            for _, Object in ipairs(ESP.Objects) do
                if Object.Drawings.Name then
                    Object.Drawings.Name.Size = Value
                end
                if Object.Drawings.Distance then
                    Object.Drawings.Distance.Size = Value - 2
                end
                if Object.Drawings.Health then
                    Object.Drawings.Health.Size = Value - 2
                end
            end
        end
    })
    
    -- Info label
    Tab:CreateLabel("Player = Blue | Zombie = Red | AI = Yellow")
    
    return Tab
end

return CreateUI
