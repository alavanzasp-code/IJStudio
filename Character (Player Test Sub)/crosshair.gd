extends TextureRect

var _normal_tex: ImageTexture
var _valid_tex: ImageTexture
var _enemy_tex: ImageTexture
var _exec_tex: ImageTexture

func _ready() -> void:
	_normal_tex = _make_crosshair(Color(1, 1, 1, 0.7))
	_valid_tex = _make_crosshair(Color(0.2, 1.0, 0.3, 1.0))
	_enemy_tex = _make_crosshair(Color(1.0, 0.6, 0.1, 1.0))
	_exec_tex = _make_crosshair(Color(1.0, 0.15, 0.15, 1.0))
	texture = _normal_tex
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_valid_target(valid: bool) -> void:
	texture = _valid_tex if valid else _normal_tex


func set_enemy_state(executable: bool) -> void:
	texture = _exec_tex if executable else _enemy_tex


func reset() -> void:
	texture = _normal_tex


func _make_crosshair(color: Color) -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)

	# Horizontal lines with a gap in the center
	for x in range(5, 14):
		img.set_pixel(x, 16, color)
	for x in range(18, 27):
		img.set_pixel(x, 16, color)

	# Vertical lines with a gap in the center
	for y in range(5, 14):
		img.set_pixel(16, y, color)
	for y in range(18, 27):
		img.set_pixel(16, y, color)

	# Center dot
	for x in range(15, 17):
		for y in range(15, 17):
			img.set_pixel(x, y, color)

	return ImageTexture.create_from_image(img)
