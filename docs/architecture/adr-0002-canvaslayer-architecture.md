# ADR-0002: CanvasLayer Rendering Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Rendering |
| **Knowledge Risk** | LOW — CanvasLayer is a stable Godot 2D feature with no breaking changes in 4.4–4.6 |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/modules/rendering.md`, `docs/engine-reference/godot/modules/ui.md` |
| **Post-Cutoff APIs Used** | None — CanvasLayer `layer` property and `modulate` are pre-4.0 stable APIs |
| **Verification Required** | Verify GL Compatibility renderer supports CanvasLayer `modulate` for full-screen color overlay (VFX flash fallback) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — HUD and VFX are separate Autoloads that must share rendering layers |
| **Enables** | HUD system implementation, VFX system implementation |
| **Blocks** | HUD stories, VFX stories — cannot implement rendering without the layer stack defined |
| **Ordering Note** | Must be Accepted before any HUD or VFX rendering code is written |

## Context

### Problem Statement

The HUD/UI GDD defines 4 visual layers (Core, Overlay, Boss, Death) and the VFX GDD defines 3 visual layers (World, Screen, Overlay). These 7 conceptual layers from two separate systems must be combined into a single rendering stack where every element's Z-order relative to every other element is unambiguously defined. Two specific constraints make this non-trivial: (1) HUD elements must render above VFX screen effects to ensure UI readability, but (2) VFX overlay effects (transform tear, death dissolve) must render above HUD to deliver their full-screen impact.

### Constraints

- Godot 4.6 + GDScript + GL Compatibility renderer
- No post-processing (per art bible Section 9)
- Pixel art with nearest-neighbor filtering
- 60 fps target with ≤ 150 simultaneous particles
- VFX uses `CpuParticles2D` (GL Compatibility doesn't support GPU particles)
- CanvasLayer order must be consistent across all game states

### Requirements

- VFX world particles render in world space below characters
- VFX screen effects (flash, HP warning) render in screen space below HUD
- HUD elements are always readable above VFX screen effects
- VFX overlay effects (transform tear, death dissolve, form aura) cover everything including HUD
- No system creates CanvasLayers belonging to another system

## Decision

**A unified 6-layer CanvasLayer stack with explicit ownership per system.**

Every CanvasLayer is owned by exactly one Autoload system. Layers are ordered by the Godot `CanvasLayer.layer` property (integer Z-index), not by node tree order. The stack is:

| Layer Z | CanvasLayer Name | Owner | Content | Coordinate Space |
|---------|-----------------|-------|---------|-----------------|
| 0 | (default) | Game World | TileMap, characters, enemies | World |
| 1 | `VFX_World` | VFX | Attack particles, enemy death particles, move dust | World |
| 2 | `VFX_Screen` | VFX | Screen flash, HP warning red gradient, wave prompt text, meter glow | Screen |
| 3 | `HUD_Core` | HUD | HP bar, form meter, duration/cooldown bar, transform prompt, berserk indicator | Screen |
| 4 | `HUD_Overlay` | HUD | Wave progress text, remaining enemies, Boss HP bar, death screen | Screen |
| 5 | `VFX_Overlay` | VFX | Transform pixel tear, form aura, death pixel dissolve, berserk overlay | Screen |

### Architecture Diagram

```
Screen (top)
┌─────────────────────────────────────────┐
│ VFX_Overlay (layer 5)                   │ ← Transform tear, death dissolve
│   covers EVERYTHING including HUD       │
├─────────────────────────────────────────┤
│ HUD_Overlay (layer 4)                   │ ← Wave info, Boss HP, Death screen
├─────────────────────────────────────────┤
│ HUD_Core (layer 3)                      │ ← HP bar, form meter, timers
├─────────────────────────────────────────┤
│ VFX_Screen (layer 2)                    │ ← Screen flash, HP warning red edge
├─────────────────────────────────────────┤
│ VFX_World (layer 1)                     │ ← Particles in world space
├─────────────────────────────────────────┤
│ Game World (default layer 0)            │ ← TileMap, characters, enemies
└─────────────────────────────────────────┘
Screen (bottom)
```

### Key Interfaces

**Each CanvasLayer is created in its owner system's `_ready()`:**

```gdscript
# VFX system _ready()
var vfx_world_layer := CanvasLayer.new()
vfx_world_layer.layer = 1
vfx_world_layer.name = "VFX_World"
add_child(vfx_world_layer)

