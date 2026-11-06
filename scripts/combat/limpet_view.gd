extends RefCounted
## What limpets, boarder pods and their work look like (docs/DRONES.md sections 4 to 6, 8): the flying disc or pod with a thin line of thruster sparks, the stuck limpet pulsing
## on the hull, the pod drilling, the husk that falls away, the predicted path while the key is held, and the effect on the room behind a stuck limpet (a green haze for
## poison, a red glow over the parts for heat; fire is the real fire). combat_view.gd calls draw and draw_path; ship_view.gd calls draw_rooms. Nothing here changes the arena.

const Art = preload("res://scripts/view/art.gd")
const Drones = preload("res://scripts/combat/drones.gd")
const TileArt = preload("res://scripts/view/tile_art.gd")

const SRC := 2.0  ## world px per source px at 1x
const BOOST := 1.15
const MIN_SCREEN := 1.2  ## fewest screen px per source px
const GLOW_MAX := 0.55
const BAR_S := 2.0  ## seconds a hurt one's hp bar shows
const TRAIL_S := 0.5
const TRAIL_GAP := 5.0  ## screen px between two spark dots
const COLORS := {"fire": Color("#ff9a3c"), "poison": Color("#9be34a"), "heat": Color("#ff5a48"), "boarder": Color("#f0b040")}


static func k_of(px: float) -> float:
	return maxf(SRC * BOOST, MIN_SCREEN * px)


static func _tint(d: Dictionary) -> Color:
	return COLORS.get(str(d["spec"].get("family", d["role"])), Color.WHITE)


## Draw every limpet and pod of `arena` on canvas `c`; glow into `quads` (an Array, or null to draw at once). `trails` is kept by the caller between frames.
static func draw(c: CanvasItem, arena, clock: float, px: float, trails: Dictionary, quads) -> void:
	var live := {}
	var zoom_fade := clampf((1.0 / px - 0.15) / 0.12, 0.0, 1.0)  # the glow fades out when zoomed far out
	for d in arena.drones:
		if str(d["role"]) != "limpet" and str(d["role"]) != "boarder":
			continue
		live[d["id"]] = true
		var k := k_of(px)
		var state := str(d["state"])
		var sc: float = Drones.scale_of(arena, d) if state == "flying" else 1.0
		if state == "gone":
			continue
		if state == "flying":
			_trail(c, trails, d, clock, px, k)
			if float(arena.tick - int(d["born"])) * arena.SUBSTEP < Drones.SHOW_AFTER_S:  # still inside the hatch
				continue
		var alpha := 1.0
		if state == "fall":
			alpha = clampf(1.0 - float(arena.tick - int(d["t0"])) * arena.SUBSTEP / 1.1, 0.0, 1.0)
		var sheet = Art.drone(str(d["art"]))
		if sheet == null:
			c.draw_circle(d["pos"], 8.0 * px, _tint(d))
			continue
		var at: Vector2 = d["pos"]
		var row := 0
		var pulse := 0.5 + 0.5 * sin(clock * 6.0 + float(d["id"]))
		if str(d["role"]) == "limpet":
			row = [0, 1][int(clock * 8.0) % 2] if state == "flying" else (6 if state == "fall" else 2 + int(clock * 6.0 + float(d["id"])) % 4)
		else:
			row = [0, 1][int(clock * 8.0) % 2] if state == "flying" else (5 if state == "fall" else 2 + int(clock * 12.0) % 3)
		var kk := k * sc
		var mod := Color(1, 1, 1, alpha)
		var glow_a := minf(GLOW_MAX, 0.3 + 0.25 * pulse) * alpha * zoom_fade * (0.0 if state == "fall" else 1.0)
		if str(d["role"]) == "limpet":
			var half := Vector2(sheet.frame) / 2.0 * kk
			c.draw_texture_rect_region(sheet.texture, Rect2(at - half, Vector2(sheet.frame) * kk), sheet.region(row), mod)
			var g = sheet.glow
			if g != null and glow_a > 0.01:
				var pin: Vector2 = sheet.pivot + Vector2(0.5, 0.5)
				TileArt.emit(c, quads, {"tex": g.texture, "rect": Rect2((-pin + g.offset) * kk, Vector2(g.frame) * kk), "src": g.region(clampi(row, 0, g.count - 1)), "xf": Transform2D(0.0, at), "mod": Color(1, 1, 1, glow_a)})
		else:
			var rot = Art.drone_rot(str(d["art"]))
			if rot == null:
				c.draw_circle(at, 8.0 * px, _tint(d))
				continue
			var n := int(sheet.meta["rot"]["count"])
			var turn := posmod(roundi(float(d["angle"]) / TAU * n), n)
			var half2 := Vector2(rot.frame) / 2.0 * kk
			c.draw_texture_rect_region(rot.texture, Rect2(at - half2, Vector2(rot.frame) * kk), Rect2(turn * rot.frame.x, row * rot.frame.y, rot.frame.x, rot.frame.y), mod)
			var g2 = sheet.glow
			if g2 != null and glow_a > 0.01:
				var pin2: Vector2 = sheet.pivot + Vector2(0.5, 0.5)
				TileArt.emit(c, quads, {"tex": g2.texture, "rect": Rect2((-pin2 + g2.offset) * kk, Vector2(g2.frame) * kk), "src": g2.region(clampi(row, 0, g2.count - 1)), "xf": Transform2D(float(d["angle"]), at), "mod": Color(1, 1, 1, glow_a)})
		_hp_bar(c, arena, d, at, px, kk)
	for id in trails.keys():
		if not live.has(id) and (trails[id].is_empty() or clock - float(trails[id].back()["t"]) > TRAIL_S):
			trails.erase(id)


