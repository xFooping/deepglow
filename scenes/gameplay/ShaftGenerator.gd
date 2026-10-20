class_name ShaftGenerator
extends RefCounted
## Fills shaft chunks from the day's seed. The same seed and chunk index always give the same chunk.

var _shaft: Dictionary
var _seed: int
var _columns: int
var _chunk_rows: int
var _top_empty: int
var _floor_row: int
var _bands: Array[Dictionary] = []


func _init(shaft_data: Dictionary, day_seed: int, columns: int, chunk_rows: int, top_empty_rows: int, floor_row: int) -> void:
	_shaft = shaft_data
	_seed = day_seed
	_columns = columns
	_chunk_rows = chunk_rows
	_top_empty = top_empty_rows
	_floor_row = floor_row
	for band: Variant in shaft_data.get("ore_bands", []):
		_bands.append(band)


func fill(chunk: ShaftChunk, above: ShaftChunk) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_seed, chunk.index])
	var n := _chunk_rows * _columns
	var kinds := PackedByteArray()
	var ore := PackedByteArray()
	var hp := PackedInt32Array()
	kinds.resize(n)
	ore.resize(n)
	hp.resize(n)

	# 1) Base fill: each cell is a block with probability fill_density.
	var fill_density := float(_shaft["fill_density"])
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

	# 2) Open pockets: small round caves.
	for _p in _count(float(_shaft.get("pockets_per_chunk", 0.0)), rng):
		var r := rng.randf_range(float(_shaft.get("pocket_min_radius", 1.0)), float(_shaft.get("pocket_max_radius", 2.0)))
		var cx := rng.randi_range(0, _columns - 1)
		var cy := rng.randi_range(0, _chunk_rows - 1)
		var reach := ceili(r)
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if dx * dx + dy * dy <= r * r:
					_clear(kinds, cx + dx, cy + dy)

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
			_clear(kinds, col, lr)
			if wide:
				_clear(kinds, col + 1, lr)
			if k % wander_every == wander_every - 1:
				col = clampi(col + rng.randi_range(-1, 1), 1, _columns - 2)

	# 4) Crystal pegs in empty cells, never adjacent to another peg.
	var empty_fraction := maxf(1.0 - fill_density, 0.05)
	var peg_chance := clampf(float(_shaft["peg_density"]) / empty_fraction, 0.0, 1.0)
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
			kinds[i] = Shaft.Kind.PEG

	chunk.kinds = kinds
	chunk.ore = ore
	chunk.hp = hp


func _is_minable_row(row: int) -> bool:
	return row >= _top_empty and row < _floor_row


## Integer part always, plus one more with probability equal to the fraction.
func _count(rate: float, rng: RandomNumberGenerator) -> int:
	var whole := floori(rate)
	return whole + (1 if rng.randf() < rate - whole else 0)


func _clear(kinds: PackedByteArray, col: int, lr: int) -> void:
	if col < 0 or col >= _columns or lr < 0 or lr >= _chunk_rows:
		return
	kinds[lr * _columns + col] = Shaft.Kind.EMPTY


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
				if above != null and above.kinds[(_chunk_rows - 1) * _columns + c] == Shaft.Kind.PEG:
					return true
				continue
			if kinds[r * _columns + c] == Shaft.Kind.PEG:
				return true
	return false


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
