# ADR-0001: Autoload Singleton Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — Autoload is a stable Godot pattern with no breaking changes in 4.4–4.6 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None — Autoload pattern is well-established and unchanged |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | All future ADRs — system implementation cannot begin without knowing the access pattern |
| **Blocks** | All system implementation stories — must be Accepted before any system code is written |
| **Ordering Note** | This is the first architectural decision. All subsequent ADRs assume this access pattern. |

## Context

### Problem Statement

Shapeshift Survivor has 12 MVP systems spanning 4 layers (Foundation → Core → Presentation). Every system communicates via signals and queries: GSM's `state_changed` is consumed by all Presentation systems, Player's `damage_dealt` is consumed by VFX and Audio, Absorption's `meter_current` is queried every frame by Audio and HUD. These cross-system references require a globally accessible, consistent access pattern. The decision must be made before any system implementation begins, as the access pattern shapes every `connect()` and property read in the codebase.

### Constraints

- Godot 4.6 + GDScript
- GL Compatibility renderer (no impact on architecture choice)
- Solo developer — simplicity and consistency prioritized over team-isolation concerns
- 60 fps target — access pattern must not add frame overhead
- All 12 MVP GDDs are designed — the access pattern must satisfy every documented signal connection and data query

### Requirements

- Every system must be able to `connect()` to any other system's signals
- Every system must be able to read any other system's public read-only properties
- Initialization order must respect the dependency chain (Foundation before Core before Presentation)
- No system may directly modify another system's internal state
- The pattern must be idiomatic Godot — a stranger reading the code should recognize the pattern

## Decision

**All 12 MVP systems are registered as Godot Autoload singletons.**

Each system is a standalone `.gd` script registered in `project.godot`'s `[autoload]` section. The Autoload list is ordered by dependency depth, ensuring Foundation systems load before Core, which load before Presentation. Systems access each other directly via their global Autoload name — no service locator, no dependency injection container, no manager indirection.

### Architecture Diagram

```
project.godot [autoload] (load order, top to bottom)
────────────────────────────────────────────────────────
 1. DataConfig            ─── Foundation (zero dependencies)
 2. GSM                   ─── Foundation
 3. InputSystem           ─── Foundation
 4. PlayerSystem          ─── Core (depends on 1,2,3)
 5. EnemySystem           ─── Core (depends on 1,2)
 6. AbsorptionSystem      ─── Core (depends on 1,4,5)
 7. TransformationSystem  ─── Core (depends on 1,2,4,6)
 8. AreaSystem            ─── Core (depends on 1,2)
 9. WaveSystem            ─── Core (depends on 1,5,8)
10. HUD                   ─── Presentation (depends on 4,7,8,11)
11. VFX                   ─── Presentation (depends on 2,4,7)
12. Audio                 ─── Presentation (depends on 2,4,7,8)

Signal flow (primary):  Foundation → Core → Presentation
Data query flow:         Presentation → Core → Foundation
```

### Key Interfaces

**Every Autoload system exposes exactly three categories of public members:**

1. **Signals** (output — other systems connect to these):
   ```gdscript
   signal state_changed(old_state: GSM.State, new_state: GSM.State)
   signal player_hit(damage: float)
   signal damage_dealt(target: Node2D, amount: float)
   signal wave_started(wave: int)
   ```

2. **Read-only properties** (input — other systems query these):
   ```gdscript
   var current_state: GSM.State: get = _current_state_get
   var hp_current: float: get = _hp_current_get
   var meter_current: float: get = _meter_current_get
   var current_form_id: String: get = _current_form_id_get
   ```

3. **Request methods** (limited — only where a system needs another to perform an action):
   ```gdscript
   func request_transition(target: GSM.State) -> bool
   ```

**System-to-system communication pattern** (enforced by code review):
```gdscript
# ✅ ALLOWED: connect to signal in _ready()
func _ready() -> void:
    GSM.state_changed.connect(_on_state_changed)

# ✅ ALLOWED: read public property
func _process(_delta: float) -> void:
    var hp = PlayerSystem.hp_current / PlayerSystem.hp_max

# ❌ FORBIDDEN: direct state mutation
func _on_something() -> void:
    PlayerSystem.hp_current = 50  # NEVER do this
```

**Initialization contract**: Each Autoload's `_ready()` runs in project-settings order. Foundation systems `_ready()` first, then Core, then Presentation. Presentation systems may safely assume all Foundation and Core systems are `_ready()` when their own `_ready()` runs. Core systems must not assume Presentation systems exist.

## Alternatives Considered

### Alternative 1: SystemManager Autoload

- **Description**: A single `SystemManager` Autoload holds references to all systems. Access via `Systems.gsm`, `Systems.player`, etc.
- **Pros**: One Autoload entry in project settings; centralized lifecycle control; easy to swap implementations
- **Cons**: Extra indirection on every access (`Systems.gsm` vs `GSM`); non-idiomatic in Godot (Autoload IS the Godot singleton pattern); requires SystemManager to initialize every system manually
- **Rejection Reason**: Adds ceremony without benefit for a solo project. The "swap implementations" advantage is theoretical — all 12 GDDs define fixed system interfaces. Autoload already provides the lifecycle control SystemManager would duplicate.

