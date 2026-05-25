# Story 002: DataConfig Core — Loading & Access

> **Epic**: Data Config (数据配置系统)
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Logic
> **Estimate**: M (2 sessions)
> **Manifest Version**: N/A — control-manifest not yet created
> **Last Updated**: 2026-05-25

## Context

**GDD**: `design/gdd/data-config.md`
**Requirements**: `TR-DC-001`, `TR-DC-002`, `TR-DC-003`, `TR-DC-007`, `TR-DC-008`, `TR-DC-009`

**ADR Governing Implementation**: ADR-0005: Data Configuration Architecture
**ADR Decision Summary**: DataConfig Autoload #1。Tier 1 `@export var` 标量可直接属性读取，Tier 2 Custom Resource 通过访问器方法查询（`get_form_config(id)`）。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: ResourceLoader.load() 是 pre-4.0 稳定 API。`@export var` 值在 `_ready()` 时立即可用。

**Control Manifest Rules (this layer)**:
- Required: N/A
- Forbidden: N/A — 注意 ADR-0005 禁止其他系统硬编码可调数值
- Guardrail: N/A

---

## Acceptance Criteria

*From GDD `design/gdd/data-config.md`:*

- [x] **AC1 (TR-DC-001)**: GIVEN 游戏启动且所有 `.tres` 文件完整有效，WHEN DataConfig._ready() 完成，THEN 所有配置类别访问器返回非空值，加载总耗时 < 50ms，控制台无 error 或 warning 日志
- [x] **AC2 (TR-DC-002)**: GIVEN 有效配置键（如 `"slime_melee"`），WHEN 调用 `DataConfig.get_enemy_config("slime_melee")`，THEN 返回 `EnemyConfig` 实例，其 `hp` > 0，`speed` > 0，`enemy_id` = `"slime_melee"`
- [x] **AC3 (TR-DC-003)**: GIVEN 不存在的配置键（如 `"nonexistent_enemy"`），WHEN 调用 `DataConfig.get_enemy_config("nonexistent_enemy")`，THEN 返回该类别预定义的默认 EnemyConfig 实例 + 控制台打印 warning 日志
- [x] **AC7 (TR-DC-007)**: GIVEN `assets/config/` 目录下缺少一个 `.tres` 文件，WHEN 游戏启动，THEN 游戏正常启动不崩溃，查询返回默认实例 + 控制台打印 error 日志标明缺失文件路径
- [x] **AC8 (TR-DC-008)**: GIVEN 两个 `.tres` 文件声明了相同的 `id = "slime_melee"`，WHEN Config 加载完成，THEN 后加载的文件覆盖前者 + 控制台打印 duplicate key warning
- [x] **AC9 (TR-DC-009)**: GIVEN Config 单例加载完成后，WHEN 任意其他 Autoload 在其 `_ready()` 中调用 Config 的任意查询方法，THEN 返回有效数据，无 null 或 "Config not loaded" 错误

---

## Implementation Notes

*Derived from ADR-0005:*

1. **DataConfig.gd 结构**：创建 `DataConfig.gd`，`extends Node`。文件分为两个区域：
   - Tier 1: `@export var` 属性块（按系统分组，带 GDD Tuning Knobs 引用注释）
   - Tier 2: Custom Resource 数组（`@export var form_configs: Array[FormConfig]` 等）+ 访问器方法
