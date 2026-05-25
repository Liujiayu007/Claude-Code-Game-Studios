# Data Config System — 数据配置系统

> **Status**: In Design
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: All（间接支撑全部三个支柱——可配置数值驱动变身手感、变异多样性、难度节奏）

## Overview

数据配置系统（Data Config System）是 Shapeshift Survivor 中所有可调数值和静态数据表的单一真相源（Single Source of Truth）。它将游戏的所有参数——敌人血量、波次生成数量、变身持续时间、变异效果倍率、区域敌人类型表——集中存储为结构化、可编辑的配置文件，使数值调优可以在不触碰游戏代码的情况下完成。

**技术层面**：系统提供一套统一的配置加载和查询接口。任何系统需要"骑士杂兵有多少血"或"兽形态冷却多少秒"时，不自行硬编码，而是通过本系统查询。配置数据在游戏启动时加载至内存，运行期间只读。所有数值集中在一个目录下，按系统分文件组织，修改后重启场景即可生效（Godot 编辑器内支持热重载）。

**玩家层面**：玩家永远不会看到"配置文件"。但他们每时每刻感受到的东西——变身的爆发力（持续时间/冷却的数值平衡）、波次的压迫感（敌人密度递增曲线）、变异的选择价值（+30% 攻击 vs +20% 范围的差异）——全部流经这层配置。当战斗"感觉太简单"或"变身不够爽"时，解决方案应该是一个数值改动，而不是一次代码改动。

没有这个系统，每个系统各自硬编码数值——调优需要找到对应脚本、改数字、重新导出，且两个系统可能因沟通不畅而使用矛盾的数值。有这个系统后，所有数值在一个地方被审视、比较和调整。

## Player Fantasy

数据配置系统本身不产生玩家幻想——它是一个静默的基础设施层，玩家永远不会意识到它的存在。它的"幻想"体现在它出问题时：

- 当数值**正确**时，玩家什么都不会注意到——战斗节奏流畅、变身爆发有力、升级选择有价值感。这是数据配置系统的理想状态：**透明到不可见**。
- 当数值**错误**时，玩家会感到不安——同一把武器突然伤害不对、变身持续了"太久"或"太短"、敌人突然变得太硬或太脆。这不是玩家在批评数据配置系统；这是玩家在感受**数值一致性的崩塌**。

因此，该系统的"幻想"可以表述为：

> **"一切如你所料"** —— 每次游戏的数值行为保持一致、可预期、且经过深思熟虑。玩家不需要怀疑"这次变身是不是和上次不一样"——因为所有数值从一个源头流出，永不矛盾。

该系统间接支撑全部三个游戏支柱：
- **支柱 1（爆发变身）**：变身持续时间和冷却时间的精确数值直接决定"爆发感"的节奏
- **支柱 2（有意义的选择）**：变异效果的数值差异（+30% vs +20%）是"选择有意义"的数学基础
- **支柱 3（节奏掌控）**：波次递增曲线和敌人属性曲线定义了什么速度是"可掌控的压力"

## Detailed Design

### Core Rules

**Rule 1: Godot Resource 定义所有配置**

每个配置类别（敌人属性、波次参数、变身数值、变异效果等）对应一个 Godot `Resource` 子类。每个 Resource 类的属性即为该配置项的调优参数。示例：

```gdscript
# enemy_config.gd
class_name EnemyConfig extends Resource
@export var enemy_id: String = ""
@export var display_name: String = ""
@export var hp: int = 1
@export var speed: float = 100.0
@export var damage: int = 1
@export var form_points_drop: int = 1
@export var sprite_frame_width: int = 16
@export var sprite_frame_height: int = 16
```

每个 Resource 类以 `.tres` 文件形式存储在 `assets/config/[category]/` 下。一个 `.tres` 文件 = 一个配置实例（如一个敌人类型 / 一个形态定义 / 一个波次模板）。

