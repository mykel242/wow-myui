#!/usr/bin/env python3
import re
import sys

def fix_logging(filename):
    with open(filename, 'r') as f:
        content = f.read()
    
    # Pattern 1: if addon.DEBUG then print(string.format(...)) end
    content = re.sub(
        r'if addon\.DEBUG then print\(string\.format\(([^)]+)\)\) end',
        r'addon:Debug(\1)',
        content
    )
    
    # Pattern 2: if addon.DEBUG then print(...) end  
    content = re.sub(
        r'if addon\.DEBUG then print\(([^)]+)\) end',
        r'addon:Debug(\1)',
        content
    )
    
    # Pattern 3: Multi-line if addon.DEBUG then
    content = re.sub(
        r'if addon\.DEBUG then\s*\n\s*print\(string\.format\(([^)]+)\)\)\s*\n\s*end',
        r'addon:Debug(\1)',
        content,
        flags=re.MULTILINE
    )
    
    # Pattern 4: Multi-line if addon.DEBUG then with simple print
    content = re.sub(
        r'if addon\.DEBUG then\s*\n\s*print\(([^)]+)\)\s*\n\s*end',
        r'addon:Debug(\1)',
        content,
        flags=re.MULTILINE
    )
    
    # Pattern 5: Standalone print statements that should be Debug
    content = re.sub(
        r'^\s*print\(string\.format\("(Session|Quality|Loading|Migrating|Test session)',
        r'    addon:Debug("',
        content,
        flags=re.MULTILINE
    )
    
    # Pattern 6: Standalone print statements that should be Info
    content = re.sub(
        r'^\s*print\("(Session deleted|Sessions cleared|No sessions)',
        r'    addon:Info("',
        content,
        flags=re.MULTILINE
    )
    
    with open(filename, 'w') as f:
        f.write(content)
    
    print(f"Fixed {filename}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        fix_logging(sys.argv[1])
    else:
        print("Usage: python fix_logging.py <filename>")