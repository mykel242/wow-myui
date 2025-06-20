-- MyCombatMeterWindow.lua
-- Real-time DPS/HPS meter with decoupled message queue architecture
--
-- PERFORMANCE DESIGN:
-- - Ring buffer for recent combat events (30 second window)
-- - Rate-limited UI updates (max 4 FPS during combat)
-- - Lightweight FontString-based 20-segment display
-- - Memory-bounded calculations with automatic cleanup
-- - Combat-aware performance scaling

local addonName, addon = ...

-- =============================================================================
-- COMBAT METER WINDOW MODULE
-- =============================================================================

local MyCombatMeterWindow = {}
addon.MyCombatMeterWindow = MyCombatMeterWindow

-- =============================================================================
-- CONSTANTS AND CONFIGURATION
-- =============================================================================

local WINDOW_WIDTH = 300
local WINDOW_HEIGHT = 400
local SEGMENT_HEIGHT = 16
local MAX_SEGMENTS = 20

-- Performance configuration for meter updates
local PERFORMANCE_CONFIG = {
    REFRESH_THROTTLE_MS = 250,    -- 4 FPS max during combat
    COMBAT_THROTTLE_MS = 500,     -- 2 FPS during intensive combat
    RING_BUFFER_SIZE = 1000,      -- Combat events for calculations
    CALCULATION_WINDOW = 30,      -- Seconds of data for rolling calculations
    BUSY_THRESHOLD = 10,          -- Events per second to consider "busy"
}

-- Calculation methods
local CALCULATION_METHODS = {
    ROLLING = "rolling",
    FINAL = "final", 
    HYBRID = "hybrid"
}

-- =============================================================================
-- UI ELEMENTS AND STATE
-- =============================================================================

local meterWindow = nil
local meterSegments = {}
local currentCalculationMethod = CALCULATION_METHODS.ROLLING
local isVisible = false

-- Ring buffer for combat events
local eventRingBuffer = {
    events = {},
    capacity = PERFORMANCE_CONFIG.RING_BUFFER_SIZE,
    writeIndex = 1,
    size = 0,
    totalWritten = 0
}

-- Meter state
local meterState = {
    currentDPS = 0,
    currentHPS = 0,
    peakDPS = 0,
    peakHPS = 0,
    combatStartTime = 0,
    inCombat = false,
    totalDamage = 0,
    totalHealing = 0,
    scale = 1000,  -- Default scale
    displayMode = "both", -- "dps", "hps", "both"
    segmentCount = MAX_SEGMENTS,
    isPaused = false,
    lastUpdateTime = 0,
    refreshTimer = nil
}

-- Performance tracking
local performanceState = {
    isBusyPeriod = false,
    recentEventTimes = {},
    pendingCalculation = false,
    throttleMode = "normal" -- "normal", "combat", "intensive"
}

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MyCombatMeterWindow:Initialize()
    -- Set up message queue subscription for combat events
    -- Note: We delay subscriptions until after the window is created
    addon:Info("MyCombatMeterWindow: Initialize called - subscriptions will be set up after window creation")
end

