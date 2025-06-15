-- EntityBlacklist.lua
-- Manages blacklists for entities that should be filtered from death indicators
-- Supports both class/spec-specific and encounter-specific blacklists

local addonName, MyUI2 = ...

-- Initialize blacklist manager
MyUI2.EntityBlacklist = MyUI2.EntityBlacklist or {}
local EntityBlacklist = MyUI2.EntityBlacklist

-- Default blacklist data (can be overridden by saved variables)
local defaultBlacklists = {
    -- Global blacklist (applies everywhere)
    global = {
        "totem",
        "spirit", 
        "guardian",
        "elemental",
        "echo",
        "image", 
        "duplicate",
        "reflection",
        "entropic rift",
        "mindbender"
    },
    
    -- Class-specific blacklists
    classes = {
        PRIEST = {
            "voidweaver",
            "shadowfiend",
            "psychic horror"
        },
        WARLOCK = {
            "felguard",
            "voidwalker", 
            "succubus",
            "felhunter",
            "doomguard",
            "infernal"
        },
        HUNTER = {
            "spirit beast",
            "dire beast"
        }
    },
    
    -- Zone-specific blacklists (by zone name only)
    zones = {
        ["Liberation of Undermine"] = {
            "unstable crawler mine",
            "explosive charge",
            "mining cart"
        }
    }
}

-- Saved variables for user customizations
EntityBlacklistDB = EntityBlacklistDB or {}

-- Initialize the blacklist system
function EntityBlacklist:Initialize()
    -- Migrate existing encounter-specific data to zone-specific (if needed)
    if EntityBlacklistDB.encounters then
        print("MyUI2: Migrating encounter-specific blacklists to zone-specific...")
        if not EntityBlacklistDB.zones then
            EntityBlacklistDB.zones = {}
        end
        
        -- Migrate encounter data to zone data
        for zoneName, encounters in pairs(EntityBlacklistDB.encounters) do
            EntityBlacklistDB.zones[zoneName] = EntityBlacklistDB.zones[zoneName] or {}
            for bossName, entities in pairs(encounters) do
                for entityName, enabled in pairs(entities) do
                    -- Merge into zone-specific blacklist
                    EntityBlacklistDB.zones[zoneName][entityName] = enabled
                end
            end
        end
        
        -- Remove old encounters structure
        EntityBlacklistDB.encounters = nil
        print("MyUI2: Migration complete - encounter-specific blacklists moved to zone-specific")
    end
    
    -- Merge default blacklists with saved customizations
    if not EntityBlacklistDB.global then
        EntityBlacklistDB.global = {}
        for _, entity in ipairs(defaultBlacklists.global) do
            EntityBlacklistDB.global[entity] = true
        end
    end
    
    if not EntityBlacklistDB.classes then
        EntityBlacklistDB.classes = {}
        for class, entities in pairs(defaultBlacklists.classes) do
            EntityBlacklistDB.classes[class] = EntityBlacklistDB.classes[class] or {}
            for _, entity in ipairs(entities) do
                EntityBlacklistDB.classes[class][entity] = true
            end
        end
    end
    
    if not EntityBlacklistDB.zones then
        EntityBlacklistDB.zones = {}
        for zone, entities in pairs(defaultBlacklists.zones) do
            EntityBlacklistDB.zones[zone] = EntityBlacklistDB.zones[zone] or {}
            for _, entity in ipairs(entities) do
                EntityBlacklistDB.zones[zone][entity] = true
            end
        end
    end
    
    -- Register slash commands
    self:RegisterSlashCommands()
    
    if MyUI2 and MyUI2.DEBUG then
        print("MyUI2: EntityBlacklist initialized with " .. 
              (EntityBlacklistDB.global and self:TableCount(EntityBlacklistDB.global) or 0) .. " global entries, " ..
              (EntityBlacklistDB.zones and self:TableCount(EntityBlacklistDB.zones) or 0) .. " zone-specific lists")
    end
end

-- Helper function to count table entries
function EntityBlacklist:TableCount(t)
    local count = 0
    if t then
        for _ in pairs(t) do
            count = count + 1
        end
    end
    return count
end

