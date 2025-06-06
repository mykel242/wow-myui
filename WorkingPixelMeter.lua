-- WorkingPixelMeter.lua
-- Based on the SimpleGridWindow that actually worked

local addonName, addon = ...

addon.WorkingPixelMeter = {}
local WorkingPixelMeter = addon.WorkingPixelMeter

function WorkingPixelMeter:New(config)
    local instance = {}
    setmetatable(instance, { __index = self })

    instance.config = config or {}
    instance.frame = nil
    instance.pixels = {}
    instance.getValue = nil
    instance.maxValue = config.maxValue or 500000      -- CHANGED: 500K default instead of 15K
    instance.originalMaxValue = instance.maxValue      -- Store original for reset
    instance.manualMaxValue = nil                      -- For manual override
    instance.meterName = config.meterName or "Unknown" -- For debug/commands

    -- Set defaults
    instance.rows = config.rows or 1
    instance.cols = config.cols or 20
    instance.pixelSize = config.pixelSize or 6
    instance.gap = config.gap or 1

    return instance
end

function WorkingPixelMeter:Create()
    if self.frame then return end

    -- Calculate total window size
    local totalWidth = (self.cols * self.pixelSize) + ((self.cols - 1) * self.gap)
    local totalHeight = (self.rows * self.pixelSize) + ((self.rows - 1) * self.gap)

    if addon.DEBUG then
        print(string.format("WorkingPixelMeter: Creating %dx%d grid, window size %dx%d",
            self.cols, self.rows, totalWidth, totalHeight))
    end

    -- Create main window frame - match parent width
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(220, totalHeight + 8)                  -- Match the 220px window width
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0) -- Right of center
    -- frame:SetFrameStrata("HIGH")

    -- Cleaner background to match existing meters
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.7) -- Match existing meter background

    -- Create grid container (minimal offset)
    local gridFrame = CreateFrame("Frame", nil, frame)
    gridFrame:SetSize(totalWidth, totalHeight)
    gridFrame:SetPoint("CENTER", frame, "CENTER", 0, 0) -- Centered, no offset

    -- Create pixels using the EXACT same method that worked
    for row = 1, self.rows do
        self.pixels[row] = {}
        for col = 1, self.cols do
            -- Create texture - same as working version
            local pixel = gridFrame:CreateTexture(nil, "OVERLAY")
            pixel:SetSize(self.pixelSize, self.pixelSize)

            -- Calculate position (top-left origin)
            local x = (col - 1) * (self.pixelSize + self.gap)
            local y = -((row - 1) * (self.pixelSize + self.gap)) -- Negative Y for top-down
            pixel:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x, y)

            -- Set initial color - dim
            pixel:SetColorTexture(0.2, 0.2, 0.2, 0.5)

            self.pixels[row][col] = pixel

            if addon.DEBUG then
                print(string.format("Created pixel [%d,%d] at (%d,%d)", row, col, x, y))
            end
        end
    end

    -- Make it non-draggable (it should follow its parent window)
    frame:SetMovable(false)
    frame:EnableMouse(false) -- Disable mouse interaction entirely

    self.frame = frame
    self.gridFrame = gridFrame

    -- Start update timer
    if not self.updateTimer then
        self.updateTimer = C_Timer.NewTicker(0.1, function()
            self:Update()
        end)
    end

    if addon.DEBUG then
        print("WorkingPixelMeter created successfully")
    end
end

function WorkingPixelMeter:SetValueSource(getValue)
    self.getValue = getValue
end

-- Manual scaling functions
function WorkingPixelMeter:SetMaxValue(newMax)
    self.manualMaxValue = newMax
    if addon.DEBUG then
        print(string.format("%s meter max set to %s", self.meterName, addon.CombatTracker:FormatNumber(newMax)))
    end
end

function WorkingPixelMeter:ResetMaxValue()
    self.manualMaxValue = nil
    self.maxValue = self.originalMaxValue
    if addon.DEBUG then
        print(string.format("%s meter max reset to %s", self.meterName,
            addon.CombatTracker:FormatNumber(self.originalMaxValue)))
    end
end

function WorkingPixelMeter:GetCurrentMaxValue()
    return self.manualMaxValue or self.maxValue
end

