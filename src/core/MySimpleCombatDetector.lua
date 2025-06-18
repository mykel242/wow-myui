-- MySimpleCombatDetector.lua
-- Simple, reliable combat detection system
-- Replaces the overly complex multi-system approach

local addonName, addon = ...

-- Self-contained module with internal debugging
local MySimpleCombatDetector = {}
addon.MySimpleCombatDetector = MySimpleCombatDetector

-- Internal debug configuration
local DEBUG_MODE = false
local logger = nil -- Injected logger instance

-- Internal debug functions with logger fallback
local function debugPrint(...)
    if logger and logger.Debug then
        logger:Debug(...)
    elseif DEBUG_MODE then
        print("[MySimpleCombatDetector]", ...)
    end
end

local function infoPrint(...)
    if logger and logger.Info then
        logger:Info(...)
    else
        print("[MySimpleCombatDetector]", ...)
    end
end

local function errorPrint(...)
    if logger and logger.Error then
        logger:Error(...)
    else
        print("[MySimpleCombatDetector][ERROR]", ...)
    end
end

-- Simple configuration
local CONFIG = {
    ACTIVITY_TIMEOUT = 8.0,      -- Seconds after last activity to end combat
    CHECK_INTERVAL = 5.0,        -- How often to check for timeout
    MIN_DURATION = 10.0,         -- Minimum session duration
    MIN_EVENTS = 5,              -- Minimum meaningful events
    MIN_ACTIVITY_RATE = 0.3,     -- Minimum events per second
}

-- Combat state
local inCombat = false
local combatStartTime = nil
local lastActivityTime = nil
local currentSessionData = nil
local sessionCounter = 0
local timeoutTimer = nil

-- Performance caches
local playerGUID = nil
local playerName = nil
local groupMemberGUIDs = {} -- Cache of group member GUIDs for fast lookup
local currentInstanceType = nil -- Cache current instance type for filtering

-- Quick exit pattern - events we NEVER care about (immediate return)
-- Based on Recount's QuickExitEvents approach for maximum performance
local QUICK_EXIT_EVENTS = {
    -- Environmental and positioning events
    ["ENVIRONMENTAL_DAMAGE"] = true,
    ["SPELL_BUILDING_DAMAGE"] = true,
    ["SPELL_BUILDING_HEAL"] = true,
    
    -- Enchant and enhancement events
    ["ENCHANT_APPLIED"] = true,
    ["ENCHANT_REMOVED"] = true,
    ["SPELL_ENCHANT_APPLIED"] = true,
    ["SPELL_ENCHANT_REMOVED"] = true,
    
    -- Summon events we don't track
    ["SPELL_SUMMON"] = true,
    ["SPELL_CREATE"] = true,
    
    -- Durability and item events
    ["SPELL_DURABILITY_DAMAGE"] = true,
    ["SPELL_DURABILITY_DAMAGE_ALL"] = true,
    
    -- Cast events we don't need for session tracking
    ["SPELL_CAST_START"] = true,
    ["SPELL_CAST_SUCCESS"] = true,
    ["SPELL_CAST_FAILED"] = true,
    
    -- Aura events that create noise
    ["SPELL_AURA_APPLIED_DOSE"] = true,
    ["SPELL_AURA_REMOVED_DOSE"] = true,
    ["SPELL_AURA_REFRESH"] = true,
    ["SPELL_AURA_BROKEN"] = true,
    ["SPELL_AURA_BROKEN_SPELL"] = true,
    
    -- Extra attacks and procs
    ["SPELL_EXTRA_ATTACKS"] = true,
    
    -- Energize events (for session tracking, we focus on damage/healing)
    ["SPELL_ENERGIZE"] = true,
    ["SPELL_PERIODIC_ENERGIZE"] = true,
    
    -- Leech and drain events
    ["SPELL_LEECH"] = true,
    ["SPELL_PERIODIC_LEECH"] = true,
    ["SPELL_DRAIN"] = true,
    ["SPELL_PERIODIC_DRAIN"] = true,
    
    -- Misc events that add noise
    ["SPELL_INSTAKILL"] = true,
    ["DAMAGE_SHIELD"] = true,
    ["DAMAGE_SHIELD_MISSED"] = true,
}

