extends MeshInstance3D

const RADIAL_SEGMENTS := 8

const ROPE_SHADER_CODE := """
shader_type spatial;

uniform float stripe_scale : hint_range(1.0, 30.0) = 11.0;
uniform vec3 dark_color : source_color = vec3(0.28, 0.18, 0.10);
uniform vec3 light_color : source_color = vec3(0.55, 0.37, 0.22);

void fragment() {
	float twist = fract(UV.x + UV.y * stripe_scale);
	ALBEDO = mix(light_color, dark_color, step(0.5, twist));
	ROUGHNESS = 1.0;
}
"""

@export var tube_segments := 20
@export var rope_radius := 0.045

@onready var _player := get_parent() as Node3D

var is_active := false
var from_point := Vector3.ZERO
var to_point := Vector3.ZERO

var _clock := 0.0
var _base_sag := 0.5
var _wobble_amp := 0.0


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = ROPE_SHADER_CODE
	material.shader = shader
	material_override = material
	visible = false


func launch(from_world: Vector3, to_world: Vector3) -> void:
	from_point = from_world
	to_point = to_world
	_base_sag = clampf((to_point - from_point).length() * 0.05, 0.2, 1.2)
	_clock = 0.0
	_wobble_amp = 0.18
	is_active = true
	visible = true
	_rebuild()


func end() -> void:
	is_active = false
	visible = false
	mesh = null


func _process(delta: float) -> void:
	if not is_active:
		return

	_clock += delta
	_wobble_amp = maxf(0.0, _wobble_amp - delta * 1.3)
	from_point = _player.global_position + Vector3(0, 0.6, 0)
	_rebuild()


func _rebuild() -> void:
	var p0 := from_point
	var p2 := to_point
	if p0.distance_to(p2) < 0.01:
		mesh = null
		return

	var mid := (p0 + p2) * 0.5
	var sag: float = clampf(_clock / 0.35, 0.0, 1.0) * _base_sag
	var wob: float = _wobble_amp * (sin(_clock * 13.0) + sin(_clock * 21.0) * 0.4)
	var control := mid + Vector3.DOWN * sag + Vector3.RIGHT * wob

	var points := PackedVector3Array()
	var tangents := PackedVector3Array()
	for i in tube_segments + 1:
		var t_val := float(i) / tube_segments
		points.append(_quad_bezier(p0, control, p2, t_val))

	for i in points.size():
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		tangents.append((next - prev).normalized())

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in points.size():
		var tangent := tangents[i]
		var right := Vector3.UP.cross(tangent).normalized()
		if right.length() < 0.1:
			right = Vector3.FORWARD.cross(tangent).normalized()
		var heft := tangent.cross(right).normalized()
		var v := float(i) / tube_segments

		for j in RADIAL_SEGMENTS:
			var u := float(j) / RADIAL_SEGMENTS
			var radial := right * cos(u * TAU) + heft * sin(u * TAU)
			st.add_normal(radial)
			st.add_uv(Vector2(u, v))
			st.add_vertex(points[i] + radial * rope_radius)

	for i in tube_segments:
		var base := i * RADIAL_SEGMENTS
		var next_base := base + RADIAL_SEGMENTS
		for j in RADIAL_SEGMENTS:
			var j2 := (j + 1) % RADIAL_SEGMENTS
			var a := base + j
			var b := next_base + j
			var a2 := base + j2
			var b2 := next_base + j2
			st.add_index(a)
			st.add_index(b)
			st.add_index(b2)
			st.add_index(a)
			st.add_index(b2)
			st.add_index(a2)

	mesh = st.commit()


func _quad_bezier(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	var inv := 1.0 - t
	return inv * inv * a + 2.0 * inv * t * c + t * t * b