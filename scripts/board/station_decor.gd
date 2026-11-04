extends Node2D
## The interior of a module station, drawn once (re-drawn when the power comes back): the race skin of each section (floor and wall tints), the walls' pipes,
## cables, vents, lamps, panels, posters and signs, the floor's marks, stains and the state's debris, scorch and frost, and every fixture (station_fixtures.gd) as
## art in code, in the style of the props'. A fixture is drawn by its id (`_art_<id>` if there is one, else a block), in the section's race style when it has a
## variant, dead (dim, its screen black) or wrecked (tilted and broken) by its state. Animated bits (flickering signs, sparking panels, the pulse of a core) are
## a child's (StationDecor.Anim) and only those near the camera. Nothing here is logic: the site holds the facts.

const Fixtures = preload("res://scripts/board/station_fixtures.gd")
const Races = preload("res://scripts/board/station_races.gd")
const Glyph = preload("res://scripts/board/station_glyph.gd")
const StationGen = preload("res://scripts/board/station_gen.gd")
const Art = preload("res://scripts/board/station_art.gd")

const CELL := 32.0

var site
var _defs := {}
var _anim: Array = []  ## [{kind, pos (px), seed, room, size}]: what the child animates
var _anim_node: Node2D
var _font: Font


func setup(p_site) -> void:
	site = p_site
	_defs = Fixtures.defs()
	_font = ThemeDB.fallback_font
	_anim_node = AnimLayer.new()
	_anim_node.decor = self
	add_child(_anim_node)
	rebuild()


## Draw it all again (the generator was repaired: dead fixtures are alive, signs lit).
func rebuild() -> void:
	_anim.clear()
	queue_redraw()


func _powered(rid: int) -> bool:
	return bool(site.modules[int(site.rooms[rid]["module"])]["powered"])


func _skin(rid: int) -> Dictionary:
	return Races.skin(str(site.modules[int(site.rooms[rid]["module"])].get("race", "human")))


func _draw() -> void:
	if site == null:
		return
	for r in site.rooms:
		if r["purpose"] == "gone" or not r.has("module"):
			continue
		var sk := _skin(r["id"])
		var rect: Rect2i = r["rect"]
		var rr := Rect2(Vector2(rect.position) * CELL, Vector2(rect.size) * CELL)
		draw_rect(rr, Color(Color(str(sk["floor"])), 0.13))
		var m: Dictionary = site.modules[int(r["module"])]
		if site.heat_of(r["id"]) >= float(StationGen.config().get("heat", {}).get("hot_visible", 55.0)):  # a hot room: an orange tint and a shimmer over it
			draw_rect(rr, Color(1.0, 0.45, 0.12, 0.11))
			_anim.append({"kind": "shimmer", "pos": rr.get_center(), "rect": rr, "seed": int(r["id"]), "room": r["id"]})
		elif str(m["climate"]) == "cold" and bool(m["powered"]):  # a cool section: a pale blue cast (a look only)
			draw_rect(rr, Color(0.6, 0.85, 1.0, 0.07))
	_draw_wall_tints()
	for d in site.dressing:
		if str(d["kind"]) in ["stain", "scuff", "arrow", "lane", "debris", "scorch", "clutter", "frost", "hazard"] and (str(d["kind"]) != "scorch" or site.room_of.has(Vector2i(d["cell"]))):
			_floor_item(d)
	for d in site.dressing:
		if not (str(d["kind"]) in ["stain", "scuff", "arrow", "lane", "debris", "clutter", "frost", "hazard"]) and not (str(d["kind"]) == "scorch" and site.room_of.has(Vector2i(d["cell"]))):
			_wall_item(d)
	for f in site.fixtures:
		_fixture(f)


## The wall cells of each module in its race's tint.
func _draw_wall_tints() -> void:
	for i in site.modules.size():
		var m: Dictionary = site.modules[i]
		var col := Color(str(Races.skin(str(m.get("race", "human")))["wall"]), 0.38)
		var rect: Rect2i = m["rect"]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2i(x, y)
				if site.grid.get_tile(c) == "wall" and not site.room_of.has(c):
					draw_rect(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)), col)


# --- the floor ---------------------------------------------------------------------------------------------------------

