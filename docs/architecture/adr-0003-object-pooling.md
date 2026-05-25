# ADR-0003: Object Pooling Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — Object pooling is a language-level pattern with no engine API dependencies. `CpuParticles2D` and `AudioStreamPlayer` are stable across all Godot 4.x versions. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/modules/rendering.md`, `docs/engine-reference/godot/modules/audio.md` |
| **Post-Cutoff APIs Used** | None — `CpuParticles2D` and `AudioStreamPlayer` are pre-4.0 stable classes |
| **Verification Required** | Profile pool exhaustion scenarios: verify recycle-oldest and priority-preemption behave correctly under max load |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — VFX and Audio are separate Autoloads, each owns its own pools |
| **Enables** | VFX particle system implementation, Audio SFX system implementation |
| **Blocks** | VFX stories (particle rendering), Audio stories (SFX playback) |
| **Ordering Note** | Must be Accepted before VFX or Audio system implementation begins |

## Context

### Problem Statement

VFX and Audio systems both need to manage pools of reusable nodes to avoid runtime allocation overhead. VFX has 6 particle pools totaling 270 `CpuParticles2D` nodes. Audio has 2 pools totaling 12 `AudioStreamPlayer` nodes. Both systems need the same core operations (acquire idle node, release back to pool, handle exhaustion), but they handle exhaustion differently: VFX recycles the oldest particle regardless of priority (with a HIGH-priority guard), while Audio uses a 5-tier priority preemption system.

### Constraints

- Godot 4.6 + GDScript + GL Compatibility renderer
- 60 fps target — no runtime `new()` or `queue_free()` calls during gameplay
- VFX: ≤ 150 simultaneous particles on screen (MVP performance cap per VFX GDD Rule 8)
- Audio: 8 concurrent SFX + 4 concurrent UI sounds maximum
- VFX GDD F.6: Pool exhaustion → recycle oldest particle; skip if all are HIGH priority
- Audio GDD Rule 6: Pool exhaustion → preempt lowest-priority active sound; drop if new request is lower priority than all active

### Requirements

- Pre-allocate all nodes in `_ready()` — zero runtime allocation
- Fixed pool sizes — no dynamic expansion in MVP
- Each pool is system-owned (VFX owns particle pools, Audio owns SFX pools)
- Exhaustion handling matches GDD specifications
- Pool managers are internal to their owning system — no cross-system pool sharing

## Decision

**Independent pool managers per system, unified interface contract.**

VFX implements a `ParticlePoolManager` for its 6 particle pools. Audio implements an `AudioPoolManager` for its 2 SFX pools. Both implement the same core interface but differ in exhaustion strategy. No shared base class or unified framework — the interface contract is conceptual, enforced by code review.

### Architecture Diagram

```
VFX Autoload                          Audio Autoload
├── ParticlePoolManager               ├── AudioPoolManager
│   ├── pool_attack (50)              │   ├── sfx_pool (8)
│   ├── pool_burst (80)               │   └── ui_pool (4)
│   ├── pool_aura (30)                │
│   ├── pool_dust (10)                │
│   ├── pool_death (60)               │
│   └── pool_cooldown (40)            │
│                                     │
│   Exhaustion: recycle oldest        │   Exhaustion: priority preemption
│   Guard: skip HIGH priority         │   Drop: if new < all active
```

### Key Interfaces

**Core pool interface (both systems implement):**

```gdscript
# acquire() → get an idle node from the pool
# Returns null if pool is exhausted and cannot recycle/preempt
func acquire() -> Node:
    for node in _pool:
        if not _is_active(node):
            _mark_active(node)
            return node
    return _handle_exhaustion()

# release(node) → return a node to the pool
func release(node: Node) -> void:
    _reset_node(node)
    _mark_idle(node)

# get_active_count() → current number of active (borrowed) nodes
func get_active_count() -> int:
    return _active_nodes.size()
```

**VFX ParticlePoolManager — exhaustion handling:**

