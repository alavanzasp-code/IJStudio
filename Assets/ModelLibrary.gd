class_name ModelLibrary
extends RefCounted

## Asset-driven model loader.
##
## Every placeholder in this project resolves through [constant SPECS]. A real
## `.glb` dropped at the listed path is instantiated and auto-normalized to
## match the placeholder's real-world size; if the file is absent the caller
## falls back to its labeled `*_Placeholder` primitives.
##
## That means adding art is a pure file-drop: no script edits, no rescaling by
## hand, no node wiring. See `res://Assets/MODEL_MANIFEST.md` for the full
## contract (orientation, target size, licensing) of each entry.
##
## Nothing here builds geometry — models always come from authored assets.

## Logical key -> normalized model spec.
##
## - `path`         where the authored asset lives (must be a .glb/.gltf/.tscn)
## - `max_extent`   the model's longest axis is scaled to this many METERS, so
##                  every asset reads at the same world size as the primitive it
##                  replaces. `0.0` disables rescaling (use the asset as-is).
## - `length_axis`  local axis the asset is stretched along for ropes/cords.
## - `rotation`     degrees applied to fix the asset's authoring orientation.
## - `offset`       meters added after centering, to sit the model on its
##                  collision shape (e.g. feet on the floor).
const SPECS: Dictionary = {
	# --- Weapons ---------------------------------------------------------
	# Authored along +Z with the tip at -Z, matching the flight basis built in
	# Arrow._integrate_forces. Longest axis is the shaft (0.9 m placeholder).
	"arrow": {
		"path": "res://Assets/models/weapons/arrow/model.gltf",
		"max_extent": 1.06,
		"rotation": Vector3.ZERO,
		"offset": Vector3.ZERO,
	},
	# Authored lying along +Z with the belly facing +X. The 90/90 lift stands it
	# upright AND turns the limb plane into the sagittal (YZ) plane, so the belly
	# faces the aim direction and the model's own string faces the archer.
	# This is what Bow._nock's draw slide (-0.06 -> +0.10 on Z) assumes.
	"bow": {
		"path": "res://Assets/models/weapons/bow/model.gltf",
		"max_extent": 1.22,
		"rotation": Vector3(90, 90, 0),
		"offset": Vector3.ZERO,
	},

	# --- Characters ------------------------------------------------------
	# Origin at the FEET, ~1.8 m tall, facing -Z (Godot's forward).
	# Geometry is centered on the origin by the loader, so the +0.9 Y offset
	# drops a standing character back down onto the floor.
	"training_dummy": {
		"path": "res://Assets/models/characters/training_dummy/model.gltf",
		"max_extent": 1.8,
		"rotation": Vector3.ZERO,
		"offset": Vector3(0, 0.9, 0),
	},
	"player_body": {
		"path": "res://Assets/models/characters/player_body/model.gltf",
		"max_extent": 1.8,
		"rotation": Vector3.ZERO,
		"offset": Vector3(0, 0.9, 0),
	},

	# --- Props / Grapple -------------------------------------------------
	# NOT YET SOURCED — see MODEL_MANIFEST.md. Must be a straight, untextured-seam
	# rope authored along +Y, exactly 1.0 m long, so it can be stretched to any
	# grapple distance without distorting.
	"grapple_rope": {
		"path": "res://Assets/models/props/grapple_rope/model.gltf",
		"max_extent": 1.0,
		"length_axis": Vector3.UP,
		"rotation": Vector3.ZERO,
		"offset": Vector3.ZERO,
	},

	# --- Environment -----------------------------------------------------
	# Tiling floor slabs. `tile` scales the model so its longest axis covers the
	# collision box exactly, keeping UV density even across the arena.
	"floor": {
		"path": "res://Assets/models/environment/floor/model.gltf",
		"max_extent": 8.0,
		"rotation": Vector3.ZERO,
		"offset": Vector3.ZERO,
	},
	# One precast concrete perimeter panel, ~6 m wide. Deliberately a solid
	# slab that fills its bounding box: a 5.9 m x 0.5 m wall is a
	# building-facade shape, and the only Sketchfab assets that matched it were
	# cut-outs of real building exteriors.
	"wall": {
		"path": "res://Assets/models/environment/wall/model.gltf",
		"max_extent": 6.0,
		"rotation": Vector3.ZERO,
		"offset": Vector3.ZERO,
	},
	# Free-standing blockout pieces (pillars, rubble, crates).
	"wall_block": {
		"path": "res://Assets/models/environment/wall_block/model.gltf",
		"max_extent": 1.0,
		"rotation": Vector3.ZERO,
		"offset": Vector3.ZERO,
	},
}