-- Event filtering - meaningful combat events for session tracking
local MEANINGFUL_EVENTS = {
    ["SPELL_DAMAGE"] = true,
    ["SPELL_PERIODIC_DAMAGE"] = true,
    ["SPELL_HEAL"] = true,
    ["SPELL_PERIODIC_HEAL"] = true,
    ["SWING_DAMAGE"] = true,
    ["SWING_MISSED"] = true,
    ["RANGE_DAMAGE"] = true,
    ["RANGE_MISSED"] = true,
    ["SPELL_MISSED"] = true,
    ["SPELL_ABSORBED"] = true,
    ["SPELL_REFLECT"] = true,
    ["UNIT_DIED"] = true,
    ["PARTY_KILL"] = true,
    ["SPELL_INTERRUPT"] = true,
    ["SPELL_DISPEL"] = true,
    ["SPELL_STEAL"] = true,
    ["SPELL_AURA_APPLIED"] = true,  -- Only applied, not other aura noise
    ["SPELL_AURA_REMOVED"] = true,  -- Only removed, not other aura noise
}

-- Combat log object flags for entity filtering (from Recount's approach)
local COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
local COMBATLOG_OBJECT_TYPE_NPC = 0x00000800  
local COMBATLOG_OBJECT_TYPE_PET = 0x00001000
local COMBATLOG_OBJECT_TYPE_GUARDIAN = 0x00002000
local COMBATLOG_OBJECT_TYPE_OBJECT = 0x00004000

local COMBATLOG_OBJECT_CONTROL_PLAYER = 0x00000100
local COMBATLOG_OBJECT_CONTROL_NPC = 0x00000200

local COMBATLOG_OBJECT_AFFILIATION_MINE = 0x00000001
local COMBATLOG_OBJECT_AFFILIATION_PARTY = 0x00000002  
local COMBATLOG_OBJECT_AFFILIATION_RAID = 0x00000004
local COMBATLOG_OBJECT_AFFILIATION_OUTSIDER = 0x00000008

-- Irrelevant entity patterns (names that indicate unimportant entities)
local IRRELEVANT_ENTITY_PATTERNS = {
    "Totem$",           -- Totems
    "Spirit$",          -- Spirit wolves, etc.
    "Clone$",           -- Mirror images, etc.
    "Image$",           -- Mirror images
    "Reflection$",      -- Various reflections
    "Statue$",          -- Healing statues
    "Trap$",            -- Hunter traps
    "Ward$",            -- Various wards
    "Banner$",          -- Warrior banners
    "Crystal$",         -- Various crystals
    "Orb$",             -- Various orbs
    "Beacon$",          -- Light beacons
    "Portal$",          -- Portals
    "Gateway$",         -- Demonic gateways
}

-- Initialize the detector
function MySimpleCombatDetector:Initialize(injectedLogger)
    -- Inject logger and validate it exists with required methods
    assert(injectedLogger, "MySimpleCombatDetector requires a logger instance")
    assert(type(injectedLogger.Debug) == "function", "Logger must have Debug method")
    assert(type(injectedLogger.Info) == "function", "Logger must have Info method")
    assert(type(injectedLogger.Error) == "function", "Logger must have Error method")
    
    logger = injectedLogger
    
    logger:Debug("MySimpleCombatDetector Initialize() called")
    
    if self.initialized then
        debugPrint("Already initialized, skipping")
        return
    end

    -- Create event frame
    self.frame = CreateFrame("Frame", addonName .. "MySimpleCombatDetector")
    debugPrint("Event frame created")
    
    -- Register for WoW combat state events
    self.frame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entered combat
    self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Left combat
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    debugPrint("Events registered: PLAYER_REGEN_DISABLED, PLAYER_REGEN_ENABLED, COMBAT_LOG_EVENT_UNFILTERED")
    
    -- Set up event handler
    self.frame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)
    debugPrint("Event handler script set")
    
    self.initialized = true
    
    -- Cache player information for performance
    self:RefreshPlayerCache()
    
    debugPrint("Initialization complete")
