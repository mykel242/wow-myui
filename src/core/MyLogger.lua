-- MyLogger.lua
-- Professional logging system with configurable levels and chat channel support

local addonName, addon = ...

print("Debug: MyLogger.lua loading...")
print("Debug: addonName =", addonName)
print("Debug: addon =", addon)

addon.MyLogger = {}
local MyLogger = addon.MyLogger

print("Debug: MyLogger assigned to addon.MyLogger")

-- =============================================================================
-- LOG LEVELS
-- =============================================================================

MyLogger.LOG_LEVELS = {
    OFF = 0,      -- No logging
    ERROR = 1,    -- Critical errors only
    WARN = 2,     -- Warnings and errors
    INFO = 3,     -- General information
    DEBUG = 4,    -- Debug information
    TRACE = 5     -- Verbose tracing
}

-- Level names for display
MyLogger.LEVEL_NAMES = {
    [0] = "OFF",
    [1] = "ERROR", 
    [2] = "WARN",
    [3] = "INFO",
    [4] = "DEBUG",
    [5] = "TRACE"
}

-- Level colors for chat output
MyLogger.LEVEL_COLORS = {
    [1] = "|cffff4444", -- ERROR: Red
    [2] = "|cfffff444", -- WARN: Yellow  
    [3] = "|cff44ff44", -- INFO: Green
    [4] = "|cff4444ff", -- DEBUG: Blue
    [5] = "|cffff44ff"  -- TRACE: Magenta
}

-- =============================================================================
-- CONFIGURATION
-- =============================================================================

local config = {
    currentLevel = MyLogger.LOG_LEVELS.OFF,
    useChannel = false,
    channelName = nil,
    channelId = nil,
    channelConnected = false,
    fallbackToPrint = true,
    includeTimestamp = true,
    includeLevel = true,
    maxMessageLength = 255 -- WoW chat message limit
}

-- =============================================================================
-- CORE LOGGING API
-- =============================================================================

-- Set the current log level
function MyLogger:SetLevel(level)
    if type(level) == "string" then
        -- Convert string to number
        for num, name in pairs(self.LEVEL_NAMES) do
            if name:upper() == level:upper() then
                level = num
                break
            end
        end
    end
    
    if type(level) == "number" and level >= 0 and level <= 5 then
        config.currentLevel = level
        self:Info("Log level set to: %s (%d)", self.LEVEL_NAMES[level], level)
        return true
    else
        self:Error("Invalid log level: %s", tostring(level))
        return false
    end
end

-- Get current log level
function MyLogger:GetLevel()
    return config.currentLevel
end

-- Check if a level should be logged
function MyLogger:ShouldLog(level)
    return config.currentLevel >= level
end

-- =============================================================================
-- CHAT CHANNEL MANAGEMENT
-- =============================================================================

-- Initialize chat channel for logging
function MyLogger:InitializeChannel(versionHash)
    if not config.useChannel then return false end
    
    -- Create unique channel name
    versionHash = versionHash or "dev"
    config.channelName = string.format("MyUI-%s-Log", versionHash)
    
    -- Try to join/create the channel
    local channelId, actualChannelName = JoinChannelByName(config.channelName)
    
    if channelId then
        config.channelId = channelId
        config.channelConnected = true
        
        -- Send session header
        self:SendToChannel("=== MyUI Logging Session Started ===")
        self:SendToChannel("Channel: %s | Level: %s", 
            actualChannelName or config.channelName, 
            self.LEVEL_NAMES[config.currentLevel])
        
        if config.fallbackToPrint then
            print(string.format("[%s] Logging to channel: %s", addonName, actualChannelName or config.channelName))
        end
        
        return true
    else
        if config.fallbackToPrint then
            print(string.format("[%s] Failed to create logging channel: %s", addonName, config.channelName))
        end
        return false
    end
end

-- Send message directly to channel
function MyLogger:SendToChannel(message, ...)
    if not config.channelConnected or not config.channelId then return false end
    
    -- Format message if needed
    if ... then
        message = string.format(message, ...)
    end
    
    -- Truncate if too long
    if #message > config.maxMessageLength then
        message = message:sub(1, config.maxMessageLength - 3) .. "..."
    end
    
    SendChatMessage(message, "CHANNEL", nil, config.channelId)
    return true
end

-- Clean up channel on shutdown
function MyLogger:CleanupChannel()
    if config.channelConnected and config.channelName then
        self:SendToChannel("=== MyUI Logging Session Ended ===")
        LeaveChannelByName(config.channelName)
        config.channelConnected = false
    end
end

-- =============================================================================
-- MESSAGE FORMATTING AND OUTPUT
-- =============================================================================