**Rule 2: Config 单例统一入口**

提供一个 `Config` Autoload 单例，负责：
- 启动时从 `assets/config/` 加载所有 `.tres` 文件至内存字典
- 提供强类型访问器方法，每个配置类别一个
- 缓存已加载数据，运行期间零磁盘读取

**Rule 3: 强类型访问器接口**

每个配置类别暴露一个以该类别命名的访问器方法，返回类型安全的配置对象或集合：

```gdscript
# 单值查询——返回特定配置实例
Config.enemy("slime_melee")           # → EnemyConfig
Config.form("beast")                  # → FormConfig
Config.wave_template("plains_horde")  # → WaveTemplateConfig

# 集合查询——返回该类别所有配置
Config.all_enemies()                  # → Array[EnemyConfig]
Config.all_mutations("beast")         # → Array[MutationConfig]
Config.area_params("windsong_plains") # → AreaParamsConfig
```

查询方法内部做缓存查找（O(1) 字典查询）。不存在的 key 返回 `null` 并打印错误日志——绝不静默失败。

**Rule 4: 配置运行时只读**

所有通过 Config 单例获取的配置对象为只读。运行期间禁止任何系统修改配置值。需要修改数值时，在 Godot 编辑器中编辑 `.tres` 文件，然后重启场景。这确保了：
- 对局期间数值行为一致（不会"打着打着敌人突然变了"）
- 所有修改有迹可循（Git diff 直接可见 `.tres` 变化）
- 多人协作时不会因为运行时修改而产生隐式状态

**Rule 5: 编辑器中支持热重载**

在 Godot 编辑器内运行游戏时，修改 `.tres` 文件后 Godot 的 Resource 系统自动通知 Config 单例重新加载。这使设计师可以：运行游戏 → 感觉数值不对 → 在 Inspector 中修改 `.tres` → 下一波敌人立即应用新值。仅在编辑器模式下启用；导出构建中禁用。

**Rule 6: 启动时验证**

Config 单例加载完成后，运行验证流程：
- 检查所有必填字段非空/非零
- 检查数值范围（如 HP 不能为负数、持续时间不能为零）
- 检查引用完整性（如敌人表引用的掉落物 ID 必须存在）
- 验证失败 → 打印错误日志 + 使用默认回退值 + 在编辑器中弹警告

**Rule 7: 配置目录结构**

```
assets/config/
├── enemies/
│   ├── plains/
│   │   ├── slime_melee.tres
│   │   ├── slime_ranged.tres
│   │   └── ...
│   ├── forest/
│   │   └── ...
│   └── castle/
│       └── ...
├── forms/
│   ├── human.tres
│   ├── beast.tres
│   ├── dragon.tres
│   └── titan.tres
├── waves/
│   ├── plains_waves.tres
│   ├── forest_waves.tres
│   └── castle_waves.tres
├── mutations/
│   ├── beast_mutations.tres
│   ├── dragon_mutations.tres
│   └── titan_mutations.tres
├── area_params/
│   ├── windsong_plains.tres
│   ├── black_miasma_forest.tres
│   └── demon_lord_castle.tres
├── difficulty/
│   ├── easy.tres
│   ├── normal.tres
│   └── hard.tres
└── global.tres
```

### States and Transitions

数据配置系统是无状态的只读查询层。它自身只有两个阶段：

| 状态 | 描述 | 进入条件 |
|------|------|---------|
| **未加载** | Config 单例尚不可用，任何查询返回错误 | 游戏启动，Config._ready() 尚未完成 |
| **已加载** | 所有配置就绪，查询正常工作 | Config._ready() 完成加载和验证 |

加载是同步的（Godot Resource 加载速度足以在启动帧内完成），因此在实际游戏中，未加载状态仅持续 <1 帧。其他系统在 `_ready()` 中查询 Config 时，Config 已先于它们完成初始化（Autoload 的 `_ready()` 按节点树顺序优先执行）。

