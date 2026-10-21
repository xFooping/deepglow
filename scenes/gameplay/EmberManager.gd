class_name EmberManager
extends Node2D
## Pooled embers with hand-rolled circle-vs-grid physics in _physics_process (no RigidBody2D, spec 4.5).
## Drawn in one pass, interpolated between physics ticks.

signal supply_changed(supply: int)

enum EmberKind { NORMAL, BOMB, NOVA }

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
	## Prisms this ember already split on (each prism splits an ember at most once).
	var split_cells: Array[Vector2i] = []
	var water_drain: float = 0.0  ## fractional durability lost in water, carried between ticks
	var steam_timer: float = 0.0
	## Peg bounces so far. Ore from blocks this ember breaks is multiplied by its combo.
	var combo: int = 0
	var kind: int = 0             ## EmberKind
	var pierce_left: int = 0      ## blocks it can still smash straight through
	var seek_target := Vector2.ZERO
	var has_target: bool = false
	var seek_timer: float = 0.0
	var is_echo: bool = false


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
var _mushroom_restitution: float
var _mushroom_nudge: float
var _prism_chance: float
var _combo_step: float
var _combo_max: float
var _combo_popup: int
var _water_drain: float
var _water_speed: float
var _steam_interval: float
var _launch_count: int = 0
var _bomb_every: int
var _bomb_radius: int
var _bomb_mult: float
var _pierce: int
var _multishot: int
var _spread: float
var _seek_strength: float
var _seek_radius: int
var _seek_retarget: float
var _peg_spark: float
var _echo_chance: float
var _echo_frac: float
var _nova_mult: float
var _nova_scale: float


func setup(shaft: Shaft, camera: CameraRig, day_seed: int) -> void:
	_shaft = shaft
	_camera = camera
	_rng.seed = day_seed
	_gravity = DataDB.num("physics.gravity")
	_max_speed = DataDB.num("physics.max_speed")
	_block_restitution = DataDB.num("physics.block_restitution")
	_peg_restitution = DataDB.num("physics.peg_restitution")
	_mushroom_nudge = DataDB.num("twists.mushroom_nudge_speed")
	_water_speed = DataDB.num("twists.water_speed_mult")


	_combo_popup = DataDB.integer("combo.popup_every")
	_steam_interval = DataDB.num("twists.water_steam_interval_s")
	_spread = deg_to_rad(DataDB.num("abilities.multishot_spread_deg"))
	_seek_radius = DataDB.integer("abilities.seek_radius_cells")
	_seek_retarget = DataDB.num("abilities.seek_retarget_s")
	_echo_frac = DataDB.num("abilities.echo_durability_frac")
	_nova_scale = DataDB.num("abilities.nova_scale")
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
	_mushroom_restitution = Stats.get_f("mushroom_restitution")
	_combo_step = Stats.get_f("combo_step")
	_combo_max = Stats.get_f("combo_max")
	_prism_chance = Stats.get_f("prism_split_chance")
	_water_drain = DataDB.num("twists.water_drain_per_sec") * Stats.get_f("water_drain_mult")
	_bomb_every = Stats.get_i("bomb_every")
	_bomb_radius = Stats.get_i("bomb_radius")
	_bomb_mult = Stats.get_f("bomb_damage_mult")
	_pierce = Stats.get_i("pierce")
	_multishot = Stats.get_i("multishot")
	_seek_strength = Stats.get_f("seek_strength")
	_peg_spark = Stats.get_f("peg_spark_mult")
	_echo_chance = Stats.get_f("echo_chance")
	_nova_mult = Stats.get_f("nova_mult")


