extends CharacterBody3D

@export var walk_speed := 5.0
@export var sprint_speed := 15.0
@export var sprint_accel := 9.0
@export var acceleration := 20.0
@export var jump_velocity := 4.3
@export var gravity := 20.0
@export var max_fall_speed := 60.0

@export var deceleration := 11.0
@export var air_control := 0.35
@export var air_friction := 0.05
@export var turn_accel := 35.0
@export var brake_accel := 45.0
@export var facing_turn_speed := 15.0

@export var slide_speed := 20.0
@export var slide_duration := 2.0

@export var grapple_range := 30.0
@export var grapple_pull_speed := 30.0
@export var grapple_fling_boost := 1.3
@export var grapple_cancel_distance := 1.0
@export var grapple_cooldown := 1.0
@export var grapple_pull_delay := 0.15
@export_range(0.0, 1.0, 0.01) var max_grapple_slope := 0.4

# Grappling an enemy does not pull you in — it reels them into a decision:
# at/below the threshold you execute (cinematic closes in + kills); otherwise
# pressing LMB just deals damage (not a kill).
@export_range(0.0, 1.0, 0.01) var execution_threshold := 0.35
@export var enemy_grapple_damage := 35.0
@export var execution_duration := 0.6
@export var execution_arrival_distance := 1.1

@export var wall_attach_push := 12.0
@export var wall_attach_hop := 10.0

@export var wall_slide_speed := 3.0
@export var wall_slide_grab := 30.0
@export var wall_slide_friction := 8.0
@export var wall_slide_stick := 10.0
@export var wall_slide_grip := 4.0

var is_sliding := false
var slide_timer := 5
var slide_direction := Vector3.ZERO

var is_grappled := false
var grapple_target := Vector3.ZERO
var grapple_surface_normal := Vector3.UP
var _grapple_cooldown_timer := 0.0
var _grapple_pull_timer := 0.0

var is_wall_attached := false

var is_wall_sliding := false
var wall_normal := Vector3.ZERO

var is_enemy_grappled := false
var grapple_enemy: TestDummy = null

var is_executing := false
var _execution_enemy: TestDummy = null
var _execution_from := Vector3.ZERO
var _execution_to := Vector3.ZERO
var _execution_progress := 0.0

var _grapple_line: MeshInstance3D = null

@onready var camera_settings := $"Camera Settings"
@onready var crosshair: TextureRect = $UI/Crosshair
@onready var grapple_cd_bar: ProgressBar = $UI/GrappleCooldown
@onready var _bow: Bow = $Bow
@onready var _cutscene_anim: AnimationPlayer = get_node_or_null("AnimationPlayer")

func _ready() -> void:
	if _cutscene_anim != null:
		_cutscene_anim.animation_finished.connect(_on_cutscene_animation_finished)


func _physics_process(delta):
	_grapple_cooldown_timer = maxf(0.0, _grapple_cooldown_timer - delta)

	# Update grapple cooldown bar
	grapple_cd_bar.visible = _grapple_cooldown_timer > 0.0
	grapple_cd_bar.value = _grapple_cooldown_timer / grapple_cooldown

	# Update crosshair — show green when a valid grapple target is in range,
	# red when aiming at an enemy below the execution threshold, or during an
	# enemy grapple hold show orange (damage) or red (executable).
	if not is_grappled and not is_enemy_grappled and not is_executing:
		var hit := raycast_grapple()
		if not hit.is_empty():
			var collider := hit.get("collider") as Node
			if collider is TestDummy and (collider as TestDummy).is_alive():
				var enemy := collider as TestDummy
				var executable := not enemy.indestructible and enemy.health <= roundi(enemy.max_health * execution_threshold)
				crosshair.set_enemy_state(executable)
			elif is_grapplable(hit):
				crosshair.set_valid_target(true)
			else:
				crosshair.reset()
		else:
			crosshair.set_valid_target(false)

	# Execution cinematic — player glides toward the target, then deals
	# lethal damage; all other input is locked out until it finishes.
	if is_executing:
		update_execution(delta)
		move_and_slide()
		return

	# Enemy grapple hold — reel aimed at enemy; pressing LMB triggers
	# the execution or a damage hit depending on the enemy's HP.
	if is_enemy_grappled:
		update_enemy_grapple(delta)
		move_and_slide()
		return

	if is_grappled:
		update_grapple(delta)
		move_and_slide()
		return

	if is_wall_attached:
		var released := update_wall_attach(delta)
		if not released:
			velocity = Vector3.ZERO
		move_and_slide()
		return

	# Gravity — fixed constant, falling builds into a heavy terminal drop
	if not is_on_floor():
		velocity.y -= gravity * delta
		velocity.y = maxf(velocity.y, -max_fall_speed)

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

		# Full character rotation — the model turns to face where it's going.
		# While aiming/shooting the bow drives the facing onto the crosshair, so
		# the body must not keep swinging toward the movement direction (that
		# made the bow jerk around while strafing).
		if not _is_fighting_stance():
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