func _floor_item(d: Dictionary) -> void:
	var c: Vector2i = d["cell"]
	var o := Vector2(c) * CELL
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d["seed"])
	match str(d["kind"]):
		"stain":
			for k in 5:
				draw_circle(o + Vector2(rng.randf_range(8, 24), rng.randf_range(8, 24)), rng.randf_range(3, 8), Color(0.05, 0.05, 0.06, 0.16))
		"scuff":
			for k in 3:
				var a := o + Vector2(rng.randf_range(2, 30), rng.randf_range(2, 30))
				draw_line(a, a + Vector2(rng.randf_range(-9, 9), rng.randf_range(-6, 6)), Color(1, 1, 1, 0.07), 1.5)
		"arrow":
			var dir := Vector2(d["dir"])
			var mid := o + Vector2(CELL, CELL) / 2.0
			var side := Vector2(-dir.y, dir.x)
			var col := Color(0.95, 0.82, 0.2, 0.32)
			draw_colored_polygon(PackedVector2Array([mid + dir * 11.0, mid - dir * 4.0 + side * 9.0, mid - dir * 4.0 - side * 9.0]), col)
			draw_line(mid - dir * 4.0, mid - dir * 13.0, col, 4.0)
		"lane":
			var along := Vector2(absf(d["dir"].y), absf(d["dir"].x))
			draw_line(o + Vector2(CELL, CELL) / 2.0 - along * 14.0, o + Vector2(CELL, CELL) / 2.0 + along * 14.0, Color(0.95, 0.95, 0.9, 0.22), 3.0)
		"hazard":
			var sz := Vector2(d["size"]) * CELL
			_stripe_frame(Rect2(o - Vector2(5, 5), sz + Vector2(10, 10)))
		"debris":
			for k in 4:
				var p := o + Vector2(rng.randf_range(5, 27), rng.randf_range(5, 27))
				var pts := PackedVector2Array()
				for q in 5:
					pts.append(p + Vector2.from_angle(TAU * float(q) / 5.0 + rng.randf()) * rng.randf_range(2.5, 6.0))
				draw_colored_polygon(pts, Color(0.33, 0.31, 0.29) if k % 2 == 0 else Color(0.22, 0.22, 0.24))
		"scorch":
			for k in 4:
				draw_circle(o + Vector2(rng.randf_range(6, 26), rng.randf_range(6, 26)), rng.randf_range(5, 11), Color(0.02, 0.02, 0.02, 0.28))
		"clutter":
			for k in 3:  # (papers and a spilt box)
				var p2 := o + Vector2(rng.randf_range(4, 22), rng.randf_range(4, 22))
				draw_rect(Rect2(p2, Vector2(rng.randf_range(5, 9), rng.randf_range(4, 7))), Color(0.82, 0.8, 0.7, 0.85))
		"frost":
			for k in 5:  # (a corner furred with ice)
				draw_circle(o + Vector2(CELL, CELL) / 2.0 + Vector2(rng.randf_range(-15, 15), rng.randf_range(-15, 15)), rng.randf_range(5, 11), Color(0.8, 0.92, 1.0, 0.2))


