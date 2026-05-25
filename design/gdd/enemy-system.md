# Enemy System — 敌人系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation) + Pillar 3 (Paced Mastery)

## Overview

敌人系统（Enemy System）管理 Shapeshift Survivor 中所有敌对实体的生命周期——从波次系统生成敌人实例的那一刻起，到敌人被击杀或离开场景为止。它定义敌人的类型（近战杂兵 / 远程射手 / 精英等）、AI 行为、HP 与受击、碰撞伤害、掉落生成，以及死亡清理。

**技术层面**：敌人系统维护一个全局敌人实例列表（供玩家系统、吸收系统查询）。每个敌人实例是 Godot 场景中的一个 `CharacterBody2D` 节点，携带其 `EnemyConfig` 引用（从 Config 查询获得）。AI 行为通过每帧查询玩家位置、向玩家移动实现（基础追踪 AI）。敌人不互相碰撞（仅与玩家和环境碰撞）。

**玩家层面**：敌人是 30 秒循环中的"压力源"——没有敌人就没有击杀、没有形态点数、没有变身需求。敌人的密度、速度、伤害定义了"我有多危险"——稀疏而慢的敌人让玩家感到从容，密集而快的敌人迫使玩家变身。敌人类型的视觉多样性（不同颜色/大小/行为）是玩家阅读战场的基础。

**没有这个系统会失去什么**：游戏没有威胁——玩家在空场景中移动，变身动力消失，核心循环崩塌。敌人是"蓄能→爆发"公式中的触发剂——没有敌人，一切不成立。

## Player Fantasy

敌人是玩家压力与满足感的来源。玩家不"喜欢"敌人——玩家喜欢**战胜**敌人。

> **"猎物成为猎手"** —— 在人类形态下，玩家是猎物——被敌人追逐、包围、压迫。敌人越来越多、越来越快，压力不断累积。然后在变身瞬间，角色逆转——玩家成为猎手，敌人从威胁变为资源（形态点数）。敌人系统的幻想不在于敌人本身，而在于它创造的**对比**——人类形态的脆弱 vs 变身形态的强大，正是因为有敌人在追逐你。

**该系统直接支撑的游戏支柱：**
- **支柱 1（爆发变身）**: 敌人是"蓄能→爆发"公式中的"蓄能"理由。敌人密度和伤害定义了什么时刻玩家感到"我必须变身了"——变身不是玩家随意按下的按钮，而是对敌人压力的回应。
- **支柱 3（节奏掌控）**: 敌人的速度、密度、类型组合定义了每一波的"节奏"。玩家通过走位在敌群中生存——敌人的 AI 行为（追踪速度、攻击前摇）是玩家走位决策的输入。

## Detailed Design

### Core Rules

**Rule 1: EnemyConfig 定义所有敌人属性**

每个敌人类型对应一个 `EnemyConfig` Resource（存储在 `assets/config/enemies/`），包含所有可调属性。敌人生成时从 Config 读取，运行期间只读。

**Rule 2: CharacterBody2D + 追踪 AI**

每个敌人实例是 `CharacterBody2D` 节点。AI 每帧执行：计算到玩家的方向向量 → 归一化 → 乘以 `move_speed` → `move_and_slide()`。无路径寻找（A*等）——敌人直接向玩家移动，被场景障碍物阻挡时沿障碍物滑动（Godot `move_and_slide()` 默认行为）。

**Rule 3: 接触伤害 + 攻击冷却**

敌人与玩家受击碰撞体重叠时造成伤害。每个敌人有内置攻击冷却（`attack_cooldown`）——防止同一敌人每帧造成伤害。伤害值 = `EnemyConfig.damage`。

**Rule 4: 敌人不互相碰撞**

敌人之间设置碰撞层掩码使它们互不碰撞——防止一群敌人互相推挤形成"卡住"的团块。敌人仅与场景边界和玩家碰撞。

**Rule 5: HP、受击与死亡**

敌人 HP 来自 `EnemyConfig.hp`。收到伤害时 `hp_current -= damage`。当 `hp_current <= 0` 时：发出 `enemy_killed` 信号（携带 `form_points_drop` 值）、播放死亡动画/特效、从场景中移除节点。

