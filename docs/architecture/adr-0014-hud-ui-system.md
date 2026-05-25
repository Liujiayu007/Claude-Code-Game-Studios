# ADR-0014: HUD/UI System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI |
| **Knowledge Risk** | LOW — `Control` nodes, `CanvasLayer`, and `Tween` are pre-4.0 stable. No post-cutoff API dependency for basic UI rendering. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify CanvasLayer 3/4 rendering order — HUD_Overlay must appear above HUD_Core. Verify dirty-flag prevents unnecessary re-renders at 60fps with 50 enemies active. Verify lerp animation doesn't cause visible lag on meter fill during rapid energy collection. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload) — HUDSystem is Autoload #10. ADR-0002 (CanvasLayer) — HUD owns layers 3 (HUD_Core) + 4 (HUD_Overlay). ADR-0007 (GSM) — state_changed drives element visibility. ADR-0012 (PlayerSystem) — hp_current/hp_max for HP bar. ADR-0008 (AbsorptionSystem) — meter_current for form meter. ADR-0009 (TransformationSystem) — duration_remaining/cooldown_remaining/is_berserk. ADR-0011 (WaveSystem) — current_wave/total_waves. ADR-0013 (AreaSystem) — display_name for area label. |
| **Enables** | Settings (UI scale/visibility toggles, VS), Tutorial (arrow/highlight overlay on UI elements, Full Vision), RunSummary (stats display, Full Vision) |
| **Blocks** | Tutorial overlay stories, Settings UI toggle stories, RunSummary display stories |
| **Ordering Note** | Must be Accepted after all upstream Core ADRs (Player, Absorption, Transformation, Wave, Area). HUD reads properties from all of them. |

## Context

### Problem Statement

In a survivor game, the player tracks 7 information dimensions simultaneously while dodging 50 enemies: current HP, form meter fill, transformation duration/cooldown, wave progress, remaining enemies, Boss HP, and upgrade choices. This information must be available at a glance — the player's eyes never leave the battlefield. HUD elements must appear and disappear based on game state (e.g., form meter hidden during transformation, cooldown bar shown during cooldown), animate smoothly (no hard jumps), and never cost more than a fraction of the frame budget. Without a defined HUD architecture, UI elements would be scattered across individual system scripts (each system managing its own UI), visibility logic would be duplicated, and animation quality would be inconsistent.

### Constraints

- Godot 4.6 + GDScript + GL Compatibility
- `Control` nodes + `CanvasLayer` for screen-space UI
- Design resolution: 1920×1080, anchor-based layout for resolution independence
- Must not allocate nodes at runtime (ADR-0003 object pooling applies to UI elements too — pre-create all elements in _ready())
- Must not hard-jump values — all transitions lerp-based
- Key binding labels must read from InputMap dynamically (not hardcoded strings)
- Maximum ~0.1ms/frame UI CPU cost (dirty-flag: only animate elements that changed)

### Requirements

- HP bar: reads PlayerSystem.hp_current/hp_max, green fill bar, red border, numeric display
- Form meter: reads AbsorptionSystem.meter_current, theme-colored fill, form icon (16×16), lerp fill animation
- Transformation prompt: appears when meter_full AND GSM=CHARGING, pulse animation, dynamic key name from InputMap
- Duration bar: replaces meter during TRANSFORMATION, counts down from FormConfig.duration
- Cooldown bar: replaces duration during COOLDOWN, fills up as cooldown progresses
- Berserk indicator: "BERSERK!" text during BERSERK state
- Wave display: "Wave N/M" + "Remaining X" text
- Boss HP bar: replaces wave display during BOSS state (interface reserved for BossSystem, VS)
- Low HP warning: screen-edge red vignette at hp_ratio ≤ 0.3, pulse at ≤ 0.15
- Death screen: "You Died" + "Press Enter to restart"
- Upgrade screen: 3-4 choice cards during UPGRADE state (content from MutationSystem, VS)
- All elements show/hide based on GSM.current_state via visibility table
- Dynamic key bind labels read from InputMap