func _stripe_frame(r: Rect2) -> void:
	var edges := [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var n := int(a.distance_to(b) / 10.0)
		for k in n:
			var p0 := a.lerp(b, float(k) / float(n))
			var p1 := a.lerp(b, float(k + 1) / float(n))
			draw_line(p0, p1, Color(0.95, 0.78, 0.1, 0.5) if k % 2 == 0 else Color(0.08, 0.08, 0.08, 0.5), 4.0)


# --- the walls ---------------------------------------------------------------------------------------------------------

func _wall_item(d: Dictionary) -> void:
	var rid := int(d["room"])
	var sk := _skin(rid)
	var powered := _powered(rid)
	var dir := Vector2(d["dir"])
	var along := Vector2(absf(dir.y), absf(dir.x))
	var c: Vector2i = d["cell"]
	var o := Vector2(c) * CELL + Vector2(CELL, CELL) / 2.0  # the middle of the wall cell
	var face := o + dir * 9.0  # toward the room: the face of the wall
	var len := int(d["len"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d["seed"])
	var a0 := face - along * CELL / 2.0
	var a1 := face + along * (float(len) - 0.5) * CELL
	match str(d["kind"]):
		"pipe":
			var col := Color(str(sk["lamp"])).darkened(0.35) if site.rooms[rid]["purpose"] in ["reactor", "power", "water", "hangar"] else Color("#6e7684")
			draw_line(a0, a1, Color(0, 0, 0, 0.5), 7.0)
			draw_line(a0, a1, col, 5.0)
			draw_line(a0 + dir * -1.0, a1 + dir * -1.0, col.lightened(0.3), 1.5)
			for k in len + 1:
				var j := a0 + along * (float(k) * CELL)
				draw_line(j - dir * 2.0 - along * 0.0, j + dir * 2.0, Color(0.15, 0.16, 0.18), 3.0)
		"cable":
			var pts := PackedVector2Array()
			var steps := 10
			for k in steps + 1:
				var t := float(k) / float(steps)
				pts.append(a0.lerp(a1, t) + dir * (2.0 + 5.0 * sin(t * PI)))
			draw_polyline(pts, Color(0.08, 0.08, 0.1), 3.5)
			draw_polyline(pts, Color(0.55, 0.2, 0.18) if int(d["seed"]) % 2 == 0 else Color(0.2, 0.35, 0.55), 1.5)
		"vent":
			var vr := Rect2(face - Vector2(10, 10) + dir * 0.0, Vector2(20, 20))
			draw_rect(vr, Color(0.12, 0.13, 0.15))
			for k in 4:
				var s0 := vr.position + (Vector2(2.0, 4.0 + 4.0 * k) if along.x > 0.0 else Vector2(4.0 + 4.0 * k, 2.0))
				draw_line(s0, s0 + along * 16.0 if along.x > 0.0 else s0 + Vector2(0, 16), Color(0.45, 0.48, 0.52), 1.5)
		"lamp":
			var lc := Color(str(sk["lamp"]))
			draw_rect(Rect2(face - Vector2(7, 7) - dir * 2.0, Vector2(14, 14)).intersection(Rect2(Vector2(c) * CELL, Vector2(CELL, CELL))), Color(0.1, 0.1, 0.12))
			if powered:
				draw_circle(face, 4.5, lc)
				draw_circle(face, 2.0, Color(1, 1, 1, 0.9))
			else:
				draw_circle(face, 4.0, Color(0.16, 0.16, 0.18))
		"panel":
			var pr := Rect2(face - Vector2(9, 9), Vector2(18 + (CELL if len > 1 else 0.0) * along.x, 18 + (CELL if len > 1 else 0.0) * along.y))
			draw_rect(pr, Color(0.18, 0.2, 0.24))
			draw_rect(pr, Color(0.05, 0.05, 0.06), false, 1.5)
			for k in 3:
				var dc := Color(0.3, 1.0, 0.5) if powered and k != 1 else (Color(1.0, 0.7, 0.2) if powered else Color(0.25, 0.1, 0.1))
				draw_circle(pr.position + Vector2(5.0 + 5.0 * k, 5.0), 1.8, dc)
			if int(d["seed"]) % 3 == 0 and site.state != "operational":
				_anim.append({"kind": "spark", "pos": pr.get_center(), "seed": int(d["seed"]), "room": rid})
		"poster":
			var pc := Color.from_hsv(float(int(d["seed"]) % 100) / 100.0, 0.35, 0.8)
			var pr2 := Rect2(face - Vector2(7, 10), Vector2(14, 20))
			draw_rect(pr2, Color(pc, 0.9) if powered or site.state == "operational" else Color(pc.darkened(0.4), 0.8))
			draw_rect(pr2, Color(0, 0, 0, 0.6), false, 1.0)
			draw_line(pr2.position + Vector2(3, 6), pr2.position + Vector2(11, 6), Color(1, 1, 1, 0.5), 1.5)
			draw_line(pr2.position + Vector2(3, 11), pr2.position + Vector2(9, 11), Color(1, 1, 1, 0.35), 1.5)
		"sign":  # (a plate with the race's glyph and the room's name; on a side wall the text runs up or down it)
			var cen := (a0 + a1) / 2.0
			var w := float(len) * CELL - 6.0
			var lit := powered
			var col2 := Color(str(sk["lamp"])) if lit else Color(0.3, 0.3, 0.32)
			var vertical := along.y > 0.0
			if vertical:
				draw_set_transform(cen, PI / 2.0 if dir.x < 0.0 else -PI / 2.0, Vector2.ONE)
			else:
				draw_set_transform(cen, 0.0, Vector2.ONE)
			var box := Rect2(Vector2(-w / 2.0, -9.0), Vector2(w, 18.0))
			draw_rect(box, Color(0.04, 0.05, 0.07))
			draw_rect(box, col2 if lit else Color(0.2, 0.2, 0.22), false, 1.5)
			Glyph.draw(self, str(sk["glyph"]), box.position + Vector2(9, 9), 5.0, col2)
			draw_string(_font, box.position + Vector2(17, 13), str(d["word"]).left(12), HORIZONTAL_ALIGNMENT_LEFT, w - 19.0, 9, col2)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if lit and site.state == "half":
				var asz := Vector2(w, 18.0) if not vertical else Vector2(18.0, w)
				_anim.append({"kind": "sign", "pos": cen, "size": asz, "seed": int(d["seed"]), "room": rid})
		"scorch":
			for k in 3:
				draw_circle(face + along * rng.randf_range(-10, 10) + dir * rng.randf_range(0, 8), rng.randf_range(6, 12), Color(0.02, 0.02, 0.02, 0.35))


# --- the fixtures -----------------------------------------------------------------------------------------------------

func _fixture(f: Dictionary) -> void:
	var def: Dictionary = _defs[f["fixture"]]
	var rid := int(f["room"])
	var sk := _skin(rid)
	var race := str(site.modules[int(site.rooms[rid]["module"])].get("race", "human"))
	var r := Rect2(Vector2(f["cell"]) * CELL, Vector2(f["size"]) * CELL)
	var base := Color(str(def["color"]))
	if race != "human":
		base = base.lerp(Color(str(sk["wall"])).lightened(0.25), 0.38)
	var dead: bool = bool(f["dead"])
	var glow := Color(str(f["glow"])) if f["glow"] != "" else Color(0, 0, 0, 0)
	if str(sk["style"]) != "plain" and f["glow"] != "" and not dead:
		glow = glow.lerp(Color(str(sk["lamp"])), 0.35)
	if dead:
		base = base.darkened(0.3)
	var wreck: bool = bool(f["wreck"])
	if wreck:  # (toppled: tipped over, a little off its place, broken)
		var rot := 0.18 + 0.1 * float(int(f["id"]) % 3)
		draw_set_transform(r.get_center() + Vector2(3, 4), rot * (1.0 if f["id"] % 2 == 0 else -1.0), Vector2.ONE)
		r = Rect2(-r.size / 2.0, r.size)
		base = base.darkened(0.25)
	var item := {"r": r.grow(-3.0), "base": base, "glow": glow, "dead": dead, "dir": Vector2(f["dir"]), "style": str(sk["style"]), "variant": str(f["variant"]), "lamp": Color(str(sk["lamp"])), "id": int(f["id"]), "powered": not dead}
	if f["blocks"] or def.get("glow", "") != "":
		draw_rect(Rect2(item["r"].position + Vector2(3, 4), item["r"].size), Color(0, 0, 0, 0.3))  # (a shadow)
	var fn := "_art_" + str(f["fixture"])
	if has_method(fn):
		call(fn, item)
	elif Art.has_art(str(f["fixture"])):  # (the race rooms' fixtures: station_art.gd)
		Callable(Art, "a_" + str(f["fixture"])).call(self, item)
	else:
		_block(item, bool(def.get("screen", false)))
	if str(item["variant"]) != "" and not wreck:
		_race_mark(item)
	if wreck:
		draw_line(item["r"].position + item["r"].size * 0.2, item["r"].position + item["r"].size * 0.7, Color(0, 0, 0, 0.7), 2.0)
		draw_circle(item["r"].position + item["r"].size * Vector2(0.75, 0.3), 3.0, Color(0.9, 0.8, 0.2, 0.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if (str(f["fixture"]) in ["reactor_core", "forge_furnace", "crystal_spire", "holo_table", "generator", "shuttle"] or bool(def.get("pulse", false))) and not dead and not wreck:
		_anim.append({"kind": "pulse", "pos": r.get_center(), "size": r.size, "color": glow, "seed": int(f["id"]), "room": rid})


## What a race's art adds to the plain block, by its style: hex cells, organic bulges, crystal facets, forge seams, tent stripes, bolts, stone cracks, reeds, hoops.
func _race_mark(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c: Color = it["lamp"]
	var dark := Color(0, 0, 0, 0.45)
	match str(it["style"]):
		"hex":
			for k in 2:
				var p := r.position + r.size * Vector2(0.3 + 0.4 * k, 0.5)
				var pts := PackedVector2Array()
				for q in 6:
					pts.append(p + Vector2.from_angle(TAU * float(q) / 6.0) * minf(r.size.x, r.size.y) * 0.18)
				draw_polyline(pts + PackedVector2Array([pts[0]]), Color(c, 0.7), 1.5)
		"organic":
			for k in 3:
				draw_circle(r.position + r.size * Vector2(0.2 + 0.3 * k, 0.3 + 0.2 * float(k % 2)), 3.0, Color(c, 0.75))
		"facet":
			draw_colored_polygon(PackedVector2Array([r.get_center() + Vector2(0, -7), r.get_center() + Vector2(5, 0), r.get_center() + Vector2(0, 7), r.get_center() + Vector2(-5, 0)]), Color(c, 0.6))
		"forge":
			draw_line(r.position + Vector2(3, r.size.y * 0.5), r.end - Vector2(3, r.size.y * 0.5), Color(1.0, 0.5, 0.15, 0.8), 2.0)
		"tent":
			var n := maxi(int(r.size.x / 8.0), 2)
			for k in n:
				if k % 2 == 0:
					draw_rect(Rect2(r.position.x + r.size.x * float(k) / float(n), r.position.y, r.size.x / float(n), 5.0), Color(c, 0.75))
		"bolt":
			for p in [r.position + Vector2(3, 3), Vector2(r.end.x - 3, r.position.y + 3), Vector2(r.position.x + 3, r.end.y - 3), r.end - Vector2(3, 3)]:
				draw_circle(p, 1.6, Color(0.9, 0.9, 0.9, 0.7))
		"stone":
			draw_line(r.position + r.size * Vector2(0.2, 0.1), r.position + r.size * Vector2(0.5, 0.6), dark, 1.5)
			draw_line(r.position + r.size * Vector2(0.5, 0.6), r.position + r.size * Vector2(0.4, 0.95), dark, 1.5)
		"reed":
			for k in 3:
				draw_line(r.position + r.size * Vector2(0.2 + 0.3 * k, 0.9), r.position + r.size * Vector2(0.25 + 0.3 * k, 0.15), Color(c, 0.7), 1.5)
		"barrel":
			draw_line(r.position + Vector2(2, r.size.y * 0.35), Vector2(r.end.x - 2, r.position.y + r.size.y * 0.35), dark, 2.0)
			draw_line(r.position + Vector2(2, r.size.y * 0.7), Vector2(r.end.x - 2, r.position.y + r.size.y * 0.7), dark, 2.0)


## The plain block: a shadowed body with a lit top edge, its dark outline, and a screen on the side that faces the room when it has one.
func _block(it: Dictionary, screen: bool) -> void:
	var r: Rect2 = it["r"]
	var base: Color = it["base"]
	draw_rect(r, base)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 4.0)), base.lightened(0.18))
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 3.0), Vector2(r.size.x, 3.0)), base.darkened(0.25))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	if screen:
		var dir: Vector2 = it["dir"]
		var sr := _screen_rect(r, dir)
		draw_rect(sr, Color(0.03, 0.04, 0.05))
		if not it["dead"]:
			draw_rect(sr.grow(-1.5), Color(it["glow"], 0.9))
			draw_line(sr.position + Vector2(2, sr.size.y * 0.35), sr.end - Vector2(2, sr.size.y * 0.65), Color(1, 1, 1, 0.5), 1.0)
		else:
			draw_line(sr.position + Vector2(1, 1), sr.end - Vector2(1, 1), Color(0.2, 0.2, 0.22), 1.0)


