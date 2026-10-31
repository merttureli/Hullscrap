extends RefCounted
## The hull grammar of the procedural enemy ships (shipgen.gd, data/enemy_tables.json "hull" of each faction).
## A ship is a stack of decks (bow to stern: the gun deck, the decks between, the engine room). The caller gives
## every deck the floor it needs; this script widens it the way the faction does (extents), draws the staircase
## silhouette that wraps the decks in a shell of `t` cells (the union of every deck's rectangle grown by `t`)
## and shapes it with the faction's ops (make): wedge (a step filled by a slope), chamfer (a convex corner cut),
## spikes (saw teeth on a flank) and arc (a round2 corner). Every edge it draws is axis aligned, 45 degrees or
## 2:1, so tests/hull_outline.gd turns the outline into the exact shaped cells of data/shapes.json.
## The polygon is clockwise on the cell lattice (x right, y down, bow up) and every vertex is a Vector2i.

const Shapes = preload("res://scripts/ship/shapes.gd")
const HullOutline = preload("res://tests/hull_outline.gd")

const MIN_OVERLAP := 6  ## columns two neighbouring decks share

## The ops of a ram bow (a Rustfang rammer): a V bow of 45 degree slopes and small bevels elsewhere.
const RAM_OPS: Array = [
	{"op": "wedge", "at": "bow", "slope": ["45"], "chance": 1.0},
	{"op": "chamfer", "at": "tip", "kind": ["45"], "n": [1, 1]},
	{"op": "chamfer", "at": "shoulder", "kind": ["45"], "n": [1, 2]},
	{"op": "chamfer", "at": "stern_end", "kind": ["45"], "n": [1, 2]},
]
## Level 0 (the plain fallback): a bevel on each end of the hull.
const PLAIN_OPS: Array = [
	{"op": "chamfer", "at": "tip", "kind": ["45"], "n": [1, 1]},
	{"op": "chamfer", "at": "stern_end", "kind": ["45"], "n": [1, 1]},
]


## `boost` (0..3) is how hard a hull that came out too boxy is reshaped: its ends narrow and bevel more. Give every deck of `bands` ([{kind, need (the floor width it needs), rooms}]) its floor columns x0..x1 (set in place): the share of
## `interior_max` its kind gets in the faction's grammar, never less than it needs, plus the faction's jitter. The centre
## line is x = 0; a symmetric faction gets even widths and no slip.
static func extents(style: Dictionary, bands: Array, interior_max: int, rng: RandomNumberGenerator, boost := 0, t := 1) -> void:
	var hull: Dictionary = style["hull"]
	var frac: Dictionary = hull["band"]
	var jw: Array = hull["jitter_w"]
	var jc := int(hull["jitter_c"])
	var asym := bool(hull["asym"])
	for b in bands:
		var share := float(frac.get(b["kind"], 1.0))
		if b["kind"] == "gun" or b["kind"] == "engine":
			share -= 0.12 * boost  # a hull that is too much of a box narrows its ends
		elif b["kind"] != "core":
			share -= 0.12 * boost
		var w := maxi(int(b["need"]), roundi(share * interior_max))
		if b["kind"] == "gun" and boost > 0:
			w = maxi(w, int(b["need"]) + 2 * maxi(0, boost + 2 - t))  # room for the bow's bevel round the guns
		w += w % 2  # an even base so a symmetric ship is symmetric
		var extra := rng.randi_range(int(jw[0]), int(jw[1])) if boost < 2 else 0
		var el := 0
		var er := 0
		if asym:
			el = rng.randi_range(0, extra)
			er = extra - el
		else:
			w += extra - extra % 2
		var slip := rng.randi_range(-jc, jc) if jc > 0 else 0
		b["x0"] = -w / 2 - el + slip
		b["x1"] = w / 2 - 1 + er + slip
	# neighbouring decks share at least MIN_OVERLAP columns, so a door can join them
	for i in range(1, bands.size()):
		var a: Dictionary = bands[i - 1]
		var b: Dictionary = bands[i]
		var over := mini(int(a["x1"]), int(b["x1"])) - maxi(int(a["x0"]), int(b["x0"])) + 1
		if over < MIN_OVERLAP:
			var shift := MIN_OVERLAP - over
			var dir := 1 if int(b["x0"]) < int(a["x0"]) else -1  # towards the previous deck
			b["x0"] = int(b["x0"]) + dir * shift
			b["x1"] = int(b["x1"]) + dir * shift
	# a deck with flank turrets needs flat flanks: it is at least as wide as the decks on either side of it
	for i in bands.size():
		if bands[i]["rooms"].any(func(r): return r["kind"] == "turret"):
			for j in [i - 1, i + 1]:
				if j >= 0 and j < bands.size():
					bands[i]["x0"] = mini(int(bands[i]["x0"]), int(bands[j]["x0"]))
					bands[i]["x1"] = maxi(int(bands[i]["x1"]), int(bands[j]["x1"]))


