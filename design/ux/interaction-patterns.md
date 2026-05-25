# Interaction Pattern Library

> **Status**: In Design
> **Author**: 刘嘉寓 + ux-designer
> **Last Updated**: 2026-05-25
> **Template**: Interaction Pattern Library

---

## Overview

The Interaction Pattern Library defines reusable, testable interaction building blocks for Shapeshift Survivor's UI. Every screen, HUD element, and menu references patterns from this library rather than reinventing input handling.

**What a pattern covers**: A pattern specifies the player's physical action (key press, button tap, hold), the platform inputs that trigger it (KBM + gamepad), the immediate feedback (visual, audio), and the outcome (state change, navigation, data mutation). Patterns are input-agnostic — a "Confirm Selection" pattern works identically whether the player presses Enter, clicks, or presses gamepad A.

**Pattern schema**: Each pattern entry includes:
- **Pattern Name** — unique identifier (e.g., `confirm-selection`)
- **Input Mapping** — KBM bindings + gamepad equivalent
- **Feedback** — visual response (color flash, scale pulse), audio cue, haptic (if applicable)
- **Outcome** — what happens in the game
- **GSM State Gating** — which game states this interaction is valid in (if any)
- **Used By** — screens/elements that reference this pattern
- **Edge Cases** — what happens on rapid input, input while transitioning, etc.

**Scope**: This library covers all player→UI interactions. It does NOT cover gameplay input (movement, attacking, transforming) — those belong to the Input System. Patterns are organized by interaction type: Navigation, Selection/Confirmation, Value Adjustment, State Transition, and Notification.

---

## Pattern Catalog

| # | Pattern Name | Category | Description |
|---|-------------|----------|-------------|
| 1 | `menu-cursor-move` | Navigation | Move selection highlight between options (keyboard arrows / gamepad d-pad) |
| 2 | `confirm-selection` | Selection | Confirm current highlighted choice (Enter / Space / gamepad A) |
| 3 | `cancel-back` | Selection | Go back / dismiss / close current screen (Esc / gamepad B) |
| 4 | `upgrade-card-select` | Selection | Navigate 3-4 upgrade cards + confirm one — used in UPGRADE state |
| 5 | `transform-prompt` | State Transition | "Press [key] to transform" — pulse animation when meter full, only in CHARGING |
| 6 | `state-driven-visibility` | State Transition | UI elements fade in/out based on GSM state membership — core HUD pattern |
| 7 | `low-hp-warning` | Notification | Screen-edge red gradient + pulse when HP ≤ 30%, driven by hp_ratio |
| 8 | `bar-fill-lerp` | Value Display | Progress bar smoothly lerps to target value (8-12 px/s), used by HP/meter/duration/cooldown bars |
| 9 | `countdown-display` | Value Display | Numeric countdown (duration remaining / cooldown remaining), updates per-frame during active states |
| 10 | `wave-announcement` | Notification | Wave number + "Wave N/M" text fades in/out at wave start |
| 11 | `boss-warning` | Notification | Boss name + warning text displayed before boss wave |
| 12 | `area-name-display` | Notification | Area name briefly shown (~2s fade in/out) on area entry |
| 13 | `death-screen` | State Transition | Death overlay: "You Died" text + "Press Enter to restart" fade in |
| 14 | `dynamic-key-label` | Input | Display current key binding from InputMap — used by transform prompt and any button prompt |

---

## Patterns

### Pattern 1: `menu-cursor-move`

- **Input Mapping**:
  - KBM: Arrow keys (↑↓←→) or W/A/S/D
  - Gamepad: D-pad or Left Stick
- **Feedback**: Highlighted option changes instantly (no lerp — cursor movement must feel instantaneous). Accompanying audio: low-click UI sfx (~200ms, short tick). Newly highlighted option's border flashes from U8 (定框铁) to U5 (琥珀灯) over 100ms.
- **Outcome**: `cursor_index` changes. The previously highlighted element loses its highlight; the new one gains it.
- **GSM State Gating**: Valid in UPGRADE state. Future: main menu, pause menu, settings.
- **Used By**: Upgrade screen (UPGRADE state). Future: main menu, pause menu, settings screen.
- **Edge Cases**:
  - **Wraparound**: Cursor at first option + press ↑/← → wraps to last option. Cursor at last option + press ↓/→ → wraps to first.
  - **Rapid input**: Each arrow key press moves exactly 1 position. Holding the key does NOT auto-repeat at OS repeat rate — instead, after a 300ms initial delay, the cursor moves at 8 positions/second. This prevents the cursor from "running away" on accidental holds while allowing fast navigation for deliberate holds.
  - **Single-option menu**: If only 1 option exists, cursor is locked — input does nothing.

