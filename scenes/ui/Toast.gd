extends CanvasLayer
## Small message that slides in at the top of the screen (Events.toast_requested). Autoloaded as
## "Toasts" so a toast survives a scene change. Messages queue up and show one at a time.

var _queue: PackedStringArray = []
var _showing: bool = false
var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
	_panel.add_child(_label)
	Events.toast_requested.connect(_on_toast_requested)


func _on_toast_requested(text: String) -> void:
	_queue.append(text)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		_panel.visible = false
		return
	_showing = true
	_label.text = _queue[0]
	_queue.remove_at(0)
	_panel.visible = true
	_panel.reset_size()
	var view := get_viewport().get_visible_rect().size
	var x := (view.x - _panel.size.x) * 0.5
	_panel.position = Vector2(x, -_panel.size.y)
	var tw := create_tween()
	tw.tween_property(_panel, "position:y", 8.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(DataDB.num("ui.toast_s"))
	tw.tween_property(_panel, "position:y", -_panel.size.y - 4.0, 0.25).set_ease(Tween.EASE_IN)
	tw.tween_callback(_show_next)
