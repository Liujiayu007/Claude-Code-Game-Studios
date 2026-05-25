# Player System — 玩家系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation) + Pillar 3 (Paced Mastery)

## Overview

玩家系统（Player System）是 Shapeshift Survivor 中玩家角色的一切——移动、自动攻击、生命值、碰撞体，以及玩家在屏幕上的物理存在。它是玩家与游戏世界之间的唯一桥梁：玩家通过键盘/手柄输入移动角色，角色自动攻击最近的敌人，玩家通过角色的 HP 感受压力，通过角色的变身感受力量。

玩家系统围绕一个核心设计原则构建：**玩家始终在做两件事——移动和自动攻击。** 没有手动瞄准、没有主动技能释放（变身除外，由变身系统管理）、没有复杂的连招输入。玩家专注于走位和变身时机；攻击自动发生。这保持了 Survivor 类型的纯度——操作简单，策略在走位和时机。

玩家角色有两种行为模式，由 GSM 的状态驱动：

- **人类形态**（EXPLORATION / CHARGING / COOLDOWN 状态）：基础移动速度 + 基础自动攻击（近战范围、低伤害）。人类形态是"脆弱期"——玩家在此阶段通过走位规避伤害、通过收集形态点数蓄能。
- **变身形态**（TRANSFORMATION / BERSERK 状态）：移动速度、攻击模式、攻击范围、碰撞体全部由当前激活的形态配置（FormConfig）替换。玩家系统不定义变身形态的行为——它只负责在收到 GSM 信号后，从 Config 读取形态参数并应用替换。

移动使用 8 方向系统（上下左右 + 四斜角），从 InputSystem 获取归一化的 Vector2 移动向量。自动攻击每 `attack_interval` 秒触发一次，目标是距离玩家最近的敌人（在 `attack_range` 半径内）。

**没有这个系统会失去什么**：游戏没有玩家——字面意义上。没有人在屏幕上移动，没有人在收集点数，没有人在变身后切换攻击模式。玩家系统是游戏与玩家之间的接口——它把输入变成移动、把配置变成属性、把状态信号变成行为切换。

## Player Fantasy

玩家系统是玩家在游戏世界中的化身——它的幻想直接且原始：**"我在这个世界里，我的每一个操作都即时响应。"**

> **"穿梭于敌群之中"** —— 玩家感受到的是在密集敌群中穿插走位的流畅感、自动攻击锁定最近敌人的可靠感、以及从脆弱人类到毁灭怪物的瞬间切换。移动响应必须即时而顺滑——玩家按下方向键的瞬间角色就开始移动，松开瞬间就停止。这不是一个"有惯性的重型角色"——这是一个"敏捷的生存者"，能在毫厘之间从敌群缝隙中穿过。

**该系统直接支撑的游戏支柱：**

- **支柱 1（爆发变身）**: 玩家系统是人类形态"脆弱期"的载体——移动速度、基础攻击力、碰撞体大小定义了"我需要变身"的紧迫感。当变身激活时，玩家系统是变身的舞台——移动速度改变、攻击模式替换、视觉切换——所有变身带来的"力量感"通过玩家系统的行为变化被玩家感受到。人类形态的脆弱和变身形态的强大之间的对比越鲜明，支柱 1 的实现越成功。

- **支柱 3（节奏掌控）**: 玩家系统的移动和攻击是玩家"掌控"的主要工具。走位是玩家在敌人波次中生存的核心技能——好的走位让玩家以弱胜强，差的走位让玩家在满血时暴毙。自动攻击的频率和范围定义了"我能控制多少空间"——攻击间隔越短、范围越大，玩家控制的空间越大。节奏掌控的本质是：玩家通过移动控制距离、通过攻击控制空间——两者结合定义了"我有多安全"。

**参考游戏中类似的手感：**
- **Vampire Survivors** 的移动流畅度——角色即时响应 WASD，无惯性、无加速曲线。玩家完全掌控角色的位置。
- **Brotato** 的"穿梭"手感——在密集弹幕和敌群中通过精确走位生存，攻击自动发生使玩家可以完全专注于走位。
- **Hades** 的冲刺——虽然不是 Survivor 类型，但其"瞬间移动 + 无敌帧"的手感是"敏捷生存者"的标杆。

**"出问题时玩家会感受到什么"：**
- 当玩家系统**正确**时，玩家感觉自己在"跳舞"——在敌群中穿梭、攻击自动锁定、每一帧的移动都精准如预期
- 当玩家系统**错误**时——移动有延迟、攻击打不到最近的敌人、碰撞体判定不准、变身后速度没变化——玩家立即感到"游戏不公平"。移动和攻击是玩家最直接、最频繁的交互——这里的任何瑕疵都会被放大 100 倍

## Detailed Design

