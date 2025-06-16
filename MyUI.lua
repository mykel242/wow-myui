-- MyUI.lua
-- Basic World of Warcraft UI Addon

-- Create addon namespace
local addonName, addon = ...

-- Force reload flag for development
if not addon.devMode then
    addon.devMode = true
end

-- Initialize addon
addon.frame = CreateFrame("Frame")

-- Development version tracking
addon.VERSION = "refactor-modularization-520cc10"
addon.BUILD_DATE = "2025-06-16-11:09"

-- Legacy debug flags removed - now using MyLogger system

-- Addon variables
addon.db = {}
addon.defaults = {
    enabled = true,
    -- showMinimap = false,
    -- minimapButtonAngle = 225, -- Default bottom-left position
    scale = 1.0,
    framePosition = nil,
    dpsWindowPosition = nil,
    showDPSWindow = false,
    hpsWindowPosition = nil,
    showHPSWindow = false,
    showMainWindow = false,
    enhancedLogging = true,
    trackAllParticipants = true,
    trackDamageTaken = true,
    trackGroupDamage = false, -- Disabled by default for performance
    maxEnhancedEvents = 1000,
    calculationMethod = "ROLLING_AVERAGE", -- Default calculation method
    -- Logging configuration
    logLevel = "OFF", -- OFF, ERROR, WARN, INFO, DEBUG, TRACE
    useLogChannel = false, -- Use chat channel for logging
    logFallbackToPrint = true -- Fallback to print() if channel fails
}

-- Logging shortcuts (MyLogger must be initialized first)
function addon:Error(...) self.MyLogger:Error(...) end
function addon:Warn(...) self.MyLogger:Warn(...) end  
function addon:Info(...) self.MyLogger:Info(...) end
function addon:Debug(...) self.MyLogger:Debug(...) end
function addon:Trace(...) self.MyLogger:Trace(...) end

-- Legacy DebugPrint for compatibility during transition
function addon:DebugPrint(...) self.MyLogger:Debug(...) end

-- Test function for new logging system
function addon:TestLogging()
    self:Error("This is an ERROR message")
    self:Warn("This is a WARN message") 
    self:Info("This is an INFO message")
    self:Debug("This is a DEBUG message")
    self:Trace("This is a TRACE message")
    self.MyLogger:DumpConfig()
end

-- Window focus management system
addon.FocusManager = {
    focusedWindow = nil,
    registeredWindows = {}
}

function addon.FocusManager:RegisterWindow(frame, pixelMeter, defaultStrata)
    if not frame then return end
    
    -- Set default strata (allow override for special windows like main config)
    defaultStrata = defaultStrata or "MEDIUM"
    frame:SetFrameStrata(defaultStrata)
    
    -- Store registration
    self.registeredWindows[frame] = {
        pixelMeter = pixelMeter,
        defaultStrata = defaultStrata
    }
    
    -- Propagate strata to children immediately
    self:PropagateStrataToChildren(frame, defaultStrata)
    
    -- Sync pixel meter strata if it exists
    if pixelMeter and pixelMeter.SyncStrataWithParent then
        pixelMeter:SyncStrataWithParent()
    end
    
    -- Hook focus events
    self:HookFocusEvents(frame)
end

function addon.FocusManager:HookFocusEvents(frame)
    -- Focus on drag start
    local originalDragStart = frame:GetScript("OnDragStart")
    frame:SetScript("OnDragStart", function(self)
        addon.FocusManager:SetFocus(self)
        if originalDragStart then
            originalDragStart(self)
        end
    end)
    
    -- Focus on mouse down
    local originalMouseDown = frame:GetScript("OnMouseDown")
    frame:SetScript("OnMouseDown", function(self, button)
        addon.FocusManager:SetFocus(self)
        if originalMouseDown then
            originalMouseDown(self, button)
        end
    end)
    
    -- Focus when shown
    local originalShow = frame:GetScript("OnShow")
    frame:SetScript("OnShow", function(self)
        addon.FocusManager:SetFocus(self)
        if originalShow then
            originalShow(self)
        end
    end)
    
    -- Lose focus when hidden
    local originalHide = frame:GetScript("OnHide")
    frame:SetScript("OnHide", function(self)
        if addon.FocusManager.focusedWindow == self then
            addon.FocusManager:ClearFocus()
        end
        if originalHide then
            originalHide(self)
        end
    end)
