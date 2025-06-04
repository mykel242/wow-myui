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
addon.VERSION = "main-6f41118"
addon.BUILD_DATE = "2025-06-04-17:22"

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

-- Create main addon frame
function addon:CreateMainFrame()
    if self.mainFrame then return end

    local frame = CreateFrame("Frame", addonName .. "MainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 250)

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
        -- Save position immediately when dragging stops
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
    frame.title:SetText("My UI v" .. addon.VERSION)

    -- Status display
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOP", frame, "TOP", 0, -40)
    statusText:SetJustifyH("CENTER")
    frame.statusText = statusText

    -- DPS Window Toggle Button
    local dpsBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    dpsBtn:SetSize(100, 30)
    dpsBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -80)
    dpsBtn:SetText("Toggle DPS")
    dpsBtn:SetScript("OnClick", function()
        if addon.DPSWindow then
            addon.DPSWindow:Toggle()
        end
    end)

    -- HPS Window Toggle Button
    local hpsBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    hpsBtn:SetSize(100, 30)
    hpsBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -80)
    hpsBtn:SetText("Toggle HPS")
    hpsBtn:SetScript("OnClick", function()
        if addon.HPSWindow then
            addon.HPSWindow:Toggle()
        end
    end)

    -- Debug Toggle Button
    local debugBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    debugBtn:SetSize(100, 30)
    debugBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -120)
    debugBtn:SetText("Toggle Debug")
    debugBtn:SetScript("OnClick", function()
        addon.DEBUG = not addon.DEBUG
        addon.db.debugMode = addon.DEBUG
        print(addonName .. " debug mode: " .. (addon.DEBUG and "ON" or "OFF"))
        addon:UpdateStatusDisplay()
    end)

    -- Start Combat Button
    local startCombatBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    startCombatBtn:SetSize(100, 30)
    startCombatBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -120)
    startCombatBtn:SetText("Start Combat")
    startCombatBtn:SetScript("OnClick", function()
        if addon.CombatTracker then
            addon.CombatTracker:StartCombat()
            print("Forced combat start")
            addon:UpdateStatusDisplay()
        end
    end)

    -- End Combat Button
    local endCombatBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    endCombatBtn:SetSize(100, 30)
    endCombatBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -160)
    endCombatBtn:SetText("End Combat")
    endCombatBtn:SetScript("OnClick", function()
        if addon.CombatTracker then
            addon.CombatTracker:EndCombat()
            print("Forced combat end")
            addon:UpdateStatusDisplay()
        end
    end)

    -- Close button functionality - SAVE STATE WHEN CLOSED
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
        addon.db.showMainWindow = false
        print("Main window hidden")
    end)

    -- Make ESC key close the window and save state
    table.insert(UISpecialFrames, frame:GetName())

    -- Override Hide function to save state when closed by ESC
    local originalHide = frame.Hide
    frame.Hide = function(frame)
        addon.db.showMainWindow = false
        originalHide(frame)
    end

    self.mainFrame = frame

    -- Apply saved scale
    frame:SetScale(self.db.scale)

    -- Start hidden unless explicitly saved as shown
    frame:Hide()

    -- Initial status update
    self:UpdateStatusDisplay()

    -- Update status periodically
    C_Timer.NewTicker(1.0, function()
        addon:UpdateStatusDisplay()
    end)
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
    else
        print("Usage: /myui [TODO]")
    end
end
