-- CombatTracker.lua
-- Tracks DPS and HPS for the player with rolling averages and timeline data

local addonName, addon = ...

-- Combat tracker module
addon.CombatTracker = {}
local CombatTracker = addon.CombatTracker

-- Configuration for data collection
local SAMPLE_INTERVAL = 0.5       -- Sample every 0.5 seconds
local ROLLING_WINDOW_SIZE = 5     -- 5 seconds for rolling average
local MAX_TIMELINE_SAMPLES = 1200 -- Keep 10 minutes of history (1200 * 0.5s)

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

-- Rolling window data (circular buffer)
local rollingData = {
    samples = {},                                            -- Array of sample data
    currentIndex = 1,
    size = math.ceil(ROLLING_WINDOW_SIZE / SAMPLE_INTERVAL), -- Number of samples in rolling window
    initialized = false
}

-- Timeline data (full combat history)
local timelineData = {
    samples = {}, -- Array of historical samples
    maxSamples = MAX_TIMELINE_SAMPLES
}

-- Sample data structure
local function CreateSample(timestamp, deltaTime)
    local currentTime = timestamp or GetTime()
    local dt = deltaTime or SAMPLE_INTERVAL

    -- Calculate rates since last sample
    local damageDelta = combatData.damage - combatData.lastSampleDamage
    local healingDelta = combatData.healing - combatData.lastSampleHealing
    local overhealDelta = combatData.overheal - combatData.lastSampleOverheal
    local absorbDelta = combatData.absorb - combatData.lastSampleAbsorb

    local instantDPS = dt > 0 and (damageDelta / dt) or 0
    local instantHPS = dt > 0 and (healingDelta / dt) or 0
    local effectiveHealing = healingDelta - overhealDelta
    local instantEffectiveHPS = dt > 0 and (effectiveHealing / dt) or 0

    -- Calculate overheal percentage for this sample
    local overhealPercent = 0
    if healingDelta > 0 then
        overhealPercent = (overhealDelta / healingDelta) * 100
    end

    return {
        timestamp = currentTime,
        elapsed = currentTime - (combatData.startTime or currentTime),
        -- Cumulative totals
        totalDamage = combatData.damage,
        totalHealing = combatData.healing,
        totalOverheal = combatData.overheal,
        totalAbsorb = combatData.absorb,
        -- Instantaneous rates (since last sample)
        instantDPS = instantDPS,
        instantHPS = instantHPS,
        instantEffectiveHPS = instantEffectiveHPS,
        instantAbsorbRate = dt > 0 and (absorbDelta / dt) or 0,
        -- Percentages
        overhealPercent = overhealPercent,
        -- Overall averages (from combat start)
        averageDPS = CombatTracker:GetDPS(),
        averageHPS = CombatTracker:GetHPS(),
        -- Delta values
        damageDelta = damageDelta,
        healingDelta = healingDelta,
        overhealDelta = overhealDelta,
        absorbDelta = absorbDelta
    }
end

-- Add sample to rolling window (circular buffer)
local function AddToRollingWindow(sample)
    if not rollingData.initialized then
        -- Initialize rolling buffer
        for i = 1, rollingData.size do
            rollingData.samples[i] = nil
        end
        rollingData.initialized = true
    end

    rollingData.samples[rollingData.currentIndex] = sample
    rollingData.currentIndex = rollingData.currentIndex + 1
    if rollingData.currentIndex > rollingData.size then
        rollingData.currentIndex = 1
    end
end

-- Add sample to timeline data
local function AddToTimeline(sample)
    table.insert(timelineData.samples, sample)

    -- Remove old samples if we exceed max
    if #timelineData.samples > timelineData.maxSamples then
        table.remove(timelineData.samples, 1)
    end
end

