class_name ShaftFlash
extends Node2D
## One-frame white flash over blocks that were hit but not broken.

var cell_px: int = 16

var _cells: Array[Vector2i] = []
var _drawn: bool = false


func add(cell: Vector2i) -> void:
	_cells.append(cell)
	queue_redraw()


func _process(_delta: float) -> void:
	if _drawn:
		_cells.clear()
		_drawn = false
		queue_redraw()


func _draw() -> void:
	var s := Vector2(cell_px, cell_px)
	for c in _cells:
		draw_rect(Rect2(Vector2(c) * cell_px, s), Color.WHITE)
	_drawn = not _cells.is_empty()
