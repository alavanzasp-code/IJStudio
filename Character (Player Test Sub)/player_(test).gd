extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 15.0
@export var sprint_accel := 9.0
@export var acceleration := 20.0
@export var jump_velocity := 3

@export var deceleration := 11.0
@export var air_control := 0.35
@export var air_friction := 0.05
@export var turn_accel := 35.0
@export var brake_accel := 45.0
@export var facing_turn_speed := 15.0

@export var slide_speed := 20.0
@export var slide_duration := 2.0

@export var grapple_range := 30.0
@export var grapple_duration := 1.4
@export var grapple_accel := 30.0
@export var grapple_cancel_distance := 1.0
@export var grapple_cooldown := 4
@export_range(0.0, 1.0, 0.01) var max_grapple_slope := 0.4

@export var wall_slide_speed := 3.0
@export var wall_slide_grab := 30.0
@export var wall_slide_friction := 8.0
@export var wall_slide_stick := 10.0
@export var wall_slide_grip := 4.0
@export var wall_jump_velocity := 5.0
@export var wall_jump_push := 8.0

var is_sliding := false
var slide_timer := 5
var slide_direction := Vector3.ZERO

var is_grappled := false
var grapple_timer := 0.0
var grapple_target := Vector3.ZERO
var _grapple_cooldown_timer := 0.0

var is_wall_sliding := false
var wall_normal := Vector3.ZERO

@onready var camera_settings := $"Camera Settings"
@onready var crosshair: TextureRect = $UI/Crosshair
@onready var grapple_cd_bar: ProgressBar = $UI/GrappleCooldown

func _physics_process(delta):
	_grapple_cooldown_timer = maxf(0.0, _grapple_cooldown_timer - delta)

	# Update grapple cooldown bar
	grapple_cd_bar.visible = _grapple_cooldown_timer > 0.0
	grapple_cd_bar.value = _grapple_cooldown_timer / grapple_cooldown

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

	# Wall slide / wall jump (state comes from the last move_and_slide)
	handle_wall_slide(delta)

	# Movement input is relative to the camera aim, not the body — the model
	# turns itself to follow the direction of travel.
	var input_dir := Input.get_vector(
		"left",
		"right",
		"up",
		"down",
	)

	var has_input := input_dir.length_squared() > 0.0

	# Project input onto the camera's ground-plane axes
	var camera := get_viewport().get_camera_3d()
	var cam_forward := -camera.global_transform.basis.z
	cam_forward.y = 0
	var cam_right := camera.global_transform.basis.x
	cam_right.y = 0
	var wish_dir := cam_right * input_dir.x - cam_forward * input_dir.y
	wish_dir.y = 0
	if has_input:
		wish_dir = wish_dir.normalized()

	# In the air you only get a fraction of steering and thrust — no mid-air darting
	var control := air_control if not is_on_floor() else 1.0

	if has_input:
		# Sprint is available in whatever direction you're heading
		var is_sprinting_now := is_sprinting()
		var base_speed := sprint_speed if is_sprinting_now else walk_speed
		var build := sprint_accel if is_sprinting_now else acceleration

		# Full character rotation — the model turns to face where it's going
		var facing_yaw: float = atan2(-wish_dir.x, -wish_dir.z)
		rotation.y = lerp_angle(
			rotation.y,
			facing_yaw,
			clampf(facing_turn_speed * delta, 0.0, 1.0),
		)

		# Direction changes keep their momentum instead of restarting a ramp:
		# a hard brake flips full reversals in under a second, and a strong
		# thrust snaps onto a new heading without bleeding speed.
		var flat_velocity := Vector3(velocity.x, 0, velocity.z)
		var flat_speed := flat_velocity.length()
		var along := flat_velocity.dot(wish_dir)

		var accel := build
		if flat_speed > 0.5:
			var deviation := flat_velocity.normalized().angle_to(wish_dir)
			if deviation > deg_to_rad(35.0):
				accel = brake_accel if along < 0.0 else turn_accel
			elif flat_speed > base_speed * 0.5:
				accel = maxf(build, turn_accel)
			else:
				accel = build

		var target_velocity := wish_dir * base_speed
		velocity.x = move_toward(velocity.x, target_velocity.x, accel * control * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, accel * control * delta)
	else:
		# No input — friction bleeds the momentum off instead of cutting it
		var drag := deceleration if is_on_floor() else air_friction
		velocity.x = move_toward(velocity.x, 0, drag * delta)
		velocity.z = move_toward(velocity.z, 0, drag * delta)

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

	# Face toward the anchor while pulling
	var flat_pull := Vector3(pull_dir.x, 0, pull_dir.z)
	if flat_pull.length_squared() > 0.001:
		rotation.y = lerp_angle(
			rotation.y,
			atan2(-flat_pull.x, -flat_pull.z),
			clampf(facing_turn_speed * delta, 0.0, 1.0),
		)

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
		# Never leave upward momentum — it hovers the player on the wall face
		velocity.y = minf(velocity.y * 0.4, 0.0)
		camera_settings.add_shake(0.05)


func handle_wall_slide(delta) -> void:
	if is_on_floor() or is_grappled:
		is_wall_sliding = false
		wall_normal = Vector3.ZERO
		return

	var normal := _detect_wall_normal()
	if normal == Vector3.ZERO or velocity.y >= 0.0:
		is_wall_sliding = false
		wall_normal = Vector3.ZERO
		return

	is_wall_sliding = true
	wall_normal = normal

	# Cap the fall to a slow slide — but never cling when first catching the
	# wall: start dropping immediately instead of drifting down lazily.
	if velocity.y > -wall_slide_speed:
		velocity.y = move_toward(
			velocity.y,
			-wall_slide_speed,
			wall_slide_grab * delta,
		)

	# Stick to the wall — pull slightly toward it and bleed sideways speed
	velocity += normal * wall_slide_grip * delta
	velocity.x = move_toward(velocity.x, 0, wall_slide_stick * delta)
	velocity.z = move_toward(velocity.z, 0, wall_slide_stick * delta)

	# Wall jump away from the surface
	if Input.is_action_just_pressed("jump"):
		velocity.y = wall_jump_velocity
		velocity += normal * wall_jump_push
		is_wall_sliding = false
		wall_normal = Vector3.ZERO


func _detect_wall_normal() -> Vector3:
	for i in get_slide_collision_count():
		var normal: Vector3 = get_slide_collision(i).get_normal()
		# Wall-like normals are nearly perpendicular to up (not floor/ceiling)
		if absf(normal.dot(Vector3.UP)) < 0.5:
			return normal
	return Vector3.ZERO


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
