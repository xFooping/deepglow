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
var _camera: CameraRig
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss_label: Label
var _shown_boss_hp: int = -1
var _combo_label: Label
var _shown_combo: float = 0.0
var _banner: Label
var _fly_count: int = 0


func setup(shaft: Shaft, embers: EmberManager, camera: CameraRig) -> void:
	_shaft = shaft
	_embers = embers
	_camera = camera
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
	_depth_bar.custom_minimum_size = Vector2(8, 140)
	_depth_bar.max_value = _shaft.boss_row
	bar_row.add_child(_depth_bar)
	bar_row.add_child(_label("%d m" % _shaft.boss_row, Color(0.7, 0.65, 0.8)))

	_boss_box = VBoxContainer.new()
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	left.add_child(_boss_box)
	_boss_box.add_child(_label("CRYSTAL", Color(0.85, 0.8, 0.95)))
	_boss_bar = ProgressBar.new()
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(margin - 24, 8)
	_boss_bar.add_theme_stylebox_override("fill", _flat(Color(1.0, 0.7, 0.35)))
	_boss_bar.add_theme_stylebox_override("background", _flat(Color(0.15, 0.1, 0.15)))
	_boss_box.add_child(_boss_bar)
	_boss_label = _label("", Color(1.0, 0.9, 0.7))
	_boss_box.add_child(_boss_label)

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

	# Combo meter, centered at the top of the shaft.
	_combo_label = _label("", Color(1.0, 0.85, 0.45))
	_combo_label.add_theme_font_size_override("font_size", 24)
	_combo_label.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.05))
	_combo_label.add_theme_constant_override("outline_size", 4)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.position = Vector2(margin, 40)
	_combo_label.size = Vector2(_shaft.width_px, 40)
	_combo_label.pivot_offset = Vector2(_shaft.width_px * 0.5, 20)
	_combo_label.visible = false
	add_child(_combo_label)

	_banner = _label("", Color(1.0, 0.9, 0.7))
	_banner.add_theme_font_size_override("font_size", 32)
	_banner.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.1))
	_banner.add_theme_constant_override("outline_size", 4)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position = Vector2(0, view.y * 0.38)
	_banner.size = Vector2(view.x, 40)
	_banner.modulate.a = 0.0
	add_child(_banner)


func _column(pos: Vector2, size_v: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = pos
	panel.custom_minimum_size = Vector2(size_v.x, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.1, 0.72)
	style.border_color = Color(0.78, 0.56, 0.34, 0.6)
	style.set_border_width_all(1)
	style.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
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
	_update_boss()
	_update_combo()


## The best live combo among active embers, shown big and warming in color as it climbs.
func _update_combo() -> void:
	var best := 1.0
	for e in _embers.active:
		best = maxf(best, _embers.combo_mult(e))
	if best < 1.25:
		_combo_label.visible = false
		_shown_combo = 0.0
		return
	_combo_label.visible = true
	if best > _shown_combo + 0.01:
		_combo_label.scale = Vector2(1.35, 1.35)
	_shown_combo = best
	_combo_label.text = "COMBO  x%.1f" % best
	var heat := clampf((best - 1.0) / 5.0, 0.0, 1.0)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6).lerp(Color(1.0, 0.45, 0.25), heat))
	_combo_label.scale = _combo_label.scale.lerp(Vector2.ONE, 0.2)


func show_day_banner(day: int, shaft_name: String, start_depth: int) -> void:
	if _banner == null:
		return
	_banner.text = "Day %d  -  %s%s" % [day, shaft_name, ("  (%d m)" % start_depth) if start_depth > 0 else ""]
	var hold := DataDB.num("juice.day_banner_s")
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
	AudioManager.play("day_start")


## A little ore icon flying from the cursor into the ore ticker.
func _fly_ore(ore_id: String) -> void:
	if _fly_count >= 24:
		return
	var icon := TextureRect.new()
	icon.texture = DataDB.ore_icon(ore_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = get_viewport().get_mouse_position()
	add_child(icon)
	_fly_count += 1
	var target := ticker_screen_pos()
	if _ore_labels.has(ore_id):
		target = (_ore_labels[ore_id] as Label).global_position
	var tw := create_tween()
	tw.tween_property(icon, "position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		icon.queue_free()
		_fly_count -= 1
		_bump(ore_id))


func _bump(ore_id: String) -> void:
	if not _ore_labels.has(ore_id):
		return
	var l: Label = _ore_labels[ore_id]
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(1.4, 1.4)
	create_tween().tween_property(l, "scale", Vector2.ONE, 0.18)


## The boss bar only shows while the chamber is on screen.
func _update_boss() -> void:
	var boss := _shaft.boss
	_boss_box.visible = boss != null and _camera.bottom() > _shaft.boss_y()
	if boss == null or boss.hp == _shown_boss_hp:
		return
	_shown_boss_hp = boss.hp
	_boss_bar.max_value = boss.max_hp
	_boss_bar.value = boss.hp
	_boss_label.text = "%s / %s" % [Fmt.num(boss.hp), Fmt.num(boss.max_hp)]


func _flat(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	return s


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


func _on_ore_collected(ore_id: String, _amount: float, source: String) -> void:
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
	if source == "magnet":
		_fly_ore(ore_id)
	elif source == "day_end":
		_bump(ore_id)


func _sort_ore_rows() -> void:
	var ordered: Array = _ore_labels.keys()
	ordered.sort_custom(func(a: String, b: String) -> bool: return int(DataDB.ore_index[a]) < int(DataDB.ore_index[b]))
	for i in ordered.size():
		_ore_list.move_child((_ore_labels[ordered[i]] as Label).get_parent(), i)
