# ADR-0006: Input System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Input |
| **Knowledge Risk** | LOW — Godot's Input singleton and Input Map are pre-4.0 stable. `Input.is_action_pressed()` and `Input.get_vector()` have not changed since 4.0. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None — Input Map, `Input` singleton, and `InputEvent` are pre-4.0 stable |
| **Verification Required** | Verify `Input.get_vector()` with negative Y for "up" works correctly with WASD and gamepad left stick in Godot 4.6 (this is a common source of inverted-axis bugs) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — InputSystem is Autoload #3, Foundation layer. ADR-0005 (Data Configuration) — keybindings are DataConfig values. |
| **Enables** | PlayerSystem implementation, HUD implementation (menu navigation), GSM (pause input) |
| **Blocks** | PlayerSystem stories (movement + combat input), HUD stories (menu navigation), GSM stories (pause handling) |
| **Ordering Note** | Must be Accepted before PlayerSystem implementation begins. InputSystem is the first Foundation system that produces data consumed by a Core system. |

## Context

### Problem Statement

Shapeshift Survivor needs to handle three input concerns that are entangled if left to ad-hoc implementation: (1) **Dual input method** — KBM (WASD movement, mouse aim, keyboard actions) and gamepad (left stick, face buttons) must produce the same in-game actions without per-system branching; (2) **Input buffering** — transformation and attack actions need a brief input buffer (~150ms) so the player can press the key slightly before the action becomes available and still have it register (critical for combat feel in a fast-paced survivor game); (3) **Input blocking** — during state transitions (e.g., TRANSFORMATION), certain inputs must be suppressed while others (pause, death screen dismiss) remain active. Without a centralized input system, each of the 12 systems would implement its own input checking, buffering, and blocking — producing inconsistent feel and duplicated edge-case handling.

### Constraints

- Godot 4.6 + GDScript + GL Compatibility renderer
- Target: PC (Steam/Epic) + Web/Browser
- Primary input: Keyboard/Mouse (WASD movement, mouse aim)
- Gamepad: Partial support — all gameplay actions gamepad-mappable, but UX optimized for KBM
- No touch support
- 60 fps target — input polling must not add frame overhead
- Solo developer — input system must be simple enough to configure without a dedicated input designer

### Requirements

- WASD/Arrow keys + gamepad left stick both produce 8-directional movement
- Mouse position accessible for aim-direction calculation
- Transformation actions (Beast, Dragon) have input buffering (press slightly early → action fires when available)
- During TRANSFORMATION state: movement allowed, attack suppressed, form-switch suppressed, pause allowed
- During DEATH state: only "return to menu" and "quit" inputs accepted
- During PAUSE state: only unpause and menu navigation accepted
- Gamepad auto-detection — UI prompts switch between keyboard and gamepad icons
- Input Map configured once in code, not manually in Project Settings (version-controllable)

## Decision

**InputSystem Autoload as configuration + buffering layer. Systems use Godot's `Input` singleton directly for simple continuous input; InputSystem provides action buffering, input blocking, and gamepad detection.**

InputSystem does not wrap every `Input.is_action_pressed()` call. It adds value only where raw `Input` access is insufficient: buffering, state-based blocking, and device detection. Simple movement input goes through `Input` directly — indirection here would add complexity without benefit.

### Architecture Diagram

```
InputSystem (Autoload #3, Foundation)
│
├── _ready(): Configure Input Map
│   ├── movement actions: move_up, move_down, move_left, move_right
│   ├── combat actions: attack, transform_beast, transform_dragon
│   ├── UI actions:     pause, confirm, cancel, navigate_*
│   └── Bindings: KBM keys + Gamepad buttons per action
│
├── Buffering layer
│   ├── _buffer: Dictionary[String, float]  # action → remaining buffer time
│   ├── buffer_action(action, duration)      # start buffering an input
│   ├── is_action_buffered(action) -> bool   # check if buffered press is active
│   └── _process_buffer(delta)               # tick down buffer timers
│
├── Input blocking (GSM-aware)
│   ├── _blocked_actions: Array[String]      # actions blocked in current state
│   ├── set_blocked_actions(state)            # called by GSM on state change
│   └── is_action_allowed(action) -> bool     # check block list + return false
│
└── Device detection
    ├── current_device: enum { KEYBOARD_MOUSE, GAMEPAD }
    ├── device_changed signal
    └── _detect_device(event)                 # last input event type = current device
```

### Key Interfaces

**1. Input Map Configuration (InputSystem._ready):**

