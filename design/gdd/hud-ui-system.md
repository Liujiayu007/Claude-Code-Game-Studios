# HUD/UI System — HUD/UI 系统

> **Status**: In Design
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation) + Pillar 3 (Paced Mastery)

## Overview

HUD/UI 系统（HUD/UI System）是 Shapeshift Survivor 中玩家与游戏状态之间的信息桥梁——它不产生任何游戏逻辑，但它决定了玩家在每一帧看到的、感知到的、以及据此做出的每一个决策。HUD/UI 系统从 5 个上游系统（玩家、变身、吸收、波次、GSM）读取数据，将其转化为屏幕上可见的信息元素：HP 条、形态计量表、变身持续时间/冷却倒计时、波次进度、Boss 警告、以及变异升级界面。

**技术骨架**：HUD/UI 系统是订阅型消费方——它不调用上游系统的逻辑方法，而是订阅 GSM 的 `state_changed` 信号和各个系统的属性变化信号来驱动 UI 切换。战斗 HUD 的核心元素根据 GSM 状态动态显示/隐藏：EXPLORATION/CHARGING 状态下显示 HP 条 + 形态计量表 + 波次进度；TRANSFORMATION/BERSERK 状态下计量表替换为持续时间倒计时条 + 狂暴标识；COOLDOWN 状态下显示冷却进度条。升级界面（UPGRADE 状态）由变异系统提供选项数据，HUD/UI 系统负责渲染 3-4 个变异卡片并处理玩家选择输入。

**玩家体验**：HUD/UI 系统是"信息清晰度"的守护者——玩家在密集敌群中不需要主动寻找信息；HP 低时屏幕边缘变红、计量表满时变身提示脉冲闪烁、冷却结束时短闪光告知。优秀的 HUD 让玩家从不困惑"我现在能变身吗"或"还剩多少时间"——它在正确的时间显示正确的信息，在不需要时隐藏，不干扰屏幕空间。UI 的视觉语言（颜色、动画节奏、字体大小）必须与游戏的核心节奏同步——蓄能阶段的渐强、变身爆发的瞬间冲击、冷却阶段的安静恢复。

**没有这个系统会失去什么**：玩家在黑暗中摸索——不知道 HP 还剩多少、不知道计量表是否满了、不知道变身还剩几秒、不知道这是第几波。信息缺失导致困惑、错误决策、以及"游戏不公平"的感受。HUD/UI 系统让游戏状态对玩家透明——没有它，玩家无法制定策略，只能靠猜。

## Player Fantasy

HUD/UI 系统的幻想是**清晰**与**掌控**。玩家可能永远不会说"这游戏的 UI 真棒"，但他们会感受到"我永远知道发生了什么"——这就是 UI 在工作。

> **"一切尽在眼底。"**

在 Shapeshift Survivor 的战场上，玩家同时追踪 7 个信息维度：HP 还剩多少、形态计量表是否满了、现在是第几波、变身还剩几秒、冷却还要多久、敌人在哪里、该往哪走。优秀的 HUD 将这些信息压缩为屏幕边缘的几个视觉元素——玩家不需要主动寻找，眼角余光就能感知状态变化。HP 低时屏幕边缘泛红——这是本能级别的警告，不需要读数字。计量表满时变身提示脉冲闪烁——这是"按下去！"的冲动召唤。变身的持续时间条从满到空——每一像素的缩减都在问玩家"你还能用这力量杀多少敌人？"

**HUD 的情感层次**：

1. **蓄能阶段——期待感**：形态计量表从空到满，填充动画平滑但有重量感（每一点数都在推动条前进）。接近满格时（>80%），计量表边框开始脉冲发光——视觉在说"快了"。这是过山车爬升到顶点的视觉维度。玩家不需要盯着计量表——余光就能感受到边框的光越来越亮。

2. **变身爆发——满足感**：按下变身键的瞬间，HUD 切换模式——计量表位置突然变为持续时间倒计时条，数字在倒数，条在缩短。这个切换本身就是一个微妙的"事件确认"——UI 的变化告诉玩家"你做到了，现在你是怪物了"。狂暴触发时，倒计时条的颜色变亮/变饱和——UI 的一小步变化传达了"现在更猛了"。

3. **冷却阶段——脆弱与期待**：冷却进度条从满到空，方向与蓄能相反（冷却完成 = 条变空 = 恢复）。灰色的冷却条传递"现在你不是怪物"的信息。冷却结束的瞬间——短闪光 + 计量表恢复颜色——"又可以蓄能了！"

**该系统直接支撑的游戏支柱**：

- **支柱 1（爆发变身）**：形态计量表、变身提示、持续时间倒计时、狂暴标识——这四个 UI 元素是 Pillar 1 的视觉骨架。它们不创造变身的力量感（那是 VFX 和音频的工作），但它们创造变身的**期待感**和**时机感**——玩家看着计量表一格一格填满，感受到变身正在靠近；变身提示的出现是"释放"的信号；倒计时条的缩短是"珍惜每一秒"的提醒。

