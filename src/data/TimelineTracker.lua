-- TimelineTracker.lua
-- Timeline data sampling and rolling averages with enhanced combat integration

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
local function CreateSample(deltaTime)
    local dt = deltaTime or SAMPLE_INTERVAL

    -- UNIFIED TIMESTAMP: Use only MyTimestampManager for all time calculations
    if not addon.MyTimestampManager or not addon.MyTimestampManager:IsActive() then
        return nil  -- Cannot create samples without active timestamp manager
    end

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

    -- UNIFIED TIMESTAMP: Get elapsed time from MyTimestampManager only
    local elapsed = addon.MyTimestampManager:GetCurrentRelativeTime()

    return {
        -- REMOVED: No more storing absolute timestamps, only relative time
        elapsed = elapsed,
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
    
    -- UNIFIED TIMESTAMP: Use MyTimestampManager for rolling window calculation
    if not addon.MyTimestampManager or not addon.MyTimestampManager:IsActive() then
        return {
            dps = 0, hps = 0, effectiveHPS = 0, overhealPercent = 0, absorbRate = 0, sampleCount = 0
        }
    end
    
    local currentRelativeTime = addon.MyTimestampManager:GetCurrentRelativeTime()
    local windowStart = currentRelativeTime - ROLLING_WINDOW_SIZE

    -- Collect valid samples from rolling window (using relative time)
    for i = 1, rollingData.size do
        local sample = rollingData.samples[i]
        if sample and sample.elapsed >= windowStart then
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
    -- Only sample when in combat and MyTimestampManager is active
    if not addon.CombatData:IsInCombat() then return end
    if not addon.MyTimestampManager or not addon.MyTimestampManager:IsActive() then return end

    local combatData = addon.CombatData:GetRawCombatData()
    
    -- UNIFIED TIMESTAMP: Calculate delta time using MyTimestampManager
    local currentRelativeTime = addon.MyTimestampManager:GetCurrentRelativeTime()
    local deltaTime = currentRelativeTime - (combatData.lastSampleRelativeTime or 0)
    
    -- Ensure reasonable delta time
    if deltaTime < 0.1 or deltaTime > 2.0 then
        deltaTime = SAMPLE_INTERVAL
    end

    -- Create sample
    local sample = CreateSample(deltaTime)
    
    if sample then
        -- Add to both rolling window and timeline
        AddToRollingWindow(sample)
        AddToTimeline(sample)

        -- Update tracking values in combat data
        combatData.lastSampleRelativeTime = currentRelativeTime
        combatData.lastSampleDamage = combatData.damage
        combatData.lastSampleHealing = combatData.healing
        combatData.lastSampleOverheal = combatData.overheal
        combatData.lastSampleAbsorb = combatData.absorb
    end

    if addon.VERBOSE_DEBUG then
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
        addon:DebugPrint("TimelineTracker: Combat started, data cleared")
    end
end

-- End combat tracking
function TimelineTracker:EndCombat()
    -- Take one final sample
    SampleCombatData()

    if addon.DEBUG then
        addon:DebugPrint(string.format("TimelineTracker: Combat ended, %d timeline samples recorded", #timelineData.samples))
    end
end

-- Reset data
function TimelineTracker:Reset()
    rollingData.samples = {}
    rollingData.currentIndex = 1
    rollingData.initialized = false
    timelineData.samples = {}

    if addon.DEBUG then
        addon:DebugPrint("TimelineTracker: Data reset")
    end
end

-- =============================================================================
-- ENHANCED TIMELINE DATA FOR SESSIONS
-- =============================================================================

-- Get timeline data for session storage with enhanced data integration
function TimelineTracker:GetTimelineForSession(duration, enhancedData)
    local sessionTimeline = {}

    -- REDUCED for memory management: 1 point per second, min 60 points (1 min), max 300 points (5 min)
    -- This reduces memory usage by ~75% while maintaining good chart resolution
    local maxTimelinePoints = math.min(300, math.max(60, math.floor(duration * 1)))
    local step = math.max(1, math.floor(#timelineData.samples / maxTimelinePoints))

    for i = 1, #timelineData.samples, step do
        local sample = timelineData.samples[i]
        if sample then
            local timelinePoint = {
                elapsed = sample.elapsed,
                instantDPS = sample.averageDPS or 0, -- Use average instead of instant for stability
                instantHPS = sample.averageHPS or 0, -- Use average instead of instant for stability
                averageDPS = sample.averageDPS or 0,
                averageHPS = sample.averageHPS or 0,
                totalDamage = sample.totalDamage,
                totalHealing = sample.totalHealing,
                overhealPercent = sample.overhealPercent
            }

            -- Enhanced data integration - add damage taken data if available
            if enhancedData and enhancedData.damageTaken then
                local damageTakenAtTime = 0
                local damageTakenCount = 0

                -- Find damage events near this timeline point (within 0.5 seconds)
                for _, dmg in ipairs(enhancedData.damageTaken) do
                    if math.abs(dmg.elapsed - sample.elapsed) < 0.5 then
                        damageTakenAtTime = damageTakenAtTime + dmg.amount
                        damageTakenCount = damageTakenCount + 1
                    end
                end

                timelinePoint.damageTaken = damageTakenAtTime
                timelinePoint.damageTakenEvents = damageTakenCount
            end

            -- Add group damage data if available
            if enhancedData and enhancedData.groupDamage then
                local groupDamageAtTime = 0

                for _, dmg in ipairs(enhancedData.groupDamage) do
                    if math.abs(dmg.elapsed - sample.elapsed) < 0.5 then
                        groupDamageAtTime = groupDamageAtTime + dmg.amount
                    end
                end

                timelinePoint.groupDamageTaken = groupDamageAtTime
            end

            -- Add enhanced healing events data if available
            if enhancedData and enhancedData.healingEvents then
                local healingAtTime = 0

                for _, heal in ipairs(enhancedData.healingEvents) do
                    if math.abs(heal.elapsed - sample.elapsed) < 0.5 then
                        healingAtTime = healingAtTime + heal.amount
                    end
                end

                timelinePoint.enhancedHealing = healingAtTime
            end

            table.insert(sessionTimeline, timelinePoint)
        end
    end

    -- Debug information for enhanced data integration
    if addon.DEBUG and enhancedData then
        local enhancedPoints = 0
        for _, point in ipairs(sessionTimeline) do
            if point.damageTaken or point.groupDamageTaken or point.enhancedHealing then
                enhancedPoints = enhancedPoints + 1
            end
        end
        print(string.format("Timeline enhanced: %d/%d points have enhanced data",
            enhancedPoints, #sessionTimeline))
    end

    return sessionTimeline
end

-- =============================================================================
-- ENHANCED DATA ACCESS METHODS
-- =============================================================================

-- Get timeline data with enhanced filtering
function TimelineTracker:GetEnhancedTimelineData(filterType)
    local filteredData = {}

    for _, sample in ipairs(timelineData.samples) do
        local includePoint = true

        if filterType == "high_activity" then
            -- Only include points with significant activity
            includePoint = (sample.instantDPS > 1000 or sample.instantHPS > 500)
        elseif filterType == "damage_taken" then
            -- Only include points where damage was taken (requires enhanced data)
            includePoint = sample.damageTaken and sample.damageTaken > 0
        elseif filterType == "healing_intensive" then
            -- Only include points with high healing activity
            includePoint = sample.instantHPS > sample.averageHPS * 1.5
        elseif filterType == "performance_peaks" then
            -- Only include points with above-average performance
            includePoint = (sample.instantDPS > sample.averageDPS * 1.2 or sample.instantHPS > sample.averageHPS * 1.2)
        elseif filterType == "combat_events" then
            -- Only include points with significant combat activity
            includePoint = (sample.damageDelta > 0 or sample.healingDelta > 0)
        end

        if includePoint then
            table.insert(filteredData, sample)
        end
    end

    return filteredData
end

-- Get timeline statistics
function TimelineTracker:GetTimelineStats()
    if #timelineData.samples == 0 then
        return {
            totalSamples = 0,
            duration = 0,
            avgDPS = 0,
            avgHPS = 0,
            peakDPS = 0,
            peakHPS = 0,
            enhancedDataPoints = 0,
            samplingRate = 0
        }
    end

    local stats = {
        totalSamples = #timelineData.samples,
        duration = 0,
        avgDPS = 0,
        avgHPS = 0,
        peakDPS = 0,
        peakHPS = 0,
        enhancedDataPoints = 0,
        samplingRate = 0
    }

    local totalDPS = 0
    local totalHPS = 0

    for _, sample in ipairs(timelineData.samples) do
        totalDPS = totalDPS + (sample.instantDPS or sample.averageDPS or 0)
        totalHPS = totalHPS + (sample.instantHPS or sample.averageHPS or 0)

        stats.peakDPS = math.max(stats.peakDPS, sample.instantDPS or sample.averageDPS or 0)
        stats.peakHPS = math.max(stats.peakHPS, sample.instantHPS or sample.averageHPS or 0)

        -- Count enhanced data points
        if sample.damageTaken or sample.groupDamageTaken or sample.enhancedHealing then
            stats.enhancedDataPoints = stats.enhancedDataPoints + 1
        end
    end

    stats.avgDPS = totalDPS / #timelineData.samples
    stats.avgHPS = totalHPS / #timelineData.samples

    -- Calculate duration and sampling rate
    if #timelineData.samples > 1 then
        local firstSample = timelineData.samples[1]
        local lastSample = timelineData.samples[#timelineData.samples]
        stats.duration = lastSample.elapsed - firstSample.elapsed

        if stats.duration > 0 then
            stats.samplingRate = #timelineData.samples / stats.duration
        end
    end

    return stats
end

-- Get timeline data for specific time range
function TimelineTracker:GetTimelineRange(startTime, endTime)
    local rangeData = {}

    for _, sample in ipairs(timelineData.samples) do
        if sample.elapsed >= startTime and sample.elapsed <= endTime then
            table.insert(rangeData, sample)
        end
    end

    return rangeData
end

-- Find timeline points near specific events
function TimelineTracker:FindTimelinePointsNearEvents(events, tolerance)
    tolerance = tolerance or 1.0 -- Default 1 second tolerance
    local matchedPoints = {}

    for _, event in ipairs(events) do
        for _, sample in ipairs(timelineData.samples) do
            if math.abs(sample.elapsed - event.elapsed) <= tolerance then
                table.insert(matchedPoints, {
                    timelinePoint = sample,
                    event = event,
                    timeDelta = sample.elapsed - event.elapsed
                })
            end
        end
    end

    return matchedPoints
end

-- Clear enhanced timeline data
function TimelineTracker:ClearEnhancedData()
    for _, sample in ipairs(timelineData.samples) do
        sample.damageTaken = nil
        sample.damageTakenEvents = nil
        sample.groupDamageTaken = nil
        sample.enhancedHealing = nil
    end

    if addon.DEBUG then
        print("Timeline enhanced data cleared")
    end
end

-- Get performance metrics for timeline
function TimelineTracker:GetPerformanceMetrics()
    if #timelineData.samples == 0 then
        return {
            consistency = 0,
            peakDuration = 0,
            activityRatio = 0,
            efficiencyRatio = 0
        }
    end

    local metrics = {
        consistency = 0,
        peakDuration = 0,
        activityRatio = 0,
        efficiencyRatio = 0
    }

    -- Calculate DPS consistency (lower standard deviation = more consistent)
    local dpsSamples = {}
    local activeSamples = 0
    local totalEffectiveHealing = 0
    local totalOverhealing = 0

    for _, sample in ipairs(timelineData.samples) do
        if sample.instantDPS > 0 then
            table.insert(dpsSamples, sample.instantDPS)
            activeSamples = activeSamples + 1
        end

        totalEffectiveHealing = totalEffectiveHealing + (sample.instantEffectiveHPS or 0)
        totalOverhealing = totalOverhealing + (sample.instantHPS - (sample.instantEffectiveHPS or 0))
    end

    -- Calculate consistency (coefficient of variation)
    if #dpsSamples > 1 then
        local mean = 0
        for _, dps in ipairs(dpsSamples) do
            mean = mean + dps
        end
        mean = mean / #dpsSamples

        local variance = 0
        for _, dps in ipairs(dpsSamples) do
            variance = variance + (dps - mean) ^ 2
        end
        variance = variance / (#dpsSamples - 1)

        local stdDev = math.sqrt(variance)
        metrics.consistency = mean > 0 and (1 - (stdDev / mean)) or 0
        metrics.consistency = math.max(0, math.min(1, metrics.consistency)) -- Clamp to 0-1
    end

    -- Calculate activity ratio
    metrics.activityRatio = #timelineData.samples > 0 and (activeSamples / #timelineData.samples) or 0

    -- Calculate healing efficiency ratio
    local totalHealing = totalEffectiveHealing + totalOverhealing
    metrics.efficiencyRatio = totalHealing > 0 and (totalEffectiveHealing / totalHealing) or 1

    -- Calculate peak duration (how long performance stayed above average)
    local stats = self:GetTimelineStats()
    local peakSamples = 0

    for _, sample in ipairs(timelineData.samples) do
        local dps = sample.instantDPS or sample.averageDPS or 0
        if dps > stats.avgDPS * 1.2 then -- 20% above average
            peakSamples = peakSamples + 1
        end
    end

    metrics.peakDuration = #timelineData.samples > 0 and (peakSamples / #timelineData.samples) or 0

    return metrics
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
        print("TimelineTracker module initialized with enhanced data integration")
    end
end
