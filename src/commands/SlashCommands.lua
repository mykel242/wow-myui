-- SlashCommands.lua
-- Legacy slash command handlers (preserved for future re-enable)

local addonName, addon = ...

-- Legacy slash command module
addon.SlashCommands = {}
local SlashCommands = addon.SlashCommands

-- DISABLED: All complex commands are disabled during modularization
-- These will be re-enabled as the new combat logging system is implemented

-- Main slash command handler (LEGACY - PRESERVED)
function SlashCommands:InitializeLegacyCommands()
    -- DISABLED: Complex slash commands preserved but not registered
    -- Uncomment the SLASH_MYUI1 line and function below to re-enable
    
    --[[
    SLASH_MYUI1 = "/myui"
    
    function SlashCmdList.MYUI(msg, editBox)
        local command = string.lower(msg)

        if command == "show" then
            if not addon.mainFrame then
                addon:CreateMainFrame()
            end
            addon.mainFrame:Show()
            addon.db.showMainWindow = true
            addon:Info("Main window toggled")
        elseif command == "hide" then
            if addon.mainFrame then
                addon.mainFrame:Hide()
                addon.db.showMainWindow = false
                addon:Info("Main window hidden")
            end
        elseif command == "toggle" or command == "" then
            addon:ToggleMainWindow()
        elseif command == "dps" then
            print("DPS meter disabled during modularization")
        elseif command == "hps" then
            print("HPS meter disabled during modularization")
        elseif command == "debug" then
            addon.DEBUG = not addon.DEBUG
            addon.db.debugMode = addon.DEBUG
            addon:Info("Debug mode: %s", addon.DEBUG and "ON" or "OFF")
        elseif command:match("^hpsmax%s+(%d+)$") then
            print("Meter commands disabled during modularization")
        elseif command:match("^dpsmax%s+(%d+)$") then
            print("Meter commands disabled during modularization")
        elseif command == "hpsreset" then
            print("Meter commands disabled during modularization")
        elseif command == "dpsreset" then
            print("Meter commands disabled during modularization")
        elseif command == "meterinfo" then
            print("Meter commands disabled during modularization")
        elseif command == "resetmeters" then
            print("Meter commands disabled during modularization")
        elseif command == "resetcombat" then
            print("Combat reset disabled during modularization")
        elseif command == "sessions" then
            print("Session commands disabled during modularization")
        elseif command == "clear" then
            print("Session commands disabled during modularization")
        elseif command:match("^scaling%s+(.+)$") then
            print("Scaling commands disabled during modularization")
        elseif command:match("^mark%s+(%w+)%s+(.+)$") then
            print("Session marking disabled during modularization")
        elseif command:match("^list%s+(.+)$") then
            print("Session listing disabled during modularization")
        elseif command == "ids" then
            print("Session commands disabled during modularization")
        elseif command == "enhancedlog" then
            print("Enhanced logging commands disabled during modularization")
        elseif command:match("^enhancedconfig%s+(.+)$") then
            print("Enhanced config disabled during modularization")
        elseif command == "memory" then
            print("Memory commands disabled during modularization")
        elseif command == "timers" then
            print("Timer commands disabled during modularization")
        elseif command == "timestamps" then
            if addon.MyTimestampManager then
                addon:Info(addon.MyTimestampManager:GetDebugSummary())
            else
                addon:Warn("MyTimestampManager not loaded")
            end
        elseif command == "cleardata" then
            print("Data clearing disabled during modularization")
        elseif command:match("^calc") then
            print("Calculation commands disabled during modularization")
        elseif command == "logger" then
            print("Combat Logger - Coming Soon!")
        elseif command == "rawdata" then
            print("Raw Data Viewer - Coming Soon!")
        else
            print("MyUI Commands (Simplified):")
            print("  /myui [ show | hide | toggle ] - Main window")
            print("  /myui debug - Toggle debug mode")
            print("  /myui timestamps - Show MyTimestampManager debug info")
            print("")
            print("New Tools (Coming Soon):")
            print("  /myui logger - Combat log viewer")
            print("  /myui rawdata - Raw data viewer")
            print("")
            print("Note: Most features disabled during modularization.")
            print("They will return with the new combat logging system.")
        end
    end
    --]]
end

