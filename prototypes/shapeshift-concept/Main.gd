# PROTOTYPE - NOT FOR PRODUCTION
# Question: Does the "charge → transform → release" rhythm create satisfying power release?
# Date: 2026-05-23

extends Node2D

const SPAWN_INTERVAL = 2.0
const MAX_ENEMIES = 20

var spawn_timer: float = 0.0

@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera2D

func _ready():
	# Player setup
	player.add_to_group("player")
	# Make camera follow player
	camera.make_current()

	# UI setup
	setup_ui()

func _process(delta):
	# Spawn enemies
	spawn_timer -= delta
	if spawn_timer <= 0:
		spawn_enemy()
		spawn_timer = SPAWN_INTERVAL

	# Cleanup form points that were collected
	for point in get_tree().get_nodes_in_group("form_points"):
		if not point or not is_instance_valid(point):
			continue

func setup_ui():
	# Create canvas layer
	var canvas = CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	# Instructions
	var instructions = Label.new()
	instructions.text = "WASD: Move | SPACE: Transform (when bar is full)"
	instructions.position = Vector2(10, 10)
	instructions.theme_type_variation = "HeaderSmall"
	canvas.add_child(instructions)

func spawn_enemy():
	var enemies = get_tree().get_nodes_in_group("enemies")
	if enemies.size() >= MAX_ENEMIES:
		return

	# Spawn at random edge of screen
	var spawn_pos = Vector2.ZERO
	var side = randi() % 4

	match side:
		0:  # Top
			spawn_pos = Vector2(randf() * 1280, -50)
		1:  # Right
			spawn_pos = Vector2(1330, randf() * 720)
		2:  # Bottom
			spawn_pos = Vector2(randf() * 1280, 770)
		3:  # Left
			spawn_pos = Vector2(-50, randf() * 720)

	# Create enemy
	var enemy_scene = preload("res://Enemy.tscn")
	var enemy = enemy_scene.instantiate()
	enemy.position = spawn_pos
	enemy.add_to_group("enemies")
	add_child(enemy)
