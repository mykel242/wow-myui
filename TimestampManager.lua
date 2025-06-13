-- TimestampManager.lua
-- Unified timestamp management - single source of truth for all combat timing

local addonName, addon = ...

addon.TimestampManager = {}
local TimestampManager = addon.TimestampManager

-- =============================================================================
-- UNIFIED TIMESTAMP SYSTEM
-- =============================================================================

-- Single source of truth for combat timing
local timestampData = {
    combatStartTime = nil,      -- GetTime() when combat started (baseline)
    combatEndTime = nil,        -- GetTime() when combat ended
    isActive = false,           -- Is combat currently active
    debugMode = false,          -- Enable detailed timestamp debugging
    -- Store the offset between combat log time and GetTime() when combat starts
    logTimeOffset = nil         -- (firstCombatLogTime - combatStartTime) for conversion
}

-- =============================================================================
-- CORE TIMESTAMP API
-- =============================================================================

-- Start a new combat session
function TimestampManager:StartCombat(logTimestamp)
    timestampData.combatStartTime = GetTime()
    timestampData.combatEndTime = nil
    timestampData.isActive = true
    timestampData.logTimeOffset = nil  -- Will be set when we get the first combat log event
    
    if addon.DEBUG or timestampData.debugMode then
        addon:DebugPrint(string.format("TimestampManager: Combat started - GetTime: %.3f", 
            timestampData.combatStartTime))
    end
end

-- End the current combat session
function TimestampManager:EndCombat()
    timestampData.combatEndTime = GetTime()
    timestampData.isActive = false
    
    if addon.DEBUG or timestampData.debugMode then
        local duration = self:GetCombatDuration()
        addon:DebugPrint(string.format("TimestampManager: Combat ended - Duration: %.3fs", duration))
    end
end

-- Set the log time offset (called by the first combat log event after combat starts)
function TimestampManager:SetLogTimeOffset(firstLogTimestamp)
    if not timestampData.logTimeOffset and timestampData.isActive then
        local currentGetTime = GetTime()
        timestampData.logTimeOffset = firstLogTimestamp - timestampData.combatStartTime
        
        if addon.DEBUG or timestampData.debugMode then
            addon:DebugPrint(string.format("TimestampManager: Set log offset - FirstLog: %.3f, Offset: %.3f", 
                firstLogTimestamp, timestampData.logTimeOffset))
        end
    end
end

-- Convert any timestamp to relative time since combat start
function TimestampManager:GetRelativeTime(inputTimestamp)
    if not timestampData.combatStartTime then
        return 0
    end
    
    -- Combat log timestamps are large numbers (server time), GetTime() are smaller (client uptime)
    if inputTimestamp > 1000000 then
        -- This is a combat log timestamp
        if not timestampData.logTimeOffset then
            -- This is the first combat log event - set the offset
            self:SetLogTimeOffset(inputTimestamp)
        end
        
        -- Convert using the established offset
        local relativeTime = inputTimestamp - (timestampData.combatStartTime + timestampData.logTimeOffset)
        
        if timestampData.debugMode then
            addon:DebugPrint(string.format("TimestampManager: LogTime %.3f - Offset %.3f = Relative %.3f", 
                inputTimestamp, (timestampData.combatStartTime + timestampData.logTimeOffset), relativeTime))
        end
        return relativeTime
    else
        -- This is already a GetTime() timestamp
        local relativeTime = inputTimestamp - timestampData.combatStartTime
        if timestampData.debugMode then
            addon:DebugPrint(string.format("TimestampManager: GetTime %.3f -> Relative %.3f", 
                inputTimestamp, relativeTime))
        end
        return relativeTime
    end
end

-- Get current relative time since combat start
function TimestampManager:GetCurrentRelativeTime()
    if not timestampData.combatStartTime then
        return 0
    end
    return GetTime() - timestampData.combatStartTime
end

-- Get total combat duration
function TimestampManager:GetCombatDuration()
    if not timestampData.combatStartTime then
        return 0
    end
    
    local endTime = timestampData.combatEndTime or GetTime()
    return endTime - timestampData.combatStartTime
end

-- =============================================================================
-- STATUS AND DEBUG API
-- =============================================================================

-- Check if combat is active
function TimestampManager:IsActive()
    return timestampData.isActive
end

-- Get all timestamp data for debugging
function TimestampManager:GetTimestampData()
    return {
        combatStartTime = timestampData.combatStartTime,
        combatEndTime = timestampData.combatEndTime,
        isActive = timestampData.isActive,
        logTimeOffset = timestampData.logTimeOffset,
        currentRelativeTime = self:GetCurrentRelativeTime(),
        totalDuration = self:GetCombatDuration()
    }
end

-- Enable/disable debug mode
function TimestampManager:SetDebugMode(enabled)
    timestampData.debugMode = enabled
    if enabled then
        addon:DebugPrint("TimestampManager: Debug mode enabled")
    end
end

-- Reset all timestamp data
function TimestampManager:Reset()
    timestampData.combatStartTime = nil
    timestampData.combatEndTime = nil
    timestampData.isActive = false
    timestampData.logTimeOffset = nil
    
    if addon.DEBUG then
        addon:DebugPrint("TimestampManager: Reset complete")
    end
end

-- =============================================================================
-- VALIDATION AND TESTING
-- =============================================================================

-- Validate timestamp conversion
function TimestampManager:ValidateTimestamp(inputTimestamp, expectedRange)
    local relativeTime = self:GetRelativeTime(inputTimestamp)
    local currentDuration = self:GetCombatDuration()
    
    local isValid = relativeTime >= 0 and relativeTime <= currentDuration
    
    if expectedRange then
        isValid = isValid and relativeTime >= expectedRange.min and relativeTime <= expectedRange.max
    end
    
    if timestampData.debugMode then
        addon:DebugPrint(string.format("TimestampManager: Validation - Input: %.3f, Relative: %.3f, Valid: %s", 
            inputTimestamp, relativeTime, tostring(isValid)))
    end
    
    return isValid, relativeTime
end

-- Get debug summary
function TimestampManager:GetDebugSummary()
    local data = self:GetTimestampData()
    local summary = "=== TIMESTAMP MANAGER DEBUG ==="
    summary = summary .. string.format("\nCombat Active: %s", tostring(data.isActive))
    summary = summary .. string.format("\nStart Time (GetTime): %.3f", data.combatStartTime or 0)
    summary = summary .. string.format("\nLog Time Offset: %.3f", data.logTimeOffset or 0)
    summary = summary .. string.format("\nCurrent Relative: %.3f", data.currentRelativeTime)
    summary = summary .. string.format("\nTotal Duration: %.3f", data.totalDuration)
    summary = summary .. "\n============================="
    return summary
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function TimestampManager:Initialize()
    self:Reset()
    
    if addon.DEBUG then
        addon:DebugPrint("TimestampManager: Initialized")
    end
end