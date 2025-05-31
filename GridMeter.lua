-- GridMeter.lua
-- Simple grid-based meter that actually works

local addonName, addon = ...

addon.GridMeter = {}
local GridMeter = addon.GridMeter

function GridMeter:New(parent, config)
    local instance = {}
    setmetatable(instance, { __index = self })

    instance.parent = parent
    instance.config = config or {}
    instance.squares = {}
    instance.frame = nil
    instance.getValue = nil
    instance.maxValue = config.maxValue or 1000

    return instance
end

function GridMeter:Create()
    if self.frame then return end

    local cfg = self.config
    local width = (cfg.squareSize + cfg.spacing) * cfg.columns - cfg.spacing
    local height = (cfg.squareSize + cfg.spacing) * cfg.rows - cfg.spacing

    -- Create container frame
    local frame = CreateFrame("Frame", nil, self.parent)
    frame:SetSize(width, height)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(self.parent:GetFrameLevel() + 10)

    -- Debug: Add bright border to see frame bounds
    if addon.DEBUG then
        local border = frame:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(frame)
        border:SetColorTexture(0, 1, 0, 0.8) -- Bright green border
        print("GridMeter: Added green debug border")
    end

    if addon.DEBUG then
        print(string.format("GridMeter: Creating %dx%d grid, frame size %dx%d",
            cfg.columns, cfg.rows, width, height))
    end

    -- Create grid of squares
    for row = 1, cfg.rows do
        self.squares[row] = {}
        for col = 1, cfg.columns do
            local square = frame:CreateTexture(nil, "OVERLAY")
            square:SetSize(cfg.squareSize, cfg.squareSize)

            -- Position from bottom-left
            local x = (col - 1) * (cfg.squareSize + cfg.spacing)
            local y = (row - 1) * (cfg.squareSize + cfg.spacing)
            square:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)

            -- Start with bright test color in debug mode
            if addon.DEBUG then
                square:SetColorTexture(1, 0, 0, 1) -- Bright red for visibility
            else
                square:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            end

            self.squares[row][col] = square

            if addon.DEBUG then
                print(string.format("Created square [%d,%d] at (%d,%d)", row, col, x, y))
            end
        end
    end

    self.frame = frame

    if addon.DEBUG then
        print("GridMeter created successfully")
    end
end

function GridMeter:SetValueSource(getValue)
    self.getValue = getValue
end

function GridMeter:SetPoint(point, xOffset, yOffset)
    if self.frame then
        self.frame:SetPoint(point, self.parent, point, xOffset or 0, yOffset or 0)
    end
end

function GridMeter:Update()
    if not self.frame or not self.getValue then return end

    local value = self.getValue() or 0
    local percent = math.min(1.0, value / self.maxValue)

    -- Auto-scale if value exceeds max
    if value > self.maxValue then
        self.maxValue = value * 1.2
        percent = value / self.maxValue
    end

    local totalSquares = self.config.columns * self.config.rows
    local activeSquares = math.floor(totalSquares * percent)

    if addon.DEBUG then
        -- Only print every 2 seconds
        local now = GetTime()
        if not self.lastDebugTime or (now - self.lastDebugTime) >= 2.0 then
            print(string.format("GridMeter: value=%.0f, percent=%.2f, active=%d/%d",
                value, percent, activeSquares, totalSquares))
            self.lastDebugTime = now
        end
    end

    -- Update square colors
    local squareIndex = 0
    for row = 1, self.config.rows do
        for col = 1, self.config.columns do
            squareIndex = squareIndex + 1
            local square = self.squares[row][col]

            if squareIndex <= activeSquares then
                -- Active square - use color based on position
                local colorPercent = squareIndex / totalSquares
                local color = self:GetColor(colorPercent)
                square:SetColorTexture(color.r, color.g, color.b, 1.0)
            else
                -- Inactive square
                square:SetColorTexture(0.2, 0.2, 0.2, 0.5)
            end
        end
    end
end

function GridMeter:GetColor(percent)
    -- Simple green to red gradient
    if percent <= 0.5 then
        -- Green to yellow
        local t = percent * 2
        return {
            r = t,
            g = 1.0,
            b = 0
        }
    else
        -- Yellow to red
        local t = (percent - 0.5) * 2
        return {
            r = 1.0,
            g = 1.0 - t,
            b = 0
        }
    end
end

function GridMeter:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()

    -- Start update timer
    if not self.updateTimer then
        self.updateTimer = C_Timer.NewTicker(0.1, function()
            self:Update()
        end)
    end
end

function GridMeter:Hide()
    if self.frame then
        self.frame:Hide()
    end
    if self.updateTimer then
        self.updateTimer:Cancel()
        self.updateTimer = nil
    end
end
