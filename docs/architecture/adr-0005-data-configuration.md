# ADR-0005: Data Configuration Architecture

## Status
Accepted

## Date
2026-05-24

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — `@export var` and Custom Resources are pre-4.0 stable features. No API changes in 4.4–4.6 that affect this pattern. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`, `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None — `@export` annotations and Resource loading are pre-4.0 stable |
| **Verification Required** | Verify `@export var` Dictionary type hint syntax works in Godot 4.6 GDScript (typed Dictionaries in exports were stabilized in 4.3) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (Autoload Architecture) — DataConfig is Autoload #1, must load before all other systems |
| **Enables** | All system implementation stories — every system reads its configuration from DataConfig |
| **Blocks** | All system implementation — systems cannot be implemented without knowing where their tuning knobs live |
| **Ordering Note** | Must be Accepted before any system code is written. DataConfig is the first file created in implementation. |

## Context

### Problem Statement

The 12 MVP GDDs collectively define 100+ tunable values: pool sizes, damage multipliers, BGM crossfade durations, absorption meter thresholds, transformation cooldown timers, wave enemy counts, and more. Without a defined configuration architecture, these values face three risks: (1) **Scattering** — hardcoded constants in each system's `.gd` file, making balancing a multi-file scavenger hunt; (2) **Duplication** — the same value defined in two systems diverging silently (e.g., VFX pool size defined in both VFX and DataConfig); (3) **Type loss** — values stored as untyped JSON or dictionaries without editor validation, causing runtime errors from type mismatches.

### Constraints

- Godot 4.6 + GDScript
- Solo developer — balancing workflow must be fast (change value, run game, feel it)
- 60 fps target — config reads must not add frame overhead
- All config loaded before any system's `_ready()` runs (DataConfig is Autoload #1)
- 12 systems × average 8-10 tuning knobs each = 100+ values to manage
- Some config is simple scalars (pool_size: int = 50), some is structured (Form definitions with 8+ fields)

### Requirements

- Single source of truth — every tunable value lives in exactly one place
- Type-safe — the editor catches type mismatches before runtime
- Editor-inspectable — values editable in the Godot inspector without opening code
- No runtime parsing — zero JSON/Dictionary parsing during gameplay
- Fast iteration — changing a value and re-running the game takes < 5 seconds
- Structured data support — Form definitions, wave tables, and other multi-field configs have proper structure

## Decision

**Hybrid configuration: exported `@export var` properties on DataConfig.gd for scalar/array values + Custom Resource classes for structured multi-field data.**

DataConfig Autoload is the single source of truth. Every system reads its configuration from DataConfig. No system hardcodes a tunable value. No system loads a config file from disk — DataConfig owns all loading.

### Tier 1: Exported Variables (Simple Config — 80% of tuning knobs)

Scalar values and simple arrays are `@export var` properties on `DataConfig.gd`. Grouped by system with section comments matching GDD "Tuning Knobs" sections:

```gdscript
# DataConfig.gd — Autoload #1
extends Node

# ─── VFX: Particle Pool Sizes (GDD vfx-system.md Tuning Knobs K1-K6) ───
@export var vfx_pool_attack: int = 50
@export var vfx_pool_burst: int = 80
@export var vfx_pool_aura: int = 30
@export var vfx_pool_dust: int = 10
@export var vfx_pool_death: int = 60
@export var vfx_pool_cooldown: int = 40

# ─── VFX: Performance (GDD vfx-system.md Tuning Knobs K7-K9) ───
@export var vfx_max_simultaneous_particles: int = 150
@export var vfx_flash_duration_ms: float = 200.0
@export var vfx_low_hp_threshold: float = 0.3

# ─── Audio: Pool Sizes (GDD audio-system.md Tuning Knobs K2-K3) ───
@export var audio_sfx_pool_size: int = 8
@export var audio_ui_pool_size: int = 4

# ─── Audio: BGM (GDD audio-system.md Tuning Knobs K5-K9) ───
@export var bgm_crossfade_duration: float = 0.3
@export var bgm_layer_ambient_vol: float = 1.0
@export var bgm_layer_bassline_vol: float = 0.8
@export var bgm_layer_percussion_vol: float = 0.9
@export var bgm_layer_lead_vol: float = 1.0

# ─── Audio: Thresholds (GDD audio-system.md Tuning Knobs K10-K13) ───
@export var audio_bassline_threshold: float = 0.25
@export var audio_percussion_threshold: float = 0.5
@export var audio_lead_threshold: float = 0.75
@export var audio_low_hp_heartbeat_period_fast: float = 0.3
@export var audio_low_hp_heartbeat_period_slow: float = 0.5

# ... ~80 more exported vars across all 12 systems
```

