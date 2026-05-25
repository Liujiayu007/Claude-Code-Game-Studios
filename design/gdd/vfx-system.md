# VFX System — 视觉特效系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation) + Pillar 3 (Paced Mastery)

## Overview

VFX 系统（Visual Effects System）是 Shapeshift Survivor 的视觉反馈层——它将游戏事件（变身、受击、攻击命中、波次切换、死亡）转化为屏幕上的像素化视觉效果，让玩家在每一个重要时刻感受到游戏的"果汁感"（game juice）。VFX 系统不创造游戏逻辑——它是纯粹的视觉输出层，将其他系统发出的信号和状态变化转化为玩家眼睛能感知的光、色、粒子、闪烁。

**技术骨架**：VFX 系统是订阅型消费者——它订阅 GSM 的 `state_changed` 信号、玩家系统的 `player_hit`/`damage_dealt`/`player_died` 信号、变身系统的 6 个转换信号、以及波次系统的 4 个事件信号。每种信号/状态转换触发对应的视觉特效，系统管理粒子池（object pooling）以控制性能，所有特效渲染在独立 CanvasLayer 上（层级高于游戏世界）。VFX 系统遵循艺术圣经的严格视觉约束：禁止后处理（无泛光/色差/景深）、像素化粒子（方形粒子、低分辨率精灵、Nearest-neighbor 缩放）、形态几何母题统一（Beast=圆形弧形、Dragon=三角形）、无补间动画（硬切帧）。

**玩家体验**：VFX 系统是"果汁感"的守护者——玩家不是在看特效，特效是在告诉玩家发生了什么。变身瞬间的全屏闪光 + 像素撕裂 = "你变身了!"。受击时的角色白闪 + 屏幕边缘红色 = "你受伤了!"。狂暴激活时的形态色光环叠加 = "现在更猛了!"。形态褪去时的像素逐行崩解 = "变身结束了，你又脆弱了"。每个视觉信号都是一种无需文字的语言——玩家在 50ms 内通过颜色和形状就理解了当前状态。优秀的 VFX 让游戏感觉"有重量"——攻击有命中感、受击有威胁感、变身有爆发感。

**没有这个系统会失去什么**：所有的"果汁感"。Shapeshift Survivor 变成一个安静的、无反馈的数据处理系统——玩家攻击敌人，敌人 HP 减少，但屏幕上什么都看不到；玩家变身，属性切换，但没有任何视觉信号确认。Pillar 1（爆发变身）如果没有 VFX 的全屏闪光和 4 帧撕裂变身，就只剩数值变化——"攻击力 +500%"不能满足"我变成了怪物"的 fantasy。VFX 系统将设计师定义的节奏转化为玩家能用眼睛感受到的情感弧线。

## Player Fantasy

VFX 系统的幻想是**果汁感**——玩家可能不会用这个词，但他们会感受到"这游戏打起来真爽"。每一次攻击命中都有像素飞溅、每一次受击都有屏幕警告、每一次变身都像是"屏幕炸了"。

> **"每一帧都在告诉我：你做到了。"**

VFX 不是装饰——它是游戏与玩家之间的视觉语言。在这门语言中：橙色圆形粒子 = "你的野兽形态在撕裂敌人"；紫色三角形粒子 = "你的龙息正在焚烧前方"；全屏白闪 = "变身了，现在你不一样了"；角色白闪 = "你受伤了，快走位"；像素逐行崩解 = "变身结束了，你又脆弱了"。

**VFX 的情感节奏**：

1. **蓄能阶段——堆积感**：形态计量表在填充，屏幕边缘的形态色微光越来越亮。这不是一个进度条——这是"力量在积聚"的视觉承诺。粒子在角色周围以低频率出现（每 2-3 秒几颗），像是在试探——"快了吗？快了。"

2. **变身瞬间——爆发感**：这是全游戏最重要的单帧视觉事件。全屏形态色闪光（Beast=橙红，Dragon=紫红），0.3s 白帧→0.2s 剪影黑帧→形态色淡出。角色精灵在 4 帧内从人形撕裂为怪物形态——像素块逐行替换，不是平滑过渡，是"撕裂旧皮露出新体"。形态色粒子从角色位置向四周爆发。玩家不需要 HUD 提示——光这一下就知道"我变身了"。

3. **变身战斗——碾压感**：每次攻击命中都产生形态几何母题的粒子飞溅。Beast 的近战圆形 AOE = 每次攻击在 96px 半径内爆发一圈橙色弧形粒子碎片。Dragon 的锥形吐息 = 每次攻击向 60° 锥形前方喷射紫红三角形粒子流。狂暴激活时——叠加第二层视觉：Beast 的红色光环、Dragon 的火焰翅膀粒子。屏幕上的粒子密度达到顶点——"我在毁灭一切"。

4. **受击——威胁感**：玩家受击时角色白闪 1-2 帧 + 屏幕边缘红色渐变。不是"你受了 5 点伤害"的数据提示——是"危险！再挨一下就死了！"的本能警告。HP 低时（<30%）屏幕边缘红色持续呼吸脉冲——即使玩家不看 HP 条，余光也能感知到危险。

5. **冷却/褪去——失落感**：变身结束时形态精灵逆向崩解——像素逐行从怪物形态剥离，露出下方的人类形态。形态色粒子从角色身上向外飘散——像是"力量在消散"。这创造了一种微妙的失落感——"结束了。又要重新蓄能了。"这个失落感是下一次变身期待感的燃料。

**该系统直接支撑的游戏支柱**：

- **支柱 1（爆发变身）**：VFX 系统是 Pillar 1 的视觉引擎。变身瞬间的 4 帧撕裂 + 全屏闪光 + 粒子爆发——这三层视觉叠加确保了"变身 = 事件"。如果没有 VFX，变身只是属性替换——玩家不会感到"我变成了怪物"，只会感到"我的攻击力变了"。VFX 将数值的变化转化为眼睛能看到的现实。

