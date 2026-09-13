class_name Bow
extends Node3D

const ARROW_SCENE: PackedScene = preload("res://Weapons/arrow_(test).tscn")

@export var draw_time := 0.55
@export var arrow_min_speed := 15.0
@export var arrow_max_speed := 55.0
@export_range(0.0, 1.0, 0.01) var min_charge := 0.15
# >1 bends the charge curve so quick taps stay weak and full draws pay the most.
@export_range(1.0, 3.0, 0.05) var charge_power := 1.35
@export var aim_turn_speed := 15.0
@export var aim_rotate_speed := 20.0

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
	var mouse_captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	var aiming := Input.is_action_pressed("aim") and mouse_captured
	var shooting := Input.is_action_pressed("shoot") and mouse_captured

	if shooting:
		_draw = clampf(_draw + delta / draw_time, 0.0, 1.0)
	elif _draw > 0.0:
		fire()
		_draw = 0.0

	if aiming or shooting:
		var dir: Vector3 = _aim_ray().normal
		_rotate_player_toward(dir, delta)
		_orient_bow(dir, delta)
	else:
		_reset_bow_local()

	_update_draw_visual(delta)


func fire() -> void:
	var ray := _aim_ray()
	var dir: Vector3 = ray.normal

	# Snap the player and bow onto the cursor so the shot leaves true.
	_rotate_player_toward(dir, 1.0)
	_orient_bow(dir, 1.0)

	# Spawn the arrow ON the crosshair ray (just ahead of the bow). The bow's
	# own offset — which grows while moving/turning — would otherwise shift the
	# whole trajectory off the crosshair.
	var origin: Vector3 = ray.origin + dir * (maxf((global_position - ray.origin).length(), 1.2) + 0.5)

	var arrow: RigidBody3D = ARROW_SCENE.instantiate()
	get_tree().current_scene.add_child(arrow)

	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	arrow.global_transform = Transform3D(Basis.looking_at(dir, up), origin)
	if _player != null:
		arrow.add_collision_exception_with(_player)

	# Nonlinear ramp: a tap only reaches ~half the max speed, so drawn shots
	# gain real travel power — but the tap still flies a usable distance.
	var charge := maxf(_draw, min_charge)
	var effective_charge := pow(charge, charge_power)
	arrow.linear_velocity = dir * lerpf(arrow_min_speed, arrow_max_speed, effective_charge)

	if _camera_settings != null and _camera_settings.has_method("add_shake"):
		_camera_settings.add_shake(0.05 + charge * 0.03)


func _aim_ray() -> Dictionary:
	var center := _camera.get_viewport().get_visible_rect().size * 0.5
	return {
		"origin": _camera.project_ray_origin(center),
		"normal": _camera.project_ray_normal(center),
	}


# Turn the player body so it (and the bow glued to it) faces the crosshair.
func _rotate_player_toward(dir: Vector3, delta: float) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	_player.rotation.y = lerp_angle(
		_player.rotation.y,
		target_yaw,
		clampf(aim_turn_speed * delta, 0.0, 1.0),
	)


# Aim the bow itself along the crosshair direction.
func _orient_bow(dir: Vector3, delta: float) -> void:
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	var target_basis := Basis.looking_at(dir, up)
	var k := clampf(aim_rotate_speed * delta, 0.0, 1.0)
	var t := global_transform
	t.basis = global_transform.basis.slerp(target_basis, k)
	global_transform = t


# Rest state — the bow stays held along the player's facing, no self-rotation.
func _reset_bow_local() -> void:
	var t := transform
	t.basis = Basis.IDENTITY
	transform = t


func _update_draw_visual(delta: float) -> void:
	var k := clampf(16.0 * delta, 0.0, 1.0)
	_string.position.z = lerpf(_string.position.z, -0.13 + _draw * 0.13, k)
	_nock.position.z = lerpf(_nock.position.z, -0.06 + _draw * 0.16, k)


func _build_bow() -> void:
	# TODO: Assign model asset (.glb) — replace placeholder primitives with instanced bow model.
	var visuals := Node3D.new()
	visuals.name = "PlaceholderVisuals"
	add_child(visuals)

	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.24, 0.1, 1.0)
	wood.roughness = 0.9

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.09, 0.05, 1.0)

	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.9, 0.9, 0.88, 1.0)

	_add_box(visuals, Vector3(0.06, 0.3, 0.05), Vector3(0, 0, 0.03), Vector3.ZERO, wood, "Grip_Placeholder")
	_add_box(visuals, Vector3(0.05, 0.62, 0.045), Vector3(0, 0.3, 0.06), Vector3(20, 0, 0), wood, "Limb_Placeholder")
	_add_box(visuals, Vector3(0.05, 0.62, 0.045), Vector3(0, -0.3, 0.06), Vector3(-20, 0, 0), wood, "Limb_Placeholder")
	_add_box(visuals, Vector3(0.06, 0.08, 0.06), Vector3(0, 0.58, 0.1), Vector3(20, 0, 0), dark, "Tip_Placeholder")
	_add_box(visuals, Vector3(0.06, 0.08, 0.06), Vector3(0, -0.58, 0.1), Vector3(-20, 0, 0), dark, "Tip_Placeholder")

	var string_mesh := BoxMesh.new()
	string_mesh.size = Vector3(0.03, 1.22, 0.012)
	_string = MeshInstance3D.new()
	_string.name = "String_Placeholder"
	_string.mesh = string_mesh
	_string.position = Vector3(0, 0, -0.13)
	_string.material_override = string_mat
	add_child(_string)

	_nock = Node3D.new()
	_nock.name = "NockPoint"
	_nock.position = Vector3(0, 0, -0.06)
	add_child(_nock)
	# Show a loaded arrow nock placeholder so the bow reads at a glance.
	Arrow.build_arrow_mesh(_nock)


func _add_box(
	parent: Node3D,
	sz: Vector3,
	pos: Vector3,
	rot_deg: Vector3,
	mat: StandardMaterial3D,
	node_name: String,
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	parent.add_child(mi)