function MyCombatMeterWindow:SetupSubscriptions()
    -- This is called after the window is created to ensure the message queue instance is ready
    addon:Debug("MyCombatMeterWindow:SetupSubscriptions - setting up message queue subscriptions")
    
    -- Debug: Check if CombatEventQueue exists
    if not addon.CombatEventQueue then
        addon:Warn("MyCombatMeterWindow: CombatEventQueue is nil!")
        return
    end
    
    if not addon.CombatEventQueue.Subscribe then
        addon:Warn("MyCombatMeterWindow: CombatEventQueue.Subscribe method not found!")
        return
    end
    
    addon:Debug("MyCombatMeterWindow: CombatEventQueue found, setting up subscriptions...")
    
    if addon.CombatEventQueue and addon.CombatEventQueue.Subscribe then
        -- Subscribe to combat state changes
        self.combatStateSubscriberId = addon.CombatEventQueue:Subscribe(
            "COMBAT_STATE_CHANGED", 
            function(message)
                self:UpdateCombatState(message.data)
            end,
            "CombatMeterWindow_StateTracker"
        )
        
        -- Subscribe to damage events
        self.damageSubscriberId = addon.CombatEventQueue:Subscribe(
            "DAMAGE_EVENT", 
            function(message)
                local eventData = message.data
                addon:Trace("MyCombatMeterWindow: Received DAMAGE_EVENT, amount: %d", eventData.amount or 0)
                self:ProcessCombatEvent({
                    type = "DAMAGE",
                    amount = eventData.amount or 0,
                    timestamp = eventData.timestamp or GetTime(),
                    source = eventData.source,
                    target = eventData.target
                })
            end,
            "CombatMeterWindow_DamageTracker"
        )
        
        -- Subscribe to healing events
        self.healSubscriberId = addon.CombatEventQueue:Subscribe(
            "HEAL_EVENT", 
            function(message)
                local eventData = message.data
                addon:Trace("MyCombatMeterWindow: Received HEAL_EVENT, amount: %d", eventData.amount or 0)
                self:ProcessCombatEvent({
                    type = "HEAL",
                    amount = eventData.amount or 0,
                    timestamp = eventData.timestamp or GetTime(),
                    source = eventData.source,
                    target = eventData.target
                })
            end,
            "CombatMeterWindow_HealTracker"
        )
        
        addon:Info("MyCombatMeterWindow: Combat event queue subscriptions established")
        addon:Debug("Subscriber IDs: State=%d, Damage=%d, Heal=%d", 
            self.combatStateSubscriberId, self.damageSubscriberId, self.healSubscriberId)
    else
        addon:Warn("MyCombatMeterWindow: CombatEventQueue not available - meter will not receive events")
        print("MyCombatMeterWindow: ERROR - No combat event queue available")
    end
end

-- =============================================================================
-- RING BUFFER FUNCTIONS
-- =============================================================================

-- Add combat event to ring buffer
local function AddEventToBuffer(eventData)
    eventRingBuffer.events[eventRingBuffer.writeIndex] = eventData
    eventRingBuffer.totalWritten = eventRingBuffer.totalWritten + 1
    
    if eventRingBuffer.size < eventRingBuffer.capacity then
        eventRingBuffer.size = eventRingBuffer.size + 1
    end
    
    eventRingBuffer.writeIndex = eventRingBuffer.writeIndex + 1
    if eventRingBuffer.writeIndex > eventRingBuffer.capacity then
        eventRingBuffer.writeIndex = 1
    end
end

-- Get events from last N seconds for calculations
local function GetRecentEvents(secondsBack)
    local cutoffTime = GetTime() - secondsBack
    local recentEvents = {}
    
    for i = 1, eventRingBuffer.size do
        local index = eventRingBuffer.writeIndex - i
        if index <= 0 then
            index = index + eventRingBuffer.capacity
        end
        
        local event = eventRingBuffer.events[index]
        if event and event.timestamp >= cutoffTime then
            table.insert(recentEvents, event)
        else
            break -- Events are ordered by time, so we can stop here
        end
    end
    
    return recentEvents
end

-- =============================================================================
-- PERFORMANCE OPTIMIZATION FUNCTIONS
-- =============================================================================

-- Check if we're in a busy combat period
local function IsBusyPeriod()
    local currentTime = GetTime()
    local recentCount = 0
    
    -- Count events in the last second
    for i = #performanceState.recentEventTimes, 1, -1 do
        local eventTime = performanceState.recentEventTimes[i]
        if currentTime - eventTime <= 1.0 then
            recentCount = recentCount + 1
        else
            -- Remove old entries
            table.remove(performanceState.recentEventTimes, i)
        end
    end
    
    return recentCount >= PERFORMANCE_CONFIG.BUSY_THRESHOLD
end

-- Update performance throttle mode based on combat intensity
local function UpdateThrottleMode()
    if not meterState.inCombat then
        performanceState.throttleMode = "normal"
    elseif IsBusyPeriod() then
        performanceState.throttleMode = "intensive"
    else
        performanceState.throttleMode = "combat"
    end
end