func _screen_rect(r: Rect2, dir: Vector2) -> Rect2:
	var t := 6.0
	if absf(dir.y) > 0.0:
		var h := minf(r.size.y * 0.45, 12.0)
		var y: float = r.position.y + 3.0 if dir.y < 0.0 else r.end.y - h - 3.0
		return Rect2(r.position.x + 4.0, y, maxf(r.size.x - 8.0, t), h)
	var w := minf(r.size.x * 0.45, 12.0)
	var x: float = r.position.x + 3.0 if dir.x < 0.0 else r.end.x - w - 3.0
	return Rect2(x, r.position.y + 4.0, w, maxf(r.size.y - 8.0, t))


func _art_reactor_core(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var rad := minf(r.size.x, r.size.y) / 2.0
	draw_rect(r, it["base"].darkened(0.3))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	draw_circle(c, rad * 0.82, Color(0.14, 0.14, 0.16))
	draw_circle(c, rad * 0.66, Color(0.28, 0.2, 0.12) if it["dead"] else Color(it["glow"], 0.35))
	draw_circle(c, rad * 0.45, Color(0.2, 0.18, 0.16) if it["dead"] else Color(it["glow"], 0.8))
	draw_circle(c, rad * 0.22, Color(0.3, 0.3, 0.3) if it["dead"] else Color(1, 0.95, 0.8))
	for k in 8:
		var a := TAU * float(k) / 8.0
		draw_line(c + Vector2.from_angle(a) * rad * 0.7, c + Vector2.from_angle(a) * rad * 0.95, Color(0.55, 0.56, 0.6), 3.0)


func _art_forge_furnace(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, it["base"].darkened(0.4))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	var m := Rect2(r.position + r.size * Vector2(0.25, 0.3), r.size * Vector2(0.5, 0.45))
	draw_rect(m, Color(0.05, 0.03, 0.03))
	if not it["dead"]:
		draw_rect(m.grow(-3.0), Color(1.0, 0.45, 0.1, 0.9))
		draw_rect(Rect2(m.position + Vector2(5, 8), m.size - Vector2(10, 12)), Color(1.0, 0.85, 0.4, 0.9))
	draw_rect(Rect2(r.position + Vector2(r.size.x * 0.4, 2), Vector2(r.size.x * 0.2, r.size.y * 0.22)), Color(0.15, 0.15, 0.16))  # (the stack)


func _art_generator(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, it["base"])
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	var c := r.get_center()
	draw_circle(c, minf(r.size.x, r.size.y) * 0.3, Color(0.18, 0.18, 0.2))
	draw_circle(c, minf(r.size.x, r.size.y) * 0.18, Color(0.45, 0.9, 0.5) if not it["dead"] else Color(0.55, 0.15, 0.12))
	for k in int(r.size.x / 8.0):
		draw_rect(Rect2(r.position.x + 3.0 + 8.0 * k, r.end.y - 7.0, 4.0, 4.0), Color(0.95, 0.8, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.1))


func _art_stall(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var dir: Vector2 = it["dir"]
	draw_rect(r, it["base"].darkened(0.1))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	var awn: Rect2 = Rect2(r.position, Vector2(r.size.x, r.size.y * 0.42)) if absf(dir.y) > 0.0 else Rect2(r.position, Vector2(r.size.x * 0.42, r.size.y))
	var n := 6
	for k in n:
		var part: Rect2 = Rect2(awn.position + Vector2(awn.size.x * float(k) / float(n), 0), Vector2(awn.size.x / float(n), awn.size.y)) if absf(dir.y) > 0.0 else Rect2(awn.position + Vector2(0, awn.size.y * float(k) / float(n)), Vector2(awn.size.x, awn.size.y / float(n)))
		draw_rect(part, it["lamp"].darkened(0.1) if k % 2 == 0 else Color(0.92, 0.9, 0.84))
	for k in 5:  # goods
		draw_circle(r.position + r.size * Vector2(0.15 + 0.17 * float(k), 0.78), 3.2, Color.from_hsv(float(k) * 0.19, 0.55, 0.85))


func _art_bunk(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var long_x := r.size.x >= r.size.y
	draw_rect(r, it["base"].darkened(0.25))
	draw_rect(r.grow(-3.0), it["base"].lightened(0.35))
	var pillow := Rect2(r.position + (Vector2(5, 5) if long_x else Vector2(5, 5)), Vector2(9, r.size.y - 10) if long_x else Vector2(r.size.x - 10, 9))
	draw_rect(pillow, Color(0.9, 0.92, 0.94))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	var blanket := Rect2(r.position + (Vector2(16, 3) if long_x else Vector2(3, 16)), Vector2(r.size.x - 19, r.size.y - 6) if long_x else Vector2(r.size.x - 6, r.size.y - 19))
	draw_rect(blanket, it["base"].darkened(0.1))


func _art_cell_bunk(it: Dictionary) -> void:
	_art_bunk(it)


func _art_table(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, Color(0.45, 0.33, 0.22))
	draw_rect(r.grow(-2.0), it["base"])
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	draw_circle(r.position + r.size * Vector2(0.3, 0.4), 3.0, Color(0.9, 0.9, 0.85))
	draw_circle(r.position + r.size * Vector2(0.7, 0.6), 3.0, Color(0.9, 0.9, 0.85))


func _art_long_table(it: Dictionary) -> void:
	_art_table(it)
	var r: Rect2 = it["r"]
	for k in int(r.size.x / 28.0):
		draw_circle(r.position + Vector2(16.0 + 28.0 * k, r.size.y / 2.0), 3.0, Color(0.9, 0.9, 0.85))


func _slats(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, it["base"])
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	if r.size.x >= r.size.y:
		for k in int(r.size.x / 8.0):
			draw_line(Vector2(r.position.x + 5.0 + 8.0 * k, r.position.y + 2), Vector2(r.position.x + 5.0 + 8.0 * k, r.end.y - 2), Color(0, 0, 0, 0.3), 1.5)
	else:
		for k in int(r.size.y / 8.0):
			draw_line(Vector2(r.position.x + 2, r.position.y + 5.0 + 8.0 * k), Vector2(r.end.x - 2, r.position.y + 5.0 + 8.0 * k), Color(0, 0, 0, 0.3), 1.5)


func _art_bench(it: Dictionary) -> void:
	_slats(it)


func _art_long_bench(it: Dictionary) -> void:
	_slats(it)


func _art_pew(it: Dictionary) -> void:
	_slats(it)


func _art_resonance_bench(it: Dictionary) -> void:
	_slats(it)


func _plants(it: Dictionary, soil: Color, leaf: Color) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, Color(0.3, 0.3, 0.32))
	draw_rect(r.grow(-2.0), soil)
	var n := maxi(int(maxf(r.size.x, r.size.y) / 12.0), 2)
	for k in n:
		var p := r.position + (Vector2(r.size.x * (float(k) + 0.5) / float(n), r.size.y / 2.0) if r.size.x >= r.size.y else Vector2(r.size.x / 2.0, r.size.y * (float(k) + 0.5) / float(n)))
		draw_circle(p, 5.5, leaf.darkened(0.2))
		draw_circle(p + Vector2(-1, -1), 3.8, leaf)
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)


func _art_planter(it: Dictionary) -> void:
	_plants(it, Color(0.25, 0.17, 0.1), Color(0.3, 0.7, 0.3) if not it["dead"] else Color(0.45, 0.4, 0.25))


func _art_grow_bed(it: Dictionary) -> void:
	_plants(it, Color(0.2, 0.15, 0.1), Color(0.4, 0.85, 0.3) if not it["dead"] else Color(0.4, 0.38, 0.25))
	if not it["dead"]:
		var r: Rect2 = it["r"]
		draw_rect(Rect2(r.position + Vector2(0, -2), Vector2(r.size.x, 2.0)), Color(it["glow"], 0.55))


func _art_holo_table(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, Color(0.14, 0.17, 0.22))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	var c := r.get_center()
	if not it["dead"]:
		draw_circle(c, minf(r.size.x, r.size.y) * 0.34, Color(it["glow"], 0.35))
		draw_arc(c, minf(r.size.x, r.size.y) * 0.34, 0.0, TAU, 28, Color(it["glow"], 0.9), 2.0, true)
		draw_arc(c, minf(r.size.x, r.size.y) * 0.18, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 1.5, true)
	else:
		draw_arc(c, minf(r.size.x, r.size.y) * 0.34, 0.0, TAU, 28, Color(0.25, 0.27, 0.3), 2.0, true)


func _art_shuttle(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	var long_x := r.size.x >= r.size.y
	var hull: Color = it["base"]
	var pts := PackedVector2Array()
	if long_x:
		pts = PackedVector2Array([Vector2(r.end.x, c.y), Vector2(r.end.x - 14, r.position.y + 6), Vector2(r.position.x + 10, r.position.y), Vector2(r.position.x, r.position.y + 10), Vector2(r.position.x, r.end.y - 10), Vector2(r.position.x + 10, r.end.y), Vector2(r.end.x - 14, r.end.y - 6)])
	else:
		pts = PackedVector2Array([Vector2(c.x, r.position.y), Vector2(r.end.x - 6, r.position.y + 14), Vector2(r.end.x, r.end.y - 10), Vector2(r.end.x - 10, r.end.y), Vector2(r.position.x + 10, r.end.y), Vector2(r.position.x, r.end.y - 10), Vector2(r.position.x + 6, r.position.y + 14)])
	draw_colored_polygon(pts, hull)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.04, 0.05, 0.07), 2.5)
	var cock := Rect2(c + (Vector2(r.size.x * 0.22, -8) if long_x else Vector2(-8, -r.size.y * 0.3)), Vector2(18, 16) if long_x else Vector2(16, 18))
	draw_rect(cock, Color(0.2, 0.3, 0.4) if it["dead"] else Color(0.5, 0.8, 1.0, 0.9))
	draw_line(r.position + Vector2(r.size.x * 0.2, r.size.y * 0.5), r.position + Vector2(r.size.x * 0.55, r.size.y * 0.5), Color(0, 0, 0, 0.4), 2.0)