# True while the bow is aimed or being drawn — the body stays locked onto the
# crosshair instead of turning with the movement direction.
func _is_fighting_stance() -> bool:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return false
	return Input.is_action_pressed("aim") or Input.is_action_pressed("shoot")


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

	# Enemy targets go into the hold stance instead of the normal pull.
	var collider := hit.get("collider") as Node
	if collider is TestDummy:
		var dummy := collider as TestDummy
		if dummy.is_alive():
			return _start_enemy_grapple(dummy)
		return false

	return _start_surface_grapple(hit)


func _start_surface_grapple(hit: Dictionary) -> bool:
	is_grappled = true
	grapple_target = hit.position
	grapple_surface_normal = hit.normal
	_grapple_pull_timer = grapple_pull_delay
	_grapple_cooldown_timer = grapple_cooldown
	is_sliding = false
	velocity.x *= 0.2
	velocity.z *= 0.2
	camera_settings.set_grappling(true)
	camera_settings.add_shake(0.12)
	return true


func _start_enemy_grapple(enemy: TestDummy) -> bool:
	_grapple_cooldown_timer = grapple_cooldown
	is_enemy_grappled = true
	grapple_enemy = enemy
	is_sliding = false
	velocity = Vector3.ZERO
	_bow.set_enemy_draw(true)
	camera_settings.set_grappling(true)
	camera_settings.add_shake(0.08)
	_ensure_grapple_line()
	return true


func update_enemy_grapple(delta: float) -> void:
	velocity = Vector3.ZERO

	if grapple_enemy == null or grapple_enemy.is_queued_for_deletion() or not grapple_enemy.is_alive():
		_release_enemy_grapple()
		return

	# Pressing jump breaks the hold entirely.
	if Input.is_action_just_pressed("jump"):
		_release_enemy_grapple()
		camera_settings.add_shake(0.05)
		return

	# Left-click fires the execution cinematic or a quick damage hit.
	if Input.is_action_just_pressed("shoot") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_activate_enemy_grapple()
		return

	# Face the enemy so the hit or execution lines up with the crosshair.
	var flat := grapple_enemy.global_position - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.0001:
		rotation.y = lerp_angle(
			rotation.y,
			atan2(-flat.x, -flat.z),
			clampf(facing_turn_speed * delta, 0.0, 1.0),
		)

	# Tick the crosshair: red = executable, orange = damage only.
	var executable := not grapple_enemy.indestructible and grapple_enemy.health <= roundi(grapple_enemy.max_health * execution_threshold)
	crosshair.set_enemy_state(executable)

	_update_grapple_line()


func _activate_enemy_grapple() -> void:
	var enemy := grapple_enemy
	if enemy == null or not enemy.is_alive():
		_release_enemy_grapple()
		return

	var executable := not enemy.indestructible and enemy.health <= roundi(enemy.max_health * execution_threshold)
	if executable:
		_begin_execution(enemy)
		return

	# Not executable — deal a quick hit and release the hold.
	var dir := (enemy.global_position - global_position).normalized()
	enemy.take_damage(roundi(enemy_grapple_damage), dir, enemy.global_position)
	camera_settings.add_shake(0.15)
	_release_enemy_grapple()


