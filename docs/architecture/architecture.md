# Architecture: Shapeshift Survivor

> **Status**: Accepted
> **Engine**: Godot 4.6
> **Language**: GDScript
> **Last Updated**: 2026-05-25
> **ADRs**: 16 (all Accepted)

---

## Architecture Overview

Shapeshift Survivor 的架构服务于一个核心的"蓄能 -> 爆发"循环：玩家在开放竞技场中移动和自动攻击敌人，击杀敌人收集能量填充计量表，满表后变身为怪物形态碾压敌人，形态过期后进入冷却，然后重新蓄能。整个架构围绕 **12 个 Autoload 单例系统** 构建，按依赖深度分为 Foundation（基础） -> Core（核心） -> Presentation（表现）三层，另外还有两个跨层级的基础模式 ADR（CanvasLayer 渲染层级和对象池机制）。

架构的核心理念是 **信号驱动的松耦合通信**：系统之间通过直接信号连接（`Emitter.signal.connect(_handler)`）进行事件通知，通过只读属性进行数据查询。不存在一个中央 EventBus Autoload — MVP 阶段的 12 个系统规模下，直接连接图完全可审计。

所有游戏行为由 **GSM 状态机** 统一驱动。8 个游戏状态（EXPLORATION / CHARGING / TRANSFORMATION / BERSERK / COOLDOWN / UPGRADE / BOSS / DEATH）定义了每个系统在不同阶段的行为边界。`state_changed` 信号是代码库中连接最广的信号 — 11 个系统订阅它来切换自己的行为模式。

渲染通过 **6 层 CanvasLayer 堆栈** 实现：Game World (层 0) -> VFX_World (层 1) -> VFX_Screen (层 2) -> HUD_Core (层 3) -> HUD_Overlay (层 4) -> VFX_Overlay (层 5)。每层由唯一的系统拥有，Z 序无歧义。

所有可调数值集中于 **DataConfig** Autoload（Autoload #1），是唯一的配置真相源。简单标量使用 `@export var`，结构化数据（形态定义、波次表、敌人类型、区域参数）使用 Godot Custom Resource 类。任何系统不得硬编码可调数值。

性能敏感的资源（粒子、音效、敌人）全部使用 **对象池** 预分配，`_ready()` 中创建，游戏过程中零运行时分配。VFX 有 6 个粒子池共 270 个 `CpuParticles2D`，Audio 有 2 个音效池共 12 个 `AudioStreamPlayer`，Enemy 有 4 个敌人池共 50 个 `CharacterBody2D`。

---

## Layer Architecture

### Foundation Layer

所有系统的基石 — 零游戏逻辑依赖，必须在所有其他系统之前稳定。

| ADR | System | Key Decision |
|-----|--------|-------------|
| ADR-0001 | Autoload Architecture | 12 个 MVP 系统全部注册为 Godot Autoload 单例，按依赖深度排序加载，系统间通过直接信号连接通信 |
| ADR-0004 | Signal Bus Pattern | 直接 Autoload-to-Autoload 信号连接，snake_case 过去时命名，仅在 `_ready()` 中 connect，MVP 不引入 EventBus |
| ADR-0005 | Data Configuration | DataConfig Autoload #1：标量用 `@export var`，结构化数据用 Custom Resource（FormConfig / WaveTable / EnemyConfig / AreaConfig） |
| ADR-0006 | Input System | 薄抽象层：移动用 `Input.get_vector()` 直连，离散动作通过 `InputSystem.is_action_buffered()` 获得 150ms 缓冲窗口，GSM 驱动输入屏蔽 |
| ADR-0007 | GSM State Machine | 8 状态 enum 状态机配 8x8 显式转换矩阵，优先级系统解决同帧多请求冲突（DEATH > BOSS > UPGRADE > ... > EXPLORATION） |

### Core Layer

驱动 30 秒核心玩法循环。全部依赖 Foundation 层。

