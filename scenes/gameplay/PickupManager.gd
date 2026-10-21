class_name PickupManager
extends Node2D
## Ore pickups: pop out of broken blocks, drift gently, get vacuumed by the cursor magnet, and
## auto-bank at a reduced rate when they scroll off the top of the screen.

signal all_collected

enum State { DRIFT, MAGNET, TO_HUD }


class Pickup:
	var pos := Vector2.ZERO
	var prev := Vector2.ZERO
	var vel := Vector2.ZERO
	var ore: int = 0
	var count: int = 1
	var state: int = 0
	var age: float = 0.0
	var fly_from := Vector2.ZERO
	var fly_t: float = 0.0


var active: Array[Pickup] = []

var _pool: Array[Pickup] = []
var _shaft: Shaft
var _camera: CameraRig
var _input: PlayerInput
var _hud: HUD
var _rng := RandomNumberGenerator.new()
var _textures: Array[Texture2D] = []
var _collecting_all: bool = false

var _speed_min: float
var _speed_max: float
var _gravity: float
var _damping: float
var _max_fall: float
var _magnet_speed: float
var _magnet_accel: float
var _collect_dist: float
var _offscreen_margin: float
var _merge_threshold: int
var _merge_radius: float
var _merge_scan: int
var _max_spawn: int
var _bob_amp: float
var _bob_speed: float
var _fly_s: float
var _stagger_s: float


func setup(shaft: Shaft, camera: CameraRig, input: PlayerInput, hud: HUD) -> void:
	_shaft = shaft
	_camera = camera
	_input = input
	_hud = hud
	_rng.randomize()
	for ore in DataDB.ores:
		_textures.append(DataDB.texture(str(ore["pickup_texture_path"])))
	_speed_min = DataDB.num("pickups.spawn_speed_min")
	_speed_max = DataDB.num("pickups.spawn_speed_max")
	_gravity = DataDB.num("pickups.gravity")
	_damping = DataDB.num("pickups.damping")
	_max_fall = DataDB.num("pickups.max_fall_speed")
	_magnet_speed = DataDB.num("pickups.magnet_speed")
	_magnet_accel = DataDB.num("pickups.magnet_accel")
	_collect_dist = DataDB.num("pickups.collect_distance_px")
	_offscreen_margin = DataDB.num("pickups.offscreen_margin_px")
	_merge_threshold = DataDB.integer("pickups.merge_threshold")
	_merge_radius = DataDB.num("pickups.merge_radius_px")
	_merge_scan = DataDB.integer("pickups.merge_scan_recent")
	_max_spawn = DataDB.integer("pickups.max_spawned_per_block")
	_bob_amp = DataDB.num("pickups.bob_amplitude_px")
	_bob_speed = DataDB.num("pickups.bob_speed")
	_fly_s = DataDB.num("pickups.day_end_fly_s")
	_stagger_s = DataDB.num("pickups.day_end_stagger_s")
	Events.block_broken.connect(_on_block_broken)
	Events.pulse_fired.connect(_on_pulse_fired)


