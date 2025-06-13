-- EnhancedCombatLogger.lua
-- Enhanced combat logging for detailed session insights

local addonName, addon = ...

addon.EnhancedCombatLogger = {}
local EnhancedCombatLogger = addon.EnhancedCombatLogger

-- =============================================================================
-- CONFIGURATION & TRACKING DATA
-- =============================================================================

-- Notable buff/debuff tracking
local NOTABLE_BUFFS = {
    -- Bloodlust effects
    [2825] = { name = "Bloodlust", type = "major_cooldown", color = { 1, 0.2, 0.2 } },
    [32182] = { name = "Heroism", type = "major_cooldown", color = { 1, 0.2, 0.2 } },
    [80353] = { name = "Time Warp", type = "major_cooldown", color = { 0.4, 0.4, 1 } },
    [90355] = { name = "Ancient Hysteria", type = "major_cooldown", color = { 0.8, 0.2, 0.8 } },

    -- Major defensive cooldowns
    [871] = { name = "Shield Wall", type = "defensive", color = { 0.8, 0.8, 0.2 } },
    [22812] = { name = "Barkskin", type = "defensive", color = { 0.6, 0.8, 0.4 } },
    [48792] = { name = "Icebound Fortitude", type = "defensive", color = { 0.4, 0.8, 1 } },
    [47585] = { name = "Dispersion", type = "defensive", color = { 0.6, 0.4, 0.8 } },

    -- Major offensive cooldowns
    [12472] = { name = "Icy Veins", type = "offensive", color = { 0.4, 0.8, 1 } },
    [190319] = { name = "Combustion", type = "offensive", color = { 1, 0.4, 0.2 } },
    [13750] = { name = "Adrenaline Rush", type = "offensive", color = { 1, 0.8, 0.2 } },
}

-- Enhanced session data structure
local enhancedSessionData = {
    combatEvents = {},
    participants = {},
    damageTaken = {},
    groupDamage = {},
    cooldownUsage = {},
    deaths = {},
    healingEvents = {}
}

-- =============================================================================
-- ENHANCED COMBAT TRACKING
-- =============================================================================

-- Track combat participants
local function TrackParticipant(guid, name, flags)
    if not guid or not name then return end

    -- UNIFIED TIMESTAMP: Use TimestampManager for participant tracking
    local currentRelativeTime = 0
    if addon.TimestampManager then
        currentRelativeTime = addon.TimestampManager:GetCurrentRelativeTime()
    end

    -- Skip if we already have this participant
    if enhancedSessionData.participants[guid] then
        enhancedSessionData.participants[guid].lastSeen = currentRelativeTime
        return
    end

    local isPlayer = bit.band(flags or 0, COMBATLOG_OBJECT_TYPE_PLAYER) > 0
    local isNPC = bit.band(flags or 0, COMBATLOG_OBJECT_TYPE_NPC) > 0
    local isPet = bit.band(flags or 0, COMBATLOG_OBJECT_TYPE_PET) > 0

    enhancedSessionData.participants[guid] = {
        name = name,
        guid = guid,
        isPlayer = isPlayer,
        isNPC = isNPC,
        isPet = isPet,
        -- UNIFIED TIMESTAMP: Store relative time instead of absolute GetTime()
        firstSeen = currentRelativeTime,
        lastSeen = currentRelativeTime,
        damageDealt = 0,
        healingDealt = 0,
        damageTaken = 0
    }

    if addon.DEBUG and math.random() < 0.2 then -- 20% sample rate for debug
        local typeStr = isPlayer and "Player" or (isPet and "Pet" or "NPC")
        if addon.VERBOSE_DEBUG then
            addon:DebugPrint(string.format("Enhanced: Tracked %s (%s)", name, typeStr))
        end
    end
end

-- Track damage taken by player
local function TrackDamageTaken(timestamp, sourceGUID, sourceName, destGUID, destName, spellId, spellName, amount)
    local playerGUID = UnitGUID("player")

    if destGUID == playerGUID then
        -- UNIFIED TIMESTAMP: Use TimestampManager for consistent time calculation
        local elapsed = 0
        if addon.TimestampManager then
            elapsed = addon.TimestampManager:GetRelativeTime(timestamp)
        end
        
        table.insert(enhancedSessionData.damageTaken, {
            -- REMOVED: No longer store absolute timestamps, only relative time
            elapsed = elapsed,
            sourceGUID = sourceGUID,
            sourceName = sourceName,
            spellId = spellId,
            spellName = spellName,
            amount = amount
        })
    end
