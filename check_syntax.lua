#!/usr/bin/env lua
-- Syntax checker for MyUI2 Lua files

local files = {
    "src/core/MyLogger.lua",
    "src/core/MyTimestampManager.lua", 
    "src/core/MySimpleCombatDetector.lua",
    "MyUI.lua"
}

local errors = 0

for _, file in ipairs(files) do
    local f, err = loadfile(file)
    if f then
        print("✅ " .. file .. " - Syntax OK")
    else
        print("❌ " .. file .. " - Syntax Error:")
        print("   " .. (err or "Unknown error"))
        errors = errors + 1
    end
end

if errors == 0 then
    print("\n🎉 All files have valid syntax!")
else
    print(string.format("\n💥 Found %d file(s) with syntax errors", errors))
    os.exit(1)
end