-- Get appropriate refresh interval based on current mode
local function GetRefreshInterval()
    if performanceState.throttleMode == "intensive" then
        return PERFORMANCE_CONFIG.COMBAT_THROTTLE_MS
    elseif performanceState.throttleMode == "combat" then
        return PERFORMANCE_CONFIG.REFRESH_THROTTLE_MS
    else
        return PERFORMANCE_CONFIG.REFRESH_THROTTLE_MS
    end
end

-- =============================================================================
-- CALCULATION ENGINE
-- =============================================================================

-- Process combat event for DPS/HPS calculation
function MyCombatMeterWindow:ProcessCombatEvent(eventData)
    -- Safety check to prevent infinite loops during startup
    if not meterWindow then
        addon:Debug("MyCombatMeterWindow: Ignoring event - window not created yet")
        return
    end
    
    addon:Debug("MyCombatMeterWindow:ProcessCombatEvent called with type: %s, amount: %s", 
        eventData and eventData.type or "nil", 
        eventData and eventData.amount or "nil")
    
    if not eventData or meterState.isPaused then
        addon:Debug("MyCombatMeterWindow: Event rejected - eventData: %s, isPaused: %s", 
            tostring(eventData ~= nil), tostring(meterState.isPaused))
        return
    end
    
    -- Track event timing for performance monitoring
    local currentTime = GetTime()
    table.insert(performanceState.recentEventTimes, currentTime)
    
    -- Add to ring buffer
    eventData.timestamp = currentTime
    AddEventToBuffer(eventData)
    
    -- Extract damage/healing values
    local damage = 0
    local healing = 0
    
    if eventData.type == "DAMAGE" and eventData.amount then
        damage = eventData.amount
        meterState.totalDamage = meterState.totalDamage + damage
        addon:Debug("MyCombatMeterWindow: Added damage %d, total now: %d", damage, meterState.totalDamage)
    elseif eventData.type == "HEAL" and eventData.amount then
        healing = eventData.amount
        meterState.totalHealing = meterState.totalHealing + healing
        addon:Debug("MyCombatMeterWindow: Added healing %d, total now: %d", healing, meterState.totalHealing)
    else
        addon:Debug("MyCombatMeterWindow: Event not processed - type: %s, amount: %s", 
            eventData.type or "nil", tostring(eventData.amount))
    end
    
    -- Schedule rate-limited calculation update
    self:ScheduleCalculationUpdate()
end

-- Schedule a rate-limited meter calculation
function MyCombatMeterWindow:ScheduleCalculationUpdate()
    if performanceState.pendingCalculation then
        return -- Already scheduled
    end
    
    UpdateThrottleMode()
    local delay = GetRefreshInterval() / 1000
    
    performanceState.pendingCalculation = true
    meterState.refreshTimer = C_Timer.After(delay, function()
        performanceState.pendingCalculation = false
        meterState.refreshTimer = nil
        
        if meterWindow and meterWindow:IsVisible() and meterState.inCombat then
            MyCombatMeterWindow:CalculateAndUpdate()
        end
    end)
end

-- Calculate current DPS/HPS using selected method
function MyCombatMeterWindow:CalculateAndUpdate()
    if not meterState.inCombat then
        return
    end
    
    local currentTime = GetTime()
    local combatElapsed = currentTime - meterState.combatStartTime
    
    if combatElapsed <= 0 then
        return
    end
    
    local newDPS = 0
    local newHPS = 0
    
    if currentCalculationMethod == CALCULATION_METHODS.ROLLING then
        -- Rolling average over last 5 seconds
        newDPS, newHPS = self:CalculateRollingAverage(5)
    elseif currentCalculationMethod == CALCULATION_METHODS.FINAL then
        -- Total damage/healing divided by elapsed time
        newDPS = meterState.totalDamage / combatElapsed
        newHPS = meterState.totalHealing / combatElapsed
    elseif currentCalculationMethod == CALCULATION_METHODS.HYBRID then
        -- 70% rolling + 30% final
        local rollingDPS, rollingHPS = self:CalculateRollingAverage(5)
        local finalDPS = meterState.totalDamage / combatElapsed
        local finalHPS = meterState.totalHealing / combatElapsed
        
        newDPS = (rollingDPS * 0.7) + (finalDPS * 0.3)
        newHPS = (rollingHPS * 0.7) + (finalHPS * 0.3)
    end
    
    -- Update meter state
    meterState.currentDPS = newDPS
    meterState.currentHPS = newHPS
    meterState.peakDPS = math.max(meterState.peakDPS, newDPS)
    meterState.peakHPS = math.max(meterState.peakHPS, newHPS)
    meterState.lastUpdateTime = currentTime
    
    -- Update visual display
    self:UpdateMeterDisplay()