- **支柱 3（节奏掌控）**：波次计数器（"波次 3/5"）和剩余敌人数量是玩家制定策略的信息基础——"还有 12 个敌人，计量表 85%——能在波次清除前变身吗？"HP 条和冷却倒计时定义了玩家的风险承受边界——"HP 50%，冷却还有 10 秒——能撑住吗？"UI 让节奏从模糊的感觉变为可读的信息——玩家基于数据进行策略决策，而非凭感觉猜测。

**参考游戏中类似的 UI 感受**：
- **Vampire Survivors** 的极简 HUD——经验条在屏幕顶部居中，HP 条在角色上方浮动。没有多余信息，玩家眼睛不需要离开战场。我们的 HUD 采取同样的"信息在战场上"哲学——核心信息（HP、计量表、变身倒计时）紧贴玩家角色区域，而非屏幕角落。
- **Hades** 的 UI 动画质感——每一个 UI 变化都有动画过渡（不是硬跳），给 UI 一种"活的"感觉。我们的计量表填充使用 lerp 平滑过渡，变身提示使用脉冲呼吸动画，模式切换有过渡而非突然替换。
- **Dead Cells** 的"信息在余光中"——HP 条和弹药计数器的位置和颜色让玩家永远不需要直接盯着看。红色 = HP 低 = 本能级别的警告。

**"出问题时玩家会感受到什么"（UI 的幻想测试）**：
- 当 UI **正确**时，玩家感觉"一切在掌控中"——信息在需要时出现，在不需要时安静。玩家从来不困惑"我能变身吗？"或"还剩多少时间？"——UI 在正确的时间给了正确的信息。
- 当 UI **错误**时——计量表不动、倒计时数字跳变、波次显示错误、变身提示该出现时没出现——玩家立即失去对游戏状态的信任。UI 错误不是"视觉瑕疵"——它是"信息断裂"，直接影响玩家的决策质量和游戏体验。

## Detailed Design

### Core Rules

**Rule 1: 订阅式数据读取——不主动轮询**

HUD/UI 系统通过两种方式获取数据：(a) 订阅上游系统的 `changed` 类信号——当数据变化时上游推送更新，UI 响应更新，(b) 每帧查询只读属性——用于需要每帧更新的显示（如倒计时数字）。HUD/UI 系统绝不调用上游系统的逻辑方法——它是纯粹的消费方。

**Rule 2: GSM 状态驱动的元素可见性**

HUD 的核心元素根据 `GSM.current_state` 动态显示/隐藏。每个 UI 元素都有一个"可见状态列表"——只有在列表中的状态下该元素才渲染。不在列表中的状态下该元素透明度为 0（不渲染以节省性能）。

| UI 元素 | 可见状态 | 隐藏状态 |
|---------|---------|---------|
| HP 条 | EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS | UPGRADE, DEATH |
| 形态计量表 | EXPLORATION, CHARGING | TRANSFORMATION, BERSERK, COOLDOWN, UPGRADE, BOSS, DEATH |
| 变身提示 | CHARGING（仅当 meter >= meter_max） | 所有其他状态及 meter < meter_max 时 |
| 持续时间条 | TRANSFORMATION | BERSERK（替换为狂暴条）, EXPLORATION, CHARGING, COOLDOWN, BOSS, UPGRADE, DEATH |
| 狂暴标识 | BERSERK | 所有其他状态 |
| 冷却进度条 | COOLDOWN | BERSERK, TRANSFORMATION, EXPLORATION, CHARGING, BOSS, UPGRADE, DEATH |
| 波次进度 | EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN | UPGRADE, DEATH, BOSS（Boss 波期间替换为 Boss HP 条） |
| 剩余敌人 | EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN | UPGRADE, DEATH, BOSS |
| Boss HP 条 | BOSS | 所有其他状态 |
| 升级界面 | UPGRADE | 所有其他状态 |
| 死亡画面 | DEATH | 所有其他状态 |

**Rule 3: 单例 CanvasLayer——渲染层级独立**

HUD/UI 系统的所有元素渲染在独立的 `CanvasLayer` 节点上（layer 层级高于游戏世界层）。这确保 UI 始终渲染在游戏画面上方——不被精灵、粒子、或地图遮挡。CanvasLayer 不随摄像机移动——UI 在屏幕空间中是固定的。

**Rule 4: 动画过渡——禁止硬跳**

所有 UI 元素的数值变化使用平滑过渡（`lerp` / `Tween`），禁止数值硬跳。具体规则：
- 计量表/进度条：目标值变化时，当前显示值以 8-12 px/s 的速度 lerp 到目标值
- 元素显隐：使用透明度渐变（fade in 0.15s, fade out 0.2s），不使用 `visible = true/false` 硬切换
- 变身提示脉冲：scale 在 1.0x ↔ 1.1x 之间呼吸，周期 0.8s，alpha 在 0.7 ↔ 1.0 之间同步

**Rule 5: 低 HP 警告——屏幕边缘红色渐变**

当玩家 `hp_current / hp_max <= 0.3`（HP ≤ 30%）时，屏幕四边出现红色渐变（alpha 从 0 到 0.3，随 HP 降低而加深）。当 HP ≤ 15% 时，增加脉冲效果（alpha 呼吸 0.3 ↔ 0.5，周期 0.5s）。HP > 30% 时警告消失（alpha lerp 到 0，0.5s 平滑过渡）。此效果渲染在独立 CanvasLayer 上，不影响其他 UI 元素。