## A small hp bar above a hurt one, for BAR_S seconds after a hit, with a dark border.
static func _hp_bar(c: CanvasItem, arena, d: Dictionary, at: Vector2, px: float, kk: float) -> void:
	if float(d["hp"]) >= float(d["max_hp"]) or str(d["state"]) == "fall":
		return
	if float(arena.tick - int(d["hit_tick"])) * arena.SUBSTEP > BAR_S:
		return
	var w := 24.0 * px
	var y := at.y - (16.0 * kk if str(d["role"]) == "boarder" else 9.0 * kk) - 7.0 * px
	c.draw_rect(Rect2(at.x - w / 2.0 - px, y - px, w + 2.0 * px, 4.0 * px), Color(0, 0, 0, 0.85))
	var f := clampf(float(d["hp"]) / float(d["max_hp"]), 0.0, 1.0)
	c.draw_rect(Rect2(at.x - w / 2.0, y, w * f, 2.0 * px), Color("#ffb347") if f > 0.4 else Color("#e0453a"))


## The thruster sparks behind a flying one: a dense thin line of small dots, `TRAIL_GAP` screen px apart, behind its tail.
static func _trail(c: CanvasItem, trails: Dictionary, d: Dictionary, clock: float, px: float, k: float) -> void:
	var list: Array = trails.get(d["id"], [])
	var dir := Vector2.from_angle(float(d["angle"]) - PI / 2.0)
	var tail: Vector2 = Vector2(d["pos"]) - dir * (20.0 if str(d["role"]) == "boarder" else 7.0) * k * 0.5 * 1.4
	if list.is_empty() or Vector2(list.back()["pos"]).distance_to(tail) >= TRAIL_GAP * px:
		list.append({"pos": tail, "t": clock})
	while not list.is_empty() and clock - float(list[0]["t"]) > TRAIL_S:
		list.pop_front()
	trails[d["id"]] = list
	var col := Color("#ffb86a") if str(d["role"]) == "boarder" else Color("#bfe4ff")
	for p in list:
		var age: float = (clock - float(p["t"])) / TRAIL_S
		c.draw_circle(p["pos"], (1.5 - 0.8 * age) * maxf(px, 0.5) * 1.3, Color(col, 0.75 * (1.0 - age)))


