class_name FxManager
extends Node2D
## Tiny pooled particle system for block chips, crit sparks and burnout puffs, plus short-lived
## beams (sparking pegs, flares) and rings (bombs, lantern pulse).


class Particle:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life: float = 0.0
	var max_life: float = 1.0
	var color := Color.WHITE
	var size: float = 1.0


var _active: Array[Particle] = []
var _pool: Array[Particle] = []
var _rng := RandomNumberGenerator.new()
var _max: int
var _gravity: float
var _chip_count: int
var _chip_speed: float
var _chip_life: float
var _spark_count: int
var _crit_count: int
var _spark_speed: float
var _spark_life: float
var _lines: Array[Dictionary] = []  ## {a, b, life, max, color, width}
var _rings: Array[Dictionary] = []  ## {pos, radius, life, max, color}


func _ready() -> void:
	_rng.randomize()
	_max = DataDB.integer("fx.max_particles")
	_gravity = DataDB.num("fx.particle_gravity")
	_chip_count = DataDB.integer("fx.chip_count")
	_chip_speed = DataDB.num("fx.chip_speed")
	_chip_life = DataDB.num("fx.chip_life_s")
	_spark_count = DataDB.integer("fx.spark_count")
	_crit_count = DataDB.integer("fx.crit_spark_count")
	_spark_speed = DataDB.num("fx.spark_speed")
	_spark_life = DataDB.num("fx.spark_life_s")
	Events.block_broken.connect(_on_block_broken)
	Events.block_hit.connect(_on_block_hit)
	Events.ember_burned_out.connect(_on_ember_burned_out)
	Events.boss_shattered.connect(_on_boss_shattered)
	Events.kindling_popped.connect(_on_kindling_popped)
	Events.prism_split.connect(_on_prism_split)
	Events.ember_steamed.connect(_on_ember_steamed)
	Events.bomb_exploded.connect(_on_bomb_exploded)
	Events.peg_sparked.connect(_on_peg_sparked)
	Events.flare_fired.connect(_on_flare_fired)
	Events.pulse_fired.connect(_on_pulse_fired)
	Events.lode_broken.connect(_on_lode_broken)
	Events.jar_broken.connect(_on_jar_broken)
	Events.moth_caught.connect(_on_moth_caught)


func burst(at: Vector2, color: Color, count: int, speed: float, life: float, size: float = 1.0) -> void:
	for _i in count:
		if _active.size() >= _max:
			return
		var p: Particle = _pool.pop_back() if not _pool.is_empty() else Particle.new()
		p.pos = at
		p.vel = Vector2.from_angle(_rng.randf() * TAU) * speed * _rng.randf_range(0.4, 1.0)
		p.max_life = life * _rng.randf_range(0.7, 1.0)
		p.life = p.max_life
		p.color = color
		p.size = size
		_active.append(p)


func _on_block_broken(_cell: Vector2i, ore_id: String, world_pos: Vector2, yield_mult: float) -> void:
	var oc := DataDB.ore_color(ore_id)
	burst(world_pos, oc, _chip_count, _chip_speed, _chip_life)
	burst(world_pos, oc.darkened(0.2), DataDB.integer("fx.debris_count"), DataDB.num("fx.debris_speed"), DataDB.num("fx.debris_life_s"), 2.0)
	if yield_mult > 1.0:
		burst(world_pos, Color(0.9, 1.0, 1.0), _spark_count, _spark_speed, _spark_life)


## Warm pops, not explosions: an orange burst that grows a little with the chain.
func _on_kindling_popped(world_pos: Vector2, chain: int) -> void:
	burst(world_pos, Color(1.0, 0.6, 0.25), _chip_count + mini(chain, 6), _chip_speed, _chip_life)


func _on_prism_split(world_pos: Vector2) -> void:
	burst(world_pos, Color(1.0, 0.85, 1.0), _spark_count, _spark_speed, _spark_life)


func _on_ember_steamed(world_pos: Vector2) -> void:
	burst(world_pos + Vector2(0, -3), Color(0.85, 0.92, 1.0, 0.7), 2, _spark_speed * 0.5, _spark_life)


func _on_block_hit(_cell: Vector2i, _ore_id: String, _damage: int, crit: bool, world_pos: Vector2) -> void:
	if crit:
		burst(world_pos, Color(1.0, 0.85, 0.3), _crit_count, _spark_speed, _spark_life)


func _on_ember_burned_out(world_pos: Vector2) -> void:
	burst(world_pos, Color(1.0, 0.6, 0.25), _spark_count, _spark_speed, _spark_life)


