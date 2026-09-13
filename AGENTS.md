# AGENTS.md

## 1. Project Context & Stack
- **Project:** 3D Action Game built in Godot 4.x.
- **Primary Language:** GDScript (Godot 4 strict typing).
- **Asset Pipeline:** Custom `.glb` / `.gltf` 3D models imported into `res://assets/`.
- **Target Engine:** Godot 4.x (Do NOT use deprecated Godot 3 syntax like `KinematicBody`, `spatial`, `set_process(true)`, etc.).

---

## 2. Hard Boundaries & Prohibitions (STRICT)
- 🚫 **NO Procedural Meshes:** NEVER generate procedural geometry, `ImmediateMesh`, `SurfaceTool`, `ArrayMesh`, or `CSGPrimitive3D` nodes (`CSGBox3D`, `CSGCylinder3D`, etc.).
- 🚫 **Reference Existing Assets Only:** Visual representations must strictly reference existing `.glb`, `.gltf`, or `.tscn` files located in `res://assets/` or `res://scenes/`.
- 🚫 **Missing Assets:** If an asset (weapon, projectile, character) does not exist, DO NOT draw a substitute via code. Instantiate an empty `Marker3D` or `Node3D` placeholder, label it clearly (e.g., `WeaponSlot`, `SpawnPoint`), and leave a `# TODO: Assign model asset` comment.
- 🚫 **No Godot 3 Syntax Drift:** Always use `CharacterBody3D.velocity`, `move_and_slide()` with no arguments, `@export` instead of `export`, and `@onready` instead of `onready`.

---

## 3. Scene Hierarchy & Node Conventions
When generating `.tscn` scene files or creating nodes via script:
- **Static Objects (Props, Scenery):** 
  - Root: `StaticBody3D`
  - Children: Visual instance (`.glb`), `CollisionShape3D` matching geometry.
- **Dynamic Entities (Player, Enemies, NPCs):**
  - Root: `CharacterBody3D`
  - Children: Model instance (`Node3D` from `.glb`), `CollisionShape3D` (CapsuleShape3D aligned to ground), `AnimationPlayer` (referenced from model or sibling).
- **Spawnables (Projectiles, Pickups):**
  - Root: `Area3D` (or `RigidBody3D` if physics-driven)
  - Children: Model instance, `CollisionShape3D`.

---

## 4. Code Standards & Architecture
- **Static Typing:** Always type variables, method arguments, and return types (`var speed: float = 5.0`, `func fire() -> void:`).
- **Node Access:** Use `@onready` with unique names (`%NodeName`) or explicit relative paths; avoid fragile deep pathing (e.g., `../../Child`).
- **State Separation:** Logic lives in scripts attached to the root node of the scene. Visual models should remain pure data containers without attached game logic scripts.

### Pattern Example

```gdscript
# ✅ CORRECT: Typed, uses existing scene asset, no procedural generation
extends CharacterBody3D

@export var projectile_scene: PackedScene = preload("res://scenes/projectiles/arrow.tscn")
@onready var muzzle_marker: Marker3D = %MuzzlePoint

func shoot() -> void:
	if not projectile_scene:
		push_warning("Projectile scene not assigned!")
		return
	var arrow: Node3D = projectile_scene.instantiate()
	arrow.global_transform = muzzle_marker.global_transform
	get_tree().current_scene.add_child(arrow)

# ❌ WRONG: Generates procedural geometry via code
func shoot() -> void:
	var mesh_instance = MeshInstance3D.new()
	var cylinder = CylinderMesh.new() # FORBIDDEN
	mesh_instance.mesh = cylinder
	add_child(mesh_instance)

---

## 5. Verification & Definition of Done
Before completing any task:
- Ensure all node references and scene paths point to valid paths inside res://.
- Confirm no procedural primitives or CSG nodes were introduced.
- Validate that all signals, function signatures, and engine calls follow Godot 4.x syntax.
