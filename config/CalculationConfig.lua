local addonName, addon = ...

addon.CalculationConfig = {}
local CalculationConfig = addon.CalculationConfig


local function CreateConfigWindow()
    local frame = CreateFrame("Frame", addonName .. "CalculationConfigFrame", UIParent)
    frame:SetSize(400, 300)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 0.9)
    
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetAllPoints(frame)
    border:SetColorTexture(0.4, 0.4, 0.4, 1)
    bg:SetPoint("TOPLEFT", border, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)
    
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    
    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 14, "OUTLINE")
    title:SetPoint("TOP", frame, "TOP", 0, -15)
    title:SetText("HPS/DPS Calculation Settings")
    title:SetTextColor(1, 1, 1, 1)
    
    local calculator = addon.CombatData:GetCalculator()
    if not calculator then
        local errorText = frame:CreateFontString(nil, "OVERLAY")
        errorText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
        errorText:SetPoint("CENTER", frame, "CENTER", 0, 0)
        errorText:SetText("Calculator not available")
        errorText:SetTextColor(1, 0, 0, 1)
        return frame
    end
    
    local currentMethod = calculator:GetCalculationMethod()
    local config = calculator:GetConfig()
    
    local methodLabel = frame:CreateFontString(nil, "OVERLAY")
    methodLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    methodLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -50)
    methodLabel:SetText("Calculation Method:")
    methodLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    
    local methodButtons = {}
    local yOffset = -80
    
    for methodKey, methodName in pairs(addon.UnifiedCalculator.CALCULATION_METHODS) do
        local button = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yOffset)
        button:SetSize(20, 20)
        
        local label = frame:CreateFontString(nil, "OVERLAY")
        label:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 11, "OUTLINE")
        label:SetPoint("LEFT", button, "RIGHT", 5, 0)
        label:SetTextColor(0.8, 0.8, 0.8, 1)
        
        if methodName == addon.UnifiedCalculator.CALCULATION_METHODS.ROLLING_AVERAGE then
            label:SetText("Rolling Average (5-second window)")
        elseif methodName == addon.UnifiedCalculator.CALCULATION_METHODS.FINAL_TOTAL then
            label:SetText("Final Total (damage/time)")
        elseif methodName == addon.UnifiedCalculator.CALCULATION_METHODS.HYBRID then
            label:SetText("Hybrid (70% rolling, 30% final)")
        end
        
        button:SetChecked(currentMethod == methodName)
        button.methodName = methodName
        methodButtons[methodName] = button
        
        button:SetScript("OnClick", function(self)
            for _, otherButton in pairs(methodButtons) do
                otherButton:SetChecked(false)
            end
            self:SetChecked(true)
            
            if calculator:SetCalculationMethod(self.methodName) then
                print("Calculation method changed to:", self.methodName)
                
                if calculator:ValidateCalculations() then
                    local validation = calculator:GetValidationResults()
                    print(string.format("Validation: DPS variance %.1f%%, HPS variance %.1f%%",
                        validation.dpsPercentageVariance, validation.hpsPercentageVariance))
                end
            end
        end)
        
        yOffset = yOffset - 30
    end
    
    local validationLabel = frame:CreateFontString(nil, "OVERLAY")
    validationLabel:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 12, "OUTLINE")
    validationLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yOffset - 10)
    validationLabel:SetText("Validation:")
    validationLabel:SetTextColor(0.8, 0.8, 0.8, 1)
    
    local validateButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    validateButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yOffset - 35)
    validateButton:SetSize(150, 25)
    validateButton:SetText("Validate Calculations")
    validateButton:SetScript("OnClick", function()
        if calculator:ValidateCalculations() then
            local validation = calculator:GetValidationResults()
            print("=== CALCULATION VALIDATION ===")
            
            if validation.inCombat then
                print("Combat Status: IN COMBAT (live validation)")
                print(string.format("Rolling DPS: %.0f | Final DPS: %.0f", 
                    validation.rollingDPS, validation.finalDPS))
                print(string.format("Rolling HPS: %.0f | Final HPS: %.0f", 
                    validation.rollingHPS, validation.finalHPS))
                print(string.format("DPS Variance: %.1f%% (%.0f difference)", 
                    validation.dpsPercentageVariance, validation.dpsVariance))
                print(string.format("HPS Variance: %.1f%% (%.0f difference)", 
                    validation.hpsPercentageVariance, validation.hpsVariance))
                
                if validation.dpsPercentageVariance < 10 and validation.hpsPercentageVariance < 10 then
                    print("✓ Calculations are consistent")
                else
                    print("⚠ High variance detected - methods differ significantly")
                end
            else
                print("Combat Status: OUT OF COMBAT")
                print("Note: Both methods return final values when not in combat")
                print(string.format("Final DPS: %.0f | Final HPS: %.0f", 
                    validation.finalDPS, validation.finalHPS))
                print("✓ No variance expected (both methods use same final calculation)")
                print("💡 Start combat to see live method differences")
            end
        else
            print("Validation failed or calculator not available")
        end
    end)
    
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    closeButton:SetSize(75, 25)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    local infoText = frame:CreateFontString(nil, "OVERLAY")
    infoText:SetFont("Interface\\AddOns\\myui2\\assets\\SCP-SB.ttf", 10, "OUTLINE")
    infoText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 40)
    infoText:SetText("Changes apply immediately to all meters and session recording")
    infoText:SetTextColor(0.6, 0.6, 0.6, 1)
    
    return frame
end

function CalculationConfig:ShowConfigWindow()
    if not self.configFrame then
        self.configFrame = CreateConfigWindow()
        self.configFrame:Show()
    else
        if self.configFrame:IsShown() then
            self.configFrame:Hide()
        else
            self.configFrame:Show()
        end
    end
end

function CalculationConfig:Initialize()
    addon:Debug("CalculationConfig module initialized")
end