## Launches one ember from the day's supply.
func launch(origin: Vector2, velocity: Vector2) -> bool:
	if supply <= 0 or active.size() >= _cap:
		return false
	supply -= 1
	supply_changed.emit(supply)
	_launch_count += 1
	var e := _spawn(origin, velocity)
	if supply == 0 and _nova_mult > 1.0:
		# Supernova: the day's last ember is a giant.
		e.kind = EmberKind.NOVA
		e.damage = roundi(e.damage * _nova_mult)
	elif _bomb_every > 0 and _launch_count % _bomb_every == 0:
		e.kind = EmberKind.BOMB
	# Twin wicks: extra embers fanned out around the shot, free of charge.
	for k in _multishot:
		var side := 1.0 if k % 2 == 0 else -1.0
		var step := float(floori(k * 0.5) + 1)
		if active.size() < _cap:
			_spawn(origin, velocity.rotated(side * step * _spread))
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
			if kind == Shaft.Kind.EMPTY or kind == Shaft.Kind.WATER:
				continue
			if kind == Shaft.Kind.PEG or kind == Shaft.Kind.MUSHROOM or kind == Shaft.Kind.PRISM:
				if not ignore_blocks and p.distance_squared_to(_shaft.cell_center(Vector2i(col, row))) < (_radius + _peg_radius) ** 2:
					return true
				continue
			if ignore_blocks and kind != Shaft.Kind.FLOOR and kind != Shaft.Kind.BOSS:
				continue
			var mn := Vector2(col * cell, row * cell)
			if p.distance_squared_to(p.clamp(mn, mn + Vector2(cell, cell))) < _radius * _radius:
				return true
	return false


func _spawn(origin: Vector2, velocity: Vector2) -> Ember:
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
	e.split_cells.clear()
	e.water_drain = 0.0
	e.steam_timer = 0.0
	e.combo = 0
	e.kind = EmberKind.NORMAL
	e.pierce_left = _pierce
	e.has_target = false
	e.seek_timer = 0.0
	e.is_echo = false
	active.append(e)
	return e