### Pattern 2: `confirm-selection`

- **Input Mapping**:
  - KBM: Enter, Space, or Left Mouse Click on option
  - Gamepad: A (Xbox) / Cross (PlayStation) / B (Nintendo)
- **Feedback**: Selected option border flashes U5 (琥珀灯) → U1 (骨白) over 150ms, then screen transitions. Audio: confirmation sfx (higher-pitched than cursor move, ~300ms).
- **Outcome**: The highlighted option's action is executed (navigation to another screen, game state change, data write).
- **GSM State Gating**: Same states as the screen using it (e.g., UPGRADE for upgrade cards).
- **Used By**: Upgrade screen, death screen (restart). Future: main menu, pause menu, settings.
- **Edge Cases**:
  - **Double-press guard**: After confirmation, input is ignored for 300ms to prevent accidental double-confirms across screen transitions.
  - **Nothing selected**: If no option is highlighted (should not occur in normal flow), confirm does nothing.

### Pattern 3: `cancel-back`

- **Input Mapping**:
  - KBM: Esc, Backspace, or Right Mouse Click
  - Gamepad: B (Xbox) / Circle (PlayStation) / A (Nintendo)
- **Feedback**: Current screen fades out (0.2s), parent screen fades in (0.15s). Audio: cancel sfx (lower-pitched than confirm, ~200ms).
- **Outcome**: Return to the previous screen/menu. If on the top-level screen (e.g., main menu), Esc does nothing or opens the quit dialog.
- **GSM State Gating**: Same states as the screen using it.
- **Used By**: Upgrade screen (not applicable in MVP — UPGRADE has no "back" action; player must choose). Future: pause menu, settings, any sub-screen.
- **Edge Cases**:
  - **No parent screen**: If there is no screen to go back to, cancel does nothing.
  - **During transition**: Cancel input during a screen transition is ignored (transition lock, 300ms).

### Pattern 4: `upgrade-card-select`

- **Input Mapping**:
  - KBM: Arrow keys / WASD for horizontal navigation between cards, Enter/Space to confirm, also mouse click on a card directly
  - Gamepad: D-pad Left/Right or Left Stick horizontal, A to confirm
- **Feedback**: Cards are arranged horizontally (3-4 cards, 200×280px each, 20px gap). Highlighted card border glows U5 (琥珀灯). Non-highlighted cards have U8 (定框铁) border. On confirm: selected card border flashes U5→U1 (150ms), other cards dim (alpha -30%). Audio: hover tick on card switch, confirm sfx on selection.
- **Outcome**: The chosen mutation is applied. GSM transitions from UPGRADE to next state (CHARGING for next wave). `upgrade_selected(option_index)` signal emitted.
- **GSM State Gating**: Valid only in UPGRADE state. All other states: input ignored.
- **Used By**: Upgrade screen (UPGRADE state).
- **Edge Cases**:
  - **Mouse hover vs keyboard**: Mouse hover sets cursor to the hovered card. If both keyboard and mouse inputs arrive in the same frame, the most recent input wins.
  - **Same-frame confirm + state change**: The confirm is processed, the upgrade is applied, then input is locked until the state transition completes (GSM blocks duplicate transitions).
  - **Only 1 card available**: In edge-case scenarios with only 1 upgrade option, cursor is locked and the single card is auto-highlighted.
  - **Card count < minimum**: If 0 cards (error state), display "No upgrades available" text. This should never occur in normal gameplay.

### Pattern 5: `transform-prompt`

- **Input Mapping**:
  - KBM: Space (default) — key name read dynamically from InputMap action `transform_activate`
  - Gamepad: Right Shoulder / R1 (default) — button name read dynamically from InputMap
