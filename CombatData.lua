-- CombatData.lua
-- Core combat data storage and tracking

local addonName, addon = ...

-- Combat data module
addon.CombatData = {}
local CombatData = addon.CombatData

-- =============================================================================
-- DATA STRUCTURES
-- =============================================================================

-- Unified calculator instance
local calculator = nil

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
    -- Last sample time
    lastSampleTime = 0,
    -- Previous sample values for calculating deltas
    lastSampleDamage = 0,
    lastSampleHealing = 0,
    lastSampleOverheal = 0,
    lastSampleAbsorb = 0
}

-- Combat action counter
local combatActionCount = 0

-- =============================================================================
-- COMBAT TRACKING API
-- =============================================================================

-- Calculate DPS using unified calculator
function CombatData:GetDPS()
    if calculator then
        return calculator:GetDPS()
    end
    -- Fallback to original logic
    if combatData.inCombat then
        return addon.TimelineTracker:GetRollingDPS()
    else
        return combatData.finalDPS or 0
    end
end

-- Calculate HPS using unified calculator
function CombatData:GetHPS()
    if calculator then
        return calculator:GetHPS()
    end
    -- Fallback to original logic
    if combatData.inCombat then
        return addon.TimelineTracker:GetRollingHPS()
    else
        return combatData.finalHPS or 0
    end
end

-- Get displayed DPS for meters using unified calculator
function CombatData:GetDisplayDPS()
    if calculator then
        return calculator:GetDPS(true)
    end
    -- Fallback to original logic
    if combatData.inCombat then
        return addon.TimelineTracker:GetRollingDPS()
    else
        return combatData.finalDPS or 0
    end
end

-- Get displayed HPS for meters using unified calculator
function CombatData:GetDisplayHPS()
    if calculator then
        return calculator:GetHPS(true)
    end
    -- Fallback to original logic
    if combatData.inCombat then
        return addon.TimelineTracker:GetRollingHPS()
    else
        return combatData.finalHPS or 0
    end
end

-- Get total damage (use final value if combat ended)
function CombatData:GetTotalDamage()
    if not combatData.inCombat and combatData.finalDamage > 0 then
        return combatData.finalDamage
    end
    return combatData.damage
end

-- Get total healing (use final value if combat ended)
function CombatData:GetTotalHealing()
    if not combatData.inCombat and combatData.finalHealing > 0 then
        return combatData.finalHealing
    end
    return combatData.healing
end

-- Get total overheal (use final value if combat ended)
function CombatData:GetTotalOverheal()
    if not combatData.inCombat and combatData.finalOverheal > 0 then
        return combatData.finalOverheal
    end
    return combatData.overheal
end

-- Get total absorb shields (use final value if combat ended)
function CombatData:GetTotalAbsorb()
    if not combatData.inCombat and combatData.finalAbsorb > 0 then
        return combatData.finalAbsorb
    end
    return combatData.absorb
end

-- Get combat duration (alias for GetElapsed)
function CombatData:GetCombatTime()
    return self:GetElapsed()
end

-- Get elapsed combat time
function CombatData:GetElapsed()
    if not combatData.startTime then
        return 0
    end

    if not combatData.inCombat and combatData.endTime then
        return combatData.endTime - combatData.startTime
    end

    return GetTime() - combatData.startTime
end

-- Access combat data for calculator
function CombatData:GetRawData()
    return combatData
end

-- Get totals for calculator
function CombatData:GetTotalDamageRaw()
    return combatData.damage
end

function CombatData:GetTotalHealingRaw()
    return combatData.healing
end

-- Get max DPS recorded using unified calculator
function CombatData:GetMaxDPS()
    if calculator then
        return calculator:GetMaxDPS()
    end
    -- Fallback to original logic
    if not combatData.inCombat and combatData.finalMaxDPS > 0 then
        return combatData.finalMaxDPS
    end
    return combatData.maxDPS
end

-- Get max HPS recorded using unified calculator
function CombatData:GetMaxHPS()
    if calculator then
        return calculator:GetMaxHPS()
    end
    -- Fallback to original logic
    if not combatData.inCombat and combatData.finalMaxHPS > 0 then
        return combatData.finalMaxHPS
    end
    return combatData.maxHPS
