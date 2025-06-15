-- SettingsWindow.lua
-- Comprehensive settings panel for MyUI2 configuration

local addonName, addon = ...

-- Settings window module
addon.SettingsWindow = {}
local SettingsWindow = addon.SettingsWindow

-- Default settings
local DEFAULT_SETTINGS = {
    -- Combat Detection Settings
    combatTimeout = 1.5,           -- Normal combat timeout in seconds
    deadPlayerTimeout = 8.0,       -- Timeout when player is dead
    includeGroupActivity = true,   -- Track group member activity
    includeIncomingDamage = true,  -- Track incoming damage to player
    
    -- Calculation Settings
    calculationMethod = "rolling_average",  -- rolling_average, final_total, hybrid
    rollingWindowSize = 5.0,       -- Rolling window size in seconds
    sampleInterval = 0.5,          -- Sample interval in seconds
    
    -- Storage Settings
    maxSessions = 50,              -- Maximum stored sessions
    sessionAgeDays = 7,            -- Auto-cleanup after days
    maxMemoryMB = 10,              -- Memory limit in MB
    compressionEnabled = true,     -- Enable session compression
    
    -- Debug Settings
    debugMode = false,             -- Enable debug output
    verboseLogging = false,        -- Enable verbose logging
    enhancedDetectionDebug = false -- Enable enhanced detection debug
}

-- Current settings (loaded from saved variables)
local currentSettings = {}

-- UI elements
local settingsFrame = nil
local tabs = {}
local panels = {}

-- =============================================================================
-- SETTINGS MANAGEMENT
-- =============================================================================

-- Load settings from saved variables
function SettingsWindow:LoadSettings()
    -- Initialize settings from saved variables or defaults
    if not MyUIDB then
        MyUIDB = {}
    end
    
    if not MyUIDB.settings then
        MyUIDB.settings = {}
    end
    
    -- Merge defaults with saved settings
    for key, defaultValue in pairs(DEFAULT_SETTINGS) do
        if MyUIDB.settings[key] ~= nil then
            currentSettings[key] = MyUIDB.settings[key]
        else
            currentSettings[key] = defaultValue
        end
    end
    
    if addon.DEBUG then
        print("SettingsWindow: Settings loaded")
    end
end

-- Save settings to saved variables
function SettingsWindow:SaveSettings()
    if not MyUIDB then
        MyUIDB = {}
    end
    
    MyUIDB.settings = {}
    for key, value in pairs(currentSettings) do
        MyUIDB.settings[key] = value
    end
    
    -- Apply settings to active systems
    self:ApplySettings()
    
    if addon.DEBUG then
        print("SettingsWindow: Settings saved and applied")
    end
end

-- Apply current settings to active systems
function SettingsWindow:ApplySettings()
    -- Apply calculation method
    if addon.CombatData and addon.CombatData.SetCalculationMethod then
        addon.CombatData:SetCalculationMethod(currentSettings.calculationMethod)
    end
    
    -- Apply debug settings
    addon.DEBUG = currentSettings.debugMode
    addon.VERBOSE_DEBUG = currentSettings.verboseLogging
    
    -- Apply TimestampManager debug if available
    if addon.TimestampManager and addon.TimestampManager.SetDebugMode then
        addon.TimestampManager:SetDebugMode(currentSettings.enhancedDetectionDebug)
    end
    
    -- Note: Combat timeout settings will be applied via GetCurrentSettings() calls
    -- Storage settings will be applied when StorageManager initializes
end

-- Get current settings (for other modules to access)
function SettingsWindow:GetCurrentSettings()
    return currentSettings
end

-- =============================================================================
-- UI CREATION
-- =============================================================================

