# ADR-0015: VFX System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Rendering |
| **Knowledge Risk** | MEDIUM — `CpuParticles2D` and `CanvasLayer.modulate` are pre-4.0 stable. GL Compatibility renderer restrictions on shader usage (no `hint_screen_texture`, limited CanvasItem shader features) affect death dissolve and screen flash implementation. Post-4.0 `CpuParticles2D` API changes (4.3+ particle emission shape, 4.4+ `emit_particle` function) may affect particle spawning approach. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | `CpuParticles2D.emit_particle()` (Godot 4.4+) — per-particle manual emission for precise burst control |
| **Verification Required** | Verify CpuParticles2D.emit_particle() behavior in Godot 4.6 GL Compatibility — confirm x/y particle count parameters work correctly. Verify CanvasLayer.modulate for full-screen flash does not cause draw call spikes. Verify 150 simultaneous CpuParticles2D at 60fps on GL Compatibility renderer stays under 1ms/frame. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload) — VFXSystem is Autoload #11. ADR-0002 (CanvasLayer) — VFX owns layers 1 (VFX_World), 2 (VFX_Screen), 5 (VFX_Overlay). ADR-0003 (Object Pooling) — ParticlePoolManager with 6 pools / 270 CpuParticles2D. ADR-0007 (GSM) — state_changed drives VFX state transitions. ADR-0012 (PlayerSystem) — player_hit, damage_dealt, player_died signals. ADR-0009 (TransformationSystem) — transformation_started/expired, berserk_activated/expired signals. ADR-0011 (WaveSystem) — wave_started/cleared, boss_wave_started, all_waves_cleared signals. |
| **Enables** | Settings (VFX intensity control, VS), BossSystem (boss intro/death VFX, VS), Audio (parallel sync via shared signals) |
| **Blocks** | Boss VFX stories, VFX intensity settings stories |
| **Ordering Note** | Must be Accepted after all upstream Core ADRs whose signals VFX subscribes to. VFX is a leaf consumer — it depends on signal contracts being finalized. |

## Context

### Problem Statement

Shapeshift Survivor relies on visual feedback ("game juice") to make every gameplay event feel impactful. 22 distinct VFX entries across 8 categories — transformation flashes, attack particles, hit feedback, death dissolve, wave announcements, boss warnings — must trigger from game signals, render at consistent Z-orders via CanvasLayer, respect pixel-art constraints (no post-processing, nearest-neighbor scaling, geometric motif per form), and stay within a 150-particle screen limit on GL Compatibility renderer. Without a defined VFX architecture, particles would be ad-hoc per-signal with duplicated spawn/decay/pool logic, Z-ordering would conflict with HUD layers, and pool exhaustion during intense combat would either crash or silently drop visual feedback.

### Constraints

- Godot 4.6 + GDScript + GL Compatibility renderer
- `CpuParticles2D` only — no GPU particles (GL Compatibility restriction)
- CanvasLayer 1 (VFX_World), 2 (VFX_Screen), 5 (VFX_Overlay) per ADR-0002
- Max 150 simultaneous particles on screen (MVP performance cap)
- Pixel art constraints: nearest-neighbor scaling, 2×2/4×4 px sprites, 90°/180° rotation only, no post-processing
- Geometric motif per form: Beast = circle/arc, Dragon = triangle
- Color theme per form: Beast = `#FF6B35`, Dragon = `#C44B8B`
- Screen flash via CanvasLayer.modulate — no additional node allocation
- Particle pool management per ADR-0003 (6 pools, 270 total, pre-allocated)

### Requirements

- 22 VFX entries catalogued by trigger signal and priority
- 3-tier CanvasLayer rendering per ADR-0002 Z-order
- Priority-based simultaneous VFX resolution (5 tiers: highest → lowest)
- Pool exhaustion: recycle oldest particle, skip if all highest-priority
- Screen flash: 4-phase sequence (form-color → white → black-silhouette → fade-out)
- Death dissolve: pixel-edge collapse inward at 16 px/s
- Per-frame form aura rendering during TRANSFORMATION/BERSERK
- Low HP warning via pre-rendered 9-slice TextureRect — not per-frame repaint
- VFX intensity settings interface (FULL / REDUCED / OFF) for future Settings system

