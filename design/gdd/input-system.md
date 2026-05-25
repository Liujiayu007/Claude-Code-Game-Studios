# Input System — 输入系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 3 (Paced Mastery)

## Overview

输入系统（Input System）是 Shapeshift Survivor 的输入抽象层——它将 Godot 引擎的底层输入事件（键盘按键、鼠标、手柄）封装为项目级的输入动作（Input Actions），并提供状态感知的输入过滤。它是所有玩家控制系统（移动、变身触发、菜单导航）获取输入的唯一入口。

系统基于 Godot 内建的 `InputMap` 和 `Input` 单例构建。每个输入动作（`move_up`, `transform_activate`, `confirm` 等）定义在 Project Settings 的 Input Map 中，绑定到具体的物理按键。输入系统提供统一的查询接口——其他系统调用 `InputSystem.is_action("move_left")` 而非检查 `Input.is_key_pressed(KEY_A)`。这一层间接性使键位重绑定、手柄支持、以及状态感知的输入禁用成为可能。

**状态感知输入过滤**是本系统的核心增值：输入系统查询 GSM 的 `current_state`，在 `UPGRADE` 和 `DEATH` 状态下自动过滤移动和攻击输入（仅保留 UI 导航输入）。这使其他系统在其 `_process` 中可以无条件地检查输入动作，而不需要每个系统重复判断"现在能接收输入吗"。

**没有这个系统会失去什么**：输入处理分散在各系统中硬编码——玩家系统检查 `KEY_A`/`KEY_D` 移动，变身系统检查 `KEY_SPACE` 变身。这导致：(1) 无法支持手柄（没有统一的重映射层），(2) 键位重绑定需要修改分散在多处的代码，(3) 状态感知的输入禁用需要每个系统自行实现（容易遗漏——变身系统可能忘了在 DEATH 状态下禁用变身键），(4) 输入冲突（两个系统响应同一按键）无法在全局层面协调。

## Player Fantasy

输入系统本身不产生玩家幻想——它是一个静默的输入抽象层，玩家永远不会意识到它的存在。它的"幻想"体现在它的缺失中：

> **"所想即所动"** —— 玩家按下变身键，角色立即变身。玩家不思考"输入层是否响应"、"按键是否绑定正确"、"为什么这个状态下按键没反应"。他们只感受到控制是即时的、可靠的、没有意外。输入系统的理想状态是**完全透明**——当玩家意识不到输入系统存在时，它就是完美的。

**该系统间接支撑的游戏支柱：**

- **支柱 3（节奏掌控）**：输入系统通过状态感知的输入过滤，确保玩家在需要做出快速反应的时刻不会因输入无响应而受挫（如冷却状态下变身键无效——但这是玩家已知的规则，不是"按键坏了"）。在升级状态下仅保留 UI 导航输入——自动过滤移动和攻击——防止玩家在变异选择界面中因误触而关闭菜单。

**"出问题时玩家会感受到什么"（基础设施的幻想测试）：**
- 当输入系统**正确**时，玩家什么都不会注意到——按键响应即时、手柄和键盘切换无延迟、在任何状态下按键的行为都是可预测的
- 当输入系统**错误**时——按变身键没反应（但没被告知"冷却中"）、手柄摇杆漂移但无死区修正、两个系统对同一按键产生冲突行为——玩家的挫败感直接且立即。"操作不跟手"是最快让玩家流失的原因之一。

## Detailed Design

### Core Rules

**Rule 1: InputMap 定义所有输入动作**

所有输入动作定义在 Godot Project Settings → Input Map 中，不在代码中硬编码按键。每个动作至少绑定键盘和手柄两组按键。输入系统通过 `Input.is_action_pressed("action_name")` 和 `Input.is_action_just_pressed("action_name")` 查询——永远不直接访问 `Input.is_key_pressed()` 或 `InputEvent`。

**Rule 2: InputSystem Autoload 统一入口**

提供 `InputSystem` Autoload，在 GSM 之后、其他所有系统之前初始化。提供以下查询接口：

```gdscript
# 持续输入——检查当前帧是否按下（用于移动等持续性动作）
InputSystem.is_action(action: String) -> bool

# 单次输入——检查是否在本帧刚按下（用于变身激活、确认、取消等一次性动作）
InputSystem.is_action_just(action: String) -> bool

# 获取移动向量——返回归一化后的 Vector2（组合上下左右四个动作）
InputSystem.get_move_vector() -> Vector2
```

