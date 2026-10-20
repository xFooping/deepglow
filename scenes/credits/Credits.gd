extends Control
## Shown after the final crystal shatters. Unlocks Endless Mode (built in Phase 6) and returns to
## the title screen.

const TITLE_SCENE := "res://scenes/title/Title.tscn"
const SCROLL_PX_PER_S := 18.0

var _scroller: VBoxContainer


func _ready() -> void:
	GameState.endless_unlocked = true
	SaveManager.save_game()

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_scroller = VBoxContainer.new()
	_scroller.alignment = BoxContainer.ALIGNMENT_CENTER
	_scroller.add_theme_constant_override("separation", 10)
	add_child(_scroller)
	_line("DEEPGLOW", 32, Color(1.0, 0.75, 0.4))
	_line("The last crystal is dust and light.", 10, Color(0.95, 0.9, 1.0))
	_line("Thanks for playing.", 10, Color(0.95, 0.9, 1.0))
	_line("", 10, Color.WHITE)
	_line("Days: %d    Time: %s" % [GameState.day_count, _clock(GameState.play_time_s)], 10, Color(0.85, 0.8, 0.95))
	_line("", 10, Color.WHITE)
	_line("Endless Mode unlocked", 12, Color(1.0, 0.85, 0.5))
	var view := get_viewport().get_visible_rect().size
	_scroller.position = Vector2(0, view.y)
	_scroller.size = Vector2(view.x, 0)

	var back := Button.new()
	back.text = "Back to Title"
	back.pressed.connect(_on_back)
	add_child(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)


func _process(delta: float) -> void:
	var stop := (get_viewport().get_visible_rect().size.y - _scroller.size.y) * 0.5
	_scroller.position.y = maxf(stop, _scroller.position.y - SCROLL_PX_PER_S * delta)


func _line(text: String, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_scroller.add_child(l)


func _clock(seconds: float) -> String:
	var m := floori(seconds / 60.0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [m / 60, m % 60]


func _on_back() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)