- **Feedback**: Text label "Press [key] to transform" appears below the form meter. Pulse animation: scale 1.0 ↔ 1.1, alpha 0.7 ↔ 1.0, period 0.8s, ease-in-out. Text color: current form's theme color from FormConfig (Beast=橙红 `#FF6B35`, Dragon=紫红 `#C44B8B`). Appears via fade-in (0.15s), disappears via fade-out (0.2s).
- **Outcome**: When the player presses the bound key, GSM transitions from CHARGING to TRANSFORMATION (if all activation gates pass — see Transformation System ADR-0009).
- **GSM State Gating**: Visible only in CHARGING state AND `meter_current >= meter_max`. Hidden in all other states. Also hidden if meter drops below max (meter decay while in CHARGING before pressing).
- **Used By**: Battle HUD (CHARGING state).
- **Edge Cases**:
  - **Prompt appears then meter decays below max**: Prompt fades out immediately (0.2s). No "lingering prompt" that suggests an action the player can't take.
  - **Key rebound while prompt is visible**: Prompt text updates next frame to show the new binding. No stale key labels.
  - **Player presses transform key but activation fails**: If GSM rejects the transition (e.g., another transition in progress), prompt stays visible with a brief "shake" micro-animation (2px horizontal displacement, 2 frames, returns to center) to indicate the failed attempt, then resumes normal pulse.
  - **Gamepad disconnected while prompt is visible**: Prompt falls back to showing the KBM binding.

### Pattern 6: `state-driven-visibility`

- **Input Mapping**: N/A — this pattern is purely reactive. It responds to GSM's `state_changed` signal, not player input.
- **Feedback**: When GSM transitions between states, each UI element checks its membership in a predefined visibility set. Elements entering the visible set fade in (0.15s, alpha 0→1.0). Elements leaving the visible set fade out (0.2s, alpha 1.0→0). No hard `visible = true/false` toggling — all transitions use `Tween`.
- **Outcome**: Only the UI elements relevant to the current GSM state are rendered. Hidden elements consume no rendering cost (alpha=0, skipped in `_process`).
- **GSM State Gating**: This IS the gating mechanism. The visibility table from HUD GDD Rule 2 defines membership:

| Element | Visible States |
|---------|---------------|
| HP bar | EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS |
| Form meter | EXPLORATION, CHARGING |
| Transform prompt | CHARGING (with meter_full condition) |
| Duration bar | TRANSFORMATION |
| Berserk label | BERSERK |
| Cooldown bar | COOLDOWN |
| Wave display | EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN |
| Enemies remaining | EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN |
| Boss HP bar | BOSS |
| Upgrade screen | UPGRADE |
| Death screen | DEATH |

- **Used By**: Every HUD element. This is the core visibility pattern for the entire battle HUD.
- **Edge Cases**:
  - **Rapid state transitions (same frame)**: GSM guarantees at most one state transition per frame. If a sequence of transitions occurs across frames (e.g., CHARGING → TRANSFORMATION → BERSERK), the Tween-based fades may be interrupted mid-animation. The rule: a new fade command cancels any in-progress fade on the same element. The element lerps from its current alpha to the new target. No "animation queue" — latest state always wins.
  - **Element depends on data from a not-yet-initialized system**: On first frame before all autoloads are ready, all elements default to hidden (alpha=0). Once GSM emits its first signal (initialization complete), elements snap to correct visibility for the current state (no fade — first paint is instant to avoid showing a flash of wrong-state UI).
  - **UPGRADE to CHARGING transition**: Upgrade screen fades out while battle HUD elements simultaneously fade in. Both tweens run in parallel, not sequentially.

### Pattern 13: `death-screen`

- **Input Mapping**:
  - KBM: Enter or Space to restart. No other input is processed.
  - Gamepad: A (Xbox) / Cross (PlayStation) to restart.
- **Feedback**: Screen-wide sequence:
  1. All battle HUD elements fade out (0.2s)
  2. Full-screen dim overlay fades in (black, alpha 0→0.7, 0.3s) — over the game world which continues to render (enemies stop moving but the last frame is visible)
  3. "You Died" text (red, large pixel font, screen-centered) fades in (0.5s)
  4. After 0.3s delay, "Press Enter to restart" text (white, smaller) fades in (0.3s)
  5. Player character death animation plays in the background during steps 1-4 (pixel disintegration per art bible Section 5.4, Death animation table)
