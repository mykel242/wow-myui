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

    local frame = CreateFrame("Frame", addonName .. self.config.frameName, UIParent)
    frame:SetSize(160, 110) -- Taller to accommodate pixel meter grid
    print("Created main frame")

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

    -- Main number (large, top-left with margin, aligned with label)
    local mainText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mainText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    mainText:SetText("0")
    mainText:SetTextColor(1, 1, 1, 1)
    mainText:SetJustifyH("LEFT")
    frame.mainText = mainText
    print("Main text created")

    -- Label (top right, aligned with main number)
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    label:SetText(self.config.label)
    label:SetTextColor(self.config.labelColor.r, self.config.labelColor.g, self.config.labelColor.b, 1)
    label:SetJustifyH("RIGHT")
    print("Label created")

    -- Store frame reference BEFORE creating PixelMeter
    self.frame = frame
    print("Frame reference stored")

    -- Try to create PixelMeterGrid if config specifies it
    local pixelMeterCreated = false
    if self.config.enablePixelMeterGrid then
        print("PixelMeterGrid enabled, attempting to create...")
        if addon.PixelMeterGrid then
            local success, error = pcall(function()
                self:CreatePixelMeterGrid()
                pixelMeterCreated = true
            end)
            if not success then
                print("ERROR creating PixelMeterGrid:", error)
                pixelMeterCreated = false
            else
                print("PixelMeterGrid created successfully")
            end
        else
            print("ERROR: addon.PixelMeterGrid is nil - PixelMeterGrid.lua not loaded?")
        end
    else
        print("PixelMeterGrid not enabled")
    end

    -- Secondary stats in 4 columns with proper alignment
    -- Only apply offset if PixelMeter was actually created
    local statsYOffset = (pixelMeterCreated and self.config.enablePixelMeterGrid) and -20 or 0
    print("Stats Y offset:", statsYOffset)

    -- Row 1: Left side (max value and label)
    print("Creating maxValue...")
    local maxValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 20 + statsYOffset)
    maxValue:SetSize(45, 0)
    maxValue:SetText("0")
    maxValue:SetTextColor(0.8, 0.8, 0.8, 1)
    maxValue:SetJustifyH("RIGHT")
    frame.maxValue = maxValue
    print("maxValue created:", frame.maxValue ~= nil)

    local maxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLabel:SetPoint("LEFT", maxValue, "RIGHT", 2, 0)
    maxLabel:SetText("max")
    maxLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    maxLabel:SetJustifyH("LEFT")
    print("maxLabel created")

    -- Row 2: Left side (total value and label)
    print("Creating totalValue...")
    local totalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalValue:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8 + statsYOffset)
    totalValue:SetSize(45, 0)
    totalValue:SetText("0")
    totalValue:SetTextColor(0.8, 0.8, 0.8, 1)
    totalValue:SetJustifyH("RIGHT")
    frame.totalValue = totalValue
    print("totalValue created:", frame.totalValue ~= nil)

    local totalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalLabel:SetPoint("LEFT", totalValue, "RIGHT", 2, 0)
    totalLabel:SetText("total")
    totalLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    totalLabel:SetJustifyH("LEFT")
    print("totalLabel created")

    -- Absorb (only if enabled in config) - Right side
    if self.config.showAbsorb == true then
        print("Creating absorb stats...")
        local absorbValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        absorbValue:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -50, 20 + statsYOffset)
        absorbValue:SetSize(25, 0)
        absorbValue:SetText("0")
        absorbValue:SetTextColor(0.8, 0.8, 0.8, 1)
        absorbValue:SetJustifyH("RIGHT")
        frame.absorbValue = absorbValue

        local absorbLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        absorbLabel:SetPoint("LEFT", absorbValue, "RIGHT", 2, 0)
        absorbLabel:SetText("absorb")
        absorbLabel:SetTextColor(0.8, 0.8, 0.8, 1)
        absorbLabel:SetJustifyH("LEFT")
        print("Absorb stats created")
    end

    -- Overheal (only if enabled in config) - Right side
    if self.config.showOverheal == true then
        print("Creating overheal stats...")
        local overhealValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        overhealValue:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -50, 8 + statsYOffset)
        overhealValue:SetSize(25, 0)
        overhealValue:SetText("0%")
        overhealValue:SetTextColor(0.8, 0.8, 0.8, 1)
        overhealValue:SetJustifyH("RIGHT")
        frame.overhealValue = overhealValue

        local overhealLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        overhealLabel:SetPoint("LEFT", overhealValue, "RIGHT", 2, 0)
        overhealLabel:SetText("overheal")
        overhealLabel:SetTextColor(0.8, 0.8, 0.8, 1)
        overhealLabel:SetJustifyH("LEFT")
        print("Overheal stats created")
    end

    frame:Hide()

    if addon.db[self.config.visibilityKey] then
        frame:Show()
    end

    print("BaseMeterWindow:Create() completed for", self.config.label)
    print("Frame elements check:")
    print("  mainText:", frame.mainText ~= nil)
    print("  maxValue:", frame.maxValue ~= nil)
    print("  totalValue:", frame.totalValue ~= nil)
    print("  absorbValue:", frame.absorbValue ~= nil)
    print("  overhealValue:", frame.overhealValue ~= nil)
