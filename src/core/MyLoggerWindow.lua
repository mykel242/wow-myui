-- MyLoggerWindow.lua
-- Dedicated log viewer window for MyLogger
--
-- RATE-LIMITED PERFORMANCE SYSTEM:
-- - CIRCULAR BUFFER: Fixed-size buffer with overflow handling (2000 entries)
-- - 1Hz REFRESH LIMIT: Maximum 1 second between UI updates prevents stalls
-- - MANUAL CONTROLS: Pause/Resume and "Refresh Now" buttons for user control
-- - LAG DETECTION: Automatic tail mode when buffer falls behind
-- - MEMORY BOUNDED: Fixed memory usage prevents runaway growth

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

-- Performance configuration for rate-limited buffering
local PERFORMANCE_CONFIG = {
    REFRESH_THROTTLE_MS = 1000,    -- HARD LIMIT: Max 1Hz refresh rate
    BATCH_SIZE = 50,               -- Larger batches for better efficiency
    MAX_PENDING_ENTRIES = 500,     -- Increased for combat memory buffering
    BUSY_THRESHOLD = 5,            -- Consider "busy" if 5+ entries in 1 second
    COMBAT_MEMORY_ONLY = false,    -- DISABLED: Set to true to re-enable auto-pause during combat
    MAX_COMBAT_BUFFER = 1000,      -- Maximum messages to buffer during combat
    
    -- Circular buffer configuration
    CIRCULAR_BUFFER_SIZE = 2000,   -- Fixed buffer size for all messages
    LAG_THRESHOLD = 500,           -- When read lag exceeds this, switch to tail mode
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

-- Circular buffer for rate-limited logging
local circularBuffer = {
    entries = {},                          -- Fixed-size array
    capacity = PERFORMANCE_CONFIG.CIRCULAR_BUFFER_SIZE,
    writeIndex = 1,                        -- Next write position
    readIndex = 1,                         -- Last UI read position
    size = 0,                             -- Current entries count
    overflowCount = 0,                    -- Messages lost to overflow
    totalWritten = 0,                     -- Total messages ever written
}

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
    displayMode = "full",       -- "full", "lightweight", "paused"
    bufferLagged = false,       -- True when buffer is too far behind
    laggedMessageCount = 0,     -- How many messages behind when lagged
}

-- =============================================================================
-- CIRCULAR BUFFER FUNCTIONS
-- =============================================================================

-- Write entry to circular buffer (always succeeds, overwrites if full)
local function WriteToCircularBuffer(entry)
    circularBuffer.entries[circularBuffer.writeIndex] = entry
    circularBuffer.totalWritten = circularBuffer.totalWritten + 1
    
    -- Update size and handle overflow
    if circularBuffer.size < circularBuffer.capacity then
        circularBuffer.size = circularBuffer.size + 1
    else
        -- Buffer is full, we're overwriting
        circularBuffer.overflowCount = circularBuffer.overflowCount + 1
        
        -- If read index is about to be overwritten, advance it
        if circularBuffer.readIndex == circularBuffer.writeIndex then
            circularBuffer.readIndex = circularBuffer.readIndex + 1
            if circularBuffer.readIndex > circularBuffer.capacity then
                circularBuffer.readIndex = 1
            end
        end
    end
    
    -- Advance write index (circular)
    circularBuffer.writeIndex = circularBuffer.writeIndex + 1
    if circularBuffer.writeIndex > circularBuffer.capacity then
        circularBuffer.writeIndex = 1
    end
end

