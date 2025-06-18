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
    -- Debug output removed for cleaner user experience
end

-- Create enhanced detail window
function EnhancedSessionDetailWindow:Create(sessionData)
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
    
    -- Clean up any open share/import windows
    if self.shareWindow then
        self.shareWindow:Hide()
        self.shareWindow = nil
    end
    
    if self.importWindow then
        self.importWindow:Hide()
        self.importWindow = nil
    end

    -- Debug the incoming session data
    DebugSessionData(sessionData)

    -- Try to get enhanced data if not already present
    if not sessionData.enhancedData and addon.SessionManager then
        -- Check if this session has enhanced data stored
        local storedSession = addon.SessionManager:GetSession(sessionData.sessionId)
        if storedSession and storedSession.enhancedData then
            sessionData.enhancedData = storedSession.enhancedData
            addon:Debug("Retrieved enhanced data from stored session")
        end
    end

    -- If still no enhanced data, try to get current enhanced data if this is a recent session
    if not sessionData.enhancedData and addon.EnhancedCombatLogger then
        local currentEnhancedData = addon.EnhancedCombatLogger:GetEnhancedSessionData()
        if currentEnhancedData then
            sessionData.enhancedData = currentEnhancedData
            addon:Debug("Using current enhanced data from logger")
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

    -- Register with focus management
    if addon.FocusManager then
        addon.FocusManager:RegisterWindow(frame, nil)
    end

    -- Standard close button (top-right)
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        self:Hide()
    end)

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

    -- Session title (left-aligned)
    local title = headerPanel:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 16, "OUTLINE")
    title:SetPoint("TOPLEFT", headerPanel, "TOPLEFT", 10, -8)
    title:SetText(string.format("Enhanced Combat Analysis: %s", sessionData.sessionId))
    title:SetTextColor(1, 1, 1, 1)
    title:SetJustifyH("LEFT")

    -- Row 1: Start, Location, Quality
    local startTime = date("%H:%M:%S", time() + (sessionData.startTime - GetTime()))

    local row1 = headerPanel:CreateFontString(nil, "OVERLAY")
    row1:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    row1:SetPoint("TOPLEFT", headerPanel, "TOPLEFT", 10, -25)
    row1:SetText(string.format("Start: %s | Location: %s | Quality: %d",
        startTime, sessionData.location or "Unknown", sessionData.qualityScore))
    row1:SetJustifyH("LEFT")

    -- Row 2: Duration, Content/Scale type
    local row2 = headerPanel:CreateFontString(nil, "OVERLAY")
    row2:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    row2:SetPoint("TOPLEFT", headerPanel, "TOPLEFT", 10, -40)
    row2:SetText(string.format("Duration: %.1fs | Content: %s",
        sessionData.duration, sessionData.contentType or "normal"))
    row2:SetJustifyH("LEFT")

    -- Performance summary line (left-aligned)
    local perfSummary = headerPanel:CreateFontString(nil, "OVERLAY")
    perfSummary:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    perfSummary:SetPoint("BOTTOMLEFT", headerPanel, "BOTTOMLEFT", 10, 8)
    perfSummary:SetText(string.format("DPS: %s (Peak: %s) | HPS: %s (Peak: %s)",
        addon.CombatTracker:FormatNumber(sessionData.avgDPS),
        addon.CombatTracker:FormatNumber(sessionData.peakDPS),
        addon.CombatTracker:FormatNumber(sessionData.avgHPS),
        addon.CombatTracker:FormatNumber(sessionData.peakHPS)))
    perfSummary:SetTextColor(0.9, 0.9, 0.9, 1)
    perfSummary:SetJustifyH("LEFT")

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
        { id = "log",          text = "Log" },
        { id = "blacklist",    text = "Blacklist" },
        { id = "whitelist",    text = "Whitelist" }
        -- { id = "damage",       text = "Damage Analysis" },
        -- { id = "insights",     text = "Combat Insights" }
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
        buttonText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
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
    contentArea:SetSize(780, 480)
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

    -- Clear content area properly
    if self.frame.currentContent then
        self.frame.currentContent:Hide()
        self.frame.currentContent:SetParent(nil)
        self.frame.currentContent = nil
    end

    -- Create new content
    self.currentTab = tabId
    if tabId == "overview" then
        self:CreateTimelineTab()
    elseif tabId == "participants" then
        self:CreateParticipantsTab()
    elseif tabId == "log" then
        self:CreateLogTab()
    elseif tabId == "blacklist" then
        self:CreateBlacklistTab()
    elseif tabId == "whitelist" then
        self:CreateWhitelistTab()
    -- elseif tabId == "damage" then
    --     self:CreateDamageTab()
    -- elseif tabId == "insights" then
    --     self:CreateInsightsTab()
    end
end

-- Create timeline tab with enhanced charting
function EnhancedSessionDetailWindow:CreateTimelineTab()
    -- Initialize chart filters if not already set
    if not self.chartFilters then
        self.chartFilters = {
            showHPS = true,
            showDPS = true,
            showCooldowns = true,
            showPlayerDeaths = true,
            showMinionDeaths = true,
            showBossDeaths = true,
            applyBlacklist = true,      -- Apply blacklist filtering
            showBlacklistedOnly = false -- Show only blacklisted entities (whitelist mode)
        }
    end

    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    -- Chart area
    local chartArea = CreateFrame("Frame", nil, content)
    chartArea:SetSize(740, 320)
    chartArea:SetPoint("TOP", content, "TOP", 0, -10)

    local chartBg = chartArea:CreateTexture(nil, "BACKGROUND")
    chartBg:SetAllPoints(chartArea)
    chartBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    -- Create enhanced timeline visualization
    self:CreateEnhancedTimeline(chartArea, self.sessionData)

    -- Chart controls
    local controlsFrame = CreateFrame("Frame", nil, content)
    controlsFrame:SetSize(740, 90)
    controlsFrame:SetPoint("BOTTOM", content, "BOTTOM", 0, 10)

    self:CreateChartControls(controlsFrame)

    content:Show()
    self.frame.currentContent = content
end

