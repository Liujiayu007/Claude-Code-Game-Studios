# Systems Index: Shapeshift Survivor

> **Status**: Draft
> **Created**: 2026-05-24
> **Last Updated**: 2026-05-24
> **Source Concept**: design/gdd/game-concept.md
> **Review Mode**: lean （所有 Gate 跳过）

---

## Overview

Shapeshift Survivor 的系统架构服务于一个核心的"蓄能→爆发"循环：玩家在异世界艾瑟兰中移动和自动攻击敌人，击杀敌人收集形态点数，点数满后变身为三种怪物形态之一（兽/龙/泰坦），在定时形态中碾压敌人，然后回到脆弱的人类形态重新蓄能。

21 个系统按依赖深度组织为 5 层。游戏的独特复杂度在于变身系统——它不是一个"属性 buff"，而是完全替换玩家的攻击模式、视觉外观和碰撞体，同时与吸收系统、变异系统和区域系统紧密耦合。两个最关键的系统是**变身系统**（支柱 1：爆发变身）和**变异系统**（支柱 2：有意义的选择）——其余所有系统为它们提供支撑。

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | 数据配置系统 (Data Config) | Foundation | MVP | Designed | design/gdd/data-config.md | — |
| 2 | 游戏状态管理 (Game State Manager) | Foundation | MVP | Designed | design/gdd/game-state-manager.md | — |
| 3 | 输入系统 (Input System) | Foundation | MVP | Designed | design/gdd/input-system.md | — |
| 4 | 玩家系统 (Player System) | Core | MVP | Designed | design/gdd/player-system.md | 1, 2, 3 |
| 5 | 敌人系统 (Enemy System) | Core | MVP | Designed | design/gdd/enemy-system.md | 1, 2 |
| 6 | 吸收系统 (Absorption System) | Core | MVP | Designed | design/gdd/absorption-system.md | 1, 4, 5 |
| 7 | 变身系统 (Transformation System) | Core | MVP | Designed | design/gdd/transformation-system.md | 1, 2, 4, 6 |
| 8 | 波次系统 (Wave System) | Core | MVP | Designed | design/gdd/wave-system.md | 1, 5, 9 |
| 9 | 区域系统 (Area System) | Core | MVP | Designed | design/gdd/area-system.md | 1, 2 |
| 10 | HUD/UI 系统 (HUD/UI System) | Presentation | MVP | Designed | design/gdd/hud-ui-system.md | 4, 7, 8, 11 |
| 11 | 视觉特效系统 (VFX System) | Presentation | MVP | Designed | design/gdd/vfx-system.md | 2, 4, 7 |
| 12 | 音频系统 (Audio System) | Presentation | MVP | Designed | design/gdd/audio-system.md | 2, 4, 7, 8 |
| 13 | 变异系统 (Mutation System) | Feature | Vertical Slice | Not Started | — | 1, 7 |
| 14 | Boss 系统 (Boss System) | Feature | Vertical Slice | Not Started | — | 5, 8, 11 |
| 15 | 形态解锁系统 (Form Unlock System) | Feature | Vertical Slice | Not Started | — | 14, 11 |
| 16 | 难度系统 (Difficulty System) | Feature | Vertical Slice | Not Started | — | 1, 5, 8 |
| 17 | 对局管理系统 (Run Manager) | Feature | Vertical Slice | Not Started | — | 2, 4, 8, 11 |
| 18 | 存档系统 (Save System) | Foundation | Vertical Slice | Not Started | — | — |
| 19 | 设置系统 (Settings System) | Polish | Vertical Slice | Not Started | — | 11, 12, 3 |
| 20 | 新手引导系统 (Tutorial System) | Polish | Full Vision | Not Started | — | 4, 6, 7, 10, 13 |
| 21 | 对局总结系统 (Run Summary) | Polish | Full Vision | Not Started | — | 16, 4, 13 |

---

## Categories

