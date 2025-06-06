-- MyUI.lua
-- Basic World of Warcraft UI Addon

-- Create addon namespace
local addonName, addon = ...

-- Force reload flag for development
if not addon.devMode then
    addon.devMode = true
    print("Development mode enabled - caching disabled")
end

-- Initialize addon
addon.frame = CreateFrame("Frame")

-- Development version tracking
addon.VERSION = "main-51c8546"
addon.BUILD_DATE = "2025-06-06-15:40"

-- Debug flag (will be loaded from saved variables)
addon.DEBUG = false

-- Addon variables
addon.db = {}
addon.defaults = {
    enabled = true,
    showMinimap = false,
    minimapButtonAngle = 225, -- Default bottom-left position
    scale = 1.0,
    framePosition = nil,
    dpsWindowPosition = nil,
    showDPSWindow = false,
    hpsWindowPosition = nil,
    showHPSWindow = false,
    debugMode = false,
    showMainWindow = false
}

-- Debug print function
function addon:DebugPrint(...)
    if self.DEBUG then
        print("[" .. addonName .. " DEBUG]", ...)
    end
end

-- Function to dump table contents (useful for debugging)
function addon:DumpTable(tbl, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)

    if not tbl then
        print(spacing .. "nil")
        return
    end

    for k, v in pairs(tbl) do
        if type(v) == "table" then
            print(spacing .. tostring(k) .. " = {")
            self:DumpTable(v, indent + 1)
            print(spacing .. "}")
        else
            print(spacing .. tostring(k) .. " = " .. tostring(v))
        end
    end
end

-- Safe function wrapper for development
local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        print("Error in " .. addonName .. ": " .. tostring(result))
    end
    return success, result
end

-- Event handler function
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            SafeCall(addon.OnInitialize, addon)
        end
    elseif event == "PLAYER_LOGIN" then
        SafeCall(addon.OnEnable, addon)
    elseif event == "PLAYER_LOGOUT" then
        SafeCall(addon.OnDisable, addon)
    end
end

-- Register events
addon.frame:RegisterEvent("ADDON_LOADED")
addon.frame:RegisterEvent("PLAYER_LOGIN")
addon.frame:RegisterEvent("PLAYER_LOGOUT")
addon.frame:SetScript("OnEvent", OnEvent)

-- Initialize function
function addon:OnInitialize()
    -- Print version info to confirm new code loaded
    print(string.format("%s v%s (Build: %s) loaded!", addonName, addon.VERSION, addon.BUILD_DATE))

    -- Load saved variables or set defaults
    if MyUIDB == nil then
        MyUIDB = {}
    end

    -- Merge defaults with saved settings
    for key, value in pairs(self.defaults) do
        if MyUIDB[key] == nil then
            MyUIDB[key] = value
        end
    end

    self.db = MyUIDB

    -- Load debug state from saved variables
    self.DEBUG = self.db.debugMode

    -- Initialize all modules
    if self.CombatTracker then
        self.CombatTracker:Initialize()
        self.CombatTracker:InitializeSessionHistory()
    end
    if self.DPSWindow then
        self.DPSWindow:Initialize()
    end
    if self.HPSWindow then
        self.HPSWindow:Initialize()
    end

    print(addonName .. " loaded successfully!")
    print("Use /myui to toggle the main configuration window")
end

function addon:OnEnable()
    if self.db.enabled then
        self:CreateMainFrame()

        -- Debug the state
        print("showMainWindow value:", self.db.showMainWindow)

        if self.db.showMainWindow then
            print("Showing main window")
            self.mainFrame:Show()
        else
            print("Not showing main window")
        end


        -- Restore other windows...
        if self.db.showDPSWindow and self.DPSWindow then
            self.DPSWindow:Show()
        end

        if self.db.showHPSWindow and self.HPSWindow then
            self.HPSWindow:Show()
        end

        print(addonName .. " is now active!")
    end
end

