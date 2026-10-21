extends Node
## Player settings (stored in the save under "settings"). Defaults live in balance.json "settings".
## The settings screen arrives with the Phase 5 polish; the toggles already work.


func _ready() -> void:
	apply()


func get_setting(key: String) -> Variant:
	var defaults: Dictionary = DataDB.val("settings")
	return GameState.settings.get(key, defaults.get(key))


func set_setting(key: String, value: Variant) -> void:
	GameState.settings[key] = value
	apply()


func numbers_enabled() -> bool:
	return bool(get_setting("damage_numbers"))


func shake_enabled() -> bool:
	return bool(get_setting("screen_shake"))


func magnet_ring_enabled() -> bool:
	return bool(get_setting("magnet_ring"))


## Pushes volumes to the audio buses.
func apply() -> void:
	for bus: String in ["Master", "Music", "SFX", "UI"]:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var vol := float(get_setting(bus.to_lower() + "_volume"))
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))
			AudioServer.set_bus_mute(idx, vol <= 0.0)
