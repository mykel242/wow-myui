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
    ERROR = "Errors",
    WARN = "Warnings", 
    INFO = "Info",
    DEBUG = "Debug"
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
    logWindow:SetFrameStrata("HIGH")  -- Higher than most UI elements
    logWindow:SetFrameLevel(100)  -- Ensure it's on top
    logWindow:Hide()
    
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
    
    -- Initialize log entries array
    logEntries = {}
end

function MyLoggerWindow:CreateFilterButtons()
    local buttonWidth = 80
    local buttonHeight = 25
    local startX = 10
    local startY = -35
    
    for i, filterType in ipairs({"ALL", "ERROR", "WARN", "INFO", "DEBUG"}) do
        local button = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
        button:SetSize(buttonWidth, buttonHeight)
        button:SetPoint("TOPLEFT", logWindow, "TOPLEFT", startX + (i-1) * (buttonWidth + 5), startY)
        button:SetText(FILTER_TYPES[filterType])
        button:SetNormalFontObject("GameFontNormalSmall")
        
        button:SetScript("OnClick", function()
            self:SetFilter(filterType)
        end)
        
        filterButtons[filterType] = button
    end
    
    -- Add Select All button
    local selectAllButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    selectAllButton:SetSize(80, buttonHeight)
    selectAllButton:SetPoint("TOPRIGHT", logWindow, "TOPRIGHT", -15, startY)
    selectAllButton:SetText("Select All")
    selectAllButton:SetNormalFontObject("GameFontNormalSmall")
    
    selectAllButton:SetScript("OnClick", function()
        if logContentFrame and logContentFrame:GetText() ~= "" then
            logContentFrame:SetFocus()
            logContentFrame:HighlightText()
        end
    end)
    
    -- Add Clear button
    local clearButton = CreateFrame("Button", nil, logWindow, "GameMenuButtonTemplate")
    clearButton:SetSize(60, buttonHeight)
    clearButton:SetPoint("RIGHT", selectAllButton, "LEFT", -5, 0)
    clearButton:SetText("Clear")
    clearButton:SetNormalFontObject("GameFontNormalSmall")
    
    clearButton:SetScript("OnClick", function()
        StaticPopup_Show("MYLOGGER_CLEAR_CONFIRM")
    end)
    
    -- Set initial filter
    self:SetFilter("ALL")
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
           (currentFilter == "ERROR" and entry.level == 1) or
           (currentFilter == "WARN" and entry.level == 2) or
           (currentFilter == "INFO" and entry.level == 3) or
           (currentFilter == "DEBUG" and entry.level == 4) then
            table.insert(filteredLogs, entry)
        end
    end
    
    -- Build text with color codes
    local logTexts = {}
    -- Add padding at the top with an empty line
    table.insert(logTexts, " ")
    
    for i, entry in ipairs(filteredLogs) do
        -- Add color codes based on level
        local color = addon.MyLogger.LEVEL_COLORS[entry.level] or ""
        table.insert(logTexts, color .. entry.formatted .. "|r")
    end
    
    -- Set the text in the EditBox
    local fullText = table.concat(logTexts, "\n")
    logContentFrame.logText = fullText  -- Store for preventing edits
    logContentFrame:SetText(fullText)
    
    -- Update EditBox height based on content
    local numLines = #filteredLogs
    local contentHeight = math.max(numLines * LOG_ENTRY_HEIGHT + 20, logScrollFrame:GetHeight())
    logContentFrame:SetHeight(contentHeight)
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