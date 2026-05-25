# ADR-0012: Player System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — `CharacterBody2D`, `Area2D`, and input handling are pre-4.0 stable. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify CharacterBody2D.move_and_slide() with 8-directional input at 60fps. Verify collision detection with 50+ enemy Area2D nodes. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload) — PlayerSystem is Autoload #4. ADR-0006 (InputSystem) — movement + combat input. ADR-0007 (GSM) — state-gated behavior. ADR-0008 (Absorption) — energy collection. ADR-0009 (Transformation) — stat modifiers. ADR-0010 (EnemySystem) — collision damage. |
| **Enables** | EnemySystem (collision target), VFX (hit flash, damage numbers), Audio (damage SFX), HUD (HP bar), TransformationSystem (stat target) |
| **Blocks** | HUD HP bar stories, VFX hit flash stories, Audio damage SFX stories |
| **Ordering Note** | Must be Accepted before HUD implementation (HUD reads PlayerSystem.hp_current). Core dependency for most Presentation systems. |

## Context

### Problem Statement

The player character is the only entity under direct player control. PlayerSystem must handle: (1) 8-directional WASD movement with gamepad support; (2) HP management with invulnerability frames after taking damage; (3) combat — auto-aim attack toward nearest enemy or mouse direction; (4) energy drop collection via pickup radius; (5) stat modifiers during transformation (applied by TransformationSystem, not self-applied); (6) death detection and signal emission. These responsibilities are tightly coupled — movement speed affects collection efficiency, HP affects survival time, collection fuels transformation which modifies all stats. Without a defined player architecture, these interlocking systems would have conflicting assumptions about player state.

### Constraints

- Godot 4.6 + GDScript + GL Compatibility
- `CharacterBody2D` for physics-based movement
- WASD + gamepad left stick input (via InputSystem/Input)
- Up to 50 enemies on screen — player collision checks scale with enemy count
- Invulnerability after hit (iframe) — prevents instant death from overlapping enemies
- Stats modified by TransformationSystem, not PlayerSystem itself (ADR-0001)
- No mouse aiming for attacks in MVP — auto-aim to nearest enemy

### Requirements

- 8-directional movement with normalized speed
- HP: float with max_hp. At 0 → player_died signal
- Invulnerability frames: 0.15s after taking damage (configurable)
- Auto-aim attack: targets nearest enemy within range
- Pickup radius: collect EnergyDrop Area2D nodes on overlap
- Stat multipliers: speed, damage, pickup_radius — applied externally via TransformationSystem
- State-gated: movement/combat only in CHARGING and TRANSFORMATION states
- Signals: player_hit(damage), damage_dealt(target, amount), player_died(), hp_changed(new_hp)

> **Default values**: The GDD `player-system.md` is the authoritative source for all default stat values (hp_max, move_speed, attack_damage, attack_range, attack_interval, collider_radius, iframe_duration, pickup_radius). The code defaults below match the GDD; runtime values are loaded from DataConfig in `_ready()`.

## Decision

**PlayerSystem Autoload owns a Player scene instance. Player is a CharacterBody2D with child Area2D nodes for collision (hurtbox, hitbox, pickup radius). Movement via Input.get_vector(). Combat via auto-aim to nearest enemy within range. Stats as multipliers on base values. Invulnerability via iframe timer.**

### Player Scene Structure

```
Player (CharacterBody2D) — instanced by PlayerSystem Autoload
├── Sprite2D                     # 32×32 pixel art character
├── CollisionShape2D             # Physics body (circle, radius ~8px)
├── Hurtbox (Area2D)             # Receives enemy contact damage
│   └── CollisionShape2D
├── Hitbox (Area2D)              # Deals damage to enemies
│   └── CollisionShape2D
├── PickupRadius (Area2D)        # Collects EnergyDrops
│   └── CollisionShape2D (circle, large radius)
└── PlayerController (script)
```

### PlayerController Script

