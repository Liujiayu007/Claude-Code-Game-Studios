# ADR-0013: Area System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — Pure data management. `Resource` loading and signal subscriptions are pre-4.0 stable. No physics, rendering, or post-cutoff API dependency. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify AreaConfig .tres files load correctly via DataConfig. Verify area_changed signal propagates to VFX (background swap) and Audio (BGM swap) within one frame. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload) — AreaSystem is Autoload #8. ADR-0005 (DataConfig) — AreaConfig Custom Resources. ADR-0007 (GSM) — state change detection. ADR-0011 (WaveSystem) — all_waves_cleared signal for MVP area completion. |
| **Enables** | WaveSystem (enemy_pool query), VFX (background/lighting query), Audio (BGM/ambient query), HUD (area name display), BossSystem (boss_id query, VS) |
| **Blocks** | VFX background swap stories, Audio BGM swap stories, HUD area name display stories |
| **Ordering Note** | Must be Accepted before ADR-0011 (WaveSystem). AreaSystem is Autoload #8 — loaded before WaveSystem (#9) which queries enemy_pool from it. |

## Context

### Problem Statement

Shapeshift Survivor's world is structured as a sequence of distinct areas — each with its own visual theme, enemy roster, Boss, and audio identity. Area data (background keys, lighting colors, enemy pools per wave, BGM tracks) must be available to multiple systems (WaveSystem, VFX, Audio, HUD) without those systems knowing about each other. Area transitions — when a Boss is defeated and the player advances to the next area — must switch all visual/audio/gameplay parameters atomically. Without a defined area architecture, area data would be scattered across WaveSystem (enemy tables), VFX (backgrounds), and Audio (BGM tracks), area transitions would be coordinated ad-hoc by whichever system detects the Boss defeat first, and adding a new area would require touching 4+ systems.

### Constraints

- Godot 4.6 + GDScript
- MVP: single area (Windsong Prairie) — no area transitions during gameplay
- Vertical Slice: 3 areas (Windsong Prairie → Magma Chasm → Frozen Ruins)
- Area transitions triggered by Boss defeat (VS) or final wave clear (MVP → VICTORY)
- Area data must be designer-editable without code changes (Custom Resources)
- Area switching must be atomic — all consumers see the new area in the same frame

### Requirements

- AreaConfig Custom Resource per area: enemy_pool, boss_id, total_waves, background_key, lighting_color, ambient_particle, bgm_track, ambient_sound
- Single active area at any time: `current_area_id: String` + `current_area_config: AreaConfig` (read-only)
- Area transition: validate boss_defeated signal → load next AreaConfig → emit area_changing → update current → emit area_changed
- If next_area_id is null: emit all_areas_cleared (final area completed)
- Enemy pool filtering by unlock_wave: only enemies with unlock_wave <= current_wave are visible to WaveSystem
- All area parameters exposed as read-only properties — no system may mutate AreaConfig at runtime

## Decision

**AreaSystem as Autoload #8. AreaConfig Custom Resources loaded by DataConfig, referenced by AreaSystem. AreaSystem is a pure data provider — read-only properties + transition signals. No per-frame processing. Area transitions are signal-driven: boss_defeated (VS) or all_waves_cleared (MVP) → load next → emit signals.**

### Core State Model

