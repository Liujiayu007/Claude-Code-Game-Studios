# ADR-0008: Absorption System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — This is a pure gameplay logic system with no engine API dependency beyond GDScript math and signals. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify meter fill/drain at 60fps edge cases — rapid collect + immediate transform request within same frame must resolve deterministically |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — AbsorptionSystem is Autoload #6, Core layer. ADR-0004 (Signal Bus Pattern) — meter_full and meter_changed signals. ADR-0005 (DataConfig) — all thresholds are DataConfig values. ADR-0007 (GSM State Machine) — meter behavior per game state. |
| **Enables** | TransformationSystem (meter full → can transform), Audio (BGM layers + charging pitch), HUD (meter display) |
| **Blocks** | TransformationSystem stories, Audio charging sound stories, HUD meter stories |
| **Ordering Note** | Must be Accepted before TransformationSystem or Audio system implementation begins. AbsorptionSystem produces the data both depend on. |

## Context

### Problem Statement

The core risk/reward loop of Shapeshift Survivor is: collect energy from defeated enemies → fill the absorption meter → trigger transformation. The meter is the central gameplay resource connecting Combat (enemies drop energy), Player (collection radius), Absorption (storage + thresholds), Transformation (consumption to activate), Audio (BGM intensity + charging pitch), and HUD (visual meter). Without a defined meter architecture, three systems (Absorption, Transformation, Audio) could develop conflicting ideas of "how full the meter is" — especially at boundary conditions: meter hits 1.0 on the same frame the player presses transform, or meter drains during TRANSFORMATION state.

### Constraints

- Godot 4.6 + GDScript
- 60 fps target — meter updates must be frame-consistent (no floating point drift from delta accumulation)
- Single meter (one resource type) for MVP — form-specific meters deferred to Vertical Slice
- Audio reads `meter_current` every frame for BGM layer crossfade
- HUD reads `meter_current` every frame for meter bar display
- Meter fill is a core gameplay mechanic — must feel responsive and legible

### Requirements

- Single float meter: 0.0 (empty) → 1.0 (full)
- Meter fills by collecting enemy drops (energy pickups)
- Meter drains to 0.0 when transformation is activated
- `meter_changed(new_value: float)` signal on every value change
- `meter_full` signal when meter crosses 1.0 threshold
- Threshold events at 0.25, 0.5, 0.75 for BGM layer triggers
- Meter cannot exceed 1.0 (capped)
- Meter cannot go below 0.0 (capped)
- During TRANSFORMATION/BERSERK/COOLDOWN/UPGRADE/BOSS/DEATH: meter does not fill, current value preserved

## Decision

**Single normalized float meter (0.0–1.0) with threshold event signals. AbsorptionSystem owns the meter state exclusively. Fill via `add_energy(amount)` method. Drain via `consume_all()` on transform activation. Threshold crossing signals emitted on value change.**

### Core Meter Model

```gdscript
# AbsorptionSystem.gd — Autoload #6
extends Node

signal meter_changed(new_value: float)
signal meter_full()                       # Emitted when meter crosses 1.0
signal meter_threshold_crossed(threshold: float, crossed_up: bool)  # 0.25/0.5/0.75

var meter_current: float = 0.0:
    get = _meter_current_get

var _meter_current: float = 0.0

# DataConfig thresholds (read once in _ready)
var _bgm_thresholds: Array[float] = []   # [0.25, 0.5, 0.75]
var _meter_capacity: float = 100.0        # Raw value capacity (for non-normalized display)

func _ready() -> void:
    _bgm_thresholds = [
        DataConfig.audio_bassline_threshold,    # 0.25
        DataConfig.audio_percussion_threshold,  # 0.5
        DataConfig.audio_lead_threshold,        # 0.75
    ]
    # Signal subscriptions:
    #   GSM.state_changed → _on_state_changed

func _meter_current_get() -> float:
    return _meter_current
```

### Fill Mechanics

```gdscript
func add_energy(amount: float) -> void:
    if _should_block_fill():
        return
    
    var old_value := _meter_current
    _meter_current = clampf(_meter_current + amount, 0.0, 1.0)
    
    if _meter_current == old_value:
        return  # No change — skip signals
    
    meter_changed.emit(_meter_current)
    
    # Check threshold crossings
    for threshold in _bgm_thresholds:
        if old_value < threshold and _meter_current >= threshold:
            meter_threshold_crossed.emit(threshold, true)   # crossed up
        elif old_value >= threshold and _meter_current < threshold:
            meter_threshold_crossed.emit(threshold, false)  # crossed down
    
    # Check full
    if old_value < 1.0 and _meter_current >= 1.0:
        meter_full.emit()

func _should_block_fill() -> bool:
    match GSM.current_state:
        GSM.State.EXPLORATION, GSM.State.CHARGING:
            return false  # Meter fills during exploration and charging
        _:
            return true   # TRANSFORMATION, BERSERK, DEATH, UPGRADE, BOSS, COOLDOWN
```