end

-- Track group/raid damage taken
local function TrackGroupDamage(timestamp, sourceGUID, sourceName, destGUID, destName, spellId, spellName, amount)
    -- Check if destination is in our group/raid
    local isGroupMember = false

    if IsInRaid() then
        for i = 1, 40 do
            if UnitExists("raid" .. i) and UnitGUID("raid" .. i) == destGUID then
                isGroupMember = true
                break
            end
        end
    elseif IsInGroup() then
        for i = 1, 5 do
            local unit = i == 1 and "player" or ("party" .. (i - 1))
            if UnitExists(unit) and UnitGUID(unit) == destGUID then
                isGroupMember = true
                break
            end
        end
    else
        -- Solo play - only track player
        isGroupMember = (destGUID == UnitGUID("player"))
    end

    if isGroupMember then
        -- UNIFIED TIMESTAMP: Use TimestampManager for consistent time calculation
        local elapsed = 0
        if addon.TimestampManager then
            elapsed = addon.TimestampManager:GetRelativeTime(timestamp)
        end
        
        table.insert(enhancedSessionData.groupDamage, {
            -- REMOVED: No longer store absolute timestamps, only relative time
            elapsed = elapsed,
            sourceGUID = sourceGUID,
            sourceName = sourceName,
            destGUID = destGUID,
            destName = destName,
            spellId = spellId,
            spellName = spellName,
            amount = amount
        })
    end
end

-- Track cooldown usage
local function TrackCooldownUsage(timestamp, sourceGUID, sourceName, spellId, spellName)
    local cooldownInfo = NOTABLE_BUFFS[spellId]
    if cooldownInfo then
        -- UNIFIED TIMESTAMP: Use TimestampManager for consistent time calculation
        local elapsed = 0
        if addon.TimestampManager then
            elapsed = addon.TimestampManager:GetRelativeTime(timestamp)
        end
        
        table.insert(enhancedSessionData.cooldownUsage, {
            -- REMOVED: No longer store absolute timestamps, only relative time
            elapsed = elapsed,
            sourceGUID = sourceGUID,
            sourceName = sourceName,
            spellId = spellId,
            spellName = spellName,
            cooldownType = cooldownInfo.type,
            color = cooldownInfo.color
        })

        if addon.DEBUG then
            addon:DebugPrint(string.format("Cooldown tracked: %s used %s at %.1fs",
                sourceName, spellName, elapsed))
        end
    end
end

-- Track deaths
local function TrackDeath(timestamp, destGUID, destName)
    -- Use TimestampManager for consistent time calculations
    local elapsed = 0
    if addon.TimestampManager then
        elapsed = addon.TimestampManager:GetRelativeTime(timestamp)
    else
        -- Fallback to old method
        local combatData = addon.CombatData:GetRawCombatData()
        local combatStartTime = combatData.startTime
        local currentTime = GetTime()
        elapsed = currentTime - combatStartTime
    end
    
    table.insert(enhancedSessionData.deaths, {
        timestamp = timestamp,           -- Original combat log timestamp
        elapsed = elapsed,               -- Time since combat start (from TimestampManager)
        destGUID = destGUID,
        destName = destName
    })

    if addon.DEBUG then
        addon:DebugPrint(string.format("Death tracked: %s died at %.3fs (logTime: %.3f)",
            destName, elapsed, timestamp))
    end
end