## Decision

**VFXSystem as Autoload #11. Three CanvasLayers per ADR-0002. ParticlePoolManager with 6 pools from ADR-0003. VFXCatalog — a data-driven Dictionary mapping (signal, form_id, state) → VFXEntry — drives all visual responses. Priority system (5 tiers) resolves simultaneous VFX ordering. Screen flash uses CanvasLayer.modulate (zero node allocation). Per-frame aura uses a single persistent CpuParticles2D with continuous emission mode.**

### Core State Model

```gdscript
# VFXSystem.gd — Autoload #11
extends Node

enum VFXPriority { LOWEST = 0, LOW = 1, MEDIUM = 2, HIGH = 3, HIGHEST = 4 }
enum VFXIntensity { FULL, REDUCED, OFF }

signal vfx_triggered(vfx_id: String)

var _intensity: VFXIntensity = VFXIntensity.FULL
var _is_paused: bool = false
var _active_vfx: Array[VFXInstance] = []

# Particle pool manager (from ADR-0003)
var _particle_pools: ParticlePoolManager

# Persistent nodes
var _screen_flash_overlay: ColorRect      # CanvasLayer 2 — reused for all flashes
var _low_hp_texture: NinePatchRect        # CanvasLayer 2 — pre-rendered vignette
var _aura_particles: CpuParticles2D       # CanvasLayer 1 — persistent, mode-switched
var _vfx_world: CanvasLayer               # Layer 1
var _vfx_screen: CanvasLayer              # Layer 2
var _vfx_overlay: CanvasLayer             # Layer 5
```

### VFXCatalog — Data-Driven VFX Registry

```gdscript
# VFXCatalog.gd — Maps (trigger, context) → VFX definition
class_name VFXCatalog
extends Resource

class VFXEntry:
    var vfx_id: String
    var trigger_signal: String       # Signal name or "state_change"
    var trigger_state: GSM.State     # Only for state_change triggers
    var trigger_form_id: String      # "" = all forms, "beast"/"dragon" = specific
    var layer: int                   # CanvasLayer 1, 2, or 5
    var priority: VFXPriority
    var particle_config: ParticleConfig  # null for non-particle VFX
    var flash_config: FlashConfig        # null for non-flash VFX
    var duration: float

var entries: Array[VFXEntry] = []

# Initialized in VFXSystem._ready():
# VFXCatalog maps:
#   "state_change/TRANSFORMATION" → [VFX-001 flash, VFX-002 tear, VFX-003 burst, VFX-004 aura]
#   "player_hit" → [VFX-011 white_flash, VFX-012 screen_warning]
#   "damage_dealt/beast" → [VFX-008 beast_aoe]
#   "damage_dealt/dragon" → [VFX-009 dragon_cone]
#   "damage_dealt/human" → [VFX-010 human_hit]
#   "state_change/BERSERK" → [VFX-006 berserk_flash]
#   "state_change/COOLDOWN" → [VFX-005 form_fade]
#   "state_change/DEATH" → [VFX-014 death_dissolve, VFX-015 grayscale]
#   "wave_started" → [VFX-016 wave_text]
#   "wave_cleared" → [VFX-017 wave_clear_text]
#   "boss_wave_started" → [VFX-018 boss_warning]
#   "all_waves_cleared" → [VFX-019 area_clear]
```

### Signal → VFX Dispatch

