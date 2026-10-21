class_name Shaft
extends Node2D
## Today's shaft as a grid of cells. Generates chunks ahead of the camera and frees them behind it.
## Cell data lives in ShaftChunk packed arrays; blocks, pegs and cracks are drawn by TileMapLayers
## that are updated cell by cell when something breaks.
## 1 row = 1 meter. Below boss depth is an open chamber holding the boss crystal, then an indestructible floor.

enum Kind { EMPTY, BLOCK, PEG, SPECIAL, FLOOR, MUSHROOM, BOSS, PRISM, WATER, KINDLING }

const PEG_TEXTURE := "res://art/blocks/peg.png"
const MUSHROOM_TEXTURE := "res://art/blocks/mushroom.png"
const PRISM_TEXTURE := "res://art/blocks/prism.png"
const WATER_TEXTURE := "res://art/blocks/water.png"
const KINDLING_TEXTURE := "res://art/blocks/kindling.png"
const RICH_TEXTURE := "res://art/blocks/rich_vein.png"
const LODE_TEXTURE := "res://art/blocks/lode.png"
const CRACK_TEXTURES: Array[String] = ["res://art/blocks/crack_1.png", "res://art/blocks/crack_2.png"]

var shaft_id: int = 1
var data: Dictionary = {}
var columns: int = 24
var cell_px: int = 16
var chunk_rows: int = 32
var floor_row: int = 0
var boss_row: int = 0             ## First row of the boss chamber (= boss depth in meters).
var boss: BossCrystal              ## Null once defeated, or on a day it isn't spawned.
var boss_cells := Rect2i()
var _chamber_wall := PackedInt32Array()  ## per chamber row: wall width in cells on each side
var width_px: float = 0.0
var floor_y: float = 0.0
var ore_ids: Array[String] = []
var ore_colors := PackedColorArray()

var _ore_max_hp := PackedInt32Array()
var _block_sources := PackedInt32Array()  ## ore index -> TileSet source id
var _peg_source: int = -1
var _mushroom_source: int = -1
var _prism_source: int = -1
var _water_source: int = -1
var _kindling_source: int = -1
var _rich_source: int = -1
var _rich_mult: float = 2.0
var _lode_source: int = -1
var _lode_mult: float = 8.0
var _peg_glow: PegGlow
var _kindling_delay: float
var _kindling_radius: int
var _bursts: Array[Dictionary] = []  ## pending kindling bursts: {cell, damage, chain, t}
var _crack_sources := PackedInt32Array()
var _crack_stage_1: float = 0.66
var _crack_stage_2: float = 0.33
var _blocks: TileMapLayer
var _cracks: TileMapLayer
var _water: TileMapLayer
var _overlay: TileMapLayer
var _flash: ShaftFlash
var _squash: MushroomSquash

var _chunks: Array = []  ## chunk index -> ShaftChunk, or null once freed
var _freed_through: int = -1
var _generator: ShaftGenerator


func setup(id: int, day_seed: int) -> void:
	shaft_id = id
	data = DataDB.shafts[id]
	columns = DataDB.integer("grid.columns")
	cell_px = DataDB.integer("grid.cell_px")
	chunk_rows = DataDB.integer("grid.chunk_rows")
	boss_row = int(data["boss_depth_m"])
	floor_row = boss_row + int(data["boss_chamber_rows"])
	_build_chamber_walls()
	width_px = columns * cell_px
	floor_y = floor_row * cell_px
	_crack_stage_1 = DataDB.num("blocks.crack_stage_1")
	_crack_stage_2 = DataDB.num("blocks.crack_stage_2")

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(cell_px, cell_px)
	for ore in DataDB.ores:
		var color := Color.html(str(ore["color"]))
		ore_ids.append(str(ore["id"]))
		ore_colors.append(color)
		_ore_max_hp.append(int(ore["hp"]))
		_block_sources.append(_add_source(tile_set, DataDB.texture(str(ore["block_texture_path"])), color))
	_peg_source = _add_source(tile_set, DataDB.texture(PEG_TEXTURE), Color(0.7, 0.95, 1.0))
	_mushroom_source = _add_source(tile_set, DataDB.texture(MUSHROOM_TEXTURE), Color(0.4, 0.9, 0.8))
	_prism_source = _add_source(tile_set, DataDB.texture(PRISM_TEXTURE), Color(1.0, 0.8, 0.95))
	_water_source = _add_source(tile_set, DataDB.texture(WATER_TEXTURE), Color(0.3, 0.5, 0.9, 0.5))
	_kindling_source = _add_source(tile_set, DataDB.texture(KINDLING_TEXTURE), Color(0.6, 0.4, 0.2))
	_rich_source = _add_source(tile_set, DataDB.texture(RICH_TEXTURE), Color(1, 1, 1, 0.3))
	_rich_mult = DataDB.num("twists.rich_vein_yield_mult")
	_lode_source = _add_source(tile_set, DataDB.texture(LODE_TEXTURE), Color(1, 1, 0.8, 0.5))
	_lode_mult = DataDB.num("generation.lode_yield_mult")
	_kindling_delay = DataDB.num("twists.kindling_chain_delay_s")
	_kindling_radius = DataDB.integer("twists.kindling_radius_cells")
	for path in CRACK_TEXTURES:
		_crack_sources.append(_add_source(tile_set, DataDB.texture(path), Color(0, 0, 0, 0.4)))

	_water = TileMapLayer.new()
	_water.tile_set = tile_set
	add_child(_water)
	_blocks = TileMapLayer.new()
	_blocks.tile_set = tile_set
	add_child(_blocks)
	_overlay = TileMapLayer.new()
	_overlay.tile_set = tile_set
	add_child(_overlay)
	_cracks = TileMapLayer.new()
	_cracks.tile_set = tile_set
	add_child(_cracks)
	_flash = ShaftFlash.new()
	_flash.cell_px = cell_px
	add_child(_flash)
	_peg_glow = PegGlow.new()
	_peg_glow.cell_px = cell_px
	add_child(_peg_glow)
	_squash = MushroomSquash.new()
	_squash.setup(self, DataDB.texture(MUSHROOM_TEXTURE))
	add_child(_squash)

	_generator = ShaftGenerator.new(data, day_seed, columns, chunk_rows, DataDB.integer("grid.top_empty_rows"), boss_row)


