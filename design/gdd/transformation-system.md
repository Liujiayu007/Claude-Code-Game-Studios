# Transformation System — 变身系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation) — Primary Carrier

## Overview

变身系统（Transformation System）是 Shapeshift Survivor 的决定性系统——它就是游戏名称中的"Shapeshift"。它是 Pillar 1（爆发变身）的核心载体，负责管理从人类到怪物的形态切换、变身期间的行为替换、狂暴强化阶段、以及变身后的冷却恢复。

**玩家体验**：经过数十秒的蓄能（吸收系统 + 击杀敌人），形态计量表终于满格——屏幕边缘发光、音效渐强至顶峰、HUD 提示"按 Space 变身"。玩家按下变身键的瞬间——屏幕闪光、角色精灵替换为巨大的野兽/龙形、攻击模式从基础的近战挥砍变为毁灭性的范围撕裂/火焰吐息、移动速度飙升、敌人如割草般倒下。这个"爆发时刻"持续 5-10 秒，然后——形态褪去，玩家回到脆弱的人类形态，冷却计时器开始倒数，循环重新开始。

**MVP 范围——2 个形态**：

| 形态 | 名称 | 攻击风格 | 幻想原型 |
|------|------|---------|---------|
| **Beast** | 兽形态 | 近战范围撕裂——高速移动 + 周身大范围近战攻击 | 狂战士——冲入敌群撕裂一切 |
| **Dragon** | 龙形态 | 远程锥形吐息——慢速移动 + 前方大范围火焰伤害 | 毁灭法师——从远处焚烧战场 |

泰坦形态（Titan——超大碰撞体 + 全屏震荡）推迟至 Vertical Slice。

**技术骨架**：变身系统不直接操控玩家节点——它通过 GSM 状态转换和 Config 数据驱动行为。当玩家激活变身：变身系统从 Config 读取目标形态的 `FormConfig` → 调用 `GSM.request_transition(TRANSFORMATION, {form: "beast"})` → 玩家系统在收到 `state_changed` 后应用 FormConfig 的属性替换。变身系统管理持续时间和冷却的计时器、检测狂暴触发条件、以及变身结束时的自动回退。

**没有这个系统会失去什么**：Shapeshift Survivor 不再是 Shapeshift Survivor——它变成了一个普通的 Survivor 游戏，玩家在原地攻击敌人，没有爆发、没有节奏、没有"蓄能→爆发"的情感弧线。变身系统是游戏的灵魂——它是玩家 30 秒循环中期待的巅峰时刻。

## Player Fantasy

变身系统**就是** Shapeshift Survivor 的核心幻想——它不是在"支撑"某个支柱，它**就是**支柱 1 本身。

> **"我变成了怪物——而且感觉真他妈爽。"**

这不是一个属性 buff。这不是"攻击力 +50%"。这是你的角色从屏幕上一小块像素变成了占据半个屏幕的巨兽——攻击从一次打一个敌人变成一次扫清一整片——移动从小心翼翼走位变成在敌群中横冲直撞。变身瞬间的视听冲击（屏幕闪光、爆发音效、精灵替换）必须让玩家每次按下变身键时都感到一种原始的满足感。

**变身的三个情感阶段：**

1. **期待（蓄能→满格）**: 计量表在填充——音效在渐强——屏幕边缘开始发光——HUD 提示闪烁。玩家感到"快要来了"——这是一种愉悦的紧张感，类似于过山车爬升到顶点前的瞬间。

2. **爆发（按下变身键→形态激活）**: 屏幕闪光 + 角色炸裂式变身 + 攻击模式立即改变 + 周围敌人被冲击波震退。这是整个 30 秒循环的巅峰——玩家等待的就是这一刻。视觉和音频必须匹配这个时刻的重要性——这不能是"一个安静的状态切换"，这必须是一次**事件**。

3. **碾压（变身持续期间→狂暴触发→冷却开始）**: 玩家在形态中以全新的能力横冲直撞。如果计量表再次填满——狂暴触发——攻击再加倍，屏幕效果再升一级。然后形态褪去——不是突然消失，而是有视觉过渡（如光晕消散）。玩家回到人类形态，冷却计时器开始——**但现在他们已经在期待下一次了。**

**参考游戏中类似的感觉：**
- **Nioh 2 的妖怪化**——这是最接近的参考。按下妖怪化按钮的瞬间，角色模型改变、攻击模式完全替换、Yokai Force 计量表在燃烧。我们的变身应该达到这个级别的视觉冲击力。
- **Vampire Survivors 的武器进化**——当武器达到满级并进化时，屏幕效果急剧升级。但这是被动的（条件满足后自动触发）。我们的变身在"手动激活"这点上给予了玩家更多掌控感——按下按钮的那一刻是玩家主动发起的"爆发"。
- **Doom (2016) 的 Berserk 强化**——拾取 Berserk 球后，音乐切换、画面变红、近战攻击变成一击必杀的处决动画。Berserk 期间的"无敌感"是我们的狂暴子系统的参考目标。

## Detailed Design

### Core Rules

**Rule 1: FormConfig 定义所有形态参数**

每个形态对应一个 `FormConfig` Resource（存储在 `assets/config/forms/`）。形态参数在 Config 中定义——变身系统读取但不修改。

**Rule 2: 手动激活——计量表满 + 玩家按键**