### Interactions with Other Systems

数据配置系统是被所有其他系统单向查询的被动服务层——它不主动调用任何系统。

| 消费方系统 | 查询内容 | 典型查询时机 |
|-----------|---------|-------------|
| 玩家系统 | 人类形态基础属性（HP/移速/攻击力/攻击范围） | 对局开始时、变身恢复人形时 |
| 敌人系统 | 敌人类型属性（HP/移速/伤害/掉落点数/精灵尺寸） | 每个敌人实例化时 |
| 波次系统 | 波次模板（波次 N 的敌人类型/数量/间隔/精英概率） | 每波开始时 |
| 吸收系统 | 形态点数基础值（每个敌人掉落量/拾取半径） | 拾取判定时 |
| 变身系统 | 形态属性（持续时间/冷却时间/攻击模式/伤害倍率/移速倍率） | 变身激活时 |
| 变异系统 | 变异效果定义（效果类型/数值/稀有度/兼容形态） | 升级界面弹出时、变异效果应用时 |
| 区域系统 | 区域参数（基础色调/环境纹理集/可用敌人池/BGM） | 区域加载时、区域切换时 |
| Boss 系统 | Boss 属性（HP/阶段数/攻击模式/掉落/登场预警时间） | Boss 生成时 |
| 难度系统 | 难度倍率（敌人 HP 倍率/伤害倍率/密度倍率/波次间隔倍率） | 对局开始时、影响敌人和波次查询 |
| 形态解锁系统 | 形态解锁条件（需要击败哪个 Boss/默认解锁列表） | 对局开始时、Boss 击败后检查 |
| HUD/UI 系统 | 显示用字符串（形态名称/变异名称/区域名称） | HUD 初始化时 |

**接口契约**：Config 单例是纯数据源——只返回数据，不执行逻辑、不修改状态、不发送信号。消费方系统负责"拿到数据后怎么用"。这个单向、只读的契约消除了所有循环依赖的可能。

## Formulas

### D.1 配置查询公式

The config lookup formula is defined as:

```
result = cache[key] ?? default_value ?? error
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| key | k | String | 非空字符串 | 配置实例的唯一标识符（如 `"slime_melee"`, `"beast"`） |
| cache | C | Dictionary | 启动时填充 | 从所有 `.tres` 文件加载的键值对字典 |
| default_value | D | 同类型 Resource | 每个类别预定义一个 | 当 key 不存在时返回的默认配置实例 |
| result | R | Resource 或 null | 有效 Resource 或 null | 查询结果；若 key 和 default 都不存在则为 null |

**Output Range:** 正常情况下返回有效的 Resource 实例。若 key 不存在但有 default → 返回 default + 打印 warning 日志。若 key 和 default 均无 → 返回 null + 打印 error 日志。

**Example:**
```
Query: Config.enemy("slime_melee")
Lookup: cache["enemy"]["slime_melee"] → EnemyConfig{hp:3, speed:80, ...}  ✓ Found
Return: EnemyConfig instance

Query: Config.enemy("nonexistent_enemy")
Lookup: cache["enemy"]["nonexistent_enemy"] → ✗ Not found
Fallback: default_enemy_config → EnemyConfig{hp:1, speed:60, ...}  ⚠ Default
Return: default_enemy_config + console warning
```

### D.2 启动加载时间预算

The loading time formula is defined as:

```
T_load = Σ(T_load_single_file) + T_validate
T_load_single_file ≤ 0.5ms (Godot ResourceLoader 基准)
T_validate ≤ 0.1ms per file
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| 配置文件总数 | N | int | 20–80（估算） | 所有 `.tres` 文件的数量 |
| 单文件加载时间 | t_load | float | 0.1–0.5ms | Godot ResourceLoader 的典型加载耗时 |
| 单文件验证时间 | t_valid | float | 0.05–0.1ms | 必填字段检查 + 范围检查 |
| 总加载时间 | T_load | float | < 50ms（硬上限） | 必须在 Godot 的首帧内完成 |

