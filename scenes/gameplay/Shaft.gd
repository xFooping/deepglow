class_name Shaft
extends Node2D
## Today's shaft as a grid of cells. Generates chunks ahead of the camera and frees them behind it.
## Cell data lives in ShaftChunk packed arrays; blocks, pegs and cracks are drawn by TileMapLayers
## that are updated cell by cell when something breaks.
## 1 row = 1 meter. Phase 1 has no boss chamber: the shaft ends in an indestructible floor at boss depth.

enum Kind { EMPTY, BLOCK, PEG, SPECIAL, FLOOR }

const PEG_TEXTURE := "res://art/blocks/peg.png"
const CRACK_TEXTURES: Array[String] = ["res://art/blocks/crack_1.png", "res://art/blocks/crack_2.png"]

var shaft_id: int = 1
var data: Dictionary = {}
var columns: int = 24
var cell_px: int = 16
var chunk_rows: int = 32
var floor_row: int = 0
var width_px: float = 0.0
var floor_y: float = 0.0
var ore_ids: Array[String] = []
var ore_colors := PackedColorArray()

var _ore_max_hp := PackedInt32Array()
var _block_sources := PackedInt32Array()  ## ore index -> TileSet source id
var _peg_source: int = -1
var _crack_sources := PackedInt32Array()
var _crack_stage_1: float = 0.66
var _crack_stage_2: float = 0.33
var _blocks: TileMapLayer
var _cracks: TileMapLayer
var _flash: ShaftFlash

var _chunks: Array = []  ## chunk index -> ShaftChunk, or null once freed
var _freed_through: int = -1
var _generator: ShaftGenerator


func setup(id: int, day_seed: int) -> void:
	shaft_id = id
	data = DataDB.shafts[id]
	columns = DataDB.integer("grid.columns")
	cell_px = DataDB.integer("grid.cell_px")
	chunk_rows = DataDB.integer("grid.chunk_rows")
	floor_row = int(data["boss_depth_m"])
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
	for path in CRACK_TEXTURES:
		_crack_sources.append(_add_source(tile_set, DataDB.texture(path), Color(0, 0, 0, 0.4)))

	_blocks = TileMapLayer.new()
	_blocks.tile_set = tile_set
	add_child(_blocks)
	_cracks = TileMapLayer.new()
	_cracks.tile_set = tile_set
	add_child(_cracks)
	_flash = ShaftFlash.new()
	_flash.cell_px = cell_px
	add_child(_flash)

	_generator = ShaftGenerator.new(data, day_seed, columns, chunk_rows, DataDB.integer("grid.top_empty_rows"), floor_row)


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
			_chunks[_freed_through] = null


func chunk_count() -> int:
	return _chunks.size() - _freed_through - 1


func kind_at(col: int, row: int) -> int:
	if row >= floor_row:
		return Kind.FLOOR
	if row < 0 or col < 0 or col >= columns:
		return Kind.EMPTY
	@warning_ignore("integer_division")
	var ci := row / chunk_rows
	if ci >= _chunks.size():
		return Kind.EMPTY
	var chunk: ShaftChunk = _chunks[ci]
	if chunk == null:
		return Kind.EMPTY
	return chunk.kinds[(row - chunk.first_row) * columns + col]


## Damages a block. Returns true if it broke.
func hit_block(cell: Vector2i, damage: int, crit: bool) -> bool:
	if kind_at(cell.x, cell.y) != Kind.BLOCK:
		return false
	@warning_ignore("integer_division")
	var chunk: ShaftChunk = _chunks[cell.y / chunk_rows]
	var i := (cell.y - chunk.first_row) * columns + cell.x
	var ore_i := chunk.ore[i]
	var center := cell_center(cell)
	var remaining := chunk.apply_damage(i, damage)
	Events.block_hit.emit(cell, ore_ids[ore_i], damage, crit, center)
	if remaining > 0:
		_update_crack(cell, float(remaining) / _ore_max_hp[ore_i])
		_flash.add(cell)
		return false
	_blocks.erase_cell(cell)
	_cracks.erase_cell(cell)
	Events.block_broken.emit(cell, ore_ids[ore_i], center)
	AudioManager.play("block_break")
	return true


## A random block among the 4 neighbours, or (-1, -1) if there is none.
func random_adjacent_block(cell: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var options: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n := cell + d
		if kind_at(n.x, n.y) == Kind.BLOCK:
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
