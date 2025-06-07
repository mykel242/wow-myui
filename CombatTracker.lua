-- CombatTracker.lua
-- Tracks DPS and HPS for the player with rolling averages, timeline data, and session history

local addonName, addon = ...

-- Combat tracker module
addon.CombatTracker = {}
local CombatTracker = addon.CombatTracker

-- Track current spec for change detection
local currentSpec = nil

-- =============================================================================
-- CONFIGURATION & CONSTANTS
-- =============================================================================

local SAMPLE_INTERVAL = 0.5       -- Sample every 0.5 seconds
local ROLLING_WINDOW_SIZE = 5     -- 5 seconds for rolling average
local MAX_TIMELINE_SAMPLES = 1200 -- Keep 10 minutes of history (1200 * 0.5s)
local SESSION_HISTORY_LIMIT = 50  -- Maximum sessions to store

-- =============================================================================
-- DATA STRUCTURES
-- =============================================================================

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

-- Session history
local sessionHistory = {} -- Will be per-character

-- Combat action counter
local combatActionCount = 0

-- Content detection system
local contentDetection = {
    manualOverride = nil, -- "scaled", "normal", nil
    overrideExpiry = 0,
    baselineStats = { avgDPS = 0, avgHPS = 0, sampleCount = 0 }
}

-- Quality scoring thresholds
local qualityThresholds = {
    minDuration = 15,  -- seconds (was 10, now 15 for more meaningful fights)
    minDamage = 25000, -- total damage (was 50K, now 25K - more realistic)
    minHealing = 5000, -- total healing (was 25K, now 5K - DPS do less healing)
    minDPS = 2000,     -- average DPS (was 5K, now 2K - much more realistic)
    minHPS = 500,      -- average HPS (was 2.5K, now 500 - DPS/tanks do minimal healing)
    minActions = 8,    -- combat log events counted (was 10, now 8)
}

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

-- Get current character+spec key for data segmentation
local function GetCharacterSpecKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    local specIndex = GetSpecialization()
    local specName = "Unknown"

    if specIndex then
        local _, specName_temp = GetSpecializationInfo(specIndex)
        if specName_temp then
            specName = specName_temp
        end
    end

    return string.format("%s-%s-%s", name, realm, specName)
end

-- Get current character key (legacy - for backwards compatibility)
local function GetCharacterKey()
    return UnitName("player") .. "-" .. GetRealmName()
end

-- Generate unique session ID
local function GenerateSessionId()
    return string.format("%04d", math.random(1000, 9999))
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

-- =============================================================================
-- CONTENT DETECTION SYSTEM
-- =============================================================================

-- Enhanced content detection with better session analysis
function CombatTracker:DetectContentType(sessionData)
    -- Check manual override first
    if contentDetection.manualOverride and GetTime() < contentDetection.overrideExpiry then
        if addon.DEBUG then
            print(string.format("Using manual content override: %s", contentDetection.manualOverride))
        end
        return contentDetection.manualOverride
    end

    -- Get baseline for comparison (use more sessions for stability)
    local normalBaseline = self:GetContentBaseline("normal", 20)

    if normalBaseline.sampleCount >= 3 then
        local dpsRatio = normalBaseline.avgDPS > 0 and (sessionData.avgDPS / normalBaseline.avgDPS) or 1
        local hpsRatio = normalBaseline.avgHPS > 0 and (sessionData.avgHPS / normalBaseline.avgHPS) or 1

        -- More nuanced detection thresholds
        local scaledThreshold = 0.6  -- Below 60% of normal suggests scaling
        local boostedThreshold = 2.5 -- Above 250% suggests boosted/scaled content

        -- Check if either DPS or HPS indicates scaling
        if dpsRatio < scaledThreshold or dpsRatio > boostedThreshold or
            hpsRatio < scaledThreshold or hpsRatio > boostedThreshold then
            if addon.DEBUG then
                print(string.format(
                    "Detected scaled content: DPS ratio %.2f, HPS ratio %.2f (baseline: %.0f DPS, %.0f HPS)",
                    dpsRatio, hpsRatio, normalBaseline.avgDPS, normalBaseline.avgHPS))
            end
            return "scaled"
        end
    end

    if addon.DEBUG then
        print(string.format("Detected normal content (baseline: %d samples)", normalBaseline.sampleCount))
    end
    return "normal"
end

-- Calculate baseline stats from recent normal content (legacy method for compatibility)
function CombatTracker:GetNormalContentBaseline()
    return self:GetContentBaseline("normal", 10)
end

