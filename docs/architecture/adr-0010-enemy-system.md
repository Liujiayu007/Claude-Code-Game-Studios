# ADR-0010: Enemy System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — `CharacterBody2D`, `Area2D`, and `NavigationAgent2D` are pre-4.0 stable. No post-cutoff API dependency for basic enemy movement and collision. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify enemy count at max wave (MVP cap) — 50 simultaneous enemies seeking the player at 60fps — navigation and physics cost must stay under 2ms/frame |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — EnemySystem is Autoload #5, Core layer. ADR-0005 (DataConfig) — EnemyConfig Custom Resources. ADR-0007 (GSM State Machine) — enemy behavior per state. ADR-0008 (Absorption System) — energy drops feed meter. |
| **Enables** | WaveSystem (spawns enemies), VFX (enemy death particles), Audio (enemy death SFX, proximity warning), PlayerSystem (enemy collision damage) |
| **Blocks** | WaveSystem stories, VFX death particle stories, Audio enemy SFX stories |
| **Ordering Note** | Must be Accepted before WaveSystem implementation — WaveSystem calls EnemySystem to spawn enemies. PlayerSystem must know EnemySystem's collision interface for damage. |

## Context

### Problem Statement

A survivor game's primary challenge is enemy density. Shapeshift Survivor needs enemies that: (1) spawn in increasing numbers per wave; (2) seek the player with simple AI; (3) are of multiple types with different stats (HP, speed, damage, size); (4) drop energy pickups on death; (5) are pooled for performance (up to 50 simultaneous enemies); (6) freeze during TRANSFORMATION and despawn on DEATH/VICTORY states. Without a defined enemy architecture, spawning logic would be scattered between WaveSystem and the scene tree, enemy death drops would be handled per-type with duplicated code, and enemy lifecycle management (activate, deactivate, recycle) would be ad-hoc per type.

### Constraints

- Godot 4.6 + GDScript + GL Compatibility renderer
- Up to 50 simultaneous enemies on screen (MVP performance cap)
- 3-4 enemy types for MVP (Slime, Bat, + possibly 2 more per WaveTable)
- Pixel art — enemy sprites are small (16×16 to 32×32)
- GL Compatibility — no GPU particles for enemy effects; use CpuParticles2D via VFX pool
- Simple seek AI (no pathfinding around obstacles in MVP — open arena)
- Enemy stats from DataConfig EnemyConfig resources (ADR-0005)

### Requirements

- Enemies spawn at wave-defined positions (edge of screen, specific spawn zones)
- Enemies seek the player using simple direction-based movement (not A* pathfinding)
- Enemies deal contact damage to the player (Area2D overlap)
- Enemies have HP and die when HP reaches 0
- On death: emit `enemy_killed(position, enemy_type, energy_value)` signal → VFX plays death particle → EnergyDrop spawned at position
- Enemy behavior branches on GSM.current_state: active in CHARGING, frozen during TRANSFORMATION, despawn all on DEATH/VICTORY
- Enemy types loaded from DataConfig EnemyConfig resources

## Decision

**Scene-based enemies with object pooling via EnemySystem. Each enemy type is a `.tscn` scene instanced into a pool. EnemySystem owns spawn, despawn, and death-drop orchestration. Simple seek AI via direction vector — no NavigationAgent2D for MVP.**

### Enemy Scene Structure

Each enemy type is a `.tscn` scene with this node structure:

```
Enemy_[Type] (CharacterBody2D)
├── Sprite2D                    # Visual
├── CollisionShape2D            # Physics body (circle/rect)
├── HurtArea (Area2D)           # Contact damage to player
│   └── CollisionShape2D
├── HitArea (Area2D)            # Receives player attacks
│   └── CollisionShape2D
└── EnemyController (script)    # AI + lifecycle
```

### EnemyController Base Script

