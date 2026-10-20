extends Node
## --bench: keeps 300 embers and 2,000 pickups alive in a gameplay day, measures frame rate with
## vsync off, prints the result and quits. Run windowed (not headless) for meaningful numbers.

const GAMEPLAY_SCENE := "res://scenes/gameplay/Gameplay.tscn"
const WARMUP_S := 1.5

var _elapsed: float = 0.0
var _frames: int = 0
var _measure_s: float = 0.0
var _worst_ms: float = 0.0
var _started: bool = false
var _slow_frames: int = 0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	GameState.reset_to_new_game()
	Stats.recompute()
	get_tree().change_scene_to_file.call_deferred(GAMEPLAY_SCENE)


func _physics_process(_delta: float) -> void:
	var gp := get_tree().get_first_node_in_group("gameplay")
	if gp == null:
		return
	_started = true
	gp.embers.set_supply(999)
	var want_embers := DataDB.integer("debug.bench_embers") - int(gp.embers.active.size())
	if want_embers > 0:
		gp.debug_spawn_embers(want_embers)
	var want_pickups := DataDB.integer("debug.bench_pickups") - int(gp.pickups.active.size())
	if want_pickups > 0:
		gp.debug_spawn_pickups(want_pickups)


func _process(delta: float) -> void:
	if not _started:
		return
	_elapsed += delta
	if _elapsed < WARMUP_S:
		return
	_frames += 1
	_measure_s += delta
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	if delta > 1.0 / 60.0:
		_slow_frames += 1
	if _measure_s >= DataDB.num("debug.bench_seconds"):
		var gp := get_tree().get_first_node_in_group("gameplay")
		print("BENCH avg_fps=%.1f worst_frame_ms=%.1f embers=%d pickups=%d physics_ms=%.2f process_ms=%.2f draw_calls=%d" % [
			_frames / _measure_s, _worst_ms, gp.embers.active.size(), gp.pickups.active.size(),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		print("BENCH frames_slower_than_60fps=%.1f%%" % [100.0 * _slow_frames / _frames])
		get_tree().quit()
