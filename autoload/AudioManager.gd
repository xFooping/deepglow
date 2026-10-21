extends Node
## Plays sounds by event name, e.g. AudioManager.play("ore_pickup"), so files can be swapped freely.
## data/audio.json maps each event to its bus, volume and one or more files (a random one plays).
## Music and the cave ambience loop on their own players for the whole session.

const AUDIO_JSON := "res://data/audio.json"
const BUSES: Array[String] = ["Music", "SFX", "UI"]

var _events: Dictionary = {}    ## event -> {bus, volume_db, streams: Array[AudioStream]}
var _voices: Dictionary = {}    ## event -> Array of AudioStreamPlayer
var _pickup_streak: int = 0
var _last_pickup_ms: int = 0
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer


func _ready() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
	_load_events()
	if not DisplayServer.get_name() == "headless":
		_music = _loop_player("music")
		_ambience = _loop_player("ambience")


func register(event: String, stream: AudioStream, bus: String = "SFX") -> void:
	_events[event] = {"bus": bus, "volume_db": 0.0, "streams": [stream]}


## pitch_step raises the pitch a little per step (peg combos climb the scale).
func play(event: String, pitch_step: int = 0) -> void:
	var entry: Dictionary = _events.get(event, {})
	var streams: Array = entry.get("streams", [])
	if streams.is_empty():
		return
	var pitch := 1.0
	if event == "ore_pickup":
		pitch = _pickup_pitch()
	elif pitch_step > 0:
		pitch = minf(1.0 + DataDB.num("audio.pickup_pitch_step") * pitch_step, DataDB.num("audio.pickup_pitch_max"))
	var jitter := DataDB.num("audio.pitch_jitter")
	var player := _voice_for(event)
	player.stream = streams[randi() % streams.size()]
	player.bus = str(entry.get("bus", "SFX"))
	player.volume_db = float(entry.get("volume_db", 0.0))
	player.pitch_scale = pitch * randf_range(1.0 - jitter, 1.0 + jitter)
	player.play()


func _load_events() -> void:
	if not FileAccess.file_exists(AUDIO_JSON):
		push_warning("AudioManager: %s missing, all sounds are silent" % AUDIO_JSON)
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(AUDIO_JSON))
	if not data is Dictionary:
		push_error("AudioManager: %s is not a JSON object" % AUDIO_JSON)
		return
	for event: Variant in data:
		var e: Dictionary = data[event]
		var streams: Array = []
		for path: Variant in e.get("files", []):
			if ResourceLoader.exists(str(path)):
				streams.append(load(str(path)))
			else:
				push_warning("AudioManager: missing sound %s" % path)
		_events[str(event)] = {"bus": str(e.get("bus", "SFX")), "volume_db": float(e.get("volume_db", 0.0)), "streams": streams}


func _loop_player(event: String) -> AudioStreamPlayer:
	var entry: Dictionary = _events.get(event, {})
	var streams: Array = entry.get("streams", [])
	if streams.is_empty():
		return null
	var stream: AudioStream = streams[0]
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = str(entry.get("bus", "Music"))
	p.volume_db = float(entry.get("volume_db", 0.0))
	add_child(p)
	p.play()
	return p


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
