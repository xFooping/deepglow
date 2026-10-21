"""Copies the chosen Kenney CC0 sounds (and font) into the project and writes data/audio.json.

Run once after downloading the packs:  python tools/import_kenney_audio.py <folder with the extracted packs>
Each pack folder is expected to be named after its kenney.nl asset page (impact-sounds, interface-sounds,
digital-audio, ui-audio, kenney-fonts, music-jingles). Generated sounds (tools/gen_audio.py) are listed
in audio.json too, so this script and gen_audio.py together produce the full sound set.
"""
import json
import os
import shutil
import sys

SRC = sys.argv[1]
ROOT = os.path.join(os.path.dirname(__file__), "..")
SFX = os.path.join(ROOT, "audio", "sfx")
os.makedirs(SFX, exist_ok=True)


def find(pack, name):
    for dirpath, _dirs, files in os.walk(os.path.join(SRC, pack)):
        if name in files:
            return os.path.join(dirpath, name)
    raise SystemExit(f"not found: {pack}/{name}")


# event -> (bus, volume_db, [(pack, file), ...])
CHOICES = {
    "ember_launch": ("SFX", -10, [("interface-sounds", "pluck_001.ogg"), ("interface-sounds", "pluck_002.ogg")]),
    "ember_bounce_peg": ("SFX", -12, [("interface-sounds", f"glass_00{i}.ogg") for i in (1, 2, 3)]),
    "ember_bounce_block": ("SFX", -22, [("impact-sounds", f"impactGeneric_light_00{i}.ogg") for i in range(5)]),
    "ember_burnout": ("SFX", -18, [("interface-sounds", "minimize_001.ogg")]),
    "block_break_earth": ("SFX", -10, [("impact-sounds", f"impactSoft_medium_00{i}.ogg") for i in range(5)]),
    "block_break_stone": ("SFX", -12, [("impact-sounds", f"impactMining_00{i}.ogg") for i in range(5)]),
    "block_break_metal": ("SFX", -14, [("impact-sounds", f"impactMetal_light_00{i}.ogg") for i in range(5)]),
    "block_break_crystal": ("SFX", -12, [("impact-sounds", f"impactGlass_light_00{i}.ogg") for i in range(5)]),
    "ore_pickup": ("SFX", -14, [("interface-sounds", "tick_002.ogg")]),
    "artifact_found": ("SFX", -6, [("music-jingles", "jingles_STEEL00.ogg")]),
    "boss_hit": ("SFX", -14, [("impact-sounds", f"impactBell_heavy_00{i}.ogg") for i in range(5)]),
    "boss_shatter": ("SFX", -4, [("impact-sounds", "impactGlass_heavy_002.ogg")]),
    "boss_fanfare": ("Music", -6, [("music-jingles", "jingles_PIZZI03.ogg")]),
    "mushroom_boing": ("SFX", -10, [("impact-sounds", f"impactSoft_heavy_00{i}.ogg") for i in range(3)]),
    "prism_split": ("SFX", -10, [("interface-sounds", "glass_005.ogg"), ("interface-sounds", "glass_006.ogg")]),
    "kindling_pop": ("SFX", -10, [("impact-sounds", f"impactWood_light_00{i}.ogg") for i in range(5)]),
    "bomb_blast": ("SFX", -8, [("impact-sounds", f"impactPunch_heavy_00{i}.ogg") for i in range(3)]),
    "lantern_flare": ("SFX", -12, [("digital-audio", "phaserUp3.ogg")]),
    "lantern_pulse": ("SFX", -12, [("digital-audio", "powerUp2.ogg")]),
    "ui_hover": ("UI", -16, [("ui-audio", "rollover2.ogg")]),
    "ui_click": ("UI", -8, [("ui-audio", "click3.ogg")]),
    "node_purchase": ("UI", -6, [("interface-sounds", "confirmation_001.ogg")]),
    "node_cant_afford": ("UI", -10, [("interface-sounds", "error_004.ogg")]),
    "panel_slide": ("UI", -12, [("interface-sounds", "open_001.ogg")]),
    "elevator_unlock": ("UI", -6, [("interface-sounds", "confirmation_003.ogg")]),
    "lode_break": ("SFX", -6, [("music-jingles", "jingles_NES05.ogg")]),
    "jar_break": ("SFX", -6, [("digital-audio", "powerUp4.ogg")]),
    "moth_catch": ("SFX", -6, [("digital-audio", "powerUp7.ogg")]),
    "depth_bonus": ("SFX", -8, [("interface-sounds", "maximize_003.ogg")]),
    "day_start": ("UI", -10, [("interface-sounds", "open_002.ogg")]),
    "tally_tick": ("UI", -18, [("interface-sounds", "tick_001.ogg")]),
}
# Made by tools/gen_audio.py (also CC0: generated for this project).
GENERATED = {
    "water_hiss": ("SFX", -16, ["water_hiss.wav"]),
    "music": ("Music", -8, ["../music/deepglow_ambient.wav"]),
    "ambience": ("Music", -14, ["../music/cave_ambience.wav"]),
}

out = {}
credits = []
for event, (bus, vol, files) in CHOICES.items():
    paths = []
    for pack, name in files:
        dst_name = f"{event}_{len(paths)}.ogg"
        shutil.copyfile(find(pack, name), os.path.join(SFX, dst_name))
        paths.append(f"res://audio/sfx/{dst_name}")
        credits.append(f"| `audio/sfx/{dst_name}` | Kenney, *{pack}* (`{name}`) | https://kenney.nl/assets/{pack} | CC0 |")
    out[event] = {"bus": bus, "volume_db": vol, "files": paths}
for event, (bus, vol, files) in GENERATED.items():
    out[event] = {"bus": bus, "volume_db": vol, "files": [f"res://audio/sfx/{f}" if not f.startswith("..") else "res://audio/" + f[3:] for f in files]}

with open(os.path.join(ROOT, "data", "audio.json"), "w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(out, indent="\t") + "\n")

fonts = os.path.join(ROOT, "fonts")
os.makedirs(fonts, exist_ok=True)
shutil.copyfile(find("kenney-fonts", "Kenney Pixel.ttf"), os.path.join(fonts, "kenney_pixel.ttf"))
credits.append("| `fonts/kenney_pixel.ttf` | Kenney, *Kenney Fonts* (`Kenney Pixel.ttf`) | https://kenney.nl/assets/kenney-fonts | CC0 |")

with open(os.path.join(ROOT, "audio", "credits_table.md"), "w", encoding="utf-8", newline="\n") as f:  # paste into CREDITS.md
    f.write("\n".join(credits) + "\n")
print(f"{len(out)} events, {len(credits)} files")
