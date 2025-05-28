-- HPSWindow.lua
-- HPS (Healing Per Second) tracking window

local addonName, addon = ...

-- HPS Window module
addon.HPSWindow = {}
local HPSWindow = addon.HPSWindow

-- Initialize HPS Window defaults
function HPSWindow:Initialize()
    if addon.db.hpsWindowPosition == nil then
        addon.db.hpsWindowPosition = nil
    end
    if addon.db.showHPSWindow == nil then
        addon.db.showHPSWindow = false
    end
end

-- Create the HPS window
function HPSWindow:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", addonName .. "HPSWindow", UIParent)
    frame:SetSize(160, 80)

    -- Restore saved position or use default
    if addon.db.hpsWindowPosition then
        frame:SetPoint(
            addon.db.hpsWindowPosition.point or "RIGHT",
            UIParent,
            addon.db.hpsWindowPosition.relativePoint or "RIGHT",
            addon.db.hpsWindowPosition.xOffset or -100,
            addon.db.hpsWindowPosition.yOffset or 0
        )
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -100, 0)
    end

    -- Make it draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        addon.db.hpsWindowPosition = {
            point = point,
            relativePoint = relativePoint,
            xOffset = xOfs,
            yOffset = yOfs
        }
    end)

    -- Background (black semi-transparent like the example)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.7)

    -- Top section background (slightly more opaque black)
    local topBg = frame:CreateTexture(nil, "BORDER")
    topBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBg:SetHeight(45)
    topBg:SetColorTexture(0, 0, 0, 0.8)

    -- Large HPS number
    local hpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    hpsText:SetPoint("LEFT", frame, "LEFT", 8, 8)
    hpsText:SetText("0")
    hpsText:SetTextColor(1, 1, 1, 1)
    hpsText:SetJustifyH("LEFT")
    frame.hpsText = hpsText

    -- HPS label (green, top right)
    local hpsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpsLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    hpsLabel:SetText("HPS")
    hpsLabel:SetTextColor(0, 1, 0.5, 1) -- Teal green like example
    hpsLabel:SetJustifyH("RIGHT")

    -- Max HPS (bottom left)
    local maxText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 20)
    maxText:SetText("0 max")
    maxText:SetTextColor(0.8, 0.8, 0.8, 1)
    maxText:SetJustifyH("LEFT")
    frame.maxText = maxText

    -- Total healing (below max)
    local totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
    totalText:SetText("0 total")
    totalText:SetTextColor(0.8, 0.8, 0.8, 1)
    totalText:SetJustifyH("LEFT")
    frame.totalText = totalText

    -- Refresh icon (bottom right) - using a texture icon
    local refreshBtn = CreateFrame("Button", nil, frame)
    refreshBtn:SetSize(20, 20)
    refreshBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)

    -- Create the icon texture
    local refreshIcon = refreshBtn:CreateTexture(nil, "ARTWORK")
    refreshIcon:SetAllPoints(refreshBtn)

    -- Use your custom texture (place refresh-icon.tga in your MyUI addon folder)
    refreshIcon:SetTexture("Interface\\AddOns\\MyUI\\refresh-icon")

    -- Fallback to WoW's built-in icon if custom texture fails to load
    if not refreshIcon:GetTexture() then
        refreshIcon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
    end

    refreshIcon:SetAlpha(0.25)

    -- Make refresh icon clickable to reset stats
    refreshBtn:SetScript("OnClick", function()
        if addon.CombatTracker then
            -- Reset HPS display stats
            if not addon.CombatTracker:IsInCombat() then
                addon.CombatTracker:ResetDisplayStats()
                print("HPS stats reset")
            end
        end
    end)
    refreshBtn:SetScript("OnEnter", function()
        refreshIcon:SetAlpha(1.0) -- Full opacity on hover
    end)
    refreshBtn:SetScript("OnLeave", function()
        refreshIcon:SetAlpha(0.25) -- Back to semi-transparent
    end)

    frame:Hide()
    self.frame = frame

    if addon.db.showHPSWindow then
        frame:Show()
    end
end

-- Update the display with current combat data
function HPSWindow:UpdateDisplay()
    if not self.frame then return end

    local hps = addon.CombatTracker:GetHPS()
    local maxHPS = addon.CombatTracker:GetMaxHPS()
    local totalHealing = addon.CombatTracker:GetTotalHealing()
    local inCombat = addon.CombatTracker:IsInCombat()

    -- Only show 0 HPS when not in combat AND no previous data exists
    if not inCombat and maxHPS == 0 then
        hps = 0
    end

    -- Update main HPS number (large)
    self.frame.hpsText:SetText(addon.CombatTracker:FormatNumber(hps))

    -- Update max HPS (keep previous values until reset)
    self.frame.maxText:SetText(addon.CombatTracker:FormatNumber(maxHPS) .. " max")

    -- Update total healing (keep previous values until reset)
    self.frame.totalText:SetText(addon.CombatTracker:FormatNumber(totalHealing) .. " total")

    -- Change color and alpha based on combat state
    if inCombat then
        self.frame.hpsText:SetTextColor(1, 1, 1, 1)       -- White when in combat
        self.frame.hpsText:SetAlpha(1.0)                  -- Full opacity
    else
        self.frame.hpsText:SetTextColor(0.8, 0.8, 0.8, 1) -- Light gray when out of combat
        self.frame.hpsText:SetAlpha(0.25)                 -- Fade to match refresh buttons
    end
end

-- Show the HPS window
function HPSWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    -- Update saved visibility state immediately
    if addon.db then
        addon.db.showHPSWindow = true
    end
end

-- Hide the HPS window
function HPSWindow:Hide()
    if self.frame then
        self.frame:Hide()
    end
    -- Update saved visibility state immediately
    if addon.db then
        addon.db.showHPSWindow = false
    end
end

-- Toggle the HPS window
function HPSWindow:Toggle()
    if not self.frame then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