end

-- Calculate rolling average DPS/HPS
function MyCombatMeterWindow:CalculateRollingAverage(windowSeconds)
    local recentEvents = GetRecentEvents(windowSeconds)
    local totalDamage = 0
    local totalHealing = 0
    
    for _, event in ipairs(recentEvents) do
        if event.type == "DAMAGE" and event.amount then
            totalDamage = totalDamage + event.amount
        elseif event.type == "HEAL" and event.amount then
            totalHealing = totalHealing + event.amount
        end
    end
    
    local actualWindow = math.min(windowSeconds, GetTime() - meterState.combatStartTime)
    if actualWindow <= 0 then
        return 0, 0
    end
    
    return totalDamage / actualWindow, totalHealing / actualWindow
end

-- =============================================================================
-- COMBAT STATE MANAGEMENT
-- =============================================================================

-- Handle combat state changes
function MyCombatMeterWindow:UpdateCombatState(stateData)
    addon:Debug("MyCombatMeterWindow:UpdateCombatState - inCombat: %s, meterState.inCombat: %s", 
        tostring(stateData.inCombat), tostring(meterState.inCombat))
    
    if stateData.inCombat and not meterState.inCombat then
        -- Combat started
        addon:Debug("MyCombatMeterWindow: Starting combat")
        self:StartCombat()
    elseif not stateData.inCombat and meterState.inCombat then
        -- Combat ended
        addon:Debug("MyCombatMeterWindow: Ending combat")
        self:EndCombat()
    end
end

-- Start combat tracking
function MyCombatMeterWindow:StartCombat()
    meterState.inCombat = true
    meterState.combatStartTime = GetTime()
    meterState.totalDamage = 0
    meterState.totalHealing = 0
    meterState.currentDPS = 0
    meterState.currentHPS = 0
    meterState.peakDPS = 0
    meterState.peakHPS = 0
    
    -- Clear ring buffer for new combat
    eventRingBuffer.size = 0
    eventRingBuffer.writeIndex = 1
    
    -- Reset performance state
    performanceState.recentEventTimes = {}
    performanceState.isBusyPeriod = false
    performanceState.throttleMode = "combat"
    
    if meterWindow and meterWindow:IsVisible() then
        self:UpdateMeterDisplay()
    end
    
    addon:Debug("Combat meter: Combat started")
end

-- End combat tracking
function MyCombatMeterWindow:EndCombat()
    meterState.inCombat = false
    
    -- Clean up refresh timer
    if meterState.refreshTimer then
        meterState.refreshTimer:Cancel()
        meterState.refreshTimer = nil
    end
    
    performanceState.pendingCalculation = false
    performanceState.throttleMode = "normal"
    
    -- Final calculation for end-of-combat display
    if meterState.combatStartTime > 0 then
        local combatDuration = meterState.lastUpdateTime - meterState.combatStartTime
        if combatDuration > 0 then
            local finalDPS = meterState.totalDamage / combatDuration
            local finalHPS = meterState.totalHealing / combatDuration
            
            meterState.currentDPS = finalDPS
            meterState.currentHPS = finalHPS
            
            if meterWindow and meterWindow:IsVisible() then
                self:UpdateMeterDisplay()
            end
            
            addon:Debug("Combat meter: Combat ended - Final DPS: %.0f, HPS: %.0f", finalDPS, finalHPS)
        end
    end
end

-- =============================================================================
-- WINDOW CREATION AND MANAGEMENT
-- =============================================================================

