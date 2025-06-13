-- EnhancedSessionDetailWindow.lua
-- Enhanced detailed view with advanced charting and combat insights - FIXED DATA POPULATION

local addonName, addon = ...

addon.EnhancedSessionDetailWindow = {}
local EnhancedSessionDetailWindow = addon.EnhancedSessionDetailWindow

-- Chart configuration
local CHART_COLORS = {
    dps = { 1, 0.3, 0.3 },
    hps = { 0.3, 1, 0.3 },
    damageTaken = { 1, 0.8, 0.2 },
    groupDamage = { 0.8, 0.4, 0.8 }
}

-- Debug function to inspect session data
local function DebugSessionData(sessionData)
    if not addon.DEBUG then return end

    print("=== SESSION DATA DEBUG ===")
    print("Session ID:", sessionData.sessionId)
    print("Enhanced data present:", sessionData.enhancedData ~= nil)

    if sessionData.enhancedData then
        local ed = sessionData.enhancedData
        print("Participants:", ed.participants and "YES" or "NO")
        print("Cooldown usage:", ed.cooldownUsage and (#ed.cooldownUsage .. " events") or "NO")
        print("Deaths:", ed.deaths and (#ed.deaths .. " events") or "NO")
        print("Damage taken:", ed.damageTaken and (#ed.damageTaken .. " events") or "NO")
        print("Group damage:", ed.groupDamage and (#ed.groupDamage .. " events") or "NO")
        print("Healing events:", ed.healingEvents and (#ed.healingEvents .. " events") or "NO")

        if ed.participants then
            local count = 0
            for _ in pairs(ed.participants) do count = count + 1 end
            print("Participant count:", count)
        end
    else
        print("No enhanced data found")
    end
    print("==========================")
end

-- Create enhanced detail window
function EnhancedSessionDetailWindow:Create(sessionData)
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end

    -- Debug the incoming session data
    DebugSessionData(sessionData)

    -- Try to get enhanced data if not already present
    if not sessionData.enhancedData and addon.SessionManager then
        -- Check if this session has enhanced data stored
        local storedSession = addon.SessionManager:GetSession(sessionData.sessionId)
        if storedSession and storedSession.enhancedData then
            sessionData.enhancedData = storedSession.enhancedData
            if addon.DEBUG then
                print("Retrieved enhanced data from stored session")
            end
        end
    end

    -- If still no enhanced data, try to get current enhanced data if this is a recent session
    if not sessionData.enhancedData and addon.EnhancedCombatLogger then
        local currentEnhancedData = addon.EnhancedCombatLogger:GetEnhancedSessionData()
        if currentEnhancedData then
            sessionData.enhancedData = currentEnhancedData
            if addon.DEBUG then
                print("Using current enhanced data from logger")
            end
        end
    end

    local frame = CreateFrame("Frame", addonName .. "EnhancedSessionDetailFrame", UIParent)
    frame:SetSize(800, 600)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Background and border
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.9)

    local border = frame:CreateTexture(nil, "BORDER")
    border:SetAllPoints(frame)
    border:SetColorTexture(0.4, 0.4, 0.4, 1)
    bg:SetPoint("TOPLEFT", border, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)

    -- Make draggable
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- === HEADER SECTION ===
    self:CreateHeaderSection(frame, sessionData)

    -- === TABBED INTERFACE ===
    self:CreateTabbedInterface(frame, sessionData)

    self.frame = frame
    self.sessionData = sessionData
    self.currentTab = "overview"

    frame:Show()
    self:ShowTab("overview")
end

-- Create header section
function EnhancedSessionDetailWindow:CreateHeaderSection(frame, sessionData)
    local headerPanel = CreateFrame("Frame", nil, frame)
    headerPanel:SetSize(780, 80)
    headerPanel:SetPoint("TOP", frame, "TOP", 0, -10)

    local headerBg = headerPanel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(headerPanel)
    headerBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    -- Session title
    local title = headerPanel:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 16, "OUTLINE")
    title:SetPoint("TOP", headerPanel, "TOP", 0, -8)
    title:SetText(string.format("Enhanced Combat Analysis: %s", sessionData.sessionId))
    title:SetTextColor(1, 1, 1, 1)

    -- Metadata in columns
    local startTime = date("%H:%M:%S", time() + (sessionData.startTime - GetTime()))

    local leftMeta = headerPanel:CreateFontString(nil, "OVERLAY")
    leftMeta:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    leftMeta:SetPoint("TOPLEFT", headerPanel, "TOPLEFT", 10, -25)
    leftMeta:SetText(string.format("Start: %s | Duration: %.1fs | Location: %s",
        startTime, sessionData.duration, sessionData.location or "Unknown"))
    leftMeta:SetJustifyH("LEFT")

    local rightMeta = headerPanel:CreateFontString(nil, "OVERLAY")
    rightMeta:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    rightMeta:SetPoint("TOPRIGHT", headerPanel, "TOPRIGHT", -10, -25)
    local enhancedStatus = sessionData.enhancedData and "Enhanced" or "Basic"
    rightMeta:SetText(string.format("Quality: %d | Content: %s | Data: %s",
        sessionData.qualityScore, sessionData.contentType or "normal", enhancedStatus))
    rightMeta:SetJustifyH("RIGHT")

    -- Performance summary line
    local perfSummary = headerPanel:CreateFontString(nil, "OVERLAY")
    perfSummary:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    perfSummary:SetPoint("BOTTOM", headerPanel, "BOTTOM", 0, 8)
    perfSummary:SetText(string.format("DPS: %s (Peak: %s) | HPS: %s (Peak: %s)",
        addon.CombatTracker:FormatNumber(sessionData.avgDPS),
        addon.CombatTracker:FormatNumber(sessionData.peakDPS),
        addon.CombatTracker:FormatNumber(sessionData.avgHPS),
        addon.CombatTracker:FormatNumber(sessionData.peakHPS)))
    perfSummary:SetTextColor(0.9, 0.9, 0.9, 1)

    frame.headerPanel = headerPanel
end

-- Create tabbed interface
function EnhancedSessionDetailWindow:CreateTabbedInterface(frame, sessionData)
    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetSize(780, 30)
    tabBar:SetPoint("TOP", frame.headerPanel, "BOTTOM", 0, -5)

    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints(tabBar)
    tabBarBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)

    -- Tab buttons
    local tabs = {
        { id = "overview",     text = "Timeline" },
        { id = "participants", text = "Participants" },
        { id = "damage",       text = "Damage Analysis" },
        { id = "insights",     text = "Combat Insights" }
    }

    frame.tabButtons = {}
    for i, tab in ipairs(tabs) do
        local button = CreateFrame("Button", nil, tabBar)
        button:SetSize(150, 25)
        button:SetPoint("LEFT", tabBar, "LEFT", 50 + (i - 1) * 155, 0)

        local buttonBg = button:CreateTexture(nil, "BACKGROUND")
        buttonBg:SetAllPoints(button)
        buttonBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        button.bg = buttonBg

        local buttonText = button:CreateFontString(nil, "OVERLAY")
        buttonText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
        buttonText:SetPoint("CENTER", button, "CENTER", 0, 0)
        buttonText:SetText(tab.text)
        buttonText:SetTextColor(0.8, 0.8, 0.8, 1)
        button.text = buttonText

        button:SetScript("OnClick", function()
            self:ShowTab(tab.id)
        end)

        button:SetScript("OnEnter", function()
            if self.currentTab ~= tab.id then
                buttonBg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
            end
        end)

        button:SetScript("OnLeave", function()
            if self.currentTab ~= tab.id then
                buttonBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            end
        end)

        frame.tabButtons[tab.id] = button
    end

    -- Content area
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetSize(780, 450)
    contentArea:SetPoint("TOP", tabBar, "BOTTOM", 0, -5)

    local contentBg = contentArea:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints(contentArea)
    contentBg:SetColorTexture(0.02, 0.02, 0.02, 0.9)

    frame.tabBar = tabBar
    frame.contentArea = contentArea
end

-- Show specific tab
function EnhancedSessionDetailWindow:ShowTab(tabId)
    -- Update tab button states
    for id, button in pairs(self.frame.tabButtons) do
        if id == tabId then
            button.bg:SetColorTexture(0.4, 0.4, 0.4, 1)
            button.text:SetTextColor(1, 1, 1, 1)
        else
            button.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            button.text:SetTextColor(0.8, 0.8, 0.8, 1)
        end
    end

    -- Clear content area
    if self.frame.currentContent then
        self.frame.currentContent:Hide()
        self.frame.currentContent = nil
    end

    -- Create new content
    self.currentTab = tabId
    if tabId == "overview" then
        self:CreateTimelineTab()
    elseif tabId == "participants" then
        self:CreateParticipantsTab()
    elseif tabId == "damage" then
        self:CreateDamageTab()
    elseif tabId == "insights" then
        self:CreateInsightsTab()
    end
end

-- Create timeline tab with enhanced charting
function EnhancedSessionDetailWindow:CreateTimelineTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    -- Chart area
    local chartArea = CreateFrame("Frame", nil, content)
    chartArea:SetSize(740, 300)
    chartArea:SetPoint("TOP", content, "TOP", 0, -20)

    local chartBg = chartArea:CreateTexture(nil, "BACKGROUND")
    chartBg:SetAllPoints(chartArea)
    chartBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    -- Create enhanced timeline visualization
    self:CreateEnhancedTimeline(chartArea, self.sessionData)

    -- Chart controls
    local controlsFrame = CreateFrame("Frame", nil, content)
    controlsFrame:SetSize(740, 100)
    controlsFrame:SetPoint("BOTTOM", content, "BOTTOM", 0, 20)

    self:CreateChartControls(controlsFrame)

    content:Show()
    self.frame.currentContent = content
end

-- Create enhanced timeline with multiple data series
function EnhancedSessionDetailWindow:CreateEnhancedTimeline(chartArea, sessionData)
    local timelineData = sessionData.timelineData or {}

    if #timelineData == 0 then
        local noDataText = chartArea:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", chartArea, "CENTER", 0, 0)
        noDataText:SetText("No detailed timeline data available")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)
        return
    end

    -- Chart configuration
    local chartWidth = 740
    local chartHeight = 280
    local pointWidth = chartWidth / math.max(1, #timelineData - 1)

    -- Find max values for scaling
    local maxDPS, maxHPS = 0, 0
    for _, point in ipairs(timelineData) do
        maxDPS = math.max(maxDPS, point.instantDPS or point.averageDPS or 0)
        maxHPS = math.max(maxHPS, point.instantHPS or point.averageHPS or 0)
    end

    -- Draw grid lines
    self:DrawChartGrid(chartArea, chartWidth, chartHeight)

    -- Draw performance lines
    self:DrawPerformanceLines(chartArea, timelineData, chartWidth, chartHeight, maxDPS, maxHPS)

    -- Draw cooldown markers if enhanced data is available
    if sessionData.enhancedData and sessionData.enhancedData.cooldownUsage then
        self:DrawCooldownMarkers(chartArea, sessionData.enhancedData.cooldownUsage, sessionData.duration, chartWidth,
            chartHeight)
    end

    -- Draw death markers if enhanced data is available
    if sessionData.enhancedData and sessionData.enhancedData.deaths then
        self:DrawDeathMarkers(chartArea, sessionData.enhancedData.deaths, sessionData.duration, chartWidth, chartHeight)
    end

    -- Chart legend
    self:CreateChartLegend(chartArea, maxDPS, maxHPS)
end

-- Draw chart grid
function EnhancedSessionDetailWindow:DrawChartGrid(chartArea, width, height)
    -- Horizontal grid lines
    for i = 1, 4 do
        local line = chartArea:CreateTexture(nil, "BORDER")
        line:SetSize(width, 1)
        line:SetPoint("BOTTOM", chartArea, "BOTTOM", 0, (i * height / 5))
        line:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    end

    -- Vertical grid lines (time markers)
    for i = 1, 9 do
        local line = chartArea:CreateTexture(nil, "BORDER")
        line:SetSize(1, height)
        line:SetPoint("LEFT", chartArea, "LEFT", (i * width / 10), 0)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.2)
    end
end

-- Draw performance lines
function EnhancedSessionDetailWindow:DrawPerformanceLines(chartArea, timelineData, width, height, maxDPS, maxHPS)
    local pointWidth = width / math.max(1, #timelineData - 1)
    local previousDPSPoint, previousHPSPoint = nil, nil

    for i, point in ipairs(timelineData) do
        if i <= 200 then -- Limit for performance
            local x = (i - 1) * pointWidth

            -- DPS line
            local dpsValue = point.instantDPS or point.averageDPS or 0
            if maxDPS > 0 then
                local dpsHeight = dpsValue > 0 and math.max(2, (dpsValue / maxDPS) * height) or 1

                if previousDPSPoint then
                    self:DrawLine(chartArea, previousDPSPoint.x, previousDPSPoint.y, x, dpsHeight, CHART_COLORS.dps)
                end
                previousDPSPoint = { x = x, y = dpsHeight }
            end

            -- HPS line
            local hpsValue = point.instantHPS or point.averageHPS or 0
            if maxHPS > 0 then
                local hpsHeight = hpsValue > 0 and math.max(2, (hpsValue / maxHPS) * height) or 1

                if previousHPSPoint then
                    self:DrawLine(chartArea, previousHPSPoint.x, previousHPSPoint.y, x, hpsHeight, CHART_COLORS.hps)
                end
                previousHPSPoint = { x = x, y = hpsHeight }
            end
        end
    end
end

-- Draw line between two points
function EnhancedSessionDetailWindow:DrawLine(parent, x1, y1, x2, y2, color)
    local lineLength = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local segments = math.max(1, math.floor(lineLength / 3))

    for j = 1, segments do
        local t = j / segments
        local x = x1 + t * (x2 - x1)
        local y = y1 + t * (y2 - y1)

        local pixel = parent:CreateTexture(nil, "ARTWORK")
        pixel:SetSize(2, 2)
        pixel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
        pixel:SetColorTexture(color[1], color[2], color[3], 0.9)
    end
end

-- Draw cooldown markers
function EnhancedSessionDetailWindow:DrawCooldownMarkers(chartArea, cooldowns, duration, width, height)
    for _, cooldown in ipairs(cooldowns) do
        if cooldown.elapsed and cooldown.elapsed >= 0 and cooldown.elapsed <= duration then
            local x = (cooldown.elapsed / duration) * width

            -- Vertical line
            local line = chartArea:CreateTexture(nil, "OVERLAY")
            line:SetSize(2, height)
            line:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", x, 0)
            line:SetColorTexture(cooldown.color[1], cooldown.color[2], cooldown.color[3], 0.8)

            -- Cooldown label
            local label = chartArea:CreateFontString(nil, "OVERLAY")
            label:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 9, "OUTLINE")
            label:SetPoint("BOTTOM", chartArea, "BOTTOMLEFT", x, height - 15)
            label:SetText(cooldown.spellName)
            label:SetTextColor(cooldown.color[1], cooldown.color[2], cooldown.color[3], 1)
            label:SetRotation(math.rad(-45)) -- Diagonal text
        end
    end
end

-- Draw death markers
function EnhancedSessionDetailWindow:DrawDeathMarkers(chartArea, deaths, duration, width, height)
    for _, death in ipairs(deaths) do
        if death.elapsed and death.elapsed >= 0 and death.elapsed <= duration then
            local x = (death.elapsed / duration) * width

            -- Death marker (skull symbol)
            local marker = chartArea:CreateFontString(nil, "OVERLAY")
            marker:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
            marker:SetPoint("BOTTOM", chartArea, "BOTTOMLEFT", x, height - 30)
            marker:SetText("💀")
            marker:SetTextColor(1, 0.2, 0.2, 1)
        end
    end
end

-- Create chart legend
function EnhancedSessionDetailWindow:CreateChartLegend(chartArea, maxDPS, maxHPS)
    local legend = chartArea:CreateFontString(nil, "OVERLAY")
    legend:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    legend:SetPoint("TOPRIGHT", chartArea, "TOPRIGHT", -10, -10)
    legend:SetText(string.format("Max: %s DPS | %s HPS\nRed: DPS | Green: HPS | Lines: Cooldowns | 💀: Deaths",
        addon.CombatTracker:FormatNumber(maxDPS),
        addon.CombatTracker:FormatNumber(maxHPS)))
    legend:SetTextColor(0.8, 0.8, 0.8, 1)
    legend:SetJustifyH("RIGHT")
end

-- Create chart controls
function EnhancedSessionDetailWindow:CreateChartControls(controlsFrame)
    local controlsBg = controlsFrame:CreateTexture(nil, "BACKGROUND")
    controlsBg:SetAllPoints(controlsFrame)
    controlsBg:SetColorTexture(0.1, 0.1, 0.1, 0.7)

    local title = controlsFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    title:SetPoint("TOP", controlsFrame, "TOP", 0, -5)
    title:SetText("Chart Controls & Event Timeline")

    -- Display recent events if available
    if self.sessionData.enhancedData then
        local events = {}

        -- Collect significant events
        for _, cooldown in ipairs(self.sessionData.enhancedData.cooldownUsage or {}) do
            table.insert(events, {
                time = cooldown.elapsed,
                text = string.format("%.1fs: %s used %s", cooldown.elapsed, cooldown.sourceName, cooldown.spellName),
                color = cooldown.color
            })
        end

        for _, death in ipairs(self.sessionData.enhancedData.deaths or {}) do
            table.insert(events, {
                time = death.elapsed,
                text = string.format("%.1fs: %s died", death.elapsed, death.destName),
                color = { 1, 0.2, 0.2 }
            })
        end

        -- Sort by time
        table.sort(events, function(a, b) return a.time < b.time end)

        -- Display first few events
        for i = 1, math.min(3, #events) do
            local event = events[i]
            local eventText = controlsFrame:CreateFontString(nil, "OVERLAY")
            eventText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
            eventText:SetPoint("TOPLEFT", controlsFrame, "TOPLEFT", 10, -25 - (i * 15))
            eventText:SetText(event.text)
            eventText:SetTextColor(event.color[1], event.color[2], event.color[3], 1)
        end

        if #events > 3 then
            local moreText = controlsFrame:CreateFontString(nil, "OVERLAY")
            moreText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
            moreText:SetPoint("TOPLEFT", controlsFrame, "TOPLEFT", 10, -85)
            moreText:SetText(string.format("... and %d more events", #events - 3))
            moreText:SetTextColor(0.6, 0.6, 0.6, 1)
        end
    end
end

-- Create participants tab - ENHANCED VERSION
function EnhancedSessionDetailWindow:CreateParticipantsTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Combat Participants")

    -- Check for enhanced data
    if not self.sessionData.enhancedData or not self.sessionData.enhancedData.participants then
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", content, "CENTER", 0, 0)
        noDataText:SetText("No participant data available\n(Enhanced logging was not active during this session)")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)

        -- Add instructions for enabling enhanced logging
        local instructionText = content:CreateFontString(nil, "OVERLAY")
        instructionText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
        instructionText:SetPoint("CENTER", content, "CENTER", 0, -40)
        instructionText:SetText(
        "To see participant data in future sessions:\n• Enhanced logging should be automatically enabled\n• Use '/myui enhancedlog' to check status")
        instructionText:SetTextColor(0.8, 0.8, 0.6, 1)

        content:Show()
        self.frame.currentContent = content
        return
    end

    -- Store reference for filtering
    self.participantsContent = content
    
    -- Convert participants table to array (keep all for filtering)
    local participants = {}
    for guid, participant in pairs(self.sessionData.enhancedData.participants) do
        table.insert(participants, participant)
    end
    
    -- Sort by total damage/healing dealt
    table.sort(participants, function(a, b)
        return (a.damageDealt + a.healingDealt) > (b.damageDealt + b.healingDealt)
    end)
    
    self.allParticipants = participants
    self.filteredParticipants = participants
    
    -- Create filter controls
    self:CreateParticipantFilters(content)
    
    -- Create the participants list
    self:CreateParticipantsList(content)

    
    content:Show()
    self.frame.currentContent = content
end

-- Create participant filter controls
function EnhancedSessionDetailWindow:CreateParticipantFilters(parent)
    local filterFrame = CreateFrame("Frame", nil, parent)
    filterFrame:SetSize(740, 50)
    filterFrame:SetPoint("TOP", parent, "TOP", 0, -45)
    
    local filterBg = filterFrame:CreateTexture(nil, "BACKGROUND")
    filterBg:SetAllPoints(filterFrame)
    filterBg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    
    -- Reorganize controls in a more compact layout
    
    -- Search box
    local searchBox = CreateFrame("EditBox", nil, filterFrame, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetPoint("LEFT", filterFrame, "LEFT", 10, 5)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    
    local searchLabel = filterFrame:CreateFontString(nil, "OVERLAY")
    searchLabel:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 9, "OUTLINE")
    searchLabel:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 0, 2)
    searchLabel:SetText("Search:")
    searchLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    
    -- Type filter dropdown
    local typeFilter = CreateFrame("Frame", nil, filterFrame, "UIDropDownMenuTemplate")
    typeFilter:SetPoint("LEFT", searchBox, "RIGHT", 10, 5)
    UIDropDownMenu_SetWidth(typeFilter, 90)
    UIDropDownMenu_SetText(typeFilter, "All Types")
    
    local typeLabel = filterFrame:CreateFontString(nil, "OVERLAY")
    typeLabel:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 9, "OUTLINE")
    typeLabel:SetPoint("BOTTOMLEFT", typeFilter, "TOPLEFT", 20, 2)
    typeLabel:SetText("Type:")
    typeLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    
    -- Show zero contributors toggle
    local showZeroBtn = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
    showZeroBtn:SetSize(14, 14)
    showZeroBtn:SetPoint("LEFT", typeFilter, "RIGHT", 15, 5)
    showZeroBtn:SetChecked(false)
    
    local showZeroLabel = filterFrame:CreateFontString(nil, "OVERLAY")
    showZeroLabel:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 9, "OUTLINE")
    showZeroLabel:SetPoint("LEFT", showZeroBtn, "RIGHT", 5, 0)
    showZeroLabel:SetText("Show Zero Contributors")
    showZeroLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    
    -- Clear filters button
    local clearBtn = CreateFrame("Button", nil, filterFrame)
    clearBtn:SetSize(50, 18)
    clearBtn:SetPoint("LEFT", showZeroLabel, "RIGHT", 15, 0)
    clearBtn:SetNormalFontObject("GameFontNormalSmall")
    clearBtn:SetText("Clear")
    clearBtn:GetFontString():SetTextColor(0.8, 0.8, 0.8, 1)
    
    local clearBg = clearBtn:CreateTexture(nil, "BACKGROUND")
    clearBg:SetAllPoints(clearBtn)
    clearBg:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    
    -- Stats display
    local statsText = filterFrame:CreateFontString(nil, "OVERLAY")
    statsText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    statsText:SetPoint("RIGHT", filterFrame, "RIGHT", -10, 5)
    statsText:SetJustifyH("RIGHT")
    statsText:SetTextColor(0.8, 0.8, 0.6, 1)
    
    -- Store references
    self.participantFilters = {
        searchBox = searchBox,
        typeFilter = typeFilter,
        statsText = statsText,
        clearBtn = clearBtn,
        showZeroBtn = showZeroBtn
    }
    
    -- Set up filter functionality
    self:SetupParticipantFilters()
end

-- Set up participant filter functionality
function EnhancedSessionDetailWindow:SetupParticipantFilters()
    local filters = self.participantFilters
    local window = self  -- Store reference to avoid context issues
    
    -- Search box functionality
    filters.searchBox:SetScript("OnTextChanged", function(editBox, userInput)
        if userInput then
            window:FilterParticipants()
        end
    end)
    
    -- Type filter dropdown
    UIDropDownMenu_Initialize(filters.typeFilter, function(frame, level)
        local info = UIDropDownMenu_CreateInfo()
        
        info.text = "All Types"
        info.value = "all"
        info.func = function() 
            UIDropDownMenu_SetSelectedValue(filters.typeFilter, "all")
            UIDropDownMenu_SetText(filters.typeFilter, "All Types")
            window:FilterParticipants()
        end
        info.checked = UIDropDownMenu_GetSelectedValue(filters.typeFilter) == "all"
        UIDropDownMenu_AddButton(info)
        
        info.text = "Players"
        info.value = "player"
        info.func = function() 
            UIDropDownMenu_SetSelectedValue(filters.typeFilter, "player")
            UIDropDownMenu_SetText(filters.typeFilter, "Players")
            window:FilterParticipants()
        end
        info.checked = UIDropDownMenu_GetSelectedValue(filters.typeFilter) == "player"
        UIDropDownMenu_AddButton(info)
        
        info.text = "Pets"
        info.value = "pet"
        info.func = function() 
            UIDropDownMenu_SetSelectedValue(filters.typeFilter, "pet")
            UIDropDownMenu_SetText(filters.typeFilter, "Pets")
            window:FilterParticipants()
        end
        info.checked = UIDropDownMenu_GetSelectedValue(filters.typeFilter) == "pet"
        UIDropDownMenu_AddButton(info)
        
        info.text = "NPCs"
        info.value = "npc"
        info.func = function() 
            UIDropDownMenu_SetSelectedValue(filters.typeFilter, "npc")
            UIDropDownMenu_SetText(filters.typeFilter, "NPCs")
            window:FilterParticipants()
        end
        info.checked = UIDropDownMenu_GetSelectedValue(filters.typeFilter) == "npc"
        UIDropDownMenu_AddButton(info)
    end)
    
    UIDropDownMenu_SetSelectedValue(filters.typeFilter, "all")
    
    -- Show zero contributors toggle
    filters.showZeroBtn:SetScript("OnClick", function()
        window:FilterParticipants()
    end)
    
    -- Clear button
    filters.clearBtn:SetScript("OnClick", function()
        filters.searchBox:SetText("")
        UIDropDownMenu_SetSelectedValue(filters.typeFilter, "all")
        UIDropDownMenu_SetText(filters.typeFilter, "All Types")
        filters.showZeroBtn:SetChecked(false)
        window:FilterParticipants()
    end)
    
    -- Initial stats update
    self:UpdateParticipantStats()
end

-- Filter participants based on current filter settings
function EnhancedSessionDetailWindow:FilterParticipants()
    local searchText = self.participantFilters.searchBox:GetText():lower()
    local typeFilter = UIDropDownMenu_GetSelectedValue(self.participantFilters.typeFilter) or "all"
    local showZeroContributors = self.participantFilters.showZeroBtn:GetChecked()
    
    self.filteredParticipants = {}
    
    for _, participant in ipairs(self.allParticipants) do
        local matchesSearch = searchText == "" or participant.name:lower():find(searchText, 1, true)
        local matchesType = typeFilter == "all" or 
                           (typeFilter == "player" and participant.isPlayer) or
                           (typeFilter == "pet" and participant.isPet) or
                           (typeFilter == "npc" and not participant.isPlayer and not participant.isPet)
        
        -- Zero contribution filter
        local totalContribution = (participant.damageDealt or 0) + (participant.healingDealt or 0) + (participant.damageTaken or 0)
        local matchesContribution = showZeroContributors or totalContribution > 0
        
        if matchesSearch and matchesType and matchesContribution then
            table.insert(self.filteredParticipants, participant)
        end
    end
    
    self:UpdateParticipantStats()
    self:RefreshParticipantsList()
end

-- Update participant statistics display
function EnhancedSessionDetailWindow:UpdateParticipantStats()
    local total = #self.allParticipants
    local filtered = #self.filteredParticipants
    local statsText = string.format("Showing %d of %d participants", filtered, total)
    self.participantFilters.statsText:SetText(statsText)
end

-- Create the virtualized participants list
function EnhancedSessionDetailWindow:CreateParticipantsList(parent)
    -- Create header row
    local headerRow = CreateFrame("Frame", nil, parent)
    headerRow:SetSize(740, 25)
    headerRow:SetPoint("TOP", parent, "TOP", 0, -100)
    
    local headerBg = headerRow:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(headerRow)
    headerBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    
    -- Initialize sorting state
    self.sortColumn = "total"  -- default sort by total damage + healing
    self.sortDirection = "desc"  -- descending by default
    
    -- Clickable column headers with sorting
    local nameHeaderBtn = CreateFrame("Button", nil, headerRow)
    nameHeaderBtn:SetSize(150, 25)
    nameHeaderBtn:SetPoint("LEFT", headerRow, "LEFT", 10, 0)
    nameHeaderBtn:SetScript("OnClick", function() self:SortParticipants("name") end)
    
    local nameHeader = nameHeaderBtn:CreateFontString(nil, "OVERLAY")
    nameHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    nameHeader:SetAllPoints(nameHeaderBtn)
    nameHeader:SetText("Name")
    nameHeader:SetJustifyH("LEFT")
    nameHeader:SetTextColor(1, 1, 1, 1)
    nameHeaderBtn.text = nameHeader
    
    local typeHeaderBtn = CreateFrame("Button", nil, headerRow)
    typeHeaderBtn:SetSize(80, 25)
    typeHeaderBtn:SetPoint("LEFT", headerRow, "LEFT", 170, 0)
    typeHeaderBtn:SetScript("OnClick", function() self:SortParticipants("type") end)
    
    local typeHeader = typeHeaderBtn:CreateFontString(nil, "OVERLAY")
    typeHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    typeHeader:SetAllPoints(typeHeaderBtn)
    typeHeader:SetText("Type")
    typeHeader:SetJustifyH("CENTER")
    typeHeader:SetTextColor(1, 1, 1, 1)
    typeHeaderBtn.text = typeHeader
    
    local damageHeaderBtn = CreateFrame("Button", nil, headerRow)
    damageHeaderBtn:SetSize(100, 25)
    damageHeaderBtn:SetPoint("LEFT", headerRow, "LEFT", 260, 0)
    damageHeaderBtn:SetScript("OnClick", function() self:SortParticipants("damage") end)
    
    local damageHeader = damageHeaderBtn:CreateFontString(nil, "OVERLAY")
    damageHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    damageHeader:SetAllPoints(damageHeaderBtn)
    damageHeader:SetText("Damage Dealt")
    damageHeader:SetJustifyH("RIGHT")
    damageHeader:SetTextColor(1, 1, 1, 1)
    damageHeaderBtn.text = damageHeader
    
    local healingHeaderBtn = CreateFrame("Button", nil, headerRow)
    healingHeaderBtn:SetSize(100, 25)
    healingHeaderBtn:SetPoint("LEFT", headerRow, "LEFT", 370, 0)
    healingHeaderBtn:SetScript("OnClick", function() self:SortParticipants("healing") end)
    
    local healingHeader = healingHeaderBtn:CreateFontString(nil, "OVERLAY")
    healingHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    healingHeader:SetAllPoints(healingHeaderBtn)
    healingHeader:SetText("Healing Dealt")
    healingHeader:SetJustifyH("RIGHT")
    healingHeader:SetTextColor(1, 1, 1, 1)
    healingHeaderBtn.text = healingHeader
    
    local takenHeaderBtn = CreateFrame("Button", nil, headerRow)
    takenHeaderBtn:SetSize(100, 25)
    takenHeaderBtn:SetPoint("LEFT", headerRow, "LEFT", 480, 0)
    takenHeaderBtn:SetScript("OnClick", function() self:SortParticipants("taken") end)
    
    local takenHeader = takenHeaderBtn:CreateFontString(nil, "OVERLAY")
    takenHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    takenHeader:SetAllPoints(takenHeaderBtn)
    takenHeader:SetText("Damage Taken")
    takenHeader:SetJustifyH("RIGHT")
    takenHeader:SetTextColor(1, 1, 1, 1)
    takenHeaderBtn.text = takenHeader
    
    -- Store header references for sorting indicators
    self.columnHeaders = {
        name = nameHeaderBtn,
        type = typeHeaderBtn,
        damage = damageHeaderBtn,
        healing = healingHeaderBtn,
        taken = takenHeaderBtn
    }
    
    -- Virtualized scrollable list
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(740, 300)
    scrollFrame:SetPoint("TOP", headerRow, "BOTTOM", -20, -5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(720, 300)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Store references for virtualization
    self.participantsList = {
        scrollFrame = scrollFrame,
        scrollChild = scrollChild,
        headerRow = headerRow,
        visibleRows = {},
        rowHeight = 27,
        maxVisibleRows = 13
    }
    
    -- Create reusable row frames for virtualization
    for i = 1, self.participantsList.maxVisibleRows do
        local row = self:CreateParticipantRow(scrollChild, i)
        table.insert(self.participantsList.visibleRows, row)
    end
    
    -- Set up scroll handling
    scrollFrame:SetScript("OnVerticalScroll", function(frame, delta)
        self:UpdateVisibleParticipants()
    end)
    
    -- Initial sorting indicators
    self:UpdateSortingIndicators()
    
    -- Initial population
    self:RefreshParticipantsList()
end

-- Create a reusable participant row frame
function EnhancedSessionDetailWindow:CreateParticipantRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(720, 25)
    row:Hide()
    
    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints(row)
    row.bg = rowBg
    
    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    nameText:SetPoint("LEFT", row, "LEFT", 10, 0)
    nameText:SetSize(150, 0)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText
    
    -- Type
    local typeText = row:CreateFontString(nil, "OVERLAY")
    typeText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    typeText:SetPoint("LEFT", row, "LEFT", 170, 0)
    typeText:SetSize(80, 0)
    typeText:SetJustifyH("CENTER")
    typeText:SetTextColor(0.7, 0.7, 0.7, 1)
    row.typeText = typeText
    
    -- Damage dealt
    local damageText = row:CreateFontString(nil, "OVERLAY")
    damageText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    damageText:SetPoint("LEFT", row, "LEFT", 260, 0)
    damageText:SetSize(100, 0)
    damageText:SetJustifyH("RIGHT")
    damageText:SetTextColor(1, 0.4, 0.4, 1)
    row.damageText = damageText
    
    -- Healing dealt
    local healingText = row:CreateFontString(nil, "OVERLAY")
    healingText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    healingText:SetPoint("LEFT", row, "LEFT", 370, 0)
    healingText:SetSize(100, 0)
    healingText:SetJustifyH("RIGHT")
    healingText:SetTextColor(0.4, 1, 0.4, 1)
    row.healingText = healingText
    
    -- Damage taken
    local takenText = row:CreateFontString(nil, "OVERLAY")
    takenText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    takenText:SetPoint("LEFT", row, "LEFT", 480, 0)
    takenText:SetSize(100, 0)
    takenText:SetJustifyH("RIGHT")
    takenText:SetTextColor(1, 0.8, 0.4, 1)
    row.takenText = takenText
    
    return row
end

-- Refresh the participants list display
function EnhancedSessionDetailWindow:RefreshParticipantsList()
    local list = self.participantsList
    local numParticipants = #self.filteredParticipants
    
    -- Update scroll child height for proper scrolling
    local totalHeight = math.max(300, numParticipants * list.rowHeight)
    list.scrollChild:SetHeight(totalHeight)
    
    -- Update visible participants
    self:UpdateVisibleParticipants()
end

-- Update which participants are visible in the virtualized list
function EnhancedSessionDetailWindow:UpdateVisibleParticipants()
    local list = self.participantsList
    local numParticipants = #self.filteredParticipants
    
    if numParticipants == 0 then
        -- Hide all rows
        for _, row in ipairs(list.visibleRows) do
            row:Hide()
        end
        return
    end
    
    -- Calculate which participants should be visible
    local scrollOffset = list.scrollFrame:GetVerticalScroll()
    local startIndex = math.floor(scrollOffset / list.rowHeight) + 1
    
    -- Update visible rows
    for i, row in ipairs(list.visibleRows) do
        local participantIndex = startIndex + i - 1
        
        if participantIndex <= numParticipants then
            local participant = self.filteredParticipants[participantIndex]
            
            -- Position the row
            row:SetPoint("TOP", list.scrollChild, "TOP", 0, -(participantIndex - 1) * list.rowHeight)
            
            -- Update row data
            self:UpdateParticipantRowData(row, participant, participantIndex)
            row:Show()
        else
            row:Hide()
        end
    end
end

-- Update a single participant row with data
function EnhancedSessionDetailWindow:UpdateParticipantRowData(row, participant, index)
    -- Alternating row background
    local alpha = index % 2 == 0 and 0.1 or 0.05
    row.bg:SetColorTexture(alpha, alpha, alpha, 0.5)
    
    -- Name with color coding
    row.nameText:SetText(participant.name)
    if participant.isPlayer then
        row.nameText:SetTextColor(0.3, 1, 0.3, 1)
    elseif participant.isPet then
        row.nameText:SetTextColor(0.8, 0.8, 0.3, 1)
    else
        row.nameText:SetTextColor(1, 0.5, 0.5, 1)
    end
    
    -- Type
    local typeStr = participant.isPlayer and "Player" or (participant.isPet and "Pet" or "NPC")
    row.typeText:SetText(typeStr)
    
    -- Stats
    row.damageText:SetText(addon.CombatTracker:FormatNumber(participant.damageDealt or 0))
    row.healingText:SetText(addon.CombatTracker:FormatNumber(participant.healingDealt or 0))
    row.takenText:SetText(addon.CombatTracker:FormatNumber(participant.damageTaken or 0))
end

-- Sort participants by column
function EnhancedSessionDetailWindow:SortParticipants(column)
    -- Toggle direction if clicking same column, otherwise default to desc
    if self.sortColumn == column then
        self.sortDirection = self.sortDirection == "desc" and "asc" or "desc"
    else
        self.sortColumn = column
        self.sortDirection = "desc"
    end
    
    -- Sort the participants array
    table.sort(self.allParticipants, function(a, b)
        local valueA, valueB
        
        if column == "name" then
            valueA = a.name:lower()
            valueB = b.name:lower()
        elseif column == "type" then
            -- Sort order: Player, Pet, NPC
            local function getTypeOrder(participant)
                if participant.isPlayer then return 1
                elseif participant.isPet then return 2
                else return 3 end
            end
            valueA = getTypeOrder(a)
            valueB = getTypeOrder(b)
        elseif column == "damage" then
            valueA = a.damageDealt or 0
            valueB = b.damageDealt or 0
        elseif column == "healing" then
            valueA = a.healingDealt or 0
            valueB = b.healingDealt or 0
        elseif column == "taken" then
            valueA = a.damageTaken or 0
            valueB = b.damageTaken or 0
        else -- total (default)
            valueA = (a.damageDealt or 0) + (a.healingDealt or 0)
            valueB = (b.damageDealt or 0) + (b.healingDealt or 0)
        end
        
        if self.sortDirection == "asc" then
            return valueA < valueB
        else
            return valueA > valueB
        end
    end)
    
    -- Update column header indicators
    self:UpdateSortingIndicators()
    
    -- Refresh the filtered view
    self:FilterParticipants()
end

-- Update sorting indicators in column headers
function EnhancedSessionDetailWindow:UpdateSortingIndicators()
    -- Reset all headers
    for _, header in pairs(self.columnHeaders) do
        local text = header.text:GetText()
        -- Remove existing arrows
        text = text:gsub(" [↑↓]", "")
        header.text:SetText(text)
        header.text:SetTextColor(1, 1, 1, 1)
    end
    
    -- Add arrow to current sort column
    if self.columnHeaders[self.sortColumn] then
        local header = self.columnHeaders[self.sortColumn]
        local text = header.text:GetText()
        local arrow = self.sortDirection == "asc" and "↑" or "↓"
        header.text:SetText(text .. " " .. arrow)
        header.text:SetTextColor(0.8, 0.8, 1, 1)  -- Highlight sorted column
    end
end

-- Create damage analysis tab - FIXED VERSION
function EnhancedSessionDetailWindow:CreateDamageTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Damage Analysis")

    if not self.sessionData.enhancedData then
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", content, "CENTER", 0, 0)
        noDataText:SetText("No damage analysis data available\n(Enhanced logging was not active during this session)")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)

        content:Show()
        self.frame.currentContent = content
        return
    end

    -- Split into sections
    self:CreateDamageTakenSection(content, self.sessionData.enhancedData.damageTaken or {})
    self:CreateGroupDamageSection(content, self.sessionData.enhancedData.groupDamage or {})

    content:Show()
    self.frame.currentContent = content
end

-- Create insights tab - FIXED VERSION
function EnhancedSessionDetailWindow:CreateInsightsTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Combat Insights & Recommendations")

    -- Performance insights
    local insights = self:GenerateInsights(self.sessionData)

    local yOffset = -50
    for i, insight in ipairs(insights) do
        local insightFrame = CreateFrame("Frame", nil, content)
        insightFrame:SetSize(740, 60)
        insightFrame:SetPoint("TOP", content, "TOP", 0, yOffset)

        local insightBg = insightFrame:CreateTexture(nil, "BACKGROUND")
        insightBg:SetAllPoints(insightFrame)
        insightBg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

        local insightText = insightFrame:CreateFontString(nil, "OVERLAY")
        insightText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
        insightText:SetPoint("TOPLEFT", insightFrame, "TOPLEFT", 10, -10)
        insightText:SetSize(720, 0)
        insightText:SetText(insight.text)
        insightText:SetJustifyH("LEFT")
        insightText:SetTextColor(insight.color[1], insight.color[2], insight.color[3], 1)

        yOffset = yOffset - 70
        if yOffset < -400 then break end -- Limit display
    end

    content:Show()
    self.frame.currentContent = content
end

-- Generate performance insights - ENHANCED VERSION
function EnhancedSessionDetailWindow:GenerateInsights(sessionData)
    local insights = {}

    -- Basic performance insights
    if sessionData.qualityScore >= 80 then
        table.insert(insights, {
            text = "✓ High Quality Session: This combat session shows excellent performance metrics and data quality.",
            color = { 0.3, 1, 0.3 }
        })
    elseif sessionData.qualityScore >= 60 then
        table.insert(insights, {
            text = "⚠ Good Session: Solid performance with some room for improvement in consistency or duration.",
            color = { 1, 0.8, 0.3 }
        })
    else
        table.insert(insights, {
            text = "⚠ Below Average: This session may have been too short or had performance issues.",
            color = { 1, 0.5, 0.3 }
        })
    end

    -- Duration analysis
    if sessionData.duration < 10 then
        table.insert(insights, {
            text = "Short Combat: Consider longer encounters for more reliable performance metrics.",
            color = { 1, 0.8, 0.4 }
        })
    elseif sessionData.duration > 120 then
        table.insert(insights, {
            text = "Extended Combat: Long encounter data is excellent for performance analysis.",
            color = { 0.4, 1, 0.4 }
        })
    end

    -- Content type insights
    if sessionData.contentType == "scaled" then
        table.insert(insights, {
            text = "Scaled Content: Performance metrics adjusted for level-scaled content (timewalking, etc.).",
            color = { 0.6, 0.8, 1 }
        })
    end

    -- Performance comparison insights
    if addon.CombatTracker then
        local baseline = addon.CombatTracker:GetContentBaseline(sessionData.contentType or "normal", 10)
        if baseline.sampleCount > 0 then
            local dpsRatio = baseline.avgDPS > 0 and (sessionData.avgDPS / baseline.avgDPS) or 1
            local hpsRatio = baseline.avgHPS > 0 and (sessionData.avgHPS / baseline.avgHPS) or 1

            if dpsRatio > 1.2 then
                table.insert(insights, {
                    text = string.format("✓ Above Average DPS: %.0f%% above your baseline for %s content.",
                        (dpsRatio - 1) * 100, sessionData.contentType or "normal"),
                    color = { 0.3, 1, 0.3 }
                })
            elseif dpsRatio < 0.8 then
                table.insert(insights, {
                    text = string.format("⚠ Below Average DPS: %.0f%% below your baseline for %s content.",
                        (1 - dpsRatio) * 100, sessionData.contentType or "normal"),
                    color = { 1, 0.6, 0.3 }
                })
            end

            if hpsRatio > 1.2 and sessionData.avgHPS > 1000 then
                table.insert(insights, {
                    text = string.format("✓ High Healing Output: %.0f%% above your baseline healing.",
                        (hpsRatio - 1) * 100),
                    color = { 0.3, 1, 0.3 }
                })
            end
        end
    end

    -- Enhanced data insights
    if sessionData.enhancedData then
        local cooldowns = #(sessionData.enhancedData.cooldownUsage or {})
        local deaths = #(sessionData.enhancedData.deaths or {})
        local participantCount = 0

        if sessionData.enhancedData.participants then
            for _ in pairs(sessionData.enhancedData.participants) do
                participantCount = participantCount + 1
            end
        end

        if cooldowns > 0 then
            table.insert(insights, {
                text = string.format("Cooldown Usage: %d major cooldowns were used during this encounter.", cooldowns),
                color = { 0.8, 0.6, 1 }
            })
        end

        if deaths > 0 then
            table.insert(insights, {
                text = string.format("⚠ Deaths Occurred: %d death(s) recorded during this encounter.", deaths),
                color = { 1, 0.4, 0.4 }
            })
        elseif sessionData.duration > 30 then
            table.insert(insights, {
                text = "✓ Clean Fight: No deaths recorded during this extended encounter.",
                color = { 0.3, 1, 0.3 }
            })
        end

        if participantCount > 1 then
            table.insert(insights, {
                text = string.format("Group Content: %d participants detected in this encounter.", participantCount),
                color = { 0.6, 0.8, 1 }
            })
        end

        -- Damage taken analysis
        local damageTaken = sessionData.enhancedData.damageTaken or {}
        if #damageTaken > 0 then
            local totalDamageTaken = 0
            for _, dmg in ipairs(damageTaken) do
                totalDamageTaken = totalDamageTaken + dmg.amount
            end

            local dtps = sessionData.duration > 0 and (totalDamageTaken / sessionData.duration) or 0
            if dtps > 50000 then
                table.insert(insights, {
                    text = string.format("High Damage Taken: %.0f DTPS - Consider defensive cooldowns or positioning.",
                        dtps),
                    color = { 1, 0.6, 0.3 }
                })
            elseif dtps < 10000 and sessionData.duration > 20 then
                table.insert(insights, {
                    text = "✓ Low Damage Taken: Excellent damage avoidance throughout the encounter.",
                    color = { 0.3, 1, 0.3 }
                })
            end
        end
    else
        table.insert(insights, {
            text = "ℹ Enhanced Logging: Enable enhanced logging for detailed cooldown and participant analysis.",
            color = { 0.7, 0.7, 0.7 }
        })
    end

    -- Timeline analysis insights
    if sessionData.timelineData and #sessionData.timelineData > 0 then
        -- Calculate performance consistency
        local dpsValues = {}
        for _, point in ipairs(sessionData.timelineData) do
            if point.instantDPS and point.instantDPS > 0 then
                table.insert(dpsValues, point.instantDPS)
            end
        end

        if #dpsValues > 5 then
            local mean = 0
            for _, dps in ipairs(dpsValues) do
                mean = mean + dps
            end
            mean = mean / #dpsValues

            local variance = 0
            for _, dps in ipairs(dpsValues) do
                variance = variance + (dps - mean) ^ 2
            end
            variance = variance / (#dpsValues - 1)

            local stdDev = math.sqrt(variance)
            local cv = stdDev / mean -- Coefficient of variation

            if cv < 0.3 then
                table.insert(insights, {
                    text = "✓ Consistent Performance: Your DPS remained steady throughout the encounter.",
                    color = { 0.3, 1, 0.3 }
                })
            elseif cv > 0.6 then
                table.insert(insights, {
                    text = "⚠ Variable Performance: Consider maintaining rotation consistency for better DPS.",
                    color = { 1, 0.6, 0.3 }
                })
            end
        end
    end

    return insights
end

-- Helper functions for damage sections
function EnhancedSessionDetailWindow:CreateDamageTakenSection(parent, damageTaken)
    local sectionFrame = CreateFrame("Frame", nil, parent)
    sectionFrame:SetSize(740, 180)
    sectionFrame:SetPoint("TOP", parent, "TOP", 0, -60)

    local sectionBg = sectionFrame:CreateTexture(nil, "BACKGROUND")
    sectionBg:SetAllPoints(sectionFrame)
    sectionBg:SetColorTexture(0.05, 0.05, 0.05, 0.6)

    local sectionTitle = sectionFrame:CreateFontString(nil, "OVERLAY")
    sectionTitle:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    sectionTitle:SetPoint("TOP", sectionFrame, "TOP", 0, -10)
    sectionTitle:SetText(string.format("Personal Damage Taken (%d events)", #damageTaken))
    sectionTitle:SetTextColor(1, 0.8, 0.4, 1)

    if #damageTaken == 0 then
        local noDataText = sectionFrame:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
        noDataText:SetPoint("CENTER", sectionFrame, "CENTER", 0, 0)
        noDataText:SetText("No damage taken events recorded")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)
        return
    end

    -- Aggregate damage by source
    local sourceData = {}
    local totalDamage = 0

    for _, dmg in ipairs(damageTaken) do
        local key = dmg.sourceName or "Unknown"
        if not sourceData[key] then
            sourceData[key] = { name = key, damage = 0, hits = 0 }
        end
        sourceData[key].damage = sourceData[key].damage + dmg.amount
        sourceData[key].hits = sourceData[key].hits + 1
        totalDamage = totalDamage + dmg.amount
    end

    -- Convert to array and sort
    local sources = {}
    for _, data in pairs(sourceData) do
        table.insert(sources, data)
    end
    table.sort(sources, function(a, b) return a.damage > b.damage end)

    -- Display top damage sources
    local yOffset = -35
    for i = 1, math.min(5, #sources) do
        local source = sources[i]
        local percent = totalDamage > 0 and (source.damage / totalDamage * 100) or 0

        local sourceText = sectionFrame:CreateFontString(nil, "OVERLAY")
        sourceText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        sourceText:SetPoint("TOPLEFT", sectionFrame, "TOPLEFT", 10, yOffset)
        sourceText:SetText(string.format("%s: %s (%.1f%%) - %d hits",
            source.name, addon.CombatTracker:FormatNumber(source.damage), percent, source.hits))
        sourceText:SetTextColor(1, 0.8, 0.6, 1)

        yOffset = yOffset - 20
    end

    -- Total summary
    local totalText = sectionFrame:CreateFontString(nil, "OVERLAY")
    totalText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    totalText:SetPoint("BOTTOMRIGHT", sectionFrame, "BOTTOMRIGHT", -10, 10)
    local dtps = self.sessionData.duration > 0 and (totalDamage / self.sessionData.duration) or 0
    totalText:SetText(string.format("Total: %s (%.0f DTPS)",
        addon.CombatTracker:FormatNumber(totalDamage), dtps))
    totalText:SetTextColor(1, 1, 0.6, 1)
end

function EnhancedSessionDetailWindow:CreateGroupDamageSection(parent, groupDamage)
    local sectionFrame = CreateFrame("Frame", nil, parent)
    sectionFrame:SetSize(740, 180)
    sectionFrame:SetPoint("TOP", parent, "TOP", 0, -250)

    local sectionBg = sectionFrame:CreateTexture(nil, "BACKGROUND")
    sectionBg:SetAllPoints(sectionFrame)
    sectionBg:SetColorTexture(0.05, 0.05, 0.05, 0.6)

    local sectionTitle = sectionFrame:CreateFontString(nil, "OVERLAY")
    sectionTitle:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    sectionTitle:SetPoint("TOP", sectionFrame, "TOP", 0, -10)
    sectionTitle:SetText(string.format("Group Damage Events (%d events)", #groupDamage))
    sectionTitle:SetTextColor(0.8, 0.4, 1, 1)

    if #groupDamage == 0 then
        local noDataText = sectionFrame:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
        noDataText:SetPoint("CENTER", sectionFrame, "CENTER", 0, 0)
        noDataText:SetText("No group damage events recorded\n(Group damage tracking may be disabled)")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)
        return
    end

    -- Similar analysis for group damage
    local sourceData = {}
    local totalDamage = 0

    for _, dmg in ipairs(groupDamage) do
        local key = dmg.sourceName or "Unknown"
        if not sourceData[key] then
            sourceData[key] = { name = key, damage = 0, hits = 0, targets = {} }
        end
        sourceData[key].damage = sourceData[key].damage + dmg.amount
        sourceData[key].hits = sourceData[key].hits + 1
        sourceData[key].targets[dmg.destName] = true
        totalDamage = totalDamage + dmg.amount
    end

    -- Convert to array and sort
    local sources = {}
    for _, data in pairs(sourceData) do
        data.targetCount = 0
        for _ in pairs(data.targets) do
            data.targetCount = data.targetCount + 1
        end
        table.insert(sources, data)
    end
    table.sort(sources, function(a, b) return a.damage > b.damage end)

    -- Display top group damage sources
    local yOffset = -35
    for i = 1, math.min(5, #sources) do
        local source = sources[i]
        local percent = totalDamage > 0 and (source.damage / totalDamage * 100) or 0

        local sourceText = sectionFrame:CreateFontString(nil, "OVERLAY")
        sourceText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        sourceText:SetPoint("TOPLEFT", sectionFrame, "TOPLEFT", 10, yOffset)
        sourceText:SetText(string.format("%s: %s (%.1f%%) - %d hits, %d targets",
            source.name, addon.CombatTracker:FormatNumber(source.damage),
            percent, source.hits, source.targetCount))
        sourceText:SetTextColor(0.8, 0.6, 1, 1)

        yOffset = yOffset - 20
    end
end

-- Close button and controls
function EnhancedSessionDetailWindow:CreateCloseButton(frame)
    local closeBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    closeBtn:SetSize(80, 25)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        self:Hide()
    end)
end

-- Show enhanced session detail window
function EnhancedSessionDetailWindow:Show(sessionData)
    -- Try to attach enhanced data if available and not already present
    if not sessionData.enhancedData then
        if addon.EnhancedCombatLogger then
            local enhancedData = addon.EnhancedCombatLogger:GetEnhancedSessionData()
            if enhancedData then
                sessionData.enhancedData = enhancedData
                if addon.DEBUG then
                    print("Attached current enhanced data to session")
                end
            end
        end

        -- Also try to get from session manager if this is a stored session
        if addon.SessionManager then
            local storedSession = addon.SessionManager:GetSession(sessionData.sessionId)
            if storedSession and storedSession.enhancedData then
                sessionData.enhancedData = storedSession.enhancedData
                if addon.DEBUG then
                    print("Retrieved enhanced data from stored session")
                end
            end
        end
    end

    self:Create(sessionData)
    self:CreateCloseButton(self.frame)
end

-- Hide window
function EnhancedSessionDetailWindow:Hide()
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
end
