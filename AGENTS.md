# AGENTS.md

## 1. Project Context & Stack
- **Project:** 3D Action Game built in Godot 4.x.
- **Primary Language:** GDScript (Godot 4 strict typing).
- **Asset Pipeline:** Custom `.glb` / `.gltf` 3D models imported into `res://assets/`.
- **Target Engine:** Godot 4.x (Do NOT use deprecated Godot 3 syntax like `KinematicBody`, `spatial`, `set_process(true)`, etc.).

---

## 2. Hard Boundaries & Prohibitions (STRICT)
- 🚫 **NO Final-Game Procedural Meshes:** NEVER build final game geometry with `ImmediateMesh`, `SurfaceTool`, or `ArrayMesh`. These are forbidden at all times.
- ✅ **DEV/Test Placeholder Primitives (ALLOWED):** Until real `.glb`/`.gltf` assets exist in `res://assets/`, primitive meshes (`BoxMesh`, `CylinderMesh`, `CapsuleMesh`, etc.) and CSG nodes are ALLOWED **only** as clearly-labeled development placeholders so the game stays visible and interactable. Mandatory rules:
  - Placeholders use a `_Placeholder` suffix in the node/mesh name, or are grouped under a parent named `PlaceholderVisuals`.
  - Each placeholder has a `# TODO: Assign model asset (path)` comment stating the intended asset.
  - Static geometry: use `StaticBody3D` + `MeshInstance3D` (primitive mesh) + `CollisionShape3D` matching. Prefer this over CSG.
  - CSG nodes are allowed only for quick level-blockout; never in final content.
  - When the real asset is added, the placeholder is replaced by the instanced `.glb`/`.gltf`/`.tscn` — placeholders must never ship as final content.
- 🚫 **Never Mix:** A placeholder may exist only where NO real asset is available. If a real `.glb`/`.gltf`/`.tscn` exists for that purpose, it MUST be used instead.
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

# ✅ CORRECT: Labeled placeholder primitive — allowed until the real .glb exists
func build_placeholder_visuals() -> void:
	var visuals := Node3D.new()
	visuals.name = "PlaceholderVisuals"
	# TODO: Assign model asset (res://assets/weapons/arrow.glb)
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft_Placeholder"
	var cylinder := CylinderMesh.new()
	cylinder.height = 0.9
	shaft.mesh = cylinder
	visuals.add_child(shaft)
	add_child(visuals)

# ❌ WRONG: Anonymous, unlabeled primitive geometry with no asset plan
func shoot() -> void:
	var mesh_instance = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	mesh_instance.mesh = cylinder
	add_child(mesh_instance)

---

## 5. Verification & Definition of Done
Before completing any task:
- Ensure all node references and scene paths point to valid paths inside res://.
- Confirm no `ImmediateMesh`, `SurfaceTool`, or `ArrayMesh` was used, and that any primitive/CSG placeholders follow the Section-2 labeling + TODO rules.
- Validate that all signals, function signatures, and engine calls follow Godot 4.x syntax.
