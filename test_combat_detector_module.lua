-- Syntax test for MySimpleCombatDetector
-- This will help us find syntax errors

-- Mock the WoW API and addon structure that the file expects
local addonName = "test"
local addon = {}

-- Load the file
local success, errorMsg = pcall(function()
    loadfile("src/core/MySimpleCombatDetector.lua")(addonName, addon)
end)

if success then
    print("✅ MySimpleCombatDetector.lua syntax is valid!")
    if addon.MySimpleCombatDetector then
        print("✅ Module loaded successfully")
    else
        print("❌ Module didn't attach to addon table")
    end
else
    print("❌ Syntax error in MySimpleCombatDetector.lua:")
    print(errorMsg)
end