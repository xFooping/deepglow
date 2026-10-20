class_name ShaftGenerator
extends RefCounted
## Fills shaft chunks from the day's seed. The same seed and chunk index always give the same chunk.
## Each shaft's twist reads special_density its own way:
##   mushroom_pegs / prism_pegs  share of pegs that become mushrooms / prisms
##   water_pockets               water pockets per chunk
##   kindling_blocks             share of blocks that are kindling

var _shaft: Dictionary
var _seed: int
var _columns: int
var _chunk_rows: int
var _top_empty: int
var _minable_end: int
var _bands: Array[Dictionary] = []
var _twist: String
var _special: float


func _init(shaft_data: Dictionary, day_seed: int, columns: int, chunk_rows: int, top_empty_rows: int, minable_end_row: int) -> void:
	_shaft = shaft_data
	_seed = day_seed
	_columns = columns
	_chunk_rows = chunk_rows
	_top_empty = top_empty_rows
	_minable_end = minable_end_row
	_twist = str(shaft_data.get("twist_id", "none"))
	_special = float(shaft_data.get("special_density", 0.0))
	for band: Variant in shaft_data.get("ore_bands", []):
		_bands.append(band)


func fill(chunk: ShaftChunk, above: ShaftChunk) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, chunk.index])
	var n := _chunk_rows * _columns
	var kinds := PackedByteArray()
	var ore := PackedByteArray()
	var hp := PackedInt32Array()
	var rich := PackedByteArray()
	kinds.resize(n)
	ore.resize(n)
	hp.resize(n)
	rich.resize(n)

	# 1) Base fill: each cell is a block with probability fill_density.
	var fill_density := float(_shaft["fill_density"])
	var kindling_hp := float(_shaft.get("kindling_hp_fraction", 0.5))
	for lr in _chunk_rows:
		var row := chunk.first_row + lr
		if not _is_minable_row(row):
			continue
		for col in _columns:
			if rng.randf() < fill_density:
				var i := lr * _columns + col
				var ore_i := _pick_ore(row, rng)
				if ore_i < 0:
					continue
				kinds[i] = Shaft.Kind.BLOCK
				ore[i] = ore_i
				hp[i] = int(DataDB.ores[ore_i]["hp"])
				if _twist == "kindling_blocks" and rng.randf() < _special:
					# Kindling takes a share of the HP of the ore it replaces, so it scales with depth.
					kinds[i] = Shaft.Kind.KINDLING
					hp[i] = maxi(1, roundi(hp[i] * kindling_hp))

	# 2) Open pockets: small round caves.
	for _p in _count(float(_shaft.get("pockets_per_chunk", 0.0)), rng):
		var r := rng.randf_range(float(_shaft.get("pocket_min_radius", 1.0)), float(_shaft.get("pocket_max_radius", 2.0)))
		_blob(kinds, rng.randi_range(0, _columns - 1), rng.randi_range(0, _chunk_rows - 1), r, Shaft.Kind.EMPTY, chunk.first_row)

	# 3) Chutes: narrow, slightly wandering vertical channels so embers can travel.
	for _c in _count(float(_shaft.get("chutes_per_chunk", 0.0)), rng):
		var col := rng.randi_range(1, _columns - 2)
		var start := rng.randi_range(0, _chunk_rows - 1)
		var length := rng.randi_range(int(_shaft.get("chute_min_len", 4)), int(_shaft.get("chute_max_len", 12)))
		var wide := rng.randf() < float(_shaft.get("chute_wide_chance", 0.0))
		var wander_every := maxi(1, int(_shaft.get("chute_wander_every_rows", 4)))
		for k in length:
			var lr := start + k
			if lr >= _chunk_rows:
				break
			_put(kinds, col, lr, Shaft.Kind.EMPTY)
			if wide:
				_put(kinds, col + 1, lr, Shaft.Kind.EMPTY)
			if k % wander_every == wander_every - 1:
				col = clampi(col + rng.randi_range(-1, 1), 1, _columns - 2)

	# 4) Drip Caverns: glowing water pockets, with rich veins in the blocks that border them.
	if _twist == "water_pockets":
		for _w in _count(_special, rng):
			var r := rng.randf_range(float(_shaft.get("water_min_radius", 1.5)), float(_shaft.get("water_max_radius", 3.0)))
			_blob(kinds, rng.randi_range(0, _columns - 1), rng.randi_range(0, _chunk_rows - 1), r, Shaft.Kind.WATER, chunk.first_row)
		for i in n:
			if kinds[i] == Shaft.Kind.BLOCK and _touches_water(kinds, i):
				rich[i] = 1

	# 5) Crystal pegs in empty cells, never adjacent to another peg.
	var empty_fraction := maxf(1.0 - fill_density, 0.05)
	var peg_chance := clampf(float(_shaft["peg_density"]) / empty_fraction, 0.0, 1.0)
	var special_peg := Shaft.Kind.PEG
	if _twist == "mushroom_pegs":
		special_peg = Shaft.Kind.MUSHROOM
	elif _twist == "prism_pegs":
		special_peg = Shaft.Kind.PRISM
	for lr in _chunk_rows:
		var row := chunk.first_row + lr
		if not _is_minable_row(row):
			continue
		for col in _columns:
			var i := lr * _columns + col
			if kinds[i] != Shaft.Kind.EMPTY or rng.randf() >= peg_chance:
				continue
			if _peg_nearby(kinds, above, col, lr):
				continue
			kinds[i] = special_peg if special_peg != Shaft.Kind.PEG and rng.randf() < _special else Shaft.Kind.PEG

	chunk.kinds = kinds
	chunk.ore = ore
	chunk.hp = hp
	chunk.rich = rich


