extends RefCounted
## What drones look like in a fight (docs/DRONES.md section 8): the pre-turned sprite of the drone (art/drones, 32 headings, so a turned drone does not jag), its glow
## and thruster trail, a launch that grows out of the hatch and a recall that shrinks into it, and the effects of the drone events. combat_view.gd calls it;
## the rules live in drones.gd. Nothing here changes the arena.

const Art = preload("res://scripts/view/art.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")

const SRC := 2.0  ## world px per source px at 1x (a cell is 32 px, 16 source px)
const BOOST := 1.4  ## drones are drawn a little larger than their art's pixels, so they read at a glance
const MIN_SCREEN := 2.4  ## fewest screen px per source px (zoomed out, they stay readable)
const TRAIL_S := 0.55  ## seconds a puff of the trail lasts
const TRAIL_STEP := 9.0  ## px between two puffs
const FIRE_S := 0.14
const HIT_S := 0.1
const COLORS := {"pulse": Color("#ffb347"), "laser": Color("#ff6b6b"), "ion": Color("#7fe8ff"), "beam": Color("#ff5a8a"), "flak": Color("#ffd24a"), "pd": Color("#7dff9b")}


## World px per source px of a drone at screen scale `px` (world px per screen px).
static func k_of(px: float) -> float:
	return maxf(SRC * BOOST, MIN_SCREEN * px)


## The frame row of drone `d` now: 0-1 idle, 2-3 fire, 4 hit.
static func row_of(arena, d: Dictionary, clock: float) -> int:
	var since_hit: float = float(arena.tick - int(d["hit_tick"])) * arena.SUBSTEP
	if since_hit < HIT_S:
		return 4
	var since_fire: float = float(arena.tick - int(d["fire_tick"])) * arena.SUBSTEP
	if since_fire < FIRE_S:
		return 2 if since_fire < FIRE_S * 0.5 else 3
	return int(clock * 3.0) % 2


## Draw every drone of `arena` on canvas `c`, glow into `quads` (an Array, or null to draw it at once). `trails`: drone id -> [{pos, t}], kept by the caller between frames.
static func draw(c: CanvasItem, arena, clock: float, px: float, trails: Dictionary, quads) -> void:
	var live := {}
	for d in arena.drones:
		live[d["id"]] = true
		var line: String = str(arena.ships[d["owner"]].ship.components.def(arena.ships[d["owner"]].bays[d["bay"]]["id"]).get("line", "standard")) if arena.ships[d["owner"]].bays.has(d["bay"]) else "standard"
		var k := k_of(px)
		var sc: float = Drones.scale_of(arena, d)
		_trail(c, trails, d, line, clock, px, k, quads)
		if float(arena.tick - int(d["born"])) * arena.SUBSTEP < Drones.SHOW_AFTER_S:  # still inside the hatch
			continue
		var sheet = Art.drone(str(d["art"]))
		var rot = Art.drone_rot(str(d["art"]))
		var row := row_of(arena, d, clock)
		var at: Vector2 = d["pos"]
		if sheet == null or rot == null:
			c.draw_circle(at, 12.0 * px * 1.5 * sc, COLORS.get(str(d["spec"]["gun"].get("family", "pulse")), Color.WHITE))
			continue
		var n := int(sheet.meta["rot"]["count"])
		var turn := posmod(roundi(float(d["angle"]) / TAU * n), n)
		var kk := k * sc
		var half := Vector2(rot.frame) / 2.0 * kk
		c.draw_texture_rect_region(rot.texture, Rect2(at - half, Vector2(rot.frame) * kk), Rect2(turn * rot.frame.x, row * rot.frame.y, rot.frame.x, rot.frame.y))
		var g = sheet.glow
		if g != null:
			var pin: Vector2 = sheet.pivot + Vector2(0.5, 0.5)
			var xf := Transform2D(float(d["angle"]), at)
			TileArt.emit(c, quads, {"tex": g.texture, "rect": Rect2((-pin + g.offset) * kk, Vector2(g.frame) * kk), "src": g.region(clampi(row, 0, g.count - 1)), "xf": xf, "mod": Color(1, 1, 1, 0.5 + 0.5 * sc)})
		if d["hp"] < d["max_hp"]:  # a small hp bar over a hurt drone
			var w := 22.0 * px * 1.4
			var y := at.y - 22.0 * px * 1.4
			c.draw_rect(Rect2(at.x - w / 2.0, y, w, 3.0 * px), Color(0, 0, 0, 0.6))
			c.draw_rect(Rect2(at.x - w / 2.0, y, w * clampf(float(d["hp"]) / float(d["max_hp"]), 0.0, 1.0), 3.0 * px), Color("#ffb347") if d["hp"] > d["max_hp"] * 0.4 else Color("#e0453a"))
	for id in trails.keys():
		if not live.has(id) and (trails[id].is_empty() or clock - float(trails[id].back()["t"]) > TRAIL_S):
			trails.erase(id)