function MyCombatMeterWindow:CreateWindow()
    if meterWindow then return end
    
    addon:Debug("Starting meter window creation...")
    
    -- Main window frame
    meterWindow = CreateFrame("Frame", addonName .. "CombatMeterWindow", UIParent, "BasicFrameTemplateWithInset")
    addon:Debug("Base frame created")
    
    meterWindow:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    meterWindow:SetPoint("CENTER", UIParent, "CENTER", 300, 0) -- Offset from main window
    meterWindow:SetMovable(true)
    meterWindow:EnableMouse(true)
    meterWindow:RegisterForDrag("LeftButton")
    meterWindow:SetScript("OnDragStart", meterWindow.StartMoving)
    meterWindow:SetScript("OnDragStop", meterWindow.StopMovingOrSizing)
    meterWindow:Hide()
    addon:Debug("Basic frame setup complete")
    
    -- Register with FocusManager
    if addon.FocusManager then
        addon.FocusManager:RegisterWindow(meterWindow, nil, "MEDIUM")
        addon:Debug("Registered with FocusManager")
    end
    
    -- Title
    meterWindow.TitleText:SetText("Combat Meter")
    addon:Debug("Title set")
    
    -- Close button
    meterWindow.CloseButton:SetScript("OnClick", function()
        MyCombatMeterWindow:Hide()
    end)
    addon:Debug("Close button setup")
    
    -- Create meter display and controls
    self:CreateMeterDisplay()
    self:CreateControlButtons()
    
    addon:Debug("Combat meter window created successfully")
    return meterWindow
end

-- Create the meter display area
function MyCombatMeterWindow:CreateMeterDisplay()
    -- Main display frame
    local displayFrame = CreateFrame("Frame", nil, meterWindow)
    displayFrame:SetPoint("TOPLEFT", meterWindow, "TOPLEFT", 15, -35)
    displayFrame:SetPoint("BOTTOMRIGHT", meterWindow, "BOTTOMRIGHT", -15, 50)
    
    -- Add backdrop
    if BackdropTemplateMixin then
        Mixin(displayFrame, BackdropTemplateMixin)
    end
    
    displayFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    displayFrame:SetBackdropColor(0, 0, 0, 0.8)
    displayFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    meterWindow.displayFrame = displayFrame
    
    -- Create meter segments
    self:CreateMeterSegments(displayFrame)
    
    -- Create info display
    self:CreateInfoDisplay(displayFrame)
end

-- Create the 20-segment meter display
function MyCombatMeterWindow:CreateMeterSegments(parent)
    meterSegments = {}
    
    local segmentWidth = (WINDOW_WIDTH - 40) / 2 -- Two columns: DPS and HPS
    local startY = -20
    
    -- DPS column
    for i = 1, meterState.segmentCount do
        local segment = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        segment:SetSize(segmentWidth - 10, SEGMENT_HEIGHT)
        segment:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, startY - (i - 1) * SEGMENT_HEIGHT)
        segment:SetJustifyH("LEFT")
        segment:SetText("") -- Start empty
        segment:SetTextColor(1, 0.8, 0.8) -- Light red for DPS
        
        meterSegments[i] = {
            dps = segment,
            level = i / meterState.segmentCount -- Normalized level (0-1)
        }
    end
    
    -- HPS column (if displaying both)
    for i = 1, meterState.segmentCount do
        local segment = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        segment:SetSize(segmentWidth - 10, SEGMENT_HEIGHT)
        segment:SetPoint("TOPLEFT", parent, "TOPLEFT", segmentWidth + 10, startY - (i - 1) * SEGMENT_HEIGHT)
        segment:SetJustifyH("LEFT")
        segment:SetText("") -- Start empty
        segment:SetTextColor(0.8, 1, 0.8) -- Light green for HPS
        
        meterSegments[i].hps = segment
    end
end