**Output Range:** 20–80 文件 × (0.5 + 0.1)ms = 12–48ms。在 50ms 硬上限内。

**Example:** 50 个配置文件 × 0.6ms/file = 30ms 总加载时间。在 60fps 目标（16.67ms/帧）下，加载跨越 2 帧。Config 单例应在首帧内完成加载以保证其他 Autoload 在 `_ready()` 中安全查询。

### D.3 数值验证规则

Config 单例在加载完成后对每个 Resource 实例执行以下验证。格式：

```
validate(resource):
  for each @export var in resource:
    if var has @export_range annotation → check value in [min, max]
    if var is int and represents HP/damage/count → check value ≥ 0
    if var is float and represents duration/cooldown → check value > 0.0
    if var is String and represents id/name → check value is not empty
    if var is Resource reference → check referenced resource exists in cache
```

**变量范围约束表：**

| 变量类型 | 语义 | 有效范围 | 违反处理 |
|---------|------|---------|---------|
| HP / 生命值 | int | ≥ 1 | 强制设为 1 + warning |
| Speed / 速度 | float | > 0, ≤ 1000 | 强制 clamp + warning |
| Damage / 伤害 | int | ≥ 0 | 强制设为 0 + warning |
| Duration / 持续时间 | float | > 0, ≤ 300 | 强制 clamp + warning |
| Cooldown / 冷却时间 | float | ≥ 0, ≤ 300 | 强制 clamp + warning |
| Drop count / 掉落数量 | int | ≥ 0, ≤ 100 | 强制 clamp + warning |
| Form points / 形态点数 | int | ≥ 1, ≤ 50 | 强制 clamp + warning |
| String id / 标识符 | String | 非空，仅含 `[a-z0-9_]` | 替换非法字符 + warning |

## Edge Cases

- **如果 `.tres` 文件损坏或无法解析**：Godot ResourceLoader 返回 null。Config 打印 error 日志标明文件路径，加载该文件对应的默认 Resource 实例（每个配置类别预定义一个 default），继续启动。不因单个配置文件损坏而阻止整个游戏启动。

- **如果两个 `.tres` 文件声明了相同的 `id`**：后加载的文件覆盖先前的（Dictionary key 覆盖语义）。打印 warning 日志："Duplicate config key '[id]' — [file_a] overwritten by [file_b]"。设计师应确保 id 唯一。

- **如果配置值超出有效范围**（如 HP = -5, duration = 0）：验证阶段检测到后，将值强制 clamp 到有效范围，打印 warning 日志标明文件/字段/原始值/修正值。不阻止启动——使用修正后的安全值继续。

- **如果系统在 Config 加载完成前查询**：Config._ready() 在所有其他 Autoload 之前执行（Godot 按节点树顺序），因此此情况仅在代码中显式 `new Config()` 或从非 Autoload 的 `_init()` 中调用时出现。如发生，返回 default 值 + error 日志 + 调用栈追踪。

- **如果查询了不存在的 key 且该类别无默认值**：返回 null。调用方系统的责任是检查 null 并自行处理（通常打印 error 并使用硬编码回退值）。Config 不负责调用方的空值处理——但 Config 负责在 key 找不到时打印清晰的日志表明哪个系统查询了什么不存在的 key。

- **如果 `.tres` 文件的 Resource 类定义发生变更**（如删除了一个字段、改了字段类型）：Godot 在加载时自动处理——新字段使用默认值，已删除的字段被忽略。Config 的验证步骤检查关键字段的有效性。若类型不兼容导致加载失败，按"文件损坏"处理（回退默认值）。

- **如果在导出构建（非编辑器）中运行**：热重载功能自动禁用。所有配置在启动时一次性加载，运行期间不会重新读取磁盘。`assets/config/` 目录被 Godot 打包进 `.pck` 文件，加载路径由 Godot 的 `res://` 虚拟文件系统处理——无需额外适配。

