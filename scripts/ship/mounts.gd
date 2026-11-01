extends RefCounted
## Hull mounts (docs/CONTENT.md 4f): a weapon or engine is two linked halves through a wall of any
## thickness. The OUTSIDE half sits in space against the outer wall face, the INSIDE half on the floor
## against the inner face, and between them is the LINK: a straight run of full wall cells across the
## mount's width, at least one cell deep. At rotation 0 outward is UP (the outside half above the
## wall); rotation r turns it r quarter turns clockwise. Static geometry and placement rules, no state
## (components.gd keeps the placed mounts).
##
## The player points at the outside half's top-left cell; plan() walks inward from there through the
## wall and puts the inside half on the first floor rows behind it. from_inside() runs the same rule
## the other way for a part saved before mounts existed (it only knows the inside half). A breech narrower
## than the outside half (a tier 1-2 gun or engine: 2 wide behind a 4 wide barrel) sits centred behind it
## (breech_shift); the link stays as wide as the outside half.
##
## ANGLED mounts: on a straight run of sloped hull cells (the 45 degree `tri`, the 1:2 `tri2_*` slopes) the outside
## half lies against the slope turned to its outward normal (`angle`, degrees clockwise from up, like `rot` x 90),
## while the inside half stays flush with the grid at the nearest quarter turn (plan_slope). The link is the sloped
## cells under the barrel plus the wall cells between them and the floor.

const Art = preload("res://scripts/view/art.gd")
const Shapes = preload("res://scripts/ship/shapes.gd")

const NONE := Vector2i(-1, -1)  ## "no outside half"
const OUTWARD: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]  ## by rotation
const MAX_DEPTH := 32  ## how many wall layers the walk looks through
const SRC_CELL := 16.0  ## art source px per grid cell
const DEFAULT_REACH := 1.5  ## cells from the barrel pivot to its muzzle when there is no art
const SLOPE_REACH := 2.5  ## how far (cells) from a sloped face the pointer still snaps to it
const SLOPE_TOL := 0.02  ## how much (cells) two shapes may overlap and still count as touching
const MAX_RUN := 64  ## the most faces a straight run is followed over
const FACE_ANGLES: Array[float] = [26.565051, 45.0, 63.434949]  ## the supported slopes, off an axis (in every quadrant)

static var _art := {}  # "<art root>/<id>" -> {pivot_px (in the rotation 0 art of the outside half), reach}


static func is_mount(def: Dictionary) -> bool:
	return def.get("mount") is Dictionary


## The outward direction (a unit cell step) of a mount turned `rot` quarter turns.
static func outward(rot: int) -> Vector2i:
	return OUTWARD[posmod(rot, 4)]


## `size` (w, h as at rotation 0) turned `rot` quarter turns: odd turns swap width and height.
static func turned(size: Array, rot: int) -> Vector2i:
	return Vector2i(int(size[1]), int(size[0])) if posmod(rot, 2) == 1 else Vector2i(int(size[0]), int(size[1]))


static func rect_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in r.size.y:
		for x in r.size.x:
			out.append(r.position + Vector2i(x, y))
	return out


## How far a breech `isz` wide sits along the wall from the outside half's edge `osz`: centred behind it
## when narrower, else flush (a wider console starts at the barrel's edge). Sizes are already turned.
static func breech_shift(osz: Vector2i, isz: Vector2i, rot: int) -> Vector2i:
	if posmod(rot, 2) == 0:
		return Vector2i(maxi(0, int((osz.x - isz.x) / 2.0)), 0)
	return Vector2i(0, maxi(0, int((osz.y - isz.y) / 2.0)))


## The cells of wall layer `k` (0 is against the outside half) of a mount whose outside half is `outside`.
static func layer(outside: Rect2i, rot: int, k: int) -> Array[Vector2i]:
	match outward(rot):
		Vector2i.UP:
			return rect_cells(Rect2i(outside.position.x, outside.end.y + k, outside.size.x, 1))
		Vector2i.DOWN:
			return rect_cells(Rect2i(outside.position.x, outside.position.y - 1 - k, outside.size.x, 1))
		Vector2i.RIGHT:
			return rect_cells(Rect2i(outside.position.x - 1 - k, outside.position.y, 1, outside.size.y))
	return rect_cells(Rect2i(outside.end.x + k, outside.position.y, 1, outside.size.y))


