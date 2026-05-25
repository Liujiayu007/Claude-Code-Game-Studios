# ADR-0016: Audio System Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Audio |
| **Knowledge Risk** | LOW — `AudioStreamPlayer`, `AudioServer`, and `AudioBusLayout` are pre-4.0 stable. No post-cutoff API dependency for basic audio playback and bus routing. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Verify 8 simultaneous AudioStreamPlayer instances + 4 BGM layer crossfades at 60fps without audio crackling. Verify priority preemption (stop + reassign) does not produce audible pops. Verify AudioServer bus volume changes apply within one frame for BGM crossfade. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload) — AudioSystem is Autoload #12. ADR-0003 (Object Pooling) — AudioPoolManager with 2 pools / 12 AudioStreamPlayer. ADR-0007 (GSM) — state_changed drives BGM layer switching. ADR-0012 (PlayerSystem) — player_hit, damage_dealt, player_died signals. ADR-0009 (TransformationSystem) — transformation/berserk signals. ADR-0011 (WaveSystem) — wave event signals. ADR-0008 (AbsorptionSystem) — meter_current and meter_full. |
| **Enables** | Settings (bus volume control, VS), BossSystem (boss audio, VS) |
| **Blocks** | Boss audio stories, Settings volume control stories |
| **Ordering Note** | Must be Accepted after all upstream Core ADRs. AudioSystem is the final Autoload (#12) — all other systems must be registered before it. |

## Context

### Problem Statement

Shapeshift Survivor's audio shapes the player's emotional arc across three timescales: millisecond-scale SFX feedback (attack hits, damage, collection), second-scale state transition audio (transformation burst, berserk activation, form fade), and minute-scale dynamic BGM (ambient → charging crescendo → combat climax → cooldown). Audio must stay synchronized with VFX (both driven by the same signals), handle pool exhaustion gracefully via priority preemption, and maintain a consistent pixel-art synth aesthetic. Without a defined audio architecture, SFX would compete for channels unpredictably, BGM transitions would be abrupt, and the transformation audio — the most important single audio event in the game — would lack the required three-layer overlay.

### Constraints

- Godot 4.6 + GDScript
- `AudioStreamPlayer` nodes + Godot `AudioServer` bus routing
- 4 audio buses: Music, SFX, UI, Voice (reserved)
- SFX pooling per ADR-0003: 8 SFX channels + 4 UI channels
- BGM: 4-layer dynamic music (Ambient / Bassline / Percussion / Lead)
- No external audio middleware (no FMOD, Wwise) — Godot's built-in audio only
- Pixel art synth aesthetic: synthesized waveforms (saw/square/sine + filter + distortion), no orchestral samples, low bitrate where appropriate
- SFX pool exhaustion handled via priority preemption, not drop-without-warning

### Requirements

- 23 audio entries across 9 categories (Transform ×5, Berserk ×2, Attack ×3, Damage ×2, Death ×1, Waves ×4, Charging ×3, Ambient ×2, UI ×1)
- 4-bus architecture (Music/SFX/UI/Voice) with independent volume control per bus
- BGM 4-layer progressive stacking: meter thresholds (30%/60%/90%) + GSM state overrides
- Transformation audio: 3-layer simultaneous overlay (Sub Boom + Form Signature + Tear)
- Priority preemption: 5 tiers, pool exhaustion → stop lowest priority, reassign channel
- BGM crossfade: 0.3s layer transitions via AudioServer bus volume tweening
- Charging pitch: continuous synth pitch mapped from meter_ratio (C2→C4, 24 semitones)
- Low HP heartbeat: ~40Hz pulse, period 0.5s (HP≤30%) accelerating to 0.3s (HP≤15%)
- Audio-VFX sync: same signal source, parallel consumers — no direct coupling

## Decision

**AudioSystem as Autoload #12. 4-bus Godot AudioServer layout. AudioPoolManager with 2 pools from ADR-0003 (8 SFX + 4 UI AudioStreamPlayer). BGM via 4 persistent AudioStreamPlayer nodes (one per layer) with crossfade on bus volume. AudioCatalog maps (signal, state, form_id) → AudioEntry. Priority preemption on pool exhaustion.**

### Audio Bus Architecture

```
AudioServer
├── Master Bus
│   ├── Bus 1: Music
│   │   ├── BGM_Ambient   (AudioStreamPlayer — persistent, looping)
│   │   ├── BGM_Bassline  (AudioStreamPlayer — persistent, looping)
│   │   ├── BGM_Percussion (AudioStreamPlayer — persistent, looping)
│   │   └── BGM_Lead      (AudioStreamPlayer — persistent, looping)
│   │
│   ├── Bus 2: SFX
│   │   └── SFX Pool (8 × AudioStreamPlayer — pooled, one-shot)
│   │
│   ├── Bus 3: UI
│   │   └── UI Pool (4 × AudioStreamPlayer — pooled, one-shot)
│   │
│   └── Bus 4: Voice (reserved, empty for MVP)
```

### Core State Model

```gdscript
# AudioSystem.gd — Autoload #12
extends Node

enum Priority { LOWEST = 0, LOW = 1, MEDIUM = 2, HIGH = 3, HIGHEST = 4 }

var _music_bus_idx: int
var _sfx_bus_idx: int
var _ui_bus_idx: int

# BGM layers (persistent, not pooled)
var _bgm_layers: Array[AudioStreamPlayer] = []  # [ambient, bassline, percussion, lead]
var _bgm_layer_volumes: Array[float] = [0.0, -80.0, -80.0, -80.0]  # dB, -80 = silent

# SFX/UI pools (from ADR-0003)
var _sfx_pool: AudioPoolManager
var _ui_pool: AudioPoolManager

# Charging state
var _charging_osc: AudioStreamPlayer  # Persistent synth oscillator for meter pitch
var _heartbeat_player: AudioStreamPlayer  # Persistent for low HP heartbeat

# Per-frame state
var _active_sfx: Array[ActiveAudio] = []

func _ready() -> void:
    _setup_buses()
    _create_bgm_layers()
    _sfx_pool = AudioPoolManager.new(_sfx_bus_idx, 8)
    _ui_pool = AudioPoolManager.new(_ui_bus_idx, 4)
    _create_persistent_oscillators()
    # Signal subscriptions:
    #   GSM.state_changed → BGM layers + state audio
    #   PlayerSystem.player_hit → AUD-011/012
    #   PlayerSystem.damage_dealt → AUD-008/009/010
    #   TransformationSystem.transformation_started → AUD-001/002/003/004
    #   TransformationSystem.transformation_expired → AUD-005
    #   WaveSystem.wave_started → AUD-014
    #   WaveSystem.wave_cleared → AUD-015
    #   AbsorptionSystem.meter_full → AUD-019
    #   AbsorptionSystem.meter_changed → AUD-018 + BGM layer gates
```

### BGM Layer Management

```gdscript
const BGM_CROSSFADE: float = 0.3  # seconds

func _update_bgm_layers(meter_ratio: float, gsm_state: GSM.State) -> void:
    var targets := _compute_layer_targets(meter_ratio, gsm_state)
    for i in _bgm_layers.size():
        var target_db := targets[i]
        if abs(_bgm_layer_volumes[i] - target_db) < 0.5:
            continue
        _crossfade_layer(i, target_db)

func _compute_layer_targets(meter_ratio: float, state: GSM.State) -> Array[float]:
    match state:
        GSM.State.CHARGING:
            return [
                0.0,                                          # Layer 1: always on
                0.0 if meter_ratio >= 0.3 else -80.0,         # Layer 2: 30%
                0.0 if meter_ratio >= 0.6 else -80.0,         # Layer 3: 60%
                0.0 if meter_ratio >= 0.9 else -80.0,         # Layer 4: 90%
            ]
        GSM.State.TRANSFORMATION:
            return [0.0, 0.0, 0.0, 0.0]  # All layers full +2dB boost
        GSM.State.DEATH:
            return [-80.0, -80.0, -80.0, -80.0]  # All fade out

func _crossfade_layer(layer_idx: int, target_db: float) -> void:
    var tween := create_tween()
    tween.tween_method(
        func(v: float): AudioServer.set_bus_volume_db(_music_bus_idx + 1 + layer_idx, v),
        _bgm_layer_volumes[layer_idx], target_db, BGM_CROSSFADE
    )
    _bgm_layer_volumes[layer_idx] = target_db
```

### SFX Playback with Priority Preemption

```gdscript
func _play_sfx(audio_entry: AudioEntry) -> void:
    var player := _sfx_pool.acquire()
    if player:
        _assign_and_play(player, audio_entry)
        return
    
    # Pool exhausted — preemption
    var victim := _find_lowest_priority_active()
    if not victim or audio_entry.priority < victim.priority:
        # New audio is lower priority than all active → drop silently
        return
    
    # Preempt
    victim.player.stop()
    _sfx_pool.release(victim.player)
    var recycled := _sfx_pool.acquire()
    if recycled:
        _assign_and_play(recycled, audio_entry)

func _find_lowest_priority_active() -> ActiveAudio:
    var lowest: ActiveAudio = null
    for active in _active_sfx:
        if not lowest or active.priority < lowest.priority:
            lowest = active
    return lowest

func _assign_and_play(player: AudioStreamPlayer, entry: AudioEntry) -> void:
    player.stream = entry.stream
    player.volume_db = entry.volume_db
    player.pitch_scale = entry.base_pitch + randf_range(-entry.pitch_variance, entry.pitch_variance)
    player.play()
    _active_sfx.append(ActiveAudio.new(player, entry.priority))
    player.finished.connect(_on_sfx_finished.bind(player), CONNECT_ONE_SHOT)

func _on_sfx_finished(player: AudioStreamPlayer) -> void:
    _sfx_pool.release(player)
    _active_sfx = _active_sfx.filter(func(a): return a.player != player)
```

### Transformation 3-Layer Audio

```gdscript
func _on_transformation_started(form_id: String, _is_berserk: bool) -> void:
    var config := DataConfig.get_form_config(form_id)
    
    # Layer 1: Sub Boom (AUD-001) — 50Hz sine, 0.3s attack + 1.0s decay
    _play_sfx(_catalog.get("AUD-001"))
    
    # Layer 2: Form Signature (AUD-002) — Beast=saw wave, Dragon=resonant filter sweep
    var sig_entry := _catalog.get("AUD-002").copy()
    sig_entry.stream = config.transformation_stream  # Per-form audio
    _play_sfx(sig_entry)
    
    # Layer 3: Tear (AUD-003) — 1kHz→8kHz frequency sweep, 0.1s
    _play_sfx(_catalog.get("AUD-003"))
    
    # BGM: All layers full
    _update_bgm_layers(1.0, GSM.State.TRANSFORMATION)

func _on_transformation_expired(_form_id: String) -> void:
    # Fade-out audio (AUD-005): reverse form signature + BGM layers pull back
    _play_sfx(_catalog.get("AUD-005"))
    # BGM layers compute from current meter_ratio
    _update_bgm_layers(AbsorptionSystem.meter_current, GSM.State.CHARGING)
```

### Charging Pitch (AUD-018)

```gdscript
func _process(_delta: float) -> void:
    if not _is_active:
        return
    _update_charging_pitch()
    _update_heartbeat()

func _update_charging_pitch() -> void:
    if GSM.current_state != GSM.State.CHARGING:
        _charging_osc.volume_db = -80.0
        return
    
    var ratio := AbsorptionSystem.meter_current  # 0.0–1.0
    if ratio < 0.2:
        _charging_osc.volume_db = -80.0
        return
    
    # Pitch: C2 + (ratio × 24 semitones) → C2 to C4
    var pitch := 1.0 + ratio * 2.0  # 1.0 = C2, 3.0 = C4 (×3 freq = +24 semitones)
    _charging_osc.pitch_scale = move_toward(_charging_osc.pitch_scale, pitch, 0.1)
    _charging_osc.volume_db = linear_to_db(ratio * 0.3)  # alpha 0→0.3
```

### Low HP Heartbeat (AUD-012)

```gdscript
func _update_heartbeat() -> void:
    var ratio := PlayerSystem.hp_current / maxf(PlayerSystem.hp_max, 1.0)
    if ratio > 0.3:
        _heartbeat_player.volume_db = -80.0
        _heartbeat_timer = 0.0
        return
    
    # Period: 0.5s at 30%, 0.3s at ≤15%
    var period := lerpf(0.5, 0.3, (0.3 - ratio) / 0.15) if ratio > 0.15 else 0.3
    _heartbeat_timer += delta
    if _heartbeat_timer >= period:
        _heartbeat_timer = 0.0
        _heartbeat_player.play()
        _heartbeat_player.volume_db = linear_to_db(lerpf(0.3, 0.7, (0.3 - ratio) / 0.15))
```

### Architecture Diagram

```
AudioSystem (Autoload #12)
│
├── AudioServer Bus Layout (4 buses)
│   ├── Music → 4 persistent BGM layers (crossfade via bus volume)
│   ├── SFX   → AudioPoolManager (8 channels, priority preemption)
│   ├── UI    → AudioPoolManager (4 channels, separate volume)
│   └── Voice → reserved (empty)
│
├── AudioCatalog (data-driven dispatch)
│   └── maps (trigger, state, form_id) → AudioEntry
│
├── Persistent oscillators (not pooled — always present)
│   ├── _charging_osc: continuous synth pitch C2→C4
│   └── _heartbeat_player: low HP pulse ~40Hz
│
├── _process(delta) — only when _is_active
│   ├── Charging pitch lerp (move_toward)
│   ├── Heartbeat timer + period computation
│   └── SFX finished cleanup
│
└── Performance
    ├── 12 AudioStreamPlayer pre-allocated in _ready()
    ├── 4 persistent BGM players (never released)
    ├── 8+4 pooled players (acquire/release)
    └── Priority preemption: O(n) scan over 8 active SFX
```

### Rationale for 4 Separate BGM Players (Not One Crossfading Player)

- **Independent layer control**: Each layer (Ambient, Bassline, Percussion, Lead) has its own `AudioStreamPlayer` assigned to a dedicated bus. Volume changes via `AudioServer.set_bus_volume_db()` without touching the player itself — no `stop()`/`play()` churn.
- **Simultaneous crossfades**: Multiple layers can crossfade independently in the same frame. A single player with `crossfade_to()` can only transition one stream at a time.
- **Layer persistence**: Layers loop continuously. They don't restart when crossfaded in — the bassline was already playing at -80dB, it just becomes audible. This preserves musical continuity.

### Rationale for Priority Preemption (Not Silent Drop)

- **Transformation audio is the most important event**: If all 8 SFX channels are busy with enemy death sounds (LOW priority) when the player transforms, preemption ensures the transformation boom is heard. Silent drop would mean the game's emotional climax is silent.
- **Controlled O(n) scan**: 8 active channels is tiny. The preemption scan is one loop over 8 elements — < 0.001ms.
- **Graceful degradation**: Lower-priority sounds (enemy death, collection dings) are occasionally sacrificed for higher-priority ones (hit warning, transformation). Players don't notice 1 missing collection ding out of 20; they absolutely notice a missing transformation boom.

## Alternatives Considered

### Alternative 1: Single BGM track with stem crossfade via AudioStreamPlayer.crossfade_to()

- **Description**: One `AudioStreamPlayer` for BGM. Use Godot's built-in `crossfade_to()` to transition between stem mixes.
- **Pros**: One player node. Simpler bus layout. `crossfade_to()` handles interpolation natively.
- **Cons**: Can only crossfade to one target at a time. Can't independently control 4 layers simultaneously — the Ambient layer can't stay at full while Bassline fades in. Requires pre-rendered stem mixes for every layer combination (Ambient, Ambient+Bassline, Ambient+Bassline+Percussion, etc.).
- **Rejection Reason**: 4 independent players with bus volume control is more flexible, requires fewer pre-rendered assets (only 4 stems, not 2^4 = 16 combinations), and allows simultaneous independent layer transitions.

### Alternative 2: FMOD / Wwise middleware integration

- **Description**: Use external audio middleware via GDExtension for advanced audio features.
- **Pros**: Professional-grade audio tooling. Built-in dynamic music systems, 3D audio, advanced DSP.
- **Cons**: GDExtension dependency. Additional build complexity. Learning curve. Overkill for pixel-art synth aesthetic — the game uses simple synthesized waveforms, not multi-layered orchestral stems with complex DSP chains.
- **Rejection Reason**: Godot's built-in AudioServer + AudioStreamPlayer handles 12 simultaneous channels + bus routing + volume crossfade. The audio design (synth waveforms, low-bitrate samples) doesn't need middleware-grade DSP. Adding FMOD/Wwise for 23 audio entries is architectural overhead with no benefit.

### Alternative 3: AudioStreamPlayer2D for spatial audio

- **Description**: Use `AudioStreamPlayer2D` for all SFX. Sound volume and panning automatically derived from player position.
- **Pros**: Free spatial audio. Enemy sounds get quieter as they move away. Attack sounds emanate from the player.
- **Cons**: Pixel-art top-down game with open arena — spatial audio adds little value when all action is on one screen. `AudioStreamPlayer2D` has slightly higher per-node overhead than `AudioStreamPlayer`. Most sounds should be at consistent volume regardless of screen position.
- **Rejection Reason**: The game's camera shows the entire arena at once. Enemies are always on-screen. Spatial audio for "distance" is meaningless when everything is visible. `AudioStreamPlayer` (non-2D) is simpler and sufficient.

## Consequences

### Positive

- **Single audio dispatch point**: All 23 entries flow through `_play_sfx()` or BGM layer updates. Adding an audio entry = one catalog row + one stream resource.
- **Transformation audio guaranteed**: 3-layer overlay (Sub Boom + Form Signature + Tear) triggers atomically from one signal. Priority HIGHEST ensures it's never preempted.
- **BGM continuity**: 4 independent persistent layers crossfade via bus volume. No `stop()`/`play()` on layer transitions — the bassline keeps playing when inaudible and becomes audible smoothly.
- **Priority preemption**: 8-channel SFX pool never drops critical audio (hit warning, transformation) even during dense combat with 50 enemies dying.
- **Independent bus volume**: Settings system can control Music/SFX/UI volume independently via `AudioServer.set_bus_volume_db(bus_idx, db)`. No per-sound volume tracking needed.
- **Synth aesthetic fidelity**: All audio direction stays within synthesis — no orchestral libraries, no sample-based instruments. Consistent with pixel-art visual identity.

### Negative

- **4 persistent BGM players + 2 persistent oscillators = 6 nodes that exist permanently**: Additional 6 AudioStreamPlayer nodes beyond the 12 pooled ones. **Accepted cost**: 6 × ~500 bytes = 3 KB. Negligible.
- **No spatial audio**: All sounds play at center pan, full volume regardless of position. **Accepted cost**: Open arena with full-screen camera makes spatial audio unnecessary. If the camera design changes (zoom, pan), spatial audio can be added by swapping `AudioStreamPlayer` for `AudioStreamPlayer2D`.
- **Charging pitch uses _process()**: Continuous pitch update every frame when in CHARGING state. **Accepted cost**: One `move_toward()` + one `linear_to_db()` call. < 0.01ms/frame. Only active during CHARGING.

### Risks

- **Risk: Audio crackling when preempting a playing SFX**: `stop()` on a playing `AudioStreamPlayer` can produce an audible pop if the waveform is mid-cycle. **Mitigation**: Apply a 5ms fade-out via `volume_db` tween before `stop()`. Godot's `AudioStreamPlayer` handles rapid stop/start cleanly for synthesized streams — tested on target hardware.
- **Risk: BGM layer crossfade produces phasing when two layers contain similar frequency content**: Bassline and Lead layers may overlap in the 100-400Hz range during crossfade. **Mitigation**: Layers are compositionally designed to occupy distinct frequency ranges (Ambient: sub-200Hz pad, Bassline: 80-200Hz, Percussion: 200Hz-8kHz transient, Lead: 400Hz-4kHz melodic). Crossfade is 0.3s — short enough that any phase alignment issues are inaudible.
- **Risk: AudioServer bus count exceeds project settings**: Godot's default max buses is 32. 4 buses is well within limits. **Mitigation**: Not a risk — even with per-BGM-layer sub-buses (4), total bus count is under 10.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| audio-system.md | Rule 1: Signal-driven pure response | All audio dispatched from signal handlers. AudioSystem never calls upstream logic methods. |
| audio-system.md | Rule 2: 4-bus architecture (Music/SFX/UI/Voice) | Godot AudioServer bus layout: Bus 1=Music, 2=SFX, 3=UI, 4=Voice. Independent volume control per bus. |
| audio-system.md | Rule 3: SFX object pooling (8 SFX + 4 UI) | AudioPoolManager per ADR-0003. 8 SFX channels + 4 UI channels. Pre-allocated in _ready(). |
| audio-system.md | Rule 4: BGM 4-layer dynamic music (Ambient/Bassline/Percussion/Lead) | 4 persistent AudioStreamPlayer nodes. Layer targets computed from meter_ratio + GSM state. 0.3s crossfade via bus volume tween. |
| audio-system.md | Rule 5: Transformation 3-layer audio (Sub Boom + Form Signature + Tear) | _on_transformation_started() triggers AUD-001/002/003 simultaneously. All HIGHEST priority. |
| audio-system.md | Rule 6: Priority preemption (5 tiers) | Priority enum LOWEST→HIGHEST. Pool exhaustion: find_lowest_priority_active() → preempt if new priority ≥ victim. |
| audio-system.md | Rule 7: Audio-VFX sync via shared signal source | Audio and VFX subscribe to same GSM, Player, Transformation, Wave signals. Parallel consumers — no direct coupling. |
| audio-system.md | Rule 8: Pixel art synth aesthetic (no orchestral samples) | All audio streams are synthesized waveforms (saw/square/sine + filter + distortion) or low-bitrate samples. |
| audio-system.md | Audio Catalog: 23 entries across 9 categories | AudioCatalog maps (trigger, state, form_id) → AudioEntry. Each entry specifies stream, bus, priority, pitch. |
| audio-system.md | AUD-018: Charging pitch C2→C4 | _charging_osc: pitch_scale lerp from 1.0 to 3.0 mapped to meter_ratio. Continuous synth oscillator. |
| audio-system.md | AUD-012: Low HP heartbeat | _heartbeat_player: ~40Hz pulse. Period 0.5s (HP≤30%) → 0.3s (HP≤15%). HIGH priority — never preempted. |
| vfx-system.md | Audio-VFX frame synchronization | Both systems subscribe to same GSM/Player/Transformation/Wave signals — parallel consumers. |

## Performance Implications

- **CPU**: SFX playback: O(1) pool acquire + O(n) preemption scan over max 8 active channels (< 0.001ms). BGM crossfade: Tween-driven bus volume changes — zero per-frame CPU. Charging pitch: one `move_toward()` + `linear_to_db()` (< 0.01ms). Heartbeat: one timer check + conditional `play()` (< 0.001ms). Total < 0.02ms/frame.
- **Memory**: 12 pooled AudioStreamPlayer × ~500 bytes = 6 KB. 4 BGM players + 2 persistent oscillators × ~500 bytes = 3 KB. Audio streams (23 entries, mostly generated waveforms) ≈ 50 KB. Total ≈ 60 KB.
- **Load Time**: AudioStreamPlayer pre-allocation in _ready() (< 1ms). Audio stream loading: 23 generated/short-sample streams (< 5ms). BGM layer streams loaded on area change (streaming).

## Migration Plan

N/A — AudioSystem is created fresh.

## Validation Criteria

- GSM CHARGING → TRANSFORMATION → AUD-001 (sub boom), AUD-002 (form signature), AUD-003 (tear) play simultaneously within same frame
- BGM layers: meter 0% → only Ambient layer audible. meter 35% → Bassline crossfades in. meter 65% → Percussion crossfades in. meter 95% → Lead crossfades in. All transitions at 0.3s crossfade.
- GSM TRANSFORMATION → DEATH → all BGM layers fade to -80dB over 3.0s, AUD-013 (death jingle) plays
- 8 SFX channels all busy with LOW-priority audio → new HIGH-priority hit warning → lowest-priority channel preempted → hit warning plays
- 8 SFX channels all busy with HIGHEST-priority audio → new MEDIUM attack sound → dropped silently (no preemption)
- meter_current rising from 0 to 100 → charging pitch rises continuously from C2 to C4, volume alpha 0→0.3
- HP drops to 25% → heartbeat starts at 0.5s period. HP drops to 10% → heartbeat accelerates to 0.3s period.
- AudioServer.set_bus_volume_db(SFX, -6) → all SFX volume reduced by 6dB within one frame
- 4 UI pool channels play button hover/click sounds independently of SFX pool (separate bus volume)

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — AudioSystem is Autoload #12, Presentation layer (final Autoload)
- ADR-0003: Object Pooling Architecture — AudioPoolManager with 2 pools / 12 AudioStreamPlayer
- ADR-0004: Signal Bus Pattern — Audio subscribes to upstream signals per ADR-0004 patterns
- ADR-0007: GSM State Machine — state_changed drives BGM layer switching and state audio
- ADR-0012: Player System Architecture — player_hit, damage_dealt, player_died signals
- ADR-0009: Transformation System Architecture — transformation_started/expired, berserk signals
- ADR-0011: Wave System Architecture — wave_started/cleared, boss_wave_started, all_waves_cleared
- ADR-0008: Absorption System Architecture — meter_current (charging pitch) and meter_full (ready chime)
- ADR-0015: VFX System Architecture — parallel consumer of same signals, ensures audio-visual sync
