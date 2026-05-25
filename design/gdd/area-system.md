# Area System — 区域系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 3 (Paced Mastery)

## Overview

区域系统（Area System）定义和管理 Shapeshift Survivor 中的可玩区域——从 MVP 的单一区域"风歌草原"（Windsong Prairie）到 Vertical Slice 阶段扩展至三大区域。每个区域是一组配置数据的集合：视觉主题（背景、色调、光照风格）、敌人类型表（该区域允许生成哪些敌人）、波次组成参数（敌人密度/类型占比）、Boss 指派、以及环境音轨。

**技术骨架**：区域系统不直接生成敌人或控制波次——它通过 `AreaConfig` Resource 向波次系统、敌人系统和视觉系统提供数据。`AreaConfig` 存储在 `assets/config/areas/` 中，由数据配置系统加载。区域系统负责：暴露当前区域的 `AreaConfig` 供其他系统查询、响应 GSM 状态变更触发区域切换（如 Boss 击败后进入下一区域）、管理区域之间的过渡（加载/卸载环境资产）。

**玩家体验**：玩家不直接操作区域系统——但玩家**感受到**它的每一项输出。区域决定了玩家在哪里战斗、面对什么敌人、看到什么背景。当波次推进到 Boss 波时，区域定义了 Boss 的类型和登场方式。当玩家击败 Boss 并进入下一区域时，背景突然变化、新敌人类型出现、音乐切换——这是区域系统通过 GSM 状态转换实现的"世界推进"时刻。

**没有这个系统会失去什么**：游戏只有一个无尽平原——没有区域边界、没有视觉变化、没有敌人类型的递进引入。30 分钟的 session 看着同一片草原、打着同样的敌人。区域系统提供了结构——它将"风歌草原→熔岩深渊→冰霜遗迹"的旅程变成玩家可感知的进度，让每次区域切换成为"我走得更远了"的里程碑。

## Player Fantasy

区域系统服务于玩家的**探索与征服感**——你不是在一个抽象竞技场中战斗，你是在穿越一个世界。

> **"我穿过了草原，击败了草原的守护者，现在前方是燃烧的大地——我准备好了吗？"**

区域切换是 Shapeshift Survivor 中最明确的进度信号。波次数字在增长，但那是抽象的；当你看到背景从翠绿草原变为暗红熔岩地，当新的敌人类型首次出现（你在草原从未见过这个），当 Boss 的登场方式从地面裂开变为从天而降——这些是玩家**感受到**的进度。

**区域系统的三个幻想锚点：**

1. **地方感（Sense of Place）**: 风歌草原不是一个"关卡"，它是一个地方——有名字、有视觉身份、有敌人生态。玩家在草原上打史莱姆——这不是随机的，这是**这个区域的主题**。当精英巨型史莱姆出现时，它属于这里——它是草原生态的一部分。

2. **递进揭示（Progressive Revelation）**: 区域系统控制敌人类型的引入节奏。玩家在区域 1（风歌草原）学会对抗近战杂兵和远程射手；区域 2（如熔岩深渊）引入更快、更危险的敌人类型；区域 3（如冰霜遗迹）引入减速和控制效果。每个新区域教授新的生存技能——从"学会走位"到"学会优先击杀远程"到"学会在减速中拉开距离"。

3. **征服里程碑（Conquest Milestone）**: 击败区域 Boss → 进入新区域。这是玩家在长时间 session 中获得的"我赢了这一章"的正反馈。区域切换的瞬间——背景变化、音乐切换、新敌人出现——必须给予玩家"我做到了"的满足感，同时以"但这更难——准备好"引发适度的紧张。

**参考游戏中的类似感觉**：
- **Vampire Survivors 的阶段选择**——每个阶段有不同的敌人阵容和视觉风格。玩家选择"疯森林"vs"图书馆"时预期不同的体验。我们的区域切换更线性（Boss 击败后自动推进），但"新地方=新敌人=新挑战"的感觉是一致的。
- **Diablo 系列的区域切换**——从鲜血荒地到沙漠到地狱，每个 Act 的视觉和敌人完全不同。区域切换时玩家感到"旅程在推进"——这是我们想要的感受。