```gdscript
# InputSystem.gd — Autoload #3
extends Node

enum Device { KEYBOARD_MOUSE, GAMEPAD }
signal device_changed(new_device: Device)

var current_device: Device = Device.KEYBOARD_MOUSE
var _buffer: Dictionary = {}       # action_name → remaining_seconds
var _blocked_actions: Array[String] = []

func _ready() -> void:
    _configure_input_map()

func _configure_input_map() -> void:
    # Movement — 8-directional via two-axis actions
    # Godot's Input.get_vector() combines these into a normalized Vector2
    _add_action("move_left",  [KEY_A, KEY_LEFT],  [JOY_BUTTON_DPAD_LEFT])
    _add_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT])
    _add_action("move_up",    [KEY_W, KEY_UP],    [JOY_BUTTON_DPAD_UP])
    _add_action("move_down",  [KEY_S, KEY_DOWN],  [JOY_BUTTON_DPAD_DOWN])

    # Combat
    _add_action("attack",           [KEY_J, MOUSE_BUTTON_LEFT], [JOY_BUTTON_X])
    _add_action("transform_beast",  [KEY_1],                    [JOY_BUTTON_A])
    _add_action("transform_dragon", [KEY_2],                    [JOY_BUTTON_B])
    _add_action("berserk",          [KEY_K],                    [JOY_BUTTON_Y])

    # UI
    _add_action("pause",     [KEY_ESCAPE],        [JOY_BUTTON_START])
    _add_action("confirm",   [KEY_ENTER, KEY_SPACE], [JOY_BUTTON_A])
    _add_action("cancel",    [KEY_ESCAPE],        [JOY_BUTTON_B])
    _add_action("ui_up",     [KEY_W, KEY_UP],     [JOY_BUTTON_DPAD_UP])
    _add_action("ui_down",   [KEY_S, KEY_DOWN],   [JOY_BUTTON_DPAD_DOWN])
    _add_action("ui_left",   [KEY_A, KEY_LEFT],   [JOY_BUTTON_DPAD_LEFT])
    _add_action("ui_right",  [KEY_D, KEY_RIGHT],  [JOY_BUTTON_DPAD_RIGHT])

func _add_action(name: String, keys: Array, buttons: Array) -> void:
    if not InputMap.has_action(name):
        InputMap.add_action(name)
    for key in keys:
        var event := InputEventKey.new()
        event.keycode = key
        InputMap.action_add_event(name, event)
    for button in buttons:
        var event := InputEventJoypadButton.new()
        event.button_index = button
        InputMap.action_add_event(name, event)
```

**2. Input Buffering:**

```gdscript
const DEFAULT_BUFFER_WINDOW: float = 0.15  # 150ms

func buffer_action(action: String, duration: float = DEFAULT_BUFFER_WINDOW) -> void:
    _buffer[action] = duration

func is_action_buffered(action: String) -> bool:
    if not is_action_allowed(action):
        return false
    if _buffer.get(action, 0.0) > 0.0:
        _buffer.erase(action)
        return true
    return Input.is_action_just_pressed(action)

func _process(_delta: float) -> void:
    # Tick down buffer timers
    var expired: Array[String] = []
    for action in _buffer:
        _buffer[action] -= _delta
        if _buffer[action] <= 0.0:
            expired.append(action)
    for action in expired:
        _buffer.erase(action)
```

**Usage in PlayerSystem:**
```gdscript
# PlayerSystem queries buffered input for discrete actions:
if InputSystem.is_action_buffered("transform_beast"):
    _request_transform("beast")

# But uses Input directly for continuous movement:
var move_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
```

**3. Input Blocking (GSM-driven):**

```gdscript
# Called by GSM when state changes
func set_blocked_actions(state: GSM.State) -> void:
    match state:
        GSM.State.CHARGING:
            _blocked_actions = []  # all inputs allowed
        GSM.State.TRANSFORMATION:
            _blocked_actions = ["attack", "transform_beast", "transform_dragon"]
        GSM.State.DEATH:
            _blocked_actions = ["move_left", "move_right", "move_up", "move_down",
                              "attack", "transform_beast", "transform_dragon", "berserk"]
        GSM.State.UPGRADE:
            _blocked_actions = ["move_left", "move_right", "move_up", "move_down",
                              "attack", "transform_beast", "transform_dragon", "berserk"]

func is_action_allowed(action: String) -> bool:
    return action not in _blocked_actions
```

**4. Device Detection:**

```gdscript
func _input(event: InputEvent) -> void:
    var new_device := current_device
    if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
        new_device = Device.KEYBOARD_MOUSE
    elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
        new_device = Device.GAMEPAD
    
    if new_device != current_device:
        current_device = new_device
        device_changed.emit(current_device)
```

