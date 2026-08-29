-- Live Luau test harness for the AOTR Family Roll controller.
-- The runner injects local MODULE_SOURCE before evaluating this file.

assert(type(MODULE_SOURCE) == "string", "MODULE_SOURCE was not injected")

local chunk, compileError = loadstring(MODULE_SOURCE)
assert(chunk, "module compile failed: " .. tostring(compileError))

local moduleFactory = chunk()
assert(type(moduleFactory) == "function", "module must return a function")

local testMode = {}
local ok, invokeError = pcall(function()
    moduleFactory({}, {testMode = testMode})
end)
assert(ok, "module test seam failed: " .. tostring(invokeError))
assert(type(testMode.newController) == "function", "module did not expose the controller test seam")
assert(type(testMode.activateButton) == "function", "module did not expose the button activation test seam")

local firedSignal
local fakeButton = {
    MouseButton1Click = {name = "MouseButton1Click"},
    Activated = {name = "Activated"},
}
local activated, activationError = testMode.activateButton(fakeButton, function(signal)
    firedSignal = signal
end)
assert(activated, "button activation fallback failed: " .. tostring(activationError))
assert(firedSignal == fakeButton.MouseButton1Click, "button activation did not prefer MouseButton1Click")

local currentFamily = "SMITH (Rare)"
local rollCount = 0
local controller = testMode.newController({
    getCurrentFamily = function()
        return currentFamily
    end,
    activateRoll = function()
        rollCount = rollCount + 1
        currentFamily = "Yeager (Legendary)"
    end,
    notify = function() end,
})

controller:setTarget("  smith  ")
controller:setEnabled(true)
controller:step()
assert(rollCount == 0, "controller rolled even though the current Family already matched")
assert(controller:isEnabled() == false, "controller did not stop when the current Family matched")

controller:setTarget("YEAGER")
controller:setEnabled(true)
controller:step()
assert(rollCount == 1, "controller did not activate one roll when the target was absent")
assert(controller:isEnabled() == true, "controller stopped before observing the new roll result")
controller:step()
assert(controller:isEnabled() == false, "controller did not stop after observing the target Family")

controller:setTarget("   ")
controller:setEnabled(true)
controller:step()
assert(rollCount == 1, "controller rolled without a valid target Family")
assert(controller:isEnabled() == false, "controller stayed enabled without a valid target Family")

return {
    passed = true,
    rollCount = rollCount,
    observedFamily = currentFamily,
}