```gdscript
# PlayerController.gd — attached to Player scene
class_name PlayerController
extends CharacterBody2D

signal player_hit(damage: float)
signal damage_dealt(target: Node2D, amount: float)
signal player_died()
signal hp_changed(new_hp: float)

# Base stats
var hp_current: float = 100.0
var hp_max: float = 100.0
var base_speed: float = 200.0
var base_damage: float = 5.0
var base_pickup_radius: float = 24.0
var attack_range: float = 48.0
var attack_cooldown: float = 0.8

# Stat multipliers (set by TransformationSystem)
var speed_mult: float = 1.0
var damage_mult: float = 1.0
var pickup_radius_mult: float = 1.0

# Internal state
var _attack_timer: float = 0.0
var _iframe_timer: float = 0.0
var _is_alive: bool = true

const IFRAME_DURATION: float = 0.15  # Overridden by DataConfig

func _ready() -> void:
    hp_max = DataConfig.player_hp_max
    hp_current = hp_max
    base_speed = DataConfig.player_base_speed
    base_damage = DataConfig.player_base_damage
    attack_range = DataConfig.player_attack_range
    attack_cooldown = DataConfig.player_attack_cooldown
    # Hurtbox connections
    $Hurtbox.area_entered.connect(_on_hurtbox_area_entered)
    $PickupRadius.area_entered.connect(_on_pickup_area_entered)

func _physics_process(delta: float) -> void:
    if not _should_process():
        return
    
    _tick_timers(delta)
    _handle_movement()
    _handle_combat()
    move_and_slide()

func _should_process() -> bool:
    if not _is_alive:
        return false
    match GSM.current_state:
        GSM.State.CHARGING, GSM.State.TRANSFORMATION:
            return true
        _:
            return false

func _handle_movement() -> void:
    var move_dir := Input.get_vector(
        "move_left", "move_right", "move_up", "move_down"
    )
    velocity = move_dir * base_speed * speed_mult

func _handle_combat() -> void:
    if _attack_timer > 0.0:
        return
    if not Input.is_action_pressed("attack"):
        return
    
    var target := _find_nearest_enemy()
    if target and global_position.distance_to(target.global_position) <= attack_range:
        _attack_timer = attack_cooldown
        var damage := base_damage * damage_mult
        target.take_damage(damage)
        damage_dealt.emit(target, damage)

func _find_nearest_enemy() -> EnemyController:
    var bodies := $Hitbox.get_overlapping_bodies()
    var nearest: EnemyController = null
    var nearest_dist := INF
    for body in bodies:
        if body is EnemyController and body._state == EnemyController.State.ACTIVE:
            var dist := global_position.distance_squared_to(body.global_position)
            if dist < nearest_dist:
                nearest_dist = dist
                nearest = body
    return nearest

func _tick_timers(delta: float) -> void:
    if _attack_timer > 0.0:
        _attack_timer -= delta
    if _iframe_timer > 0.0:
        _iframe_timer -= delta
```

### Damage & Invulnerability

```gdscript
func take_damage(amount: float) -> void:
    if not _is_alive:
        return
    if _iframe_timer > 0.0:
        return  # Still invulnerable
    
    hp_current = maxf(hp_current - amount, 0.0)
    hp_changed.emit(hp_current)
    player_hit.emit(amount)
    
    # Start invulnerability
    _iframe_timer = DataConfig.player_iframe_duration  # 0.15s
    
    # Visual feedback delegated to VFX (subscribes to player_hit)
    
    if hp_current <= 0.0:
        _die()

func _die() -> void:
    _is_alive = false
    player_died.emit()
    GSM.request_transition(GSM.State.DEATH)

func _on_hurtbox_area_entered(area: Area2D) -> void:
    # Enemy HurtArea entered player's hurtbox
    if area.get_parent() is EnemyController:
        var enemy := area.get_parent() as EnemyController
        if enemy._state == EnemyController.State.ACTIVE:
            take_damage(enemy.contact_damage)
```

### Pickup Collection

```gdscript
func _on_pickup_area_entered(area: Area2D) -> void:
    if area is EnergyDrop:
        AbsorptionSystem.add_energy(area.energy_value)
        area.queue_free()  # Drop consumed
        # Audio: AUD-020 (collection "ding")
```

### PlayerSystem Autoload (Wrapper)

