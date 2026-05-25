// PROTOTYPE - NOT FOR PRODUCTION
// Question: Does the "charge → transform → release" rhythm create satisfying power release?
// Date: 2026-05-23

extends CharacterBody2D

# Transformation settings
const TRANSFORM_DURATION = 10.0  # Seconds
const TRANSFORM_COOLDOWN = 15.0  # Seconds after form ends
const MAX_FORM_POINTS = 100.0

# Combat settings
const HUMAN_ATTACK_RANGE = 150.0
const HUMAN_ATTACK_DAMAGE = 10.0
const HUMAN_ATTACK_COOLDOWN = 0.5
const MONSTER_ATTACK_RANGE = 300.0
const MONSTER_ATTACK_DAMAGE = 50.0
const MONSTER_ATTACK_COOLDOWN = 0.3
const MONSTER_ATTACK_SPREAD = 0.5  # Wide area attack

# State
var form_points: float = 0.0
var is_transformed: bool = false
var transform_timer: float = 0.0
var cooldown_timer: float = 0.0
var attack_timer: float = 0.0

# Movement
const SPEED = 200.0

# References
@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $AttackArea
@onready var cooldown_bar: ProgressBar = $CooldownBar
@onready var transform_bar: ProgressBar = $TransformBar

func _ready():
    # Initial setup
    update_visuals()
    area.monitoring = false

func _physics_process(delta):
    # Handle movement
    var direction = Vector2.ZERO
    if Input.is_action_pressed("move_left"):
        direction.x -= 1
    if Input.is_action_pressed("move_right"):
        direction.x += 1
    if Input.is_action_pressed("move_up"):
        direction.y -= 1
    if Input.is_action_pressed("move_down"):
        direction.y += 1

    velocity = direction.normalized() * SPEED
    move_and_slide()

    # Handle attack cooldown
    if attack_timer > 0:
        attack_timer -= delta
    elif attack_timer <= 0:
        auto_attack()
        attack_timer = HUMAN_ATTACK_COOLDOWN if not is_transformed else MONSTER_ATTACK_COOLDOWN

    # Handle transformation
    if Input.is_action_just_pressed("transform") and can_transform():
        activate_transform()

    # Handle transformed state timer
    if is_transformed:
        transform_timer -= delta
        if transform_timer <= 0:
            deactivate_transform()
    else:
        # Handle cooldown
        if cooldown_timer > 0:
            cooldown_timer -= delta

    # Update UI
    update_ui()

func can_transform() -> bool:
    return form_points >= MAX_FORM_POINTS and not is_transformed and cooldown_timer <= 0

func activate_transform():
    is_transformed = true
    form_points = 0.0
    transform_timer = TRANSFORM_DURATION
    update_visuals()

    # Wide area attack on transform
    perform_monster_attack()

    # Screen flash effect (placeholder)
    get_tree().get_root().modulate = Color(1, 1, 1, 0.8)
    await get_tree().create_timer(0.1).timeout
    get_tree().get_root().modulate = Color(1, 1, 1, 1.0)

func deactivate_transform():
    is_transformed = false
    cooldown_timer = TRANSFORM_COOLDOWN
    update_visuals()

func auto_attack():
    if is_transformed:
        # Monster form: automatic wide area attack
        perform_monster_attack()
    else:
        # Human form: single target attack
        perform_human_attack()

func perform_human_attack():
    var attack_range = HUMAN_ATTACK_RANGE
    var closest_enemy = find_closest_enemy(attack_range)

    if closest_enemy:
        # Deal damage (visual feedback with ray)
        closest_enemy.take_damage(HUMAN_ATTACK_DAMAGE)

func perform_monster_attack():
    # Wide area attack
    var attack_range = MONSTER_ATTACK_RANGE
    var enemies = get_tree().get_nodes_in_group("enemies")

    for enemy in enemies:
        if global_position.distance_to(enemy.global_position) <= attack_range:
            enemy.take_damage(MONSTER_ATTACK_DAMAGE)

    # Visual feedback (screen shake placeholder)
    # TODO: Add particle effects

func find_closest_enemy(range_limit: float) -> Node2D:
    var enemies = get_tree().get_nodes_in_group("enemies")
    var closest: Node2D = null
    var closest_dist: float = range_limit

    for enemy in enemies:
        var dist = global_position.distance_to(enemy.global_position)
        if dist < closest_dist:
            closest_dist = dist
            closest = enemy

    return closest

func add_form_points(amount: float):
    form_points = min(form_points + amount, MAX_FORM_POINTS)

func update_visuals():
    if is_transformed:
        sprite.modulate = Color(1.0, 0.0, 0.0)  # Red for monster form
        scale = Vector2(1.5, 1.5)
    else:
        sprite.modulate = Color(0.5, 0.5, 1.0)  # Blue for human form
        scale = Vector2(1.0, 1.0)

func update_ui():
    if is_transformed:
        transform_bar.value = (transform_timer / TRANSFORM_DURATION) * 100
        transform_bar.show()
        cooldown_bar.hide()
    else:
        if cooldown_timer > 0:
            cooldown_bar.value = (1.0 - (cooldown_timer / TRANSFORM_COOLDOWN)) * 100
            cooldown_bar.show()
            transform_bar.hide()
        else:
            transform_bar.value = (form_points / MAX_FORM_POINTS) * 100
            transform_bar.show()
            cooldown_bar.hide()