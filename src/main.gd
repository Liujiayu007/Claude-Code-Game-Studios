extends Node2D

## Main scene — manages enemy spawning and game loop.

const MAX_ENEMIES: int = 20

var _spawn_timer: float = 0.0
var _spawn_interval: float = 2.0
var _enemy_scene: PackedScene = preload("res://src/enemy/Enemy.tscn")

@onready var player: Player = $Player
@onready var camera: Camera2D = $Camera2D


func _ready() -> void:
	camera.position = Vector2(640, 360)
	_setup_hud()


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0:
		_try_spawn_enemy()
		_spawn_timer = _spawn_interval


func _try_spawn_enemy() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() >= MAX_ENEMIES:
		return

	var spawn_pos: Vector2
	var side := randi() % 4
	match side:
		0: spawn_pos = Vector2(randf() * 1280, -50)
		1: spawn_pos = Vector2(1330, randf() * 720)
		2: spawn_pos = Vector2(randf() * 1280, 770)
		3: spawn_pos = Vector2(-50, randf() * 720)

	var enemy := _enemy_scene.instantiate()
	enemy.position = spawn_pos
	add_child(enemy)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUDLayer"
	add_child(canvas)

	var label := Label.new()
	label.text = "WASD: Move | SPACE: Transform (when bar full)"
	label.position = Vector2(10, 10)
	canvas.add_child(label)
