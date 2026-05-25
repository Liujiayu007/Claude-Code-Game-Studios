# Absorption System — 吸收系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation)

## Overview

吸收系统（Absorption System）是 Shapeshift Survivor 中连接"击杀敌人"与"蓄能变身"的桥梁。它负责：检测敌人死亡 → 生成形态点数掉落物 → 玩家接近时自动收集 → 填充形态计量表 → 计量表满时通知玩家可以变身。

该系统定义了"蓄能→爆发"循环中的"蓄能"阶段——它将战斗成果（击杀）转化为战略资源（变身机会）。收集模式为**自动吸取**——形态点数在掉落后向玩家飞行，玩家无需手动拾取。吸收效率在 CHARGING 状态下获得倍率加成（由 GSM 状态驱动）。

## Player Fantasy

吸收系统不产生独立的玩家幻想——它的幻想是**累积的视觉和听觉满足感**：敌人死亡时爆出的小光点、光点飞向玩家的轨迹、计量表填充的渐强音效、满格那一刻的视觉提示。这些元素组合在一起创造了"即将爆发"的期待感——吸收系统是"蓄能→爆发"公式中的张力建设者。

## Detailed Design

### Core Rules

**Rule 1: 击杀→掉落**

敌人死亡时，`enemy_killed` 信号携带 `form_points_drop` 值。吸收系统接收信号，在敌人死亡位置生成对应数量的形态点数掉落物。

**Rule 2: 自动吸取**

掉落物生成后，在 `pickup_delay`（默认 0.3s）后开始向玩家位置飞行。飞行速度 = `fly_speed`（默认 400 px/s）。掉落物碰到玩家碰撞体时被收集。若玩家距离 > `pickup_radius`（默认 150px），掉落物在地面等待——玩家走近后自动吸取。

**Rule 3: 计量表累积**

收集到的点数累加到 `meter_current`（0.0–1.0，归一化浮点数）。`meter_max` = 1.0（固定）。`meter_current` 即为计量表填充比例。

**Rule 4: CHARGING 状态倍率**

当 GSM 状态为 CHARGING 时，吸收效率 × `charging_multiplier`（默认 2.0x）。当 GSM 状态为 COOLDOWN 时，收集点数但效率 × 0.1。

**Rule 5: 计量表满→通知**

当 `meter_current >= 1.0` 时，发出 `meter_full` 信号（HUD 显示变身提示）。若玩家在 CHARGING 状态下按下变身键，`GSM.request_transition(TRANSFORMATION)` 被调用。

**Rule 6: 变身消耗**

进入 TRANSFORMATION 状态时，`meter_current` 重置为 0.0。溢出值（如收集了 0.12 即 1.10/1.0）保留至下次蓄能。

### Interactions with Other Systems

| 系统 | 交互 | 内容 |
|------|------|------|
| 敌人系统 | 订阅 | `enemy_killed` 信号 → 生成点数掉落物 |
| 玩家系统 | 查询 | 玩家位置 → 掉落物飞行目标；玩家碰撞体 → 收集触发 |
| 游戏状态管理 | 查询 | `current_state` → 倍率调整；发出 `meter_full` → 通知可变身 |
| 变身系统 | 触发 | 计量表满 + 玩家按键 → 触发变身 |
| HUD/UI 系统 | 暴露 | `meter_current` / `meter_max` → HUD 渲染计量表 |
| VFX/音频系统 | 触发 | 收集特效、计量表填充音效、满格提示音 |

## Formulas

### F.1 Meter Accumulation

```
meter_current = clamp(meter_current + points * state_multiplier, 0.0, 1.0)
```

**Variables:**

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| meter_current | float | 0.0–1.0 | Current meter fill level (normalized) |
| points | float | 0.01–0.20 | Form points from enemy drop |
| state_multiplier | float | 0.1 / 1.0 / 2.0 | CHARGING=2.0, COOLDOWN=0.1, other=1.0 |
| meter_max | float | 1.0 | Maximum meter value (fixed) |

### F.2 Pickup Flight

```
direction = (player.global_position - pickup.global_position).normalized()
pickup.global_position += direction * fly_speed * delta
```

Flight begins after `pickup_delay` (0.3s). Only if distance ≤ `pickup_radius`.

## Edge Cases

- **如果玩家在掉落物飞行途中死亡**：掉落物停止飞行，留在原地（对局结束，场景清理时统一销毁）。

- **如果多个敌人同时死亡（AOE 变身攻击）**：每个敌人独立生成掉落物——无上限。大量掉落物飞向玩家时可能产生视觉密度——这是期望的"爆发"视觉反馈。