-- Create info display at bottom
function MyCombatMeterWindow:CreateInfoDisplay(parent)
    local infoFrame = CreateFrame("Frame", nil, parent)
    infoFrame:SetSize(WINDOW_WIDTH - 30, 80)
    infoFrame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 10)
    
    -- Current values display
    local dpsLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dpsLabel:SetPoint("TOPLEFT", infoFrame, "TOPLEFT", 10, -5)
    dpsLabel:SetTextColor(1, 0.8, 0.8)
    dpsLabel:SetText("DPS: 0")
    
    local hpsLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hpsLabel:SetPoint("TOPRIGHT", infoFrame, "TOPRIGHT", -10, -5)
    hpsLabel:SetTextColor(0.8, 1, 0.8)
    hpsLabel:SetText("HPS: 0")
    
    -- Peak values display
    local peakDPSLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    peakDPSLabel:SetPoint("TOPLEFT", dpsLabel, "BOTTOMLEFT", 0, -5)
    peakDPSLabel:SetTextColor(1, 1, 0.8)
    peakDPSLabel:SetText("Peak: 0")
    
    local peakHPSLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    peakHPSLabel:SetPoint("TOPRIGHT", hpsLabel, "BOTTOMRIGHT", 0, -5)
    peakHPSLabel:SetTextColor(1, 1, 0.8)
    peakHPSLabel:SetText("Peak: 0")
    
    -- Combat time display
    local timeLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timeLabel:SetPoint("TOP", infoFrame, "TOP", 0, -35)
    timeLabel:SetTextColor(0.8, 0.8, 1)
    timeLabel:SetText("Combat: 0s")
    
    -- Method display
    local methodLabel = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    methodLabel:SetPoint("TOP", timeLabel, "BOTTOM", 0, -5)
    methodLabel:SetTextColor(0.7, 0.7, 0.7)
    methodLabel:SetText("Method: Rolling")
    
    -- Store references
    meterWindow.dpsLabel = dpsLabel
    meterWindow.hpsLabel = hpsLabel
    meterWindow.peakDPSLabel = peakDPSLabel
    meterWindow.peakHPSLabel = peakHPSLabel
    meterWindow.timeLabel = timeLabel
    meterWindow.methodLabel = methodLabel
end