func _begin_execution(enemy: TestDummy) -> void:
	_execution_enemy = enemy
	_execution_from = global_position
	_execution_to = enemy.global_position - (enemy.global_position - global_position).normalized() * execution_arrival_distance
	_execution_to.y += 0.3
	_execution_progress = 0.0
	is_enemy_grappled = false
	grapple_enemy = null
	is_executing = true
	_bow.set_enemy_draw(false)
	camera_settings.set_grappling(false)
	camera_settings.set_cutscene(true)
	crosshair.reset()
	_clear_grapple_line()

	# Play the cutscene. If an AnimationPlayer with an "execute" clip exists,
	# its length drives the glide so the player lands when the camera does.
	if _cutscene_anim != null and _cutscene_anim.has_animation("execute"):
		var clip_len: float = _cutscene_anim.get_animation("execute").length
		if clip_len > 0.001:
			execution_duration = clip_len
		_cutscene_anim.play("execute")


func update_execution(delta: float) -> void:
	if _execution_enemy == null or _execution_enemy.is_queued_for_deletion() or not _execution_enemy.is_alive():
		_finish_execution()
		return

	_execution_progress = minf(_execution_progress + delta / execution_duration, 1.0)
	var t := 1.0 - pow(1.0 - _execution_progress, 3.0)
	global_position = _execution_from.lerp(_execution_to, t)
	velocity = Vector3.ZERO

	var flat := _execution_enemy.global_position - global_position
	flat.y = 0.0
	if flat.length_squared() > 0.0001:
		rotation.y = lerp_angle(
			rotation.y,
			atan2(-flat.x, -flat.z),
			clampf(20.0 * delta, 0.0, 1.0),
		)

	if _execution_progress >= 1.0:
		_apply_execution_kill()


func _apply_execution_kill() -> void:
	var enemy := _execution_enemy
	if enemy == null or enemy.is_queued_for_deletion():
		_finish_execution()
		return
	_execution_enemy = null
	var dir := (global_position - enemy.global_position).normalized()
	enemy.take_damage(99999, dir, global_position)
	camera_settings.add_shake(0.2)
	_finish_execution()


func _on_cutscene_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"execute" and is_executing:
		_apply_execution_kill()


func _finish_execution() -> void:
	is_executing = false
	_execution_enemy = null
	velocity = Vector3.ZERO
	camera_settings.set_grappling(false)
	camera_settings.set_cutscene(false)
	if _cutscene_anim != null and _cutscene_anim.is_playing():
		_cutscene_anim.stop()
	crosshair.reset()


func _release_enemy_grapple() -> void:
	is_enemy_grappled = false
	grapple_enemy = null
	_bow.set_enemy_draw(false)
	camera_settings.set_grappling(false)
	crosshair.reset()
	_clear_grapple_line()


func player_is_busy() -> bool:
	return is_enemy_grappled or is_executing


func get_grapple_enemy() -> Node3D:
	if is_enemy_grappled:
		return grapple_enemy
	if is_executing:
		return _execution_enemy
	return null


func _ensure_grapple_line() -> void:
	if _grapple_line != null and is_instance_valid(_grapple_line):
		return
	var mid_mesh := CylinderMesh.new()
	mid_mesh.top_radius = 0.012
	mid_mesh.bottom_radius = 0.012
	# TODO: Assign model asset (.glb) — replace placeholder grapple line with a rope / cord mesh.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.6, 0.2, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var line := MeshInstance3D.new()
	line.name = "GrappleLine_Placeholder"
	line.mesh = mid_mesh
	line.material_override = mat
	add_child(line)
	_grapple_line = line


