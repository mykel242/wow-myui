-- DPSWindow.lua
-- DPS tracking window using BaseMeterWindow with integrated pixel meter

local addonName, addon = ...

-- DPS Window configuration
local dpsConfig = {
    frameName = "DPSWindow",
    label = "DPS",
    labelColor = { r = 1, g = 0.2, b = 0.2 },
    positionKey = "dpsWindowPosition",
    visibilityKey = "showDPSWindow",
    showAbsorb = false,
    showOverheal = false,
    defaultPosition = {
        point = "RIGHT",
        relativePoint = "RIGHT",
        xOffset = -100,
        yOffset = 100
    },
    getMainValue = function() return addon.CombatData:GetDisplayDPS() end,
    getMaxValue = function() return addon.CombatData:GetMaxDPS() end,
    getTotalValue = function() return addon.CombatData:GetTotalDamage() end
}

-- Create DPS Window instance
addon.DPSWindow = addon.BaseMeterWindow:New(dpsConfig)

-- Initialize DPS Window (DISABLED DURING MODULARIZATION)
function addon.DPSWindow:Initialize()
    --[[
    DISABLED DURING MODULARIZATION - PRESERVE FOR RE-ENABLE
    addon.BaseMeterWindow.Initialize(self)
    --]]
    
    addon:Debug("DPSWindow initialization disabled during modularization")
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
    addon.BaseMeterWindow.Show(self)

    if not addon.dpsPixelMeter and addon.WorkingPixelMeter then
        addon.dpsPixelMeter = addon.WorkingPixelMeter:New({
            cols = 20,
            rows = 1,
            pixelSize = 10,
            gap = 1,
            meterName = "DPS"
        })
        addon.dpsPixelMeter:SetValueSource(function()
            return addon.CombatData:GetDisplayDPS()
        end)
    end

    if addon.dpsPixelMeter then
        addon.dpsPixelMeter:Show()
        PositionPixelMeter()
        
        -- Update focus manager registration to include pixel meter
        if addon.FocusManager and self.frame then
            addon.FocusManager.registeredWindows[self.frame].pixelMeter = addon.dpsPixelMeter
            addon.dpsPixelMeter:SyncStrataWithParent()
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
function addon.DPSWindow:Hide()
    -- Hide pixel meter first
    if addon.dpsPixelMeter then
        addon.dpsPixelMeter:Hide()
    end

    -- Call parent Hide method
    addon.BaseMeterWindow.Hide(self)
end
