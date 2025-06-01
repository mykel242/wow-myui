-- DPSWindow.lua
-- DPS tracking window using BaseMeterWindow with integrated pixel meter

local addonName, addon = ...

-- DPS Window configuration
local dpsConfig = {
    frameName = "DPSWindow",
    label = "DPS",
    labelColor = { r = 1, g = 0.2, b = 0.2 }, -- Red
    positionKey = "dpsWindowPosition",
    visibilityKey = "showDPSWindow",
    showAbsorb = false,           -- Hide absorb for DPS
    showOverheal = false,         -- Hide overheal for DPS
    enablePixelMeterGrid = false, -- Disable built-in pixel meter (using WorkingPixelMeter instead)
    defaultPosition = {
        point = "RIGHT",
        relativePoint = "RIGHT",
        xOffset = -100,
        yOffset = 100
    },
    getMainValue = function() return addon.CombatTracker:GetRollingDPS() end,
    getMaxValue = function() return addon.CombatTracker:GetMaxDPS() end,
    getTotalValue = function() return addon.CombatTracker:GetTotalDamage() end
}

-- Create DPS Window instance
addon.DPSWindow = addon.BaseMeterWindow:New(dpsConfig)

-- Initialize DPS Window
function addon.DPSWindow:Initialize()
    addon.BaseMeterWindow.Initialize(self)
end

-- Function to position pixel meter relative to window
local function PositionPixelMeter()
    if addon.dpsPixelMeter and addon.dpsPixelMeter.frame and addon.DPSWindow.frame then
        addon.dpsPixelMeter.frame:ClearAllPoints()
        addon.dpsPixelMeter.frame:SetPoint("BOTTOM", addon.DPSWindow.frame, "TOP", 0, 0)
    end
end

-- Override Show to also show pixel meter
function addon.DPSWindow:Show()
    -- Call parent Show method
    addon.BaseMeterWindow.Show(self)

    -- Create and show pixel meter if it doesn't exist
    if not addon.dpsPixelMeter and addon.WorkingPixelMeter then
        addon.dpsPixelMeter = addon.WorkingPixelMeter:New({
            cols = 20,
            rows = 1,
            pixelSize = 10,
            gap = 1,
            maxValue = 15000,
            meterName = "DPS" -- For debug/commands
        })
        addon.dpsPixelMeter:SetValueSource(function()
            return addon.CombatTracker:GetRollingDPS()
        end)
    end

    -- Show and position pixel meter
    if addon.dpsPixelMeter then
        addon.dpsPixelMeter:Show()
        PositionPixelMeter()
    end

    -- Hook into the drag events to keep pixel meter positioned
    if self.frame and not self.frame.dragHooked then
        local originalOnDragStop = self.frame:GetScript("OnDragStop")
        self.frame:SetScript("OnDragStop", function(frame)
            -- Call original drag stop handler
            if originalOnDragStop then
                originalOnDragStop(frame)
            end
            -- Reposition pixel meter after drag
            PositionPixelMeter()
        end)
        self.frame.dragHooked = true
    end
end

-- Override Hide to also hide pixel meter
function addon.DPSWindow:Hide()
    -- Hide pixel meter first
    if addon.dpsPixelMeter then
        addon.dpsPixelMeter:Hide()
    end

    -- Call parent Hide method
    addon.BaseMeterWindow.Hide(self)
end
