class_name EmberManager
extends Node2D
## Pooled embers with hand-rolled circle-vs-grid physics in _physics_process (no RigidBody2D, spec 4.5).
## Drawn in one pass, interpolated between physics ticks.

signal supply_changed(supply: int)

const CORE_TEXTURE := "res://art/embers/ember_core.png"
const GLOW_TEXTURE := "res://art/embers/ember_glow.png"


class Ember:
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var vel := Vector2.ZERO
	var damage: int = 1
	var durability: int = 1
	var max_durability: int = 1
	var stuck_time: float = 0.0
	var hit_cooldown: float = 0.0
	## Launched from inside rock (the keeper hangs above the dug-out area): passes through
	## blocks and pegs until it first reaches open air.
	var phasing: bool = false


var supply: int = 0
var active: Array[Ember] = []
var deepest_y: float = 0.0

var _pool: Array[Ember] = []
var _shaft: Shaft
var _camera: CameraRig
var _rng := RandomNumberGenerator.new()
var _glow: Node2D
var _core_tex: Texture2D
var _glow_tex: Texture2D

var _gravity: float
var _max_speed: float
var _block_restitution: float
var _peg_restitution: float
var _wall_restitution: float
var _stuck_speed: float
var _stuck_limit: float
var _radius: float
var _peg_radius: float
var _jitter: float
var _min_hit_speed: float
var _hit_cooldown: float
var _max_step: float
var _leash: float
var _cap: int
var _crit_mult: int
var _min_alpha: float
var _crit_chance: float
var _chain_chance: float


func setup(shaft: Shaft, camera: CameraRig, day_seed: int) -> void:
	_shaft = shaft
	_camera = camera
	_rng.seed = day_seed
	_gravity = DataDB.num("physics.gravity")
	_max_speed = DataDB.num("physics.max_speed")
	_block_restitution = DataDB.num("physics.block_restitution")
	_peg_restitution = DataDB.num("physics.peg_restitution")
	_wall_restitution = DataDB.num("physics.wall_restitution")
	_stuck_speed = DataDB.num("physics.stuck_speed_threshold")
	_stuck_limit = DataDB.num("physics.stuck_time_to_burnout")
	_radius = DataDB.num("physics.ember_radius")
	_peg_radius = DataDB.num("physics.peg_radius")
	_jitter = deg_to_rad(DataDB.num("physics.bounce_jitter_deg"))
	_min_hit_speed = DataDB.num("physics.min_hit_speed")
	_hit_cooldown = DataDB.num("physics.hit_cooldown_s")
	_max_step = _radius * DataDB.num("physics.substep_fraction_of_radius")
	_leash = DataDB.num("camera.leash_px")
	_cap = DataDB.integer("combat.active_ember_cap")
	_crit_mult = DataDB.integer("combat.crit_multiplier")
	_min_alpha = DataDB.num("combat.ember_min_alpha")
	_core_tex = DataDB.texture(CORE_TEXTURE)
	_glow_tex = DataDB.texture(GLOW_TEXTURE)

	_glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.show_behind_parent = true
	_glow.draw.connect(_draw_glow)
	add_child(_glow)

	Stats.stats_changed.connect(_cache_stats)
	_cache_stats()
	supply = Stats.get_i("ember_count")


func _cache_stats() -> void:
	_crit_chance = Stats.get_f("crit_chance")
	_chain_chance = Stats.get_f("chain_spark_chance")


## Launches one ember from the day's supply.
func launch(origin: Vector2, velocity: Vector2) -> bool:
	if supply <= 0 or active.size() >= _cap:
		return false
	supply -= 1
	supply_changed.emit(supply)
	_spawn(origin, velocity)
	Events.ember_launched.emit()
	return true


## Spawns an ember that doesn't use the day's supply (debug, and later prism splits).
func spawn_free(origin: Vector2, velocity: Vector2) -> void:
	if active.size() < _cap:
		_spawn(origin, velocity)


func set_supply(value: int) -> void:
	supply = maxi(value, 0)
	supply_changed.emit(supply)


