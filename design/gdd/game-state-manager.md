# Game State Manager — 游戏状态管理

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation) + Pillar 3 (Paced Mastery)

## Overview

游戏状态管理（Game State Manager）是 Shapeshift Survivor 的全局状态机——它是所有其他系统判断"现在应该做什么"的单一真相源。它定义了游戏任意时刻所处的 8 个高层级状态，管理状态之间的合法转换，并通过信号通知所有订阅系统当前状态已变更。

这 8 个状态是：**探索、蓄能、变身、狂暴、冷却、升级、Boss、死亡**。每个状态定义了一个行为模式——例如，在"蓄能"状态下，吸收系统以更高效率填充形态计量表；在"变身"状态下，玩家系统的攻击模式被完全替换；在"升级"状态下，所有敌人暂停移动等待玩家做出变异选择。

系统以 Autoload 单例形式存在，在任何其他系统之前完成初始化。其他系统不自行追踪"现在是变身还是冷却"——它们查询 Game State Manager 的当前状态，并订阅状态转换信号以在转换发生时立即响应。

**没有这个系统会失去什么**：每个系统需要自行追踪游戏状态并猜测其他系统的当前状态——导致状态不一致（变身系统认为正在变身，但敌人系统仍在移动）、转换 bug（从变身直接跳到升级跳过冷却）、以及无法在全局层面理解"当前游戏在做什么"。Game State Manager 用一个统一的、可预测的状态机取代了分散在各处的布尔标志位。

从玩家视角，状态机是透明的——但他们感受到的一切节奏都来自它：什么时候能变身、什么时候敌人暂停、什么时候 BGM 切换。它是"蓄能→爆发"循环的骨架——不直接创造情感，但没有它，情感弧线会崩塌。

## Player Fantasy

游戏状态管理系统本身不产生玩家幻想——它是一个静默的基础设施层，玩家永远不会看到"状态机"或意识到它的存在。它的"幻想"体现在它管理的节奏中：

> **"节奏即掌控"** —— 玩家感受到的不是 8 个状态的切换，而是一个清晰、可预测的情感弧线：探索的从容 → 蓄能的紧张 → 变身的爆发 → 狂暴的碾压 → 冷却的脆弱 → 再次蓄能的循环。状态机是这个弧线的骨架——没有它，节奏崩塌；有了它，玩家沉浸于流程而从不质疑"为什么敌人突然停了"或"为什么变身结束了"。

**该系统间接支撑的游戏支柱：**

- **支柱 1（爆发变身）**: 状态转换序列——探索→蓄能→变身→狂暴→冷却——就是"蓄能→爆发"情感弧线的精确实现。每个状态定义了一个情感阶段，转换定义了节奏。变身不是"一个持续 N 秒的 buff"——它是从"蓄能"状态到"变身"状态的转换瞬间（屏幕闪光 + 音效）加上"变身"状态内的行为替换。

- **支柱 3（节奏掌控）**: 状态机是"节奏"的数学定义。哪些状态允许玩家自由移动（探索/蓄能/冷却）、哪些状态强制暂停游戏时间（升级）、哪些状态改变玩家能力（变身/狂暴）、哪些状态移除玩家控制（死亡）——这些规则定义了玩家"掌控"的边界。Paced Mastery 的本质是：玩家在探索/蓄能阶段感到可控，在变身阶段感到强大，在冷却阶段感到脆弱——状态机确保这些阶段以正确的顺序和正确的转换条件发生。

**参考游戏中类似的基础设施感受：**
- **Vampire Survivors** 的"探索→被包围→武器进化清场"节奏——玩家不感知状态机，但感受到"糟了→来了→爽了"的弧线。我们的状态机做了同样的事，但更精确地分割了各阶段。
- **Hades** 的"遭遇战→清场→选择奖励"节奏——玩家在遭遇战结束后自然地期待奖励选择，因为状态转换（战斗→清场→升级）是可靠的。

**"出问题时玩家会感受到什么"（基础设施的幻想测试）：**
- 当状态机**正确**时，玩家什么都不会注意到——节奏流畅、转换自然、从不困惑"现在能变身吗？"
- 当状态机**错误**时——在变身中途突然弹出升级界面、Boss 战中冷却状态被跳过、死后仍能移动——玩家的沉浸感立刻崩塌。这不是玩家在批评状态机；这是玩家在感受**游戏规则的不可靠**。

## Detailed Design

### Core Rules

**Rule 1: 全局单例 + 单一当前状态**

Game State Manager（以下简称 GSM）以 Godot Autoload 形式存在，在任何其他系统之前完成初始化。任意时刻，游戏恰好处于 8 个状态之一。`current_state` 是只读属性，其他系统通过 `GSM.current_state` 查询，但绝不可直接写入。

**Rule 2: 合法转换白名单**

GSM 维护一个硬编码的状态转换白名单。只有白名单中的转换可以被请求。请求非法转换（如从"死亡"跳转到"变身"）时，GSM 拒绝请求并打印 error 日志。这防止了"变身中途弹出升级界面"类的 bug。