**Benefits of this approach:**
- All scalar config visible in one file — no "which file has the BGM crossfade constant?" questions
- Godot inspector shows all values with type validation (int, float, String, Vector2, etc.)
- No loading code — `@export var` values are available immediately when DataConfig is `_ready()`
- Change value in inspector, press F5 — instant iteration
- GDScript type system catches mismatches at parse time

### Tier 2: Custom Resources (Structured Data — ~20% of config)

Multi-field structured data uses Godot Custom Resource classes. Each resource type is a `.gd` script extending `Resource`. Instances are `.tres` files loaded by DataConfig in `_ready()`:

```gdscript
# FormConfig.gd — Custom Resource for form definitions
class_name FormConfig
extends Resource

@export var form_id: String = ""
@export var form_name: String = ""
@export var hp_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0
@export var damage_multiplier: float = 1.0
@export var duration_seconds: float = 10.0
@export var cooldown_seconds: float = 30.0
@export var primary_color: Color = Color.WHITE
@export var unlock_wave: int = 0
@export var audio_form_signature: AudioStream  # AUD-002
```

```gdscript
# DataConfig.gd — Resource loading section
@export var form_configs: Array[FormConfig] = []

func _ready() -> void:
    # Resources can also be loaded from disk if not assigned in inspector:
    # form_configs = _load_resources("res://assets/data/forms/", FormConfig)
    pass

func get_form_config(form_id: String) -> FormConfig:
    for config in form_configs:
        if config.form_id == form_id:
            return config
    push_error("[DataConfig] FormConfig not found: %s" % form_id)
    return null
```

**Custom Resource types planned for MVP:**

| Resource Class | Contains | Used By |
|---------------|----------|---------|
| `FormConfig` | Form stats, color, duration, cooldown, audio signature | TransformationSystem, VFX, Audio, HUD |
| `WaveTable` | Wave number → enemy count, types, spawn timing | WaveSystem |
| `EnemyConfig` | Enemy type, HP, speed, damage, death_particle_type | EnemySystem |

**Benefits:**
- Type-safe multi-field data — `form_config.hp_multiplier` is a float, enforced by Godot
- Editor-inspectable — each `.tres` file can be edited in the Godot inspector
- Reusable — `FormConfig` is a class; `.tres` files are instances
- Extensible — adding a new field to `FormConfig` auto-propagates to all `.tres` instances

### Architecture Diagram

```
DataConfig.gd (Autoload #1)
│
├── @export var (Tier 1 — scalar/array)
│   ├── vfx_pool_attack: int = 50
│   ├── vfx_pool_burst: int = 80
│   ├── bgm_crossfade_duration: float = 0.3
│   ├── audio_sfx_pool_size: int = 8
│   └── ... (~80 more scalars)
│
└── @export var (Tier 2 — Custom Resource references)
    ├── form_configs: Array[FormConfig]
    │   ├── beast_form.tres
    │   └── dragon_form.tres
    ├── wave_tables: Array[WaveTable]
    │   └── wave_table_mvp.tres
    └── enemy_configs: Array[EnemyConfig]
        ├── enemy_slime.tres
        └── enemy_bat.tres

Access pattern (all 11 other systems):
  VFX:              DataConfig.vfx_pool_attack
  Audio:            DataConfig.bgm_crossfade_duration
  Transformation:   DataConfig.get_form_config("beast")
  WaveSystem:       DataConfig.wave_tables[0]
```

### Access Pattern

Systems read DataConfig properties directly — no getter methods for simple scalars:

