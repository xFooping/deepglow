class_name ShaftBackdrop
extends Node2D
## Draws what sits behind and around the blocks: the open-air background, the decorative rock
## in the side margins, and the floor at the bottom of the shaft. Redraws only when the camera
## crosses a row.

const ROCK_TEXTURE := "res://art/backgrounds/rock.png"
const FLOOR_TEXTURE := "res://art/backgrounds/floor.png"

var _shaft: Shaft
var _camera: CameraRig
var _rock: Texture2D
var _floor: Texture2D
var _rock_tint := Color.WHITE
var _background := Color.BLACK
var _margin: int = 0
var _row: int = -999999


func setup(shaft: Shaft, camera: CameraRig) -> void:
	_shaft = shaft
	_camera = camera
	_rock = DataDB.texture(ROCK_TEXTURE)
	_floor = DataDB.texture(FLOOR_TEXTURE)
	var palette: Dictionary = shaft.data["palette"]
	_rock_tint = Color.html(str(palette.get("rock_tint", "#ffffff")))
	_background = Color.html(str(palette.get("background", "#000000")))
	_margin = ceili((camera.view_size.x - shaft.width_px) * 0.5)


func _process(_delta: float) -> void:
	var row := floori(_camera.top / _shaft.cell_px)
	if row != _row:
		_row = row
		queue_redraw()


func _draw() -> void:
	var cell := _shaft.cell_px
	var rows := ceili(_camera.view_size.y / cell) + 3
	var first := _row - 1
	draw_rect(Rect2(0, first * cell, _shaft.width_px, rows * cell), _background)
	for r in rows:
		var row := first + r
		var y := row * cell
		for x in range(-_margin - cell, 0, cell):
			_tile(_rock, Vector2(x, y), _rock_tint)
		for x in range(int(_shaft.width_px), int(_shaft.width_px) + _margin + cell, cell):
			_tile(_rock, Vector2(x, y), _rock_tint)
		if row >= _shaft.floor_row:
			for col in _shaft.columns:
				_tile(_floor, Vector2(col * cell, y), Color.WHITE)


func _tile(tex: Texture2D, pos: Vector2, tint: Color) -> void:
	if tex:
		draw_texture(tex, pos, tint)
	else:
		draw_rect(Rect2(pos, Vector2(_shaft.cell_px, _shaft.cell_px)), tint.darkened(0.5))
