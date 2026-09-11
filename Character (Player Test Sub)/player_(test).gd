extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 15.0
@export var acceleration := 15.0
@export var jump_velocity := 5.0

@export var slide_speed := 20.0
@export var slide_duration := 5.0

@export var grapple_range := 30.0
@export var grapple_duration := 1.4
@export var grapple_accel := 30.0
@export var grapple_cancel_distance := 1.0
@export var grapple_cooldown := 0.4
@export_range(0.0, 1.0, 0.01) var max_grapple_slope := 0.4

var is_sliding := false
var slide_timer := 5
var slide_direction := Vector3.ZERO

var is_grappled := false
var grapple_timer := 0.0
var grapple_target := Vector3.ZERO
var _grapple_cooldown_timer := 0.0

@onready var camera_settings := $"Camera Settings"
@onready var crosshair: TextureRect = $UI/Crosshair

func _physics_process(delta):
	_grapple_cooldown_timer = maxf(0.0, _grapple_cooldown_timer - delta)

	# Update crosshair — show green when a valid grapple target is in range
	if not is_grappled:
		crosshair.set_valid_target(is_grapplable(raycast_grapple()))

	if is_grappled:
		update_grapple(delta)
		move_and_slide()
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_sliding:
		velocity.y = jump_velocity

	# Start grapple
	if Input.is_action_just_pressed("grapple"):
		if try_start_grapple():
			move_and_slide()
			return

	# Start slide
	if Input.is_action_just_pressed("slide") and is_on_floor() and is_sprinting():
		start_slide()

	# Sliding
	if is_sliding:
		update_slide(delta)
		move_and_slide()
		return

	# Movement input
	var input_dir := Input.get_vector(
		"left",
		"right",
		"up",
		"down",
	)   

	var direction := Vector3(input_dir.x, 0, input_dir.y)

	# Convert input relative to player
	direction = transform.basis * direction
	direction.y = 0
	direction = direction.normalized()

	# Sprint or walk
	var target_speed := sprint_speed if is_sprinting() else walk_speed

	if direction:
		velocity.x = move_toward(
			velocity.x,
			direction.x * target_speed,
			acceleration * delta
		)
		velocity.z = move_toward(
			velocity.z,
			direction.z * target_speed,
			acceleration * delta
		)
	else:
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)

	move_and_slide()


func is_sprinting() -> bool:
	return Input.is_action_pressed("sprint")


func raycast_grapple() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var center := get_viewport().get_visible_rect().size * 0.5
	var origin := camera.project_ray_origin(center)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + camera.project_ray_normal(center) * grapple_range,
	)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func is_grapplable(hit: Dictionary) -> bool:
	return not hit.is_empty() and hit.normal.dot(Vector3.UP) < max_grapple_slope


func try_start_grapple() -> bool:
	if _grapple_cooldown_timer > 0.0:
		return false

	var hit := raycast_grapple()
	if not is_grapplable(hit):
		return false

	is_grappled = true
	grapple_timer = grapple_duration
	grapple_target = hit.position
	is_sliding = false
	velocity.x *= 0.2
	velocity.z *= 0.2
	camera_settings.set_grappling(true)
	camera_settings.add_shake(0.12)
	return true


func update_grapple(delta):
	grapple_timer -= delta

	if Input.is_action_just_pressed("jump"):
		end_grapple()
		return

	var pull_point := global_position + Vector3(0, 0.6, 0)
	if grapple_timer <= 0.0:
		end_grapple()
		return

	if pull_point.distance_to(grapple_target) <= grapple_cancel_distance:
		end_grapple(true)
		return

	# Pull the player toward the anchor point
	var pull_dir := (grapple_target - pull_point).normalized()
	velocity += pull_dir * grapple_accel * delta

	# Approaching shake — stronger when fast, fades as we get closer
	var dist := pull_point.distance_to(grapple_target)
	var speed := velocity.length()
	camera_settings.add_shake(speed * 0.002 * clampf(dist / 15.0, 0.0, 1.0))


func end_grapple(damp_velocity := false) -> void:
	is_grappled = false
	_grapple_cooldown_timer = grapple_cooldown
	camera_settings.set_grappling(false)

	if damp_velocity:
		# Landing damp — bleed off the incoming pull so we don't slam the wall
		velocity.x *= 0.35
		velocity.z *= 0.35
		velocity.y *= 0.4
		camera_settings.add_shake(0.05)


func start_slide():
	is_sliding = true
	slide_timer = slide_duration

	# Slide in the direction the player is currently moving
	slide_direction = Vector3(velocity.x, 0, velocity.z).normalized()

	if slide_direction == Vector3.ZERO:
		slide_direction = -global_transform.basis.z

	velocity.x = slide_direction.x * slide_speed
	velocity.z = slide_direction.z * slide_speed


func update_slide(delta):
	slide_timer -= delta

	# Gradually slow down
	velocity.x = move_toward(
		velocity.x,
		0,
		slide_speed * 5.0 * delta
	)

	velocity.z = move_toward(
		velocity.z,
		0,
		slide_speed * 2.0 * delta
	)

	if slide_timer <= 0:
		is_sliding = false
