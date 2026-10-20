class_name DayEndPanel
extends CanvasLayer
## Slides into the middle of the frozen gameplay view with the day's summary.

const SKILL_TREE_SCENE := "res://scenes/skilltree/SkillTree.tscn"

var _dim: ColorRect
var _slider: Control


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
			row.add_child(_text("%s  %s" % [DataDB.ore_name(id), Fmt.num(float(ore[id]))]))
			box.add_child(row)
	box.add_child(_text("Deepest: %d m" % int(summary.get("max_depth_m", 0))))
	if bool(summary.get("boss_defeated", false)):
		var won := _text("Crystal shattered! A deeper shaft is open.")
		won.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		box.add_child(won)
	elif bool(summary.get("reached_chamber", false)):
		box.add_child(_text("Damage to the crystal: %s" % Fmt.num(float(summary.get("boss_damage", 0)))))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var again := Button.new()
	again.text = "Mine Again"
	again.pressed.connect(_on_mine_again)
	buttons.add_child(again)
	var tree_button := Button.new()
	tree_button.text = "Skill Tree"
	tree_button.pressed.connect(_on_skill_tree)
	buttons.add_child(tree_button)

	var slide_s := DataDB.num("ui.panel_slide_s")
	var view_h := get_viewport().get_visible_rect().size.y
	_slider.position.y = view_h
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_slider, "position:y", 0.0, slide_s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "color:a", DataDB.num("ui.panel_dim_alpha"), slide_s)
	AudioManager.play("panel_slide")


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