```gdscript
func _handle_exhaustion() -> Node:
    # Find oldest active particle that is NOT HIGH priority
    var candidates := _active_nodes.filter(
        func(n): return n.priority != VFXPriority.HIGH
    )
    if candidates.is_empty():
        push_warning("[VFX] Pool %s exhausted — all HIGH priority, new request dropped" % _pool_name)
        return null
    
    var oldest := candidates.reduce(
        func(a, b): return a if a.elapsed_time > b.elapsed_time else b
    )
    _reset_node(oldest)
    return oldest
```

**Audio AudioPoolManager — exhaustion handling:**

```gdscript
func _handle_exhaustion(requested_priority: AudioPriority) -> Node:
    var lowest := _active_nodes.reduce(
        func(a, b): return a if a.priority < b.priority else b
    )
    if requested_priority >= lowest.priority:
        _stop_and_recycle(lowest)
        return lowest._player  # reuse the AudioStreamPlayer
    # New request is lower priority than everything active → drop
    return null
```

**Per-node metadata (attached by the pool manager, not subclassed):**

```gdscript
# VFX particle metadata
class ParticleMeta:
    var priority: VFXPriority
    var elapsed_time: float
    var lifetime: float

# Audio channel metadata
class AudioChannelMeta:
    var priority: AudioPriority
    var stream: AudioStream
```

### Pool Configuration (from GDDs)

**VFX Pools:**

| Pool ID | Node Type | Size | Exhaustion Strategy |
|---------|-----------|------|---------------------|
| attack | CpuParticles2D | 50 | Recycle oldest non-HIGH |
| burst | CpuParticles2D | 80 | Recycle oldest non-HIGH |
| aura | CpuParticles2D | 30 | Recycle oldest non-HIGH |
| dust | CpuParticles2D | 10 | Recycle oldest non-HIGH |
| death | CpuParticles2D | 60 | Recycle oldest non-HIGH |
| cooldown | CpuParticles2D | 40 | Recycle oldest non-HIGH |

**Audio Pools:**

| Pool ID | Node Type | Size | Exhaustion Strategy |
|---------|-----------|------|---------------------|
| sfx | AudioStreamPlayer | 8 | Priority preemption |
| ui | AudioStreamPlayer | 4 | First-idle (no preemption — UI sounds are "lowest" priority) |

### Rationale for Independent Managers (Not Unified Framework)

- **Different node types**: `CpuParticles2D` and `AudioStreamPlayer` share no common base class relevant to pooling. A generic `Pool<Node>` would need `[Node]` as a type parameter but couldn't call `particle.emitting = true` or `audio.play()` generically anyway.
- **Different exhaustion strategies**: VFX recycles oldest (temporal), Audio preempts lowest-priority (priority-based). Unifying these under one exhaustion handler would require an abstract strategy pattern — over-engineered for two implementations.
- **Solo developer reality**: Two ~50-line pool managers with clear, independent logic are easier to debug than one ~150-line generic pool manager with strategy injection.

## Alternatives Considered

### Alternative 1: Unified PoolManager base class

- **Description**: A single `PoolManager<T>` base class with configurable exhaustion strategy. VFX and Audio extend it.
- **Pros**: Code reuse — acquire/release logic written once; exhaustion strategy is a pluggable delegate
- **Cons**: GDScript doesn't support generics. Would need to use untyped `Node` arrays with runtime type checks — losing type safety without gaining real abstraction. The "shared" acquire/release logic is ~10 lines each.
- **Rejection Reason**: GDScript's lack of generics makes a unified base class more awkward than two simple independent implementations. The shared code is trivial — not worth the abstraction cost.

### Alternative 2: No pools — create/destroy nodes at runtime

- **Description**: Create `CpuParticles2D` and `AudioStreamPlayer` nodes on demand, `queue_free()` when done.
- **Pros**: Simplest code — no pool management. No fixed memory reservation.
- **Cons**: `new()` + `add_child()` during gameplay triggers node tree updates and potential GC. At 60 fps with up to 150 particles, this creates measurable frame spikes. The Audio module reference explicitly warns against this: "Creating new AudioStreamPlayer nodes at runtime is a common mistake."
- **Rejection Reason**: Performance is unacceptable for the target particle and SFX volumes. The VFX GDD explicitly mandates object pooling (Rule 3).