-- Disable function
function addon:OnDisable()
    -- Save frame position before logout
    if self.mainFrame then
        if self.mainFrame:IsShown() then
            local point, relativeTo, relativePoint, xOfs, yOfs = self.mainFrame:GetPoint()
            self.db.framePosition = {
                point = point,
                relativePoint = relativePoint,
                xOffset = xOfs,
                yOffset = yOfs
            }
        end
        self.db.showMainWindow = self.mainFrame:IsShown()
    end

    -- Save visibility states for all windows
    if self.DPSWindow and self.DPSWindow.frame then
        self.db.showDPSWindow = self.DPSWindow.frame:IsShown()
    end

    if self.HPSWindow and self.HPSWindow.frame then
        self.db.showHPSWindow = self.HPSWindow.frame:IsShown()
    end
end

-- Toggle main window function
function addon:ToggleMainWindow()
    if not self.mainFrame then
        self:CreateMainFrame()
    end

    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
        self.db.showMainWindow = false
        print("Main window hidden")
    else
        self.mainFrame:Show()
        self.db.showMainWindow = true
        print("Main window shown")
    end
end

-- Update status display
function addon:UpdateStatusDisplay()
    if not self.mainFrame or not self.mainFrame.statusText then
        return
    end

    local debugStatus = self.DEBUG and "|cff00ff00ON|r" or "|cffff0000OFF|r"
    local combatStatus = (self.CombatTracker and self.CombatTracker:IsInCombat()) and "|cffff0000IN COMBAT|r" or
        "|cff888888Out of Combat|r"

    self.mainFrame.statusText:SetText("Debug: " .. debugStatus .. "\nCombat: " .. combatStatus)
end

