# ADR-0004: Signal Bus Pattern

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — GDScript signals are a pre-4.0 language feature with no breaking changes. Signal conventions are a project-level pattern with zero engine API dependency. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None — GDScript `signal` keyword and `connect()`/`emit()` are pre-4.0 stable |
| **Verification Required** | None — signal conventions are enforced by code review, not engine behavior |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — assumes all 12 systems are globally accessible Autoloads. ADR-0003 (Object Pooling) — Audio/VFX pool exhaustion emit signals. |
| **Enables** | All system implementation stories — every `connect()` call in the codebase follows this ADR's conventions |
| **Blocks** | No specific stories — but incorrect signal usage discovered at code review will be traced back to this ADR's conventions |
| **Ordering Note** | Must be Accepted before any system implementation begins, as every system's `_ready()` signal subscriptions must follow these conventions |

## Context

### Problem Statement

ADR-0001 established that all 12 MVP systems communicate via signals (for events) and read-only properties (for queries). But it left four critical conventions undefined: (1) signal naming — what tense and format guarantees a signal is recognizable as a signal across 12 different Autoload scripts? (2) payload format — positional args vs. typed dictionaries vs. custom Resource objects? (3) connection lifecycle — where does `connect()` happen, where does `disconnect()` happen, and is runtime connect/disconnect permitted? (4) EventBus — should cross-cutting events that 4+ systems need (e.g., `game_paused`, `screen_shake`) funnel through a central EventBus Autoload, or should every system connect directly to every emitter?

Without these conventions, each of the 12 MVP systems will develop its own signal style — inconsistent payloads, mismatched tenses, connections scattered across `_ready()`, `_process()`, and inline callbacks. At 12 systems with an average of 4-6 signal connections each, that's 50-70 `connect()` calls. Inconsistency at that scale produces bugs that are hard to trace: "why didn't VFX react to `player_hit`?" could mean wrong signal name, wrong payload type, wrong connection timing, or wrong disconnect.

### Constraints

- Godot 4.6 + GDScript
- 12 Autoload systems (ADR-0001) — each connects to 3-8 signals from other systems
- Solo developer — conventions must be simple enough to enforce by code review, not by tooling
- 60 fps target — signal emission and connection overhead must be negligible
- No third-party event bus libraries — pattern must use only built-in GDScript `signal`

### Requirements

- Every `signal` declaration in the codebase follows the same naming convention
- Every `connect()` call follows the same lifecycle rules
- Signal payloads are consistent — a reader can guess the payload format from the signal name alone
- The pattern works for 1:1 (one emitter, one listener), 1:N (one emitter, many listeners), and N:M (many emitters, many listeners) communication topologies
- The pattern is idiomatic Godot — recognizable to any Godot developer

## Decision

**Direct Autoload-to-Autoload signal connections with formalized conventions. No separate EventBus Autoload for MVP.**

ADR-0001 already established the direct-connection pattern: `GSM.state_changed.connect(_on_state_changed)`. This ADR formalizes the conventions around that pattern. A dedicated EventBus Autoload is considered but deferred — the 12-system topology does not justify the extra indirection for MVP.

### Signal Naming Convention

All signals use `snake_case` **past tense** or **present-state** form:

| Event Type | Tense | Example |
|-----------|-------|---------|
| State transitions | Past tense | `state_changed`, `player_died`, `wave_started` |
| Actions performed | Past tense | `damage_dealt`, `transformation_started` |
| Threshold crossed | Past tense | `meter_full`, `hp_critical` |
| Continuous value change | Present noun | `meter_changed` (not `meter_changing`) |

**Rationale**: Past tense signals describe something that *happened* — the emitter is notifying listeners of a completed event. This distinguishes signals (events) from methods (commands). `damage_dealt` is something that occurred; `deal_damage()` is something you request.

### Signal Payload Standard

| Payload Size | Format | Example |
|-------------|--------|---------|
| 0 params | Bare signal | `signal player_died()` |
| 1-3 params | Positional args with type hints | `signal damage_dealt(target: Node2D, amount: float)` |
| 4+ params | Typed Dictionary | `signal combat_event(data: Dictionary)` — documented with required keys |

