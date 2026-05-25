# Audio System — 音频系统

> **Status**: Designed
> **Author**: Claude Code + User
> **Last Updated**: 2026-05-24
> **Implements Pillar**: Pillar 1 (Explosive Transformation) + Pillar 3 (Paced Mastery)

## Overview

Audio 系统（Audio System）是 Shapeshift Survivor 的听觉反馈层——它将游戏事件转化为声音信号，在三个时间尺度上塑造玩家的情感体验：**微秒级**的音效反馈（攻击命中、受击、收集点数）提供即时的"果汁感"；**秒级**的状态转换音频（变身爆发、狂暴激活、形态褪去）标记节奏节点；**分钟级**的动态 BGM 系统（探索→蓄能渐强→变身战斗高潮→冷却回落）构建"蓄能→爆发"循环的听觉弧线。

**技术骨架**：Audio 系统是订阅型消费者——订阅 GSM 的 `state_changed`（BGM 层级切换）、玩家系统的 `player_hit`/`damage_dealt`/`player_died`（音效触发）、变身系统的 6 个信号（变身/狂暴/冷却关键时刻音效）、波次系统的 4 个信号（波次提示音效）、吸收系统的 `meter_current` 变化（蓄能渐强音）。音频通过 4 条总线输出（Music、SFX、UI、Voice），SFX 使用 AudioStreamPlayer 对象池（8 个并发通道），BGM 使用分层音频技术——在蓄能阶段叠加强度层，变身时切换到战斗高潮层。

**玩家体验**：玩家不是在"听音效"——音频在告诉玩家发生了什么。变身瞬间的低频轰鸣 + 形态主题音效 = "你变身了!"。蓄能阶段渐强的合成器音高 = "力量在积聚"。受击时的短促刺耳音 = "危险!"。没有这个系统，Shapeshift Survivor 变成一部无声电影——Pillar 1 的爆发变身只剩视觉、Pillar 3 的节奏掌控失去最重要的时间标记。音频将设计师定义的节奏转化为玩家能用耳朵感受到的情感弧线。

## Player Fantasy

Audio 系统的幻想是**听觉冲击力**——玩家可能不会用"音频设计"这个词，但他们会感受到"这游戏的音效太爽了"。每一次变身都有令人振奋的低频轰鸣、每一次蓄能都有渐强的合成器音高、每一次受击都有刺痛神经的短促警告音。

> **"声音不是装饰——声音是力量本身。"**

Audio 不是背景噪音——它是游戏与玩家之间的听觉语言。在这门语言中：渐强的合成器音高 = "力量在积聚，快能变身了"；低频轰鸣 + 形态主题音色 = "你变身了，现在是碾压时刻"；短促刺耳音 = "危险，快走位"；BGM 突然从战斗高潮降回探索氛围 = "变身结束了，你又脆弱了，重新蓄能吧"。

**Audio 的情感节奏**：

1. **探索阶段——空旷感**：BGM 保持在最低强度层——稀疏的环境音垫（ambient pad）+ 低频脉动（sub pulse），节奏稀疏（每 2-3 秒一次）。玩家听到的是"空旷、安静、潜藏危险"的感觉。偶尔的敌人接近音效（微弱、远处）增加紧张感。这个阶段的音频告诉玩家："你还在积蓄力量，还没到爆发的时候。"

2. **蓄能阶段——渐强的期待感**：随着 `meter_current` 从 0% → 100%，BGM 的强度层逐渐叠加——首先是 bassline 进入（30%），然后是打击乐层（60%），最后是合成器主旋律（90%）。合成器音高随蓄能比例上升——从低沉的 C2 渐升至明亮的 C4。配合屏幕边缘形态色微光，玩家在听觉和视觉上同时感受到"力量在积聚"的预期。计量表满（100%）时——短促的"准备就绪"提示音（上升琶音），告诉玩家："可以变身了!"

3. **变身瞬间——爆发感**：这是全游戏最重要的单次音频事件。变身音效分三层叠加：① 低频轰鸣（sub boom，~50Hz，0.3s attack + 1.0s decay）——撼动身体；② 形态主题音色（Beast=粗糙失真合成器锯齿波，Dragon=尖锐共振滤波扫频）——标识形态身份；③ 高频"撕裂"音（快速频率扫描，0.1s）——暗示"旧形态被撕裂"。玩家不需要看屏幕——光听声音就知道"我变身了"。

4. **变身战斗——碾压感**：BGM 切换至最高强度层——全打击乐 + 失真 bassline + 主旋律全开。每次攻击命中有形态主题的命中音效——Beast 圆形 AOE 的每次命中 = 低沉有力的"咚"（低频打击感），Dragon 锥形吐息的每次命中 = 尖锐的"嘶嘶"火焰音。角色周围有持续的形态主题低频嗡声——提醒玩家"你仍在变身中"。狂暴激活时——BGM 短暂加速（tempo +10%）+ 失真度增加 + 音高升高半音——"现在更猛了"。

5. **受击——威胁感**：玩家受击时短促刺耳警告音（~2kHz 方波，0.05s）——即使不看屏幕也知道"挨打了"。HP < 30% 时——持续的低频心跳脉冲声（~40Hz，周期 0.5s），随 HP 降低频率加快。这个心跳声是本能的——不需要理解"HP 百分比"的概念，身体的原始反应就会告诉玩家："危险! 快躲!"

6. **冷却/褪去——失落感**：变身到期的视觉撕裂伴随音频的"回落"——BGM 从战斗高潮在 1.0s 内撤去打击乐和主旋律层，只剩 bassline 和氛围垫。形态主题的低频嗡声消失——"力量不见了"。短暂静默（0.3s）→ 探索氛围恢复。这个突然的安静是一种"失落"，是下一次蓄能期待感的燃料。

**该系统直接支撑的游戏支柱**：

