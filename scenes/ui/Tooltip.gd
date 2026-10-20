class_name Tooltip
extends PanelContainer
## Hover card for a skill node: name, description, level, current -> next value, and cost per ore.

const LOCK_ICON := "res://art/ui/lock.png"
const UNKNOWN_ORE_ICON := "res://art/ui/unknown_ore.png"

var _box: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_box)


func show_upgrade(id: String) -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if id == "":
		visible = false
		return
	var up: Dictionary = DataDB.upgrades[id]
	var level := GameState.upgrade_level(id)
	var max_level := int(up.get("max_level", 1))
	var status := GameState.purchase_status(id)

	_add(str(up["name"]), Color(1.0, 0.85, 0.55))
	var desc := _add(str(up["description"]), Color(0.9, 0.88, 0.95))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(150, 0)
	if max_level > 1 or level == 0:
		_add("Level %d/%d" % [level, max_level], Color(0.75, 0.72, 0.85))

	if status != GameState.PurchaseStatus.MAXED:
		var now := Stats.resolve(GameState.upgrade_levels, GameState.owned_artifacts)
		var next := Stats.preview(id)
		for eff: Variant in up.get("effects", []):
			var e: Dictionary = eff
			if e.has("type"):
				if str(e["type"]) == "unlock_elevator_stop":
					_add("Unlocks a %d m start" % int(e.get("depth_m", 0)), Color(0.8, 0.95, 0.8))
				continue
			var stat := str(e["stat"])
			_add("%s: %s -> %s" % [Stats.display_name(stat), Stats.format_value(stat, now[stat]), Stats.format_value(stat, next[stat])], Color(0.8, 0.95, 0.8))

		var cost := GameState.upgrade_cost(id)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(row)
		for ore_id: String in cost:
			var locked := not GameState.is_ore_obtainable(ore_id)
			var icon := TextureRect.new()
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.texture = DataDB.texture(UNKNOWN_ORE_ICON) if locked else DataDB.ore_icon(ore_id)
			row.add_child(icon)
			var enough := GameState.ore_amount(ore_id) + 0.0001 >= float(cost[ore_id])
			var l := Label.new()
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.text = Fmt.num(float(cost[ore_id])) + "  "
			l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.85) if enough else Color(1.0, 0.4, 0.35))
			row.add_child(l)
		if status == GameState.PurchaseStatus.LOCKED:
			var lock_row := HBoxContainer.new()
			lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var lock := TextureRect.new()
			lock.texture = DataDB.texture(LOCK_ICON)
			lock.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lock_row.add_child(lock)
			var l := Label.new()
			l.text = "Needs ore from a deeper shaft"
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.add_theme_color_override("font_color", Color(0.75, 0.7, 0.8))
			lock_row.add_child(l)
			_box.add_child(lock_row)
	else:
		_add("Maxed", Color(1.0, 0.8, 0.35))
	visible = true
	reset_size()


## Places the card next to the cursor, kept on screen.
func follow(screen_pos: Vector2) -> void:
	var view := get_viewport().get_visible_rect().size
	var p := screen_pos + Vector2(12, 12)
	if p.x + size.x > view.x:
		p.x = screen_pos.x - size.x - 8
	if p.y + size.y > view.y:
		p.y = view.y - size.y
	position = p.max(Vector2.ZERO)


func _add(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	_box.add_child(l)
	return l