func _is_minable_row(row: int) -> bool:
	return row >= _top_empty and row < _minable_end


## Integer part always, plus one more with probability equal to the fraction.
func _count(rate: float, rng: RandomNumberGenerator) -> int:
	var whole := floori(rate)
	return whole + (1 if rng.randf() < rate - whole else 0)


## Fills a round blob of cells with one kind (open air or water), inside minable rows only.
func _blob(kinds: PackedByteArray, cx: int, cy: int, r: float, kind: int, first_row: int) -> void:
	var reach := ceili(r)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if dx * dx + dy * dy <= r * r and _is_minable_row(first_row + cy + dy):
				_put(kinds, cx + dx, cy + dy, kind)


func _put(kinds: PackedByteArray, col: int, lr: int, kind: int) -> void:
	if col < 0 or col >= _columns or lr < 0 or lr >= _chunk_rows:
		return
	kinds[lr * _columns + col] = kind


func _touches_water(kinds: PackedByteArray, i: int) -> bool:
	var col := i % _columns
	@warning_ignore("integer_division")
	var lr := i / _columns
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var c := col + d.x
		var r := lr + d.y
		if c >= 0 and c < _columns and r >= 0 and r < _chunk_rows and kinds[r * _columns + c] == Shaft.Kind.WATER:
			return true
	return false


func _peg_nearby(kinds: PackedByteArray, above: ShaftChunk, col: int, lr: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c: int = col + dx
			var r: int = lr + dy
			if c < 0 or c >= _columns or r >= _chunk_rows:
				continue
			if r < 0:
				# Look into the last row of the chunk above, if it still exists.
				if above != null and _is_peg(above.kinds[(_chunk_rows - 1) * _columns + c]):
					return true
				continue
			if _is_peg(kinds[r * _columns + c]):
				return true
	return false


func _is_peg(kind: int) -> bool:
	return kind == Shaft.Kind.PEG or kind == Shaft.Kind.MUSHROOM or kind == Shaft.Kind.PRISM


## Weighted pick among the ore bands covering this row. Returns an ore index or -1.
func _pick_ore(row: int, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for b in _bands:
		if row >= float(b["from_m"]) and row < float(b["to_m"]):
			total += float(b["weight"])
	if total <= 0.0:
		return -1
	var roll := rng.randf() * total
	for b in _bands:
		if row >= float(b["from_m"]) and row < float(b["to_m"]):
			roll -= float(b["weight"])
			if roll <= 0.0:
				return int(DataDB.ore_index.get(str(b["ore_id"]), -1))
	return -1
