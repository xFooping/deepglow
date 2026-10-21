class_name Popups
extends Node2D
## Small rising numbers in the world: combo milestones ("x2.0") and ore collected by the magnet.
## Pooled and drawn in one pass.

const RISE_PX_PER_S := 18.0
const LIFE_S := 0.8
const MAX_POPUPS := 60
const CALLOUT_S := 1.3


class FloatText:
	var pos := Vector2.ZERO
	var text: String = ""
	var color := Color.WHITE
	var life: float = 0.0
	var max_life: float = 0.8
	var size: int = 16
	var big: bool = false


var _active: Array[FloatText] = []
var _input: PlayerInput
var _font: Font
var _font_size: int = 8
var _tiers: Array = []
var _popup_every: int = 4
var _last_ore_ms: int = 0


func setup(input: PlayerInput) -> void:
	_input = input
	_font = ThemeDB.fallback_font
	var theme := ThemeDB.get_project_theme()
	if theme and theme.default_font:
		_font = theme.default_font
	_font_size = DataDB.integer("ui.popup_font_size")
	_tiers = DataDB.val("juice.combo_callouts")
	_popup_every = DataDB.integer("combo.popup_every")
	Events.combo_reached.connect(_on_combo_reached)
	Events.ore_collected.connect(_on_ore_collected)
	Events.jar_broken.connect(func(p: Vector2, n: int) -> void: callout(p, "+%d EMBERS!" % n, Color(1.0, 0.65, 0.3)))
	Events.moth_caught.connect(func(p: Vector2) -> void: callout(p, "GLOWMOTH! +1 EMBER", Color(0.6, 1.0, 0.8)))
	Events.lode_broken.connect(func(p: Vector2) -> void: callout(p, "LODE!", Color(1.0, 0.85, 0.35)))
	Events.depth_bonus.connect(func(p: Vector2, m: int, n: int) -> void: callout(p, "%d m!  +%d EMBER" % [m, n], Color(0.85, 0.8, 1.0)))
	Events.bomb_exploded.connect(func(p: Vector2, _r: int) -> void: add(p, "BOOM", Color(1.0, 0.55, 0.3)))


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
	p.max_life = LIFE_S
	p.size = _font_size
	_active.append(p)


## A big word that pops in with a little overshoot and floats up. Always shown (it's feedback,
## not a number), so it ignores the damage-numbers setting.
func callout(at: Vector2, text: String, color: Color) -> void:
	if _active.size() >= MAX_POPUPS:
		_active.pop_front()
	var p := FloatText.new()
	p.pos = at
	p.text = text
	p.color = color
	p.max_life = CALLOUT_S
	p.life = CALLOUT_S
	p.size = _font_size * 2
	p.big = true
	_active.append(p)


func _on_combo_reached(world_pos: Vector2, mult: float) -> void:
	add(world_pos + Vector2(0, -6), "x%.1f" % mult, Color(1.0, 0.8, 0.4))
	# A word when the combo climbs into a new tier.
	var prev := mult - Stats.get_f("combo_step") * _popup_every
	var word := _tier_word(mult)
	if word != "" and word != _tier_word(prev):
		callout(world_pos + Vector2(0, -16), word, Color(1.0, 0.9, 0.5))


func _tier_word(mult: float) -> String:
	var word := ""
	for t: Variant in _tiers:
		var tier: Array = t
		if mult >= float(tier[0]):
			word = str(tier[1])
	return word


func _on_ore_collected(ore_id: String, amount: float, source: String) -> void:
	var now := Time.get_ticks_msec()
	if source == "magnet" and _input and now - _last_ore_ms > 60:
		_last_ore_ms = now
		add(_input.cursor_world() + Vector2(4, -6), "+%s" % Fmt.num(amount), DataDB.ore_color(ore_id).lightened(0.3))


func _process(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var p := _active[i]
		p.life -= delta
		p.pos.y -= RISE_PX_PER_S * delta * (0.5 if p.big else 1.0)
		if p.life <= 0.0:
			_active.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for p in _active:
		var c := p.color
		c.a = clampf(p.life / p.max_life * 1.5, 0.0, 1.0)
		var s := 1.0
		if p.big:
			# Pop in with a small overshoot, then settle.
			var age := p.max_life - p.life
			s = 1.0 + 0.35 * exp(-age * 9.0) * cos(age * 22.0) - 0.4 * exp(-age * 30.0)
		var w := _font.get_string_size(p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size).x
		draw_set_transform(p.pos.round(), 0.0, Vector2(s, s))
		var at := Vector2(-w * 0.5, 0)
		draw_string(_font, at + Vector2(1, 1), p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size, Color(0, 0, 0, c.a * 0.7))
		draw_string(_font, at, p.text, HORIZONTAL_ALIGNMENT_LEFT, -1, p.size, c)
	draw_set_transform(Vector2.ZERO)
