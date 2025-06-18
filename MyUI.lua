-- MyUI.lua
-- Basic World of Warcraft UI Addon

-- Create addon namespace
local addonName, addon = ...

-- Expose addon globally for debugging (optional)
_G.MyUI2 = addon

-- Force reload flag for development
if not addon.devMode then
    addon.devMode = true
end

-- Initialize addon
addon.frame = CreateFrame("Frame")

-- Development version tracking
addon.VERSION = "feature-generalized-virtual-scrolling-f00a449"
addon.BUILD_DATE = "2025-06-18-17:44"

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
    logLevel = "WARN", -- OFF, ERROR, WARN, INFO, DEBUG, TRACE
    logFallbackToPrint = false -- Don't print to chat (except PANIC)
}

-- Logging shortcuts (MyLogger must be initialized first)
function addon:Panic(...) self.MyLogger:Panic(...) end
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

-- Window focus management system with strata and frame level coordination
addon.FocusManager = {
    focusedWindow = nil,
    registeredWindows = {},
    
    -- Frame level assignments for precise layering control
    frameLevels = {
        -- Base levels for different window types (conservative spacing)
        sessionBrowser = 1,
        combatLogViewer = 2,
        loggerWindow = 3,
        settingsWindow = 4,
        mainWindow = 5,
        
        -- Special levels
        focusBoost = 10,   -- Small boost for focused windows
        dialogBase = 20,   -- Modest base for dialog windows
    },
    
    -- Strata assignments (simpler now with frame levels handling conflicts)
    strataAssignments = {
        -- Most windows on MEDIUM for consistency
        default = "MEDIUM",
        dialog = "DIALOG",
        tooltip = "TOOLTIP"
    }
}

function addon.FocusManager:RegisterWindow(frame, pixelMeter, defaultStrata)
    if not frame then return end
    
    -- Assign strata and frame level for precise layering
    local assignedStrata, frameLevel = self:AssignStrataAndLevel(frame, defaultStrata)
    
    -- Store registration
    self.registeredWindows[frame] = {
        pixelMeter = pixelMeter,
        defaultStrata = assignedStrata,
        defaultFrameLevel = frameLevel,
        requestedStrata = defaultStrata or "MEDIUM" -- Track what was originally requested
    }
    
    -- Set up initial element management for the window
    self:ManageWindowElements(frame, frameLevel, false)
    
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
        self:RevertWindowLevel(self.focusedWindow)
    end
    
    -- Set new focus
    self.focusedWindow = frame
    
    -- Boost the frame level for focused window
    local windowInfo = self.registeredWindows[frame]
    if windowInfo then
        local boostedLevel = windowInfo.defaultFrameLevel + self.frameLevels.focusBoost
        frame:SetFrameLevel(boostedLevel)
        
        -- Manage specific child elements (like close buttons)
        self:ManageWindowElements(frame, boostedLevel, true)
        
        -- Also ensure previously focused window's elements are properly managed
        for registeredFrame, _ in pairs(self.registeredWindows) do
            if registeredFrame ~= frame then
                local otherWindowInfo = self.registeredWindows[registeredFrame]
                self:ManageWindowElements(registeredFrame, otherWindowInfo.defaultFrameLevel, false)
            end
        end
        
        -- Sync pixel meter if needed
        if windowInfo.pixelMeter and windowInfo.pixelMeter.SyncStrataWithParent then
            windowInfo.pixelMeter:SyncStrataWithParent()
        end
        
        addon:Debug("FocusManager: %s focused, boosted to level %d", 
            frame:GetName() or "Unknown", boostedLevel)
    end
end

function addon.FocusManager:ClearFocus()
    if self.focusedWindow then
        self:RevertWindowLevel(self.focusedWindow)
        self.focusedWindow = nil
    end
end

function addon.FocusManager:RevertWindowLevel(frame)
    local windowInfo = self.registeredWindows[frame]
    if windowInfo then
        frame:SetFrameLevel(windowInfo.defaultFrameLevel)
        
        -- Manage child elements for unfocused state
        self:ManageWindowElements(frame, windowInfo.defaultFrameLevel, false)
        
        -- Sync pixel meter if needed
        if windowInfo.pixelMeter and windowInfo.pixelMeter.SyncStrataWithParent then
            windowInfo.pixelMeter:SyncStrataWithParent()
        end
        
        addon:Debug("FocusManager: %s focus removed, reverted to level %d", 
            frame:GetName() or "Unknown", windowInfo.defaultFrameLevel)
    end
end