**Rule 6: 形态计量表颜色主题**

计量表填充色根据 `current_form_id` 动态切换：
- Beast（兽形态）：橙红色 `#FF6B35`
- Dragon（龙形态）：紫红色 `#C44B8B`
- 未解锁/无形态时（人类）：暗灰色 `#555555`

形态图标（16×16 px）显示在计量表左侧。图标资源键由变身系统的 `FormConfig.icon_key` 提供。

**Rule 7: 按键绑定显示**

变身提示文字"按 [Space] 变身"中的按键名从输入系统动态读取——如果玩家改键，UI 自动显示当前绑定的按键名。使用 `InputMap` 查询 `transform_activate` 动作的第一个绑定按键/键位，转换为可读文本。

**Rule 8: 性能约束——仅脏更新**

UI 元素仅在数据变化时重新渲染（脏标记模式）。对于需要动画的持续元素（倒计时数字、计量表 lerp），使用 Godot 的 `_process` 但限制更新频率——计量表 lerp 仅在其目标值变化后的过渡期间每帧更新；过渡完成后停止更新。静态文本（如波次数字、形态名称）仅在值变化时更新。

### HUD Layout

所有位置描述以 1920×1080 分辨率为设计基准，使用锚点（anchor）定位以适配不同分辨率。

#### 战斗 HUD 布局（由下至上）

**Layer 1 — 玩家角色上方（屏幕底部居中）**：

| 元素 | 锚点 | 位置 | 尺寸 | 说明 |
|------|------|------|------|------|
| HP 条 | 底部居中 | `(0, -80)` 偏移 | 宽 120px，高 8px | 绿色填充条，红色边框。HP 数字显示在条右侧："85/100" |
| 形态计量表 | 底部居中 | `(0, -60)` 偏移 | 宽 200px，高 12px | 形态主题色填充，未填充部分深灰半透明。左侧 16×16 形态图标 |
| 持续时间/冷却条 | 底部居中 | `(0, -60)` 偏移 | 宽 150px，高 6px | 与计量表同位置——状态切换时计量表渐隐 + 此条渐显 |
| 变身提示 | 底部居中 | `(0, -45)` 偏移 | 自适应文字宽度 | "按 [Space] 变身"——仅在计量表满时显示 |
| 狂暴标识 | 底部居中 | `(0, -35)` 偏移 | 自适应文字宽度 | "狂暴!" 文字——仅在 BERSERK 时显示 |

**Layer 2 — 屏幕顶部（左上/右上角）**：

| 元素 | 锚点 | 位置 | 尺寸 | 说明 |
|------|------|------|------|------|
| 波次进度 | 顶部居中 | `(0, 20)` 偏移 | 自适应文字宽度 | "波次 3/5"——白色文字，字号 16px |
| 剩余敌人 | 顶部居中 | `(0, 40)` 偏移 | 自适应文字宽度 | "剩余 12"——灰色文字，字号 12px |

**Layer 3 — Boss 战时替换元素**：

| 元素 | 锚点 | 位置 | 尺寸 | 说明 |
|------|------|------|------|------|
| Boss HP 条 | 顶部居中 | `(0, 24)` 偏移 | 宽 300px，高 16px | 红色填充条，BOSS 名称显示在条上方。仅在 BOSS 状态显示 |

**Layer 4 — 死亡画面**：

| 元素 | 锚点 | 位置 | 尺寸 | 说明 |
|------|------|------|------|------|
| "你死了" 文字 | 屏幕居中 | `(0, 0)` | 自适应 | 大号红色文字，淡入 0.5s |
| "按 Enter 重新开始" | 屏幕居中 | `(0, 60)` | 自适应 | 白色文字，淡入 0.5s（延迟 0.3s） |

#### 屏幕边缘 HP 警告

| 元素 | 锚点 | 尺寸 | 说明 |
|------|------|------|------|
| 红色渐变覆盖 | 全屏四边 | 边宽 40px | 从边缘向中心的红色渐变，alpha 由 HP 比例驱动。HP ≤ 30% 时出现 |

### Upgrade Screen

变异升级界面在 `UPGRADE` 状态下显示。MVP 阶段变异系统尚未实现——升级界面的完整规格在变异系统 GDD 中定义。HUD/UI 系统在此定义升级界面的布局骨架，变异系统填充具体选项内容。

**布局规则**：

| 规则 | 描述 |
|------|------|
| 背景 | 游戏画面 dim——叠加半透明黑色覆盖层（alpha 0.6） |
| 标题 | 屏幕顶部居中："选择一项升级"——白色文字，字号 24px |
| 选项卡片 | 屏幕中部水平排列 3-4 张卡片。每张卡片尺寸约 200×280px，卡片间距 20px。卡片内容由变异系统提供（图标 + 名称 + 描述 + 稀有度颜色边框） |
| 选中指示 | 当前高亮的卡片边框发光（金色），其他卡片边框暗色。键盘 ↑↓←→ 或手柄方向键切换选中 |
| 确认 | 按 `confirm`（Space/Enter/手柄 A）确认选择。选择后 GSM 退出 UPGRADE 状态 |

