class_name Glowmoth
extends Node2D
## A glowing moth that flutters across the view now and then. Hit it with an ember for a free
## ember and a burst of the best ore at this depth (Peggle's free-ball bucket, but alive).

const TEXTURE := "res://art/fx/glowmoth.png"

var _shaft: Shaft
var _camera: CameraRig
var _embers: EmberManager
var _pickups: PickupManager
var _rng := RandomNumberGenerator.new()
var _tex: Texture2D
var _glow: Texture2D
var _active: bool = false
var _wait: float = 0.0
var _t: float = 0.0
var _dir: float = 1.0
var _row_frac: float = 0.5
var _cfg: Dictionary


func setup(shaft: Shaft, camera: CameraRig, embers: EmberManager, pickups: PickupManager) -> void:
	_shaft = shaft
	_camera = camera
	_embers = embers
	_pickups = pickups
	_rng.randomize()
	_tex = DataDB.texture(TEXTURE)
	_glow = DataDB.texture("res://art/embers/ember_glow.png")
	_cfg = DataDB.val("glowmoth")
	_wait = _rng.randf_range(float(_cfg["first_delay_min_s"]), float(_cfg["first_delay_max_s"]))
	visible = false


func _physics_process(delta: float) -> void:
	if not _active:
		# Only while the day is running.
		if _embers.supply <= 0 and _embers.active.is_empty():
			return
		_wait -= delta
		if _wait <= 0.0:
			_spawn()
		return
	_t += delta
	var duration := float(_cfg["cross_s"])
	if _t >= duration:
		_finish()
		return
	_place()
	var reach := float(_cfg["hit_radius_px"])
	for e in _embers.active:
		if e.pos.distance_squared_to(position) <= reach * reach:
			_caught()
			return


func _spawn() -> void:
	_active = true
	visible = true
	_t = 0.0
	_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	_row_frac = _rng.randf_range(float(_cfg["min_height_frac"]), float(_cfg["max_height_frac"]))
	_place()
	reset_physics_interpolation()


func _place() -> void:
	var u := _t / float(_cfg["cross_s"])
	if _dir < 0.0:
		u = 1.0 - u
	var x := lerpf(-8.0, _shaft.width_px + 8.0, u)
	var y := _camera.top + _camera.view_size.y * _row_frac + sin(_t * float(_cfg["flutter_speed"])) * float(_cfg["flutter_px"])
	position = Vector2(x, y)


func _caught() -> void:
	Events.moth_caught.emit(position)
	AudioManager.play("moth_catch")
	_embers.set_supply(_embers.supply + int(_cfg["bonus_embers"]))
	var ore := _best_ore_here()
	if ore >= 0:
		_pickups.spawn(ore, position, int(_cfg["bonus_ore"]))
	_finish()


func _finish() -> void:
	_active = false
	visible = false
	_wait = _rng.randf_range(float(_cfg["interval_min_s"]), float(_cfg["interval_max_s"]))


## The ore index of the highest-tier ore whose band covers the current depth.
func _best_ore_here() -> int:
	var row := floori(position.y / _shaft.cell_px)
	var best := -1
	for band: Variant in _shaft.data["ore_bands"]:
		var b: Dictionary = band
		if row >= float(b["from_m"]) and row < float(b["to_m"]):
			best = maxi(best, int(DataDB.ore_index.get(str(b["ore_id"]), -1)))
	return best


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not _active:
		return
	var flap := absf(sin(_t * 14.0))
	if _glow:
		draw_texture(_glow, -_glow.get_size() * 0.5, Color(0.7, 1.0, 0.85, 0.9))
	if _tex:
		var s := _tex.get_size()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(_dir * (0.6 + 0.4 * flap), 1.0))
		draw_texture(_tex, -s * 0.5)
		draw_set_transform(Vector2.ZERO)
