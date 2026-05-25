# ADR-0011: Wave System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — Pure gameplay logic. Timer-based wave progression uses `_process(delta)`. No post-cutoff API dependency. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify wave transition timing — spawn pause between waves must not block input processing. Verify all_waves_cleared triggers victory screen correctly. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload) — WaveSystem is Autoload #9. ADR-0005 (DataConfig) — WaveTable resources. ADR-0007 (GSM) — BOSS state transition, scene-level victory handling. ADR-0010 (EnemySystem) — spawn_enemy(). |
| **Enables** | VFX (wave announcements, boss warning), Audio (wave start/clear SFX), HUD (wave progress display), EnemySystem (spawn commands) |
| **Blocks** | VFX wave stories, Audio wave stories, HUD wave display stories |
| **Ordering Note** | Must be Accepted after ADR-0010 (EnemySystem). WaveSystem calls EnemySystem.spawn_enemy() for every spawn. |

## Context

### Problem Statement

A survivor game's pacing comes from its wave system. Shapeshift Survivor needs: (1) progressively harder waves — more enemies, tougher types, faster spawns; (2) a brief pause between waves for the player to breathe, collect remaining energy drops, and see their progress; (3) boss waves every N waves with a distinct warning and special enemy; (4) a defined end condition — when all waves are cleared, trigger VICTORY. Without a defined wave architecture, spawn timing would be hardcoded in EnemySystem, wave progression would be opaque (no "Wave 3/10" display possible), and the wave-complete detection ("are all enemies dead?") would be unreliable.

### Constraints

- Godot 4.6 + GDScript
- Open arena — no spawn rooms or spawn points (enemies spawn from arena edges)
- Up to 50 simultaneous enemies (ADR-0010)
- Boss every 5th wave (MVP — configurable)
- 10-15 waves for MVP (configurable via WaveTable)
- Brief pause between waves (~3 seconds)

### Requirements

- Waves defined in DataConfig WaveTable resources (wave number → enemy groups, spawn timing)
- Enemies spawn from arena edges (random position along perimeter)
- Wave completion: all enemies in current wave are dead
- Inter-wave pause: 3s gap with "Wave N Complete" / "Wave N+1 Incoming" announcement
- Boss wave every N waves (boss enemy + minions)
- `wave_started(wave: int)` signal on each wave begin
- `wave_cleared(wave: int)` signal when all enemies in wave are dead
- `boss_wave_started(wave: int)` signal for boss wave warning
- `all_waves_cleared()` signal when final wave is complete

## Decision

**Timer-driven wave sequencer in WaveSystem. Waves defined in WaveTable Custom Resources. Enemies spawned in batches with configurable spawn intervals. Wave completion detected via EnemySystem.get_active_count() poll, not per-enemy-death counting. Boss waves use a special spawn entry in WaveTable.**

### Core State Model

```gdscript
# WaveSystem.gd — Autoload #9
extends Node

enum Phase {
    IDLE,             # Not in combat (MENU, etc.)
    WAVE_ACTIVE,      # Enemies spawning + active
    WAVE_CLEARING,    # All enemies dead, inter-wave pause
    ALL_CLEARED,      # All waves complete
}

signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal boss_wave_started(wave: int)
signal all_waves_cleared()
signal intermission_started(wave_just_cleared: int)
signal intermission_ended(next_wave: int)

var current_wave: int = 0
var total_waves: int = 0
var _phase: Phase = Phase.IDLE
var _wave_tables: Array[WaveTable] = []
var _spawn_queue: Array = []           # Pending spawn groups
var _spawn_timer: float = 0.0          # Time until next spawn batch
var _intermission_timer: float = 0.0   # Time until next wave starts
var _boss_wave_interval: int = 5       # Every Nth wave is a boss wave

func _ready() -> void:
    _wave_tables = DataConfig.wave_tables
    total_waves = _wave_tables.size()
    _boss_wave_interval = DataConfig.boss_wave_interval
    # Signal subscriptions:
    #   GSM.state_changed → _on_state_changed
    #   EnemySystem.enemy_killed → _on_enemy_killed (for wave clear check)
```

### Wave Lifecycle

```
GSM → CHARGING
  → WaveSystem.start_wave_sequence()
      → wave_started(1)
      → spawn wave 1 enemies (batch by batch)

      → [Wave 1 active — enemies fighting]
      → [Last enemy dies]
      → wave_cleared(1)

      → intermission_started(1)
      → [3 second pause]
      → intermission_ended(2)
      → wave_started(2)

      → ... repeat ...

      → wave_cleared(final_wave)
      → all_waves_cleared()
      → GSM.request_transition(CHARGING)  # victory handled at scene level
```

