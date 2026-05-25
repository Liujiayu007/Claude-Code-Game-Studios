extends Area2D
class_name Enemy

## Enemy AI — moves toward player, takes damage, drops form points on death.
## Reads stats from DataConfig via enemy_id lookup.

@export var enemy_id: String = "slime"

var health: float
var _speed: float
var _damage: int
var _form_points_drop: int
var _player_ref: Player

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _flash_timer: float = 0.0
var _is_flashing: bool = false


func _ready() -> void:
	add_to_group("enemies")
	_make_placeholder_texture()
	_load_config()
	_player_ref = get_tree().get_first_node_in_group("player") as Player


func _make_placeholder_texture() -> void:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(img)


func _load_config() -> void:
	var cfg := DataConfig.get_enemy_config(enemy_id)
	if cfg:
		health = float(cfg.hp)
		_speed = cfg.speed
		_damage = cfg.damage
		_form_points_drop = cfg.form_points_drop
	else:
		health = 30.0
		_speed = 80.0
		_damage = 10
		_form_points_drop = 10


func _physics_process(delta: float) -> void:
	if _is_flashing:
		_flash_timer -= delta
		if _flash_timer <= 0:
			_is_flashing = false
			sprite.modulate = Color(1, 0.5, 0.5)
	if not _player_ref or not is_instance_valid(_player_ref):
		return
	var direction := (_player_ref.global_position - global_position).normalized()
	position += direction * _speed * delta


func take_damage(amount: float) -> void:
	health -= amount
	_is_flashing = true
	_flash_timer = 0.1
	sprite.modulate = Color.WHITE

	if health <= 0:
		_die()


func _die() -> void:
	_drop_form_point()
	queue_free()


func _drop_form_point() -> void:
	var point := Area2D.new()
	point.name = "FormPoint"
	point.position = position
	point.collision_layer = 0
	point.collision_mask = 1

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	col.shape = shape
	point.add_child(col)

	var vis := Node2D.new()
	vis.name = "Visual"
	var vis_script := GDScript.new()
	vis_script.source_code = """extends Node2D
func _draw():
	draw_colored_polygon(PackedVector2Array([Vector2(0, -6), Vector2(6, 0), Vector2(0, 6), Vector2(-6, 0)]), Color(0.2, 0.9, 0.2))
"""
	vis_script.reload()
	vis.set_script(vis_script)
	point.add_child(vis)

	point.add_to_group("form_points")
	var drop_value := _form_points_drop
	point.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"):
			body.add_form_points(drop_value)
			point.queue_free()
	)
	get_parent().add_child(point)

	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(point):
		point.queue_free()
