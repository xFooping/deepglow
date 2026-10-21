"""Builds data/upgrades.json from the compact branch definitions below.

Run:  python tools/gen_tree.py
The JSON stays the source of truth the game reads (and can be hand-edited); this script is just a
quick way to regenerate the whole tree after a structural change. It overwrites upgrades.json.

Layout: eight branches radiate from the root. Each branch has a main lane (one node per ore tier,
cheapest first) and side nodes (milestones that unlock new mechanics) hanging off it.
"""
import json
import math
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "data", "upgrades.json")

# Ore tiers in order, with the base cost of a node in that tier: (main ore, amount, previous ore, amount).
TIERS = {
    1: ("dirt", 15, None, 0),
    2: ("coal", 25, "dirt", 120),
    3: ("copper", 25, "coal", 150),
    4: ("iron", 90, "copper", 250),
    5: ("silver", 60, "iron", 450),
    6: ("gold", 220, "silver", 300),
    7: ("quartz", 150, "gold", 900),
    8: ("sapphire", 120, "quartz", 400),
    9: ("moonstone", 90, "sapphire", 600),
    10: ("obsidian", 150, "moonstone", 400),
    11: ("emberstone", 100, "obsidian", 1000),
}
SPACING = 64
SIDE = 52
START = 80

nodes = [{"id": "root", "name": "Lantern Keeper", "description": "Your little keeper and their lantern. Everything grows from here.",
          "icon": "res://art/icons/upgrades/root.png", "position": [0, 0], "prereqs": [], "max_level": 1, "cost": {}, "effects": []}]


def cost(tier, weight=1.0):
    main, amount, prev, prev_amount = TIERS[tier]
    out = {main: max(1, int(round(amount * weight / 5.0)) * 5) if amount * weight > 10 else max(1, int(round(amount * weight)))}
    if prev:
        out[prev] = int(round(prev_amount * weight / 5.0)) * 5
    return out


def eff(stat, op, value):
    return {"stat": stat, "op": op, "value": value}


def add(nid, name, desc, icon, pos, prereqs, max_level, tier, effects, weight=1.0, scaling=1.8, cost_override=None):
    n = {"id": nid, "name": name, "description": desc, "icon": f"res://art/icons/upgrades/{icon}.png",
         "position": [int(round(pos[0])), int(round(pos[1]))], "prereqs": prereqs, "max_level": max_level,
         "cost": cost_override or cost(tier, weight)}
    if max_level > 1:
        n["cost_scaling"] = scaling
    n["effects"] = effects
    nodes.append(n)


def branch(angle_deg, lane, sides):
    """lane: list of (id, name, desc, icon, max_level, tier, effects, weight, scaling)
    sides: list of (lane_index, side(+1/-1), id, name, desc, icon, max_level, tier, effects, weight)"""
    a = math.radians(angle_deg)
    d = (math.cos(a), math.sin(a))
    perp = (-d[1], d[0])
    prev = "root"
    for i, (nid, name, desc, icon, ml, tier, effects, weight, scaling) in enumerate(lane):
        dist = START + SPACING * i
        add(nid, name, desc, icon, (d[0] * dist, d[1] * dist), [prev], ml, tier, effects, weight, scaling)
        prev = nid
    for (li, side, nid, name, desc, icon, ml, tier, effects, weight) in sides:
        dist = START + SPACING * li
        pos = (d[0] * dist + perp[0] * SIDE * side, d[1] * dist + perp[1] * SIDE * side)
        add(nid, name, desc, icon, pos, [lane[li][0]], ml, tier, effects, weight, 1.9)


ORE_NAMES = ["Dirt", "Coal", "Copper", "Iron", "Silver", "Gold", "Quartz", "Sapphire", "Moonstone", "Obsidian", "Emberstone"]

# --- Heat: damage, crits, bombs, supernova (right) -------------------------------
heat_names = ["Hotter Coals", "Coal Heart", "Copper Core", "Iron Heart", "Silver Flame", "Gilded Flame", "Rose Fire",
              "Blue Heat", "Moonfire", "Black Glass Heart", "Emberheart"]
heat_lane = []
for t in range(1, 12):
    v = 2 ** (t - 1)
    heat_lane.append((f"heat_{t}", heat_names[t - 1], f"+{v} ember damage per level.", "damage", 5, t,
                      [eff("ember_damage", "add", v)], 1.0, 1.8))