| Category | Description | Systems |
|----------|-------------|---------|
| **Foundation** | Zero-dependency infrastructure — must be stable before anything else | 数据配置、游戏状态管理、输入、存档 |
| **Core** | Drive the 30-second gameplay loop | 玩家、敌人、吸收、变身、波次、区域 |
| **Feature** | Complete the full session experience | 变异、Boss、形态解锁、难度、对局管理 |
| **Presentation** | Visual and audio feedback layers | HUD/UI、VFX、音频 |
| **Polish** | Smoothness, accessibility, first-time experience | 设置、新手引导、对局总结 |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Count |
|------|------------|------------------|-------|
| **MVP** | 30 秒核心循环可玩——风歌草原 1-5 波 + 1 个形态 + 能变身 + 能死 | First playable prototype | 12 |
| **Vertical Slice** | 风歌草原完整体验——加上升级选择、Boss、形态解锁、难度、存档 | Vertical slice / demo | 7 |
| **Full Vision** | 三大区域 + 新手引导 + 对局总结 | Beta / Release | 2 |

---

## Dependency Map

### Foundation Layer (zero dependencies)

1. **数据配置系统** — 所有可调数值的单一真相源。所有其他系统依赖它读取配置，因此必须第一个设计并锁定接口
2. **游戏状态管理** — 8 状态机（探索/蓄能/变身/狂暴/冷却/升级/Boss/死亡）。多数系统需要根据当前状态切换行为
3. **输入系统** — 键盘/手柄映射。玩家系统的直接前置依赖
4. **存档系统** — 独立的持久化层，仅在 Vertical Slice 阶段需要。零依赖，可平行设计

### Core Layer (depends on Foundation)

5. **玩家系统** — depends on: 1, 2, 3。移动 + 属性(HP/ATK/SPD) + 自动攻击 + 碰撞
6. **敌人系统** — depends on: 1, 2。类型定义 + AI + 属性 + 掉落生成
7. **吸收系统** — depends on: 1, 4(玩家), 5(敌人)。击杀→掉落形态点数→拾取→填充计量表
8. **变身系统** — depends on: 1, 2, 4(玩家), 6(吸收)。计量表满→激活形态切换→持续/冷却→恢复人形。**支柱 1 的核心载体**
9. **区域系统** — depends on: 1, 2。定义三大区域的环境/敌人表/视觉参数
10. **波次系统** — depends on: 1, 5(敌人), 9(区域)。控制敌人波次生成(数量/类型/密度递增)

### Feature Layer (depends on Core)

11. **变异系统** — depends on: 1, 7(变身)。波次间 3-4 选 1 升级。**支柱 2 的核心载体**
12. **Boss 系统** — depends on: 5(敌人), 8(波次), 9(区域)。Boss AI/多阶段/登场/死亡
13. **形态解锁系统** — depends on: 12(Boss), 9(区域)。击败 Boss→永久解锁形态
14. **难度系统** — depends on: 1, 5(敌人), 8(波次)。难度等级→敌人密度/血量/伤害倍率
15. **对局管理系统** — depends on: 2, 4(玩家), 8(波次), 9(区域)。单次对局生命周期

### Presentation Layer (depends on gameplay systems)

16. **HUD/UI 系统** — depends on: 4(玩家 HP/形态), 7(变身计量表), 8(波次显示), 11(变异升级界面)
17. **视觉特效系统** — depends on: 2, 4(玩家), 7(变身爆发特效), 12(Boss 特效)
18. **音频系统** — depends on: 2, 4(玩家), 7(变身音效), 8(波次提示)

### Polish Layer (depends on everything)

19. **设置系统** — depends on: 16(VFX 开关), 17(音量), 3(输入绑定)
20. **新手引导系统** — depends on: 4, 6, 7, 10, 13(变异)
21. **对局总结系统** — depends on: 15(对局管理), 4, 13(变异)

---

## Recommended Design Order

