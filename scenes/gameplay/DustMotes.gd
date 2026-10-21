class_name DustMotes
extends Node2D
## Slow glowing dust drifting through the cave air, brighter near the keeper's lantern.

var _camera: CameraRig
var _shaft: Shaft
var _motes: Array[Vector3] = []  ## x, y (relative to the view), phase
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0


func setup(camera: CameraRig, shaft: Shaft) -> void:
	_camera = camera
	_shaft = shaft
	_rng.randomize()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	for _i in DataDB.integer("visuals.dust_motes"):
		_motes.append(Vector3(_rng.randf_range(0, shaft.width_px), _rng.randf_range(0, camera.view_size.y), _rng.randf() * TAU))


func _process(delta: float) -> void:
	_time += delta
	for i in _motes.size():
		var m := _motes[i]
		m.y -= delta * 4.0
		m.x += sin(_time * 0.6 + m.z) * delta * 3.0
		if m.y < 0.0:
			m = Vector3(_rng.randf_range(0, _shaft.width_px), _camera.view_size.y, _rng.randf() * TAU)
		_motes[i] = m
	queue_redraw()


func _draw() -> void:
	if _camera == null:
		return
	var view_top := -get_viewport().get_canvas_transform().origin.y
	var lamp := Vector2(_shaft.width_px * 0.5, view_top + 40.0)
	for m in _motes:
		var p := Vector2(m.x, view_top + m.y)
		var near := clampf(1.0 - p.distance_to(lamp) / 160.0, 0.0, 1.0)
		var a := (0.12 + 0.5 * near) * (0.6 + 0.4 * sin(_time * 1.5 + m.z))
		draw_rect(Rect2(p.round(), Vector2.ONE), Color(1.0, 0.85, 0.6, a))
