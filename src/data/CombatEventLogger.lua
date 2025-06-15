-- CombatEventLogger.lua
-- Core combat detection and raw logging system (single source of truth)

local addonName, addon = ...

-- Combat Event Logger module
addon.CombatEventLogger = {}
local CombatEventLogger = addon.CombatEventLogger

-- State tracking
local isInitialized = false
local isTracking = false
local currentCombatId = nil
local combatStartTime = nil
local lastEventTime = nil
local eventBuffer = {}

-- Configuration
local CONFIG = {
    COMBAT_TIMEOUT = 3.0, -- Seconds after last event to end combat
    MAX_BUFFER_SIZE = 5000, -- Maximum events per combat session
    DEBUG_EVENTS = false, -- Extra verbose event debugging
}

-- Event filtering - only track meaningful combat events
local TRACKED_EVENTS = {
    ["SPELL_DAMAGE"] = true,
    ["SPELL_PERIODIC_DAMAGE"] = true,
    ["SPELL_HEAL"] = true,
    ["SPELL_PERIODIC_HEAL"] = true,
    ["SWING_DAMAGE"] = true,
    ["RANGE_DAMAGE"] = true,
    ["SPELL_ABSORBED"] = true,
    ["UNIT_DIED"] = true,
    ["PARTY_KILL"] = true,
    ["SPELL_CAST_SUCCESS"] = true,
    ["SPELL_AURA_APPLIED"] = true,
    ["SPELL_AURA_REMOVED"] = true,
}

-- Initialize the combat event logger
function CombatEventLogger:Initialize()
    if isInitialized then
        return
    end
    
    -- Create event frame
    self.frame = CreateFrame("Frame", addonName .. "CombatEventLogger")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering combat
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving combat
    self.frame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)
    
    -- Initialize combat tracking state
    currentCombatId = nil
    combatStartTime = nil
    isTracking = false
    eventBuffer = {}
    
    isInitialized = true
    
    if addon.DEBUG then
        print("CombatEventLogger initialized - ready for combat detection")
    end
end