变身需要两个条件同时满足：(a) 吸收系统的 `meter_current >= meter_max`，(b) 玩家按下 `transform_activate`。两个条件缺一不可——计量表未满时按键无效，计量表满时不按键保持 CHARGING（受衰减规则影响）。

**Rule 3: 形态选择——当前激活形态**

MVP 阶段玩家拥有 1 个默认形态（Beast）——计量表满时按下变身键直接激活。当玩家解锁多个形态后（Vertical Slice），变身系统支持通过 UI 或快捷键选择当前激活形态。`current_form_id` 属性追踪当前选择的形态。

**Rule 4: 持续时间管理**

进入 TRANSFORMATION 状态时，变身系统启动 `duration_timer`（值 = `FormConfig.duration`）。计时器使用 `delta * GSM.time_scale`（在 UPGRADE 状态下自动暂停）。计时器到期时，自动调用 `GSM.request_transition(COOLDOWN)`。

**Rule 5: 冷却时间管理**

进入 COOLDOWN 状态时，变身系统启动 `cooldown_timer`（值 = `FormConfig.cooldown`）。冷却期间：(a) 玩家处于人类形态（基础属性），(b) 吸收效率 × 0.1，(c) `transform_activate` 输入被 GSM 状态过滤（不可用）。计时器到期后，若 `meter_current > 0` 则 GSM 自动转换至 CHARGING，否则至 EXPLORATION。

**Rule 6: 狂暴触发**

在 TRANSFORMATION 状态期间，如果 `meter_current` 再次达到 100% 且形态支持狂暴（`FormConfig.has_berserk = true`），变身系统自动调用 `GSM.request_transition(BERSERK, {form: current_form_id})`。狂暴是自动触发的——无需玩家按键。狂暴有独立的、更短的持续时间（`FormConfig.berserk_duration`），到期后直接进入 COOLDOWN。

**Rule 7: 形态切换流程（玩家系统视角）**

变身系统不直接修改玩家节点。流程为：
1. 变身系统调用 `GSM.request_transition(TRANSFORMATION, metadata)`，metadata 携带 `form_id`
2. GSM 发出 `state_changed(old, TRANSFORMATION, metadata)`
3. 玩家系统收到信号，从 metadata 中提取 `form_id`，从 Config 读取 `FormConfig`
4. 玩家系统应用：`move_speed`、`attack_pattern`、`attack_damage`、`attack_range`、`collider_shape`、`sprite`
5. VFX 系统收到信号，播放变身爆发特效
6. 音频系统收到信号，播放变身爆发音效

变身系统只负责**时机**——什么时候开始、什么时候结束、什么时候狂暴。玩家系统、VFX 系统、音频系统负责**执行**。

### Form Definitions (MVP)

#### Beast Form — 兽形态

| 属性 | 值 | 说明 |
|------|-----|------|
| `form_id` | `"beast"` | 唯一标识符 |
| `display_name` | "兽形态" | 玩家可见名称 |
| `duration` | 8.0s | 变身持续时间 |
| `cooldown` | 15.0s | 变身后冷却时间 |
| `move_speed` | 300 px/s | 移动速度（人类: 200） |
| `attack_damage` | 25 | 每次攻击伤害（人类: 5） |
| `attack_range` | 96 px | 攻击范围半径（人类: 48） |
| `attack_interval` | 0.3s | 攻击间隔（人类: 0.8s） |
| `attack_pattern` | `circular_aoe` | 周身圆形范围攻击——每次攻击伤害范围内所有敌人 |
| `collider_radius` | 16 px | 碰撞体半径（人类: 8）——更大的身体 |
| `has_berserk` | true | 支持狂暴 |
| `berserk_duration` | 4.0s | 狂暴持续时间 |
| `berserk_damage_mult` | 2.0 | 狂暴期间攻击力倍率 |
| `berserk_speed_mult` | 1.5 | 狂暴期间移动速度倍率 |
| `sprite_key` | `"beast_form"` | 精灵资源标识符 |

**攻击行为**：每 0.3 秒，对玩家周围 96px 半径内的所有敌人造成 25 点伤害。视觉表现为红色撕裂特效环绕角色。

#### Dragon Form — 龙形态

| 属性 | 值 | 说明 |
|------|-----|------|
| `form_id` | `"dragon"` | 唯一标识符 |
| `display_name` | "龙形态" | 玩家可见名称 |
| `duration` | 10.0s | 变身持续时间（比 Beast 长） |
| `cooldown` | 20.0s | 冷却时间（比 Beast 长） |
| `move_speed` | 150 px/s | 移动速度（比人类还慢——站桩输出） |
| `attack_damage` | 40 | 每次攻击伤害 |
| `attack_range` | 200 px | 攻击范围（前方锥形长度） |
| `attack_angle` | 60° | 锥形角度 |
| `attack_interval` | 0.5s | 攻击间隔 |
| `attack_pattern` | `cone_aoe` | 前方锥形范围攻击——伤害锥形范围内的所有敌人 |
| `collider_radius` | 20 px | 碰撞体半径——最大的身体 |
| `has_berserk` | true | 支持狂暴 |
| `berserk_duration` | 5.0s | 狂暴持续时间 |
| `berserk_damage_mult` | 2.5 | 狂暴期间攻击力倍率 |
| `berserk_speed_mult` | 1.0 | 狂暴期间移动速度倍率（仍慢——龙形态不靠速度） |
| `sprite_key` | `"dragon_form"` | 精灵资源标识符 |