- **Outcome**: On confirm, the game restarts (scene reload or new run initialization). No "return to main menu" in MVP.
- **GSM State Gating**: Valid only in DEATH state. All other states: this pattern is not rendered.
- **Used By**: Death screen (DEATH state).
- **Edge Cases**:
  - **Player presses restart during fade-in**: Input is locked until the full death screen sequence completes (total ~1.4s from death trigger). This prevents accidental instant-restarts that skip the death feedback.
  - **Death triggered during UPGRADE**: GSM priority DEATH > UPGRADE. Upgrade screen fades out abruptly (0.15s fast fade), death screen sequence begins. Upgrade selection is discarded.
  - **Death triggered during TRANSFORMATION**: Transformation is force-ended. Player reverts to human form in the death animation (monster form → human form collapse per art bible death animation spec).
  - **Multiple death triggers**: GSM guarantees DEATH state is terminal — once entered, no further state transitions are accepted. Death screen renders once and ignores duplicate triggers.

### Pattern 8: `bar-fill-lerp`

- **Input Mapping**: N/A — purely data-driven. Reacts to value changes from upstream systems.
- **Feedback**: When the target fill ratio changes (e.g., HP drops from 100 to 85), the bar's displayed width smoothly lerps from the old value to the new value at 10 px/s (configurable via `meter_lerp_speed` tuning knob). The bar fill uses the element's assigned color:
  - HP bar: Green `#5CE06E` (U6 翠醒) when HP > 50%, transitions to amber `#E6C040` (U5) when 30-50%, transitions to red `#FF4444` (U3 警示赤) when <30%
  - Form meter: Current form's theme color (Beast=橙红, Dragon=紫红)
  - Duration bar: Current form's theme color, filling decreases (right→left)
  - Cooldown bar: Gray `#6B6B7A` (U4 冷钢), filling increases (left→right)
- **Outcome**: The bar's visual width in pixels = `clamp(current_display_value / max_value, 0.0, 1.0) * bar_max_width`. The displayed value lerps independently of the actual value — the actual value updates instantly, the display catches up visually.
- **GSM State Gating**: Each bar is only rendered in its defined visible states (see Pattern 6 visibility table).
- **Used By**: HP bar, form meter, duration bar, cooldown bar, boss HP bar.
- **Edge Cases**:
  - **Target changes mid-lerp**: The current lerp is cancelled and a new lerp begins from the current displayed position to the new target. No "animation queue" — the bar always moves toward the most recent target value.
  - **Value jumps to 0 (e.g., HP 100→0 in one frame)**: The bar lerps from 100% to 0% over the full lerp duration. This means the bar will still be animating downward when the death screen appears — this is intentional. The death screen overlay (alpha 0.7) covers the bar, and the bar's fade-out (0.2s per pattern 6) hides it. The lerp does not need to complete before the bar is hidden.
  - **Bar max_width is 0 (config error)**: Bar renders at 0 width. Console warning logged. No crash.
  - **Negative values (should not occur)**: Clamped to 0.0 by the fill ratio formula.

### Pattern 9: `countdown-display`

- **Input Mapping**: N/A — data-driven, updates per-frame from upstream system properties.
- **Feedback**: Numeric text displays remaining seconds with one decimal place (e.g., "5.0s", "0.5s"). The text uses a monospace pixel font (3px wide × 5px high digits per art bible low-resolution rules). Updates every frame during active states.
  - **Duration countdown** (TRANSFORMATION): Text color = current form theme color. Numbers count down: "8.0s" → "7.9s" → ... → "0.0s".
  - **Cooldown countdown** (COOLDOWN): Text color = gray U4 (冷钢). Numbers count down: "15.0s" → "14.9s" → ... → "0.0s".
  - **Last 3 seconds**: Text color shifts to amber U5 (琥珀灯) for both duration and cooldown — "time is almost up" signal.
  - **Last 1 second**: Text color shifts to red U3 (警示赤) + text does a single 1.05x scale pop on each whole-second boundary.
