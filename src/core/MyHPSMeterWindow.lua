-- MyHPSMeterWindow.lua  
-- Real-time HPS meter with decoupled message queue architecture
--
-- PERFORMANCE DESIGN:
-- - Ring buffer for recent combat events (30 second window)
-- - Rate-limited UI updates (max 4 FPS during combat)
-- - Lightweight FontString-based 20-segment display
-- - Memory-bounded calculations with automatic cleanup
-- - Combat-aware performance scaling

local addonName, addon = ...

-- =============================================================================
-- HPS METER WINDOW MODULE
-- =============================================================================

local MyHPSMeterWindow = {}
addon.MyHPSMeterWindow = MyHPSMeterWindow

-- =============================================================================
-- CONSTANTS AND CONFIGURATION
-- =============================================================================

local WINDOW_WIDTH = 300  -- Compact horizontal layout  
local WINDOW_HEIGHT = 85  -- Minimal height for HPS-focused display
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

-- HPS meter state (DPS removed - focused on HPS only)
local meterState = {
    currentHPS = 0,
    peakHPS = 0,
    combatStartTime = 0,
    inCombat = false,
    totalHealing = 0,
    scale = 300000,  -- Current scale value (lower default for HPS)
    autoScale = 300000,  -- Auto-calculated scale
    manualScale = 300000,  -- User-specified scale
    useAutoScale = true,  -- Toggle between auto/manual
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

function MyHPSMeterWindow:Initialize()
    -- Set up message queue subscription for combat events
    -- Note: We delay subscriptions until after the window is created
    addon:Info("MyHPSMeterWindow: Initialize called - subscriptions will be set up after window creation")
end

function MyHPSMeterWindow:SetupSubscriptions()
    -- This is called after the window is created to ensure the message queue instance is ready
    addon:Debug("MyHPSMeterWindow:SetupSubscriptions - setting up message queue subscriptions")
    
    -- Debug: Check if CombatEventQueue exists
    if not addon.CombatEventQueue then
        addon:Warn("MyHPSMeterWindow: CombatEventQueue is nil!")
        return
    end
    
    if not addon.CombatEventQueue.Subscribe then
        addon:Warn("MyHPSMeterWindow: CombatEventQueue.Subscribe method not found!")
        return
    end
    
    addon:Debug("MyHPSMeterWindow: CombatEventQueue found, setting up subscriptions...")
    
    if addon.CombatEventQueue and addon.CombatEventQueue.Subscribe then
        -- Subscribe to combat state changes
        self.combatStateSubscriberId = addon.CombatEventQueue:Subscribe(
            "COMBAT_STATE_CHANGED", 
            function(message)
                self:UpdateCombatState(message.data)
            end,
            "HPSMeterWindow_StateTracker"
        )
        
        -- Subscribe to healing events
        self.healSubscriberId = addon.CombatEventQueue:Subscribe(
            "HEAL_EVENT", 
            function(message)
                local eventData = message.data
                
                -- Validate event data to prevent integer overflow
                if not eventData or not eventData.amount then
                    addon:Trace("MyHPSMeterWindow: Invalid healing event data")
                    return
                end
                
                local amount = eventData.amount
                if type(amount) ~= "number" or amount < 0 or amount > 2147483647 then -- Max 32-bit int
                    addon:Warn("MyHPSMeterWindow: Invalid healing amount: %s (type: %s)", tostring(amount), type(amount))
                    return
                end
                
                addon:Trace("MyHPSMeterWindow: Received HEAL_EVENT, amount: %d", amount)
                self:ProcessCombatEvent({
                    type = "HEAL",
                    amount = amount,
                    timestamp = eventData.timestamp or GetTime(),
                    source = eventData.source,
                    target = eventData.target,
                    sourceFlags = eventData.sourceFlags
                })
            end,
            "HPSMeterWindow_HealTracker"
        )
        
        -- HPS meter focuses only on healing events (no damage subscription)
        
        addon:Info("MyHPSMeterWindow: Combat event queue subscriptions established")
        addon:Debug("Subscriber IDs: State=%d, Heal=%d", 
            self.combatStateSubscriberId, self.healSubscriberId)
    else
        addon:Error("MyHPSMeterWindow: Failed to subscribe to CombatEventQueue")
    end
end

-- Subscribe to scale updates from the scaler
function MyHPSMeterWindow:SubscribeToScaleUpdates()
    if addon.UIEventQueue then
        addon.UIEventQueue:Subscribe("SCALE_UPDATE", function(message)
            addon:Info("MyHPSMeterWindow: Received SCALE_UPDATE event")
            if message.data then
                local dpsScale = message.data.dpsScale
                local hpsScale = message.data.hpsScale
                
                addon:Info("MyHPSMeterWindow: Scale event data - DPS: %.0f, HPS: %.0f", dpsScale or 0, hpsScale or 0)
                
                if hpsScale and hpsScale > 0 then
                    meterState.autoScale = hpsScale
                    
                    if meterState.useAutoScale then
                        local oldScale = meterState.scale
                        meterState.scale = hpsScale
                        addon:Info("MyHPSMeterWindow: Scale updated via event from %.0f to %.0f", oldScale, hpsScale)
                        
                        -- Update display if window is visible
                        if meterWindow and meterWindow:IsVisible() then
                            self:UpdateMeterDisplay()
                            addon:Info("MyHPSMeterWindow: Display updated")
                        else
                            addon:Info("MyHPSMeterWindow: Window not visible, display not updated")
                        end
                    else
                        addon:Info("MyHPSMeterWindow: Auto-scale disabled, ignoring scale update")
                    end
                else
                    addon:Info("MyHPSMeterWindow: Invalid HPS scale value received")
                end
            else
                addon:Info("MyHPSMeterWindow: Scale event missing data")
            end
        end, "HPSMeterWindow")
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

-- Process combat event for HPS calculation
function MyHPSMeterWindow:ProcessCombatEvent(eventData)
    -- Safety check to prevent infinite loops during startup
    if not meterWindow then
        addon:Debug("MyHPSMeterWindow: Ignoring event - window not created yet")
        return
    end
    
    -- Only process healing events
    if eventData.type ~= "HEAL" then
        return
    end
    
    -- PHASE 1: STRICT PLAYER-ONLY FILTERING (will undercount, but be accurate)
    local playerGUID = UnitGUID("player")
    local isPlayerHealing = eventData.source == playerGUID
    
    -- Ownership decoration for debugging
    local ownershipInfo = "UNKNOWN"
    if eventData.sourceFlags then
        local COMBATLOG_OBJECT_AFFILIATION_MINE = 0x00000001
        local COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
        local COMBATLOG_OBJECT_TYPE_PET = 0x00001000
        local COMBATLOG_OBJECT_TYPE_GUARDIAN = 0x00002000
        
        local isMine = bit.band(eventData.sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0
        local isPlayer = bit.band(eventData.sourceFlags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0
        local isPet = bit.band(eventData.sourceFlags, COMBATLOG_OBJECT_TYPE_PET) ~= 0
        local isGuardian = bit.band(eventData.sourceFlags, COMBATLOG_OBJECT_TYPE_GUARDIAN) ~= 0
        
        if isPlayer then
            ownershipInfo = isMine and "MY_PLAYER" or "OTHER_PLAYER"
        elseif isPet then
            ownershipInfo = isMine and "MY_PET" or "OTHER_PET"
        elseif isGuardian then
            ownershipInfo = isMine and "MY_GUARDIAN" or "OTHER_GUARDIAN"
        else
            ownershipInfo = isMine and "MY_OTHER" or "OTHER_ENTITY"
        end
    end
    
    -- Debug log with ownership decoration
    addon:Debug("MyHPSMeterWindow: Event analysis - Source: %s, Player: %s, Ownership: %s, Flags: 0x%08X, Amount: %s", 
        tostring(eventData.source), tostring(playerGUID), ownershipInfo, eventData.sourceFlags or 0, tostring(eventData.amount))
    
    -- PHASE 1: Only accept direct player healing (strict filtering)
    if not isPlayerHealing then
        addon:Debug("MyHPSMeterWindow: FILTERED OUT - Phase 1 strict player-only mode (source: %s, ownership: %s)", 
            tostring(eventData.source), ownershipInfo)
        return
    end
    
    -- PHASE 2: Pet/Guardian ownership detection (disabled for now)
    -- TODO: Uncomment this section for Phase 2 to include player-owned pets/guardians
    --[[
    local isPlayerOwnedUnit = false
    if not isPlayerHealing and eventData.sourceFlags then
        local COMBATLOG_OBJECT_AFFILIATION_MINE = 0x00000001
        isPlayerOwnedUnit = bit.band(eventData.sourceFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0
    end
    
    if not (isPlayerHealing or isPlayerOwnedUnit) then
        addon:Debug("MyHPSMeterWindow: FILTERED OUT - not from player or player's units (source: %s, ownership: %s)", 
            tostring(eventData.source), ownershipInfo)
        return
    end
    --]]
    
    addon:Debug("MyHPSMeterWindow:ProcessCombatEvent - ACCEPTED player healing: amount=%s, ownership=%s", 
        tostring(eventData.amount), ownershipInfo)
    
    local currentTime = GetTime()
    
    -- Add to performance tracking
    table.insert(performanceState.recentEventTimes, currentTime)
    
    -- Update performance mode
    UpdateThrottleMode()
    
    -- Add to ring buffer for calculations
    AddEventToBuffer({
        amount = eventData.amount,
        timestamp = currentTime,
        source = eventData.source,
        target = eventData.target
    })
    
    -- Sanity check for reasonable healing values (prevent overflow)
    local healing = eventData.amount
    if healing > 5000000 then -- 5M healing seems unreasonable for a single heal
        addon:Warn("MyHPSMeterWindow: Suspicious healing amount: %d, capping at 5M", healing)
        healing = 5000000
    end
    
    -- Update total healing
    meterState.totalHealing = meterState.totalHealing + healing
    addon:Debug("MyHPSMeterWindow: Added player healing %d, total now: %d", healing, meterState.totalHealing)
    
    -- Schedule display update if not already pending
    if not performanceState.pendingCalculation then
        performanceState.pendingCalculation = true
        local refreshInterval = GetRefreshInterval()
        
        C_Timer.After(refreshInterval / 1000, function()
            performanceState.pendingCalculation = false
            self:UpdateMeterDisplay()
        end)
    end
end

-- Calculate current HPS based on selected method
function MyHPSMeterWindow:CalculateCurrentHPS()
    if not meterState.inCombat then
        return 0
    end
    
    local currentTime = GetTime()
    local method = currentCalculationMethod
    
    if method == CALCULATION_METHODS.ROLLING then
        -- Rolling average over last 30 seconds
        local recentEvents = GetRecentEvents(PERFORMANCE_CONFIG.CALCULATION_WINDOW)
        local totalHealing = 0
        
        for _, event in ipairs(recentEvents) do
            totalHealing = totalHealing + event.amount
        end
        
        return totalHealing / PERFORMANCE_CONFIG.CALCULATION_WINDOW
        
    elseif method == CALCULATION_METHODS.FINAL then
        -- Final HPS (total / combat duration)
        local combatDuration = currentTime - meterState.combatStartTime
        if combatDuration > 0 then
            return meterState.totalHealing / combatDuration
        end
        return 0
        
    elseif method == CALCULATION_METHODS.HYBRID then
        -- Hybrid: rolling for first 30s, then final
        local combatDuration = currentTime - meterState.combatStartTime
        if combatDuration <= PERFORMANCE_CONFIG.CALCULATION_WINDOW then
            -- Use rolling for short fights
            return self:CalculateCurrentHPS_Rolling()
        else
            -- Use final for longer fights
            return meterState.totalHealing / combatDuration
        end
    end
    
    return 0
end

-- Helper for rolling calculation
function MyHPSMeterWindow:CalculateCurrentHPS_Rolling()
    local recentEvents = GetRecentEvents(PERFORMANCE_CONFIG.CALCULATION_WINDOW)
    local totalHealing = 0
    
    for _, event in ipairs(recentEvents) do
        totalHealing = totalHealing + event.amount
    end
    
    return totalHealing / PERFORMANCE_CONFIG.CALCULATION_WINDOW
end

-- =============================================================================
-- COMBAT STATE MANAGEMENT
-- =============================================================================

-- Update combat state based on message queue events
function MyHPSMeterWindow:UpdateCombatState(stateData)
    if stateData.inCombat then
        self:StartCombat(stateData.startTime)
    else
        self:EndCombat()
    end
end

-- Start combat tracking
function MyHPSMeterWindow:StartCombat(startTime)
    meterState.inCombat = true
    meterState.combatStartTime = startTime or GetTime()
    meterState.totalHealing = 0
    meterState.currentHPS = 0
    meterState.peakHPS = 0
    
    -- Clear ring buffer
    eventRingBuffer.events = {}
    eventRingBuffer.writeIndex = 1
    eventRingBuffer.size = 0
    eventRingBuffer.totalWritten = 0
    
    -- Clear performance tracking
    performanceState.recentEventTimes = {}
    performanceState.throttleMode = "combat"
    
    addon:Debug("MyHPSMeterWindow: Combat started")
    self:UpdateMeterDisplay()
end

-- End combat tracking
function MyHPSMeterWindow:EndCombat()
    meterState.inCombat = false
    
    -- Clean up refresh timer
    if meterState.refreshTimer then
        meterState.refreshTimer:Cancel()
        meterState.refreshTimer = nil
    end
    
    performanceState.pendingCalculation = false
    performanceState.throttleMode = "normal"
    
    -- Final calculation for end-of-combat display (match DPS meter behavior)
    if meterState.combatStartTime > 0 then
        local combatDuration = meterState.lastUpdateTime - meterState.combatStartTime
        if combatDuration > 0 then
            local finalHPS = meterState.totalHealing / combatDuration
            
            meterState.currentHPS = finalHPS
            
            -- Delegate scaling to MyCombatMeterScaler (match DPS meter)
            if meterState.useAutoScale and addon.MyCombatMeterScaler then
                addon:Info("HPS meter: Combat ended - Peak: %.0f, Final: %.0f, Duration: %.1fs", 
                    meterState.peakHPS, finalHPS, combatDuration)
                
                -- Let MyCombatMeterScaler handle all scaling logic
                -- Scale updates will come via UI event subscription
                addon.MyCombatMeterScaler:AutoUpdateAfterCombat({
                    duration = combatDuration,
                    peakHPS = meterState.peakHPS,
                    totalHealing = meterState.totalHealing
                })
            end
            
            -- Always update display after combat
            if meterWindow and meterWindow:IsVisible() then
                self:UpdateMeterDisplay()
            end
            
            addon:Debug("HPS meter: Combat ended - Final HPS: %.0f", finalHPS)
        end
    end
end

-- =============================================================================
-- UI CREATION AND MANAGEMENT
-- =============================================================================

-- Create the main HPS meter window
function MyHPSMeterWindow:CreateWindow()
    if meterWindow then return end
    
    addon:Debug("Starting HPS meter window creation...")
    
    -- Subscribe to scale updates from the scaler
    self:SubscribeToScaleUpdates()
    
    -- Request initial scale from scaler (delayed to ensure scaler is fully initialized)
    C_Timer.After(0.5, function()
        if addon.MyCombatMeterScaler then
            addon:Info("MyHPSMeterWindow: Requesting initial scale from scaler...")
            addon.MyCombatMeterScaler:RequestCurrentScale()
            addon:Info("MyHPSMeterWindow: Initial scale request completed")
        else
            addon:Warn("MyHPSMeterWindow: MyCombatMeterScaler not available for initial scale request")
        end
    end)
    
    -- Create custom frame without default WoW template
    meterWindow = CreateFrame("Frame", addonName .. "HPSMeterWindow", UIParent, BackdropTemplateMixin and "BackdropTemplate")
    addon:Debug("Base frame created")
    
    -- Set size and initial position
    meterWindow:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    meterWindow:SetPoint("CENTER", UIParent, "CENTER", 200, 100) -- Offset from DPS meter
    
    -- Create solid black background texture (match DPS meter)
    local bg = meterWindow:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(meterWindow)
    bg:SetColorTexture(0, 0, 0, 0.85) -- Solid black, 85% opacity
    meterWindow.bg = bg
    
    -- Add subtle border frame (match DPS meter)
    meterWindow:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    meterWindow:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    
    -- Make movable
    meterWindow:SetMovable(true)
    meterWindow:EnableMouse(true)
    meterWindow:RegisterForDrag("LeftButton")
    meterWindow:SetScript("OnDragStart", meterWindow.StartMoving)
    meterWindow:SetScript("OnDragStop", meterWindow.StopMovingOrSizing)
    
    -- Set up window elements
    self:CreateMeterElements(meterWindow)
    self:SetupSubscriptions()
    
    -- Register with FocusManager with higher strata to prevent overlap
    if addon.FocusManager then
        addon.FocusManager:RegisterWindow(meterWindow, nil, "HIGH")
    end
    
    -- Start hidden
    meterWindow:Hide()
    isVisible = false
    
    addon:Debug("HPS meter window creation complete")
end

-- Create meter visual elements
function MyHPSMeterWindow:CreateMeterElements(parent)
    -- Create progress bar at top (match DPS meter)
    self:CreateProgressBar(parent)
    
    -- Create info display
    self:CreateInfoDisplay(parent)
end

-- Create horizontal progress bar (match DPS meter)
function MyHPSMeterWindow:CreateProgressBar(parent)
    local barHeight = 8
    local segmentCount = 25
    local barFrame = CreateFrame("Frame", nil, parent)
    barFrame:SetHeight(barHeight)
    barFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
    barFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -5)
    
    -- Store segments for updating
    meterSegments = {}
    
    local segmentWidth = (WINDOW_WIDTH - 10) / segmentCount
    for i = 1, segmentCount do
        local segment = barFrame:CreateTexture(nil, "ARTWORK")
        segment:SetHeight(barHeight)
        segment:SetWidth(segmentWidth - 2) -- 2px gap between segments
        segment:SetPoint("LEFT", barFrame, "LEFT", (i-1) * segmentWidth + 1, 0)
        segment:SetTexture("Interface\\Buttons\\WHITE8X8")
        segment:SetVertexColor(0.2, 0.2, 0.2, 1) -- Dark gray when empty
        
        meterSegments[i] = segment
    end
    
    meterWindow.progressSegments = meterSegments
    meterWindow.progressBar = barFrame
end

-- Create info display
function MyHPSMeterWindow:CreateInfoDisplay(parent)
    -- Create custom font object for main HPS value (match DPS meter)
    local customFont = CreateFont("MyHPSMeterFont")
    customFont:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 28, "OUTLINE")
    
    -- Main HPS value (large, custom font, left side) - match DPS meter
    local hpsLabel = parent:CreateFontString(nil, "OVERLAY")
    hpsLabel:SetFontObject(customFont)
    hpsLabel:SetPoint("LEFT", parent, "LEFT", 10, 5)
    hpsLabel:SetTextColor(1, 1, 1) -- Pure white to match DPS meter
    hpsLabel:SetText("0")
    parent.hpsLabel = hpsLabel
    
    -- Scale info (clickable, bottom left after peak) - match DPS meter
    local scaleButton = CreateFrame("Button", nil, parent)
    scaleButton:SetSize(100, 20)
    scaleButton:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 22)
    
    local scaleLabel = scaleButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleLabel:SetAllPoints(scaleButton)
    scaleLabel:SetJustifyH("LEFT")
    scaleLabel:SetTextColor(0.4, 0.8, 0.8) -- Cyan/teal to match DPS meter
    scaleLabel:SetText("300K (auto)")
    parent.scaleLabel = scaleLabel
    
    -- Scale cycling on click
    scaleButton:SetScript("OnClick", function()
        self:CycleScale()
    end)
    
    -- Hover effect
    scaleButton:SetScript("OnEnter", function()
        scaleLabel:SetTextColor(0.6, 1, 1) -- Brighter cyan on hover to match DPS meter
    end)
    scaleButton:SetScript("OnLeave", function()
        scaleLabel:SetTextColor(0.4, 0.8, 0.8) -- Cyan/teal to match DPS meter
    end)
    
    -- Method label (clickable, bottom right)
    local methodButton = CreateFrame("Button", nil, parent)
    methodButton:SetSize(60, 20)
    methodButton:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 8)
    
    local methodLabel = methodButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    methodLabel:SetAllPoints(methodButton)
    methodLabel:SetTextColor(0.7, 0.7, 0.7) -- Start with gray
    methodLabel:SetText("Rolling")
    parent.methodLabel = methodLabel
    
    -- Method cycling on click
    methodButton:SetScript("OnClick", function()
        self:CycleMethod()
    end)
    
    -- Hover effect
    methodButton:SetScript("OnEnter", function()
        methodLabel:SetTextColor(1, 1, 1)
    end)
    methodButton:SetScript("OnLeave", function()
        if meterState.inCombat then
            methodLabel:SetTextColor(1, 0.6, 0.6) -- Reddish when in combat
        else
            methodLabel:SetTextColor(0.7, 0.7, 0.7) -- Gray when out of combat (match DPS meter)
        end
    end)
    
    -- Peak HPS (smaller, bottom left) - match DPS meter
    local peakLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    peakLabel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 8)
    peakLabel:SetTextColor(0.8, 0.8, 0.8) -- Match DPS meter gray
    peakLabel:SetText("0 peak")
    parent.peakLabel = peakLabel
    
    -- "HPS" label (right side of main value) - light green/teal for healing
    local typeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    typeLabel:SetPoint("RIGHT", parent, "RIGHT", -10, 15)
    typeLabel:SetTextColor(0.4, 1, 0.8) -- Light green/teal for healing
    typeLabel:SetText("HPS")
    parent.typeLabel = typeLabel