## Returns true when a real asset is present for [param key].
##
## Cheap enough to call per-instance; use it to skip building placeholder
## primitives entirely once art has landed.
static func has_model(key: String) -> bool:
	var spec: Variant = SPECS.get(key)
	if spec == null:
		return false
	return ResourceLoader.exists(String(spec["path"]))


## Loads the [PackedScene] backing [param key], or `null` if unavailable.
## Index (0=X, 1=Y, 2=Z) of a vector's largest component.
static func _dominant_axis(v: Vector3) -> int:
	if v.x >= v.y and v.x >= v.z:
		return 0
	return 1 if v.y >= v.z else 2


## Largest single-axis extent of a size. NOT the diagonal — normalizing by
## `size.length()` would shrink a cube and leave a needle oversized.
static func _longest_axis(size: Vector3) -> float:
	return maxf(size.x, maxf(size.y, size.z))


## Where a model-space axis lands in world space after the tiling basis maps
## the model's long axis onto the target's long axis.
static func _world_axis_of(model_axis: int, from: int, to: int) -> int:
	if model_axis == from:
		return to
	if model_axis == to:
		return from
	return model_axis


## Basis that rotates the unit axis [param from] onto the unit axis
## [param to], staying orthonormal and right-handed.
static func _axis_align_basis(from: int, to: int) -> Basis:
	if from == to:
		return Basis.IDENTITY
	var unit := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var cols := [unit[0], unit[1], unit[2]]
	cols[to] = unit[from]
	cols[from] = unit[to]
	var rest := 3 - from - to
	cols[rest] = cols[to].cross(cols[from])
	var b := Basis(cols[0], cols[1], cols[2])
	if b.determinant() < 0.0:
		# Rare, but a mirrored basis would invert the asset's winding.
		cols[to] = -cols[to]
		b = Basis(cols[0], cols[1], cols[2])
	return b


## Godot 4's `deg_to_rad` is float-only, so convert per component.
static func _basis_from_degrees(deg: Vector3) -> Basis:
	return Basis.from_euler(
		Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
	)


## Loads the [PackedScene] at [param path], or [param key]'s spec path when
## [param path] is empty. `null` when unavailable.
static func _load_packed(key: String, path_override: String = "") -> PackedScene:
	var path := path_override
	if path.is_empty():
		var spec: Variant = SPECS.get(key)
		if spec == null:
			push_warning("ModelLibrary: unknown model key '%s'." % key)
			return null
		path = String(spec["path"])

	if not ResourceLoader.exists(path):
		return null

	var packed := ResourceLoader.load(path) as PackedScene
	if packed == null:
		push_warning("ModelLibrary: '%s' is not a PackedScene — skipping." % path)
	return packed


## Instantiates the model for [param key] and normalizes it to spec size.
##
## Returns a ready-to-parent wrapper [Node3D], or `null` when the asset is
## missing so the caller can fall back to its placeholder primitives.
## The caller owns the result and should `free()` it on any failure path.
static func instantiate_model(key: String) -> Node3D:
	var spec: Variant = SPECS.get(key)
	if spec == null:
		push_warning("ModelLibrary: unknown model key '%s'." % key)
		return null
	var packed := _load_packed(key)
	if packed == null:
		return null
	return _normalized_instance(key, spec, packed)