**MVP 简化**：变异系统未实现前，升级界面可显示占位卡片以验证 UI 布局和交互流程。

### Interactions with Other Systems

| 系统 | 方向 | 查询/订阅 | 内容 |
|------|------|----------|------|
| 游戏状态管理 | 订阅 | `state_changed` | 驱动所有 UI 元素的显示/隐藏切换。最重要的上游信号 |
| 玩家系统 | 查询 | `hp_current`, `hp_max` | HP 条填充比例 + 低 HP 警告触发。每帧查询（仅 HP 条和警告需要） |
| 吸收系统 | 查询 | `meter_current`, `meter_max` | 形态计量表填充比例。每帧查询（lerp 到目标值） |
| 变身系统 | 查询 | `current_form_id`, `duration_remaining`, `cooldown_remaining`, `is_berserk` | 形态图标切换、持续时间/冷却倒计时数字、狂暴标识显示。每帧查询（仅倒计时数字需要） |
| 波次系统 | 查询 | `current_wave`, `total_waves`, `enemies_remaining` | 波次进度显示、剩余敌人数字。仅在值变化时更新 |
| Boss 系统 | 查询 | Boss HP 当前值/最大值 | Boss HP 条。Boss 系统 GDD 尚未设计——预留接口 |
| 变异系统 | 被调用 | 升级界面选项数据 | 变异系统提供选项卡片数据（图标、名称、描述、稀有度），HUD/UI 渲染。Vertical Slice |
| 输入系统 | 查询 | 按键绑定名称 | 变身提示中的动态按键名。仅在初始化时查询一次，改键时刷新 |
| VFX 系统 | 间接 | — | UI 不触发 VFX。但 VFX 系统订阅的 GSM 信号与 UI 元素切换同步——两者由同一信号驱动，视觉上协调一致 |
| 音频系统 | 间接 | — | UI 不触发音频。但 UI 状态切换（变身提示出现/消失）与音频系统的蓄能渐强音同步——两者由同一 GSM 信号驱动 |

## Formulas

### F.1 HP Bar Fill Ratio

```
hp_fill = clamp(hp_current / hp_max, 0.0, 1.0)
hp_display_width = hp_fill * hp_bar_max_width
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| hp_current | int | 0–hp_max | 当前 HP（来自玩家系统） |
| hp_max | int | 50–500 | 最大 HP（来自 HumanConfig） |
| hp_fill | float | 0.0–1.0 | HP 条填充比例 |
| hp_bar_max_width | int | 120 | HP 条最大像素宽度 |

**Example**: hp_current=85, hp_max=100 → fill=0.85 → display_width=102px。

### F.2 Form Meter Fill Ratio

```
meter_fill = clamp(meter_current / meter_max, 0.0, 1.0)
meter_display_width = meter_fill * meter_bar_max_width
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| meter_current | float | 0–100 | 当前计量表值（来自吸收系统） |
| meter_max | int | 100 | 计量表最大值（常量） |
| meter_fill | float | 0.0–1.0 | 计量表填充比例 |
| meter_bar_max_width | int | 200 | 计量表最大像素宽度 |

**Example**: meter_current=85, meter_max=100 → fill=0.85 → display_width=170px。

### F.3 Duration / Cooldown Bar Fill Ratio

```
duration_fill = clamp(duration_remaining / FormConfig.duration, 0.0, 1.0)
cooldown_fill = 1.0 - clamp(cooldown_remaining / FormConfig.cooldown, 0.0, 1.0)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| duration_remaining | float | 0–FormConfig.duration | 变身剩余秒数（来自变身系统） |
| duration_fill | float | 0.0–1.0 | 持续时间条填充比例（从满到空） |
| cooldown_remaining | float | 0–FormConfig.cooldown | 冷却剩余秒数（来自变身系统） |
| cooldown_fill | float | 0.0–1.0 | 冷却条填充比例（从空到满——方向与持续时间相反） |

**注意**：持续时间条从 100% → 0%（倒计时——时间越少条越短）；冷却条从 0% → 100%（冷却进行——越来越多的条变为灰色）。冷却完成时 `cooldown_fill = 1.0`，但此时状态已切换到 CHARGING/EXPLORATION——冷却条不再渲染。

**Example (Beast 形态)**：
- 变身开始: duration_remaining=8.0, duration=8.0 → fill=1.0
- 变身 3 秒后: duration_remaining=5.0 → fill=0.625
- 冷却开始: cooldown_remaining=15.0, cooldown=15.0 → fill=0.0
- 冷却 5 秒后: cooldown_remaining=10.0 → fill=1.0-10.0/15.0=0.333

### F.4 Low HP Warning Alpha

```
hp_ratio = clamp(hp_current / hp_max, 0.0, 1.0)
if hp_ratio <= 0.15:
    warning_alpha = 0.3 + 0.2 * abs(sin(Time.get_ticks_msec() / 500.0 * PI))
elif hp_ratio <= 0.3:
    warning_alpha = (0.3 - hp_ratio) / 0.15 * 0.3  // 线性插值: hp_ratio=0.3→0, hp_ratio=0.15→0.3