end

-- =============================================================================
-- DISPLAY UPDATE FUNCTIONS
-- =============================================================================

-- Update the meter display
function MyHPSMeterWindow:UpdateMeterDisplay()
    if not meterWindow or not meterWindow:IsVisible() then
        return
    end
    
    -- Calculate current HPS
    local currentHPS = self:CalculateCurrentHPS()
    meterState.currentHPS = currentHPS
    
    -- Update peak
    if currentHPS > meterState.peakHPS then
        meterState.peakHPS = currentHPS
    end
    
    -- Update HPS display
    local hpsText = self:FormatNumber(currentHPS)
    meterWindow.hpsLabel:SetText(hpsText)
    
    -- Update peak display
    local peakText = self:FormatNumber(meterState.peakHPS) .. " peak"
    meterWindow.peakLabel:SetText(peakText)
    
    -- Update scale display
    local scaleText = self:FormatNumber(meterState.scale)
    if meterState.useAutoScale then
        scaleText = scaleText .. " (auto)"
    else
        scaleText = scaleText .. " (manual)"
    end
    meterWindow.scaleLabel:SetText(scaleText)
    
    -- Update progress bar
    self:UpdateProgressBar()
    
    -- Update method label color based on combat state (match DPS meter exactly)
    if meterState.inCombat then
        meterWindow.methodLabel:SetTextColor(1, 0.6, 0.6) -- Reddish when in combat
    else
        meterWindow.methodLabel:SetTextColor(0.7, 0.7, 0.7) -- Gray when out of combat (match DPS meter)
    end
