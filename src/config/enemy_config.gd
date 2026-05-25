class_name EnemyConfig
extends Resource

## 敌人类型定义 —— 定义一种敌人的全部属性
## Used by: EnemySystem
## GDD ref: enemy-system.md, data-config.md Tuning Knobs

@export var enemy_id: String = ""
@export var display_name: String = ""

@export_range(1, 9999) var hp: int = 10
@export_range(10.0, 500.0) var speed: float = 100.0
@export_range(1, 9999) var damage: int = 5
@export_range(0, 100) var form_points_drop: int = 1

@export_enum("none", "slime_pop", "dust_puff", "bone_shatter") var death_particle_type: String = "slime_pop"
