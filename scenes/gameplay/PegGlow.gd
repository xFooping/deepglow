class_name PegGlow
extends Node2D
## Pegs light up when an ember bounces off them, warmer the longer the ember's combo.
## Drawn additively over the peg tiles and faded out over a short time.

const FADE_S := 0.45
const GLOW_TEXTURE := "res://art/embers/ember_glow.png"

var cell_px: int = 16

var _lit: Dictionary = {}  ## Vector2i cell -> [seconds left, combo]
var _tex: Texture2D


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_tex = DataDB.texture(GLOW_TEXTURE)
	set_process(false)


func light(cell: Vector2i, combo: int) -> void:
	_lit[cell] = [FADE_S, combo]
	set_process(true)


func _process(delta: float) -> void:
	for cell: Vector2i in _lit.keys():
		var entry: Array = _lit[cell]
		entry[0] = float(entry[0]) - delta
		if float(entry[0]) <= 0.0:
			_lit.erase(cell)
	if _lit.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var half := _tex.get_size() * 0.5
	for cell: Vector2i in _lit:
		var entry: Array = _lit[cell]
		var t := float(entry[0]) / FADE_S
		var warm := clampf(float(entry[1]) / 12.0, 0.0, 1.0)
		var c := Color(0.6, 0.9, 1.0).lerp(Color(1.0, 0.75, 0.35), warm)
		c.a = t
		var center := Vector2((cell.x + 0.5) * cell_px, (cell.y + 0.5) * cell_px)
		draw_texture(_tex, center - half, c)
