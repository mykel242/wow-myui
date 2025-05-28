-- CombatTracker.lua
-- Tracks DPS and HPS for the player

local addonName, addon = ...

-- Combat tracker module
addon.CombatTracker = {}
local CombatTracker = addon.CombatTracker

-- Combat data storage
local combatData = {
    damage = 0,
    healing = 0,
    startTime = nil,
    inCombat = false,
    lastUpdate = 0
}

-- Initialize combat tracker
function CombatTracker:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering combat
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving combat
    self.frame:SetScript("OnEvent", function(self, event, ...)
        CombatTracker:OnEvent(event, ...)
    end)

    -- Update timer
    self.updateTimer = C_Timer.NewTicker(0.1, function()
        CombatTracker:UpdateDisplays()
    end)
end

-- Event handler
function CombatTracker:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self:StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:EndCombat()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:ParseCombatLog(CombatLogGetCurrentEventInfo())
    end
end

-- Start combat tracking
function CombatTracker:StartCombat()
    combatData.inCombat = true
    combatData.startTime = GetTime()
    combatData.damage = 0
    combatData.healing = 0
    combatData.lastUpdate = GetTime()
end

-- End combat tracking
function CombatTracker:EndCombat()
    combatData.inCombat = false
    -- Keep displaying the final numbers for a few seconds
    C_Timer.After(5, function()
        if not combatData.inCombat then
            combatData.damage = 0
            combatData.healing = 0
            combatData.startTime = nil
        end
    end)
end

-- Parse combat log events
function CombatTracker:ParseCombatLog(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
                                      destGUID, destName, destFlags, destRaidFlags, ...)
    local playerGUID = UnitGUID("player")

    -- Only track events where the player is the source
    if sourceGUID ~= playerGUID then
        return
    end

    -- Damage events
    if subevent == "SPELL_DAMAGE" or subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" then
        local amount
        if subevent == "SWING_DAMAGE" then
            amount = select(1, ...)
        else
            amount = select(4, ...)
        end

        if amount and amount > 0 then
            combatData.damage = combatData.damage + amount
        end

        -- Periodic damage (DOTs)
    elseif subevent == "SPELL_PERIODIC_DAMAGE" then
        local amount = select(4, ...)
        if amount and amount > 0 then
            combatData.damage = combatData.damage + amount
        end

        -- Healing events
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local amount = select(4, ...)
        if amount and amount > 0 then
            combatData.healing = combatData.healing + amount
        end
    end
end

-- Calculate DPS
function CombatTracker:GetDPS()
    if not combatData.inCombat or not combatData.startTime then
        return 0
    end

    local elapsed = GetTime() - combatData.startTime
    if elapsed <= 0 then
        return 0
    end

    return combatData.damage / elapsed
end

-- Calculate HPS
function CombatTracker:GetHPS()
    if not combatData.inCombat or not combatData.startTime then
        return 0
    end

    local elapsed = GetTime() - combatData.startTime
    if elapsed <= 0 then
        return 0
    end

    return combatData.healing / elapsed
end

-- Get total damage
function CombatTracker:GetTotalDamage()
    return combatData.damage
end

-- Get total healing
function CombatTracker:GetTotalHealing()
    return combatData.healing
end

-- Get combat duration
function CombatTracker:GetCombatTime()
    if not combatData.startTime then
        return 0
    end
    return GetTime() - combatData.startTime
end

-- Check if in combat
function CombatTracker:IsInCombat()
    return combatData.inCombat
end

-- Update all displays
function CombatTracker:UpdateDisplays()
    -- Update DPS window
    if addon.DPSWindow and addon.DPSWindow.frame and addon.DPSWindow.frame:IsShown() then
        addon.DPSWindow:UpdateDisplay()
    end

    -- Update HPS window
    if addon.HPSWindow and addon.HPSWindow.frame and addon.HPSWindow.frame:IsShown() then
        addon.HPSWindow:UpdateDisplay()
    end
end

-- Format numbers (like 1.5M, 2.3K, etc.)
function CombatTracker:FormatNumber(num)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end
