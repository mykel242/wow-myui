-- CombatTracker.lua
-- Main combat tracking coordination module

local addonName, addon = ...

-- Combat tracker module
addon.CombatTracker = {}
local CombatTracker = addon.CombatTracker

-- =============================================================================
-- MAIN API FUNCTIONS
-- =============================================================================

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
-- COMBAT TRACKING API (delegates to CombatData module)
-- =============================================================================

-- Calculate DPS (rolling during combat, final after)
function CombatTracker:GetDPS()
    return addon.CombatData:GetDPS()
end

-- Calculate HPS (rolling during combat, final after)
function CombatTracker:GetHPS()
    return addon.CombatData:GetHPS()
end

-- Get displayed DPS for meters (rolling during combat, final after)
function CombatTracker:GetDisplayDPS()
    return addon.CombatData:GetDisplayDPS()
end

-- Get displayed HPS for meters (rolling during combat, final after)
function CombatTracker:GetDisplayHPS()
    return addon.CombatData:GetDisplayHPS()
end

-- Get total damage
function CombatTracker:GetTotalDamage()
    return addon.CombatData:GetTotalDamage()
end

-- Get total healing
function CombatTracker:GetTotalHealing()
    return addon.CombatData:GetTotalHealing()
end

-- Get total overheal
function CombatTracker:GetTotalOverheal()
    return addon.CombatData:GetTotalOverheal()
end

-- Get total absorb shields
function CombatTracker:GetTotalAbsorb()
    return addon.CombatData:GetTotalAbsorb()
end

-- Get combat duration
function CombatTracker:GetCombatTime()
    return addon.CombatData:GetCombatTime()
end

-- Get max DPS recorded
function CombatTracker:GetMaxDPS()
    return addon.CombatData:GetMaxDPS()
end

-- Get max HPS recorded
function CombatTracker:GetMaxHPS()
    return addon.CombatData:GetMaxHPS()
end

-- Check if in combat
function CombatTracker:IsInCombat()
    return addon.CombatData:IsInCombat()
end

-- Get the final peak values from the last completed combat
function CombatTracker:GetLastCombatMaxDPS()
    return addon.CombatData:GetLastCombatMaxDPS()
end

function CombatTracker:GetLastCombatMaxHPS()
    return addon.CombatData:GetLastCombatMaxHPS()
end

-- =============================================================================
-- SESSION MANAGEMENT API (delegates to SessionManager module)
-- =============================================================================

-- Get session history array
function CombatTracker:GetSessionHistory()
    return addon.SessionManager:GetSessionHistory()
end

-- Get specific session by ID
function CombatTracker:GetSession(sessionId)
    return addon.SessionManager:GetSession(sessionId)
end

-- Mark session with user preference
function CombatTracker:MarkSession(sessionId, status)
    return addon.SessionManager:MarkSession(sessionId, status)
end

-- Delete specific session
function CombatTracker:DeleteSession(sessionId)
    return addon.SessionManager:DeleteSession(sessionId)
end

-- Clear all session history
function CombatTracker:ClearHistory()
    return addon.SessionManager:ClearHistory()
end

-- Get quality sessions only
function CombatTracker:GetQualitySessions()
    return addon.SessionManager:GetQualitySessions()
end

-- Get sessions for specific content type
function CombatTracker:GetScalingSessions(contentType, maxCount)
    return addon.SessionManager:GetScalingSessions(contentType, maxCount)
end

-- Get baseline statistics for specific content type
function CombatTracker:GetContentBaseline(contentType, maxSessions)
    return addon.SessionManager:GetContentBaseline(contentType, maxSessions)
end

-- =============================================================================
-- CONTENT DETECTION API (delegates to ContentDetection module)
-- =============================================================================

-- Enhanced content detection
function CombatTracker:DetectContentType(sessionData)
    return addon.ContentDetection:DetectContentType(sessionData)
end

-- Get baseline stats from recent normal content
function CombatTracker:GetNormalContentBaseline()
    return addon.ContentDetection:GetNormalContentBaseline()