## Detailed Design

### Core Rules

**Rule 1: AreaConfig 定义所有区域参数**

每个区域对应一个 `AreaConfig` Resource（存储在 `assets/config/areas/`）。区域系统在初始化时加载所有 AreaConfig，运行时只读。

**Rule 2: 单区域激活——`current_area_id`**

任意时刻有且仅有一个区域处于激活状态。区域系统暴露 `current_area_id: String` 和 `current_area_config: AreaConfig`（只读）供所有系统查询。

**Rule 3: 区域切换——Boss 击败触发**

区域切换通过 GSM 状态转换触发：
1. Boss 系统发出 `boss_defeated` 信号
2. 区域系统检查 `AreaConfig.next_area_id`
3. 若 `next_area_id` 存在 → 加载下一区域配置、发出 `area_changing(old_id, new_id)` → 更新 `current_area_id` → 发出 `area_changed(new_id)` → GSM 进入 EXPLORATION 状态（开始新区域的波次循环）
4. 若 `next_area_id` 为空 → 玩家已通关所有区域——进入胜利结算

**Rule 4: 区域决定可用敌人类型**

波次系统在生成波次前查询 `current_area_config.enemy_pool`——当前区域允许的敌人类型列表及其生成权重。区域系统不直接参与波次生成，仅提供敌人表。

**Rule 5: 环境参数——视觉/音频系统查询**

VFX 系统查询 `current_area_config.background_key`、`lighting_color`、`ambient_particle` 来设置场景。音频系统查询 `current_area_config.bgm_track` 播放区域主题音乐。

**Rule 6: 向后兼容——MVP 单区域**

MVP 仅风歌草原一个区域。`next_area_id = null`——Boss 击败后进入胜利结算。区域切换逻辑完整实现但仅在 Vertical Slice 多区域场景下触发。

### MVP Area: Windsong Prairie（风歌草原）

| 属性 | 值 | 说明 |
|------|-----|------|
| `area_id` | `"windsong_prairie"` | 唯一标识符 |
| `display_name` | "风歌草原" | 玩家可见名称 |
| `description` | "艾瑟兰的起始之地——微风拂过金色草原，史莱姆在草丛中游荡。看似平静，却是每个觉醒者的试炼场。" | 氛围描述文字 |
| `area_order` | 1 | 在区域序列中的位置 |
| `next_area_id` | `null` (MVP) / `"magma_chasm"` (VS) | 通关后前往的区域 |
| `enemy_pool` | 见下方敌人表 | 可用敌人类型 + 生成权重 |
| `boss_id` | `"giant_slime_king"` | 该区域的 Boss 标识符（MVP 暂未设计，VS 阶段由 Boss 系统 GDD 定义） |
| `total_waves` | 5 (MVP) | 该区域总波次数（含 Boss 波） |
| `background_key` | `"bg_windsong_prairie"` | 背景精灵资源标识符 |
| `ground_tile_key` | `"tile_grass"` | 地面 TileMap 资源标识符 |
| `lighting_color` | `#FFF8DC` (暖金色) | 环境光照颜色——暖黄阳光感 |
| `ambient_particle` | `"pollen_float"` | 环境粒子——漂浮的花粉/草籽 |
| `bgm_track` | `"bgm_windsong_prairie"` | 背景音乐 |
| `ambient_sound` | `"ambient_wind_grass"` | 环境音效——微风 + 草叶沙沙声 |

#### 敌人表 (enemy_pool)

