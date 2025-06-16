-- BaseMeterWindow.lua
-- Shared base class for DPS and HPS meter windows with PixelMeter support

local addonName, addon = ...

-- Base Meter Window module
addon.BaseMeterWindow = {}
local BaseMeterWindow = addon.BaseMeterWindow

-- Create a new meter window instance
function BaseMeterWindow:New(config)
    local instance = {}
    setmetatable(instance, { __index = self })

    -- Store configuration
    instance.config = config
    instance.frame = nil

    return instance
end

-- Initialize window defaults
function BaseMeterWindow:Initialize()
    if addon.db[self.config.positionKey] == nil then
        addon.db[self.config.positionKey] = nil
    end
    if addon.db[self.config.visibilityKey] == nil then
        addon.db[self.config.visibilityKey] = false
    end
end

-- Create the meter window
function BaseMeterWindow:Create()
    if self.frame then return end

    addon:Debug("BaseMeterWindow:Create() starting for", self.config.label)

    -- Set desired window width
    local windowWidth = 220
    local frame = CreateFrame("Frame", addonName .. self.config.frameName, UIParent)
    frame:SetSize(windowWidth, 85) -- Use fixed 220px width
    addon:Debug("Created main frame with width:", windowWidth)


    -- Restore saved position or use default
    if addon.db[self.config.positionKey] then
        local pos = addon.db[self.config.positionKey]
        frame:SetPoint(
            pos.point or self.config.defaultPosition.point,
            UIParent,
            pos.relativePoint or self.config.defaultPosition.relativePoint,
            pos.xOffset or self.config.defaultPosition.xOffset,
            pos.yOffset or self.config.defaultPosition.yOffset
        )
    else
        frame:SetPoint(
            self.config.defaultPosition.point,
            UIParent,
            self.config.defaultPosition.relativePoint,
            self.config.defaultPosition.xOffset,
            self.config.defaultPosition.yOffset
        )
    end
    addon:Debug("Frame positioned")


    -- Make it draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    local instance = self
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        addon.db[instance.config.positionKey] = {
            point = point,
            relativePoint = relativePoint,
            xOffset = xOfs,
            yOffset = yOfs
        }
    end)
    addon:Debug("Frame made draggable")


    -- Background (black semi-transparent)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.7)

    -- Top section background (slightly more opaque black)
    local topBg = frame:CreateTexture(nil, "BORDER")
    topBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBg:SetHeight(32)
    topBg:SetColorTexture(0, 0, 0, 0.8)
    addon:Debug("Backgrounds created")

    -- Main number (large, top-left with margin, aligned with label) - CUSTOM FONT
    local mainText = frame:CreateFontString(nil, "OVERLAY")
    mainText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 20, "OUTLINE")
    mainText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    mainText:SetText("0")
    mainText:SetTextColor(1, 1, 1, 1)
    mainText:SetJustifyH("LEFT")
    frame.mainText = mainText
    addon:Debug("Main text created with custom font")

    -- Label (top right, aligned with main number)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    label:SetText(self.config.label)
    label:SetTextColor(self.config.labelColor.r, self.config.labelColor.g, self.config.labelColor.b, 1)
    label:SetJustifyH("RIGHT")
    
    -- Calculation method indicator (smaller text under label)
    local methodIndicator = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    methodIndicator:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -2)
    methodIndicator:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 8, "OUTLINE")
    methodIndicator:SetText("Rolling")
    methodIndicator:SetTextColor(0.7, 0.7, 0.7, 0.8)
    methodIndicator:SetJustifyH("RIGHT")
    
    self.methodIndicator = methodIndicator
    self.label = label
    
    addon:Debug("Label and method indicator created")

    -- Store frame reference
    self.frame = frame
    
    -- Register with focus management system (meter windows use LOW default strata)
    if addon.FocusManager then
        addon.FocusManager:RegisterWindow(frame, nil, "LOW")
    end

    -- Meter mode indicator (small text showing current max and mode)
    local meterIndicator = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    meterIndicator:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4) -- Bottom left near reset button
    meterIndicator:SetText("auto")                                   -- No prefix to save space
    meterIndicator:SetTextColor(0, 1, 1, 0.8)                        -- Cyan for auto
    meterIndicator:SetJustifyH("LEFT")
    frame.meterIndicator = meterIndicator

    -- Reset button (small, lower right corner)
    local resetBtn = CreateFrame("Button", nil, frame)
    resetBtn:SetSize(16, 16)
    resetBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)

    -- Button texture (your custom refresh icon)
    local texture = resetBtn:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints(resetBtn)
    texture:SetTexture("Interface\\AddOns\\myui2\\assets\\refresh-icon") -- Your custom icon path
    texture:SetAlpha(0.6)

    -- Button highlight
    local highlight = resetBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(resetBtn)
    highlight:SetTexture("Interface\\AddOns\\myui2\\assets\\refresh-icon") -- Your custom icon path
    highlight:SetAlpha(1.0)

    -- Button functionality
    resetBtn:SetScript("OnClick", function()
        -- Reset the associated pixel meter if it exists
        local meterName = self.config.label:lower() -- "DPS" -> "dps", "HPS" -> "hps"
        local pixelMeter = nil

        if meterName == "dps" and addon.dpsPixelMeter then
            pixelMeter = addon.dpsPixelMeter
        elseif meterName == "hps" and addon.hpsPixelMeter then
            pixelMeter = addon.hpsPixelMeter
        end

        if pixelMeter then
            pixelMeter:ResetMaxValue()
            -- Update the meter indicator immediately
            instance:UpdateMeterIndicator()
        end

        -- Reset the combat stats for this meter type (both peak and totals)
        if addon.CombatTracker then
            -- Reset both combat stats AND the specific meter's peak values
            if meterName == "dps" then
                addon.CombatTracker:ResetDPSStats()
            elseif meterName == "hps" then
                addon.CombatTracker:ResetHPSStats()
            end
        end

        addon:Info(self.config.label .. " meter and peak values reset")
    end)

    -- Tooltip
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Reset " .. instance.config.label .. " Meter")
        GameTooltip:AddLine("Resets max value scaling and combat stats", 1, 1, 1, true)
        GameTooltip:Show()
    end)

    resetBtn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    frame.resetBtn = resetBtn

    -- Secondary stats - redesigned with better alignment and inline labels
    -- Row 1: Left side (max value with inline label) - CUSTOM FONT

    addon:Debug("Creating maxValue...")

    local maxValue = frame:CreateFontString(nil, "OVERLAY")
    maxValue:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    maxValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -40) -- Just below main counter area
    maxValue:SetSize(106, 0)                               -- Wider to accommodate "123K max" format
    maxValue:SetText("0 peak")                             -- Include label in the text
    maxValue:SetTextColor(0.8, 0.8, 0.8, 1)
    maxValue:SetJustifyH("LEFT")
    frame.maxValue = maxValue

    -- Row 2: Left side (total value with inline label) - CUSTOM FONT
    addon:Debug("Creating totalValue...")
    local totalValue = frame:CreateFontString(nil, "OVERLAY")
    totalValue:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    totalValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -52) -- Below peak counter
    totalValue:SetSize(106, 0)                               -- Wider to accommodate "456K total" format
    totalValue:SetText("0 total")                            -- Include label in the text
    totalValue:SetTextColor(0.8, 0.8, 0.8, 1)
    totalValue:SetJustifyH("LEFT")
    totalValue:SetWordWrap(false)
    frame.totalValue = totalValue

    -- Absorb (only if enabled in config) - Right side, top position - CUSTOM FONT
    if self.config.showAbsorb == true then
        addon:Debug("Creating absorb stats...")
        local absorbValue = frame:CreateFontString(nil, "OVERLAY")
        absorbValue:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
        absorbValue:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -40) -- Top row, right side
        absorbValue:SetSize(106, 0)                                  -- Wider to accommodate "456K absorb" format
        absorbValue:SetText("0 absorb")                              -- Include label in the text
        absorbValue:SetTextColor(0.7, 0.7, 1.0, 1)                   -- Light blue for absorb
        absorbValue:SetJustifyH("RIGHT")
        frame.absorbValue = absorbValue
        addon:Debug("Absorb stats created")
    end

    -- Overheal (only if enabled in config) - Right side, bottom position - CUSTOM FONT
    if self.config.showOverheal == true then
        addon:Debug("Creating overheal stats...")
        local overhealValue = frame:CreateFontString(nil, "OVERLAY")
        overhealValue:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
        -- Position below absorb if absorb is shown, otherwise use top position
        if self.config.showAbsorb == true then
            overhealValue:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -52) -- Bottom row, right side
        else
            overhealValue:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -40) -- Top row, right side
        end
        overhealValue:SetSize(106, 0)                                      -- Wider to accommodate "45% overheal" format
        overhealValue:SetText("0% over")                                   -- Include label in the text
        overhealValue:SetTextColor(0.8, 0.8, 0.8, 1)
        overhealValue:SetJustifyH("RIGHT")
        frame.overhealValue = overhealValue
        addon:Debug("Overheal stats created")
    end

    frame:Hide()

    if addon.db[self.config.visibilityKey] then
        frame:Show()
    end

    addon:Debug("BaseMeterWindow:Create() completed for", self.config.label)