**Rule 3: 转换信号广播**

状态转换成功时，GSM 按以下顺序执行：
1. 验证请求的转换在白名单中
2. 执行当前状态的 `exit` 行为（如"升级"状态退出时恢复游戏时间流速）
3. 更新 `current_state` 为新状态
4. 执行新状态的 `enter` 行为（如"变身"状态进入时设置时间流速为 1.0）
5. 发出 `state_changed(old_state, new_state)` 信号

其他系统通过订阅此信号或在其 `_process` 中查询 `current_state` 来响应状态变化。信号发射顺序保证所有订阅者在同一帧内收到通知。

**Rule 4: 状态行为由订阅系统执行，不由 GSM 执行**

GSM 只管理状态机逻辑（当前状态是什么 + 是否允许转换 + 转换信号）。GSM 不执行任何游戏逻辑——不移动玩家、不生成敌人、不修改 UI。当状态变为"变身"时，GSM 发出信号；玩家系统收到信号后自行替换攻击模式；VFX 系统收到信号后自行播放爆发特效。GSM 是交通指挥，不是车辆驾驶员。

**Rule 5: 时间流速控制**

GSM 通过 `time_scale` 属性控制游戏时间流速。仅在"升级"和"死亡"状态下修改该值——"升级"状态设为 0（暂停），"死亡"状态设为 0 或慢动作（待定），其余所有状态为 1（正常）。其他系统在需要暂停效果时查询 `GSM.time_scale`，不自行调用 `Engine.time_scale`。

**Rule 6: 状态转换请求接口**

其他系统通过 `GSM.request_transition(new_state)` 请求状态转换——不直接设置 `current_state`。GSM 验证转换合法性后执行。对于需要参数的状态转换（如"变身"需要知道是哪个形态），使用 `GSM.request_transition(new_state, metadata)` —— metadata 是一个可选的 Dictionary，携带转换附加上下文。

**Rule 7: 状态阻止（State Blocking）**

某些系统可以在特定条件下阻止状态转换。例如，Boss 登场动画播放期间，Boss 系统可以调用 `GSM.set_block("boss_intro", true)` 阻止任何状态转换。动画播放完成后调用 `set_block("boss_intro", false)` 解除阻止。GSM 维护一个阻塞标志字典——任一阻塞标志为 true 时，所有转换请求被拒绝（返回 false + warning 日志）。这防止了"Boss 登场动画还没播完就进入变身状态"的 bug。

### States and Transitions

#### 8 States Defined

| # | State | 中文名 | 描述 | 时间流速 | 玩家输入 | 典型持续时间 |
|---|-------|--------|------|---------|---------|------------|
| 1 | `EXPLORATION` | 探索 | 普通游玩——玩家移动、自动攻击、敌人正常生成和移动 | 1.0 | 完全控制 | 无限（直到发生事件） |
| 2 | `CHARGING` | 蓄能 | 与探索相同，但形态计量表正在填充，吸收效率提升 | 1.0 | 完全控制 | 数秒至数十秒 |
| 3 | `TRANSFORMATION` | 变身 | 形态激活——攻击模式替换、碰撞体变化、视觉切换 | 1.0 | 移动 + 形态攻击 | 由 FormConfig.duration 决定 |
| 4 | `BERSERK` | 狂暴 | 变身中的强化阶段——形态计量表在变身期间再次填满触发 | 1.0 | 移动 + 强化攻击 | 由 FormConfig.berserk_duration 决定 |
| 5 | `COOLDOWN` | 冷却 | 变身后恢复人形——脆弱期，无法再次变身 | 1.0 | 移动 + 基础攻击 | 由 FormConfig.cooldown 决定 |
| 6 | `UPGRADE` | 升级 | 波次清除——游戏暂停，展示 3-4 个变异选项 | 0.0 | 仅 UI 选择 | 无限（直到玩家选择） |
| 7 | `BOSS` | Boss | Boss 战进行中——Boss HP 条显示、BGM 切换 | 1.0 | 完全控制（可在 Boss 战中变身） | 直到 Boss 或玩家死亡 |
| 8 | `DEATH` | 死亡 | 玩家 HP 归零——游戏结束 | 0.0 或 0.1（慢动作） | 无 | 直到回到主菜单 |

#### State Transition Whitelist

```
EXPLORATION → CHARGING
EXPLORATION → UPGRADE
EXPLORATION → BOSS
EXPLORATION → DEATH

CHARGING → EXPLORATION      (meter decay to 0)
CHARGING → TRANSFORMATION   (meter full + player activates)
CHARGING → UPGRADE
CHARGING → BOSS
CHARGING → DEATH

TRANSFORMATION → BERSERK    (meter fills again during transformation)
TRANSFORMATION → COOLDOWN   (duration expires)
TRANSFORMATION → DEATH

BERSERK → COOLDOWN          (berserk duration expires)
BERSERK → DEATH

COOLDOWN → EXPLORATION      (cooldown timer expires)
COOLDOWN → CHARGING         (cooldown expires + meter > 0)
COOLDOWN → UPGRADE
COOLDOWN → BOSS
COOLDOWN → DEATH

UPGRADE → EXPLORATION       (mutation selected)
UPGRADE → CHARGING          (mutation selected + meter > 0)

BOSS → EXPLORATION          (boss defeated + meter = 0)
BOSS → CHARGING             (boss defeated + meter > 0)
BOSS → UPGRADE              (boss defeated → wave clear → mutation select)
BOSS → DEATH

DEATH → (仅可通过重新开始对局退出)
```