```gdscript
# AreaSystem.gd — Autoload #8
extends Node

signal area_changing(old_id: String, new_id: String)
signal area_changed(new_id: String)
signal area_load_failed(area_id: String, reason: String)
signal all_areas_cleared()

var current_area_id: String = ""
var current_area_config: AreaConfig = null
var total_areas: int = 0

var _area_configs: Dictionary = {}  # area_id → AreaConfig
var _area_order: Array[String] = [] # area_ids in sequence order

func _ready() -> void:
    _load_all_configs()
    _activate_starting_area()
    # Signal subscriptions:
    #   WaveSystem.all_waves_cleared → _on_all_waves_cleared (MVP area completion)
    #   GSM.state_changed → _on_state_changed (VS: detect BOSS state exit)

func _load_all_configs() -> void:
    for config in DataConfig.area_configs:
        _area_configs[config.area_id] = config
    # Sort by area_order for progression sequence
    _area_order = _area_configs.values()
    _area_order.sort_custom(func(a, b): return a.area_order < b.area_order)
    total_areas = _area_order.size()

func _activate_starting_area() -> void:
    var start_id := _area_order[0] if _area_order.size() > 0 else ""
    if start_id.is_empty():
        push_error("[AreaSystem] No area configs found — cannot start game")
        return
    _activate_area(start_id)

func get_enemy_pool_for_wave(wave: int) -> Array:
    if not current_area_config:
        return []
    var filtered: Array = []
    for entry in current_area_config.enemy_pool:
        if entry.unlock_wave <= wave:
            filtered.append(entry)
    return filtered
```

### Area Transition Flow

```
MVP (single area):
  WaveSystem.all_waves_cleared
    → AreaSystem._on_all_waves_cleared()
    → current_area_config.next_area_id == null
    → all_areas_cleared.emit()
    → GSM.request_transition(VICTORY)

Vertical Slice (multi-area):
  BossSystem.boss_defeated(area_id)
    → AreaSystem._on_boss_defeated(area_id)
    → Validate area_id == current_area_id
    → next = current_area_config.next_area_id
    → if next != null:
        area_changing.emit(current_area_id, next)
        _activate_area(next)
        area_changed.emit(next)
    → else:
        all_areas_cleared.emit()
```

### Area Activation

```gdscript
func _activate_area(area_id: String) -> void:
    if area_id == current_area_id:
        return  # Idempotent — already active
    
    var config := _area_configs.get(area_id) as AreaConfig
    if not config:
        push_error("[AreaSystem] AreaConfig not found: %s" % area_id)
        area_load_failed.emit(area_id, "config_missing")
        return
    
    current_area_id = area_id
    current_area_config = config

func _on_all_waves_cleared() -> void:
    if not current_area_config:
        return
    
    var next := current_area_config.next_area_id
    if next and not next.is_empty():
        # Multi-area: advance to next area
        area_changing.emit(current_area_id, next)
        _activate_area(next)
        area_changed.emit(next)
        # WaveSystem restarts wave sequence for new area
    else:
        # Final area completed — victory handled at scene level (not a GSM state)
        all_areas_cleared.emit()

func _on_boss_defeated(area_id: String) -> void:
    if area_id != current_area_id:
        return  # Cross-area validation — ignore signals from other areas
    
    _on_all_waves_cleared()  # Same transition logic
```

### AreaConfig Custom Resource

```gdscript
# AreaConfig.gd — Custom Resource
class_name AreaConfig
extends Resource

@export var area_id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var area_order: int = 1
@export var next_area_id: String = ""  # Empty = final area
@export var enemy_pool: Array[EnemyPoolEntry] = []
@export var boss_id: String = ""
@export var total_waves: int = 5
@export var background_key: String = ""
@export var ground_tile_key: String = ""
@export var lighting_color: Color = Color.WHITE
@export var ambient_particle: String = ""
@export var bgm_track: String = ""
@export var ambient_sound: String = ""

# EnemyPoolEntry.gd — Inner resource for enemy pool entries
class_name EnemyPoolEntry
extends Resource

@export var enemy_type: String = "slime"
@export var weight: int = 50
@export var unlock_wave: int = 1
```

### Architecture Diagram

