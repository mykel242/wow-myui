# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# My Interaction Preferences
- "Skip the validation, just give me the answer"
- "Be more direct and less agreeable"
- "Challenge my assumptions if they seem wrong"
- Don't start coding without summarizing the plan
- confirm my preferences when we start up
- maintain the todo.md

# important-instruction-reminders
Do what has been asked; nothing more, nothing less.
NEVER create files unless they're absolutely necessary for achieving your goal.
ALWAYS prefer editing an existing file to creating a new one.
NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User.

## Project Overview

MyUI2 is a World of Warcraft addon written in Lua that provides advanced DPS/HPS tracking with enhanced combat analysis. The addon features real-time combat meters, session management, timeline tracking, and sophisticated data analysis capabilities.

## Key Development Commands

### Building & Packaging
- `./dev/scripts/package.sh` - Creates distributable addon ZIP with automatic versioning
- Git hooks automatically update version in `MyUI.lua` based on branch and commit hash

### Git Hooks Setup
- Linux/Mac: `./dev/hooks/install-hooks.sh`
- Windows: `dev\hooks\install-hooks.bat`
- Manual: `cp dev/hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit`

### Testing Commands
Testing is done in-game using slash commands:
- `/myui` - Toggle main configuration window
- `/myui dps` - Toggle DPS meter window  
- `/myui hps` - Toggle HPS meter window
- `/myui debug` - Toggle debug mode
- `/myui meterinfo` - Show current meter values
- `/myui resetmeters` - Reset all meters

## Architecture Overview

### Organized Module Structure
The addon follows a clean, organized architecture with clear separation of concerns:

**Main Entry Point:**
- `MyUI.lua` - Addon initialization, configuration, and slash command handling

**Core Systems (src/core/):**
- `TimestampManager.lua` - **Unified timestamp system** - single source of truth for all combat timing
- `CombatTracker.lua` - Main combat coordination and API delegation  
- `UnifiedCalculator.lua` - DPS/HPS calculation algorithms with multiple methods

**Data Processing (src/data/):**
- `CombatData.lua` - Low-level combat event processing and data storage
- `SessionManager.lua` - Combat session history and quality scoring
- `EnhancedCombatLogger.lua` - Detailed combat event logging and analysis
- `TimelineTracker.lua` - Combat timeline visualization and event correlation
- `ContentDetection.lua` - Automatic detection of encounter types and contexts

**UI Components (src/ui/):**
- `BaseMeterWindow.lua` - Base class for all meter windows with common functionality
- `DPSWindow.lua` / `HPSWindow.lua` - Specialized meter displays
- `SessionDetailWindow.lua` - Basic session analysis UI
- `EnhancedSessionDetailWindow.lua` - Advanced session analysis with timeline integration
- `WorkingPixelMeter.lua` - Visual meter rendering system

**Configuration (config/):**
- `CalculationConfig.lua` - Calculation method configuration interface
- `EntityBlacklist.lua` - Filtering system for irrelevant entities (totems, pets, etc.)

**Development Tools (dev/):**
- `hooks/` - Git hooks for automated versioning
- `scripts/` - Build and packaging scripts

**Assets (assets/):**
- `SCP-SB.ttf` - Custom font file
- `refresh-icon.tga` - UI icons and textures

### Key Architectural Patterns

**Timestamp Management:**
The addon uses a unified timestamp system where `TimestampManager` is the single authority for all combat timing. All modules delegate timestamp queries to this system to ensure consistency across death markers, timeline events, and calculations.

**Session Quality Scoring:**
Sessions are automatically scored based on duration, damage dealt, and activity level. This enables intelligent session retention and helps users focus on meaningful combat data.

**Modular UI System:**
All meter windows inherit from `BaseMeterWindow` providing consistent behavior for dragging, resizing, and configuration. Each specialized window adds its own display logic.

**Enhanced vs Basic Modes:**
The addon supports both lightweight basic tracking and comprehensive enhanced logging. Enhanced mode provides detailed event correlation and timeline analysis at the cost of higher memory usage.

## File Load Order

The load order is defined in `MyUI2.toc` following the organized structure:
1. `MyUI.lua` (entry point)
2. **Core Systems:** `src/core/TimestampManager.lua`, `src/core/UnifiedCalculator.lua`, `src/core/CombatTracker.lua`
3. **UI Foundation:** `src/ui/BaseMeterWindow.lua`
4. **Data Processing:** `src/data/CombatData.lua`, `src/data/ContentDetection.lua`, etc.
5. **UI Components:** `src/ui/DPSWindow.lua`, `src/ui/HPSWindow.lua`, etc.
6. **Configuration:** `config/EntityBlacklist.lua`, `config/CalculationConfig.lua`

## Development Context

**Current Status:** Phase 1-3 complete (Unified Timestamp System)
**Active Branch:** Typically feature branches, main for releases
**Version Format:** `branch-commit` (e.g., `main-c248ecd`)

The addon is in active development with a structured roadmap focusing on performance optimization, enhanced data integration, and UI improvements. See `TODO.md` for detailed development phases and priorities.

## Code Conventions

- Use addon namespace: `local addonName, addon = ...`
- Module pattern: `addon.ModuleName = {}` with local reference
- Consistent indentation and commenting for complex calculations
- Event-driven architecture using WoW's combat log system
- Saved variables: `MyUIDB` (main settings), `EntityBlacklistDB` (blacklist data)

## Common Development Tasks

When working with combat calculations, always consider the timestamp system and ensure events are properly correlated. When adding new UI components, extend `BaseMeterWindow` for consistency. When modifying data retention, respect the quality scoring system in `SessionManager`.