class_name Bow
extends Node3D

const ARROW_SCENE: PackedScene = preload("res://Weapons/arrow_(test).tscn")

@export var draw_time := 0.55
@export var arrow_speed := 26.0
@export_range(0.0, 1.0, 0.01) var min_charge := 0.4

var _draw := 0.0
var _string: MeshInstance3D
var _nock: Node3D

var _camera: Camera3D
var _player: CharacterBody3D
var _camera_settings: Node


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	if _player == null:
		push_error("Bow must be a direct child of the player CharacterBody3D.")
		set_physics_process(false)
		return

	_camera = _player.get_node_or_null("Camera Settings/Camera3D") as Camera3D
	_camera_settings = _player.get_node_or_null("Camera Settings")

	if _camera == null:
		push_error("Bow could not find the player camera.")
		set_physics_process(false)
		return

	_build_bow()


func _physics_process(delta: float) -> void:
	var drawing := (
		Input.is_action_pressed("shoot")
		and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	)

	if drawing:
		_draw = clampf(_draw + delta / draw_time, 0.0, 1.0)
	elif _draw > 0.0:
		fire()
		_draw = 0.0

	_aim_bow()
	_update_draw_visual(delta)


func fire() -> void:
	var dir := -global_transform.basis.z
	var origin := global_position + dir * 0.12

	var arrow: RigidBody3D = ARROW_SCENE.instantiate()
	get_tree().current_scene.add_child(arrow)

	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	arrow.global_transform = Transform3D(Basis.looking_at(dir, up), origin)
	if _player != null:
		arrow.add_collision_exception_with(_player)

	var charge := maxf(_draw, min_charge)
	arrow.linear_velocity = dir * (arrow_speed * charge)

	if _camera_settings != null and _camera_settings.has_method("add_shake"):
		_camera_settings.add_shake(0.05 + charge * 0.03)


func _aim_bow() -> void:
	var dir := -_camera.global_transform.basis.z
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	var t := global_transform
	t.basis = Basis.looking_at(dir, up)
	global_transform = t


func _update_draw_visual(delta: float) -> void:
	var k := clampf(16.0 * delta, 0.0, 1.0)
	_string.position.z = lerpf(_string.position.z, -0.13 + _draw * 0.13, k)
	_nock.position.z = lerpf(_nock.position.z, -0.06 + _draw * 0.16, k)


func _build_bow() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.24, 0.1, 1.0)
	wood.roughness = 0.9

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.09, 0.05, 1.0)

	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.9, 0.9, 0.88, 1.0)

	_add_box(Vector3(0.06, 0.3, 0.05), Vector3(0, 0, 0.03), Vector3.ZERO, wood)
	_add_box(Vector3(0.05, 0.62, 0.045), Vector3(0, 0.3, 0.06), Vector3(20, 0, 0), wood)
	_add_box(Vector3(0.05, 0.62, 0.045), Vector3(0, -0.3, 0.06), Vector3(-20, 0, 0), wood)
	_add_box(Vector3(0.06, 0.08, 0.06), Vector3(0, 0.58, 0.1), Vector3(20, 0, 0), dark)
	_add_box(Vector3(0.06, 0.08, 0.06), Vector3(0, -0.58, 0.1), Vector3(-20, 0, 0), dark)

	var string_mesh := BoxMesh.new()
	string_mesh.size = Vector3(0.03, 1.22, 0.012)
	_string = MeshInstance3D.new()
	_string.mesh = string_mesh
	_string.position = Vector3(0, 0, -0.13)
	_string.material_override = string_mat
	add_child(_string)

	_nock = Node3D.new()
	_nock.position = Vector3(0, 0, -0.06)
	add_child(_nock)
	Arrow.build_arrow_mesh(_nock)


func _add_box(sz: Vector3, pos: Vector3, rot_deg: Vector3, mat: StandardMaterial3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)