| ADR | System | Key Decision |
|-----|--------|-------------|
| ADR-0012 | Player System | PlayerSystem Autoload 拥有 Player `CharacterBody2D` 场景实例，8 方向移动 + 自动瞄准攻击 + iframe 无敌帧 + 统计倍率模式 |
| ADR-0010 | Enemy System | 场景化敌人配对象池，4 种敌人类型共 50 个预分配实例，简单方向向量追踪 AI，死亡掉落 EnergyDrop |
| ADR-0008 | Absorption System | 单一归一化 0.0-1.0 浮点计量表，`add_energy()` 填充 / `consume_all()` 消耗，在 0.25/0.5/0.75 阈值发射 BGM 层级切换信号 |
| ADR-0009 | Transformation System | 5 道门控激活检查，`_process(delta)` 计时器管理持续/冷却，狂暴模式（满表激活 = 强化属性 + 特殊 VFX/Audio），形态配置来自 FormConfig |
| ADR-0013 | Area System | 纯数据提供者 — AreaConfig Custom Resource 定义区域的所有参数（敌人池、Boss、背景、BGM），零 `_process()` 成本 |
| ADR-0011 | Wave System | 计时器驱动的波次序列器，WaveTable 定义每波敌人组和生成间隔，通过 `EnemySystem.get_active_count()` 轮询检测波次清空 |

### Presentation Layer

视觉和听觉反馈。依赖 Core 系统的信号和属性。

| ADR | System | Key Decision |
|-----|--------|-------------|
| ADR-0002 | CanvasLayer Architecture | 6 层 CanvasLayer 堆栈（层 0-5），每层由唯一系统拥有，VFX 拥有层 1/2/5，HUD 拥有层 3/4 |
| ADR-0003 | Object Pooling | VFX ParticlePoolManager（6 池 270 CpuParticles2D）和 Audio AudioPoolManager（2 池 12 AudioStreamPlayer），预分配 + acquire/release 接口 |
| ADR-0014 | HUD/UI System | 双 CanvasLayer（3=HUD_Core, 4=HUD_Overlay），dirty-flag 仅在有数据变化时渲染，visibility table 按 GSM 状态控制元素显隐 |
| ADR-0015 | VFX System | 信号驱动的 VFXCatalog（22 个条目），5 级优先级系统，CanvasLayer.modulate 实现屏幕闪光（零节点分配），持久化 CpuParticles2D 做形态光环 |
| ADR-0016 | Audio System | 4 总线架构（Music/SFX/UI/Voice），BGM 4 层动态音乐（Ambient/Bassline/Percussion/Lead）通过 AudioServer 总线音量渐变，5 级优先级抢占 |

---

## Key Architectural Decisions

### 1. Autoload Singleton Pattern (ADR-0001)

所有 12 个 MVP 系统作为 Godot Autoload 注册在 `project.godot` 的 `[autoload]` 段中，按依赖深度排序加载。Foundation 层系统先 `_ready()`，然后 Core 层，最后 Presentation 层。Presentation 层系统可以安全地假设所有 Foundation 和 Core 系统在其 `_ready()` 运行时已就绪。

每个 Autoload 暴露三类公共成员：(1) **Signals** — 其他系统连接的输出事件；(2) **Read-only properties** — 其他系统查询的输入数据；(3) **Request methods** — 有限的请求方法，仅在需要其他系统执行操作时使用（如 `GSM.request_transition()`）。系统间通信规则：只允许通过 `connect()` 订阅信号和通过属性读取数据，**严禁** 直接修改其他系统的内部状态。