-- Assign strata and frame level for precise window layering
function addon.FocusManager:AssignStrataAndLevel(frame, requestedStrata)
    local frameName = frame:GetName() or "Unknown"
    
    -- Determine strata
    local assignedStrata
    if requestedStrata == "DIALOG" or requestedStrata == "TOOLTIP" or 
       frameName:find("Settings") or frameName:find("Main") then
        assignedStrata = self.strataAssignments.dialog
    else
        assignedStrata = self.strataAssignments.default
    end
    
    -- Determine frame level based on window type
    local frameLevel
    if frameName:find("SessionBrowser") then
        frameLevel = self.frameLevels.sessionBrowser
    elseif frameName:find("CombatLogViewer") then
        frameLevel = self.frameLevels.combatLogViewer
    elseif frameName:find("Logger") then
        frameLevel = self.frameLevels.loggerWindow
    elseif frameName:find("Settings") or frameName:find("Config") then
        frameLevel = self.frameLevels.dialogBase + self.frameLevels.settingsWindow
    elseif frameName:find("Main") then
        frameLevel = self.frameLevels.dialogBase + self.frameLevels.mainWindow
    else
        -- Default level for unknown windows
        frameLevel = 15
    end
    
    -- Apply strata and level
    frame:SetFrameStrata(assignedStrata)
    frame:SetFrameLevel(frameLevel)
    
    addon:Debug("FocusManager: %s assigned strata=%s, level=%d (requested strata=%s)", 
        frameName, assignedStrata, frameLevel, requestedStrata or "default")
    
    return assignedStrata, frameLevel
end

-- Selectively manage frame levels for specific child elements
function addon.FocusManager:ManageWindowElements(parentFrame, frameLevel, isFocused)
    if not parentFrame then return end
    
    -- Find and manage close button specifically
    local closeButton = parentFrame.CloseButton
    if closeButton and closeButton.SetFrameLevel then
        if isFocused then
            -- Focused window's close button should be on top
            closeButton:SetFrameLevel(frameLevel + 1)
        else
            -- Unfocused window's close button at normal level
            closeButton:SetFrameLevel(frameLevel)
        end
    end
    
    -- Could add other specific element management here if needed
end

-- Get information about the focus management system
function addon.FocusManager:GetStatus()
    local status = {
        focusedWindow = self.focusedWindow and self.focusedWindow:GetName() or "None",
        registeredWindowCount = 0,
        windowList = {}
    }
    
    for frame, info in pairs(self.registeredWindows) do
        status.registeredWindowCount = status.registeredWindowCount + 1
        table.insert(status.windowList, {
            frame = frame, -- Include frame reference for debug
            name = frame:GetName() or "Unknown",
            defaultStrata = info.defaultStrata,
            currentStrata = frame:GetFrameStrata(),
            isShown = frame:IsShown(),
            hasFocus = (self.focusedWindow == frame)
        })
    end
    
    return status
end

-- Debug function to print focus manager status
function addon.FocusManager:DebugStatus()
    local status = self:GetStatus()
    addon:Debug("=== FocusManager Status ===")
    addon:Debug("Focused Window: %s", status.focusedWindow)
    addon:Debug("Registered Windows: %d", status.registeredWindowCount)
    
    -- Show frame level assignments
    addon:Debug("Frame Level Assignments:")
    for name, level in pairs(self.frameLevels) do
        addon:Debug("  %s: %d", name, level)
    end
    
    addon:Debug("Window Details:")
    for _, window in ipairs(status.windowList) do
        local windowInfo = self.registeredWindows[window.frame]
        local currentLevel = window.frame:GetFrameLevel()
        local defaultLevel = windowInfo and windowInfo.defaultFrameLevel or "unknown"
        local requested = windowInfo and windowInfo.requestedStrata or "unknown"
        
        addon:Debug("  %s: strata=%s, level=%d (default=%s), shown=%s, focus=%s", 
            window.name, window.currentStrata, currentLevel, tostring(defaultLevel),
            tostring(window.isShown), tostring(window.hasFocus))
    end
    addon:Debug("=== End Status ===")
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
        fallbackToPrint = self.db.logFallbackToPrint ~= false,
        savedVariables = self.db -- Pass reference for persistent logging
    })
    
    -- Initialize MyLoggerWindow and register with logger
    if self.MyLoggerWindow then
        self.MyLoggerWindow:RegisterWithLogger()
        self:Debug("MyLoggerWindow initialized and registered")
    end

    -- Initialize core modules with logger injection
    -- 0. Unified calculator must be available before combat data
    -- (UnifiedCalculator is loaded via file inclusion - no init needed)
    
    -- 0.5. Initialize MyTimestampManager first (single source of truth for timing)
    if self.MyTimestampManager then
        self.MyTimestampManager:Initialize(self.MyLogger)
        self:Debug("MyTimestampManager initialized with logger injection")
    end
    
    --[[
    -- 1. Initialize CombatEventLogger (DISABLED - replaced by SimpleCombatDetector)
    if self.CombatEventLogger then
        self.CombatEventLogger:Initialize()
    end
    --]]
    
    -- 1. Initialize MySimpleCombatDetector (new reliable combat detection)
    if self.MySimpleCombatDetector then
        self.MySimpleCombatDetector:Initialize(self.MyLogger)
        self:Debug("MySimpleCombatDetector initialized with logger injection")
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
    
    -- 4. Initialize CombatLogViewer (basic UI) - DISABLED
    --[[
    if self.CombatLogViewer then
        self.CombatLogViewer:Initialize()
    end
    --]]
    
    -- 5. Initialize ExportDialog (export functionality)
    if self.ExportDialog then
        self.ExportDialog:Initialize()
    end
    
    -- 6. Initialize SessionBrowser (session table view)
    if self.SessionBrowser then
        self.SessionBrowser:Initialize()
    end
    
    -- 7. Initialize SettingsWindow - DISABLED
    --[[
    if self.SettingsWindow then
        self.SettingsWindow:Initialize()
    end
    --]]
    
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
    
    -- MyLogger cleanup not needed (no channels)

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
        self:Info("Main window shown")
    end
