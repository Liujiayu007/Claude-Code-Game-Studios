# Epic: Input System (输入系统)

> **Layer**: Foundation
> **GDD**: design/gdd/input-system.md
> **Architecture Module**: InputSystem Autoload (#3)
> **Status**: Ready
> **Stories**: Not yet created — run `/create-stories input-system`

## Overview

实现 InputSystem Autoload 单例——Godot 内建 `InputMap` 和 `Input` 单例之上的薄抽象层。核心职责：(1) 统一输入查询接口——其他系统调用 `InputSystem.is_action("move_left")` 而非直接检查 `Input.is_key_pressed(KEY_A)`，使键位重绑定和手柄支持成为可能；(2) 150ms 输入缓冲窗口（`is_action_buffered()`）——变身等关键动作在按下后 150ms 内持续有效，避免因帧时机偏差导致"按了但没反应"；(3) GSM 状态驱动的输入屏蔽——查询 GSM 的 `current_state`，在 UPGRADE 和 DEATH 状态下自动过滤移动和攻击输入，仅保留 UI 导航（`ui_up/down/left/right`、`confirm`、`cancel`）；(4) 动态按键标签——`get_action_label("transform_activate")` 从 InputMap 读取当前绑定按键并返回可读文本，支持变身提示中的动态按键显示。Autoload #3，在 DataConfig (#1) 和 GSM (#2) 之后初始化。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0006: Input System Architecture | 薄抽象层：移动用 Input.get_vector() 直连，离散动作通过 InputSystem.is_action_buffered() 获得 150ms 缓冲窗口，GSM 驱动输入屏蔽 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-INP-001 | Input Map 中 8 个核心动作全部注册完毕 | ADR-0006 |
| TR-INP-002 | is_action("move_up") 在按下时返回 true, 松开后返回 false | ADR-0006 |
| TR-INP-003 | is_action_buffered("transform_activate") 按下后 150ms 内持续返回 true | ADR-0006 |
| TR-INP-004 | DEATH 状态下移动/攻击动作被屏蔽，仅 ui_* 动作有效 | ADR-0006 |
| TR-INP-005 | UPGRADE 状态下移动/攻击/变身动作被屏蔽，仅 ui_* 动作有效 | ADR-0006 |
| TR-INP-006 | get_action_label("transform_activate") 返回当前绑定按键名 | ADR-0006 |
| TR-INP-007 | 改键后 get_action_label 下一帧返回更新后的按键名 | ADR-0006 |
| TR-INP-008 | 手柄插入/拔出时输入设备自动切换，不丢帧 | ADR-0006 |
| TR-INP-009 | get_move_vector() 对手柄摇杆应用 0.15 死区 | ADR-0006 |
| TR-INP-010 | UI 导航动作始终有效（不受 GSM 状态屏蔽） | ADR-0006 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All 10 acceptance criteria from `design/gdd/input-system.md` are verified
- All Logic and Integration stories have passing test files in `tests/unit/input_system/`
- 8 个核心 Input Map 动作全部注册（move_up/down/left/right, transform_activate, confirm, cancel, pause）
- 输入缓冲系统通过快速连按场景测试
- GSM 状态屏蔽通过 DEATH/UPGRADE 状态下按键无效验证

## Next Step

Run `/create-stories input-system` to break this epic into implementable stories.