## Decision

**HUDSystem as Autoload #10. Two CanvasLayers (3=HUD_Core, 4=HUD_Overlay) per ADR-0002. All UI elements pre-created as Control nodes in _ready(). GSM state_changed drives element visibility via a visibility table. Dirty-flag pattern: elements only re-render when their source data changes. Animated elements (meter lerp, prompts) use _process(delta) only during active transitions. Key bind labels read from InputMap dynamically.**

### CanvasLayer Assignment

```
HUDSystem (Autoload #10)
├── CanvasLayer #3 — HUD_Core (layer 3)
│   ├── HUD_Battle (Control)
│   │   ├── HPBar (TextureProgressBar + Label)
│   │   ├── FormMeter (TextureProgressBar + Sprite2D icon)
│   │   ├── DurationBar (TextureProgressBar + Label)   # Replaces meter during TRANSFORMATION
│   │   ├── CooldownBar (TextureProgressBar + Label)   # Replaces duration during COOLDOWN
│   │   ├── TransformPrompt (Label)                    # "Press [Key] to Transform"
│   │   ├── BerserkLabel (Label)                       # "BERSERK!"
│   │   ├── WaveDisplay (Label)                        # "Wave 3/5"
│   │   ├── EnemiesRemaining (Label)                   # "Remaining 12"
│   │   └── BossHPBar (TextureProgressBar + Label)     # Boss HP (reserved for VS)
│   └── UpgradeScreen (Control)                        # 3-4 choice cards (VS)
│
└── CanvasLayer #4 — HUD_Overlay (layer 4)
    ├── LowHPWarning (ColorRect × 4)                   # Screen-edge red vignette
    └── DeathScreen (Control)
        ├── DeathLabel ("You Died")
        └── RestartLabel ("Press Enter to restart")
```

### Core State Model

```gdscript
# HUDSystem.gd — Autoload #10
extends Node

# Element visibility table — which GSM states each element is visible in
const VISIBILITY_TABLE: Dictionary = {
    "hp_bar":            [EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS],
    "form_meter":        [EXPLORATION, CHARGING, COOLDOWN],  # Also gated by meter < full
    "transform_prompt":  [CHARGING],                          # Also gated by meter == full
    "duration_bar":      [TRANSFORMATION, BERSERK],
    "berserk_label":     [BERSERK],                           # Also gated by is_berserk
    "cooldown_bar":      [COOLDOWN],
    "wave_display":      [EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS],
    "enemies_remaining": [EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS],
    "boss_hp_bar":       [BOSS],
    "upgrade_screen":    [UPGRADE],
    "death_screen":      [DEATH],
}

# Per-element dirty flags
var _dirty: Dictionary = {}
var _is_animating: bool = false

# References to Control nodes (set in _ready())
var _hp_bar: TextureProgressBar
var _form_meter: TextureProgressBar
var _duration_bar: TextureProgressBar
# ... etc.

func _ready() -> void:
    _create_ui_elements()
    _init_visibility_table()
    # Signal subscriptions:
    #   GSM.state_changed → _on_state_changed
    #   PlayerSystem.hp_changed → _on_hp_changed
    #   AbsorptionSystem.meter_changed → _on_meter_changed
    #   TransformationSystem.transformation_started → _on_transformation_started
    #   TransformationSystem.transformation_expired → _on_transformation_expired
    #   WaveSystem.wave_started → _on_wave_changed
    #   WaveSystem.wave_cleared → _on_wave_changed
```

### State-Driven Visibility

