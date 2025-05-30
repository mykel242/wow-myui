-- CombatTracker.lua
-- Tracks DPS and HPS for the player - Enhanced Debug Version

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
    finalHPS = 0,
    -- Debug counters
    debugCounters = {
        totalEvents = 0,
        damageEvents = 0,
        healingEvents = 0,
        absorbEvents = 0,
        unknownEvents = 0
    }
}

-- Debug function
local function DebugPrint(...)
    if addon.DEBUG then
        print("[CombatTracker]", ...)
    end
end

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

    DebugPrint("Combat tracker initialized")
end

-- Event handler
function CombatTracker:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self:StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Capture final values IMMEDIATELY when combat ends
        if combatData.inCombat then
            local elapsed = GetTime() - combatData.startTime
            DebugPrint("Combat ending: elapsed=%.1f, damage=%d, healing=%d", elapsed, combatData.damage,
                combatData.healing)

            if elapsed > 0 then
                combatData.finalDPS = combatData.damage / elapsed
                combatData.finalHPS = combatData.healing / elapsed
                DebugPrint("Calculated finalDPS=%.1f, finalHPS=%.1f", combatData.finalDPS, combatData.finalHPS)
            else
                combatData.finalDPS = 0
                combatData.finalHPS = 0
                DebugPrint("Elapsed time was 0, setting final values to 0")
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
        if combatData.inCombat then
            combatData.debugCounters.totalEvents = combatData.debugCounters.totalEvents + 1
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

    -- Reset debug counters
    combatData.debugCounters = {
        totalEvents = 0,
        damageEvents = 0,
        healingEvents = 0,
        absorbEvents = 0,
        unknownEvents = 0
    }

    print("Combat started!")
    DebugPrint("Combat tracking reset and started")
end

-- End combat tracking
function CombatTracker:EndCombat()
    if not combatData.inCombat then return end

    combatData.endTime = GetTime()
    local elapsed = combatData.endTime - combatData.startTime
    local elapsedMin = math.floor(elapsed / 60)
    local elapsedSec = elapsed % 60

    combatData.inCombat = false

    -- Print detailed combat summary
    print("Combat Ended")
    print("--------------------")
    print(string.format("Elapsed: %02d:%02d", elapsedMin, elapsedSec))
    print("--------------------")
    print(string.format("Max DPS: %s", self:FormatNumber(combatData.finalMaxDPS)))
    print(string.format("Total Damage: %s", self:FormatNumber(combatData.finalDamage)))
    print(string.format("Max HPS: %s", self:FormatNumber(combatData.finalMaxHPS)))
    print(string.format("Total Healing: %s", self:FormatNumber(combatData.finalHealing)))
    print(string.format("Total Overheal: %s", self:FormatNumber(combatData.finalOverheal)))
    print(string.format("Total Absorbs: %s", self:FormatNumber(combatData.finalAbsorb)))
    print("--------------------")

    -- Print debug statistics
    if addon.DEBUG then
        print("Debug Statistics:")
        print(string.format("Total Events: %d", combatData.debugCounters.totalEvents))
        print(string.format("Damage Events: %d", combatData.debugCounters.damageEvents))
        print(string.format("Healing Events: %d", combatData.debugCounters.healingEvents))
        print(string.format("Absorb Events: %d", combatData.debugCounters.absorbEvents))
        print(string.format("Unknown Events: %d", combatData.debugCounters.unknownEvents))
        print("--------------------")
    end
end

