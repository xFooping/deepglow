class_name PreDayPicker
extends CanvasLayer
## Small popup to pick a shaft and start depth before a day. Only shown when there's a real choice
## (more than one shaft, or more than one start depth). Defaults to the last pick.

const SCENE := "res://scenes/ui/PreDayPicker.tscn"
const GAMEPLAY_SCENE := "res://scenes/gameplay/Gameplay.tscn"

var _shaft: int = 1
var _depth: int = 0
var _shaft_row: HBoxContainer
var _depth_row: HFlowContainer


## Starts the next day, asking first if there's a choice to make. Used by Mine Again and Next Day.
static func begin_next_day(host: Node) -> void:
	if not GameState.needs_day_picker():
		host.get_tree().change_scene_to_file(GAMEPLAY_SCENE)
		return
	var picker: PreDayPicker = (load(SCENE) as PackedScene).instantiate()
	host.add_child(picker)


func _ready() -> void:
	layer = 20
	_shaft = int(GameState.last_pick.get("shaft", GameState.unlocked_shafts[0]))
	if not GameState.unlocked_shafts.has(_shaft):
		_shaft = int(GameState.unlocked_shafts[0])
	_depth = int(GameState.last_pick.get("depth_m", 0))

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.08, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(240, 0)
	panel.add_child(box)

	box.add_child(_title("Where to today?"))
	box.add_child(_caption("Shaft"))
	_shaft_row = HBoxContainer.new()
	box.add_child(_shaft_row)
	box.add_child(_caption("Start depth"))
	_depth_row = HFlowContainer.new()
	box.add_child(_depth_row)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(actions)
	var go := Button.new()
	go.text = "Descend"
	go.pressed.connect(_on_go)
	actions.add_child(go)
	var cancel := Button.new()
	cancel.text = "Back"
	cancel.pressed.connect(queue_free)
	actions.add_child(cancel)

	_rebuild()


func _rebuild() -> void:
	for c in _shaft_row.get_children():
		c.queue_free()
	for c in _depth_row.get_children():
		c.queue_free()
	var shaft_group := ButtonGroup.new()
	for sid: Variant in GameState.unlocked_shafts:
		var id := int(sid)
		var b := Button.new()
		b.text = str(DataDB.shafts[id]["display_name"]) + (" *" if GameState.is_boss_defeated(id) else "")
		b.toggle_mode = true
		b.button_group = shaft_group
		b.button_pressed = id == _shaft
		b.pressed.connect(_on_shaft_chosen.bind(id))
		_shaft_row.add_child(b)

	var depths := GameState.available_start_depths(_shaft)
	if not depths.has(_depth):
		_depth = 0
	var boss_depth := int(DataDB.shafts[_shaft]["boss_depth_m"])
	var depth_group := ButtonGroup.new()
	for d in depths:
		var b := Button.new()
		b.text = "Top" if d == 0 else ("Crystal" if d == boss_depth else "%d m" % d)
		b.toggle_mode = true
		b.button_group = depth_group
		b.button_pressed = d == _depth
		b.pressed.connect(_on_depth_chosen.bind(d))
		_depth_row.add_child(b)


func _on_shaft_chosen(id: int) -> void:
	_shaft = id
	_rebuild()


func _on_depth_chosen(d: int) -> void:
	_depth = d


func _on_go() -> void:
	AudioManager.play("ui_click")
	GameState.last_pick = {"shaft": _shaft, "depth_m": _depth}
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


func _title(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	return l


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color(0.75, 0.72, 0.85))
	return l