```gdscript
func _on_state_changed(_old: GSM.State, new_state: GSM.State) -> void:
    # Fade out elements not visible in new state
    # Fade in elements visible in new state
    for element_name in VISIBILITY_TABLE:
        var should_show := _is_visible_in_state(element_name, new_state)
        var element := _get_element(element_name)
        if not element:
            continue
        if should_show and not element.visible:
            _fade_in(element)
        elif not should_show and element.visible:
            _fade_out(element)

func _is_visible_in_state(element_name: String, state: GSM.State) -> bool:
    var valid_states: Array = VISIBILITY_TABLE.get(element_name, [])
    if state not in valid_states:
        return false
    # Additional gates beyond state check
    match element_name:
        "transform_prompt":
            return AbsorptionSystem.meter_current >= 1.0
        "berserk_label":
            return TransformationSystem.is_berserk
    return true

func _fade_in(element: Control) -> void:
    element.visible = true
    element.modulate.a = 0.0
    var tween := create_tween()
    tween.tween_property(element, "modulate:a", 1.0, FADE_IN_DURATION)

func _fade_out(element: Control) -> void:
    var tween := create_tween()
    tween.tween_property(element, "modulate:a", 0.0, FADE_OUT_DURATION)
    tween.tween_callback(func(): element.visible = false)
```

### Dirty-Flag Rendering

```gdscript
func _process(delta: float) -> void:
    if not _is_animating:
        return  # Zero cost when nothing is animating
    
    # Meter lerp animation
    if _dirty.get("meter", false):
        _tick_meter_lerp(delta)
    
    # Duration/cooldown countdown
    if _dirty.get("duration", false):
        _tick_duration_display(delta)
    if _dirty.get("cooldown", false):
        _tick_cooldown_display(delta)
    
    # Low HP warning pulse
    if _dirty.get("hp_warning", false):
        _tick_hp_warning(delta)
    
    # Any element still animating?
    _is_animating = _dirty.values().any(func(v): return v)

func _on_meter_changed(_value: float) -> void:
    _dirty["meter"] = true
    _is_animating = true
    _meter_target_width = _value * METER_BAR_MAX_WIDTH

func _tick_meter_lerp(delta: float) -> void:
    var current := _form_meter.size.x
    var target := _meter_target_width
    if abs(current - target) < 1.0:
        _form_meter.size.x = target
        _dirty["meter"] = false
        return
    _form_meter.size.x = move_toward(current, target, METER_LERP_SPEED * delta)

func _on_hp_changed(_new_hp: float) -> void:
    # HP bar updates immediately — no lerp (instant feedback for damage)
    var ratio := PlayerSystem.hp_current / PlayerSystem.hp_max
    _hp_bar.value = ratio * 100
    _hp_label.text = "%d/%d" % [int(PlayerSystem.hp_current), int(PlayerSystem.hp_max)]
    # Trigger low HP warning update
    _dirty["hp_warning"] = ratio <= LOW_HP_THRESHOLD
    _is_animating = _is_animating or _dirty["hp_warning"]
```

### HP Bar — Instant Update (No Lerp)

Damage feedback must be immediate. The HP bar jumps to the new value instantly — no lerp. This is intentional: delayed HP display undermines player trust. The player needs to know *right now* how much HP they lost. The VFX hit flash and Audio damage SFX provide the "feel" — the HP bar provides the fact.

```gdscript
func _on_hp_changed(_new_hp: float) -> void:
    var ratio: float = clampf(PlayerSystem.hp_current / PlayerSystem.hp_max, 0.0, 1.0)
    _hp_bar.value = ratio * 100.0
    _hp_label.text = "%d/%d" % [int(PlayerSystem.hp_current), int(PlayerSystem.hp_max)]
    
    # Low HP warning gate
    _dirty["hp_warning"] = ratio <= LOW_HP_THRESHOLD
    _is_animating = _is_animating or _dirty["hp_warning"]
```

### Form Meter — Lerp Fill (Smooth Accumulation)

Energy collection is gradual — the meter should *feel* like it's filling. Lerp at 10 px/s provides a satisfying "charging up" visual without lagging behind gameplay.