#### Meter Decay Rule

在 `CHARGING` 状态下，如果玩家在 `meter_decay_timeout` 秒内没有击杀任何敌人，形态计量表以 `meter_decay_rate`/秒的速度衰减。计量表降至 0 时，自动从 `CHARGING` 转换至 `EXPLORATION`。`meter_decay_timeout` 和 `meter_decay_rate` 为可调参数（定义在 `global.tres` 中，见 Tuning Knobs）。

#### BERSERK 触发条件

在 `TRANSFORMATION` 状态下，形态计量表继续填充（吸收系统在变身期间仍收集形态点数）。计量表再次达到 100% 时，自动进入 `BERSERK` 状态——无需玩家手动触发。如果形态不支持狂暴（`FormConfig.has_berserk = false`），则计量表在 100% 时停止增长，不进入 `BERSERK`。

#### BOSS 状态特殊规则

- 可以从任何非 DEATH/UPGRADE 状态进入 `BOSS` 状态（Boss 波开始时强制转换）
- 在 `BOSS` 状态下，玩家可以正常经历探索→蓄能→变身→冷却循环（BOSS 不等于"不能变身"）
- 在 `BOSS` 状态下波次清除规则暂停——没有小波清除事件，只有"Boss 死亡"一个出口事件
- Boss 死亡后的状态取决于是否触发了波次清除：若 Boss 是波次的最后一波 → 进入 `UPGRADE`；否则进入 `EXPLORATION` 或 `CHARGING`

### Interactions with Other Systems

GSM 与所有其他系统的交互遵循同一模式：**其他系统查询 `current_state` 或订阅 `state_changed` 信号，GSM 不主动调用任何游戏逻辑**。

#### 标准查询模式（每帧或按需）

每个系统在需要判断"当前能做什么"时，查询 `GSM.current_state`：

```gdscript
if GSM.current_state == GSM.State.EXPLORATION or GSM.current_state == GSM.State.CHARGING:
    # player can move and auto-attack normally
```

#### 标准订阅模式（状态转换响应）

每个需要响应状态转换的系统在初始化时订阅 `GSM.state_changed`：

```gdscript
GSM.state_changed.connect(_on_state_changed)

func _on_state_changed(old_state: GSM.State, new_state: GSM.State):
    match new_state:
        GSM.State.TRANSFORMATION:
            # replace attack pattern, play transformation VFX
        GSM.State.COOLDOWN:
            # restore human form, start cooldown timer
```

#### 各系统对 GSM 的具体依赖

| 消费方系统 | 查询/订阅 | 关键行为 |
|-----------|----------|---------|
| 玩家系统 | 订阅 `state_changed` | `EXPLORATION/CHARGING/COOLDOWN`: 人类移动+自动攻击；`TRANSFORMATION/BERSERK`: 替换为形态攻击模式、碰撞体；`DEATH`: 移除控制、播放死亡动画 |
| 敌人系统 | 查询 `current_state` (每帧) | `UPGRADE`: 暂停移动（`time_scale=0`）；`DEATH`: 停止 AI |
| 吸收系统 | 订阅 `state_changed` | `CHARGING/TRANSFORMATION`: 形态点数收集效率提升；`COOLDOWN`: 点数收集暂停或效率大幅降低 |
| 变身系统 | 订阅 `state_changed` | `CHARGING` 且计量表满: 显示变身提示；`TRANSFORMATION/BERSERK`: 管理持续时间和冷却计时器 |
| 波次系统 | 查询 `current_state` | `UPGRADE/DEATH`: 不生成新敌人；`BOSS`: 暂停普通波次生成 |
| 区域系统 | 订阅 `state_changed` | `BOSS`: 切换 BGM、显示 Boss HP 条 |
| HUD/UI 系统 | 订阅 `state_changed` | 每个状态切换对应的 UI 元素显示/隐藏（蓄能条、变身计时器、Boss HP 条等） |
| VFX 系统 | 订阅 `state_changed` | 状态转换瞬间播放对应特效（变身爆发闪光、狂暴强化光环等） |
| 音频系统 | 订阅 `state_changed` | 状态切换时切换 BGM 层级/播放转换音效 |
| 变异系统 | 查询 `current_state` | 仅在 `UPGRADE` 状态下显示升级界面 |
| Boss 系统 | 查询 `current_state` + 调用 `request_transition(BOSS)` | Boss 登场时强制转入 `BOSS` 状态；Boss 死亡时相应退出 |
| 对局管理系统 | 查询 `current_state` | `DEATH`: 触发对局结束流程；`UPGRADE`: 记录波次清除 |

