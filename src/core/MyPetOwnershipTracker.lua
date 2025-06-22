-- MyPetOwnershipTracker.lua
-- Multi-layer pet ownership detection system based on Recount's proven methodology
-- Handles permanent pets, temporary guardians, and ephemeral summons

local addonName, addon = ...

-- =============================================================================
-- MY PET OWNERSHIP TRACKER MODULE
-- =============================================================================

local MyPetOwnershipTracker = {}
addon.MyPetOwnershipTracker = MyPetOwnershipTracker

-- =============================================================================
-- CONSTANTS AND CONFIGURATION
-- =============================================================================

-- Combat log object flags (matching Recount's constants)
local COMBATLOG_OBJECT_AFFILIATION_MINE = 0x00000001
local COMBATLOG_OBJECT_AFFILIATION_PARTY = 0x00000002
local COMBATLOG_OBJECT_AFFILIATION_RAID = 0x00000004
local COMBATLOG_OBJECT_AFFILIATION_OUTSIDER = 0x00000008

local COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
local COMBATLOG_OBJECT_TYPE_NPC = 0x00000800
local COMBATLOG_OBJECT_TYPE_PET = 0x00001000
local COMBATLOG_OBJECT_TYPE_GUARDIAN = 0x00002000

local COMBATLOG_OBJECT_CONTROL_PLAYER = 0x00000100
local COMBATLOG_OBJECT_CONTROL_NPC = 0x00000200

-- Configuration
local PET_CONFIG = {
    includePets = true,           -- Include permanent pets
    includeGuardians = true,      -- Include temporary summons  
    includeGroupPets = false,     -- Include group member pets (for raid-wide view)
    useTooltipFallback = false,   -- Use expensive tooltip detection (disabled for performance)
    maxGuardiansPerOwner = 12,    -- Limit memory usage like Recount
    unitScanInterval = 1.0,       -- Rate limit unit scanning
    cacheCleanupInterval = 300,   -- Clean old entries every 5 minutes
}

-- =============================================================================
-- STATE TRACKING
-- =============================================================================

-- Global caches for fast lookup
local guidToOwnerCache = {}      -- petGUID -> ownerName
local ownerToGuardians = {}      -- ownerName -> guardian data
local lastUnitScanTime = 0       -- Rate limiting for unit scanning
local cacheStats = {
    hits = 0,
    misses = 0,
    unitScans = 0,
    flagDetections = 0,
    totalLookups = 0
}

-- =============================================================================
-- CORE PET DETECTION FUNCTIONS
-- =============================================================================

-- Main pet ownership detection function (following Recount's multi-layer approach)
function MyPetOwnershipTracker:DetectPetOwnership(name, guid, flags)
    if not name or not guid then
        return name, nil, nil
    end
    
    -- DEBUG: Add detailed logging for detection process
    addon:Debug("MyPetOwnership: === Starting detection for '%s' (GUID: %s, Flags: 0x%08X) ===", 
        tostring(name), tostring(guid), tonumber(flags) or 0)
    
    cacheStats.totalLookups = cacheStats.totalLookups + 1
    local petName, owner, ownerGUID
    
    -- Step 1: Parse existing <owner> format in name
    petName, owner = name:match("(.-) <(.*)>")
    if not petName then 
        petName = name 
    end
    
    -- If we already have owner from name format, validate and return
    if owner then
        ownerGUID = self:GetPlayerGUID(owner)
        if ownerGUID then
            addon:Debug("MyPetOwnership: Found owner from name format - %s -> %s", petName, owner)
            return name, owner, ownerGUID
        end
    end
    
    -- Step 2: Check GUID-based lookup cache (fastest)
    owner = guidToOwnerCache[guid]
    if owner then
        cacheStats.hits = cacheStats.hits + 1
        ownerGUID = self:GetPlayerGUID(owner)
        addon:Debug("MyPetOwnership: Cache hit - %s (%s) -> %s", petName, guid, owner)
        return petName.." <"..owner..">", owner, ownerGUID
    end
    
    cacheStats.misses = cacheStats.misses + 1
    
    -- Step 3: Use combat log flags for immediate classification
    if flags and self:IsPetOrGuardian(flags) then
        if bit.band(flags, COMBATLOG_OBJECT_AFFILIATION_MINE) ~= 0 then
            -- Player's own pet/guardian
            local playerName = UnitName("player")
            local playerGUID = UnitGUID("player")
            
            -- Cache this relationship
            guidToOwnerCache[guid] = playerName
            cacheStats.flagDetections = cacheStats.flagDetections + 1
            
            addon:Debug("MyPetOwnership: Flag detection (MINE) - %s (%s) -> %s", petName, guid, playerName)
            return petName.." <"..playerName..">", playerName, playerGUID
            
        elseif PET_CONFIG.includeGroupPets and 
               bit.band(flags, COMBATLOG_OBJECT_AFFILIATION_PARTY + COMBATLOG_OBJECT_AFFILIATION_RAID) ~= 0 then
            -- Group member's pet - need unit scanning
            owner, ownerGUID = self:FindOwnerFromUnitScan(petName, guid)
            if owner then
                guidToOwnerCache[guid] = owner
                addon:Debug("MyPetOwnership: Flag detection (GROUP) + unit scan - %s (%s) -> %s", petName, guid, owner)
                return petName.." <"..owner..">", owner, ownerGUID
            end
        end
    end
    
    -- Step 4: Unit scanning for reliable detection (rate limited)
    if self:ShouldScanUnits() then
        owner, ownerGUID = self:FindOwnerFromUnitScan(petName, guid)
        if owner then
            guidToOwnerCache[guid] = owner
            addon:Debug("MyPetOwnership: Unit scan success - %s (%s) -> %s", petName, guid, owner)
            return petName.." <"..owner..">", owner, ownerGUID
        end
    end
    
    -- Step 5: Enhanced guardian detection for player pets/guardians that might not have flags
    -- This catches things like Mindbender, Shadowfiend, etc. that might have unclear flags
    addon:Debug("MyPetOwnership: Step 5 - Checking if '%s' could be player pet", petName)
    if self:CouldBePlayerPet(petName, guid) then
        local playerName = UnitName("player")
        local playerGUID = UnitGUID("player")
        guidToOwnerCache[guid] = playerName
        addon:Debug("MyPetOwnership: Enhanced detection SUCCESS - %s (%s) -> %s (player guardian)", petName, guid, playerName)
        return petName.." <"..playerName..">", playerName, playerGUID
    else
        addon:Debug("MyPetOwnership: Step 5 - CouldBePlayerPet returned false for '%s'", petName)
    end
    
    addon:Trace("MyPetOwnership: No owner found - %s (%s)", petName, guid)
    return petName, nil, nil
end

-- Check if entity is a pet or guardian using combat log flags
function MyPetOwnershipTracker:IsPetOrGuardian(flags)
    if not flags then return false end
    
    local isPet = bit.band(flags, COMBATLOG_OBJECT_TYPE_PET) ~= 0
    local isGuardian = bit.band(flags, COMBATLOG_OBJECT_TYPE_GUARDIAN) ~= 0
    
    return (PET_CONFIG.includePets and isPet) or (PET_CONFIG.includeGuardians and isGuardian)
end

-- Rate limiting for expensive unit scanning
function MyPetOwnershipTracker:ShouldScanUnits()
    local currentTime = GetTime()
    if currentTime - lastUnitScanTime >= PET_CONFIG.unitScanInterval then
        lastUnitScanTime = currentTime
        return true
    end
    return false
end

-- =============================================================================
-- UNIT SCANNING (Recount's most reliable method)
-- =============================================================================

-- Scan group units to find pet owner (adapted from Recount's FindOwnerPetFromGUID)
function MyPetOwnershipTracker:FindOwnerFromUnitScan(petName, petGUID)
    cacheStats.unitScans = cacheStats.unitScans + 1
    
    -- Check player's own pet first
    if petGUID == UnitGUID("pet") then
        local playerName = UnitName("player")
        local playerGUID = UnitGUID("player")
        addon:Debug("MyPetOwnership: Unit scan - player pet match")
        return playerName, playerGUID
    end
    
    -- Scan group members
    local numGroupMembers = GetNumGroupMembers()
    if numGroupMembers > 0 then
        for i = 1, numGroupMembers do
            local unitPrefix = IsInRaid() and "raid" or "party"
            local petUnit = unitPrefix.."pet"..i
            local ownerUnit = unitPrefix..i
            
            if UnitExists(petUnit) and petGUID == UnitGUID(petUnit) then
                local ownerName, ownerRealm = UnitName(ownerUnit)
                if ownerName then
                    if ownerRealm and ownerRealm ~= "" then
                        ownerName = ownerName.."-"..ownerRealm
                    end
                    local ownerGUID = UnitGUID(ownerUnit)
                    addon:Debug("MyPetOwnership: Unit scan - group pet match (%s%d)", unitPrefix, i)
                    return ownerName, ownerGUID
                end
            end
        end
    end
    
    return nil, nil
end

-- =============================================================================
-- GUARDIAN TRACKING SYSTEM
-- =============================================================================

-- Track temporary guardians with circular buffer (following Recount's approach)
function MyPetOwnershipTracker:TrackGuardianOwnership(ownerName, petName, petGUID)
    if not ownerName or not petName or not petGUID then return end
    
    -- Initialize owner's guardian tracking
    if not ownerToGuardians[ownerName] then
        ownerToGuardians[ownerName] = {}
    end
    
    local ownerGuardians = ownerToGuardians[ownerName]
    
    -- Initialize guardian name tracking with circular buffer
    if not ownerGuardians[petName] then
        ownerGuardians[petName] = {
            latestIndex = 0,
            guids = {}
        }
    end
    
    local guardian = ownerGuardians[petName]
    
    -- Add to circular buffer (max 12 guardians of same name like Recount)
    guardian.latestIndex = (guardian.latestIndex + 1) % PET_CONFIG.maxGuardiansPerOwner
    guardian.guids[guardian.latestIndex] = petGUID
    
    -- Update global cache
    guidToOwnerCache[petGUID] = ownerName
    
    addon:Debug("MyPetOwnership: Guardian tracked - %s (%s) -> %s [%d]", 
        petName, petGUID, ownerName, guardian.latestIndex)
end

-- Get the latest guardian GUID for a specific owner and pet name
function MyPetOwnershipTracker:GetLatestGuardianGUID(ownerName, petName)
    local ownerGuardians = ownerToGuardians[ownerName]
    if not ownerGuardians or not ownerGuardians[petName] then
        return nil
    end
    
    local guardian = ownerGuardians[petName]
    return guardian.guids[guardian.latestIndex]
end

-- Enhanced detection for known player pets/guardians (especially priest pets)
function MyPetOwnershipTracker:CouldBePlayerPet(petName, guid)
    if not guid then 
        addon:Debug("MyPetOwnership: CouldBePlayerPet - Invalid input: petName='%s', guid='%s'", tostring(petName), tostring(guid))
        return false 
    end
    
    addon:Debug("MyPetOwnership: CouldBePlayerPet - Checking '%s' with GUID '%s'", tostring(petName), guid)
    
    -- GUID-based detection for when sourceName is "Unknown"
    -- Check if this GUID indicates a player-controlled entity
    if guid and type(guid) == "string" then
        -- Pet GUIDs typically start with "Pet-" 
        -- Guardian GUIDs may be "Creature-" but with specific patterns
        if string.find(guid, "^Pet%-") then
            addon:Debug("MyPetOwnership: GUID indicates Pet entity - %s", guid)
            return true
        end
        
        -- Some guardians may have Creature GUIDs but be player-controlled
        -- This requires checking current active pet/guardian GUIDs
        local playerPetGUID = UnitGUID("pet")
        if playerPetGUID == guid then
            addon:Debug("MyPetOwnership: GUID matches current player pet - %s", guid)
            return true
        end
    end
    
    -- If petName is "Unknown", we can't do name-based detection
    if not petName or petName == "Unknown" then
        addon:Debug("MyPetOwnership: Cannot do name-based detection for 'Unknown' entity")
        return false
    end
    
    -- Known priest pets/guardians that should be attributed to player
    local PRIEST_PETS = {
        ["Shadowfiend"] = true,
        ["Mindbender"] = true,
        ["Voidwraith"] = true,
        ["Lightwell"] = true,
        ["Spirit of Redemption"] = true,
        ["Void Tendril"] = true,
        ["Psychic Horror"] = true,
    }
    
    -- Known patterns for other classes (add as needed)
    local KNOWN_PET_PATTERNS = {
        -- Shaman
        ["Fire Elemental"] = true,
        ["Earth Elemental"] = true,
        ["Storm Elemental"] = true,
        ["Spirit Wolf"] = true,
        ["Feral Spirit"] = true,
        
        -- Warlock 
        ["Wild Imp"] = true,
        ["Dreadstalker"] = true,
        ["Vilefiend"] = true,
        ["Demonic Tyrant"] = true,
        ["Darkglare"] = true,
        ["Infernal"] = true,
        
        -- Death Knight
        ["Army of the Dead"] = true,
        ["Gargoyle"] = true,
        ["Abomination"] = true,
        
        -- Mage
        ["Water Elemental"] = true,
        ["Mirror Image"] = true,
        
        -- Druid
        ["Treant"] = true,
        ["Grove Guardian"] = true,
        
        -- Monk
        ["Storm"] = true,
        ["Earth"] = true,
        ["Fire"] = true,
        ["Xuen"] = true,
        ["Yu'lon"] = true,
        ["Chi-Ji"] = true,
        ["Niuzao"] = true,
    }
    
    -- Check exact name match
    if PRIEST_PETS[petName] or KNOWN_PET_PATTERNS[petName] then
        addon:Debug("MyPetOwnership: Known pet pattern match - %s", petName)
        return true
    else
        addon:Debug("MyPetOwnership: No exact match for '%s' in known pets", petName)
    end
    
    -- Check partial name matches for dynamic pets
    local lowerName = string.lower(petName)
    local PARTIAL_PATTERNS = {
        "shadowfiend", "mindbender", "voidwraith", "spirit wolf", "wild imp", "treant", 
        "mirror image", "elemental", "gargoyle", "abomination"
    }
    
    for _, pattern in ipairs(PARTIAL_PATTERNS) do
        if string.find(lowerName, pattern) then
            addon:Debug("MyPetOwnership: Partial pet pattern match - %s contains %s", petName, pattern)
            return true
        end
    end
    
    addon:Debug("MyPetOwnership: No partial matches found for '%s' (lowercase: '%s')", petName, lowerName)
    return false
end

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

-- Get player GUID from name (with caching)
function MyPetOwnershipTracker:GetPlayerGUID(playerName)
    if not playerName then return nil end
    
    -- Check if it's the current player
    if playerName == UnitName("player") then
        return UnitGUID("player")
    end
    
    -- Scan group members for the GUID
    local numGroupMembers = GetNumGroupMembers()
    for i = 1, numGroupMembers do
        local unitPrefix = IsInRaid() and "raid" or "party"
        local unitName = UnitName(unitPrefix..i)
        if unitName == playerName then
            return UnitGUID(unitPrefix..i)
        end
    end
    
    return nil
end

-- Clean up old cache entries to prevent memory bloat
function MyPetOwnershipTracker:CleanupCache()
    local currentTime = GetTime()
    local cleaned = 0
    
    -- For now, we'll implement a simple size-based cleanup
    -- TODO: Add time-based cleanup when we track entry timestamps
    local cacheSize = 0
    for _ in pairs(guidToOwnerCache) do
        cacheSize = cacheSize + 1
    end
    
    if cacheSize > 1000 then
        guidToOwnerCache = {} -- Nuclear cleanup
        cleaned = cacheSize
        addon:Debug("MyPetOwnership: Cache cleared (size limit: %d entries)", cleaned)
    end
    
    return cleaned
end

-- =============================================================================
-- CONFIGURATION AND STATS
-- =============================================================================

-- Update configuration
function MyPetOwnershipTracker:SetConfig(key, value)
    if PET_CONFIG[key] ~= nil then
        PET_CONFIG[key] = value
        addon:Debug("MyPetOwnership: Config updated - %s = %s", key, tostring(value))
        return true
    end
    return false
end

-- Get current configuration
function MyPetOwnershipTracker:GetConfig()
    return PET_CONFIG
end

-- Get cache statistics for monitoring
function MyPetOwnershipTracker:GetStats()
    local cacheSize = 0
    for _ in pairs(guidToOwnerCache) do
        cacheSize = cacheSize + 1
    end
    
    local guardianCount = 0
    for owner, guardians in pairs(ownerToGuardians) do
        for petName, guardian in pairs(guardians) do
            for _ in pairs(guardian.guids) do
                guardianCount = guardianCount + 1
            end
        end
    end
    
    return {
        cacheSize = cacheSize,
        guardianCount = guardianCount,
        hitRate = cacheStats.totalLookups > 0 and (cacheStats.hits / cacheStats.totalLookups) or 0,
        totalLookups = cacheStats.totalLookups,
        hits = cacheStats.hits,
        misses = cacheStats.misses,
        unitScans = cacheStats.unitScans,
        flagDetections = cacheStats.flagDetections
    }
end

-- Reset statistics
function MyPetOwnershipTracker:ResetStats()
    cacheStats = {
        hits = 0,
        misses = 0,
        unitScans = 0,
        flagDetections = 0,
        totalLookups = 0
    }
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

function MyPetOwnershipTracker:Initialize()
    addon:Debug("MyPetOwnership: Tracker initialized")
    
    -- Set up periodic cache cleanup
    C_Timer.NewTicker(PET_CONFIG.cacheCleanupInterval, function()
        self:CleanupCache()
    end)
end

return MyPetOwnershipTracker