-- Create enhanced timeline with multiple data series
function EnhancedSessionDetailWindow:CreateEnhancedTimeline(chartArea, sessionData)
    local timelineData = sessionData.timelineData or {}

    if #timelineData == 0 then
        local noDataText = chartArea:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", chartArea, "CENTER", 0, 0)
        noDataText:SetText("No detailed timeline data available")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)
        return
    end

    -- Chart configuration
    local chartWidth = 740
    local chartHeight = 300
    local pointWidth = chartWidth / math.max(1, #timelineData - 1)

    -- Find max values for scaling - only for enabled charts
    local maxDPS, maxHPS = 0, 0
    if self.chartFilters and self.chartFilters.showDPS then
        for _, point in ipairs(timelineData) do
            maxDPS = math.max(maxDPS, point.instantDPS or point.averageDPS or 0)
        end
    end
    if self.chartFilters and self.chartFilters.showHPS then
        for _, point in ipairs(timelineData) do
            maxHPS = math.max(maxHPS, point.instantHPS or point.averageHPS or 0)
        end
    end

    -- Draw grid lines with time axis and Y-axis labels
    self:DrawChartGrid(chartArea, chartWidth, chartHeight, sessionData.duration, maxDPS, maxHPS)

    -- Draw performance lines
    self:DrawPerformanceLines(chartArea, timelineData, chartWidth, chartHeight, maxDPS, maxHPS)

    -- Draw cooldown markers if enhanced data is available and filter allows
    if sessionData.enhancedData and sessionData.enhancedData.cooldownUsage and 
       self.chartFilters and self.chartFilters.showCooldowns then
        self:DrawCooldownMarkers(chartArea, sessionData.enhancedData.cooldownUsage, sessionData.duration, chartWidth,
            chartHeight)
    end

    -- Draw death markers if enhanced data is available and filters allow
    if sessionData.enhancedData and sessionData.enhancedData.deaths and #sessionData.enhancedData.deaths > 0 and
       self.chartFilters and (self.chartFilters.showPlayerDeaths or self.chartFilters.showMinionDeaths) then
        -- addon:Debug("Drawing %d death markers", #sessionData.enhancedData.deaths)
        self:DrawDeathMarkers(chartArea, sessionData.enhancedData.deaths, sessionData.duration, chartWidth, chartHeight)
    else
        -- One-time debug for enhanced data structure (only when opening chart)
        addon:Debug("=== ENHANCED DATA DEBUG ===")
        if sessionData.enhancedData then
            addon:Debug("Enhanced data keys available:")
            for k, v in pairs(sessionData.enhancedData) do
                if type(v) == "table" then
                    addon:Debug("  %s: table with %d items", tostring(k), #v)
                    if k == "deaths" and #v > 0 then
                        addon:Debug("    First death event keys: %s", table.concat(addon:GetTableKeys(v[1]), ", "))
                        addon:Debug("    First death event:")
                        for dk, dv in pairs(v[1]) do
                            addon:Debug("      %s: %s", tostring(dk), tostring(dv))
                        end
                    end
                else
                    addon:Debug("  %s: %s", tostring(k), tostring(v))
                end
            end
        else
            addon:Debug("No enhanced data found in session")
        end
        addon:Debug("========================")
    end

    -- TEST: Temporarily removed - test markers were working

    -- Chart legend
    self:CreateChartLegend(chartArea, maxDPS, maxHPS)
end


-- Draw chart grid with time axis and Y-axis labels
function EnhancedSessionDetailWindow:DrawChartGrid(chartArea, width, height, duration, maxDPS, maxHPS)
    -- Horizontal grid lines
    for i = 1, 4 do
        local line = chartArea:CreateTexture(nil, "BORDER")
        line:SetSize(width, 1)
        line:SetPoint("BOTTOM", chartArea, "BOTTOM", 0, (i * height / 5))
        line:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    end

    -- Y-axis labels for DPS (left side, red) - only if DPS is enabled
    if self.chartFilters and self.chartFilters.showDPS then
        self:CreateDPSAxis(chartArea, height, maxDPS)
    end

    -- Y-axis labels for HPS (right side, green) - only if HPS is enabled
    if self.chartFilters and self.chartFilters.showHPS then
        self:CreateHPSAxis(chartArea, width, height, maxHPS)
    end

    -- Calculate time intervals based on duration
    local timeInterval = self:CalculateTimeInterval(duration)
    local numIntervals = math.floor(duration / timeInterval)

    -- Vertical grid lines with time labels
    for i = 0, numIntervals do
        local timePos = i * timeInterval
        local x = (timePos / duration) * width

        -- Only draw if within chart bounds
        if x <= width then
            -- Vertical grid line
            local line = chartArea:CreateTexture(nil, "BORDER")
            line:SetSize(1, height)
            line:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", x, 0)
            line:SetColorTexture(0.4, 0.4, 0.4, 0.5)

            -- Time label
            local timeLabel = chartArea:CreateFontString(nil, "OVERLAY")
            timeLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
            timeLabel:SetPoint("BOTTOM", chartArea, "BOTTOMLEFT", x, -15)
            timeLabel:SetText(string.format("%.0fs", timePos))
            timeLabel:SetTextColor(0.8, 0.8, 0.8, 1)
            timeLabel:SetJustifyH("CENTER")
        end
    end

    -- Add final time marker if duration doesn't align with interval
    if numIntervals * timeInterval < duration then
        local x = width
        local timeLabel = chartArea:CreateFontString(nil, "OVERLAY")
        timeLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
        timeLabel:SetPoint("BOTTOM", chartArea, "BOTTOMRIGHT", 0, -15)
        timeLabel:SetText(string.format("%.1fs", duration))
        timeLabel:SetTextColor(0.8, 0.8, 0.8, 1)
        timeLabel:SetJustifyH("CENTER")
    end
end

-- Calculate appropriate time interval for grid
function EnhancedSessionDetailWindow:CalculateTimeInterval(duration)
    if duration <= 30 then
        return 5  -- 5-second intervals for short fights
    elseif duration <= 60 then
        return 10 -- 10-second intervals for medium fights
    elseif duration <= 180 then
        return 15 -- 15-second intervals for longer fights
    else
        return 30 -- 30-second intervals for very long fights
    end
end

-- Create DPS axis (left side, red)
function EnhancedSessionDetailWindow:CreateDPSAxis(chartArea, height, maxDPS)
    if maxDPS <= 0 then return end

    local numLabels = 5
    for i = 0, numLabels do
        local value = (i / numLabels) * maxDPS
        local y = (i / numLabels) * height

        -- DPS axis label (positioned inside chart area)
        local dpsLabel = chartArea:CreateFontString(nil, "OVERLAY")
        dpsLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 9, "OUTLINE")
        dpsLabel:SetPoint("LEFT", chartArea, "BOTTOMLEFT", 5, y)
        dpsLabel:SetText(self:FormatAxisValue(value))
        dpsLabel:SetTextColor(1, 0.3, 0.3, 0.9) -- Red to match DPS line
        dpsLabel:SetJustifyH("LEFT")
    end

    -- DPS axis title (positioned inside chart area)
    local dpsTitle = chartArea:CreateFontString(nil, "OVERLAY")
    dpsTitle:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
    dpsTitle:SetPoint("TOPLEFT", chartArea, "TOPLEFT", 5, -5)
    dpsTitle:SetText("DPS")
    dpsTitle:SetTextColor(1, 0.3, 0.3, 1)
    dpsTitle:SetJustifyH("LEFT")
end

-- Create HPS axis (right side, green)
function EnhancedSessionDetailWindow:CreateHPSAxis(chartArea, width, height, maxHPS)
    if maxHPS <= 0 then return end

    local numLabels = 5
    for i = 0, numLabels do
        local value = (i / numLabels) * maxHPS
        local y = (i / numLabels) * height

        -- HPS axis label (positioned inside chart area on the right side)
        local hpsLabel = chartArea:CreateFontString(nil, "OVERLAY")
        hpsLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 9, "OUTLINE")
        hpsLabel:SetPoint("RIGHT", chartArea, "BOTTOMRIGHT", -5, y)
        hpsLabel:SetText(self:FormatAxisValue(value))
        hpsLabel:SetTextColor(0.3, 1, 0.3, 0.9) -- Green to match HPS line
        hpsLabel:SetJustifyH("RIGHT")
    end

    -- HPS axis title (positioned inside chart area at top-right corner)
    local hpsTitle = chartArea:CreateFontString(nil, "OVERLAY")
    hpsTitle:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
    hpsTitle:SetPoint("TOPRIGHT", chartArea, "TOPRIGHT", -5, -5)
    hpsTitle:SetText("HPS")
    hpsTitle:SetTextColor(0.3, 1, 0.3, 1)
    hpsTitle:SetJustifyH("RIGHT")
end

-- Format axis values for readability
function EnhancedSessionDetailWindow:FormatAxisValue(value)
    if value >= 1000000 then
        return string.format("%.1fM", value / 1000000)
    elseif value >= 1000 then
        return string.format("%.0fK", value / 1000)
    else
        return string.format("%.0f", value)
    end
end

-- Draw performance lines
function EnhancedSessionDetailWindow:DrawPerformanceLines(chartArea, timelineData, width, height, maxDPS, maxHPS)
    -- Initialize chart filters if not set (safety check)
    if not self.chartFilters then
        self.chartFilters = {
            showHPS = true,
            showDPS = true,
            showCooldowns = true,
            showPlayerDeaths = true,
            showMinionDeaths = true
        }
    end

    local pointWidth = width / math.max(1, #timelineData - 1)
    local previousDPSPoint, previousHPSPoint = nil, nil

    for i, point in ipairs(timelineData) do
        -- Remove arbitrary 200-point limit to show full combat duration
        local x = (i - 1) * pointWidth

        -- DPS line - only draw if filter is enabled
        if self.chartFilters and self.chartFilters.showDPS then
            local dpsValue = point.instantDPS or point.averageDPS or 0
            if maxDPS > 0 then
                local dpsHeight = dpsValue > 0 and math.max(2, (dpsValue / maxDPS) * height) or 1

                if previousDPSPoint then
                    self:DrawLine(chartArea, previousDPSPoint.x, previousDPSPoint.y, x, dpsHeight, CHART_COLORS.dps)
                end
                previousDPSPoint = { x = x, y = dpsHeight }
            end
        end

        -- HPS line - only draw if filter is enabled
        if self.chartFilters and self.chartFilters.showHPS then
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

-- Draw enhanced cooldown markers with improved visibility and tooltips
function EnhancedSessionDetailWindow:DrawCooldownMarkers(chartArea, cooldowns, duration, width, height)
    -- Only draw cooldown markers if filter is enabled
    if not (self.chartFilters and self.chartFilters.showCooldowns) then
        return
    end
    for _, cooldown in ipairs(cooldowns) do
        if cooldown.elapsed and cooldown.elapsed >= 0 and cooldown.elapsed <= duration then
            local x = (cooldown.elapsed / duration) * width

            -- Enhanced vertical line (thinner)
            local line = chartArea:CreateTexture(nil, "OVERLAY")
            line:SetSize(0.5, height)
            line:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", x, 0)
            line:SetColorTexture(cooldown.color[1], cooldown.color[2], cooldown.color[3], 0.8)

            -- Glow effect background for the line (also thinner)
            local lineGlow = chartArea:CreateTexture(nil, "BACKGROUND")
            lineGlow:SetSize(1, height)
            lineGlow:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", x - 0.25, 0)
            lineGlow:SetColorTexture(cooldown.color[1], cooldown.color[2], cooldown.color[3], 0.3)

            -- Enhanced marker icon at top of line (class-specific raid markers)
            local markerIcon = chartArea:CreateTexture(nil, "OVERLAY")
            markerIcon:SetSize(14, 14)
            markerIcon:SetPoint("CENTER", chartArea, "TOPLEFT", x, -7)

            -- Set class-specific raid marker based on cooldown type
            local classMarker = self:GetClassMarkerForCooldown(cooldown)
            markerIcon:SetTexture(classMarker.texture)
            markerIcon:SetVertexColor(cooldown.color[1], cooldown.color[2], cooldown.color[3], 1)

            -- Create interactive frame for tooltip
            local markerFrame = CreateFrame("Frame", nil, chartArea)
            markerFrame:SetSize(16, height) -- Wider hit area
            markerFrame:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", x - 8, 0)
            markerFrame:EnableMouse(true)

            -- Enhanced tooltip with detailed information
            markerFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(cooldown.spellName, 1, 1, 1, 1, true)
                GameTooltip:AddLine(string.format("Used by: %s", cooldown.sourceName or "Unknown"), 0.8, 0.8, 1, true)
                GameTooltip:AddLine(string.format("Time: %.1f seconds", cooldown.elapsed), 1, 1, 0.8, true)
                if cooldown.spellID then
                    GameTooltip:AddLine(string.format("Spell ID: %d", cooldown.spellID), 0.6, 0.6, 0.6, true)
                end
                GameTooltip:Show()

                -- Highlight effect on hover
                line:SetAlpha(1.0)
                markerIcon:SetSize(14, 14) -- Slightly larger on hover
            end)

            markerFrame:SetScript("OnLeave", function(self)
                GameTooltip:Hide()

                -- Reset highlight effect
                line:SetAlpha(0.9)
                markerIcon:SetSize(12, 12)
            end)

            -- Spell name label (vertical, full spell name allowed)
            if #cooldowns <= 8 then -- Only show labels if 8 or fewer cooldowns
                local label = chartArea:CreateFontString(nil, "OVERLAY")
                label:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 8, "OUTLINE")
                label:SetPoint("TOP", markerIcon, "BOTTOM", 0, -50) -- Anchor top of text to bottom of symbol
                label:SetWidth(200)                                 -- Wide enough for full spell names

                -- Use full spell name (no abbreviation needed with vertical text)
                local displayName = cooldown.spellName

                label:SetText(displayName)
                label:SetTextColor(cooldown.color[1], cooldown.color[2], cooldown.color[3], 0.9)
                label:SetRotation(math.rad(-90)) -- Vertical text
                label:SetJustifyV("TOP")         -- Align to top (start near symbol)
            end
        end
    end
end