**接口契约**: GSM 提供 `current_state`（只读属性）、`state_changed` 信号、`request_transition()` 方法。不提供任何游戏逻辑。消费方系统负责"知道状态后怎么行为"。

## Formulas

### D.1 State Transition Validation

The state transition validation formula is defined as:

```
is_valid_transition(from, to) = (from, to) ∈ WHITELIST
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 当前状态 | from | enum State | 8 values | Transition source state |
| 目标状态 | to | enum State | 8 values | Requested destination state |
| 转换白名单 | WHITELIST | Set<(State, State)> | 20-25 pairs | All valid (from, to) pairs |

**Output Range:** boolean — `true` if valid, `false` if illegal.

**Example:**
```
request: EXPLORATION → CHARGING
check:   (EXPLORATION, CHARGING) ∈ WHITELIST → true ✓
result:  transition proceeds

request: DEATH → TRANSFORMATION
check:   (DEATH, TRANSFORMATION) ∈ WHITELIST → false ✗
result:  request rejected + error log
```

### D.2 Meter Decay Timing

```
is_decaying(t) = (t - t_last_kill) > T_decay_timeout

meter(t) = meter(t_last_kill) - max(0, t - t_last_kill - T_decay_timeout) * R_decay

transition_to_exploration = meter(t) ≤ 0
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 当前时间 | t | float (seconds) | ≥ 0 | Current game time since run start |
| 最后一次击杀时间 | t_last_kill | float (seconds) | ≥ 0 | Game time at which the player last killed an enemy |
| 衰减等待时间 | T_decay_timeout | float | 2.0–10.0s | Grace period before decay begins (default: 3.0s) |
| 衰减速率 | R_decay | float | 5–25%/s | Percentage of full meter lost per second (default: 10%/s) |
| 当前计量表值 | meter(t) | float | 0–100% | Current form meter fill level |

**Output Range:** meter(t) ∈ [0, 100]. When meter(t) reaches 0, GSM auto-transitions CHARGING → EXPLORATION.

**Example:**
```
Given: T_decay_timeout = 3.0s, R_decay = 10%/s
t_last_kill = 10.0s, meter(10.0) = 60%

At t = 12.0s: t - t_last_kill = 2.0s < 3.0s → no decay, meter = 60%
At t = 15.0s: t - t_last_kill = 5.0s > 3.0s → decay active
  decay_amount = (5.0 - 3.0) * 10 = 20%
  meter(15.0) = 60 - 20 = 40%
At t = 20.0s: decay_amount = (10.0 - 3.0) * 10 = 70% → meter drops to 0
  → auto-transition to EXPLORATION
```

### D.3 Time Scale Determination

```
time_scale(state) = 
  | 0.0  if state = UPGRADE
  | T_death  if state = DEATH
  | 1.0  otherwise
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 死亡时间倍率 | T_death | float | 0.0–0.5 | Time scale during death state (0.0 = freeze, 0.1 = slow-motion) |

T_death 是可调参数——设计决策（死亡时是画面定格还是慢动作）待定。默认值：0.0（定格）。

**Output Range:** time_scale ∈ {0.0, T_death, 1.0}. No intermediate values used.

### D.4 State Blocking Check

```
is_blocked() = ∃ key ∈ blocks: blocks[key] = true
transition_allowed = is_valid_transition(from, to) AND NOT is_blocked()
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 阻塞标志字典 | blocks | Dictionary<String, bool> | N entries | Each key is a blocking reason identifier |

**Example:**
```
blocks = {"boss_intro": true, "death_animation": false}
is_blocked() → true (boss_intro is blocking)

GSM.request_transition(EXPLORATION, TRANSFORMATION)
  → is_valid_transition(EXPLORATION, TRANSFORMATION) → true
  → is_blocked() → true
  → REJECTED: "Transition EXPLORATION → TRANSFORMATION blocked by: boss_intro"
```

## Edge Cases

- **如果同一帧内多个系统请求不同的状态转换**（如波次系统请求 `→UPGRADE` 同时变身系统因计量表满请求 `→TRANSFORMATION`）：GSM 在每帧结束时按优先级处理请求。优先级顺序：DEATH > BOSS > UPGRADE > TRANSFORMATION > BERSERK > COOLDOWN > CHARGING > EXPLORATION。若两个请求指向不同目标状态，仅执行优先级更高的那个；低优先级的请求被丢弃并打印 warning 日志。这防止了"波次清除和变身同时发生，到底进入哪个状态"的不确定行为。

- **如果状态转换被阻塞时收到请求**：GSM 返回 `false` + warning 日志标明阻塞来源（如 `"blocked by: boss_intro"`）。请求不被排队——调用方系统需要稍后重新请求。这避免了"解除阻塞后一堆排队请求突然全部执行"的意外行为。