- **支柱 1（爆发变身）**：Audio 系统是 Pillar 1 的听觉引擎。变身瞬间的三层音频叠加（低频轰鸣 + 形态音色 + 撕裂音）与 VFX 系统的三层视觉（全屏闪光 + 像素撕裂 + 粒子爆发）完美同步——视觉和听觉在同一帧告诉玩家同一件事："你变身了。"如果没有 Audio，Pillar 1 只剩视觉——玩家会看到闪光和粒子，但身体的震动感（50Hz sub boom）消失了。声音是最直接的本能触发——低频振动让玩家"感到"力量，而不只是"看到"力量。

- **支柱 3（节奏掌控）**：Audio 为每一个状态转换提供独特的听觉标识——变身是爆发频率扫频、受击是刺痛方波、冷却褪去是突然安静、死亡是低频渐弱。这些听觉信号与视觉信号在同一帧触发（由同一 GSM 信号驱动），确保"节奏"在玩家的两个感官维度上同时被感知。

**参考游戏中类似的感觉**：
- **Nioh 2 妖怪化**——变身瞬间的低频轰鸣 + 音调偏移 + 环境音短暂静默，然后妖怪形态的战吼声进入。我们的三层变身音频（低频轰鸣 + 形态音色 + 撕裂音）是对这个听觉瞬间的合成器音乐翻译。
- **DOOM (2016)** 的"战斗音乐分层"——BGM 根据战斗强度动态叠加/撤去乐器层。我们的 BGM 系统使用同样技术——蓄能阶段叠加强度层，变身时全开，冷却时撤去。
- **Hades 的受击和死亡音效**——短促、刺耳、不容忽视。受击音不需要"好听"，需要"有效"。我们的受击警告音（2kHz 方波 + 低频心跳）沿用同样哲学。

**"出问题时玩家会感受到什么"**：
- 当 Audio **正确**时，玩家感觉游戏"很 juicy"——攻击有重量、受击有威胁、变身有爆发。他们可能不会单独注意到音效，但会感觉整体游戏体验"很爽"。
- 当 Audio **错误**时——变身没有轰鸣只有视觉、受击没有警告音、BGM 在状态切换时不变——游戏感觉"空洞、死寂"。玩家仍然能看到游戏逻辑在运行（HP 在减少、变身开始了），但缺乏情绪连接。Audio 的缺失降低了游戏的情感冲击力——Pillar 1 的"爆发变身"变成纯数值切换。

## Detailed Design

### Core Rules

**Rule 1: 信号驱动的纯响应系统**

Audio 系统不主动发起任何音频——它订阅上游系统的信号和 GSM 的状态转换，在收到通知时触发对应的音频事件。Audio 系统不调用任何上游系统的逻辑方法——它是纯粹的听觉输出层。

**Rule 2: 四总线音频架构**

所有音频通过 4 条 Audio Bus 输出：

| Bus | 名称 | 内容 | 说明 |
|-----|------|------|------|
| Bus 1 | Music | BGM 分层播放、BGM 过渡 | 最低层——持续存在。受设置系统音量控制 |
| Bus 2 | SFX | 游戏音效（攻击、受击、变身、拾取、波次提示） | 最活跃的总线——需要 8 通道对象池 |
| Bus 3 | UI | UI 交互音效（按钮 hover/click、菜单开关、升级选择） | 轻量级——4 通道对象池。与 SFX 独立音量控制 |
| Bus 4 | Voice | 角色语音/战吼（预留——MVP 不使用） | 为 Vertical Slice 预留 |

**Rule 3: SFX 对象池管理**

所有 SFX 使用 AudioStreamPlayer 对象池——预分配播放器节点，播放时从池中取出并配置（stream、volume_db、pitch_scale），`finished` 信号触发后回收至池中。

| 池 | 通道数 | 用途 | 说明 |
|----|--------|------|------|
| SFX Pool | 8 | 游戏音效 | 攻击命中、受击、变身、拾取、波次提示 |
| UI Pool | 4 | UI 音效 | 按钮交互、菜单切换、升级选择 |

若池中所有播放器均忙碌，按优先级规则处理（见 Rule 6）。

**Rule 4: BGM 分层动态音乐系统**

BGM 使用分层音频技术——单一音乐轨分为 4 个强度层，根据 GSM 状态和蓄能进度动态叠加/撤去。不使用多首独立 BGM 切换——所有变化通过层的叠加实现，确保音乐连续性。

| Layer | 名称 | 内容 | 触发条件 |
|-------|------|------|---------|
| Layer 1 | Ambient | 环境音垫 + 低频脉动（sub pulse） | 始终播放（EXPLORATION 状态下仅此层） |
| Layer 2 | Bassline | 低音合成器 bassline | `meter_current >= 30%` 或 GSM = CHARGING |
| Layer 3 | Percussion | 打击乐层（kick + hi-hat + snare pattern） | `meter_current >= 60%` |
| Layer 4 | Lead | 合成器主旋律（形态主题音色） | `meter_current >= 90%` 或 GSM = TRANSFORMATION/BERSERK |

层之间的切换使用 0.3s crossfade（Tween `volume_db`），避免突然的音频跳变。

**Rule 5: 变身音频三层叠加**

变身瞬间（GSM → TRANSFORMATION）是最高优先级的音频事件，分三层同步触发：

| 层 | 音频内容 | 频率特征 | 时长 | 说明 |
|----|---------|---------|------|------|
| Sub Boom | 低频轰鸣 | ~50Hz 正弦波 + 失真 | 0.3s attack + 1.0s decay | 撼动身体——通过 subwoofer 感知 |
| Form Signature | 形态主题音色 | Beast: 锯齿波失真合成器 (100-400Hz), Dragon: 共振滤波扫频 (200-2000Hz) | 0.5s | 标识形态身份 |
| Tear | 高频撕裂音 | 快速频率扫描 (1kHz→8kHz，0.1s) | 0.1s | 暗示"旧形态被撕裂" |

**Rule 6: 音频优先级与抢占**

当 SFX 池耗尽时，按优先级决定播放哪个音频：

