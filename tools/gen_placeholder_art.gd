extends SceneTree
## Generates the placeholder pixel art under res://art. Every file is meant to be replaced by real
## art later: the game only finds these by path (via res://data/*.json or a path constant), so
## swapping a PNG needs no code change.
## Run: Godot --headless --path . --script res://tools/gen_placeholder_art.gd

const PALETTE := {
	"o": Color(1.0, 0.55, 0.15),
	"y": Color(1.0, 0.85, 0.3),
	"w": Color(1.0, 0.97, 0.9),
	"d": Color(0.15, 0.1, 0.12),
	"b": Color(0.55, 0.36, 0.22),
	"g": Color(0.6, 0.6, 0.66),
	"c": Color(0.6, 0.9, 1.0),
	"r": Color(0.85, 0.3, 0.3),
	"k": Color(1.0, 0.78, 0.25),
}

const ICONS := {
	"root": ["...dd...", "..d..d..", "..dddd..", ".dyyyyd.", ".dywyyd.", ".dyyyyd.", "..dddd..", "........"],
	"damage": ["...o....", "...oo...", "..oyo.o.", ".ooyyoo.", ".oyywyo.", "oyywwyyo", "oyywwyyo", ".oyyyyo."],
	"durability": ["....o...", "....y...", "...www..", "...wyw..", "...www..", "...www..", "...www..", "..bbbbb."],
	"count": ["........", ".o....o.", "oyo..oyo", ".o....o.", "....o...", "...oyo..", "....o...", "........"],
	"magnet": [".ww..ww.", ".rr..rr.", ".rr..rr.", ".rr..rr.", ".rr..rr.", ".rrrrrr.", "..rrrr..", "........"],
	"launch": ["........", ".wwww...", ".ww.....", ".w.w....", ".w..w...", ".....w..", "......w.", "........"],
	"fire_rate": ["..gggg..", ".gwwwwg.", "gwwdwwwg", "gwwdwwwg", "gwwddwwg", "gwwwwwwg", ".gwwwwg.", "..gggg.."],
	"yield": [".gggg...", "g....g..", "....bg..", "...b....", "..b.....", ".b......", "b.......", "........"],
	"bank": ["...dd...", "..b..b..", ".bbbbbb.", "bbkbbbbb", "bbbbbkbb", "bbbbbbbb", ".bbbbbb.", "........"],
	"crit": ["...k....", "...k....", "kkkkkkk.", ".kkkkk..", "..kkk...", ".kk.kk..", ".k...k..", "........"],
	"elevator": [".b...b..", ".bbbbb..", ".b...b..", ".bbbbb..", ".b...b..", ".bbbbb..", ".b...b..", ".b...b.."],
	"chain": ["....k...", "...k....", "..kkkk..", "....k...", "...k....", "..kkkk..", "....k...", "...k...."],
	"mushroom": ["..cccc..", ".cwccwc.", "cccccccc", "cwcccwcc", "..wwww..", "...ww...", "...ww...", "..wwww.."],
	"prism": ["...w....", "..wcw...", "..ccc...", ".ccwcc..", ".ccccc..", "cckccrc.", "ccccccc.", "........"],
	"water": ["...c....", "...c....", "..ccc...", ".ccwcc..", ".cwccc..", ".ccccc..", "..ccc...", "........"],
	"kindling": ["..o.....", ".oyo..o.", "..o..oyo", "bbbbbbbb", ".bdbbdb.", "bbbbbbbb", ".bbdbbd.", "........"],
	"artifact": ["...c....", "..cwc...", ".cwcwc..", "cwcwcwc.", ".cwcwc..", "..cwc...", "...c....", "........"],
	"auto_collect": ["k.rr.rr.", ".krr.rrk", ".rr..rr.", ".rr..rr.", ".rr..rr.", ".rrrrrr.", "k.rrrr.k", "........"],
	"mastery": ["k..o...k", "...oo...", "..oyo.o.", ".ooyyoo.", ".oyywyo.", "oyywwyyo", "oyywwyyo", "k.oyyo.k"],
	"gate": ["...w....", "...w....", "...w....", ".wwwww..", "..www...", "...w....", "gggggggg", "gdgdgdgd"],
}

