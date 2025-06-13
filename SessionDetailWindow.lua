-- SessionDetailWindow.lua
-- Detailed view for individual combat sessions with timeline visualization

local addonName, addon = ...

addon.SessionDetailWindow = {}
local SessionDetailWindow = addon.SessionDetailWindow

-- Create detail window for a specific session
function SessionDetailWindow:Create(sessionData)
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end

    local frame = CreateFrame("Frame", addonName .. "SessionDetailFrame", UIParent)
    frame:SetSize(600, 490)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    -- Background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.8)

    -- Border
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
    local headerPanel = CreateFrame("Frame", nil, frame)
    headerPanel:SetSize(580, 80)
    headerPanel:SetPoint("TOP", frame, "TOP", 0, -10)

    local headerBg = headerPanel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetAllPoints(headerPanel)
    headerBg:SetColorTexture(0.1, 0.1, 0.1, 0.7)

    -- Session title
    local title = headerPanel:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 16, "OUTLINE")
    title:SetPoint("TOP", headerPanel, "TOP", 0, -8)
    title:SetText(string.format("Combat Session: %s", sessionData.sessionId))
    title:SetTextColor(1, 1, 1, 1)

    -- Session metadata (two columns)
    local startTime = date("%H:%M:%S", time() + (sessionData.startTime - GetTime()))
    local endTime = date("%H:%M:%S", time() + (sessionData.endTime - GetTime()))

    -- Left column
    local leftMeta = headerPanel:CreateFontString(nil, "OVERLAY")
    leftMeta:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    leftMeta:SetPoint("TOPLEFT", headerPanel, "TOPLEFT", 10, -25)
    leftMeta:SetText(string.format("Start: %s\nDuration: %.1fs\nLocation: %s",
        startTime, sessionData.duration, sessionData.location or "Unknown"))
    leftMeta:SetJustifyH("LEFT")

    -- Right column
    local rightMeta = headerPanel:CreateFontString(nil, "OVERLAY")
    rightMeta:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    rightMeta:SetPoint("TOPRIGHT", headerPanel, "TOPRIGHT", -10, -25)
    rightMeta:SetText(string.format("Quality: %d\nContent: %s\nActions: %d",
        sessionData.qualityScore, sessionData.contentType or "normal", sessionData.actionCount or 0))
    rightMeta:SetJustifyH("RIGHT")

    -- === PERFORMANCE SUMMARY ===
    local summaryPanel = CreateFrame("Frame", nil, frame)
    summaryPanel:SetSize(580, 60)
    summaryPanel:SetPoint("TOP", headerPanel, "BOTTOM", 0, -5)

    local summaryBg = summaryPanel:CreateTexture(nil, "BACKGROUND")
    summaryBg:SetAllPoints(summaryPanel)
    summaryBg:SetColorTexture(0.05, 0.05, 0.05, 0.7)

    local summaryTitle = summaryPanel:CreateFontString(nil, "OVERLAY")
    summaryTitle:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    summaryTitle:SetPoint("TOP", summaryPanel, "TOP", 0, -5)
    summaryTitle:SetText("Performance Summary")

    -- Performance metrics (4 columns)
    local dpsCol = summaryPanel:CreateFontString(nil, "OVERLAY")
    dpsCol:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    dpsCol:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", 15, -25)
    dpsCol:SetText(string.format("Avg DPS\n%s", addon.CombatTracker:FormatNumber(sessionData.avgDPS)))
    dpsCol:SetTextColor(1, 0.3, 0.3, 1)

    local peakDpsCol = summaryPanel:CreateFontString(nil, "OVERLAY")
    peakDpsCol:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    peakDpsCol:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", 145, -25)
    peakDpsCol:SetText(string.format("Peak DPS\n%s", addon.CombatTracker:FormatNumber(sessionData.peakDPS)))
    peakDpsCol:SetTextColor(1, 0.5, 0.5, 1)

    local hpsCol = summaryPanel:CreateFontString(nil, "OVERLAY")
    hpsCol:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    hpsCol:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", 275, -25)
    hpsCol:SetText(string.format("Avg HPS\n%s", addon.CombatTracker:FormatNumber(sessionData.avgHPS)))
    hpsCol:SetTextColor(0.3, 1, 0.3, 1)

    local peakHpsCol = summaryPanel:CreateFontString(nil, "OVERLAY")
    peakHpsCol:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    peakHpsCol:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", 405, -25)
    peakHpsCol:SetText(string.format("Peak HPS\n%s", addon.CombatTracker:FormatNumber(sessionData.peakHPS)))
    peakHpsCol:SetTextColor(0.5, 1, 0.5, 1)
    
    -- === CALCULATION METHOD COMPARISON ===
    local comparisonPanel = CreateFrame("Frame", nil, frame)
    comparisonPanel:SetSize(580, 40)
    comparisonPanel:SetPoint("TOP", summaryPanel, "BOTTOM", 0, -5)
    
    local compBg = comparisonPanel:CreateTexture(nil, "BACKGROUND")
    compBg:SetAllPoints(comparisonPanel)
    compBg:SetColorTexture(0.05, 0.05, 0.15, 0.7)
    
    -- Calculate alternative method values for comparison
    local altDPS, altHPS = sessionData.avgDPS, sessionData.avgHPS
    local methodNote = "Session stored with unified calculation"
    
    if sessionData.totalDamage and sessionData.totalHealing and sessionData.duration > 0 then
        altDPS = sessionData.totalDamage / sessionData.duration
        altHPS = sessionData.totalHealing / sessionData.duration
        
        local dpsVariance = math.abs(sessionData.avgDPS - altDPS)
        local hpsVariance = math.abs(sessionData.avgHPS - altHPS)
        local dpsPercent = sessionData.avgDPS > 0 and (dpsVariance / sessionData.avgDPS) * 100 or 0
        local hpsPercent = sessionData.avgHPS > 0 and (hpsVariance / sessionData.avgHPS) * 100 or 0
        
        if dpsPercent > 5 or hpsPercent > 5 then
            methodNote = string.format("Raw calc differs: %.1f%% DPS, %.1f%% HPS variance", dpsPercent, hpsPercent)
        else
            methodNote = "Raw calculation matches stored values"
        end
    end
    
    local comparisonText = comparisonPanel:CreateFontString(nil, "OVERLAY")
    comparisonText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    comparisonText:SetPoint("CENTER", comparisonPanel, "CENTER", 0, 5)
    comparisonText:SetText(string.format("Stored: %s DPS, %s HPS | Raw: %s DPS, %s HPS",
        addon.CombatTracker:FormatNumber(sessionData.avgDPS),
        addon.CombatTracker:FormatNumber(sessionData.avgHPS),
        addon.CombatTracker:FormatNumber(altDPS),
        addon.CombatTracker:FormatNumber(altHPS)))
    comparisonText:SetTextColor(0.8, 0.8, 1, 1)
    
    local methodText = comparisonPanel:CreateFontString(nil, "OVERLAY")
    methodText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 9, "OUTLINE")
    methodText:SetPoint("CENTER", comparisonPanel, "CENTER", 0, -10)
    methodText:SetText(methodNote)
    methodText:SetTextColor(0.6, 0.6, 0.8, 1)

    -- === TIMELINE CHART ===
    local chartPanel = CreateFrame("Frame", nil, frame)
    chartPanel:SetSize(580, 220)
    chartPanel:SetPoint("TOP", comparisonPanel, "BOTTOM", 0, -5)

    local chartBg = chartPanel:CreateTexture(nil, "BACKGROUND")
    chartBg:SetAllPoints(chartPanel)
    chartBg:SetColorTexture(0.02, 0.02, 0.02, 0.8)

    local chartTitle = chartPanel:CreateFontString(nil, "OVERLAY")
    chartTitle:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    chartTitle:SetPoint("TOP", chartPanel, "TOP", 0, -5)
    chartTitle:SetText("Performance Timeline")

    -- Chart area
    local chartArea = CreateFrame("Frame", nil, chartPanel)
    chartArea:SetSize(540, 180)
    chartArea:SetPoint("BOTTOM", chartPanel, "BOTTOM", 0, 10)

    local chartAreaBg = chartArea:CreateTexture(nil, "BACKGROUND")
    chartAreaBg:SetAllPoints(chartArea)
    chartAreaBg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    -- Grid lines (simple)
    local gridLines = {}
    for i = 1, 4 do
        local line = chartArea:CreateTexture(nil, "BORDER")
        line:SetSize(540, 1)
        line:SetPoint("BOTTOM", chartArea, "BOTTOM", 0, (i * 36))
        line:SetColorTexture(0.3, 0.3, 0.3, 0.3)
        table.insert(gridLines, line)
    end

    -- Timeline data visualization would go here
    -- For now, create placeholder elements
    self:CreateTimelineVisualization(chartArea, sessionData)

    -- === CONTROL BUTTONS ===
    local controlPanel = CreateFrame("Frame", nil, frame)
    controlPanel:SetSize(580, 40)
    controlPanel:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)


    local exportBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    exportBtn:SetSize(80, 25)
    exportBtn:SetPoint("RIGHT", controlPanel, "RIGHT", -10, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        self:ExportSession(sessionData)
    end)

    -- Mark as representative button
    local markRepBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    markRepBtn:SetSize(100, 25)
    markRepBtn:SetPoint("LEFT", controlPanel, "LEFT", 10, 0)
    if sessionData.userMarked == "representative" then
        markRepBtn:SetText("★ Representative")
        markRepBtn:Disable()
    else
        markRepBtn:SetText("Mark as Rep")
        markRepBtn:SetScript("OnClick", function()
            if addon.CombatTracker then
                addon.CombatTracker:MarkSession(sessionData.sessionId, "representative")
                markRepBtn:SetText("★ Representative")
                markRepBtn:Disable()
                print(string.format("Session %s marked as representative", sessionData.sessionId))
            end
        end)
    end

    self.frame = frame
    self.sessionData = sessionData
    frame:Show()