- **Outcome**: Pure information display. The countdown reaching 0.0s does NOT trigger any game logic — that's the Transformation System's responsibility. The display just reflects the value.
- **GSM State Gating**: Duration countdown visible only in TRANSFORMATION, BERSERK. Cooldown countdown visible only in COOLDOWN.
- **Used By**: Duration bar (TRANSFORMATION, BERSERK), cooldown bar (COOLDOWN).
- **Edge Cases**:
  - **Duration/cooldown is 0 (config error)**: Display shows "0.0s". Console warning. No crash.
  - **Timer jumps backward (e.g., mutation extends duration mid-form)**: The display simply reflects the new value next frame. No interpolation needed for numeric text — just show the latest value.
  - **Frame drop causes value to skip decimals**: The display always shows the current value. If a frame is dropped and the timer jumps from 5.2s to 4.8s, the player sees "4.8s" — this is acceptable and imperceptible at 60fps.
  - **BERSERK state extends duration mid-countdown**: Duration countdown continues, but `berserk_multiplier` makes the displayed value decrease at a different effective rate. The display doesn't know about the multiplier — it just shows `duration_remaining` from the Transformation System.

### Pattern 7: `low-hp-warning`

- **Input Mapping**: N/A — data-driven. Reacts to `hp_current / hp_max` ratio from Player System.
- **Feedback**: Screen-edge red gradient overlay rendered on its own CanvasLayer (below HUD layer, above game world). The gradient extends 40px inward from all four screen edges, fading from red `#FF4444` (U3 警示赤) at the edge to fully transparent at 40px in.
  - **HP 30%-15%**: Alpha linearly increases from 0 at 30% HP to 0.3 at 15% HP (formula: `warning_alpha = (0.3 - hp_ratio) / 0.15 * 0.3`).
  - **HP < 15%**: Pulse mode — alpha oscillates between 0.3 and 0.5, period 0.5s (formula: `0.3 + 0.2 * abs(sin(time / 500ms * PI))`).
  - **HP > 30%**: Gradient fades out (alpha lerp to 0 over 0.5s).
- **Outcome**: Player receives an instinct-level warning that doesn't require reading numbers. The red at screen edges is visible in peripheral vision. No audio cue (the low-HP sound is handled by the Audio System independently).
- **GSM State Gating**: Active in EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS. Hidden in UPGRADE, DEATH.
- **Used By**: Battle HUD (low HP state).
- **Edge Cases**:
  - **HP jumps from above 30% to below 15% in one hit**: Warning alpha snaps to the correct pulse range value for the current hp_ratio (no lerp from 0 — instant onset). The player took a massive hit; the warning should be immediate.
  - **HP restored above 30% (healing pickup)**: Warning fades out over 0.5s. Smooth exit — no jarring cut.
  - **Overlaps with VFX system's screen flash (e.g., transformation flash)**: The warning CanvasLayer is below the VFX flash layer. A transformation flash will temporarily wash out the warning — this is acceptable (the flash is ~1s total, and the player's attention should be on the transformation, not HP).
  - **Warning alpha + upgrade overlay alpha stack**: Upgrade overlay (alpha 0.6) renders above the warning. The stacked alpha may make the screen edges very dark. Acceptable — the player is safe during UPGRADE (time_scale=0).

### Pattern 10: `wave-announcement`

- **Input Mapping**: N/A — triggered by Wave System's `wave_started` signal.
- **Feedback**: Text "Wave [N]/[Total]" appears at screen top-center. White (U1 骨白), 16px pixel font. Sequence: fade in (0.3s) → hold (1.5s) → fade out (0.3s). Total display duration: ~2.1s. Does not interrupt gameplay — the wave has already started spawning.
- **Outcome**: Pure information. The player knows which wave they're on and how many remain.
- **GSM State Gating**: Renders in EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN (the states where wave display is visible per Pattern 6).
- **Used By**: Wave display in battle HUD.
- **Edge Cases**:
  - **Wave cleared during announcement hold**: Announcement continues its fade-out sequence. The next wave's announcement starts after the current one finishes its hold + fade.
  - **Player enters UPGRADE during announcement**: Announcement fades out immediately (0.15s fast fade) — UPGRADE screen takes priority.
  - **Boss wave**: Wave count text is replaced by Boss warning (Pattern 11). Boss waves that are also the final wave show only the boss warning, not the wave number.

### Pattern 11: `boss-warning`

- **Input Mapping**: N/A — triggered by Wave System's `boss_wave_started` signal.
- **Feedback**: Two-stage sequence:
  1. "WARNING" text (red U3, large pixel font, screen center) flashes 3 times (on 200ms / off 200ms, total 1.2s). Screen border flashes red in sync.
  2. Boss name text (white U1, slightly smaller, screen top-center) fades in (0.3s) → holds (2.0s) → fades out (0.3s). During this hold, the boss spawns.