-- Create the main settings window
function SettingsWindow:CreateWindow()
    if settingsFrame then
        return settingsFrame
    end
    
    -- Main frame
    local frame = CreateFrame("Frame", "MyUISettingsFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    
    -- Title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("LEFT", frame.TitleBg, "LEFT", 5, 0)
    frame.title:SetText("MyUI2 Settings")
    
    -- Create tab system
    self:CreateTabs(frame)
    
    -- Create panels for each tab
    self:CreateCombatDetectionPanel(frame)
    self:CreateCalculationsPanel(frame)
    self:CreateStoragePanel(frame)
    self:CreateDebugPanel(frame)
    
    -- Buttons
    self:CreateButtons(frame)
    
    settingsFrame = frame
    return frame
end

-- Create tab buttons
function SettingsWindow:CreateTabs(parent)
    local tabNames = {"Combat Detection", "Calculations", "Storage", "Debug"}
    
    for i, name in ipairs(tabNames) do
        -- Create a simple button using GameMenuButtonTemplate
        local tab = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
        tab:SetSize(120, 25)
        tab:SetID(i)
        tab:SetText(name)
        
        -- Set up click handler
        tab:SetScript("OnClick", function() self:SelectTab(i) end)
        
        -- Position tabs
        if i == 1 then
            tab:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 5, -28)
        else
            tab:SetPoint("LEFT", tabs[i-1], "RIGHT", 5, 0)
        end
        
        tabs[i] = tab
    end
end

-- Select a tab
function SettingsWindow:SelectTab(tabIndex)
    -- Hide all panels
    for i, panel in ipairs(panels) do
        panel:Hide()
    end
    
    -- Show selected panel
    if panels[tabIndex] then
        panels[tabIndex]:Show()
    end
    
    -- Update tab appearance
    for i, tab in ipairs(tabs) do
        if i == tabIndex then
            -- Selected tab appearance - push the button down
            tab:SetButtonState("PUSHED", true)
            tab:SetAlpha(1.0)
        else
            -- Unselected tab appearance
            tab:SetButtonState("NORMAL")
            tab:SetAlpha(0.8)
        end
    end
end

-- Create Combat Detection panel
function SettingsWindow:CreateCombatDetectionPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent.Inset, "TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMRIGHT", parent.Inset, "BOTTOMRIGHT", -10, 40)
    panel:Hide()
    
    local yOffset = -20
    
    -- Combat Timeout slider
    local timeoutLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeoutLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    timeoutLabel:SetText("Combat Timeout (seconds)")
    
    local timeoutSlider = CreateFrame("Slider", "MyUITimeoutSlider", panel, "OptionsSliderTemplate")
    timeoutSlider:SetPoint("TOPLEFT", timeoutLabel, "BOTTOMLEFT", 0, -10)
    timeoutSlider:SetMinMaxValues(0.5, 15.0)
    timeoutSlider:SetValueStep(0.5)
    timeoutSlider:SetValue(currentSettings.combatTimeout)
    
    -- Create value display text
    local timeoutValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeoutValueText:SetPoint("TOP", timeoutSlider, "BOTTOM", 0, -5)
    timeoutValueText:SetText(string.format("%.1f", currentSettings.combatTimeout))
    
    timeoutSlider:SetScript("OnValueChanged", function(self, value)
        currentSettings.combatTimeout = value
        timeoutValueText:SetText(string.format("%.1f", value))
    end)
    
    -- Set slider labels if the template supports them
    if _G[timeoutSlider:GetName() .. "Low"] then
        _G[timeoutSlider:GetName() .. "Low"]:SetText("0.5")
    end
    if _G[timeoutSlider:GetName() .. "High"] then
        _G[timeoutSlider:GetName() .. "High"]:SetText("15.0")
    end
    
    yOffset = yOffset - 70
    
    -- Dead Player Timeout slider
    local deadTimeoutLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    deadTimeoutLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    deadTimeoutLabel:SetText("Dead Player Timeout (seconds)")
    
    local deadTimeoutSlider = CreateFrame("Slider", "MyUIDeadTimeoutSlider", panel, "OptionsSliderTemplate")
    deadTimeoutSlider:SetPoint("TOPLEFT", deadTimeoutLabel, "BOTTOMLEFT", 0, -10)
    deadTimeoutSlider:SetMinMaxValues(2.0, 30.0)
    deadTimeoutSlider:SetValueStep(1.0)
    deadTimeoutSlider:SetValue(currentSettings.deadPlayerTimeout)
    
    -- Create value display text
    local deadTimeoutValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    deadTimeoutValueText:SetPoint("TOP", deadTimeoutSlider, "BOTTOM", 0, -5)
    deadTimeoutValueText:SetText(string.format("%.0f", currentSettings.deadPlayerTimeout))
    
    deadTimeoutSlider:SetScript("OnValueChanged", function(self, value)
        currentSettings.deadPlayerTimeout = value
        deadTimeoutValueText:SetText(string.format("%.0f", value))
    end)
    
    -- Set slider labels if the template supports them
    if _G[deadTimeoutSlider:GetName() .. "Low"] then
        _G[deadTimeoutSlider:GetName() .. "Low"]:SetText("2")
    end
    if _G[deadTimeoutSlider:GetName() .. "High"] then
        _G[deadTimeoutSlider:GetName() .. "High"]:SetText("30")
    end
    
    yOffset = yOffset - 70
    
    -- Group Activity checkbox
    local groupActivityCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    groupActivityCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    groupActivityCheck:SetChecked(currentSettings.includeGroupActivity)
    groupActivityCheck:SetScript("OnClick", function(self)
        currentSettings.includeGroupActivity = self:GetChecked()
    end)
    groupActivityCheck.Text:SetText("Include Group Member Activity")
    
    yOffset = yOffset - 30
    
    -- Incoming Damage checkbox
    local incomingDamageCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    incomingDamageCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    incomingDamageCheck:SetChecked(currentSettings.includeIncomingDamage)
    incomingDamageCheck:SetScript("OnClick", function(self)
        currentSettings.includeIncomingDamage = self:GetChecked()
    end)
    incomingDamageCheck.Text:SetText("Include Incoming Damage to Player")
    
    panels[1] = panel