-- Get class-specific marker for cooldowns
function EnhancedSessionDetailWindow:GetClassMarkerForCooldown(cooldown)
    -- Determine class based on spell names or IDs
    local spellName = cooldown.spellName or ""
    local lowerName = string.lower(spellName)

    -- Priest abilities - Purple Diamond (Raid Target 4)
    if string.find(lowerName, "dispersion") or string.find(lowerName, "guardian spirit") or
        string.find(lowerName, "power infusion") or string.find(lowerName, "pain suppression") or
        string.find(lowerName, "barrier") or string.find(lowerName, "salvation") or
        string.find(lowerName, "vampiric embrace") or string.find(lowerName, "ascension") then
        return { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" } -- Purple Diamond
    end

    -- Death Knight abilities - Red X (Raid Target 7)
    if string.find(lowerName, "icebound") or string.find(lowerName, "vampiric blood") or
        string.find(lowerName, "pillar of frost") or string.find(lowerName, "army") or
        string.find(lowerName, "apocalypse") or string.find(lowerName, "lichborne") or
        string.find(lowerName, "empower rune") or string.find(lowerName, "rune tap") or
        string.find(lowerName, "tombstone") or string.find(lowerName, "frostwyrm") or
        string.find(lowerName, "breath of sindragosa") or string.find(lowerName, "consumption") then
        return { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" } -- Red X
    end

    -- Monk abilities - Green Triangle (Raid Target 3)
    if string.find(lowerName, "diffuse magic") or string.find(lowerName, "touch of karma") or
        string.find(lowerName, "dampen harm") or string.find(lowerName, "thunder focus") or
        string.find(lowerName, "storm, earth") or string.find(lowerName, "serenity") or
        string.find(lowerName, "invoke") or string.find(lowerName, "fortifying brew") or
        string.find(lowerName, "revival") or string.find(lowerName, "mana tea") or
        string.find(lowerName, "exploding keg") then
        return { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" } -- Green Triangle
    end

    -- Default for unknown/general abilities - Yellow Star (Raid Target 1)
    return { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" } -- Yellow Star
end

-- Get death marker style based on entity type
function EnhancedSessionDetailWindow:GetDeathMarkerStyle(entityType)
    -- Default to minion if no type specified (backwards compatibility)
    entityType = entityType or "minion"
    
    if entityType == "player" then
        -- Player deaths: Small red skull at top
        return 12, -6, 
               {r = 1.0, g = 0.2, b = 0.2, a = 1.0}, -- Red color
               {r = 1.0, g = 0.4, b = 0.4, a = 0.4}  -- Red glow
    elseif entityType == "boss" then
        -- Boss deaths: Regular white skull at top
        return 16, -8,
               {r = 1.0, g = 1.0, b = 1.0, a = 1.0}, -- White color
               {r = 0.8, g = 0.8, b = 0.8, a = 0.3}  -- White glow
    else -- "minion" or unknown
        -- Minion deaths: Small gray skull lower on chart
        return 10, -18,
               {r = 0.6, g = 0.6, b = 0.6, a = 0.8}, -- Gray color
               {r = 0.5, g = 0.5, b = 0.5, a = 0.2}  -- Gray glow
    end
end

-- Draw enhanced death markers with improved visibility and tooltips
function EnhancedSessionDetailWindow:DrawDeathMarkers(chartArea, deaths, duration, width, height)
    -- Check if any death markers should be shown based on filters
    if not (self.chartFilters and (self.chartFilters.showPlayerDeaths or self.chartFilters.showMinionDeaths or self.chartFilters.showBossDeaths)) then
        return
    end

    -- Capture session data for use in closures
    local sessionData = self.sessionData
    
    -- Get combat start time for timestamp conversion
    local combatStartTime = sessionData and sessionData.startTime

    -- Filter deaths based on chart filter settings for blacklist/whitelist
    local filteredDeaths = deaths
    
    if addon.EntityBlacklist and (self.chartFilters.applyBlacklist or self.chartFilters.showBlacklistedOnly) then
        local playerClass = addon.EntityBlacklist:GetPlayerClass()
        -- Use session zone data for consistent filtering
        local sessionZone = sessionData and sessionData.location or "Unknown"
        
        local tempFilteredDeaths = {}
        
        for _, death in ipairs(deaths) do
            if death.destName and death.destName ~= "" then
                local isBlacklisted = addon.EntityBlacklist:IsBlacklisted(death.destName, playerClass, sessionZone)
                
                if self.chartFilters.applyBlacklist and not isBlacklisted then
                    -- Normal blacklist mode: show only non-blacklisted entities
                    table.insert(tempFilteredDeaths, death)
                elseif self.chartFilters.showBlacklistedOnly and isBlacklisted then
                    -- Whitelist mode: show only blacklisted entities
                    table.insert(tempFilteredDeaths, death)
                elseif not self.chartFilters.applyBlacklist and not self.chartFilters.showBlacklistedOnly then
                    -- Both filters off: show everything
                    table.insert(tempFilteredDeaths, death)
                end
            end
        end
        
        filteredDeaths = tempFilteredDeaths
    end

    -- Further filter deaths based on chart filter settings
    local chartFilteredDeaths = {}
    for _, death in ipairs(filteredDeaths) do
        local shouldShow = false
        
        -- Use the structured entityType field for proper classification
        if death.entityType == "player" and self.chartFilters.showPlayerDeaths then
            shouldShow = true
        elseif death.entityType == "boss" and self.chartFilters.showBossDeaths then
            shouldShow = true
        elseif death.entityType == "minion" and self.chartFilters.showMinionDeaths then
            shouldShow = true
        elseif not death.entityType then
            -- Fallback for older data without entityType - use the boolean flags
            if death.isPlayer and self.chartFilters.showPlayerDeaths then
                shouldShow = true
            elseif (death.isPet or death.isNPC) and self.chartFilters.showMinionDeaths then
                shouldShow = true
            end
        end
        
        if shouldShow then
            table.insert(chartFilteredDeaths, death)
        end
    end
    
    filteredDeaths = chartFilteredDeaths

    for i, death in ipairs(filteredDeaths) do
        addon:Debug("Death", i, "- elapsed:", death.elapsed, "destName:", death.destName)

        -- UNIFIED: Use death.elapsed directly (already calculated by MyTimestampManager)
        local relativeTime = death.elapsed

        if relativeTime and relativeTime > 0 and relativeTime <= duration then
            local x = (relativeTime / duration) * width

            -- Determine marker style based on entity type
            local markerSize, markerYOffset, markerColor, glowColor = self:GetDeathMarkerStyle(death.entityType)
            
            -- Background warning line (thinner)
            local warningLine = chartArea:CreateTexture(nil, "BORDER")
            warningLine:SetSize(0.5, height)
            warningLine:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", x, 0)
            warningLine:SetColorTexture(1, 1, 1, 0.6) -- White warning line (more transparent)

            -- Enhanced death marker with WoW skull raid target texture
            local marker = chartArea:CreateTexture(nil, "OVERLAY")
            marker:SetSize(markerSize, markerSize)
            marker:SetPoint("CENTER", chartArea, "TOPLEFT", x, markerYOffset)
            marker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") -- Skull raid marker
            marker:SetVertexColor(markerColor.r, markerColor.g, markerColor.b, markerColor.a)

            -- Glow effect for death marker
            local markerGlow = chartArea:CreateTexture(nil, "BACKGROUND")
            markerGlow:SetSize(markerSize + 4, markerSize + 4)
            markerGlow:SetPoint("CENTER", chartArea, "TOPLEFT", x, markerYOffset)
            markerGlow:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") -- Skull raid marker
            markerGlow:SetVertexColor(glowColor.r, glowColor.g, glowColor.b, glowColor.a)

            -- Create interactive frame for tooltip (positioned with marker)
            local deathFrame = CreateFrame("Frame", nil, chartArea)
            deathFrame:SetSize(markerSize + 8, markerSize + 8) -- Hit area around the skull
            deathFrame:SetPoint("CENTER", chartArea, "TOPLEFT", x, markerYOffset)
            deathFrame:EnableMouse(true)

            -- Enhanced tooltip with death details (use converted time for display)
            deathFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                
                -- Color-code the victim name based on entity type
                local nameColor = {r = 1, g = 0.8, b = 0.8} -- Default
                if death.entityType == "player" then
                    nameColor = {r = 1, g = 0.2, b = 0.2} -- Red for players
                elseif death.entityType == "boss" then
                    nameColor = {r = 1, g = 1, b = 0.2} -- Yellow for bosses
                else
                    nameColor = {r = 0.7, g = 0.7, b = 0.7} -- Gray for minions
                end
                
                local entityLabel = death.entityType == "player" and " (Player)" or 
                                  death.entityType == "boss" and " (Boss)" or 
                                  death.entityType == "minion" and " (Minion)" or ""
                
                GameTooltip:SetText(string.format("Victim: %s%s", death.destName or "Unknown", entityLabel), 
                                  nameColor.r, nameColor.g, nameColor.b, true)
                GameTooltip:AddLine(string.format("Time: %.1f seconds", relativeTime), 1, 1, 0.8, true)

                if death.spellName and death.spellName ~= "" then
                    GameTooltip:AddLine(string.format("Killed by: %s", death.spellName), 1, 0.6, 0.6, true)
                end

                if death.sourceName and death.sourceName ~= "" then
                    GameTooltip:AddLine(string.format("Source: %s", death.sourceName), 1, 0.6, 0.6, true)
                end

                if death.amount and death.amount > 0 then
                    GameTooltip:AddLine(string.format("Damage: %s", addon.CombatTracker:FormatNumber(death.amount)), 1,
                        0.7, 0.7, true)
                end

                -- Add blacklist instructions
                GameTooltip:AddLine(" ", 1, 1, 1, true) -- Spacer
                GameTooltip:AddLine("Right-click to blacklist options:", 0.7, 0.7, 1, true)
                GameTooltip:AddLine("• Shift+Right-click: Blacklist globally", 0.6, 0.6, 0.9, true)
                GameTooltip:AddLine("• Ctrl+Right-click: Blacklist for your class", 0.6, 0.6, 0.9, true)
                GameTooltip:AddLine("• Alt+Right-click: Blacklist for this zone", 0.6, 0.6, 0.9, true)

                GameTooltip:Show()

                -- Highlight effect on hover (brighten current color)
                local brightColor = {
                    r = math.min(1, markerColor.r + 0.3),
                    g = math.min(1, markerColor.g + 0.3), 
                    b = math.min(1, markerColor.b + 0.3)
                }
                marker:SetVertexColor(brightColor.r, brightColor.g, brightColor.b, 1)
                markerGlow:SetVertexColor(brightColor.r, brightColor.g, brightColor.b, 0.5)
            end)

            deathFrame:SetScript("OnLeave", function(self)
                GameTooltip:Hide()

                -- Reset to original colors
                marker:SetVertexColor(markerColor.r, markerColor.g, markerColor.b, markerColor.a)
                markerGlow:SetVertexColor(glowColor.r, glowColor.g, glowColor.b, glowColor.a)
            end)

            -- Right-click handler for blacklisting
            deathFrame:SetScript("OnMouseUp", function(self, button)
                if button == "RightButton" and death.destName then
                    local entityName = death.destName
                    local blacklistType = "global"
                    local classOrZone = nil
                    local encounter = nil
                    local message = ""

                    if IsShiftKeyDown() then
                        -- Global blacklist
                        blacklistType = "global"
                        message = string.format("Blacklisted '%s' globally", entityName)
                    elseif IsControlKeyDown() then
                        -- Class-specific blacklist - try to determine the class of the deceased entity
                        blacklistType = "class"
                        local targetClass = nil
                        
                        -- Try to determine relevant class for blacklisting
                        if death.isPlayer and death.destGUID then
                            -- For players, try to get their class from unit frames if they're still around
                            for i = 1, 40 do
                                local unit = IsInRaid() and ("raid" .. i) or (i <= 5 and (i == 1 and "player" or ("party" .. (i-1))) or nil)
                                if unit and UnitExists(unit) and UnitGUID(unit) == death.destGUID then
                                    local _, class = UnitClass(unit)
                                    targetClass = class
                                    break
                                end
                            end
                            
                            -- If we couldn't find them in group, try target/focus
                            if not targetClass then
                                if UnitExists("target") and UnitGUID("target") == death.destGUID then
                                    local _, class = UnitClass("target")
                                    targetClass = class
                                elseif UnitExists("focus") and UnitGUID("focus") == death.destGUID then
                                    local _, class = UnitClass("focus")
                                    targetClass = class
                                end
                            end
                        elseif death.isPet and death.destName then
                            -- For pets, try to determine the owner's class by checking unit pet relationships
                            for i = 1, 40 do
                                local unit = IsInRaid() and ("raid" .. i) or (i <= 5 and (i == 1 and "player" or ("party" .. (i-1))) or nil)
                                if unit and UnitExists(unit) then
                                    local petUnit = unit .. "pet"
                                    if UnitExists(petUnit) and UnitName(petUnit) == death.destName then
                                        local _, class = UnitClass(unit)
                                        targetClass = class
                                        break
                                    end
                                end
                            end
                            
                            -- Also check player's own pet
                            if not targetClass and UnitExists("pet") and UnitName("pet") == death.destName then
                                local _, class = UnitClass("player")
                                targetClass = class
                            end
                        end
                        
                        -- Fall back to current player's class if we couldn't determine the target's class
                        classOrZone = targetClass or addon.EntityBlacklist:GetPlayerClass()
                        
                        if targetClass then
                            if death.isPlayer then
                                message = string.format("Blacklisted '%s' for %s class", entityName, targetClass)
                            elseif death.isPet then
                                message = string.format("Blacklisted '%s' for %s class (pet owner)", entityName, targetClass)
                            else
                                message = string.format("Blacklisted '%s' for %s class", entityName, targetClass)
                            end
                        else
                            message = string.format("Blacklisted '%s' for %s (your class - entity class unknown)", entityName, classOrZone or "your class")
                        end
                    elseif IsAltKeyDown() then
                        -- Zone-specific blacklist (use session location)
                        blacklistType = "zone"
                        local sessionZone = sessionData and sessionData.location
                        
                        -- Enhanced zone detection if session zone is missing/unknown
                        if not sessionZone or sessionZone == "Unknown" or sessionZone == "" then
                            -- Try multiple zone detection methods
                            sessionZone = GetRealZoneText() or GetZoneText() or GetMinimapZoneText() or "Unknown Zone"
                        end
                        
                        classOrZone = sessionZone
                        message = string.format("Blacklisted '%s' for zone %s", entityName, sessionZone)
                    else
                        -- Default to global if no modifier
                        blacklistType = "global"
                        message = string.format("Blacklisted '%s' globally (no modifier key)", entityName)
                    end

                    -- Add to blacklist
                    local success = addon.EntityBlacklist:AddToBlacklist(entityName, blacklistType, classOrZone)
                    
                    if success then
                        print("|cff00ff00MyUI2:|r " .. message)
                        print("|cff888888MyUI2:|r Toggle the Blacklist filter to see changes")
                    else
                        print("|cffff0000MyUI2:|r Failed to blacklist '" .. entityName .. "'")
                    end
                end
            end)
        else
            addon:Debug("  Death %d SKIPPED - relativeTime: %f, duration: %f", i, relativeTime, duration)
            addon:Debug("    Reason: relativeTime outside bounds [0, %f]", duration)
        end
    end

    -- Summary
end

-- TEST: Draw test markers to verify chart functionality
function EnhancedSessionDetailWindow:DrawTestMarkers(chartArea, duration, width, height)
    -- Test cooldown marker at 25% through the fight
    local testX = (duration * 0.25 / duration) * width

    local testLine = chartArea:CreateTexture(nil, "OVERLAY")
    testLine:SetSize(3, height)
    testLine:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", testX - 1, 0)
    testLine:SetColorTexture(0, 1, 1, 0.8) -- Cyan test line

    local testMarker = chartArea:CreateTexture(nil, "OVERLAY")
    testMarker:SetSize(12, 12)
    testMarker:SetPoint("BOTTOM", chartArea, "BOTTOMLEFT", testX, height - 15)
    testMarker:SetColorTexture(0, 1, 1, 1) -- Cyan marker

    -- Test death marker at 75% through the fight
    local testDeathX = (duration * 0.75 / duration) * width

    local testDeathLine = chartArea:CreateTexture(nil, "OVERLAY")
    testDeathLine:SetSize(2, height)
    testDeathLine:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", testDeathX, 0)
    testDeathLine:SetColorTexture(1, 0, 1, 0.8) -- Magenta test line

    local testDeathMarker = chartArea:CreateTexture(nil, "OVERLAY")
    testDeathMarker:SetSize(16, 16)
    testDeathMarker:SetPoint("CENTER", chartArea, "TOPLEFT", testDeathX, -8)        -- Top of chart, centered
    testDeathMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8") -- Skull raid marker
    testDeathMarker:SetVertexColor(1, 0, 1, 1)                                      -- Magenta skull

    addon:Debug("Drew test markers at", testX, "and", testDeathX)
end

-- Create chart legend (removed - was the light gray summary data)
function EnhancedSessionDetailWindow:CreateChartLegend(chartArea, maxDPS, maxHPS)
    -- Legend removed per user feedback - was the unwanted light gray summary data
end

-- Create chart controls and filters
function EnhancedSessionDetailWindow:CreateChartControls(controlsFrame)
    local controlsBg = controlsFrame:CreateTexture(nil, "BACKGROUND")
    controlsBg:SetAllPoints(controlsFrame)
    controlsBg:SetColorTexture(0.1, 0.1, 0.1, 0.7)

    -- Initialize chart filters if not already set
    if not self.chartFilters then
        self.chartFilters = {
            showHPS = true,
            showDPS = true,
            showCooldowns = true,
            showPlayerDeaths = true,
            showMinionDeaths = true,
            showBossDeaths = true,
            applyBlacklist = true,      -- Apply blacklist filtering
            showBlacklistedOnly = false -- Show only blacklisted entities (whitelist mode)
        }
    end

    -- Create filter toggles
    self:CreateChartFilterToggles(controlsFrame)
end

-- Create chart filter toggles
function EnhancedSessionDetailWindow:CreateChartFilterToggles(controlsFrame)
    -- Create a horizontal layout for filter toggles
    local toggleContainer = CreateFrame("Frame", nil, controlsFrame)
    toggleContainer:SetSize(720, 35)
    toggleContainer:SetPoint("TOP", controlsFrame, "TOP", 0, -10)

    local toggles = {
        { key = "showHPS", text = "HPS", color = { 0.3, 1, 0.3 } },
        { key = "showDPS", text = "DPS", color = { 1, 0.3, 0.3 } },
        { key = "showCooldowns", text = "Cooldowns", color = { 0.3, 0.3, 1 } },
        { key = "showPlayerDeaths", text = "Player Deaths", color = { 1, 0.2, 0.2 } },
        { key = "showBossDeaths", text = "Boss Deaths", color = { 1, 1, 0.2 } },
        { key = "showMinionDeaths", text = "Minion Deaths", color = { 0.8, 0.4, 0.4 } },
        { key = "applyBlacklist", text = "Blacklist", color = { 0.4, 0.4, 0.4 } },
        { key = "showBlacklistedOnly", text = "Entity Track", color = { 0.9, 0.9, 0.9 } }
    }

    local xOffset = 10
    for i, toggle in ipairs(toggles) do
        local checkbox = CreateFrame("CheckButton", nil, toggleContainer)
        checkbox:SetSize(20, 20)
        checkbox:SetPoint("LEFT", toggleContainer, "LEFT", xOffset, 5)

        -- Checkbox background
        local checkBg = checkbox:CreateTexture(nil, "BACKGROUND")
        checkBg:SetAllPoints(checkbox)
        checkBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

        -- Checkbox check mark
        local checkMark = checkbox:CreateTexture(nil, "OVERLAY")
        checkMark:SetSize(12, 12)
        checkMark:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
        checkMark:SetColorTexture(toggle.color[1], toggle.color[2], toggle.color[3], 1)
        checkbox.checkMark = checkMark

        -- Update check mark visibility based on current state
        checkMark:SetShown(self.chartFilters[toggle.key])

        -- Label
        local label = toggleContainer:CreateFontString(nil, "OVERLAY")
        label:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
        label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        label:SetText(toggle.text)
        label:SetTextColor(toggle.color[1], toggle.color[2], toggle.color[3], 1)

        -- Click handler with immediate redraw
        checkbox:SetScript("OnClick", function()
            self.chartFilters[toggle.key] = not self.chartFilters[toggle.key]
            checkMark:SetShown(self.chartFilters[toggle.key])
            
            -- Immediately redraw the chart
            self:RedrawChart()
        end)

        -- Hover effects
        checkbox:SetScript("OnEnter", function()
            checkBg:SetColorTexture(0.3, 0.3, 0.3, 0.8)
        end)

        checkbox:SetScript("OnLeave", function()
            checkBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        end)

        -- Calculate next position
        local labelWidth = label:GetStringWidth()
        xOffset = xOffset + 25 + labelWidth + 15
    end

    -- Redraw button removed - charts now update automatically when filters change
end

-- Redraw chart with current filter settings
function EnhancedSessionDetailWindow:RedrawChart()
    if not self.frame or self.currentTab ~= "overview" then
        return
    end

    -- Clear current content properly and recreate timeline tab
    if self.frame.currentContent then
        self.frame.currentContent:Hide()
        self.frame.currentContent = nil
    end
    
    -- Recreate the timeline tab
    self:CreateTimelineTab()
end

-- Create scrollable event log for deaths and buffs
function EnhancedSessionDetailWindow:CreateScrollableEventLog(controlsFrame)
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

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, controlsFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", controlsFrame, "TOPLEFT", 5, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", controlsFrame, "BOTTOMRIGHT", -25, 10)

    -- Create content frame
    local contentFrame = CreateFrame("Frame", nil, scrollFrame)
    contentFrame:SetSize(scrollFrame:GetWidth() - 10, math.max(100, #events * 15))
    scrollFrame:SetScrollChild(contentFrame)

    -- Add events to content frame
    for i, event in ipairs(events) do
        local eventText = contentFrame:CreateFontString(nil, "OVERLAY")
        eventText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
        eventText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 5, -5 - ((i - 1) * 15))
        eventText:SetText(event.text)
        eventText:SetTextColor(event.color[1], event.color[2], event.color[3], 1)
        eventText:SetJustifyH("LEFT")
        eventText:SetWidth(contentFrame:GetWidth() - 10)
    end

    -- Style the scroll bar
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 0, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 0, 16)
    end
end

-- Create log tab with scrollable event log
function EnhancedSessionDetailWindow:CreateLogTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Combat Event Log")

    -- Check for enhanced data
    if not self.sessionData.enhancedData then
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", content, "CENTER", 0, 0)
        noDataText:SetText("No event log data available\n(Enhanced logging was not active during this session)")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)

        content:Show()
        self.frame.currentContent = content
        return
    end

    -- Create the scrollable event log taking up most of the tab
    local logFrame = CreateFrame("Frame", nil, content)
    logFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -50)
    logFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 10)

    self:CreateScrollableEventLog(logFrame)

    content:Show()
    self.frame.currentContent = content