-- Read unread entries from circular buffer
local function ReadFromCircularBuffer()
    local entries = {}
    local count = 0
    
    -- Calculate unread entries
    local unreadCount
    if circularBuffer.size == 0 then
        return entries, 0
    elseif circularBuffer.writeIndex > circularBuffer.readIndex then
        unreadCount = circularBuffer.writeIndex - circularBuffer.readIndex
    elseif circularBuffer.writeIndex < circularBuffer.readIndex then
        unreadCount = (circularBuffer.capacity - circularBuffer.readIndex) + circularBuffer.writeIndex
    else
        -- writeIndex == readIndex
        if circularBuffer.size == circularBuffer.capacity then
            -- Buffer is full, all entries are unread
            unreadCount = circularBuffer.capacity
        else
            -- Buffer is empty or fully read
            return entries, 0
        end
    end
    
    -- Read entries
    local currentIndex = circularBuffer.readIndex
    for i = 1, unreadCount do
        if circularBuffer.entries[currentIndex] then
            table.insert(entries, circularBuffer.entries[currentIndex])
            count = count + 1
        end
        
        currentIndex = currentIndex + 1
        if currentIndex > circularBuffer.capacity then
            currentIndex = 1
        end
    end
    
    -- Update read index
    circularBuffer.readIndex = circularBuffer.writeIndex
    
    return entries, count
end

-- Get buffer lag (unread entries count)
local function GetBufferLag()
    if circularBuffer.size == 0 then
        return 0
    elseif circularBuffer.writeIndex > circularBuffer.readIndex then
        return circularBuffer.writeIndex - circularBuffer.readIndex
    elseif circularBuffer.writeIndex < circularBuffer.readIndex then
        return (circularBuffer.capacity - circularBuffer.readIndex) + circularBuffer.writeIndex
    else
        -- writeIndex == readIndex
        return circularBuffer.size == circularBuffer.capacity and circularBuffer.capacity or 0
    end
end

-- Reset circular buffer read position to end (tail mode)
local function JumpToBufferTail()
    circularBuffer.readIndex = circularBuffer.writeIndex
    return GetBufferLag()
end

-- Get buffer statistics for debugging/monitoring
function MyLoggerWindow:GetBufferStats()
    return {
        capacity = circularBuffer.capacity,
        size = circularBuffer.size,
        writeIndex = circularBuffer.writeIndex,
        readIndex = circularBuffer.readIndex,
        overflowCount = circularBuffer.overflowCount,
        totalWritten = circularBuffer.totalWritten,
        currentLag = GetBufferLag(),
        isLagged = performanceState.bufferLagged,
        laggedCount = performanceState.laggedMessageCount,
        displayBufferSize = #logEntries,
        refreshRate = PERFORMANCE_CONFIG.REFRESH_THROTTLE_MS,
    }
end

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

