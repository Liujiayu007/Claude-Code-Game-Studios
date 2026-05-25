# Epic: Game State Manager (游戏状态管理)

> **Layer**: Foundation
> **GDD**: design/gdd/game-state-manager.md
> **Architecture Module**: GSM Autoload (#2)
> **Status**: Ready
> **Stories**: Not yet created — run `/create-stories game-state-manager`

## Overview

实现 GSM (Game State Manager) Autoload 单例——全局 8 状态枚举状态机，是整个游戏流程的中央编排点。8 个状态覆盖完整的"蓄能→爆发"循环：EXPLORATION（探索）、CHARGING（蓄能）、TRANSFORMATION（变身）、BERSERK（狂暴）、COOLDOWN（冷却）、UPGRADE（升级）、BOSS（Boss 战）、DEATH（死亡）。核心机制包括：(1) 显式 8×8 转换矩阵——仅允许预定义的状态转换，非法转换返回 false + error 日志；(2) 优先级冲突解决系统——DEATH(8) > BOSS(7) > UPGRADE(6) > TRANSFORMATION(5) > BERSERK(4) > COOLDOWN(3) > CHARGING(2) > EXPLORATION(1)，同帧多请求按优先级选择；(3) 阻塞标志系统——允许系统注册临时阻塞（如 Boss 登场期间阻止升级）；(4) `time_scale` 管理——UPGRADE/DEATH 状态下 time_scale=0 暂停游戏时间；(5) `state_changed(old, new)` 信号——11 个系统订阅此信号切换行为模式。Autoload #2，在 DataConfig 之后、所有其他系统之前初始化。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0007: Game State Machine Architecture | 8 状态 enum 状态机 + 8×8 显式转换矩阵 + 优先级系统 + 阻塞标志。GSM 拥有状态定义和转换规则，各系统拥有自己的按状态行为。 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-GSM-001 | 初始化完成后 current_state=EXPLORATION, time_scale=1.0 | ADR-0007 |
| TR-GSM-002 | 合法状态转换返回true，状态变更，state_changed信号发出 | ADR-0007 |
| TR-GSM-003 | 非法状态转换返回false，状态不变，打印error日志 | ADR-0007 |
| TR-GSM-004 | 阻塞标志激活时合法转换请求被拒绝，返回false+warning | ADR-0007 |
| TR-GSM-005 | CHARGING超时无击杀→计量表衰减至0→自动转EXPLORATION | ADR-0007 |
| TR-GSM-006 | 同帧多转换请求按优先级解决，仅执行最高优先级 | ADR-0007 |
| TR-GSM-007 | UPGRADE状态下time_scale=0 | ADR-0007 |
| TR-GSM-008 | TRANSFORMATION期间计量表再满→自动转BERSERK | ADR-0007 |
| TR-GSM-009 | TRANSFORMATION持续时间到期→转COOLDOWN | ADR-0007 |
| TR-GSM-010 | TRANSFORMATION期间HP=0→立即转DEATH，放弃变身计时器 | ADR-0007 |
| TR-GSM-011 | reset() 重置为EXPLORATION，清空blocks，不发射state_changed | ADR-0007 |
| TR-GSM-012 | 运行60秒+20次转换后无错误日志，所有转换通过合法白名单 | ADR-0007 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All 12 acceptance criteria from `design/gdd/game-state-manager.md` are verified
- All Logic and Integration stories have passing test files in `tests/unit/gsm/`
- 8 状态枚举定义完毕，8×8 转换矩阵全部实现
- 优先级冲突解决系统通过同帧多请求场景测试
- 阻塞标志系统通过 Boss 登场阻止升级场景测试

## Next Step

Run `/create-stories game-state-manager` to break this epic into implementable stories.