### Core Rules

**Rule 1: CharacterBody2D 驱动移动**

玩家角色使用 Godot 的 `CharacterBody2D` 节点。每帧从 `InputSystem.get_move_vector()` 获取移动方向，乘以 `current_move_speed`，通过 `move_and_slide()` 应用移动。无加速度曲线——输入即时响应。

```
velocity = InputSystem.get_move_vector() * current_move_speed
move_and_slide()
```

**Rule 2: 自动攻击——最近敌人锁定**

玩家不手动攻击。每 `attack_interval` 秒，玩家系统自动对攻击范围内最近的敌人造成伤害。攻击范围通过 `Area2D`（圆形）检测——进入该区域的敌人被加入候选列表，离开时移除。每次攻击触发时，从候选列表中选择距离最近的敌人，对其施加伤害。

**Rule 3: HP 与受击**

玩家 HP 从 Config 读取 `hp_max`（人类形态对应 `HumanConfig.hp`）。`hp_current` 初始等于 `hp_max`。玩家受到伤害时 `hp_current -= damage`。每次受击后有短暂的**受击无敌帧**（`iframe_duration`）——防止同一敌人在一帧内造成多次伤害，也防止多个敌人同时接触导致瞬间死亡。当 `hp_current <= 0` 时，玩家系统调用 `GSM.request_transition(DEATH)`。

**Rule 4: 碰撞伤害机制**

玩家与敌人之间的碰撞使用 Godot 碰撞层（collision layers）——敌人攻击碰撞体在 `enemy_attack` 层，玩家受击碰撞体在 `player_hurt` 层。当两者重叠时，玩家系统收到 `area_entered` / `body_entered` 信号，根据敌人类型计算伤害并扣除 HP + 触发受击无敌帧。

**Rule 5: 状态驱动的行为切换**

玩家系统订阅 `GSM.state_changed` 信号，根据状态切换行为模式：

| 状态 | 移动 | 攻击 | HP | 碰撞体 |
|------|------|------|-----|--------|
| EXPLORATION | Human speed | Human attack | Human HP | Human collider |
| CHARGING | Human speed | Human attack | Human HP | Human collider |
| COOLDOWN | Human speed | Human attack | Human HP | Human collider |
| TRANSFORMATION | Form speed | Form attack | Human HP (same pool) | Form collider |
| BERSERK | Form speed × berserk_mult | Form attack × berserk_mult | Human HP (same pool) | Form collider |
| UPGRADE | Stopped (time_scale=0) | Stopped | Human HP | Human collider |
| BOSS | Depends on sub-state | Depends on sub-state | Human HP | Depends on sub-state |
| DEATH | Stopped | Stopped | 0 (dead) | Disabled |

**Rule 6: 属性来源——Config 查询**

所有玩家属性（HP、移速、攻击力、攻击范围、攻击间隔）从 Config 读取——永不硬编码。人类形态属性来自 `Config.player_human()`（返回 `HumanConfig`）。变身形态属性由变身系统在形态激活时提供（读取 `FormConfig`）——玩家系统接收并应用。

**Rule 7: 单例场景——全局唯一玩家实例**

玩家角色是场景中的单例节点（不由任何系统动态创建或销毁——对局期间始终存在）。死亡时节点保留（播放死亡动画），由对局管理系统在重启对局时重置状态。

### Human Form Baseline

人类形态的默认属性（定义在 `assets/config/player/human.tres`）：

| 属性 | 默认值 | 说明 |
|------|--------|------|
| `hp_max` | 100 | 人类形态初始生命值 |
| `move_speed` | 200 px/s | 基础移动速度 |
| `attack_damage` | 5 | 每次自动攻击的基础伤害 |
| `attack_range` | 48 px | 自动攻击的圆形作用半径 |
| `attack_interval` | 0.8s | 两次自动攻击之间的时间间隔 |
| `collider_radius` | 8 px | 玩家圆形碰撞体半径 |
| `hurtbox_radius` | 10 px | 玩家受击碰撞体半径（略大于物理碰撞体） |
| `iframe_duration` | 0.15s | 受击后无敌帧持续时间 |

### Interactions with Other Systems

| 系统 | 交互方向 | 内容 |
|------|---------|------|
| 数据配置系统 | 查询 | 人类形态基础属性；变身时读取 FormConfig |
| 游戏状态管理 | 订阅 | `state_changed` → 切换行为模式；`request_transition(DEATH)` on death |
| 输入系统 | 查询 | `get_move_vector()` 每帧驱动移动 |
| 吸收系统 | 被调用 | 玩家击杀敌人后，吸收系统检测（通过信号）并增加形态点数 |
| 变身系统 | 被调用 | `state_changed(TRANSFORMATION)` → 变身系统提供 FormConfig，玩家系统应用 |
| 敌人系统 | 双向 | 玩家攻击伤害 → 敌人系统；敌人碰撞 → 玩家受击 |
| HUD/UI 系统 | 被查询 | HUD 查询玩家 HP / 形态计量表 / 当前状态以显示 |
| VFX 系统 | 触发 | 受击白闪、攻击特效、死亡特效 |