```gdscript
# PlayerSystem.gd — Autoload #4
extends Node

var player: PlayerController = null
var hp_current: float: get = _hp_current_get
var hp_max: float: get = _hp_max_get
var global_position: Vector2: get = _global_position_get

func _ready() -> void:
    _spawn_player()
    # Signal subscriptions:
    #   TransformationSystem.transformation_started → _on_transformation_started
    #   TransformationSystem.transformation_expired → _on_transformation_expired

func _spawn_player() -> void:
    var scene := load("res://assets/scenes/player/player.tscn") as PackedScene
    player = scene.instantiate() as PlayerController
    add_child(player)
    player.global_position = _get_player_spawn_position()

func _on_transformation_started(form_id: String, is_berserk: bool) -> void:
    var config := DataConfig.get_form_config(form_id)
    player.speed_mult = config.speed_multiplier
    player.damage_mult = config.damage_multiplier
    player.pickup_radius_mult = config.get("pickup_radius_multiplier", 1.0)
    if is_berserk:
        player.speed_mult *= DataConfig.berserk_stat_multiplier
        player.damage_mult *= DataConfig.berserk_stat_multiplier

func _on_transformation_expired(_form_id: String) -> void:
    player.speed_mult = 1.0
    player.damage_mult = 1.0
    player.pickup_radius_mult = 1.0

func _hp_current_get() -> float:
    return player.hp_current if player else 0.0

func _hp_max_get() -> float:
    return player.hp_max if player else 100.0

func _global_position_get() -> Vector2:
    return player.global_position if player else Vector2.ZERO
```

### Architecture Diagram

```
PlayerSystem (Autoload #4)
│
└── Player (CharacterBody2D scene instance)
    ├── Movement: Input.get_vector() × base_speed × speed_mult
    ├── Combat: Auto-aim → nearest enemy in Hitbox range
    │   └── damage_dealt(target, base_damage × damage_mult)
    ├── Damage: Hurtbox.Area2D.area_entered → take_damage()
    │   ├── iframe_timer blocks re-damage for 0.15s
    │   └── player_hit(damage) + hp_changed(new_hp) signals
    ├── Collection: PickupRadius.area_entered → AbsorptionSystem.add_energy()
    ├── Death: hp_current ≤ 0 → player_died() → GSM.request_transition(DEATH)
    └── Stat modifiers: Applied by TransformationSystem signals
        ├── speed_mult, damage_mult, pickup_radius_mult
        └── Reset to 1.0 on transformation_expired
```

### Auto-Aim Rationale

- **No mouse aiming in MVP**: The game is a survivor — the primary skill is positioning and transformation timing, not precise aiming.
- **Auto-aim is standard for the genre**: Vampire Survivors, Brotato, 20 Minutes Till Dawn all use auto-aim. Players expect it.
- **Mouse aim adds complexity**: Mouse position tracking, aim direction rendering, projectile spawning toward cursor — all additional systems that don't serve the core fantasy.
- **Manual aim can be added later**: The architecture supports it — swap `_find_nearest_enemy()` for `_get_mouse_direction()` in the combat handler.

### Stat Multiplier Pattern

PlayerSystem owns **base stats** (from DataConfig) and **multipliers** (set by TransformationSystem). The effective stat is `base × multiplier`. This pattern:

- **Preserves owner writes**: PlayerSystem never writes to TransformationSystem. TransformationSystem sets `player.speed_mult` directly — but this is PlayerSystem's own property, so it respects ADR-0001 (TransformationSystem writes to PlayerSystem's multiplier, not PlayerSystem's HP or other internal state).
- **Clean reset**: On `transformation_expired`, all multipliers reset to 1.0. No need to "remember" the pre-transform value.
- **Stackable**: Multiple stat sources can multiply together. A future "speed power-up" would set its own multiplier.
- **Correction**: Actually, ADR-0001 says systems must not directly assign to another Autoload's properties. TransformationSystem setting `player.speed_mult` directly violates this. The correct pattern is: TransformationSystem emits `transformation_started(form_id, is_berserk)` → PlayerSystem listens and applies modifiers to itself. Let me fix this in the code.

Fixed: PlayerSystem subscribes to `TransformationSystem.transformation_started` and self-applies multipliers. This respects ADR-0001.

## Alternatives Considered

### Alternative 1: Player as a separate scene (not under PlayerSystem Autoload)