```gdscript
# ✅ ALLOWED — direct property read
var pool_size = DataConfig.vfx_pool_attack

# ✅ ALLOWED — structured access via lookup method
var form = DataConfig.get_form_config("beast")

# ❌ FORBIDDEN — hardcoding a tunable value
var pool_size = 50  # NEVER — use DataConfig.vfx_pool_attack
```

### Rationale for Hybrid (Not All-Custom-Resource)

- **Scalars as CustomResources would create 80+ `.tres` files** — each file wrapping a single number. This is file bloat with no benefit. The Godot inspector can edit exported vars on DataConfig just as well as `.tres` files.
- **Structured data as exported vars would create untyped Dictionaries** — losing the type safety and autocomplete that Custom Resources provide. A `Dictionary` with string keys has no compile-time checking for `hp_multiplier` vs `hp_multiplier` (typo).

The hybrid approach puts each value in its natural format: simple things are simple, complex things get structure.

## Alternatives Considered

### Alternative 1: All-Custom-Resource — every config value in .tres files

- **Description**: No `@export var` on DataConfig. Everything is a typed Resource. Pool sizes are `PoolConfig.tres`, BGM settings are `BgmConfig.tres`, etc. DataConfig loads all resources.
- **Pros**: Maximum type safety — every config value is in a typed Resource class. Maximum modularity — per-system config files can be swapped independently.
- **Cons**: 80+ `.tres` files, many wrapping single integers. A pool size change becomes: find `vfx_pool_config.tres`, open it, find the field, change 50 to 60. Slower iteration than typing `50 → 60` in DataConfig.gd. Over-engineered for a solo project.
- **Rejection Reason**: The iteration speed cost is real and unjustified for scalar values. A solo developer changing `vfx_pool_attack` from 50 to 60 should not navigate a file tree.

### Alternative 2: JSON-based — all config in .json files

- **Description**: All config values in JSON files under `assets/data/`. DataConfig loads and parses JSON in `_ready()`. Each system's config is a `.json` file.
- **Pros**: Diffable in version control. Language-agnostic — tools outside Godot can read/edit config. No Godot editor dependency.
- **Cons**: No type safety — a `"pool_size": "fifty"` in JSON is a runtime error, not a parse error. Requires manual validation code for every value. No autocomplete for config keys. Godot's JSON parser is slower than native Resource loading.
- **Rejection Reason**: Loses Godot's type system. The editor-inspector workflow (change value → press F5 → test) is the primary balancing loop for a solo dev. JSON breaks that loop.

### Alternative 3: Inline constants in each system's .gd file

- **Description**: Each system defines its own tunable values as `const` declarations at the top of its script.
- **Pros**: Zero loading overhead. Simplest possible approach — values are right where they're used.
- **Cons**: Scattered — balancing requires opening 12 files. Duplication risk — VFX pool size defined in both VFX.gd and Audio.gd can diverge. No central overview of all game parameters. Changing a value requires finding which system owns it.
- **Rejection Reason**: Violates "single source of truth." For a game with heavy cross-system tuning dependencies (Audio needs VFX pool sizes for frame-sync, HUD needs Absorption thresholds), scattered constants create invisible coupling.

## Consequences

### Positive

- **Single-file balancing**: 80% of tuning knobs are in one file (`DataConfig.gd`). Open it, tweak values in the inspector, press F5. No file hunting.
- **Type safety**: `@export var vfx_pool_attack: int = 50` means assigning `"fifty"` is a parse error. Custom Resources enforce field types at editor time.
- **Zero runtime parsing**: All values are native Godot types — no JSON parsing, no Dictionary validation, no string-to-float conversion.
- **GDD-aligned**: DataConfig.gd's section structure mirrors the GDD "Tuning Knobs" sections. The GDD tells the designer what to tune; DataConfig is where they tune it.
- **Extensible**: Adding a new tuning knob = one `@export var` line in DataConfig. Adding a new structured config type = one Resource class + `.tres` files.

### Negative

