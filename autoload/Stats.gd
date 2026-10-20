extends Node
## Resolves final gameplay values from skill tree levels and owned artifacts:
##   final = (base + sum(add)) * product(mult), unless an effect uses "set".
## Gameplay reads stats from here, never from upgrades or artifacts directly.

signal stats_changed

const PERCENT_STATS: Array[String] = ["crit_chance", "offscreen_bank_rate", "chain_spark_chance", "prism_split_chance", "artifact_chance"]
const STAT_NAMES: Dictionary = {
	"ember_count": "Embers per day",
	"ember_damage": "Ember damage",
	"ember_durability": "Ember durability",
	"fire_cooldown": "Fire cooldown",
	"launch_speed": "Launch speed",
	"crit_chance": "Crit chance",
	"magnet_radius": "Magnet radius",
	"offscreen_bank_rate": "Off-screen bank rate",
	"auto_collect": "Auto-collect",
	"artifact_chance": "Artifact chance",
	"chain_spark_chance": "Chain spark chance",
	"prism_split_chance": "Prism split chance",
	"water_drain_mult": "Water drain",
	"kindling_burst_mult": "Kindling burst",
	"mushroom_restitution": "Mushroom bounce",
}

var debug_overrides: Dictionary = {}  ## Cheat panel values, applied last.

var _values: Dictionary = {}


func _ready() -> void:
	Events.upgrade_purchased.connect(_on_upgrade_purchased)
	Events.artifact_found.connect(_on_artifact_found)
	recompute()


func recompute() -> void:
	_values = resolve(GameState.upgrade_levels, GameState.owned_artifacts)
	stats_changed.emit()


func get_value(stat: String) -> Variant:
	if not _values.has(stat):
		push_error("Stats: unknown stat '%s'" % stat)
		return 0.0
	return _values[stat]


func get_f(stat: String) -> float:
	return float(get_value(stat))


func get_i(stat: String) -> int:
	return roundi(float(get_value(stat)))


func get_b(stat: String) -> bool:
	return bool(get_value(stat))


## Stat values if the given upgrade had one more level.
func preview(upgrade_id: String) -> Dictionary:
	var levels := GameState.upgrade_levels.duplicate()
	levels[upgrade_id] = int(levels.get(upgrade_id, 0)) + 1
	return resolve(levels, GameState.owned_artifacts)


func resolve(levels: Dictionary, owned: Array) -> Dictionary:
	var stats_base: Dictionary = DataDB.val("stats")
	var yield_base := DataDB.num("ore_yield_base")
	var adds: Dictionary = {}
	var mults: Dictionary = {}
	var sets: Dictionary = {}
	for up_id: Variant in levels:
		var level := int(levels[up_id])
		if level > 0 and DataDB.upgrades.has(str(up_id)):
			_accumulate(DataDB.upgrades[str(up_id)].get("effects", []), level, adds, mults, sets)
	for art_id: Variant in owned:
		if DataDB.artifacts.has(str(art_id)):
			_accumulate(DataDB.artifacts[str(art_id)].get("effects", []), 1, adds, mults, sets)

	var limits: Dictionary = DataDB.val("stat_limits")
	var out: Dictionary = {}
	for id in DataDB.stat_ids:
		var base: Variant = stats_base.get(id, yield_base)
		var v: Variant
		if sets.has(id):
			v = sets[id]
		elif base is bool:
			v = base
		else:
			var f := (float(base) + float(adds.get(id, 0.0))) * float(mults.get(id, 1.0))
			var lim: Dictionary = limits.get(id, {})
			if lim.has("min"):
				f = maxf(f, float(lim["min"]))
			if lim.has("max"):
				f = minf(f, float(lim["max"]))
			v = f
		out[id] = v
	for id: Variant in debug_overrides:
		out[id] = debug_overrides[id]
	return out


func display_name(stat: String) -> String:
	if STAT_NAMES.has(stat):
		return STAT_NAMES[stat]
	if stat.begins_with("ore_yield_"):
		return "%s per block" % DataDB.ore_name(stat.trim_prefix("ore_yield_"))
	return stat.capitalize()


func format_value(stat: String, v: Variant) -> String:
	if v is bool:
		return "On" if v else "Off"
	var f := float(v)
	if PERCENT_STATS.has(stat):
		return "%s%%" % _trim(f * 100.0)
	if stat == "fire_cooldown":
		return "%.2fs" % f
	return _trim(f)


func _trim(f: float) -> String:
	if is_equal_approx(f, roundf(f)):
		return str(roundi(f))
	return "%.1f" % f


func _accumulate(effects: Array, level: int, adds: Dictionary, mults: Dictionary, sets: Dictionary) -> void:
	for eff: Variant in effects:
		var e: Dictionary = eff
		if e.has("type"):
			continue  # special effects (elevator stops) are handled by GameState
		var stat := str(e["stat"])
		match str(e["op"]):
			"add":
				adds[stat] = float(adds.get(stat, 0.0)) + float(e["value"]) * level
			"mult":
				mults[stat] = float(mults.get(stat, 1.0)) * pow(float(e["value"]), level)
			"set":
				sets[stat] = e["value"]


func _on_upgrade_purchased(_id: String, _level: int) -> void:
	recompute()


func _on_artifact_found(_id: String) -> void:
	recompute()
