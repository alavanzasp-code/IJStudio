extends Node3D

@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity := 0.002
@export_range(1.0, 89.0, 1.0) var max_pitch_degrees := 85.0

@onready var character := get_parent() as CharacterBody3D

var yaw := 0.0
var pitch := 0.0


func _ready() -> void:
	if character == null:
		push_error("Camera Settings must be a child of a CharacterBody3D.")
		set_process_input(false)
		return

	yaw = character.rotation.y
	pitch = rotation.x
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var mouse_is_captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if mouse_is_captured else Input.MOUSE_MODE_CAPTURED
		)
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