function addon:CreateMainFrame()
    if self.mainFrame then return end

    local frame = CreateFrame("Frame", addonName .. "MainFrame", UIParent)
    frame:SetSize(440, 480)

    -- Add main background
    local mainBg = frame:CreateTexture(nil, "BACKGROUND")
    mainBg:SetAllPoints(frame)
    mainBg:SetColorTexture(0, 0, 0, 0.7)

    -- Position and dragging
    if self.db.framePosition then
        frame:SetPoint(
            self.db.framePosition.point or "CENTER",
            UIParent,
            self.db.framePosition.relativePoint or "CENTER",
            self.db.framePosition.xOffset or 0,
            self.db.framePosition.yOffset or 0
        )
    else
        frame:SetPoint("CENTER")
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        addon.db.framePosition = {
            point = point,
            relativePoint = relativePoint,
            xOffset = xOfs,
            yOffset = yOfs
        }
    end)

    -- Frame title
    -- frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    -- frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    -- frame.title:SetText("MyUI v" .. addon.VERSION)

    -- === CURRENT COMBAT PANEL ===
    local combatPanel = CreateFrame("Frame", nil, frame)
    combatPanel:SetSize(400, 75)
    combatPanel:SetPoint("TOP", frame, "TOP", 0, -30)

    local combatBg = combatPanel:CreateTexture(nil, "BACKGROUND")
    combatBg:SetAllPoints(combatPanel)
    combatBg:SetColorTexture(0, 0, 0, 0.7)

    local combatBorder = combatPanel:CreateTexture(nil, "BORDER")
    combatBorder:SetAllPoints(combatPanel)
    combatBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
    combatBg:SetPoint("TOPLEFT", combatBorder, "TOPLEFT", 1, -1)
    combatBg:SetPoint("BOTTOMRIGHT", combatBorder, "BOTTOMRIGHT", -1, 1)

    local combatHeader = combatPanel:CreateFontString(nil, "OVERLAY")
    combatHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    combatHeader:SetPoint("TOP", combatPanel, "TOP", 0, -8)
    combatHeader:SetText("Last Combat")
    frame.combatHeader = combatHeader

    local dpsText = combatPanel:CreateFontString(nil, "OVERLAY")
    dpsText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    dpsText:SetPoint("TOPLEFT", combatPanel, "TOPLEFT", 10, -25)
    dpsText:SetText("DPS: 0")
    frame.dpsText = dpsText

    local hpsText = combatPanel:CreateFontString(nil, "OVERLAY")
    hpsText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    hpsText:SetPoint("TOPRIGHT", combatPanel, "TOPRIGHT", -10, -25)
    hpsText:SetText("HPS: 0")
    frame.hpsText = hpsText

    local damageText = combatPanel:CreateFontString(nil, "OVERLAY")
    damageText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    damageText:SetPoint("TOPLEFT", combatPanel, "TOPLEFT", 10, -45)
    damageText:SetText("Damage: 0")
    frame.damageText = damageText

    local healingText = combatPanel:CreateFontString(nil, "OVERLAY")
    healingText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    healingText:SetPoint("TOPRIGHT", combatPanel, "TOPRIGHT", -10, -45)
    healingText:SetText("Healing: 0")
    frame.healingText = healingText

    local timeText = combatPanel:CreateFontString(nil, "OVERLAY")
    timeText:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 12, "OUTLINE")
    timeText:SetPoint("BOTTOM", combatPanel, "BOTTOM", 0, 5)
    timeText:SetText("Duration: 0s")
    frame.timeText = timeText

    -- === SESSION HISTORY PANEL ===
    local historyPanel = CreateFrame("Frame", nil, frame)
    historyPanel:SetSize(400, 180)
    historyPanel:SetPoint("TOP", combatPanel, "BOTTOM", 0, -5)

    local historyBg = historyPanel:CreateTexture(nil, "BACKGROUND")
    historyBg:SetAllPoints(historyPanel)
    historyBg:SetColorTexture(0, 0, 0, 0.7)

    local historyBorder = historyPanel:CreateTexture(nil, "BORDER")
    historyBorder:SetAllPoints(historyPanel)
    historyBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
    historyBg:SetPoint("TOPLEFT", historyBorder, "TOPLEFT", 1, -1)
    historyBg:SetPoint("BOTTOMRIGHT", historyBorder, "BOTTOMRIGHT", -1, 1)

    local historyHeader = historyPanel:CreateFontString(nil, "OVERLAY")
    historyHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    historyHeader:SetPoint("TOP", historyPanel, "TOP", 0, -8)
    historyHeader:SetText("Session History")

    -- Column headers background
    local headerBg = historyPanel:CreateTexture(nil, "BORDER")
    headerBg:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 5, -25)
    headerBg:SetSize(390, 16)
    headerBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    local timeHeader = historyPanel:CreateFontString(nil, "OVERLAY")
    timeHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    timeHeader:SetPoint("LEFT", headerBg, "LEFT", 5, 0)
    timeHeader:SetWidth(40)
    timeHeader:SetJustifyH("LEFT")
    timeHeader:SetText("Time")
    timeHeader:SetTextColor(1, 1, 1, 1)

    local durationHeader = historyPanel:CreateFontString(nil, "OVERLAY")
    durationHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    durationHeader:SetPoint("LEFT", headerBg, "LEFT", 50, 0)
    durationHeader:SetWidth(30)
    durationHeader:SetJustifyH("LEFT")
    durationHeader:SetText("Dur")
    durationHeader:SetTextColor(1, 1, 1, 1)

    local avgDpsHeader = historyPanel:CreateFontString(nil, "OVERLAY")
    avgDpsHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    avgDpsHeader:SetPoint("LEFT", headerBg, "LEFT", 85, 0)
    avgDpsHeader:SetWidth(50)
    avgDpsHeader:SetJustifyH("LEFT")
    avgDpsHeader:SetText("DPS")
    avgDpsHeader:SetTextColor(1, 1, 1, 1)

    local avgHpsHeader = historyPanel:CreateFontString(nil, "OVERLAY")
    avgHpsHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    avgHpsHeader:SetPoint("LEFT", headerBg, "LEFT", 140, 0)
    avgHpsHeader:SetWidth(50)
    avgHpsHeader:SetJustifyH("LEFT")
    avgHpsHeader:SetText("HPS")
    avgHpsHeader:SetTextColor(1, 1, 1, 1)

    local qualityHeader = historyPanel:CreateFontString(nil, "OVERLAY")
    qualityHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    qualityHeader:SetPoint("LEFT", headerBg, "LEFT", 195, 0)
    qualityHeader:SetWidth(25)
    qualityHeader:SetJustifyH("CENTER")
    qualityHeader:SetText("Q")
    qualityHeader:SetTextColor(1, 1, 1, 1)

    local locationHeader = historyPanel:CreateFontString(nil, "OVERLAY")
    locationHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
    locationHeader:SetPoint("LEFT", headerBg, "LEFT", 225, 0)
    locationHeader:SetWidth(80)
    locationHeader:SetJustifyH("LEFT")
    locationHeader:SetText("Zone")
    locationHeader:SetTextColor(1, 1, 1, 1)

    -- Scrollable session list
    local scrollFrame = CreateFrame("ScrollFrame", nil, historyPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(360, 130)                              -- Reduced from 360 to fit
    scrollFrame:SetPoint("TOP", historyPanel, "TOP", -15, -45) -- Adjusted offset




    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(360, 140)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild

    -- Session rows
    frame.sessionRows = {}
    for i = 1, 20 do
        local row = CreateFrame("Button", nil, scrollChild)
        row:SetSize(360, 16)
        row:SetPoint("TOP", scrollChild, "TOP", 0, -(i - 1) * 16)

        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(row)
        if i % 2 == 0 then
            rowBg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
        else
            rowBg:SetColorTexture(0.05, 0.05, 0.05, 0.3)
        end

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints(row)
        highlight:SetColorTexture(0.3, 0.3, 0.3, 0.3)

        row.time = row:CreateFontString(nil, "OVERLAY")
        row.time:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        row.time:SetPoint("LEFT", row, "LEFT", 5, 0)
        row.time:SetWidth(40)
        row.time:SetJustifyH("LEFT")

        row.duration = row:CreateFontString(nil, "OVERLAY")
        row.duration:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        row.duration:SetPoint("LEFT", row, "LEFT", 50, 0)
        row.duration:SetWidth(30)
        row.duration:SetJustifyH("LEFT")

        row.avgDps = row:CreateFontString(nil, "OVERLAY")
        row.avgDps:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        row.avgDps:SetPoint("LEFT", row, "LEFT", 85, 0)
        row.avgDps:SetWidth(50)
        row.avgDps:SetJustifyH("LEFT")

        row.avgHps = row:CreateFontString(nil, "OVERLAY")
        row.avgHps:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        row.avgHps:SetPoint("LEFT", row, "LEFT", 140, 0)
        row.avgHps:SetWidth(50)
        row.avgHps:SetJustifyH("LEFT")

        row.quality = row:CreateFontString(nil, "OVERLAY")
        row.quality:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        row.quality:SetPoint("LEFT", row, "LEFT", 195, 0)
        row.quality:SetWidth(25)
        row.quality:SetJustifyH("CENTER")

        row.location = row:CreateFontString(nil, "OVERLAY")
        row.location:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 10, "OUTLINE")
        row.location:SetPoint("LEFT", row, "LEFT", 225, 0)
        row.location:SetWidth(80)
        row.location:SetJustifyH("LEFT")

        -- Delete button
        row.deleteBtn = CreateFrame("Button", nil, row)
        row.deleteBtn:SetSize(12, 12)
        row.deleteBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.deleteBtn:SetText("×")
        row.deleteBtn:SetNormalFontObject("GameFontNormalSmall")

        local btnText = row.deleteBtn:GetFontString()
        if btnText then
            btnText:SetTextColor(0.8, 0.3, 0.3, 1)
        end

        row.deleteBtn:SetScript("OnEnter", function(self)
            local text = self:GetFontString()
            if text then text:SetTextColor(1, 0.5, 0.5, 1) end
        end)
        row.deleteBtn:SetScript("OnLeave", function(self)
            local text = self:GetFontString()
            if text then text:SetTextColor(0.8, 0.3, 0.3, 1) end
        end)

        frame.sessionRows[i] = row
    end

    -- === VERTICAL CHART PANEL ===
    local chartPanel = CreateFrame("Frame", nil, frame)
    chartPanel:SetSize(400, 120)
    chartPanel:SetPoint("TOP", historyPanel, "BOTTOM", 0, -5)

    local chartBg = chartPanel:CreateTexture(nil, "BACKGROUND")
    chartBg:SetAllPoints(chartPanel)
    chartBg:SetColorTexture(0, 0, 0, 0.7)

    local chartBorder = chartPanel:CreateTexture(nil, "BORDER")
    chartBorder:SetAllPoints(chartPanel)
    chartBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
    chartBg:SetPoint("TOPLEFT", chartBorder, "TOPLEFT", 1, -1)
    chartBg:SetPoint("BOTTOMRIGHT", chartBorder, "BOTTOMRIGHT", -1, 1)

    local chartHeader = chartPanel:CreateFontString(nil, "OVERLAY")
    chartHeader:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 14, "OUTLINE")
    chartHeader:SetPoint("TOP", chartPanel, "TOP", 0, -8)
    chartHeader:SetText("Performance Trend")

    local chartArea = CreateFrame("Frame", nil, chartPanel)
    chartArea:SetSize(360, 80)
    chartArea:SetPoint("BOTTOM", chartPanel, "BOTTOM", 0, 8)

    local gridBg = chartArea:CreateTexture(nil, "BACKGROUND")
    gridBg:SetAllPoints(chartArea)
    gridBg:SetColorTexture(0.02, 0.02, 0.02, 0.6)

    -- Create 10 vertical bars
    frame.chartBars = {}
    for i = 1, 10 do
        local bar = {}
        local barWidth = 28
        local barSpacing = 8
        local xPos = (i - 1) * (barWidth + barSpacing) + 10

        bar.bgBar = chartArea:CreateTexture(nil, "BORDER")
        bar.bgBar:SetSize(barWidth, 80)
        bar.bgBar:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", xPos, 0)
        bar.bgBar:SetColorTexture(0.1, 0.1, 0.1, 0.8)

        bar.dpsBar = chartArea:CreateTexture(nil, "ARTWORK")
        bar.dpsBar:SetSize(barWidth / 2, 1)
        bar.dpsBar:SetPoint("BOTTOMLEFT", chartArea, "BOTTOMLEFT", xPos, 0)
        bar.dpsBar:SetColorTexture(0.8, 0.2, 0.2, 0.9)

        bar.hpsBar = chartArea:CreateTexture(nil, "ARTWORK")
        bar.hpsBar:SetSize(barWidth / 2, 1)
        bar.hpsBar:SetPoint("BOTTOMRIGHT", chartArea, "BOTTOMLEFT", xPos + barWidth, 0)
        bar.hpsBar:SetColorTexture(0.2, 0.8, 0.4, 0.9)

        frame.chartBars[i] = bar
    end

    -- === CONTROL PANEL ===
    local controlPanel = CreateFrame("Frame", nil, frame)
    controlPanel:SetSize(400, 50)
    controlPanel:SetPoint("TOP", chartPanel, "BOTTOM", 0, -5)

    local controlBg = controlPanel:CreateTexture(nil, "BACKGROUND")
    controlBg:SetAllPoints(controlPanel)
    controlBg:SetColorTexture(0, 0, 0, 0.7)

    local dpsBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    dpsBtn:SetSize(70, 22)
    dpsBtn:SetPoint("LEFT", controlPanel, "LEFT", 10, 8)
    dpsBtn:SetText("DPS")
    dpsBtn:SetScript("OnClick", function()
        if addon.DPSWindow then addon.DPSWindow:Toggle() end
    end)

    local hpsBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    hpsBtn:SetSize(70, 22)
    hpsBtn:SetPoint("LEFT", dpsBtn, "RIGHT", 5, 0)
    hpsBtn:SetText("HPS")
    hpsBtn:SetScript("OnClick", function()
        if addon.HPSWindow then addon.HPSWindow:Toggle() end
    end)

    local clearBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("LEFT", hpsBtn, "RIGHT", 5, 0)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        if addon.CombatTracker then
            addon.CombatTracker:ClearHistory()
            addon:UpdateMainWindow()
        end
    end)

    local debugBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    debugBtn:SetSize(70, 22)
    debugBtn:SetPoint("LEFT", clearBtn, "RIGHT", 5, 0)
    debugBtn:SetText("Debug")
    debugBtn:SetScript("OnClick", function()
        addon.DEBUG = not addon.DEBUG
        addon.db.debugMode = addon.DEBUG
        print(addonName .. " debug: " .. (addon.DEBUG and "ON" or "OFF"))
    end)

    local sessionCount = controlPanel:CreateFontString(nil, "OVERLAY")
    sessionCount:SetFont("Interface\\AddOns\\myui2\\SCP-SB.ttf", 11, "OUTLINE")
    sessionCount:SetPoint("BOTTOM", controlPanel, "BOTTOM", 0, 5)
    sessionCount:SetText("0 sessions")
    frame.sessionCount = sessionCount

    self.mainFrame = frame
    frame:SetScale(self.db.scale)
    frame:Hide()

    if not self.mainWindowUpdateTimer then
        self.mainWindowUpdateTimer = C_Timer.NewTicker(0.5, function()
            addon:UpdateMainWindow()
        end)
    end
