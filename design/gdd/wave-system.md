# Wave System — 波次系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 3 (Paced Mastery)

## Overview

波次系统（Wave System）是 Shapeshift Survivor 中控制战斗节奏的核心系统。它决定每一波次何时开始、生成多少敌人、以何种密度和组成出现、以及波次何时判定为"清除"。波次系统驱动 30 秒循环中的"压力→释放"潮汐感——敌群涌入时压力攀升，波次清除后短暂喘息，下一波开始前玩家利用间隙收集残留点数和调整位置。

**技术骨架**：波次系统从区域系统查询 `enemy_pool` 和 `total_waves`，从敌人系统调用 `spawn_enemy(config, position)` 生成敌人实例。波次参数（每波敌人数量、生成间隔、密度曲线）由 `WaveConfig` Resource 定义（存储在 `assets/config/waves/`）。波次系统订阅 GSM 的 `state_changed`——仅在 EXPLORATION 和 CHARGING 状态下运行波次逻辑，在 BOSS/UPGRADE/DEATH 状态下暂停生成。波次清除时发出 `wave_cleared` 信号，最终波清除时发出 `all_waves_cleared`。

**玩家体验**：玩家不直接操作波次系统，但波次系统**定义**了玩家的每一次心跳加速。第一波：零星几只史莱姆——玩家学习基本走位和攻击节奏。第三波：史莱姆 + 酸液射手 + 冲锋者混合涌入——玩家被迫优先击杀远程、躲避冲锋。第五波：精英巨型史莱姆出现——压力达到顶点，变身时刻到了。波次之间的短暂间隙（2-3 秒）给玩家喘息和收集的空间——这是"蓄能→爆发"公式中"蓄能"阶段的微观潮汐。

**没有这个系统会失去什么**：敌人要么持续不断涌入（无节奏，玩家疲劳），要么随机出现（无可预测性，策略无意义）。波次系统提供了结构——它让每一波成为一个可感知的"回合"，让玩家在波次清除时获得"我撑过了这一波"的满足感，让 Boss 波成为玩家期待（或恐惧）的已知事件。

## Player Fantasy

波次系统的幻想是**节奏**。玩家可能永远不会说"波次系统真棒"，但他们会说"这游戏的节奏真好"——这就是波次系统在工作。

> **"我被包围了——快撑不住了——最后一击！全清！……呼，还剩 3 秒，赶紧捡点数。"**

波次系统的幻想是**潮汐**：压力涌来 → 达到顶点 → 释放 → 短暂平静 → 下一波。这个循环以两层嵌套运行：

**微观潮汐（波内）**：一波之中，敌人在 5-8 秒内分批生成。第一批敌人出现时压力低——玩家从容击杀、收集点数。随着更多批次加入，屏幕上的敌人密度累积，压力递增。最后一批出现时玩家可能被迫变身——或者靠走位硬撑。整波清除的那一刻——音频提示 + HUD 显示"波次清除"——是微观层面的释放。

**宏观潮汐（波间→Boss）**：波次 1-4 是蓄能阶段——敌人密度和类型逐步升级，玩家在"击杀→蓄能→变身→冷却"的循环中构建节奏。波次 5（Boss 波）是释放——整个区域的压力积累在此达到顶点。Boss 击败后，比普通波间更长的间隙（3-5 秒）给予玩家真正的成就感。

**波次系统直接支撑的支柱**：
- **Pillar 3（节奏掌控）**: 波次系统是"节奏"二字在代码中的化身。波次的密度曲线、生成间隔、波间停顿——这些都是设计师调节"压力何时来、压力何时去"的直接工具。玩家通过变身时机和走位来掌控节奏，而波次系统定义了节奏的底层节拍。

**参考游戏中的类似感觉**：
- **Vampire Survivors 的波次节奏**——敌人密度随波次递增，Boss 在固定波次出现。玩家在波次间隙中感到"我变强了"的对比。我们的波次系统提供同样的对比感，但压力来源是变身时机而非武器升级。
- **Left 4 Dead 的 Director AI**——生成系统根据玩家状态动态调整压力。我们的 MVP 波次是固定配置的（非动态），但保留动态调整的接口用于 Vertical Slice 的难度系统。

## Detailed Design

### Core Rules

**Rule 1: WaveConfig 定义波次参数**

波次参数存储在 `WaveConfig` Resource 中（`assets/config/waves/`）。风歌草原使用默认 `WaveConfig`。每个区域可覆盖独立的波次参数。

**Rule 2: 波次序列——current_wave 从 1 到 total_waves**

对局开始时 `current_wave = 1`。每波清除后 `current_wave += 1`。当 `current_wave > total_waves` 时发出 `all_waves_cleared`。波次总数由区域系统提供（`AreaConfig.total_waves`）。

