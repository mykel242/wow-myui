-- MyCombatMeterScaler.lua
-- Dynamic scaling system for combat meter based on session history
--
-- SCALING STRATEGY:
-- - Analyzes last N sessions for peak DPS/HPS values
-- - Calculates appropriate scale using 95th percentile + 10% buffer
-- - Maintains separate scales per character/spec combination
-- - Provides manual override capability
-- - Adapts to player progression and gear improvements

local addonName, addon = ...

-- =============================================================================
-- COMBAT METER SCALER MODULE
-- =============================================================================

local MyCombatMeterScaler = {}
addon.MyCombatMeterScaler = MyCombatMeterScaler

-- =============================================================================
-- CONSTANTS AND CONFIGURATION
-- =============================================================================

local DEFAULT_CONFIG = {
    HISTORY_SESSION_COUNT = 10,     -- Number of recent sessions to analyze
    PERCENTILE_THRESHOLD = 0.95,    -- Use 95th percentile for scale calculation
    SCALE_BUFFER_PERCENT = 10,      -- Add 10% buffer above percentile
    MIN_SCALE = 100,                -- Minimum scale value
    MAX_SCALE = 1000000,            -- Maximum scale value (1M DPS/HPS)
    DEFAULT_SCALE = 1000,           -- Default scale for new characters
    MINIMUM_COMBAT_DURATION = 10,   -- Only use sessions longer than 10 seconds
    SCALE_DECAY_DAYS = 7,           -- Reduce scale weight for sessions older than 7 days
    AUTO_SCALE_ENABLED = true,      -- Whether to automatically update scales
    MANUAL_OVERRIDE_DURATION = 300, -- Manual overrides last 5 minutes
}

-- Scale storage structure
local scaleData = {
    characterScales = {},           -- Per-character/spec scales
    lastAnalysis = 0,               -- When we last analyzed sessions
    analysisCache = {},             -- Cached analysis results
    manualOverrides = {},           -- Manual scale overrides with timestamps
    globalSettings = {              -- Global scaler settings
        autoScaleEnabled = DEFAULT_CONFIG.AUTO_SCALE_ENABLED,
        historyCount = DEFAULT_CONFIG.HISTORY_SESSION_COUNT,
        scaleBuffer = DEFAULT_CONFIG.SCALE_BUFFER_PERCENT
    }
}

-- Current character/spec info
local currentCharacterKey = nil
local currentSpecName = nil

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MyCombatMeterScaler:Initialize()
    -- Get current character info
    self:UpdateCharacterInfo()
    
    -- Load saved scale data
    self:LoadScaleData()
    
    addon:Debug("MyCombatMeterScaler initialized for: %s", currentCharacterKey or "Unknown")
end

-- Update current character and spec information
function MyCombatMeterScaler:UpdateCharacterInfo()
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    
    -- Get current spec
    local specIndex = GetSpecialization()
    local specName = "Unknown"
    
    if specIndex then
        local specID, name = GetSpecializationInfo(specIndex)
        if name then
            specName = name
        end
    end
    
    currentCharacterKey = string.format("%s-%s-%s", playerName, realmName, specName)
    currentSpecName = specName
    
    -- Initialize character scale data if not exists
    if not scaleData.characterScales[currentCharacterKey] then
        scaleData.characterScales[currentCharacterKey] = {
            dpsScale = DEFAULT_CONFIG.DEFAULT_SCALE,
            hpsScale = DEFAULT_CONFIG.DEFAULT_SCALE,
            lastUpdated = GetServerTime(),
            sessionCount = 0,
            peakValues = {
                dps = 0,
                hps = 0,
                timestamp = 0
            }
        }
    end
end

-- =============================================================================
-- SCALE CALCULATION FUNCTIONS
-- =============================================================================

