class_name WaveEntry
extends Resource

## 单波定义 —— WaveTable 中的一行
## Used by: WaveTable, WaveSystem
## GDD ref: wave-system.md

@export var wave_number: int = 1
@export var enemy_count: int = 10
@export var enemy_types: Array[String] = []  # enemy_id 列表
@export_range(0.1, 10.0) var spawn_interval: float = 1.0