**Rule 3: 分批生成——spawn_batch_size + batch_interval**

每波敌人不一次性全部生成——分批次投入。每批次 `spawn_batch_size` 个敌人，间隔 `batch_interval` 秒。总批次 = `total_enemies / spawn_batch_size`（向上取整）。分批次的好处：(a) 减轻单帧性能压力，(b) 创造"敌人持续涌入"的潮汐感。

**Rule 4: 波间暂停——inter_wave_pause**

波次清除后，启动 `inter_wave_timer`（默认 3.0s）。在暂停期间：不生成新敌人、已生成敌人继续活跃。计时器到期后开始下一波。Boss 波前的暂停延长至 5.0s（给玩家准备时间）。

**Rule 5: 生成位置——屏幕外随机边缘**

敌人在玩家视野外的屏幕边缘生成。生成位置 = 玩家位置 + 屏幕对角线方向偏移 ± 随机角度：`spawn_pos = player_pos + (screen_diagonal * random_direction)`，其中 `random_direction` 为随机单位向量，确保生成点距玩家至少 `min_spawn_distance`（默认 150px，由敌人系统强制执行）。

**Rule 6: 波次清除条件**

当 `spawned_count >= total_enemies`（该波所有敌人生成完毕）且 `active_enemies_in_wave == 0`（全部死亡），波次判定为清除。已生成但未死亡的敌人不计入——它们必须被击杀。

**Rule 7: Boss 波——最后一波特殊处理**

当 `current_wave == total_waves` 时，不生成普通敌人——触发 Boss 波。波次系统发出 `boss_wave_started` 信号，Boss 系统响应以生成区域 Boss。Boss 波不适用分批生成逻辑。

**Rule 8: GSM 状态感知**

波次生成仅在 `GSM.current_state` 为 EXPLORATION 或 CHARGING 时运行。UPGRADE/DEATH 状态下 `time_scale = 0` 自动暂停所有计时器。BOSS 状态下不生成普通敌人。

### Wave Structure（MVP — 风歌草原）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `total_waves` | 5 | 来自 AreaConfig（区域系统提供） |
| `enemies_per_wave` | `[8, 12, 18, 25, boss]` | 每波的敌人总数。第 5 波为 Boss |
| `spawn_batch_size` | 3 | 每批生成的敌人数量 |
| `batch_interval` | 1.5s | 批次之间的间隔 |
| `inter_wave_pause` | 3.0s | 普通波间暂停 |
| `boss_wave_pause` | 5.0s | Boss 波前暂停 |

**波次进度表**：

| 波次 | 敌人总数 | 批次 | 敌人池 | 压力曲线 |
|------|---------|------|--------|---------|
| 1 | 8 | 3 批 (3+3+2) | 仅 slime | 低——教学波，单敌人类型 |
| 2 | 12 | 4 批 (3×4) | slime + slime_ranged | 中低——引入远程 |
| 3 | 18 | 6 批 (3×6) | slime + ranged + charger | 中——引入冲锋者，三种类型混合 |
| 4 | 25 | 9 批 (3×8 + 1) | slime + ranged + charger + elite | 高——引入精英，最高密度 |
| 5 | Boss | — | giant_slime_king | 顶点——Boss 战 |

每波的具体敌人组成由区域系统的 `enemy_pool` 权重随机决定——波次系统选择敌人类型时调用 F.1 加权随机公式（见区域系统 GDD）。

### Interactions with Other Systems

| 系统 | 方向 | 交互内容 |
|------|------|---------|
| 数据配置系统 | 查询 | 加载 `WaveConfig` Resource——波次参数 |
| 区域系统 | 查询 | `current_area_config.enemy_pool`（敌人类型+权重）、`total_waves`——决定生成内容和波次总数 |
| 敌人系统 | 调用 | `spawn_enemy(config, position)`——生成敌人实例；查询 `active_enemies`——判断波次清除 |
| 游戏状态管理 | 订阅 | `state_changed`——EXPLORATION/CHARGING 状态下运行波次 |
| Boss 系统 | 触发 | `boss_wave_started` 信号——Boss 系统生成区域 Boss |
| HUD/UI 系统 | 暴露 | `current_wave`、`total_waves`、`enemies_remaining`——HUD 显示波次进度 |
| VFX/音频系统 | 触发 | `wave_cleared`、`boss_wave_started` 信号——波次提示特效和音效 |

## Formulas

### F.1 Enemies Per Wave Calculation