end

-- Update the progress bar (match DPS meter style)
function MyHPSMeterWindow:UpdateProgressBar()
    if not meterWindow.progressSegments then return end
    
    local fillRatio = 0
    if meterState.scale > 0 then
        fillRatio = math.min(1, meterState.currentHPS / meterState.scale)
    end
    
    local segmentCount = #meterWindow.progressSegments
    local filledSegments = math.floor(fillRatio * segmentCount)
    
    for i = 1, segmentCount do
        local segment = meterWindow.progressSegments[i]
        if i <= filledSegments then
            -- Color gradient: green -> yellow -> orange -> red (like DPS meter but green-based)
            local segmentRatio = i / segmentCount
            local r, g, b = 0, 1, 0 -- Start green
            
            if segmentRatio > 0.75 then
                -- Yellow-green zone (overhealing)
                r, g, b = 0.8, 1, 0.2
            elseif segmentRatio > 0.5 then
                -- Bright green zone
                r, g, b = 0.2, 1, 0.2
            elseif segmentRatio > 0.25 then
                -- Medium green zone
                r, g, b = 0, 0.8, 0
            end
            
            segment:SetVertexColor(r, g, b, 1)
        else
            -- Empty segment
            segment:SetVertexColor(0.2, 0.2, 0.2, 1)
        end
    end
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