### Access Pattern Summary

| Input Type | How Systems Access It | Rationale |
|-----------|----------------------|-----------|
| Movement (continuous) | `Input.get_vector("move_left", "move_right", "move_up", "move_down")` | No buffering needed. Godot's `get_vector()` already handles dead zones and normalization. |
| Mouse aim position | `get_viewport().get_mouse_position()` | Direct access — no abstraction benefit. |
| Discrete actions (attack, transform) | `InputSystem.is_action_buffered("attack")` | Buffering improves combat feel. InputSystem adds the buffer window. |
| UI navigation | `Input.is_action_just_pressed("ui_up")` | UI polling is in `_process()`. No buffering needed for menu navigation. |
| Device type | `InputSystem.current_device` | Centralized detection. HUD reads this to show correct button prompts. |

### When to Use InputSystem vs Input Directly

```
Q: Is this a discrete action that benefits from buffering?
  YES → InputSystem.is_action_buffered(action)
  NO  → Q: Is this continuous movement input?
         YES → Input.get_vector("move_left", "move_right", "move_up", "move_down")
         NO  → Input.is_action_pressed(action) or Input.is_action_just_pressed(action)
```

### Rationale for Thin Abstraction (Not Full Wrapper)

- **Movement is a solved problem**: `Input.get_vector()` already handles WASD, arrow keys, and gamepad stick — all normalized to a single Vector2. Wrapping this adds zero value.
- **Buffering is the unique value**: No Godot built-in provides input buffering. This IS the reason InputSystem exists as more than a config file.
- **Full wrappers create busywork**: Every new action would require adding a method to InputSystem (`is_jump_pressed()`, `is_dash_pressed()`...). With direct `Input` access, adding an action = adding it to the Input Map config only.

## Alternatives Considered

### Alternative 1: Full InputSystem wrapper — all input through InputSystem

- **Description**: InputSystem exposes `is_action_pressed()`, `is_action_just_pressed()`, `get_vector()` as pass-through methods. Systems never call `Input` directly.
- **Pros**: Single point of control for all input. Easy to add global input modifiers (slow-mo, input delay).
- **Cons**: Every `Input` method needs a wrapper. Movement polling adds a function call per frame for no benefit. Adding a new action requires both Input Map config AND a new InputSystem method. Violates YAGNI — the global modifiers don't exist in MVP.
- **Rejection Reason**: The wrapper adds indirection without adding value for the 80% of input that is simple movement polling. The 20% that needs buffering is handled by `is_action_buffered()`.

### Alternative 2: No InputSystem — each system configures its own input

- **Description**: PlayerSystem defines its own actions. HUD defines its own actions. Each system calls `Input` independently.
- **Pros**: Zero centralized input code. Maximum independence per system.
- **Cons**: Input Map scattered across multiple files — no single place to see all keybindings. Buffering logic duplicated in every system that needs it. Input blocking requires each system to check GSM state independently. Gamepad detection duplicated.
- **Rejection Reason**: The shared concerns (buffering, blocking, device detection, Input Map configuration) require centralization. Without InputSystem, these 4 concerns are scattered across 4-6 systems with inconsistent implementations.

### Alternative 3: Godot's @export var action names — Editor-configured Input Map

- **Description**: Use Godot's Project Settings → Input Map editor. Export `String` action names on each system for the actions it needs.
- **Pros**: Visual Input Map editor — drag-and-drop key assignment. Standard Godot workflow.
- **Cons**: Input Map is stored in `project.godot` (binary-ish, hard to review in PRs). Adding actions requires opening Project Settings, not writing code. Not version-controllable in a clean diffable way.
- **Rejection Reason**: Code-based Input Map configuration (`InputMap.add_action()` in `_ready()`) is version-controllable, diffable, and keeps all input logic in one file. The Project Settings editor is convenient but opaque to version control.

## Consequences

### Positive

- **Version-controlled keybindings**: Input Map configured in `_configure_input_map()` — adding a keybinding is a code change visible in git diff.
- **Buffering improves combat feel**: 150ms buffer window means "press transform slightly before cooldown ends" registers. This is a standard action game feel technique, now centralized.
- **State-based input blocking**: GSM controls which inputs are active. No system needs to check `GSM.current_state` before processing input — InputSystem blocks at the source.
- **Auto gamepad detection**: HUD reads `InputSystem.current_device` and shows correct button prompts. Switching between KBM and gamepad is seamless.
- **Thin abstraction**: Systems use `Input` directly for the 80% case (movement). InputSystem adds value only for the 20% that needs it.

