class_name LanternKeeper
extends Node2D
## The launcher critter. Sits at the top-center of the view, turns its lantern toward the cursor,
## shows a short aim guide and fires embers (click, or hold to auto-fire).

const BODY_TEXTURE := "res://art/keeper/keeper.png"
const LANTERN_TEXTURE := "res://art/keeper/lantern.png"

var enabled: bool = true

var _shaft: Shaft
var _camera: CameraRig
var _embers: EmberManager
var _input: PlayerInput
var _cooldown_left: float = 0.0
var _cooldown_total: float = 1.0
var _armed: bool = false  ## Needs one release first, so the click that started the day doesn't fire.
var _aim_dir := Vector2.DOWN
var _guide := PackedVector2Array()
var _offset: float
var _min_angle: float
var _max_angle: float

@onready var _body: Sprite2D = $Body
@onready var _lantern: Sprite2D = $Lantern


func setup(shaft: Shaft, camera: CameraRig, embers: EmberManager, input: PlayerInput) -> void:
	_shaft = shaft
	_camera = camera
	_embers = embers
	_input = input
	_offset = DataDB.num("camera.keeper_offset_px")
	_min_angle = deg_to_rad(DataDB.num("aim.min_angle_deg"))
	_max_angle = deg_to_rad(DataDB.num("aim.max_angle_deg"))
	_body.texture = DataDB.texture(BODY_TEXTURE)
	_lantern.texture = DataDB.texture(LANTERN_TEXTURE)
	_place()
	reset_physics_interpolation()


func launch_origin() -> Vector2:
	return _lantern.global_position


func cooldown_ready() -> bool:
	return _cooldown_left <= 0.0


func _place() -> void:
	global_position = Vector2(_shaft.width_px * 0.5, _camera.top + _offset)


func _physics_process(delta: float) -> void:
	_place()
	var origin := launch_origin()
	_aim_dir = _clamp_aim(_input.cursor_world() - origin)
	_lantern.rotation = _aim_dir.angle() - PI * 0.5
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if not _armed:
		_armed = not _input.fire_held()
	elif enabled and _input.fire_held() and _cooldown_left <= 0.0:
		if _embers.launch(origin, _aim_dir * Stats.get_f("launch_speed")):
			_cooldown_total = Stats.get_f("fire_cooldown")
			_cooldown_left = _cooldown_total
			AudioManager.play("ember_launch")
	_rebuild_guide(origin)
	queue_redraw()


## Peggle-style: aim from the keeper toward the cursor, clamped to the lower half.
func _clamp_aim(v: Vector2) -> Vector2:
	if v.length_squared() < 0.01:
		return Vector2.DOWN
	var a := v.angle()  # y points down, so positive angles are below the horizon
	if a < 0.0:
		a = _min_angle if v.x >= 0.0 else _max_angle
	return Vector2.from_angle(clampf(a, _min_angle, _max_angle))


## Fixed-length dotted guide using the real ember gravity, ending at the first collision.
func _rebuild_guide(origin: Vector2) -> void:
	_guide.clear()
	if not enabled or _embers.supply <= 0:
		return
	var length := DataDB.num("aim.aim_guide_length_px")
	var spacing := DataDB.num("aim.aim_guide_dot_spacing_px")
	var step := DataDB.num("aim.aim_guide_sim_step_s")
	var gravity := DataDB.num("physics.gravity")
	var ignore_blocks := _embers.overlaps_solid(origin) and not _embers.overlaps_solid(origin, true)
	var p := origin
	var v := _aim_dir * Stats.get_f("launch_speed")
	var travelled := 0.0
	var next_dot := spacing
	while travelled < length:
		v.y += gravity * step
		var np := p + v * step
		travelled += np.distance_to(p)
		p = np
		if ignore_blocks and not _embers.overlaps_solid(p):
			ignore_blocks = false
		if _embers.overlaps_solid(p, ignore_blocks):
			break
		if travelled >= next_dot:
			_guide.append(p - global_position)
			next_dot += spacing


func _draw() -> void:
	var lantern_pos := _lantern.position
	draw_line(Vector2(0, 2), lantern_pos, Color(0.55, 0.42, 0.3), 1.0)
	for dot in _guide:
		draw_rect(Rect2(dot.round(), Vector2.ONE), Color(1.0, 0.92, 0.75, 0.85))
	if _cooldown_left > 0.0 and _cooldown_total > 0.0:
		var frac := 1.0 - _cooldown_left / _cooldown_total
		draw_arc(lantern_pos, 6.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 20, Color(1.0, 0.8, 0.45, 0.6), 1.0)
