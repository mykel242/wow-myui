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
                print("Main window hidden")
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
            print(addonName .. " debug mode: " .. (addon.DEBUG and "ON" or "OFF"))
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
                print(addon.MyTimestampManager:GetDebugSummary())
            else
                print("MyTimestampManager not loaded")
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
                print("Main window hidden")
            end
        elseif command == "toggle" or command == "" then
            addon:ToggleMainWindow()
        elseif command == "debug" then
            addon.DEBUG = not addon.DEBUG
            addon.db.debugMode = addon.DEBUG
            print(addonName .. " debug mode: " .. (addon.DEBUG and "ON" or "OFF"))
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
                print(addon.MyTimestampManager:GetDebugSummary())
            else
                print("MyTimestampManager not loaded")
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
                print(addon.GUIDResolver:GetDebugSummary())
            else
                print("GUIDResolver not loaded")
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
            -- Display memory usage information
            local memoryKB = collectgarbage("count")
            local memoryMB = memoryKB / 1024
            
            print(string.format("=== MyUI2 Memory Usage ==="))
            print(string.format("Total Lua Memory: %.2f MB (%.0f KB)", memoryMB, memoryKB))
            
            -- Storage breakdown
            if addon.StorageManager then
                local stats = addon.StorageManager:GetDebugSummary()
                print("Storage Manager:")
                print(string.format("  Sessions: %s", stats:match("Sessions: ([^,]+)") or "Unknown"))
                print(string.format("  Memory Usage: %s", stats:match("Memory: ([^,]+)") or "Unknown"))
            end
            
            -- GUID cache
            if addon.GUIDResolver then
                local guidStats = addon.GUIDResolver:GetDebugSummary()
                local cacheCount = guidStats:match("Cache: (%d+)") or "Unknown"
                print(string.format("  GUID Cache: %s entries", cacheCount))
            end
            
            -- Table pool
            if addon.StorageManager then
                local poolStats = addon.StorageManager:GetPoolStats()
                print(string.format("  Table Pool: %d/%d tables (%.1f%% reuse)", 
                    poolStats.currentPoolSize, poolStats.maxPoolSize, poolStats.reuseRatio * 100))
            end
            
            -- Logger buffer statistics
            if addon.MyLoggerWindow then
                local bufferStats = addon.MyLoggerWindow:GetBufferStats()
                print(string.format("  Logger Buffer: %d/%d entries (%.1f%% full)", 
                    bufferStats.size, bufferStats.capacity, 
                    (bufferStats.size / bufferStats.capacity) * 100))
                print(string.format("    Display Buffer: %d entries", bufferStats.displayBufferSize))
                print(string.format("    Overflow Count: %d messages lost", bufferStats.overflowCount))
                print(string.format("    Current Lag: %d unread messages", bufferStats.currentLag))
                if bufferStats.isLagged then
                    print(string.format("    ⚠️ Buffer lagged: %d messages behind", bufferStats.laggedCount))
                end
                print(string.format("    Refresh Rate: %dms (%.1fHz)", 
                    bufferStats.refreshRate, 1000 / bufferStats.refreshRate))
            elseif addon.MyLogger then
                print("  Logger: ~100 recent messages in memory")
            end
            
            print("Use '/myui gc' to force garbage collection")
        elseif command == "gc" then
            -- Force garbage collection
            local beforeKB = collectgarbage("count")
            collectgarbage("collect")
            local afterKB = collectgarbage("count")
            local freedKB = beforeKB - afterKB
            
            print(string.format("=== Garbage Collection ==="))
            print(string.format("Before: %.2f MB (%.0f KB)", beforeKB / 1024, beforeKB))
            print(string.format("After: %.2f MB (%.0f KB)", afterKB / 1024, afterKB))
            print(string.format("Freed: %.2f MB (%.0f KB)", freedKB / 1024, freedKB))
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
            print("  /myui guid <guid> - Resolve specific GUID")
            print("  /myui browser - Toggle session browser (table view)")
            print("  /myui export - Open session browser for export")
            print("")
            print("Memory & Performance:")
            print("  /myui memory - Show memory usage breakdown")
            print("  /myui gc - Force garbage collection")
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