- **如果玩家在变身期间死亡**：DEATH 具有最高优先级。GSM 立即从 `TRANSFORMATION` 或 `BERSERK` 转换至 `DEATH`。玩家系统在收到 `state_changed(_, DEATH)` 后：停止所有攻击、播放死亡动画、清理形态视觉。变身持续时间计时器被放弃——死亡状态无冷却。

- **如果波次在变身期间清除**：这是合法场景——例如玩家在变身中清完了本波最后一个敌人。GSM 从 `TRANSFORMATION` 或 `BERSERK` 转换至 `UPGRADE`。变身持续时间计时器**暂停**（而非重置）——玩家从升级界面返回后，变身继续剩余时间。暂停通过 GSM 的 `time_scale=0`（升级状态）自然实现——变身系统的倒计时使用 `delta * GSM.time_scale`，因此在升级期间自动暂停。

- **如果形态计量表衰减至 0 和玩家按下变身键发生在同一帧**：衰减处理先于手动输入处理。若 `meter(t) ≤ 0`，GSM 已自动转换至 `EXPLORATION`，此后收到的 `→TRANSFORMATION` 请求被拒绝（`EXPLORATION → TRANSFORMATION` 不在白名单中——只有 `CHARGING → TRANSFORMATION` 是合法路径）。玩家看到一个"misinput"——变身键在计量表归零的瞬间按下，无事发生。这是预期行为：玩家应在计量表降至危险水平前激活变身。

- **如果 Boss 在变身期间登场**：Boss 波开始事件到来时，BOSS 状态优先级高于 TRANSFORMATION。GSM 从 `TRANSFORMATION` 切换至 `BOSS`。变身持续时间计时器**继续倒计时**（BOSS 状态 time_scale 为 1.0，与变身一致）。实际上，玩家在 Boss 战中以变身状态开始——这是有利场景。变身持续时间照常到期后，GSM 从 `BOSS` 内的变身逻辑转换至冷却（仍在 BOSS 状态下——玩家在 Boss 战中进入冷却/重新蓄能，状态保持在 `BOSS`）。

- **如果请求转换到当前状态**（如在 `EXPLORATION` 状态下请求 `→EXPLORATION`）：GSM 直接返回 `true`（不视为错误），但不发出 `state_changed` 信号（当前状态未变化）。这使调用方代码更简洁——系统可以无条件地"确保处于某状态"而无需先检查当前状态。

- **如果 GSM 尚未初始化时另一个系统查询 `current_state`**：GSM 的 `_ready()` 在所有其他 Autoload 之前执行（Config 第一，GSM 第二，其他按序排列）。因此此场景仅在代码中显式实例化 GSM 或从非 Autoload 的 `_init()` 调用时出现。GSM 的 `_init()` 将 `current_state` 初始化为 `EXPLORATION`（硬编码默认值），因此查询总是返回有效枚举值。但在此状态下调用 `request_transition` 会打印 warning："GSM not fully initialized — transition request deferred"。

- **如果玩家在变形计量表满时不立即变身（即挂机）**：CHARGING 状态下计量表保持 100%，不继续增长，衰减规则照常（如果长时间不击杀→衰减→跌落至 0→回到 EXPLORATION）。这是有意为之——允许玩家策略性地选择变身的时机（如等到更多敌人出现时），但不鼓励无限等待（衰减迫使他们最终失去充能或被迫使用变身）。

- **如果对局管理系统请求重启对局（DEATH → 新对局）**：GSM 提供特殊的 `reset()` 方法，绕过白名单直接重置所有内部状态——`current_state = EXPLORATION`、清空 `blocks` 字典、不发出 `state_changed` 信号。这避免了对局重启时状态机的"死亡→探索"转换被视为普通状态转换（其他系统应由对局管理系统通知对局重启，而非听到一个假的"死亡→探索"状态转换信号）。

## Dependencies

### 上游依赖（本系统依赖）

**无硬依赖。** 游戏状态管理是 Foundation 层系统，零上游硬依赖。它仅依赖 Godot 引擎内建的信号系统和枚举——这些是引擎提供的能力，不属于游戏系统。

**软依赖（增强功能但非必需）：**

| 系统 | 依赖内容 | 回退方案 |
|------|---------|---------|
| 数据配置系统 | 读取 `global.tres` 中的可调参数（`meter_decay_timeout`, `meter_decay_rate`, `T_death`） | GSM 内建硬编码默认值——Config 不可用时仍可正常运作 |

### 下游依赖方（依赖本系统）

所有需要感知或响应游戏状态的系统依赖 GSM。按依赖性质分类：

**硬依赖（系统无 GSM 无法正确运行）：**