### Drain Mechanics

```gdscript
func consume_all() -> float:
    # Called by TransformationSystem when transform is activated
    # Returns the amount consumed (for VFX scaling, etc.)
    var consumed := _meter_current
    var old_value := _meter_current
    _meter_current = 0.0
    
    if consumed > 0.0:
        meter_changed.emit(0.0)
        # Emit threshold crossed-down for any thresholds that were met
        for threshold in _bgm_thresholds:
            if old_value >= threshold:
                meter_threshold_crossed.emit(threshold, false)
    
    return consumed
```

### Energy Drop Collection

EnemySystem emits `enemy_killed(position, enemy_type, form_points_drop)`. AbsorptionSystem does NOT connect to this signal directly — instead, energy drops are physical `Area2D` pickups in the game world that PlayerSystem collects. PlayerSystem calls `AbsorptionSystem.add_energy(amount)` on collection:

```gdscript
# PlayerSystem — on pickup area entered:
func _on_pickup_area_entered(area: Area2D) -> void:
    if area is EnergyDrop:
        AbsorptionSystem.add_energy(area.energy_value)
        area.queue_free()  # Drop consumed
```

**Rationale for PlayerSystem-mediated collection (not AbsorptionSystem direct):**
- Collection radius is a PlayerSystem property (GDD player-system.md)
- Pickup magnetism/vacuum is a PlayerSystem behavior (future feature)
- AbsorptionSystem is a pure data store — it doesn't know about world geometry

### Energy Drop Configuration

```gdscript
# EnergyDrop.gd — attached to energy pickup scenes
class_name EnergyDrop
extends Area2D

@export var energy_value: float = 0.05  # 5% of meter per small drop

# Drop types (from DataConfig):
#   small:  0.05 (20 drops to full)
#   medium: 0.10 (10 drops to full)
#   large:  0.25 (4 drops to full)
#   boss:   0.50 (2 drops to full)
```

### Architecture Diagram

```
EnemySystem                    PlayerSystem              AbsorptionSystem
┌──────────┐    drop_spawned   ┌──────────────┐   add_  ┌─────────────────┐
│ enemy_   │──────────────────→│ _on_pickup_  │───energy→│ meter_current   │
│ defeated │   EnergyDrop      │ area_entered │  (amount)│ (0.0–1.0)       │
│ (pos)    │   (Area2D)        │              │         │                 │
└──────────┘                   │ collection_  │         │ consume_all()   │← TransformationSystem
                               │ radius       │         │                 │  (on transform)
                               └──────────────┘         │ Signals:        │
                                                         │ meter_changed   │──→ Audio (BGM layers)
                                                         │ meter_full      │──→ TransformationSystem
                                                         │ meter_threshold │──→ Audio (layer switch)
                                                         │ _crossed        │──→ HUD (meter bar)
                                                         └─────────────────┘
```

### Threshold Semantics

The three BGM thresholds divide the meter into 4 zones:

| Meter Range | BGM Layers Active | Audio State |
|------------|-------------------|-------------|
| 0.00 – 0.25 | Ambient only | Low intensity |
| 0.25 – 0.50 | Ambient + Bassline | Building |
| 0.50 – 0.75 | Ambient + Bassline + Percussion | Medium intensity |
| 0.75 – 1.00 | All 4 layers (including Lead) | High intensity — combat climax |
| = 1.00 | All layers + `meter_full` signal | Ready to transform |

### Signal Emission Order

On `add_energy()` that crosses multiple thresholds:

```
add_energy(0.3)  # meter goes 0.2 → 0.5
  → meter_changed(0.5)
  → meter_threshold_crossed(0.25, true)
  → meter_threshold_crossed(0.5, true)
```

On `consume_all()` from full:

```
consume_all()  # meter goes 1.0 → 0.0
  → meter_changed(0.0)
  → meter_threshold_crossed(0.25, false)
  → meter_threshold_crossed(0.5, false)
  → meter_threshold_crossed(0.75, false)
```

