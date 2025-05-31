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
    instance.maxValue = config.maxValue or 15000

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

    print(string.format("WorkingPixelMeter: Creating %dx%d grid, window size %dx%d",
        self.cols, self.rows, totalWidth, totalHeight))

    -- Create main window frame - much more compact
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(totalWidth + 8, totalHeight + 8)       -- Minimal padding
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0) -- Right of center
    frame:SetFrameStrata("HIGH")

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

            print(string.format("Created pixel [%d,%d] at (%d,%d)", row, col, x, y))
        end
    end

    -- Make it draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    self.frame = frame
    self.gridFrame = gridFrame

    -- Start update timer
    if not self.updateTimer then
        self.updateTimer = C_Timer.NewTicker(0.1, function()
            self:Update()
        end)
    end

    print("WorkingPixelMeter created successfully")
end

function WorkingPixelMeter:SetValueSource(getValue)
    self.getValue = getValue
end

function WorkingPixelMeter:Update()
    if not self.frame or not self.getValue then return end

    local value = self.getValue() or 0

    -- Auto-scale maxValue if needed
    if value > self.maxValue then
        self.maxValue = value * 1.2
    end

    local percent = math.min(1.0, value / self.maxValue)
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
