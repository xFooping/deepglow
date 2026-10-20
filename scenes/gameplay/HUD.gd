class_name HUD
extends CanvasLayer
## Minimal in-play HUD in the side margins: depth meter on the left, embers left and today's ore
## on the right. Never takes mouse input.

const EMBER_ICON := "res://art/ui/ember_icon.png"

var _shaft: Shaft
var _embers: EmberManager
var _depth_label: Label
var _depth_bar: ProgressBar
var _ember_row: HFlowContainer
var _ember_count: Label
var _ore_list: VBoxContainer
var _ore_labels: Dictionary = {}  ## ore id -> Label
var _shown_supply: int = -1
var _shown_depth: int = -1


func setup(shaft: Shaft, embers: EmberManager) -> void:
	_shaft = shaft
	_embers = embers
	_build()
	Events.ore_collected.connect(_on_ore_collected)


## Screen position the end-of-day pickups fly to.
func ticker_screen_pos() -> Vector2:
	if _ore_list == null:
		return Vector2.ZERO
	return _ore_list.global_position + Vector2(8, 8)


func _build() -> void:
	var view := get_viewport().get_visible_rect().size
	var margin := (view.x - _shaft.width_px) * 0.5

	var left := _column(Vector2(8, 8), Vector2(margin - 16, view.y - 16))
	left.add_child(_label("DEPTH", Color(0.85, 0.8, 0.95)))
	_depth_label = _label("0 m", Color(1.0, 0.9, 0.7))
	left.add_child(_depth_label)
	var bar_row := HBoxContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(bar_row)
	_depth_bar = ProgressBar.new()
	_depth_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_depth_bar.fill_mode = ProgressBar.FILL_TOP_TO_BOTTOM
	_depth_bar.show_percentage = false
	_depth_bar.custom_minimum_size = Vector2(8, 200)
	_depth_bar.max_value = _shaft.floor_row
	bar_row.add_child(_depth_bar)
	bar_row.add_child(_label("%d m" % _shaft.floor_row, Color(0.7, 0.65, 0.8)))

	var right := _column(Vector2(view.x - margin + 8, 8), Vector2(margin - 16, view.y - 16))
	right.add_child(_label("EMBERS", Color(0.85, 0.8, 0.95)))
	_ember_row = HFlowContainer.new()
	_ember_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_ember_row)
	_ember_count = _label("", Color(1.0, 0.9, 0.7))
	right.add_child(_ember_count)
	right.add_child(_label("TODAY", Color(0.85, 0.8, 0.95)))
	_ore_list = VBoxContainer.new()
	_ore_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_ore_list)


func _column(pos: Vector2, size_v: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = pos
	box.size = size_v
	add_child(box)
	return box


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	return l


func _process(_delta: float) -> void:
	if _embers == null:
		return
	if _embers.supply != _shown_supply:
		_shown_supply = _embers.supply
		_refresh_embers()
	if GameState.day_max_depth_m != _shown_depth:
		_shown_depth = GameState.day_max_depth_m
		_depth_label.text = "%d m" % _shown_depth
		_depth_bar.value = _shown_depth


func _refresh_embers() -> void:
	for c in _ember_row.get_children():
		c.queue_free()
	var icon := DataDB.texture(EMBER_ICON)
	var max_icons := DataDB.integer("ui.hud_ember_icon_max")
	var icons := _shown_supply if _shown_supply <= max_icons else 1
	for _i in icons:
		var t := TextureRect.new()
		t.texture = icon
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ember_row.add_child(t)
	_ember_count.text = "x %d" % _shown_supply if _shown_supply > max_icons else ""
	_ember_count.visible = _shown_supply > max_icons


func _on_ore_collected(ore_id: String, _amount: float, _source: String) -> void:
	if not _ore_labels.has(ore_id):
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = DataDB.ore_icon(ore_id)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var l := _label("", Color.WHITE)
		row.add_child(l)
		_ore_list.add_child(row)
		_ore_labels[ore_id] = l
		_sort_ore_rows()
	(_ore_labels[ore_id] as Label).text = Fmt.num(float(GameState.day_ore.get(ore_id, 0.0)))


func _sort_ore_rows() -> void:
	var ordered: Array = _ore_labels.keys()
	ordered.sort_custom(func(a: String, b: String) -> bool: return int(DataDB.ore_index[a]) < int(DataDB.ore_index[b]))
	for i in ordered.size():
		_ore_list.move_child((_ore_labels[ordered[i]] as Label).get_parent(), i)