Signals are emitted in ascending threshold order (fill) or descending (drain). Audio and HUD can rely on this order for sequential animations.

### Rationale for Normalized Float (Not Integer Points)

- **Integer model** (0–100 points): Audio needs continuous 0.0–1.0 for BGM crossfade, HUD needs continuous 0.0–1.0 for smooth meter bar. Integer would require division every frame: `_meter_points / 100.0`.
- **Normalized float**: Direct use — `meter_current` IS the crossfade weight. No conversion. Natural for threshold comparisons (`< 0.25` vs `if points < 25`).
- **Precision**: 32-bit float has ~7 significant digits. Meter changes by 0.05 minimum (smallest drop). No precision issues at 60fps.

## Alternatives Considered

### Alternative 1: Integer point system (0–100)

- **Description**: Meter is an integer 0–100. Drops award integer points (5, 10, 25). Thresholds at 25, 50, 75.
- **Pros**: No floating-point comparison edge cases. Integer math is exact. Easier to display as "25/100" text.
- **Cons**: Every crossfade and meter bar render divides by 100. Threshold comparisons are trivially correct in float (clampf + bounds check). The "floating point edge cases" concern is theoretical at 0.05 increments — there is no repeated addition drift.
- **Rejection Reason**: Normalized float is the natural domain for both Audio crossfade and HUD meter bar. Integer would add a division step in every consumer with no actual precision benefit.

### Alternative 2: Per-form meters (Beast meter + Dragon meter)

- **Description**: Each transformation form has its own meter. Collecting energy fills the meter of the currently selected form.
- **Pros**: Strategic depth — player chooses which form to charge. Different forms could have different meter capacities.
- **Cons**: Doubles the meter state (2 forms × 1 meter each = 2 signals). HUD must show 2 meters. Audio would need per-form BGM layers — complex. GDD specifies single meter for MVP.
- **Rejection Reason**: GDD absorption-system.md (MVP scope) defines one meter. Per-form meters are a Vertical Slice feature — the single-meter architecture supports extension by adding a `_meters: Dictionary[String, float]` later.

### Alternative 3: Time-based passive drain

- **Description**: Meter slowly drains over time when not collecting (urgency mechanic).
- **Pros**: Creates time pressure — "use it or lose it." Common in action games.
- **Cons**: GDD absorption-system.md does not specify passive drain. The transformation cooldown (TransformationSystem) is the resource constraint, not meter drain. Adding drain complicates the meter model (drain rate, minimum floor) and creates feel-bad moments when meter drains just before reaching 1.0.
- **Rejection Reason**: The GDD's tension comes from cooldown management (TransformationSystem), not meter drain. Adding a second time-pressure mechanic dilutes both.

## Consequences

### Positive

- **Single source of truth**: `AbsorptionSystem.meter_current` is the authoritative meter value. No duplicate calculation or cached copies in other systems.
- **Threshold events are precise**: `meter_threshold_crossed` fires exactly once per crossing. Audio can trigger BGM layer switches without polling thresholds every frame.
- **Simple mental model for fill/drain**: `add_energy(amount)` / `consume_all()`. Two methods. No state machine.
- **Frame-consistent**: `clampf()` prevents out-of-bounds values. State-based fill blocking prevents meter change during invalid states.
- **Signal-driven consumers**: Audio and HUD never poll `meter_current` for threshold events — they react to `meter_threshold_crossed`. Only continuous crossfade reads `meter_current` per frame.

### Negative

- **Single meter limits strategic depth**: Cannot charge different forms independently. **Accepted cost**: GDD MVP scope. Extension path is documented.
- **No overflow mechanic**: Meter caps at 1.0 — excess energy from drops while full is lost. **Accepted cost**: The `meter_full` signal can flash the HUD meter as a "wasted energy" warning, teaching the player to transform promptly.
- **AbsorptionSystem is passive**: It's a data store with signals — it doesn't spawn drops, collect them, or trigger transforms. **Accepted cost**: This is by design. Each system owns its domain: EnemySystem spawns drops, PlayerSystem collects them, AbsorptionSystem stores energy, TransformationSystem consumes it.

### Risks

