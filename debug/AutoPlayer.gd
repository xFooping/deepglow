extends Node
## --autoplay: a simple bot for balance checks. Run headless with a fixed frame rate so it plays
## faster than real time:
##   Godot --headless --path . --fixed-fps 60 -- --autoplay
## It aims at a random downward angle, moves a speed-limited virtual cursor to vacuum ore, buys
## the cheapest affordable upgrades between days, and reports the play time to reach the goal node.

const GAMEPLAY_SCENE := "res://scenes/gameplay/Gameplay.tscn"

var sim_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _aim_target := Vector2.ZERO
var _has_aim: bool = false
var _last_supply: int = -1
var _day_end_wait: float = -1.0
var _cursor := Vector2.ZERO
var _cursor_speed: float
var _aim_radius: float
var _goal_shaft: int
var _gate_reported: bool = false
var _boss_frac: float = 0.3  ## running estimate of how much of a day's potential lands on the crystal


func _ready() -> void:
	_rng.seed = 12345
	seed(12345)
	_cursor_speed = DataDB.num("debug.autoplay_cursor_speed")
	_aim_radius = DataDB.num("debug.autoplay_aim_radius_px")
	_goal_shaft = DataDB.integer("debug.autoplay_goal_boss_shaft")
	GameState.reset_to_new_game()
	Stats.recompute()
	Events.day_ended.connect(_on_day_ended)
	Events.boss_defeated.connect(_on_boss_defeated)
	get_tree().change_scene_to_file.call_deferred(GAMEPLAY_SCENE)


func _on_boss_defeated(shaft_id: int) -> void:
	print("AUTOPLAY MILESTONE boss %d defeated on day %d at %.1f minutes" % [shaft_id, GameState.day_count, sim_time / 60.0])


## Plays the newest shaft whose crystal still stands. Goes for the crystal (elevator stop) once
## a day's potential damage is close to its HP; otherwise mines from the deepest milestone stop.
func _pick_day() -> void:
	var shaft_id := int(GameState.unlocked_shafts.back())
	for sid: Variant in GameState.unlocked_shafts:
		if not GameState.is_boss_defeated(int(sid)):
			shaft_id = int(sid)
			break
	var boss_depth := int(DataDB.shafts[shaft_id]["boss_depth_m"])
	var depths := GameState.available_start_depths(shaft_id)
	var potential := Stats.get_f("ember_count") * Stats.get_f("ember_durability") * Stats.get_f("ember_damage")
	var depth := 0
	for d in depths:
		if d != boss_depth:
			depth = maxi(depth, d)
	if depths.has(boss_depth) and potential * _boss_frac >= DataDB.num("debug.autoplay_boss_attempt_ratio") * float(GameState.boss_hp_today(shaft_id)):
		depth = boss_depth
	GameState.last_pick = {"shaft": shaft_id, "depth_m": depth}


func _physics_process(delta: float) -> void:
	sim_time += delta
	if _day_end_wait >= 0.0:
		_day_end_wait -= delta
		if _day_end_wait < 0.0:
			_between_days()
		return
	var gp := get_tree().get_first_node_in_group("gameplay")
	if gp == null or gp.day_over:
		return
	var input: PlayerInput = gp.player_input
	var keeper: LanternKeeper = gp.keeper
	var embers: EmberManager = gp.embers
	if not input.bot_active:
		input.bot_active = true
		_cursor = keeper.launch_origin() + Vector2(0, 40)
		_has_aim = false
		_last_supply = embers.supply
	if embers.supply != _last_supply:
		_last_supply = embers.supply
		_has_aim = false

	var target := _cursor
	input.bot_fire = false
	if embers.supply > 0 and keeper.cooldown_ready():
		if not _has_aim:
			_aim_target = Vector2.from_angle(deg_to_rad(_rng.randf_range(30.0, 150.0))) * _aim_radius
			_has_aim = true
		target = keeper.launch_origin() + _aim_target
		input.bot_fire = _cursor.distance_to(target) < 3.0
	else:
		var best := INF
		var pickups: PickupManager = gp.pickups
		for p in pickups.active:
			var d := _cursor.distance_squared_to(p.pos)
			if d < best:
				best = d
				target = p.pos
	_cursor = _cursor.move_toward(target, _cursor_speed * delta)
	input.bot_cursor = _cursor


func _on_day_ended(summary: Dictionary) -> void:
	var ore: Dictionary = summary.get("ore", {})
	var parts: PackedStringArray = []
	for id: Variant in ore:
		parts.append("%s=%d" % [id, int(float(ore[id]))])
	print("AUTOPLAY day=%d t=%.1fmin shaft=%d start=%dm depth=%dm boss_dmg=%d dmg=%d dur=%d embers=%d  %s" % [
		int(summary.get("day", 0)), sim_time / 60.0, int(summary.get("shaft", 0)), GameState.start_depth_m,
		int(summary.get("max_depth_m", 0)), int(summary.get("boss_damage", 0)),
		Stats.get_i("ember_damage"), Stats.get_i("ember_durability"), Stats.get_i("ember_count"), " ".join(parts)])
	if GameState.start_depth_m > 0 and bool(summary.get("reached_chamber", false)) and GameState.start_depth_m == int(DataDB.shafts[int(summary.get("shaft", 1))]["boss_depth_m"]):
		var potential := Stats.get_f("ember_count") * Stats.get_f("ember_durability") * Stats.get_f("ember_damage")
		if potential > 0.0:
			_boss_frac = lerpf(_boss_frac, float(summary.get("boss_damage", 0)) / potential, 0.5)
	_day_end_wait = 0.5


func _between_days() -> void:
	_buy_everything_affordable()
	sim_time += DataDB.num("debug.autoplay_menu_overhead_s")
	if not _gate_reported and GameState.is_upgrade_visible("gate_iron"):
		_gate_reported = true
		print("AUTOPLAY MILESTONE iron gate visible on day %d at %.1f minutes" % [GameState.day_count, sim_time / 60.0])
	if GameState.is_boss_defeated(_goal_shaft):
		print("AUTOPLAY GOAL boss %d defeated after %d days, %.1f minutes" % [_goal_shaft, GameState.day_count, sim_time / 60.0])
		_print_levels()
		get_tree().quit()
		return
	if GameState.day_count >= DataDB.integer("debug.autoplay_max_days"):
		print("AUTOPLAY gave up after %d days, %.1f minutes" % [GameState.day_count, sim_time / 60.0])
		_print_levels()
		get_tree().quit()
		return
	_pick_day()
	get_tree().change_scene_to_file(GAMEPLAY_SCENE)


## Repeatedly buys the affordable node with the lowest cost, weighting each ore by its block HP.
func _buy_everything_affordable() -> void:
	while true:
		var best_id := ""
		var best_cost := INF
		for id: String in DataDB.upgrades:
			if GameState.purchase_status(id) != GameState.PurchaseStatus.OK:
				continue
			var cost := GameState.upgrade_cost(id)
			var weighted := 0.0
			for ore_id: String in cost:
				weighted += float(cost[ore_id]) * float(DataDB.ore_by_id[ore_id]["hp"])
			if weighted < best_cost:
				best_cost = weighted
				best_id = id
		if best_id == "":
			return
		GameState.purchase(best_id)


func _print_levels() -> void:
	var parts: PackedStringArray = []
	for id: String in DataDB.upgrades:
		parts.append("%s:%d" % [id, GameState.upgrade_level(id)])
	print("AUTOPLAY levels " + " ".join(parts))
