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

    -- Background similar to the example image
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.8)

    -- Border
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetAllPoints(frame)
    border:SetColorTexture(0.4, 0.4, 0.4, 0.9)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)

    -- Player name and rank
    local playerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerText:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
    playerText:SetText("1. " .. UnitName("player"))
    playerText:SetTextColor(1, 1, 1, 1)
    playerText:SetJustifyH("LEFT")
    frame.playerText = playerText

    -- HPS value
    local hpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpsText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    hpsText:SetText("0")
    hpsText:SetTextColor(0, 1, 0, 1) -- Green for healing
    hpsText:SetJustifyH("RIGHT")
    frame.hpsText = hpsText

    -- Total healing
    local totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -25)
    totalText:SetText("Total: 0")
    totalText:SetTextColor(0.8, 0.8, 0.8, 1)
    totalText:SetJustifyH("LEFT")
    frame.totalText = totalText

    -- Combat time
    local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -25)
    timeText:SetText("0s")
    timeText:SetTextColor(0.8, 0.8, 0.8, 1)
    timeText:SetJustifyH("RIGHT")
    frame.timeText = timeText

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("BOTTOM", frame, "BOTTOM", 0, 5)
    title:SetText("My HPS")
    title:SetTextColor(0.9, 0.9, 0.9, 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(12, 12)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeBtnText:SetAllPoints(closeBtn)
    closeBtnText:SetText("×")
    closeBtnText:SetTextColor(1, 0.2, 0.2, 1)
    closeBtnText:SetJustifyH("CENTER")

    closeBtn:SetScript("OnClick", function() HPSWindow:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeBtnText:SetTextColor(1, 0.5, 0.5, 1) end)
    closeBtn:SetScript("OnLeave", function() closeBtnText:SetTextColor(1, 0.2, 0.2, 1) end)

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
    local totalHealing = addon.CombatTracker:GetTotalHealing()
    local combatTime = addon.CombatTracker:GetCombatTime()
    local inCombat = addon.CombatTracker:IsInCombat()

    -- Update HPS text
    self.frame.hpsText:SetText(addon.CombatTracker:FormatNumber(hps))

    -- Update total healing
    self.frame.totalText:SetText("Total: " .. addon.CombatTracker:FormatNumber(totalHealing))

    -- Update combat time
    self.frame.timeText:SetText(string.format("%.1fs", combatTime))

    -- Change color based on combat state
    if inCombat then
        self.frame.hpsText:SetTextColor(0, 1, 0, 1)          -- Green when in combat
        self.frame.playerText:SetTextColor(1, 1, 1, 1)       -- White
    else
        self.frame.hpsText:SetTextColor(0.7, 0.7, 0.7, 1)    -- Gray when out of combat
        self.frame.playerText:SetTextColor(0.7, 0.7, 0.7, 1) -- Gray
    end
end

-- Show the HPS window
function HPSWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    addon.db.showHPSWindow = true
end

-- Hide the HPS window
function HPSWindow:Hide()
    if self.frame then
        self.frame:Hide()
    end
    addon.db.showHPSWindow = false
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
