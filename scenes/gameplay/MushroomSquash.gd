class_name MushroomSquash
extends Node2D
## Iron Veins twist visuals: a mushroom peg squashes and springs back when an ember bounces off it.
## The tile is hidden while the squashed copy is drawn here, then restored.

var _shaft: Shaft
var _tex: Texture2D
var _left: Dictionary = {}  ## Vector2i cell -> seconds left
var _duration: float


func setup(shaft: Shaft, tex: Texture2D) -> void:
	_shaft = shaft
	_tex = tex
	_duration = DataDB.num("twists.mushroom_squash_s")
	set_process(false)


func squash(cell: Vector2i) -> void:
	if not _left.has(cell):
		_shaft.set_mushroom_tile_visible(cell, false)
	_left[cell] = _duration
	set_process(true)
	AudioManager.play("mushroom_boing")


func _process(delta: float) -> void:
	for cell: Vector2i in _left.keys():
		var t := float(_left[cell]) - delta
		if t <= 0.0:
			_left.erase(cell)
			if _shaft.kind_at(cell.x, cell.y) == Shaft.Kind.MUSHROOM:
				_shaft.set_mushroom_tile_visible(cell, true)
		else:
			_left[cell] = t
	if _left.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _tex == null:
		return
	var size_v := _tex.get_size()
	for cell: Vector2i in _left:
		var t := 1.0 - float(_left[cell]) / _duration
		var s := sin(t * PI) * 0.3
		var bottom := Vector2((cell.x + 0.5) * _shaft.cell_px, (cell.y + 1) * _shaft.cell_px)
		draw_set_transform(bottom, 0.0, Vector2(1.0 + s, 1.0 - s))
		draw_texture(_tex, Vector2(-size_v.x * 0.5, -size_v.y))
	draw_set_transform(Vector2.ZERO)