- **支柱 3（节奏掌控）**：VFX 为每一个状态转换提供视觉标识——变身是爆发、受击是警告、冷却褪去是失落、死亡是崩解。这些视觉信号让玩家在不需要阅读任何文字或数字的情况下感知节奏——红色代表危险、橙色代表力量、灰色代表脆弱。VFX 是"节奏"的视觉语法。

**参考游戏中类似的感觉**：
- **Vampire Survivors** 的"低保真高密度"粒子美学——大量粗糙粒子在屏幕上飞舞，制造"我变得很强"的满足感。我们的 VFX 使用同样的低分辨率粒子哲学，但加上形态几何母题的纪律——粒子不是随机的，而是形态身份的延伸。
- **Nioh 2 的妖怪化瞬间**——全屏色调偏移 + 角色模型替换 + 妖怪粒子爆发。我们的"全屏形态色闪光 + 4 帧撕裂变身"是对这个瞬间的像素艺术翻译。
- **Hades 的受击反馈**——屏幕边缘红色脉动 + 角色白闪 + 击退。不需要看 HP 数字就知道自己受伤了。我们的受击 VFX 采用同样的"本能级"警告系统。

**"出问题时玩家会感受到什么"**：
- 当 VFX **正确**时，玩家感觉游戏"很 juicy"——虽然他们可能说不出为什么。攻击有重量、受击有威胁、变身有爆发。游戏世界感觉"活的、响应的"。
- 当 VFX **错误**时——粒子不出现、屏幕闪光是灰色的、受击没白闪、变身没有撕裂只有硬切——游戏感觉"死的、空洞的"。这不是一个可以被忽略的问题——VFX 的缺失直接削弱 Pillar 1 和 Pillar 3 的兑现能力。

## Detailed Design

### Core Rules

**Rule 1: 信号驱动的纯响应系统**

VFX 系统不主动发起任何视觉特效——它订阅上游系统的信号和 GSM 的状态转换，在收到通知时触发对应的视觉效果。VFX 系统不调用任何上游系统的逻辑方法——它是纯粹的视觉输出层。

**Rule 2: 分层渲染架构**

所有 VFX 元素使用 3 层 CanvasLayer 渲染（从下到上）：

| Layer | 名称 | 渲染内容 | 说明 |
|-------|------|---------|------|
| Layer 1 | World VFX | 攻击命中粒子、敌人死亡粒子、玩家移动尘埃 | 与游戏世界混合——粒子使用世界坐标 |
| Layer 2 | Screen VFX | 屏幕边缘发光、全屏闪光、HP 警告、波次提示 | 屏幕空间固定——不随摄像机移动 |
| Layer 3 | Overlay VFX | 变身撕裂覆盖、形态光环、死亡崩解覆盖 | 最高层级——覆盖所有其他渲染，包括 UI |

**Rule 3: 粒子池管理**

所有粒子使用 Godot 的 object pooling 模式——预分配粒子节点池，触发时从池中取出并配置（位置、方向、颜色、生命周期），粒子生命周期结束后回收至池中。每类粒子有独立的池大小：

| 粒子类型 | 池大小 | 单粒子最大生命周期 |
|---------|--------|-----------------|
| 攻击命中粒子 | 50 | 0.4s |
| 变身爆发粒子 | 80 | 0.8s |
| 形态光环粒子 | 30 | 持续（跟随形态持续时间） |
| 移动尘埃粒子 | 10 | 1.0s |
| 死亡崩解粒子 | 60 | 2.0s |
| 冷却飘散粒子 | 40 | 1.5s |

**Rule 4: 像素艺术严格约束**

所有 VFX 视觉必须符合艺术圣经的像素艺术约束：
- 禁止任何后处理特效（泛光、色差、景深、色调映射、运动模糊、镜头眩光）
- 粒子使用 2×2px 或 4×4px 方形精灵 + Nearest-neighbor 缩放
- 粒子精灵仅允许 90° 和 180° 旋转（保持像素对齐）
- 每帧状态调色板不超过 8 色（背景）+ 4 色（角色）
- 无补间动画——特效帧间使用硬切

**Rule 5: 形态几何母题统一**

每个形态的所有攻击 VFX 使用统一的几何母题（出自艺术圣经 Section 3）：

| 形态 | 几何母题 | 粒子形状 | 攻击 VFX 描述 |
|------|---------|---------|-------------|
| Beast（兽形态） | 圆形 + 弧形 | 3×1px 弧形碎片 | 周身环形撕裂——每次攻击在 96px 半径爆发橙色圆弧碎片 |
| Dragon（龙形态） | 三角形 | 4×4px 等边三角 | 前方锥形火焰——每次攻击向 60° 锥形喷射紫色三角粒子流 |

**Rule 6: 形态主题色统一**

每个形态的所有 VFX 使用统一的主题色（出自艺术圣经 Section 3）：

| 形态 | 主色 | Hex | 辅色 | 用途 |
|------|------|-----|------|------|
| Beast | 橙红 | `#FF6B35` | 深橙 `#CC5522` | 所有 Beast VFX——粒子、光环、屏幕闪光 |
| Dragon | 紫红 | `#C44B8B` | 深紫 `#883366` | 所有 Dragon VFX——粒子、光环、屏幕闪光 |

**Rule 7: 角色可读性保护**

VFX 粒子不得覆盖角色剪影的核心识别区域（出自艺术圣经）：角色最外层 1px 轮廓始终可见。VFX 粒子的渲染 Z-order 低于角色精灵——角色始终在粒子之上渲染。

**Rule 8: 性能约束**

- 屏幕同时可见粒子总数 ≤ 150（MVP 目标——Godot 4.6 GL Compatibility 渲染器）
- 全屏闪光使用 CanvasLayer 的 `modulate` 颜色叠加（不创建新节点）
- 屏幕边缘渐变使用单张预渲染 9-slice TextureRect（不需要每帧重绘）
- 粒子使用 `CpuParticles2D`（Godot 4.6 GL 兼容模式不支持 GPU 粒子）