-- Calculate rolling averages
local function CalculateRollingAverages()
    local validSamples = {}
    local currentTime = GetTime()
    local windowStart = currentTime - ROLLING_WINDOW_SIZE

    -- Collect valid samples from rolling window
    for i = 1, rollingData.size do
        local sample = rollingData.samples[i]
        if sample and sample.timestamp >= windowStart then
            table.insert(validSamples, sample)
        end
    end

    if #validSamples == 0 then
        return {
            dps = 0,
            hps = 0,
            effectiveHPS = 0,
            overhealPercent = 0,
            absorbRate = 0,
            sampleCount = 0
        }
    end

    -- Calculate averages
    local totalDPS = 0
    local totalHPS = 0
    local totalEffectiveHPS = 0
    local totalOverhealPercent = 0
    local totalAbsorbRate = 0

    for _, sample in ipairs(validSamples) do
        totalDPS = totalDPS + sample.instantDPS
        totalHPS = totalHPS + sample.instantHPS
        totalEffectiveHPS = totalEffectiveHPS + sample.instantEffectiveHPS
        totalOverhealPercent = totalOverhealPercent + sample.overhealPercent
        totalAbsorbRate = totalAbsorbRate + sample.instantAbsorbRate
    end

    local count = #validSamples
    return {
        dps = totalDPS / count,
        hps = totalHPS / count,
        effectiveHPS = totalEffectiveHPS / count,
        overhealPercent = totalOverhealPercent / count,
        absorbRate = totalAbsorbRate / count,
        sampleCount = count
    }
end