function WorkingPixelMeter:GetDebugInfo()
    local currentValue = self.getValue and self.getValue() or 0
    local currentMax = self:GetCurrentMaxValue()
    local percent = currentMax > 0 and (currentValue / currentMax) or 0
    local activeCols = math.floor(self.cols * percent)

    return {
        name = self.meterName,
        currentValue = currentValue,
        currentMax = currentMax,
        originalMax = self.originalMaxValue,
        manualMax = self.manualMaxValue,
        percent = percent * 100,
        activeCols = activeCols,
        totalCols = self.cols,
        isManual = self.manualMaxValue ~= nil
    }
end

function WorkingPixelMeter:Update()
    if not self.frame or not self.getValue then return end

    local value = self.getValue() or 0
    local currentMax = self:GetCurrentMaxValue()

    -- Only auto-scale if no manual override is set
    if not self.manualMaxValue then
        -- Simple approach: scale based on last combat's peak
        local autoScale = self:GetAutoScale()
        self.maxValue = autoScale
        currentMax = autoScale
    end

    local percent = math.min(1.0, currentMax > 0 and (value / currentMax) or 0)
    local activeCols = math.floor(self.cols * percent)

    -- Update pixel colors
    for row = 1, self.rows do
        for col = 1, self.cols do
            local pixel = self.pixels[row][col]

            if col <= activeCols then
                -- Active pixel - color based on position
                local colPercent = col / self.cols
                local r, g, b = self:GetMeterColor(colPercent)
                pixel:SetColorTexture(r, g, b, 1.0)
            else
                -- Inactive pixel
                pixel:SetColorTexture(0.2, 0.2, 0.2, 0.4)
            end
        end
    end
end

-- Color scheme: Green -> Yellow -> Orange -> Red
function WorkingPixelMeter:GetMeterColor(percent)
    if percent <= 0.33 then
        -- Green to bright green
        local t = percent / 0.33
        return 0, 0.6 + (t * 0.4), 0 -- Dark green to bright green
    elseif percent <= 0.66 then
        -- Green to yellow
        local t = (percent - 0.33) / 0.33
        return t, 1.0, 0 -- Green to yellow
    else
        -- Yellow to red
        local t = (percent - 0.66) / 0.34
        return 1.0, 1.0 - t, 0 -- Yellow to red
    end
end

function WorkingPixelMeter:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
end

function WorkingPixelMeter:Hide()
    if self.frame then
        self.frame:Hide()
    end
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
end

function WorkingPixelMeter:Toggle()
    if not self.frame then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function WorkingPixelMeter:GetAutoScale()
    if not addon.CombatTracker then
        return self.originalMaxValue
    end

    -- Get the last combat's peak for this meter type
    local lastPeak = 0
    if self.meterName == "DPS" then
        lastPeak = addon.CombatTracker:GetLastCombatMaxDPS()
    elseif self.meterName == "HPS" then
        lastPeak = addon.CombatTracker:GetLastCombatMaxHPS()
    end

    -- If we have a previous peak, use it with some headroom
    if lastPeak > 0 then
        local autoScale = lastPeak * 1.4 -- 40% headroom

        -- Round to nice number
        autoScale = self:RoundToNiceNumber(autoScale)

        -- Reasonable bounds
        autoScale = math.max(autoScale, self.originalMaxValue) -- Don't go below 500K
        autoScale = math.min(autoScale, 20000000)              -- 20M cap

        return autoScale
    else
        -- No previous data, use default (500K)
        return self.originalMaxValue
    end
end

function WorkingPixelMeter:RoundToNiceNumber(value)
    -- Round to nice round numbers: 100K, 200K, 500K, 1M, 2M, 5M, 10M, etc.

    if value < 100000 then
        -- Below 100K: round to nearest 50K
        return math.ceil(value / 50000) * 50000
    elseif value < 1000000 then
        -- 100K to 1M: round to nearest 100K
        return math.ceil(value / 100000) * 100000
    elseif value < 5000000 then
        -- 1M to 5M: round to nearest 500K
        return math.ceil(value / 500000) * 500000
    elseif value < 10000000 then
        -- 5M to 10M: round to nearest 1M
        return math.ceil(value / 1000000) * 1000000
    else
        -- Above 10M: round to nearest 2M
        return math.ceil(value / 2000000) * 2000000
    end
end
