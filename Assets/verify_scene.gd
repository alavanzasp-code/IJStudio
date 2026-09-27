extends SceneTree

## End-to-end check: loads the real main scene and reports what actually ended
## up in the tree, so a silent no-op can't be mistaken for success.
##   godot --headless --script Assets/verify_scene.gd

func _initialize() -> void:
	var main_path := "res://Test Area (World)/test_area.tscn"
	var packed := ResourceLoader.load(main_path) as PackedScene
	if packed == null:
		print("FAILED to load %s" % main_path)
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	# Let _ready run on the whole tree.
	await process_frame
	await process_frame

	var placeholders := 0
	var models := 0
	var tiled_tiles := 0
	var report: Array[String] = []
	# GDScript lambdas capture ints by value, so tally through an array.
	var tally := [0, 0, 0]

	_walk(scene, func(n: Node) -> void:
		var name_s := String(n.name)
		if name_s.ends_with("_Placeholder"):
			tally[0] += 1
		elif name_s.ends_with("Model") or name_s.ends_with("_Model") or name_s.begins_with("Tiled"):
			tally[1] += 1
		if name_s.begins_with("Tile_"):
			tally[2] += 1
	)
	placeholders = tally[0]
	models = tally[1]
	tiled_tiles = tally[2]

	print("=== Scene verification: %s ===" % main_path)
	print("  remaining *_Placeholder nodes : %d" % placeholders)
	print("  model nodes from ModelLibrary : %d" % models)
	print("  environment tiles             : %d" % tiled_tiles)
	print("")

	# Detail the interesting nodes.
	for n: Node in _collect(scene):
		var s := String(n.name)
		if s.ends_with("_Model") or s.begins_with("Tile_"):
			continue
		if n is Node3D and (n.get_child_count() > 0):
			var mi_count := (n as Node3D).find_children("*", "MeshInstance3D", true, false).size()
			if mi_count > 0 and (s.contains("Arena") or s.contains("Decor") or s.contains("Dummy") or s.contains("Bow") or s.contains("Player")):
				report.append("  %-34s meshes=%d" % [s, mi_count])
	for line: String in report:
		print(line)

	# Confirm each placeholder that was expected to be replaced is gone.
	print("")
	for expect: String in ["FloorMesh_Placeholder", "WallEastMesh_Placeholder", "PlayerBody_Placeholder", "Shaft_Placeholder", "Grip_Placeholder", "Body_Placeholder"]:
		var found := scene.find_child(expect, true, false) != null
		print("  %-28s %s" % [expect, "STILL PRESENT" if found else "replaced"])

	quit()


func _collect(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c: Node in n.get_children():
		out.append_array(_collect(c))
	return out


func _walk(n: Node, fn: Callable) -> void:
	fn.call(n)
	for c: Node in n.get_children():
		_walk(c, fn)