else:
    warning_alpha = 0.0
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| hp_ratio | float | 0.0–1.0 | 当前 HP 比例 |
| warning_alpha | float | 0.0–0.5 | 屏幕边缘红色渐变的 alpha 值 |

**Example**:
- hp_current=100, hp_max=100 → hp_ratio=1.0 → warning_alpha=0（无警告）
- hp_current=25, hp_max=100 → hp_ratio=0.25 → warning_alpha=(0.3-0.25)/0.15×0.3=0.1
- hp_current=10, hp_max=100 → hp_ratio=0.1 → warning_alpha=0.3+0.2×|sin(…)|（脉冲 0.3↔0.5）

### F.5 Boss HP Bar Fill Ratio

```
boss_hp_fill = clamp(boss_hp_current / boss_hp_max, 0.0, 1.0)
boss_hp_display_width = boss_hp_fill * boss_bar_max_width
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| boss_hp_current | int | 0–boss_hp_max | Boss 当前 HP（来自 Boss 系统） |
| boss_hp_max | int | TBD | Boss 最大 HP（来自 BossConfig） |
| boss_hp_fill | float | 0.0–1.0 | Boss HP 条填充比例 |
| boss_bar_max_width | int | 300 | Boss HP 条最大像素宽度 |

**注**: Boss 系统 GDD 尚未设计——Boss HP 的数据接口为占位契约，待 Boss 系统 GDD 确认后更新。

### F.6 UI Element Visibility State Check

```
is_visible(element, state) = state ∈ element.visible_states
```

**每个元素的可见状态集合**（定义在 Core Rules Rule 2 的可见性表中）：

| 元素 | visible_states |
|------|---------------|
| HP 条 | {EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS} |
| 形态计量表 | {EXPLORATION, CHARGING} |
| 变身提示 | {CHARGING}（附加条件：meter_current >= meter_max） |
| 持续时间条 | {TRANSFORMATION} |
| 狂暴标识 | {BERSERK} |
| 冷却进度条 | {COOLDOWN} |
| 波次进度 | {EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN} |
| 剩余敌人 | {EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN} |
| Boss HP 条 | {BOSS} |
| 升级界面 | {UPGRADE} |
| 死亡画面 | {DEATH} |

## Edge Cases

- **如果 HUD/UI 初始化时上游系统尚未就绪**：HUD/UI 系统在 `_ready()` 中延迟初始化——先检查所有依赖的 Autoload（GSM、玩家系统、吸收系统、变身系统、波次系统）是否已注册。未注册的系统对应的 UI 元素使用默认值渲染（HP=100, meter=0, wave=1/5, form="—"）。当上游系统就绪并发出第一个信号时，UI 自动更新为正确值。避免空引用崩溃。

- **如果 hp_current 变为 0 但 GSM 尚未进入 DEATH 状态（同帧窗口）**：HP 条显示 0 宽度——这是预期行为。低 HP 警告（hp_ratio=0）触发最大 alpha 脉冲（0.3↔0.5）。下一帧 GSM 进入 DEATH → HP 条隐藏（DEATH 不在可见状态列表中）。不存在"显示死亡角色还有 HP"的窗口。

- **如果计量表 lerp 动画尚未到达目标值而目标值已变化**：UI 中断当前的 lerp 并启动新的 lerp——以最新目标值为准。不排队多个 lerp。这确保计量表在激烈战斗中始终响应最新数据，而非播放过时的动画。

- **如果玩家在同一帧内从 EXPLORATION 切换到 TRANSFORMATION 再切换到 BERSERK**：GSM 的状态转换优先级和同一帧单次转换规则（见 GSM GDD Edge Cases）保证这不会发生。但如果因某些原因发生了快速连续状态切换（如 UPGRADE → EXPLORATION → CHARGING 在同一帧），UI 使用最新状态决定可见性——中间状态不产生可察觉的闪烁（因为状态切换和信号处理在同一帧内完成，UI 只渲染最终状态）。

- **如果屏幕分辨率不是 1920×1080**：所有 UI 元素使用锚点（anchor）和容器（container）定位——HP 条使用"底部居中"锚点、波次进度使用"顶部居中"锚点。元素尺寸以设计分辨率（1920×1080）为基准，CanvasLayer 的 `follow_viewport_scale` 启用——UI 随窗口缩放。极端比例（如 21:9 超宽屏或 4:3）下 UI 元素位置保持锚点约束——HP 条仍然在底部居中，不会漂移到屏幕外。

- **如果 Boss HP 条的数据查询失败（Boss 系统尚未实现或数据缺失）**：Boss HP 条显示为灰色占位条（"???"文字），不崩溃。Boss 系统 GDD 设计完成后更新接口。此边缘情况仅在 MVP 阶段可能出现（Boss 系统为 Vertical Slice 优先级）。

- **如果 meter_current >= meter_max 但 GSM 状态不是 CHARGING（如玩家在 COOLDOWN 状态下因变异效果获得了点数）**：变身提示仅在 `GSM.current_state == CHARGING AND meter_current >= meter_max` 时显示。COOLDOWN 状态下即使计量表满也不显示变身提示——变身键本身在该状态下已被 GSM 过滤。UI 反映游戏的规则约束，不提供错误提示。

- **如果 FormConfig.duration 或 FormConfig.cooldown 为 0（配置错误）**：持续时间条/冷却条宽度为 0（不填充），倒计时数字显示 "0.0s"。不崩溃。控制台打印 warning 日志："[HUD] FormConfig [form_id] has duration=0 or cooldown=0 — check config"。

- **如果形态名称或 Boss 名称过长溢出 UI 空间**：UI 文本使用 `clip_content` + 省略号溢出模式。形态名称限制为最多 10 个字符（超出截断 + "..."）。Boss 名称限制为最多 20 个字符。

- **如果升级界面在显示时玩家死亡**：GSM 转换优先级 DEATH > UPGRADE——升级界面立即关闭（fade out 0.15s），死亡画面淡入。升级界面被放弃——玩家不保留选择。

- **如果玩家在变身提示显示时（计量表满）进入 UPGRADE 状态（波次清除）**：GSM 状态切换至 UPGRADE → 变身提示隐藏（CHARGING 不在 UPGRADE 的可见状态列表中）。升级界面显示——变身提示不干扰升级选择。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 游戏状态管理 | `GSM.current_state`（只读查询）— 驱动所有 UI 元素可见性；`GSM.state_changed` 信号（订阅）— 触发 UI 模式切换 |
| 玩家系统 | `player.hp_current`、`player.hp_max`（只读查询）— HP 条 + 低 HP 警告 |
| 吸收系统 | `absorption.meter_current`、`absorption.meter_max`（只读查询）— 形态计量表 |
| 变身系统 | `transformation.current_form_id`、`duration_remaining`、`cooldown_remaining`、`is_berserk`（只读查询）— 形态图标、倒计时、狂暴标识 |
| 波次系统 | `wave.current_wave`、`total_waves`、`enemies_remaining`（只读查询）— 波次进度 + 剩余敌人 |
| 输入系统 | `InputMap` 查询 `transform_activate` 动作的绑定按键名 — 变身提示中的动态按键名 |

### 软依赖（尚未设计，预留接口）

| 系统 | 依赖内容 | 回退方案 |
|------|---------|---------|
| Boss 系统 | Boss 当前 HP / 最大 HP — Boss HP 条 | 显示占位条 "???" |
| 变异系统 | 升级界面选项卡片数据（图标、名称、描述、稀有度） | 显示占位卡片以验证布局 |

### 下游依赖方

| 系统 | 依赖内容 |
|------|---------|
| 设置系统（Vertical Slice） | UI 缩放倍率、HUD 元素显隐开关 — 设置系统可调整 HUD 的显示参数 |
| 新手引导系统（Full Vision） | 引导箭头/高亮叠加在特定 UI 元素上 — 引导系统需要知道 UI 元素的位置和状态 |
| 对局总结系统（Full Vision） | 对局统计数据展示 — 与战斗 HUD 共享 CanvasLayer 和 UI 样式 |

### 接口契约

HUD/UI 系统是叶子消费者节点——在 MVP 阶段不向其他系统暴露主动接口。但它提供以下内部契约供未来系统引用：

1. **UI 元素位置查询**：`get_element_rect(element_id: String) -> Rect2` — 返回指定 UI 元素的屏幕空间矩形，供新手引导系统定位箭头/高亮
2. **HUD 显隐控制**：`set_hud_visible(visible: bool)` — 全局 HUD 开关，供设置系统使用
3. **升级界面选择回调**：`upgrade_selected(option_index: int)` 信号 — 玩家在升级界面确认选择时发出，变异系统订阅

## Tuning Knobs

| 参数 | 默认值 | 安全范围 | 玩法/视觉影响 |
|------|--------|---------|-------------|
| `hp_bar_width` | 120 px | 80–200 px | HP 条长度。太短→HP 变化不清晰；太长→占用屏幕空间 |
| `hp_bar_height` | 8 px | 4–16 px | HP 条粗细。太细→难以在余光中感知；太粗→视觉过重 |
| `hp_bar_offset_y` | -80 px | -120 – -40 px | HP 条相对于屏幕底部的垂直偏移 |
| `meter_bar_width` | 200 px | 120–300 px | 计量表长度。长度=填充视觉的"重量感"——越长越有成就感 |
| `meter_bar_height` | 12 px | 6–20 px | 计量表粗细。比 HP 条更粗——计量表是战斗 HUD 的核心焦点 |
| `meter_bar_offset_y` | -60 px | -100 – -30 px | 计量表相对于屏幕底部的垂直偏移 |
| `duration_bar_width` | 150 px | 100–250 px | 持续时间条长度。与计量表同一位置——切换时不突兀 |
| `duration_bar_height` | 6 px | 4–10 px | 持续时间条粗细。比计量表细——"子信息"层级 |
| `meter_lerp_speed` | 10 px/s | 5–30 px/s | 计量表填充动画速度。太慢→计量表"跟不上"实际值（信息延迟）；太快→硬跳感 |
| `fade_in_duration` | 0.15s | 0.05–0.3s | 元素淡入时间。太快→闪烁感；太慢→响应迟钝 |
| `fade_out_duration` | 0.2s | 0.1–0.4s | 元素淡出时间。略慢于淡入——消失比出现需要更多时间被注意到 |
| `low_hp_warning_threshold` | 0.3 | 0.15–0.5 | HP 低于此比例时触发屏幕红色警告。太高→警告频繁出现（狼来了）；太低→警告出现时已经太晚 |
| `low_hp_critical_threshold` | 0.15 | 0.05–0.25 | HP 低于此比例时警告升级为脉冲。应明显低于普通警告阈值 |
| `warning_pulse_period` | 0.5s | 0.3–1.0s | 低 HP 脉冲周期。太快→焦虑感过强；太慢→不够紧迫 |
| `transform_prompt_pulse_period` | 0.8s | 0.5–1.5s | 变身提示脉冲周期。应慢于低 HP 脉冲——提示是"邀请"而非"警告" |
| `wave_text_font_size` | 16 px | 12–24 px | 波次文字字号。太大→抢夺战斗焦点；太小→难以阅读 |
| `enemies_remaining_font_size` | 12 px | 10–18 px | 剩余敌人文字字号。比波次文字小——信息层级低于波次编号 |
| `boss_hp_bar_width` | 300 px | 200–500 px | Boss HP 条长度。比普通 HP 条更长——Boss 是特殊事件 |
| `boss_hp_bar_height` | 16 px | 12–24 px | Boss HP 条粗细。比普通 HP 条更粗——Boss 的重要性需要视觉重量 |
| `upgrade_card_width` | 200 px | 150–280 px | 升级卡片宽度。影响卡片内的文字换行和图标大小 |
| `upgrade_card_height` | 280 px | 200–350 px | 升级卡片高度 |
| `upgrade_overlay_alpha` | 0.6 | 0.4–0.8 | 升级界面背景暗化 alpha。太暗→看不到战场；太亮→看不清卡片 |
| `death_fade_in_duration` | 0.5s | 0.3–1.0s | 死亡画面淡入时间。较慢的淡入匹配死亡时刻的重量感 |

## Visual/Audio Requirements

HUD/UI 系统本身就是游戏的视觉输出层——它不"触发"其他系统产生视觉/音频，它**就是**视觉。但以下定义 HUD 的视觉设计约束：

| 需求 | 优先级 | 描述 |
|------|--------|------|
| 像素字体一致性 | MVP | 所有 UI 文字使用像素艺术风格字体（如 m3x6 或类似 8-16px 像素字体）。与游戏整体像素美学一致 |
| 颜色语义一致性 | MVP | HP = 绿色，伤害/危险 = 红色，形态主题色 = 橙红（Beast）/ 紫红（Dragon），冷却/不可用 = 灰色，奖励/升级 = 金色 |
| 动画节奏一致性 | MVP | 所有 UI 动画使用相同的缓动曲线（ease-in-out）。脉冲动画周期统一在 0.5-0.8s 范围内 |
| 透明度层次 | MVP | 主要信息（HP、计量表）= 100% 不透。次要信息（剩余敌人）= 80%。背景元素 = 50-60% |
| 形态计量表边框脉冲 | MVP | 计量表 >= 80% 时边框微弱发光（形态主题色 glow，alpha 0→0.3 呼吸）。不刺眼——余光可感知 |
| 计量表填充音同步 | MVP | 计量表视觉填充与音频系统的蓄能渐强音同步——两者由同一 GSM 信号驱动，不需直接耦合 |

## UI Requirements

此系统本身就是 UI。以下定义 UI 的自身设计方向（而非对其他系统的需求）：

| 方向 | 优先级 | 描述 |
|------|--------|------|
| 信息层级 | MVP | 三层信息结构：核心（HP + 计量表——始终可见、最大尺寸）、次要（波次 + 敌人——小尺寸、屏幕顶部）、事件（变身提示/Boss HP/升级——覆盖显示） |
| 战场哲学 | MVP | "信息在战场上"——核心信息紧贴玩家角色（屏幕底部居中），而非传统 HUD 的屏幕角落。玩家眼睛不需要离开战斗区域就能获取关键信息 |
| 最小干扰 | MVP | 仅在状态切换时显示相关信息——无效或不可用的信息不显示。不需要的 UI 元素透明度为 0（完全隐藏） |
| 按键可读性 | MVP | 所有按键提示使用动态绑定显示（从 InputMap 读取实际绑定），而非硬编码 "[Space]" |
| 可扩展性 | MVP | HUD 布局使用锚点和容器，预留新元素（新形态图标、新状态标识）的插入点。不硬编码元素位置 |

## Acceptance Criteria

- **AC1 — HP 条反映玩家 HP**：**GIVEN** 玩家 HP 为 100/100，**WHEN** 玩家受到 15 点伤害，**THEN** HP 条宽度从 120px 缩小至 102px（= 85/100 × 120），HP 数字显示 "85/100"。

- **AC2 — 形态计量表反映吸收点数**：**GIVEN** meter_current=0，**WHEN** 玩家收集点数使 meter_current 升至 60，**THEN** 计量表填充宽度从 0 平滑增长至 120px（= 60/100 × 200），动画使用 lerp(10 px/s)。

- **AC3 — 变身提示在计量表满时出现**：**GIVEN** GSM 状态 = CHARGING 且 meter_current 达到 100，**WHEN** 下一帧 UI 更新，**THEN** 变身提示文字"按 [Space] 变身"出现在计量表上方，脉冲动画（scale 1.0↔1.1，周期 0.8s）。

- **AC4 — 变身激活后 UI 模式切换**：**GIVEN** GSM 状态从 CHARGING 切换至 TRANSFORMATION，**WHEN** `state_changed` 信号触发，**THEN** 计量表渐隐（0.2s fade out），持续时间条渐显（0.15s fade in）在同一位置，倒计时数字开始从 Beast `duration=8.0s` 递减。

- **AC5 — 冷却条在 COOLDOWN 状态下显示**：**GIVEN** GSM 状态 = COOLDOWN 且 Beast `cooldown=15.0s`，**WHEN** UI 更新，**THEN** 冷却条显示在计量表位置，灰色填充从 0px 逐渐增长至 150px（冷却完成时），数字从 "15.0s" 递减至 "0.0s"。

- **AC6 — 波次进度正确显示**：**GIVEN** current_wave=3, total_waves=5，**WHEN** UI 更新波次显示，**THEN** 屏幕顶部显示 "波次 3/5"，字号 16px，白色。

- **AC7 — 低 HP 警告触发**：**GIVEN** 玩家 HP 降至 25/100（25%），**WHEN** hp_ratio=0.25 ≤ 0.3，**THEN** 屏幕四边出现红色渐变（alpha = (0.3-0.25)/0.15×0.3 ≈ 0.1），alpha 随 HP 降低线性增加。

- **AC8 — 低 HP 临界脉冲**：**GIVEN** 玩家 HP 降至 10/100（10%），**WHEN** hp_ratio=0.1 ≤ 0.15，**THEN** 屏幕红色警告进入脉冲模式——alpha 在 0.3 ↔ 0.5 之间呼吸，周期 0.5s。

- **AC9 — UPGRADE 状态下战斗 HUD 隐藏**：**GIVEN** GSM 状态从 CHARGING 切换至 UPGRADE，**WHEN** UI 更新，**THEN** HP 条、计量表、波次进度全部渐隐（0.2s），升级界面淡入（0.15s）。

- **AC10 — DEATH 状态下死亡画面显示**：**GIVEN** GSM 状态切换至 DEATH，**WHEN** UI 更新，**THEN** 所有战斗 HUD 隐藏，"你死了"文字（红色）和"按 Enter 重新开始"提示淡入（0.5s）。

- **AC11 — 变身提示动态按键名**：**GIVEN** 玩家将 `transform_activate` 按键绑定从 Space 改为 Q，**WHEN** 计量表满且 UI 渲染变身提示，**THEN** 提示文字显示 "按 Q 变身"（而非硬编码的 Space）。

- **AC12 — 形态图标随 current_form_id 切换**：**GIVEN** 玩家当前选择 Dragon 形态，**WHEN** UI 渲染计量表，**THEN** 计量表左侧显示 Dragon 图标（16×16 px），计量表填充色为紫红 `#C44B8B`。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | HP 条应浮动在玩家角色上方（世界空间）还是固定在屏幕底部（屏幕空间）？世界空间更直观——HP 条随角色移动，眼睛不需要离开角色。屏幕空间更整洁——位置固定可预测。 | 否——默认屏幕空间（底部居中） | 原型测试——若玩家反馈"看 HP 条需要离开战斗"，切换为世界空间 |
| 2 | 形态计量表是否需要分段（如每段 20% = 1 格）而非连续填充条？分段提供更清晰的"距满格还有几格"的感觉。连续填充条更平滑但"距满格"的感觉模糊。 | 否——连续填充条对 MVP 足够 | 原型测试比较两种方案 |
| 3 | 升级界面是否需要在 UPGRADE 状态**自动**弹出，还是允许玩家延迟选择（如先收集战场上残留的点数再开升级界面）？当前设计是自动弹出（UPGRADE 状态 time_scale=0），但可以考虑允许延迟——玩家先收集完点数再按交互键进入升级界面。 | 否——自动弹出对 MVP 足够 | 波次系统 GDD 已定义波间暂停 3.0s——在暂停内玩家可收集残留点数。升级界面的触发时机在变异系统 GDD 中最终决定 |
| 4 | 屏幕边缘 HP 警告是否应与 VFX 系统的受击白闪协调（alpha 叠加不应超过某个上限避免叠加视觉过曝）？ | 否——两个系统响应同一 GSM 信号，自然同步 | VFX 系统 GDD 设计时交叉确认 |
| 5 | MVP 是否需要暂停菜单（按 Esc 暂停 + 显示菜单）？暂停菜单不在系统索引的 21 个系统中——是否作为 HUD/UI 系统的一部分，还是另行定义？ | 否——MVP 阶段 Esc = 关闭游戏窗口或回到主菜单即可 | 对局管理系统 GDD（#17）设计时处理暂停逻辑 |