-- Check if an entity should be blacklisted
function EntityBlacklist:IsBlacklisted(entityName, playerClass, zone)
    if not entityName then return false end
    
    local lowerName = string.lower(entityName or "")
    
    -- Debug output removed for cleaner user experience
    
    -- Helper function for flexible pattern matching
    local function matchesPattern(entityName, pattern)
        local lowerName = string.lower(entityName)
        local lowerPattern = string.lower(pattern)
        
        -- Try exact substring match first
        if string.find(lowerName, lowerPattern) then
            return true
        end
        
        -- Try flexible matching for patterns with spaces - match if all words are present
        if string.find(lowerPattern, " ") then
            local allWordsMatch = true
            for word in string.gmatch(lowerPattern, "%S+") do
                if not string.find(lowerName, word) then
                    allWordsMatch = false
                    break
                end
            end
            return allWordsMatch
        end
        
        return false
    end
    
    -- Check global blacklist (only if enabled)
    for pattern, enabled in pairs(EntityBlacklistDB.global or {}) do
        if enabled and matchesPattern(entityName, pattern) then
            return true
        end
    end
    
    -- Check class-specific blacklist (only if enabled)
    if playerClass and EntityBlacklistDB.classes and EntityBlacklistDB.classes[playerClass] then
        for pattern, enabled in pairs(EntityBlacklistDB.classes[playerClass]) do
            if enabled and matchesPattern(entityName, pattern) then
                return true
            end
        end
    end
    
    -- Check zone-specific blacklist (only if enabled)
    if zone and EntityBlacklistDB.zones and EntityBlacklistDB.zones[zone] then
        for pattern, enabled in pairs(EntityBlacklistDB.zones[zone]) do
            if enabled and matchesPattern(entityName, pattern) then
                return true
            end
        end
    end
    
    return false
end

-- Add entity to blacklist
function EntityBlacklist:AddToBlacklist(entityName, blacklistType, classOrZone)
    if not entityName or entityName == "" then return false end
    
    -- Preserve original formatting for storage and display
    -- The IsBlacklisted function handles case-insensitive matching
    
    if blacklistType == "global" then
        EntityBlacklistDB.global = EntityBlacklistDB.global or {}
        EntityBlacklistDB.global[entityName] = true
        return true
    elseif blacklistType == "class" and classOrZone then
        EntityBlacklistDB.classes = EntityBlacklistDB.classes or {}
        EntityBlacklistDB.classes[classOrZone] = EntityBlacklistDB.classes[classOrZone] or {}
        EntityBlacklistDB.classes[classOrZone][entityName] = true
        return true
    elseif blacklistType == "zone" and classOrZone then
        EntityBlacklistDB.zones = EntityBlacklistDB.zones or {}
        EntityBlacklistDB.zones[classOrZone] = EntityBlacklistDB.zones[classOrZone] or {}
        EntityBlacklistDB.zones[classOrZone][entityName] = true
        return true
    end
    
    return false
end

-- Remove entity from blacklist (requires exact name match for removal)
function EntityBlacklist:RemoveFromBlacklist(entityName, blacklistType, classOrZone)
    if not entityName or entityName == "" then return false end
    
    -- For removal, we need to find the exact stored key
    -- Since we now store original format, this should work with exact matches
    
    if blacklistType == "global" and EntityBlacklistDB.global then
        EntityBlacklistDB.global[entityName] = nil
        return true
    elseif blacklistType == "class" and classOrZone and EntityBlacklistDB.classes and EntityBlacklistDB.classes[classOrZone] then
        EntityBlacklistDB.classes[classOrZone][entityName] = nil
        return true
    elseif blacklistType == "zone" and classOrZone and EntityBlacklistDB.zones and EntityBlacklistDB.zones[classOrZone] then
        EntityBlacklistDB.zones[classOrZone][entityName] = nil
        return true
    end
    
    return false
end

-- Toggle enable/disable state of blacklist entry
function EntityBlacklist:ToggleBlacklistEntry(entityName, blacklistType, classOrZone)
    if not entityName or entityName == "" then return false end
    
    local currentState = false
    
    if blacklistType == "global" and EntityBlacklistDB.global then
        currentState = EntityBlacklistDB.global[entityName] or false
        EntityBlacklistDB.global[entityName] = not currentState
        return true
    elseif blacklistType == "class" and classOrZone and EntityBlacklistDB.classes and EntityBlacklistDB.classes[classOrZone] then
        currentState = EntityBlacklistDB.classes[classOrZone][entityName] or false
        EntityBlacklistDB.classes[classOrZone][entityName] = not currentState
        return true
    elseif blacklistType == "zone" and classOrZone and EntityBlacklistDB.zones and EntityBlacklistDB.zones[classOrZone] then
        currentState = EntityBlacklistDB.zones[classOrZone][entityName] or false
        EntityBlacklistDB.zones[classOrZone][entityName] = not currentState
        return true
    end
    
    return false
end

-- Get enable/disable state of blacklist entry
function EntityBlacklist:GetBlacklistEntryState(entityName, blacklistType, classOrZone)
    if not entityName or entityName == "" then return false end
    
    if blacklistType == "global" and EntityBlacklistDB.global then
        return EntityBlacklistDB.global[entityName] or false
    elseif blacklistType == "class" and classOrZone and EntityBlacklistDB.classes and EntityBlacklistDB.classes[classOrZone] then
        return EntityBlacklistDB.classes[classOrZone][entityName] or false
    elseif blacklistType == "zone" and classOrZone and EntityBlacklistDB.zones and EntityBlacklistDB.zones[classOrZone] then
        return EntityBlacklistDB.zones[classOrZone][entityName] or false
    end
    
    return false
