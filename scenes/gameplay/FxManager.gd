class_name FxManager
extends Node2D
## Tiny pooled particle system for block chips, crit sparks and burnout puffs.


class Particle:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life: float = 0.0
	var max_life: float = 1.0
	var color := Color.WHITE


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


func burst(at: Vector2, color: Color, count: int, speed: float, life: float) -> void:
	for _i in count:
		if _active.size() >= _max:
			return
		var p: Particle = _pool.pop_back() if not _pool.is_empty() else Particle.new()
		p.pos = at
		p.vel = Vector2.from_angle(_rng.randf() * TAU) * speed * _rng.randf_range(0.4, 1.0)
		p.max_life = life * _rng.randf_range(0.7, 1.0)
		p.life = p.max_life
		p.color = color
		_active.append(p)


func _on_block_broken(_cell: Vector2i, ore_id: String, world_pos: Vector2) -> void:
	burst(world_pos, DataDB.ore_color(ore_id), _chip_count, _chip_speed, _chip_life)


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


func _process(delta: float) -> void:
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
		draw_rect(Rect2(p.pos.round(), Vector2.ONE), c)