| Enemy ID | 权重 | 引入波次 | 说明 |
|----------|------|---------|------|
| `slime` | 50 | 波次 1 | 基础近战敌人，从第一波即出现 |
| `slime_ranged` | 20 | 波次 2 | 远程敌人，第二波引入——教玩家优先击杀远程 |
| `charger` | 20 | 波次 3 | 快速冲刺敌人，第三波引入——教玩家走位躲避直线冲刺 |
| `elite_slime` | 10 | 波次 4 | 精英敌人，第四波引入——高 HP 高伤害，压力升级 |
| `boss` | — | 波次 5 | Boss 波——Giant Slime King（MVP 暂由精英替代，VS 由 Boss 系统实现） |

权重为相对生成概率。波次系统使用权重进行加权随机——`slime` 有 50% 的概率被选中，`elite_slime` 有 10%。每波的可选敌人受"引入波次"限制——未达引入波次前不会出现在池中。

### Future Areas (Vertical Slice+)

以下为 Vertical Slice 阶段规划的 2 个额外区域——仅列概念骨架，详细设计在对应阶段展开：

| 属性 | Magma Chasm（熔岩深渊） | Frozen Ruins（冰霜遗迹） |
|------|------------------------|------------------------|
| `area_id` | `"magma_chasm"` | `"frozen_ruins"` |
| `area_order` | 2 | 3 |
| 视觉主题 | 暗红/橙色调，熔岩河，火山岩地面 | 蓝白/青色调，冰雪覆盖的古代建筑废墟 |
| 新敌人概念 | 火元素生物、熔岩史莱姆、飞行恶魔 | 冰霜幽魂、冰晶傀儡、减速光环敌人 |
| 核心挑战 | 高速敌人 + 地面危险区域（熔岩裂隙） | 减速效果 + 远程冰冻弹射物 |
| 主题 Boss | Magma Wyrm（熔岩蠕虫） | Frost Lich（冰霜巫妖） |

### Interactions with Other Systems

| 系统 | 方向 | 交互内容 |
|------|------|---------|
| 数据配置系统 | 查询 | 加载 `AreaConfig` Resource——所有区域参数 |
| 游戏状态管理 | 订阅 | 订阅 `state_changed`——检测 BOSS → EXPLORATION 转换以触发区域切换 |
| 波次系统 | 被查询 | 暴露 `current_area_config.enemy_pool`、`total_waves`——波次系统查询以决定生成内容和波次结构 |
| 敌人系统 | 间接 | 不直接交互——波次系统读取 enemy_pool 后调用 `spawn_enemy()` |
| Boss 系统 | 被查询 + 订阅 | 暴露 `current_area_config.boss_id`——Boss 系统查询以加载对应 Boss；订阅 `boss_defeated` 信号以触发区域切换 |
| VFX 系统 | 被查询 | 暴露 `background_key`、`lighting_color`、`ambient_particle`——VFX 系统设置场景视觉 |
| 音频系统 | 被查询 | 暴露 `bgm_track`、`ambient_sound`——音频系统切换音乐和环境音效 |
| 对局管理系统 | 被查询 | 暴露 `current_area_id`——对局管理记录当前区域进度 |
| 形态解锁系统 | 间接 | `area_id` 关联 Boss 击败 → 形态解锁映射——由形态解锁系统自行维护，区域系统不持有此映射 |

## Formulas

### F.1 Enemy Pool Weighted Selection

```
total_weight = sum(enemy.weight for enemy in enemy_pool if enemy.unlock_wave <= current_wave)
random_value = randf() * total_weight
cumulative = 0
for each enemy in filtered_pool:
    cumulative += enemy.weight
    if random_value <= cumulative:
        selected_enemy = enemy
        break
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| enemy_pool | Array[EnemyPoolEntry] | 1–10 entries | 当前区域的敌人类型列表 |
| enemy.unlock_wave | int | 1–total_waves | 该敌人类型首次出现的波次 |
| enemy.weight | int | 1–100 | 该敌人类型的生成权重 |
| current_wave | int | 1–total_waves | 当前波次编号 |
| total_weight | int | 1–500 | 过滤后可用的总权重 |
| random_value | float | 0–total_weight | 随机选择值 |
| selected_enemy | String | enemy ID | 被选中的敌人类型标识符 |

**Output Range**: 一个敌人 ID 字符串。权重较高的敌人更常被选中。每波生成多个敌人时，每次独立运行此公式。

### F.2 Area Transition Check

```
if signal == "boss_defeated" AND area_id == current_area_id:
    next = current_area_config.next_area_id
    if next != null:
        load_and_activate(next)
        emit("area_changed", next)
    else:
        emit("all_areas_cleared")
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| area_id | String | — | 被击败 Boss 所属的区域 ID |
| current_area_id | String | — | 当前激活区域的 ID |
| next_area_id | String or null | — | 下一区域的 ID 或 null |