12 个 Autoload 的加载顺序：`DataConfig` (#1) -> `GSM` (#2) -> `InputSystem` (#3) -> `PlayerSystem` (#4) -> `EnemySystem` (#5) -> `AbsorptionSystem` (#6) -> `TransformationSystem` (#7) -> `AreaSystem` (#8) -> `WaveSystem` (#9) -> `HUD` (#10) -> `VFX` (#11) -> `Audio` (#12)。

备选方案 SystemManager 模式（单一 Autoload 持有所有系统引用）被拒绝，因为它在 solo 项目中增加了不必要的间接层，且不如直接 Autoload 符合 Godot 习惯。

### 2. Signal Bus Communication (ADR-0004)

所有跨系统事件通知使用 GDScript 原生 `signal` 机制。信号命名遵循 **snake_case 过去时** 或 **现在状态** 形式：状态转换用 `state_changed`、`player_died`，已完成的动作用 `damage_dealt`、`transformation_started`，阈值跨越用 `meter_full`、`hp_critical`。

信号载荷规则：0-3 个参数使用位置参数加类型标注（`signal damage_dealt(target: Node2D, amount: float)`），4+ 个参数使用带文档注释的 typed Dictionary。

所有 `connect()` 调用发生在 `_ready()` 中，运行时绝不 connect/disconnect。对象池中的节点使用 boolean guard 而非动态连接/断开。每个系统的 `_ready()` 以注释块开头，列出其所有信号订阅。

MVP **不引入 EventBus Autoload**。直接连接模式在 12 个系统的规模下完全可审计。当出现 5+ 个无关系统需要监听同一事件、或引入动态系统加载时，重新评估 EventBus。

关键信号流向：GSM.state_changed（11 个系统订阅）、PlayerSystem.player_hit / damage_dealt / player_died（VFX + Audio + HUD）、AbsorptionSystem.meter_changed / meter_full / meter_threshold_crossed（Audio + HUD + TransformationSystem）、TransformationSystem.transformation_started / expired / berserk_activated（VFX + Audio + HUD + PlayerSystem）、WaveSystem.wave_started / wave_cleared / boss_wave_started（VFX + Audio + HUD）。

### 3. CanvasLayer Rendering (ADR-0002)

6 层 CanvasLayer 堆栈按 Godot `CanvasLayer.layer` 属性（整型 Z-index）排序：

| Layer Z | Name | Owner | Content |
|---------|------|-------|---------|
| 0 | Game World | Scene Root | TileMap, characters, enemies |
| 1 | VFX_World | VFX | Attack particles, death particles, dust |
| 2 | VFX_Screen | VFX | Screen flash, HP warning, wave prompts |
| 3 | HUD_Core | HUD | HP bar, form meter, duration/cooldown bar |
| 4 | HUD_Overlay | HUD | Wave progress, Boss HP, death screen |
| 5 | VFX_Overlay | VFX | Transform tear, death dissolve, berserk overlay |

VFX_World（层 1）在世界空间中渲染粒子，位于角色下方。VFX_Screen（层 2）在屏幕空间中渲染闪光和警告，位于 HUD 下方以确保 HUD 可读性。VFX_Overlay（层 5）是最高层，有意覆盖包括 HUD 在内的所有内容，仅在短暂的状态转换期间使用（< 2s）。

每个 CanvasLayer 由拥有系统在其 `_ready()` 中创建。VFX 创建并拥有层 1、2、5，HUD 创建并拥有层 3、4。任何系统不得向其他系统的 CanvasLayer 添加子节点。

### 4. Data-Driven Configuration (ADR-0005)

DataConfig 是 Autoload #1 — 所有系统加载前就绪，是所有可调数值的单一真相源。

两层架构：
- **Tier 1（80% 的配置）**：`@export var` 标量属性直接在 `DataConfig.gd` 上。按系统分组，带注释块映射回 GDD 的 Tuning Knobs 章节。在 Godot Inspector 中编辑，按 F5 即时生效。
- **Tier 2（20% 的配置）**：Custom Resource 类用于结构化多字段数据。`FormConfig`（形态属性、持续/冷却、颜色、音频）、`WaveTable`（每波敌人组和生成时序）、`EnemyConfig`（敌人类型属性）、`AreaConfig`（区域环境参数、敌人池、BGM）。

系统通过 `DataConfig.vfx_pool_attack` 读取标量，通过 `DataConfig.get_form_config("beast")` 查询结构化数据。任何系统不得硬编码 GDD 中定义的可调数值。

### 5. GSM State Machine (ADR-0007)

GSM 是 Autoload #2 — 游戏流程的中央编排点。8 个 enum 状态覆盖完整的 "蓄能 -> 爆发" 循环：

- **EXPLORATION**：无计量表，敌人刷新，玩家收集初始击杀
- **CHARGING**：计量表填充中（meter > 0），BGM 层级递增
- **TRANSFORMATION**：玩家变身（Beast/Dragon），形态能力激活，持续计时器运行
- **BERSERK**：强化变身 — 在 TRANSFORMATION 期间满表触发，属性提升
- **COOLDOWN**：变身后恢复期 — 人形态，计量表填充降为 0.1x
- **UPGRADE**：升级/变异选择界面 — `Engine.time_scale = 0`
- **BOSS**：Boss 敌人激活 — 特殊生成，专属 BGM
- **DEATH**：玩家 HP=0 — 死亡画面，敌人冻结

转换矩阵是显式的 8x8 `match` 语句，仅允许预定义的有效转换。`request_transition()` 在一次调用中完成退出旧状态 -> 进入新状态 -> 发射 `state_changed` -> 配置 InputSystem 屏蔽的全过程。同帧多请求通过优先级系统解决：DEATH(8) > BOSS(7) > UPGRADE(6) > TRANSFORMATION(5) > BERSERK(4) > COOLDOWN(3) > CHARGING(2) > EXPLORATION(1)。

每个系统的按状态行为由各系统自身拥有，不由 GSM 集中管理。GSM 拥有状态定义和转换规则；每个系统通过订阅 `state_changed` 信号或读取 `GSM.current_state` 来决定自己的行为。

### 6. Object Pooling (ADR-0003)

三个系统使用对象池，全部在 `_ready()` 中预分配，游戏过程中零运行时 `new()` 或 `queue_free()`：

- **VFX ParticlePoolManager**：6 个粒子池 — attack(50) + burst(80) + aura(30) + dust(10) + death(60) + cooldown(40) = 270 个 `CpuParticles2D`。池耗尽策略：回收最旧的非 HIGH 优先级粒子；如果全部为 HIGH 优先级则丢弃请求。
- **Audio AudioPoolManager**：2 个音效池 — sfx(8) + ui(4) = 12 个 `AudioStreamPlayer`。池耗尽策略：5 级优先级抢占 — 停止最低优先级的活跃音效，重新分配给更高优先级的请求；如果新请求优先级低于所有活跃音效则静默丢弃。
- **EnemySystem**（ADR-0010）使用相同的池模式管理 4 种敌人类型的 50 个预分配 `CharacterBody2D` 实例。

VFX 和 Audio 各自拥有独立的池管理器 — 不共享基类。GDScript 不支持泛型，且两种节点类型和耗尽策略差异足够大，统一抽象不划算。

---

## System Dependency Graph

```
                    ┌─────────────────────────────────┐
                    │        FOUNDATION LAYER          │
                    │                                 │
                    │  DataConfig (#1) ── 所有配置源   │
                    │  GSM (#2) ── 中央状态机          │
                    │  InputSystem (#3) ── 输入+缓冲   │
                    └──────────┬──────────────────────┘
                               │
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                  ▼
    ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
    │  CORE LAYER   │  │  CORE LAYER   │  │  CORE LAYER   │
    │               │  │               │  │               │
    │ PlayerSystem  │  │ EnemySystem   │  │ AreaSystem    │
    │ (#4)          │  │ (#5)          │  │ (#8)          │
    │ 移动+战斗+HP  │  │ AI+掉落+池    │  │ 区域参数+过渡 │
    └───┬───┬───────┘  └───┬───┬───────┘  └───┬───────────┘
        │   │              │   │              │
        │   │    ┌─────────┘   │              │
        │   ▼    ▼             ▼              │
        │  ┌───────────────┐   │              │
        │  │AbsorptionSystem│  │              │
        │  │(#6) 计量表    │   │              │
        │  └───────┬───────┘   │              │
        │          │           │              │
        ▼          ▼           │              │
    ┌───────────────────┐      │              │
    │TransformationSystem│     │              │
    │(#7) 变身+冷却     │      │              │
    └───────────────────┘      │              │
                               ▼              ▼
                        ┌───────────────┐  ┌───────────────┐
                        │ WaveSystem    │  │ (AreaSystem   │
                        │ (#9) 波次序列 │  │  已在左上)    │
                        └───────────────┘  └───────────────┘
                               │
            ┌──────────────────┼──────────────────┐
            ▼                  ▼                  ▼
    ┌──────────────────────────────────────────────────┐
    │              PRESENTATION LAYER                   │
    │                                                  │
    │  HUD (#10) ── HP条+计量表+波次+升级界面          │
    │  VFX (#11) ── 粒子+闪光+溶解+光环                │
    │  Audio (#12) ── BGM 4层+SFX池+蓄能音高           │
    │                                                  │
    │  [Cross-cutting patterns:]                       │
    │  CanvasLayer Stack (ADR-0002) — 6层 Z序          │
    │  Object Pooling (ADR-0003) — 预分配+复用         │
    └──────────────────────────────────────────────────┘
```

依赖流向：
- **信号流（主要）**：Foundation -> Core -> Presentation（由 GSM 的状态变化触发，经 Player、Absorption、Transformation、Wave 等系统传递）
- **数据查询流**：Presentation -> Core -> Foundation（HUD 读 PlayerSystem.hp_current 和 AbsorptionSystem.meter_current）
- **信号依赖关系**：VFX 连接 11 个信号（GSM + Player + Transformation + Wave），Audio 连接 8+ 个信号，HUD 连接来自 5 个 Core 系统的信号

---

## Data Flow

**Gameplay Data Flow（配置到渲染）**：DataConfig（启动时一次性加载）-> Game Systems 读取配置并初始化 -> 游戏过程中系统产生实时数据（HP、计量表、波次）-> Presentation 层通过只读属性查询或通过信号订阅接收更新 -> HUD/VFX/Audio 渲染反馈。配置数据绝不流回 DataConfig — 它是只读源。运行时数据绝不跨系统写入 — 每个系统是其自身状态的唯一所有者。

**Event Flow（信号流）**：Game Systems 在事件发生时发射信号 -> 信号在 `_ready()` 中建立的连接图上传播 -> Presentation 层和其他 Core 系统的回调处理器被触发。信号是广播式的（一个发射者 -> 多个监听者），但监听者不相互通信。典型的帧级事件链：`EnemyController._die()` -> `EnemySystem.enemy_killed` -> `WaveSystem._on_enemy_killed()` 检查波次清空 + `VFX` 播放死亡粒子 + `Audio` 播放死亡音效。

**State Flow（状态流）**：GSM 是唯一的状态权威。状态转换触发链：GSM 验证转换 -> 执行 `_exit_state(old)` / `_enter_state(new)` -> 发射 `state_changed(old, new)` -> 调用 `InputSystem.set_blocked_actions(new)` -> 11 个系统接收信号并切换行为。整个转换在一个 `_execute_transition()` 调用中完成，是原子操作。系统不得从自身上下文推断状态 — 始终通过 `GSM.current_state` 查询或响应 `state_changed` 信号。

**性能备注**：配置读取是启动时一次性操作（O(1) 属性访问）。信号发射是 Godot 原生调度（每个发射 < 0.01ms）。HUD 使用 dirty-flag 避免空闲帧渲染。VFX 和 Audio 的 `_process()` 仅在活跃效果或音频播放时运行。

---

## ADR Index

| ADR | Title | Layer | Status | Autoload # |
|-----|-------|-------|--------|------------|
| ADR-0001 | Autoload Singleton Architecture | Foundation | Accepted | (all 12) |
| ADR-0002 | CanvasLayer Rendering Architecture | Presentation | Accepted | — |
| ADR-0003 | Object Pooling Architecture | Presentation | Accepted | — |
| ADR-0004 | Signal Bus Pattern | Foundation | Accepted | — |
| ADR-0005 | Data Configuration Architecture | Foundation | Accepted | #1 |
| ADR-0006 | Input System Architecture | Foundation | Accepted | #3 |
| ADR-0007 | Game State Machine Architecture | Foundation | Accepted | #2 |
| ADR-0008 | Absorption System Architecture | Core | Accepted | #6 |
| ADR-0009 | Transformation System Architecture | Core | Accepted | #7 |
| ADR-0010 | Enemy System Architecture | Core | Accepted | #5 |
| ADR-0011 | Wave System Architecture | Core | Accepted | #9 |
| ADR-0012 | Player System Architecture | Core | Accepted | #4 |
| ADR-0013 | Area System Architecture | Core | Accepted | #8 |
| ADR-0014 | HUD/UI System Architecture | Presentation | Accepted | #10 |
| ADR-0015 | VFX System Architecture | Presentation | Accepted | #11 |
| ADR-0016 | Audio System Architecture | Presentation | Accepted | #12 |

---

## Open Architectural Questions

1. **EventBus 引入时机（ADR-0004 推迟）**：当前触发条件是"单个事件需要 5+ 监听者，或引入动态系统加载"。在 Vertical Slice 阶段新增 BossSystem、MutationSystem、FormUnlockSystem 后，`state_changed` 的监听者将超过 11 个，需要重新评估是否引入 SignalBus Autoload。

2. **场景管理器尚未定义**：当前架构没有明确的场景管理器（Scene Manager）负责加载/卸载游戏场景（主菜单、游戏世界、胜利画面）。这些职责目前隐式分配给了 GSM（`Engine.time_scale` 控制）和 WaveSystem（`all_waves_cleared` 触发胜利）。Vertical Slice 阶段可能需要一个 ADR 定义场景生命周期管理。

3. **Area ↔ Wave 循环依赖**：systems-index.md 中标记了区域系统与波次系统的循环依赖。ADR-0011 和 ADR-0013 通过数据查询解耦（WaveSystem 调用 `AreaSystem.get_enemy_pool_for_wave()` 读取数据，AreaSystem 订阅 `WaveSystem.all_waves_cleared` 但不持有 WaveSystem 引用）解决了此问题。当前方案在 MVP（单区域）下工作正常，但在 Vertical Slice（多区域过渡）需要在区域切换时通知 WaveSystem 重新开始波次序列 — 这个通知机制尚未在 ADR 中明确定义。

4. **存档系统的加载顺序**：存档系统（Systems Index #18）是一个 Foundation 层系统（零依赖），计划在 Vertical Slice 阶段实现。它需要决定是作为 Autoload #0（在 DataConfig 之前加载，以便在 DataConfig 加载配置之前还原玩家存档状态）还是作为稍后的 Autoload。这需要一个新的 ADR。

5. **跨系统数据一致性**：多项 ADR 引用了同一个数据（例如 FormConfig 被 TransformationSystem、VFX、Audio、HUD 四个系统读取），但数据本身在 DataConfig 中是不可变的。当前没有机制确保运行时某个系统缓存的 FormConfig 与 DataConfig 中的一致 — 这依赖于"配置在运行时不可变"的约定。如果未来引入运行时动态修改配置的需求（例如调试控制台调整属性），需要一个新的数据一致性 ADR。

6. **Transform 期间玩家属性倍率模式**：ADR-0012 的代码注释中指出了 ADR-0001 的规则违反 — TransformationSystem 直接写入 `player.speed_mult` 会被 ADR-0001 禁止。修正方案是 PlayerSystem 订阅 `transformation_started` 信号并自行应用倍率。这在 ADR-0009 的决策中已明确（"PlayerSystem listens to transformation_started and applies stat modifiers"），但 ADR-0012 的实现代码示例中仍有模糊之处。实现阶段需要确保一致性。
