-- HPSWindow.lua
-- HPS tracking window using BaseMeterWindow with integrated pixel meter

local addonName, addon = ...

-- HPS Window configuration
local hpsConfig = {
    frameName = "HPSWindow",
    label = "HPS",
    labelColor = { r = 0, g = 1, b = 0.5 },
    positionKey = "hpsWindowPosition",
    visibilityKey = "showHPSWindow",
    showAbsorb = true,
    showOverheal = true,
    defaultPosition = {
        point = "RIGHT",
        relativePoint = "RIGHT",
        xOffset = -100,
        yOffset = 0
    },
    getMainValue = function() return addon.CombatData:GetDisplayHPS() end,
    getMaxValue = function() return addon.CombatData:GetMaxHPS() end,
    getTotalValue = function() return addon.CombatData:GetTotalHealing() end,
    getAbsorbValue = function() return addon.CombatData:GetTotalAbsorb() end
}

-- Create HPS Window instance
addon.HPSWindow = addon.BaseMeterWindow:New(hpsConfig)

-- Initialize HPS Window (DISABLED DURING MODULARIZATION)
function addon.HPSWindow:Initialize()
    --[[
    DISABLED DURING MODULARIZATION - PRESERVE FOR RE-ENABLE
    addon.BaseMeterWindow.Initialize(self)
    --]]
    
    addon:Debug("HPSWindow initialization disabled during modularization")
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
    addon.BaseMeterWindow.Show(self)

    if not addon.hpsPixelMeter and addon.WorkingPixelMeter then
        addon.hpsPixelMeter = addon.WorkingPixelMeter:New({
            cols = 20,
            rows = 1,
            pixelSize = 10,
            gap = 1,
            meterName = "HPS"
        })
        addon.hpsPixelMeter:SetValueSource(function()
            return addon.CombatData:GetDisplayHPS()
        end)
    end

    if addon.hpsPixelMeter then
        addon.hpsPixelMeter:Show()
        PositionPixelMeter()
        
        -- Update focus manager registration to include pixel meter
        if addon.FocusManager and self.frame then
            addon.FocusManager.registeredWindows[self.frame].pixelMeter = addon.hpsPixelMeter
            addon.hpsPixelMeter:SyncStrataWithParent()
        end
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
