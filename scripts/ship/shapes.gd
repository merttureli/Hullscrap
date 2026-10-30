extends RefCounted
## Cell shapes and the pieces built from them (data/shapes.json, docs/CONTENT.md 4d). A shaped cell
## holds a convex polygon of its unit square in cell-local coordinates (x right, y down, 0..1), a
## rotation in quarter turns clockwise about the cell centre and a mirror (x flipped before turning).
## Every polygon is wound the same way (positive shoelace area, clockwise on screen), so outward
## edge normals are (e.y, -e.x). Pure maths and data: no nodes, no drawing.

const PATH := "res://data/shapes.json"
const FULL := "full"
const EPS := 1e-9

static var _data := {}
static var _polys := {}  # "shape|rot|mirror" -> PackedVector2Array
static var _normals := {}  # same key -> PackedVector2Array: outward unit normal of edge i (p[i] -> p[i+1])


static func _load() -> void:
	if not _data.is_empty():
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert(d is Dictionary and d.get("shapes") is Dictionary and d.get("pieces") is Dictionary, "bad shape data: " + PATH)
	_data = d


static func has_shape(id: String) -> bool:
	_load()
	return _data["shapes"].has(id)


static func has_piece(id: String) -> bool:
	_load()
	return _data["pieces"].has(id)


static func shape_ids() -> Array:
	_load()
	return _data["shapes"].keys()


static func piece_ids() -> Array:
	_load()
	return _data["pieces"].keys()


## The stored form of a cell's shape: {"shape", "rot", "mirror"}; {} for a full square (or an unknown shape).
static func norm(sd: Dictionary) -> Dictionary:
	var id := str(sd.get("shape", FULL))
	if id == FULL or not has_shape(id):
		return {}
	return {"shape": id, "rot": posmod(int(sd.get("rot", 0)), 4), "mirror": bool(sd.get("mirror", false))}


## Solid polygon of `shape` after the mirror and `rot` quarter turns clockwise, in cell-local coordinates.
static func cell_polygon(shape: String, rot := 0, mirror := false) -> PackedVector2Array:
	var r := posmod(rot, 4)
	var key := "%s|%d|%d" % [shape, r, 1 if mirror else 0]
	if _polys.has(key):
		return _polys[key]
	_load()
	var base: Array = _data["shapes"].get(shape, _data["shapes"][FULL])
	var pts := PackedVector2Array()
	for p in base:
		var v := Vector2(float(p[0]), float(p[1]))
		if mirror:
			v.x = 1.0 - v.x
		for k in r:
			v = Vector2(1.0 - v.y, v.x)  # a quarter turn clockwise about (0.5, 0.5)
		pts.append(v)
	if mirror:
		pts.reverse()  # a mirror flips the winding
	_polys[key] = pts
	var nrm := PackedVector2Array()
	for i in pts.size():
		var e: Vector2 = pts[(i + 1) % pts.size()] - pts[i]
		nrm.append(Vector2(e.y, -e.x).normalized())
	_normals[key] = nrm
	return pts


## Outward unit normals of the edges of cell_polygon(shape, rot, mirror), edge i running p[i] -> p[i+1].
static func edge_normals(shape: String, rot := 0, mirror := false) -> PackedVector2Array:
	cell_polygon(shape, rot, mirror)
	return _normals["%s|%d|%d" % [shape, posmod(rot, 4), 1 if mirror else 0]]


static func polygon_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var a: Vector2 = p[i]
		var b: Vector2 = p[(i + 1) % p.size()]
		s += a.x * b.y - b.x * a.y
	return s / 2.0


## Solid area of `shape` in cells (rotation and mirror do not change it): full 1, tri 0.5.
static func area(shape: String) -> float:
	return polygon_area(cell_polygon(shape))


## Area of a stored shape dictionary ({} = a full cell = 1).
static func area_of(sd: Dictionary) -> float:
	return area(str(sd["shape"])) if not sd.is_empty() else 1.0


## Centroid of the solid part of a shape, in cell-local coordinates.
static func centroid(shape: String, rot := 0, mirror := false) -> Vector2:
	var p := cell_polygon(shape, rot, mirror)
	var a2 := 0.0
	var c := Vector2.ZERO
	for i in p.size():
		var u: Vector2 = p[i]
		var v: Vector2 = p[(i + 1) % p.size()]
		var cr := u.x * v.y - v.x * u.y
		a2 += cr
		c += (u + v) * cr
	return c / (3.0 * a2) if absf(a2) > EPS else Vector2(0.5, 0.5)


## Footprint of piece `piece` after `rot` quarter turns (odd turns swap width and height).
static func piece_size(piece: String, rot := 0) -> Vector2i:
	_load()
	var w := 1
	var h := 1
	for c in _data["pieces"].get(piece, []):
		w = maxi(w, int(c["off"][0]) + 1)
		h = maxi(h, int(c["off"][1]) + 1)
	return Vector2i(h, w) if posmod(rot, 2) == 1 else Vector2i(w, h)


## The cells of piece `piece` placed with the top-left cell of its turned footprint on `anchor`: the
## piece is mirrored (x flipped) and then turned `rot` quarter turns clockwise, like a component. Each
## entry is {cell, shape, rot, mirror}: the cell's own rotation and mirror are the piece's. [] for an unknown piece.
static func piece_cells(piece: String, anchor: Vector2i, rot := 0, mirror := false) -> Array:
	_load()
	var list: Array = _data["pieces"].get(piece, [])
	var w := 1
	var h := 1
	for c in list:
		w = maxi(w, int(c["off"][0]) + 1)
		h = maxi(h, int(c["off"][1]) + 1)
	var r := posmod(rot, 4)
	var out := []
	for c in list:
		var p := Vector2i(int(c["off"][0]), int(c["off"][1]))
		if mirror:
			p.x = w - 1 - p.x
		var bw := w
		var bh := h
		for k in r:
			p = Vector2i(bh - 1 - p.y, p.x)
			var t := bw
			bw = bh
			bh = t
		out.append({"cell": anchor + p, "shape": str(c["shape"]), "rot": r, "mirror": mirror})
	return out


## Where the segment a -> b meets the convex shape of `sd` ({shape, rot, mirror}) on a cell, a and b
## in that cell's local coordinates: {"t": fraction of the segment where it enters (0 when it starts
## inside), "n": the outward unit normal of the edge it enters through (zero when it starts inside)};
## {} when the segment misses the solid part, only touches it, or leaves it where it starts.
static func segment_hit(sd: Dictionary, a: Vector2, b: Vector2) -> Dictionary:
	var shape := str(sd["shape"])
	var rot := int(sd.get("rot", 0))
	var mirror := bool(sd.get("mirror", false))
	var poly := cell_polygon(shape, rot, mirror)
	var nrm := edge_normals(shape, rot, mirror)
	var d := b - a
	var t_in := 0.0
	var t_out := 1.0
	var n_in := Vector2.ZERO
	for i in poly.size():
		var nv: Vector2 = nrm[i]
		var denom := nv.dot(d)
		var dist := nv.dot(a - poly[i])  # > 0: a lies outside this edge
		if absf(denom) < EPS:
			if dist > EPS:
				return {}
			continue
		var t := -dist / denom
		if denom < 0.0:
			if t > t_in:
				t_in = t
				n_in = nv
		else:
			t_out = minf(t_out, t)
		if t_out - t_in <= EPS:
			return {}
	return {"t": t_in, "n": n_in}