end

-- Create Calculations panel
function SettingsWindow:CreateCalculationsPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent.Inset, "TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMRIGHT", parent.Inset, "BOTTOMRIGHT", -10, 40)
    panel:Hide()
    
    local yOffset = -20
    
    -- Calculation Method dropdown
    local methodLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    methodLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    methodLabel:SetText("Calculation Method")
    
    local methodDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    methodDropdown:SetPoint("TOPLEFT", methodLabel, "BOTTOMLEFT", -15, -5)
    
    local function MethodDropdown_OnClick(self)
        currentSettings.calculationMethod = self.value
        UIDropDownMenu_SetText(methodDropdown, self:GetText())
        CloseDropDownMenus()
    end
    
    local function MethodDropdown_Initialize(self)
        local info = UIDropDownMenu_CreateInfo()
        
        local methods = {
            {text = "Rolling Average", value = "rolling_average"},
            {text = "Final Total", value = "final_total"},
            {text = "Hybrid", value = "hybrid"}
        }
        
        for _, method in ipairs(methods) do
            info.text = method.text
            info.value = method.value
            info.func = MethodDropdown_OnClick
            info.checked = currentSettings.calculationMethod == method.value
            UIDropDownMenu_AddButton(info)
        end
    end
    
    UIDropDownMenu_Initialize(methodDropdown, MethodDropdown_Initialize)
    UIDropDownMenu_SetWidth(methodDropdown, 150)
    
    -- Set initial text
    local methodText = "Rolling Average"
    if currentSettings.calculationMethod == "final_total" then
        methodText = "Final Total"
    elseif currentSettings.calculationMethod == "hybrid" then
        methodText = "Hybrid"
    end
    UIDropDownMenu_SetText(methodDropdown, methodText)
    
    yOffset = yOffset - 80
    
    -- Rolling Window Size slider
    local windowLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    windowLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    windowLabel:SetText("Rolling Window Size (seconds)")
    
    local windowSlider = CreateFrame("Slider", "MyUIWindowSlider", panel, "OptionsSliderTemplate")
    windowSlider:SetPoint("TOPLEFT", windowLabel, "BOTTOMLEFT", 0, -10)
    windowSlider:SetMinMaxValues(1.0, 10.0)
    windowSlider:SetValueStep(0.5)
    windowSlider:SetValue(currentSettings.rollingWindowSize)
    
    -- Create value display text
    local windowValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    windowValueText:SetPoint("TOP", windowSlider, "BOTTOM", 0, -5)
    windowValueText:SetText(string.format("%.1f", currentSettings.rollingWindowSize))
    
    windowSlider:SetScript("OnValueChanged", function(self, value)
        currentSettings.rollingWindowSize = value
        windowValueText:SetText(string.format("%.1f", value))
    end)
    
    -- Set slider labels if the template supports them
    if _G[windowSlider:GetName() .. "Low"] then
        _G[windowSlider:GetName() .. "Low"]:SetText("1.0")
    end
    if _G[windowSlider:GetName() .. "High"] then
        _G[windowSlider:GetName() .. "High"]:SetText("10.0")
    end
    
    yOffset = yOffset - 70
    
    -- Sample Interval slider
    local sampleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sampleLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    sampleLabel:SetText("Sample Interval (seconds)")
    
    local sampleSlider = CreateFrame("Slider", "MyUISampleSlider", panel, "OptionsSliderTemplate")
    sampleSlider:SetPoint("TOPLEFT", sampleLabel, "BOTTOMLEFT", 0, -10)
    sampleSlider:SetMinMaxValues(0.1, 2.0)
    sampleSlider:SetValueStep(0.1)
    sampleSlider:SetValue(currentSettings.sampleInterval)
    
    -- Create value display text
    local sampleValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sampleValueText:SetPoint("TOP", sampleSlider, "BOTTOM", 0, -5)
    sampleValueText:SetText(string.format("%.1f", currentSettings.sampleInterval))
    
    sampleSlider:SetScript("OnValueChanged", function(self, value)
        currentSettings.sampleInterval = value
        sampleValueText:SetText(string.format("%.1f", value))
    end)
    
    -- Set slider labels if the template supports them
    if _G[sampleSlider:GetName() .. "Low"] then
        _G[sampleSlider:GetName() .. "Low"]:SetText("0.1")
    end
    if _G[sampleSlider:GetName() .. "High"] then
        _G[sampleSlider:GetName() .. "High"]:SetText("2.0")
    end
    
    panels[2] = panel
