extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 15.0
@export var acceleration := 15.0
@export var jump_velocity := 5.0

@export var slide_speed := 20.0
@export var slide_duration := 5.0

var is_sliding := false
var slide_timer := 5
var slide_direction := Vector3.ZERO

func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_sliding:
		velocity.y = jump_velocity

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
