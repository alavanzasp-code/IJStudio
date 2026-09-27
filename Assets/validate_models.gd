extends SceneTree

## One-off validation of ModelLibrary against the downloaded assets.
## Run: godot --headless --script Assets/validate_models.gd

func _initialize() -> void:
	print("=== ModelLibrary asset validation ===")
	var keys: Array = ModelLibrary.SPECS.keys()
	keys.sort()
	for key: String in keys:
		var path: String = ModelLibrary.SPECS[key]["path"]
		if not ResourceLoader.exists(path):
			print("  [MISSING] %-16s %s" % [key, path])
			continue
		var inst := ModelLibrary.instantiate_model(key)
		if inst == null:
			print("  [FAILED ] %-16s loaded but instantiate returned null" % key)
			continue
		var box := ModelLibrary.world_aabb(inst)
		var meshes := inst.find_children("*", "MeshInstance3D", true, false).size()
		var spec: Dictionary = ModelLibrary.SPECS[key]
		print(
			"  [OK     ] %-16s size=%-26s center=%-22s meshes=%d target=%.2f"
			% [
				key,
				str(box.size.snapped(Vector3(0.001, 0.001, 0.001))),
				str(box.get_center().snapped(Vector3(0.001, 0.001, 0.001))),
				meshes,
				float(spec["max_extent"]),
			]
		)
		inst.free()

	# Exercise the tiling path the arena uses.
	print("\n=== Tiling (arena) ===")
	for pair: Array in [["floor", Vector3(30, 1.2, 30)], ["wall", Vector3(30, 3.8, 0.5)]]:
		var key: String = pair[0]
		var target: Vector3 = pair[1]
		if not ModelLibrary.has_model(key):
			print("  [MISSING] %s" % key)
			continue
		var tiled := ModelLibrary.tile_to_fit(key, target)
		if tiled == null:
			print("  [FAILED ] %s" % key)
			continue
		var count := tiled.get_child_count()
		var covered := ModelLibrary.world_aabb(tiled).size
		print(
			"  [OK     ] %-6s target=%-22s tiles=%-5d world_covers=%s"
			% [key, str(target), count, str(covered.snapped(Vector3(0.01, 0.01, 0.01)))]
		)
		tiled.free()

	quit()
