extends RefCounted
## The exterior dressing of an enemy's livery (`style.dressing` of data/ship_styles.json and data/enemy_tables.json): decoration drawn OUTSIDE the
## hull, so a ship reads as its people's at a glance. It is a drawn layer only: no cells, no hp, no collision, nothing the threat rating
## counts. plan() places the pieces along the hull's outline by the ship's seed (the same ship always wears the same dressing); draw() paints
## them in the ship's frame. Kinds: spikes, fins, ribs, pods, shards, spars, lanterns, tarps, scrap, mandibles, slabs, and the fighting
## roles' own (data/role_looks.json, added to the livery's by plan()): bay_doors (carrier), clamps (boarder), racks (siege), fin_trim
## (skirmisher), horn_lamps (flanker), plate_seams (bulwark).
## A dressing entry: {kind, count: [min, max], where: "any" | "flank" | "bow" | "stern" | "front" (bow and the shoulders), sym: true to mirror
## each piece about the hull's middle, ln: its length in cells (default by kind)}. mandibles, clamps, fin_trim and horn_lamps place
## themselves (one each side: at the prow, the bow's outer flanks, the stern's outer corners, the tips of the horns) and take no count.

const Hullgen = preload("res://scripts/space/hullgen.gd")

const LENGTH := {"spikes": 1.8, "fins": 3.5, "ribs": 1.0, "pods": 1.5, "shards": 2.6, "spars": 3.5, "lanterns": 1.3, "tarps": 1.0, "scrap": 1.2, "slabs": 0.7, "mandibles": 3.4,
	"bay_doors": 2.4, "clamps": 3.0, "racks": 1.6, "fin_trim": 2.6, "horn_lamps": 1.0, "plate_seams": 2.4}
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const PAIRED := ["clamps", "fin_trim", "horn_lamps"]  ## the role kinds that place one piece each side by themselves


## The pieces for `ship` ({kind, at (cell coordinates of the outline face), n (the outward normal), ln, seed}), [] when it has no dressing.
## The dressing of the ship's fighting role (its `shipgen` meta) comes after `entries`.
static func plan(ship, entries: Array) -> Array:
	var out: Array = []
	if ship == null:
		return out
	entries = entries + Hullgen.look_of(str(ship.get_meta("shipgen", {}).get("role", ""))).get("dressing", [])
	if entries.is_empty():
		return out
	var grid = ship.grid
	var blocked := {}  # the cells of the mounts' outside halves: nothing grows there
	for uid in ship.components.instances:
		for c in ship.components.instances[uid]["out_cells"]:
			blocked[c] = true
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for c in grid.tiles:
		lo = lo.min(c)
		hi = hi.max(c)
	var mid_x := float(lo.x + hi.x + 1) / 2.0
	var faces: Array = []  # [cell, normal]
	var cells: Array = grid.tiles.keys()
	cells.sort()
	for c in cells:
		if not grid.shape_of(c).is_empty():
			continue
		for d in DIRS:
			if grid.tiles.has(c + d) or blocked.has(c + d) or blocked.has(c + d * 2) or blocked.has(c + d + Vector2i(d.y, d.x)) or blocked.has(c + d - Vector2i(d.y, d.x)):
				continue
			faces.append([c, d])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ship.rng_seed) * 7919 + 17
	for e in entries:
		var kind := str(e["kind"])
		var pool: Array = faces.filter(func(f): return _fits(str(e.get("where", "any")), f[1], f[0], lo, hi))
		if kind == "mandibles":
			pool = faces.filter(func(f): return f[1] == Vector2i.UP and f[0].y == lo.y)
			if pool.is_empty():
				continue
			var left: Array = pool.filter(func(f): return float(f[0].x) < mid_x)
			var right: Array = pool.filter(func(f): return float(f[0].x) >= mid_x)
			if left.is_empty() or right.is_empty():
				continue
			var l: Array = left[0]  # the outermost cell of each side
			var r: Array = right[right.size() - 1]
			out.append({"kind": kind, "at": Vector2(l[0]) + Vector2(0.5, 0.0), "n": Vector2(-0.45, -1.0).normalized(), "len": float(e.get("len", LENGTH["mandibles"])), "seed": rng.randi()})
			out.append({"kind": kind, "at": Vector2(r[0]) + Vector2(0.5, 0.0), "n": Vector2(0.45, -1.0).normalized(), "len": float(e.get("len", LENGTH["mandibles"])), "seed": rng.randi()})
			continue
		if PAIRED.has(kind):
			for p in _pair(kind, faces, mid_x):
				out.append({"kind": kind, "at": p[0], "n": p[1], "len": float(e.get("len", LENGTH[kind])), "seed": rng.randi()})
			continue
		if kind == "trim":  # a fine ship: an accent line along every face of the outline
			for f in pool:
				out.append({"kind": kind, "at": Vector2(f[0]) + Vector2(0.5, 0.5) + Vector2(f[1]) * 0.5, "n": Vector2(f[1]), "len": 0.0, "seed": 0})
			continue
		if pool.is_empty():
			continue
		var n := rng.randi_range(int(e["count"][0]), int(e["count"][1]))
		var taken := {}
		var tries := 0
		while n > 0 and tries < 60:
			tries += 1
			var f: Array = pool[rng.randi() % pool.size()]
			var picks: Array = [f]
			if bool(e.get("sym", false)):
				var mirror := Vector2i(int(2.0 * mid_x) - 1 - f[0].x, f[0].y)
				for g in pool:
					if g[0] == mirror and g[1] == Vector2i(-f[1].x, f[1].y):
						picks.append(g)
						break
			var key: Vector2i = f[0] / 2 + f[1] * 100
			if taken.has(key):
				continue
			taken[key] = true
			for p in picks:
				var ln := float(e.get("len", LENGTH.get(kind, 1.5))) * rng.randf_range(0.8, 1.25)
				out.append({"kind": kind, "at": Vector2(p[0]) + Vector2(0.5, 0.5) + Vector2(p[1]) * 0.5, "n": Vector2(p[1]), "len": ln, "seed": rng.randi()})
			n -= 1
	return out


