class_name Juice
extends Node
## Game feel: screen shake and hit-stop for the big moments (bombs, lodes, jars, glowmoths, combo
## milestones, crystal crits and the shatter). Shake respects the "Screen shake" setting; hit-stop
## is skipped in bot and benchmark runs so they stay deterministic.

var _camera: CameraRig
var _rng := RandomNumberGenerator.new()
var _shake: float = 0.0
var _shake_left: float = 0.0
var _shake_total: float = 0.0
var _hitstop_left: float = 0.0
var _hitstop_allowed: bool = true
var _cfg: Dictionary


func setup(camera: CameraRig) -> void:
	_camera = camera
	_rng.randomize()
	_cfg = DataDB.val("juice")
	var args := OS.get_cmdline_user_args()
	_hitstop_allowed = not (args.has("--autoplay") or args.has("--bench"))
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.bomb_exploded.connect(func(_p: Vector2, _r: int) -> void: kick("bomb"))
	Events.lode_broken.connect(func(_p: Vector2) -> void: kick("lode"))
	Events.jar_broken.connect(func(_p: Vector2, _n: int) -> void: kick("jar"))
	Events.moth_caught.connect(func(_p: Vector2) -> void: kick("moth"))
	Events.combo_reached.connect(_on_combo)
	Events.boss_hit.connect(_on_boss_hit)
	Events.boss_shattered.connect(func(_p: Vector2, _c: Color) -> void: kick("shatter"))


## Plays the shake/hit-stop preset named in balance.json "juice".
func kick(preset: String) -> void:
	var p: Dictionary = _cfg.get(preset, {})
	shake(float(p.get("shake_px", 0.0)), float(p.get("shake_s", 0.0)))
	hitstop(float(p.get("hitstop_s", 0.0)))


func shake(px: float, seconds: float) -> void:
	if px <= 0.0 or seconds <= 0.0 or not Settings.shake_enabled():
		return
	if px >= _shake * (_shake_left / maxf(_shake_total, 0.001)):
		_shake = px
		_shake_left = seconds
		_shake_total = seconds


func hitstop(seconds: float) -> void:
	if seconds <= 0.0 or not _hitstop_allowed:
		return
	_hitstop_left = maxf(_hitstop_left, seconds)
	Engine.time_scale = float(_cfg.get("hitstop_time_scale", 0.05))


func _on_combo(_pos: Vector2, mult: float) -> void:
	if mult >= float(_cfg.get("combo_kick_from_mult", 2.0)):
		kick("combo")


func _on_boss_hit(_shaft: int, _damage: int, _hp: int, _max: int, crit: bool) -> void:
	if crit:
		kick("boss_crit")


func _process(_delta: float) -> void:
	# Real time, so hit-stop doesn't stretch itself or the shake.
	var dt := minf(1.0 / 30.0, 1.0 / maxf(Engine.get_frames_per_second(), 1.0))
	if _hitstop_left > 0.0:
		_hitstop_left -= dt
		if _hitstop_left <= 0.0:
			Engine.time_scale = 1.0
	if _shake_left > 0.0 and _camera:
		_shake_left -= dt
		var k := maxf(_shake_left / _shake_total, 0.0)
		_camera.offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake * k
		if _shake_left <= 0.0:
			_camera.offset = Vector2.ZERO


func _exit_tree() -> void:
	Engine.time_scale = 1.0