```
enemies_in_wave = enemies_per_wave[current_wave - 1]
// MVP: [8, 12, 18, 25, boss] → wave 1=8, wave 2=12, etc.
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| enemies_per_wave | Array[int] | [1–100 per entry] | 每波敌人总数的预设数组 |
| current_wave | int | 1–total_waves | 当前波次编号 |

**Example**: 风歌草原波次 3 → `enemies_in_wave = 18`。

### F.2 Batch Count

```
total_batches = ceil(enemies_in_wave / spawn_batch_size)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| enemies_in_wave | int | 1–100 | 该波敌人总数 |
| spawn_batch_size | int | 1–10 | 每批生成数 |
| total_batches | int | 1–34 | 该波的总批次数 |

**Example**: 波次 4 有 25 个敌人，batch_size=3 → `ceil(25/3) = 9` 批（8 批 × 3 + 最后 1 批 × 1）。

### F.3 Wave Total Duration (Approximate)

```
wave_duration ≈ total_batches * batch_interval
```

风歌草原波次 3: `6 批 × 1.5s = 9s`。加上波间暂停 3s = 完整一波周期约 12s。

### F.4 Spawn Position

```
direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
spawn_pos = player_pos + direction * (screen_diagonal / 2 + randf_range(0, 100))
```

确保生成在屏幕外但足够近——敌人生成后能迅速进入战场。

## Edge Cases

- **如果玩家在波间暂停期间死亡**：GSM 进入 DEATH → time_scale=0，inter_wave_timer 暂停。对局结束，波次状态随场景清理一并销毁。

- **如果最后一波 Boss 被击败但新区域不存在**：发出 `all_waves_cleared` → GSM 进入胜利状态（或直接对局总结）。

- **如果 active_enemies_in_wave 变为 0 但 spawned_count < total_enemies**：波次未清除——后续批次仍在等待生成。不提前清除。

- **如果所有敌人生成完毕但 1 个敌人卡在场景边界外**：波次永远不清除。敌人系统需检测边界外敌人并自动销毁（见 enemy-system.md Edge Cases）。

- **如果在 BOSS 状态下 current_wave 意外递增**：波次计数器仅在波次清除时递增。BOSS 状态下不运行波次逻辑——计数器不变。

- **如果 enemies_per_wave 数组长度 < total_waves**：数组不够长时使用最后一个值。如 [8,12,18] 但 total_waves=5，则波 4 和波 5 均沿用 18。

- **如果批量生成时玩家切换到 UPGRADE**：batch_timer 暂停（time_scale=0），剩余批次保留。玩家退出升级后从暂停点继续生成。

## Dependencies

### 上游依赖

| 系统 | 依赖内容 |
|------|---------|
| 数据配置系统 | `WaveConfig` Resource——波次参数（enemies_per_wave、batch_size、batch_interval 等） |
| 区域系统 | `current_area_config.enemy_pool`、`total_waves`——敌人表和波次总数 |
| 敌人系统 | `spawn_enemy(config, position)` 接口、`active_enemies` 查询 |
| 游戏状态管理 | `GSM.current_state`、`time_scale`——状态感知和计时器暂停 |

### 下游依赖方

| 系统 | 依赖内容 |
|------|---------|
| Boss 系统 | `boss_wave_started` 信号——触发 Boss 生成 |
| HUD/UI 系统 | `current_wave`、`total_waves`、`enemies_remaining`——波次进度显示 |
| VFX 系统 | `wave_cleared`、`wave_started` 信号——波次提示特效 |
| 音频系统 | `wave_cleared`、`boss_wave_incoming` 信号——波次提示音效 |
| 对局管理系统 | `all_waves_cleared` 信号——区域通关判断 |
| 难度系统（Vertical Slice） | WaveConfig 参数可被难度等级修改 |

### 接口契约

1. `current_wave: int` (只读) — 当前波次编号
2. `total_waves: int` (只读) — 总波次数
3. `enemies_remaining: int` (只读) — 当前波次内剩余存活敌人
4. `wave_started(wave: int)` 信号
5. `wave_cleared(wave: int)` 信号
6. `boss_wave_started()` 信号
7. `all_waves_cleared()` 信号

## Tuning Knobs

| 参数 | 默认值 | 安全范围 | 玩法影响 |
|------|--------|---------|---------|
| `enemies_per_wave` | [8,12,18,25,boss] | [3–50 per wave] | 敌人总数。太少→无聊；太多→窒息 |
| `spawn_batch_size` | 3 | 1–10 | 每批数量。太大→单帧性能冲击+瞬间压力过高；太小→敌人"滴漏"感 |
| `batch_interval` | 1.5s | 0.5–5.0s | 批次间隔。太短→近乎一次性倾泻；太长→节奏拖沓 |
| `inter_wave_pause` | 3.0s | 1.0–10.0s | 波间喘息。太短→无休息感；太长→节奏断裂 |
| `boss_wave_pause` | 5.0s | 2.0–15.0s | Boss 波前准备。太短→措手不及；太长→等待无聊 |