| 系统 | 依赖内容 | 性质 |
|------|---------|------|
| 玩家系统 | 查询当前状态决定移动/攻击模式；订阅 `state_changed` 切换形态行为 | 无 GSM → 玩家不知道何时变身、何时恢复人形 |
| 变身系统 | 订阅 `state_changed` 管理变身持续时间/冷却/狂暴触发 | 无 GSM → 变身无计时管理、无法触发冷却 |
| 波次系统 | 查询当前状态决定是否生成敌人；订阅 `state_changed` 响应波次清除 | 无 GSM → 升级界面期间仍生成敌人 |
| 变异系统 | 仅在 `UPGRADE` 状态下展示升级界面 | 无 GSM → 升级界面随时弹出，打断游戏 |
| Boss 系统 | 请求 `→BOSS` 转换；查询当前状态管理 Boss 生命周期 | 无 GSM → Boss 登场/死亡无全局通知 |
| 对局管理系统 | 查询 `DEATH` 状态触发对局结束；调用 `reset()` 重启对局 | 无 GSM → 无法可靠检测对局结束 |

**软依赖（GSM 提升行为正确性但系统有合理回退）：**

| 系统 | 依赖内容 | 回退方案 |
|------|---------|---------|
| 敌人系统 | 查询 `UPGRADE/DEATH` 状态暂停 AI | 可通过 `time_scale=0` 间接暂停——但需自己追踪升级状态 |
| 吸收系统 | 查询 `CHARGING/COOLDOWN` 状态调整吸收效率 | 可通过自身逻辑判断（如有无变身冷却）替代 |
| HUD/UI 系统 | 订阅 `state_changed` 显示/隐藏 UI 元素 | 可自行查询多个系统拼凑"当前应该显示什么" |
| VFX 系统 | 订阅 `state_changed` 播放状态转换特效 | 可订阅变身系统/波次系统的独立信号替代 |
| 音频系统 | 订阅 `state_changed` 切换 BGM 层级 | 可订阅多个系统的独立信号拼凑音乐状态 |
| 区域系统 | 订阅 `state_changed` 响应 BOSS 状态 | 可订阅 Boss 系统信号替代 |

### 接口契约

GSM 向所有下游依赖方提供以下保证：

1. **可用性保证**: GSM 在 Config 之后、所有其他 Autoload 之前完成初始化——任何系统在其 `_ready()` 中查询 `GSM.current_state` 均返回有效值（最低为 `EXPLORATION`）
2. **一致性保证**: `current_state` 在同一帧内不变——所有系统在同一帧中查询得到相同状态值
3. **信号完整性保证**: 每次状态转换恰好发出一次 `state_changed` 信号——不丢、不重复
4. **阻塞可见性**: 当转换因阻塞被拒绝时，调用方收到明确的 `false` 返回值 + 日志标明阻塞来源

消费方应向 GSM 提供的保证：

1. **只读保证**: 不直接写入 `current_state`；所有转换通过 `request_transition()` 进行
2. **快速响应**: `state_changed` 信号回调中不执行耗时操作（如同步文件 I/O）——防止阻塞其他订阅者的信号处理
3. **状态无关性**: 不在收到 `state_changed` 信号后立即请求另一个状态转换（防止转换链式反应）——如确需连续转换，延迟至下一帧

## Tuning Knobs

### G.1 GSM 自身可调参数

这些参数控制 GSM 的行为，定义在 `assets/config/global.tres` 中：

| 参数 | 类型 | 默认值 | 安全范围 | 玩法影响 | 如果设置太高 | 如果设置太低 |
|------|------|--------|---------|---------|------------|------------|
| `meter_decay_timeout` | float | 3.0 | 1.0–10.0s | 击杀后形态计量表开始衰减前的宽限期。更长=更宽容（低压力），更短=更高紧迫感 | 玩家几乎感受不到衰减压力——充能可无限保持，降低变身时机的策略性 | 玩家刚杀完一个敌人就开始衰减——压迫感过强，惩罚短暂的走位调整 |
| `meter_decay_rate` | float | 10.0 | 2.0–30.0%/s | 衰减开始后每秒损失计量表百分比。更快=更强紧迫感 | 计量表在 3-4 秒内从满变空——玩家必须立即变身，无策略选择空间 | 衰减几乎不可见——与"无衰减"无异，失去"充能→爆发"的张力 |
| `death_time_scale` | float | 0.0 | 0.0–0.5 | 死亡状态的时间流速。0.0=定格，0.1-0.5=慢动作 | 慢动作过长影响重开对局的节奏 | 画面瞬间定格——可能让玩家困惑"发生了什么"（定格需配合视觉提示） |

**关联关系**：
- `meter_decay_timeout` 和 `meter_decay_rate` 共同决定"从满充能到自动归零"的总时间。例如 timeout=3s + rate=10%/s 意味着满充能(100%)在 13 秒后归零。调整其中一个应检查另一个，确保总窗口在 8-20 秒的可玩范围内。
- `meter_decay_timeout` 应大于玩家的典型走位调整时间（2-5 秒），确保玩家在正常游玩中不会因短暂的非击杀期而受惩罚。
- 这两个参数与吸收系统的"形态点数获得量"强关联——如果敌人掉落点数高（计量表填充快），衰减可以更激进；如果点数低，衰减应更温和。

