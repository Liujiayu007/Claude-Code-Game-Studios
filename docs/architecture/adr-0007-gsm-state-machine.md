# ADR-0007: Game State Machine Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — GDScript `enum`, `match` statements, and signal emission are pre-4.0 stable. No engine API dependency — this is a pure code-level state machine pattern. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify state transition validation under rapid-fire requests (e.g., player presses transform + upgrade simultaneously) — only one transition should win |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — GSM is Autoload #2, Foundation layer. ADR-0004 (Signal Bus Pattern) — state_changed signal follows naming conventions. ADR-0006 (Input System) — GSM calls InputSystem.set_blocked_actions() on state change. |
| **Enables** | All 9 downstream systems — VFX, Audio, HUD, PlayerSystem, EnemySystem, WaveSystem, TransformationSystem, AbsorptionSystem, AreaSystem all react to state_changed |
| **Blocks** | All Core and Presentation system stories — every system's behavior branches on GSM.current_state |
| **Ordering Note** | Must be Accepted before any Core system implementation begins. GSM is the central orchestration point for all game flow. |

## Context

### Problem Statement

Shapeshift Survivor's core loop is "蓄能→爆发" (Charge → Explode): the player moves and auto-attacks enemies in an open arena, kills generate form points that fill a meter, at full meter the player transforms into a monster form (Beast/Dragon), the transformation expires into a cooldown period, and the cycle repeats. This cycle maps to 8 distinct gameplay states: EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, UPGRADE, BOSS, DEATH. Every system branches on the current state: Audio switches BGM layers, VFX enables/disables particle types, HUD shows/hides UI sections, InputSystem blocks specific actions, EnemySystem spawns/pauses enemies. Without a centralized state machine with well-defined transition rules, each system independently determines "what state are we in?" — creating inconsistent state interpretations, race conditions on rapid transitions, and silent disagreements about which state is active.

### Constraints

- Godot 4.6 + GDScript
- 8 game states representing the full "蓄能→爆发" cycle
- Solo developer — state machine must be auditable at a glance
- 60 fps target — state transitions must complete within one frame (no multi-frame transition logic in MVP)
- GSM is Autoload #2 (Foundation) — must be `_ready()` before any Core system queries it

### Requirements

- Enum-based state definition — no string state names
- Explicit transition matrix — which state→state transitions are valid
- Atomic transitions — a transition request either fully succeeds or fully fails (no partial state change)
- `state_changed(old_state, new_state)` signal emitted on every successful transition
- Systems can query `GSM.current_state` at any time
- Transition validation is centralized — GSM decides, not the requester
- During TRANSFORMATION: movement allowed, combat/transform actions modified (form-specific attack patterns)
- During BERSERK: same as TRANSFORMATION with enhanced stats
- During DEATH: only restart actions accepted
- During UPGRADE: time_scale = 0, only upgrade UI interactions accepted

## Decision

**Centralized enum-based finite state machine in GSM Autoload. GSM is the sole authority on current state. Transitions are validated against an explicit 8×8 transition matrix matching the GDD's "蓄能→爆发" cycle. Systems react to `state_changed` signal — never assume state from their own context.**

### State Enum

```gdscript
# GSM.gd — Autoload #2
extends Node

enum State {
    EXPLORATION,      # No meter, enemies spawning, player collecting initial kills
    CHARGING,         # Meter filling (meter > 0), enemies active, BGM layers building
    TRANSFORMATION,   # Player transformed (Beast/Dragon), form abilities active, timer running
    BERSERK,          # Enhanced transformation — meter filled during TRANSFORMATION, boosted stats
    COOLDOWN,         # Post-transformation recovery — human form, reduced absorption, timer running
    UPGRADE,          # Upgrade/level-up screen — time paused, UI only
    BOSS,             # Boss enemy active — special spawn, unique BGM
    DEATH,            # Player HP = 0 — death screen, enemies frozen
}

signal state_changed(old_state: State, new_state: State)

var current_state: State = State.EXPLORATION:
    get = _current_state_get

var _current_state: State = State.EXPLORATION
var _transition_in_progress: bool = false
```

