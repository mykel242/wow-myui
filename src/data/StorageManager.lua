-- StorageManager.lua
-- Memory-efficient storage system for combat sessions

local addonName, addon = ...

-- Storage Manager module
addon.StorageManager = {}
local StorageManager = addon.StorageManager

-- State tracking
local isInitialized = false
local sessionStorage = {}
local memoryStats = {}

-- Get current storage configuration from settings
local function GetStorageConfig()
    local settings = addon.SettingsWindow and addon.SettingsWindow:GetCurrentSettings() or {}
    return {
        MAX_SESSIONS = settings.maxSessions or 50,
        MAX_SESSION_AGE_DAYS = settings.sessionAgeDays or 7,
        MAX_MEMORY_MB = settings.maxMemoryMB or 10,
        COMPRESSION_ENABLED = settings.compressionEnabled ~= false, -- Default true
        WARNING_THRESHOLD = 0.8 -- Warn at 80% of limits
    }
end

-- Saved variable for persistent storage
local STORAGE_KEY = "MyUI_CombatSessions"

-- Initialize the storage manager
function StorageManager:Initialize()
    if isInitialized then
        return
    end
    
    -- Initialize storage from saved variables
    self:LoadFromSavedVariables()
    
    -- Initialize memory stats
    memoryStats = {
        sessionsStored = #sessionStorage,
        totalMemoryKB = 0,
        lastCleanup = GetTime(),
        compressionRatio = 0
    }
    
    isInitialized = true
    
    -- Check storage limits on initialization (delayed to allow settings to load)
    C_Timer.After(2.0, function()
        self:CheckStorageLimits()
    end)
    
    addon:Debug("StorageManager initialized - %d sessions loaded", #sessionStorage)
end

-- Store a completed combat session
function StorageManager:StoreCombatSession(sessionData)
    if not isInitialized then
        self:Initialize()
    end
    
    -- Add metadata and timestamps
    sessionData.storedAt = GetTime()
    sessionData.serverTime = GetServerTime()
    
    -- Get context metadata if available
    if addon.MetadataCollector then
        sessionData.metadata = addon.MetadataCollector:GetMetadataForCombat(sessionData.id)
    end
    
    -- Compress event data if enabled
    local config = GetStorageConfig()
    if config.COMPRESSION_ENABLED then
        sessionData.events = self:CompressEvents(sessionData.events)
        sessionData.compressed = true
    end
    
    -- Add to storage
    table.insert(sessionStorage, sessionData)
    
    -- Update memory stats
    self:UpdateMemoryStats()
    
    -- Check for storage warnings and cleanup if needed
    self:CheckStorageLimits()
    
    -- Auto-save after storing new session
    self:SaveToSavedVariables()
    
    addon:Debug("Combat session stored: %s (%d events, %.1fKB)", 
        sessionData.id, 
        sessionData.eventCount,
        self:EstimateSessionSizeKB(sessionData))
    
    -- Notify Session Browser to refresh if it's open
    if addon.SessionBrowser and addon.SessionBrowser:IsShown() then
        addon.SessionBrowser:RefreshSessionList()
    end
end

-- Compress event data for storage
function StorageManager:CompressEvents(events)
    if not events or #events == 0 then
        return {}
    end
    
    local compressed = {}
    local eventTypeMap = {} -- Map event types to short codes
    local nextTypeId = 1
    
    for _, event in ipairs(events) do
        -- Map event type to short ID
        local eventType = event.subevent
        if not eventTypeMap[eventType] then
            eventTypeMap[eventType] = nextTypeId
            nextTypeId = nextTypeId + 1
        end
        
        -- Create compressed event record
        local compressedEvent = {
            t = math.floor(((event.time or event.realTime) or 0) * 1000), -- Timestamp in ms (handle both formats)
            e = eventTypeMap[eventType], -- Event type ID
            s = event.sourceGUID, -- Source GUID
            d = event.destGUID,   -- Dest GUID
            a = event.args and #event.args > 0 and event.args or nil -- Args only if present
        }
        
        table.insert(compressed, compressedEvent)
    end
    
    return {
        events = compressed,
        typeMap = eventTypeMap,
        originalCount = #events
    }
end

-- Decompress event data for reading
function StorageManager:DecompressEvents(compressedData)
    if not compressedData or not compressedData.events then
        return {}
    end
    
    local events = {}
    local reverseTypeMap = {} -- Reverse the type mapping
    
    for eventType, id in pairs(compressedData.typeMap) do
        reverseTypeMap[id] = eventType
    end
    
    for _, compressed in ipairs(compressedData.events) do
        local event = {
            realTime = compressed.t and (compressed.t / 1000) or 0,
            subevent = reverseTypeMap[compressed.e] or "UNKNOWN",
            sourceGUID = compressed.s,
            destGUID = compressed.d,
            args = compressed.a or {}
        }
        
        table.insert(events, event)
    end
    
    return events
end

-- Estimate memory usage of a session in KB
function StorageManager:EstimateSessionSizeKB(sessionData)
    -- Rough estimation based on data structure
    local baseSize = 1 -- Base session metadata
    local eventSize = sessionData.eventCount * 0.1 -- ~100 bytes per event
    local metadataSize = sessionData.metadata and 2 or 0 -- ~2KB for metadata
    
    return baseSize + eventSize + metadataSize
end

-- Update memory statistics
function StorageManager:UpdateMemoryStats()
    local totalSizeKB = 0
    local compressedEvents = 0
    local originalEvents = 0
    
    for _, session in ipairs(sessionStorage) do
        totalSizeKB = totalSizeKB + self:EstimateSessionSizeKB(session)
        
        if session.compressed and session.events and session.events.originalCount then
            compressedEvents = compressedEvents + #session.events.events
            originalEvents = originalEvents + session.events.originalCount
        end
    end
    
    memoryStats.sessionsStored = #sessionStorage
    memoryStats.totalMemoryKB = totalSizeKB
    memoryStats.compressionRatio = originalEvents > 0 and (compressedEvents / originalEvents) or 1
end

-- Check storage limits and warn/cleanup as needed
function StorageManager:CheckStorageLimits(testMode)
    local config = GetStorageConfig()
    
    -- In test mode, temporarily lower limits to force warnings
    if testMode then
        config.MAX_SESSIONS = math.max(1, #sessionStorage - 5) -- Force close to limit
        config.MAX_MEMORY_MB = math.max(0.1, (memoryStats.totalMemoryKB / 1024) + 0.1) -- Force close to limit
        config.WARNING_THRESHOLD = 0.5 -- Lower threshold for easier testing
    end
    
    self:UpdateMemoryStats()
    
    local warnings = {}
    local cleanupNeeded = false
    
    -- Check session count limit
    local sessionCount = #sessionStorage
    local maxSessions = config.MAX_SESSIONS
    local sessionWarningThreshold = math.floor(maxSessions * config.WARNING_THRESHOLD)
    
    if sessionCount >= maxSessions then
        cleanupNeeded = true
    elseif sessionCount >= sessionWarningThreshold then
        table.insert(warnings, string.format("Session count: %d/%d (%.0f%%)", 
            sessionCount, maxSessions, (sessionCount / maxSessions) * 100))
    end
    
    -- Check memory limit  
    local memoryMB = memoryStats.totalMemoryKB / 1024
    local maxMemoryMB = config.MAX_MEMORY_MB
    local memoryWarningThreshold = maxMemoryMB * config.WARNING_THRESHOLD
    
    if memoryMB >= maxMemoryMB then
        cleanupNeeded = true
    elseif memoryMB >= memoryWarningThreshold then
        table.insert(warnings, string.format("Memory usage: %.1f/%.1f MB (%.0f%%)", 
            memoryMB, maxMemoryMB, (memoryMB / maxMemoryMB) * 100))
    end
    
    -- Check age-based cleanup need
    local cutoffTime = GetServerTime() - (config.MAX_SESSION_AGE_DAYS * 24 * 60 * 60)
    local expiredCount = 0
    for _, session in ipairs(sessionStorage) do
        if session.serverTime and session.serverTime < cutoffTime then
            expiredCount = expiredCount + 1
        end
    end
    
    if expiredCount > 0 then
        table.insert(warnings, string.format("%d sessions older than %d days", 
            expiredCount, config.MAX_SESSION_AGE_DAYS))
        cleanupNeeded = true
    end
    
    -- Show warnings if any
    if #warnings > 0 then
        self:ShowStorageWarning(warnings, cleanupNeeded)
    end
    
    -- Perform cleanup if over limits (not just warnings)
    if cleanupNeeded then
        self:PerformMemoryCleanup()
    end
end

-- Perform memory cleanup (when limits are exceeded)
function StorageManager:PerformMemoryCleanup()
    local config = GetStorageConfig()
    local cleaned = false
    local cleanupLog = {}
    
    -- Remove sessions exceeding max count (oldest first)
    local initialCount = #sessionStorage
    while #sessionStorage > config.MAX_SESSIONS do
        table.remove(sessionStorage, 1)
        cleaned = true
    end
    if initialCount > #sessionStorage then
        table.insert(cleanupLog, string.format("Removed %d sessions over limit", initialCount - #sessionStorage))
    end
    
    -- Remove sessions older than max age
    local cutoffTime = GetServerTime() - (config.MAX_SESSION_AGE_DAYS * 24 * 60 * 60)
    local expiredRemoved = 0
    local i = 1
    while i <= #sessionStorage do
        local session = sessionStorage[i]
        if session.serverTime and session.serverTime < cutoffTime then
            table.remove(sessionStorage, i)
            expiredRemoved = expiredRemoved + 1
            cleaned = true
        else
            i = i + 1
        end
    end
    if expiredRemoved > 0 then
        table.insert(cleanupLog, string.format("Removed %d expired sessions", expiredRemoved))
    end
    
    -- Memory-based cleanup if still over limit
    self:UpdateMemoryStats()
    if memoryStats.totalMemoryKB > (config.MAX_MEMORY_MB * 1024) then
        local beforeCount = #sessionStorage
        -- Remove oldest 25% of sessions
        local removeCount = math.floor(#sessionStorage * 0.25)
        for i = 1, removeCount do
            table.remove(sessionStorage, 1)
        end
        cleaned = true
        table.insert(cleanupLog, string.format("Removed %d sessions for memory limit", removeCount))
    end
    
    if cleaned then
        self:UpdateMemoryStats()
        if #cleanupLog > 0 then
            addon:Info("Storage cleanup performed:")
            for _, msg in ipairs(cleanupLog) do
                addon:Info("  " .. msg)
            end
            addon:Info("  Final: %d sessions, %.1fKB", 
                memoryStats.sessionsStored, memoryStats.totalMemoryKB)
        end
    end
end

-- Show storage warning to user
function StorageManager:ShowStorageWarning(warnings, cleanupNeeded)
    local message = "Storage Usage Warning:\n\n"
    for _, warning in ipairs(warnings) do
        message = message .. "• " .. warning .. "\n"
    end
    
    if cleanupNeeded then
        message = message .. "\nAutomatic cleanup will occur to stay within limits."
    else
        message = message .. "\nConsider exporting important sessions or increasing storage limits in Settings."
    end
    
    message = message .. "\n\nOpen Session Browser to export sessions?\nOpen Settings to adjust limits?"
    
    -- Create warning dialog (escape % characters to prevent format errors)
    StaticPopupDialogs["MYUI_STORAGE_WARNING"] = {
        text = message:gsub("%%", "%%%%"),
        button1 = "Session Browser",
        button2 = "Settings", 
        button3 = "Dismiss",
        OnAccept = function()
            if addon.SessionBrowser then
                addon.SessionBrowser:Show()
            end
        end,
        OnCancel = function()
            if addon.SettingsWindow then
                addon.SettingsWindow:Show()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopup_Show("MYUI_STORAGE_WARNING")
end

-- Load sessions from saved variables
function StorageManager:LoadFromSavedVariables()
    if MyUIDB and MyUIDB[STORAGE_KEY] then
        sessionStorage = MyUIDB[STORAGE_KEY]
        addon:Debug("Loaded %d combat sessions from saved variables", #sessionStorage)
    else
        sessionStorage = {}
    end
end

-- Save sessions to saved variables
function StorageManager:SaveToSavedVariables()
    if not MyUIDB then
        MyUIDB = {}
    end
    
    MyUIDB[STORAGE_KEY] = sessionStorage
    
    -- Note: Silent save - no chat spam
end

-- Public API methods
function StorageManager:GetAllSessions()
    -- Return copy to prevent modification
    local sessions = {}
    for i, session in ipairs(sessionStorage) do
        sessions[i] = session
    end
    return sessions
end

function StorageManager:GetSession(sessionId)
    for _, session in ipairs(sessionStorage) do
        if session.id == sessionId then
            -- Return copy with decompressed events if needed
            local sessionCopy = {}
            for k, v in pairs(session) do
                sessionCopy[k] = v
            end
            
            if session.compressed and session.events then
                sessionCopy.events = self:DecompressEvents(session.events)
                sessionCopy.compressed = false
            end
            
            return sessionCopy
        end
    end
    return nil
end

function StorageManager:GetRecentSessions(count)
    count = count or 10
    local recent = {}
    local startIndex = math.max(1, #sessionStorage - count + 1)
    
    for i = startIndex, #sessionStorage do
        table.insert(recent, sessionStorage[i])
    end
    
    return recent
end

function StorageManager:DeleteSession(sessionId)
    for i, session in ipairs(sessionStorage) do
        if session.id == sessionId then
            table.remove(sessionStorage, i)
            self:UpdateMemoryStats()
            self:SaveToSavedVariables() -- Auto-save after deletion
            return true
        end
    end
    return false
end

function StorageManager:ClearAllSessions()
    sessionStorage = {}
    memoryStats.sessionsStored = 0
    memoryStats.totalMemoryKB = 0
    self:SaveToSavedVariables() -- Auto-save after clearing
    
    addon:Debug("All combat sessions cleared")
end

function StorageManager:GetMemoryStats()
    local config = GetStorageConfig()
    return {
        sessionsStored = memoryStats.sessionsStored,
        totalMemoryKB = memoryStats.totalMemoryKB,
        totalMemoryMB = memoryStats.totalMemoryKB / 1024,
        compressionRatio = memoryStats.compressionRatio,
        maxSessions = config.MAX_SESSIONS,
        maxMemoryMB = config.MAX_MEMORY_MB,
        maxSessionAgeDays = config.MAX_SESSION_AGE_DAYS,
        compressionEnabled = config.COMPRESSION_ENABLED
    }
end

function StorageManager:GetStatus()
    local stats = self:GetMemoryStats()
    return {
        isInitialized = isInitialized,
        sessionsStored = stats.sessionsStored,
        memoryUsageMB = stats.totalMemoryMB,
        compressionEnabled = stats.compressionEnabled,
        lastCleanup = memoryStats.lastCleanup
    }
end

-- Debug summary for slash commands
function StorageManager:GetDebugSummary()
    local status = self:GetStatus()
    local stats = self:GetMemoryStats()
    
    return string.format(
        "StorageManager Status:\n" ..
        "  Initialized: %s\n" ..
        "  Sessions Stored: %d / %d (%.0f%%)\n" ..
        "  Memory Usage: %.2f / %.1f MB (%.0f%%)\n" ..
        "  Session Age Limit: %d days\n" ..
        "  Compression: %s (%.1f%% ratio)\n" ..
        "  Recent Sessions: %d available",
        tostring(status.isInitialized),
        stats.sessionsStored,
        stats.maxSessions,
        (stats.sessionsStored / stats.maxSessions) * 100,
        stats.totalMemoryMB,
        stats.maxMemoryMB,
        (stats.totalMemoryMB / stats.maxMemoryMB) * 100,
        stats.maxSessionAgeDays,
        stats.compressionEnabled and "ON" or "OFF",
        (stats.compressionRatio * 100),
        math.min(5, stats.sessionsStored)
    )
end

-- Export data for external tools
function StorageManager:ExportSessionsToTable()
    local exportData = {
        metadata = {
            exportTime = GetServerTime(),
            addonVersion = addon.VERSION,
            sessionCount = #sessionStorage
        },
        sessions = {}
    }
    
    for _, session in ipairs(sessionStorage) do
        local exportSession = {}
        for k, v in pairs(session) do
            exportSession[k] = v
        end
        
        -- Decompress events for export
        if session.compressed and session.events then
            exportSession.events = self:DecompressEvents(session.events)
            exportSession.compressed = false
        end
        
        table.insert(exportData.sessions, exportSession)
    end
    
    return exportData
end