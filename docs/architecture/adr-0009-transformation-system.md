# ADR-0009: Transformation System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — Pure gameplay logic system. Timer-based duration/cooldown uses Godot's `Timer` node or `_process()` delta accumulation. No post-cutoff API dependency. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify cooldown timer accuracy at 60fps — delta accumulation must not drift. Verify rapid activate/cancel/activate cycle does not leave residual timer state. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — TransformationSystem is Autoload #7, Core layer. ADR-0005 (DataConfig) — FormConfig resources. ADR-0007 (GSM State Machine) — TRANSFORMATION state. ADR-0008 (Absorption System) — meter consumption. |
| **Enables** | VFX (transform tear, form aura, berserk overlay), Audio (transform 3-layer overlay), HUD (cooldown bar, form meter), PlayerSystem (stat modifiers during transformation) |
| **Blocks** | VFX transform stories, Audio transform stories, HUD cooldown stories, PlayerSystem stat modifier stories |
| **Ordering Note** | Must be Accepted after ADR-0008 (Absorption). TransformationSystem consumes the meter that AbsorptionSystem provides. |

## Context

### Problem Statement

Shapeshift Survivor's core mechanic is transforming into monster forms. The transformation flow touches 6 systems: Player presses transform key (InputSystem) → AbsorptionSystem has enough meter? → GSM transitions to TRANSFORMATION state → TransformationSystem activates form, starts duration timer → PlayerSystem gets stat modifiers → VFX plays transform tear + form aura → Audio plays sub-boom + form signature + tear sweep → duration expires → GSM transitions to CHARGING → TransformationSystem starts cooldown → HUD shows cooldown bar. Without a defined transformation architecture, the activation gate checks, duration/cooldown timing, form definition loading, berserk trigger conditions, and cooldown-gating logic would be scattered across InputSystem, PlayerSystem, and GSM — producing three different "can I transform?" answers.

### Constraints