end

-- Update the meter indicator display
function BaseMeterWindow:UpdateMeterIndicator()
    if not self.frame or not self.frame.meterIndicator then return end

    local meterName = self.config.label:lower()
    local pixelMeter = nil

    if meterName == "dps" and addon.dpsPixelMeter then
        pixelMeter = addon.dpsPixelMeter
    elseif meterName == "hps" and addon.hpsPixelMeter then
        pixelMeter = addon.hpsPixelMeter
    end

    if pixelMeter then
        local info = pixelMeter:GetDebugInfo()
        local indicatorText = string.format("%s (%s)",
            addon.CombatTracker:FormatNumber(info.currentMax),
            info.isManual and "manual" or "auto"
        )
        self.frame.meterIndicator:SetText(indicatorText)

        -- Color coding: manual = green, auto = cyan
        if info.isManual then
            self.frame.meterIndicator:SetTextColor(0, 1, 0, 0.8) -- Green for manual
        else
            self.frame.meterIndicator:SetTextColor(0, 1, 1, 0.8) -- Cyan for auto
        end
    else
        self.frame.meterIndicator:SetText("-- (--)")
        self.frame.meterIndicator:SetTextColor(0.6, 0.6, 0.6, 0.8)
    end
end

-- Update the display with current combat data
function BaseMeterWindow:UpdateDisplay()
    if not self.frame then return end

    local inCombat = addon.CombatTracker:IsInCombat()
    local mainValue = self.config.getMainValue()
    local maxValue = self.config.getMaxValue()
    local totalValue = self.config.getTotalValue()
    local overhealValue = addon.CombatTracker:GetTotalOverheal()
    local totalHealing = addon.CombatTracker:GetTotalHealing()
    local absorbValue = self.config.getAbsorbValue and self.config.getAbsorbValue() or 0

    -- Update main number
    if self.frame.mainText then
        self.frame.mainText:SetText(addon.CombatTracker:FormatNumber(mainValue))
    end
    
    -- Update calculation method indicator
    if self.methodIndicator and addon.CombatData and addon.CombatData:GetCalculator() then
        local calculator = addon.CombatData:GetCalculator()
        local currentMethod = calculator:GetCalculationMethod()
        local methods = addon.UnifiedCalculator.CALCULATION_METHODS
        
        local methodText = currentMethod == methods.ROLLING_AVERAGE and "Rolling" or
                          currentMethod == methods.FINAL_TOTAL and "Final" or
                          currentMethod == methods.HYBRID and "Hybrid" or "Unknown"
        
        self.methodIndicator:SetText(methodText)
    end

    -- Update secondary stats with inline labels (no floating labels)
    if self.frame.maxValue then
        local formattedMax = addon.CombatTracker:FormatNumber(maxValue)
        self.frame.maxValue:SetText(formattedMax .. " peak") -- Changed from "max" to "peak"
    else
        addon:Error("ERROR: maxValue is nil in UpdateDisplay for", self.config.label)
    end

    if self.frame.totalValue then
        local formattedTotal = addon.CombatTracker:FormatNumber(totalValue)
        self.frame.totalValue:SetText(formattedTotal .. " total")
    end

    -- Update absorb if enabled AND the UI element exists (inline label format)
    if self.config.showAbsorb == true and self.frame.absorbValue then
        local formattedAbsorb = addon.CombatTracker:FormatNumber(absorbValue)
        self.frame.absorbValue:SetText(formattedAbsorb .. " absorb")
    end

    -- Update overheal if enabled AND the UI element exists (inline label format)
    if self.config.showOverheal == true and self.frame.overhealValue then
        local overhealPercent = 0
        local effectiveHealing = totalHealing
        if overhealValue > 0 and effectiveHealing > 0 then
            overhealPercent = math.floor((overhealValue / (effectiveHealing + overhealValue)) * 100)
        end
        self.frame.overhealValue:SetText(overhealPercent .. "% over")
    end

    -- Update meter indicator
    self:UpdateMeterIndicator()

    -- Simple alpha based on combat state
    if inCombat then
        if self.frame.mainText then
            self.frame.mainText:SetAlpha(1.0)
        end
    else
        if self.frame.mainText then
            self.frame.mainText:SetAlpha(0.25)
        end
    end
end

-- Show the window
function BaseMeterWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    if self.pixelMeter then
        self.pixelMeter:Show()
    end
    if addon.db then
        addon.db[self.config.visibilityKey] = true
    end
end

-- Hide the window
function BaseMeterWindow:Hide()
    if self.frame then
        self.frame:Hide()
    end
    if self.pixelMeter then
        self.pixelMeter:Hide()
    end
    if addon.db then
        addon.db[self.config.visibilityKey] = false
    end
end

-- Toggle the window
function BaseMeterWindow:Toggle()
    if not self.frame then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
