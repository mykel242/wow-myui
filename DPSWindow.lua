-- DPSWindow.lua
-- DPS tracking window using BaseMeterWindow

local addonName, addon = ...

-- DPS Window configuration
local dpsConfig = {
    frameName = "DPSWindow",
    label = "DPS",
    labelColor = { r = 1, g = 0.2, b = 0.2 }, -- Red
    positionKey = "dpsWindowPosition",
    visibilityKey = "showDPSWindow",
    showAbsorb = false,   -- Hide absorb for DPS
    showOverheal = false, -- Hide overheal for DPS
    defaultPosition = {
        point = "RIGHT",
        relativePoint = "RIGHT",
        xOffset = -100,
        yOffset = 100
    },
    getMainValue = function() return addon.CombatTracker:GetDPS() end,
    getMaxValue = function() return addon.CombatTracker:GetMaxDPS() end,
    getTotalValue = function() return addon.CombatTracker:GetTotalDamage() end
}

-- Create DPS Window instance
addon.DPSWindow = addon.BaseMeterWindow:New(dpsConfig)

-- Initialize DPS Window (required for compatibility)
function addon.DPSWindow:Initialize()
    addon.BaseMeterWindow.Initialize(self)
end