```
AreaSystem (Autoload #8)
│
├── AreaConfig[0..N] (from DataConfig)
│   └── EnemyPoolEntry[] per area
│
├── Read-only properties
│   ├── current_area_id: String
│   ├── current_area_config: AreaConfig
│   └── total_areas: int
│
├── Query methods
│   └── get_enemy_pool_for_wave(wave: int) → Array[EnemyPoolEntry]
│
├── Area transition (signal-driven)
│   ├── all_waves_cleared (MVP) or boss_defeated (VS)
│   ├── Validate cross-area (area_id == current_area_id)
│   ├── area_changing(old, new) → area_changed(new)
│   └── all_areas_cleared() when final area done
│
└── Consumers
    ├── WaveSystem → enemy_pool + total_waves
    ├── VFX → background_key, lighting_color, ambient_particle
    ├── Audio → bgm_track, ambient_sound
    ├── HUD → display_name
    ├── BossSystem → boss_id (VS)
    └── RunManager → area_order, current_area_id (VS)
```

### Rationale for AreaSystem as Pure Data Provider (Not Spawn Controller)

- **Separation of concerns**: WaveSystem owns spawning. AreaSystem owns "what can spawn here." WaveSystem queries AreaSystem.get_enemy_pool_for_wave() — AreaSystem doesn't know or care how WaveSystem uses the result.
- **No _process()**: AreaSystem has zero per-frame cost. It only activates on signals (boss_defeated, all_waves_cleared). No timers, no polling.
- **Atomic transitions**: When `_activate_area()` runs, all consumers see the new AreaConfig in the same frame. No partial state where VFX has new background but Audio still plays old BGM.

### Rationale for cross-area validation (area_id == current_area_id)

The GDD requires that only a Boss defeated in the *current* area triggers a transition. Without this check, a future scenario with multiple simultaneous Bosses (co-op, or a "summoned boss" power-up) could trigger area transitions from the wrong area. The check is one string comparison — negligible cost, prevents a whole class of bugs.

## Alternatives Considered

### Alternative 1: Area data embedded in DataConfig only — no AreaSystem Autoload

- **Description**: AreaConfig resources are loaded by DataConfig. WaveSystem, VFX, and Audio each read DataConfig.area_configs directly. Area transitions coordinated by GSM state changes.
- **Pros**: One fewer Autoload. Simpler dependency graph. No AreaSystem code to maintain.
- **Cons**: Area transition logic scattered across consumers. Each consumer must independently detect "area changed" and reload its parameters. If VFX reloads but Audio misses the signal, the game has new background + old BGM. No single owner of "what area are we in right now."
- **Rejection Reason**: Area identity is shared state read by 4+ systems. Without a single owner, area transitions become a distributed consensus problem — each consumer must independently detect and react. AreaSystem centralizes "current area" as a single source of truth.

### Alternative 2: AreaSystem directly controls spawning and wave structure

- **Description**: AreaSystem owns the full area lifecycle — it triggers wave starts, spawns enemies, manages inter-wave timing per area.
- **Pros**: Single system owns the full "area experience." Adding an area = one AreaConfig that controls everything.
- **Cons**: Duplicates WaveSystem responsibility. AreaSystem would need spawn timers, intermission timers, wave clear detection — all the same logic as WaveSystem but with area-specific parameters. Creates a hard boundary between areas that complicates cross-area persistence (player buffs, mutation choices).
- **Rejection Reason**: WaveSystem already handles wave progression, spawn timing, and clear detection (ADR-0011). AreaSystem provides the *parameters* for those systems — not the systems themselves.

### Alternative 3: Area transitions via GSM state (EXPLORATION per area)

- **Description**: Each area is a distinct GSM state — EXPLORATION_WINDSONG, EXPLORATION_MAGMA, etc. State transitions handle area switching.
- **Pros**: GSM already handles state transitions atomically. Area switching is "just another transition."
- **Cons**: Explodes the GSM state count (3 areas × 6 states = 18 states). Couples GSM to area count — adding an area means adding new enum values and transition rules. Violates GSM's role as a game-wide state machine, not a per-content state machine.
- **Rejection Reason**: GSM states represent game mode (CHARGING, UPGRADE, DEATH). Areas are content within CHARGING mode. Mixing these concerns creates an N×M state explosion.