end

-- Create blacklist tab
function EnhancedSessionDetailWindow:CreateBlacklistTab()
    -- Clear any existing content first
    if self.frame.currentContent then
        local children = {self.frame.contentArea:GetChildren()}
        for _, child in ipairs(children) do
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(nil)
        end
        self.frame.currentContent = nil
    end

    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Entity Blacklists (Tree View)")

    -- Check if EntityBlacklist is available
    if not addon.EntityBlacklist or not EntityBlacklistDB then
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", content, "CENTER", 0, 0)
        noDataText:SetText("Entity blacklist data not available")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)

        content:Show()
        self.frame.currentContent = content
        return
    end

    -- Create scrollable tree view
    local scrollFrame = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -30, 50)

    local scrollContent = CreateFrame("Frame", nil, scrollFrame)
    scrollContent:SetSize(scrollFrame:GetWidth() - 10, 1000)
    scrollFrame:SetScrollChild(scrollContent)

    -- Track tree state and checkboxes
    self.treeState = self.treeState or {
        global = { expanded = true },
        classes = {},
        zones = {}
    }
    self.treeCheckboxes = {}

    local yOffset = -10

    -- Helper function to create expandable tree node
    local function CreateTreeNode(parent, text, level, nodeKey, nodeType, expandCallback)
        local nodeFrame = CreateFrame("Frame", nil, parent)
        nodeFrame:SetSize(700, 20)
        nodeFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", level * 15, yOffset)

        -- Expand/collapse button
        local expandButton = CreateFrame("Button", nil, nodeFrame)
        expandButton:SetSize(12, 12)
        expandButton:SetPoint("LEFT", nodeFrame, "LEFT", 0, 0)

        local expandTexture = expandButton:CreateTexture(nil, "OVERLAY")
        expandTexture:SetAllPoints(expandButton)
        expandTexture:SetColorTexture(0.8, 0.8, 0.8, 1)

        -- Node text
        local nodeText = nodeFrame:CreateFontString(nil, "OVERLAY")
        nodeText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
        nodeText:SetPoint("LEFT", expandButton, "RIGHT", 5, 0)
        nodeText:SetText(text)
        nodeText:SetTextColor(1, 0.9, 0.6, 1)

        -- Set expand button state based on nodeType
        local isExpanded = false
        if nodeType == "global" then
            isExpanded = self.treeState.global and self.treeState.global.expanded
        elseif nodeType == "class" then
            isExpanded = self.treeState.classes[nodeKey] and self.treeState.classes[nodeKey].expanded
        elseif nodeType == "zone" then
            isExpanded = self.treeState.zones[nodeKey] and self.treeState.zones[nodeKey].expanded
        end
        
        expandTexture:SetTexCoord(0, 1, 0, 1)
        if isExpanded then
            expandTexture:SetColorTexture(0.6, 0.8, 0.6, 1) -- Green for expanded
        else
            expandTexture:SetColorTexture(0.8, 0.6, 0.6, 1) -- Red for collapsed
        end

        expandButton:SetScript("OnClick", function()
            expandCallback(nodeKey, not isExpanded)
        end)

        yOffset = yOffset - 22
        return nodeFrame, isExpanded
    end

    -- Helper function to create checkbox entry
    local function CreateCheckboxEntry(parent, pattern, enabled, level, toggleCallback)
        local entryFrame = CreateFrame("Frame", nil, parent)
        entryFrame:SetSize(700, 24)  -- Increased height for better spacing
        entryFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", level * 15 + 5, yOffset)

        -- Larger clickable checkbox area
        local checkbox = CreateFrame("Button", nil, entryFrame)
        checkbox:SetSize(20, 20)  -- Bigger hit area
        checkbox:SetPoint("LEFT", entryFrame, "LEFT", 0, 0)

        -- Visual checkbox background
        local checkboxBg = checkbox:CreateTexture(nil, "BACKGROUND")
        checkboxBg:SetSize(16, 16)  -- Visual size
        checkboxBg:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
        checkboxBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

        -- Border for checkbox
        local checkboxBorder = checkbox:CreateTexture(nil, "BORDER")
        checkboxBorder:SetSize(18, 18)
        checkboxBorder:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
        checkboxBorder:SetColorTexture(0.4, 0.4, 0.4, 1)

        -- Checkmark (using texture coordinates to draw an X)
        local checkboxCheck = checkbox:CreateTexture(nil, "OVERLAY")
        checkboxCheck:SetSize(10, 10)
        checkboxCheck:SetPoint("CENTER", checkbox, "CENTER", 0, 0)
        checkboxCheck:SetColorTexture(0.2, 0.8, 0.2, 1)
        checkboxCheck:SetShown(enabled)
        
        -- Create checkmark lines using FontString with special characters
        local checkText = checkbox:CreateFontString(nil, "OVERLAY")  -- Changed from ARTWORK to OVERLAY
        checkText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
        checkText:SetPoint("CENTER", checkbox, "CENTER", 0, 1)
        checkText:SetText("✓")  -- Try checkmark character
        checkText:SetTextColor(0.2, 0.8, 0.2, 1)
        checkText:SetShown(enabled)
        checkText:SetDrawLayer("OVERLAY", 10)  -- Force it to top layer

        -- Entry text
        local entryText = entryFrame:CreateFontString(nil, "OVERLAY")
        entryText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")  -- Slightly larger font
        entryText:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
        entryText:SetText(pattern)
        entryText:SetTextColor(enabled and 0.9 or 0.5, enabled and 0.9 or 0.5, enabled and 0.9 or 0.5, 1)

        -- Hover effects
        checkbox:SetScript("OnEnter", function()
            checkboxBorder:SetColorTexture(0.6, 0.6, 0.6, 1)
        end)

        checkbox:SetScript("OnLeave", function()
            checkboxBorder:SetColorTexture(0.4, 0.4, 0.4, 1)
        end)

        checkbox:SetScript("OnClick", function()
            local newState = not enabled
            enabled = newState  -- Update the local enabled state
            checkboxCheck:SetShown(newState)
            checkText:SetShown(newState)
            entryText:SetTextColor(newState and 0.9 or 0.5, newState and 0.9 or 0.5, newState and 0.9 or 0.5, 1)
            toggleCallback(newState)
        end)

        -- Store reference for later updates
        table.insert(self.treeCheckboxes, {
            checkbox = checkbox,
            checkmark = checkboxCheck,
            checkText = checkText,
            text = entryText,
            pattern = pattern
        })

        yOffset = yOffset - 26  -- Increased spacing
        return entryFrame
    end

    -- Function to rebuild the tree
    local function RebuildTree()
        -- Clear existing elements more thoroughly
        local children = {scrollContent:GetChildren()}
        for _, child in ipairs(children) do
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(nil)
        end
        -- Clear any stored references
        self.treeCheckboxes = {}
        yOffset = -10

        -- Global Blacklist Section
        local globalExpanded
        local function toggleGlobal(key, expanded)
            self.treeState.global.expanded = expanded
            RebuildTree()
        end
        _, globalExpanded = CreateTreeNode(scrollContent, "Global Blacklist", 0, "global", "global", toggleGlobal)

        if globalExpanded and EntityBlacklistDB.global then
            for pattern, enabled in pairs(EntityBlacklistDB.global) do
                CreateCheckboxEntry(scrollContent, pattern, enabled, 1, function(newState)
                    EntityBlacklistDB.global[pattern] = newState
                end)
            end
        end

        -- Class-specific Blacklists
        if EntityBlacklistDB.classes then
            for className, entities in pairs(EntityBlacklistDB.classes) do
                if not self.treeState.classes[className] then
                    self.treeState.classes[className] = { expanded = false }
                end

                local classExpanded
                local function toggleClass(key, expanded)
                    self.treeState.classes[className].expanded = expanded
                    RebuildTree()
                end
                _, classExpanded = CreateTreeNode(scrollContent, "Class: " .. className, 0, className, "class", toggleClass)

                if classExpanded then
                    for pattern, enabled in pairs(entities) do
                        CreateCheckboxEntry(scrollContent, pattern, enabled, 1, function(newState)
                            EntityBlacklistDB.classes[className][pattern] = newState
                        end)
                    end
                end
            end
        end

        -- Zone-specific Blacklists  
        if EntityBlacklistDB.zones then
            for zoneName, entities in pairs(EntityBlacklistDB.zones) do
                if not self.treeState.zones[zoneName] then
                    self.treeState.zones[zoneName] = { expanded = false }
                end

                local zoneExpanded
                local function toggleZone(key, expanded)
                    self.treeState.zones[zoneName].expanded = expanded
                    RebuildTree()
                end
                _, zoneExpanded = CreateTreeNode(scrollContent, "Zone: " .. zoneName, 0, zoneName, "zone", toggleZone)

                if zoneExpanded then
                    for pattern, enabled in pairs(entities) do
                        CreateCheckboxEntry(scrollContent, pattern, enabled, 1, function(newState)
                            EntityBlacklistDB.zones[zoneName][pattern] = newState
                        end)
                    end
                end
            end
        end

        -- Update scroll content height
        scrollContent:SetHeight(math.abs(yOffset) + 50)
    end

    -- Initial tree build
    RebuildTree()

    -- Add bulk operation buttons
    local buttonContainer = CreateFrame("Frame", nil, content)
    buttonContainer:SetSize(760, 60)
    buttonContainer:SetPoint("BOTTOM", content, "BOTTOM", 0, 5)

    -- Helper function to create buttons
    local function CreateActionButton(parent, text, x, y, width, color, clickHandler)
        local button = CreateFrame("Button", nil, parent)
        button:SetSize(width, 28)
        button:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)

        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(button)
        bg:SetColorTexture(color[1], color[2], color[3], 0.8)

        local buttonText = button:CreateFontString(nil, "OVERLAY")
        buttonText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
        buttonText:SetPoint("CENTER", button, "CENTER", 0, 0)
        buttonText:SetText(text)
        buttonText:SetTextColor(1, 1, 1, 1)

        button:SetScript("OnClick", clickHandler)

        button:SetScript("OnEnter", function()
            bg:SetColorTexture(color[1] + 0.1, color[2] + 0.1, color[3] + 0.1, 0.9)
        end)

        button:SetScript("OnLeave", function()
            bg:SetColorTexture(color[1], color[2], color[3], 0.8)
        end)

        return button
    end

    -- Row 1: Selection controls
    CreateActionButton(buttonContainer, "Select All", 5, 32, 80, {0.2, 0.6, 0.2}, function()
        self:SelectAllBlacklistEntries()
    end)

    CreateActionButton(buttonContainer, "Deselect All", 90, 32, 80, {0.6, 0.6, 0.2}, function()
        self:DeselectAllBlacklistEntries()
    end)

    CreateActionButton(buttonContainer, "Remove Selected", 175, 32, 100, {0.8, 0.3, 0.2}, function()
        self:ShowRemoveConfirmation()
    end)
    
    CreateActionButton(buttonContainer, "Cleanup Empty", 275, 32, 95, {0.6, 0.4, 0.8}, function()
        self:CleanupEmptyNodes()
    end)

    -- Row 2: Import/Export/Reset
    CreateActionButton(buttonContainer, "Share Selected", 5, 2, 100, {0.2, 0.6, 0.2}, function()
        self:ShowBlacklistShareWindow()
    end)

    CreateActionButton(buttonContainer, "Import", 110, 2, 70, {0.2, 0.2, 0.6}, function()
        self:ShowBlacklistImportWindow()
    end)

    CreateActionButton(buttonContainer, "Reset", 185, 2, 70, {0.6, 0.2, 0.6}, function()
        self:ShowResetConfirmation()
    end)

    content:Show()
    self.frame.currentContent = content