跨区域验证——仅当被击败的 Boss 属于当前激活区域时才触发切换。防止未来场景中跨区域信号误触。

### F.3 Area Order Progression

```
current_area_order = current_area_config.area_order
// 区域顺序固定：1 → 2 → 3
// area_order 仅用于 HUD 显示（如"区域 1/3"）
```

不用于任何计算逻辑——区域切换通过 `next_area_id` 显式引用（而非序数 +1），支持未来非线性分支（如玩家选择路线）。

## Edge Cases

- **如果 AreaConfig 加载失败或 current_area_id 指向不存在的配置**：区域系统在初始化时验证所有 `AreaConfig` 的完整性。若启动时 `area_order = 1` 的配置缺失，游戏无法启动——显示错误提示 "区域配置缺失：起始区域未找到"。运行时若 `load_and_activate(id)` 失败（如 `next_area_id` 拼写错误），保持当前区域不变，发出 `area_load_failed(area_id, reason)` 信号，记录 error 日志。

- **如果 `boss_defeated` 信号中携带的 `area_id` 与 `current_area_id` 不匹配**：忽略信号——不触发区域切换。这是防御性检查——防止 Vertical Slice 阶段多个 Boss 同时存在时跨区域信号误触（见 F.2 跨区域验证）。

- **如果 `next_area_id` 指向的 AreaConfig 不存在**：区域切换失败——发出 `area_load_failed(area_id, "config_missing")`。游戏保持在当前区域的 Boss 击败状态（BOSS → EXPLORATION），HUD 显示 "区域加载失败" 提示。不崩溃——玩家可继续在当前区域无限波次中游玩或手动退出。

- **如果所有区域已通关（`next_area_id = null` 且 Boss 被击败）**：发出 `all_areas_cleared` 信号。GSM 进入终局状态（如新增 VICTORY 状态，或直接过渡至对局总结）。MVP 阶段仅风歌草原，Boss 击败 = 胜利。

- **如果 `enemy_pool` 在当前波次无可用敌人**（所有敌人的 `unlock_wave > current_wave` 或池为空）：波次系统回退至默认行为——生成 `slime`（基础敌人）。若连 `slime` 配置也不可用，波次跳过（空波），发出 warning 日志："区域 [id] 波次 [n] 无可生成敌人"。

- **如果波次系统请求的 `current_wave > total_waves`**：区域系统返回 `total_waves` 对应的敌人池配置——最后一波（Boss 波）的敌人池重复使用。不报错——这可能是设计意图（Boss 波后额外无限波次）。

- **如果区域切换发生在 TRANSFORMATION 或 BERSERK 状态下**：Boss 击败时 GSM 优先处理 BOSS → EXPLORATION 转换（见 GSM Rule 4 优先级）。变身/狂暴在 BOSS 进入前已结束（BOSS 状态阻断变身输入）。若由于异常触发导致切换时仍在变身中：变身系统检测到 GSM 状态变更 → 强制结束变身 → 恢复人类形态 → 区域切换继续。不丢失区域进度。