branch(0, heat_lane, [
    (1, -1, "bomb_ember", "Bomb Ember", "Every 5th ember is a bomb: its first block hit bursts for 3x damage around it.", "bomb", 1, 2,
     [eff("bomb_every", "set", 5)], 1.5),
    (2, 1, "crit_1", "Flare-up", "+5% crit chance per level. Crits deal triple damage.", "crit", 3, 3, [eff("crit_chance", "add", 0.05)], 1.0),
    (3, -1, "short_fuse", "Short Fuse", "One fewer ember between bombs, per level.", "bomb", 2, 4, [eff("bomb_every", "add", -1)], 1.3),
    (5, 1, "crit_2", "Bright Flare", "+5% crit chance per level.", "crit", 3, 6, [eff("crit_chance", "add", 0.05)], 1.0),
    (6, -1, "big_bang", "Big Bang", "+1 bomb blast radius.", "bomb", 1, 7, [eff("bomb_radius", "add", 1)], 1.5),
    (7, 1, "heat_mastery", "Heat Mastery", "+15% ember damage per level.", "mastery", 3, 8, [eff("ember_damage", "mult", 1.15)], 1.3),
    (9, -1, "supernova", "Supernova", "The day's last ember is a giant with 10x damage.", "nova", 1, 10, [eff("nova_mult", "set", 10)], 1.5),
])

# --- Wick: durability, piercing, afterglow (down) -----------------------------
wick_vals = [5, 8, 12, 20, 30, 35, 45, 55, 65, 80, 100]
wick_names = ["Slow Burn", "Thick Wick", "Braided Wick", "Iron Wick", "Silver Thread", "Golden Wick", "Quartz Thread",
              "Tide Wick", "Moon Thread", "Obsidian Wick", "Everburn"]
branch(90, [(f"wick_{t}", wick_names[t - 1], f"+{wick_vals[t - 1]} ember durability per level.", "durability", 5, t,
             [eff("ember_durability", "add", wick_vals[t - 1])], 1.0, 1.7) for t in range(1, 12)], [
    (2, -1, "pierce_1", "Piercing Flame", "Embers smash straight through blocks they break, once more per level.", "pierce", 3, 3,
     [eff("pierce", "add", 1)], 1.4),
    (5, 1, "pierce_2", "Lancing Flame", "Embers smash through one more block per level.", "pierce", 3, 6, [eff("pierce", "add", 1)], 1.3),
    (7, -1, "afterglow", "Afterglow", "+15% chance per level that a spent ember leaves a smaller echo.", "echo", 3, 8,
     [eff("echo_chance", "add", 0.15)], 1.3),
    (9, 1, "wick_mastery", "Wick Mastery", "+15% ember durability per level.", "mastery", 3, 10, [eff("ember_durability", "mult", 1.15)], 1.3),
])

# --- Supply: ember count, twin shots (left) ---------------------------------------
supply_vals = [1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4]
supply_names = ["Spare Embers", "Ember Pouch", "Lantern Satchel", "Ember Crate", "Hearth Bag", "Treasure Pouch",
                "Glimmer Sack", "Diving Bag", "Moon Satchel", "Hearth Crate", "Ember Trove"]
branch(180, [(f"supply_{t}", supply_names[t - 1], f"+{supply_vals[t - 1]} embers per day per level.", "count", 3, t,
              [eff("ember_count", "add", supply_vals[t - 1])], 1.6, 2.0) for t in range(1, 12)], [
    (3, 1, "twin_wick", "Twin Wick", "Each shot fires one extra free ember, fanned out.", "multishot", 1, 4, [eff("multishot", "add", 1)], 1.6),
    (6, -1, "triple_wick", "Triple Wick", "Each shot fires another extra free ember.", "multishot", 1, 7, [eff("multishot", "add", 1)], 1.6),
    (9, 1, "fan_of_flames", "Fan of Flames", "Each shot fires another extra free ember.", "multishot", 1, 10, [eff("multishot", "add", 1)], 1.6),
])

# --- Quick Hands: fire rate, launch speed, Lantern Flare (up-left) --------------
quick_lane = []
for t in range(1, 12):
    if t % 2 == 1:
        quick_lane.append((f"quick_{t}", f"Quick Hands {t // 2 + 1}", "-12% fire cooldown per level.", "fire_rate", 3, t,
                           [eff("fire_cooldown", "mult", 0.88)], 1.0, 1.8))
    else:
        quick_lane.append((f"quick_{t}", f"Strong Arm {t // 2}", "+10% launch speed per level.", "launch", 3, t,
                           [eff("launch_speed", "mult", 1.1)], 0.8, 1.8))
