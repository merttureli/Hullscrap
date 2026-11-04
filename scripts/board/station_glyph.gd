extends RefCounted
## The signage glyph of a race (data/station_races.json skin.glyph), drawn small with shapes: the mark on a sign and a poster. `c` the middle, `s` the size.


static func draw(canvas: CanvasItem, kind: String, c: Vector2, s: float, col: Color) -> void:
	match kind:
		"chevron":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-s, -s * 0.5), c + Vector2(0, s * 0.7), c + Vector2(s, -s * 0.5)]), col, 2.0)
		"block":
			canvas.draw_rect(Rect2(c - Vector2(s, s) * 0.8, Vector2(s, s) * 1.6), col)
		"flame":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, s * 0.2), c + Vector2(s * 0.3, s), c + Vector2(-s * 0.4, s), c + Vector2(-s * 0.7, s * 0.1), c + Vector2(-s * 0.1, -s * 0.3)]), col)
		"ring":
			canvas.draw_arc(c, s * 0.8, 0.0, TAU, 16, col, 2.0, true)
		"hex":
			var pts := PackedVector2Array()
			for q in 7:
				pts.append(c + Vector2.from_angle(TAU * float(q) / 6.0) * s)
			canvas.draw_polyline(pts, col, 2.0)
		"drop":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, s * 0.3), c + Vector2(0, s), c + Vector2(-s * 0.7, s * 0.3)]), col)
		"leaf":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s * 0.2, -s * 0.8), c + Vector2(s, -s * 0.5), c + Vector2(s * 0.3, s * 0.7)]), col)
		"gear":
			canvas.draw_arc(c, s * 0.7, 0.0, TAU, 12, col, 3.0, true)
			for k in 6:
				var a := TAU * float(k) / 6.0
				canvas.draw_line(c + Vector2.from_angle(a) * s * 0.7, c + Vector2.from_angle(a) * s * 1.05, col, 2.0)
		"bar":
			canvas.draw_rect(Rect2(c + Vector2(-s, -s * 0.25), Vector2(s * 2.0, s * 0.5)), col)
		"diamond":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.7, 0), c + Vector2(0, s), c + Vector2(-s * 0.7, 0)]), col)
		_:
			canvas.draw_circle(c, s * 0.6, col)
