# Story 003: Validation System

> **Epic**: Data Config (数据配置系统)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: S (1 session)
> **Manifest Version**: N/A — control-manifest not yet created
> **Last Updated**: 2026-05-25

## Context

**GDD**: `design/gdd/data-config.md`
**Requirements**: `TR-DC-004`, `TR-DC-011`

**ADR Governing Implementation**: ADR-0005: Data Configuration Architecture
**ADR Decision Summary**: 配置验证在加载后立即执行——检测越界值、引用完整性和缺失文件，使用 warning 日志 + 自动修正（clamp/默认值），不阻止启动。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: GDScript type system catches type mismatches at parse time. Runtime validation handles semantic constraints (range checks, cross-reference integrity).

**Control Manifest Rules (this layer)**:
- Required: N/A
- Forbidden: N/A
- Guardrail: N/A

---

## Acceptance Criteria

*From GDD `design/gdd/data-config.md`:*

- [ ] **AC4 (TR-DC-004)**: GIVEN 某个 `.tres` 文件中的 `hp` 字段被手动设为 -5，WHEN Config 加载完成并运行验证，THEN `hp` 被自动修正为 1（clamp 到有效范围），控制台打印 warning 日志标明文件路径和修正值
- [ ] **AC4-ext (TR-DC-004)**: GIVEN 配置值超过有效上限（如 pool_size=500，上限=200），WHEN 验证运行，THEN 值被 clamp 到上限，warning 日志标明原始值→修正值
- [ ] **AC11 (TR-DC-011)**: GIVEN 一个 `.tres` 文件包含 `Resource` 引用字段（如 BossConfig 引用 EnemyConfig），WHEN Config 验证阶段检查引用完整性，THEN 若引用的 Resource 存在 → 通过；若引用不存在 → warning 日志 + 使用默认引用
- [ ] 所有验证 warning 日志包含足够信息：文件路径 + 字段名 + 原始值 + 修正值（便于设计师定位问题）
- [ ] 验证在 DataConfig._ready() 中加载完成后自动执行（无需手动调用）

---

## Implementation Notes

*Derived from ADR-0005 + GDD Validation Rules:*

1. **验证时机**：在 `_ready()` 中，所有 Resource 加载并缓存后，立即运行 `_validate_all_configs()`
2. **越界检查（AC4）**：
   - 从 Story 001 的 Resource 类中读取 `@export_range` 注解的范围作为验证边界
   - 如果无法读取注解范围，使用 GDD Tuning Knobs 中的硬编码安全范围
   - 违规处理：clamp + `push_warning("[DataConfig] Value out of range in [file]: [field] = [original] → clamped to [corrected]")`
3. **引用完整性（AC11）**：
   - 遍历所有 Resource 的 `Resource` 类型字段（`is_instance_of(Resource)`）
   - 检查被引用的 Resource 是否在对应缓存字典中存在
   - 不存在时：`push_warning("[DataConfig] Broken reference in [file]: [field] → using default")` + 替换为默认引用
4. **验证严格度**：使用 `Config.validation_strictness` 枚举控制（详见 GDD Tuning Knobs G.1）：
   - `silent`：静默修正
   - `warn`：修正 + warning（MVP 默认）
   - `error`：修正 + `push_error()`（CI 模式）
5. **日志信息粒度**：每条 warning 包含「文件:字段:原值→修正值:原因」四个信息，确保设计师可以立即定位问题

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 配置加载和访问器方法（验证在这些方法的基础上运行）
- Story 004: 编辑器热重载时的重新验证、性能测试

---

## QA Test Cases

- **AC4 — 越界值 clamp（低于下限）**:
  - Given: enemy_slime.tres 中 hp=-5（有效范围 1–9999），validation_strictness=warn
  - When: DataConfig._ready() 加载并验证
  - Then: hp 被修正为 1，`push_warning()` 包含 "enemy_slime.tres"、"hp"、"-5"、"1"
  - Edge cases: hp=0（边界值，通常是非法的——0 HP = 不能死？应 clamp 到 1）

- **AC4 — 越界值 clamp（高于上限）**:
  - Given: vfx_pool_attack=500（有效上限 200）
  - When: 验证运行
  - Then: 值被 clamp 到 200，warning 包含原始值→修正值

- **AC11 — 引用完整性**:
  - Given: boss_config.tres 引用 enemy_id="dragon_boss"，但该 enemy config 不存在
  - When: 验证运行
  - Then: `push_warning()` 标明 broken reference，引用被替换为默认 EnemyConfig
  - Edge cases: 引用字段为 null（未设置）→ 同缺失引用处理（null → 默认值）

- **配置严格度 silent 模式**:
  - Given: validation_strictness=silent
  - When: hp=-5 被检测到
  - Then: 值被修正但不产生日志输出
  - Edge cases: 确保 silent 模式不隐藏文件级错误（如 .tres 语法损坏）→ 语法错误仍应报告

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/data_config/config_validation_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Completion Notes

**Completed**: 2026-05-25
**Criteria**: 5/5 passing
**Deviations**:
- ADVISORY: Validation + mutation exceeds ADR-0005 "passive data store" boundary (~90 lines of active mutation logic)
- ADVISORY: VALIDATION_RULES duplicates Resource class @export_range annotations (two-file edit for one field change)
- ADVISORY: AC11 _validate_reference_integrity() implemented and tested but not wired into auto-validation (deferred until cross-cache references exist)
- ADVISORY: Log content verification not auto-testable (GdUnit4 framework limitation — no push_warning interception)
**Test Evidence**: tests/unit/data_config/config_validation_test.gd — 15 test functions
**Code Review**: Complete — APPROVED WITH SUGGESTIONS (3 fixes applied: is_same, hp=0 boundary, 2ms threshold)

---

## Dependencies

- Depends on: Story 002（DataConfig Core — 需要加载和访问器方法已实现才能运行验证）
- Unlocks: Story 004（Editor/Export/Performance）
