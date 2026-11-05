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
		"fold":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-s, -s), c + Vector2(s * 0.4, -s), c + Vector2(s, -s * 0.4), c + Vector2(s, s), c + Vector2(-s, s), c + Vector2(-s, -s)]), col, 2.0)
			canvas.draw_line(c + Vector2(s * 0.4, -s), c + Vector2(s * 0.4, -s * 0.4), col, 2.0)
			canvas.draw_line(c + Vector2(s * 0.4, -s * 0.4), c + Vector2(s, -s * 0.4), col, 2.0)
		"eye":
			canvas.draw_arc(c + Vector2(0, s * 0.6), s * 1.1, -PI * 0.8, -PI * 0.2, 8, col, 2.0, true)
			canvas.draw_arc(c + Vector2(0, -s * 0.6), s * 1.1, PI * 0.2, PI * 0.8, 8, col, 2.0, true)
			canvas.draw_circle(c, s * 0.35, col)
		"fang":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s), c + Vector2(s * 0.7, -s), c + Vector2(0, s)]), col)
		"spark":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(s * 0.4, -s), c + Vector2(-s * 0.4, 0), c + Vector2(s * 0.4, 0), c + Vector2(-s * 0.4, s)]), col, 2.5)
		"shell":
			for k in 3:
				canvas.draw_arc(c + Vector2(0, s * 0.6), s * (0.4 + 0.35 * float(k)), PI, TAU, 10, col, 1.8, true)
		"lamp":
			canvas.draw_circle(c + Vector2(0, s * 0.15), s * 0.7, col)
			canvas.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(0, -s), col, 2.0)
		"cairn":
			canvas.draw_rect(Rect2(c + Vector2(-s, s * 0.3), Vector2(s * 2.0, s * 0.7)), col)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.65, -s * 0.4), Vector2(s * 1.3, s * 0.6)), col)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.3, -s), Vector2(s * 0.6, s * 0.5)), col)
		"note":
			canvas.draw_circle(c + Vector2(-s * 0.3, s * 0.6), s * 0.45, col)
			canvas.draw_line(c + Vector2(s * 0.1, s * 0.6), c + Vector2(s * 0.1, -s), col, 2.0)
			canvas.draw_line(c + Vector2(s * 0.1, -s), c + Vector2(s * 0.8, -s * 0.4), col, 2.0)
		"scrap":
			canvas.draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s * 0.4, -s * 0.8), c + Vector2(s * 0.1, s * 0.3), c + Vector2(s * 0.5, -s * 0.5), c + Vector2(s, s * 0.7)]), col, 2.0)
		"tiles":
			for k in 4:
				canvas.draw_rect(Rect2(c + Vector2(-s + s * float(k % 2) * 1.05, -s + s * float(k / 2) * 1.05), Vector2(s * 0.95, s * 0.95)), col, k == 0 or k == 3)
		"blade":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.3, s), c + Vector2(-s * 0.1, -s), c + Vector2(s * 0.4, -s * 0.2), c + Vector2(s * 0.2, s)]), col)
		"quill":
			for k in 4:
				var x := -s + s * 0.66 * float(k)
				canvas.draw_line(c + Vector2(x, s), c + Vector2(x + s * 0.2, -s), col, 2.0)
		"kite":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.8, -s * 0.1), c + Vector2(0, s * 0.6), c + Vector2(-s * 0.8, -s * 0.1)]), col)
			canvas.draw_line(c + Vector2(0, s * 0.6), c + Vector2(s * 0.3, s), col, 2.0)
		"lens":
			canvas.draw_arc(c, s * 0.95, 0.0, TAU, 14, col, 2.0, true)
			canvas.draw_circle(c, s * 0.4, col)
		"pick":
			canvas.draw_line(c + Vector2(-s * 0.7, s), c + Vector2(s * 0.5, -s * 0.8), col, 2.5)
			canvas.draw_arc(c + Vector2(0, -s * 0.2), s * 0.9, PI * 1.1, PI * 1.9, 8, col, 2.5, true)
		"cloud":
			canvas.draw_circle(c + Vector2(-s * 0.5, s * 0.2), s * 0.5, col)
			canvas.draw_circle(c + Vector2(s * 0.2, -s * 0.2), s * 0.65, col)
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.5, s * 0.2), Vector2(s * 1.4, s * 0.5)), col)
		"feather":
			canvas.draw_line(c + Vector2(-s * 0.8, s), c + Vector2(s * 0.6, -s), col, 2.0)
			for k in 3:
				var q := c + Vector2(-s * 0.4 + s * 0.35 * float(k), s * 0.5 - s * 0.55 * float(k))
				canvas.draw_line(q, q + Vector2(s * 0.5, s * 0.15), col, 1.5)
		"claw":
			canvas.draw_arc(c + Vector2(s * 0.4, 0), s * 0.9, PI * 0.55, PI * 1.45, 10, col, 3.0, true)
			canvas.draw_arc(c + Vector2(-s * 0.4, 0), s * 0.9, -PI * 0.45, PI * 0.45, 10, col, 3.0, true)
		"mirror":
			canvas.draw_rect(Rect2(c + Vector2(-s * 0.8, -s), Vector2(s * 1.6, s * 2.0)), col, false, 2.0)
			canvas.draw_line(c + Vector2(-s * 0.2, s * 0.7), c + Vector2(s * 0.5, -s * 0.5), col, 1.5)
		"magnet":
			canvas.draw_arc(c + Vector2(0, -s * 0.1), s * 0.7, PI, TAU, 10, col, 3.0, true)
			canvas.draw_line(c + Vector2(-s * 0.7, -s * 0.1), c + Vector2(-s * 0.7, s * 0.8), col, 3.0)
			canvas.draw_line(c + Vector2(s * 0.7, -s * 0.1), c + Vector2(s * 0.7, s * 0.8), col, 3.0)
		_:
			canvas.draw_circle(c, s * 0.6, col)
