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

    -- DPS value
    local dpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpsText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    dpsText:SetText("0")
    dpsText:SetTextColor(1, 1, 0, 1) -- Yellow like in the example
    dpsText:SetJustifyH("RIGHT")
    frame.dpsText = dpsText

    -- Total damage
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
    title:SetText("My DPS")
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

    closeBtn:SetScript("OnClick", function() DPSWindow:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeBtnText:SetTextColor(1, 0.5, 0.5, 1) end)
    closeBtn:SetScript("OnLeave", function() closeBtnText:SetTextColor(1, 0.2, 0.2, 1) end)

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
    local totalDamage = addon.CombatTracker:GetTotalDamage()
    local combatTime = addon.CombatTracker:GetCombatTime()
    local inCombat = addon.CombatTracker:IsInCombat()

    -- Show 0 DPS when not in combat
    if not inCombat then
        dps = 0
    end

    -- Update DPS text
    self.frame.dpsText:SetText(addon.CombatTracker:FormatNumber(dps))

    -- Update total damage
    self.frame.totalText:SetText("Total: " .. addon.CombatTracker:FormatNumber(totalDamage))

    -- Update combat time
    if inCombat then
        self.frame.timeText:SetText(string.format("%.1fs", combatTime))
    else
        self.frame.timeText:SetText("0s")
    end

    -- Change color based on combat state
    if inCombat then
        self.frame.dpsText:SetTextColor(1, 1, 0, 1)          -- Yellow when in combat
        self.frame.playerText:SetTextColor(1, 1, 1, 1)       -- White
    else
        self.frame.dpsText:SetTextColor(0.7, 0.7, 0.7, 1)    -- Gray when out of combat
        self.frame.playerText:SetTextColor(0.7, 0.7, 0.7, 1) -- Gray
    end
end

-- Show the DPS window
function DPSWindow:Show()
    if not self.frame then
        self:Create()
    end
    self.frame:Show()
    addon.db.showDPSWindow = true
end

-- Hide the DPS window
function DPSWindow:Hide()
    if self.frame then
        self.frame:Hide()
    end
    addon.db.showDPSWindow = false
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
