class_name TreeCanvas
extends Control
## The skill tree node web, drawn in one pass. Scroll wheel zooms toward the cursor; left or
## middle drag pans; a left click without dragging buys one level of the hovered node.

signal hovered_changed(upgrade_id: String)
signal purchase_requested(upgrade_id: String)

const LOCK_ICON := "res://art/ui/lock.png"

var zoom: float = 1.0
var origin := Vector2.ZERO  ## Screen position of tree coordinate (0, 0).
var hovered: String = ""

var _drag_button: int = 0
var _press_pos := Vector2.ZERO
var _dragging: bool = false
var _centered: bool = false
var _bounds := Rect2()
var _pops: Dictionary = {}   ## upgrade id -> seconds left
var _flows: Array[Dictionary] = []  ## {from: Vector2, to: Vector2, t: float}
var _node_px: float
var _zoom_min: float
var _zoom_max: float
var _zoom_step: float
var _drag_threshold: float
var _pop_s: float
var _flow_s: float


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_node_px = DataDB.num("ui.tree_node_px")
	_zoom_min = DataDB.num("ui.tree_zoom_min")
	_zoom_max = DataDB.num("ui.tree_zoom_max")
	_zoom_step = DataDB.num("ui.tree_zoom_step")
	_drag_threshold = DataDB.num("ui.tree_drag_threshold_px")
	_pop_s = DataDB.num("ui.tree_pop_s")
	_flow_s = DataDB.num("ui.tree_flow_s")
	var margin := DataDB.num("ui.tree_bounds_margin_px")
	var first := true
	for id: String in DataDB.upgrades:
		var p := _tree_pos(id)
		if first:
			_bounds = Rect2(p, Vector2.ZERO)
			first = false
		else:
			_bounds = _bounds.expand(p)
	_bounds = _bounds.grow(margin)
	resized.connect(_on_resized)
	_on_resized.call_deferred()


func _on_resized() -> void:
	if not _centered and size.x > 0.0:
		origin = size * 0.5  # start centered on the root
		_centered = true
	_clamp()
	queue_redraw()


## Plays the purchase pop and sends particles toward newly revealed neighbours.
func play_purchase(id: String, revealed: Array[String]) -> void:
	_pops[id] = _pop_s
	for r in revealed:
		_flows.append({"from": _tree_pos(id), "to": _tree_pos(r), "t": 0.0})
	queue_redraw()


func _tree_pos(id: String) -> Vector2:
	var p: Array = DataDB.upgrades[id].get("position", [0, 0])
	return Vector2(float(p[0]), float(p[1]))