## Formulas

### F.1 Movement Speed

```
velocity = InputSystem.get_move_vector() * current_move_speed * GSM.time_scale
move_and_slide()
```

**Variables:**

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| current_move_speed | float | 0–1000 px/s | Human default: 200 px/s. Form speed from FormConfig |

InputSystem already returns a normalized vector, so diagonal movement is not faster.

### F.2 Auto-Attack Target Selection

```
target = argmin(enemy in attack_area: distance(player.position, enemy.position))
if target exists:
    deal_damage(target, attack_damage)
```

**Variables:**

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| attack_area | Array[Node] | 0–N enemies | Enemies currently inside the Area2D attack range |
| attack_damage | int | 1–1000 | Damage per attack. Human default: 5 |

### F.3 HP Depletion → Death

```
hp_current = clamp(hp_current - damage, 0, hp_max)
if hp_current <= 0 AND GSM.current_state != DEATH:
    GSM.request_transition(DEATH)
```

### F.4 IFrame Window

```
can_be_hit = (Time.get_ticks_msec() - t_last_hit) > iframe_duration_ms
```

Where `iframe_duration_ms = iframe_duration * 1000`. Default: 150ms.

## Edge Cases

- **如果玩家被多个敌人同时接触**：受击无敌帧（0.15s）确保只有第一次接触造成伤害。后续敌人在无敌帧期间的接触不造成伤害。防止"被一群敌人围住 = 瞬间死亡"。

- **如果攻击范围内没有敌人**：攻击不触发——玩家不空挥。`attack_interval` 计时器照常运行（下次触发时重新检测）。

- **如果玩家在攻击动画期间移动**：攻击和移动完全独立——没有"攻击前摇锁定移动"的限制。玩家可以在攻击的同时自由移动。这保持了 Survivor 类型的流畅手感。

- **如果玩家在变身期间 HP 归零**：立即死亡（DEATH 优先级最高），变身持续时间被放弃。

- **如果变身形态的攻击范围与人类形态不同**：攻击范围 Area2D 的半径在形态切换时动态调整（读取 FormConfig.attack_range）。

- **如果 Config 中的人类形态属性缺失或无效**：使用硬编码回退值（HP=100, speed=200, damage=5, range=48, interval=0.8, collider=8）。

- **如果玩家被推出场景边界**：`move_and_slide()` 配合场景边界碰撞体自然阻止越界。

- **如果玩家在同一帧内既击杀敌人又死亡**：DEATH 优先。先处理 HP 归零 → DEATH 状态；攻击伤害在该帧已发出，敌人仍受到伤害。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 数据配置系统 | 人类形态属性（`HumanConfig`）；变身时读取 `FormConfig` |
| 游戏状态管理 | `current_state` + `state_changed` 信号驱动行为切换；`request_transition(DEATH)` |
| 输入系统 | `get_move_vector()` 每帧驱动移动 |

### 下游依赖方（依赖本系统）

吸收系统、变身系统、敌人系统、HUD/UI、VFX、音频、对局管理系统、新手引导、对局总结。

### 接口契约

玩家系统向消费方暴露：
1. `hp_current: int` (只读) — 当前 HP
2. `hp_max: int` (只读) — 最大 HP
3. `current_move_speed: float` (只读) — 当前移速
4. `attack_damage: int` (只读) — 当前攻击力
5. `global_position: Vector2` (只读) — 当前位置（继承自 Node2D）
6. `player_died` 信号 — HP 归零时发出
7. `damage_dealt(target, amount)` 信号 — 每次攻击命中时发出
8. `player_hit(damage)` 信号 — 玩家受击时发出

## Tuning Knobs

| 参数 | 默认值 | 安全范围 | 玩法影响 |
|------|--------|---------|---------|
| `hp_max` | 100 | 50–500 | 人类形态生存能力。太高→变身无紧迫感；太低→活不到第一次变身 |
| `move_speed` | 200 | 100–500 px/s | 走位能力。太快→敌人永远追不上（无压力）；太慢→无法躲避（挫败感） |
| `attack_damage` | 5 | 1–50 | 人类形态击杀效率。太高→不需要变身就能清场 |
| `attack_range` | 48 | 16–128 px | 自动攻击覆盖面积。太大→玩家不需要走位接近敌人 |
| `attack_interval` | 0.8 | 0.2–2.0s | 攻击频率。太快→视觉混乱 + 敌人太容易死；太慢→攻击不频繁 |
| `collider_radius` | 8 | 4–16 px | 物理碰撞体大小。太小→穿模感；太大→碰撞判定不公平 |
| `iframe_duration` | 0.15 | 0.05–0.5s | 受击无敌帧。太短→多敌同时接触 = 秒杀；太长→站在敌群中不掉血 |