| Priority | 音频事件 | 说明 |
|----------|---------|------|
| 最高 | 变身三层（Sub Boom + Form Signature + Tear）、死亡音频 | 不可被抢占 |
| 高 | 受击警告音、低 HP 心跳、Boss 警告音 | 可抢占最低优先级 |
| 中 | 攻击命中、波次提示、蓄能满提示音、狂暴激活 | 默认优先级 |
| 低 | 收集点数、敌人死亡、变身结束褪去 | 可被高优先级抢占 |
| 最低 | 移动脚步声（预留）、UI 音效 | 可被任何优先级抢占 |

池耗尽处理：若所有 8 个 SFX 通道均在使用且新请求的优先级 ≥ 当前播放中最低优先级的音频 → 抢占（停止最低优先级播放器，回收并分配给新音频）。若新请求优先级较低 → 丢弃（该音效不播放，不打印 warning——正常游戏流程中池耗尽在 MVP 阶段不应频繁发生）。

**Rule 7: 音频与 VFX 同步**

Audio 和 VFX 订阅同一信号源（GSM `state_changed`、Player 信号、Transformation 信号、Wave 信号）——确保视觉和听觉在同一帧触发。Audio 不依赖 VFX 来确保同步——两者是同一信号驱动下的平行消费者。

**Rule 8: 像素艺术听觉美学**

音频风格与像素艺术视觉风格一致——避免高保真管弦乐或真实乐器采样。使用合成器音色（锯齿波/方波/正弦波 + 滤波 + 失真）、低比特率采样、bit-crush 效果。音效简洁有力——每个音效在 0.05-0.5s 内完成其听觉信息传达，不拖泥带水。

### Audio Catalog

#### 1. 变身相关 Audio

**AUD-001: 变身低频轰鸣 (Sub Boom)**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)` |
| 音频 | ~50Hz 正弦波 → 软削波失真 → sub boost (+6dB @ 60Hz)。0.3s attack（无声到峰值）→ 1.0s decay（峰值到无声）。使用合成器生成——不需要采样 |
| 总线 | SFX（不是 Music——这是单次事件音效） |
| 优先级 | 最高 |

**AUD-002: 形态主题变身音色 (Form Signature)**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)`（与 AUD-001 同时） |
| 音频 | Beast: 锯齿波合成器（100-400Hz sweep）+ 失真 + bit-crush（8-bit）。Dragon: 共振低通滤波扫频（200→2000Hz）+ 锐利 resonance peak + 略微混响。0.5s 持续 |
| 总线 | SFX |
| 优先级 | 最高 |

**AUD-003: 变身撕裂音 (Tear)**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)`（与 AUD-001/002 同时） |
| 音频 | 快速频率扫描 1kHz→8kHz，0.1s，方波 + ring modulation。轻微 distortion。短促锐利——模拟"撕裂"的听觉感觉 |
| 总线 | SFX |
| 优先级 | 最高 |

**AUD-004: 变身战斗 BGM 全开**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, TRANSFORMATION)` |
| 音频 | BGM Layer 4 (Lead) 进入（如尚未进入），音量 0→full 0.2s crossfade。整轨输出 volume +2dB（通过 Music bus 临时增益——营造"更强"的感觉） |
| 总线 | Music |
| 优先级 | —（持续轨，不占 SFX 池） |

**AUD-005: 变身结束褪去音频**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, COOLDOWN)` |
| 音频 | BGM Layer 4 (Lead) 和 Layer 3 (Percussion) 在 1.0s 内 crossfade 退出（音量 full→0）。0.3s 短暂静默 → Layer 1-2 保持。低频嗡声（~40Hz，持续循环在变身期间播放）立即停止。形态主题音色的反向播放（0.3s，反向 reverb swell）——"力量被吸走了" |
| 总线 | Music + SFX |
| 优先级 | 低（形态褪去音效） |

#### 2. 狂暴相关 Audio

**AUD-006: 狂暴激活音频**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, BERSERK)` |
| 音频 | 短促上升音阶（3 音符快速琶音，形态主题音色，0.2s）——"更猛了!"。Music bus 插入轻微 overdrive（+3dB gain，soft clip） |
| 总线 | Music + SFX |
| 优先级 | 中 |

**AUD-007: 狂暴持续氛围**

| 属性 | 值 |
|------|-----|
| 触发 | BERSERK 状态持续期间 |
| 音频 | 持续的 ~55Hz 低频嗡声（比变身低频更高、更紧张），脉动周期 0.3s（与 VFX 光环脉冲同步）。叠加到 SFX bus。alpha 0.4 |
| 总线 | SFX（持续循环——占用 1 个 SFX 通道） |
| 优先级 | 中 |

#### 3. 攻击 Audio

**AUD-008: Beast 圆形 AOE 攻击音**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `damage_dealt`（Beast TRANSFORMATION/BERSERK） |
| 音频 | 低沉"咚"——~80Hz 正弦波 percussion hit（0.1s attack + 0.2s decay）。每次攻击触发的音高微变（±5% pitch randomization）避免重复疲劳。最大触发频率由 Beast 攻击间隔决定（每 0.3s 一次） |
| 总线 | SFX |
| 优先级 | 中 |

**AUD-009: Dragon 锥形吐息攻击音**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `damage_dealt`（Dragon TRANSFORMATION/BERSERK） |
| 音频 | 尖锐"嘶嘶"——白噪声 → 带通滤波 (1-4kHz) + 0.15s attack + 0.2s decay。模拟火焰喷射声。最大触发频率由 Dragon 攻击间隔决定（每 0.5s 一次） |
| 总线 | SFX |
| 优先级 | 中 |

**AUD-010: 人类形态攻击音**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `damage_dealt`（人类形态） |
| 音频 | 轻量级"啪"——短促白噪声 burst（0.05s），band-pass 2-6kHz，低音量。人类攻击的音频反馈较弱——强化"人类形态弱"的感觉 |
| 总线 | SFX |
| 优先级 | 低 |

