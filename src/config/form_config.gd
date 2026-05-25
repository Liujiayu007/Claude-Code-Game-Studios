class_name FormConfig
extends Resource

## 形态定义 —— 定义一种怪物形态的全部参数
## Used by: TransformationSystem, VFX, Audio, HUD
## GDD ref: data-config.md Tuning Knobs / transformation-system.md

@export var form_id: String = ""
@export var form_name: String = ""

@export_range(0.1, 10.0) var hp_multiplier: float = 1.0
@export_range(0.1, 10.0) var speed_multiplier: float = 1.0
@export_range(0.1, 10.0) var damage_multiplier: float = 1.0

@export_range(1.0, 60.0) var duration_seconds: float = 8.0
@export_range(1.0, 120.0) var cooldown_seconds: float = 15.0

@export var primary_color: Color = Color(0.91, 0.36, 0.23)  # Beast orange-red
@export var unlock_wave: int = 0
@export var audio_form_signature: AudioStream
