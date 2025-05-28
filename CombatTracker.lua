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
    overheal = 0,
    absorb = 0,
    startTime = nil,
    endTime = nil,
    inCombat = false,
    lastUpdate = 0,
    maxDPS = 0,
    maxHPS = 0,
    -- Final values captured at combat end
    finalDamage = 0,
    finalHealing = 0,
    finalOverheal = 0,
    finalAbsorb = 0,
    finalMaxDPS = 0,
    finalMaxHPS = 0,
    finalDPS = 0,
    finalHPS = 0
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
        -- Capture final values IMMEDIATELY when combat ends, before any other processing
        if combatData.inCombat then
            -- Calculate final DPS/HPS rates while still in combat
            local elapsed = GetTime() - combatData.startTime
            if elapsed > 0 then
                combatData.finalDPS = combatData.damage / elapsed
                combatData.finalHPS = combatData.healing / elapsed
            else
                combatData.finalDPS = 0
                combatData.finalHPS = 0
            end

            -- Capture other final values
            combatData.finalDamage = combatData.damage
            combatData.finalHealing = combatData.healing
            combatData.finalOverheal = combatData.overheal
            combatData.finalAbsorb = combatData.absorb
            combatData.finalMaxDPS = combatData.maxDPS
            combatData.finalMaxHPS = combatData.maxHPS
        end
        self:EndCombat()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Only process combat events if we're still in combat
        if combatData.inCombat then
            self:ParseCombatLog(CombatLogGetCurrentEventInfo())
        end
    end
end

-- Start combat tracking
function CombatTracker:StartCombat()
    combatData.inCombat = true
    combatData.startTime = GetTime()
    combatData.endTime = nil
    combatData.damage = 0
    combatData.healing = 0
    combatData.overheal = 0
    combatData.absorb = 0
    combatData.maxDPS = 0
    combatData.maxHPS = 0
    combatData.finalDamage = 0
    combatData.finalHealing = 0
    combatData.finalOverheal = 0
    combatData.finalAbsorb = 0
    combatData.finalMaxDPS = 0
    combatData.finalMaxHPS = 0
    combatData.finalDPS = 0
    combatData.finalHPS = 0
    combatData.lastUpdate = GetTime()
    print("Combat started!")
end

