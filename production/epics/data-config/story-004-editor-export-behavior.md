# Story 004: Editor Hot Reload & Export Behavior

> **Epic**: Data Config (数据配置系统)
> **Status**: In Progress
> **Layer**: Foundation
> **Type**: Integration
> **Estimate**: M (2 sessions)
> **Manifest Version**: N/A — control-manifest not yet created
> **Last Updated**: 2026-05-25

## Context

**GDD**: `design/gdd/data-config.md`
**Requirements**: `TR-DC-005`, `TR-DC-006`, `TR-DC-010`

**ADR Governing Implementation**: ADR-0005: Data Configuration Architecture
**ADR Decision Summary**: 编辑器模式下支持热重载（修改 .tres → 自动刷新缓存）。导出构建中配置只读且从 .pck 包加载。所有访问 O(1)，零运行时开销。

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Engine.is_editor_hint()` 区分编辑器/导出构建。`ResourceLoader.load()` 在编辑器中有缓存行为——热重载需要 `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)`。

**Control Manifest Rules (this layer)**:
- Required: N/A
- Forbidden: N/A
- Guardrail: N/A

---

## Acceptance Criteria

*From GDD `design/gdd/data-config.md`:*

- [ ] **AC5 (TR-DC-005)**: GIVEN 游戏在 Godot 编辑器中运行且 `hot_reload_enabled = true`，WHEN 设计师在 Inspector 中修改某个 `.tres` 文件的数值并保存，THEN 下一次 `DataConfig.get_enemy_config(id)` 查询返回更新后的值，无需重启场景
- [ ] **AC6 (TR-DC-006)**: GIVEN 游戏在导出构建（非编辑器）中运行，WHEN 调用 `DataConfig.get_enemy_config("slime_melee")`，THEN 返回与编辑器中相同的配置值，且运行期间磁盘上的 `.tres` 文件修改不影响正在运行的游戏
- [ ] **AC10 (TR-DC-010)**: GIVEN 玩家系统在 `_process()` 中每帧调用 `DataConfig.get_enemy_config(...)`，WHEN 连续运行 60 秒（约 3600 次查询），THEN 帧率保持在 60fps，Config 查询不成为性能瓶颈（单次查询 < 0.01ms）

---

## Implementation Notes

*Derived from ADR-0005 + GDD:*

1. **编辑器热重载（AC5）**：
   - 使用 `Engine.is_editor_hint()` 判断是否在编辑器中运行
   - 在 `_process(delta)` 中轻量轮询——使用 `ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)` 检查 `.tres` 文件的修改时间
   - 仅在检测到变化时才重建缓存字典——不在每帧无变化时重新加载
   - 符合 GDD G.1 的 `hot_reload_enabled` 开关——false 时跳过轮询
2. **导出构建（AC6）**：
   - 使用 `OS.has_feature("editor")` 或 `Engine.is_editor_hint()` 判断构建类型
   - 导出构建中：配置在启动时一次性加载，无热重载轮询，零运行时开销
   - `.tres` 文件打包在 `.pck` 中，通过 `res://` 路径访问——与编辑器路径相同，无特殊适配
3. **性能（AC10）**：
   - Dictionary 查询 O(1)，单次 < 0.001ms
   - 热重载轮询仅在编辑器 + hot_reload_enabled 时运行，开销忽略不计
   - 导出构建中零额外 `_process()` 开销
4. **性能测试方法**：
   - 创建简单的基准测试场景：循环调用 `get_enemy_config()` 3600 次
   - 测量总耗时——应 < 36ms（3600 × 0.01ms）
   - 确认无内存分配（无 Dictionary 复制、无临时 String 分配）

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 002: 基础加载和访问器方法（热重载在这些方法的基础上添加刷新逻辑）
- Story 003: 值验证——热重载后自动重新运行验证
- 性能分析工具（`/perf-profile`）集成——Story 004 仅做基础性能验证

---

## QA Test Cases

- **AC5 — 编辑器热重载**:
  - Given: 游戏在编辑器中运行，hot_reload_enabled=true，enemy_slime.tres 中 hp=10
  - When: 在 Inspector 中将 hp 改为 20 并保存
  - Then: 下一次 `DataConfig.get_enemy_config("slime_melee").hp` 返回 20（不需重启场景）
  - Edge cases: 在相同 id 的新 .tres 文件添加到目录后，热重载检测到新文件并加入缓存

- **AC6 — 导出构建一致性**:
  - Given: 编辑器构建中 enemy_slime.tres 的 hp=10
  - When: 导出并运行游戏
  - Then: `DataConfig.get_enemy_config("slime_melee").hp` 返回 10
  - Edge cases: 导出后在磁盘上修改 .pck 包外的 config 文件不影响游戏内值

- **AC10 — 性能压力**:
  - Given: 一个循环调用 `get_enemy_config("test_enemy")` 3600 次
  - When: 测量执行前后的时间戳差值
  - Then: 总耗时 < 36ms（单次 < 0.01ms），60fps 帧率稳定
  - Edge cases: 缓存中有 50+ 个条目时查询仍然 O(1)，时间不随缓存大小线性增长

- **热重载关闭时不轮询**:
  - Given: hot_reload_enabled=false，编辑器模式
  - When: 修改 .tres 文件
  - Then: `_process()` 中无文件系统访问，查询仍返回旧值

---

## Test Evidence

**Story Type**: Integration
**Required evidence**: `tests/integration/data_config/hot_reload_test.gd` OR manual playtest doc
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 002（DataConfig Core）, Story 003（Validation System — 热重载后需重新验证）
- Unlocks: None — 这是 Data Config epic 的最后一个 story