-- Set manual content type override
function CombatTracker:SetContentOverride(contentType, durationHours)
    durationHours = durationHours or 2 -- Default 2 hours

    if contentType == "auto" then
        contentDetection.manualOverride = nil
        contentDetection.overrideExpiry = 0
        print("Content detection set to automatic")
    else
        contentDetection.manualOverride = contentType
        contentDetection.overrideExpiry = GetTime() + (durationHours * 3600)
        print(string.format("Content type manually set to '%s' for %d hours", contentType, durationHours))
    end
end

-- Get current content type (for meter scaling)
function CombatTracker:GetCurrentContentType()
    if contentDetection.manualOverride and GetTime() < contentDetection.overrideExpiry then
        return contentDetection.manualOverride
    end

    -- Default to normal for meter scaling
    return "normal"
end

-- =============================================================================
-- SESSION MANAGEMENT
-- =============================================================================

-- Calculate combat quality score (0-100) - Relative scoring, no magic numbers
local function CalculateQualityScore(sessionData)
    local score = 70 -- Start with "good" baseline
    local flags = {}

    if addon.DEBUG then
        print(string.format("Quality Debug: Duration=%.1f, Damage=%.0f, Healing=%.0f, DPS=%.0f, HPS=%.0f, Actions=%d",
            sessionData.duration, sessionData.totalDamage, sessionData.totalHealing,
            sessionData.avgDPS, sessionData.avgHPS, combatActionCount))
    end

    -- Duration check - the only reliable absolute metric
    if sessionData.duration < 3 then
        score = score - 40 -- Really short fights are questionable
        flags.tooShort = true
        if addon.DEBUG then print("Quality: Too short (-40)") end
    elseif sessionData.duration < 6 then
        score = score - 15 -- Short fights are less reliable
        if addon.DEBUG then print("Quality: Short (-15)") end
    elseif sessionData.duration > 30 then
        score = score + 10 -- Long fights are high quality
        if addon.DEBUG then print("Quality: Long fight (+10)") end
    else
        -- Normal duration 6-30s, no penalty
        if addon.DEBUG then print("Quality: Normal duration (0)") end
    end

    -- Activity check - based on actions per second (relative to duration)
    local actionsPerSecond = combatActionCount / sessionData.duration
    if actionsPerSecond < 0.3 then -- Less than 1 action per 3 seconds
        score = score - 25
        flags.lowActivity = true
        if addon.DEBUG then print(string.format("Quality: Low activity %.2f APS (-25)", actionsPerSecond)) end
    elseif actionsPerSecond > 1.5 then -- More than 1.5 actions per second
        score = score + 15             -- High activity bonus
        if addon.DEBUG then print(string.format("Quality: High activity %.2f APS (+15)", actionsPerSecond)) end
    else
        score = score + 5 -- Normal activity
        if addon.DEBUG then print(string.format("Quality: Normal activity %.2f APS (+5)", actionsPerSecond)) end
    end

    -- Performance consistency check - DPS should be reasonable relative to duration
    local expectedMinDPS = 10 * sessionData.duration -- Very low baseline: 10 DPS per second of combat
    if sessionData.avgDPS < expectedMinDPS then
        score = score - 20
        flags.lowDPS = true
        if addon.DEBUG then
            print(string.format("Quality: DPS too low %.0f < %.0f (-20)", sessionData.avgDPS,
                expectedMinDPS))
        end
    else
        score = score + 10 -- Meeting minimum performance
        if addon.DEBUG then print("Quality: DPS acceptable (+10)") end
    end

    -- Healing appropriateness (only matters if they did substantial healing relative to damage)
    if sessionData.totalHealing > 0 then
        local healingRatio = sessionData.totalHealing / sessionData.totalDamage
        if healingRatio > 0.5 then     -- Healing more than 50% of damage dealt (tank/healer)
            score = score + 10         -- Bonus for hybrid/support role
            if addon.DEBUG then print(string.format("Quality: High healing ratio %.2f (+10)", healingRatio)) end
        elseif healingRatio > 0.1 then -- Some healing (tank/hybrid)
            score = score + 5          -- Small bonus
            if addon.DEBUG then print(string.format("Quality: Some healing ratio %.2f (+5)", healingRatio)) end
        end
        -- Pure DPS with minimal healing gets no penalty or bonus
    end

    -- Combat engagement check - did damage happen throughout the fight?
    -- This catches "afk in combat" or "combat ended but still flagged" scenarios
    if sessionData.totalDamage == 0 then
        score = score - 50 -- No damage at all = not real combat
        flags.noDamage = true
        if addon.DEBUG then print("Quality: No damage (-50)") end
    end

    -- Cap score bounds
    score = math.max(0, math.min(100, score))

    if addon.DEBUG then
        print(string.format("Quality Final: %d, Flags: %s", score,
            next(flags) and table.concat(flags, ", ") or "none"))
    end

    return score, flags