## Consequences

### Positive

- **Single source of truth for area identity**: `AreaSystem.current_area_id` and `current_area_config`. All 4+ consumer systems read from one place. No risk of VFX showing area 2 background while WaveSystem spawns area 1 enemies.
- **Data-driven area design**: Adding an area = creating one AreaConfig.tres + adding to DataConfig.area_configs array. Zero code changes. Designer-editable in the Godot inspector.
- **Zero per-frame cost**: AreaSystem has no `_process()`. It only activates on signals. Memory footprint is minimal (N AreaConfig resources × ~500 bytes each + one Dictionary of references).
- **Cross-area validation**: One string comparison (`area_id == current_area_id`) prevents cross-area signal bugs that would be hard to diagnose at runtime.
- **Enemy pool filtering per wave**: `get_enemy_pool_for_wave(wave)` returns only enemies whose `unlock_wave <= wave`. WaveSystem doesn't need to know about unlock mechanics — it just gets the filtered list.
- **MVP-compatible**: The multi-area transition logic is fully implemented but only fires when `next_area_id` is non-null. MVP's single area (next_area_id = null) → all_waves_cleared → VICTORY. Zero wasted code.

### Negative

- **One more Autoload**: AreaSystem is Autoload #8. Adds to the initialization order complexity. **Accepted cost**: AreaSystem is lightweight (no _process, no children, no pools). It loads configs in _ready() and waits for signals.
- **AreaConfig is passive data**: All area parameters must be pre-defined in .tres files. No procedural area generation. **Accepted cost**: The GDD specifies 3 hand-designed areas. Procedural generation is out of scope.
- **Transition logic duplicated for MVP/VS paths**: `_on_all_waves_cleared()` (MVP) and `_on_boss_defeated()` (VS) both call the same `_on_all_waves_cleared()` internal. But the signal sources differ. **Accepted cost**: Two signal handlers, one transition method. Cleaner than trying to unify WaveSystem.all_waves_cleared and BossSystem.boss_defeated into a single signal.

### Risks

- **Risk: AreaConfig.tres file references broken after moving/renaming assets**: If background_key = "bg_windsong_prairie" but the asset is renamed, VFX gets an empty string and the background is black. **Mitigation**: AreaSystem validates all resource keys in `_ready()` — checks that referenced assets exist. Emits `area_load_failed` for any missing keys. Logs all errors at boot, not at transition time.
- **Risk: Area transition triggers while player is in TRANSFORMATION state**: Boss defeated during berserk mode. **Mitigation**: Boss defeat triggers BOSS state (GSM), which blocks transformation input. Transformation expires before BOSS→EXPLORATION transition. If an edge case triggers transition during active transformation: TransformationSystem detects GSM state change and force-ends transformation. AreaSystem doesn't need to handle this — GSM + TransformationSystem cover it.
- **Risk: Final area's all_areas_cleared conflicts with WaveSystem's all_waves_cleared**: Both systems detect "everything done" and both try to transition GSM to VICTORY. **Mitigation**: Only AreaSystem calls `GSM.request_transition(VICTORY)`. WaveSystem's `all_waves_cleared` is consumed by AreaSystem — WaveSystem does NOT directly trigger VICTORY when AreaSystem is active. This is a design contract: if AreaSystem exists, WaveSystem defers end-game to it.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| area-system.md | AreaConfig Resource per area with all parameters | AreaConfig Custom Resource with @export fields for all GDD-defined properties (area_id, enemy_pool, boss_id, total_waves, background_key, lighting_color, etc.) |
| area-system.md | Single active area — current_area_id + current_area_config (read-only) | AreaSystem.current_area_id and current_area_config exposed as read-only properties. _activate_area() is the sole write path. |
| area-system.md | Area transition: Boss defeat → validate → load next → area_changed signal | boss_defeated signal handler with cross-area validation. area_changing → _activate_area() → area_changed signal sequence. Idempotent activation (same-id skip). |
| area-system.md | Enemy pool filtering by unlock_wave | get_enemy_pool_for_wave(wave) returns Array[EnemyPoolEntry] filtered to unlock_wave <= wave. WaveSystem calls this each wave start. |
| area-system.md | MVP: Windsong Prairie only, next_area_id = null → VICTORY | _on_all_waves_cleared() checks next_area_id. If null/empty → all_areas_cleared() → GSM VICTORY. Multi-area logic is implemented but inert for MVP. |
| area-system.md | Cross-area signal validation (area_id must match current_area_id) | _on_boss_defeated() checks area_id == current_area_id before proceeding. One string comparison. |
| area-system.md | Environment parameters exposed to VFX/Audio | current_area_config.background_key, .lighting_color, .ambient_particle (VFX). .bgm_track, .ambient_sound (Audio). |
| wave-system.md | WaveSystem queries area for enemy pool | WaveSystem calls AreaSystem.get_enemy_pool_for_wave(current_wave) to determine spawn composition. |
| vfx-system.md | VFX queries area for background/lighting/particles | VFX subscribes to area_changed → reads current_area_config → applies new background, lighting, particles. |
| audio-system.md | Audio queries area for BGM/ambient | Audio subscribes to area_changed → reads current_area_config → crossfades to new BGM, switches ambient sound. |

