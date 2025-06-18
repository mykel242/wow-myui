-- MetadataCollector.lua
-- Context gathering system for combat sessions

local addonName, addon = ...

-- Metadata Collector module
addon.MetadataCollector = {}
local MetadataCollector = addon.MetadataCollector

-- State tracking
local isInitialized = false
local currentMetadata = {}

-- Initialize the metadata collector
function MetadataCollector:Initialize()
    if isInitialized then
        return
    end
    
    -- Create event frame for context changes
    self.frame = CreateFrame("Frame", addonName .. "MetadataCollector")
    self.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.frame:RegisterEvent("PLAYER_LEVEL_UP")
    self.frame:SetScript("OnEvent", function(frame, event, ...)
        self:OnEvent(event, ...)
    end)
    
    -- Initialize current metadata
    self:RefreshMetadata()
    
    isInitialized = true
    
    addon:Debug("MetadataCollector initialized - tracking context changes")
end

-- Event handler for context changes
function MetadataCollector:OnEvent(event, ...)
    addon:Debug("MetadataCollector: Context changed (" .. event .. ")")
    
    -- Refresh metadata when context changes
    self:RefreshMetadata()
end

-- Collect comprehensive metadata about current context
function MetadataCollector:RefreshMetadata()
    currentMetadata = {
        -- Timestamp
        timestamp = GetTime(),
        serverTime = GetServerTime(),
        
        -- Player info
        player = {
            name = UnitName("player"),
            realm = GetRealmName(),
            class = UnitClass("player"),
            level = UnitLevel("player"),
            spec = self:GetPlayerSpecialization(),
            itemLevel = self:GetAverageItemLevel(),
        },
        
        -- Zone info
        zone = {
            name = GetZoneText(),
            subzone = GetSubZoneText(),
            mapID = C_Map.GetBestMapForUnit("player"),
            instanceInfo = self:GetInstanceInfo(),
        },
        
        -- Group composition
        group = self:GetGroupComposition(),
        
        -- Game version info
        client = {
            version = GetBuildInfo(),
            addonVersion = addon.VERSION,
        },
    }
    
    addon:Debug("Metadata refreshed: %s in %s (%s)", 
        currentMetadata.player.name,
        currentMetadata.zone.name,
        currentMetadata.group.type)
end

-- Get player specialization info
function MetadataCollector:GetPlayerSpecialization()
    local specIndex = GetSpecialization()
    if not specIndex then
        return {
            name = "None",
            role = "NONE",
            id = 0
        }
    end
    
    local id, name, description, icon, role = GetSpecializationInfo(specIndex)
    return {
        name = name,
        role = role,
        id = id,
        icon = icon
    }
end

-- Get average item level
function MetadataCollector:GetAverageItemLevel()
    local totalLevel = 0
    local itemCount = 0
    
    -- Check equipped items (slots 1-18, excluding shirt/tabard)
    local slots = {1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,18}
    
    for _, slot in ipairs(slots) do
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local itemLevel = GetDetailedItemLevelInfo(itemLink)
            if itemLevel and itemLevel > 0 then
                totalLevel = totalLevel + itemLevel
                itemCount = itemCount + 1
            end
        end
    end
    
    return itemCount > 0 and math.floor(totalLevel / itemCount) or 0
end

-- Get instance information
function MetadataCollector:GetInstanceInfo()
    local name, instanceType, difficultyID, difficultyName, maxPlayers, 
          dynamicDifficulty, isDynamic, instanceID, instanceGroupSize, 
          LfgDungeonID = GetInstanceInfo()
    
    return {
        name = name,
        type = instanceType,
        difficultyID = difficultyID,
        difficultyName = difficultyName,
        maxPlayers = maxPlayers,
        instanceID = instanceID,
        isLFG = LfgDungeonID ~= nil
    }
end

