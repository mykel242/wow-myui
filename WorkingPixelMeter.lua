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
    instance.maxValue = config.maxValue or 1000        -- CHANGED: 1K default for true beginners
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
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0) -- Default position - will be repositioned by parent
    frame:SetFrameStrata("MEDIUM")

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

    -- Make it draggable but propagate to parent window
    frame:SetMovable(false)  -- Don't move this frame directly
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    
    -- Find parent window and delegate dragging to it
    local meterInstance = self
    frame:SetScript("OnDragStart", function(pixelFrame)
        local parentWindow = nil
        
        -- Find the parent meter window based on meter name
        if meterInstance.meterName == "DPS" and addon.DPSWindow and addon.DPSWindow.frame then
            parentWindow = addon.DPSWindow.frame
        elseif meterInstance.meterName == "HPS" and addon.HPSWindow and addon.HPSWindow.frame then
            parentWindow = addon.HPSWindow.frame
        end
        
        -- Start dragging the parent window instead
        if parentWindow and parentWindow:IsMovable() then
            parentWindow:StartMoving()
        end
    end)
    
    frame:SetScript("OnDragStop", function(pixelFrame)
        local parentWindow = nil
        
        -- Find the parent meter window based on meter name
        if meterInstance.meterName == "DPS" and addon.DPSWindow and addon.DPSWindow.frame then
            parentWindow = addon.DPSWindow.frame
        elseif meterInstance.meterName == "HPS" and addon.HPSWindow and addon.HPSWindow.frame then
            parentWindow = addon.HPSWindow.frame
        end
        
        -- Stop dragging the parent window
        if parentWindow then
            parentWindow:StopMovingOrSizing()
            
            -- Trigger the parent's OnDragStop if it has one
            local parentDragStop = parentWindow:GetScript("OnDragStop")
            if parentDragStop then
                parentDragStop(parentWindow)
            end
        end
    end)

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
        -- Enhanced approach: use content-specific session pools
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

