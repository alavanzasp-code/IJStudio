class_name TestDummy
extends CharacterBody3D

@export var max_health := 60
@export var indestructible := false
@export var respawn_enabled := true
@export var respawn_delay := 3.0

@export var movement_enabled := false
@export var movement_speed := 2.5
@export var patrol_distance := 8.0

@export var flying := false
@export var fly_radius := 3.0
@export var fly_speed := 4.0
@export var fly_height := 3.0
@export var flight_spring := 8.0

@export var body_color := Color(0.55, 0.55, 0.6)
@export var flash_color := Color(1.0, 0.45, 0.2)
@export var hit_flash_time := 0.12
@export var knockback := 6.0
@export var gravity := 20.0

var health := 0

var _dead := false
var _respawn_timer := 0.0
var _spawn_position := Vector3.ZERO
var _patrol_dir := 1.0
var _fly_angle := 0.0
var _flash_progress := 0.0
var _body_mat: StandardMaterial3D

var _bar_root: Node3D
var _health_bar_fill: MeshInstance3D
var _fill_material: StandardMaterial3D


func _ready() -> void:
	_spawn_position = global_position
	health = max_health
	build_placeholder_visuals()
	build_health_bar()
	_update_health_bar()


func _physics_process(delta: float) -> void:
	_update_flash(delta)

	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
		return

	if _dead:
		return

	if flying:
		_update_flight(delta)
	else:
		_update_grounded(delta)

	move_and_slide()


func is_alive() -> bool:
	return not _dead


func take_damage(amount: int, hit_dir: Vector3 = Vector3.ZERO, hit_pos: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return

	if not indestructible:
		health -= amount
	if hit_dir != Vector3.ZERO:
		velocity += hit_dir.normalized() * knockback
	_flash_progress = hit_flash_time
	_update_health_bar()
	_spawn_damage_label(amount)

	if not indestructible and health <= 0:
		_die(hit_pos)


func _die(origin: Vector3) -> void:
	_dead = true
	visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_clear_nearby_arrows(origin)
	if respawn_enabled:
		_respawn_timer = respawn_delay


func respawn() -> void:
	_dead = false
	global_position = _spawn_position
	velocity = Vector3.ZERO
	health = max_health
	_patrol_dir = 1.0
	_fly_angle = 0.0
	_flash_progress = 0.0
	visible = true
	collision_layer = 1
	collision_mask = 1
	_body_mat.albedo_color = body_color
	_update_health_bar()


func _update_grounded(delta: float) -> void:
	velocity.y -= gravity * delta
	velocity.x = 0.0
	velocity.z = 0.0

	if movement_enabled:
		var half := maxf(patrol_distance * 0.5, 0.5)
		if _patrol_dir > 0.0 and global_position.x >= _spawn_position.x + half:
			_patrol_dir = -1.0
		elif _patrol_dir < 0.0 and global_position.x <= _spawn_position.x - half:
			_patrol_dir = 1.0
		velocity.x = _patrol_dir * movement_speed


func _update_flight(delta: float) -> void:
	_fly_angle += (fly_speed / maxf(fly_radius, 0.1)) * delta
	var target := _spawn_position + Vector3(cos(_fly_angle) * fly_radius, fly_height, sin(_fly_angle) * fly_radius)
	velocity = (target - global_position) * flight_spring
	if velocity.length() > fly_speed * 1.5:
		velocity = velocity.normalized() * fly_speed * 1.5


func _update_flash(delta: float) -> void:
	if _flash_progress <= 0.0 or _body_mat == null:
		return
	_flash_progress -= delta
	if _flash_progress <= 0.0:
		_body_mat.albedo_color = body_color
		return
	_body_mat.albedo_color = body_color.lerp(flash_color, _flash_progress / hit_flash_time)


func _clear_nearby_arrows(origin: Vector3) -> void:
	for node: Node in get_tree().get_nodes_in_group("arrow"):
		var riding := node.get_parent() == self
		if riding or (node is Node3D and (node as Node3D).global_position.distance_to(origin) < 1.5):
			node.queue_free()


func build_placeholder_visuals() -> void:
	var visuals := Node3D.new()
	visuals.name = "PlaceholderVisuals"
	# TODO: Assign model asset (res://assets/characters/dummy.glb)
	add_child(visuals)

	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = body_color
	_body_mat.roughness = 0.6

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 1.8
	var body := MeshInstance3D.new()
	body.name = "Body_Placeholder"
	body.mesh = body_mesh
	body.position.y = 0.9
	body.material_override = _body_mat
	visuals.add_child(body)


# Dev/test UI — a billboarded HP bar floating above the dummy. Not final game
# geometry; replaced by a proper UI/feedback system when real assets exist.
func build_health_bar() -> void:
	var bg_mat := StandardMaterial3D.new()
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.albedo_color = Color(0.06, 0.06, 0.08, 0.8)

	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(1.5, 0.2)
	var bg := MeshInstance3D.new()
	bg.name = "HealthBarBg_Placeholder"
	bg.mesh = bg_mesh
	bg.material_override = bg_mat

	_fill_material = StandardMaterial3D.new()
	_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_fill_material.albedo_color = Color(0.35, 0.95, 0.4)

	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(1.42, 0.14)
	_health_bar_fill = MeshInstance3D.new()
	_health_bar_fill.name = "HealthBarFill_Placeholder"
	_health_bar_fill.mesh = fill_mesh
	_health_bar_fill.material_override = _fill_material

	_bar_root = Node3D.new()
	_bar_root.name = "HealthBar"
	_bar_root.position.y = 2.125
	_bar_root.add_child(bg)
	_bar_root.add_child(_health_bar_fill)
	add_child(_bar_root)


func _update_health_bar() -> void:
	if _health_bar_fill == null:
		return
	var fraction := clampf(health / float(maxi(max_health, 1)), 0.0, 1.0)
	var fill_w := 1.42 * fraction
	(_health_bar_fill.mesh as QuadMesh).size = Vector2(fill_w, 0.14)
	_health_bar_fill.position.x = -0.71 + fill_w * 0.5
	_fill_material.albedo_color = Color(0.9, 0.25, 0.2).lerp(Color(0.35, 0.95, 0.4), fraction)


func _spawn_damage_label(amount: int) -> void:
	# Skip scripted kills (execution deals a fake 99999) — show only real hits
	# so distance/charge damage can be read.
	if amount >= 10000:
		return

	var label := Label3D.new()
	label.text = str(amount)
	label.font_size = 42
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)

	var world := get_tree().current_scene
	if world == null:
		world = get_parent()
	label.global_position = global_position + Vector3(randf_range(-0.25, 0.25), 2.2, randf_range(-0.25, 0.25))
	world.add_child(label)

	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 0.9, 0.9) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tween.chain().tween_callback(label.queue_free)