## Where the two halves of a mount of `def` turned `rot` are, with the outside half's top-left on
## `out` and a wall `depth` layers thick between them: {inside: Rect2i, outside: Rect2i, link: cells}.
## The halves start together along the wall, a narrower breech centred behind the barrel (breech_shift).
static func layout(def: Dictionary, out: Vector2i, rot: int, depth: int) -> Dictionary:
	var osz := turned(def["mount"]["outside"], rot)
	var isz := turned(def["size"], rot)
	var outside := Rect2i(out, osz)
	var link: Array[Vector2i] = []
	for k in depth:
		link.append_array(layer(outside, rot, k))
	var at := out
	match outward(rot):
		Vector2i.UP:
			at = Vector2i(out.x, out.y + osz.y + depth)
		Vector2i.DOWN:
			at = Vector2i(out.x, out.y - depth - isz.y)
		Vector2i.RIGHT:
			at = Vector2i(out.x - depth - isz.x, out.y)
		_:
			at = Vector2i(out.x + osz.x + depth, out.y)
	return {"inside": Rect2i(at + breech_shift(osz, isz, rot), isz), "outside": outside, "link": link}


## The wall depth between a saved outside top-left `out` and inside top-left `anchor`, or 0 when the
## two do not line up as one mount (not on the same axis, or not on opposite sides of a wall).
static func depth_of(def: Dictionary, anchor: Vector2i, rot: int, out: Vector2i) -> int:
	for depth in range(1, MAX_DEPTH + 1):
		if layout(def, out, rot, depth)["inside"].position == anchor:
			return depth
	return 0


## Why a mount `def` turned `rot` cannot have its outside half's top-left on `out`, or "" (`why`).
## On success the result also has: anchor (the inside half's top-left), depth, cells (inside),
## out_cells, link. `comps`: the placed components (components.gd), `grid`: the ship grid.
static func plan(grid, comps, def: Dictionary, out: Vector2i, rot: int) -> Dictionary:
	var res := {"why": "", "anchor": NONE, "depth": 0, "cells": [], "out_cells": [], "link": []}
	var outside := Rect2i(out, turned(def["mount"]["outside"], rot))
	for c in rect_cells(outside):
		if not grid.in_bounds(c) or grid.get_tile(c) != "" or comps.any_at(c) >= 0:
			res["why"] = "the barrel must stick out into space"
			return res
	var depth := 0
	while depth < MAX_DEPTH and layer(outside, rot, depth).all(func(c): return flat_wall(grid, c)):
		depth += 1
	if depth == 0:
		res["why"] = "needs an outer wall or a slope to mount through"
		return res
	var lay := layout(def, out, rot, depth)
	var inside := rect_cells(lay["inside"])
	if not inside.all(func(c): return comps.free_floor(grid, c)):
		res["why"] = "the breech needs %dx%d free floor behind the wall" % [lay["inside"].size.x, lay["inside"].size.y]
		return res
	res.merge({"anchor": lay["inside"].position, "depth": depth, "cells": inside, "out_cells": rect_cells(lay["outside"]), "link": lay["link"]}, true)
	return res