end

-- Cache player and group information for performance
function MySimpleCombatDetector:RefreshPlayerCache()
    playerGUID = UnitGUID("player")
    playerName = UnitName("player")
    
    -- Cache instance information for filtering
    local name, instanceType, difficultyID, difficultyName, maxPlayers, 
          dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, LfgDungeonID = GetInstanceInfo()
    currentInstanceType = instanceType
    
    -- Clear and rebuild group member cache
    wipe(groupMemberGUIDs)
    
    if IsInGroup() then
        for i = 1, GetNumGroupMembers() do
            local unit = IsInRaid() and "raid"..i or "party"..i
            if UnitExists(unit) then
                local memberGUID = UnitGUID(unit)
                if memberGUID then
                    groupMemberGUIDs[memberGUID] = true
                end
            end
        end
    end
    
    debugPrint("Player cache refreshed: playerGUID=%s, %d group members, instance=%s", 
        playerGUID or "nil", self:TableSize(groupMemberGUIDs), currentInstanceType or "none")
end

-- Determine if an entity is relevant for combat tracking
function MySimpleCombatDetector:IsRelevantEntity(guid, name, flags)
    if not guid then
        return false
    end
    
    -- Always track players
    if flags and bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) ~= 0 then
        return true
    end
    
    -- Track player-controlled pets/guardians
    if flags and bit.band(flags, COMBATLOG_OBJECT_CONTROL_PLAYER) ~= 0 then
        return true
    end
    
    -- Track friendly/party/raid affiliated entities
    if flags then
        local affiliation = bit.band(flags, 0x0000000F) -- Affiliation mask
        if affiliation == COMBATLOG_OBJECT_AFFILIATION_MINE or
           affiliation == COMBATLOG_OBJECT_AFFILIATION_PARTY or
           affiliation == COMBATLOG_OBJECT_AFFILIATION_RAID then
            return true
        end
    end
    
    -- Filter out irrelevant entities by name pattern
    if name then
        for _, pattern in ipairs(IRRELEVANT_ENTITY_PATTERNS) do
            if string.match(name, pattern) then
                return false
            end
        end
    end
    
    -- Track NPCs in combat encounters (but not irrelevant objects)
    if flags and bit.band(flags, COMBATLOG_OBJECT_TYPE_NPC) ~= 0 then
        return true
    end
    
    -- Default: don't track objects, totems, etc.
    return false
end