### Transition Matrix

Valid transitions (✓ = allowed, ✗ = rejected with warning):

| From → To | EXPL | CHRG | TRNS | BRSK | COOL | UPGD | BOSS | DETH |
|-----------|------|------|------|------|------|------|------|------|
| **EXPLORATION** | — | ✓ | ✗ | ✗ | ✗ | ✓ | ✓ | ✗ |
| **CHARGING** | ✓ | — | ✓ | ✗ | ✗ | ✓ | ✗ | ✓ |
| **TRANSFORMATION** | ✗ | ✗ | — | ✓ | ✓ | ✗ | ✗ | ✓ |
| **BERSERK** | ✗ | ✗ | ✗ | — | ✓ | ✗ | ✗ | ✓ |
| **COOLDOWN** | ✓ | ✓ | ✗ | ✗ | — | ✓ | ✗ | ✗ |
| **UPGRADE** | ✓ | ✓ | ✗ | ✗ | ✗ | — | ✗ | ✗ |
| **BOSS** | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ | — | ✓ |
| **DEATH** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | — |

**Transition rules rationale:**
- EXPLORATION → CHARGING: First enemy killed, meter becomes > 0. EXPLORATION → BOSS: Boss wave triggered. EXPLORATION → UPGRADE: Player opens upgrade menu.
- CHARGING → EXPLORATION: Meter decays to 0 (no kills for `meter_decay_timeout` seconds). CHARGING → TRANSFORMATION: Player presses transform, meter ≥ 1.0, cooldown clear. CHARGING → UPGRADE: Player opens upgrade. CHARGING → DEATH: HP reaches 0.
- TRANSFORMATION → COOLDOWN: Duration timer expires (normal exit). TRANSFORMATION → BERSERK: Meter fills to 1.0 during transformation and `has_berserk = true`. TRANSFORMATION → DEATH: Player killed during transformation.
- BERSERK → COOLDOWN: Berserk duration expires. BERSERK → DEATH: Player killed during berserk.
- COOLDOWN → CHARGING: Cooldown timer expires and `meter_current > 0`. COOLDOWN → EXPLORATION: Cooldown timer expires and `meter_current == 0`. COOLDOWN → UPGRADE: Player opens upgrade.
- UPGRADE → CHARGING: Player closes upgrade, meter > 0. UPGRADE → EXPLORATION: Player closes upgrade, meter == 0.
- BOSS → EXPLORATION: Boss defeated, no next area (MVP: all waves cleared → VICTORY handled at scene level). BOSS → CHARGING: Boss defeated in multi-area mode (VS). BOSS → DEATH: Player killed by boss.
- DEATH → EXPLORATION: Player restarts run.

### Transition Implementation

```gdscript
func request_transition(target: State) -> bool:
    if _transition_in_progress:
        push_warning("[GSM] Transition already in progress — rejecting request to %s" % target)
        return false
    
    if not _is_valid_transition(_current_state, target):
        push_warning("[GSM] Invalid transition: %s → %s" % [_current_state, target])
        return false
    
    _execute_transition(target)
    return true

func _is_valid_transition(from_state: State, to_state: State) -> bool:
    match from_state:
        State.EXPLORATION:
            return to_state in [State.CHARGING, State.UPGRADE, State.BOSS]
        State.CHARGING:
            return to_state in [State.EXPLORATION, State.TRANSFORMATION, State.UPGRADE, State.DEATH]
        State.TRANSFORMATION:
            return to_state in [State.COOLDOWN, State.BERSERK, State.DEATH]
        State.BERSERK:
            return to_state in [State.COOLDOWN, State.DEATH]
        State.COOLDOWN:
            return to_state in [State.EXPLORATION, State.CHARGING, State.UPGRADE]
        State.UPGRADE:
            return to_state in [State.EXPLORATION, State.CHARGING]
        State.BOSS:
            return to_state in [State.EXPLORATION, State.CHARGING, State.DEATH]
        State.DEATH:
            return to_state == State.EXPLORATION
        _:
            return false

func _execute_transition(target: State) -> void:
    _transition_in_progress = true
    var old_state := _current_state
    
    # 1. Exit current state
    _exit_state(_current_state)
    
    # 2. Update state
    _current_state = target
    
    # 3. Enter new state
    _enter_state(target)
    
    # 4. Notify all systems
    state_changed.emit(old_state, target)
    
    # 5. Configure input blocking for new state
    InputSystem.set_blocked_actions(target)
    
    _transition_in_progress = false

func _exit_state(state: State) -> void:
    match state:
        State.UPGRADE:
            Engine.time_scale = 1.0  # Restore normal time
        State.BOSS:
            pass  # Boss-specific cleanup via state_changed signal

func _enter_state(state: State) -> void:
    match state:
        State.UPGRADE:
            Engine.time_scale = 0.0  # Freeze game logic
        State.COOLDOWN:
            pass  # Per-system behavior via state_changed signal
```

