class_name Arrow
extends RigidBody3D

@export var lifetime := 20.0
@export var arrow_gravity := 0.9

var _frozen := false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	lock_rotation = true
	continuous_cd = true
	gravity_scale = arrow_gravity
	body_entered.connect(_on_body_entered)

	var col := get_node_or_null("CollisionShape3D")
	if col is CollisionShape3D:
		col.rotation_degrees = Vector3(90, 0, 0)

	build_arrow_mesh(self)
	_autofree()


static func build_arrow_mesh(parent: Node3D) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.52, 0.33, 0.16, 1.0)
	wood.roughness = 0.85

	var fletch := StandardMaterial3D.new()
	fletch.albedo_color = Color(0.82, 0.22, 0.16, 1.0)

	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.012
	shaft.bottom_radius = 0.012
	shaft.height = 0.9
	shaft.material = wood

	var mi := MeshInstance3D.new()
	mi.mesh = shaft
	mi.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(mi)

	var head := CylinderMesh.new()
	head.bottom_radius = 0.04
	head.top_radius = 0.0
	head.height = 0.16
	head.material = wood

	mi = MeshInstance3D.new()
	mi.mesh = head
	mi.position = Vector3(0, 0, -0.53)
	mi.rotation_degrees = Vector3(-90, 0, 0)
	parent.add_child(mi)

	for i in 3:
		var fin := BoxMesh.new()
		fin.size = Vector3(0.012, 0.09, 0.1)
		fin.material = fletch

		mi = MeshInstance3D.new()
		mi.mesh = fin
		mi.position = Vector3(0, 0, 0.42)
		mi.rotation_degrees = Vector3(0, float(i) * 120.0, 0)
		parent.add_child(mi)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _frozen:
		return
	var vel := state.linear_velocity
	if vel.length_squared() < 4.0:
		return
	var dir := vel.normalized()
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	var t := state.transform
	t.basis = Basis.looking_at(dir, up)
	state.transform = t


func _on_body_entered(_body: Node) -> void:
	if _frozen:
		return
	_frozen = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _autofree() -> void:
	await get_tree().create_timer(lifetime).timeout
	if not _frozen:
		queue_free()