end

function addon:UpdateMainWindow()
    if not self.mainFrame or not self.mainFrame:IsShown() then return end

    local inCombat = self.CombatTracker and self.CombatTracker:IsInCombat()

    if inCombat then
        self.mainFrame.combatHeader:SetText("Current Combat")
        self.mainFrame.combatHeader:SetTextColor(1, 0.2, 0.2)
    else
        self.mainFrame.combatHeader:SetText("Last Combat")
        self.mainFrame.combatHeader:SetTextColor(0.7, 0.7, 0.7)
    end

    if self.CombatTracker then
        local dps = self.CombatTracker:GetDPS()
        local hps = self.CombatTracker:GetHPS()
        local damage = self.CombatTracker:GetTotalDamage()
        local healing = self.CombatTracker:GetTotalHealing()
        local duration = self.CombatTracker:GetCombatTime()

        self.mainFrame.dpsText:SetText("DPS: " .. self.CombatTracker:FormatNumber(dps))
        self.mainFrame.hpsText:SetText("HPS: " .. self.CombatTracker:FormatNumber(hps))
        self.mainFrame.damageText:SetText("Damage: " .. self.CombatTracker:FormatNumber(damage))
        self.mainFrame.healingText:SetText("Healing: " .. self.CombatTracker:FormatNumber(healing))

        local durText = string.format("Duration: %dm %02ds", math.floor(duration / 60), duration % 60)
        self.mainFrame.timeText:SetText(durText)
    end

    self:UpdateSessionTable()
    self:UpdatePerformanceChart()
