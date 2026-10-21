extends Node
## Loads every JSON file under res://data at startup and validates it.
## Gameplay code reads tunables through num()/val() so no balance number lives in a script.

const DATA_DIR := "res://data/"
const EFFECT_OPS: Array[String] = ["add", "mult", "set"]
const SPECIAL_EFFECT_TYPES: Array[String] = ["unlock_elevator_stop"]
const ORE_FIELDS: Array[String] = ["id", "display_name", "hp", "color", "icon_path", "block_texture_path", "pickup_texture_path", "sort_order"]
const SHAFT_FIELDS: Array[String] = ["id", "display_name", "boss_depth_m", "boss_hp", "boss_chamber_rows", "boss_size_cells", "boss_texture_path", "ore_bands", "patterns", "special_density", "palette", "twist_id"]
const PATTERN_IDS: Array[String] = ["peg_field", "shelves", "timber", "funnel", "vein_mass", "cavern", "lake"]
const TWIST_IDS: Array[String] = ["none", "mushroom_pegs", "prism_pegs", "water_pockets", "kindling_blocks"]
const BAND_FIELDS: Array[String] = ["ore_id", "from_m", "to_m", "weight"]
const UPGRADE_FIELDS: Array[String] = ["id", "name", "description", "icon", "position", "prereqs", "max_level", "cost", "effects"]
const ARTIFACT_FIELDS: Array[String] = ["id", "name", "description", "flavor", "icon", "effects"]
const BALANCE_SECTIONS: Array[String] = ["grid", "physics", "aim", "combat", "boss", "twists", "generation", "combo", "abilities", "visuals", "settings", "blocks", "camera", "pickups", "fx", "ui", "save", "audio", "stats", "stat_limits", "debug"]

var balance: Dictionary = {}
var ores: Array[Dictionary] = []      ## Sorted by sort_order. An ore's position here is its "ore index".
var ore_by_id: Dictionary = {}        ## ore id -> ore dict
var ore_index: Dictionary = {}        ## ore id -> int index into ores
var shafts: Dictionary = {}           ## int shaft id -> shaft dict
var shaft_order: Array[int] = []
var upgrades: Dictionary = {}         ## upgrade id -> upgrade dict, in file order
var artifacts: Dictionary = {}        ## artifact id -> artifact dict
var stat_ids: Array[String] = []
var errors: PackedStringArray = PackedStringArray()

var _texture_cache: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	errors.clear()
	_texture_cache.clear()
	balance = _load_dict("balance.json")

	ores.clear()
	ore_by_id.clear()
	ore_index.clear()
	ores = _load_list("ores.json")
	ores.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("sort_order", 0)) < float(b.get("sort_order", 0)))
	for i in ores.size():
		var id := str(ores[i].get("id", ""))
		ore_by_id[id] = ores[i]
		ore_index[id] = i

	shafts.clear()
	shaft_order.clear()
	for s in _load_list("shafts.json"):
		var sid := int(s.get("id", 0))
		shafts[sid] = s
		shaft_order.append(sid)
	shaft_order.sort()

	upgrades = _index_by_id(_load_list("upgrades.json"), "upgrades.json")
	artifacts = _index_by_id(_load_list("artifacts.json"), "artifacts.json")

	stat_ids.clear()
	var stats_base: Variant = balance.get("stats", {})
	if stats_base is Dictionary:
		for key: Variant in stats_base:
			stat_ids.append(str(key))
	for ore in ores:
		stat_ids.append("ore_yield_" + str(ore.get("id", "")))

	_validate()
	if errors.is_empty():
		print("DataDB: loaded %d ores, %d shafts, %d upgrades, %d artifacts" % [ores.size(), shafts.size(), upgrades.size(), artifacts.size()])
	else:
		for e in errors:
			push_error("DataDB: " + e)


## Returns a value from balance.json by dotted path, e.g. val("physics.gravity").
func val(path: String) -> Variant:
	var node: Variant = balance
	for key in path.split("."):
		if node is Dictionary and (node as Dictionary).has(key):
			node = (node as Dictionary)[key]
		else:
			push_error("DataDB: balance.json is missing '%s'" % path)
			return null
	return node


func num(path: String) -> float:
	var v: Variant = val(path)
	if v is float or v is int:
		return float(v)
	push_error("DataDB: balance value '%s' is not a number" % path)
	return 0.0


func integer(path: String) -> int:
	return roundi(num(path))


func texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	else:
		push_warning("DataDB: texture not found: %s" % path)
	_texture_cache[path] = tex
	return tex


func ore_color(ore_id: String) -> Color:
	return Color.html(str(ore_by_id.get(ore_id, {}).get("color", "#ff00ff")))


func ore_name(ore_id: String) -> String:
	return str(ore_by_id.get(ore_id, {}).get("display_name", ore_id))


func ore_icon(ore_id: String) -> Texture2D:
	return texture(str(ore_by_id.get(ore_id, {}).get("icon_path", "")))


func shaft_has_ore(shaft_id: int, ore_id: String) -> bool:
	var shaft: Dictionary = shafts.get(shaft_id, {})
	for band: Variant in shaft.get("ore_bands", []):
		if str((band as Dictionary).get("ore_id", "")) == ore_id:
			return true
	return false