-- Main event handler
function CombatEventLogger:OnEvent(event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:ProcessCombatLogEvent(CombatLogGetCurrentEventInfo())
    elseif event == "PLAYER_REGEN_DISABLED" then
        self:OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:OnCombatEnd()
    end
end

-- Process individual combat log events
function CombatEventLogger:ProcessCombatLogEvent(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, ...)
    -- Only process tracked events
    if not TRACKED_EVENTS[subevent] then
        return
    end
    
    -- Ensure we have a combat session
    if not isTracking then
        self:StartCombatSession()
    end
    
    -- Update last event time for timeout detection
    lastEventTime = GetTime()
    
    -- Create event record
    local eventRecord = {
        timestamp = timestamp,
        realTime = GetTime(),
        subevent = subevent,
        sourceGUID = sourceGUID,
        sourceName = sourceName,
        sourceFlags = sourceFlags,
        destGUID = destGUID,
        destName = destName,
        destFlags = destFlags,
        args = {...} -- Store all additional arguments
    }
    
    -- Enhance with GUID name resolution
    if addon.GUIDResolver then
        eventRecord = addon.GUIDResolver:ResolveCombatEvent(eventRecord)
    end
    
    -- Add to buffer (with size limit)
    if #eventBuffer >= CONFIG.MAX_BUFFER_SIZE then
        -- Remove oldest event to make room
        table.remove(eventBuffer, 1)
    end
    table.insert(eventBuffer, eventRecord)
    
    -- Debug output for development
    if CONFIG.DEBUG_EVENTS and addon.DEBUG then
        print(string.format("[%s] %s: %s -> %s", 
            subevent, 
            sourceName or "Unknown", 
            destName or "Unknown",
            self:FormatEventArgs(subevent, ...)))
    end
end

-- Start a new combat session
function CombatEventLogger:StartCombatSession()
    if isTracking then
        return -- Already tracking
    end
    
    local now = GetTime()
    currentCombatId = self:GenerateCombatId()
    combatStartTime = now
    lastEventTime = now
    isTracking = true
    eventBuffer = {}
    
    if addon.DEBUG then
        print(string.format("Combat session started: %s", currentCombatId))
    end
    
    -- Start combat timeout timer
    self:StartCombatTimeoutTimer()
end

-- End current combat session
function CombatEventLogger:EndCombatSession()
    if not isTracking then
        return
    end
    
    local duration = GetTime() - combatStartTime
    local eventCount = #eventBuffer
    
    if addon.DEBUG then
        print(string.format("Combat session ended: %s (%.1fs, %d events)", 
            currentCombatId, duration, eventCount))
    end
    
    -- Prepare session data with name mapping
    local sessionData = {
        id = currentCombatId,
        startTime = combatStartTime,
        endTime = GetTime(),
        duration = duration,
        eventCount = eventCount,
        events = eventBuffer
    }
    
    -- Add comprehensive name mapping for narrative reconstruction
    if addon.GUIDResolver then
        sessionData.nameMapping = addon.GUIDResolver:GetSessionNameMapping(eventBuffer)
    end
    
    -- Store completed session
    self:StoreCombatSession(sessionData)
    
    -- Reset state
    isTracking = false
    currentCombatId = nil
    combatStartTime = nil
    lastEventTime = nil
    eventBuffer = {}
end

-- Handle WoW combat state changes
function CombatEventLogger:OnCombatStart()
    if addon.DEBUG then
        print("Player entered combat (PLAYER_REGEN_DISABLED)")
    end
    self:StartCombatSession()
end

function CombatEventLogger:OnCombatEnd()
    if addon.DEBUG then
        print("Player left combat (PLAYER_REGEN_ENABLED)")
    end
    -- Don't end immediately - let timeout handle it in case of brief gaps
end

-- Combat timeout detection
function CombatEventLogger:StartCombatTimeoutTimer()
    if self.timeoutTimer then
        self.timeoutTimer:Cancel()
    end
    
    self.timeoutTimer = C_Timer.NewTicker(0.5, function()
        if isTracking and lastEventTime then
            local timeSinceLastEvent = GetTime() - lastEventTime
            if timeSinceLastEvent >= CONFIG.COMBAT_TIMEOUT then
                self:EndCombatSession()
                if self.timeoutTimer then
                    self.timeoutTimer:Cancel()
                    self.timeoutTimer = nil
                end
            end
        end
    end)
end

-- Generate unique combat session ID using realm-character-counter format
function CombatEventLogger:GenerateCombatId()
    local realm = GetRealmName() or "Unknown"
    local character = UnitName("player") or "Unknown"
    
    -- Clean realm and character names (remove spaces, special chars)
    realm = realm:gsub("[%s%-]", ""):lower()
    character = character:gsub("[%s%-]", ""):lower()
    
    -- Get or initialize session counter for this character
    if not MyUIDB then
        MyUIDB = {}
    end
    if not MyUIDB.sessionCounters then
        MyUIDB.sessionCounters = {}
    end
    
    local characterKey = realm .. "-" .. character
    local counter = (MyUIDB.sessionCounters[characterKey] or 0) + 1
    MyUIDB.sessionCounters[characterKey] = counter
    
    return string.format("%s-%s-%03d", realm, character, counter)
end

-- Format event arguments for debugging
function CombatEventLogger:FormatEventArgs(subevent, ...)
    local args = {...}
    if subevent:match("DAMAGE") then
        return string.format("Amount: %s", tostring(args[1] or "?"))
    elseif subevent:match("HEAL") then
        return string.format("Amount: %s", tostring(args[1] or "?"))
    elseif subevent == "SPELL_CAST_SUCCESS" then
        return string.format("Spell: %s", tostring(args[2] or "?"))
    else
        return table.concat(args, ", ")
    end
end

-- Store completed combat session
function CombatEventLogger:StoreCombatSession(sessionData)
    if addon.StorageManager then
        addon.StorageManager:StoreCombatSession(sessionData)
    else
        if addon.DEBUG then
            print(string.format("StorageManager not available - session lost: %s (%d events)", 
                sessionData.id, sessionData.eventCount))
        end
    end
end

-- Public API methods
function CombatEventLogger:IsTracking()
    return isTracking
end

function CombatEventLogger:GetCurrentCombatId()
    return currentCombatId
end

function CombatEventLogger:GetEventCount()
    return #eventBuffer
end

function CombatEventLogger:GetCurrentEvents()
    -- Return copy to prevent modification
    local events = {}
    for i, event in ipairs(eventBuffer) do
        events[i] = event
    end
    return events
end

function CombatEventLogger:GetStatus()
    return {
        isInitialized = isInitialized,
        isTracking = isTracking,
        currentCombatId = currentCombatId,
        eventCount = #eventBuffer,
        combatDuration = combatStartTime and (GetTime() - combatStartTime) or 0
    }
end

-- Debug summary for slash commands
function CombatEventLogger:GetDebugSummary()
    local status = self:GetStatus()
    return string.format(
        "CombatEventLogger Status:\n" ..
        "  Initialized: %s\n" ..
        "  Tracking: %s\n" ..
        "  Combat ID: %s\n" ..
        "  Event Count: %d\n" ..
        "  Duration: %.1fs",
        tostring(status.isInitialized),
        tostring(status.isTracking),
        status.currentCombatId or "None",
        status.eventCount,
        status.combatDuration
    )
end