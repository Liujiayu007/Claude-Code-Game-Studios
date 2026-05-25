# Epic: Data Config (数据配置系统)

> **Layer**: Foundation
> **GDD**: design/gdd/data-config.md
> **Architecture Module**: DataConfig Autoload (#1)
> **Status**: Ready
> **Stories**: 4 stories (2 Logic + 1 Config/Data + 1 Integration)

## Stories

| # | Story | Type | Status | ADR |
|---|-------|------|--------|-----|
| 001 | Resource Class Definitions | Config/Data | Ready | ADR-0005 |
| 002 | DataConfig Core — Loading & Access | Logic | Ready | ADR-0005 |
| 003 | Validation System | Logic | Ready | ADR-0005 |
| 004 | Editor Hot Reload & Export Behavior | Integration | Ready | ADR-0005 |

## Overview

实现 DataConfig Autoload 单例——游戏中所有可调数值和静态数据表的单一真相源（Single Source of Truth）。该系统采用两层架构：Tier 1（80% 的配置）使用 `@export var` 标量属性直接在 `DataConfig.gd` 上定义，按系统分组，在 Godot Inspector 中即时编辑；Tier 2（20% 的配置）使用 Custom Resource 类（FormConfig / WaveTable / EnemyConfig / AreaConfig）处理多字段结构化数据。所有配置在 `_ready()` 中一次性加载至字典缓存，运行期间只读。提供强类型访问器方法，包含越界保护和缺失文件回退。必须在所有其他 Autoload（Autoload #1）之前完成初始化。

## Governing ADRs

| ADR | Decision Summary | Engine Risk |
|-----|-----------------|-------------|
| ADR-0005: Data Configuration Architecture | 两层架构：@export var 标量 + Custom Resource 结构化数据。DataConfig Autoload #1，所有系统通过 `DataConfig.get_xxx()` 查询。 | LOW |

## GDD Requirements

| TR-ID | Requirement | ADR Coverage |
|-------|-------------|--------------|
| TR-DC-001 | 启动时所有.tres完整有效，所有访问器返回非空值，加载<50ms | ADR-0005 |
| TR-DC-002 | 有效key查询返回正确Resource实例，字段值符合预期 | ADR-0005 |
| TR-DC-003 | 不存在的key查询返回默认Resource实例并打印warning日志 | ADR-0005 |
| TR-DC-004 | 配置值越界时自动clamp到有效范围并打印warning日志 | ADR-0005 |
| TR-DC-005 | 编辑器热重载：修改.tres保存后查询返回更新值 | ADR-0005 |
| TR-DC-006 | 导出构建中返回与编辑器相同的配置值，运行时磁盘修改不影响游戏 | ADR-0005 |
| TR-DC-007 | 缺少.tres文件时游戏正常启动不崩溃，返回默认实例+error日志 | ADR-0005 |
| TR-DC-008 | 两个.tres声明相同id时后加载覆盖前者+duplicate key warning | ADR-0005 |
| TR-DC-009 | Config在任意其他Autoload的_ready()之前完成加载 | ADR-0005 |
| TR-DC-010 | 连续60秒每帧查询不成为性能瓶颈，单次查询<0.01ms | ADR-0005 |
| TR-DC-011 | Resource引用字段验证：引用存在则通过，不存在则warning+使用默认引用 | ADR-0005 |

## Definition of Done

This epic is complete when:
- All stories are implemented, reviewed, and closed via `/story-done`
- All 11 acceptance criteria from `design/gdd/data-config.md` are verified
- All Logic and Integration stories have passing test files in `tests/unit/data_config/`
- All Config Resource 子类（FormConfig / WaveTable / EnemyConfig / AreaConfig / 默认 Resource）已创建并可加载

## Next Step

Run `/create-stories data-config` to break this epic into implementable stories.
