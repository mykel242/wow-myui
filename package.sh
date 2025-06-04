#!/bin/bash
# package-addon.sh
# Script to package MyUI addon for distribution

set -e  # Exit on any error

# Configuration
ADDON_NAME="MyUI2"
VERSION_FILE="MyUI.lua"
DIST_DIR="dist"
TEMP_DIR="${DIST_DIR}/temp"
ADDON_DIR="${TEMP_DIR}/${ADDON_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to extract version from MyUI.lua
get_version() {
    if [ -f "$VERSION_FILE" ]; then
        # Extract version from the addon.VERSION line
        local version=$(grep '^addon\.VERSION = ' "$VERSION_FILE" | sed 's/.*"\(.*\)".*/\1/')
        if [ -n "$version" ]; then
            echo "$version"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Function to create clean addon directory
create_addon_structure() {
    print_status "Creating addon directory structure..."
    
    # Create directories
    mkdir -p "$ADDON_DIR"
    
    # Core addon files (must be included)
    local core_files=(
        "MyUI2.toc"
        "MyUI.lua"
        "CombatTracker.lua"
        "BaseMeterWindow.lua"
        "DPSWindow.lua"
        "HPSWindow.lua"
        "WorkingPixelMeter.lua"
    )
    
    # Copy core files
    for file in "${core_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$ADDON_DIR/"
            print_status "Copied: $file"
        else
            print_error "Missing required file: $file"
            exit 1
        fi
    done
    
    # Optional files (copy if they exist)
    local optional_files=(
        "README.md"
        "CHANGELOG.md"
        "LICENSE"
    )
    
    for file in "${optional_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$ADDON_DIR/"
            print_status "Copied optional file: $file"
        fi
    done
    
    # Copy asset directories if they exist
    if [ -d "assets" ]; then
        cp -r assets "$ADDON_DIR/"
        print_status "Copied assets directory"
    fi
    
    # Copy any texture/image files in root directory
    find . -maxdepth 1 \( -name "*.tga" -o -name "*.blp" -o -name "*.png" -o -name "*.jpg" -o -name "*.ttf" \) -exec cp {} "$ADDON_DIR/" \;
    
    print_success "Addon structure created"
}

# Function to validate TOC file
validate_toc() {
    local toc_file="$ADDON_DIR/MyUI2.toc"
    
    print_status "Validating TOC file..."
    
    if [ ! -f "$toc_file" ]; then
        print_error "TOC file not found: $toc_file"
        exit 1
    fi
    
    # Check for required TOC fields
    local required_fields=("Interface" "Title" "Version")
    
    for field in "${required_fields[@]}"; do
        if ! grep -q "^## ${field}:" "$toc_file"; then
            print_warning "TOC file missing recommended field: $field"
        fi
    done
    
    # Validate that all Lua files listed in TOC exist
    local lua_files=$(grep -v '^#' "$toc_file" | grep '\.lua$' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    
    while IFS= read -r lua_file; do
        if [ -n "$lua_file" ] && [ ! -f "$ADDON_DIR/$lua_file" ]; then
            print_error "TOC references missing file: $lua_file"
            exit 1
        fi
    done <<< "$lua_files"
    
    print_success "TOC file validation passed"
}

# Function to create installation instructions
create_readme() {
    print_status "Creating installation README..."
    
    local readme_file="$ADDON_DIR/INSTALL.txt"
    local version=$(get_version)
    
    cat > "$readme_file" << EOF
MyUI2 - World of Warcraft Addon
Version: $version
===============================

INSTALLATION INSTRUCTIONS:
==========================

1. Close World of Warcraft completely

2. Extract this entire folder to your WoW AddOns directory:
   - Retail: World of Warcraft\_retail_\Interface\AddOns\
   - Classic: World of Warcraft\_classic_\Interface\AddOns\
   
   The final path should look like:
   .../Interface/AddOns/MyUI2/MyUI2.toc

3. Start World of Warcraft

4. At the character selection screen, click "AddOns" and ensure 
   "My UI Too." is checked and enabled

5. Log into the game and type /myui to open the main window

USAGE:
======
- /myui          - Toggle main configuration window
- /myui dps      - Toggle DPS meter window  
- /myui hps      - Toggle HPS meter window
- /myui debug    - Toggle debug mode

FEATURES:
=========
- Real-time DPS/HPS tracking with pixel meters
- Rolling average calculations
- Combat statistics and peak tracking
- Draggable, resizable windows
- Auto-scaling meter displays

SUPPORT:
========
This is a test version. Report issues with:
- Your WoW version (Retail/Classic)
- Detailed description of the problem
- Any error messages from the game

EOF

    print_success "Installation README created"
}

# Function to create zip package
create_zip_package() {
    local version=$(get_version)
    local zip_name="${ADDON_NAME}-${version}.zip"
    local zip_path="${DIST_DIR}/${zip_name}"
    
    print_status "Creating zip package: $zip_name"
    
    # Change to temp directory to create zip with correct structure
    cd "$TEMP_DIR"
    
    # Create zip file
    if command -v zip >/dev/null 2>&1; then
        zip -r "../$zip_name" "$ADDON_NAME/" -x "*.DS_Store" "*Thumbs.db"
    else
        print_error "zip command not found. Please install zip utility."
        exit 1
    fi
    
    cd - > /dev/null
    
    # Verify zip was created
    if [ -f "$zip_path" ]; then
        local zip_size=$(du -h "$zip_path" | cut -f1)
        print_success "Package created: $zip_path ($zip_size)"
    else
        print_error "Failed to create zip package"
        exit 1
    fi
    
    # Create latest symlink/copy
    local latest_path="${DIST_DIR}/${ADDON_NAME}-latest.zip"
    cp "$zip_path" "$latest_path"
    print_status "Created latest version: $latest_path"
    
    return 0
}

# Function to show package contents
show_package_info() {
    local version=$(get_version)
    local zip_name="${ADDON_NAME}-${version}.zip"
    local zip_path="${DIST_DIR}/${zip_name}"
    
    print_status "Package Information:"
    echo "  Name: $zip_name"
    echo "  Version: $version"
    echo "  Size: $(du -h "$zip_path" | cut -f1)"
    echo "  Location: $zip_path"
    echo ""
    
    print_status "Package Contents:"
    if command -v unzip >/dev/null 2>&1; then
        unzip -l "$zip_path" | grep -v "Archive:" | grep -v "^-" | grep -v "^$" | head -20
        local total_files=$(unzip -l "$zip_path" | grep "files" | awk '{print $1}')
        echo "  ... ($total_files total files)"
    else
        echo "  (Install unzip to see detailed contents)"
    fi
}

# Function to cleanup
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_status "Cleaned up temporary files"
    fi
}

# Main execution
main() {
    echo "================================================="
    echo "MyUI2 Addon Packaging Script"
    echo "================================================="
    
    # Check if we're in the right directory
    if [ ! -f "MyUI2.toc" ]; then
        print_error "MyUI2.toc not found. Run this script from the addon root directory."
        exit 1
    fi
    
    # Create dist directory
    mkdir -p "$DIST_DIR"
    
    # Clean up any previous temp directory
    cleanup
    
    # Create addon structure
    create_addon_structure
    
    # Validate TOC file
    validate_toc
    
    # Create installation instructions
    create_readme
    
    # Create zip package
    create_zip_package
    
    # Show package information
    show_package_info
    
    # Cleanup
    cleanup
    
    echo ""
    print_success "Addon packaging completed successfully!"
    echo ""
    echo "Share this file with your test users:"
    echo "  $(pwd)/${DIST_DIR}/${ADDON_NAME}-$(get_version).zip"
    echo ""
    echo "Or use the latest version link:"
    echo "  $(pwd)/${DIST_DIR}/${ADDON_NAME}-latest.zip"
}

# Run main function
main "$@"