**Rule 6: 状态感知——GSM 时间流速响应**

敌人移动使用 `delta * GSM.time_scale`。当 GSM 进入 UPGRADE 或 DEATH 状态时 `time_scale = 0`，敌人自动停止移动——无需敌人系统显式检查状态。

**Rule 7: 全局敌人注册表**

敌人系统维护一个全局活跃敌人字典（`active_enemies: Dictionary`）。供玩家系统（查找最近敌人）、吸收系统（检测击杀事件）、波次系统（检查波次是否清除）查询。

### Enemy Types (MVP — 风歌草原)

| ID | 名称 | HP | 移速 | 伤害 | 攻击冷却 | 掉落点数 | 行为 |
|----|------|-----|------|------|---------|---------|------|
| `slime` | 史莱姆 | 3 | 60 | 5 | 1.5s | 1 | 追踪玩家，低速近战 |
| `slime_ranged` | 酸液史莱姆 | 2 | 30 | 8 | 2.0s | 2 | 在 100px 距离停下，发射弹射物 |
| `charger` | 冲锋者 | 5 | 150 | 10 | 2.0s | 3 | 快速冲刺（直线），撞到场景边界后短暂眩晕 |
| `elite_slime` | 巨型史莱姆 | 20 | 40 | 15 | 1.0s | 5 | 大型史莱姆，高 HP，精英单位 |

### Interactions with Other Systems

| 系统 | 交互 | 内容 |
|------|------|------|
| 数据配置系统 | 查询 | 读取 EnemyConfig 初始化敌人属性 |
| 游戏状态管理 | 查询 | `GSM.time_scale` 驱动移动暂停 |
| 波次系统 | 被调用 | 波次系统调用 `spawn_enemy(config, position)` 生成敌人 |
| 玩家系统 | 双向 | 玩家攻击 → 敌人受击；敌人碰撞 → 玩家受击 |
| 吸收系统 | 触发 | `enemy_killed(points)` 信号 → 吸收系统增加形态点数 |
| VFX 系统 | 触发 | 受击闪白、死亡特效 |

## Formulas

### F.1 Enemy Movement (Tracking AI)

```
direction = (player.global_position - enemy.global_position).normalized()
velocity = direction * move_speed * GSM.time_scale
enemy.move_and_slide()
```

### F.2 Contact Damage

```
if enemy.attack_cooldown_ready AND enemy.hurtbox.overlaps(player.hurtbox):
    player.take_damage(enemy.damage)
    enemy.reset_attack_cooldown()
```

### F.3 Enemy Death → Points

```
if hp_current <= 0:
    emit_signal("enemy_killed", config.form_points_drop)
    queue_free()
```

## Edge Cases

- **如果玩家位置不可达（如玩家死亡后节点被禁用）**：敌人在 `player == null` 时停止移动并进入 idle 状态。

- **如果大量敌人（50+）同时追踪玩家导致性能下降**：敌人 AI 使用分组更新（每帧只更新一半敌人，分批处理），确保每帧 AI 更新数 ≤ 25。

- **如果敌人在攻击冷却期间持续与玩家重叠**：冷却计时器（`attack_cooldown`）确保每 1-2 秒最多造成一次伤害——持续重叠不产生额外伤害。

- **如果敌人被推离场景边界**：`move_and_slide()` 配合场景边界碰撞体阻止越界。如果敌人通过异常方式越界（bug），`_process` 中检测位置——超出边界 200px 以上则自动销毁 + warning 日志。

- **如果配置文件中的敌人 HP 为非正值**：Config 验证阶段修正（见 data-config.md），敌人系统收到保证有效的值。

- **如果敌人在生成时与玩家重叠**：`spawn_enemy()` 检查生成位置距玩家位置 ≥ `min_spawn_distance`（默认 100px）。若不满足，偏移至最近合法位置。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 数据配置系统 | `EnemyConfig` — 所有敌人类型的属性数据 |
| 游戏状态管理 | `GSM.time_scale` — 驱动移动暂停（UPGRADE/DEATH 状态下停止） |

