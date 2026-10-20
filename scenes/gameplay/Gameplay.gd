extends Node2D
## One day of mining: builds today's shaft, wires the systems together and runs the end-of-day flow.

const DAY_END_PANEL := preload("res://scenes/ui/DayEndPanel.tscn")

var day_over: bool = false

var _generate_ahead: float
var _free_behind: float

@onready var ambient: CanvasModulate = $Ambient
@onready var backdrop: ShaftBackdrop = $Backdrop
@onready var shaft: Shaft = $Shaft
@onready var pickups: PickupManager = $PickupManager
@onready var fx: FxManager = $FxManager
@onready var embers: EmberManager = $EmberManager
@onready var keeper: LanternKeeper = $LanternKeeper
@onready var cursor_view: CursorView = $CursorView
@onready var player_input: PlayerInput = $PlayerInput
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: HUD = $HUD


func _ready() -> void:
	add_to_group("gameplay")
	_generate_ahead = DataDB.num("grid.generate_ahead_px")
	_free_behind = DataDB.num("camera.leash_px") + DataDB.num("grid.free_behind_px")

	GameState.start_day()
	shaft.setup(GameState.current_shaft, GameState.current_seed)
	camera_rig.setup(shaft, GameState.start_depth_m * shaft.cell_px)
	shaft.ensure_generated_to(camera_rig.bottom() + _generate_ahead)
	backdrop.setup(shaft, camera_rig)
	embers.setup(shaft, camera_rig, GameState.current_seed)
	hud.setup(shaft, embers)
	pickups.setup(shaft, camera_rig, player_input, hud)
	keeper.setup(shaft, camera_rig, embers, player_input)
	cursor_view.setup(player_input)
	ambient.color = Color.html(str(shaft.data["palette"].get("ambient", "#ffffff")))
	pickups.all_collected.connect(_on_pickups_banked)
	print("Day %d: shaft %d, seed %d" % [GameState.day_count, GameState.current_shaft, GameState.current_seed])


func _physics_process(delta: float) -> void:
	if day_over:
		return
	if not embers.active.is_empty():
		camera_rig.follow(embers.deepest_y, delta)
		GameState.record_depth(floori(embers.deepest_y / shaft.cell_px))
	shaft.ensure_generated_to(camera_rig.bottom() + _generate_ahead)
	shaft.free_above(camera_rig.top - _free_behind)
	if embers.supply <= 0 and embers.active.is_empty():
		_begin_day_end()


func _begin_day_end() -> void:
	day_over = true
	keeper.enabled = false
	pickups.collect_all_to_hud()


func _on_pickups_banked() -> void:
	for n: Node in [embers, pickups, keeper, fx, backdrop]:
		n.process_mode = Node.PROCESS_MODE_DISABLED
	cursor_view.visible = false
	var summary := {
		"day": GameState.day_count,
		"shaft": GameState.current_shaft,
		"ore": GameState.day_ore.duplicate(),
		"max_depth_m": GameState.day_max_depth_m,
	}
	var panel: DayEndPanel = DAY_END_PANEL.instantiate()
	add_child(panel)
	panel.show_summary(summary)
	Events.day_ended.emit(summary)


# --- debug hooks (F3 overlay / F4 cheat panel / bench / autoplay) -----------

func debug_info() -> Dictionary:
	return {
		"embers": embers.active.size(),
		"supply": embers.supply,
		"pickups": pickups.active.size(),
		"seed": GameState.current_seed,
		"depth_m": GameState.day_max_depth_m,
		"camera_y": camera_rig.top,
		"chunks": shaft.chunk_count(),
	}


func debug_end_day() -> void:
	embers.set_supply(0)
	embers.burn_out_all()


func debug_spawn_embers(count: int) -> void:
	var origin := keeper.launch_origin()
	var speed := Stats.get_f("launch_speed")
	for _i in count:
		var dir := Vector2.from_angle(randf_range(deg_to_rad(20.0), deg_to_rad(160.0)))
		embers.spawn_free(origin, dir * speed)


func debug_spawn_pickups(count: int) -> void:
	var view := Rect2(0, camera_rig.top + 40, shaft.width_px, camera_rig.view_size.y - 60)
	for _i in count:
		var at := Vector2(randf_range(view.position.x, view.end.x), randf_range(view.position.y, view.end.y))
		pickups.spawn(randi() % DataDB.ores.size(), at, 1)
