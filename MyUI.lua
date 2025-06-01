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
addon.VERSION = "main-73c452e"
addon.BUILD_DATE = "2025-06-01-18:42"

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
    elseif command == "pixeltest" then
        print("=== PIXEL METER TEST ===")
        if not addon.HPSWindow then
            print("ERROR: HPSWindow doesn't exist")
            return
        end
        if not addon.HPSWindow.frame then
            print("ERROR: HPSWindow.frame doesn't exist")
            return
        end
        if not addon.HPSWindow.pixelMeter then
            print("ERROR: HPSWindow.pixelMeter doesn't exist")
            return
        end

        local pm = addon.HPSWindow.pixelMeter
        print("PixelMeter object exists:", pm ~= nil)
        print("PixelMeter.frame exists:", pm.frame ~= nil)
        print("PixelMeter.pixels table exists:", pm.pixels ~= nil)

        if pm.pixels then
            print("PixelMeter.pixels[1] exists:", pm.pixels[1] ~= nil)
            if pm.pixels[1] then
                print("PixelMeter.pixels[1][1] exists:", pm.pixels[1][1] ~= nil)
            end
        end

        print("Calling pm:Show()...")
        pm:Show()
        print("pm:Show() completed")
        print("=== END PIXEL TEST ===")
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
    elseif command == "hpsmeter" then
        if not addon.hpsPixelMeter then
            if addon.WorkingPixelMeter then
                addon.hpsPixelMeter = addon.WorkingPixelMeter:New({
                    cols = 20,
                    rows = 1,
                    pixelSize = 8,
                    gap = 1,
                    maxValue = 15000
                })
                addon.hpsPixelMeter:SetValueSource(function()
                    return addon.CombatTracker:GetRollingHPS()
                end)
            else
                print("ERROR: WorkingPixelMeter not loaded")
                return
            end
        end
        addon.hpsPixelMeter:Toggle()

        -- Position after showing (when frame exists)
        if addon.hpsPixelMeter.frame and addon.HPSWindow and addon.HPSWindow.frame then
            addon.hpsPixelMeter.frame:ClearAllPoints()
            addon.hpsPixelMeter.frame:SetPoint("BOTTOM", addon.HPSWindow.frame, "TOP", 0, 5)
        end
    elseif command == "dpsmeter" then
        if not addon.dpsPixelMeter then
            if addon.WorkingPixelMeter then
                addon.dpsPixelMeter = addon.WorkingPixelMeter:New({
                    cols = 20,
                    rows = 1,
                    pixelSize = 8,
                    gap = 1,
                    maxValue = 15000
                })
                addon.dpsPixelMeter:SetValueSource(function()
                    return addon.CombatTracker:GetRollingDPS()
                end)
            else
                print("ERROR: WorkingPixelMeter not loaded")
                return
            end
        end
        addon.dpsPixelMeter:Toggle()

        -- Position after showing (when frame exists)
        if addon.dpsPixelMeter.frame and addon.DPSWindow and addon.DPSWindow.frame then
            addon.dpsPixelMeter.frame:ClearAllPoints()
            addon.dpsPixelMeter.frame:SetPoint("BOTTOM", addon.DPSWindow.frame, "TOP", 0, 5)
        end
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
    else
        print("Usage: /myui [show | hide | toggle | dps | hps | debug | pixeltest | cstart | cend ]")
    end
end