- **Large DataConfig.gd**: With 80+ exported vars, the file will be long (~300-400 lines). **Accepted cost**: Well-organized with section comments, it's a scrollable reference, not a complexity problem. Longer than ideal, but the alternative (80 files) is worse.
- **DataConfig knows about every system**: DataConfig has `vfx_pool_attack`, `bgm_crossfade_duration`, etc. — it has knowledge of every system's internal config needs. **Accepted cost**: This is the definition of a "configuration" module. DataConfig doesn't know how systems USE the values, only what values exist. No logic lives in DataConfig.
- **Custom Resources require boilerplate**: Each Resource class is a `.gd` file with `class_name`, `extends Resource`, and `@export var` fields. For 3-5 Resource types in MVP, this is ~30 lines of boilerplate each. **Accepted cost**: The boilerplate IS the schema — it documents the data structure and provides type checking.

### Risks

- **Risk: DataConfig.gd becomes a merge conflict hotspot**: With 80+ exported vars in one file, two branches adding different tuning knobs will conflict at the file level. **Mitigation**: Solo developer — merge conflicts with yourself are rare. Section comments keep additions organized. If a team grows, DataConfig can be split into per-system `.gd` files that are `@export var` includes — mechanical refactor.
- **Risk: Structured data formats change mid-development**: A `FormConfig` field is renamed or removed. All `.tres` files referencing the old field become invalid. **Mitigation**: Godot's Resource loader warns about unknown fields on load — visible in the editor immediately. `.tres` files are text-based and grep-able for batch renames.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| data-config.md | Rule 1: Single source of truth for all tunable values — loaded before all other systems | DataConfig Autoload #1. All `@export var` values available in `_ready()`. Custom Resources loaded before any system queries them. |
| vfx-system.md | Tuning Knobs K1-K12: Pool sizes, performance caps, flash durations, thresholds | `@export var vfx_pool_*`, `vfx_max_simultaneous_particles`, `vfx_flash_duration_ms`, `vfx_low_hp_threshold` in DataConfig |
| audio-system.md | Tuning Knobs K1-K22: Pool sizes, BGM crossfade, thresholds, heartbeat rates, charging pitch range | `@export var audio_*` and `bgm_*` properties in DataConfig |
| transformation-system.md | Form definitions: hp_mult, speed_mult, damage_mult, duration, cooldown, color, audio | `FormConfig` Custom Resource with `@export` fields matching every GDD-defined form attribute |
| wave-system.md | Wave tables: enemy counts, types, spawn timing per wave | `WaveTable` Custom Resource loaded by DataConfig |
| enemy-system.md | Enemy type definitions: HP, speed, damage, death particle type | `EnemyConfig` Custom Resource loaded by DataConfig |
| All 12 MVP GDDs | Every "Tuning Knobs" section has a corresponding location in DataConfig | DataConfig.gd section structure mirrors GDD Tuning Knobs sections 1:1 |

## Performance Implications

- **CPU**: Config reads are direct property accesses (O(1) for scalars, O(n) for Array lookups with small n). Zero per-frame overhead — all config is read once at init or on state transition, not every frame.
- **Memory**: 80+ scalars + 3-5 Resource arrays ≈ 10-20 KB total. Custom Resource `.tres` files are loaded once and shared (no per-instance duplication).
- **Load Time**: `@export var` requires zero loading (values are compiled into the script). Custom Resource loading of 3-5 `.tres` files ≈ sub-millisecond. Total DataConfig `_ready()` time < 1ms.

## Migration Plan

N/A — DataConfig is created fresh. No existing config code to migrate.

## Validation Criteria

- DataConfig.gd is Autoload #1 in `project.godot` — loads before GSM, InputSystem, and all other systems
- Every scalar tuning knob from every GDD's "Tuning Knobs" section exists as an `@export var` in DataConfig.gd
- No system `.gd` file contains a hardcoded magic number that matches a GDD tuning knob (enforced by code review)
- `FormConfig`, `WaveTable`, `EnemyConfig` Resource classes exist and have `@export` fields matching their GDD specifications
- All `.tres` files load without errors in Godot editor
- Changing a value in DataConfig's inspector and pressing F5 reflects the change in-game

## Related Decisions

- ADR-0001: Autoload Singleton Architecture — DataConfig is Autoload #1, Foundation layer
- ADR-0003: Object Pooling Architecture — Pool sizes (vfx_pool_attack, etc.) are DataConfig values, not hardcoded in pool managers
- ADR-0004: Signal Bus Pattern — DataConfig does not emit signals; it is a passive data store read via properties
