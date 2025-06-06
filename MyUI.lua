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
addon.VERSION = "feature-main-window-update-6f0c6a7"
addon.BUILD_DATE = "2025-06-06-11:35"

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

-- Enable function
function addon:OnEnable()
    if self.db.enabled then
        -- Create main frame but don't show it yet
        self:CreateMainFrame()
        -- self:CreateMinimapButton()

        -- Only show main window if it was explicitly shown before
        if self.db.showMainWindow then
            self.mainFrame:Show()
        end

        -- Restore DPS window visibility
        if self.db.showDPSWindow and self.DPSWindow then
            self.DPSWindow:Show()
        end

        -- Restore HPS window visibility
        if self.db.showHPSWindow and self.HPSWindow then
            self.HPSWindow:Show()
        end

        print(addonName .. " is now active!")
    end
end

-- Disable function
function addon:OnDisable()
    -- Save frame position before logout
    if self.mainFrame and self.mainFrame:IsShown() then
        local point, relativeTo, relativePoint, xOfs, yOfs = self.mainFrame:GetPoint()
        self.db.framePosition = {
            point = point,
            relativePoint = relativePoint,
            xOffset = xOfs,
            yOffset = yOfs
        }
    end

    -- Save main window visibility state
    if self.mainFrame then
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

-- Create main addon frame with session history and combat summary
function addon:CreateMainFrame()
    if self.mainFrame then return end

    local frame = CreateFrame("Frame", addonName .. "MainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(400, 350) -- Larger to accommodate session table

    -- Restore saved position or use default
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
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText("MyUI v" .. addon.VERSION)

    -- === CURRENT COMBAT PANEL ===
    local combatPanel = CreateFrame("Frame", nil, frame)
    combatPanel:SetSize(380, 80)
    combatPanel:SetPoint("TOP", frame, "TOP", 0, -30)

    -- Combat panel background
    local combatBg = combatPanel:CreateTexture(nil, "BACKGROUND")
    combatBg:SetAllPoints(combatPanel)
    combatBg:SetColorTexture(0.1, 0.1, 0.3, 0.3)

    -- Combat status header
    local combatHeader = combatPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    combatHeader:SetPoint("TOP", combatPanel, "TOP", 0, -8)
    combatHeader:SetText("Current Combat")
    frame.combatHeader = combatHeader

    -- Combat stats display (two columns)
    local dpsText = combatPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dpsText:SetPoint("TOPLEFT", combatPanel, "TOPLEFT", 10, -25)
    dpsText:SetText("DPS: 0")
    frame.dpsText = dpsText

    local hpsText = combatPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpsText:SetPoint("TOPRIGHT", combatPanel, "TOPRIGHT", -10, -25)
    hpsText:SetText("HPS: 0")
    frame.hpsText = hpsText

    local damageText = combatPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    damageText:SetPoint("TOPLEFT", combatPanel, "TOPLEFT", 10, -45)
    damageText:SetText("Damage: 0")
    frame.damageText = damageText

    local healingText = combatPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    healingText:SetPoint("TOPRIGHT", combatPanel, "TOPRIGHT", -10, -45)
    healingText:SetText("Healing: 0")
    frame.healingText = healingText

    local timeText = combatPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("BOTTOM", combatPanel, "BOTTOM", 0, 5)
    timeText:SetText("Duration: 0s")
    frame.timeText = timeText

    -- === SESSION HISTORY PANEL ===
    local historyPanel = CreateFrame("Frame", nil, frame)
    historyPanel:SetSize(380, 180)
    historyPanel:SetPoint("TOP", combatPanel, "BOTTOM", 0, -10)

    -- History panel background
    local historyBg = historyPanel:CreateTexture(nil, "BACKGROUND")
    historyBg:SetAllPoints(historyPanel)
    historyBg:SetColorTexture(0.1, 0.3, 0.1, 0.3)

    -- History header
    local historyHeader = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    historyHeader:SetPoint("TOP", historyPanel, "TOP", 0, -8)
    historyHeader:SetText("Recent Sessions")

    -- Session table headers
    local headerBg = historyPanel:CreateTexture(nil, "BORDER")
    headerBg:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 5, -25)
    headerBg:SetSize(370, 20)
    headerBg:SetColorTexture(0, 0, 0, 0.5)

    local timeHeader = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeHeader:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 10, -30)
    timeHeader:SetText("Time")

    local durationHeader = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durationHeader:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 70, -30)
    durationHeader:SetText("Duration")

    local avgDpsHeader = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    avgDpsHeader:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 140, -30)
    avgDpsHeader:SetText("Avg DPS")

    local avgHpsHeader = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    avgHpsHeader:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 210, -30)
    avgHpsHeader:SetText("Avg HPS")

    local qualityHeader = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qualityHeader:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 280, -30)
    qualityHeader:SetText("Quality")

    local locationHeader = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    locationHeader:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 330, -30)
    locationHeader:SetText("Zone")

    -- Session rows (create 7 rows for recent sessions)
    frame.sessionRows = {}
    for i = 1, 7 do
        local row = {}
        local yOffset = -45 - (i - 1) * 18

        -- Row background (alternating colors)
        row.bg = historyPanel:CreateTexture(nil, "BORDER")
        row.bg:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 5, yOffset + 8)
        row.bg:SetSize(370, 16)
        if i % 2 == 0 then
            row.bg:SetColorTexture(0, 0, 0, 0.2)
        else
            row.bg:SetColorTexture(0, 0, 0, 0.1)
        end

        row.time = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.time:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 10, yOffset)
        row.time:SetText("")

        row.duration = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.duration:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 70, yOffset)
        row.duration:SetText("")

        row.avgDps = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.avgDps:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 140, yOffset)
        row.avgDps:SetText("")

        row.avgHps = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.avgHps:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 210, yOffset)
        row.avgHps:SetText("")

        row.quality = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.quality:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 285, yOffset)
        row.quality:SetText("")

        row.location = historyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.location:SetPoint("TOPLEFT", historyPanel, "TOPLEFT", 330, yOffset)
        row.location:SetText("")

        frame.sessionRows[i] = row
    end

    -- === CONTROL PANEL ===
    local controlPanel = CreateFrame("Frame", nil, frame)
    controlPanel:SetSize(380, 60)
    controlPanel:SetPoint("TOP", historyPanel, "BOTTOM", 0, -5)

    -- Control panel background
    local controlBg = controlPanel:CreateTexture(nil, "BACKGROUND")
    controlBg:SetAllPoints(controlPanel)
    controlBg:SetColorTexture(0.3, 0.1, 0.1, 0.3)

    -- Essential controls (compact layout)
    local dpsBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    dpsBtn:SetSize(80, 25)
    dpsBtn:SetPoint("TOPLEFT", controlPanel, "TOPLEFT", 10, -8)
    dpsBtn:SetText("DPS")
    dpsBtn:SetScript("OnClick", function()
        if addon.DPSWindow then
            addon.DPSWindow:Toggle()
        end
    end)

    local hpsBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    hpsBtn:SetSize(80, 25)
    hpsBtn:SetPoint("TOPLEFT", controlPanel, "TOPLEFT", 100, -8)
    hpsBtn:SetText("HPS")
    hpsBtn:SetScript("OnClick", function()
        if addon.HPSWindow then
            addon.HPSWindow:Toggle()
        end
    end)

    local clearBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    clearBtn:SetSize(80, 25)
    clearBtn:SetPoint("TOPLEFT", controlPanel, "TOPLEFT", 190, -8)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        if addon.CombatTracker then
            addon.CombatTracker:ClearHistory()
            addon:UpdateMainWindow()
        end
    end)

    local debugBtn = CreateFrame("Button", nil, controlPanel, "GameMenuButtonTemplate")
    debugBtn:SetSize(80, 25)
    debugBtn:SetPoint("TOPLEFT", controlPanel, "TOPLEFT", 280, -8)
    debugBtn:SetText("Debug")
    debugBtn:SetScript("OnClick", function()
        addon.DEBUG = not addon.DEBUG
        addon.db.debugMode = addon.DEBUG
        print(addonName .. " debug: " .. (addon.DEBUG and "ON" or "OFF"))
    end)

    -- Session count display
    local sessionCount = controlPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sessionCount:SetPoint("BOTTOM", controlPanel, "BOTTOM", 0, 8)
    sessionCount:SetText("0 sessions stored")
    frame.sessionCount = sessionCount

    -- Close button functionality
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
        addon.db.showMainWindow = false
    end)

    -- ESC key support
    table.insert(UISpecialFrames, frame:GetName())
    local originalHide = frame.Hide
    frame.Hide = function(frame)
        addon.db.showMainWindow = false
        originalHide(frame)
    end

    self.mainFrame = frame
    frame:SetScale(self.db.scale)
    frame:Hide()

    -- Start update timer for real-time data
    if not self.mainWindowUpdateTimer then
        self.mainWindowUpdateTimer = C_Timer.NewTicker(0.5, function()
            addon:UpdateMainWindow()
        end)
    end
