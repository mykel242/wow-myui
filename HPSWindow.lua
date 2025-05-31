-- HPSWindow.lua
-- HPS tracking window using BaseMeterWindow with integrated PixelMeter

local addonName, addon = ...

-- HPS Window configuration
local hpsConfig = {
    frameName = "HPSWindow",
    label = "HPS",
    labelColor = { r = 0, g = 1, b = 0.5 }, -- Teal green
    positionKey = "hpsWindowPosition",
    visibilityKey = "showHPSWindow",
    showAbsorb = true,           -- Show absorb for HPS
    showOverheal = true,         -- Show overheal for HPS
    enablePixelMeterGrid = true, -- Enable the generic pixel meter grid
    defaultPosition = {
        point = "RIGHT",
        relativePoint = "RIGHT",
        xOffset = -100,
        yOffset = 0
    },
    -- Main value functions
    getMainValue = function() return addon.CombatTracker:GetRollingHPS() end,
    getMaxValue = function() return addon.CombatTracker:GetMaxHPS() end,
    getTotalValue = function() return addon.CombatTracker:GetTotalHealing() end,
    -- Pixel Meter Grid configuration
    pixelMeterConfig = {
        cols = 20,
        rows = 1,
        pixelSize = 6,
        gap = 1,
        maxValue = 15000
    },
    -- Pixel Meter Grid value source
    getPixelMeterValue = function() return addon.CombatTracker:GetRollingHPS() end
}

-- Create HPS Window instance
addon.HPSWindow = addon.BaseMeterWindow:New(hpsConfig)

-- Initialize HPS Window
function addon.HPSWindow:Initialize()
    addon.BaseMeterWindow.Initialize(self)
end