### Wave Start & Spawn

```gdscript
func start_wave_sequence() -> void:
    current_wave = 0
    _phase = Phase.WAVE_ACTIVE
    _advance_to_next_wave()

func _advance_to_next_wave() -> void:
    current_wave += 1
    if current_wave > total_waves:
        _all_waves_complete()
        return
    
    var table := _wave_tables[current_wave - 1]
    
    if _is_boss_wave(current_wave):
        boss_wave_started.emit(current_wave)
    wave_started.emit(current_wave)
    
    # Build spawn queue from wave table
    _spawn_queue = table.spawn_groups.duplicate()  # Array of SpawnGroup
    _spawn_timer = 0.0  # First batch spawns immediately

func _is_boss_wave(wave: int) -> bool:
    return wave % _boss_wave_interval == 0

func _process(delta: float) -> void:
    if _phase != Phase.WAVE_ACTIVE:
        return
    if GSM.current_state != GSM.State.CHARGING:
        return
    
    # Spawn timer
    if _spawn_queue.size() > 0:
        _spawn_timer -= delta
        if _spawn_timer <= 0.0:
            _spawn_next_batch()
    
    # Intermission timer
    if _phase == Phase.WAVE_CLEARING:
        _intermission_timer -= delta
        if _intermission_timer <= 0.0:
            _phase = Phase.WAVE_ACTIVE
            intermission_ended.emit(current_wave + 1)
            _advance_to_next_wave()

func _spawn_next_batch() -> void:
    if _spawn_queue.is_empty():
        return
    
    var group = _spawn_queue.pop_front() as SpawnGroup
    
    for i in group.count:
        var spawn_pos := _get_spawn_position(group.spawn_zone)
        var enemy := EnemySystem.spawn_enemy(group.enemy_type, spawn_pos)
        if enemy == null:
            push_warning("[WaveSystem] Spawn failed — pool exhausted for %s" % group.enemy_type)
            break  # Don't keep trying if pool is empty
    
    # Set timer for next batch
    if _spawn_queue.size() > 0:
        _spawn_timer = group.interval_seconds
```

### Wave Clear Detection

```gdscript
func _on_enemy_killed(_position: Vector2, _enemy_type: String, _energy_value: float) -> void:
    if _phase != Phase.WAVE_ACTIVE:
        return
    if _spawn_queue.size() > 0:
        return  # Still spawning — wave not done yet
    
    # All spawns done + no active enemies = wave cleared
    if EnemySystem.get_active_count() == 0:
        _on_wave_cleared()

func _on_wave_cleared() -> void:
    wave_cleared.emit(current_wave)
    
    if current_wave >= total_waves:
        _all_waves_complete()
    else:
        _phase = Phase.WAVE_CLEARING
        _intermission_timer = DataConfig.intermission_duration  # 3.0s
        intermission_started.emit(current_wave)

func _all_waves_complete() -> void:
    _phase = Phase.ALL_CLEARED
    all_waves_cleared.emit()
    # Victory handled at scene level (not a GSM state). Scene manager listens
    # for all_waves_cleared and triggers victory screen / scene transition.
```

### Spawn Position Strategy

```gdscript
enum SpawnZone { EDGE_RANDOM, EDGE_TOP, EDGE_BOTTOM, EDGE_LEFT, EDGE_RIGHT, CENTER }

func _get_spawn_position(zone: SpawnZone) -> Vector2:
    var viewport_rect := get_viewport().get_visible_rect()
    var margin := 50.0  # Pixels outside viewport edge
    
    match zone:
        SpawnZone.EDGE_RANDOM:
            var edge := randi() % 4
            match edge:
                0: return Vector2(randf_range(0, viewport_rect.size.x), -margin)        # Top
                1: return Vector2(randf_range(0, viewport_rect.size.x), viewport_rect.size.y + margin)  # Bottom
                2: return Vector2(-margin, randf_range(0, viewport_rect.size.y))         # Left
                3: return Vector2(viewport_rect.size.x + margin, randf_range(0, viewport_rect.size.y))  # Right
        SpawnZone.EDGE_TOP:
            return Vector2(randf_range(0, viewport_rect.size.x), -margin)
        SpawnZone.CENTER:
            return viewport_rect.size / 2.0
        # ... other zones
    
    return Vector2.ZERO
```

### WaveTable Custom Resource