#### 4. 受击 Audio

**AUD-011: 玩家受击警告音**

| 属性 | 值 |
|------|-----|
| 触发 | 玩家系统 `player_hit` |
| 音频 | 短促刺耳方波（~2kHz，0.05s）+ 轻微 pitch drop（2kHz→1.5kHz）。即使在密集音效中也清晰可辨。与 VFX-011（受击白闪）同步 |
| 总线 | SFX |
| 优先级 | 高 |

**AUD-012: 低 HP 心跳**

| 属性 | 值 |
|------|-----|
| 触发 | 每帧检查 `hp_current / hp_max <= 0.3` |
| 音频 | 低频心跳——~40Hz 正弦波 pulse（0.05s on，周期随 HP 变化）。HP 30%→15%：周期 0.5s。HP <15%：周期 0.3s。心跳声 alpha 随 HP 降低线性增加（0.3→0.7）。与 VFX-013（低 HP 屏幕边缘红色脉冲）同步 |
| 总线 | SFX（持续循环——占用 1 个 SFX 通道） |
| 优先级 | 高——不可被抢占（生理警告） |

#### 5. 死亡 Audio

**AUD-013: 死亡音频**

| 属性 | 值 |
|------|-----|
| 触发 | GSM `state_changed(_, DEATH)` |
| 音频 | 三层叠加：① 所有 BGM 层在 3.0s 内 fade out。② 低频渐弱——~30Hz 正弦波持续 2.0s→渐弱 0.5s。③ 最后的"心跳停止"——AUD-012 在死亡瞬间播放最后一个心跳，然后静默。0.3s 后——死亡 jingle（8 音符下降音阶，合成器，0.5s） |
| 总线 | Music + SFX |
| 优先级 | 最高 |

#### 6. 波次相关 Audio

**AUD-014: 波次开始提示音**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `wave_started(wave)` |
| 音频 | 短促上升音阶（4 音符，合成器，0.3s）——音高随 wave 数微升（wave 1=C4，wave 2=D4...） |
| 总线 | SFX |
| 优先级 | 中 |

**AUD-015: 波次清除提示音**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `wave_cleared(wave)` |
| 音频 | 6 音符上升琶音（合成器 + 轻微延迟，0.5s）——比波次开始更有"胜利感"。与 VFX-017（波次清除文字）同步 |
| 总线 | SFX |
| 优先级 | 中 |

**AUD-016: Boss 波警告音**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `boss_wave_started` |
| 音频 | 低频轰鸣（~35Hz，1.0s swell）+ 不和谐和弦（minor second interval，合成器 pad，2.0s）。与 VFX-018（Boss 屏幕红色闪烁）同步 |
| 总线 | SFX |
| 优先级 | 高——Boss 登场是重大事件 |

**AUD-017: 区域通关音频**

| 属性 | 值 |
|------|-----|
| 触发 | 波次系统 `all_waves_cleared` |
| 音频 | 胜利 jingle（12 音符上升旋律，合成器 + bell-like 音色，1.5s）+ BGM 短暂静默 0.5s。与 VFX-019（全屏金色闪光）同步 |
| 总线 | Music + SFX |
| 优先级 | 高 |

#### 7. 蓄能相关 Audio

**AUD-018: 蓄能渐强音高**

| 属性 | 值 |
|------|-----|
| 触发 | 吸收系统 `meter_current` 变化（每帧检查） |
| 音频 | 持续合成器音高从低到高线性映射 `meter_ratio`——`pitch = C2 + (meter_ratio * 24)` semitones（C2→C4）。音量随 `meter_ratio` 线性增加（alpha 0→0.3）。使用平滑插值（lerp 0.1 per frame）避免跳变。`meter >= 80%` 时增加轻微 tremolo（amplitude modulation ~4Hz）——"快要满了"的紧张感。`meter < 20%` 时不播放（保持音频干净） |
| 总线 | SFX（持续循环——占用 1 个 SFX 通道） |
| 优先级 | 低——可被攻击/受击音抢占 |

**AUD-019: 蓄能满提示音**

| 属性 | 值 |
|------|-----|
| 触发 | 吸收系统 `meter_full` 信号 |
| 音频 | 短促上升琶音（5 音符快速音阶，形态主题音色，0.3s）——"可以变身了!" |
| 总线 | SFX |
| 优先级 | 中 |

**AUD-020: 收集点数音效**

| 属性 | 值 |
|------|-----|
| 触发 | 吸收系统——每个掉落物被收集时 |
| 音频 | 短促"叮"——~1kHz 正弦波 + 轻微谐波（2kHz, 3kHz），0.05s。快速连续收集时音高微升（pitch randomization ±3%） |
| 总线 | SFX |
| 优先级 | 低 |

#### 8. 环境 Audio

**AUD-021: 敌人接近警告音**

| 属性 | 值 |
|------|-----|
| 触发 | 每 1s 检查——若任意敌人距离玩家 < 100px |
| 音频 | 微弱的 400Hz 脉动（0.05s on, 1.0s off）——"有敌人靠近"。仅在 EXPLORATION 和 CHARGING 状态播放。TRANSFORMATION 和 BERSERK 状态抑制 |
| 总线 | SFX |
| 优先级 | 最低 |

**AUD-022: 敌人死亡音效**

| 属性 | 值 |
|------|-----|
| 触发 | 敌人系统——敌人 HP 归零（预留接口） |
| 音频 | 低音量"噗"——白噪声 0.05s burst + 轻微 pitch drop。音量随机化 ±20%。最大并发限制：2 个（防止大量敌人同时死亡时音量突增） |
| 总线 | SFX |
| 优先级 | 低 |

#### 9. UI Audio

**AUD-023: UI 交互音效集**

