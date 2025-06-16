-- SessionManager.lua
-- Session history management and storage

local addonName, addon = ...

-- Session manager module
addon.SessionManager = {}
local SessionManager = addon.SessionManager

-- =============================================================================
-- CONFIGURATION & CONSTANTS
-- =============================================================================

local SESSION_HISTORY_LIMIT = 50 -- Maximum sessions to store (reduced from 100 for memory management)

-- =============================================================================
-- DATA STRUCTURES
-- =============================================================================

-- Session history
local sessionHistory = {} -- Will be per-character

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

-- =============================================================================
-- SESSION MANAGEMENT
-- =============================================================================

-- Calculate combat quality score (0-100) - Relative scoring, no magic numbers
local function CalculateQualityScore(sessionData)
    local score = 70 -- Start with "good" baseline
    local flags = {}
    local combatActionCount = addon.CombatData:GetActionCount()

    addon:Debug("Quality Debug: Duration=%.1f, Damage=%.0f, Healing=%.0f, DPS=%.0f, HPS=%.0f, Actions=%d",
        sessionData.duration, sessionData.totalDamage, sessionData.totalHealing,
        sessionData.avgDPS, sessionData.avgHPS, combatActionCount)

    -- Duration check - the only reliable absolute metric
    if sessionData.duration < 3 then
        score = score - 40 -- Really short fights are questionable
        flags.tooShort = true
        addon:Debug("Quality: Too short (-40)")
    elseif sessionData.duration < 6 then
        score = score - 15 -- Short fights are less reliable
        addon:Debug("Quality: Short (-15)")
    elseif sessionData.duration > 30 then
        score = score + 10 -- Long fights are high quality
        addon:Debug("Quality: Long fight (+10)")
    else
        -- Normal duration 6-30s, no penalty
        addon:Debug("Quality: Normal duration (0)")
    end

    -- Activity check - based on actions per second (relative to duration)
    local actionsPerSecond = combatActionCount / sessionData.duration
    if actionsPerSecond < 0.3 then -- Less than 1 action per 3 seconds
        score = score - 25
        flags.lowActivity = true
        addon:Debug("Quality: Low activity %.2f APS (-25)", actionsPerSecond)
    elseif actionsPerSecond > 1.5 then -- More than 1.5 actions per second
        score = score + 15             -- High activity bonus
        addon:Debug("Quality: High activity %.2f APS (+15)", actionsPerSecond)
    else
        score = score + 5 -- Normal activity
        addon:Debug("Quality: Normal activity %.2f APS (+5)", actionsPerSecond)
    end

    -- Performance consistency check - DPS should be reasonable relative to duration
    local expectedMinDPS = 10 * sessionData.duration -- Very low baseline: 10 DPS per second of combat
    if sessionData.avgDPS < expectedMinDPS then
        score = score - 20
        flags.lowDPS = true
        addon:Debug("Quality: DPS too low %.0f < %.0f (-20)", sessionData.avgDPS, expectedMinDPS)
    else
        score = score + 10 -- Meeting minimum performance
        addon:Debug("Quality: DPS acceptable (+10)")
    end

    -- Healing appropriateness (only matters if they did substantial healing relative to damage)
    if sessionData.totalHealing > 0 then
        local healingRatio = sessionData.totalHealing / sessionData.totalDamage
        if healingRatio > 0.5 then     -- Healing more than 50% of damage dealt (tank/healer)
            score = score + 10         -- Bonus for hybrid/support role
            addon:Debug("Quality: High healing ratio %.2f (+10)", healingRatio)
        elseif healingRatio > 0.1 then -- Some healing (tank/hybrid)
            score = score + 5          -- Small bonus
            addon:Debug("Quality: Some healing ratio %.2f (+5)", healingRatio)
        end
        -- Pure DPS with minimal healing gets no penalty or bonus
    end

    -- Combat engagement check - did damage happen throughout the fight?
    -- This catches "afk in combat" or "combat ended but still flagged" scenarios
    if sessionData.totalDamage == 0 then
        score = score - 50 -- No damage at all = not real combat
        flags.noDamage = true
        addon:Debug("Quality: No damage (-50)")
    end

    -- Cap score bounds
    score = math.max(0, math.min(100, score))

    addon:Debug("Quality Final: %d, Flags: %s", score,
        next(flags) and table.concat(flags, ", ") or "none")

    return score, flags
end