# --- loading ---------------------------------------------------------------

func _parse(file: String) -> Variant:
	var path := DATA_DIR + file
	if not FileAccess.file_exists(path):
		errors.append("missing file %s" % path)
		return null
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		errors.append("%s line %d: %s" % [file, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_dict(file: String) -> Dictionary:
	var parsed: Variant = _parse(file)
	if parsed is Dictionary:
		return parsed
	if parsed != null:
		errors.append("%s: expected a JSON object" % file)
	return {}


func _load_list(file: String) -> Array[Dictionary]:
	var parsed: Variant = _parse(file)
	var out: Array[Dictionary] = []
	if parsed is Array:
		for item: Variant in parsed:
			if item is Dictionary:
				out.append(item)
			else:
				errors.append("%s: every entry must be an object" % file)
	elif parsed != null:
		errors.append("%s: expected a JSON array" % file)
	return out


func _index_by_id(list: Array[Dictionary], file: String) -> Dictionary:
	var out: Dictionary = {}
	for item in list:
		var id := str(item.get("id", ""))
		if out.has(id):
			errors.append("%s: duplicate id '%s'" % [file, id])
		out[id] = item
	return out


# --- validation ------------------------------------------------------------

func _validate() -> void:
	for section in BALANCE_SECTIONS:
		if not balance.has(section):
			errors.append("balance.json: missing section '%s'" % section)

	for ore in ores:
		_require(ore, ORE_FIELDS, "ores.json '%s'" % ore.get("id", "?"))

	for sid in shaft_order:
		var shaft: Dictionary = shafts[sid]
		var ctx := "shafts.json %d" % sid
		_require(shaft, SHAFT_FIELDS, ctx)
		for pat: Variant in shaft.get("patterns", {}):
			if not PATTERN_IDS.has(str(pat)):
				errors.append("%s: unknown pattern '%s'" % [ctx, pat])
		if not TWIST_IDS.has(str(shaft.get("twist_id", ""))):
			errors.append("%s: unknown twist_id '%s'" % [ctx, shaft.get("twist_id", "")])
		for band: Variant in shaft.get("ore_bands", []):
			if not band is Dictionary:
				errors.append("%s: ore band must be an object" % ctx)
				continue
			var b: Dictionary = band
			_require(b, BAND_FIELDS, ctx + " ore band")
			if not ore_by_id.has(str(b.get("ore_id", ""))):
				errors.append("%s: unknown ore id '%s'" % [ctx, b.get("ore_id", "")])
			if float(b.get("from_m", 0)) >= float(b.get("to_m", 0)):
				errors.append("%s: ore band for '%s' has from_m >= to_m" % [ctx, b.get("ore_id", "")])

	for id: String in upgrades:
		var up: Dictionary = upgrades[id]
		var ctx := "upgrades.json '%s'" % id
		_require(up, UPGRADE_FIELDS, ctx)
		for pre: Variant in up.get("prereqs", []):
			if not upgrades.has(str(pre)):
				errors.append("%s: unknown prereq '%s'" % [ctx, pre])
		var cost: Variant = up.get("cost", {})
		if cost is Dictionary:
			for ore_id: Variant in cost:
				if not ore_by_id.has(str(ore_id)):
					errors.append("%s: unknown ore id '%s' in cost" % [ctx, ore_id])
		else:
			errors.append("%s: cost must be an object" % ctx)
		_validate_effects(up.get("effects", []), ctx)

	for id: String in artifacts:
		var art: Dictionary = artifacts[id]
		var ctx := "artifacts.json '%s'" % id
		_require(art, ARTIFACT_FIELDS, ctx)
		_validate_effects(art.get("effects", []), ctx)

	var limits: Variant = balance.get("stat_limits", {})
	if limits is Dictionary:
		for stat: Variant in limits:
			if not stat_ids.has(str(stat)):
				errors.append("balance.json stat_limits: unknown stat id '%s'" % stat)


func _validate_effects(effects: Variant, ctx: String) -> void:
	if not effects is Array:
		errors.append("%s: effects must be an array" % ctx)
		return
	for eff: Variant in effects:
		if not eff is Dictionary:
			errors.append("%s: each effect must be an object" % ctx)
			continue
		var e: Dictionary = eff
		if e.has("type"):
			if not SPECIAL_EFFECT_TYPES.has(str(e["type"])):
				errors.append("%s: unknown effect type '%s'" % [ctx, e["type"]])
			continue
		if not stat_ids.has(str(e.get("stat", ""))):
			errors.append("%s: unknown stat id '%s'" % [ctx, e.get("stat", "")])
		if not EFFECT_OPS.has(str(e.get("op", ""))):
			errors.append("%s: unknown op '%s'" % [ctx, e.get("op", "")])
		if not e.has("value"):
			errors.append("%s: effect on '%s' has no value" % [ctx, e.get("stat", "")])


func _require(d: Dictionary, fields: Array[String], ctx: String) -> void:
	for f in fields:
		if not d.has(f):
			errors.append("%s: missing field '%s'" % [ctx, f])