## One instance, scaled to the spec's target size and centered on the origin.
static func _normalized_instance(key: String, spec: Dictionary, packed: PackedScene) -> Node3D:
	var root := packed.instantiate()
	var model := root as Node3D
	if model == null:
		# Non-3D asset (texture/audio) assigned by mistake.
		root.free()
		push_warning("ModelLibrary: '%s' has no Node3D root — skipping." % spec["path"])
		return null

	# Normalize inside a private wrapper so the spec's rotation/offset do not
	# contaminate the measured AABB of the model itself.
	var holder := Node3D.new()
	holder.name = "%sModel" % key.to_pascal_case()
	holder.rotation_degrees = spec["rotation"] as Vector3
	model.name = "Source"
	holder.add_child(model)

	var measured := measure_aabb(model)
	if _longest_axis(measured.size) > 0.0001:
		var target := float(spec["max_extent"])
		if target > 0.0:
			# Uniform scale on the LONGEST axis: preserves the asset's
			# proportions no matter how it was authored or exported.
			var uniform := target / _longest_axis(measured.size)
			model.scale = Vector3(uniform, uniform, uniform)
			# AABB has no scale helper — scale origin and extents directly.
			measured = AABB(measured.position * uniform, measured.size * uniform)
		# Re-center so the AABB middle sits on the origin, then apply the spec
		# offset (e.g. lift a character so its feet rest on the floor).
		model.position = -measured.get_center() + (spec["offset"] as Vector3)

	holder.set_meta("model_key", key)
	holder.set_meta("source_aabb", measured)
	return holder


## Tiles a model across a volume so large surfaces keep an even UV density.
##
## Stretching one instance over a 30 m floor would smear the texture, so instead
## the target box is filled with whole tiles and the result is scaled by the
## small leftover. Whole tiles keep every instance at its native proportions.
##
## [param target] is the world size to cover. Returns `null` if the asset is
## unavailable or carries no geometry. Guard callers with a tile cap: prefer a
## tiling *texture* over a tiled model for very large floors.
## Keys already reported as badly distorted, so a 20-instance wall does not
## print the same warning twenty times in one frame.
static var _distortion_reported: Dictionary = {}


static func tile_to_fit(
	key: String,
	target: Vector3,
	max_tiles := 256,
	max_distortion := 0.25,
	path_override := ""
) -> Node3D:
	var spec: Variant = SPECS.get(key)
	if spec == null:
		return null
	var packed := _load_packed(key, path_override)
	if packed == null:
		return null

	var probe := _normalized_instance(key, spec, packed)
	if probe == null:
		return null
	var raw := normalized_aabb(probe).size
	if _longest_axis(raw) <= 0.0001:
		probe.free()
		return null

	# Orient the model so its longest axis follows the target's longest axis,
	# then tile on that axis. Without this a wall authored along Z tiles along
	# Z and leaves the 30 m span of an arena wall completely uncovered.
	var model_axis := _dominant_axis(raw)
	var target_axis := _dominant_axis(target.abs())
	# Grid math happens in the MODEL's own frame; `oriented` then carries that
	# frame into the world. Permuting the tile size here as well would apply the
	# axis swap twice and land the long edge on the wrong world axis.
	var tile := raw
	var thin_axis := 0
	for axis: int in 3:
		if raw[axis] < raw[thin_axis]:
			thin_axis = axis
	var is_flat := raw[thin_axis] <= 0.0001
	# The probe exists only to measure `raw`; release it here. Freeing it again
	# on a later exit path double-frees and crashes the engine.
	probe.free()

	var root := Node3D.new()
	root.name = "%sTiled" % key.to_pascal_case()
	var oriented := _axis_align_basis(model_axis, target_axis) * _basis_from_degrees(
		spec["rotation"] as Vector3
	)
	var offset := spec["offset"] as Vector3

	var counts := Vector3i()
	var total := 1
	var steps := Vector3()
	var t := target.abs()
	var t_longest := maxf(t.x, maxf(t.y, t.z))
	for axis: int in 3:
		# How long this model axis must become once the basis carries it to world.
		var want: float = t[_world_axis_of(axis, model_axis, target_axis)]
		var step: float = tile[axis]
		# A zero-thickness axis (or a target thinner than one tile) is a single
		# tile that gets squashed to fit rather than repeated.
		var count: int = 1 if step <= 0.0001 else maxi(roundi(want / step), 1)
		counts[axis] = count
		total *= count
		steps[axis] = step * count if step > 0.0001 else 0.0

	if total > max_tiles:
		push_warning(
			"ModelLibrary: tiling '%s' over %s needs %d instances (cap %d) — using one stretched copy."
			% [key, target, total, max_tiles]
		)
		return _normalized_instance(key, spec, packed)

	for ix in counts.x:
		for iy in counts.y:
			for iz in counts.z:
				var inst := _normalized_instance(key, spec, packed)
				if inst == null:
					continue
				inst.name = "Tile_%d_%d_%d" % [ix, iy, iz]
				inst.position = offset + Vector3(
					(float(ix) - float(counts.x - 1) * 0.5) * tile.x,
					(float(iy) - float(counts.y - 1) * 0.5) * tile.y,
					(float(iz) - float(counts.z - 1) * 0.5) * tile.z
				)
				root.add_child(inst)

	# Absorb the sub-tile remainder so the block covers the full target box.
	var fit := Vector3.ONE
	var worst := 1.0
	for axis: int in 3:
		var world_axis := _world_axis_of(axis, model_axis, target_axis)
		var want: float = t[world_axis]
		if steps[axis] <= 0.0001:
			fit[axis] = 1.0
			continue
		fit[axis] = want / steps[axis]
		# Thickness is cheap to scale and nobody can see the difference between
		# a 0.4 m and a 0.5 m wall, so it is exempt. Judge thickness on the
		# WORLD axis this one maps to — a model axis and its world axis are not
		# the same index once the tiling basis has swapped them. A flat model's
		# own thin axis is exempt too, where the geometry is a plane either way.
		var is_thickness := t[world_axis] < t_longest * 0.1
		if is_thickness or (is_flat and axis == thin_axis):
			continue
		worst = maxf(worst, maxf(fit[axis], 1.0 / fit[axis]))
	# A badly distorted tile looks worse than the blockout it replaces, and it
	# is a symptom of the wrong asset for this block — not of a tuning problem.
	if worst > 1.0 + max_distortion:
		var reason := "%s:%.2f" % [key, worst]
		if not _distortion_reported.has(reason):
			_distortion_reported[reason] = true
			push_warning(
				"ModelLibrary: '%s' cannot fill %s without %.0f%% distortion — keeping the placeholder. Source an asset with proportions closer to this block."
				% [key, target, (worst - 1.0) * 100.0]
			)
		for child: Node in root.get_children():
			child.free()
		root.free()
		return null
	# `fit` is expressed along the MODEL's axes, so it must be post-multiplied to
	# apply before the rotation. Basis.scaled() and from_scale()*oriented both
	# scale in the parent's frame instead, which lands the long edge on the
	# wrong world axis and leaves the arena wall mostly uncovered.
	root.basis = oriented * Basis.from_scale(fit)
	return root


