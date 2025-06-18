-- SessionBrowser.lua
-- Table view for browsing stored combat sessions with detailed viewer

local addonName, addon = ...

-- Session Browser module
addon.SessionBrowser = {}
local SessionBrowser = addon.SessionBrowser

-- State tracking
local isInitialized = false
local browserFrame = nil
local sessionTable = nil
local selectedSession = nil
local viewerFrame = nil
local viewerEditBox = nil

-- Configuration
local CONFIG = {
    BROWSER_WIDTH = 650,  -- Increased for Hash and Segments columns
    BROWSER_HEIGHT = 400,
    VIEWER_WIDTH = 700,
    VIEWER_HEIGHT = 500,
    ROW_HEIGHT = 16,
    MAX_VISIBLE_ROWS = 20,
    
    -- Session Viewer Performance Settings (Virtual Scrolling)
    EVENTS_PER_CHUNK = 500,       -- Events loaded per chunk
    SCROLL_BUFFER_CHUNKS = 2,     -- Buffer chunks above/below visible area
    MIN_EVENTS_FOR_VIRTUAL = 1000, -- Only virtualize if more than this many events
}


-- Initialize the session browser
function SessionBrowser:Initialize()
    if isInitialized then
        return
    end
    
    self:CreateBrowserWindow()
    self:CreateSessionViewer()
    isInitialized = true
    
    addon:Debug("SessionBrowser initialized - ready to browse stored sessions")
end

