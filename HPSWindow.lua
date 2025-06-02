-- HPSWindow.lua
-- HPS tracking window using BaseMeterWindow with integrated pixel meter

local addonName, addon = ...

-- HPS Window configuration
local hpsConfig = {
    frameName = "HPSWindow",
    label = "HPS",
    labelColor = { r = 0, g = 1, b = 0.5 }, -- Teal green
    positionKey = "hpsWindowPosition",
    visibilityKey = "showHPSWindow",
    showAbsorb = true,   -- Enable absorb counter
    showOverheal = true, -- Show overheal for HPS
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
    getAbsorbValue = function() return addon.CombatTracker:GetTotalAbsorb() end -- Add absorb getter
}

-- Create HPS Window instance
addon.HPSWindow = addon.BaseMeterWindow:New(hpsConfig)

-- Initialize HPS Window
function addon.HPSWindow:Initialize()
    addon.BaseMeterWindow.Initialize(self)
end

-- Function to position pixel meter relative to window
local function PositionPixelMeter()
    if addon.hpsPixelMeter and addon.hpsPixelMeter.frame and addon.HPSWindow.frame then
        addon.hpsPixelMeter.frame:ClearAllPoints()
        addon.hpsPixelMeter.frame:SetPoint("BOTTOM", addon.HPSWindow.frame, "TOP", 0, 0)
    end
end

-- Override Show to also show pixel meter
function addon.HPSWindow:Show()
    -- Call parent Show method
    addon.BaseMeterWindow.Show(self)

    -- Create and show pixel meter if it doesn't exist
    if not addon.hpsPixelMeter and addon.WorkingPixelMeter then
        addon.hpsPixelMeter = addon.WorkingPixelMeter:New({
            cols = 20,
            rows = 1,
            pixelSize = 10,
            gap = 1,
            meterName = "HPS" -- For debug/commands
        })
        addon.hpsPixelMeter:SetValueSource(function()
            return addon.CombatTracker:GetRollingHPS()
        end)
    end

    -- Show and position pixel meter
    if addon.hpsPixelMeter then
        addon.hpsPixelMeter:Show()
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
function addon.HPSWindow:Hide()
    -- Hide pixel meter first
    if addon.hpsPixelMeter then
        addon.hpsPixelMeter:Hide()
    end

    -- Call parent Hide method
    addon.BaseMeterWindow.Hide(self)
end