## The two spots ([at, n]) of a paired kind, left then right, or [] when a side has none: clamps on the outer flank face of
## the bow's first row (they reach forward), fin_trim under the outermost cells of the stern row (swept back and out), horn_lamps
## on the foremost bow faces of each side (the tips of a flanker's horns).
static func _pair(kind: String, faces: Array, mid_x: float) -> Array:
	var best := [[], []]  # per side: [score, face]
	for f in faces:
		var c: Vector2i = f[0]
		var d: Vector2i = f[1]
		var s := 0 if float(c.x) + 0.5 < mid_x else 1
		var score := 0.0
		match kind:
			"clamps":
				if d.x != (-1 if s == 0 else 1):
					continue
				score = c.y * 100.0 - absf(c.x - mid_x)
			"fin_trim":
				if d != Vector2i.DOWN:
					continue
				score = -c.y * 100.0 - absf(c.x - mid_x)
			"horn_lamps":
				if d != Vector2i.UP:
					continue
				score = c.y * 100.0 - absf(c.x - mid_x)
		if best[s].is_empty() or score < float(best[s][0]):
			best[s] = [score, f]
	if best[0].is_empty() or best[1].is_empty():
		return []
	var out: Array = []
	for s in 2:
		var f: Array = best[s][1]
		var side := -1.0 if s == 0 else 1.0
		var at := Vector2(f[0]) + Vector2(0.5, 0.5) + Vector2(f[1]) * 0.5
		match kind:
			"clamps":
				out.append([at, Vector2(side * 0.35, -1.0).normalized()])
			"fin_trim":
				out.append([at + Vector2(side * 0.5, 0.0), Vector2(side * 0.75, 1.0).normalized()])
			_:
				out.append([at, Vector2.UP])
	return out


static func _fits(where: String, n: Vector2i, c: Vector2i, lo: Vector2i, hi: Vector2i) -> bool:
	match where:
		"flank":
			return n.x != 0
		"bow":
			return n == Vector2i.UP
		"stern":
			return n == Vector2i.DOWN
		"front":
			return n.y < 0 or (n.x != 0 and c.y < lo.y + (hi.y - lo.y) / 3)
	return true


## The pieces of `pieces` (plan()) whose hull cell is still there. In a fight the dressing is never planned again: a lost cell
## drops the pieces on it and every other piece stays where it was, so nothing slides along the hull as it is shot apart.
static func kept(pieces: Array, grid) -> Array:
	return pieces.filter(func(p): return grid.tiles.has(Vector2i((Vector2(p["at"]) - Vector2(p["n"]) * 0.5).floor())))