- **Outcome**: Player receives a clear "this is different" signal. The flashing red creates urgency distinct from the calm wave announcement pattern.
- **GSM State Gating**: Renders during the state transition into BOSS state. Once in BOSS state, the boss HP bar replaces this display.
- **Used By**: Boss wave start (BOSS state entry).
- **Edge Cases**:
  - **Player is in TRANSFORMATION when boss wave triggers**: Warning displays as normal over the transformation HUD. The warning is more important than momentary state context.
  - **Multiple boss phases (future)**: Each boss phase transition triggers a shorter version — "WARNING" flashes only once (200ms), then the new phase name displays.
  - **Boss name string is empty or missing (config error)**: Displays "???" as boss name. Console warning. Sequence still runs.

### Pattern 12: `area-name-display`

- **Input Mapping**: N/A — triggered by Area System's `area_changed` signal.
- **Feedback**: Area display name text appears at screen top-center (above wave display position). White (U1 骨白), 18px pixel font. Sequence: fade in (0.5s) → hold (2.0s) → fade out (0.5s). Total display duration: ~3.0s. The longer duration (vs wave announcement) reflects that area transitions are rarer and more significant.
- **Outcome**: Player knows they've entered a new area. The name sets environmental expectations (e.g., "风歌草原" = grasslands, "黑瘴森林" = dark forest).
- **GSM State Gating**: Displays during the EXPLORATION or CHARGING state that follows an area transition. Does not display during TRANSFORMATION, BERSERK, COOLDOWN, UPGRADE, DEATH (in those states, the area name is deferred until the next EXPLORATION/CHARGING state).
- **Used By**: Area transition sequences.
- **Edge Cases**:
  - **Area name is very long (e.g., >15 characters)**: Text clips with ellipsis. Max display width = 80% of screen width.
  - **Multiple area transitions in quick succession (should not occur)**: Only the most recent area name is shown. Previous area name display is cancelled.
  - **Area transition during boss fight**: Area name display is deferred until the boss is defeated and the area truly changes (BOSS → EXPLORATION in new area).

### Pattern 14: `dynamic-key-label`

- **Input Mapping**: N/A — reads from Godot's `InputMap` system. Does not handle input; it displays what input to use.
- **Feedback**: Text label containing a dynamic key/button name. The key name is queried from `InputMap.get_action_list(action_name)` — taking the first assigned input event and converting it to a human-readable string:
  - Keyboard keys: `OS.get_keycode_string(event.keycode)` (e.g., "Space", "Q", "Enter")
  - Mouse buttons: "Mouse1", "Mouse2"
  - Gamepad buttons: `Input.get_joy_button_string(event.button_index)` (e.g., "A", "R1")
- **Outcome**: The label always reflects the player's current key binding. If the player rebinds `transform_activate` from Space to Q, the label automatically shows "Q" on the next frame.
- **GSM State Gating**: N/A — this pattern can be used by any UI element in any state that needs to display a key binding. It is most commonly used by `transform-prompt` (Pattern 5) in CHARGING state.
- **Used By**: Transform prompt, any future button prompt (e.g., "Press Enter to restart" on death screen, "Press Esc to pause").
- **Edge Cases**:
  - **Action has no binding**: Displays "???" as the key name. Console warning: "[UI] Action '[action_name]' has no bound inputs."
  - **Action has multiple bindings**: Displays the first binding only. If the player has both Space and gamepad A bound, the label shows the primary KBM binding when last input was keyboard, or the gamepad binding when last input was gamepad (using `InputSystem.last_input_device` from the Input System).
  - **Gamepad disconnected**: Falls back to displaying the KBM binding, regardless of `last_input_device`. Checks `Input.get_connected_joypads().size() > 0` before showing gamepad labels.
  - **Action name doesn't exist in InputMap**: Displays the action name in brackets as fallback: "[transform_activate]". Console error logged. This should never occur for defined actions.
  - **Localization**: Key names are engine-provided and locale-independent (e.g., "Space" is the same in all languages). Gamepad button names vary by platform — use the engine-provided string without modification.

---

## Gaps & Patterns Needed