```gdscript
# EnemyController.gd — base script for all enemy types
class_name EnemyController
extends CharacterBody2D

enum State { IDLE, ACTIVE, DYING, DEAD }

signal enemy_died(position: Vector2, enemy_type: String, energy_value: float)

var enemy_type: String = ""
var hp_current: float = 0.0
var hp_max: float = 0.0
var move_speed: float = 0.0
var contact_damage: float = 0.0
var energy_value: float = 0.0
var death_particle_type: String = ""

var _state: State = State.IDLE
var _is_pooled: bool = true  # Managed by EnemySystem pool

func configure(config: EnemyConfig) -> void:
    enemy_type = config.enemy_type
    hp_max = config.hp_max
    hp_current = hp_max
    move_speed = config.move_speed
    contact_damage = config.contact_damage
    energy_value = config.energy_value
    death_particle_type = config.death_particle_type

func activate(spawn_position: Vector2) -> void:
    global_position = spawn_position
    hp_current = hp_max
    _state = State.ACTIVE
    show()
    set_process(true)
    set_physics_process(true)

func deactivate() -> void:
    _state = State.IDLE
    hide()
    set_process(false)
    set_physics_process(false)

func take_damage(amount: float) -> void:
    if _state != State.ACTIVE:
        return
    hp_current -= amount
    if hp_current <= 0.0:
        _die()

func _die() -> void:
    _state = State.DYING
    enemy_died.emit(global_position, enemy_type, energy_value)
    # EnemySystem listens to enemy_died → spawns EnergyDrop + plays VFX
    deactivate()
    _state = State.DEAD

func _physics_process(_delta: float) -> void:
    if _state != State.ACTIVE:
        return
    if not _should_process():
        return
    _seek_player()
    move_and_slide()

func _seek_player() -> void:
    var dir := (PlayerSystem.global_position - global_position).normalized()
    velocity = dir * move_speed

func _should_process() -> bool:
    match GSM.current_state:
        GSM.State.CHARGING:
            return true
        GSM.State.TRANSFORMATION:
            return false  # Frozen during transform
        _:
            return false  # DEATH, UPGRADE, etc.
```

### EnemySystem Autoload

```gdscript
# EnemySystem.gd — Autoload #5
extends Node

signal enemy_spawned(enemy: EnemyController)
signal enemy_killed(position: Vector2, enemy_type: String, form_points_drop: float)
signal all_enemies_despawned()

var _pools: Dictionary = {}           # enemy_type → Array[EnemyController]
var _active_enemies: Array[EnemyController] = []
var _configs: Dictionary = {}         # enemy_type → EnemyConfig

func _ready() -> void:
    _load_configs()
    _preallocate_pools()
    # Signal subscriptions:
    #   GSM.state_changed → _on_state_changed

func _load_configs() -> void:
    for config in DataConfig.enemy_configs:
        _configs[config.enemy_type] = config

func _preallocate_pools() -> void:
    for enemy_type in _configs:
        var config: EnemyConfig = _configs[enemy_type]
        var pool: Array[EnemyController] = []
        var scene := load(config.scene_path) as PackedScene
        for i in config.pool_size:
            var enemy := scene.instantiate() as EnemyController
            enemy.configure(config)
            enemy.deactivate()
            enemy.enemy_died.connect(_on_enemy_died)
            add_child(enemy)
            pool.append(enemy)
        _pools[enemy_type] = pool

func spawn_enemy(enemy_type: String, position: Vector2) -> EnemyController:
    var pool := _pools.get(enemy_type, [])
    for enemy in pool:
        if enemy._state == EnemyController.State.IDLE or enemy._state == EnemyController.State.DEAD:
            enemy.activate(position)
            _active_enemies.append(enemy)
            enemy_spawned.emit(enemy)
            return enemy
    push_warning("[EnemySystem] Pool exhausted for %s — dropping spawn" % enemy_type)
    return null

func despawn_all() -> void:
    for enemy in _active_enemies:
        enemy.deactivate()
    _active_enemies.clear()
    all_enemies_despawned.emit()

func get_active_count() -> int:
    return _active_enemies.size()

func _on_enemy_died(position: Vector2, enemy_type: String, energy_value: float) -> void:
    _active_enemies.erase(enemy)  # FIX: need reference to enemy
    enemy_killed.emit(position, enemy_type, energy_value)
    # EnergyDrop spawned by EnemySystem or delegated to a DropManager
    _spawn_energy_drop(position, energy_value)
    # VFX death particle triggered by enemy_killed signal (VFX listens)

func _spawn_energy_drop(position: Vector2, energy_value: float) -> void:
    var drop := _energy_drop_pool.acquire()
    if drop:
        drop.spawn(position, energy_value)

func _on_state_changed(_old: GSM.State, new_state: GSM.State) -> void:
    match new_state:
        GSM.State.DEATH, GSM.State.VICTORY:
            despawn_all()
```

