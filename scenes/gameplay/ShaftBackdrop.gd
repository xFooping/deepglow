class_name ShaftBackdrop
extends Node2D
## Everything behind and around the blocks: a parallax cave wall behind the open air, rocky side
## margins with roots, lanterns, crystals and mushrooms, and the floor and funnel walls of the boss
## chamber. Tinted by the shaft's palette. Redrawn every frame (it's only a few hundred tiles).

const BACK_TEXTURE := "res://art/backgrounds/cave_back.png"
const WALL_TEXTURE := "res://art/backgrounds/wall.png"
const DECOR_TEXTURE := "res://art/backgrounds/decor.png"
const FLOOR_TEXTURE := "res://art/backgrounds/floor.png"

var _shaft: Shaft
var _camera: CameraRig
var _back: Texture2D
var _wall: Texture2D
var _decor: Texture2D
var _floor: Texture2D
var _rock_tint := Color.WHITE
var _background := Color.BLACK
var _margin: int = 0
var _back_parallax: float
var _side_parallax: float
var _decor_chance: float


func setup(shaft: Shaft, camera: CameraRig) -> void:
	_shaft = shaft
	_camera = camera
	_back = DataDB.texture(BACK_TEXTURE)
	_wall = DataDB.texture(WALL_TEXTURE)
	_decor = DataDB.texture(DECOR_TEXTURE)
	_floor = DataDB.texture(FLOOR_TEXTURE)
	var palette: Dictionary = shaft.data["palette"]
	_rock_tint = Color.html(str(palette.get("rock_tint", "#ffffff")))
	_background = Color.html(str(palette.get("background", "#000000")))
	_margin = ceili((camera.view_size.x - shaft.width_px) * 0.5)
	_back_parallax = DataDB.num("visuals.back_parallax")
	_side_parallax = DataDB.num("visuals.side_parallax")
	_decor_chance = DataDB.num("visuals.side_decor_chance")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var view_top := -get_viewport().get_canvas_transform().origin.y
	var view_h := _camera.view_size.y
	var cell := _shaft.cell_px

	# Parallax cave wall behind the open air.
	draw_rect(Rect2(0, view_top - cell, _shaft.width_px, view_h + cell * 2), _background)
	if _back:
		var bs := _back.get_size()
		var shift := view_top * _back_parallax
		var y0 := floorf((view_top - shift) / bs.y) * bs.y + shift
		var tint := _background.lightened(0.25)
		var y := y0 - bs.y
		while y < view_top + view_h + bs.y:
			var x := 0.0
			while x < _shaft.width_px:
				var w := minf(bs.x, _shaft.width_px - x)
				draw_texture_rect_region(_back, Rect2(x, y, w, bs.y), Rect2(0, 0, w, bs.y), tint)
				x += bs.x
			y += bs.y

	# Side margins: rock wall with decorations, scrolling a little slower than the board.
	var side_shift := view_top * (1.0 - _side_parallax)
	var first_row := floori((view_top - side_shift) / cell) - 1
	var rows := ceili(view_h / cell) + 3
	for r in rows:
		var row := first_row + r
		var y := row * cell + side_shift
		for x in range(-_margin - cell, 0, cell):
			_wall_tile(Vector2(x, y), row, x)
		for x in range(int(_shaft.width_px), int(_shaft.width_px) + _margin + cell, cell):
			_wall_tile(Vector2(x, y), row, x)
		_side_decor(row, y)

	# Chamber floor and funnel walls (solid, part of the board, no parallax).
	var board_first := floori(view_top / cell) - 1
	for r in ceili(view_h / cell) + 3:
		var row := board_first + r
		for col in _shaft.columns:
			if row >= _shaft.floor_row or _shaft.is_chamber_wall(col, row):
				_tile(_floor, Vector2(col * cell, row * cell), Color.WHITE)


func _wall_tile(pos: Vector2, row: int, x: int) -> void:
	if _wall == null:
		draw_rect(Rect2(pos, Vector2(_shaft.cell_px, _shaft.cell_px)), _rock_tint.darkened(0.5))
		return
	var variants := maxi(1, floori(_wall.get_width() / float(_shaft.cell_px)))
	var v := absi(hash(Vector2i(row, x))) % variants
	draw_texture_rect_region(_wall, Rect2(pos, Vector2(_shaft.cell_px, _shaft.cell_px)),
		Rect2(v * _shaft.cell_px, 0, _shaft.cell_px, _shaft.cell_px), _rock_tint)


## A decoration now and then on each side margin, picked by a hash of the row so it's stable.
func _side_decor(row: int, y: float) -> void:
	if _decor == null:
		return
	var w := 16
	var h := int(_decor.get_height())
	var kinds := floori(_decor.get_width() / float(w))
	for side in 2:
		var hv := absi(hash(Vector3i(row, side, _shaft.shaft_id)))
		if float(hv % 1000) / 1000.0 >= _decor_chance:
			continue
		var kind := hv % kinds
		var offset := floori(hv / 7.0) % maxi(1, _margin - 32)
		var x := (-_margin + 8 + offset) if side == 0 else (int(_shaft.width_px) + 8 + offset)
		# Roots and lanterns hang from above; crystals and mushrooms sit on a ledge.
		draw_texture_rect_region(_decor, Rect2(x, y, w, h), Rect2(kind * w, 0, w, h), Color.WHITE.lerp(_rock_tint, 0.3))


func _tile(tex: Texture2D, pos: Vector2, tint: Color) -> void:
	if tex:
		draw_texture(tex, pos, tint)
	else:
		draw_rect(Rect2(pos, Vector2(_shaft.cell_px, _shaft.cell_px)), tint.darkened(0.5))