func _to_screen(tree_pos: Vector2) -> Vector2:
	return origin + tree_pos * zoom


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var factor := _zoom_step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / _zoom_step
			_zoom_at(mb.position, factor)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag_button = mb.button_index
				_press_pos = mb.position
				_dragging = false
			elif mb.button_index == _drag_button:
				if not _dragging and mb.button_index == MOUSE_BUTTON_LEFT and hovered != "":
					purchase_requested.emit(hovered)
				_drag_button = 0
				_dragging = false
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_button != 0:
			if not _dragging and mm.position.distance_to(_press_pos) > _drag_threshold:
				_dragging = true
			if _dragging:
				origin += mm.relative
				_clamp()
				queue_redraw()
		_update_hover(mm.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_set_hovered("")


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(zoom * factor, _zoom_min, _zoom_max)
	origin = screen_pos - (screen_pos - origin) * (new_zoom / zoom)
	zoom = new_zoom
	_clamp()
	_update_hover(screen_pos)
	queue_redraw()


## Keeps the middle of the screen inside the tree bounds.
func _clamp() -> void:
	var center := size * 0.5
	var tree_center := (center - origin) / zoom
	tree_center = tree_center.clamp(_bounds.position, _bounds.end)
	origin = center - tree_center * zoom


func _update_hover(screen_pos: Vector2) -> void:
	var found := ""
	var half := _node_px * zoom * 0.5
	for id: String in DataDB.upgrades:
		if not GameState.is_upgrade_visible(id):
			continue
		var d := (screen_pos - _to_screen(_tree_pos(id))).abs()
		if d.x <= half and d.y <= half:
			found = id
			break
	_set_hovered(found)


func _set_hovered(id: String) -> void:
	if id != hovered:
		hovered = id
		hovered_changed.emit(id)
		queue_redraw()


func _process(delta: float) -> void:
	if _pops.is_empty() and _flows.is_empty():
		return
	for id: String in _pops.keys():
		_pops[id] = float(_pops[id]) - delta
		if float(_pops[id]) <= 0.0:
			_pops.erase(id)
	for i in range(_flows.size() - 1, -1, -1):
		_flows[i]["t"] = float(_flows[i]["t"]) + delta / _flow_s
		if float(_flows[i]["t"]) >= 1.0:
			_flows.remove_at(i)
	queue_redraw()


func _draw() -> void:
	# Lines from each visible node to its visible prerequisites.
	for id: String in DataDB.upgrades:
		if not GameState.is_upgrade_visible(id):
			continue
		for pre: Variant in DataDB.upgrades[id].get("prereqs", []):
			if not GameState.is_upgrade_visible(str(pre)):
				continue
			var lit := GameState.upgrade_level(id) > 0
			var c := Color(1.0, 0.75, 0.4, 0.9) if lit else Color(0.6, 0.55, 0.7, 0.5)
			draw_line(_to_screen(_tree_pos(str(pre))), _to_screen(_tree_pos(id)), c, maxf(1.0, zoom))

	var font := get_theme_default_font()
	var lock := DataDB.texture(LOCK_ICON)
	for id: String in DataDB.upgrades:
		if not GameState.is_upgrade_visible(id):
			continue
		var up: Dictionary = DataDB.upgrades[id]
		var status := GameState.purchase_status(id)
		var level := GameState.upgrade_level(id)
		var pop := float(_pops.get(id, 0.0)) / _pop_s if _pop_s > 0.0 else 0.0
		var s := _node_px * zoom * (1.0 + 0.25 * pop)
		var center := _to_screen(_tree_pos(id))
		var rect := Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s))

		var fill := Color(0.16, 0.13, 0.2)
		var border := Color(0.45, 0.42, 0.55)
		var icon_tint := Color(0.55, 0.55, 0.6)
		match status:
			GameState.PurchaseStatus.MAXED:
				border = Color(1.0, 0.8, 0.35)
				icon_tint = Color.WHITE
				fill = Color(0.32, 0.22, 0.14)
			GameState.PurchaseStatus.OK:
				border = Color(1.0, 0.95, 0.85)
				icon_tint = Color.WHITE
			GameState.PurchaseStatus.LOCKED:
				fill = Color(0.1, 0.08, 0.12)
				icon_tint = Color(0.35, 0.35, 0.4)
		if level > 0 and status != GameState.PurchaseStatus.MAXED:
			fill = Color(0.28, 0.2, 0.16)
		if id == hovered:
			border = border.lightened(0.3)
		draw_rect(rect, fill)
		draw_rect(rect, border, false, 1.0)

		var icon := DataDB.texture(str(up.get("icon", "")))
		var icon_rect := rect.grow(-s * 0.06)
		if icon:
			draw_texture_rect(icon, icon_rect, false, icon_tint)
		if status == GameState.PurchaseStatus.LOCKED and lock:
			var ls := lock.get_size() * maxf(1.0, roundf(zoom))
			draw_texture_rect(lock, Rect2(rect.end - ls, ls), false)

		var max_level := int(up.get("max_level", 1))
		if max_level > 1 and font:
			var label := "%d/%d" % [level, max_level]
			draw_string(font, Vector2(rect.position.x, rect.end.y + 11), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 16, Color(0.85, 0.8, 0.9))

	for f in _flows:
		var t := float(f["t"])
		var p := _to_screen((f["from"] as Vector2).lerp(f["to"] as Vector2, t))
		draw_circle(p, 2.0 * zoom, Color(1.0, 0.85, 0.5, 1.0 - t))