## Consequences

### Positive

- **No runtime allocation**: All nodes created in `_ready()`. No `new()` or `queue_free()` during gameplay — zero allocation stutter.
- **Predictable memory**: Fixed pool sizes = fixed memory footprint. Total: 270 CpuParticles2D + 12 AudioStreamPlayer ≈ 282 nodes, negligible memory.
- **GDD-aligned**: Exhaustion behavior matches VFX GDD F.6 and Audio GDD Rule 6 exactly.
- **Simple debug surface**: Each pool has a `get_active_count()` method. A debug overlay (future) can display pool utilization at a glance.

### Negative

- **Fixed capacity**: Pool sizes are hardcoded. If gameplay produces more simultaneous particles than expected, effects are dropped. **Mitigation**: Pool sizes were chosen from GDD analysis — 150 particle cap (VFX GDD Rule 8) is well below the 270 total pool capacity across all types.
- **Code duplication**: acquire/release logic exists in two files. **Accepted cost**: ~20 lines duplicated. Less harmful than a forced abstraction in a language without generics.

### Risks

- **Risk: Pool size too small for real gameplay**: The GDD-derived sizes are theoretical. Actual combat may produce more simultaneous particles. **Mitigation**: `push_warning()` on pool exhaustion makes this visible in development. If warnings appear frequently, increase pool sizes — a one-line constant change.
- **Risk: recycle-oldest produces visual pop**: When a particle is force-recycled mid-animation, it disappears abruptly. **Mitigation**: VFX GDD F.6 already prioritizes — HIGH priority particles are never recycled. MID and LOW priority particles being recycled mid-animation is visually acceptable (player is unlikely to notice one particle disappearing among 150).

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| vfx-system.md | Rule 3: Object pooling for 6 particle types with fixed sizes | VFX ParticlePoolManager with 6 configured pools matching GDD sizes |
| vfx-system.md | F.6: Pool exhaustion — recycle oldest, skip if all HIGH priority | `_handle_exhaustion()` filter + reduce logic in ParticlePoolManager |
| audio-system.md | Rule 3: SFX object pool (8 channels) + UI pool (4 channels) | Audio AudioPoolManager with sfx_pool and ui_pool |
| audio-system.md | Rule 6: Priority preemption on pool exhaustion | `_handle_exhaustion()` with priority comparison in AudioPoolManager |
| audio-system.md | Audio module reference: "Never create AudioStreamPlayer at runtime" | All AudioStreamPlayer nodes pre-allocated in `_ready()` |
| vfx-system.md | Rule 8: Performance — ≤ 150 simultaneous particles | Total pool capacity (270) exceeds the 150 cap. Pool exhaustion is the safety valve |

## Performance Implications

- **CPU**: Pool acquire/release is O(n) where n = pool size (worst case 80 for VFX burst pool). At 60 fps with 150 active particles, the total scan cost is < 0.05ms per frame — negligible.
- **Memory**: 282 total pooled nodes. Each CpuParticles2D ≈ 200 bytes (node + empty particle data). Each AudioStreamPlayer ≈ 150 bytes. Total ≈ 55 KB.
- **Load Time**: All 282 nodes created in `_ready()` across VFX and Audio Autoloads. Node creation is sub-millisecond for this volume.

## Migration Plan

N/A — pools are created fresh in VFX and Audio system `_ready()`. No existing code to migrate.

## Validation Criteria

- All 8 pools (6 VFX + 2 Audio) pre-allocate nodes in `_ready()` — no `new()` calls during gameplay
- VFX pool exhaustion recycles the oldest non-HIGH priority particle
- VFX pool exhaustion drops request when all active particles are HIGH priority (logs warning)
- Audio pool exhaustion preempts lowest-priority active sound when new request has higher or equal priority
- Audio pool exhaustion drops request when new priority < all active priorities
- No `queue_free()` called on any pooled node during gameplay
- `get_active_count()` returns correct count for each pool at any frame

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — VFX and Audio are separate Autoloads that own their pools
- ADR-0002: CanvasLayer Rendering Architecture — VFX particles render on specific CanvasLayers owned by the VFX Autoload