-- Utility function to get table size
function MySimpleCombatDetector:TableSize(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Check if current instance type is worth tracking
function MySimpleCombatDetector:IsInstanceWorthTracking()
    -- Always track in these instances
    if currentInstanceType == "raid" or 
       currentInstanceType == "party" or 
       currentInstanceType == "scenario" then
        return true
    end
    
    -- Track world content only if in a group (world bosses, etc.)
    if currentInstanceType == "none" and IsInGroup() then
        return true
    end
    
    -- Don't track in cities, battlegrounds without configuration
    if currentInstanceType == "pvp" then
        return false -- Could be configurable later
    end
    
    -- Default: track solo world content (leveling, questing)
    return true
end

-- Main event handler
function MySimpleCombatDetector:OnEvent(event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        debugPrint("PLAYER_REGEN_DISABLED - calling StartCombat()")
        self:StartCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        debugPrint("PLAYER_REGEN_ENABLED - calling BeginCombatTimeout()")
        self:BeginCombatTimeout()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Only process combat log events if we're tracking combat
        if inCombat then
            -- Get the combat log event info properly
            local eventInfo = {CombatLogGetCurrentEventInfo()}
            self:ProcessCombatEvent(unpack(eventInfo))
        end
    end
end

-- Start a new combat session
function MySimpleCombatDetector:StartCombat()
    debugPrint("StartCombat() called")
    
    -- Cancel any existing timeout
    self:CancelTimeout()
    
    -- If already in combat, don't restart
    if inCombat then
        debugPrint("Already in combat, ignoring start")
        return
    end
    
    -- Refresh cache first to get current instance type
    self:RefreshPlayerCache()
    
    -- Check if current instance is worth tracking
    if not self:IsInstanceWorthTracking() then
        debugPrint("Instance type '%s' not worth tracking, ignoring combat", currentInstanceType or "unknown")
        return
    end
    
    -- Start MyTimestampManager combat tracking
    if addon.MyTimestampManager then
        -- Get the current combat log timestamp for proper timing
        local logTimestamp = select(1, CombatLogGetCurrentEventInfo())
        addon.MyTimestampManager:StartCombat(logTimestamp)
        combatStartTime = addon.MyTimestampManager:GetTimestampData().combatStartTime
    else
        combatStartTime = GetTime()
    end
    
    -- Generate simplified session ID (realm/character are implicit in WTF storage)
    sessionCounter = sessionCounter + 1
    local timestamp = math.floor(combatStartTime * 1000) -- Convert to milliseconds for precision
    
    -- Create shorter, more readable session ID: timestamp-counter
    local baseId = string.format("%d-%03d", timestamp, sessionCounter)
    
    -- Generate checksum for validation (simple hash of the base ID)
    local checksum = 0
    for i = 1, #baseId do
        checksum = checksum + string.byte(baseId, i)
    end
    checksum = checksum % 1000 -- Keep it to 3 digits
    
    local sessionId = string.format("%s-%03d", baseId, checksum)
    
    -- Initialize combat state
    inCombat = true
    lastActivityTime = combatStartTime
    
    -- Create session data structure with GUID mapping
    currentSessionData = {
        id = sessionId,
        startTime = combatStartTime,
        endTime = nil,
        eventCount = 0,
        events = {},
        guidMap = {},  -- GUID -> name mapping for efficient storage
        zone = GetZoneText() or "Unknown",
        instance = GetInstanceInfo() or GetZoneText() or "Unknown",
        player = playerName or "Unknown",
        playerClass = UnitClass("player") or "Unknown",
        playerLevel = UnitLevel("player") or 80,
        groupType = IsInRaid() and "raid" or IsInGroup() and "party" or "solo",
        groupSize = GetNumGroupMembers() or 1
    }
    
    debugPrint("Combat started: %s (cached %d group members)", sessionId, self:TableSize(groupMemberGUIDs))
end

-- Begin combat timeout when player leaves WoW combat
function MySimpleCombatDetector:BeginCombatTimeout()
    if not inCombat then
        return
    end
    
    debugPrint("Player left WoW combat, starting activity timeout")
    
    -- Start timeout timer
    self:StartTimeoutTimer()
end

-- Process combat log events
function MySimpleCombatDetector:ProcessCombatEvent(...)
    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags = ...
    
    -- PHASE 1: Quick exit for events we never care about (maximum performance)
    if QUICK_EXIT_EVENTS[eventType] then
        return
    end
    
    -- PHASE 2: Only process if we're tracking combat
    if not inCombat or not currentSessionData then
        return
    end
    
    -- PHASE 3: Filter for meaningful combat events only
    if not MEANINGFUL_EVENTS[eventType] then
        return
    end
    
    -- PHASE 4: Entity filtering - reject irrelevant entity types
    -- Skip events involving totems, guardians we don't care about, etc.
    if not self:IsRelevantEntity(sourceGUID, sourceName, sourceFlags) and 
       not self:IsRelevantEntity(destGUID, destName, destFlags) then
        return
    end
    
    -- PHASE 5: Fast player/group member check using cached GUIDs
    local isPlayerEvent = (sourceGUID == playerGUID) or (destGUID == playerGUID)
    
    -- For group play, check cached group member GUIDs (much faster than UnitExists loop)
    if not isPlayerEvent and next(groupMemberGUIDs) then
        isPlayerEvent = groupMemberGUIDs[sourceGUID] or groupMemberGUIDs[destGUID]
    end
    
    if not isPlayerEvent then
        return
    end
    
    -- Add names to GUID map if not already present
    if sourceGUID and sourceName and sourceName ~= "nil" then
        if not currentSessionData.guidMap[sourceGUID] then
            currentSessionData.guidMap[sourceGUID] = sourceName
        end
    end
    
    if destGUID and destName and destName ~= "nil" then
        if not currentSessionData.guidMap[destGUID] then
            currentSessionData.guidMap[destGUID] = destName
        end
    end
    
    -- Log recording with GUID info for debugging
    debugPrint("RECORD: %s (%s -> %s)", 
        eventType, sourceName or "nil", destName or "nil")
    
    -- Update activity time for relevant events (optimized with cached GUIDs)
    if sourceGUID == playerGUID then
        lastActivityTime = GetTime()
    elseif destGUID == playerGUID and (eventType:find("DAMAGE") or eventType:find("HEAL")) then
        lastActivityTime = GetTime()
    end
    
    -- Calculate relative timestamp using TimestampManager
    local relativeTime = 0
    if addon.MyTimestampManager then
        relativeTime = addon.MyTimestampManager:GetRelativeTime(timestamp)
        -- Debug: Log the timestamp calculation
        logger:Debug("ProcessCombatEvent: timestamp=%.3f, relativeTime=%.3f", 
            tonumber(timestamp) or 0, tonumber(relativeTime) or 0)
    else
        -- Fallback to manual calculation
        relativeTime = timestamp and combatStartTime and (timestamp - combatStartTime) or 0
        logger:Debug("ProcessCombatEvent: FALLBACK timestamp=%.3f, combatStartTime=%.3f, relativeTime=%.3f", 
            tonumber(timestamp) or 0, tonumber(combatStartTime) or 0, tonumber(relativeTime) or 0)
    end
    
    -- Store only GUIDs and relative time - much more efficient
    local eventData = {
        time = relativeTime,           -- Relative time from combat start
        subevent = eventType,
        sourceGUID = sourceGUID,
        destGUID = destGUID
        -- Names are resolved from guidMap during export
    }
    
    table.insert(currentSessionData.events, eventData)
    currentSessionData.eventCount = currentSessionData.eventCount + 1
    
    -- Only show count every 5 events to reduce spam
    if currentSessionData.eventCount % 5 == 0 then
        debugPrint("Events recorded: %d", currentSessionData.eventCount)
    end
end

-- Start the activity timeout timer
function MySimpleCombatDetector:StartTimeoutTimer()
    -- Cancel any existing timer
    self:CancelTimeout()
    
    -- Create new timer that checks every CHECK_INTERVAL seconds
    timeoutTimer = C_Timer.NewTicker(CONFIG.CHECK_INTERVAL, function()
        self:CheckActivityTimeout()
    end)
end

-- Check if we should end combat due to inactivity
function MySimpleCombatDetector:CheckActivityTimeout()
    if not inCombat or not lastActivityTime then
        self:CancelTimeout()
        return
    end
    
    local timeSinceActivity = GetTime() - lastActivityTime
    
    if timeSinceActivity >= CONFIG.ACTIVITY_TIMEOUT then
        debugPrint("Combat timeout reached: %.1fs since last activity", timeSinceActivity)
        self:EndCombat()
    else
        addon:Trace("Combat continues: %.1fs since last activity", timeSinceActivity)
    end
end

-- End the current combat session
function MySimpleCombatDetector:EndCombat()
    if not inCombat or not currentSessionData then
        debugPrint("EndCombat called but no active session")
        return
    end
    
    -- Cancel timeout timer
    self:CancelTimeout()
    
    -- End TimestampManager combat tracking
    if addon.MyTimestampManager then
        addon.MyTimestampManager:EndCombat()
        currentSessionData.endTime = addon.MyTimestampManager:GetTimestampData().combatEndTime
    else
        currentSessionData.endTime = GetTime()
    end
    
    -- Calculate duration and validate session
    local duration = currentSessionData.endTime - currentSessionData.startTime
    currentSessionData.duration = duration  -- Explicitly store duration
    local eventCount = currentSessionData.eventCount
    local activityRate = eventCount / duration
    
    debugPrint("Combat ended: %s (%.1fs, %d events, %.2f events/sec)", 
        currentSessionData.id, duration, eventCount, activityRate)
    
    -- Check if session meets minimum criteria
    if duration >= CONFIG.MIN_DURATION and 
       eventCount >= CONFIG.MIN_EVENTS and 
       activityRate >= CONFIG.MIN_ACTIVITY_RATE then
        
        self:StoreSession(currentSessionData)
        
        infoPrint("Session stored: %s", currentSessionData.id)
    else
        debugPrint("Session discarded: insufficient activity (%s)", currentSessionData.id)
    end
    
    -- Reset combat state
    inCombat = false
    combatStartTime = nil
    lastActivityTime = nil
    currentSessionData = nil
end

-- Store the completed session
function MySimpleCombatDetector:StoreSession(sessionData)
    if addon.StorageManager then
        addon.StorageManager:StoreCombatSession(sessionData)
    else
        errorPrint("StorageManager not available - session lost")
    end
end

-- Cancel the timeout timer
function MySimpleCombatDetector:CancelTimeout()
    if timeoutTimer then
        timeoutTimer:Cancel()
        timeoutTimer = nil
    end
end

-- Public API methods
function MySimpleCombatDetector:IsInCombat()
    return inCombat
end

function MySimpleCombatDetector:GetCurrentSession()
    return currentSessionData
end

function MySimpleCombatDetector:ForceEndCombat()
    if inCombat then
        self:EndCombat()
    end
end

-- Debug method to check current state
function MySimpleCombatDetector:GetDebugInfo()
    return {
        inCombat = inCombat,
        sessionId = currentSessionData and currentSessionData.id or nil,
        duration = currentSessionData and (GetTime() - currentSessionData.startTime) or 0,
        eventCount = currentSessionData and currentSessionData.eventCount or 0,
        timeSinceActivity = lastActivityTime and (GetTime() - lastActivityTime) or 0,
        hasTimer = timeoutTimer ~= nil
    }
end

-- Session ID validation helper
function MySimpleCombatDetector:ValidateSessionId(sessionId)
    if not sessionId or type(sessionId) ~= "string" then
        return false, "Invalid session ID format"
    end
    
    -- Extract parts: timestamp-counter-checksum
    local parts = {}
    for part in sessionId:gmatch("[^-]+") do
        table.insert(parts, part)
    end
    
    if #parts ~= 3 then
        return false, "Session ID must have 3 parts separated by dashes"
    end
    
    -- Reconstruct base ID without checksum
    local baseId = string.format("%s-%s", parts[1], parts[2])
    
    -- Calculate expected checksum
    local expectedChecksum = 0
    for i = 1, #baseId do
        expectedChecksum = expectedChecksum + string.byte(baseId, i)
    end
    expectedChecksum = expectedChecksum % 1000
    
    -- Compare with provided checksum
    local providedChecksum = tonumber(parts[3])
    if expectedChecksum == providedChecksum then
        return true, "Session ID is valid"
    else
        return false, string.format("Checksum mismatch: expected %03d, got %03d", expectedChecksum, providedChecksum)
    end
end

-- Configuration methods
function MySimpleCombatDetector:GetConfig()
    return CONFIG
end

-- Enable/disable internal debug mode
function MySimpleCombatDetector:SetInternalDebug(enabled)
    DEBUG_MODE = enabled
    debugPrint("Internal debug mode:", enabled and "enabled" or "disabled")
end

return MySimpleCombatDetector