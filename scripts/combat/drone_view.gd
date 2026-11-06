extends RefCounted
## What drones look like in a fight (docs/DRONES.md section 8): the pre-turned sprite of the drone (art/drones, 32 headings, so a turned drone does not jag), its glow
## and thruster trail, a launch that grows out of the hatch and a recall that shrinks into it, and the effects of the drone events. combat_view.gd calls it;
## the rules live in drones.gd. Nothing here changes the arena.

const Art = preload("res://scripts/view/art.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")

const SRC := 2.0  ## world px per source px at 1x (a cell is 32 px, 16 source px)
const BOOST := 1.4  ## drones are drawn a little larger than their art's pixels, so they read at a glance
const MIN_SCREEN := 1.0  ## fewest screen px per source px (zoomed out, they stay readable)
const TRAIL_S := 0.4  ## seconds a puff of the trail lasts
const TRAIL_STEP_PX := 5.0  ## screen px between two puffs
const TAIL_SRC := 11.0  ## source px behind the centre a puff starts at
const NOZZLE_SRC := 6.0  ## source px each nozzle is to the side
const GLOW_FADE_FROM := 0.08  ## zoom below which the drone glow is gone
const GLOW_FADE_TO := 0.25  ## zoom above which it is full
const HP_BAR_S := 2.0  ## seconds the hp bar shows after a hit
const FIRE_S := 0.14
const HIT_S := 0.06
const TRAIL_COLORS := {"standard": Color("#9fd0ff"), "scrap": Color("#ffa14a"), "neon": Color("#4ff2ff")}
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


## Draw every drone of `arena` on canvas `c`, glow into `quads` (an Array, or null to draw it at once). `trails`: drone key -> [{pos, t}], kept by the caller between frames.
static func draw(c: CanvasItem, arena, clock: float, px: float, trails: Dictionary, quads) -> void:
	var live := {}
	var fade := clampf((1.0 / px - GLOW_FADE_FROM) / (GLOW_FADE_TO - GLOW_FADE_FROM), 0.0, 1.0)  # the glow thins out as the camera pulls away
	for d in arena.drones:
		live[d["id"]] = true
		var age: float = float(arena.tick - int(d["born"])) * arena.SUBSTEP
		if age < Drones.SHOW_AFTER_S:  # still inside the bay: the cradle carries it
			continue
		var line := "standard"
		if arena.ships[d["owner"]].bays.has(d["bay"]):
			line = str(arena.ships[d["owner"]].ship.components.def(arena.ships[d["owner"]].bays[d["bay"]]["id"]).get("line", "standard"))
		var k := k_of(px)
		var sc: float = Drones.scale_of(arena, d)
		var kk := k * sc * (1.2 if d["role"] == "defence" else 1.0)  # (a defence drone is the smallest art: a little larger to read)
		var sheet = Art.drone(str(d["art"]))
		var at: Vector2 = d["pos"]
		if d["role"] != "defence":
			_trail(c, trails, d, line, clock, px, kk, quads, fade, sheet)
		var row := row_of(arena, d, clock)
		var rot = Art.drone_rot(str(d["art"]))
		if sheet == null or rot == null:
			c.draw_circle(at, 12.0 * px * 1.5 * sc, COLORS.get(str(d["spec"]["gun"].get("family", "pulse")), Color.WHITE))
			continue
		var n := int(sheet.meta["rot"]["count"])
		var turn := posmod(roundi(float(d["angle"]) / TAU * n), n)
		var half := Vector2(rot.frame) / 2.0 * kk
		var src := Rect2(turn * rot.frame.x, row * rot.frame.y, rot.frame.x, rot.frame.y)
		if d["role"] == "defence" and sheet.meta.has("parts"):  # the hoop and dome stay as they are; only the twin barrel turns
			var base = Art.drone_part(str(d["art"]), "base")
			var bar = Art.drone_part(str(d["art"]), "barrel_rot")
			if base != null and bar != null:
				c.draw_texture_rect_region(base.texture, Rect2(at - Vector2(base.frame) / 2.0 * kk, Vector2(base.frame) * kk), base.region(row))
				c.draw_texture_rect_region(bar.texture, Rect2(at - half, Vector2(bar.frame) * kk), Rect2(turn * bar.frame.x, row * bar.frame.y, bar.frame.x, bar.frame.y))
			else:
				c.draw_texture_rect_region(rot.texture, Rect2(at - half, Vector2(rot.frame) * kk), src)
		else:
			c.draw_texture_rect_region(rot.texture, Rect2(at - half, Vector2(rot.frame) * kk), src)
		var g = sheet.glow
		if g != null and row != 4 and fade > 0.0:  # (no glow on the white hit frame: its dark outline must stay)
			var pin: Vector2 = sheet.pivot + Vector2(0.5, 0.5)
			var a := 1.0 if row in [2, 3] else 0.3 + 0.25 * sc  # full only while it fires: the grey body stays crisp
			TileArt.emit(c, quads, {"tex": g.texture, "rect": Rect2((-pin + g.offset) * kk, Vector2(g.frame) * kk), "src": g.region(clampi(row, 0, g.count - 1)), "xf": Transform2D(float(d["angle"]), at), "mod": Color(1, 1, 1, a * fade)})
		var since_hit: float = float(arena.tick - int(d["hit_tick"])) * arena.SUBSTEP
		if d["hp"] < d["max_hp"] and since_hit < HP_BAR_S:  # a small hp bar over a drone that was just hit
			var w := 22.0 * px * 1.4
			var y := at.y - float(sheet.frame.y) / 2.0 * kk - 4.0 * px
			c.draw_rect(Rect2(at.x - w / 2.0 - px, y - px, w + 2.0 * px, 3.0 * px + 2.0 * px), Color(0.03, 0.04, 0.07, 0.9))
			c.draw_rect(Rect2(at.x - w / 2.0, y, w, 3.0 * px), Color(0.1, 0.12, 0.16, 0.9))
			c.draw_rect(Rect2(at.x - w / 2.0, y, w * clampf(float(d["hp"]) / float(d["max_hp"]), 0.0, 1.0), 3.0 * px), Color("#ffb347") if d["hp"] > d["max_hp"] * 0.4 else Color("#e0453a"))
	for id in trails.keys():
		if not live.has(int(id) / 2) and (trails[id].is_empty() or clock - float(trails[id].back()["t"]) > TRAIL_S):
			trails.erase(id)