-- Get group composition details
function MetadataCollector:GetGroupComposition()
    local groupType = "solo"
    local size = 1
    local members = {}
    
    if IsInRaid() then
        groupType = "raid"
        size = GetNumGroupMembers()
        
        for i = 1, size do
            local unit = "raid" .. i
            if UnitExists(unit) then
                table.insert(members, self:GetUnitInfo(unit))
            end
        end
    elseif IsInGroup() then
        groupType = "party"
        size = GetNumGroupMembers()
        
        -- Add player
        table.insert(members, self:GetUnitInfo("player"))
        
        -- Add party members
        for i = 1, size - 1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                table.insert(members, self:GetUnitInfo(unit))
            end
        end
    else
        -- Solo
        table.insert(members, self:GetUnitInfo("player"))
    end
    
    return {
        type = groupType,
        size = size,
        members = members,
        roles = self:GetRoleDistribution(members)
    }
end

-- Get unit information
function MetadataCollector:GetUnitInfo(unit)
    local name = UnitName(unit)
    local class = UnitClass(unit)
    local level = UnitLevel(unit)
    local role = UnitGroupRolesAssigned(unit)
    
    return {
        name = name,
        class = class,
        level = level,
        role = role,
        isPlayer = UnitIsUnit(unit, "player")
    }
end

-- Analyze role distribution in group
function MetadataCollector:GetRoleDistribution(members)
    local roles = {
        TANK = 0,
        HEALER = 0,
        DAMAGER = 0,
        NONE = 0
    }
    
    for _, member in ipairs(members) do
        local role = member.role or "NONE"
        roles[role] = (roles[role] or 0) + 1
    end
    
    return roles
end

-- Public API methods
function MetadataCollector:GetCurrentMetadata()
    -- Return copy to prevent modification
    local metadata = {}
    for k, v in pairs(currentMetadata) do
        if type(v) == "table" then
            metadata[k] = {}
            for k2, v2 in pairs(v) do
                metadata[k][k2] = v2
            end
        else
            metadata[k] = v
        end
    end
    return metadata
end

function MetadataCollector:GetMetadataForCombat(combatId)
    -- Get current metadata snapshot for a combat session
    local metadata = self:GetCurrentMetadata()
    metadata.combatId = combatId
    metadata.captureTime = GetTime()
    
    return metadata
end

function MetadataCollector:IsInInstance()
    return currentMetadata.zone and currentMetadata.zone.instanceInfo and 
           currentMetadata.zone.instanceInfo.type ~= "none"
end

function MetadataCollector:GetInstanceType()
    if currentMetadata.zone and currentMetadata.zone.instanceInfo then
        return currentMetadata.zone.instanceInfo.type
    end
    return "none"
end

function MetadataCollector:GetGroupType()
    return currentMetadata.group and currentMetadata.group.type or "solo"
end

function MetadataCollector:GetStatus()
    return {
        isInitialized = isInitialized,
        lastUpdate = currentMetadata.timestamp,
        zone = currentMetadata.zone and currentMetadata.zone.name or "Unknown",
        groupType = self:GetGroupType(),
        groupSize = currentMetadata.group and currentMetadata.group.size or 1
    }
end

-- Debug summary for slash commands
function MetadataCollector:GetDebugSummary()
    local status = self:GetStatus()
    local meta = currentMetadata
    
    return string.format(
        "MetadataCollector Status:\n" ..
        "  Initialized: %s\n" ..
        "  Current Zone: %s\n" ..
        "  Instance: %s (%s)\n" ..
        "  Group: %s (%d members)\n" ..
        "  Player: %s %s (L%d, iLvl %d)",
        tostring(status.isInitialized),
        status.zone,
        meta.zone and meta.zone.instanceInfo.name or "None",
        meta.zone and meta.zone.instanceInfo.type or "none",
        status.groupType,
        status.groupSize,
        meta.player and meta.player.name or "Unknown",
        meta.player and meta.player.spec.name or "Unknown",
        meta.player and meta.player.level or 0,
        meta.player and meta.player.itemLevel or 0
    )
end