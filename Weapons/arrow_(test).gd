class_name Arrow
extends RigidBody3D

@export var lifetime := 20.0
@export var arrow_gravity := 0.4
@export var damage_scale := 1.0
@export var stuck_lifetime := 8.0

var _frozen := false
var _first_frame := true
var _prev_position := Vector3.ZERO
var _sweep_shape: CapsuleShape3D
var _source: Node3D = null
var _impact_basis := Basis.IDENTITY
var _impact_pose_set := false

## Speed captured BEFORE the solver resolves contacts.
##
## `body_entered` is emitted after the physics step that stopped this body, so
## reading `linear_velocity` inside the handler always returns 0 and every hit
## dealt 0 damage. The pre-solve speed is the real impact speed, and it is
## what the damage formula must use.
var _impact_speed := 0.0


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

	# build_visual parents its result to `self` itself.
	build_visual(self)
	_autofree()


func set_source(body: Node3D) -> void:
	_source = body


## Builds the arrow's visuals under [param parent].
##
## Prefers the real asset from ModelLibrary; falls back to the labeled
## placeholder primitives when it is not downloaded yet. Returns the container
## that was populated, or `null` if [param parent] was invalid.
static func build_visual(parent: Node3D) -> Node3D:
	if parent == null:
		push_error("Arrow.build_visual() needs a parent node.")
		return null

	var model := ModelLibrary.instantiate_model("arrow")
	if model != null:
		parent.add_child(model)
		return model

	# TODO: Assign model asset — drop a .glb at the path in ModelLibrary.SPECS
	# ("arrow") and these primitives are removed automatically.
	var visuals := Node3D.new()
	visuals.name = "PlaceholderVisuals"
	parent.add_child(visuals)

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
	visuals.add_child(shaft)

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
	visuals.add_child(head)

	for i in 3:
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.012, 0.09, 0.1)
		var fin := MeshInstance3D.new()
		fin.name = "Fletching_Placeholder"
		fin.mesh = fin_mesh
		fin.position = Vector3(0, 0, 0.42)
		fin.rotation_degrees = Vector3(0, float(i) * 120.0, 0)
		fin.material_override = fletch
		visuals.add_child(fin)

	return visuals


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _frozen:
		if _impact_pose_set and not state.transform.basis.is_equal_approx(_impact_basis):
			var tf := state.transform
			tf.basis = _impact_basis
			state.transform = tf
		return

	var vel := state.linear_velocity
	# Keep the last genuinely-moving speed. The step that makes contact reports
	# a velocity of zero here as well as in body_entered, because both are
	# delivered after the solver has resolved the collision.
	_capture_speed(vel.length())
	if vel.length_squared() < 4.0:
		return
	var dir := vel.normalized()
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.FORWARD
	var t := state.transform
	t.basis = Basis.looking_at(dir, up)
	state.transform = t


func _physics_process(_delta: float) -> void:
	# _physics_process runs BEFORE the step, so this is the last reliable read
	# of the arrow's real flight speed.
	if not _frozen:
		_capture_speed(linear_velocity.length())
	if _frozen:
		if _impact_pose_set and not global_transform.basis.is_equal_approx(_impact_basis):
			var tf := global_transform
			tf.basis = _impact_basis
			global_transform = tf
		return
	var current := global_position
	if _first_frame:
		# Defer seeding until the first physics process: _ready runs during
		# add_child, before the shooter applies the spawn transform, so the
		# previous position would wrongly be the scene origin. Sweeping a long
		# phantom segment from the origin to the spawn point would hit the
		# world (floor/walls) and freeze arrows mid-air beside the player.
		_first_frame = false
		_prev_position = current
		return
	if _prev_position.distance_squared_to(current) > 0.0004:
		# Sweep the full segment travelled since the last frame so a fast-moving
		# target (flying/moving dummies) can never slip through a between-frame
		# gap that discrete/CCD contact would miss.
		_sweep_hit(_prev_position, current)
	_prev_position = current