- **如果配置文件总数超过预期（>80 文件）导致加载时间超过 50ms 硬上限**：Config 在加载完成后检查 `Time.get_ticks_msec()` 差值。若超过 50ms，打印 warning："Config load took [N]ms — consider reducing config file count or implementing async loading"。50ms 是软上限——不阻止启动，但提示需要关注。

- **如果同一 key 被多个系统高频查询（每帧数百次）**：字典查询为 O(1)，在 Godot GDScript 中 <0.001ms/次。即使 20 个系统 × 每帧 10 次查询 = 200 次/帧，总耗时 <0.2ms。无性能风险。如未来遇到此问题，消费方系统应缓存查询结果到本地变量，而非每帧调用 Config。

## Dependencies

### 上游依赖（本系统依赖）

**无。** 数据配置系统是 Foundation 层系统，零上游依赖。它仅依赖 Godot 引擎内建的 `ResourceLoader` 和文件系统——这些是引擎提供的能力，不属于游戏系统。

### 下游依赖方（依赖本系统）

所有其他 20 个系统依赖数据配置系统获取可调数值。按依赖性质分类：

**硬依赖（系统无 Config 无法运行）：**

| 系统 | 依赖内容 | 性质 |
|------|---------|------|
| 玩家系统 | 人类形态 HP/移速/攻击力/攻击范围 | 核心属性缺失→玩家无法操作 |
| 敌人系统 | 所有敌人类型的属性 | 敌人实例化必须知道 HP/速度/掉落 |
| 变身系统 | 各形态的持续时间/冷却/伤害倍率 | 变身核心参数 |
| 波次系统 | 每波敌人类型/数量/间隔 | 波次生成逻辑 |
| 变异系统 | 所有变异效果的定义和数值 | 升级选项内容 |
| 吸收系统 | 形态点数基础值 | 核心循环经济 |
| 区域系统 | 区域参数（可用敌人/BGM/视觉） | 区域加载 |

**软依赖（Config 提升质量但系统有合理默认值）：**

| 系统 | 依赖内容 | 回退方案 |
|------|---------|---------|
| Boss 系统 | Boss 属性/阶段/掉落 | 可硬编码单个 Boss 原型 |
| 难度系统 | 难度倍率表 | 可硬编码 3 档倍率 |
| 形态解锁系统 | 解锁条件配置 | 可硬编码"击败 Boss X 解锁形态 Y" |
| HUD/UI 系统 | 显示字符串 | 可硬编码显示名称 |
| 对局管理系统 | 对局参数 | 可硬编码默认值 |

### 接口契约

数据配置系统向所有下游依赖方提供以下保证：

1. **可用性保证**：Config 单例在任何其他 Autoload 的 `_ready()` 调用前完成加载
2. **一致性保证**：同一 key 在同一次对局中始终返回同一实例（缓存不失效）
3. **类型安全保证**：所有访问器返回强类型的 Resource 子类，消费方无需做类型转换
4. **错误可见性保证**：所有查询失败（key 不存在/值越界/文件损坏）产生可读日志

消费方应向 Config 提供的保证：

1. **只读保证**：不修改获取到的 Resource 实例的属性
2. **空值处理**：检查 null 返回值并做安全回退
3. **缓存自由**：消费方可自由缓存查询结果到本地变量以减少函数调用开销

## Tuning Knobs

### G.1 配置系统自身参数

这些参数控制 Config 单例的行为，定义在 `assets/config/global.tres` 中：