- **如果同一 AreaConfig 被重复加载**（如 `area_changing` 信号发出后快速再次触发）：区域切换是幂等的——`load_and_activate(id)` 检查 `id == current_area_id`，若已激活则跳过加载，仅返回已有配置。不重复发射 `area_changed`。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 数据配置系统 | `AreaConfig` Resource——所有区域参数（area_id、enemy_pool、boss_id、total_waves、视觉/音频资源键）。区域系统初始化时从 `assets/config/areas/` 加载所有配置 |
| 游戏状态管理 | `GSM.current_state`——查询当前状态以判断区域切换合法性；订阅 `state_changed` 信号——响应 BOSS 状态结束以触发区域切换；`GSM.time_scale`——区域过渡期间可能需要暂停游戏 |

### 下游依赖方

| 系统 | 依赖内容 |
|------|---------|
| 波次系统 | 查询 `current_area_config.enemy_pool`（敌人类型 + 权重 + 引入波次）、`current_area_config.total_waves`——决定每波生成内容和波次总数 |
| Boss 系统 | 查询 `current_area_config.boss_id`——加载对应 Boss 配置；发出 `boss_defeated(area_id)` 信号——区域系统订阅以触发切换 |
| VFX 系统 | 查询 `current_area_config.background_key`、`lighting_color`、`ambient_particle`——设置场景背景、光照、环境粒子 |
| 音频系统 | 查询 `current_area_config.bgm_track`、`ambient_sound`——切换区域主题音乐和环境音效 |
| 对局管理系统 | 查询 `current_area_id`、`current_area_config.area_order`——记录和显示当前进度（如"区域 1/3"） |
| 形态解锁系统（Vertical Slice） | 区域 Boss 击败 → 解锁新形态的映射关系——由形态解锁系统自行维护 |
| HUD/UI 系统 | 查询 `current_area_config.display_name`——显示当前区域名称 |

### 接口契约

区域系统向消费方暴露：

1. `current_area_id: String` (只读) — 当前激活区域的标识符
2. `current_area_config: AreaConfig` (只读) — 当前激活区域的完整配置对象
3. `area_changing(old_id: String, new_id: String)` 信号 — 区域切换开始前发出
4. `area_changed(new_id: String)` 信号 — 区域切换完成后发出
5. `area_load_failed(area_id: String, reason: String)` 信号 — 区域加载失败时发出
6. `all_areas_cleared()` 信号 — 所有区域通关时发出

## Tuning Knobs

| 参数 | 风歌草原默认值 | 安全范围 | 玩法影响 |
|------|-------------|---------|---------|
| `total_waves` | 5 | 3–15 | 区域总波次数。太少→区域太短，来不及建立节奏就进入 Boss；太多→区域拖沓，玩家疲劳。MVP 5 波 ≈ 5-8 分钟 |
| `enemy_pool[each].weight` | slime=50, ranged=20, charger=20, elite=10 | 1–100 | 敌人类型分布。调整权重 = 调整区域难度曲线 |
| `enemy_pool[each].unlock_wave` | 1/2/3/4 | 1–total_waves | 敌人引入时机。太早 = 玩家被新类型压倒；太晚 = 区域前半段过于单调 |
| `boss_id` | `"giant_slime_king"` | — | 区域 Boss 选择。必须与 Boss 系统的 BossConfig 匹配。错误 ID → Boss 加载失败 |
| `next_area_id` | `null` (MVP) | null 或有效 area_id | 区域通关后的目的地。null = 最终区域 |
| `lighting_color` | `#FFF8DC` | 任意 hex 颜色 | 环境光照。太暗→敌人不可见；太亮→失去像素艺术氛围 |
| `ambient_particle` | `"pollen_float"` | 粒子资源键 | 环境粒子密度和样式。太多→视觉杂乱；太少→场景静态 |

### 核心平衡注意事项

- **权重总和变化**：当波次推进、新敌人解锁加入池时，总权重增加但单一敌人的相对概率下降。例如波次 2 引入 `slime_ranged` 后，`slime` 的相对概率从 100% 降至 50/(50+20) = 71.4%。这是期望行为——早期波次敌人类型单一（玩家学习基础），后期波次敌人混合（玩家应用技能）。