-- Create the main browser window with session table
function SessionBrowser:CreateBrowserWindow()
    if browserFrame then
        return
    end
    
    -- Main browser frame
    local frame = CreateFrame("Frame", addonName .. "SessionBrowser", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(CONFIG.BROWSER_WIDTH, CONFIG.BROWSER_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Register with FocusManager for proper strata coordination
    if addon.FocusManager then
        addon.FocusManager:RegisterWindow(frame, nil, "MEDIUM")
    end
    
    -- Set title
    frame.TitleText:SetText("Session Browser")
    
    -- Close button behavior
    frame.CloseButton:SetScript("OnClick", function()
        self:Hide()
    end)
    
    -- === TOOLBAR ===
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetSize(CONFIG.BROWSER_WIDTH - 30, 30)
    toolbar:SetPoint("TOP", frame, "TOP", 0, -30)
    
    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("LEFT", toolbar, "LEFT", 10, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        self:RefreshSessionList()
    end)
    
    -- Delete button
    local deleteBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    deleteBtn:SetSize(80, 22)
    deleteBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 10, 0)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        self:DeleteSelectedSession()
    end)
    
    -- View button
    local viewBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    viewBtn:SetSize(80, 22)
    viewBtn:SetPoint("LEFT", deleteBtn, "RIGHT", 10, 0)
    viewBtn:SetText("View")
    viewBtn:SetScript("OnClick", function()
        self:ViewSelectedSession()
    end)
    
    
    -- Clear all button
    local clearBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("RIGHT", toolbar, "RIGHT", -10, 0)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        self:ClearAllSessions()
    end)
    
    -- === SESSION TABLE ===
    local tableFrame = CreateFrame("Frame", nil, frame)
    tableFrame:SetSize(CONFIG.BROWSER_WIDTH - 40, CONFIG.BROWSER_HEIGHT - 100)
    tableFrame:SetPoint("TOP", toolbar, "BOTTOM", 0, -10)
    
    -- Table headers
    local headerFrame = CreateFrame("Frame", nil, tableFrame)
    headerFrame:SetSize(CONFIG.BROWSER_WIDTH - 40, 20)
    headerFrame:SetPoint("TOP", tableFrame, "TOP", 0, 0)
    
    local headers = {
        {text = "Hash", width = 50},
        {text = "Session ID", width = 120},
        {text = "Duration", width = 60},
        {text = "Events", width = 60},
        {text = "Segments", width = 60},
        {text = "Zone", width = 100},
        {text = "Time", width = 110}
    }
    
    local xOffset = 0
    for _, header in ipairs(headers) do
        local headerText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", xOffset + 5, -2)
        headerText:SetSize(header.width, 16)
        headerText:SetJustifyH("LEFT")
        headerText:SetText(header.text)
        headerText:SetTextColor(1, 1, 0.5) -- Yellow headers
        xOffset = xOffset + header.width
    end
    
    -- Scrollable session list
    local scrollFrame = CreateFrame("ScrollFrame", nil, tableFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", tableFrame, "BOTTOMRIGHT", -25, 10)
    
    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(1, 1)
    scrollFrame:SetScrollChild(contentFrame)
    
    -- Store references
    browserFrame = frame
    frame.scrollFrame = scrollFrame
    frame.contentFrame = contentFrame
    frame.selectedRow = nil
    frame.sessionRows = {}
    
    addon:Debug("Session browser window created")
end

-- Create the session detail viewer
function SessionBrowser:CreateSessionViewer()
    if viewerFrame then
        return
    end
    
    -- Session viewer frame
    local frame = CreateFrame("Frame", addonName .. "SessionViewer", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(CONFIG.VIEWER_WIDTH, CONFIG.VIEWER_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Register viewer frame with FocusManager
    if addon.FocusManager then
        addon.FocusManager:RegisterWindow(frame, nil, "MEDIUM")
    end
    
    -- Set title
    frame.TitleText:SetText("Session Viewer")
    
    -- Close button behavior
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- === VIEWER TOOLBAR ===
    local toolbar = CreateFrame("Frame", nil, frame)
    toolbar:SetSize(CONFIG.VIEWER_WIDTH - 30, 30)
    toolbar:SetPoint("TOP", frame, "TOP", 0, -30)
    
    -- Format dropdown
    local formatDropdown = CreateFrame("Frame", nil, toolbar, "UIDropDownMenuTemplate")
    formatDropdown:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
    UIDropDownMenu_SetWidth(formatDropdown, 120)
    UIDropDownMenu_SetText(formatDropdown, "Raw")
    UIDropDownMenu_SetSelectedValue(formatDropdown, "raw")
    
    UIDropDownMenu_Initialize(formatDropdown, function(self, level)
        local formats = {
            {id = "raw", name = "Raw Data"},
            {id = "text", name = "Text"},
            {id = "json", name = "JSON"}
        }
        
        for _, format in ipairs(formats) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = format.name
            info.value = format.id
            info.func = function()
                UIDropDownMenu_SetSelectedValue(formatDropdown, format.id)
                UIDropDownMenu_SetText(formatDropdown, format.name)
                SessionBrowser:RefreshViewerContent()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    -- Select All button (simplified toolbar)
    local selectAllBtn = CreateFrame("Button", nil, toolbar, "GameMenuButtonTemplate")
    selectAllBtn:SetSize(80, 22)
    selectAllBtn:SetPoint("LEFT", formatDropdown, "RIGHT", 10, 0)
    selectAllBtn:SetText("Select All")
    selectAllBtn:SetScript("OnClick", function()
        if viewerEditBox then
            viewerEditBox:SetFocus()
            viewerEditBox:HighlightText()
        end
    end)
    
    -- Virtual scroll tracking
    frame.virtualScroll = {
        loadedChunks = {},
        totalChunks = 0,
        currentContent = ""
    }
    
    -- Export info text
    local exportInfo = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    exportInfo:SetPoint("RIGHT", toolbar, "RIGHT", -10, 0)
    exportInfo:SetText("Large sessions use virtual scrolling for performance")
    exportInfo:SetTextColor(0.8, 0.8, 0.8)
    
    frame.formatDropdown = formatDropdown
    
    -- === SESSION INFO HEADER ===
    local infoFrame = CreateFrame("Frame", nil, frame)
    infoFrame:SetSize(CONFIG.VIEWER_WIDTH - 30, 60)
    infoFrame:SetPoint("TOP", toolbar, "BOTTOM", 0, -5)
    
    local sessionTitle = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sessionTitle:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 10, -5)
    sessionTitle:SetText("No Session Selected")
    frame.sessionTitle = sessionTitle
    
    local sessionInfo = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionInfo:SetPoint("TOPLEFT", sessionTitle, "BOTTOMLEFT", 0, -5)
    sessionInfo:SetText("")
    frame.sessionInfo = sessionInfo
    
    local sessionMeta = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionMeta:SetPoint("TOPLEFT", sessionInfo, "BOTTOMLEFT", 0, -5)
    sessionMeta:SetText("")
    frame.sessionMeta = sessionMeta
    
    -- === FULL SESSION LOG ===
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", infoFrame, "BOTTOMLEFT", 10, -10)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 10)
    
    -- Edit box for session content (read-only)
    local editbox = CreateFrame("EditBox", nil, scroll)
    editbox:SetMultiLine(true)
    editbox:SetAutoFocus(false)
    editbox:SetFontObject(ChatFontNormal)
    editbox:SetWidth(scroll:GetWidth())
    editbox:SetScript("OnEscapePressed", function() editbox:ClearFocus() end)
    editbox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            -- Prevent user editing
            self:SetText(viewerFrame.lastContent or "")
            self:ClearFocus()
        end
    end)
    
    -- Set up scroll event monitoring for virtual scrolling
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        SessionBrowser:OnScrollChanged(offset)
    end)
    
    scroll:SetScript("OnScrollRangeChanged", function(self, xrange, yrange)
        SessionBrowser:OnScrollRangeChanged(yrange)
    end)
    
    scroll:SetScrollChild(editbox)
    
    viewerFrame = frame
    viewerEditBox = editbox
    frame.scrollFrame = scroll
    
    addon:Debug("Session viewer window created")
end

-- Show the session browser
function SessionBrowser:Show()
    if not isInitialized then
        self:Initialize()
    end
    
    if browserFrame then
        browserFrame:Show()
        self:RefreshSessionList()
        
        addon:Debug("Session browser shown")
    end
end

-- Hide the session browser
function SessionBrowser:Hide()
    if browserFrame then
        browserFrame:Hide()
    end
    if viewerFrame then
        viewerFrame:Hide()
    end
    
    addon:Debug("Session browser hidden")
end

-- Toggle browser visibility
function SessionBrowser:Toggle()
    if browserFrame and browserFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Refresh the session list
function SessionBrowser:RefreshSessionList()
    if not browserFrame or not addon.StorageManager then
        return
    end
    
    -- Clear existing rows
    for _, row in ipairs(browserFrame.sessionRows) do
        row:Hide()
    end
    browserFrame.sessionRows = {}
    browserFrame.selectedRow = nil
    
    -- Get all sessions
    local sessions = addon.StorageManager:GetAllSessions()
    
    if #sessions == 0 then
        -- Show "no sessions" message
        local noSessionsText = browserFrame.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noSessionsText:SetPoint("TOP", browserFrame.contentFrame, "TOP", 0, -20)
        noSessionsText:SetText("No combat sessions stored")
        noSessionsText:SetTextColor(0.7, 0.7, 0.7)
        return
    end
    
    -- Create rows for each session (newest first)
    for i = #sessions, 1, -1 do
        local session = sessions[i]
        local rowIndex = #sessions - i + 1
        
        local row = self:CreateSessionRow(session, rowIndex)
        table.insert(browserFrame.sessionRows, row)
    end
    
    -- Update content frame size
    local totalHeight = #browserFrame.sessionRows * CONFIG.ROW_HEIGHT + 20
    browserFrame.contentFrame:SetSize(CONFIG.BROWSER_WIDTH - 60, totalHeight)
    
    addon:Debug("Session list refreshed: %d sessions", #sessions)
end

-- Create a row for a session
function SessionBrowser:CreateSessionRow(session, rowIndex)
    local row = CreateFrame("Button", nil, browserFrame.contentFrame)
    row:SetSize(CONFIG.BROWSER_WIDTH - 60, CONFIG.ROW_HEIGHT)
    row:SetPoint("TOPLEFT", browserFrame.contentFrame, "TOPLEFT", 0, -(rowIndex - 1) * CONFIG.ROW_HEIGHT)
    
    -- Alternating row colors
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    if rowIndex % 2 == 0 then
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
    else
        bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
    end
    row.bg = bg
    
    -- Highlight texture
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetColorTexture(0.3, 0.3, 0.9, 0.3)
    
    -- Selection texture
    local selection = row:CreateTexture(nil, "ARTWORK")
    selection:SetAllPoints(row)
    selection:SetColorTexture(0.2, 0.6, 1.0, 0.4)
    selection:Hide()
    row.selection = selection
    
    -- Row data
    local function formatSessionId(sessionId)
        if not sessionId then return "Unknown" end
        -- Extract parts from: timestamp-counter-checksum
        local parts = {}
        for part in sessionId:gmatch("[^-]+") do
            table.insert(parts, part)
        end
        if #parts >= 2 then
            -- Convert timestamp to readable format and show with counter
            local timestamp = tonumber(parts[1])
            if timestamp then
                local readableTime = date("%H:%M:%S", timestamp / 1000)
                return readableTime .. "-" .. parts[2]
            else
                return parts[1] .. "-" .. parts[2]
            end
        end
        return sessionId
    end
    
    local function formatDuration(session)
        local duration = session.duration
        if not duration or duration == 0 then
            -- Try to calculate from start/end times
            if session.startTime and session.endTime then
                duration = session.endTime - session.startTime
            elseif session.startTime and session.storedAt then
                duration = session.storedAt - session.startTime
            end
        end
        return string.format("%.1fs", duration or 0)
    end
    
    local function getSegmentCount(session)
        if session.isSegmented and session.segments then
            return tostring(#session.segments)
        elseif session.segmentCount and session.segmentCount > 0 then
            return tostring(session.segmentCount)
        else
            return "1"  -- Traditional single-segment session
        end
    end
    
    local columns = {
        {text = session.hash or "----", width = 50},
        {text = formatSessionId(session.id), width = 120},
        {text = formatDuration(session), width = 60},
        {text = tostring(session.eventCount or 0), width = 60},
        {text = getSegmentCount(session), width = 60},
        {text = (session.metadata and session.metadata.zone and session.metadata.zone.name) or "Unknown", width = 100},
        {text = session.serverTime and date("%m/%d %H:%M", session.serverTime) or "Unknown", width = 110}
    }
    
    local xOffset = 0
    for _, column in ipairs(columns) do
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", row, "LEFT", xOffset + 5, 0)
        text:SetSize(column.width, CONFIG.ROW_HEIGHT)
        text:SetJustifyH("LEFT")
        text:SetText(column.text)
        xOffset = xOffset + column.width
    end
    
    -- Click behavior
    row:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            self:GetParent():GetParent():GetParent():GetParent().selectedRow = self
            SessionBrowser:SelectSession(session)
        end
    end)
    
    -- Double-click to view
    row:SetScript("OnDoubleClick", function()
        SessionBrowser:ViewSelectedSession()
    end)
    
    row.sessionData = session
    
    return row
end

-- Select a session
function SessionBrowser:SelectSession(session)
    if not browserFrame then
        return
    end
    
    -- Clear previous selection
    for _, row in ipairs(browserFrame.sessionRows) do
        row.selection:Hide()
    end
    
    -- Highlight selected row
    if browserFrame.selectedRow then
        browserFrame.selectedRow.selection:Show()
    end
    
    selectedSession = session
    
    addon:Debug("Selected session: " .. (session.id or "Unknown"))
end

-- View the selected session in detail viewer
function SessionBrowser:ViewSelectedSession()
    if not selectedSession or not viewerFrame then
        addon:Warn("No session selected")
        return
    end
    
    -- Get full session data with decompressed events
    local fullSession = addon.StorageManager:GetSession(selectedSession.id)
    if not fullSession then
        addon:Error("Could not load session data")
        return
    end
    
    -- Update viewer title and info
    viewerFrame.sessionTitle:SetText("Session: " .. (fullSession.id or "Unknown"))
    
    local infoText = string.format("Duration: %.1fs | Events: %d | Stored: %s", 
        fullSession.duration or 0,
        fullSession.eventCount or 0,
        fullSession.serverTime and date("%Y-%m-%d %H:%M:%S", fullSession.serverTime) or "Unknown")
    viewerFrame.sessionInfo:SetText(infoText)
    
    local metaText = ""
    if fullSession.metadata then
        local meta = fullSession.metadata
        metaText = string.format("Zone: %s | Player: %s (%s) | Group: %s (%d)",
            (meta.zone and meta.zone.name) or "Unknown",
            (meta.player and meta.player.name) or "Unknown",
            (meta.player and meta.player.spec and meta.player.spec.name) or "Unknown",
            (meta.group and meta.group.type) or "solo",
            (meta.group and meta.group.size) or 1)
    end
    viewerFrame.sessionMeta:SetText(metaText)
    
    -- Initialize virtual scrolling for new session
    viewerFrame.currentSession = fullSession
    
    -- Generate session content using appropriate method
    self:RefreshViewerContent()
    
    -- Show viewer
    viewerFrame:Show()
    
    addon:Debug("Viewing session: %s (%d events)", fullSession.id, #(fullSession.events or {}))
end

-- Generate complete session log
function SessionBrowser:GenerateSessionLog(session)
    local lines = {}
    
    -- Calculate duration if not present
    local duration = session.duration
    if not duration and session.startTime and session.endTime then
        duration = session.endTime - session.startTime
    end
    
    -- Header
    table.insert(lines, "=== Combat Session Log ===")
    table.insert(lines, "Session ID: " .. (session.id or "Unknown"))
    table.insert(lines, "Duration: " .. string.format("%.1fs", duration or 0))
    table.insert(lines, "Total Events: " .. tostring(session.eventCount or 0))
    
    -- Use session time if available, otherwise try startTime
    local sessionTime = session.serverTime or session.startTime
    if sessionTime then
        table.insert(lines, "Timestamp: " .. date("%Y-%m-%d %H:%M:%S", sessionTime))
    end
    
    -- Handle both old metadata format and SimpleCombatDetector format
    table.insert(lines, "")
    table.insert(lines, "=== Context ===")
    
    if session.metadata then
        -- Old format with nested metadata
        local meta = session.metadata
        if meta.zone then
            table.insert(lines, "Zone: " .. (meta.zone.name or "Unknown"))
            if meta.zone.instanceInfo and meta.zone.instanceInfo.type ~= "none" then
                table.insert(lines, "Instance: " .. (meta.zone.instanceInfo.name or "Unknown"))
            end
        end
        if meta.player then
            table.insert(lines, string.format("Player: %s (%s %s, Level %d)",
                meta.player.name or "Unknown",
                meta.player.spec and meta.player.spec.name or "Unknown",
                meta.player.class or "Unknown",
                meta.player.level or 0))
        end
        if meta.group then
            table.insert(lines, string.format("Group: %s (%d members)",
                meta.group.type or "unknown",
                meta.group.size or 1))
        end
    else
        -- SimpleCombatDetector format with direct fields
        table.insert(lines, "Zone: " .. (session.zone or "Unknown"))
        if session.instance and session.instance ~= session.zone then
            table.insert(lines, "Instance: " .. session.instance)
        end
        table.insert(lines, string.format("Player: %s (%s %s, Level %d)",
            session.player or "Unknown",
            "Unknown", -- spec not tracked yet
            session.playerClass or "Unknown",
            session.playerLevel or 0))
        table.insert(lines, string.format("Group: %s (%d members)",
            session.groupType or "unknown",
            session.groupSize or 1))
    end
    
    -- GUID Map (if available)
    if session.guidMap and next(session.guidMap) then
        table.insert(lines, "")
        table.insert(lines, "=== Entity GUID Map ===")
        local guidCount = 0
        for guid, name in pairs(session.guidMap) do
            guidCount = guidCount + 1
            table.insert(lines, string.format("%s = %s", guid, name))
        end
        table.insert(lines, string.format("Total entities: %d", guidCount))
    end
    
    -- Event log (full for traditional view, virtual scrolling handles large sessions separately)
    table.insert(lines, "")
    table.insert(lines, "=== Event Log ===")
    
    if session.events and #session.events > 0 then
        local totalEvents = #session.events
        
        -- For non-virtual scrolling sessions, show all events
        table.insert(lines, string.format("Total events: %d", totalEvents))
        table.insert(lines, "")
        
        for i, event in ipairs(session.events) do
            -- Get relative timestamp (new format uses 'time', old format needs calculation)
            local relativeTime = event.time or 0
            if relativeTime == 0 then
                -- Fallback for old format
                if event.timestamp and session.startTime then
                    relativeTime = event.timestamp - session.startTime
                elseif event.realTime then
                    relativeTime = event.realTime
                end
            end
            
            local timestamp = string.format("%.3f", relativeTime)
            
            -- Show GUIDs instead of names (names are in GUID map above)
            local sourceId = event.sourceGUID or (event.sourceName and ("[" .. event.sourceName .. "]")) or "?"
            local destId = event.destGUID or (event.destName and ("[" .. event.destName .. "]")) or "?"
            
            local eventLine = string.format("[%s] %s: %s -> %s",
                timestamp,
                event.subevent or "UNKNOWN",
                sourceId,
                destId)
            
            if event.args and #event.args > 0 then
                local argStrings = {}
                for j, arg in ipairs(event.args) do
                    if j <= 3 then -- Limit for performance
                        argStrings[j] = tostring(arg or "nil")
                    end
                end
                if #argStrings > 0 then
                    eventLine = eventLine .. " (" .. table.concat(argStrings, ", ") .. ")"
                end
            end
            
            table.insert(lines, eventLine)
        end
    else
        table.insert(lines, "No events recorded")
    end
    
    table.insert(lines, "")
    table.insert(lines, "=== End of Session ===")
    
    return table.concat(lines, "\n")
end

-- Handle scroll position changes for virtual scrolling
function SessionBrowser:OnScrollChanged(offset)
    if not viewerFrame or not viewerFrame.currentSession then
        return
    end
    
    local session = viewerFrame.currentSession
    local totalEvents = session.eventCount or (session.events and #session.events or 0)
    
    -- Only use virtual scrolling for large sessions
    if totalEvents < CONFIG.MIN_EVENTS_FOR_VIRTUAL then
        return
    end
    
    -- Calculate which chunk should be visible based on scroll position
    local scrollFrame = viewerFrame.scrollFrame
    if not scrollFrame then
        return
    end
    
    local scrollHeight = scrollFrame:GetVerticalScrollRange()
    local scrollPercent = scrollHeight > 0 and (offset / scrollHeight) or 0
    
    local targetChunk = math.floor(scrollPercent * viewerFrame.virtualScroll.totalChunks) + 1
    targetChunk = math.max(1, math.min(targetChunk, viewerFrame.virtualScroll.totalChunks))
    
    self:EnsureChunkLoaded(targetChunk)
end

-- Handle scroll range changes
function SessionBrowser:OnScrollRangeChanged(yrange)
    -- Could be used for dynamic content sizing in the future
end

-- Ensure a specific chunk and its buffers are loaded
function SessionBrowser:EnsureChunkLoaded(chunkIndex)
    if not viewerFrame or not viewerFrame.currentSession then
        return
    end
    
    local vs = viewerFrame.virtualScroll
    local bufferSize = CONFIG.SCROLL_BUFFER_CHUNKS
    
    -- Calculate range of chunks to load
    local startChunk = math.max(1, chunkIndex - bufferSize)
    local endChunk = math.min(vs.totalChunks, chunkIndex + bufferSize)
    
    local needsUpdate = false
    
    -- Load missing chunks in range
    for i = startChunk, endChunk do
        if not vs.loadedChunks[i] then
            self:LoadChunk(i)
            needsUpdate = true
        end
    end
    
    -- Unload chunks outside range to save memory
    for loadedChunk, _ in pairs(vs.loadedChunks) do
        if loadedChunk < startChunk or loadedChunk > endChunk then
            vs.loadedChunks[loadedChunk] = nil
            needsUpdate = true
        end
    end
    
    if needsUpdate then
        self:UpdateVirtualContent()
    end
end

-- Load a specific chunk of events
function SessionBrowser:LoadChunk(chunkIndex)
    if not viewerFrame or not viewerFrame.currentSession then
        return
    end
    
    local session = viewerFrame.currentSession
    local vs = viewerFrame.virtualScroll
    
    local startIdx = (chunkIndex - 1) * CONFIG.EVENTS_PER_CHUNK + 1
    local endIdx = math.min(startIdx + CONFIG.EVENTS_PER_CHUNK - 1, #session.events)
    
    local chunkLines = {}
    
    -- Generate content for this chunk
    for i = startIdx, endIdx do
        local event = session.events[i]
        if event then
            local relativeTime = event.time or 0
            if relativeTime == 0 and event.timestamp and session.startTime then
                relativeTime = event.timestamp - session.startTime
            elseif relativeTime == 0 and event.realTime then
                relativeTime = event.realTime
            end
            
            local timestamp = string.format("%.3f", relativeTime)
            local sourceId = event.sourceGUID or "?"
            local destId = event.destGUID or "?"
            
            local eventLine = string.format("[%s] %s: %s -> %s",
                timestamp,
                event.subevent or "UNKNOWN",
                sourceId,
                destId)
            
            table.insert(chunkLines, eventLine)
        end
    end
    
    vs.loadedChunks[chunkIndex] = table.concat(chunkLines, "\n")
end

-- Update the virtual content display
function SessionBrowser:UpdateVirtualContent()
    if not viewerFrame or not viewerFrame.currentSession then
        return
    end
    
    local session = viewerFrame.currentSession
    local vs = viewerFrame.virtualScroll
    
    -- Build content from loaded chunks
    local contentLines = {}
    
    -- Add session header (always visible)
    table.insert(contentLines, "=== Combat Session Log ===")
    table.insert(contentLines, "Session ID: " .. (session.id or "Unknown"))
    table.insert(contentLines, "Duration: " .. string.format("%.1fs", session.duration or 0))
    table.insert(contentLines, "Total Events: " .. tostring(session.eventCount or 0))
    table.insert(contentLines, "")
    table.insert(contentLines, "=== Event Log (Virtual Scrolling) ===")
    table.insert(contentLines, "")
    
    -- Add loaded chunks in order
    for chunkIndex = 1, vs.totalChunks do
        if vs.loadedChunks[chunkIndex] then
            table.insert(contentLines, vs.loadedChunks[chunkIndex])
        else
            -- Placeholder for unloaded chunks
            local startIdx = (chunkIndex - 1) * CONFIG.EVENTS_PER_CHUNK + 1
            local endIdx = math.min(startIdx + CONFIG.EVENTS_PER_CHUNK - 1, #session.events)
            table.insert(contentLines, string.format("[Loading events %d-%d...]", startIdx, endIdx))
        end
    end
    
    local newContent = table.concat(contentLines, "\n")
    vs.currentContent = newContent
    
    viewerEditBox:SetText(newContent)
    viewerFrame.lastContent = newContent
end

-- Refresh viewer content based on selected format
function SessionBrowser:RefreshViewerContent()
    if not viewerFrame or not viewerFrame:IsShown() or not viewerFrame.currentSession then
        return
    end
    
    local session = viewerFrame.currentSession
    local totalEvents = session.eventCount or (session.events and #session.events or 0)
    
    -- Use virtual scrolling for large sessions
    if totalEvents >= CONFIG.MIN_EVENTS_FOR_VIRTUAL then
        self:InitializeVirtualScrolling(session)
        self:EnsureChunkLoaded(1) -- Load initial chunk
    else
        -- Use traditional full content for smaller sessions
        local selectedFormat = UIDropDownMenu_GetSelectedValue(viewerFrame.formatDropdown) or "raw"
        local content = self:GenerateViewerContent(session, selectedFormat)
        
        viewerEditBox:SetText(content)
        viewerFrame.lastContent = content
    end
    
    addon:Debug("Refreshed viewer content: %d events, virtual=%s", totalEvents, tostring(totalEvents >= CONFIG.MIN_EVENTS_FOR_VIRTUAL))
end

-- Initialize virtual scrolling for a session
function SessionBrowser:InitializeVirtualScrolling(session)
    if not viewerFrame then
        return
    end
    
    local vs = viewerFrame.virtualScroll
    vs.loadedChunks = {}
    vs.totalChunks = math.ceil(#session.events / CONFIG.EVENTS_PER_CHUNK)
    vs.currentContent = ""
    
    addon:Debug("Initialized virtual scrolling: %d events, %d chunks", #session.events, vs.totalChunks)
end

-- Generate content in different formats for the viewer
function SessionBrowser:GenerateViewerContent(session, format)
    if format == "raw" then
        return self:FormatAsRaw(session)
    elseif format == "text" then
        return self:GenerateSessionLog(session)  -- Use existing function
    elseif format == "json" then
        return self:FormatAsJSON(session)
    else
        return "Unknown format: " .. tostring(format)
    end
end

-- Format as raw session data
function SessionBrowser:FormatAsRaw(session)
    local lines = {}
    
    -- Raw session object
    table.insert(lines, "=== RAW SESSION DATA ===")
    table.insert(lines, "Session ID: " .. tostring(session.id))
    table.insert(lines, "Duration: " .. tostring(session.duration))
    table.insert(lines, "Event Count: " .. tostring(session.eventCount))
    table.insert(lines, "Start Time: " .. tostring(session.startTime))
    table.insert(lines, "End Time: " .. tostring(session.endTime))
    table.insert(lines, "Stored At: " .. tostring(session.storedAt))
    table.insert(lines, "Server Time: " .. tostring(session.serverTime))
    table.insert(lines, "Compressed: " .. tostring(session.compressed))
    table.insert(lines, "")
    
    -- Raw metadata
    if session.metadata then
        table.insert(lines, "=== RAW METADATA ===")
        self:DumpTableToLines(session.metadata, lines, 0)
        table.insert(lines, "")
    end
    
    -- GUID Map (unified format for both guidMap and nameMapping)
    if session.guidMap and next(session.guidMap) then
        table.insert(lines, "=== GUID MAP ===")
        local guidCount = 0
        for guid, name in pairs(session.guidMap) do
            guidCount = guidCount + 1
            table.insert(lines, string.format("%s = %s", guid, name))
        end
        table.insert(lines, string.format("Total entities: %d", guidCount))
        table.insert(lines, "")
    elseif session.nameMapping then
        table.insert(lines, "=== NAME MAPPING ===")
        local guidCount = 0
        for guid, nameData in pairs(session.nameMapping) do
            guidCount = guidCount + 1
            table.insert(lines, string.format("GUID %d: %s", guidCount, guid))
            table.insert(lines, string.format("  Name: %s", nameData.name))
            table.insert(lines, string.format("  Type: %s", nameData.guidType))
            table.insert(lines, string.format("  Cached: %s", nameData.cached and "Yes" or "No"))
            if nameData.metadata then
                table.insert(lines, "  Metadata:")
                self:DumpTableToLines(nameData.metadata, lines, 2)
            end
            table.insert(lines, "")
        end
        table.insert(lines, string.format("Total entities: %d", guidCount))
        table.insert(lines, "")
    end
    
    -- Raw events (limited for performance in raw view)
    if session.events then
        local totalEvents = #session.events
        table.insert(lines, "=== RAW EVENTS (" .. totalEvents .. " total) ===")
        
        -- Limit raw events display for performance
        local maxRawEvents = 100
        if totalEvents > maxRawEvents then
            table.insert(lines, string.format("Showing first %d events (of %d total) for performance", maxRawEvents, totalEvents))
            table.insert(lines, "Use Text format for full event log with virtual scrolling")
            table.insert(lines, "")
            
            for i = 1, maxRawEvents do
                local event = session.events[i]
                if event then
                    table.insert(lines, "Event " .. i .. ":")
                    self:DumpTableToLines(event, lines, 1)
                    table.insert(lines, "")
                end
            end
        else
            -- Show all events if under the limit
            for i, event in ipairs(session.events) do
                table.insert(lines, "Event " .. i .. ":")
                self:DumpTableToLines(event, lines, 1)
                table.insert(lines, "")
            end
        end
    end
    
    return table.concat(lines, "\n")
end

-- Helper function to dump table structure to lines
function SessionBrowser:DumpTableToLines(tbl, lines, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)
    
    if not tbl then
        table.insert(lines, spacing .. "nil")
        return
    end
    
    if type(tbl) ~= "table" then
        table.insert(lines, spacing .. tostring(tbl))
        return
    end
    
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            table.insert(lines, spacing .. tostring(k) .. " = {")
            self:DumpTableToLines(v, lines, indent + 1)
            table.insert(lines, spacing .. "}")
        else
            table.insert(lines, spacing .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- Delete selected session
function SessionBrowser:DeleteSelectedSession()
    if not selectedSession then
        addon:Warn("No session selected")
        return
    end
    
    if addon.StorageManager then
        local deleted = addon.StorageManager:DeleteSession(selectedSession.id)
        if deleted then
            addon:Info("Session deleted: " .. selectedSession.id)
            selectedSession = nil
            self:RefreshSessionList()
            if viewerFrame and viewerFrame:IsShown() then
                viewerFrame:Hide()
            end
        else
            addon:Error("Failed to delete session")
        end
    end
end

-- Clear all sessions
function SessionBrowser:ClearAllSessions()
    if addon.StorageManager then
        addon.StorageManager:ClearAllSessions()
        addon:Info("All sessions cleared")
        selectedSession = nil
        self:RefreshSessionList()
        if viewerFrame and viewerFrame:IsShown() then
            viewerFrame:Hide()
        end
    end
end


-- Format as JSON (simplified implementation)
function SessionBrowser:FormatAsJSON(data)
    local function serializeValue(value, indent)
        indent = indent or 0
        local spacing = string.rep("  ", indent)
        
        if type(value) == "table" then
            local result = "{\n"
            for k, v in pairs(value) do
                result = result .. spacing .. "  \"" .. tostring(k) .. "\": " .. serializeValue(v, indent + 1) .. ",\n"
            end
            result = result .. spacing .. "}"
            return result
        elseif type(value) == "string" then
            return "\"" .. value:gsub("\"", "\\\"") .. "\""
        elseif type(value) == "number" then
            return tostring(value)
        elseif type(value) == "boolean" then
            return value and "true" or "false"
        else
            return "\"" .. tostring(value) .. "\""
        end
    end
    
    -- Create a copy of data with GUID mapping included
    local jsonData = {}
    for k, v in pairs(data) do
        jsonData[k] = v
    end
    
    -- Add GUID map if available
    if data.guidMap and next(data.guidMap) then
        jsonData.guidMap = data.guidMap
    elseif data.nameMapping and next(data.nameMapping) then
        jsonData.guidMap = {}
        for guid, nameData in pairs(data.nameMapping) do
            jsonData.guidMap[guid] = nameData.name
        end
    end
    
    return serializeValue(jsonData)
end


-- Public API
function SessionBrowser:IsShown()
    return browserFrame and browserFrame:IsShown()
end

function SessionBrowser:GetStatus()
    return {
        isInitialized = isInitialized,
        isShown = self:IsShown(),
        selectedSession = selectedSession and selectedSession.id or nil
    }
end