const LOCK := ["..gggg..", ".g....g.", ".g....g.", "gggggggg", "gkkkkkkg", "gkkdkkkg", "gkkdkkkg", "gggggggg"]
const UNKNOWN := ["..wwww..", ".w....w.", "......w.", "....ww..", "...w....", "...w....", "........", "...w...."]
const CURSOR := ["d.......", "dd......", "dwd.....", "dwwd....", "dwwwd...", "dwwdd...", "dd.d....", "........"]
const ARTIFACT := ["...c....", "..cwc...", ".cwcwc..", "cwcwcwc.", ".cwcwc..", "..cwc...", "...c....", "........"]


func _init() -> void:
	var ores: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ores.json"))
	for entry: Variant in ores:
		var ore: Dictionary = entry
		var c := Color.html(str(ore["color"]))
		_save(_block(c, hash(str(ore["id"]))), str(ore["block_texture_path"]))
		_save(_pickup(c), str(ore["pickup_texture_path"]))
	_save(_peg(), "res://art/blocks/peg.png")
	_save(_mushroom(), "res://art/blocks/mushroom.png")
	_save(_prism(), "res://art/blocks/prism.png")
	_save(_water(), "res://art/blocks/water.png")
	_save(_kindling(), "res://art/blocks/kindling.png")
	_save(_rich(), "res://art/blocks/rich_vein.png")
	var shafts: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/shafts.json"))
	for entry: Variant in shafts:
		var shaft: Dictionary = entry
		var cells: Array = shaft["boss_size_cells"]
		_save(_boss(int(cells[0]) * 16, int(cells[1]) * 16, Color.html(str(shaft["boss_color"])), int(shaft["id"])), str(shaft["boss_texture_path"]))
	_save(_cracks(1), "res://art/blocks/crack_1.png")
	_save(_cracks(2), "res://art/blocks/crack_2.png")
	_save(_ember_core(), "res://art/embers/ember_core.png")
	_save(_ember_glow(), "res://art/embers/ember_glow.png")
	_save(_keeper(), "res://art/keeper/keeper.png")
	_save(_lantern(), "res://art/keeper/lantern.png")
	_save(_rock(Color(0.75, 0.75, 0.75), 7, false), "res://art/backgrounds/rock.png")
	_save(_rock(Color(0.28, 0.22, 0.3), 11, true), "res://art/backgrounds/floor.png")
	for icon_name: String in ICONS:
		_save(_ascii(ICONS[icon_name], 2), "res://art/icons/upgrades/%s.png" % icon_name)
	_save(_ascii(ARTIFACT, 2), "res://art/icons/artifacts/placeholder.png")
	_save(_ascii(LOCK, 1), "res://art/ui/lock.png")
	_save(_ascii(UNKNOWN, 1), "res://art/ui/unknown_ore.png")
	_save(_ascii(CURSOR, 1), "res://art/ui/cursor.png")
	_save(_ascii(ICONS["damage"], 1), "res://art/ui/ember_icon.png")
	print("Placeholder art generated.")
	quit()


