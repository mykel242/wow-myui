-- MyLoggerWindow.lua
-- Dedicated log viewer window for MyLogger

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
local logEntries = {}
local filterButtons = {}
local currentFilter = "ALL"
local copyEditBox = nil

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
    -- Scroll frame for logs
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
    
    -- Create EditBox for selectable text
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
    
    -- Initialize virtual scrolling mixin
    logWindow.virtualScroll = addon.VirtualScrollMixin:new()
    logWindow.virtualScroll:Initialize(logWindow, logScrollFrame, logContentFrame, {
        LINES_PER_CHUNK = 100,        -- Smaller chunks for logs
        MIN_LINES_FOR_VIRTUAL = 200,  -- Lower threshold for logs
        TIMER_INTERVAL = 0.2          -- Slower updates for logs
    })
    
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
    
    -- Add Clear All button (permanent data deletion)
    local clearAllButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    clearAllButton:SetSize(80, 25)
    clearAllButton:SetPoint("TOPRIGHT", logWindow, "TOPRIGHT", -15, -35)
    clearAllButton:SetText("Clear All")
    clearAllButton:SetNormalFontObject("GameFontNormalSmall")
    
    clearAllButton:SetScript("OnClick", function()
        StaticPopup_Show("MYLOGGER_CLEAR_CONFIRM")
    end)
    
    -- Add Clear View button (display only)
    local clearViewButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    clearViewButton:SetSize(80, 25)
    clearViewButton:SetPoint("TOPRIGHT", clearAllButton, "TOPLEFT", -5, 0)
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
    
    -- Refresh log display
    self:RefreshLogs()
end

-- =============================================================================
-- LOG MANAGEMENT
-- =============================================================================

function MyLoggerWindow:AddLogEntry(level, message, timestamp)
    if not logWindow then return end
    
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
    
    table.insert(logEntries, entry)
    
    -- Keep only last 500 entries to prevent memory issues
    if #logEntries > 500 then
        table.remove(logEntries, 1)
    end
    
    -- Refresh display if window is visible and filter matches
    if logWindow:IsVisible() then
        self:RefreshLogs()
    end
end

function MyLoggerWindow:RefreshLogs()
    if not logWindow or not logWindow:IsVisible() then return end
    
    -- Filter logs based on current filter
    local filteredLogs = {}
    for _, entry in ipairs(logEntries) do
        if currentFilter == "ALL" or 
           (currentFilter == "PANIC" and entry.level == 1) or
           (currentFilter == "ERROR" and entry.level == 2) or
           (currentFilter == "WARN" and entry.level == 3) or
           (currentFilter == "INFO" and entry.level == 4) or
           (currentFilter == "DEBUG" and entry.level == 5) or
           (currentFilter == "TRACE" and entry.level == 6) then
            table.insert(filteredLogs, entry)
        end
    end
    
    -- Generate content lines for virtual scrolling
    local contentLines = {}
    
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
    
    -- Use virtual scrolling mixin to display content
    local headerLines = {
        string.format("=== MyLogger Output (%d entries, filter: %s) ===", #filteredLogs, currentFilter),
        ""
    }
    
    logWindow.virtualScroll:SetContent(contentLines, headerLines)
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
    
    -- Load existing logs when first shown
    if #logEntries == 0 then
        self:LoadExistingLogs()
    end
    
    logWindow:Show()
    self:RefreshLogs()
end

function MyLoggerWindow:Hide()
    if logWindow then
        logWindow:Hide()
    end
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

-- =============================================================================
-- CLEAR FUNCTIONS
-- =============================================================================

-- Clear the view only (does not affect persistent data)
function MyLoggerWindow:ClearView()
    -- Clear only the display entries, not the persistent data
    logEntries = {}
    
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