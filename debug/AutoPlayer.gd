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
var _goal: String


func _ready() -> void:
	_rng.seed = 12345
	seed(12345)
	_cursor_speed = DataDB.num("debug.autoplay_cursor_speed")
	_aim_radius = DataDB.num("debug.autoplay_aim_radius_px")
	_goal = str(DataDB.val("debug.autoplay_goal_upgrade"))
	GameState.reset_to_new_game()
	Stats.recompute()
	Events.day_ended.connect(_on_day_ended)
	get_tree().change_scene_to_file.call_deferred(GAMEPLAY_SCENE)


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
	print("AUTOPLAY day=%d t=%.1fmin depth=%dm dmg=%d dur=%d embers=%d  %s" % [
		int(summary.get("day", 0)), sim_time / 60.0, int(summary.get("max_depth_m", 0)),
		Stats.get_i("ember_damage"), Stats.get_i("ember_durability"), Stats.get_i("ember_count"), " ".join(parts)])
	_day_end_wait = 0.5


func _between_days() -> void:
	_buy_everything_affordable()
	sim_time += DataDB.num("debug.autoplay_menu_overhead_s")
	if GameState.is_upgrade_visible(_goal):
		print("AUTOPLAY GOAL '%s' visible after %d days, %.1f minutes" % [_goal, GameState.day_count, sim_time / 60.0])
		_print_levels()
		get_tree().quit()
		return
	if GameState.day_count >= DataDB.integer("debug.autoplay_max_days"):
		print("AUTOPLAY gave up after %d days, %.1f minutes" % [GameState.day_count, sim_time / 60.0])
		_print_levels()
		get_tree().quit()
		return
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