end

-- Get current player class for blacklist checks
function EntityBlacklist:GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- Get current zone info
function EntityBlacklist:GetCurrentZone()
    return GetRealZoneText() or GetZoneText() or "Unknown"
end

-- Export blacklist data for backup/sharing
function EntityBlacklist:ExportBlacklists()
    return EntityBlacklistDB
end

-- Import blacklist data
function EntityBlacklist:ImportBlacklists(data)
    if type(data) == "table" then
        EntityBlacklistDB = data
        return true
    end
    return false
end

-- Slash command handlers
local function ShowBlacklistCommands()
    print("|cff00ff00MyUI2 Entity Blacklist Commands:|r")
    print("  /myui2 blacklist show [global|class|encounter] - Show blacklist entries")
    print("  /myui2 blacklist add <entity_name> [global|class|encounter] - Add entity to blacklist")
    print("  /myui2 blacklist remove <entity_name> [global|class|encounter] - Remove entity from blacklist")
    print("  /myui2 blacklist clear [global|class|encounter] - Clear blacklist (be careful!)")
    print("  /myui2 blacklist test <entity_name> - Test if entity would be blacklisted")
end

local function HandleBlacklistCommand(args)
    local cmd = args[1]
    
    if not cmd or cmd == "help" then
        ShowBlacklistCommands()
        return
    end
    
    if cmd == "show" then
        local listType = args[2] or "all"
        local playerClass = EntityBlacklist:GetPlayerClass()
        local zone, encounter = EntityBlacklist:GetCurrentEncounter()
        
        if listType == "all" or listType == "global" then
            print("|cffyellow(Global Blacklist:|r")
            if EntityBlacklistDB.global then
                for entity, _ in pairs(EntityBlacklistDB.global) do
                    print("  - " .. entity)
                end
            else
                print("  (empty)")
            end
        end
        
        if listType == "all" or listType == "class" then
            print("|cff00ff00Class Blacklist (" .. (playerClass or "Unknown") .. "):|r")
            if EntityBlacklistDB.classes and EntityBlacklistDB.classes[playerClass] then
                for entity, _ in pairs(EntityBlacklistDB.classes[playerClass]) do
                    print("  - " .. entity)
                end
            else
                print("  (empty)")
            end
        end
        
        if listType == "all" or listType == "encounter" then
            print("|cff9999ffEncounter Blacklist (" .. (zone or "Unknown") .. " - " .. (encounter or "No encounter") .. "):|r")
            if zone and encounter and EntityBlacklistDB.encounters and 
               EntityBlacklistDB.encounters[zone] and EntityBlacklistDB.encounters[zone][encounter] then
                for entity, _ in pairs(EntityBlacklistDB.encounters[zone][encounter]) do
                    print("  - " .. entity)
                end
            else
                print("  (empty)")
            end
        end
        
    elseif cmd == "test" then
        local entityName = args[2]
        if not entityName then
            print("|cffff0000Error:|r Please specify an entity name to test")
            return
        end
        
        local playerClass = EntityBlacklist:GetPlayerClass()
        local zone, encounter = EntityBlacklist:GetCurrentEncounter()
        local isBlacklisted = EntityBlacklist:IsBlacklisted(entityName, playerClass, zone, encounter)
        
        if isBlacklisted then
            print("|cffff0000Entity '" .. entityName .. "' would be BLACKLISTED|r")
        else
            print("|cff00ff00Entity '" .. entityName .. "' would NOT be blacklisted|r")
        end
        print("Current context: Class=" .. (playerClass or "Unknown") .. ", Zone=" .. (zone or "Unknown") .. ", Encounter=" .. (encounter or "None"))
        
    else
        print("|cffff0000Unknown blacklist command:|r " .. cmd)
        ShowBlacklistCommands()
    end
end

-- Filter deaths array based on current blacklist settings (for reporting)
function EntityBlacklist:FilterDeaths(deaths, playerClass, zone)
    if not deaths then return {} end
    
    local filteredDeaths = {}
    
    for _, death in ipairs(deaths) do
        if death.destName and death.destName ~= "" then
            -- Check if this death should be filtered out
            if not self:IsBlacklisted(death.destName, playerClass, zone) then
                table.insert(filteredDeaths, death)
            end
        end
    end
    
    return filteredDeaths
end

-- Filter deaths array using current context (convenience function)
function EntityBlacklist:FilterDeathsForCurrentContext(deaths)
    local playerClass = self:GetPlayerClass()
    local zone = self:GetCurrentZone()
    return self:FilterDeaths(deaths, playerClass, zone)
end

-- Register slash command integration (to be called from main addon)
function EntityBlacklist:RegisterSlashCommands()
    -- This will be integrated with the main addon's slash command system
    -- For now, we just store the handler
    self.SlashCommandHandler = HandleBlacklistCommand
end