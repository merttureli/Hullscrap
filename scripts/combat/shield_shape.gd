extends RefCounted
## The outline of a shield bubble: the convex hull of the ship's solid cells (their corners, so the
## whole cell counts) pushed out by INFLATE cells with rounded corners. So it hugs a long, wedge-shaped
## or lumpy ship and never cuts through the hull. Pure geometry in the ship's own cell coordinates (no
## nodes, no randomness); Shields caches one per arena ship and rebuilds it when the cells change.
## - contains(p), margin(p): is a point inside, and how far in (the distance to the outline).
## - entry_t(a, b), exit_t(a, b): where the segment a -> b meets the outline, as a fraction 0..1.
## - sector_at(v, n): the sector of a vector from the centre, sector 0 centred on the bow (up).
## - outline() and sector_lines(n): the points to draw.

const INFLATE := 1.5  ## cells between the hull of the cells and the bubble
const ARC_STEPS := 8  ## points on each rounded corner
const EPS := 1e-7

var verts := PackedVector2Array()  ## the hull of the cell corners, turning the same way all round (left turns, y down)
var centre := Vector2.ZERO  ## where the sectors start: the ship's pivot
var radius := INFLATE  ## cells from the centre to the farthest point of the outline
var inflate := INFLATE
var _normals := PackedVector2Array()  # outward unit normal of edge i (verts[i] -> verts[i+1])
var _outline := PackedVector2Array()
var _lines := {}  # n -> sector_lines(n)
var _grown := {}  # extra -> a wider shape


## The shape round the cell corners of `cells` (Vector2i, any iterable), sectors counted from `centre`
## (the middle of the cells when INF). No cells: a single cell at the centre.
static func from_cells(cells, centre := Vector2.INF, grow := INFLATE) -> RefCounted:
	var pts := PackedVector2Array()
	for c in cells:
		var v := Vector2(c)
		pts.append(v)
		pts.append(v + Vector2(1.0, 0.0))
		pts.append(v + Vector2(0.0, 1.0))
		pts.append(v + Vector2.ONE)
	if pts.is_empty():
		pts = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE])
	var s: RefCounted = (load("res://scripts/combat/shield_shape.gd") as GDScript).new()
	s.inflate = grow
	s.verts = hull_of(pts)
	if centre == Vector2.INF:
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in s.verts:
			lo = lo.min(p)
			hi = hi.max(p)
		centre = (lo + hi) / 2.0
	s.centre = centre
	s._prepare()
	return s


## The cells that make a ship's bubble: every wall and door, every part's cell (a hull mount's outside
## half too), every cell shot open (a breach does not change the shape), and the hull cells when there is
## nothing else.
static func cells_of(ship) -> Array:
	var g = ship.grid
	var solid := {}
	for c in g.tiles:
		var d: Dictionary = g.defs.get_def(g.tiles[c]) if g.defs != null else {}
		if bool(d.get("solid", false)) or bool(d.get("door", false)):
			solid[c] = true
	for c in g.breached:
		solid[c] = true
	for uid in ship.components.instances:
		var inst: Dictionary = ship.components.instances[uid]
		for c in inst["cells"]:
			solid[c] = true
		for c in inst.get("out_cells", []):  # the outside half of a hull mount sits in space: the bubble goes round it
			solid[c] = true
	return solid.keys() if not solid.is_empty() else g.hull.keys()


## The middle of the hull's bounding box in cell coordinates: the pivot the arena uses.
static func centre_of(ship) -> Vector2:
	var g = ship.grid
	if g.hull.is_empty():
		return Vector2(g.size) / 2.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in g.hull:
		lo = lo.min(Vector2(c))
		hi = hi.max(Vector2(c) + Vector2.ONE)
	return (lo + hi) / 2.0


## A cheap fingerprint of the cells cells_of() reads, to tell when the shape needs rebuilding.
static func signature(ship) -> Array:
	var g = ship.grid
	return [g.tiles.size(), g.breached.size(), g.hull.size(), g.shapes.size(), ship.components.instances.size()]


## The convex hull of `pts` (Andrew's monotone chain), turning left all the way round, without collinear points.
static func hull_of(pts: PackedVector2Array) -> PackedVector2Array:
	var p: Array = Array(pts)
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var out: Array = []
	for pass_no in 2:
		var start := out.size()
		for q in p:
			while out.size() >= start + 2 and (out[-1] - out[-2]).cross(q - out[-2]) <= 0.0:
				out.pop_back()
			out.append(q)
		out.pop_back()
		p.reverse()
	return PackedVector2Array(out)


## The sector (0..n-1) of the vector `v` from the centre: sector 0 is centred on the bow (up), the rest follow clockwise on screen.
static func sector_at(v: Vector2, n: int) -> int:
	if n <= 1 or v.length_squared() < 1e-12:
		return 0
	return posmod(floori((atan2(v.x, -v.y) + PI / n) / (TAU / n)), n)


func _prepare() -> void:
	var n := verts.size()
	_normals = PackedVector2Array()
	var area := 0.0
	for i in n:
		area += verts[i].cross(verts[(i + 1) % n])
	for i in n:
		var e := verts[(i + 1) % n] - verts[i]
		_normals.append(Vector2(e.y, -e.x).normalized() * (1.0 if area >= 0.0 else -1.0))
	radius = 0.0
	for v in verts:
		radius = maxf(radius, v.distance_to(centre) + inflate)


# --- points -----------------------------------------------------------------------------------------