## The predicted path of a throw (Limpets.predict): faint dots from the hatch, with a ring where it would stick or a cross where it drifts off.
static func draw_path(c: CanvasItem, pred: Dictionary, px: float, tint: Color) -> void:
	var path: PackedVector2Array = pred.get("path", PackedVector2Array())
	var n := path.size()
	if n < 2:
		return
	for i in n:
		var f := float(i) / float(n)
		c.draw_circle(path[i], (1.7 - 0.6 * f) * px * 1.3, Color(tint, 0.62 - 0.4 * f))
	var end: Vector2 = path[n - 1]
	if str(pred["end"]) == "hit":
		c.draw_arc(end, 7.0 * px, 0.0, TAU, 20, Color(tint, 0.8), 1.5 * px, true)
	elif str(pred["end"]) == "lost":
		for s in [Vector2(1, 1), Vector2(1, -1)]:
			c.draw_line(end - s * 4.0 * px, end + s * 4.0 * px, Color(1.0, 0.5, 0.4, 0.6), 1.5 * px, true)


## The effect on the room behind each stuck limpet of ship `index`: `pxf` turns cell coordinates into the canvas's px, `cell_px` is a cell's size.
static func draw_rooms(c: CanvasItem, arena, index: int, pxf: Callable, cell_px: float, clock: float) -> void:
	var ship = arena.ships[index].ship
	for d in ship.stuck:
		if str(d["state"]) != "stuck" or str(d["role"]) != "limpet":
			continue
		var room: int = ship.atmosphere.room_at(d["rcell"])
		if room < 0:
			continue
		var cells: Array = ship.atmosphere.rooms[room]["cells"]
		var kind := str(d["spec"]["effect"]["kind"])
		var pulse := 0.5 + 0.5 * sin(clock * 3.0)
		if kind == "poison":
			for cell in cells:
				c.draw_rect(Rect2(pxf.call(Vector2(cell)), Vector2(cell_px, cell_px)), Color(0.45, 0.85, 0.25, 0.15 + 0.05 * pulse))
				for i in 2:  # drifting spores
					var h := float(hash([cell.x, cell.y, i]) % 1000) / 1000.0
					var off := Vector2(fposmod(h * 7.0 + clock * 0.07 * (1 + i), 1.0), fposmod(h * 13.0 - clock * 0.11, 1.0))
					c.draw_circle(pxf.call(Vector2(cell) + off), cell_px * 0.045, Color(0.7, 1.0, 0.4, 0.7))
		elif kind == "heat":
			for cell in cells:
				c.draw_rect(Rect2(pxf.call(Vector2(cell)), Vector2(cell_px, cell_px)), Color(1.0, 0.25, 0.15, 0.10 + 0.04 * pulse))
			for uid in ship.components.instances:
				var inst: Dictionary = ship.components.instances[uid]
				if ship.atmosphere.room_at(inst["anchor"]) != room:
					continue
				var hot := clampf(float(inst["heat"]) / maxf(float(ship.effective(inst["id"])["heat_limit"]), 1.0), 0.0, 1.0)
				for cell in inst["cells"]:
					c.draw_rect(Rect2(pxf.call(Vector2(cell)), Vector2(cell_px, cell_px)), Color(1.0, 0.3, 0.2, (0.18 + 0.4 * hot) * (0.8 + 0.2 * pulse)))


## The effect entries (combat_view's format) of the limpet event `e`: a small flash and sparks where it stuck, chips where it fell off or was lost, a burst where a pod cut in.
static func effects(e: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	var pos: Vector2 = e.get("pos", Vector2.ZERO)
	match e["type"]:
		"limpet_stick":
			out.append({"k": "flash", "pos": pos, "life": 0.12, "r": 8.0, "color": Color("#ffe9a8")})
			for i in 3:
				out.append({"k": "spark", "pos": pos, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 160.0), "life": rng.randf_range(0.15, 0.3), "color": Color("#ffe9a8")})
		"limpet_off", "limpet_lost":
			for i in 3:
				out.append({"k": "debris", "pos": pos, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 80.0), "life": rng.randf_range(0.6, 1.1),
					"size": rng.randf_range(1.8, 3.2), "spin": rng.randf_range(-6.0, 6.0), "color": [Color("#5b6577"), Color("#8a8f99")][i % 2]})
		"pod_breach":
			out.append({"k": "flash", "pos": pos, "life": 0.2, "r": 16.0, "color": Color("#ffd27a")})
			for i in 8:
				out.append({"k": "spark", "pos": pos, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, 240.0), "life": rng.randf_range(0.2, 0.45), "color": Color("#ffd27a")})
	return out