end

-- Bulk operation functions for blacklist management
function EnhancedSessionDetailWindow:SelectAllBlacklistEntries()
    -- Select all global entries
    if EntityBlacklistDB.global then
        for pattern, _ in pairs(EntityBlacklistDB.global) do
            EntityBlacklistDB.global[pattern] = true
        end
    end
    
    -- Select all class entries
    if EntityBlacklistDB.classes then
        for className, entities in pairs(EntityBlacklistDB.classes) do
            for pattern, _ in pairs(entities) do
                EntityBlacklistDB.classes[className][pattern] = true
            end
        end
    end
    
    -- Select all zone entries
    if EntityBlacklistDB.zones then
        for zoneName, entities in pairs(EntityBlacklistDB.zones) do
            for pattern, _ in pairs(entities) do
                EntityBlacklistDB.zones[zoneName][pattern] = true
            end
        end
    end
    
    -- Expand all tree nodes to show what was selected
    self:ExpandAllTreeNodes()
    
    -- Rebuild tree to reflect changes
    self:CreateBlacklistTab()
    print("MyUI2: All blacklist entries selected and tree expanded")
end

function EnhancedSessionDetailWindow:DeselectAllBlacklistEntries()
    -- Deselect all global entries
    if EntityBlacklistDB.global then
        for pattern, _ in pairs(EntityBlacklistDB.global) do
            EntityBlacklistDB.global[pattern] = false
        end
    end
    
    -- Deselect all class entries
    if EntityBlacklistDB.classes then
        for className, entities in pairs(EntityBlacklistDB.classes) do
            for pattern, _ in pairs(entities) do
                EntityBlacklistDB.classes[className][pattern] = false
            end
        end
    end
    
    -- Deselect all zone entries
    if EntityBlacklistDB.zones then
        for zoneName, entities in pairs(EntityBlacklistDB.zones) do
            for pattern, _ in pairs(entities) do
                EntityBlacklistDB.zones[zoneName][pattern] = false
            end
        end
    end
    
    -- Rebuild tree to reflect changes
    self:CreateBlacklistTab()
    print("MyUI2: All blacklist entries deselected")
end

function EnhancedSessionDetailWindow:ShowRemoveConfirmation()
    -- Count selected entries
    local selectedCount = 0
    
    if EntityBlacklistDB.global then
        for _, enabled in pairs(EntityBlacklistDB.global) do
            if enabled then selectedCount = selectedCount + 1 end
        end
    end
    
    if EntityBlacklistDB.classes then
        for _, entities in pairs(EntityBlacklistDB.classes) do
            for _, enabled in pairs(entities) do
                if enabled then selectedCount = selectedCount + 1 end
            end
        end
    end
    
    if EntityBlacklistDB.zones then
        for _, entities in pairs(EntityBlacklistDB.zones) do
            for _, enabled in pairs(entities) do
                if enabled then selectedCount = selectedCount + 1 end
            end
        end
    end
    
    if selectedCount == 0 then
        print("MyUI2: No entries selected for removal")
        return
    end
    
    self:ShowConfirmationModal(
        "Remove Selected Entries",
        string.format("Are you sure you want to remove %d selected blacklist entries?\n\nThis action cannot be undone.", selectedCount),
        function() self:RemoveSelectedEntries() end
    )
end

function EnhancedSessionDetailWindow:RemoveSelectedEntries()
    local removedCount = 0
    
    -- Remove selected global entries
    if EntityBlacklistDB.global then
        for pattern, enabled in pairs(EntityBlacklistDB.global) do
            if enabled then
                EntityBlacklistDB.global[pattern] = nil
                removedCount = removedCount + 1
            end
        end
    end
    
    -- Remove selected class entries
    if EntityBlacklistDB.classes then
        for className, entities in pairs(EntityBlacklistDB.classes) do
            for pattern, enabled in pairs(entities) do
                if enabled then
                    EntityBlacklistDB.classes[className][pattern] = nil
                    removedCount = removedCount + 1
                end
            end
        end
    end
    
    -- Remove selected zone entries
    if EntityBlacklistDB.zones then
        for zoneName, entities in pairs(EntityBlacklistDB.zones) do
            for pattern, enabled in pairs(entities) do
                if enabled then
                    EntityBlacklistDB.zones[zoneName][pattern] = nil
                    removedCount = removedCount + 1
                end
            end
            -- Clean up empty zone entries
            if next(EntityBlacklistDB.zones[zoneName]) == nil then
                EntityBlacklistDB.zones[zoneName] = nil
            end
        end
    end
    
    -- Automatically clean up empty parent nodes
    local cleanedNodes = self:CleanupEmptyBlacklistNodes()
    
    -- Rebuild tree to reflect changes
    self:CreateBlacklistTab()
    
    if cleanedNodes > 0 then
        print(string.format("MyUI2: Removed %d blacklist entries and cleaned up %d empty parent node(s)", removedCount, cleanedNodes))
    else
        print(string.format("MyUI2: Removed %d blacklist entries", removedCount))
    end
end

-- Utility function to clean up empty parent nodes
function EnhancedSessionDetailWindow:CleanupEmptyBlacklistNodes()
    local cleanedNodes = 0
    
    -- Clean up empty zone nodes
    if EntityBlacklistDB.zones then
        for zoneName, entities in pairs(EntityBlacklistDB.zones) do
            if next(entities) == nil then
                EntityBlacklistDB.zones[zoneName] = nil
                cleanedNodes = cleanedNodes + 1
            end
        end
    end
    
    -- Clean up empty class nodes
    if EntityBlacklistDB.classes then
        for className, entities in pairs(EntityBlacklistDB.classes) do
            if next(entities) == nil then
                EntityBlacklistDB.classes[className] = nil
                cleanedNodes = cleanedNodes + 1
            end
        end
    end
    
    return cleanedNodes
end

-- Manual cleanup function (called by button)
function EnhancedSessionDetailWindow:CleanupEmptyNodes()
    local cleanedNodes = self:CleanupEmptyBlacklistNodes()
    
    if cleanedNodes > 0 then
        self:CreateBlacklistTab()
        print(string.format("MyUI2: Cleaned up %d empty parent node(s)", cleanedNodes))
    else
        print("MyUI2: No empty parent nodes found to clean up")
    end
