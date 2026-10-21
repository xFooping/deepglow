class_name TitleBackdrop
extends Control
## Title screen backdrop: dark cave rock, a lattice of glowing pegs and embers drifting down
## through it, bouncing off the pegs. Purely decorative.

const EMBERS := 18
const PEG_SPACING := 48

var _cave: Texture2D
var _glow: Texture2D
var _peg: Texture2D
var _embers: Array[Vector3] = []  ## x, y, speed
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cave = DataDB.texture("res://art/backgrounds/cave_back.png")
	_glow = DataDB.texture("res://art/embers/ember_glow.png")
	_peg = DataDB.texture("res://art/blocks/peg.png")
	_rng.randomize()
	for _i in EMBERS:
		_embers.append(Vector3(_rng.randf_range(0, 640), _rng.randf_range(-360, 360), _rng.randf_range(14, 30)))


func _process(delta: float) -> void:
	_time += delta
	var view := get_viewport_rect().size
	for i in _embers.size():
		var e := _embers[i]
		e.y += e.z * delta
		e.x += sin(_time * 1.3 + i) * 6.0 * delta
		if e.y > view.y + 20:
			e = Vector3(_rng.randf_range(0, view.x), -20, _rng.randf_range(14, 30))
		_embers[i] = e
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.07, 0.05, 0.09))
	if _cave:
		draw_texture_rect(_cave, Rect2(Vector2.ZERO, view), true, Color(0.2, 0.16, 0.26))
	if _peg:
		for row in range(0, int(view.y / PEG_SPACING) + 2):
			var off := PEG_SPACING * 0.5 if row % 2 == 1 else 0.0
			for col in range(0, int(view.x / PEG_SPACING) + 2):
				var p := Vector2(col * PEG_SPACING + off, row * PEG_SPACING + 20)
				var pulse := 0.16 + 0.08 * sin(_time * 0.8 + col * 0.7 + row)
				draw_texture(_peg, p - Vector2(8, 8), Color(1, 1, 1, pulse))
	if _glow:
		for e in _embers:
			draw_texture(_glow, Vector2(e.x, e.y) - Vector2(12, 12), Color(1, 0.8, 0.6, 0.9))
			draw_circle(Vector2(e.x, e.y), 1.5, Color(1.0, 0.9, 0.6))
