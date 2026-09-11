extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 15.0
@export var acceleration := 15.0
@export var jump_velocity := 5.0

@export var slide_speed := 20.0
@export var slide_duration := 5.0

@export var grapple_range := 2.5
@export var grapple_duration := 1.2
@export var grapple_slide_speed := 2.0
@export var wall_jump_push := 6.0

var is_sliding := false
var slide_timer := 5
var slide_direction := Vector3.ZERO

var is_grappled := false
var grapple_timer := 0.0
var grapple_normal := Vector3.ZERO

func _physics_process(delta):
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


func find_wall_normal() -> Vector3:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.6, 0)
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin - global_transform.basis.z * grapple_range,
	)
	var hit := space.intersect_ray(query)
	if hit:
		return hit.normal
	return Vector3.ZERO


func try_start_grapple() -> bool:
	if is_on_floor():
		return false

	var wall_normal := find_wall_normal()
	if wall_normal == Vector3.ZERO:
		return false

	is_grappled = true
	grapple_timer = grapple_duration
	grapple_normal = wall_normal
	is_sliding = false
	velocity.y = -grapple_slide_speed
	velocity.x *= 0.2
	velocity.z *= 0.2
	return true


func update_grapple(delta):
	grapple_timer -= delta

	if Input.is_action_just_pressed("jump"):
		wall_jump()
		is_grappled = false
		return

	# Detach when time runs out or the wall is no longer in reach
	if grapple_timer <= 0.0 or find_wall_normal() == Vector3.ZERO:
		is_grappled = false
		return

	# Slide down the wall at a steady pace
	velocity.y = move_toward(velocity.y, -grapple_slide_speed, acceleration * delta)

	# Cling to the wall, damp incoming horizontal speed
	velocity.x = move_toward(velocity.x, 0, acceleration * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0, acceleration * 2.0 * delta)


func wall_jump() -> void:
	velocity.y = jump_velocity
	velocity += grapple_normal * wall_jump_push


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