class_name CameraRig
extends Camera2D
## Follows the deepest active ember with smoothing. Moves down only; never scrolls back up during a day.

var top: float = 0.0  ## World y of the top edge of the view.
var view_size := Vector2.ZERO

var _max_top: float = 0.0
var _follow_fraction: float
var _follow_speed: float


func setup(shaft: Shaft, start_top: float) -> void:
	view_size = get_viewport_rect().size
	_follow_fraction = DataDB.num("camera.follow_screen_fraction")
	_follow_speed = DataDB.num("camera.follow_speed")
	_max_top = maxf(0.0, shaft.floor_y + DataDB.num("grid.floor_rows_shown") * shaft.cell_px - view_size.y)
	top = clampf(start_top, 0.0, _max_top)
	position = Vector2(shaft.width_px * 0.5, top + view_size.y * 0.5)
	make_current()
	reset_physics_interpolation()


## Call from _physics_process with the deepest active ember's y.
func follow(target_y: float, delta: float) -> void:
	var want := target_y - view_size.y * _follow_fraction
	if want > top:
		top = minf(lerpf(top, want, 1.0 - exp(-_follow_speed * delta)), _max_top)
		position.y = top + view_size.y * 0.5


## The one allowed camera bump (boss shatter): a quick drop and settle.
func bump(px: float, duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "offset:y", px, duration * 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "offset:y", 0.0, duration * 0.7).set_trans(Tween.TRANS_SINE)


func bottom() -> float:
	return top + view_size.y
