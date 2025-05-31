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
            print(string.format("Combat ending: elapsed=%.1f, damage=%d, healing=%d", elapsed, combatData.damage,
                combatData.healing))

            if elapsed > 0 then
                combatData.finalDPS = combatData.damage / elapsed
                combatData.finalHPS = combatData.healing / elapsed
                print(string.format("Calculated finalDPS=%.1f, finalHPS=%.1f", combatData.finalDPS, combatData.finalHPS))
            else
                combatData.finalDPS = 0
                combatData.finalHPS = 0
                print("Elapsed time was 0, setting final values to 0")
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
    combatData.finalDamage = 0
    combatData.finalHealing = 0
    combatData.finalOverheal = 0
    combatData.finalAbsorb = 0
    combatData.finalMaxDPS = 0
    combatData.finalMaxHPS = 0
    combatData.finalDPS = 0
    combatData.finalHPS = 0
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