```gdscript
# WaveTable.gd — Custom Resource
class_name WaveTable
extends Resource

@export var wave_number: int = 1
@export var spawn_groups: Array[SpawnGroup] = []
@export var is_boss_wave_override: bool = false  # Force boss wave regardless of interval

# SpawnGroup.gd
class_name SpawnGroup
extends Resource

@export var enemy_type: String = "slime"
@export var count: int = 5
@export var spawn_zone: WaveSystem.SpawnZone = WaveSystem.SpawnZone.EDGE_RANDOM
@export var interval_seconds: float = 1.0  # Delay after this batch before next batch
```

### Example WaveTable Data

```gdscript
# Wave 1:  10 slimes, batches of 3 every 1.5s
# Wave 2:  15 slimes + 5 bats, alternating batches
# Wave 5:  Boss (1 brute) + 10 slime minions
# Wave 10: Boss (2 brutes) + 20 slimes + 10 bats
```

### Architecture Diagram

```
WaveSystem (Autoload #9)
│
├── WaveTable[0..N] (from DataConfig)
│   └── SpawnGroup[] per wave
│
├── _process(delta)
│   ├── Spawn timer → _spawn_next_batch() → EnemySystem.spawn_enemy()
│   └── Intermission timer → _advance_to_next_wave()
│
├── Wave clear detection
│   └── EnemySystem.get_active_count() == 0 && spawn queue empty
│
└── Signals
    ├── wave_started(wave)        → HUD, Audio, VFX
    ├── wave_cleared(wave)        → HUD, Audio, VFX
    ├── boss_wave_started(wave)   → VFX (boss warning), Audio (AUD-016/017)
    ├── all_waves_cleared()       → GSM (→ VICTORY), Audio (victory fanfare)
    ├── intermission_started      → HUD ("Wave N Complete!")
    └── intermission_ended        → HUD ("Wave N+1 Incoming!")
```

### Rationale for Polling get_active_count() (Not Per-Death Counting)

- **Simplicity**: `EnemySystem.get_active_count()` is one method call. Per-death counting would require tracking how many enemies the wave spawned and comparing to deaths — fragile if an enemy dies to something other than player damage.
- **Robustness**: If an enemy dies to a bug (falls off map, gets cleaned up), `get_active_count()` still returns the correct number. Per-death counting would be off by one.
- **Self-correction**: `get_active_count() == 0` is rechecked every time any enemy dies. If a bug leaves an enemy in a broken state that doesn't count as "active", the wave still clears.

## Alternatives Considered

### Alternative 1: Timed waves (enemies spawn on a schedule regardless of deaths)

- **Description**: Wave N spawns enemies for T seconds, then wave N+1 starts regardless of kill status.
- **Pros**: Predictable pacing. Player can't "stall" a wave by leaving one enemy alive. Simpler implementation — no clear detection needed.
- **Cons**: Creates overwhelming enemy density if player can't kill fast enough. Punishes slower builds. No "breather" moment after clearing a wave — tension is relentless.
- **Rejection Reason**: GDD specifies "clear all enemies to advance" pacing. The intermission is a deliberate design choice for the player to collect drops and breathe.

### Alternative 2: Continuous spawning (no waves — enemy stream)

- **Description**: Enemies spawn continuously with increasing rate. No wave boundaries. Game ends when player dies — no VICTORY condition.
- **Pros**: Classic survivor game feel (Vampire Survivors). No wave management code. "Endless mode" is the default.
- **Cons**: No victory condition contradicts the GDD (which specifies wave-based progression with a victory condition). No narrative pacing — just increasing enemy density until death.
- **Rejection Reason**: GDD specifies wave-based structure with a victory end condition. The game is designed around discrete waves, not continuous stream.

## Consequences

### Positive

- **Data-driven wave design**: Adding a wave = adding a WaveTable entry in DataConfig. Changing spawn composition (more bats, fewer slimes) = edit SpawnGroups in the inspector. No code changes.
- **Clear phase machine**: `IDLE → WAVE_ACTIVE → WAVE_CLEARING → WAVE_ACTIVE → ... → ALL_CLEARED`. Every phase has exactly one entry and one exit path.
- **Boss waves are data, not code**: Boss wave detection is `wave % interval == 0`. The `is_boss_wave_override` flag on WaveTable lets designers force any wave to be a boss wave. Boss spawns are just SpawnGroups with boss-type enemies.
- **Intermission is a breather**: 3 seconds between waves gives the player time to collect remaining drops and reposition. HUD shows wave transition text during this window.
- **Robust clear detection**: Polling `get_active_count()` self-corrects. No counter drift possible.

### Negative