-- Format numbers for display
function MyHPSMeterWindow:FormatNumber(number)
    if number >= 1000000 then
        return string.format("%.1fM", number / 1000000)
    elseif number >= 1000 then
        return string.format("%.1fK", number / 1000)
    else
        return string.format("%.0f", number)
    end
end

-- Cycle between calculation methods
function MyHPSMeterWindow:CycleMethod()
    if currentCalculationMethod == CALCULATION_METHODS.ROLLING then
        currentCalculationMethod = CALCULATION_METHODS.FINAL
        meterWindow.methodLabel:SetText("Final")
    elseif currentCalculationMethod == CALCULATION_METHODS.FINAL then
        currentCalculationMethod = CALCULATION_METHODS.HYBRID
        meterWindow.methodLabel:SetText("Hybrid")
    else
        currentCalculationMethod = CALCULATION_METHODS.ROLLING
        meterWindow.methodLabel:SetText("Rolling")
    end
    
    addon:Info("HPS calculation method changed to: %s", currentCalculationMethod)
    self:UpdateMeterDisplay()
end

-- Cycle between auto and manual scaling
function MyHPSMeterWindow:CycleScale()
    if meterState.useAutoScale then
        meterState.useAutoScale = false
        meterState.scale = meterState.manualScale
        addon:Info("HPS meter switched to manual scaling: %.0f", meterState.scale)
    else
        meterState.useAutoScale = true
        meterState.scale = meterState.autoScale
        addon:Info("HPS meter switched to auto-scaling: %.0f", meterState.scale)
    end
    
    self:UpdateMeterDisplay()
