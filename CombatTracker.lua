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
        -- Capture final values IMMEDIATELY when combat ends, before any other processing
        if combatData.inCombat then
            -- Calculate final DPS/HPS rates while still in combat
            local elapsed = GetTime() - combatData.startTime
            if addon.DEBUG then
                print(string.format("Combat ending: elapsed=%.1f, damage=%d, healing=%d", elapsed, combatData.damage,
                    combatData.healing))
            end

            if elapsed > 0 then
                combatData.finalDPS = combatData.damage / elapsed
                combatData.finalHPS = combatData.healing / elapsed
                if addon.DEBUG then
                    print(string.format("Calculated finalDPS=%.1f, finalHPS=%.1f", combatData.finalDPS,
                        combatData.finalHPS))
                end
            else
                combatData.finalDPS = 0
                combatData.finalHPS = 0
                if addon.DEBUG then
                    print("Elapsed time was 0, setting final values to 0")
                end
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
    if addon.DEBUG then
        print("[CombatTracker] Combat tracking reset and started")
    end
end

-- End combat tracking
function CombatTracker:EndCombat()
    if not combatData.inCombat then return end

    combatData.endTime = GetTime()
    local elapsed = combatData.endTime - combatData.startTime
    local elapsedMin = math.floor(elapsed / 60)
    local elapsedSec = elapsed % 60

    -- CAPTURE FINAL VALUES BEFORE SETTING inCombat TO FALSE
    local finalDPS = combatData.damage / (elapsed > 0 and elapsed or 1)
    local finalHPS = combatData.healing / (elapsed > 0 and elapsed or 1)
    local totalDamage = combatData.damage
    local totalHealing = combatData.healing
    local totalOverheal = combatData.overheal
    local totalAbsorb = combatData.absorb
    local maxDPS = combatData.maxDPS
    local maxHPS = combatData.maxHPS

    -- Store final values for persistent display
    combatData.finalDPS = finalDPS
    combatData.finalHPS = finalHPS
    combatData.finalDamage = totalDamage
    combatData.finalHealing = totalHealing
    combatData.finalOverheal = totalOverheal
    combatData.finalAbsorb = totalAbsorb
    combatData.finalMaxDPS = maxDPS
    combatData.finalMaxHPS = maxHPS

    -- NOW set inCombat to false
    combatData.inCombat = false

    -- Print detailed combat summary using the captured values
    print("Combat Ended")
    print("--------------------")
    print(string.format("Elapsed: %02d:%02d", elapsedMin, elapsedSec))
    print("--------------------")
    print(string.format("Final DPS: %s", self:FormatNumber(finalDPS)))
    print(string.format("Max DPS: %s", self:FormatNumber(maxDPS)))
    print(string.format("Total Damage: %s", self:FormatNumber(totalDamage)))
    print(string.format("Final HPS: %s", self:FormatNumber(finalHPS)))
    print(string.format("Max HPS: %s", self:FormatNumber(maxHPS)))
    print(string.format("Total Healing: %s", self:FormatNumber(totalHealing)))
    print(string.format("Total Overheal: %s", self:FormatNumber(totalOverheal)))
    print(string.format("Total Absorbs: %s", self:FormatNumber(totalAbsorb)))
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