## The outline of a ship whose decks are `bands` ([{kind, y0, y1, x0, x1}], the floor rectangles, rows y0..y1 inclusive),
## wrapped in a shell `t` cells thick, `rows` cells tall. `opts`: level (2 = the whole grammar, 1 = wedges and chamfers
## only, 0 = a bevel at each end), ram (the ops of a ram bow), avoid ([[y0, y1], ...] rows whose flanks stay flat).
## Returns {outline (the Array hull_outline.gd reads), poly (the Vector2i vertices)}. avoid also keeps chamfers off those flanks.
static func make(style: Dictionary, bands: Array, t: int, rows: int, rng: RandomNumberGenerator, opts := {}) -> Dictionary:
	var prof := _profile(bands, t, rows)
	var poly := _polygon(prof["l"], prof["r"], rows)
	var level := int(opts.get("level", 2))
	var ops: Array = style["hull"].get("ops", [])
	if bool(opts.get("ram", false)):
		ops = RAM_OPS
	if level <= 0:
		ops = PLAIN_OPS
	var boost := int(opts.get("boost", 0))
	if boost > 0:
		ops = ops + [
			{"op": "chamfer", "at": "tip", "kind": ["45"], "n": [boost + 2, boost + 2]},
			{"op": "chamfer", "at": "stern_end", "kind": ["45"], "n": [boost + 2, boost + 2]},
			{"op": "chamfer", "at": "shoulder", "kind": ["45"], "n": "max"},
		]
	var arcs := {}
	if OS.get_environment("SHIPGEN_DEBUG") != "":
		print("poly0 ", poly)
	for op in ops:
		if OS.get_environment("SHIPGEN_DEBUG") != "":
			print("op ", op["op"], " ", op.get("at", ""), " -> ", poly)
		match str(op["op"]):
			"wedge", "chamfer":
				if str(op["op"]) == "wedge" and boost >= 2 and not bool(opts.get("ram", false)):
					continue  # a wedge fills the very step a boxy hull needs
				_apply(poly, op, rng, opts.get("avoid", []))
			"spikes":
				if level >= 2:
					_spikes(poly, op, rng, opts.get("avoid", []))
	for op in ops:
		if str(op["op"]) == "arc" and level >= 2:
			_arcs(poly, op, rng, arcs)
	var out: Array = []
	for i in poly.size():
		var v: Vector2i = poly[i]
		out.append(_arc_entry(poly, i) if arcs.has(v) else [v.x, v.y])
	return {"outline": out, "poly": poly}


# --- the staircase -----------------------------------------------------------------------------------

## Per row y: l[y] the first column of the shell and r[y] one past the last, the union of every deck grown by t.
static func _profile(bands: Array, t: int, rows: int) -> Dictionary:
	var l := PackedInt32Array()
	var r := PackedInt32Array()
	l.resize(rows)
	r.resize(rows)
	l.fill(1 << 20)
	r.fill(-(1 << 20))
	for b in bands:
		for y in range(maxi(int(b["y0"]) - t, 0), mini(int(b["y1"]) + t + 1, rows)):
			l[y] = mini(l[y], int(b["x0"]) - t)
			r[y] = maxi(r[y], int(b["x1"]) + 1 + t)
	return {"l": l, "r": r}


## The clockwise polygon of the staircase: the right edge down, then the left edge up.
static func _polygon(l: PackedInt32Array, r: PackedInt32Array, rows: int) -> Array:
	var poly: Array = []
	for v in _stair(r, rows):
		poly.append(v)
	var left := _stair(l, rows)
	left.reverse()
	for v in left:
		poly.append(v)
	return _dedupe(poly)