-- Parse combat log events
-- Parse combat log events - Replace the ENTIRE function with this
function CombatTracker:ParseCombatLog(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
                                      destGUID, destName, destFlags, destRaidFlags, ...)
    local playerGUID = UnitGUID("player")

    -- FIRST: Let's see ALL absorb-related events regardless of source/dest
    if string.find(string.lower(subevent), "absorb") then
        print("=== ABSORB EVENT DETECTED ===")
        print("Event: " .. subevent)
        print("Source: " .. tostring(sourceName) .. " (Player: " .. tostring(sourceGUID == playerGUID) .. ")")
        print("Dest: " .. tostring(destName) .. " (Player: " .. tostring(destGUID == playerGUID) .. ")")

        local args = { ... }
        print("Arguments (" .. #args .. " total):")
        for i = 1, math.min(15, #args) do
            local arg = args[i]
            local argType = type(arg)
            if argType == "number" then
                print(string.format("  [%d] = %d (number)", i, arg))
            else
                print(string.format("  [%d] = %s (%s)", i, tostring(arg), argType))
            end
        end
        print("=============================")

        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        return -- Exit early to focus on absorb events only
    end

    -- Only track events where the player is the source for damage/healing
    if sourceGUID ~= playerGUID then
        return
    end

    -- Damage events
    if subevent == "SPELL_DAMAGE" or subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" or subevent == "SPELL_PERIODIC_DAMAGE" then
        local amount
        if subevent == "SWING_DAMAGE" then
            amount = select(1, ...)
        else
            amount = select(4, ...)
        end

        if amount and amount > 0 then
            combatData.damage = combatData.damage + amount
            combatData.debugCounters.damageEvents = combatData.debugCounters.damageEvents + 1
            if addon.DEBUG then
                print(string.format("[DAMAGE] +%d (total: %d)", amount, combatData.damage))
            end
        end

        -- Healing events
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical = select(1, ...)

        if amount and amount > 0 then
            combatData.healing = combatData.healing + amount
            combatData.debugCounters.healingEvents = combatData.debugCounters.healingEvents + 1
            if addon.DEBUG then
                print(string.format("[HEALING] +%d (total: %d)", amount, combatData.healing))
            end
        end

        if overhealing and overhealing > 0 then
            combatData.overheal = combatData.overheal + overhealing
            if addon.DEBUG then
                print(string.format("[OVERHEAL] +%d (total: %d)", overhealing, combatData.overheal))
            end
        end

        -- Check if this healing event also created an absorb shield
        if absorbed and absorbed > 0 then
            combatData.absorb = combatData.absorb + absorbed
            combatData.healing = combatData.healing + absorbed
            combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
            print(string.format("*** HEALING ABSORB: %d (total: %d) ***", absorbed, combatData.absorb))
        end

        -- Look for shield/absorb-related aura events from ANY source/dest
    elseif (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_APPLIED_DOSE") then
        local spellId, spellName, spellSchool = select(1, ...)
        if spellName then
            local lowerName = string.lower(spellName)
            if string.find(lowerName, "shield") or
                string.find(lowerName, "absorb") or
                string.find(lowerName, "barrier") or
                string.find(lowerName, "ward") then
                print("=== ABSORB AURA DETECTED ===")
                print("Event: " .. subevent)
                print("Spell: " .. tostring(spellName) .. " (ID: " .. tostring(spellId) .. ")")
                print("Source: " .. tostring(sourceName))
                print("Dest: " .. tostring(destName))

                local args = { ... }
                for i = 1, math.min(10, #args) do
                    local arg = args[i]
                    if type(arg) == "number" then
                        print(string.format("  [%d] = %d", i, arg))
                    else
                        print(string.format("  [%d] = %s", i, tostring(arg)))
                    end
                end
                print("===========================")
            end
        end
    end

    combatData.debugCounters.totalEvents = combatData.debugCounters.totalEvents + 1
end

-- Calculate DPS
function CombatTracker:GetDPS()
    if not combatData.inCombat and combatData.finalDPS > 0 then
        return combatData.finalDPS
    end

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
    if not combatData.inCombat and combatData.finalHPS > 0 then
        return combatData.finalHPS
    end

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
        combatData.debugCounters = {
            totalEvents = 0,
            damageEvents = 0,
            healingEvents = 0,
            absorbEvents = 0,
            unknownEvents = 0
        }
        DebugPrint("Combat stats reset")
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

-- Debug function to get current combat data
function CombatTracker:GetDebugInfo()
    return {
        inCombat = combatData.inCombat,
        damage = combatData.damage,
        healing = combatData.healing,
        overheal = combatData.overheal,
        absorb = combatData.absorb,
        counters = combatData.debugCounters,
        dps = self:GetDPS(),
        hps = self:GetHPS()
    }
end