### G.2 状态转换优先级

状态转换优先级是硬编码的（非可调参数），但在此明确列出以备未来调整：

| 优先级 | 状态 | 理由 |
|--------|------|------|
| 1 (最高) | DEATH | 死亡是最紧急事件——必须立即响应，任何延迟都会导致"死后仍能攻击"的 bug |
| 2 | BOSS | Boss 登场/死亡是全局事件——应覆盖大部分其他状态 |
| 3 | UPGRADE | 波次清除是阶段性事件——优先于玩法状态切换 |
| 4 | TRANSFORMATION | 变身是玩家主动触发的高价值事件 |
| 5 | BERSERK | 狂暴是变身的子事件——优先级略低于初始变身 |
| 6 | COOLDOWN | 冷却自动触发——最低紧急度 |
| 7 | CHARGING | 蓄能和探索是被动状态——仅在无事发生时存在 |
| 8 (最低) | EXPLORATION | 默认状态——当没有更紧急的事件时处于此状态 |

如需修改优先级（例如使 BERSERK 优先于 UPGRADE），需修改 GSM 源代码中的硬编码优先级别表。此设计选择的原因是优先级顺序定义了游戏的核心节奏——不应由设计师在配置文件中随意调整（可能导致不一致的游戏体验）。

### G.3 扩展新状态（流程）

当未来设计需要新增状态时（如 "PAUSED" 暂停菜单状态）：

1. 在 GSM 的 `State` 枚举中添加新值
2. 在白名单中添加新状态的合法入口和出口转换
3. 定义新状态的 entry/exit 行为（或标记为无操作）
4. 更新优先级列表——决定新状态在冲突解决中的位置
5. 通知所有订阅 `state_changed` 的系统更新其 match 分支

新状态应满足以下条件才可添加：
- 至少一个系统的行为因该状态而发生实质性改变（不仅仅是"标记"）
- 不能用现有状态的组合表达
- 其 entry/exit 行为与现有状态不冲突

## Visual/Audio Requirements

不适用。游戏状态管理系统不产生视觉或音频输出——它是一个纯逻辑层，在后台静默运行。然而，GSM 的状态转换是其他系统产生视觉/音频输出的**触发器**：

- VFX 系统订阅 `state_changed` → 在 `→TRANSFORMATION` 时播放变身爆发特效
- 音频系统订阅 `state_changed` → 在 `→CHARGING` 时渐强蓄能音效、在 `→TRANSFORMATION` 时播放变身爆发音
- HUD/UI 系统订阅 `state_changed` → 切换显示对应状态的 UI 元素

GSM 自身不关心这些效果如何实现——它只负责在正确的时间发出正确的信号。

## UI Requirements

不适用。游戏状态管理系统没有玩家可见的 UI。状态信息（如"当前是变身状态"）通过 HUD/UI 系统展示——HUD/UI 系统查询 `GSM.current_state` 决定显示哪些 UI 元素，但 UI 的布局、样式、动画由 HUD/UI 系统的 GDD 定义，不由 GSM 定义。

## Acceptance Criteria

- **GIVEN** 游戏启动且 GSM 完成初始化，**WHEN** 任意 Autoload 在其 `_ready()` 中查询 `GSM.current_state`，**THEN** 返回 `GSM.State.EXPLORATION`，`GSM.time_scale` 返回 `1.0`，且 `GSM.state_changed` 信号尚未被发出过（初始化不视为状态转换）。

- **GIVEN** 当前状态为 `EXPLORATION`，**WHEN** 调用 `GSM.request_transition(CHARGING)`，**THEN** 返回 `true`，`GSM.current_state` 变为 `CHARGING`，且 `GSM.state_changed` 信号携带 `(EXPLORATION, CHARGING)` 参数被发出。

- **GIVEN** 当前状态为 `DEATH`，**WHEN** 调用 `GSM.request_transition(TRANSFORMATION)`，**THEN** 返回 `false`，`GSM.current_state` 保持 `DEATH`，且控制台打印 error 日志标明非法转换。

- **GIVEN** 设置了阻塞标志 `blocks = {"boss_intro": true}`，**WHEN** 调用 `GSM.request_transition(UPGRADE)`（该转换在白名单中合法），**THEN** 返回 `false`，`GSM.current_state` 保持不变，且控制台打印 warning 日志标明阻塞来源 `"boss_intro"`。

- **GIVEN** 当前状态为 `CHARGING` 且 `meter_decay_timeout = 3.0s`、`meter_decay_rate = 10%/s`，**WHEN** 最后一次击杀发生在 14 秒前且初始计量表为 100%，**THEN** 计量表衰减至 0%，GSM 自动从 `CHARGING` 转换至 `EXPLORATION`，且 `state_changed(CHARGING, EXPLORATION)` 信号被发出。