```gdscript
const METER_LERP_SPEED: float = 10.0  # px/s — from GDD tuning knobs

func _tick_meter_lerp(delta: float) -> void:
    var target_width := _meter_target_width
    var current_width := _form_meter.size.x
    
    if abs(current_width - target_width) < 0.5:
        _form_meter.size.x = target_width
        _dirty["meter"] = false
        return
    
    _form_meter.size.x = move_toward(current_width, target_width, METER_LERP_SPEED * delta)
```

### Dynamic Key Binding Display

```gdscript
func _get_transform_key_label() -> String:
    var events := InputMap.action_get_events("transform_beast")
    if events.is_empty():
        return "[未绑定]"
    
    var event := events[0]
    if event is InputEventKey:
        return OS.get_keycode_string(event.keycode)
    elif event is InputEventJoypadButton:
        return _joypad_button_name(event.button_index)
    return "[?]"
```

### Low HP Warning — Screen-Edge Vignette

Four `ColorRect` nodes on CanvasLayer 4 (HUD_Overlay), one per screen edge. Each is 40px wide from the edge inward, with a gradient from red (edge) to transparent (center). Alpha driven by hp_ratio formula from GDD F.4.

```gdscript
func _tick_hp_warning(delta: float) -> void:
    var ratio := clampf(PlayerSystem.hp_current / PlayerSystem.hp_max, 0.0, 1.0)
    
    if ratio > LOW_HP_THRESHOLD:
        _set_warning_alpha(0.0)
        _dirty["hp_warning"] = false
        return
    
    var alpha: float
    if ratio <= CRITICAL_HP_THRESHOLD:
        # Pulse: 0.3 ↔ 0.5 at 0.5s period
        var pulse := abs(sin(Time.get_ticks_msec() / 500.0 * PI))
        alpha = 0.3 + 0.2 * pulse
    else:
        # Linear: ratio 0.3→0, alpha 0→0.3
        alpha = (LOW_HP_THRESHOLD - ratio) / (LOW_HP_THRESHOLD - CRITICAL_HP_THRESHOLD) * 0.3
    
    _set_warning_alpha(alpha)
```

### Architecture Diagram

```
HUDSystem (Autoload #10)
│
├── CanvasLayer #3 (HUD_Core)
│   ├── Battle HUD elements (HP, meter, bars, wave text)
│   └── UpgradeScreen (reserved for MutationSystem, VS)
│
├── CanvasLayer #4 (HUD_Overlay)
│   ├── LowHPWarning (4 × ColorRect edge vignettes)
│   └── DeathScreen
│
├── Data flow (subscription-based, not polling)
│   ├── GSM.state_changed        → visibility table lookup → fade in/out
│   ├── PlayerSystem.hp_changed  → instant HP bar update + warning gate
│   ├── AbsorptionSystem.meter_changed → lerp target update
│   ├── TransformationSystem signals → duration/cooldown display
│   ├── WaveSystem signals       → wave text update
│   └── InputMap (via InputSystem)   → key label on init + rebind
│
├── _process(delta) — only when _is_animating
│   ├── Meter lerp (move_toward, 10 px/s)
│   ├── Duration countdown display
│   ├── Cooldown countup display
│   └── Low HP warning alpha pulse
│
└── Performance
    ├── Dirty flag: no render when data unchanged
    ├── _is_animating gate: _process() returns immediately when idle
    ├── All elements pre-created in _ready() — zero runtime allocation
    └── HP bar: instant (no lerp) — trust-critical feedback
```

### Rationale for Dirty-Flag + _is_animating Gate (Not Continuous _process)