```gdscript
func _ready() -> void:
    _create_canvas_layers()
    _particle_pools = ParticlePoolManager.new(_vfx_world, _vfx_screen, _vfx_overlay)
    _create_persistent_nodes()
    _build_vfx_catalog()
    # Signal subscriptions:
    #   GSM.state_changed → _on_state_changed
    #   PlayerSystem.player_hit → _on_player_hit
    #   PlayerSystem.damage_dealt → _on_damage_dealt
    #   PlayerSystem.player_died → _on_player_died
    #   TransformationSystem.transformation_started → _on_transformation_started
    #   TransformationSystem.transformation_expired → _on_transformation_expired
    #   WaveSystem.wave_started → _on_wave_started
    #   WaveSystem.wave_cleared → _on_wave_cleared
    #   WaveSystem.boss_wave_started → _on_boss_wave_started
    #   WaveSystem.all_waves_cleared → _on_all_waves_cleared

func _dispatch_vfx(trigger: String, context: Dictionary = {}) -> void:
    if _intensity == VFXIntensity.OFF and not _is_core_feedback(trigger):
        return
    
    var matches := _vfx_catalog.find_entries(trigger, context)
    for entry in matches:
        if _intensity == VFXIntensity.REDUCED:
            if entry.priority <= VFXPriority.LOW:
                continue  # Skip ambient/low VFX in reduced mode
            entry = entry.reduced_copy()  # Halve particle count, skip flash
        
        match entry.layer:
            1: _play_world_vfx(entry, context)
            2: _play_screen_vfx(entry, context)
            5: _play_overlay_vfx(entry, context)

func _is_core_feedback(trigger: String) -> bool:
    # Even in OFF mode, preserve: hit flash (gameplay-critical feedback)
    return trigger in ["player_hit", "player_died"]
```

### Screen Flash — CanvasLayer.modulate (Zero Node Allocation)

```gdscript
# Reuses a single ColorRect on CanvasLayer 2
var _flash_color_rect: ColorRect
var _flash_timer: float = 0.0
var _flash_config: FlashConfig = null

func _trigger_screen_flash(config: FlashConfig) -> void:
    if _intensity == VFXIntensity.OFF:
        return
    if _intensity == VFXIntensity.REDUCED:
        config = config.reduced_copy()  # Shorter, no white frame
    
    _flash_config = config
    _flash_timer = 0.0
    _flash_color_rect.visible = true
    _flash_color_rect.color = config.form_color
    _flash_color_rect.modulate.a = 1.0

func _tick_flash(delta: float) -> void:
    if not _flash_config:
        return
    _flash_timer += delta
    var t := _flash_timer
    var cfg := _flash_config
    
    # 4-phase sequence: form-color → white → black → fade-out
    if t < 0.3:
        _flash_color_rect.color = cfg.form_color  # Phase 1: form color
    elif t < 0.5:
        _flash_color_rect.color = Color.WHITE      # Phase 2: white
    elif t < 0.7:
        _flash_color_rect.color = Color.BLACK      # Phase 3: silhouette
        _flash_color_rect.modulate.a = 0.8
    elif t < 1.0:
        var fade_t := (t - 0.7) / 0.3
        _flash_color_rect.color = cfg.form_color   # Phase 4: fade out
        _flash_color_rect.modulate.a = lerpf(1.0, 0.0, fade_t)
    else:
        _flash_color_rect.visible = false
        _flash_config = null
```

### Per-Frame Aura — Persistent CpuParticles2D (Mode-Switched)

```gdscript
# One persistent CpuParticles2D on CanvasLayer 1 — mode-switched per form/state
# Not allocated per transformation. Configured, not instantiated.

func _on_transformation_started(form_id: String, is_berserk: bool) -> void:
    var config := DataConfig.get_form_config(form_id)
    
    # Configure persistent aura emitter
    _aura_particles.emitting = true
    _aura_particles.amount = config.aura_particle_count
    _aura_particles.lifetime = 0.8
    _aura_particles.initial_velocity_min = 10.0
    _aura_particles.initial_velocity_max = 30.0
    _aura_particles.color = config.primary_color
    _aura_particles.color.a = 0.15 if not is_berserk else 0.4
    _aura_particles.scale_amount_min = 1.0
    _aura_particles.scale_amount_max = 2.0
    _aura_particles.emission_shape = CpuParticles2D.EMISSION_SHAPE_SPHERE
    _aura_particles.emission_sphere_radius = 16.0 if not is_berserk else 24.0
    
    if is_berserk:
        _aura_particles.amount *= 1.5
        _aura_particles.pulse_period = 0.3  # Berserk pulse

func _on_transformation_expired(_form_id: String) -> void:
    _aura_particles.emitting = false
```

### Particle Burst — emit_particle() (Godot 4.4+)