end

-- Set manual content type override
function CombatTracker:SetContentOverride(contentType, durationHours)
    return addon.ContentDetection:SetContentOverride(contentType, durationHours)
end

-- Get current content type
function CombatTracker:GetCurrentContentType()
    return addon.ContentDetection:GetCurrentContentType()
end

-- =============================================================================
-- TIMELINE/ROLLING DATA API (delegates to TimelineTracker module)
-- =============================================================================

function CombatTracker:GetRollingDPS()
    return addon.TimelineTracker:GetRollingDPS()
end

function CombatTracker:GetRollingHPS()
    return addon.TimelineTracker:GetRollingHPS()
end

function CombatTracker:GetRollingEffectiveHPS()
    return addon.TimelineTracker:GetRollingEffectiveHPS()
end

function CombatTracker:GetRollingOverhealPercent()
    return addon.TimelineTracker:GetRollingOverhealPercent()
end

function CombatTracker:GetRollingAbsorbRate()
    return addon.TimelineTracker:GetRollingAbsorbRate()
end

function CombatTracker:GetTimelineData()
    return addon.TimelineTracker:GetTimelineData()
end

function CombatTracker:GetRollingData()
    return addon.TimelineTracker:GetRollingData()
end

-- =============================================================================
-- RESET FUNCTIONS (delegates to CombatData module)
-- =============================================================================

-- Reset display stats (for refresh button)
function CombatTracker:ResetDisplayStats()
    return addon.CombatData:ResetDisplayStats()
end

-- Reset only DPS-related stats
function CombatTracker:ResetDPSStats()
    return addon.CombatData:ResetDPSStats()
end

-- Reset only HPS-related stats
function CombatTracker:ResetHPSStats()
    return addon.CombatData:ResetHPSStats()
end

-- =============================================================================
-- SPEC CHANGE HANDLING
-- =============================================================================

-- Track current spec for change detection
local currentSpec = nil

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

            addon:DebugPrint(string.format("Spec changed from %s to %s - reloading session data", oldSpecName, newSpecName))
        end

        -- Reload session history for new spec
        addon.SessionManager:InitializeSessionHistory()

        -- Reset meter scaling to let it adapt to new spec
        if addon.dpsPixelMeter then
            addon.dpsPixelMeter:ResetMaxValue()
        end
        if addon.hpsPixelMeter then
            addon.hpsPixelMeter:ResetMaxValue()
        end

        addon:DebugPrint("Switched to new spec - session data and meter scaling updated")
    end

    currentSpec = newSpec
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Initialize combat tracker and all sub-modules
function CombatTracker:Initialize()
    -- Initialize all sub-modules first
    if addon.CombatData then
        addon.CombatData:Initialize()
    end

    if addon.TimelineTracker then
        addon.TimelineTracker:Initialize()
    end

    if addon.ContentDetection then
        addon.ContentDetection:Initialize()
    end

    if addon.SessionManager then
        addon.SessionManager:Initialize()
        addon.SessionManager:InitializeSessionHistory()
    end

    -- Spec change check timer (check every 2 seconds)
    self.specCheckTimer = C_Timer.NewTicker(2.0, function()
        CombatTracker:CheckSpecChange()
    end)

    if addon.DEBUG then
    end
end

-- =============================================================================
-- DEBUG FUNCTIONS (delegates to SessionManager)
-- =============================================================================

-- Debug session history
function CombatTracker:DebugSessionHistory()
    return addon.SessionManager:DebugSessionHistory()
end

-- Generate test session data
function CombatTracker:GenerateTestData()
    return addon.SessionManager:GenerateTestData()
end

-- Debug peak tracking values
function CombatTracker:DebugPeakTracking()
    return addon.CombatData:DebugPeakTracking()
end

-- Debug content scaling analysis
function CombatTracker:DebugContentScaling()
    return addon.ContentDetection:DebugContentScaling()
end