**攻击行为**：每 0.5 秒，对玩家前方 60° 锥形、200px 范围内的所有敌人造成 40 点伤害。视觉表现为火焰吐息特效。

### Transformation Lifecycle

```
CHARGING (meter=100%)
  │ player presses transform_activate
  ▼
TRANSFORMATION START (t=0)
  │ GSM → TRANSFORMATION
  │ Player swaps to FormConfig
  │ VFX: screen flash + transformation burst
  │ Audio: transformation boom
  │ duration_timer starts (8-10s)
  ▼
TRANSFORMATION ACTIVE
  │ Player uses form abilities
  │ Meter continues filling
  │
  ├─ meter=100% AND has_berserk → BERSERK (see Part 4)
  │
  └─ duration_timer expires
      ▼
    COOLDOWN (t=0)
      │ GSM → COOLDOWN
      │ Player reverts to human form
      │ VFX: form fade-out
      │ cooldown_timer starts (15-20s)
      │ Absorption efficiency ×0.1
      ▼
    COOLDOWN EXPIRES
      │ cooldown_timer expires
      │ meter>0 → CHARGING
      │ meter=0 → EXPLORATION
```

### Berserk Sub-State

狂暴是变身的"第二阶段"——在变身期间计量表再次填满时自动触发。

**触发条件**（三个条件必须同时满足）：
1. 当前状态 = TRANSFORMATION
2. `meter_current >= meter_max`（吸收系统在变身期间继续收集点数）
3. `FormConfig.has_berserk = true`

**行为**：
- 自动触发——不等待玩家按键
- 进入 BERSERK 状态（GSM）
- 原有变身持续时间计时器**暂停**——狂暴持续时间接管
- 攻击力 × `berserk_damage_mult`，移速 × `berserk_speed_mult`
- VFX：额外视觉层（如 Beast 狂暴=红色光环，Dragon 狂暴=火焰翅膀）
- 狂暴持续时间到期 → 直接进入 COOLDOWN（不回到普通变身）

**如果形态不支持狂暴**：计量表在 100% 时停止增长——不进入狂暴，保持普通变身至持续时间结束。

### Interactions with Other Systems

| 系统 | 交互 | 内容 |
|------|------|------|
| 数据配置系统 | 查询 | 读取 `FormConfig`——所有形态参数 |
| 游戏状态管理 | 订阅+调用 | 订阅 `state_changed`；调用 `request_transition(TRANSFORMATION/BERSERK/COOLDOWN)` |
| 玩家系统 | 间接 | 通过 GSM 状态 + FormConfig 驱动玩家行为切换 |
| 吸收系统 | 订阅 | 订阅 `meter_full`；查询 `meter_current` 检测狂暴触发条件 |
| HUD/UI 系统 | 暴露 | `current_form_id`, `duration_remaining`, `cooldown_remaining`, `is_berserk` |
| VFX 系统 | 触发 | 变身爆发、狂暴光环、形态褪去特效 |
| 音频系统 | 触发 | 变身爆发音、狂暴音、冷却结束提示音 |
| 变异系统 | 被查询 | 变异效果可修改 FormConfig 参数（如 +2s duration） |

## Formulas

### F.1 Duration Tracking

```
duration_remaining -= delta * GSM.time_scale
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| duration_remaining | float | 0 – FormConfig.duration | 变身剩余秒数 |
| delta | float | > 0 | 帧增量时间（秒） |
| GSM.time_scale | float | 0 or 1 | 游戏时间流速（UPGRADE/DEATH 时 = 0 暂停） |

当 `duration_remaining <= 0` 时，发出 `transformation_expired` → GSM 转换至 COOLDOWN。

### F.2 Cooldown Tracking

```
cooldown_remaining -= delta * GSM.time_scale
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| cooldown_remaining | float | 0 – FormConfig.cooldown | 冷却剩余秒数 |
| delta | float | > 0 | 帧增量时间 |
| GSM.time_scale | float | 0 or 1 | 游戏时间流速 |

当 `cooldown_remaining <= 0` 时：若 `meter_current > 0` → CHARGING，否则 → EXPLORATION。

### F.3 Berserk Trigger Check

```
can_berserk = (GSM.current_state == TRANSFORMATION)
              AND (meter_current >= meter_max)
              AND (FormConfig.has_berserk == true)
```

三个条件必须同时为真。为真时，变身系统调用 `GSM.request_transition(BERSERK, {form: current_form_id})`。此检查在 TRANSFORMATION 状态下每帧运行。

### F.4 Berserk Duration Override

```
berserk_remaining -= delta * GSM.time_scale
// 原有的 duration_timer 暂停——不递减
```

狂暴激活时：变身的 `duration_remaining` 暂停（不重置——保留当前值）。独立的 `berserk_remaining = FormConfig.berserk_duration` 开始倒计时。当 `berserk_remaining <= 0` 时，发出 `berserk_expired` → GSM 直接转换至 COOLDOWN（跳过普通变身阶段）。

### F.5 Form Stat Application

```
effective_stat = FormConfig.base_stat * stat_multiplier

// stat_multiplier 取决于状态：
//   TRANSFORMATION → 1.0
//   BERSERK         → berserk_damage_mult（仅 attack_damage）
//                      berserk_speed_mult（仅 move_speed）
```

