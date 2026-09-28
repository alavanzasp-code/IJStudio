extends SceneTree

## Verifies the grapple rope: it must exist for a WALL grapple (not just the
## enemy hold) and must actually span its endpoints.
##   godot --headless --script Assets/test_grapple_line.gd

var _fails := 0


func _initialize() -> void:
	var packed := ResourceLoader.load("res://Test Area (World)/test_area.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var player := scene.find_child("Player (Test)", true, false) as CharacterBody3D
	var space := (scene as Node3D).get_world_3d().direct_space_state

	# Aim at a real wall so this exercises the same hit dict the game uses.
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, 1.5, 0), Vector3(0, 1.5, -40.0))
	query.exclude = [player.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		print("FAILED: no wall to grapple in the test arena")
		quit(1)
		return
	_ok("wall grapple ray finds a surface", true)

	# --- Wall grapple builds a rope (this was the primary bug) ---
	player._start_surface_grapple(hit)
	_ok("wall grapple creates a rope", player._grapple_line != null)
	_ok("rope is in the tree",
		player._grapple_line != null and player._grapple_line.is_inside_tree())

	# --- Rope spans the real distance to the anchor ---
	# Stand in for the per-frame update_grapple() the game runs next.
	player._update_grapple_line()
	await process_frame

	var rope := player._grapple_line as Node3D
	var hand: Vector3 = player.global_position + Vector3(0, 1.1, 0)
	var anchor: Vector3 = player.grapple_target
	var expected := hand.distance_to(anchor)
	var got := _rope_length(rope)
	print("    anchor distance = %.2f m, rope length = %.2f m" % [expected, got])
	_ok("rope length matches anchor distance (%.2f m)" % expected,
		absf(got - expected) < 0.15, got)

	var box := _rope_aabb(rope)
	var midpoint: Vector3 = (hand + anchor) * 0.5
	print("    rope midpoint = %s (expected %s)" % [
		box.get_center().snapped(Vector3(0.01, 0.01, 0.01)),
		midpoint.snapped(Vector3(0.01, 0.01, 0.01)),
	])
	_ok("rope is centred between hand and anchor",
		box.get_center().distance_to(midpoint) < 0.2)
	_ok("rope is visible", rope.visible)
	_ok("rope is thick enough to see (>1 cm across)",
		_rope_thickness(rope) > 0.01, _rope_thickness(rope))

	# --- A long grapple must not stay at the native 1 m (the second bug) ---
	# Leave the grapple state first: while `is_grappled` is set the player's own
	# _physics_process calls _update_grapple_line() every tick and would overwrite
	# whatever geometry this check sets.
	player.is_grappled = false
	player.is_wall_attached = false

	player._set_line_between(Vector3(0, 0, 0), Vector3(0, 2, 0))
	await process_frame
	var short_thick := _rope_thickness(player._grapple_line as Node3D)
	player._set_line_between(Vector3(0, 0, 0), Vector3(0, 20, 0))
	await process_frame
	var long_len := _rope_length(player._grapple_line as Node3D)
	var long_thick := _rope_thickness(player._grapple_line as Node3D)
	print("    20 m pull -> rope length = %.2f m" % long_len)
	_ok("20 m grapple stretches the rope to 20 m", absf(long_len - 20.0) < 0.2, long_len)
	# A uniform scale would fatten the rope in proportion to its length.
	print("    thickness 2 m = %.4f m, 20 m = %.4f m" % [short_thick, long_thick])
	_ok("thickness is independent of length (no uniform-scale fattening)",
		absf(long_thick - short_thick) < 0.002,
		"%.4f vs %.4f" % [short_thick, long_thick])

	# --- Straight-up and horizontal pulls stay finite (degenerate basis guard) ---
	player._set_line_between(Vector3.ZERO, Vector3(0, 5, 0))
	await process_frame
	_ok("vertical pull produces a finite rope",
		is_finite(_rope_length(player._grapple_line as Node3D)))

	# --- A rope authored along X instead of Y must still point at the anchor ---
	# MODEL_MANIFEST asks for +Y, but the loader reads a length axis per spec, so
	# an X-authored rope has to work rather than stretch across the grapple.
	#
	# Built as holder + rotated child, which is the shape ModelLibrary returns for
	# a real model. Setting the holder's own transform is what _set_line_between
	# drives, so the child's internal rotation has to live below it.
	var y_rope: Node3D = player._grapple_line
	player._clear_grapple_line()

	var x_mesh := CylinderMesh.new()
	x_mesh.top_radius = 0.02
	x_mesh.bottom_radius = 0.02
	x_mesh.height = 1.0
	var x_child := MeshInstance3D.new()
	x_child.mesh = x_mesh
	# Cylinder height is along its own Y; rotate it so the rope runs along X.
	x_child.transform = Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5), Vector3.ZERO)
	var x_holder := Node3D.new()
	x_holder.add_child(x_child)
	player.add_child(x_holder)
	player._grapple_line = x_holder
	player._grapple_line_axis = Vector3.RIGHT
	player._grapple_line_base = 1.0

	player._set_line_between(Vector3.ZERO, Vector3(12, 0, 0))
	await process_frame
	var x_box := _rope_aabb(x_holder)
	print("    X-authored rope pulled along +X -> size %s" % x_box.size.snapped(Vector3(0.01, 0.01, 0.01)))
	_ok("X-authored rope stretches to 12 m", absf(x_box.size.x - 12.0) < 0.2, x_box.size.x)
	_ok("X-authored rope runs along the pull direction, not across it",
		x_box.size.z < 0.2 and x_box.size.y < 0.2,
		x_box.size.snapped(Vector3(0.01, 0.01, 0.01)))

	player._clear_grapple_line()
	if is_instance_valid(y_rope):
		player._grapple_line = y_rope
		player._grapple_line_axis = Vector3.UP
		player._grapple_line_base = 1.0

	# --- Releasing clears it, so it cannot linger on screen ---
	player.end_grapple()
	await process_frame
	_ok("end_grapple clears the rope",
		player._grapple_line == null or not is_instance_valid(player._grapple_line))

	# --- Enemy hold still gets a rope (regression on the original path) ---
	player._ensure_grapple_line()
	_ok("enemy hold still creates a rope", player._grapple_line != null)
	player._clear_grapple_line()

	print("\n%s" % ("FAILED: %d check(s)" % _fails if _fails > 0 else "PASSED: all grapple rope checks green"))
	quit(1 if _fails > 0 else 0)


