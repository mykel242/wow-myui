-- DPSWindow.lua
-- DPS tracking window

local addonName, addon = ...

-- DPS Window module
addon.DPSWindow = {}
local DPSWindow = addon.DPSWindow

-- Initialize DPS Window defaults
function DPSWindow:Initialize()
    if addon.db.dpsWindowPosition == nil then
        addon.db.dpsWindowPosition = nil
    end
    if addon.db.showDPSWindow == nil then
        addon.db.showDPSWindow = false
    end
end

-- Create the DPS window
function DPSWindow:Create()
    if self.frame then return end

    local frame = CreateFrame("Frame", addonName .. "DPSWindow", UIParent)
    frame:SetSize(160, 80)

    -- Restore saved position or use default
    if addon.db.dpsWindowPosition then
        frame:SetPoint(
            addon.db.dpsWindowPosition.point or "RIGHT",
            UIParent,
            addon.db.dpsWindowPosition.relativePoint or "RIGHT",
            addon.db.dpsWindowPosition.xOffset or -100,
            addon.db.dpsWindowPosition.yOffset or 100
        )
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -100, 100)
    end

    -- Make it draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        addon.db.dpsWindowPosition = {
            point = point,
            relativePoint = relativePoint,
            xOffset = xOfs,
            yOffset = yOfs
        }
    end)

    -- Background (black semi-transparent like HPS window)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.7)

    -- Top section background (slightly more opaque black)
    local topBg = frame:CreateTexture(nil, "BORDER")
    topBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    topBg:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    topBg:SetHeight(45)
    topBg:SetColorTexture(0, 0, 0, 0.8)

    -- Large DPS number
    local dpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    dpsText:SetPoint("LEFT", frame, "LEFT", 8, 8)
    dpsText:SetText("0")
    dpsText:SetTextColor(1, 1, 1, 1)
    dpsText:SetJustifyH("LEFT")
    frame.dpsText = dpsText

    -- DPS label (red, top right)
    local dpsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpsLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    dpsLabel:SetText("DPS")
    dpsLabel:SetTextColor(1, 0.2, 0.2, 1) -- Red for DPS
    dpsLabel:SetJustifyH("RIGHT")

    -- Max DPS (bottom left, top line)
    local maxText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 20)
    maxText:SetText("0 max")
    maxText:SetTextColor(0.8, 0.8, 0.8, 1)
    maxText:SetJustifyH("LEFT")
    frame.maxText = maxText

    -- Total damage (below max)
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
            -- Reset DPS display stats
            if not addon.CombatTracker:IsInCombat() then
                addon.CombatTracker:ResetDisplayStats()
                print("DPS stats reset")
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

    if addon.db.showDPSWindow then
        frame:Show()
    end
end

-- Update the display with current combat data
function DPSWindow:UpdateDisplay()
    if not self.frame then return end

    local dps = addon.CombatTracker:GetDPS()
    local maxDPS = addon.CombatTracker:GetMaxDPS()
    local totalDamage = addon.CombatTracker:GetTotalDamage()
    local inCombat = addon.CombatTracker:IsInCombat()

    -- Only show 0 DPS when not in combat AND no previous data exists
    if not inCombat and maxDPS == 0 then
        dps = 0
    end

    -- Update main DPS number (large)
    self.frame.dpsText:SetText(addon.CombatTracker:FormatNumber(dps))

    -- Update max DPS (keep previous values until reset)
    self.frame.maxText:SetText(addon.CombatTracker:FormatNumber(maxDPS) .. " max")

    -- Update total damage (keep previous values until reset)
    self.frame.totalText:SetText(addon.CombatTracker:FormatNumber(totalDamage) .. " total")

    -- Change color based on combat state
    if inCombat then
        self.frame.dpsText:SetTextColor(1, 1, 1, 1)       -- White when in combat
    else
        self.frame.dpsText:SetTextColor(0.8, 0.8, 0.8, 1) -- Light gray when out of combat (but keep numbers visible)
    end
end

-- Show the DPS window
function DPSWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    -- Update saved visibility state immediately
    if addon.db then
        addon.db.showDPSWindow = true
    end
end

-- Hide the DPS window
function DPSWindow:Hide()
    if self.frame then
        self.frame:Hide()
    end
    -- Update saved visibility state immediately
    if addon.db then
        addon.db.showDPSWindow = false
    end
end

-- Toggle the DPS window
function DPSWindow:Toggle()
    if not self.frame then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end
