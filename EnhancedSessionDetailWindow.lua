-- EnhancedSessionDetailWindow.lua
-- Enhanced detailed view with advanced charting and combat insights

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

-- Create enhanced detail window
function EnhancedSessionDetailWindow:Create(sessionData)
    if self.frame then
        self.frame:Hide()
        self.frame = nil
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
    rightMeta:SetText(string.format("Quality: %d | Content: %s | Actions: %d",
        sessionData.qualityScore, sessionData.contentType or "normal", sessionData.actionCount or 0))
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

-- Create participants tab
function EnhancedSessionDetailWindow:CreateParticipantsTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Combat Participants")

    -- Participants list (scrollable)
    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(740, 380)
    scrollFrame:SetPoint("TOP", content, "TOP", -20, -50)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(720, 400)
    scrollFrame:SetScrollChild(scrollChild)

    -- Get participant data if available
    if self.sessionData.enhancedData and self.sessionData.enhancedData.participants then
        local summary = {}
        for guid, participant in pairs(self.sessionData.enhancedData.participants) do
            table.insert(summary, participant)
        end

        -- Sort by total damage/healing dealt
        table.sort(summary, function(a, b)
            return (a.damageDealt + a.healingDealt) > (b.damageDealt + b.healingDealt)
        end)

        -- Create participant rows
        for i, participant in ipairs(summary) do
            if i <= 20 then -- Limit display
                local row = CreateFrame("Frame", nil, scrollChild)
                row:SetSize(720, 25)
                row:SetPoint("TOP", scrollChild, "TOP", 0, -(i - 1) * 27)

                local rowBg = row:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints(row)
                rowBg:SetColorTexture(i % 2 == 0 and 0.1 or 0.05, i % 2 == 0 and 0.1 or 0.05, i % 2 == 0 and 0.1 or 0.05,
                    0.5)

                -- Name
                local nameText = row:CreateFontString(nil, "OVERLAY")
                nameText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
                nameText:SetPoint("LEFT", row, "LEFT", 10, 0)
                nameText:SetSize(150, 0)
                nameText:SetText(participant.name)
                nameText:SetJustifyH("LEFT")

                -- Color code by type
                if participant.isPlayer then
                    nameText:SetTextColor(0.3, 1, 0.3, 1)
                elseif participant.isPet then
                    nameText:SetTextColor(0.8, 0.8, 0.3, 1)
                else
                    nameText:SetTextColor(1, 0.5, 0.5, 1)
                end

                -- Damage dealt
                local damageText = row:CreateFontString(nil, "OVERLAY")
                damageText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
                damageText:SetPoint("LEFT", row, "LEFT", 170, 0)
                damageText:SetSize(100, 0)
                damageText:SetText(addon.CombatTracker:FormatNumber(participant.damageDealt or 0))
                damageText:SetJustifyH("RIGHT")
                damageText:SetTextColor(1, 0.4, 0.4, 1)

                -- Healing dealt
                local healingText = row:CreateFontString(nil, "OVERLAY")
                healingText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
                healingText:SetPoint("LEFT", row, "LEFT", 280, 0)
                healingText:SetSize(100, 0)
                healingText:SetText(addon.CombatTracker:FormatNumber(participant.healingDealt or 0))
                healingText:SetJustifyH("RIGHT")
                healingText:SetTextColor(0.4, 1, 0.4, 1)

                -- Damage taken
                local takenText = row:CreateFontString(nil, "OVERLAY")
                takenText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
                takenText:SetPoint("LEFT", row, "LEFT", 390, 0)
                takenText:SetSize(100, 0)
                takenText:SetText(addon.CombatTracker:FormatNumber(participant.damageTaken or 0))
                takenText:SetJustifyH("RIGHT")
                takenText:SetTextColor(1, 0.8, 0.4, 1)

                -- Type
                local typeText = row:CreateFontString(nil, "OVERLAY")
                typeText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
                typeText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                typeText:SetSize(80, 0)
                local typeStr = participant.isPlayer and "Player" or (participant.isPet and "Pet" or "NPC")
                typeText:SetText(typeStr)
                typeText:SetJustifyH("CENTER")
                typeText:SetTextColor(0.7, 0.7, 0.7, 1)
            end
        end

        scrollChild:SetHeight(math.max(400, #summary * 27))
    else
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", content, "CENTER", 0, 0)
        noDataText:SetText("No participant data available\n(Enhanced logging was not active)")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)
    end

    content:Show()
    self.frame.currentContent = content
end

-- Create damage analysis tab
function EnhancedSessionDetailWindow:CreateDamageTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Damage Analysis")

    -- Split into two sections: Damage Taken and Group Damage
    if self.sessionData.enhancedData then
        -- Personal damage taken section
        self:CreateDamageTakenSection(content, self.sessionData.enhancedData.damageTaken or {})

        -- Group damage section
        self:CreateGroupDamageSection(content, self.sessionData.enhancedData.groupDamage or {})
    else
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", content, "CENTER", 0, 0)
        noDataText:SetText("No damage analysis data available\n(Enhanced logging was not active)")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)
    end

    content:Show()
    self.frame.currentContent = content
end

-- Create insights tab
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

-- Generate performance insights
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

    -- Enhanced data insights
    if sessionData.enhancedData then
        local cooldowns = #(sessionData.enhancedData.cooldownUsage or {})
        local deaths = #(sessionData.enhancedData.deaths or {})

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
        end
    else
        table.insert(insights, {
            text = "ℹ Enhanced Logging: Enable enhanced logging for detailed cooldown and participant analysis.",
            color = { 0.7, 0.7, 0.7 }
        })
    end

    return insights
end

-- Helper functions for damage sections
function EnhancedSessionDetailWindow:CreateDamageTakenSection(parent, damageTaken)
    -- Implementation would create a detailed breakdown of damage sources
    local sectionTitle = parent:CreateFontString(nil, "OVERLAY")
    sectionTitle:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -60)
    sectionTitle:SetText(string.format("Personal Damage Taken (%d events)", #damageTaken))
    sectionTitle:SetTextColor(1, 0.8, 0.4, 1)
end

function EnhancedSessionDetailWindow:CreateGroupDamageSection(parent, groupDamage)
    -- Implementation would create a breakdown of group-wide damage patterns
    local sectionTitle = parent:CreateFontString(nil, "OVERLAY")
    sectionTitle:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    sectionTitle:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -200)
    sectionTitle:SetText(string.format("Group Damage Events (%d events)", #groupDamage))
    sectionTitle:SetTextColor(0.8, 0.4, 1, 1)
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
    -- Attach enhanced data if available
    if addon.EnhancedCombatLogger then
        local enhancedData = addon.EnhancedCombatLogger:GetEnhancedSessionData()
        if enhancedData then
            sessionData.enhancedData = enhancedData
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
