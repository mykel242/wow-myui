# MyUI2 - Next Steps & Development Roadmap

## ✅ COMPLETED: EventQueue Architecture Foundation
- **EventQueue system**: CombatEventQueue (2500 capacity) + LogEventQueue (2000 capacity)
- **Combat meter**: Real-time DPS/HPS tracking via queue subscriptions 
- **Zero message loss**: Both queues operating efficiently with 0% drop rate
- **Clean separation**: Combat data flows through queues, debugging through logs
- **Monitoring tools**: `/myui queuestats`, `/myui queuedebug`, `/myui queuesubscribers`
- **Foundation ready**: Architecture supports multiple specialized agent windows

---

## 🎯 IMMEDIATE PRIORITIES

### 1. Specialized Agent Windows (High Priority)
The EventQueue architecture is ready for your vision of "many small agent windows that subscribe to specific combat events."

**Example Agent Ideas:**
```lua
-- Buff/Debuff Tracker Agent
addon.CombatEventQueue:Subscribe("BUFF_EVENT", function(message)
    -- Track important buffs/debuffs
end, "BuffTracker")

-- Cooldown Monitor Agent  
addon.CombatEventQueue:Subscribe("SPELL_CAST", function(message)
    -- Track ability cooldowns
end, "CooldownMonitor")

-- Threat Meter Agent
addon.CombatEventQueue:Subscribe("THREAT_EVENT", function(message)
    -- Track threat levels
end, "ThreatMeter")

-- Performance Analysis Agent
addon.CombatEventQueue:Subscribe("DAMAGE_EVENT", function(message)
    -- Analyze DPS patterns, efficiency
end, "PerformanceAnalyzer")
```

**Implementation Steps:**
1. Choose first agent type (buff tracker, cooldown monitor, etc.)
2. Create new window file in `src/ui/`
3. Subscribe to relevant combat events
4. Build minimal UI for display
5. Test with queue monitoring tools

### 2. Expand Combat Event Types (Medium Priority)
Currently publishing: `DAMAGE_EVENT`, `HEAL_EVENT`, `COMBAT_STATE_CHANGED`

**Add Support For:**
- `BUFF_EVENT` / `DEBUFF_EVENT` (aura tracking)
- `SPELL_CAST_EVENT` (ability usage)  
- `THREAT_EVENT` (threat changes)
- `DEATH_EVENT` (player/enemy deaths)
- `INTERRUPT_EVENT` (spell interruptions)
- `DISPEL_EVENT` (dispel/purge events)

**Location:** `src/core/MySimpleCombatDetector.lua` - expand event detection logic

### 3. Queue Performance Optimization (Low Priority)
- **Message filtering**: Add filters to subscriptions to reduce processing
- **Batch processing**: Group similar events for efficiency
- **Memory management**: TTL-based automatic cleanup
- **Compression**: Store repeated data more efficiently

---

## 🏗️ ARCHITECTURAL IMPROVEMENTS

### 4. Enhanced Session Management
- **Queue integration**: Connect combat events to session storage
- **Real-time sessions**: Live session updates via queues
- **Session analysis**: Post-combat analysis through queues
- **Export integration**: Queue-based data export

### 5. Configuration System
- **Agent configuration**: Enable/disable specific agents
- **Queue tuning**: Adjustable queue sizes and TTL
- **Event filtering**: User-configurable event filtering
- **Performance tuning**: Subscription management UI

### 6. Advanced Monitoring
- **Queue health dashboard**: Visual queue monitoring window
- **Performance metrics**: Latency, throughput analysis  
- **Subscriber management**: Enable/disable subscribers dynamically
- **Debug tools**: Advanced debugging and profiling tools

---

## 🎨 UI/UX ENHANCEMENTS

### 7. Visual Improvements
- **Combat meter styling**: Improve visual design
- **Agent window themes**: Consistent styling across agents
- **Layout management**: Window positioning and docking
- **Responsive design**: Support for different screen sizes

### 8. User Experience
- **Setup wizard**: Guide users through agent configuration
- **Presets**: Pre-configured agent combinations for different roles
- **Help system**: In-game documentation and tutorials
- **Performance recommendations**: Automatic optimization suggestions

---

## 🧪 TESTING & VALIDATION

### 9. Stress Testing
- **High combat scenarios**: Raid environments, mass PvP
- **Memory leak detection**: Long-term stability testing
- **Performance benchmarking**: Queue throughput under load
- **Error handling**: Graceful degradation testing

### 10. Integration Testing
- **Multiple agents**: Test many concurrent subscribers
- **Cross-agent communication**: Agent interaction patterns
- **Session integration**: End-to-end data flow validation
- **Export functionality**: Data consistency verification

---

## 📋 CURRENT SYSTEM STATUS

**EventQueue Performance:**
- CombatEventQueue: 256/2500 (10.2% full), 2.47 msg/sec, 0% drop rate
- LogEventQueue: 566/2000 (28.3% full), 5.46 msg/sec, 0% drop rate

**Active Subscribers:**
- CombatMeterWindow_StateTracker → COMBAT_STATE_CHANGED
- CombatMeterWindow_DamageTracker → DAMAGE_EVENT  
- CombatMeterWindow_HealTracker → HEAL_EVENT
- LoggerWindowLightweight → LOG

**Available Commands:**
- `/myui queuestats` - Queue performance statistics
- `/myui queuedebug` - Detailed queue debugging
- `/myui queuesubscribers [combat|log]` - Subscriber information
- `/myui meter` - Toggle combat meter window

---

## 🚀 RECOMMENDED NEXT STEP

**Start with a simple Buff/Debuff Tracker agent:**
1. Creates a small window showing active buffs/debuffs
2. Subscribes to aura-related combat events  
3. Demonstrates the agent pattern clearly
4. Low complexity, high visual impact
5. Foundation for more complex agents

This would validate the agent architecture and provide immediate value while setting the pattern for future specialized windows.