extends Node3D

## Swaps the arena's blockout visual meshes for real models, in place.
##
## The collision shapes are the source of truth for each block's size — the
## art is fitted to the collision, never the other way round, so gameplay
## geometry can never drift because of an asset swap.
##
## Attach to the arena root. Safe to run with no models downloaded: every
## `*_Placeholder` visual is left exactly as it is.
##
## Once the assets land, delete the placeholder MeshInstance3D nodes from
## `test_area.tscn` and this script becomes a no-op pass-through.

## Node-name fragment -> ModelLibrary key. First match wins.
const KEY_BY_NAME: Dictionary = {
	"floor": "floor",
	"decor": "wall_block",
}


func _ready() -> void:
	# Collect first: the swap mutates the tree mid-walk.
	var placeholders: Array[MeshInstance3D] = []
	for child: Node in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		# Only arena blockout: those visuals sit directly on a StaticBody3D.
		# Weapon/character placeholders hang off the player and must be left
		# alone — they are handled by their own scripts.
		if String(mi.name).ends_with("_Placeholder") and mi.get_parent() is StaticBody3D:
			placeholders.append(mi)

	for mi: MeshInstance3D in placeholders:
		_upgrade(mi)


## Replaces one blockout visual with a fitted model, if the asset exists.
func _upgrade(mi: MeshInstance3D) -> void:
	var key := _model_key_for(mi)
	if key.is_empty() or not ModelLibrary.has_model(key):
		# Asset not downloaded yet — the placeholder stays put, silently.
		return

	var box_size: Variant = _sibling_box_size(mi)
	if box_size == null:
		push_warning("ArenaVisualUpgrade: no sibling BoxShape3D for '%s'." % mi.name)
		return

	var target: Vector3 = box_size
	var fitted := ModelLibrary.tile_to_fit(key, target)
	if fitted == null:
		# Asset not downloaded yet — the placeholder stays put.
		return

	var parent := mi.get_parent()
	parent.add_child(fitted)
	fitted.name = String(mi.name).replace("_Placeholder", "_Model")
	# Inherit the blockout's placement so the swap is invisible to gameplay.
	fitted.transform = mi.transform
	mi.queue_free()


## Resolves which model this visual should become from its own and its parent's
## name, so the arena scene keeps working without extra tagging.
func _model_key_for(mi: MeshInstance3D) -> String:
	var haystacks: Array[String] = [String(mi.name).to_lower()]
	var parent := mi.get_parent()
	if parent != null:
		haystacks.append(String(parent.name).to_lower())

	for fragment: String in KEY_BY_NAME:
		for text: String in haystacks:
			if text.contains(fragment):
				return KEY_BY_NAME[fragment]

	# Anything else on the arena shell is perimeter walling.
	return "wall"


## Size of the BoxShape3D that belongs to this visual.
##
## The arena names its pairs by a shared stem — "WallEastCollision" goes with
## "WallEastMesh_Placeholder" — so match on that stem. Returning the *first*
## collision sibling instead would silently give every visual the floor's box.
func _sibling_box_size(mi: MeshInstance3D) -> Variant:
	var parent := mi.get_parent()
	if parent == null:
		return null

	var stem := String(mi.name)
	for suffix: String in ["Mesh_Placeholder", "_Placeholder", "Mesh", "Collision"]:
		if stem.ends_with(suffix):
			stem = stem.trim_suffix(suffix)
			break

	var fallback: Variant = null
	for sibling: Node in parent.get_children():
		if not (sibling is CollisionShape3D):
			continue
		var box := (sibling as CollisionShape3D).shape as BoxShape3D
		if box == null:
			continue
		if fallback == null:
			fallback = box.size
		if stem != "" and String(sibling.name).begins_with(stem):
			return box.size
	return fallback