### Enemy Pool Configuration

| Enemy Type | Pool Size | Scene Path | Notes |
|-----------|-----------|------------|-------|
| slime | 20 | `res://assets/scenes/enemies/enemy_slime.tscn` | Most common, small |
| bat | 15 | `res://assets/scenes/enemies/enemy_bat.tscn` | Fast, low HP |
| brute | 10 | `res://assets/scenes/enemies/enemy_brute.tscn` | Slow, high HP |
| spawner | 5 | `res://assets/scenes/enemies/enemy_spawner.tscn` | Stationary, spawns mini-enemies |

Total pool: 50 enemies (matches MVP performance cap).

### Enemy Death Flow

```
Enemy HP reaches 0
    → EnemyController._die()
        → enemy_died signal (position, type, energy_value)
            → EnemySystem._on_enemy_died()
                → Removes from _active_enemies
                → Spawns EnergyDrop (via drop pool)
                → Emits enemy_killed signal
                    → VFX plays death particle (from pool) at position
                    → Audio plays enemy death SFX (AUD-022)
                    → WaveSystem checks wave clear condition
```

### Rationale for Scene-Based Enemies (Not Pure Code)

- **Visual variety**: Each enemy type has its own `Sprite2D` with specific texture/frames. A pure-code enemy would need to load textures manually — scenes do this declaratively.
- **Collision shape per type**: Slime = small circle. Brute = large rectangle. Defined in `.tscn` per type.
- **Godot workflow**: Scenes are the standard way to compose nodes. Rejecting scenes for enemies would mean fighting the engine.

### Rationale for Simple Seek AI (Not NavigationAgent2D)

- **Open arena**: MVP has no obstacles (walls, pits). Enemies move in straight lines toward the player. `NavigationAgent2D` with an empty navigation map is just an expensive direction vector.
- **Performance**: 50 `NavigationAgent2D` nodes each calling `get_next_path_position()` per frame = significant overhead. A normalized direction vector is one subtraction + one `normalized()` call.
- **Future-proofing**: If obstacles are added in Vertical Slice, `NavigationAgent2D` can be added to the `_seek_player()` method without changing the rest of the architecture.

## Alternatives Considered

### Alternative 1: Pure-code enemies (no .tscn scenes)

- **Description**: Enemy types are defined entirely in code. EnemySystem creates `CharacterBody2D` nodes and adds children programmatically. Stats from EnemyConfig.
- **Pros**: No scene loading overhead. No `.tscn` files to maintain. Enemies are pure data.
- **Cons**: Collision shapes, sprites, and area nodes must be created in code — verbose and error-prone. Visual iteration requires code changes. Not idiomatic Godot.
- **Rejection Reason**: Scenes are the natural Godot way to compose visual objects. The marginal cost of loading 3-4 `.tscn` files at boot is negligible. Visual designers can tweak enemy sprites and collision shapes without touching code.

### Alternative 2: No enemy pooling — instantiate/free per spawn/death