end

-- Expand all tree nodes to show content
function EnhancedSessionDetailWindow:ExpandAllTreeNodes()
    -- Ensure treeState exists
    if not self.treeState then
        self.treeState = {
            global = { expanded = true },
            classes = {},
            zones = {}
        }
    end
    
    -- Expand global node
    self.treeState.global.expanded = true
    
    -- Expand all class nodes
    if EntityBlacklistDB.classes then
        for className, _ in pairs(EntityBlacklistDB.classes) do
            if not self.treeState.classes[className] then
                self.treeState.classes[className] = { expanded = true }
            else
                self.treeState.classes[className].expanded = true
            end
        end
    end
    
    -- Expand all zone nodes
    if EntityBlacklistDB.zones then
        for zoneName, _ in pairs(EntityBlacklistDB.zones) do
            if not self.treeState.zones[zoneName] then
                self.treeState.zones[zoneName] = { expanded = true }
            else
                self.treeState.zones[zoneName].expanded = true
            end
        end
    end
end

function EnhancedSessionDetailWindow:ShowResetConfirmation()
    self:ShowConfirmationModal(
        "Reset All Blacklists",
        "Are you sure you want to reset ALL blacklist entries to their default state?\n\nThis will:\n• Remove all custom entries\n• Reset all entries to enabled\n• Cannot be undone",
        function() self:ResetAllBlacklists() end
    )
end

function EnhancedSessionDetailWindow:ResetAllBlacklists()
    -- Reset EntityBlacklist to defaults
    if addon.EntityBlacklist and addon.EntityBlacklist.Initialize then
        -- Clear current data
        EntityBlacklistDB = {}
        -- Reinitialize with defaults
        addon.EntityBlacklist:Initialize()
        print("MyUI2: All blacklists reset to defaults")
    else
        print("MyUI2: Could not reset blacklists - EntityBlacklist system not available")
    end
    
    -- Rebuild tree to reflect changes
    self:CreateBlacklistTab()
end

function EnhancedSessionDetailWindow:ShowConfirmationModal(title, message, confirmCallback)
    if self.confirmationModal then
        self.confirmationModal:Hide()
        self.confirmationModal = nil
    end

    local modal = CreateFrame("Frame", nil, UIParent)
    modal:SetSize(400, 250)
    modal:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    modal:SetFrameStrata("FULLSCREEN_DIALOG")

    -- Background
    local bg = modal:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(modal)
    bg:SetColorTexture(0, 0, 0, 0.9)

    local border = modal:CreateTexture(nil, "BORDER")
    border:SetAllPoints(modal)
    border:SetColorTexture(0.6, 0.6, 0.6, 1)
    bg:SetPoint("TOPLEFT", border, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)

    -- Title
    local titleText = modal:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    titleText:SetPoint("TOP", modal, "TOP", 0, -20)
    titleText:SetText(title)
    titleText:SetTextColor(1, 0.8, 0.2, 1)

    -- Message
    local messageText = modal:CreateFontString(nil, "OVERLAY")
    messageText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    messageText:SetPoint("TOP", modal, "TOP", 0, -60)
    messageText:SetWidth(360)
    messageText:SetText(message)
    messageText:SetTextColor(1, 1, 1, 1)

    -- Confirm button
    local confirmButton = CreateFrame("Button", nil, modal)
    confirmButton:SetSize(100, 35)
    confirmButton:SetPoint("BOTTOM", modal, "BOTTOM", -60, 20)

    local confirmBg = confirmButton:CreateTexture(nil, "BACKGROUND")
    confirmBg:SetAllPoints(confirmButton)
    confirmBg:SetColorTexture(0.8, 0.2, 0.2, 1)

    local confirmText = confirmButton:CreateFontString(nil, "OVERLAY")
    confirmText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    confirmText:SetPoint("CENTER", confirmButton, "CENTER", 0, 0)
    confirmText:SetText("CONFIRM")
    confirmText:SetTextColor(1, 1, 1, 1)

    confirmButton:SetScript("OnClick", function()
        modal:Hide()
        self.confirmationModal = nil
        confirmCallback()
    end)

    -- Cancel button
    local cancelButton = CreateFrame("Button", nil, modal)
    cancelButton:SetSize(100, 35)
    cancelButton:SetPoint("BOTTOM", modal, "BOTTOM", 60, 20)

    local cancelBg = cancelButton:CreateTexture(nil, "BACKGROUND")
    cancelBg:SetAllPoints(cancelButton)
    cancelBg:SetColorTexture(0.4, 0.4, 0.4, 1)

    local cancelText = cancelButton:CreateFontString(nil, "OVERLAY")
    cancelText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    cancelText:SetPoint("CENTER", cancelButton, "CENTER", 0, 0)
    cancelText:SetText("CANCEL")
    cancelText:SetTextColor(1, 1, 1, 1)

    cancelButton:SetScript("OnClick", function()
        modal:Hide()
        self.confirmationModal = nil
    end)

    modal:Show()
    self.confirmationModal = modal
end