### Transition Priority System

When multiple transition requests arrive in the same frame, GSM resolves by priority:

```
DEATH > BOSS > UPGRADE > TRANSFORMATION > BERSERK > COOLDOWN > CHARGING > EXPLORATION
```

Only the highest-priority request is executed; lower-priority requests are rejected.

```gdscript
var _pending_requests: Array[State] = []

func _process(_delta: float) -> void:
    if _pending_requests.is_empty():
        return
    # Sort by priority (DEATH highest, EXPLORATION lowest)
    _pending_requests.sort_custom(func(a, b): return _state_priority(a) > _state_priority(b))
    var winner := _pending_requests[0]
    _pending_requests.clear()
    request_transition(winner)

func _state_priority(state: State) -> int:
    const PRIORITY := {
        State.DEATH: 8,
        State.BOSS: 7,
        State.UPGRADE: 6,
        State.TRANSFORMATION: 5,
        State.BERSERK: 4,
        State.COOLDOWN: 3,
        State.CHARGING: 2,
        State.EXPLORATION: 1,
    }
    return PRIORITY.get(state, 0)

func request_transition_queued(target: State) -> void:
    _pending_requests.append(target)
```

### Force Transition (Escape Hatch)

One exception to the transition matrix: `force_transition()` for emergency cases (e.g., critical error recovery, debug commands). This skips validation:

```gdscript
func force_transition(target: State) -> void:
    push_warning("[GSM] Force transition: %s → %s" % [_current_state, target])
    var old_state := _current_state
    _current_state = target
    state_changed.emit(old_state, target)
```

Only used for: debug console, error recovery (e.g., corrupted state detected), and development tools. Never used in normal gameplay flow.

### System Behavior Per State

| State | Player Movement | Combat Actions | Enemies Active | BGM | Time Scale | Meter Fill |
|-------|----------------|----------------|----------------|-----|------------|------------|
| EXPLORATION | ✓ | ✓ (Human) | ✓ | Ambient | 1.0 | ✓ (starts charging) |
| CHARGING | ✓ | ✓ (Human) | ✓ | Layered BGM (meter-driven) | 1.0 | ✓ (2.0× multiplier) |
| TRANSFORMATION | ✓ | ✓ (Form) | ✓ (frozen/despawned) | BGM Full + Transform Overlay | 1.0 | ✗ (blocked) |
| BERSERK | ✓ | ✓ (Form × multiplier) | ✓ (frozen/despawned) | BGM Full + Berserk Overlay | 1.0 | ✗ (blocked) |
| COOLDOWN | ✓ | ✓ (Human) | ✓ | BGM Ambient | 1.0 | ✓ (0.1× multiplier) |
| UPGRADE | ✗ | ✗ | ✗ | BGM muted | 0.0 | ✗ (frozen) |
| BOSS | ✓ | ✓ (Human) | ✓ (Boss only) | Boss BGM | 1.0 | ✓ |
| DEATH | ✗ | ✗ | ✗ | Death jingle → silence | 0.0 | ✗ (blocked) |

### Architecture Diagram

