class_name Lights
extends Node2D
## Warm light in a dim cave: a big soft light on the keeper's lantern and a capped pool of small
## lights that follow the most recent embers (spec 12.4: no light per ember, no shadows).
## Every other ember glows through its additive sprite only.

const LIGHT_TEXTURE := "res://art/fx/light.png"

var _embers: EmberManager
var _keeper: LanternKeeper
var _keeper_light: PointLight2D
var _pool: Array[PointLight2D] = []


func setup(embers: EmberManager, keeper: LanternKeeper) -> void:
	_embers = embers
	_keeper = keeper
	var tex := DataDB.texture(LIGHT_TEXTURE)
	_keeper_light = _make(tex, DataDB.num("visuals.keeper_light_scale"), DataDB.num("visuals.keeper_light_energy"), Color(1.0, 0.8, 0.5))
	for _i in DataDB.integer("visuals.ember_lights"):
		var l := _make(tex, DataDB.num("visuals.ember_light_scale"), DataDB.num("visuals.ember_light_energy"), Color(1.0, 0.65, 0.35))
		l.visible = false
		_pool.append(l)


func _make(tex: Texture2D, scale_v: float, energy: float, color: Color) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = tex
	l.texture_scale = scale_v
	l.energy = energy
	l.color = color
	l.shadow_enabled = false
	add_child(l)
	return l


func _process(_delta: float) -> void:
	if _keeper:
		_keeper_light.global_position = _keeper.launch_origin()
	var f := Engine.get_physics_interpolation_fraction()
	var n := mini(_pool.size(), _embers.active.size())
	for i in _pool.size():
		var l := _pool[i]
		if i < n:
			var e: EmberManager.Ember = _embers.active[_embers.active.size() - 1 - i]
			l.visible = true
			l.global_position = e.prev.lerp(e.pos, f)
		else:
			l.visible = false