**核心节奏杠杆**: `total_waves × (avg_batches × batch_interval + inter_wave_pause)` ≈ 完整区域时长。风歌草原: `4 × (avg 5.5 批 × 1.5s + 3s) + boss` ≈ `4 × 11.25s + boss` ≈ 45s + Boss 时长。

## Visual/Audio Requirements

波次系统不直接产生视觉或音频——它发出信号触发 VFX 和音频系统。以下定义波次事件需兑现的视听需求：

| 时机 | 需求 | 优先级 | 描述 |
|------|------|--------|------|
| `wave_started` | 波次开始提示 | MVP | 屏幕顶部显示"波次 [n]"文字（~1.5s 淡入淡出）。字体 16px，白色 |
| `wave_cleared` | 波次清除提示 | MVP | "波次清除!" 文字（~2s）+ 短促胜利音效（~0.5s 上升音阶） |
| `boss_wave_started` | Boss 登场 | Vertical Slice | 更强烈的提示——屏幕边缘变红/闪烁 + 低音轰鸣 + Boss 名称显示 |
| `all_waves_cleared` | 区域通关 | Vertical Slice | 区域通关音乐 + 区域名显示 + 过渡效果 |

## UI Requirements

| UI 元素 | 数据来源 | 优先级 | 描述 |
|---------|---------|--------|------|
| 波次进度 | `current_wave / total_waves` | MVP | HUD 顶部/角落显示"波次 [n]/[total]"——如"波次 3/5" |
| 剩余敌人 | `enemies_remaining` | MVP | 与波次进度并列或替代显示——如"剩余 12 敌人" |
| Boss 波警告 | `boss_wave_started` 信号 | MVP | Boss 波前显示警告文字 + Boss 名称 |

## Acceptance Criteria

- **AC1 — 波次按序列递增**：**GIVEN** 对局开始 `current_wave = 1`，**WHEN** 波 1 清除，**THEN** `current_wave = 2`，`wave_started(2)` 发出。

- **AC2 — 分批生成**：**GIVEN** 波次 1 的 `enemies_in_wave = 8` 且 `spawn_batch_size = 3`，**WHEN** 波次开始，**THEN** 分 3 批生成（前 2 批 × 3 + 最后 1 批 × 2），每批间隔 1.5s。

- **AC3 — 波次清除条件**：**GIVEN** 波次中所有敌人生成完毕（spawned_count = total）且 active_enemies = 0，**WHEN** 最后一帧检查，**THEN** `wave_cleared(1)` 发出。

- **AC4 — 波间暂停**：**GIVEN** 波次 1 清除，**WHEN** `wave_cleared` 发出，**THEN** 3.0s 内无新敌人生成，3.0s 后波次 2 自动开始。

- **AC5 — Boss 波触发**：**GIVEN** `current_wave = 5`（= total_waves）且波次 5 开始，**WHEN** 波次逻辑运行，**THEN** 不生成普通敌人，`boss_wave_started()` 发出。

- **AC6 — GSM 暂停波次**：**GIVEN** GSM 状态 = UPGRADE（time_scale=0），**WHEN** batch_timer 正在运行，**THEN** timer 暂停，不生成新敌人。

- **AC7 — 敌人池权重查询**：**GIVEN** 波次 1 开始，**WHEN** 波次系统查询 `area_config.enemy_pool`，**THEN** 仅获取 unlock_wave ≤ 1 的敌人（仅 slime 可用）。

- **AC8 — 通关触发**：**GIVEN** 最后一波（Boss）清除且区域 `next_area_id = null`，**WHEN** Boss 死亡，**THEN** `all_waves_cleared()` 发出。

## Open Questions

| # | 问题 | 阻塞 | 预计解决 |
|---|------|------|---------|
| 1 | 是否需要"无限波次"模式——Boss 击败后区域继续生成波次？对无尽模式或刷分玩法有价值。 | 否——MVP 5 波后通关 | Vertical Slice 评估 |
| 2 | 波次进度是否应与 GSM 状态耦合更紧密——如 DEATH 状态自动重置 `current_wave = 1`？当前设计中死亡后对局结束，波次状态随对局管理系统重置。 | 否——对局管理系统处理重置 | 对局管理系统 GDD 时确认 |
| 3 | 每波的敌人类型分布是否需要独立覆盖——如波次 3 强制"charger 占比 50%"而非纯权重随机？当前设计完全依赖区域系统权重。 | 否——MVP 权重足够 | 原型测试波次多样性后决定 |