-- Analyze recent sessions and calculate optimal scales
function MyCombatMeterScaler:AnalyzeSessionHistory()
    if not addon.StorageManager then
        addon:Error("StorageManager not available for scale analysis")
        return nil
    end
    
    local sessions = addon.StorageManager:GetRecentSessions(scaleData.globalSettings.historyCount)
    if not sessions or #sessions == 0 then
        addon:Debug("No sessions available for scale analysis")
        return nil
    end
    
    local validSessions = self:FilterValidSessions(sessions)
    if #validSessions == 0 then
        addon:Debug("No valid sessions found for scale analysis")
        return nil
    end
    
    local dpsValues = {}
    local hpsValues = {}
    
    -- Extract peak DPS/HPS values from each session
    for _, session in ipairs(validSessions) do
        local peakDPS, peakHPS = self:ExtractSessionPeaks(session)
        
        if peakDPS > 0 then
            table.insert(dpsValues, peakDPS)
        end
        if peakHPS > 0 then
            table.insert(hpsValues, peakHPS)
        end
    end
    
    -- Calculate scales based on percentiles
    local dpsScale = self:CalculateScaleFromValues(dpsValues)
    local hpsScale = self:CalculateScaleFromValues(hpsValues)
    
    local analysis = {
        sessionsAnalyzed = #validSessions,
        dpsValues = dpsValues,
        hpsValues = hpsValues,
        recommendedDPSScale = dpsScale,
        recommendedHPSScale = hpsScale,
        timestamp = GetServerTime()
    }
    
    -- Cache the analysis
    scaleData.analysisCache = analysis
    scaleData.lastAnalysis = GetServerTime()
    
    addon:Debug("Scale analysis complete: DPS=%.0f, HPS=%.0f (from %d sessions)", 
        dpsScale, hpsScale, #validSessions)
    
    return analysis
end

-- Filter sessions to only include valid ones for scaling
function MyCombatMeterScaler:FilterValidSessions(sessions)
    local validSessions = {}
    local cutoffTime = GetServerTime() - (DEFAULT_CONFIG.SCALE_DECAY_DAYS * 24 * 60 * 60)
    
    for _, session in ipairs(sessions) do
        -- Filter criteria
        local isValidDuration = (session.duration or 0) >= DEFAULT_CONFIG.MINIMUM_COMBAT_DURATION
        local isRecentEnough = (session.serverTime or 0) >= cutoffTime
        local hasEvents = (session.eventCount or 0) > 0
        
        if isValidDuration and isRecentEnough and hasEvents then
            table.insert(validSessions, session)
        end
    end
    
    return validSessions
end

-- Extract peak DPS/HPS values from a session
function MyCombatMeterScaler:ExtractSessionPeaks(session)
    -- For now, estimate peaks based on total damage/healing and duration
    -- TODO: Integrate with actual peak calculation from combat events
    
    local duration = session.duration or 1
    local totalDamage = 0
    local totalHealing = 0
    
    -- Try to get actual damage/healing totals if available
    if session.events then
        for _, event in ipairs(session.events) do
            if event.type == "DAMAGE" and event.amount then
                totalDamage = totalDamage + event.amount
            elseif event.type == "HEAL" and event.amount then
                totalHealing = totalHealing + event.amount
            end
        end
    end
    
    -- Estimate peak as 150% of average (burst factor)
    local avgDPS = totalDamage / duration
    local avgHPS = totalHealing / duration
    local peakDPS = avgDPS * 1.5
    local peakHPS = avgHPS * 1.5
    
    return peakDPS, peakHPS
end

-- Calculate scale from a set of values using percentile + buffer
function MyCombatMeterScaler:CalculateScaleFromValues(values)
    if not values or #values == 0 then
        return DEFAULT_CONFIG.DEFAULT_SCALE
    end
    
    -- Sort values
    table.sort(values)
    
    -- Calculate percentile index
    local percentileIndex = math.ceil(#values * DEFAULT_CONFIG.PERCENTILE_THRESHOLD)
    percentileIndex = math.max(1, math.min(percentileIndex, #values))
    
    local percentileValue = values[percentileIndex]
    
    -- Add buffer
    local bufferMultiplier = 1 + (scaleData.globalSettings.scaleBuffer / 100)
    local scale = percentileValue * bufferMultiplier
    
    -- Apply bounds
    scale = math.max(DEFAULT_CONFIG.MIN_SCALE, math.min(DEFAULT_CONFIG.MAX_SCALE, scale))
    
    return math.floor(scale)
end

-- =============================================================================
-- SCALE MANAGEMENT
-- =============================================================================

-- Get current scales for the character/spec
function MyCombatMeterScaler:GetCurrentScales()
    if not currentCharacterKey then
        self:UpdateCharacterInfo()
    end
    
    local characterData = scaleData.characterScales[currentCharacterKey]
    if not characterData then
        return DEFAULT_CONFIG.DEFAULT_SCALE, DEFAULT_CONFIG.DEFAULT_SCALE
    end
    
    -- Check for manual overrides
    local now = GetServerTime()
    local manualOverride = scaleData.manualOverrides[currentCharacterKey]
    
    if manualOverride and (now - manualOverride.timestamp) < DEFAULT_CONFIG.MANUAL_OVERRIDE_DURATION then
        return manualOverride.dpsScale, manualOverride.hpsScale
    end
    
    return characterData.dpsScale, characterData.hpsScale
end

-- Update scales based on analysis
function MyCombatMeterScaler:UpdateScales(analysis)
    if not analysis or not currentCharacterKey then
        return false
    end
    
    local characterData = scaleData.characterScales[currentCharacterKey]
    if not characterData then
        return false
    end
    
    -- Update scales
    characterData.dpsScale = analysis.recommendedDPSScale
    characterData.hpsScale = analysis.recommendedHPSScale
    characterData.lastUpdated = GetServerTime()
    characterData.sessionCount = analysis.sessionsAnalyzed
    
    -- Update peak tracking
    if #analysis.dpsValues > 0 then
        characterData.peakValues.dps = math.max(unpack(analysis.dpsValues))
    end
    if #analysis.hpsValues > 0 then
        characterData.peakValues.hps = math.max(unpack(analysis.hpsValues))
    end
    characterData.peakValues.timestamp = GetServerTime()
    
    -- Save to persistent storage
    self:SaveScaleData()
    
    addon:Debug("Scales updated for %s: DPS=%.0f, HPS=%.0f", 
        currentCharacterKey, characterData.dpsScale, characterData.hpsScale)
    
    return true
end

-- Set manual scale override
function MyCombatMeterScaler:SetManualScale(dpsScale, hpsScale)
    if not currentCharacterKey then
        self:UpdateCharacterInfo()
    end
    
    -- Validate inputs
    dpsScale = math.max(DEFAULT_CONFIG.MIN_SCALE, math.min(DEFAULT_CONFIG.MAX_SCALE, dpsScale or DEFAULT_CONFIG.DEFAULT_SCALE))
    hpsScale = math.max(DEFAULT_CONFIG.MIN_SCALE, math.min(DEFAULT_CONFIG.MAX_SCALE, hpsScale or DEFAULT_CONFIG.DEFAULT_SCALE))
    
    scaleData.manualOverrides[currentCharacterKey] = {
        dpsScale = dpsScale,
        hpsScale = hpsScale,
        timestamp = GetServerTime()
    }
    
    addon:Debug("Manual scale override set: DPS=%.0f, HPS=%.0f", dpsScale, hpsScale)
    return true
end

-- Clear manual scale override
function MyCombatMeterScaler:ClearManualScale()
    if currentCharacterKey and scaleData.manualOverrides[currentCharacterKey] then
        scaleData.manualOverrides[currentCharacterKey] = nil
        addon:Debug("Manual scale override cleared")
        return true
    end
    return false
end

-- =============================================================================
-- AUTO-SCALING FUNCTIONS
-- =============================================================================

-- Automatically update scales after combat ends
function MyCombatMeterScaler:AutoUpdateAfterCombat(sessionData)
    if not scaleData.globalSettings.autoScaleEnabled then
        return false
    end
    
    if not sessionData or (sessionData.duration or 0) < DEFAULT_CONFIG.MINIMUM_COMBAT_DURATION then
        return false
    end
    
    -- Only update occasionally to avoid constant recalculation
    local timeSinceLastAnalysis = GetServerTime() - scaleData.lastAnalysis
    if timeSinceLastAnalysis < 300 then -- 5 minutes
        return false
    end
    
    local analysis = self:AnalyzeSessionHistory()
    if analysis then
        return self:UpdateScales(analysis)
    end
    
    return false
end

-- Check if scales need updating based on recent performance
function MyCombatMeterScaler:CheckScaleRelevance(currentDPS, currentHPS)
    local dpsScale, hpsScale = self:GetCurrentScales()
    
    -- If current values consistently exceed scale, we might need to update
    local dpsRatio = dpsScale > 0 and (currentDPS / dpsScale) or 0
    local hpsRatio = hpsScale > 0 and (currentHPS / hpsScale) or 0
    
    local scaleNeedsUpdate = false
    local reasons = {}
    
    if dpsRatio > 1.2 then -- Exceeding scale by 20%
        scaleNeedsUpdate = true
        table.insert(reasons, string.format("DPS exceeds scale by %.0f%%", (dpsRatio - 1) * 100))
    end
    
    if hpsRatio > 1.2 then -- Exceeding scale by 20%
        scaleNeedsUpdate = true
        table.insert(reasons, string.format("HPS exceeds scale by %.0f%%", (hpsRatio - 1) * 100))
    end
    
    return scaleNeedsUpdate, reasons
end

-- =============================================================================
-- PERSISTENT STORAGE
-- =============================================================================

-- Save scale data to SavedVariables
function MyCombatMeterScaler:SaveScaleData()
    if not MyUIDB then
        MyUIDB = {}
    end
    
    MyUIDB.combatMeterScales = scaleData
    
    -- Note: Silent save to avoid spam
end

-- Load scale data from SavedVariables
function MyCombatMeterScaler:LoadScaleData()
    if MyUIDB and MyUIDB.combatMeterScales then
        local savedData = MyUIDB.combatMeterScales
        
        -- Merge saved data with defaults
        scaleData.characterScales = savedData.characterScales or {}
        scaleData.lastAnalysis = savedData.lastAnalysis or 0
        scaleData.manualOverrides = savedData.manualOverrides or {}
        
        if savedData.globalSettings then
            for k, v in pairs(savedData.globalSettings) do
                scaleData.globalSettings[k] = v
            end
        end
        
        addon:Debug("Scale data loaded from SavedVariables")
    else
        addon:Debug("No saved scale data found, using defaults")
    end
end

-- =============================================================================
-- CONFIGURATION AND SETTINGS
-- =============================================================================

function MyCombatMeterScaler:SetAutoScaleEnabled(enabled)
    scaleData.globalSettings.autoScaleEnabled = enabled
    self:SaveScaleData()
    addon:Debug("Auto-scaling %s", enabled and "enabled" or "disabled")
end

function MyCombatMeterScaler:IsAutoScaleEnabled()
    return scaleData.globalSettings.autoScaleEnabled
end

function MyCombatMeterScaler:SetHistorySessionCount(count)
    scaleData.globalSettings.historyCount = math.max(5, math.min(25, count))
    self:SaveScaleData()
    addon:Debug("History session count set to: %d", scaleData.globalSettings.historyCount)
end

function MyCombatMeterScaler:GetHistorySessionCount()
    return scaleData.globalSettings.historyCount
end

function MyCombatMeterScaler:SetScaleBuffer(percent)
    scaleData.globalSettings.scaleBuffer = math.max(0, math.min(50, percent))
    self:SaveScaleData()
    addon:Debug("Scale buffer set to: %.0f%%", scaleData.globalSettings.scaleBuffer)
end

function MyCombatMeterScaler:GetScaleBuffer()
    return scaleData.globalSettings.scaleBuffer
end

-- =============================================================================
-- ANALYSIS AND REPORTING
-- =============================================================================

-- Generate scale analysis report
function MyCombatMeterScaler:GenerateScaleReport()
    local analysis = scaleData.analysisCache
    local dpsScale, hpsScale = self:GetCurrentScales()
    
    local lines = {}
    table.insert(lines, "=== Combat Meter Scale Analysis ===")
    table.insert(lines, string.format("Character: %s", currentCharacterKey or "Unknown"))
    table.insert(lines, string.format("Spec: %s", currentSpecName or "Unknown"))
    table.insert(lines, "")
    
    table.insert(lines, "Current Scales:")
    table.insert(lines, string.format("  DPS Scale: %.0f", dpsScale))
    table.insert(lines, string.format("  HPS Scale: %.0f", hpsScale))
    table.insert(lines, "")
    
    -- Manual override info
    local manualOverride = scaleData.manualOverrides[currentCharacterKey]
    if manualOverride then
        local timeRemaining = DEFAULT_CONFIG.MANUAL_OVERRIDE_DURATION - (GetServerTime() - manualOverride.timestamp)
        if timeRemaining > 0 then
            table.insert(lines, string.format("Manual Override Active: %.0f seconds remaining", timeRemaining))
        end
    end
    
    -- Analysis info
    if analysis then
        table.insert(lines, "Recent Analysis:")
        table.insert(lines, string.format("  Sessions Analyzed: %d", analysis.sessionsAnalyzed))
        table.insert(lines, string.format("  Recommended DPS Scale: %.0f", analysis.recommendedDPSScale))
        table.insert(lines, string.format("  Recommended HPS Scale: %.0f", analysis.recommendedHPSScale))
        table.insert(lines, string.format("  Analysis Time: %s", date("%Y-%m-%d %H:%M:%S", analysis.timestamp)))
        
        if #analysis.dpsValues > 0 then
            table.sort(analysis.dpsValues)
            table.insert(lines, string.format("  DPS Range: %.0f - %.0f (median: %.0f)", 
                analysis.dpsValues[1], 
                analysis.dpsValues[#analysis.dpsValues],
                analysis.dpsValues[math.ceil(#analysis.dpsValues / 2)]))
        end
        
        if #analysis.hpsValues > 0 then
            table.sort(analysis.hpsValues)
            table.insert(lines, string.format("  HPS Range: %.0f - %.0f (median: %.0f)", 
                analysis.hpsValues[1], 
                analysis.hpsValues[#analysis.hpsValues],
                analysis.hpsValues[math.ceil(#analysis.hpsValues / 2)]))
        end
    else
        table.insert(lines, "No recent analysis available")
    end
    
    table.insert(lines, "")
    table.insert(lines, "Settings:")
    table.insert(lines, string.format("  Auto-Scale: %s", scaleData.globalSettings.autoScaleEnabled and "Enabled" or "Disabled"))
    table.insert(lines, string.format("  History Sessions: %d", scaleData.globalSettings.historyCount))
    table.insert(lines, string.format("  Scale Buffer: %.0f%%", scaleData.globalSettings.scaleBuffer))
    
    return table.concat(lines, "\n")
end

-- Get status information
function MyCombatMeterScaler:GetStatus()
    local dpsScale, hpsScale = self:GetCurrentScales()
    local hasManualOverride = scaleData.manualOverrides[currentCharacterKey] ~= nil
    
    return {
        currentCharacter = currentCharacterKey,
        currentSpec = currentSpecName,
        dpsScale = dpsScale,
        hpsScale = hpsScale,
        autoScaleEnabled = scaleData.globalSettings.autoScaleEnabled,
        hasManualOverride = hasManualOverride,
        lastAnalysis = scaleData.lastAnalysis,
        historySessionCount = scaleData.globalSettings.historyCount,
        scaleBuffer = scaleData.globalSettings.scaleBuffer
    }
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

-- Force immediate scale analysis and update
function MyCombatMeterScaler:ForceScaleUpdate()
    local analysis = self:AnalyzeSessionHistory()
    if analysis then
        self:UpdateScales(analysis)
        return analysis
    end
    return nil
end

-- Get recommended scales without updating current scales
function MyCombatMeterScaler:GetRecommendedScales()
    local analysis = self:AnalyzeSessionHistory()
    if analysis then
        return analysis.recommendedDPSScale, analysis.recommendedHPSScale
    end
    return nil, nil
end

return MyCombatMeterScaler