-- Enhanced WorkingPixelMeter:GetAutoScale() with content-specific pools
function WorkingPixelMeter:GetAutoScale()
    if not addon.CombatTracker then
        return self.originalMaxValue
    end

    -- Get current content type for scaling context
    local contentType = addon.CombatTracker:GetCurrentContentType()

    -- Get appropriate sessions for this content type
    local sessions = addon.CombatTracker:GetScalingSessions(contentType, 10)

    if #sessions == 0 then
        -- No relevant sessions, fall back to last combat peak
        local lastPeak = 0
        if self.meterName == "DPS" then
            lastPeak = addon.CombatTracker:GetLastCombatMaxDPS()
        elseif self.meterName == "HPS" then
            lastPeak = addon.CombatTracker:GetLastCombatMaxHPS()
        end

        if lastPeak > 0 then
            local autoScale = lastPeak * 1.4 -- 40% headroom
            autoScale = self:RoundToNiceNumber(autoScale)
            autoScale = math.max(autoScale, self.originalMaxValue)
            autoScale = math.min(autoScale, 20000000)

            if addon.DEBUG then
                print(string.format("%s: Using last combat peak %.0f -> %.0f (%s content)",
                    self.meterName, lastPeak, autoScale, contentType))
            end

            return autoScale
        else
            return self.originalMaxValue
        end
    end

    -- Calculate weighted average from session pool
    local autoScale = self:CalculateWeightedScale(sessions, contentType)

    if addon.DEBUG then
        print(string.format("%s: Using %d %s sessions -> %.0f",
            self.meterName, #sessions, contentType, autoScale))
    end

    return autoScale
end

-- New method: Calculate weighted scaling from session pool
function WorkingPixelMeter:CalculateWeightedScale(sessions, contentType)
    local values = {}
    local weights = {}
    local totalWeight = 0

    -- Extract relevant values and calculate weights
    for i, session in ipairs(sessions) do
        local value = 0
        if self.meterName == "DPS" then
            value = session.peakDPS or session.avgDPS
        elseif self.meterName == "HPS" then
            value = session.peakHPS or session.avgHPS
        end

        if value and value > 0 then
            table.insert(values, value)

            -- Weight calculation: recent sessions and high quality count more
            local recencyWeight = math.max(0.3, 1.0 - ((i - 1) * 0.1)) -- Decay: 1.0, 0.9, 0.8...
            local qualityWeight = session.qualityScore / 100
            local userWeight = 1.0

            -- Boost representative sessions
            if session.userMarked == "representative" then
                userWeight = 1.5
            elseif session.userMarked == "ignore" then
                userWeight = 0.1 -- Still include but with minimal weight
            end

            local combinedWeight = recencyWeight * qualityWeight * userWeight
            table.insert(weights, combinedWeight)
            totalWeight = totalWeight + combinedWeight
        end
    end

    if #values == 0 then
        return self.originalMaxValue
    end

    -- Calculate weighted average
    local weightedSum = 0
    for i, value in ipairs(values) do
        weightedSum = weightedSum + (value * weights[i])
    end

    local weightedAverage = weightedSum / totalWeight

    -- Apply content-specific headroom
    local headroomMultiplier = 1.4 -- Default 40%
    if contentType == "scaled" then
        headroomMultiplier = 1.6   -- More headroom for scaled content (60%)
    end

    local autoScale = weightedAverage * headroomMultiplier

    -- Outlier protection: cap scaling changes
    local currentMax = self:GetCurrentMaxValue()
    local maxChange = 3.0 -- Don't change by more than 3x in one update

    if autoScale > currentMax * maxChange then
        autoScale = currentMax * maxChange
        if addon.DEBUG then
            print(string.format("%s: Capped scaling change to %.0f (was %.0f)",
                self.meterName, autoScale, weightedAverage * headroomMultiplier))
        end
    elseif autoScale < currentMax / maxChange then
        autoScale = currentMax / maxChange
        if addon.DEBUG then
            print(string.format("%s: Limited scaling reduction to %.0f (was %.0f)",
                self.meterName, autoScale, weightedAverage * headroomMultiplier))
        end
    end

    -- Round and bound
    autoScale = self:RoundToNiceNumber(autoScale)
    autoScale = math.max(autoScale, 500)      -- Don't go below 500 DPS
    autoScale = math.min(autoScale, 50000000) -- 50M cap

    if addon.DEBUG then
        print(string.format("%s Auto-scale (%s): %.0f avg * %.1f headroom = %.0f (from %d sessions)",
            self.meterName, contentType, weightedAverage, headroomMultiplier, autoScale, #values))
    end

    return autoScale
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

function WorkingPixelMeter:RoundToNiceNumber(value)
    -- Round to nice round numbers across the full DPS spectrum

    if value < 1000 then
        -- Below 1K: round to nearest 100 (for level 1-15 players)
        return math.ceil(value / 100) * 100
    elseif value < 5000 then
        -- 1K to 5K: round to nearest 500 (low level)
        return math.ceil(value / 500) * 500
    elseif value < 10000 then
        -- 5K to 10K: round to nearest 1K
        return math.ceil(value / 1000) * 1000
    elseif value < 50000 then
        -- 10K to 50K: round to nearest 5K
        return math.ceil(value / 5000) * 5000
    elseif value < 100000 then
        -- 50K to 100K: round to nearest 10K
        return math.ceil(value / 10000) * 10000
    elseif value < 500000 then
        -- 100K to 500K: round to nearest 25K
        return math.ceil(value / 25000) * 25000
    elseif value < 1000000 then
        -- 500K to 1M: round to nearest 50K
        return math.ceil(value / 50000) * 50000
    elseif value < 5000000 then
        -- 1M to 5M: round to nearest 250K
        return math.ceil(value / 250000) * 250000
    elseif value < 10000000 then
        -- 5M to 10M: round to nearest 500K
        return math.ceil(value / 500000) * 500000
    else
        -- Above 10M: round to nearest 1M
        return math.ceil(value / 1000000) * 1000000
    end
end