func _pool(it: Dictionary, deep: Color) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, Color(0.2, 0.2, 0.22))
	draw_rect(r.grow(-3.0), deep.darkened(0.3) if it["dead"] else deep)
	for k in 3:
		draw_arc(r.get_center() + Vector2(float(k - 1) * r.size.x * 0.18, 0), 4.0 + 3.0 * k, 0.0, TAU, 16, Color(1, 1, 1, 0.18), 1.5, true)
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)


func _art_spore_pool(it: Dictionary) -> void:
	_pool(it, Color(0.4, 0.75, 0.3))
	var r: Rect2 = it["r"]
	for k in 6:
		draw_circle(r.position + r.size * Vector2(0.15 + 0.14 * float(k), 0.3 + 0.4 * float((k * 7) % 3) / 2.0), 3.0, Color(0.85, 1.0, 0.6, 0.85))


func _art_quench_pool(it: Dictionary) -> void:
	_pool(it, Color(0.85, 0.35, 0.12))


func _art_reclaim_tank(it: Dictionary) -> void:
	_pool(it, Color(0.25, 0.55, 0.85))


func _art_water_tank(it: Dictionary) -> void:
	_pool(it, Color(0.3, 0.6, 0.85))


func _art_crystal_spire(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	draw_rect(r, Color(0.16, 0.14, 0.22))
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		var tip := c + Vector2.from_angle(a) * (r.size.x * 0.4) * (0.65 + 0.35 * float(k % 2))
		draw_colored_polygon(PackedVector2Array([c + Vector2.from_angle(a + 1.2) * 7.0, tip, c + Vector2.from_angle(a - 1.2) * 7.0]), Color(it["glow"], 0.9) if not it["dead"] else Color(0.35, 0.3, 0.4))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r.size.y * 0.4), c + Vector2(9, 0), c + Vector2(0, r.size.y * 0.38), c + Vector2(-9, 0)]), Color(1, 1, 1, 0.75) if not it["dead"] else Color(0.5, 0.48, 0.55))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)


