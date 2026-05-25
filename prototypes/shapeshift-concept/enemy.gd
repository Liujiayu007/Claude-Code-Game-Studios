# PROTOTYPE - NOT FOR PRODUCTION
# Question: Does the "charge → transform → release" rhythm create satisfying power release?
# Date: 2026-05-23

extends Area2D

const MAX_HEALTH = 30.0
const SPEED = 80.0
const FORM_POINTS_VALUE = 10.0

var health: float = MAX_HEALTH
var player_ref: Node2D = null

@onready var visual: ColorRect = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	player_ref = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	if not player_ref:
		return

	# Move toward player
	var direction = (player_ref.global_position - global_position).normalized()
	position += direction * SPEED * delta

func take_damage(amount: float):
	health -= amount

	# Visual feedback - flash white
	visual.color = Color.WHITE
	await get_tree().create_timer(0.1).timeout
	visual.color = Color(1, 0.5, 0.5, 1)

	if health <= 0:
		die()

func die():
	# Drop form point
	drop_form_point()

	# Remove self
	queue_free()

func drop_form_point():
	# Create form point pickup
	var form_point = Area2D.new()
	form_point.name = "FormPoint"
	form_point.position = position

	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 15.0
	collision.shape = shape
	form_point.add_child(collision)

	form_point.add_to_group("form_points")

	# Self-contained pickup via lambda — enemy may be dead when pickup occurs
	form_point.body_entered.connect(func(body: Node2D):
		if body.is_in_group("player"):
			body.add_form_points(FORM_POINTS_VALUE)
			form_point.queue_free()
	)

	get_parent().add_child(form_point)

	# Auto-remove after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(form_point):
		form_point.queue_free()