### Negative

- **Input Map configured in code**: Not editable via Godot's visual Input Map editor. **Accepted cost**: For a solo developer, editing code is faster than navigating Project Settings. The code is self-documenting — each action shows its KBM and gamepad bindings inline.
- **Buffer window is global**: All buffered actions share the same 150ms window. **Accepted cost**: 150ms is a standard action-game buffer. If specific actions need different windows, `buffer_action(action, custom_duration)` supports it — just not used in MVP.
- **InputSystem must know all game actions**: Adding a new gameplay action = editing InputSystem's `_configure_input_map()`. **Accepted cost**: All actions are defined in GDDs before implementation. New actions in Vertical Slice are a conscious addition, not ad-hoc.

### Risks

- **Risk: Input.get_vector() axis inversion**: `get_vector()` with negative Y for "up" is a common bug — if move_up/move_down actions are configured with wrong polarity, movement is inverted. **Mitigation**: Validation Criteria #1 explicitly tests this. Gamepad stick Y-axis is negative-up by convention — the Input Map configuration must match.
- **Risk: Web platform key event conflicts**: Browsers intercept certain keys (Escape, F5, Ctrl+W). **Mitigation**: Godot's HTML5 export captures keys via `canvas` element focus. Known issue — document in platform notes. Pause is also mappable to gamepad Start button.
- **Risk: Buffer window too generous → double-registration**: If the buffer window is too long, a single press could register as two actions. **Mitigation**: `is_action_buffered()` erases the buffer after returning true — one press = one action. The 150ms default is short enough to prevent accidental double-taps.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| input-system.md | Core: WASD + mouse + gamepad unification | InputSystem configures Input Map with both KBM keys and gamepad buttons per action. `Input.get_vector()` unifies movement. |
| input-system.md | Input buffering for transformation/attack actions | `buffer_action()` + `is_action_buffered()` with 150ms default window |
| input-system.md | State-based input blocking | `set_blocked_actions()` called by GSM on state change. `is_action_allowed()` gates all buffered input. |
| input-system.md | Gamepad auto-detection with UI prompt switching | `_input()` detects device type. `device_changed` signal notifies HUD. `current_device` property for polling. |
| game-state-manager.md | Input suppression during transitions | GSM calls `InputSystem.set_blocked_actions(state)` on each state transition |
| player-system.md | Movement: 8-directional WASD + gamepad left stick | `Input.get_vector("move_left", "move_right", "move_up", "move_down")` — normalized Vector2 |
| player-system.md | Attack: mouse left click + keyboard J + gamepad X | All three bound to "attack" action in Input Map |
| hud-ui-system.md | Menu navigation: keyboard arrows + gamepad d-pad | `ui_up/down/left/right` actions with dual KBM+gamepad bindings |
| technical-preferences.md | Platform: PC + Web, KBM primary, Gamepad partial | Input Map config includes both KBM and gamepad bindings for all gameplay actions |

## Performance Implications

- **CPU**: `Input.is_action_pressed()` is O(1) hash lookup in Godot's input state. `_process()` buffer tickdown is O(n) where n = active buffered actions (typically 0-2). Total input processing < 0.01ms/frame.
- **Memory**: `_buffer` Dictionary with max 2-3 entries. `_blocked_actions` Array with max 8 entries. Negligible.
- **Load Time**: `_configure_input_map()` creates ~12 actions × 3 events each = 36 InputEvent objects. Sub-millisecond.

## Migration Plan

N/A — InputSystem is created fresh. No existing input code to migrate.

## Validation Criteria

- WASD and Arrow keys both produce correct 8-directional movement (including diagonals)
- Gamepad left stick produces the same movement Vector2 as WASD (within dead zone tolerance)
- Pressing "transform" key 100ms before cooldown expires → transformation fires when cooldown completes
- During TRANSFORMATION state: attack key ignored, movement keys still work, pause key still works
- During DEATH state: only UI actions (confirm/cancel) accepted — all gameplay input suppressed
- Switching from keyboard to gamepad (press any gamepad button) → `device_changed` signal fires → HUD updates button prompts
- All Input Map actions are configured in code (`InputMap.add_action()`) — zero actions configured manually in Project Settings
- Buffer window: pressing a buffered action and releasing within the window triggers exactly one action (no double-fire)

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — InputSystem is Autoload #3, Foundation layer
- ADR-0004: Signal Bus Pattern — `device_changed` signal follows past-tense naming convention, typed enum payload
- ADR-0005: Data Configuration Architecture — keybinding defaults could migrate to DataConfig for Vertical Slice rebinding