-- Parse combat log events - COMPLETE FUNCTION REPLACEMENT (FIXED DEBUG CHECKS)
function CombatTracker:ParseCombatLog(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
                                      destGUID, destName, destFlags, destRaidFlags, ...)
    local playerGUID = UnitGUID("player")

    -- ENHANCED ABSORB DETECTION - Multiple methods
    local isAbsorbEvent = false
    local absorbAmount = 0
    local shouldTrack = false

    -- Method 1: SPELL_ABSORBED events (when your absorb shields absorb damage)
    if subevent == "SPELL_ABSORBED" then
        isAbsorbEvent = true

        -- ONLY show debug if debug is actually enabled
        if addon.DEBUG then
            print("=== SPELL_ABSORBED EVENT ===")
            print("Event: " .. subevent)
            print("Source: " .. tostring(sourceName) .. " (attacking)")
            print("Dest: " .. tostring(destName) .. " (being protected)")
        end

        -- For SPELL_ABSORBED, we care if the DESTINATION is the player
        -- (meaning YOUR absorb shield absorbed the damage)
        if destGUID == playerGUID then
            shouldTrack = true
            if addon.DEBUG then
                print("^ This is YOUR absorb shield working!")
            end
        end

        local args = { ... }
        if addon.DEBUG then
            print("Arguments (" .. #args .. " total):")
            for i = 1, math.min(15, #args) do
                local arg = args[i]
                if type(arg) == "number" and arg > 0 and arg < 10000000 then
                    print(string.format("  [%d] = %d (number) ← POSSIBLE ABSORB AMOUNT", i, arg))
                    if absorbAmount == 0 and arg > 100 then -- Take first reasonable amount > 100
                        absorbAmount = arg
                    end
                else
                    print(string.format("  [%d] = %s (%s)", i, tostring(arg), type(arg)))
                end
            end
        else
            -- Even without debug, try to find absorb amount
            for i = 1, math.min(15, #args) do
                local arg = args[i]
                if type(arg) == "number" and arg > 100 and arg < 10000000 and absorbAmount == 0 then
                    absorbAmount = arg
                    break
                end
            end
        end

        -- The absorb amount in SPELL_ABSORBED is often in position 8 or 5
        if absorbAmount == 0 then
            local possibleAmounts = { select(8, ...), select(5, ...), select(3, ...) }
            for _, amount in ipairs(possibleAmounts) do
                if type(amount) == "number" and amount > 100 and amount < 10000000 then
                    absorbAmount = amount
                    if addon.DEBUG then
                        print(string.format("Using absorb amount: %d", amount))
                    end
                    break
                end
            end
        end

        if addon.DEBUG then
            print("============================")
        end
    end

    -- Method 2: Direct absorb events (other types)
    if string.find(string.lower(subevent), "absorb") and subevent ~= "SPELL_ABSORBED" then
        isAbsorbEvent = true
        if addon.DEBUG then
            print("=== OTHER ABSORB EVENT ===")
            print("Event: " .. subevent)
            print("Source: " .. tostring(sourceName) .. " (Player: " .. tostring(sourceGUID == playerGUID) .. ")")
            print("Dest: " .. tostring(destName) .. " (Player: " .. tostring(destGUID == playerGUID) .. ")")
        end

        if sourceGUID == playerGUID then
            shouldTrack = true
        end

        local args = { ... }
        if addon.DEBUG then
            print("Arguments (" .. #args .. " total):")
            for i = 1, math.min(15, #args) do
                local arg = args[i]
                if type(arg) == "number" and arg > 0 and arg < 10000000 then
                    print(string.format("  [%d] = %d (number) ← POSSIBLE ABSORB AMOUNT", i, arg))
                    if absorbAmount == 0 then absorbAmount = arg end
                else
                    print(string.format("  [%d] = %s (%s)", i, tostring(arg), type(arg)))
                end
            end
            print("============================")
        end
    end

    -- Method 3: Shield/Absorb aura applications
    if (subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_APPLIED_DOSE") then
        local spellId, spellName, spellSchool, auraType, amount = select(1, ...)
        if spellName then
            local lowerName = string.lower(spellName)
            if string.find(lowerName, "shield") or
                string.find(lowerName, "absorb") or
                string.find(lowerName, "barrier") or
                string.find(lowerName, "cocoon") or
                string.find(lowerName, "ward") then
                isAbsorbEvent = true
                if addon.DEBUG then
                    print("=== ABSORB AURA DETECTED ===")
                    print("Event: " .. subevent)
                    print("Spell: " .. tostring(spellName) .. " (ID: " .. tostring(spellId) .. ")")
                    print("Source: " .. tostring(sourceName) .. " (Player: " .. tostring(sourceGUID == playerGUID) .. ")")
                    print("Dest: " .. tostring(destName) .. " (Player: " .. tostring(destGUID == playerGUID) .. ")")
                    print("Aura Type: " .. tostring(auraType))
                end

                if sourceGUID == playerGUID then
                    shouldTrack = true
                end

                if amount and type(amount) == "number" and amount > 0 then
                    if addon.DEBUG then
                        print("Amount: " .. amount)
                    end
                    absorbAmount = amount
                end

                local args = { ... }
                if addon.DEBUG then
                    for i = 1, math.min(10, #args) do
                        local arg = args[i]
                        if type(arg) == "number" and arg > 0 and arg < 10000000 then
                            print(string.format("  [%d] = %d ← POSSIBLE ABSORB", i, arg))
                            if absorbAmount == 0 then absorbAmount = arg end
                        else
                            print(string.format("  [%d] = %s", i, tostring(arg)))
                        end
                    end
                    print("============================")
                end
            end
        end
    end

    -- Method 4: Healing events that create absorbs
    if sourceGUID == playerGUID and (subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL") then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical = select(1, ...)

        if spellName then
            local lowerName = string.lower(spellName)
            if string.find(lowerName, "shield") or
                string.find(lowerName, "absorb") or
                string.find(lowerName, "barrier") or
                string.find(lowerName, "cocoon") then
                isAbsorbEvent = true
                shouldTrack = true
                if addon.DEBUG then
                    print("=== HEAL-BASED ABSORB ===")
                    print("Spell: " .. tostring(spellName))
                    print("Amount: " .. tostring(amount))
                    print("Absorbed: " .. tostring(absorbed))
                    print("=========================")
                end
                if amount and amount > 0 then
                    absorbAmount = amount
                end
            end
        end
    end

    -- ACTUALLY ADD ABSORB TO TRACKING
    if isAbsorbEvent and absorbAmount > 0 and shouldTrack then
        combatData.absorb = combatData.absorb + absorbAmount
        combatData.healing = combatData.healing + absorbAmount
        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        if addon.DEBUG then
            print(string.format("*** ABSORB TRACKED: +%d (total absorb: %d, total healing: %d) ***",
                absorbAmount, combatData.absorb, combatData.healing))
        end
    elseif isAbsorbEvent then
        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        -- ONLY show debug messages when debug is enabled
        if addon.DEBUG then
            if not shouldTrack then
                print("*** ABSORB EVENT DETECTED BUT NOT TRACKED (not player-related) ***")
            else
                print("*** ABSORB EVENT DETECTED BUT NOT TRACKED (no valid amount found) ***")
            end
        end
    end

    -- Early exit if this was an absorb event to avoid double processing
    if isAbsorbEvent then
        return
    end

    -- Only track regular events where the player is the source for damage/healing
    if sourceGUID ~= playerGUID then
        return
    end

    -- FIXED DAMAGE EVENT DETECTION
    if subevent == "SPELL_DAMAGE" or
        subevent == "SPELL_PERIODIC_DAMAGE" or
        subevent == "SWING_DAMAGE" or
        subevent == "RANGE_DAMAGE" or
        subevent == "SPELL_BUILDING_DAMAGE" or
        subevent == "ENVIRONMENTAL_DAMAGE" then
        local amount, overkill, school, resisted, blocked, absorbed, critical

        if subevent == "SWING_DAMAGE" then
            amount, overkill, school, resisted, blocked, absorbed, critical = select(1, ...)
        elseif subevent == "ENVIRONMENTAL_DAMAGE" then
            -- Environmental damage has different structure
            amount = select(2, ...)
        else
            -- Most spell damage events
            amount, overkill, school, resisted, blocked, absorbed, critical = select(4, ...)
        end

        if amount and amount > 0 then
            combatData.damage = combatData.damage + amount
            combatData.debugCounters.damageEvents = combatData.debugCounters.damageEvents + 1
            if addon.DEBUG then
                print(string.format("[DAMAGE] %s: +%d (total: %d)", subevent, amount, combatData.damage))
            end
        end

        -- Regular healing events (excluding absorb spells which were handled above)
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical = select(1, ...)

        -- Skip if this was already processed as an absorb above
        if spellName then
            local lowerName = string.lower(spellName)
            if string.find(lowerName, "shield") or
                string.find(lowerName, "absorb") or
                string.find(lowerName, "barrier") or
                string.find(lowerName, "cocoon") then
                return -- Already processed above
            end
        end

        if amount and amount > 0 then
            combatData.healing = combatData.healing + amount
            combatData.debugCounters.healingEvents = combatData.debugCounters.healingEvents + 1
            if addon.DEBUG then
                print(string.format("[HEALING] %s (%s): +%d (total: %d)",
                    subevent, tostring(spellName), amount, combatData.healing))
            end
        end

        if overhealing and overhealing > 0 then
            combatData.overheal = combatData.overheal + overhealing
            if addon.DEBUG then
                print(string.format("[OVERHEAL] +%d (total: %d)", overhealing, combatData.overheal))
            end
        end

        -- Check if this healing event also created an absorb shield (backup method)
        if absorbed and absorbed > 0 then
            combatData.absorb = combatData.absorb + absorbed
            combatData.healing = combatData.healing + absorbed
            combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
            if addon.DEBUG then
                print(string.format("*** HEALING EVENT ABSORB: %d (total: %d) ***", absorbed, combatData.absorb))
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

    -- Only update displays if windows are actually visible
    -- This reduces unnecessary work when windows are hidden

    -- Update DPS window
    if addon.DPSWindow and addon.DPSWindow.frame and addon.DPSWindow.frame:IsShown() then
        addon.DPSWindow:UpdateDisplay()
    end

    -- Update HPS window
    if addon.HPSWindow and addon.HPSWindow.frame and addon.HPSWindow.frame:IsShown() then
        addon.HPSWindow:UpdateDisplay()
    end
end

-- Format numbers with aligned decimal points - COMPLETE FUNCTION REPLACEMENT
function CombatTracker:FormatNumber(num)
    local formatted

    if num >= 1000000 then
        local millions = num / 1000000
        -- Always show exactly 2 decimal places for consistent alignment
        formatted = string.format("%.2fM", millions)
    elseif num >= 1000 then
        local thousands = num / 1000
        -- Always show exactly 2 decimal places for consistent alignment
        formatted = string.format("%.2fK", thousands)
    else
        -- For numbers under 1000, show 2 decimal places
        formatted = string.format("%.2f", num)
    end

    return formatted
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
