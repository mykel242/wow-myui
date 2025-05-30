-- CombatTracker.lua
-- Tracks DPS and HPS for the player
-- Refactored for readability and maintainability

local addonName, addon = ...

-- Combat tracker module
addon.CombatTracker = {}
local CombatTracker = addon.CombatTracker

-- ============================================================================
-- CONSTANTS AND CONFIGURATION
-- ============================================================================

local UPDATE_INTERVAL = 0.1 -- How often to update displays (seconds)

-- Event types we care about for damage tracking
local DAMAGE_EVENTS = {
    "SPELL_DAMAGE",
    "SPELL_PERIODIC_DAMAGE",
    "SWING_DAMAGE",
    "RANGE_DAMAGE",
    "SPELL_BUILDING_DAMAGE",
    "ENVIRONMENTAL_DAMAGE"
}

-- Event types we care about for healing tracking
local HEALING_EVENTS = {
    "SPELL_HEAL",
    "SPELL_PERIODIC_HEAL"
}

-- Event types we care about for absorb tracking
local ABSORB_AURA_EVENTS = {
    "SPELL_AURA_APPLIED",
    "SPELL_AURA_APPLIED_DOSE"
}

-- ============================================================================
-- DATA STORAGE
-- ============================================================================

-- Combat data storage - all combat statistics
local combatData = {
    -- Current combat values
    damage = 0,
    healing = 0,
    overheal = 0,
    absorb = 0,

    -- Combat timing
    startTime = nil,
    endTime = nil,
    inCombat = false,
    lastUpdate = 0,

    -- Peak values during combat
    maxDPS = 0,
    maxHPS = 0,

    -- Final values captured at combat end (for persistent display)
    finalDamage = 0,
    finalHealing = 0,
    finalOverheal = 0,
    finalAbsorb = 0,
    finalMaxDPS = 0,
    finalMaxHPS = 0,
    finalDPS = 0,
    finalHPS = 0,

    -- Debug statistics
    debugCounters = {
        totalEvents = 0,
        damageEvents = 0,
        healingEvents = 0,
        absorbEvents = 0,
        unknownEvents = 0
    }
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Debug print function - only prints when debug mode is enabled
local function DebugPrint(...)
    if addon.DEBUG then
        print("[CombatTracker]", ...)
    end
end

-- Check if an event type is in a list of event types
local function IsEventType(eventType, eventList)
    for _, validEvent in ipairs(eventList) do
        if eventType == validEvent then
            return true
        end
    end
    return false
end

-- ============================================================================
-- ABSORB SPELL DETECTION
-- ============================================================================

-- Future-proof absorb spell detection
-- Returns true if the spell name indicates an absorb effect
local function IsAbsorbSpell(spellName)
    if not spellName then
        return false
    end

    local lowerName = string.lower(spellName)

    -- Common patterns that indicate absorb spells
    local absorbPatterns = {
        "shield", "absorb", "barrier", "cocoon", "ward", "aegis", "protection",
        "deflection", "guard", "bulwark", "carapace", "shell", "mantle",
        "veil", "shroud"
    }

    -- Check if spell name contains any absorb patterns
    for _, pattern in ipairs(absorbPatterns) do
        if string.find(lowerName, pattern) then
            return true
        end
    end

    -- Specific spell names that don't follow common patterns
    local specificAbsorbSpells = {
        "strength of the black ox", "black ox", "divine aegis", "blazing barrier",
        "ice barrier", "mana shield", "bone armor", "frost armor", "demon skin",
        "fel armor", "anti-magic shell", "anti-magic zone", "temporal shield",
        "greater invisibility", "dampen magic"
    }

    -- Check specific spell names
    for _, specificSpell in ipairs(specificAbsorbSpells) do
        if string.find(lowerName, string.lower(specificSpell)) then
            return true
        end
    end

    return false
end

-- ============================================================================
-- COMBAT DATA MANAGEMENT
-- ============================================================================

-- Reset all combat data to initial state
local function ResetCombatData()
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
    combatData.lastUpdate = GetTime()

    -- Reset debug counters
    combatData.debugCounters = {
        totalEvents = 0,
        damageEvents = 0,
        healingEvents = 0,
        absorbEvents = 0,
        unknownEvents = 0
    }
end

-- Capture final values when combat ends (for persistent display)
local function CaptureFinalValues()
    -- Safety check for startTime
    if not combatData.startTime or not combatData.endTime then
        DebugPrint("ERROR: Missing startTime or endTime in CaptureFinalValues")
        combatData.finalDPS = 0
        combatData.finalHPS = 0
        return
    end

    local elapsed = combatData.endTime - combatData.startTime

    -- Calculate final rates
    if elapsed > 0 then
        combatData.finalDPS = combatData.damage / elapsed
        combatData.finalHPS = combatData.healing / elapsed
    else
        combatData.finalDPS = 0
        combatData.finalHPS = 0
    end

    -- Store final totals
    combatData.finalDamage = combatData.damage
    combatData.finalHealing = combatData.healing
    combatData.finalOverheal = combatData.overheal
    combatData.finalAbsorb = combatData.absorb
    combatData.finalMaxDPS = combatData.maxDPS
    combatData.finalMaxHPS = combatData.maxHPS

    DebugPrint(string.format("Final values captured - DPS: %.1f, HPS: %.1f",
        combatData.finalDPS, combatData.finalHPS))
end

-- ============================================================================
-- COMBAT LOG PARSING - INDIVIDUAL EVENT HANDLERS
-- ============================================================================

-- Handle damage events from the player
local function HandleDamageEvent(subevent, ...)
    local amount

    -- Different damage events have different argument structures
    if subevent == "SWING_DAMAGE" then
        amount = select(1, ...)
    elseif subevent == "ENVIRONMENTAL_DAMAGE" then
        amount = select(2, ...)
    else
        amount = select(4, ...) -- Most spell damage events
    end

    if amount and amount > 0 then
        combatData.damage = combatData.damage + amount
        combatData.debugCounters.damageEvents = combatData.debugCounters.damageEvents + 1
        DebugPrint(string.format("[DAMAGE] %s: +%d (total: %d)", subevent, amount, combatData.damage))
    end
end

-- Handle healing events from the player
local function HandleHealingEvent(subevent, spellName, ...)
    -- Skip if this spell was already processed as an absorb
    if IsAbsorbSpell(spellName) then
        return
    end

    local amount, overhealing, absorbed = select(4, ...), select(5, ...), select(6, ...)

    -- Track effective healing
    if amount and amount > 0 then
        combatData.healing = combatData.healing + amount
        combatData.debugCounters.healingEvents = combatData.debugCounters.healingEvents + 1
        DebugPrint(string.format("[HEALING] %s (%s): +%d (total: %d)",
            subevent, tostring(spellName), amount, combatData.healing))
    end

    -- Track overhealing
    if overhealing and overhealing > 0 then
        combatData.overheal = combatData.overheal + overhealing
        DebugPrint(string.format("[OVERHEAL] +%d (total: %d)", overhealing, combatData.overheal))
    end

    -- Track absorbs created by healing spells (backup method)
    if absorbed and absorbed > 0 then
        combatData.absorb = combatData.absorb + absorbed
        combatData.healing = combatData.healing + absorbed
        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        DebugPrint(string.format("*** HEALING EVENT ABSORB: %d (total: %d) ***", absorbed, combatData.absorb))
    end
end

-- Handle absorb aura events (shield creation)
local function HandleAbsorbAuraEvent(subevent, sourceGUID, sourceName, destGUID, destName, ...)
    local playerGUID = UnitGUID("player")
    local spellId, spellName, spellSchool, auraType, amount = select(1, ...)

    if not (spellName and IsAbsorbSpell(spellName)) then
        return false -- Not an absorb spell
    end

    DebugPrint("=== ABSORB AURA DETECTED ===")
    DebugPrint("Event: " .. subevent)
    DebugPrint("Spell: " .. tostring(spellName) .. " (ID: " .. tostring(spellId) .. ")")
    DebugPrint("Source: " .. tostring(sourceName) .. " (Player: " .. tostring(sourceGUID == playerGUID) .. ")")
    DebugPrint("Dest: " .. tostring(destName))
    DebugPrint("Aura Type: " .. tostring(auraType))

    -- Only track absorbs that originate from the player (healer mode)
    if sourceGUID ~= playerGUID then
        DebugPrint("*** ABSORB NOT TRACKED (not from player) ***")
        return true -- Was an absorb event, but not tracked
    end

    -- Determine who received the shield
    if destGUID == playerGUID then
        DebugPrint("^ Player shield applied to SELF")
    else
        DebugPrint("^ Player shield applied to ALLY: " .. tostring(destName))
    end

    -- Try to find absorb amount
    local absorbAmount = 0
    if amount and type(amount) == "number" and amount > 0 then
        absorbAmount = amount
        DebugPrint("Amount: " .. amount)
    else
        -- Search through all arguments for possible absorb amounts
        local args = { ... }
        for i = 1, math.min(10, #args) do
            local arg = args[i]
            if type(arg) == "number" and arg > 0 and arg < 10000000 then
                DebugPrint(string.format("  [%d] = %d ← POSSIBLE ABSORB", i, arg))
                if absorbAmount == 0 then
                    absorbAmount = arg
                end
            end
        end
    end

    -- Track the absorb
    if absorbAmount > 0 then
        combatData.absorb = combatData.absorb + absorbAmount
        combatData.healing = combatData.healing + absorbAmount
        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        DebugPrint(string.format("*** ABSORB TRACKED: +%d (total: %d) ***", absorbAmount, combatData.absorb))
    else
        DebugPrint("*** ABSORB NOT TRACKED (no valid amount found) ***")
    end

    DebugPrint("============================")
    return true -- Was an absorb event
end

-- Handle heal-based absorb events (spells that directly create absorbs)
local function HandleHealBasedAbsorb(subevent, spellName, destName, ...)
    if not IsAbsorbSpell(spellName) then
        return false -- Not an absorb spell
    end

    local amount, overhealing, absorbed = select(4, ...), select(5, ...), select(6, ...)

    DebugPrint("=== HEAL-BASED ABSORB ===")
    DebugPrint("Spell: " .. tostring(spellName))
    DebugPrint("Target: " .. tostring(destName))
    DebugPrint("Amount: " .. tostring(amount))
    DebugPrint("Absorbed: " .. tostring(absorbed))
    DebugPrint("=========================")

    if amount and amount > 0 then
        combatData.absorb = combatData.absorb + amount
        combatData.healing = combatData.healing + amount
        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        DebugPrint(string.format("*** HEAL-BASED ABSORB TRACKED: +%d ***", amount))
    end

    return true -- Was an absorb event
end

-- ============================================================================
-- MAIN COMBAT LOG PARSER
-- ============================================================================

-- Parse combat log events - main entry point
function CombatTracker:ParseCombatLog(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
                                      destGUID, destName, destFlags, destRaidFlags, ...)
    local playerGUID = UnitGUID("player")
    combatData.debugCounters.totalEvents = combatData.debugCounters.totalEvents + 1

    -- Handle SPELL_ABSORBED events (when absorb shields consume damage)
    if subevent == "SPELL_ABSORBED" then
        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        if addon.DEBUG then
            print("=== SPELL_ABSORBED EVENT ===")
            print("Event: " .. subevent)
            print("Source: " .. tostring(sourceName) .. " (attacking)")
            print("Dest: " .. tostring(destName) .. " (being protected)")
            print("*** SPELL_ABSORBED NOTED - Relying on creation events for tracking ***")
        end
        return -- Skip direct absorption tracking for now
    end

    -- Handle other absorb-related events
    if string.find(string.lower(subevent), "absorb") and subevent ~= "SPELL_ABSORBED" then
        combatData.debugCounters.absorbEvents = combatData.debugCounters.absorbEvents + 1
        DebugPrint("=== OTHER ABSORB EVENT ===")
        DebugPrint("Event: " .. subevent)
        DebugPrint("Source: " .. tostring(sourceName))
        -- Could implement specific handling here if needed
        return
    end

    -- Handle absorb aura applications (shield creation)
    if IsEventType(subevent, ABSORB_AURA_EVENTS) then
        if HandleAbsorbAuraEvent(subevent, sourceGUID, sourceName, destGUID, destName, ...) then
            return -- Was an absorb event, early exit
        end
    end

    -- Only track player-sourced events for damage and healing
    if sourceGUID ~= playerGUID then
        return
    end

    -- Handle damage events from player
    if IsEventType(subevent, DAMAGE_EVENTS) then
        HandleDamageEvent(subevent, ...)
        return
    end

    -- Handle healing events from player
    if IsEventType(subevent, HEALING_EVENTS) then
        local spellName = select(2, ...)

        -- Check if this is a heal-based absorb
        if HandleHealBasedAbsorb(subevent, spellName, destName, ...) then
            return -- Was an absorb, don't double-count as healing
        end

        -- Handle as regular healing
        HandleHealingEvent(subevent, spellName, ...)
        return
    end
end

-- ============================================================================
-- COMBAT STATE MANAGEMENT
-- ============================================================================

-- Start combat tracking
function CombatTracker:StartCombat()
    combatData.inCombat = true
    combatData.endTime = nil

    ResetCombatData()

    -- Set start time AFTER reset (since ResetCombatData sets it to nil)
    combatData.startTime = GetTime()

    print("Combat started!")
    DebugPrint("Combat tracking reset and started")
end

-- End combat tracking
function CombatTracker:EndCombat()
    if not combatData.inCombat then
        return
    end

    combatData.endTime = GetTime()

    -- Safety check for startTime
    if not combatData.startTime then
        DebugPrint("ERROR: startTime is nil in EndCombat, setting to endTime")
        combatData.startTime = combatData.endTime
    end

    local elapsed = combatData.endTime - combatData.startTime
    local elapsedMin = math.floor(elapsed / 60)
    local elapsedSec = elapsed % 60

    -- Capture final values before marking combat as ended
    CaptureFinalValues()
    combatData.inCombat = false

    -- Print combat summary
    print("Combat Ended")
    print("--------------------")
    print(string.format("Elapsed: %02d:%02d", elapsedMin, elapsedSec))
    print("--------------------")
    print(string.format("Final DPS: %s", self:FormatNumber(combatData.finalDPS)))
    print(string.format("Max DPS: %s", self:FormatNumber(combatData.finalMaxDPS)))
    print(string.format("Total Damage: %s", self:FormatNumber(combatData.finalDamage)))
    print(string.format("Final HPS: %s", self:FormatNumber(combatData.finalHPS)))
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
        print("--------------------")
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

-- Main event handler
function CombatTracker:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self:StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:EndCombat()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if combatData.inCombat then
            self:ParseCombatLog(CombatLogGetCurrentEventInfo())
        end
    end
end

-- ============================================================================
-- INITIALIZATION AND UPDATES
-- ============================================================================

-- Initialize combat tracker
function CombatTracker:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.frame:SetScript("OnEvent", function(self, event, ...)
        CombatTracker:OnEvent(event, ...)
    end)

    -- Update timer for displays and max value tracking
    self.updateTimer = C_Timer.NewTicker(UPDATE_INTERVAL, function()
        CombatTracker:UpdateDisplays()
    end)

    DebugPrint("Combat tracker initialized")
end

-- Update displays and track maximum values
function CombatTracker:UpdateDisplays()
    -- Track peak DPS and HPS during combat
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

    -- Update visible windows only
    if addon.DPSWindow and addon.DPSWindow.frame and addon.DPSWindow.frame:IsShown() then
        addon.DPSWindow:UpdateDisplay()
    end

    if addon.HPSWindow and addon.HPSWindow.frame and addon.HPSWindow.frame:IsShown() then
        addon.HPSWindow:UpdateDisplay()
    end
end

-- ============================================================================
-- PUBLIC API - DATA GETTERS
-- ============================================================================

-- Calculate current DPS
function CombatTracker:GetDPS()
    -- Return final DPS if combat has ended
    if not combatData.inCombat and combatData.finalDPS > 0 then
        return combatData.finalDPS
    end

    -- Calculate current DPS if in combat
    if not combatData.inCombat or not combatData.startTime then
        return 0
    end

    local elapsed = GetTime() - combatData.startTime
    return elapsed > 0 and (combatData.damage / elapsed) or 0
end

-- Calculate current HPS
function CombatTracker:GetHPS()
    -- Return final HPS if combat has ended
    if not combatData.inCombat and combatData.finalHPS > 0 then
        return combatData.finalHPS
    end

    -- Calculate current HPS if in combat
    if not combatData.inCombat or not combatData.startTime then
        return 0
    end

    local elapsed = GetTime() - combatData.startTime
    return elapsed > 0 and (combatData.healing / elapsed) or 0
end

-- Get total damage (use final value if combat ended)
function CombatTracker:GetTotalDamage()
    return (not combatData.inCombat and combatData.finalDamage > 0) and combatData.finalDamage or combatData.damage
end

-- Get total healing (use final value if combat ended)
function CombatTracker:GetTotalHealing()
    return (not combatData.inCombat and combatData.finalHealing > 0) and combatData.finalHealing or combatData.healing
end

-- Get total overheal (use final value if combat ended)
function CombatTracker:GetTotalOverheal()
    return (not combatData.inCombat and combatData.finalOverheal > 0) and combatData.finalOverheal or combatData
    .overheal
end

-- Get total absorb shields (use final value if combat ended)
function CombatTracker:GetTotalAbsorb()
    return (not combatData.inCombat and combatData.finalAbsorb > 0) and combatData.finalAbsorb or combatData.absorb
end

-- Get maximum DPS recorded (use final value if combat ended)
function CombatTracker:GetMaxDPS()
    return (not combatData.inCombat and combatData.finalMaxDPS > 0) and combatData.finalMaxDPS or combatData.maxDPS
end

-- Get maximum HPS recorded (use final value if combat ended)
function CombatTracker:GetMaxHPS()
    return (not combatData.inCombat and combatData.finalMaxHPS > 0) and combatData.finalMaxHPS or combatData.maxHPS
end

-- Get combat duration
function CombatTracker:GetCombatTime()
    return combatData.startTime and (GetTime() - combatData.startTime) or 0
end

-- Check if currently in combat
function CombatTracker:IsInCombat()
    return combatData.inCombat
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Format numbers with consistent decimal alignment
function CombatTracker:FormatNumber(num)
    if num >= 1000000 then
        return string.format("%.2fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.2fK", num / 1000)
    else
        return string.format("%.2f", num)
    end
end

-- Reset all statistics (for refresh button)
function CombatTracker:ResetDisplayStats()
    if not combatData.inCombat then
        ResetCombatData()
        DebugPrint("Combat stats reset")
    end
end

-- Get debug information (for status commands)
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
