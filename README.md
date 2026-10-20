# Deepglow

A cozy, mouse-only incremental built in Godot 4 with GDScript.

## Getting started

1. Install the latest Godot 4 (standard build, not .NET).
2. Clone this repo and open `project.godot` from the Godot Project Manager.
3. The first open re-imports assets into `.godot/`, which is ignored by git.

The design spec lives in the project files as `deepglow_design_spec.md`.

## Tuning

Every balance number lives in `data/*.json`: `balance.json` (physics, stats, camera, UI timings),
`ores.json`, `shafts.json`, `upgrades.json` and `artifacts.json`. `DataDB` validates them at startup
and prints clear errors for missing fields, unknown ores, broken prereqs and unknown stats.

## Dev tools (debug builds only)

- **F3**: overlay with FPS, embers, pickups, seed, depth, camera y.
- **F4**: cheat panel (add ore, override ember count/damage, end day, spawn 300 embers / 2,000 pickups, reset save).

Command-line tools (user args go after `--`):

```
# Balance bot: plays headless faster than real time and reports when it reaches the iron gate
# and beats each boss (goal shaft set by debug.autoplay_goal_boss_shaft)
Godot --headless --path . --fixed-fps 60 -- --autoplay

# Performance check: keeps 300 embers + 2,000 pickups alive with vsync off and prints FPS
Godot --path . -- --bench

# Screenshots at the given seconds, saved to user://shots/
Godot --path . -- --shots=2,5,9

# Jump straight to a shaft's boss chamber (combine with --shots to check the art)
Godot --path . res://scenes/gameplay/Gameplay.tscn -- --shaft=2 --reach-boss

# Regenerate the placeholder art
Godot --headless --path . --script res://tools/gen_placeholder_art.gd
```

Bot and benchmark runs never read or write the player's save.