end

-- Create session record from combat data
local function CreateSessionRecord()
    if not combatData.startTime or not combatData.endTime then
        if addon.DEBUG then
            print("Cannot create session: missing start/end time")
        end
        return nil
    end

    local duration = combatData.endTime - combatData.startTime
    local avgDPS = duration > 0 and (combatData.finalDamage / duration) or 0
    local avgHPS = duration > 0 and (combatData.finalHealing / duration) or 0

    local sessionData = {
        sessionId = GenerateSessionId(),
        startTime = combatData.startTime,
        endTime = combatData.endTime,
        duration = duration,

        -- Performance metrics
        totalDamage = combatData.finalDamage,
        totalHealing = combatData.finalHealing,
        totalOverheal = combatData.finalOverheal,
        totalAbsorb = combatData.finalAbsorb,
        avgDPS = avgDPS,
        avgHPS = avgHPS,
        peakDPS = combatData.finalMaxDPS,
        peakHPS = combatData.finalMaxHPS,

        -- Metadata
        location = GetZoneText() or "Unknown",
        playerLevel = UnitLevel("player"),
        actionCount = combatActionCount,

        -- User management
        userMarked = nil, -- "keep", "ignore", "representative"

        -- Quality will be calculated
        qualityScore = 0,
        qualityFlags = {}
    }

    -- Calculate quality and content type
    sessionData.qualityScore, sessionData.qualityFlags = CalculateQualityScore(sessionData)
    sessionData.contentType = CombatTracker:DetectContentType(sessionData)
    sessionData.detectionMethod = contentDetection.manualOverride and "manual" or "auto"

    if addon.DEBUG then
        print(string.format("Session created: %s, Quality: %d, Duration: %.1fs, DPS: %.0f, Type: %s",
            sessionData.sessionId, sessionData.qualityScore, sessionData.duration, sessionData.avgDPS,
            sessionData.contentType))
    end

    return sessionData
end

-- Add session to history with limit management
local function AddSessionToHistory(session)
    if not session then return end

    -- Add to beginning of array (most recent first)
    table.insert(sessionHistory, 1, session)

    -- Trim to limit
    while #sessionHistory > SESSION_HISTORY_LIMIT do
        table.remove(sessionHistory)
    end

    -- Save to database per-character-spec
    if addon.db then
        if not addon.db.sessionHistoryBySpec then
            addon.db.sessionHistoryBySpec = {}
        end
        addon.db.sessionHistoryBySpec[GetCharacterSpecKey()] = sessionHistory

        -- Also save to legacy character-only key for backwards compatibility
        if not addon.db.sessionHistory then
            addon.db.sessionHistory = {}
        end
        addon.db.sessionHistory[GetCharacterKey()] = sessionHistory
    end

    if addon.DEBUG then
        print(string.format("Session added to history for %s. Total sessions: %d", GetCharacterSpecKey(), #
            sessionHistory))
    end
end

-- =============================================================================
-- SESSION API FUNCTIONS
-- =============================================================================

-- Get session history array
function CombatTracker:GetSessionHistory()
    return sessionHistory
end

-- Get specific session by ID
function CombatTracker:GetSession(sessionId)
    for _, session in ipairs(sessionHistory) do
        if session.sessionId == sessionId then
            return session
        end
    end
    return nil
end

-- Mark session with user preference
function CombatTracker:MarkSession(sessionId, status)
    -- Convert short status names to full names for internal storage
    local fullStatus = status
    if status == "rep" then
        fullStatus = "representative"
    end

    -- First try exact match
    for _, session in ipairs(sessionHistory) do
        if session.sessionId == sessionId then
            session.userMarked = fullStatus
            if fullStatus == "representative" then
                session.qualityScore = 100 -- Override quality score
            end

            -- Save changes per-character-spec
            if addon.db then
                if not addon.db.sessionHistoryBySpec then
                    addon.db.sessionHistoryBySpec = {}
                end
                addon.db.sessionHistoryBySpec[GetCharacterSpecKey()] = sessionHistory

                -- Also save to legacy key
                if not addon.db.sessionHistory then
                    addon.db.sessionHistory = {}
                end
                addon.db.sessionHistory[GetCharacterKey()] = sessionHistory
            end

            if addon.DEBUG then
                print(string.format("Session %s marked as: %s", sessionId, fullStatus))
            end
            return true
        end
    end

    return false
end

