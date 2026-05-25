# Story 001: Resource Class Definitions

> **Epic**: Data Config (数据配置系统)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Config/Data
> **Estimate**: S (1 session)
> **Manifest Version**: N/A — control-manifest not yet created
> **Last Updated**: 2026-05-25

## Context

**GDD**: `design/gdd/data-config.md`
**Requirement**: `TR-DC-002` (partial — defines the data structures that loading code will populate)

**ADR Governing Implementation**: ADR-0005: Data Configuration Architecture
**ADR Decision Summary**: Hybrid config — Tier 1 `@export var` scalars on DataConfig.gd, Tier 2 Custom Resource classes (FormConfig / WaveTable / EnemyConfig / AreaConfig) for structured multi-field data.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `@export` annotations and Resource loading are pre-4.0 stable. No post-cutoff API usage. Verify typed Dictionary exports work in 4.6 GDScript.

**Control Manifest Rules (this layer)**:
- Required: N/A — manifest not yet created
- Forbidden: N/A
- Guardrail: N/A

---

## Acceptance Criteria

*From GDD `design/gdd/data-config.md`, scoped to this story:*

- [x] `FormConfig` Resource 类存在，包含所有 `@export` 字段（form_id, form_name, hp_multiplier, speed_multiplier, damage_multiplier, duration_seconds, cooldown_seconds, primary_color, unlock_wave, audio_form_signature）
- [x] `WaveTable` Resource 类存在，包含波次定义所需字段（wave_number, enemy_groups, spawn_interval）
- [x] `EnemyConfig` Resource 类存在，包含所有 `@export` 字段（enemy_id, display_name, hp, speed, damage, form_points_drop, death_particle_type）
- [x] `AreaConfig` Resource 类存在，包含区域参数字段（area_id, area_name, enemy_pool, boss_id, bgm_id, background_tileset）
- [x] 每个 Resource 类的字段类型正确（int / float / String / Color / Array），使用 `@export_range` 标注有效范围
- [x] 每个 Resource 类的字段默认值遵循 GDD Tuning Knobs 中定义的安全默认值
- [x] 至少一个默认 `.tres` 实例为每个 Resource 类型存在（用于查询失败时的回退）

---

## Implementation Notes

*Derived from ADR-0005 Implementation Guidelines:*

1. 每个 Resource 类是一个独立的 `.gd` 文件，放在 `src/config/` 下，继承 `Resource`，使用 `class_name` 命名
2. 命名格式为 `[Category]Config`（如 `FormConfig`、`EnemyConfig`）
3. 所有字段使用 `@export var` 声明，确保在 Godot Inspector 中可编辑
4. 默认 `.tres` 实例放在 `assets/config/defaults/` 下，命名为 `default_[category].tres`
5. Resource 类是纯数据容器——不包含逻辑方法（除了可能的数据验证方法）
6. 字段类型必须精确匹配 GDD Tuning Knobs 中的定义（不能使用 `Variant` 或 `Dictionary`）
7. 枚举类型字段（如 `death_particle_type`）使用 `@export_enum` 声明

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: DataConfig.gd 中的 Tier 1 `@export var` 定义和 Resource 加载逻辑
- Story 003: 配置值验证（越界 clamp、引用完整性）
- Story 004: 编辑器热重载、导出构建行为、性能测试

---

## QA Test Cases

**Manual check — this is a Config/Data story:**
- Setup: 在 Godot 编辑器中打开项目，在 FileSystem 面板确认所有 Resource 类文件存在于 `src/config/`
- Verify: 每个 Resource 类的 `@export` 字段在 Inspector 中可见且类型正确
- Pass condition: 可以创建新的 `.tres` 实例，在 Inspector 中编辑所有字段并保存，重新加载后值不变
- Smoke check: 创建的默认 `.tres` 文件在 Godot 编辑器中无错误加载

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: Smoke check pass (`production/qa/smoke-*.md`)
**Status**: [ ] Not yet created (deferred to Story 002 — project.godot required for .tres resolution)

---

## Completion Notes

**Completed**: 2026-05-25
**Criteria**: 7/7 passing
**Deviations**: None (design refinements only: WaveEntry/WaveTable split, AreaConfig added beyond ADR-0005's 3 planned types)
**Test Evidence**: Smoke check deferred to Story 002 (project.godot needed for .tres resolution)
**Code Review**: Complete — APPROVED (no required changes)

---

## Dependencies

- Depends on: None — 这是第一个 DataConfig story，纯数据定义，零代码依赖
- Unlocks: Story 002（DataConfig Core 加载代码依赖 Resource 类存在）