static func _stair(edge: PackedInt32Array, rows: int) -> Array:
	var pts: Array = [Vector2i(edge[0], 0)]
	for y in range(1, rows):
		if edge[y] != edge[y - 1]:
			pts.append(Vector2i(edge[y - 1], y))
			pts.append(Vector2i(edge[y], y))
	pts.append(Vector2i(edge[rows - 1], rows))
	return pts


# --- vertex helpers ----------------------------------------------------------------------------------

static func _sgn(v: Vector2i) -> Vector2i:
	return Vector2i(signi(v.x), signi(v.y))


static func _dedupe(poly: Array) -> Array:
	var out: Array = []
	for v in poly:
		if out.is_empty() or out[out.size() - 1] != v:
			out.append(v)
	while out.size() > 1 and out[0] == out[out.size() - 1]:
		out.pop_back()
	return out


## What vertex i of the clockwise polygon is: its neighbours, the way in and out, the edge lengths (only
## meaningful for axis aligned edges), whether it is a convex corner and whether both its edges are axis aligned.
static func _info(poly: Array, i: int) -> Dictionary:
	var n := poly.size()
	var v: Vector2i = poly[i]
	var a: Vector2i = poly[(i + n - 1) % n]
	var b: Vector2i = poly[(i + 1) % n]
	var din := _sgn(v - a)
	var dout := _sgn(b - v)
	return {
		"v": v, "din": din, "dout": dout,
		"lin": absi(v.x - a.x) + absi(v.y - a.y), "lout": absi(b.x - v.x) + absi(b.y - v.y),
		"convex": din.x * dout.y - din.y * dout.x > 0,
		"axis": (a.x == v.x or a.y == v.y) and (v.x == b.x or v.y == b.y),
	}


static func _bounds(poly: Array) -> Rect2i:
	var lo: Vector2i = poly[0]
	var hi: Vector2i = poly[0]
	for v in poly:
		lo = lo.min(v)
		hi = hi.max(v)
	return Rect2i(lo, hi - lo)


## The vertices an op's `at` (and `side`) selects, as positions: convex corners at the "tip" (the top row), the
## "stern_end" (the bottom row), the "shoulder" (any other), concave steps in the "bow" or "stern" half.
static func _targets(poly: Array, at: String, side: String) -> Array:
	var box := _bounds(poly)
	var mid_y := box.position.y + box.size.y / 2.0
	var mid_x := box.position.x + box.size.x / 2.0
	var out: Array = []
	for i in poly.size():
		var f := _info(poly, i)
		var y: int = f["v"].y
		var ok := false
		if f["convex"]:
			match at:
				"tip":
					ok = y == box.position.y
				"stern_end":
					ok = y == box.end.y
				"shoulder":
					ok = y != box.position.y and y != box.end.y
				"all":
					ok = true
		else:
			match at:
				"bow":
					ok = y < mid_y
				"stern":
					ok = y >= mid_y
				"all":
					ok = true
		if ok and side != "":
			ok = (f["v"].x < mid_x) == (side == "left")
		if ok:
			out.append(f["v"])
	return out


## The side an op works on: "" (both), or one picked by the seed ("random_one").
static func _side(op: Dictionary, rng: RandomNumberGenerator) -> String:
	match str(op.get("side", "")):
		"random_one":
			return "left" if rng.randf() < 0.5 else "right"
		"left", "right":
			return str(op["side"])
	return ""


# --- ops ---------------------------------------------------------------------------------------------

## A wedge or chamfer op: its chance, side, kind and size are rolled once, then it is applied to every vertex it selects.
static func _apply(poly: Array, op: Dictionary, rng: RandomNumberGenerator, avoid: Array) -> void:
	if rng.randf() >= float(op.get("chance", 1.0)):
		return
	var side := _side(op, rng)
	var kinds: Array = op.get("kind", op.get("slope", ["45"]))
	var kind := str(kinds[rng.randi() % kinds.size()])
	var n := 1
	if op.has("n"):
		n = 99 if str(op["n"]) == "max" else rng.randi_range(int(op["n"][0]), int(op["n"][1]))
	var targets := _targets(poly, str(op["at"]), side)
	for v in targets:
		var i := poly.find(v)
		if i < 0:
			continue
		if str(op["op"]) == "wedge":
			if not _wedge(poly, i, kind) and kind != "45":
				_wedge(poly, i, "45")
		else:
			_chamfer(poly, i, kind, n, avoid)
	var clean := _dedupe(poly)
	poly.clear()
	poly.append_array(clean)