| Stat | Beast (TRANS) | Beast (BERSERK) | Dragon (TRANS) | Dragon (BERSERK) |
|------|---------------|-----------------|----------------|------------------|
| move_speed | 300 | 300 × 1.5 = 450 | 150 | 150 × 1.0 = 150 |
| attack_damage | 25 | 25 × 2.0 = 50 | 40 | 40 × 2.5 = 100 |
| attack_range | 96 | 96（不变） | 200 | 200（不变） |
| attack_interval | 0.3s | 0.3s（不变） | 0.5s | 0.5s（不变） |

狂暴倍率仅作用于 `attack_damage` 和 `move_speed`。范围、间隔和碰撞体在狂暴期间不变。

### F.6 Meter Consumption on Transform

```
// 进入 TRANSFORMATION 时：
meter_current = 0  // 始终归零
```

依据吸收系统规则 6，进入 TRANSFORMATION 时 `meter_current` 重置为 0。计量表上限为 100，因此不存在溢出场景。

### F.7 Beast Circular AOE Damage

```
// 每次攻击判定（每 attack_interval = 0.3s）：
for each enemy in active_enemies:
    distance = (enemy.global_position - player.global_position).length()
    if distance <= effective_attack_range:
        enemy.take_damage(effective_attack_damage)
```

圆形半径内所有敌人每攻击周期受到一次伤害。无目标数量上限——命中范围内一切敌人。

### F.8 Dragon Cone AOE Filter

```
// 每次攻击判定（每 attack_interval = 0.5s）：
for each enemy in active_enemies:
    to_enemy = enemy.global_position - player.global_position
    distance = to_enemy.length()
    if distance > effective_attack_range:
        continue
    angle = rad_to_deg(to_enemy.angle_to(player.aim_direction))
    if abs(angle) <= attack_angle / 2:  // 60° 锥形 = ±30°
        enemy.take_damage(effective_attack_damage)
```

仅伤害处于前方锥形（以瞄准方向为中心、半角范围内）且距离 ≤ 最大射程的敌人。

## Edge Cases

- **如果玩家在计量表满的同一帧按下变身键，但 GSM 尚未从 CHARGING 切换**：`transform_activate` 在 CHARGING 状态下有效（见 GSM 状态输入过滤）。若计量表恰好在同一帧因衰减降至 < 100%，变身系统在扣除 `meter_current` 前检查 `meter_current >= meter_max`——条件不满足，变身不触发，按键无效。

- **如果 duration_remaining 归零与狂暴触发发生在同一帧**：先检查狂暴条件。若满足 → 进入 BERSERK（duration_remaining 暂停，不会同时到期）。若不满足 → 正常进入 COOLDOWN。两个事件不会同时发生——狂暴检查优先于持续时间到期。

- **如果玩家在变身期间死亡**：GSM 的 DEATH 状态优先级最高（见 GSM GDD 规则 4）。进入 DEATH 时 `time_scale = 0`，变身计时器自然暂停。形态褪去——玩家系统恢复到人类视觉/碰撞体（由玩家系统处理死亡重置）。变身系统清理所有变身计时器。

- **如果玩家在变身期间进入 UPGRADE 状态**：GSM `time_scale = 0` 暂停变身持续时间。变身视觉效果保持——玩家在升级界面背景中仍看到自己的变身形态。退出 UPGRADE → TRANSFORMATION 时，`duration_remaining` 从暂停位置继续。升级不会"吃掉"变身时间。

- **如果冷却结束但玩家处于 BOSS 状态**：GSM 状态转换优先级规则决定了 BOSS > COOLDOWN。冷却计时器到期时检查 `GSM.current_state`——若当前状态不是 COOLDOWN（如被 BOSS 状态抢占），不执行 COOLDOWN → CHARGING 转换。等待 BOSS 状态结束后再根据 `meter_current` 决定进入 CHARGING 还是 EXPLORATION。

- **如果 FormConfig 数据缺失或损坏**：变身系统在初始化时加载 `assets/config/forms/` 下的所有 FormConfig。若目标 `form_id` 的 Config 加载失败，`request_transition(TRANSFORMATION)` 调用被拒绝——发出 `transformation_failed(reason: "config_missing")` 信号，HUD 显示错误提示。玩家保持在 CHARGING 状态，可重试。

- **如果玩家在 COOLDOWN 期间反复按变身键**：COOLDOWN 状态下 `transform_activate` 被 GSM 输入过滤屏蔽——按键无任何效果。HUD 可选显示冷却剩余时间以告知玩家。

- **如果计量表在狂暴期间再次填满**：不二次触发狂暴——狂暴不可嵌套。当 `GSM.current_state == BERSERK` 时跳过狂暴检查。计量表保持在 100% 停止增长（与 `has_berserk = false` 形态的行为一致）。

- **如果玩家在变身激活后的瞬间帧（< 0.05s）受到致命伤害**：不存在窗口期问题——变身调用 `GSM.request_transition(TRANSFORMATION)` 是同步的，形态替换在 `state_changed` 信号处理中立即完成。玩家 HP 在形态切换时不受影响——HP 不变，仅攻击模式/碰撞体/精灵切换。