end

function addon.FocusManager:SetFocus(frame)
    -- Clear previous focus
    if self.focusedWindow and self.focusedWindow ~= frame then
        self:RevertWindowStrata(self.focusedWindow)
    end
    
    -- Set new focus
    self.focusedWindow = frame
    frame:SetFrameStrata("HIGH")
    
    -- Propagate strata to all child frames
    self:PropagateStrataToChildren(frame, "HIGH")
    
    -- Sync pixel meter strata
    local windowInfo = self.registeredWindows[frame]
    if windowInfo and windowInfo.pixelMeter and windowInfo.pixelMeter.SyncStrataWithParent then
        windowInfo.pixelMeter:SyncStrataWithParent()
    end
end

function addon.FocusManager:ClearFocus()
    if self.focusedWindow then
        self:RevertWindowStrata(self.focusedWindow)
        self.focusedWindow = nil
    end
end

function addon.FocusManager:RevertWindowStrata(frame)
    local windowInfo = self.registeredWindows[frame]
    if windowInfo then
        frame:SetFrameStrata(windowInfo.defaultStrata)
        
        -- Propagate strata to all child frames
        self:PropagateStrataToChildren(frame, windowInfo.defaultStrata)
        
        -- Sync pixel meter strata
        if windowInfo.pixelMeter and windowInfo.pixelMeter.SyncStrataWithParent then
            windowInfo.pixelMeter:SyncStrataWithParent()
        end
    end
end

-- Recursively propagate frame strata to all child frames
function addon.FocusManager:PropagateStrataToChildren(parentFrame, strata)
    if not parentFrame then return end
    
    -- Get all child frames
    local children = { parentFrame:GetChildren() }
    
    for _, child in ipairs(children) do
        if child and child.SetFrameStrata then
            child:SetFrameStrata(strata)
            -- Recursively apply to grandchildren
            self:PropagateStrataToChildren(child, strata)
        end
    end
end

-- Utility function to get table keys
function addon:GetTableKeys(tbl)
    local keys = {}
    if tbl then
        for k, _ in pairs(tbl) do
            table.insert(keys, tostring(k))
        end
    end
    return keys
end

