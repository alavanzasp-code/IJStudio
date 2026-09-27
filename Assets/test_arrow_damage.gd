extends SceneTree

## Regression test for arrow damage.
##
## Guards a bug that made EVERY hit deal 0 damage: `body_entered` is emitted
## after the physics solver has already stopped the body, so reading
## `linear_velocity` in the handler returns 0. The arrow now remembers the last
## speed it was actually travelling at.
##
## Exits non-zero on failure, so it can gate a commit.
##   godot --headless --script Assets/test_arrow_damage.gd

const ARROW_SCENE := "res://Weapons/arrow_(test).tscn"
const TARGET := "DummyGround"

var _failures := 0


func _initialize() -> void:
	var packed := ResourceLoader.load("res://Test Area (World)/test_area.tscn") as PackedScene
	if packed == null:
		_fail("could not load the main scene")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var dummy := scene.get_node(TARGET) as TestDummy
	var player := scene.get_node("Player (Test)")
	if dummy == null or player == null:
		_fail("missing %s or the player" % TARGET)
		quit(1)
		return

	# Damage must scale with charge: a tapped shot must still hurt.
	for case: Array in [[55.0, 40.0], [30.0, 20.0], [15.0, 5.0]]:
		await _check(dummy, player, case[0], case[1])

	if _failures > 0:
		print("\nFAILED: %d check(s)" % _failures)
		quit(1)
	else:
		print("\nPASSED: all arrow damage checks green")
		quit(0)


## Fires one arrow and asserts it dealt meaningful damage.
func _check(dummy: TestDummy, player: Node, speed: float, min_damage: int) -> void:
	dummy.health = dummy.max_health
	dummy.visible = true
	dummy.collision_layer = 1
	dummy.collision_mask = 1
	dummy.set("_dead", false)
	await process_frame

	var arrow := (ResourceLoader.load(ARROW_SCENE) as PackedScene).instantiate() as RigidBody3D
	var from: Vector3 = player.global_position + Vector3(0, 0.2, 0)
	var target: Vector3 = dummy.global_position + Vector3(0, 0.9, 0)
	var dir := (target - from).normalized()

	# Same order as Bow.fire().
	root.get_child(0).add_child(arrow)
	arrow.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), from)
	arrow.linear_velocity = dir * speed
	arrow.add_collision_exception_with(player)
	arrow.call("set_source", player)

	var before: int = dummy.health
	for i: int in 120:
		await physics_frame
	var dealt := before - int(dummy.health)

	if dealt < min_damage:
		_fail("%.0f m/s: dealt %d damage, expected at least %d" % [speed, dealt, min_damage])
	elif dealt > before:
		_fail("%.0f m/s: dealt %d damage but the dummy only had %d HP" % [speed, dealt, before])
	else:
		print("  ok  %.0f m/s -> %2d damage (HP %d -> %d)" % [speed, dealt, before, dummy.health])

	arrow.queue_free()
	await process_frame


func _fail(msg: String) -> void:
	_failures += 1
	print("  FAIL %s" % msg)