- **如果 Dragon 形态的锥形攻击方向在攻击间隔之间改变**：攻击判定在每攻击周期的瞬间计算——以该帧的 `player.aim_direction` 为基准。玩家在 0.5s 攻击间隔之间的旋转不影响已结算的伤害。0.5s 后下一攻击周期使用新的瞄准方向。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 数据配置系统 | `FormConfig` Resource——所有形态参数（duration、cooldown、move_speed、attack_damage、attack_range、attack_pattern、collider_radius、has_berserk、berserk_duration、berserk 倍率、sprite_key） |
| 游戏状态管理 | `GSM.request_transition(TRANSFORMATION/BERSERK/COOLDOWN)`——触发状态转换；`GSM.current_state`——查询当前状态以判断变身/狂暴/冷却是否合法；`GSM.time_scale`——驱动计时器暂停；订阅 `state_changed` 信号——响应外部状态变更 |
| 玩家系统 | 响应 `state_changed(TRANSFORMATION, {form_id})` 信号 → 应用 FormConfig 的 `move_speed`、`attack_damage`、`attack_range`、`attack_pattern`、`collider_shape`、`sprite`；响应 `state_changed(COOLDOWN)` → 恢复 HumanConfig 的人类形态属性 |
| 吸收系统 | 订阅 `meter_full` 信号 → 获知计量表满；查询 `meter_current` → 检测狂暴触发条件（≥ `meter_max`）；进入 TRANSFORMATION 时 `meter_current` 归零由吸收系统响应 `state_changed` 执行 |

### 下游依赖方

| 系统 | 依赖内容 |
|------|---------|
| HUD/UI 系统 | 暴露 `current_form_id`、`duration_remaining`、`cooldown_remaining`、`is_berserk`——HUD 渲染变身计量表、持续时间条、冷却倒计时、狂暴状态标识 |
| VFX 系统 | 变身爆发、狂暴光环、形态褪去特效——VFX 系统响应 GSM 状态变更信号播放对应特效 |
| 音频系统 | 变身爆发音、狂暴激活音、冷却结束提示音——音频系统响应 GSM 状态变更信号播放对应音效 |
| 变异系统 | FormConfig 参数可被变异效果修改（如 `duration + 2s`、`cooldown - 3s`、`attack_damage × 1.2`）——变异系统查询并临时覆写 FormConfig 中的数值 |
| 形态解锁系统（Vertical Slice） | `current_form_id` 的可用选项由其解锁状态决定——解锁系统在变身系统初始化时提供已解锁形态列表 |
| 新手引导系统（Full Vision） | 引导玩家完成首次"蓄能→变身→冷却"循环——需要变身系统的状态信号来推进引导步骤 |

### 接口契约

变身系统向消费方暴露：

1. `current_form_id: String` (只读) — 当前选择的形态标识符
2. `duration_remaining: float` (只读) — 变身剩余秒数（仅在 TRANSFORMATION/BERSERK 状态下有效，否则为 0）
3. `cooldown_remaining: float` (只读) — 冷却剩余秒数（仅在 COOLDOWN 状态下有效，否则为 0）
4. `is_berserk: bool` (只读) — 当前是否处于狂暴子状态
5. `available_forms: Array[String]` (只读) — 已解锁的可选形态列表
6. `transformation_started(form_id: String)` 信号 — 变身激活时发出
7. `transformation_expired()` 信号 — 变身持续时间到期时发出
8. `berserk_activated()` 信号 — 狂暴触发时发出
9. `berserk_expired()` 信号 — 狂暴到期时发出
10. `cooldown_complete()` 信号 — 冷却结束时发出
11. `transformation_failed(reason: String)` 信号 — 变身尝试被拒绝时发出（如 Config 缺失）

## Tuning Knobs

变身系统的所有可调参数定义在 `FormConfig` Resource 中（由数据配置系统管理）。以下是各参数的玩法影响和安全范围：

| 参数 | Beast 默认值 | Dragon 默认值 | 安全范围 | 玩法影响 |
|------|-------------|-------------|---------|---------|
| `duration` | 8.0s | 10.0s | 4–15s | 变身时长。太短→爆发感不足，来不及享受形态能力；太长→变身不再珍贵，冷却等待显得更漫长 |
| `cooldown` | 15.0s | 20.0s | 8–30s | 冷却时长。太短→变身几乎无缝（失去"人类脆弱期"的紧张感）；太长→玩家等待过久（节奏断裂） |
| `move_speed` | 300 | 150 | 100–500 px/s | 形态移动速度。Beast 高速→冲入敌群撕裂；Dragon 低速→站桩远程输出。速度差是形态身份的核心 |
| `attack_damage` | 25 | 40 | 10–100 | 每次攻击伤害。太低的伤害让变身感觉不"爆发"——与人类攻击力（5）的对比是变身满足感的关键 |
| `attack_range` | 96 | 200 | 48–300 px | 攻击范围。Beast 近战→周身安全感；Dragon 远程→前方压制感 |
| `attack_interval` | 0.3s | 0.5s | 0.1–1.0s | 攻击频率。频率 × 伤害 = DPS。Beast 高频近战，Dragon 低频高伤 |
| `collider_radius` | 16 | 20 | 8–32 px | 碰撞体大小。更大→更容易被敌人命中（变身的代价），但视觉上更巨大（变身的满足） |
| `has_berserk` | true | true | bool | 是否支持狂暴。关闭→该形态为"单阶段"变身，比较简单 |
| `berserk_duration` | 4.0s | 5.0s | 2–8s | 狂暴时长。应明显短于基础变身持续时间——狂暴是短暂的更高峰 |
| `berserk_damage_mult` | 2.0 | 2.5 | 1.2–4.0 | 狂暴攻击倍率。太高→狂暴秒杀一切（无挑战）；太低→感觉不到狂暴的存在 |
| `berserk_speed_mult` | 1.5 | 1.0 | 1.0–2.5 | 狂暴移速倍率。Beast 狂爆加速→冲得更快；Dragon 保持 1.0→移速不是 Dragon 的 fantasy |
| `attack_angle` | — | 60° | 30–120° | 仅 Dragon。锥形角度。太小→难以命中；太大→失去"前方"的定位感 |