end

-- Create Storage panel
function SettingsWindow:CreateStoragePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent.Inset, "TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMRIGHT", parent.Inset, "BOTTOMRIGHT", -10, 40)
    panel:Hide()
    
    local yOffset = -20
    
    -- Max Sessions slider
    local maxSessionsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    maxSessionsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    maxSessionsLabel:SetText("Maximum Stored Sessions")
    
    local maxSessionsSlider = CreateFrame("Slider", "MyUIMaxSessionsSlider", panel, "OptionsSliderTemplate")
    maxSessionsSlider:SetPoint("TOPLEFT", maxSessionsLabel, "BOTTOMLEFT", 0, -10)
    maxSessionsSlider:SetMinMaxValues(10, 200)
    maxSessionsSlider:SetValueStep(10)
    maxSessionsSlider:SetValue(currentSettings.maxSessions)
    
    -- Create value display text
    local maxSessionsValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxSessionsValueText:SetPoint("TOP", maxSessionsSlider, "BOTTOM", 0, -5)
    maxSessionsValueText:SetText(string.format("%.0f", currentSettings.maxSessions))
    
    maxSessionsSlider:SetScript("OnValueChanged", function(self, value)
        currentSettings.maxSessions = value
        maxSessionsValueText:SetText(string.format("%.0f", value))
    end)
    
    -- Set slider labels if the template supports them
    if _G[maxSessionsSlider:GetName() .. "Low"] then
        _G[maxSessionsSlider:GetName() .. "Low"]:SetText("10")
    end
    if _G[maxSessionsSlider:GetName() .. "High"] then
        _G[maxSessionsSlider:GetName() .. "High"]:SetText("200")
    end
    
    yOffset = yOffset - 70
    
    -- Session Age slider
    local sessionAgeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sessionAgeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    sessionAgeLabel:SetText("Auto-cleanup After (days)")
    
    local sessionAgeSlider = CreateFrame("Slider", "MyUISessionAgeSlider", panel, "OptionsSliderTemplate")
    sessionAgeSlider:SetPoint("TOPLEFT", sessionAgeLabel, "BOTTOMLEFT", 0, -10)
    sessionAgeSlider:SetMinMaxValues(1, 30)
    sessionAgeSlider:SetValueStep(1)
    sessionAgeSlider:SetValue(currentSettings.sessionAgeDays)
    
    -- Create value display text
    local sessionAgeValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sessionAgeValueText:SetPoint("TOP", sessionAgeSlider, "BOTTOM", 0, -5)
    sessionAgeValueText:SetText(string.format("%.0f", currentSettings.sessionAgeDays))
    
    sessionAgeSlider:SetScript("OnValueChanged", function(self, value)
        currentSettings.sessionAgeDays = value
        sessionAgeValueText:SetText(string.format("%.0f", value))
    end)
    
    -- Set slider labels if the template supports them
    if _G[sessionAgeSlider:GetName() .. "Low"] then
        _G[sessionAgeSlider:GetName() .. "Low"]:SetText("1")
    end
    if _G[sessionAgeSlider:GetName() .. "High"] then
        _G[sessionAgeSlider:GetName() .. "High"]:SetText("30")
    end
    
    yOffset = yOffset - 70
    
    -- Memory Limit slider
    local memoryLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    memoryLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    memoryLabel:SetText("Memory Limit (MB)")
    
    local memorySlider = CreateFrame("Slider", "MyUIMemorySlider", panel, "OptionsSliderTemplate")
    memorySlider:SetPoint("TOPLEFT", memoryLabel, "BOTTOMLEFT", 0, -10)
    memorySlider:SetMinMaxValues(5, 100)
    memorySlider:SetValueStep(5)
    memorySlider:SetValue(currentSettings.maxMemoryMB)
    
    -- Create value display text
    local memoryValueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    memoryValueText:SetPoint("TOP", memorySlider, "BOTTOM", 0, -5)
    memoryValueText:SetText(string.format("%.0f", currentSettings.maxMemoryMB))
    
    memorySlider:SetScript("OnValueChanged", function(self, value)
        currentSettings.maxMemoryMB = value
        memoryValueText:SetText(string.format("%.0f", value))
    end)
    
    -- Set slider labels if the template supports them
    if _G[memorySlider:GetName() .. "Low"] then
        _G[memorySlider:GetName() .. "Low"]:SetText("5")
    end
    if _G[memorySlider:GetName() .. "High"] then
        _G[memorySlider:GetName() .. "High"]:SetText("100")
    end
    
    yOffset = yOffset - 70
    
    -- Compression checkbox
    local compressionCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    compressionCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    compressionCheck:SetChecked(currentSettings.compressionEnabled)
    compressionCheck:SetScript("OnClick", function(self)
        currentSettings.compressionEnabled = self:GetChecked()
    end)
    compressionCheck.Text:SetText("Enable Session Compression")
    
    panels[3] = panel