- **GIVEN** 当前状态为 `CHARGING`，**WHEN** 同一帧内波次系统请求 `→UPGRADE` 且变身系统请求 `→TRANSFORMATION`，**THEN** 仅执行 `→UPGRADE`（优先级 3 > 优先级 4），`GSM.current_state` 变为 `UPGRADE`，`→TRANSFORMATION` 请求被丢弃 + warning 日志。

- **GIVEN** 当前状态为 `UPGRADE`，**WHEN** 查询 `GSM.time_scale`，**THEN** 返回 `0.0`。**AND** **WHEN** 任意系统在 `_process(delta)` 中使用 `delta * GSM.time_scale` 计算时间增量，**THEN** 该时间增量为 `0`（游戏时间暂停）。

- **GIVEN** 当前状态为 `TRANSFORMATION` 且形态支持狂暴（`has_berserk = true`），**WHEN** 形态计量表在变身期间再次达到 100%，**THEN** GSM 自动从 `TRANSFORMATION` 转换至 `BERSERK`，且 `state_changed(TRANSFORMATION, BERSERK)` 信号被发出。

- **GIVEN** 当前状态为 `TRANSFORMATION` 且变身持续时间到期，**WHEN** 变身系统的计时器触发 `request_transition(COOLDOWN)`，**THEN** GSM 转换至 `COOLDOWN`，`state_changed(TRANSFORMATION, COOLDOWN)` 信号被发出，且 `GSM.time_scale` 保持 `1.0`。

- **GIVEN** 当前状态为 `TRANSFORMATION`，**WHEN** 玩家 HP 降至 0（死亡），**THEN** GSM 立即转换至 `DEATH`（即使变身持续时间尚未到期），变身计时器被放弃，且 `state_changed(TRANSFORMATION, DEATH)` 信号被发出。

- **GIVEN** 当前状态为 `DEATH`，**WHEN** 对局管理系统调用 `GSM.reset()`，**THEN** `GSM.current_state` 重置为 `EXPLORATION`，`blocks` 字典清空，且 **NO** `state_changed` 信号被发出（reset 不视为状态转换）。

- **GIVEN** 游戏已运行 60 秒且经历至少 20 次状态转换，**WHEN** 检查控制台日志，**THEN** 无"missed transition"、无"duplicate signal"、无"state mismatch"类错误日志。所有状态转换均通过合法白名单路径。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | `BERSERK` 是否需要作为独立状态？还是作为 `TRANSFORMATION` 内部的强化阶段（子状态）？如果合并，变身系统自己管理"普通变身 vs 狂暴"的差异，GSM 只需知道"正在变身"。这样减少状态数但增加变身系统的复杂度。 | 否——当前设计保留 BERSERK 为独立状态，后续若发现增加复杂度 > 收益，可合并 | 变身系统 GDD 设计时决定 |
| 2 | `DEATH` 状态的时间流速——定格（0.0）还是慢动作（0.1-0.3）？定格更清晰但可能让玩家困惑"游戏卡住了"；慢动作更有戏剧性但需要额外实现死亡慢动作视觉。 | 否——默认值 0.0 可运作 | 视觉特效系统 GDD 设计时决定（需要配合死亡视觉效果） |
| 3 | 形态计量表衰减曲线——当前设计为线性衰减（固定速率）。是否需要加速衰减（越接近 0 衰减越快，倒逼玩家在计量表下降前变身）？加速衰减增加紧迫感，但使玩家更难预测"还剩多少时间"。 | 否——线性衰减对 MVP 足够；加速衰减可在后续迭代中添加 | 原型测试阶段通过 playtest 比较两种曲线 |
| 4 | 状态转换优先级——当前优先级顺序（DEATH > BOSS > UPGRADE > TRANSFORMATION > ...）是否在所有场景下正确？例如，如果 Boss 在变身期间登场，当前设计从变身切换到 BOSS 状态，变身计时器继续倒计时——这对玩家有利。但如果设计方向变了（变身应被 Boss 登场强制结束），则需要调整优先级或 Boss 状态的 entry 行为。 | 否——当前优先级可运作 | 波次系统 + Boss 系统 GDD 设计时交叉确认 |
| 5 | `EXPLORATION` 和 `CHARGING` 是否应该合并为一个状态？两者的差异仅在于"形态计量表是否 > 0"。如果合并，系统通过 `meter > 0` 判断而非 `current_state == CHARGING`，减少状态数但增加各系统的条件判断复杂度。 | 否——当前设计保留两个状态，因为音效、VFX、吸收效率在两个状态下有实质性差异 | 吸收系统 GDD 设计时决定——如果吸收系统设计中两状态行为差异很小，则应合并 |
| 6 | GSM 是否应追踪"前一个状态"（`previous_state`）供系统查询？例如，从 `UPGRADE` 返回时需要知道"升级前是探索还是变身"来决定回到哪个状态。当前设计通过状态转换白名单解决（UPGRADE → EXPLORATION 或 CHARGING），但如果返回逻辑变复杂，可能需要 `previous_state`。 | 否——当前白名单方法覆盖所有 MVP 场景 | 实现阶段——如果发现某个系统反复需要"know where we came from"，则添加 |
