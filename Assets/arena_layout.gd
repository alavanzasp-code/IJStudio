extends SceneTree

## Diagnostic: dumps the real world-space layout of the arena and prints an
## ASCII top-down map built from the *collision* shapes (authored, pre-swap).
##   godot --headless --script Assets/arena_layout.gd

const CELL := 1.0  # metres per ASCII cell


func _initialize() -> void:
	var packed := ResourceLoader.load("res://Test Area (World)/test_area.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var arena := scene.find_child("Arena", true, false) as StaticBody3D
	if arena == null:
		print("no Arena node")
		quit(1)
		return

	print("=== Arena children (scene file values, before any runtime swap) ===")
	var boxes: Array[Dictionary] = []
	for child: Node in arena.get_children():
		var origin: Vector3 = child.global_position
		if child is CollisionShape3D:
			var box := (child as CollisionShape3D).shape as BoxShape3D
			if box == null:
				continue
			var half := box.size * 0.5
			boxes.append({
				"name": String(child.name),
				"min": origin - half,
				"max": origin + half,
			})
		elif child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh as BoxMesh
			if mesh == null:
				continue
			var half := mesh.size * 0.5
			boxes.append({
				"name": String(child.name),
				"min": origin - half,
				"max": origin + half,
			})

	for b: Dictionary in boxes:
		print(
			"  %-34s x[%7.2f,%7.2f] y[%6.2f,%6.2f] z[%7.2f,%7.2f]"
			% [
				b["name"],
				(b["min"] as Vector3).x, (b["max"] as Vector3).x,
				(b["min"] as Vector3).y, (b["max"] as Vector3).y,
				(b["min"] as Vector3).z, (b["max"] as Vector3).z,
			]
		)

	_print_map(boxes)
	await _print_runtime(scene)
	quit()


## Top-down ASCII map. '#' = any wall covering that cell. Cells are sampled at
## their CENTRE, which is what makes a 0.5 m thick wall visible at all: a
## half-open [min, max) test on a 1 m grid whose samples sit on integers steps
## straight over a wall spanning [19.5, 20.0).
func _print_map(boxes: Array[Dictionary]) -> void:
	var extent := 26.0
	var n := int(extent * 2.0 / CELL)
	print("\n=== Top-down map (collision+mesh AABBs, %d x %d cells at %.1f m) ===" % [n, n, CELL])
	print("    +%s+" % ("-".repeat(n)))

	var rows: Array[String] = []
	# z from +extent (top of map, "north") down to -extent.
	var z := extent - CELL * 0.5
	while z > -extent:
		var row := ""
		var x := -extent + CELL * 0.5
		while x < extent:
			var hit := false
			for b: Dictionary in boxes:
				var lo: Vector3 = b["min"]
				var hi: Vector3 = b["max"]
				var mid_y := (lo.y + hi.y) * 0.5
				# The floor is a wide flat slab; skip it so it does not paint
				# every cell and hide the walls standing on it.
				if hi.y - lo.y < 1.5:
					continue
				if x >= lo.x and x <= hi.x and z >= lo.z and z <= hi.z and mid_y > 0.5:
					hit = true
					break
			row += "#" if hit else "."
			x += CELL
		rows.append(row)
		z -= CELL

	# z+ is up on screen, so print from the far side down.
	for r: String in rows:
		print("    |%s|" % r)
	print("    +%s+" % ("-").repeat(n))
	print("    x runs %+.1f (left) .. %+.1f (right), z runs %+.1f (top) .. %+.1f (bottom)"
		% [-extent, extent, extent, -extent])


## After _ready has run, report what the ModelLibrary swap actually produced,
## using real world AABBs rather than the authored numbers.
func _print_runtime(scene: Node) -> void:
	await process_frame
	await process_frame
	print("\n=== Arena after runtime swap (world AABB per top-level child) ===")
	var arena := scene.find_child("Arena", true, false) as StaticBody3D
	for child in arena.get_children():
		if child is CollisionShape3D:
			continue
		var n3 := child as Node3D
		if n3 == null:
			continue
		var aabb := ModelLibrary.world_aabb(n3)
		if aabb.size == Vector3.ZERO:
			print("  %-34s (no mesh geometry)" % child.name)
			continue
		print(
			"  %-34s x[%7.2f,%7.2f] y[%6.2f,%6.2f] z[%7.2f,%7.2f]  meshes=%d"
			% [
				child.name,
				aabb.position.x, aabb.end.x,
				aabb.position.y, aabb.end.y,
				aabb.position.z, aabb.end.z,
				n3.find_children("*", "MeshInstance3D", true, false).size(),
			]
		)