end

-- Create Debug panel
function SettingsWindow:CreateDebugPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent.Inset, "TOPLEFT", 10, -10)
    panel:SetPoint("BOTTOMRIGHT", parent.Inset, "BOTTOMRIGHT", -10, 40)
    panel:Hide()
    
    local yOffset = -20
    
    -- Debug Mode checkbox
    local debugModeCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    debugModeCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    debugModeCheck:SetChecked(currentSettings.debugMode)
    debugModeCheck:SetScript("OnClick", function(self)
        currentSettings.debugMode = self:GetChecked()
    end)
    debugModeCheck.Text:SetText("Enable Debug Mode")
    
    yOffset = yOffset - 30
    
    -- Verbose Logging checkbox
    local verboseCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    verboseCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    verboseCheck:SetChecked(currentSettings.verboseLogging)
    verboseCheck:SetScript("OnClick", function(self)
        currentSettings.verboseLogging = self:GetChecked()
    end)
    verboseCheck.Text:SetText("Enable Verbose Logging")
    
    yOffset = yOffset - 30
    
    -- Enhanced Detection Debug checkbox
    local enhancedDebugCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    enhancedDebugCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    enhancedDebugCheck:SetChecked(currentSettings.enhancedDetectionDebug)
    enhancedDebugCheck:SetScript("OnClick", function(self)
        currentSettings.enhancedDetectionDebug = self:GetChecked()
    end)
    enhancedDebugCheck.Text:SetText("Enable Enhanced Detection Debug")
    
    yOffset = yOffset - 50
    
    -- Debug buttons section
    local debugButtonsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    debugButtonsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    debugButtonsLabel:SetText("Debug Commands")
    
    yOffset = yOffset - 30
    
    -- Combat Detection Debug button
    local combatDebugBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    combatDebugBtn:SetSize(200, 25)
    combatDebugBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    combatDebugBtn:SetText("Combat Detection Debug")
    combatDebugBtn:SetScript("OnClick", function()
        if addon.CombatData and addon.CombatData.DebugEnhancedCombatDetection then
            addon.CombatData:DebugEnhancedCombatDetection()
        else
            print("Combat detection debug not available")
        end
    end)
    
    yOffset = yOffset - 35
    
    -- Storage Debug button
    local storageDebugBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    storageDebugBtn:SetSize(200, 25)
    storageDebugBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, yOffset)
    storageDebugBtn:SetText("Storage Debug")
    storageDebugBtn:SetScript("OnClick", function()
        if addon.StorageManager and addon.StorageManager.GetDebugSummary then
            print(addon.StorageManager:GetDebugSummary())
        else
            print("Storage debug not available")
        end
    end)
    
    panels[4] = panel