-- Create control buttons
function MyCombatMeterWindow:CreateControlButtons()
    local buttonFrame = CreateFrame("Frame", nil, meterWindow)
    buttonFrame:SetSize(WINDOW_WIDTH - 30, 30)
    buttonFrame:SetPoint("BOTTOM", meterWindow, "BOTTOM", 0, 10)
    
    -- Pause/Resume button
    local pauseButton = CreateFrame("Button", nil, buttonFrame, "GameMenuButtonTemplate")
    pauseButton:SetSize(60, 22)
    pauseButton:SetPoint("LEFT", buttonFrame, "LEFT", 10, 0)
    pauseButton:SetText("Pause")
    pauseButton:SetScript("OnClick", function()
        MyCombatMeterWindow:TogglePause()
    end)
    
    -- Reset button
    local resetButton = CreateFrame("Button", nil, buttonFrame, "GameMenuButtonTemplate")
    resetButton:SetSize(60, 22)
    resetButton:SetPoint("LEFT", pauseButton, "RIGHT", 5, 0)
    resetButton:SetText("Reset")
    resetButton:SetScript("OnClick", function()
        MyCombatMeterWindow:ResetMeter()
    end)
    
    -- Method dropdown
    local methodDropdown = CreateFrame("Frame", nil, buttonFrame, "UIDropDownMenuTemplate")
    methodDropdown:SetPoint("RIGHT", buttonFrame, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(methodDropdown, 80)
    UIDropDownMenu_SetText(methodDropdown, "Rolling")
    
    UIDropDownMenu_Initialize(methodDropdown, function(self, level)
        local methods = {
            {id = CALCULATION_METHODS.ROLLING, name = "Rolling"},
            {id = CALCULATION_METHODS.FINAL, name = "Final"},
            {id = CALCULATION_METHODS.HYBRID, name = "Hybrid"}
        }
        
        for _, method in ipairs(methods) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = method.name
            info.value = method.id
            info.func = function()
                MyCombatMeterWindow:SetCalculationMethod(method.id)
                UIDropDownMenu_SetSelectedValue(methodDropdown, method.id)
                UIDropDownMenu_SetText(methodDropdown, method.name)
            end
            info.checked = (currentCalculationMethod == method.id)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    -- Store references
    meterWindow.pauseButton = pauseButton
    meterWindow.resetButton = resetButton
    meterWindow.methodDropdown = methodDropdown
end

-- =============================================================================
-- VISUAL UPDATE FUNCTIONS
-- =============================================================================

-- Update the meter visual display
function MyCombatMeterWindow:UpdateMeterDisplay()
    if not meterWindow or not meterWindow:IsVisible() then
        return
    end
    
    -- Update info labels
    meterWindow.dpsLabel:SetText(string.format("DPS: %.0f", meterState.currentDPS))
    meterWindow.hpsLabel:SetText(string.format("HPS: %.0f", meterState.currentHPS))
    meterWindow.peakDPSLabel:SetText(string.format("Peak: %.0f", meterState.peakDPS))
    meterWindow.peakHPSLabel:SetText(string.format("Peak: %.0f", meterState.peakHPS))
    
    -- Update combat time
    if meterState.inCombat and meterState.combatStartTime > 0 then
        local elapsed = GetTime() - meterState.combatStartTime
        meterWindow.timeLabel:SetText(string.format("Combat: %.0fs", elapsed))
    else
        meterWindow.timeLabel:SetText("Combat: --")
    end
    
    -- Update method display
    local methodNames = {
        [CALCULATION_METHODS.ROLLING] = "Rolling",
        [CALCULATION_METHODS.FINAL] = "Final",
        [CALCULATION_METHODS.HYBRID] = "Hybrid"
    }
    meterWindow.methodLabel:SetText("Method: " .. (methodNames[currentCalculationMethod] or "Unknown"))
    
    -- Update meter segments
    self:UpdateMeterSegments()
end

-- Update the visual meter segments
function MyCombatMeterWindow:UpdateMeterSegments()
    local maxDPS = math.max(meterState.peakDPS, meterState.scale)
    local maxHPS = math.max(meterState.peakHPS, meterState.scale)
    
    for i = 1, meterState.segmentCount do
        local segment = meterSegments[i]
        if not segment then break end
        
        local segmentThreshold = segment.level
        
        -- Update DPS segment
        if segment.dps then
            local dpsRatio = maxDPS > 0 and (meterState.currentDPS / maxDPS) or 0
            if dpsRatio >= segmentThreshold then
                segment.dps:SetText("██")
                -- Color intensity based on how much we exceed threshold
                local intensity = math.min(1, (dpsRatio - segmentThreshold) * 2 + 0.3)
                segment.dps:SetTextColor(1, intensity * 0.5, intensity * 0.5)
            else
                segment.dps:SetText("░░")
                segment.dps:SetTextColor(0.3, 0.3, 0.3)
            end
        end
        
        -- Update HPS segment
        if segment.hps then
            local hpsRatio = maxHPS > 0 and (meterState.currentHPS / maxHPS) or 0
            if hpsRatio >= segmentThreshold then
                segment.hps:SetText("██")
                -- Color intensity based on how much we exceed threshold
                local intensity = math.min(1, (hpsRatio - segmentThreshold) * 2 + 0.3)
                segment.hps:SetTextColor(intensity * 0.5, 1, intensity * 0.5)
            else
                segment.hps:SetText("░░")
                segment.hps:SetTextColor(0.3, 0.3, 0.3)
            end
        end
    end
end

-- =============================================================================
-- PUBLIC INTERFACE
-- =============================================================================

function MyCombatMeterWindow:Show()
    if not meterWindow then
        self:CreateWindow()
        -- Set up message queue subscriptions after window creation
        self:SetupSubscriptions()
    end
    
    meterWindow:Show()
    isVisible = true
    
    -- Start listening for combat events (this is now a no-op since we use message queue)
    self:RegisterForCombatEvents()
    
    -- Initial display update
    self:UpdateMeterDisplay()
    
    addon:Debug("Combat meter window shown")
end

function MyCombatMeterWindow:Hide()
    if meterWindow then
        meterWindow:Hide()
    end
    
    isVisible = false
    
    -- Stop listening for combat events
    self:UnregisterFromCombatEvents()
    
    -- Clean up any pending timers
    if meterState.refreshTimer then
        meterState.refreshTimer:Cancel()
        meterState.refreshTimer = nil
    end
    
    addon:Debug("Combat meter window hidden")
end

function MyCombatMeterWindow:Toggle()
    if isVisible then
        self:Hide()
    else
        self:Show()
    end
end

function MyCombatMeterWindow:IsVisible()
    return isVisible and meterWindow and meterWindow:IsVisible()
end

-- =============================================================================
-- CONFIGURATION FUNCTIONS
-- =============================================================================

function MyCombatMeterWindow:SetCalculationMethod(method)
    if CALCULATION_METHODS[method:upper()] then
        currentCalculationMethod = CALCULATION_METHODS[method:upper()]
        addon:Debug("Combat meter: Calculation method set to %s", method)
        
        if meterWindow and meterWindow:IsVisible() then
            self:UpdateMeterDisplay()
        end
        
        return true
    end
    
    return false
end

function MyCombatMeterWindow:GetCalculationMethod()
    return currentCalculationMethod
end

function MyCombatMeterWindow:TogglePause()
    meterState.isPaused = not meterState.isPaused
    
    if meterWindow and meterWindow.pauseButton then
        meterWindow.pauseButton:SetText(meterState.isPaused and "Resume" or "Pause")
    end
    
    addon:Debug("Combat meter: %s", meterState.isPaused and "Paused" or "Resumed")
end

function MyCombatMeterWindow:ResetMeter()
    meterState.currentDPS = 0
    meterState.currentHPS = 0
    meterState.peakDPS = 0
    meterState.peakHPS = 0
    meterState.totalDamage = 0
    meterState.totalHealing = 0
    
    -- Clear ring buffer
    eventRingBuffer.size = 0
    eventRingBuffer.writeIndex = 1
    
    if meterWindow and meterWindow:IsVisible() then
        self:UpdateMeterDisplay()
    end
    
    addon:Debug("Combat meter: Reset")
end

function MyCombatMeterWindow:SetScale(newScale)
    meterState.scale = math.max(100, newScale) -- Minimum scale of 100
    
    if meterWindow and meterWindow:IsVisible() then
        self:UpdateMeterDisplay()
    end
    
    addon:Debug("Combat meter: Scale set to %.0f", meterState.scale)
end

function MyCombatMeterWindow:GetScale()
    return meterState.scale
end

-- =============================================================================
-- EVENT REGISTRATION (Placeholder for message queue integration)
-- =============================================================================

function MyCombatMeterWindow:RegisterForCombatEvents()
    -- TODO: Subscribe to combat events via message queue
    -- addon.LogMessageQueue:Subscribe("COMBAT_EVENT", self.ProcessCombatEvent)
    -- addon.LogMessageQueue:Subscribe("COMBAT_STATE", self.UpdateCombatState)
    addon:Debug("Combat meter: Registered for combat events (placeholder)")
end

function MyCombatMeterWindow:UnregisterFromCombatEvents()
    -- TODO: Unsubscribe from combat events
    addon:Debug("Combat meter: Unregistered from combat events (placeholder)")
end

-- =============================================================================
-- DEBUG AND MONITORING
-- =============================================================================

function MyCombatMeterWindow:GetMeterStats()
    return {
        -- Current state
        inCombat = meterState.inCombat,
        isPaused = meterState.isPaused,
        currentDPS = meterState.currentDPS,
        currentHPS = meterState.currentHPS,
        peakDPS = meterState.peakDPS,
        peakHPS = meterState.peakHPS,
        
        -- Configuration
        calculationMethod = currentCalculationMethod,
        scale = meterState.scale,
        segmentCount = meterState.segmentCount,
        
        -- Performance
        throttleMode = performanceState.throttleMode,
        refreshInterval = GetRefreshInterval(),
        bufferSize = eventRingBuffer.size,
        bufferCapacity = eventRingBuffer.capacity,
        pendingCalculation = performanceState.pendingCalculation,
        
        -- Combat tracking
        combatDuration = meterState.inCombat and (GetTime() - meterState.combatStartTime) or 0,
        totalDamage = meterState.totalDamage,
        totalHealing = meterState.totalHealing,
    }
end

return MyCombatMeterWindow