func _art_crystal_cluster(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	for k in 3:
		var a := -1.2 + 1.2 * float(k)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 8), c + Vector2(sin(a) * 9.0, -9.0 - 3.0 * float(k % 2)), c + Vector2(4, 8)]), Color(it["glow"], 0.9) if not it["dead"] else Color(0.35, 0.3, 0.4))


func _art_glow_cap(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	draw_rect(Rect2(c + Vector2(-2, 0), Vector2(4, 9)), Color(0.8, 0.8, 0.7))
	draw_circle(c + Vector2(0, -2), 8.0, Color(it["glow"], 0.9) if not it["dead"] else Color(0.35, 0.4, 0.3))
	draw_circle(c + Vector2(-2, -4), 2.5, Color(1, 1, 1, 0.6))


func _art_cargo_stack(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, it["base"])
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	var half := r.size / 2.0
	for k in 2:
		for j in 2:
			var q := Rect2(r.position + Vector2(half.x * k, half.y * j), half).grow(-2.0)
			draw_rect(q, it["base"].lightened(0.1 * float((k + j) % 2)))
			draw_line(q.position, q.end, Color(0, 0, 0, 0.3), 1.5)


func _art_shipping_container(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, it["base"])
	for k in int(maxf(r.size.x, r.size.y) / 6.0):
		if r.size.x >= r.size.y:
			draw_line(Vector2(r.position.x + 4.0 + 6.0 * k, r.position.y + 2), Vector2(r.position.x + 4.0 + 6.0 * k, r.end.y - 2), Color(0, 0, 0, 0.25), 1.5)
		else:
			draw_line(Vector2(r.position.x + 2, r.position.y + 4.0 + 6.0 * k), Vector2(r.end.x - 2, r.position.y + 4.0 + 6.0 * k), Color(0, 0, 0, 0.25), 1.5)
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)