-- Create session record from combat data
function SessionManager:CreateSessionFromCombatData(enhancedData)
    local combatData = addon.CombatData:GetRawCombatData()

    if not combatData.startTime or not combatData.endTime then
        addon:Error("Cannot create session: missing start/end time (start: %s, end: %s)", tostring(combatData.startTime), tostring(combatData.endTime))
        addon:Debug("Combat data keys: %s", table.concat(addon:GetTableKeys(combatData), ", "))
        return nil
    end

    local duration = combatData.endTime - combatData.startTime
    -- Use unified calculator for consistent calculations
    local calculator = addon.CombatData:GetCalculator()
    local avgDPS, avgHPS
    if calculator then
        avgDPS = calculator:_GetFinalDPS(false)
        avgHPS = calculator:_GetFinalHPS(false)
    else
        -- Fallback to direct calculation
        avgDPS = duration > 0 and (combatData.finalDamage / duration) or 0
        avgHPS = duration > 0 and (combatData.finalHealing / duration) or 0
    end

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
        peakDPS = calculator and calculator:GetMaxDPS() or combatData.finalMaxDPS,
        peakHPS = calculator and calculator:GetMaxHPS() or combatData.finalMaxHPS,

        -- Metadata
        location = GetRealZoneText() or GetZoneText() or GetMinimapZoneText() or "Unknown",
        playerLevel = UnitLevel("player"),
        actionCount = addon.CombatData:GetActionCount(),

        -- User management
        userMarked = nil, -- "keep", "ignore", "representative"

        -- Quality will be calculated
        qualityScore = 0,
        qualityFlags = {},

        -- Store actual timeline data
        timelineData = {},

        -- ENHANCED DATA - Store the enhanced data directly
        enhancedData = enhancedData
    }

    -- Get timeline data from TimelineTracker
    if addon.TimelineTracker then
        sessionData.timelineData = addon.TimelineTracker:GetTimelineForSession(duration, enhancedData)
    end

    -- Calculate quality and content type
    sessionData.qualityScore, sessionData.qualityFlags = CalculateQualityScore(sessionData)

    if addon.ContentDetection then
        sessionData.contentType = addon.ContentDetection:DetectContentType(sessionData)
        sessionData.detectionMethod = addon.ContentDetection:GetDetectionMethod()
    else
        sessionData.contentType = "normal"
        sessionData.detectionMethod = "none"
    end

    -- Debug enhanced data info
    local enhancedInfo = ""
    if enhancedData then
        local participants = 0
        local cooldowns = 0
        local deaths = 0

        if enhancedData.participants then
            for _ in pairs(enhancedData.participants) do
                participants = participants + 1
            end
        end
        if enhancedData.cooldownUsage then
            cooldowns = #enhancedData.cooldownUsage
        end
        if enhancedData.deaths then
            deaths = #enhancedData.deaths
        end

        enhancedInfo = string.format(", Enhanced: %dP/%dC/%dD", participants, cooldowns, deaths)
    else
        enhancedInfo = ", Enhanced: NO DATA"
    end

    addon:Debug(
        "Session created: %s, Quality: %d, Duration: %.1fs, DPS: %.0f, Type: %s, Timeline points: %d%s",
        sessionData.sessionId, sessionData.qualityScore, sessionData.duration, sessionData.avgDPS,
        sessionData.contentType, #sessionData.timelineData, enhancedInfo)

    return sessionData
end

function SessionManager:VerifyEnhancedData(sessionId)
    local session = self:GetSession(sessionId)
    if not session then
        return false, "Session not found"
    end

    if not session.enhancedData then
        return false, "No enhanced data"
    end

    local ed = session.enhancedData
    local checks = {
        participants = ed.participants ~= nil,
        damageTaken = ed.damageTaken ~= nil,
        cooldownUsage = ed.cooldownUsage ~= nil,
        deaths = ed.deaths ~= nil,
        healingEvents = ed.healingEvents ~= nil
    }

    local participantCount = 0
    if ed.participants then
        for _ in pairs(ed.participants) do
            participantCount = participantCount + 1
        end
    end

    return true, string.format("Enhanced data OK: %d participants, %d cooldowns, %d deaths",
        participantCount,
        #(ed.cooldownUsage or {}),
        #(ed.deaths or {}))
end

-- Add session to history with limit management
function SessionManager:AddSessionToHistory(session)
    if not session then return end

    -- Add to beginning of array (most recent first)
    table.insert(sessionHistory, 1, session)

    -- Trim to limit and clean up memory-heavy data from older sessions
    while #sessionHistory > SESSION_HISTORY_LIMIT do
        table.remove(sessionHistory)
    end
    
    -- MEMORY MANAGEMENT: Clean up enhanced data from sessions older than 25 to save memory
    -- Keep basic session data but remove memory-heavy timeline and enhanced data
    for i = 26, #sessionHistory do
        local session = sessionHistory[i]
        if session then
            -- Keep essential data for scaling calculations
            session.timelineData = nil  -- Remove detailed timeline (biggest memory user)
            
            -- Reduce enhanced data to just summary info
            if session.enhancedData then
                local participantCount = 0
                if session.enhancedData.participants then
                    for _ in pairs(session.enhancedData.participants) do
                        participantCount = participantCount + 1
                    end
                end
                
                -- Replace heavy enhanced data with lightweight summary
                session.enhancedData = {
                    participantCount = participantCount,
                    cooldownCount = session.enhancedData.cooldownUsage and #session.enhancedData.cooldownUsage or 0,
                    deathCount = session.enhancedData.deaths and #session.enhancedData.deaths or 0,
                    memoryReduced = true
                }
            end
        end
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

    addon:Debug("Session added to history for %s. Total sessions: %d", GetCharacterSpecKey(), #sessionHistory)
end

-- =============================================================================
-- SESSION API FUNCTIONS
-- =============================================================================

-- Get session history array
function SessionManager:GetSessionHistory()
    return sessionHistory
end

-- Get specific session by ID
function SessionManager:GetSession(sessionId)
    for _, session in ipairs(sessionHistory) do
        if session.sessionId == sessionId then
            return session
        end
    end
    return nil
end

-- Force memory cleanup (can be called manually)
function SessionManager:CleanupMemory()
    local cleaned = 0
    local before = #sessionHistory
    
    -- Remove sessions older than limit
    while #sessionHistory > SESSION_HISTORY_LIMIT do
        table.remove(sessionHistory)
        cleaned = cleaned + 1
    end
    
    -- Clean up memory-heavy data from older sessions (keep only first 25 with full data)
    for i = 26, #sessionHistory do
        local session = sessionHistory[i]
        if session and (session.timelineData or (session.enhancedData and not session.enhancedData.memoryReduced)) then
            -- Remove detailed timeline data
            session.timelineData = nil
            
            -- Reduce enhanced data to summary
            if session.enhancedData and not session.enhancedData.memoryReduced then
                local participantCount = 0
                if session.enhancedData.participants then
                    for _ in pairs(session.enhancedData.participants) do
                        participantCount = participantCount + 1
                    end
                end
                
                session.enhancedData = {
                    participantCount = participantCount,
                    cooldownCount = session.enhancedData.cooldownUsage and #session.enhancedData.cooldownUsage or 0,
                    deathCount = session.enhancedData.deaths and #session.enhancedData.deaths or 0,
                    memoryReduced = true
                }
                cleaned = cleaned + 1
            end
        end
    end
    
    addon:Debug("Memory cleanup: %d operations, %d->%d sessions", cleaned, before, #sessionHistory)
    
    return cleaned
end

-- Mark session with user preference
function SessionManager:MarkSession(sessionId, status)
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

            addon:Debug("Session %s marked as: %s", sessionId, fullStatus)
            return true
        end
    end

    return false
end

-- Delete specific session
function SessionManager:DeleteSession(sessionId)
    for i, session in ipairs(sessionHistory) do
        if session.sessionId == sessionId then
            table.remove(sessionHistory, i)

            -- Save changes per-character-spec
            if addon.db then
                if not addon.db.sessionHistoryBySpec then
                    addon.db.sessionHistoryBySpec = {}
                end
                addon.db.sessionHistoryBySpec[GetCharacterSpecKey()] = sessionHistory

                -- Also save to legacy key for backwards compatibility
                if not addon.db.sessionHistory then
                    addon.db.sessionHistory = {}
                end
                addon.db.sessionHistory[GetCharacterKey()] = sessionHistory
            end

            addon:Info("Session %s deleted", sessionId)
            
            -- Debug: Show current session count
            addon:Debug("%d sessions remaining for %s", #sessionHistory, GetCharacterSpecKey())
            
            return true
        end
    end
    return false
end

-- Clear all session history
function SessionManager:ClearHistory()
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
    addon:Debug("Session history cleared for %s", GetCharacterSpecKey())
end

-- Get quality sessions only (score >= 70 or user marked as representative)
function SessionManager:GetQualitySessions()
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
function SessionManager:GetScalingSessions(contentType, maxCount)
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

    addon:Trace("GetScalingSessions(%s): Found %d sessions, returning %d",
        contentType, #filteredSessions, #result)

    return result
end

-- Get baseline statistics for specific content type
function SessionManager:GetContentBaseline(contentType, maxSessions)
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

function SessionManager:InitializeSessionHistory()
    local characterSpecKey = GetCharacterSpecKey()
    local characterKey = GetCharacterKey() -- Legacy fallback

    sessionHistory = {}

    -- Try to load spec-specific data first
    if addon.db and addon.db.sessionHistoryBySpec and addon.db.sessionHistoryBySpec[characterSpecKey] then
        sessionHistory = addon.db.sessionHistoryBySpec[characterSpecKey]
        addon:Debug("Loaded %d sessions for %s", #sessionHistory, characterSpecKey)
        -- Fallback to legacy character-only data
    elseif addon.db and addon.db.sessionHistory and addon.db.sessionHistory[characterKey] then
        sessionHistory = addon.db.sessionHistory[characterKey]
        addon:Debug("Loaded %d legacy sessions for %s", #sessionHistory, characterKey)

        -- Migrate to new spec-specific format
        if not addon.db.sessionHistoryBySpec then
            addon.db.sessionHistoryBySpec = {}
        end
        addon.db.sessionHistoryBySpec[characterSpecKey] = sessionHistory
        addon:Debug("Migrated sessions to spec-specific storage: %s", characterSpecKey)
    else
        sessionHistory = {}
        addon:Debug("Initialized empty session history for %s", characterSpecKey)
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Initialize session manager
function SessionManager:Initialize()
    addon:Debug("SessionManager module initialized")
end

-- =============================================================================
-- DEBUG FUNCTIONS
-- =============================================================================

-- Debug session history
function SessionManager:DebugSessionHistory()
    addon:Info("=== SESSION HISTORY DEBUG ===")
    addon:Info("Total sessions: %d", #sessionHistory)
    addon:Info("History limit: %d", SESSION_HISTORY_LIMIT)

    if #sessionHistory > 0 then
        addon:Info("Recent sessions:")
        for i = 1, math.min(5, #sessionHistory) do
            local s = sessionHistory[i]
            addon:Info("[%d] %s: %.1fs, DPS:%.0f, HPS:%.0f, Q:%d, Type:%s%s",
                i, s.sessionId:sub(-8), s.duration, s.avgDPS, s.avgHPS, s.qualityScore,
                s.contentType or "unknown",
                s.userMarked and (" (" .. s.userMarked .. ")") or ""
            )
        end

        if #sessionHistory > 5 then
            addon:Info("... and %d more", #sessionHistory - 5)
        end
    else
        addon:Info("No sessions recorded")
    end

    local qualitySessions = self:GetQualitySessions()
    addon:Debug("Quality sessions: %d", #qualitySessions)

    addon:Info("=========================")
end

-- Generate test session data for development
function SessionManager:GenerateTestData()
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
            userMarked = nil,

            -- Empty timeline for test data
            timelineData = {}
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

    addon:Debug("Generated %d %s test sessions for %s", #testSessions,
        isDPS and "DPS" or (isHealer and "Healer" or (isTank and "Tank" or "Hybrid")),
        GetCharacterSpecKey())
    self:DebugSessionHistory()
end

-- =============================================================================
-- Enhanced session analysis methods
-- =============================================================================

-- Get sessions with enhanced data
function SessionManager:GetEnhancedSessions(maxCount)
    maxCount = maxCount or 10
    local enhancedSessions = {}

    for _, session in ipairs(sessionHistory) do
        if session.enhancedData then
            table.insert(enhancedSessions, session)
            if #enhancedSessions >= maxCount then
                break
            end
        end
    end

    return enhancedSessions
end

-- Get enhanced data statistics
function SessionManager:GetEnhancedDataStats()
    local stats = {
        totalSessions = #sessionHistory,
        enhancedSessions = 0,
        avgParticipants = 0,
        avgCooldowns = 0,
        avgDeaths = 0
    }

    local totalParticipants = 0
    local totalCooldowns = 0
    local totalDeaths = 0

    for _, session in ipairs(sessionHistory) do
        if session.enhancedData then
            stats.enhancedSessions = stats.enhancedSessions + 1

            -- Count participants
            if session.enhancedData.participants then
                for _ in pairs(session.enhancedData.participants) do
                    totalParticipants = totalParticipants + 1
                end
            end

            -- Count cooldowns
            if session.enhancedData.cooldownUsage then
                totalCooldowns = totalCooldowns + #session.enhancedData.cooldownUsage
            end

            -- Count deaths
            if session.enhancedData.deaths then
                totalDeaths = totalDeaths + #session.enhancedData.deaths
            end
        end
    end

    if stats.enhancedSessions > 0 then
        stats.avgParticipants = totalParticipants / stats.enhancedSessions
        stats.avgCooldowns = totalCooldowns / stats.enhancedSessions
        stats.avgDeaths = totalDeaths / stats.enhancedSessions
    end

    return stats
end

-- Check if session has enhanced data
function SessionManager:HasEnhancedData(sessionId)
    local session = self:GetSession(sessionId)
    return session and session.enhancedData ~= nil
end
