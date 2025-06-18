# MyUI2 Modularization TODO

## Overview
Disable existing session management, DPS/HPS meters, and complex UI features to create a clean foundation for the new combat logging system. Simplify the main window to act as a launcher for new tools.

## Phase 1: Disable Existing Features

### 1. Disable Session Management & History
**Files to modify:**
- `MyUI.lua` - Remove session history panel, charts, and related UI
- `src/data/SessionManager.lua` - Disable initialization and data collection
- `src/data/EnhancedCombatLogger.lua` - Disable initialization

**Actions:**
- Comment out session-related initialization code
- Remove session history display from main window
- Remove performance charts
- Keep data structures intact for future re-enable

### 2. Disable DPS/HPS Meters
**Files to modify:**
- `MyUI.lua` - Remove DPS/HPS window toggles and initialization
- `src/ui/DPSWindow.lua` - Disable initialization
- `src/ui/HPSWindow.lua` - Disable initialization
- `src/ui/BaseMeterWindow.lua` - Keep for future use
- move the code for slash commands into a separate file

**Actions:**
- Comment out meter window initialization
- Remove meter buttons from main UI
- Remove meter update timers
- Preserve meter classes for future re-enable

### 3. Remove Calculation Method Dropdown
**Files to modify:**
- `MyUI.lua` - Remove calculation dropdown from control panel

**Actions:**
- Remove dropdown UI components
- Keep calculation logic intact in backend
- Remove dropdown update functions

### 4. Simplify Slash Commands
**Current commands to disable:**
- `/myui dps`, `/myui hps` - meter toggles
- `/myui dpsmax`, `/myui hpsmax`, `/myui dpsreset`, `/myui hpsreset` - meter scaling
- `/myui resetmeters`, `/myui meterinfo` - meter management
- `/myui sessions`, `/myui list`, `/myui mark`, `/myui ids` - session management
- `/myui scaling`, `/myui enhancedlog`, `/myui enhancedconfig` - advanced features
- `/myui clear`, `/myui resetcombat`, `/myui memory` - data management
- `/myui calc` - calculation methods

**Keep only:**
- `/myui` - toggle main window
- `/myui debug` - debug mode toggle
- `/myui show/hide/toggle` - basic window management

### 5. Simplify Main Window
**New simplified layout:**
- **Header**: Title and close button
- **Status Panel**: Simple addon status (debug on/off, version info)
- **Tool Launcher Panel**: Buttons for new tools as they're developed
- **Footer**: Minimal info (version, build date)
- Use a default warcraft ui style for this window including normal size and position, close button etc. use a default strata so that the elements inherit the window's strata.

**Remove:**
- Current combat display panel
- Session history table and scrolling
- Performance charts
- Complex control panel with multiple buttons
- Calculation method dropdown

## Phase 2: Create New Tool Foundation

### 1. Combat Log Viewer Button
**Add to simplified main window:**
- "Combat Logger" button - launches new combat logging tool
- Initially shows placeholder/coming soon message

### 2. Future Tool Placeholder Buttons
**Prepare launcher spots for:**
- "Raw Data Viewer" button
- "Export Tools" button
- "Session Browser" button (when re-enabled with new data layer)

### 3. New Slash Commands
**Add minimal new commands:**
- `/myui logger` - open combat log viewer
- `/myui rawdata` - open raw data viewer (when implemented)

## Phase 3: Preserve for Re-enable

### What to Keep Intact
**Core Systems (preserve but disable initialization):**
- `TimestampManager` - keep fully functional
- `UnifiedCalculator` - keep calculation logic
- `CombatData` - keep data structures
- `CombatTracker` - keep API facade

**UI Systems (preserve classes but disable):**
- `BaseMeterWindow` - keep for future meters
- `DPSWindow`, `HPSWindow` - disable but preserve
- `SessionDetailWindow`, `EnhancedSessionDetailWindow` - disable but preserve

**Data Systems (preserve but disable):**
- `SessionManager` - keep structures, disable collection
- `EnhancedCombatLogger` - keep for future integration
- `ContentDetection` - keep logic intact

## Implementation Strategy

### Step 1: Comment Out Initialization
- Wrap existing module initializations in `if false then` blocks
- Preserve all existing code for easy re-enable
- Add clear comments marking disabled sections

### Step 2: Remove UI Components
- Remove complex panels from main window creation
- Replace with simple launcher interface
- Keep UI creation functions intact but not called

### Step 3: Disable Slash Commands
- Comment out complex command handlers
- Keep command parsing structure for easy re-add
- Add placeholder responses for disabled commands

### Step 4: Add New Foundation
- Create simple launcher buttons
- Add new slash commands for future tools
- Prepare UI hooks for new combat logging system

## Benefits

### Clean Development Environment
- No interference from existing complex systems
- Clear separation between old and new functionality
- Easier debugging during development

### Easier Re-integration
- All existing code preserved and commented
- Clear path to re-enable features with new data layer
- Maintains all existing configuration and saved data structures

### User Experience
- Simpler, focused interface during development
- Clear indication of what's being rebuilt
- Gradual feature rollout as new system develops

## Result
A streamlined addon that:
- Shows simple launcher window with tool buttons
- Keeps essential debug and window management commands
- Preserves all existing code for future re-enable
- Provides clean foundation for new combat logging system
- Maintains user's saved settings and data

---

## Core Abilities to Implement

### 1. Combat Detection and Raw Logging System
**Goal**: Create a single source of truth for combat activity analysis

**Features**:
- Detect combat and create raw log of events
- Store metadata (player, zone, participants, encounter, quality score)
- Maintain sequence and relative timing of events
- Non-destructive logging preserving original event data
- Forever storage with intelligent memory management
- Quality-based retention and cleanup

### 2. Combat Log Viewer UI
**Goal**: Historical session browser and raw data viewer

**Features**:
- Scrollable text area showing real-time logging activity
- Session list with metadata (date, duration, location, quality)
- Load and view raw data for any historical session
- Export data to external tools (JSON, CSV, etc.)
- Delete individual sessions
- Search and filter functionality

**UI Components**:
- Main window with session browser
- Live logging panel with real-time event stream
- Raw data viewer for detailed event inspection
- Export dialog, we want to be able to look at the data in external tools
