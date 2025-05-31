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

    print("BaseMeterWindow:Create() starting for", self.config.label)

    -- Calculate pixel meter width to match our frame width
    local pixelMeterWidth = (20 * 8) + (19 * 1) + 8 -- 20 cols * 8px + 19 gaps * 1px + 8px padding

    local frame = CreateFrame("Frame", addonName .. self.config.frameName, UIParent)
    frame:SetSize(pixelMeterWidth, 85) -- Match pixel meter width, reduce height
    print("Created main frame with width:", pixelMeterWidth)

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
    print("Frame positioned")

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
    print("Frame made draggable")

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
    print("Backgrounds created")

    -- Main number (large, top-left with margin, aligned with label) - CUSTOM FONT
    local mainText = frame:CreateFontString(nil, "OVERLAY")
    mainText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 20, "OUTLINE")
    mainText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    mainText:SetText("0")
    mainText:SetTextColor(1, 1, 1, 1)
    mainText:SetJustifyH("LEFT")
    frame.mainText = mainText
    print("Main text created with custom font")

    -- Label (top right, aligned with main number)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    label:SetText(self.config.label)
    label:SetTextColor(self.config.labelColor.r, self.config.labelColor.g, self.config.labelColor.b, 1)
    label:SetJustifyH("RIGHT")
    print("Label created")

    -- Store frame reference
    self.frame = frame

    -- Meter mode indicator (small text showing current max and mode)
    local meterIndicator = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    meterIndicator:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4) -- Bottom left near reset button
    meterIndicator:SetText("15.0K (auto)")                           -- Remove "max:" prefix
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
    texture:SetTexture("Interface\\AddOns\\myui2\\refresh-icon") -- Your custom icon path
    texture:SetAlpha(0.6)

    -- Button highlight
    local highlight = resetBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(resetBtn)
    highlight:SetTexture("Interface\\AddOns\\myui2\\refresh-icon") -- Your custom icon path
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

        -- Also reset the combat stats for this meter type
        if addon.CombatTracker then
            addon.CombatTracker:ResetDisplayStats()
        end

        print(self.config.label .. " meter reset")
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
    local maxValue = frame:CreateFontString(nil, "OVERLAY")
    maxValue:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    maxValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -44)
    maxValue:SetSize(120, 12) -- Wider and set height
    maxValue:SetText("0 max")
    maxValue:SetTextColor(0.8, 0.8, 0.8, 1)
    maxValue:SetJustifyH("LEFT")
    maxValue:SetWordWrap(false) -- Prevent wrapping
    frame.maxValue = maxValue

    -- Row 2: Left side (total value with inline label) - CUSTOM FONT
    local totalValue = frame:CreateFontString(nil, "OVERLAY")
    totalValue:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    totalValue:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -56)
    totalValue:SetSize(120, 12) -- Wider and set height
    totalValue:SetText("0 total")
    totalValue:SetTextColor(0.8, 0.8, 0.8, 1)
    totalValue:SetJustifyH("LEFT")
    totalValue:SetWordWrap(false) -- Prevent wrapping
    frame.totalValue = totalValue

    -- Overheal (only if enabled in config) - Right side, top position - CUSTOM FONT
    if self.config.showOverheal == true then
        print("Creating overheal stats...")
        local overhealValue = frame:CreateFontString(nil, "OVERLAY")
        overhealValue:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
        overhealValue:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -44) -- More space from right edge
        overhealValue:SetSize(100, 12)                                 -- Wider and set height to prevent wrapping
        overhealValue:SetText("0% overheal")                           -- Include label in the text
        overhealValue:SetTextColor(0.8, 0.8, 0.8, 1)
        overhealValue:SetJustifyH("RIGHT")
        overhealValue:SetWordWrap(false) -- Explicitly disable word wrapping
        frame.overhealValue = overhealValue
        print("Overheal stats created")
    end

    frame:Hide()

    if addon.db[self.config.visibilityKey] then
        frame:Show()
    end

    print("BaseMeterWindow:Create() completed for", self.config.label)
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

    -- Update main number
    if self.frame.mainText then
        self.frame.mainText:SetText(addon.CombatTracker:FormatNumber(mainValue))
    else
        print("ERROR: mainText is nil in UpdateDisplay")
    end

    -- Update secondary stats with inline labels (no floating labels)
    if self.frame.maxValue then
        local formattedMax = addon.CombatTracker:FormatNumber(maxValue)
        self.frame.maxValue:SetText(formattedMax .. " max")
    else
        print("ERROR: maxValue is nil in UpdateDisplay for", self.config.label)
    end

    if self.frame.totalValue then
        local formattedTotal = addon.CombatTracker:FormatNumber(totalValue)
        self.frame.totalValue:SetText(formattedTotal .. " total")
    else
        print("ERROR: totalValue is nil in UpdateDisplay for", self.config.label)
    end

    -- Update overheal if enabled AND the UI element exists (inline label format)
    if self.config.showOverheal == true and self.frame.overhealValue then
        local overhealPercent = 0
        local effectiveHealing = totalHealing
        if overhealValue > 0 and effectiveHealing > 0 then
            overhealPercent = math.floor((overhealValue / (effectiveHealing + overhealValue)) * 100)
        end
        self.frame.overhealValue:SetText(overhealPercent .. "% overheal")
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