| Order | System | Priority | Layer | Est. Effort | Rationale |
|-------|--------|----------|-------|-------------|-----------|
| 1 | 数据配置系统 | MVP | Foundation | S | 瓶颈——所有其他系统的前置依赖 |
| 2 | 游戏状态管理 | MVP | Foundation | S | 瓶颈——驱动 8 个状态下的所有系统行为 |
| 3 | 输入系统 | MVP | Foundation | S | 玩家系统的直接前置 |
| 4 | 玩家系统 | MVP | Core | M | 30s 循环的起点——吸收/变身/UI/VFX 全部依赖它 |
| 5 | 敌人系统 | MVP | Core | M | 30s 循环的对立面——吸收和波次依赖它 |
| 6 | 吸收系统 | MVP | Core | S | 连接"击杀"与"变身"的桥梁 |
| 7 | 变身系统 | MVP | Core | L | **支柱 1 核心**——全游戏最复杂的系统，3 形态+持续/冷却 |
| 8 | 区域系统 | MVP | Core | M | 定义 MVP 区域（仅风歌草原）+ 为后续 2 区域留好接口 |
| 9 | 波次系统 | MVP | Core | M | 与区域系统有事件解耦的循环依赖，需协调设计 |
| 10 | HUD/UI 系统 | MVP | Presentation | M | 战斗 HUD 最低实现（HP 条+形态计量表+波次显示） |
| 11 | 视觉特效系统 | MVP | Presentation | M | 变身爆发闪光——支柱 1 的视觉最低兑现 |
| 12 | 音频系统 | MVP | Presentation | M | 蓄能渐强音+变身爆发音——支柱 1 的听觉维度 |
| 13 | 变异系统 | Vertical Slice | Feature | L | **支柱 2 核心**——3 形态 × 多分支树 = 大量设计内容 |
| 14 | Boss 系统 | Vertical Slice | Feature | L | Boss AI + 多阶段 + 双层视觉结构 |
| 15 | 形态解锁系统 | Vertical Slice | Feature | S | 连接 Boss 击败 → 永久解锁 |
| 16 | 难度系统 | Vertical Slice | Feature | S | 数值倍率表设计 |
| 17 | 对局管理系统 | Vertical Slice | Feature | S | 对局生命周期 + 暂停菜单 |
| 18 | 存档系统 | Vertical Slice | Foundation | S | 独立的持久化层 |
| 19 | 设置系统 | Vertical Slice | Polish | S | 特效开关+音量+输入 |
| 20 | 新手引导系统 | Full Vision | Polish | M | 首次用户体验设计 |
| 21 | 对局总结系统 | Full Vision | Polish | S | 统计画面 + "再来一局" |

> **Effort estimates**: S = 1 session, M = 2-3 sessions, L = 4+ sessions.
> A "session" is one focused design conversation producing a complete GDD with all 8 required sections.

---

## Circular Dependencies

- **区域系统 ↔ 波次系统**: 波次系统需要区域系统提供当前区域的敌人类型表，区域系统需要波次系统告知波次进度以触发区域切换。**Resolution**: 通过事件总线解耦——区域系统暴露 `current_area_config` 作为只读数据接口，波次系统读取；区域系统订阅波次系统的 `wave_cleared` 事件，波次系统不持有区域系统的引用。两者应在同一阶段并行设计以对齐接口。

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| **变身系统** | Design + Technical | 全游戏最复杂的系统——3 个形态各有独立攻击模式/碰撞体/视觉标识，切换时需替换玩家节点的多个组件。持续时间/冷却时间的数值平衡直接影响游戏手感 | 原型已初步验证（shapeshift-concept）。GDD 必须精确定义形态切换的 Godot 节点替换流程和状态转换 |
| **变异系统** | Design + Scope | 3 形态 × 多分支树 = 大量变异效果需要设计。如果每个形态有 6-8 个变异，总计 18-24 个升级选项——超出 solo 开发的可维护范围 | MVP 仅需 1 形态的变异树（简化验证），Vertical Slice 扩展至 3 形态。每个形态初期仅设计 4-5 个变异 |
| **波次系统** | Design | 敌人密度/类型/波次间隔的数值曲线决定核心节奏——太稀疏=无聊，太密集=无法操作。且与区域系统有循环依赖 | 参考 Vampire Survivors 的波次曲线作为基线，提供可调参数 |
| **视觉特效系统** | Scope | 艺术圣经定义了 8 个状态 × 每个状态多种特效的详细规范。MVP 阶段可能超出美术产能 | MVP 仅实现变身爆发的 4 帧硬切闪光+受击白闪。其余特效在 Vertical Slice 阶段追加 |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 21 |
| Design docs started | 12 |
| Design docs reviewed | 0 |
| Design docs approved | 0 |
| MVP systems designed | 12 / 12 |
| Vertical Slice systems designed | 0 / 7 |

---

## Next Steps

- [ ] Design MVP-tier systems in order: start with `/design-system 数据配置系统`
- [ ] Run `/design-review` on each completed GDD
- [ ] Run `/gate-check pre-production` when all MVP GDDs are complete
- [ ] Validate 变身系统 (highest-risk MVP system) with `/prototype` if design uncertainties remain
- [ ] Use `/map-systems next` to always pick the highest-priority undesigned system