### 核心平衡公式

```
transform_uptime_ratio = duration / (duration + cooldown)
```

- Beast: `8 / (8 + 15) = 34.8%` 的时间处于变身
- Dragon: `10 / (10 + 20) = 33.3%` 的时间处于变身

约 1/3 时间在"爆发"，2/3 时间在"蓄能"——这是一个经过验证的愉快比例。

```
变身 DPS 优势 = effective_attack_damage / attack_interval / 人类 DPS
```

- Beast TRANS vs 人类: `(25 / 0.3) / (5 / 0.8) = 83.3 / 6.25 = 13.3x`
- Dragon TRANS vs 人类: `(40 / 0.5) / (5 / 0.8) = 80 / 6.25 = 12.8x`
- Beast BERSERK vs 人类: `(50 / 0.3) / (5 / 0.8) = 166.7 / 6.25 = 26.7x`

变身 DPS 是人类形态的 13-27 倍——这个巨大差距是"爆发变身"支柱的数学基础。

## Visual/Audio Requirements

变身系统不自行实现视觉或音频——它向 VFX 系统和音频系统发出信号触发。以下是每个变身阶段必须兑现的视听需求：

### 视觉需求

| 时机 | 需求 | 优先级 | 描述 |
|------|------|--------|------|
| 计量表接近满格（>80%） | 屏幕边缘发光 | MVP | 屏幕四角/边缘出现形态主题色的微光脉冲（Beast=橙红，Dragon=紫红）。强度随计量表从 80%→100% 递增 |
| 计量表满格 | HUD 变身提示闪烁 | MVP | "按 Space 变身" 文字提示出现并脉冲闪烁（见 UI Requirements） |
| 变身激活瞬间 | 屏幕闪光 + 角色变身爆发 | MVP | 全屏白闪（1-2 帧）+ 角色位置爆发形态主题色粒子环。精灵从人类替换为形态精灵（硬切——像素艺术中过渡帧会模糊） |
| 变身激活瞬间 | 冲击波震退 | Vertical Slice | 玩家周围小范围冲击波特效，敌人被推开一小段距离（~30px）——强化"炸裂变身"的感觉 |
| 变身持续期间 | 形态视觉标识 | MVP | Beast：角色周围持续红色撕裂粒子 + 每次攻击时 96px 圆形撕裂特效；Dragon：角色前方 60° 锥形火焰吐息 + 角色周身微小火苗 |
| 狂暴激活 | 狂暴视觉层 | MVP | Beast 狂暴：角色叠加红色光环；Dragon 狂暴：角色叠加火焰翅膀。狂暴视觉层叠加在基础变身视觉之上——不替换 |
| 变身/狂暴结束 | 形态褪去 | MVP | 形态精灵渐隐（~0.2s 溶解效果或光晕消散），人类精灵渐显。不是突然消失——有视觉过渡 |
| 冷却期间 | 冷却视觉指示 | MVP | 形态计量表显示冷却进度（见 UI Requirements）。可选：角色色调略微偏灰，表示"弱化"状态 |
| 冷却结束 | 冷却完成提示 | MVP | 计量表边框短闪光（~0.3s），表示蓄能已恢复 |

### 音频需求

| 时机 | 需求 | 优先级 | 描述 |
|------|------|--------|------|
| 计量表填充中（0→100%） | 渐强蓄能音 | MVP | 持续低音嗡鸣，音调随计量表填充而上升。从几乎听不到（0%）到明显但不刺耳（100%）。音调曲线为对数——前期缓慢上升，接近满格时加速 |
| 计量表满格 | "叮"提示音 | MVP | 短促清亮提示音（~0.3s），与 HUD 变身提示同步。与吸收系统的收集提示音不同——音调更高、更突出 |
| 变身激活瞬间 | 变身爆发音 | MVP | 强冲击音（~0.5s）——低频"砰" + 形态主题元素音（Beast=野兽咆哮、Dragon=火焰喷发声）。这是全游戏最重要的单一音效——必须匹配"爆发"时刻的重要性 |
| 野兽形态持续 | 持续低吼 | Vertical Slice | 变身期间持续播放的野兽低吼循环，增强"我是怪物"的感觉 |
| 龙形态持续 | 火焰燃烧循环 | Vertical Slice | 变身期间持续播放的火焰噼啪循环 |
| 狂暴激活 | 狂暴音响升级 | MVP | 在基础变身音上加一层——音调升高、音量增大、节奏加快。Beast 狂暴=咆哮更猛烈；Dragon 狂暴=火焰更猛烈 |
| 变身/狂暴结束 | 形态褪去音 | MVP | 反向爆发音——从强到弱的下行音效（~0.5s），与视觉褪去同步 |
| 冷却结束 | 冷却完成提示音 | MVP | 短促"复活"音效（~0.3s），与冷却完成视觉闪光同步——告知玩家"可以再次蓄能了" |