end

-- Update status display (simplified)
function addon:UpdateStatusDisplay()
    -- Status display no longer needed - window is simplified
end

-- Simplified main window (tool launcher)
function addon:CreateMainFrame()
    if self.mainFrame then return end

    -- Use default Warcraft UI style as requested
    local frame = CreateFrame("Frame", addonName .. "MainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(350, 200)
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
    statusPanel:SetSize(310, 40)
    statusPanel:SetPoint("TOP", frame, "TOP", 0, -30)

    local statusTitle = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusTitle:SetPoint("TOP", statusPanel, "TOP", 0, -5)
    statusTitle:SetText("Addon Status")

    local versionText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    versionText:SetPoint("CENTER", statusPanel, "CENTER", 0, -15)
    versionText:SetText("Version: " .. addon.VERSION:sub(-7))
    versionText:SetTextColor(0.8, 0.8, 0.8)

    -- === TOOL LAUNCHER PANEL ===
    local toolPanel = CreateFrame("Frame", nil, frame)
    toolPanel:SetSize(310, 100)
    toolPanel:SetPoint("TOP", statusPanel, "BOTTOM", 0, -10)

    local toolTitle = toolPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toolTitle:SetPoint("TOP", toolPanel, "TOP", 0, -5)
    toolTitle:SetText("Combat Analysis Tools")

    -- Combat Logger button (DISABLED)
    --[[
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
    --]]

    -- MyLogger Window button (centered on top row)
    local myLoggerBtn = CreateFrame("Button", nil, toolPanel, "GameMenuButtonTemplate")
    myLoggerBtn:SetSize(160, 25)
    myLoggerBtn:SetPoint("TOP", toolPanel, "TOP", 0, -35)
    myLoggerBtn:SetText("MyLogger Window")
    myLoggerBtn:SetScript("OnClick", function()
        if addon.MyLoggerWindow then
            addon.MyLoggerWindow:Show()
        else
            print("MyLogger Window not available")
        end
    end)

    -- Session Browser button (centered on bottom row)
    local sessionBtn = CreateFrame("Button", nil, toolPanel, "GameMenuButtonTemplate")
    sessionBtn:SetSize(160, 25)
    sessionBtn:SetPoint("TOP", myLoggerBtn, "BOTTOM", 0, -10)
    sessionBtn:SetText("Session Browser")
    sessionBtn:SetScript("OnClick", function()
        if addon.SessionBrowser then
            addon.SessionBrowser:Show()
        else
            print("Session Browser not available")
        end
    end)

    -- Settings button (DISABLED)
    --[[
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
    --]]

    -- === FOOTER ===
    local footer = toolPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOM", toolPanel, "BOTTOM", 0, 5)
    footer:SetText("Build: " .. addon.BUILD_DATE)
    footer:SetTextColor(0.7, 0.7, 0.7)

    self.mainFrame = frame
    frame:SetScale(self.db.scale)
    frame:Hide()
    
    -- Register with FocusManager for proper strata coordination
    if self.FocusManager then
        self.FocusManager:RegisterWindow(frame, nil, "DIALOG")
    end

    -- No complex update timer needed for simplified launcher
    self:Debug("Simplified main window created")
end

-- Simplified update for launcher window
function addon:UpdateMainWindow()
    -- Main window is now static - no dynamic updates needed
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