end

-- Check if in combat
function CombatData:IsInCombat()
    return combatData.inCombat
end

-- Get the final peak values from the last completed combat
function CombatData:GetLastCombatMaxDPS()
    return combatData.finalMaxDPS or 0
end

function CombatData:GetLastCombatMaxHPS()
    return combatData.finalMaxHPS or 0
end

-- Get raw combat data (for other modules)
function CombatData:GetRawCombatData()
    return combatData
end

-- Get action count
function CombatData:GetActionCount()
    return combatActionCount
end

-- =============================================================================
-- COMBAT EVENT HANDLERS
-- =============================================================================

-- Start combat tracking
function CombatData:StartCombat()
    combatData.inCombat = true
    combatData.startTime = GetTime()
    combatData.endTime = nil
    combatData.damage = 0
    combatData.healing = 0
    combatData.overheal = 0
    combatData.absorb = 0
    combatData.maxDPS = 0
    combatData.maxHPS = 0
    combatData.lastUpdate = GetTime()

    -- Reset sampling data
    combatData.lastSampleTime = combatData.startTime
    combatData.lastSampleDamage = 0
    combatData.lastSampleHealing = 0
    combatData.lastSampleOverheal = 0
    combatData.lastSampleAbsorb = 0

    -- Reset action counter
    combatActionCount = 0

    -- Tell timeline tracker to reset
    if addon.TimelineTracker then
        addon.TimelineTracker:StartCombat()
    end

    -- === ADD THIS: Start enhanced logging ===
    if addon.EnhancedCombatLogger then
        addon.EnhancedCombatLogger:StartEnhancedTracking()
    end

    addon:DebugPrint("Combat started!")
end