```gdscript
func _emit_burst(config: ParticleConfig, position: Vector2, direction: Vector2) -> void:
    if _intensity == VFXIntensity.OFF:
        return
    
    var count := config.count
    if _intensity == VFXIntensity.REDUCED:
        count = int(count * 0.6)
    
    var pool := _particle_pools.get_pool(config.pool_type)
    if not pool:
        return
    
    for i in count:
        var particle := pool.acquire()
        if not particle:
            # Pool exhausted — recycle oldest
            particle = pool.recycle_oldest(config.priority)
            if not particle:
                push_warning("[VFX] Pool %s exhausted — all HIGHEST priority, dropping" % config.pool_type)
                break
        
        particle.position = position
        particle.direction = direction.rotated(randf_range(-config.spread_angle, config.spread_angle))
        particle.initial_velocity = config.base_speed + randf_range(-config.speed_variance, config.speed_variance)
        particle.lifetime = config.lifetime
        particle.modulate = config.color
        particle.modulate.a = config.alpha_start
        particle.texture = config.sprite
        particle.emitting = true
```

### Priority Resolution for Simultaneous VFX

```gdscript
# When two VFX compete for the same CanvasLayer space:
# Higher priority renders on top. Equal priority: newer wins.
func _resolve_z_order(a: VFXInstance, b: VFXInstance) -> int:
    if a.priority != b.priority:
        return int(a.priority) - int(b.priority)
    return a.start_time - b.start_time  # Newer = higher (larger timestamp)
```

| Priority | VFX IDs |
|----------|---------|
| HIGHEST | VFX-001 (transform flash), VFX-002 (pixel tear), VFX-014 (death dissolve) |
| HIGH | VFX-003 (transform burst), VFX-005 (form fade), VFX-006 (berserk flash), VFX-011 (hit white flash), VFX-018 (boss warning), VFX-019 (area clear) |
| MEDIUM | VFX-007 (berserk aura), VFX-008 (Beast AOE), VFX-009 (Dragon cone), VFX-012 (hit screen warning), VFX-013 (low HP warning), VFX-015 (death grayscale), VFX-016/017 (wave text) |
| LOW | VFX-004 (form aura), VFX-010 (human attack), VFX-020 (meter glow), VFX-022 (enemy death) |
| LOWEST | VFX-021 (dust) |

### Architecture Diagram

```
VFXSystem (Autoload #11)
│
├── CanvasLayer #1 — VFX_World (world-space particles)
│   ├── ParticlePoolManager — 4 pools
│   │   ├── attack_hit        (50 CpuParticles2D)
│   │   ├── transform_burst   (80 CpuParticles2D)
│   │   ├── form_aura         (30 CpuParticles2D, persistent emitter)
│   │   └── dust              (10 CpuParticles2D)
│   └── Enemy death + form fade particles (temporary)
│
├── CanvasLayer #2 — VFX_Screen (screen-space effects)
│   ├── ParticlePoolManager — 2 pools
│   │   ├── death_dissolve    (60 CpuParticles2D)
│   │   └── form_fade_out     (40 CpuParticles2D)
│   ├── _flash_color_rect     (ColorRect — reused, no allocation)
│   ├── _low_hp_texture       (NinePatchRect — pre-rendered, no per-frame repaint)
│   └── Wave text labels      (pre-created Labels, faded in/out via Tween)
│
├── CanvasLayer #5 — VFX_Overlay (above HUD, above everything)
│   ├── _tear_overlay         (ColorRect × 4 — pixel row replacement for transform tear)
│   ├── Death dissolve overlay (character pixel disintegration)
│   └── Death grayscale       (full-screen ColorRect with desaturation)
│
├── VFXCatalog (data-driven dispatch)
│   └── maps (trigger, state, form_id) → VFXEntry[]
│
├── _process(delta) — only when active VFX present
│   ├── Flash timer tick
│   ├── Aura configuration (on mode switch only)
│   ├── Death dissolve progress
│   └── Low HP warning alpha update
│
└── Performance
    ├── All 270 CpuParticles2D pre-allocated in _ready()
    ├── Screen flash: modulate on existing ColorRect (zero nodes)
    ├── Low HP vignette: pre-rendered 9-slice (zero per-frame draw)
    ├── _process() returns immediately when _active_vfx.is_empty()
    └── Max 150 simultaneous visible particles enforced by pool recycle
```

### GL Compatibility Constraints Handling