`InputSystem` 内部委托给 `Input.is_action_pressed()` 和 `Input.is_action_just_pressed()`，但在此之前先进行状态过滤。

**Rule 3: 状态感知输入过滤**

InputSystem 在每次查询时检查 `GSM.current_state`，根据当前状态决定哪些动作类别可用：

| 动作类别 | EXPLORATION | CHARGING | TRANSFORMATION | BERSERK | COOLDOWN | UPGRADE | BOSS | DEATH |
|---------|-------------|----------|----------------|---------|----------|---------|------|-------|
| 移动 (`move_*`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ |
| 变身激活 (`transform_activate`) | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✓(*) | ✗ |
| UI 导航 (`ui_*`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| 暂停 (`pause`) | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✓ | ✗ |

> (*) 在 BOSS 状态下，如果形态计量表已满（CHARGING 子状态），变身激活可用。InputSystem 需查询吸收系统的计量表状态。

被过滤的动作静默返回 `false`——不打印日志、不发出信号。这是预期行为，不是错误。

**Rule 4: 移动向量归一化**

`get_move_vector()` 组合 `move_up`/`move_down`/`move_left`/`move_right` 四个动作，返回归一化的 Vector2。斜向移动（同时按上和右）长度不超过 1.0（防止斜向移动比正交移动快 √2 倍）。若四个方向均未按下，返回 `Vector2.ZERO`。

**Rule 5: 手柄死区**

手柄模拟摇杆的输入动作在 Input Map 中设置死区（deadzone）为 0.2（Godot 默认为 0.5，对快节奏游戏过于迟钝）。键盘按键不需要死区。

**Rule 6: 输入动作仅由 InputSystem 消费**

其他系统不直接访问 Godot 的 `Input` 单例。这确保：
- 状态过滤在全局层面一致生效
- 键位重绑定只需在 Input Map 中修改，无需触及其他代码
- 输入模拟（调试/自动化测试）只需修改 InputSystem 一层

**Rule 7: 自动检测当前输入设备**

InputSystem 追踪最近使用的输入设备类型（键盘/手柄），通过 `last_input_device` 属性暴露。当检测到手柄输入时，UI 提示文本切换为手柄按钮图标（如"按 A 确认"而非"按 Enter 确认"）。检测逻辑：在 `_input(event)` 中，如果 event 是 `InputEventJoypadButton` 或 `InputEventJoypadMotion`，设置 `last_input_device = DEVICE_GAMEPAD`。

### Input Actions

#### Gameplay Actions

| 动作名 | 类型 | 默认键盘绑定 | 默认手柄绑定 | 用法 |
|--------|------|------------|------------|------|
| `move_up` | 持续 | W / ↑ | Left Stick Up / D-Pad Up | 玩家向上移动 |
| `move_down` | 持续 | S / ↓ | Left Stick Down / D-Pad Down | 玩家向下移动 |
| `move_left` | 持续 | A / ← | Left Stick Left / D-Pad Left | 玩家向左移动 |
| `move_right` | 持续 | D / → | Left Stick Right / D-Pad Right | 玩家向右移动 |
| `transform_activate` | 单次 | Space | Gamepad A (South Button) | 激活变身（计量表满时） |

#### UI Actions

| 动作名 | 类型 | 默认键盘绑定 | 默认手柄绑定 | 用法 |
|--------|------|------------|------------|------|
| `ui_up` | 单次 | ↑ / W | D-Pad Up / Left Stick Up | UI 选项上移 |
| `ui_down` | 单次 | ↓ / S | D-Pad Down / Left Stick Down | UI 选项下移 |
| `ui_left` | 单次 | ← / A | D-Pad Left / Left Stick Left | UI 选项左移 |
| `ui_right` | 单次 | → / D | D-Pad Right / Left Stick Right | UI 选项右移 |
| `ui_confirm` | 单次 | Enter / Space | Gamepad A (South Button) | 确认选择 |
| `ui_cancel` | 单次 | Escape / Backspace | Gamepad B (East Button) | 取消/返回 |

#### System Actions

| 动作名 | 类型 | 默认键盘绑定 | 默认手柄绑定 | 用法 |
|--------|------|------------|------------|------|
| `pause` | 单次 | Escape | Start Button | 暂停/继续游戏 |

> **注意**：`transform_activate` 和 `ui_confirm` 都绑定了 Space 和 Gamepad A。这是有意的——变身激活仅在游戏状态为 CHARGING 且计量表满时生效；UI 确认仅在菜单/升级界面中生效。两者互斥（状态过滤确保同一时刻只有一个可用）。`pause` 和 `ui_cancel` 都绑定了 Escape——同样是上下文分离的。

### Interactions with Other Systems

| 消费方系统 | 查询方法 | 用途 |
|-----------|---------|------|
| 玩家系统 | `InputSystem.get_move_vector()` (每帧) | 驱动玩家移动方向 |
| 玩家系统 | `InputSystem.is_action("transform_activate")` | 触发变身（仅 CHARGING 状态下可用） |
| 变身系统 | `InputSystem.is_action_just("transform_activate")` | 检测变身激活按键（单次按下） |
| HUD/UI 系统 | `InputSystem.is_action_just("ui_confirm")`, `ui_cancel`, `ui_up/down/left/right` | 驱动菜单导航和选择 |
| 变异系统 | `InputSystem.is_action_just("ui_*")` | 升级界面中的变异选择 |
| 对局管理系统 | `InputSystem.is_action_just("pause")` | 暂停/恢复游戏 |
| 设置系统 | `InputSystem.last_input_device` | 显示正确的按键提示（键盘 vs 手柄） |

**接口契约**：InputSystem 提供上述查询方法——纯数据读取，不执行游戏逻辑。消费方负责"知道输入后做什么"。InputSystem 仅依赖 GSM（查询状态）和 Godot Input 单例——不依赖其他游戏系统。

## Formulas

### D.1 Move Vector Normalization

```
raw = Vector2(
    is_action("move_right") - is_action("move_left"),   # x: +1, 0, or -1
    is_action("move_down") - is_action("move_up")        # y: +1, 0, or -1
)
move_vector = normalize(raw)   if raw.length() > 0
              Vector2.ZERO     otherwise
```

**Variables:**

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| raw | Vector2 | x ∈ {-1, 0, 1}, y ∈ {-1, 0, 1} | Raw input combination (8-directional) |
| move_vector | Vector2 | length ∈ {0, 1} | Normalized output |

**Example:**
```
Input: move_right = true, move_up = true → raw = (1, -1)
raw.length() = √2 ≈ 1.414 > 0 → normalize → (0.707, -0.707)
Output: Diagonal movement at same speed as orthogonal
```

### D.2 State-Based Input Filtering

```
is_action_available(action, state) =
    action ∈ GAMEPLAY_ACTIONS  →  state ∈ {EXPLORATION, CHARGING, TRANSFORMATION, BERSERK, COOLDOWN, BOSS}
    action = "transform_activate"  →  state ∈ {CHARGING} OR (state = BOSS AND meter = 100%)
    action ∈ UI_ACTIONS  →  state ≠ DEATH
    action = "pause"  →  state ≠ UPGRADE AND state ≠ DEATH
```

**Output:** boolean — `true` if the action is available in the current state.

### D.3 Dead Zone Application

```
effective_value = |raw_value| > DEADZONE  →  raw_value
                  otherwise               →  0.0
```

Handled by Godot's InputMap deadzone setting per action. DEADZONE = 0.2 for analog stick actions.

## Edge Cases

- **如果其他系统绕过 InputSystem 直接访问 Godot `Input` 单例**：InputSystem 无法检测或阻止——Godot 的 `Input` 是全局可访问的。通过 Code Review 和 lint 规则（禁止直接使用 `Input.is_key_pressed`）强制执行。在实现阶段，创建一个 lint 检查：任何对 `Input.is_` 的调用（`InputSystem.gd` 自身除外）触发 CI 警告。

- **如果查询的输入动作名在 InputMap 中不存在**：Godot 的 `Input.is_action_pressed("nonexistent")` 返回 `false` 并打印 error 日志。InputSystem 不额外处理——将错误直接暴露给开发者（错误动作名应立即修复，不应静默吞掉）。

- **如果键盘和手柄同时输入**：两个输入源都可以触发动作（Godot 默认行为——多个物理按键可绑定到同一动作）。这是预期行为——玩家在键盘和手柄间切换时不应有延迟。`last_input_device` 追踪最近使用的设备，UI 提示据此切换。

- **如果手柄在游戏进行中断开连接**：Godot 默认不停止游戏。InputSystem 检测到此情况（连续 N 帧无手柄输入 + `last_input_device == DEVICE_GAMEPAD`），自动回退至键盘输入，且发出 `device_changed(DEVICE_KEYBOARD)` 信号通知 HUD 系统切换提示图标。

- **如果玩家在状态转换的同一帧内按下按键**：InputSystem 在查询时读取 `GSM.current_state`。GSM 的 Autoload 优先级高于 InputSystem（GSM 第 2，InputSystem 第 3），因此 InputSystem 查询时读取的是 GSM 本帧已更新后的状态。行为正确：如果 GSM 刚转换到 COOLDOWN，transform_activate 在该帧已不可用。

- **如果玩家快速连按 `transform_activate`**：`is_action_just("transform_activate")` 在状态过滤生效前仅在按下首帧返回 `true`——连按不产生额外效果。变身系统在收到第一次激活后进入 TRANSFORMATION 状态，`transform_activate` 在 TRANSFORMATION 状态下被过滤（不可用），因此后续连按被静默忽略。

- **如果 InputSystem 在 GSM 初始化前被查询**：InputSystem 的 `_ready()` 在 GSM 之后执行。若 GSM 不可用（尚未初始化的边缘情况），InputSystem 默认所有动作可用（保守策略——允许所有输入，不阻塞）。打印一次性 warning："GSM not available — input filtering disabled until GSM ready."

- **如果玩家在 UI 导航时同时按下移动键**：`ui_up` 和 `move_up` 都绑定到 W/↑。在 UPGRADE 状态下，移动动作被过滤但 UI 动作可用——因此 W/↑ 作为 UI 上移正常工作。在游戏状态下，UI 动作不可用但移动动作可用——因此 W/↑ 作为移动正常工作。同一按键在不同状态下的不同行为由状态过滤自然处理。

## Dependencies

### 上游依赖

| 系统 | 依赖性质 | 依赖内容 |
|------|---------|---------|
| 游戏状态管理 | **硬依赖** | 查询 `GSM.current_state` 进行状态感知输入过滤。无 GSM → 输入过滤功能丧失（可回退为所有输入始终可用） |
| 数据配置系统 | 软依赖 | 读取手柄死区值、输入设备切换超时等可调参数。不可用时使用硬编码默认值 |

### 下游依赖方

| 系统 | 依赖性质 | 依赖内容 |
|------|---------|---------|
| 玩家系统 | **硬依赖** | `get_move_vector()` — 移动输入；`is_action("transform_activate")` — 变身触发 |
| HUD/UI 系统 | **硬依赖** | `is_action_just("ui_*")` — 菜单导航和确认/取消 |
| 变身系统 | **硬依赖** | `is_action_just("transform_activate")` — 检测变身激活按键 |
| 变异系统 | **硬依赖** | `is_action_just("ui_*")` — 升级界面中的选项选择 |
| 对局管理系统 | **硬依赖** | `is_action_just("pause")` — 暂停/恢复 |
| 设置系统 | 软依赖 | `last_input_device` — 显示正确的按键提示图标 |

### 接口契约

InputSystem 向消费方提供：
1. 所有输入查询方法返回 bool / Vector2 — 无异常、无 null
2. 状态过滤对所有调用方一致生效 — 同一帧内同一动作的查询结果一致
3. `last_input_device` 在设备切换的同一帧更新

消费方应：
1. 不直接访问 Godot `Input` 单例
2. 仅在 `_process` 或 `_input` 中查询 — 不在 `_init` 中查询（GSM 可能未就绪）

## Tuning Knobs

| 参数 | 类型 | 默认值 | 安全范围 | 玩法影响 |
|------|------|--------|---------|---------|
| `gamepad_deadzone` | float | 0.2 | 0.1–0.5 | 手柄摇杆死区。太低→漂移敏感的摇杆导致意外移动；太高→摇杆推动一段距离后才响应，手感迟钝 |
| `device_switch_timeout` | float | 0.5s | 0.1–2.0s | 最后手柄输入后等待多久切换设备提示。太短→键盘和手柄交替使用时提示图标抖动；太长→手柄断开后提示延迟更新 |
| `idle_timeout` | float | 0.0 | 0–300s | 无输入多少秒后触发暂停（0=禁用）。非零→挂机保护；太长→无实际作用 |

## Visual/Audio Requirements

不适用。输入系统不产生视觉或音频输出。设备切换时（键盘↔手柄）HUD 系统订阅 `device_changed` 信号更新 UI 提示图标——但图标的视觉设计由 HUD/UI 系统的 GDD 定义。

## UI Requirements

不适用。输入系统没有玩家可见的 UI。键位提示（如"按 Space 变身"）由 HUD/UI 系统根据 `InputSystem.last_input_device` 和当前状态动态显示——但 UI 元素的布局、样式、动画由 HUD/UI 系统的 GDD 定义。

## Acceptance Criteria

- **GIVEN** 游戏运行且当前状态为 `EXPLORATION`，**WHEN** 玩家按下 W 键，**THEN** `InputSystem.is_action("move_up")` 返回 `true`，`InputSystem.get_move_vector()` 返回 `Vector2(0, -1)`。

- **GIVEN** 游戏运行且当前状态为 `CHARGING` 且形态计量表为 100%，**WHEN** 玩家按下 Space 键，**THEN** `InputSystem.is_action_just("transform_activate")` 返回 `true`。

- **GIVEN** 游戏运行且当前状态为 `EXPLORATION` 且形态计量表为 0%，**WHEN** 玩家按下 Space 键，**THEN** `InputSystem.is_action("transform_activate")` 返回 `false`（计量表未满，变身不可用）。

- **GIVEN** 当前状态为 `UPGRADE`，**WHEN** 玩家按下 W/↑ 键，**THEN** `InputSystem.is_action_just("ui_up")` 返回 `true`，但 `InputSystem.is_action("move_up")` 返回 `false`（移动在 UPGRADE 状态下被过滤）。

- **GIVEN** 当前状态为 `DEATH`，**WHEN** 玩家按下任意游戏按键，**THEN** 所有 gameplay actions 和 UI actions 返回 `false`（死亡状态下无输入可用）。

- **GIVEN** 玩家同时按下 W 和 D 键，**WHEN** 调用 `InputSystem.get_move_vector()`，**THEN** 返回 `Vector2(0.707, -0.707)`（归一化斜向移动）。

- **GIVEN** 玩家使用键盘输入中，**WHEN** 玩家按下手柄 A 键，**THEN** `InputSystem.last_input_device` 变为 `DEVICE_GAMEPAD`，且 `device_changed(DEVICE_GAMEPAD)` 信号被发出。

- **GIVEN** 游戏运行中且手柄被断开，**WHEN** 经过 `device_switch_timeout`（默认 0.5s）无手柄输入，**THEN** `InputSystem.last_input_device` 变为 `DEVICE_KEYBOARD`。

- **GIVEN** 游戏运行中，**WHEN** 查询一个不存在于 InputMap 中的动作名（如 `"nonexistent_action"`），**THEN** 返回 `false` + Godot 控制台自动打印 error（InputSystem 不额外处理）。

- **GIVEN** 当前状态为 `UPGRADE`，**WHEN** 玩家按下 Escape 键，**THEN** `InputSystem.is_action_just("pause")` 返回 `false`（暂停在升级状态下被过滤），但 `InputSystem.is_action_just("ui_cancel")` 返回 `true`（取消在升级状态下可用）。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 是否需要输入缓冲（Input Buffering）？例如，玩家在冷却期间按下变身键，是否应在冷却结束时自动激活变身？输入缓冲提升手感但需要额外的缓冲队列管理。 | 否——MVP 不需要输入缓冲 | 原型测试时评估玩家反馈——如果大量玩家反映"变身键没反应"，则添加 |
| 2 | 是否需要支持键位重绑定 UI？Godot 4.6 InputMap 在编辑器内可配置，但导出构建中需要额外代码实现运行时重绑定。MVP 是否需要重绑定界面？ | 否——MVP 使用默认键位即可 | 设置系统 GDD 设计时决定 |
| 3 | 挂机检测——玩家长时间无输入时应暂停游戏（如去接电话）？还是保持运行自然死亡？ | 否——对 MVP 体验影响小 | UI/UX 抛光阶段决定 |
| 4 | 移动输入是否应支持仅键盘 8 方向（当前设计）还是模拟摇杆的 360° 全向移动？全向移动在手感上更流畅但增加了移动系统的复杂度——玩家速度需分解为 Vector2 而非四方向离散值。 | 是——影响玩家系统 GDD 中的移动实现 | **玩家系统 GDD 设计前必须决定**。建议：MVP 使用 8 方向（与 Vampire Survivors 一致），360° 全向作为后续迭代 |