| # | Pattern | Needed For | Earliest Phase | Notes |
|---|---------|------------|----------------|-------|
| 1 | `main-menu-navigate` | Main menu screen | Pre-Production (when main menu UX spec is authored) | Extends `menu-cursor-move` + `confirm-selection` for the top-level menu. Vertical layout (Start, Settings, Quit). |
| 2 | `slider-adjust` | Settings screen (volume, UI scale) | Vertical Slice | Horizontal bar + draggable handle. KBM: arrow keys or click-drag. Gamepad: d-pad left/right. |
| 3 | `toggle-switch` | Settings screen (fullscreen, mute) | Vertical Slice | Binary on/off toggle. KBM: click or Enter to flip. Gamepad: A to flip. 2-frame animation (no tween — per art bible UI animation rules). |
| 4 | `dropdown-select` | Settings screen (resolution, language) | Vertical Slice | Expandable list of options. KBM: click to open, click option to select. Gamepad: A to open, d-pad to navigate, A to confirm. |
| 5 | `form-selector` | Form selection UI (choosing which form to transform into) | Vertical Slice | 2-3 form icons arranged horizontally. Uses form-specific geometric shapes (arc/triangle/square) as button frames per art bible Section 5.2. |
| 6 | `pause-menu-overlay` | Pause menu (Esc during gameplay) | Vertical Slice | Full-screen dim (alpha 0.6) + vertical menu overlay. GSM may need a PAUSED state or handle via time_scale=0 without a state transition. |
| 7 | `save-confirm-dialog` | Save/load operations | Vertical Slice | Modal dialog: "Overwrite save?" with Confirm/Cancel. Blocks all other input until resolved. |
| 8 | `tutorial-highlight` | Tutorial system (first-time prompts) | Full Vision | Semi-transparent overlay with a cutout "spotlight" on the target UI element + arrow + text. Requires element screen-position queries from HUD. |
| 9 | `run-summary-sequence` | Run summary screen (after death or completion) | Full Vision | Sequential stat reveals: waves cleared → enemies killed → damage dealt → form used → mutations acquired. Each stat animates in one at a time with player confirm to advance. |

---

## Open Questions

| # | Question | Blocking? | Notes |
|---|---------|-----------|-------|
| 1 | Should `menu-cursor-move` use Godot's built-in `ui_up/down/left/right` actions or define custom navigation actions? The Input System GDD defines these as standard UI actions — using them would give us gamepad d-pad support for free via Godot's built-in input map. | No — use built-in `ui_*` actions for MVP | Simplifies implementation. Custom actions only if we need different behavior per screen. |
| 2 | Does the pause menu (gap pattern #6) require a new GSM state? GSM currently has no PAUSED state. The alternative is setting `time_scale = 0` without a state transition, but then UI visibility (Pattern 6) wouldn't know to show the pause overlay. | No — Vertical Slice concern | Decision deferred to Run Manager GDD (#17). If a PAUSED state is added, update the visibility table in Pattern 6. |
| 3 | Should gamepad navigation support both cardinal directions in upgrade card select? Cards are horizontal; up/down could either do nothing or wrap to the same card. | No — left/right only for MVP | Up/down doing nothing is clearer than unexpected wrapping behavior. |
| 4 | What haptic feedback (gamepad rumble) should accompany UI interactions? The art bible and GDDs don't specify haptics. Potential candidates: light rumble on confirm, micro-rumble on cursor move. | No — no haptics for MVP | Haptics are polish-tier. Add to gap patterns if desired during Vertical Slice. |
| 5 | How should UI patterns handle the transition between KBM and gamepad input mid-interaction? The Input System already tracks `last_input_device`. Patterns should query this to decide which button prompts to show (Pattern 14 handles this). | No — handled by Pattern 14 + Input System | If the player is using keyboard and touches the gamepad, prompts switch to gamepad labels on next frame. |
| 6 | Should there be an "input buffer" for the death screen restart? Currently Pattern 13 locks input for 1.4s. Some players may want to restart immediately. | No — lock is intentional | The 1.4s lock prevents accidental skips and lets the death animation play. If playtest feedback says it's too long, reduce to 0.8s. |
| 7 | Touch input is explicitly out of scope per technical-preferences.md, but Web platform may receive touch events from mobile browsers. Should we handle accidental touch input? | No — Web export targets desktop browsers | Mobile browser touch is not a supported use case for MVP. If this changes, add a `touch-input` pattern. |