## Performance Implications

- **CPU**: Zero per-frame cost. No `_process()`. Signal handlers run only on area transitions (0–2 times per full game session). Each handler: one string comparison + one Dictionary lookup + signal emission. < 0.01ms.
- **Memory**: AreaConfig resources: 1 area (MVP) × ~500 bytes. 3 areas (VS) × ~500 bytes = 1.5 KB. _area_configs Dictionary: 3 entries × ~100 bytes = 300 bytes. Total < 2 KB.
- **Load Time**: AreaConfig .tres files loaded by DataConfig (not AreaSystem). AreaSystem reads references from DataConfig.area_configs array. Zero additional load time.

## Migration Plan

N/A — AreaSystem is created fresh.

## Validation Criteria

- AreaSystem initializes → `current_area_id = "windsong_prairie"` → `current_area_config` is valid AreaConfig with all fields populated
- `get_enemy_pool_for_wave(1)` returns only slime (unlock_wave=1). `get_enemy_pool_for_wave(3)` returns slime + slime_ranged + charger (unlock_wave ≤ 3).
- `get_enemy_pool_for_wave(0)` returns empty array (no enemy unlocks before wave 1)
- `all_waves_cleared` signal received with `next_area_id = null` → `all_areas_cleared()` emitted → GSM transitions to VICTORY
- `boss_defeated("windsong_prairie")` with `next_area_id = "magma_chasm"` → `area_changing` → `current_area_id` updates → `area_changed("magma_chasm")` emitted
- `boss_defeated("magma_chasm")` while `current_area_id = "windsong_prairie"` → signal ignored (cross-area validation)
- `_activate_area("windsong_prairie")` called twice → second call is no-op (idempotent)
- Missing AreaConfig (next_area_id points to nonexistent config) → `area_load_failed` emitted → current_area_id unchanged → game continues
- VFX subscribes to `area_changed` → background and lighting update within one frame of signal emission
- Audio subscribes to `area_changed` → BGM crossfade begins within one frame of signal emission

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — AreaSystem is Autoload #8, Core layer
- ADR-0005: Data Configuration Architecture — AreaConfig Custom Resources in DataConfig.area_configs
- ADR-0007: GSM State Machine — AreaSystem calls GSM.request_transition(VICTORY) on final area completion
- ADR-0011: Wave System Architecture — WaveSystem queries AreaSystem.get_enemy_pool_for_wave() for spawn composition