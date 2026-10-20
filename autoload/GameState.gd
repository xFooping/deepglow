extends Node
## Currencies, progression flags and the current day. Everything above "Runtime only" is saved.

enum PurchaseStatus { OK, MAXED, HIDDEN, LOCKED, UNAFFORDABLE }

var ores: Dictionary = {}                 ## ore id -> float (fractional off-screen banking accumulates)
var upgrade_levels: Dictionary = {}       ## upgrade id -> int
var owned_artifacts: Array = []
var unlocked_shafts: Array = []
var defeated_bosses: Array = []
var max_depth_by_shaft: Dictionary = {}   ## "shaft id" -> deepest meter reached
var boss_reach_by_shaft: Dictionary = {}  ## "shaft id" -> times the boss chamber was reached
var elevator_stops: Dictionary = {}       ## "shaft id" -> Array of unlocked start depths (m)
var last_pick: Dictionary = {}            ## {"shaft": int, "depth_m": int}
var day_count: int = 0
var play_time_s: float = 0.0
var endless_best_depth: int = 0
var settings: Dictionary = {}
var achievement_stats: Dictionary = {}

# Runtime only
var current_shaft: int = 1
var current_seed: int = 0
var start_depth_m: int = 0
var day_ore: Dictionary = {}
var day_max_depth_m: int = 0


func _ready() -> void:
	reset_to_new_game()


func _process(delta: float) -> void:
	play_time_s += delta


func reset_to_new_game() -> void:
	ores = {}
	for ore in DataDB.ores:
		ores[str(ore["id"])] = 0.0
	upgrade_levels = {}
	for id: String in DataDB.upgrades:
		var up: Dictionary = DataDB.upgrades[id]
		if (up.get("prereqs", []) as Array).is_empty() and (up.get("cost", {}) as Dictionary).is_empty():
			upgrade_levels[id] = 1  # free starting node (the root)
	owned_artifacts = []
	unlocked_shafts = [DataDB.shaft_order[0]] if not DataDB.shaft_order.is_empty() else []
	defeated_bosses = []
	max_depth_by_shaft = {}
	boss_reach_by_shaft = {}
	elevator_stops = {}
	last_pick = {"shaft": unlocked_shafts[0] if not unlocked_shafts.is_empty() else 1, "depth_m": 0}
	day_count = 0
	play_time_s = 0.0
	endless_best_depth = 0
	achievement_stats = {}
	day_ore = {}
	day_max_depth_m = 0
	Events.ores_changed.emit()


func start_day() -> void:
	day_count += 1
	current_shaft = int(last_pick.get("shaft", 1))
	start_depth_m = 0  # Phase 2: comes from the pre-day picker
	current_seed = randi()
	day_ore = {}
	day_max_depth_m = start_depth_m
	Events.day_started.emit(day_count, current_seed)


# --- ore ---------------------------------------------------------------------

func add_ore(ore_id: String, amount: float, source: String = "") -> void:
	if amount <= 0.0:
		return
	ores[ore_id] = float(ores.get(ore_id, 0.0)) + amount
	day_ore[ore_id] = float(day_ore.get(ore_id, 0.0)) + amount
	Events.ore_collected.emit(ore_id, amount, source)
	Events.ores_changed.emit()


func ore_amount(ore_id: String) -> float:
	return float(ores.get(ore_id, 0.0))


## An ore is obtainable once any unlocked shaft has it in its ore bands.
func is_ore_obtainable(ore_id: String) -> bool:
	for sid: Variant in unlocked_shafts:
		if DataDB.shaft_has_ore(int(sid), ore_id):
			return true
	return false


func record_depth(depth_m: int) -> void:
	if depth_m <= day_max_depth_m:
		return
	day_max_depth_m = depth_m
	var key := str(current_shaft)
	if depth_m > int(max_depth_by_shaft.get(key, 0)):
		max_depth_by_shaft[key] = depth_m


# --- upgrades ----------------------------------------------------------------

func upgrade_level(id: String) -> int:
	return int(upgrade_levels.get(id, 0))


func is_upgrade_visible(id: String) -> bool:
	if upgrade_level(id) > 0:
		return true
	var prereqs: Array = DataDB.upgrades.get(id, {}).get("prereqs", [])
	if prereqs.is_empty():
		return true
	for pre: Variant in prereqs:
		if upgrade_level(str(pre)) > 0:
			return true
	return false