## The same rule the other way: a part whose inside half is at `anchor` (rotation `rot`) mounted
## through the wall on its outward side. `why` is "" and the plan() entries are there when it can be
## (the part's own cells count as free floor); `out` is where the outside half would have been.
static func from_inside(grid, comps, def: Dictionary, anchor: Vector2i, rot: int) -> Dictionary:
	var isz := turned(def["size"], rot)
	var osz := turned(def["mount"]["outside"], rot)
	var base := anchor - breech_shift(osz, isz, rot)  # where the halves start together along the wall
	var wide := Vector2i(maxi(osz.x, isz.x), isz.y) if posmod(rot, 2) == 0 else Vector2i(isz.x, maxi(osz.y, isz.y))
	var look := Rect2i(base, wide)  # the cells the wall walk looks through: the barrel's full width behind it
	var depth := 0
	while depth < MAX_DEPTH and _beyond(look, rot, depth).all(func(c): return flat_wall(grid, c)):
		depth += 1
	var out := base
	match outward(rot):
		Vector2i.UP:
			out = Vector2i(base.x, anchor.y - depth - osz.y)
		Vector2i.DOWN:
			out = Vector2i(base.x, anchor.y + isz.y + depth)
		Vector2i.RIGHT:
			out = Vector2i(anchor.x + isz.x + depth, base.y)
		_:
			out = Vector2i(anchor.x - depth - osz.x, base.y)
	if depth == 0:
		return {"why": "needs an outer wall or a slope to mount through", "out": out}
	var own := {}
	for c in rect_cells(Rect2i(anchor, isz)):
		own[c] = true
	var p := plan(grid, _Placed.new(comps, own), def, out, rot)
	p["out"] = out
	return p


## The cells `k` layers beyond the outward edge of the inside half `inside`.
static func _beyond(inside: Rect2i, rot: int, k: int) -> Array[Vector2i]:
	match outward(rot):
		Vector2i.UP:
			return rect_cells(Rect2i(inside.position.x, inside.position.y - 1 - k, inside.size.x, 1))
		Vector2i.DOWN:
			return rect_cells(Rect2i(inside.position.x, inside.end.y + k, inside.size.x, 1))
		Vector2i.RIGHT:
			return rect_cells(Rect2i(inside.end.x + k, inside.position.y, 1, inside.size.y))
	return rect_cells(Rect2i(inside.position.x - 1 - k, inside.position.y, 1, inside.size.y))


## The link and outside cells of a mount saved with its outside top-left `out`: the plan() entries
## (no `why`), or {} when the two halves do not line up. Reads no grid.
static func cells_of(def: Dictionary, anchor: Vector2i, rot: int, out: Vector2i) -> Dictionary:
	var depth := depth_of(def, anchor, rot, out)
	if depth == 0:
		return {}
	var lay := layout(def, out, rot, depth)
	return {"anchor": anchor, "depth": depth, "cells": rect_cells(lay["inside"]), "out_cells": rect_cells(lay["outside"]), "link": lay["link"]}


## A full, flat, plain wall cell: a solid tile with no door, no shape and no breach.
static func flat_wall(grid, c: Vector2i) -> bool:
	var id: String = grid.get_tile(c)
	return id != "" and grid.tile_flag(id, "solid") and not grid.tile_flag(id, "door") and grid.shape_of(c).is_empty()


## Where a shot leaves a mount: {pivot: the barrel's turning point (ship-local cell coordinates),
## reach: cells from the pivot to the muzzle}, read from the art's anchors (art/components/<id>_out.json
## has the pivot on the outside half and the barrel's pivot and muzzle). The art is drawn at rotation 0
## (outward up), so the pivot turns about the middle of the outside half with the part. Without that art:
## the middle of the outside half and DEFAULT_REACH.
static func barrel(def: Dictionary, out: Vector2i, rot: int) -> Dictionary:
	return _barrel_at(def, Vector2(out) + Vector2(turned(def["mount"]["outside"], rot)) / 2.0, posmod(rot, 4) * PI / 2.0)


## barrel() for an outside half whose middle is `centre` (grid coordinates), turned `angle` radians clockwise.
static func _barrel_at(def: Dictionary, centre: Vector2, angle: float) -> Dictionary:
	var key := "%s/%s" % [Art.root, def.get("id", "")]
	if not _art.has(key):
		_art[key] = _read_barrel(def)
	var raw: Array = def["mount"]["outside"]
	var half := Vector2(float(raw[0]), float(raw[1])) * SRC_CELL / 2.0
	var pivot_px: Vector2 = _art[key]["pivot_px"]
	return {"pivot": centre + (pivot_px - half).rotated(angle) / SRC_CELL, "reach": _art[key]["reach"]}


