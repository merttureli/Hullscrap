extends RefCounted
## The exterior dressing of an enemy's livery (`style.dressing` of data/ship_styles.json and data/enemy_tables.json): decoration drawn OUTSIDE the
## hull, so a ship reads as its people's at a glance. It is a drawn layer only: no cells, no hp, no collision, nothing the threat rating
## counts. plan() places the pieces along the hull's outline by the ship's seed (the same ship always wears the same dressing); draw() paints
## them in the ship's frame. Kinds: spikes, fins, ribs, pods, shards, spars, lanterns, tarps, scrap, mandibles, slabs.
## A dressing entry: {kind, count: [min, max], where: "any" | "flank" | "bow" | "stern" | "front" (bow and the shoulders), sym: true to mirror
## each piece about the hull's middle, ln: its length in cells (default by kind)}.

const LENGTH := {"spikes": 1.8, "fins": 3.5, "ribs": 1.0, "pods": 1.5, "shards": 2.6, "spars": 3.5, "lanterns": 1.3, "tarps": 1.0, "scrap": 1.2, "slabs": 0.7, "mandibles": 3.4}
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]


## The pieces for `ship` ({kind, at (cell coordinates of the outline face), n (the outward normal), ln, seed}), [] when it has no dressing.
static func plan(ship, entries: Array) -> Array:
	var out: Array = []
	if entries.is_empty() or ship == null:
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
		var pool: Array = faces.filter(func(f): return _fits(str(e.get("where", "any")), f[1], f[0], lo, hi, mid_x))
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


static func _fits(where: String, n: Vector2i, c: Vector2i, lo: Vector2i, hi: Vector2i, mid_x: float) -> bool:
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
			"mandibles":  # a hooked horn curling in over the prow
				var inward := Vector2(-n.x, 0.0).normalized()
				var pts := PackedVector2Array([base + tg * 0.6 * k, base + n * ln * 0.55 + tg * 0.5 * k, base + n * ln + inward * 1.3 * k, base + n * ln * 0.6 - tg * 0.2 * k, base - tg * 0.6 * k])
				_poly(cv, pts, body.lightened(0.2), edge)


static func _poly(cv: CanvasItem, pts: Array, fill: Color, line: Color) -> void:
	var v := PackedVector2Array(pts)
	cv.draw_colored_polygon(v, fill)
	var closed := v.duplicate()
	closed.append(v[0])
	cv.draw_polyline(closed, line, 1.5, true)