### 跨阶段原则

- **形态主题色一致性**：Beast 使用橙红/血红调，Dragon 使用紫红/深红调。所有该形态的视觉特效和 HUD 元素统一使用对应主题色
- **像素艺术限制**：所有特效维持像素艺术风格——64px 精灵分辨率、无平滑渐变、硬边粒子形状。不使用高分辨率粒子或 3D 粒子系统
- **音量优先级**：变身爆发音 > 狂暴激活音 > 蓄能渐强音 > 形态持续循环音。重要时刻的音效应盖过其他声音——变身瞬间需要短暂的音频焦点

## UI Requirements

变身系统不直接产生 UI——HUD/UI 系统查询变身系统的公开属性来渲染界面元素。以下定义变身系统向 UI 提供的所有数据，以及 UI 该如何呈现它们：

### UI 暴露数据

| 属性 | 类型 | 更新频率 | 用途 |
|------|------|---------|------|
| `meter_current` | float (0–100) | 每帧 | 形态计量表填充百分比——来自吸收系统，HUD 渲染为计量表条 |
| `meter_max` | int (100) | 常量 | 计量表最大值 |
| `current_form_id` | String | 形态切换时 | 当前激活形态——HUD 显示形态名称/图标 |
| `duration_remaining` | float | 每帧 | 变身剩余秒数——HUD 渲染为倒计时条（仅在 TRANSFORMATION/BERSERK 时显示） |
| `cooldown_remaining` | float | 每帧 | 冷却剩余秒数——HUD 渲染为冷却进度条（仅在 COOLDOWN 时显示） |
| `is_berserk` | bool | 状态切换时 | 是否狂暴——HUD 切换显示模式 |
| `available_forms` | Array[String] | 解锁时 | 可选形态列表——HUD 渲染形态选择器（Vertical Slice） |

### HUD 布局需求

**形态计量表（始终可见，战斗 HUD 核心元素）**：
- 位置：屏幕底部居中，紧贴玩家角色下方区域
- 样式：横向长条，宽约 200px，高约 12px
- 填充颜色：Beast = 橙红，Dragon = 紫红。未填充部分 = 深灰半透明
- 动画：填充时平滑增长（lerp 到目标值，不是硬跳）。满格时边框脉冲发光
- 形态图标：计量表左侧显示当前激活形态的小图标（16×16 px）

**变身提示（仅在计量表满格时显示）**：
- 位置：计量表正上方
- 内容："按 [Space] 变身"（[Space] 使用按键绑定图标——如果玩家改键，自动显示对应按键名）
- 动画：脉冲缩放（1.0x ↔ 1.1x，周期 ~0.8s）+ 透明度呼吸（70% ↔ 100%）
- 颜色：形态主题色

**持续时间条（仅在 TRANSFORMATION/BERSERK 时显示）**：
- 位置：计量表正上方（替换变身提示的位置）
- 样式：横向细条，宽 150px，高 6px。颜色 = 形态主题色（Berserk 时更亮/更饱和）
- 动画：从满到空的倒计时——剩余时间直接映射为条宽度
- 数字：条右侧显示秒数（如 "7.2s"），字号 12px

**狂暴标识（仅在 BERSERK 时显示）**：
- 位置：持续时间条上方或替换持续时间条的文字部分
- 内容："狂暴!" 文字（形态主题色 + 更亮），与持续时间数字交替显示或并排显示
- 动画：文字脉冲缩放（比变身提示更剧烈——1.0x ↔ 1.2x）

**冷却进度条（仅在 COOLDOWN 时显示）**：
- 位置：与计量表同一位置（替换计量表填充色）
- 样式：灰色冷却进度从左到右填充——方向与蓄能相反（冷却完成 = 条变空 = 恢复蓄能能力）
- 数字：条右侧显示冷却剩余秒数（如 "12.3s"）

**形态选择器（Vertical Slice）**：
- 仅在玩家解锁多个形态后出现
- 位置：计量表右侧或下方
- 样式：小图标行——每个已解锁形态一个图标，当前选中形态高亮
- 交互：按 `form_switch_next` / `form_switch_prev` 切换，或点击图标（如果支持鼠标）

## Acceptance Criteria

- **AC1 — 手动激活变身**：**GIVEN** GSM 状态 = CHARGING 且 `meter_current >= 100`，**WHEN** 玩家按下 `transform_activate`，**THEN** GSM 转换为 TRANSFORMATION，玩家属性替换为 `FormConfig` 中的形态属性（move_speed、attack_damage、attack_range、attack_pattern、collider_radius、sprite），`meter_current` 重置为 0。

- **AC2 — 计量表不满时按键无效**：**GIVEN** GSM 状态 = CHARGING 且 `meter_current = 85`（< 100），**WHEN** 玩家按下 `transform_activate`，**THEN** 无任何状态变更，玩家保持 CHARGING，所有属性保持人类形态。

- **AC3 — 持续时间结束进入冷却**：**GIVEN** GSM 状态 = TRANSFORMATION 且 Beast `duration = 8.0s`，**WHEN** `duration_remaining` 递减至 0，**THEN** GSM 转换为 COOLDOWN，玩家属性恢复为 HumanConfig 人类形态，`cooldown_remaining = 15.0s`（Beast cooldown）。