end

-- Update main window displays with current data
function addon:UpdateMainWindow()
    if not self.mainFrame or not self.mainFrame:IsShown() then
        return
    end

    local inCombat = self.CombatTracker and self.CombatTracker:IsInCombat()

    -- Update combat status header
    if inCombat then
        self.mainFrame.combatHeader:SetText("Current Combat")
        self.mainFrame.combatHeader:SetTextColor(1, 0.2, 0.2) -- Red
    else
        self.mainFrame.combatHeader:SetText("Last Combat")
        self.mainFrame.combatHeader:SetTextColor(0.7, 0.7, 0.7) -- Gray
    end

    -- Update current/last combat stats
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

    -- Update session history table
    self:UpdateSessionTable()
end

-- Update the session history table
function addon:UpdateSessionTable()
    if not self.mainFrame or not self.mainFrame.sessionRows then
        return
    end

    local sessions = {}
    if self.CombatTracker then
        sessions = self.CombatTracker:GetSessionHistory()
    end

    -- Update session count
    if self.mainFrame.sessionCount then
        self.mainFrame.sessionCount:SetText(string.format("%d sessions stored", #sessions))
    end

    -- Clear all rows first
    for i = 1, 7 do
        local row = self.mainFrame.sessionRows[i]
        row.time:SetText("")
        row.duration:SetText("")
        row.avgDps:SetText("")
        row.avgHps:SetText("")
        row.quality:SetText("")
        row.location:SetText("")
    end

    -- Fill rows with session data (most recent first)
    for i = 1, math.min(7, #sessions) do
        local session = sessions[i]
        local row = self.mainFrame.sessionRows[i]

        -- Format time (HH:MM)
        local timeStr = date("%H:%M", session.startTime)
        row.time:SetText(timeStr)

        -- Format duration (Xm Ys or Xs)
        local durStr
        if session.duration >= 60 then
            durStr = string.format("%dm %ds", math.floor(session.duration / 60), session.duration % 60)
        else
            durStr = string.format("%ds", session.duration)
        end
        row.duration:SetText(durStr)

        -- Format DPS/HPS
        row.avgDps:SetText(self.CombatTracker:FormatNumber(session.avgDPS))
        row.avgHps:SetText(self.CombatTracker:FormatNumber(session.avgHPS))

        -- Quality score with color coding
        local qualityText = tostring(session.qualityScore)
        if session.userMarked == "representative" then
            qualityText = "★" .. qualityText
            row.quality:SetTextColor(1, 1, 0)     -- Gold
        elseif session.qualityScore >= 80 then
            row.quality:SetTextColor(0, 1, 0)     -- Green
        elseif session.qualityScore >= 60 then
            row.quality:SetTextColor(1, 1, 0)     -- Yellow
        else
            row.quality:SetTextColor(1, 0.5, 0.5) -- Light red
        end
        row.quality:SetText(qualityText)

        -- Location (truncated)
        local location = session.location or "Unknown"
        if string.len(location) > 8 then
            location = string.sub(location, 1, 8) .. "..."
        end
        row.location:SetText(location)
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
    else
        print("Usage: /myui [TODO]")
    end
end
