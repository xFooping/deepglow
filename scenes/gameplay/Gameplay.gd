extends Node2D
## One day of mining: builds today's shaft, wires the systems together and runs the end-of-day flow.

const DAY_END_PANEL := preload("res://scenes/ui/DayEndPanel.tscn")
const BOSS_CRYSTAL := preload("res://scenes/gameplay/BossCrystal.tscn")

var day_over: bool = false

var _generate_ahead: float
var _free_behind: float
var _reached_chamber: bool = false
var _celebrating: bool = false
var _next_depth_bonus: int = 0
var _stats := {"blocks": 0, "lodes": 0, "jars": 0, "moths": 0, "best_combo": 1.0, "depth_bonuses": 0}
var _juice := Juice.new()
var _moth := Glowmoth.new()
var _dust := DustMotes.new()

@onready var ambient: CanvasModulate = $Ambient
@onready var backdrop: ShaftBackdrop = $Backdrop
@onready var shaft: Shaft = $Shaft
@onready var pickups: PickupManager = $PickupManager
@onready var fx: FxManager = $FxManager
@onready var embers: EmberManager = $EmberManager
@onready var keeper: LanternKeeper = $LanternKeeper
@onready var lights: Lights = $Lights
@onready var popups: Popups = $Popups
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
	if not GameState.is_boss_defeated(shaft.shaft_id):
		shaft.spawn_boss(BOSS_CRYSTAL.instantiate())
	# Elevator: the keeper starts at the chosen depth (the camera clamps so the chamber stays framed).
	camera_rig.setup(shaft, GameState.start_depth_m * shaft.cell_px - DataDB.num("camera.keeper_offset_px"))
	shaft.ensure_generated_to(camera_rig.bottom() + _generate_ahead)
	backdrop.setup(shaft, camera_rig)
	embers.setup(shaft, camera_rig, GameState.current_seed)
	hud.setup(shaft, embers, camera_rig)
	pickups.setup(shaft, camera_rig, player_input, hud)
	keeper.setup(shaft, camera_rig, embers, player_input)
	cursor_view.setup(player_input)
	popups.setup(player_input)
	lights.setup(embers, keeper)
	add_child(_juice)
	_juice.setup(camera_rig)
	add_child(_moth)
	_moth.setup(shaft, camera_rig, embers, pickups)
	add_child(_dust)
	move_child(_dust, backdrop.get_index() + 1)
	_dust.setup(camera_rig, shaft)
	var every := DataDB.integer("juice.depth_bonus_every_m")
	_next_depth_bonus = (floori(float(GameState.start_depth_m) / every) + 1) * every
	# A dim cave: lights (keeper lantern, embers) bring the warmth back.
	ambient.color = Color.html(str(shaft.data["palette"].get("ambient", "#ffffff"))).darkened(DataDB.num("visuals.ambient_darken"))
	pickups.all_collected.connect(_on_pickups_banked)
	Events.boss_defeated.connect(_on_boss_defeated)
	Events.jar_broken.connect(_on_jar_broken)
	Events.moth_caught.connect(func(_p: Vector2) -> void: _stats["moths"] += 1)
	Events.lode_broken.connect(func(_p: Vector2) -> void: _stats["lodes"] += 1)
	Events.block_broken.connect(func(_c: Vector2i, _o: String, _p: Vector2, _m: float) -> void: _stats["blocks"] += 1)
	Events.combo_reached.connect(func(_p: Vector2, m: float) -> void: _stats["best_combo"] = maxf(float(_stats["best_combo"]), m))
	hud.show_day_banner(GameState.day_count, str(shaft.data["display_name"]), GameState.start_depth_m)
	print("Day %d: shaft %d, seed %d" % [GameState.day_count, GameState.current_shaft, GameState.current_seed])


func _physics_process(delta: float) -> void:
	if day_over:
		return
	if not embers.active.is_empty():
		camera_rig.follow(embers.deepest_y, delta)
		GameState.record_depth(mini(floori(embers.deepest_y / shaft.cell_px), shaft.boss_row))
		if not _reached_chamber and embers.deepest_y >= shaft.boss_y():
			_on_chamber_reached()
		_check_depth_bonus()
	shaft.ensure_generated_to(camera_rig.bottom() + _generate_ahead)
	shaft.free_above(camera_rig.top - _free_behind)
	if embers.supply <= 0 and embers.active.is_empty():
		_begin_day_end()


func _begin_day_end() -> void:
	day_over = true
	keeper.enabled = false
	pickups.collect_all_to_hud()


## Every 25 m reached in a day gives an extra ember, so pushing deeper keeps the day going.
func _check_depth_bonus() -> void:
	if GameState.day_max_depth_m < _next_depth_bonus or _next_depth_bonus > shaft.boss_row:
		return
	var n := DataDB.integer("juice.depth_bonus_embers")
	embers.set_supply(embers.supply + n)
	_stats["depth_bonuses"] += 1
	Events.depth_bonus.emit(Vector2(shaft.width_px * 0.5, _next_depth_bonus * shaft.cell_px), _next_depth_bonus, n)
	AudioManager.play("depth_bonus")
	_next_depth_bonus += DataDB.integer("juice.depth_bonus_every_m")


func _on_jar_broken(_world_pos: Vector2, n: int) -> void:
	_stats["jars"] += 1
	if not day_over:
		embers.set_supply(embers.supply + n)


## Counted once per day. The third time without a win unlocks an elevator stop at the chamber.
func _on_chamber_reached() -> void:
	_reached_chamber = true
	Events.boss_chamber_reached.emit(shaft.shaft_id)
	if GameState.record_boss_reach(shaft.shaft_id):
		AudioManager.play("elevator_unlock")
		Events.toast_requested.emit("Elevator to the Crystal unlocked!")


## After a short celebration the day ends normally; embers still in play burn out.
func _on_boss_defeated(_shaft_id: int) -> void:
	if _celebrating:
		return
	_celebrating = true
	keeper.enabled = false
	Events.toast_requested.emit("%s's crystal shattered!" % str(shaft.data["display_name"]))
	await get_tree().create_timer(DataDB.num("boss.celebration_s"), false, true).timeout
	if not is_inside_tree() or day_over:
		return
	embers.set_supply(0)
	embers.burn_out_all()


func _on_pickups_banked() -> void:
	for n: Node in [embers, pickups, keeper, fx, backdrop]:
		n.process_mode = Node.PROCESS_MODE_DISABLED
	cursor_view.visible = false
	var summary := {
		"day": GameState.day_count,
		"shaft": GameState.current_shaft,
		"ore": GameState.day_ore.duplicate(),
		"max_depth_m": GameState.day_max_depth_m,
		"reached_chamber": _reached_chamber,
		"boss_damage": GameState.day_boss_damage,
		"boss_defeated": GameState.day_boss_defeated,
		"stats": _stats,
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
		"shaft": shaft.shaft_id,
		"boss_hp": shaft.boss.hp if shaft.boss else 0,
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