```
                        GSM (Autoload #2)
                    ┌──────────────────────────┐
                    │  State Machine           │
                    │                          │
    request_       │  Transition Matrix       │   state_changed
    transition() ──▶  (8×8 validation)        ────▶ signal to all
                    │                          │    11 systems
                    │  current_state           │
                    │  (read-only enum)       │◀── queried by
                    │                          │    any system
                    │  Priority Resolution     │
                    │  (DEATH > ... > EXPL)    │
                    │                          │
                    │  force_transition()      │
                    │  (debug escape)          │
                    └──────────────────────────┘
                              │
                              │ set_blocked_actions(state)
                              ▼
                        InputSystem
                    (blocks inputs per state)
```

### State-Specific Rules Delegated to Systems

GSM owns the state definition and transition rules. **Per-state behavior rules are owned by each system**, not by GSM:

| System | State-Dependent Behavior | How It Knows |
|--------|------------------------|-------------|
| InputSystem | Block attack/transform during COOLDOWN/UPGRADE/DEATH | GSM calls `InputSystem.set_blocked_actions(state)` |
| VFX | Transform tear in TRANSFORMATION, death dissolve in DEATH, berserk flash in BERSERK | Connects to `GSM.state_changed` |
| Audio | BGM layer switching, death jingle, upgrade mute, boss BGM | Connects to `GSM.state_changed` |
| HUD | Show/hide HP bar, form meter, upgrade screen, death screen per state | Connects to `GSM.state_changed` |
| EnemySystem | Spawn during EXPLORATION/CHARGING/COOLDOWN, freeze during DEATH/UPGRADE | Connects to `GSM.state_changed` |
| PlayerSystem | Enable input during EXPLORATION/CHARGING/COOLDOWN, form stats during TRANSFORMATION/BERSERK | Reads `GSM.current_state` |
| WaveSystem | Advance waves during EXPLORATION/CHARGING/COOLDOWN | Connects to `GSM.state_changed` |
| AbsorptionSystem | Fill meter in EXPLORATION/CHARGING, blocked in TRANSFORMATION/BERSERK/DEATH/UPGRADE | Reads `GSM.current_state` |

### Rationale for Centralized Transition Matrix (Not Distributed Validation)

- **Distributed** (each system validates): System A allows CHARGING→TRANSFORMATION, System B rejects it → inconsistent state. "Why did the transform animation play but stats didn't change?"
- **Centralized** (GSM validates): One source of truth. The transition either happens for all systems or none. Atomic.
- **Solo dev reality**: The transition matrix fits in one `match` statement (8 states, ~30 lines). Distributed validation would scatter equivalent logic across 8+ systems — harder to audit, easier to get wrong.

## Alternatives Considered

### Alternative 1: String-based states with dynamic transitions

- **Description**: States are strings (`"charging"`, `"cooldown"`). Any state can transition to any other state. Systems validate transitions themselves.
- **Pros**: Maximum flexibility — no enum to update when adding states. Easy to add ad-hoc states for prototyping.
- **Cons**: String typo = silent state mismatch (`"charging"` ≠ `"Charging"` ≠ `"CHARGING"`). No compile-time checking. Any→any transitions create edge cases like DEATH→TRANSFORMATION (how did a dead player transform?). Hard to audit the complete transition graph.
- **Rejection Reason**: Enum-based states with explicit transition matrix catch errors at compile time. String-based states push errors to runtime — unacceptable for the central orchestration point of the entire game.

### Alternative 2: Hierarchical State Machine (HSM) with sub-states

- **Description**: States contain sub-states. TRANSFORMATION contains sub-states: ENTER, ACTIVE, EXIT. CHARGING contains sub-states: BUILDING, FULL.
- **Pros**: Finer-grained control — ACTIVE sub-state handles per-frame form logic; ENTER handles one-time initialization.
- **Cons**: More complexity — sub-state transitions, inheritance rules, entry/exit chains. GDScript has no built-in HSM library — would be custom-built.
- **Rejection Reason**: 8 flat states with clear, distinct behavior differences don't justify HSM complexity. Form-specific logic (Beast vs Dragon) is handled by TransformationSystem, not by GSM sub-states. If sub-state count exceeds 3 within a single parent state, reconsider HSM in Vertical Slice.