- **如果计量表已满但玩家不按变身键**：CHARGING 状态下计量表保持 1.0，衰减规则照常（见 GSM GDD）。衰减至 < 1.0 后 `meter_full` 信号撤销。

- **如果拾取半径内无掉落物但远处有**：掉落物保持在地面，不飞行。玩家走近至 `pickup_radius` 内时开始飞行。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 敌人系统 | `enemy_killed` 信号 + `form_points_drop` 值 |
| 玩家系统 | 玩家全局位置（飞行目标）+ 玩家碰撞体（收集触发） |
| 游戏状态管理 | `current_state`（倍率调整）+ `GSM.request_transition(TRANSFORMATION)` |

### 下游依赖方

变身系统、HUD/UI、VFX、音频、新手引导。

### 接口契约

吸收系统向消费方暴露：
1. `meter_current: float` (只读) — 当前计量表值 (0.0–1.0，归一化)
2. `meter_max: float` (只读) — 计量表最大值 (1.0)
3. `meter_percent: float` (只读) — meter_current（已归一化，等同于 meter_current）
4. `meter_full` 信号 — 计量表达 1.0 时发出
5. `points_collected(count: float)` 信号 — 每次收集点数时发出

## Tuning Knobs

| 参数 | 默认值 | 安全范围 | 玩法影响 |
|------|--------|---------|---------|
| `meter_max` | 1.0 | 0.5–2.0 | 蓄能总需求（归一化）。>1.0→变身间隔长（节奏慢）；<1.0→变身太频繁（不珍贵）。注意：改变 meter_max 需同步调整 HUD 计量表渲染 |
| `pickup_radius` | 150 px | 80–300 | 自动吸取范围。太大→全屏吸取（无位置感）；太小→需要精确走位捡取 |
| `fly_speed` | 400 | 200–800 px/s | 点数飞向玩家的速度。太慢→延迟感；太快→看不清轨迹 |
| `pickup_delay` | 0.3s | 0–1.0s | 死亡后点数开始飞行的延迟。创造"击杀→爆出→飞向"的节奏 |
| `charging_multiplier` | 2.0 | 1.0–4.0 | CHARGING 状态吸收倍率。太高→蓄能阶段几乎瞬间完成 |

## Visual/Audio Requirements

- 掉落物：小光点（形态颜色主题），从敌人尸体爆出
- 飞行轨迹：光点拖着短尾迹飞向玩家
- 计量表填充：渐强音效（低→高音调），满格时短促"叮"提示音
- 具体设计由 VFX/音频系统 GDD + 艺术圣经定义

## UI Requirements

不直接产生 UI。HUD 系统查询 `meter_current`/`meter_max` 渲染计量表条——位置/样式/动画由 HUD GDD 定义。

## Acceptance Criteria

- **GIVEN** 敌人死亡且 `form_points_drop = 0.03`，**WHEN** `enemy_killed` 信号发出，**THEN** 3 个形态点数掉落物生成在敌人死亡位置。

- **GIVEN** 3 个掉落物在玩家 150px 范围内，**WHEN** `pickup_delay` (0.3s) 过后，**THEN** 掉落物以 400 px/s 向玩家飞行。

- **GIVEN** 掉落物碰到玩家碰撞体，**WHEN** 收集触发，**THEN** `meter_current` 增加对应点数 × 状态倍率。

- **GIVEN** GSM 状态为 CHARGING 且 `charging_multiplier = 2.0`，**WHEN** 收集 0.03 点，**THEN** `meter_current` 增加 0.06（0.03 × 2.0）。

- **GIVEN** `meter_current` 达到 1.0，**WHEN** 计量表检查，**THEN** `meter_full` 信号发出。

- **GIVEN** GSM 状态为 COOLDOWN，**WHEN** 收集点数，**THEN** `meter_current` 仅增加 0.1x（冷却惩罚）。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 变身时溢出的计量表值（如 1.10/1.0）是否保留到下次蓄能？保留→增加策略深度；重置→更简单可预测。 | 否——MVP 保留溢出值（见 Core Rule 6） | 变身系统 GDD 时确认 |
| 2 | 是否需要"磁铁"机制——暂时扩大拾取范围（如变身结束后给予 3 秒磁铁效果）？ | 否——MVP 固定拾取范围 | Vertical Slice 作为变异效果添加 |
| 3 | COOLDOWN 状态下收集点数是否完全阻止（×0）还是大幅降低（×0.1）？×0 = 冷却期间击杀无奖励（惩罚重）；×0.1 = 仍有微弱进展（更宽容）。 | 否——当前选择 ×0.1（宽容） | 原型测试手感 |