func burn_out_all() -> void:
	for i in range(active.size() - 1, -1, -1):
		_burn_out(i)


## True if an ember at p would touch a wall, the floor, a peg or (unless ignore_blocks) a block.
func overlaps_solid(p: Vector2, ignore_blocks: bool = false) -> bool:
	if p.x < _radius or p.x > _shaft.width_px - _radius:
		return true
	var cell := float(_shaft.cell_px)
	for row in range(floori((p.y - _radius) / cell), floori((p.y + _radius) / cell) + 1):
		for col in range(floori((p.x - _radius) / cell), floori((p.x + _radius) / cell) + 1):
			var kind := _shaft.kind_at(col, row)
			if kind == Shaft.Kind.EMPTY:
				continue
			if kind == Shaft.Kind.PEG:
				if not ignore_blocks and p.distance_squared_to(_shaft.cell_center(Vector2i(col, row))) < (_radius + _peg_radius) ** 2:
					return true
				continue
			if ignore_blocks and kind != Shaft.Kind.FLOOR:
				continue
			var mn := Vector2(col * cell, row * cell)
			if p.distance_squared_to(p.clamp(mn, mn + Vector2(cell, cell))) < _radius * _radius:
				return true
	return false


func _spawn(origin: Vector2, velocity: Vector2) -> void:
	var e: Ember = _pool.pop_back() if not _pool.is_empty() else Ember.new()
	e.pos = origin
	e.prev = origin
	e.vel = velocity
	e.damage = Stats.get_i("ember_damage")
	e.max_durability = Stats.get_i("ember_durability")
	e.durability = e.max_durability
	e.stuck_time = 0.0
	e.hit_cooldown = 0.0
	e.phasing = overlaps_solid(origin) and not overlaps_solid(origin, true)
	active.append(e)


func _physics_process(delta: float) -> void:
	var leash_y := _camera.top - _leash
	var deepest := -INF
	var i := active.size() - 1
	while i >= 0:
		var e := active[i]
		e.prev = e.pos
		e.hit_cooldown -= delta
		_integrate(e, delta)
		if e.vel.length_squared() < _stuck_speed * _stuck_speed:
			e.stuck_time += delta
		else:
			e.stuck_time = 0.0
		if e.durability <= 0 or e.stuck_time >= _stuck_limit or e.pos.y < leash_y:
			_burn_out(i)
		elif e.pos.y > deepest:
			deepest = e.pos.y
		i -= 1
	if deepest > -INF:
		deepest_y = deepest


func _integrate(e: Ember, delta: float) -> void:
	# Substep so an ember never moves more than ~its radius per step (no tunneling).
	var travel := (e.vel.length() + _gravity * delta) * delta
	var steps := maxi(1, ceili(travel / _max_step))
	var dt := delta / steps
	for _s in steps:
		e.vel.y += _gravity * dt
		e.vel = e.vel.limit_length(_max_speed)
		e.pos += e.vel * dt
		_collide(e)
		if e.durability <= 0:
			return