## Distance from `p` to the hull of the cells (0 inside it).
func hull_distance(p: Vector2) -> float:
	var n := verts.size()
	var inside := true
	var best := INF
	for i in n:
		var a := verts[i]
		var b := verts[(i + 1) % n]
		var ab := b - a
		if ab.cross(p - a) < 0.0:
			inside = false
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return 0.0 if inside else best


## How far inside the outline `p` is (the distance to the outline); negative outside.
func margin(p: Vector2) -> float:
	var d := hull_distance(p)
	if d > 0.0:
		return inflate - d
	var n := verts.size()
	var depth := INF
	for i in n:
		depth = minf(depth, absf((p - verts[i]).dot(_normals[i])))
	return inflate + depth


func contains(p: Vector2) -> bool:
	return hull_distance(p) <= inflate + EPS


# --- segments ---------------------------------------------------------------------------------------

## The fractions t in 0..1 where the segment a -> b crosses the outline, ascending: along the flat
## sides (the hull's edges moved out by `inflate`) and round the corner arcs.
func crossings(a: Vector2, b: Vector2) -> Array[float]:
	var d := b - a
	var out: Array[float] = []
	var n := verts.size()
	var qa := d.dot(d)
	for i in n:
		var v := verts[i]
		var nm := _normals[i]
		var p0 := v + nm * inflate
		var e := verts[(i + 1) % n] + nm * inflate - p0
		var den := d.cross(e)
		if absf(den) > 1e-12:
			var w := p0 - a
			var t := w.cross(e) / den
			var u := w.cross(d) / den
			if t >= -EPS and t <= 1.0 + EPS and u >= -EPS and u <= 1.0 + EPS:
				out.append(clampf(t, 0.0, 1.0))
		if qa < 1e-12:
			continue
		var f := a - v
		var qb := 2.0 * f.dot(d)
		var disc := qb * qb - 4.0 * qa * (f.dot(f) - inflate * inflate)
		if disc < 0.0:
			continue
		var root := sqrt(disc)
		var prev := _normals[(i + n - 1) % n]
		for t in [(-qb - root) / (2.0 * qa), (-qb + root) / (2.0 * qa)]:
			if t < -EPS or t > 1.0 + EPS:
				continue
			var q: Vector2 = f + d * t
			if prev.cross(q) >= -EPS * inflate and q.cross(nm) >= -EPS * inflate:  # on the arc between the two sides
				out.append(clampf(t, 0.0, 1.0))
	out.sort()
	return out


## Where the segment a -> b first enters the outline (a fraction 0..1); -1 when it does not, or when
## it starts inside (it is in already).
func entry_t(a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var near := clampf((centre - a).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
	if (a + ab * near).distance_to(centre) > radius:
		return -1.0  # the segment never comes within the bubble's reach
	if contains(a):
		return -1.0
	var ts := crossings(a, b)
	if not ts.is_empty():
		return ts[0]
	if not contains(b):
		return -1.0
	var lo := 0.0  # a rounding miss: the end is inside, so bisect for the edge
	var hi := 1.0
	for i in 40:
		var mid := (lo + hi) / 2.0
		if contains(a.lerp(b, mid)):
			hi = mid
		else:
			lo = mid
	return hi


## Where the segment a -> b last crosses the outline (a fraction 0..1): the way out of a point inside. -1 for none.
func exit_t(a: Vector2, b: Vector2) -> float:
	var ts := crossings(a, b)
	return ts[-1] if not ts.is_empty() else -1.0


## The outline point in the direction `dir` from the centre.
func boundary_toward(dir: Vector2) -> Vector2:
	var far := centre + dir.normalized() * (radius + 1.0)
	var t := exit_t(centre, far)
	return centre.lerp(far, t) if t >= 0.0 else centre


# --- drawing ----------------------------------------------------------------------------------------

## The outline, point by point all the way round: the corner arcs, ARC_STEPS points each.
func outline() -> PackedVector2Array:
	if not _outline.is_empty():
		return _outline
	var n := verts.size()
	for i in n:
		var from := _normals[(i + n - 1) % n].angle()
		var to := _normals[i].angle()
		var turn := wrapf(to - from, 0.0, TAU)
		for k in ARC_STEPS + 1:
			_outline.append(verts[i] + Vector2.from_angle(from + turn * k / ARC_STEPS) * inflate)
	return _outline


## The outline cut into the `n` sectors: n polylines (cell coordinates), sector k from its first
## boundary round to its second, clockwise on screen. One sector: the whole loop, closed.
func sector_lines(n: int) -> Array:
	if _lines.has(n):
		return _lines[n]
	var pts := outline()
	var width := TAU / n
	var out := []
	for k in n:
		var a0 := (float(k) - 0.5) * width if n > 1 else -PI
		var mine := []
		for p in pts:
			var delta := fposmod(atan2(p.x - centre.x, centre.y - p.y) - a0, TAU)
			if delta > 1e-6 and delta < width - 1e-6:
				mine.append([delta, p])
		mine.sort_custom(func(x, y): return x[0] < y[0])
		var line := PackedVector2Array([boundary_toward(Vector2(sin(a0), -cos(a0)))])
		for m in mine:
			line.append(m[1])
		var a1 := a0 + width
		line.append(boundary_toward(Vector2(sin(a1), -cos(a1))))
		out.append(line)
	_lines[n] = out
	return out


## The same shape `extra` cells wider (cached).
func grown(extra: float) -> RefCounted:
	if not _grown.has(extra):
		var s: RefCounted = (load("res://scripts/combat/shield_shape.gd") as GDScript).new()
		s.inflate = inflate + extra
		s.verts = verts
		s.centre = centre
		s._prepare()
		_grown[extra] = s
	return _grown[extra]
