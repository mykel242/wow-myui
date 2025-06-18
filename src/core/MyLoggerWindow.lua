-- MyLoggerWindow.lua
-- Dedicated log viewer window for MyLogger
--
-- HYBRID PERFORMANCE SYSTEM:
-- - COMBAT MODE: Memory-only logging with zero display updates during combat
-- - MANUAL CONTROLS: Pause/Resume and "Refresh Now" buttons for user control
-- - LIGHTWEIGHT MODE: FontString display for minimal overhead (if needed)
-- - FULL MODE: Normal EditBox with virtual scrolling when out of combat
-- - BUFFERED DISPLAY: Shows "X new messages" counter during paused states
-- - Automatic mode switching based on combat state with manual override options

local addonName, addon = ...

-- =============================================================================
-- LOGGER WINDOW MODULE
-- =============================================================================

local MyLoggerWindow = {}
addon.MyLoggerWindow = MyLoggerWindow

-- =============================================================================
-- STATIC POPUPS
-- =============================================================================

StaticPopupDialogs["MYLOGGER_CLEAR_CONFIRM"] = {
    text = "Clear all logs?\n\nThis will clear both current session logs and saved persistent logs.",
    button1 = "Clear All",
    button2 = "Cancel",
    OnAccept = function()
        MyLoggerWindow:ClearAllLogs()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- =============================================================================
-- CONSTANTS AND CONFIGURATION
-- =============================================================================

local WINDOW_WIDTH = 600
local WINDOW_HEIGHT = 400
local LOG_ENTRY_HEIGHT = 16
local MAX_VISIBLE_LOGS = math.floor((WINDOW_HEIGHT - 100) / LOG_ENTRY_HEIGHT)

-- Performance configuration for hybrid combat approach
local PERFORMANCE_CONFIG = {
    REFRESH_THROTTLE_MS = 250,     -- Normal refresh rate when not in combat
    BATCH_SIZE = 20,               -- Process up to 20 entries per batch
    MAX_PENDING_ENTRIES = 500,     -- Increased for combat memory buffering
    BUSY_THRESHOLD = 5,            -- Consider "busy" if 5+ entries in 1 second
    COMBAT_MEMORY_ONLY = true,     -- During combat: memory-only, no display updates
    MAX_COMBAT_BUFFER = 1000,      -- Maximum messages to buffer during combat
}

-- Filter types
local FILTER_TYPES = {
    ALL = "All",
    PANIC = "Panic",
    ERROR = "Errors", 
    WARN = "Warnings",
    INFO = "Info",
    DEBUG = "Debug",
    TRACE = "Trace"
}

-- =============================================================================
-- UI ELEMENTS
-- =============================================================================

local logWindow = nil
local logScrollFrame = nil
local logContentFrame = nil
local logLightweightFrame = nil  -- FontString for lightweight display
local logStatusFrame = nil       -- Status display during combat/pause
local logEntries = {}
local filterButtons = {}
local currentFilter = "ALL"
local copyEditBox = nil
local isRefreshing = false

-- Performance tracking and hybrid display state
local performanceState = {
    lastRefreshTime = 0,
    pendingEntries = {},
    recentEntryTimes = {},
    refreshTimer = nil,
    isBusyPeriod = false,
    inCombat = false,
    combatStartTime = 0,
    combatBuffer = {},          -- Messages stored during combat
    isPaused = false,           -- Manual pause state
    newMessageCount = 0,        -- Count of unprocessed messages
    displayMode = "full"        -- "full", "lightweight", "paused"
}

-- =============================================================================
-- PERFORMANCE OPTIMIZATION FUNCTIONS
-- =============================================================================

-- Update combat state and display mode
local function UpdateCombatState()
    local inCombat = UnitAffectingCombat("player")
    if inCombat and not performanceState.inCombat then
        performanceState.inCombat = true
        performanceState.combatStartTime = GetTime()
        if PERFORMANCE_CONFIG.COMBAT_MEMORY_ONLY and not performanceState.isPaused then
            performanceState.displayMode = "paused"
            MyLoggerWindow:UpdateDisplayMode()
        end
    elseif not inCombat and performanceState.inCombat then
        performanceState.inCombat = false
        if performanceState.displayMode == "paused" and not performanceState.isPaused then
            performanceState.displayMode = "full"
            MyLoggerWindow:UpdateDisplayMode()
        end
    end
end

-- Check if we're in a busy logging period
local function IsBusyPeriod()
    local currentTime = GetTime()
    local recentCount = 0
    
    -- Count entries in the last second
    for i = #performanceState.recentEntryTimes, 1, -1 do
        local entryTime = performanceState.recentEntryTimes[i]
        if currentTime - entryTime <= 1.0 then
            recentCount = recentCount + 1
        else
            -- Remove old entries
            table.remove(performanceState.recentEntryTimes, i)
        end
    end
    
    return recentCount >= PERFORMANCE_CONFIG.BUSY_THRESHOLD
end

-- Process pending entries in batches
local function ProcessPendingEntries()
    if #performanceState.pendingEntries == 0 then
        return
    end
    
    -- Use larger batch size during combat for better performance
    local batchSize = performanceState.inCombat and PERFORMANCE_CONFIG.COMBAT_BATCH_SIZE or PERFORMANCE_CONFIG.BATCH_SIZE
    local processCount = math.min(batchSize, #performanceState.pendingEntries)
    
    for i = 1, processCount do
        local entry = table.remove(performanceState.pendingEntries, 1)
        if entry then
            table.insert(logEntries, entry)
        end
    end
    
    -- Keep only last 500 total entries to prevent memory issues
    if #logEntries > 500 then
        local removeCount = #logEntries - 500
        for i = 1, removeCount do
            table.remove(logEntries, 1)
        end
    end
end

-- Schedule a throttled refresh
local function ScheduleThrottledRefresh()
    if performanceState.refreshTimer then
        return -- Already scheduled
    end
    
    -- Use longer delay during combat for better performance
    local delay = performanceState.inCombat and (PERFORMANCE_CONFIG.COMBAT_THROTTLE_MS / 1000) or (PERFORMANCE_CONFIG.REFRESH_THROTTLE_MS / 1000)
    
    performanceState.refreshTimer = C_Timer.After(delay, function()
        performanceState.refreshTimer = nil
        if logWindow and logWindow:IsVisible() then
            ProcessPendingEntries()
            MyLoggerWindow:RefreshLogs()
        end
    end)
end

-- =============================================================================
-- WINDOW CREATION
-- =============================================================================

function MyLoggerWindow:CreateWindow()
    if logWindow then return end
    
    -- Main window frame
    logWindow = CreateFrame("Frame", addonName .. "LogWindow", UIParent, "BasicFrameTemplateWithInset")
    logWindow:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    logWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    logWindow:SetMovable(true)
    logWindow:EnableMouse(true)
    logWindow:RegisterForDrag("LeftButton")
    logWindow:SetScript("OnDragStart", logWindow.StartMoving)
    logWindow:SetScript("OnDragStop", logWindow.StopMovingOrSizing)
    logWindow:Hide()
    
    -- Register with FocusManager for proper strata coordination
    if addon.FocusManager then
        addon.FocusManager:RegisterWindow(logWindow, nil, "MEDIUM")
    end
    
    -- Title
    logWindow.title = logWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    logWindow.title:SetPoint("LEFT", logWindow.TitleBg, "LEFT", 5, 0)
    logWindow.title:SetText("MyLogger - Log Viewer")
    
    -- Close button (use the template's close button)
    logWindow.CloseButton:SetScript("OnClick", function()
        MyLoggerWindow:Hide()
    end)
    
    self:CreateScrollArea()
    self:CreateFilterButtons()
    self:CreateCopyArea()
    
    return logWindow
end

function MyLoggerWindow:CreateScrollArea()
    -- Main scroll frame for full display mode
    logScrollFrame = CreateFrame("ScrollFrame", nil, logWindow, "UIPanelScrollFrameTemplate")
    logScrollFrame:SetPoint("TOPLEFT", logWindow, "TOPLEFT", 15, -65)
    logScrollFrame:SetPoint("BOTTOMRIGHT", logWindow, "BOTTOMRIGHT", -35, 35)
    
    -- Add backdrop mixin for newer WoW versions
    if BackdropTemplateMixin then
        Mixin(logScrollFrame, BackdropTemplateMixin)
    end
    
    -- Add backdrop to scroll frame
    logScrollFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    logScrollFrame:SetBackdropColor(0, 0, 0, 0.8)
    logScrollFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    -- Create EditBox for full mode (selectable text)
    logContentFrame = CreateFrame("EditBox", nil, logScrollFrame)
    logContentFrame:SetMultiLine(true)
    logContentFrame:SetAutoFocus(false)
    logContentFrame:SetFontObject("GameFontNormal")
    logContentFrame:SetWidth(WINDOW_WIDTH - 60)
    logContentFrame:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    logContentFrame:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            -- Prevent user from typing
            self:SetText(self.logText or "")
            self:ClearFocus()
        end
    end)
    
    logScrollFrame:SetScrollChild(logContentFrame)
    
    -- Create lightweight FontString for combat mode (no scrolling, no selection)
    logLightweightFrame = CreateFrame("Frame", nil, logWindow)
    logLightweightFrame:SetPoint("TOPLEFT", logWindow, "TOPLEFT", 15, -65)
    logLightweightFrame:SetPoint("BOTTOMRIGHT", logWindow, "BOTTOMRIGHT", -35, 35)
    logLightweightFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    logLightweightFrame:SetBackdropColor(0, 0, 0, 0.8)
    logLightweightFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    logLightweightFrame:Hide() -- Start hidden
    
    local lightweightText = logLightweightFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lightweightText:SetPoint("TOPLEFT", logLightweightFrame, "TOPLEFT", 5, -5)
    lightweightText:SetPoint("BOTTOMRIGHT", logLightweightFrame, "BOTTOMRIGHT", -5, 5)
    lightweightText:SetJustifyH("LEFT")
    lightweightText:SetJustifyV("TOP")
    logLightweightFrame.text = lightweightText
    
    -- Create status frame for paused/combat mode
    logStatusFrame = CreateFrame("Frame", nil, logWindow)
    logStatusFrame:SetPoint("TOPLEFT", logWindow, "TOPLEFT", 15, -65)
    logStatusFrame:SetPoint("BOTTOMRIGHT", logWindow, "BOTTOMRIGHT", -35, 35)
    logStatusFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    logStatusFrame:SetBackdropColor(0, 0, 0, 0.9)
    logStatusFrame:SetBackdropBorderColor(0.8, 0.8, 0, 1) -- Yellow border for attention
    logStatusFrame:Hide() -- Start hidden
    
    local statusText = logStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusText:SetPoint("CENTER", logStatusFrame, "CENTER", 0, 20)
    statusText:SetTextColor(1, 1, 0) -- Yellow text
    logStatusFrame.statusText = statusText
    
    local counterText = logStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    counterText:SetPoint("CENTER", logStatusFrame, "CENTER", 0, -10)
    counterText:SetTextColor(0.8, 0.8, 0.8)
    logStatusFrame.counterText = counterText
    
    local instructionText = logStatusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructionText:SetPoint("CENTER", logStatusFrame, "CENTER", 0, -40)
    instructionText:SetTextColor(0.6, 0.6, 0.6)
    instructionText:SetText("Click 'Resume' or 'Refresh Now' to see messages")
    logStatusFrame.instructionText = instructionText
    
    -- Store references on the window for later access
    logWindow.scrollFrame = logScrollFrame
    logWindow.contentFrame = logContentFrame
    logWindow.lightweightFrame = logLightweightFrame
    logWindow.statusFrame = logStatusFrame
    
    -- Initialize log entries array and load persistent logs
    logEntries = {}
    self:LoadPersistentLogs()
end

function MyLoggerWindow:CreateFilterButtons()
    -- Filter dropdown instead of buttons to save space
    local filterDropdown = CreateFrame("Frame", nil, logWindow, "UIDropDownMenuTemplate")
    filterDropdown:SetPoint("TOPLEFT", logWindow, "TOPLEFT", 10, -30)
    UIDropDownMenu_SetWidth(filterDropdown, 120)
    UIDropDownMenu_SetText(filterDropdown, FILTER_TYPES[currentFilter])
    
    UIDropDownMenu_Initialize(filterDropdown, function(self, level)
        local filterOrder = {"ALL", "PANIC", "ERROR", "WARN", "INFO", "DEBUG", "TRACE"}
        
        for _, filterType in ipairs(filterOrder) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = FILTER_TYPES[filterType]
            info.value = filterType
            info.func = function()
                MyLoggerWindow:SetFilter(filterType)
                UIDropDownMenu_SetSelectedValue(filterDropdown, filterType)
                UIDropDownMenu_SetText(filterDropdown, FILTER_TYPES[filterType])
            end
            info.checked = (currentFilter == filterType)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    logWindow.filterDropdown = filterDropdown
    
    -- Add Follow Messages checkbox (positioned better to avoid overlap)
    local followCheckbox = CreateFrame("CheckButton", nil, logWindow, "UICheckButtonTemplate")
    followCheckbox:SetSize(18, 18)
    followCheckbox:SetPoint("LEFT", filterDropdown, "RIGHT", 20, 0)
    followCheckbox:SetChecked(true)  -- Default to following
    followCheckbox.text = followCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    followCheckbox.text:SetPoint("LEFT", followCheckbox, "RIGHT", 3, 0)
    followCheckbox.text:SetText("Follow")
    followCheckbox.text:SetTextColor(1, 1, 1)
    
    followCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if isChecked and logContentFrame then
            -- Auto-scroll to bottom when enabled
            logContentFrame:SetCursorPosition(string.len(logContentFrame:GetText() or ""))
        end
        addon:Debug("Follow messages: %s", isChecked and "enabled" or "disabled")
    end)
    
    logWindow.followCheckbox = followCheckbox
    
    -- Add Pause/Resume button (manual control)
    local pauseResumeButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    pauseResumeButton:SetSize(70, 22)
    pauseResumeButton:SetPoint("TOPRIGHT", logWindow, "TOPRIGHT", -10, -35)
    pauseResumeButton:SetText("Pause")
    pauseResumeButton:SetNormalFontObject("GameFontNormalSmall")
    
    pauseResumeButton:SetScript("OnClick", function()
        MyLoggerWindow:TogglePause()
    end)
    logWindow.pauseResumeButton = pauseResumeButton
    
    -- Add Refresh Now button (process queued messages)
    local refreshNowButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    refreshNowButton:SetSize(80, 22)
    refreshNowButton:SetPoint("TOPRIGHT", pauseResumeButton, "TOPLEFT", -3, 0)
    refreshNowButton:SetText("Refresh Now")
    refreshNowButton:SetNormalFontObject("GameFontNormalSmall")
    
    refreshNowButton:SetScript("OnClick", function()
        MyLoggerWindow:ProcessQueuedMessages()
    end)
    logWindow.refreshNowButton = refreshNowButton
    
    -- Add Clear All button (permanent data deletion)
    local clearAllButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    clearAllButton:SetSize(70, 22)
    clearAllButton:SetPoint("TOPRIGHT", refreshNowButton, "TOPLEFT", -3, 0)
    clearAllButton:SetText("Clear All")
    clearAllButton:SetNormalFontObject("GameFontNormalSmall")
    
    clearAllButton:SetScript("OnClick", function()
        StaticPopup_Show("MYLOGGER_CLEAR_CONFIRM")
    end)
    
    -- Add Clear View button (display only)
    local clearViewButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    clearViewButton:SetSize(70, 22)
    clearViewButton:SetPoint("TOPRIGHT", clearAllButton, "TOPLEFT", -3, 0)
    clearViewButton:SetText("Clear View")
    clearViewButton:SetNormalFontObject("GameFontNormalSmall")
    
    clearViewButton:SetScript("OnClick", function()
        MyLoggerWindow:ClearView()
    end)
    
    -- Add Select All button
    local selectAllButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    selectAllButton:SetSize(80, 25)
    selectAllButton:SetPoint("TOPRIGHT", clearViewButton, "TOPLEFT", -5, 0)
    selectAllButton:SetText("Select All")
    selectAllButton:SetNormalFontObject("GameFontNormalSmall")
    
    selectAllButton:SetScript("OnClick", function()
        if logContentFrame and logContentFrame:GetText() ~= "" then
            logContentFrame:SetFocus()
            logContentFrame:HighlightText()
        end
    end)
    
    -- Set initial filter
    self:SetFilter("ALL")
end

-- Load persistent logs from MyLogger's SavedVariables
function MyLoggerWindow:LoadPersistentLogs()
    if not addon.MyLogger then return end
    
    local persistentLogs = addon.MyLogger:GetPersistentLogs()
    for _, savedEntry in ipairs(persistentLogs) do
        -- Convert saved log format to MyLoggerWindow format
        local level = addon.MyLogger.LOG_LEVELS[savedEntry.level] or 4
        local entry = {
            timestamp = savedEntry.timestamp,
            level = level,
            levelName = savedEntry.level,
            message = savedEntry.message,
            session = savedEntry.session,
            formatted = string.format("[%s] [%s] %s", 
                date("%H:%M:%S", savedEntry.timestamp),
                savedEntry.level,
                savedEntry.message
            )
        }
        table.insert(logEntries, entry)
    end
    
    -- Also load current memory logs
    local memoryLogs = addon.MyLogger:GetRecentLogs()
    for _, logLine in ipairs(memoryLogs) do
        -- Parse memory log format: "[timestamp] [level] message"
        local timestamp, levelName, message = logLine:match("%[([^%]]+)%] %[([^%]]+)%] (.+)")
        if timestamp and levelName and message then
            local level = addon.MyLogger.LOG_LEVELS[levelName] or 4
            local entry = {
                timestamp = os.time(), -- Use current time since memory logs don't store timestamp
                level = level,
                levelName = levelName,
                message = message,
                session = "current",
                formatted = string.format("[%s] [%s] %s", 
                    timestamp,
                    levelName,
                    message
                )
            }
            table.insert(logEntries, entry)
        end
    end
end

function MyLoggerWindow:CreateCopyArea()
    -- Copy instructions at bottom
    local instructions = logWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("BOTTOM", logWindow, "BOTTOM", 0, 15)
    instructions:SetText("Select text and press Ctrl+C to copy")
    instructions:SetTextColor(0.7, 0.7, 0.7)
end

-- =============================================================================
-- FILTER MANAGEMENT
-- =============================================================================

function MyLoggerWindow:SetFilter(filterType)
    currentFilter = filterType
    
    -- Update button states
    for filter, button in pairs(filterButtons) do
        if filter == filterType then
            button:LockHighlight()
        else
            button:UnlockHighlight()
        end
    end
    
    -- Force refresh by clearing the isRefreshing flag if stuck
    isRefreshing = false
    
    -- Refresh log display
    self:RefreshLogs()
end

-- =============================================================================
-- LOG MANAGEMENT
-- =============================================================================

function MyLoggerWindow:AddLogEntry(level, message, timestamp)
    local currentTime = GetTime()
    
    -- Update combat state
    UpdateCombatState()
    
    local entry = {
        level = level,
        message = message,
        timestamp = timestamp or time(),
        formatted = string.format("[%s] [%s] %s", 
            date("%H:%M:%S", timestamp or time()),
            addon.MyLogger.LEVEL_NAMES[level] or "UNKNOWN",
            message
        )
    }
    
    -- Handle different modes
    if performanceState.displayMode == "paused" or performanceState.isPaused then
        -- MODE: Memory-only during combat or manual pause
        table.insert(performanceState.combatBuffer, entry)
        performanceState.newMessageCount = performanceState.newMessageCount + 1
        
        -- Prevent memory bloat during long combat
        if #performanceState.combatBuffer > PERFORMANCE_CONFIG.MAX_COMBAT_BUFFER then
            table.remove(performanceState.combatBuffer, 1)
        end
        
        -- Update status display if window is visible
        if logWindow and logWindow:IsVisible() then
            self:UpdateStatusDisplay()
        end
        
    elseif performanceState.displayMode == "lightweight" then
        -- MODE: Lightweight display (FontString only, no virtual scrolling)
        table.insert(logEntries, entry)
        
        -- Keep only last 100 entries for lightweight mode
        if #logEntries > 100 then
            table.remove(logEntries, 1)
        end
        
        -- Update lightweight display if window is visible
        if logWindow and logWindow:IsVisible() then
            self:UpdateLightweightDisplay()
        end
        
    else
        -- MODE: Full display with virtual scrolling
        table.insert(logEntries, entry)
        
        -- Keep only last 500 entries to prevent memory issues
        if #logEntries > 500 then
            table.remove(logEntries, 1)
        end
        
        -- Normal refresh if window exists and is visible
        if logWindow and logWindow:IsVisible() then
            -- Use throttled refresh for busy periods only
            local isBusy = IsBusyPeriod()
            if isBusy then
                table.insert(performanceState.pendingEntries, entry)
                ScheduleThrottledRefresh()
            else
                self:RefreshLogs()
            end
        end
    end
end

function MyLoggerWindow:RefreshLogs()
    if not logWindow or not logWindow:IsVisible() or isRefreshing then return end
    
    isRefreshing = true
    
    -- Filter logs based on current filter (exact level match, not inclusive)
    local filteredLogs = {}
    for _, entry in ipairs(logEntries) do
        local shouldInclude = false
        
        if currentFilter == "ALL" then
            shouldInclude = true
        elseif currentFilter == "PANIC" and entry.level == 1 then
            shouldInclude = true
        elseif currentFilter == "ERROR" and entry.level == 2 then
            shouldInclude = true
        elseif currentFilter == "WARN" and entry.level == 3 then
            shouldInclude = true
        elseif currentFilter == "INFO" and entry.level == 4 then
            shouldInclude = true
        elseif currentFilter == "DEBUG" and entry.level == 5 then
            shouldInclude = true
        elseif currentFilter == "TRACE" and entry.level == 6 then
            shouldInclude = true
        end
        
        if shouldInclude then
            table.insert(filteredLogs, entry)
        end
    end
    
    -- Generate content lines for virtual scrolling
    local contentLines = {}
    
    if #filteredLogs == 0 then
        -- Show "no matches" message for empty filter results
        local filterDisplayName = FILTER_TYPES[currentFilter] or currentFilter
        table.insert(contentLines, "|cffffff00No " .. filterDisplayName .. " messages found.|r")
        table.insert(contentLines, "")
        table.insert(contentLines, "|cffccccccTry selecting a different filter or check if any messages")
        table.insert(contentLines, "have been logged at this level.|r")
    else
        for i, entry in ipairs(filteredLogs) do
            -- Add color codes based on level
            local color = addon.MyLogger.LEVEL_COLORS[entry.level] or ""
            
            -- Ensure formatted field exists (defensive programming)
            local formatted = entry.formatted
            if not formatted and entry.message then
                formatted = string.format("[%s] [%s] %s", 
                    entry.timestamp and date("%H:%M:%S", entry.timestamp) or "??:??:??",
                    addon.MyLogger.LEVEL_NAMES[entry.level] or "UNKNOWN",
                    entry.message
                )
            end
            
            if formatted then
                table.insert(contentLines, color .. formatted .. "|r")
            end
        end
    end
    
    -- Use virtual scrolling mixin to display content (if initialized)
    local filterDisplayName = FILTER_TYPES[currentFilter] or currentFilter
    local headerLines = {
        string.format("=== MyLogger Output (%d entries, filter: %s) ===", #filteredLogs, filterDisplayName),
        ""
    }
    
    if logWindow.virtualScroll then
        -- Pass filtered content to virtual scrolling (cache invalidation handled automatically)
        logWindow.virtualScroll:SetContent(contentLines, headerLines)
        
        -- Auto-scroll to bottom if follow is enabled
        if logWindow.followCheckbox and logWindow.followCheckbox:GetChecked() then
            -- Scroll to bottom after content is set
            C_Timer.After(0.1, function()
                if logWindow.virtualScroll.scrollFrame then
                    logWindow.virtualScroll.scrollFrame:SetVerticalScroll(
                        logWindow.virtualScroll.scrollFrame:GetVerticalScrollRange()
                    )
                end
            end)
        end
    else
        -- Fallback to traditional display if virtual scrolling not ready
        local allLines = {}
        for _, line in ipairs(headerLines) do
            table.insert(allLines, line)
        end
        for _, line in ipairs(contentLines) do
            table.insert(allLines, line)
        end
        
        local fullContent = table.concat(allLines, "\n")
        logContentFrame:SetText(fullContent)
        logContentFrame.logText = fullContent
        
        -- Auto-scroll to bottom if follow is enabled
        if logWindow.followCheckbox and logWindow.followCheckbox:GetChecked() then
            logContentFrame:SetCursorPosition(string.len(fullContent))
        end
    end
    
    isRefreshing = false
end

-- Removed UpdateCopyText - copy functionality is now handled by the Copy All button

function MyLoggerWindow:LoadExistingLogs()
    if not addon.MyLogger then return end
    
    -- Load from memory logs
    local memoryLogs = addon.MyLogger:GetRecentLogs()
    for _, logText in ipairs(memoryLogs) do
        -- Parse the formatted log text
        local timestamp, level, message = logText:match("%[(%d+:%d+:%d+)%] %[([^%]]+)%] (.+)")
        if timestamp and level and message then
            local levelNum = 3 -- Default to INFO
            for num, name in pairs(addon.MyLogger.LEVEL_NAMES) do
                if name == level then
                    levelNum = num
                    break
                end
            end
            self:AddLogEntry(levelNum, message, time())
        end
    end
    
    -- Load from persistent logs
    local persistentLogs = addon.MyLogger:GetPersistentLogs()
    for _, entry in ipairs(persistentLogs) do
        local levelNum = 3 -- Default to INFO
        for num, name in pairs(addon.MyLogger.LEVEL_NAMES) do
            if name == entry.level then
                levelNum = num
                break
            end
        end
        self:AddLogEntry(levelNum, entry.message, entry.timestamp)
    end
end

-- =============================================================================
-- PUBLIC INTERFACE
-- =============================================================================

function MyLoggerWindow:Show()
    if not logWindow then
        self:CreateWindow()
    end
    
    -- Initialize virtual scrolling mixin on first show (lazy initialization)
    if not logWindow.virtualScroll and logWindow.scrollFrame and logWindow.contentFrame then
        logWindow.virtualScroll = addon.VirtualScrollMixin:new()
        logWindow.virtualScroll:Initialize(logWindow, logWindow.scrollFrame, logWindow.contentFrame, {
            LINES_PER_CHUNK = 100,        -- Reasonable chunk size for normal operation
            MIN_LINES_FOR_VIRTUAL = 200,  -- Standard threshold
            TIMER_INTERVAL = 0.5,         -- Normal scroll monitoring
            BUFFER_CHUNKS = 1             -- Standard buffer
        })
    end
    
    -- Load existing logs when first shown
    if #logEntries == 0 then
        self:LoadExistingLogs()
    end
    
    -- Initialize display mode based on current state
    UpdateCombatState()
    if performanceState.inCombat and PERFORMANCE_CONFIG.COMBAT_MEMORY_ONLY and not performanceState.isPaused then
        performanceState.displayMode = "paused"
    else
        performanceState.displayMode = "full"
    end
    
    logWindow:Show()
    self:UpdateDisplayMode()
end

function MyLoggerWindow:Hide()
    if logWindow then
        logWindow:Hide()
    end
    
    -- Clean up performance timers when hiding
    if performanceState.refreshTimer then
        performanceState.refreshTimer:Cancel()
        performanceState.refreshTimer = nil
    end
    
    -- Process any remaining pending entries before hiding
    ProcessPendingEntries()
end

function MyLoggerWindow:Toggle()
    if logWindow and logWindow:IsVisible() then
        self:Hide()
    else
        self:Show()
    end
end

function MyLoggerWindow:IsVisible()
    return logWindow and logWindow:IsVisible()
end

-- Update display mode and show/hide appropriate frames
function MyLoggerWindow:UpdateDisplayMode()
    if not logWindow then return end
    
    -- Hide all display frames first
    logWindow.scrollFrame:Hide()
    logWindow.lightweightFrame:Hide()
    logWindow.statusFrame:Hide()
    
    -- Show appropriate frame based on display mode
    if performanceState.displayMode == "paused" then
        logWindow.statusFrame:Show()
        self:UpdateStatusDisplay()
    elseif performanceState.displayMode == "lightweight" then
        logWindow.lightweightFrame:Show()
        self:UpdateLightweightDisplay()
    else -- "full"
        logWindow.scrollFrame:Show()
        self:RefreshLogs()
    end
    
    -- Update button states
    if logWindow.pauseResumeButton then
        if performanceState.isPaused or performanceState.displayMode == "paused" then
            logWindow.pauseResumeButton:SetText("Resume")
        else
            logWindow.pauseResumeButton:SetText("Pause")
        end
    end
end

-- Update status display during paused/combat mode
function MyLoggerWindow:UpdateStatusDisplay()
    if not logWindow or not logWindow.statusFrame then return end
    
    local statusText = performanceState.inCombat and "COMBAT MODE - Logging Paused" or "LOGGING PAUSED"
    logWindow.statusFrame.statusText:SetText(statusText)
    
    local countText = string.format("%d new messages buffered", performanceState.newMessageCount)
    logWindow.statusFrame.counterText:SetText(countText)
end

-- Update lightweight display (FontString only)
function MyLoggerWindow:UpdateLightweightDisplay()
    if not logWindow or not logWindow.lightweightFrame then return end
    
    -- Show only last 20 lines in lightweight mode
    local recentEntries = {}
    local startIndex = math.max(1, #logEntries - 19)
    
    for i = startIndex, #logEntries do
        local entry = logEntries[i]
        if entry and self:PassesFilter(entry) then
            local color = addon.MyLogger.LEVEL_COLORS[entry.level] or ""
            table.insert(recentEntries, color .. entry.formatted .. "|r")
        end
    end
    
    local content = table.concat(recentEntries, "\n")
    if #recentEntries == 0 then
        content = "|cffccccccNo recent messages|r"
    end
    
    logWindow.lightweightFrame.text:SetText(content)
end

-- Manual pause/resume toggle
function MyLoggerWindow:TogglePause()
    performanceState.isPaused = not performanceState.isPaused
    
    if performanceState.isPaused then
        performanceState.displayMode = "paused"
    else
        -- Resume to appropriate mode based on combat state
        if performanceState.inCombat and PERFORMANCE_CONFIG.COMBAT_MEMORY_ONLY then
            performanceState.displayMode = "paused"
        else
            performanceState.displayMode = "full"
        end
    end
    
    self:UpdateDisplayMode()
end

-- Process queued messages manually
function MyLoggerWindow:ProcessQueuedMessages()
    -- Process combat buffer
    if #performanceState.combatBuffer > 0 then
        for _, entry in ipairs(performanceState.combatBuffer) do
            table.insert(logEntries, entry)
        end
        
        -- Clear combat buffer
        performanceState.combatBuffer = {}
        performanceState.newMessageCount = 0
        
        -- Trim log entries to prevent memory bloat
        if #logEntries > 500 then
            local removeCount = #logEntries - 500
            for i = 1, removeCount do
                table.remove(logEntries, 1)
            end
        end
    end
    
    -- Process pending entries
    ProcessPendingEntries()
    
    -- Switch to full display mode and refresh
    if not performanceState.isPaused then
        performanceState.displayMode = "full"
        self:UpdateDisplayMode()
    end
end

-- Check if entry passes current filter
function MyLoggerWindow:PassesFilter(entry)
    if currentFilter == "ALL" then
        return true
    elseif currentFilter == "PANIC" and entry.level == 1 then
        return true
    elseif currentFilter == "ERROR" and entry.level == 2 then
        return true
    elseif currentFilter == "WARN" and entry.level == 3 then
        return true
    elseif currentFilter == "INFO" and entry.level == 4 then
        return true
    elseif currentFilter == "DEBUG" and entry.level == 5 then
        return true
    elseif currentFilter == "TRACE" and entry.level == 6 then
        return true
    end
    return false
end

-- Get performance statistics (debug)
function MyLoggerWindow:GetPerformanceStats()
    UpdateCombatState()
    return {
        isBusyPeriod = performanceState.isBusyPeriod,
        inCombat = performanceState.inCombat,
        isPaused = performanceState.isPaused,
        displayMode = performanceState.displayMode,
        combatDuration = performanceState.inCombat and (GetTime() - performanceState.combatStartTime) or 0,
        pendingEntries = #performanceState.pendingEntries,
        combatBufferSize = #performanceState.combatBuffer,
        newMessageCount = performanceState.newMessageCount,
        recentEntryCount = #performanceState.recentEntryTimes,
        refreshTimerActive = performanceState.refreshTimer ~= nil,
        totalLogEntries = #logEntries,
        virtualScrollActive = logWindow and logWindow.virtualScroll and logWindow.virtualScroll.state.isActive or false
    }
end

-- =============================================================================
-- CLEAR FUNCTIONS
-- =============================================================================

-- Clear the view only (does not affect persistent data)
function MyLoggerWindow:ClearView()
    -- Clear only the display entries, not the persistent data
    logEntries = {}
    
    -- Clear performance state
    performanceState.pendingEntries = {}
    performanceState.recentEntryTimes = {}
    performanceState.combatBuffer = {}
    performanceState.newMessageCount = 0
    performanceState.isBusyPeriod = false
    performanceState.inCombat = false
    performanceState.combatStartTime = 0
    performanceState.isPaused = false
    performanceState.displayMode = "full"
    if performanceState.refreshTimer then
        performanceState.refreshTimer:Cancel()
        performanceState.refreshTimer = nil
    end
    
    -- Clear the scroll frame content
    if logContentFrame then
        logContentFrame:SetText("")
    end
    
    -- Clear individual log entry frames
    for _, frame in pairs(self.logFrames or {}) do
        if frame then
            frame:Hide()
        end
    end
    
    -- Reset scroll position
    if logScrollFrame then
        logScrollFrame:SetVerticalScroll(0)
    end
    
    addon:Debug("Log view cleared (persistent data preserved)")
end

function MyLoggerWindow:ClearAllLogs()
    -- Clear in-memory logs
    logEntries = {}
    
    -- Clear performance state
    performanceState.pendingEntries = {}
    performanceState.recentEntryTimes = {}
    performanceState.combatBuffer = {}
    performanceState.newMessageCount = 0
    performanceState.isBusyPeriod = false
    performanceState.inCombat = false
    performanceState.combatStartTime = 0
    performanceState.isPaused = false
    performanceState.displayMode = "full"
    if performanceState.refreshTimer then
        performanceState.refreshTimer:Cancel()
        performanceState.refreshTimer = nil
    end
    
    -- Clear MyLogger's memory buffer
    if addon.MyLogger and addon.MyLogger.memoryLogs then
        addon.MyLogger.memoryLogs = {}
    end
    
    -- Clear SavedVariables logs
    local savedVars = addon.MyLogger:GetPersistentLogs()
    if MyUI2 and MyUI2.db and MyUI2.db.logs then
        MyUI2.db.logs = {}
    end
    
    -- Refresh display
    if logWindow and logWindow:IsVisible() then
        self:RefreshLogs()
    end
    
    print("All logs cleared")
end

-- =============================================================================
-- INTEGRATION WITH MYLOGGER
-- =============================================================================

-- Register with MyLogger to receive new log messages
function MyLoggerWindow:RegisterWithLogger()
    if addon.MyLogger then
        -- Hook into MyLogger's Log function to capture new messages
        local originalLog = addon.MyLogger.Log
        addon.MyLogger.Log = function(self, level, message, ...)
            -- Call original log function
            originalLog(self, level, message, ...)
            
            -- Send to window if it exists
            if MyLoggerWindow then
                local formattedMessage = message
                if ... then
                    formattedMessage = string.format(message, ...)
                end
                MyLoggerWindow:AddLogEntry(level, formattedMessage)
            end
        end
    end
end

return MyLoggerWindow