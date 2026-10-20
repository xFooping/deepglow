class_name BossCrystal
extends Node2D
## The giant crystal in the boss chamber. Its HP resets every day; the player has to deal all of
## it in a single day. Embers bounce off it like a block (Shaft reports its cells as Kind.BOSS).

signal defeated

var shaft_id: int = 1
var max_hp: int = 1
var hp: int = 1
var area := Rect2()

var _tex: Texture2D
var _color := Color.WHITE
var _flash_left: float = 0.0
var _time: float = 0.0
var _flash_s: float
var _shimmer_speed: float
var _shimmer_amount: float
var _crack_seed: int = 0
var _solid := PackedByteArray()
var _mask_size := Vector2i.ZERO


func setup(id: int, rect: Rect2, cell_px: int) -> void:
	shaft_id = id
	area = rect
	var data: Dictionary = DataDB.shafts[id]
	max_hp = int(data["boss_hp"])
	hp = max_hp
	_tex = DataDB.texture(str(data["boss_texture_path"]))
	_color = Color.html(str(data.get("boss_color", "#ffffff")))
	_flash_s = DataDB.num("boss.hit_flash_s")
	_shimmer_speed = DataDB.num("boss.shimmer_speed")
	_shimmer_amount = DataDB.num("boss.shimmer_amount")
	_crack_seed = id * 7919
	_build_solid_mask(Vector2i(area.size / cell_px), cell_px)


## Which cells of the boss rectangle are solid, read from the texture so the collision follows
## the art: a cell is solid when at least a third of its pixels are opaque. No texture = all solid.
func _build_solid_mask(cells: Vector2i, cell: int) -> void:
	_mask_size = cells
	_solid.resize(cells.x * cells.y)
	_solid.fill(1)
	if _tex == null:
		return
	var img := _tex.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	img.resize(cells.x * cell, cells.y * cell, Image.INTERPOLATE_NEAREST)
	for cy in cells.y:
		for cx in cells.x:
			var opaque := 0
			for y in cell:
				for x in cell:
					if img.get_pixel(cx * cell + x, cy * cell + y).a > 0.5:
						opaque += 1
			_solid[cy * cells.x + cx] = 1 if opaque * 3 >= cell * cell else 0


## local_cell is relative to the top-left cell of the boss rectangle.
func is_solid(local_cell: Vector2i) -> bool:
	return _solid[local_cell.y * _mask_size.x + local_cell.x] == 1


func hit(damage: int, crit: bool) -> void:
	if hp <= 0:
		return
	var dealt := mini(damage, hp)
	hp -= dealt
	GameState.day_boss_damage += dealt
	_flash_left = _flash_s
	Events.boss_hit.emit(shaft_id, dealt, hp, max_hp, crit)
	AudioManager.play("boss_hit")
	if hp <= 0:
		_shatter()


func center() -> Vector2:
	return area.get_center()


func _shatter() -> void:
	defeated.emit()
	Events.boss_shattered.emit(center(), _color)
	AudioManager.play("boss_shatter")
	GameState.defeat_boss(shaft_id)
	queue_free()


func _process(delta: float) -> void:
	_time += delta
	_flash_left = maxf(0.0, _flash_left - delta)
	queue_redraw()


func _draw() -> void:
	# Idle shimmer: a slow brightness wave. The hit flash goes white for a moment.
	var shimmer := 1.0 + sin(_time * _shimmer_speed) * _shimmer_amount
	var tint := Color(shimmer, shimmer, shimmer)
	if _flash_left > 0.0:
		tint = Color(1.6, 1.6, 1.6)
	if _tex:
		draw_texture_rect(_tex, area, false, tint)
	else:
		draw_rect(area, _color * tint)
	# Cracks spread as HP drops: one more jagged line per 1/8 of HP lost.
	var rng := RandomNumberGenerator.new()
	rng.seed = _crack_seed
	var lines := floori((1.0 - float(hp) / max_hp) * 8.0)
	for _i in lines:
		var p := area.position + Vector2(rng.randf_range(0.2, 0.8) * area.size.x, rng.randf_range(0.2, 0.8) * area.size.y)
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for _s in 5:
			var q := p + dir * rng.randf_range(4.0, 9.0)
			draw_line(p, q, Color(0.1, 0.05, 0.1, 0.8), 1.0)
			p = q
			dir = dir.rotated(rng.randf_range(-0.7, 0.7))
