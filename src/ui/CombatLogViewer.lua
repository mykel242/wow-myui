-- CombatLogViewer.lua
-- Basic UI for viewing combat logs with scrollable text area

local addonName, addon = ...

-- Combat Log Viewer module
addon.CombatLogViewer = {}
local CombatLogViewer = addon.CombatLogViewer

-- State tracking
local isInitialized = false
local viewerFrame = nil
local scrollFrame = nil
local editBox = nil
local refreshTimer = nil

-- Configuration
local CONFIG = {
    WINDOW_WIDTH = 500,
    WINDOW_HEIGHT = 400,
    REFRESH_RATE = 1.0, -- Seconds between auto-refresh
    MAX_LINES = 1000,   -- Maximum lines in display
    AUTO_SCROLL = true, -- Auto-scroll to bottom
}

-- Initialize the combat log viewer
function CombatLogViewer:Initialize()
    if isInitialized then
        return
    end
    
    self:CreateViewerWindow()
    isInitialized = true
    
    addon:Debug("CombatLogViewer initialized - ready to display combat logs")
end

-- Create the main viewer window
function CombatLogViewer:CreateViewerWindow()
    if viewerFrame then
        return
    end
    
    -- Main frame using default WoW UI style
    local frame = CreateFrame("Frame", addonName .. "CombatLogViewer", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(CONFIG.WINDOW_WIDTH, CONFIG.WINDOW_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 100, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Set title
    frame.TitleText:SetText("Combat Log Viewer")
    
    -- Close button behavior
    frame.CloseButton:SetScript("OnClick", function()
        self:Hide()
    end)
    
    -- === TOOLBAR ===
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetSize(CONFIG.WINDOW_WIDTH - 30, 30)
    toolbar:SetPoint("TOP", frame, "TOP", 0, -30)
    
    -- Auto-refresh toggle
    local autoRefreshBtn = CreateFrame("CheckButton", nil, toolbar, "InterfaceOptionsCheckButtonTemplate")
    autoRefreshBtn:SetPoint("LEFT", toolbar, "LEFT", 10, 0)
    autoRefreshBtn:SetChecked(CONFIG.AUTO_SCROLL)
    autoRefreshBtn.Text:SetText("Auto-refresh")
    autoRefreshBtn:SetScript("OnClick", function()
        local checked = autoRefreshBtn:GetChecked()
        if checked then
            self:StartAutoRefresh()
        else
            self:StopAutoRefresh()
        end
    end)
    
    -- Manual refresh button
    local refreshBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("LEFT", autoRefreshBtn, "RIGHT", 100, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        self:RefreshContent()
    end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 10, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        self:ClearContent()
    end)
    
    -- Browse Sessions button (replaces export)
    local browseBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    browseBtn:SetSize(90, 22)
    browseBtn:SetPoint("RIGHT", toolbar, "RIGHT", -10, 0)
    browseBtn:SetText("Browse Sessions")
    browseBtn:SetScript("OnClick", function()
        if addon.SessionBrowser then
            addon.SessionBrowser:Show()
        else
            addon:Error("Session Browser not available")
        end
    end)
    
    -- === SCROLL FRAME AND TEXT AREA ===
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    
    -- Edit box for text content
    local editbox = CreateFrame("EditBox", nil, scroll)
    editbox:SetMultiLine(true)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(ChatFontNormal)
    editbox:SetWidth(scroll:GetWidth())
    editbox:SetScript("OnEscapePressed", function() editbox:ClearFocus() end)
    editbox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            -- Prevent user editing by reverting changes
            self:SetText(CombatLogViewer.lastContent or "")
            self:ClearFocus()
        end
    end)
    
    scroll:SetScrollChild(editbox)
    
    -- Store references
    viewerFrame = frame
    scrollFrame = scroll
    editBox = editbox
    
    -- Initial content
    self:RefreshContent()
    
    -- Start auto-refresh if enabled
    if CONFIG.AUTO_SCROLL then
        self:StartAutoRefresh()
    end
    
    addon:Debug("Combat log viewer window created")
end

-- Show the viewer window
function CombatLogViewer:Show()
    if not isInitialized then
        self:Initialize()
    end
    
    if viewerFrame then
        viewerFrame:Show()
        self:RefreshContent()
        
        addon:Debug("Combat log viewer shown")
    end
end

-- Hide the viewer window
function CombatLogViewer:Hide()
    if viewerFrame then
        viewerFrame:Hide()
        self:StopAutoRefresh()
        
        addon:Debug("Combat log viewer hidden")
    end
end

-- Toggle visibility
function CombatLogViewer:Toggle()
    if viewerFrame and viewerFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Refresh the content display
function CombatLogViewer:RefreshContent()
    if not editBox then
        return
    end
    
    local content = self:GenerateLogContent()
    editBox:SetText(content)
    self.lastContent = content
    
    -- Auto-scroll to bottom
    if CONFIG.AUTO_SCROLL then
        C_Timer.After(0.1, function()
            if scrollFrame then
                scrollFrame:SetVerticalScroll(scrollFrame:GetVerticalScrollRange())
            end
        end)
    end
end

-- Generate log content focusing on combat state changes
function CombatLogViewer:GenerateLogContent()
    local lines = {}
    
    -- Header
    table.insert(lines, "=== MyUI2 Combat State Monitor ===")
    table.insert(lines, string.format("Updated: %s", date("%Y-%m-%d %H:%M:%S")))
    table.insert(lines, "")
    
    -- Current combat status
    if addon.MySimpleCombatDetector then
        local debugInfo = addon.MySimpleCombatDetector:GetDebugInfo()
        table.insert(lines, "=== Current Combat Status ===")
        table.insert(lines, string.format("In Combat: %s", debugInfo.inCombat and "YES" or "NO"))
        
        if debugInfo.inCombat then
            table.insert(lines, string.format("Session ID: %s", debugInfo.sessionId or "Unknown"))
            table.insert(lines, string.format("Duration: %.1fs", debugInfo.duration or 0))
            table.insert(lines, string.format("Events Recorded: %d", debugInfo.eventCount or 0))
            table.insert(lines, string.format("Time Since Activity: %.1fs", debugInfo.timeSinceActivity or 0))
            table.insert(lines, string.format("Has Timeout Timer: %s", debugInfo.hasTimer and "YES" or "NO"))
        else
            table.insert(lines, "Not currently in combat")
            table.insert(lines, "Waiting for combat to begin...")
        end
        table.insert(lines, "")
    end
    -- System status
    table.insert(lines, "=== System Status ===")
    table.insert(lines, string.format("MySimpleCombatDetector: %s", addon.MySimpleCombatDetector and "Loaded" or "Not Loaded"))
    table.insert(lines, string.format("MyTimestampManager: %s", addon.MyTimestampManager and "Loaded" or "Not Loaded"))
    table.insert(lines, string.format("StorageManager: %s", addon.StorageManager and "Loaded" or "Not Loaded"))
    table.insert(lines, "")
    
    -- Context information
    if addon.MetadataCollector then
        local metadata = addon.MetadataCollector:GetCurrentMetadata()
        table.insert(lines, "=== Current Context ===")
        if metadata.player then
            table.insert(lines, string.format("Player: %s (%s %s, Level %d)", 
                tostring(metadata.player.name or "Unknown"),
                tostring(metadata.player.spec and metadata.player.spec.name or "Unknown"),
                tostring(metadata.player.class or "Unknown"),
                tonumber(metadata.player.level) or 0))
        end
        if metadata.zone then
            table.insert(lines, string.format("Zone: %s", tostring(metadata.zone.name or "Unknown")))
            if metadata.zone.instanceInfo and metadata.zone.instanceInfo.type ~= "none" then
                table.insert(lines, string.format("Instance: %s (%s)", 
                    tostring(metadata.zone.instanceInfo.name or "Unknown"),
                    tostring(metadata.zone.instanceInfo.difficultyName or "Normal")))
            end
        end
        if metadata.group then
            table.insert(lines, string.format("Group: %s (%d members)", 
                tostring(metadata.group.type or "unknown"),
                tonumber(metadata.group.size) or 0))
        end
        table.insert(lines, "")
    end
    
    -- Footer
    table.insert(lines, "=== End of State Monitor ===")
    table.insert(lines, "")
    table.insert(lines, "Note: For detailed session data and event logs, use Session Browser")
    
    return table.concat(lines, "\n")
end

-- Clear the content display
function CombatLogViewer:ClearContent()
    if editBox then
        editBox:SetText("Log cleared at " .. date("%H:%M:%S") .. "\n\nWaiting for new combat data...")
        self.lastContent = editBox:GetText()
    end
end

-- Start auto-refresh timer
function CombatLogViewer:StartAutoRefresh()
    if refreshTimer then
        refreshTimer:Cancel()
    end
    
    refreshTimer = C_Timer.NewTicker(CONFIG.REFRESH_RATE, function()
        if viewerFrame and viewerFrame:IsShown() then
            self:RefreshContent()
        end
    end)
    
    addon:Debug("Combat log auto-refresh started")
end

-- Stop auto-refresh timer
function CombatLogViewer:StopAutoRefresh()
    if refreshTimer then
        refreshTimer:Cancel()
        refreshTimer = nil
    end
    
    addon:Debug("Combat log auto-refresh stopped")
end

-- Public API
function CombatLogViewer:IsShown()
    return viewerFrame and viewerFrame:IsShown()
end

function CombatLogViewer:GetStatus()
    return {
        isInitialized = isInitialized,
        isShown = self:IsShown(),
        autoRefresh = refreshTimer ~= nil,
        contentLines = self.lastContent and select(2, string.gsub(self.lastContent, '\n', '\n')) or 0
    }
end