branch(225, quick_lane, [
    (1, 1, "flare", "Lantern Flare", "Every 12 s the keeper fires a beam along your aim that hits every block it crosses (5x damage).",
     "flare", 1, 2, [eff("flare_cooldown", "set", 12), eff("flare_damage_mult", "set", 5)], 1.6),
    (4, -1, "bright_beam", "Bright Beam", "-15% flare cooldown and +2 flare damage per level.", "flare", 3, 5,
     [eff("flare_cooldown", "mult", 0.85), eff("flare_damage_mult", "add", 2)], 1.3),
    (6, 1, "long_beam", "Long Beam", "+4 cells of flare length per level.", "flare", 3, 7, [eff("flare_length", "add", 4)], 1.3),
])

# --- Lantern Pull: magnet, banking, pulse, auto-collect (up) ---------------------
pull_lane = []
for t in range(1, 12):
    if t <= 5 and t % 2 == 0:
        pull_lane.append((f"pull_{t}", f"Lost & Found {t // 2}", "+10% of off-screen ore is banked, per level.", "bank", 3, t,
                          [eff("offscreen_bank_rate", "add", 0.1)], 0.8, 1.8))
    else:
        pull_lane.append((f"pull_{t}", f"Gentle Pull {t}", "+8 px magnet radius per level.", "magnet", 3, t,
                          [eff("magnet_radius", "add", 8)], 0.6, 1.8))
branch(270, pull_lane, [
    (2, 1, "pulse", "Lantern Pulse", "Every 8 s, every ore on screen flies to your cursor.", "pulse", 1, 3, [eff("pulse_cooldown", "set", 8)], 1.5),
    (4, -1, "lanterns_call", "Lantern's Call", "All ore flies to you on its own and nothing is lost off-screen.", "auto_collect", 1, 5,
     [eff("auto_collect", "set", True)], 2.0),
])

# --- Prospecting: yields, lodes, ore sense, chain spark (up-right) ---------------
pro_lane = [(f"yield_{ORE_NAMES[t - 1].lower()}", f"{ORE_NAMES[t - 1]} Vein", f"+1 {ORE_NAMES[t - 1].lower()} per {ORE_NAMES[t - 1].lower()} block, per level.",
             "yield", 3, t, [eff(f"ore_yield_{ORE_NAMES[t - 1].lower()}", "add", 1)], 1.6, 2.2) for t in range(1, 12)]
branch(315, pro_lane, [
    (1, -1, "lode_eye", "Prospector's Eye", "More glowing lodes (8x ore) appear: +1% per level.", "lode", 3, 2, [eff("lode_chance", "add", 0.01)], 1.2),
    (2, 1, "chain_1", "Copper Wire", "+6% chance per level that a broken block sparks into a neighbour.", "chain", 3, 3,
     [eff("chain_spark_chance", "add", 0.06)], 1.2),
    (3, -1, "ore_sense", "Ore Sense", "Embers curve gently toward nearby lodes and ore.", "seek", 1, 4, [eff("seek_strength", "set", 250)], 1.6),
    (5, 1, "chain_2", "Iron Filings", "+6% chain spark chance per level.", "chain", 3, 6, [eff("chain_spark_chance", "add", 0.06)], 1.2),
    (6, -1, "keen_sense", "Keen Sense", "Embers home in harder: +150 pull per level.", "seek", 2, 7, [eff("seek_strength", "add", 150)], 1.3),
    (7, 1, "artifact_1", "Keen Eye", "+25% artifact chance per level.", "artifact", 3, 8, [eff("artifact_chance", "mult", 1.25)], 1.0),
    (9, -1, "chain_3", "Ember Wire", "+6% chain spark chance per level.", "chain", 3, 10, [eff("chain_spark_chance", "add", 0.06)], 1.2),
])