-- End combat tracking
function CombatData:EndCombat()
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

    -- Capture final values BEFORE setting inCombat to false
    if elapsed > 0 then
        combatData.finalDPS = combatData.damage / elapsed
        combatData.finalHPS = combatData.healing / elapsed
    else
        combatData.finalDPS = 0
        combatData.finalHPS = 0
    end

    combatData.finalDamage = combatData.damage
    combatData.finalHealing = combatData.healing
    combatData.finalOverheal = combatData.overheal
    combatData.finalAbsorb = combatData.absorb
    combatData.finalMaxDPS = combatData.maxDPS
    combatData.finalMaxHPS = combatData.maxHPS

    -- ENHANCED DATA COLLECTION - Get enhanced data BEFORE ending tracking
    local enhancedData = nil
    if addon.EnhancedCombatLogger then
        enhancedData = addon.EnhancedCombatLogger:GetEnhancedSessionData()

        -- Debug enhanced data collection
        if addon.DEBUG and enhancedData then
            local participantCount = 0
            if enhancedData.participants then
                for _ in pairs(enhancedData.participants) do
                    participantCount = participantCount + 1
                end
            end
            addon:DebugPrint(string.format("Enhanced data collected: %d participants, %d cooldowns, %d deaths",
                participantCount,
                #(enhancedData.cooldownUsage or {}),
                #(enhancedData.deaths or {})))
        end

        -- End enhanced tracking AFTER collecting data
        addon.EnhancedCombatLogger:EndEnhancedTracking()
    end

    combatData.inCombat = false

    -- Tell timeline tracker to end combat
    if addon.TimelineTracker then
        addon.TimelineTracker:EndCombat()
    end

    -- Debug combat summary (only when debug enabled)
    if addon.DEBUG then
        addon:DebugPrint("Combat Ended")
        addon:DebugPrint("--------------------")
        addon:DebugPrint(string.format("Start: %s", startTime))
        addon:DebugPrint(string.format("End:   %s", endTime))
        addon:DebugPrint(string.format("Elapsed: %02d:%02d", elapsedMin, elapsedSec))
        addon:DebugPrint("--------------------")
        addon:DebugPrint(string.format("Max DPS: %s", addon.CombatTracker:FormatNumber(maxDPS)))
        addon:DebugPrint(string.format("Total Damage: %s", addon.CombatTracker:FormatNumber(totalDamage)))
        addon:DebugPrint(string.format("Max HPS: %s", addon.CombatTracker:FormatNumber(maxHPS)))
        addon:DebugPrint(string.format("Total Healing: %s", addon.CombatTracker:FormatNumber(totalHealing)))
        addon:DebugPrint(string.format("Total Overheal: %s", addon.CombatTracker:FormatNumber(combatData.finalOverheal)))
        addon:DebugPrint(string.format("Total Absorbs: %s", addon.CombatTracker:FormatNumber(combatData.finalAbsorb)))
        if addon.TimelineTracker then
            local timelineData = addon.TimelineTracker:GetTimelineData()
            addon:DebugPrint(string.format("Timeline Samples: %d", #timelineData))
        end
    end

    -- Enhanced data summary
    if enhancedData then
        local participantCount = 0
        if enhancedData.participants then
            for _ in pairs(enhancedData.participants) do
                participantCount = participantCount + 1
            end
        end
        if addon.DEBUG then
            addon:DebugPrint(string.format("Enhanced Data: %d participants, %d cooldowns, %d deaths",
                participantCount,
                #(enhancedData.cooldownUsage or {}),
                #(enhancedData.deaths or {})))
        end
    end

    -- Create and store session record WITH enhanced data
    if addon.SessionManager then
        local session = addon.SessionManager:CreateSessionFromCombatData(enhancedData)
        if session then
            addon.SessionManager:AddSessionToHistory(session)

            -- Verify enhanced data was attached
            if addon.DEBUG then
                if session.enhancedData then
                    print("✓ Session created with enhanced data")
                else
                    print("✗ Session created WITHOUT enhanced data")
                end
            end
        end
    end
end

-- Parse combat log events with improved filtering
function CombatData:ParseCombatLog(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
                                   destGUID, destName, destFlags, destRaidFlags, ...)
    local playerGUID = UnitGUID("player")
    local playerName = UnitName("player")

    -- Only track events where YOU are the source
    if sourceGUID ~= playerGUID then
        return
    end

    -- Additional safety check with player name
    if sourceName and sourceName ~= playerName then
        return
    end

    -- Count relevant combat actions
    if subevent == "SPELL_DAMAGE" or subevent == "SWING_DAMAGE" or
        subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_DAMAGE" or
        subevent == "SPELL_PERIODIC_HEAL" then
        combatActionCount = combatActionCount + 1
    end

    -- Damage events with reasonable limits
    if subevent == "SPELL_DAMAGE" or subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" then
        local amount
        if subevent == "SWING_DAMAGE" then
            amount = select(1, ...)
        else
            amount = select(4, ...)
        end

        -- Sanity check: reject unreasonably large damage values
        if amount and amount > 0 and amount < 10000000 then -- Max 10M per hit
            combatData.damage = combatData.damage + amount

            if addon.DEBUG then
                print(string.format("Damage: %s (%s)", addon.CombatTracker:FormatNumber(amount), subevent))
            end
        elseif amount and amount >= 10000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large damage: %s (%s)", addon.CombatTracker:FormatNumber(amount), subevent))
            end
        end

        -- Periodic damage (DOTs) with limits
    elseif subevent == "SPELL_PERIODIC_DAMAGE" then
        local amount = select(4, ...)

        -- Sanity check for DOT damage
        if amount and amount > 0 and amount < 5000000 then -- Max 5M per DOT tick
            combatData.damage = combatData.damage + amount

            if addon.DEBUG then
                print(string.format("DOT Damage: %s", addon.CombatTracker:FormatNumber(amount)))
            end
        elseif amount and amount >= 5000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large DOT: %s", addon.CombatTracker:FormatNumber(amount)))
            end
        end

        -- Healing events with limits
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool, amount, overhealing, absorbed, critical = select(1, ...)

        -- Sanity check for healing
        if amount and amount > 0 and amount < 5000000 then -- Max 5M heal
            combatData.healing = combatData.healing + amount

            if addon.DEBUG then
                print(string.format("Heal: %s (%s%s)",
                    addon.CombatTracker:FormatNumber(amount),
                    spellName or "Unknown",
                    critical and " CRIT" or ""
                ))
            end
        elseif amount and amount >= 5000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large heal: %s (%s)",
                    addon.CombatTracker:FormatNumber(amount),
                    spellName or "Unknown"
                ))
            end
        end

        -- Track overhealing separately with limits
        if overhealing and overhealing > 0 and overhealing < 5000000 then
            combatData.overheal = combatData.overheal + overhealing
        end

        -- Absorb shield events - re-enabled for healing calculations
    elseif subevent == "SPELL_ABSORBED" then
        local absorbAmount = select(8, ...)
        if absorbAmount and absorbAmount > 0 and absorbAmount < 5000000 then
            combatData.absorb = combatData.absorb + absorbAmount
            combatData.healing = combatData.healing + absorbAmount -- Count absorbs as healing

            if addon.DEBUG then
                print(string.format("Absorb: %s", addon.CombatTracker:FormatNumber(absorbAmount)))
            end
        elseif absorbAmount and absorbAmount >= 5000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large absorb: %s", addon.CombatTracker:FormatNumber(absorbAmount)))
            end
        end
    end
end

-- Event handler
function CombatData:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self:StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:EndCombat()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Only process combat events if we're still in combat
        if combatData.inCombat then
            self:ParseCombatLog(CombatLogGetCurrentEventInfo())
        end
    end
end

-- =============================================================================
-- UPDATE & DISPLAY SYSTEM
-- =============================================================================

-- Update displays
function CombatData:UpdateDisplays()
    -- Track max DPS and HPS during combat
    if combatData.inCombat then
        local elapsed = GetTime() - combatData.startTime

        -- TIMING PROTECTION: Don't track peaks for the first 1.5 seconds of combat
        if elapsed >= 1.5 then
            local rollingDPS = addon.TimelineTracker:GetRollingDPS()
            local rollingHPS = addon.TimelineTracker:GetRollingHPS()

            -- Track peaks of rolling averages (more stable than overall DPS)
            if rollingDPS > combatData.maxDPS then
                combatData.maxDPS = rollingDPS
                if addon.DEBUG then
                    addon:DebugPrint(string.format("NEW ROLLING DPS PEAK: %.0f", rollingDPS))
                end
            end

            if rollingHPS > combatData.maxHPS then
                combatData.maxHPS = rollingHPS
                if addon.DEBUG then
                    addon:DebugPrint(string.format("NEW ROLLING HPS PEAK: %.0f", rollingHPS))
                end
            end
        else
            if addon.DEBUG then
                addon:DebugPrint(string.format("Peak tracking disabled: elapsed=%.2f < 1.5 seconds", elapsed))
            end
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

-- =============================================================================
-- RESET FUNCTIONS
-- =============================================================================

-- Reset display stats (for refresh button)
function CombatData:ResetDisplayStats()
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

        -- Clear timeline data
        if addon.TimelineTracker then
            addon.TimelineTracker:Reset()
        end
    end
end

-- Reset only DPS-related stats (for individual DPS meter reset)
function CombatData:ResetDPSStats()
    if not combatData.inCombat then
        -- Reset DPS-specific values
        combatData.damage = 0
        combatData.maxDPS = 0
        combatData.finalDamage = 0
        combatData.finalMaxDPS = 0
        combatData.finalDPS = 0

        -- Clear timeline data
        if addon.TimelineTracker then
            addon.TimelineTracker:Reset()
        end

        -- Reset start time if no combat is active
        combatData.startTime = nil
        combatData.endTime = nil

        print("DPS stats and peak values reset")
    else
        print("Cannot reset DPS stats during combat")
    end
end

-- Reset only HPS-related stats (for individual HPS meter reset)
function CombatData:ResetHPSStats()
    if not combatData.inCombat then
        -- Reset HPS-specific values
        combatData.healing = 0
        combatData.overheal = 0
        combatData.absorb = 0
        combatData.maxHPS = 0
        combatData.finalHealing = 0
        combatData.finalOverheal = 0
        combatData.finalAbsorb = 0
        combatData.finalMaxHPS = 0
        combatData.finalHPS = 0

        -- Clear timeline data
        if addon.TimelineTracker then
            addon.TimelineTracker:Reset()
        end

        -- Reset start time if no combat is active
        combatData.startTime = nil
        combatData.endTime = nil

        print("HPS stats and peak values reset")
    else
        print("Cannot reset HPS stats during combat")
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Initialize combat data module
function CombatData:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering combat
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving combat
    self.frame:SetScript("OnEvent", function(self, event, ...)
        CombatData:OnEvent(event, ...)
    end)

    -- Initialize unified calculator
    if addon.UnifiedCalculator then
        calculator = addon.UnifiedCalculator:New()
        calculator:SetCombatData(self)
    end
    
    -- Set timeline tracker when available
    if calculator and addon.TimelineTracker then
        calculator:SetTimelineTracker(addon.TimelineTracker)
    end

    -- Update timer (for displays and max tracking)
    self.updateTimer = C_Timer.NewTicker(0.1, function()
        CombatData:UpdateDisplays()
    end)

    if addon.DEBUG then
        print("CombatData module initialized with UnifiedCalculator")
    end
end

-- Get calculator instance for external access
function CombatData:GetCalculator()
    return calculator
end

-- Update calculator configuration
function CombatData:SetCalculationMethod(method)
    if calculator then
        return calculator:SetCalculationMethod(method)
    end
    return false
end

-- Get current calculation method
function CombatData:GetCalculationMethod()
    if calculator then
        return calculator:GetCalculationMethod()
    end
    return "unknown"
end

-- =============================================================================
-- DEBUG FUNCTIONS
-- =============================================================================

-- Debug peak tracking values
function CombatData:DebugPeakTracking()
    print("=== PEAK TRACKING DEBUG ===")
    print("Combat State:", self:IsInCombat() and "IN COMBAT" or "OUT OF COMBAT")
    print("Current DPS:", math.floor(self:GetDPS()))
    print("Current HPS:", math.floor(self:GetHPS()))
    if addon.TimelineTracker then
        print("Rolling DPS:", math.floor(addon.TimelineTracker:GetRollingDPS()))
        print("Rolling HPS:", math.floor(addon.TimelineTracker:GetRollingHPS()))
    end

    print("--- Stored Peak Values ---")
    print("combatData.maxDPS:", math.floor(combatData.maxDPS))
    print("combatData.maxHPS:", math.floor(combatData.maxHPS))
    print("combatData.finalMaxDPS:", math.floor(combatData.finalMaxDPS))
    print("combatData.finalMaxHPS:", math.floor(combatData.finalMaxHPS))

    print("--- What GetMaxDPS/HPS Return ---")
    print("GetMaxDPS():", math.floor(self:GetMaxDPS()))
    print("GetMaxHPS():", math.floor(self:GetMaxHPS()))

    print("--- Combat Totals ---")
    print("Total Damage:", addon.CombatTracker:FormatNumber(combatData.damage))
    print("Total Healing:", addon.CombatTracker:FormatNumber(combatData.healing))
    print("Combat Duration:", string.format("%.1f seconds", self:GetCombatTime()))

    if combatData.startTime then
        local elapsed = GetTime() - combatData.startTime
        if elapsed > 0 then
            print("Expected Average DPS:", math.floor(combatData.damage / elapsed))
            print("Expected Average HPS:", math.floor(combatData.healing / elapsed))
        end
    end
    print("========================")
end

-- =============================================================================
-- Enhanced data access methods
-- =============================================================================

-- Get enhanced combat data if available
function CombatData:GetEnhancedData()
    if addon.EnhancedCombatLogger then
        return addon.EnhancedCombatLogger:GetEnhancedSessionData()
    end
    return nil
end

-- Check if enhanced logging is active
function CombatData:IsEnhancedLoggingActive()
    return addon.EnhancedCombatLogger ~= nil
end