func _art_stock_crates(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var n := 2 if r.size.x >= r.size.y else 1
	for k in maxi(int(maxf(r.size.x, r.size.y) / CELL), 1):
		var q := Rect2(r.position + (Vector2(CELL * k, 0) if r.size.x >= r.size.y else Vector2(0, CELL * k)), Vector2(CELL - 6.0, CELL - 6.0)) if n == 2 or true else r
		draw_rect(q, it["base"])
		draw_rect(q, Color(0.04, 0.05, 0.07), false, 2.0)
		draw_line(q.position, q.end, Color(0, 0, 0, 0.35), 1.5)


func _art_shelf_rack(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(r, it["base"].darkened(0.2))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	var long_x := r.size.x >= r.size.y
	for k in 3:
		var p := r.position + (Vector2(4, 5.0 + 6.0 * k) if long_x else Vector2(5.0 + 6.0 * k, 4))
		var q := (Vector2(r.size.x - 8, 3) if long_x else Vector2(3, r.size.y - 8))
		draw_rect(Rect2(p, q), it["base"].lightened(0.3))
		for j in 4:
			var item_p := p + (Vector2(5.0 + (r.size.x - 14.0) * float(j) / 3.0, -3) if long_x else Vector2(-3, 5.0 + (r.size.y - 14.0) * float(j) / 3.0))
			draw_rect(Rect2(item_p, Vector2(4, 4)), Color.from_hsv(float(k * 4 + j) * 0.083, 0.5, 0.8))


func _art_scanner(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	draw_rect(r, it["base"].darkened(0.1))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	draw_circle(c, minf(r.size.x, r.size.y) * 0.34, Color(0.08, 0.1, 0.12))
	draw_arc(c, minf(r.size.x, r.size.y) * 0.34, 0.0, TAU, 24, Color(it["glow"], 0.9) if not it["dead"] else Color(0.3, 0.32, 0.34), 3.0, true)


func _art_scanner_arch(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var col: Color = Color(it["glow"], 0.9) if not it["dead"] else Color(0.3, 0.3, 0.32)
	if r.size.x >= r.size.y:
		draw_rect(Rect2(r.position, Vector2(6, r.size.y)), Color(0.35, 0.36, 0.4))
		draw_rect(Rect2(Vector2(r.end.x - 6, r.position.y), Vector2(6, r.size.y)), Color(0.35, 0.36, 0.4))
		draw_line(r.position + Vector2(6, r.size.y / 2.0), Vector2(r.end.x - 6, r.position.y + r.size.y / 2.0), Color(col, 0.55), 2.0)
	else:
		draw_rect(Rect2(r.position, Vector2(r.size.x, 6)), Color(0.35, 0.36, 0.4))
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - 6), Vector2(r.size.x, 6)), Color(0.35, 0.36, 0.4))
		draw_line(r.position + Vector2(r.size.x / 2.0, 6), Vector2(r.position.x + r.size.x / 2.0, r.end.y - 6), Color(col, 0.55), 2.0)


func _art_curtain(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.3), Vector2(r.size.x, r.size.y * 0.4)), Color(it["base"], 0.75))
	for k in int(maxf(r.size.x, r.size.y) / 6.0):
		draw_line(r.position + Vector2(3.0 + 6.0 * k, r.size.y * 0.3), r.position + Vector2(3.0 + 6.0 * k, r.size.y * 0.7), Color(0, 0, 0, 0.2), 1.0)