# --- Pegs and twists: combo, sparking pegs, shaft twists (down-left) ------------
peg_lane = [
    ("ringing_pegs", "Ringing Pegs", "+0.1 ore multiplier per peg bounce, per level.", "combo", 3, 1, [eff("combo_step", "add", 0.1)], 1.2, 1.9),
    ("deep_combo", "Deep Combo", "+2 to the highest combo multiplier, per level.", "combo", 3, 3, [eff("combo_max", "add", 2)], 1.2, 1.9),
    ("springy_caps", "Springy Caps", "Mushrooms bounce harder: +0.05 per level.", "mushroom", 3, 4, [eff("mushroom_restitution", "add", 0.05)], 1.0, 1.9),
    ("bouncy_spores", "Bouncy Spores", "Mushrooms bounce harder: +0.05 per level.", "mushroom", 3, 5, [eff("mushroom_restitution", "add", 0.05)], 1.0, 1.9),
    ("facets", "Facets", "+8% prism split chance per level.", "prism", 3, 6, [eff("prism_split_chance", "add", 0.08)], 1.0, 1.9),
    ("rainbow_edge", "Rainbow Edge", "+8% prism split chance per level.", "prism", 3, 7, [eff("prism_split_chance", "add", 0.08)], 1.0, 1.9),
    ("oiled_wick", "Oiled Wick", "-20% durability drained by water, per level.", "water", 3, 8, [eff("water_drain_mult", "mult", 0.8)], 1.0, 1.9),
    ("steam_shell", "Steam Shell", "-20% durability drained by water, per level.", "water", 3, 9, [eff("water_drain_mult", "mult", 0.8)], 1.0, 1.9),
    ("dry_tinder", "Dry Tinder", "+1x ember damage per kindling burst, per level.", "kindling", 3, 10, [eff("kindling_burst_mult", "add", 1.0)], 1.0, 1.9),
    ("bonfire_heart", "Bonfire Heart", "+2x ember damage per kindling burst, per level.", "kindling", 3, 11, [eff("kindling_burst_mult", "add", 2.0)], 1.0, 1.9),
]
branch(135, peg_lane, [
    (1, 1, "sparking_pegs", "Sparking Pegs", "Pegs zap a neighbouring block for 1x ember damage when hit.", "spark", 1, 2,
     [eff("peg_spark_mult", "set", 1)], 1.6),
    (4, -1, "storm_pegs", "Storm Pegs", "+1x peg spark damage per level.", "spark", 3, 6, [eff("peg_spark_mult", "add", 1)], 1.2),
])

# --- Elevator: start stops per shaft and the gates between shafts (down-right) ---
STOPS = [(1, 50, 2), (1, 100, 3), (2, 50, 4), (2, 120, 5), (2, 200, 5), (3, 80, 6), (3, 180, 7), (3, 280, 7),
         (4, 100, 8), (4, 220, 9), (4, 340, 9), (5, 120, 10), (5, 300, 11), (5, 450, 11)]
GATES = {1: ("gate_iron", "Deeper Still", "iron", "copper", "The Shallows"),
         2: ("gate_gold", "Deeper Still II", "gold", "silver", "Iron Veins"),
         3: ("gate_sapphire", "Deeper Still III", "sapphire", "quartz", "Glimmer Grotto"),
         4: ("gate_obsidian", "Deeper Still IV", "obsidian", "moonstone", "Drip Caverns")}
SHAFT_NAMES = {1: "The Shallows", 2: "Iron Veins", 3: "Glimmer Grotto", 4: "Drip Caverns", 5: "The Hearth"}
elev_lane = []
for idx, (shaft, depth, tier) in enumerate(STOPS):
    elev_lane.append((f"elevator_{idx + 1}", f"{SHAFT_NAMES[shaft]} {depth} m", f"Unlocks a {depth} m start in {SHAFT_NAMES[shaft]} (once you've been that deep).",
                      "elevator", 1, tier, [{"type": "unlock_elevator_stop", "shaft": shaft, "depth_m": depth}], 1.2, 1.8))
    last_of_shaft = idx + 1 == len(STOPS) or STOPS[idx + 1][0] != shaft
    if last_of_shaft and shaft in GATES:
        gid, gname, gore, held, this_name = GATES[shaft]
        elev_lane.append((gid, gname, f"Needs {gore} from the next shaft. Break the crystal at the bottom of {this_name}.", "gate", 1, tier,
                          [], 1.0, 1.8))
branch(45, elev_lane, [])
for n in nodes:
    if n["id"] in [g[0] for g in GATES.values()]:
        g = next(v for v in GATES.values() if v[0] == n["id"])
        n["cost"] = {g[2]: 10, g[3]: 200}

with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("[\n" + ",\n".join("\t" + json.dumps(n, ensure_ascii=False) for n in nodes) + "\n]\n")

# Spacing check: report any two nodes closer than 44 px.
close = []
for i in range(len(nodes)):
    for j in range(i + 1, len(nodes)):
        a, b = nodes[i]["position"], nodes[j]["position"]
        if math.hypot(a[0] - b[0], a[1] - b[1]) < 44:
            close.append((nodes[i]["id"], nodes[j]["id"]))
print(f"{len(nodes)} nodes written to {OUT}")
if close:
    print("too close:", close)