static func _read_barrel(def: Dictionary) -> Dictionary:
	var raw: Array = def["mount"]["outside"]
	var out := {"pivot_px": Vector2(float(raw[0]), float(raw[1])) * SRC_CELL / 2.0, "reach": DEFAULT_REACH}
	var b = Art.read_json("%s/components/%s_out.json" % [Art.root, def.get("id", "")]).get("barrel")
	if b is Dictionary:
		if b.get("pivot_on_base") is Array and b["pivot_on_base"].size() == 2:
			out["pivot_px"] = Vector2(float(b["pivot_on_base"][0]), float(b["pivot_on_base"][1]))
		var on = b.get("pivot_on_barrel")
		var mz = b.get("muzzle")
		if on is Array and mz is Array and on.size() == 2 and mz.size() == 2:
			out["reach"] = absf(float(on[1]) - float(mz[1])) / SRC_CELL
	return out


# --- angled mounts --------------------------------------------------------------------------------

## The angle (degrees clockwise from up) the placed mount (or ghost) `inst` faces: its `angle`, else rot x 90.
static func angle_of(inst: Dictionary) -> float:
	return float(inst.get("angle", posmod(int(inst.get("rot", 0)), 4) * 90))


## Does `inst` sit on a slope (its angle is not its quarter turn)?
static func is_angled(inst: Dictionary) -> bool:
	return inst.has("angle") and absf(wrapf(float(inst["angle"]) - posmod(int(inst.get("rot", 0)), 4) * 90.0, -180.0, 180.0)) > 0.01


## The unit vector (ship-local, up is -y) a mount faces: its true outward direction; exactly the cell step on a quarter turn.
static func dir_of(inst: Dictionary) -> Vector2:
	if not is_angled(inst):
		return Vector2(outward(int(inst.get("rot", 0))))
	return normal_of(float(inst["angle"]))


## The unit outward vector of angle `a` (degrees clockwise from up), and the unit vector along the face (a quarter turn on).
static func normal_of(a: float) -> Vector2:
	return Vector2.UP.rotated(deg_to_rad(a))


static func along_of(a: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(a))


## The middle of the outside half of placed mount `inst`, in grid coordinates.
static func out_centre(def: Dictionary, inst: Dictionary) -> Vector2:
	var raw: Array = def["mount"]["outside"]
	if is_angled(inst):
		return Vector2(inst["out_at"]) + dir_of(inst) * float(raw[1]) / 2.0
	return Vector2(inst["out_anchor"]) + Vector2(turned(raw, int(inst["rot"]))) / 2.0


## The box (grid cells) of the outside half's quarter-turn size about its middle: its own cells on a straight mount.
static func out_rect(def: Dictionary, inst: Dictionary) -> Rect2:
	var sz := Vector2(turned(def["mount"]["outside"], int(inst["rot"])))
	return Rect2(out_centre(def, inst) - sz / 2.0, sz)


## The four corners (grid coordinates) of an outside half `w` along the face and `h` out, its base middle on `at`, facing `angle`.
static func out_polygon(at: Vector2, angle: float, w: float, h: float) -> PackedVector2Array:
	var t := along_of(angle) * w / 2.0
	var n := normal_of(angle) * h
	return PackedVector2Array([at - t, at + t, at + t + n, at - t + n])


## Where a shot leaves placed mount `inst`: barrel() for its outside half, turned to its angle on a slope.
static func barrel_of(def: Dictionary, inst: Dictionary) -> Dictionary:
	if not is_angled(inst):
		return barrel(def, inst["out_anchor"], int(inst["rot"]))
	return _barrel_at(def, out_centre(def, inst), deg_to_rad(float(inst["angle"])))


## The supported slope angle (degrees clockwise from up) of the unit outward normal `n`, or -1 when it is not one.
static func face_angle(n: Vector2) -> float:
	var a := fposmod(rad_to_deg(atan2(n.x, -n.y)), 360.0)
	var r := fmod(a, 90.0)
	for f in FACE_ANGLES:
		if absf(r - f) < 0.5:
			return floorf(a / 90.0) * 90.0 + f
	return -1.0


