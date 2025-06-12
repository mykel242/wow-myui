-- ContentDetection.lua
-- Content type detection system

local addonName, addon = ...

-- Content detection module
addon.ContentDetection = {}
local ContentDetection = addon.ContentDetection

-- =============================================================================
-- DATA STRUCTURES
-- =============================================================================

-- Content detection system
local contentDetection = {
    manualOverride = nil, -- "scaled", "normal", nil
    overrideExpiry = 0,
    baselineStats = { avgDPS = 0, avgHPS = 0, sampleCount = 0 }
}

-- =============================================================================
-- CONTENT DETECTION SYSTEM
-- =============================================================================

-- Enhanced content detection with better session analysis
function ContentDetection:DetectContentType(sessionData)
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
function ContentDetection:GetNormalContentBaseline()
    return self:GetContentBaseline("normal", 10)
end

-- Get baseline statistics for specific content type
function ContentDetection:GetContentBaseline(contentType, maxSessions)
    if addon.SessionManager then
        return addon.SessionManager:GetContentBaseline(contentType, maxSessions)
    else
        -- Fallback if SessionManager not available
        return {
            avgDPS = 0,
            avgHPS = 0,
            peakDPS = 0,
            peakHPS = 0,
            sampleCount = 0,
            contentType = contentType
        }
    end
end

-- Set manual content type override
function ContentDetection:SetContentOverride(contentType, durationHours)
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
function ContentDetection:GetCurrentContentType()
    if contentDetection.manualOverride and GetTime() < contentDetection.overrideExpiry then
        return contentDetection.manualOverride
    end

    -- Default to normal for meter scaling
    return "normal"
end

-- Get detection method for session records
function ContentDetection:GetDetectionMethod()
    if contentDetection.manualOverride and GetTime() < contentDetection.overrideExpiry then
        return "manual"
    else
        return "auto"
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Initialize content detection module
function ContentDetection:Initialize()
    if addon.DEBUG then
        print("ContentDetection module initialized")
    end
end

-- =============================================================================
-- DEBUG FUNCTIONS
-- =============================================================================

-- Debug method for content scaling analysis
function ContentDetection:DebugContentScaling()
    print("=== CONTENT SCALING DEBUG ===")

    local currentType = self:GetCurrentContentType()
    print(string.format("Current content type: %s", currentType))

    -- Show baseline for each content type
    for _, contentType in ipairs({ "normal", "scaled" }) do
        local baseline = self:GetContentBaseline(contentType, 10)
        local sessions = {}

        if addon.SessionManager then
            sessions = addon.SessionManager:GetScalingSessions(contentType, 10)
        end

        print(string.format("\n%s Content:", string.upper(contentType)))
        print(string.format("  Sessions: %d (baseline from %d)", #sessions, baseline.sampleCount))
        print(string.format("  Avg DPS: %s", addon.CombatTracker:FormatNumber(baseline.avgDPS)))
        print(string.format("  Avg HPS: %s", addon.CombatTracker:FormatNumber(baseline.avgHPS)))
        print(string.format("  Peak DPS: %s", addon.CombatTracker:FormatNumber(baseline.peakDPS)))
        print(string.format("  Peak HPS: %s", addon.CombatTracker:FormatNumber(baseline.peakHPS)))

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
    if addon.SessionManager then
        local sessionHistory = addon.SessionManager:GetSessionHistory()
        if #sessionHistory > 0 then
            local lastSession = sessionHistory[1]
            local normalBaseline = self:GetContentBaseline("normal", 20)

            if normalBaseline.sampleCount > 0 then
                local dpsRatio = normalBaseline.avgDPS > 0 and (lastSession.avgDPS / normalBaseline.avgDPS) or 1
                local hpsRatio = normalBaseline.avgHPS > 0 and (lastSession.avgHPS / normalBaseline.avgHPS) or 1

                print(string.format("\nLast Session Detection:"))
                print(string.format("  DPS Ratio: %.2f (%.0f / %.0f)", dpsRatio, lastSession.avgDPS,
                    normalBaseline.avgDPS))
                print(string.format("  HPS Ratio: %.2f (%.0f / %.0f)", hpsRatio, lastSession.avgHPS,
                    normalBaseline.avgHPS))
                print(string.format("  Detected as: %s", lastSession.contentType))
            end
        end
    end

    print("========================")
end