func _art_kiosk(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	var c := r.get_center()
	draw_rect(r, it["base"].darkened(0.15))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 2.0)
	draw_rect(Rect2(c - Vector2(14, 14), Vector2(28, 28)), Color(0.05, 0.06, 0.08))
	if not it["dead"]:
		draw_rect(Rect2(c - Vector2(11, 11), Vector2(22, 22)), Color(it["glow"], 0.85))
		draw_line(c + Vector2(-7, -3), c + Vector2(7, -3), Color(1, 1, 1, 0.6), 1.5)
		draw_line(c + Vector2(-7, 3), c + Vector2(3, 3), Color(1, 1, 1, 0.45), 1.5)


func _art_anvil(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_rect(Rect2(r.position + Vector2(2, 6), r.size - Vector2(4, 12)), Color(0.28, 0.28, 0.32))
	draw_rect(Rect2(r.position + Vector2(0, 3), Vector2(r.size.x, 7)), Color(0.4, 0.4, 0.45))
	draw_rect(r, Color(0.04, 0.05, 0.07), false, 1.5)


func _art_fuel_drum(it: Dictionary) -> void:
	var c: Vector2 = it["r"].get_center()
	draw_circle(c, 11.0, it["base"])
	draw_arc(c, 11.0, 0.0, TAU, 20, Color(0.04, 0.05, 0.07), 2.0, true)
	draw_arc(c, 6.0, 0.0, TAU, 14, Color(0, 0, 0, 0.35), 1.5, true)


func _art_wreckage(it: Dictionary) -> void:
	var r: Rect2 = it["r"]
	draw_colored_polygon(PackedVector2Array([r.position + Vector2(2, 8), r.position + Vector2(r.size.x * 0.4, 0), r.position + Vector2(r.size.x * 0.9, 6), r.end - Vector2(2, 4), r.position + Vector2(r.size.x * 0.3, r.size.y - 2)]), Color(0.3, 0.3, 0.33))
	draw_line(r.position + Vector2(6, 10), r.end - Vector2(8, 8), Color(0.12, 0.12, 0.14), 2.0)
	draw_line(r.position + Vector2(r.size.x * 0.6, 4), r.position + Vector2(r.size.x * 0.5, r.size.y - 6), Color(0.55, 0.3, 0.2), 2.0)


# --- the animated bits --------------------------------------------------------------------------------------------------

class AnimLayer extends Node2D:
	var decor
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()

	func _draw() -> void:
		if decor == null or decor.site == null:
			return
		var vp := get_viewport()
		var view := vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
		view = view.grow(96.0)
		for a in decor._anim:
			if not (view.intersects(a["rect"]) if a.has("rect") else view.has_point(a["pos"])):
				continue
			var seed_f := float(int(a["seed"]) % 97)
			match str(a["kind"]):
				"sign":  # (a failing sign: mostly on, dropping out in bursts)
					if sin(_t * 7.0 + seed_f) * sin(_t * 2.3 + seed_f * 0.7) > 0.5:
						draw_rect(Rect2(a["pos"] - a["size"] / 2.0, a["size"]), Color(0.03, 0.03, 0.04, 0.85))
				"spark":
					var k := fmod(_t * 0.7 + seed_f * 0.13, 3.0)
					if k < 0.25:
						for j in 3:
							var ang := seed_f + float(j) * 2.1 + _t * 9.0
							draw_line(a["pos"], a["pos"] + Vector2.from_angle(ang) * (6.0 + 6.0 * k * 4.0), Color(1.0, 0.9, 0.4, 1.0 - k * 4.0), 1.5)
				"shimmer":  # (heat haze: a few faint wavy lines rising over the room)
					var rc: Rect2 = a["rect"]
					for k in 5:
						var y0 := rc.position.y + fmod(_t * 14.0 + float(k) * rc.size.y / 5.0 + seed_f * 9.0, rc.size.y)
						var pts := PackedVector2Array()
						for q in 13:
							var x := rc.position.x + rc.size.x * float(q) / 12.0
							pts.append(Vector2(x, y0 + 2.5 * sin(_t * 3.0 + x * 0.05 + float(k))))
						draw_polyline(pts, Color(1.0, 0.7, 0.4, 0.06), 3.0)
				"pulse":
					var glow: Color = a["color"]
					var p := 0.5 + 0.5 * sin(_t * 2.0 + seed_f)
					draw_circle(a["pos"], minf(a["size"].x, a["size"].y) * 0.42, Color(glow, 0.05 + 0.07 * p))