| 属性 | 值 |
|------|-----|
| 触发 | 按钮 hover、按钮 click、菜单打开/关闭、升级选择确认 |
| 音频 | 按钮 hover: 轻微 1kHz 方波 blip (0.02s)。按钮 click: 双音符 (C5→E5, 0.05s)。菜单开关: 短促下降/上升音阶 (3 音符, 0.1s)。升级选择确认: 上升琶音 (4 音符, 0.2s) |
| 总线 | UI Bus（独立于 SFX bus——有单独音量控制） |
| 优先级 | 最低 |

### Interactions with Other Systems

| 系统 | 方向 | 内容 |
|------|------|------|
| 游戏状态管理 | 订阅 | `state_changed` → BGM 层切换 + 状态转换音效（变身三层、狂暴、冷却褪去、死亡） |
| 玩家系统 | 订阅 | `player_hit` → AUD-011/012；`damage_dealt` → AUD-008/009/010；`player_died` → AUD-013 |
| 变身系统 | 订阅 | `transformation_started` → AUD-001/002/003/004；`transformation_expired` → AUD-005；`berserk_activated` → AUD-006；`berserk_expired` → AUD-007；`cooldown_complete` → 冷却结束提示音（可选）；`transformation_failed` → 错误提示音 |
| 波次系统 | 订阅 | `wave_started` → AUD-014；`wave_cleared` → AUD-015；`boss_wave_started` → AUD-016；`all_waves_cleared` → AUD-017 |
| 吸收系统 | 订阅+查询 | `meter_full` → AUD-019；查询 `meter_current`（每帧）→ AUD-018 蓄能渐强音高 + BGM Layer 2/3 触发 |
| 敌人系统 | 订阅 | 敌人死亡信号（预留）→ AUD-022；查询敌人距离（每 1s）→ AUD-021 |
| VFX 系统 | 平行 | Audio 与 VFX 订阅同一信号源——确保变身三层音频与 VFX 全屏闪光/撕裂在同一帧触发 |
| 设置系统 | 暴露 | Audio 通过 `AudioServer.set_bus_volume_db()` 暴露 Music/SFX/UI/Voice 总线音量控制。设置系统（Vertical Slice）通过总线索引调整音量 |

## Formulas

### F.1 Audio Priority Resolution

```
play_decision(new_audio, pool) =
  if pool.has_idle_channel():
    assign_idle_channel(new_audio)
  else:
    lowest = pool.find_lowest_priority_active()
    if priority[new_audio] >= priority[lowest]:
      stop(lowest)
      assign_recycled_channel(lowest.channel, new_audio)
    else:
      drop(new_audio)  // 静默丢弃，不播放
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| new_audio.priority | enum | 0–4 | 0=最低, 1=低, 2=中, 3=高, 4=最高 |
| pool.channels | int | 8 | SFX 池通道数 |
| pool.active_count | int | 0–8 | 当前活跃播放器数 |

**Output**: 分配通道播放 / 抢占后播放 / 丢弃。
**Example**: 8 个通道全被"中"优先级攻击音占用，新来的"高"优先级受击音 → 抢占一个"中"优先级通道。

### F.2 BGM Layer Crossfade

```
layer_volume[layer](t) = lerp(volume_start, volume_target, clamp(t / fade_duration, 0.0, 1.0))
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| volume_start | float | -80–0 dB | 淡入淡出起始音量 |
| volume_target | float | -80–0 dB | 淡入淡出目标音量 |
| fade_duration | float | 0.3s | 固定 crossfade 时长 |
| t | float | 0–fade_duration | 已运行时间 |

**Example**: Layer 4 (Lead) 进入——`volume_start = -80 dB, volume_target = 0 dB, fade_duration = 0.3s`。0.15s 后 volume 约为 -6 dB。

### F.3 Charging Pitch Mapping

```
pitch_semitones = floor(meter_ratio * 24)  // C2 → C4 (2 octaves)
pitch_hz = 65.41 * pow(2, pitch_semitones / 12)  // C2 = 65.41 Hz
volume_alpha = clamp(meter_ratio - 0.2, 0.0, 0.3) / 0.8  // 20%→100% meter maps to alpha 0.0→0.3
tremolo_depth = meter_ratio >= 0.8 ? (meter_ratio - 0.8) * 0.25 : 0.0  // 80%→100% maps to tremolo depth 0.0→0.05
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| meter_ratio | float | 0.0–1.0 | `meter_current / meter_max` |
| pitch_semitones | int | 0–24 | 相对于 C2 的半音偏移 |
| pitch_hz | float | 65.41–261.63 Hz | 当前音高 (Hz) |
| volume_alpha | float | 0.0–0.3 | 合成器音量（线性增益） |
| tremolo_depth | float | 0.0–0.05 | AM 调制深度 |

**Example** (meter=50%): pitch_semitones = 12 (C3), pitch_hz = 130.81 Hz, volume_alpha ≈ 0.11, tremolo_depth = 0。
**Example** (meter=90%): pitch_semitones = 21 (A3), pitch_hz ≈ 220 Hz, volume_alpha = 0.3, tremolo_depth = 0.025。

### F.4 Low HP Heartbeat Rate

```
heartbeat_period = lerp(0.5, 0.3, clamp((0.3 - hp_ratio) / 0.3, 0.0, 1.0))  // seconds
heartbeat_volume = lerp(0.3, 0.7, clamp((0.3 - hp_ratio) / 0.3, 0.0, 1.0))
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| hp_ratio | float | 0.0–1.0 | `hp_current / hp_max` |
| heartbeat_period | float | 0.3–0.5s | 心跳脉冲间隔 |
| heartbeat_volume | float | 0.3–0.7 | 心跳音量（alpha） |

**Example** (hp_ratio=0.3): period=0.5s, volume=0.3。
**Example** (hp_ratio=0.1): period=0.3s, volume=0.7。

### F.5 Attack Pitch Randomization