end

-- Create OK/Cancel buttons
function SettingsWindow:CreateButtons(parent)
    -- OK button
    local okBtn = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
    okBtn:SetSize(80, 25)
    okBtn:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 10)
    okBtn:SetText("OK")
    okBtn:SetScript("OnClick", function()
        self:SaveSettings()
        settingsFrame:Hide()
    end)
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
    cancelBtn:SetSize(80, 25)
    cancelBtn:SetPoint("RIGHT", okBtn, "LEFT", -10, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        self:RevertSettings()
        settingsFrame:Hide()
    end)
    
    -- Apply button
    local applyBtn = CreateFrame("Button", nil, parent, "GameMenuButtonTemplate")
    applyBtn:SetSize(80, 25)
    applyBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
    applyBtn:SetText("Apply")
    applyBtn:SetScript("OnClick", function()
        self:SaveSettings()
    end)
end

-- Revert settings to saved values
function SettingsWindow:RevertSettings()
    self:LoadSettings()
    -- TODO: Update UI elements to reflect reverted values
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

-- Show the settings window
function SettingsWindow:Show()
    if not settingsFrame then
        self:CreateWindow()
        self:LoadSettings()
    end
    
    settingsFrame:Show()
    self:SelectTab(1) -- Show first tab by default
end

-- Hide the settings window
function SettingsWindow:Hide()
    if settingsFrame then
        settingsFrame:Hide()
    end
end

-- Toggle settings window visibility
function SettingsWindow:Toggle()
    if settingsFrame and settingsFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Initialize settings system
function SettingsWindow:Initialize()
    self:LoadSettings()
    self:ApplySettings()
    
    if addon.DEBUG then
        print("SettingsWindow: Initialized")
    end
end