-- Show blacklist sharing window with base64 encoded data
function EnhancedSessionDetailWindow:ShowBlacklistShareWindow()
    if self.shareWindow then
        self.shareWindow:Hide()
        self.shareWindow = nil
    end

    -- Create share window
    local shareWindow = CreateFrame("Frame", nil, UIParent)
    shareWindow:SetSize(500, 400)
    shareWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    shareWindow:SetFrameStrata("FULLSCREEN_DIALOG")

    -- Background and border
    local bg = shareWindow:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(shareWindow)
    bg:SetColorTexture(0, 0, 0, 0.9)

    local border = shareWindow:CreateTexture(nil, "BORDER")
    border:SetAllPoints(shareWindow)
    border:SetColorTexture(0.4, 0.4, 0.4, 1)
    bg:SetPoint("TOPLEFT", border, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)

    -- Title
    local title = shareWindow:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", shareWindow, "TOP", 0, -15)
    title:SetText("Share Blacklist Configuration")
    title:SetTextColor(1, 1, 1, 1)

    -- Serialize and encode blacklist data (only enabled entries)
    local blacklistData = {
        global = {},
        classes = {},
        zones = {}
    }
    
    -- Only include enabled global entries
    if EntityBlacklistDB and EntityBlacklistDB.global then
        for pattern, enabled in pairs(EntityBlacklistDB.global) do
            if enabled then
                blacklistData.global[pattern] = true
            end
        end
    end
    
    -- Only include enabled class entries
    if EntityBlacklistDB and EntityBlacklistDB.classes then
        for className, entities in pairs(EntityBlacklistDB.classes) do
            blacklistData.classes[className] = {}
            for pattern, enabled in pairs(entities) do
                if enabled then
                    blacklistData.classes[className][pattern] = true
                end
            end
            -- Remove empty class entries
            if next(blacklistData.classes[className]) == nil then
                blacklistData.classes[className] = nil
            end
        end
    end
    
    -- Only include enabled zone entries
    if EntityBlacklistDB and EntityBlacklistDB.zones then
        for zoneName, entities in pairs(EntityBlacklistDB.zones) do
            blacklistData.zones[zoneName] = {}
            for pattern, enabled in pairs(entities) do
                if enabled then
                    blacklistData.zones[zoneName][pattern] = true
                end
            end
            -- Remove empty zone entries
            if next(blacklistData.zones[zoneName]) == nil then
                blacklistData.zones[zoneName] = nil
            end
        end
    end

    -- Simple serialization to Lua table format
    local function serializeTable(t, depth)
        depth = depth or 0
        if depth > 10 then return "{}" end
        
        local parts = {}
        for k, v in pairs(t) do
            local key
            if type(k) == "string" then
                -- Escape special characters in key
                key = '["' .. k:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"]'
            else
                key = "[" .. tostring(k) .. "]"
            end
            
            local value
            if type(v) == "table" then
                value = serializeTable(v, depth + 1)
            elseif type(v) == "string" then
                value = '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
            elseif type(v) == "boolean" then
                value = v and "true" or "false"
            else
                value = tostring(v)
            end
            table.insert(parts, key .. "=" .. value)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    local serializedData = serializeTable(blacklistData)

    -- Base64 encode (simple implementation)
    local function base64Encode(data)
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local result = ""
        
        for i = 1, #data, 3 do
            local byte1 = string.byte(data, i) or 0
            local byte2 = string.byte(data, i + 1) or 0
            local byte3 = string.byte(data, i + 2) or 0
            
            local combined = bit.bor(bit.lshift(byte1, 16), bit.lshift(byte2, 8), byte3)
            
            result = result .. string.sub(chars, bit.rshift(combined, 18) + 1, bit.rshift(combined, 18) + 1)
            result = result .. string.sub(chars, bit.band(bit.rshift(combined, 12), 63) + 1, bit.band(bit.rshift(combined, 12), 63) + 1)
            result = result .. (i + 1 <= #data and string.sub(chars, bit.band(bit.rshift(combined, 6), 63) + 1, bit.band(bit.rshift(combined, 6), 63) + 1) or "=")
            result = result .. (i + 2 <= #data and string.sub(chars, bit.band(combined, 63) + 1, bit.band(combined, 63) + 1) or "=")
        end
        
        return result
    end

    local encodedData = base64Encode(serializedData)

    -- COPY ALL button - first priority
    local copyButton = CreateFrame("Button", nil, shareWindow)
    copyButton:SetSize(120, 35)
    copyButton:SetPoint("TOP", shareWindow, "TOP", -70, -50)

    local copyBg = copyButton:CreateTexture(nil, "BACKGROUND") 
    copyBg:SetAllPoints(copyButton)
    copyBg:SetColorTexture(0.2, 0.6, 0.2, 1)

    local copyText = copyButton:CreateFontString(nil, "OVERLAY")
    copyText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    copyText:SetPoint("CENTER", copyButton, "CENTER", 0, 0)
    copyText:SetText("COPY ALL")
    copyText:SetTextColor(1, 1, 1, 1)

    -- CLOSE button - second priority  
    local closeButton = CreateFrame("Button", nil, shareWindow)
    closeButton:SetSize(100, 35)
    closeButton:SetPoint("TOP", shareWindow, "TOP", 70, -50)

    local closeBg = closeButton:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints(closeButton)
    closeBg:SetColorTexture(0.8, 0.2, 0.2, 1)

    local closeText = closeButton:CreateFontString(nil, "OVERLAY")
    closeText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    closeText:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    closeText:SetText("CLOSE")
    closeText:SetTextColor(1, 1, 1, 1)

    -- Text area
    local textAreaFrame = CreateFrame("Frame", nil, shareWindow)
    textAreaFrame:SetPoint("TOPLEFT", shareWindow, "TOPLEFT", 20, -100)
    textAreaFrame:SetPoint("BOTTOMRIGHT", shareWindow, "BOTTOMRIGHT", -20, 50)
    
    local textAreaBg = textAreaFrame:CreateTexture(nil, "BACKGROUND")
    textAreaBg:SetAllPoints(textAreaFrame)
    textAreaBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    local scrollFrame = CreateFrame("ScrollFrame", nil, textAreaFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", textAreaFrame, "TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", textAreaFrame, "BOTTOMRIGHT", -30, 10)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth() - 20)
    editBox:SetText(encodedData)
    editBox:SetCursorPosition(0)
    scrollFrame:SetScrollChild(editBox)

    -- Button click handlers
    copyButton:SetScript("OnClick", function()
        editBox:HighlightText()
        editBox:SetFocus()
        print("MyUI2: Text selected - use Ctrl+C to copy to clipboard")
    end)

    copyButton:SetScript("OnEnter", function()
        copyBg:SetColorTexture(0.3, 0.7, 0.3, 1)
    end)

    copyButton:SetScript("OnLeave", function()
        copyBg:SetColorTexture(0.2, 0.6, 0.2, 1)
    end)

    closeButton:SetScript("OnClick", function()
        shareWindow:Hide()
        self.shareWindow = nil
    end)

    closeButton:SetScript("OnEnter", function()
        closeBg:SetColorTexture(1, 0.3, 0.3, 1)
    end)

    closeButton:SetScript("OnLeave", function()
        closeBg:SetColorTexture(0.8, 0.2, 0.2, 1)
    end)

    -- Instructions at bottom
    local instructText = shareWindow:CreateFontString(nil, "OVERLAY")
    instructText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    instructText:SetPoint("BOTTOM", shareWindow, "BOTTOM", 0, 15)
    instructText:SetText("Click COPY ALL to select text, then use Ctrl+C to copy. Click CLOSE when done.")
    instructText:SetTextColor(1, 1, 0.5, 1)

    -- Make draggable
    shareWindow:SetMovable(true)
    shareWindow:EnableMouse(true)
    shareWindow:RegisterForDrag("LeftButton")
    shareWindow:SetScript("OnDragStart", shareWindow.StartMoving)
    shareWindow:SetScript("OnDragStop", shareWindow.StopMovingOrSizing)

    shareWindow:Show()
    self.shareWindow = shareWindow
end

-- Show blacklist import window
function EnhancedSessionDetailWindow:ShowBlacklistImportWindow()
    if self.importWindow then
        self.importWindow:Hide()
        self.importWindow = nil
    end

    -- Create import window
    local importWindow = CreateFrame("Frame", nil, UIParent)
    importWindow:SetSize(500, 400)
    importWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    importWindow:SetFrameStrata("FULLSCREEN_DIALOG")

    -- Background and border
    local bg = importWindow:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(importWindow)
    bg:SetColorTexture(0, 0, 0, 0.9)

    local border = importWindow:CreateTexture(nil, "BORDER")
    border:SetAllPoints(importWindow)
    border:SetColorTexture(0.4, 0.4, 0.4, 1)
    bg:SetPoint("TOPLEFT", border, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)

    -- Title
    local title = importWindow:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", importWindow, "TOP", 0, -20)
    title:SetText("Import Blacklist Configuration")
    title:SetTextColor(1, 1, 1, 1)

    -- Description
    local descText = importWindow:CreateFontString(nil, "OVERLAY")
    descText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    descText:SetPoint("TOP", importWindow, "TOP", 0, -50)
    descText:SetText("Paste the encoded blacklist data below to import a configuration from another user.")
    descText:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Create text area for pasting data
    local textAreaFrame = CreateFrame("Frame", nil, importWindow)
    textAreaFrame:SetPoint("TOPLEFT", importWindow, "TOPLEFT", 20, -90)
    textAreaFrame:SetPoint("BOTTOMRIGHT", importWindow, "BOTTOMRIGHT", -20, 110)
    
    local textAreaBg = textAreaFrame:CreateTexture(nil, "BACKGROUND")
    textAreaBg:SetAllPoints(textAreaFrame)
    textAreaBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    local scrollFrame = CreateFrame("ScrollFrame", nil, textAreaFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", textAreaFrame, "TOPLEFT", 10, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", textAreaFrame, "BOTTOMRIGHT", -30, 10)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth() - 20)
    editBox:SetText("")
    scrollFrame:SetScrollChild(editBox)

    -- Button container
    local buttonContainer = CreateFrame("Frame", nil, importWindow)
    buttonContainer:SetSize(460, 40)
    buttonContainer:SetPoint("BOTTOM", importWindow, "BOTTOM", 0, 35)

    -- Import button
    local importButton = CreateFrame("Button", nil, buttonContainer)
    importButton:SetSize(100, 30)
    importButton:SetPoint("CENTER", buttonContainer, "CENTER", -50, 0)

    local importBg = importButton:CreateTexture(nil, "BACKGROUND")
    importBg:SetAllPoints(importButton)
    importBg:SetColorTexture(0.2, 0.2, 0.7, 0.8)

    local importText = importButton:CreateFontString(nil, "OVERLAY")
    importText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    importText:SetPoint("CENTER", importButton, "CENTER", 0, 0)
    importText:SetText("Import")
    importText:SetTextColor(1, 1, 1, 1)

    importButton:SetScript("OnClick", function()
        self:ImportBlacklistData(editBox:GetText())
    end)

    importButton:SetScript("OnEnter", function()
        importBg:SetColorTexture(0.3, 0.3, 0.8, 0.8)
    end)

    importButton:SetScript("OnLeave", function()
        importBg:SetColorTexture(0.2, 0.2, 0.7, 0.8)
    end)

    -- Close button
    local closeButton = CreateFrame("Button", nil, buttonContainer)
    closeButton:SetSize(80, 30)
    closeButton:SetPoint("CENTER", buttonContainer, "CENTER", 50, 0)

    local closeBg = closeButton:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints(closeButton)
    closeBg:SetColorTexture(0.6, 0.2, 0.2, 0.8)

    local closeText = closeButton:CreateFontString(nil, "OVERLAY")
    closeText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    closeText:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    closeText:SetText("Close")
    closeText:SetTextColor(1, 1, 1, 1)

    closeButton:SetScript("OnClick", function()
        importWindow:Hide()
        self.importWindow = nil
    end)

    closeButton:SetScript("OnEnter", function()
        closeBg:SetColorTexture(0.7, 0.3, 0.3, 0.8)
    end)

    closeButton:SetScript("OnLeave", function()
        closeBg:SetColorTexture(0.6, 0.2, 0.2, 0.8)
    end)

    -- Instructions
    local instructText = importWindow:CreateFontString(nil, "OVERLAY")
    instructText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
    instructText:SetPoint("BOTTOM", importWindow, "BOTTOM", 0, 10)
    instructText:SetText("Paste encoded data above and click Import. This will merge with your existing blacklist.")
    instructText:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Make draggable
    importWindow:SetMovable(true)
    importWindow:EnableMouse(true)
    importWindow:RegisterForDrag("LeftButton")
    importWindow:SetScript("OnDragStart", importWindow.StartMoving)
    importWindow:SetScript("OnDragStop", importWindow.StopMovingOrSizing)

    importWindow:Show()
    self.importWindow = importWindow
end

-- Import blacklist data from base64 encoded string
function EnhancedSessionDetailWindow:ImportBlacklistData(encodedData)
    if not encodedData or encodedData:gsub("^%s*(.-)%s*$", "%1") == "" then
        print("MyUI2: No data to import")
        return
    end

    -- Base64 decode (simple implementation)
    local function base64Decode(data)
        -- Basic validation
        if not data or #data == 0 then 
            print("MyUI2: Empty base64 data")
            return "" 
        end
        
        -- Remove whitespace
        data = data:gsub("%s", "")
        
        -- Validate base64 characters
        if not data:match("^[A-Za-z0-9+/=]*$") then
            print("MyUI2: Invalid base64 characters found")
            return ""
        end
        
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local charMap = {}
        for i = 1, #chars do
            charMap[string.sub(chars, i, i)] = i - 1
        end
        
        local result = ""
        
        for i = 1, #data, 4 do
            local a = charMap[string.sub(data, i, i)] or 0
            local b = charMap[string.sub(data, i + 1, i + 1)] or 0
            local c = charMap[string.sub(data, i + 2, i + 2)] or 0
            local d = charMap[string.sub(data, i + 3, i + 3)] or 0
            
            local combined = bit.bor(bit.lshift(a, 18), bit.lshift(b, 12), bit.lshift(c, 6), d)
            
            result = result .. string.char(bit.rshift(combined, 16))
            if string.sub(data, i + 2, i + 2) ~= "=" then
                result = result .. string.char(bit.band(bit.rshift(combined, 8), 0xFF))
            end
            if string.sub(data, i + 3, i + 3) ~= "=" then
                result = result .. string.char(bit.band(combined, 0xFF))
            end
        end
        
        return result
    end

    -- Simple deserialization from string (matching our serialize format)
    local function deserializeTable(str)
        -- Basic safety check
        if not str or type(str) ~= "string" then return {} end
        
        -- Trim leading/trailing whitespace but preserve spaces within strings
        str = str:gsub("^%s+", ""):gsub("%s+$", "")
        if not str:match("^%{.*%}$") then
            print("MyUI2: Invalid blacklist format - must be a table structure")
            return nil
        end
        
        -- Try to parse using loadstring with environment protection
        local func, err = loadstring("return " .. str)
        if not func then
            print("MyUI2: Failed to parse blacklist data - syntax error:", err)
            return nil
        end
        
        -- Execute in protected environment
        local success, result = pcall(func)
        if success and type(result) == "table" then
            return result
        else
            print("MyUI2: Failed to execute blacklist data - invalid result type")
            return nil
        end
    end

    -- Decode and parse the data
    local decodedData = base64Decode(encodedData)
    addon:Debug("Decoded data length: %d", #decodedData)
    addon:Debug("First 100 chars: %s", decodedData:sub(1, 100))
    
    local importedBlacklist = deserializeTable(decodedData)
    
    if not importedBlacklist then
        print("MyUI2: Import failed - could not parse blacklist data")
        print("MyUI2: Try exporting a fresh blacklist to get valid format")
        return
    end
    
    -- DEBUG: Show what we're about to import
    print("MyUI2 DEBUG: Imported blacklist structure:")
    if importedBlacklist.zones then
        for zoneName, entities in pairs(importedBlacklist.zones) do
            print("  Zone: " .. zoneName)
            for entityName, enabled in pairs(entities) do
                print("    - '" .. entityName .. "' = " .. tostring(enabled))
            end
        end
    end

    -- Merge with existing blacklist data (imported entries are enabled by default)
    local merged = {
        global = 0,
        classes = 0,
        zones = 0
    }

    -- Merge global blacklist
    if importedBlacklist.global then
        EntityBlacklistDB.global = EntityBlacklistDB.global or {}
        for pattern, _ in pairs(importedBlacklist.global) do
            if not EntityBlacklistDB.global[pattern] then
                EntityBlacklistDB.global[pattern] = true -- Enable imported entries
                merged.global = merged.global + 1
            end
        end
    end

    -- Merge class blacklists
    if importedBlacklist.classes then
        EntityBlacklistDB.classes = EntityBlacklistDB.classes or {}
        for className, entities in pairs(importedBlacklist.classes) do
            EntityBlacklistDB.classes[className] = EntityBlacklistDB.classes[className] or {}
            for pattern, _ in pairs(entities) do
                if not EntityBlacklistDB.classes[className][pattern] then
                    EntityBlacklistDB.classes[className][pattern] = true -- Enable imported entries
                    merged.classes = merged.classes + 1
                end
            end
        end
    end

    -- Merge zone blacklists (new structure)
    if importedBlacklist.zones then
        EntityBlacklistDB.zones = EntityBlacklistDB.zones or {}
        for zoneName, entities in pairs(importedBlacklist.zones) do
            EntityBlacklistDB.zones[zoneName] = EntityBlacklistDB.zones[zoneName] or {}
            for pattern, _ in pairs(entities) do
                if not EntityBlacklistDB.zones[zoneName][pattern] then
                    EntityBlacklistDB.zones[zoneName][pattern] = true -- Enable imported entries
                    merged.zones = merged.zones + 1
                end
            end
        end
    end
    
    -- Handle legacy encounter blacklists (convert to zones for backward compatibility)
    if importedBlacklist.encounters then
        EntityBlacklistDB.zones = EntityBlacklistDB.zones or {}
        for zoneName, encounters in pairs(importedBlacklist.encounters) do
            EntityBlacklistDB.zones[zoneName] = EntityBlacklistDB.zones[zoneName] or {}
            for bossName, entities in pairs(encounters) do
                for pattern, _ in pairs(entities) do
                    if not EntityBlacklistDB.zones[zoneName][pattern] then
                        EntityBlacklistDB.zones[zoneName][pattern] = true -- Enable imported entries
                        merged.zones = merged.zones + 1
                    end
                end
            end
        end
        print("MyUI2: Converted legacy encounter-specific blacklists to zone-specific during import")
    end

    print(string.format("MyUI2: Imported blacklist entries - Global: %d, Classes: %d, Zones: %d", 
        merged.global, merged.classes, merged.zones))

    -- Close import window and refresh blacklist view if it's open
    if self.importWindow then
        self.importWindow:Hide()
        self.importWindow = nil
    end

    -- Refresh the blacklist tab if it's currently showing
    if self.frame and self.frame.currentContent then
        self:CreateBlacklistTab()
    end
end

-- Create whitelist tab (placeholder)
function EnhancedSessionDetailWindow:CreateWhitelistTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Entity Whitelist (Priority Tracking)")

    -- Description
    local descText = content:CreateFontString(nil, "OVERLAY")
    descText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    descText:SetPoint("TOP", content, "TOP", 0, -60)
    descText:SetText("Configure entities, buffs, and abilities that should always be tracked and charted,\neven if they would normally be filtered or blacklisted.")
    descText:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Future features section
    local futureTitle = content:CreateFontString(nil, "OVERLAY")
    futureTitle:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 13, "OUTLINE")
    futureTitle:SetPoint("TOP", content, "TOP", 0, -120)
    futureTitle:SetText("Planned Features:")
    futureTitle:SetTextColor(1, 0.8, 0.2, 1)

    local featuresList = {
        "• Priority buff tracking (important raid buffs that should always show)",
        "• Custom entity inclusion (override blacklists for specific entities)",
        "• VIP player tracking (always track specific players' actions)",
        "• Priority spell/ability tracking (key cooldowns to always display)",
        "• Import/Export whitelist configurations",
        "• Per-encounter whitelist settings"
    }

    local yOffset = -150
    for _, feature in ipairs(featuresList) do
        local featureText = content:CreateFontString(nil, "OVERLAY")
        featureText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
        featureText:SetPoint("TOPLEFT", content, "TOPLEFT", 50, yOffset)
        featureText:SetText(feature)
        featureText:SetTextColor(0.7, 0.9, 0.7, 1)
        yOffset = yOffset - 20
    end

    -- Coming soon notice
    local comingSoonText = content:CreateFontString(nil, "OVERLAY")
    comingSoonText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    comingSoonText:SetPoint("BOTTOM", content, "BOTTOM", 0, 80)
    comingSoonText:SetText("🚧 Coming Soon! 🚧")
    comingSoonText:SetTextColor(1, 0.6, 0.2, 1)

    local implementationText = content:CreateFontString(nil, "OVERLAY")
    implementationText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    implementationText:SetPoint("BOTTOM", content, "BOTTOM", 0, 50)
    implementationText:SetText("This feature will be implemented in a future update.")
    implementationText:SetTextColor(0.8, 0.8, 0.8, 1)

    content:Show()
    self.frame.currentContent = content
end

-- Create participants tab - ENHANCED VERSION
function EnhancedSessionDetailWindow:CreateParticipantsTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Combat Participants")

    -- Check for enhanced data
    if not self.sessionData.enhancedData or not self.sessionData.enhancedData.participants then
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", content, "CENTER", 0, 0)
        noDataText:SetText("No participant data available\n(Enhanced logging was not active during this session)")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)

        -- Add instructions for enabling enhanced logging
        local instructionText = content:CreateFontString(nil, "OVERLAY")
        instructionText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
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
    searchBox:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")

    local searchLabel = filterFrame:CreateFontString(nil, "OVERLAY")
    searchLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 9, "OUTLINE")
    searchLabel:SetPoint("BOTTOMLEFT", searchBox, "TOPLEFT", 0, 2)
    searchLabel:SetText("Search:")
    searchLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Type filter dropdown
    local typeFilter = CreateFrame("Frame", nil, filterFrame, "UIDropDownMenuTemplate")
    typeFilter:SetPoint("LEFT", searchBox, "RIGHT", 10, 5)
    UIDropDownMenu_SetWidth(typeFilter, 90)
    UIDropDownMenu_SetText(typeFilter, "All Types")

    local typeLabel = filterFrame:CreateFontString(nil, "OVERLAY")
    typeLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 9, "OUTLINE")
    typeLabel:SetPoint("BOTTOMLEFT", typeFilter, "TOPLEFT", 20, 2)
    typeLabel:SetText("Type:")
    typeLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Show zero contributors toggle
    local showZeroBtn = CreateFrame("CheckButton", nil, filterFrame, "UICheckButtonTemplate")
    showZeroBtn:SetSize(14, 14)
    showZeroBtn:SetPoint("LEFT", typeFilter, "RIGHT", 10, 5)
    showZeroBtn:SetChecked(false)

    local showZeroLabel = filterFrame:CreateFontString(nil, "OVERLAY")
    showZeroLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 9, "OUTLINE")
    showZeroLabel:SetPoint("LEFT", showZeroBtn, "RIGHT", 3, 0)
    showZeroLabel:SetText("Show Zero")
    showZeroLabel:SetTextColor(0.8, 0.8, 0.8, 1)

    -- Clear filters button
    local clearBtn = CreateFrame("Button", nil, filterFrame)
    clearBtn:SetSize(45, 18)
    clearBtn:SetPoint("LEFT", showZeroLabel, "RIGHT", 8, 0)
    clearBtn:SetNormalFontObject("GameFontNormalSmall")
    clearBtn:SetText("Clear")
    clearBtn:GetFontString():SetTextColor(0.8, 0.8, 0.8, 1)

    local clearBg = clearBtn:CreateTexture(nil, "BACKGROUND")
    clearBg:SetAllPoints(clearBtn)
    clearBg:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    -- Store references
    self.participantFilters = {
        searchBox = searchBox,
        typeFilter = typeFilter,
        clearBtn = clearBtn,
        showZeroBtn = showZeroBtn
    }

    -- Set up filter functionality
    self:SetupParticipantFilters()