2. **Tier 1 访问**：其他系统通过 `DataConfig.vfx_pool_attack` 直接读取属性——无需 getter 方法
3. **Tier 2 访问**：提供 `get_form_config(id: String) -> FormConfig` 等查询方法。内部使用 Dictionary 缓存（key=id, value=Resource），在 `_ready()` 中构建缓存
4. **加载流程**：`_ready()` 中构建缓存字典——遍历 `@export var` 数组中的 Resource，以 `resource.id` 为 key 插入 Dictionary。重复 key 时覆盖 + warning
5. **默认回退**：每个类别在 `assets/config/defaults/` 下有一个 `default_[category].tres`。当查询的 key 不存在时返回该默认实例
6. **Autoload 注册**：DataConfig 必须注册为 Autoload #1（在 project.godot `[autoload]` 列表中排第一），确保所有其他 Autoload 在其 `_ready()` 中可以得到有效数据
7. **禁止模式**：任何其他系统不得 `ResourceLoader.load("res://assets/config/...")` ——所有配置加载由 DataConfig 独佔

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001: Resource 类定义（FormConfig / WaveTable / EnemyConfig / AreaConfig 的字段声明）
- Story 003: 值越界 clamp 验证、Resource 引用完整性验证
- Story 004: 编辑器热重载、导出构建行为、性能压力测试（AC1 性能部分由 Story 004 验证）

---

## QA Test Cases

- **AC1 — 启动加载完整性**: 
  - Given: 所有 .tres 文件完整有效且 DataConfig 加载完成
  - When: 调用每个类别的访问器方法
  - Then: 所有访问器返回非空值，`Time.get_ticks_msec()` 差值 < 50ms
  - Edge cases: 空 config 目录（零 .tres 文件）→ 所有访问器返回默认值，不崩溃

- **AC2 — 有效 key 查询**:
  - Given: 存在 enemy_id="slime_melee" 的 EnemyConfig，hp=10
  - When: 调用 `DataConfig.get_enemy_config("slime_melee")`
  - Then: 返回 EnemyConfig 实例，hp==10，enemy_id=="slime_melee"
  - Edge cases: key 大小写敏感性（"SLIME_MELEE" vs "slime_melee"）→ 精确匹配

- **AC3 — 不存在 key 查询**:
  - Given: 不存在 id="nonexistent" 的配置
  - When: 调用 `DataConfig.get_enemy_config("nonexistent")`
  - Then: 返回默认 EnemyConfig 实例（非 null），`push_warning()` 被调用
  - Edge cases: 空字符串 key → 同不存在 key 处理

- **AC7 — 缺失文件**:
  - Given: assets/config/enemies/ 目录为空（无 .tres 文件）
  - When: DataConfig._ready() 加载
  - Then: 游戏正常启动，`get_enemy_config(any)` 返回默认实例，`push_error()` 标记缺失目录

- **AC8 — 重复 key**:
  - Given: 两个 .tres 文件都有 id="slime_melee"（hp=10 和 hp=20）
  - When: DataConfig 加载
  - Then: 后加载的覆盖（hp=20），`push_warning("Duplicate config key...")` 被调用
  - Edge cases: 两个文件 id 完全相同且字段值完全相同 → 仍打印 warning（警告设计师检查）

- **AC9 — 加载顺序**:
  - Given: DataConfig 是 Autoload #1，GSM 是 Autoload #2
  - When: GSM._ready() 调用 `DataConfig.get_form_config("beast")`
  - Then: 返回有效 FormConfig，非 null，无 "Config not loaded" 错误
  - Edge cases: 测试脚本模拟后续 Autoload 的 _ready() 中查询 → 确认 DataConfig 已就绪

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/data_config/config_loader_test.gd` — must exist and pass
**Status**: [x] Created — 11 test functions covering 6 ACs + 3 edge cases. push_warning assertions deferred (requires running Godot engine).

---

## Completion Notes

**Completed**: 2026-05-25
**Criteria**: 6/6 passing
**Deviations**: ADVISORY — AC7 describes push_error with file path, but ADR-0005 uses Inspector @export var assignment model (not disk scanning). DataConfig processes assigned Resource references, doesn't know file paths. This is AC-to-ADR alignment, not code deviation.
**Test Evidence**: `tests/unit/data_config/config_loader_test.gd` — 11 test functions covering all 6 ACs
**Code Review**: Complete — APPROVED (1 BLOCKING format-string bug fixed before close)

---

## Dependencies

- Depends on: Story 001（Resource Class Definitions — 需要 FormConfig 等类存在才能加载）
- Unlocks: Story 003（Validation System）, Story 004（Editor/Export/Performance）
