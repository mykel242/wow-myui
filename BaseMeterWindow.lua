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

-- Create the meter window - COMPLETE FUNCTION REPLACEMENT (OPTIMIZED FONT SETTING)
function BaseMeterWindow:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", addonName .. self.config.frameName, UIParent)
    frame:SetSize(210, 80)

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

    -- Font loading with fallback (OPTIMIZED - ONLY SET ONCE)
    local function SetCustomFont(fontString, size)
        -- Don't set font if it's already been set for this fontstring
        if fontString._fontSet then
            return
        end

        local fontPaths = {
            "Interface/AddOns/MyUI/SCP-SB.ttf",
            "Interface\\AddOns\\MyUI\\SCP-SB.ttf",
            "Interface/AddOns/myui2/SCP-SB.ttf",
            "Interface\\AddOns\\myui2\\SCP-SB.ttf"
        }

        local fontSet = false
        for _, fontPath in ipairs(fontPaths) do
            if fontString:SetFont(fontPath, size, "OUTLINE") then
                fontSet = true
                if addon.DEBUG then
                    print("Font loaded successfully: " .. fontPath)
                end
                break
            end
        end

        if not fontSet then
            fontString:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
            if addon.DEBUG then
                print("Using fallback font - SCP-SB.ttf not found")
            end
        end

        -- Mark this fontstring as having its font set
        fontString._fontSet = true
    end

    -- Main number with custom font
    local mainText = frame:CreateFontString(nil, "OVERLAY")
    SetCustomFont(mainText, 18)
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

    -- TIGHTER SECONDARY STATS LAYOUT - SIZED FOR 888.88M

    -- Row 1: Left side (max value and label)
    local maxValue = frame:CreateFontString(nil, "OVERLAY")
    SetCustomFont(maxValue, 11)
    maxValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 20)
    maxValue:SetSize(55, 0)
    maxValue:SetText("0")
    maxValue:SetTextColor(0.8, 0.8, 0.8, 1)
    maxValue:SetJustifyH("RIGHT")
    frame.maxValue = maxValue

    local maxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLabel:SetPoint("LEFT", maxValue, "RIGHT", 1, 0)
    maxLabel:SetText("max")
    maxLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    maxLabel:SetJustifyH("LEFT")

    -- Row 2: Left side (total value and label)
    local totalValue = frame:CreateFontString(nil, "OVERLAY")
    SetCustomFont(totalValue, 11)
    totalValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 8)
    totalValue:SetSize(55, 0)
    totalValue:SetText("0")
    totalValue:SetTextColor(0.8, 0.8, 0.8, 1)
    totalValue:SetJustifyH("RIGHT")
    frame.totalValue = totalValue

    local totalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("LEFT", totalValue, "RIGHT", 1, 0)
    totalLabel:SetText("total")
    totalLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    totalLabel:SetJustifyH("LEFT")

    -- Row 1: Right side (absorb value and label) - PROPERLY ALIGNED
    if self.config.showAbsorb == true then
        local absorbValue = frame:CreateFontString(nil, "OVERLAY")
        SetCustomFont(absorbValue, 11)
        absorbValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 110, 20)
        absorbValue:SetSize(55, 0)
        absorbValue:SetText("0")
        absorbValue:SetTextColor(0.8, 0.8, 0.8, 1)
        absorbValue:SetJustifyH("RIGHT")
        absorbValue:SetWordWrap(false)
        frame.absorbValue = absorbValue

        local absorbLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        absorbLabel:SetPoint("LEFT", absorbValue, "RIGHT", 1, 0)
        absorbLabel:SetText("absorb")
        absorbLabel:SetTextColor(0.8, 0.8, 0.8, 1)
        absorbLabel:SetJustifyH("LEFT")
    end

    -- Row 2: Right side (overheal value and label) - PROPERLY ALIGNED
    if self.config.showOverheal == true then
        local overhealValue = frame:CreateFontString(nil, "OVERLAY")
        SetCustomFont(overhealValue, 11)
        overhealValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 110, 8)
        overhealValue:SetSize(45, 0)
        overhealValue:SetText("0%")
        overhealValue:SetTextColor(0.8, 0.8, 0.8, 1)
        overhealValue:SetJustifyH("RIGHT")
        overhealValue:SetWordWrap(false)
        frame.overhealValue = overhealValue

        local overhealLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        overhealLabel:SetPoint("LEFT", overhealValue, "RIGHT", 1, 0)
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

    -- Update absorb if enabled - FIXED FORMATTING (NO DEBUG SPAM)
    if self.config.showAbsorb == true and self.frame.absorbValue then
        -- Use the same FormatNumber function for consistency
        local formattedAbsorb = addon.CombatTracker:FormatNumber(absorbValue)
        self.frame.absorbValue:SetText(formattedAbsorb)
    end

    -- Update overheal if enabled - FIXED CALCULATION (NO DEBUG SPAM)
    if self.config.showOverheal == true and self.frame.overhealValue then
        local overhealPercent = 0

        -- Calculate overheal percentage correctly
        -- Total healing includes: effective healing + overheal + absorbs
        -- Overheal % = overheal / (total healing including overheal)
        local totalHealingWithOverheal = totalHealing + overhealValue

        if overhealValue > 0 and totalHealingWithOverheal > 0 then
            overhealPercent = math.floor((overhealValue / totalHealingWithOverheal) * 100)
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