end

-- Create Pixel Meter Grid (generic)
function BaseMeterWindow:CreatePixelMeterGrid()
    print("CreatePixelMeterGrid() called")

    if not self.frame then
        error("self.frame is nil in CreatePixelMeterGrid")
    end

    if not addon.PixelMeterGrid then
        error("addon.PixelMeterGrid is nil")
    end

    print("BaseMeterWindow: Creating PixelMeterGrid for", self.config.label)

    -- Get meter config from window config
    local meterConfig = self.config.pixelMeterConfig or {
        cols = 20,
        rows = 1,
        pixelSize = 6,
        gap = 1,
        maxValue = 10000
    }

    print("PixelMeter config:", meterConfig.cols, "x", meterConfig.rows)

    -- Create the pixel meter (using PixelMeterGrid as the implementation)
    self.pixelMeter = addon.PixelMeterGrid:New(self.frame, meterConfig)
    print("PixelMeterGrid:New returned:", self.pixelMeter ~= nil)

    -- Position it between main text and stats
    self.pixelMeter:SetPoint("TOP", 0, -40)
    print("PixelMeter positioned")

    -- Set the value source from config
    if self.config.getPixelMeterValue then
        self.pixelMeter:SetValueSource(self.config.getPixelMeterValue)
        print("Value source set")
    else
        print("WARNING: No getPixelMeterValue in config")
    end

    self.pixelMeter:Show()
    print("PixelMeter:Show() called")
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

    -- Update main number
    if self.frame.mainText then
        self.frame.mainText:SetText(addon.CombatTracker:FormatNumber(mainValue))
    else
        print("ERROR: mainText is nil in UpdateDisplay")
    end

    -- Update secondary stats with nil checks
    if self.frame.maxValue then
        self.frame.maxValue:SetText(addon.CombatTracker:FormatNumber(maxValue))
    else
        print("ERROR: maxValue is nil in UpdateDisplay for", self.config.label)
    end

    if self.frame.totalValue then
        self.frame.totalValue:SetText(addon.CombatTracker:FormatNumber(totalValue))
    else
        print("ERROR: totalValue is nil in UpdateDisplay for", self.config.label)
    end

    -- Update absorb if enabled
    if self.config.showAbsorb == true and self.frame.absorbValue then
        self.frame.absorbValue:SetText(addon.CombatTracker:FormatNumber(absorbValue))
    end

    -- Update overheal if enabled
    if self.config.showOverheal == true and self.frame.overhealValue then
        local overhealPercent = 0
        local effectiveHealing = totalHealing
        if overhealValue > 0 and effectiveHealing > 0 then
            overhealPercent = math.floor((overhealValue / (effectiveHealing + overhealValue)) * 100)
        end
        self.frame.overhealValue:SetText(overhealPercent .. "%")
    end

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