### 下游依赖方

吸收系统、波次系统、Boss 系统、难度系统、新手引导。

### 接口契约

敌人系统向消费方暴露：
1. `active_enemies: Dictionary` (只读) — 全局活跃敌人列表
2. `enemy_killed(form_points: int)` 信号 — 敌人死亡 + 掉落点数
3. `spawn_enemy(config: EnemyConfig, position: Vector2)` — 生成敌人（由波次系统调用）
4. `clear_all_enemies()` — 清除所有活跃敌人（对局重启时调用）

## Tuning Knobs

| 参数 | 默认范围 | 玩法影响 |
|------|---------|---------|
| `hp` | 1–100 | 击杀所需攻击次数。太低→敌人一碰就死（无压力）；太高→单个敌人需要太多时间 |
| `move_speed` | 20–200 px/s | 追踪速度。慢于玩家→可风筝；等于玩家→无法甩掉；快于玩家→必须变身 |
| `damage` | 1–50 | 每次接触伤害。太低→碰撞无威胁；太高→擦边即残血 |
| `attack_cooldown` | 0.5–3.0s | 攻击频率。太短→站在敌群中瞬间死亡 |
| `form_points_drop` | 1–20 | 击杀奖励。太少→蓄能太慢（变身间隔长）；太多→蓄能太快（变身不珍贵） |

## Visual/Audio Requirements

- 敌人精灵按 EnemyConfig 指定。4 种敌人类型各有独特视觉（颜色、大小、形状）
- 受击白闪（0.05s）、死亡动画/粒子爆发
- 追踪移动无持续音效；攻击命中时发出攻击音效；死亡时发出死亡音效
- 具体视觉/音频设计由艺术圣经和音频系统 GDD 定义

## UI Requirements

不适用。敌人系统不产生 UI。敌人 HP 条（可选）由 HUD 系统决定是否显示在敌人头顶——敌人系统仅暴露 `hp_current` / `hp_max` 作为只读属性。

## Acceptance Criteria

- **GIVEN** 一个史莱姆敌人生成在场景中，**WHEN** 玩家在 200px 范围内，**THEN** 敌人以 60 px/s 向玩家移动。

- **GIVEN** 敌人与玩家碰撞体重叠且攻击冷却就绪，**WHEN** 重叠持续，**THEN** 玩家受到 5 点伤害且敌人进入 1.5s 攻击冷却。

- **GIVEN** 敌人 HP = 3 且玩家攻击力 = 5，**WHEN** 玩家攻击命中敌人，**THEN** 敌人 HP 归零，`enemy_killed(1)` 信号发出，节点被移除。

- **GIVEN** GSM 状态为 UPGRADE（time_scale=0），**WHEN** 检查敌人移动，**THEN** 所有敌人速度为 0（停止移动）。

- **GIVEN** 50 个敌人同时活跃，**WHEN** 检查帧率，**THEN** 敌人 AI 更新不导致帧率下降（每帧 AI 更新数 ≤ 25，分组处理）。

- **GIVEN** 生成位置距玩家 < 100px，**WHEN** 调用 `spawn_enemy()`，**THEN** 敌人位置被偏移至 ≥ 100px 外。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 远程敌人（酸液史莱姆）的弹射物是否需要独立系统管理？还是敌人系统内部管理？ | 否——MVP 可在敌人系统内部用简单 Area2D 弹射物实现 | 波次系统 GDD 时交叉确认 |
| 2 | 是否需要"精英光环"（精英敌人 buff 周围小兵）？增加策略深度但增加 AI 复杂度。 | 否——MVP 精英仅属性增强 | Vertical Slice 阶段评估 |
| 3 | 敌人是否需要受击动画/击退效果？击退增加打击感但影响敌人追踪行为。 | 否——MVP 仅受击白闪 | 原型测试手感后决定 |
| 4 | 冲锋者的"直线冲刺+撞墙眩晕"行为是否对 MVP 过于复杂？可简化为"快速追踪"。 | 否——保留当前设计 | 实现阶段——若行为复杂导致 bug，退化为快速追踪 |