**Payload naming rules:**
- Positional params use descriptive snake_case names: `old_state`, `new_state`, not `from`, `to`
- Dictionary payloads document required keys in a comment block above the signal declaration
- Never use untyped `Variant` arrays as payload — `signal something_happened(args: Array)` is forbidden

**Dictionary payload documentation pattern:**
```gdscript
## Emitted when a combat event resolves.
## data keys: "source" (Node2D), "target" (Node2D), "amount" (float), "is_crit" (bool), "damage_type" (String)
signal combat_resolved(data: Dictionary)
```

### Connection Lifecycle Rules

1. **All `connect()` calls happen in `_ready()`** — no runtime connect/disconnect during gameplay. This guarantees the connection graph is static and auditable in one place.

2. **Disconnection is the exception, not the rule** — pooled objects (ADR-0003) that are recycled do NOT disconnect/reconnect signals. Instead, the pool manager calls a `_reset()` method that temporarily ignores signals via a boolean flag:
   ```gdscript
   func _on_player_hit(damage: float) -> void:
       if _is_idle:  # pooled node is inactive — ignore signal
           return
       _play_hit_flash(damage)
   ```

3. **Signal subscription documentation** — each system's `_ready()` opens with a comment block listing all signals it subscribes to:
   ```gdscript
   func _ready() -> void:
       # Signal subscriptions:
       #   GSM.state_changed      → _on_state_changed
       #   PlayerSystem.player_hit → _on_player_hit
       #   WaveSystem.wave_started → _on_wave_started
       GSM.state_changed.connect(_on_state_changed)
       PlayerSystem.player_hit.connect(_on_player_hit)
       WaveSystem.wave_started.connect(_on_wave_started)
   ```

4. **No anonymous callbacks** — all `connect()` calls reference named methods, never lambdas:
   ```gdscript
   # ✅ ALLOWED
   GSM.state_changed.connect(_on_state_changed)
   
   # ❌ FORBIDDEN
   GSM.state_changed.connect(func(from, to): print("%s -> %s" % [from, to]))
   ```

### EventBus: Deferred for MVP

A dedicated EventBus Autoload (`SignalBus.gd`) is a common Godot pattern where systems emit to and subscribe from a central bus, decoupling emitters from receivers:

```gdscript
# With EventBus (not used in MVP):
SignalBus.player_hit.emit(damage)       # Emitter: PlayerSystem
SignalBus.player_hit.connect(_on_hit)   # Listener: VFX, Audio, HUD
```