-- Delete specific session
function CombatTracker:DeleteSession(sessionId)
    for i, session in ipairs(sessionHistory) do
        if session.sessionId == sessionId then
            table.remove(sessionHistory, i)

            -- Save changes per-character
            if addon.db then
                if not addon.db.sessionHistory then
                    addon.db.sessionHistory = {}
                end
                addon.db.sessionHistory[GetCharacterKey()] = sessionHistory
            end

            if addon.DEBUG then
                print(string.format("Session %s deleted", sessionId))
            end
            return true
        end
    end
    return false
end

-- Clear all session history
function CombatTracker:ClearHistory()
    sessionHistory = {}
    if addon.db then
        -- Clear spec-specific data
        if not addon.db.sessionHistoryBySpec then
            addon.db.sessionHistoryBySpec = {}
        end
        addon.db.sessionHistoryBySpec[GetCharacterSpecKey()] = {}

        -- Also clear legacy data
        if not addon.db.sessionHistory then
            addon.db.sessionHistory = {}
        end
        addon.db.sessionHistory[GetCharacterKey()] = {}
    end

    print(string.format("Session history cleared for %s", GetCharacterSpecKey()))
end

-- Get quality sessions only (score >= 70 or user marked as representative)
function CombatTracker:GetQualitySessions()
    local qualitySessions = {}
    for _, session in ipairs(sessionHistory) do
        if session.userMarked == "representative" or
            (session.userMarked ~= "ignore" and session.qualityScore >= 70) then
            table.insert(qualitySessions, session)
        end
    end
    return qualitySessions
end

