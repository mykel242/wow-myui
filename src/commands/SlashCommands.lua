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
        elseif command == "settings" then
            if addon.SettingsWindow then
                addon.SettingsWindow:Show()
            else
                print("Settings window not available")
            end
        elseif command == "timestamps" then
            if addon.MyTimestampManager then
                print(addon.MyTimestampManager:GetDebugSummary())
            else
                print("MyTimestampManager not loaded")
            end
        elseif command == "logger" then
            if addon.CombatEventLogger then
                print(addon.CombatEventLogger:GetDebugSummary())
            else
                print("CombatEventLogger not loaded")
            end
        elseif command == "rawdata" then
            if addon.CombatEventLogger then
                local events = addon.CombatEventLogger:GetCurrentEvents()
                print(string.format("Current combat raw data: %d events", #events))
                if #events > 0 then
                    print("Latest 3 events:")
                    for i = math.max(1, #events - 2), #events do
                        local event = events[i]
                        print(string.format("  [%s] %s: %s -> %s", 
                            event.subevent,
                            event.sourceName or "?",
                            event.destName or "?",
                            table.concat(event.args or {}, ",")))
                    end
                end
            else
                print("CombatEventLogger not loaded")
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
        elseif command == "sessions" then
            if addon.StorageManager then
                local sessions = addon.StorageManager:GetRecentSessions(5)
                print(string.format("Recent combat sessions (%d shown):", #sessions))
                for i, session in ipairs(sessions) do
                    print(string.format("  %s: %.1fs, %d events (%s)", 
                        session.id, 
                        session.duration or 0, 
                        session.eventCount or 0,
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
        elseif command == "combatdetection" then
            if addon.CombatTracker then
                addon.CombatTracker:DebugEnhancedCombatDetection()
            else
                print("CombatTracker not loaded")
            end
        elseif command:match("^guid%s+(.+)$") then
            local guid = command:match("^guid%s+(.+)$")
            if addon.GUIDResolver then
                local name = addon.GUIDResolver:ResolveGUID(guid)
                local cached = addon.GUIDResolver:GetCachedName(guid)
                print(string.format("GUID: %s", guid))
                print(string.format("Resolved Name: %s", name))
                print(string.format("Cached: %s", cached and "Yes" or "No"))
            else
                print("GUIDResolver not loaded")
            end
        elseif command == "viewer" then
            if addon.CombatLogViewer then
                addon.CombatLogViewer:Toggle()
            else
                print("CombatLogViewer not loaded")
            end
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
        elseif command == "browser" then
            if addon.SessionBrowser then
                addon.SessionBrowser:Toggle()
            else
                print("SessionBrowser not loaded")
            end
        elseif command:match("^session%s+(.+)$") then
            local sessionId = command:match("^session%s+(.+)$")
            if addon.StorageManager then
                local session = addon.StorageManager:GetSession(sessionId)
                if session then
                    print(string.format("=== Session Details: %s ===", sessionId))
                    print(string.format("Duration: %.1fs", session.duration or 0))
                    print(string.format("Events: %d", session.eventCount or 0))
                    if session.metadata and session.metadata.zone then
                        print(string.format("Zone: %s", session.metadata.zone.name or "Unknown"))
                    end
                    if session.events then
                        print("Latest 5 events:")
                        local startIndex = math.max(1, #session.events - 4)
                        for i = startIndex, #session.events do
                            local event = session.events[i]
                            print(string.format("  [%.3f] %s: %s -> %s", 
                                event.realTime or 0,
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
            print("  /myui settings - Open settings panel")
            print("  /myui timestamps - Show MyTimestampManager debug info")
            print("")
            print("New Tools (Active):")
            print("  /myui logger - Combat event logger status")
            print("  /myui rawdata - Current combat raw data")
            print("  /myui metadata - Current context metadata")
            print("  /myui storage - Storage manager status")
            print("  /myui testwarning - Test storage warning system")
            print("  /myui sessions - Recent combat sessions")
            print("  /myui session <id> - Show detailed session data")
            print("  /myui counters - Show session counter status")
            print("  /myui guids - Show GUID resolver status")
            print("  /myui guid <guid> - Resolve specific GUID")
            print("  /myui combatdetection - Debug enhanced combat detection")
            print("  /myui browser - Toggle session browser (table view)")
            print("  /myui viewer - Toggle combat log viewer window")
            print("  /myui export - Open session browser for export")
            print("  /myui logchannel - Join logger chat channel")
            print("  /myui leavechannel - Leave logger chat channel")
            print("  /myui testchannel - Send test message to logger channel")
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