- **Description**: `enemy_scene.instantiate()` on spawn, `queue_free()` on death. No pool management.
- **Pros**: Simple code. No `_state` enum. No activate/deactivate lifecycle.
- **Cons**: `instantiate()` + `add_child()` 50 times over a wave creates node-tree churn. `queue_free()` on death triggers GC. At 60fps with waves spawning 5-10 enemies at once, this produces measurable frame spikes.
- **Rejection Reason**: Same reason as ADR-0003 (Object Pooling) — runtime node allocation during gameplay is banned. Enemies are pooled for the same reason particles are pooled.

### Alternative 3: NavigationAgent2D pathfinding per enemy

- **Description**: Each enemy has a `NavigationAgent2D` child. Enemies compute paths around obstacles to reach the player.
- **Pros**: Handles obstacles naturally. Enemies can be blocked by walls, kited around terrain. Better AI.
- **Cons**: 50 `NavigationAgent2D` path queries per physics frame = 2-3ms. Without obstacles, it's wasted computation. Requires navigation map setup.
- **Rejection Reason**: MVP has an open arena. Paying for pathfinding without obstacles is wasteful. The `_seek_player()` direction vector is one line and < 0.01ms for 50 enemies.

## Consequences

### Positive

- **Unified enemy lifecycle**: `IDLE → ACTIVE → DYING → DEAD`. Every enemy follows the same state machine. Pooled enemies cycle through IDLE↔ACTIVE↔DYING→DEAD→IDLE.
- **Pool exhaustion drops, not crashes**: If all 50 enemies are active, `spawn_enemy()` returns null. WaveSystem can handle this gracefully (delay spawn, skip spawn, log warning).
- **Death flow is centralized**: `EnemyController._die()` → `EnemySystem._on_enemy_died()` → EnergyDrop + VFX + Audio + WaveSystem check. One signal, four consumers.
- **GSM-aware movement**: `_should_process()` gates all enemy AI on game state. During TRANSFORMATION, enemies freeze. During DEATH, all despawn. Zero per-enemy state checking — each enemy reads GSM directly.
- **Data-driven enemy types**: Adding a new enemy = EnemyConfig.tres + enemy_new.tscn scene + add to DataConfig.enemy_configs. Zero EnemySystem code changes.

### Negative

- **Fixed pool sizes**: 20 slimes, 15 bats, etc. If a wave design requires 25 slimes simultaneously, the 21st spawn is dropped. **Accepted cost**: Pool sizes are configurable in DataConfig enemy pool sizes. Visible warning on exhaustion.
- **No obstacle navigation**: Enemies walk through each other and any future obstacles. **Accepted cost**: Open arena for MVP. Enemy-enemy collision avoidance can be added via simple separation steering in `_seek_player()` without full pathfinding.
- **EnemyController is coupled to PlayerSystem global**: `_seek_player()` references `PlayerSystem.global_position` directly. **Accepted cost**: This is the Autoload pattern (ADR-0001). PlayerSystem is globally accessible. If enemy AI needs to target something other than the player (future feature), a `_target_position` property replaces the direct reference.

### Risks