### VFX Catalog

每个 VFX 条目定义：触发信号/条件、视觉规格、持续时间、优先级（用于同时触发多个 VFX 时的叠加规则）。

#### 1. 变身相关 VFX

**VFX-001: 变身爆发闪光**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)` |
| 视觉 | 全屏单色闪光：0.3s 形态色帧 → 0.2s 纯白帧 → 0.2s 黑色剪影帧 → 0.3s 淡出。Layer 2（Screen VFX）。CanvasLayer modulate 实现——不创建新节点 |
| 颜色 | Beast: `#FF6B35` / Dragon: `#C44B8B` |
| 持续时间 | 1.0s 总长 |
| 优先级 | 最高——覆盖所有其他 VFX |

**VFX-002: 变身像素撕裂**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)`（与 VFX-001 同时） |
| 视觉 | 角色精灵在 4 帧内从人形逐行替换为形态精灵——每帧替换约 25% 像素行，从角色底部向上推进。产生"旧皮撕裂、新体露出"的视觉。Layer 3（Overlay VFX） |
| 持续时间 | 4 帧（约 0.067s @ 60fps） |
| 优先级 | 最高 |

**VFX-003: 变身粒子爆发**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)`（与 VFX-001/002 同时） |
| 视觉 | 40 个形态几何母题粒子从角色位置向四面八方爆发。速度 200-400 px/s（随机），生命周期 0.5-0.8s，alpha 从 1.0 → 0.0。Layer 1（World VFX） |
| 粒子形状 | Beast: 3×1px 弧形碎片 / Dragon: 4×4px 三角形 |
| 持续时间 | 0.8s（粒子全部消失） |
| 优先级 | 高 |

**VFX-004: 变身期间形态光环**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)` |
| 视觉 | 角色周围 16px 半径内持续存在的微弱形态色光晕——alpha 0.15，不脉冲。提示"你仍在变身中"。Layer 1（World VFX） |
| 颜色 | 形态主题色 |
| 持续时间 | 整个 TRANSFORMATION 状态期间 |
| 优先级 | 低——背景层 |

**VFX-005: 形态褪去（变身→冷却）**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, COOLDOWN)` |
| 视觉 | 逆向像素撕裂——形态精灵从顶部向下逐行剥离为人类精灵（3 帧）。形态色粒子从角色身上向外飘散（20 个粒子，速度 100-200 px/s，alpha 0.6→0.0）。Layer 3 + Layer 1 |
| 持续时间 | 3 帧撕裂 + 1.0s 粒子飘散 |
| 优先级 | 高 |

#### 2. 狂暴相关 VFX

**VFX-006: 狂暴激活**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, BERSERK)` |
| 视觉 | 全屏短闪光（0.15s 形态色，比变身闪光更短更亮）+ 形态光环 alpha 从 0.15 跳升至 0.4 + 光环半径从 16px 扩展至 24px。Layer 2 + Layer 1 |
| 颜色 | 形态主题色（比 TRANSFORMATION 状态下更饱和） |
| 持续时间 | 0.15s 闪光 + 光环持续至 BERSERK 结束 |
| 优先级 | 高 |

**VFX-007: 狂暴光环叠加**

| 属性 | 值 |
|------|-----|
| 触发 | BERSERK 状态持续期间 |
| 视觉 | Beast 狂暴：红色光环（alpha 0.4，24px 半径，微弱脉冲周期 0.3s）。Dragon 狂暴：火焰翅膀粒子——角色两侧各 8-12px 的三角粒子群（5 个三角/侧），粒子在原地做 ±4px 随机抖动。Layer 1 |
| 持续时间 | 整个 BERSERK 状态期间 |
| 优先级 | 中 |

#### 3. 攻击 VFX

**VFX-008: Beast 圆形 AOE 撕裂**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `damage_dealt` 信号（当玩家处于 Beast TRANSFORMATION/BERSERK） |
| 视觉 | 以玩家位置为圆心、96px 半径的圆形爆发——15 个 3×1px 橙色弧形碎片从圆心向外扩散（速度 300-500 px/s），alpha 0.9→0.0，生命周期 0.3s。Layer 1 |
| 攻击间隔 | 0.3s（每次攻击触发一次） |
| 优先级 | 中 |

**VFX-009: Dragon 锥形火焰吐息**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `damage_dealt` 信号（当玩家处于 Dragon TRANSFORMATION/BERSERK） |
| 视觉 | 向玩家瞄准方向（最近敌人方向）60° 锥形喷射 12 个 4×4px 紫色三角粒子。粒子速度 250-450 px/s，alpha 0.8→0.0，生命周期 0.35s。Layer 1 |
| 攻击间隔 | 0.5s（每次攻击触发一次） |
| 优先级 | 中 |

**VFX-010: 人类形态攻击命中**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `damage_dealt` 信号（当玩家处于人类形态） |
| 视觉 | 被击中敌人位置出现 4 个 2×2px 白色方形粒子向 4 个对角方向飞出（速度 150 px/s），alpha 0.7→0.0，生命周期 0.2s。Layer 1 |
| 优先级 | 低 |

#### 4. 受击 VFX

**VFX-011: 玩家受击白闪**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `player_hit` 信号 |
| 视觉 | 角色精灵瞬间替换为全白剪影（1 帧 @60fps = ~0.017s）→ 立即恢复原精灵。仅角色——不影响背景和其他对象。Layer 3 |
| 持续时间 | 1 帧 |
| 优先级 | 高——确保玩家立即注意到受击 |

**VFX-012: 受击屏幕警告**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `player_hit` 信号（与 VFX-011 同时） |
| 视觉 | 屏幕四边短暂红色渐变闪现（alpha 0.15，0.1s fade in → immediate 0.3s fade out）。与 HUD 系统的持续低 HP 警告（HP ≤ 30%）不同——这是每次受击的独立"刺痛"信号。Layer 2 |
| 持续时间 | 0.4s |
| 优先级 | 中 |

**VFX-013: 持续低 HP 警告**

| 属性 | 值 |
|------|-----|
| 触发 | 每帧检查 `hp_current / hp_max <= 0.3` |
| 视觉 | 屏幕四边红色渐变持续存在——alpha 随 HP 降低线性增加：hp_ratio=0.3 → alpha=0.05，hp_ratio=0.15 → alpha=0.2。HP ≤ 0.15 时进入脉冲模式（alpha 0.2↔0.35，周期 0.5s）。Layer 2。使用预渲染 9-slice TextureRect——不每帧重绘 |
| 持续时间 | HP ≤ 30% 期间持续 |
| 优先级 | 中 |

#### 5. 死亡 VFX

**VFX-014: 死亡像素崩解**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, DEATH)` |
| 视觉 | 角色精灵从边缘像素开始逐帧崩解为 2×2px 碎片向外飘散。崩解速度：从外向内收缩，速度约 16px/s（以角色中心为原点）。碎片颜色继承角色精灵对应位置的像素颜色——崩解后碎片在 2.0s 内 alpha 1.0→0.0 并向外移动 30-60px。全屏色彩从正常向灰度过渡（0.5s 内饱和度降为 0）。Layer 3 + Layer 2 |
| 持续时间 | 2.0s（崩解完成 + 碎片消散） |
| 优先级 | 最高——覆盖一切 |