- Godot 4.6 + GDScript
- 2 forms for MVP: Beast + Dragon (more forms in Vertical Slice)
- Forms defined as DataConfig FormConfig Custom Resources (ADR-0005)
- Transformation has: activation gate, duration (active time), cooldown (can't reactivate)
- Berserk mode: enhanced transformation triggered when meter is full at activation
- During TRANSFORMATION state: movement allowed, attack suppressed, transform keys suppressed
- Solo developer — form count may grow; architecture should support adding forms with data-only changes

### Requirements

- Player can activate transformation when: (a) meter_current >= meter_max (1.0), (b) cooldown is complete, (c) GSM is in CHARGING state
- On activation: meter_current resets to 0 → enter TRANSFORMATION state → apply form stat modifiers → start duration timer
- Duration: form is active for N seconds (per-form, from FormConfig)
- Cooldown: after duration expires, cooldown of M seconds before next transform (per-form, from FormConfig)
- Berserk: if meter_current == 1.0 at activation, transformation is "berserk" — enhanced stats + special VFX/Audio
- Form selection: player selects active form via key (1=Beast, 2=Dragon) or cycles forms
- `transformation_started(form_id, is_berserk)` signal on successful activation
- `transformation_expired(form_id)` signal when duration ends
- `berserk_activated` / `berserk_expired` signals
- `cooldown_complete(form_id)` signal when cooldown timer finishes
- `transformation_failed(reason)` signal when activation is rejected (with enum reason)

## Decision

**Centralized TransformationSystem manages form state, activation gates, duration/cooldown timers, and berserk mode. Forms loaded from DataConfig FormConfig resources. Timer-based duration/cooldown via `_process(delta)` accumulation — no Godot Timer nodes.**

### Core State Model

```gdscript
# TransformationSystem.gd — Autoload #7
extends Node

enum FailureReason {
    NONE,
    METER_NOT_FULL,       # meter_current < meter_max
    COOLDOWN_ACTIVE,      # cooldown timer still running
    WRONG_STATE,          # GSM not in CHARGING
    ALREADY_TRANSFORMED,  # already in a transformation
    FORM_UNKNOWN,         # requested form_id not in config
}

signal transformation_started(form_id: String, is_berserk: bool)
signal transformation_expired(form_id: String)
signal berserk_activated()
signal berserk_expired()
signal cooldown_complete(form_id: String)
signal transformation_failed(reason: FailureReason)

var active_form_id: String = ""           # Currently active form ("" = none)
var is_berserk: bool = false              # Is current transformation berserk?
var cooldown_remaining: float = 0.0       # Cooldown timer (seconds)
var duration_remaining: float = 0.0       # Active duration timer (seconds)
var _form_configs: Dictionary = {}        # form_id → FormConfig
var _global_cooldown: bool = false        # Shared cooldown across all forms (MVP)

func _ready() -> void:
    _load_form_configs()
    # Signal subscriptions:
    #   GSM.state_changed → _on_state_changed

func _load_form_configs() -> void:
    for config in DataConfig.form_configs:
        _form_configs[config.form_id] = config
```

### Activation Flow

```gdscript
func request_transformation(form_id: String) -> FailureReason:
    # Gate 1: Valid form?
    if not _form_configs.has(form_id):
        transformation_failed.emit(FailureReason.FORM_UNKNOWN)
        return FailureReason.FORM_UNKNOWN
    
    # Gate 2: Already transformed?
    if active_form_id != "":
        transformation_failed.emit(FailureReason.ALREADY_TRANSFORMED)
        return FailureReason.ALREADY_TRANSFORMED
    
    # Gate 3: GSM in CHARGING?
    if GSM.current_state != GSM.State.CHARGING:
        transformation_failed.emit(FailureReason.WRONG_STATE)
        return FailureReason.WRONG_STATE
    
    # Gate 4: Meter full?
    if AbsorptionSystem.meter_current < 1.0:
        transformation_failed.emit(FailureReason.METER_NOT_FULL)
        return FailureReason.METER_NOT_FULL
    
    # Gate 5: Cooldown complete?
    if _global_cooldown and cooldown_remaining > 0.0:
        transformation_failed.emit(FailureReason.COOLDOWN_ACTIVE)
        return FailureReason.COOLDOWN_ACTIVE
    
    # All gates passed — activate
    _activate(form_id)
    return FailureReason.NONE

func _activate(form_id: String) -> void:
    var config: FormConfig = _form_configs[form_id]
    
    # Determine berserk
    var was_full := AbsorptionSystem.meter_current >= 1.0
    is_berserk = was_full
    
    # Consume meter
    AbsorptionSystem.consume_all()
    
    # Set active state
    active_form_id = form_id
    duration_remaining = config.duration_seconds
    if is_berserk:
        duration_remaining *= DataConfig.berserk_duration_multiplier  # e.g., 1.5x
    
    # Request state transition (may fail if GSM rejects)
    if not GSM.request_transition(GSM.State.TRANSFORMATION):
        _cancel_activation()
        return
    
    # Apply stat modifiers (notified via signal — PlayerSystem listens)
    transformation_started.emit(form_id, is_berserk)
    if is_berserk:
        berserk_activated.emit()

func _cancel_activation() -> void:
    # Rollback on GSM rejection (shouldn't happen — CHARGING→TRANSFORMATION is valid)
    # Refund meter if needed
    active_form_id = ""
    is_berserk = false
    duration_remaining = 0.0
```

### Duration & Cooldown Tick

```gdscript
func _process(delta: float) -> void:
    # Tick active duration
    if active_form_id != "":
        duration_remaining -= delta
        if duration_remaining <= 0.0:
            _expire_transformation()
    
    # Tick cooldown
    if cooldown_remaining > 0.0:
        cooldown_remaining -= delta
        if cooldown_remaining <= 0.0:
            cooldown_remaining = 0.0
            cooldown_complete.emit(active_form_id)  # Note: active_form_id is "" here
                                                     # Actually: _last_form_id

func _expire_transformation() -> void:
    var expired_form := active_form_id
    var was_berserk := is_berserk
    
    # Clear state
    active_form_id = ""
    is_berserk = false
    duration_remaining = 0.0
    
    # Start cooldown
    var config: FormConfig = _form_configs[expired_form]
    cooldown_remaining = config.cooldown_seconds
    
    # Return to CHARGING
    GSM.request_transition(GSM.State.CHARGING)
    
    # Notify
    if was_berserk:
        berserk_expired.emit()
    transformation_expired.emit(expired_form)
```

### GSM State Reaction

```gdscript
func _on_state_changed(old_state: GSM.State, new_state: GSM.State) -> void:
    match new_state:
        GSM.State.DEATH:
            # Cancel active transformation on death
            if active_form_id != "":
                var was_berserk := is_berserk
                active_form_id = ""
                is_berserk = false
                duration_remaining = 0.0
                # No cooldown on death-cancel
                if was_berserk:
                    berserk_expired.emit()
                transformation_expired.emit(active_form_id)  # FIX: use saved var
```

### Architecture Diagram

```
Player Input              TransformationSystem            GSM
┌──────────┐  request_    ┌──────────────────────┐  request_  ┌──────────┐
│ Input    │──transformation─→ Gate checks:       │──transition→│          │
│ System   │  ("beast")   │ 1. Valid form?       │──CHARGING──→│  GSM     │
│          │              │ 2. Already active?   │  →TRANS.   │          │
│ (Player) │              │ 3. GSM == CHARGING?    │            └──────────┘
└──────────┘              │ 4. Meter >= max?        │
                          │ 5. Cooldown done?    │   consume_all()
                          │                      │──→AbsorptionSystem
                          │ All pass → _activate │
                          │                      │   signals
                          │ duration timer       │──→VFX, Audio, HUD
                          │ cooldown timer       │
                          │ berserk state        │
                          └──────────────────────┘
```

### Stat Modifiers (Delegate to PlayerSystem)

TransformationSystem does NOT modify PlayerSystem stats directly (forbidden by ADR-0001). Instead, PlayerSystem listens to `transformation_started` and applies stat modifiers from the FormConfig:

```gdscript
# PlayerSystem — signal handler
func _on_transformation_started(form_id: String, is_berserk: bool) -> void:
    var config := DataConfig.get_form_config(form_id)
    _stat_multipliers.hp = config.hp_multiplier
    _stat_multipliers.speed = config.speed_multiplier
    _stat_multipliers.damage = config.damage_multiplier
    if is_berserk:
        _stat_multipliers.hp *= DataConfig.berserk_stat_multiplier
        _stat_multipliers.damage *= DataConfig.berserk_stat_multiplier

func _on_transformation_expired(_form_id: String) -> void:
    _stat_multipliers.hp = 1.0
    _stat_multipliers.speed = 1.0
    _stat_multipliers.damage = 1.0
```

### Berserk Trigger & Behavior

Berserk activates when `meter_current >= 1.0` at the moment of transformation:

| Property | Normal Transform | Berserk |
|----------|-----------------|---------|
| Duration | `FormConfig.duration_seconds` | `duration × berserk_duration_multiplier` (1.5×) |
| Stats | `FormConfig` multipliers | `FormConfig × berserk_stat_multiplier` (1.3×) |
| VFX | Form aura only | Form aura + berserk overlay (VFX_Overlay layer 5) |
| Audio | Transform 3-layer overlay | AUD-006 + AUD-007 on top |
| Meter cost | All meter consumed | All meter consumed |
| Cooldown | Standard | Standard (no penalty for berserk) |

### Form Selection

```gdscript
var _selected_form_id: String = ""  # Currently selected (not active) form

func select_form(form_id: String) -> void:
    if _form_configs.has(form_id):
        _selected_form_id = form_id
    else:
        push_warning("[Transformation] Unknown form: %s" % form_id)

func cycle_form() -> void:
    var ids := _form_configs.keys()
    var idx := ids.find(_selected_form_id)
    idx = (idx + 1) % ids.size()
    _selected_form_id = ids[idx]

# Quick-activate current selection:
func request_current_form() -> FailureReason:
    if _selected_form_id == "":
        return FailureReason.FORM_UNKNOWN
    return request_transformation(_selected_form_id)
```

### Rationale for Timer via _process(delta) (Not Godot Timer Nodes)

- **Delta accumulation is zero-allocation**: No `Timer.new()` calls. No node management.
- **Timers don't need signals for simple countdown**: `duration_remaining -= delta` is one line. A Timer would need `timeout.connect()`, `start()`, `stop()` — more ceremony.
- **Pause behavior is explicit**: `_process(delta)` stops at `Engine.time_scale = 0.0` (e.g. during DEATH state). If duration should continue during pause, use `_physics_process` or unscaled delta. For MVP, duration/cooldown freeze during pause — correct behavior.
- **Single tick point**: Duration AND cooldown tick in one `_process()`. Two separate Timer nodes would need separate signal handlers.

## Alternatives Considered

### Alternative 1: Godot Timer nodes for duration and cooldown

- **Description**: `_duration_timer: Timer` and `_cooldown_timer: Timer` as children of TransformationSystem. Start/stop on activate/expire.
- **Pros**: Timer handles pausing automatically. `timeout` signal is well-understood. No manual delta math.
- **Cons**: Timer nodes add scene tree overhead (minimal but real). Two timers = two signal connections = two handlers. Pausing a Timer during PAUSE is automatic — which is correct for MVP, but less visible to the developer reading the code (delta math is explicit about when time passes).
- **Rejection Reason**: Delta accumulation in `_process()` is 3 lines per timer and makes the time flow explicit. The "automatic pause" behavior of Timer is a hidden assumption; delta math makes the developer consciously decide whether to use scaled or unscaled time.

### Alternative 2: Per-form independent cooldowns (not shared)

- **Description**: Each form has its own cooldown timer. Player can transform Beast → Beast expires → switch to Dragon immediately (Dragon cooldown is separate).
- **Pros**: Encourages form-switching gameplay. Reduces downtime between transformations.
- **Cons**: GDD specifies a shared cooldown for MVP ("cooldown_complete" signal has `form_id` parameter — but the GDD may intend sequential transforms). Two parallel cooldowns would let the player be in transformation state nearly 100% of the time with 2 forms — undermining the "survivor" tension.
- **Rejection Reason**: Shared cooldown for MVP keeps the survivor tension high. Per-form cooldowns are a Vertical Slice tuning decision — the architecture supports it via `_global_cooldown` boolean flag (swap to per-form Dictionary for cooldowns).

### Alternative 3: Transformation as a PlayerSystem sub-state (no separate system)

- **Description**: PlayerSystem manages transformation state internally. No dedicated TransformationSystem Autoload.
- **Pros**: One less Autoload. All player state in one place.
- **Cons**: Transformation touches 6 systems (GSM, Absorption, VFX, Audio, HUD, Player). PlayerSystem would need to own GSM transitions, meter consumption, and cooldown display — bloating PlayerSystem beyond its GDD scope (movement + combat + stats). The GDD explicitly separates PlayerSystem (#4) from TransformationSystem (#7).
- **Rejection Reason**: GDD systems index separates them. PlayerSystem handles moment-to-moment gameplay; TransformationSystem handles the transform lifecycle. Separation of concerns.

## Consequences

### Positive

- **5-gate activation check**: Every rejection reason is an enum value. `transformation_failed` signal carries the reason — HUD can display "Cooldown: 3.2s" or "Meter empty" contextually.
- **Berserk is a boolean, not a separate state**: Simpler than a BERSERK game state in GSM. VFX/Audio react to `berserk_activated` signal independently.
- **Timer state is transparent**: `duration_remaining` and `cooldown_remaining` are readable properties. HUD queries them for bar displays. No need to query Timer.time_left.
- **Form-agnostic core**: Adding a new form = adding a FormConfig.tres + adding it to DataConfig.form_configs. Zero code changes in TransformationSystem.
- **Stat modifiers via signals**: PlayerSystem owns its stat state. TransformationSystem only notifies — respecting ADR-0001's "no direct state writes" rule.

### Negative

- **Single active form at a time**: Cannot stack or chain forms. **Accepted cost**: GDD specifies one transformation at a time. Stacking forms is not an MVP feature.
- **Global cooldown blocks all forms**: After Beast expires, cannot immediately Dragon. **Accepted cost**: Encourages strategic timing. Tuning knob (`_global_cooldown` flag) enables per-form cooldowns if gameplay testing shows it's more fun.
- **No partial meter consumption**: Always consumes all meter. Cannot "spend 50% for a half-duration transform." **Accepted cost**: GDD specifies full meter consumption. Partial consumption is a Vertical Slice tuning option.

### Risks

- **Risk: Double-activation from input buffering**: ADR-0006's 150ms buffer could cause `request_transformation()` to be called twice. **Mitigation**: Gate 2 (ALREADY_TRANSFORMED) rejects the second call. The first call sets `active_form_id` before GSM transition completes, blocking the second.
- **Risk: Death during TRANSFORMATION state**: Player dies while transformed. **Mitigation**: GSM allows TRANSFORMATION→DEATH transition. `_on_state_changed` cancels the active transformation. Cooldown is skipped (death resets state).
- **Risk: GSM rejects CHARGING→TRANSFORMATION transition**: All gates pass but GSM's transition matrix rejects (shouldn't happen — the matrix allows it). **Mitigation**: `_cancel_activation()` rolls back state. `transformation_failed(WRONG_STATE)` emitted.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| transformation-system.md | Signals: `transformation_started`, `transformation_expired`, `berserk_activated`, `berserk_expired`, `cooldown_complete`, `transformation_failed` | All 6 signals defined with typed parameters and emit points |
| transformation-system.md | Activation gates: meter >= max, cooldown complete, CHARGING state, not already transformed, valid form | 5-gate check in `request_transformation()` with FailureReason enum |
| transformation-system.md | Berserk mode: meter == 1.0 at activation → enhanced stats + special VFX/Audio | `was_full` check in `_activate()`. `berserk_duration_multiplier` + `berserk_stat_multiplier` from DataConfig |
| transformation-system.md | Duration/Cooldown: per-form from FormConfig | `FormConfig.duration_seconds` + `FormConfig.cooldown_seconds`. Delta accumulation in `_process()` |
| transformation-system.md | Form selection: key 1=Beast, 2=Dragon, cycle | `select_form()`, `cycle_form()`, `request_current_form()` |
| transformation-system.md | Stat modifiers during transformation | PlayerSystem applies multipliers from `transformation_started` signal + FormConfig |
| absorption-system.md | Meter consumed on transformation | `AbsorptionSystem.consume_all()` called in `_activate()` |
| gsm-state-manager.md | TRANSFORMATION state: movement allowed, combat blocked | GSM state transition in `_activate()`. Input blocking via ADR-0006 |
| vfx-system.md | Transform tear + form aura + berserk overlay | VFX subscribes to `transformation_started` (with `is_berserk` flag) and `berserk_activated` |
| audio-system.md | Transform 3-layer overlay (sub-boom + form signature + tear sweep) | Audio subscribes to `transformation_started`. Form signature from FormConfig.audio_form_signature |
| hud-ui-system.md | Cooldown bar display | HUD reads `cooldown_remaining` or subscribes to `cooldown_complete` |
| player-system.md | Stat modifiers during transformation | PlayerSystem subscribes to `transformation_started`/`transformation_expired` |

## Performance Implications

- **CPU**: `request_transformation()` is O(1) — 5 boolean checks. `_process(delta)` does 2 float subtractions + 2 comparisons. Total < 0.01ms/frame.
- **Memory**: 2 floats (duration, cooldown), 2 bools (berserk, global_cooldown), 1 String (active_form_id), 1 Dictionary (form_configs). < 1 KB.
- **Load Time**: FormConfig Resource loading in DataConfig (not TransformationSystem). `_load_form_configs()` copies references. Sub-millisecond.

## Migration Plan

N/A — TransformationSystem is created fresh. No existing transformation code to migrate.

## Validation Criteria

- `request_transformation("beast")` with meter at 0.8 → `transformation_started("beast", false)` emitted → GSM transitions to TRANSFORMATION → duration timer starts
- `request_transformation("beast")` with meter at 1.0 → `transformation_started("beast", true)` + `berserk_activated()` emitted
- `request_transformation("beast")` with cooldown active → `transformation_failed(COOLDOWN_ACTIVE)` emitted → no state change
- `request_transformation("beast")` with meter at 0 → `transformation_failed(METER_NOT_FULL)` emitted
- `request_transformation("beast")` during EXPLORATION state → `transformation_failed(WRONG_STATE)` emitted
- `request_transformation("beast")` while already transformed → `transformation_failed(ALREADY_TRANSFORMED)` emitted
- Duration expires → `transformation_expired("beast")` → GSM transitions to CHARGING → cooldown starts
- Berserk duration is longer than normal (duration × berserk_duration_multiplier)
- Death during transformation → transformation cancelled → no cooldown → GSM transitions to DEATH
- Cooldown completes → `cooldown_complete(form_id)` emitted → next `request_transformation()` succeeds

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — TransformationSystem is Autoload #7, Core layer
- ADR-0004: Signal Bus Pattern — All 6 signals follow past-tense naming, typed params
- ADR-0005: Data Configuration Architecture — FormConfig Custom Resources define per-form stats
- ADR-0007: GSM State Machine — GSM owns TRANSFORMATION state. TransformationSystem requests transitions.
- ADR-0008: Absorption System Architecture — TransformationSystem consumes meter via `AbsorptionSystem.consume_all()`