func _collide(e: Ember) -> void:
	if e.pos.x < _radius:
		e.pos.x = _radius
		if e.vel.x < 0.0:
			_bounce(e, Vector2.RIGHT, _wall_restitution)
	elif e.pos.x > _shaft.width_px - _radius:
		e.pos.x = _shaft.width_px - _radius
		if e.vel.x > 0.0:
			_bounce(e, Vector2.LEFT, _wall_restitution)

	var cell := float(_shaft.cell_px)
	var best_pen := 0.0
	var best_normal := Vector2.ZERO
	var best_kind: int = Shaft.Kind.EMPTY
	var best_cell := Vector2i.ZERO
	var touching_block := false
	for row in range(floori((e.pos.y - _radius) / cell), floori((e.pos.y + _radius) / cell) + 1):
		for col in range(floori((e.pos.x - _radius) / cell), floori((e.pos.x + _radius) / cell) + 1):
			var kind := _shaft.kind_at(col, row)
			if kind == Shaft.Kind.EMPTY:
				continue
			var pen := 0.0
			var normal := Vector2.UP
			if kind == Shaft.Kind.PEG:
				if e.phasing:
					continue
				var d := e.pos - _shaft.cell_center(Vector2i(col, row))
				var reach := _radius + _peg_radius
				var dist2 := d.length_squared()
				if dist2 >= reach * reach:
					continue
				var dist := sqrt(dist2)
				if dist > 0.0001:
					normal = d / dist
				pen = reach - dist
			else:
				# Blocks and the floor are solid grid cells (circle vs AABB).
				var mn := Vector2(col * cell, row * cell)
				var d := e.pos - e.pos.clamp(mn, mn + Vector2(cell, cell))
				var dist2 := d.length_squared()
				if dist2 >= _radius * _radius:
					continue
				if kind == Shaft.Kind.BLOCK:
					touching_block = true
					if e.phasing:
						continue
				if dist2 > 0.0001:
					var dist := sqrt(dist2)
					normal = d / dist
					pen = _radius - dist
				else:
					var away := e.pos - (mn + Vector2(cell, cell) * 0.5)
					if away.length_squared() > 0.0001:
						normal = away.normalized()
					pen = _radius
			if pen > best_pen:
				best_pen = pen
				best_normal = normal
				best_kind = kind
				best_cell = Vector2i(col, row)
	if e.phasing and not touching_block:
		e.phasing = false
	if best_pen <= 0.0:
		return

	e.pos += best_normal * best_pen
	var vn := e.vel.dot(best_normal)
	if vn >= 0.0:
		return
	if best_kind == Shaft.Kind.PEG:
		_bounce(e, best_normal, _peg_restitution)
		AudioManager.play("ember_bounce_peg")
		return
	_bounce(e, best_normal, _block_restitution)
	# A short per-ember hit cooldown stops a settled ember from spending its durability 60 times a
	# second; it grinds through the block at a steady rate instead of dying stuck on top of it.
	if best_kind == Shaft.Kind.BLOCK and -vn >= _min_hit_speed and e.hit_cooldown <= 0.0:
		e.hit_cooldown = _hit_cooldown
		_hit_block(e, best_cell)


func _bounce(e: Ember, normal: Vector2, restitution: float) -> void:
	e.vel = e.vel.bounce(normal) * restitution
	e.vel = e.vel.rotated(_rng.randf_range(-_jitter, _jitter))


func _hit_block(e: Ember, cell: Vector2i) -> void:
	var crit := _rng.randf() < _crit_chance
	var damage := e.damage * (_crit_mult if crit else 1)
	e.durability -= 1
	e.stuck_time = 0.0  # grinding through a block is progress, not being stuck
	AudioManager.play("ember_bounce_block")
	if _shaft.hit_block(cell, damage, crit) and _rng.randf() < _chain_chance:
		var next := _shaft.random_adjacent_block(cell, _rng)
		if next.x >= 0:
			_shaft.hit_block(next, e.damage, false)


func _burn_out(i: int) -> void:
	var e := active[i]
	active[i] = active[active.size() - 1]
	active.pop_back()
	_pool.append(e)
	Events.ember_burned_out.emit(e.pos)
	AudioManager.play("ember_burnout")


func _process(_delta: float) -> void:
	queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	var f := Engine.get_physics_interpolation_fraction()
	for e in active:
		var p := e.prev.lerp(e.pos, f)
		var c := Color(1, 1, 1, lerpf(_min_alpha, 1.0, float(e.durability) / e.max_durability))
		if _core_tex:
			draw_texture(_core_tex, (p - _core_tex.get_size() * 0.5).round(), c)
		else:
			draw_circle(p, _radius, Color(1.0, 0.8, 0.4, c.a))


func _draw_glow() -> void:
	if _glow_tex == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var half := _glow_tex.get_size() * 0.5
	for e in active:
		var p := e.prev.lerp(e.pos, f)
		var a := lerpf(_min_alpha, 1.0, float(e.durability) / e.max_durability)
		_glow.draw_texture(_glow_tex, (p - half).round(), Color(1, 1, 1, a))
