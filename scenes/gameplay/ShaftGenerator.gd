class_name ShaftGenerator
extends RefCounted
## Builds shaft chunks from the day's seed. The same seed and chunk index always give the same chunk.
##
## A chunk is stacked from hand-shaped *segments* (peg fields, block shelves, funnels, ore masses,
## caverns, lakes, timber beams), picked by each shaft's "patterns" weights. That keeps the board
## readable, so a shot can be planned, and gives every shaft its own look. Ore is laid down in
## veins (each block takes the ore of its nearest vein seed), and a few glowing lode blocks are
## worth aiming for.

const LODE := 2       ## value in ShaftChunk.rich for a lode block
const RICH_VEIN := 1  ## value in ShaftChunk.rich for a rich vein (next to water)

var _shaft: Dictionary
var _seed: int
var _columns: int
var _chunk_rows: int
var _top_empty: int
var _minable_end: int
var _bands: Array[Dictionary] = []
var _twist: String
var _special: float
var _patterns: Dictionary
var _gen: Dictionary  ## balance.json "generation"


func _init(shaft_data: Dictionary, day_seed: int, columns: int, chunk_rows: int, top_empty_rows: int, minable_end_row: int) -> void:
	_shaft = shaft_data
	_seed = day_seed
	_columns = columns
	_chunk_rows = chunk_rows
	_top_empty = top_empty_rows
	_minable_end = minable_end_row
	_twist = str(shaft_data.get("twist_id", "none"))
	_special = float(shaft_data.get("special_density", 0.0))
	_patterns = shaft_data.get("patterns", {"peg_field": 1})
	_gen = DataDB.val("generation")
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

	# 1) Shape: stack pattern segments down the chunk.
	var lr := 0
	while lr < _chunk_rows:
		var h := rng.randi_range(int(_gen["segment_min_rows"]), int(_gen["segment_max_rows"]))
		var end := mini(lr + h, _chunk_rows)
		_apply_pattern(_pick_pattern(rng), kinds, above, lr, end, rng)
		lr = end

	# 2) Rows outside the mined range stay open (top rows, the boss chamber). The last stretch
	#    above the crystal is an open peg field, so embers rain into the chamber instead of
	#    spending themselves on rock.
	var ante_start := _minable_end - int(_gen["antechamber_rows"])
	for r in _chunk_rows:
		var row := chunk.first_row + r
		if not _is_minable_row(row) or row >= ante_start:
			for c in _columns:
				kinds[r * _columns + c] = Shaft.Kind.EMPTY
	var ante_r0 := clampi(ante_start - chunk.first_row, 0, _chunk_rows)
	var ante_r1 := clampi(_minable_end - chunk.first_row, 0, _chunk_rows)
	if ante_r1 > ante_r0:
		_peg_field(kinds, above, ante_r0, ante_r1, rng)
		for i in range(ante_r0 * _columns, ante_r1 * _columns):
			if kinds[i] == Shaft.Kind.BLOCK:
				kinds[i] = Shaft.Kind.EMPTY

	# 3) Ore veins: every block takes the ore of its nearest vein seed (seeds use the depth bands).
	var seeds: Array[Vector3i] = []  ## x = col, y = local row, z = ore index
	for _v in int(_gen["vein_seeds_per_chunk"]):
		var vr := rng.randi_range(0, _chunk_rows - 1)
		var ore_i := _pick_ore(chunk.first_row + vr, rng)
		if ore_i >= 0:
			seeds.append(Vector3i(rng.randi_range(0, _columns - 1), vr, ore_i))
	var kindling_hp := float(_shaft.get("kindling_hp_fraction", 0.5))
	var lode_chance := Stats.get_f("lode_chance")
	var lode_hp := float(_gen["lode_hp_mult"])
	for i in n:
		var k := kinds[i]
		if k != Shaft.Kind.BLOCK and k != Shaft.Kind.KINDLING:
			continue
		var col := i % _columns
		@warning_ignore("integer_division")
		var r := i / _columns
		var ore_i := _nearest_seed_ore(seeds, col, r)
		if ore_i < 0:
			ore_i = _pick_ore(chunk.first_row + r, rng)
		if ore_i < 0:
			kinds[i] = Shaft.Kind.EMPTY
			continue
		ore[i] = ore_i
		var base_hp := int(DataDB.ores[ore_i]["hp"])
		if k == Shaft.Kind.BLOCK and _twist == "kindling_blocks" and rng.randf() < _special:
			kinds[i] = Shaft.Kind.KINDLING
			k = Shaft.Kind.KINDLING
		if k == Shaft.Kind.KINDLING:
			hp[i] = maxi(1, roundi(base_hp * kindling_hp))
		elif rng.randf() < lode_chance:
			rich[i] = LODE
			hp[i] = roundi(base_hp * lode_hp)
		else:
			hp[i] = base_hp

	# 4) Twist pegs: a share of pegs become mushrooms or prisms.
	if _twist == "mushroom_pegs" or _twist == "prism_pegs":
		var special_peg := Shaft.Kind.MUSHROOM if _twist == "mushroom_pegs" else Shaft.Kind.PRISM
		for i in n:
			if kinds[i] == Shaft.Kind.PEG and rng.randf() < _special:
				kinds[i] = special_peg

	# 5) Rich veins next to water (Drip Caverns).
	for i in n:
		if kinds[i] == Shaft.Kind.BLOCK and rich[i] == 0 and _touches(kinds, i, Shaft.Kind.WATER):
			rich[i] = RICH_VEIN

	chunk.kinds = kinds
	chunk.ore = ore
	chunk.hp = hp
	chunk.rich = rich


