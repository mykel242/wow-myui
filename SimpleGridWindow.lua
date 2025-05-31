-- SimpleGridWindow.lua
-- Bulletproof grid using the same texture approach that worked for debug borders

local addonName, addon = ...

addon.SimpleGridWindow = {}
local SimpleGridWindow = addon.SimpleGridWindow

function SimpleGridWindow:New(config)
    local instance = {}
    setmetatable(instance, { __index = self })

    instance.config = config or {}
    instance.frame = nil
    instance.pixels = {}

    -- Set defaults
    instance.rows = config.rows or 4
    instance.cols = config.cols or 10
    instance.pixelSize = config.pixelSize or 8
    instance.gap = config.gap or 1

    return instance
end

function SimpleGridWindow:Create()
    if self.frame then return end

    -- Calculate total window size
    local totalWidth = (self.cols * self.pixelSize) + ((self.cols - 1) * self.gap)
    local totalHeight = (self.rows * self.pixelSize) + ((self.rows - 1) * self.gap)

    print(string.format("SimpleGridWindow: Creating %dx%d grid, window size %dx%d",
        self.cols, self.rows, totalWidth, totalHeight))

    -- Create main window frame
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(totalWidth + 20, totalHeight + 40)      -- Extra space for title
    frame:SetPoint("CENTER", UIParent, "CENTER", -200, 0) -- Left of center
    frame:SetFrameStrata("HIGH")

    -- Window background (dark)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -5)
    title:SetText(string.format("Grid: %dx%d", self.cols, self.rows))
    title:SetTextColor(1, 1, 1, 1)

    -- Create grid container (offset from top for title)
    local gridFrame = CreateFrame("Frame", nil, frame)
    gridFrame:SetSize(totalWidth, totalHeight)
    gridFrame:SetPoint("CENTER", frame, "CENTER", 0, -5)

    -- Grid background (to see bounds)
    local gridBg = gridFrame:CreateTexture(nil, "BACKGROUND")
    gridBg:SetAllPoints(gridFrame)
    gridBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    -- Create pixels using the EXACT same method as debug borders
    for row = 1, self.rows do
        self.pixels[row] = {}
        for col = 1, self.cols do
            -- Create texture - same as debug borders that worked
            local pixel = gridFrame:CreateTexture(nil, "OVERLAY")
            pixel:SetSize(self.pixelSize, self.pixelSize)

            -- Calculate position (top-left origin)
            local x = (col - 1) * (self.pixelSize + self.gap)
            local y = -((row - 1) * (self.pixelSize + self.gap)) -- Negative Y for top-down
            pixel:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", x, y)

            -- Set initial color - bright for testing
            pixel:SetColorTexture(0.5, 0.8, 1, 1) -- Light blue

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

    print("SimpleGridWindow created successfully")
end

-- Set pixel color by row/col
function SimpleGridWindow:SetPixel(row, col, r, g, b, a)
    if self.pixels[row] and self.pixels[row][col] then
        self.pixels[row][col]:SetColorTexture(r, g, b, a or 1)
    end
end

-- Set multiple pixels at once
function SimpleGridWindow:SetPixels(pixelData)
    for _, data in ipairs(pixelData) do
        self:SetPixel(data.row, data.col, data.r, data.g, data.b, data.a)
    end
end

-- Clear all pixels to a color
function SimpleGridWindow:Clear(r, g, b, a)
    for row = 1, self.rows do
        for col = 1, self.cols do
            self:SetPixel(row, col, r or 0.2, g or 0.2, b or 0.2, a or 0.5)
        end
    end
end

-- Test pattern - rainbow
function SimpleGridWindow:TestPattern()
    for row = 1, self.rows do
        for col = 1, self.cols do
            local hue = (col - 1) / (self.cols - 1) -- 0 to 1
            local r, g, b = self:HSVtoRGB(hue, 1, 1)
            self:SetPixel(row, col, r, g, b, 1)
        end
    end
end

-- HSV to RGB conversion for rainbow
function SimpleGridWindow:HSVtoRGB(h, s, v)
    local r, g, b
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)

    i = i % 6

    if i == 0 then
        r, g, b = v, t, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, t
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = t, p, v
    elseif i == 5 then
        r, g, b = v, p, q
    end

    return r, g, b
end

function SimpleGridWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()

    -- Test pattern after showing
    C_Timer.After(0.1, function()
        self:TestPattern()
        print("Test pattern applied")
    end)
end

function SimpleGridWindow:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function SimpleGridWindow:Toggle()
    if not self.frame then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