-- Function to dump table contents (useful for debugging)
function addon:DumpTable(tbl, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)

    if not tbl then
        print(spacing .. "nil")
        return
    end

    for k, v in pairs(tbl) do
        if type(v) == "table" then
            print(spacing .. tostring(k) .. " = {")
            self:DumpTable(v, indent + 1)
            print(spacing .. "}")
        else
            print(spacing .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- Safe function wrapper for development
local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        print("Error in " .. addonName .. ": " .. tostring(result))
    end
    return success, result
end

-- Event handler function
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            SafeCall(addon.OnInitialize, addon)
        end
    elseif event == "PLAYER_LOGIN" then
        SafeCall(addon.OnEnable, addon)
    elseif event == "PLAYER_LOGOUT" then
        SafeCall(addon.OnDisable, addon)
    end
end

-- Register events
addon.frame:RegisterEvent("ADDON_LOADED")
addon.frame:RegisterEvent("PLAYER_LOGIN")
addon.frame:RegisterEvent("PLAYER_LOGOUT")
addon.frame:SetScript("OnEvent", OnEvent)

-- Initialize function
function addon:OnInitialize()
    -- Load saved variables or set defaults
    if MyUIDB == nil then
        MyUIDB = {}
    end

    -- Merge defaults with saved settings
    for key, value in pairs(self.defaults) do
        if MyUIDB[key] == nil then
            MyUIDB[key] = value
        end
    end

    self.db = MyUIDB

    -- CRITICAL: Initialize MyLogger first - everything else depends on it
    if not self.MyLogger then
        error(addonName .. ": MyLogger module not available - cannot continue")
    end
    
    -- Extract version hash for unique channel naming
    local versionHash = self.VERSION:match("%-([^%-]+)$") or "dev"
    
    self.MyLogger:Initialize({
        level = self.db.logLevel or "OFF",
        useChannel = self.db.useLogChannel or false,
        versionHash = versionHash,
        fallbackToPrint = self.db.logFallbackToPrint ~= false
    })

    -- Initialize core modules only (others disabled during modularization)
    -- 0. Unified calculator must be available before combat data
    -- (UnifiedCalculator is loaded via file inclusion - no init needed)
    
    -- 0.5. Initialize MyTimestampManager first (single source of truth for timing)
    if self.MyTimestampManager then
        self.MyTimestampManager:Initialize()
    end
    
    --[[
    -- 1. Initialize CombatEventLogger (DISABLED - replaced by SimpleCombatDetector)
    if self.CombatEventLogger then
        self.CombatEventLogger:Initialize()
    end
    --]]
    
    -- 1. Initialize MySimpleCombatDetector (new reliable combat detection)
    if self.MySimpleCombatDetector then
        self.MySimpleCombatDetector:Initialize()
    end
    
    -- 2. Initialize MetadataCollector (context gathering)
    if self.MetadataCollector then
        self.MetadataCollector:Initialize()
    end
    
    -- 2.5. Initialize GUIDResolver (name resolution and caching)
    if self.GUIDResolver then
        self.GUIDResolver:Initialize()
    end
    
    -- 3. Initialize StorageManager (memory-efficient storage)
    if self.StorageManager then
        self.StorageManager:Initialize()
    end
    
    -- 4. Initialize CombatLogViewer (basic UI)
    if self.CombatLogViewer then
        self.CombatLogViewer:Initialize()
    end
    
    -- 5. Initialize ExportDialog (export functionality)
    if self.ExportDialog then
        self.ExportDialog:Initialize()
    end
    
    -- 6. Initialize SessionBrowser (session table view)
    if self.SessionBrowser then
        self.SessionBrowser:Initialize()
    end
    
    -- 7. Initialize SettingsWindow
    if self.SettingsWindow then
        self.SettingsWindow:Initialize()
    end
    
    --[[
    OLD COMBAT TRACKING MODULES - DISABLED IN FAVOR OF MySimpleCombatDetector
    
    -- 1. Core combat tracking first
    if self.CombatData then
        self.CombatData:Initialize()
    end

    -- 2. Timeline tracker (depends on CombatData)
    if self.TimelineTracker then
        self.TimelineTracker:Initialize()
    end

    -- 3. Enhanced logger (depends on CombatData)
    if self.EnhancedCombatLogger then
        self.EnhancedCombatLogger:Initialize()
    end

    -- 4. Entity blacklist system
    if self.EntityBlacklist then
        self.EntityBlacklist:Initialize()
    end

    -- 5. Content detection
    if self.ContentDetection then
        self.ContentDetection:Initialize()
    end

    -- 6. Session manager (depends on others)
    if self.SessionManager then
        self.SessionManager:Initialize()
    end

    -- 6. Main combat tracker (coordinator)
    if self.CombatTracker then
        self.CombatTracker:Initialize()
    end

    -- 7. UI windows
    if self.DPSWindow then
        self.DPSWindow:Initialize()
    end
    if self.HPSWindow then
        self.HPSWindow:Initialize()
    end
    
    -- 8. Configuration interfaces
    if self.CalculationConfig then
        self.CalculationConfig:Initialize()
    end

    -- Load session history for current character/spec
    if self.SessionManager then
        self.SessionManager:InitializeSessionHistory()
    end

    -- Debug enhanced logging status
    if self.EnhancedCombatLogger then
        local status = self.EnhancedCombatLogger:GetStatus()
        self:Debug("Enhanced logging status: initialized=%s, tracking=%s, participants=%d",
            tostring(status.isInitialized), tostring(status.isTracking), status.participantCount)
    end
    --]]
    
    -- Initialize simplified slash commands
    if self.SlashCommands then
        self.SlashCommands:Initialize()
    end
end

function addon:OnEnable()
    if self.db.enabled then
        self:CreateMainFrame()

        -- Debug the state
        self:Debug("showMainWindow value: %s", tostring(self.db.showMainWindow))

        if self.db.showMainWindow then
            self:Debug("Showing main window")
            self.mainFrame:Show()
        else
            self:Debug("Not showing main window")
        end

        --[[
        DISABLED DURING MODULARIZATION - PRESERVE FOR RE-ENABLE
        
        -- Restore other windows...
        if self.db.showDPSWindow and self.DPSWindow then
            self.DPSWindow:Show()
        end

        if self.db.showHPSWindow and self.HPSWindow then
            self.HPSWindow:Show()
        end
        --]]

        self:Info("%s is now active!", addonName)
    end
end

-- Disable function
function addon:OnDisable()
    -- Save frame position before logout
    if self.mainFrame then
        if self.mainFrame:IsShown() then
            local point, relativeTo, relativePoint, xOfs, yOfs = self.mainFrame:GetPoint()
            self.db.framePosition = {
                point = point,
                relativePoint = relativePoint,
                xOffset = xOfs,
                yOffset = yOfs
            }
        end
        self.db.showMainWindow = self.mainFrame:IsShown()
    end

    -- Ensure session data is saved
    if self.StorageManager then
        self.StorageManager:SaveToSavedVariables()
    end
    
    -- Save GUID cache
    if self.GUIDResolver then
        self.GUIDResolver:SaveToSavedVariables()
    end
    
    -- Cleanup MyLogger channel
    if self.MyLogger then
        self.MyLogger:CleanupChannel()
    end

    --[[
    DISABLED DURING MODULARIZATION - PRESERVE FOR RE-ENABLE
    
    -- Save visibility states for all windows
    if self.DPSWindow and self.DPSWindow.frame then
        self.db.showDPSWindow = self.DPSWindow.frame:IsShown()
    end

    if self.HPSWindow and self.HPSWindow.frame then
        self.db.showHPSWindow = self.HPSWindow.frame:IsShown()
    end
    --]]
end

-- Toggle main window function
function addon:ToggleMainWindow()
    if not self.mainFrame then
        self:CreateMainFrame()
    end

    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        self.db.showMainWindow = false
        print("Main window hidden")
    else
        self.mainFrame:Show()
        self.db.showMainWindow = true
        print("Main window shown")
    end
end

-- Update status display (simplified)
function addon:UpdateStatusDisplay()
    if not self.mainFrame or not self.mainFrame.debugText then
        return
    end

    local debugStatus = self.DEBUG and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    self.mainFrame.debugText:SetText("Debug: " .. debugStatus)
end

-- Simplified main window (tool launcher)
function addon:CreateMainFrame()
    if self.mainFrame then return end

    -- Use default Warcraft UI style as requested
    local frame = CreateFrame("Frame", addonName .. "MainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(350, 250)
    frame:SetPoint("CENTER")

    -- Set title text
    frame.TitleText:SetText("MyUI2 - Combat Logger")

    -- Position and dragging (handled by BasicFrameTemplate)
    if self.db.framePosition then
        frame:SetPoint(
            self.db.framePosition.point or "CENTER",
            UIParent,
            self.db.framePosition.relativePoint or "CENTER",
            self.db.framePosition.xOffset or 0,
            self.db.framePosition.yOffset or 0
        )
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        addon.db.framePosition = {
            point = point,
            relativePoint = relativePoint,
            xOffset = xOfs,
            yOffset = yOfs
        }
    end)
    
    -- Override close button behavior
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
        addon.db.showMainWindow = false
    end)

    -- === STATUS PANEL ===
    local statusPanel = CreateFrame("Frame", nil, frame)
    statusPanel:SetSize(310, 60)
    statusPanel:SetPoint("TOP", frame, "TOP", 0, -30)

    local statusTitle = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusTitle:SetPoint("TOP", statusPanel, "TOP", 0, -5)
    statusTitle:SetText("Addon Status")

    local debugText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugText:SetPoint("TOPLEFT", statusPanel, "TOPLEFT", 10, -25)
    debugText:SetText("Debug: OFF")
    frame.debugText = debugText

    local versionText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("TOPRIGHT", statusPanel, "TOPRIGHT", -10, -25)
    versionText:SetText("Version: " .. addon.VERSION:sub(-7))

    local statusText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("BOTTOM", statusPanel, "BOTTOM", 0, 5)
    statusText:SetText("Simplified Mode (Modularization in Progress)")
    statusText:SetTextColor(1, 0.8, 0.2)
    frame.statusText = statusText

    -- === TOOL LAUNCHER PANEL ===
    local toolPanel = CreateFrame("Frame", nil, frame)
    toolPanel:SetSize(310, 120)
    toolPanel:SetPoint("TOP", statusPanel, "BOTTOM", 0, -10)

    local toolTitle = toolPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toolTitle:SetPoint("TOP", toolPanel, "TOP", 0, -5)
    toolTitle:SetText("Combat Analysis Tools")

    -- Combat Logger button
    local loggerBtn = CreateFrame("Button", nil, toolPanel, "GameMenuButtonTemplate")
    loggerBtn:SetSize(140, 25)
    loggerBtn:SetPoint("TOPLEFT", toolPanel, "TOPLEFT", 10, -30)
    loggerBtn:SetText("Combat Logger")
    loggerBtn:SetScript("OnClick", function()
        if addon.CombatLogViewer then
            addon.CombatLogViewer:Show()
        else
            print("Combat Log Viewer not available")
        end
    end)

    -- Raw Data Viewer button
    local rawDataBtn = CreateFrame("Button", nil, toolPanel, "GameMenuButtonTemplate")
    rawDataBtn:SetSize(140, 25)
    rawDataBtn:SetPoint("TOPRIGHT", toolPanel, "TOPRIGHT", -10, -30)
    rawDataBtn:SetText("Raw Data Viewer")
    rawDataBtn:SetScript("OnClick", function()
        if addon.StorageManager then
            local sessions = addon.StorageManager:GetAllSessions()
            print(string.format("=== Raw Data Summary ==="))
            print(string.format("Total Sessions: %d", #sessions))
            
            for i, session in ipairs(sessions) do
                print(string.format("Session %d: %s", i, session.id))
                print(string.format("  Duration: %.1fs, Events: %d", 
                    session.duration or 0, session.eventCount or 0))
                if session.metadata and session.metadata.zone then
                    print(string.format("  Zone: %s", session.metadata.zone.name or "Unknown"))
                end
                if i >= 5 then
                    print(string.format("... and %d more sessions", #sessions - 5))
                    break
                end
            end
            print("Use '/myui sessions' for recent sessions")
            print("Use Combat Logger for detailed event view")
        else
            print("StorageManager not available")
        end
    end)

    -- Session Browser button
    local sessionBtn = CreateFrame("Button", nil, toolPanel, "GameMenuButtonTemplate")
    sessionBtn:SetSize(140, 25)
    sessionBtn:SetPoint("TOPLEFT", toolPanel, "TOPLEFT", 10, -65)
    sessionBtn:SetText("Session Browser")
    sessionBtn:SetScript("OnClick", function()
        if addon.SessionBrowser then
            addon.SessionBrowser:Show()
        else
            print("Session Browser not available")
        end
    end)

    -- Settings button
    local settingsBtn = CreateFrame("Button", nil, toolPanel, "GameMenuButtonTemplate")
    settingsBtn:SetSize(140, 25)
    settingsBtn:SetPoint("TOPRIGHT", toolPanel, "TOPRIGHT", -10, -65)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function()
        if addon.SettingsWindow then
            addon.SettingsWindow:Show()
        else
            print("Settings window not available")
        end
    end)

    -- === FOOTER ===
    local footer = toolPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOM", toolPanel, "BOTTOM", 0, 5)
    footer:SetText("Build: " .. addon.BUILD_DATE)
    footer:SetTextColor(0.7, 0.7, 0.7)

    self.mainFrame = frame
    frame:SetScale(self.db.scale)
    frame:Hide()

    -- No complex update timer needed for simplified launcher
    self:Debug("Simplified main window created")
end

-- Simplified update for launcher window
function addon:UpdateMainWindow()
    if not self.mainFrame or not self.mainFrame:IsShown() then return end

    -- Update debug status
    if self.mainFrame.debugText then
        local debugStatus = self.DEBUG and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        self.mainFrame.debugText:SetText("Debug: " .. debugStatus)
    end
end

--[[
DISABLED DURING MODULARIZATION - PRESERVE FOR RE-ENABLE
Complex session table update removed with simplified UI
--]]

--[[
DISABLED DURING MODULARIZATION - PRESERVE FOR RE-ENABLE
Complex performance chart update removed with simplified UI
--]]

--[[
DISABLED DURING MODULARIZATION - PRESERVE FOR RE-ENABLE
Legacy slash command handler moved to src/commands/SlashCommands.lua
Simple commands now handled by SlashCommands module
--]]