- **引入波次与 total_waves 的协调**：如果 `total_waves = 5` 但最后一个敌人类型的 `unlock_wave = 8`——该敌人永远无法生成。配置验证阶段需检查所有 `unlock_wave <= total_waves`。

- **区域难度递增**：区域 1（风歌草原）核心参数：5 波，敌人速度 30-150，伤害 5-15。区域 2（熔岩深渊）预期核心参数：7-8 波，敌人速度 60-250，伤害 10-30。每个区域的参数独立定义——不存在全局缩放公式（由难度系统在 VS 阶段处理）。

## Visual/Audio Requirements

### 视觉需求

| 需求 | 优先级 | 描述 |
|------|--------|------|
| 区域背景精灵 | MVP | 风歌草原：横向平铺草原背景——金色草地 + 远山轮廓 + 蓝天。像素艺术 64px 分辨率，4 层视差滚动（天空/远山/近草/地面）。Vertical Slice 追加：熔岩深渊（暗红火山背景）、冰霜遗迹（蓝白废墟背景） |
| 地面 TileMap | MVP | 风歌草原：绿色草地瓦片（`tile_grass`），32×32 px 瓦片尺寸。场景边界由不可通行瓦片或 invisible wall 环绕 |
| 环境光照 | MVP | 风歌草原：暖金色光照（`#FFF8DC`），通过 `CanvasModulate` 节点实现。区域切换时渐变过渡（~1.0s lerp）而非硬切 |
| 环境粒子 | MVP | 风歌草原：漂浮花粉/草籽粒子——小白色/淡黄圆点（4×4 px），缓慢上升漂移，密度约 10-15 个同时在屏幕内 |
| 区域切换过渡 | Vertical Slice | 区域切换时屏幕短暂黑屏（~0.5s），旧背景淡出、新背景淡入——给玩家一个明确的"离开→到达"视觉信号 |

### 音频需求

| 需求 | 优先级 | 描述 |
|------|--------|------|
| 区域主题音乐 (BGM) | MVP | 风歌草原：轻快、悠扬的笛子/弦乐旋律——平和但不单调。BPM 约 100-120，循环播放。音乐不应干扰战斗音效——低频和打击乐部分保持克制。Vertical Slice 追加：熔岩深渊（沉重打击乐 + 低音铜管）、冰霜遗迹（空灵钟声 + 弦乐泛音） |
| 环境音效 | MVP | 风歌草原：微风沙沙声 + 偶尔鸟鸣（~15-20s 间隔）。环境音效持续低音量播放，在变身爆发音等关键时刻自动降低音量 |
| 区域切换音频过渡 | Vertical Slice | 区域切换时：旧 BGM fade out（~1.0s）+ 新 BGM fade in（~1.0s），交叉淡入淡出。伴随一声"抵达"音效（短促上升音阶） |
| Boss 波音乐变化 | Vertical Slice | 进入 Boss 波时：当前区域 BGM 无缝切换至更强力版本（加速 BPM、增加打击乐层），Boss 击败后恢复基础 BGM 或切换至胜利音乐 |

## UI Requirements

区域系统不直接产生 UI——HUD/UI 系统查询区域系统的公开属性。以下定义 UI 需求：

| UI 元素 | 数据来源 | 优先级 | 描述 |
|---------|---------|--------|------|
| 区域名称显示 | `current_area_config.display_name` | MVP | 区域开始时短暂显示（~2s）在屏幕顶部中央——"风歌草原"文字淡入→停留→淡出。区域切换时重新显示新区域名 |
| 区域进度 | `current_area_config.area_order` / `total_areas` | Vertical Slice | HUD 角落显示"区域 1/3"——告知玩家在整体旅程中的位置 |
| 波次进度 | 波次系统提供 `current_wave` / `total_waves` | MVP | 虽不是区域系统直接提供，但 HUD 组合显示：当前区域名 + 波次 (如"风歌草原 — 波次 3/5")。此项由 HUD/UI 系统 GDD 详细定义 |