### Alternative 2: Hybrid — Foundation Autoload + Core/Presentation via SystemManager

- **Description**: GSM, DataConfig, InputSystem as Autoloads; Core and Presentation systems registered in a SystemManager dictionary
- **Pros**: Limits Autoload count to 3; acknowledges Foundation's special status
- **Cons**: Inconsistent access pattern — some systems are globals (`GSM`), others are `Systems.player`. Two mental models instead of one. Solo developer pays the cognitive cost with no benefit.
- **Rejection Reason**: Consistency beats minimalism for a solo project. 12 Autoloads is well within Godot's practical limits. Splitting the pattern across layers creates confusion for no gain.

## Consequences

### Positive

- **Idiomatic Godot**: Every Godot developer who reads the code immediately understands how systems are accessed. No custom infrastructure to learn.
- **Minimal ceremony**: Adding a new system = create `.gd` + add one line to `project.godot`. No registration code to write.
- **Zero-call overhead**: Direct global access has no indirection (`GSM.current_state` vs `Systems.gsm.current_state`).
- **Natural initialization order**: Godot's Autoload loading order directly enforces the dependency chain. Foundation systems load first by construction.
- **Discoverable**: Any system can be found via autocomplete by its global name — no need to remember which manager holds which reference.

### Negative

- **12 Autoload entries**: Project settings file has 12 `[autoload]` entries. Acceptable — Godot handles dozens of Autoloads without issue.
- **No lazy loading**: All 12 systems load at game start. Each system is lightweight (a `.gd` script + minimal nodes) — total startup overhead is negligible for a 2D pixel art game.
- **Global namespace pollution**: 12 global names in the script namespace. Mitigated by descriptive, unique names (`TransformationSystem`, not `TS`).

### Risks

- **Risk: Accidental circular dependency during init**: If two systems reference each other in `_ready()`, one gets `null`. **Mitigation**: Autoload order prevents this — Presentation systems (at the end) can reference any earlier system, but earlier systems must not reference later ones.
- **Risk: Signal connection explosion**: 12 systems each connecting to multiple signals could produce messy `_ready()` methods. **Mitigation**: Each system's `_ready()` documents its subscriptions in a comment block. Code review enforces the "signal subscriptions only in `_ready()`" rule.
- **Risk: Systems grow too coupled**: Direct global access could tempt developers to bypass the signal contract and directly call methods. **Mitigation**: GDD-defined interfaces specify exactly what each system exposes. ADR-0001's "Allowed/Forbidden" patterns are enforced in code review.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-state-manager.md | Rule 7: GSM exposes `state_changed` signal + `current_state` read-only property + `request_transition()` method | GSM Autoload — all systems connect via `GSM.state_changed.connect()` and read `GSM.current_state` |
| player-system.md | Signals: `player_hit`, `damage_dealt`, `player_died` | PlayerSystem Autoload — VFX/Audio/HUD connect via `PlayerSystem.player_hit.connect()` |
| transformation-system.md | Signals: `transformation_started`, `transformation_expired`, `berserk_activated`, `berserk_expired`, `cooldown_complete`, `transformation_failed` | TransformationSystem Autoload — VFX/Audio/HUD subscribe to transform lifecycle |
| absorption-system.md | Exposes: `meter_current` (read-only), `meter_full` signal | AbsorptionSystem Autoload — Audio reads `AbsorptionSystem.meter_current` per frame |
| wave-system.md | Signals: `wave_started`, `wave_cleared`, `boss_wave_started`, `all_waves_cleared` | WaveSystem Autoload — VFX/Audio subscribe to wave events |
| vfx-system.md | Rule 1: Signal-driven pure response system — subscribes to GSM, Player, Transformation, Wave signals | VFX Autoload — connects to all upstream signals in `_ready()` |
| audio-system.md | Rule 1: Signal-driven pure response system — subscribes to GSM, Player, Transformation, Wave, Absorption signals | Audio Autoload — connects to all upstream signals in `_ready()` |
| hud-ui-system.md | Rule 1: Subscription-based data reading — reads GSM state, Player HP, Absorption meter | HUD Autoload — reads `GSM.current_state`, `PlayerSystem.hp_current`, etc. |
| data-config.md | Rule 1: Single source of truth for all tunable values — loaded before all other systems | DataConfig Autoload #1 — guaranteed to load first in project settings order |

## Performance Implications

- **CPU**: Negligible — global variable access has no overhead vs. any other variable access in GDScript
- **Memory**: ~12 script instances + minimal node overhead per Autoload (~1 KB each). Total < 100 KB.
- **Load Time**: All 12 Autoloads instantiated at game start. GDscript parsing is the dominant factor — each script is < 200 lines, so parsing time is sub-millisecond.

## Migration Plan

N/A — this is the first architectural decision. No existing code to migrate.

## Validation Criteria

- All 12 systems listed in `project.godot` `[autoload]` section in the specified order
- Each system's `_ready()` connects to upstream signals only (never references a system later in the load order)
- No system directly assigns to another system's properties
- Cross-system communication uses signals (for events) + read-only properties (for queries) exclusively

## Related Decisions

- [No other ADRs yet]
