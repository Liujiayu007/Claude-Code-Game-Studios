extends CharacterBody2D
class_name Player

## Player controller — WASD movement, auto-attack, form transformation.
## Reads base stats from DataConfig autoload.

# ─── Form state ───
var form_points: float = 0.0
var is_transformed: bool = false
var transform_timer: float = 0.0
var cooldown_timer: float = 0.0
var attack_timer: float = 0.0

const MAX_FORM_POINTS: float = 100.0

# ─── Cached config refs ───
var _human_form: FormConfig
var _monster_form: FormConfig

@onready var sprite: Sprite2D = $Sprite2D
@onready var transform_bar: ProgressBar = $TransformBar
@onready var cooldown_bar: ProgressBar = $CooldownBar


func _ready() -> void:
	add_to_group("player")
	_make_placeholder_texture()
	_load_config()
	_setup_hud()
	_update_sprite()


func _make_placeholder_texture() -> void:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(img)


func _setup_hud() -> void:
	var tf_style := StyleBoxFlat.new()
	tf_style.bg_color = Color(0.3, 0.5, 1.0)
	transform_bar.add_theme_stylebox_override("fill", tf_style)
	var cd_style := StyleBoxFlat.new()
	cd_style.bg_color = Color(0.5, 0.5, 0.5)
	cooldown_bar.add_theme_stylebox_override("fill", cd_style)


func _load_config() -> void:
	_human_form = DataConfig.get_form_config("default")
	_monster_form = DataConfig.get_form_config("default")
	if not _human_form:
		_human_form = FormConfig.new()
		_human_form.form_id = "default"
		_human_form.duration_seconds = 10.0
		_human_form.cooldown_seconds = 15.0
		_human_form.hp_multiplier = 1.0
		_human_form.speed_multiplier = 1.0
		_human_form.damage_multiplier = 1.0
	if not _monster_form:
		_monster_form = _human_form


func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_attack(delta)
	_handle_transform_input()
	_handle_transform_timers(delta)
	_update_hud()


func _handle_movement(_delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1

	velocity = direction.normalized() * DataConfig.base_move_speed
	move_and_slide()


func _handle_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0:
		return

	if is_transformed:
		_perform_monster_attack()
		attack_timer = 0.3
	else:
		_perform_human_attack()
		attack_timer = 0.5


func _handle_transform_input() -> void:
	if Input.is_action_just_pressed("transform") and _can_transform():
		_activate_transform()


func _handle_transform_timers(delta: float) -> void:
	if is_transformed:
		transform_timer -= delta
		if transform_timer <= 0:
			_deactivate_transform()
	elif cooldown_timer > 0:
		cooldown_timer -= delta


func _can_transform() -> bool:
	return form_points >= MAX_FORM_POINTS and not is_transformed and cooldown_timer <= 0


func _activate_transform() -> void:
	is_transformed = true
	form_points = 0.0
	transform_timer = _monster_form.duration_seconds
	_update_sprite()
	_perform_monster_attack()
	_screen_flash()


func _screen_flash() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ScreenFlash"
	canvas.layer = 100
	add_child(canvas)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(1, 1, 1, 0.3)
	canvas.add_child(rect)
	await get_tree().create_timer(0.1).timeout
	canvas.queue_free()


func _deactivate_transform() -> void:
	is_transformed = false
	cooldown_timer = _monster_form.cooldown_seconds
	_update_sprite()


func _perform_human_attack() -> void:
	var closest := _find_closest_enemy(150.0)
	if closest:
		closest.take_damage(10.0)


func _perform_monster_attack() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if global_position.distance_to(enemy.global_position) <= 300.0:
			enemy.take_damage(50.0)


func _find_closest_enemy(range_limit: float) -> Node2D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var closest: Node2D = null
	var closest_dist := range_limit
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = enemy
	return closest


func add_form_points(amount: float) -> void:
	form_points = minf(form_points + amount, MAX_FORM_POINTS)


func _update_sprite() -> void:
	if is_transformed:
		sprite.modulate = Color(1.0, 0.2, 0.2)
		sprite.scale = Vector2(1.5, 1.5)
	else:
		sprite.modulate = Color(0.3, 0.5, 1.0)
		sprite.scale = Vector2(1.0, 1.0)


func _update_hud() -> void:
	if is_transformed:
		transform_bar.value = (transform_timer / _monster_form.duration_seconds) * 100
		transform_bar.visible = true
		cooldown_bar.visible = false
	elif cooldown_timer > 0:
		cooldown_bar.value = (1.0 - (cooldown_timer / _monster_form.cooldown_seconds)) * 100
		cooldown_bar.visible = true
		transform_bar.visible = false
	else:
		transform_bar.value = (form_points / MAX_FORM_POINTS) * 100
		transform_bar.visible = true
		cooldown_bar.visible = false