func spawn(ore_index: int, at: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	var pieces := mini(amount, _max_spawn)
	for k in pieces:
		# The last piece carries whatever is left over.
		var count := 1 if k < pieces - 1 else amount - (pieces - 1)
		if active.size() >= _merge_threshold and _merge_into_neighbour(ore_index, at, count):
			continue
		var p: Pickup = _pool.pop_back() if not _pool.is_empty() else Pickup.new()
		p.pos = at
		p.prev = at
		p.vel = Vector2.from_angle(_rng.randf_range(-PI, 0.0)) * _rng.randf_range(_speed_min, _speed_max)
		p.ore = ore_index
		p.count = count
		p.state = State.DRIFT
		p.age = _rng.randf() * TAU
		active.append(p)


## Sends every pickup to the HUD ore ticker at full value. Emits all_collected when done.
func collect_all_to_hud() -> void:
	_collecting_all = true
	for p in active:
		p.state = State.TO_HUD
		p.fly_from = p.pos
		p.fly_t = -_rng.randf() * _stagger_s
	if active.is_empty():
		_finish_collect_all.call_deferred()


func _finish_collect_all() -> void:
	if _collecting_all:
		_collecting_all = false
		all_collected.emit()


## Lantern Pulse: every drifting pickup on screen flies to the cursor.
func _on_pulse_fired(_at: Vector2) -> void:
	for p in active:
		if p.state == State.DRIFT:
			p.state = State.MAGNET


func _on_block_broken(_cell: Vector2i, ore_id: String, world_pos: Vector2, yield_mult: float) -> void:
	spawn(int(DataDB.ore_index[ore_id]), world_pos, roundi(Stats.get_f("ore_yield_" + ore_id) * yield_mult))


func _merge_into_neighbour(ore_index: int, at: Vector2, count: int) -> bool:
	# Only the most recent pickups are checked: they're the ones most likely to be nearby,
	# and a full scan of 2,000 per spawn costs too much.
	var r2 := _merge_radius * _merge_radius
	for k in range(active.size() - 1, maxi(active.size() - 1 - _merge_scan, -1), -1):
		var p := active[k]
		if p.ore == ore_index and p.state == State.DRIFT and p.pos.distance_squared_to(at) <= r2:
			p.count += count
			return true
	return false


func _physics_process(delta: float) -> void:
	var cursor := _input.cursor_world()
	var auto := Stats.get_b("auto_collect")
	var radius := Stats.get_f("magnet_radius")
	var bank_rate := 1.0 if auto else Stats.get_f("offscreen_bank_rate")
	var offscreen_y := _camera.top - _offscreen_margin
	var lowest := minf(_camera.bottom(), _shaft.floor_y) - _offscreen_margin
	var hud_target := get_viewport().get_canvas_transform().affine_inverse() * _hud.ticker_screen_pos()
	var damp := exp(-_damping * delta)
	var i := active.size() - 1
	while i >= 0:
		var p := active[i]
		p.prev = p.pos
		p.age += delta
		match p.state:
			State.DRIFT:
				p.vel.y = minf(p.vel.y + _gravity * delta, _max_fall)
				p.vel *= damp
				p.pos += p.vel * delta
				p.pos.x = clampf(p.pos.x, 2.0, _shaft.width_px - 2.0)
				p.pos.y = minf(p.pos.y, lowest)
				if auto or p.pos.distance_squared_to(cursor) <= radius * radius:
					p.state = State.MAGNET
			State.MAGNET:
				var to_cursor := cursor - p.pos
				p.vel = p.vel.move_toward(to_cursor.normalized() * _magnet_speed, _magnet_accel * delta)
				p.pos += p.vel * delta
				if p.pos.distance_squared_to(cursor) <= _collect_dist * _collect_dist:
					_collect(i, 1.0, "magnet")
					i -= 1
					continue
			State.TO_HUD:
				p.fly_t += delta / _fly_s
				var t := clampf(p.fly_t, 0.0, 1.0)
				p.pos = p.fly_from.lerp(hud_target, t * t)
				if p.fly_t >= 1.0:
					_collect(i, 1.0, "day_end")
					i -= 1
					continue
		if p.state != State.TO_HUD and p.pos.y < offscreen_y:
			_collect(i, bank_rate, "offscreen")
		i -= 1
	if _collecting_all and active.is_empty():
		_finish_collect_all()


func _collect(i: int, rate: float, source: String) -> void:
	var p := active[i]
	active[i] = active[active.size() - 1]
	active.pop_back()
	_pool.append(p)
	GameState.add_ore(_shaft.ore_ids[p.ore], p.count * rate, source)
	if source == "magnet":
		AudioManager.play("ore_pickup")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	# Bucket by ore first so each texture is drawn in one run (keeps the renderer batching).
	var buckets: Array[Array] = []
	for _i in _textures.size():
		buckets.append([])
	var f := Engine.get_physics_interpolation_fraction()
	for p in active:
		var pp := p.prev.lerp(p.pos, f)
		if p.state == State.DRIFT:
			pp.y += sin(p.age * _bob_speed) * _bob_amp
		buckets[p.ore].append(pp)
	for ore_i in buckets.size():
		var tex := _textures[ore_i]
		var half := tex.get_size() * 0.5 if tex else Vector2(3, 3)
		for pp: Vector2 in buckets[ore_i]:
			if tex:
				draw_texture(tex, (pp - half).round())
			else:
				draw_rect(Rect2(pp - half, half * 2.0), _shaft.ore_colors[ore_i])