## The thruster puffs behind drone `d`: from each of its two nozzles, one every few screen px, the frame by age (a dense spark line). They start at the tail, well
## behind the hull, and a puff within the sprite's half-size of the drone has no glow (no blue squares over the body).
static func _trail(c: CanvasItem, trails: Dictionary, d: Dictionary, line: String, clock: float, px: float, kk: float, quads, fade: float, sheet) -> void:
	var at: Vector2 = d["pos"]
	var fwd := Vector2.from_angle(float(d["angle"]) - PI / 2.0)
	var side := fwd.rotated(PI / 2.0)
	var art = Art.trail(line)
	var half: float = float(sheet.frame.x) / 2.0 * kk if sheet != null else 12.0 * kk
	for nz in 2:
		var key: int = int(d["id"]) * 2 + nz
		var list: Array = trails.get(key, [])
		var spawn := at - fwd * TAIL_SRC * kk + side * (float(nz) * 2.0 - 1.0) * NOZZLE_SRC * kk
		if list.is_empty() or Vector2(list.back()["pos"]).distance_to(spawn) >= TRAIL_STEP_PX * px:
			list.append({"pos": spawn, "t": clock})
		while not list.is_empty() and clock - float(list[0]["t"]) > TRAIL_S:
			list.pop_front()
		trails[key] = list
		if art == null:
			continue
		var col: Color = TRAIL_COLORS.get(line, Color.WHITE)
		for j in list.size():  # a dense line of sparks: a short bright segment from each puff to the next, thinning with age
			var p: Dictionary = list[j]
			var age: float = (clock - float(p["t"])) / TRAIL_S
			var pos: Vector2 = p["pos"]
			var nxt: Vector2 = list[j + 1]["pos"] if j + 1 < list.size() else spawn
			c.draw_line(pos, nxt, Color(col, 0.9 * (1.0 - age)), maxf(1.0 * px, 0.45 * kk * (1.0 - 0.6 * age)))
			if j % 3 == 0:
				c.draw_circle(pos, maxf(0.9 * px, 0.3 * kk * (1.0 - age)), Color(1, 1, 1, 0.8 * (1.0 - age)))
			var g = art.glow
			if g != null and fade > 0.0 and j % 3 == 0 and pos.distance_to(at) > half:
				var kp := kk * 0.6 * (1.0 - 0.3 * age)
				TileArt.emit(c, quads, {"tex": g.texture, "rect": Rect2(pos + (-Vector2(art.frame) / 2.0 + g.offset) * kp, Vector2(g.frame) * kp), "src": g.region(clampi(int(age * 4.0), 0, 3)), "xf": Transform2D.IDENTITY, "mod": Color(1, 1, 1, 0.8 * (1.0 - age) * fade)})


## The effect entries (the view's own format) of the drone event `e`: [{k, pos, life, ...}], from a seeded scatter.
static func effects(e: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	var pos: Vector2 = e.get("pos", Vector2.ZERO)
	match e["type"]:
		"drone_emerge":  # it shows in the open hatch: a small puff and three sparks along the launch direction (never over shut doors)
			var dir: Vector2 = e["dir"]
			for i in 3:
				out.append({"k": "spark", "pos": pos, "vel": dir.rotated(deg_to_rad(rng.randf_range(-20.0, 20.0))) * rng.randf_range(90.0, 220.0), "life": rng.randf_range(0.2, 0.35), "color": Color("#cfe6ff")})
			out.append({"k": "flash", "pos": pos, "life": 0.2, "r": 8.0, "color": Color(0.62, 0.82, 1.0, 0.6)})
		"drone_hit":
			out.append({"k": "flash", "pos": pos, "life": 0.1, "r": 6.0, "color": Color(1.0, 0.91, 0.66, 0.7)})
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