func _save(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		push_error("Could not save %s: %s" % [path, error_string(err)])


func _new(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


func _block(c: Color, s: int) -> Image:
	var img := _new(16, 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	for y in 16:
		for x in 16:
			var n := rng.randf_range(-0.07, 0.07)
			var col := c.lightened(n) if n > 0.0 else c.darkened(-n)
			if x == 0 or y == 0:
				col = c.lightened(0.22)
			elif x == 15 or y == 15:
				col = c.darkened(0.35)
			img.set_pixel(x, y, col)
	for _i in 4:
		img.set_pixel(rng.randi_range(2, 13), rng.randi_range(2, 13), c.lightened(0.5))
	return img


func _pickup(c: Color) -> Image:
	var img := _new(8, 8)
	for y in 8:
		for x in 8:
			var d := absf(x - 3.5) + absf(y - 3.5)
			if d > 4.0:
				continue
			var col := c
			if d > 3.0:
				col = c.darkened(0.45)
			elif x <= 3 and y <= 3 and d < 2.5:
				col = c.lightened(0.45)
			img.set_pixel(x, y, col)
	return img


func _peg() -> Image:
	var img := _new(16, 16)
	var center := Vector2(7.5, 7.5)
	for y in 16:
		for x in 16:
			var d := Vector2(x, y).distance_to(center)
			if d > 5.5:
				continue
			var col := Color(0.62, 0.9, 0.98)
			if d > 4.6:
				col = Color(0.3, 0.55, 0.7)
			elif Vector2(x, y).distance_to(Vector2(6, 6)) < 1.6:
				col = Color(0.95, 1.0, 1.0)
			img.set_pixel(x, y, col)
	return img


## A glowing teal mushroom cap on a pale stem, ~12 px wide, sitting on the cell's bottom edge.
func _mushroom() -> Image:
	var img := _new(16, 16)
	var cap := Color(0.35, 0.85, 0.78)
	for y in 16:
		for x in 16:
			var p := Vector2(x, y)
			var in_cap := y >= 3 and y <= 8 and Vector2((x - 7.5) / 6.0, (y - 8.0) / 5.0).length() <= 1.0
			var in_stem := y >= 9 and y <= 14 and absf(x - 7.5) <= 1.6
			if in_cap:
				var col := cap
				if y == 8 or Vector2((x - 7.5) / 6.0, (y - 8.0) / 5.0).length() > 0.82:
					col = cap.darkened(0.35)
				if p.distance_to(Vector2(5, 5)) < 1.2 or p.distance_to(Vector2(10, 6)) < 1.0:
					col = Color(0.92, 1.0, 0.95)
				img.set_pixel(x, y, col)
			elif in_stem:
				img.set_pixel(x, y, Color(0.9, 0.86, 0.76) if absf(x - 7.5) < 1.0 else Color(0.7, 0.66, 0.58))
	return img


## A pale diamond-shaped prism with rainbow edge pixels, ~11 px across.
func _prism() -> Image:
	var img := _new(16, 16)
	var rainbow: Array[Color] = [Color(1, 0.6, 0.6), Color(1, 0.9, 0.5), Color(0.6, 1, 0.7), Color(0.6, 0.8, 1), Color(0.9, 0.7, 1)]
	for y in 16:
		for x in 16:
			var d := absf(x - 7.5) + absf(y - 7.5) * 0.8
			if d > 5.5:
				continue
			var col := Color(0.97, 0.9, 1.0)
			if d > 4.5:
				col = rainbow[(x + y) % rainbow.size()]
			elif x < 8 and y < 8:
				col = Color(1, 1, 1)
			img.set_pixel(x, y, col)
	return img


## Translucent glowing water with a lighter ripple line.
func _water() -> Image:
	var img := _new(16, 16)
	for y in 16:
		for x in 16:
			var col := Color(0.35, 0.6, 1.0, 0.45)
			if (y == 4 and x % 6 < 3) or (y == 11 and (x + 3) % 6 < 3):
				col = Color(0.75, 0.9, 1.0, 0.6)
			img.set_pixel(x, y, col)
	return img


## Dry wood block: horizontal grain with darker knots.
func _kindling() -> Image:
	var img := _new(16, 16)
	var wood := Color(0.62, 0.42, 0.24)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for y in 16:
		for x in 16:
			var col := wood.lightened(0.12) if (y % 4 == 1) else wood
			if x == 0 or y == 0:
				col = wood.lightened(0.25)
			elif x == 15 or y == 15:
				col = wood.darkened(0.4)
			img.set_pixel(x, y, col)
	for _k in 3:
		img.set_pixel(rng.randi_range(3, 12), rng.randi_range(3, 12), wood.darkened(0.5))
	return img


## Sparkle overlay drawn over rich-vein blocks.
func _rich() -> Image:
	var img := _new(16, 16)
	for p: Vector2i in [Vector2i(3, 3), Vector2i(12, 5), Vector2i(6, 11), Vector2i(11, 12)]:
		img.set_pixelv(p, Color(1, 1, 1, 0.95))
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			img.set_pixelv(p + d, Color(0.8, 0.95, 1.0, 0.6))
	return img


## A cluster of tall glowing crystal shards filling a w x h box.
func _boss(w: int, h: int, c: Color, s: int) -> Image:
	var img := _new(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = s * 31
	var shards := 7
	for k in shards:
		var cx := w * (0.12 + 0.76 * k / float(shards - 1)) + rng.randf_range(-3.0, 3.0)
		var half_w := rng.randf_range(w * 0.07, w * 0.11)
		var top := h * (0.08 + 0.45 * absf(k - (shards - 1) * 0.5) / ((shards - 1) * 0.5)) + rng.randf_range(-4.0, 4.0)
		var tip := half_w * 1.6
		for y in range(maxi(int(top), 0), h):
			var width := half_w if y > top + tip else half_w * (y - top) / tip
			for x in range(maxi(int(cx - width), 0), mini(int(cx + width) + 1, w)):
				var u := (x - (cx - width)) / maxf(width * 2.0, 1.0)
				var col := c.lightened(0.35 * (1.0 - u)).darkened(0.25 * float(y) / h)
				if absf(x - cx) >= width - 1.0:
					col = c.darkened(0.45)
				img.set_pixel(x, y, col)
	return img


func _cracks(stage: int) -> Image:
	var img := _new(16, 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var dark := Color(0.08, 0.05, 0.06, 0.85)
	for _line in stage * 2:
		var p := Vector2(rng.randi_range(3, 12), rng.randi_range(3, 12))
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for _step in 4 + stage * 2:
			var ip := Vector2i(p.round())
			if ip.x >= 1 and ip.x <= 14 and ip.y >= 1 and ip.y <= 14:
				img.set_pixelv(ip, dark)
			dir = dir.rotated(rng.randf_range(-0.6, 0.6))
			p += dir
	return img


func _ember_core() -> Image:
	var img := _new(6, 6)
	for y in 6:
		for x in 6:
			var d := Vector2(x, y).distance_to(Vector2(2.5, 2.5))
			if d <= 1.2:
				img.set_pixel(x, y, Color(1.0, 0.97, 0.85))
			elif d <= 2.0:
				img.set_pixel(x, y, Color(1.0, 0.8, 0.35))
			elif d <= 2.8:
				img.set_pixel(x, y, Color(1.0, 0.5, 0.15))
	return img


func _ember_glow() -> Image:
	var img := _new(24, 24)
	for y in 24:
		for x in 24:
			var d := Vector2(x, y).distance_to(Vector2(11.5, 11.5)) / 12.0
			if d < 1.0:
				var a := pow(1.0 - d, 2.0) * 0.55
				img.set_pixel(x, y, Color(1.0, 0.55, 0.2, a))
	return img


func _keeper() -> Image:
	var img := _new(24, 24)
	var fur := Color(0.62, 0.45, 0.32)
	var belly := Color(0.88, 0.76, 0.6)
	var dark := Color(0.2, 0.13, 0.1)
	for y in 24:
		for x in 24:
			var p := Vector2(x, y)
			var body := p.distance_to(Vector2(11.5, 14.0))
			var ear_l := p.distance_to(Vector2(6.5, 6.0))
			var ear_r := p.distance_to(Vector2(16.5, 6.0))
			if body <= 8.5:
				img.set_pixel(x, y, dark if body > 7.6 else fur)
				if p.distance_to(Vector2(11.5, 17.0)) < 4.2:
					img.set_pixel(x, y, belly)
			elif ear_l <= 2.6 or ear_r <= 2.6:
				img.set_pixel(x, y, dark if minf(ear_l, ear_r) > 1.8 else fur)
	for e: Vector2i in [Vector2i(9, 11), Vector2i(14, 11)]:
		img.set_pixelv(e, dark)
	img.set_pixel(10, 10, Color.WHITE)
	img.set_pixel(15, 10, Color.WHITE)
	img.set_pixel(11, 13, Color(0.9, 0.5, 0.5))
	img.set_pixel(12, 13, Color(0.9, 0.5, 0.5))
	return img


func _lantern() -> Image:
	return _ascii(["..dd....", ".d..d...", "dddddd..", "dyyyyd..", "dywyyd..", "dyyyyd..", "dddddd..", "........"], 1)


func _rock(c: Color, s: int, bricks: bool) -> Image:
	var img := _new(16, 16)
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	for y in 16:
		for x in 16:
			var n := rng.randf_range(-0.08, 0.08)
			var col := c.lightened(n) if n > 0.0 else c.darkened(-n)
			if bricks and (y % 8 == 0 or (x + (8 if y >= 8 else 0)) % 16 == 0):
				col = c.darkened(0.4)
			img.set_pixel(x, y, col)
	return img


func _ascii(rows: Array, scale: int) -> Image:
	var img := _new(8, 8)
	for y in rows.size():
		var row := str(rows[y])
		for x in row.length():
			var ch := row[x]
			if PALETTE.has(ch):
				img.set_pixel(x, y, PALETTE[ch])
	if scale > 1:
		img.resize(8 * scale, 8 * scale, Image.INTERPOLATE_NEAREST)
	return img
