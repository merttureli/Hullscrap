extends RefCounted
## A race's or faction's emblem (data/ship_styles.json, data/enemy_tables.json `style.emblem`): a glyph made of a few primitives in a unit box
## (poly: a polygon, filled or an outline; circle [cx, cy, r]; line: a polyline of x, y pairs), drawn in one colour into any rect.
## Drawing only: the contact card, the map marker, the enemy panel and the decal on the hull use it.


## Draw `emblem` ({prims: [...]}) into `r` in colour `col`; `width` is the outline width in px (0: a twelfth of the rect).
static func draw(cv: CanvasItem, emblem: Dictionary, r: Rect2, col: Color, width := 0.0) -> void:
	var w := width if width > 0.0 else maxf(1.0, minf(r.size.x, r.size.y) / 12.0)
	for prim in emblem.get("prims", []):
		var fill: bool = bool(prim.get("fill", false))
		if prim.has("poly"):
			var pts := _pts(prim["poly"], r)
			if fill:
				cv.draw_colored_polygon(pts, col)
			else:
				pts.append(pts[0])
				cv.draw_polyline(pts, col, w, true)
		elif prim.has("circle"):
			var c: Array = prim["circle"]
			var centre := r.position + Vector2(float(c[0]) * r.size.x, float(c[1]) * r.size.y)
			var rad := float(c[2]) * minf(r.size.x, r.size.y)
			if fill:
				cv.draw_circle(centre, rad, col)
			else:
				cv.draw_arc(centre, rad, 0.0, TAU, 24, col, w, true)
		elif prim.has("line"):
			var flat: Array = prim["line"]
			var pairs: Array = []
			for i in range(0, flat.size() - 1, 2):
				pairs.append([flat[i], flat[i + 1]])
			cv.draw_polyline(_pts(pairs, r), col, w, true)


static func _pts(pairs: Array, r: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pairs:
		out.append(r.position + Vector2(float(p[0]) * r.size.x, float(p[1]) * r.size.y))
	return out