end

-- Set up participant filter functionality
function EnhancedSessionDetailWindow:SetupParticipantFilters()
    local filters = self.participantFilters
    local window = self -- Store reference to avoid context issues

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
        local totalContribution = (participant.damageDealt or 0) + (participant.healingDealt or 0) +
            (participant.damageTaken or 0)
        local matchesContribution = showZeroContributors or totalContribution > 0

        if matchesSearch and matchesType and matchesContribution then
            table.insert(self.filteredParticipants, participant)
        end
    end

    self:RefreshParticipantsList()
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
    self.sortColumn = "total"   -- default sort by total damage + healing
    self.sortDirection = "desc" -- descending by default

    -- Clickable column headers with sorting
    local nameHeaderBtn = CreateFrame("Button", nil, headerRow)
    nameHeaderBtn:SetSize(150, 25)
    nameHeaderBtn:SetPoint("LEFT", headerRow, "LEFT", 10, 0)
    nameHeaderBtn:SetScript("OnClick", function() self:SortParticipants("name") end)

    local nameHeader = nameHeaderBtn:CreateFontString(nil, "OVERLAY")
    nameHeader:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
    typeHeader:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
    damageHeader:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
    healingHeader:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
    takenHeader:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
    nameText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    nameText:SetPoint("LEFT", row, "LEFT", 10, 0)
    nameText:SetSize(150, 0)
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    -- Type
    local typeText = row:CreateFontString(nil, "OVERLAY")
    typeText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
    typeText:SetPoint("LEFT", row, "LEFT", 170, 0)
    typeText:SetSize(80, 0)
    typeText:SetJustifyH("CENTER")
    typeText:SetTextColor(0.7, 0.7, 0.7, 1)
    row.typeText = typeText

    -- Damage dealt
    local damageText = row:CreateFontString(nil, "OVERLAY")
    damageText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    damageText:SetPoint("LEFT", row, "LEFT", 260, 0)
    damageText:SetSize(100, 0)
    damageText:SetJustifyH("RIGHT")
    damageText:SetTextColor(1, 0.4, 0.4, 1)
    row.damageText = damageText

    -- Healing dealt
    local healingText = row:CreateFontString(nil, "OVERLAY")
    healingText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
    healingText:SetPoint("LEFT", row, "LEFT", 370, 0)
    healingText:SetSize(100, 0)
    healingText:SetJustifyH("RIGHT")
    healingText:SetTextColor(0.4, 1, 0.4, 1)
    row.healingText = healingText

    -- Damage taken
    local takenText = row:CreateFontString(nil, "OVERLAY")
    takenText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
                if participant.isPlayer then
                    return 1
                elseif participant.isPet then
                    return 2
                else
                    return 3
                end
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
    -- Reset all headers to base names
    local baseNames = {
        name = "Name",
        type = "Type",
        damage = "Damage Dealt",
        healing = "Healing Dealt",
        taken = "Damage Taken"
    }

    for column, header in pairs(self.columnHeaders) do
        header.text:SetText(baseNames[column] or "")
        header.text:SetTextColor(1, 1, 1, 1)
    end

    -- Add arrow to current sort column
    if self.columnHeaders[self.sortColumn] then
        local header = self.columnHeaders[self.sortColumn]
        local baseName = baseNames[self.sortColumn] or ""
        local arrow = self.sortDirection == "asc" and " ↑" or " ↓"
        header.text:SetText(baseName .. arrow)
        header.text:SetTextColor(0.8, 0.8, 1, 1) -- Highlight sorted column
    end
end

-- Create damage analysis tab - FIXED VERSION
function EnhancedSessionDetailWindow:CreateDamageTab()
    local content = CreateFrame("Frame", nil, self.frame.contentArea)
    content:SetAllPoints(self.frame.contentArea)

    local title = content:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", content, "TOP", 0, -20)
    title:SetText("Damage Analysis")

    if not self.sessionData.enhancedData then
        local noDataText = content:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
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
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
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
        insightText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
    sectionTitle:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    sectionTitle:SetPoint("TOP", sectionFrame, "TOP", 0, -10)
    sectionTitle:SetText(string.format("Personal Damage Taken (%d events)", #damageTaken))
    sectionTitle:SetTextColor(1, 0.8, 0.4, 1)

    if #damageTaken == 0 then
        local noDataText = sectionFrame:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
        sourceText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
        sourceText:SetPoint("TOPLEFT", sectionFrame, "TOPLEFT", 10, yOffset)
        sourceText:SetText(string.format("%s: %s (%.1f%%) - %d hits",
            source.name, addon.CombatTracker:FormatNumber(source.damage), percent, source.hits))
        sourceText:SetTextColor(1, 0.8, 0.6, 1)

        yOffset = yOffset - 20
    end

    -- Total summary
    local totalText = sectionFrame:CreateFontString(nil, "OVERLAY")
    totalText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
    sectionTitle:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    sectionTitle:SetPoint("TOP", sectionFrame, "TOP", 0, -10)
    sectionTitle:SetText(string.format("Group Damage Events (%d events)", #groupDamage))
    sectionTitle:SetTextColor(0.8, 0.4, 1, 1)

    if #groupDamage == 0 then
        local noDataText = sectionFrame:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
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
        sourceText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
        sourceText:SetPoint("TOPLEFT", sectionFrame, "TOPLEFT", 10, yOffset)
        sourceText:SetText(string.format("%s: %s (%.1f%%) - %d hits, %d targets",
            source.name, addon.CombatTracker:FormatNumber(source.damage),
            percent, source.hits, source.targetCount))
        sourceText:SetTextColor(0.8, 0.6, 1, 1)

        yOffset = yOffset - 20
    end
end

-- Close button and controls (bottom-right close button removed per user feedback)
function EnhancedSessionDetailWindow:CreateCloseButton(frame)
    -- Bottom-right close button removed per user feedback
    -- Only the standard top-right X button remains
end

-- Show enhanced session detail window
function EnhancedSessionDetailWindow:Show(sessionData)
    -- Try to attach enhanced data if available and not already present
    if not sessionData.enhancedData then
        if addon.EnhancedCombatLogger then
            local enhancedData = addon.EnhancedCombatLogger:GetEnhancedSessionData()
            if enhancedData then
                sessionData.enhancedData = enhancedData
                addon:Debug("Attached current enhanced data to session")
            end
        end

        -- Also try to get from session manager if this is a stored session
        if addon.SessionManager then
            local storedSession = addon.SessionManager:GetSession(sessionData.sessionId)
            if storedSession and storedSession.enhancedData then
                sessionData.enhancedData = storedSession.enhancedData
                addon:Debug("Retrieved enhanced data from stored session")
            end
        end
    end

    self:Create(sessionData)
    -- Bottom-right close button removed per user feedback
    -- self:CreateCloseButton(self.frame)
end

-- Hide window with proper cleanup
function EnhancedSessionDetailWindow:Hide()
    -- Clean up share window
    if self.shareWindow then
        self.shareWindow:Hide()
        self.shareWindow = nil
    end
    
    -- Clean up import window
    if self.importWindow then
        self.importWindow:Hide()
        self.importWindow = nil
    end
    
    -- Hide main window
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
end