## Cut the convex corner i: legs (n, n) for "45", (2n, n) along the horizontal edge for "shallow", (n, 2n) for "steep".
## An n too big for the edges (or reaching into `avoid`, the rows of a flank that carries a turret) is cut down to what fits.
static func _chamfer(poly: Array, i: int, kind: String, n: int, avoid: Array) -> bool:
	var f := _info(poly, i)
	if not f["axis"] or not f["convex"]:
		return false
	var horizontal_in: bool = f["din"].y == 0
	var lh: int = f["lin"] if horizontal_in else f["lout"]  # the horizontal edge at the corner
	var lv: int = f["lout"] if horizontal_in else f["lin"]  # the vertical one
	var hm := 1
	var vm := 1
	match kind:
		"shallow":
			hm = 2
		"steep":
			vm = 2
	var corner: Vector2i = f["v"]
	var along: Vector2i = f["dout"] if horizontal_in else -f["din"]  # down the vertical edge from the corner
	n = mini(n, mini(lh / hm, lv / vm))
	while n >= 1:
		var y_b := corner.y + along.y * n * vm
		if not avoid.any(func(r): return mini(corner.y, y_b) < int(r[1]) + 1 and maxi(corner.y, y_b) > int(r[0])):
			break
		n -= 1
	if n < 1:
		return false
	var a_in := n * hm if horizontal_in else n * vm
	var a_out := n * vm if horizontal_in else n * hm
	poly[i] = corner - f["din"] * a_in
	poly.insert(i + 1, corner + f["dout"] * a_out)
	return true


## Fill the concave step i with a slope: the step's horizontal edge (length s) is joined to the vertical edge beside
## the step by a diagonal, 45 degrees (rises s), "shallow" (s even, rises s / 2) or "steep" (rises 2 s).
static func _wedge(poly: Array, i: int, kind: String) -> bool:
	var f := _info(poly, i)
	if not f["axis"] or f["convex"]:
		return false
	var out_horizontal: bool = f["dout"].y == 0
	var s: int = f["lout"] if out_horizontal else f["lin"]
	var vlen: int = f["lin"] if out_horizontal else f["lout"]
	var rise := s
	match kind:
		"shallow":
			if s % 2 != 0:
				return false
			rise = s / 2
		"steep":
			rise = 2 * s
	if rise > vlen or rise < 1:
		return false
	var away: Vector2i = -f["din"] if out_horizontal else f["dout"]  # from the step along the vertical edge
	poly[i] = f["v"] + away * rise
	return true


## Saw teeth on the long vertical flanks: 45 degree triangles `depth` deep, outside the shell, away from the rows in `avoid`.
static func _spikes(poly: Array, op: Dictionary, rng: RandomNumberGenerator, avoid: Array) -> void:
	if rng.randf() >= float(op.get("chance", 1.0)):
		return
	var depth := int(op.get("depth", 2))
	var teeth := rng.randi_range(int(op["count"][0]), int(op["count"][1]))
	var span := 2 * depth
	for _t in teeth:
		var spots: Array = []  # [edge index, first row of a tooth]
		for i in poly.size():
			var a: Vector2i = poly[i]
			var b: Vector2i = poly[(i + 1) % poly.size()]
			if a.x != b.x or absi(b.y - a.y) < span + 2:
				continue
			var y_lo := mini(a.y, b.y) + 1
			var y_hi := maxi(a.y, b.y) - 1 - span
			for y in range(y_lo, y_hi + 1):
				if not avoid.any(func(r): return y <= int(r[1]) and y + span >= int(r[0])):
					spots.append([i, y])
		if spots.is_empty():
			return
		var pick: Array = spots[rng.randi() % spots.size()]
		var i: int = pick[0]
		var a: Vector2i = poly[i]
		var b: Vector2i = poly[(i + 1) % poly.size()]
		var d := _sgn(b - a)
		var out := Vector2i(d.y, -d.x)  # outward of a clockwise polygon
		var base := Vector2i(a.x, int(pick[1]) if d.y > 0 else int(pick[1]) + span)
		var tooth: Array = [base, base + out * depth + d * depth, base + d * span]
		for k in tooth.size():
			poly.insert(i + 1 + k, tooth[k])


