extends Node
## Global signal bus. Systems talk through these signals instead of holding references to each other.

@warning_ignore_start("unused_signal")

signal block_hit(cell: Vector2i, ore_id: String, damage: int, crit: bool, world_pos: Vector2)
signal block_broken(cell: Vector2i, ore_id: String, world_pos: Vector2)
signal ore_collected(ore_id: String, amount: float, source: String)
signal ores_changed()
signal ember_launched()
signal ember_burned_out(world_pos: Vector2)
signal day_started(day: int, day_seed: int)
signal day_ended(summary: Dictionary)
signal boss_defeated(shaft_id: int)
signal boss_hit(shaft_id: int, damage: int, hp: int, max_hp: int, crit: bool)
signal boss_shattered(world_pos: Vector2, color: Color)
signal boss_chamber_reached(shaft_id: int)
signal upgrade_purchased(upgrade_id: String, new_level: int)
signal artifact_found(artifact_id: String)
signal toast_requested(text: String)

@warning_ignore_restore("unused_signal")