## Glowing shards: a big, slow, gold-tinted burst in the crystal's color.
func _on_boss_shattered(world_pos: Vector2, color: Color) -> void:
	var count := DataDB.integer("boss.shatter_particles")
	burst(world_pos, color.lightened(0.3), count, DataDB.num("boss.shatter_speed"), DataDB.num("boss.shatter_life_s"))
	burst(world_pos, Color(1.0, 0.85, 0.5), floori(count * 0.5), DataDB.num("boss.shatter_speed") * 0.6, DataDB.num("boss.shatter_life_s"))


func line(a: Vector2, b: Vector2, color: Color, width: float, life: float) -> void:
	_lines.append({"a": a, "b": b, "life": life, "max": life, "color": color, "width": width})


func ring(at: Vector2, radius: float, color: Color, life: float) -> void:
	_rings.append({"pos": at, "radius": radius, "life": life, "max": life, "color": color})


## A gold shower: the lode moment.
func _on_lode_broken(world_pos: Vector2) -> void:
	burst(world_pos, Color(1.0, 0.85, 0.35), DataDB.integer("fx.lode_sparkles"), _chip_speed * 1.6, _chip_life * 2.0, 2.0)
	burst(world_pos, Color(1.0, 1.0, 0.85), DataDB.integer("fx.lode_sparkles"), _chip_speed, _chip_life * 1.5)
	ring(world_pos, 28.0, Color(1.0, 0.85, 0.4), 0.35)


func _on_jar_broken(world_pos: Vector2, _embers: int) -> void:
	burst(world_pos, Color(1.0, 0.6, 0.25), DataDB.integer("fx.lode_sparkles"), _chip_speed * 1.3, _chip_life * 1.6, 2.0)
	ring(world_pos, 24.0, Color(1.0, 0.7, 0.4), 0.3)


func _on_moth_caught(world_pos: Vector2) -> void:
	burst(world_pos, Color(0.7, 1.0, 0.85), DataDB.integer("fx.lode_sparkles"), _chip_speed * 1.4, _chip_life * 1.8, 2.0)
	ring(world_pos, 32.0, Color(0.7, 1.0, 0.85), 0.4)


func _on_bomb_exploded(world_pos: Vector2, radius: int) -> void:
	burst(world_pos, Color(1.0, 0.55, 0.25), _chip_count * 3, _chip_speed * 1.5, _chip_life * 1.4)
	ring(world_pos, (radius + 0.5) * 16.0, Color(1.0, 0.7, 0.35), 0.3)


func _on_peg_sparked(from_pos: Vector2, to_pos: Vector2) -> void:
	line(from_pos, to_pos, Color(0.7, 0.95, 1.0), 1.0, 0.15)


func _on_flare_fired(from_pos: Vector2, to_pos: Vector2) -> void:
	line(from_pos, to_pos, Color(1.0, 0.85, 0.5), 3.0, DataDB.num("abilities.flare_beam_s"))


func _on_pulse_fired(world_pos: Vector2) -> void:
	ring(world_pos, 120.0, Color(1.0, 0.9, 0.6), DataDB.num("abilities.pulse_ring_s"))


func _process(delta: float) -> void:
	for list: Array[Dictionary] in [_lines, _rings]:
		for k in range(list.size() - 1, -1, -1):
			list[k]["life"] = float(list[k]["life"]) - delta
			if float(list[k]["life"]) <= 0.0:
				list.remove_at(k)
	var i := _active.size() - 1
	while i >= 0:
		var p := _active[i]
		p.life -= delta
		if p.life <= 0.0:
			_active[i] = _active[_active.size() - 1]
			_active.pop_back()
			_pool.append(p)
		else:
			p.vel.y += _gravity * delta
			p.pos += p.vel * delta
		i -= 1
	queue_redraw()


func _draw() -> void:
	for p in _active:
		var c := p.color
		c.a = p.life / p.max_life
		draw_rect(Rect2(p.pos.round(), Vector2(p.size, p.size)), c)
	for l in _lines:
		var lc: Color = l["color"]
		lc.a = float(l["life"]) / float(l["max"])
		draw_line(l["a"], l["b"], lc, float(l["width"]))
	for r in _rings:
		var t := 1.0 - float(r["life"]) / float(r["max"])
		var rc: Color = r["color"]
		rc.a = 1.0 - t
		draw_arc(r["pos"], float(r["radius"]) * (0.3 + 0.7 * t), 0.0, TAU, 32, rc, 1.0)
