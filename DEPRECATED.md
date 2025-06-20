# Deprecated Files and Architecture Changes

This document lists all deprecated files from the prototype phase and their modern replacements.

## Architecture Migration Summary

The addon was refactored from a complex multi-module prototype to a simplified, performant system with clear separation of concerns.

### Key Changes:
- **Unified Combat Detection**: Single `MySimpleCombatDetector.lua` replaces multiple combat systems
- **Message Queue Architecture**: Decoupled real-time meter from session storage 
- **Simplified UI**: Direct window creation instead of inheritance hierarchy
- **Performance Focus**: Ring buffers, table pooling, and throttled updates

---

## Deprecated Files

### Combat Detection & Logging
| **Deprecated File** | **Replacement** | **Reason** |
|---------------------|-----------------|------------|
| `src/data/EnhancedCombatLogger.lua` | `src/core/MySimpleCombatDetector.lua` | Overly complex; simplified approach with message queue |
| `src/data/SessionManager.lua` | `src/data/StorageManager.lua` + `MySimpleCombatDetector.lua` | Split session management from combat detection |
| `src/data/TimelineTracker.lua` | Simplified timeline in `MySimpleCombatDetector.lua` | Reduced complexity while keeping essential timeline features |
| `src/data/ContentDetection.lua` | Built into `MySimpleCombatDetector.lua` | Simplified zone/instance detection |

### Calculation Systems  
| **Deprecated File** | **Replacement** | **Reason** |
|---------------------|-----------------|------------|
| `src/core/UnifiedCalculator.lua` | `src/core/MyCombatMeterCalculator.lua` | Modular approach with message queue integration |
| `config/CalculationConfig.lua` | Built into `MyCombatMeterCalculator.lua` | Configuration simplified and embedded |

### UI Systems
| **Deprecated File** | **Replacement** | **Reason** |
|---------------------|-----------------|------------|
| `src/ui/BaseMeterWindow.lua` | Direct creation in `MyCombatMeterWindow.lua` | Inheritance overhead removed |
| `src/ui/DPSWindow.lua` | `src/core/MyCombatMeterWindow.lua` | Unified DPS/HPS meter |
| `src/ui/HPSWindow.lua` | `src/core/MyCombatMeterWindow.lua` | Unified DPS/HPS meter |
| `src/ui/WorkingPixelMeter.lua` | Built into `MyCombatMeterWindow.lua` | Integrated meter display |
| `src/ui/CombatLogViewer.lua` | `src/core/MyLoggerWindow_Lightweight.lua` | Performance-focused rewrite |
| `src/ui/SettingsWindow.lua` | Slash commands in `SlashCommands.lua` | Simplified configuration |
| `src/ui/SessionDetailWindow.lua` | `src/ui/SessionBrowser.lua` | Consolidated session viewing |
| `src/ui/EnhancedSessionDetailWindow.lua` | `src/ui/SessionBrowser.lua` | Simplified session details |

### Configuration & Support
| **Deprecated File** | **Replacement** | **Reason** |
|---------------------|-----------------|------------|
| `config/EntityBlacklist.lua` | Built into `MySimpleCombatDetector.lua` | Simplified entity filtering |
| `src/core/MyLoggerWindow.lua` | `src/core/MyLoggerWindow_Lightweight.lua` | Performance rewrite with ring buffer |

---

## Current Active Architecture

### Core System (9 files)
```
src/core/MyMessageQueue.lua          # Decoupled communication
src/core/MyLogger.lua                # Unified logging  
src/core/MyLoggerWindow_Lightweight.lua  # Performant log viewer
src/core/MyCombatMeterCalculator.lua # DPS/HPS calculations
src/core/MyCombatMeterScaler.lua     # Dynamic scaling
src/core/MyCombatMeterWindow.lua     # Real-time meter display
src/core/MyTimestampManager.lua      # Unified timing
src/core/MySimpleCombatDetector.lua  # Combat detection & events
src/utils/VirtualScrollMixin.lua     # UI scrolling support
```

### Data Management (3 files)
```
src/data/MetadataCollector.lua       # Zone/encounter context
src/data/GUIDResolver.lua            # Name resolution & caching  
src/data/StorageManager.lua          # Session storage & compression
```

### UI Components (2 files)
```
src/ui/SessionBrowser.lua            # Session browsing & analysis
src/ui/ExportDialog.lua              # Data export functionality
```

### Main Entry (2 files)
```
MyUI.lua                             # Addon initialization
src/commands/SlashCommands.lua       # Command interface
```

**Total: 16 active files** (down from ~30 in prototype)

---

## Data Flow Architecture

### Old (Prototype) - Complex Multi-System
```
Combat Log → Multiple Listeners → Complex Processing → Multiple Storage → Multiple UI
```

### New (Current) - Unified Single-Source
```
Combat Log → MySimpleCombatDetector → [Message Queue + Storage] → [Real-time Meter + Session Browser]
```

### Benefits of New Architecture:
- ✅ **Single Source of Truth**: One combat log listener
- ✅ **Decoupled Components**: Message queue prevents tight coupling  
- ✅ **Performance Focused**: Ring buffers, throttling, table pooling
- ✅ **Simplified Maintenance**: Fewer files, clearer responsibilities
- ✅ **Consistent Data**: Same events go to both storage and real-time display

---

## Migration Notes

- All deprecated files are marked with `## DEPRECATED:` in the TOC file
- Files contain deprecation headers with replacement information
- Key parsing logic was preserved and improved (especially combat log parsing)
- Performance characteristics are significantly better in the new system
- Feature parity maintained while reducing complexity

**Do not reference deprecated files for new development.** Use the active architecture documented above.