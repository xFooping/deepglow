extends Node
## Single autosave slot in user://save.json. Writes a temp file and renames it so a crash can't
## leave a half-written save.

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const SAVE_VERSION := 1

## False for bot/benchmark runs so they never touch the player's save.
var enabled: bool = true

var _debounce: Timer


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	enabled = not (args.has("--autoplay") or args.has("--bench"))
	get_tree().set_auto_accept_quit(false)
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = DataDB.num("save.purchase_debounce_s")
	_debounce.timeout.connect(save_game)
	add_child(_debounce)
	Events.upgrade_purchased.connect(_on_upgrade_purchased)
	Events.day_ended.connect(_on_day_ended)
	if enabled and has_save():
		load_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if GameState.day_count > 0:
			save_game()
		get_tree().quit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	if not enabled:
		return
	var data := GameState.to_dict()
	data["save_version"] = SAVE_VERSION
	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: can't write %s (%s)" % [TMP_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var dir := DirAccess.open("user://")
	var err := dir.rename(TMP_PATH, SAVE_PATH)
	if err != OK:
		# Some platforms refuse to rename over an existing file.
		dir.remove(SAVE_PATH)
		err = dir.rename(TMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("SaveManager: can't move the save into place (%s)" % error_string(err))


func load_game() -> bool:
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("SaveManager: %s is unreadable, starting fresh" % SAVE_PATH)
		return false
	var data := _migrate(parsed)
	GameState.from_dict(data)
	Stats.recompute()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 1))
	while version < SAVE_VERSION:
		# match version: add a step here for each save_version bump.
		version += 1
	data["save_version"] = version
	return data


func _on_upgrade_purchased(_id: String, _level: int) -> void:
	_debounce.start()


func _on_day_ended(_summary: Dictionary) -> void:
	save_game()