## Cost of the next level: round(base * cost_scaling^(level - 1)) per ore.
func upgrade_cost(id: String) -> Dictionary:
	var up: Dictionary = DataDB.upgrades.get(id, {})
	var next_level := upgrade_level(id) + 1
	var scaling := float(up.get("cost_scaling", 1.0))
	var out: Dictionary = {}
	var base: Dictionary = up.get("cost", {})
	for ore_id: Variant in base:
		out[str(ore_id)] = roundi(float(base[ore_id]) * pow(scaling, next_level - 1))
	return out


func can_afford(cost: Dictionary) -> bool:
	for ore_id: Variant in cost:
		if ore_amount(str(ore_id)) + 0.0001 < float(cost[ore_id]):
			return false
	return true


func purchase_status(id: String) -> PurchaseStatus:
	var up: Dictionary = DataDB.upgrades.get(id, {})
	if upgrade_level(id) >= int(up.get("max_level", 1)):
		return PurchaseStatus.MAXED
	if not is_upgrade_visible(id):
		return PurchaseStatus.HIDDEN
	var cost := upgrade_cost(id)
	for ore_id: String in cost:
		if not is_ore_obtainable(ore_id):
			return PurchaseStatus.LOCKED
	if not can_afford(cost):
		return PurchaseStatus.UNAFFORDABLE
	return PurchaseStatus.OK


func purchase(id: String) -> bool:
	if purchase_status(id) != PurchaseStatus.OK:
		return false
	var cost := upgrade_cost(id)
	for ore_id: String in cost:
		ores[ore_id] = ore_amount(ore_id) - float(cost[ore_id])
	var level := upgrade_level(id) + 1
	upgrade_levels[id] = level
	_apply_special_effects(DataDB.upgrades[id])
	Events.ores_changed.emit()
	Events.upgrade_purchased.emit(id, level)
	return true


func _apply_special_effects(up: Dictionary) -> void:
	for eff: Variant in up.get("effects", []):
		var e: Dictionary = eff
		if str(e.get("type", "")) == "unlock_elevator_stop":
			var key := str(int(e.get("shaft", 1)))
			var stops: Array = elevator_stops.get(key, [])
			var depth := int(e.get("depth_m", 0))
			if not stops.has(depth):
				stops.append(depth)
				stops.sort()
			elevator_stops[key] = stops


# --- save data ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"ores": ores,
		"upgrade_levels": upgrade_levels,
		"owned_artifacts": owned_artifacts,
		"unlocked_shafts": unlocked_shafts,
		"defeated_bosses": defeated_bosses,
		"max_depth_by_shaft": max_depth_by_shaft,
		"boss_reach_by_shaft": boss_reach_by_shaft,
		"elevator_stops": elevator_stops,
		"last_pick": last_pick,
		"day_count": day_count,
		"play_time_s": play_time_s,
		"endless_best_depth": endless_best_depth,
		"settings": settings,
		"achievement_stats": achievement_stats,
	}


func from_dict(d: Dictionary) -> void:
	reset_to_new_game()
	var saved_ores: Dictionary = d.get("ores", {})
	for ore_id: Variant in saved_ores:
		ores[str(ore_id)] = float(saved_ores[ore_id])
	var saved_levels: Dictionary = d.get("upgrade_levels", {})
	for id: Variant in saved_levels:
		if DataDB.upgrades.has(str(id)):
			upgrade_levels[str(id)] = int(saved_levels[id])
	owned_artifacts = d.get("owned_artifacts", [])
	unlocked_shafts = _ints(d.get("unlocked_shafts", unlocked_shafts))
	defeated_bosses = _ints(d.get("defeated_bosses", []))
	max_depth_by_shaft = d.get("max_depth_by_shaft", {})
	boss_reach_by_shaft = d.get("boss_reach_by_shaft", {})
	elevator_stops = d.get("elevator_stops", {})
	last_pick = d.get("last_pick", last_pick)
	day_count = int(d.get("day_count", 0))
	play_time_s = float(d.get("play_time_s", 0.0))
	endless_best_depth = int(d.get("endless_best_depth", 0))
	settings = d.get("settings", {})
	achievement_stats = d.get("achievement_stats", {})
	Events.ores_changed.emit()


func _ints(values: Array) -> Array:
	var out: Array = []
	for v: Variant in values:
		out.append(int(v))
	return out