| 参数 | 类型 | 默认值 | 范围 | 如果设置太高 | 如果设置太低 |
|------|------|--------|------|------------|------------|
| `load_timeout_ms` | int | 50 | 10–200 | 启动时卡顿超过可接受范围 | 大型配置可能在截止前加载不完，误报 warning |
| `hot_reload_enabled` | bool | true | true/false | —（开/关无"太高"） | 编辑器内调优效率降低，每次改值需重启场景 |
| `validation_strictness` | enum | `warn` | `silent` / `warn` / `error` | `error` 模式下值越界会阻止启动——适合 CI 但不适合快速迭代 | `silent` 模式下越界值静默修正——可能掩盖真正的设计错误 |
| `log_config_on_startup` | bool | false | true/false | 启动时打印所有配置键和值——日志洪水 | —（关掉无代价，仅在调试时需要） |

### G.2 添加新配置类别（扩展流程）

当新系统需要自己的配置数据时，按以下步骤扩展：

1. **创建 Resource 类**：在 `src/config/` 下新建 `.gd` 脚本，继承 `Resource`，`class_name` 命名格式为 `[Category]Config`
2. **定义 `@export` 属性**：每个属性 = 一个调优旋钮。使用 `@export_range` 标注有效范围
3. **创建 `.tres` 文件**：在 `assets/config/[category]/` 下创建配置实例
4. **注册到 Config**：在 Config 单例中添加该类别对应的访问器方法和字典
5. **添加默认值**：为该类别创建一个 `default_[category].tres` 作为查询失败时的回退

示例——添加一个新的配置类别：

```gdscript
# weather_config.gd
class_name WeatherConfig extends Resource
@export var weather_id: String = ""
@export var particle_count: int = 10
@export_range(0.0, 1.0) var opacity: float = 0.3
@export var duration_seconds: float = 30.0
```

```gdscript
# 在 Config.gd 中注册
var _weather_cache: Dictionary = {}

func weather(id: String) -> WeatherConfig:
    return _weather_cache.get(id, _default_weather)

func all_weathers() -> Array[WeatherConfig]:
    return _weather_cache.values()
```

### G.3 调优工作流

设计师调优某个数值的标准流程：

1. 在 Godot 编辑器中运行游戏
2. 在 FileSystem 面板找到对应的 `.tres` 文件
3. 在 Inspector 中修改数值
4. 观察游戏内效果（热重载在下一帧生效）
5. 满意后保存 `.tres` 文件
6. `.tres` 文件随代码一起提交 Git

**关联关系**：某些旋钮会相互影响。例如：
- 改变 `BeastFormConfig.duration` 可能需要对应调整 `BeastFormConfig.cooldown` 以保持"蓄能→爆发→冷却"的节奏比例
- 改变 `EnemyConfig.hp` 需要对应考虑 `WaveTemplateConfig.spawn_count`——更硬的敌人 + 同样数量 = 更难
- 改变全局 `global.tres` 中的 `base_move_speed` 会影响所有玩家形态和敌人的速度感知

这些关联不在配置系统中自动处理——属于设计师的调优判断。Config 系统只保证"改一个值不会意外影响另一个不相关的值"。

## Acceptance Criteria

- **GIVEN** 游戏启动且所有 `.tres` 文件完整有效，**WHEN** Config._ready() 完成，**THEN** 所有配置类别访问器返回非空值，加载总耗时 < 50ms，控制台无 error 或 warning 日志。

- **GIVEN** 一个有效的敌人配置键（如 `"slime_melee"`），**WHEN** 调用 `Config.enemy("slime_melee")`，**THEN** 返回一个 `EnemyConfig` 实例，其 `hp` > 0，`speed` > 0，`enemy_id` = `"slime_melee"`。

- **GIVEN** 一个不存在的配置键（如 `"nonexistent_enemy"`），**WHEN** 调用 `Config.enemy("nonexistent_enemy")`，**THEN** 返回该类别预定义的默认 EnemyConfig 实例 + 控制台打印 warning 日志。

- **GIVEN** 某个 `.tres` 文件中的 `hp` 字段被手动设为 -5，**WHEN** Config 加载完成并运行验证，**THEN** `hp` 被自动修正为 1 + 控制台打印 warning 日志标明文件路径和修正值。