## Acceptance Criteria

- **AC1 — 区域初始化加载起始区域**：**GIVEN** 游戏启动且所有 AreaConfig 有效，**WHEN** 区域系统初始化，**THEN** `current_area_id = "windsong_prairie"`，`current_area_config` 非空，`area_order = 1`。

- **AC2 — 暴露 enemy_pool 供波次系统查询**：**GIVEN** 当前区域为风歌草原且 `current_wave = 3`，**WHEN** 波次系统查询 `current_area_config.enemy_pool`，**THEN** 返回 3 个可用敌人类型（slime、slime_ranged、charger——unlock_wave ≤ 3），elite_slime 不在列表中（unlock_wave = 4）。

- **AC3 — Boss 击败触发区域切换**：**GIVEN** GSM 状态 = BOSS，`current_area_id = "windsong_prairie"`，`next_area_id = "magma_chasm"`，**WHEN** `boss_defeated(area_id: "windsong_prairie")` 信号发出，**THEN** `area_changing("windsong_prairie", "magma_chasm")` 发出，`current_area_id` 更新为 `"magma_chasm"`，`area_changed("magma_chasm")` 发出。

- **AC4 — 最终区域 Boss 击败触发通关**：**GIVEN** `next_area_id = null`，**WHEN** `boss_defeated` 信号发出且验证通过，**THEN** `all_areas_cleared()` 信号发出。

- **AC5 — 跨区域信号验证**：**GIVEN** `current_area_id = "windsong_prairie"`，**WHEN** `boss_defeated(area_id: "magma_chasm")` 信号发出（Boss ID 不匹配），**THEN** 区域切换不触发——信号被忽略。

- **AC6 — 环境参数暴露**：**GIVEN** 当前区域为风歌草原，**WHEN** VFX 系统查询 `current_area_config.background_key` 和 `lighting_color`，**THEN** 返回 `"bg_windsong_prairie"` 和 `#FFF8DC`。

- **AC7 — 区域加载失败不崩溃**：**GIVEN** `next_area_id = "nonexistent_area"`（Config 不存在），**WHEN** Boss 击败触发区域切换，**THEN** `area_load_failed("nonexistent_area", "config_missing")` 发出，`current_area_id` 保持不变，游戏不崩溃。

- **AC8 — 权重过滤按 unlock_wave**：**GIVEN** 风歌草原 enemy_pool 且 `current_wave = 1`，**WHEN** 波次系统请求敌人池，**THEN** 仅 `slime`（unlock_wave=1）可用——其他三种被过滤。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 区域切换时是否需要完整的加载画面（loading screen），还是即时切换？MVP 单区域无需切换，但 Vertical Slice 时若区域资产量大（TileMap + 背景 + BGM），可能需要 ~0.5-1.0s 加载时间。 | 否——MVP 单区域无需切换 | Vertical Slice 设计熔岩深渊时根据实际加载时间决定 |
| 2 | 区域是否支持非线性选择——如"击败 Boss 后玩家从 2 条路线中选择"？当前 `next_area_id` 为单一引用。若需分支，可改为 `next_area_options: Array[String]`。 | 否——MVP 线性 | Vertical Slice 阶段若需要玩家路线选择则扩展 |
| 3 | Boss 波是否总是在最后一波（`wave = total_waves`），还是可以配置为中间波？当前设计假设 Boss 波在最后。若 Boss 出现在第 3 波（5 波区域中），波次系统和区域系统的协调需要调整。 | 否——MVP Boss 在最后一波 | 波次系统 GDD 中协调确认 |
| 4 | `ambient_particle` 和视觉效果的性能预算？花粉粒子在 10-15 个同时屏幕内是低开销的，但熔岩深渊的"火山灰 + 火焰粒子"组合可能更密集。 | 否——MVP 风歌草原粒子简单 | 熔岩深渊区域设计时评估并设定性能预算 |