end

-- Create timeline visualization from session data
function SessionDetailWindow:CreateTimelineVisualization(chartArea, sessionData)
    -- Use real timeline data if available, otherwise fall back to estimated data
    local timelinePoints = {}

    if sessionData.timelineData and #sessionData.timelineData > 0 then
        -- Use actual timeline data
        timelinePoints = sessionData.timelineData
        if addon.DEBUG then
            print(string.format("Using real timeline data: %d points", #timelinePoints))
        end
    else
        -- Fall back to estimated timeline for older sessions
        timelinePoints = self:GenerateEstimatedTimeline(sessionData)
        if addon.DEBUG then
            print("Using estimated timeline data (no real data available)")
        end
    end

    -- OPTION 3: Smart baseline - ensure timeline starts at 0 and ends properly
    if #timelinePoints > 0 then
        -- Add starting point if first sample isn't at 0
        if timelinePoints[1].elapsed > 0.1 then
            table.insert(timelinePoints, 1, {
                elapsed = 0,
                instantDPS = 0,
                instantHPS = 0,
                averageDPS = 0,
                averageHPS = 0,
                totalDamage = 0,
                totalHealing = 0,
                overhealPercent = 0
            })
            if addon.DEBUG then
                print("Added starting point at elapsed=0")
            end
        end

        -- Add ending point if needed
        local lastPoint = timelinePoints[#timelinePoints]
        if lastPoint.elapsed < (sessionData.duration - 0.5) then
            table.insert(timelinePoints, {
                elapsed = sessionData.duration,
                instantDPS = 0,
                instantHPS = 0,
                averageDPS = sessionData.avgDPS,
                averageHPS = sessionData.avgHPS,
                totalDamage = sessionData.totalDamage,
                totalHealing = sessionData.totalHealing,
                overhealPercent = 0
            })
            if addon.DEBUG then
                print(string.format("Added ending point at elapsed=%.1f", sessionData.duration))
            end
        end

        if addon.DEBUG then
            print(string.format("Timeline after smart baseline: %d points, %.1fs to %.1fs",
                #timelinePoints, timelinePoints[1].elapsed, timelinePoints[#timelinePoints].elapsed))
        end
    end

    if #timelinePoints == 0 then
        -- Show "no data" message
        local noDataText = chartArea:CreateFontString(nil, "OVERLAY")
        noDataText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
        noDataText:SetPoint("CENTER", chartArea, "CENTER", 0, 0)
        noDataText:SetText("No timeline data available")
        noDataText:SetTextColor(0.6, 0.6, 0.6, 1)
        return
    end

    -- Find max values for scaling
    local maxDPS, maxHPS = 0, 0
    for _, point in ipairs(timelinePoints) do
        maxDPS = math.max(maxDPS, point.instantDPS or point.averageDPS or 0)
        maxHPS = math.max(maxHPS, point.instantHPS or point.averageHPS or 0)
    end

    -- Timeline debug (no spam)
    if addon.DEBUG then
        print("=== TIMELINE DEBUG ===")
        print(string.format("Chart max DPS: %.0f vs Summary peak: %.0f", maxDPS, sessionData.peakDPS))
        print(string.format("Chart max HPS: %.0f vs Summary peak: %.0f", maxHPS, sessionData.peakHPS))
        print(string.format("Timeline points: %d", #timelinePoints))

        -- Show first few points
        for i = 1, math.min(3, #timelinePoints) do
            local p = timelinePoints[i]
            print(string.format("Point %d: elapsed=%.1f, DPS=%.0f, HPS=%.0f",
                i, p.elapsed, p.instantDPS or 0, p.instantHPS or 0))
        end
        print("==================")
    end

    -- Create connected line visualization instead of dots
    local chartWidth = 540
    local chartHeight = 160
    local pointWidth = chartWidth / math.max(1, #timelinePoints - 1)

    local previousDPSPoint = nil
    local previousHPSPoint = nil

    for i, point in ipairs(timelinePoints) do
        if i <= 150 then -- Limit for performance
            local x = (i - 1) * pointWidth

            -- Use instantaneous values for more interesting visualization
            local dpsValue = point.instantDPS or point.averageDPS or 0
            local hpsValue = point.instantHPS or point.averageHPS or 0

            -- DPS line - draw ALL points including zeros
            if maxDPS > 0 then
                local dpsHeight = dpsValue > 0 and math.max(2, (dpsValue / maxDPS) * chartHeight) or 1

                if previousDPSPoint then
                    -- Draw line segment from previous point
                    local lineLength = math.sqrt((x - previousDPSPoint.x) ^ 2 + (dpsHeight - previousDPSPoint.y) ^ 2)
                    local lineSegments = math.max(1, math.floor(lineLength / 3))

                    for j = 1, lineSegments do
                        local t = j / lineSegments
                        local lineX = previousDPSPoint.x + t * (x - previousDPSPoint.x)
                        local lineY = previousDPSPoint.y + t * (dpsHeight - previousDPSPoint.y)

                        local dpsPoint = chartArea:CreateTexture(nil, "ARTWORK")
                        dpsPoint:SetSize(2, 2)
                        dpsPoint:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", lineX, lineY)
                        -- Different color for zero values
                        if dpsValue > 0 then
                            dpsPoint:SetColorTexture(1, 0.3, 0.3, 0.9)
                        else
                            dpsPoint:SetColorTexture(0.5, 0.1, 0.1, 0.6) -- Dimmer red for zeros
                        end
                    end
                end

                previousDPSPoint = { x = x, y = dpsHeight }
            end

            -- HPS line - draw ALL points including zeros
            if maxHPS > 0 then
                local hpsHeight = hpsValue > 0 and math.max(2, (hpsValue / maxHPS) * chartHeight) or 1

                if previousHPSPoint then
                    -- Draw line segment from previous point
                    local lineLength = math.sqrt((x - previousHPSPoint.x) ^ 2 + (hpsHeight - previousHPSPoint.y) ^ 2)
                    local lineSegments = math.max(1, math.floor(lineLength / 3))

                    for j = 1, lineSegments do
                        local t = j / lineSegments
                        local lineX = previousHPSPoint.x + t * (x - previousHPSPoint.x)
                        local lineY = previousHPSPoint.y + t * (hpsHeight - previousHPSPoint.y)

                        local hpsPoint = chartArea:CreateTexture(nil, "ARTWORK")
                        hpsPoint:SetSize(2, 2)
                        hpsPoint:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", lineX, lineY)
                        -- Different color for zero values
                        if hpsValue > 0 then
                            hpsPoint:SetColorTexture(0.3, 1, 0.3, 0.9)
                        else
                            hpsPoint:SetColorTexture(0.1, 0.5, 0.1, 0.6) -- Dimmer green for zeros
                        end
                    end
                end

                previousHPSPoint = { x = x, y = hpsHeight }
            end
        end
    end

    -- Add scale indicators
    local scaleText = chartArea:CreateFontString(nil, "OVERLAY")
    scaleText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 9, "OUTLINE")
    scaleText:SetPoint("TOPLEFT", chartArea, "TOPLEFT", 5, -5)
    scaleText:SetText(string.format("Max: %s DPS, %s HPS",
        addon.CombatTracker:FormatNumber(maxDPS),
        addon.CombatTracker:FormatNumber(maxHPS)))
    scaleText:SetTextColor(0.7, 0.7, 0.7, 1)

    -- Add legend
    local legend = chartArea:CreateFontString(nil, "OVERLAY")
    legend:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    legend:SetPoint("TOPRIGHT", chartArea, "TOPRIGHT", -5, -5)
    legend:SetText("Red: DPS  Green: HPS")
    legend:SetTextColor(0.8, 0.8, 0.8, 1)
end

-- Generate estimated timeline data for sessions without real timeline data
function SessionDetailWindow:GenerateEstimatedTimeline(sessionData)
    local points = {}
    local duration = sessionData.duration

    if duration <= 0 then return points end

    local intervals = math.min(60, math.floor(duration * 2)) -- Every 0.5s, max 60 points

    for i = 1, intervals do
        local timePercent = i / intervals
        local elapsed = timePercent * duration

        -- Create a more realistic ramp-up pattern
        local rampUp = math.min(1.0, elapsed / 3.0) -- 3 second ramp up
        local fadeOut = elapsed > (duration - 2) and math.max(0.3, (duration - elapsed) / 2) or 1.0

        -- Add some realistic variation
        local variation = 0.7 + (math.random() * 0.6) -- 70% to 130% of average
        local intensity = rampUp * fadeOut * variation

        table.insert(points, {
            elapsed = elapsed,
            instantDPS = sessionData.avgDPS * intensity,
            instantHPS = sessionData.avgHPS * intensity,
            averageDPS = sessionData.avgDPS,
            averageHPS = sessionData.avgHPS
        })
    end

    return points
end

-- Export session data (future feature)
function SessionDetailWindow:ExportSession(sessionData)
    print("Export functionality not yet implemented")
    print("Would export:", sessionData.sessionId)
    -- Future: Create CSV/JSON export of session data
end

-- Show session detail window
function SessionDetailWindow:Show(sessionData)
    self:Create(sessionData)
end

-- Hide session detail window
function SessionDetailWindow:Hide()
    if self.frame then
        self.frame:Hide()
        self.frame = nil
    end
end