func _physics_process(delta: float) -> void:
	var leash_y := _camera.top - _leash
	var deepest := -INF
	var i := active.size() - 1
	while i >= 0:
		var e := active[i]
		e.prev = e.pos
		e.hit_cooldown -= delta
		if _seek_strength > 0.0:
			_seek(e, delta)
		_integrate(e, delta)
		if e.vel.length_squared() < _stuck_speed * _stuck_speed:
			e.stuck_time += delta
		else:
			e.stuck_time = 0.0
		if e.pos.y < leash_y:
			_burn_out(i, false)
		elif e.durability <= 0 or e.stuck_time >= _stuck_limit:
			_burn_out(i, true)
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
		var in_water := _shaft.water_at(e.pos)
		e.pos += e.vel * dt * (_water_speed if in_water else 1.0)
		if in_water:
			_soak(e, dt)
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
			if kind == Shaft.Kind.EMPTY or kind == Shaft.Kind.WATER:
				continue
			var pen := 0.0
			var normal := Vector2.UP
			if kind == Shaft.Kind.PEG or kind == Shaft.Kind.MUSHROOM or kind == Shaft.Kind.PRISM:
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
				# Blocks, the boss and the floor are solid grid cells (circle vs AABB).
				var mn := Vector2(col * cell, row * cell)
				var d := e.pos - e.pos.clamp(mn, mn + Vector2(cell, cell))
				var dist2 := d.length_squared()
				if dist2 >= _radius * _radius:
					continue
				if kind == Shaft.Kind.BLOCK or kind == Shaft.Kind.KINDLING:
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
	# Piercing: an ember that will break the block smashes straight through it, no bounce.
	if e.pierce_left > 0 and best_kind == Shaft.Kind.BLOCK and e.kind == EmberKind.NORMAL and e.hit_cooldown <= 0.0:
		var hp := _shaft.block_hp(best_cell)
		if hp > 0 and hp <= e.damage:
			e.pierce_left -= 1
			e.hit_cooldown = _hit_cooldown
			_hit_block(e, best_cell)
			return

	e.pos += best_normal * best_pen
	var vn := e.vel.dot(best_normal)
	if vn >= 0.0:
		return
	if best_kind == Shaft.Kind.PEG or best_kind == Shaft.Kind.PRISM or best_kind == Shaft.Kind.MUSHROOM:
		_peg_hit(e, best_cell)
	if best_kind == Shaft.Kind.PEG:
		_bounce(e, best_normal, _peg_restitution)
		return
	if best_kind == Shaft.Kind.PRISM:
		_bounce(e, best_normal, _peg_restitution)
		_try_split(e, best_cell)
		return
	if best_kind == Shaft.Kind.MUSHROOM:
		# Springy: gains a little speed and gets nudged sideways, away from the cap's center.
		_bounce(e, best_normal, _mushroom_restitution)
		var side := signf(best_normal.x) if absf(best_normal.x) > 0.05 else (1.0 if _rng.randf() < 0.5 else -1.0)
		e.vel.x += side * _mushroom_nudge
		_shaft.squash_mushroom(best_cell)
		return
	_bounce(e, best_normal, _block_restitution)
	# A short per-ember hit cooldown stops a settled ember from spending its durability 60 times a
	# second; it grinds through the block at a steady rate instead of dying stuck on top of it.
	var hittable := best_kind == Shaft.Kind.BLOCK or best_kind == Shaft.Kind.KINDLING or best_kind == Shaft.Kind.BOSS
	if hittable and (-vn >= _min_hit_speed or best_kind == Shaft.Kind.BOSS) and e.hit_cooldown <= 0.0:
		e.hit_cooldown = _hit_cooldown
		if best_kind == Shaft.Kind.BOSS:
			_hit_boss(e)
		elif e.kind == EmberKind.BOMB:
			e.kind = EmberKind.NORMAL
			e.durability -= 1
			_shaft.explode(best_cell, _bomb_radius, roundi(e.damage * _bomb_mult), e.damage, combo_mult(e))
		else:
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
	if _shaft.hit_block(cell, damage, crit, e.damage, 0, combo_mult(e)) and _rng.randf() < _chain_chance:
		var next := _shaft.random_adjacent_block(cell, _rng)
		if next.x >= 0:
			_shaft.hit_block(next, e.damage, false, e.damage)


## Glimmer Grotto: a prism may split the ember. The child copies its damage, takes half of its
## remaining durability (rounded up), flies on the mirrored path, and costs no supply.
func _try_split(e: Ember, cell: Vector2i) -> void:
	if e.split_cells.has(cell) or active.size() >= _cap or _rng.randf() >= _prism_chance:
		return
	e.split_cells.append(cell)
	var child: Ember = _pool.pop_back() if not _pool.is_empty() else Ember.new()
	child.pos = e.pos
	child.prev = e.pos
	child.vel = Vector2(-e.vel.x, e.vel.y)
	child.damage = e.damage
	child.max_durability = e.max_durability
	child.durability = ceili(e.durability * 0.5)
	child.stuck_time = 0.0
	child.hit_cooldown = 0.0
	child.phasing = false
	child.split_cells = e.split_cells.duplicate()
	child.water_drain = 0.0
	child.steam_timer = 0.0
	child.combo = e.combo
	active.append(child)
	Events.prism_split.emit(e.pos)
	AudioManager.play("prism_split")


## Drip Caverns: water drains durability over time (fractions carry over) and hisses steam.
func _soak(e: Ember, dt: float) -> void:
	e.water_drain += _water_drain * dt
	if e.water_drain >= 1.0:
		var whole := floori(e.water_drain)
		e.durability -= whole
		e.water_drain -= whole
	e.steam_timer -= dt
	if e.steam_timer <= 0.0:
		e.steam_timer = _steam_interval
		Events.ember_steamed.emit(e.pos)
		AudioManager.play("water_hiss")


