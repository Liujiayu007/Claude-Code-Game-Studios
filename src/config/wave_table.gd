class_name WaveTable
extends Resource

## 波次表 —— 定义一个区域全部波次的配置
## Used by: WaveSystem
## GDD ref: wave-system.md, data-config.md Tuning Knobs

@export var table_id: String = ""
@export var area_id: String = ""
@export var entries: Array[WaveEntry] = []
