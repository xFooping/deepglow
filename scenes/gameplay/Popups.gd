class_name Popups
extends Node2D
## Small rising numbers in the world: combo milestones ("x2.0") and ore collected by the magnet.
## Pooled and drawn in one pass.

const RISE_PX_PER_S := 18.0
const LIFE_S := 0.8
const MAX_POPUPS := 60


class FloatText:
	var pos := Vector2.ZERO
	var text: String = ""
	var color := Color.WHITE
	var life: float = 0.0


var _active: Array[FloatText] = []
var _input: PlayerInput
var _font: Font
var _font_size: int = 8


func setup(input: PlayerInput) -> void:
	_input = input
	_font = ThemeDB.fallback_font
	var theme := ThemeDB.get_project_theme()
	if theme and theme.default_font:
		_font = theme.default_font
	_font_size = DataDB.integer("ui.popup_font_size")
	Events.combo_reached.connect(_on_combo_reached)
	Events.ore_collected.connect(_on_ore_collected)


func add(at: Vector2, text: String, color: Color) -> void:
	if not Settings.numbers_enabled():
		return
	if _active.size() >= MAX_POPUPS:
		_active.pop_front()
	var p := FloatText.new()
	p.pos = at
	p.text = text
	p.color = color
	p.life = LIFE_S
	_active.append(p)


func _on_combo_reached(world_pos: Vector2, mult: float) -> void:
	add(world_pos + Vector2(0, -6), "x%.1f" % mult, Color(1.0, 0.8, 0.4))


func _on_ore_collected(ore_id: String, amount: float, source: String) -> void:
	if source == "magnet" and _input:
		add(_input.cursor_world() + Vector2(4, -6), "+%s" % Fmt.num(amount), DataDB.ore_color(ore_id).lightened(0.3))


func _process(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var p := _active[i]
		p.life -= delta
		p.pos.y -= RISE_PX_PER_S * delta
		if p.life <= 0.0:
			_active.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for p in _active:
		var c := p.color
		c.a = clampf(p.life / LIFE_S * 1.5, 0.0, 1.0)
		var w := _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x
		var at := (p.pos - Vector2(w * 0.5, 0)).round()
		draw_string(_font, at + Vector2(1, 1), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, Color(0, 0, 0, c.a * 0.6))
		draw_string(_font, at, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, c)