## Plinko ping: the peg lights up, the combo grows, and the chime climbs with it.
func _peg_hit(e: Ember, cell: Vector2i) -> void:
	e.combo += 1
	_shaft.light_peg(cell, e.combo)
	AudioManager.play("ember_bounce_peg", e.combo)
	if _combo_popup > 0 and e.combo % _combo_popup == 0:
		Events.combo_reached.emit(e.pos, combo_mult(e))
	if _peg_spark > 0.0:
		# Sparking pegs: the peg zaps a neighbouring block.
		var target := _shaft.random_adjacent_block(cell, _rng)
		if target.x >= 0:
			_shaft.hit_block(target, roundi(e.damage * _peg_spark), false, e.damage, 0, combo_mult(e))
			Events.peg_sparked.emit(_shaft.cell_center(cell), _shaft.cell_center(target))


## Ore sense: embers curve gently toward the nearest lode (or any block) within a few cells.
func _seek(e: Ember, delta: float) -> void:
	e.seek_timer -= delta
	if e.seek_timer <= 0.0:
		e.seek_timer = _seek_retarget
		e.has_target = false
		var cc := Vector2i(floori(e.pos.x / _shaft.cell_px), floori(e.pos.y / _shaft.cell_px))
		var best := INF
		for dy in range(-_seek_radius, _seek_radius + 1):
			for dx in range(-_seek_radius, _seek_radius + 1):
				var cell := cc + Vector2i(dx, dy)
				var score := float(dx * dx + dy * dy)
				if _shaft.is_lode(cell):
					score -= 100.0
				elif _shaft.kind_at(cell.x, cell.y) != Shaft.Kind.BLOCK:
					continue
				if score < best:
					best = score
					e.seek_target = _shaft.cell_center(cell)
					e.has_target = true
	if e.has_target:
		e.vel += (e.seek_target - e.pos).normalized() * _seek_strength * delta


func combo_mult(e: Ember) -> float:
	return minf(1.0 + e.combo * _combo_step, _combo_max)


## Boss hits work like block hits: ember damage (crits too), 1 durability.
func _hit_boss(e: Ember) -> void:
	var crit := _rng.randf() < _crit_chance
	e.durability -= 1
	e.stuck_time = 0.0
	_shaft.hit_boss(e.damage * (_crit_mult if crit else 1), crit)


func _burn_out(i: int, can_echo: bool = false) -> void:
	var e := active[i]
	active[i] = active[active.size() - 1]
	active.pop_back()
	_pool.append(e)
	# Afterglow: a burned-out ember may leave a smaller echo that keeps going.
	if can_echo and not e.is_echo and _echo_chance > 0.0 and _rng.randf() < _echo_chance and active.size() < _cap:
		var echo := _spawn(e.pos, Vector2.from_angle(_rng.randf_range(-PI, 0.0)) * _max_speed * 0.4)
		echo.damage = e.damage
		echo.max_durability = maxi(1, ceili(e.max_durability * _echo_frac))
		echo.durability = echo.max_durability
		echo.combo = e.combo
		echo.is_echo = true
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
		if e.kind == EmberKind.BOMB:
			c = Color(1.0, 0.45, 0.35, c.a)
		elif e.is_echo:
			c = Color(0.8, 0.85, 1.0, c.a)
		if e.kind == EmberKind.NOVA and _core_tex:
			var size_v := _core_tex.get_size() * _nova_scale
			draw_texture_rect(_core_tex, Rect2((p - size_v * 0.5).round(), size_v), false, c)
		elif _core_tex:
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
		if e.kind == EmberKind.NOVA:
			var size_v := _glow_tex.get_size() * _nova_scale
			_glow.draw_texture_rect(_glow_tex, Rect2((p - size_v * 0.5).round(), size_v), false, Color(1, 1, 1, a))
		else:
			_glow.draw_texture(_glow_tex, (p - half).round(), Color(1, 0.55, 0.45, a) if e.kind == EmberKind.BOMB else Color(1, 1, 1, a))