**Why EventBus is deferred:**
- ADR-0001's direct-connection pattern (`PlayerSystem.player_hit.connect()`) is already established and approved. Introducing EventBus now would create an inconsistency.
- At 12 systems, the direct-connection graph is fully auditable. The longest connection chain is: Foundation signal → Core listener. There is no N:M topology in MVP that direct connections handle poorly.
- EventBus adds an Autoload (#13) solely for signal routing — an extra node in every signal path with no MVP benefit.
- The decoupling benefit becomes real at ~20+ systems or when systems are dynamically added/removed. MVP has exactly 12 fixed systems.

**Trigger for reconsideration** (Vertical Slice or later):
- A single event needs 5+ listeners across unrelated systems
- A system needs to emit events without knowing which other systems exist (plugin/mod architecture)
- Dynamic system loading is introduced (e.g., per-level systems, DLC systems)

### Architecture Diagram

```
Direct connection pattern (MVP — this ADR):

  PlayerSystem                VFX
  ┌──────────┐    signal     ┌──────────┐
  │ player_  │──────────────→│ _on_     │
  │ hit(dmg) │   .connect()  │ player_  │
  │          │               │ hit(dmg) │
  │          │──────────────→│          │
  │ damage_  │   .connect()  │ _on_     │
  │ dealt(…) │               │ damage_  │
  └──────────┘               │ dealt(…) │
        │                    └──────────┘
        │     signal              ↑
        ├─────────────────────────┤
        │                    Audio (also connected)
        │                    ┌──────────┐
        └────────────────────→ _on_     │
                             │ player_  │
                             │ hit(dmg) │
                             └──────────┘

Deferred (Vertical Slice+):
  EventBus / SignalBus Autoload — not used in MVP.
  Reconsider when: 5+ listeners per event, or dynamic systems.
```

### Key Interfaces

No new API contracts. This ADR formalizes conventions around the existing `signal` + `connect()` + `emit()` pattern from ADR-0001:

**Signal declaration template:**
```gdscript
## [One-line description of what happened.]
## [If Dictionary payload:] data keys: "key1" (Type), "key2" (Type)
signal [snake_case_past_tense]([typed_params])
```

**Connection template:**
```gdscript
func _ready() -> void:
    # Signal subscriptions:
    #   [Emitter].[signal_name] → [_callback_method]
    Emitter.signal_name.connect(_callback_method)
```

**Emission template:**
```gdscript
signal_name.emit(param1, param2)
```

### Timeline

- **MVP**: Direct connections with formalized conventions (this ADR)
- **Vertical Slice**: Re-evaluate EventBus if cross-cutting event count exceeds threshold
- **If EventBus is adopted later**: It replaces direct connections for cross-cutting events only — system-internal signals remain direct. Migration is mechanical: move `signal` declarations to EventBus, update `connect()` and `emit()` calls.

## Alternatives Considered

### Alternative 1: Central EventBus Autoload for ALL signals

- **Description**: A `SignalBus` Autoload owns every cross-system signal. Systems never connect directly to each other — all signals route through SignalBus.
- **Pros**: Maximum decoupling — VFX never references PlayerSystem by name, only SignalBus. Easy to add new listeners without touching the emitter. Central place to audit all events.
- **Cons**: Contradicts ADR-0001's direct-connection pattern (approved in the same session). Adds an Autoload solely for routing. Every signal emission goes through an extra node: `SignalBus.player_hit.emit()` vs `player_hit.emit()`. Debugging requires tracing through SignalBus to find the true emitter.
- **Rejection Reason**: Inconsistent with ADR-0001. Over-engineered for 12 systems. The decoupling value is theoretical at MVP scale — every system already knows which systems produce its needed signals from the GDD dependency tables.

### Alternative 2: String-based signal names (loose coupling)

- **Description**: Use string names instead of typed signal references: `EventBus.emit("player_hit", data)` / `EventBus.on("player_hit", callback)`.
- **Pros**: Zero compile-time coupling between systems. Easy to add ad-hoc events without declaring signals.
- **Cons**: No type checking on payload — runtime errors when `emit("player_hit", 50)` is consumed as `func(data: Dictionary)`. No autocomplete. String typos are silent failures. Not idiomatic Godot — Godot's `signal` keyword exists specifically to avoid string-based event systems.
- **Rejection Reason**: Loses all compile-time safety GDScript signals provide. The entire point of Godot's signal system over raw string events is type checking and autocomplete.

### Alternative 3: Signal connection via exported Array[NodePath] (Godot Editor wiring)

- **Description**: Declare signals in each system, then wire connections visually in the Godot editor by assigning node paths.
- **Pros**: Visual editor-driven workflow — no code for signal wiring. Designer-friendly.
- **Cons**: Autoload singletons have no node path in the editor — they're globally accessible scripts, not nodes in a scene tree. Editor-based signal wiring only works for scene-instanced nodes, not Autoloads. Would require placing all 12 systems as nodes in a scene, defeating the Autoload pattern from ADR-0001.
- **Rejection Reason**: Incompatible with ADR-0001's Autoload architecture. Autoload signals are connected in code by design.

## Consequences

### Positive

- **Auditable signal graph**: Every `connect()` call is in a `_ready()` behind a comment block. A grep for `connect(` produces the complete inter-system signal map.
- **Consistent payload mental model**: 1-3 positional args = simple. 4+ = typed Dictionary. No guessing whether `player_hit` expects `(float)` or `(Dictionary)`.
- **No silent signal loss**: No runtime connect/disconnect means no "I forgot to reconnect" bugs. Pooled nodes use a boolean guard, not connect/disconnect.
- **Deferred complexity**: EventBus is a documented future option with a clear trigger threshold — no premature architecture.
- **Idiomatic**: The conventions reinforce GDScript best practices (typed signals, named callbacks, documented payloads).

### Negative

- **Direct coupling**: Every listener system references the emitter by name (`PlayerSystem.player_hit`). If an emitter is renamed, all listeners break at compile time. **Accepted cost**: Renaming an Autoload is rare (names are locked by GDDs). Compile-time breaks are visible and easy to fix.
- **No EventBus for MVP**: Cross-cutting events (e.g., `game_paused`, `screen_shake`) that may eventually need 5+ listeners are emitted directly from their source system, meaning that system must know about all its listeners — or listeners connect to multiple emitters. **Accepted cost**: MVP has at most 3-4 listeners per event. Each listener explicitly connects in `_ready()`.

### Risks

- **Risk: Signal connection explosion in larger systems**: VFX connects to GSM (1 signal), PlayerSystem (2 signals), TransformationSystem (4 signals), WaveSystem (4 signals) = 11 connections in `_ready()`. This is manageable — each connection is one line + one comment line. **Mitigation**: The comment block keeps it organized. If a system exceeds ~15 connections, it likely has too many responsibilities — consider splitting.
- **Risk: EventBus deferred decision is forgotten**: The team reaches Vertical Slice and never re-evaluates the EventBus trigger. **Mitigation**: This ADR is referenced in the Vertical Slice milestone checklist. The trigger threshold (5+ listeners, or dynamic systems) is concrete and testable.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| vfx-system.md | Rule 1: Signal-driven pure response system — subscribes to GSM, Player, Transformation, Wave signals | Formalizes the `connect()` pattern VFX uses for its 11 signal subscriptions |
| audio-system.md | Rule 1: Signal-driven pure response system — subscribes to GSM, Player, Transformation, Wave, Absorption signals | Formalizes the `connect()` pattern Audio uses for its 8+ signal subscriptions |
| hud-ui-system.md | Rule 1: Subscription-based data reading — reads GSM state, Player HP, Absorption meter | Distinguishes signal-based events (HUD connects to) from property-based queries (HUD reads directly) |
| game-state-manager.md | Rule 7: GSM exposes `state_changed` signal | Names and payloads follow the past-tense + typed-params convention |
| player-system.md | Signals: `player_hit`, `damage_dealt`, `player_died` | Payload format: positional `(float)` for simple, Dictionary for combat events |
| All 12 MVP GDDs | Cross-system communication pattern | Establishes the single pattern every system follows for signal declaration, connection, and emission |

## Performance Implications

- **CPU**: `connect()` happens once at `_ready()` time — zero per-frame cost. `emit()` is Godot's native signal dispatch — O(listeners) with negligible constant factor (< 0.01ms per emission for 3-4 listeners).
- **Memory**: No additional data structures. Signal connections are part of Godot's Object internals.
- **Load Time**: 50-70 `connect()` calls at game start — sub-millisecond total.

## Migration Plan

N/A — no existing signal code to migrate. This ADR establishes conventions before implementation begins.

## Validation Criteria

- Every `signal` declaration in the codebase uses snake_case past tense or present-state form
- Every signal with 0-3 params uses positional args with type hints
- Every signal with 4+ params uses a typed Dictionary with documented keys
- Every `connect()` call is in `_ready()` — none in `_process()`, `_input()`, or inline callbacks
- Every `connect()` references a named method, never a lambda
- Every system's `_ready()` opens with a comment block listing its signal subscriptions
- No system disconnects/reconnects signals at runtime
- No separate EventBus Autoload exists in MVP

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — establishes the Autoload pattern this ADR's signal conventions build on
- ADR-0003: Object Pooling Architecture — pooled nodes use boolean guards instead of connect/disconnect