end

function addon:UpdateSessionTable()
    if not self.mainFrame or not self.mainFrame.sessionRows then return end

    local sessions = {}
    if self.CombatTracker then
        sessions = self.CombatTracker:GetSessionHistory()
    end

    if self.mainFrame.sessionCount then
        self.mainFrame.sessionCount:SetText(string.format("%d sessions", #sessions))
    end

    local scrollHeight = math.max(140, #sessions * 16)
    self.mainFrame.scrollChild:SetHeight(scrollHeight)

    for i = 1, 20 do
        local row = self.mainFrame.sessionRows[i]
        if i <= #sessions then
            row:Show()
            local session = sessions[i]

            -- Convert GetTime() to real time for display
            local realTime = time() + (session.startTime - GetTime())
            row.time:SetText(date("%H:%M", realTime))

            local durStr = session.duration >= 60 and
                string.format("%dm", math.floor(session.duration / 60)) or
                string.format("%ds", session.duration)
            row.duration:SetText(durStr)

            row.avgDps:SetText(self.CombatTracker:FormatNumber(session.avgDPS))
            row.avgHps:SetText(self.CombatTracker:FormatNumber(session.avgHPS))

            local qualityText = tostring(session.qualityScore)
            if session.userMarked == "representative" then
                qualityText = "★" .. qualityText
                row.quality:SetTextColor(1, 1, 0)
            elseif session.qualityScore >= 80 then
                row.quality:SetTextColor(0, 1, 0)
            elseif session.qualityScore >= 60 then
                row.quality:SetTextColor(1, 1, 0)
            else
                row.quality:SetTextColor(1, 0.5, 0.5)
            end
            row.quality:SetText(qualityText)

            local location = session.location or "Unknown"
            if string.len(location) > 12 then
                location = string.sub(location, 1, 12) .. "..."
            end
            row.location:SetText(location)

            row.deleteBtn:SetScript("OnClick", function()
                if addon.CombatTracker then
                    addon.CombatTracker:DeleteSession(session.sessionId)
                    addon:UpdateMainWindow()
                end
            end)
        else
            row:Hide()
        end
    end
end

function addon:UpdatePerformanceChart()
    if not self.mainFrame or not self.mainFrame.chartBars then return end

    local sessions = {}
    if self.CombatTracker then
        sessions = self.CombatTracker:GetSessionHistory()
    end

    local maxDPS, maxHPS = 0, 0
    for i = 1, math.min(10, #sessions) do
        local session = sessions[i]
        maxDPS = math.max(maxDPS, session.avgDPS or 0)
        maxHPS = math.max(maxHPS, session.avgHPS or 0)
    end

    for i = 1, 10 do
        local bar = self.mainFrame.chartBars[i]
        if i <= #sessions then
            local session = sessions[i]

            local dpsHeight = maxDPS > 0 and math.max(2, (session.avgDPS / maxDPS) * 80) or 2
            local hpsHeight = maxHPS > 0 and math.max(2, (session.avgHPS / maxHPS) * 80) or 2

            bar.dpsBar:SetHeight(dpsHeight)
            bar.hpsBar:SetHeight(hpsHeight)

            local alpha = math.max(0.4, session.qualityScore / 100)
            bar.dpsBar:SetAlpha(alpha)
            bar.hpsBar:SetAlpha(alpha)
        else
            bar.dpsBar:SetHeight(1)
            bar.hpsBar:SetHeight(1)
            bar.dpsBar:SetAlpha(0.2)
            bar.hpsBar:SetAlpha(0.2)
        end
    end
end

-- Main slash command handler
SLASH_MYUI1 = "/myui"
function SlashCmdList.MYUI(msg, editBox)
    local command = string.lower(msg)

    if command == "show" then
        if not addon.mainFrame then
            addon:CreateMainFrame()
        end
        addon.mainFrame:Show()
        addon.db.showMainWindow = true
        print("Main window shown")
    elseif command == "hide" then
        if addon.mainFrame then
            addon.mainFrame:Hide()
            addon.db.showMainWindow = false
            print("Main window hidden")
        end
    elseif command == "toggle" or command == "" then
        addon:ToggleMainWindow()
    elseif command == "dps" then
        if addon.DPSWindow then
            addon.DPSWindow:Toggle()
        end
    elseif command == "hps" then
        if addon.HPSWindow then
            addon.HPSWindow:Toggle()
        end
    elseif command == "debug" then
        addon.DEBUG = not addon.DEBUG
        addon.db.debugMode = addon.DEBUG
        print(addonName .. " debug mode: " .. (addon.DEBUG and "ON" or "OFF"))
        addon:UpdateStatusDisplay()
    elseif command == "cstart" then
        if not addon.CombatTracker then
            print("CombatTracker not loaded!")
            return
        end
        addon.CombatTracker:StartCombat()
        print("Forced combat start")
        addon:UpdateStatusDisplay()
    elseif command == "cend" then
        if not addon.CombatTracker then
            print("CombatTracker not loaded!")
            return
        end
        addon.CombatTracker:EndCombat()
        print("Forced combat end")
        addon:UpdateStatusDisplay()
    elseif command:match("^hpsmax%s+(%d+)$") then
        local maxValue = tonumber(command:match("^hpsmax%s+(%d+)$"))
        if addon.hpsPixelMeter then
            addon.hpsPixelMeter:SetMaxValue(maxValue)
        else
            print("HPS meter not active")
        end
    elseif command:match("^dpsmax%s+(%d+)$") then
        local maxValue = tonumber(command:match("^dpsmax%s+(%d+)$"))
        if addon.dpsPixelMeter then
            addon.dpsPixelMeter:SetMaxValue(maxValue)
        else
            print("DPS meter not active")
        end
    elseif command == "hpsreset" then
        if addon.hpsPixelMeter then
            addon.hpsPixelMeter:ResetMaxValue()
        else
            print("HPS meter not active")
        end
    elseif command == "dpsreset" then
        if addon.dpsPixelMeter then
            addon.dpsPixelMeter:ResetMaxValue()
        else
            print("DPS meter not active")
        end
    elseif command == "meterinfo" then
        print("=== METER DEBUG INFO ===")
        if addon.hpsPixelMeter then
            local info = addon.hpsPixelMeter:GetDebugInfo()
            print(string.format("HPS: %s/%s (%s) [%d/%d pixels] %s",
                addon.CombatTracker:FormatNumber(info.currentValue),
                addon.CombatTracker:FormatNumber(info.currentMax),
                string.format("%.1f%%", info.percent),
                info.activeCols, info.totalCols,
                info.isManual and "(manual)" or "(auto)"
            ))
        else
            print("HPS meter: Not active")
        end

        if addon.dpsPixelMeter then
            local info = addon.dpsPixelMeter:GetDebugInfo()
            print(string.format("DPS: %s/%s (%s) [%d/%d pixels] %s",
                addon.CombatTracker:FormatNumber(info.currentValue),
                addon.CombatTracker:FormatNumber(info.currentMax),
                string.format("%.1f%%", info.percent),
                info.activeCols, info.totalCols,
                info.isManual and "(manual)" or "(auto)"
            ))
        else
            print("DPS meter: Not active")
        end
        print("=== END METER INFO ===")
    elseif command == "resetmeters" then
        if addon.hpsPixelMeter then
            addon.hpsPixelMeter:ResetMaxValue()
        end
        if addon.dpsPixelMeter then
            addon.dpsPixelMeter:ResetMaxValue()
        end
        print("All meter max values reset to defaults")
    elseif command == "resetcombat" then
        print("=== RESETTING COMBAT DATA ===")
        if addon.CombatTracker then
            addon.CombatTracker:ResetDisplayStats()
            print("Combat stats reset")
        end

        -- Reset meter scaling
        if addon.hpsPixelMeter then
            addon.hpsPixelMeter:ResetMaxValue()
        end
        if addon.dpsPixelMeter then
            addon.dpsPixelMeter:ResetMaxValue()
        end
        print("Meter scaling reset to defaults")
        print("=== RESET COMPLETE ===")
    elseif command == "debugpeaks" then
        if addon.CombatTracker then
            addon.CombatTracker:DebugPeakTracking()
        else
            print("CombatTracker not loaded")
        end
    elseif command == "debugdps" then
        if addon.CombatTracker then
            addon.CombatTracker:DebugDPSCalculation()
        else
            print("CombatTracker not loaded")
        end
    elseif command == "comparerolling" then
        if addon.CombatTracker then
            addon.CombatTracker:CompareRollingVsOverall()
        else
            print("CombatTracker not loaded")
        end
    elseif command == "checktiming" then
        if addon.CombatTracker then
            addon.CombatTracker:CheckUpdateTiming()
        else
            print("CombatTracker not loaded")
        end
    elseif command == "sessions" then
        if addon.CombatTracker then
            addon.CombatTracker:DebugSessionHistory()
        else
            print("CombatTracker not loaded")
        end
    elseif command == "testsession" then
        if addon.CombatTracker then
            addon.CombatTracker:TestSessionCreation()
        else
            print("CombatTracker not loaded")
        end
    elseif command == "clearsessions" then
        if addon.CombatTracker then
            addon.CombatTracker:ClearHistory()
        else
            print("CombatTracker not loaded")
        end
    elseif command == "timetest" then
        local sessions = {}
        if addon.CombatTracker then
            sessions = addon.CombatTracker:GetSessionHistory()
        end
        if #sessions > 0 then
            local s = sessions[1]
            print("Session startTime:", s.startTime)
            print("Formatted session:", date("%H:%M", s.startTime))
            print("Current GetTime():", GetTime())
            print("Current time():", time())
            print("Current formatted:", date("%H:%M"))
        else
            print("No sessions found")
        end
    else
        print("Usage: /myui [TODO]")
    end
end
