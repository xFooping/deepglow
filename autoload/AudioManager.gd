extends Node
## Plays sounds by event name, e.g. AudioManager.play("ore_pickup"), so files can be swapped freely.
## Phase 1 ships no audio files: every event is a silent placeholder until register() is given a stream.

const BUSES: Array[String] = ["Music", "SFX", "UI"]

var _streams: Dictionary = {}   ## event -> AudioStream
var _buses: Dictionary = {}     ## event -> bus name
var _voices: Dictionary = {}    ## event -> Array of AudioStreamPlayer
var _pickup_streak: int = 0
var _last_pickup_ms: int = 0


func _ready() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")


func register(event: String, stream: AudioStream, bus: String = "SFX") -> void:
	_streams[event] = stream
	_buses[event] = bus


func play(event: String) -> void:
	var pitch := 1.0
	if event == "ore_pickup":
		pitch = _pickup_pitch()
	var stream: AudioStream = _streams.get(event)
	if stream == null:
		return
	var jitter := DataDB.num("audio.pitch_jitter")
	var player := _voice_for(event)
	player.stream = stream
	player.bus = _buses.get(event, "SFX")
	player.pitch_scale = pitch * randf_range(1.0 - jitter, 1.0 + jitter)
	player.play()


## Rising chime when ore is collected in quick succession; resets after a short idle.
func _pickup_pitch() -> float:
	var now := Time.get_ticks_msec()
	if now - _last_pickup_ms > int(DataDB.num("audio.pickup_streak_reset_s") * 1000.0):
		_pickup_streak = 0
	_last_pickup_ms = now
	_pickup_streak += 1
	return minf(1.0 + DataDB.num("audio.pickup_pitch_step") * (_pickup_streak - 1), DataDB.num("audio.pickup_pitch_max"))


## Reuses a free player for this event, or steals the oldest one past the voice limit.
func _voice_for(event: String) -> AudioStreamPlayer:
	var voices: Array = _voices.get(event, [])
	for v: Variant in voices:
		var p: AudioStreamPlayer = v
		if not p.playing:
			return p
	if voices.size() < DataDB.integer("audio.max_voices_per_sound"):
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
		_voices[event] = voices
		return p
	var oldest: AudioStreamPlayer = voices.pop_front()
	voices.append(oldest)
	return oldest