## One single-tile atlas per texture, so any PNG can be swapped without touching code.
func _add_source(tile_set: TileSet, tex: Texture2D, fallback: Color) -> int:
	if tex == null:
		var img := Image.create_empty(cell_px, cell_px, false, Image.FORMAT_RGBA8)
		img.fill(fallback)
		tex = ImageTexture.create_from_image(img)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(cell_px, cell_px)
	src.create_tile(Vector2i.ZERO)
	return tile_set.add_source(src)


func ensure_generated_to(world_y: float) -> void:
	var last_row := mini(floori(world_y / cell_px), floor_row - 1)
	var needed := floori(float(last_row) / chunk_rows)
	while _chunks.size() <= needed:
		var chunk := ShaftChunk.new(_chunks.size(), chunk_rows)
		var above: ShaftChunk = _chunks.back() if not _chunks.is_empty() else null
		_generator.fill(chunk, above)
		_chunks.append(chunk)
		_paint_chunk(chunk)


## Frees every chunk that lies entirely above world_y. They are never regenerated.
func free_above(world_y: float) -> void:
	var last_free := mini(floori(floorf(world_y / cell_px) / chunk_rows) - 1, _chunks.size() - 1)
	while _freed_through < last_free:
		_freed_through += 1
		var chunk: ShaftChunk = _chunks[_freed_through]
		if chunk:
			for lr in chunk.rows:
				for col in columns:
					var c := Vector2i(col, chunk.first_row + lr)
					_blocks.erase_cell(c)
					_cracks.erase_cell(c)
					_water.erase_cell(c)
					_overlay.erase_cell(c)
			_chunks[_freed_through] = null


func chunk_count() -> int:
	return _chunks.size() - _freed_through - 1


func kind_at(col: int, row: int) -> int:
	if row >= floor_row:
		return Kind.FLOOR
	if row < 0 or col < 0 or col >= columns:
		return Kind.EMPTY
	if row >= boss_row:
		var wall := _chamber_wall[row - boss_row]
		if col < wall or col >= columns - wall:
			return Kind.FLOOR
	if boss and row >= boss_cells.position.y and boss_cells.has_point(Vector2i(col, row)):
		if boss.is_solid(Vector2i(col, row) - boss_cells.position):
			return Kind.BOSS
	@warning_ignore("integer_division")
	var ci := row / chunk_rows
	if ci >= _chunks.size():
		return Kind.EMPTY
	var chunk: ShaftChunk = _chunks[ci]
	if chunk == null:
		return Kind.EMPTY
	return chunk.kinds[(row - chunk.first_row) * columns + col]


