-- SubWindow.lua
-- Handles the secondary semi-transparent window

local addonName, addon = ...

-- SubWindow module
addon.SubWindow = {}
local SubWindow = addon.SubWindow

-- Initialize SubWindow defaults
function SubWindow:Initialize()
    -- Add subwindow defaults to main addon defaults if not present
    if addon.db.subWindowPosition == nil then
        addon.db.subWindowPosition = nil
    end
    if addon.db.showSubWindow == nil then
        addon.db.showSubWindow = false
    end
end

-- Create the sub window
function SubWindow:Create()
    if self.frame then return end

    -- Create a basic frame with no template for custom styling
    local frame = CreateFrame("Frame", addonName .. "SubWindow", UIParent)
    frame:SetSize(160, 80)

    -- Restore saved position or use default
    if addon.db.subWindowPosition then
        frame:SetPoint(
            addon.db.subWindowPosition.point or "LEFT",
            UIParent,
            addon.db.subWindowPosition.relativePoint or "LEFT",
            addon.db.subWindowPosition.xOffset or 100,
            addon.db.subWindowPosition.yOffset or 0
        )
    else
        frame:SetPoint("LEFT", UIParent, "LEFT", 100, 0)
    end

    -- Make it draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position immediately when dragging stops
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        addon.db.subWindowPosition = {
            point = point,
            relativePoint = relativePoint,
            xOffset = xOfs,
            yOffset = yOfs
        }
    end)

    -- Semi-transparent background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.7) -- Black with 70% opacity
    frame.background = bg

    -- Optional: Add a subtle border
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetAllPoints(frame)
    border:SetColorTexture(0.3, 0.3, 0.3, 0.8) -- Gray border
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
    frame.border = border

    -- Add some content
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", frame, "TOP", 0, -5)
    title:SetText("Sub Window")
    title:SetTextColor(1, 1, 1, 1)

    local content = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    content:SetPoint("CENTER", frame, "CENTER", 0, 0)
    content:SetText("Draggable\nWindow")
    content:SetTextColor(0.8, 0.8, 0.8, 1)
    content:SetJustifyH("CENTER")

    -- Close button (small X in top-right corner)
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    -- Close button texture
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtnText:SetAllPoints(closeBtn)
    closeBtnText:SetText("×")
    closeBtnText:SetTextColor(1, 0.2, 0.2, 1)
    closeBtnText:SetJustifyH("CENTER")
    closeBtnText:SetJustifyV("MIDDLE")

    closeBtn:SetScript("OnClick", function()
        SubWindow:Hide()
    end)

    closeBtn:SetScript("OnEnter", function(self)
        closeBtnText:SetTextColor(1, 0.5, 0.5, 1)
    end)

    closeBtn:SetScript("OnLeave", function(self)
        closeBtnText:SetTextColor(1, 0.2, 0.2, 1)
    end)

    -- Initially hidden
    frame:Hide()

    self.frame = frame

    -- Show if it was visible when last saved
    if addon.db.showSubWindow then
        frame:Show()
    end
end

-- Show the sub window
function SubWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    -- Update saved visibility state immediately
    if addon.db then
        addon.db.showSubWindow = true
    end
end

-- Hide the sub window
function SubWindow:Hide()
    if self.frame then
        self.frame:Hide()
    end
    -- Update saved visibility state immediately
    if addon.db then
        addon.db.showSubWindow = false
    end
end

-- Toggle the sub window
function SubWindow:Toggle()
    if not self.frame then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Check if sub window is shown
function SubWindow:IsShown()
    return self.frame and self.frame:IsShown()
end
