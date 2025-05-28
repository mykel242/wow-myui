-- BaseMeterWindow.lua
-- Shared base class for DPS and HPS meter windows

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

    local frame = CreateFrame("Frame", addonName .. self.config.frameName, UIParent)
    frame:SetSize(160, 80)

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

    -- Main number (large, top-left with margin, aligned with label)
    local mainText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mainText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    mainText:SetText("0")
    mainText:SetTextColor(1, 1, 1, 1)
    mainText:SetJustifyH("LEFT")
    frame.mainText = mainText

    -- Label (top right, aligned with main number)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    label:SetText(self.config.label)
    label:SetTextColor(self.config.labelColor.r, self.config.labelColor.g, self.config.labelColor.b, 1)
    label:SetJustifyH("RIGHT")

    -- Secondary stats in 4 columns with proper alignment
    -- Row 1: Left side (max value and label)
    local maxValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 20)
    maxValue:SetSize(45, 0) -- Wider for larger numbers
    maxValue:SetText("0")
    maxValue:SetTextColor(0.8, 0.8, 0.8, 1)
    maxValue:SetJustifyH("RIGHT")
    frame.maxValue = maxValue

    local maxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLabel:SetPoint("LEFT", maxValue, "RIGHT", 2, 0)
    maxLabel:SetText("max")
    maxLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    maxLabel:SetJustifyH("LEFT")

    -- Row 2: Left side (total value and label)
    local totalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    totalValue:SetSize(45, 0) -- Same width as max
    totalValue:SetText("0")
    totalValue:SetTextColor(0.8, 0.8, 0.8, 1)
    totalValue:SetJustifyH("RIGHT")
    frame.totalValue = totalValue

    local totalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("LEFT", totalValue, "RIGHT", 2, 0)
    totalLabel:SetText("total")
    totalLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    totalLabel:SetJustifyH("LEFT")

    -- Absorb (only if enabled in config) - Right side
    if self.config.showAbsorb == true then
        local absorbValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        absorbValue:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -50, 20)
        absorbValue:SetSize(25, 0) -- Width for absorb numbers
        absorbValue:SetText("0")
        absorbValue:SetTextColor(0.8, 0.8, 0.8, 1)
        absorbValue:SetJustifyH("RIGHT")
        frame.absorbValue = absorbValue

        local absorbLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        absorbLabel:SetPoint("LEFT", absorbValue, "RIGHT", 2, 0)
        absorbLabel:SetText("absorb")
        absorbLabel:SetTextColor(0.8, 0.8, 0.8, 1)
        absorbLabel:SetJustifyH("LEFT")
    end

    -- Overheal (only if enabled in config) - Right side
    if self.config.showOverheal == true then
        local overhealValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        overhealValue:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -50, 8)
        overhealValue:SetSize(25, 0) -- Width for percentage
        overhealValue:SetText("0%")
        overhealValue:SetTextColor(0.8, 0.8, 0.8, 1)
        overhealValue:SetJustifyH("RIGHT")
        frame.overhealValue = overhealValue

        local overhealLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        overhealLabel:SetPoint("LEFT", overhealValue, "RIGHT", 2, 0)
        overhealLabel:SetText("overheal")
        overhealLabel:SetTextColor(0.8, 0.8, 0.8, 1)
        overhealLabel:SetJustifyH("LEFT")
    end

    frame:Hide()
    self.frame = frame

    if addon.db[self.config.visibilityKey] then
        frame:Show()
    end
end

-- Update the display with current combat data
function BaseMeterWindow:UpdateDisplay()
    if not self.frame then return end

    local inCombat = addon.CombatTracker:IsInCombat()
    local mainValue = self.config.getMainValue()
    local maxValue = self.config.getMaxValue()
    local totalValue = self.config.getTotalValue()
    local absorbValue = addon.CombatTracker:GetTotalAbsorb()
    local overhealValue = addon.CombatTracker:GetTotalOverheal()
    local totalHealing = addon.CombatTracker:GetTotalHealing()

    -- Always show the most recent values (never reset to 0 unless new combat starts)

    -- Update main number
    self.frame.mainText:SetText(addon.CombatTracker:FormatNumber(mainValue))

    -- Update secondary stats
    self.frame.maxValue:SetText(addon.CombatTracker:FormatNumber(maxValue))
    self.frame.totalValue:SetText(addon.CombatTracker:FormatNumber(totalValue))

    -- Update absorb if enabled
    if self.config.showAbsorb == true and self.frame.absorbValue then
        self.frame.absorbValue:SetText(addon.CombatTracker:FormatNumber(absorbValue))
    end

    -- Update overheal if enabled
    if self.config.showOverheal == true and self.frame.overhealValue then
        local overhealPercent = 0
        local effectiveHealing = totalHealing -- This is healing without overheal
        if overhealValue > 0 and effectiveHealing > 0 then
            -- Overheal % = overheal / (effective healing + overheal)
            overhealPercent = math.floor((overhealValue / (effectiveHealing + overhealValue)) * 100)
        end
        self.frame.overhealValue:SetText(overhealPercent .. "%")
    end

    -- Simple alpha based on combat state - no timers
    if inCombat then
        self.frame.mainText:SetAlpha(1.0)  -- Full opacity in combat
    else
        self.frame.mainText:SetAlpha(0.25) -- Faded when out of combat
    end
end

-- Show the window
function BaseMeterWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    if addon.db then
        addon.db[self.config.visibilityKey] = true
    end
end

-- Hide the window
function BaseMeterWindow:Hide()
    if self.frame then
        self.frame:Hide()
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