## Damages a block or kindling. Returns true if it broke. ember_damage is the base (non-crit)
## damage of whatever hit it; a breaking kindling block bursts for a multiple of it.
func hit_block(cell: Vector2i, damage: int, crit: bool, ember_damage: int = 0, chain: int = 0, combo_mult: float = 1.0) -> bool:
	var kind := kind_at(cell.x, cell.y)
	if kind != Kind.BLOCK and kind != Kind.KINDLING:
		return false
	@warning_ignore("integer_division")
	var chunk: ShaftChunk = _chunks[cell.y / chunk_rows]
	var i := (cell.y - chunk.first_row) * columns + cell.x
	var ore_i := chunk.ore[i]
	var center := cell_center(cell)
	var max_hp := chunk.hp[i]
	if kind == Kind.BLOCK:
		max_hp = _ore_max_hp[ore_i]
	var remaining := chunk.apply_damage(i, damage)
	if kind == Kind.BLOCK:
		Events.block_hit.emit(cell, ore_ids[ore_i], damage, crit, center)
	if remaining > 0:
		if kind == Kind.BLOCK:
			_update_crack(cell, float(remaining) / max_hp)
		_flash.add(cell)
		return false
	_blocks.erase_cell(cell)
	_cracks.erase_cell(cell)
	_overlay.erase_cell(cell)
	if kind == Kind.KINDLING:
		_queue_burst(cell, maxi(ember_damage, 1), chain)
		return true
	var yield_mult := combo_mult
	if chunk.rich[i] == ShaftGenerator.RICH_VEIN:
		yield_mult *= _rich_mult
	elif chunk.rich[i] == ShaftGenerator.LODE:
		yield_mult *= _lode_mult
	chunk.rich[i] = 0
	Events.block_broken.emit(cell, ore_ids[ore_i], center, yield_mult)
	AudioManager.play("block_break")
	return true


# --- The Hearth: kindling chain reactions -----------------------------------

func _queue_burst(cell: Vector2i, ember_damage: int, chain: int) -> void:
	_bursts.append({"cell": cell, "damage": ember_damage, "chain": chain, "t": _kindling_delay * float(chain > 0)})


## Warm, staggered pops: each kindling block bursts a beat after the one that set it off,
## hitting every block within the burst radius for kindling_burst_mult x ember damage.
func _physics_process(delta: float) -> void:
	if _bursts.is_empty():
		return
	var due: Array[Dictionary] = []
	for b in _bursts:
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) <= 0.0:
			due.append(b)
	for b in due:
		_bursts.erase(b)
		var cell: Vector2i = b["cell"]
		var chain: int = int(b["chain"]) + 1
		var ember_damage: int = b["damage"]
		var burst := roundi(ember_damage * Stats.get_f("kindling_burst_mult"))
		Events.kindling_popped.emit(cell_center(cell), chain)
		AudioManager.play("kindling_pop")
		var best := int(GameState.achievement_stats.get("max_kindling_chain", 0))
		if chain > best:
			GameState.achievement_stats["max_kindling_chain"] = chain
		for dy in range(-_kindling_radius, _kindling_radius + 1):
			for dx in range(-_kindling_radius, _kindling_radius + 1):
				if dx != 0 or dy != 0:
					hit_block(cell + Vector2i(dx, dy), burst, false, ember_damage, chain)


func water_at(p: Vector2) -> bool:
	return kind_at(floori(p.x / cell_px), floori(p.y / cell_px)) == Kind.WATER


## The chamber narrows like a funnel: wall width grows from 0 at the top to the gap beside the
## crystal at the bottom, so embers that fall in are steered onto it.
func _build_chamber_walls() -> void:
	var rows := floor_row - boss_row
	var size_cells: Array = data["boss_size_cells"]
	@warning_ignore("integer_division")
	var bottom_wall := (columns - int(size_cells[0])) / 2 - int(DataDB.num("boss.funnel_gap_cells"))
	_chamber_wall.resize(rows)
	for k in rows:
		_chamber_wall[k] = maxi(0, floori(bottom_wall * float(k + 1) / rows))


func is_chamber_wall(col: int, row: int) -> bool:
	if row < boss_row or row >= floor_row:
		return false
	var wall := _chamber_wall[row - boss_row]
	return col < wall or col >= columns - wall


## Places today's boss crystal on the chamber floor, centered. Skipped once that boss is beaten.
func spawn_boss(crystal: BossCrystal) -> void:
	var size_cells: Array = data["boss_size_cells"]
	var w := int(size_cells[0])
	var h := int(size_cells[1])
	@warning_ignore("integer_division")
	boss_cells = Rect2i((columns - w) / 2, floor_row - h, w, h)
	boss = crystal
	crystal.setup(shaft_id, Rect2(Vector2(boss_cells.position * cell_px), Vector2(boss_cells.size * cell_px)), cell_px)
	crystal.defeated.connect(_on_boss_defeated)
	add_child(crystal)


func hit_boss(damage: int, crit: bool) -> void:
	if boss:
		boss.hit(damage, crit)


func boss_y() -> float:
	return boss_row * cell_px


func _on_boss_defeated() -> void:
	boss = null