**VFX-015: 死亡背景灰度化**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, DEATH)`（与 VFX-014 同时） |
| 视觉 | 从屏幕边缘向中心灰度化收缩（速度 16px/s），最后到达角色位置。使用 CanvasLayer modulate——在独立的灰度化 Layer 上覆盖（saturation shader）。若不支持 shader，回退为半透明黑色覆盖层（alpha 0.4）。Layer 3 |
| 持续时间 | 约 2.0s 至完全灰度化 |
| 优先级 | 中 |

#### 6. 波次相关 VFX

**VFX-016: 波次开始提示**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `wave_started` 信号 |
| 视觉 | 屏幕顶部显示"波次 [n]"文字——白色像素字体，淡入 0.3s → 停留 1.0s → 淡出 0.2s。Layer 2。VFX 负责视觉渲染——HUD 系统提供位置锚点 |
| 持续时间 | 1.5s |
| 优先级 | 中 |

**VFX-017: 波次清除提示**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `wave_cleared` 信号 |
| 视觉 | "波次清除！"文字——黄色像素字体，淡入 0.3s → 停留 1.5s → 淡出 0.2s。Layer 2 |
| 持续时间 | 2.0s |
| 优先级 | 中 |

**VFX-018: Boss 波警告**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `boss_wave_started` 信号 |
| 视觉 | 屏幕边缘红色闪烁（alpha 0.2↔0.4，周期 0.3s，持续 2.0s）+ Boss 名称显示（大号红色像素字体，屏幕上部居中）。Layer 2 |
| 持续时间 | 2.0s 闪烁 + Boss 名称保持至 BOSS 状态结束 |
| 优先级 | 高——Boss 登场是重大事件 |

**VFX-019: 区域通关**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `all_waves_cleared` 信号 |
| 视觉 | 全屏金色闪光（0.2s）+ "区域通关!" 大号金色像素文字（屏幕居中，淡入 0.5s → 停留 2.0s）。Layer 2 |
| 持续时间 | 2.7s |
| 优先级 | 高——仅次于死亡和变身 |

#### 7. 蓄能相关 VFX

**VFX-020: 计量表边缘发光**

| 属性 | 值 |
|------|-----|
| 触发 | 吸收系统 `meter_current` 变化（每帧检查） |
| 视觉 | 当 `meter >= 80%` 时，屏幕四角出现形态主题色微光脉冲——alpha 0→0.1 线性增长（80%→100%）。Layer 2。不闪烁——缓慢呼吸（周期 0.8s）。当 `meter < 80%` 时不显示 |
| 颜色 | 当前激活形态的主题色 |
| 持续时间 | meter ≥ 80% 期间持续 |
| 优先级 | 低——不抢夺玩家注意力 |

#### 8. 通用 VFX

**VFX-021: 玩家移动像素尘埃**

| 属性 | 值 |
|------|-----|
| 触发 | 每 N 帧（约每 6 帧 @60fps，= 0.1s 间隔），当玩家在移动时 |
| 视觉 | 在玩家脚后位置生成 1-2 个 2×2px 灰色/棕色方形粒子，alpha 0.4 → 0.0，缓慢向上飘升（速度 20-40 px/s），生命周期 0.8-1.2s。Layer 1 |
| 持续时间 | 持续（玩家移动期间） |
| 优先级 | 最低——氛围层 |

**VFX-022: 敌人死亡粒子**

| 属性 | 值 |
|------|-----|
| 触发 | 敌人系统——敌人 HP 归零（预留接口） |
| 视觉 | 敌人位置生成 6-10 个 2×2px 粒子（随机颜色：敌人主色 + 白色 + 灰色），向外爆散（速度 100-200 px/s），alpha 0.7→0.0，生命周期 0.3-0.5s。Layer 1 |
| 持续时间 | 0.5s |
| 优先级 | 低 |

### Interactions with Other Systems

| 系统 | 方向 | 内容 |
|------|------|------|
| 游戏状态管理 | 订阅 | `state_changed` → 触发状态转换 VFX（变身爆发、狂暴激活、形态褪去、死亡崩解） |
| 玩家系统 | 订阅 | `player_hit` → VFX-011/012；`damage_dealt` → VFX-008/009/010；`player_died` → VFX-014/015 |
| 变身系统 | 订阅 | `transformation_started`/`expired` → VFX-001-005；`berserk_activated`/`expired` → VFX-006/007；`cooldown_complete` → 冷却结束提示 |
| 波次系统 | 订阅 | `wave_started` → VFX-016；`wave_cleared` → VFX-017；`boss_wave_started` → VFX-018；`all_waves_cleared` → VFX-019 |
| 吸收系统 | 查询 | `meter_current`（每帧） → VFX-020（计量表边缘发光） |
| 敌人系统 | 订阅 | 敌人死亡信号（预留） → VFX-022 |
| 音频系统 | 平行 | VFX 与音频系统响应同一 GSM 信号——同步视觉和听觉爆发时刻。VFX 不直接调用音频，但两者由同一信号驱动确保同步 |
| HUD/UI 系统 | 协调 | VFX 的 Layer 2（Screen VFX）与 HUD 共享屏幕空间。HUD 元素 Z-order 高于 VFX Layer 2——确保 UI 文字始终可读。低 HP 警告（VFX-013）的红色渐变在 HUD 元素下层 |

## Formulas

### F.1 Particle Velocity

```
v = v_base + randf_range(-v_variance, +v_variance)
position(t) = position(0) + v * direction * t
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| v_base | float | 100–500 px/s | 基础粒子速度（按特效类型不同） |
| v_variance | float | 50–150 px/s | 速度随机偏差——确保粒子自然感 |
| direction | Vector2 | 归一化 | 粒子发射方向 |
| t | float | 0–lifetime | 粒子已存在时间 |