## The sloped faces of the solid cell `c`: [{a, b (grid coordinates, running along the face), angle, cell}].
static func cell_faces(grid, c: Vector2i) -> Array:
	var id: String = grid.get_tile(c)
	var sd: Dictionary = grid.shape_of(c)
	if id == "" or sd.is_empty() or not grid.tile_flag(id, "solid"):
		return []
	var shape := str(sd["shape"])
	var poly := Shapes.cell_polygon(shape, int(sd["rot"]), bool(sd["mirror"]))
	var nrm := Shapes.edge_normals(shape, int(sd["rot"]), bool(sd["mirror"]))
	var out := []
	for i in poly.size():
		var ang := face_angle(nrm[i])
		if ang >= 0.0:
			out.append({"a": Vector2(c) + poly[i], "b": Vector2(c) + poly[(i + 1) % poly.size()], "angle": ang, "cell": c})
	return out


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 4.0), roundi(p.y * 4.0))


## The face of the same angle that starts at `p` (`forward`) or ends there, else {}.
static func _face_from(grid, p: Vector2, angle: float, forward: bool) -> Dictionary:
	var seen := {}
	for dx in [-0.01, 0.01]:
		for dy in [-0.01, 0.01]:
			var c := Vector2i(floori(p.x + dx), floori(p.y + dy))
			if seen.has(c):
				continue
			seen[c] = true
			for f in cell_faces(grid, c):
				if absf(f["angle"] - angle) < 0.01 and _key(f["a" if forward else "b"]) == _key(p):
					return f
	return {}


## The straight run of faces `face` is part of, in order along it: each face starts where the last one ends.
static func face_run(grid, face: Dictionary) -> Array:
	var run := [face]
	var cur := face
	for _i in MAX_RUN:
		var nx := _face_from(grid, cur["b"], face["angle"], true)
		if nx.is_empty():
			break
		run.append(nx)
		cur = nx
	cur = face
	for _i in MAX_RUN:
		var pv := _face_from(grid, cur["a"], face["angle"], false)
		if pv.is_empty():
			break
		run.push_front(pv)
		cur = pv
	return run


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0))


## The sloped face nearest the grid point `p` (within SLOPE_REACH, and `p` on its outer side), else {}.
static func nearest_face(grid, p: Vector2) -> Dictionary:
	var best := {}
	var best_d := SLOPE_REACH + 1.0
	for y in range(floori(p.y - SLOPE_REACH), floori(p.y + SLOPE_REACH) + 1):
		for x in range(floori(p.x - SLOPE_REACH), floori(p.x + SLOPE_REACH) + 1):
			for f in cell_faces(grid, Vector2i(x, y)):
				if (p - f["a"]).dot(normal_of(f["angle"])) < -0.25:
					continue
				var d := _dist_to_segment(p, f["a"], f["b"])
				if d < best_d - 1e-9:
					best = f
					best_d = d
	return best if best_d <= SLOPE_REACH else {}


## Do the convex polygons `a` and `b` overlap by more than SLOPE_TOL? Sharing an edge or a corner is not overlap.
static func polys_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for poly in [a, b]:
		for i in poly.size():
			var e: Vector2 = poly[(i + 1) % poly.size()] - poly[i]
			if e.length_squared() < 1e-12:
				continue
			var ax := Vector2(e.y, -e.x).normalized()
			var lo := [INF, INF]
			var hi := [-INF, -INF]
			for k in 2:
				for v in [a, b][k]:
					var d := ax.dot(v)
					lo[k] = minf(lo[k], d)
					hi[k] = maxf(hi[k], d)
			if minf(hi[0], hi[1]) - maxf(lo[0], lo[1]) <= SLOPE_TOL:
				return false
	return true


static func _cell_poly(grid, c: Vector2i) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in grid.polygon_at(c):
		out.append(Vector2(c) + v)
	return out