- **AC4 — 冷却结束后进入蓄能**：**GIVEN** GSM 状态 = COOLDOWN 且 `meter_current > 0`，**WHEN** `cooldown_remaining` 递减至 0，**THEN** GSM 转换为 CHARGING。

- **AC5 — 冷却结束后计量表为空进入探索**：**GIVEN** GSM 状态 = COOLDOWN 且 `meter_current = 0`，**WHEN** `cooldown_remaining` 递减至 0，**THEN** GSM 转换为 EXPLORATION。

- **AC6 — 狂暴自动触发**：**GIVEN** GSM 状态 = TRANSFORMATION，`meter_current >= 100`，且 `FormConfig.has_berserk = true`，**WHEN** 每帧狂暴检查运行，**THEN** GSM 自动转换为 BERSERK（无需玩家按键），攻击力 × `berserk_damage_mult`，移速 × `berserk_speed_mult`，原有的 `duration_remaining` 暂停。

- **AC7 — 狂暴不支持时不触发**：**GIVEN** GSM 状态 = TRANSFORMATION，`meter_current >= 100`，但 `FormConfig.has_berserk = false`，**WHEN** 每帧狂暴检查运行，**THEN** 不触发狂暴，计量表停止在 100%，变身正常持续至 `duration_remaining` 到期。

- **AC8 — 狂暴结束后直接进入冷却**：**GIVEN** GSM 状态 = BERSERK 且 Beast `berserk_duration = 4.0s`，**WHEN** `berserk_remaining` 递减至 0，**THEN** GSM 直接转换为 COOLDOWN（不回到普通 TRANSFORMATION），玩家属性恢复为 HumanConfig。

- **AC9 — Beast 圆形 AOE 命中所有范围内敌人**：**GIVEN** 玩家处于 Beast TRANSFORMATION，`attack_range = 96`，**WHEN** 攻击周期触发且 96px 半径内有 5 个敌人，**THEN** 5 个敌人均受到 25 点伤害。

- **AC10 — Dragon 锥形 AOE 仅命中锥形内敌人**：**GIVEN** 玩家处于 Dragon TRANSFORMATION，`attack_range = 200`，`attack_angle = 60°`，**WHEN** 攻击周期触发，前方锥形内有 3 个敌人、锥形外有 2 个敌人（但在 200px 范围内），**THEN** 锥形内 3 个敌人各受 40 点伤害，锥形外 2 个敌人不受伤害。

- **AC11 — COOLDOWN 状态下变身键被屏蔽**：**GIVEN** GSM 状态 = COOLDOWN，**WHEN** 玩家按下 `transform_activate`，**THEN** 输入被 GSM 状态过滤拦截——无效果。

- **AC12 — 变身期间死亡**：**GIVEN** GSM 状态 = TRANSFORMATION 且玩家 HP 降至 0，**WHEN** GSM 转换至 DEATH，**THEN** 所有变身计时器清理、形态视觉效果结束、玩家精灵恢复为人类形态。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 变身期间是否应提供短暂无敌（如变身瞬间 0.3s 无敌帧）？当前设计变身不改变 HP——玩家在变身期间仍然脆弱。若变身瞬间被击杀会严重破坏 fantasy。 | 否——MVP 可先不加 | 原型测试手感后决定 |
| 2 | Dragon 形态的锥形攻击方向由什么决定？选项：A) 玩家最近移动方向，B) 朝向最近敌人的方向（自动瞄准），C) 独立瞄准输入（鼠标/右摇杆）。自动瞄准（B）最简单但减少操作感，独立瞄准（C）提供最大掌控但增加输入复杂度。 | 否——MVP 可用选项 B（自动瞄准最近敌人） | Dragon 形态实现时确认 |
| 3 | 多个形态解锁后（Vertical Slice），形态之间的冷却是否共享？共享冷却→变身选择是战前决策（进对局前选形态），独立冷却→可在对局中切换形态。 | 否——MVP 仅 1 个形态 | Vertical Slice 阶段设计形态解锁系统时决定 |
| 4 | 变身期间是否应免疫或减免某些伤害类型？例如 Beast 形态获得 30% 伤害减免（狂战士 fantasy——越战越勇），Dragon 形态仍全额受伤（玻璃大炮）。 | 否——MVP 不加 | 原型测试后评估是否需要生存能力差异 |
| 5 | 如果玩家在 COOLDOWN 状态结束时恰好在敌人包围中（无蓄能），是否有"保底"机制确保玩家不被"困住"？例如冷却结束后立即给予少量点数（如 10 点 = 10%）或短暂无敌？当前设计依赖已有的 `meter_current`——如果冷却期间收集了点数（×0.1 效率），冷却结束后可能 > 0。 | 否——×0.1 倍率提供了最低限度的进展 | 原型测试——若冷却结束→立即死亡的场景频繁出现，需添加保底 |
| 6 | Beast 和 Dragon 的攻击范围（96px / 200px）是否需要攻击动画来传达范围感？像素艺术 64px 分辨率下，200px Dragon 锥形可能需要屏幕空间的 ~1/3——如何在不使用范围指示器的前提下让玩家感知范围？ | 否——MVP 依赖视觉特效（火焰粒子覆盖锥形区域）传达 | VFX 系统 GDD 设计 Dragon 火焰特效时确认视觉传达方案 |