**各特效类型的 v_base / v_variance**：

| 特效 | v_base | v_variance | lifetime |
|------|--------|-----------|----------|
| 变身爆发粒子 | 300 | 100 | 0.5–0.8s |
| Beast AOE 撕裂 | 400 | 100 | 0.3s |
| Dragon 锥形粒子 | 350 | 100 | 0.35s |
| 人类攻击命中 | 150 | 0 | 0.2s |
| 形态褪去飘散 | 150 | 50 | 1.0s |
| 移动尘埃 | 30 | 10 | 0.8–1.2s |
| 死亡崩解碎片 | 100 | 50 | 2.0s |
| 敌人死亡粒子 | 150 | 50 | 0.3–0.5s |

### F.2 Particle Alpha Decay

```
alpha(t) = alpha_start * clamp(1.0 - t / lifetime, 0.0, 1.0)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| alpha_start | float | 0.4–1.0 | 粒子初始透明度 |
| t | float | 0–lifetime | 粒子已存在时间 |
| lifetime | float | 0.2–2.0s | 粒子最大生命周期 |

所有粒子使用线性 alpha 衰减——保持一致性和性能。不使用缓动曲线（与像素艺术的硬切哲学一致）。

### F.3 Screen Flash Modulation

```
flash_alpha(t) = sequence(t):
  t in [0.00, 0.30]: form_color, alpha = 1.0       // 形态色帧
  t in [0.30, 0.50]: white (#FFFFFF), alpha = 1.0   // 纯白帧
  t in [0.50, 0.70]: black (#000000), alpha = 0.8   // 剪影帧
  t in [0.70, 1.00]: form_color, alpha = lerp(1.0 → 0.0)  // 淡出
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| t | float | 0–1.0s | 闪光已运行时间 |
| form_color | Color | `#FF6B35` 或 `#C44B8B` | 形态主题色 |
| flash_alpha | float | 0.0–1.0 | CanvasLayer modulate alpha |

### F.4 Death Dissolve Progress

```
dissolve_radius(t) = max(char_radius - dissolve_speed * t, 0)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| char_radius | float | 12–32 px | 角色外包圆的半径（像素） |
| dissolve_speed | float | 16 px/s | 崩解速度——边缘向内收缩速率 |
| t | float | 0–char_radius/dissolve_speed | 崩解已运行时间 |
| dissolve_radius | float | 0–char_radius | 当前未崩解核心半径 |

当 `dissolve_radius <= 0` 时，角色完全崩解——所有碎片继续飘散直至 alpha 归零。

**Example** (人类形态 char_radius=12px): 完全崩解时间 = 12/16 = 0.75s。
**Example** (Beast 形态 char_radius=16px): 完全崩解时间 = 16/16 = 1.0s。

### F.5 Simultaneous VFX Priority Resolution

```
render_priority(vfx_a, vfx_b) = compare(priority[vfx_a], priority[vfx_b])
  if priority[vfx_a] > priority[vfx_b]: vfx_a renders on top
  if equal: newer vfx renders on top (timestamp tiebreak)
```

| Priority | VFX 条目 |
|----------|---------|
| 最高 | VFX-001 (变身闪光), VFX-002 (像素撕裂), VFX-014 (死亡崩解) |
| 高 | VFX-003 (变身爆发), VFX-005 (形态褪去), VFX-006 (狂暴激活), VFX-011 (受击白闪), VFX-018 (Boss 警告), VFX-019 (区域通关) |
| 中 | VFX-007 (狂暴光环), VFX-008 (Beast AOE), VFX-009 (Dragon 锥形), VFX-012 (受击警告), VFX-013 (低 HP 警告), VFX-016/017 (波次提示), VFX-015 (死亡灰度化) |
| 低 | VFX-004 (形态光环), VFX-010 (人类攻击), VFX-020 (计量表发光), VFX-022 (敌人死亡) |
| 最低 | VFX-021 (移动尘埃) |

### F.6 Pool Exhaustion Handling

```
if pool.active_count >= pool.size:
    oldest_particle = argmax(p in pool.active: p.elapsed_time)
    recycle(oldest_particle)  // 强制回收最老的粒子——将其分配给新请求
```

当粒子池耗尽时，强制回收已运行时间最长的活跃粒子，分配给新请求。这确保新特效总是有粒子可用（即使牺牲旧粒子的生命周期）。若已运行时间最长的粒子属于更高优先级的 VFX（如变身爆发），跳过该粒子，回收次老的粒子。

## Edge Cases

- **如果粒子池耗尽且所有活跃粒子均属于最高优先级 VFX（如变身闪光正在进行中）**：新请求的粒子不生成——在控制台打印 warning："[VFX] Pool [type] exhausted — all particles are HIGH priority, new request dropped"。此场景仅在极端情况下发生（如连续多次变身触发 + 大量攻击命中同时发生），在正常游玩中不应出现。

- **如果变身闪光正在进行中时触发死亡**：DEATH 优先级最高——死亡崩解 VFX（VFX-014）覆盖变身闪光。闪光立即中断（CanvasLayer modulate 直接切换到死亡崩解覆盖）。变身撕裂动画被跳过——直接进入死亡崩解。不尝试同时播放两个"最高"优先级 VFX。

- **如果变身粒子爆发和攻击命中粒子同时触发**：两者独立渲染——变身粒子来自角色位置向外爆发，攻击粒子在敌人位置产生。它们不共享粒子池，不会互相影响。Z-order：变身粒子（Layer 3/1）在攻击粒子（Layer 1）之上。

- **如果玩家在低 HP 警告（VFX-013）激活时受击**：受击屏幕警告（VFX-012）短暂叠加在持续低 HP 警告之上——两者的红色渐变 alpha 相加（但不叠加超过 0.5 以防止视觉过曝）。受击警告 alpha 0.15 + 低 HP 警告 alpha 0.05-0.35 → 瞬时叠加 alpha 0.2-0.5。

- **如果形态褪去粒子（VFX-005）和变身爆发粒子（VFX-003）重叠**：仅在变身持续时间刚好等于 0 时可能发生（持续时间归零的同一帧触发 COOLDOWN）——但实际上 VFX-003 的粒子生命周期为 0.8s，VFX-005 的粒子在 COOLDOWN 开始时才生成。若变身持续时间 < 0.8s（FormConfig duration 异常短），旧粒子尚未消散——两者共存，形态褪去粒子（alpha 0.6）叠在残留的变身粒子（alpha 递减中）之上。视觉上不会混淆——褪去粒子的速度较慢（150 vs 300 px/s）。

- **如果 CanvasLayer modulate 不支持形态色叠加（引擎/渲染器限制）**：GL Compatibility 渲染器支持 CanvasLayer modulate。若切换到更受限的渲染模式，回退方案为：创建一个全屏 ColorRect 节点并在需要的帧内修改其 color 和 alpha——效果相同，但需要一个持久节点。

- **如果玩家在变身撕裂（VFX-002）的 4 帧期间移动**：角色精灵继续跟随玩家位置移动——撕裂效果在角色当前位置上执行，不锁定到撕裂开始时的位置。这意味着撕裂和移动同时发生——视觉上角色在移动过程中完成变身。

- **如果多个 Boss 波警告信号同时触发（波次系统 bug）**：VFX-018（Boss 波警告）的屏幕红色闪烁使用 `start()` / `stop()` 模式——连续的 `start()` 调用不叠加、不延长持续时间，仅重置闪烁计时器至 2.0s。

- **如果计量表从 79% 跳升至 100%（一次性收集大量点数跳过 80-99% 区间）**：VFX-020（计量表边缘发光）在 80%→100% 的过渡被跳过——屏幕边缘发光直接从 alpha 0 跳到 alpha 0.1（对应 100%）。不尝试播放"遗漏"的过渡帧。

- **如果敌人死亡粒子触发时敌人精灵已被移除（死亡动画与精灵移除的帧序问题）**：VFX-022（敌人死亡粒子）使用敌人死亡位置作为粒子原点——在敌人节点被 `queue_free()` 之前捕获 `global_position`。若 sprite 已在同一帧被移除但位置已缓存，粒子在正确位置生成但无敌人精灵作为视觉参考。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 游戏状态管理 | 订阅 `state_changed` 信号——驱动状态转换 VFX（变身闪光、狂暴激活、形态褪去、死亡崩解） |
| 玩家系统 | 订阅 `player_hit`、`damage_dealt`、`player_died` 信号；查询 `global_position`（攻击 VFX 位置参考） |
| 变身系统 | 订阅 `transformation_started`、`transformation_expired`、`berserk_activated`、`berserk_expired`、`cooldown_complete`、`transformation_failed` 信号；查询 `current_form_id`（形态主题色和几何母题选择） |
| 波次系统 | 订阅 `wave_started`、`wave_cleared`、`boss_wave_started`、`all_waves_cleared` 信号 |
| 吸收系统 | 查询 `meter_current`（每帧）——驱动计量表边缘发光 VFX |

### 软依赖（尚未设计，预留接口）

| 系统 | 依赖内容 | 回退方案 |
|------|---------|---------|
| 敌人系统 | 订阅敌人死亡信号——触发敌人死亡粒子 VFX | 跳过敌人死亡粒子——不影响核心玩法 VFX |
| Boss 系统 | Boss 登场/死亡 VFX——艺术圣经定义了 12 帧 Boss 死亡动画 | 待 Boss 系统 GDD 设计后补充 VFX 条目 |

### 下游依赖方

| 系统 | 依赖内容 |
|------|---------|
| 设置系统（Vertical Slice） | VFX 强度设置——"开启/减弱/关闭"三级控制。VFX 系统需响应此设置调整粒子数量和屏幕闪光强度 |
| Boss 系统（Vertical Slice） | VFX 系统为 Boss 登场和死亡提供视觉特效——Boss 系统触发信号，VFX 系统执行渲染 |
| 音频系统 | 平行系统——两者响应同一信号源（GSM、玩家系统、变身系统），确保视觉和听觉同步 |

### 接口契约

VFX 系统是叶子消费者节点——不向其他系统暴露主动接口。但它提供以下内部契约：

1. **VFX 强度设置**：`set_intensity(level: VFXIntensity)` —— `FULL`（所有特效）/ `REDUCED`（闪烁频率减半、无全屏闪）/ `OFF`（无闪烁、无震动）。供设置系统调用
2. **粒子总计数查询**：`get_active_particle_count() -> int` —— 性能监控接口
3. **VFX 暂停/恢复**：`set_paused(paused: bool)` —— 当 GSM time_scale=0 时暂停所有粒子动画

## Tuning Knobs

| 参数 | 默认值 | 安全范围 | 视觉/性能影响 |
|------|--------|---------|-------------|
| `transform_flash_duration` | 1.0s | 0.5–2.0s | 变身闪光总时长。太长→覆盖游戏时间过长；太短→爆发感不足 |
| `transform_flash_white_duration` | 0.2s | 0.1–0.3s | 白帧持续时间。太长→刺眼；太短→无白帧感 |
| `transform_tear_frames` | 4 帧 | 2–8 帧 | 像素撕裂帧数。太少→瞬间切换无撕裂感；太多→"变身慢"的感觉 |
| `transform_burst_particle_count` | 40 | 20–80 | 变身爆发粒子数量。太多→性能 + 遮挡角色；太少→爆发感不足 |
| `form_aura_alpha` | 0.15 | 0.05–0.3 | 变身光环透明度。太高→分散注意力；太低→不可见 |
| `form_aura_radius` | 16 px | 8–32 px | 变身光环半径 |
| `berserk_aura_alpha` | 0.4 | 0.2–0.6 | 狂暴光环透明度 |
| `berserk_aura_radius` | 24 px | 16–40 px | 狂暴光环半径 |
| `berserk_aura_pulse_period` | 0.3s | 0.15–0.6s | 狂暴光环脉冲周期 |
| `beast_aoe_particle_count` | 15 | 8–30 | Beast AOE 每攻击粒子数 |
| `dragon_cone_particle_count` | 12 | 6–25 | Dragon 锥形吐息每攻击粒子数 |
| `hit_flash_duration` | 1 帧 (0.017s) | 1–3 帧 | 受击白闪持续帧数 |
| `death_dissolve_speed` | 16 px/s | 8–32 px/s | 死亡崩解速度。太快→看不清崩解过程；太慢→死亡画面冗长 |
| `death_dissolve_particle_count` | 60 | 30–100 | 死亡崩解粒子总数 |
| `death_grayscale_duration` | 2.0s | 1.0–4.0s | 死亡灰度化总时长 |
| `wave_text_fade_in` | 0.3s | 0.1–0.5s | 波次提示淡入时间 |
| `wave_text_stay` | 1.0s | 0.5–2.0s | 波次提示停留时间 |
| `boss_warning_flash_period` | 0.3s | 0.15–0.6s | Boss 警告闪烁周期 |
| `meter_glow_start_threshold` | 0.8 | 0.6–0.9 | 计量表边缘发光起始阈值（占 meter_max 比例） |
| `max_screen_particles` | 150 | 80–250 | 屏幕上同时可见粒子总数上限。受目标平台性能限制 |
| `dust_particle_interval` | 6 帧 (0.1s) | 3–12 帧 | 移动尘埃生成间隔 |

## Visual/Audio Requirements

| # | 需求 | 约束来源 | 实现方式 |
|---|------|---------|---------|
| VR-1 | 像素完整性——所有粒子使用 Nearest-neighbor 缩放，2×2px 或 4×4px 方形精灵，仅允许 90°/180° 旋转 | 艺术圣经 Section 8, 9 | `CpuParticles2D` + 预渲染精灵帧 |
| VR-2 | 形态颜色一致性——每个形态的所有 VFX 使用统一的主题色（Beast `#FF6B35`/`#CC5522`，Dragon `#C44B8B`/`#883366`） | 艺术圣经 Section 3 | `modulate` 属性设置为形态主题色 |
| VR-3 | 形态几何母题统一——Beast VFX 仅使用圆形/弧形粒子，Dragon VFX 仅使用三角形粒子 | 艺术圣经 Section 3 | 预渲染像素精灵帧（3×1px 弧形、4×4px 三角） |
| VR-4 | 角色可读性——粒子 Z-order 低于角色精灵，角色最外层 1px 轮廓始终可见 | 艺术圣经角色可读性规则 | CanvasLayer Z-index 排序：角色在粒子之上 |
| VR-5 | 禁止后处理——无泛光、色差、景深、色调映射、运动模糊、镜头眩光 | 艺术圣经 Section 9 | 所有效果使用 CanvasLayer modulate + ColorRect + 粒子精灵 |
| VR-6 | 状态转换视觉连续性——变身序列（VFX-001 → VFX-002 → VFX-003 → VFX-004）必须按序触发，帧精确同步 | 游戏状态管理 GDD（状态转换规则） | 连接 GSM `state_changed` 信号 + `_process` 计时 |
| VR-7 | 音频同步——所有 VFX 爆发时刻（变身闪光、受击白闪、死亡崩解）与音频系统的音效触发点对齐 | 音频系统 GDD（待设计——预留接口） | 同一 GSM/玩家信号驱动 VFX 和音频——不直接耦合，但信号时间戳确保同步 |

## UI Requirements

| # | 需求 | 说明 |
|---|------|------|
| UI-1 | VFX 强度设置（设置系统——Vertical Slice） | 三级控制：`FULL`（所有特效）/ `REDUCED`（闪烁减半、无全屏闪光、粒子数量减至 60% 上限）/ `OFF`（仅保留受击白闪和低 HP 警告——核心游戏性反馈 VFX）。VFX 系统通过 `set_intensity(level)` 接口响应 |
| UI-2 | 波次提示文字渲染 | VFX 系统负责渲染波次提示文字（VFX-016/017/018/019），使用像素字体。文字位置使用 HUD 系统提供的锚点（top-center），确保不与 HUD 元素的波次信息重叠渲染 |
| UI-3 | 低 HP 警告与 HUD 层级协调 | VFX-013（低 HP 屏幕边缘红色渐变）渲染在 Layer 2——Z-order 低于 HUD 的 CanvasLayer。HUD 的 HP 条和数值始终可读。红色渐变 alpha 不应超过 0.35（防止遮挡 HUD 元素） |

## Acceptance Criteria

| # | 条件 | 期望结果 |
|---|------|---------|
| AC-1 | GIVEN 玩家计量表满且按变身键，WHEN GSM 进入 TRANSFORMATION 状态 | THEN 全屏形态色闪光触发：0.3s 形态色→0.2s 纯白→0.2s 黑色剪影→0.3s 淡出（VFX-001），且形态色为当前激活形态的主题色（Beast=橙红 `#FF6B35`，Dragon=紫红 `#C44B8B`） |
| AC-2 | GIVEN GSM 进入 TRANSFORMATION 状态，WHEN VFX-002 触发 | THEN 角色精灵在 4 帧内从人形逐行替换为形态精灵，替换方向为底部向上推进，每帧替换约 25% 像素行 |
| AC-3 | GIVEN 玩家处于 Beast TRANSFORMATION 状态，WHEN `damage_dealt` 信号触发 | THEN 以玩家位置为圆心、96px 半径爆发 15 个橙色 3×1px 弧形粒子（VFX-008），粒子向外扩散 0.3s 后 alpha 归零 |
| AC-4 | GIVEN 玩家处于 Dragon TRANSFORMATION 状态，WHEN `damage_dealt` 信号触发 | THEN 向玩家瞄准方向 60° 锥形喷射 12 个紫色 4×4px 三角粒子（VFX-009），粒子飞行 0.35s 后 alpha 归零 |
| AC-5 | GIVEN 玩家被敌人击中，WHEN `player_hit` 信号触发 | THEN 角色精灵 1 帧白闪（VFX-011）+ 屏幕四边红色渐变闪现 0.4s（VFX-012） |
| AC-6 | GIVEN 玩家 HP ≤ 30%，WHEN 每帧检查 hp_ratio | THEN 屏幕四边红色渐变持续存在（VFX-013），alpha 随 HP 降低线性增加；HP ≤ 15% 时进入脉冲模式（alpha 0.2↔0.35，周期 0.5s） |
| AC-7 | GIVEN GSM 进入 DEATH 状态，WHEN VFX-014 和 VFX-015 触发 | THEN 角色精灵从边缘向内崩解为 2×2px 碎片（速度 16px/s），碎片 2.0s 内消散；全屏向灰度过渡（饱和度 2.0s 内降为 0） |
| AC-8 | GIVEN 波次系统发送 `boss_wave_started` 信号，WHEN VFX-018 触发 | THEN 屏幕边缘红色闪烁（alpha 0.2↔0.4，周期 0.3s，持续 2.0s）+ Boss 名称显示于屏幕上部居中 |
| AC-9 | GIVEN GSM 从 TRANSFORMATION 进入 COOLDOWN 状态，WHEN VFX-005 触发 | THEN 形态精灵从顶部向下逐行剥离为人类精灵（3 帧）+ 20 个形态色粒子从角色向外飘散（1.0s 内 alpha 0.6→0.0） |
| AC-10 | GIVEN 某一粒子池（如攻击命中）已全部使用且池中无低优先级粒子，WHEN 新 VFX 请求触发 | THEN 新粒子不生成，控制台打印 `[VFX] Pool exhausted` warning；不存在最高优先级的粒子被强制回收 |
| AC-11 | GIVEN 玩家从 Beast 形态冷却完成后切换为 Dragon 形态，WHEN 下次变身触发 | THEN 所有 VFX 颜色切换为 Dragon 主题色（紫红 `#C44B8B`），粒子形状切换为三角形 |
| AC-12 | GIVEN 游戏运行中任意时刻，WHEN 查询 `get_active_particle_count()` | THEN 返回的活跃粒子总数 ≤ 150（MVP 性能硬上限），超出时最老的粒子被强制回收（F.6 规则） |

## Open Questions

| # | 问题 | 影响 | 建议方向 |
|---|------|------|---------|
| OQ-1 | 像素撕裂（VFX-002/005）使用 shader 还是预渲染精灵帧序列？ | 实现复杂度——shader 需要 GL Compatibility 兼容的 CanvasItem shader（`texture` + `UV` 逐行替换），精灵帧序列需要预渲染 4 帧动画（美术工作量） | 用 shader 实现——灵活性更高，不需要美术额外产帧。但需要验证 GL Compatibility 渲染器下 CanvasItem shader 的 `TEXTURE_PIXEL_SIZE` 可用性（Godot 4.6） |
| OQ-2 | 屏幕边缘红色渐变（VFX-012/013）使用 9-slice TextureRect 还是 ColorRect 组合？ | 性能——9-slice 仅需 1 个节点但需要预渲染纹理；4 个 ColorRect（上下左右各一）无需纹理但需 4 个节点 | 建议 9-slice TextureRect——节点数少、内存可控、与像素艺术风格一致。若 9-slice 在 GL Compatibility 下有问题，回退为 ColorRect |
| OQ-3 | 粒子池大小是否需要动态扩展（运行时扩缩容）？ | 内存和灵活性——固定池大小更简单但可能在极端战斗场景中不足；动态池更灵活但增加内存管理复杂度 | MVP 使用固定池大小（当前值）。在 playtest 中监控池耗尽 warning 频率——若频繁出现，在 Vertical Slice 中实现动态扩展 |
| OQ-4 | GL Compatibility 渲染器是否支持灰度化 shader（VFX-015 死亡灰度化）？ | VFX-015 的视觉实现——shader 方案（调整 saturation）vs 回退方案（半透明黑色覆盖层 alpha 0.4 逐渐增加至 alpha 0.7） | 优先尝试 CanvasItem shader 的 `saturation` 调整；若不支持，使用回退方案。Godot 4.6 GL Compatibility 的 shader 限制需要实际测试确认 |
| OQ-5 | Boss VFX（登场大型特效、12 帧死亡动画、双层视觉结构）的详细规格需等 Boss 系统 GDD 设计后补充 | VFX Catalog 的完整度——当前 Boss 相关 VFX 仅为预留（VFX-018 仅覆盖波次警告，不含 Boss 登场/死亡特效） | Boss 系统 GDD（#14, Vertical Slice）设计时，VFX 系统需补充 2-3 个 Boss 专属 VFX 条目（登场大型特效、12 帧死亡动画、Boss 受击阶段视觉变化） |