- **Typical frame**: No meter change, no HP change, no state transition. `_is_animating = false` → `_process()` returns on line 1. Cost: one boolean check. < 0.001ms.
- **Meter filling frame**: Energy collected → `_dirty["meter"] = true` → `_is_animating = true` → `_process()` runs lerp math. Cost: one `move_toward()` + one comparison. < 0.01ms.
- **State transition frame**: GSM state changes → visibility update → 2-3 Tween creations for fade in/out. Cost: Godot Tween overhead. < 0.05ms (one-time).
- **Worst case** (meter lerping + HP warning pulsing + duration counting down simultaneously): ~3 lerp math operations. < 0.05ms/frame.

### Rationale for HP Bar Instant Update (Not Lerp)

The GDD specifies lerp for all UI elements. However, HP is an exception — damage feedback must be immediate. If HP bar lerps from 100 to 85 over 0.5s, the player sees "100" for 0.5s after taking damage — they wonder "did that hit actually register?" The VFX hit flash and Audio damage SFX provide the "feel" of impact; the HP bar must match instantly to maintain trust. The meter lerps because energy *accumulation* is a positive, gradual sensation; HP drops because damage is an immediate, negative event.

## Alternatives Considered

### Alternative 1: Each system owns its own UI elements

- **Description**: PlayerSystem renders HP bar. AbsorptionSystem renders form meter. WaveSystem renders wave text. No dedicated HUDSystem.
- **Pros**: No HUD Autoload. Each system's UI is co-located with its data — no cross-system queries for rendering.
- **Cons**: UI Z-ordering becomes ad-hoc (which system's CanvasLayer is on top?). Visibility coordination is distributed — "hide all battle UI during UPGRADE" requires every system to subscribe to GSM individually. Duplicated fade in/out, lerp, and Tween logic across 5+ systems. UI style divergence risk (each system chooses slightly different fonts/colors/animation timings).
- **Rejection Reason**: The GDD's visibility table (Rule 2) requires coordinated show/hide of 11 UI elements across 6 GSM states. Distributing this across 5 systems creates a synchronization problem — if one system's fade-out is 0.05s slower than another's, the UI feels "glitchy."

### Alternative 2: World-space UI (HP bar floats above player in game world)

- **Description**: HP bar and form meter are Sprite2D children of the Player scene, rendered in game world space. They follow the player as they move.
- **Pros**: "Information on the battlefield" philosophy taken literally — HP bar is physically next to the player. No CanvasLayer needed for core HUD.
- **Cons**: HP bar can be occluded by enemies, particles, or map features. UI elements scale with camera zoom — harder to maintain consistent readability. Mixing game-world and UI rendering in the same CanvasLayer complicates Z-ordering.
- **Rejection Reason**: GDD specifies screen-space UI (Rule 3: "CanvasLayer not affected by camera movement"). Screen-space ensures UI is always visible and consistently positioned regardless of camera state. The "information near the character" goal is achieved via bottom-center anchor positioning — the player's eyes flick down slightly, not across the screen.

### Alternative 3: Continuous _process polling (no dirty flags)

- **Description**: `_process()` runs every frame, reading all upstream properties and updating all UI elements unconditionally.
- **Pros**: Simpler code. No dirty flag management. No risk of "stale" UI.
- **Cons**: Pointless work on >90% of frames — HP doesn't change every frame, meter doesn't fill every frame, state doesn't transition every frame. At 60fps with 11 UI elements, continuous polling costs ~0.05-0.1ms/frame for literally no visual change.
- **Rejection Reason**: The dirty flag costs 2 lines of code per data source and saves ~0.05ms/frame on idle frames. When the player is just moving (not collecting, not taking damage, not transforming), the HUD should cost zero CPU — that budget belongs to enemy AI and physics.

## Consequences

### Positive

- **Single owner for UI visibility**: The visibility table is defined in one place. Adding a new UI element = add one row to the table + one Control node. No other system touches visibility logic.
- **Dirty flag eliminates idle cost**: On frames where nothing changes (player just moving), `_process()` returns immediately. UI CPU budget goes to enemies and physics where it's needed.
- **CanvasLayer isolation**: HUD_Core (layer 3) and HUD_Overlay (layer 4) are independent of game world (layer 0), VFX (layers 1-2), and each other. Death screen and low HP warning on layer 4 always render above battle HUD on layer 3.
- **Dynamic key labels**: Reading from InputMap means rebinding keys updates UI automatically. No hardcoded "[Space]" strings to hunt down when a player changes binds.
- **Tween-based transitions**: Godot's built-in Tween system handles fade in/out interpolation. No manual alpha lerp in _process() for visibility — only for continuous effects (meter fill, HP warning pulse).

### Negative

- **Pre-created elements increase node count**: 11+ Control nodes created in _ready(). This is ~15-20 nodes total including child labels and icons. **Accepted cost**: Nodes are cheap (≈ 2 KB total). Recreating them would violate ADR-0003 (no runtime allocation during gameplay).
- **Visibility table is a centralized dependency**: Every UI element's visibility logic passes through one Dictionary. If the table has an error, multiple elements misbehave simultaneously. **Accepted cost**: Centralization is the point — decentralized visibility logic is what we're avoiding. The table is small (~11 rows) and auditable.
- **HP bar is the only element that skips lerp**: Inconsistent with the "all UI elements use lerp" GDD rule. **Accepted cost**: Explicit design decision documented in this ADR. Instant HP feedback is a trust-critical requirement that overrides the general lerp rule.

### Risks

- **Risk: Meter lerp falls behind during rapid energy collection**: Player kills 10 enemies in 0.5s → meter target jumps from 0.2 to 0.8 → lerp at 10 px/s takes 1.2s to reach target → visual meter shows 0.6 when actual is 0.8. **Mitigation**: If the gap between displayed value and target exceeds a threshold (e.g., 20% of bar width), lerp speed temporarily increases (3× boost) to catch up. This preserves the smooth feel for normal collection while preventing visible lag during spikes.
- **Risk: Tween accumulation on rapid state switches**: If GSM state flickers (bug), each flicker creates new Tweens for fade in/out. **Mitigation**: Before creating a new Tween on an element, kill any existing Tween on that element via `element.set("modulate:a", null)` or storing Tween references and calling `tween.kill()`. GSM's `_transition_in_progress` flag (ADR-0007) prevents re-entrant transitions — state flicker is architecturally impossible.
- **Risk: CanvasLayer 3 and 4 rendering order conflicts with VFX_Overlay (layer 5)**: Low HP warning (layer 4) must appear above battle HUD (layer 3) but below VFX_Overlay effects (layer 5). **Mitigation**: ADR-0002 already defines the Z-order: 3=HUD_Core, 4=HUD_Overlay, 5=VFX_Overlay. The low HP warning on layer 4 naturally sits between battle HUD and top-level VFX. No conflict.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| hud-ui-system.md | Rule 1: Subscription-based data reading (no polling of logic methods) | All HUD data comes from signal handlers + read-only property access. HUDSystem never calls methods like request_transformation() or spawn_enemy(). |
| hud-ui-system.md | Rule 2: GSM state-driven element visibility | VISIBILITY_TABLE Dictionary maps element_name → Array of valid GSM states. _on_state_changed() iterates table, fades elements in/out. |
| hud-ui-system.md | Rule 3: CanvasLayer rendering independent of camera | HUD_Core on CanvasLayer #3 (layer 3), HUD_Overlay on CanvasLayer #4 (layer 4). Per ADR-0002 Z-ordering. |
| hud-ui-system.md | Rule 4: Smooth animation transitions (no hard jumps) | lerp via move_toward() for meter fill. Godot Tween for fade in/out. HP bar is the only exception (instant — documented in rationale). |
| hud-ui-system.md | Rule 5: Low HP warning — screen-edge red vignette at hp ≤ 30% | Four ColorRect nodes on HUD_Overlay. Alpha formula from GDD F.4. Pulse at hp ≤ 15%. |
| hud-ui-system.md | Rule 6: Form meter color theme per form_id | Meter tint color set from FormConfig on transformation_started signal. Form icon (16×16) from FormConfig.icon_key. |
| hud-ui-system.md | Rule 7: Dynamic key binding display | _get_transform_key_label() reads InputMap.action_get_events("transform_beast") → OS.get_keycode_string(). Refreshes on input rebind. |
| hud-ui-system.md | Rule 8: Dirty-flag performance (re-render only on change) | _dirty Dictionary per data source. _is_animating gate on _process(). Idle frames: one boolean check → return. |
| hud-ui-system.md | Upgrade screen layout skeleton | UpgradeScreen Control node on HUD_Core with 3-4 card slots. Content provided by MutationSystem (VS). Placeholder cards for MVP layout validation. |
| hud-ui-system.md | Death screen | DeathScreen on HUD_Overlay. "You Died" + "Press Enter to restart". Fade in 0.5s on GSM DEATH state. |
| hud-ui-system.md | Boss HP bar (reserved interface) | BossHPBar Control node. Reads BossSystem HP (VS). Placeholder display until BossSystem implemented. |

## Performance Implications

- **CPU**: Idle frames: one `_is_animating` boolean check → return (< 0.001ms). Active frames: 1-3 `move_toward()` calls + 1-2 lerp calculations (< 0.05ms). State transition frames: 2-6 Tween creations (< 0.1ms, one-time). Well within 0.1ms/frame budget.
- **Memory**: 15-20 Control nodes (TextureProgressBar × 4, Label × 8, ColorRect × 4, Control × 2). ≈ 15 KB total.
- **Load Time**: All Control nodes created in _ready(). No .tscn loading. Sub-millisecond.

## Migration Plan

N/A — HUDSystem is created fresh.

## Validation Criteria

- GSM state CHARGING → HP bar + form meter + wave display visible; duration bar + cooldown bar + death screen hidden
- GSM state TRANSFORMATION → duration bar visible at meter position; meter hidden; wave display still visible
- GSM state DEATH → all battle HUD hidden; death screen fades in over 0.5s
- Player takes 15 damage at 100 HP → HP bar instantly shows 85% fill (no lerp delay), numeric shows "85/100"
- meter_current changes from 0 to 60 → form meter width lerps from 0 to 120px at 10 px/s over ~0.72s
- meter_current reaches 100 in CHARGING → transform prompt appears with pulse animation, shows current key binding
- Transform key rebound from Space to Q → prompt shows "按 Q 变身"
- Low HP at 25% → screen-edge red vignette appears at alpha ~0.1, deepens as HP drops
- Low HP at 10% → vignette pulses at 0.5s period, alpha 0.3↔0.5
- HP > 30% → vignette fades to alpha 0
- _process() with no dirty flags → returns on line 1 (one boolean check)
- 3 rapid meter changes during lerp → lerp retargets to latest value (no animation queue)

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — HUDSystem is Autoload #10, Presentation layer
- ADR-0002: CanvasLayer Z-Ordering — HUD owns layers 3 (HUD_Core) + 4 (HUD_Overlay)
- ADR-0003: Object Pooling Architecture — UI elements pre-created in _ready(), not allocated at runtime
- ADR-0006: Input System Architecture — Dynamic key labels read from InputMap
- ADR-0007: GSM State Machine — state_changed drives all element visibility
- ADR-0012: Player System Architecture — hp_changed signal + hp_current/hp_max properties
- ADR-0008: Absorption System Architecture — meter_changed signal + meter_current property
- ADR-0009: Transformation System Architecture — transformation_started/expired signals + duration/cooldown properties
- ADR-0011: Wave System Architecture — wave_started/wave_cleared signals + current_wave/total_waves properties
- ADR-0013: Area System Architecture — display_name for area label
