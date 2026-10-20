extends CanvasLayer
## Dev-build tools: F3 toggles the stats overlay, F4 the cheat panel.
## Command-line user args (after "--"): --bench runs the 300 ember / 2,000 pickup benchmark,
## --autoplay runs the headless balance bot. Everything here is disabled in release builds.

const AutoPlayerScript := preload("res://debug/AutoPlayer.gd")
const BenchScript := preload("res://debug/Bench.gd")
const TITLE_SCENE := "res://scenes/title/Title.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay/Gameplay.tscn"

var cheats_open: bool = false

var _label: Label
var _panel: PanelContainer
var _ore_pick: OptionButton
var _ore_amount: SpinBox
var _count_override: SpinBox
var _damage_override: SpinBox


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.is_debug_build():
		set_process(false)
		set_process_unhandled_input(false)
		return
	_build_overlay()
	_build_cheats()
	var args := OS.get_cmdline_user_args()
	if args.has("--autoplay"):
		add_child(AutoPlayerScript.new())
	elif args.has("--bench"):
		add_child(BenchScript.new())
	for arg in args:
		if arg.begins_with("--give-ore="):
			for o in DataDB.ores:
				GameState.add_ore(str(o["id"]), float(arg.trim_prefix("--give-ore=")), "cheat")
		if arg.begins_with("--shaft="):
			var sid := int(arg.trim_prefix("--shaft="))
			if not GameState.unlocked_shafts.has(sid):
				GameState.unlocked_shafts.append(sid)
			GameState.last_pick = {"shaft": sid, "depth_m": 0}
		if arg == "--reach-boss":
			GameState.forced_start_depth_m = int(DataDB.shafts[int(GameState.last_pick.get("shaft", 1))]["boss_depth_m"])
		if arg.begins_with("--shots="):
			_take_screenshots(arg.trim_prefix("--shots=").split(","))


## --shots=2,5,9 saves a screenshot of the window at those seconds to user://shots/, then quits.
func _take_screenshots(times: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	var elapsed := 0.0
	for t in times:
		await get_tree().create_timer(float(t) - elapsed, true, false, true).timeout
		elapsed = float(t)
		await RenderingServer.frame_post_draw
		var path := "user://shots/shot_%s.png" % t
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()


func gameplay() -> Node:
	return get_tree().get_first_node_in_group("gameplay")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_F3:
				_label.visible = not _label.visible
			KEY_F4:
				cheats_open = not cheats_open
				_panel.visible = cheats_open


func _process(_delta: float) -> void:
	if not _label.visible:
		return
	var lines: PackedStringArray = ["FPS %d" % Engine.get_frames_per_second()]
	var gp := gameplay()
	if gp:
		var info: Dictionary = gp.debug_info()
		lines.append("embers %d (supply %d)" % [info["embers"], info["supply"]])
		lines.append("pickups %d" % info["pickups"])
		lines.append("seed %d" % info["seed"])
		lines.append("depth %d m" % info["depth_m"])
		lines.append("camera y %.0f" % info["camera_y"])
		lines.append("chunks %d" % info["chunks"])
		lines.append("shaft %d, crystal hp %d" % [info["shaft"], info["boss_hp"]])
	_label.text = "\n".join(lines)


func _build_overlay() -> void:
	_label = Label.new()
	_label.position = Vector2(4, 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 2)
	_label.visible = false
	add_child(_label)


func _build_cheats() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(140, 20)
	_panel.visible = false
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Cheats (F4)"
	box.add_child(title)

	var ore_row := HBoxContainer.new()
	box.add_child(ore_row)
	_ore_pick = OptionButton.new()
	for o in DataDB.ores:
		_ore_pick.add_item(str(o["display_name"]))
	ore_row.add_child(_ore_pick)
	_ore_amount = _spin(1, 1000000, 100)
	ore_row.add_child(_ore_amount)
	ore_row.add_child(_button("Add ore", _on_add_ore))

	var stat_row := HBoxContainer.new()
	box.add_child(stat_row)
	stat_row.add_child(_small_label("Embers"))
	_count_override = _spin(0, 1000, 0)
	stat_row.add_child(_count_override)
	stat_row.add_child(_small_label("Dmg"))
	_damage_override = _spin(0, 1000000, 0)
	stat_row.add_child(_damage_override)
	stat_row.add_child(_button("Set (0 = off)", _on_set_overrides))

	var row2 := HBoxContainer.new()
	box.add_child(row2)
	row2.add_child(_button("Unlock next shaft", _on_unlock_shaft))
	row2.add_child(_button("End day", _on_end_day))
	var row3 := HBoxContainer.new()
	box.add_child(row3)
	row3.add_child(_button("+300 embers", _on_spawn_embers))
	row3.add_child(_button("+2000 pickups", _on_spawn_pickups))
	var row4 := HBoxContainer.new()
	box.add_child(row4)
	row4.add_child(_button("Reset save", _on_reset_save))
	row4.add_child(_button("Reach the boss", _on_reach_boss))


func _spin(lo: float, hi: float, value: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	return s


func _small_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _on_add_ore() -> void:
	var ore_id := str(DataDB.ores[_ore_pick.selected]["id"])
	GameState.add_ore(ore_id, _ore_amount.value, "cheat")


func _on_set_overrides() -> void:
	Stats.debug_overrides.clear()
	if _count_override.value > 0:
		Stats.debug_overrides["ember_count"] = _count_override.value
	if _damage_override.value > 0:
		Stats.debug_overrides["ember_damage"] = _damage_override.value
	Stats.recompute()
	var gp := gameplay()
	if gp and _count_override.value > 0:
		gp.embers.set_supply(int(_count_override.value))


func _on_unlock_shaft() -> void:
	for sid in DataDB.shaft_order:
		if not GameState.unlocked_shafts.has(sid):
			GameState.unlocked_shafts.append(sid)
			Events.ores_changed.emit()
			print("Cheat: unlocked shaft %d" % sid)
			return
	print("Cheat: no more shafts in shafts.json to unlock")


func _on_end_day() -> void:
	var gp := gameplay()
	if gp:
		gp.debug_end_day()


## Restarts today in the current shaft with the keeper at the boss chamber.
func _on_reach_boss() -> void:
	var shaft_id := int(GameState.last_pick.get("shaft", 1))
	var gp := gameplay()
	if gp:
		shaft_id = int(gp.shaft.shaft_id)
	GameState.last_pick["shaft"] = shaft_id
	GameState.forced_start_depth_m = int(DataDB.shafts[shaft_id]["boss_depth_m"])
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _on_spawn_embers() -> void:
	var gp := gameplay()
	if gp:
		gp.debug_spawn_embers(DataDB.integer("debug.bench_embers"))


func _on_spawn_pickups() -> void:
	var gp := gameplay()
	if gp:
		gp.debug_spawn_pickups(DataDB.integer("debug.bench_pickups"))


func _on_reset_save() -> void:
	SaveManager.delete_save()
	GameState.reset_to_new_game()
	Stats.debug_overrides.clear()
	Stats.recompute()
	cheats_open = false
	_panel.visible = false
	get_tree().change_scene_to_file(TITLE_SCENE)
