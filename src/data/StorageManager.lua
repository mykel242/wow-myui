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

-- Table Pooling System (based on Recount's approach)
local tablePool = {}
local poolStats = {
    created = 0,        -- Total tables created
    reused = 0,         -- Tables reused from pool
    returned = 0,       -- Tables returned to pool
    currentPoolSize = 0, -- Current pool size
    maxPoolSize = 500,   -- Increased for better reuse during intensive combat
    warnings = 0        -- Pool-related warnings
}

-- Get current storage configuration (hardcoded defaults since SettingsWindow is disabled)
-- MEMORY OPTIMIZATION: Reduced limits to prevent 34MB saved file issue
local function GetStorageConfig()
    return {
        MAX_SESSIONS = 15,        -- Reduced from 50 - prevents memory bloat
        MAX_SESSION_AGE_DAYS = 3, -- Reduced from 7 - more aggressive cleanup
        MAX_MEMORY_MB = 5,        -- Reduced from 10 - tighter memory control
        COMPRESSION_ENABLED = true,
        ENHANCED_COMPRESSION = true, -- NEW: More aggressive compression for saved data
        WARNING_THRESHOLD = 0.7   -- Warn at 70% instead of 80% - earlier warnings
    }
end

-- Saved variable for persistent storage
local STORAGE_KEY = "MyUI_CombatSessions"

-- ============================================================================
-- TABLE POOLING SYSTEM (based on Recount's methodology)
-- ============================================================================

-- Get a table from the pool (reuse existing or create new)
function StorageManager:GetTable()
    local table
    
    if #tablePool > 0 then
        -- Reuse existing table from pool
        table = tablePool[#tablePool]
        tablePool[#tablePool] = nil
        poolStats.currentPoolSize = poolStats.currentPoolSize - 1
        poolStats.reused = poolStats.reused + 1
        
        -- Sanity check - warn if table isn't empty (indicates improper cleanup)
        local count = 0
        for _ in pairs(table) do
            count = count + 1
        end
        
        if count > 0 then
            poolStats.warnings = poolStats.warnings + 1
            if addon.MyLogger then
                addon.MyLogger:Warn("Table pool warning: reused table has %d entries (should be empty)", count)
            end
            -- Clear the table to prevent data corruption
            for k in pairs(table) do
                table[k] = nil
            end
        end
    else
        -- Create new table
        table = {}
        poolStats.created = poolStats.created + 1
    end
    
    return table
end

-- Return a table to the pool for reuse
function StorageManager:ReleaseTable(table)
    if not table then
        if addon.MyLogger then
            addon.MyLogger:Warn("Attempted to release nil table to pool")
        end
        return
    end
    
    -- Clear all contents before returning to pool
    for k in pairs(table) do
        table[k] = nil
    end
    
    -- Only add to pool if we haven't exceeded maximum size
    if poolStats.currentPoolSize < poolStats.maxPoolSize then
        tablePool[#tablePool + 1] = table
        poolStats.currentPoolSize = poolStats.currentPoolSize + 1
        poolStats.returned = poolStats.returned + 1
    else
        -- Pool is full, let this table be garbage collected
        -- This prevents memory bloat while still providing pooling benefits
    end
end

-- Get table pool statistics for debugging/monitoring
function StorageManager:GetPoolStats()
    return {
        created = poolStats.created,
        reused = poolStats.reused,
        returned = poolStats.returned,
        currentPoolSize = poolStats.currentPoolSize,
        maxPoolSize = poolStats.maxPoolSize,
        warnings = poolStats.warnings,
        reuseRatio = (poolStats.created > 0) and (poolStats.reused / poolStats.created) or 0
    }
end

-- Reset pool statistics (useful for testing)
function StorageManager:ResetPoolStats()
    poolStats.created = 0
    poolStats.reused = 0
    poolStats.returned = 0
    poolStats.warnings = 0
    -- Don't reset currentPoolSize or maxPoolSize as they reflect actual state
end

-- Clear the entire table pool (emergency cleanup)
function StorageManager:ClearTablePool()
    for i = 1, #tablePool do
        tablePool[i] = nil
    end
    poolStats.currentPoolSize = 0
    if addon.MyLogger then
        addon.MyLogger:Info("Table pool cleared")
    end
end

-- Helper function to clean up pooled tables in a session before removal
local function CleanupSessionPooledTables(sessionData)
    if not sessionData then
        return
    end
    
    -- Clean up event tables
    if sessionData.events then
        for _, eventData in ipairs(sessionData.events) do
            if eventData and type(eventData) == "table" then
                StorageManager:ReleaseTable(eventData)
            end
        end
        StorageManager:ReleaseTable(sessionData.events)
    end
    
    -- Clean up segment tables (new segmentation support)
    if sessionData.segments then
        for _, segment in ipairs(sessionData.segments) do
            if segment and type(segment) == "table" then
                -- Clean up segment events
                if segment.events then
                    for _, eventData in ipairs(segment.events) do
                        if eventData and type(eventData) == "table" then
                            StorageManager:ReleaseTable(eventData)
                        end
                    end
                    StorageManager:ReleaseTable(segment.events)
                end
                -- Clean up the segment table itself
                StorageManager:ReleaseTable(segment)
            end
        end
        StorageManager:ReleaseTable(sessionData.segments)
    end
    
    -- Clean up GUID map
    if sessionData.guidMap then
        StorageManager:ReleaseTable(sessionData.guidMap)
    end
    
    -- Clean up the main session table
    StorageManager:ReleaseTable(sessionData)
end

-- ============================================================================
-- END TABLE POOLING SYSTEM
-- ============================================================================

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
    
    -- REGULAR AUTO-CLEANUP: Schedule periodic cleanup every 30 minutes
    self.cleanupTimer = C_Timer.NewTicker(1800, function() -- 30 minutes
        self:PerformScheduledCleanup()
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
    
    -- Preserve GUID map by copying it (prevent table pool cleanup)
    if sessionData.guidMap then
        local guidMapCopy = {}
        for guid, name in pairs(sessionData.guidMap) do
            guidMapCopy[guid] = name
        end
        sessionData.guidMap = guidMapCopy
    end
    
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
    
    local compressed = self:GetTable() or {}
    local eventTypeMap = self:GetTable() or {} -- Map event types to short codes
    local nextTypeId = 1
    
    for _, event in ipairs(events) do
        -- Map event type to short ID
        local eventType = event.subevent
        if not eventTypeMap[eventType] then
            eventTypeMap[eventType] = nextTypeId
            nextTypeId = nextTypeId + 1
        end
        
        -- Create compressed event record using table pool
        local compressedEvent = self:GetTable() or {}
        compressedEvent.t = math.floor(((event.time or event.realTime) or 0) * 1000) -- Timestamp in ms (handle both formats)
        compressedEvent.e = eventTypeMap[eventType] -- Event type ID
        compressedEvent.s = event.sourceGUID -- Source GUID
        compressedEvent.d = event.destGUID   -- Dest GUID
        compressedEvent.a = event.args and #event.args > 0 and event.args or nil -- Args only if present
        
        table.insert(compressed, compressedEvent)
    end
    
    local result = self:GetTable() or {}
    result.events = compressed
    result.typeMap = eventTypeMap
    result.originalCount = #events
    
    return result
end

-- Decompress event data for reading
function StorageManager:DecompressEvents(compressedData)
    if not compressedData or not compressedData.events then
        return {}
    end
    
    local events = self:GetTable() or {}
    local reverseTypeMap = self:GetTable() or {} -- Reverse the type mapping
    
    for eventType, id in pairs(compressedData.typeMap) do
        reverseTypeMap[id] = eventType
    end
    
    for _, compressed in ipairs(compressedData.events) do
        local event = self:GetTable() or {}
        event.realTime = compressed.t and (compressed.t / 1000) or 0
        event.subevent = reverseTypeMap[compressed.e] or "UNKNOWN"
        event.sourceGUID = compressed.s
        event.destGUID = compressed.d
        event.args = compressed.a or {}
        
        table.insert(events, event)
    end
    
    -- Release the reverseTypeMap back to pool
    self:ReleaseTable(reverseTypeMap)
    
    return events
end

-- Estimate memory usage of a session in KB
function StorageManager:EstimateSessionSizeKB(sessionData)
    -- Rough estimation based on data structure
    local baseSize = 1 -- Base session metadata
    local eventSize = sessionData.eventCount * 0.1 -- ~100 bytes per event
    local metadataSize = sessionData.metadata and 2 or 0 -- ~2KB for metadata
    
    -- Add segment overhead for segmented sessions
    local segmentOverhead = 0
    if sessionData.isSegmented and sessionData.segments then
        segmentOverhead = #sessionData.segments * 0.5 -- ~0.5KB per segment metadata
    end
    
    return baseSize + eventSize + metadataSize + segmentOverhead
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
        local removedSession = table.remove(sessionStorage, 1)
        CleanupSessionPooledTables(removedSession)
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
            local removedSession = table.remove(sessionStorage, i)
            CleanupSessionPooledTables(removedSession)
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
            local removedSession = table.remove(sessionStorage, 1)
            CleanupSessionPooledTables(removedSession)
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

-- LAZY LOADING: Load only session metadata on startup, full data when accessed
function StorageManager:LoadFromSavedVariables()
    if MyUIDB and MyUIDB[STORAGE_KEY] then
        local loadedSessions = MyUIDB[STORAGE_KEY]
        sessionStorage = {}
        
        -- LAZY LOADING: Only load metadata, mark events/segments as lazy
        for _, session in ipairs(loadedSessions) do
            local lightSession = self:GetTable()
            
            -- Copy only lightweight metadata
            lightSession.id = session.id
            lightSession.hash = session.hash
            lightSession.duration = session.duration
            lightSession.eventCount = session.eventCount
            lightSession.storedAt = session.storedAt
            lightSession.serverTime = session.serverTime
            lightSession.compressed = session.compressed
            lightSession.isSegmented = session.isSegmented
            lightSession.segmentCount = session.segmentCount
            
            -- Copy lightweight metadata only
            if session.metadata then
                lightSession.metadata = self:GetTable()
                lightSession.metadata.zone = session.metadata.zone and session.metadata.zone.name or "Unknown"
                lightSession.metadata.player = session.metadata.player and session.metadata.player.name or "Unknown"
                lightSession.metadata.group = session.metadata.group and session.metadata.group.type or "solo"
            end
            
            -- Mark as lazy-loaded (events/segments not loaded)
            lightSession._lazyLoaded = true
            lightSession._originalIndex = #sessionStorage + 1
            
            table.insert(sessionStorage, lightSession)
        end
        
        -- Store reference to full data for lazy loading
        self._savedSessionData = loadedSessions
        
        addon:Debug("Loaded %d combat sessions from saved variables (lazy metadata only)", #sessionStorage)
    else
        sessionStorage = {}
        self._savedSessionData = {}
    end
end

-- Convert a session and all its nested data to use table pool
function StorageManager:ConvertSessionToPool(session)
    local pooledSession = self:GetTable()
    
    -- Copy basic properties
    for k, v in pairs(session) do
        if type(v) ~= "table" then
            pooledSession[k] = v
        end
    end
    
    -- Convert events array if present
    if session.events then
        if session.compressed then
            -- Handle compressed events structure
            pooledSession.events = self:ConvertCompressedEventsToPool(session.events)
        else
            -- Handle regular events array
            pooledSession.events = self:GetTable()
            for _, event in ipairs(session.events) do
                local pooledEvent = self:GetTable()
                for k, v in pairs(event) do
                    pooledEvent[k] = v
                end
                table.insert(pooledSession.events, pooledEvent)
            end
        end
        pooledSession.compressed = session.compressed
    end
    
    -- Convert segments array if present
    if session.segments then
        pooledSession.segments = self:GetTable()
        for _, segment in ipairs(session.segments) do
            local pooledSegment = self:GetTable()
            
            -- Copy segment properties
            for k, v in pairs(segment) do
                if type(v) ~= "table" then
                    pooledSegment[k] = v
                end
            end
            
            -- Convert segment events if present
            if segment.events then
                pooledSegment.events = self:GetTable()
                for _, event in ipairs(segment.events) do
                    local pooledEvent = self:GetTable()
                    for k, v in pairs(event) do
                        pooledEvent[k] = v
                    end
                    table.insert(pooledSegment.events, pooledEvent)
                end
            end
            
            table.insert(pooledSession.segments, pooledSegment)
        end
    end
    
    -- Convert guidMap if present (keep as regular table since it's used for lookups)
    if session.guidMap then
        pooledSession.guidMap = {}
        for k, v in pairs(session.guidMap) do
            pooledSession.guidMap[k] = v
        end
    end
    
    -- Convert metadata if present
    if session.metadata then
        pooledSession.metadata = self:ConvertMetadataToPool(session.metadata)
    end
    
    return pooledSession
end

-- Convert compressed events structure to use table pool
function StorageManager:ConvertCompressedEventsToPool(compressedEvents)
    local pooledCompressed = self:GetTable()
    
    -- Copy basic properties
    pooledCompressed.originalCount = compressedEvents.originalCount
    
    -- Convert events array
    if compressedEvents.events then
        pooledCompressed.events = self:GetTable()
        for _, event in ipairs(compressedEvents.events) do
            local pooledEvent = self:GetTable()
            for k, v in pairs(event) do
                pooledEvent[k] = v
            end
            table.insert(pooledCompressed.events, pooledEvent)
        end
    end
    
    -- Convert type map
    if compressedEvents.typeMap then
        pooledCompressed.typeMap = self:GetTable()
        for k, v in pairs(compressedEvents.typeMap) do
            pooledCompressed.typeMap[k] = v
        end
    end
    
    return pooledCompressed
end

-- Convert metadata structure to use table pool
function StorageManager:ConvertMetadataToPool(metadata)
    local pooledMetadata = self:GetTable()
    
    for k, v in pairs(metadata) do
        if type(v) == "table" then
            pooledMetadata[k] = self:GetTable()
            for k2, v2 in pairs(v) do
                if type(v2) == "table" then
                    pooledMetadata[k][k2] = self:GetTable()
                    for k3, v3 in pairs(v2) do
                        pooledMetadata[k][k2][k3] = v3
                    end
                else
                    pooledMetadata[k][k2] = v2
                end
            end
        else
            pooledMetadata[k] = v
        end
    end
    
    return pooledMetadata
end

-- REGULAR AUTO-CLEANUP: Scheduled cleanup to prevent memory buildup
function StorageManager:PerformScheduledCleanup()
    local config = GetStorageConfig()
    local initialCount = #sessionStorage
    local cleaned = false
    
    addon:Debug("Performing scheduled session cleanup (every 30 minutes)")
    
    -- Remove sessions older than max age
    local cutoffTime = GetServerTime() - (config.MAX_SESSION_AGE_DAYS * 24 * 60 * 60)
    local expiredRemoved = 0
    local i = 1
    while i <= #sessionStorage do
        local session = sessionStorage[i]
        if session.serverTime and session.serverTime < cutoffTime then
            local removedSession = table.remove(sessionStorage, i)
            
            -- Clean up session data if it's fully loaded
            if not removedSession._lazyLoaded then
                CleanupSessionPooledTables(removedSession)
            else
                -- Just release the light session
                if removedSession.metadata then
                    self:ReleaseTable(removedSession.metadata)
                end
                self:ReleaseTable(removedSession)
            end
            
            expiredRemoved = expiredRemoved + 1
            cleaned = true
        else
            i = i + 1
        end
    end
    
    -- Remove excess sessions if over limit (oldest first)
    while #sessionStorage > config.MAX_SESSIONS do
        local removedSession = table.remove(sessionStorage, 1)
        
        -- Clean up session data if it's fully loaded
        if not removedSession._lazyLoaded then
            CleanupSessionPooledTables(removedSession)
        else
            -- Just release the light session
            if removedSession.metadata then
                self:ReleaseTable(removedSession.metadata)
            end
            self:ReleaseTable(removedSession)
        end
        
        cleaned = true
    end
    
    if cleaned then
        self:UpdateMemoryStats()
        self:SaveToSavedVariables()
        
        local finalCount = #sessionStorage
        local totalRemoved = initialCount - finalCount
        
        if totalRemoved > 0 then
            addon:Info("Scheduled cleanup: removed %d sessions (%d expired, %d over limit)", 
                totalRemoved, expiredRemoved, totalRemoved - expiredRemoved)
            addon:Info("Sessions remaining: %d / %d", finalCount, config.MAX_SESSIONS)
        end
    end
end

-- Save sessions to saved variables with enhanced compression
function StorageManager:SaveToSavedVariables()
    if not MyUIDB then
        MyUIDB = {}
    end
    
    local config = GetStorageConfig()
    
    if config.ENHANCED_COMPRESSION then
        -- ENHANCED COMPRESSION: Save only essential data, strip runtime fields
        local compressedSessions = {}
        
        for _, session in ipairs(sessionStorage) do
            local compressedSession = {}
            
            -- Copy only essential persistent fields
            compressedSession.id = session.id
            compressedSession.hash = session.hash
            compressedSession.duration = session.duration
            compressedSession.eventCount = session.eventCount
            compressedSession.storedAt = session.storedAt
            compressedSession.serverTime = session.serverTime
            compressedSession.compressed = session.compressed
            compressedSession.isSegmented = session.isSegmented
            compressedSession.segmentCount = session.segmentCount
            
            -- Compress metadata to essential fields only
            if session.metadata then
                compressedSession.metadata = {
                    zone = session.metadata.zone and { name = session.metadata.zone.name } or nil,
                    player = session.metadata.player and { name = session.metadata.player.name } or nil,
                    group = session.metadata.group and { type = session.metadata.group.type } or nil
                }
            end
            
            -- Copy events/segments only if fully loaded (not lazy)
            if not session._lazyLoaded then
                compressedSession.events = session.events
                compressedSession.segments = session.segments
                compressedSession.guidMap = session.guidMap
            end
            
            table.insert(compressedSessions, compressedSession)
        end
        
        MyUIDB[STORAGE_KEY] = compressedSessions
        addon:Debug("Saved %d sessions with enhanced compression", #compressedSessions)
    else
        -- Standard save
        MyUIDB[STORAGE_KEY] = sessionStorage
    end
    
    -- Note: Silent save - no chat spam
end

-- Public API methods
function StorageManager:GetAllSessions()
    -- Return copy to prevent modification using table pool
    local sessions = self:GetTable() or {}
    for i, session in ipairs(sessionStorage) do
        sessions[i] = session
    end
    return sessions
end

function StorageManager:GetSession(sessionId)
    for i, session in ipairs(sessionStorage) do
        if session.id == sessionId or (session.hash and string.upper(session.hash) == string.upper(sessionId)) then
            
            -- LAZY LOADING: Load full session data if needed
            if session._lazyLoaded then
                addon:Debug("Lazy loading full session data for: %s", sessionId)
                session = self:LazyLoadFullSession(i)
            end
            
            -- Return copy with decompressed events if needed using table pool
            local sessionCopy = self:GetTable() or {}
            for k, v in pairs(session) do
                if k ~= "_lazyLoaded" and k ~= "_originalIndex" then
                    sessionCopy[k] = v
                end
            end
            
            -- Handle legacy compressed events
            if session.compressed and session.events then
                sessionCopy.events = self:DecompressEvents(session.events)
                sessionCopy.compressed = false
            end
            
            -- Handle segmented sessions - decompress segment events
            if session.segments and session.isSegmented then
                sessionCopy.segments = self:GetTable() or {}
                for i, segment in ipairs(session.segments) do
                    local segmentCopy = self:GetTable() or {}
                    for k, v in pairs(segment) do
                        segmentCopy[k] = v
                    end
                    
                    -- Decompress segment events if needed
                    if segment.compressed and segment.events then
                        segmentCopy.events = self:DecompressEvents(segment.events)
                        segmentCopy.compressed = false
                    end
                    
                    sessionCopy.segments[i] = segmentCopy
                end
            end
            
            return sessionCopy
        end
    end
    return nil
end

-- LAZY LOADING: Load full session data when accessed
function StorageManager:LazyLoadFullSession(sessionIndex)
    local lightSession = sessionStorage[sessionIndex]
    if not lightSession._lazyLoaded or not self._savedSessionData then
        return lightSession -- Already fully loaded
    end
    
    local originalIndex = lightSession._originalIndex
    if not self._savedSessionData[originalIndex] then
        addon:Warn("Lazy loading failed: original session data not found")
        return lightSession
    end
    
    -- Convert the full session data to use table pool
    local fullSession = self:ConvertSessionToPool(self._savedSessionData[originalIndex])
    
    -- Replace the light session with the full session
    -- Release the light session back to pool first
    if lightSession.metadata then
        self:ReleaseTable(lightSession.metadata)
    end
    self:ReleaseTable(lightSession)
    
    -- Store the full session
    sessionStorage[sessionIndex] = fullSession
    
    addon:Debug("Lazy loaded full session: %s (%d events)", fullSession.id, fullSession.eventCount)
    return fullSession
end

function StorageManager:GetRecentSessions(count)
    count = count or 10
    local recent = self:GetTable() or {}
    local startIndex = math.max(1, #sessionStorage - count + 1)
    
    for i = startIndex, #sessionStorage do
        table.insert(recent, sessionStorage[i])
    end
    
    return recent
end

function StorageManager:DeleteSession(sessionId)
    for i, session in ipairs(sessionStorage) do
        if session.id == sessionId or (session.hash and string.upper(session.hash) == string.upper(sessionId)) then
            local removedSession = table.remove(sessionStorage, i)
            CleanupSessionPooledTables(removedSession)
            self:UpdateMemoryStats()
            self:SaveToSavedVariables() -- Auto-save after deletion
            return true
        end
    end
    return false
end

function StorageManager:ClearAllSessions()
    -- Clean up all pooled tables before clearing
    for _, session in ipairs(sessionStorage) do
        CleanupSessionPooledTables(session)
    end
    sessionStorage = {}
    memoryStats.sessionsStored = 0
    memoryStats.totalMemoryKB = 0
    self:SaveToSavedVariables() -- Auto-save after clearing
    
    addon:Debug("All combat sessions cleared")
end

-- ============================================================================
-- SESSION SEGMENTATION SUPPORT
-- ============================================================================

-- Get a specific segment from a session (supports hash or full ID)
function StorageManager:GetSessionSegment(sessionId, segmentIndex)
    local session = self:GetSession(sessionId)
    if not session or not session.segments or not session.segments[segmentIndex] then
        return nil
    end
    
    return session.segments[segmentIndex]
end

-- Get all segments for a session (with optional lazy loading)
function StorageManager:GetSessionSegments(sessionId, loadEvents)
    local session = self:GetSession(sessionId)
    if not session or not session.segments then
        return {}
    end
    
    -- If loadEvents is false, return segments without event data for performance
    if loadEvents == false then
        local lightSegments = {}
        for i, segment in ipairs(session.segments) do
            local lightSegment = {
                id = segment.id,
                segmentIndex = segment.segmentIndex,
                startTime = segment.startTime,
                endTime = segment.endTime,
                duration = segment.duration,
                eventCount = segment.eventCount,
                isActive = segment.isActive
            }
            lightSegments[i] = lightSegment
        end
        return lightSegments
    end
    
    return session.segments
end

-- Get segment summary for UI display
function StorageManager:GetSegmentSummary(sessionId)
    local session = self:GetSession(sessionId)
    if not session then
        return nil
    end
    
    local summary = {
        sessionId = sessionId,
        isSegmented = session.isSegmented or false,
        segmentCount = session.segmentCount or 0,
        totalEvents = session.eventCount or 0,
        totalDuration = session.duration or 0
    }
    
    if session.segments then
        summary.segments = {}
        for i, segment in ipairs(session.segments) do
            summary.segments[i] = {
                index = i,
                id = segment.id,
                duration = segment.duration or 0,
                eventCount = segment.eventCount or 0,
                startTime = segment.startTime,
                endTime = segment.endTime
            }
        end
    end
    
    return summary
end

-- Merge segments back into a single event stream (for export/analysis)
function StorageManager:MergeSessionSegments(sessionId)
    local session = self:GetSession(sessionId)
    if not session or not session.segments then
        -- Return existing events if not segmented
        return session and session.events or {}
    end
    
    local mergedEvents = {}
    
    for _, segment in ipairs(session.segments) do
        if segment.events then
            for _, event in ipairs(segment.events) do
                table.insert(mergedEvents, event)
            end
        end
    end
    
    -- Sort by timestamp to maintain chronological order
    table.sort(mergedEvents, function(a, b)
        return (a.time or 0) < (b.time or 0)
    end)
    
    return mergedEvents
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

-- Release compressed data structure back to pool
function StorageManager:ReleaseCompressedData(compressedData)
    if not compressedData then
        return
    end
    
    -- Release individual compressed events
    if compressedData.events then
        for _, event in ipairs(compressedData.events) do
            self:ReleaseTable(event)
        end
        self:ReleaseTable(compressedData.events)
    end
    
    -- Release the type map
    if compressedData.typeMap then
        self:ReleaseTable(compressedData.typeMap)
    end
    
    -- Release the main structure
    self:ReleaseTable(compressedData)
end

-- Release session copy returned by GetSession
function StorageManager:ReleaseSessionCopy(sessionCopy)
    if not sessionCopy then
        return
    end
    
    -- Release events array if it was decompressed
    if sessionCopy.events then
        for _, event in ipairs(sessionCopy.events) do
            self:ReleaseTable(event)
        end
        self:ReleaseTable(sessionCopy.events)
    end
    
    -- Release segments if they exist
    if sessionCopy.segments then
        for _, segment in ipairs(sessionCopy.segments) do
            if segment.events then
                for _, event in ipairs(segment.events) do
                    self:ReleaseTable(event)
                end
                self:ReleaseTable(segment.events)
            end
            self:ReleaseTable(segment)
        end
        self:ReleaseTable(sessionCopy.segments)
    end
    
    -- Release the main session copy
    self:ReleaseTable(sessionCopy)
end

-- Release session list returned by GetAllSessions or GetRecentSessions
function StorageManager:ReleaseSessionList(sessionList)
    if sessionList then
        self:ReleaseTable(sessionList)
    end
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
    local poolStats = self:GetPoolStats()
    
    -- Count segmented sessions
    local segmentedSessions = 0
    local totalSegments = 0
    for _, session in ipairs(sessionStorage) do
        if session.isSegmented and session.segments then
            segmentedSessions = segmentedSessions + 1
            totalSegments = totalSegments + #session.segments
        end
    end
    
    return string.format(
        "StorageManager Status:\n" ..
        "  Initialized: %s\n" ..
        "  Sessions Stored: %d / %d (%.0f%%)\n" ..
        "  Segmented Sessions: %d (%.0f%% of total)\n" ..
        "  Total Segments: %d\n" ..
        "  Memory Usage: %.2f / %.1f MB (%.0f%%)\n" ..
        "  Session Age Limit: %d days\n" ..
        "  Compression: %s (%.1f%% ratio)\n" ..
        "  Recent Sessions: %d available\n" ..
        "Table Pool Stats:\n" ..
        "  Pool Size: %d / %d\n" ..
        "  Created: %d, Reused: %d (%.1f%% reuse)\n" ..
        "  Returned: %d, Warnings: %d",
        tostring(status.isInitialized),
        stats.sessionsStored,
        stats.maxSessions,
        (stats.sessionsStored / stats.maxSessions) * 100,
        segmentedSessions,
        stats.sessionsStored > 0 and (segmentedSessions / stats.sessionsStored) * 100 or 0,
        totalSegments,
        stats.totalMemoryMB,
        stats.maxMemoryMB,
        (stats.totalMemoryMB / stats.maxMemoryMB) * 100,
        stats.maxSessionAgeDays,
        stats.compressionEnabled and "ON" or "OFF",
        (stats.compressionRatio * 100),
        math.min(5, stats.sessionsStored),
        poolStats.currentPoolSize,
        poolStats.maxPoolSize,
        poolStats.created,
        poolStats.reused,
        (poolStats.reuseRatio * 100),
        poolStats.returned,
        poolStats.warnings
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