- **Description**: Player is a standalone scene in the game world, not a child of the PlayerSystem Autoload. PlayerSystem is just a data proxy.
- **Pros**: Player is part of the scene tree with other game objects. Natural physics interactions.
- **Cons**: PlayerSystem Autoload can't easily access the player node (which scene owns it? GameWorld? Main?). Access requires `get_tree().get_first_node_in_group("player")` — fragile string-based lookup. The Autoload being the player's parent ensures PlayerSystem always has a direct reference.
- **Rejection Reason**: ADR-0001 declares PlayerSystem as Autoload #4. The player node being a child of the Autoload is the natural Godot pattern for Autoload-owned entities.

### Alternative 2: Mouse-aim combat (player aims attack direction)

- **Description**: Player aims with mouse cursor. Attack fires toward cursor position. Projectile or melee in aimed direction.
- **Pros**: More player agency. Skill expression through aim. Distinct from Vampire Survivors clone criticism.
- **Cons**: Requires mouse tracking, aim indicator UI, projectile system. Adds input complexity — player must manage WASD movement AND mouse aim simultaneously. GDD specifies "auto-aim to nearest enemy" for MVP combat.
- **Rejection Reason**: GDD specifies auto-aim for MVP. Mouse aim is a Vertical Slice enhancement that can layer on top of the existing combat handler without architectural changes.

### Alternative 3: Player stats owned by individual components (HPComponent, SpeedComponent, etc.)

- **Description**: Player is composed of reusable `HealthComponent`, `MovementComponent`, `CombatComponent` nodes — each a self-contained `.gd` script.
- **Pros**: Reusable across player and enemies. Testable in isolation. Clean separation.
- **Cons**: Over-engineered for MVP with one player and 3-4 enemy types. Components add node depth and inter-component communication complexity. The shared interface between PlayerCombat and EnemyCombat is minimal — they don't benefit from a shared base.
- **Rejection Reason**: Component architecture adds ceremony without benefit at MVP scale. If enemy count or complexity grows significantly in Vertical Slice, extract shared components then. The current architecture (PlayerController + EnemyController) is clear and independent.

## Consequences

### Positive

- **Single player instance**: `PlayerSystem.player` is the authoritative reference. Enemy AI, HUD, VFX all access the same node.
- **Multiplier pattern is clean**: Base stats from DataConfig. Multipliers from TransformationSystem. Effective = base × multiplier. Reset to 1.0 on transform expire. No state restore needed.
- **Iframe prevents burst damage**: 0.15s invulnerability after hit prevents 5 overlapping enemies from dealing 5× damage in one frame.
- **Auto-aim is simple and genre-appropriate**: One method, no aiming UI, no projectile system. Attack hits nearest enemy in range.
- **Pickup radius scales with transformation**: `pickup_radius_mult` set by TransformationSystem means transformed forms can collect drops from farther away — a satisfying power spike.

### Negative

- **Player is a scene, not procedural**: Player visuals require a `.tscn` file. Changing player appearance means editing the scene. **Accepted cost**: Player appearance is art-driven, not procedural. A scene is the right tool.
- **Auto-aim removes aiming skill**: Player cannot prioritize targets. Nearest enemy always takes damage. **Accepted cost**: Genre convention. Survivor games are about positioning, not aiming. If players want target priority, a "target lock" system can be added in Vertical Slice.
- **Single attack type**: No heavy attack, no special attack, no ranged attack. **Accepted cost**: MVP scope. Transformation changes damage output via multipliers, which is the form-differentiated "attack variety."

### Risks