## Records the arrow's in-flight speed, ignoring stops.
##
## Both `body_entered` and `_integrate_forces` report a velocity of zero on the
## step where contact happens, so the impact speed has to be remembered from
## the last step the arrow was actually travelling.
func _capture_speed(speed: float) -> void:
	if speed > 0.5:
		_impact_speed = speed


func _sweep_hit(from: Vector3, to: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var segment := to - from
	if segment.length() < 0.01:
		return
	if _sweep_shape == null:
		_sweep_shape = CapsuleShape3D.new()
		_sweep_shape.radius = 0.05
	var dir := segment.normalized()
	_sweep_shape.height = segment.length() + 0.2
	var up := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	var z_axis := up.cross(dir).normalized()
	var x_axis := dir.cross(z_axis).normalized()

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _sweep_shape
	params.transform = Transform3D(Basis(x_axis, dir, z_axis), (from + to) * 0.5)
	params.collision_mask = 1
	var exclude := [get_rid()]
	if _source is PhysicsBody3D:
		exclude.append((_source as PhysicsBody3D).get_rid())
	params.exclude = exclude

	# Ask for several candidates: intersect_shape does NOT return hits ordered by
	# distance, so taking only the first result can report a body that is well
	# past the target while the target itself is also inside the swept volume.
	var results := space.intersect_shape(params, 8)
	if results.is_empty():
		return
	_handle_impact(_nearest_along(results, from, dir))


## Picks the candidate the arrow met first.
##
## `intersect_shape` gives no ordering and no contact point, so distance is
## measured by projecting each collider's origin onto the travel direction.
## Ties break in favour of something that can take damage, so an arrow clipping
## a wall and a target in the same step still credits the target.
func _nearest_along(results: Array[Dictionary], from: Vector3, dir: Vector3) -> Node:
	var best: Node = null
	var best_t := INF
	var best_hits := false
	for entry: Dictionary in results:
		var collider := entry.get("collider") as Node
		if collider == null or collider == _source or collider is Arrow:
			continue
		var hits := collider.has_method("take_damage")
		var t := INF
		var node3d := collider as Node3D
		if node3d != null:
			t = (node3d.global_position - from).dot(dir)
		# Strictly-less keeps the first candidate on a tie; a damageable
		# candidate only wins an exact tie.
		if t < best_t or (is_equal_approx(t, best_t) and hits and not best_hits):
			best = collider
			best_t = t
			best_hits = hits
	return best


func _on_body_entered(body: Node) -> void:
	_handle_impact(body)


func _handle_impact(body: Node) -> void:
	if _frozen or body == null:
		return
	if body is Arrow or body == _source:
		return
	_frozen = true
	_impact_basis = global_transform.basis
	_impact_pose_set = true
	physics_interpolation_mode = Node3D.PHYSICS_INTERPOLATION_MODE_OFF

	var impact_dir := -global_transform.basis.z
	if linear_velocity.length_squared() > 1.0:
		impact_dir = linear_velocity.normalized()
	# Fall back to the live velocity if the pre-solve capture is missing (e.g.
	# an impact detected by the sweep before any integration ran).
	var impact_speed := _impact_speed
	if impact_speed <= 0.0:
		impact_speed = linear_velocity.length()

	# On stick: stop acting as a solid obstacle, embed into the victim so it
	# rides along (moving dummies are no longer blocked), and despawn after a
	# short stuck lifetime instead of lingering forever.
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_deferred_attach.call_deferred(body)
	_autofree()

	if body.has_method("take_damage"):
		body.take_damage(roundi(impact_speed * damage_scale), impact_dir, global_position)


func _deferred_attach(body: Node) -> void:
	var target := body as Node3D
	if target == null or is_queued_for_deletion() or not is_inside_tree():
		return
	reparent(target)


func _autofree() -> void:
	var despawn_time := lifetime
	if _frozen:
		despawn_time = stuck_lifetime
	await get_tree().create_timer(despawn_time).timeout
	if is_inside_tree() and not is_queued_for_deletion():
		queue_free()