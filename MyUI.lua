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
addon.VERSION = "bugfix-absorbs-f51a66b"
addon.BUILD_DATE = "2025-05-30-18:49"

-- Debug flag
addon.DEBUG = true

-- Addon variables
addon.db = {}
addon.defaults = {
    enabled = true,
    showMinimap = true,
    scale = 1.0,
    framePosition = nil,
    subWindowPosition = nil,
    showSubWindow = false,
    dpsWindowPosition = nil,
    showDPSWindow = false,
    hpsWindowPosition = nil,
    showHPSWindow = false
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

    -- Initialize all modules
    if self.CombatTracker then
        self.CombatTracker:Initialize()
    end
    if self.SubWindow then
        self.SubWindow:Initialize()
    end
    if self.DPSWindow then
        self.DPSWindow:Initialize()
    end
    if self.HPSWindow then
        self.HPSWindow:Initialize()
    end

    print(addonName .. " loaded successfully!")
end

-- Enable function
function addon:OnEnable()
    if self.db.enabled then
        self:CreateMainFrame()

        -- Restore DPS window visibility
        if self.db.showDPSWindow and self.DPSWindow then
            self.DPSWindow:Show()
        end

        -- Restore HPS window visibility
        if self.db.showHPSWindow and self.HPSWindow then
            self.HPSWindow:Show()
        end

        -- Restore SubWindow visibility
        if self.db.showSubWindow and self.SubWindow then
            self.SubWindow:Show()
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

    -- Save visibility states for all windows
    if self.DPSWindow and self.DPSWindow.frame then
        self.db.showDPSWindow = self.DPSWindow.frame:IsShown()
    end

    if self.HPSWindow and self.HPSWindow.frame then
        self.db.showHPSWindow = self.HPSWindow.frame:IsShown()
    end

    if self.SubWindow and self.SubWindow.frame then
        self.db.showSubWindow = self.SubWindow.frame:IsShown()
    end
end

-- Create main addon frame
function addon:CreateMainFrame()
    if self.mainFrame then return end

    local frame = CreateFrame("Frame", addonName .. "MainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(300, 200)

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
    frame.title:SetText("My UI v" .. addon.VERSION) -- Show version in title

    -- Example content
    local content = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    content:SetPoint("CENTER", frame, "CENTER", 0, 20)
    content:SetText("Hello World (of Warcraft)")

    -- DPS Window Toggle Button
    local dpsBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    dpsBtn:SetSize(80, 25)
    dpsBtn:SetPoint("LEFT", frame, "LEFT", 20, -20)
    dpsBtn:SetText("DPS Meter")
    dpsBtn:SetScript("OnClick", function()
        if addon.DPSWindow then
            addon.DPSWindow:Toggle()
        end
    end)

    -- HPS Window Toggle Button
    local hpsBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    hpsBtn:SetSize(80, 25)
    hpsBtn:SetPoint("RIGHT", frame, "RIGHT", -20, -20)
    hpsBtn:SetText("HPS Meter")
    hpsBtn:SetScript("OnClick", function()
        if addon.HPSWindow then
            addon.HPSWindow:Toggle()
        end
    end)

    -- Sub Window Toggle Button (moved down)
    local subWindowBtn = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    subWindowBtn:SetSize(120, 25)
    subWindowBtn:SetPoint("CENTER", frame, "CENTER", 0, -50)
    subWindowBtn:SetText("Toggle Sub Window")
    subWindowBtn:SetScript("OnClick", function()
        if addon.SubWindow then
            addon.SubWindow:Toggle()
        end
    end)

    -- Close button functionality
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    self.mainFrame = frame

    -- Apply saved scale
    frame:SetScale(self.db.scale)
end

-- Main slash command handler
SLASH_MYUI1 = "/myui"
SLASH_MYUI2 = "/mui"

function SlashCmdList.MYUI(msg, editBox)
    local command = string.lower(msg)

    if command == "show" then
        if addon.mainFrame then
            addon.mainFrame:Show()
        else
            addon:CreateMainFrame()
        end
    elseif command == "hide" then
        if addon.mainFrame then
            addon.mainFrame:Hide()
        end
    elseif command == "toggle" then
        if addon.mainFrame then
            if addon.mainFrame:IsShown() then
                addon.mainFrame:Hide()
            else
                addon.mainFrame:Show()
            end
        else
            addon:CreateMainFrame()
        end
    elseif command == "sub" or command == "subwindow" then
        if addon.SubWindow then
            addon.SubWindow:Toggle()
        end
    elseif command == "dps" then
        if addon.DPSWindow then
            addon.DPSWindow:Toggle()
        end
    elseif command == "hps" then
        if addon.HPSWindow then
            addon.HPSWindow:Toggle()
        end
    elseif command == "config" then
        print("Configuration options:")
        print("/myui show - Show the main frame")
        print("/myui hide - Hide the main frame")
        print("/myui toggle - Toggle frame visibility")
        print("/myui sub - Toggle sub window")
        print("/myui dps - Toggle DPS meter")
        print("/myui hps - Toggle HPS meter")
        print("/myui reload - Reload UI")
        print("/myui reset - Reset all data")
        print("/myui debug - Toggle debug mode")
        print("/myui status - Show addon status")
    else
        print("Usage: /myui [show | hide | toggle | sub | dps | hps | reload | reset | debug | status | config]")
    end
end

-- Reload command
SLASH_MYUIRELOAD1 = "/muireload"
SLASH_MYUIRELOAD2 = "/muir"

function SlashCmdList.MYUIRELOAD(msg, editBox)
    print("Reloading " .. addonName .. "...")
    ReloadUI()
end

-- Reset all saved data
SLASH_MYUIRESET1 = "/muireset"
function SlashCmdList.MYUIRESET(msg, editBox)
    MyUIDB = {}
    addon.db = {}
    print(addonName .. " data reset. Use /reload to reinitialize.")
end

-- Toggle debug mode
SLASH_MYUIDEBUG1 = "/muidebug"
function SlashCmdList.MYUIDEBUG(msg, editBox)
    addon.DEBUG = not addon.DEBUG
    print(addonName .. " debug mode: " .. (addon.DEBUG and "ON" or "OFF"))
end

-- Force combat start/end (for testing)
SLASH_MYUICOMBAT1 = "/muicombat"
function SlashCmdList.MYUICOMBAT(msg, editBox)
    if not addon.CombatTracker then
        print("CombatTracker not loaded!")
        return
    end

    if msg == "start" then
        addon.CombatTracker:StartCombat()
        print("Forced combat start")
    elseif msg == "end" then
        addon.CombatTracker:EndCombat()
        print("Forced combat end")
    else
        print("Usage: /muicombat start|end")
    end
end

-- Quick window position reset
SLASH_MYUIPOS1 = "/muipos"
function SlashCmdList.MYUIPOS(msg, editBox)
    -- Reset window positions to defaults
    addon.db.dpsWindowPosition = nil
    addon.db.hpsWindowPosition = nil
    addon.db.framePosition = nil
    addon.db.subWindowPosition = nil
    print("Window positions reset. Use /reload to apply.")
end

-- Quick status check command
SLASH_MYUISTATUS1 = "/muistatus"
function SlashCmdList.MYUISTATUS(msg, editBox)
    print("=== " .. addonName .. " Status ===")
    print("Version: " .. addon.VERSION)
    print("Build: " .. addon.BUILD_DATE)
    print("Debug Mode: " .. (addon.DEBUG and "ON" or "OFF"))
    print("Combat Tracker: " .. (addon.CombatTracker and "Loaded" or "Missing"))
    print("DPS Window: " .. (addon.DPSWindow and "Loaded" or "Missing"))
    print("HPS Window: " .. (addon.HPSWindow and "Loaded" or "Missing"))
    print("Sub Window: " .. (addon.SubWindow and "Loaded" or "Missing"))
    if addon.CombatTracker then
        print("In Combat: " .. tostring(addon.CombatTracker:IsInCombat()))

        -- Show combat debug info
        local debugInfo = addon.CombatTracker:GetDebugInfo()
        if debugInfo then
            print("Current DPS: " .. addon.CombatTracker:FormatNumber(debugInfo.dps))
            print("Current HPS: " .. addon.CombatTracker:FormatNumber(debugInfo.hps))
            print("Total Damage: " .. addon.CombatTracker:FormatNumber(debugInfo.damage))
            print("Total Healing: " .. addon.CombatTracker:FormatNumber(debugInfo.healing))
            print("Total Absorb: " .. addon.CombatTracker:FormatNumber(debugInfo.absorb))
            if debugInfo.counters then
                print("Event Counters:")
                print("  Total: " .. debugInfo.counters.totalEvents)
                print("  Damage: " .. debugInfo.counters.damageEvents)
                print("  Healing: " .. debugInfo.counters.healingEvents)
                print("  Absorb: " .. debugInfo.counters.absorbEvents)
            end
        end
    end
    print("Main Frame: " .. (addon.mainFrame and "Created" or "Not Created"))
    if addon.mainFrame then
        print("Main Frame Visible: " .. tostring(addon.mainFrame:IsShown()))
    end
end

-- Combat debug command
SLASH_MYUICOMBATDEBUG1 = "/muicombatdebug"
function SlashCmdList.MYUICOMBATDEBUG(msg, editBox)
    if not addon.CombatTracker then
        print("CombatTracker not loaded!")
        return
    end

    local debugInfo = addon.CombatTracker:GetDebugInfo()
    print("=== Combat Debug Info ===")
    addon:DumpTable(debugInfo)
end

-- Absorb testing command
SLASH_MYUIABSORBTEST1 = "/muiabsorb"
function SlashCmdList.MYUIABSORBTEST(msg, editBox)
    print("=== Testing Absorb Detection ===")
    print("1. Cast an absorb spell (Power Word: Shield, etc.)")
    print("2. Watch chat for absorb events")
    print("3. Use /muistatus to see absorb counter")
    print("4. Enable debug mode with /muidebug if not already on")
    print("================================")

    -- Also show current absorb status
    if addon.CombatTracker then
        local debugInfo = addon.CombatTracker:GetDebugInfo()
        if debugInfo then
            print("Current absorb total: " .. addon.CombatTracker:FormatNumber(debugInfo.absorb))
            print("Absorb events detected: " .. (debugInfo.counters.absorbEvents or 0))
        end
    end
end

-- Clear absorb debug logs
SLASH_MYUIABSORBCLEAR1 = "/muiabsorbclear"
function SlashCmdList.MYUIABSORBCLEAR(msg, editBox)
    if addon.CombatTracker then
        -- Reset just the absorb counter for testing
        local debugInfo = addon.CombatTracker:GetDebugInfo()
        if debugInfo and debugInfo.counters then
            debugInfo.counters.absorbEvents = 0
        end
        print("Absorb event counter reset")
    end
end

-- Debug display values command (one-time check, no spam)
SLASH_MYUIDISPLAYCHECK1 = "/muidisplay"
function SlashCmdList.MYUIDISPLAYCHECK(msg, editBox)
    if not addon.CombatTracker then
        print("CombatTracker not loaded!")
        return
    end

    print("=== Display Values Check ===")
    print("In Combat: " .. tostring(addon.CombatTracker:IsInCombat()))

    local absorbValue = addon.CombatTracker:GetTotalAbsorb()
    local overhealValue = addon.CombatTracker:GetTotalOverheal()
    local totalHealing = addon.CombatTracker:GetTotalHealing()

    print("Raw Values:")
    print("  Absorb: " .. absorbValue)
    print("  Overheal: " .. overhealValue)
    print("  Total Healing: " .. totalHealing)

    print("Formatted Values:")
    print("  Absorb: " .. addon.CombatTracker:FormatNumber(absorbValue))
    print("  Overheal: " .. addon.CombatTracker:FormatNumber(overhealValue))
    print("  Total Healing: " .. addon.CombatTracker:FormatNumber(totalHealing))

    -- Overheal calculation
    local totalHealingWithOverheal = totalHealing + overhealValue
    local overhealPercent = 0
    if overhealValue > 0 and totalHealingWithOverheal > 0 then
        overhealPercent = math.floor((overhealValue / totalHealingWithOverheal) * 100)
    end
    print("  Overheal %: " .. overhealPercent .. "%")

    print("============================")
end

-- Minimap button (optional)
function addon:CreateMinimapButton()
    if not self.db.showMinimap then return end

    local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)

    -- Button texture
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetSize(20, 20)
    texture:SetPoint("CENTER")
    texture:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")

    -- Button functionality
    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            SlashCmdList.MYUI("toggle")
        elseif button == "RightButton" then
            SlashCmdList.MYUI("config")
        end
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(addonName)
        GameTooltip:AddLine("Left-click to toggle", 1, 1, 1)
        GameTooltip:AddLine("Right-click for options", 1, 1, 1)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    self.minimapButton = button
end
