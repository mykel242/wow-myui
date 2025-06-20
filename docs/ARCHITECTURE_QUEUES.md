# Message Queue Architecture

## Overview

MyUI2 uses a unified message queue pattern for decoupled communication between data producers and consumers. This pattern is used consistently across logging, combat events, and metrics.

## Architecture Diagram

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   MyLogger      │────▶│  Log Message     │◀────│ MyLoggerWindow  │
│                 │     │     Queue        │     │  (pulls every   │
│                 │     │                  │     │   0.5 seconds)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘

┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Combat Detector │────▶│  Combat Event    │◀────│  DPS/HPS Meter  │
│                 │     │     Queue        │     │ (subscribes for │
│                 │     │                  │     │  real-time)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                ▲                         ▲
                                │                         │
                                └─────────────────────────┘
                                        │
                                ┌───────────────┐
                                │Session Detail │
                                │   Viewer      │
                                │ (pulls full   │
                                │  history)     │
                                └───────────────┘
```

## Queue Types

### 1. Log Message Queue
- **Size**: 200 messages
- **TTL**: 5 minutes
- **Purpose**: Debug/info logging
- **Producers**: MyLogger
- **Consumers**: MyLoggerWindow

### 2. Combat Event Queue
- **Size**: 10,000 events
- **TTL**: 10 minutes
- **Purpose**: Raw combat log events
- **Producers**: MySimpleCombatDetector
- **Consumers**: DPS/HPS calculators, Session storage

### 3. Metrics Queue
- **Size**: 300 entries (5 min @ 1/sec)
- **TTL**: 5 minutes
- **Purpose**: Calculated DPS/HPS values
- **Producers**: DPS/HPS calculators
- **Consumers**: Meter displays, Session analyzer

## Usage Examples

### Producer Pattern (MyLogger)

```lua
function MyLogger:Initialize()
    -- Create or get the log queue
    self.queue = addon.LogMessageQueue or addon.MyQueueFactory:CreateLogQueue()
    addon.LogMessageQueue = self.queue
end

function MyLogger:Log(level, message, ...)
    -- Format message
    local formatted = self:FormatMessage(level, message, ...)
    
    -- Push to queue instead of direct coupling
    self.queue:Push("LOG", {
        level = level,
        levelName = self.LEVEL_NAMES[level],
        message = formatted,
        raw = message,
        args = {...}
    })
end
```

### Consumer Pattern (MyLoggerWindow)

```lua
function MyLoggerWindow:Initialize()
    -- Get the log queue
    self.queue = addon.LogMessageQueue
    
    -- Option 1: Pull-based (for throttled updates)
    self:ScheduleRepeatingTimer(function()
        if self:IsVisible() then
            self:RefreshFromQueue()
        end
    end, 0.5)
    
    -- Option 2: Push-based subscription (for real-time)
    self.queue:Subscribe("LoggerWindow", function(message)
        if self:IsVisible() then
            self:AddMessage(message.data.levelName, message.data.message)
        end
    end)
end

function MyLoggerWindow:RefreshFromQueue()
    -- Pull recent messages
    local messages = self.queue:Pull({
        count = 30,
        since = GetTime() - 60  -- Last minute
    })
    
    -- Update display
    self:ClearDisplay()
    for _, msg in ipairs(messages) do
        self:AddMessage(msg.data.levelName, msg.data.message)
    end
end
```

### Combat Event Pattern

```lua
-- Producer (Combat Detector)
function MySimpleCombatDetector:COMBAT_LOG_EVENT_UNFILTERED()
    local timestamp, event, _, sourceGUID, sourceName, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
    
    -- Push to combat event queue
    self.combatQueue:Push("COMBAT_EVENT", {
        timestamp = timestamp,
        event = event,
        sourceGUID = sourceGUID,
        sourceName = sourceName,
        destGUID = destGUID,
        destName = destName,
        -- ... other combat data
    })
end

-- Consumer (DPS Meter)
function MyDPSMeter:Initialize()
    -- Subscribe to combat events
    addon.CombatEventQueue:Subscribe("DPSMeter", function(message)
        local data = message.data
        if data.event == "SPELL_DAMAGE" or data.event == "SWING_DAMAGE" then
            self:ProcessDamageEvent(data)
        end
    end, 
    -- Optional filter function
    function(message)
        return message.data.sourceGUID == UnitGUID("player")
    end)
end

-- Consumer (Session Storage)
function MySessionStorage:OnCombatEnd()
    -- Pull all events from this combat
    local combatEvents = addon.CombatEventQueue:Pull({
        since = self.combatStartTime,
        type = "COMBAT_EVENT"
    })
    
    -- Store for later analysis
    self:StoreSession(combatEvents)
end
```

## Benefits

1. **Decoupling**: Producers don't know about consumers
2. **Performance**: Consumers control their update rate
3. **Flexibility**: Multiple consumers can process same data differently
4. **Memory Bounded**: Fixed-size circular buffers
5. **Time-based**: Natural expiration of old data
6. **Filtering**: Consumers can filter what they care about

## Queue Management

```lua
-- Get queue statistics
local stats = queue:GetStats()
print(string.format("Queue %s: %d/%d messages (%.1f%% full)", 
    stats.name, stats.size, stats.maxSize, stats.utilization))

-- Clean up expired messages
local cleaned = queue:Cleanup()
print(string.format("Cleaned %d expired messages", cleaned))

-- Clear queue
queue:Clear()
```