function addon:CreateMinimapButton()
    if not self.db.showMinimap then return end
    if self.minimapButton then return end

    print("Creating minimap button with dynamic radius...")

    local button = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)

    -- Create background circle
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(32, 32)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Button icon
    local texture = button:CreateTexture(nil, "ARTWORK")
    texture:SetSize(20, 20)
    texture:SetPoint("CENTER")
    texture:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")

    -- Create highlight texture
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(32, 32)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.5)

    -- Position button using dynamic radius
    local angle = self.db.minimapButtonAngle or 225
    self:PositionMinimapButton(button, angle)

    -- FIXED DRAGGING - follows mouse smoothly around circle
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")

    local isDragging = false
    local dragStartTime = 0

    button:SetScript("OnDragStart", function(self)
        isDragging = true
        dragStartTime = GetTime()

        -- Get the dynamic radius once at start of drag
        local dragRadius = addon:GetDynamicRadius()
        if not dragRadius or dragRadius <= 0 then
            dragRadius = 85
        end

        self:SetScript("OnUpdate", function(self)
            local centerX, centerY = Minimap:GetCenter()
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()

            cursorX = cursorX / scale
            cursorY = cursorY / scale

            if centerX and centerY then
                -- Calculate angle from minimap center to cursor
                local deltaX = cursorX - centerX
                local deltaY = cursorY - centerY
                local angle = math.atan2(deltaY, deltaX)

                -- Position button at fixed radius in direction of cursor
                local newX = centerX + math.cos(angle) * dragRadius
                local newY = centerY + math.sin(angle) * dragRadius

                -- Position relative to UIParent (screen coordinates)
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", newX, newY)
            end
        end)
    end)

    button:SetScript("OnDragStop", function(self)
        local dragDuration = GetTime() - dragStartTime
        isDragging = false
        self:SetScript("OnUpdate", nil)

        -- Save the final position
        addon:UpdateMinimapButtonAngle()

        -- If it was a very short drag (< 0.1 seconds), treat it as a click
        if dragDuration < 0.1 then
            addon:ToggleMainWindow()
        end
    end)

    -- SIMPLIFIED CLICK HANDLING - only for right-click since left-click is handled by drag
    button:SetScript("OnMouseUp", function(self, clickButton)
        if clickButton == "RightButton" and not isDragging then
            addon:ShowMinimapButtonMenu()
        end
    end)

    -- Tooltip
    button:SetScript("OnEnter", function(self)
        if not isDragging then -- Only show tooltip when not dragging
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("My UI v" .. addon.VERSION, 1, 1, 1)
            GameTooltip:AddLine("Left-click: Toggle main window", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Right-click: Options menu", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Drag: Move around minimap", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end
    end)

    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    button:Show()
    self.minimapButton = button
    print("MyUI minimap button created with smooth dragging!")
end

function addon:PositionMinimapButton(button, angle)
    local radius = self:GetDynamicRadius() or 98 -- Dynamic with fallback
    local radian = math.rad(angle)
    local x = math.cos(radian) * radius
    local y = math.sin(radian) * radius

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function addon:UpdateMinimapButtonAngle()
    if not self.minimapButton then return end

    local centerX, centerY = Minimap:GetCenter()
    local buttonX, buttonY = self.minimapButton:GetCenter()

    if centerX and centerY and buttonX and buttonY then
        local angle = math.deg(math.atan2(buttonY - centerY, buttonX - centerX))
        self.db.minimapButtonAngle = angle
        -- Don't reposition here - it's already positioned correctly
    end
end

function addon:ShowMinimapButtonMenu()
    addon:ShowSimpleRightClickMenu()
end

-- Simple text-based right-click menu that always works
function addon:ShowSimpleRightClickMenu()
    print("|cffFFD700=== My UI Quick Menu ===|r")
    print("|cff80FF80Left-click this button:|r Toggle main window")
    print("|cff80FF80Available commands:|r")
    print("  |cffFFFFFF/myui|r - Toggle main window")
    print("  |cffFFFFFF/myui dps|r - Toggle DPS window")
    print("  |cffFFFFFF/myui hps|r - Toggle HPS window")
    print("  |cffFFFFFF/myui debug|r - Toggle debug mode")
    print("  |cffFFFFFF/myui minimap|r - Hide this button")
    print("|cffFFD700=======================|r")
end

function addon:GetDynamicRadius()
    -- Get minimap boundaries
    local minimapLeft = Minimap:GetLeft() or 0
    local minimapRight = Minimap:GetRight() or 0
    local minimapTop = Minimap:GetTop() or 0
    local minimapBottom = Minimap:GetBottom() or 0

    local minimapWidth = minimapRight - minimapLeft
    local minimapHeight = minimapTop - minimapBottom

    -- Calculate radius based on actual minimap size
    local actualRadius = math.min(minimapWidth, minimapHeight) / 2
    local buttonRadius = actualRadius + 18 -- Add space for button outside border

    print("Minimap boundaries:", minimapLeft, minimapRight, minimapTop, minimapBottom)
    print("Minimap dimensions:", minimapWidth, "x", minimapHeight)
    print("Dynamic radius:", math.floor(buttonRadius))

    return buttonRadius
end
