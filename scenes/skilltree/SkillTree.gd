extends Control
## Full-screen skill tree: currency bar along the top, Upgrades / Artifacts tabs, Next Day button.

var _canvas: TreeCanvas
var _tooltip: Tooltip
var _currency_row: HBoxContainer
var _artifacts_view: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.07, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_canvas = TreeCanvas.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_canvas.hovered_changed.connect(_on_hovered_changed)
	_canvas.purchase_requested.connect(_on_purchase_requested)

	_artifacts_view = _build_artifacts_view()
	_artifacts_view.visible = false
	add_child(_artifacts_view)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(bar)
	var bar_row := HBoxContainer.new()
	bar.add_child(bar_row)
	_currency_row = HBoxContainer.new()
	_currency_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(_currency_row)
	var tabs := ButtonGroup.new()
	for i in 2:
		var tab := Button.new()
		tab.text = ["Upgrades", "Artifacts"][i]
		tab.toggle_mode = true
		tab.button_group = tabs
		tab.button_pressed = i == 0
		tab.pressed.connect(_on_tab_changed.bind(i))
		bar_row.add_child(tab)

	var next_day := Button.new()
	next_day.text = "Next Day"
	next_day.pressed.connect(_on_next_day)
	add_child(next_day)
	next_day.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 8)

	_tooltip = Tooltip.new()
	add_child(_tooltip)

	Events.ores_changed.connect(_refresh_currency)
	_refresh_currency()


func _build_artifacts_view() -> Control:
	var view := CenterContainer.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	var l := Label.new()
	l.text = "No artifacts found yet.\n(Artifacts arrive in Phase 4.)"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	view.add_child(l)
	return view


func _process(_delta: float) -> void:
	if _tooltip.visible:
		_tooltip.follow(get_viewport().get_mouse_position())


func _refresh_currency() -> void:
	for c in _currency_row.get_children():
		_currency_row.remove_child(c)
		c.queue_free()
	for o in DataDB.ores:
		var id := str(o["id"])
		if not GameState.is_ore_obtainable(id) and GameState.ore_amount(id) <= 0.0:
			continue
		var icon := TextureRect.new()
		icon.texture = DataDB.ore_icon(id)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		_currency_row.add_child(icon)
		var l := Label.new()
		l.text = Fmt.num(GameState.ore_amount(id)) + "   "
		_currency_row.add_child(l)


func _on_hovered_changed(id: String) -> void:
	_tooltip.show_upgrade(id)
	if id != "":
		AudioManager.play("ui_hover")


func _on_purchase_requested(id: String) -> void:
	var before := _visible_ids()
	if not GameState.purchase(id):
		AudioManager.play("node_cant_afford")
		return
	AudioManager.play("node_purchase")
	var revealed: Array[String] = []
	for v in _visible_ids():
		if not before.has(v):
			revealed.append(v)
	_canvas.play_purchase(id, revealed)
	_tooltip.show_upgrade(id)


func _visible_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in DataDB.upgrades:
		if GameState.is_upgrade_visible(id):
			out.append(id)
	return out


func _on_tab_changed(tab: int) -> void:
	_canvas.visible = tab == 0
	_artifacts_view.visible = tab == 1
	_tooltip.show_upgrade("")


func _on_next_day() -> void:
	AudioManager.play("ui_click")
	PreDayPicker.begin_next_day(self)
