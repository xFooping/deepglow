class_name CursorView
extends Node2D
## In-world cursor with a faint ring showing the magnet radius. Hides the OS cursor during play.

const CURSOR_TEXTURE := "res://art/ui/cursor.png"

var _input: PlayerInput
var _tex: Texture2D


func setup(input: PlayerInput) -> void:
	_input = input
	_tex = DataDB.texture(CURSOR_TEXTURE)


func _process(_delta: float) -> void:
	var show_os_cursor := not visible or DebugOverlay.cheats_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_os_cursor else Input.MOUSE_MODE_HIDDEN
	queue_redraw()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _draw() -> void:
	if _input == null:
		return
	var p := _input.cursor_world().round()
	if Settings.magnet_ring_enabled():
		draw_arc(p, Stats.get_f("magnet_radius"), 0.0, TAU, 40, Color(1.0, 0.9, 0.7, 0.25), 1.0)
	if _tex:
		draw_texture(_tex, p)
	else:
		draw_rect(Rect2(p - Vector2.ONE, Vector2(3, 3)), Color.WHITE)