end

-- =============================================================================
-- PUBLIC API
-- =============================================================================

-- Show/Hide functions
function MyHPSMeterWindow:Show()
    if not meterWindow then
        self:CreateWindow()
    end
    
    meterWindow:Show()
    isVisible = true
    self:UpdateMeterDisplay()
    addon:Debug("HPS meter window shown")
end

function MyHPSMeterWindow:Hide()
    if meterWindow then
        meterWindow:Hide()
        isVisible = false
        addon:Debug("HPS meter window hidden")
    end
end

function MyHPSMeterWindow:Toggle()
    if isVisible then
        self:Hide()
    else
        self:Show()
    end
end

function MyHPSMeterWindow:IsVisible()
    return isVisible and meterWindow and meterWindow:IsVisible()
end

-- Configuration functions
function MyHPSMeterWindow:SetCalculationMethod(method)
    if CALCULATION_METHODS[method:upper()] then
        currentCalculationMethod = CALCULATION_METHODS[method:upper()]
        if meterWindow and meterWindow.methodLabel then
            meterWindow.methodLabel:SetText(method:gsub("^%l", string.upper))
        end
        addon:Info("HPS calculation method set to: %s", method)
        self:UpdateMeterDisplay()
        return true
    end
    return false
end

function MyHPSMeterWindow:SetAutoScale(enabled)
    meterState.useAutoScale = enabled
    if enabled then
        meterState.scale = meterState.autoScale
    else
        meterState.scale = meterState.manualScale
    end
    self:UpdateMeterDisplay()
