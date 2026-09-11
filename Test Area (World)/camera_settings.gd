extends Node3D

@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity := 0.002
@export_range(1.0, 89.0, 1.0) var max_pitch_degrees := 85.0
@export var base_fov := 75.0
@export var max_fov := 100.0
@export var fov_lerp_speed := 8.0

@onready var character := get_parent() as CharacterBody3D
@onready var camera_3d := get_node("Camera3D") as Camera3D

var yaw := 0.0
var pitch := 0.0
var view_is_left := false
var view_tween: Tween
var _shake_offset := Vector2.ZERO
var _is_grappling := false


func _ready() -> void:
	if character == null:
		push_error("Camera Settings must be a child of a CharacterBody3D.")
		set_process_input(false)
		set_process(false)
		return

	yaw = character.rotation.y
	pitch = rotation.x
	camera_3d.fov = base_fov
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
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
	camera_3d.fov = lerpf(camera_3d.fov, target_fov, fov_lerp_speed * delta)


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

	# Yaw the character so movement stays relative to the view. Keep pitch on
	# this pivot so looking up or down never tilts the collision body.
	character.rotation.y = yaw
	rotation.x = pitch


func switch_view() -> void:
	view_is_left = not view_is_left
	var target_x: float = -abs(camera_3d.position.x) if view_is_left else abs(camera_3d.position.x)

	if view_tween and view_tween.is_valid():
		view_tween.kill()

	view_tween = create_tween()
	view_tween.tween_property(camera_3d, "position:x", target_x, 0.2) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