## Local-space AABB of every [MeshInstance3D] under [param node].
##
## Exposed so runtime code that stretches a model (the grapple rope) can derive
## its scale from the asset's real dimensions instead of a hardcoded guess.
static func measure_aabb(node: Node3D) -> AABB:
	var combined := AABB()
	var found := false

	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# `transform` is relative to the mesh's immediate parent, which may be a
		# Skeleton3D rather than `node` — so walk the chain up by hand. The mesh
		# may also not be in the tree yet, which rules out global_transform.
		var to_mesh := mi.transform
		var walker := mi.get_parent()
		while walker != null and walker != node:
			var step := walker as Node3D
			if step == null:
				break
			to_mesh = step.transform * to_mesh
			walker = walker.get_parent()
		if walker != node:
			# Detached from the subtree we were asked to measure — skip it.
			continue
		var box: AABB = to_mesh * mi.get_aabb()
		combined = box if not found else combined.merge(box)
		found = true

	return combined


## World-space AABB of [param node], accounting for its own transform.
## Use this to check what a node actually covers, not just its local geometry.
static func world_aabb(node: Node3D) -> AABB:
	var box := measure_aabb(node)
	if box.size == Vector3.ZERO:
		return box
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(node.transform * box.get_endpoint(i))
	var world := AABB(corners[0], Vector3.ZERO)
	for c: Vector3 in corners:
		world = world.expand(c)
	return world


## The asset's normalized AABB, read from a node returned by
## [method instantiate_model]. Empty if the model carried no geometry.
static func normalized_aabb(instance: Node3D) -> AABB:
	var box: Variant = instance.get_meta("source_aabb", null)
	return box as AABB if box != null else AABB()


## Which local axis a model is meant to be stretched along.
## Defaults to +Y when the spec does not declare one.
static func length_axis(key: String) -> Vector3:
	var spec: Variant = SPECS.get(key)
	if spec == null:
		return Vector3.UP
	return (spec.get("length_axis", Vector3.UP) as Vector3)