-- Enhanced combat log parser
function EnhancedCombatLogger:ParseEnhancedCombatLog(timestamp, subevent, _, sourceGUID, sourceName, sourceFlags,
                                                     sourceRaidFlags,
                                                     destGUID, destName, destFlags, destRaidFlags, ...)
    if not addon.CombatData:IsInCombat() then return end

    -- Track all participants more aggressively
    if sourceGUID and sourceName then
        TrackParticipant(sourceGUID, sourceName, sourceFlags)
    end
    if destGUID and destName then
        TrackParticipant(destGUID, destName, destFlags)
    end

    local playerGUID = UnitGUID("player")

    -- Handle different event types with debug output
    if subevent == "SPELL_DAMAGE" or subevent == "SWING_DAMAGE" or subevent == "RANGE_DAMAGE" then
        local spellId, spellName, spellSchool, amount

        if subevent == "SWING_DAMAGE" then
            amount = select(1, ...)
            spellId = nil
            spellName = "Melee"
        else
            spellId, spellName, spellSchool = select(1, ...)
            amount = select(4, ...)
        end

        if amount and amount > 0 then
            -- Track player damage taken
            if destGUID == playerGUID then
                TrackDamageTaken(timestamp, sourceGUID, sourceName, destGUID, destName, spellId, spellName, amount)

                if addon.DEBUG and math.random() < 0.1 then -- 10% sample rate for debug
                    if addon.VERBOSE_DEBUG then
                        addon:DebugPrint(string.format("Enhanced: Player took %s damage from %s",
                            addon.CombatTracker:FormatNumber(amount), sourceName or "Unknown"))
                    end
                end
            end

            -- Track group damage taken (if enabled)
            if addon.db and addon.db.trackGroupDamage then
                TrackGroupDamage(timestamp, sourceGUID, sourceName, destGUID, destName, spellId, spellName, amount)
            end

            -- Update participant damage stats
            if enhancedSessionData.participants[sourceGUID] then
                enhancedSessionData.participants[sourceGUID].damageDealt =
                    (enhancedSessionData.participants[sourceGUID].damageDealt or 0) + amount
                -- UNIFIED TIMESTAMP: Use relative time for lastSeen
                if addon.TimestampManager then
                    enhancedSessionData.participants[sourceGUID].lastSeen = addon.TimestampManager:GetRelativeTime(timestamp)
                end
            end
            if enhancedSessionData.participants[destGUID] then
                enhancedSessionData.participants[destGUID].damageTaken =
                    (enhancedSessionData.participants[destGUID].damageTaken or 0) + amount
                -- UNIFIED TIMESTAMP: Use relative time for lastSeen
                if addon.TimestampManager then
                    enhancedSessionData.participants[destGUID].lastSeen = addon.TimestampManager:GetRelativeTime(timestamp)
                end
            end
        end
    elseif subevent == "SPELL_HEAL" or subevent == "SPELL_PERIODIC_HEAL" then
        local spellId, spellName, spellSchool, amount = select(1, ...)

        if amount and amount > 0 then
            -- UNIFIED TIMESTAMP: Use TimestampManager for consistent time calculation
            local elapsed = 0
            if addon.TimestampManager then
                elapsed = addon.TimestampManager:GetRelativeTime(timestamp)
            end
            
            table.insert(enhancedSessionData.healingEvents, {
                -- REMOVED: No longer store absolute timestamps, only relative time
                elapsed = elapsed,
                sourceGUID = sourceGUID,
                sourceName = sourceName,
                destGUID = destGUID,
                destName = destName,
                spellId = spellId,
                spellName = spellName,
                amount = amount
            })

            -- Update participant healing stats
            if enhancedSessionData.participants[sourceGUID] then
                enhancedSessionData.participants[sourceGUID].healingDealt =
                    (enhancedSessionData.participants[sourceGUID].healingDealt or 0) + amount
                -- UNIFIED TIMESTAMP: Use relative time for lastSeen
                if addon.TimestampManager then
                    enhancedSessionData.participants[sourceGUID].lastSeen = addon.TimestampManager:GetRelativeTime(timestamp)
                end
            end
        end
    elseif subevent == "SPELL_AURA_APPLIED" then
        local spellId, spellName = select(1, ...)
        TrackCooldownUsage(timestamp, sourceGUID, sourceName, spellId, spellName)
    elseif subevent == "SPELL_CAST_SUCCESS" then
        local spellId, spellName = select(1, ...)
        -- Some cooldowns might not show as aura applications
        TrackCooldownUsage(timestamp, sourceGUID, sourceName, spellId, spellName)
    elseif subevent == "UNIT_DIED" then
        TrackDeath(timestamp, destGUID, destName)
    end
