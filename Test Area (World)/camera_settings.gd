extends Node3D

@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity := 0.002
@export_range(1.0, 89.0, 1.0) var max_pitch_degrees := 85.0
@export var base_fov := 75.0
@export var max_fov := 100.0
@export var aim_fov := 50.0
@export var fov_lerp_speed := 8.0
@export var camera_margin := 0.2
@export var min_camera_distance := 0.4

@onready var character := get_parent() as CharacterBody3D
@onready var camera_3d := get_node("Camera3D") as Camera3D

var yaw := 0.0
var pitch := 0.0
var view_is_left := false
var view_tween: Tween
var _shake_offset := Vector2.ZERO
var _is_grappling := false
var _view_x := 0.0
var _base_camera_pos := Vector3.ZERO


func _ready() -> void:
	if character == null:
		push_error("Camera Settings must be a child of a CharacterBody3D.")
		set_process_input(false)
		set_process(false)
		return

	yaw = character.rotation.y
	pitch = rotation.x
	camera_3d.fov = base_fov
	_base_camera_pos = camera_3d.position
	_view_x = _base_camera_pos.x
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	# The camera holds its own world-space yaw. The body rotates toward its
	# movement direction, so compensate here or the view would swing with it.
	rotation.y = yaw - character.rotation.y
	rotation.x = pitch

	_shake_offset = _shake_offset.lerp(Vector2.ZERO, 10.0 * delta)
	camera_3d.h_offset = _shake_offset.x
	camera_3d.v_offset = _shake_offset.y

	if not character:
		return

	var target_fov := base_fov
	if _is_grappling:
		var speed := Vector3(character.velocity.x, 0, character.velocity.z).length()
		var normalized := clampf(speed / 30.0, 0.0, 1.0)
		target_fov = lerpf(base_fov, max_fov, normalized * normalized)
	if Input.is_action_pressed("aim") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		target_fov = aim_fov
	camera_3d.fov = lerpf(camera_3d.fov, target_fov, fov_lerp_speed * delta)

	apply_camera_collision()


func apply_camera_collision() -> void:
	# Ideal camera spot (view-switch animation drives only the x offset).
	# If anything blocks the camera on the way there, pull it in so it never
	# clips through walls or the floor.
	var ideal_local := Vector3(_view_x, _base_camera_pos.y, _base_camera_pos.z)
	var ideal_world := global_transform * ideal_local
	var anchor := global_position + Vector3(0, 0.5, 1)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(anchor, ideal_world)
	query.exclude = [character.get_rid()]
	var hit := space.intersect_ray(query)
	if hit:
		var dir: Vector3 = (ideal_world - anchor).normalized()
		ideal_world = hit.position - dir * camera_margin
		if anchor.distance_to(ideal_world) < min_camera_distance:
			ideal_world = anchor + dir * min_camera_distance

	camera_3d.position = to_local(ideal_world)


func set_grappling(active: bool) -> void:
	_is_grappling = active


func add_shake(intensity: float) -> void:
	_shake_offset += Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
	) * intensity


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var mouse_is_captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if mouse_is_captured else Input.MOUSE_MODE_CAPTURED
		)
		return

	if event.is_action_pressed("switch-view"):
		switch_view()
		return

	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
		and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED
	):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		look_around(event.screen_relative)


func look_around(mouse_movement: Vector2) -> void:
	yaw -= mouse_movement.x * mouse_sensitivity
	pitch -= mouse_movement.y * mouse_sensitivity
	pitch = clamp(pitch, -deg_to_rad(max_pitch_degrees), deg_to_rad(max_pitch_degrees))


func switch_view() -> void:
	view_is_left = not view_is_left
	var target_x: float = -abs(_base_camera_pos.x) if view_is_left else abs(_base_camera_pos.x)

	if view_tween and view_tween.is_valid():
		view_tween.kill()

	view_tween = create_tween()
	view_tween.tween_property(self, "_view_x", target_x, 0.2) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
