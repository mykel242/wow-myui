-- PixelMeterGrid.lua
-- Generic pixel meter grid that can be used for any meter type

local addonName, addon = ...

addon.PixelMeterGrid = {}
local PixelMeterGrid = addon.PixelMeterGrid

function PixelMeterGrid:New(parent, config)
    local instance = {}
    setmetatable(instance, { __index = self })

    instance.parent = parent
    instance.config = config or {}
    instance.frame = nil
    instance.pixels = {}
    instance.getValue = nil
    instance.maxValue = config.maxValue or 10000

    -- Set defaults optimized for meter display
    instance.cols = config.cols or 20 -- 20 bars wide
    instance.rows = config.rows or 1  -- 1 row high
    instance.pixelSize = config.pixelSize or 6
    instance.gap = config.gap or 1

    return instance
end

function PixelMeterGrid:Create()
    if self.frame then return end

    -- AGGRESSIVE DEBUG: Make frame HUGE in debug mode
    local debugMultiplier = addon.DEBUG and 2 or 1
    local totalWidth = ((self.cols * self.pixelSize) + ((self.cols - 1) * self.gap)) * debugMultiplier
    local totalHeight = ((self.rows * self.pixelSize) + ((self.rows - 1) * self.gap)) * debugMultiplier

    if addon.DEBUG then
        print(string.format("PixelMeterGrid: Creating HUGE %dx%d meter, size %dx%d",
            self.cols, self.rows, totalWidth, totalHeight))
    end

    -- Create meter frame as child of parent
    local frame = CreateFrame("Frame", nil, self.parent)
    frame:SetSize(totalWidth, totalHeight)
    frame:SetFrameStrata("TOOLTIP")                       -- Higher strata to be on top
    frame:SetFrameLevel(self.parent:GetFrameLevel() + 20) -- Much higher level

    -- DEBUG: Add BRIGHT border to see frame bounds
    if addon.DEBUG then
        local border = frame:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(frame)
        border:SetColorTexture(1, 1, 0, 0.8) -- Bright yellow border
        print("PixelMeterGrid: Added BRIGHT YELLOW debug border")
    end

    -- Create pixels using the proven method
    for row = 1, self.rows do
        self.pixels[row] = {}
        for col = 1, self.cols do
            local pixel = frame:CreateTexture(nil, "OVERLAY")

            -- AGGRESSIVE DEBUG: Make pixels HUGE and BRIGHT
            if addon.DEBUG then
                pixel:SetSize(15, 15)             -- MASSIVE pixels
                pixel:SetColorTexture(1, 0, 1, 1) -- Bright magenta, full alpha
            else
                pixel:SetSize(self.pixelSize, self.pixelSize)
                pixel:SetColorTexture(0.2, 0.2, 0.2, 0.6)
            end

            -- Position from left to right with bigger gaps in debug mode
            local actualPixelSize = addon.DEBUG and 15 or self.pixelSize
            local actualGap = addon.DEBUG and 2 or self.gap
            local x = (col - 1) * (actualPixelSize + actualGap)
            local y = -((row - 1) * (actualPixelSize + actualGap))
            pixel:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)

            self.pixels[row][col] = pixel

            if addon.DEBUG then
                print(string.format("Created HUGE pixel [%d,%d] at (%d,%d), size=%d",
                    row, col, x, y, actualPixelSize))
            end
        end
    end

    self.frame = frame

    -- Start update timer
    if not self.updateTimer then
        self.updateTimer = C_Timer.NewTicker(0.1, function()
            self:Update()
        end)
    end

    if addon.DEBUG then
        print("PixelMeterGrid created successfully")
    end
end

function PixelMeterGrid:SetValueSource(getValue)
    self.getValue = getValue
end

function PixelMeterGrid:SetPoint(point, xOffset, yOffset)
    if self.frame then
        self.frame:SetPoint(point, self.parent, point, xOffset or 0, yOffset or 0)
    end
end

function PixelMeterGrid:Update()
    if not self.frame or not self.getValue then return end

    local value = self.getValue() or 0

    -- Auto-scale maxValue if needed
    if value > self.maxValue then
        self.maxValue = value * 1.2
    end

    local percent = math.min(1.0, value / self.maxValue)
    local activeCols = math.floor(self.cols * percent)

    if addon.DEBUG then
        -- Debug every 2 seconds
        local now = GetTime()
        if not self.lastDebugTime or (now - self.lastDebugTime) >= 2.0 then
            print(string.format("PixelMeterGrid: value=%.0f, percent=%.2f, active=%d/%d",
                value, percent, activeCols, self.cols))
            self.lastDebugTime = now
        end
    end

    -- Update pixel colors (skip in debug mode to keep them visible)
    if not addon.DEBUG then
        for row = 1, self.rows do
            for col = 1, self.cols do
                local pixel = self.pixels[row][col]

                if col <= activeCols then
                    -- Active pixel - color based on position
                    local colPercent = col / self.cols
                    local r, g, b = self:GetHPSColor(colPercent)
                    pixel:SetColorTexture(r, g, b, 1.0)
                else
                    -- Inactive pixel
                    pixel:SetColorTexture(0.2, 0.2, 0.2, 0.4)
                end
            end
        end
    end
end

-- Generic color scheme: Green -> Yellow -> Orange -> Red
function PixelMeterGrid:GetHPSColor(percent)
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

function PixelMeterGrid:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
end

function PixelMeterGrid:Hide()
    if self.frame then
        self.frame:Hide()
    end
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
end

function PixelMeterGrid:Destroy()
    self:Hide()
    if self.frame then
        self.frame = nil
    end
    self.pixels = {}
end