## Visual/Audio Requirements

玩家系统产生以下视觉效果（具体视觉设计由 VFX 系统和艺术圣经定义）：
- 移动：角色精灵根据移动方向切换朝向（4 或 8 方向精灵）
- 自动攻击：命中特效（挥砍/突刺方向指向最近敌人）
- 受击：角色白闪（iframe 期间）、屏幕边缘红色渐变（低 HP 警告）
- 死亡：死亡动画 + 屏幕变暗
- 形态切换：变身/冷却时的精灵替换（由变身系统触发，玩家系统执行）

音频：移动无持续音效（保持干净）。攻击触发攻击音效。受击触发受伤音效。死亡触发死亡音效。具体音频设计由音频系统 GDD 定义。

## UI Requirements

玩家系统不直接产生 UI。HUD 系统查询玩家 HP 等数据来渲染 HP 条、变身提示等。玩家系统暴露这些数据为只读属性——但不定义 UI 的视觉设计。

## Acceptance Criteria

- **GIVEN** 游戏运行且状态为 EXPLORATION，**WHEN** 玩家按下 W 键，**THEN** 玩家角色以 `move_speed` (200 px/s) 向上移动。

- **GIVEN** 一个敌人在玩家攻击范围（48px）内，**WHEN** `attack_interval` (0.8s) 到期，**THEN** 该敌人受到 `attack_damage` (5) 点伤害。

- **GIVEN** 多个敌人在攻击范围内，**WHEN** 攻击触发，**THEN** 仅最近的一个敌人受到伤害（单目标攻击）。

- **GIVEN** 玩家 HP 为 10 且受到 15 点伤害，**WHEN** 伤害结算，**THEN** `hp_current` = 0 且 `GSM.request_transition(DEATH)` 被调用。

- **GIVEN** 玩家刚受到一次伤害（`iframe_duration` 内），**WHEN** 另一个敌人尝试对玩家造成伤害，**THEN** 该伤害被忽略（无敌帧保护）。

- **GIVEN** GSM 状态从 EXPLORATION 变为 TRANSFORMATION，**WHEN** `state_changed` 信号触发，**THEN** 玩家 `move_speed`/`attack_damage`/`attack_range`/`collider` 切换为 FormConfig 中的值。

- **GIVEN** GSM 状态从 TRANSFORMATION 变为 COOLDOWN，**WHEN** `state_changed` 信号触发，**THEN** 玩家属性恢复为人类形态默认值。

- **GIVEN** 玩家同时按下 W 和 D 键，**WHEN** 调用 `move_and_slide()`，**THEN** 玩家以 `200 / √2 ≈ 141.4 px/s` 的速度沿对角线移动（归一化防止斜向加速）。

- **GIVEN** 攻击范围内无敌人，**WHEN** `attack_interval` 到期，**THEN** 不触发任何攻击（无空挥效果、无伤害施加）。

- **GIVEN** 游戏运行 60 秒，**WHEN** 检查帧率，**THEN** 玩家系统的 `_process` 不导致帧率下降（移动+攻击检测 <0.5ms/帧）。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 玩家是否需要"冲刺/闪避"能力（短距离瞬移 + 短暂无敌帧）？这会增加操作维度但偏离"纯走位"的 Survivor 类型纯度。 | 否——MVP 仅移动+攻击 | 原型测试时评估——如果走位深度不够，添加冲刺作为变异效果 |
| 2 | 自动攻击是否应显示攻击动画（如挥剑）还是仅显示伤害数字 + 命中特效？攻击动画增加视觉反馈但需要更多精灵资产（每形态一套攻击动画）。 | 否——MVP 可仅用命中特效 + 伤害数字 | 艺术圣经和玩家精灵资产到位后决定 |
| 3 | 玩家碰撞体应为圆形（简化碰撞）还是胶囊形（更精确的像素级碰撞）？圆形碰撞体在 Godot 中性能更好且对像素游戏足够。 | 否——圆形是合理的默认选择 | 实现阶段——若测试中发现碰撞判定不公，切换为更精确的形状 |
| 4 | 人类形态的自动攻击表现——近战挥砍（前方锥形）还是圆形范围（周身攻击）？当前设计假定圆形范围（简化——不需要朝向判断）。 | 否——圆形范围对 MVP 足够 | 敌人系统 GDD 完成后交叉验证——如果敌人设计倾向于方向性攻击，调整为锥形 |
