-- EntityBlacklist.lua
-- Manages blacklists for entities that should be filtered from death indicators
-- Supports both class/spec-specific and encounter-specific blacklists

local addonName, MyUI2 = ...

-- Initialize blacklist manager
MyUI2.EntityBlacklist = MyUI2.EntityBlacklist or {}
local EntityBlacklist = MyUI2.EntityBlacklist

-- Default blacklist data (can be overridden by saved variables)
local defaultBlacklists = {
    -- Global blacklist (applies to all classes/specs)
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
    
    -- Encounter-specific blacklists (by zone/boss name)
    encounters = {
        ["Liberation of Undermine"] = {
            ["Mug'Zee"] = {
                "unstable crawler mine",
                "explosive charge",
                "mining cart"
            }
        }
    }
}

-- Saved variables for user customizations
EntityBlacklistDB = EntityBlacklistDB or {}

-- Initialize the blacklist system
function EntityBlacklist:Initialize()
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
    
    if not EntityBlacklistDB.encounters then
        EntityBlacklistDB.encounters = {}
        for zone, encounters in pairs(defaultBlacklists.encounters) do
            EntityBlacklistDB.encounters[zone] = EntityBlacklistDB.encounters[zone] or {}
            for boss, entities in pairs(encounters) do
                EntityBlacklistDB.encounters[zone][boss] = EntityBlacklistDB.encounters[zone][boss] or {}
                for _, entity in ipairs(entities) do
                    EntityBlacklistDB.encounters[zone][boss][entity] = true
                end
            end
        end
    end
    
    -- Register slash commands
    self:RegisterSlashCommands()
    
    if MyUI2 and MyUI2.DEBUG then
        print("MyUI2: EntityBlacklist initialized with " .. 
              (EntityBlacklistDB.global and self:TableCount(EntityBlacklistDB.global) or 0) .. " global entries")
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
function EntityBlacklist:IsBlacklisted(entityName, playerClass, zone, encounter)
    if not entityName then return false end
    
    local lowerName = string.lower(entityName or "")
    
    -- Check global blacklist
    for pattern, _ in pairs(EntityBlacklistDB.global or {}) do
        if string.find(lowerName, string.lower(pattern)) then
            return true
        end
    end
    
    -- Check class-specific blacklist
    if playerClass and EntityBlacklistDB.classes and EntityBlacklistDB.classes[playerClass] then
        for pattern, _ in pairs(EntityBlacklistDB.classes[playerClass]) do
            if string.find(lowerName, string.lower(pattern)) then
                return true
            end
        end
    end
    
    -- Check encounter-specific blacklist
    if zone and encounter and EntityBlacklistDB.encounters and 
       EntityBlacklistDB.encounters[zone] and EntityBlacklistDB.encounters[zone][encounter] then
        for pattern, _ in pairs(EntityBlacklistDB.encounters[zone][encounter]) do
            if string.find(lowerName, string.lower(pattern)) then
                return true
            end
        end
    end
    
    return false
end

-- Add entity to blacklist
function EntityBlacklist:AddToBlacklist(entityName, blacklistType, classOrZone, encounter)
    if not entityName or entityName == "" then return false end
    
    local lowerName = string.lower(entityName)
    
    if blacklistType == "global" then
        EntityBlacklistDB.global = EntityBlacklistDB.global or {}
        EntityBlacklistDB.global[lowerName] = true
        return true
    elseif blacklistType == "class" and classOrZone then
        EntityBlacklistDB.classes = EntityBlacklistDB.classes or {}
        EntityBlacklistDB.classes[classOrZone] = EntityBlacklistDB.classes[classOrZone] or {}
        EntityBlacklistDB.classes[classOrZone][lowerName] = true
        return true
    elseif blacklistType == "encounter" and classOrZone and encounter then
        EntityBlacklistDB.encounters = EntityBlacklistDB.encounters or {}
        EntityBlacklistDB.encounters[classOrZone] = EntityBlacklistDB.encounters[classOrZone] or {}
        EntityBlacklistDB.encounters[classOrZone][encounter] = EntityBlacklistDB.encounters[classOrZone][encounter] or {}
        EntityBlacklistDB.encounters[classOrZone][encounter][lowerName] = true
        return true
    end
    
    return false
end

-- Remove entity from blacklist
function EntityBlacklist:RemoveFromBlacklist(entityName, blacklistType, classOrZone, encounter)
    if not entityName or entityName == "" then return false end
    
    local lowerName = string.lower(entityName)
    
    if blacklistType == "global" and EntityBlacklistDB.global then
        EntityBlacklistDB.global[lowerName] = nil
        return true
    elseif blacklistType == "class" and classOrZone and EntityBlacklistDB.classes and EntityBlacklistDB.classes[classOrZone] then
        EntityBlacklistDB.classes[classOrZone][lowerName] = nil
        return true
    elseif blacklistType == "encounter" and classOrZone and encounter and 
           EntityBlacklistDB.encounters and EntityBlacklistDB.encounters[classOrZone] and 
           EntityBlacklistDB.encounters[classOrZone][encounter] then
        EntityBlacklistDB.encounters[classOrZone][encounter][lowerName] = nil
        return true
    end
    
    return false
end

-- Get current player class for blacklist checks
function EntityBlacklist:GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- Get current zone and encounter info
function EntityBlacklist:GetCurrentEncounter()
    local zone = GetRealZoneText() or GetZoneText() or "Unknown"
    
    -- Try to detect current encounter from various sources
    local encounter = nil
    
    -- Check if we're in a boss encounter
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        -- Get encounter ID if available
        local encounterID = GetCurrentEncounterID and GetCurrentEncounterID()
        if encounterID and encounterID > 0 then
            local encounterName = EJ_GetEncounterInfo and EJ_GetEncounterInfo(encounterID)
            if encounterName then
                encounter = encounterName
            end
        end
        
        -- Fallback: try to get from unit frames (target boss names)
        if not encounter then
            for i = 1, 4 do
                local unitID = "boss" .. i
                if UnitExists(unitID) then
                    local bossName = UnitName(unitID)
                    if bossName and bossName ~= "" then
                        encounter = bossName
                        break
                    end
                end
            end
        end
        
        -- Fallback: check target if it's a boss
        if not encounter then
            if UnitExists("target") and UnitClassification("target") == "worldboss" then
                encounter = UnitName("target")
            end
        end
    end
    
    return zone, encounter
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

-- Register slash command integration (to be called from main addon)
function EntityBlacklist:RegisterSlashCommands()
    -- This will be integrated with the main addon's slash command system
    -- For now, we just store the handler
    self.SlashCommandHandler = HandleBlacklistCommand
end