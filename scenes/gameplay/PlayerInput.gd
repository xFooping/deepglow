class_name PlayerInput
extends Node2D
## Where the cursor is in the world and whether fire is held. The autoplay bot overrides both.

var bot_active: bool = false
var bot_cursor := Vector2.ZERO
var bot_fire: bool = false


func cursor_world() -> Vector2:
	return bot_cursor if bot_active else get_global_mouse_position()


func fire_held() -> bool:
	if bot_active:
		return bot_fire
	if DebugOverlay.cheats_open or get_viewport().gui_get_hovered_control() != null:
		return false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