```
pitch_scale = 1.0 + randf_range(-randomization_range, +randomization_range)
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| randomization_range | float | 0.03–0.05 | 音高随机偏差 |
| pitch_scale | float | ~0.95–1.05 | 应用到 AudioStreamPlayer.pitch_scale |

不同音效的 `randomization_range`：
- Beast AOE (AUD-008): ±5%
- Dragon Breath (AUD-009): ±3%
- Human Attack (AUD-010): ±3%
- Enemy Death (AUD-022): ±20% (音量随机化)

### F.6 BGM Tempo Modulation (狂暴 — MVP 可选)

```
tempo_multiplier = 1.0 + (berserk_active ? 0.05 : 0.0)  // +5% during BERSERK
```

| Variable | Type | Range | Description |
|----------|------|-------|-------------|
| berserk_active | bool | 0/1 | 狂暴是否激活 |
| tempo_multiplier | float | 1.0–1.05 | BGM 播放速度倍率 |

> MVP 注意：tempo shift 在 Godot 4.6 中可通过 `AudioStreamPlayer.pitch_scale` 微调实现——但会影响音高。若需保持音高不变，需要独立的变速播放功能（Godot 4.6 不原生支持），MVP 可跳过此效果。

## Edge Cases

- **如果 SFX 池 8 个通道全部被"最高"优先级音频占用（如连续变身触发——正常情况下不可能）**：新音频请求被丢弃。控制台打印 warning: `[Audio] SFX pool exhausted — all channels occupied by CRITICAL priority, new request dropped`。此场景在正常游玩中不应出现——变身有冷却时间，不可能连续触发。

- **如果 GSM 在玩家受击的同一帧触发状态转换（如从 EXPLORATION → DEATH）**：死亡音频（AUD-013，优先级最高）抢占受击警告音（AUD-011，优先级高）的通道。受击音被停止，死亡音频播放。这是正确行为——死亡是最高优先级的音频事件。

- **如果 BGM 分层切换（crossfade）尚未完成时触发新的状态转换**：中断当前 crossfade——新目标音量设置为当前值，然后开始新的 crossfade。不出现"旧 crossfade 完成后再开始新 crossfade"的延迟。

- **如果玩家在低 HP 心跳（AUD-012）播放期间 HP 恢复到 >30%（如拾取回血道具）**：心跳声在当前周期结束后停止——不立即中断（心跳的最后一个脉冲被允许完成，避免"心跳突然停止"的不自然感）。然后 AUD-012 循环标记为非活跃，回收 SFX 通道。

- **如果蓄能渐强音高（AUD-018）的通道被高优先级音频抢占（如受击）**：AUD-018 被停止——蓄能音高不是关键反馈。抢占结束后不自动恢复——下一次 `meter_current` 检查（下一帧）会重新触发 AUD-018（如 meter ≥ 20%）。蓄能音高短暂中断在 fast-paced combat 中是正常的。

- **如果多个敌人同时死亡（>2 个，如 Beast AOE 同时击杀一群敌人）**：AUD-022 的并发限制为 2——最多 2 个敌人死亡音效同时播放。第 3+ 个死亡被丢弃。防止音量突增和音频混乱。

- **如果 BGM Layer 音频文件缺失或加载失败**：该层的 `AudioStreamPlayer` 初始化为 null stream——静默。其他层正常播放。控制台打印 error: `[Audio] BGM Layer [N] stream failed to load`。游戏不崩溃——缺少一层 BGM 不会影响游戏性。

- **如果变身三层音频（AUD-001/002/003）中某一层因池不足被丢弃**：三层独立处理——某一层被丢弃不影响其他层。但"HIGHEST"优先级意味着正常情况下三层的任何一层都不会被抢占（8 通道池足够容纳 3 个最高优先级音频 + 剩余 5 通道为其他用途）。如果三层中有任何一层被丢弃，打印 warning。

- **如果 `meter_current` 从 95% 直接跳到 0%（变身激活——计量表归零）**：蓄能渐强音高（AUD-018）在 meter<20% 时停止播放——跳跃到 0% 触发立即停止。不播放"遗漏"的下降音高——直接静默。计量表满提示音（AUD-019）在 `meter_full` 信号时已触发，变身开始后不重复。

- **如果 UI 音效在设置系统关闭 SFX 的情况下触发**：UI 音效使用独立的 UI Bus（Bus 3），不受 SFX Bus 音量影响。设置系统可以通过 `AudioServer.set_bus_mute(AudioServer.get_bus_index("UI"), true)` 独立静音 UI 音效。若没有设置系统（MVP 阶段），UI 音效始终播放。

## Dependencies

### 上游依赖（硬依赖）

| 系统 | 依赖内容 |
|------|---------|
| 游戏状态管理 | 订阅 `state_changed` 信号——驱动 BGM 层切换和状态转换音效（变身三层、狂暴、冷却褪去、死亡） |
| 玩家系统 | 订阅 `player_hit`、`damage_dealt`、`player_died` 信号；查询 `hp_current`/`hp_max`（每帧，低 HP 心跳） |
| 变身系统 | 订阅 `transformation_started`、`transformation_expired`、`berserk_activated`、`berserk_expired`、`cooldown_complete`、`transformation_failed` 信号；查询 `current_form_id`（形态主题音色选择） |
| 波次系统 | 订阅 `wave_started`、`wave_cleared`、`boss_wave_started`、`all_waves_cleared` 信号 |
| 吸收系统 | 查询 `meter_current`（每帧）——驱动蓄能渐强音高和 BGM Layer 2/3 触发；订阅 `meter_full` ——蓄能满提示音 |

### 软依赖（尚未设计，预留接口）

| 系统 | 依赖内容 | 回退方案 |
|------|---------|---------|
| 敌人系统 | 订阅敌人死亡信号——触发敌人死亡音效；每 1s 查询敌人距离——触发接近警告音 | 跳过敌人死亡音效和接近警告——不影响核心玩法音频 |
| Boss 系统 | Boss 登场/死亡/阶段转换音效 | 待 Boss 系统 GDD 设计后补充 Audio 条目 |

### 下游依赖方

| 系统 | 依赖内容 |
|------|---------|
| 设置系统（Vertical Slice） | Audio 通过 4 条 Audio Bus 暴露音量控制——Music、SFX、UI、Voice。设置系统通过 `AudioServer.set_bus_volume_db()` 和 `set_bus_mute()` 调整 |
| VFX 系统 | 平行系统——两者响应同一信号源，确保听觉和视觉同步 |

### 接口契约

Audio 系统是叶子消费者节点——不向其他系统暴露主动接口。但它提供以下内部契约：

1. **总线音量控制**：暴露 4 条 Audio Bus (Music/SFX/UI/Voice) 到 AudioServer——设置系统通过标准 Godot API 调整，Audio 系统不需要自定义接口
2. **音频静音**：`set_muted(muted: bool)` ——当游戏窗口失去焦点或 GSM time_scale=0 时静音所有音频
3. **SFX 池状态查询**：`get_active_sfx_count() -> int` ——性能监控接口

## Tuning Knobs

| 参数 | 默认值 | 安全范围 | 影响 |
|------|--------|---------|------|
| `sfx_pool_size` | 8 | 6–16 | SFX 并发通道数。太少→频繁抢占/丢弃；太多→内存浪费 |
| `ui_pool_size` | 4 | 2–8 | UI 音效并发通道数 |
| `bgm_crossfade_duration` | 0.3s | 0.1–0.5s | BGM 层切换速度。太快→突然；太慢→响应迟钝 |
| `transform_sub_boom_freq` | 50 Hz | 30–80 Hz | 变身低频轰鸣频率。太低→普通音箱听不到；太高→失去"震撼"感 |
| `transform_sub_boom_attack` | 0.3s | 0.1–0.5s | 低频轰鸣 attack 时间 |
| `transform_sub_boom_decay` | 1.0s | 0.5–2.0s | 低频轰鸣 decay 时间 |
| `transform_tear_duration` | 0.1s | 0.05–0.2s | 高频撕裂音持续 |
| `meter_pitch_start_ratio` | 0.2 | 0.1–0.3 | 蓄能音高起始阈值（meter_ratio 低于此值不播放） |
| `meter_pitch_octave_range` | 2 (C2→C4) | 1–3 | 蓄能音高八度范围 |
| `meter_tremolo_start_ratio` | 0.8 | 0.7–0.9 | 蓄能 tremolo 起始阈值 |
| `heartbeat_hp_threshold` | 0.3 | 0.2–0.4 | 低 HP 心跳起始阈值 |
| `heartbeat_period_high` | 0.5s | 0.3–0.7s | 心跳最高间隔（HP 30%） |
| `heartbeat_period_low` | 0.3s | 0.2–0.4s | 心跳最低间隔（HP 0%） |
| `heartbeat_volume_max` | 0.7 | 0.5–0.9 | 心跳最大 alpha |
| `attack_pitch_randomization` | 0.05 (±5%) | 0.0–0.1 | 攻击音高随机偏差。太高→音高不一致；0→重复疲劳 |
| `enemy_death_max_concurrent` | 2 | 1–4 | 敌人死亡音效最大并发数 |
| `enemy_proximity_check_interval` | 1.0s | 0.5–2.0s | 敌人接近检查间隔 |
| `enemy_proximity_radius` | 100 px | 50–200 px | 敌人接近警告触发距离 |
| `berserk_overdrive_gain` | 3 dB | 1–6 dB | 狂暴时 Music bus overdrive 增益 |
| `death_bgm_fade_duration` | 3.0s | 2.0–5.0s | 死亡时 BGM fade out 时长 |
| `cooldown_bgm_fade_duration` | 1.0s | 0.5–2.0s | 冷却时 BGM 层退出的 crossfade 时长 |
| `meter_full_arp_duration` | 0.3s | 0.1–0.5s | 蓄能满提示音持续 |

## Visual/Audio Requirements

| # | 需求 | 约束来源 | 说明 |
|---|------|---------|------|
| AR-1 | 合成器音频美学——所有音效使用合成器生成（锯齿波/方波/正弦波 + 滤波 + 失真），避免高保真管弦乐或真实乐器采样 | Rule 8（像素艺术听觉美学） | 与像素艺术视觉风格一致——低保真、高冲击力 |
| AR-2 | 变身音频三层同步——Sub Boom + Form Signature + Tear 必须在 GSM `state_changed(_, TRANSFORMATION)` 的同一帧触发，三层之间的时间偏差 ≤ 1 帧（~17ms @ 60fps） | Rule 5, VR-7 (VFX GDD) | 与 VFX 的全屏闪光/撕裂同步 |
| AR-3 | 形态主题音色区分——Beast 和 Dragon 的变身音色必须有明显不同的音色特征，玩家闭眼也能分辨当前形态 | Rule 5 | Beast=锯齿波失真，Dragon=共振滤波扫频 |
| AR-4 | 低 HP 心跳不可被抢占——AUD-012 优先级为"高"，不可被"中"及以下优先级的音效抢占 | Rule 6 | 生理警告——心跳中断会削弱威胁感 |
| AR-5 | BGM 层连续播放——Layer 1 (Ambient) 在整个对局中持续循环，不因状态转换而停止。仅在对局结束（DEATH/通关）时 fade out | Rule 4 | 确保音乐连续性——没有"音乐停止→重新开始"的间隙 |
| AR-6 | SFX 池性能约束——8 通道 SFX 池 + 4 通道 UI 池的最大节点数为 12 个 AudioStreamPlayer，不在运行时创建/销毁节点 | Godot Audio 最佳实践 | 避免运行时内存分配和 GC 停顿 |
| AR-7 | 音频总线独立——Music、SFX、UI、Voice 四条总线在 AudioServer 中独立配置，音量调整互不影响 | Rule 2 | 为设置系统的独立音量控制预留接口 |

## UI Requirements

Audio 系统本身不产生 UI 元素——它是纯听觉输出。但它需要以下 UI 系统协调：

| # | 需求 | 说明 |
|---|------|------|
| UI-1 | 设置系统音量控制（Vertical Slice） | 设置系统提供 Music / SFX / UI / Voice 四条独立音量滑块——Audio 系统通过 `AudioServer.set_bus_volume_db()` 响应。MVP 阶段使用硬编码默认音量（0 dB），无音量设置 UI |
| UI-2 | 音频静音 on 失焦 | 游戏窗口失去焦点时（`NOTIFICATION_WM_WINDOW_FOCUS_OUT`），Audio 系统自动静音所有总线。恢复焦点时取消静音。不需要 UI——自动行为 |

## Acceptance Criteria

| # | 条件 | 期望结果 |
|---|------|---------|
| AC-1 | GIVEN GSM 进入 TRANSFORMATION 状态，WHEN `state_changed(_, TRANSFORMATION)` 发出 | THEN 变身三层音频（AUD-001 Sub Boom + AUD-002 Form Signature + AUD-003 Tear）同时触发，Sub Boom 频率约 50Hz、持续 ~1.3s（0.3s attack + 1.0s decay） |
| AC-2 | GIVEN 玩家处于 Beast 形态（`current_form_id = "beast"`），WHEN 变身触发 | THEN AUD-002 使用锯齿波失真合成器音色（100-400Hz sweep） |
| AC-3 | GIVEN 玩家处于 Dragon 形态（`current_form_id = "dragon"`），WHEN 变身触发 | THEN AUD-002 使用共振滤波扫频音色（200→2000Hz） |
| AC-4 | GIVEN GSM 进入 COOLDOWN 状态，WHEN `state_changed(_, COOLDOWN)` 发出 | THEN BGM Layer 3 + 4 在 1.0s 内 fade out，持续低频嗡声立即停止，形态褪去反向音效播放 |
| AC-5 | GIVEN 玩家处于 Beast TRANSFORMATION，WHEN `damage_dealt` 信号触发 | THEN 播放 AUD-008——~80Hz "咚"声，0.3s 持续，每次攻击音高 ±5% 随机偏差 |
| AC-6 | GIVEN 玩家被敌人击中，WHEN `player_hit` 信号触发 | THEN 播放 AUD-011——~2kHz 短促方波警告音（0.05s），与 VFX-011 受击白闪在同一帧 |
| AC-7 | GIVEN 玩家 HP ≤ 30%，WHEN 每帧检查 hp_ratio | THEN AUD-012 低 HP 心跳播放——HP 30% 时间隔 0.5s/volume 0.3，HP <15% 时间隔 0.3s/volume 0.7 |
| AC-8 | GIVEN 吸收系统 `meter_current` 从 20% 上升至 100%，WHEN 每帧检查 | THEN AUD-018 蓄能音高从 20% 对应音高连续升至 100% 对应音高（C2→C4），音量 alpha 0→0.3 |
| AC-9 | GIVEN SFX 池 8 通道全满且均为"中"优先级，WHEN 新的"高"优先级受击音请求到达 | THEN 最老的"中"优先级音频被抢占停止，释放的通道分配给受击音 |
| AC-10 | GIVEN SFX 池 8 通道全满且均为"最高"优先级，WHEN 新的任何优先级音效请求到达 | THEN 新请求被静默丢弃，控制台打印 pool exhausted warning |
| AC-11 | GIVEN BGM Layer 2 在 0.3s crossfade 期间（t=0.15s），WHEN GSM 触发新的状态转换需要不同的层配置 | THEN 当前 crossfade 被中断，新目标音量设为当前值，立即开始新的 0.3s crossfade |
| AC-12 | GIVEN AUD-012 低 HP 心跳播放中，WHEN 玩家 HP 恢复到 >30%（如拾取回血） | THEN 心跳在当前周期完成后停止（不立即中断），SFX 通道回收 |

## Open Questions

| # | 问题 | 影响 | 建议方向 |
|---|------|------|---------|
| OQ-1 | BGM 分层音频轨由谁制作？4 层（Ambient + Bassline + Percussion + Lead）需要 4 个独立音频文件，需要作曲家按同调性、同 tempo、同结构制作 | 音频生产管线——需要外部音频资源，Solo 开发可能需要购买/委托 | MVP 可使用免费合成器生成简单音频层（如用 Bosca Ceoil 或 jsfxr 生成 loop），Vertical Slice 阶段委托作曲家 |
| OQ-2 | 音频资源格式——Godot 4.6 推荐 Ogg Vorbis（有损压缩）还是 WAV（无损）？ | 包体大小 vs 音频质量——WAV 文件大但加载快，Ogg 文件小但需要 CPU 解码 | SFX 使用 WAV（短文件，加载快，包体影响小）；BGM 使用 Ogg Vorbis（长文件，压缩显著减小包体）。Godot 4.6 支持两种格式 |
| OQ-3 | 是否需要 3D 定位音频（AudioStreamPlayer2D）用于敌人接近/攻击方向？ | 游戏性——玩家能否通过听觉判断敌人位置 | MVP 使用纯 2D 音频（AudioStreamPlayer）——屏幕范围内的敌人不需要空间定位。若 playtest 发现需要空间感知，Vertical Slice 中迁移至 AudioStreamPlayer2D |
| OQ-4 | 低频轰鸣（Sub Boom ~50Hz）在普通笔记本音箱/移动设备上能否被感知？ | 可及性——大部分玩家没有 subwoofer | 为低频叠加谐波（100Hz 第二谐波 + 150Hz 第三谐波）——即使基频听不到，谐波仍能传达"重量感"。sub 频段的物理震动效果仅在 subwoofer/好耳机上可感知——这是可接受的渐进增强 |
| OQ-5 | UI 音效（AUD-023）是否在 MVP 阶段需要？ | 范围——MVP 的 HUD 和升级界面是否需要 UI 交互音效 | MVP 实现最少 UI 音效——仅按钮 click 和升级选择确认音（最关键的 UI 反馈）。hover 音效和菜单开关音效可推迟至 Vertical Slice |