-- Schedule a rate-limited refresh (max 1Hz)
local function ScheduleRateLimitedRefresh()
    if performanceState.refreshTimer then
        return -- Already scheduled
    end
    
    -- HARD LIMIT: 1 second minimum between refreshes
    local delay = PERFORMANCE_CONFIG.REFRESH_THROTTLE_MS / 1000
    
    performanceState.refreshTimer = C_Timer.After(delay, function()
        performanceState.refreshTimer = nil
        
        if logWindow and logWindow:IsVisible() then
            -- Read new entries from circular buffer
            local newEntries, newCount = ReadFromCircularBuffer()
            
            if newCount > 0 then
                -- Check for buffer lag
                local currentLag = GetBufferLag()
                
                if currentLag > PERFORMANCE_CONFIG.LAG_THRESHOLD then
                    -- Buffer is too far behind, switch to tail mode
                    JumpToBufferTail()
                    performanceState.bufferLagged = true
                    performanceState.laggedMessageCount = currentLag
                else
                    performanceState.bufferLagged = false
                end
                
                -- Add new entries to display buffer
                for _, entry in ipairs(newEntries) do
                    table.insert(logEntries, entry)
                end
                
                -- Keep display buffer bounded
                if #logEntries > 500 then
                    local removeCount = #logEntries - 500
                    for i = 1, removeCount do
                        table.remove(logEntries, 1)
                    end
                end
                
                -- Refresh the display
                MyLoggerWindow:RefreshLogs()
            end
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
    logScrollFrame:SetPoint("BOTTOMRIGHT", logWindow, "BOTTOMRIGHT", -35, 45) -- More space for footer
    
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
    logLightweightFrame:SetPoint("BOTTOMRIGHT", logWindow, "BOTTOMRIGHT", -35, 45) -- More space for footer
    
    -- Add backdrop mixin for newer WoW versions
    if BackdropTemplateMixin then
        Mixin(logLightweightFrame, BackdropTemplateMixin)
    end
    
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
    logStatusFrame:SetPoint("BOTTOMRIGHT", logWindow, "BOTTOMRIGHT", -35, 45) -- More space for footer
    
    -- Add backdrop mixin for newer WoW versions
    if BackdropTemplateMixin then
        Mixin(logStatusFrame, BackdropTemplateMixin)
    end
    
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
    instructionText:SetText("Use 'Resume' or 'Refresh Now' buttons below to see messages")
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
    
    -- Add Clear All button (permanent data deletion) - moved to top right
    local clearAllButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    clearAllButton:SetSize(70, 22)
    clearAllButton:SetPoint("TOPRIGHT", logWindow, "TOPRIGHT", -10, -35)
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
    -- Create footer frame for controls
    local footerFrame = CreateFrame("Frame", nil, logWindow)
    footerFrame:SetPoint("BOTTOMLEFT", logWindow, "BOTTOMLEFT", 10, 5)
    footerFrame:SetPoint("BOTTOMRIGHT", logWindow, "BOTTOMRIGHT", -10, 5)
    footerFrame:SetHeight(30)
    
    -- Add Follow Messages checkbox (footer left side)
    local followCheckbox = CreateFrame("CheckButton", nil, footerFrame, "UICheckButtonTemplate")
    followCheckbox:SetSize(18, 18)
    followCheckbox:SetPoint("LEFT", footerFrame, "LEFT", 0, 0)
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
        -- User setting change - no need to log this
    end)
    
    logWindow.followCheckbox = followCheckbox
    
    -- Add Pause/Resume button (footer center-left)
    local pauseResumeButton = CreateFrame("Button", nil, footerFrame, "GameMenuButtonTemplate")
    pauseResumeButton:SetSize(70, 22)
    pauseResumeButton:SetPoint("LEFT", followCheckbox.text, "RIGHT", 20, 0)
    pauseResumeButton:SetText("Pause")
    pauseResumeButton:SetNormalFontObject("GameFontNormalSmall")
    
    pauseResumeButton:SetScript("OnClick", function()
        MyLoggerWindow:TogglePause()
    end)
    logWindow.pauseResumeButton = pauseResumeButton
    
    -- Add Refresh Now button (footer center-right)
    local refreshNowButton = CreateFrame("Button", nil, footerFrame, "GameMenuButtonTemplate")
    refreshNowButton:SetSize(80, 22)
    refreshNowButton:SetPoint("LEFT", pauseResumeButton, "RIGHT", 5, 0)
    refreshNowButton:SetText("Refresh Now")
    refreshNowButton:SetNormalFontObject("GameFontNormalSmall")
    
    refreshNowButton:SetScript("OnClick", function()
        MyLoggerWindow:ProcessQueuedMessages()
    end)
    logWindow.refreshNowButton = refreshNowButton
    
    -- Copy instructions at bottom right
    local instructions = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("RIGHT", footerFrame, "RIGHT", 0, 0)
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
    
    -- ALWAYS write to circular buffer first (off-screen buffering)
    WriteToCircularBuffer(entry)
    
    -- Track recent entry times for busy period detection
    local currentTime = GetTime()
    table.insert(performanceState.recentEntryTimes, currentTime)
    
    -- Schedule rate-limited UI refresh (max 1Hz)
    if logWindow and logWindow:IsVisible() then
        ScheduleRateLimitedRefresh()
    end
    
    -- Update status display if paused (immediate for user feedback)
    if (performanceState.displayMode == "paused" or performanceState.isPaused) and 
       logWindow and logWindow:IsVisible() then
        performanceState.newMessageCount = performanceState.newMessageCount + 1
        self:UpdateStatusDisplay()
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
    
    local statusText = "LOGGING PAUSED"  -- Combat auto-pause disabled
    logWindow.statusFrame.statusText:SetText(statusText)
    
    local countText
    if performanceState.bufferLagged then
        countText = string.format("⚠️ %d messages behind (showing latest)", performanceState.laggedMessageCount)
    else
        local currentLag = GetBufferLag()
        countText = string.format("%d messages buffered", currentLag)
    end
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