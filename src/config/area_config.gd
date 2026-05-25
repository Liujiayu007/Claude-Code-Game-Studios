class_name AreaConfig
extends Resource

## 区域定义 —— 定义一个游戏区域的全部参数
## Used by: AreaSystem
## GDD ref: area-system.md, data-config.md Tuning Knobs

@export var area_id: String = ""
@export var area_name: String = ""

@export var enemy_pool: Array[String] = []  # 该区域可用的 enemy_id 列表
@export var boss_id: String = ""
@export var bgm_id: String = ""

@export var background_tileset: TileSet