# --- patterns ----------------------------------------------------------------

func _pick_pattern(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for p: Variant in _patterns:
		total += float(_patterns[p])
	var roll := rng.randf() * total
	for p: Variant in _patterns:
		roll -= float(_patterns[p])
		if roll <= 0.0:
			return str(p)
	return "peg_field"


func _apply_pattern(pattern: String, kinds: PackedByteArray, above: ShaftChunk, r0: int, r1: int, rng: RandomNumberGenerator) -> void:
	match pattern:
		"peg_field":
			_peg_field(kinds, above, r0, r1, rng)
		"shelves":
			_shelves(kinds, above, r0, r1, rng, Shaft.Kind.BLOCK)
		"timber":
			_shelves(kinds, above, r0, r1, rng, Shaft.Kind.KINDLING)
		"funnel":
			_funnel(kinds, above, r0, r1, rng)
		"vein_mass":
			_vein_mass(kinds, above, r0, r1, rng)
		"cavern":
			_cavern(kinds, above, r0, r1, rng, false)
		"lake":
			_cavern(kinds, above, r0, r1, rng, true)
		_:
			push_warning("ShaftGenerator: unknown pattern '%s'" % pattern)
			_peg_field(kinds, above, r0, r1, rng)


## Offset rows of pegs (a classic plinko lattice) with a few stray blocks to break.
func _peg_field(kinds: PackedByteArray, above: ShaftChunk, r0: int, r1: int, rng: RandomNumberGenerator) -> void:
	var spacing := int(_gen["peg_field_spacing"])
	var shift := rng.randi_range(0, spacing - 1)
	for r in range(r0, r1):
		var row_i := r - r0
		if row_i % 2 == 0:
			var offset := (shift + (floori(spacing * 0.5) if floori(row_i * 0.5) % 2 == 1 else 0)) % spacing
			for c in range(offset, _columns, spacing):
				_peg(kinds, above, c, r)
		else:
			for c in _columns:
				if rng.randf() < float(_gen["peg_field_block_chance"]):
					_put(kinds, c, r, Shaft.Kind.BLOCK)


## Horizontal shelves of blocks (or kindling beams) with gaps; pegs above the gaps steer embers.
func _shelves(kinds: PackedByteArray, above: ShaftChunk, r0: int, r1: int, rng: RandomNumberGenerator, kind: int) -> void:
	var gap_every := int(_gen["shelf_every_rows"])
	for r in range(r0, r1):
		if (r - r0) % gap_every != 1:
			if rng.randf() < float(_gen["shelf_peg_chance"]):
				_peg(kinds, above, rng.randi_range(1, _columns - 2), r)
			continue
		var thick := rng.randi_range(1, 2)
		for t in thick:
			for c in _columns:
				var cell_kind := kind
				if kind == Shaft.Kind.KINDLING and rng.randf() > float(_gen["timber_kindling_share"]):
					cell_kind = Shaft.Kind.BLOCK
				_put(kinds, c, r + t, cell_kind)
		for _g in rng.randi_range(2, 3):
			var gc := rng.randi_range(0, _columns - 3)
			var gw := rng.randi_range(2, 3)
			for c in range(gc, gc + gw):
				for t in thick:
					_put(kinds, c, r + t, Shaft.Kind.EMPTY)
			_peg(kinds, above, gc + 1, r - 1)


## Pegs in a V that funnels embers into a pocket of blocks.
func _funnel(kinds: PackedByteArray, above: ShaftChunk, r0: int, r1: int, rng: RandomNumberGenerator) -> void:
	var center := rng.randi_range(6, _columns - 7)
	var steps := (r1 - r0) - 2
	for i in maxi(steps, 0):
		var r := r0 + i
		var reach := maxi(2, 11 - i * 2)
		if i % 2 == 0:
			_peg(kinds, above, center - reach, r)
			_peg(kinds, above, center + reach, r)
	for r in range(maxi(r1 - 3, r0), r1):
		for c in range(center - 4, center + 5):
			_put(kinds, c, r, Shaft.Kind.BLOCK)


## A dense mass of ore cut by one or two chutes.
func _vein_mass(kinds: PackedByteArray, above: ShaftChunk, r0: int, r1: int, rng: RandomNumberGenerator) -> void:
	for r in range(r0, r1):
		for c in _columns:
			if rng.randf() < float(_gen["vein_mass_fill"]):
				_put(kinds, c, r, Shaft.Kind.BLOCK)
	for _ch in rng.randi_range(1, 2):
		var c := rng.randi_range(2, _columns - 3)
		for r in range(r0, r1):
			_put(kinds, c, r, Shaft.Kind.EMPTY)
			_put(kinds, c + 1, r, Shaft.Kind.EMPTY)
			if (r - r0) % 3 == 2:
				c = clampi(c + rng.randi_range(-1, 1), 1, _columns - 3)


## Open cave with rock along the walls, floating islands and pegs. A lake floods its floor.
func _cavern(kinds: PackedByteArray, above: ShaftChunk, r0: int, r1: int, rng: RandomNumberGenerator, lake: bool) -> void:
	for r in range(r0, r1):
		var left := rng.randi_range(0, 3)
		var right := rng.randi_range(0, 3)
		for c in left:
			_put(kinds, c, r, Shaft.Kind.BLOCK)
		for c in right:
			_put(kinds, _columns - 1 - c, r, Shaft.Kind.BLOCK)
		if rng.randf() < float(_gen["cavern_peg_chance"]):
			_peg(kinds, above, rng.randi_range(4, _columns - 5), r)
	for _i in rng.randi_range(1, 3):
		var cx := rng.randi_range(4, _columns - 5)
		var cy := rng.randi_range(r0, r1 - 1)
		for dy in range(-1, 2):
			for dx in range(-2, 3):
				if absi(dx) + absi(dy) <= 2:
					_put(kinds, cx + dx, cy + dy, Shaft.Kind.BLOCK)
	if lake:
		var depth := rng.randi_range(2, 4)
		var lx := rng.randi_range(2, 6)
		var rx := _columns - rng.randi_range(3, 7)
		for r in range(maxi(r1 - depth, r0), r1):
			for c in range(lx, rx):
				_put(kinds, c, r, Shaft.Kind.WATER)
			_put(kinds, lx - 1, r, Shaft.Kind.BLOCK)
			_put(kinds, rx, r, Shaft.Kind.BLOCK)
		for c in range(lx - 1, rx + 1):
			_put(kinds, c, r1, Shaft.Kind.BLOCK)


# --- helpers -------------------------------------------------------------------

func _is_minable_row(row: int) -> bool:
	return row >= _top_empty and row < _minable_end


func _put(kinds: PackedByteArray, col: int, lr: int, kind: int) -> void:
	if col < 0 or col >= _columns or lr < 0 or lr >= _chunk_rows:
		return
	kinds[lr * _columns + col] = kind


## Places a peg if the cell is open and no other peg is adjacent.
func _peg(kinds: PackedByteArray, above: ShaftChunk, col: int, lr: int) -> void:
	if col < 0 or col >= _columns or lr < 0 or lr >= _chunk_rows:
		return
	if kinds[lr * _columns + col] != Shaft.Kind.EMPTY or _peg_nearby(kinds, above, col, lr):
		return
	kinds[lr * _columns + col] = Shaft.Kind.PEG


func _touches(kinds: PackedByteArray, i: int, kind: int) -> bool:
	var col := i % _columns
	@warning_ignore("integer_division")
	var lr := i / _columns
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var c := col + d.x
		var r := lr + d.y
		if c >= 0 and c < _columns and r >= 0 and r < _chunk_rows and kinds[r * _columns + c] == kind:
			return true
	return false


func _nearest_seed_ore(seeds: Array[Vector3i], col: int, lr: int) -> int:
	var best := -1
	var best_d := 1 << 30
	for s in seeds:
		var d := absi(s.x - col) + absi(s.y - lr) * 2
		if d < best_d:
			best_d = d
			best = s.z
	return best


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
