--[[
==================================================================================
⚠️  DEPRECATED - DO NOT USE ⚠️  
==================================================================================

This file is DEPRECATED and replaced by MyCombatMeterCalculator.lua

Original Purpose: Legacy calculation system from prototype
Replacement: src/core/MyCombatMeterCalculator.lua 
Deprecated Date: 2025-06-20
Status: Not loaded in TOC file

This file is kept for reference only. All calculation functionality has been
moved to the new modular MyCombatMeterCalculator.lua system.

==================================================================================
--]]

local addonName, addon = ...

addon.UnifiedCalculator = {}
local UnifiedCalculator = addon.UnifiedCalculator
UnifiedCalculator.__index = UnifiedCalculator

local CALCULATION_METHODS = {
    ROLLING_AVERAGE = "rolling_average",
    FINAL_TOTAL = "final_total",
    HYBRID = "hybrid"
}

local DEFAULT_CONFIG = {
    method = CALCULATION_METHODS.ROLLING_AVERAGE,
    rollingWindowSize = 5.0,
    sampleInterval = 0.5,
    peakTrackingDelay = 1.5,
    maxDPSSanity = 10000000,
    maxHPSSanity = 5000000,
    minDeltaSanity = 0.1,
    enableValidation = true
}

function UnifiedCalculator:New(config)
    local self = setmetatable({}, UnifiedCalculator)
    self.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        self.config[k] = (config and config[k]) or v
    end
    
    self.timelineTracker = nil
    self.combatData = nil
    self.validationResults = {}
    
    return self
end

function UnifiedCalculator:SetTimelineTracker(tracker)
    self.timelineTracker = tracker
end

function UnifiedCalculator:SetCombatData(combatData)
    self.combatData = combatData
end

function UnifiedCalculator:GetDPS(useDisplayMethod)
    if not self.combatData then return 0 end
    
    local inCombat = self.combatData:IsInCombat()
    
    if self.config.method == CALCULATION_METHODS.ROLLING_AVERAGE then
        return self:_GetRollingDPS(inCombat)
    elseif self.config.method == CALCULATION_METHODS.FINAL_TOTAL then
        return self:_GetFinalDPS(inCombat)
    elseif self.config.method == CALCULATION_METHODS.HYBRID then
        return self:_GetHybridDPS(inCombat)
    end
    
    return 0
end

function UnifiedCalculator:GetHPS(useDisplayMethod)
    if not self.combatData then return 0 end
    
    local inCombat = self.combatData:IsInCombat()
    
    if self.config.method == CALCULATION_METHODS.ROLLING_AVERAGE then
        return self:_GetRollingHPS(inCombat)
    elseif self.config.method == CALCULATION_METHODS.FINAL_TOTAL then
        return self:_GetFinalHPS(inCombat)
    elseif self.config.method == CALCULATION_METHODS.HYBRID then
        return self:_GetHybridHPS(inCombat)
    end
    
    return 0
end

function UnifiedCalculator:GetMaxDPS()
    if not self.combatData then return 0 end
    
    -- Access raw combat data directly to avoid circular dependency
    local rawData = self.combatData:GetRawData()
    if not rawData then return 0 end
    
    if not rawData.inCombat and rawData.finalMaxDPS > 0 then
        return rawData.finalMaxDPS
    end
    return rawData.maxDPS
end

function UnifiedCalculator:GetMaxHPS()
    if not self.combatData then return 0 end
    
    -- Access raw combat data directly to avoid circular dependency
    local rawData = self.combatData:GetRawData()
    if not rawData then return 0 end
    
    if not rawData.inCombat and rawData.finalMaxHPS > 0 then
        return rawData.finalMaxHPS
    end
    return rawData.maxHPS
end

function UnifiedCalculator:_GetRollingDPS(inCombat)
    if inCombat and self.timelineTracker then
        return self.timelineTracker:GetRollingDPS()
    else
        -- When not in combat or no timeline tracker, use final calculation
        return self:_GetFinalDPS(inCombat)
    end
end

function UnifiedCalculator:_GetRollingHPS(inCombat)
    if inCombat and self.timelineTracker then
        return self.timelineTracker:GetRollingHPS()
    else
        -- When not in combat or no timeline tracker, use final calculation
        return self:_GetFinalHPS(inCombat)
    end
end

function UnifiedCalculator:_GetFinalDPS(inCombat)
    if not self.combatData then return 0 end
    
    local elapsed = self.combatData:GetElapsed()
    if elapsed <= 0 then return 0 end
    
    local rawData = self.combatData:GetRawData()
    if not rawData then return 0 end
    
    return rawData.damage / elapsed
