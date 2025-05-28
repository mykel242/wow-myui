-- HPSWindow.lua
-- HPS tracking window using BaseMeterWindow

local addonName, addon = ...

-- HPS Window configuration
local hpsConfig = {
    frameName = "HPSWindow",
    label = "HPS",
    labelColor = { r = 0, g = 1, b = 0.5 }, -- Teal green
    positionKey = "hpsWindowPosition",
    visibilityKey = "showHPSWindow",
    showAbsorb = true,   -- Show absorb for HPS
    showOverheal = true, -- Show overheal for HPS
    defaultPosition = {
        point = "RIGHT",
        relativePoint = "RIGHT",
        xOffset = -100,
        yOffset = 0
    },
    getMainValue = function() return addon.CombatTracker:GetHPS() end,
    getMaxValue = function() return addon.CombatTracker:GetMaxHPS() end,
    getTotalValue = function() return addon.CombatTracker:GetTotalHealing() end
}

-- Create HPS Window instance
addon.HPSWindow = addon.BaseMeterWindow:New(hpsConfig)

-- Initialize HPS Window (required for compatibility)
function addon.HPSWindow:Initialize()
    addon.BaseMeterWindow.Initialize(self)
end
