class_name DayEndPanel
extends CanvasLayer
## Slides into the middle of the frozen gameplay view with the day's summary.

const SKILL_TREE_SCENE := "res://scenes/skilltree/SkillTree.tscn"
const CREDITS_SCENE := "res://scenes/credits/Credits.tscn"

var _dim: ColorRect
var _slider: Control
var _panel: PanelContainer
var _again: Button
var _countdown: float = 0.0
var _tallies: Array[Dictionary] = []  ## {label, prefix, target, shown}
var _tally_t: float = 0.0
var _tick_every: float = 0.0


func show_summary(summary: Dictionary) -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.03, 0.08, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_slider = Control.new()
	_slider.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slider)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slider.add_child(center)

	var panel := PanelContainer.new()
	_panel = panel
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(200, 0)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Day %d done" % int(summary.get("day", 0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	box.add_child(title)

	var ore: Dictionary = summary.get("ore", {})
	if ore.is_empty():
		box.add_child(_text("No ore today."))
	else:
		box.add_child(_text("Ore collected"))
		for o in DataDB.ores:
			var id := str(o["id"])
			if not ore.has(id):
				continue
			var row := HBoxContainer.new()
			var icon := TextureRect.new()
			icon.texture = DataDB.ore_icon(id)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			row.add_child(icon)
			var l := _text("%s  0" % DataDB.ore_name(id))
			row.add_child(l)
			box.add_child(row)
			_tallies.append({"label": l, "prefix": DataDB.ore_name(id) + "  ", "target": float(ore[id])})
	box.add_child(_text("Deepest: %d m" % int(summary.get("max_depth_m", 0))))
	var stats: Dictionary = summary.get("stats", {})
	var highlights: PackedStringArray = []
	if float(stats.get("best_combo", 1.0)) > 1.0:
		highlights.append("Best combo x%.1f" % float(stats["best_combo"]))
	for key: String in ["lodes", "jars", "moths"]:
		if int(stats.get(key, 0)) > 0:
			highlights.append("%s %d" % [{"lodes": "Lodes", "jars": "Jars", "moths": "Moths"}[key], int(stats[key])])
	if not highlights.is_empty():
		var hl := _text("  ".join(highlights))
		hl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		box.add_child(hl)
	if bool(summary.get("boss_defeated", false)):
		var won := _text("Crystal shattered! A deeper shaft is open.")
		won.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		box.add_child(won)
	elif bool(summary.get("reached_chamber", false)):
		box.add_child(_text("Damage to the crystal: %s" % Fmt.num(float(summary.get("boss_damage", 0)))))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	if bool(summary.get("boss_defeated", false)) and GameState.is_final_shaft(int(summary.get("shaft", 0))):
		# The final crystal: the only way on is the credits.
		var credits := Button.new()
		credits.text = "Roll Credits"
		credits.pressed.connect(_on_credits)
		buttons.add_child(credits)
	else:
		_add_day_buttons(buttons)

	var slide_s := DataDB.num("ui.panel_slide_s")
	var view_h := get_viewport().get_visible_rect().size.y
	_slider.position.y = view_h
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_slider, "position:y", 0.0, slide_s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "color:a", DataDB.num("ui.panel_dim_alpha"), slide_s)
	AudioManager.play("panel_slide")


## If nothing in the tree is affordable there's nothing to decide, so the next day starts on its
## own after a short countdown (cancelled by hovering the panel). If something is affordable,
## the Skill Tree button is highlighted instead.
func _add_day_buttons(buttons: HBoxContainer) -> void:
	_again = Button.new()
	_again.text = "Mine Again"
	_again.pressed.connect(_on_mine_again)
	buttons.add_child(_again)
	var tree_button := Button.new()
	tree_button.text = "Skill Tree"
	tree_button.pressed.connect(_on_skill_tree)
	buttons.add_child(tree_button)
	var affordable := _affordable_count()
	if affordable > 0:
		tree_button.text = "Skill Tree (%d ready)" % affordable
		tree_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		tree_button.grab_focus.call_deferred()
	elif not GameState.needs_day_picker():
		_countdown = DataDB.num("ui.auto_continue_s")


## Numbers count up after the panel lands, with a soft tick.
func _run_tally(delta: float) -> void:
	if _tallies.is_empty():
		return
	_tally_t += delta
	var t := clampf((_tally_t - 0.35) / 0.8, 0.0, 1.0)
	t = 1.0 - pow(1.0 - t, 3.0)
	for entry in _tallies:
		(entry["label"] as Label).text = str(entry["prefix"]) + Fmt.num(float(entry["target"]) * t)
	_tick_every -= delta
	if t > 0.0 and t < 1.0 and _tick_every <= 0.0:
		_tick_every = 0.06
		AudioManager.play("tally_tick")
	if t >= 1.0:
		_tallies.clear()


func _affordable_count() -> int:
	var n := 0
	for id: String in DataDB.upgrades:
		if GameState.purchase_status(id) == GameState.PurchaseStatus.OK:
			n += 1
	return n


func _process(delta: float) -> void:
	_run_tally(delta)
	if _countdown <= 0.0 or _again == null:
		return
	if _panel and _panel.get_global_rect().has_point(_panel.get_global_mouse_position()):
		_countdown = 0.0
		_again.text = "Mine Again"
		return
	_countdown -= delta
	_again.text = "Mine Again (%d)" % ceili(_countdown)
	if _countdown <= 0.0:
		_on_mine_again()


func _on_credits() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file(CREDITS_SCENE)


func _text(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _on_mine_again() -> void:
	AudioManager.play("ui_click")
	PreDayPicker.begin_next_day(self)


func _on_skill_tree() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file(SKILL_TREE_SCENE)
