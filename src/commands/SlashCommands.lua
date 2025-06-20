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


        if command == "toggle" or command == "" then
            addon:ToggleMainWindow()
        elseif command:match("^session%s+(.+)$") then
            local sessionId = msg:match("^session%s+(.+)$")  -- Use original msg, not lowercased command
            if addon.StorageManager then
                local session = addon.StorageManager:GetSession(sessionId)

                if session then
                    addon:Info("=== Session Details: [%s] %s ===", session.hash or "----", sessionId)
                    addon:Info("Duration: %.1fs", session.duration or 0)
                    addon:Info("Events: %d", session.eventCount or 0)
                    
                    -- Show segmentation info
                    if session.isSegmented and session.segments then
                        addon:Info("Segmented: %d segments", #session.segments)
                        for i, segment in ipairs(session.segments) do
                            addon:Info("  Segment %d: %.1fs, %d events (%s)", 
                                i, segment.duration or 0, segment.eventCount or 0, segment.id)
                        end
                    else
                        addon:Info("Segmented: No")
                    end
                    
                    if session.metadata and session.metadata.zone then
                        if type(session.metadata.zone) == "string" then
                            addon:Info("Zone: %s", session.metadata.zone)
                        elseif session.metadata.zone.name then
                            addon:Info("Zone: %s", session.metadata.zone.name)
                        end
                    end
                    if session.events then
                        addon:Info("Latest 5 events:")
                        local startIndex = math.max(1, #session.events - 4)
                        for i = startIndex, #session.events do
                            local event = session.events[i]
                            addon:Info("  [%.3f] %s: %s -> %s", 
                                event.realTime or event.time or 0,
                                event.subevent or "UNKNOWN",
                                event.sourceName or "?",
                                event.destName or "?")
                        end
                    end
                    addon:Info("Use '/myui logs' to view full output")
                else
                    addon:Error("Session not found: %s", sessionId)
                end
            else
                addon:Error("StorageManager not loaded")
            end
        elseif command == "version" then
            local tocVersion, title
            if C_AddOns and C_AddOns.GetAddOnMetadata then
                tocVersion = C_AddOns.GetAddOnMetadata("myui2", "Version") or "Unknown"
                title = C_AddOns.GetAddOnMetadata("myui2", "Title") or "MyUI2"
            elseif GetAddOnMetadata then
                tocVersion = GetAddOnMetadata("myui2", "Version") or "Unknown"
                title = GetAddOnMetadata("myui2", "Title") or "MyUI2"
            else
                tocVersion = "Unknown"
                title = "MyUI2"
            end
            
            -- Get build info from addon table
            local buildVersion = addon.VERSION or "Unknown"
            local buildDate = addon.BUILD_DATE or "Unknown"
            
            addon:Info("=== %s Version Info ===", title)
            addon:Info("TOC Version: %s", tocVersion)
            addon:Info("Build Version: %s", buildVersion)
            addon:Info("Build Date: %s", buildDate)
        elseif command == "sessions" then
            if addon.StorageManager then
                local sessions = addon.StorageManager:GetRecentSessions(25)  -- Show all stored sessions
                addon:Info("=== Recent Combat Sessions (%d shown) ===", #sessions)
                for i, session in ipairs(sessions) do
                    local segments = session.isSegmented and session.segments and #session.segments or 1
                    local zoneInfo = "Unknown Zone"
                    if session.metadata then
                        if type(session.metadata.zone) == "string" then
                            zoneInfo = session.metadata.zone
                        elseif session.metadata.zone and session.metadata.zone.name then
                            zoneInfo = session.metadata.zone.name
                        end
                    end
                    addon:Info("  [%s] %s: %.1fs, %d events, %d segments (%s)", 
                        session.hash or "----",
                        session.id, 
                        session.duration or 0, 
                        session.eventCount or 0,
                        segments,
                        zoneInfo)
                end
                addon:Info("Use '/myui logs' to view full output")
            else
                addon:Error("StorageManager not loaded")
            end
        elseif command == "logs" or command == "logwindow" then
            if addon.MyLoggerWindow then
                addon.MyLoggerWindow:Toggle()
            else
                print("MyLoggerWindow not loaded")
            end
        elseif command:match("^loglevel%s+(.+)$") then
            local level = command:match("^loglevel%s+(.+)$"):upper()
            if addon.MyLogger then
                local success = addon.MyLogger:SetLevel(level)
                if success then
                    print(string.format("Log level set to: %s", level))
                    -- Save to database
                    addon.db.logLevel = level
                else
                    print(string.format("Invalid log level: %s", level))
                    print("Valid levels: OFF, PANIC, ERROR, WARN, INFO, DEBUG, TRACE")
                end
            else
                print("MyLogger not loaded")
            end
        elseif command == "loglevel" then
            if addon.MyLogger then
                local currentLevel = addon.MyLogger:GetLevel()
                local levelNames = {"OFF", "PANIC", "ERROR", "WARN", "INFO", "DEBUG", "TRACE"}
                addon:Info("Current log level: %s (%d)", levelNames[currentLevel + 1] or "UNKNOWN", currentLevel)
                addon:Info("Usage: /myui loglevel <level>")
                addon:Info("Valid levels: OFF, PANIC, ERROR, WARN, INFO, DEBUG, TRACE")
            else
                addon:Error("MyLogger not loaded")
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
            addon:Info("Use '/myui logs' to view detailed output")
        elseif command == "storagestats" then
            -- Show storage and memory analysis
            if addon.StorageManager then
                addon:Info("=== Storage Analysis ===")
                addon:Info("Storage Limits: 25 sessions max, 7 days retention, 8 MB memory limit")
                addon:Info("Priority Sessions: 10 (kept regardless of age)")
                
                local sessions = addon.StorageManager:GetAllSessions()
                addon:Info("Current Sessions: %d", #sessions)
                
                if #sessions > 0 then
                    local totalEvents = 0
                    for _, session in ipairs(sessions) do
                        totalEvents = totalEvents + (session.eventCount or 0)
                    end
                    addon:Info("Total Events: %d (avg %.0f per session)", totalEvents, totalEvents / #sessions)
                end
                
                local poolStats = addon.StorageManager:GetPoolStats()
                addon:Info("Table Pool: %d/%d (%.1f%% reuse)", 
                    poolStats.currentPoolSize, poolStats.maxPoolSize, poolStats.reuseRatio * 100)
                    
                local memoryMB = collectgarbage("count") / 1024
                addon:Info("Total Memory: %.2f MB", memoryMB)
            else
                addon:Error("StorageManager not loaded")
            end
        else
            print("MyUI Essential Commands:")
            print("  /myui - Toggle main window")
            print("  /myui logs - Toggle log viewer window")
            print("  /myui loglevel [level] - Show/set log level")
            print("  /myui browser - Toggle session browser")
            print("  /myui sessions - Show recent sessions")
            print("  /myui session <hash> - Show session details")
            print("  /myui memory - Show memory usage")
            print("  /myui storagestats - Show storage analysis")
            print("  /myui version - Show addon version")
        end
    end
end

-- Initialize the appropriate command set
function SlashCommands:Initialize()
    -- Use simple commands during modularization
    self:InitializeSimpleCommands()
    
    -- SlashCommands initialized
end