- **Risk: Floating point never exactly reaches 1.0**: `_meter_current` accumulates via `clampf(_meter_current + amount, 0.0, 1.0)`. If amounts are always multiples of 0.05 and start from 0.0, the sum will exactly hit 1.0 after 20 small drops. **Mitigation**: Using `>= 1.0` in the `meter_full` check handles any precision edge case.
- **Risk: `consume_all()` called when meter is 0**: TransformationSystem should check `meter_current > 0` before calling `consume_all()`. If called with 0, `meter_changed` and `meter_threshold_crossed` signals do not fire — no visual/audio artifacts from a "zero consume." **Mitigation**: TransformationSystem's own gate check prevents this.
- **Risk: Rapid add_energy() calls in one frame**: Multiple pickups collected simultaneously (enemies killed by AoE). Each calls `add_energy()` independently. `meter_full` signal fires only once (guarded by `old_value < 1.0` check). **Mitigation**: The guard condition ensures `meter_full` emits at most once per fill cycle.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| absorption-system.md | Core: Single 0.0–1.0 meter, fills via enemy drops, drains on transform | `add_energy(amount)` / `consume_all()` with state-based fill blocking |
| absorption-system.md | Exposes: `meter_current` (read-only), `meter_full` signal | Public `meter_current` getter + `meter_full` signal with crossing guard |
| absorption-system.md | Threshold events for BGM layers at 0.25, 0.5, 0.75 | `meter_threshold_crossed(threshold, crossed_up)` on each threshold boundary |
| audio-system.md | Rule 4: BGM layered dynamic music — layer intensity crossfade + charging pitch mapped to `meter_current` | `meter_current` is 0.0–1.0 float — direct crossfade weight. No conversion needed |
| audio-system.md | F.3: Charging pitch mapping — `meter_ratio → C2 + 24 semitones` | `meter_current` is the `meter_ratio` input to the charging pitch formula |
| audio-system.md | BGM crossfade duration 0.3s | Audio reads `meter_current` changes and applies crossfade — AbsorptionSystem provides the value, Audio controls the smoothing |
| hud-ui-system.md | Meter bar display — reads `meter_current` per frame | HUD reads `AbsorptionSystem.meter_current` for smooth bar rendering |
| transformation-system.md | Transform activation requires meter >= max | TransformationSystem reads `meter_current` and calls `consume_all()` on activation |
| vfx-system.md | Charging/meter glow VFX intensity | VFX reads `meter_current` or connects to `meter_changed` for glow intensity |
| enemy-system.md | Enemies drop energy on death | EnemySystem spawns EnergyDrop instances. AbsorptionSystem does not control drop spawning |
| player-system.md | Player collects drops via pickup radius | PlayerSystem detects Area2D overlap and calls `AbsorptionSystem.add_energy()` |

## Performance Implications

- **CPU**: `add_energy()` is O(1) — one clamp, one comparison, at most 3 threshold checks (3-element array). Called per pickup collected (typically 1-5 per frame). Total < 0.01ms/frame.
- **Memory**: One float + one Array[float] (3 elements). Negligible.
- **Load Time**: Zero — no resources to load.

## Migration Plan

N/A — AbsorptionSystem is created fresh. No existing meter code to migrate.

## Validation Criteria

- `add_energy(0.05)` 20 times → `meter_current` reaches exactly 1.0 → `meter_full` signal fires once
- `add_energy(0.1)` when already at 0.95 → `meter_current` is 1.0 (capped, no overflow)
- `consume_all()` at 0.8 → returns 0.8 → `meter_current` is 0.0 → `meter_changed(0.0)` emitted
- Crossing 0.25 threshold upward → `meter_threshold_crossed(0.25, true)` emitted
- Crossing 0.25 threshold downward (via consume_all) → `meter_threshold_crossed(0.25, false)` emitted
- `add_energy()` during TRANSFORMATION state → meter unchanged, returns silently
- `consume_all()` when meter is 0.0 → returns 0.0, no signals emitted
- `meter_full` fires at most once per fill cycle (repeated `add_energy(0.01)` at 1.0 does not re-emit)
- Rapid multi-pickup in one frame → `meter_changed` fires once per `add_energy()` call → multiple signals correctly emitted

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — AbsorptionSystem is Autoload #6, Core layer
- ADR-0003: Object Pooling Architecture — EnergyDrop nodes may be pooled if volume warrants
- ADR-0004: Signal Bus Pattern — `meter_changed`, `meter_full`, `meter_threshold_crossed` follow past-tense/state naming conventions
- ADR-0005: Data Configuration Architecture — All thresholds and drop values are DataConfig `@export var` properties
- ADR-0007: GSM State Machine — Fill blocked during non-combat states (TRANSFORMATION, BERSERK, COOLDOWN, UPGRADE, BOSS, DEATH) via `GSM.current_state` check