| Constraint | Impact | Solution |
|------------|--------|----------|
| No GPU particles | CpuParticles2D only | All 270 particles use CpuParticles2D. Per-particle emit via `emit_particle()` (Godot 4.4+). |
| No screen-reading shaders | Can't use `hint_screen_texture` for dissolve effects | Death dissolve: manual pixel-block ColorRect removal (not shader-based). Death grayscale: full-screen ColorRect overlay with desaturated modulate (not saturation shader). |
| Limited CanvasItem shader features | Pixel tear may need fallback | Primary: CanvasItem shader with `UV` row replacement. Fallback: 4 pre-rendered sprite frames swapped per frame. |
| Nearest-neighbor filter required | All particle sprites must use filter | Set `texture_filter = TEXTURE_FILTER_NEAREST` on all CpuParticles2D nodes in _ready(). |

## Alternatives Considered

### Alternative 1: Per-system VFX (each system spawns its own particles)

- **Description**: PlayerSystem spawns attack particles. EnemySystem spawns death particles. GSM spawns transition flashes.
- **Pros**: No VFXSystem Autoload. Each system's VFX is co-located with its trigger.
- **Cons**: Pool management duplicated across systems. Z-ordering conflicts between systems' particles. No unified priority resolution — PlayerSystem's attack particles and GSM's death flash can't coordinate rendering order. VFX intensity settings require touching every system.
- **Rejection Reason**: Same as HUD — centralization is the point. 22 VFX entries across 7 signal sources need a single arbiter for pools, priorities, and Z-order.

### Alternative 2: GPU particles (Godot 4.6 Vulkan/Forward+ renderer)

- **Description**: Use `GpuParticles2D` for all particles. GPU-accelerated, supports thousands of simultaneous particles.
- **Pros**: Dramatically higher particle ceiling. More visual fidelity (smooth gradients, larger sprites). Simpler pool management (larger pools, less exhaustion risk).
- **Cons**: Requires Forward+ or Mobile renderer. GL Compatibility — required for Web export — does not support GPU particles. Switching to Forward+ would block the Web platform target.
- **Rejection Reason**: Web export is a stated platform target (CLAUDE.md). GL Compatibility is the only Web-compatible renderer. CpuParticles2D at 150 cap is sufficient for the pixel-art aesthetic (particles are 2×2/4×4 px — even 150 is visually dense for this art style).

### Alternative 3: VFX as AnimationPlayer-driven sprite sequences (no particles)

- **Description**: All visual effects are pre-rendered sprite sheet animations played via AnimationPlayer nodes. No runtime particle simulation.
- **Pros**: Deterministic, frame-perfect visuals. No physics-based particle variance. Easier to art-direct (every frame is hand-crafted).
- **Cons**: Every VFX variation (e.g., attack at 5 different angles, burst at 3 sizes) needs pre-rendered frames. Explodes sprite sheet count. Loses organic variance — every attack looks identical. Cannot respond to dynamic parameters (direction, speed, position) without massive sprite sheet matrix.
- **Rejection Reason**: The VFX catalog's 22 entries × multiple direction/position variations would require hundreds of pre-rendered sprite sheets. CpuParticles2D provides organic variance with a single small sprite per particle type.

## Consequences

### Positive

- **Single dispatch point**: All VFX flow through `_dispatch_vfx(trigger, context)`. Adding a VFX entry = one catalog row. All pool, priority, and intensity concerns handled centrally.
- **Zero node allocation during gameplay**: All 270 CpuParticles2D pre-allocated. Screen flash reuses one ColorRect. Low HP vignette reuses one NinePatchRect. Per ADR-0003.
- **CanvasLayer isolation**: VFX_World (1) particles never obscure HUD_Core (3). VFX_Overlay (5) effects intentionally cover everything for transformation/death moments. Z-order is deterministic per ADR-0002.
- **Intensity settings interface**: `set_intensity(FULL/REDUCED/OFF)` gates all VFX dispatch. Settings system (VS) controls this with one method call. REDUCED mode halves particle counts and skips screen flashes. OFF mode preserves only gameplay-critical feedback (hit flash).
- **GL Compatibility safe**: All rendering paths verified against GL Compatibility constraints. No GPU particles, no screen-reading shaders, no post-processing.