- **Risk: 50 enemies seeking the player simultaneously causes clumping**: All enemies converge on the same point → they overlap visually and functionally. **Mitigation**: Simple separation steering added to `_seek_player()` — each enemy pushes away from nearby enemies. A `_separation_radius` in EnemyConfig per type.
- **Risk: EnergyDrop pool exhaustion**: If 50 enemies die in rapid succession, EnergyDrop pool may exhaust. **Mitigation**: EnergyDrop pool is sized generously (30-40). Drops are temporary (visible briefly, then collected or fade). If pool exhausts, the drop is skipped — energy is lost, but the game doesn't crash.
- **Risk: `_active_enemies` array isn't cleaned if enemy dies without signal**: If `_die()` fails to emit `enemy_died` (bug), enemy stays in `_active_enemies` forever, inflating `get_active_count()`. **Mitigation**: The `_state` machine is explicit. `activate()` and `deactivate()` are the only state transitions. A debug check in `_process()` can detect DEAD enemies still in `_active_enemies`.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| enemy-system.md | Enemy types: Slime, Bat, Brute, Spawner with per-type stats | EnemyConfig Custom Resource per type. Pooled scenes. `configure(config)` sets stats. |
| enemy-system.md | Seek player AI (simple direction-based) | `_seek_player()` — normalized direction × move_speed. Steering separation for anti-clump. |
| enemy-system.md | Contact damage to player via Area2D overlap | HurtArea child → `body_entered` signal → PlayerSystem.take_damage(contact_damage) |
| enemy-system.md | Death drops energy pickups | `enemy_died` → EnemySystem._on_enemy_died() → spawn EnergyDrop from pool |
| enemy-system.md | State-dependent behavior: active in CHARGING, frozen in TRANSFORMATION, despawn on DEATH/VICTORY | `_should_process()` gates `_physics_process()`. `_on_state_changed()` despawns on DEATH/VICTORY. |
| enemy-system.md | Performance: ≤ 50 simultaneous enemies at 60fps | Object pooling with fixed pools totaling 50. Simple seek AI (no pathfinding). |
| vfx-system.md | Enemy death particles per type | `enemy_killed` signal carries `enemy_type` → VFX plays death particle from pool matching type |
| audio-system.md | Enemy death SFX (AUD-022) | Audio subscribes to `enemy_killed` → plays death SFX |
| audio-system.md | Enemy proximity warning (AUD-021) | Audio reads nearest enemy distance (or EnemySystem emits proximity signal) |
| absorption-system.md | Energy drops fill absorption meter | EnergyDrop collected by PlayerSystem → AbsorptionSystem.add_energy(amount) |
| wave-system.md | Waves spawn enemy groups | WaveSystem calls `EnemySystem.spawn_enemy(type, position)` per wave definition |

## Performance Implications

- **CPU**: 50 enemies × `_physics_process()` = 50 direction calculations + 50 `move_and_slide()` calls. Estimated 1-2ms/frame on PC. Within 16.6ms budget with headroom for other systems.
- **Memory**: 50 pooled CharacterBody2D instances ≈ 50 × 2KB = 100 KB. EnergyDrop pool (30 × 1KB = 30 KB). Total ≈ 130 KB.
- **Load Time**: 3-4 `.tscn` file loads × pool_size instantiations. Pre-allocation in `_ready()`. Estimated 5-10ms at boot — acceptable.

## Migration Plan

N/A — EnemySystem is created fresh. No existing enemy code to migrate.

## Validation Criteria

- `spawn_enemy("slime", Vector2(100, 100))` activates an idle enemy from the slime pool at the given position
- `spawn_enemy("slime", ...)` when all 20 slimes are active returns null (not a crash)
- 50 enemies seek the player simultaneously — frame time does not exceed 2ms
- Enemy HP reaches 0 → `enemy_died` signal → EnergyDrop appears at death position → enemy returns to pool (IDLE)
- During TRANSFORMATION state: all active enemies stop moving (frozen in place)
- During DEATH state: all active enemies despawn (hide + deactivate) → `all_enemies_despawned` signal
- A new enemy type added via EnemyConfig.tres + .tscn → spawns correctly without EnemySystem code changes
- Energy drops from 50 simultaneous kills do not exhaust the EnergyDrop pool (or gracefully skip)
- Enemy contact with player → PlayerSystem takes damage matching EnemyConfig.contact_damage

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — EnemySystem is Autoload #5, Core layer
- ADR-0003: Object Pooling Architecture — Enemy and EnergyDrop pools follow the same acquire/release/active_count pattern
- ADR-0005: Data Configuration Architecture — EnemyConfig Custom Resource defines per-type stats
- ADR-0007: GSM State Machine — Enemy behavior gated by `GSM.current_state`
- ADR-0008: Absorption System Architecture — EnergyDrop collection feeds meter
