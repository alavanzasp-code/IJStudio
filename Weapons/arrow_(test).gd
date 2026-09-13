class_name Arrow
extends RigidBody3D

@export var lifetime := 20.0
@export var arrow_gravity := 0.4

var _frozen := false


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	lock_rotation = true
	continuous_cd = true
	gravity_scale = arrow_gravity
	body_entered.connect(_on_body_entered)

	# Arrows never collide with each other — otherwise volleys clump into an
	# arrow train mid-air and pile into stacks on impact.
	add_to_group("arrow")
	for other: Node in get_tree().get_nodes_in_group("arrow"):
		if other != self:
			add_collision_exception_with(other)

	var col := get_node_or_null("CollisionShape3D")
	if col is CollisionShape3D:
		col.rotation_degrees = Vector3(90, 0, 0)

	var model := Node3D.new()
	model.name = "PlaceholderVisuals"
	# TODO: Assign model asset (.glb) — replace placeholder primitives with instanced model.
	add_child(model)
	build_arrow_mesh(model)
	_autofree()


static func build_arrow_mesh(parent: Node3D) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.52, 0.33, 0.16, 1.0)
	wood.roughness = 0.85

	var fletch := StandardMaterial3D.new()
	fletch.albedo_color = Color(0.82, 0.22, 0.16, 1.0)

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.012
	shaft_mesh.bottom_radius = 0.012
	shaft_mesh.height = 0.9
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft_Placeholder"
	shaft.mesh = shaft_mesh
	shaft.rotation_degrees = Vector3(90, 0, 0)
	shaft.material_override = wood
	parent.add_child(shaft)

	var head_mesh := CylinderMesh.new()
	head_mesh.bottom_radius = 0.04
	head_mesh.top_radius = 0.0
	head_mesh.height = 0.16
	var head := MeshInstance3D.new()
	head.name = "Head_Placeholder"
	head.mesh = head_mesh
	head.position = Vector3(0, 0, -0.53)
	head.rotation_degrees = Vector3(-90, 0, 0)
	head.material_override = wood
	parent.add_child(head)

	for i in 3:
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.012, 0.09, 0.1)
		var fin := MeshInstance3D.new()
		fin.name = "Fletching_Placeholder"
		fin.mesh = fin_mesh
		fin.position = Vector3(0, 0, 0.42)
		fin.rotation_degrees = Vector3(0, float(i) * 120.0, 0)
		fin.material_override = fletch
		parent.add_child(fin)


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


func _on_body_entered(body: Node) -> void:
	if _frozen:
		return
	if body is Arrow:
		return
	_frozen = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _autofree() -> void:
	await get_tree().create_timer(lifetime).timeout
	if not _frozen:
		queue_free()