## World-space AABB of the rope.
##
## Not ModelLibrary.world_aabb(): that walks `find_children`, which excludes the
## node itself, so it reports an empty box for the placeholder rope (a leaf
## MeshInstance3D). Once a real model lands the rope becomes a holder with mesh
## children and that helper works, so handle both shapes.
func _rope_aabb(rope: Node3D) -> AABB:
	if rope == null or not is_instance_valid(rope):
		return AABB()
	if rope is MeshInstance3D:
		var mi := rope as MeshInstance3D
		if mi.mesh == null:
			return AABB()
		return rope.global_transform * mi.get_aabb()
	return ModelLibrary.world_aabb(rope)


## World-space length of the rope along its own stretch axis.
func _rope_length(rope: Node3D) -> float:
	var box := _rope_aabb(rope)
	if box.size == Vector3.ZERO:
		return 0.0
	# Longest extent is the rope itself: it is far longer than it is thick.
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


## Shortest extent, i.e. the rope's diameter. Scaling is applied along the
## length axis only, so this must stay at the authored radius.
func _rope_thickness(rope: Node3D) -> float:
	var box := _rope_aabb(rope)
	if box.size == Vector3.ZERO:
		return 0.0
	return minf(box.size.x, minf(box.size.y, box.size.z))


func _ok(label: String, condition: bool, measured: Variant = null) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		if measured != null:
			print("  FAIL %s (measured %s)" % [label, str(measured)])
		else:
			print("  FAIL %s" % label)
		_fails += 1