## The thruster puffs behind drone `d`: one every TRAIL_STEP px, the frame by age; the glow of each in the additive layer.
static func _trail(c: CanvasItem, trails: Dictionary, d: Dictionary, line: String, clock: float, px: float, k: float, quads) -> void:
	var list: Array = trails.get(d["id"], [])
	var at: Vector2 = d["pos"]
	if list.is_empty() or Vector2(list.back()["pos"]).distance_to(at) >= maxf(TRAIL_STEP, TRAIL_STEP * px * 0.5):
		list.append({"pos": at - Vector2.from_angle(float(d["angle"]) - PI / 2.0) * 8.0 * k / 2.0, "t": clock})
	while not list.is_empty() and clock - float(list[0]["t"]) > TRAIL_S:
		list.pop_front()
	trails[d["id"]] = list
	var art = Art.trail(line)
	if art == null:
		return
	for p in list:
		var age: float = (clock - float(p["t"])) / TRAIL_S
		var f := clampi(int(age * 4.0), 0, 3)
		var kk := k * 0.9 * (1.0 - 0.3 * age)
		var half := Vector2(art.frame) / 2.0 * kk
		c.draw_texture_rect_region(art.texture, Rect2(Vector2(p["pos"]) - half, Vector2(art.frame) * kk), art.region(f), Color(1, 1, 1, 1.0 - 0.5 * age))
		var g = art.glow
		if g != null:
			TileArt.emit(c, quads, {"tex": g.texture, "rect": Rect2(Vector2(p["pos"]) + (-Vector2(art.frame) / 2.0 + g.offset) * kk, Vector2(g.frame) * kk), "src": g.region(f), "xf": Transform2D.IDENTITY, "mod": Color(1, 1, 1, 1.0 - age)})


## The effect entries (the view's own format) of the drone event `e`: [{k, pos, life, ...}], from a seeded scatter.
static func effects(e: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	var pos: Vector2 = e.get("pos", Vector2.ZERO)
	match e["type"]:
		"drone_launch":  # a puff of thruster out of the hatch
			var dir: Vector2 = e["dir"]
			for i in 5:
				out.append({"k": "spark", "pos": pos, "vel": dir * rng.randf_range(60.0, 220.0) + Vector2.from_angle(rng.randf() * TAU) * 40.0, "life": rng.randf_range(0.2, 0.4), "color": Color("#cfe6ff")})
			out.append({"k": "flash", "pos": pos, "life": 0.25, "r": 20.0, "color": Color("#9fd0ff")})
		"drone_hit":
			out.append({"k": "flash", "pos": pos, "life": 0.14, "r": 13.0, "color": Color("#ffe9a8")})
			for i in 3:
				out.append({"k": "spark", "pos": pos, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(90.0, 260.0), "life": rng.randf_range(0.2, 0.4), "color": Color("#ffe9a8")})
		"drone_down":  # the existing explosion art, a few chips of hull and sparks
			out.append({"k": "art", "name": "explosion", "pos": pos, "life": 0.5, "scale": 0.55, "r": 24.0, "color": Color("#ff9a4a")})
			var v: Vector2 = e.get("vel", Vector2.ZERO) * 0.3
			for i in 6:
				out.append({"k": "debris", "pos": pos, "vel": v + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 180.0), "life": rng.randf_range(0.7, 1.4),
					"size": rng.randf_range(2.0, 4.5), "spin": rng.randf_range(-7.0, 7.0), "color": [Color("#8a8f99"), Color("#b9bfc9"), Color("#5b6577"), Color("#c9a37a")][i % 4]})
			for i in 5:
				out.append({"k": "spark", "pos": pos, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(120.0, 330.0), "life": rng.randf_range(0.2, 0.5), "color": Color("#ffd27a")})
		"drone_home":
			out.append({"k": "flash", "pos": pos, "life": 0.18, "r": 14.0, "color": Color("#9fd0ff")})
		"drone_shot":
			if str(e["kind"]) == "pd":  # a tracer to what it shot at
				out.append({"k": "beam", "a": e["origin"], "b": e["to"], "life": 0.12, "color": Color("#7dff9b") if bool(e.get("hit", false)) else Color(0.5, 0.9, 0.6, 0.6), "kind": "pd", "weapon": "__pd"})
			out.append({"k": "flash", "pos": e["origin"], "life": 0.09, "r": 9.0, "color": COLORS.get(_family(str(e["weapon"])), Color.WHITE)})
	return out


static func _family(weapon: String) -> String:
	if weapon.begins_with("pulse"):
		return "pulse"
	if weapon.begins_with("laser"):
		return "laser"
	if weapon.begins_with("ion"):
		return "ion"
	if weapon.begins_with("prismatic"):
		return "beam"
	if weapon.begins_with("shrapnel"):
		return "flak"
	return "pd"


## The loaded drone sitting on the cradle of bay `inst` (def `def`), drawn over the bay's inside half `rect` (the screen rectangle of its cells) at `cell_px` per cell:
## its idle frame turned with the part. `rise`: source px the cradle has run up the rail (a launch). Nothing without a kit or art.
static func draw_docked(c: CanvasItem, def: Dictionary, inst: Dictionary, rect: Rect2, cell_px: float, clock: float, rise := 0.0, alpha := 1.0) -> void:
	var kit := Drones.kit(str(inst.get("kit", "")))
	var sheet = Art.drone(str(kit.get("drone", {}).get("art", ""))) if not kit.is_empty() else null
	var bay = Art.component(str(def["id"]))
	if sheet == null or bay == null:
		return
	var k := cell_px / 16.0
	var cradle: Vector2 = bay.anchors.get("cradle", Vector2(24, 38)) - Vector2(24.0, 24.0) + bay.offset  # from the footprint's middle, source px
	var at := Vector2(cradle.x, cradle.y - rise) * k
	var xf := Transform2D(deg_to_rad(float(inst.get("angle", posmod(int(inst.get("rot", 0)), 4) * 90))), rect.get_center())
	var f := int(clock * 3.0) % 2
	c.draw_set_transform_matrix(xf)
	c.draw_texture_rect_region(sheet.texture, Rect2(at - Vector2(sheet.frame) / 2.0 * k, Vector2(sheet.frame) * k), sheet.region(f), Color(1, 1, 1, alpha))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)