## Paint `pieces` (plan()) with grid cell (0, 0) at `origin` px, `k` px per cell, in the colours of `pal` (a style's palette: tint, accent, mark, lamp).
static func draw(cv: CanvasItem, pieces: Array, origin: Vector2, k: float, pal: Dictionary, t := 0.0) -> void:
	var body: Color = Color(pal["tint"]).darkened(0.35)
	var edge: Color = Color(pal["tint"]).darkened(0.65)
	var lit: Color = Color(pal["mark"])
	for p in pieces:
		var n: Vector2 = p["n"]
		var tg := Vector2(-n.y, n.x)
		var base: Vector2 = origin + p["at"] * k
		var ln: float = float(p["len"]) * k
		match str(p["kind"]):
			"spikes":
				_poly(cv, [base + tg * 0.7 * k, base + n * ln, base - tg * 0.7 * k], body, edge)
			"fins":  # a long swept blade
				_poly(cv, [base + tg * 0.35 * k, base + n * ln + tg * 0.9 * k, base + n * ln * 0.9 - tg * 0.2 * k, base - tg * 0.35 * k], body.lightened(0.25), edge)
			"ribs":
				_poly(cv, [base + tg * 0.22 * k, base + n * ln + tg * 0.22 * k, base + n * ln - tg * 0.22 * k, base - tg * 0.22 * k], body, edge)
			"pods":  # a cargo pod: a rounded box with a band
				var c: Vector2 = base + n * ln * 0.5
				cv.draw_circle(c, ln * 0.55, edge)
				cv.draw_circle(c, ln * 0.46, body.lightened(0.1))
				cv.draw_line(c - tg * ln * 0.46, c + tg * ln * 0.46, edge, maxf(1.0, k / 10.0))
			"shards":  # a crystal: a long thin diamond, a bright facet line
				var h := float(p["seed"] % 5) / 5.0 * 0.5 + 0.8
				var tip: Vector2 = base + n * ln * h
				_poly(cv, [base + tg * 0.45 * k, base + n * ln * 0.45 * h + tg * 0.55 * k, tip, base + n * ln * 0.45 * h - tg * 0.2 * k, base - tg * 0.45 * k], body.lightened(0.3), lit)
			"spars":  # a lattice mast: a long line with cross ties
				cv.draw_line(base, base + n * ln, lit.darkened(0.2), maxf(1.0, k / 8.0))
				for i in 3:
					var q: Vector2 = base + n * ln * (0.3 + 0.3 * i)
					cv.draw_line(q - tg * 0.5 * k, q + tg * 0.5 * k, edge.lightened(0.2), maxf(1.0, k / 12.0))
			"lanterns":  # a stem and a lamp
				var s: Vector2 = base + n * ln
				cv.draw_line(base, s, edge, maxf(1.0, k / 12.0))
				cv.draw_circle(s, 0.34 * k, Color(pal["lamp"], 0.3 + 0.1 * sin(t * 3.0 + float(p["seed"] % 7))))
				cv.draw_circle(s, 0.2 * k, Color(pal["lamp"]))
			"tarps":  # a patch of cloth draped over the edge, in the accent colour
				var a: Vector2 = base - tg * 1.3 * k
				var b: Vector2 = base + tg * 1.3 * k
				_poly(cv, [a, a + n * 0.9 * k, b + n * 0.6 * k, b], Color(pal["accent"]).lerp(Color(pal["tint"]), 0.45), edge)
			"scrap":  # welded plates: two off-square slabs
				_poly(cv, [base - tg * 0.9 * k, base - tg * 0.8 * k + n * ln, base + tg * 0.2 * k + n * ln * 0.8, base + tg * 0.1 * k], body.lightened(0.15), edge)
				_poly(cv, [base + tg * 0.1 * k, base + tg * 0.3 * k + n * ln * 1.1, base + tg * 1.2 * k + n * ln * 0.6, base + tg * 1.1 * k], body, edge)
			"slabs":  # heavy flat plates laid along the edge
				_poly(cv, [base - tg * 1.6 * k, base - tg * 1.6 * k + n * 0.7 * k, base + tg * 1.6 * k + n * 0.7 * k, base + tg * 1.6 * k], body.lightened(0.12), edge)
			"trim":
				cv.draw_line(base - tg * 0.5 * k + n * 0.12 * k, base + tg * 0.5 * k + n * 0.12 * k, Color(pal["accent"], 0.9), maxf(1.0, k / 9.0))
			"mandibles":  # a hooked horn curling in over the prow
				var inward := Vector2(-n.x, 0.0).normalized()
				var pts := PackedVector2Array([base + tg * 0.6 * k, base + n * ln * 0.55 + tg * 0.5 * k, base + n * ln + inward * 1.3 * k, base + n * ln * 0.6 - tg * 0.2 * k, base - tg * 0.6 * k])
				_poly(cv, pts, body.lightened(0.2), edge)
			"bay_doors":  # a launch bay's lip: a dark mouth behind two door leaves, hazard marks on the sill
				var a: Vector2 = base - tg * ln * 0.5
				var b: Vector2 = base + tg * ln * 0.5
				_poly(cv, [a, a + n * 0.75 * k, b + n * 0.75 * k, b], body, edge)
				_poly(cv, [a + tg * 0.2 * k, a + tg * 0.2 * k + n * 0.5 * k, b - tg * 0.2 * k + n * 0.5 * k, b - tg * 0.2 * k], edge.darkened(0.4), edge)
				cv.draw_line(base, base + n * 0.5 * k, body.lightened(0.3), maxf(1.0, k / 10.0))
				for i in 4:
					var q: Vector2 = a + tg * ln * (0.15 + 0.233 * i) + n * 0.68 * k
					cv.draw_line(q, q + tg * 0.25 * k, Color(pal["accent"]), maxf(1.0, k / 9.0))
			"clamps":  # a boarding arm: a jointed strut reaching forward, a claw at its end bent in over the foe
				var side := signf(n.x)
				var elbow: Vector2 = base + n * ln * 0.55
				var hand: Vector2 = elbow + Vector2(-side * 0.35, -1.0).normalized() * ln * 0.45
				cv.draw_line(base, elbow, edge, 0.6 * k)
				cv.draw_line(elbow, hand, edge, 0.5 * k)
				cv.draw_line(base, elbow, body.lightened(0.25), 0.36 * k)
				cv.draw_line(elbow, hand, body.lightened(0.25), 0.28 * k)
				cv.draw_circle(elbow, 0.32 * k, lit)
				_poly(cv, [hand + Vector2(side * 0.4, 0.2) * k, hand + Vector2(-side * 0.7, -0.6) * k, hand + Vector2(-side * 0.2, 0.1) * k], body.lightened(0.1), edge)
				_poly(cv, [hand + Vector2(-side * 0.4, 0.3) * k, hand + Vector2(-side * 1.1, 0.0) * k, hand + Vector2(-side * 0.3, 0.6) * k], body.lightened(0.1), edge)
			"racks":  # a missile rack: a frame along the hull holding three tube heads
				var a: Vector2 = base - tg * ln * 0.5
				var b: Vector2 = base + tg * ln * 0.5
				_poly(cv, [a, a + n * 0.6 * k, b + n * 0.6 * k, b], edge, edge)
				for i in 3:
					var q: Vector2 = a + tg * ln * (0.2 + 0.3 * i) + n * 0.35 * k
					cv.draw_circle(q, 0.24 * k, body.lightened(0.3))
					cv.draw_circle(q, 0.11 * k, Color(pal["accent"]))
			"fin_trim":  # a swept fin blade off the stern corner, an accent stripe along its leading edge
				var tip: Vector2 = base + n * ln
				_poly(cv, [base - tg * 0.45 * k, tip, base + n * ln * 0.45 + tg * 0.5 * k, base + tg * 0.2 * k], body.lightened(0.2), edge)
				cv.draw_line(base - tg * 0.3 * k + n * 0.2 * k, tip - n * 0.25 * k, Color(pal["accent"]), maxf(1.5, k / 6.0))
			"horn_lamps":  # a lamp on a horn's tip, its beam cast forward
				var s2: Vector2 = base + n * ln * 0.6
				var glow := Color(pal["lamp"], 0.22 + 0.08 * sin(t * 2.5 + float(p["seed"] % 5)))
				cv.draw_colored_polygon(PackedVector2Array([s2, s2 + n * 3.2 * k + tg * 1.0 * k, s2 + n * 3.2 * k - tg * 1.0 * k]), glow)
				cv.draw_line(base, s2, edge, maxf(1.0, k / 8.0))
				cv.draw_circle(s2, 0.42 * k, edge)
				cv.draw_circle(s2, 0.3 * k, Color(pal["lamp"]))
			"plate_seams":  # stepped armour plates over the edge: a wide lower layer, a narrower upper one, seams and rivets
				var a: Vector2 = base - tg * ln * 0.5
				var b: Vector2 = base + tg * ln * 0.5
				_poly(cv, [a, a + n * 0.8 * k, b + n * 0.8 * k, b], body, edge)
				_poly(cv, [a + tg * 0.35 * k, a + tg * 0.35 * k + n * 0.45 * k, b - tg * 0.35 * k + n * 0.45 * k, b - tg * 0.35 * k], body.lightened(0.22), edge)
				for i in 2:
					var q: Vector2 = a + tg * ln * (0.33 + 0.34 * i)
					cv.draw_line(q, q + n * 0.8 * k, edge, maxf(1.0, k / 10.0))
					cv.draw_circle(q + tg * 0.3 * k + n * 0.62 * k, maxf(0.8, 0.09 * k), lit)


static func _poly(cv: CanvasItem, pts: Array, fill: Color, line: Color) -> void:
	var v := PackedVector2Array(pts)
	cv.draw_colored_polygon(v, fill)
	var closed := v.duplicate()
	closed.append(v[0])
	cv.draw_polyline(closed, line, 1.5, true)