end

-- =============================================================================
-- DATA ACCESS FUNCTIONS
-- =============================================================================

function EnhancedCombatLogger:GetStatus()
    local status = {
        isInitialized = self.frame ~= nil,
        isTracking = addon.CombatData and addon.CombatData:IsInCombat(),
        participantCount = 0,
        eventCounts = {
            damageTaken = #(enhancedSessionData.damageTaken or {}),
            groupDamage = #(enhancedSessionData.groupDamage or {}),
            cooldownUsage = #(enhancedSessionData.cooldownUsage or {}),
            deaths = #(enhancedSessionData.deaths or {}),
            healingEvents = #(enhancedSessionData.healingEvents or {})
        }
    }

    if enhancedSessionData.participants then
        for _ in pairs(enhancedSessionData.participants) do
            status.participantCount = status.participantCount + 1
        end
    end

    return status
end

-- Get enhanced session data for a completed session
function EnhancedCombatLogger:GetEnhancedSessionData()
    return {
        participants = enhancedSessionData.participants,
        damageTaken = enhancedSessionData.damageTaken,
        groupDamage = enhancedSessionData.groupDamage,
        cooldownUsage = enhancedSessionData.cooldownUsage,
        deaths = enhancedSessionData.deaths,
        healingEvents = enhancedSessionData.healingEvents
    }
end

-- Get participants summary
function EnhancedCombatLogger:GetParticipantsSummary()
    local players = {}
    local npcs = {}
    local pets = {}

    for guid, participant in pairs(enhancedSessionData.participants) do
        if participant.isPlayer then
            table.insert(players, participant)
        elseif participant.isPet then
            table.insert(pets, participant)
        elseif participant.isNPC then
            table.insert(npcs, participant)
        end
    end

    -- Sort by damage dealt
    table.sort(players, function(a, b) return (a.damageDealt or 0) > (b.damageDealt or 0) end)
    table.sort(npcs, function(a, b) return (a.damageDealt or 0) > (b.damageDealt or 0) end)

    return {
        players = players,
        npcs = npcs,
        pets = pets
    }
end

-- Get cooldown timeline for chart overlay
function EnhancedCombatLogger:GetCooldownTimeline()
    return enhancedSessionData.cooldownUsage
end

-- Get damage taken timeline
function EnhancedCombatLogger:GetDamageTakenTimeline()
    return enhancedSessionData.damageTaken
end

-- =============================================================================
-- SESSION LIFECYCLE
-- =============================================================================

function EnhancedCombatLogger:StartEnhancedTracking()
    -- Reset all data structures
    enhancedSessionData = {
        participants = {},
        damageTaken = {},
        groupDamage = {},
        cooldownUsage = {},
        deaths = {},
        healingEvents = {}
    }

    if addon.DEBUG then
        addon:DebugPrint("Enhanced combat logging started - data structures reset")
    end
end

-- End enhanced tracking
function EnhancedCombatLogger:EndEnhancedTracking()
    if addon.DEBUG then
        local summary = self:GetParticipantsSummary()
        addon:DebugPrint(string.format("Enhanced logging ended: %d players, %d NPCs, %d cooldowns used, %d deaths",
            #summary.players, #summary.npcs, #enhancedSessionData.cooldownUsage, #enhancedSessionData.deaths))
    end
end

-- Reset enhanced data
function EnhancedCombatLogger:Reset()
    enhancedSessionData = {
        participants = {},
        damageTaken = {},
        groupDamage = {},
        cooldownUsage = {},
        deaths = {},
        healingEvents = {}
    }
end

-- =============================================================================
-- EVENT HANDLING
-- =============================================================================

-- Event handler
function EnhancedCombatLogger:OnEvent(event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:ParseEnhancedCombatLog(CombatLogGetCurrentEventInfo())
    end
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Initialize enhanced combat logger
function EnhancedCombatLogger:Initialize()
    self.frame = CreateFrame("Frame")
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.frame:SetScript("OnEvent", function(self, event, ...)
        EnhancedCombatLogger:OnEvent(event, ...)
    end)

    if addon.DEBUG then
    end
end