-- Simple slash command handler (ACTIVE)
function SlashCommands:InitializeSimpleCommands()
    SLASH_MYUI1 = "/myui"
    
    function SlashCmdList.MYUI(msg, editBox)
        local command = string.lower(msg)

        if command == "show" then
            if not addon.mainFrame then
                addon:CreateMainFrame()
            end
            addon.mainFrame:Show()
            addon.db.showMainWindow = true
            addon:Info("Main window toggled")
        elseif command == "hide" then
            if addon.mainFrame then
                addon.mainFrame:Hide()
                addon.db.showMainWindow = false
                addon:Info("Main window hidden")
            end
        elseif command == "toggle" or command == "" then
            addon:ToggleMainWindow()
        elseif command == "debug" then
            addon.DEBUG = not addon.DEBUG
            addon.db.debugMode = addon.DEBUG
            addon:Info("Debug mode: %s", addon.DEBUG and "ON" or "OFF")
        --[[ DISABLED
        elseif command == "settings" then
            if addon.SettingsWindow then
                addon.SettingsWindow:Show()
            else
                print("Settings window not available")
            end
        --]]
        elseif command == "timestamps" then
            if addon.MyTimestampManager then
                addon:Info(addon.MyTimestampManager:GetDebugSummary())
            else
                addon:Warn("MyTimestampManager not loaded")
            end
        elseif command == "logger" then
            if addon.MySimpleCombatDetector then
                local debugInfo = addon.MySimpleCombatDetector:GetDebugInfo()
                print(string.format("Combat Detector Status: inCombat=%s, sessionId=%s", 
                    tostring(debugInfo.inCombat), debugInfo.sessionId or "none"))
                print(string.format("Duration: %.1fs, Events: %d, Time since activity: %.1fs", 
                    debugInfo.duration, debugInfo.eventCount, debugInfo.timeSinceActivity))
            else
                print("MySimpleCombatDetector not loaded")
            end
        elseif command == "rawdata" then
            if addon.MySimpleCombatDetector then
                local session = addon.MySimpleCombatDetector:GetCurrentSession()
                if session then
                    print(string.format("Current combat raw data: %d events", session.eventCount))
                    if session.eventCount > 0 then
                        print("Latest 3 events:")
                        local startIndex = math.max(1, #session.events - 2)
                        for i = startIndex, #session.events do
                            local event = session.events[i]
                            local sourceName = session.guidMap[event.sourceGUID] or "Unknown"
                            local destName = session.guidMap[event.destGUID] or "Unknown"
                            print(string.format("  [%.3f] %s: %s -> %s", 
                                event.time, event.subevent, sourceName, destName))
                        end
                    end
                else
                    print("No active combat session")
                end
            else
                print("MySimpleCombatDetector not loaded")
            end
        elseif command == "metadata" then
            if addon.MetadataCollector then
                print(addon.MetadataCollector:GetDebugSummary())
            else
                print("MetadataCollector not loaded")
            end
        elseif command == "storage" then
            if addon.StorageManager then
                print(addon.StorageManager:GetDebugSummary())
            else
                print("StorageManager not loaded")
            end
        elseif command == "testwarning" then
            if addon.StorageManager then
                -- Force a storage warning check in test mode
                addon.StorageManager:CheckStorageLimits(true)
                print("Storage warning test triggered (with lowered limits)")
            else
                print("StorageManager not loaded")
            end
        elseif command == "poolstats" then
            if addon.StorageManager then
                local stats = addon.StorageManager:GetPoolStats()
                print("=== Table Pool Statistics ===")
                print(string.format("Pool Size: %d / %d (%.1f%% full)", 
                    stats.currentPoolSize, stats.maxPoolSize, 
                    (stats.currentPoolSize / stats.maxPoolSize) * 100))
                print(string.format("Created: %d tables", stats.created))
                print(string.format("Reused: %d tables (%.1f%% reuse rate)", 
                    stats.reused, stats.reuseRatio * 100))
                print(string.format("Returned: %d tables", stats.returned))
                print(string.format("Warnings: %d", stats.warnings))
                local efficiency = stats.created > 0 and (stats.reused / (stats.created + stats.reused)) * 100 or 0
                print(string.format("Memory Efficiency: %.1f%% (higher is better)", efficiency))
            else
                print("StorageManager not loaded")
            end
        elseif command == "sessions" then
            if addon.StorageManager then
                local sessions = addon.StorageManager:GetRecentSessions(5)
                print(string.format("Recent combat sessions (%d shown):", #sessions))
                for i, session in ipairs(sessions) do
                    local segments = session.isSegmented and session.segments and #session.segments or 1
                    print(string.format("  [%s] %s: %.1fs, %d events, %d segments (%s)", 
                        session.hash or "----",
                        session.id, 
                        session.duration or 0, 
                        session.eventCount or 0,
                        segments,
                        session.metadata and session.metadata.zone.name or "Unknown Zone"))
                end
            else
                print("StorageManager not loaded")
            end
        elseif command == "counters" then
            if MyUIDB and MyUIDB.sessionCounters then
                print("=== Session Counters ===")
                for characterKey, counter in pairs(MyUIDB.sessionCounters) do
                    print(string.format("  %s: %d sessions", characterKey, counter))
                end
            else
                print("No session counters found")
            end
        elseif command == "guids" then
            if addon.GUIDResolver then
                addon:Info(addon.GUIDResolver:GetDebugSummary())
            else
                addon:Error("GUIDResolver not loaded")
            end
        elseif command == "guidcleanup" then
            if addon.GUIDResolver then
                local before = addon.GUIDResolver:GetStatus()
                addon.GUIDResolver:PerformCleanup()
                local after = addon.GUIDResolver:GetStatus()
                
                addon:Info("=== GUID Cache Cleanup ===")
                addon:Info("Before: %d cache, %d encounters", before.cacheSize, before.encounterCount)
                addon:Info("After: %d cache, %d encounters", after.cacheSize, after.encounterCount)
                addon:Info("Removed: %d cache, %d encounters", 
                    before.cacheSize - after.cacheSize, 
                    before.encounterCount - after.encounterCount)
            else
                addon:Error("GUIDResolver not loaded")
            end
        --[[ DISABLED - CombatTracker not available
        elseif command == "combatdetection" then
            if addon.CombatTracker then
                addon.CombatTracker:DebugEnhancedCombatDetection()
            else
                print("CombatTracker not loaded")
            end
        --]]
        elseif command:match("^guid%s+(.+)$") then
            local guid = msg:match("^guid%s+(.+)$")  -- Use original msg, not lowercased command
            if addon.GUIDResolver then
                local name = addon.GUIDResolver:ResolveGUID(guid)
                local cached = addon.GUIDResolver:GetCachedName(guid)
                print(string.format("GUID: %s", guid))
                print(string.format("Resolved Name: %s", name))
                print(string.format("Cached: %s", cached and "Yes" or "No"))
            else
                print("GUIDResolver not loaded")
            end
        --[[ DISABLED
        elseif command == "viewer" then
            if addon.CombatLogViewer then
                addon.CombatLogViewer:Toggle()
            else
                print("CombatLogViewer not loaded")
            end
        --]]
        elseif command == "export" then
            if addon.SessionBrowser then
                addon.SessionBrowser:Show()
                print("Select a session in the browser, then click Export")
            else
                print("SessionBrowser not loaded")
            end
        elseif command == "dumplogs" or command == "recentlogs" then
            if addon.MyLogger then
                addon.MyLogger:DumpRecentLogs()
            else
                print("MyLogger not loaded")
            end
        elseif command == "copylogs" or command == "copyrecentlogs" then
            if addon.MyLogger then
                addon.MyLogger:ExportRecentLogs()
            else
                print("MyLogger not loaded")
            end
        elseif command == "exportlogs" or command == "persistentlogs" then
            if addon.MyLogger then
                addon.MyLogger:DumpPersistentLogs()
            else
                print("MyLogger not loaded")
            end
        elseif command == "copyexportlogs" or command == "copypersistentlogs" then
            if addon.MyLogger then
                addon.MyLogger:ExportPersistentLogs()
            else
                print("MyLogger not loaded")
            end
        elseif command == "testlog" then
            if addon.MyLogger then
                addon.MyLogger:Debug("Logger test - debug level check")
                addon.MyLogger:Info("Logger test - info level check")
                print("Test messages logged. Use /myui logs to open log viewer.")
            else
                print("MyLogger not loaded")
            end
        elseif command == "logs" or command == "logwindow" then
            if addon.MyLoggerWindow then
                addon.MyLoggerWindow:Toggle()
            else
                print("MyLoggerWindow not loaded")
            end
        elseif command == "clearlogs" then
            if addon.MyLoggerWindow then
                StaticPopup_Show("MYLOGGER_CLEAR_CONFIRM")
            else
                print("MyLoggerWindow not loaded")
            end
        elseif command:match("^segments%s+(.+)$") then
            local sessionId = msg:match("^segments%s+(.+)$")  -- Use original msg, not lowercased command
            if addon.StorageManager then
                local summary = addon.StorageManager:GetSegmentSummary(sessionId)
                if summary then
                    print(string.format("=== Segment Summary: %s ===", sessionId))
                    print(string.format("Segmented: %s", summary.isSegmented and "Yes" or "No"))
                    print(string.format("Total Duration: %.1fs, Total Events: %d", 
                        summary.totalDuration, summary.totalEvents))
                    
                    if summary.segments and #summary.segments > 0 then
                        print(string.format("Segments (%d):", #summary.segments))
                        for _, segment in ipairs(summary.segments) do
                            print(string.format("  %d. %s: %.1fs, %d events", 
                                segment.index, segment.id, segment.duration, segment.eventCount))
                        end
                    else
                        print("No segments found")
                    end
                else
                    print("Session not found: " .. sessionId)
                end
            else
                print("StorageManager not loaded")
            end
        elseif command == "browser" then
            if addon.SessionBrowser then
                addon.SessionBrowser:Toggle()
            else
                print("SessionBrowser not loaded")
            end
        elseif command == "memory" then
            -- Display memory usage information via MyLogger
            local memoryKB = collectgarbage("count")
            local memoryMB = memoryKB / 1024
            
            addon:Info("=== MyUI2 Memory Usage ===")
            addon:Info("Total Lua Memory: %.2f MB (%.0f KB)", memoryMB, memoryKB)
            
            -- Storage breakdown
            if addon.StorageManager then
                local stats = addon.StorageManager:GetDebugSummary()
                addon:Info("Storage Manager:")
                addon:Info("  Sessions: %s", stats:match("Sessions: ([^,]+)") or "Unknown")
                addon:Info("  Memory Usage: %s", stats:match("Memory: ([^,]+)") or "Unknown")
                
                local poolStats = addon.StorageManager:GetPoolStats()
                addon:Info("  Table Pool: %d/%d tables (%.1f%% reuse)", 
                    poolStats.currentPoolSize, poolStats.maxPoolSize, poolStats.reuseRatio * 100)
                addon:Info("    Created: %d, Reused: %d, Returned: %d", 
                    poolStats.created, poolStats.reused, poolStats.returned)
            end
            
            -- GUID cache with proper reporting
            if addon.GUIDResolver then
                local guidStats = addon.GUIDResolver:GetCacheStats()
                if guidStats then
                    addon:Info("  GUID Cache: %d entries, %d recent encounters", 
                        guidStats.cacheSize or 0, guidStats.encounterCount or 0)
                else
                    local guidSummary = addon.GUIDResolver:GetDebugSummary()
                    local cacheCount = guidSummary:match("Cache: (%d+)") or "Unknown"
                    addon:Info("  GUID Cache: %s entries", cacheCount)
                end
            end
            
            -- Logger buffer statistics
            if addon.MyLoggerWindow then
                local bufferStats = addon.MyLoggerWindow:GetBufferStats()
                addon:Info("  Logger Buffer: %d/%d entries (%.1f%% full)", 
                    bufferStats.size, bufferStats.capacity, 
                    (bufferStats.size / bufferStats.capacity) * 100)
                addon:Info("    Display Buffer: %d entries", bufferStats.displayBufferSize)
                addon:Info("    Overflow Count: %d messages lost", bufferStats.overflowCount)
                addon:Info("    Current Lag: %d unread messages", bufferStats.currentLag)
                if bufferStats.isLagged then
                    addon:Warn("    ⚠️ Buffer lagged: %d messages behind", bufferStats.laggedCount)
                end
                addon:Info("    Refresh Rate: %dms (%.1fHz)", 
                    bufferStats.refreshRate, 1000 / bufferStats.refreshRate)
            elseif addon.MyLogger then
                addon:Info("  Logger: ~100 recent messages in memory")
            end
            
            -- Add component memory estimates
            addon:Info("")
            addon:Info("Component Memory Estimates:")
            
            -- Enhanced Combat Logger analysis
            if addon.EnhancedCombatLogger then
                addon:Info("  Enhanced Combat Logger: Active (no pooling)")
            end
            
            -- Timeline Tracker analysis  
            if addon.TimelineTracker then
                addon:Info("  Timeline Tracker: Active (no pooling)")
            end
            
            -- Session data analysis
            if addon.StorageManager then
                local stats = addon.StorageManager:GetDebugSummary()
                local sessionInfo = stats:match("Sessions: ([^,]+)") or "Unknown"
                addon:Info("  Combat Sessions: %s stored", sessionInfo)
            end
            
            addon:Info("")
            addon:Info("Memory Usage Gap: %.1f MB unaccounted", 
                math.max(0, memoryMB - 10)) -- Rough estimate of expected usage
            addon:Info("Use '/myui gc' to force garbage collection")
            addon:Info("Use '/myui logs' to view detailed output")
        elseif command == "gc" then
            -- Force garbage collection via MyLogger
            local beforeKB = collectgarbage("count")
            collectgarbage("collect")
            local afterKB = collectgarbage("count")
            local freedKB = beforeKB - afterKB
            
            addon:Info("=== Garbage Collection ===")
            addon:Info("Before: %.2f MB (%.0f KB)", beforeKB / 1024, beforeKB)
            addon:Info("After: %.2f MB (%.0f KB)", afterKB / 1024, afterKB)
            addon:Info("Freed: %.2f MB (%.0f KB)", freedKB / 1024, freedKB)
            
            -- Also show table pool stats after GC
            if addon.StorageManager then
                local poolStats = addon.StorageManager:GetPoolStats()
                addon:Info("Table Pool After GC: %d/%d tables", poolStats.currentPoolSize, poolStats.maxPoolSize)
                addon:Info("Pool Stats: Created=%d, Reused=%d, Returned=%d", 
                    poolStats.created, poolStats.reused, poolStats.returned)
            end
            
            addon:Info("Use '/myui logs' to view detailed output")
        elseif command == "poolconvert" then
            -- Force conversion of saved data to use table pool
            if addon.StorageManager then
                local beforeKB = collectgarbage("count")
                local beforeStats = addon.StorageManager:GetPoolStats()
                
                addon:Info("=== Converting Saved Data to Table Pool ===")
                addon:Info("Before: %.2f MB memory, %d pool tables", beforeKB / 1024, beforeStats.currentPoolSize)
                
                -- Force reload and conversion
                addon.StorageManager:LoadFromSavedVariables()
                
                -- Force aggressive garbage collection to free old data
                addon:Info("Forcing garbage collection to free old data...")
                collectgarbage("collect")
                collectgarbage("collect") -- Double collection for stubborn references
                
                local afterKB = collectgarbage("count")
                local afterStats = addon.StorageManager:GetPoolStats()
                local memoryChange = (afterKB - beforeKB) / 1024
                
                addon:Info("After: %.2f MB memory (%.1f MB %s)", afterKB / 1024, 
                    math.abs(memoryChange), memoryChange >= 0 and "increase" or "decrease")
                addon:Info("Pool: %d tables (%d created for conversion)", 
                    afterStats.currentPoolSize, afterStats.created - beforeStats.created)
                addon:Info("Conversion complete!")
            else
                addon:Error("StorageManager not loaded")
            end
        elseif command == "clearsessions" then
            -- Clear all stored sessions to free memory
            if addon.StorageManager then
                local beforeKB = collectgarbage("count")
                local sessionCount = #addon.StorageManager:GetAllSessions()
                
                addon:Info("=== Clearing All Sessions ===")
                addon:Info("Before: %.2f MB memory, %d sessions", beforeKB / 1024, sessionCount)
                
                -- Clear all sessions (releases pooled tables)
                addon.StorageManager:ClearAllSessions()
                
                -- Force garbage collection
                collectgarbage("collect")
                collectgarbage("collect")
                
                local afterKB = collectgarbage("count")
                local memoryFreed = (beforeKB - afterKB) / 1024
                
                addon:Info("After: %.2f MB memory (%.1f MB freed)", afterKB / 1024, memoryFreed)
                addon:Info("All %d sessions cleared and memory released!", sessionCount)
                addon:Warn("Note: This will also clear your saved session data permanently.")
            else
                addon:Error("StorageManager not loaded")
            end
        elseif command == "addons" then
            -- Check memory usage of all addons using modern API
            if UpdateAddOnMemoryUsage then
                UpdateAddOnMemoryUsage()
            end
            
            local addonMemory = {}
            local totalAddonMemory = 0
            
            -- Try modern C_AddOns API first, fallback to legacy
            local function GetAddOnCount()
                if C_AddOns and C_AddOns.GetNumAddOns then
                    return C_AddOns.GetNumAddOns()
                else
                    return GetNumAddOns and GetNumAddOns() or 0
                end
            end
            
            local function GetAddOnData(i)
                if C_AddOns and C_AddOns.GetAddOnInfo then
                    local name, title = C_AddOns.GetAddOnInfo(i)
                    return name, title
                elseif GetAddOnInfo then
                    return GetAddOnInfo(i)
                else
                    return nil, nil
                end
            end
            
            local function GetAddOnMem(i)
                -- Try multiple API paths for memory usage
                if C_AddOns and C_AddOns.GetAddOnMemoryUsage then
                    return C_AddOns.GetAddOnMemoryUsage(i)
                elseif GetAddOnMemoryUsage then
                    return GetAddOnMemoryUsage(i)
                else
                    -- Fallback: estimate based on addon being loaded
                    local name = GetAddOnData(i)
                    if name and C_AddOns and C_AddOns.IsAddOnLoaded then
                        return C_AddOns.IsAddOnLoaded(name) and 50 or 0  -- Rough 50KB estimate
                    elseif name and IsAddOnLoaded then
                        return IsAddOnLoaded(name) and 50 or 0
                    end
                    return 0
                end
            end
            
            local numAddons = GetAddOnCount()
            
            for i = 1, numAddons do
                local name, title = GetAddOnData(i)
                local memory = GetAddOnMem(i)
                
                if name and memory and memory > 100 then -- Only show addons using >100KB
                    table.insert(addonMemory, {name = title or name, memory = memory})
                    totalAddonMemory = totalAddonMemory + memory
                end
            end
            
            table.sort(addonMemory, function(a, b) return a.memory > b.memory end)
            
            addon:Info("=== Addon Memory Usage (>100KB) ===")
            for i = 1, math.min(10, #addonMemory) do
                local addon_info = addonMemory[i]
                addon:Info("  %s: %.2f MB", addon_info.name, addon_info.memory / 1024)
            end
            addon:Info("Total Addon Memory: %.2f MB", totalAddonMemory / 1024)
            addon:Info("WoW + Other Memory: %.2f MB", (collectgarbage("count") - totalAddonMemory) / 1024)
        elseif command == "tableleaks" then
            -- Analyze table pool usage patterns
            if addon.StorageManager then
                local poolStats = addon.StorageManager:GetPoolStats()
                addon:Info("=== Table Pool Leak Analysis ===")
                addon:Info("Pool Status: %d/%d tables", poolStats.currentPoolSize, poolStats.maxPoolSize)
                addon:Info("Created: %d tables", poolStats.created)
                addon:Info("Reused: %d tables", poolStats.reused) 
                addon:Info("Returned: %d tables", poolStats.returned)
                addon:Info("Warnings: %d", poolStats.warnings)
                
                local leakedTables = poolStats.created - poolStats.returned
                addon:Info("Potential Leaks: %d tables never returned", leakedTables)
                addon:Info("Reuse Efficiency: %.1f%% (higher is better)", poolStats.reuseRatio * 100)
                
                if poolStats.currentPoolSize >= poolStats.maxPoolSize then
                    addon:Warn("⚠️ Pool is full - new returns will be ignored")
                end
                
                if leakedTables > 100 then
                    addon:Warn("⚠️ High leak count suggests missing ReleaseTable() calls")
                end
                
                addon:Info("Potential leak sources:")
                addon:Info("  - StorageManager compression/export temporary tables")
                addon:Info("  - UI components (SessionBrowser, etc.)")
                addon:Info("  - MyLogger internal structures")
                addon:Info("  - Note: EnhancedCombatLogger & TimelineTracker are DISABLED")
            else
                addon:Error("StorageManager not loaded")
            end
        elseif command:match("^session%s+(.+)$") then
            local sessionId = msg:match("^session%s+(.+)$")  -- Use original msg, not lowercased command
            if addon.StorageManager then
                local session = addon.StorageManager:GetSession(sessionId)
                if session then
                    print(string.format("=== Session Details: [%s] %s ===", session.hash or "----", sessionId))
                    print(string.format("Duration: %.1fs", session.duration or 0))
                    print(string.format("Events: %d", session.eventCount or 0))
                    
                    -- Show segmentation info
                    if session.isSegmented and session.segments then
                        print(string.format("Segmented: %d segments", #session.segments))
                        for i, segment in ipairs(session.segments) do
                            print(string.format("  Segment %d: %.1fs, %d events (%s)", 
                                i, segment.duration or 0, segment.eventCount or 0, segment.id))
                        end
                    else
                        print("Segmented: No")
                    end
                    
                    if session.metadata and session.metadata.zone then
                        print(string.format("Zone: %s", session.metadata.zone.name or "Unknown"))
                    end
                    if session.events then
                        print("Latest 5 events:")
                        local startIndex = math.max(1, #session.events - 4)
                        for i = startIndex, #session.events do
                            local event = session.events[i]
                            print(string.format("  [%.3f] %s: %s -> %s", 
                                event.realTime or event.time or 0,
                                event.subevent or "UNKNOWN",
                                event.sourceName or "?",
                                event.destName or "?"))
                        end
                    end
                else
                    print("Session not found: " .. sessionId)
                end
            else
                print("StorageManager not loaded")
            end
        else
            print("MyUI Commands (Simplified):")
            print("  /myui [ show | hide | toggle ] - Main window")
            print("  /myui debug - Toggle debug mode")
            print("  /myui timestamps - Show MyTimestampManager debug info")
            print("")
            print("Combat Analysis Tools:")
            print("  /myui logger - Combat detector status")
            print("  /myui rawdata - Current combat raw data")
            print("  /myui metadata - Current context metadata")
            print("  /myui storage - Storage manager status")
            print("  /myui testwarning - Test storage warning system")
            print("  /myui poolstats - Table pooling statistics")
            print("  /myui sessions - Recent combat sessions")
            print("  /myui session <id|hash> - Show detailed session data")
            print("  /myui segments <id|hash> - Show session segment details")
            print("  /myui counters - Show session counter status")
            print("  /myui guids - Show GUID resolver status")
            print("  /myui guidcleanup - Force GUID cache cleanup")
            print("  /myui guid <guid> - Resolve specific GUID")
            print("  /myui browser - Toggle session browser (table view)")
            print("  /myui export - Open session browser for export")
            print("")
            print("Memory & Performance:")
            print("  /myui memory - Show memory usage breakdown")
            print("  /myui addons - Show all addon memory usage")
            print("  /myui gc - Force garbage collection")
            print("  /myui tableleaks - Analyze table pool leaks")
            print("  /myui poolconvert - Convert saved data to use table pool")
            print("  /myui clearsessions - Clear all stored sessions (frees memory)")
            print("")
            print("Logging Tools:")
            print("  /myui logs - Toggle log viewer window")
            print("  /myui dumplogs - Print recent logs to chat")
            print("  /myui copylogs - Copy recent logs to clipboard")
            print("  /myui exportlogs - Print persistent logs to chat")
            print("  /myui copyexportlogs - Copy persistent logs to clipboard")
            print("  /myui testlog - Generate test log messages")
            print("  /myui clearlogs - Clear all log data")
            print("")
            print("Note: Most features disabled during modularization.")
            print("They will return with the new combat logging system.")
        end
    end
end

-- Initialize the appropriate command set
function SlashCommands:Initialize()
    -- Use simple commands during modularization
    self:InitializeSimpleCommands()
    
    -- SlashCommands initialized
end