-- Format a log message
function MyLogger:FormatMessage(level, message, ...)
    -- Format the message content
    if ... then
        message = string.format(message, ...)
    end
    
    local parts = {}
    
    -- Add timestamp if enabled
    if config.includeTimestamp then
        table.insert(parts, date("%H:%M:%S"))
    end
    
    -- Add level if enabled
    if config.includeLevel then
        local levelName = self.LEVEL_NAMES[level] or "UNKNOWN"
        local colorCode = self.LEVEL_COLORS[level] or ""
        table.insert(parts, string.format("%s[%s]|r", colorCode, levelName))
    end
    
    -- Add addon name
    table.insert(parts, string.format("[%s]", addonName))
    
    -- Add the message
    table.insert(parts, message)
    
    return table.concat(parts, " ")
end

-- Core logging function
function MyLogger:Log(level, message, ...)
    -- Check if we should log this level
    if not self:ShouldLog(level) then return end
    
    -- Format the message
    local formattedMessage = self:FormatMessage(level, message, ...)
    
    -- Try to send to channel first
    local sentToChannel = false
    if config.useChannel and config.channelConnected then
        sentToChannel = self:SendToChannel(formattedMessage)
    end
    
    -- Fallback to print if needed
    if not sentToChannel and config.fallbackToPrint then
        print(formattedMessage)
    end
end

-- =============================================================================
-- CONVENIENCE LOGGING METHODS
-- =============================================================================

-- Error logging (always important)
function MyLogger:Error(message, ...)
    self:Log(self.LOG_LEVELS.ERROR, message, ...)
end

-- Warning logging  
function MyLogger:Warn(message, ...)
    self:Log(self.LOG_LEVELS.WARN, message, ...)
end

-- Info logging
function MyLogger:Info(message, ...)
    self:Log(self.LOG_LEVELS.INFO, message, ...)
end

-- Debug logging
function MyLogger:Debug(message, ...)
    self:Log(self.LOG_LEVELS.DEBUG, message, ...)
end

-- Trace logging (most verbose)
function MyLogger:Trace(message, ...)
    self:Log(self.LOG_LEVELS.TRACE, message, ...)
end

-- =============================================================================
-- CONFIGURATION API
-- =============================================================================

-- Enable/disable chat channel logging
function MyLogger:SetUseChannel(enabled)
    config.useChannel = enabled
    if enabled then
        self:Info("Chat channel logging enabled")
    else
        self:Info("Chat channel logging disabled")
        if config.channelConnected then
            self:CleanupChannel()
        end
    end
end

-- Enable/disable fallback to print
function MyLogger:SetFallbackToPrint(enabled)
    config.fallbackToPrint = enabled
end

-- Enable/disable timestamps
function MyLogger:SetIncludeTimestamp(enabled)
    config.includeTimestamp = enabled
end

-- Enable/disable level names
function MyLogger:SetIncludeLevel(enabled)
    config.includeLevel = enabled
end

-- Get current configuration
function MyLogger:GetConfig()
    return {
        level = config.currentLevel,
        levelName = self.LEVEL_NAMES[config.currentLevel],
        useChannel = config.useChannel,
        channelConnected = config.channelConnected,
        channelName = config.channelName,
        fallbackToPrint = config.fallbackToPrint,
        includeTimestamp = config.includeTimestamp,
        includeLevel = config.includeLevel
    }
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MyLogger:Initialize(settings)
    settings = settings or {}
    
    -- Apply settings
    self:SetLevel(settings.level or self.LOG_LEVELS.OFF)
    self:SetUseChannel(settings.useChannel or false)
    self:SetFallbackToPrint(settings.fallbackToPrint ~= false) -- Default true
    self:SetIncludeTimestamp(settings.includeTimestamp ~= false) -- Default true
    self:SetIncludeLevel(settings.includeLevel ~= false) -- Default true
    
    -- Initialize channel if requested
    if settings.useChannel then
        self:InitializeChannel(settings.versionHash)
    end
    
    self:Info("MyLogger initialized")
end

-- =============================================================================
-- DEBUG UTILITIES
-- =============================================================================

-- Debug dump of current configuration
function MyLogger:DumpConfig()
    local cfg = self:GetConfig()
    self:Info("=== MyLogger Configuration ===")
    self:Info("Level: %s (%d)", cfg.levelName, cfg.level)
    self:Info("Use Channel: %s", tostring(cfg.useChannel))
    self:Info("Channel Connected: %s", tostring(cfg.channelConnected))
    self:Info("Channel Name: %s", cfg.channelName or "none")
    self:Info("Fallback to Print: %s", tostring(cfg.fallbackToPrint))
    self:Info("Include Timestamp: %s", tostring(cfg.includeTimestamp))
    self:Info("Include Level: %s", tostring(cfg.includeLevel))
    self:Info("==============================")
end

return MyLogger