static func _cell_square(c: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([Vector2(c), Vector2(c) + Vector2.RIGHT, Vector2(c) + Vector2.ONE, Vector2(c) + Vector2.DOWN])


## The cells of a slope mount's outside half `poly` (about `at`, `angle`, `w` x `h`) that are empty space and under it: those
## whose middle is inside it and those holding its centre or the middles of its four quarters. In (y, x) order.
static func slope_out_cells(grid, at: Vector2, angle: float, w: float, h: float) -> Array[Vector2i]:
	var t := along_of(angle)
	var n := normal_of(angle)
	var found := {}
	var poly := out_polygon(at, angle, w, h)
	var lo := Vector2i(floori(poly[0].x), floori(poly[0].y))
	var hi := lo
	for v in poly:
		lo = lo.min(Vector2i(floori(v.x), floori(v.y)))
		hi = hi.max(Vector2i(floori(v.x), floori(v.y)))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var m := Vector2(x, y) + Vector2(0.5, 0.5) - at
			if absf(m.dot(t)) < w / 2.0 and m.dot(n) > 0.0 and m.dot(n) < h:
				found[Vector2i(x, y)] = true
	for q in [Vector2(0, h / 2.0), Vector2(-w / 4.0, h / 4.0), Vector2(w / 4.0, h / 4.0), Vector2(-w / 4.0, h * 0.75), Vector2(w / 4.0, h * 0.75)]:
		var pt: Vector2 = at + t * q.x + n * q.y
		found[Vector2i(floori(pt.x), floori(pt.y))] = true
	var out: Array[Vector2i] = []
	for c in found:
		if grid.in_bounds(c) and grid.get_tile(c) == "":
			out.append(c)
	out.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


## Plan mount `def` against the sloped hull face nearest the grid point `p` (the pointer). {angled: false} when no sloped face is
## near. Otherwise {angled: true, why ("" when it can go), angle, at (the base middle of the outside half, on the face), rot (the
## nearest quarter turn, for the inside half), out (the cell holding `at`)} and, when the rest fits, the plan() entries: anchor,
## depth (the wall cells behind the slope), cells (inside), out_cells (the empty cells under the barrel), link (the sloped cells
## under the barrel and the wall behind them). The outside half lies flat on one straight face at least as wide as the barrel; the
## inside half goes on the free floor the barrel's middle line meets, flush with the grid.
static func plan_slope(grid, comps, def: Dictionary, p: Vector2) -> Dictionary:
	var face := nearest_face(grid, p)
	if face.is_empty():
		return {"angled": false, "why": ""}
	var raw: Array = def["mount"]["outside"]
	var w := float(raw[0])
	var h := float(raw[1])
	var angle: float = face["angle"]
	var t := along_of(angle)
	var n := normal_of(angle)
	var run := face_run(grid, face)
	var start: Vector2 = run[0]["a"]
	var length: float = (run[run.size() - 1]["b"] - start).length()
	var res := {"angled": true, "why": "", "angle": angle, "at": start, "rot": 0, "out": NONE, "anchor": NONE, "depth": 0, "cells": [], "out_cells": [], "link": []}
	var want := (p - start).dot(t)
	var s := clampf(want, 0.0, length)
	if length + SLOPE_TOL >= w:
		var step: float = (run[0]["b"] - run[0]["a"]).length() / 2.0  # the middle of a face or the joint between two
		var snapped: float = roundf(clampf(want, w / 2.0, length - w / 2.0) / step) * step
		s = snapped if snapped >= w / 2.0 - SLOPE_TOL and snapped <= length - w / 2.0 + SLOPE_TOL else clampf(want, w / 2.0, length - w / 2.0)
	var at := start + t * s
	at = Vector2(roundf(at.x * 64.0), roundf(at.y * 64.0)) / 64.0
	res["at"] = at
	res["out"] = Vector2i(floori(at.x), floori(at.y))
	if length + SLOPE_TOL < w:
		res["why"] = "the slope must be a straight face as wide as the barrel"
		return res
	var poly := out_polygon(at, angle, w, h)
	var lo := Vector2i(floori(poly[0].x), floori(poly[0].y))
	var hi := lo
	for v in poly:
		lo = lo.min(Vector2i(floori(v.x), floori(v.y)))
		hi = hi.max(Vector2i(floori(v.x), floori(v.y)))
	if not (grid.in_bounds(lo) and grid.in_bounds(hi)):
		res["why"] = "the barrel must stick out into space"
		return res
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if (grid.get_tile(c) != "" and polys_overlap(_cell_poly(grid, c), poly)) or (comps.any_at(c) >= 0 and polys_overlap(_cell_square(c), poly)):
				res["why"] = "the barrel must stick out into space"
				return res
	for uid in comps.instances:
		var o: Dictionary = comps.instances[uid]
		if is_angled(o) and not o["out_cells"].is_empty() and polys_overlap(out_polygon(o["out_at"], float(o["angle"]), float(comps.by_id[o["id"]]["mount"]["outside"][0]), float(comps.by_id[o["id"]]["mount"]["outside"][1])), poly):
			res["why"] = "the barrel must stick out into space"
			return res
	var out_cells := slope_out_cells(grid, at, angle, w, h)
	if out_cells.is_empty():
		res["why"] = "the barrel must stick out into space"
		return res
	# the faces under the barrel, then the wall behind them along the barrel's middle line down to the floor
	var link: Array[Vector2i] = []
	var from := 0.0
	for f in run:
		var to: float = from + (f["b"] - f["a"]).length()
		if minf(to, s + w / 2.0) - maxf(from, s - w / 2.0) > 0.05 and not link.has(f["cell"]):
			link.append(f["cell"])
		from = to
	var reach := -1.0  # how far along the barrel's middle line the first free floor is
	var depth := 0
	var seen := {}
	for k in int(MAX_DEPTH / 0.1):
		var q := at - n * (0.05 + 0.1 * k)
		var c := Vector2i(floori(q.x), floori(q.y))
		if seen.has(c):
			continue
		seen[c] = true
		var id: String = grid.get_tile(c)
		if id != "" and grid.tile_flag(id, "solid") and not grid.tile_flag(id, "door"):
			depth += 1
			if not link.has(c):
				link.append(c)
		elif comps.free_floor(grid, c):
			reach = 0.05 + 0.1 * k
			break
		else:
			break
	if reach < 0.0:
		res["why"] = "needs free floor behind the slope"
		return res
	# the breech: the whole-cell block of free floor nearest the middle line, a little way behind the face (the nearest quarter turn)
	var quarter := floori(angle / 90.0)
	var turns: Array[int] = [posmod(quarter, 4), posmod(quarter + 1, 4)]  # a 45 degree slope tries both neighbouring quarter turns
	if angle - quarter * 90.0 < 44.0:
		turns = [posmod(quarter, 4)]
	elif angle - quarter * 90.0 > 46.0:
		turns = [posmod(quarter + 1, 4)]
	res["rot"] = turns[0]
	var best := INF
	for r in turns:
		var isz := turned(def["size"], r)
		var target := at - n * (reach + (absf(n.x) * isz.x + absf(n.y) * isz.y) / 2.0)  # where the block's middle would be if it started where the floor does
		for y0 in range(floori(target.y - isz.y / 2.0) - 3, floori(target.y - isz.y / 2.0) + 5):
			for x0 in range(floori(target.x - isz.x / 2.0) - 3, floori(target.x - isz.x / 2.0) + 5):
				var middle := Vector2(x0, y0) + Vector2(isz) / 2.0
				var score := middle.distance_to(target)
				if score >= best - 1e-9 or (at - middle).dot(n) <= 0.0:
					continue
				var cells := rect_cells(Rect2i(x0, y0, isz.x, isz.y))
				if cells.all(func(c): return comps.free_floor(grid, c)):
					best = score
					res.merge({"rot": r, "anchor": Vector2i(x0, y0), "depth": depth, "cells": cells, "out_cells": out_cells, "link": link}, true)
	if best < INF:
		return res
	res["why"] = "needs free floor behind the slope"
	return res


## Stand-in for the placed components while migrating a part: `own` cells count as free floor.
class _Placed extends RefCounted:
	var _comps
	var _own: Dictionary

	func _init(comps, own: Dictionary) -> void:
		_comps = comps
		_own = own

	func any_at(c: Vector2i) -> int:
		return _comps.any_at(c)

	func free_floor(grid, c: Vector2i) -> bool:
		return _own.has(c) or _comps.free_floor(grid, c)