- **GIVEN** 游戏在 Godot 编辑器中运行且 `hot_reload_enabled = true`，**WHEN** 设计师在 Inspector 中修改某个 `.tres` 文件的数值并保存，**THEN** 下一次 Config 查询返回更新后的值，无需重启场景。

- **GIVEN** 游戏在导出构建（非编辑器）中运行，**WHEN** 调用 `Config.enemy("slime_melee")`，**THEN** 返回与编辑器中相同的配置值，且运行期间磁盘上的 `.tres` 文件修改不影响正在运行的游戏。

- **GIVEN** `assets/config/` 目录下缺少一个 `.tres` 文件（如 `beast.tres` 被误删），**WHEN** 游戏启动，**THEN** 游戏正常启动不崩溃，调用 `Config.form("beast")` 返回默认 FormConfig 实例 + 控制台打印 error 日志标明缺失文件路径。

- **GIVEN** 两个 `.tres` 文件声明了相同的 `id = "slime_melee"`，**WHEN** Config 加载完成，**THEN** 后加载的文件覆盖前者 + 控制台打印 duplicate key warning。

- **GIVEN** Config 单例加载完成后，**WHEN** 任意其他 Autoload 在其 `_ready()` 中调用 Config 的任意查询方法，**THEN** 返回有效数据，无 null 或 "Config not loaded" 错误。

- **GIVEN** 玩家系统在 `_process()` 中每帧调用 `Config.enemy(...)`，**WHEN** 连续运行 60 秒（约 3600 次查询），**THEN** 帧率保持在 60fps，Config 查询不成为性能瓶颈（单次查询 <0.01ms）。

- **GIVEN** 一个 `.tres` 文件包含一个 `Resource` 引用字段（如 `BossConfig` 引用 `EnemyConfig`），**WHEN** Config 验证阶段检查引用完整性，**THEN** 若引用的 Resource 存在 → 通过；若引用不存在 → warning 日志 + 使用默认引用。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 配置文件总数估算——当前估算 20-80 个 `.tres` 文件。各系统 GDD 完成后方可得到精确数量。是否存在单类别超过 20 个文件的情况（如敌人种类超过 20）？如果超过，是否需要子文件夹层级？ | 否——当前架构支持 100+ 文件 | 所有系统 GDD 完成时 |
| 2 | 大型表格数据的表示——波次定义中每波有多个敌人类型/数量，用 `.tres` 的 Array 字段是否足够直观？还是需要引入 CSV 用于纯表格数据？ | 否——Array 字段在 Godot Inspector 中可展开编辑，对 solo 项目足够 | 波次系统 GDD 设计时决定 |
| 3 | 配置 Schema 版本化——当 Resource 类增加新字段后，旧的 `.tres` 文件缺少该字段。Godot 自动使用默认值，但无法区分"有意使用默认值"和"忘记填写"。是否需要每个 `.tres` 包含一个 `schema_version` 字段？ | 否——当前项目规模下，缺失字段使用默认值 + warning 足够 | 若后续出现字段遗漏导致 bug，再做决策 |
| 4 | Config Autoload 的节点顺序——Godot 按节点树顺序执行 Autoload 的 `_ready()`。Config 必须在所有其他 Autoload 之前加载。Godot 的 Autoload 优先级通过 Project Settings → Autoload 列表的排列顺序控制——Config 应排在第一。此设置需在 `/setup-engine` 后确认。 | 否——Project Settings 配置不阻塞 GDD | 引擎配置完成后 |

## Visual/Audio Requirements

不适用。数据配置系统不产生视觉或音频输出——它是纯数据层，在后台静默运行。

## UI Requirements

不适用。数据配置系统没有玩家可见的 UI。设计师通过 Godot 编辑器的 Inspector 面板（引擎内建工具）编辑 `.tres` 文件——这属于开发工具链，不是游戏 UI。