func _update_grapple_line() -> void:
	if _grapple_line == null or not is_instance_valid(_grapple_line) or grapple_enemy == null:
		return
	_set_line_between(global_position + Vector3(0, 1.1, 0), grapple_enemy.global_position + Vector3(0, 0.5, 0))


func _set_line_between(from: Vector3, to: Vector3) -> void:
	if _grapple_line == null or not is_instance_valid(_grapple_line):
		return
	var segment := to - from
	var length := segment.length()
	if length < 0.01:
		_grapple_line.visible = false
		return
	_grapple_line.visible = true
	var mesh := _grapple_line.mesh as CylinderMesh
	if mesh != null:
		mesh.height = length
	var dir := segment / length
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	var z_axis := up.cross(dir).normalized()
	var x_axis := dir.cross(z_axis).normalized()
	_grapple_line.global_transform = Transform3D(Basis(x_axis, dir, z_axis), (from + to) * 0.5)


func _clear_grapple_line() -> void:
	if _grapple_line != null and is_instance_valid(_grapple_line):
		_grapple_line.queue_free()
		_grapple_line = null


func update_grapple(delta) -> void:
	# Jumping mid-grapple cancels the pull and flings you off with momentum
	if Input.is_action_just_pressed("jump"):
		end_grapple()
		velocity.x *= grapple_fling_boost
		velocity.z *= grapple_fling_boost
		return

	var pull_point := global_position + Vector3(0, 0.6, 0)

	# Short wind-up simulating the grapple being shot / initial animation
	if _grapple_pull_timer > 0.0:
		_grapple_pull_timer -= delta
		return

	# Reached the wall — attach and cling before we can pass through it
	if pull_point.distance_to(grapple_target) <= grapple_cancel_distance:
		attach_to_wall()
		return

	# Flight: slam the velocity straight at the anchor every frame — a fast,
	# readable pull with no acceleration buildup, overshoot, or swinging.
	var pull_dir := (grapple_target - pull_point).normalized()
	velocity = pull_dir * grapple_pull_speed

	# Face toward the anchor while flying so the pull reads as an animation
	var flat_pull := Vector3(pull_dir.x, 0, pull_dir.z)
	if flat_pull.length_squared() > 0.001:
		rotation.y = lerp_angle(
			rotation.y,
			atan2(-flat_pull.x, -flat_pull.z),
			clampf(facing_turn_speed * delta, 0.0, 1.0),
		)

	camera_settings.add_shake(0.01)


func attach_to_wall() -> void:
	is_grappled = false
	is_wall_attached = true
	velocity = Vector3.ZERO
	camera_settings.set_grappling(false)
	camera_settings.add_shake(0.08)


func update_wall_attach(_delta: float) -> bool:
	if is_on_floor():
		is_wall_attached = false
		return true

	# Jump breaks the grip and flings off the surface
	if Input.is_action_just_pressed("jump"):
		is_wall_attached = false
		velocity = grapple_surface_normal * wall_attach_push
		velocity.y = wall_attach_hop
		camera_settings.set_grappling(false)
		camera_settings.add_shake(0.1)
		return true

	return false


func end_grapple(damp_velocity := false) -> void:
	is_grappled = false
	camera_settings.set_grappling(false)

	if damp_velocity:
		# Landing damp — bleed off the incoming pull so we don't slam the wall
		velocity.x *= 0.35
		velocity.z *= 0.35
		# Never leave upward momentum — it hovers the player on the wall face
		velocity.y = minf(velocity.y * 0.4, 0.0)
		camera_settings.add_shake(0.05)


func handle_wall_slide(delta) -> void:
	if is_on_floor() or is_grappled or is_wall_attached:
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


func _detect_wall_normal() -> Vector3:
	for i in get_slide_collision_count():
		var normal: Vector3 = get_slide_collision(i).get_normal()
		# Wall-like normals are nearly perpendicular to up (not floor/ceiling)
		if absf(normal.dot(Vector3.UP)) < 0.5:
			return normal
	return Vector3.ZERO


func start_slide():
	is_sliding = true
	@warning_ignore("narrowing_conversion")
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