### Alternative 3: Godot AnimationTree-based state machine

- **Description**: Use Godot's `AnimationTree` node with a `AnimationNodeStateMachinePlayback` to manage game states visually.
- **Pros**: Visual editor for state machine — drag-and-drop states and transitions. Built-in cross-fade and transition blending.
- **Cons**: Designed for animation blending, not game logic. No enum type safety. Transition conditions are string-based expressions. Overhead of AnimationTree node for a logic-only state machine. Mixes presentation (animation) with logic (state management).
- **Rejection Reason**: AnimationTree is for visual state machines (character animations). Using it for game logic state management conflates two concerns and limits code flexibility.

## Consequences

### Positive

- **Auditable transition graph**: The `_is_valid_transition()` match statement is the complete, documented transition map. A grep for `request_transition` finds every place in the codebase that can change game state.
- **Atomic transitions**: `_transition_in_progress` flag prevents re-entrant transitions. A rapid double-press of transform + upgrade results in exactly one transition (whichever arrives first).
- **Single source of truth**: `GSM.current_state` is authoritative. No system can be in a different state than any other system.
- **Compile-time state validation**: `State.TRANSFORMATION` is an enum — typos are parse errors, not runtime bugs.
- **Input blocking is automatic**: Systems don't check GSM state before processing input. GSM calls InputSystem on transition. Input is blocked at the source.
- **Priority resolution**: Same-frame conflicting requests (e.g., player dies and presses upgrade simultaneously) resolve deterministically — DEATH always wins.

### Negative

- **Flat state model**: Form-specific behavior (Beast vs Dragon attack patterns) is handled by TransformationSystem, not by GSM sub-states. Systems needing form-specific behavior must query `TransformationSystem.active_form_id`. **Accepted cost**: Forms are gameplay modifiers, not full game states. Form-specific logic belongs to TransformationSystem.
- **Transition matrix is exhaustive**: Adding a state requires updating the matrix (8×8 → 9×9). **Accepted cost**: States are GDD-defined and change rarely. The matrix is ~30 lines — updating it is trivial and forces the designer to think about every valid transition from the new state.

### Risks