-- Sample combat data
local function SampleCombatData()
    if not combatData.inCombat then return end

    local currentTime = GetTime()
    local deltaTime = currentTime - combatData.lastSampleTime

    -- Create sample
    local sample = CreateSample(currentTime, deltaTime)

    -- Add to both rolling window and timeline
    AddToRollingWindow(sample)
    AddToTimeline(sample)

    -- Update tracking values
    combatData.lastSampleTime = currentTime
    combatData.lastSampleDamage = combatData.damage
    combatData.lastSampleHealing = combatData.healing
    combatData.lastSampleOverheal = combatData.overheal
    combatData.lastSampleAbsorb = combatData.absorb

    if addon.DEBUG then
        local rolling = CalculateRollingAverages()
        addon:DebugPrint(string.format("Sample: DPS=%.0f, HPS=%.0f (%.0f effective), OH=%.1f%%, Samples=%d",
            rolling.dps, rolling.hps, rolling.effectiveHPS, rolling.overhealPercent, rolling.sampleCount))

        -- Auto-output rolling and timeline data every 5 seconds (10 samples)
        local sampleCount = #timelineData.samples
        if sampleCount > 0 and sampleCount % 10 == 0 then
            -- Output rolling data
            print("=== Auto Rolling Report (5-sec) ===")
            print(string.format("DPS: %.1f | HPS: %.1f | Effective HPS: %.1f", rolling.dps, rolling.hps,
                rolling.effectiveHPS))
            print(string.format("Overheal: %.1f%% | Absorb Rate: %.1f | Samples: %d", rolling.overhealPercent,
                rolling.absorbRate, rolling.sampleCount))

            -- Output recent timeline samples (last 3)
            local timeline = timelineData.samples
            print("=== Auto Timeline Report (last 3 samples) ===")
            local startIdx = math.max(1, #timeline - 2)
            for i = startIdx, #timeline do
                local s = timeline[i]
                print(string.format("[%.1fs] DPS:%.0f HPS:%.0f OH:%.1f%% Abs:%.0f",
                    s.elapsed, s.instantDPS, s.instantHPS, s.overhealPercent, s.instantAbsorbRate))
            end
            print("--- End Auto Report ---")
        end
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

    -- Update timer (for displays and max tracking)
    self.updateTimer = C_Timer.NewTicker(0.1, function()
        CombatTracker:UpdateDisplays()
    end)

    -- Sample timer (for rolling averages and timeline)
    self.sampleTimer = C_Timer.NewTicker(SAMPLE_INTERVAL, function()
        SampleCombatData()
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

            -- Take one final sample
            SampleCombatData()
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

    -- DON'T RESET THESE - keep them for auto-scaling:
    -- combatData.finalDamage = 0
    -- combatData.finalHealing = 0
    -- combatData.finalOverheal = 0
    -- combatData.finalAbsorb = 0
    -- combatData.finalMaxDPS = 0
    -- combatData.finalMaxHPS = 0
    -- combatData.finalDPS = 0
    -- combatData.finalHPS = 0

    combatData.lastUpdate = GetTime()

    -- Reset sampling data
    combatData.lastSampleTime = combatData.startTime
    combatData.lastSampleDamage = 0
    combatData.lastSampleHealing = 0
    combatData.lastSampleOverheal = 0
    combatData.lastSampleAbsorb = 0

    -- Clear rolling window and timeline
    rollingData.samples = {}
    rollingData.currentIndex = 1
    rollingData.initialized = false
    timelineData.samples = {}

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
    print(string.format("Timeline Samples: %d", #timelineData.samples))
    print("--------------------")

    -- Keep displaying the final numbers until manual reset or new combat
    -- Removed automatic reset timer - numbers persist until refresh clicked or new combat starts
end

-- Parse combat log events with improved filtering
function CombatTracker:ParseCombatLog(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
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

-- Get rolling average DPS
function CombatTracker:GetRollingDPS()
    local rolling = CalculateRollingAverages()
    return rolling.dps
end

-- Get rolling average HPS
function CombatTracker:GetRollingHPS()
    local rolling = CalculateRollingAverages()
    return rolling.hps
end

-- Get rolling average effective HPS (excluding overheal)
function CombatTracker:GetRollingEffectiveHPS()
    local rolling = CalculateRollingAverages()
    return rolling.effectiveHPS
end

-- Get rolling overheal percentage
function CombatTracker:GetRollingOverhealPercent()
    local rolling = CalculateRollingAverages()
    return rolling.overhealPercent
end

-- Get rolling absorb rate
function CombatTracker:GetRollingAbsorbRate()
    local rolling = CalculateRollingAverages()
    return rolling.absorbRate
end

-- Get timeline data (for visualization)
function CombatTracker:GetTimelineData()
    return timelineData.samples
end

-- Get rolling data summary
function CombatTracker:GetRollingData()
    return CalculateRollingAverages()
end

-- Calculate DPS
function CombatTracker:GetDPS()
    -- Return final DPS if combat has ended and we have a final value
    if not combatData.inCombat and combatData.finalDPS > 0 then
        return combatData.finalDPS
    end

    -- Otherwise calculate current DPS if in combat
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
    -- Return final HPS if combat has ended and we have a final value
    if not combatData.inCombat and combatData.finalHPS > 0 then
        return combatData.finalHPS
    end

    -- Otherwise calculate current HPS if in combat
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

        -- Clear rolling window and timeline
        rollingData.samples = {}
        rollingData.currentIndex = 1
        rollingData.initialized = false
        timelineData.samples = {}
    end
end

-- Reset only DPS-related stats (for individual DPS meter reset)
function CombatTracker:ResetDPSStats()
    if not combatData.inCombat then
        -- Reset DPS-specific values
        combatData.damage = 0
        combatData.maxDPS = 0
        combatData.finalDamage = 0
        combatData.finalMaxDPS = 0
        combatData.finalDPS = 0

        -- Reset timeline and rolling data (affects both DPS and HPS calculations)
        rollingData.samples = {}
        rollingData.currentIndex = 1
        rollingData.initialized = false
        timelineData.samples = {}

        -- Reset start time if no combat is active
        combatData.startTime = nil
        combatData.endTime = nil

        print("DPS stats and peak values reset")
    else
        print("Cannot reset DPS stats during combat")
    end
end

-- Reset only HPS-related stats (for individual HPS meter reset)
function CombatTracker:ResetHPSStats()
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

        -- Reset timeline and rolling data (affects both DPS and HPS calculations)
        rollingData.samples = {}
        rollingData.currentIndex = 1
        rollingData.initialized = false
        timelineData.samples = {}

        -- Reset start time if no combat is active
        combatData.startTime = nil
        combatData.endTime = nil

        print("HPS stats and peak values reset")
    else
        print("Cannot reset HPS stats during combat")
    end
end

-- Check if in combat
function CombatTracker:IsInCombat()
    return combatData.inCombat
end

-- Simple UpdateDisplays fix - just replace this function in your CombatTracker.lua

function CombatTracker:UpdateDisplays()
    -- Track max DPS and HPS during combat
    if combatData.inCombat then
        local elapsed = GetTime() - combatData.startTime

        -- TIMING PROTECTION: Don't track peaks for the first 1.5 seconds of combat
        if elapsed >= 1.5 then
            local rollingDPS = self:GetRollingDPS()
            local rollingHPS = self:GetRollingHPS()

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

-- === DEBUG FUNCTIONS ===

-- Debug peak tracking values
function CombatTracker:DebugPeakTracking()
    print("=== PEAK TRACKING DEBUG ===")
    print("Combat State:", self:IsInCombat() and "IN COMBAT" or "OUT OF COMBAT")
    print("Current DPS:", math.floor(self:GetDPS()))
    print("Current HPS:", math.floor(self:GetHPS()))
    print("Rolling DPS:", math.floor(self:GetRollingDPS()))
    print("Rolling HPS:", math.floor(self:GetRollingHPS()))

    print("--- Stored Peak Values ---")
    print("combatData.maxDPS:", math.floor(combatData.maxDPS))
    print("combatData.maxHPS:", math.floor(combatData.maxHPS))
    print("combatData.finalMaxDPS:", math.floor(combatData.finalMaxDPS))
    print("combatData.finalMaxHPS:", math.floor(combatData.finalMaxHPS))

    print("--- What GetMaxDPS/HPS Return ---")
    print("GetMaxDPS():", math.floor(self:GetMaxDPS()))
    print("GetMaxHPS():", math.floor(self:GetMaxHPS()))

    print("--- Combat Totals ---")
    print("Total Damage:", self:FormatNumber(combatData.damage))
    print("Total Healing:", self:FormatNumber(combatData.healing))
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

-- Debug DPS calculation in detail
function CombatTracker:DebugDPSCalculation()
    print("=== DPS CALCULATION DEBUG ===")

    if not combatData.inCombat and combatData.finalDPS > 0 then
        print("Using FINAL DPS:", combatData.finalDPS)
        print("Final damage:", combatData.finalDamage)
        return
    end

    if not combatData.inCombat or not combatData.startTime then
        print("Not in combat or no start time")
        return
    end

    local elapsed = GetTime() - combatData.startTime
    local calculatedDPS = elapsed > 0 and (combatData.damage / elapsed) or 0

    print("Combat Start Time:", combatData.startTime)
    print("Current Time:", GetTime())
    print("Elapsed Time:", elapsed)
    print("Total Damage:", combatData.damage)
    print("Calculated DPS:", calculatedDPS)
    print("Stored Max DPS:", combatData.maxDPS)

    -- Check if elapsed time is too small
    if elapsed < 0.1 then
        print("WARNING: Very short elapsed time, DPS calculation may be inflated!")
    end

    -- Check for timing issues
    if elapsed < 1.0 and combatData.damage > 100000 then
        print("WARNING: High damage in short time - potential timing issue!")
        print("This could cause artificially high peak DPS values")
    end

    print("========================")
end

-- Compare rolling vs overall calculations
function CombatTracker:CompareRollingVsOverall()
    print("=== ROLLING VS OVERALL COMPARISON ===")
    print("Overall DPS (from start):", math.floor(self:GetDPS()))
    print("Rolling DPS (5-sec avg):", math.floor(self:GetRollingDPS()))
    print("Overall HPS (from start):", math.floor(self:GetHPS()))
    print("Rolling HPS (5-sec avg):", math.floor(self:GetRollingHPS()))

    local rolling = CalculateRollingAverages()
    print("Rolling sample count:", rolling.sampleCount)
    print("Rolling window size:", ROLLING_WINDOW_SIZE, "seconds")
    print("Sample interval:", SAMPLE_INTERVAL, "seconds")

    -- Show timeline sample count
    print("Timeline samples:", #timelineData.samples)
    print("====================================")
end

-- Check update timing and timers
function CombatTracker:CheckUpdateTiming()
    print("=== UPDATE TIMING CHECK ===")
    print("Update timer interval: 0.1 seconds")
    print("Sample timer interval:", SAMPLE_INTERVAL, "seconds")
    print("Rolling window size:", ROLLING_WINDOW_SIZE, "seconds")
    print("Max timeline samples:", MAX_TIMELINE_SAMPLES)

    if self.updateTimer then
        print("Update timer exists and running")
    else
        print("WARNING: Update timer not found!")
    end

    if self.sampleTimer then
        print("Sample timer exists and running")
    else
        print("WARNING: Sample timer not found!")
    end

    -- Check combat data timestamps
    if combatData.startTime then
        print("Combat start time:", combatData.startTime)
        print("Last sample time:", combatData.lastSampleTime)
        print("Current time:", GetTime())
    else
        print("No combat start time recorded")
    end
    print("==========================")
end

-- Debug what happens during peak detection
function CombatTracker:DebugPeakDetection()
    print("=== PEAK DETECTION DEBUG ===")

    if not combatData.inCombat then
        print("Not in combat - no peak detection active")
        return
    end

    local currentDPS = self:GetDPS()
    local currentHPS = self:GetHPS()
    local rollingDPS = self:GetRollingDPS()
    local rollingHPS = self:GetRollingHPS()
    local elapsed = GetTime() - combatData.startTime

    print("Time since combat start:", string.format("%.2f seconds", elapsed))
    print("Total damage so far:", combatData.damage)
    print("Total healing so far:", combatData.healing)
    print("Current overall DPS:", math.floor(currentDPS))
    print("Current overall HPS:", math.floor(currentHPS))
    print("Current rolling DPS:", math.floor(rollingDPS))
    print("Current rolling HPS:", math.floor(rollingHPS))
    print("Current peak DPS:", math.floor(combatData.maxDPS))
    print("Current peak HPS:", math.floor(combatData.maxHPS))

    -- Predict if peaks will update
    if currentDPS > combatData.maxDPS then
        print(">>> DPS PEAK WILL UPDATE on next UpdateDisplays() call")
    else
        print("--- DPS peak will not update")
    end

    if currentHPS > combatData.maxHPS then
        print(">>> HPS PEAK WILL UPDATE on next UpdateDisplays() call")
    else
        print("--- HPS peak will not update")
    end

    print("============================")
end

-- Test peak tracking with artificial values
function CombatTracker:TestPeakTracking()
    print("=== TESTING PEAK TRACKING ===")

    -- Save original values
    local origMaxDPS = combatData.maxDPS
    local origMaxHPS = combatData.maxHPS
    local origFinalMaxDPS = combatData.finalMaxDPS
    local origFinalMaxHPS = combatData.finalMaxHPS

    -- Test with artificial peaks
    print("Setting artificial peak values...")
    combatData.maxDPS = 500000 -- 500K
    combatData.maxHPS = 300000 -- 300K

    -- Force display update
    self:UpdateDisplays()
    print("Updated displays with 500K DPS peak, 300K HPS peak")

    -- Test with higher values
    combatData.maxDPS = 1000000 -- 1M
    combatData.maxHPS = 600000  -- 600K

    -- Force display update
    self:UpdateDisplays()
    print("Updated displays with 1M DPS peak, 600K HPS peak")

    -- Restore original values
    combatData.maxDPS = origMaxDPS
    combatData.maxHPS = origMaxHPS
    combatData.finalMaxDPS = origFinalMaxDPS
    combatData.finalMaxHPS = origFinalMaxHPS

    self:UpdateDisplays()
    print("Restored original peak values")
    print("===========================")
end

-- Get the final peak values from the last completed combat
function CombatTracker:GetLastCombatMaxDPS()
    return combatData.finalMaxDPS or 0
end

function CombatTracker:GetLastCombatMaxHPS()
    return combatData.finalMaxHPS or 0
end