- **Polling `get_active_count()` on every enemy death**: One method call per death. Trivial overhead (deaths are low-frequency events — maybe 5-10/second at peak).
- **Fixed intermission duration**: 3 seconds is hardcoded (via DataConfig). If all enemies die instantly, the player waits the full 3 seconds. **Accepted cost**: The intermission is intentionally a fixed pause. If tuning shows 3s is too long, it's a DataConfig value.
- **WaveTable is sequential**: Waves must be completed in order. No branching or "choose your next wave" mechanic. **Accepted cost**: Linear progression for MVP. Branching waves are a Vertical Slice feature.

### Risks

- **Risk: `get_active_count()` never reaches 0 due to stuck enemy**: An enemy in ACTIVE state but outside the arena or stuck in geometry. **Mitigation**: A future `_process()` cleanup check — if an enemy has been ACTIVE for > 60 seconds, force-deactivate and log warning. MVP: trust the physics bounds to keep enemies on-screen.
- **Risk: Intermission timer fires during state transition**: Player dies during intermission. **Mitigation**: `_process()` checks `GSM.current_state == CHARGING` before ticking timers. If GSM changes to DEATH mid-intermission, the timer stops. When game restarts, waves reset.
- **Risk: Final wave boss kill + minions still alive triggers victory too early**: `get_active_count() == 0 && spawn queue empty` guards against this — victory only when ALL enemies are dead.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| wave-system.md | Signals: `wave_started`, `wave_cleared`, `boss_wave_started`, `all_waves_cleared` | All 4 signals defined with typed int parameters and correct emit points |
| wave-system.md | Progressive difficulty via WaveTable | WaveTable Custom Resource with SpawnGroup arrays — per-wave enemy composition |
| wave-system.md | Boss wave every N waves | `wave % boss_wave_interval == 0` + `boss_wave_started` signal + VFX boss warning |
| wave-system.md | Inter-wave pause | `WAVE_CLEARING` phase with `DataConfig.intermission_duration` (3s default) |
| wave-system.md | Victory on all waves cleared | `all_waves_cleared()` → scene-level victory screen (not a GSM state) |
| enemy-system.md | WaveSystem drives enemy spawning | `WaveSystem._spawn_next_batch()` → `EnemySystem.spawn_enemy(type, position)` |
| vfx-system.md | Wave announcement VFX + boss warning | VFX subscribes to `wave_started`, `boss_wave_started`, `all_waves_cleared` |
| audio-system.md | Wave start/clear/boss SFX (AUD-014–017) | Audio subscribes to wave signals. Boss wave plays AUD-016+AUD-017 |
| hud-ui-system.md | Wave progress display ("Wave 3/10") | HUD reads `WaveSystem.current_wave` and `WaveSystem.total_waves` or subscribes to `wave_started` |

## Performance Implications

- **CPU**: `_process(delta)` does 2 timer subtractions + 2 comparisons. `_on_enemy_killed()` does `get_active_count()` (O(1) Array.size). Total < 0.01ms/frame.
- **Memory**: WaveTable resources (10-15 waves × ~5 SpawnGroups each) ≈ 5 KB. Spawn queue Array ≈ 200 bytes.
- **Load Time**: WaveTable resources loaded by DataConfig (not WaveSystem). WaveSystem reads references. Zero load time impact.

## Migration Plan

N/A — WaveSystem is created fresh.

## Validation Criteria

- `start_wave_sequence()` from CHARGING state → `wave_started(1)` → enemies spawn in batches per WaveTable
- All enemies in current wave dead + spawn queue empty → `wave_cleared(N)` → 3s intermission → `wave_started(N+1)`
- Wave 5 (boss interval = 5) → `boss_wave_started(5)` emitted before `wave_started(5)`
- Final wave cleared → `all_waves_cleared()` → scene-level victory screen triggered
- `EnemySystem.get_active_count() == 0` during WAVE_ACTIVE with empty spawn queue → wave cleared (not before)
- Spawn batch respects SpawnGroup interval — not all enemies appear at once
- GSM transitions to DEATH mid-wave → WaveSystem stops processing, no more spawns
- WaveTable with `is_boss_wave_override = true` on wave 3 → boss wave triggers at wave 3 regardless of interval

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — WaveSystem is Autoload #9, Core layer
- ADR-0005: Data Configuration Architecture — WaveTable Custom Resources with SpawnGroup arrays
- ADR-0007: GSM State Machine — WaveSystem triggers BOSS state via GSM; victory handled at scene level
- ADR-0010: Enemy System Architecture — WaveSystem calls EnemySystem.spawn_enemy() for all spawns