end

function UnifiedCalculator:_GetFinalHPS(inCombat)
    if not self.combatData then return 0 end
    
    local elapsed = self.combatData:GetElapsed()
    if elapsed <= 0 then return 0 end
    
    local rawData = self.combatData:GetRawData()
    if not rawData then return 0 end
    
    return rawData.healing / elapsed
end

function UnifiedCalculator:_GetHybridDPS(inCombat)
    local rollingDPS = self:_GetRollingDPS(inCombat)
    local finalDPS = self:_GetFinalDPS(inCombat)
    
    if inCombat then
        if self.combatData and self.combatData:GetElapsed() > self.config.peakTrackingDelay then
            return (rollingDPS * 0.7) + (finalDPS * 0.3)
        else
            return rollingDPS
        end
    else
        return finalDPS
    end
end

function UnifiedCalculator:_GetHybridHPS(inCombat)
    local rollingHPS = self:_GetRollingHPS(inCombat)
    local finalHPS = self:_GetFinalHPS(inCombat)
    
    if inCombat then
        if self.combatData and self.combatData:GetElapsed() > self.config.peakTrackingDelay then
            return (rollingHPS * 0.7) + (finalHPS * 0.3)
        else
            return rollingHPS
        end
    else
        return finalHPS
    end
end

function UnifiedCalculator:ValidateCalculations()
    if not self.config.enableValidation then return true end
    
    local rollingDPS = self:_GetRollingDPS(self.combatData and self.combatData:IsInCombat())
    local finalDPS = self:_GetFinalDPS(self.combatData and self.combatData:IsInCombat())
    local rollingHPS = self:_GetRollingHPS(self.combatData and self.combatData:IsInCombat())
    local finalHPS = self:_GetFinalHPS(self.combatData and self.combatData:IsInCombat())
    
    self.validationResults = {
        rollingDPS = rollingDPS,
        finalDPS = finalDPS,
        rollingHPS = rollingHPS,
        finalHPS = finalHPS,
        dpsVariance = math.abs(rollingDPS - finalDPS),
        hpsVariance = math.abs(rollingHPS - finalHPS),
        dpsPercentageVariance = finalDPS > 0 and (math.abs(rollingDPS - finalDPS) / finalDPS) * 100 or 0,
        hpsPercentageVariance = finalHPS > 0 and (math.abs(rollingHPS - finalHPS) / finalHPS) * 100 or 0,
        timestamp = GetTime(),
        combatDuration = self.combatData and self.combatData:GetElapsed() or 0,
        inCombat = self.combatData and self.combatData:IsInCombat() or false
    }
    
    return self.validationResults.dpsPercentageVariance < 20 and self.validationResults.hpsPercentageVariance < 20
end

function UnifiedCalculator:GetDetailedValidation()
    if not self.validationResults then
        self:ValidateCalculations()
    end
    
    local results = self.validationResults
    if not results then return nil end
    
    return {
        summary = {
            consistent = results.dpsPercentageVariance < 10 and results.hpsPercentageVariance < 10,
            dpsVariancePercent = results.dpsPercentageVariance,
            hpsVariancePercent = results.hpsPercentageVariance
        },
        details = {
            rollingMethod = {
                dps = results.rollingDPS,
                hps = results.rollingHPS
            },
            finalMethod = {
                dps = results.finalDPS,
                hps = results.finalHPS
            },
            variance = {
                dps = results.dpsVariance,
                hps = results.hpsVariance
            },
            combat = {
                duration = results.combatDuration,
                inCombat = results.inCombat,
                timestamp = results.timestamp
            }
        }
    }
end

function UnifiedCalculator:GetValidationResults()
    return self.validationResults
end

function UnifiedCalculator:GetCalculationMethod()
    return self.config.method
end

function UnifiedCalculator:SetCalculationMethod(method)
    -- Check if the method is one of the valid values
    local validMethod = false
    for _, validValue in pairs(CALCULATION_METHODS) do
        if validValue == method then
            validMethod = true
            break
        end
    end
    
    if validMethod then
        self.config.method = method
        -- Save to persistent storage
        if addon and addon.db then
            addon.db.calculationMethod = method
        end
        return true
    end
    return false
end

function UnifiedCalculator:GetConfig()
    return self.config
end

function UnifiedCalculator:UpdateConfig(newConfig)
    for k, v in pairs(newConfig) do
        if self.config[k] ~= nil then
            self.config[k] = v
        end
    end
end

UnifiedCalculator.CALCULATION_METHODS = CALCULATION_METHODS