## Bomb ember blast: damages every block and kindling within radius cells (round).
func explode(cell: Vector2i, radius: int, damage: int, ember_damage: int, combo_mult: float) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius + radius:
				hit_block(cell + Vector2i(dx, dy), damage, false, ember_damage, 0, combo_mult)
	Events.bomb_exploded.emit(cell_center(cell), radius)
	AudioManager.play("bomb_blast")


## HP left in a block or kindling cell, or -1 if it isn't one.
func block_hp(cell: Vector2i) -> int:
	var k := kind_at(cell.x, cell.y)
	if k != Kind.BLOCK and k != Kind.KINDLING:
		return -1
	@warning_ignore("integer_division")
	var chunk: ShaftChunk = _chunks[cell.y / chunk_rows]
	return chunk.hp[(cell.y - chunk.first_row) * columns + cell.x]


func is_lode(cell: Vector2i) -> bool:
	if kind_at(cell.x, cell.y) != Kind.BLOCK:
		return false
	@warning_ignore("integer_division")
	var chunk: ShaftChunk = _chunks[cell.y / chunk_rows]
	return chunk.rich[(cell.y - chunk.first_row) * columns + cell.x] == ShaftGenerator.LODE


## Lights up a peg that was just hit (the plinko "ping").
func light_peg(cell: Vector2i, combo: int) -> void:
	_peg_glow.light(cell, combo)


## Clears blocks around the lantern keeper so it never hangs inside solid rock. No ore drops.
func carve(center: Vector2, half_cells: Vector2i) -> void:
	var cc := Vector2i(floori(center.x / cell_px), floori(center.y / cell_px))
	for dy in range(-half_cells.y, half_cells.y + 1):
		for dx in range(-half_cells.x, half_cells.x + 1):
			var cell := cc + Vector2i(dx, dy)
			var k := kind_at(cell.x, cell.y)
			if k == Kind.BLOCK or k == Kind.KINDLING:
				@warning_ignore("integer_division")
				var chunk: ShaftChunk = _chunks[cell.y / chunk_rows]
				var i := (cell.y - chunk.first_row) * columns + cell.x
				chunk.apply_damage(i, chunk.hp[i])
				chunk.rich[i] = 0
				_blocks.erase_cell(cell)
				_cracks.erase_cell(cell)
				_overlay.erase_cell(cell)


## Plays the squash on a mushroom peg that was just bounced off.
func squash_mushroom(cell: Vector2i) -> void:
	_squash.squash(cell)


## A random block among the 4 neighbours, or (-1, -1) if there is none.
func random_adjacent_block(cell: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var options: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n := cell + d
		var k := kind_at(n.x, n.y)
		if k == Kind.BLOCK or k == Kind.KINDLING:
			options.append(n)
	if options.is_empty():
		return Vector2i(-1, -1)
	return options[rng.randi_range(0, options.size() - 1)]


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_px, (cell.y + 0.5) * cell_px)


func _paint_chunk(chunk: ShaftChunk) -> void:
	for i in chunk.kinds.size():
		@warning_ignore("integer_division")
		var c := Vector2i(i % columns, chunk.first_row + i / columns)
		match chunk.kinds[i]:
			Kind.BLOCK:
				_blocks.set_cell(c, _block_sources[chunk.ore[i]], Vector2i.ZERO)
			Kind.PEG:
				_blocks.set_cell(c, _peg_source, Vector2i.ZERO)
			Kind.MUSHROOM:
				_blocks.set_cell(c, _mushroom_source, Vector2i.ZERO)
			Kind.PRISM:
				_blocks.set_cell(c, _prism_source, Vector2i.ZERO)
			Kind.WATER:
				_water.set_cell(c, _water_source, Vector2i.ZERO)
			Kind.KINDLING:
				_blocks.set_cell(c, _kindling_source, Vector2i.ZERO)
		if chunk.rich[i] == ShaftGenerator.RICH_VEIN:
			_overlay.set_cell(c, _rich_source, Vector2i.ZERO)
		elif chunk.rich[i] == ShaftGenerator.LODE:
			_overlay.set_cell(c, _lode_source, Vector2i.ZERO)


## Hides a mushroom's tile while MushroomSquash draws it squashed, then restores it.
func set_mushroom_tile_visible(cell: Vector2i, shown: bool) -> void:
	if shown:
		_blocks.set_cell(cell, _mushroom_source, Vector2i.ZERO)
	else:
		_blocks.erase_cell(cell)


func _update_crack(cell: Vector2i, hp_frac: float) -> void:
	var stage := -1
	if hp_frac <= _crack_stage_2:
		stage = 1
	elif hp_frac <= _crack_stage_1:
		stage = 0
	if stage < 0:
		return
	if _cracks.get_cell_source_id(cell) != _crack_sources[stage]:
		_cracks.set_cell(cell, _crack_sources[stage], Vector2i.ZERO)