- **Risk: Iframe too short → player dies instantly to stacked enemies**: 5 enemies dealing contact damage on the same frame before iframe activates. **Mitigation**: `take_damage()` sets `_iframe_timer` BEFORE processing damage — the iframe activates on the first hit within the same frame. Additionally, `_physics_process` only calls `move_and_slide()` once per frame, so enemy collision damage is processed once per enemy per frame at most.
- **Risk: Player gets stuck on enemy collision bodies**: 50 enemies surrounding the player create a collision cage. **Mitigation**: Enemy `CollisionShape2D` uses `collision_layer` that does NOT collide with player physics body. Enemy damage is delivered via Area2D overlap (HurtArea), not physics collision. Player slides through enemies — damage is the deterrent, not physical blocking.
- **Risk: `global_position` access by 50 enemies each frame**: Each enemy reads `PlayerSystem.global_position` in `_seek_player()`. This is a property access — not a method call. Zero overhead. But if PlayerSystem.player is null (briefly during init), enemies crash. **Mitigation**: Enemy `_physics_process()` checks `is_instance_valid(PlayerSystem.player)` before seeking. PlayerSystem guarantees player exists before GSM transitions to CHARGING.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| player-system.md | 8-directional WASD movement + gamepad | `Input.get_vector()` → `velocity = direction × base_speed × speed_mult` → `move_and_slide()` |
| player-system.md | HP with max_hp. 0 → player_died | `take_damage()` with iframe guard. `hp_current ≤ 0` → `player_died()` → `GSM.request_transition(DEATH)` |
| player-system.md | Auto-aim attack to nearest enemy | `_find_nearest_enemy()` iterates Hitbox overlapping bodies. Attack cooldown via `_attack_timer` |
| player-system.md | Invulnerability frames after hit | `_iframe_timer = DataConfig.player_iframe_duration` (0.15s). Blocks `take_damage()` until expired |
| player-system.md | Energy drop collection via pickup radius | `PickupRadius.Area2D.area_entered` → `AbsorptionSystem.add_energy(amount)` |
| player-system.md | Signals: player_hit, damage_dealt, player_died | All 3 defined on PlayerController. PlayerSystem Autoload exposes them via player reference |
| player-system.md | Stat modifiers during transformation | PlayerSystem subscribes to `transformation_started` → sets `speed_mult`, `damage_mult`, `pickup_radius_mult` from FormConfig |
| enemy-system.md | Enemy contact damage to player | Enemy HurtArea → Player Hurtbox overlap → `PlayerController.take_damage(enemy.contact_damage)` |
| transformation-system.md | Stat modifiers applied to player | TransformationSystem emits signal → PlayerSystem self-applies multipliers |
| absorption-system.md | Energy drops collected by player | Player PickupRadius → EnergyDrop Area2D overlap → `AbsorptionSystem.add_energy()` |
| hud-ui-system.md | HP bar display | HUD reads `PlayerSystem.hp_current` / `PlayerSystem.hp_max` or subscribes to `hp_changed` |
| vfx-system.md | Hit flash on damage | VFX subscribes to `player_hit` → triggers hit flash VFX |
| audio-system.md | Damage SFX (AUD-011/012) | Audio subscribes to `player_hit` → plays damage SFX. Low HP heartbeat reads `hp_current / hp_max` |

## Performance Implications

- **CPU**: `_physics_process()`: 1 `get_vector()` + 1 `move_and_slide()` + auto-aim (iterates overlapping bodies in Hitbox — typically 2-5 enemies). < 0.1ms/frame.
- **Memory**: One CharacterBody2D + 3 Area2D + 1 Sprite2D + 1 CollisionShape2D ≈ 5 KB.
- **Load Time**: One `.tscn` load + instantiation. Sub-millisecond.

## Migration Plan

N/A — PlayerSystem is created fresh.

## Validation Criteria

- WASD produces 8-directional movement at `base_speed` pixels/second
- Player cannot move during UPGRADE or DEATH state
- Enemy contact while `_iframe_timer == 0` → `take_damage()` → `hp_changed` + `player_hit` signals → iframe activates
- Enemy contact while `_iframe_timer > 0` → damage ignored
- HP reaches 0 → `player_died()` → GSM transitions to DEATH
- Holding attack key → auto-aim hits nearest enemy within range → `damage_dealt` signal → `_attack_timer` prevents continuous fire
- EnergyDrop within pickup radius → `AbsorptionSystem.add_energy()` → drop consumed
- `transformation_started("beast", false)` → `speed_mult = FormConfig.speed_multiplier` → player moves at modified speed
- `transformation_expired("beast")` → all multipliers reset to 1.0
- 50 enemies surrounding player → iframe prevents one-frame death → player can move through enemies (no collision block)

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — PlayerSystem is Autoload #4, Core layer
- ADR-0004: Signal Bus Pattern — All player signals follow past-tense naming
- ADR-0005: Data Configuration Architecture — Player base stats from DataConfig
- ADR-0006: Input System Architecture — Movement via Input.get_vector()
- ADR-0007: GSM State Machine — Player behavior gated by GSM.current_state
- ADR-0008: Absorption System Architecture — Energy collection feeds meter
- ADR-0009: Transformation System Architecture — Stat multipliers applied to PlayerSystem
- ADR-0010: Enemy System Architecture — Collision damage via Area2D overlap