### Negative

- **CpuParticles2D limit**: 150 simultaneous visible particles. Dense combat (Berserk + 50 enemies dying + wave text) could hit this cap. **Accepted cost**: The pixel-art aesthetic uses small particles (2×2/4×4 px). 150 of these on screen is visually very dense. Pool exhaustion recycles oldest — visual quality degrades gracefully, not catastrophically.
- **emit_particle() requires Godot 4.4+**: If the project downgrades engine versions, per-particle burst emission must fall back to `one_shot = true` + `amount` + `emitting = true`. Less precise control. **Accepted cost**: Godot 4.6 is pinned. 4.4+ API is safe to use.
- **Pixel tear shader fallback**: If GL Compatibility CanvasItem shader can't do UV row replacement, fallback to 4 pre-rendered frames. This adds 4 sprite assets per form (8 total for Beast + Dragon). **Accepted cost**: 8 small sprite assets (32×32 × 4 frames × 2 forms ≈ 16 KB).

### Risks

- **Risk: 150 particle cap hit during Berserk + wave clear + 10 simultaneous enemy deaths**: Attack particles (15) + aura (30) + berserk pulse particles (15) + enemy deaths (10 × 8 = 80) + wave text particles = ~140. Near cap. **Mitigation**: Pool recycling with priority-aware victim selection. Enemy death particles (LOW priority) are recycled before attack particles (MEDIUM) or transform burst (HIGH). Worst case: some enemy death particles don't spawn — players rarely notice missing enemy death particles during intense combat.
- **Risk: CanvasLayer.modulate flash causes draw call spike**: Full-screen ColorRect with modulate change may trigger a full-screen redraw. **Mitigation**: The ColorRect is a single node with a solid color — no texture. modulate change = one uniform update. Godot batches this efficiently. If profiling shows a spike, replace with a shader-based `canvas_item_set_modulate` call.
- **Risk: emit_particle() function signature changes in Godot 4.6**: The API was introduced in 4.4 and may have been refined in 4.5/4.6. **Mitigation**: Wrap `emit_particle()` call in a VFXSystem method `_emit_single_particle(pool, config)`. If the API changes, only one call site needs updating.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| vfx-system.md | Rule 1: Signal-driven pure response system | All VFX dispatched via `_dispatch_vfx(trigger, context)` from signal handlers. VFXSystem never calls upstream logic methods. |
| vfx-system.md | Rule 2: 3-layer CanvasLayer rendering | Per ADR-0002: VFX_World (layer 1), VFX_Screen (layer 2), VFX_Overlay (layer 5). GDD's internal "Layer 1/2/3" maps to these. |
| vfx-system.md | Rule 3: Particle pool management (6 pools) | ParticlePoolManager per ADR-0003 with GDD-specified pool sizes: attack=50, burst=80, aura=30, dust=10, dissolve=60, fade_out=40. |
| vfx-system.md | Rule 4: Pixel art constraints (no post-processing, nearest-neighbor, 90°/180° rotation) | All CpuParticles2D nodes set `texture_filter = NEAREST`. Particle sprites are 2×2/4×4 px. No shader post-effects. |
| vfx-system.md | Rule 5: Form geometric motif (Beast=circle/arc, Dragon=triangle) | Particle sprite selection from FormConfig.geometric_motif. Beast particles use 3×1px arc sprites. Dragon particles use 4×4px triangle sprites. |
| vfx-system.md | Rule 6: Form color theme (Beast=#FF6B35, Dragon=#C44B8B) | modulate set to FormConfig.primary_color on all particles for that form. Screen flash color reads from same config. |
| vfx-system.md | Rule 7: Character readability protection | All VFX particles render on CanvasLayer 1 (below HUD_Core layer 3). VFX_Overlay (layer 5) intentionally covers everything for transformation/death. |
| vfx-system.md | Rule 8: Performance — ≤150 particles, CanvasLayer.modulate for flash, 9-slice for vignette | Pool sizes total 270 with active cap enforced by recycle. Flash uses single ColorRect.modulate. Vignette uses pre-rendered NinePatchRect. |
| vfx-system.md | VFX Catalog: 22 entries across 8 categories | VFXCatalog maps (trigger, state, form_id) → VFXEntry. Each entry specifies layer, priority, particle/flash config, duration. |
| vfx-system.md | Priority resolution (5 tiers) | VFXPriority enum (LOWEST→HIGHEST). `_resolve_z_order()` sorts by priority then timestamp. |
| vfx-system.md | Pool exhaustion: recycle oldest, skip if highest priority | pool.recycle_oldest(priority) — skips particles at HIGHEST priority. Drops request if all are HIGHEST. |
| vfx-system.md | VFX intensity settings (FULL/REDUCED/OFF) | `set_intensity(level)` gates dispatch. REDUCED halves particles, skips flash. OFF preserves only player_hit and player_died. |
| vfx-system.md | Death dissolve (VFX-014) + grayscale (VFX-015) | Pixel-block removal inward at 16 px/s. Grayscale via full-screen ColorRect desaturation overlay. |
| hud-ui-system.md | Low HP warning coordination | VFX-013 renders on CanvasLayer 2 (below HUD). Alpha ≤ 0.35 ensures HUD readability. HUD's own low HP label is on CanvasLayer 3. |

## Performance Implications

- **CPU**: Idle frames (no VFX active): one boolean check in `_process()` → return (< 0.001ms). Active frames (combat): particle emit calls + flash tick + aura config = 0.05-0.1ms. Peak frames (transformation + 50 enemies): burst emit (40 particles) + aura update + flash sequence ≈ 0.2ms. Well under 1ms/frame budget.
- **Memory**: 270 CpuParticles2D × ~200 bytes = 54 KB. Particle sprites (6 types × 2×2/4×4 px) ≈ 1 KB. ColorRect × 4, NinePatchRect × 1 ≈ 2 KB. Total ≈ 57 KB.
- **Load Time**: 270 CpuParticles2D pre-allocated in _ready(). 6 particle sprite textures loaded. Estimated 5-10ms at boot — acceptable.

## Migration Plan

N/A — VFXSystem is created fresh.

## Validation Criteria

- GSM CHARGING → TRANSFORMATION → VFX-001 flash (0.3s form-color → 0.2s white → 0.2s black → 0.3s fade-out) + VFX-003 particle burst (40 particles outward)
- PlayerSystem.player_hit → VFX-011 (1-frame white flash on character) + VFX-012 (screen edge red flash 0.4s)
- PlayerSystem.damage_dealt while Beast active → VFX-008 (15 orange arc particles, 96px radius burst)
- PlayerSystem.damage_dealt while Dragon active → VFX-009 (12 purple triangle particles, 60° cone)
- GSM TRANSFORMATION → COOLDOWN → VFX-005 (reverse tear 3 frames + 20 fade-out particles)
- GSM → DEATH → VFX-014 (pixel dissolve inward 16 px/s) + VFX-015 (grayscale overlay)
- All 6 particle pools pre-allocated → pool.acquire() never allocates at runtime
- Pool exhaustion: 51st attack particle request → oldest LOW-priority particle recycled
- VFX intensity set to OFF → only player_hit and player_died VFX still trigger
- `get_active_particle_count()` ≤ 150 at all times
- Screen flash uses existing ColorRect — zero nodes created during flash sequence

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — VFXSystem is Autoload #11, Presentation layer
- ADR-0002: CanvasLayer Z-Ordering — VFX owns layers 1 (VFX_World), 2 (VFX_Screen), 5 (VFX_Overlay)
- ADR-0003: Object Pooling Architecture — ParticlePoolManager with 6 pools / 270 CpuParticles2D
- ADR-0004: Signal Bus Pattern — VFX subscribes to upstream signals per ADR-0004 patterns
- ADR-0007: GSM State Machine — state_changed drives transformation/death VFX sequences
- ADR-0012: Player System Architecture — player_hit, damage_dealt, player_died signals
- ADR-0009: Transformation System Architecture — transformation_started/expired, berserk signals
- ADR-0011: Wave System Architecture — wave_started/cleared, boss_wave_started, all_waves_cleared
- ADR-0014: HUD/UI System Architecture — Z-order coordination (VFX layer 2 below HUD layer 3)