var vfx_screen_layer := CanvasLayer.new()
vfx_screen_layer.layer = 2
vfx_screen_layer.name = "VFX_Screen"
add_child(vfx_screen_layer)

var vfx_overlay_layer := CanvasLayer.new()
vfx_overlay_layer.layer = 5
vfx_overlay_layer.name = "VFX_Overlay"
add_child(vfx_overlay_layer)
```

```gdscript
# HUD system _ready()
var hud_core_layer := CanvasLayer.new()
hud_core_layer.layer = 3
hud_core_layer.name = "HUD_Core"
add_child(hud_core_layer)

var hud_overlay_layer := CanvasLayer.new()
hud_overlay_layer.layer = 4
hud_overlay_layer.name = "HUD_Overlay"
add_child(hud_overlay_layer)
```

**Layer ownership rules:**
- VFX creates and owns layers 1, 2, 5
- HUD creates and owns layers 3, 4
- No system adds children to another system's CanvasLayer
- Game World (layer 0) is the default scene root — no explicit CanvasLayer needed

**Inter-system coordination constants** (defined in DataConfig or a shared constants file):
```gdscript
const LAYER_VFX_WORLD   := 1
const LAYER_VFX_SCREEN  := 2
const LAYER_HUD_CORE    := 3
const LAYER_HUD_OVERLAY := 4
const LAYER_VFX_OVERLAY := 5
```

### Rationale for Specific Ordering

- **VFX_World (1) above Game World (0) but below characters**: Particles render in world space behind the character layer. Characters are children of the scene root (layer 0) and their visual Z-index within layer 0 places them above VFX_World particles. This satisfies the art bible's "1px character outline always visible" constraint.
- **VFX_Screen (2) below HUD_Core (3)**: Screen flash and HP warning red gradient must not obscure the HP bar and form meter. The HUD GDD explicitly states "低 HP 警告的红色渐变在 HUD 元素下层."
- **VFX_Overlay (5) above HUD_Overlay (4)**: Transform tear and death dissolve are brief full-screen effects that intentionally cover HUD. The VFX GDD specifies "覆盖所有其他渲染，包括 UI" for Layer 3 Overlay VFX. These effects are short-lived (< 2s) and signal major state transitions where HUD readability is temporarily deprioritized.

## Alternatives Considered

### Alternative 1: Single CanvasLayer per System (2 total layers)

- **Description**: HUD owns one CanvasLayer, VFX owns one. All VFX renders on one layer, all HUD on the other. HUD always above VFX.
- **Pros**: Simpler setup, fewer layers to manage
- **Cons**: Cannot place VFX overlay effects above HUD while keeping VFX screen effects below HUD. Transform tear would render BELOW the HP bar — reducing its impact. The VFX GDD explicitly requires overlay effects to cover UI.
- **Rejection Reason**: Doesn't satisfy the VFX GDD's Layer 3 requirement (overlay covers everything including UI).

### Alternative 2: All 7 conceptual layers as separate CanvasLayers

- **Description**: Each GDD-defined layer = one CanvasLayer (4 HUD layers + 3 VFX layers = 7).
- **Pros**: Maximum granularity; each layer from the GDDs maps 1:1 to a CanvasLayer
- **Cons**: HUD's 4 "layers" are actually logical groupings within one system, not rendering layers requiring separate CanvasLayers. Two HUD CanvasLayers (Core + Overlay) is sufficient to express the HUD's internal Z-ordering. Extra layers add node overhead with no benefit.
- **Rejection Reason**: Over-engineered. The HUD GDD's 4 layers are logical groupings — separating them into 4 CanvasLayers adds complexity without improving rendering order.

## Consequences

### Positive

- **Unambiguous Z-order**: Every pixel on screen has a defined layer. No "which CanvasLayer renders on top?" questions during implementation.
- **Single-owner discipline**: Each CanvasLayer has exactly one owning system. No cross-system node parenting confusion.
- **GDD-aligned**: The stack directly fulfills HUD GDD Rule 3 (CanvasLayer architecture) and VFX GDD Rule 2 (3-layer rendering architecture).
- **Extensible**: Adding a new layer (e.g., Tutorial overlay in Vertical Slice) = pick an unused Z-index, add one CanvasLayer in the owning system. No reordering of existing layers.

### Negative

- **5 CanvasLayers create 5 draw calls**: Each CanvasLayer is a separate draw pass in GL Compatibility. Acceptable for 2D pixel art — total draw call count remains well within budget.
- **Layer Z constants must be shared**: HUD and VFX need to agree on layer Z numbers. Mitigated by a shared constants file (autoloaded DataConfig or a dedicated `LayerConstants` singleton).

### Risks

- **Risk: VFX_Overlay covers HUD during critical UI moments**: If a transform tear lasts too long or triggers during a UI interaction, the HUD becomes temporarily unreadable. **Mitigation**: VFX_Overlay effects are short-lived (< 2s) and only trigger on state transitions — never during upgrade selection or pause menu. The HUD GDD's visibility rules already hide most UI during TRANSFORMATION state.
- **Risk: CanvasLayer `layer` property misinterpreted**: Godot's `layer` property is a bitmask for `VisualServer.canvas_layer_set_layer()`, not a simple Z-index. Using `layer = 5` actually sets bit 5 (value 32), which still orders correctly (higher bits render on top). **Mitigation**: Document this in code comments. The pattern works correctly as long as all layers use powers of 2 (1, 2, 4, 8, 16, 32) or sequential integers (the rendering order is by integer value, not bit position).

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| hud-ui-system.md | Rule 3: CanvasLayer architecture — 3 rendering layers | HUD_Core (layer 3) + HUD_Overlay (layer 4). HUD GDD's 4 logical layers map to 2 CanvasLayers with internal Z-ordering via node order |
| vfx-system.md | Rule 2: 3-layer rendering (World/Screen/Overlay CanvasLayers) | VFX_World (layer 1) + VFX_Screen (layer 2) + VFX_Overlay (layer 5). Direct mapping of GDD layers to CanvasLayers |
| vfx-system.md | Rule 7: Character readability — VFX particles Z-order below character | VFX_World (layer 1) is below character rendering in Game World (layer 0). Characters render on top of world particles |
| hud-ui-system.md | Interactions: HUD elements Z-order above VFX Layer 2 | HUD_Core (layer 3) > VFX_Screen (layer 2). HUD text always readable above screen flash and HP warning |
| vfx-system.md | Layer 3 description: "覆盖所有其他渲染，包括 UI" | VFX_Overlay (layer 5) is the topmost layer, above HUD_Overlay (layer 4) |
| art-bible.md | Section 9: No post-processing | All effects use CanvasLayer modulate (color overlay) + CpuParticles2D + 9-slice TextureRect — no shader-based post-processing |

## Performance Implications

- **CPU**: 5 CanvasLayer nodes — negligible overhead (< 0.1ms/frame total for layer sorting)
- **GPU**: Each CanvasLayer is a separate 2D draw pass. For a pixel art game with < 100 draw calls/frame, 5 layers add no measurable GPU cost
- **Memory**: 5 CanvasLayer nodes ≈ 5 KB

## Migration Plan

N/A — this is the second architectural decision. No existing rendering code to migrate.

## Validation Criteria

- All 5 CanvasLayers render in the correct Z order: Game World → VFX_World → VFX_Screen → HUD_Core → HUD_Overlay → VFX_Overlay
- HUD HP bar and form meter are visible above VFX screen flash during gameplay
- VFX transform tear covers HUD elements during the TRANSFORMATION state transition
- VFX world particles render behind the player character sprite
- No system adds children to another system's CanvasLayer

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — HUD and VFX are separate Autoloads that own their respective CanvasLayers