-- End combat tracking
function CombatTracker:EndCombat()
    if not combatData.inCombat then return end

    combatData.endTime = GetTime()

    -- Calculate final values BEFORE setting inCombat to false
    local finalDPS = self:GetDPS()
    local finalHPS = self:GetHPS()
    local totalDamage = combatData.damage
    local totalHealing = combatData.healing
    local maxDPS = combatData.maxDPS
    local maxHPS = combatData.maxHPS

    -- Format timestamps
    local startTime = date("%H:%M:%S", combatData.startTime)
    local endTime = date("%H:%M:%S", combatData.endTime)
    local elapsed = combatData.endTime - combatData.startTime
    local elapsedMin = math.floor(elapsed / 60)
    local elapsedSec = elapsed % 60

    combatData.inCombat = false

    -- Print detailed combat summary
    print("Combat Ended")
    print("--------------------")
    print(string.format("Start: %s", startTime))
    print(string.format("End:   %s", endTime))
    print(string.format("Elapsed: %02d:%02d", elapsedMin, elapsedSec))
    print("--------------------")
    print(string.format("Max DPS: %s", self:FormatNumber(maxDPS)))
    print(string.format("Total Damage: %s", self:FormatNumber(totalDamage)))
    print(string.format("Max HPS: %s", self:FormatNumber(maxHPS)))
    print(string.format("Total Healing: %s", self:FormatNumber(totalHealing)))
    print(string.format("Total Overheal: %s", self:FormatNumber(combatData.finalOverheal)))
    print(string.format("Total Absorbs: %s", self:FormatNumber(combatData.finalAbsorb)))
    print("--------------------")

    -- Keep displaying the final numbers until manual reset or new combat
    -- Removed automatic reset timer - numbers persist until refresh clicked or new combat starts
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

        -- Healing events (now split between effective healing and overhealing)
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        -- For healing events: spellId, spellName, spellSchool, amount, overhealing, absorbed, critical
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical = select(1, ...)

        if amount and amount > 0 then
            -- Add all healing (including overhealing) to total for HPS calculation
            combatData.healing = combatData.healing + amount
        end

        if overhealing and overhealing > 0 then
            -- Track overhealing separately
            combatData.overheal = combatData.overheal + overhealing
            -- Removed debug spam since it's working
        end

        -- Absorb shield events
    elseif subevent == "SPELL_ABSORBED" then
        print("*** ABSORB EVENT DETECTED ***")
        local args = { ... }
        for i = 1, math.min(10, #args) do
            print(string.format("  arg[%d] = %s (%s)", i, tostring(args[i]), type(args[i])))
        end

        -- Try to find absorb amount - it's usually in position 8
        local absorbAmount = select(8, ...)
        if absorbAmount and absorbAmount > 0 then
            combatData.absorb = combatData.absorb + absorbAmount
            combatData.healing = combatData.healing + absorbAmount
            print(string.format("*** ABSORB: %d (total: %d) ***", absorbAmount, combatData.absorb))
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

-- Get total damage (use final value if combat ended)
function CombatTracker:GetTotalDamage()
    if not combatData.inCombat and combatData.finalDamage > 0 then
        return combatData.finalDamage
    end
    return combatData.damage
end

-- Get total healing (use final value if combat ended)
function CombatTracker:GetTotalHealing()
    if not combatData.inCombat and combatData.finalHealing > 0 then
        return combatData.finalHealing
    end
    return combatData.healing
end

-- Get total overheal (use final value if combat ended)
function CombatTracker:GetTotalOverheal()
    if not combatData.inCombat and combatData.finalOverheal > 0 then
        return combatData.finalOverheal
    end
    return combatData.overheal
end

-- Get total absorb shields (use final value if combat ended)
function CombatTracker:GetTotalAbsorb()
    if not combatData.inCombat and combatData.finalAbsorb > 0 then
        return combatData.finalAbsorb
    end
    return combatData.absorb
end

-- Get combat duration
function CombatTracker:GetCombatTime()
    if not combatData.startTime then
        return 0
    end
    return GetTime() - combatData.startTime
end

-- Get max DPS recorded (use final value if combat ended)
function CombatTracker:GetMaxDPS()
    if not combatData.inCombat and combatData.finalMaxDPS > 0 then
        return combatData.finalMaxDPS
    end
    return combatData.maxDPS
end

-- Get max HPS recorded (use final value if combat ended)
function CombatTracker:GetMaxHPS()
    if not combatData.inCombat and combatData.finalMaxHPS > 0 then
        return combatData.finalMaxHPS
    end
    return combatData.maxHPS
end

-- Reset display stats (for refresh button)
function CombatTracker:ResetDisplayStats()
    if not combatData.inCombat then
        combatData.damage = 0
        combatData.healing = 0
        combatData.overheal = 0
        combatData.absorb = 0
        combatData.maxDPS = 0
        combatData.maxHPS = 0
        combatData.finalDamage = 0
        combatData.finalHealing = 0
        combatData.finalOverheal = 0
        combatData.finalAbsorb = 0
        combatData.finalMaxDPS = 0
        combatData.finalMaxHPS = 0
        combatData.finalDPS = 0
        combatData.finalHPS = 0
        combatData.startTime = nil
        combatData.endTime = nil
    end
end

-- Check if in combat
function CombatTracker:IsInCombat()
    return combatData.inCombat
end

-- Update all displays
function CombatTracker:UpdateDisplays()
    -- Track max DPS and HPS during combat
    if combatData.inCombat then
        local currentDPS = self:GetDPS()
        local currentHPS = self:GetHPS()

        if currentDPS > combatData.maxDPS then
            combatData.maxDPS = currentDPS
        end

        if currentHPS > combatData.maxHPS then
            combatData.maxHPS = currentHPS
        end
    end

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