- **Risk: Re-entrant transition from signal handler**: A system's `_on_state_changed` handler calls `GSM.request_transition()` — creating a nested transition. **Mitigation**: `_transition_in_progress` flag rejects nested requests. The warning log makes this visible in development.
- **Risk: Time scale 0 prevents _process() but _input() still fires**: At `Engine.time_scale = 0.0` (UPGRADE, DEATH), `_process()` stops but `_input()` still fires. **Mitigation**: InputSystem's buffered action check is in `_process()` (stops at time_scale 0), but `_input()` device detection continues running. Upgrade menu navigation uses `Input.is_action_just_pressed()` which works via `_input()` — unaffected by time scale.
- **Risk: Death during TRANSFORMATION creates unexpected state chain**: CHARGING → TRANSFORMATION → DEATH in rapid succession means systems see CHARGING→TRANSFORMATION then TRANSFORMATION→DEATH. Audio must handle: BGM full + transform overlay cut short by death jingle. **Mitigation**: The `state_changed` signal carries both `old_state` and `new_state` — Audio can check if old_state was TRANSFORMATION and skip the transform audio overlay.
- **Risk: BERSERK nested within TRANSFORMATION**: Both states share similar behavior (form abilities active) but BERSERK has enhanced stats. Systems must handle both states identically for core behavior but differentiate for stat multipliers. **Mitigation**: PlayerSystem checks `GSM.current_state in [TRANSFORMATION, BERSERK]` for form abilities, and separately checks `TransformationSystem.is_berserk` for stat multipliers.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-state-manager.md | 8 states: EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, UPGRADE, BOSS, DEATH | Full enum with all 8 states |
| game-state-manager.md | Transition validation — only valid transitions accepted | `_is_valid_transition()` with explicit 8×8 match matrix |
| game-state-manager.md | Priority system: DEATH > BOSS > UPGRADE > TRANSFORMATION > BERSERK > COOLDOWN > CHARGING > EXPLORATION | `_state_priority()` + `request_transition_queued()` for same-frame resolution |
| game-state-manager.md | GSM exposes `state_changed` signal + `current_state` read-only + `request_transition()` | All three implemented in GSM Autoload with typed enum states |
| game-state-manager.md | CHARGING meter decay → EXPLORATION when meter reaches 0 | Transition rule: CHARGING → EXPLORATION valid |
| game-state-manager.md | BERSERK triggered by meter filling during TRANSFORMATION | Transition rule: TRANSFORMATION → BERSERK valid |
| game-state-manager.md | UPGRADE pauses game (time_scale = 0) | `_enter_state(UPGRADE)` sets `Engine.time_scale = 0.0` |
| game-state-manager.md | `set_block()` mechanism for blocking transitions | Block flag check in `request_transition()` |
| game-state-manager.md | GSM.reset() for run restart | `force_transition(EXPLORATION)` via reset |
| vfx-system.md | Rule 1: Subscribes to GSM state_changed | `state_changed` signal carries old and new state |
| audio-system.md | Rule 1: Subscribes to GSM state_changed | Audio reacts to each state transition with appropriate BGM/SFX |
| hud-ui-system.md | Rule 1: Reads GSM.current_state | HUD shows/hides UI sections per state |
| input-system.md | State-based input blocking | GSM calls `InputSystem.set_blocked_actions(state)` in `_execute_transition()` |
| player-system.md | Movement/combat enabled per state | PlayerSystem reads `GSM.current_state` |
| enemy-system.md | Enemy spawning/behavior per state | EnemySystem connects to `state_changed` |
| wave-system.md | Wave progression only during non-paused states | WaveSystem checks `GSM.current_state` |
| transformation-system.md | Transitions to TRANSFORMATION state | Calls `GSM.request_transition(State.TRANSFORMATION)` |

## Performance Implications

- **CPU**: State transition is O(1) — one match statement + one signal emit. `current_state` read is a variable access. Zero per-frame cost.
- **Memory**: One enum variable (4 bytes). Signal connections to `state_changed` are per-system (max 11 connections). Negligible.
- **Load Time**: Enum definition is compile-time. Zero load time impact.

## Migration Plan

N/A — GSM is created fresh. No existing state machine to migrate.

## Validation Criteria

- `GSM.request_transition(State.CHARGING)` from EXPLORATION returns `true` and emits `state_changed(EXPLORATION, CHARGING)`
- `GSM.request_transition(State.TRANSFORMATION)` from EXPLORATION returns `false` — invalid transition (must go through CHARGING)
- `GSM.request_transition(State.COOLDOWN)` from TRANSFORMATION returns `true` — normal transformation expiry
- `GSM.request_transition(State.BERSERK)` from TRANSFORMATION returns `true` — meter-filled berserk activation
- Rapid sequential calls: `request_transition(TRANSFORMATION)` followed by `request_transition(UPGRADE)` in the same frame — only the first succeeds (TRANSFORMATION→UPGRADE is invalid)
- During CHARGING: pressing Escape → `request_transition(UPGRADE)` → `Engine.time_scale = 0.0` → game freezes
- During UPGRADE: closing menu → `request_transition(CHARGING)` → `Engine.time_scale = 1.0` → game resumes
- Priority: simultaneous DEATH + UPGRADE requests → DEATH wins
- `GSM.current_state` returns the correct state at any point — no system reads a stale state
- All 11 downstream systems receive `state_changed` signal within the same frame as the transition

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — GSM is Autoload #2, Foundation layer
- ADR-0004: Signal Bus Pattern — `state_changed` follows past-tense naming, typed enum payload
- ADR-0006: Input System Architecture — GSM calls `InputSystem.set_blocked_actions()` on each transition
- ADR-0008: Absorption System Architecture — meter fill gated by GSM state (only during EXPLORATION/CHARGING)
- ADR-0009: Transformation System Architecture — requests GSM transition to TRANSFORMATION/BERSERK