## Mark convex corners to be drawn as round2 arcs (both edges at least 2 long, no arcs side by side on a short edge).
static func _arcs(poly: Array, op: Dictionary, rng: RandomNumberGenerator, arcs: Dictionary) -> void:
	var side := _side(op, rng)
	var count := rng.randi_range(int(op["count"][0]), int(op["count"][1]))
	var targets := _targets(poly, str(op["at"]), side)
	var order: Array = []
	while not targets.is_empty():
		order.append(targets.pop_at(rng.randi() % targets.size()))
	for v in order:
		if count <= 0:
			break
		var i := poly.find(v)
		var f := _info(poly, i)
		if not f["axis"] or not f["convex"] or f["lin"] < 2 or f["lout"] < 2:
			continue
		var n := poly.size()
		var prev: Vector2i = poly[(i + n - 1) % n]
		var next: Vector2i = poly[(i + 1) % n]
		if (arcs.has(prev) and f["lin"] < 4) or (arcs.has(next) and f["lout"] < 4):
			continue
		arcs[v] = true
		count -= 1


## The round2 arc replacing the convex corner i: radius 2, centred inside the corner.
static func _arc_entry(poly: Array, i: int) -> Array:
	var f := _info(poly, i)
	var v: Vector2i = f["v"]
	var c: Vector2i = v + (f["dout"] - f["din"]) * 2
	var from := rad_to_deg(atan2(-f["dout"].y, -f["dout"].x))
	var to := rad_to_deg(atan2(f["din"].y, f["din"].x))
	from = fposmod(from, 360.0)
	to = fposmod(to, 360.0)
	if to <= from:
		to += 360.0
	return ["arc", c.x, c.y, roundf(from), roundf(to)]


## The same cells and errors as HullOutline.rasterize(outline), faster: only the cells a slope or an arc crosses are cut out
## of the polygon; every other cell is full or empty by whether its centre is inside.
static func raster(outline: Array) -> Dictionary:
	var poly := HullOutline.polygon(outline)
	var n := poly.size()
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var y0 := floori(lo.y)
	var y1 := ceili(hi.y)
	var x0 := floori(lo.x)
	var cut := {}  # cells a slanted edge crosses
	var crossings: Array = []  # per row: the x where an edge crosses the row's middle line
	for _y in range(y0, y1):
		crossings.append([])
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		if a.y == b.y:
			continue
		var ya := minf(a.y, b.y)
		var yb := maxf(a.y, b.y)
		for y in range(maxi(y0, floori(ya)), mini(y1, ceili(yb))):
			var mid := y + 0.5
			if mid > ya and mid < yb:
				crossings[y - y0].append(a.x + (mid - a.y) * (b.x - a.x) / (b.y - a.y))
			if a.x != b.x:  # slanted: the cells it passes through in this row
				var xa := a.x + (maxf(float(y), ya) - a.y) * (b.x - a.x) / (b.y - a.y)
				var xb := a.x + (minf(float(y + 1), yb) - a.y) * (b.x - a.x) / (b.y - a.y)
				for x in range(floori(minf(xa, xb) + 1e-6), maxi(ceili(maxf(xa, xb) - 1e-6), floori(minf(xa, xb) + 1e-6) + 1)):
					cut[Vector2i(x, y)] = true
	var cells := {}
	var errors := []
	for y in range(y0, y1):
		var xs: Array = crossings[y - y0]
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(roundi(xs[k] - 0.5 + 1e-6), roundi(xs[k + 1] - 0.5 + 1e-6)):
				if not cut.has(Vector2i(x, y)):
					cells[Vector2i(x, y)] = {}
	for c in cut:
		var piece := HullOutline._clip(poly, Vector2(c.x, c.y))
		var area := absf(Shapes.polygon_area(piece))
		if area < HullOutline.EPS:
			continue
		if area > 1.0 - HullOutline.EPS:
			cells[c] = {}
			continue
		var sd := HullOutline._match(piece, area)
		if sd.is_empty():
			errors.append("cell %s: the outline cuts it into %s, which is no shape of shapes.json" % [str(c), str(piece)])
		else:
			cells[c] = sd
	return {"cells": cells, "errors": errors}


## The area of the cells of a rasterized outline over their bounding box (a slope or a curve counts its solid part).
static func fill_ratio(cells: Dictionary) -> float:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	var area := 0.0
	for c in cells:
		lo = lo.min(c)
		hi = hi.max(c)
		area += 1.0 if cells[c].is_empty() else minf(Shapes.area_of(cells[c]), 1.0)
	return area / float((hi.x - lo.x + 1) * (hi.y - lo.y + 1))