end

function MyHPSMeterWindow:SetManualScale(scale)
    meterState.manualScale = scale
    meterState.useAutoScale = false
    meterState.scale = scale
    self:UpdateMeterDisplay()
end

-- Position management
function MyHPSMeterWindow:GetPosition()
    if not meterWindow then return nil end
    
    local point, relativeTo, relativePoint, xOfs, yOfs = meterWindow:GetPoint()
    return {
        point = point,
        relativePoint = relativePoint,
        xOffset = xOfs,
        yOffset = yOfs
    }
end

function MyHPSMeterWindow:RestorePosition(position)
    if not meterWindow or not position then return end
    
    meterWindow:ClearAllPoints()
    meterWindow:SetPoint(
        position.point or "CENTER",
        UIParent,
        position.relativePoint or "CENTER",
        position.xOffset or 0,
        position.yOffset or 0
    )
end

-- Debug and status functions
function MyHPSMeterWindow:GetDebugInfo()
    return {
        isVisible = isVisible,
        inCombat = meterState.inCombat,
        currentHPS = meterState.currentHPS,
        peakHPS = meterState.peakHPS,
        totalHealing = meterState.totalHealing,
        scale = meterState.scale,
        useAutoScale = meterState.useAutoScale,
        calculationMethod = currentCalculationMethod,
        ringBufferSize = eventRingBuffer.size,
        throttleMode = performanceState.throttleMode
    }
end

return MyHPSMeterWindow