-- TimelineTracker.lua
-- Timeline data sampling and rolling averages

local addonName, addon = ...

-- Timeline tracker module
addon.TimelineTracker = {}
local TimelineTracker = addon.TimelineTracker

-- =============================================================================
-- CONFIGURATION & CONSTANTS
-- =============================================================================

local SAMPLE_INTERVAL = 0.5       -- Sample every 0.5 seconds
local ROLLING_WINDOW_SIZE = 5     -- 5 seconds for rolling average
local MAX_TIMELINE_SAMPLES = 1200 -- Keep 10 minutes of history (1200 * 0.5s)

-- =============================================================================
-- DATA STRUCTURES
-- =============================================================================

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

-- =============================================================================
-- SAMPLING SYSTEM
-- =============================================================================

-- Sample data structure
local function CreateSample(timestamp, deltaTime)
    local currentTime = timestamp or GetTime()
    local dt = deltaTime or SAMPLE_INTERVAL

    local combatData = addon.CombatData:GetRawCombatData()

    -- Calculate rates since last sample
    local damageDelta = combatData.damage - combatData.lastSampleDamage
    local healingDelta = combatData.healing - combatData.lastSampleHealing
    local overhealDelta = combatData.overheal - combatData.lastSampleOverheal
    local absorbDelta = combatData.absorb - combatData.lastSampleAbsorb

    local instantDPS = dt > 0 and (damageDelta / dt) or 0
    local instantHPS = dt > 0 and (healingDelta / dt) or 0
    local effectiveHealing = healingDelta - overhealDelta
    local instantEffectiveHPS = dt > 0 and (effectiveHealing / dt) or 0

    -- Sanity checking: Cap instantaneous values to reasonable maximums
    local maxReasonableDPS = 10000000 -- 10M DPS cap
    local maxReasonableHPS = 5000000  -- 5M HPS cap

    instantDPS = math.min(instantDPS, maxReasonableDPS)
    instantHPS = math.min(instantHPS, maxReasonableHPS)

    -- Also ignore samples with tiny time deltas that cause spikes
    if dt < 0.1 then
        instantDPS = 0
        instantHPS = 0
    end

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
        averageDPS = addon.CombatData:GetDPS(),
        averageHPS = addon.CombatData:GetHPS(),
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
    if not addon.CombatData:IsInCombat() then return end

    local combatData = addon.CombatData:GetRawCombatData()
    local currentTime = GetTime()
    local deltaTime = currentTime - combatData.lastSampleTime

    -- Create sample
    local sample = CreateSample(currentTime, deltaTime)

    -- Add to both rolling window and timeline
    AddToRollingWindow(sample)
    AddToTimeline(sample)

    -- Update tracking values in combat data
    combatData.lastSampleTime = currentTime
    combatData.lastSampleDamage = combatData.damage
    combatData.lastSampleHealing = combatData.healing
    combatData.lastSampleOverheal = combatData.overheal
    combatData.lastSampleAbsorb = combatData.absorb

    if addon.DEBUG then
        local rolling = CalculateRollingAverages()
        addon:DebugPrint(string.format("Sample: DPS=%.0f, HPS=%.0f (%.0f effective), OH=%.1f%%, Samples=%d",
            rolling.dps, rolling.hps, rolling.effectiveHPS, rolling.overhealPercent, rolling.sampleCount))
    end
end

-- =============================================================================
-- ROLLING AVERAGE API
-- =============================================================================

function TimelineTracker:GetRollingDPS()
    local rolling = CalculateRollingAverages()
    return rolling.dps
end

function TimelineTracker:GetRollingHPS()
    local rolling = CalculateRollingAverages()
    return rolling.hps
end

function TimelineTracker:GetRollingEffectiveHPS()
    local rolling = CalculateRollingAverages()
    return rolling.effectiveHPS
end

function TimelineTracker:GetRollingOverhealPercent()
    local rolling = CalculateRollingAverages()
    return rolling.overhealPercent
end

function TimelineTracker:GetRollingAbsorbRate()
    local rolling = CalculateRollingAverages()
    return rolling.absorbRate
end

function TimelineTracker:GetTimelineData()
    return timelineData.samples
end

function TimelineTracker:GetRollingData()
    return CalculateRollingAverages()
end

-- =============================================================================
-- COMBAT EVENT HANDLERS
-- =============================================================================

-- Start combat tracking
function TimelineTracker:StartCombat()
    -- Clear rolling window and timeline
    rollingData.samples = {}
    rollingData.currentIndex = 1
    rollingData.initialized = false
    timelineData.samples = {}

    if addon.DEBUG then
        print("TimelineTracker: Combat started, data cleared")
    end
end

-- End combat tracking
function TimelineTracker:EndCombat()
    -- Take one final sample
    SampleCombatData()

    if addon.DEBUG then
        print(string.format("TimelineTracker: Combat ended, %d timeline samples recorded", #timelineData.samples))
    end
end

-- Reset data
function TimelineTracker:Reset()
    rollingData.samples = {}
    rollingData.currentIndex = 1
    rollingData.initialized = false
    timelineData.samples = {}

    if addon.DEBUG then
        print("TimelineTracker: Data reset")
    end
end

-- =============================================================================
-- TIMELINE DATA FOR SESSIONS
-- =============================================================================

-- Get timeline data for session storage
function TimelineTracker:GetTimelineForSession(duration)
    local sessionTimeline = {}

    -- Dynamic: 2 points per second, min 120 points (1 min), max 1200 points (10 min)
    local maxTimelinePoints = math.min(1200, math.max(120, math.floor(duration * 2)))
    local step = math.max(1, math.floor(#timelineData.samples / maxTimelinePoints))

    for i = 1, #timelineData.samples, step do
        local sample = timelineData.samples[i]
        if sample then
            table.insert(sessionTimeline, {
                elapsed = sample.elapsed,
                instantDPS = sample.averageDPS or 0, -- Use average instead of instant
                instantHPS = sample.averageHPS or 0, -- Use average instead of instant
                averageDPS = sample.averageDPS or 0,
                averageHPS = sample.averageHPS or 0,
                totalDamage = sample.totalDamage,
                totalHealing = sample.totalHealing,
                overhealPercent = sample.overhealPercent
            })
        end
    end

    return sessionTimeline
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Initialize timeline tracker
function TimelineTracker:Initialize()
    -- Sample timer (for rolling averages and timeline)
    self.sampleTimer = C_Timer.NewTicker(SAMPLE_INTERVAL, function()
        SampleCombatData()
    end)

    if addon.DEBUG then
        print("TimelineTracker module initialized")
    end
end