-- Get sessions for specific content type with scaling focus
function CombatTracker:GetScalingSessions(contentType, maxCount)
    contentType = contentType or "normal"
    maxCount = maxCount or 10

    local filteredSessions = {}

    -- Filter sessions by content type and quality
    for _, session in ipairs(sessionHistory) do
        -- Skip ignored sessions for scaling calculations
        if session.userMarked ~= "ignore" then
            -- Include if content type matches OR if it's a representative session
            if session.contentType == contentType or session.userMarked == "representative" then
                -- Quality threshold: use representative sessions regardless of quality
                if session.userMarked == "representative" or session.qualityScore >= 60 then
                    table.insert(filteredSessions, session)
                end
            end
        end
    end

    -- Limit to maxCount most recent sessions
    local result = {}
    for i = 1, math.min(#filteredSessions, maxCount) do
        table.insert(result, filteredSessions[i])
    end

    if addon.DEBUG then
        print(string.format("GetScalingSessions(%s): Found %d sessions, returning %d",
            contentType, #filteredSessions, #result))
    end

    return result
end

-- Get baseline statistics for specific content type
function CombatTracker:GetContentBaseline(contentType, maxSessions)
    contentType = contentType or "normal"
    maxSessions = maxSessions or 15

    local sessions = self:GetScalingSessions(contentType, maxSessions)

    if #sessions == 0 then
        return {
            avgDPS = 0,
            avgHPS = 0,
            peakDPS = 0,
            peakHPS = 0,
            sampleCount = 0,
            contentType = contentType
        }
    end

    local totalDPS, totalHPS = 0, 0
    local maxPeakDPS, maxPeakHPS = 0, 0
    local validCount = 0

    for _, session in ipairs(sessions) do
        totalDPS = totalDPS + (session.avgDPS or 0)
        totalHPS = totalHPS + (session.avgHPS or 0)
        maxPeakDPS = math.max(maxPeakDPS, session.peakDPS or 0)
        maxPeakHPS = math.max(maxPeakHPS, session.peakHPS or 0)
        validCount = validCount + 1
    end

    return {
        avgDPS = validCount > 0 and (totalDPS / validCount) or 0,
        avgHPS = validCount > 0 and (totalHPS / validCount) or 0,
        peakDPS = maxPeakDPS,
        peakHPS = maxPeakHPS,
        sampleCount = validCount,
        contentType = contentType
    }
end

-- Check for spec changes and reload data if needed
function CombatTracker:CheckSpecChange()
    local newSpec = GetSpecialization()

    -- If spec changed, reload session data for new spec
    if currentSpec ~= nil and currentSpec ~= newSpec then
        if addon.DEBUG then
            local oldSpecName = "Unknown"
            local newSpecName = "Unknown"

            if currentSpec then
                local _, oldSpecName_temp = GetSpecializationInfo(currentSpec)
                if oldSpecName_temp then oldSpecName = oldSpecName_temp end
            end

            if newSpec then
                local _, newSpecName_temp = GetSpecializationInfo(newSpec)
                if newSpecName_temp then newSpecName = newSpecName_temp end
            end

            print(string.format("Spec changed from %s to %s - reloading session data", oldSpecName, newSpecName))
        end

        -- Reload session history for new spec
        self:InitializeSessionHistory()

        -- Reset meter scaling to let it adapt to new spec
        if addon.dpsPixelMeter then
            addon.dpsPixelMeter:ResetMaxValue()
        end
        if addon.hpsPixelMeter then
            addon.hpsPixelMeter:ResetMaxValue()
        end

        print(string.format("Switched to new spec - session data and meter scaling updated"))
    end

    currentSpec = newSpec
end

function CombatTracker:InitializeSessionHistory()
    local characterSpecKey = GetCharacterSpecKey()
    local characterKey = GetCharacterKey() -- Legacy fallback

    sessionHistory = {}

    -- Try to load spec-specific data first
    if addon.db and addon.db.sessionHistoryBySpec and addon.db.sessionHistoryBySpec[characterSpecKey] then
        sessionHistory = addon.db.sessionHistoryBySpec[characterSpecKey]
        if addon.DEBUG then
            print(string.format("Loaded %d sessions for %s", #sessionHistory, characterSpecKey))
        end
        -- Fallback to legacy character-only data
    elseif addon.db and addon.db.sessionHistory and addon.db.sessionHistory[characterKey] then
        sessionHistory = addon.db.sessionHistory[characterKey]
        if addon.DEBUG then
            print(string.format("Loaded %d legacy sessions for %s", #sessionHistory, characterKey))
        end

        -- Migrate to new spec-specific format
        if not addon.db.sessionHistoryBySpec then
            addon.db.sessionHistoryBySpec = {}
        end
        addon.db.sessionHistoryBySpec[characterSpecKey] = sessionHistory
        if addon.DEBUG then
            print(string.format("Migrated sessions to spec-specific storage: %s", characterSpecKey))
        end
    else
        sessionHistory = {}
        if addon.DEBUG then
            print(string.format("Initialized empty session history for %s", characterSpecKey))
        end
    end
end

-- =============================================================================
-- SAMPLING SYSTEM
-- =============================================================================

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
    end
end

-- =============================================================================
-- ROLLING AVERAGE API
-- =============================================================================

function CombatTracker:GetRollingDPS()
    local rolling = CalculateRollingAverages()
    return rolling.dps
end

function CombatTracker:GetRollingHPS()
    local rolling = CalculateRollingAverages()
    return rolling.hps
end

function CombatTracker:GetRollingEffectiveHPS()
    local rolling = CalculateRollingAverages()
    return rolling.effectiveHPS
end

function CombatTracker:GetRollingOverhealPercent()
    local rolling = CalculateRollingAverages()
    return rolling.overhealPercent
end

function CombatTracker:GetRollingAbsorbRate()
    local rolling = CalculateRollingAverages()
    return rolling.absorbRate
end

function CombatTracker:GetTimelineData()
    return timelineData.samples
end

function CombatTracker:GetRollingData()
    return CalculateRollingAverages()
end

-- =============================================================================
-- COMBAT TRACKING API
-- =============================================================================

-- Calculate DPS (rolling during combat, final after)
function CombatTracker:GetDPS()
    if combatData.inCombat then
        return self:GetRollingDPS()
    else
        return combatData.finalDPS or 0
    end
end

-- Calculate HPS (rolling during combat, final after)
function CombatTracker:GetHPS()
    if combatData.inCombat then
        return self:GetRollingHPS()
    else
        return combatData.finalHPS or 0
    end
end

-- Get displayed DPS for meters (rolling during combat, final after)
function CombatTracker:GetDisplayDPS()
    if combatData.inCombat then
        return self:GetRollingDPS()
    else
        return combatData.finalDPS or 0
    end
end

-- Get displayed HPS for meters (rolling during combat, final after)
function CombatTracker:GetDisplayHPS()
    if combatData.inCombat then
        return self:GetRollingHPS()
    else
        return combatData.finalHPS or 0
    end
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

    if not combatData.inCombat and combatData.endTime then
        return combatData.endTime - combatData.startTime
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

-- Check if in combat
function CombatTracker:IsInCombat()
    return combatData.inCombat
end

-- Get the final peak values from the last completed combat
function CombatTracker:GetLastCombatMaxDPS()
    return combatData.finalMaxDPS or 0
end

function CombatTracker:GetLastCombatMaxHPS()
    return combatData.finalMaxHPS or 0
end

-- =============================================================================
-- COMBAT EVENT HANDLERS
-- =============================================================================

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

    -- Reset action counter
    combatActionCount = 0

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

    -- Create and store session record
    local session = CreateSessionRecord()
    if session then
        AddSessionToHistory(session)
    end
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
                print(string.format("Damage: %s (%s)", self:FormatNumber(amount), subevent))
            end
        elseif amount and amount >= 10000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large damage: %s (%s)", self:FormatNumber(amount), subevent))
            end
        end

        -- Periodic damage (DOTs) with limits
    elseif subevent == "SPELL_PERIODIC_DAMAGE" then
        local amount = select(4, ...)

        -- Sanity check for DOT damage
        if amount and amount > 0 and amount < 5000000 then -- Max 5M per DOT tick
            combatData.damage = combatData.damage + amount

            if addon.DEBUG then
                print(string.format("DOT Damage: %s", self:FormatNumber(amount)))
            end
        elseif amount and amount >= 5000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large DOT: %s", self:FormatNumber(amount)))
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
                    self:FormatNumber(amount),
                    spellName or "Unknown",
                    critical and " CRIT" or ""
                ))
            end
        elseif amount and amount >= 5000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large heal: %s (%s)",
                    self:FormatNumber(amount),
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
                print(string.format("Absorb: %s", self:FormatNumber(absorbAmount)))
            end
        elseif absorbAmount and absorbAmount >= 5000000 then
            if addon.DEBUG then
                print(string.format("REJECTED large absorb: %s", self:FormatNumber(absorbAmount)))
            end
        end
    end
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
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Handle spec change event
        self:CheckSpecChange()
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

-- =============================================================================
-- RESET FUNCTIONS
-- =============================================================================

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

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Initialize combat tracker
function CombatTracker:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")         -- Entering combat
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")          -- Leaving combat
    self.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED") -- Spec changes
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

    -- Spec change check timer (check every 2 seconds)
    self.specCheckTimer = C_Timer.NewTicker(2.0, function()
        CombatTracker:CheckSpecChange()
    end)
end

-- =============================================================================
-- DEBUG FUNCTIONS
-- =============================================================================

-- Debug session history
function CombatTracker:DebugSessionHistory()
    print("=== SESSION HISTORY DEBUG ===")
    print(string.format("Total sessions: %d", #sessionHistory))
    print(string.format("History limit: %d", SESSION_HISTORY_LIMIT))

    if #sessionHistory > 0 then
        print("Recent sessions:")
        for i = 1, math.min(5, #sessionHistory) do
            local s = sessionHistory[i]
            print(string.format("[%d] %s: %.1fs, DPS:%.0f, HPS:%.0f, Q:%d, Type:%s%s",
                i, s.sessionId:sub(-8), s.duration, s.avgDPS, s.avgHPS, s.qualityScore,
                s.contentType or "unknown",
                s.userMarked and (" (" .. s.userMarked .. ")") or ""
            ))
        end

        if #sessionHistory > 5 then
            print(string.format("... and %d more", #sessionHistory - 5))
        end
    else
        print("No sessions recorded")
    end

    local qualitySessions = self:GetQualitySessions()
    print(string.format("Quality sessions: %d", #qualitySessions))

    print("=========================")
end

-- Generate test session data for development
function CombatTracker:GenerateTestData()
    -- Clear existing data first
    sessionHistory = {}

    -- Get current character info for appropriate test data
    local specIndex = GetSpecialization()
    local specName = "Unknown"
    local className = UnitClass("player")

    if specIndex then
        local _, specName_temp = GetSpecializationInfo(specIndex)
        if specName_temp then
            specName = specName_temp
        end
    end

    -- Adjust test data based on spec/class
    local testSessions = {}

    -- Determine appropriate DPS/HPS ranges based on role
    local isDPS = specName:find("Shadow") or specName:find("Fire") or specName:find("Frost") or
        specName:find("Arcane") or specName:find("Fury") or specName:find("Arms") or
        specName:find("Retribution") or specName:find("Enhancement") or specName:find("Elemental") or
        specName:find("Balance") or specName:find("Feral") or specName:find("Beast") or
        specName:find("Marksmanship") or specName:find("Survival") or specName:find("Assassination") or
        specName:find("Outlaw") or specName:find("Subtlety") or specName:find("Affliction") or
        specName:find("Demonology") or specName:find("Destruction") or specName:find("Havoc") or
        specName:find("Windwalker") or specName:find("Devastation") or specName:find("Augmentation")

    local isHealer = specName:find("Holy") or specName:find("Discipline") or specName:find("Restoration") or
        specName:find("Mistweaver") or specName:find("Preservation")

    local isTank = specName:find("Protection") or specName:find("Blood") or specName:find("Guardian") or
        specName:find("Brewmaster") or specName:find("Vengeance")

    if isDPS then
        -- DPS spec test data - high damage, low healing
        testSessions = {
            { dps = 850000,  hps = 5000, duration = 45, quality = 85, location = "Mythic Keystone", type = "normal" },
            { dps = 1200000, hps = 3000, duration = 38, quality = 90, location = "The Dawnbreaker", type = "normal" },
            { dps = 750000,  hps = 8000, duration = 52, quality = 80, location = "Ara-Kara",        type = "normal" },
            { dps = 950000,  hps = 4000, duration = 41, quality = 88, location = "City of Threads", type = "normal" },
            { dps = 1350000, hps = 2000, duration = 35, quality = 92, location = "The Stonevault",  type = "normal" },
            { dps = 180000,  hps = 2000, duration = 65, quality = 75, location = "Timewalking",     type = "scaled" },
            { dps = 220000,  hps = 3000, duration = 58, quality = 78, location = "Black Temple",    type = "scaled" },
            { dps = 1650000, hps = 5000, duration = 28, quality = 95, location = "Raid Finder",     type = "normal" },
        }
    elseif isHealer then
        -- Healer spec test data - moderate damage, high healing
        testSessions = {
            { dps = 250000, hps = 450000, duration = 45, quality = 85, location = "Mythic Keystone", type = "normal" },
            { dps = 180000, hps = 580000, duration = 38, quality = 90, location = "The Dawnbreaker", type = "normal" },
            { dps = 220000, hps = 520000, duration = 52, quality = 80, location = "Ara-Kara",        type = "normal" },
            { dps = 200000, hps = 495000, duration = 41, quality = 88, location = "City of Threads", type = "normal" },
            { dps = 160000, hps = 620000, duration = 35, quality = 92, location = "The Stonevault",  type = "normal" },
            { dps = 80000,  hps = 180000, duration = 65, quality = 75, location = "Timewalking",     type = "scaled" },
            { dps = 90000,  hps = 200000, duration = 58, quality = 78, location = "Black Temple",    type = "scaled" },
            { dps = 140000, hps = 750000, duration = 28, quality = 95, location = "Raid Finder",     type = "normal" },
        }
    elseif isTank then
        -- Tank spec test data - moderate damage, moderate healing
        testSessions = {
            { dps = 450000, hps = 180000, duration = 45, quality = 85, location = "Mythic Keystone", type = "normal" },
            { dps = 520000, hps = 150000, duration = 38, quality = 90, location = "The Dawnbreaker", type = "normal" },
            { dps = 380000, hps = 220000, duration = 52, quality = 80, location = "Ara-Kara",        type = "normal" },
            { dps = 490000, hps = 190000, duration = 41, quality = 88, location = "City of Threads", type = "normal" },
            { dps = 550000, hps = 160000, duration = 35, quality = 92, location = "The Stonevault",  type = "normal" },
            { dps = 120000, hps = 60000,  duration = 65, quality = 75, location = "Timewalking",     type = "scaled" },
            { dps = 140000, hps = 70000,  duration = 58, quality = 78, location = "Black Temple",    type = "scaled" },
            { dps = 480000, hps = 250000, duration = 28, quality = 95, location = "Raid Finder",     type = "normal" },
        }
    else
        -- Unknown/hybrid spec - balanced data
        testSessions = {
            { dps = 600000, hps = 100000, duration = 45, quality = 85, location = "Mythic Keystone", type = "normal" },
            { dps = 750000, hps = 80000,  duration = 38, quality = 90, location = "The Dawnbreaker", type = "normal" },
            { dps = 550000, hps = 120000, duration = 52, quality = 80, location = "Ara-Kara",        type = "normal" },
            { dps = 680000, hps = 90000,  duration = 41, quality = 88, location = "City of Threads", type = "normal" },
            { dps = 800000, hps = 70000,  duration = 35, quality = 92, location = "The Stonevault",  type = "normal" },
            { dps = 150000, hps = 30000,  duration = 65, quality = 75, location = "Timewalking",     type = "scaled" },
            { dps = 180000, hps = 40000,  duration = 58, quality = 78, location = "Black Temple",    type = "scaled" },
            { dps = 850000, hps = 110000, duration = 28, quality = 95, location = "Raid Finder",     type = "normal" },
        }
    end

    -- Add some poor quality sessions regardless of spec
    table.insert(testSessions,
        { dps = 80000, hps = 5000, duration = 8, quality = 45, location = "Stormwind", type = "normal" })
    table.insert(testSessions,
        { dps = 120000, hps = 3000, duration = 12, quality = 38, location = "Valdrakken", type = "normal" })

    local currentTime = GetTime()
    local baseTime = currentTime - 3600 -- Start 1 hour ago

    for i, data in ipairs(testSessions) do
        local session = {
            sessionId = GenerateSessionId(),
            startTime = baseTime + (i * 180), -- 3 minutes apart
            endTime = baseTime + (i * 180) + data.duration,
            duration = data.duration,

            -- Performance metrics
            totalDamage = data.dps * data.duration,
            totalHealing = data.hps * data.duration,
            totalOverheal = math.floor(data.hps * data.duration * 0.25), -- 25% overheal
            totalAbsorb = math.floor(data.hps * data.duration * 0.1),    -- 10% absorbs
            avgDPS = data.dps,
            avgHPS = data.hps,
            peakDPS = math.floor(data.dps * 1.3), -- 30% higher peaks
            peakHPS = math.floor(data.hps * 1.4), -- 40% higher peaks

            -- Metadata
            location = data.location,
            playerLevel = 80,
            actionCount = math.floor(data.duration * 2), -- 2 actions per second

            -- Quality assessment
            qualityScore = data.quality,
            qualityFlags = {},
            contentType = data.type,
            detectionMethod = "manual",

            -- User management
            userMarked = nil
        }

        -- Add some representative sessions
        if i == 2 then -- Mark one session as representative
            session.userMarked = "representative"
            session.qualityScore = 100
        elseif i == #testSessions - 1 then -- Mark one poor session as ignore
            session.userMarked = "ignore"
        end

        -- Insert at beginning to maintain "most recent first" order
        table.insert(sessionHistory, 1, session)
    end

    -- Save to database with spec-specific key
    if addon.db then
        if not addon.db.sessionHistoryBySpec then
            addon.db.sessionHistoryBySpec = {}
        end
        addon.db.sessionHistoryBySpec[GetCharacterSpecKey()] = sessionHistory

        -- Also save to legacy key for compatibility
        if not addon.db.sessionHistory then
            addon.db.sessionHistory = {}
        end
        addon.db.sessionHistory[GetCharacterKey()] = sessionHistory
    end

    if addon.DEBUG then
        print(string.format("Generated %d %s test sessions for %s", #testSessions,
            isDPS and "DPS" or (isHealer and "Healer" or (isTank and "Tank" or "Hybrid")),
            GetCharacterSpecKey()))
        self:DebugSessionHistory()
    end
end

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

-- Debug method for content scaling analysis
function CombatTracker:DebugContentScaling()
    print("=== CONTENT SCALING DEBUG ===")

    local currentType = self:GetCurrentContentType()
    print(string.format("Current content type: %s", currentType))

    -- Show baseline for each content type
    for _, contentType in ipairs({ "normal", "scaled" }) do
        local baseline = self:GetContentBaseline(contentType, 10)
        local sessions = self:GetScalingSessions(contentType, 10)

        print(string.format("\n%s Content:", string.upper(contentType)))
        print(string.format("  Sessions: %d (baseline from %d)", #sessions, baseline.sampleCount))
        print(string.format("  Avg DPS: %s", self:FormatNumber(baseline.avgDPS)))
        print(string.format("  Avg HPS: %s", self:FormatNumber(baseline.avgHPS)))
        print(string.format("  Peak DPS: %s", self:FormatNumber(baseline.peakDPS)))
        print(string.format("  Peak HPS: %s", self:FormatNumber(baseline.peakHPS)))

        if #sessions > 0 then
            print("  Recent sessions:")
            for i = 1, math.min(3, #sessions) do
                local s = sessions[i]
                print(string.format("    %s: DPS %.0f, HPS %.0f, Q:%d%s",
                    s.sessionId:sub(-8), s.avgDPS, s.avgHPS, s.qualityScore,
                    s.userMarked and (" (" .. s.userMarked .. ")") or ""))
            end
        end
    end

    -- Show content detection ratios
    if #sessionHistory > 0 then
        local lastSession = sessionHistory[1]
        local normalBaseline = self:GetContentBaseline("normal", 20)

        if normalBaseline.sampleCount > 0 then
            local dpsRatio = normalBaseline.avgDPS > 0 and (lastSession.avgDPS / normalBaseline.avgDPS) or 1
            local hpsRatio = normalBaseline.avgHPS > 0 and (lastSession.avgHPS / normalBaseline.avgHPS) or 1

            print(string.format("\nLast Session Detection:"))
            print(string.format("  DPS Ratio: %.2f (%.0f / %.0f)", dpsRatio, lastSession.avgDPS, normalBaseline.avgDPS))
            print(string.format("  HPS Ratio: %.2f (%.0f / %.0f)", hpsRatio, lastSession.avgHPS, normalBaseline.avgHPS))
            print(string.format("  Detected as: %s", lastSession.contentType))
        end
    end

    print("========================")
end
